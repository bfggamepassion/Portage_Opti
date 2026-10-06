---
name: cpc-optimisation
description: Techniques d'optimisation Z80 pour Amstrad CPC (464/6128), tirées du désassemblage de Pinball Dreams, Toki GGP et R-Type 128K, du CRTC Compendium de Longshot (différences entre les types de CRTC 0 à 4, durée des instructions, interruptions, temps fixe) et du portage de Ghosts'n Goblins depuis le ZX Spectrum. À utiliser dès qu'on écrit, porte ou optimise un jeu ou une routine pour Amstrad CPC — conversion depuis MSX, ZX Spectrum ou arcade (garder la logique d'origine, afficher avec les moyens du CPC, jamais en émulant l'écran d'origine), moteur d'affichage, défilement, sprites, tuiles, CRTC (R12/R13, ruptures, compatibilité entre CRTC, détection du type), palette, changement de mode, interruptions, code calé au cycle près, banques 128K, chargement disque, compression — même si l'utilisateur ne cite pas la skill ; aussi pour mesurer un coût en NOPs, choisir une architecture d'affichage CPC, ou comprendre un affichage qui ne marche que sur certains CPC ou certains émulateurs.
---

# Optimisation Amstrad CPC

Deux références, à ne pas lire en entier :

- `references/TECHNIQUES_OPTIMISATION_CPC.md` (≈ 850 lignes) : ce que font les jeux, avec le code observé.
  Lis d'abord la section 0 (règles d'or) et la section 14 (check-list), puis seulement les sections utiles à
  la tâche, d'après la première table ci-dessous.
- `references/CRTC_COMPENDIUM.md` (≈ 420 lignes) : ce que fait la **machine**, d'après *The Amstrad CPC CRTC
  Compendium* (Longshot / Logon System). À lire dès qu'on touche au CRTC, au Gate Array ou aux
  interruptions en cours d'image, ou qu'on compte des NOPs précisément. Deuxième table ci-dessous.

Le PDF d'origine (296 pages, `docs/references/ACCC1.11-EN.pdf` du dépôt Portage_Opti) n'est utile que pour le détail
au microseconde : la section 0 de `CRTC_COMPENDIUM.md` dit quelles pages ouvrir.

Si tu produis du code ou un document qui s'appuie sur les informations du Compendium, garde la mention que
sa licence demande : `Technical information sourced from the "Amstrad CPC CRTC Compendium" by Longshot
(CC BY-NC-ND).`

## Démarche

1. **Mesurer avant d'optimiser.** Exprimer chaque coût en **NOPs** (1 NOP = 1 µs ; une image = 19 968 NOPs,
   312 lignes × 64). Table des coûts d'instructions : §2.1. Donner le coût avant/après de toute proposition.
2. **Choisir l'architecture avant le code** (mode, taille d'écran, double tampon ou cases sales, défilement
   matériel ou logiciel, banques). C'est là que se font les plus gros gains (×10 à ×100), pas dans le
   micro-code.
3. **Faire faire le travail au matériel** (CRTC, palette, interruptions) avant de redessiner.
4. **Rendre le travail proportionnel aux changements**, jamais à la taille de l'écran.
5. **Précalculer et pré-ranger** les données dans l'ordre où le code les consomme.
6. Passer la check-list §14 avant de proposer un changement de moteur.
7. **Portage depuis une autre machine** : garder la logique du jeu d'origine (les sensations de jeu),
   mais **refaire l'affichage avec les moyens du CPC** — graphismes mode 0 préparés à l'avance, objets
   immobiles dans le décor, positions lues dans les données du jeu. Ne jamais reconstituer l'écran
   d'origine à partir de ses appels de dessin (Ghosts'n Goblins : 9 images/s ainsi, §15).

## Où chercher dans `TECHNIQUES_OPTIMISATION_CPC.md`

