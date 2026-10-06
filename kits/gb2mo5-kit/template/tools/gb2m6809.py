"""Traduction statique de la logique d'un jeu Game Boy (SM83) en 6809 (asm6809).

Lit la ROM, suit le code atteint depuis CFG.ROOTS (gb_closure) et écrit
CFG.LOGIC_OUT (gb/gb_logic.asm).

Modèle d'exécution :
- A du GB = A du 6809 ; B C D E H L du GB sont en page directe (rB ... rL,
  définis par le programme : paires dans l'ordre du 6809, octet haut
  d'abord, donc « ldx <rH » charge HL) ; B, X, U du 6809 sont des brouillons
  (et D, qui contient A : jamais sans sauvegarder A) ;
- indicateurs : seuls Z et C servent (pas de DAA dans la logique), et ceux
  du 6809 ont le même sens que ceux du GB (C = emprunt après SUB/CMP). Mais
  les LD/ST du 6809 modifient Z, et quelques instructions ne mettent pas C
  comme le GB (AND, OR, XOR : C du GB à 0). Une analyse de durée de vie des
  indicateurs (comme pour le C64) dit, après chaque instruction GB, si Z et
  C seront lus : on ajoute alors le correctif (andcc) ou la sauvegarde
  (pshs cc / puls cc) nécessaires, et seulement dans ce cas ;
- la pile GB est la pile S du 6809 : CALL -> JSR, RET -> RTS ; PUSH AF /
  POP AF -> PSHS A,CC / PULS A,CC (toujours appariés dans la logique) ;
- RAM GB déplacée par CFG.RAM_MAP ; la page directe (DP) contient la HRAM
  et les registres : l'assembleur choisit l'adressage direct (SETDP).
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
RAM_MAP = getattr(CFG, 'RAM_MAP', lambda a: None)

REG = {'b': 'rB', 'c': 'rC', 'd': 'rD', 'e': 'rE', 'h': 'rH', 'l': 'rL'}
PAIR = {'bc': 'rB', 'de': 'rD', 'hl': 'rH'}
IND = {'[hl]': 'rH', '[bc]': 'rB', '[de]': 'rD'}

FZ, FC = 1, 2
ALL = FZ | FC

_n = 0


def skip():
    global _n
    _n += 1
    return f'_s{_n}'


def lab(a):
    return f'G_{a:04X}'


def ram(a):
    m = RAM_MAP(a)
    return a if m is None else m


def src8(x, d8, pre):
    """Opérande 6809 d'une source GB 8 bits (hors A). pre reçoit le chargement
    de pointeur éventuel ; renvoie l'opérande (#n, <rX ou ,x)."""
    if x in REG:
        return '<' + REG[x]
    if x in IND:
        pre.append(f'ldx <{IND[x]}')
        return ',x'
    if x == 'd8':
        return f'#${d8:02X}'
    raise ValueError(x)


# lignes marquées : correctif utile seulement si l'indicateur est lu ensuite
def fixz(ins):
    return ins + ' @Z'


def fixc(ins):
    return ins + ' @C'


ALU8 = {'add': 'adda', 'adc': 'adca', 'sub': 'suba', 'sbc': 'sbca', 'cp': 'cmpa',
        'and': 'anda', 'or': 'ora', 'xor': 'eora'}


