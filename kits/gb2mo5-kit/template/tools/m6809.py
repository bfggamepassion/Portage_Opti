"""Émulateur 6809 compact (Python), avec décompte des cycles.

Écrit pour le portage MO5 : mémoire plate (bytearray de 64 Ko) et deux
fonctions facultatives pour les zones spéciales :
  - read_hook(addr) -> valeur ou None (None : lire la mémoire) ;
  - write_hook(addr, valeur) -> True si l'écriture est prise en charge.
Elles ne sont appelées que pour les adresses où special[addr] est vrai
(zone vidéo en banques, entrées-sorties).

Registres : a, b, dp, cc, x, y, u, s, pc ; cycles (total).
Vérifié par tools/test_m6809.py contre l'émulateur MC6809 (PyPI).
"""

CC_E, CC_F, CC_H, CC_I, CC_N, CC_Z, CC_V, CC_C = 0x80, 0x40, 0x20, 0x10, 8, 4, 2, 1


class CPU:
    def __init__(self, mem=None):
        self.mem = mem if mem is not None else bytearray(65536)
        self.special = bytearray(65536)
        self.read_hook = None
        self.write_hook = None
        self.a = self.b = self.dp = 0
        self.cc = CC_I | CC_F
        self.x = self.y = self.u = self.s = self.pc = 0
        self.cycles = 0
        self._build()

    # --- mémoire ------------------------------------------------------------
    def rd(self, a):
        if self.special[a]:
            v = self.read_hook(a)
            if v is not None:
                return v
        return self.mem[a]

    def wr(self, a, v):
        if self.special[a] and self.write_hook(a, v):
            return
        self.mem[a] = v

    def rd16(self, a):
        return (self.rd(a) << 8) | self.rd((a + 1) & 0xFFFF)

    def wr16(self, a, v):
        self.wr(a, v >> 8)
        self.wr((a + 1) & 0xFFFF, v & 0xFF)

    def fetch(self):
        v = self.mem[self.pc]
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def fetch16(self):
        v = (self.mem[self.pc] << 8) | self.mem[(self.pc + 1) & 0xFFFF]
        self.pc = (self.pc + 2) & 0xFFFF
        return v

    # --- registres indexés -----------------------------------------------------
    def getr(self, r):
        return (self.x, self.y, self.u, self.s)[r]

    def setr(self, r, v):
        if r == 0:
            self.x = v
        elif r == 1:
            self.y = v
        elif r == 2:
            self.u = v
        else:
            self.s = v

    @property
    def d(self):
        return (self.a << 8) | self.b

    @d.setter
    def d(self, v):
        self.a = (v >> 8) & 0xFF
        self.b = v & 0xFF

    # --- adressage ---------------------------------------------------------------
    def ea_direct(self):
        return (self.dp << 8) | self.fetch()

    def ea_ext(self):
        return self.fetch16()

    def ea_indexed(self):
        pb = self.fetch()
        r = (pb >> 5) & 3
        if not pb & 0x80:                               # 5 bits signés
            off = pb & 0x1F
            if off & 0x10:
                off -= 32
            self.cycles += 1
            return (self.getr(r) + off) & 0xFFFF
        mode = pb & 0x0F
        ind = pb & 0x10
        if mode == 0:                                   # ,R+
            ea = self.getr(r)
            self.setr(r, (ea + 1) & 0xFFFF)
            self.cycles += 2
        elif mode == 1:                                 # ,R++
            ea = self.getr(r)
            self.setr(r, (ea + 2) & 0xFFFF)
            self.cycles += 3
        elif mode == 2:                                 # ,-R
            ea = (self.getr(r) - 1) & 0xFFFF
            self.setr(r, ea)
            self.cycles += 2
        elif mode == 3:                                 # ,--R
            ea = (self.getr(r) - 2) & 0xFFFF
            self.setr(r, ea)
            self.cycles += 3
        elif mode == 4:                                 # ,R
            ea = self.getr(r)
        elif mode == 5:                                 # B,R
            b = self.b - 256 if self.b & 0x80 else self.b
            ea = (self.getr(r) + b) & 0xFFFF
            self.cycles += 1
        elif mode == 6:                                 # A,R
            a = self.a - 256 if self.a & 0x80 else self.a
            ea = (self.getr(r) + a) & 0xFFFF
            self.cycles += 1
        elif mode == 8:                                 # n8,R
            o = self.fetch()
            if o & 0x80:
                o -= 256
            ea = (self.getr(r) + o) & 0xFFFF
            self.cycles += 1
        elif mode == 9:                                 # n16,R
            ea = (self.getr(r) + self.fetch16()) & 0xFFFF
            self.cycles += 4
        elif mode == 11:                                # D,R
            ea = (self.getr(r) + self.d) & 0xFFFF
            self.cycles += 4
        elif mode == 12:                                # n8,PC
            o = self.fetch()
            if o & 0x80:
                o -= 256
            ea = (self.pc + o) & 0xFFFF
            self.cycles += 1
        elif mode == 13:                                # n16,PC
            o = self.fetch16()
            ea = (self.pc + o) & 0xFFFF
            self.cycles += 5
        elif mode == 15:                                # [n16]
            ea = self.fetch16()
            self.cycles += 2
        else:
            raise RuntimeError(f'mode indexé illégal ${pb:02X} en ${self.pc:04X}')
        if ind:
            ea = self.rd16(ea)
            self.cycles += 3
        return ea

    # --- indicateurs -------------------------------------------------------------
    def nz8(self, v):
        self.cc = (self.cc & ~(CC_N | CC_Z | CC_V)) | (v & 0x80 and CC_N) | (0 if v else CC_Z)

    def nz16(self, v):
        self.cc = (self.cc & ~(CC_N | CC_Z | CC_V)) | (v & 0x8000 and CC_N) | (0 if v else CC_Z)

    def add8(self, a, b, c=0):
        r = a + b + c
        cc = self.cc & ~(CC_H | CC_N | CC_Z | CC_V | CC_C)
        if (a & 15) + (b & 15) + c > 15:
            cc |= CC_H
        if r & 0x100:
            cc |= CC_C
        r &= 0xFF
        if r & 0x80:
            cc |= CC_N
        if not r:
            cc |= CC_Z
        if (~(a ^ b) & (a ^ r)) & 0x80:
            cc |= CC_V
        self.cc = cc
        return r

    def sub8(self, a, b, c=0):
        r = a - b - c
        cc = self.cc & ~(CC_N | CC_Z | CC_V | CC_C)
        if r < 0:
            cc |= CC_C
        r &= 0xFF
        if r & 0x80:
            cc |= CC_N
        if not r:
            cc |= CC_Z
        if ((a ^ b) & (a ^ r)) & 0x80:
            cc |= CC_V
        self.cc = cc
        return r

    def add16(self, a, b):
        r = a + b
        cc = self.cc & ~(CC_N | CC_Z | CC_V | CC_C)
        if r & 0x10000:
            cc |= CC_C
        r &= 0xFFFF
        if r & 0x8000:
            cc |= CC_N
        if not r:
            cc |= CC_Z
        if (~(a ^ b) & (a ^ r)) & 0x8000:
            cc |= CC_V
        self.cc = cc
        return r

    def sub16(self, a, b):
        r = a - b
        cc = self.cc & ~(CC_N | CC_Z | CC_V | CC_C)
        if r < 0:
            cc |= CC_C
        r &= 0xFFFF
        if r & 0x8000:
            cc |= CC_N
        if not r:
            cc |= CC_Z
        if ((a ^ b) & (a ^ r)) & 0x8000:
            cc |= CC_V
        self.cc = cc
        return r

    # --- opérations de lecture-modification-écriture (8 bits) --------------------
    def rmw(self, kind, v):
        cc = self.cc
        if kind == 'neg':
            r = self.sub8(0, v)
            return r
        if kind == 'com':
            r = (~v) & 0xFF
            self.nz8(r)
            self.cc |= CC_C
            return r
        if kind == 'lsr':
            r = v >> 1
            self.cc = (cc & ~(CC_N | CC_Z | CC_C)) | (v & 1) | (0 if r else CC_Z)
            return r
        if kind == 'ror':
            r = (v >> 1) | ((cc & CC_C) << 7)
            self.cc = (cc & ~(CC_N | CC_Z | CC_C)) | (v & 1) | (r & 0x80 and CC_N) | (0 if r else CC_Z)
            return r
        if kind == 'asr':
            r = (v >> 1) | (v & 0x80)
            self.cc = (cc & ~(CC_N | CC_Z | CC_C)) | (v & 1) | (r & 0x80 and CC_N) | (0 if r else CC_Z)
            return r
        if kind == 'asl':
            r = (v << 1) & 0xFF
            self.cc = ((cc & ~(CC_N | CC_Z | CC_V | CC_C)) | (v >> 7) | (r & 0x80 and CC_N)
                       | (0 if r else CC_Z) | (((v ^ (v << 1)) & 0x80) and CC_V))
            return r
        if kind == 'rol':
            r = ((v << 1) | (cc & CC_C)) & 0xFF
            self.cc = ((cc & ~(CC_N | CC_Z | CC_V | CC_C)) | (v >> 7) | (r & 0x80 and CC_N)
                       | (0 if r else CC_Z) | (((v ^ (v << 1)) & 0x80) and CC_V))
            return r
        if kind == 'dec':
            r = (v - 1) & 0xFF
            self.cc = ((cc & ~(CC_N | CC_Z | CC_V)) | (r & 0x80 and CC_N) | (0 if r else CC_Z)
                       | (CC_V if v == 0x80 else 0))
            return r
        if kind == 'inc':
            r = (v + 1) & 0xFF
            self.cc = ((cc & ~(CC_N | CC_Z | CC_V)) | (r & 0x80 and CC_N) | (0 if r else CC_Z)
                       | (CC_V if v == 0x7F else 0))
            return r
        if kind == 'tst':
            self.nz8(v)
            return None
        if kind == 'clr':
            self.cc = (cc & ~(CC_N | CC_V | CC_C)) | CC_Z
            return 0
        raise RuntimeError(kind)

    # --- pile ------------------------------------------------------------------------
    def push8(self, sp_attr, v):
        sp = (getattr(self, sp_attr) - 1) & 0xFFFF
        setattr(self, sp_attr, sp)
        self.wr(sp, v)

    def pull8(self, sp_attr):
        sp = getattr(self, sp_attr)
        v = self.rd(sp)
        setattr(self, sp_attr, (sp + 1) & 0xFFFF)
        return v

    def push16(self, sp_attr, v):
        self.push8(sp_attr, v & 0xFF)
        self.push8(sp_attr, v >> 8)

    def pull16(self, sp_attr):
        hi = self.pull8(sp_attr)
        return (hi << 8) | self.pull8(sp_attr)

    def pshs(self, pb, sp_attr, other):
        if pb & 0x80:
            self.push16(sp_attr, self.pc)
            self.cycles += 2
        if pb & 0x40:
            self.push16(sp_attr, getattr(self, other))
            self.cycles += 2
        if pb & 0x20:
            self.push16(sp_attr, self.y)
            self.cycles += 2
        if pb & 0x10:
            self.push16(sp_attr, self.x)
            self.cycles += 2
        if pb & 0x08:
            self.push8(sp_attr, self.dp)
            self.cycles += 1
        if pb & 0x04:
            self.push8(sp_attr, self.b)
            self.cycles += 1
        if pb & 0x02:
            self.push8(sp_attr, self.a)
            self.cycles += 1
        if pb & 0x01:
            self.push8(sp_attr, self.cc)
            self.cycles += 1

    def puls(self, pb, sp_attr, other):
        if pb & 0x01:
            self.cc = self.pull8(sp_attr)
            self.cycles += 1
        if pb & 0x02:
            self.a = self.pull8(sp_attr)
            self.cycles += 1
        if pb & 0x04:
            self.b = self.pull8(sp_attr)
            self.cycles += 1
        if pb & 0x08:
            self.dp = self.pull8(sp_attr)
            self.cycles += 1
        if pb & 0x10:
            self.x = self.pull16(sp_attr)
            self.cycles += 2
        if pb & 0x20:
            self.y = self.pull16(sp_attr)
            self.cycles += 2
        if pb & 0x40:
            setattr(self, other, self.pull16(sp_attr))
            self.cycles += 2
        if pb & 0x80:
            self.pc = self.pull16(sp_attr)
            self.cycles += 2

    # --- TFR / EXG -------------------------------------------------------------------
    def reg_get(self, n):
        return {0: self.d, 1: self.x, 2: self.y, 3: self.u, 4: self.s, 5: self.pc,
                8: self.a, 9: self.b, 10: self.cc, 11: self.dp}[n]

    def reg_set(self, n, v):
        if n == 0:
            self.d = v & 0xFFFF
        elif n == 1:
            self.x = v & 0xFFFF
        elif n == 2:
            self.y = v & 0xFFFF
        elif n == 3:
            self.u = v & 0xFFFF
        elif n == 4:
            self.s = v & 0xFFFF
        elif n == 5:
            self.pc = v & 0xFFFF
        elif n == 8:
            self.a = v & 0xFF
        elif n == 9:
            self.b = v & 0xFF
        elif n == 10:
            self.cc = v & 0xFF
        elif n == 11:
            self.dp = v & 0xFF

    def cond(self, n):
        cc = self.cc
        c = cc & CC_C
        z = cc & CC_Z
        nn = bool(cc & CC_N)
        v = bool(cc & CC_V)
        if n == 0:
            return True
        if n == 1:
            return False
        if n == 2:
            return not (c or z)
        if n == 3:
            return bool(c or z)
        if n == 4:
            return not c
        if n == 5:
            return bool(c)
        if n == 6:
            return not z
        if n == 7:
            return bool(z)
        if n == 8:
            return not v
        if n == 9:
            return v
        if n == 10:
            return not nn
        if n == 11:
            return nn
        if n == 12:
            return nn == v
        if n == 13:
            return nn != v
        if n == 14:
            return not z and nn == v
        return bool(z) or nn != v

    # --- table des instructions --------------------------------------------------------
    def _build(self):
        ops = [None] * 256
        p2 = {}
        p3 = {}
        rmw_names = {0x0: 'neg', 0x3: 'com', 0x4: 'lsr', 0x6: 'ror', 0x7: 'asr', 0x8: 'asl',
                     0x9: 'rol', 0xA: 'dec', 0xC: 'inc', 0xD: 'tst', 0xF: 'clr'}

        def mk_rmw_mem(kind, eaf, cyc):
            def f():
                ea = eaf()
                r = self.rmw(kind, self.rd(ea))
                if r is not None:
                    self.wr(ea, r)
                self.cycles += cyc
            return f

        def mk_rmw_reg(kind, reg):
            def f():
                r = self.rmw(kind, getattr(self, reg))
                if r is not None:
                    setattr(self, reg, r)
                self.cycles += 2
            return f

        for lo, kind in rmw_names.items():
            ops[0x00 | lo] = mk_rmw_mem(kind, self.ea_direct, 6)
            ops[0x60 | lo] = mk_rmw_mem(kind, self.ea_indexed, 6)
            ops[0x70 | lo] = mk_rmw_mem(kind, self.ea_ext, 7)
            ops[0x40 | lo] = mk_rmw_reg(kind, 'a')
            ops[0x50 | lo] = mk_rmw_reg(kind, 'b')

        def mk_jmp(eaf, cyc):
            def f():
                self.pc = eaf()
                self.cycles += cyc
            return f
        ops[0x0E] = mk_jmp(self.ea_direct, 3)
        ops[0x6E] = mk_jmp(self.ea_indexed, 3)
        ops[0x7E] = mk_jmp(self.ea_ext, 4)

        def nop():
            self.cycles += 2
        ops[0x12] = nop

        def lbra():
            o = self.fetch16()
            self.pc = (self.pc + o) & 0xFFFF
            self.cycles += 5
        ops[0x16] = lbra

        def lbsr():
            o = self.fetch16()
            self.push16('s', self.pc)
            self.pc = (self.pc + o) & 0xFFFF
            self.cycles += 9
        ops[0x17] = lbsr

        def daa():
            a = self.a
            cc = self.cc
            corr = 0
            if (cc & CC_H) or (a & 15) > 9:
                corr |= 0x06
            if (cc & CC_C) or (a >> 4) > 9 or ((a >> 4) > 8 and (a & 15) > 9):
                corr |= 0x60
            r = a + corr
            c = (cc & CC_C) or (r > 0xFF)
            r &= 0xFF
            self.a = r
            self.nz8(r)
            self.cc = (self.cc & ~CC_C) | (CC_C if c else 0)
            self.cycles += 2
        ops[0x19] = daa

        def orcc():
            self.cc |= self.fetch()
            self.cycles += 3
        ops[0x1A] = orcc

        def andcc():
            self.cc &= self.fetch()
            self.cycles += 3
        ops[0x1C] = andcc

        def sex():
            self.a = 0xFF if self.b & 0x80 else 0
            self.nz16(self.d)
            self.cycles += 2
        ops[0x1D] = sex

        def exg():
            pb = self.fetch()
            r1, r2 = pb >> 4, pb & 15
            v1, v2 = self.reg_get(r1), self.reg_get(r2)
            self.reg_set(r1, v2)
            self.reg_set(r2, v1)
            self.cycles += 8
        ops[0x1E] = exg

        def tfr():
            pb = self.fetch()
            v = self.reg_get(pb >> 4)
            if (pb >> 4) >= 8 and (pb & 15) < 8:
                v = v | 0xFF00
            self.reg_set(pb & 15, v)
            self.cycles += 6
        ops[0x1F] = tfr

        def mk_bra(n):
            def f():
                o = self.fetch()
                if self.cond(n):
                    self.pc = (self.pc + (o - 256 if o & 0x80 else o)) & 0xFFFF
                self.cycles += 3
            return f
        for n in range(16):
            ops[0x20 | n] = mk_bra(n)

        def mk_lbra(n):
            def f():
                o = self.fetch16()
                if self.cond(n):
                    self.pc = (self.pc + o) & 0xFFFF
                    self.cycles += 6
                else:
                    self.cycles += 5
            return f
        for n in range(1, 16):
            p2[0x20 | n] = mk_lbra(n)

        def mk_lea(r, flags):
            def f():
                ea = self.ea_indexed()
                self.setr(r, ea)
                if flags:
                    self.cc = (self.cc & ~CC_Z) | (0 if ea else CC_Z)
                self.cycles += 4
            return f
        ops[0x30] = mk_lea(0, True)
        ops[0x31] = mk_lea(1, True)
        ops[0x32] = mk_lea(3, False)
        ops[0x33] = mk_lea(2, False)

        def pshs():
            self.pshs(self.fetch(), 's', 'u')
            self.cycles += 5
        ops[0x34] = pshs

        def puls():
            self.puls(self.fetch(), 's', 'u')
            self.cycles += 5
        ops[0x35] = puls

        def pshu():
            self.pshs(self.fetch(), 'u', 's')
            self.cycles += 5
        ops[0x36] = pshu

        def pulu():
            self.puls(self.fetch(), 'u', 's')
            self.cycles += 5
        ops[0x37] = pulu

        def rts():
            self.pc = self.pull16('s')
            self.cycles += 5
        ops[0x39] = rts

        def abx():
            self.x = (self.x + self.b) & 0xFFFF
            self.cycles += 3
        ops[0x3A] = abx

        def rti():
            self.cc = self.pull8('s')
            if self.cc & CC_E:
                self.puls(0xFE, 's', 'u')
                self.cycles += 15
            else:
                self.pc = self.pull16('s')
                self.cycles += 6
        ops[0x3B] = rti

        def mul():
            r = self.a * self.b
            self.d = r
            self.cc = (self.cc & ~(CC_Z | CC_C)) | (0 if r else CC_Z) | (CC_C if r & 0x80 else 0)
            self.cycles += 11
        ops[0x3D] = mul

        # --- accumulateurs : modes immédiat, direct, indexé, étendu ---------------
        def ea_for(mode, size):
            if mode == 0:
                def imm():
                    a = self.pc
                    self.pc = (self.pc + size) & 0xFFFF
                    return a
                return imm
            return (None, self.ea_direct, self.ea_indexed, self.ea_ext)[mode]

        CYC8 = (2, 4, 4, 5)
        CYC16A = (4, 6, 6, 7)
        CYC16L = (3, 5, 5, 6)

        def mk_alu8(reg, fn, mode, store=True):
            eaf = ea_for(mode, 1)
            cyc = CYC8[mode]

            def f():
                v = self.rd(eaf())
                r = fn(getattr(self, reg), v)
                if store and r is not None:
                    setattr(self, reg, r)
                self.cycles += cyc
            return f

        def f_sub(a, v):
            return self.sub8(a, v)

        def f_cmp(a, v):
            self.sub8(a, v)
            return None

        def f_sbc(a, v):
            return self.sub8(a, v, self.cc & CC_C)

        def f_and(a, v):
            r = a & v
            self.nz8(r)
            return r

        def f_bit(a, v):
            self.nz8(a & v)
            return None

        def f_ld(a, v):
            self.nz8(v)
            return v

        def f_eor(a, v):
            r = a ^ v
            self.nz8(r)
            return r

        def f_adc(a, v):
            return self.add8(a, v, self.cc & CC_C)

        def f_or(a, v):
            r = a | v
            self.nz8(r)
            return r

        def f_add(a, v):
            return self.add8(a, v)

        alu = {0x0: f_sub, 0x1: f_cmp, 0x2: f_sbc, 0x4: f_and, 0x5: f_bit, 0x6: f_ld,
               0x8: f_eor, 0x9: f_adc, 0xA: f_or, 0xB: f_add}
        for mode in range(4):
            for lo, fn in alu.items():
                ops[0x80 | (mode << 4) | lo] = mk_alu8('a', fn, mode)
                ops[0xC0 | (mode << 4) | lo] = mk_alu8('b', fn, mode)

        def mk_st8(reg, mode):
            eaf = ea_for(mode, 1)
            cyc = CYC8[mode]

            def f():
                v = getattr(self, reg)
                self.wr(eaf(), v)
                self.nz8(v)
                self.cycles += cyc
            return f
        for mode in (1, 2, 3):
            ops[0x87 | (mode << 4)] = mk_st8('a', mode)
            ops[0xC7 | (mode << 4)] = mk_st8('b', mode)

        def mk_16(kind, getter, setter, mode, cycles):
            eaf = ea_for(mode, 2)

            def f():
                ea = eaf()
                if kind == 'st':
                    v = getter()
                    self.wr16(ea, v)
                    self.nz16(v)
                else:
                    v = self.rd16(ea)
                    if kind == 'ld':
                        setter(v)
                        self.nz16(v)
                    elif kind == 'add':
                        setter(self.add16(getter(), v))
                    elif kind == 'sub':
                        setter(self.sub16(getter(), v))
                    elif kind == 'cmp':
                        self.sub16(getter(), v)
                self.cycles += cycles[mode]
            return f

        def g_d():
            return self.d

        def s_d(v):
            self.d = v

        def g(attr):
            return lambda: getattr(self, attr)

        def s(attr):
            return lambda v: setattr(self, attr, v)

        CYC_CMP2 = (5, 7, 7, 8)
        CYC_L2 = (4, 6, 6, 7)
        for mode in range(4):
            base = mode << 4
            ops[0x83 | base] = mk_16('sub', g_d, s_d, mode, CYC16A)
            ops[0xC3 | base] = mk_16('add', g_d, s_d, mode, CYC16A)
            ops[0x8C | base] = mk_16('cmp', g('x'), None, mode, CYC16A)
            ops[0x8E | base] = mk_16('ld', None, s('x'), mode, CYC16L)
            ops[0xCC | base] = mk_16('ld', None, s_d, mode, CYC16L)
            ops[0xCE | base] = mk_16('ld', None, s('u'), mode, CYC16L)
            p2[0x83 | base] = mk_16('cmp', g_d, None, mode, CYC_CMP2)
            p2[0x8C | base] = mk_16('cmp', g('y'), None, mode, CYC_CMP2)
            p2[0x8E | base] = mk_16('ld', None, s('y'), mode, CYC_L2)
            p2[0xCE | base] = mk_16('ld', None, s('s'), mode, CYC_L2)
            p3[0x83 | base] = mk_16('cmp', g('u'), None, mode, CYC_CMP2)
            p3[0x8C | base] = mk_16('cmp', g('s'), None, mode, CYC_CMP2)
            if mode:
                ops[0x8F | base] = mk_16('st', g('x'), None, mode, CYC16L)
                ops[0xCD | base] = mk_16('st', g_d, None, mode, CYC16L)
                ops[0xCF | base] = mk_16('st', g('u'), None, mode, CYC16L)
                p2[0x8F | base] = mk_16('st', g('y'), None, mode, CYC_L2)
                p2[0xCF | base] = mk_16('st', g('s'), None, mode, CYC_L2)

        def bsr():
            o = self.fetch()
            self.push16('s', self.pc)
            self.pc = (self.pc + (o - 256 if o & 0x80 else o)) & 0xFFFF
            self.cycles += 7
        ops[0x8D] = bsr

        def mk_jsr(eaf, cyc):
            def f():
                ea = eaf()
                self.push16('s', self.pc)
                self.pc = ea
                self.cycles += cyc
            return f
        ops[0x9D] = mk_jsr(self.ea_direct, 7)
        ops[0xAD] = mk_jsr(self.ea_indexed, 7)
        ops[0xBD] = mk_jsr(self.ea_ext, 8)

        def page2():
            op = self.fetch()
            f = p2.get(op)
            if f is None:
                raise RuntimeError(f'instruction $10 ${op:02X} inconnue en ${self.pc - 2:04X}')
            f()

        def page3():
            op = self.fetch()
            f = p3.get(op)
            if f is None:
                raise RuntimeError(f'instruction $11 ${op:02X} inconnue en ${self.pc - 2:04X}')
            f()
        ops[0x10] = page2
        ops[0x11] = page3
        self.ops = ops
        self.p2 = p2
        self.p3 = p3

    def step(self):
        op = self.fetch()
        f = self.ops[op]
        if f is None:
            raise RuntimeError(f'instruction ${op:02X} inconnue en ${(self.pc - 1) & 0xFFFF:04X}')
        f()

    def call(self, addr, stop=0xFFF0, max_steps=10_000_000):
        """Appelle la routine addr (JSR simulé) jusqu'au retour."""
        self.push16('s', stop)
        self.pc = addr
        n = 0
        while self.pc != stop:
            self.step()
            n += 1
            if n > max_steps:
                raise RuntimeError(f'routine ${addr:04X} : trop long (PC ${self.pc:04X})')
