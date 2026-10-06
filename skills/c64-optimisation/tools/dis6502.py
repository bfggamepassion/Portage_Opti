"""6502/6510 disassembler with illegal opcodes, flow tracing and cross-reference search.

CLI:
  dis6502.py dump.ram dis  1000 1100          linear disassembly of a range
  dis6502.py dump.ram xref d011 d012 ...       every instruction whose operand is one of these addresses
  dis6502.py dump.ram xrange d000 d02e         same for an address range, grouped by address
  dis6502.py dump.ram trace 1000 [more...]     recursive-descent trace, prints the code map (ranges)
A .ram file made by vicemon (2-byte header) or a raw 64K image is accepted; -b ADDR loads a raw blob at ADDR.
"""
import sys

M = {}


def _d(s):
    for t in s.split():
        op, mn, mode = t.split(':')
        M[int(op, 16)] = (mn, mode)


_d("00:BRK:imp 01:ORA:izx 05:ORA:zp 06:ASL:zp 08:PHP:imp 09:ORA:imm 0A:ASL:acc 0D:ORA:abs 0E:ASL:abs "
   "10:BPL:rel 11:ORA:izy 15:ORA:zpx 16:ASL:zpx 18:CLC:imp 19:ORA:aby 1D:ORA:abx 1E:ASL:abx "
   "20:JSR:abs 21:AND:izx 24:BIT:zp 25:AND:zp 26:ROL:zp 28:PLP:imp 29:AND:imm 2A:ROL:acc 2C:BIT:abs 2D:AND:abs 2E:ROL:abs "
   "30:BMI:rel 31:AND:izy 35:AND:zpx 36:ROL:zpx 38:SEC:imp 39:AND:aby 3D:AND:abx 3E:ROL:abx "
   "40:RTI:imp 41:EOR:izx 45:EOR:zp 46:LSR:zp 48:PHA:imp 49:EOR:imm 4A:LSR:acc 4C:JMP:abs 4D:EOR:abs 4E:LSR:abs "
   "50:BVC:rel 51:EOR:izy 55:EOR:zpx 56:LSR:zpx 58:CLI:imp 59:EOR:aby 5D:EOR:abx 5E:LSR:abx "
   "60:RTS:imp 61:ADC:izx 65:ADC:zp 66:ROR:zp 68:PLA:imp 69:ADC:imm 6A:ROR:acc 6C:JMP:ind 6D:ADC:abs 6E:ROR:abs "
   "70:BVS:rel 71:ADC:izy 75:ADC:zpx 76:ROR:zpx 78:SEI:imp 79:ADC:aby 7D:ADC:abx 7E:ROR:abx "
   "81:STA:izx 84:STY:zp 85:STA:zp 86:STX:zp 88:DEY:imp 8A:TXA:imp 8C:STY:abs 8D:STA:abs 8E:STX:abs "
   "90:BCC:rel 91:STA:izy 94:STY:zpx 95:STA:zpx 96:STX:zpy 98:TYA:imp 99:STA:aby 9A:TXS:imp 9D:STA:abx "
   "A0:LDY:imm A1:LDA:izx A2:LDX:imm A4:LDY:zp A5:LDA:zp A6:LDX:zp A8:TAY:imp A9:LDA:imm AA:TAX:imp AC:LDY:abs AD:LDA:abs AE:LDX:abs "
   "B0:BCS:rel B1:LDA:izy B4:LDY:zpx B5:LDA:zpx B6:LDX:zpy B8:CLV:imp B9:LDA:aby BA:TSX:imp BC:LDY:abx BD:LDA:abx BE:LDX:aby "
   "C0:CPY:imm C1:CMP:izx C4:CPY:zp C5:CMP:zp C6:DEC:zp C8:INY:imp C9:CMP:imm CA:DEX:imp CC:CPY:abs CD:CMP:abs CE:DEC:abs "
   "D0:BNE:rel D1:CMP:izy D5:CMP:zpx D6:DEC:zpx D8:CLD:imp D9:CMP:aby DD:CMP:abx DE:DEC:abx "
   "E0:CPX:imm E1:SBC:izx E4:CPX:zp E5:SBC:zp E6:INC:zp E8:INX:imp E9:SBC:imm EA:NOP:imp EC:CPX:abs ED:SBC:abs EE:INC:abs "
   "F0:BEQ:rel F1:SBC:izy F5:SBC:zpx F6:INC:zpx F8:SED:imp F9:SBC:aby FD:SBC:abx FE:INC:abx")
# illegal opcodes (lower-case mnemonics so they stand out)
_d("03:slo:izx 07:slo:zp 0F:slo:abs 13:slo:izy 17:slo:zpx 1B:slo:aby 1F:slo:abx "
   "23:rla:izx 27:rla:zp 2F:rla:abs 33:rla:izy 37:rla:zpx 3B:rla:aby 3F:rla:abx "
   "43:sre:izx 47:sre:zp 4F:sre:abs 53:sre:izy 57:sre:zpx 5B:sre:aby 5F:sre:abx "
   "63:rra:izx 67:rra:zp 6F:rra:abs 73:rra:izy 77:rra:zpx 7B:rra:aby 7F:rra:abx "
   "83:sax:izx 87:sax:zp 8F:sax:abs 97:sax:zpy "
   "A3:lax:izx A7:lax:zp AF:lax:abs B3:lax:izy B7:lax:zpy BF:lax:aby "
   "C3:dcp:izx C7:dcp:zp CF:dcp:abs D3:dcp:izy D7:dcp:zpx DB:dcp:aby DF:dcp:abx "
   "E3:isc:izx E7:isc:zp EF:isc:abs F3:isc:izy F7:isc:zpx FB:isc:aby FF:isc:abx "
   "0B:anc:imm 2B:anc:imm 4B:alr:imm 6B:arr:imm 8B:ane:imm AB:lxa:imm CB:sbx:imm EB:sbc:imm "
   "93:sha:izy 9F:sha:aby 9C:shy:abx 9E:shx:aby 9B:tas:aby BB:las:aby "
   "1A:nop:imp 3A:nop:imp 5A:nop:imp 7A:nop:imp DA:nop:imp FA:nop:imp "
   "80:nop:imm 82:nop:imm 89:nop:imm C2:nop:imm E2:nop:imm "
   "04:nop:zp 44:nop:zp 64:nop:zp 14:nop:zpx 34:nop:zpx 54:nop:zpx 74:nop:zpx D4:nop:zpx F4:nop:zpx "
   "0C:nop:abs 1C:nop:abx 3C:nop:abx 5C:nop:abx 7C:nop:abx DC:nop:abx FC:nop:abx "
   "02:jam:imp 12:jam:imp 22:jam:imp 32:jam:imp 42:jam:imp 52:jam:imp 62:jam:imp 72:jam:imp 92:jam:imp B2:jam:imp D2:jam:imp F2:jam:imp")
