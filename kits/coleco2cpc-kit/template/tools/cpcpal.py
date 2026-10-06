"""Palette : couleurs TMS9918 (ColecoVision) -> couleurs du CPC.

CPC : 27 couleurs (niveaux 0 / 128 / 255 par composante). Ink n du mode 0 =
couleur TMS n ; l'encre 0 (TMS « transparent ») prend la couleur de fond
(registre 7 du VDP), comme la bordure.
"""
# numéro firmware -> (RVB, code matériel du Gate Array)
CPC = [((0, 0, 0), 0x54), ((0, 0, 128), 0x44), ((0, 0, 255), 0x55), ((128, 0, 0), 0x5C),
       ((128, 0, 128), 0x58), ((128, 0, 255), 0x5D), ((255, 0, 0), 0x4C), ((255, 0, 128), 0x45),
       ((255, 0, 255), 0x4D), ((0, 128, 0), 0x56), ((0, 128, 128), 0x46), ((0, 128, 255), 0x57),
       ((128, 128, 0), 0x5E), ((128, 128, 128), 0x40), ((128, 128, 255), 0x5F), ((255, 128, 0), 0x4E),
       ((255, 128, 128), 0x47), ((255, 128, 255), 0x4F), ((0, 255, 0), 0x52), ((0, 255, 128), 0x42),
       ((0, 255, 255), 0x53), ((128, 255, 0), 0x5A), ((128, 255, 128), 0x59), ((128, 255, 255), 0x5B),
       ((255, 255, 0), 0x4A), ((255, 255, 128), 0x43), ((255, 255, 255), 0x4B)]

# couleur TMS -> numéro firmware CPC (choisi à l'œil, pas seulement au plus proche :
# on garde distinctes les couleurs TMS voisines quand le jeu les juxtapose)
TMS_TO_CPC = [
    0,      # 0 transparent (remplacé par la couleur de fond)
    0,      # 1 noir
    18,     # 2 vert moyen        -> vert vif
    22,     # 3 vert clair        -> vert pastel
    2,      # 4 bleu foncé        -> bleu vif
    14,     # 5 bleu clair        -> bleu pastel
    3,      # 6 rouge foncé       -> rouge
    20,     # 7 cyan              -> cyan vif
    6,      # 8 rouge moyen       -> rouge vif
    16,     # 9 rouge clair       -> rose
    24,     # 10 jaune foncé      -> jaune vif
    25,     # 11 jaune clair      -> jaune pastel
    9,      # 12 vert foncé       -> vert
    17,     # 13 magenta          -> magenta pastel
    13,     # 14 gris             -> gris
    26,     # 15 blanc            -> blanc
]


def rgb(tms):
    return CPC[TMS_TO_CPC[tms]][0]


def hw(tms):
    return CPC[TMS_TO_CPC[tms]][1]


def mode0_byte(left, right):
    """2 pixels mode 0 -> octet (gauche : bits 7,3,5,1 ; droite : 6,2,4,0)."""
    return (((left & 1) << 7) | ((left & 2) << 2) | ((left & 4) << 3) | ((left & 8) >> 2) |
            ((right & 1) << 6) | ((right & 2) << 1) | ((right & 4) << 2) | ((right & 8) >> 3))


def pair(bits2, fg, bg):
    """Deux pixels TMS (bits de motif, gauche en bit 1) -> une couleur :
    un seul pixel allumé suffit (les traits fins ne disparaissent pas)."""
    return fg if bits2 else bg
