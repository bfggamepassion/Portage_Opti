#!/bin/sh
# Lance le jeu dans Caprice32 (CPC 6128) pour l'utilisateur : RUN"<GAME>"
# tapé automatiquement. À lancer depuis bash (PowerShell perd les guillemets
# de la commande tapée : « runGAME » -> Syntax error).
cd "$(dirname "$0")"
GAME=$(python -c "import sys; sys.path.insert(0, 'tools'); import port_config as p; print(p.GAME)")
DSKW=$(cygpath -w "$PWD/build/$GAME.dsk")
cd "$LOCALAPPDATA/Caprice32/cap32-win64" && (./cap32.exe -O system.model=2 -a "$(printf 'run"%s\n' "$GAME")" "$DSKW" > /dev/null 2>&1 &)
echo "Caprice32 lancé : build/$GAME.dsk"
