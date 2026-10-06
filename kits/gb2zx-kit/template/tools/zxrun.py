"""Exécute un .tap ZX Spectrum 48K sans fenêtre et capture l'écran.

Usage :
  python tools/zxrun.py build/tennis.tap --frames 300 --out build/run \
      --keys "50-120:P,SPACE" --kempston "130-200:RIGHT,FIRE" --every 25 --gif

- Chargement réaliste : tap2sna --sim-load (le BASIC charge le code machine).
- Les entrées sont scriptées par plages de trames (trame 0 = fin du chargement).
- Sorties : PNG toutes les N trames, dernière image, GIF animé optionnel.
"""
import argparse
import os
import subprocess
import sys

from PIL import Image
from skoolkit import CSimulator, CCMIOSimulator
from skoolkit.simulator import Simulator
from skoolkit.simutils import from_snapshot
from skoolkit.snapshot import Snapshot

KEYMAP = [
    ['CAPS', 'Z', 'X', 'C', 'V'],
    ['A', 'S', 'D', 'F', 'G'],
    ['Q', 'W', 'E', 'R', 'T'],
    ['1', '2', '3', '4', '5'],
    ['0', '9', '8', '7', '6'],
    ['P', 'O', 'I', 'U', 'Y'],
    ['ENTER', 'L', 'K', 'J', 'H'],
    ['SPACE', 'SYM', 'M', 'N', 'B'],
]
KEYPOS = {k: (row, bit) for row, keys in enumerate(KEYMAP) for bit, k in enumerate(keys)}
KEMPSTON = {'RIGHT': 1, 'LEFT': 2, 'DOWN': 4, 'UP': 8, 'FIRE': 16, 'FIRE2': 32}

# Palette Spectrum (normal, bright)
COLOURS = [
    [(0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205), (0, 205, 0), (0, 205, 205), (205, 205, 0), (205, 205, 205)],
    [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255), (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)],
]


def parse_script(specs, table):
    events = []
    for spec in specs or []:
        rng, names = spec.split(':')
        a, _, b = rng.partition('-')
        a = int(a)
        b = int(b) if b else a
        events.append((a, b, [n.strip().upper() for n in names.split(',')]))
    for _, _, names in events:
        for n in names:
            if n not in table:
                sys.exit(f'touche inconnue : {n}')
    return events


def screen_to_image(scr, border, flash_phase=False):
    img = Image.new('RGB', (256 + 32, 192 + 32), COLOURS[0][border])
    px = img.load()
    for y in range(192):
        row = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        for cx in range(32):
            byte = scr[row + cx]
            attr = scr[6144 + (y >> 3) * 32 + cx]
            ink, paper = attr & 7, (attr >> 3) & 7
            if attr & 0x80 and flash_phase:
                ink, paper = paper, ink
            pal = COLOURS[(attr >> 6) & 1]
            for b in range(8):
                px[16 + cx * 8 + b, 16 + y] = pal[ink] if byte & (0x80 >> b) else pal[paper]
    return img


