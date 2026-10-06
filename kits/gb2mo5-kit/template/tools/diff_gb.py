"""Comparaison pas à pas : ROM Game Boy (PyBoy) contre logique traduite (Z80).

1. Le vrai jeu GB tourne dans PyBoy ; un robot joue le joueur 1. À chaque
   trame de match, on relève la RAM GB ($C000-$C0FF, $DD00-$DDFF, $FF80-$FFFE).
2. Pour chaque trame i, on recopie l'état GB de la trame i-1 dans le Spectrum
   émulé (asm/build/tennis.tap), on exécute gb_tick (un pas de jeu traduit)
   et on compare la RAM obtenue à l'état GB de la trame i.

Sont exclus de la comparaison : le joypad ($FF98-$FF9E, lu après la logique),
le hasard ($FFA4, qui avance pendant l'attente de l'interruption), et les
variables d'affichage GB (défilement, OAM, compteurs de VBlank).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import zxrun  # noqa: E402
from pyboy import PyBoy  # noqa: E402
from skoolkit import CSimulator  # noqa: E402
from skoolkit.simutils import from_snapshot  # noqa: E402
from skoolkit.snapshot import Snapshot  # noqa: E402

ROOT = os.path.join(HERE, '..')
ROM = os.path.join(ROOT, 're', 'game.gb')
TAP_DIR = os.path.join(ROOT, 'asm', 'build')

# Variables HRAM de la logique : déroulement du point, côté, gagnant, options,
# tour de jeu, IA, annonce, écart de sets
LOGIC_HRAM = [0xFF90, 0xFF91, 0xFF92, 0xFF93, 0xFF95, 0xFF96, 0xFFAD, 0xFFAE,
              0xFFB0, 0xFFB1, 0xFFB2, 0xFFB3, 0xFFB4, 0xFFB5, 0xFFB6, 0xFFB7, 0xFFB8, 0xFFB9,
              0xFFC2, 0xFFC4]
# $C0C0-$C0DA : tampon de texte rempli par l'affichage du score GB (hors logique)
COMPARE = list(range(0xC000, 0xC0C0)) + list(range(0xC0DB, 0xC100)) + LOGIC_HRAM
MASK = {0xFFC2: 0x7F}                   # bit 7 de $FFC2 : géré par l'affichage GB ($3318)
REGIONS = [(0xC000, 0xC100), (0xDD00, 0xDE00), (0xFF80, 0xFFFF)]


def gb_state(pb):
    return {a: pb.memory[a] for lo, hi in REGIONS for a in range(lo, hi)}


class GBBot:
    """Robot joueur 1 pour le jeu GB (même logique que zxrun.Bot)."""

    def __init__(self):
        self.bot = zxrun.Bot('0xC000')

    def buttons(self, mem, f):
        keys = self.bot.keys(mem, f)
        conv = {'SPACE': 'a', 'Q': 'up', 'A': 'down', 'O': 'left', 'P': 'right'}
        return [conv[k] for k in keys if k in conv]


def run_gb(frames):
    pb = PyBoy(ROM, window='null', sound_emulated=False)
    for _ in range(120):
        pb.tick()

    def press(b, n=5):
        pb.button_press(b)
        for _ in range(n):
            pb.tick()
        pb.button_release(b)
        for _ in range(30):
            pb.tick()
    press('start')          # titre -> sélection du niveau
    press('start')          # niveau 1 -> match
    bot = GBBot()
    mem = pb.memory
    states = []
    held = set()
    f = 0
    while len(states) < frames and f < frames * 3:
        want = set(bot.buttons(mem, f))
        for b in held - want:
            pb.button_release(b)
        for b in want - held:
            pb.button_press(b)
        held = want
        pb.tick()
        f += 1
        in_match = mem[0xFF8B] == 1 and mem[0xFFA5] == 0
        states.append(gb_state(pb) if in_match else None)
    pb.stop()
    return states


def z80_setup():
    sym = open(os.path.join(TAP_DIR, 'tennis.sym')).read()

    def addr(n):
        return int(re.search(r'^' + re.escape(n) + r':\s+EQU\s+0x([0-9A-F]+)', sym, re.M).group(1), 16)
    snap = os.path.join(TAP_DIR, 'run', 'loaded.z80')
    sim = from_snapshot(CSimulator, Snapshot.get(snap))
    sim.set_tracer(zxrun.Tracer())
    return sim, addr('gb_tick')


def z80_tick(sim, tick_addr, state):
    mem = sim.memory
    for a, v in state.items():
        mem[a] = v
    stop = 0x5FF0                       # adresse de retour factice
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
    for i in range(1, len(states)):
        before, after = states[i - 1], states[i]
        if before is None or after is None:
            continue
        if before[0xFF8A] != after[0xFF8A] or after[0xFF8A] != 3:
            continue                    # changement d'écran GB : hors logique
        if states[i - 2] is None:
            continue                    # première trame du match (état de l'écran précédent)
        if all(before[a] == after[a] for a in COMPARE):
            skipped += 1
            continue                    # le GB n'a pas exécuté de pas de jeu (changement d'écran)
        got = z80_tick(sim, tick, before)
        compared += 1
        diff = [a for a in COMPARE if (got[a] ^ after[a]) & MASK.get(a, 0xFF)]
        if diff:
            mismatched += 1
            if len(first) < 8:
                first.append((i, [(f'{a:04X}', f'{after[a]:02X}', f'{got[a]:02X}') for a in diff[:10]]))
    print(f'{compared} pas de jeu comparés, {mismatched} différents '
          f'({skipped} trames sans pas de jeu GB ignorées)')
    for i, d in first:
        print(f'  trame {i} : (adresse, GB, Z80)', d)


if __name__ == '__main__':
    main()