def translate_cb(cbm):
    op, args = cbm.split(None, 1)
    if op in ('bit', 'set', 'res'):
        n, r = args.split(',')
        m = 1 << int(n)
        if r == 'a':
            if op == 'bit':
                return [f'bita #${m:02X}']
            if op == 'set':
                return [f'ora #${m:02X}']
            return [f'anda #${0xFF ^ m:02X}']
        pre = []
        s = src8(r, 0, pre)
        if op == 'bit':
            return pre + [f'ldb {s}', f'bitb #${m:02X}']
        if op == 'set':
            return pre + [f'ldb {s}', f'orb #${m:02X}', f'stb {s}']
        return pre + [f'ldb {s}', f'andb #${0xFF ^ m:02X}', f'stb {s}']
    r = args
    if op == 'swap':
        assert r == 'a'
        return ['pshs a', 'lsla', 'lsla', 'lsla', 'lsla', 'ldb ,s+', 'lsrb', 'lsrb', 'lsrb',
                'lsrb', 'pshs b', 'ora ,s+', fixc('andcc #$FE')]
    m6 = {'rl': 'rol', 'rr': 'ror', 'sla': 'lsl', 'sra': 'asr', 'srl': 'lsr'}.get(op)
    if m6:
        if r == 'a':
            return [m6 + 'a']
        pre = []
        s = src8(r, 0, pre)
        return pre + [f'{m6} {s}']
    if op in ('rlc', 'rrc'):
        sk = skip()
        if r == 'a':
            if op == 'rlc':
                return ['lsla', f'bcc {sk}', 'ora #1', sk, 'tsta']
            return ['lsra', f'bcc {sk}', 'ora #$80', sk, 'tsta']
        pre = []
        s = src8(r, 0, pre)
        if op == 'rlc':
            return pre + [f'ldb {s}', 'lslb', f'bcc {sk}', 'orb #1', sk, f'stb {s}']
        return pre + [f'ldb {s}', 'lsrb', f'bcc {sk}', 'orb #$80', sk, f'stb {s}']
    raise ValueError(cbm)


def cond_branch(cond, target, long=True):
    b = {'z': 'beq', 'nz': 'bne', 'c': 'bcs', 'nc': 'bcc'}[cond]
    return ('l' + b if long else b) + ' ' + target


def inverse(cond):
    return {'z': 'nz', 'nz': 'z', 'c': 'nc', 'nc': 'c'}[cond]


