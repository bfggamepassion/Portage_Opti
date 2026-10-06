"""Décor ColecoVision : le stade du Tennis GB (comme les versions CPC), en mode
graphique 2 du TMS9918A (256x192, 2 couleurs par ligne de 8 pixels).

- Le stade GB fait 256 pixels de large : il remplit l'écran. 24 rangées GB
  (2 à 25) sont affichées : y écran = y GB - 16.
- Teintes GB 0-3 -> vert clair, vert, vert foncé, noir (TMS 3, 2, 12, 1).
  Une ligne de 8 pixels à plus de 2 teintes garde la paire la plus fidèle.
- Le mode 2 découpe l'écran en 3 tiers de 8 rangées, chacun avec ses 256
  motifs : tuiles du décor à partir de 0, police en FONT_BASE-255 (codes
  32-95 : motif = code + FONT_BASE - 32), dans chaque tiers.
Sorties : gfx/court.asm (motifs et couleurs par tiers, carte 32x24),
gfx/font.asm, build/court_preview.png
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tms  # noqa: E402
import gen_cpcgfx as g  # noqa: E402  (VRAM GB du stade, décodeur de tilemap)

ROOT = os.path.join(HERE, '..')
FIRST_ROW = 2
ROWS = 24
SHADE = [tms.LGREEN, tms.MGREEN, tms.DGREEN, tms.BLACK]
FONT_BASE = 192                 # motifs 192-255 : caractères 32-95
TEXT_FG, TEXT_BG = tms.WHITE, tms.BLACK

EXTRA = {                       # signes absents de la police GB (8 lignes de 8 pixels)
    '-': ['', '', '', '######', '', '', '', ''],
    '/': ['      #', '     #', '    #', '   #', '  #', ' #', '#', ''],
    ':': ['', '  ##', '  ##', '', '', '  ##', '  ##', ''],
    '.': ['', '', '', '', '', '  ##', '  ##', ''],
    ',': ['', '', '', '', '', '  ##', '  ##', ' ##'],
    '!': ['  ##', '  ##', '  ##', '  ##', '  ##', '', '  ##', ''],
    '>': [' #', '  #', '   #', '    #', '   #', '  #', ' #', ''],
    '<': ['     #', '    #', '   #', '  #', '   #', '    #', '     #', ''],
    '+': ['', '   #', '   #', ' #####', '   #', '   #', '', ''],
    '(': ['   #', '  #', ' #', ' #', ' #', '  #', '   #', ''],
    ')': [' #', '  #', '   #', '   #', '   #', '  #', ' #', ''],
    "'": ['  #', '  #', ' #', '', '', '', '', ''],
    '#': ['', ' #  #', '######', ' #  #', ' #  #', '######', ' #  #', ''],
    '*': ['', ' #  #', '  ##', '######', '  ##', ' #  #', '', ''],
}


def title_vram():
    """VRAM GB de l'écran titre (police : tuiles $D0-$F3)."""
    v = g.VRAM(g.ROM, fill_tile=0x80)
    v.copy(0x62D6, 0x8000, 0x800)
    v.copy(0x5AD6, 0x8800, 0x800)
    v.copy(0x52D6, 0x9000, 0x800)
    v.copy(0x71B4, 0x8800, 0x500)
    g.tennis_tilemap(v, 0x76B4)
    return v


def font_rows():
    """64 caractères (codes 32-95) : 8 octets de motif (1 = encre) chacun."""
    v = title_vram()
    out = []
    for code in range(32, 96):
        ch = chr(code)
        rows = [0] * 8
        if ch.isdigit() or ('A' <= ch <= 'Z'):
            tile = 0xD0 + int(ch) if ch.isdigit() else 0xDA + ord(ch) - ord('A')
            px = v.tile(tile)
            rows = [sum(0x80 >> x for x in range(8) if px[y][x]) for y in range(8)]
        elif ch in EXTRA:
            rows = [sum(0x80 >> x for x, c in enumerate(r) if c == '#') for r in EXTRA[ch]]
        out.append(rows)
    return out


def court_tiles():
    """-> tiers : liste de 3 (motifs, couleurs) uniques ; carte 24x32 (numéros)."""
    v = g.court_vram()
    thirds = []
    cmap = []
    total_err = 0
    for third in range(3):
        uniq = {}
        for r in range(third * 8, third * 8 + 8):
            row = []
            for c in range(32):
                t = v.map_tile(c, FIRST_ROW + r)
                pats, cols, err = tms.encode_tile([[SHADE[s] for s in line] for line in t])
                total_err += err
                key = pats + cols
                if key not in uniq:
                    uniq[key] = len(uniq)
                row.append(uniq[key])
            cmap.append(row)
        assert len(uniq) <= FONT_BASE, f'tiers {third} : {len(uniq)} tuiles'
        thirds.append(list(uniq))
    return thirds, cmap


def db_lines(data, per=16):
    return ['        db ' + ', '.join(f'${b:02X}' for b in data[k:k + per])
            for k in range(0, len(data), per)]


def main():
    thirds, cmap = court_tiles()
    out = ['; Fichier généré par tools/gen_cvgfx.py : stade du Tennis GB en mode 2.', '',
           f'FONT_BASE   equ {FONT_BASE}',
           f'TEXT_COLOR  equ ${(TEXT_FG << 4) | TEXT_BG:02X}']
    for k, tiles in enumerate(thirds):
        out.append(f'COURT_N{k}    equ {len(tiles)}')
    for k, tiles in enumerate(thirds):
        out.append(f'court_pat{k}')
        out += db_lines(b''.join(t[:8] for t in tiles))
        out.append(f'court_col{k}')
        out += db_lines(b''.join(t[8:] for t in tiles))
    out.append('court_map                   ; 24 rangées x 32 motifs')
    for row in cmap:
        out += db_lines(bytes(row), 32)
    open(os.path.join(ROOT, 'gfx', 'court.asm'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    font = font_rows()
    fo = ['; Fichier généré par tools/gen_cvgfx.py : police (codes 32-95), 1 bit par pixel.', 'font']
    for code, rows in enumerate(font, 32):
        fo.append('        db ' + ', '.join(f'${b:02X}' for b in rows) + f'   ; {chr(code)!r}')
    open(os.path.join(ROOT, 'gfx', 'font.asm'), 'w', encoding='utf-8').write('\n'.join(fo) + '\n')
    print('décor : ' + ', '.join(f'tiers {k} {len(t)} motifs' for k, t in enumerate(thirds)))
    preview(thirds, cmap)


def preview(thirds, cmap):
    im = Image.new('RGB', (256, 192))
    px = im.load()
    for r in range(24):
        for c in range(32):
            t = thirds[r // 8][cmap[r][c]]
            d = tms.decode_tile(t[:8], t[8:])
            for y in range(8):
                for x in range(8):
                    px[c * 8 + x, r * 8 + y] = tms.PALETTE[d[y][x]]
    os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
    im.resize((512, 384), Image.NEAREST).save(os.path.join(ROOT, 'build', 'court_preview.png'))


if __name__ == '__main__':
    main()
