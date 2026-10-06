"""Traceur récursif de la ROM GB : sépare le code des données.

Suit le flot d'exécution depuis les vecteurs (CFG.TRACE_ENTRIES) en gérant
les conventions RST du jeu (tables de sauts, données en ligne).
Produit :
  - CFG.SYM_OUT : blocs .code/.data pour mgbdis ;
  - data_ranges.txt (à côté) : plages de données restantes ;
  - un rapport : tables de sauts, « jp hl » non résolus (à ajouter à la main
    dans TRACE_ENTRIES), routines qui commencent par « pop hl » (souvent des
    données placées après le CALL).

Usage : python tools/gb_trace.py [adresse_hex ...]   (entrées en plus)
Puis   : python tools/mgbdis/mgbdis.py re/game.gb --tiny --print-hex --overwrite

Limite : ROM de 32 Ko sans mapper (banque 0 seulement). Pour une ROM avec
MBC, il faut tracer banque par banque et suivre les changements de banque.
"""
import os
import sys

from gbrom import CFG, ROM, instructions, length, w, jr_target, inline_len, path, \
    RST_JUMPTABLE, RST_INLINE_DATA, TABLE_LEN, JUMPS16, JUMPS8, ENDS

SIZE = min(len(ROM), 0x8000)
ENTRIES = list(getattr(CFG, 'TRACE_ENTRIES', [0x0100, 0x0040, 0x0048, 0x0050, 0x0058, 0x0060]))
ENTRIES += [int(x, 16) for x in sys.argv[1:]]

code = bytearray(SIZE)       # 1 = octet d'instruction, 2 = données en ligne
starts = set()
jumptables = {}
jphl = []
callers_pop = set()
todo = list(ENTRIES)
branch_targets = set(todo)


def add(t):
    if t < SIZE and t not in starts:
        branch_targets.add(t)
        todo.append(t)


def trace(pc):
    while 0 <= pc < SIZE:
        if pc in starts:
            return
        if code[pc]:
            print(f'! chevauchement à {pc:04x}')
            return
        op = ROM[pc]
        if op not in instructions or instructions[op].startswith('ILLEGAL'):
            print(f'! opcode illégal {op:02x} à {pc:04x}')
            return
        n = length(op)
        starts.add(pc)
        for i in range(n):
            code[pc + i] = 1
        nxt = pc + n
        if op in RST_JUMPTABLE:                  # table de sauts après l'appel
            jumptables[nxt] = []
            return
        if op in RST_INLINE_DATA:                # données en ligne, puis reprise
            cnt = inline_len(pc)
            for i in range(cnt):
                code[nxt + i] = 2
            pc = nxt + cnt
            continue
        if op == 0xE9:                           # jp hl : cible inconnue
            jphl.append(pc)
            return
        if op in JUMPS16:
            t = w(pc + 1)
            add(t)
            if op == 0xCD and t < SIZE and ROM[t] == 0xE1:
                callers_pop.add(t)
        if op in JUMPS8:
            add(jr_target(pc))
        if op in ENDS or op in (0xC7, 0xFF):     # rst $00 / $38 : reset, piège
            return
        pc = nxt


def extend_tables():
    """Étend chaque table de sauts tant que les entrées sont plausibles."""
    changed = False
    for tb, targets in jumptables.items():
        a = tb + 2 * len(targets)
        while a + 1 < SIZE and len(targets) < TABLE_LEN.get(tb, 999):
            if a in starts or a in branch_targets or code[a] or code[a + 1]:
                break
            t = w(a)
            if not (0x0150 <= t < 0x8000):
                break
            code[a] = code[a + 1] = 2
            targets.append(t)
            add(t)
            changed = True
            a += 2
    return changed


def main():
    while True:
        while todo:
            trace(todo.pop())
        if not extend_tables():
            break
    ncode = sum(1 for b in code if b == 1)
    ninl = sum(1 for b in code if b == 2)
    print(f'code : {ncode} octets, données en ligne : {ninl}, reste : {SIZE - ncode - ninl}')
    print(f'tables de sauts : {len(jumptables)}')
    for tb, t in sorted(jumptables.items()):
        print(f'  {tb:04x}: ' + ' '.join(f'{x:04x}' for x in t))
    print('jp hl non résolus : ' + ' '.join(f'{x:04x}' for x in sorted(set(jphl))))
    print('routines appelées commençant par pop hl : ' + ' '.join(f'{x:04x}' for x in sorted(callers_pop)))

    sym = path(getattr(CFG, 'SYM_OUT', 're/game.sym'))
    os.makedirs(os.path.dirname(sym), exist_ok=True)
    with open(sym, 'w') as f:
        a = 0x0150
        while a < SIZE:
            kind = 'code' if code[a] == 1 else 'data'
            b = a
            while b < SIZE and b != 0x4000 and ('code' if code[b] == 1 else 'data') == kind:
                b += 1
            if b == a:
                b += 1
            f.write(f'00:{a:04x} .{kind}:{b - a:x}\n')
            a = b
    with open(os.path.join(os.path.dirname(sym), 'data_ranges.txt'), 'w') as f:
        a = 0x0150
        while a < SIZE:
            if code[a] == 0:
                b = a
                while b < SIZE and code[b] == 0:
                    b += 1
                f.write(f'{a:04x}-{b - 1:04x} ({b - a} octets)\n')
                a = b
            else:
                a += 1
    print(f'-> {sym}')


if __name__ == '__main__':
    main()
