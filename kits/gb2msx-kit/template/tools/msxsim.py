"""MSX1 simulé (Z80 de SkoolKit + VDP TMS9918A + PSG/PPI pour les manettes),
pour tester la cartouche sans émulateur, et surtout VÉRIFIER LES ACCÈS AU
VDP comme sur une vraie machine :

- pendant l'affichage (lignes 0-191, écran allumé), deux accès à la mémoire
  vidéo doivent être espacés d'au moins MIN_GAP cycles (8 µs) ;
- l'interruption ne doit pas toucher au VDP pendant que la boucle principale
  est au milieu d'une écriture d'adresse ;
- durée de l'interruption.
(Le MSX ajoute un cycle d'attente par lecture d'instruction : les vrais
écarts sont un peu plus grands que ceux mesurés ici, donc plus sûrs.)

Faux BIOS : RSLREG ($0138) et ENASLT ($0024) rendent la main, $002B dit
60 Hz (ou 50 Hz avec --50).
Usage :
  python tools/msxsim.py [trames] [--50] [--shot N,N,...] [--keys script]
  script : suite de « trame:touches » ; touches parmi U D L R (joystick),
  1 2 (boutons A, B), S (ESPACE), M, K1-K4 (chiffres), ex. « 60:S 70: ».
Images : build/sim_NNNN.png
"""
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
from sim64 import Simulator  # noqa: E402  (SkoolKit, 64 Ko de RAM)
import tms  # noqa: E402

LINE_T = 228                    # cycles par ligne (NTSC, 3,58 MHz)
LINES = 262
FRAME_T = LINE_T * LINES        # 59 736
VBLANK_LINE = 192
MIN_GAP = 29                    # 8 µs entre deux accès VRAM pendant l'affichage

def symbols():
    sym = open(os.path.join(ROOT, 'build', 'tennis.sym')).read()
    return {m.group(1): int(m.group(2), 16)
            for m in re.finditer(r'^(\S+):\s+EQU\s+0x([0-9A-F]+)', sym, re.M)}


class VDP:
    def __init__(self):
        self.vram = bytearray(0x4000)
        self.reg = [0] * 8
        self.addr = 0
        self.latch = None
        self.status = 0
        self.readbuf = 0


