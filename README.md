# qemu-gzvm

QEMU `aarch64-softmmu` for Android, accelerated by the MediaTek GenieZone
hypervisor (`gzvm`) through `/dev/gzvm`. The tree is a trimmed QEMU fork: it
keeps the `virt` machine, the `gzvm` accelerator, virtio devices, virgl/OpenGL,
AAudio and a small set of block/network backends.

## What is enabled

- Target: `aarch64-softmmu`, machine `virt`, accelerator `gzvm`
- CPU: `host` (the only AArch64 CPU model registered by this fork)
- Virtio: `virtio-blk-pci`, `virtio-net-pci`, `virtio-gpu-gl-pci`,
  `virtio-keyboard-pci`, `virtio-tablet-pci`, `virtio-snd-pci`
- Graphics: virglrenderer + OpenGL, AGL display backend (Android surface)
- Audio: AAudio
- Networking: user-mode NAT (`-netdev user`, slirp) and TAP (`-netdev tap`)
- Disks: raw images only (`-drive ...,format=raw`)
- Libraries: glib, pixman, libffi, pcre2, libucontext, liburing, libepoxy,
  virglrenderer (all built from source by `build.sh`)

## Limitations

- User-mode networking supports IPv4/IPv6, DHCP, TFTP, `hostfwd` and
  `guestfwd`. SMB (`smb=`) needs an `smbd` binary on the device and is not
  usable in practice.
- Only the `raw` block format exists. There is no `qemu-img` and no qcow2/vmdk.
  Convert images with an external `qemu-img` before use.
- There is no USB, 9p/virtfs, TPM, vhost, guest agent or loadable modules.
- `/dev/gzvm` and root privileges are required on the device.

## Requirements

Build host: Linux x86_64.

- Android NDK r30-beta2 (`ANDROID_NDK_ROOT`)
- `ar cmake curl git make meson ninja patchelf perl pkg-config python3 tar zstd`
- Network access (the script downloads Termux `.deb` packages and sources)

## Build locally

```sh
export ANDROID_NDK_ROOT=/path/to/android-ndk-r30-beta2
export alsDir=/path/to/android-app     # must contain app/src/main
./build.sh
```

`alsDir` is the Android project that receives the packaged JNI libraries. Only
`$alsDir/app/src/main` needs to exist, so a stub directory is enough for a
standalone build:

```sh
mkdir -p /tmp/als/app/src/main
ANDROID_NDK_ROOT=/path/to/android-ndk-r30-beta2 alsDir=/tmp/als ./build.sh
```

The script fetches Termux aarch64 packages (libslirp, gnutls, zstd, png, …) and
unpacks them into `build/sysroot`. Dependency builds are skipped when their
outputs already exist; the QEMU build directory is recreated on every run.

## Build and release with GitHub Actions

Workflow: `.github/workflows/build.yml`.

- Push to `main` → build, upload the archives as workflow artifacts.
- Push a `v*` tag → build, upload artifacts, and create a GitHub Release with
  the compiled tarballs attached.
- Publish a release manually → build and attach the compiled tarballs to it.
- Manual: **Actions → Build and Release → Run workflow**. Set `release` to create
  a release and optionally provide a `version` tag.

```sh
git tag v26.8.2
git push origin v26.8.2
```

Release assets are `qemu-gzvm-<version>-aarch64.tar.gz` and
`jniLibs-<version>-arm64-v8a.tar.gz`. GitHub also always lists auto-generated
"Source code (zip/tar.gz)" links; those are not the build output. The tag must
point to a commit that contains this workflow, otherwise its run uses the older
workflow from that commit.

The workflow downloads NDK r30-beta2, installs Meson 1.5.0, pre-populates
`python/wheels` (needed because QEMU is configured with `--disable-download`),
creates a stub `alsDir`, runs `./build.sh`, and packages the result.

## Outputs

```
build/out/qemu-gzvm/
├── qemu-system-aarch64
├── libqemu-gzvm.so
├── fw/efi-virtio.rom
└── lib/*.so
```

The JNI libraries are copied to:

```
$alsDir/app/src/main/jniLibs/arm64-v8a/
├── libqemu-gzvm.so
└── ...runtime dependencies...
```

`qemu-system-aarch64` and `libqemu-gzvm.so` are patched with
`RPATH=$ORIGIN/lib`, so keep the `lib/` directory next to them.

## Run from the command line

Copy the whole `build/out/qemu-gzvm` directory to the device and run it as root:

```sh
adb push build/out/qemu-gzvm /data/local/tmp/qemu-gzvm
adb shell
cd /data/local/tmp/qemu-gzvm
chmod +x qemu-system-aarch64

./qemu-system-aarch64 \
  -L fw \
  -M virt -accel gzvm -cpu host \
  -smp 4 -m 2048 \
  -kernel Image \
  -append "console=ttyAMA0 root=/dev/vda rw" \
  -drive file=rootfs.img,format=raw,if=virtio \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=n0 \
  -nographic
```

