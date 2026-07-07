# Building firmware_mod binaries

Cross-compiled for Ingenic T20/T20L (MIPS32r2, little-endian).

## Toolchain

Two toolchains are needed:

1. **Debian `mipsel-linux-gnu-gcc`** — for static glibc binaries (busybox, jq)
2. **Ingenic `mips-gcc472`** — for uClibc binaries (dropbear, mDNSResponder, curl, mbedTLS)

The Ingenic toolchain is at
[Dafang-Hacks/Ingenic-T10_20](https://github.com/Dafang-Hacks/Ingenic-T10_20).
Download `mips-gcc472-glibc216-64bit-r2.3.3.7z` and extract with `7z x -y`.
**Warning:** 7z may corrupt symlinks in the toolchain. Use the `.a` archives
from `uclibc/usr/lib/` directly, not the `.so` symlinks.

The key flag is `-muclibc` which tells GCC to link against the uClibc sysroot
instead of glibc. Without this, `crypt()` is unavailable and password auth fails.

## BusyBox 1.38.0

Static glibc build with Debian cross-compiler.

```bash
docker run --rm -it debian:bookworm bash
apt-get update && apt-get install -y gcc-mipsel-linux-gnu make wget xz-utils bzip2 file

wget https://busybox.net/downloads/busybox-1.38.0.tar.bz2
tar xjf busybox-1.38.0.tar.bz2 && cd busybox-1.38.0
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
# Disable HW-accelerated SHA (not available on MIPS)
sed -i 's/CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' .config
sed -i 's/CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' .config
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- olddefconfig
make ARCH=mips CROSS_COMPILE=mipsel-linux-gnu- -j$(nproc)
```

Produces a ~2.7MB statically linked MIPS binary.

## jq 1.8.2

Static glibc build with Debian cross-compiler.

```bash
wget https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-1.8.2.tar.gz
tar xzf jq-1.8.2.tar.gz && cd jq-1.8.2
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

## mDNSResponder 2881.120.11

Apple's mDNS daemon, cross-compiled for uClibc with the Ingenic toolchain.
Requires several patches for GCC 4.7 and POSIX compatibility.

```bash
TC=/path/to/mips-gcc472-glibc216-64bit
export PATH=$TC/bin:$PATH

git clone --depth 1 --branch mDNSResponder-2881.120.11 \
  https://github.com/apple-oss-distributions/mDNSResponder.git
cd mDNSResponder/mDNSPosix
mkdir -p objects/prod build/prod
```

### Patches required

**1. `mdns_strict.h` — remove `_mdns_strict_strlcpy` and use system `strlcpy`:**
```bash
# Delete the _mdns_strict_strlcpy function definition (lines 119-141)
sed -i "119,141d" ../mDNSCore/mdns_strict.h
# Replace the macro to point to system strlcpy
sed -i "s/#define mdns_strlcpy[[:space:]]*_mdns_strict_strlcpy/#define mdns_strlcpy strlcpy/" ../mDNSCore/mdns_strict.h
```

**2. `IFA_FLAGS` undefined** (add at top of mDNSPosix.c):
```bash
sed -i "1i #ifndef IFA_FLAGS\n#define IFA_FLAGS 8\n#endif" mDNSPosix.c
```

**3. AWDL code** (Apple Wireless Direct Link — not available on POSIX):
```bash
sed -i "s|const mDNSBool is_split_awdl_query = (req->resolve_awdl && question->InterfaceID == AWDLInterfaceID);|const mDNSBool is_split_awdl_query = mDNSfalse;|" ../mDNSShared/uds_daemon.c
```

**4. TLS stubs** (mDNSResponder includes mbedtls TLS support — stub it out):
```c
// tls_stubs.c
int mDNSPosixTLSInit(void *a) { (void)a; return 0; }
void mDNSPosixTLSFree(void *a) { (void)a; }
int mDNSPosixTLSRead(void *a, void *b, int c) { (void)a; (void)b; (void)c; return -1; }
int mDNSPosixTLSWrite(void *a, const void *b, int c) { (void)a; (void)b; (void)c; return -1; }
void *mDNSPosixTLSSocket(int a) { (void)a; return 0; }
int mDNSPosixTLSClientStateCreate(void *a) { (void)a; return 0; }
int mDNSPosixTLSStart(void *a) { (void)a; return 0; }
```

**5. Makefile changes:**
```bash
sed -i "s|^os =.*|os = linux|" Makefile
sed -i "0,/^CC =/s|^CC =.*|CC = mips-linux-gnu-gcc -muclibc|" Makefile
sed -i "/^CFLAGS_COMMON/s/$/ -std=gnu99 -w/" Makefile
sed -i "s|^LDFLAGS =.*|LDFLAGS = -static|" Makefile
sed -i "0,/^LD =/s|^LD =.*|LD = mips-linux-gnu-gcc -muclibc|" Makefile
sed -i "s/\$(STRIP) \\\$@//g" Makefile
sed -i "s|TLSOBJS = \$(OBJDIR)/mbedtls.c.o -lmbedtls -lmbedcrypto|TLSOBJS = \$(OBJDIR)/tls_stubs.o|" Makefile

# Add tls_stubs compilation rule
printf "\$(OBJDIR)/tls_stubs.o: tls_stubs.c\n\t\$(CC) \$(CFLAGS) -c -o \$@ \$<\n" >> Makefile
```

### Build

```bash
make 2>&1 | tail -5
# Ignore dns-sd client build failure (host linker can't use cross-compiled .so)
# The mdnsd daemon builds successfully
```

Produces a ~1.4MB dynamically linked uClibc binary.

## mbedTLS 2.28.9 (2.x LTS)

TLS library used by curl. Built with Ingenic toolchain for uClibc.

**Use 2.28.x, not 3.x** — curl is pinned to 7.59.0 (see below) and curl 7.59's
mbedTLS glue targets the 2.x API; mbedTLS 3.x is source-incompatible with it.

```bash
TC=/path/to/mips-gcc472-glibc216-64bit
export PATH=$TC/bin:$PATH

wget https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-2.28.9/mbedtls-2.28.9.tar.bz2
tar xf mbedtls-2.28.9.tar.bz2 && cd mbedtls-2.28.9
# -std=gnu99 is REQUIRED: gcc-4.7 defaults to C89, and bignum.c uses C99
# for-loop declarations.
CC=mips-linux-gnu-gcc AR=mips-linux-gnu-ar \
  CFLAGS="-muclibc -O2 -march=mips32r2 -std=gnu99 -w" \
  make -j$(nproc) lib

# Stage headers + static libs into /build/mb. Do NOT `make install` — its
# programs target (aes/crypt_and_hash, etc.) link with the HOST linker and
# fail in a cross-build.
mkdir -p /build/mb/include /build/mb/lib
cp -r include/mbedtls /build/mb/include/
cp library/libmbed*.a /build/mb/lib/
```

## curl 7.59.0 + libcurl

curl with HTTPS via mbedTLS 2.28. Produces both `curl` binary and `libcurl.a`
for linking into other programs (e.g. the donekamera client).

**CRITICAL: pin to 7.59.0 — do NOT use curl 8.x.** curl 8.21 (and other 8.x)
hangs inside `curl_easy_perform` on the camera's uClibc 0.9.33 / gcc-4.7
runtime: even `curl file:///etc/hostname` stalls forever and `--max-time` never
fires, while every OS primitive it depends on (getaddrinfo, poll/select,
non-blocking connect, clock_gettime, socketpair) works fine. 7.59.0 (2018) is
contemporary with this toolchain and works correctly. This is also the version
the legacy `curl.bin` shipped with.

```bash
TC=/path/to/mips-gcc472-glibc216-64bit
export PATH=$TC/bin:$PATH

wget https://curl.se/download/curl-7.59.0.tar.gz
tar xzf curl-7.59.0.tar.gz && cd curl-7.59.0

CC=mips-linux-gnu-gcc \
  CFLAGS="-muclibc -O2 -march=mips32r2 -w -I/build/mb/include" \
  LDFLAGS="-L/build/mb/lib" \
  ./configure --host=mips-linux-gnu --prefix=/usr --with-mbedtls=/build/mb \
    --enable-static --disable-shared \
    --disable-ldap --disable-rtsp --disable-dict \
    --disable-telnet --disable-tftp --disable-pop3 \
    --disable-imap --disable-smb --disable-smtp \
    --disable-gopher --disable-manual \
    --without-libidn2 --without-librtmp --without-nghttp2 \
    --without-brotli --without-zstd --without-libpsl \
    --without-libssh2 --without-libgsasl --without-zlib

make -j$(nproc)
make install  # installs libcurl.a + headers to sysroot
```

Produces a ~950KB (stripped) dynamically linked uClibc `curl` binary and a
~620KB static `libcurl.a` for cross-compilation. Link with
`-lcurl -lmbedtls -lmbedx509 -lmbedcrypto`.

## Binary versions (current)

| Binary | Version | Linkage |
|--------|---------|---------|
| busybox | 1.38.0 | static (glibc) |
| jq | 1.8.2 | static (glibc) |
| dropbearmulti | 2026.92 | static (uClibc) |
| mDNSResponder | 2881.120.11 | dynamic (uClibc) |
| curl | 7.59.0 | dynamic (uClibc) |
| mbedTLS | 2.28.9 | static (uClibc, lib) |

## Updating

1. Replace the binary in `bin/`
2. Test on a camera with `ssh root@<camera-ip>` (password: `ismart12`)
3. Verify `busybox --help` and `jq --version` work
4. Commit and tag
