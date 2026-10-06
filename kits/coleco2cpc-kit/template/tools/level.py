"""Va directement au niveau N dans le CPC simulé, puis mesure :
  python tools/level.py N [secondes] [--walk] [--prof]
- images/s par seconde (bascules d'écran), captures build/level_N_k.png ;
- --walk : maintient « droite » ; --prof : temps par routine (base 0 /
  banque 4 / cartouche), pour trouver ce qui ralentit un niveau."""
import bisect
import collections
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import portsim  # noqa: E402
import port_config as P  # noqa: E402
import prof as PR  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith('--')]
n = int(args[0], 0)
secs = int(args[1]) if len(args) > 1 else 4
walk = '--walk' in sys.argv
sym = portsim.symbols()
c, keys = portsim.cpc_level(n, f'{P.POKE_FRAME_CPC + 260}:{P.RIGHT_CPC}' if walk else '')
c.run_frames(300, keys)                       # le niveau se construit

if '--prof' in sys.argv:
    b0, b4 = PR.load_sym()
    a0, a4 = sorted(b0), sorted(b4)
    where = collections.Counter()

    def prof(pc, us):
        if pc < 0x4000:
            s, addrs = (b4, a4) if c.map[0] == 4 else (b0, a0)
            i = bisect.bisect_right(addrs, pc) - 1
            where[('jeu ' if c.map[0] == 4 else 'rendu ') + (s[addrs[i]] if i >= 0 else '?')] += us
        else:
            where['cartouche %02X00' % (pc >> 8)] += us
    c.run_frames(50 * secs, keys, prof=prof)
    tot = sum(where.values())
    part = collections.Counter()
    for k, v in where.items():
        part[k.split()[0]] += v
    print(' '.join(f'{k} {100 * v / tot:.0f}%' for k, v in part.items()))
    for k, v in where.most_common(25):
        print('%-32s %6.1f%%' % (k, 100 * v / tot))
else:
    for k in range(secs):
        cnt = [0]

        def prof(pc, us):
            if c.map[0] == 0 and pc == sym['flip_wait']:
                cnt[0] += 1
        c.run_frames(50, keys, prof=prof)
        c.screenshot(os.path.join(HERE, '..', 'build', f'level_{n}_{k}.png'))
        print(f'niveau {n}, seconde {k} : {cnt[0]} images/s')
