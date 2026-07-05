# Building firmware_mod binaries

Cross-compiled for Ingenic T20/T20L (MIPS32r2, little-endian).

## Toolchain

Two toolchains are needed:

1. **Debian `mipsel-linux-gnu-gcc`** — for static glibc binaries (busybox, jq)
2. **Ingenic `mips-gcc472`** — for uClibc binaries (dropbear, mDNSResponder)

The Ingenic toolchain is at
[Dafang-Hacks/Ingenic-T10_20](https://github.com/Dafang-Hacks/Ingenic-T10_20).
Download `mips-gcc472-glibc216-64bit-r2.3.3.7z` and extract with `7z x -y`.
**Warning:** 7z may corrupt symlinks in the toolchain. Use the `.a` archives
from `uclibc/usr/lib/` directly, not the `.so` symlinks.

The key flag is `-muclibc` which tells GCC to link against the uClibc sysroot
instead of glibc. Without this, `crypt()` is unavailable and password auth fails.

## BusyBox 1.37.0

Static glibc build with Debian cross-compiler.

```bash
docker run --rm -it debian:bookworm bash
apt-get update && apt-get install -y gcc-mipsel-linux-gnu make wget xz-utils bzip2 file

wget https://busybox.net/downloads/busybox-1.37.0.tar.bz2
tar xjf busybox-1.37.0.tar.bz2 && cd busybox-1.37.0
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
# Disable HW-accelerated SHA (not available on MIPS)
sed -i 's/CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' .config
sed -i 's/CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' .config
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- olddefconfig
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- -j$(nproc)
```

Produces a ~2.7MB statically linked MIPS binary.

## jq 1.7.1

Static glibc build with Debian cross-compiler.

```bash
wget https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-1.7.1.tar.gz
tar xzf jq-1.7.1.tar.gz && cd jq-1.7.1
CC=mipsel-linux-gnu-gcc CFLAGS="-O2 -march=mips32r2 -static" \
  ./configure --host=mipsel-linux-gnu --with-oniguruma=builtin --enable-all-static
make -j$(nproc)
```

Produces a ~2.0MB statically linked MIPS binary.

## dropbearmulti 2022.83

Static uClibc build with Ingenic toolchain. Includes dropbear (SSH server),
dbclient (SSH client), and scp.

```bash
TC=/path/to/mips-gcc472-glibc216-64bit
export PATH=$TC/bin:$PATH
CC=mips-linux-gnu-gcc
UCFLAGS="-muclibc -O2 -march=mips32r2"
ULDFLAGS="-muclibc -static"

wget https://matt.ucc.asn.au/dropbear/releases/dropbear-2022.83.tar.bz2
tar xjf dropbear-2022.83.tar.bz2 && cd dropbear-2022.83

# Enable password and pubkey authentication
cat > localoptions.h <<'EOPT'
#define DROPBEAR_SVR_PASSWORD_AUTH 1
#define DROPBEAR_SVR_PUBKEY_AUTH 1
EOPT

CC=$CC CFLAGS="$UCFLAGS" LDFLAGS="$ULDFLAGS" \
  ./configure --host=mips-linux-gnu --prefix=/usr \
  --disable-zlib --disable-pam

# Force crypt() support (configure can't find it in cross-compile)
sed -i "s|#undef HAVE_CRYPT|#define HAVE_CRYPT 1|" config.h
sed -i "s|#error.*crypt.*|#\/\* crypt check bypassed \*\/|" sysoptions.h

make PROGRAMS="dropbear dbclient scp" -j$(nproc)
cat dropbear dbclient scp > dropbearmulti
```

Produces a ~1.7MB statically linked uClibc binary. Password: `ismart12`.

## mDNSResponder 1556.80.2

Apple's mDNS daemon, cross-compiled for uClibc with the Ingenic toolchain.
Requires several patches for GCC 4.7 compatibility.

```bash
TC=/path/to/mips-gcc472-glibc216-64bit
export PATH=$TC/bin:$PATH
CC="mips-linux-gnu-gcc -muclibc"
UC=$TC/mips-linux-gnu/libc/uclibc

git clone --depth 1 --branch mDNSResponder-1556.80.2 \
  https://github.com/apple-oss-distributions/mDNSResponder.git
cd mDNSResponder/mDNSPosix
mkdir -p objects/prod
```

### Patches required

**1. `_mdns_strict_strlcpy` → `strlcpy`** (GCC 4.7 doesn't support the strict wrapper):
```bash
sed -i "s/_mdns_strict_strlcpy/strlcpy/g" ../mDNSCore/mdns_strict.h mDNSPosix.c
```

**2. `IFA_FLAGS` undefined** (missing in older kernel headers):
```bash
sed -i "/#include <linux\/if.h>/a #ifndef IFA_FLAGS\n#define IFA_FLAGS 8\n#endif" mDNSPosix.c
```

**3. `TCP_NOTSENT_LOWAT` undefined** (defined via CFLAGS):
```
-DTCP_NOTSENT_LOWAT=19
```

**4. TLS stubs** (mDNSResponder includes TLS support that requires mbedtls):
```c
// tls_stubs.c — stub out all TLS functions
int mDNSPosixTLSInit(void *a) { (void)a; return 0; }
void mDNSPosixTLSFree(void *a) { (void)a; }
int mDNSPosixTLSRead(void *a, void *b, int c) { (void)a; (void)b; (void)c; return -1; }
int mDNSPosixTLSWrite(void *a, const void *b, int c) { (void)a; (void)b; (void)c; return -1; }
void *mDNSPosixTLSSocket(int a) { (void)a; return 0; }
int mDNSPosixTLSClientStateCreate(void *a) { (void)a; return 0; }
int mDNSPosixTLSStart(void *a) { (void)a; return 0; }
```
Compile: `mips-linux-gnu-gcc -muclibc -O2 -march=mips32r2 -std=gnu99 -c tls_stubs.c -o objects/prod/tls_stubs.o`

Then replace `TLSOBJS` in the Makefile to point to `tls_stubs.o` and remove `mbedtls.c.o`.

**5. Makefile configuration:**
```bash
# Force os=linux (detects via uname -s which may not match cross-compile)
sed -i '1a os = linux' Makefile

# Remove strip command (host strip can't handle MIPS binaries)
sed -i 's|\$(STRIP) \$@||g' Makefile

# Set compiler and flags
sed -i "s|^CC =.*|CC = $CC|" Makefile
sed -i "s|^CFLAGS =.*|CFLAGS = -O2 -march=mips32r2 -std=gnu99 -DHAVE_IPV6 -DNOT_HAVE_DAEMON -DNO_SECURITYFRAMEWORK -DTARGET_OS_LINUX -D_GNU_SOURCE -DTCP_NOTSENT_LOWAT=19 -DPOSIX_HAS_TLS=0 -w|" Makefile
sed -i "s|^LDFLAGS =.*|LDFLAGS = -static|" Makefile
sed -i "s|^LD =.*|LD = $CC|" Makefile

# Add uclibc .a libraries to LINKOPTS (replace empty LINKOPTS on first occurrence)
# Use python3 or awk — sed can't handle the long paths with /
LINKOPTS_PATH="$UC/usr/lib/libm.a $UC/usr/lib/librt.a $UC/usr/lib/libresolv.a"
python3 -c "
with open('Makefile') as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    if line.strip() == 'LINKOPTS =':
        lines[i] = 'LINKOPTS = -muclibc $LINKOPTS_PATH\n'
        break
with open('Makefile', 'w') as f:
    f.writelines(lines)
"
```

### Build

```bash
make 2>&1 | tail -5
# Ignore dns-sd client build failure (not needed)
# The mdnsd daemon builds successfully
```

Produces a ~1.5MB dynamically linked uClibc binary.

## Binary versions (current)

| Binary | Version | Linkage |
|--------|---------|---------|
| busybox | 1.37.0 | static (glibc) |
| jq | 1.7.1 | static (glibc) |
| dropbearmulti | 2022.83 | static (uClibc) |
| mDNSResponder | 1556.80.2 | dynamic (uClibc) |

## Updating

1. Replace the binary in `bin/`
2. Test on a camera with `ssh root@<camera-ip>` (password: `ismart12`)
3. Verify `busybox --help` and `jq --version` work
4. Commit and tag
