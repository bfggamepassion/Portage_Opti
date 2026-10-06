---
name: coleco-to-cpc-port
description: Porter un jeu ColecoVision (ou toute machine Z80 à puce vidéo TMS9918/EF9345) vers l'Amstrad CPC 6128 en faisant tourner le code Z80 d'origine inchangé et en remplaçant ses E/S vidéo/son/manette par du code CPC (HLE), avec un moteur mode 0 en double tampon, à partir du kit coleco2cpc-kit. À utiliser pour porter un jeu Coleco (.col/.rom) ou un autre jeu Z80 vers le CPC sans le traduire, ou pour toute question d'émulation TMS9918 sur CPC, de conversion SN76489→AY, ou de comparaison tour par tour d'un portage avec l'original.
---

# ColecoVision → Amstrad CPC 6128 (même processeur : HLE)

Méthode générale : skill `portage-retro`. Optimisation du moteur : skill `cpc-optimisation`.
La même approche s'applique à toute machine Z80 → CPC (MSX, VG5000…) : seule la puce vidéo virtuelle change.

## Où est tout

- Kit : `<DEPOT>\kits\coleco2cpc-kit\`
  - `PORTING.md` : **la méthode, à lire en entier** :
    - les trois contrôles d'une nouvelle ROM : taille de la cartouche (16 Ko tient en banque 6 ; 24/32 Ko
      demandent un autre plan mémoire), appels au BIOS, sites d'E/S ;
    - le plan mémoire (vues Gate Array V_GAME/V_BASE/V_B4/V_B5/V_B7, état partagé, code commun identique en base 0 et banque 4) ;
    - le moteur (cache de tuiles, cases sales, table de sprites paresseuse, masques, double tampon, conversion mode 0, police fine) ;
    - entrées, menu, SN76489 → AY, leçons de performance, pièges.
  - `template/` : un portage complet rendu générique. Tout ce qui est propre au jeu pour les outils est dans
    `tools/port_config.py` ; les parties `.asm` à adapter sont listées dans `PORTING.md` §11.
  - Outils clés : `cvrun.py` (Coleco simulée avec le vrai BIOS), `disasm.py`, `cpcsim.py` (CPC 6128
    simulé), `ticks.py` (logique comparée tour par tour), `level.py`/`prof.py`/`fps.py` (vitesse),
    `render_check.py`, `make_dsk.py`, `sprite_editor.py` (retouche des sprites mode 0).

## Démarrer

1. Lire `PORTING.md`.
2. Demander à l'utilisateur ce qui lui revient : ROM du jeu, écran titre/menu, triches, langue des textes.
3. Copier `template/*` dans le nouveau dépôt. ROM dans `re/<JEU>.col`, BIOS Coleco dans `re/coleco_bios.rom`
   (non fourni). Régler `GAME`/`DSK_NAME` dans `tools/port_config.py`.
4. Étudier l'original avec `cvrun.py` (couverture, `re/io.txt`) et `disasm.py`. Faire les trois contrôles
   de `PORTING.md` §2 **avant** d'écrire du code ; prévenir l'utilisateur si la cartouche dépasse 16 Ko ou si le jeu dépend du BIOS.
5. Adapter `defs.asm`, `patches.asm` et les conventions d'entrée de `gamecode.asm`. Construire avec `sh build.sh`, contrôler dans `cpcsim.py`.
6. Vérifier la logique avec `tools/ticks.py N --walk` : objectif 0 tour différent. Puis mesurer avec `tools/level.py N [--prof]`.
7. Après chaque étape visible : `sh run.sh` (Caprice32) pour l'utilisateur.

## Non négociable

- Ne jamais modifier la logique d'origine. Remplacer seulement les E/S, ou réécrire une boucle en natif
  avec **exactement** le même effet et les mêmes registres de sortie, prouvé par `ticks.py`.
- Avant d'accuser le portage d'une différence de jeu, comparer avec `ticks.py` contre la vraie ROM + BIOS.
- Déboguer dans les simulateurs, pas par des lancements d'émulateur répétés.
- Toujours laisser la version normale dans `build/`.
