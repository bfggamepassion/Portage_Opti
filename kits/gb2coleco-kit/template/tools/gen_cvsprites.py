"""Sprites ColecoVision (TMS9918A : 16x16, une couleur chacun, 4 par ligne).

Une image GB (3 teintes) devient des couches d'une couleur, chacune découpée
en sprites 16x16 :
- joueurs : couche « contour » (teintes 2 et 3) dans la couleur du joueur,
  couche « clair » (teinte 1) en blanc ; 2 colonnes x 2 rangées au plus par
  couche, soit 8 sprites (et 4 au plus sur une même ligne) ;
- balle (3 tailles), ombre, marque : 1 sprite.
Les sprites vides ne sont pas gardés ; les motifs identiques sont partagés.

Numéros d'images (comme les autres versions) : 0-19 joueur 1, 20-39 joueur 2,
40-42 balle, 43 ombre, 44 marque.
Format (gfx/sprites.asm) :
  spr_img : DW adresse de chaque image
  image   : DB n, puis n x (DB dx, dy, couleur ; DW motif)
            dx, dy : coin haut-gauche du sprite depuis le point d'ancrage (signés)
  spr_blk : motifs de 32 octets (ordre du TMS : colonne gauche 16 lignes,
            puis colonne droite)
Sortie : gfx/sprites.asm, build/sprites_preview.png
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import extract_sprites as es  # noqa: E402
import tms  # noqa: E402

TILE_SPRITES = [(0x31, -6, -3), (0x37, -6, -3), (0x38, -6, -3),   # balle (tuile, dy, dx)
                (0x22, -8, -3),                                     # ombre
                (0x2F, -5, -3)]                                     # marque
# couches : (teintes GB, couleur TMS)
P1_LAYERS = [((2, 3), tms.DRED), ((1,), tms.WHITE)]
P2_LAYERS = [((2, 3), tms.DBLUE), ((1,), tms.WHITE)]
BALL_LAYERS = [((1, 2, 3), tms.WHITE)]
SHADOW_LAYERS = [((1, 2, 3), tms.BLACK)]
MARK_LAYERS = [((1, 2, 3), tms.DGREEN)]
MAX_SPR = {'player': 8, 'small': 1}


def block(pix, ox, oy):
    """Motif 16x16 (32 octets, ordre TMS) des pixels (ox.., oy..) de l'ensemble pix."""
    data = bytearray(32)
    for y in range(16):
        for x in range(16):
            if (ox + x, oy + y) in pix:
                k = (x // 8) * 16 + y
                data[k] |= 0x80 >> (x % 8)
    return bytes(data)


def split(pix, layers):
    """Image {(x, y): teinte} -> sprites [(dx, dy, couleur, motif)]."""
    out = []
    for shades, color in layers:
        pts = {p for p, s in pix.items() if s in shades}
        if not pts:
            continue
        x0 = min(x for x, _ in pts)
        y0 = min(y for _, y in pts)
        for dy in (0, 16):
            for dx in (0, 16):
                b = block(pts, x0 + dx, y0 + dy)
                if any(b):
                    out.append((x0 + dx, y0 + dy, color, b))
    return out


def images():
    frames = json.load(open(os.path.join(ROOT, 're', 'sprites.json')))
    imgs = []
    for pl, layers in (('j1', P1_LAYERS), ('j2', P2_LAYERS)):
        for f in frames[pl]['frames']:
            pix = es.render([tuple(i) for i in f])
            s = split(pix, layers)
            assert len(s) <= MAX_SPR['player']
            imgs.append(s)
    for (t, dy, dx), layers in zip(TILE_SPRITES, (BALL_LAYERS,) * 3 + (SHADOW_LAYERS, MARK_LAYERS)):
        px = es.tile_px(t)
        pix = {(dx + x, dy + y): px[y][x] for y in range(8) for x in range(8) if px[y][x]}
        s = split(pix, layers)
        assert len(s) == 1
        imgs.append(s)
    return imgs


def main():
    imgs = images()
    blocks = {}
    for s in imgs:
        for _, _, _, b in s:
            blocks.setdefault(b, len(blocks))
    out = ['; Fichier généré par tools/gen_cvsprites.py : sprites 16x16 du TMS9918A.', '',
           f'NIMAGES     equ {len(imgs)}',
           'spr_img']
    for k in range(0, len(imgs), 8):
        out.append('        dw ' + ', '.join(f'spr_i{i}' for i in range(k, min(k + 8, len(imgs)))))
    for i, s in enumerate(imgs):
        out.append(f'spr_i{i}  db {len(s)}')
        for dx, dy, col, b in s:
            out.append(f'        db {dx & 0xFF}, {dy & 0xFF}, {col}')
            out.append(f'        dw spr_blk + {blocks[b] * 32}')
    out.append('spr_blk')
    for b in blocks:
        out.append('        db ' + ', '.join(f'${x:02X}' for x in b))
    open(os.path.join(ROOT, 'gfx', 'sprites.asm'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    size = len(blocks) * 32 + sum(1 + 5 * len(s) for s in imgs) + 2 * len(imgs)
    print(f'{len(imgs)} images, {len(blocks)} motifs 16x16, {size} octets')
    preview(imgs)


def preview(imgs, scale=3):
    im = Image.new('RGB', (len(imgs) * 36, 40), tms.PALETTE[tms.LGREEN])
    px = im.load()
    for i, s in enumerate(imgs):
        for dx, dy, col, b in s:
            for y in range(16):
                for x in range(16):
                    if b[(x // 8) * 16 + y] & (0x80 >> (x % 8)):
                        X, Y = i * 36 + 12 + dx + x, 30 + dy + y
                        if 0 <= X < im.width and 0 <= Y < im.height:
                            px[X, Y] = tms.PALETTE[col]
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im.save(os.path.join(ROOT, 'build', 'sprites_preview.png'))


if __name__ == '__main__':
    main()
