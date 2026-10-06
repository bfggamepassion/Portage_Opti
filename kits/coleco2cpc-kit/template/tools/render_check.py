"""Contrôle d'une optimisation du rendu : compare deux binaires (référence et
nouveau) sur les mêmes situations. Dans chaque cas, le jeu est figé à une
trame donnée (drapeau anti-réentrée $6005 : la NMI ne fait plus rien), le
rendu termine, puis les DEUX écrans (A et B) doivent être identiques octet
pour octet entre les deux binaires.

  python tools/render_check.py REF.bin [NOUVEAU.bin] [--quick]

Le hasard « ld a,r » reçoit la même suite de valeurs dans les deux cas
(sinon la logique divergerait, le registre R dépendant du code exécuté).
"""
import os
import re
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import cpcsim  # noqa: E402
import port_config as P  # noqa: E402

R_SITES = set()
for line in open(os.path.join(ROOT, 're', P.GAME + '.lst'), encoding='utf-8'):
    m = re.match(r'\s+([0-9A-F]{4})\s+ED 5F\s+ld a,r', line)
    if m:
        R_SITES.add(int(m.group(1), 16))


def poke(c, addr, val):
    c.ram[5 * 0x4000 + addr - 0x4000] = val
    if c.map[1] == 5:
        c.mem[addr] = val


def screens(c):
    """Octets visibles des écrans A (bloc 2) et B (bloc 3)."""
    c.phys()
    out = bytearray()
    for blk in (2, 3):
        base = blk * 0x4000
        for k in range(8):
            out += c.ram[base + k * 0x800:base + k * 0x800 + 0x600]
    return bytes(out)


def run(binp, level, keys_s, freeze_at, settle=60):
    """Tout est réglé sur le nombre de ticks de jeu exécutés (pas sur les
    trames : un tick peut glisser d'une trame à l'autre selon les fenêtres
    DI du rendu). Les instants des CASES sont en trames « nominales »
    (tick = trame x 1,2). Écrans relevés à la première bascule (écriture de
    R12) après `settle` trames de gel : image terminée."""
    c = cpcsim.CPC(binp)
    script = cpcsim.parse_keys(keys_s)
    x = [0x5A]
    st = {'ticks': 0, 'frozen': False, 'poked': level is None, 'arm': False, 'r12': None, 'shot': None}
    acc, acc_op = P.NMI_ACCEPT
    nmi = acc - 0x18                          # entrée de la NMI du jeu ($807C)
    t_poke = P.POKE_FRAME_CPC * 6 // 5
    t_freeze = freeze_at * 6 // 5

    def keys(frame):
        return script(st['ticks'] * 5 // 6)

    def prof(pc, us):
        if pc in R_SITES and c.map[2] == 6:
            x[0] = (x[0] * 73 + 41) & 0xFF
            c.r[0] = x[0] & 0x7F
        elif pc == nmi and c.map[2] == 6:
            if st['ticks'] >= t_freeze:
                st['frozen'] = True
            if st['frozen']:
                poke(c, 0x6005, 1)           # la NMI ressort aussitôt : jeu figé
        elif pc == acc and c.mem[pc] == acc_op:
            st['ticks'] += 1
            c.keys = keys(0)                 # touches du tick, dès son début
            if not st['poked'] and st['ticks'] >= t_poke:
                st['poked'] = True
                for a, v in P.level_pokes(level):
                    poke(c, a, v)
        if st['arm'] and st['shot'] is None and c.crtc[12] != st['r12']:
            st['shot'] = screens(c)
            c.shown = 0 if (c.crtc[12] & 0x30) == 0x20 else 1   # écran affiché : A ($8000) ou B
    while not st['frozen']:
        c.run_frames(10, keys, prof=prof)
    c.run_frames(settle, keys, prof=prof)
    st['r12'] = c.crtc[12]
    st['arm'] = True
    end = c.frame + 50
    while st['shot'] is None and c.frame < end:
        c.run_frames(1, keys, prof=prof)
    return st['shot'] or screens(c), c


CASES = [
    # (nom, niveau, touches, trame du gel)
    ('menu', None, '', 420),
    ('menu, T', None, '380:T 390:', 430),
    ('PLAYER 1', None, '400:1 425:', 760),
]
for lvl in (3, 26, 12, 1, 5, 9, 16, 20):
    for t in (1040, 1113, 1187):
        CASES.append((f'décor {lvl} trame {t}', lvl, '400:1 425: 960:J0R 1100:J0R+J0F1 1106:J0R', t))

if __name__ == '__main__':
    ref = sys.argv[1]
    new = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else os.path.join(ROOT, 'build', P.GAME + '.bin')
    cases = CASES[::4] if '--quick' in sys.argv else CASES
    bad = 0
    for name, lvl, keys, t in cases:
        a, ca = run(ref, lvl, keys, t)
        b, cb = run(new, lvl, keys, t)
        keep = [k for k in range(0x400) if not any(x <= 0x6000 + k <= y for x, y in P.TICKS_IGNORE)]
        ga = bytes(ca.ram[5 * 0x4000 + 0x2000 + k] for k in keep)
        gb = bytes(cb.ram[5 * 0x4000 + 0x2000 + k] for k in keep)
        d = sum(1 for i in range(len(a)) if a[i] != b[i])
        tag = 'OK' if d == 0 else f'DIFFÉRENT : {d} octets'
        if ga != gb:
            tag += ' (état du jeu différent !)'
        if d:
            bad += 1
            first = next(i for i in range(len(a)) if a[i] != b[i])
            scr, off = divmod(first, 8 * 0x600)
            k, o = divmod(off, 0x600)
            tag += f' ; premier : écran {"AB"[scr]} ligne {(o // 64) * 8 + k} octet {o % 64}'
        print(f'{name:28} {tag}')
    print('RÉSULTAT :', 'identique partout' if bad == 0 else f'{bad} cas différents')
    sys.exit(1 if bad else 0)
