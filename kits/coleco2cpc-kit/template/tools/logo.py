"""Extrait le logo « Cabbage Patch Kids » de l'affiche (gfx/logo.png),
le détoure (tout ce qui est entouré par son liseré crème) et le réduit aux
encres du mode 0 : build/logo_*.png pour vérifier."""
import os, sys
from collections import deque
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)

CROP = (110, 90, 650, 330)


def is_cream(p):
    r, g, b = p[:3]
    return r > 165 and g > 165 and b > 120 and max(r, g, b) - min(r, g, b) < 90


def mask():
    im = Image.open(os.path.join(ROOT, 'gfx', 'logo.png')).convert('RGB').crop(CROP)
    w, h = im.size
    px = im.load()
    bg = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or bg[y][x] or is_cream(px[x, y]):
            continue
        bg[y][x] = True
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return im, bg


if __name__ == '__main__':
    im, bg = mask()
    out = im.copy()
    o = out.load()
    for y in range(im.height):
        for x in range(im.width):
            if bg[y][x]:
                o[x, y] = (0, 0, 0)
    out.save(os.path.join(ROOT, 'build', 'logo_mask.png'))


# --- réduction en mode 0 -------------------------------------------------------------
import cpcpal  # noqa: E402

INKS = [1, 12, 2, 3, 11, 15]          # noir, vert, vert vif, vert pastel, jaune pastel, blanc
TILES_W = 28                          # largeur en cases (4 pixels CPC chacune)


def classify(c):
    """Couleur de l'affiche -> encre : liseré crème, contour vert sombre,
    lettres vert vif, reflets vert pastel."""
    r, g, b = c[:3]
    lum = (r + g + b) / 3
    if is_cream(c) or (lum > 150 and r > 120):
        return 11 if lum < 215 else 15
    if lum < 60:
        return 12
    if lum < 125:
        return 2
    return 3


def build():
    im, bg = mask()
    w, h = im.size
    # composante principale seulement
    seen = [[False] * w for _ in range(h)]
    best = []
    for sy in range(h):
        for sx in range(w):
            if bg[sy][sx] or seen[sy][sx]:
                continue
            comp = []
            q = deque([(sx, sy)])
            seen[sy][sx] = True
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not bg[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if len(comp) > len(best):
                best = comp
    keep = Image.new('L', (w, h), 0)
    kp = keep.load()
    for x, y in best:
        kp[x, y] = 255
    box = keep.getbbox()
    im, keep = im.crop(box), keep.crop(box)
    tw = TILES_W * 4
    th = round(tw * 2 * im.height / im.width)
    small = im.resize((tw, th), Image.LANCZOS)
    km = keep.resize((tw, th), Image.LANCZOS)
    rows = (th + 7) // 8
    pal = [(i, cpcpal.rgb(i)) for i in INKS]
    pix = [[1] * tw for _ in range(rows * 8)]
    sp, kmp = small.load(), km.load()
    for y in range(th):
        for x in range(tw):
            if kmp[x, y] < 110:
                continue
            pix[y][x] = classify(sp[x, y])
    return pix, rows


def tiles(pix, rows):
    """-> (tuiles uniques en octets mode 0, carte rows x TILES_W d'index)"""
    uniq, index, cmap = [], {}, []
    for r in range(rows):
        line = []
        for c in range(TILES_W):
            data = bytes(cpcpal.mode0_byte(pix[r * 8 + y][c * 4 + k], pix[r * 8 + y][c * 4 + k + 1])
                         for y in range(8) for k in (0, 2))
            if data not in index:
                index[data] = len(uniq)
                uniq.append(data)
            line.append(index[data])
        cmap.append(line)
    return uniq, cmap


def preview(pix):
    h, w = len(pix), len(pix[0])
    img = Image.new('RGB', (w * 2, h))
    p = img.load()
    for y in range(h):
        for x in range(w):
            p[2 * x, y] = p[2 * x + 1, y] = cpcpal.rgb(pix[y][x])
    img.resize((w * 8, h * 4), Image.NEAREST).save(os.path.join(ROOT, 'build', 'logo_cpc.png'))


if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1] == 'cpc':
    pix, rows = build()
    preview(pix)
    u, m = tiles(pix, rows)
    print(rows, 'rangées,', len(u), 'tuiles uniques')


def write_asm():
    """src/logo_tiles.asm (base 0 : tuiles mode 0 par tiers) et
    src/logo_map.asm (noms des rangées 0-12, colonnes 2-29 ; base 0, recopiés en banque 4)."""
    pix, rows = build()
    blank = [[1] * (TILES_W * 4) for _ in range(8)]
    out_t = ['; Fichier généré par tools/logo.py : logo en tuiles mode 0']
    out_m = ['; Fichier généré par tools/logo.py : carte du logo (index dans le tiers)',
             f'LOGO_ROWS equ {rows}', 'logo_map_data:   ; (base 0, recopiée en banque 4 par init)']
    for third, (r0, r1) in enumerate(((0, 8), (8, rows))):
        part = blank + pix[r0 * 8:r1 * 8]           # tuile 0 = vide
        u, m = tiles(part, 1 + (r1 - r0))
        assert u[0] == bytes([0xC0] * 16)            # tuile 0 vide (encre 1)
        out_t.append(f'LOGO_N{third} equ {len(u)}')
        out_t.append(f'logo_t{third}:')
        for t in u:
            out_t.append('        db ' + ','.join('$%02X' % b for b in t))
        for line in m[1:]:
            out_m.append('        db ' + ','.join(str(v) for v in line))
    nl = chr(10)
    open(os.path.join(ROOT, 'src', 'logo_tiles.asm'), 'w', encoding='utf-8').write(nl.join(out_t) + nl)
    open(os.path.join(ROOT, 'src', 'logo_map.asm'), 'w', encoding='utf-8').write(nl.join(out_m) + nl)


if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1] == 'asm':
    write_asm()
