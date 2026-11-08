#!/bin/sh
# Copies the libgit2 sources that BaseKit compiles into Packages/BaseKit/Vendor/libgit2.
# Usage: scripts/vendor-libgit2.sh v1.9.7
# The build settings live in Packages/BaseKit/Package.swift; check them against the new
# release's src/util/git2_features.h.in when updating.
set -eu
tag="${1:?usage: scripts/vendor-libgit2.sh <libgit2 tag>}"
cd "$(dirname "$0")/.."
dest=Packages/BaseKit/Vendor/libgit2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone --quiet --depth 1 --branch "$tag" https://github.com/libgit2/libgit2 "$tmp/libgit2"
src="$tmp/libgit2"

rm -rf "$dest"
mkdir -p "$dest/src" "$dest/deps"
cp -R "$src/include" "$dest/include"
cp -R "$src/src/libgit2" "$src/src/util" "$dest/src/"
cp -R "$src/deps/llhttp" "$src/deps/xdiff" "$dest/deps/"
cp "$src/COPYING" "$dest/COPYING"

# Windows-only code, and the hash and TLS backends Usual Base doesn't use.
rm -rf "$dest/src/util/win32"
rm -f "$dest/src/util/hash/builtin."* "$dest/src/util/hash/openssl."* "$dest/src/util/hash/mbedtls."* \
    "$dest/src/util/hash/win32."*
rm -rf "$dest/src/util/hash/rfc6234"
# Keep only C sources and headers, so SwiftPM has no unhandled files to warn about.
find "$dest/src" "$dest/deps" -type f ! -name '*.c' ! -name '*.h' -delete

printf '%s %s\n' "$tag" "$(git -C "$src" rev-parse HEAD)" > "$dest/VERSION"
echo "Vendored libgit2 $tag into $dest"
