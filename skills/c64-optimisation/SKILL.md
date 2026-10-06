---
name: c64-optimisation
description: Techniques d'optimisation 6502 pour Commodore 64, tirées du désassemblage et du profilage au cycle près de Galencia, Zeta Wing et Sam's Journey (défilement étalé sur plusieurs images, couleur RAM, double tampon, multiplexeur de sprites et tri, interruptions raster stables, bords ouverts, code automodifié, chargeur et décompression), avec des outils pour mesurer un jeu dans VICE. À utiliser dès qu'on écrit, porte ou optimise un jeu ou une routine pour C64 — moteur d'affichage, défilement, sprites, IRQ raster, VIC-II ($D011, $D016, $D018), organisation mémoire, vitesse insuffisante, image qui saccade ou se déchire, sprites qui clignotent, portage d'un jeu d'une autre machine (afficher avec les sprites et caractères du C64, jamais en émulant l'écran d'origine) — même si l'utilisateur ne cite pas la skill ; aussi pour chiffrer un coût en cycles, choisir une architecture d'affichage, profiler un .prg ou un .d64 dans VICE, ou analyser le code d'un jeu C64 existant.
---

# Optimisation Commodore 64

Une référence et cinq outils :

- `references/TECHNIQUES_OPTIMISATION_C64.md` (≈ 800 lignes) : ce que font trois jeux réputés, avec le code
  observé et les coûts mesurés. **Ne pas le lire en entier** : lire la section 0 (règles d'or) et la
  section 12 (check-list), puis les sections utiles d'après la table ci-dessous.
- `tools/` : extraction de disquette, pilotage de VICE, désassembleur, profileur (référence §13).

## Démarche

1. **Chiffrer avant d'optimiser.** Tout coût s'exprime en cycles : une image PAL = 19 656 (312 × 63),
   environ 18 000 utiles une fois déduits les badlines et les sprites. NTSC : 17 095. Donner le coût avant
   et après pour chaque proposition.
2. **Mesurer le vrai programme** quand il existe : `tools/vicemon.py` pour capturer une trace,
   `tools/prof.py` pour la lire. La part de temps passée dans la boucle d'attente est la marge réelle.
3. **Choisir l'architecture avant le code** (pour un portage, voir la section suivante : sprites et
   décor C64, jamais d'émulation de l'écran d'origine) : banque VIC, un ou deux écrans, taille et couleur des tuiles,
   zone de jeu et panneau, nombre de sprites. Les gains d'un facteur 3 à 10 sont là ; le micro-code
   rapporte 10 à 30 %.
4. **Un travail qui ne tient pas dans une image se découpe** en phases, une par image (§6).
5. **Sortir le calcul des interruptions** : le programme principal écrit les valeurs dans le code de
   l'IRQ, qui ne fait que les poser (§4.3).
6. Passer la check-list §12 avant de proposer un moteur ou un changement de moteur.

## Porter un jeu d'une autre machine : afficher en C64, ne pas émuler l'écran d'origine

Règle prioritaire pour tout portage (Oric, Spectrum, CPC, Game Boy, MSX…). Le but est la même
sensation de jeu (physique, déplacements, vitesse, collisions), pas la copie de l'écran source.

- **La logique d'origine peut rester** (même CPU, ou code traduit), mais **l'affichage se refait avec
  le VIC-II** : sprites matériels pour tout ce qui bouge (couleurs propres, positionnement au pixel,
  aucun coût de dessin), jeu de caractères ou bitmap pour le décor fixe, tracé une seule fois par
  niveau ; registres de couleur, couleur RAM et caractères redéfinis pour les animations de décor.
- **Ne jamais convertir en continu la mémoire écran de la machine source** vers le bitmap C64 (octets
  de 6 pixels Oric, attributs série, écran Spectrum…). Mesuré sur un portage Oric → C64 : la
  conversion, même optimisée (conversion immédiate, copies natives, lignes inchangées sautées),
  laissait le jeu 2 à 4 fois trop lent et gardait le débordement de couleur ; le moteur a été
  abandonné au profit des sprites.
- **Si la logique relit son écran pour les collisions**, garder cet écran source en RAM comme **carte
  de collisions invisible** : le jeu y écrit au même coût que sur la machine d'origine, rien n'est
  converti. On intercepte ses routines de dessin d'objets pour placer les sprites (position tirée
  de ses variables ou de l'adresse de tracé), et on ne convertit que le décor, au changement de
  niveau ou quand il change vraiment.
- **Vitesse d'origine** : si l'affichage ne coûte plus rien, les boucles d'attente du jeu donnent la
  même vitesse ; sinon, les remplacer par une attente qui déduit le temps passé par le moteur.
- **Limites à chiffrer avant de coder** : 8 sprites par ligne (multiplexeur §5 ou objets nombreux et
  petits en caractères/bitmap), 21 lignes et 24 pixels par sprite (superposer ou empiler), une
  couleur par sprite hires (superposition pour les personnages multicolores), 200 lignes visibles
  (panneau de score dans le bord ou sur le côté).
- **Valider cette architecture avec l'utilisateur avant d'écrire un moteur** : c'est le choix qui
  décide de la vitesse et du rendu.

## Où chercher dans la référence

| Besoin | Sections |
|---|---|
| Cycles par image, badlines, coût des instructions, registres VIC | §2 |
| Banque VIC, `$01`, RAM sous les E/S, installer l'IRQ en `$FFFE` | §3.1, §3.2 |
| Décompression Exomizer à la demande ou pendant le chargement | §3.3 |
| Allocateur mémoire à deux piles | §3.4 |
| Chargeur rapide qui marche écran allumé | §3.5 |
| PAL / NTSC | §2.1, §3.6 |
| Chaîne d'IRQ, acquittement, sauvegarde des registres | §4.1, §4.2 |
| **IRQ à immédiats patchés (« liste d'affichage »)** | §4.3 |
| Raster stable, compensation du défilement vertical | §4.4, §4.5 |
| Coupure jeu / panneau, bande noire par mode invalide | §4.6 |
| Bords haut et bas ouverts, score en sprites | §4.7 |
| Dégradés, barres de couleur | §4.8 |
| **Multiplexeur de sprites** : comparaison de trois, tri, placement des IRQ | §5 |
| Longueur variable d'un code déroulé (`RTS` posé, entrée calculée) | §5.3, §5.4 |
| **Défilement vertical en 8 phases** | §6.1 |
| **Couleur RAM moins chère par le choix des tuiles** | §6.2 |
| **Défilement 8 directions, copie devant le faisceau** | §6.3, §6.4 |
| Champ d'étoiles et décors animés par le jeu de caractères | §7 |
| Synchronisation, attente productive, tableaux parallèles, aiguillages, joystick | §8 |
| Astuces de code 6502 | §9 |
| Budget du son | §10 |
| Choisir vite entre deux méthodes (tableau de gains mesurés) | §11 |
| Profiler un jeu dans VICE | §13 |

## Réflexes à avoir sans relire la référence

- Copier un octet : `LDA abs,X / STA abs,X` = 9 cycles ; `LDA (zp),Y / STA (zp),Y / INY` = 13 ; tout
  déroulé en `abs` = 8. Déplacer 1 000 cases = 9 000 cycles : écran + couleur ne tiennent pas dans une
  image.
- La couleur RAM (`$D800`) est unique, ni déplaçable ni doublable. Soit les tuiles en réduisent le coût
  (N × M cases d'une seule couleur → coût divisé par environ N × M), soit on la copie devant le
  faisceau : le haut pendant que le faisceau est en bas, le bas pendant qu'il retraverse le haut.
- Deux écrans (`$D018`) : écrire les pointeurs de sprites (`écran + $3F8`) dans les deux.
- `$01 = $35`, vecteur en `$FFFE`, `LDA #$7F / STA $DC0D` : l'entrée d'IRQ coûte 7 cycles.
- Acquitter par `DEC $D019` (ou `INC`, `LSR`) : aucun registre touché. Une IRQ qui ne fait que
  `LDA #imm / STA` ne sauve que A (`PHA … PLA`). S'il faut les trois registres : page zéro
  (`STA/STX/STY zp`), 18 cycles aller-retour contre 29 par la pile.
- Avant de programmer l'IRQ suivante, comparer sa ligne à `$D012` : si elle est passée ou à moins de 2–3
  lignes, enchaîner sans `RTI`. Une IRQ posée dans le passé ne tombe qu'à l'image suivante.
- Coupure visible : double IRQ (`TSX / CLI / JMP *`, puis `TXS` dans la seconde), et si l'écran défile
  verticalement, retard par table indexée par `$D011 & 7`.
- Tri des sprites : insertion sur l'ordre de l'image précédente, indices en page zéro, code déroulé.
  Rejeter les sprites hors écran avant de trier.
- Code déroulé de longueur variable : poser un `RTS` ($60) à l'étage voulu, appeler, remettre l'opcode.
- Objets en tableaux parallèles indexés par X (`LDA champ,X`), boucle de N−1 à 0.
- État qui change rarement : patcher l'opérande d'un `JMP`. État choisi à chaque appel : table +
  `PHA / PHA / RTS` (adresses − 1).
- Code automodifié lu par une IRQ : écrire la valeur sous `SEI`, ou en une seule instruction.
- Décor répétitif animé (étoiles, pluie, eau) : modifier quelques octets du jeu de caractères, pas
  l'écran.
- Musique : 600 à 1 000 cycles par image, appelée en bas d'écran après les écritures vidéo sensibles.
- Les opcodes illégaux ne sont pas nécessaires : aucun des trois jeux n'en exécute en jeu.

## Mesurer un programme

```python
import sys; sys.path.insert(0, "<dossier de la skill>/tools")
from vicemon import Vice
v = Vice(["-autostart", "build/game.prg"])      # ou un .d64
v.run_to(30e6)                                   # cycles émulés ; ~1 s réelle pour 10 M
v.joy_auto(0x02a7); v.joy_cell(0x18)             # joystick 2 simulé : 1 haut, 2 bas, 4 gauche, 8 droite, $10 feu
v.run_for(3e6)
v.dump("out/jeu"); v.history("out/jeu.chis", 150000)
v.quit()
```
Puis :
```
python tools/state.py out/jeu                # mode vidéo, banque, sprites, carte mémoire
python tools/prof.py out/jeu.chis            # temps par bloc de code (le 1er est souvent la boucle d'attente)
python tools/prof.py out/jeu.chis subs       # temps par sous-programme
python tools/prof.py out/jeu.chis irq        # chaque interruption : écart, adresse, durée
python tools/dis6502.py out/jeu.ram dis 1000 10ff
python tools/dis6502.py out/jeu.ram xrange d000 d02e     # qui écrit dans le VIC
```

Pièges connus :
- `vicemon.py` contient le chemin de VICE 3.10 sous Windows (`%LOCALAPPDATA%\VICE\…\x64sc.exe`) :
  l'adapter en tête de fichier si besoin.
- Sans fenêtre visible, VICE cale à vitesse normale : le pilote force le mode accéléré.
- `joy_auto` redirige les lectures de `$DC00` présentes en RAM à cet instant ; le refaire après chaque
  chargement de code. Choisir une case que le programme n'utilise pas, jamais dans `$0100–$01FF`, et ne
  pas l'écrire pendant une décompression.
- Les chiffres de la référence sont PAL. Pour du NTSC, relancer les mesures.