| Besoin | Sections |
|---|---|
| Coûts, temps vidéo, ports, configurations 128K, registres CRTC | §2 |
| Couper le firmware, vecteur d'interruption, détection 128K / type de CRTC, clavier | §3 |
| Banques, trampolines, disquette maison, pilote FDC, Exomizer vs ZX7 | §4, §12.1–12.3 |
| Taille d'écran, double tampon R12, **défilement matériel**, ruptures, code au cycle près | §5 |
| VSYNC, compter les 6 interruptions, rythme de jeu fixe, `HALT` | §6, §12.4 |
| Cycle de couleurs, palette par bande ou par ligne, deux modes dans l'image | §7, §12.5 |
| **Tuiles par la pile + ordre de Gray + zigzag**, sprites masqués par table, tables précalculées | §8 |
| **Moteur de cases sales avec aiguillage**, tuiles en miroir | §12.6 |
| Astuces de code (automodification, `RST`, `JP (HL)`, `EXX`, tables alignées) | §9 |
| Son (lecteur en banque, appel à moment fixe) | §10 |
| Choisir vite entre deux méthodes (tableau de gains) | §11 |
| Exemple complet de portage MSX → CPC avec mesures et options de défilement | §13 |
| **Porter un jeu d'une autre machine** : garder sa logique, refaire l'affichage en CPC ; pièges (ROM appelée par accident, pile détournée, démarrage à froid) ; bandeau fixe par rupture sous un défilement matériel | §15 |

## Où chercher dans `CRTC_COMPENDIUM.md`

| Besoin | Sections |
|---|---|
| Quelles pages du PDF ouvrir | §0 |
| Les cinq types de CRTC, vocabulaire (C0, C4, C9, VMA) | §1 |
| **Quand écrire R12/R13**, longueur de la VSYNC, limites de R2/R3, mode et couleurs, **interruptions**, accès aux ports, écran coupé, plein écran, couture du défilement matériel | §2 |
| Ruptures : règles communes et différences par type | §3 |
| Reconnaître le type de CRTC | §4 |
| Écrire du code à durée fixe, routines d'attente | §5 |
| Astuces Z80 (pages de 256 octets, automodification, déroulage partiel) | §6 |
| **Durée de toutes les instructions en NOPs** | §7 |

## Réflexes à avoir sans relire la référence

- `LDIR` = 6 NOPs/octet, `LDI` = 5, `POP`+`PUSH` ≈ 3,5 : jamais de `LDIR` dans une boucle chaude.
- `JP (HL)` = 1 NOP, `RET` = 3, `CALL` = 5, `RST` = 4, `INC L` = 1 contre `INC HL` = 2, `(IX+d)` = 3 NOPs de
  plus que `(HL)`, entrée dans une interruption = 5. En cas de doute, table complète : Compendium §7.
- Tuile 2 octets × 8 lignes : `POP DE / LD (HL),E / INC L / LD (HL),D` + `SET/RES b,H` dans l'ordre de lignes
  0,1,3,2,6,7,5,4 ≈ 80 NOPs (contre ≈ 128 en boucle). `DI` tant que SP est détourné (l'interruption attend).
- Avec R1 = 32 (64 octets par ligne), 32 rangées remplissent un bloc de 2 Ko : défilement vertical matériel en
  anneau par R12/R13, on ne dessine que la rangée qui entre. Le défilement matériel déplace toute la largeur.
- R12/R13 ne sont pris en compte qu'au début d'une trame CRTC, mais le CRTC 1 les relit pendant toute la
  première rangée et le CRTC 2 les fige sur la dernière ligne : **les écrire juste après la VSYNC**, jamais
  à un moment quelconque.
- Mode 0 : masque d'un octet = `($AA si pixel gauche = 0) | ($55 si pixel droit = 0)` → table de 256 octets
  alignée. Miroir mode 0 : échanger les bits pairs et impairs (`((b&$AA)>>1)|((b&$55)<<1)`).
- Changer une encre dans l'interruption n° k la change pour tout ce qui est affiché sous la ligne 52 × k.
- Un changement de mode n'est appliqué qu'à la HSYNC suivante (ligne entière, pas de calage fin) ; un
  changement de couleur est immédiat, au pixel près.
- `DI` de moins de 32 lignes (≈ 2 000 NOPs) si des interruptions découpent l'écran : au-delà, les
  suivantes sont décalées jusqu'à la VSYNC. Pour tomber au microseconde près, `HALT` avant la zone sensible.
- Se caler sur le **début** de la VSYNC, jamais sur sa fin (8 ou 16 lignes selon le CRTC). Garder
  R2 + R3 ≤ R0 (sinon plus de VSYNC sur CRTC 2) et R3 ≠ 0.
- Les ruptures (changer R4/R6/R7/R9/R12/R13 en cours d'image) dépendent du type de CRTC. Préférer un
  découpage par interruption ; sinon une rupture simple écrite selon les règles communes (Compendium §3.1) ;
  détection et variantes seulement pour le ligne à ligne.
- Un affichage qui marche sur un émulateur ou un CPC et pas sur un autre : penser type de CRTC d'abord
  (Compendium §2 et §3).
