"""Traduction statique de la logique d'un jeu Game Boy (SM83) en 6502 (64tass).

Lit la ROM, suit le code atteint depuis CFG.ROOTS (gb_closure) et écrit
CFG.LOGIC_OUT (gb/gb_logic.asm).

Modèle d'exécution :
- les registres GB sont en page zéro : zA, zB, zC, zD, zE, zH, zL, rangés
  par paires (zC/zB, zE/zD, zL/zH : octet bas puis haut) pour servir de
  pointeurs : [hl] devient (zL),y ;
- Y vaut toujours 0 dans le code traduit (et doit valoir 0 au retour de
  toute routine écrite à la main) ; A et X du 6502 sont des brouillons ;
- indicateurs : seuls Z et C servent (pas de DAA dans la logique).
  zZ = dernier résultat (Z du GB <=> zZ = 0), zCY = retenue du GB en bit 0.
  Ils ne sont écrits que par les instructions GB qui les modifient, donc les
  LD entre un test et un saut ne les perdent pas (contrairement aux
  indicateurs du 6502, que LDA modifie) ;
- la retenue des soustractions est inversée sur 6502 (C = pas d'emprunt) :
  on la remet dans le sens GB avec INC zCY (inverse le bit 0) ;
- la pile GB est la pile du 6502 : CALL -> JSR, RET -> RTS, PUSH/POP -> PHA/PLA.
  JSR empile l'adresse de retour - 1 : les adresses de code empilées par la
  ROM (CODE_PTRS, adresses de retour) sont donc traduites en « étiquette - 1 »,
  et les routines RST (écrites à la main) ajoutent 1 à l'adresse dépilée ;
- la RAM GB garde ses adresses ($C000-$DFFF, $FF80-$FFCB) : sur C64, la
  logique tourne avec toute la RAM visible ($01 = $34).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gb_closure as gc  # noqa: E402
from gbrom import CFG, ROM, instructions, cb_instructions, length, w, path, inline_len, \
    RST_JUMPTABLE, RST_INLINE_DATA  # noqa: E402

OUT = path(CFG.LOGIC_OUT)
STUB_LABEL = {a: l for a, l in CFG.STUBS.items() if l}
PATCHES = dict(getattr(CFG, 'PATCHES', {}))
CODE_PTRS = set(getattr(CFG, 'CODE_PTRS', []))
DATA_PTRS = set(getattr(CFG, 'DATA_PTRS', []))
DATA_BLOCKS = list(getattr(CFG, 'DATA_BLOCKS', []))
DATA_LABELS = set(getattr(CFG, 'DATA_LABELS', []))

REG = {'a': 'zA', 'b': 'zB', 'c': 'zC', 'd': 'zD', 'e': 'zE', 'h': 'zH', 'l': 'zL'}
PAIR = {'bc': ('zC', 'zB'), 'de': ('zE', 'zD'), 'hl': ('zL', 'zH')}
IND = {'[hl]': '(zL),y', '[bc]': '(zC),y', '[de]': '(zE),y'}

_n = 0


def skip():
    global _n
    _n += 1
    return f'_s{_n}'


def lab(a):
    return f'G_{a:04X}'


def operand(x, d8):
    """Opérande 6502 d'une source GB (registre, [rr] ou d8)."""
    if x in REG:
        return REG[x]
    if x in IND:
        return IND[x]
    if x == 'd8':
        return f'#${d8:02X}'
    raise ValueError(x)


def cond_false(cond, target):
    """Saut vers target si la condition GB est FAUSSE."""
    if cond == 'z':
        return ['lda zZ', f'bne {target}']
    if cond == 'nz':
        return ['lda zZ', f'beq {target}']
    if cond == 'c':
        return ['lda zCY', 'lsr a', f'bcc {target}']
    if cond == 'nc':
        return ['lda zCY', 'lsr a', f'bcs {target}']
    raise ValueError(cond)


def conditional(cond, action):
    sk = skip()
    return cond_false(cond, sk) + [action, f'{sk}']


