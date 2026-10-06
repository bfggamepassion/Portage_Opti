# Techniques d'optimisation Commodore 64 — référence pour jeux et portages

> **À qui s'adresse ce document** : à Claude (ou à tout développeur) qui écrit ou optimise du code 6502
> pour Commodore 64, en particulier un moteur de jeu ou un **portage**.
> Il est autonome : copie-le tel quel dans un autre dépôt.
>
> **D'où viennent ces techniques** : du désassemblage et du profilage, dans VICE, de trois jeux réputés
> pour leur technique (dépôt Opti-C64). Chaque technique indique le jeu, l'adresse et le code réellement
> observés. Les coûts sont en **cycles** (1 cycle ≈ 1 µs en PAL) et, quand c'est écrit « mesuré », ils
> viennent d'une trace d'exécution datée au cycle, pas d'un calcul.
>
> **Ce que ce document n'est pas** : un cours sur le VIC-II. Les faits matériels de la section 2 sont le
> minimum pour lire la suite ; ils viennent de la connaissance générale de la machine, pas des jeux.

---

## 0. Règles d'or (à appliquer avant tout)

1. **Compter en cycles.** Une image PAL = **19 656 cycles** (312 lignes × 63). Les 25 « badlines » en
   volent ~40 chacune et chaque sprite affiché 2 par ligne : il reste **≈ 18 000 cycles** utiles.
2. **Mesurer avant d'optimiser.** `tools/vicemon.py` + `tools/prof.py` donnent le coût réel de chaque
   routine (§13). Les trois jeux ont de la marge : 35 à 67 % du temps passé à attendre (§11).
3. **Un travail trop gros pour une image se découpe**, il ne s'accélère pas. Les deux jeux à défilement
   répartissent la copie d'écran sur 2 à 8 images (§6). C'est le plus gros gain du corpus.
4. **Faire faire le travail au VIC-II** : défilement fin par `$D011`/`$D016`, double tampon par `$D018`,
   fond animé par le jeu de caractères, score en sprites dans les bords.
5. **Sortir les calculs des interruptions.** Le programme principal prépare, l'IRQ ne fait que
   `LDA #imm / STA registre` avec des immédiats écrits à l'avance (§4.3).
6. **Dérouler les boucles chaudes et régler leur longueur en patchant le code** (un `RTS` posé, un
   `JMP` calculé) plutôt qu'avec un compteur (§5.3, §9).
7. **Concevoir les graphismes pour le moteur** : tuiles d'une seule couleur, de 3 × 2 caractères, et la
   couleur RAM coûte trois fois moins cher à déplacer (§6.2).
8. **Couper le KERNAL** (`$01 = $35`, vecteur `$FFFE` en RAM) : l'entrée d'interruption passe de ~36 à
   7 cycles et on récupère la RAM sous les ROM.

---

## 1. Corpus analysé et limites

| Disquette | Jeu | Ce qui a été analysé |
|---|---|---|
| `Galencia.d64` | **Galencia** (Jason Aldred, édité par Protovision) — tir fixe façon Galaga | boot, intro, jeu : chaîne d'IRQ, multiplexeur 31 sprites, tri, bords ouverts, champ d'étoiles, collisions, Exomizer |
| `Zeta_Wing_v1.2.2_+6D_[ExCeSs].d64` | **Zeta Wing** v1.2.2 (Sarah Jane Avory) — tir à défilement vertical. Version crackée par Excess (intro, visionneuse, trainer devant le jeu : non analysés) | jeu : défilement vertical en 8 phases, couleur RAM, multiplexeur 24 sprites à IRQ pré-cuite, tri |
| `1.d64` à `4.d64` | **Sam's Journey** (Knights of Bytes, code Chester Kollschen) — plates-formes à défilement 8 directions | titre, menu, carte, niveau : défilement, couleur RAM, IRQ stables, multiplexeur, boucle principale, chargeur, allocateur, décompression |

**Méthode.** Chaque jeu est lancé dans VICE piloté par script (joystick simulé), puis : dump de la RAM et
des registres, désassemblage, et trace des 120 000 à 190 000 dernières instructions avec leur date en
cycles. Les adresses données sont celles de la RAM au moment du dump.

**Limites.**
- Un seul niveau de Sam's Journey (forêt, disque 2) et le premier niveau des deux autres ont été tracés.
  Les mesures valent pour ces scènes.
- Code du lecteur 1541 de Sam's Journey, lecteurs de musique, écran-titre à parallaxe de Sam's Journey :
  repérés, pas décortiqués.
- Galencia existe en deux binaires, `GALPAL` et `GALNTSC` ; seul le PAL a été exécuté. Tous les chiffres
  sont PAL.
- Le Zeta Wing analysé est une version modifiée par un groupe de crack ; le moteur est celui du jeu, mais
  quelques octets (trainer) peuvent différer de l'original.

---

## 2. La machine en chiffres

### 2.1 Temps

| | PAL (6569) | NTSC (6567R8) |
|---|---|---|
| Cycles par ligne | 63 | 65 |
| Lignes par image | 312 | 263 |
| Cycles par image | **19 656** | 17 095 |
| Images par seconde | 50,12 | 59,83 |

- **Badline** : sur chaque ligne où `(ligne & 7) == (YSCROLL)` dans la zone d'affichage (lignes $30–$F7),
  le VIC prend le bus 40 à 43 cycles pour lire 40 codes de caractères. 25 badlines par image ≈ 1 000
  cycles. Conséquence : une écriture calée au cycle près ne tombe pas au même endroit selon `YSCROLL`
  (voir §4.5).
- **Sprites** : chaque sprite affiché sur une ligne coûte 2 cycles (+ jusqu'à 3 d'arrêt du bus). 8 sprites
  sur une ligne : ~19 cycles perdus sur 63.
- **Interruption** : 7 cycles pour entrer, 6 pour `RTI`, et l'instruction en cours se termine d'abord
  (gigue de 0 à 7 cycles).

### 2.2 Coût des instructions utiles

| Instruction | Cycles | | Instruction | Cycles |
|---|---|---|---|---|
| `LDA #imm` | 2 | | `STA abs` | 4 |
| `LDA zp` / `STA zp` | 3 | | `STA abs,X` / `abs,Y` | 5 |
| `LDA abs` | 4 | | `STA (zp),Y` | 6 |
| `LDA abs,X` / `abs,Y` | 4 (+1 si page franchie) | | `INC abs` / `DEC abs` | 6 |
| `LDA (zp),Y` | 5 (+1) | | `INX` `DEY` `TAX` `ASL A` `NOP` | 2 |
| `BIT zp` / `BIT abs` | 3 / 4 | | branche non prise / prise | 2 / 3 (+1 page) |
| `JMP abs` | 3 | | `JMP (ind)` | 5 |
| `JSR` | 6 | | `RTS` / `RTI` | 6 |
| `PHA` | 3 | | `PLA` | 4 |

