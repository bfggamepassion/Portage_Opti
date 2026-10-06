"""Génère les tables du moteur de rendu et la police fine :

  src/tables.asm   tables alignées (conversion des tuiles et des sprites, encres)
  src/font4.asm    police 4 pixels (doublée en 8) pour l'écran d'options
  build/cart.bin   cartouche avec la police du jeu remplacée par la police fine

Mode 0 : un pixel CPC = deux pixels Coleco. Une ligne de tuile (8 pixels,
couleurs fg/bg) donne 2 octets. Paire mixte (un pixel allumé sur deux) : la
couleur minoritaire de la ligne l'emporte, pour garder les détails fins.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import cpcpal  # noqa: E402
from font4 import FONT, glyph_bytes  # noqa: E402
import port_config  # noqa: E402

PAIR_PAGE = 0x32            # pages $32-$35 : PAIR_s[cb]


def popcount(x):
    return bin(x).count('1')


def pair_on(p, i, minority_on):
    b = (p >> (6 - 2 * i)) & 3
    if b == 3:
        return 1
    if b == 0:
        return 0
    return 1 if minority_on else 0


def sels(p):
    mo = popcount(p) <= 4
    on = [pair_on(p, i, mo) for i in range(4)]
    return (on[0] << 1) | on[1], (on[2] << 1) | on[3]


def db(data, per=16, indent='        '):
    return [indent + 'db ' + ','.join('$%02X' % b for b in data[k:k + per])
            for k in range(0, len(data), per)]


def main():
    out = ['; Fichier généré par tools/gen_tables.py - ne pas modifier', '']
    sell = [PAIR_PAGE + sels(p)[0] for p in range(256)]
    selr = [PAIR_PAGE + sels(p)[1] for p in range(256)]
    out += ['SELL:   ; page de la table PAIR pour l\'octet gauche'] + db(sell)
    out += ['SELR:   ; idem, octet droit'] + db(selr)
    for s in range(4):
        tab = []
        for cb in range(256):
            fg, bg = cb >> 4, cb & 15
            left = fg if s & 2 else bg
            right = fg if s & 1 else bg
            tab.append(cpcpal.mode0_byte(left, right))
        out += [f'PAIR{s}:'] + db(tab)
    # sprites : 8 pixels Coleco -> 4 bits (une paire allumée si l'un des deux l'est)
    sprn = [sum((((p >> (6 - 2 * i)) & 3) != 0) << (3 - i) for i in range(4)) for p in range(256)]
    out += ['SPRN:   ; motif de sprite (8 pixels) -> 4 pixels CPC (bit 3 = gauche)'] + db(sprn)
    # masques : 2 bits (pixel gauche, pixel droit) -> octet de masque mode 0
    out += ['MASK2:  ; 00 01 10 11 -> octet (gauche $AA, droite $55)',
            '        db $00,$55,$AA,$FF']
    out += ['COLB:   ; couleur TMS -> octet mode 0 (deux pixels de cette encre)'] + \
        db([cpcpal.mode0_byte(c, c) for c in range(16)])
    out += ['INKHW:  ; couleur TMS -> couleur matérielle du Gate Array'] + \
        db([cpcpal.hw(c) for c in range(16)])
    m2 = [0x00, 0x55, 0xAA, 0xFF]
    out += ['N2:     ; 4 pixels CPC (bit 3 = gauche) -> 2 octets de masque'] +         db([b for n in range(16) for b in (m2[n >> 2], m2[n & 3])])
    os.makedirs(os.path.join(ROOT, 'src'), exist_ok=True)
    open(os.path.join(ROOT, 'src', 'tables.asm'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')

    # police fine pour l'écran d'options (codes ASCII $20-$5A)
    fo = ['; Fichier généré par tools/gen_tables.py : police 4 pixels doublée',
          'font4_data:  ; caractères $20-$5A, 8 octets chacun (base 0, recopiés en banque 4 par init)']
    for code in range(0x20, 0x5B):
        fo += db(glyph_bytes(chr(code)), 8)
    open(os.path.join(ROOT, 'src', 'font4.asm'), 'w', encoding='utf-8').write('\n'.join(fo) + '\n')

    # cartouche : police du jeu remplacée par la police fine (port_config.FONT_PATCH)
    rom = bytearray(open(os.path.join(ROOT, 're', port_config.GAME + '.col'), 'rb').read())
    for off, chars in port_config.FONT_PATCH:
        for k, ch in enumerate(chars):
            rom[off + k * 8:off + k * 8 + 8] = glyph_bytes(ch)
    # sprites redessinés pour le mode 0 (tools/sprite_fix.py, gfx/sprites_cpc.json)
    import sprite_fix
    sprite_fix.apply(rom)
    os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
    open(os.path.join(ROOT, 'build', 'cart.bin'), 'wb').write(rom)


if __name__ == '__main__':
    main()
