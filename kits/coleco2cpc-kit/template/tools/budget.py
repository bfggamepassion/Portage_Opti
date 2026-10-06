"""Budget par image affichée (en NOPs, 1 trame = 19 968) sur les décors de
référence : rendu / jeu (NMI, VDP virtuel, son, manettes) / attente du VSYNC.
  python tools/budget.py [décor ...]      (défaut : 3 26 12 1)
Décors 3 et 26 : fille en marche ; 12 et 1 : à l'arrêt (en marche elle tombe
à l'eau et l'écran de mort fausse la mesure)."""
import collections
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import portsim  # noqa: E402

WALK = {3: True, 26: True, 12: False, 1: False, 29: False}


def budget(lvl, walk):
    sym = portsim.symbols()
    c, keys = portsim.cpc_level(lvl, '960:J0R' if walk else '')
    c.run_frames(300, keys)
    t = collections.Counter()
    n = [0]
    fw0, fw1 = sym['flip_wait'], sym['update_palette']

    def prof(pc, us):
        if pc < 0x4000 and c.map[0] == 0:
            t['attente' if fw0 <= pc < fw1 else 'rendu'] += us
            if pc == fw0:
                n[0] += 1
        else:
            t['jeu'] += us
    c.run_frames(150, keys, prof=prof)
    im = n[0]
    return 50 * im / 150, {k: v / im for k, v in t.items()}


if __name__ == '__main__':
    lv = [int(x) for x in sys.argv[1:]] or [3, 26, 12, 1]
    for lvl in lv:
        fps, t = budget(lvl, WALK.get(lvl, True))
        print(f'décor {lvl:2} : {fps:4.1f} images/s | par image : rendu {t["rendu"]:6.0f}  '
              f'jeu {t["jeu"]:6.0f}  attente {t.get("attente", 0):6.0f} NOPs')