ALU = {
    'add': lambda s: ['clc', 'lda zA', f'adc {s}', 'sta zA', 'sta zZ', 'rol zCY'],
    'adc': lambda s: ['lda zCY', 'lsr a', 'lda zA', f'adc {s}', 'sta zA', 'sta zZ', 'rol zCY'],
    'sub': lambda s: ['sec', 'lda zA', f'sbc {s}', 'sta zA', 'sta zZ', 'rol zCY', 'inc zCY'],
    'sbc': lambda s: ['lda zCY', 'eor #1', 'lsr a', 'lda zA', f'sbc {s}', 'sta zA', 'sta zZ',
                      'rol zCY', 'inc zCY'],
    'cp': lambda s: ['sec', 'lda zA', f'sbc {s}', 'sta zZ', 'rol zCY', 'inc zCY'],
    'and': lambda s: ['lda zA', f'and {s}', 'sta zA', 'sta zZ', 'sty zCY'],
    'or': lambda s: ['lda zA', f'ora {s}', 'sta zA', 'sta zZ', 'sty zCY'],
    'xor': lambda s: ['lda zA', f'eor {s}', 'sta zA', 'sta zZ', 'sty zCY'],
}


def rot(kind, s, z_result=True):
    """Rotations et décalages sur la source s (registre ou (zL),y)."""
    zf = ['sta zZ'] if z_result else []
    tail = ['lda #1', 'sta zZ'] if not z_result else []
    if kind == 'rlc':
        body = ['lda ' + s, 'cmp #$80', 'rol a', 'sta ' + s] + zf + ['rol zCY']
    elif kind == 'rrc':
        sk = skip()
        body = ['lda ' + s, 'lsr a', f'bcc {sk}', 'ora #$80', sk, 'sta ' + s] + zf + ['rol zCY']
    elif kind == 'rl':
        body = ['lda zCY', 'lsr a', 'lda ' + s, 'rol a', 'sta ' + s] + zf + ['rol zCY']
    elif kind == 'rr':
        body = ['lda zCY', 'lsr a', 'lda ' + s, 'ror a', 'sta ' + s] + zf + ['rol zCY']
    elif kind == 'sla':
        body = ['lda ' + s, 'asl a', 'sta ' + s] + zf + ['rol zCY']
    elif kind == 'sra':
        body = ['lda ' + s, 'cmp #$80', 'ror a', 'sta ' + s] + zf + ['rol zCY']
    elif kind == 'srl':
        body = ['lda ' + s, 'lsr a', 'sta ' + s] + zf + ['rol zCY']
    elif kind == 'swap':
        body = ['lda ' + s, 'asl a', 'adc #$80', 'rol a', 'asl a', 'adc #$80', 'rol a',
                'sta ' + s, 'sta zZ', 'sty zCY']
    else:
        raise ValueError(kind)
    return body + tail


def translate_cb(cbm):
    op, args = cbm.split(None, 1)
    if op in ('bit', 'set', 'res'):
        n, r = args.split(',')
        s = operand(r, 0)
        m = 1 << int(n)
        if op == 'bit':
            return ['lda ' + s, f'and #${m:02X}', 'sta zZ']
        if op == 'set':
            return ['lda ' + s, f'ora #${m:02X}', 'sta ' + s]
        return ['lda ' + s, f'and #${0xFF ^ m:02X}', 'sta ' + s]
    return rot(op, operand(args, 0))


