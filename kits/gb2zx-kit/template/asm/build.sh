#!/bin/sh
# Compilation complète : traduit la logique depuis la ROM GB, génère les
# graphismes, assemble avec sjasmplus -> build/game.tap (+ .sym, .lst).
#
# L'assemblage se fait dans une copie locale (hors Google Drive/OneDrive...) :
# écrire la cassette bloc par bloc dans un dossier synchronisé l'a corrompue
# (bloc manquant, ancienne version). Les fichiers produits sont recopiés
# d'un coup dans build/.
set -e
cd "$(dirname "$0")"
SJASM="${SJASM:-$LOCALAPPDATA/sjasmplus/sjasmplus-1.24.0.win/sjasmplus.exe}"
WORK="${GB2ZX_WORK:-$LOCALAPPDATA/gb2zx/asm_build}"
mkdir -p build
if [ -f ../port_config.py ] && [ -f ../re/game.gb ]; then
    python -X utf8 ../tools/gb2z80.py
fi
# À FAIRE : générateurs du jeu (sprites, décor, écran titre), par exemple :
# python -X utf8 ../tools/gen_sprites.py
python -X utf8 ../tools/make_title.py
rm -rf "$WORK"
mkdir -p "$WORK/build"
cp -r src gb gfx "$WORK/"
(cd "$WORK/src" && "$SJASM" --nologo --msg=war --sym=../build/game.sym --lst=../build/game.lst main.asm "$@")
cp "$WORK/build/game.tap" "$WORK/build/game.sym" "$WORK/build/game.lst" build/
ls -l build/game.tap
