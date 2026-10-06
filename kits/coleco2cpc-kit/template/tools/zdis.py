"""Désassemble une plage : python tools/zdis.py ADR [N_instr] (mémoire = BIOS + cartouche)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import z80dis
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
mem = bytearray(65536)
bios = open(os.path.join(ROOT, 're', 'coleco_bios.rom'), 'rb').read()
rom = open(os.path.join(ROOT, 're', __import__('port_config').GAME + '.col'), 'rb').read()
mem[0:len(bios)] = bios
mem[0x8000:0x8000 + len(rom)] = rom
def dis(a, n):
    for _ in range(n):
        ins = z80dis.decode(mem, a)
        print(f'{a:04X}  {" ".join("%02X" % mem[a+i] for i in range(ins.size)):12} {z80dis.fmt(ins)}')
        a += ins.size
if __name__ == '__main__':
    dis(int(sys.argv[1], 16), int(sys.argv[2]) if len(sys.argv) > 2 else 30)
