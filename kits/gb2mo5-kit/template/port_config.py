"""Configuration du portage : Tennis (Game Boy, Nintendo 1989) -> Thomson MO5.

Le MO5 a un 6809 : la logique est traduite par tools/gb2m6809.py.
- Registres GB B C D E H L en page directe ($9F00-$9F05, paires dans l'ordre
  du 6809 : octet haut d'abord) ; A du GB = A du 6809.
- RAM GB déplacée (RAM_MAP) : $C000-$C0FF -> $9D00, $DD00 -> $9E00,
  HRAM $FF80-$FFFE -> $9F80 (page directe, DP = $9F).
Vérifié pas à pas contre le jeu GB (tools/diff_mo5.py).
Les chemins sont relatifs au dossier de ce fichier.
"""

# --- Fichiers ------------------------------------------------------------------
ROM = 're/game.gb'                 # ROM GB (32 Ko, sans mapper)
SYM_OUT = 'build/tennis_gb.sym'                  # gb_trace.py -> blocs pour mgbdis
LOGIC_OUT = 'gb/gb_logic.asm'                 # gb2z80.py -> logique traduite



def RAM_MAP(a):
    """Adresse GB -> adresse MO5 (None : pas de la RAM déplacée)."""
    if 0xC000 <= a < 0xC100:
        return a - 0xC000 + 0x9D00
    if 0xFF80 <= a <= 0xFFFF:
        return a - 0xFF00 + 0x9F00
    if 0xDD00 <= a < 0xDE00:
        return a - 0xDD00 + 0x9E00
    return None


# --- Conventions RST du jeu (lues dans le désassemblage, $0000-$003F) ------------
# rst $08 : saut indexé par A, table de DW juste après l'appel
RST_JUMPTABLE = {0xCF: 'G_RST08'}
# rst $18 : lecture indexée, rst $28 : copie vers [DE] ; après l'appel : db N + N octets
RST_INLINE_DATA = {0xDF: 'G_RST18', 0xEF: 'G_RST28'}
# Tables de sauts dont la fin ne se devine pas (adresse de la table -> entrées)
TABLE_LEN = {0x19E3: 3, 0x1A34: 3}

# --- Traceur (gb_trace.py) : point d'entrée et vecteurs d'interruption ------------
TRACE_ENTRIES = [0x0100, 0x0040, 0x0048, 0x0050, 0x0058, 0x0060,
                 0x19E9, 0x1A3A]      # adresses de retour empilées en $19AC (trouvées à la main)

# --- Logique à traduire ----------------------------------------------------------
# Racines : routines appelées par la boucle principale pendant le jeu
ROOTS = {
    0x1F8E: 'déroulement du match',
    0x0B7D: 'joueur 1',
    0x10ED: 'joueur 2',
    0x17A0: 'balle',
    0x2720: 'IA joueur 2',
    0x0A9D: 'fiche de niveau',
    0x3297: 'remise à zéro du match',
    0x2159: 'nouveau jeu',
}
# Projection de l'affichage ($095D, $0951, $09C2) : réécrite en Z80 natif
# (src/proj.asm). REF_PROJ=1 ajoute la version traduite, pour
# tools/test_proj.py qui compare les deux.
import os as _os
if _os.environ.get('REF_PROJ'):
    ROOTS.update({0x095D: 'projection', 0x0951: 'projection de la marque', 0x09C2: 'hauteur de la balle'})
# Indicateurs écrits / lus par les routines écrites à la main (FZ = 1, FC = 2)
STUB_FLAGS = {'S_SOUND': (0, 0), 'S_RET': (0, 0)}
# Indicateurs écrits par les routines RST : rst $08 (add a, add hl,de) Z et C,
# rst $18 (add hl,bc) C, rst $28 (dec b) Z
RST_FLAG_DEFS = {'G_RST08': 3, 'G_RST18': 2, 'G_RST28': 1}
# Adresses non suivies. Avec un nom : routine Spectrum appelée à la place.
# Avec None : ne doit pas être appelée depuis la logique (sinon ATTENTION).
STUBS = {
    0x3665: 'S_SOUND',        # jouer le son A
    0x3670: None,             # son (autre point d'entrée)
    0x1F6B: 'S_RET',          # vérification de la musique
    0x016D: 'S_SCREEN',       # changement d'écran ($FF8A)
    0x0150: None,             # reset
    0x227C: 'S_RET',          # sortie du mode démo
    0x2FDB: None, 0x2FED: None, 0x0837: None,   # câble link
}
# Immédiats 16 bits qui sont des adresses de code (ex. adresses de retour empilées)
CODE_PTRS = [0x19E9, 0x1A3A]
# Immédiats 16 bits qui sont des adresses de données (-> étiquettes D_xxxx)
DATA_PTRS = [0x0B35]
# Données recopiées : table de pointeurs des fiches de niveau, puis les fiches
DATA_BLOCKS = [(0x0B35, 0x0B3D, 'dw'), (0x0B3D, 0x0B7D, 'db')]
# Réglages volontaires : instruction GB remplacée par du code 6809
PATCHES = {
    0x10A6: 'jmp S_P1SHOT',    # coups croisés / longs du joueur 1 atténués de 10 %
}

