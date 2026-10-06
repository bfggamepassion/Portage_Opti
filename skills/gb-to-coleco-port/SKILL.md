---
name: gb-to-coleco-port
description: Porter un jeu Game Boy vers la ColecoVision en traduisant la ROM GB (SM83) en assembleur Z80 (sjasmplus) avec le kit gb2coleco-kit — 1 Ko de RAM et RAM_MAP, règle d'or du VDP TMS9918 (VRAM écrite seulement écran coupé ou dans la NMI), mode 2, sprites en deux couches, SN76489, manettes, tests openMSX. À utiliser pour porter, convertir ou adapter un jeu Game Boy vers la ColecoVision, ou pour toute question de timing VRAM TMS9918, de mises à jour VDP par NMI, de conversion mode 2, de remappage RAM ou de son SN76489.
---

# Game Boy → ColecoVision

Méthode générale : skill `portage-retro`. Le MSX1 a le même VDP : skill `gb-to-msx-port`.

## Où est tout

- Kit : `<DEPOT>\kits\gb2coleco-kit\`
  - `PORTING.md` : **méthode, à lire en entier** — 1 Ko de RAM et `RAM_MAP` de `gb2z80.py` ; **règle d'or
    du VDP** (VRAM écrite seulement écran et NMI coupés, ou dans la NMI depuis des tampons en RAM :
    `frame_ready`, `vdp_free`) ; tiers du mode 2, sprites en deux couches monochromes, limite de 4 par
    ligne et rotation des priorités ; SN76489, manette et pavé, pièges, chiffres.
  - `template/` : outils et sources complets d'un portage qui marche (ROM dans `re/game.gb`) ; à adapter
    au nouveau jeu (`gen_*.py`, `render.asm`, `menu.asm`).
- Rétro-ingénierie et vérification communes : `<DEPOT>\kits\gb2zx-kit\PORTING.md` §4-6.

## Démarrer

1. Lire `gb2coleco-kit\PORTING.md`.
2. Poser les décisions : nom, contrôles, langue.
3. Copier `template/*`, ROM dans `re/game.gb`.
4. Mesurer la RAM GB utilisée par la logique et écrire `RAM_MAP` ; traduire ; vérifier avec `tools/diff_cv.py`.
5. Adapter les scripts `gen_*.py` et écrire `render.asm` d'après les routines OAM de la ROM.
6. Après chaque étape visible : `tools/cvsim.py` (contrôle des accès VDP, captures), puis openMSX pour l'utilisateur.

## Non négociable

- Ne jamais éditer `gb/gb_logic.asm`.
- Jamais de VRAM écran allumé hors de la NMI : `cvsim.py` ne doit signaler aucune erreur VDP.
- Le BIOS (`COLECO.ROM`) n'est pas fourni : à copier dans `Documents\openMSX\share\systemroms`.
