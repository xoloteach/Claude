#!/usr/bin/env bash
# Idempotently install the Godot editor + ONLY the Web export templates.
#
# Usage: tools/setup_godot.sh
# Env:
#   GODOT_VERSION   (default 4.7.2)
#   GODOT_DIR       install dir for the editor binary (default ~/.local/godot)
#   GODOT_TEMPLATES templates dir (default ~/.local/share/godot/export_templates/<ver>.stable)
#
# Prints the path of the godot binary on the last line. In GitHub Actions it
# also appends GODOT_BIN=<path> to $GITHUB_ENV and the dir to $GITHUB_PATH.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
TAG="${GODOT_VERSION}-stable"
GODOT_DIR="${GODOT_DIR:-$HOME/.local/godot}"
GODOT_TEMPLATES="${GODOT_TEMPLATES:-$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable}"
BASE_URL="https://github.com/godotengine/godot/releases/download/${TAG}"
EDITOR_NAME="Godot_v${TAG}_linux.x86_64"
TPZ_NAME="Godot_v${TAG}_export_templates.tpz"

log() { echo "[setup_godot] $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { log "missing required tool: $1"; exit 1; }; }
need curl
need unzip

mkdir -p "$GODOT_DIR" "$GODOT_TEMPLATES"

# ---- Editor --------------------------------------------------------------
BIN="$GODOT_DIR/$EDITOR_NAME"
if [[ -x "$BIN" ]] && "$BIN" --headless --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; then
  log "editor already installed: $BIN"
else
  log "downloading editor ${TAG} ..."
  tmp="$(mktemp -d)"
  curl -fL --retry 3 --retry-delay 5 -sS -o "$tmp/editor.zip" "$BASE_URL/${EDITOR_NAME}.zip"
  unzip -q -o "$tmp/editor.zip" -d "$tmp"
  mv -f "$tmp/$EDITOR_NAME" "$BIN"
  chmod +x "$BIN"
  rm -rf "$tmp"
fi
ln -sf "$BIN" "$GODOT_DIR/godot"

# ---- Web export templates -----------------------------------------------
REQUIRED=(web_nothreads_release.zip web_nothreads_debug.zip)
have_templates=1
for f in "${REQUIRED[@]}" version.txt; do
  [[ -s "$GODOT_TEMPLATES/$f" ]] || have_templates=0
done
if [[ $have_templates -eq 1 ]] && grep -q "^${GODOT_VERSION}\.stable" "$GODOT_TEMPLATES/version.txt"; then
  log "web templates already installed: $GODOT_TEMPLATES"
else
  log "downloading export templates (~1.2 GB, only web* will be kept) ..."
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 3 --retry-delay 5 -sS -o "$tmp/$TPZ_NAME" "$BASE_URL/$TPZ_NAME"
  unzip -q -o "$tmp/$TPZ_NAME" 'templates/web*.zip' 'templates/version.txt' -d "$tmp/x"
  rm -f "$tmp/$TPZ_NAME"
  mv -f "$tmp"/x/templates/* "$GODOT_TEMPLATES/"
  rm -rf "$tmp"
  trap - EXIT
  for f in "${REQUIRED[@]}"; do
    [[ -s "$GODOT_TEMPLATES/$f" ]] || { log "template $f missing after extraction"; exit 1; }
  done
  log "installed templates: $(cd "$GODOT_TEMPLATES" && ls | tr '\n' ' ')"
fi

"$BIN" --headless --version >&2 || { log "godot binary does not run"; exit 1; }

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "GODOT_BIN=$BIN" >> "$GITHUB_ENV"
  echo "$GODOT_DIR" >> "$GITHUB_PATH"
fi
echo "$BIN"