def translate_op(pc, op, m, d8, d16, nxt, warnings, target16, zlive):
    """-> (lignes 6809, le code continue-t-il après ?, protégeable par pshs cc ?)"""
    if op == 0xCB:
        return translate_cb(cb_instructions[ROM[pc + 1]]), True, True
    parts = m.split(None, 1)
    name = parts[0]
    args = parts[1] if len(parts) > 1 else ''
    if name == 'nop':
        return [], True, True
    if name in ('di', 'ei'):
        warnings.append(f'{pc:04x} {name} ignoré')
        return [], True, True
    if name == 'add' and args.startswith('hl,'):
        rr = PAIR[args[3:]]
        if zlive:           # Z du GB conservé, C de l'addition
            sk = skip()
            return ['pshs a,cc', 'ldd <rH', f'addd <{rr}', 'std <rH', 'ldb ,s', 'andb #$FE',
                    f'bcc {sk}', 'incb', sk, 'stb ,s', 'puls a,cc'], True, False
        return ['pshs a', 'ldd <rH', f'addd <{rr}', 'std <rH', 'puls a'], True, False
    if name in ALU8:
        s = args.split(',')[-1] if name in ('add', 'adc', 'sbc') and args.startswith('a,') else args
        mn = ALU8[name]
        if s == 'a':
            if name == 'xor':
                return ['clra'], True, True
            if name in ('and', 'or'):
                return ['tsta', fixc('andcc #$FE')], True, True
            if name == 'cp':
                return ['cmpa #0', fixc('andcc #$FE'), fixz('orcc #4')], True, True
            if name == 'sub':
                return ['clra'], True, True
            if name == 'add':
                return ['lsla'], True, True
            if name == 'adc':
                return ['rola'], True, True
            return [f'{mn} ,s', 'nop'], True, True      # sbc a : improbable
        pre = []
        o = src8(s, d8, pre)
        body = pre + [f'{mn} {o}']
        if name in ('and', 'or', 'xor'):
            body.append(fixc('andcc #$FE'))
        return body, True, True
    if name in ('inc', 'dec'):
        if args in PAIR:
            rr = PAIR[args]
            return [f'ldx <{rr}', f'leax {1 if name == "inc" else -1},x', f'stx <{rr}'], True, True
        if args == 'a':
            return [name + 'a'], True, True
        pre = []
        o = src8(args, 0, pre)
        return pre + [f'{name} {o}'], True, True
    if name == 'rlca':
        sk = skip()
        return ['lsla', f'bcc {sk}', 'ora #1', sk, fixz('andcc #$FB')], True, True
    if name == 'rrca':
        sk = skip()
        return ['lsra', f'bcc {sk}', 'ora #$80', sk, fixz('andcc #$FB')], True, True
    if name == 'rla':
        return ['rola', fixz('andcc #$FB')], True, True
    if name == 'rra':
        return ['rora', fixz('andcc #$FB')], True, True
    if name == 'cpl':
        return ['eora #$FF'], True, True
    if name == 'scf':
        return ['orcc #1'], True, True
    if name == 'ccf':
        s1, s2 = skip(), skip()
        return [f'bcs {s1}', 'orcc #1', f'bra {s2}', s1, 'andcc #$FE', s2], True, True
    if name == 'push':
        if args == 'af':
            return ['pshs a,cc'], True, False
        rr = PAIR[args]
        if zlive:
            return ['pshs cc', f'ldx <{rr}', 'puls cc', 'pshs x'], True, False
        return [f'ldx <{rr}', 'pshs x'], True, False
    if name == 'pop':
        if args == 'af':
            return ['puls a,cc'], True, False
        rr = PAIR[args]
        if zlive:
            return ['puls x', 'pshs cc', f'stx <{rr}', 'puls cc'], True, False
        return ['puls x', f'stx <{rr}'], True, False
    if name == 'ldh':
        if args == '[a8],a':
            return [f'sta ${ram(0xFF00 + d8):04X}'], True, True
        return [f'lda ${ram(0xFF00 + d8):04X}'], True, True
    if name == 'ld':
        dst, src = args.split(',')
        if dst in PAIR and src == 'd16':
            if d16 in CODE_PTRS:
                v = lab(d16)
            elif d16 in DATA_PTRS:
                v = f'D_{d16:04X}'
            else:
                v = f'${ram(d16):04X}'
            return [f'ldx #{v}', f'stx <{PAIR[dst]}'], True, True
        if dst in ('[hl+]', '[hl-]'):
            if '+' in dst:
                return ['ldx <rH', 'sta ,x+', 'stx <rH'], True, True
            return ['ldx <rH', 'sta ,x', 'leax -1,x', 'stx <rH'], True, True
        if src in ('[hl+]', '[hl-]'):
            if '+' in src:
                return ['ldx <rH', 'lda ,x+', 'stx <rH'], True, True
            return ['ldx <rH', 'lda ,x', 'leax -1,x', 'stx <rH'], True, True
        if dst == '[a16]':
            if RAM_MAP(d16) is None:
                warnings.append(f'{pc:04x} écriture hors RAM déplacée {d16:04x}')
            return [f'sta ${ram(d16):04X}'], True, True
        if src == '[a16]':
            if RAM_MAP(d16) is None:
                warnings.append(f'{pc:04x} lecture hors RAM déplacée {d16:04x}')
            return [f'lda ${ram(d16):04X}'], True, True
        if dst == 'a':
            pre = []
            o = src8(src, d8, pre)
            return pre + [f'lda {o}'], True, True
        if src == 'a':
            pre = []
            o = src8(dst, 0, pre)
            return pre + [f'sta {o}'], True, True
        # registre ou [hl] <- registre, [hl] ou d8 : par B du 6809
        pre = []
        so = src8(src, d8, pre)
        pre2 = []
        do = src8(dst, 0, pre2)
        return pre + [f'ldb {so}'] + pre2 + [f'stb {do}'], True, True
    if name in ('jp', 'jr', 'call'):
        if 'pc+r8' in args:
            r = d8 - 256 if d8 > 127 else d8
            t = lab(nxt + r)
        else:
            t = target16(d16)
        cond = args.split(',')[0] if ',' in args else ''
        if name == 'call':
            if cond:
                sk = skip()
                return [cond_branch(inverse(cond), sk, long=False), f'jsr {t}', sk], True, False
            return [f'jsr {t}'], True, False
        if cond:
            return [cond_branch(cond, t)], True, False
        return [f'jmp {t}'], False, False
    if name in ('ret', 'reti'):
        if args:
            sk = skip()
            return [cond_branch(inverse(args), sk, long=False), 'rts', sk], True, False
        return ['rts'], False, False
    warnings.append(f'{pc:04x} {m} : non traduit')
    return [f'error "non traduit : {m} en ${pc:04X}"'], True, True


