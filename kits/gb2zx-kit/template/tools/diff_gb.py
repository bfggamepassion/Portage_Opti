"""Comparaison pas à pas : ROM Game Boy (PyBoy) contre logique traduite (Z80).

C'est LE test de fidélité de la traduction.
1. Le vrai jeu GB tourne dans PyBoy ; le robot (CFG.Bot) joue. À chaque trame
   de jeu (CFG.gb_in_play), on relève la RAM GB (CFG.REGIONS).
2. Pour chaque trame i, on recopie l'état GB de la trame i-1 dans le Spectrum
   émulé (CFG.TAP chargé par zxrun.py), on appelle la routine CFG.TICK_SYMBOL
   (un pas de logique traduit) et on compare la RAM obtenue (CFG.COMPARE,
   CFG.MASK) à l'état GB de la trame i.

À exclure de COMPARE : le joypad (lu après la logique), le hasard s'il avance
pendant l'attente de l'interruption, et tout ce que seul l'affichage GB écrit
(défilement, OAM, compteurs de VBlank, tampons de texte).

Prérequis : avoir lancé une fois zxrun.py sur le .tap (crée build/run/loaded.z80).
Usage : python tools/diff_gb.py [nombre_de_trames]
Dépendances : pip install pyboy skoolkit
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import zxrun  # noqa: E402
from gbrom import CFG, path  # noqa: E402
from pyboy import PyBoy  # noqa: E402
from skoolkit import CSimulator  # noqa: E402
from skoolkit.simutils import from_snapshot  # noqa: E402
from skoolkit.snapshot import Snapshot  # noqa: E402

COMPARE = list(CFG.COMPARE)
MASK = dict(getattr(CFG, 'MASK', {}))


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


def z80_setup():
    sym = open(path(CFG.SYM)).read()
    m = re.search(r'^' + re.escape(CFG.TICK_SYMBOL) + r':\s+EQU\s+0x([0-9A-F]+)', sym, re.M)
    snap = os.path.join(os.path.dirname(path(CFG.TAP)), 'run', 'loaded.z80')
    sim = from_snapshot(CSimulator, Snapshot.get(snap))
    sim.set_tracer(zxrun.Tracer())
    return sim, int(m.group(1), 16)


def z80_tick(sim, tick_addr, state):
    """Charge l'état GB, exécute un pas de logique Z80, renvoie la RAM obtenue.
    Pile et adresse de retour factices sous $6000 (à adapter à la carte mémoire)."""
    mem = sim.memory
    for a, v in state.items():
        mem[a] = v
    stop = 0x5FF0
    sp = 0x5FE0
    mem[sp] = stop & 0xFF
    mem[sp + 1] = stop >> 8
    regs = sim.registers
    regs[12] = sp                       # SP
    regs[24] = tick_addr                # PC
    regs[26] = 0                        # interruptions coupées
    sim.trace(tick_addr, stop, 0, 0, False, None, None, None, None, None)
    return {a: mem[a] for a in state}


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    states = run_gb(n)
    sim, tick = z80_setup()
    compared = mismatched = skipped = 0
    first = []
    for i in range(2, len(states)):
        before, after = states[i - 1], states[i]
        if before is None or after is None or states[i - 2] is None:
            continue                    # hors jeu, ou première trame de jeu
        if not CFG.gb_logic_ran(before, after):
            continue
        if all(before[a] == after[a] for a in COMPARE):
            skipped += 1
            continue                    # le GB n'a pas exécuté de pas de logique
        got = z80_tick(sim, tick, before)
        compared += 1
        diff = [a for a in COMPARE if (got[a] ^ after[a]) & MASK.get(a, 0xFF)]
        if diff:
            mismatched += 1
            if len(first) < 8:
                first.append((i, [(f'{a:04X}', f'{after[a]:02X}', f'{got[a]:02X}') for a in diff[:10]]))
    print(f'{compared} pas de logique comparés, {mismatched} différents '
          f'({skipped} trames sans pas de logique ignorées)')
    for i, d in first:
        print(f'  trame {i} : (adresse, GB, Z80)', d)


if __name__ == '__main__':
    main()
