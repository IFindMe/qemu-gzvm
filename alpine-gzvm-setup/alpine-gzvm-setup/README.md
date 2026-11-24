# Alpine Linux ARM64 on Android with QEMU-GZVM

This guide documents installing and running Alpine Linux 3.24.4 ARM64 on Android using Termux and QEMU-GZVM.

It covers both the initial Alpine installation and subsequent booting from the installed virtual disk, including an important kernel synchronization requirement.

## 1. Configuration

| Component | Configuration |
|---|---|
| Host | Android / Termux |
| Guest architecture | ARM64 / AArch64 |
| QEMU | QEMU-GZVM 26.8.4 package (binary reports 26.8.1) |
| Accelerator | `gzvm` |
| Machine | `virt`, GICv3 |
| vCPUs | 8 |
| RAM | 2048 MiB |
| Virtual disk | 32 GiB QCOW2, dynamically allocated |
| Distribution | Alpine Linux Virtual 3.24.4 ARM64 |
| Storage | VirtIO block |
| Networking | QEMU user networking |
| SSH forwarding | Host TCP 2222 → Guest TCP 22 |

All files are kept under `~/alpine`.

## 2. Install Termux packages

Run in Termux:

```sh
pkg update
pkg install -y tar xorriso qemu-utils openssh
```

Packages:

- `tar`: Extract QEMU archives.
- `xorriso`: Extract files from the Alpine ISO.
- `qemu-utils`: Provides `qemu-img`.
- `openssh`: Provides SSH and SCP for guest access and kernel synchronization.

## 3. Create the working directory

```sh
mkdir -p ~/alpine
cd ~/alpine
```

Place the following downloaded files in this directory:

```text
alpine-virt-3.24.4-aarch64.iso
qemu-gzvm-v26.8.4-aarch64.tar.gz
jniLibs-v26.8.4-arm64-v8a.tar.gz
```

## 4. Extract QEMU-GZVM and Android libraries

```sh
cd ~/alpine

mkdir -p qemu-gzvm

tar -xzf qemu-gzvm-v26.8.4-aarch64.tar.gz -C qemu-gzvm
tar -xzf jniLibs-v26.8.4-arm64-v8a.tar.gz -C qemu-gzvm

cp -af qemu-gzvm/arm64-v8a/*.so qemu-gzvm/qemu-gzvm/lib/
```

Expected directory structure:

```text
qemu-gzvm/
├── arm64-v8a/
│   └── *.so
└── qemu-gzvm/
    ├── qemu-system-aarch64
    ├── lib/
    └── fw/
        └── efi-virtio.rom
```

Verify QEMU:

```sh
QEMU="$PWD/qemu-gzvm/qemu-gzvm/qemu-system-aarch64"

export LD_LIBRARY_PATH="$PWD/qemu-gzvm/qemu-gzvm/lib:$PWD/qemu-gzvm/arm64-v8a"

"$QEMU" --version
"$QEMU" -accel help
```

The accelerator list should include `gzvm`.

## 5. Create the virtual disk

```sh
cd ~/alpine
qemu-img create -f qcow2 alpine.qcow2 32G
```

QCOW2 is thin-provisioned. The image initially occupies much less than 32 GiB and grows as guest data is written.

Ensure sufficient free Android storage is available.

## 6. Extract the initial Alpine boot files

The initial live installer requires a kernel and initramfs.

Extract them from the Alpine ISO:

```sh
cd ~/alpine

mkdir -p boot

xorriso -osirrox on \
  -indev alpine-virt-3.24.4-aarch64.iso \
  -extract /boot boot
```

Verify:

```sh
test -f boot/vmlinuz-virt
test -f boot/initramfs-virt
test -f boot/modloop-virt
```

**Important:** These files belong to the ISO's kernel version. They are suitable for starting the live installer, but must not automatically be treated as the permanent boot files after installing Alpine.

## 7. Install Alpine Linux

Save the initial installer launcher as `run-alpine-install.sh`.

The installer launcher must:

- Use `boot/vmlinuz-virt` and `boot/initramfs-virt`.
- Attach `alpine.qcow2` as the first VirtIO block device.
- Attach the Alpine ISO as the second VirtIO block device.
- Enable GZVM acceleration.
- Configure 8 vCPUs and 2048 MiB RAM.
- Forward host TCP port 2222 to guest TCP port 22.

Start the installer:

```sh
cd ~/alpine
chmod +x run-alpine-install.sh
./run-alpine-install.sh
```

At the Alpine prompt:

```sh
setup-alpine
```

For a standard installation, select:

| Setting | Selection |
|---|---|
| Target disk | `vda` |
| Installation mode | `sys` |
| Filesystem | `ext4` |

**Verify the target disk before confirming erasure.** The virtual disk is `vda`; the installer ISO is `vdb`.