Notes:

- `-cpu host` is the default for `-M virt` in this fork; it is the only CPU
  model available.
- `rootfs.img` and `Image` must be raw/plain files on the device.
- For a UEFI guest, pass your own firmware with `-bios QEMU_EFI.fd`; the package
  only ships `fw/efi-virtio.rom` (a virtio option ROM).
- `-L fw` points QEMU at the bundled `fw/` directory so it can find
  `efi-virtio.rom`. Without it, `virtio-net-pci` fails with
  `failed to find romfile "efi-virtio.rom"`. If you boot with `-kernel` and do
  not need the NIC option ROM, you can instead append `,romfile=` to the
  device.
- Replace `-nographic` with `-display agl` when running inside the Android app
  (see below).

### Graphics and audio

```sh
./qemu-system-aarch64 \
  -L fw \
  -M virt -accel gzvm -cpu host -m 2048 \
  -device virtio-gpu-gl-pci \
  -display agl \
  -audiodev aaudio,id=snd0 \
  -device virtio-snd-pci,audiodev=snd0 \
  -device virtio-keyboard-pci -device virtio-tablet-pci \
  ...
```

`-display agl` renders into an Android `Surface` supplied by the host app via
JNI. For a headless/console guest use `-nographic` instead.

## Networking

### User-mode NAT (no host setup)

```sh
-netdev user,id=n0,hostfwd=tcp::2222-:22 \
-device virtio-net-pci,netdev=n0
```

The guest sees `10.0.2.15` with gateway/DNS at `10.0.2.2`/`10.0.2.3`, and
outgoing traffic is NATed by slirp. `hostfwd` maps host ports to guest ports;
`guestfwd` forwards guest TCP connections to a host chardev. Use
`restrict=on` to block outbound traffic, and `net=`, `host=`, `dhcpstart=`,
`dns=`, `tftp=`, `bootfile=`, `ipv6=on`, `ipv6-prefix=`, etc. for finer
control. No root or TUN/TAP device is required.

### TAP (bridged, needs root + TUN/TAP)

```sh
ip tuntap add dev tap0 mode tap
ip link set tap0 up
ip addr add 10.0.2.1/24 dev tap0
```

Then pass `-netdev tap,id=n0,ifname=tap0,script=no,downscript=no` to QEMU.
TAP gives the guest layer-2 access, but there is no built-in DHCP/NAT; provide
it on the host side if the guest needs it.

## Android JNI integration

`libqemu-gzvm.so` registers native methods on these exact Java/Kotlin classes
(see `system/jni.c`); the package name must be `sui.k.als.qemu.vm` or
`JNI_OnLoad` will fail:

```kotlin
package sui.k.als.qemu.vm

object VMNative {
    init { System.loadLibrary("qemu-gzvm") }

    external fun grantRoot(): Int
    external fun run(workDir: String, args: Array<String>, audioFd: Int): Int
    external fun pointer(x: Float, y: Float, buttons: Int)
    external fun scroll(dx: Float, dy: Float)
    external fun key(scanCode: Int, down: Boolean)
    external fun stop()
}
```

```kotlin
package sui.k.als.qemu.vm

import android.view.Surface

class AGL {
    external fun setSurface(surface: Surface?, ratio: Float)
}
```

Example (the app must call `AGL.setSurface()` before `run` when `-display agl`
is used):

```kotlin
val argv = arrayOf(
    "qemu-system-aarch64",
    "-L", "fw",
    "-M", "virt",
    "-accel", "gzvm",
    "-cpu", "host",
    "-smp", "4",
    "-m", "2048",
    "-kernel", "Image",
    "-append", "console=ttyAMA0 root=/dev/vda rw",
    "-drive", "file=rootfs.img,format=raw,if=virtio",
    "-device", "virtio-gpu-gl-pci",
    "-display", "agl"
)

VMNative.run("/data/local/tmp/qemu-gzvm", argv, -1)
```

`workDir` is the current directory used for relative paths. `audioFd` is the
AAudio input file descriptor, or `-1` when unused. For a console-only guest,
replace `-display agl` with `-nographic`.

## Troubleshooting

- `Could not access /dev/gzvm` → the GenieZone driver is missing or not
  accessible; run as root.
- `Could not configure /dev/net/tun` → TAP needs root and kernel TUN/TAP
  support; use `-netdev user` instead if you only need outbound access.
- `Could not open '...qcow2'` → only raw images are supported.
- `error while loading shared libraries` → keep the `lib/` directory next to the
  binaries (the `$ORIGIN/lib` RPATH expects it).
- `Unable to find CPU model ...` → this fork only provides `-cpu host`.