def translate_op(pc, op, m, d8, d16, nxt, tables, warnings, target16):
    """Renvoie (lignes 6502, le code continue-t-il après ?)."""
    if op == 0xCB:
        return translate_cb(cb_instructions[ROM[pc + 1]]), True
    parts = m.split(None, 1)
    name = parts[0]
    args = parts[1] if len(parts) > 1 else ''
    if name == 'nop':
        return [], True
    if name in ('di', 'ei'):
        warnings.append(f'{pc:04x} {name} ignoré')
        return [], True
    if name in ALU:
        s = args.split(',')[-1] if name in ('add', 'adc', 'sbc') and args.startswith('a,') else args
        if name == 'add' and args.startswith('hl,'):
            lo, hi = PAIR[args[3:]]
            return ['clc', 'lda zL', f'adc {lo}', 'sta zL', 'lda zH', f'adc {hi}', 'sta zH',
                    'rol zCY'], True
        return ALU[name](operand(s, d8)), True
    if name in ('inc', 'dec'):
        if args in PAIR:
            lo, hi = PAIR[args]
            sk = skip()
            if name == 'inc':
                return [f'inc {lo}', f'bne {sk}', f'inc {hi}', sk], True
            return [f'lda {lo}', f'bne {sk}', f'dec {hi}', sk, f'dec {lo}'], True
        if args in REG:
            r = REG[args]
            return [f'{name} {r}', f'lda {r}', 'sta zZ'], True
        s = IND[args]
        if name == 'inc':
            return ['lda ' + s, 'clc', 'adc #1', 'sta ' + s, 'sta zZ'], True
        return ['lda ' + s, 'sec', 'sbc #1', 'sta ' + s, 'sta zZ'], True
    if name in ('rlca', 'rrca', 'rla', 'rra'):
        return rot({'rlca': 'rlc', 'rrca': 'rrc', 'rla': 'rl', 'rra': 'rr'}[name], 'zA',
                   z_result=False), True
    if name == 'cpl':
        return ['lda zA', 'eor #$FF', 'sta zA'], True
    if name == 'scf':
        return ['lda #1', 'sta zCY'], True
    if name == 'ccf':
        return ['inc zCY'], True
    if name == 'push':
        if args == 'af':
            return ['lda zA', 'pha', 'jsr G_GETF', 'pha'], True
        lo, hi = PAIR[args]
        return [f'lda {hi}', 'pha', f'lda {lo}', 'pha'], True
    if name == 'pop':
        if args == 'af':
            return ['pla', 'jsr G_SETF', 'pla', 'sta zA'], True
        lo, hi = PAIR[args]
        return ['pla', f'sta {lo}', 'pla', f'sta {hi}'], True
    if name == 'ldh':
        if args == '[a8],a':
            return ['lda zA', f'sta ${0xFF00 + d8:04X}'], True
        return [f'lda ${0xFF00 + d8:04X}', 'sta zA'], True
    if name == 'ld':
        dst, src = args.split(',')
        if dst in PAIR and src == 'd16':
            lo, hi = PAIR[dst]
            if d16 in CODE_PTRS:
                v = f'({lab(d16)}-1)'            # adresse de retour (convention JSR)
            elif d16 in DATA_PTRS:
                v = f'D_{d16:04X}'
            else:
                v = f'${d16:04X}'
            return [f'lda #<{v}', f'sta {lo}', f'lda #>{v}', f'sta {hi}'], True
        if dst in ('[hl+]', '[hl-]') or src in ('[hl+]', '[hl-]'):
            if dst.startswith('[hl'):
                body = ['lda zA', 'sta (zL),y']
            else:
                body = ['lda (zL),y', 'sta zA']
            sk = skip()
            if '+' in args:
                return body + ['inc zL', f'bne {sk}', 'inc zH', sk], True
            return body + ['lda zL', f'bne {sk}', 'dec zH', sk, 'dec zL'], True
        if dst == '[a16]':
            if d16 < 0x8000:
                warnings.append(f'{pc:04x} écriture ROM {d16:04x}')
            return ['lda zA', f'sta ${d16:04X}'], True
        if src == '[a16]':
            if d16 < 0x8000:
                warnings.append(f'{pc:04x} lecture ROM {d16:04x}')
            return [f'lda ${d16:04X}', 'sta zA'], True
        s = operand(src, d8)
        d = REG.get(dst) or IND[dst]
        return [f'lda {s}', f'sta {d}'], True
    if name in ('jp', 'jr', 'call'):
        if 'pc+r8' in args:
            r = d8 - 256 if d8 > 127 else d8
            t = lab(nxt + r)
        else:
            t = target16(d16)
        cond = args.split(',')[0] if ',' in args else ''
        ins = f'jsr {t}' if name == 'call' else f'jmp {t}'
        if cond:
            return conditional(cond, ins), True
        return [ins], name == 'call'
    if name in ('ret', 'reti'):
        if args:
            return conditional(args, 'rts'), True
        return ['rts'], False
    warnings.append(f'{pc:04x} {m} : non traduit')
    return [f'.error "non traduit : {m} en ${pc:04X}"'], True


