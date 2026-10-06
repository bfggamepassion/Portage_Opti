"""Désassemblage de la cartouche par descente récursive + couverture du simulateur.

  python tools/disasm.py            -> re/<GAME>.lst (listing annoté)
Sortie aussi : re/code_map.bin (1 = octet de code, 2 = début d'instruction).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import z80dis  # noqa: E402
import port_config  # noqa: E402

ROM = open(os.path.join(ROOT, 're', port_config.GAME + '.col'), 'rb').read()
MEM = bytearray(65536)
MEM[0x8000:0xC000] = ROM

# Routines appelées suivies d'une table de mots en ligne (call X / dw ...).
INLINE_JUMP_TABLES = port_config.INLINE_JUMP_TABLES
# Routines appelées suivies de N octets de données en ligne (call X / db ...).
INLINE_DATA = port_config.INLINE_DATA
# Entrées connues
ENTRIES = port_config.DISASM_ENTRIES


def in_rom(a):
    return 0x8000 <= a < 0xC000


def analyse(extra_entries=()):
    kind = bytearray(65536)          # 0 inconnu, 1 code, 2 début d'instruction, 3 donnée table
    ins_at = {}
    labels = {}
    xref = {}
    todo = list(ENTRIES) + list(extra_entries)
    cov_path = os.path.join(ROOT, 're', 'coverage.bin')
    if os.path.exists(cov_path):
        cov = open(cov_path, 'rb').read()
        todo += [a for a in range(0x8000, 0xC000) if cov[a]]
    for a in ENTRIES:
        labels[a] = 'L%04X' % a
    tables = {}
    while todo:
        a = todo.pop()
        while in_rom(a) and kind[a] != 2:
            if kind[a] == 1:
                print('chevauchement %04X' % a)
                break
            ins = z80dis.decode(MEM, a)
            ins_at[a] = ins
            kind[a] = 2
            for i in range(1, ins.size):
                kind[a + i] = 1
            for t in ins.targets:
                if in_rom(t) or ins.flow == 'rst':
                    labels.setdefault(t, 'L%04X' % t)
                    xref.setdefault(t, []).append(a)
                    if in_rom(t):
                        todo.append(t)
            if ins.flow == 'call' and ins.targets[0] in INLINE_JUMP_TABLES:
                # table de mots en ligne : lue tant que ce sont des adresses de ROM
                p = a + 3
                n = 0
                while kind[p] == 0 and in_rom(MEM[p] | MEM[p + 1] << 8) and n < 64:
                    w = MEM[p] | MEM[p + 1] << 8
                    kind[p] = kind[p + 1] = 3
                    labels.setdefault(w, 'L%04X' % w)
                    todo.append(w)
                    tables.setdefault(a + 3, []).append(w)
                    p += 2
                    n += 1
                break
            if ins.flow == 'call' and ins.targets[0] in INLINE_DATA:
                n = INLINE_DATA[ins.targets[0]]
                for i in range(n):
                    kind[a + 3 + i] = 4
                todo.append(a + 3 + n)
                break
            if ins.flow in ('jp', 'ret', 'jpind', 'halt') or (ins.flow == 'rst' and False):
                break
            a += ins.size
    return kind, ins_at, labels, xref, tables


def main():
    kind, ins_at, labels, xref, tables = analyse()
    code = sum(1 for a in range(0x8000, 0xC000) if kind[a] in (1, 2))
    print(f'code : {code} octets, {len(ins_at)} instructions, tables en ligne : {len(tables)}')
    out = []
    a = 0x8000
    while a < 0xC000:
        if a in labels:
            refs = xref.get(a, [])
            out.append(f'{labels[a]}:' + (f'   ; <- {" ".join("%04X" % r for r in refs[:8])}' if refs else ''))
        if kind[a] == 2:
            ins = ins_at[a]
            hexb = ' '.join('%02X' % MEM[a + i] for i in range(ins.size))
            out.append(f'  {a:04X}  {hexb:12} {z80dis.fmt(ins, labels)}')
            a += ins.size
        elif kind[a] == 4:
            b = a
            while kind[b] == 4:
                b += 1
            out.append(f'  {a:04X}  db ' + ','.join('$%02X' % c for c in MEM[a:b]) + '   ; en ligne')
            a = b
        elif kind[a] == 3:
            w = MEM[a] | MEM[a + 1] << 8
            out.append(f'  {a:04X}  {MEM[a]:02X} {MEM[a+1]:02X}        dw {labels.get(w, "$%04X" % w)}')
            a += 2
        else:
            b = a
            while b < 0xC000 and (b == a or (kind[b] in (0, 1) and b not in labels)) and b - a < 16:
                b += 1
            data = MEM[a:b]
            txt = ''.join(chr(c) if 32 <= c < 127 else '.' for c in data)
            out.append(f'  {a:04X}  db ' + ','.join('$%02X' % c for c in data) + f'   ; {txt}')
            a = b
    open(os.path.join(ROOT, 're', port_config.GAME + '.lst'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    open(os.path.join(ROOT, 're', 'code_map.bin'), 'wb').write(bytes(kind))


if __name__ == '__main__':
    main()
