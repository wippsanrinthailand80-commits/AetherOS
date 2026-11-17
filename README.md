# AetherOS

AetherOS is a Linux operating system built from scratch: a custom-configured
Linux kernel plus a BusyBox-based userspace, packaged as an initramfs and a
bootable ISO. The kernel is configured with broad GPU/DRM support (virtio-gpu,
Nouveau, i915, AMDGPU, Radeon and more) so it can run on a wide range of
hardware and virtual GPUs.

## Build

```sh
./build.sh
```

Artifacts are written to `out/` (`bzImage`, `initramfs.img`, `aetheros.iso`).

## Boot (QEMU)

```sh
qemu-system-x86_64 -kernel out/bzImage -initrd out/initramfs.img \
  -append "console=ttyS0 rdinit=/init" -nographic -m 512
```
