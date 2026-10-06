"""Réglages propres au jeu porté : tous les outils les lisent ici.

Les valeurs ci-dessous sont celles de Cabbage Patch Kids (le portage de
référence) : à remplacer pour un nouveau jeu, au fil du désassemblage.
"""

# Nom court : re/<GAME>.col (ROM), re/<GAME>.lst (listing), build/<GAME>.bin,
# .sym, .dsk ; sur la disquette : <DSK_NAME>.BIN, lancé par RUN"<GAME>".
GAME = 'game'
DSK_NAME = 'GAME'

# --- Désassembleur (tools/disasm.py) ------------------------------------------
# Points d'entrée connus : démarrage (mot en $800A de l'en-tête), NMI (saut en
# $8021), routines d'accès au VDP, puis tout ce que la couverture de cvrun
# ne trouve pas (tables de sauts...).
DISASM_ENTRIES = [0x80C6, 0x807C, 0x8054, 0x805D, 0x8067, 0x806E, 0x8073, 0xAA3D, 0xAA10]
# Routines appelées suivies d'une table de mots en ligne (call X / dw ...).
INLINE_JUMP_TABLES = {0x80EA}
# Routines appelées suivies de N octets de données en ligne (call X / db ...).
INLINE_DATA = {0x9F9C: 6}

# --- Police fine (tools/gen_tables.py) ----------------------------------------
# La police 8 pixels du jeu devient illisible à 4 pixels de large en mode 0 :
# on la remplace dans la ROM par la police 3x7 doublée (tools/font4.py).
# (décalage dans la ROM, caractères consécutifs de 8 octets). [] : rien.
FONT_PATCH = [(0x092C, '0123456789'), (0x09AC, '-'), (0x09B4, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')]

# --- Simulateurs (tools/portsim.py, ticks.py, level.py) -----------------------
# Touches pour passer du menu à la partie : cpcsim (script « trame:touches »)
# et cvrun (touche du pavé, de la trame A à la trame B).
START_KEYS_CPC = "400:1 425:"
START_KEY_CV = ('K1', 700, 730)
# Trame où la partie est lancée mais le niveau pas encore construit (écran
# « PLAYER 1 ») : c'est là qu'on écrit level_pokes().
POKE_FRAME_CPC = 700
POKE_FRAME_CV = 860
# Dans la NMI du jeu : adresse atteinte quand le tick est exécuté, et quand
# la NMI est ignorée parce que le tick précédent n'est pas fini (drapeau
# anti-réentrée du jeu), plus l'octet d'opcode à cette adresse (contrôle).
NMI_ACCEPT = (0x8094, 0x36)
NMI_SKIP = (0x80B2, 0xDD)
# Alignement des relevés Coleco/CPC : premier tick où cet octet de RAM a
# cette valeur (ici l'état « partie en cours » du jeu).
ALIGN = (0x6000, 0x0B)
# Compteurs recopiés de la Coleco vers le CPC à l'entrée en jeu (leur
# valeur dépend du temps passé dans les menus) : ici le compteur de trames
# du jeu, qui cadence les animations.
SYNC_AT_ALIGN = [0x6003]
# Octets de RAM ignorés par ticks.py : ce qui diffère légitimement entre
# les deux machines (valeurs tirées de « ld a,r », manettes, compteurs du
# BIOS, son, pile). À trouver avec « ticks.py N --walk --detail » : tout
# ce qui reste doit être identique.
TICKS_IGNORE = [(0x6003, 0x6003), (0x6008, 0x6022), (0x6055, 0x6055), (0x6300, 0x63FF)]
# Touche « droite » : cpcsim (joystick) et cvrun (manette).
RIGHT_CPC, RIGHT_CV = 'J0R', 'R'


def level_pokes(n):
    """Écritures en RAM Coleco pour aller directement au niveau n."""
    return [(0x6054, n), (0x6059, (n // 10) << 4 | n % 10)]   # numéro, et son affichage BCD
