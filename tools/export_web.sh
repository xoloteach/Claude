#!/usr/bin/env bash
# Export the "Web" preset to build/web/index.html.
#
# Usage: tools/export_web.sh [--debug]
# Env:   GODOT_BIN (default: $GODOT_BIN, `godot` on PATH, then ~/.local/godot/godot)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="--export-release"
[[ "${1:-}" == "--debug" ]] && MODE="--export-debug"

GODOT="${GODOT_BIN:-}"
if [[ -z "$GODOT" ]]; then
  if command -v godot >/dev/null 2>&1; then GODOT="$(command -v godot)"
  elif [[ -x "$HOME/.local/godot/godot" ]]; then GODOT="$HOME/.local/godot/godot"
  else echo "[export_web] godot not found; run tools/setup_godot.sh or set GODOT_BIN" >&2; exit 1
  fi
fi
echo "[export_web] using $GODOT ($("$GODOT" --headless --version 2>/dev/null))"

OUT_DIR="build/web"
LOG_DIR="build/logs"
mkdir -p "$OUT_DIR" "$LOG_DIR"
# Keep Godot from scanning/importing generated or tooling folders.
touch build/.gdignore
for d in tools/node_modules tools/shots; do [[ -d "$d" ]] && touch "$d/.gdignore"; done
rm -rf "${OUT_DIR:?}"/*

# Godot often exits 0 even when scripts fail to parse, so grep the log too.
check_log() {
  local log="$1" what="$2"
  sed -i 's/\x1b\[[0-9;]*m//g' "$log"  # strip ANSI colors
  if grep -E "^(SCRIPT ERROR|ERROR|USER ERROR|Parse Error)|Failed to (load|export)|Cannot (open|load)" "$log" \
       | grep -vE "Condition \"!f\" is true\. Returning: false|editor_settings|Could not create the directory: .*shader_cache" >/dev/null; then
    echo "::error::[export_web] $what reported errors:" >&2
    grep -nE -A3 "^(SCRIPT ERROR|ERROR|USER ERROR|Parse Error)|Failed to (load|export)|Cannot (open|load)" "$log" | head -80 >&2
    return 1
  fi
}

echo "[export_web] importing assets ..."
set +e
"$GODOT" --headless --import 2>&1 | tee "$LOG_DIR/import.log"
rc=${PIPESTATUS[0]}
set -e
[[ $rc -eq 0 ]] || { echo "::error::[export_web] import failed (exit $rc)" >&2; exit $rc; }
check_log "$LOG_DIR/import.log" "import" || exit 1

echo "[export_web] exporting ($MODE) ..."
set +e
"$GODOT" --headless $MODE "Web" "$OUT_DIR/index.html" 2>&1 | tee "$LOG_DIR/export.log"
rc=${PIPESTATUS[0]}
set -e
[[ $rc -eq 0 ]] || { echo "::error::[export_web] export failed (exit $rc)" >&2; exit $rc; }
check_log "$LOG_DIR/export.log" "export" || exit 1

for f in index.html index.js index.wasm index.pck; do
  [[ -s "$OUT_DIR/$f" ]] || { echo "::error::[export_web] missing $OUT_DIR/$f" >&2; exit 1; }
done
touch "$OUT_DIR/.nojekyll"

pck_bytes=$(stat -c %s "$OUT_DIR/index.pck")
echo "[export_web] OK -> $OUT_DIR"
ls -la "$OUT_DIR"
echo "[export_web] pck size: $(numfmt --to=iec --suffix=B "$pck_bytes" 2>/dev/null || echo "$pck_bytes bytes") ($pck_bytes bytes)"
echo "[export_web] total size: $(du -sh "$OUT_DIR" | cut -f1)"