# --- Durée de vie des indicateurs ---------------------------------------------
# Une instruction GB qui écrit Z ou C n'a pas besoin de les sauvegarder (zZ,
# zCY) si aucune suite possible ne les lit avant de les réécrire. Analyse
# arrière classique sur le graphe du code GB, prudente : au RET, les deux
# indicateurs sont supposés lus (l'appelant peut les tester).
FZ, FC = 1, 2
ALL = FZ | FC
# Routines écrites à la main (CFG.STUBS) : (indicateurs écrits, lus), avec
# FZ = 1, FC = 2. Inconnue : rien d'écrit, tout lu (prudent).
STUB_FLAGS = dict(getattr(CFG, 'STUB_FLAGS', {}))
COND = {'z': FZ, 'nz': FZ, 'c': FC, 'nc': FC}
# Indicateurs écrits par chaque routine RST (nom Z80/6502 -> FZ | FC)
RST_DEFS = dict(getattr(CFG, 'RST_FLAG_DEFS', {}))


def flag_effect(pc, tables):
    """-> (lus, écrits, successeurs, appel) ; appel = cible d'un CALL (ou None).
    Successeur 'RET' : sortie de routine (tout est vivant), 'END' : rien."""
    op = ROM[pc]
    m = instructions[op]
    nxt = pc + length(op)
    if pc in PATCHES:
        return ALL, 0, ['RET'], None
    if op in RST_JUMPTABLE:
        return 0, RST_DEFS.get(RST_JUMPTABLE[op], 0), tables[nxt], None
    if op in RST_INLINE_DATA:
        return 0, RST_DEFS.get(RST_INLINE_DATA[op], 0), [nxt + inline_len(pc)], None
    if op == 0xCB:
        name = cb_instructions[ROM[pc + 1]].split()[0]
        if name == 'bit':
            return 0, FZ, [nxt], None
        if name in ('set', 'res'):
            return 0, 0, [nxt], None
        return (FC if name in ('rl', 'rr') else 0), ALL, [nxt], None
    parts = m.split(None, 1)
    name, args = parts[0], (parts[1] if len(parts) > 1 else '')
    if name in ('add', 'adc', 'sub', 'sbc', 'and', 'or', 'xor', 'cp'):
        if args.startswith('hl,'):
            return 0, FC, [nxt], None
        return (FC if name in ('adc', 'sbc') else 0), ALL, [nxt], None
    if name in ('inc', 'dec'):
        return 0, (0 if args in PAIR else FZ), [nxt], None
    if name in ('rlca', 'rrca'):
        return 0, ALL, [nxt], None
    if name in ('rla', 'rra'):
        return FC, ALL, [nxt], None
    if name == 'scf':
        return 0, FC, [nxt], None
    if name == 'ccf':
        return FC, FC, [nxt], None
    if name == 'push' and args == 'af':
        return ALL, 0, [nxt], None
    if name == 'pop' and args == 'af':
        return 0, ALL, [nxt], None
    cond = args.split(',')[0] if ',' in args else ''
    use = COND.get(cond, 0)
    if name in ('ret', 'reti'):
        return ALL, 0, (['RET', nxt] if args else ['RET']), None
    if name in ('jp', 'jr', 'call'):
        if 'pc+r8' in args:
            r = ROM[pc + 1]
            t = nxt + (r - 256 if r > 127 else r)
        else:
            t = w(pc + 1)
        if name == 'call':
            return use, 0, [nxt], t
        tgt = STUB_LABEL.get(t, t) if t in STUB_LABEL else t
        if isinstance(tgt, str):
            tgt = 'END' if tgt == 'S_SCREEN' else 'RET'
        return use, 0, ([nxt, tgt] if cond else [tgt]), None
    if name == 'jp' and args == 'hl':
        return ALL, 0, ['RET'], None
    return 0, 0, [nxt], None


