"""Compare le jeu d'origine (ColecoVision simulée avec son BIOS) et le
portage (CPC simulé) au niveau N, tick par tick :
  python tools/ticks.py N [secondes] [--walk] [--ram A-B] [--detail] [--realr]
                          [--show A,B,... [--from T] [--to T]]
- cadence : ticks exécutés / NMI par seconde des deux côtés (une NMI est
  ignorée si le tick précédent n'est pas fini) ;
- état : la RAM Coleco (plage A-B, défaut $6000-$63FF) relevée au début de
  chaque tick, à partir du premier tick de jeu ; affiche les ticks qui
  diffèrent (hors port_config.TICKS_IGNORE ; --detail : toutes les
  adresses qui diffèrent, pour régler cette liste). Zéro différence = la logique du portage est exacte (reste
  alors l'affichage : retard, cadence...)."""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import portsim  # noqa: E402
import port_config as P  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith('--')]
n = int(args[0], 0) if args else None
secs = int(args[1]) if len(args) > 1 else 5
walk = '--walk' in sys.argv
lo, hi = 0x6000, 0x6400
if '--ram' in sys.argv:
    a, b = sys.argv[sys.argv.index('--ram') + 1].split('-')
    lo, hi = int(a, 16), int(b, 16) + 1
WALK_AFTER = 30                    # ticks de jeu avant de marcher

al_addr, al_val = P.ALIGN

# « ld a,r » (hasard tiré du registre R) : sa valeur dépend du nombre
# d'instructions exécutées, donc diffère forcément entre les deux machines.
# Pour comparer la logique, les deux reçoivent la même suite de valeurs
# (--realr : garder le vrai R).
import re as _re
R_SITES = set()
if '--realr' not in sys.argv:
    for line in open(os.path.join(HERE, '..', 're', P.GAME + '.lst'), encoding='utf-8'):
        mm = _re.match(r'\s+([0-9A-F]{4})\s+ED 5F\s+ld a,r', line)
        if mm:
            R_SITES.add(int(mm.group(1), 16))


def r_seq():
    x = 0x5A
    while True:
        x = (x * 73 + 41) & 0xFF
        yield x & 0x7F


def r_hook(regs, gen):
    regs[0] = next(gen)                # A

# --- ColecoVision : RAM au début de chaque tick exécuté (même point de la
# NMI que sur le CPC), et NMI ignorées ---
st = {'t0': None}
cvl = []
cvc = {'a': 0, 's': 0}
acc, acc_op = P.NMI_ACCEPT
skip, skip_op = P.NMI_SKIP


def after(f):
    return {P.RIGHT_CV} if walk and st['t0'] is not None and len(cvl) - st['t0'] >= WALK_AFTER else set()


cv, cvkeys = portsim.cv_level(n, after)
g_cv = r_seq()


def cv_tick(c):
    cvc['a'] += 1
    if st['t0'] is None and c.mem[al_addr] == al_val:
        st['t0'] = len(cvl)
    cvl.append(bytes(c.mem[x] for x in range(lo, hi)))


def cv_skip(c):
    cvc['s'] += 1


cv.post_hooks = {pc: (lambda c: r_hook(c.r, g_cv)) for pc in R_SITES}
if cv.mem[acc] == acc_op and cv.mem[skip] == skip_op:
    cv.post_hooks[acc] = cv_tick
    cv.post_hooks[skip] = cv_skip
else:
    sys.exit('port_config.NMI_ACCEPT / NMI_SKIP : opcodes inattendus dans la ROM')
cv.run_frames(90, cvkeys)                          # début du niveau
out = []
for s in range(secs):
    cvc['a'] = cvc['s'] = 0
    cv.run_frames(60, cvkeys)
    out.append(f"{cvc['a']}/{cvc['a'] + cvc['s']}")
print('Coleco  ticks/NMI par seconde :', ' '.join(out))

# --- CPC : RAM au début de chaque tick exécuté ---
if st['t0'] is None:
    sys.exit(f'état {P.ALIGN} jamais vu sur la Coleco : régler port_config.ALIGN')
