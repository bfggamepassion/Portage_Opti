# Portage_Opti — boîte à outils pour porter et optimiser des jeux rétro

Tout ce qu'il faut pour porter un jeu d'une machine rétro vers une autre, ou accélérer un jeu sur sa propre
machine, avec Claude Code : la méthode, les prompts, les skills, les outils de conversion et de
vérification, les références d'optimisation. **Générique** : aucun jeu n'est fourni ; on part de son propre
fichier (ROM, disquette, cassette…).

## Démarrage rapide

1. Installer les outils : [INSTALLATION.md](INSTALLATION.md).
2. Installer les skills : `powershell -ExecutionPolicy Bypass -File installer.ps1`.
3. Créer un dépôt vide pour le jeu (hors Google Drive pour les builds), y mettre le fichier d'origine.
4. Ouvrir Claude Code dans ce dépôt et coller le prompt de la phase, champs `[ ]` remplis :
   [préparation](prompts/01_preparation.md) → [portage](prompts/02_portage.md) →
   [optimisation](prompts/03_optimisation.md) ; [adaptation](prompts/04_adaptation.md) si le jeu ne tient pas ;
   [optimisation sans portage](prompts/05_optimisation_sans_portage.md) pour accélérer un jeu sur sa machine.
5. À chaque nouvelle session : « Lis le fichier de reprise et continue. »

## Contenu

| Dossier | Contenu |
|---|---|
| [prompts/](prompts/) | Les prompts de travail, phase par phase, et un prompt de génération d'images au format CPC mode 0 |
| [skills/](skills/) | Les skills Claude (voir ci-dessous) |
| [kits/](kits/) | Outils et modèles de portage, prêts à copier dans un nouveau dépôt |
| [docs/LECONS.md](docs/LECONS.md) | Leçons et pièges : méthode, vérification, chaîne d'outils, émulateurs, façon de travailler |
| [docs/optimisation/](docs/optimisation/) | Les techniques d'optimisation CPC et C64 expliquées simplement |
| [docs/references/](docs/references/) | *Amstrad CPC CRTC Compendium* (Longshot, CC BY-NC-ND) |
| [outils/](outils/) | `synchroniser.py` : met à jour kits et skills d'optimisation depuis les dossiers de travail |

### Skills

| Skill | Rôle |
|---|---|
| `portage-retro` | Point d'entrée : méthode générale, choix de la stratégie et du kit, règles, façon de travailler |
| `gb-to-zx-port`, `gb-to-cpc-port`, `gb-to-c64-port`, `gb-to-coleco-port`, `gb-to-msx-port`, `gb-to-mo5-port` | Game Boy → ZX Spectrum, CPC, C64, ColecoVision, MSX1, Thomson MO5 (traduction statique de la ROM) |
| `coleco-to-cpc-port` | ColecoVision (ou autre machine Z80) → CPC 6128 : code d'origine gardé, E/S remplacées (HLE) |
| `cpc-optimisation` | Optimisation Z80 sur CPC : coûts en NOPs, CRTC, double tampon, défilement matériel, tuiles par la pile, sprites |
| `c64-optimisation` | Optimisation 6502 sur C64 : cycles, IRQ raster, multiplexeur de sprites, défilement, couleur RAM ; outils de profilage VICE |

### Kits

Chaque kit a un `PORTING.md` (la méthode et ses pièges) et un `template/` (outils pilotés par
`port_config.py` + squelette assembleur qui tourne).

| Kit | Source → cible | Stratégie | Outils phares |
|---|---|---|---|
| `gb2zx-kit` | GB → ZX Spectrum | SM83 → Z80 | `gb_trace`, `gb_closure`, `gb2z80`, `diff_gb`, `zxrun` (socle commun des kits GB) |
| `gb2cpc664-kit` | GB → CPC 464/664/6128 | SM83 → Z80 | `cpcgfx`, `make_dsk`, `sim64`, `cpcshot.sh` |
| `gb2c64-kit` | GB → C64 | SM83 → 6502 | `gb2m6502`, `diff_gb6502`, `c64gfx` |
| `gb2coleco-kit` | GB → ColecoVision | SM83 → Z80, 1 Ko de RAM | `cvsim` (contrôle des accès VDP), `diff_cv`, `gen_cv*` |
| `gb2msx-kit` | GB → MSX1 | SM83 → Z80 | `msxsim` (50/60 Hz), `diff_msx` |
| `gb2mo5-kit` | GB → Thomson MO5 | SM83 → 6809 | `gb2m6809`, `m6809` (émulateur), `mo5sim`, `make_k7` |
| `coleco2cpc-kit` | Coleco (Z80) → CPC 6128 | code d'origine + HLE | `cvrun`, `cpcsim`, `ticks` (tour par tour), `prof`, `fps`, `sprite_editor` |

Pour une paire de machines sans kit, la skill `portage-retro` indique de quel kit partir et quoi écrire.

## Principes

- La logique du jeu vient de son code (gardé ou traduit), prouvée identique tour par tour.
- L'affichage, le son et les entrées sont refaits avec les moyens de la cible, jamais en émulant la machine d'origine.
- Rien n'est affirmé sans mesure, dans l'unité de la machine.
- Un fichier de reprise par projet, tenu à jour, pour reprendre n'importe quelle session.

## Droits

- Aucune ROM, image disque ni BIOS dans ce dépôt : chacun utilise ses propres fichiers.
- `docs/references/ACCC1.11-EN.pdf` : *The Amstrad CPC CRTC Compendium* de Longshot (Logon System), licence
  CC BY-NC-ND 4.0, redistribué sans modification. Tout travail qui s'en sert garde la mention :
  `Technical information sourced from the "Amstrad CPC CRTC Compendium" by Longshot (CC BY-NC-ND).`
- `kits/*/template/tools/mgbdis` : désassembleur Game Boy de Matt Currie, sous sa propre licence (voir son dossier).
