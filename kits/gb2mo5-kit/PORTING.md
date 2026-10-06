# Porter un jeu Game Boy sur Thomson MO5 : méthode

Ce guide tire les leçons du portage de **MO5 Tennis** (Tennis, Nintendo 1989), sur cassette :
- le projet complet est dans `G:\Mon Drive\Coding\Tennis\MO5` ;
- le modèle réutilisable est dans [template/](template/) ;

Les étapes communes (rétro-ingénierie de la ROM, fermeture de la logique, configuration, preuve de fidélité) sont décrites dans [../gb2zx-kit/PORTING.md](../gb2zx-kit/PORTING.md) (§4 à §6). Le principe du traducteur avec analyse des indicateurs vient de [../gb2c64-kit/PORTING.md](../gb2c64-kit/PORTING.md).

---

## 1. Le principe

Le MO5 a un **6809 à 1 MHz** : il faut un **nouveau traducteur**, `tools/gb2m6809.py` (SM83 → 6809, pour asm6809). Le reste est comme ailleurs : la logique du jeu est la ROM traduite, vérifiée pas à pas contre le vrai jeu ; l'affichage, le son et le clavier sont écrits à la main.

## 2. Outils

| Outil | Rôle | Emplacement |
|---|---|---|
| **asm6809 2.17** | Assembleur 6809. `-B` : binaire brut, `-C` : binaire segmenté (le format de `LOADM`) | `%LOCALAPPDATA%\asm6809\asm6809-2.17-w64\asm6809.exe` |
| **DCMOTO** | Émulateur Thomson. ROM incluses. **Pas de ligne de commande** : interface graphique seulement | `%LOCALAPPDATA%\dcmoto\dcmoto-64\dcmoto.exe` |
| `tools/m6809.py` | Émulateur 6809 écrit pour ce projet : cycles, zones d'entrées-sorties | Fourni |
| `tools/test_m6809.py` | Test croisé contre l'émulateur MC6809 de PyPI. Ce dernier a deux bogues (`PULU` avec S, `SEX`), les seules différences restantes | Fourni |
| `tools/mo5sim.py` | MO5 simulé (écran en banques, PIA, clavier, circuit vidéo) : captures, mesures de cadence | Fourni |
| `tools/diff_mo5.py` | Comparaison pas à pas avec le jeu GB (PyBoy), coût d'un pas en cycles | Fourni |
| `tools/make_k7.py` | Cassette `.k7` | Fourni |

**asm6809** :
- pas de `rept` : les tables sont générées en Python (`gfx/tables.asm`) ;
- pas d'étiquettes locales `.x` : utiliser des noms uniques ;
- `setdp` : l'assembleur choisit tout seul l'adressage direct ;
- `bsr` et `bra` ont une portée de ±127 octets : passer à `jsr` / `lbra` quand l'assembleur se plaint.

**DCMOTO** :
- choisir la machine MO5, puis « Supports amovibles », « Charger une cassette » ;
- au BASIC, taper `LOADM"",,R`. Si la frappe passe mal (guillemets, virgule : « error 2 »), utiliser **« Simuler le clavier »** avec la commande dans le presse-papier.

## 3. Le traducteur SM83 → 6809

- **Registres** :
  - A du GB = A du 6809 ;
  - B, C, D, E, H, L du GB en page directe (`rB`…`rL` en `$9F00-$9F05`). Les paires sont dans l'ordre du 6809, octet haut d'abord : `ldx <rH` charge HL ;
  - B, X, U du 6809 sont des brouillons. D contient A : on ne s'en sert qu'en sauvegardant A.
