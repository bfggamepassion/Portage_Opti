---
name: portage-retro
description: Méthode générique pour porter, adapter ou optimiser un jeu rétro d'une machine 8/16 bits vers une autre (Game Boy, ColecoVision, MSX, ZX Spectrum, Amstrad CPC, C64, Thomson, Oric, VG5000, Master System, arcade…) — préparation (extraction, simulateur, listing réassemblable, frontière du portage), portage (même processeur : programme d'origine corrigé ; processeur différent : traduction statique vérifiée), optimisation mesurée, adaptation d'un jeu trop gros. À utiliser dès qu'on parle de porter, convertir, adapter, rétro-ingénier ou accélérer un jeu rétro, même sans citer la skill ; elle dit quel kit, quelle skill de machine et quel prompt prendre.
---

# Portage de jeux rétro — méthode générique

Dépôt de référence : `<DEPOT>` (installé par `installer.ps1`). Tout y est générique : aucun jeu
n'est fourni.

| Besoin | Où |
|---|---|
| Prompts de travail (préparation, portage, optimisation, adaptation, optimisation sans portage, images CPC) | `<DEPOT>\prompts\` |
| Leçons et pièges (émulateurs, chaîne d'outils, façon de travailler) | `<DEPOT>\docs\LECONS.md` |
| Installation des outils | `<DEPOT>\INSTALLATION.md` |
| Kits Game Boy → ZX / CPC / C64 / Coleco / MSX / MO5 | `<DEPOT>\kits\gb2*-kit\` (skills `gb-to-*-port`) |
| Kit ColecoVision → CPC (code d'origine + HLE des E/S) | `<DEPOT>\kits\coleco2cpc-kit\` (skill `coleco-to-cpc-port`) |
| Optimisation CPC / C64 | skills `cpc-optimisation`, `c64-optimisation` ; explications pour débutant dans `<DEPOT>\docs\optimisation\` |

## Les quatre phases

Chaque phase a son prompt dans `<DEPOT>\prompts\`. Si l'utilisateur colle un de ces prompts, le suivre à la lettre.

1. **Préparation** (`01_preparation.md`) : extraire l'image de référence (MD5), simulateur pilotable par
   script, outil de comparaison tour par tour, listing **réassemblable à l'identique**, fichier de noms,
   document « frontière du portage » + carte mémoire minimale, fichier de reprise.
2. **Portage** (`02_portage.md`) : logique identique, affichage/son/entrées natifs.
3. **Optimisation** (`03_optimisation.md`) ou **optimisation sans portage** (`05_optimisation_sans_portage.md`).
4. **Adaptation** (`04_adaptation.md`) quand le jeu ne tient pas : budget, inventaire, triage, **arrêt
   obligatoire** avant toute coupe.

## Choisir la stratégie

| Cas | Stratégie | Kit de départ |
|---|---|---|
| Même processeur (Z80→Z80, 6502→6502) | Programme d'origine gardé en mémoire, corrigé aux points de la frontière ; E/S remplacées par un moteur natif (HLE) | `coleco2cpc-kit` (modèle : banques, patches d'E/S, moteur de rendu, `ticks.py`) |
| Processeur différent | Traduction statique routine par routine, générée depuis la ROM, jamais retouchée à la main | `gb2*-kit` : `gb2z80.py`, `gb2m6502.py`, `gb2m6809.py` + `diff_*.py` |
| Code compilé naïf trop gros à traduire | Décompiler vers une représentation intermédiaire, puis générer le code cible | à écrire ; s'inspirer des traducteurs des kits |
| Jeu en BASIC | Machine virtuelle à bytecode ou réécriture assembleur, textes extraits | à écrire |
| Même machine (optimisation) | Source réassemblable, moteur d'affichage réécrit, logique comparée tour par tour | skills d'optimisation |

## Règles non négociables

- **La logique vient du code d'origine**, jamais de l'observation du jeu. Toute réécriture à la main d'une
  routine est prouvée identique (comparaison tour par tour, entrées scriptées et aléatoires, hasard rendu identique).
- **Afficher avec les moyens de la cible, jamais émuler l'écran d'origine.** Sprites et tuiles natifs,
  graphismes convertis hors ligne (PNG modifiables → données cible). Si la logique relit son écran
  (collisions), garder cet écran en RAM comme carte de collisions invisible, sans le convertir.
- **Mesurer avant d'affirmer**, dans l'unité de la machine (NOPs CPC, cycles 6502, T-states). Une estimation est marquée comme telle.
- **Architecture avant micro-code** : les gains ×3 à ×100 viennent de ne pas faire le travail (cases sales, matériel, précalcul).
- Petites étapes vérifiées et commitées ; fichier de reprise tenu à jour (outils, état, pièges, prochaine action exacte).
- Démarrage, chargement et affichage vérifiés sur un **vrai émulateur** de la cible avant d'annoncer qu'un
  support (disquette, ROM, cassette) marche : un simulateur maison ne voit ni le firmware, ni le DOS, ni le chargeur.
- Construire hors des dossiers synchronisés (Google Drive, OneDrive) : ils ont corrompu des `.tap`/`.dsk`.
- Si une piste n'aboutit pas après deux essais, la noter, puis changer d'approche ou **proposer des concessions** chiffrées à l'utilisateur plutôt que s'acharner.

## Façon de travailler avec l'utilisateur

- Parler français ; textes du jeu en anglais sauf décision contraire.
- Pas de texte entre deux étapes ; un compte rendu court à chaque palier ou point d'arrêt, et à la fin
  (tableau avant/après, ce qui est mesuré ou estimé, prochaine étape). Ne pas s'arrêter entre deux étapes d'un plan validé.
- L'utilisateur teste visuellement et à l'oreille : déboguer dans les simulateurs, peu de lancements
  d'émulateur automatiques, une seule fenêtre d'émulateur à la fois, toujours laisser la version **normale**
  (pas la version de test) dans `build/`.
- Ne jamais piloter son bureau (envoi de touches, captures d'écran) pendant qu'il travaille : tester sans fenêtre.
- Décisions qui lui reviennent (machine cible, fidélité, contrôles, coupes de contenu) : les poser au début, une fois.
