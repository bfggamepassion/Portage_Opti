#!/bin/sh
# Capture d'écran automatique dans Caprice32 (CPC 6128) :
#   sh tools/cpcshot.sh [délais] [sortie.png] [touches après chargement]
# Lance RUN"<GAME>", attend N fois CAP32_DELAY, capture l'écran et quitte.
cd "$(dirname "$0")/.."
N="${1:-10}"
OUT="${2:-build/shot.png}"
KEYS="${3:-}"
GAME=$(python -c "import sys; sys.path.insert(0, 'tools'); import port_config as p; print(p.GAME)")
DSK="build/$GAME.dsk"
CAP="$LOCALAPPDATA/Caprice32/cap32-win64/cap32.exe"
TMP="$TEMP/cpcshots"
rm -rf "$TMP"; mkdir -p "$TMP"
D=""
i=0
while [ $i -lt "$N" ]; do D="$D\(CAP32_DELAY)"; i=$((i+1)); done
CMD=$(printf 'run"%s\n%s%s\(CAP32_SCRNSHOT)\(CAP32_EXIT)' "$GAME" "$D" "$KEYS")
DSKW=$(cygpath -w "$PWD/$DSK")
OUTP="$PWD/$OUT"
cd "$(dirname "$CAP")"
timeout 600 "$CAP" -O system.model=2 $CAPOPT -O "file.sdump_dir=$(cygpath -w "$TMP")" -a "$CMD" "$DSKW" > "$TMP/log.txt" 2>&1
cp "$TMP"/screenshot_*.png "$OUTP" && echo "capture : $OUT"
