#!/bin/bash
# Native whois 5.6.6 package build for Haiku OS (x86_64)
# Runs entirely on the Haiku machine; one-shot: extract, patch, build, stage,
# package.
#
# Produces: /boot/home/out/whois-5.6.6-1-x86_64.hpkg
#
# Usage: ./build_haiku_whois.sh [source-dir]
#   source-dir must contain whois_5.6.6.tar.xz and whois-5.6.6.patchset
#   (default: /boot/home/build/whois-src)
set -e

VERSION="5.6.6"
REVISION="1"
PKGVER="${VERSION}-${REVISION}"
SRCDIR="${1:-/boot/home/build/whois-src}"
WORK="/boot/home/build/whois-work"
OUT="/boot/home/out"
STAGE="/boot/home/build/stage-whois"
PKGNAME="whois"
# Optional local WHOIS-server overrides, see whois.conf(5). ENOENT is
# handled gracefully by upstream, so the file need not exist.
CONFIG_FILE="/boot/system/settings/network/whois.conf"

rm -rf "$WORK" "$STAGE"
mkdir -p "$WORK" "$STAGE" "$OUT"

# ---- 1. extract (tarball's top-level dir is "work/": native Debian format) ----
tar -C "$WORK" -xf "$SRCDIR/whois_${VERSION}.tar.xz"
cd "$WORK/work"

# ---- 2. apply the Haiku patchset ----
#   config.h: HAVE_GETOPT_LONG / HAVE_GETADDRINFO / HAVE_REGEXEC (long opts!)
#   Makefile: socket API -> libnetwork
patch -p1 < "$SRCDIR/whois-${VERSION}.patchset"

# ---- 3. build the whois binary only ----
#   mkpasswd (needs libcrypt) and po/ (needs gettext) are deliberately
#   not built.
make whois CONFIG_FILE="$CONFIG_FILE"

# ---- 4. stage install ----
#   Binary: bin/whois.
#   Man pages: upstream installs to share/man, but Haiku's man(1) (mandoc)
#   only reads /boot/system/documentation/man -- re-root them there.
rm -rf /tmp/whois-destroot
make install-whois prefix=/boot/system DESTDIR=/tmp/whois-destroot \
	CONFIG_FILE="$CONFIG_FILE"
mkdir -p "$STAGE"
cp -a /tmp/whois-destroot/boot/system/. "$STAGE/"
rm -rf /tmp/whois-destroot
mkdir -p "$STAGE/documentation/man"
mv "$STAGE/share/man/man1" "$STAGE/documentation/man/man1"
mv "$STAGE/share/man/man5" "$STAGE/documentation/man/man5"
rmdir "$STAGE/share/man" "$STAGE/share"

# ---- 5. strip the binary; keep a debug copy alongside the package ----
mkdir -p "$OUT/debuginfo"
cp "$STAGE/bin/whois" "$OUT/debuginfo/whois.debug"
strip "$STAGE/bin/whois"

# ---- .PackageInfo ----
cat > "$STAGE/.PackageInfo" <<EOF
name			$PKGNAME
version			$PKGVER
architecture		x86_64
summary			"Intelligent WHOIS client"
description		"whois is a RFC 3912 WHOIS protocol client that intelligently selects the appropriate WHOIS server for most queries: it starts at whois.iana.org and follows TLD, registry and registrar referrals until it reaches the authoritative server. This build is compiled natively for Haiku."
packager		"Native whois for Haiku build"
vendor			"whois project (github.com/rfc1036/whois)"
licenses {
	"GNU GPL v2"
}
copyrights {
	"1996-2026 Marco d'Itri and contributors"
}
provides {
	$PKGNAME = $PKGVER compat >= 1
	cmd:$PKGNAME = $PKGVER
}
requires {
	haiku >= r1~beta5
}
urls {
	"https://github.com/rfc1036/whois"
}
EOF

# ---- create the package from the staged tree ----
rm -f "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"
package create -C "$STAGE" "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"

echo "=== package created ==="
ls -la "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"
package info "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"
echo "=== contents ==="
package list "$OUT/${PKGNAME}-${PKGVER}-x86_64.hpkg"
