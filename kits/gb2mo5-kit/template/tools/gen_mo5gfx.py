"""Graphismes MO5 : stade, police, sprites (tirés de la ROM du Tennis GB).

Écran du MO5 : 320x200, 40 octets par ligne ; pour chaque groupe de 8
pixels, un octet de forme (1 bit par pixel) et un octet de couleur
(4 bits hauts : couleur des bits à 1, 4 bits bas : couleur des bits à 0).
Même disposition que la version CPC : le stade GB (256 pixels de large,
rangées 2 à 26) occupe les colonnes 4-35 ; le score est sur les côtés.

- Stade : teintes GB 0-3 -> vert clair, vert, gris, noir. Dans chaque
  groupe de 8 pixels, la couleur la plus présente est celle des bits à 0
  (le fond) ; groupe d'une seule couleur : couleur des bits à 1 = noir.
  Un sprite qui passe met ses pixels à 1 et sa couleur dans les 4 bits hauts.
  Tuiles 8x8 uniques : 8 octets de forme puis 8 octets de couleur.
- Police : codes 32-95, 8 octets (forme) par caractère.
- Sprites : deux plans d'un bit, « masque » (pixels opaques) et « encre »
  (pixels foncés, teintes 2 et 3, dessinés dans la couleur de l'objet) ;
  les pixels clairs (teinte 1) laissent voir le fond du groupe.
  Image : FCB largeur (octets), hauteur, x0, y0 (coin haut-gauche depuis
  le point d'ancrage, signés), puis par ligne : masque, encre.
Sorties : gfx/court.asm, gfx/font.asm, gfx/sprites.asm, build/*_preview.png
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import mo5pal as P  # noqa: E402
import gen_cpcgfx as g  # noqa: E402  (VRAM GB du stade)
import gen_cvgfx as cg  # noqa: E402  (police)
import extract_sprites as es  # noqa: E402

FIRST_ROW = 2
ROWS = 25
SHADE = [P.LGREEN, P.GREEN, P.GRAY, P.BLACK]
TILE_SPRITES = [(0x31, -6, -3), (0x37, -6, -3), (0x38, -6, -3),   # balle (tuile, dy, dx)
                (0x22, -8, -3),                                     # ombre
                (0x2F, -5, -3)]                                     # marque


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(P.PALETTE[a], P.PALETTE[b]))


def encode_row(cols):
    """8 couleurs -> (forme, couleur) ; fond = couleur la plus présente."""
    order = sorted(set(cols), key=lambda c: (-cols.count(c), c))
    bg = order[0]
    fg = order[1] if len(order) > 1 else P.BLACK
    form = 0
    for x, c in enumerate(cols):
        if c != bg and (c == fg or dist(c, fg) < dist(c, bg)):
            form |= 0x80 >> x
    return form, (fg << 4) | bg


def court():
    v = g.court_vram()
    tiles = {}
    cmap = []
    for r in range(ROWS):
        row = []
        for c in range(32):
            t = v.map_tile(c, FIRST_ROW + r)
            enc = [encode_row([SHADE[s] for s in line]) for line in t]
            key = bytes(f for f, _ in enc) + bytes(k for _, k in enc)
            tiles.setdefault(key, len(tiles))
            row.append(tiles[key])
        cmap.append(row)
    return list(tiles), cmap


def sprite_planes(pix, color_shades=(2, 3)):
    """{(x, y): teinte} -> (largeur octets, hauteur, x0, y0, lignes [(masque, encre)])"""
    x0 = min(x for x, _ in pix)
    y0 = min(y for _, y in pix)
    w = max(x for x, _ in pix) - x0 + 1
    h = max(y for _, y in pix) - y0 + 1
    wb = (w + 7) // 8
    rows = []
    for y in range(h):
        mask = [0] * wb
        ink = [0] * wb
        for x in range(w):
            s = pix.get((x0 + x, y0 + y), 0)
            if s:
                mask[x // 8] |= 0x80 >> (x % 8)
                if s in color_shades:
                    ink[x // 8] |= 0x80 >> (x % 8)
        rows.append((mask, ink))
    return wb, h, x0, y0, rows


def sprites():
    frames = json.load(open(os.path.join(ROOT, 're', 'sprites.json')))
    imgs = []
    for pl in ('j1', 'j2'):
        for f in frames[pl]['frames']:
            imgs.append(sprite_planes(es.render([tuple(i) for i in f])))
    for k, (t, dy, dx) in enumerate(TILE_SPRITES):
        px = es.tile_px(t)
        pix = {(dx + x, dy + y): px[y][x] for y in range(8) for x in range(8) if px[y][x]}
        imgs.append(sprite_planes(pix, color_shades=(1, 2, 3)))    # balle, ombre, marque : unies
    return imgs


def db(data, per=16):
    return ['        fcb ' + ','.join(f'${b:02X}' for b in data[k:k + per])
            for k in range(0, len(data), per)]


def main():
    tiles, cmap = court()
    out = ['; Fichier généré par tools/gen_mo5gfx.py : stade du Tennis GB (tuiles 8x8).', '',
           f'COURT_NTILES equ {len(tiles)}',
           'court_tiles                     ; 8 octets de forme, 8 octets de couleur']
    for t in tiles:
        out += db(t)
    out.append('court_map                       ; 25 rangées x 32 tuiles')
    for row in cmap:
        out += db(bytes(row), 32)
    open(os.path.join(ROOT, 'gfx', 'court.asm'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    fo = ['; Fichier généré par tools/gen_mo5gfx.py : police (codes 32-95), 1 bit par pixel.', 'font']
    for code, rows in enumerate(cg.font_rows(), 32):
        fo.append('        fcb ' + ','.join(f'${b:02X}' for b in rows) + f'   ; {chr(code)!r}')
    open(os.path.join(ROOT, 'gfx', 'font.asm'), 'w', encoding='utf-8').write('\n'.join(fo) + '\n')
    tb = ['; Fichier généré par tools/gen_mo5gfx.py : tables.', 'rowaddr                 ; rangée de cases x 320']
    tb += ['        fdb ' + ','.join(str(r * 320) for r in range(k, min(k + 8, 25))) for k in range(0, 25, 8)]
    tb.append('sq_tab                  ; carrés (projection)')
    tb += ['        fdb ' + ','.join(str(i * i) for i in range(k, k + 8)) for k in range(0, 256, 8)]
    tb.append('ytab                    ; y = $1C + b x 40 / 47')
    tb += db(bytes((28 + (b * 40) // 47) % 256 for b in range(256)))
    tb.append('lifttab                 ; z x 6 / 16')
    tb += db(bytes((z * 6) // 16 for z in range(256)))
    open(os.path.join(ROOT, 'gfx', 'tables.asm'), 'w', encoding='utf-8').write('\n'.join(tb) + '\n')
    imgs = sprites()
    so = ['; Fichier généré par tools/gen_mo5gfx.py : sprites (masque, encre).', '',
          f'NIMAGES     equ {len(imgs)}', 'spr_img']
    for k in range(0, len(imgs), 8):
        so.append('        fdb ' + ','.join(f'spr_i{i}' for i in range(k, min(k + 8, len(imgs)))))
    size = 0
    for i, (wb, h, x0, y0, rows) in enumerate(imgs):
        so.append(f'spr_i{i}  fcb {wb},{h},{x0 & 0xFF},{y0 & 0xFF}')
        data = []
        for mask, ink in rows:
            data += mask + ink
        so += db(data, 2 * wb * 4)
        size += 4 + len(data)
    open(os.path.join(ROOT, 'gfx', 'sprites.asm'), 'w', encoding='utf-8').write('\n'.join(so) + '\n')
    print(f'stade : {len(tiles)} tuiles ({len(tiles) * 16} octets) ; sprites : {len(imgs)} images, '
          f'{size} octets')
    preview(tiles, cmap, imgs)


def preview(tiles, cmap, imgs):
    im = Image.new('RGB', (320, 200), P.PALETTE[P.BLACK])
    px = im.load()
    for r in range(ROWS):
        for c in range(32):
            t = tiles[cmap[r][c]]
            for y in range(8):
                f, k = t[y], t[8 + y]
                for x in range(8):
                    px[32 + c * 8 + x, r * 8 + y] = P.PALETTE[(k >> 4) if f & (0x80 >> x) else (k & 15)]
    im.resize((640, 400), Image.NEAREST).save(os.path.join(ROOT, 'build', 'court_preview.png'))
    sp = Image.new('RGB', (len(imgs) * 34, 36), P.PALETTE[P.LGREEN])
    q = sp.load()
    for i, (wb, h, x0, y0, rows) in enumerate(imgs):
        col = P.RED if i < 20 else P.BLUE if i < 40 else P.WHITE
        for y, (mask, ink) in enumerate(rows):
            for x in range(wb * 8):
                if ink[x // 8] & (0x80 >> (x % 8)):
                    q[i * 34 + 2 + x, 2 + y] = P.PALETTE[col]
    sp.resize((sp.width * 3, sp.height * 3), Image.NEAREST).save(
        os.path.join(ROOT, 'build', 'sprites_preview.png'))


if __name__ == '__main__':
    main()