# --- Comparaison pas à pas (diff_gb.py) -------------------------------------------
TAP = '../../../asm/build/tennis.tap'
SYM = '../../../asm/build/tennis.sym'         # table des symboles sjasmplus
TICK_SYMBOL = 'gb_tick'                       # un pas de logique, appelable seul
REGIONS = [(0xC000, 0xC100), (0xDD00, 0xDE00), (0xFF80, 0xFFFF)]   # RAM GB recopiée
# Adresses comparées : RAM de la logique (hors tampon de texte $C0C0-$C0DA)
# et variables HRAM de la logique (hors joypad, hasard, affichage)
COMPARE = (list(range(0xC000, 0xC0C0)) + list(range(0xC0DB, 0xC100)) +
           [0xFF90, 0xFF91, 0xFF92, 0xFF93, 0xFF95, 0xFF96, 0xFFAD, 0xFFAE,
            0xFFB0, 0xFFB1, 0xFFB2, 0xFFB3, 0xFFB4, 0xFFB5, 0xFFB6, 0xFFB7, 0xFFB8, 0xFFB9,
            0xFFC2, 0xFFC4])
MASK = {0xFFC2: 0x7F}                         # bit 7 : géré par l'affichage GB


def gb_start(pb, press):
    """Mène le jeu GB (PyBoy) jusqu'au début de la partie."""
    for _ in range(120):
        pb.tick()
    press('start')            # titre -> sélection du niveau
    press('start')            # niveau 1 -> match


def gb_in_play(mem):
    """Vrai pendant le jeu proprement dit (hors écrans, démo)."""
    return mem[0xFF8B] == 1 and mem[0xFFA5] == 0


def gb_logic_ran(before, after):
    """Vrai si le GB a exécuté un pas de logique entre deux trames
    (faux sur les changements d'écran, qui ne passent pas par la logique)."""
    return before[0xFF8A] == after[0xFF8A] == 3


# --- Robot joueur 1 (zxrun.py --bot, diff_gb.py) ------------------------------------
class Bot:
    """Joue le joueur 1 en lisant la RAM GB ($C000...). Renvoie des touches
    Spectrum (Q A O P SPACE), converties en boutons GB pour PyBoy."""
    GB_BUTTONS = {'SPACE': 'a', 'Q': 'up', 'A': 'down', 'O': 'left', 'P': 'right'}

    def __init__(self):
        self.swing_cool = 0
        self.serve_t = 0

    def keys(self, mem, f):
        rd = lambda o: mem[0xC000 + o]  # noqa: E731
        p_state = rd(0x00)
        px, py = rd(0x05), rd(0x03)
        b_state = rd(0x40)
        bx, by, bz = rd(0x45), rd(0x43), rd(0x47)
        keys = []
        if self.swing_cool:
            self.swing_cool -= 1
        if p_state == 5:                                  # service
            self.serve_t += 1
            if self.serve_t == 20:
                keys.append('SPACE')
            return keys
        if p_state == 6:                                  # balle lancée
            if (rd(0x52) & 0x80) and bz < 0x50 and self.swing_cool == 0:
                keys.append('SPACE')
                self.swing_cool = 10
            return keys
        self.serve_t = 0
        if b_state in (3, 4) and not (rd(0x4F) & 0x80) and by >= 0x60:
            target = (bx - 10) & 0xFF                     # se placer pour un coup droit
            if px < target - 2:
                keys.append('P')
            elif px > target + 2:
                keys.append('O')
            if 0 < py - by < 16 and self.swing_cool == 0 and p_state == 1:
                keys.append('SPACE')
                self.swing_cool = 12
        elif p_state == 1:                                # revenir au centre, au fond
            if px < 0x68:
                keys.append('P')
            elif px > 0x70:
                keys.append('O')
            if py > 0xBA:
                keys.append('Q')
        return keys