Copier un octet : `LDA abs,X / STA abs,X` = **9** ; `LDA (zp),Y / STA (zp),Y / INY` = **13** ;
`LDA abs / STA abs` (tout déroulé) = **8** ; un `LDA` pour trois `STA abs` = **5,3 par octet**.

### 2.3 Registres qui servent partout

| Registre | Rôle |
|---|---|
| `$D011` | bits 0–2 défilement vertical fin, bit 3 : 25/24 rangées, bit 4 : écran allumé, bit 5 bitmap, bit 6 ECM, bit 7 : bit 8 de la ligne raster |
| `$D012` | ligne raster (lecture) / ligne de l'IRQ (écriture) |
| `$D016` | bits 0–2 défilement horizontal fin, bit 3 : 40/38 colonnes, bit 4 multicolore |
| `$D018` | bits 4–7 : écran (× $400), bits 1–3 : jeu de caractères (× $800), dans la banque VIC |
| `$DD00` | bits 0–1 : banque VIC de 16 Ko (inversés : %00 = $C000) |
| `$D019` / `$D01A` | acquittement / masque des IRQ VIC |
| `$D015`, `$D000–$D010`, `$D027–$D02E` | sprites : activation, positions, couleurs |
| `$D017` / `$D01D` / `$D01C` / `$D01B` | sprites : double hauteur / double largeur / multicolore / priorité |
| `$01` | `$37` tout visible, `$35` RAM + E/S (pas de ROM), `$34` RAM partout |
| `$D800–$DBE7` | couleur RAM : fixe, 4 bits, **impossible à déplacer ou à doubler** |

Les pointeurs d'images des sprites sont les 8 derniers octets de l'écran (`écran + $3F8`). Avec deux
écrans, il faut les écrire **dans les deux**.

---

## 3. Démarrage et organisation mémoire

### 3.1 Tout le monde en banque VIC $C000, sans ROM

Les trois jeux font le même choix :

| | Banque VIC | Écran(s) | Caractères | `$01` | IRQ |
|---|---|---|---|---|---|
| Galencia | $C000 | $C000 | $F800 | $35 | `$FFFE` en RAM |
| Zeta Wing | $C000 | $C000 + $C400 | $F000 | $35 | `$FFFE` en RAM |
| Sam's Journey | $C000 | $C000 + $C400 | $C800 (jeu), $F800 (panneau) | $35 | `$FFFE` en RAM |

Intérêt : tout le graphisme vit en haut de la mémoire, **sous** les ROM et les E/S, et laisse $0800–$BFFF
d'un seul tenant au code et aux données.

**RAM sous les E/S.** Le VIC lit toujours la RAM, jamais les E/S. Les 4 Ko de RAM en $D000–$DFFF, que le
processeur ne voit pas tant que les E/S sont visibles, servent donc de réserve graphique gratuite : Sam's
Journey y range des sprites (pointeur $7F → $DFC0 ; en jeu $62 → $D880, $43 → $D0C0), et son écran-titre
y met son jeu de caractères (`$D018 = $05` → $D000). Pour y écrire : `SEI`, `$01 = $34`, copier,
`$01 = $35`, `CLI`.

**Vecteur NMI neutralisé.** Sam's Journey pointe `$FFFA` sur `$01FF` où se trouve un `RTI` : la touche
RESTORE ne peut plus planter le jeu.

### 3.2 Interruption en RAM : 7 cycles au lieu de ~36

Avec `$01 = $35`, l'IRQ saute directement à l'adresse en `$FFFE/$FFFF`. Par le KERNAL (`$0314`), on paie
la sauvegarde des trois registres et le test BRK avant même d'arriver chez soi.

Séquence d'installation observée (Galencia, `$521F`) :
```
LDA #$01 : STA $D01A      ; IRQ raster seulement
LDA #<irq : STA $FFFE
LDA #>irq : STA $FFFF
LDA #$7F : STA $DC0D      ; coupe les IRQ du CIA 1
LDA #$00 : STA $D012
```
Intro de Galencia (`$6DC3`) ajoute `LDA $DC0D / LDA $DD0D` (vide les IRQ en attente) et `LSR $D019`.

### 3.3 Décompression à la demande (Exomizer)

- **Galencia** garde des segments compressés en mémoire et les décompresse entre l'intro et le jeu :
  `LDX #<src / LDY #>src / JSR $788E`, avec `$01 = $34` pendant l'opération pour écrire partout
  (`$08DC–$08FF`). La routine en `$788E` est le décompresseur Exomizer (table de 52 entrées).
- **Sam's Journey** branche le même type de décompresseur sur une **source d'octets interchangeable** :
  un `JMP` automodifié (`$13EC : JMP $13EF`) pointe soit sur une lecture mémoire, soit sur l'octet suivant
  du chargeur (`$1217`). On décompresse **pendant** le chargement, sans tampon intermédiaire.

### 3.4 Allocateur à deux piles (Sam's Journey, `$1292–$13C2`)

La zone $8000–$BFFE est gérée par deux piles qui se font face :
- pile basse, qui monte (`$1292/$1293`) : `$12C0` alloue X/Y octets, `$1314` dépile ;
- pile haute, qui descend (`$1294/$1295`) : `$1344` alloue, `$139C` dépile ;
- chaque bloc mémorise le pointeur précédent ; l'allocation échoue (carry) si les deux piles se croisent.

Usage type : ce qui dure (monde, héros) d'un côté, ce qui change à chaque niveau de l'autre. Libérer un
niveau = dépiler, sans fragmentation. C'est ce qui permet 4 disquettes de contenu dans 64 Ko.

### 3.5 Chargeur rapide tolérant (Sam's Journey, `$118C–$126C`)

