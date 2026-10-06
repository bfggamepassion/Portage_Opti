"""Comparaison pas à pas : ROM Game Boy (PyBoy) contre logique traduite de la cartouche MSX
(HRAM GB déplacée : port_config.RAM_MAP).

Comme ../tools/diff_gb.py : pour chaque trame de match, l'état GB de la
trame précédente est recopié (aux adresses déplacées) dans la ColecoVision
simulée, gb_tick fait un pas de jeu, et la RAM obtenue est comparée à l'état
GB de la trame suivante.
Usage : python tools/diff_cv.py [trames GB]
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import diff_gb  # noqa: E402  (PyBoy + robot, liste des adresses comparées)
import msxsim  # noqa: E402

spec = importlib.util.spec_from_file_location('port_config', os.path.join(ROOT, 'port_config.py'))
cfg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cfg)
STOP = 0x0100


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    states = diff_gb.run_gb(n)
    sym = msxsim.symbols()
    cv = msxsim.MSX()
    mem = cv.mem
    r = cv.r
    compared = mismatched = skipped = 0
    first = []
    for i in range(1, len(states)):
        before, after = states[i - 1], states[i]
        if before is None or after is None or states[i - 2] is None:
            continue
        if before[0xFF8A] != after[0xFF8A] or after[0xFF8A] != 3:
            continue
        if all(before[a] == after[a] for a in diff_gb.COMPARE):
            skipped += 1
            continue
        for a, v in before.items():
            m = cfg.RAM_MAP(a)
            if m is not None:
                mem[m] = v
        sp = 0xC7F0
        mem[sp], mem[sp + 1] = STOP & 0xFF, STOP >> 8
        r[12] = sp
        r[26] = 0
        cv.sim.run(sym['gb_tick'], STOP)
        compared += 1
        diff = [a for a in diff_gb.COMPARE
                if (mem[cfg.RAM_MAP(a)] ^ after[a]) & diff_gb.MASK.get(a, 0xFF)]
        if diff:
            mismatched += 1
            if len(first) < 8:
                first.append((i, [(f'{a:04X}', f'{after[a]:02X}', f'{mem[cfg.RAM_MAP(a)]:02X}')
                                  for a in diff[:10]]))
    print(f'{compared} pas de jeu comparés, {mismatched} différents '
          f'({skipped} trames sans pas de jeu GB ignorées)')
    for i, d in first:
        print(f'  trame {i} : (adresse GB, GB, MSX)', d)


if __name__ == '__main__':
    main()
