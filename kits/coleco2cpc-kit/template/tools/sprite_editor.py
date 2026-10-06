"""Éditeur des sprites en mode 0 : ouvre une page dans le navigateur pour
redessiner les motifs (en pixels CPC), les enregistrer dans
gfx/sprites_cpc.json, compiler (build.sh) et lancer le jeu dans Caprice32.

  python tools/sprite_editor.py        (ou editeur_sprites.bat)

Le serveur n'écoute que sur cet ordinateur (127.0.0.1). Ctrl+C pour l'arrêter.
"""
import json
import os
import shutil
import subprocess
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
import cpcpal  # noqa: E402
import port_config  # noqa: E402
import sprite_fix  # noqa: E402

PORT = 8765
ROM = os.path.join(ROOT, 're', port_config.GAME + '.col')
DSK = os.path.join(ROOT, 'build', port_config.GAME + '.dsk')
CAP32 = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Caprice32', 'cap32-win64', 'cap32.exe')

# Poses du personnage relevées dans le jeu original (exemple de Cabbage Patch
# Kids : Anna Lee tournée à droite ; à relever avec cvrun pour un autre jeu). Calques
# du premier plan au fond : [motif n, couleur TMS, dx, dy].
PRESETS = [
    ('Debout', [[0xD4, 1, 8, 32], [0x00, 8, 8, 0], [0x04, 11, 8, 0], [0x24, 13, 5, 16], [0x28, 11, 5, 16], [0x08, 8, 0, 0]]),
    ('Marche 1', [[0xD4, 1, 8, 32], [0x00, 8, 8, 0], [0x04, 11, 8, 0], [0x0C, 13, 5, 16], [0x10, 11, 5, 16], [0x08, 8, 0, 0]]),
    ('Marche 2', [[0xD4, 1, 8, 32], [0x00, 8, 8, 0], [0x04, 11, 8, 0], [0x14, 13, 5, 16], [0x18, 11, 5, 16], [0x08, 8, 0, 0]]),
    ('Marche 3', [[0xD4, 1, 8, 32], [0x00, 8, 8, 0], [0x04, 11, 8, 0], [0x1C, 13, 5, 16], [0x20, 11, 5, 16], [0x08, 8, 0, 0]]),
    ('Marche 4', [[0xD4, 1, 8, 32], [0x00, 8, 8, 0], [0x04, 11, 8, 0], [0x2C, 13, 8, 16], [0x30, 11, 8, 16], [0x08, 8, 0, 0]]),
    ('Étourdie', [[0xD4, 1, 8, 32], [0x3C, 8, 8, 0], [0x04, 11, 8, 0], [0x24, 13, 5, 16], [0x28, 11, 5, 16], [0x08, 8, 0, 0]]),
]


def bash_path():
    for p in (r'C:\Program Files\Git\bin\bash.exe', r'C:\Program Files (x86)\Git\bin\bash.exe'):
        if os.path.exists(p):
            return p
    p = shutil.which('bash')
    if p and 'system32' not in p.lower():       # pas le bash de WSL
        return p
    return None


def data():
    rom = open(ROM, 'rb').read()
    fix = sprite_fix.load()
    pats = []
    for k in range(sprite_fix.BLOCK_COUNT):
        off = sprite_fix.BLOCK_ADDR - 0x8000 + 32 * k
        rows = [(rom[off + y] << 8) | rom[off + 16 + y] for y in range(16)]
        pats.append({'addr': '%04X' % (0x8000 + off), 'n': sprite_fix.block_n(k),
                     'orig': rows, 'fix': fix.get(off)})
    return {'patterns': pats, 'presets': PRESETS,
            'palette': ['#%02x%02x%02x' % cpcpal.rgb(i) for i in range(16)],
            'dsk': DSK}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype='application/json'):
        b = body.encode('utf-8') if isinstance(body, str) else body
        self.send_response(code)
        self.send_header('Content-Type', ctype + '; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path in ('/', '/index.html'):
            self.send(200, open(os.path.join(HERE, 'sprite_editor.html'), 'rb').read(), 'text/html')
        elif self.path == '/api/data':
            self.send(200, json.dumps(data()))
        else:
            self.send(404, '{}')

    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(n) or b'{}')
        if self.path == '/api/save':
            fix = {}
            for a, rows in body.get('fixes', {}).items():
                a = int(a, 16)
                ok = (sprite_fix.BLOCK_ADDR <= a < sprite_fix.BLOCK_ADDR + 32 * sprite_fix.BLOCK_COUNT
                      and (a - sprite_fix.BLOCK_ADDR) % 32 == 0 and len(rows) == 16
                      and all(len(r) == 8 and set(r) <= {'#', '.'} for r in rows))
                if not ok:
                    return self.send(400, json.dumps({'ok': False, 'log': f'motif invalide ${a:04X}'}))
                fix[a] = rows
            sprite_fix.save(fix)
            self.send(200, json.dumps({'ok': True, 'log': f'{len(fix)} motif(s) enregistré(s) dans gfx/sprites_cpc.json'}))
        elif self.path == '/api/build':
            bash = bash_path()
            if not bash:
                return self.send(200, json.dumps({'ok': False, 'log': 'Git Bash introuvable (C:\\Program Files\\Git\\bin\\bash.exe)'}))
            r = subprocess.run([bash, 'build.sh'], cwd=ROOT, capture_output=True, text=True,
                               encoding='utf-8', errors='replace')
            log = (r.stdout + r.stderr).strip()
            self.send(200, json.dumps({'ok': r.returncode == 0, 'log': log[-3000:]}))
        elif self.path == '/api/run':
            if not os.path.exists(CAP32):
                return self.send(200, json.dumps({'ok': False, 'log': 'Caprice32 introuvable : ' + CAP32}))
            subprocess.Popen([CAP32, '-O', 'system.model=2', '-a', 'run"' + port_config.GAME + '\n', DSK],
                             cwd=os.path.dirname(CAP32))
            self.send(200, json.dumps({'ok': True, 'log': 'Caprice32 lancé'}))
        else:
            self.send(404, '{}')


def main():
    srv = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    url = f'http://127.0.0.1:{PORT}/'
    print(f'Éditeur de sprites : {url}  (Ctrl+C pour arrêter)')
    if '--no-browser' not in sys.argv:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
