"""Extraction des images d'animation (métasprites) des joueurs.

Chaque image est une liste d'entrées OAM relatives (dy, dx, tuile, attributs)
terminée par $80 (routine d'affichage $305A / $0063). Les tables de pointeurs
sont indexées par l'image courante du joueur ($C001 / $C021).
Sortie : gfx/sprites_j1.png, gfx/sprites_j2.png et sprites.json.
"""
import json
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
ROM = open(os.path.join(HERE, '..', 're', 'game.gb'), 'rb').read()
OUT = os.path.join(HERE, '..', 'build', 'gfx_re')
TILES = 0x62D6          # tuiles de sprites copiées en $8000 au démarrage
SHADES = [None, (136, 192, 112), (52, 104, 86), (8, 24, 32)]  # 0 = transparent

TABLES = {'j1': 0x4887, 'j2': 0x4AA8}


def w(a):
    return ROM[a] | (ROM[a + 1] << 8)


def read_table(base):
    ptrs = []
    a = base
    lowest = 0x10000
    while a < lowest:
        p = w(a)
        if not (0x3A59 <= p < 0x8000):
            break
        ptrs.append(p)
        lowest = min(lowest, p)
        a += 2
    return ptrs


def read_list(p):
    items = []
    while ROM[p] != 0x80:
        dy, dx, tile, attr = ROM[p], ROM[p + 1], ROM[p + 2], ROM[p + 3]
        items.append((dy - 256 if dy > 127 else dy, dx - 256 if dx > 127 else dx, tile, attr))
        p += 4
    return items


def tile_px(t):
    off = TILES + t * 16
    return [[((ROM[off + 2 * y] >> (7 - x)) & 1) | (((ROM[off + 2 * y + 1] >> (7 - x)) & 1) << 1)
             for x in range(8)] for y in range(8)]


def render(items):
    """Rend une image : dict (x, y) -> teinte, origine au point de référence."""
    pix = {}
    for dy, dx, tile, attr in items:
        px = tile_px(tile)
        for y in range(8):
            for x in range(8):
                sx = 7 - x if attr & 0x20 else x
                sy = 7 - y if attr & 0x40 else y
                c = px[sy][sx]
                if c:
                    pix[(dx + x, dy + y)] = c
    return pix


def main():
    data = {}
    for name, base in TABLES.items():
        ptrs = read_table(base)
        frames = [read_list(p) for p in ptrs]
        data[name] = {'table': base, 'frames': [[list(i) for i in f] for f in frames]}
        cell, cols, scale = 48, 8, 3
        rows = (len(frames) + cols - 1) // cols
        img = Image.new('RGB', (cols * cell, rows * (cell + 10)), (224, 248, 208))
        d = ImageDraw.Draw(img)
        for i, f in enumerate(frames):
            ox, oy = (i % cols) * cell, (i // cols) * (cell + 10)
            d.text((ox + 2, oy), f'{i:02x}', fill=(200, 0, 0))
            pix = render(f)
            # point de référence (pieds) au centre-bas de la case
            for (x, y), c in pix.items():
                X, Y = ox + cell // 2 + x, oy + 10 + cell - 12 + y
                if 0 <= X < img.width and 0 <= Y < img.height:
                    img.putpixel((X, Y), SHADES[c])
            d.point((ox + cell // 2, oy + 10 + cell - 12), fill=(255, 0, 0))
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
        img.save(os.path.join(OUT, f'sprites_{name}.png'))
        print(name, len(frames), 'images')
    json.dump(data, open(os.path.join(HERE, '..', 're', 'sprites.json'), 'w'), indent=0)


if __name__ == '__main__':
    main()