- **Page directe** (DP = `$9F`) : registres GB, variables rapides, HRAM GB (`$9F80`).
- **Indicateurs** : Z et C du 6809 ont le même sens que ceux du GB, y compris C comme emprunt après SUB et CMP (contrairement au 6502). Il reste deux différences :
  - LD, ST et LEAX modifient Z sur 6809, pas sur GB ;
  - AND, OR et XOR ne mettent pas C à 0.

  L'analyse de durée de vie des indicateurs dit, après chaque instruction GB, si Z et C seront lus. Si oui, on ajoute le correctif (`andcc #$FE`, `andcc #$FB` après les rotations RLA et co.) ou la sauvegarde `pshs cc` / `puls cc`. Sinon, rien.
- **Analyse interprocédurale** : au RET d'une routine, seuls comptent les indicateurs lus après *ses* appels. Tennis passe de 429 à 86 sauvegardes. **Piège** : le RET lui-même ne « lit » rien. Ce qui est lu après passe par le successeur `'RET'`, sinon tout reste vivant.
- **Pile** :
  - CALL → JSR, RET → RTS ;
  - PUSH AF / POP AF → `pshs a,cc` / `puls a,cc`. Dans Tennis, les paires sont toujours appariées : vérifier que c'est le cas dans le nouveau jeu ;
  - les adresses de code empilées (`CODE_PTRS`) marchent telles quelles : `pshs x` puis `rts`.
