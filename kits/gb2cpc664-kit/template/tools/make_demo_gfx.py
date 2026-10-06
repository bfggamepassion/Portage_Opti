"""Graphismes de démonstration du squelette (à remplacer par ceux du jeu).

Décor : un terrain uni avec un cadre (tuiles fabriquées ici) ; sprite 0 :
une balle 8x8. Pour un vrai jeu, reconstituer l'écran GB avec gbgfx.VRAM
(copies de tuiles + décodeur de tilemap du jeu), puis write_background ; et
les images des objets d'après les listes OAM de la ROM (voir le repo Tennis :
Amstrad/tools/gen_cpcgfx.py et gen_cpcsprites.py).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cpcgfx  # noqa: E402

GFX = os.path.join(HERE, '..', 'gfx')

plain = [[0] * 8 for _ in range(8)]
edge = [[1] * 8] + [[1] + [0] * 6 + [1] for _ in range(6)] + [[1] * 8]
rows = [[edge if r in (0, 24) or c in (0, 31) else plain for c in range(32)] for r in range(25)]
n = cpcgfx.write_background(os.path.join(GFX, 'court.asm'), rows,
                            ['pastel_green', 'bright_green', 'green', 'black'])
cpcgfx.write_lines_table(os.path.join(GFX, 'lines.asm'))
ball = {(x - 4, y - 8): (3 if (x in (0, 7) or y in (0, 7)) else 1)
        for y in range(8) for x in range(8) if (x - 3.5) ** 2 + (y - 3.5) ** 2 <= 16}
count, total, area_b = cpcgfx.write_sprites(GFX, [ball], [(0xA600, 0xC000)])
print(f'démo : {n} tuiles, {count} sprite ({total} octets décalés)')
