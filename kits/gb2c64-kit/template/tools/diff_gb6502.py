"""Comparaison pas à pas : ROM Game Boy (PyBoy) contre logique traduite en 6502 (py65).

1. Le vrai jeu GB tourne dans PyBoy ; le robot (CFG.Bot) joue le joueur 1.
   À chaque trame de jeu, on relève la RAM GB (CFG.REGIONS).
2. Pour chaque trame i, on recopie l'état GB de la trame i-1 dans un 6502
   simulé (py65) où est chargé build/tennis.prg, on appelle gb_tick (un pas
   de logique traduit) et on compare la RAM obtenue à l'état GB de la trame i.
3. On mesure aussi les cycles 6502 de chaque pas : le C64 PAL dispose
   d'environ 19 650 cycles par trame (63 x 312), et doit faire 6 pas de
   logique toutes les 5 trames pour garder le rythme du GB.

Usage : python tools/diff_gb6502.py [nombre_de_trames]
Dépendances : pip install pyboy py65
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gbrom import CFG, path  # noqa: E402
from py65.devices.mpu6502 import MPU  # noqa: E402
from pyboy import PyBoy  # noqa: E402

COMPARE = list(CFG.COMPARE)
MASK = dict(getattr(CFG, 'MASK', {}))
STOP = 0x0300                           # adresse de retour factice


def labels():
    out = {}
    for line in open(path(CFG.SYM)):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            out[p[2].lstrip('.')] = int(p[1], 16)
    return out


def gb_state(pb):
    return {a: pb.memory[a] for lo, hi in CFG.REGIONS for a in range(lo, hi)}


def run_gb(frames):
    pb = PyBoy(path(CFG.ROM), window='null', sound_emulated=False)

    def press(b, n=5):
        pb.button_press(b)
        for _ in range(n):
            pb.tick()
        pb.button_release(b)
        for _ in range(30):
            pb.tick()
    CFG.gb_start(pb, press)
    bot = CFG.Bot()
    conv = CFG.Bot.GB_BUTTONS
    mem = pb.memory
    states = []
    held = set()
    f = 0
    while len(states) < frames and f < frames * 3:
        want = {conv[k] for k in bot.keys(mem, f) if k in conv}
        for b in held - want:
            pb.button_release(b)
        for b in want - held:
            pb.button_press(b)
        held = want
        pb.tick()
        f += 1
        states.append(gb_state(pb) if CFG.gb_in_play(mem) else None)
    pb.stop()
    return states


def load_mpu():
    mpu = MPU()
    prg = open(path(CFG.PRG), 'rb').read()
    load = prg[0] | (prg[1] << 8)
    mpu.memory[load:load + len(prg) - 2] = list(prg[2:])
    return mpu


def tick_6502(mpu, tick_addr, state):
    """Charge l'état GB, exécute gb_tick, renvoie (RAM obtenue, cycles)."""
    mem = mpu.memory
    for a, v in state.items():
        mem[a] = v
    mem[0x1FF] = (STOP - 1) >> 8
    mem[0x1FE] = (STOP - 1) & 0xFF
    mpu.sp = 0xFD
    mpu.pc = tick_addr
    mpu.y = 0
    c0 = mpu.processorCycles
    n = 0
    while mpu.pc != STOP:
        mpu.step()
        n += 1
        if n > 2_000_000:
            raise RuntimeError(f'pas de logique sans fin (PC = ${mpu.pc:04X})')
    return {a: mem[a] for a in state}, mpu.processorCycles - c0


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
    states = run_gb(n)
    lab = labels()
    mpu = load_mpu()
    tick = lab[CFG.TICK_SYMBOL]
    compared = mismatched = 0
    cycles = []
    first = []
    for i in range(2, len(states)):
        before, after = states[i - 1], states[i]
        if before is None or after is None or states[i - 2] is None:
            continue
        if not CFG.gb_logic_ran(before, after):
            continue
        if all(before[a] == after[a] for a in COMPARE):
            continue
        got, cyc = tick_6502(mpu, tick, before)
        cycles.append(cyc)
        compared += 1
        diff = [a for a in COMPARE if (got[a] ^ after[a]) & MASK.get(a, 0xFF)]
        if diff:
            mismatched += 1
            if len(first) < 8:
                first.append((i, [(f'{a:04X}', f'{after[a]:02X}', f'{got[a]:02X}') for a in diff[:10]]))
    print(f'{compared} pas de logique comparés, {mismatched} différents')
    for i, d in first:
        print(f'  trame {i} : (adresse, GB, 6502)', d)
    if cycles:
        cycles.sort()
        avg = sum(cycles) // len(cycles)
        print(f'cycles 6502 par pas : moyenne {avg}, médiane {cycles[len(cycles) // 2]}, '
              f'max {cycles[-1]} ; budget C64 PAL ~19650 par trame, 1,2 pas par trame')


if __name__ == '__main__':
    main()
