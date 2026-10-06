#!/bin/sh
# Version Thomson MO5 : traduit la logique depuis la ROM GB (6809), génère
# les graphismes, assemble avec asm6809 et fabrique la cassette
# build/tennis.k7 (LOADM"",,R). « sh build.sh AUTOPLAY » : le robot joue.
set -e
cd "$(dirname "$0")"
ASM="${ASM6809:-$LOCALAPPDATA/asm6809/asm6809-2.17-w64/asm6809.exe}"
mkdir -p build
AUTO=0
[ "$1" = "AUTOPLAY" ] && AUTO=1
echo "AUTOPLAY    equ $AUTO" > src/config.asm
python -X utf8 tools/gb2m6809.py
python -X utf8 tools/gen_mo5gfx.py
cd src
"$ASM" -B -o ../build/tennis.bin -l ../build/tennis.lst -s ../build/tennis.sym main.asm
"$ASM" -C -e start -o ../build/tennis.lm main.asm
cd ..
python -X utf8 tools/make_k7.py build/tennis.lm build/tennis.k7 TENNIS
ls -l build/tennis.bin build/tennis.k7