def flag_liveness(starts, tables):
    """-> {pc: indicateurs vivants après l'instruction}"""
    eff = {pc: flag_effect(pc, tables) for pc in starts}
    live_in = {pc: 0 for pc in starts}

    def lin(t):
        if t == 'RET':
            return ALL
        if t == 'END':
            return 0
        return live_in.get(t, ALL)

    def out_of(pc):
        use, defs, succ, call = eff[pc]
        o = 0
        for t in succ:
            o |= lin(t)
        return o

    changed = True
    while changed:
        changed = False
        for pc in sorted(starts, reverse=True):
            use, defs, succ, call = eff[pc]
            o = out_of(pc)
            if call is not None:
                if call in STUB_LABEL:
                    sdefs, suse = STUB_FLAGS.get(STUB_LABEL[call], (0, ALL))
                    if STUB_LABEL[call] == 'S_SCREEN':
                        o = 0
                    new = use | suse | (o & ~sdefs)
                else:
                    new = use | lin(call) | o          # l'appelé peut laisser passer
            else:
                new = use | (o & ~defs)
            if new != live_in[pc]:
                live_in[pc] = new
                changed = True
    return {pc: out_of(pc) for pc in starts}, eff


def strip_flags(lines, dead):
    """Retire les sauvegardes d'indicateurs morts (dead : FZ | FC)."""
    out = []
    i = 0
    while i < len(lines):
        ins = lines[i]
        nxt = lines[i + 1] if i + 1 < len(lines) else ''
        if dead & FZ and ins in ('sta zZ', 'sty zZ'):
            i += 1
            continue
        if dead & FZ and ins == 'lda #1' and nxt == 'sta zZ':
            i += 2
            continue
        if dead & FC and ins == 'rol zCY':
            i += 2 if nxt == 'inc zCY' else 1
            continue
        if dead & FC and ins in ('sty zCY', 'inc zCY'):
            i += 1
            continue
        if dead & FC and ins == 'lda #1' and nxt == 'sta zCY':
            i += 2
            continue
        out.append(ins)
        i += 1
    return out


def translate():
    starts, targets, tables, _, _, _, _ = gc.explore()
    live_out, effects = flag_liveness(starts, tables)
    saved = [0, 0]
    labels = set(targets) | set(gc.ROOTS) | CODE_PTRS
    for ents in tables.values():
        labels |= set(ents)
    out = ['; Fichier généré par tools/gb2m6502.py à partir de la ROM Game Boy.',
           '; Ne pas modifier à la main : relancer le script.', '']
    warnings = []
    prev_end = None
    prev_falls = False
    for pc in sorted(starts):
        if prev_falls and prev_end != pc:
            out.append(f'        jmp {lab(prev_end)}          ; continuité du code GB')
            labels.add(prev_end)
        if pc in labels or pc in STUB_LABEL:
            out.append(f'{lab(pc)}')
        op = ROM[pc]
        n = length(op)
        nxt = pc + n
        m = instructions[op]
        d8 = ROM[pc + 1] if n >= 2 else 0
        d16 = w(pc + 1) if n == 3 else 0
        shown = cb_instructions[ROM[pc + 1]] if op == 0xCB else m
        comment = f'; ${pc:04X} {shown}'
        if pc in PATCHES:
            out.append(f'        {PATCHES[pc]:30s}{comment} (réglage)')
            prev_end = nxt
            prev_falls = not PATCHES[pc].startswith('jmp ')
            continue

        def target16(v):
            if v in STUB_LABEL:
                return STUB_LABEL[v]
            if v in gc.STUBS:
                warnings.append(f'{pc:04x} appel du stub sans routine {v:04x}')
            return lab(v)

        if op in RST_JUMPTABLE:
            out.append(f'        {"jsr " + RST_JUMPTABLE[op]:30s}{comment}')
            out.append('        .word ' + ', '.join(lab(t) for t in tables[nxt]))
            prev_end = nxt + 2 * len(tables[nxt])
            prev_falls = False
            continue
        if op in RST_INLINE_DATA:
            cnt = inline_len(pc)
            out.append(f'        {"jsr " + RST_INLINE_DATA[op]:30s}{comment}')
            out.append('        .byte ' + ', '.join(f'${b:02X}' for b in ROM[nxt:nxt + cnt]))
            prev_end = nxt + cnt
            prev_falls = True
            continue
        if m == 'rst vec':
            lines, falls = [f'jsr G_RST{op & 0x38:02X}'], True
        else:
            lines, falls = translate_op(pc, op, m, d8, d16, nxt, tables, warnings, target16)
            dead = effects[pc][1] & ~live_out[pc]
            if dead:
                before = len(lines)
                lines = strip_flags(lines, dead)
                saved[0] += before - len(lines)
                saved[1] += 1
        first = True
        for ins in lines:
            if ins.startswith('_s'):
                out.append(ins)
                continue
            out.append(f'        {ins:30s}{comment if first else ""}')
            first = False
        if first:
            out.append(f'        {"":30s}{comment}')
        prev_end = nxt
        prev_falls = falls
    out = peephole(out)
    emitted = {int(l[2:6], 16) for l in out if l.startswith('G_')}
    missing = sorted(a for a in labels if a not in emitted and a not in STUB_LABEL)
    out += data_blocks()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    parts = split(out, getattr(CFG, 'SPLIT_AT', []))
    base = OUT[:-4]
    for k, part in enumerate(parts, 1):
        open(f'{base}_{k}.asm', 'w', encoding='utf-8').write('\n'.join(part) + '\n')
    print(f'{len(starts)} instructions GB traduites -> {os.path.basename(base)}_1..{len(parts)}.asm'
          f" ({saved[0]} sauvegardes d'indicateurs inutiles retirées, sur {saved[1]} instructions)")
    if missing:
        print('ÉTIQUETTES MANQUANTES :', ' '.join(f'{a:04x}' for a in missing))
    for x in warnings:
        print('ATTENTION :', x)