class Tracer:
    def __init__(self):
        self.keyboard = [0] * 8
        self.kempston = 0
        self.border = 7
        self.t_start = None
        self.colour_spans = {}
        self.prof_ignore = 4

    def read_port(self, registers, port):
        if port & 0xFF == 0x1F:
            return self.kempston
        if port % 2 == 0:
            h = (port >> 8) ^ 0xFF
            v = 0
            for i in range(8):
                if h & (1 << i):
                    v |= self.keyboard[i]
            return (v ^ 0xFF) & 0xBF | 0xA0
        return 0xFF

    def write_port(self, registers, port, value, offset=0):
        if port % 2 == 0:
            # profilage : durée passée dans chaque couleur de bordure (sauf la couleur normale)
            v = value & 7
            if v != self.border:
                if self.border != self.prof_ignore and self.t_start is not None:
                    self.colour_spans.setdefault(self.border, []).append(registers[25] - self.t_start)
                self.t_start = registers[25]
            self.border = v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tap')
    ap.add_argument('--frames', type=int, default=200)
    ap.add_argument('--out', default='build/run')
    ap.add_argument('--keys', action='append', help='trames:TOUCHE,TOUCHE (ex. 10-50:P,SPACE)')
    ap.add_argument('--kempston', action='append', help='trames:DIR,FIRE (ex. 10-50:LEFT,FIRE)')
    ap.add_argument('--every', type=int, default=0, help='PNG toutes les N trames')
    ap.add_argument('--gif', action='store_true')
    ap.add_argument('--gif-step', type=int, default=2)
    ap.add_argument('--gif-from', type=int, default=0, help='première trame du GIF')
    ap.add_argument('--scale', type=int, default=2)
    ap.add_argument('--sheet', type=int, default=0, help='planche contact : une image toutes les N trames')
    ap.add_argument('--cmio', action='store_true',
                    help='simule la contention mémoire et E/S (comme un vrai Spectrum 48K)')
    ap.add_argument('--bot', action='store_true', help='robot joueur (classe Bot de port_config.py)')
    ap.add_argument('--bot-start', type=int, default=0, help='trame de démarrage du robot')
    ap.add_argument('--prof-ignore', type=int, default=4, help='couleur de bordure normale (non profilée)')
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    z80 = os.path.join(args.out, 'loaded.z80')
    if not os.path.exists(z80) or os.path.getmtime(z80) < os.path.getmtime(args.tap):
        if os.path.exists(z80):
            os.remove(z80)
        subprocess.run([sys.executable, _script('tap2sna.py'), args.tap, z80],
                       check=True, stdout=subprocess.DEVNULL)

    snap = Snapshot.get(z80)
    sim = from_snapshot((CCMIOSimulator if args.cmio else CSimulator) or Simulator, snap)
    tracer = Tracer()
    tracer.prof_ignore = args.prof_ignore
    sim.set_tracer(tracer)
    keys = parse_script(args.keys, KEYPOS)
    kemp = parse_script(args.kempston, KEMPSTON)

    frames = []
    sheet = []
    bot = None
    if args.bot:
        from gbrom import CFG
        bot = CFG.Bot()
    frame_t = sim.frame_duration
    regs = sim.registers
    t0 = regs[25]
    for f in range(args.frames):
        tracer.keyboard = [0] * 8
        tracer.kempston = 0
        for a, b, names in keys:
            if a <= f <= b:
                for n in names:
                    row, bit = KEYPOS[n]
                    tracer.keyboard[row] |= 1 << bit
        for a, b, names in kemp:
            if a <= f <= b:
                for n in names:
                    tracer.kempston |= KEMPSTON[n]
        if bot and f >= args.bot_start:
            for n in bot.keys(sim.memory, f):
                row, bit = KEYPOS[n]
                tracer.keyboard[row] |= 1 << bit
        _run_frame(sim, t0 + (f + 1) * frame_t)
        scr = bytes(sim.memory[16384:23296])
        want_png = args.every and f % args.every == 0
        want_gif = args.gif and f >= args.gif_from and f % args.gif_step == 0
        want_sheet = args.sheet and f % args.sheet == 0
        if want_png or want_gif or want_sheet or f == args.frames - 1:
            img = screen_to_image(scr, tracer.border, (f // 16) % 2 == 1)
            if want_png:
                img.resize((img.width * args.scale, img.height * args.scale), Image.NEAREST).save(
                    os.path.join(args.out, f'frame_{f:05d}.png'))
            if want_gif:
                frames.append(img)
            if want_sheet:
                sheet.append((f, img))
            if f == args.frames - 1:
                img.resize((img.width * args.scale, img.height * args.scale), Image.NEAREST).save(
                    os.path.join(args.out, 'last.png'))
    if sheet:
        from PIL import ImageDraw
        cols = 4
        rows = (len(sheet) + cols - 1) // cols
        w, h = sheet[0][1].size
        planche = Image.new('RGB', (cols * w, rows * h), (40, 40, 40))
        for i, (f, img) in enumerate(sheet):
            planche.paste(img, ((i % cols) * w, (i // cols) * h))
            ImageDraw.Draw(planche).text(((i % cols) * w + 2, (i // cols) * h + 2), f't{f}', fill=(255, 255, 0))
        planche.save(os.path.join(args.out, 'planche.png'))
    if frames:
        frames[0].save(os.path.join(args.out, 'run.gif'), save_all=True, append_images=frames[1:],
                       duration=20 * args.gif_step, loop=0)
    for col, sp in sorted(tracer.colour_spans.items()):
        print(f'profil bordure {col} : {len(sp)} mesures, moy {sum(sp)//len(sp)} T, max {max(sp)} T '
              f'(trame = {frame_t} T)')
    print(f'{args.frames} trames exécutées, sortie dans {args.out}')


def _script(name):
    for d in os.environ.get('PATH', '').split(os.pathsep) + [
            os.path.join(os.environ.get('APPDATA', ''), 'Python', f'Python{sys.version_info[0]}{sys.version_info[1]}', 'Scripts')]:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    sys.exit(f'{name} introuvable (pip install skoolkit)')


def _run_frame(sim, t_end):
    """Exécute jusqu'à la T-state t_end, interruptions actives."""
    sim.trace(sim.registers[24], -1, 0, t_end, True, None, None, None, None, None)


if __name__ == '__main__':
    main()
