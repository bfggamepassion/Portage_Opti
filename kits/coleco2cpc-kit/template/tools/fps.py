"""Cadence du rendu dans le simulateur : images affichées par seconde (bascules)
entre deux trames.   python tools/fps.py DEBUT FIN [--keys script]"""
import os, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cpcsim
ROOT = os.path.join(HERE, '..')
sym = {}
for line in open(os.path.join(ROOT, 'build', __import__('port_config').GAME + '.sym')):
    k, _, v = line.partition(': EQU ')
    if v:
        sym[k] = int(v, 16)
a, b = int(sys.argv[1]), int(sys.argv[2])
keys = cpcsim.parse_keys(sys.argv[4]) if len(sys.argv) > 4 else None
c = cpcsim.CPC()
c.run_frames(a, keys)
F, DS = sym['flip_wait'], sym['draw_sprite']
n = collections.Counter()
def prof(pc, us):
    if c.map[0] == 0:
        if pc == F:
            n['flip'] += 1
        elif pc == DS:
            n['spr'] += 1
c.run_frames(b - a, keys, prof=prof)
print(f"{n['flip']} images en {b - a} trames : {50 * n['flip'] / (b - a):.1f} images/s, "
      f"{n['spr'] / max(1, n['flip']):.1f} sprites par image")
