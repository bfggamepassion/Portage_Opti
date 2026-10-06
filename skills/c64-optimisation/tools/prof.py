"""Profile a VICE `chis` execution trace (see vicemon.Vice.history).

  prof.py trace.chis            executed code blocks, cycles spent in each, share of the total
  prof.py trace.chis subs       cycles per subroutine (inclusive), call counts
  prof.py trace.chis irq        every interrupt entry: raster line-ish timing, handler, duration
  prof.py trace.chis io         every write to $D000-$DFFF with the cycle offset inside the frame
"""
import sys, re

LINE = re.compile(rb"\.C:([0-9a-f]{4})  ((?:[0-9A-F]{2} )+)\s*(\S+)(?: (\S+))?\s+A:(..) X:(..) Y:(..) SP:(..) \S+\s+(\d+)")


def parse(path):
    out = []
    for m in LINE.finditer(open(path, 'rb').read()):
        out.append((int(m.group(1), 16), m.group(3).decode(), (m.group(4) or b'').decode(),
                    int(m.group(5), 16), int(m.group(6), 16), int(m.group(7), 16), int(m.group(8), 16),
                    int(m.group(9)), len(m.group(2).split())))
    return out


def blocks(tr, gap=8):
    """Contiguous executed address ranges -> (start, end, cycles, instruction count)."""
    cyc = {}
    cnt = {}
    for i in range(len(tr) - 1):
        pc = tr[i][0]
        cyc[pc] = cyc.get(pc, 0) + tr[i + 1][7] - tr[i][7]
        cnt[pc] = cnt.get(pc, 0) + 1
    out = []
    s = e = None
    c = n = 0
    for a in sorted(cyc):
        if s is None or a > e + gap:
            if s is not None:
                out.append((s, e, c, n))
            s, c, n = a, 0, 0
        e = a
        c += cyc[a]
        n += cnt[a]
    out.append((s, e, c, n))
    return out


def irqs(tr):
    """Interrupt entries: PC changes to a non-sequential address while the previous opcode was not a jump
    and SP dropped by 3."""
    out = []
    for i in range(1, len(tr)):
        p, c = tr[i - 1], tr[i]
        if ((p[6] - c[6]) & 0xff) == 3 and p[1] not in ('JSR', 'BRK') and c[0] != p[0] + p[8]:
            # find matching RTI
            j = i
            while j < len(tr) and not (tr[j][1] == 'RTI' and tr[j][6] == c[6]):
                j += 1
            out.append((c[7], c[0], (tr[j][7] - c[7] + 6) if j < len(tr) else None, p[0]))
    return out


def subs(tr):
    """Inclusive cycles per JSR target."""
    stack = []
    tot = {}
    calls = {}
    for i in range(len(tr) - 1):
        pc, mn, arg, a, x, y, sp, clk, n = tr[i]
        if mn == 'JSR':
            stack.append((int(arg[1:], 16), clk, sp))
        elif mn == 'RTS' and stack:
            while stack and stack[-1][2] != ((sp + 2) & 0xff) and len(stack) > 0 and stack[-1][2] < sp:
                stack.pop()
            if stack:
                t, c0, _ = stack.pop()
                tot[t] = tot.get(t, 0) + tr[i + 1][7] - c0
                calls[t] = calls.get(t, 0) + 1
    return tot, calls


if __name__ == '__main__':
    tr = parse(sys.argv[1])
    mode = sys.argv[2] if len(sys.argv) > 2 else 'blocks'
    total = tr[-1][7] - tr[0][7]
    print("%d instructions, %d cycles (%.1f PAL frames)" % (len(tr), total, total / 19656))
    if mode == 'blocks':
        for s, e, c, n in sorted(blocks(tr), key=lambda b: -b[2]):
            if c * 1000 >= total:
                print("  %04X-%04X  %7d cyc  %5.1f%%  %6d instr" % (s, e, c, 100 * c / total, n))
    elif mode == 'subs':
        tot, calls = subs(tr)
        for t in sorted(tot, key=lambda t: -tot[t])[:60]:
            print("  JSR %04X  %7d cyc  %5.1f%%  %5d calls  %6.0f cyc/call" % (
                t, tot[t], 100 * tot[t] / total, calls[t], tot[t] / calls[t]))
    elif mode == 'irq':
        prev = None
        for clk, h, d, frm in irqs(tr):
            print("  +%6s cyc  handler %04X  %s cyc  (interrupted %04X)" % (
                '' if prev is None else clk - prev, h, d, frm))
            prev = clk
    elif mode == 'io':
        for pc, mn, arg, a, x, y, sp, clk, n in tr:
            if mn in ('STA', 'STX', 'STY', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR') and arg.startswith('$D') and len(arg) >= 5:
                v = {'STA': a, 'STX': x, 'STY': y}.get(mn)
                print("  %9d  %04X  %s %s  %s" % (clk, pc, mn, arg, '' if v is None else '%02X' % v))
