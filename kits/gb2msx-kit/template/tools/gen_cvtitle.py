"""Écran de présentation MSX (mode 2) : « MSX » en grandes lettres
(police du Tennis GB x2, un dégradé de couleurs ligne par ligne), puis la
bande TENNIS de l'écran titre GB (tuiles $71B4, tilemap $76B4), prolongée
sur toute la largeur. Les rangées 14-23 reçoivent le menu (texte).

Sortie : gfx/title.asm (motifs et couleurs par tiers, carte des rangées
0-TITLE_ROWS-1, 32 colonnes ; les autres rangées : espaces), build/title_preview.png
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_cvgfx as cg  # noqa: E402
import tms  # noqa: E402

ROOT = os.path.join(HERE, '..')
BAND_ROW = 5                    # rangée de la 1re rangée de la bande
BAND_COL = 6                    # colonne de la colonne GB 0 (bande GB : 20 colonnes)
LOGO_ROWS = range(1, 10)        # rangées GB : filet haut ... poignées des raquettes
EXTEND = {1: 0xB1, 8: 0xB2, 9: 0x80}   # prolongement hors du logo (sinon $81)
BAND_SHADE = [tms.LGREEN, tms.MGREEN, tms.WHITE, tms.BLACK]
BIG_WORD, BIG_Y, BIG = 'MSX', 4, 3     # mot, ligne du haut, agrandissement
BIG_GRADIENT = ([tms.WHITE] * 2 + [tms.LYELLOW] * 4 + [tms.DYELLOW] * 4 + [tms.LRED] * 4 +
                [tms.MRED] * 4 + [tms.DRED] * 3 + [tms.MAGENTA] * 3)
TITLE_ROWS = 14


def main():
    v = cg.title_vram()
    img = [[tms.BLACK] * 256 for _ in range(TITLE_ROWS * 8)]
    for i, gy in enumerate(LOGO_ROWS):
        for c in range(32):
            gx = c - BAND_COL
            t = v.mem[0x1800 + gy * 32 + gx] if 0 <= gx < 20 else EXTEND.get(gy, 0x81)
            px = v.tile(t)
            for y in range(8):
                for x in range(8):
                    s = px[y][x]
                    col = BAND_SHADE[s]
                    if gy == 9 and s == 0:              # sous la bande : fond noir
                        col = tms.BLACK
                    img[(BAND_ROW + i) * 8 + y][c * 8 + x] = col
    # grandes lettres : police GB en gras, agrandie BIG fois
    size = 8 * BIG
    width = len(BIG_WORD) * size + (len(BIG_WORD) - 1) * 8
    x0 = (256 - width) // 2 // 8 * 8
    for k, ch in enumerate(BIG_WORD):
        px = v.tile(0xDA + ord(ch) - ord('A'))
        px = [[bool(r[x] or (x > 0 and r[x - 1])) for x in range(8)] for r in px]
        for y in range(size):
            for x in range(size):
                if px[y // BIG][x // BIG]:
                    img[BIG_Y + y][x0 + k * (size + 8) + x] = BIG_GRADIENT[y]
    # tuiles par tiers
    thirds = [{} for _ in range(3)]
    tmap = []
    for r in range(TITLE_ROWS):
        row = []
        for c in range(32):
            pats, cols, _ = tms.encode_tile([img[r * 8 + y][c * 8:c * 8 + 8] for y in range(8)])
            if not any(pats) and all(cc & 15 == tms.BLACK for cc in cols):
                row.append(cg.FONT_BASE)                # noir : l'espace de la police
                continue
            u = thirds[r // 8]
            key = pats + cols
            if key not in u:
                u[key] = len(u)
            row.append(u[key])
        tmap.append(row)
    for k, u in enumerate(thirds):
        assert len(u) <= cg.FONT_BASE, f'tiers {k} : {len(u)} motifs'
    out = ['; Fichier généré par tools/gen_cvtitle.py : écran de présentation (mode 2).', '',
           f'TITLE_ROWS  equ {TITLE_ROWS}']
    for k, u in enumerate(thirds):
        out.append(f'TITLE_N{k}    equ {len(u)}')
    for k, u in enumerate(thirds):
        out.append(f'title_pat{k}')
        if u:
            out += cg.db_lines(b''.join(t[:8] for t in u))
        out.append(f'title_col{k}')
        if u:
            out += cg.db_lines(b''.join(t[8:] for t in u))
    out.append('title_map')
    for row in tmap:
        out += cg.db_lines(bytes(row), 32)
    open(os.path.join(ROOT, 'gfx', 'title.asm'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('écran titre : ' + ', '.join(f'tiers {k} {len(u)} motifs' for k, u in enumerate(thirds)))
    im = Image.new('RGB', (256, 192))
    p = im.load()
    for r in range(TITLE_ROWS):
        for c in range(32):
            t = tmap[r][c]
            if t == cg.FONT_BASE:
                continue
            key = list(thirds[r // 8])[t]
            d = tms.decode_tile(key[:8], key[8:])
            for y in range(8):
                for x in range(8):
                    p[c * 8 + x, r * 8 + y] = tms.PALETTE[d[y][x]]
    im.resize((512, 384), Image.NEAREST).save(os.path.join(ROOT, 'build', 'title_preview.png'))


if __name__ == '__main__':
    main()
