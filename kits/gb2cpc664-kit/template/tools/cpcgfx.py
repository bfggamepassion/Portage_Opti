"""Graphismes Game Boy -> Amstrad CPC (repris de CPC Tennis).

Correspondances clés :
  - Mode 1 (320x200, 4 encres) : les 4 teintes GB = les 4 encres du CPC,
    SANS PERTE. Une tuile GB 8x8 = 16 octets (2 octets par ligne). Le CPC
    montre une image GB de 256 pixels de large à l'échelle 1 (32 tuiles,
    colonnes CPC 4-35), sur 25 rangées.
  - Mode 0 (160x200, 16 encres) : 160 pixels = la largeur de l'écran GB.
    Idéal pour un écran titre GB (20 tuiles) en couleurs.

Écran déplacé en $4000 (la RAM GB occupe $C000-$FFFF) : adresse d'une ligne
y = $4000 + (y AND 7) x $800 + (y / 8) x 80.

Sprites (moteur src/sprite.asm, en XOR) : write_sprites() écrit
  gfx/sprites_raw.asm        images non décalées (lues au démarrage)
  gfx/sprites_meta.asm       tables par image et par décalage
  gfx/sprite_shift_tables.asm  tables SHR/CAR (fabrication des décalages)
et répartit les images décalées dans des zones de RAM libres après le
démarrage (le firmware coupé libère $A600-$BFFF, etc.).
"""
import os

# Couleurs matérielles du CPC (valeur envoyée au Gate Array, bit 6 compris)
HW = {'black': 0x54, 'blue': 0x44, 'bright_blue': 0x55, 'red': 0x5C, 'magenta': 0x58,
      'mauve': 0x5D, 'bright_red': 0x4C, 'purple': 0x45, 'bright_magenta': 0x4D,
      'green': 0x56, 'cyan': 0x46, 'sky_blue': 0x57, 'yellow': 0x5E, 'white': 0x40,
      'pastel_blue': 0x5F, 'orange': 0x4E, 'pink': 0x47, 'pastel_magenta': 0x4F,
      'bright_green': 0x52, 'sea_green': 0x42, 'bright_cyan': 0x53, 'lime': 0x5A,
      'pastel_green': 0x59, 'pastel_cyan': 0x5B, 'bright_yellow': 0x4A,
      'pastel_yellow': 0x43, 'bright_white': 0x4B}


# --- Mode 1 : 4 pixels par octet ; pixel i : bit 7-i = bit 0 de l'encre,
#     bit 3-i = bit 1 de l'encre ------------------------------------------------------
def mode1_byte(pix4):
    b = 0
    for i, ink in enumerate(pix4):
        b |= (ink & 1) << (7 - i)
        b |= ((ink >> 1) & 1) << (3 - i)
    return b


def mode1_pixel(b, i):
    return ((b >> (7 - i)) & 1) | (((b >> (3 - i)) & 1) << 1)


def tile_mode1(px):
    """8x8 teintes (0-3) -> 16 octets mode 1."""
    return bytes(mode1_byte(row[k:k + 4]) for row in px for k in (0, 4))


# --- Mode 0 : 2 pixels par octet ; gauche : bits 7,3,5,1 ; droite : 6,2,4,0 -----------
def mode0_byte(left, right):
    return (((left & 1) << 7) | ((left & 2) << 2) | ((left & 4) << 3) | ((left & 8) >> 2) |
            ((right & 1) << 6) | ((right & 2) << 1) | ((right & 4) << 2) | ((right & 8) >> 3))


def line_addr(y, base=0x4000):
    return base + (y & 7) * 0x800 + (y >> 3) * 80


def write_asm(path, lines):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')


def db_lines(data, per=16):
    return ['        db ' + ', '.join(f'${b:02X}' for b in data[k:k + per])
            for k in range(0, len(data), per)]


def write_lines_table(path):
    out = ['; Fichier généré : adresse écran de chaque ligne (écran en $4000).', 'line_tab']
    for y in range(0, 200, 8):
        out.append('        dw ' + ', '.join(f'${line_addr(yy):04X}' for yy in range(y, y + 8)))
    write_asm(path, out)


def write_background(path, tile_rows, inks, border='black', label='court'):
    """tile_rows : 25 listes de 32 tuiles (8x8 teintes). Dédoublonne et écrit
    <label>_tiles, <label>_map (25 x 32), <label>_inks, <LABEL>_BORDER."""
    tiles = {}
    tmap = []
    for row in tile_rows:
        r = []
        for px in row:
            data = tile_mode1(px)
            if data not in tiles:
                tiles[data] = len(tiles)
            r.append(tiles[data])
        tmap.append(r)
    out = ['; Fichier généré par tools/cpcgfx.py : décor (mode 1).', '',
           f'{label}_inks   db ' + ', '.join(f'${HW[i]:02X}' for i in inks),
           f'{label.upper()}_BORDER = ${HW[border]:02X}', f'{label}_tiles']
    for data in tiles:
        out += db_lines(data)
    out.append(f'{label}_map')
    for r in tmap:
        out.append('        db ' + ', '.join(str(t) for t in r))
    write_asm(path, out)
    return len(tiles)