When installation finishes:

```sh
poweroff
```

## 8. Booting the installed Alpine system

This is a separate boot stage from the live installer.

The installed Alpine system has its own kernel package, installed by `apk`:

```sh
apk add linux-virt
```

The installed kernel and modules are stored inside the virtual disk:

```text
/boot/
├── vmlinuz-virt
├── initramfs-virt
├── System.map-*
├── config-*
└── dtbs-virt/

/lib/modules/
└── <kernel-version>/
```

QEMU, however, boots files from the Android/Termux filesystem. It does not automatically use the kernel installed inside the guest.

Therefore, the installed kernel and initramfs must be copied from Alpine to Termux.

### 8.1 Enable SSH in Alpine

Inside the installed Alpine VM:

```sh
rc-update add sshd default
rc-service sshd start
```

Ensure the root account has a password if using password authentication.

### 8.2 Copy the installed kernel to Termux

Open another Termux session while Alpine is running.

From Termux:

```sh
cd ~/alpine

scp -P 2222 root@127.0.0.1:/boot/vmlinuz-virt boot/vmlinuz-virt.new

scp -P 2222 root@127.0.0.1:/boot/initramfs-virt boot/initramfs-virt.new
```

Enter the Alpine root password when prompted.

### 8.3 Verify and replace the boot files

Verify both files were transferred:

```sh
ls -lh boot/*.new
```

Only replace the existing files after confirming both transfers succeeded.

Keep backups:

```sh
cp boot/vmlinuz-virt boot/vmlinuz-virt.bak
cp boot/initramfs-virt boot/initramfs-virt.bak
```

Replace:

```sh
mv boot/vmlinuz-virt.new boot/vmlinuz-virt
mv boot/initramfs-virt.new boot/initramfs-virt
```

The Termux boot files now correspond to the installed Alpine kernel.

### 8.4 Configure the installed-system launcher

The installed-system launcher must:

- Boot `boot/vmlinuz-virt`.
- Boot `boot/initramfs-virt`.
- Attach only `alpine.qcow2`.
- Not attach the installer ISO.
- Pass the installed root filesystem UUID to the kernel.

Example kernel arguments:

```text
root=UUID=2400f7ad-8f71-45c3-8b2f-2c7ac1ea066b
modules=virtio_blk,sd-mod,ext4
rootfstype=ext4
rootwait
rw
console=ttyAMA0,38400
```

Example QEMU boot configuration:

```sh
-kernel boot/vmlinuz-virt \
-initrd boot/initramfs-virt \
-append "root=UUID=2400f7ad-8f71-45c3-8b2f-2c7ac1ea066b modules=virtio_blk,sd-mod,ext4 rootfstype=ext4 rootwait rw console=ttyAMA0,38400" \
-drive if=none,id=disk0,file=alpine.qcow2,format=qcow2 \
-device virtio-blk-pci,drive=disk0
```

Save this configuration in `run-alpine.sh`.

Start the installed system:

```sh
cd ~/alpine
chmod +x run-alpine.sh
./run-alpine.sh
```

## 9. Kernel synchronization and upgrades

**Important: Keep the Termux boot kernel synchronized with Alpine's installed kernel.**

This issue was encountered during the original installation.

The initial ISO supplied kernel `6.18.60`, while Alpine later installed `linux-virt` with kernel `6.18.65`.

The resulting configuration was:

| Component | Version |
|---|---|
| Termux QEMU boot kernel | 6.18.60 |
| Alpine installed kernel | 6.18.65 |
| Alpine kernel modules | 6.18.65 |

This caused `modprobe` to fail because it searched for modules under the running kernel's version:

```text
modprobe: FATAL: Module nf_tables not found in directory /lib/modules/6.18.60-0-virt
```

The modules actually existed under:

```text
/lib/modules/6.18.65-0-virt/
```

### 9.1 Verify kernel consistency

Inside Alpine:

```sh
uname -r
ls /lib/modules/
```

Both must correspond to the same kernel version.

Check the installed kernel package:

```sh
apk info -W /boot/vmlinuz-virt
```

### 9.2 Synchronize after kernel upgrades

Whenever `linux-virt` is upgraded:

1. Start Alpine.
2. Ensure SSH is running.
3. Copy the new kernel and initramfs to Termux using SCP.
4. Verify both transferred successfully.
5. Shut down Alpine.
6. Replace the host-side boot files.
7. Start Alpine again.
8. Verify the running kernel version.

The transfer commands are:

```sh
scp -P 2222 root@127.0.0.1:/boot/vmlinuz-virt boot/vmlinuz-virt.new

scp -P 2222 root@127.0.0.1:/boot/initramfs-virt boot/initramfs-virt.new
```

Do not replace the host boot files while the VM is running.

