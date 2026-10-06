"""Minimal D64 reader: directory listing and file extraction (PRG/SEQ/USR)."""
import sys, os

SPT = [21]*17 + [19]*7 + [18]*6 + [17]*5  # sectors per track, tracks 1..35
OFF = [0]
for n in SPT: OFF.append(OFF[-1] + n*256)

def sec(img, t, s):
    o = OFF[t-1] + s*256
    return img[o:o+256]

def pet(b):
    return ''.join(chr(c) if 32 <= c < 127 else ('.' if c != 0xA0 else ' ') for c in b).rstrip()

def directory(img):
    t, s = 18, 1
    seen = set()
    out = []
    while t and (t, s) not in seen and t <= 35:
        seen.add((t, s))
        d = sec(img, t, s)
        for i in range(8):
            e = d[i*32:(i+1)*32]
            ft = e[2]
            if ft == 0: continue
            out.append(dict(type=ft, t=e[3], s=e[4], name=pet(e[5:21]), raw=bytes(e[5:21]),
                            blocks=e[30] | e[31] << 8))
        t, s = d[0], d[1]
    return out

def read_file(img, t, s):
    data = bytearray(); seen = set()
    while t and (t, s) not in seen and 1 <= t <= 35 and s < SPT[t-1]:
        seen.add((t, s))
        d = sec(img, t, s)
        if d[0] == 0:
            data += d[2:d[1]+1]; break
        data += d[2:]
        t, s = d[0], d[1]
    return bytes(data)

if __name__ == '__main__':
    path = sys.argv[1]
    img = open(path, 'rb').read()
    bam = sec(img, 18, 0)
    print(f"== {os.path.basename(path)}  disk name: '{pet(bam[0x90:0xA0])}' id '{pet(bam[0xA2:0xA7])}'")
    outdir = sys.argv[2] if len(sys.argv) > 2 else None
    if outdir: os.makedirs(outdir, exist_ok=True)
    for n, e in enumerate(directory(img)):
        kind = ['DEL','SEQ','PRG','USR','REL'][e['type'] & 7] if (e['type'] & 7) < 5 else '???'
        f = read_file(img, e['t'], e['s']) if e['t'] else b''
        la = f[0] | f[1] << 8 if len(f) > 1 else 0
        print(f"  {n:2d} {e['blocks']:4d} blk {kind} t{e['t']:2d}/s{e['s']:2d} '{e['name']}' len={len(f)} load=${la:04X}")
        if outdir and f:
            safe = ''.join(c if c.isalnum() else '_' for c in e['name']) or 'noname'
            open(os.path.join(outdir, f"{n:02d}_{safe}.prg"), 'wb').write(f)
