# Building firmware_mod binaries

Cross-compiled for Ingenic T20/T20L (MIPS32r2, little-endian).

## Toolchain

**BusyBox and jq** — built with Debian `mipsel-linux-gnu-gcc` (glibc, static):

```bash
# Docker
docker run --rm -it debian:bookworm bash
apt-get update && apt-get install -y gcc-mipsel-linux-gnu make wget xz-utils bzip2 file

# BusyBox 1.37.0
wget https://busybox.net/downloads/busybox-1.37.0.tar.bz2
tar xjf busybox-1.37.0.tar.bz2 && cd busybox-1.37.0
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
sed -i 's/CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' .config
sed -i 's/CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' .config
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- olddefconfig
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- -j$(nproc)

# jq 1.7.1
wget https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-1.7.1.tar.gz
tar xzf jq-1.7.1.tar.gz && cd jq-1.7.1
CC=mipsel-linux-gnu-gcc CFLAGS="-O2 -march=mips32r2 -static" \
  ./configure --host=mipsel-linux-gnu --with-oniguruma=builtin --enable-all-static
make -j$(nproc)
```

**dropbearmulti** — built with Ingenic mips-gcc472 toolchain (uClibc):

The camera runs uClibc (`/lib/ld-uClibc.so.0`), so dropbear must be dynamically
linked against it. The Ingenic toolchain at
[Dafang-Hacks/Ingenic-T10_20](https://github.com/Dafang-Hacks/Ingenic-T10_20)
includes a uClibc sysroot at `mips-gcc472-glibc216-64bit/mips-linux-gnu/libc/uclibc/`.

Building dropbear with password auth requires `crypt()` from uClibc, which is why
the standard Debian cross-compiler cannot be used for this binary.

## Binary versions (current)

| Binary | Version | Linkage |
|--------|---------|---------|
| busybox | 1.37.0 | static (glibc) |
| jq | 1.7.1 | static (glibc) |
| dropbearmulti | 2019.78 | dynamic (uClibc) |

## Updating

1. Replace the binary in `bin/`
2. Test on a camera with `ssh root@<camera-ip>` (password: `ismart12`)
3. Verify `busybox --help` and `jq --version` work
4. Commit and tag