LEN = dict(imp=1, acc=1, imm=2, zp=2, zpx=2, zpy=2, izx=2, izy=2, rel=2, abs=3, abx=3, aby=3, ind=3)
ILLEGAL = {op for op, (mn, _) in M.items() if mn.islower()}
FMT = {'imp': '', 'acc': ' A', 'imm': ' #$%02X', 'zp': ' $%02X', 'zpx': ' $%02X,X', 'zpy': ' $%02X,Y',
       'izx': ' ($%02X,X)', 'izy': ' ($%02X),Y', 'rel': ' $%04X', 'abs': ' $%04X', 'abx': ' $%04X,X',
       'aby': ' $%04X,Y', 'ind': ' ($%04X)'}


def decode(mem, pc):
    """-> (mnemonic, mode, length, operand address or value or None)"""
    op = mem[pc]
    mn, mode = M[op]
    n = LEN[mode]
    if n == 1:
        return mn, mode, 1, None
    if n == 2:
        v = mem[(pc + 1) & 0xffff]
        if mode == 'rel':
            v = (pc + 2 + (v - 256 if v > 127 else v)) & 0xffff
        return mn, mode, 2, v
    return mn, mode, 3, mem[(pc + 1) & 0xffff] | mem[(pc + 2) & 0xffff] << 8


def fmt(mn, mode, v):
    return mn + FMT[mode] % (() if v is None else (v,))


def line(mem, pc):
    mn, mode, n, v = decode(mem, pc)
    return n, "%04X  %-8s  %s" % (pc, ' '.join('%02X' % mem[(pc + i) & 0xffff] for i in range(n)), fmt(mn, mode, v))


def dis(mem, start, end):
    out = []
    pc = start
    while pc <= end:
        n, s = line(mem, pc)
        out.append(s)
        pc += n
    return '\n'.join(out)


def trace(mem, entries, lo=0, hi=0xffff):
    """Recursive descent. Returns (dict instruction start -> length, dict target -> set of callers)."""
    code = {}
    refs = {}
    todo = list(entries)
    while todo:
        pc = todo.pop()
        while lo <= pc <= hi and pc not in code:
            mn, mode, n, v = decode(mem, pc)
            code[pc] = n
            if mn == 'jam':
                break
            if mode == 'rel' or mn == 'JSR':
                refs.setdefault(v, set()).add(pc)
                todo.append(v)
            if mn == 'JMP':
                if mode == 'abs':
                    refs.setdefault(v, set()).add(pc)
                    todo.append(v)
                break
            if mn in ('RTS', 'RTI', 'BRK'):
                break
            pc += n
    return code, refs


def ranges(code):
    out = []
    s = e = None
    for a in sorted(code):
        if s is None:
            s, e = a, a + code[a]
        elif a <= e:
            e = max(e, a + code[a])
        else:
            out.append((s, e - 1))
            s, e = a, a + code[a]
    if s is not None:
        out.append((s, e - 1))
    return out


def xref(mem, targets, lo=0, hi=0xffff, modes=('abs', 'abx', 'aby', 'ind')):
    """Linear byte scan: any 3-byte instruction whose operand hits targets (false positives possible)."""
    targets = set(targets)
    out = []
    for pc in range(lo, hi - 1):
        mn, mode = M[mem[pc]]
        if mode in modes and (mem[pc + 1] | mem[pc + 2] << 8) in targets and mn != 'jam':
            out.append(pc)
    return out


def loadimg(path, base=None):
    d = open(path, 'rb').read()
    if base is not None:
        m = bytearray(65536)
        m[base:base + len(d)] = d[:65536 - base]
        return m
    if len(d) == 65538:
        d = d[2:]
    return bytearray(d.ljust(65536, b'\0'))


if __name__ == '__main__':
    a = sys.argv[1:]
    base = None
    if a[0] == '-b':
        base = int(a[1], 16)
        a = a[2:]
    mem = loadimg(a[0], base)
    cmd = a[1]
    h = [int(x, 16) for x in a[2:]]
    if cmd == 'dis':
        print(dis(mem, h[0], h[1]))
    elif cmd == 'xref':
        for pc in xref(mem, h):
            print(line(mem, pc)[1])
    elif cmd == 'xrange':
        by = {}
        for pc in xref(mem, range(h[0], h[1] + 1)):
            by.setdefault(decode(mem, pc)[3], []).append(pc)
        for t in sorted(by):
            print("$%04X:" % t)
            for pc in by[t]:
                print("   " + line(mem, pc)[1])
    elif cmd == 'trace':
        code, refs = trace(mem, h)
        for s, e in ranges(code):
            print("%04X-%04X" % (s, e))
