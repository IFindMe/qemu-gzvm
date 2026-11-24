#!/data/data/com.termux/files/usr/bin/sh
# Launch the Alpine Linux ARM64 live installer with QEMU-GZVM.
# Keep this script in the same directory as alpine.qcow2, the ISO, boot/, and qemu-gzvm/.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

QEMU="$SCRIPT_DIR/qemu-gzvm/qemu-gzvm/qemu-system-aarch64"
QEMU_LIB="$SCRIPT_DIR/qemu-gzvm/qemu-gzvm/lib"
JNI_LIB="$SCRIPT_DIR/qemu-gzvm/arm64-v8a"
FIRMWARE_DIR="$SCRIPT_DIR/qemu-gzvm/qemu-gzvm/fw"

KERNEL="$SCRIPT_DIR/boot/vmlinuz-virt"
INITRAMFS="$SCRIPT_DIR/boot/initramfs-virt"
ISO="$SCRIPT_DIR/alpine-virt-3.24.4-aarch64.iso"
DISK="$SCRIPT_DIR/alpine.qcow2"

for file in "$QEMU" "$KERNEL" "$INITRAMFS" "$ISO" "$DISK" \
            "$FIRMWARE_DIR/efi-virtio.rom"; do
    if [ ! -f "$file" ]; then
        printf 'ERROR: Required file not found:\n  %s\n' "$file" >&2
        exit 1
    fi
done

export LD_LIBRARY_PATH="$QEMU_LIB:$JNI_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$QEMU" \
    -L "$FIRMWARE_DIR" \
    -name alpine \
    -machine virt,gic-version=3 \
    -accel gzvm \
    -cpu host \
    -smp 8 \
    -m 2048 \
    -kernel "$KERNEL" \
    -initrd "$INITRAMFS" \
    -append "modules=loop,squashfs,sd-mod,virtio_blk console=ttyAMA0 debug_init" \
    -drive if=none,id=disk0,file="$DISK",format=qcow2 \
    -device virtio-blk-pci,drive=disk0 \
    -drive if=none,id=iso,file="$ISO",format=raw,readonly=on \
    -device virtio-blk-pci,drive=iso \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic
