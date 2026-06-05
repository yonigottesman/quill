#!/usr/bin/env bash
# Generates Quill/Quill.icns from the pencil.line symbol. Run when you want to
# regenerate the app icon; the .icns is committed so normal builds don't need it.
set -euo pipefail
cd "$(dirname "$0")/.."

PNG=/tmp/quill-1024.png
ICONSET=/tmp/Quill.iconset

swift scripts/make-icon.swift "$PNG"

rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s"       "$PNG" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
  sips -z $((s*2)) $((s*2)) "$PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Quill/Quill.icns
echo "wrote Quill/Quill.icns"
