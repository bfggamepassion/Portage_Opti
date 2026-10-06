# gb2c64-kit : porter un jeu Game Boy sur Commodore 64

Ce kit regroupe ce qui a servi à faire **C64 Tennis**, pour le réutiliser sur un autre jeu Game Boy, dans un autre repository. C'est l'équivalent C64 de [gb2zx-kit](../gb2zx-kit) (ZX Spectrum).

| Dossier / fichier | Contenu |
|---|---|
| [PORTING.md](PORTING.md) | **La méthode** : modèle de traduction SM83 → 6502, vérification, optimisation, affichage (caractères, sprites), SID, entrées, pièges, chiffres de référence. À lire en premier. |
| [claude/](claude/) | Pour que Claude retrouve ce savoir-faire dans un autre projet : un skill, et un extrait pour les instructions globales. |
| [template/](template/) | Le modèle à copier dans le nouveau repo : outils génériques et squelette 64tass, qui s'assemble et démarre. |


## Tous les kits

| Kit | Machine | Processeur | Traducteur |
|---|---|---|---|
| [gb2zx-kit](../gb2zx-kit) | ZX Spectrum | Z80 | `gb2z80.py` |
| [gb2cpc664-kit](../gb2cpc664-kit) | Amstrad CPC (+ CPC Plus/GX4000) | Z80 | `gb2z80.py` |
| [gb2c64-kit](../gb2c64-kit) | Commodore 64 | 6502 | `gb2m6502.py` |
| [gb2coleco-kit](../gb2coleco-kit) | ColecoVision | Z80 | `gb2z80.py` + `RAM_MAP` |
| [gb2msx-kit](../gb2msx-kit) | MSX1 | Z80 | `gb2z80.py` + `RAM_MAP` |
| [gb2mo5-kit](../gb2mo5-kit) | Thomson MO5 | 6809 | `gb2m6809.py` |

Le traducteur Z80 (`gb2z80.py`) sait déplacer la RAM GB (`RAM_MAP` dans `port_config.py`) pour les machines qui n'ont pas de RAM en `$C000` / `$FF80`. Sans `RAM_MAP`, il se comporte comme avant.

## Démarrer un nouveau portage

1. Créer le nouveau repo et y copier le contenu de `template/`.
2. Mettre la ROM dans `re/game.gb`.
3. Remplir `port_config.py` au fil de la rétro-ingénierie : les étapes communes sont dans le guide du kit Spectrum, celles du C64 dans [PORTING.md](PORTING.md).
4. Compiler : `sh build.sh`, qui produit `build/game.prg`. La logique est traduite dès que `ROOTS` est rempli.
5. Vérifier : `python -X utf8 tools/diff_gb6502.py 2000`.
6. Jouer : `x64sc -autostart build/game.prg`.

## Installer la partie Claude (une fois)

- **Skill** : copier `claude/skills/gb-to-c64-port/` vers `%USERPROFILE%\.claude\skills\gb-to-c64-port\` (c'est fait).
- **Instructions globales** (facultatif) : ajouter le bloc de [claude/CLAUDE-global.md](claude/CLAUDE-global.md) à `%USERPROFILE%\.claude\CLAUDE.md`.

## Le modèle (`template/`)

```
port_config.py       paramètres du jeu (racines, stubs, pointeurs, RST, découpage, indicateurs...)
build.sh             traduction + assemblage (64tass -C) -> build/game.prg, .lbl, .lst
tools/
  gbrom.py           socle commun : config, ROM, jeu d'instructions SM83
  gb_trace.py        traceur : sépare code et données -> .sym pour mgbdis
  gb_closure.py      code atteint depuis la logique ; accès matériel et pointeurs à classer
  gb2m6502.py        traduction SM83 -> 6502 (durée de vie des indicateurs, découpage)
  diff_gb6502.py     preuve de fidélité et coût en cycles : PyBoy contre py65, pas à pas
  gbgfx.py           tuiles 2bpp, VRAM reconstituée, sprites OAM
  c64gfx.py          tuiles -> caractères (haute résolution / multicolore), sprites, aperçus
  mgbdis/            désassembleur GB (MIT, Matt Currie)
src/
  main.asm           démarrage, banques ($01, VIC), interruption raster, boucle 60->50 Hz,
                     joystick port 2 + clavier, carte mémoire
  zp.asm             registres GB en page zéro
  gb_support.asm     RST, registre F, stubs (son, écran), gb_new_game, gb_tick, joypad
  render.asm         sprites : registres fantômes, recopie dans le VIC, placement
  text.asm           police recopiée de la ROM, encodage c64txt, affichage de texte
  sound.asm          bruitages SID
  gb_math_tennis.asm EXEMPLE : calculs de la ROM de Tennis réécrits en 6502 exact
gb/                  logique traduite (bouche-trous au départ)
```

## Ce qui a été vérifié

- `diff_gb6502.py` donne 0 différence sur 1 255 pas, sur la version exacte du jeu (`-D GB_EXACT=1`).
- Le squelette `template/` s'assemble et démarre dans VICE, avec son écran « PRESS FIRE TO PLAY ».

