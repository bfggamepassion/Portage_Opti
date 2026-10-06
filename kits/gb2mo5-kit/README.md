# gb2mo5-kit : porter un jeu Game Boy sur Thomson MO5

Ce kit regroupe ce qui a servi à faire **MO5 Tennis** (cassette), pour le réutiliser sur un autre jeu Game Boy dans un autre repository. C'est le seul kit avec un **traducteur SM83 → 6809**. Kits voisins :

| Kit | Machine | Processeur |
|---|---|---|
| [gb2zx-kit](../gb2zx-kit) | ZX Spectrum | Z80 |
| [gb2cpc664-kit](../gb2cpc664-kit) | Amstrad CPC (+ CPC Plus/GX4000) | Z80 |
| [gb2c64-kit](../gb2c64-kit) | Commodore 64 | 6502 |
| [gb2coleco-kit](../gb2coleco-kit) | ColecoVision | Z80 |
| [gb2msx-kit](../gb2msx-kit) | MSX1 | Z80 |
| **gb2mo5-kit** | Thomson MO5 | 6809 |

| Dossier / fichier | Contenu |
|---|---|
| [PORTING.md](PORTING.md) | **La méthode** : traducteur 6809 (registres, indicateurs, analyse interprocédurale, pièges), vérifications, matériel du MO5 (d'après MAME), recomposition par cases, cassette, son, chiffres. À lire en premier. |
| [claude/](claude/) | Le skill `gb-to-mo5-port` (installé) et un extrait pour les instructions globales. |
| [template/](template/) | Les outils et les sources de MO5 Tennis, rendus autonomes : ROM dans `re/game.gb`. |

## Démarrer un nouveau portage

1. Copier `template/` dans le nouveau repo et mettre la ROM dans `re/game.gb`.
2. Configurer `port_config.py` en suivant le kit Spectrum (§4 à §6) : racines, stubs, RST, `RAM_MAP`, indicateurs des stubs.
3. Traduire et vérifier la logique seule :
   - `python tools/gb2m6809.py` ;
   - assembler `src/logictest.asm` ;
   - `python tools/diff_mo5.py`.
4. `sh build.sh`, qui produit `build/tennis.bin` et `build/tennis.k7`. Puis `python tools/mo5sim.py 400 --keys "60:S 64:" --shot 200,399`.
5. Tester dans DCMOTO avec `LOADM"",,R`, par « Simuler le clavier » si la frappe passe mal.

## Ce qui a été vérifié

- Avec la ROM de Tennis, le modèle refait **exactement** la cassette de MO5 Tennis (comparée octet par octet).
- L'émulateur 6809 est validé par un test croisé contre l'émulateur MC6809.
- MO5 Tennis a été joué dans DCMOTO par l'utilisateur. Il **n'a pas été testé sur une vraie machine**.