class MSX:
    def __init__(self, rom_path=None, hz50=False):
        self.mem = bytearray(65536)
        rom = open(rom_path or os.path.join(ROOT, 'build', 'tennis.rom'), 'rb').read()
        self.mem[0x4000:0x4000 + len(rom)] = rom
        self.mem[0x0024] = 0xC9                                 # ENASLT
        self.mem[0x0138:0x013A] = bytes([0xAF, 0xC9])           # RSLREG : xor a / ret
        self.mem[0x002B] = 0x80 if hz50 else 0
        self.lines = 313 if hz50 else 262
        self.frame_t = self.lines * LINE_T
        self.sim = Simulator(self.mem, {'SP': 0xF380})
        self.sim.set_tracer(self)
        self.r = self.sim.registers
        self.r[24] = self.mem[0x4002] | (self.mem[0x4003] << 8)
        self.psg_reg = 0
        self.psg = [0] * 16
        self.ppi_c = 0
        self.vdp = VDP()
        self.next_vb = VBLANK_LINE * LINE_T
        self.nmi_pending = False
        self.in_nmi = False
        self.nmi_start = 0
        self.nmi_sp = 0
        self.nmi_latch_busy = False
        self.nmi_times = []
        self.last_access = -10 ** 9
        self.errors = []
        self.joy = set()
        self.frame = 0
        self.vdp_accesses = 0

    # --- ports -----------------------------------------------------------------
    def t(self):
        return self.r[25]

    def active(self, t):
        return (self.vdp.reg[1] & 0x40) and (t % self.frame_t) // LINE_T < VBLANK_LINE

    def access(self, what):
        t = self.t()
        self.vdp_accesses += 1
        if self.active(t) and t - self.last_access < MIN_GAP:
            self.error(f'accès VRAM trop rapide ({t - self.last_access} T, {what}) '
                       f'ligne {(t % self.frame_t) // LINE_T}')
        self.last_access = t

    def error(self, msg):
        pc = self.r[24]
        if len(self.errors) < 30:
            self.errors.append(f'trame {self.frame} PC ${pc:04X}{" (interruption)" if self.in_nmi else ""} : {msg}')

    def read_port(self, registers, port):
        p = port & 0xFF
        v = self.vdp
        if p in (0x98, 0x99):
            if self.in_nmi and self.nmi_latch_busy:
                self.error("l'interruption lit le VDP pendant une écriture d'adresse du programme")
            if p & 1:                                   # état
                s = v.status
                v.status &= 0x1F
                v.latch = None
                return s
            self.access('lecture')
            val = v.readbuf
            v.readbuf = v.vram[v.addr]
            v.addr = (v.addr + 1) & 0x3FFF
            v.latch = None
            return val
        k = self.joy
        if p == 0xA2:                                   # PSG
            if self.psg_reg == 14:
                if self.psg[15] & 0x40:
                    return 0x3F                         # port 2 : rien
                b = 0x3F
                for bit, key in ((0, 'U'), (1, 'D'), (2, 'L'), (3, 'R'), (4, '1'), (5, '2')):
                    if key in k:
                        b &= ~(1 << bit)
                return b
            return self.psg[self.psg_reg]
        if p == 0xA9:                                   # clavier
            row = self.ppi_c & 0x0F
            b = 0xFF
            if row == 8 and 'S' in k:
                b &= ~0x01
            if row == 4 and 'M' in k:
                b &= ~0x04
            if row == 0:
                for key in k:
                    if key.startswith('K'):
                        b &= ~(1 << int(key[1:]))
            return b
        if p == 0xAA:
            return self.ppi_c
        return 0xFF

    def write_port(self, registers, port, value, offset=0):
        p = port & 0xFF
        v = self.vdp
        if p == 0xA0:
            self.psg_reg = value & 15
        elif p == 0xA1:
            self.psg[self.psg_reg] = value
            if self.psg_reg == 7 and (value & 0xC0) != 0x80:
                self.error(f'PSG registre 7 = ${value:02X} (bits 7-6 doivent valoir 10)')
        elif p == 0xAA:
            self.ppi_c = value
        elif p in (0x98, 0x99):
            if self.in_nmi and self.nmi_latch_busy:
                self.error("l'interruption écrit au VDP pendant une écriture d'adresse du programme")
            if p & 1:                                   # contrôle
                if v.latch is None:
                    v.latch = value
                    return
                lo, v.latch = v.latch, None
                if value & 0x80:
                    old = v.reg[1]
                    v.reg[value & 7] = lo
                    if (value & 7) == 1 and (lo & 0x20) and not (old & 0x20) and (v.status & 0x80):
                        self.nmi_pending = True         # NMI validée avec l'indicateur levé
                else:
                    v.addr = ((value & 0x3F) << 8) | lo
                    if not (value & 0x40):
                        self.access('adresse (lecture)')
                        v.readbuf = v.vram[v.addr]
                        v.addr = (v.addr + 1) & 0x3FFF
                return
            self.access('écriture')
            v.vram[v.addr] = value
            v.readbuf = value
            v.addr = (v.addr + 1) & 0x3FFF
            v.latch = None

    # --- exécution --------------------------------------------------------------
    def run_frames(self, n, keys=None, shots=(), on_frame=None):
        opcodes = self.sim.opcodes
        mem = self.mem
        r = self.r
        v = self.vdp
        end_frame = self.frame + n
        while self.frame < end_frame:
            pc = r[24]
            if self.in_nmi and mem[pc] == 0xED and mem[pc + 1] == 0x4D:     # RETI
                opcodes[0xED]()
                self.in_nmi = False
                self.nmi_times.append(r[25] - self.nmi_start)
            else:
                opcodes[mem[pc]]()
            if r[25] >= self.next_vb:
                self.next_vb += self.frame_t
                self.frame += 1
                v.status |= 0x80
                if keys is not None:
                    self.joy = keys(self.frame)
                if self.frame in shots:
                    self.screenshot(os.path.join(ROOT, 'build', f'sim_{self.frame:04d}.png'))
                if on_frame:
                    on_frame(self)
            if (v.status & 0x80) and (v.reg[1] & 0x20) and r[26] and not self.in_nmi:
                self.nmi_latch_busy = v.latch is not None
                if self.sim.accept_interrupt(r, mem, pc):
                    self.in_nmi = True
                    self.nmi_start = r[25]

    # --- image -----------------------------------------------------------------
    def render(self):
        v = self.vdp
        vr = v.vram
        name = (v.reg[2] & 0x0F) * 0x400
        pat = (v.reg[4] & 0x04) * 0x800
        col = (v.reg[3] & 0x80) * 0x40
        sat = (v.reg[5] & 0x7F) * 0x80
        spat = (v.reg[6] & 0x07) * 0x800
        img = Image.new('RGB', (256, 192), tms.PALETTE[v.reg[7] & 15])
        px = img.load()
        if not (v.reg[1] & 0x40):
            return img
        back = v.reg[7] & 15
        for r in range(24):
            for c in range(32):
                t = vr[name + r * 32 + c] + (r // 8) * 256
                for y in range(8):
                    p = vr[pat + t * 8 + y]
                    cc = vr[col + t * 8 + y]
                    fg, bg = cc >> 4, cc & 15
                    for x in range(8):
                        k = fg if p & (0x80 >> x) else bg
                        px[c * 8 + x, r * 8 + y] = tms.PALETTE[k or back]
        size = 16 if v.reg[1] & 2 else 8
        per_line = [0] * 192
        drawn = [[False] * 256 for _ in range(192)]
        for s in range(32):
            y, x, p, c = vr[sat + s * 4:sat + s * 4 + 4]
            if y == 0xD0:
                break
            y = y + 1 if y < 0xE1 else y - 255
            if c & 0x80:
                x -= 32
            if size == 16:
                p &= 0xFC
            for dy in range(size):
                yy = y + dy
                if not 0 <= yy < 192:
                    continue
                per_line[yy] += 1
                if per_line[yy] > 4:
                    continue
                for dx in range(size):
                    xx = x + dx
                    if not 0 <= xx < 256 or drawn[yy][xx]:
                        continue
                    b = vr[spat + p * 8 + (dx // 8) * 16 + dy]
                    if b & (0x80 >> (dx % 8)) and (c & 15):
                        px[xx, yy] = tms.PALETTE[c & 15]
                        drawn[yy][xx] = True
        return img

    def screenshot(self, path, scale=2):
        self.render().resize((256 * scale, 192 * scale), Image.NEAREST).save(path)


def parse_keys(script):
    ev = []
    for tok in script.split():
        f, _, k = tok.partition(':')
        keys = set()
        i = 0
        while i < len(k):
            if k[i] == 'K':
                keys.add(k[i:i + 2])
                i += 2
            else:
                keys.add(k[i])
                i += 1
        ev.append((int(f), keys))
    ev.sort(key=lambda e: e[0])

    def keys_at(frame):
        cur = set()
        for f, k in ev:
            if f <= frame:
                cur = k
        return cur
    return keys_at


def main():
    args = sys.argv[1:]
    n = 300
    shots = set()
    keys = None
    i = 0
    while i < len(args):
        if args[i] == '--50':
            i += 1
        elif args[i] == '--shot':
            shots = {int(x) for x in args[i + 1].split(',')}
            i += 2
        elif args[i] == '--keys':
            keys = parse_keys(args[i + 1])
            i += 2
        else:
            n = int(args[i])
            i += 1
    cv = MSX(hz50='--50' in sys.argv)
    cv.run_frames(n, keys, shots)
    t = cv.nmi_times
    print(f'{cv.frame} trames, {len(t)} interruptions (max {max(t) if t else 0} T, '
          f'budget du retour de trame {(cv.lines - VBLANK_LINE) * LINE_T} T), '
          f'{cv.vdp_accesses} accès VDP')
    print('ERREURS VDP :' if cv.errors else 'accès VDP : aucune erreur')
    for e in cv.errors:
        print(' ', e)
    return cv


if __name__ == '__main__':
    main()
