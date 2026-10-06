"""Graphismes Game Boy -> Commodore 64 (repris de C64 Tennis).

Correspondance clé : une tuile GB 8x8 = un caractère C64 8x8. Le C64
(320x200) peut montrer une image GB de 256 pixels de large à l'échelle 1.

Caractères, mode multicolore mixte (bit 3 de la couleur de case) :
  - tuile à deux couleurs dont le fond ($D021) : caractère haute résolution,
    exact au pixel, encre = couleur de la case (0-7 seulement) ;
  - sinon : caractère multicolore, pixels doubles (on garde le plus foncé
    des deux pixels GB) : 00 = $D021, 01 = $D022, 10 = $D023, 11 = case (0-7).
Sprites : multicolores (pixels doubles, 3 couleurs : $D025, $D026, propre)
ou haute résolution (1 couleur). 24 x 21 pixels ; deux sprites empilés pour
un personnage de plus de 21 lignes.

Usage type (voir C64/tools/gen_c64gfx.py du repo Tennis pour un décor complet) :
    chars = CharSet()
    code, color = chars.add_tile(px, shade_color={0: 13, 1: 5, 2: 1, 3: 0},
                                 bg=13, mc1=5, mc2=0)
    ...
    chars.write_asm('gfx/charset.asm', 'charset')
"""
import os

from PIL import Image

# Palette C64 (Pepto)
PAL = [(0, 0, 0), (255, 255, 255), (104, 55, 43), (112, 164, 178), (111, 61, 134), (88, 141, 67),
       (53, 40, 121), (184, 199, 111), (111, 79, 37), (67, 57, 0), (154, 103, 89), (68, 68, 68),
       (108, 108, 108), (154, 210, 132), (108, 94, 181), (149, 149, 149)]
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)
ORANGE, BROWN, LIGHT_RED, DARK_GREY, GREY, LIGHT_GREEN, LIGHT_BLUE, LIGHT_GREY = range(8, 16)


def tile_to_char(px, shade_color, bg, mc1, mc2):
    """Tuile GB (8x8 teintes 0-3) -> (8 octets, couleur de case).
    shade_color : teinte GB -> couleur C64. bg/mc1/mc2 : $D021/$D022/$D023."""
    cols = {shade_color[c] for r in px for c in r}
    others = cols - {bg}
    if len(others) <= 1 and (not others or max(others) <= 7):
        ink = others.pop() if others else 0
        data = bytes(sum(0x80 >> x for x in range(8) if shade_color[px[y][x]] == ink and ink != bg)
                     for y in range(8))
        return data, ink
    cell = [c for c in cols if c not in (bg, mc1, mc2)]
    if len(cell) > 1 or (cell and cell[0] > 7):
        raise ValueError(f'tuile impossible en multicolore : couleurs {sorted(cols)}')
    cellc = cell[0] if cell else 0
    slot = {bg: 0, mc1: 1, mc2: 2, cellc: 3}
    out = []
    for y in range(8):
        b = 0
        for fx in range(4):
            s = max(px[y][2 * fx], px[y][2 * fx + 1])     # le plus foncé
            b |= slot[shade_color[s]] << (6 - 2 * fx)
        out.append(b)
    return bytes(out), 8 | cellc


class CharSet:
    """Jeu de caractères dédoublonné (256 au plus)."""

    def __init__(self):
        self.chars = {}

    def add(self, data):
        if data not in self.chars:
            if len(self.chars) >= 256:
                raise ValueError('plus de 256 caractères')
            self.chars[data] = len(self.chars)
        return self.chars[data]

    def add_tile(self, px, shade_color, bg, mc1, mc2):
        data, color = tile_to_char(px, shade_color, bg, mc1, mc2)
        return self.add(data), color

    def data(self, size=2048):
        out = bytearray(size)
        for d, code in self.chars.items():
            out[code * 8:code * 8 + 8] = d
        return out

    def write_asm(self, path, label):
        write_bytes_asm(path, label, self.data())


def write_bytes_asm(path, label, data, per_line=16, head='Fichier généré.'):
    rows = [data[k:k + per_line] for k in range(0, len(data), per_line)]
    out = [f'; {head}', label] + ['        .byte ' + ', '.join(f'${b:02X}' for b in r) for r in rows]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')


def mc_sprite(pix, x0, y0, code={0: 0, 3: 1, 1: 3, 2: 2}):
    """Sprite multicolore 24x21 depuis {(x, y): teinte GB}, coin (x0, y0).
    code : teinte -> 00 transparent, 01 $D025, 10 couleur propre, 11 $D026."""
    data = bytearray(63)
    for row in range(21):
        for fx in range(12):
            s = max(pix.get((x0 + 2 * fx, y0 + row), 0), pix.get((x0 + 2 * fx + 1, y0 + row), 0))
            data[row * 3 + fx // 4] |= code[s] << (6 - 2 * (fx % 4))
    return data


def hires_sprite(pix, x0, y0, test=lambda s: s > 0):
    """Sprite haute résolution 24x21 : pixels pour lesquels test(teinte) est vrai."""
    data = bytearray(63)
    for (x, y), s in pix.items():
        x, y = x - x0, y - y0
        if test(s) and 0 <= x < 24 and 0 <= y < 21:
            data[y * 3 + x // 8] |= 0x80 >> (x % 8)
    return data


def preview_screen(path, charset, screen, color, bg, mc1, mc2, scale=2):
    """Aperçu PNG d'un écran caractères (screen/color : 25 listes de 40)."""
    im = Image.new('RGB', (320, 200))
    px = im.load()
    for r in range(25):
        for c in range(40):
            ch, col = screen[r][c], color[r][c]
            for y in range(8):
                b = charset[ch * 8 + y]
                if col & 8:
                    for fx in range(4):
                        v = (b >> (6 - 2 * fx)) & 3
                        rgb = PAL[[bg, mc1, mc2, col & 7][v]]
                        px[c * 8 + 2 * fx, r * 8 + y] = rgb
                        px[c * 8 + 2 * fx + 1, r * 8 + y] = rgb
                else:
                    for x in range(8):
                        px[c * 8 + x, r * 8 + y] = PAL[col & 7] if b & (0x80 >> x) else PAL[bg]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    im.resize((320 * scale, 200 * scale), Image.NEAREST).save(path)