# --- Indicateurs : effet des instructions 6809 émises --------------------------------
Z_SAFE = {'jsr', 'jmp', 'rts', 'bra', 'bcc', 'bcs', 'beq', 'bne', 'lbeq', 'lbne', 'lbcc',
          'lbcs', 'pshs', 'puls', 'leas', 'leau', 'abx', 'tfr', 'exg', 'nop', 'lbra'}
C_CHANGERS = ('add', 'adc', 'sub', 'sbc', 'cmp', 'neg', 'com', 'clr', 'lsl', 'asl', 'lsr',
              'asr', 'rol', 'ror', 'mul', 'daa', 'andcc', 'orcc')


def clobbers(lines):
    """-> indicateurs (FZ | FC) que ces lignes 6809 peuvent modifier."""
    f = 0
    for ins in lines:
        if ins.startswith('_s'):
            continue
        mn = ins.split()[0]
        if mn in ('pshs', 'puls') and 'cc' in ins:
            f |= ALL
            continue
        if mn in ('andcc', 'orcc'):
            t = ins.split('#')[1].split()[0]
            v = int(t[1:], 16) if t.startswith('$') else int(t)
            bits = (~v & 0xFF) if mn == 'andcc' else v
            f |= (FZ if bits & 4 else 0) | (FC if bits & 1 else 0)
            continue
        if mn not in Z_SAFE:
            f |= FZ
        if any(mn.startswith(c) for c in C_CHANGERS):
            f |= FC
    return f


# --- Durée de vie des indicateurs (reprise de la version C64) --------------------------
STUB_FLAGS = dict(getattr(CFG, 'STUB_FLAGS', {}))
COND = {'z': FZ, 'nz': FZ, 'c': FC, 'nc': FC}
RST_DEFS = dict(getattr(CFG, 'RST_FLAG_DEFS', {}))


def flag_effect(pc, tables):
    """-> (lus, écrits, successeurs, appel)"""
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
    if name in ('ret', 'reti'):         # (ce qui est lu après : successeur 'RET')
        return COND.get(args, 0), 0, (['RET', nxt] if args else ['RET']), None
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
    return 0, 0, [nxt], None


def routines(starts, eff):
    """Routine(s) de chaque instruction : parcours depuis chaque cible d'appel
    (et racine) sans suivre les appels. -> ({pc: {routines}}, {routine: [appels]})"""
    entries = set(gc.ROOTS) | set(CODE_PTRS)
    callers = {}
    for pc, (use, defs, succ, call) in eff.items():
        if call is not None and call not in STUB_LABEL:
            entries.add(call)
            callers.setdefault(call, []).append(pc)
    member = {pc: set() for pc in starts}
    for e in entries:
        todo = [e]
        seen = set()
        while todo:
            pc = todo.pop()
            if pc in seen or pc not in eff:
                continue
            seen.add(pc)
            member[pc].add(e)
            for t in eff[pc][2]:
                if isinstance(t, int):
                    todo.append(t)
    return member, callers