Protocole à **2 bits par échange, cadencé par l'ordinateur** :
```
LDY #$08
BIT $DD00        ; N = DATA, V = CLOCK : deux bits lus d'un coup, sans toucher A
STY $DD00        ; bascule ATN : « envoie les deux suivants »
BMI + : ORA #$20
+ BVS + : ORA #$80
```
Quatre échanges par octet. Comme c'est le C64 qui donne le rythme, la durée entre deux échanges est
libre : le chargement marche **écran allumé, sprites affichés et interruptions actives** (musique pendant
le chargement). Les octets arrivent par blocs de 256 dans un tampon (`$1040`), et `$1217` sert d'« octet
suivant » avec pointeur automodifié (`LDA $1099` dont l'opérande est incrémenté).

`BIT abs` pour lire deux lignes d'un port dans N et V est réutilisable pour tout port dont les bits 6 et
7 sont intéressants.

### 3.6 Deux binaires plutôt qu'un code adaptatif (Galencia)

Le boot charge `GALPAL` ou `GALNTSC` selon la machine (`$C11F` : `LDA $C198 / CMP #$03`). Toutes les
lignes raster, durées et tables sont figées à l'assemblage pour chaque norme : aucune table double ni
test à l'exécution dans les IRQ.

---

## 4. Interruptions raster

### 4.1 La chaîne : chaque IRQ programme la suivante

Schéma commun : acquitter, écrire les registres, poser la ligne et le vecteur de la suivante, `RTI`.

Galencia en jeu, 10 à 20 IRQ par image (mesuré) :

| Ligne | Adresse | Rôle | Durée |
|---|---|---|---|
| $E4 | `$3F59` | musique (`JSR $8003`) | ~1 000 |
| $FA | `$3C04` | ouvre le bord bas, incrémente le compteur d'image, place les 8 sprites du bas | 279 |
| $FF | `$3CCF` | referme (25 rangées), bit 8 du raster | 65 |
| $105–$10F | `$3CEC`, `$3D11`, `$3D36` | couleurs des sprites du bas | 76 |
| $01 | `$3D5B` | place les 8 sprites du score dans le bord haut | 231 |
| $23, $27, $2D | `$3EAE`, `$3EE7`, `$3F20` | dégradé de couleur sur le score | 129 |
| $32 | `$526C` | multiplexeur : 8 premiers sprites | 524 |
| … | `$53FA`… | un sprite réutilisé par IRQ | 71 |

Sam's Journey : 3 IRQ par image seulement (`$20D3` ligne 0, `$2508`+`$2523` lignes $CB/$CD, `$258E`
ligne $D5), plus celles du multiplexeur quand il y a plus de 8 sprites.
Zeta Wing : une IRQ en bas (ligne $F6) qui fait tout, puis une par sprite réutilisé.

### 4.2 Économies d'entrée et de sortie

