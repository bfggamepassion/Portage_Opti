"""Graphismes Game Boy : tuiles 2bpp, VRAM reconstituée, rendu PNG.

Méthode (Tennis) : plutôt que de deviner où sont les images, on rejoue ce que
fait le jeu : les copies de tuiles vers la VRAM et son décodeur de tilemap,
puis on rend l'écran. Les adresses se trouvent dans le désassemblage, en
cherchant les copies vers $8000-$9FFF (ou en posant un point d'arrêt
d'écriture VRAM dans un émulateur/débogueur GB comme BGB ou Emulicious).

Teintes GB : 0 = blanc ... 3 = noir (avec la palette $E4, la plus courante).
"""
from PIL import Image

SHADES = [(224, 248, 208), (136, 192, 112), (52, 104, 86), (8, 24, 32)]


def tile_pixels(data, off):
    """Tuile 2bpp de 16 octets en data[off:] -> 8 lignes de 8 teintes (0-3)."""
    rows = []
    for y in range(8):
        lo, hi = data[off + 2 * y], data[off + 2 * y + 1]
        rows.append([((lo >> (7 - x)) & 1) | (((hi >> (7 - x)) & 1) << 1) for x in range(8)])
    return rows


def sheet(rom, src, length, out_png, per_row=16, scale=3):
    """Planche des tuiles brutes rom[src:src+length] (pour repérer les graphismes)."""
    n = length // 16
    rows = (n + per_row - 1) // per_row
    img = Image.new('RGB', (per_row * 9 + 1, rows * 9 + 1), (255, 0, 255))
    for t in range(n):
        px = tile_pixels(rom, src + t * 16)
        bx, by = 1 + (t % per_row) * 9, 1 + (t // per_row) * 9
        for y in range(8):
            for x in range(8):
                img.putpixel((bx + x, by + y), SHADES[px[y][x]])
    img.resize((img.width * scale, img.height * scale), Image.NEAREST).save(out_png)


class VRAM:
    """VRAM GB ($8000-$9FFF) reconstituée à partir de la ROM."""

    def __init__(self, rom, fill_tile=0):
        self.rom = rom
        self.mem = bytearray(0x2000)
        self.mem[0x1800:0x2000] = bytes([fill_tile]) * 0x800

    def copy(self, src, dst, length):
        """Copie ROM -> VRAM (rejoue une copie de tuiles du jeu)."""
        self.mem[dst - 0x8000:dst - 0x8000 + length] = self.rom[src:src + length]

    def put_map(self, x, y, tiles, base=0x9800):
        self.mem[base - 0x8000 + y * 32 + x:base - 0x8000 + y * 32 + x + len(tiles)] = bytes(tiles)

    def tile(self, t, signed=True):
        """Pixels de la tuile de fond t (adressage $8800 signé si signed, sinon $8000)."""
        addr = 0x9000 + (t - 256 if t > 127 else t) * 16 if signed else 0x8000 + t * 16
        return tile_pixels(self.mem, addr - 0x8000)

    def map_tile(self, tx, ty, base=0x9800, signed=True):
        return self.tile(self.mem[base - 0x8000 + ty * 32 + tx], signed)

    def render(self, out_png, signed=True, base=0x9800, w=20, h=18, scale=3):
        img = Image.new('RGB', (w * 8, h * 8))
        for ty in range(h):
            for tx in range(w):
                px = self.map_tile(tx, ty, base, signed)
                for y in range(8):
                    for x in range(8):
                        img.putpixel((tx * 8 + x, ty * 8 + y), SHADES[px[y][x]])
        img.resize((img.width * scale, img.height * scale), Image.NEAREST).save(out_png)


def sprite_from_oam_list(rom, entries, tile_base=0x8000, vram=None):
    """Assemble un sprite matériel : entries = [(dy, dx, tuile, attributs)...]
    (format OAM relatif, à adapter aux listes du jeu). Renvoie {(x, y): teinte}
    sans les pixels transparents (teinte 0). Bits d'attributs : 5 = miroir X,
    6 = miroir Y. vram : VRAM reconstituée, sinon tuiles lues dans rom à tile_base."""
    pix = {}
    for dy, dx, t, at in entries:
        data = vram.mem if vram else rom
        off = (tile_base - 0x8000 if vram else tile_base) + t * 16
        px = tile_pixels(data, off)
        for y in range(8):
            for x in range(8):
                c = px[7 - y if at & 0x40 else y][7 - x if at & 0x20 else x]
                if c:
                    pix[(dx + x, dy + y)] = c
    return pix
