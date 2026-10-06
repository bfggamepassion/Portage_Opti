"""ColecoVision simulée AVEC le vrai BIOS, pour étudier le jeu (re/<GAME>.col) :
exécute la ROM d'origine, trace la couverture de code (octets exécutés),
les instructions d'E/S (port, PC) et les écritures VDP, et fait des images.

Usage :
  python tools/cvrun.py [trames] [--shot N,N,...] [--keys script] [--save f]
Images : build/cv_NNNN.png ; couverture : re/coverage.bin (1 = début
d'instruction exécutée), re/io.txt (E/S par PC).
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import cvsim  # noqa: E402
import port_config  # noqa: E402
from cvsim import Coleco, parse_keys, LINE_T, FRAME_T, VBLANK_LINE  # noqa: E402
from sim64 import Simulator  # noqa: E402


class Mem(bytearray):
    """64 Ko de la ColecoVision : BIOS et cartouche en lecture seule, 1 Ko de
    RAM répété de $6000 à $7FFF."""
    def __getitem__(self, a):
        if type(a) is int and 0x6000 <= a < 0x8000:
            a = 0x6000 | (a & 0x3FF)
        return bytearray.__getitem__(self, a)

    def __setitem__(self, a, v):
        if type(a) is int:
            if 0x6000 <= a < 0x8000:
                bytearray.__setitem__(self, 0x6000 | (a & 0x3FF), v)
            elif self.rom_protect and (a < 0x2000 or a >= 0x8000):
                self.rom_writes += 1
            elif self.rom_protect:
                self.unmapped_writes += 1
            else:
                bytearray.__setitem__(self, a, v)
        else:
            bytearray.__setitem__(self, a, v)


class ColecoBios(Coleco):
    def __init__(self):
        self.mem = Mem(65536)
        self.mem.rom_protect = False
        self.mem.rom_writes = self.mem.unmapped_writes = 0
        bios = open(os.path.join(ROOT, 're', 'coleco_bios.rom'), 'rb').read()
        rom = open(os.path.join(ROOT, 're', port_config.GAME + '.col'), 'rb').read()
        self.mem[0:len(bios)] = bios
        self.mem[0x8000:0x8000 + len(rom)] = rom
        self.mem[0x8000 + len(rom):0x10000] = b'\xFF' * (0x8000 - len(rom))
        self.mem.rom_protect = True
        self.sim = Simulator(self.mem, {'SP': 0x73FF})
        self.sim.set_tracer(self)
        self.r = self.sim.registers
        self.r[24] = 0
        self.vdp = cvsim.VDP()
        self.next_vb = VBLANK_LINE * LINE_T
        self.nmi_pending = False
        self.in_nmi = False
        self.nmi_start = 0
        self.nmi_sp = 0
        self.nmi_latch_busy = False
        self.nmi_times = []
        self.last_access = -10 ** 9
        self.errors = []
        self.ctrl_mode = 'joy'
        self.joy = set()
        self.frame = 0
        self.vdp_accesses = 0
        self.cov = bytearray(65536)
        self.io = Counter()
        self.nmi_line = False
        self.nmi_count = 0
        self.in_nmi = 0
        self.bad_mem = Counter()
        self.post_hooks = {}       # PC -> fonction(self), appelée après l'instruction

    def nmi(self):
        depth = self.in_nmi
        Coleco.nmi(self)
        self.in_nmi = depth + 1

    def read_port(self, registers, port):
        self.io[('in', port & 0xFF, self.r[24])] += 1
        return super().read_port(registers, port)

    def write_port(self, registers, port, value, offset=0):
        self.io[('out', port & 0xFF, self.r[24])] += 1
        return super().write_port(registers, port, value, offset)

    def run_frames(self, n, keys=None, shots=(), on_frame=None):
        opcodes = self.sim.opcodes
        mem = self.mem
        r = self.r
        cov = self.cov
        post = self.post_hooks
        end_frame = self.frame + n
        while self.frame < end_frame:
            pc = r[24]
            cov[pc] = 1
            if self.in_nmi and mem[pc] == 0xED and mem[pc + 1] in (0x45, 0x4D):     # RETN/RETI
                opcodes[0xED]()
                self.in_nmi -= 1
                self.nmi_times.append(r[25] - self.nmi_start)
            else:
                opcodes[mem[pc]]()
            if pc in post:                               # après l'instruction (ticks.py)
                post[pc](self)
            line = (self.vdp.status & 0x80) and (self.vdp.reg[1] & 0x20)
            if line and not self.nmi_line:
                self.nmi_count += 1
                self.nmi()
            self.nmi_line = line
            if r[25] >= self.next_vb:
                self.next_vb += FRAME_T
                self.frame += 1
                self.vdp.status |= 0x80
                if keys is not None:
                    self.joy = keys(self.frame)
                if self.frame in shots:
                    self.screenshot(os.path.join(ROOT, 'build', f'cv_{self.frame:04d}.png'))
                if on_frame:
                    on_frame(self)
        # ROM (BIOS, cartouche) : les écritures n'ont pas d'effet sur une vraie console
        # (pas vérifié ici : SkoolKit écrit partout)


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
    cv = ColecoBios()
    cv.run_frames(n, keys, shots)
    print(f'{cv.frame} trames, {len(cv.nmi_times)} NMI, VDP regs', [hex(x) for x in cv.vdp.reg])
    cov_path = os.path.join(ROOT, 're', 'coverage.bin')
    old = bytearray(open(cov_path, 'rb').read()) if os.path.exists(cov_path) else bytearray(65536)
    for a in range(65536):
        old[a] |= cv.cov[a]
    open(cov_path, 'wb').write(old)
    with open(os.path.join(ROOT, 're', 'io.txt'), 'w') as f:
        for (d, p, pc), c in sorted(cv.io.items(), key=lambda x: x[0][2]):
            f.write(f'{pc:04X} {d:3} {p:02X} x{c}\n')
    return cv


if __name__ == '__main__':
    main()
