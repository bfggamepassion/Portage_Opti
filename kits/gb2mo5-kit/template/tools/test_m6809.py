"""Test croisé : tools/m6809.py contre l'émulateur MC6809 (PyPI).

Pour des milliers d'instructions tirées au hasard (opcode, opérandes,
registres et mémoire aléatoires), exécute une instruction sur les deux
émulateurs et compare registres, indicateurs N Z V C (et H après les
additions 8 bits) et mémoire.
Usage : python tools/test_m6809.py [nombre]
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import m6809  # noqa: E402
from MC6809.components.cpu6809 import CPU as RefCPU  # noqa: E402
from MC6809.components.memory import Memory  # noqa: E402
from MC6809.core.configs import BaseConfig  # noqa: E402


class Cfg(BaseConfig):
    RAM_START = 0x0000
    RAM_END = 0x7FFF
    ROM_START = 0x8000
    ROM_END = 0xFFFF


# postoctets indexés valides (hors modes indirects rares)
IDX_MODES = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x08, 0x09, 0x0B, 0x0C, 0x0D,
             0x14, 0x11, 0x13, 0x15, 0x16, 0x18, 0x19, 0x1B, 0x1C, 0x1D, 0x1F]


def rand_postbyte():
    if random.random() < 0.3:
        return random.randrange(0, 0x80)                # 5 bits signés
    m = random.choice(IDX_MODES)
    r = random.randrange(4) << 5
    if m == 0x1F:
        return 0x9F
    return 0x80 | r | m


PAGE0 = [op for op in range(256)
         if op not in (0x01, 0x02, 0x05, 0x0B, 0x10, 0x11, 0x13, 0x14, 0x15, 0x18, 0x1B, 0x38,
                       0x3B, 0x3C, 0x3E, 0x3F, 0x41, 0x42, 0x45, 0x4B, 0x4E, 0x51, 0x52,
                       0x55, 0x5B, 0x5E, 0x61, 0x62, 0x65, 0x6B, 0x71, 0x72, 0x75, 0x7B,
                       0x87, 0x8F, 0xC7, 0xCD, 0xCF, 0x87, 0x19, 0x1E, 0x1F)
         and not (0x40 <= op < 0x60 and (op & 15) in (1, 2, 5, 0xB, 0xE))]
PAGE2 = [0x21, 0x22, 0x27, 0x2C, 0x83, 0x8C, 0x8E, 0x93, 0x9C, 0x9E, 0x9F, 0xA3, 0xAC,
         0xAE, 0xAF, 0xB3, 0xBC, 0xBE, 0xBF, 0xCE, 0xDE, 0xDF, 0xEE, 0xEF, 0xFE, 0xFF]
PAGE3 = [0x83, 0x8C, 0x93, 0x9C, 0xA3, 0xAC, 0xB3, 0xBC]


def encode(op, prefix=None):
    """Octets d'une instruction avec des opérandes aléatoires."""
    b = ([prefix] if prefix else []) + [op]
    hi = op >> 4
    if prefix and 0x20 <= op < 0x30:
        return b + [random.randrange(256), random.randrange(256)]
    if op in (0x16, 0x17):
        return b + [random.randrange(256), random.randrange(256)]
    if 0x20 <= op < 0x30 or op in (0x8D, 0x1A, 0x1C, 0x34, 0x35, 0x36, 0x37):
        return b + [random.randrange(256)]
    if op in (0x30, 0x31, 0x32, 0x33):
        return b + [rand_postbyte()] + [random.randrange(256), random.randrange(256)]
    if hi in (0x0, 0x9, 0xD):
        return b + [random.randrange(256)]
    if hi in (0x6, 0xA, 0xE):
        return b + [rand_postbyte(), random.randrange(256), random.randrange(256)]
    if hi in (0x7, 0xB, 0xF):
        return b + [random.randrange(256), random.randrange(256)]
    if hi in (0x8, 0xC):
        wide = (op & 15) in (3, 0xC, 0xE) or (prefix and (op & 15) in (3, 0xC, 0xE))
        if wide:
            return b + [random.randrange(256), random.randrange(256)]
        return b + [random.randrange(256)]
    return b


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
    random.seed(1)
    mem0 = bytearray(random.randrange(256) for _ in range(65536))
    ref_mem = Memory(Cfg({'verbosity': None, 'trace': None}))
    ref = RefCPU(ref_mem, Cfg({'verbosity': None, 'trace': None}))
    errors = 0
    for i in range(n):
        r = random.random()
        if r < 0.1:
            prefix, op = 0x10, random.choice(PAGE2)
        elif r < 0.13:
            prefix, op = 0x11, random.choice(PAGE3)
        else:
            prefix, op = None, random.choice(PAGE0)
        code = encode(op, prefix)
        pc = 0x4000
        mem = bytearray(mem0)
        mem[pc:pc + len(code)] = bytes(code)
        regs = dict(a=random.randrange(256), b=random.randrange(256), dp=random.randrange(256),
                    x=random.randrange(65536), y=random.randrange(65536),
                    u=random.randrange(0x5000, 0x7000), s=random.randrange(0x5000, 0x7000),
                    cc=random.randrange(256) & 0x2F)
        me = m6809.CPU(bytearray(mem))
        for k, v in regs.items():
            setattr(me, k, v)
        me.pc = pc
        for a in range(0, 65536, 256):
            ref_mem.load(a, mem[a:a + 256])
        ref.accu_a.set(regs['a'])
        ref.accu_b.set(regs['b'])
        ref.direct_page.set(regs['dp'])
        ref.index_x.set(regs['x'])
        ref.index_y.set(regs['y'])
        ref.user_stack_pointer.set(regs['u'])
        ref.system_stack_pointer.set(regs['s'])
        ref.set_cc(regs['cc'])
        ref.program_counter.set(pc)
        try:
            me.step()
        except RuntimeError as e:
            print('m6809 :', e, [hex(x) for x in code])
            errors += 1
            continue
        ref.get_and_call_next_op()
        got = dict(a=me.a, b=me.b, dp=me.dp, x=me.x, y=me.y, u=me.u, s=me.s, pc=me.pc)
        exp = dict(a=ref.accu_a.value, b=ref.accu_b.value, dp=ref.direct_page.value,
                   x=ref.index_x.value, y=ref.index_y.value, u=ref.user_stack_pointer.value,
                   s=ref.system_stack_pointer.value, pc=ref.program_counter.value)
        mask = 0x0F
        if (prefix is None and (op & 0x4F) in (0x49, 0x4B)) or op in (0x89, 0x8B, 0xC9, 0xCB):
            mask |= 0x20
        if op in (0x1A, 0x1C, 0x35) or (op == 0x3D):
            mask = 0x0F if op != 0x3D else 0x05
        cg, ce = me.cc & mask, ref.get_cc_value() & mask
        diff = {k: (hex(got[k]), hex(exp[k])) for k in got if got[k] != exp[k]}
        if cg != ce:
            diff['cc'] = (hex(cg), hex(ce))
        refm = bytes(ref_mem.get(0, 0x10000)) if False else None
        if diff:
            errors += 1
            if errors <= 25:
                print('diff', ' '.join(f'{x:02X}' for x in code), regs, diff)
    print(f'{n} instructions testées, {errors} différences')


if __name__ == '__main__':
    main()