**Acquitter sans toucher à A.** `DEC $D019` (Galencia), `INC $D019` (Zeta Wing), `LSR $D019` : 6 cycles,
3 octets, aucun registre abîmé. L'instruction relit puis réécrit la valeur, ce qui remet à zéro le bit
levé. (Variante quand A est déjà sauvé : `LDA #$01 / STA $D019`, Sam's Journey.)

**Ne sauver que ce qu'on utilise.** Les IRQ « liste d'affichage » de Galencia et Zeta Wing ne touchent
qu'à A : `PHA … PLA / RTI`. Coût fixe : 7 (entrée) + 3 + 4 + 6 = 20 cycles.

**Sauver en page zéro plutôt que sur la pile** quand il faut les trois :
```
STA $12 : STX $13 : STY $14        ; 9 cycles   (Sam's Journey $20D3, Galencia $526C avec $02–$04)
…
LDA $12 : LDX $13 : LDY $14 : RTI  ; 9 cycles
```
contre `PHA/TXA/PHA/TYA/PHA` (13) et `PLA/TAY/PLA/TAX/PLA` (16). Gain : 11 cycles par IRQ. Condition :
les IRQ ne s'imbriquent pas (ou chaque niveau a ses propres cases).

**L'urgent d'abord.** Intro de Galencia (`$6DE8`) :
```
PHA
LDA #$10 : STA $D016      ; les écritures visibles tout de suite
LDA #$0C : STA $D022
…
TXA : PHA : TYA : PHA     ; le reste de la sauvegarde ensuite
```
Les écritures sensibles tombent au plus près du début de ligne ; la sauvegarde de X et Y, qui ne presse
pas, vient après.

### 4.3 L'IRQ « liste d'affichage » : des immédiats écrits à l'avance

C'est la technique commune aux trois jeux. L'IRQ ne contient que des `LDA #imm / STA $D0xx` ; le
programme principal **écrit les valeurs dans les opérandes** pendant qu'il a le temps.

- **Galencia**, score en sprites : `$0A26 : LDA #$11 / STA $3D67,X` avec X qui avance de 5 (la taille
  d'un `LDA #imm / STA abs`). Chaque chiffre du score est un immédiat de l'IRQ `$3D5B`.
- **Zeta Wing**, multiplexeur entier : `$380C` et `$346F` remplissent, pour chaque sprite, Y, X, bit 8,
  couleur et image dans le code d'IRQ (`STX $2FBC`, `STX $2FC1`, `STA $2FC6`…). L'IRQ d'un sprite
  (`$2FB7`) ne fait **aucune lecture de table** :
  ```
  PHA : INC $D019
  LDA #$F5 : STA $D001     ; Y      (immédiat patché)
  LDA #$7E : STA $D000     ; X
  LDA #$00 : STA $D010     ; bits 8, valeur complète déjà calculée
  LDA #$89 : STA $C3F8 : STA $C7F8   ; image, dans les deux écrans
  LDA #$9B : STA $D027     ; couleur
  ```
- **Sam's Journey**, réglages de l'image (`$20D9`) :
  ```
  LDA #$00 : ORA #$10 : STA $D011    ; l'immédiat $00 = défilement vertical, patché en $20DA
  LDA #$07 : ORA #$10 : STA $D016    ; défilement horizontal, patché en $20E1
  LDA #$C4 : ASL : ASL : ORA #$02 : STA $D018   ; page d'écran, patchée en $20E8
  ```
  La boucle principale recopie les trois valeurs d'un coup, sous `SEI`, juste après la synchro
  (`$47ED–$4806`) : l'image suivante prend les trois nouvelles valeurs ou aucune, jamais un mélange.

Pourquoi c'est rentable : `LDA #imm` = 2 cycles contre 4 à 5 pour une lecture indexée, pas d'index à
gérer, donc pas de X/Y à sauver, et tout le calcul (bits 8, masques) se fait hors de la zone critique.

Même idée pour les **drapeaux** : Zeta Wing code « y a-t-il encore un sprite ? » par
`LDA #$00 / BNE +3 / JMP fin` dont l'immédiat est patché (`$2FE1`).

### 4.4 Raster stable par double IRQ (Sam's Journey, `$2508`)

Pour couper l'écran proprement entre le jeu et le panneau, il faut écrire à un cycle précis. Méthode :
```
$2508  STX $13
       LDX #$01 : STX $D019
       LDX #$CD : STX $D012          ; 2e IRQ deux lignes plus bas
       LDX #<$2523 : STX $FFFE
       LDX #>$2523 : STX $FFFF
       TSX                           ; mémorise la pile
       CLI
$2520  JMP $2520                     ; on attend la 2e IRQ dans une boucle de 3 cycles
$2523  TXS                           ; 2e IRQ : on jette son cadre de pile
```
La deuxième IRQ interrompt toujours un `JMP` de 3 cycles : la gigue tombe de 0–7 cycles à 0–2.
`TSX … TXS` évite de dépiler : on revient au niveau de la première IRQ, dont le `RTI` final rend la main
au programme.

### 4.5 Compenser la badline selon le défilement vertical

La position de la badline dépend de `YSCROLL`. Sam's Journey, qui défile verticalement, corrige le retard
par table juste après le `TXS` :
```
$2526  LDA $D011 : AND #$07 : TAX
       LDA $1C60,X : TAX             ; table : 0A 0A 0A 0A 0A 02 02 0A
$2530  DEX : BNE $2530               ; 5 cycles par tour
```
Huit valeurs de défilement, huit retards : la coupure tombe toujours au même endroit de la ligne.
Astuce annexe : X sort **à zéro** de la boucle et sert aussitôt de zéro pour tout éteindre
(`STX $D01D / STX $D015 / STX $D000 … STX $D010`), sans `LDX #$00`.

### 4.6 Un mode vidéo invalide pour tracer du noir

Entre le jeu et le panneau, Sam's Journey écrit `$D011 = $57` : ECM (bit 6) alors que le multicolore est
actif dans `$D016`. Cette combinaison est invalide et le VIC affiche **du noir**, sans éteindre l'écran
(les badlines et le timing restent identiques). Huit lignes plus bas (`$258E`, attente active sur
`$D012` puis `STA $D011` avec `$17`), le panneau apparaît avec son propre écran, son jeu de caractères
(`$D018 = $0E`) et ses couleurs. La bande noire cache le changement de défilement, qui sinon laisserait
une ligne de caractères déchirée.

### 4.7 Ouvrir les bords haut et bas (Galencia)

```
ligne $FA ($3C04) : LDA $D011 : AND #$F7 : STA $D011     ; passe à 24 rangées
ligne $FF ($3CCF) : LDA $D011 : ORA #$88 : STA $D011     ; repasse à 25 (+ bit 8 du raster)
```
À la ligne $FA, le VIC en mode 24 rangées a déjà dépassé sa ligne de fermeture ($F7) ; en mode 25, elle
est à $FB et on l'évite en changeant juste avant. Le bord ne se ferme plus : les sprites y deviennent
visibles, en bas (Y = $FE) comme en haut (Y = $1C).

Galencia y met le **score** (8 sprites en haut) et **les vies et le niveau** (8 sprites en bas). Les 25
rangées de caractères restent entièrement au jeu, et l'affichage du score ne coûte aucune écriture à
l'écran.

### 4.8 Dégradés et barres de couleur

- **Couleur des sprites par tranche** (Galencia `$3EAE`) : 10 `NOP` de calage puis `LDA #$0F` et huit
  `STA $D027…$D02E`. Trois IRQ à 4 et 6 lignes d'écart donnent le dégradé métallique des chiffres du
  score. Les `NOP` repoussent l'écriture dans le bord, hors de la zone où les sprites sont dessinés.
- **Dégradé de fond sans IRQ par ligne** (intro de Galencia `$6EAB`) : une seule IRQ puis attente active
  ```
  LDX #$06
  - LDA table,X : STA $D021 : DEX : BMI fin
    LDA $D012 : CLC : ADC #$02
  - CMP $D012 : BEQ suite : BNE -
  ```
  Sept couleurs à deux lignes d'intervalle pour ~250 cycles, au lieu de sept entrées d'IRQ.

---

## 5. Sprites

### 5.1 Trois multiplexeurs comparés

| | Galencia | Zeta Wing | Sam's Journey |
|---|---|---|---|
| Sprites virtuels | 31 | 24 | 8 + réutilisation |
| Tables | `$5A26` Y, `$5A46` X, `$5A66` bit 8, `$5A86` couleur, `$5AA6` image | `$C800` Y, `$C81A` X, `$C84E` bit 8, `$C868` couleur, `$C882` image | `$003F` Y (page zéro), `$0A00` X, `$0A20` bit 8, `$0A40` image, `$0A60` couleur + attributs |
| Ordre trié | page zéro `$1D…` | page zéro `$20…` | page zéro `$1F…` |
| Lecture des tables | dans l'IRQ, `LDA table,Y` | **avant**, immédiats patchés | dans l'IRQ |
| Code | déroulé 8 fois (un bloc par sprite matériel) | déroulé, un segment par sprite | déroulé pour les 8 premiers, boucle ensuite |
| Ligne de l'IRQ suivante | `Y + $17 − raster`, 3 lignes minimum | `Y + $15` comparé à `$D012`, +2 | **milieu** entre fin de l'ancien et début du nouveau |
| Coût mesuré | tri 1 050, 1re IRQ 524, puis 71 par sprite | tri 414, préparation ~530, IRQ ~50 par sprite | non mesuré (≤ 8 sprites dans la scène) |

### 5.2 Le tri : insertion déroulée, ordre conservé d'une image à l'autre

Galencia (`$57E2`) et Zeta Wing (`$B528`) ont le même code, à un octet près :
```
LDY $1E : LDX $1D            ; deux indices voisins dans l'ordre
LDA $5A26,Y : CMP $5A26,X    ; compare leurs Y
BCS suivant                  ; déjà dans l'ordre : on avance
STX $1E : STY $1D            ; sinon on échange…
BCC étage_précédent          ; … et on recule d'un étage
```
18 octets par étage, un étage par paire voisine, aucune boucle, aucun compteur. L'ordre de l'image
précédente est le point de départ : comme les sprites bougent peu d'une image à l'autre, presque tous
les étages passent en 14 cycles sans échange. Mesuré : **414 cycles pour 24 sprites** (Zeta Wing),
1 050 pour 31 en plein mouvement de formation (Galencia).

### 5.3 Régler la longueur d'un code déroulé en y posant un `RTS`

Le nombre de sprites varie, le code déroulé est de longueur fixe. Solution des deux jeux :
```
Galencia $57BF :                      Zeta Wing $392B :
  LDA $0B : SBC #$02 : TAY              LDA #$60 : STA $3946,Y     ; pose RTS
  LDA $5AC6,Y : STA $19                 JSR $3946                  ; exécute le début
  LDA $5AE6,Y : STA $1A                 LDA #$B5 : STA $3946,Y     ; remet l'opcode d'origine
  LDY #$00
  LDA #$60 : STA ($19),Y     ; pose RTS
  JSR $57E2
  LDA #$A4 : STA ($19),Y     ; remet LDY zp
```
La table `$5AC6/$5AE6` donne l'adresse de chaque étage (préparée une fois, `$579A`, pas de 18). Coût
fixe d'une vingtaine de cycles, zéro cycle par itération. À utiliser pour toute boucle déroulée dont la
longueur change rarement.

### 5.4 Entrer au milieu d'un code déroulé

- **Galencia** (`$5286`), moins de 9 sprites : `LDA $575A,X / STA $17 / LDA $5763,X / STA $18 /
  JMP ($0017)` saute directement au bloc du premier sprite utile, et `$D015` reçoit le masque
  `$576C,X` (0, 1, 3, 7, 15…). Un opcode est basculé entre `JMP` ($4C) et `BIT` ($2C) en `$53C4` pour
  activer ou non la sortie anticipée : `BIT abs` sert de « saut désactivé » de 3 octets.
- **Sam's Journey** (`$2135`) : l'offset d'une branche est calculé et écrit dans le code
  ```
  LDA $15 : ASL : ADC $15     ; n × 3
  STA $213E                   ; opérande du BCC qui suit
  BCC *                       ; atterrit dans une table de JMP de 3 octets
  JMP $24BE : JMP $238E : JMP $233D : JMP $22EC : …
  ```
  Aiguillage sur n en ~15 cycles, sans table d'adresses ni `JMP (ind)`.

### 5.5 Placer l'IRQ de réutilisation

- **En retard ? On ne rend pas la main.** Galencia (`$53CA`) : `LDA $D001 / ADC #$17 / SBC $D012 /
  BCC sprite_suivant`. Zeta Wing (`$2FE8`) : `LDA $D003 / CLC / ADC #$15 / CMP $D012 / BCC suite`. Si la
  ligne voulue est déjà passée, on traite le sprite suivant dans la même IRQ : on évite 20 cycles
  d'aller-retour et surtout une IRQ programmée dans le passé, qui ne se déclencherait qu'à l'image
  suivante.
- **Marge minimale.** Galencia impose 3 lignes (`CMP #$03 / BCS / LDA #$03`), Zeta Wing ajoute 2.
- **Au milieu du trou** (Sam's Journey `$23EA`) :
  ```
  LDA $003F,Y : ADC #$16      ; bas de l'ancien sprite (Y + 22)
  ADC $003F,Y'                ; + haut du nouveau
  ROR                         ; moyenne sur 9 bits (la retenue rentre par la gauche)
  CMP #$C1 : BCS fin          ; rien sous la ligne du panneau
  ```
  Placer l'IRQ à mi-chemin donne la même tolérance des deux côtés : elle peut arriver en retard (badline,
  IRQ voisine) sans couper le sprite précédent ni rater le suivant. `ADC / ROR` est la façon la plus
  courte de moyenner deux octets sans perdre la retenue.
- Si c'est trop proche pour une IRQ : attente active `DEY / CPY $D012 / BCS` (`$24B5`).

### 5.6 N'écrire que ce qui change

Sam's Journey range dans l'octet de couleur trois attributs (bit 7 : haute résolution ou multicolore,
bit 6 : double hauteur, bit 5 : double largeur). À chaque réutilisation (`$2448`) :
```
LDA $5F,X : STA $2456       ; ancienne valeur → opérande du EOR ci-dessous
LDA $0A60,Y : STA $D027,X : STA $5F,X
EOR #$87                    ; différence avec l'ancienne
AND #$F0 : BEQ rien_à_faire ; mêmes attributs : on saute 3 registres
```
Dans le cas courant (mêmes attributs), on économise trois séquences `LDA $D01x / EOR masque / STA`
(~45 cycles). Masques de bits en tables (`$0DA0,X` pour mettre, `$0D98,X` pour ôter) plutôt que décalés.

### 5.7 Divers

- **Rejeter avant de trier** (Zeta Wing `$38FB`) : les sprites avec Y < $23 ou Y ≥ $F6 sont exclus de la
  fenêtre active ; l'IRQ ne les voit jamais.
- **Pas de sprites dans le panneau** (Sam's Journey) : l'IRQ du bas met X = 0 partout et `$D015 = 0`,
  ce qui supprime aussi leur coût en cycles sur ces lignes.
- **Collisions en logiciel** (Galencia `$1EF6`) : X sur 9 bits ramené à 8 par `ASL / ROR $54 / ROR $53`
  (on divise par 2), test vertical d'abord (`|dy| < 5`, le plus discriminant dans un tir vertical), puis
  `|dx/2| < 12`. La valeur absolue s'écrit `SEC / SBC / BPL + / EOR #$FF`.

---

## 6. Défilement

Le problème : déplacer 1 000 caractères **et** 1 000 couleurs coûte au minimum 2 × 9 000 cycles, soit
toute l'image. Et la couleur RAM ne peut pas être préparée à l'avance dans un second tampon.

### 6.1 Zeta Wing : vertical, 1 pixel par image, 8 phases

Tout le défilement est dans l'IRQ du bas d'écran (`$2E82` → `$19EE`) :
```
LDA $1A : TAX              ; phase 0 à 7
EOR #$07 : ORA #$10 : STA $D011      ; défilement fin
LDA $1A09,X : PHA : LDA $1A01,X : PHA : RTS      ; aiguillage sur la phase
```

| Phase | Travail | Coût |
|---|---|---|
| 1 à 6 | copier une tranche de 160 octets (4 rangées) de l'écran visible vers l'écran caché, 40 plus bas (`$1A38`… → `JMP $B6D9`) | ≈ 2 080 |
| 7 | dessiner la nouvelle rangée de tuiles (`$2135`) | — |
| 0 | basculer d'écran (`EOR #$10` sur `$D018`), décaler la couleur RAM, poser la rangée de couleur entrante (`$1A11`) | ≈ 2 700 |

6 tranches × 160 = 960 octets = 24 rangées. **Jamais plus de ~2 700 cycles de défilement dans une
image**, au lieu de ~18 000 d'un coup.

La copie est déroulée (`LDA ($02),Y / STA ($04),Y / INY` × 160, 13 cycles par octet). L'adressage
indirect permet d'utiliser le même code dans les deux sens (A→B puis B→A). Une version en `abs,X`
(9 cycles) demanderait deux copies du code : gain possible de ~640 cycles par tranche si la mémoire le
permet.

### 6.2 Zeta Wing : la couleur RAM à 2,9 cycles par case

Le décor est fait de **tuiles de 3 × 2 caractères d'une seule couleur**. Deux conséquences :

1. **Un `LDA` pour trois `STA`** (`$A400`) :
   ```
   LDA $D800 : STA $D828 : STA $D829 : STA $D82A     ; 16 cycles pour 3 cases
   LDA $D803 : STA $D82B : STA $D82C : STA $D82D
   ```
2. **Une rangée sur deux seulement change.** Comme chaque tuile fait 2 rangées, après un cran de
   défilement une rangée sur deux garde sa couleur. Deux routines déroulées alternent : `$A400` (rangées
   paires → impaires) et `$AC80` (impaires → paires), choisies par un drapeau basculé (`EOR #$80`,
   `$1C7C`). Sources et destinations sont disjointes : pas de problème d'ordre de copie.

Mesuré : **2 680 cycles** par appel (156 groupes × 16 + appel), pour un écran de 936 cases, soit 2,9
cycles par case contre 9 pour une copie classique. La rangée entrante est posée pareil (`$1A1B` :
`LDA $B500,X / STA $D800,X / STA $D801,X / STA $D802,X`, X de 3 en 3).

À retenir pour un portage : **la taille et la couleur des tuiles sont un choix de moteur**. Des tuiles
de N × M d'une seule couleur divisent le coût de la couleur RAM par environ N × M.

### 6.3 Sam's Journey : 8 directions, 3 pixels par image, 50 images par seconde

Couleur libre par caractère, donc pas de raccourci sur la couleur. La solution est un étalement sur 2 à
3 images, mesuré image par image pendant une course vers la droite :

| Image | Copie d'écran | Couleur RAM | Attente + tâche de fond |
|---|---|---|---|
| n | 5 600 | — | 12 200 |
| n+1 | 2 100 | 5 560 | 4 500 |
| n+2 | 200 | 2 060 | 5 400 |
| n+3 | 5 600 | — | … |

Le défilement fin relevé dans `$D016` sur ces images : 4, 1, 6, 3, 0, 5, 2… soit 3 pixels par image.

- **Copie d'écran** (`$3484`, ≈ 7 700 cycles au total) vers l'écran caché, 20 rangées déroulées dans une
  boucle sur les colonnes :
  ```
  LDA $C2F8,X : STA $C6F8,Y     ; rangée 19
  LDA $C2D0,X : STA $C6D0,Y     ; rangée 18
  …  (20 paires)
  INX : INY : CPX #fin : BNE
  ```
  Le décalage est **la différence entre X et Y** à l'entrée (`LDX #$01 / LDY #$00` pour un cran vers la
  gauche, `$2EA2`) : la même routine sert pour gauche, droite et sans décalage. Nombre de colonnes et
  sens des tampons sont patchés dans le code (`STA $351C`, `STA $359B`). 9 cycles par octet.
- **Couleur RAM** (`$2EBF`, ≈ 7 600 cycles), sur place, en **deux bandes** : rangées 0–6 puis 7–19.
- **Colonne entrante** : `$2C74` (≈ 900 cycles), couleur `$3679`.
- **Aiguillage** : le type de déplacement (4 bits de direction) choisit la routine par un `JMP`
  automodifié (`$2CB6`, tables `$2E82/$2E92`).
- **Position en 1/8 de pixel** (`$2A2C/$2A2D`, 0–$3F) : vitesses fractionnaires sans 16 bits ;
  `LSR×3 / AND #7 / EOR #7` donne la valeur du registre.

### 6.4 Rester devant le faisceau

La couleur RAM de Sam's Journey est modifiée sur place, donc visible. Elle n'est jamais vue à moitié
faite parce que la copie **court devant le faisceau** :

- la bande du haut (7 rangées, ≈ 2 060 cycles) est copiée en fin d'image, pendant que le faisceau est
  dans le panneau et le bord bas ;
- la bande du bas (13 rangées, ≈ 5 560 cycles) est copiée au début de l'image suivante ; le faisceau met
  ≈ 6 700 cycles à atteindre la rangée 7 (51 lignes de bord + 56 lignes) : la copie a fini avant lui.

C'est pour cela qu'il y a deux bandes : dans chacune, la boucle avance colonne par colonne sur toutes ses
rangées à la fois ; une seule bande de 20 rangées serait rattrapée.

La boucle principale s'y prête : après la synchro, elle attend que le raster soit repassé en haut
(`LDA $D011 / BPL / LDA $D012 / CMP #$10 / BCS attendre`, `$47E1`), puis **commence par le défilement**
(`JSR $2CB6` en premier, 9 800 cycles dans l'image mesurée) et ne fait la logique du jeu qu'ensuite.

Règle générale : pour modifier une zone visible sans déchirure, soit on la modifie hors de son passage
(bord, zone déjà affichée), soit on part devant le faisceau en allant plus vite que lui (une rangée de
caractères = 8 lignes = 504 cycles, moins 40 de badline).

### 6.5 Deux écrans, mêmes pointeurs de sprites

Zeta Wing et Sam's Journey basculent entre `$C000` et `$C400`. Les pointeurs de sprites sont donc écrits
deux fois à chaque mise à jour (`STA $C3F8 / STA $C7F8`). Le panneau de Sam's Journey, lui, reste
toujours sur l'écran `$C000` avec un autre jeu de caractères : il n'est pas concerné par la bascule.

---

## 7. Décors animés presque gratuits

### 7.1 Champ d'étoiles par le jeu de caractères (Galencia)

**371 cycles par image** (mesuré, `$4B9E`) pour un champ d'étoiles plein écran à 3 vitesses.

Mise en place, une fois : l'écran est rempli d'un motif de **50 caractères** ($3A à $6B) où chaque
colonne descend de un en un (la colonne 0 contient $3A, $3B, $3C… de haut en bas) et où les colonnes
sont décalées entre elles. Les 50 caractères forment ainsi, dans chaque colonne, une bande verticale de
400 lignes de pixels, et leurs 400 octets de définition (`$F9D0–$FB5F`) sont contigus.

Chaque image, pour chacune des 4 « étoiles » (pointeurs en page zéro) :
```
LDA #$00 : TAY : STA ($4D),Y        ; efface l'ancienne position : 1 octet
INC $4D : …                         ; avance le pointeur (1 px, 2 px, ou 1 px une image sur deux)
CMP #fin : … : LDA #début           ; reboucle sur les 400 octets
LDA ($4D),Y : ORA #$03 : STA ($4D),Y     ; pose 2 bits : 1 octet
```
Un octet modifié apparaît partout où son caractère est affiché : 4 pointeurs donnent des dizaines
d'étoiles à l'écran. Trois vitesses (pointeurs avancés de 2, de 1, ou un tour sur deux) font la
profondeur ; la couleur vient de la paire de bits posée (`$03`, `$0C`, `$30`) et de la couleur RAM.
Deux octets fixes (`$FA50`, `$F9E0`) allumés et éteints selon le compteur d'image font le scintillement.

Généralisation : tout décor répétitif (pluie, neige, tapis roulant, eau) se fait en modifiant quelques
octets du jeu de caractères plutôt que l'écran.

### 7.2 Couleur par caractère en table

Intro de Galencia (`$0880`) : la couleur RAM se déduit du code du caractère.
```
LDA $C000,X : TAY : LDA $C400,Y : STA $D800,X
```
Une table de 256 couleurs indexée par le code écran remplace un second plan de données de 1 000 octets.
Convient quand chaque caractère a toujours la même couleur.

### 7.3 Amplitude variable sans multiplication

Galencia anime sa formation avec un seul sinus de 128 octets (`$B97D`) et obtient trois amplitudes par
décalages successifs (`LSR`, puis `LSR` encore) : la colonne centrale bouge de A, la suivante de A/2, la
dernière de A/4 (`$2C09–$2CD9`). Les résultats sont écrits directement dans les tables de positions des
ennemis de chaque colonne (suite de `STA abs`, pas de boucle).

---

## 8. Boucle de jeu

### 8.1 Synchronisation : un compteur ou un drapeau posé par l'IRQ

```
Galencia $0A34 :   LDA $5F           Zeta Wing $0EA4 :   LSR $03FE      ; efface le drapeau
                 - CMP $5F                             - LDA $03FE
                   BEQ -                                 BEQ -
```
L'IRQ du bas d'écran fait `INC $5F` ou `STA $03FE`. `LSR` pour effacer un drapeau valant 1 : une
instruction, pas de registre.

Sam's Journey utilise **deux compteurs** (`$1E8B` incrémenté en haut d'image, `$1E8C` en bas) et les
compare pour savoir dans quelle moitié de l'image il se trouve.

### 8.2 Une attente qui travaille (Sam's Journey `$47C4`)

```
$47C4  CLI
$47C5  JSR $3B7E            ; une petite tranche de travail de fond
       LDX $44A9
       CPX $1E8C
       BEQ $47C5            ; pas encore la nouvelle image : encore une tranche
       SEI
```
`$3B7E` avance d'**un élément** dans deux listes d'objets du niveau (une par axe) et active ceux qui
entrent dans le voisinage de l'écran. Environ 36 cycles par appel, des centaines d'appels par image
quand le jeu a de la marge, très peu quand il est chargé : le travail non urgent se cale tout seul sur
le temps libre. Mesuré pendant le défilement : 14 % du temps dans la boucle, 20 % dans la tâche.

Conditions : la tâche doit être découpable en pas de quelques dizaines de cycles, et ne rien toucher que
le reste du jeu modifie pendant une IRQ.

### 8.3 Défilement dans l'IRQ, jeu dans la boucle (Zeta Wing)

Le défilement de Zeta Wing est entièrement dans l'interruption : il avance d'un pixel par image quoi que
fasse le jeu. Si la logique déborde sur l'image suivante, les objets ralentissent mais le décor reste
fluide. Coût mesuré de la partie IRQ : 2 000 à 4 900 cycles selon la phase.

### 8.4 Objets en tableaux parallèles

Les trois jeux rangent les objets en **tableaux par champ**, indexés par X :
- Galencia : `$B500,X` état, `$B520,X`, `$B540,X`… (32 objets, tableaux espacés de 32) ;
- Zeta Wing : `$C8D0,X` type (24 objets) ;
- Sam's Journey : `$0A90,X`, `$0AC0,X`, `$0AF0,X`, `$0BF0,X`… (16 objets, tableaux espacés de 16).

`LDA champ,X` = 4 cycles, sans calcul d'adresse. Une structure par objet obligerait à passer par
`(zp),Y` (5 à 6 cycles, Y mobilisé, pointeur à mettre à jour). Les boucles vont de N−1 à 0 (`DEX / BPL`
ou `DEX / CPX #1`) pour se passer de `CPX`.

### 8.5 Aiguillages

| Forme | Exemple | Coût | Quand |
|---|---|---|---|
| Adresse empilée puis `RTS` | Galencia `$2CDC`, Zeta Wing `$19F8`, `$2245` : `LDA tbl_hi,X / PHA / LDA tbl_lo,X / PHA / RTS` (la table contient l'adresse − 1) | 20 | état choisi à chaque appel |
| `JSR` dont l'opérande est patché | Zeta Wing `$2DAE` : `LDA $2E0C,Y / STA $2DC0 / LDA $2DC9,Y / STA $2DBF / JSR $xxxx` | 22 + retour normal | appeler le comportement d'un objet **et revenir** |
| `JMP` dont l'opérande est patché | Sam's Journey `$2866` (menus), `$2CB6` (défilement), `$13EC` (source d'octets) | 3 une fois posé | état qui change rarement : le changement coûte, l'appel est gratuit |
| Branche à offset patché vers une table de `JMP` | Sam's Journey `$2135` | ~15 | entrée dans du code déroulé |
| `JMP (zp)` | Galencia `$52A6` | 5 + préparation | idem |

### 8.6 Entrées

- **Table de décodage** (Sam's Journey `$1C36`) : `LDA $DC00 / AND #$1F / TAX / LDA $1C03,X`. La table de
  32 octets inverse les bits (le joystick est actif à 0) **et annule les directions opposées** : haut +
  bas ensemble donnent 0. Un accès au lieu d'une série de tests.
- **Fronts par immédiat patché** : l'état précédent, inversé, est écrit dans l'opérande d'un `AND #imm`
  (`$1C33 : STA $1C45`) ; `nouveau AND non-ancien` = boutons qui viennent d'être pressés, sans variable.
- **Anti-rebond par registre à décalage** (boot de Galencia `$C0A5`) : `LSR A / ROR $C196`, puis
  `BIT $C196 / BMI / BVC` teste « relâché maintenant, pressé avant » en une instruction.
- **Lecture propre** (Zeta Wing `$1999`) : `LDA #$FF / STA $DC00 / EOR $DC00 / AND #$1F` donne
  directement les bits actifs à 1.

---

## 9. Astuces de code 6502 relevées

| Astuce | Où | Effet |
|---|---|---|
| `DEC $D019` / `INC $D019` / `LSR $D019` | partout | acquitte l'IRQ sans registre |
| `BIT abs` comme saut désactivé de 3 octets (`$2C` ↔ `$4C`) | Galencia `$53C4` | bascule un `JMP` en un octet |
| `BIT $00` comme attente de 3 cycles, `NOP` de 2 | Sam's Journey `$25A2`, Galencia | calage au cycle |
| `BIT port` pour lire les bits 6 et 7 dans V et N | Sam's Journey `$11B2` | deux bits lus sans toucher A |
| `RTS` posé dans du code déroulé | Galencia `$57D4`, Zeta Wing `$392B` | longueur variable sans compteur |
| Opérande de branche patché | Sam's Journey `$213A` | saut calculé court |
| Opérande d'adresse incrémenté (`INC $1220`) au lieu d'un pointeur page zéro | Sam's Journey `$1222`, `$1286` ; Zeta Wing `$F21C` | `LDA abs` (4) au lieu de `LDA (zp),Y` (5), Y libre |
| `ADC / ROR` : moyenne de deux octets | Sam's Journey `$23F3` | 9 bits sans débordement |
| `CMP #$80 / ROR` : division par 2 signée | Sam's Journey `$2D3E` | garde le signe |
| `ASL / ROR m+1 / ROR m` : 9 bits → 8 | Galencia `$1F52` | coordonnée X divisée par 2 |
| Registre sorti à 0 d'une boucle réutilisé comme zéro | Sam's Journey `$254A` | pas de `LDX #0` |
| Table de masques de bits (`$0DA0,X`, `$0D98,X`) | Sam's Journey | pas de décalages en boucle |
| Branche toujours prise à la place de `JMP` (`BNE` après `LDA #non-nul`, `BCC` après un test) | partout | 2 octets au lieu de 3, code relogeable |
| Table en page zéro lue en `abs,Y` (`LDA $003F,Y`) | Sam's Journey | garde X libre (pas de `zp,Y` pour `LDA`) |
| Table d'adresses d'étages précalculée une fois | Galencia `$579A` | pas de multiplication par 18 à l'exécution |

**Opcodes illégaux** : aucun parmi les 2 000 à 2 900 adresses exécutées dans chacune des trois traces
de jeu (vérifié par script). Leur vitesse vient
de l'architecture, pas du jeu d'instructions non documenté.

---

## 10. Son

- **Musique appelée à ligne fixe** par une IRQ dédiée ou en fin d'IRQ : Galencia `JSR $8003` à la ligne
  $E4 (≈ 1 000 cycles), Sam's Journey `JSR $16B3` dans l'IRQ du bas (≈ 650 cycles, bruitages compris),
  Zeta Wing `JSR $13DB` en fin d'IRQ (≈ 570 cycles ; identifié par sa place et son coût, pas désassemblé).
- Dans les trois cas la musique joue **en bas d'écran**, après les écritures vidéo sensibles : sa durée
  variable ne décale aucune coupure.
- Budget à prévoir : 600 à 1 000 cycles par image, soit 3 à 5 % du temps.

---

## 11. Gains mesurés

| Sujet | Approche directe | Ce que font les jeux | Gain |
|---|---|---|---|
| Défilement d'un écran complet | ~18 000 cycles dans une image | Zeta Wing : ≤ 2 700 par image sur 8 images | lissé ÷ 6 |
| | | Sam's Journey : ≤ 9 800 par image sur 3 images, à 3 px/image | tient en 50 i/s |
| Couleur RAM (936 cases) | 9 cycles par case = 8 400 | Zeta Wing : 2 680 (tuiles 3 × 2 unicolores) | ÷ 3,1 |
| Tri de 24 sprites | tri complet : plusieurs milliers | insertion déroulée sur l'ordre précédent : 414 | ÷ 5 à 10 |
| IRQ d'un sprite réutilisé | ~110 (sauvegarde complète + tables) | Galencia 71, Zeta Wing ~50 | ÷ 1,5 à 2 |
| Entrée/sortie d'IRQ, 3 registres | 29 par la pile | 18 par la page zéro | −11 par IRQ |
| Champ d'étoiles plein écran | des centaines de caractères à déplacer | 371 (4 pointeurs dans le jeu de caractères) | ÷ 20 et plus |
| Score et vies | écritures à l'écran, rangées perdues | sprites dans les bords : 0 rangée | 25 rangées pour le jeu |

Charge mesurée (part du temps passée à attendre l'image suivante) :

| Jeu | Scène | Temps libre |
|---|---|---|
| Galencia | formation complète, tirs | 47 % |
| Zeta Wing | début du niveau 1 | 67 % |
| Sam's Journey | course à vitesse maximale, défilement continu | 35 % (dont 20 % rendus utiles par la tâche de fond) |

Aucun des trois ne frôle la limite : la marge absorbe les pics (explosions, écran plein).

---

## 12. Check-list avant de proposer un moteur

1. Le budget est-il posé en cycles, avec les badlines et les sprites déduits ?
2. Le KERNAL est-il coupé (`$01 = $35`), l'IRQ en `$FFFE`, les CIA muets ?
3. Où est la banque VIC ? Le graphisme est-il sous les ROM et les E/S pour libérer le bas de la mémoire ?
4. Chaque routine chaude a-t-elle un coût mesuré (`prof.py`) ?
5. Le défilement est-il découpé en tranches de moins de ~1/3 d'image ? Qui fait quoi à quelle phase ?
6. La couleur RAM : les tuiles permettent-elles d'en écrire moins ? Sinon, la copie court-elle devant le
   faisceau ?
7. Deux écrans : les pointeurs de sprites sont-ils écrits dans les deux ?
8. Les IRQ ne font-elles que des `LDA #imm / STA` préparés ? Sauvent-elles seulement ce qu'elles
   utilisent ?
9. Une IRQ peut-elle être programmée sur une ligne déjà passée ? (Test « en retard → enchaîner ».)
10. Les coupures visibles sont-elles stables (double IRQ) et indépendantes du défilement vertical ?
11. Multiplexeur : tri sur l'ordre précédent, rejet hors écran avant le tri, marge de 2 à 3 lignes ?
12. Le score peut-il sortir de la zone de jeu (bords, panneau séparé) ?
13. Les objets sont-ils en tableaux parallèles indexés par X ?
14. Y a-t-il du travail non urgent à mettre dans la boucle d'attente ?
15. PAL et NTSC : un binaire par norme, ou des tables ? Les lignes raster sont-elles toutes revues ?
16. Code automodifié : la valeur patchée est-elle écrite **avant** que l'IRQ qui la lit puisse tomber
    (sous `SEI`, ou en une seule écriture) ?

---

## 13. Outils de mesure (`tools/`)

Python 3, sans dépendance. `vicemon.py` suppose VICE 3.10 dans `%LOCALAPPDATA%\VICE\` (chemin en tête
du fichier).

| Outil | Usage |
|---|---|
| `d64.py image.d64 [dossier]` | liste le répertoire et extrait les fichiers |
| `vicemon.py` | classe `Vice` : lance `x64sc` en accéléré, `run_to`, `dump` (RAM, registres, capture), `poke`, joystick simulé (`joy_auto`, `joy_cell`), `history` (trace), `disk` (changer de disquette) |
| `state.py dump` | résumé : vecteurs, mode vidéo, banque, écran, sprites, carte de la mémoire |
| `dis6502.py dump.ram dis 1000 1100` | désassemblage (opcodes illégaux en minuscules) ; `xref`, `xrange` : qui touche à telle adresse |
| `prof.py trace.chis` | temps par bloc de code ; `subs` : par sous-programme ; `irq` : chaque interruption, sa durée, son écart ; `io` : chaque écriture en `$Dxxx` |

Recette pour profiler son propre jeu :
```python
from vicemon import Vice
v = Vice(["-autostart", "build/game.prg"])
v.run_to(30e6)                       # laisser démarrer
v.joy_auto(0x02a7); v.joy_cell(0x18) # feu + droite
v.run_for(3e6)
v.dump("out/jeu"); v.history("out/jeu.chis", 150000)
v.quit()
```
puis `prof.py out/jeu.chis`, `prof.py out/jeu.chis subs`, `prof.py out/jeu.chis irq`.

Lecture du résultat : la boucle d'attente apparaît comme le premier bloc ; son pourcentage est la marge.
Tout bloc au-dessus de 5 % mérite un regard. Dans `irq`, un écart qui varie d'une image à l'autre
signale une IRQ en retard.
