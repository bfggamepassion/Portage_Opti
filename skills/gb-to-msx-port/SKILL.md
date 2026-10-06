---
name: gb-to-msx-port
description: Porter un jeu Game Boy vers le MSX1 (cartouche) en traduisant la ROM GB (SM83) en assembleur Z80 (sjasmplus) avec le kit gb2msx-kit, dérivé du kit ColecoVision (même VDP) — mise en place cartouche (ENASLT, IM 2), timing VRAM TMS9918, registre 7 de l'AY, clavier/joystick MSX, 50/60 Hz, tests openMSX/C-BIOS. À utiliser pour porter, convertir ou adapter un jeu Game Boy vers le MSX.
---

# Game Boy → MSX1

Méthode générale : skill `portage-retro`.

## Où est tout

- Kit : `<DEPOT>\kits\gb2msx-kit\`
  - `PORTING.md` : la méthode propre au MSX. Lire **d'abord** `<DEPOT>\kits\gb2coleco-kit\PORTING.md`
    (règle d'or du VDP, mode 2, couches de sprites, `RAM_MAP`).
  - `template/` : outils et sources complets d'un portage qui marche (ROM dans `re/game.gb`).
- Rétro-ingénierie et vérification communes : `<DEPOT>\kits\gb2zx-kit\PORTING.md` §4-6.

## Démarrer

1. Lire `gb2coleco-kit\PORTING.md`, puis `gb2msx-kit\PORTING.md`.
2. Poser les décisions : nom, contrôles, langue.
3. Copier `template/*`, ROM dans `re/game.gb`, remplir `port_config.py` (avec `RAM_MAP` pour la HRAM), vérifier avec `tools/diff_msx.py`.
4. Adapter les scripts graphiques et `render.asm`. Contrôler avec `tools/msxsim.py` à 60 Hz et à 50 Hz (`--50`).
5. Tester dans openMSX avec `C-BIOS_MSX1_EU` et `C-BIOS_MSX1` (aucun BIOS propriétaire nécessaire). Pas de `throttle off` pour les captures scriptées.

## Non négociable

- Ne jamais éditer `gb/gb_logic.asm`.
- VRAM écrite seulement écran et interruptions coupés, ou dans l'interruption de trame. Registre 7 du PSG : bits 7-6 toujours à 10.
