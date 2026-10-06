"""Summarise a dump made by vicemon: vectors, VIC-II / CIA state, memory map guess.

  state.py dumps/gal_2
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vicemon import load


def summary(prefix):
    ram, io = load(prefix)
    v = io[0:0x40]
    print(open(prefix + '.reg').read())
    print("vectors in RAM  NMI/RES/IRQ: %04X %04X %04X   $0314 IRQ %04X  $0318 NMI %04X   (CPU port: see p0/p1 above)" % (
        ram[0xfffa] | ram[0xfffb] << 8, ram[0xfffc] | ram[0xfffd] << 8,
        ram[0xfffe] | ram[0xffff] << 8, ram[0x314] | ram[0x315] << 8, ram[0x318] | ram[0x319] << 8))
    d011, d016, d018 = v[0x11], v[0x16], v[0x18]
    bank = (3 - (io[0xd00] & 3)) * 0x4000
    mode = ('ECM ' if d011 & 0x40 else '') + ('BMM ' if d011 & 0x20 else '') + ('MCM' if d016 & 0x10 else 'hires')
    print("D011=%02X (yscroll %d, %d rows, %s)  D016=%02X (xscroll %d, %d cols)  mode: %s" % (
        d011, d011 & 7, 25 if d011 & 8 else 24, 'on' if d011 & 0x10 else 'BLANK', d016, d016 & 7,
        40 if d016 & 8 else 38, mode))
    print("D018=%02X  DD00=%02X -> VIC bank $%04X, screen $%04X, charset/bitmap $%04X" % (
        d018, io[0xd00], bank, bank + (d018 >> 4) * 0x400, bank + ((d018 >> 1) & 7) * 0x800))
    print("D012 raster cmp=%d  D01A irq mask=%02X  D019=%02X" % (v[0x12] | (d011 & 0x80) << 1, v[0x1a], v[0x19]))
    print("sprites: enable=%02X msb=%02X mc=%02X xexp=%02X yexp=%02X prio=%02X  mc0/1=%X/%X" % (
        v[0x15], v[0x10], v[0x1c], v[0x1d], v[0x17], v[0x1b], v[0x25] & 15, v[0x26] & 15))
    scr = bank + (d018 >> 4) * 0x400
    for i in range(8):
        print("   spr%d x=%3d y=%3d col=%X ptr=%02X (data $%04X)" % (
            i, v[i * 2] | ((v[0x10] >> i) & 1) << 8, v[i * 2 + 1], v[0x27 + i] & 15, ram[scr + 0x3f8 + i],
            bank + ram[scr + 0x3f8 + i] * 64))
    print("colours: border %X bg %X %X %X %X" % tuple(x & 15 for x in (v[0x20], v[0x21], v[0x22], v[0x23], v[0x24])))
    print("CIA1 timers A=%04X B=%04X cra=%02X crb=%02X icr=%02X | CIA2 A=%04X B=%04X cra=%02X crb=%02X" % (
        io[0xc04] | io[0xc05] << 8, io[0xc06] | io[0xc07] << 8, io[0xc0e], io[0xc0f], io[0xc0d],
        io[0xd04] | io[0xd05] << 8, io[0xd06] | io[0xd07] << 8, io[0xd0e], io[0xd0f]))
    # crude memory map: 256-byte pages, '.'=all equal, else entropy class
    import math
    row = ''
    for p in range(256):
        b = ram[p * 256:(p + 1) * 256]
        if len(set(b)) <= 2:
            row += '.'
        else:
            h = -sum(c / 256 * math.log2(c / 256) for c in (b.count(x) for x in set(b)))
            row += 'abcdefgh'[min(7, int(h))]
        if p % 64 == 63:
            print("  $%04X %s" % ((p - 63) * 256, row))
            row = ''


if __name__ == '__main__':
    summary(sys.argv[1])
