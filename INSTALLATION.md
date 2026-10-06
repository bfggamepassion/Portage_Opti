# Installation sur une nouvelle machine (Windows)

Les scripts des kits cherchent les outils à des chemins fixes sous `%LOCALAPPDATA%`. En les installant
exactement là, tout marche sans rien modifier. Sinon, changer les variables en tête des `build.sh` / `run.sh`
(`TASS`, `C1541`, `SJASM`, `CAP32`, `MAME`, `WLA`…).

`installer.ps1` vérifie tout et dit ce qui manque :

```powershell
powershell -ExecutionPolicy Bypass -File installer.ps1 -Verifier
```

## 1. Base

| Outil | Pourquoi | Où le trouver |
|---|---|---|
| Claude Code (extension VS Code ou CLI) | l'agent qui fait le travail | https://claude.com/claude-code |
| Python 3.11+ (testé 3.14) | tous les outils | https://www.python.org — cocher « Add to PATH » |
| Paquets Python | `python -m pip install -r requirements.txt` | — |
| Git for Windows | `git` et `sh` (Git Bash) : les `build.sh` sont des scripts sh | https://git-scm.com |
| Node.js 18+ (facultatif) | simulateurs écrits en JavaScript, `npx repomix` | https://nodejs.org |

`repomix` (facultatif) : `npx repomix` produit `repomix-output.xml`, un résumé du dépôt que Claude lit au lieu de fouiller fichier par fichier.

## 2. Assembleurs

| Outil | Machines | Chemin attendu | Téléchargement |
|---|---|---|---|
| sjasmplus 1.24.0 | Z80 : CPC, ZX, MSX, Coleco | `%LOCALAPPDATA%\sjasmplus\sjasmplus-1.24.0.win\sjasmplus.exe` | https://github.com/z00m128/sjasmplus/releases |
| 64tass 1.60 | 6502 : C64 | `%LOCALAPPDATA%\64tass\64tass-1.60.3243\64tass.exe` | https://sourceforge.net/projects/tass64/ |
| asm6809 2.17 | 6809 : Thomson | `%LOCALAPPDATA%\asm6809\asm6809-2.17-w64\asm6809.exe` | https://www.6809.org.uk/asm6809/ |
| RGBDS 1.0 | Game Boy (réassembler un listing GB) | `%LOCALAPPDATA%\rgbds\rgbasm.exe` | https://github.com/gbdev/rgbds/releases |
| WLA-DX | Master System | dossier dans la variable `WLA` | https://github.com/vhelin/wla-dx |

## 3. Émulateurs

| Émulateur | Machines | Chemin attendu | Téléchargement / réglage |
|---|---|---|---|
| Caprice32 (fork ColinPitrat) | Amstrad CPC | `%LOCALAPPDATA%\Caprice32\cap32-win64\cap32.exe` | https://github.com/ColinPitrat/caprice32/releases — régler `cap32.cfg` en 6128 ; le lancer depuis son dossier |
| VICE 3.10 (GTK3) | C64 (`x64sc`, `c1541`) | `%LOCALAPPDATA%\VICE\GTK3VICE-3.10-win64\bin\` | https://vice-emu.sourceforge.io |
| openMSX | MSX (C-BIOS fourni), ColecoVision | `%LOCALAPPDATA%\openMSX\openmsx.exe` | https://openmsx.org — BIOS Coleco à copier dans `Documents\openMSX\share\systemroms\COLECO.ROM` |
| DCMOTO | Thomson MO5/TO | `%LOCALAPPDATA%\dcmoto\dcmoto-64\dcmoto.exe` | http://dcmoto.free.fr |
| ZEsarUX 13 | ZX Spectrum | `%LOCALAPPDATA%\ZEsarUX\ZEsarUX_windows-13.0\zesarux.exe` | https://github.com/chernandezba/zesarux/releases |
| Mesen2 | Game Boy, Master System | `%LOCALAPPDATA%\Mesen2\Mesen.exe` | https://www.mesen.ca |
| MAME | arcade, référence matérielle | variable `MAME` | https://www.mamedev.org |

Les ROM système (BIOS Coleco, firmware CPC, ROM des consoles) et les jeux **ne sont pas dans ce dépôt** :
chacun fournit les siens.

## 4. Skills Claude

```powershell
powershell -ExecutionPolicy Bypass -File installer.ps1
```

Copie `skills\*` dans `%USERPROFILE%\.claude\skills\` en remplaçant `<DEPOT>` par le chemin de ce dépôt
(les skills pointent vers `kits\` et `docs\`). **Relancer après avoir déplacé le dépôt.** Claude Code
charge ensuite seul la bonne skill quand on parle de portage ou d'optimisation.

## 5. Vérifier

Dans Claude Code, ouvrir un dossier vide et demander : « Quelles skills de portage as-tu ? ». Il doit citer
`portage-retro`, les `gb-to-*-port`, `coleco-to-cpc-port`, `cpc-optimisation` et `c64-optimisation`.
