#!/bin/sh
# Compilation : tables et police (Python), assemblage (sjasmplus), disquette
# build/<GAME>.dsk (RUN"<GAME>"). Assemblage dans une copie locale (hors
# Google Drive : écrire bloc par bloc dans un dossier synchronisé corrompt).
# Options passées à sjasmplus, ex. : sh build.sh -DPROFILE
set -e
cd "$(dirname "$0")"
GAME=$(python -c "import sys; sys.path.insert(0, 'tools'); import port_config as p; print(p.GAME)")
DSK_NAME=$(python -c "import sys; sys.path.insert(0, 'tools'); import port_config as p; print(p.DSK_NAME)")
SJASM="${SJASM:-$LOCALAPPDATA/sjasmplus/sjasmplus-1.24.0.win/sjasmplus.exe}"
WORK="${PORT_WORK:-$LOCALAPPDATA/coleco-cpc/$GAME/build}"
mkdir -p build
python -X utf8 tools/gen_tables.py
if [ -f gfx/logo.png ]; then python -X utf8 tools/logo.py asm; fi
rm -rf "$WORK"
mkdir -p "$WORK/build"
cp -r src "$WORK/"
cp build/cart.bin "$WORK/build/"
(cd "$WORK/src" && "$SJASM" --nologo --msg=war --sym="../build/$GAME.sym" --lst="../build/$GAME.lst" main.asm "$@")
mv "$WORK/build/game.bin" "$WORK/build/$GAME.bin" 2>/dev/null || true
python -X utf8 tools/make_dsk.py "$WORK/build/$GAME.dsk" "$DSK_NAME.BIN" "$WORK/build/$GAME.bin" 0x0400 0x9E00
cp "$WORK/build/$GAME.dsk" "$WORK/build/$GAME.bin" "$WORK/build/$GAME.sym" "$WORK/build/$GAME.lst" build/
ls -l "build/$GAME.dsk"
