"""Outils communs du TMS9918A (VDP de la ColecoVision) : palette, conversion
d'une ligne de 8 pixels en motif + couleur (mode graphique 2 : 2 couleurs
par ligne de 8 pixels), rendu d'aperçu.
"""
# Palette TMS9918A (valeurs RGB courantes des émulateurs)
PALETTE = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120), (84, 85, 237),
           (125, 118, 252), (212, 82, 77), (66, 235, 245), (252, 85, 84), (255, 121, 120),
           (212, 193, 84), (230, 206, 128), (33, 176, 59), (201, 91, 186), (204, 204, 204),
           (255, 255, 255)]
BLACK, MGREEN, LGREEN, DBLUE, LBLUE, DRED, CYAN, MRED, LRED, DYELLOW, LYELLOW, \
    DGREEN, MAGENTA, GRAY, WHITE = range(1, 16)


def dist(a, b):
    pa, pb = PALETTE[a], PALETTE[b]
    return sum((x - y) ** 2 for x, y in zip(pa, pb))


def encode_row(cols):
    """8 couleurs TMS -> (octet de motif, octet de couleur fg<<4 | bg), erreur.
    Plus de 2 couleurs : la paire qui trahit le moins la ligne."""
    distinct = sorted(set(cols), key=cols.index)
    if len(distinct) <= 2:
        pair = distinct if len(distinct) == 2 else [distinct[0], distinct[0]]
        err = 0
    else:
        best = None
        for i in range(len(distinct)):
            for j in range(i + 1, len(distinct)):
                p = (distinct[i], distinct[j])
                e = sum(min(dist(c, p[0]), dist(c, p[1])) for c in cols)
                if best is None or e < best[0]:
                    best = (e, p)
        err, pair = best
    fg, bg = pair
    pat = 0
    for x, c in enumerate(cols):
        if dist(c, fg) < dist(c, bg) or (c == fg):
            pat |= 0x80 >> x
    if fg == bg:
        pat = 0
    # forme canonique : moins de pixels allumés que d'éteints (motif plus lisible)
    return pat, (fg << 4) | bg, err


def encode_tile(rows):
    """8 lignes de 8 couleurs TMS -> (8 octets de motif, 8 octets de couleur), erreur."""
    pats, cols, err = [], [], 0
    for r in rows:
        p, c, e = encode_row(r)
        pats.append(p)
        cols.append(c)
        err += e
    return bytes(pats), bytes(cols), err


def decode_tile(pats, cols):
    """Inverse (aperçu) : 8 lignes de 8 couleurs."""
    out = []
    for p, c in zip(pats, cols):
        fg, bg = c >> 4, c & 15
        out.append([fg if p & (0x80 >> x) else bg for x in range(8)])
    return out
