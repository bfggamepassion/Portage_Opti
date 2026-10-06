"""Désassembleur Z80 compact (syntaxe sjasmplus).

decode(mem, addr) -> Ins(addr, size, text, targets, flow, ref)
  text    : mnémonique, les adresses 16 bits notées {W:xxxx} (remplacées par
            une étiquette si on veut), les ports notés tels quels ;
  targets : destinations de saut/appel ;
  flow    : 'jp' (saut inconditionnel), 'ret', 'call', 'cond', 'rst', 'halt', None
  ref     : adresse 16 bits utilisée comme donnée (ld hl,nn / ld a,(nn) ...)
"""
from collections import namedtuple

Ins = namedtuple('Ins', 'addr size text targets flow ref imm16')

R8 = ['b', 'c', 'd', 'e', 'h', 'l', '(hl)', 'a']
RP = ['bc', 'de', 'hl', 'sp']
RP2 = ['bc', 'de', 'hl', 'af']
CC = ['nz', 'z', 'nc', 'c', 'po', 'pe', 'p', 'm']
ALU = ['add a,', 'adc a,', 'sub ', 'sbc a,', 'and ', 'xor ', 'or ', 'cp ']
ROT = ['rlc', 'rrc', 'rl', 'rr', 'sla', 'sra', 'sll', 'srl']


def W(v):
    return '{W:%04X}' % v


def B(v):
    return '$%02X' % v


def decode(mem, a):
    def rb(o):
        return mem[(a + o) & 0xFFFF]

    def rw(o):
        return rb(o) | (rb(o + 1) << 8)

    op = rb(0)
    if op in (0xDD, 0xFD):
        return decode_index(mem, a, 'ix' if op == 0xDD else 'iy')
    if op == 0xCB:
        o2 = rb(1)
        x, y, z = o2 >> 6, (o2 >> 3) & 7, o2 & 7
        if x == 0:
            t = f'{ROT[y]} {R8[z]}'
        else:
            t = f'{["", "bit", "res", "set"][x]} {y},{R8[z]}'
        return Ins(a, 2, t, (), None, None, None)
    if op == 0xED:
        return decode_ed(mem, a)
    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    p, q = y >> 1, y & 1
    if x == 0:
        if z == 0:
            if y == 0:
                return Ins(a, 1, 'nop', (), None, None, None)
            if y == 1:
                return Ins(a, 1, "ex af,af'", (), None, None, None)
            d = rb(1)
            tgt = (a + 2 + (d if d < 128 else d - 256)) & 0xFFFF
            if y == 2:
                return Ins(a, 2, 'djnz ' + W(tgt), (tgt,), 'cond', None, None)
            if y == 3:
                return Ins(a, 2, 'jr ' + W(tgt), (tgt,), 'jp', None, None)
            return Ins(a, 2, f'jr {CC[y - 4]},' + W(tgt), (tgt,), 'cond', None, None)
        if z == 1:
            if q == 0:
                v = rw(1)
                return Ins(a, 3, f'ld {RP[p]},' + W(v), (), None, None, v)
            return Ins(a, 1, f'add hl,{RP[p]}', (), None, None, None)
        if z == 2:
            if p < 2:
                r = RP[p]
                return Ins(a, 1, f'ld ({r}),a' if q == 0 else f'ld a,({r})', (), None, None, None)
            v = rw(1)
            if p == 2:
                t = f'ld ({W(v)}),hl' if q == 0 else f'ld hl,({W(v)})'
            else:
                t = f'ld ({W(v)}),a' if q == 0 else f'ld a,({W(v)})'
            return Ins(a, 3, t, (), None, v, None)
        if z == 3:
            return Ins(a, 1, ('inc ' if q == 0 else 'dec ') + RP[p], (), None, None, None)
        if z == 4:
            return Ins(a, 1, 'inc ' + R8[y], (), None, None, None)
        if z == 5:
            return Ins(a, 1, 'dec ' + R8[y], (), None, None, None)
        if z == 6:
            return Ins(a, 2, f'ld {R8[y]},{B(rb(1))}', (), None, None, None)
        return Ins(a, 1, ['rlca', 'rrca', 'rla', 'rra', 'daa', 'cpl', 'scf', 'ccf'][y], (), None, None, None)
    if x == 1:
        if op == 0x76:
            return Ins(a, 1, 'halt', (), 'halt', None, None)
        return Ins(a, 1, f'ld {R8[y]},{R8[z]}', (), None, None, None)
    if x == 2:
        return Ins(a, 1, ALU[y] + R8[z], (), None, None, None)
    # x == 3
    if z == 0:
        return Ins(a, 1, 'ret ' + CC[y], (), 'condret', None, None)
    if z == 1:
        if q == 0:
            return Ins(a, 1, 'pop ' + RP2[p], (), None, None, None)
        t = ['ret', 'exx', 'jp (hl)', 'ld sp,hl'][p]
        fl = {0: 'ret', 2: 'jpind'}.get(p)
        return Ins(a, 1, t, (), fl, None, None)
    if z == 2:
        v = rw(1)
        return Ins(a, 3, f'jp {CC[y]},' + W(v), (v,), 'cond', None, None)
    if z == 3:
        if y == 0:
            v = rw(1)
            return Ins(a, 3, 'jp ' + W(v), (v,), 'jp', None, None)
        if y == 2:
            return Ins(a, 2, f'out ({B(rb(1))}),a', (), 'out', None, None)
        if y == 3:
            return Ins(a, 2, f'in a,({B(rb(1))})', (), 'in', None, None)
        return Ins(a, 1, ['', '', '', '', 'ex (sp),hl', 'ex de,hl', 'di', 'ei'][y], (), None, None, None)
    if z == 4:
        v = rw(1)
        return Ins(a, 3, f'call {CC[y]},' + W(v), (v,), 'ccall', None, None)
    if z == 5:
        if q == 0:
            return Ins(a, 1, 'push ' + RP2[p], (), None, None, None)
        if p == 0:
            v = rw(1)
            return Ins(a, 3, 'call ' + W(v), (v,), 'call', None, None)
    if z == 6:
        return Ins(a, 2, ALU[y] + B(rb(1)), (), None, None, None)
    if z == 7:
        return Ins(a, 1, 'rst $%02X' % (y * 8), (y * 8,), 'rst', None, None)
    raise ValueError('%04X' % a)


