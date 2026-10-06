"""Temps du rendu par routine (NOPs par image affichée) : python tools/rprof.py [décor ...]"""
import collections
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import portsim  # noqa: E402
import budget  # noqa: E402

RANGES = [('grab', 'chg_add'), ('chg_add', 'collect_pats'), ('collect_pats', 'vram_pass'), ('vram_pass', 'retile'),
          ('retile', 'respr'), ('respr', 'draw_cells'), ('draw_cells', 'draw_cell'), ('draw_cell', 'draw_sprites'),
          ('draw_sprites', 'draw_sprite'), ('draw_sprite', 'spk1'), ('spk1', 'next_line'), ('next_line', 'spr_rect'),
          ('spr_rect', 'flip_req'), ('flip_req', 'flip_wait')]
for lvl in [int(x) for x in sys.argv[1:]] or [3, 1]:
    sym = portsim.symbols()
    c, keys = portsim.cpc_level(lvl, '960:J0R' if budget.WALK.get(lvl, True) else '')
    c.run_frames(300, keys)
    rs = [(sym[a], sym[b], a) for a, b in RANGES]
    t = collections.Counter()
    n = [0]

    def prof(pc, us):
        if pc >= 0x4000 or c.map[0] != 0:
            return
        if pc == sym['flip_wait']:
            n[0] += 1
        for a, b, name in rs:
            if a <= pc < b:
                t[name] += us
                break
    c.run_frames(150, keys, prof=prof)
    print(f'décor {lvl} :', ', '.join(f'{k} {v / n[0]:.0f}' for k, v in t.most_common()))
