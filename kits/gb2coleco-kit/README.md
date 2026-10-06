# gb2coleco-kit : porter un jeu Game Boy sur ColecoVision

Ce kit regroupe ce qui a servi à faire **Coleco Tennis**, pour le réutiliser sur un autre jeu Game Boy dans un autre repository. Kits voisins :

| Kit | Machine | Processeur |
|---|---|---|
| [gb2zx-kit](../gb2zx-kit) | ZX Spectrum | Z80 |
| [gb2cpc664-kit](../gb2cpc664-kit) | Amstrad CPC (+ CPC Plus/GX4000) | Z80 |
| [gb2c64-kit](../gb2c64-kit) | Commodore 64 | 6502 |
| **gb2coleco-kit** | ColecoVision | Z80 |
| [gb2msx-kit](../gb2msx-kit) | MSX1 | Z80 |
| [gb2mo5-kit](../gb2mo5-kit) | Thomson MO5 | 6809 |

| Dossier / fichier | Contenu |
|---|---|
| [PORTING.md](PORTING.md) | **La méthode** : 1 Ko de RAM et `RAM_MAP`, la règle du VDP (NMI, `frame_ready`, `vdp_free`), mode 2, sprites en 2 couches, SN76489, manette, pièges, chiffres. À lire en premier. |
| [claude/](claude/) | Le skill `gb-to-coleco-port` (installé) et un extrait pour les instructions globales. |
| [template/](template/) | Les outils et les sources de Coleco Tennis, rendus autonomes : ROM dans `re/game.gb`, outils dans `tools/`. |

## Démarrer un nouveau portage

1. Créer le nouveau repo et y copier le contenu de `template/`.
2. Mettre la ROM dans `re/game.gb`.
3. Rétro-ingénierie et configuration (`port_config.py`), en suivant le guide du kit Spectrum (§4 à §6). Mesurer la RAM GB utilisée et écrire `RAM_MAP`.
4. `sh build.sh`, puis `python tools/diff_cv.py` (fidélité) et `python tools/cvsim.py 300 --shot 100,299` (accès VDP, captures).

## Le modèle (`template/`)

```
port_config.py     paramètres du jeu (racines, stubs, RST, RAM_MAP)
build.sh           traduction + graphismes + sjasmplus -> build/tennis.rom
tools/
  gbrom.py, gb_trace.py, gb_closure.py, gb2z80.py (+ RAM_MAP), gbgfx.py, mgbdis/
  tms.py           palette TMS9918, ligne de 8 pixels -> motif + couleur
  gen_cvgfx.py     décor (tiers, police en 192-255)   } propres à Tennis :
  gen_cvtitle.py   écran titre                          } à adapter (VRAM GB
  gen_cvsprites.py sprites 16x16 en couches             } reconstituée, images)
  gen_cpcgfx.py, extract_sprites.py   reconstitution de la VRAM et des sprites de Tennis
  cvsim.py         console simulée + contrôle des accès VDP + captures
  diff_cv.py, diff_gb.py, zxrun.py    comparaison pas à pas (PyBoy)
  sim64.py         simulateur Z80 SkoolKit, 64 Ko de RAM
src/
  main.asm         en-tête, démarrage, NMI, boucle de match
  vdp.asm          écran éteint / retour de trame, travaux de texte, recopie des motifs
  render.asm       décor, sprites (couches, ordre alterné)
  proj.asm         projection de Tennis (exemple de routine native)
  text.asm, menu.asm, input.asm, sound.asm, gb_support.asm, vars.asm, defs.asm
```

## Ce qui a été vérifié

- Avec la ROM de Tennis, le modèle refait **exactement** la cartouche de Coleco Tennis (comparée octet par octet).
- Dans openMSX, avec le BIOS et l'alerte d'accès VRAM trop rapide activée, l'écran titre s'affiche sans alerte. Le match complet a été vérifié dans `cvsim.py` : aucune erreur d'accès VDP sur 5 000 trames jouées par le robot.