def decode_ed(mem, a):
    o2 = mem[(a + 1) & 0xFFFF]
    x, y, z = o2 >> 6, (o2 >> 3) & 7, o2 & 7
    p, q = y >> 1, y & 1

    def rw(o):
        return mem[(a + o) & 0xFFFF] | (mem[(a + o + 1) & 0xFFFF] << 8)
    if x == 1:
        if z == 0:
            return Ins(a, 2, 'in ' + ('f' if y == 6 else R8[y]) + ',(c)', (), 'in', None, None)
        if z == 1:
            return Ins(a, 2, 'out (c),' + ('0' if y == 6 else R8[y]), (), 'out', None, None)
        if z == 2:
            return Ins(a, 2, ('sbc' if q == 0 else 'adc') + f' hl,{RP[p]}', (), None, None, None)
        if z == 3:
            v = rw(2)
            t = f'ld ({W(v)}),{RP[p]}' if q == 0 else f'ld {RP[p]},({W(v)})'
            return Ins(a, 4, t, (), None, v, None)
        if z == 4:
            return Ins(a, 2, 'neg', (), None, None, None)
        if z == 5:
            return Ins(a, 2, 'retn' if y != 1 else 'reti', (), 'ret', None, None)
        if z == 6:
            return Ins(a, 2, 'im ' + ['0', '0', '1', '2', '0', '0', '1', '2'][y], (), None, None, None)
        return Ins(a, 2, ['ld i,a', 'ld r,a', 'ld a,i', 'ld a,r', 'rrd', 'rld', 'nop', 'nop'][y], (), None, None, None)
    if x == 2 and z <= 3 and y >= 4:
        t = [['ldi', 'cpi', 'ini', 'outi'], ['ldd', 'cpd', 'ind', 'outd'],
             ['ldir', 'cpir', 'inir', 'otir'], ['lddr', 'cpdr', 'indr', 'otdr']][y - 4][z]
        fl = 'in' if z == 2 else 'out' if z == 3 else None
        return Ins(a, 2, t, (), fl, None, None)
    return Ins(a, 2, 'db $ED,$%02X' % o2, (), None, None, None)


