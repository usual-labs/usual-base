#!/bin/sh
# Installs the Usual Base CLI as ~/.local/bin/usual. It needs Node.js 18 or later and git.
set -eu
SERVER="https://base.usual.dev"
DIR="${USUAL_BASE_BIN:-$HOME/.local/bin}"

command -v node >/dev/null 2>&1 || { echo "Usual Base needs Node.js 18 or later: https://nodejs.org" >&2; exit 1; }
major=$(node -p 'process.versions.node.split(".")[0]')
[ "$major" -ge 18 ] || { echo "Usual Base needs Node.js 18 or later; this is $(node --version)." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "Usual Base needs git." >&2; exit 1; }

mkdir -p "$DIR"
curl -fsSL "$SERVER/cli/usual.mjs" -o "$DIR/usual.tmp"
mv "$DIR/usual.tmp" "$DIR/usual"
chmod +x "$DIR/usual"
echo "Installed $DIR/usual"
case ":$PATH:" in
  *":$DIR:"*) ;;
  *) echo "Add $DIR to your PATH, or run it as $DIR/usual" ;;
esac
