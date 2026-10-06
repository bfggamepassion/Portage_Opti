"""Profil du portage dans le simulateur : temps par routine (base 0 / banque 4 /
cartouche) entre deux trames.
  python tools/prof.py DEBUT FIN [--keys script]"""
import os, sys, bisect, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cpcsim
ROOT = os.path.join(HERE, '..')


def load_sym():
    """Étiquettes de la base 0 (common + render) et de la banque 4 (common + gamecode)."""
    import re
    def labels(f):
        return set(re.findall(r'^([A-Za-z_]\w*):', open(os.path.join(ROOT, 'src', f), encoding='utf-8').read(), re.M))
    common = labels('common.asm')
    game = labels('gamecode.asm') | common
    rend = labels('render.asm') | labels('tables.asm') | common
    b0, b4 = {}, {}
    for line in open(os.path.join(ROOT, 'build', __import__('port_config').GAME + '.sym')).read().splitlines():
        k, _, v = line.partition(': EQU ')
        if not v or '.' in k:
            continue
        a = int(v, 16)
        if a >= 0x4000:
            continue
        if k in game:
            b4[a] = k
        if k in rend:
            b0[a] = k
    return b0, b4


def main():
    a, b = int(sys.argv[1]), int(sys.argv[2])
    keys = cpcsim.parse_keys(sys.argv[4]) if len(sys.argv) > 4 else None
    b0, b4 = load_sym()
    a0, a4 = sorted(b0), sorted(b4)
    c = cpcsim.CPC()
    c.run_frames(a, keys)
    where = collections.Counter()

    def prof(pc, us):
        if pc < 0x4000:
            sym, addrs = (b4, a4) if c.map[0] == 4 else (b0, a0)
            i = bisect.bisect_right(addrs, pc) - 1
            where[('jeu ' if c.map[0] == 4 else 'rendu ') + (sym[addrs[i]] if i >= 0 else '?')] += us
        else:
            where['cartouche %02X00' % (pc >> 8)] += us
    c.run_frames(b - a, keys, prof=prof)
    tot = sum(where.values())
    print(f'{tot} us sur {b - a} trames ({tot / (b - a):.0f} us/trame)')
    for k, v in where.most_common(30):
        print('%-32s %6.1f%%' % (k, 100 * v / tot))


if __name__ == '__main__':
    main()
