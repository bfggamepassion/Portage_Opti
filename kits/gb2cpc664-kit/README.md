# gb2cpc664-kit : porter un jeu Game Boy sur Amstrad CPC664

Ce kit regroupe ce qui a servi à faire **CPC Tennis**, pour le réutiliser sur un autre jeu Game Boy, dans un autre repository. C'est l'équivalent CPC de [gb2zx-kit](../gb2zx-kit) (Spectrum) et [gb2c64-kit](../gb2c64-kit) (C64).

| Dossier / fichier | Contenu |
|---|---|
| [PORTING.md](PORTING.md) | **La méthode** : mémoire du 664, écran en `$4000`, sprites logiciels (XOR, VSYNC, ordre du balayage), mode 0, entrées, AY, pièges, chiffres. À lire en premier. |
| [claude/](claude/) | Le skill `gb-to-cpc-port` (installé) et un extrait pour les instructions globales. |
| [template/](template/) | Le modèle à copier : outils et squelette sjasmplus. Il s'assemble, démarre et affiche un sprite qui bouge. |


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
3. Rétro-ingénierie et configuration (`port_config.py`) : suivre le guide du kit Spectrum (§4 à §6). Le traducteur Z80 est le même.
4. Compiler : `sh build.sh`, qui produit `build/game.dsk`.
5. Capture de contrôle : `sh tools/cpcshot.sh 10`.

## Le modèle (`template/`)

```
port_config.py       paramètres du jeu (racines, stubs, pointeurs, RST...)
build.sh             traduction + graphismes + sjasmplus + disquette
tools/
  gbrom.py, gb_trace.py, gb_closure.py, gb2z80.py, gbgfx.py, mgbdis/
                     rétro-ingénierie et traduction SM83 -> Z80 (comme le Spectrum)
  cpcgfx.py          mode 1 / mode 0, tuiles, décor, table des lignes, sprites
                     (lignes rognées, 4 décalages fabriqués au démarrage, zones de RAM)
  make_demo_gfx.py   graphismes de démonstration (à remplacer)
  make_dsk.py        disquette .dsk (format DATA, en-tête AMSDOS)
  cpcshot.sh         capture automatique dans Caprice32
  sim64.py           simulateur Z80 de SkoolKit avec 64 Ko de RAM (profilage, tests)
src/
  main.asm           démarrage (firmware coupé, écran en $4000, IM 1), VSYNC,
                     boucle 60 -> 50 Hz, décor en tuiles, menu minimal
  defs.asm           carte mémoire, emplacements de sprites
  gb_support.asm     RST, stubs, gb_new_game, gb_tick, joypad, gb_idle
  sprite.asm         moteur de sprites en XOR (fabrication des décalages, découpage)
  update.asm         mise à jour : sprites changés, dans l'ordre du balayage
  render.asm         places des sprites (démo : une balle qui traverse l'écran)
  input.asm          clavier + joystick (matrice par le PSG), 1 ou 2 boutons
  text.asm           police de la ROM (lue au démarrage), texte en mode 1
  sound.asm          bruitages AY
gb/                  logique traduite (bouche-trou au départ)
```

## Ce qui a été vérifié

- Le squelette s'assemble et fabrique `build/game.dsk`. Dans Caprice32 (664), `RUN"GAME"` affiche le décor et « PRESS SPACE », puis le sprite de démonstration se déplace sans trace.
- Le moteur de sprites, la synchronisation sur le VSYNC, les entrées et le son sont ceux de CPC Tennis, validés en jeu par l'utilisateur.
