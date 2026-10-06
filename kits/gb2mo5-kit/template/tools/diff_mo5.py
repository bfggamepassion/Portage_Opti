"""Comparaison pas à pas : ROM Game Boy (PyBoy) contre logique traduite en 6809.

Comme ../tools/diff_gb.py : pour chaque trame de match, l'état GB de la
trame précédente est recopié (aux adresses déplacées : port_config.RAM_MAP)
dans la mémoire du 6809 simulé (tools/m6809.py), gb_tick fait un pas de jeu,
et la RAM obtenue est comparée à l'état GB de la trame suivante.
Programme testé : build/logictest.bin (src/logictest.asm : logique seule).
Usage : python tools/diff_mo5.py [trames GB]
Affiche aussi le coût d'un pas de jeu en cycles 6809.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import diff_gb  # noqa: E402  (PyBoy + robot, liste des adresses comparées)
import m6809  # noqa: E402

spec = importlib.util.spec_from_file_location('port_config', os.path.join(ROOT, 'port_config.py'))
cfg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cfg)


def symbols(name):
    txt = open(os.path.join(ROOT, 'build', name)).read()
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'^(\S+)\s+equ\s+(\d+)', txt, re.M)}


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    states = diff_gb.run_gb(n)
    sym = symbols('logictest.sym')
    cpu = m6809.CPU()
    binf = open(os.path.join(ROOT, 'build', 'logictest.bin'), 'rb').read()
    cpu.mem[0x2600:0x2600 + len(binf)] = binf
    cpu.dp = 0x9F
    mem = cpu.mem
    compared = mismatched = skipped = 0
    first = []
    cycles = []
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
        cpu.s = 0x9CF0
        c0 = cpu.cycles
        cpu.call(sym['gb_tick'])
        cycles.append(cpu.cycles - c0)
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
        print(f'  trame {i} : (adresse GB, GB, MO5)', d)
    if cycles:
        cycles.sort()
        print(f'cycles 6809 par pas : moyenne {sum(cycles) // len(cycles)}, '
              f'médiane {cycles[len(cycles) // 2]}, 90 % {cycles[int(len(cycles) * .9)]}, '
              f'max {cycles[-1]}')


if __name__ == '__main__':
    main()
