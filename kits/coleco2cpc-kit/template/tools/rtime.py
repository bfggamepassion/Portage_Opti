"""Durée de chaque rendu (trames entre deux bascules) et temps pur de dessin."""
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
st = {'t0': None, 'game': 0, 'draw': 0, 'wait': 0, 'prep': 0, 'phase': 'draw'}
rows = []
DC, FR, FW, W = sym['draw_cells'], sym['flip_req'], sym['flip_wait'], sym['flip_wait.w']
def prof(pc, us):
    if c.map == (4, 5, 6, 7):
        st['game'] += us
        return
    if pc == DC:
        if st['t0'] is not None:
            rows.append((st['draw'], st['prep'], st['wait'], st['game']))
        st.update(t0=c.us, game=0, draw=0, wait=0, prep=0, phase='draw')
    elif pc == FR:
        st['phase'] = 'prep'
    elif pc == W:
        st['phase'] = 'wait'
    st[st['phase']] += us
c.run_frames(b - a, keys, prof=prof)
print('dessin  prép.  attente  jeu   (us)   total/trames')
for r in rows:
    t = sum(r)
    print('%6d %6d %6d %6d   %.2f' % (r + (t / 19968,)))
n = len(rows)
print('moyennes', [sum(r[i] for r in rows) // n for i in range(4)])
