"""Composition d'écrans Spectrum (titre, décor) en Python.

  s = Screen()                        # 256x192 pixels + 32x24 attributs
  s.gb_tile(col, row, pixels)         # tuile GB (teintes >= 2 -> encre)
  s.text(row, col, 'HELLO', ink)      # police de la ROM Spectrum (via skoolkit)
  s.big_text(x, y, 'ZX', scale=4)     # police agrandie (grasse)
  s.attr_rect(row, col, h, w, attr(INK, PAPER))
  s.save_scr('asm/gfx/title.scr')     # écran de chargement (bloc SCREEN$)
  s.save_rle_asm('asm/gfx/title.asm', 'title_rle')   # pour asm/src/unrle.asm
  s.preview('asm/build/title.png')

Rappel : 2 couleurs par case de 8x8 (attribut : FLASH, BRIGHT, PAPER, INK).
"""
import os

from PIL import Image

BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = range(8)
PALETTE = [
    [(0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205), (0, 205, 0), (0, 205, 205), (205, 205, 0), (205, 205, 205)],
    [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255), (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)],
]


def attr(ink, paper, bright=True, flash=False):
    return (0x80 if flash else 0) | (0x40 if bright else 0) | (paper << 3) | ink


def rom_font():
    from skoolkit import ROM48
    rom = open(ROM48, 'rb').read()
    return lambda ch: rom[0x3D00 + (ord(ch) - 32) * 8:0x3D00 + (ord(ch) - 32) * 8 + 8]


def scr_addr(y):
    """Adresse (relative à $4000) de la ligne de pixels y."""
    return ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)


class Screen:
    def __init__(self, fill=attr(WHITE, BLACK)):
        self.pix = [[0] * 256 for _ in range(192)]
        self.att = [[fill] * 32 for _ in range(24)]
        self.glyph = rom_font()

    def gb_tile(self, col, row, px, threshold=2, a=None):
        for y in range(8):
            for x in range(8):
                self.pix[row * 8 + y][col * 8 + x] = 1 if px[y][x] >= threshold else 0
        if a is not None:
            self.att[row][col] = a

    def text(self, row, col, s, ink=WHITE, paper=BLACK, bright=True):
        for k, ch in enumerate(s):
            gl = self.glyph(ch)
            for y in range(8):
                for x in range(8):
                    self.pix[row * 8 + y][(col + k) * 8 + x] = 1 if gl[y] & (0x80 >> x) else 0
            self.att[row][col + k] = attr(ink, paper, bright)

    def big_text(self, x0, y0, s, scale=4, bold=True):
        for k, ch in enumerate(s):
            gl = [b | (b >> 1) if bold else b for b in self.glyph(ch)]
            for y in range(8):
                for x in range(8):
                    if gl[y] & (0x80 >> x):
                        for dy in range(scale):
                            for dx in range(scale):
                                self.pix[y0 + y * scale + dy][x0 + (k * 8 + x) * scale + dx] = 1

    def attr_rect(self, row, col, h, w, a):
        for r in range(row, row + h):
            for c in range(col, col + w):
                self.att[r][c] = a

    def clear_cell(self, row, col):
        for y in range(8):
            for x in range(8):
                self.pix[row * 8 + y][col * 8 + x] = 0

    def to_bytes(self):
        data = bytearray(6912)
        for y in range(192):
            a = scr_addr(y)
            for cx in range(32):
                b = 0
                for x in range(8):
                    if self.pix[y][cx * 8 + x]:
                        b |= 0x80 >> x
                data[a + cx] = b
        for r in range(24):
            for c in range(32):
                data[6144 + r * 32 + c] = self.att[r][c]
        return data

    def save_scr(self, path):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        open(path, 'wb').write(self.to_bytes())

    def save_rle_asm(self, path, label):
        packed = rle(self.to_bytes())
        lines = [f'; Fichier généré : écran compressé (RLE, voir unrle.asm), {len(packed)} octets.',
                 f'{label}:']
        for k in range(0, len(packed), 16):
            lines.append('        db ' + ', '.join(f'${b:02X}' for b in packed[k:k + 16]))
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
        return len(packed)

    def preview(self, path, scale=3):
        im = Image.new('RGB', (256, 192))
        for y in range(192):
            for x in range(256):
                a = self.att[y // 8][x // 8]
                p = PALETTE[(a >> 6) & 1]
                im.putpixel((x, y), p[a & 7] if self.pix[y][x] else p[(a >> 3) & 7])
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        im.resize((256 * scale, 192 * scale), Image.NEAREST).save(path)


def rle(data):
    """Paquets : n (1-127) + n octets littéraux, ou $80+n (n 3-127) + octet
    répété n fois. $00 : fin. (Écran titre de Tennis : 6912 -> ~1300 octets.)"""
    out = bytearray()
    lit = bytearray()

    def flush():
        nonlocal lit
        while lit:
            out.append(len(lit[:127]))
            out.extend(lit[:127])
            lit = lit[127:]
    i = 0
    while i < len(data):
        j = i
        while j < len(data) and data[j] == data[i] and j - i < 127:
            j += 1
        if j - i >= 3:
            flush()
            out += bytes([0x80 | (j - i), data[i]])
            i = j
        else:
            lit.append(data[i])
            i += 1
    flush()
    out.append(0)
    return out
