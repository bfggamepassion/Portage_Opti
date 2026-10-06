#!/bin/sh
# Version ColecoVision : traduit la logique depuis la ROM GB (Z80, RAM GB
# déplacée dans le 1 Ko de la console), génère les graphismes, assemble avec
# sjasmplus -> build/tennis.rom (cartouche 32 Ko).
# Assemblage dans une copie locale (hors Google Drive), comme pour le Spectrum.
set -e
cd "$(dirname "$0")"
SJASM="${SJASM:-$LOCALAPPDATA/sjasmplus/sjasmplus-1.24.0.win/sjasmplus.exe}"
WORK="${TENNIS_WORK:-$LOCALAPPDATA/Tennis/cv_build}"
mkdir -p build
python -X utf8 tools/gb2z80.py
python -X utf8 tools/gen_cvgfx.py
python -X utf8 tools/gen_cvtitle.py
python -X utf8 tools/gen_cvsprites.py
rm -rf "$WORK"
mkdir -p "$WORK/build"
cp -r src gb gfx "$WORK/"
(cd "$WORK/src" && "$SJASM" --nologo --msg=war --sym=../build/tennis.sym --lst=../build/tennis.lst main.asm "$@")
cp "$WORK/build/tennis.rom" "$WORK/build/tennis.sym" "$WORK/build/tennis.lst" build/
ls -l build/tennis.rom
