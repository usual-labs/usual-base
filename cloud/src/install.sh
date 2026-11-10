#!/bin/sh
# Installs the Usual Base CLI as ~/.local/bin/usual-base, with ubase as a link to it. It needs Node.js 18 or later
# and git.
set -eu
SERVER="https://base.usual.dev"
DIR="${USUAL_BASE_BIN:-$HOME/.local/bin}"

command -v node >/dev/null 2>&1 || { echo "Usual Base needs Node.js 18 or later: https://nodejs.org" >&2; exit 1; }
major=$(node -p 'process.versions.node.split(".")[0]')
[ "$major" -ge 18 ] || { echo "Usual Base needs Node.js 18 or later; this is $(node --version)." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "Usual Base needs git." >&2; exit 1; }

mkdir -p "$DIR"
curl -fsSL "$SERVER/cli/usual-base.mjs" -o "$DIR/usual-base.tmp"
mv "$DIR/usual-base.tmp" "$DIR/usual-base"
chmod +x "$DIR/usual-base"
# The short name, unless something else already has it.
if [ ! -e "$DIR/ubase" ] && [ ! -L "$DIR/ubase" ]; then ln -s usual-base "$DIR/ubase"; fi
if [ "$(readlink "$DIR/ubase" 2>/dev/null)" = usual-base ]; then also=" (also as ubase)"; else also=""; fi
echo "Installed $DIR/usual-base$also"
case ":$PATH:" in
  *":$DIR:"*) ;;
  *) echo "Add $DIR to your PATH, or run it as $DIR/usual-base" ;;
esac
