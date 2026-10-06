#!/bin/sh
# Compilation : traduit la logique depuis la ROM GB (Z80) si la ROM et la
# configuration sont là, génère les graphismes, assemble avec sjasmplus et
# fabrique la disquette build/game.dsk (RUN"GAME").
# Assemblage dans une copie locale (hors Google Drive/OneDrive...) : écrire
# des fichiers bloc par bloc dans un dossier synchronisé les a corrompus.
# Options passées à sjasmplus, ex. : sh build.sh -DPROFILE
set -e
cd "$(dirname "$0")"
SJASM="${SJASM:-$LOCALAPPDATA/sjasmplus/sjasmplus-1.24.0.win/sjasmplus.exe}"
WORK="${GB2CPC_WORK:-$LOCALAPPDATA/gb2cpc/build}"
mkdir -p build
if [ -f re/game.gb ] && [ -n "$(python -c 'import port_config as c; print(c.ROOTS)' | tr -d '{}')" ]; then
    python -X utf8 tools/gb2z80.py
fi
# À FAIRE : générateurs du jeu (décor, sprites, titre), avec tools/cpcgfx.py
python -X utf8 tools/make_demo_gfx.py
rm -rf "$WORK"
mkdir -p "$WORK/build"
cp -r src gb gfx "$WORK/"
(cd "$WORK/src" && "$SJASM" --nologo --msg=war --sym=../build/game.sym --lst=../build/game.lst main.asm "$@")
python -X utf8 tools/make_dsk.py "$WORK/build/game.dsk" GAME.BIN "$WORK/build/game.bin" 0x0200 0x0200
cp "$WORK/build/game.dsk" "$WORK/build/game.bin" "$WORK/build/game.sym" "$WORK/build/game.lst" build/
ls -l build/game.dsk
