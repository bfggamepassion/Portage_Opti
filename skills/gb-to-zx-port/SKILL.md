---
name: gb-to-zx-port
description: Porter un jeu Game Boy vers le ZX Spectrum en traduisant la ROM GB (SM83) en assembleur Z80 (sjasmplus) avec le kit gb2zx-kit — trace, désassemblage, fermeture de la logique, traduction vérifiée, moteur de sprites masqués, beeper, écran titre. À utiliser pour porter, convertir ou adapter un jeu Game Boy (GB/DMG) vers le ZX Spectrum, ou pour toute question de traduction SM83→Z80, de moteur de sprites Spectrum ou de son beeper.
---

# Game Boy → ZX Spectrum

Méthode générale : skill `portage-retro`. Ce kit est le **socle commun** des portages Game Boy : ses
étapes de rétro-ingénierie et de vérification (PORTING.md §4-6) servent à tous les autres kits `gb2*`.

## Où est tout

- Kit : `<DEPOT>\kits\gb2zx-kit\`
  - `PORTING.md` : **la méthode, à lire en entier avant tout** (étapes, différences SM83/Z80, moteur de
    sprites, cadence, carte mémoire, pièges).
  - `template/` : point de départ. Outils pilotés par `port_config.py` : `gb_trace.py`, `gb_closure.py`,
    `gb2z80.py`, `diff_gb.py`, `zxrun.py`, `gbgfx.py`, `mono_sprite.py`, `zxscreen.py`, `make_title.py`,
    et un squelette sjasmplus qui s'assemble et tourne (IM2, cadence 60→50 Hz, sprites masqués, beeper,
    titre RLE, chargeur BASIC avec `SCREEN$`).

## Démarrer

1. Lire `PORTING.md`.
2. Poser les décisions « étape 0 » : fidélité, 48K ou 128K, son, couleurs, modes, contrôles, bouton unique, langue des textes.
3. Copier `template/*` dans le nouveau dépôt, ROM dans `re/game.gb`.
4. Dans l'ordre : trace → désassemblage → fiche du jeu → racines de la logique → `port_config.py` →
   `gb_closure.py` → `gb2z80.py` → `gb_support.asm` → **validation `diff_gb.py`** → graphismes, sprites,
   entrées, son, titre, menu.
5. Après chaque étape visible : capture avec `zxrun.py`, puis lancer ZEsarUX pour l'utilisateur (commande dans PORTING.md §2).

## Non négociable

- La logique vient de la ROM, traduite. Régénérer `gb_logic.asm`, ne jamais l'éditer. Les retouches de
  gameplay voulues vont dans `PATCHES`, isolées et documentées.
- Assembleur (sjasmplus), pas de BASIC compilé.
- Construire hors de Google Drive (`build.sh` le fait).
- Fluidité des sprites avant les astuces de vitesse ; correspondance bouton unique simple et automatique.
