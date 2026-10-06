# gb2zx-kit : porter un jeu Game Boy sur ZX Spectrum

Ce kit regroupe ce qui a servi à faire **ZX Tennis**, pour le réutiliser sur un autre jeu Game Boy, dans un autre repository.

| Dossier / fichier | Contenu |
|---|---|
| [PORTING.md](PORTING.md) | **La méthode** : principe, outils, étapes, pièges rencontrés, chiffres de référence. À lire en premier. |
| [claude/](claude/) | Pour que Claude retrouve ce savoir-faire dans un autre projet : un skill, et un extrait pour les instructions globales. |
| [template/](template/) | Le modèle à copier dans le nouveau repo : outils génériques et squelette assembleur qui s'assemble et tourne. |


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
3. Remplir `port_config.py` au fil de la rétro-ingénierie, en suivant [PORTING.md](PORTING.md) (§4 à §6).
4. Compiler : `sh asm/build.sh`, qui produit `asm/build/game.tap`.
5. Tester : `python tools/zxrun.py asm/build/game.tap --frames 300 --keys "60-62:ENTER" --sheet 25`.

## Installer la partie Claude (une fois)

- **Skill**, disponible dans tous les projets : copier `claude/skills/gb-to-zx-port/` vers `%USERPROFILE%\.claude\skills\gb-to-zx-port\`. Claude le charge dès qu'on parle de porter un jeu Game Boy. On peut aussi l'appeler directement avec `/gb-to-zx-port`.
- **Instructions globales** (facultatif) : ajouter le bloc de [claude/CLAUDE-global.md](claude/CLAUDE-global.md) à `%USERPROFILE%\.claude\CLAUDE.md`.

## Le modèle (`template/`)

```
port_config.py       paramètres du jeu (racines de la logique, stubs, pointeurs, RST...)
tools/
  gbrom.py           socle commun : config, ROM, jeu d'instructions SM83
  gb_trace.py        traceur : sépare code et données -> .sym pour mgbdis
  gb_closure.py      code atteint depuis la logique ; accès matériel et pointeurs à classer
  gb2z80.py          traduction SM83 -> Z80 (asm/gb/gb_logic.asm)
  diff_gb.py         preuve de fidélité : PyBoy contre Z80, pas à pas
  zxrun.py           Spectrum 48K simulé sans fenêtre : captures, GIF, robot, contention, profilage
  gbgfx.py           tuiles 2bpp, VRAM reconstituée, sprites OAM -> PNG
  mono_sprite.py     sprites GB 4 teintes -> sprites Spectrum masqués (asm)
  zxscreen.py        composition d'écrans Spectrum, .scr, RLE, aperçu
  make_title.py      exemple d'écran titre
  mgbdis/            désassembleur GB (MIT, Matt Currie)
asm/
  build.sh           chaîne complète, assemblage hors Google Drive
  src/main.asm       démarrage, IM2, menu, boucle de jeu 60->50 Hz, chargeur cassette
  src/defs.asm       carte mémoire
  src/gb_support.asm RST, stubs, gb_new_game, gb_tick, joypad
  src/sprite.asm     moteur de sprites masqués pré-décalés (celui de Tennis)
  src/input.asm      clavier QAOP/ESPACE + Kempston -> joypad GB
  src/sound.asm      bruitages beeper
  src/text.asm       texte avec la police ROM
  src/unrle.asm      décompression de l'écran titre
```

## Ce qui a été vérifié

  - `gb2z80.py` reproduit à l'identique le `gb_logic.asm` de Tennis ;
  - `gb_trace.py` reproduit à l'identique le `re/tennis.sym` de Tennis ;
  - `diff_gb.py` donne 1255 pas comparés, dont 3 différents, qui sont les effets voulus du patch `S_P1SHOT`.
- Le squelette `template/asm` s'assemble et tourne dans `zxrun.py` : le menu s'affiche, puis ENTER lance la boucle de jeu.