# --- Sprites ----------------------------------------------------------------------------
def sprite_image(pix):
    """{(x, y): teinte 1-3} (0 = transparent) -> (wb, h, x0, y0, lignes d'octets mode 1)"""
    xs = [x for x, _ in pix]
    ys = [y for _, y in pix]
    x0, y0 = min(xs), min(ys)
    w = max(xs) - x0 + 1
    h = max(ys) - y0 + 1
    wb = (w + 3) // 4
    rows = [[mode1_byte([pix.get((x0 + k * 4 + i, y0 + y), 0) for i in range(4)]) for k in range(wb)]
            for y in range(h)]
    return wb, h, x0, y0, rows


def shifted(rows, wb, s):
    out = []
    for r in rows:
        src = r + [0]
        prev = 0
        o = []
        for k in range(wb + (1 if s else 0)):
            b = src[k]
            px = [mode1_pixel(b, j - s) if j >= s else mode1_pixel(prev, 4 + j - s) for j in range(4)]
            o.append(mode1_byte(px))
            prev = b
        out.append(o)
    return out


def trimmed_size(rows, wb, s):
    """Par ligne : 2 octets (décalage, longueur) + les octets utiles."""
    size = 0
    for r in (shifted(rows, wb, s) if s else rows):
        nz = [i for i, b in enumerate(r) if b]
        size += 2 + ((nz[-1] - nz[0] + 1) if nz else 0)
    return size


def shift_tables():
    t = {}
    for s in range(4):
        t[f'SHR{s}'] = [mode1_byte([mode1_pixel(b, j - s) if j >= s else 0 for j in range(4)])
                        for b in range(256)]
        t[f'CAR{s}'] = [mode1_byte([mode1_pixel(b, 4 + j - s) if j < s else 0 for j in range(4)])
                        for b in range(256)]
    return t


def write_sprites(gfx_dir, pix_images, regions, area_b='spr_area_b'):
    """pix_images : liste de {(x, y): teinte} (ancrage en (0, 0)).
    regions : [(début, fin)] de RAM libre après le démarrage ; le reste va
    dans une réserve en partie B (label area_b, taille SPR_AREA_B_SIZE)."""
    imgs = [sprite_image(p) for p in pix_images]
    free = [list(r) for r in regions]
    size_b = 0
    ptrs = []
    for wb, h, x0, y0, rows in imgs:
        for s in range(4):
            size = trimmed_size(rows, wb, s)
            for r in free:
                if r[1] - r[0] >= size:
                    ptrs.append(f'${r[0]:04X}')
                    r[0] += size
                    break
            else:
                ptrs.append(f'{area_b}+{size_b}')
                size_b += size
    meta = ['; Fichier généré par tools/cpcgfx.py : sprites (mode 1).', '',
            f'NSPRITES    equ {len(imgs)}', f'SPR_AREA_B_SIZE equ {size_b}',
            'spr_raw_tab                     ; image non décalée (utilisée au démarrage)']
    meta += [f'        dw spr_raw{i}' for i in range(len(imgs))]
    meta.append('spr_ptr                         ; image décalée : [numéro x 4 + décalage]')
    meta += ['        dw ' + ', '.join(ptrs[i:i + 4]) for i in range(0, len(ptrs), 4)]
    meta.append('spr_wtab                        ; largeur en octets : [numéro x 4 + décalage]')
    meta += [f'        db {wb}, {wb + 1}, {wb + 1}, {wb + 1}' for wb, *_ in imgs]
    meta.append('spr_htab')
    meta.append('        db ' + ', '.join(str(h) for _, h, *_ in imgs))
    meta.append("spr_x0tab                       ; décalage signé depuis le point d'ancrage")
    meta.append('        db ' + ', '.join(str(x0 & 0xFF) for _, _, x0, *_ in imgs))
    meta.append('spr_y0tab')
    meta.append('        db ' + ', '.join(str(y0 & 0xFF) for _, _, _, y0, _ in imgs))
    write_asm(os.path.join(gfx_dir, 'sprites_meta.asm'), meta)
    raw = ['; Fichier généré par tools/cpcgfx.py : images non décalées.']
    for i, (wb, h, x0, y0, rows) in enumerate(imgs):
        raw.append(f'spr_raw{i}')
        for r in rows:
            raw.append('        db ' + ', '.join(f'${b:02X}' for b in r))
    write_asm(os.path.join(gfx_dir, 'sprites_raw.asm'), raw)
    tb = ['; Fichier généré par tools/cpcgfx.py : tables de décalage (alignées).',
          "; SHRs[b] : pixels de b décalés de s vers la droite ; CARs[b] : pixels sortis."]
    for name, t in shift_tables().items():
        tb.append(f'        ALIGN 256\n{name}_TAB')
        tb += db_lines(t)
    write_asm(os.path.join(gfx_dir, 'sprite_shift_tables.asm'), tb)
    total = sum(trimmed_size(rows, wb, s) for wb, h, x0, y0, rows in imgs for s in range(4))
    return len(imgs), total, size_b
