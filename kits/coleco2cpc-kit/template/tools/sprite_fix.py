"""Motifs de sprites redessinés pour le mode 0 (appliqués à la ROM par
gen_tables.py, comme la police fine).

La conversion 2:1 fusionne chaque paire de pixels Coleco : les détails d'un
pixel (yeux et bouche d'Anna Lee, dessinés par le sprite des cheveux devant
celui de la peau) s'y mélangent en une bande rouge. On redessine ces motifs
directement en pixels CPC (8 par ligne, « # » = allumé) ; chaque pixel CPC
devient deux pixels Coleco identiques, que la conversion rend sans perte
(et le miroir que fait le jeu pour la marche à gauche reste aligné).

Les dessins sont dans gfx/sprites_cpc.json (adresse ROM en hexa -> 16
lignes de 8 pixels), écrit par l'éditeur (tools/sprite_editor.py).
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
DATA = os.path.join(ROOT, 'gfx', 'sprites_cpc.json')

# Motifs de sprites de la cartouche : bloc contigu de 41 motifs 16x16 en
# $9053-$9572. Numéro VRAM : n = 4k pour les 23 premiers (Anna Lee, tournée
# à droite ; le jeu fabrique les miroirs en n + $5C), puis $B8 + 4(k - 23).
BLOCK_ADDR = 0x9053
BLOCK_COUNT = 41


def block_n(k):
    return 4 * k if k < 23 else 0xB8 + 4 * (k - 23)


def load():
    """{décalage ROM ($8000 = 0): 16 lignes de 8 caractères}"""
    if not os.path.exists(DATA):
        return {}
    raw = json.load(open(DATA, encoding='utf-8'))
    return {int(a, 16) - 0x8000: rows for a, rows in raw.items()}


def save(fix):
    """fix : {adresse ROM (int): lignes} -> gfx/sprites_cpc.json"""
    data = {'%04X' % a: fix[a] for a in sorted(fix)}
    tmp = DATA + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, DATA)


def expand(row):
    """8 pixels CPC -> 16 pixels Coleco (mot, bit 15 = gauche)."""
    v = 0
    for i, ch in enumerate(row):
        if ch == '#':
            v |= 3 << (14 - 2 * i)
    return v


def apply(rom):
    """rom : bytearray de la cartouche ($8000 = 0). Motif de sprite 16x16 :
    16 octets de la moitié gauche, puis 16 de la moitié droite."""
    for off, rows in load().items():
        assert len(rows) == 16 and all(len(r) == 8 for r in rows), hex(off)
        for y, r in enumerate(rows):
            v = expand(r)
            rom[off + y] = v >> 8
            rom[off + 16 + y] = v & 0xFF
