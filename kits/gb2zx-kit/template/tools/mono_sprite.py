"""Sprites GB (4 teintes) -> sprites Spectrum masqués (format de asm/src/sprite.asm).

Conversion des teintes (choix validé sur Tennis) :
  3 -> encre ; 2 -> trame (un pixel sur deux) ; 1 -> papier opaque ; 0 -> transparent.

Format d'un sprite (octets) : largeur W (octets), hauteur H, décalage X et Y
(signés, depuis le point d'ancrage), puis H lignes de W paires (masque, dessin).
Écran = (écran AND masque) OR dessin.

Usage type :
    import gbgfx, mono_sprite
    sprites = [mono_sprite.to_mono(gbgfx.sprite_from_oam_list(rom, liste)) for liste in listes]
    mono_sprite.write_asm(sprites, 'asm/gfx/sprites.asm')
"""
import os


def to_mono(pix, scale_x=1.0, scale_y=1.0):
    """pix : dict (x, y) -> teinte, x/y relatifs au point d'ancrage.
    Renvoie (x0, y0, W, H, lignes de (masque, dessin))."""
    if scale_x != 1.0 or scale_y != 1.0:
        pix = rescale(pix, scale_x, scale_y)
    xs = [x for x, _ in pix]
    ys = [y for _, y in pix]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    wbytes = (x1 - x0) // 8 + 1
    rows = []
    for y in range(y0, y1 + 1):
        row = []
        for b in range(wbytes):
            m, g = 0xFF, 0
            for bit in range(8):
                x = x0 + b * 8 + bit
                c = pix.get((x, y), 0)
                if c:
                    m &= ~(0x80 >> bit) & 0xFF
                    if c == 3 or (c == 2 and (x + y) % 2 == 0):
                        g |= 0x80 >> bit
            row.append((m, g))
        rows.append(row)
    return x0, y0, wbytes, y1 - y0 + 1, rows


def rescale(pix, sx, sy):
    """Mise à l'échelle au plus proche voisin (écran GB 160x144 -> Spectrum 256x192 :
    Tennis a gardé les sprites à l'échelle 1 et projeté les positions)."""
    xs = [x for x, _ in pix]
    ys = [y for _, y in pix]
    out = {}
    for y in range(int(min(ys) * sy), int((max(ys) + 1) * sy)):
        for x in range(int(min(xs) * sx), int((max(xs) + 1) * sx)):
            c = pix.get((int(x / sx), int(y / sy)))
            if c:
                out[(x, y)] = c
    return out


def write_asm(sprites, path, header='sprites tirés de la ROM GB'):
    out = [f'; Fichier généré ({header}). Ne pas modifier à la main.', '', 'SprTable:']
    for i in range(0, len(sprites), 8):
        out.append('        dw ' + ', '.join(f'Spr{j}' for j in range(i, min(i + 8, len(sprites)))))
    total = 0
    for i, (x0, y0, w, h, rows) in enumerate(sprites):
        out.append(f'Spr{i}:')
        out.append(f'        db {w}, {h}, {x0 & 0xFF}, {y0 & 0xFF}')
        for row in rows:
            out.append('        db ' + ', '.join(f'${m:02X}, ${g:02X}' for m, g in row))
        total += 4 + h * w * 2
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(f'{len(sprites)} sprites, {total} octets -> {path}')