def split(out, fractions):
    """Coupe le code en morceaux (placés dans des zones mémoire différentes),
    à une frontière sans continuité (après jmp, rts ou une table), près de
    chaque fraction demandée du nombre de lignes."""
    parts = []
    start = 0
    for f in fractions:
        i = max(start, int(len(out) * f))
        while i < len(out):
            prev = out[i - 1].partition(';')[0].strip()
            if out[i].startswith('G_') and (prev in ('rts',) or prev.startswith('jmp ')
                                            or prev.startswith('.word')):
                break
            i += 1
        parts.append(out[start:i])
        start = i
    parts.append(out[start:])
    return parts


def peephole(out):
    """« sta X » suivi de « lda X » (sans étiquette entre les deux) : A contient
    déjà la valeur, la relecture est supprimée. Sans risque : les sauts du
    code traduit recalculent toujours leurs indicateurs juste avant."""
    res = []
    for line in out:
        ins, _, com = line.partition(';')
        ins = ins.strip()
        if res and line.startswith(' ') and ins.startswith('lda '):
            prev = res[-1].partition(';')[0].strip()
            if prev == 'sta ' + ins[4:]:
                if com.strip():
                    res.append(f'        {"":30s};{com}')
                continue
        res.append(line)
    return res


def data_blocks():
    if not DATA_BLOCKS:
        return []
    out = ['', '; --- Données de la ROM lues par la logique ---']
    names = set(DATA_PTRS) | DATA_LABELS
    for start, end, kind in DATA_BLOCKS:
        if kind == 'dw':
            names |= {w(a) for a in range(start, end, 2)}
    for start, end, kind in DATA_BLOCKS:
        if kind == 'dw':
            out.append(f'D_{start:04X}')
            out.append('        .word ' + ', '.join(f'D_{w(a):04X}' for a in range(start, end, 2)))
            continue
        a = start
        while a < end:
            if a in names:
                out.append(f'D_{a:04X}')
            b = a + 1
            while b < end and b - a < 16 and b not in names:
                b += 1
            out.append('        .byte ' + ', '.join(f'${x:02X}' for x in ROM[a:b]))
            a = b
    return out


if __name__ == '__main__':
    translate()
