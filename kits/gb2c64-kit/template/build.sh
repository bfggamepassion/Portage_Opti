#!/bin/sh
# Compilation : traduit la logique depuis la ROM GB (6502) si la ROM et la
# configuration sont là, génère les graphismes, assemble avec 64tass
# -> build/game.prg (+ étiquettes VICE build/game.lbl, listing build/game.lst).
# Options passées à 64tass, ex. : sh build.sh -D AUTOPLAY=1
set -e
cd "$(dirname "$0")"
TASS="${TASS:-$LOCALAPPDATA/64tass/64tass-1.60.3243/64tass.exe}"
mkdir -p build
if [ -f port_config.py ] && [ -f re/game.gb ] && [ -n "$(python -c 'import port_config as c; print(c.ROOTS)' | tr -d '{}')" ]; then
    python -X utf8 tools/gb2m6502.py
fi
# À FAIRE : générateurs du jeu (décor, sprites, titre), avec tools/c64gfx.py
# -C : majuscules et minuscules distinctes (sinon TITLE_COLORS = title_colors)
(cd src && "$TASS" -q -a -B -C -o ../build/game.prg --vice-labels -l ../build/game.lbl -L ../build/game.lst main.asm "$@")
ls -l build/game.prg
