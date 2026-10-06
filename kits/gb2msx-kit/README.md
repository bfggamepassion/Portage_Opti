# gb2msx-kit : porter un jeu Game Boy sur MSX1

Ce kit regroupe ce qui a servi à faire **MSX Tennis**, pour le réutiliser sur un autre jeu Game Boy dans un autre repository. Il complète [gb2coleco-kit](../gb2coleco-kit) : même VDP (TMS9918A), même Z80. Kits voisins :

| Kit | Machine | Processeur |
|---|---|---|
| [gb2zx-kit](../gb2zx-kit) | ZX Spectrum | Z80 |
| [gb2cpc664-kit](../gb2cpc664-kit) | Amstrad CPC (+ CPC Plus/GX4000) | Z80 |
| [gb2c64-kit](../gb2c64-kit) | Commodore 64 | 6502 |
| [gb2coleco-kit](../gb2coleco-kit) | ColecoVision | Z80 |
| **gb2msx-kit** | MSX1 | Z80 |
| [gb2mo5-kit](../gb2mo5-kit) | Thomson MO5 | 6809 |

| Dossier / fichier | Contenu |
|---|---|
| [PORTING.md](PORTING.md) | **Les différences avec la ColecoVision** : cartouche `$4000` et ENASLT, HRAM déplacée, IM 2, AY et registre 7, clavier et joystick, 50/60 Hz, automatisation d'openMSX. Lire d'abord le guide Coleco. |
| [claude/](claude/) | Le skill `gb-to-msx-port` (installé) et un extrait pour les instructions globales. |
| [template/](template/) | Les outils et les sources de MSX Tennis, rendus autonomes : ROM dans `re/game.gb`. |

## Démarrer un nouveau portage

1. Copier `template/` dans le nouveau repo, puis mettre la ROM dans `re/game.gb`.
2. Configurer `port_config.py` en suivant le kit Spectrum (§4 à §6), avec `RAM_MAP` pour la HRAM.
3. `sh build.sh`, puis `python tools/diff_msx.py` (fidélité) et `python tools/msxsim.py 300 --shot 100,299` (accès VDP, captures). Ajouter `--50` pour tester à 50 Hz.
4. Tester dans openMSX sur `C-BIOS_MSX1_EU` et `C-BIOS_MSX1`.

## Ce qui a été vérifié

- Avec la ROM de Tennis, le modèle refait **exactement** la cartouche de MSX Tennis (comparée octet par octet).
- MSX Tennis a été vérifié dans openMSX, en C-BIOS 50 et 60 Hz, avec l'alerte d'accès VRAM trop rapide activée : menu, lancement du match et match, sans alerte.