cv_sync = {x: cvl[st['t0']][x - lo] for x in P.SYNC_AT_ALIGN}
s2 = {'t0': None}
c, keys = portsim.cpc_level(n)
cpl = []
cnt = {'a': 0, 's': 0}


g_cpc = r_seq()


def prof(pc, us):
    if pc in R_SITES and c.map[2] == 6:            # cartouche en place (vue jeu)
        r_hook(c.r, g_cpc)
    elif pc == acc and c.mem[pc] == acc_op:
        cnt['a'] += 1
        if s2['t0'] is None and portsim.cpc_peek(c, al_addr) == al_val:
            s2['t0'] = len(cpl)
            for x in P.SYNC_AT_ALIGN:              # compteurs de la Coleco
                portsim.cpc_poke(c, x, cv_sync[x])
        cpl.append(portsim.cpc_ram(c, lo, hi))
        c.keys = keys_walk(c.frame, 1)         # touches du tick, dès son début
    elif pc == skip and c.mem[pc] == skip_op:
        cnt['s'] += 1


def keys_walk(f, cur=0):
    # cur = 1 : appelé au début d'un tick déjà compté dans cpl
    k = set(keys(f))
    if walk and s2['t0'] is not None and len(cpl) - cur - s2['t0'] >= WALK_AFTER:
        k.add(P.RIGHT_CPC)
    return k


c.run_frames(75, keys_walk, prof=prof)
out = []
for s in range(secs):
    cnt['a'] = cnt['s'] = 0
    c.run_frames(50, keys_walk, prof=prof)
    out.append(f"{cnt['a']}/{cnt['a'] + cnt['s']}")
print('CPC     ticks/NMI par seconde :', ' '.join(out))

# --- état tick par tick, depuis l'entrée en jeu (sans port_config.TICKS_IGNORE) ---
if st['t0'] is None or s2['t0'] is None:
    sys.exit(f'état {P.ALIGN} jamais vu (Coleco {st["t0"]}, CPC {s2["t0"]}) : régler port_config.ALIGN')
keep = [k for k in range(hi - lo) if not any(x <= lo + k <= y for x, y in P.TICKS_IGNORE)]
if '--detail' in sys.argv:
    keep = list(range(hi - lo))
a, b = cvl[st['t0']:], cpl[s2['t0']:]
m = min(len(a), len(b))
bad = {}
for i in range(m):
    d = [k for k in keep if a[i][k] != b[i][k]]
    if d:
        bad[i] = d
print(f"{m} ticks comparés depuis l'entrée en jeu, {len(bad)} différents", sorted(bad)[:10])
if bad and '--detail' not in sys.argv:
    i = min(bad)
    print(f'tick {i} :', ' '.join(f'${lo + k:04X} Coleco {a[i][k]:02X} CPC {b[i][k]:02X}' for k in bad[i][:8]))
if '--detail' in sys.argv:
    import collections
    per = collections.Counter(lo + k for d in bad.values() for k in d)
    print('adresses différentes (nombre de ticks) :')
    print(' '.join(f'${x:04X}:{v}' for x, v in sorted(per.items())))
if '--show' in sys.argv:                  # --show 6134,6135 [--from T] [--to T]
    addrs = [int(x, 16) for x in sys.argv[sys.argv.index('--show') + 1].split(',')]
    t0 = int(sys.argv[sys.argv.index('--from') + 1]) if '--from' in sys.argv else 0
    t1 = int(sys.argv[sys.argv.index('--to') + 1]) if '--to' in sys.argv else m
    print('tick  ' + '  '.join(f'${x:04X}' for x in addrs) + '   (Coleco | CPC)')
    for i in range(t0, min(t1, m)):
        u = ' '.join(f'{a[i][x - lo]:02X}' for x in addrs)
        v = ' '.join(f'{b[i][x - lo]:02X}' for x in addrs)
        print(f'{i:4}  {u}  |  {v}' + ('   *' if u != v else ''))
