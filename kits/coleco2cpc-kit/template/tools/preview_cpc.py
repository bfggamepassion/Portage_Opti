"""Aperçu de la conversion en mode 0 (128 pixels utiles, 16 couleurs) d'un
état VDP, comparé à l'original.

  python tools/preview_cpc.py [trame] [--keys script]
-> build/preview_NNNN.png (gauche : Coleco 256x192, droite : CPC 128x192 étiré x2)
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import cpcpal  # noqa: E402


def popcount(x):
    return bin(x).count('1')


def sel4(p):
    """Motif de 8 pixels -> 4 sélecteurs (bit 3 = paire de gauche) : la couleur
    minoritaire de la ligne gagne les paires mixtes (garde les détails fins)."""
    out = 0
    minority_on = popcount(p) <= 4
    for i in range(4):
        b = (p >> (6 - 2 * i)) & 3
        if b == 3:
            on = True
        elif b == 0:
            on = False
        else:
            on = minority_on
        out |= on << (3 - i)
    return out


def spr4(p):
    """Sprite : une paire est allumée si l'un des deux pixels l'est."""
    return sum(((p >> (6 - 2 * i)) & 3 != 0) << (3 - i) for i in range(4))


def render_cpc(v):
    """VDP (mode graphique 2) -> image 128x192 d'encres (0-15)."""
    vr = v.vram
    reg = v.reg
    back = reg[7] & 15
    img = [[back] * 128 for _ in range(192)]
    if not (reg[1] & 0x40):
        return img
    name = (reg[2] & 0x0F) * 0x400
    m2 = reg[0] & 2
    for r in range(24):
        for c in range(32):
            t = vr[name + r * 32 + c]
            for y in range(8):
                if m2:
                    tt = (t + (r // 8) * 256) & (((reg[4] & 3) << 8) | 0xFF)
                    p = vr[(reg[4] & 4) * 0x800 + tt * 8 + y]
                    cc = vr[(reg[3] & 0x80) * 0x40 + (tt & (((reg[3] & 0x7F) << 3) | 7)) * 8 + y]
                else:
                    p = vr[(reg[4] & 7) * 0x800 + t * 8 + y]
                    cc = vr[reg[3] * 0x40 + (t >> 3)]
                fg, bg = cc >> 4, cc & 15
                s = sel4(p)
                for i in range(4):
                    k = fg if s & (8 >> i) else bg
                    img[r * 8 + y][c * 4 + i] = k
    sat = (reg[5] & 0x7F) * 0x80
    spat = (reg[6] & 7) * 0x800
    size = 16 if reg[1] & 2 else 8
    sprites = []
    for s in range(32):
        y, x, p, col = vr[sat + s * 4:sat + s * 4 + 4]
        if y == 0xD0:
            break
        sprites.append((y, x, p, col))
    for y, x, p, col in reversed(sprites):          # le sprite 0 passe devant
        if not col & 15:
            continue
        y = y + 1 if y < 0xE1 else y - 255
        if col & 0x80:
            x -= 32
        if size == 16:
            p &= 0xFC
        for dy in range(size):
            yy = y + dy
            if not 0 <= yy < 192:
                continue
            for dx in range(size):
                b = vr[spat + p * 8 + (dx // 8) * 16 + dy]
                xx = x + dx
                if b & (0x80 >> (dx & 7)) and 0 <= xx < 256:
                    img[yy][xx >> 1] = col & 15
    return img


def to_image(img, back):
    out = Image.new('RGB', (256, 192))
    px = out.load()
    for y in range(192):
        for x in range(128):
            k = img[y][x] or back
            c = cpcpal.rgb(k)
            px[2 * x, y] = c
            px[2 * x + 1, y] = c
    return out


def main():
    import cvrun
    from cvsim import parse_keys
    frame = int(sys.argv[1]) if len(sys.argv) > 1 else 1200
    keys = parse_keys(sys.argv[3]) if len(sys.argv) > 3 else parse_keys('800:K1 815: 1000:R 1400:R1 1410:R')
    cv = cvrun.ColecoBios()
    cv.run_frames(frame, keys)
    orig = cv.render()
    cpc = to_image(render_cpc(cv.vdp), cv.vdp.reg[7] & 15)
    out = Image.new('RGB', (512 + 8, 192))
    out.paste(orig, (0, 0))
    out.paste(cpc, (264, 0))
    out = out.resize((out.width * 2, out.height * 2), Image.NEAREST)
    out.save(os.path.join(ROOT, 'build', f'preview_{frame:04d}.png'))


if __name__ == '__main__':
    main()
