
#!/data/data/com.termux/files/usr/bin/sh

set -eu

# ============================================================
# Configuration
# ============================================================

VM_NAME="alpine"

# Hardware
CPU_CORES="${CPU_CORES:-8}"
RAM_MB="${RAM_MB:-2048}"

# Storage
DISK_IMAGE="alpine.qcow2"
ROOT_UUID="2400f7ad-8f71-45c3-8b2f-2c7ac1ea066b"

# Boot
KERNEL_PATH="boot/vmlinuz-virt"
INITRAMFS_PATH="boot/initramfs-virt"

KERNEL_ARGS="root=UUID=${ROOT_UUID} modules=virtio_blk,sd-mod,ext4 rootfstype=ext4 rootwait rw console=ttyAMA0,38400"

# Networking
NETWORK_ID="net0"

SSH_HOST_PORT="${SSH_HOST_PORT:-2222}"
SSH_GUEST_PORT="${SSH_GUEST_PORT:-22}"

UDP_BIND="${UDP_BIND:-0.0.0.0}"
UDP_PORTS="
40000
51820
"

# Background execution
LOG_FILE="alpine.log"
PID_FILE="alpine.pid"

# ============================================================
# Paths
# ============================================================

case "$0" in
    /*) SCRIPT="$0" ;;
    *)  SCRIPT="$PWD/$0" ;;
esac

DIR="$(CDPATH= cd -- "$(dirname -- "$SCRIPT")" && pwd)"

QEMU="$DIR/qemu-gzvm/qemu-gzvm/qemu-system-aarch64"
QEMU_LIB="$DIR/qemu-gzvm/qemu-gzvm/lib"
JNI_LIB="$DIR/qemu-gzvm/arm64-v8a"
FIRMWARE="$DIR/qemu-gzvm/qemu-gzvm/fw"

DISK="$DIR/$DISK_IMAGE"
KERNEL="$DIR/$KERNEL_PATH"
INITRAMFS="$DIR/$INITRAMFS_PATH"

LOG="$DIR/$LOG_FILE"
PID="$DIR/$PID_FILE"

# ============================================================
# Arguments
# ============================================================

MODE="foreground"

case "${1:-}" in
    --bg)
        MODE="background"
        ;;
    --foreground)
        MODE="foreground"
        ;;
    --help|-h)
        echo "Usage: $0 [--bg | --foreground]"
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Usage: $0 [--bg | --foreground]" >&2
        exit 1
        ;;
esac

# ============================================================
# Background launcher
# ============================================================

if [ "$MODE" = "background" ]; then

    if [ -f "$PID" ]; then
        OLD_PID="$(cat "$PID")"

        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "Alpine is already running (PID: $OLD_PID)"
            exit 1
        fi

        rm -f "$PID"
    fi

    echo "Starting Alpine in background..."

    nohup "$SCRIPT" --foreground \
        > "$LOG" 2>&1 < /dev/null &

    VM_PID=$!
    echo "$VM_PID" > "$PID"

    sleep 1

    if ! kill -0 "$VM_PID" 2>/dev/null; then
        echo "ERROR: Alpine failed to start."
        rm -f "$PID"
        tail -n 20 "$LOG"
        exit 1
    fi

    echo "Alpine started."
    echo "PID: $VM_PID"
    echo "Log: $LOG"
    echo "SSH: ssh root@127.0.0.1 -p $SSH_HOST_PORT"
    exit 0
fi

# ============================================================
# Validation
# ============================================================

require_file() {
    [ -f "$1" ] || {
        echo "ERROR: File not found: $1" >&2
        exit 1
    }
}

require_executable() {
    [ -x "$1" ] || {
        echo "ERROR: Executable not found: $1" >&2
        exit 1
    }
}

require_executable "$QEMU"
require_file "$KERNEL"
require_file "$INITRAMFS"
require_file "$DISK"

[ -d "$FIRMWARE" ] || {
    echo "ERROR: Firmware directory not found: $FIRMWARE" >&2
    exit 1
}

# ============================================================
# Environment
# ============================================================

export LD_LIBRARY_PATH="$QEMU_LIB:$JNI_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ============================================================
# Network configuration
# ============================================================

NETDEV="user,id=$NETWORK_ID"

# SSH forwarding
NETDEV="$NETDEV,hostfwd=tcp:127.0.0.1:${SSH_HOST_PORT}-:${SSH_GUEST_PORT}"

# UDP forwarding
for PORT in $UDP_PORTS; do
    NETDEV="$NETDEV,hostfwd=udp:${UDP_BIND}:${PORT}-:${PORT}"
done

# ============================================================
# Startup
# ============================================================

echo "========================================"
echo " VM:       $VM_NAME"
echo " CPU:      $CPU_CORES cores"
echo " RAM:      $RAM_MB MB"
echo " Disk:     $DISK_IMAGE"
echo " SSH:      127.0.0.1:$SSH_HOST_PORT"
echo " UDP:      $UDP_PORTS"
echo "========================================"

# ============================================================
# QEMU
# ============================================================

exec "$QEMU" \
    -L "$FIRMWARE" \
    -name "$VM_NAME" \
    -machine virt,gic-version=3 \
    -accel gzvm \
    -cpu host \
    -smp "$CPU_CORES" \
    -m "$RAM_MB" \
    -kernel "$KERNEL" \
    -initrd "$INITRAMFS" \
    -append "$KERNEL_ARGS" \
    -drive if=none,id=disk0,file="$DISK",format=qcow2 \
    -device virtio-blk-pci,drive=disk0 \
    -netdev "$NETDEV" \
    -device virtio-net-pci,netdev="$NETWORK_ID" \
    -nographic