- **RST** du GB (`$08` table de sauts, `$18` lecture, `$28` copie) : réécrits à la main dans `gb_support.asm`, avec les mêmes effets sur les registres GB que la version Z80.
- **Données de la ROM** (`DATA_BLOCKS`) : une table de pointeurs lue octet par octet par la logique GB doit rester **en ordre GB (octet bas d'abord)**, donc `fcb lo,hi` et non `fdb`. Dans Tennis, c'était la table des fiches de niveau. Avec `fdb`, l'IA de l'adversaire ne bougeait plus.

## 4. Vérifier : attention aux chemins que la comparaison ne voit pas

`diff_mo5.py` part d'états du vrai GB. Tout ce qui s'exécute **avant** (initialisation du match, fiches chargées une fois) n'est donc pas couvert. Deux bogues de Tennis ont échappé à la comparaison :
- la table de pointeurs en `fdb` ;
- un service mal minuté, qui n'était pas un bogue : c'est la règle du GB.

Il faut donc aussi :
- **comparer l'initialisation** (`gb_new_match`) avec la version Z80, pour chaque niveau ;
- **rejouer les touches d'une vraie partie** dans le MO5 simulé, puis comparer chaque pas à la version Z80 depuis le même état : c'est `tools/check_ticks_vs_z80.py`, qui s'appuie sur la version ColecoVision de Tennis.

## 5. Matériel du MO5 (faits tirés des sources de MAME, `src/mame/thomson/`)

| Zone | Contenu |
|---|---|
| `$0000-$1FFF` | Écran : banque **forme** si le bit 0 de `$A7C0` vaut 1, banque **couleur** sinon |
| `$2000-$9FFF` | RAM (moniteur et BASIC en bas) |
| `$A7C0-$A7C3` | PIA système (PA, PB, CRA, CRB) |
| `$A7CC-$A7CF` | PIA de l'extension jeux (joysticks, son 6 bits) : optionnelle |
| `$A7E4-$A7E7` | Circuit vidéo (crayon optique) |

- Écran 320×200, 40 octets par ligne. **Octet de couleur** : 4 bits hauts = couleur des bits à 1, 4 bits bas = couleur des bits à 0.
- Palette : 0 noir, 1 rouge, 2 vert, 3 jaune, 4 bleu, 5 magenta, 6 cyan, 7 blanc, 8 gris, 9 rose, 10 vert clair, 11 jaune clair, 12 bleu clair, 13 parme, 14 cyan clair, 15 orange.
- `$A7C0` : bit 0 = banque, bits 1-4 = bordure.
- **Clavier** :
  - écrire dans `$A7C1` le code colonne << 1 | (7 − ligne) << 4, puis lire le bit 7 (0 = appuyée) ;
  - codes : haut `$62`, gauche `$52`, bas `$42`, droite `$32`, ESPACE `$40`, ENTRÉE `$68`, S `$46`, B `$44`, M `$34`, 1-4 `$5E $4E $3E $2E` ;
  - le bit 0 de `$A7C1` est le buzzer : le garder dans l'état voulu.
- **Synchro** : le bit 7 de `$A7E7` vaut 1 pendant les 200 lignes de l'image. On compte les trames sur son passage de 1 à 0, en l'interrogeant souvent : attente, clavier, chaque case redessinée, entre les pas de jeu. **Ne pas utiliser l'indicateur 50 Hz du PIA** (bit 7 de `$A7C3`) : dans DCMOTO, il ne se comporte pas comme prévu et le jeu tournait beaucoup trop vite.
- Trame : 312 lignes de 64 µs = **19 968 cycles**.

## 6. Affichage sans sprites matériels : recomposition par cases

- Même disposition que la version CPC : le stade GB (256 pixels) est en colonnes 4-35, le score dans les marges.
- Tuiles 8×8 du décor : 8 octets de forme et 8 de couleur. Dans chaque groupe de 8 pixels, la couleur la plus présente devient celle des bits à 0. Un groupe d'une seule couleur prend le noir pour les bits à 1.
- Un objet a deux plans d'un bit : **masque** (pixels opaques) et **encre** (pixels foncés, dans la couleur de l'objet). Les pixels clairs laissent voir le fond du groupe.
- Quand un objet bouge ou change d'image, les cases de son ancien et de son nouveau rectangle sont marquées. Chaque case marquée est **recomposée d'un seul coup** : tuile, puis objets (forme = fond AND NOT masque OR encre ; couleur des bits à 1 = celle de l'objet s'il y a de l'encre). Ensuite, 8 octets de forme et 8 de couleur sont écrits. Il n'y a jamais d'état effacé à l'écran, donc pas de clignotement.
- Image décalée de `x AND 7` pixels, refaite seulement si l'image ou le décalage change. Le 6809 décale un octet en une multiplication : `MUL` par 2^(8−s) donne `octet >> s` dans A et le reste dans B.
- Tennis : 45 images par seconde en moyenne au simulateur, la logique gardant le rythme du GB (6 pas pour 5 trames).

## 7. Cassette et chargement

- `.k7` MO5 : blocs précédés d'octets `$01`, puis `$3C $5A`, type (0 en-tête, 1 données, `$FF` fin), taille (= données + 2), données, somme (somme des données + somme = 0).
- En-tête : nom (8), extension (3), type 2 (binaire), mode 0.
- Données : la sortie `asm6809 -C` (segments `$00 longueur adresse données`, fin `$FF $00 $00 lancement`).
- Tennis se charge en **`$3000`** (`LOADM"",,R`), au-dessus de l'espace du BASIC. Zone de travail en `$9400-$9BFF`, pile en `$9C00`, RAM GB en `$9D00`.

## 8. Son

Buzzer à 1 bit (bit 0 de `$A7C1`) : un son est une rafale de demi-périodes jouée d'un coup (2 à 4 ms), pendant laquelle le jeu s'arrête. Bruit : demi-période tirée au hasard. On ne touche jamais au hasard du jeu GB (`H_RNG`).

## 9. Jouabilité (retours de l'utilisateur)

- **Un seul bouton** (ESPACE), avec le lob automatique quand l'adversaire est au filet.
- Le réglage « coups du joueur −10 % » est gardé : sans lui, les balles sortent trop.
- Service au GB : il faut frapper la balle **pendant qu'elle monte** (hauteur < ~80). Au sommet ou après, c'est une faute.

## 10. Chiffres (Tennis)

| Élément | Valeur |
|---|---|
| Logique traduite | 11,6 Ko |
| Programme complet | 23,8 Ko |
| Coût d'un pas | 4 600 cycles en moyenne, 9 700 au pire |
| Décor | 109 tuiles (1,7 Ko) |
| Sprites | 5,3 Ko |
