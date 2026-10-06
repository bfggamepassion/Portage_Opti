"""Décor CPC : le stade du Tennis GB (tilemap $6F16 + arbitre $5180), à l'échelle 1.

Mode 1 (320x200, 4 encres) : les 4 teintes du Game Boy deviennent les 4
encres du CPC, sans perte (teinte n -> encre n). Une tuile GB 8x8 = 16
octets en mode 1 (2 octets par ligne de 8 pixels). Le jeu affiche 25
rangées GB (2 à 26) sur toute la largeur GB (256 pixels), colonnes CPC 4-35
(en caractères de 8 pixels) ; les colonnes 0-3 et 36-39 reçoivent le score.

Octet mode 1 : 4 pixels ; pixel i (0 = gauche) : bit 7-i = bit 0 de l'encre,
bit 3-i = bit 1 de l'encre.
Sorties : gfx/court.asm (tuiles, carte), build/court_preview.png
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gbgfx import VRAM  # noqa: E402

ROOT = os.path.join(HERE, '..')
ROM = open(os.path.join(ROOT, 're', 'game.gb'), 'rb').read()
FIRST_ROW = 2
ROWS = 25

# Couleurs matérielles du CPC (valeur envoyée au Gate Array, bit 6 compris)
HW = {'black': 0x54, 'blue': 0x44, 'bright_blue': 0x55, 'red': 0x5C, 'magenta': 0x58,
      'mauve': 0x5D, 'bright_red': 0x4C, 'purple': 0x45, 'bright_magenta': 0x4D,
      'green': 0x56, 'cyan': 0x46, 'sky_blue': 0x57, 'yellow': 0x5E, 'white': 0x40,
      'pastel_blue': 0x5F, 'orange': 0x4E, 'pink': 0x47, 'pastel_magenta': 0x4F,
      'bright_green': 0x52, 'sea_green': 0x42, 'bright_cyan': 0x53, 'lime': 0x5A,
      'pastel_green': 0x59, 'pastel_cyan': 0x5B, 'bright_yellow': 0x4A,
      'pastel_yellow': 0x43, 'bright_white': 0x4B}
RGB = {'black': (0, 0, 0), 'green': (0, 128, 0), 'bright_green': (0, 255, 0),
       'pastel_green': (128, 255, 128), 'lime': (128, 255, 0), 'white': (128, 128, 128),
       'bright_white': (255, 255, 255), 'sea_green': (0, 255, 128), 'yellow': (128, 128, 0),
       'bright_yellow': (255, 255, 0), 'bright_red': (255, 0, 0), 'blue': (0, 0, 128)}
# Encres du court : teinte GB 0 (la plus claire) à 3 (la plus foncée)
INKS = ['pastel_green', 'bright_green', 'green', 'black']
BORDER = 'black'


def tennis_tilemap(v, hl, de=0x9800, c=1):
    """Décodeur de tilemap du jeu ($326B) : $F9 00 fin, $F9 02 n v répétition,
    $F9 pas adresse : nouveau pas et nouvelle destination."""
    while True:
        a = ROM[hl]; hl += 1
        if a != 0xF9:
            v.mem[de - 0x8000] = a
            de += c
            continue
        a = ROM[hl]; hl += 1
        if a == 0x02:
            n, val = ROM[hl], ROM[hl + 1]; hl += 2
            for _ in range(n):
                v.mem[de - 0x8000] = val
                de += c
            continue
        if a == 0:
            return
        c = a
        de = ROM[hl] | (ROM[hl + 1] << 8); hl += 2


def court_vram():
    v = VRAM(ROM, fill_tile=0x80)
    v.copy(0x62D6, 0x8000, 0x800)
    v.copy(0x5AD6, 0x8800, 0x800)
    v.copy(0x52D6, 0x9000, 0x800)
    tennis_tilemap(v, 0x6F16)
    tennis_tilemap(v, 0x5180)
    return v


def mode1_bytes(row):
    """8 pixels (encres 0-3) -> 2 octets mode 1."""
    out = []
    for k in (0, 4):
        b = 0
        for i in range(4):
            ink = row[k + i]
            b |= (ink & 1) << (7 - i)
            b |= ((ink >> 1) & 1) << (3 - i)
        out.append(b)
    return out


def tile_mode1(px):
    return bytes(b for row in px for b in mode1_bytes(row))


def main():
    v = court_vram()
    tiles = {}
    tmap = []
    for r in range(ROWS):
        row = []
        for gx in range(32):
            data = tile_mode1(v.map_tile(gx, FIRST_ROW + r))
            if data not in tiles:
                tiles[data] = len(tiles)
            row.append(tiles[data])
        tmap.append(row)
    print(f'décor : {len(tiles)} tuiles ({len(tiles) * 16} octets)')
    out = ['; Fichier généré par tools/gen_cpcgfx.py : décor du stade (tuiles du Tennis GB, mode 1).', '',
           f'COURT_NTILES = {len(tiles)}',
           'court_inks   db ' + ', '.join(f'${HW[i]:02X}' for i in INKS),
           f'COURT_BORDER = ${HW[BORDER]:02X}',
           'court_tiles']
    for data in tiles:
        out.append('        db ' + ', '.join(f'${b:02X}' for b in data))
    out.append('court_map                       ; 25 rangées x 32 tuiles')
    for row in tmap:
        out.append('        db ' + ', '.join(str(t) for t in row))
    open(os.path.join(ROOT, 'gfx', 'court.asm'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    lines = ['; Fichier généré par tools/gen_cpcgfx.py : adresse écran de chaque ligne (écran en $4000).',
             'line_tab']
    for y in range(0, 200, 8):
        lines.append('        dw ' + ', '.join(f'${0x4000 + (yy & 7) * 0x800 + (yy >> 3) * 80:04X}'
                                          for yy in range(y, y + 8)))
    open(os.path.join(ROOT, 'gfx', 'lines.asm'), 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    preview(v)


def preview(v, scale=2):
    im = Image.new('RGB', (320, 200), RGB[BORDER])
    px = im.load()
    for r in range(ROWS):
        for gx in range(32):
            t = v.map_tile(gx, FIRST_ROW + r)
            for y in range(8):
                for x in range(8):
                    px[32 + gx * 8 + x, r * 8 + y] = RGB[INKS[t[y][x]]]
    os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
    im.resize((640, 400), Image.NEAREST).save(os.path.join(ROOT, 'build', 'court_preview.png'))


if __name__ == '__main__':
    main()