def decode_index(mem, a, ix):
    def rb(o):
        return mem[(a + o) & 0xFFFF]
    op = rb(1)

    def disp(d):
        return f'({ix}+{d})' if d < 128 else f'({ix}-{256 - d})'
    if op == 0xCB:
        d, o3 = rb(2), rb(3)
        x, y, z = o3 >> 6, (o3 >> 3) & 7, o3 & 7
        if x == 0:
            t = f'{ROT[y]} {disp(d)}'
        else:
            t = f'{["", "bit", "res", "set"][x]} {y},{disp(d)}'
        if z != 6 and x != 1:
            return Ins(a, 4, f'db ${mem[a]:02X},$CB,${d:02X},${o3:02X}', (), None, None, None)
        return Ins(a, 4, t, (), None, None, None)
    h, l = ix + 'h', ix + 'l'
    if op == 0x21:
        v = rb(2) | (rb(3) << 8)
        return Ins(a, 4, f'ld {ix},' + W(v), (), None, None, v)
    if op == 0x22:
        v = rb(2) | (rb(3) << 8)
        return Ins(a, 4, f'ld ({W(v)}),{ix}', (), None, v, None)
    if op == 0x2A:
        v = rb(2) | (rb(3) << 8)
        return Ins(a, 4, f'ld {ix},({W(v)})', (), None, v, None)
    if op == 0x36:
        return Ins(a, 4, f'ld {disp(rb(2))},{B(rb(3))}', (), None, None, None)
    if op == 0xE9:
        return Ins(a, 2, f'jp ({ix})', (), 'jpind', None, None)
    if op in (0x09, 0x19, 0x29, 0x39):
        return Ins(a, 2, f'add {ix},' + ['bc', 'de', ix, 'sp'][op >> 4], (), None, None, None)
    if op == 0x23:
        return Ins(a, 2, f'inc {ix}', (), None, None, None)
    if op == 0x2B:
        return Ins(a, 2, f'dec {ix}', (), None, None, None)
    if op == 0xE1:
        return Ins(a, 2, f'pop {ix}', (), None, None, None)
    if op == 0xE5:
        return Ins(a, 2, f'push {ix}', (), None, None, None)
    if op == 0xE3:
        return Ins(a, 2, f'ex (sp),{ix}', (), None, None, None)
    if op == 0xF9:
        return Ins(a, 2, f'ld sp,{ix}', (), None, None, None)
    if op in (0x34, 0x35):
        return Ins(a, 3, ('inc ' if op == 0x34 else 'dec ') + disp(rb(2)), (), None, None, None)
    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    if x == 1 and op != 0x76:
        if z == 6:
            return Ins(a, 3, f'ld {R8[y]},{disp(rb(2))}', (), None, None, None)
        if y == 6:
            return Ins(a, 3, f'ld {disp(rb(2))},{R8[z]}', (), None, None, None)
        m = {4: h, 5: l}
        if y in m or z in m:
            return Ins(a, 2, f'ld {m.get(y, R8[y])},{m.get(z, R8[z])}', (), None, None, None)
    if x == 2:
        if z == 6:
            return Ins(a, 3, ALU[y] + disp(rb(2)), (), None, None, None)
        if z in (4, 5):
            return Ins(a, 2, ALU[y] + (h if z == 4 else l), (), None, None, None)
    if x == 0 and z == 6 and y in (4, 5):
        return Ins(a, 3, f'ld {h if y == 4 else l},{B(rb(2))}', (), None, None, None)
    if x == 0 and z in (4, 5) and y in (4, 5):
        return Ins(a, 2, ('inc ' if z == 4 else 'dec ') + (h if y == 4 else l), (), None, None, None)
    # préfixe sans effet : un seul octet
    return Ins(a, 1, f'db ${mem[a]:02X}', (), None, None, None)


def fmt(ins, labels=None):
    import re

    def rep(m):
        v = int(m.group(1), 16)
        if labels and v in labels:
            return labels[v]
        return '$%04X' % v
    return re.sub(r'\{W:([0-9A-F]{4})\}', rep, ins.text)
