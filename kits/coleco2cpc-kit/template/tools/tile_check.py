"""Contrôle absolu des tuiles : jeu figé (comme render_check), chaque case
de l'écran qu'aucun sprite ne recouvre doit être la conversion de sa tuile
en VRAM (règle de la couleur minoritaire). Détecte une tuile périmée dans le
cache ou une case pas redessinée.
  python tools/tile_check.py BINAIRE [BINAIRE ...]"""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cpcpal  # noqa: E402
import preview_cpc as PV  # noqa: E402
import render_check as R  # noqa: E402


def bad_cells(c, shot):
    c.phys()
    vr = c.ram[7 * 0x4000:8 * 0x4000]
    reg = c.ram[5 * 0x4000 + 0x0382:5 * 0x4000 + 0x038A]
    if reg[1] & 0x40 == 0:
        return []                                   # écran éteint
    sat = c.ram[2 * 0x4000 + 0x1600:2 * 0x4000 + 0x1680]
    cover = set()
    for i in range(32):
        y, x, n, col = sat[4 * i:4 * i + 4]
        if y == 0xD0:
            break
        if col & 15 == 0:
            continue
        yy = y + 1 if y + 1 < 0xE2 else y + 1 - 256
        xx = x - (32 if col & 0x80 else 0)
        for r in range(max(0, yy // 8), min(24, (yy + 16) // 8 + 1)):
            for q in range(max(0, xx // 8), min(32, (xx + 16) // 8 + 1)):
                cover.add((r, q))
    first = 16 if c.ram[5 * 0x4000 + 0x03B3] else 0     # menu : logo (tiers 0-1) posé par le rendu
    names = (reg[2] & 0x0F) * 0x400
    pbase, cbase = (reg[4] & 4) * 0x800, (reg[3] & 0x80) * 0x40
    bad = []
    half = len(shot) // 2
    for scr in (getattr(c, 'shown', 0),):          # l'écran qui vient d'être affiché
        for r in range(first, 24):
            for q in range(32):
                if (r, q) in cover:
                    continue
                nm = vr[names + r * 32 + q]
                t = r // 8
                for y in range(8):
                    p = vr[pbase + t * 0x800 + nm * 8 + y]
                    cc = vr[cbase + t * 0x800 + nm * 8 + y]
                    fg, bg = cc >> 4, cc & 15
                    sel = PV.sel4(p)
                    px = [(fg if (sel >> (3 - k)) & 1 else bg) for k in range(4)]
                    exp = (cpcpal.mode0_byte(px[0], px[1]), cpcpal.mode0_byte(px[2], px[3]))
                    line = r * 8 + y
                    off = scr * half + (line & 7) * 0x600 + (line >> 3) * 64 + q * 2
                    if (shot[off], shot[off + 1]) != exp:
                        bad.append(("AB"[scr], r, q, y))
                        break
    return bad


if __name__ == '__main__':
    keys = '400:1 425: 960:J0R ' + ' '.join(f'{t}:J0R+J0F1 {t+6}:J0R' for t in range(1100, 3600, 70))
    points = [(12, 2200), (12, 2450), (None, 2300)] + [(None, t) for t in range(1175, 3400, 150)] + [(12, t) for t in range(1175, 2600, 150)]
    for binp in sys.argv[1:]:
        tot = 0
        for lvl, t in points:
            shot, c = R.run(binp, lvl, keys, t)
            b = bad_cells(c, shot)
            if b:
                tot += 1
                print(os.path.basename(binp), f'départ {lvl} trame {t} : {len(b)} cases fausses', b[:4], flush=True)
        print(os.path.basename(binp), ':', tot, 'situations avec des cases fausses sur', len(points), flush=True)
