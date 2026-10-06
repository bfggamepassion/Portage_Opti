"""Socle commun des outils : configuration du portage, ROM, jeu d'instructions SM83.

La configuration est un fichier Python (port_config.py à la racine du projet,
ou le chemin donné par la variable d'environnement GB2ZX_CONFIG). Les chemins
qu'elle contient sont relatifs au dossier de ce fichier.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'mgbdis'))
from instruction_set import instructions, cb_instructions  # noqa: E402,F401


def _load_config():
    path = os.environ.get('GB2ZX_CONFIG', os.path.join(HERE, '..', 'port_config.py'))
    path = os.path.abspath(path)
    if not os.path.exists(path):
        sys.exit(f'configuration introuvable : {path} (copier port_config.py ou définir GB2ZX_CONFIG)')
    spec = importlib.util.spec_from_file_location('port_config', path)
    cfg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cfg)
    cfg.ROOT = os.path.dirname(path)
    return cfg


CFG = _load_config()


def path(p):
    """Chemin de la configuration -> chemin absolu."""
    return p if os.path.isabs(p) else os.path.join(CFG.ROOT, p)


ROM = open(path(CFG.ROM), 'rb').read()

# Conventions RST du jeu (voir port_config.py)
RST_JUMPTABLE = dict(getattr(CFG, 'RST_JUMPTABLE', {}))       # opcode -> routine Z80
RST_INLINE_DATA = dict(getattr(CFG, 'RST_INLINE_DATA', {}))   # opcode -> routine Z80
TABLE_LEN = dict(getattr(CFG, 'TABLE_LEN', {}))

JUMPS16 = (0xC3, 0xCA, 0xC2, 0xDA, 0xD2, 0xCD, 0xC4, 0xCC, 0xD4, 0xDC)
JUMPS8 = (0x18, 0x20, 0x28, 0x30, 0x38)
ENDS = (0xC3, 0x18, 0xC9, 0xD9)                  # fin inconditionnelle du flot


def length(op):
    """Longueur en octets de l'instruction SM83 d'opcode op."""
    if op == 0xCB:
        return 2
    m = instructions[op]
    if 'd16' in m or 'a16' in m:
        return 3
    if 'd8' in m or 'r8' in m or 'a8' in m:
        return 2
    return 1


def w(a):
    return ROM[a] | (ROM[a + 1] << 8)


def jr_target(pc):
    r = ROM[pc + 1]
    return pc + 2 + (r - 256 if r > 127 else r)


def inline_len(pc):
    """rst à données en ligne en pc : nombre d'octets de données après l'opcode
    (format « db N puis N octets » ; adapter ici si le jeu en utilise un autre)."""
    return 1 + ROM[pc + 1]
