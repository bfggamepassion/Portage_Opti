"""Écran de présentation (exemple minimal à personnaliser).

Produit asm/gfx/title.scr (écran de chargement, bloc SCREEN$) et
asm/gfx/title.asm (même écran compressé, affiché par le menu).
Pour un vrai titre, reprendre les tuiles du logo GB (voir gbgfx.VRAM et
l'écran titre de ZX Tennis : logo GB + « ZX » + rayures arc-en-ciel).
"""
import os

from zxscreen import Screen, attr, BLACK, RED, YELLOW, GREEN, CYAN, WHITE

HERE = os.path.dirname(os.path.abspath(__file__))
GFX = os.path.join(HERE, '..', 'asm', 'gfx')

s = Screen()
s.big_text(128 - 64, 16, 'GAME', scale=4)
for r, ink in zip(range(2, 6), (RED, YELLOW, GREEN, CYAN)):
    s.attr_rect(r, 0, 1, 32, attr(ink, BLACK))
for r in range(0, 4):                       # rayures arc-en-ciel du Spectrum
    for k, col in enumerate((RED, YELLOW, GREEN, CYAN)):
        s.clear_cell(r, 28 + k - r)
        s.att[r][28 + k - r] = attr(BLACK, col)
s.text(23, 1, 'based on the Game Boy game', WHITE)
s.save_scr(os.path.join(GFX, 'title.scr'))
n = s.save_rle_asm(os.path.join(GFX, 'title.asm'), 'title_rle')
s.preview(os.path.join(HERE, '..', 'asm', 'build', 'title_preview.png'))
print(f'écran titre : {n} octets compressés')
