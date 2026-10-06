"""MO5 simulé (tools/m6809.py + écran, PIA système, circuit vidéo, clavier),
pour tester le programme sans DCMOTO, mesurer le temps et faire des images.

- $0000-$1FFF : écran, banque « forme » si le bit 0 de $A7C0 vaut 1,
  sinon banque « couleur » ;
- $A7C1 : écriture = touche à tester (bits 1-6) et buzzer (bit 0) ; lecture :
  bit 7 = 0 si la touche est appuyée ; la lecture efface l'indicateur de
  trame (bit 7 de $A7C3, levé à chaque trame de 50 Hz) ;
- $A7E7 : bit 7 = 1 pendant les 200 lignes de l'image ;
- $A7CC/$A7CD : manette de l'extension jeux (rien d'appuyé).
Trame : 312 lignes de 64 µs = 19 968 cycles.
Usage : python tools/mo5sim.py [trames] [--shot N,...] [--keys script]
  touches : U D L R (flèches), S (ESPACE), M, 1-4, E (ENTRÉE) ; ex. « 50:S 55: »
"""
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import m6809  # noqa: E402
import mo5pal as P  # noqa: E402

FRAME = 19968
ACTIVE = 200 * 64
KEYS = {'U': 0x62, 'L': 0x52, 'D': 0x42, 'R': 0x32, 'S': 0x40, 'M': 0x34, 'E': 0x68,
        '1': 0x5E, '2': 0x4E, '3': 0x3E, '4': 0x2E}
LOAD = 0x3000


def symbols():
    txt = open(os.path.join(ROOT, 'build', 'tennis.sym')).read()
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'^(\S+)\s+equ\s+(\d+)', txt, re.M)}


class MO5:
    def __init__(self, binpath=None):
        self.cpu = cpu = m6809.CPU()
        data = open(binpath or os.path.join(ROOT, 'build', 'tennis.bin'), 'rb').read()
        cpu.mem[LOAD:LOAD + len(data)] = data
        self.form = bytearray(0x2000)
        self.color = bytearray(0x2000)
        self.pia_a = 1
        self.pia_b = 0
        self.crb_flag = 0
        self.keys = set()
        self.frame = 0
        self.next_frame = FRAME
        for a in range(0x2000):
            cpu.special[a] = 1
        for a in range(0xA7C0, 0xA800):
            cpu.special[a] = 1
        cpu.read_hook = self.rd
        cpu.write_hook = self.wr
        cpu.pc = LOAD
        cpu.s = 0x9D00

    def rd(self, a):
        if a < 0x2000:
            return (self.form if self.pia_a & 1 else self.color)[a]
        if a == 0xA7C0:
            return self.pia_a | 0x80
        if a == 0xA7C1:
            self.crb_flag = 0
            code = self.pia_b & 0x7E
            pressed = any(KEYS.get(k) == code for k in self.keys)
            return (self.pia_b & 0x7F) | (0 if pressed else 0x80)
        if a == 0xA7C3:
            return 0x04 | (0x80 if self.crb_flag else 0)
        if a == 0xA7E7:
            return 0x80 if (self.cpu.cycles % FRAME) < ACTIVE else 0
        if a in (0xA7CC, 0xA7CD):
            return 0xFF
        return 0xFF

    def wr(self, a, v):
        if a < 0x2000:
            (self.form if self.pia_a & 1 else self.color)[a] = v
            return True
        if a == 0xA7C0:
            self.pia_a = v
        elif a == 0xA7C1:
            self.pia_b = v
        return True

    def run_frames(self, n, keys=None, shots=(), on_frame=None, max_steps=None):
        cpu = self.cpu
        end = self.frame + n
        step = cpu.step
        while self.frame < end:
            step()
            if cpu.cycles >= self.next_frame:
                self.next_frame += FRAME
                self.frame += 1
                self.crb_flag = 1
                if keys:
                    self.keys = keys(self.frame)
                if self.frame in shots:
                    self.screenshot(os.path.join(ROOT, 'build', f'sim_{self.frame:04d}.png'))
                if on_frame:
                    on_frame(self)

    def render(self):
        im = Image.new('RGB', (320, 200))
        px = im.load()
        pal = P.PALETTE
        for y in range(200):
            for cx in range(40):
                f = self.form[y * 40 + cx]
                c = self.color[y * 40 + cx]
                fg, bg = pal[c >> 4], pal[c & 15]
                for x in range(8):
                    px[cx * 8 + x, y] = fg if f & (0x80 >> x) else bg
        return im

    def screenshot(self, path):
        self.render().resize((640, 400), Image.NEAREST).save(path)


def parse_keys(script):
    ev = []
    for tok in script.split():
        f, _, k = tok.partition(':')
        ev.append((int(f), set(k)))
    ev.sort(key=lambda e: e[0])

    def at(frame):
        cur = set()
        for f, k in ev:
            if f <= frame:
                cur = k
        return cur
    return at


def main():
    args = sys.argv[1:]
    n, shots, keys = 100, set(), None
    i = 0
    while i < len(args):
        if args[i] == '--shot':
            shots = {int(x) for x in args[i + 1].split(',')}
            i += 2
        elif args[i] == '--keys':
            keys = parse_keys(args[i + 1])
            i += 2
        else:
            n = int(args[i])
            i += 1
    mo = MO5()
    mo.run_frames(n, keys, shots)
    print(f'{mo.frame} trames simulées, PC ${mo.cpu.pc:04X}')
    return mo


if __name__ == '__main__':
    main()
