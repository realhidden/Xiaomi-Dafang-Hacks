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

**dropbearmulti** — built with Ingenic mips-gcc472 toolchain using `-muclibc`:

The camera runs uClibc (`/lib/ld-uClibc.so.0`), so dropbear must be built with
`-muclibc` flag. The Ingenic toolchain at
[Dafang-Hacks/Ingenic-T10_20](https://github.com/Dafang-Hacks/Ingenic-T10_20)
includes uClibc support.

```bash
# In Docker with Ingenic toolchain:
TC=/build/tc/mips-gcc472-glibc216-64bit
export PATH=$TC/bin:$PATH
CC=mips-linux-gnu-gcc
UCFLAGS="-muclibc -O2 -march=mips32r2"
ULDFLAGS="-muclibc -static"

cd dropbear-2022.83
cat > localoptions.h <<EOPT
#define DROPBEAR_SVR_PASSWORD_AUTH 1
#define DROPBEAR_SVR_PUBKEY_AUTH 1
EOPT

CC=$CC CFLAGS="$UCFLAGS" LDFLAGS="$ULDFLAGS" \
  ./configure --host=mips-linux-gnu --prefix=/usr \
  --disable-zlib --disable-pam

# Force crypt() support
sed -i "s|#undef HAVE_CRYPT|#define HAVE_CRYPT 1|" config.h
sed -i "s|#error.*crypt.*|#\/\* crypt check bypassed \*\/|" sysoptions.h

make PROGRAMS="dropbear dbclient scp" -j$(nproc)
cat dropbear dbclient scp > dropbearmulti
```

The key flag is `-muclibc` which tells GCC to link against the uClibc sysroot
instead of glibc. Without this, `crypt()` is unavailable and password auth fails.

## Binary versions (current)

| Binary | Version | Linkage |
|--------|---------|---------|
| busybox | 1.37.0 | static (glibc) |
| jq | 1.7.1 | static (glibc) |
| dropbearmulti | 2022.83 | static (uClibc) |

## Updating

1. Replace the binary in `bin/`
2. Test on a camera with `ssh root@<camera-ip>` (password: `ismart12`)
3. Verify `busybox --help` and `jq --version` work
4. Commit and tag
