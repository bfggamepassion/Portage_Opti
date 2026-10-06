"""Configuration du portage vers l'Amstrad CPC (un fichier par jeu). Lu par tools/*.py.

Les valeurs se remplissent au fil de la rétro-ingénierie (voir PORTING.md).
Les chemins sont relatifs au dossier de ce fichier.
"""

# --- Fichiers ------------------------------------------------------------------
ROM = 're/game.gb'                            # ROM GB (32 Ko sans mapper pour gb_trace.py)
SYM_OUT = 're/game.sym'                       # gb_trace.py -> blocs code/données pour mgbdis
LOGIC_OUT = 'gb/gb_logic.asm'                 # gb2z80.py -> logique traduite (Z80, comme le Spectrum)

# --- Conventions RST du jeu : lire $0000-$003F dans le désassemblage ------------------
# opcode du rst -> routine Z80 (à écrire dans asm/src/gb_support.asm)
RST_JUMPTABLE = {}        # ex. {0xCF: 'G_RST08'} : rst $08 suivi d'une table de DW
RST_INLINE_DATA = {}      # ex. {0xDF: 'G_RST18'} : rst suivi de « db N » + N octets
TABLE_LEN = {}            # tables de sauts dont la fin ne se devine pas : {adresse: entrées}

# --- Traceur ------------------------------------------------------------------------
TRACE_ENTRIES = [0x0100, 0x0040, 0x0048, 0x0050, 0x0058, 0x0060]   # + cibles de « jp hl »

# --- Logique à traduire ---------------------------------------------------------------
ROOTS = {}                # {adresse: 'rôle'} : routines de logique appelées par la boucle principale
STUBS = {}                # {adresse: 'S_ROUTINE' ou None} : non suivies (son, VRAM, écrans...)
CODE_PTRS = []            # immédiats 16 bits qui sont des adresses de code
DATA_PTRS = []            # immédiats 16 bits qui sont des adresses de données
DATA_BLOCKS = []          # [(début, fin, 'dw' ou 'db')] : données de la ROM lues par la logique
DATA_LABELS = []          # étiquettes D_xxxx en plus, à l'intérieur des blocs 'db'
PATCHES = {}              # {adresse: 'code Z80'} : réglages volontaires (hors fidélité)

# --- Comparaison pas à pas (diff_gb.py) -----------------------------------------------
TAP = 'asm/build/game.tap'
SYM = 'asm/build/game.sym'
TICK_SYMBOL = 'gb_tick'
REGIONS = [(0xC000, 0xE000), (0xFF80, 0xFFFF)]     # RAM GB recopiée dans le Spectrum
COMPARE = list(range(0xC000, 0xC100))              # adresses comparées (logique seulement)
MASK = {}                                          # {adresse: bits comparés}


def gb_start(pb, press):
    """Mène le jeu GB (PyBoy) jusqu'au début de la partie : press('start')..."""
    for _ in range(120):
        pb.tick()
    press('start')


def gb_in_play(mem):
    """Vrai pendant le jeu proprement dit (variable d'état de la ROM)."""
    return True


def gb_logic_ran(before, after):
    """Vrai si le GB a exécuté un pas de logique entre deux trames."""
    return True


class Bot:
    """Robot joueur : lit la RAM GB, renvoie des touches Spectrum."""
    GB_BUTTONS = {'SPACE': 'a', 'Q': 'up', 'A': 'down', 'O': 'left', 'P': 'right'}

    def keys(self, mem, f):
        return []