def flag_liveness(starts, tables):
    """-> ({pc: indicateurs vivants après l'instruction}, effets).
    Au RET : indicateurs lus après les appels de la routine (analyse
    interprocédurale) ; racines appelées par le code écrit à la main : aucun ;
    adresses de code empilées (CODE_PTRS) et instructions hors routine : tous."""
    eff = {pc: flag_effect(pc, tables) for pc in starts}
    member, callers = routines(starts, eff)
    live_in = {pc: 0 for pc in starts}
    ret_live = {r: 0 for r in set().union(*member.values())}
    for r in CODE_PTRS:
        ret_live[r] = ALL

    def lin(t, pc):
        if t == 'RET':
            rs = member.get(pc)
            if not rs:
                return ALL
            o = 0
            for r in rs:
                o |= ret_live.get(r, ALL)
            return o
        if t == 'END':
            return 0
        return live_in.get(t, ALL)

    def out_of(pc):
        o = 0
        for t in eff[pc][2]:
            o |= lin(t, pc)
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
                    new = use | lin(call, pc) | o
            else:
                new = use | (o & ~defs)
            if new != live_in[pc]:
                live_in[pc] = new
                changed = True
        for r, calls in callers.items():
            v = ret_live.get(r, 0)
            for c in calls:
                v |= out_of(c)
            if v != ret_live.get(r, 0):
                ret_live[r] = v
                changed = True
    return {pc: out_of(pc) for pc in starts}, eff


def finish(lines, live, writes, protectable, stats):
    """Retire les correctifs inutiles, ajoute la sauvegarde de CC si besoin."""
    out = []
    for ins in lines:
        if ins.endswith(' @Z'):
            if live & FZ:
                out.append(ins[:-3])
            continue
        if ins.endswith(' @C'):
            if live & FC:
                out.append(ins[:-3])
            continue
        out.append(ins)
    if not protectable:         # indicateurs déjà traités par la traduction elle-même
        return out
    need = clobbers([i for i in lines if not i.endswith((' @Z', ' @C'))]) & live & ~writes
    if need:
        stats[0] += 1
        return ['pshs cc'] + out + ['puls cc']
    return out


def translate():
    starts, targets, tables, _, _, _, _ = gc.explore()
    live_out, effects = flag_liveness(starts, tables)
    stats = [0]
    labels = set(targets) | set(gc.ROOTS) | CODE_PTRS
    for ents in tables.values():
        labels |= set(ents)
    out = ['; Fichier généré par tools/gb2m6809.py à partir de la ROM Game Boy.',
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
            out.append('        fdb ' + ','.join(lab(t) for t in tables[nxt]))
            prev_end = nxt + 2 * len(tables[nxt])
            prev_falls = False
            continue
        if op in RST_INLINE_DATA:
            cnt = inline_len(pc)
            out.append(f'        {"jsr " + RST_INLINE_DATA[op]:30s}{comment}')
            out.append('        fcb ' + ','.join(f'${b:02X}' for b in ROM[nxt:nxt + cnt]))
            prev_end = nxt + cnt
            prev_falls = True
            continue
        live = live_out[pc]
        if m == 'rst vec':
            lines, falls, prot = [f'jsr G_RST{op & 0x38:02X}'], True, False
        else:
            lines, falls, prot = translate_op(pc, op, m, d8, d16, nxt, warnings, target16,
                                              bool(live & FZ))
        lines = finish(lines, live, effects[pc][1], prot, stats)
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
    emitted = {int(l[2:6], 16) for l in out if l.startswith('G_')}
    missing = sorted(a for a in labels if a not in emitted and a not in STUB_LABEL)
    out += data_blocks()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(f'{len(starts)} instructions GB traduites -> {OUT} '
          f'({stats[0]} sauvegardes de CC)')
    if missing:
        print('ÉTIQUETTES MANQUANTES :', ' '.join(f'{a:04x}' for a in missing))
    for x in warnings:
        print('ATTENTION :', x)


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
            # table de pointeurs lue octet par octet par la logique GB :
            # ordre du GB (octet bas d'abord), pas celui du 6809
            out.append(f'D_{start:04X}')
            for a in range(start, end, 2):
                out.append(f'        fcb (D_{w(a):04X})&255,(D_{w(a):04X})>>8')
            continue
        a = start
        while a < end:
            if a in names:
                out.append(f'D_{a:04X}')
            b = a + 1
            while b < end and b - a < 16 and b not in names:
                b += 1
            out.append('        fcb ' + ','.join(f'${x:02X}' for x in ROM[a:b]))
            a = b
    return out


if __name__ == '__main__':
    translate()