**The host-side kernel and initramfs are independent files. Updating Alpine's kernel package does not automatically update the copies used by QEMU.**

## 10. Docker configuration

Docker requires Linux kernel facilities for container isolation and networking.

Install Docker:

```sh
apk add docker
```

Enable it at startup:

```sh
rc-update add docker default
```

Start the daemon:

```sh
rc-service docker start
```

### 10.1 Required networking modules

For the nftables-based iptables backend:

```sh
modprobe nf_tables
modprobe nf_nat
modprobe nft_chain_nat
modprobe br_netfilter
modprobe ip_tables
modprobe iptable_nat
```

Verify:

```sh
iptables --version
iptables -t nat -L
```

Expected iptables backend:

```text
iptables v1.8.13 (nf_tables)
```

Restart Docker:

```sh
rc-service docker restart
docker info
docker ps
```

Test container execution:

```sh
docker run --rm hello-world
```

If Docker fails:

```sh
tail -n 80 /var/log/docker.log
```

Note that successful kernel module loading does not by itself guarantee that all Docker networking and container runtime features are supported by the guest kernel.

## 11. Networking and SSH

QEMU user networking uses the following default guest network configuration:

| Setting | Address |
|---|---|
| Guest IP | `10.0.2.15` |
| Gateway | `10.0.2.2` |
| DNS | `10.0.2.3` |

SSH from Termux:

```sh
ssh -p 2222 root@127.0.0.1
```

The QEMU host forwarding rule is:

```text
tcp:127.0.0.1:2222-:22
```

The guest must have SSH installed, configured, and running.

## 12. Troubleshooting

### `failed to find romfile "efi-virtio.rom"`

Check:

```sh
ls -l qemu-gzvm/qemu-gzvm/fw/efi-virtio.rom
```

Ensure QEMU receives the correct firmware directory using `-L`.

### `library "libz.so.1" not found`

Check the JNI libraries:

```sh
ls -l qemu-gzvm/qemu-gzvm/lib/libz.so
```

Ensure `LD_LIBRARY_PATH` includes both QEMU's library directory and the extracted Android libraries.

### `virtio-scsi-pci is not a valid device model name`

This QEMU build does not include that device model.

Use:

```sh
-device virtio-blk-pci
```

### `GZVM_SET_USER_MEMORY_REGION failed: Bad address (errno=14)`

This warning appeared during testing. Its cause and whether it affects all guest memory regions have not been established.

Record whether the VM boots and operates successfully; do not assume the warning is harmless.

### `modprobe: FATAL: Module not found`

Check:

```sh
uname -r
ls /lib/modules/
```

If the versions differ, synchronize the kernel and initramfs as described in Section 9.

### `iptables: Failed to initialize nft: Protocol not supported`

Check the running kernel version and available modules.

```sh
modprobe nf_tables
modprobe nft_chain_nat
iptables --version
```

If modules cannot be found, first investigate a kernel/modules version mismatch.

## 13. Directory layout

Expected Termux directory structure:

```text
~/alpine/
├── README.md
├── run-alpine-install.sh
├── run-alpine.sh
├── alpine-virt-3.24.4-aarch64.iso
├── alpine.qcow2
├── boot/
│   ├── vmlinuz-virt
│   ├── initramfs-virt
│   ├── modloop-virt
│   ├── vmlinuz-virt.bak
│   └── initramfs-virt.bak
├── qemu-gzvm-v26.8.4-aarch64.tar.gz
├── jniLibs-v26.8.4-arm64-v8a.tar.gz
└── qemu-gzvm/
    ├── arm64-v8a/
    └── qemu-gzvm/
        ├── qemu-system-aarch64
        ├── lib/
        └── fw/
            └── efi-virtio.rom
```




# Load the VirtIO 9P module at boot
grep -qxF '9pnet_virtio' /etc/modules 2>/dev/null ||
    echo '9pnet_virtio' >> /etc/modules

rc-update add modules boot

# Create mount point
mkdir -p /mnt/host

# Add permanent filesystem entry
grep -qE '^[[:space:]]*hostshare[[:space:]]+/mnt/host[[:space:]]' /etc/fstab ||
    echo 'hostshare /mnt/host 9p trans=virtio,version=9p2000.L 0 0' >> /etc/fstab

# Test
modprobe 9pnet_virtio
mount -a

## 14. Key operational rules

1. Use the Alpine ISO kernel only for the initial live installation.
2. Use the installed Alpine kernel and initramfs for normal VM operation.
3. Keep the Termux kernel and initramfs synchronized with Alpine's installed kernel package.
4. Verify `uname -r` against `/lib/modules/` after kernel changes.
5. Keep a backup of the previous working boot files.
6. Do not attach the installer ISO during normal installed-system boot.
7. Do not assume Docker networking works until the required kernel features have been verified.