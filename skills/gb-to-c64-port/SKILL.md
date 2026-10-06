---
name: gb-to-c64-port
description: Porter un jeu Game Boy vers le Commodore 64 en traduisant la ROM GB (SM83) en assembleur 6502 (64tass) avec le kit gb2c64-kit — modèle de traduction (registres en page zéro, indicateurs, pile, banques $01), vérification, affichage en caractères et sprites matériels, SID, tests VICE. À utiliser pour porter, convertir ou adapter un jeu Game Boy vers le C64, ou pour toute question de traduction SM83→6502, de conversion des graphismes GB en caractères/sprites C64, de son SID ou de tests VICE.
---

# Game Boy → Commodore 64

Méthode générale : skill `portage-retro`. Optimisation C64 : skill `c64-optimisation`.

## Où est tout

- Kit : `<DEPOT>\kits\gb2c64-kit\`
  - `PORTING.md` : **méthode C64, à lire en entier** — registres GB en page zéro, indicateurs zZ/zCY, pile
    6502 avec JSR -1, banques `$01` ; vérification et optimisation ; affichage 1:1 (tuiles GB en
    caractères mixtes MC/hires, sprites matériels) ; SID, entrées, titre ; pièges et chiffres.
  - `template/` : outils génériques pilotés par configuration (`gb2m6502.py`, `diff_gb6502.py`,
    `c64gfx.py`, `gb_trace.py`, `gb_closure.py`, `gbgfx.py`) et un squelette 64tass qui tourne dans VICE.
- Rétro-ingénierie commune (trace, désassemblage, racines, configuration) : `<DEPOT>\kits\gb2zx-kit\PORTING.md` §4-5.

## Démarrer

1. Lire `gb2c64-kit\PORTING.md`.
2. Poser les décisions : fidélité, PAL/NTSC, contrôles, bouton unique, nom, langue.
3. Copier `template/*`, ROM dans `re/game.gb`.
4. Trace → désassemblage → racines → `port_config.py` → `gb2m6502.py` → `gb_support.asm` →
   **fidélité prouvée par `diff_gb6502.py` (0 différence)** → profil → stubs natifs rapides pour les points
   chauds, chacun vérifié contre la ROM traduite → affichage, sprites, SID, entrées, menu.
5. Après chaque étape visible : capture VICE sans fenêtre (`-limitcycles`, `-exitscreenshot`), puis
   `x64sc -autostart build/game.prg` pour l'utilisateur.

## Non négociable

- Ne jamais éditer les `gb/gb_logic_*.asm` générés. Retouches de gameplay sous `.if !GB_EXACT` ; les
  builds de vérification avec `-D GB_EXACT=1`.
- Toujours assembler avec 64tass `-C` ; garder Y = 0 dans tout code appelé par la logique traduite.
- Mesurer la vitesse réelle dans VICE (build autoplay + compteur d'images en retard), ne pas deviner.
