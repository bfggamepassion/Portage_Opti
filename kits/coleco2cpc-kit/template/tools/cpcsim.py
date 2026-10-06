"""CPC 6128 simulé (Z80 de SkoolKit + 128 Ko en banques + Gate Array, CRTC,
PPI, clavier, interruptions), pour déboguer et mesurer le portage sans
émulateur.

  python tools/cpcsim.py [trames] [--shot N,N,...] [--keys script] [--prof]
  script : « trame:touches » ; touches : noms de key_pos (ex. 1 SPACE UP).
Images : build/cpc_NNNN.png

Temps : chaque instruction compte ceil(T/4) microsecondes (arrondi du CPC).
Une trame = 312 lignes de 64 us ; interruption toutes les 52 lignes, calée
2 lignes après le début du VSYNC (ligne R7 x 8, 8 lignes).
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
from sim64 import Simulator  # noqa: E402

LINE_US = 64
FRAME_LINES = 312
FRAME_US = LINE_US * FRAME_LINES

# (ligne, bit) du clavier
KEY_POS = {
    'UP': (0, 0), 'RIGHT': (0, 1), 'DOWN': (0, 2), 'LEFT': (1, 0), 'COPY': (1, 1),
    'SPACE': (5, 7), 'RETURN': (2, 2), 'M': (4, 6),
    '1': (8, 0), '2': (8, 1), '3': (7, 1), '4': (7, 0), '5': (6, 1), '6': (6, 0),
    '7': (5, 1), '8': (5, 0), '9': (4, 1), '0': (4, 0),
    'T': (6, 3), 'N': (5, 6), 'Q': (8, 3), 'A': (8, 5), 'O': (4, 2), 'P': (3, 3),
    'J0U': (9, 0), 'J0D': (9, 1), 'J0L': (9, 2), 'J0R': (9, 3), 'J0F2': (9, 4), 'J0F1': (9, 5),
}

# palette matérielle -> RVB
HW_RGB = {0x54: (0, 0, 0), 0x44: (0, 0, 128), 0x55: (0, 0, 255), 0x5C: (128, 0, 0),
          0x58: (128, 0, 128), 0x5D: (128, 0, 255), 0x4C: (255, 0, 0), 0x45: (255, 0, 128),
          0x4D: (255, 0, 255), 0x56: (0, 128, 0), 0x46: (0, 128, 128), 0x57: (0, 128, 255),
          0x5E: (128, 128, 0), 0x40: (128, 128, 128), 0x5F: (128, 128, 255), 0x4E: (255, 128, 0),
          0x47: (255, 128, 128), 0x4F: (255, 128, 255), 0x52: (0, 255, 0), 0x42: (0, 255, 128),
          0x53: (0, 255, 255), 0x5A: (128, 255, 0), 0x59: (128, 255, 128), 0x5B: (128, 255, 255),
          0x4A: (255, 255, 0), 0x43: (255, 255, 128), 0x4B: (255, 255, 255)}
MMR_MAP = {0: (0, 1, 2, 3), 1: (0, 1, 2, 7), 2: (4, 5, 6, 7), 3: (0, 3, 2, 7),
           4: (0, 4, 2, 3), 5: (0, 5, 2, 3), 6: (0, 6, 2, 3), 7: (0, 7, 2, 3)}


class CPC:
    def __init__(self, bin_path=None, load=0x0400, entry=0x9E00):
        self.ram = bytearray(8 * 0x4000)          # blocs 0-3 : base, 4-7 : banques
        data = open(bin_path or os.path.join(ROOT, 'build', __import__('port_config').GAME + '.bin'), 'rb').read()
        self.ram[load:load + len(data)] = data
        self.mem = bytearray(65536)
        self.map = (0, 1, 2, 3)
        self.mem[:] = self.ram[0:0x10000]
        self.sim = Simulator(self.mem, {'SP': 0xBFF0})
        self.sim.set_tracer(self)
        self.r = self.sim.registers
        self.r[24] = entry
        self.us = 0
        self.pens = [0x54] * 17
        self.pen = 0
        self.mode = 1
        self.crtc = [0] * 18
        self.crtc_sel = 0
        self.ppi_c = 0
        self.ppi_a_out = 0
        self.psg_sel = 0
        self.psg = [0] * 16
        self.keys = set()
        self.ppi_a_in = False
        self.kb_errors = []
        self.int_line = 0          # compteur de lignes du Gate Array
        self.int_pending = False
        self.line = 0
        self.frame = 0
        self.frame_base = 0x30
        self.writes_rom = 0
        self.stats = {}

    # --- mémoire en banques -------------------------------------------------------
    def set_map(self, new):
        if new == self.map:
            return
        for i, b in enumerate(self.map):
            self.ram[b * 0x4000:(b + 1) * 0x4000] = self.mem[i * 0x4000:(i + 1) * 0x4000]
        # un même bloc peut apparaître deux fois : relire après écriture
        for i, b in enumerate(new):
            self.mem[i * 0x4000:(i + 1) * 0x4000] = self.ram[b * 0x4000:(b + 1) * 0x4000]
        self.map = new

    def phys(self):
        """Écrit la fenêtre courante dans la RAM physique (pour lire l'écran)."""
        for i, b in enumerate(self.map):
            self.ram[b * 0x4000:(b + 1) * 0x4000] = self.mem[i * 0x4000:(i + 1) * 0x4000]

    # --- ports -----------------------------------------------------------------------
    def read_port(self, registers, port):
        hi = (port >> 8) & 0xFF
        if not (hi & 0x08):                          # PPI
            fn = hi & 3
            if fn == 1:                              # port B : VSYNC en bit 0
                vs = self.vsync_line()
                return 0x7E | (1 if vs else 0)
            if fn == 0:                              # port A : PSG
                if not self.ppi_a_in:
                    self.kb_errors.append(f'lecture du port A en sortie (PC ${self.r[24]:04X})')
                    return self.ppi_a_out
                if (self.ppi_c >> 6) != 1:
                    self.kb_errors.append(f'lecture du PSG hors fonction lecture (PC ${self.r[24]:04X})')
                    return 0xFF
                if self.psg[7] & 0x40:
                    self.kb_errors.append(f'registre 7 du PSG : port A en sortie (PC ${self.r[24]:04X})')
                if self.psg_sel == 14:
                    line = self.ppi_c & 0x0F
                    v = 0xFF
                    for k in self.keys:
                        ln, bit = KEY_POS[k]
                        if ln == line:
                            v &= ~(1 << bit)
                    return v & 0xFF
                return self.psg[self.psg_sel]
        return 0xFF

    def write_port(self, registers, port, value, offset=0):
        hi = (port >> 8) & 0xFF
        if (hi & 0xC0) == 0x40:                      # Gate Array
            f = value >> 6
            if f == 0:
                self.pen = value & 0x1F
            elif f == 1:
                if self.pen & 0x10:
                    self.pens[16] = value | 0x40
                else:
                    self.pens[self.pen & 15] = value | 0x40
            elif f == 2:
                self.mode = value & 3
            else:
                self.set_map(MMR_MAP[value & 7])
        if not (hi & 0x40):                          # CRTC
            if (hi & 3) == 0:
                self.crtc_sel = value & 31
            elif (hi & 3) == 1 and self.crtc_sel < 18:
                self.crtc[self.crtc_sel] = value
        if not (hi & 0x08):                          # PPI
            fn = hi & 3
            if fn == 0:
                self.ppi_a_out = value
            elif fn == 3 and value & 0x80:
                self.ppi_a_in = bool(value & 0x10)
            elif fn == 2:
                self.ppi_c = value
                ctl = value >> 6
                if ctl == 3:
                    self.psg_sel = self.ppi_a_out & 15
                elif ctl == 2:
                    self.psg[self.psg_sel] = self.ppi_a_out

    def vsync_line(self):
        vs = self.crtc[7] * 8 if self.crtc[7] else 30 * 8
        ln = (self.us // LINE_US) % FRAME_LINES
        return vs <= ln < vs + 8

    # --- exécution ----------------------------------------------------------------------
    def run_frames(self, n, keys=None, shots=(), on_frame=None, prof=None):
        opcodes = self.sim.opcodes
        mem = self.mem
        r = self.r
        end = self.frame + n
        next_line_us = (self.us // LINE_US + 1) * LINE_US
        while self.frame < end:
            pc = r[24]
            t0 = r[25]
            op = mem[pc]
            opcodes[op]()
            dt = r[25] - t0
            self.us += (dt + 3) >> 2
            if prof is not None:
                prof(pc, (dt + 3) >> 2)
            while self.us >= next_line_us:
                next_line_us += LINE_US
                self.step_line(keys, shots, on_frame)
            if self.int_pending and r[26] and op != 0xFB:   # IFF1 (EI : une instruction de délai)
                self.int_pending = False
                self.int_line &= 0x1F                 # acquittement : bit 5 à 0
                self.accept_int()

    def accept_int(self):
        r = self.r
        if r[27] != 1:                               # IM 1 seulement
            pass
        pc = r[24]
        if self.mem[pc] == 0x76:                     # HALT
            pc = (pc + 1) & 0xFFFF
        sp = (r[12] - 2) & 0xFFFF
        self.mem[sp] = pc & 0xFF
        self.mem[(sp + 1) & 0xFFFF] = pc >> 8
        r[12] = sp
        r[26] = 0
        r[24] = 0x38
        r[25] += 13
        self.us += 4

    def step_line(self, keys, shots, on_frame):
        self.line = (self.line + 1) % FRAME_LINES
        vs = self.crtc[7] * 8 if self.crtc[7] else 30 * 8
        if self.line == vs + 2:
            # Gate Array : remise à zéro du compteur 2 lignes après le VSYNC
            if self.int_line >= 32:
                self.int_pending = True
            self.int_line = 0
        else:
            self.int_line += 1
            if self.int_line == 52:
                self.int_line = 0
                self.int_pending = True
        if self.line == 0:
            self.frame += 1
            self.frame_base = self.crtc[12]
            if keys is not None:
                self.keys = keys(self.frame)
            if self.frame in shots:
                self.screenshot(os.path.join(ROOT, 'build', f'cpc_{self.frame:04d}.png'))
            if on_frame:
                on_frame(self)

    # --- image ------------------------------------------------------------------------------
    def render(self):
        self.phys()
        base = ((self.frame_base >> 4) & 3) * 0x4000
        off = ((self.frame_base & 3) << 8 | self.crtc[13]) * 2
        w = self.crtc[1] * 2 or 64
        rows = self.crtc[6] or 24
        img = Image.new('RGB', (w * 2, rows * 8), HW_RGB.get(self.pens[16], (0, 0, 0)))
        px = img.load()
        for y in range(rows * 8):
            a0 = base + (y & 7) * 0x800 + ((off + (y >> 3) * w) & 0x7FF)
            for x in range(w):
                b = self.ram[base + (((a0 - base) & 0x3800) | ((a0 - base + x) & 0x7FF))]
                for i, pix in enumerate((
                        ((b >> 7) & 1) | ((b >> 2) & 2) | ((b >> 3) & 4) | ((b << 2) & 8),
                        ((b >> 6) & 1) | ((b >> 1) & 2) | ((b >> 2) & 4) | ((b << 3) & 8))):
                    px[x * 2 + i, y] = HW_RGB.get(self.pens[pix], (255, 0, 255))
        return img

    def screenshot(self, path):
        img = self.render()
        img.resize((img.width * 4, img.height * 2), Image.NEAREST).save(path)


def parse_keys(script):
    ev = []
    for tok in script.split():
        f, _, k = tok.partition(':')
        ev.append((int(f), set(x for x in k.split('+') if x)))
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
        if args[i] == '--shot':
            shots = {int(x) for x in args[i + 1].split(',')}
            i += 2
        elif args[i] == '--keys':
            keys = parse_keys(args[i + 1])
            i += 2
        else:
            n = int(args[i])
            i += 1
    cpc = CPC()
    cpc.run_frames(n, keys, shots)
    print(f'{cpc.frame} trames, PC ${cpc.r[24]:04X}, vue {cpc.map}')
    for e in sorted(set(cpc.kb_errors))[:20]:
        print('  ', e)
    return cpc


if __name__ == '__main__':
    main()
