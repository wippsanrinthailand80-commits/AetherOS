#!/usr/bin/env bash
set -euo pipefail

ARCH="${ARCH:-x86_64}"
JOBS="${JOBS:-$(nproc)}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
OUT="$ROOT/out"
KVER="${KVER:-6.12.49}"
BVER="${BVER:-1.36.1}"

mkdir -p "$SRC" "$OUT"
rm -rf "$OUT/rootfs"
mkdir -p "$OUT/rootfs"

# ---- Kernel source ----
if [ ! -f "$SRC/linux-$KVER.tar.xz" ]; then
  wget -q "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz" -O "$SRC/linux-$KVER.tar.xz"
fi
if [ ! -d "$SRC/linux-$KVER" ]; then
  tar -xf "$SRC/linux-$KVER.tar.xz" -C "$SRC"
fi

# ---- BusyBox source ----
if [ ! -f "$SRC/busybox-$BVER.tar.bz2" ]; then
  wget -q "https://busybox.net/downloads/busybox-$BVER.tar.bz2" -O "$SRC/busybox-$BVER.tar.bz2"
fi
if [ ! -d "$SRC/busybox-$BVER" ]; then
  tar -xf "$SRC/busybox-$BVER.tar.bz2" -C "$SRC"
fi

# ---- Build BusyBox ----
cd "$SRC/busybox-$BVER"
make distclean >/dev/null 2>&1 || true
make defconfig >/dev/null
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
make oldconfig >/dev/null 2>&1 || true
make -j"$JOBS" >/dev/null
make install CONFIG_PREFIX="$OUT/rootfs" >/dev/null

# ---- Rootfs skeleton ----
ROOTFS="$OUT/rootfs"
for d in dev proc sys etc lib/modules tmp run var root home mnt; do
  mkdir -p "$ROOTFS/$d"
done
cp -a "$ROOT"/rootfs-overlay/. "$ROOTFS"/ 2>/dev/null || true
chmod +x "$ROOTFS/init" 2>/dev/null || true

# device nodes (best effort)
mknod -m 622 "$ROOTFS/dev/console" c 5 1 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/null" c 1 3 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/tty" c 5 0 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/ttyS0" c 4 64 2>/dev/null || true

# ---- Kernel config + build ----
cd "$SRC/linux-$KVER"
make distclean >/dev/null 2>&1 || true
make "${ARCH}_defconfig" >/dev/null
"$SRC/linux-$KVER/scripts/kconfig/merge_config.sh" .config "$ROOT/config/kernel.config" >/dev/null 2>&1 || true
make olddefconfig >/dev/null
make -j"$JOBS" bzImage modules

# ---- Install modules into rootfs ----
make modules_install INSTALL_MOD_PATH="$ROOTFS" >/dev/null

# ---- Build initramfs ----
cd "$ROOTFS"
find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 > "$OUT/initramfs.img"

# ---- Copy kernel image ----
cp "$SRC/linux-$KVER/arch/x86/boot/bzImage" "$OUT/bzImage" 2>/dev/null || \
cp "$SRC/linux-$KVER/arch/arm64/boot/Image" "$OUT/Image" 2>/dev/null || true

# ---- Build bootable ISO (x86_64) ----
if [ "$ARCH" = "x86_64" ] && command -v xorriso >/dev/null 2>&1; then
  ISODIR="$OUT/iso"
  rm -rf "$ISODIR"
  mkdir -p "$ISODIR/boot/isolinux"
  cp "$OUT/bzImage" "$ISODIR/boot/bzImage"
  cp "$OUT/initramfs.img" "$ISODIR/boot/initramfs.img"
  if [ -f /usr/lib/ISOLINUX/isolinux.bin ]; then
    cp /usr/lib/ISOLINUX/isolinux.bin "$ISODIR/boot/isolinux/"
  fi
  if [ -f /usr/lib/syslinux/modules/bios/ldlinux.c32 ]; then
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$ISODIR/boot/isolinux/"
  fi
  cat > "$ISODIR/boot/isolinux/isolinux.cfg" <<'CFG'
DEFAULT aetheros
LABEL aetheros
  KERNEL /boot/bzImage
  APPEND initrd=/boot/initramfs.img console=ttyS0 rdinit=/init
CFG
  xorriso -as mkisofs -o "$OUT/aetheros.iso" \
    -b boot/isolinux/isolinux.bin -c boot/isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    "$ISODIR" >/dev/null 2>&1 || true
fi

echo "Build complete. Artifacts in $OUT"
ls -lh "$OUT"
