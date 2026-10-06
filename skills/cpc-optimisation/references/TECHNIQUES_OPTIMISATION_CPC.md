# Techniques d'optimisation Amstrad CPC — référence pour portages

> **À qui s'adresse ce document** : à Claude (ou à tout développeur) qui écrit ou optimise du code Z80
> pour Amstrad CPC, en particulier pour des **portages** (MSX, ZX Spectrum, arcade → CPC).
> Il est autonome : copie-le tel quel dans un autre dépôt.
>
> **D'où viennent ces techniques** : du désassemblage des disquettes de ce dépôt (OptiCPC).
> Chaque technique indique le jeu, l'adresse et le code réellement observés.
> Les coûts sont donnés en **NOPs** (1 NOP = 1 µs, l'unité de temps réelle du CPC).
>
> **Document compagnon** : `CRTC_COMPENDIUM.md` (même dossier) résume, pour les jeux, *The Amstrad CPC CRTC
> Compendium* de Longshot / Logon System (CC BY-NC-ND) : différences entre les cinq types de CRTC, moments
> où les registres sont pris en compte, interruptions, temps fixe, durée de toutes les instructions. Les
> renvois « Compendium §n » ci-dessous pointent vers ce fichier. Les durées et les règles CRTC de ce
> document ont été recoupées avec lui ; les corrections qui en viennent sont signalées.

---

## 0. Règles d'or (à appliquer avant tout)

1. **Compter en NOPs, pas en T-states.** Sur CPC, toute instruction est arrondie à un multiple de 4 T-states
   (le Gate Array partage la RAM avec la vidéo). Une trame = **19 968 NOPs** (312 lignes × 64 µs).
   À 50 images/s, c'est tout le budget ; à 25 images/s, 39 936.
2. **Mesurer avant d'optimiser.** Profiler la boucle principale (émulateur avec compteur de cycles, ou
   changer la couleur du bord au début et à la fin d'une routine pour voir sa durée à l'écran).
3. **Ne jamais retravailler ce qui n'a pas changé** : tuiles « sales », sprites inchangés conservés,
   comparaison de l'état précédent. Tous les jeux analysés ne redessinent que le nécessaire.
4. **Faire faire le travail au matériel** : défilement par le CRTC (R12/R13), double tampon par R12,
   changement de palette au lieu de redessiner, interruptions pour découper l'écran.
5. **Précalculer** tout ce qui peut l'être (tables alignées sur 256 octets, sprites pré-décalés,
   tuiles déjà converties au format écran, données réordonnées dans l'ordre de dessin).
6. **Couper le firmware** dès que possible (DI, ROM coupées, vecteur $38 à soi) : on récupère la RAM
   de $A600 à $BFFF et on supprime le coût de l'interruption système.
7. **Découpler la logique de l'affichage** : rythme de jeu fixe (ex. 1 mise à jour toutes les 3 VBL
   dans R-Type 1988) pour une vitesse stable même quand l'écran est chargé.
8. **Porter un jeu, c'est garder sa logique, pas son affichage.** La logique d'origine (physique,
   déplacements, IA, timings) donne les sensations de jeu : on la garde. L'affichage se refait avec les
   moyens du CPC (graphismes mode 0 préparés à l'avance, décor en tuiles, défilement CRTC, palette),
   en lisant les positions dans les données du jeu. Ne jamais reconstituer l'écran de la machine
   d'origine à partir de ses appels de dessin : voir §15.

---

## 1. Corpus analysé et limites

| Disquette | Identité réelle (d'après le code) | Machine | Ce qui a été analysé |
|---|---|---|---|
| `Pinball_Dreams__(3_inch_version)__ENGLISH__Side_A/B.dsk` | Pinball Dreams CPC (image CPCRULEZ) | **128K obligatoire** (« 128K Required ») | chargeur, format disque, pilote FDC, compresseurs, système (banques, trampolines), moteur d'affichage de l'intro et du menu, détection du CRTC |
| `TOKIGGP-FACE-A/B.dsk` | Toki GGP, groupe AmstradGGP (`amstradggp.com` cité dans `CHARGE.BIN`) | 128K (banques $C4–$C7) | `PROG.BIN` complet : boucle principale, double tampon, tuiles, sprites masqués, interruption, chargement |
| `R-Type (UK) (128K) (2012) (Version double size) [Original].dsk` | **R-Type 128K d'Easter Egg** (« BUILD - Fano on 04/10/2012 », `WTF.TXT` signé Julien, TotO, Fano ; version 3"½ double face) | **128K obligatoire** | chargeur, système de fichiers maison, lanceur, décompression de tous les fichiers, noyau (RST, interruptions), moteur de cases, partage mode 0/mode 1, chargement des niveaux (§12) |
| `rtypeed.dsk` | R-Type d'Electric Dreams (1988), code Bob Pape, disquette « Cracked and compacted by Nich Campbell » — **reçu par erreur, gardé comme point de comparaison** | 64K | décompression, boucle de jeu, interruption, format écran, niveau 1 |

Dans la suite, **« R-Type 128K »** désigne le homebrew de 2012 (le vrai sujet) et **« R-Type 1988 »** la
version commerciale (conversion du Spectrum). Les techniques de la version 1988 restent utiles pour des
portages depuis le Spectrum ou le MSX (même géométrie 256 × 192).

**Méthode** : extraction des DSK (format AMSDOS, pistes non standard et système de fichiers maison),
désassemblage Z80, et un petit émulateur CPC 128K (Gate Array, banques, CRTC, PPI, clavier, interruptions
300 Hz calées sur la VSYNC) pour dérouler les décompressions et journaliser les accès matériel image par image.
**Limites** : la partie « table de flipper en jeu » de Pinball Dreams n'a pas été atteinte en émulation ;
R-Type 128K a été suivi jusqu'au menu et au chargement d'un niveau, puis analysé
statiquement (moteur de jeu, fichiers de niveau décompressés) ; R-Type 1988 jusqu'à l'écran titre.
Ce qui est **observé** est distingué de ce qui est **déduit**.

---

## 2. Rappels machine indispensables

### 2.1 Coûts des instructions (NOPs)

| Instruction | NOPs | Instruction | NOPs |
|---|---|---|---|
| `NOP`, `LD r,r'`, `INC r`, `EX DE,HL`, `EXX`, `OR r` | 1 | `LD r,n`, `LD r,(HL)`, `LD (HL),r`, `ADD A,n`, `AND (HL)` | 2 |
| `LD rr,nn`, `POP rr`, `JP nn`, `RET`, `ADD HL,rr`, `LD (HL),n` | 3 | `PUSH rr`, `OUT (C),r`, `IN A,(C)`, `LD A,(nn)`, `LD (nn),A` | 4 |
| `LDI`, `OUTI`, `LD HL,(nn)`, `CALL nn` | 5 | `LDIR` (par octet recopié) | 6 |
| `SET b,H` / `RES b,H` | 2 | `DJNZ` (saut / sortie) | 4 / 3 |
| `JR` (saut / sortie) | 3 / 2 | `LD SP,HL` / `INC L` | 2 / 1 |
| `JP (HL)` / `JP (IX)` | 1 / 2 | `RST n` / `OUT (n),A` | 4 / 3 |
| `INC HL` / `INC IXL` | 2 / 2 | `LD (nn),HL` / `LD (nn),SP` | 5 / 6 |

Table complète (toutes les instructions, entrée en interruption comprise) : Compendium §7.

Conséquences directes :
- recopier un octet : `LDIR` = 6, `LDI` déroulé = 5, **pile** (`POP` + `PUSH`) ≈ **3,5**, `LD (HL),r` avec valeur déjà en registre = 2 ;
- une boucle `DJNZ` coûte 4 NOPs par tour **en plus** du corps : dérouler (`REPT`) dès que la boucle est chaude.

### 2.2 Temps vidéo
- 1 ligne = 64 NOPs ; 1 trame = 312 lignes = 19 968 NOPs.
- Le Gate Array déclenche **6 interruptions par trame** (toutes les 52 lignes), la première ~2 lignes
  après le début de la VSYNC. Une interruption non acceptée (DI) **reste en attente** : un `DI` court ne
  la perd pas. Si elle est acceptée avec **plus de 32 lignes (~2 000 NOPs)** de retard, les interruptions
  suivantes sont décalées jusqu'à la VSYNC suivante ; au-delà de 52 lignes (~3 300 NOPs), une interruption
  est perdue (Compendium §2.5).
- Entrer dans l'interruption coûte 5 NOPs (IM 1). Elle n'arrive qu'à la fin de l'instruction en cours :
  pour un effet calé au microseconde, la faire précéder d'un `HALT`.
- VSYNC lisible sur le PPI : port `$F5xx`, bit 0. Le signal dure 8 ou 16 lignes selon le CRTC : ne se caler
  que sur son **début** (Compendium §2.2).
- Un changement de **mode** n'est appliqué qu'à la HSYNC suivante (donc proprement à la ligne d'après) ; un
  changement de **couleur** est immédiat, au pixel près (Compendium §2.4).

### 2.3 Ports
| Port | Rôle |
|---|---|
| `$7Fxx` | Gate Array : `%00ppppp` choix d'encre, `%010ccccc` couleur, `%100iRRmm` mode + ROM (bit 2 = ROM basse coupée, bit 3 = ROM haute coupée, bit 4 = remise à zéro du compteur d'interruptions), `%11xxxccc` configuration RAM (`$C0`–`$C7`) |
| `$BCxx` / `$BDxx` | CRTC : sélection du registre / écriture de la valeur ; `$BExx`/`$BFxx` : lecture (selon type de CRTC) |
| `$F4xx` / `$F6xx` / `$F7xx` | PPI : données PSG (AY) / commande PSG + ligne du clavier / contrôle |
| `$FA7E` | moteur du lecteur ; `$FB7E` statut FDC ; `$FB7F` données FDC |

### 2.4 Configurations RAM 128K (`OUT ($7F),$C0+n`)
| Config | $0000 | $4000 | $8000 | $C000 | Usage typique |
|---|---|---|---|---|---|
| `$C0` | 0 | 1 | 2 | 3 | normal |
| `$C1` | 0 | 1 | 2 | **7** | code/musique en banque 7 visible en haut |
| `$C2` | **4** | **5** | **6** | **7** | tout en banques supplémentaires (Roller Ball : « vue MSX ») |
| `$C3` | 0 | **3** | 2 | **7** | |
| `$C4`–`$C7` | 0 | **4–7** | 2 | 3 | fenêtre de 16K en $4000 sur une banque de données |

### 2.5 CRTC (6845) — registres utiles
| Reg | Rôle | Remarques |
|---|---|---|
| R1 | caractères affichés par ligne (1 caractère = 2 octets) | 32 → 64 octets par ligne (256 px en mode 1) ; 40 = standard |
| R0 | caractères par ligne − 1 | 63 = lignes de 64 µs ; ne pas y toucher dans un jeu |
| R1 | caractères affichés par ligne (1 caractère = 2 octets) | 32 → 64 octets par ligne (256 px en mode 1) ; 40 = standard ; **0 = rien d'affiché, sur tous les CRTC** |
| R2 | position de la HSYNC | centre l'image horizontalement (46 = standard, 50 = plein écran) ; ± 1 décale l'image de 2 octets ; **R2 + R3 ≤ R0**, sinon plus de VSYNC sur CRTC 2 |
| R3 | bits 3–0 : largeur de la HSYNC ; bits 7–4 : hauteur de la VSYNC (CRTC 0, 3, 4 seulement) | `$8E` par défaut ; jamais 0 (plus d'interruptions sur CRTC 0 et 1) ; passer les bits faibles de 5 à 4 décale l'image d'**un octet** |
| R4 | nombre de rangées de caractères − 1 (hauteur totale de la « trame CRTC ») | petit R4 = **rupture** (plusieurs trames CRTC par image) ; ne jamais écrire moins que la rangée en cours |
| R5 | ajustement vertical (lignes en plus) | défilement vertical fin ; les rangées sont comptées différemment selon le CRTC pendant ces lignes |
| R6 | rangées affichées | 0 = écran noir, mais pris en compte différemment selon le CRTC : préférer R1 = 0 |
| R7 | position de la VSYNC | 127 (`$7F`, registre sur 7 bits) = pas de VSYNC dans cette trame CRTC (ruptures) |
| R8 | entrelacé et décalage du bord | laisser à 0 |
| R9 | lignes par rangée − 1 | 7 = normal ; 0 = une ligne par rangée (ruptures ligne à ligne) |
| R12/R13 | adresse de début (en mots) | R12 bits 5–4 = page ($00=$0000, $10=$4000, $20=$8000, $30=$C000), bits 3–2 = taille (11 = 32K), bits 1–0 + R13 = décalage ; **à écrire juste après la VSYNC** (§5.2) |

Détail par registre et par type de CRTC : Compendium §2 et §3.

Adresse écran d'un octet : `page + (ligne AND 7) × $800 + rangée × (2 × R1) + colonne`. L'adresse
« tourne » dans chaque bloc de **2 Ko** (compteur MA sur 10 bits) : c'est ce qui permet le défilement
matériel sans fin (voir §5.3).

---

## 3. Contrôle total de la machine

### 3.1 Couper le firmware et prendre l'interruption — *tous les jeux*
- Pinball Dreams, premier octet exécuté : `DI`, puis Gate Array `$8D` (mode 1, **ROM basse et haute coupées**),
  vecteur `$0038` = `EI / RET` (`$A405 : LD HL,$C9FB / LD ($0038),HL`) ; plus tard la routine réelle est
  branchée en écrivant seulement l'adresse (`$08C0 : LD HL,$0834 / LD ($0039),HL`).
- Toki : `$0A82 : LD A,$C3 / LD ($0038),A / LD HL,$0927 / LD ($0039),HL / IM 1` → `JP` direct, sans firmware.
- R-Type 1988 : `$85FE : LD A,$CD / LD ($0038),A / LD HL,$8400 / LD ($0039),HL` → `CALL $8400` ; au retour,
  l'exécution continue en `$003B` où le firmware avait laissé un `RET` (vecteur d'interruption externe).
  ⚠️ Si tu coupes le firmware, **garde un `RET` ($C9) en `$003B`** si ton vecteur est un `CALL`.

**À retenir** : changer de routine d'interruption = réécrire 2 octets en `$0039`. Pratique pour passer
d'une routine « intro » à une routine « jeu » sans test dans l'interruption.

### 3.2 Détection du matériel — *Pinball Dreams*
- **Mémoire** (`$8000–$8026` de `DISC.BIN`) : écrit un octet témoin en `$C7D0` sous chaque configuration
  `$C1, $C9, $D1…` (jusqu'à 512K) et vérifie qu'il ne se retrouve pas en banque 0 ; sinon affiche
  « 128K Required ».
- **Type de CRTC** (`$A637`) : lit les registres d'état par `$BExx`/`$BFxx`, compare, puis teste le PPI →
  renvoie 0 à 4. Le résultat est rangé en `$0001` puis sert à **patcher** les routines de rupture
  (`$08A0` : si CRTC ≠ 0 et ≠ 2, on écrit d'autres valeurs en `$0995`, `$09AF`, `$0A0A`, `$0B04`).
  → Les ruptures et effets CRTC **diffèrent selon le type de CRTC** : si tu en fais, prévois des variantes
  et la détection.
  Le découpage « 0 et 2 d'un côté, 1, 3 et 4 de l'autre » correspond à la façon d'entrer dans une rupture
  ligne à ligne (Compendium §3.2). Ce que chaque type permet de lire sur `$BExx`/`$BFxx`, et une recette de
  détection : Compendium §4. Attention : `$BExx` ne renvoie rien de fiable sur les types 0 et 2.

### 3.3 Clavier en une rafale — *Pinball Dreams `$014E`*
```z80
        ld bc,$F782 : out (c),c     ; PPI : port A en sortie
        ld bc,$F40E : ld e,b : out (c),c   ; registre 14 du PSG
        ld bc,$F6C0 : ld d,b : out (c),c   ; « sélection registre »
        out (c),0
        ld bc,$F792 : out (c),c     ; port A en entrée
        ld c,$40                    ; ligne 0
        ld a,10
.l:     ld b,d : out (c),c          ; F6 : lecture PSG + ligne C
        ld b,e : ini                ; lit F4 dans (HL), HL++
        inc c : dec a : jr nz,.l
        ld bc,$F782 : out (c),c
```
Les 10 lignes de la matrice sont lues une seule fois par image dans un tampon ; le jeu ne teste ensuite que
des bits en RAM. (R-Type 1988 lit lui aussi le clavier directement par le PSG, sans firmware, en `$0640`.)

---

## 4. Mémoire, chargement, compression

### 4.1 Trampolines de banques en RAM basse — *Pinball Dreams `$0040–$006B`*
```z80
$0040:  ld bc,$7FC0 : out (c),c : jp (hl)          ; aller en config C0 puis sauter
$0046:  ld bc,$7FC2 : out (c),c : jp (hl)          ; aller en config C2 puis sauter
$004C:  ld bc,$7FC0 : out (c),c : ld bc,$0056 : push bc : jp (hl)   ; appel lointain, retour via $0056
$0056:  ld bc,$7FC2 : out (c),c : ret              ; retour dans l'autre config
```
Ces quelques octets en `$0000–$3FFF` (banque 0, **toujours visible** sauf en `$C2`) servent d'**appels
lointains** entre banques. Règle : le code qui change de configuration ne doit pas se trouver dans la zone
qui disparaît.

La musique (lecteur Arkos Tracker 2, voir §8) vit en **banque 7** et est appelée une fois par image via une
petite routine en banque 0 (`$0887` : `LD A,$C1 / OUT` → `CALL $F3D8` → `LD A,$C0 / OUT`).

### 4.2 Répartition des données par banque
- **Toki** : une table de chargement (`$0231`, lue en `$15A8`, 18 octets par entrée : configuration RAM de
  destination, nom de fichier AMSDOS sur 11 caractères, adresses) fait charger chaque niveau dans la bonne
  banque (`1BANKC0.PCK`, `BOSS2A.PCK`…), fichier par fichier, puis décompresser (`$1613 : CALL $1B58`).
  Les tuiles sont en banque 4, lues en `$4000` avec la config `$C4` pendant que le code tourne en banque 0.
- **Pinball Dreams** : code système en banque 0, musique + pilote disque en banque 7 (`$F300–$FFFF`), gros
  blocs graphiques en banques 4–6 décompressés à la demande.

### 4.3 Format de disquette maison — *Pinball Dreams*
Observé dans les DSK :
- pistes 0–1 : format DATA standard (9 × 512, secteurs $C1–$C9), qui contient seulement `DISC.BIN` ;
- **pistes 2–39 : 10 secteurs de 512 octets** (ID $01–$0A) = **5 Ko par piste** au lieu de 4,5 Ko (+11 %) ;
- **décalage de secteurs d'une piste à l'autre** : le premier secteur physique avance de 2 à chaque piste
  (01, 03, 05, 07, 09, 01…) : quand la tête arrive sur la piste suivante, le secteur 1 passe juste sous elle,
  on ne perd pas un tour de disque (200 ms) ;
- le catalogue AMSDOS contient des **entrées sans nom** (attributs lecture seule + système) qui réservent
  les blocs 9 à 179 : AMSDOS voit le disque plein et n'écrira jamais par-dessus les données maison.

### 4.4 Pilote FDC direct — *Pinball Dreams `$FC6F–$FE66`*
Sans AMSDOS : moteur (`$FA7E`), `SEEK` ($0F), `RECALIBRATE` ($07), `READ DATA` multi-secteurs (**$46**),
`WRITE DATA` (**$45**, pour les scores), lecture octet par octet en scrutant le bit 7 de `$FB7E` :
```z80
.rd:    in a,(c)            ; BC = $FB7E (statut)
        jp p,.rd            ; bit 7 = prêt
        and $20             ; bit 5 = phase d'exécution
        jr z,.fin
        inc c
        in a,(c)            ; $FB7F : donnée
        ld (hl),a
        dec c
        inc hl
        jr .rd
```
Point d'entrée : `H` = piste, `L` = secteur, `B` = nombre, `DE` = destination ; passage automatique à la
piste suivante après le secteur 10. Avantages : RAM du firmware libérée, plus de secteurs par piste,
chargement pendant que la musique joue.

### 4.5 Compression : deux décompresseurs selon l'usage
| Décompresseur | Où | Pourquoi |
|---|---|---|
| **Exomizer** (table de 52 entrées, `LD B,$34`, tables indexées par IY) | Pinball Dreams `$FE67` (et une copie en `$0211`) ; Toki `$1B58` pour tous les `.PCK` | meilleur taux → tient sur la disquette, décompressé **une fois** au chargement |
| **ZX7** (variante rapide : `LD A,$80 / LDI / ADD A,A`, offset via `SLL E`) | Pinball Dreams `$A543` | beaucoup plus rapide → pour ce qui est décompressé **pendant le jeu** (écrans, graphismes en banque) |
| LZ maison (littéraux, copies, répétitions) | R-Type 1988 `$FE03` (compacteur du cracker) | plusieurs étapes de décompression, niveaux compressés individuellement |

Règle : **Exomizer pour le stockage, ZX7/ZX0 (ou LZ4) pour ce qui se décompresse en temps réel.**

---

## 5. Écran et CRTC

### 5.1 Écran réduit = moins à dessiner
| Jeu | Mode | R1 × R6 | Taille | Raison |
|---|---|---|---|---|
| Toki | 0 | **32 × 19** rangées (`$0A9D`) | 64 o × 152 lignes = 9,5 Ko | moins d'octets à redessiner à chaque image, plus de marge |
| R-Type 1988 | 1 | **32 × 24** (`$847A`) | 256 × 192 = 12 Ko | géométrie Spectrum : graphismes et logique repris tels quels |
| Roller Ball (ton portage) | 1 | 32 × 24 | 256 × 192 | géométrie MSX |

64 octets par ligne (R1 = 32) a un avantage énorme : une rangée de caractères (8 lignes) occupe exactement
`8 × $800` et **32 rangées remplissent un bloc de 2 Ko** → défilement vertical matériel qui boucle tout seul
(§5.3).

R-Type 1988 place même son écran en **`$0040` en banque 0** (R12 = 0, R13 = $20) pour garder `$4000–$FFFF` au code
et aux données.

### 5.2 Double tampon par R12 — *Toki `$202E`, Pinball Dreams `$05DE`, Roller Ball*
```z80
; Toki, fin de boucle principale : bascule l'écran affiché ($8000 <-> $C000)
        ld bc,$BC0C
        out (c),c
        inc b                   ; B = $BD
.v:     ld a,$20                ; <- immédiat modifié à chaque passage
        out (c),a
        xor $10                 ; $20 <-> $30
        ld (.v+1),a             ; réécrit l'immédiat du LD A,n (code automodifiant)
; et les routines de dessin visent l'autre écran en inversant l'octet fort
; de leurs adresses : LD A,($128D) / XOR $40 / LD ($128D),A   ($80 <-> $C0)
```
Le CRTC ne prend R12/R13 en compte qu'**au début d'une trame CRTC**, mais pas de la même façon sur tous
les types (**correction** d'après le Compendium §2.1 ; la version précédente de ce document disait « on
peut écrire R12 n'importe quand ») :
- CRTC 0, 3, 4 : une seule fois, au tout début de la trame ;
- CRTC 1 : à chaque ligne de la **première rangée** : une écriture pendant ces 8 lignes coupe la rangée du
  haut en deux pour une image ;
- CRTC 2 : l'adresse est figée un peu avant la fin de la trame précédente : une écriture sur la toute
  dernière ligne arrive une image trop tard.

Règle : **écrire R12 (et R13) juste après avoir détecté la VSYNC**. La trame suivante commence 72 lignes
plus tard avec les réglages standard : c'est sûr sur les cinq types. Dès la VSYNC, l'ancien écran n'est plus
affiché (on est sous la zone visible) : on peut commencer à le redessiner tout de suite.
La bascule de Toki ci-dessus est écrite en fin de boucle principale, à un moment quelconque de l'image :
sur CRTC 1 elle peut tomber dans la première rangée (déduit, non observé sur machine).

### 5.3 Défilement matériel (principe à appliquer)
Déplacer l'adresse de début (R12/R13) fait défiler **tout l'écran** sans recopier un octet :
- horizontal : ± 1 mot = 2 octets (8 px en mode 1, 4 px en mode 0) ;
- vertical : ± R1 mots = une rangée de caractères (8 lignes) ; plus fin avec R5/R9 ou des ruptures ;
- avec R1 = 32, les 32 rangées d'un bloc de 2 Ko forment un **anneau** : on n'affiche que 24 rangées, et
  à chaque pas on dessine seulement **la rangée qui entre** (32 tuiles au lieu de 768).
```z80
; top = rangée de l'anneau affichée en haut (0-31). MA = top × 32 mots.
PAGE    equ $20                 ; $20 = écran en $8000, $30 = écran en $C000
set_scroll:                     ; A = top
        ld l,a
        ld h,0
        add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl   ; × 32
        ld a,h
        or PAGE                 ; bits 1-0 de R12 = poids fort du décalage
        ld bc,$BC0C : out (c),c
        inc b : out (c),a       ; R12
        ld bc,$BC0D : out (c),c
        inc b : out (c),l       ; R13
        ret
; adresse d'une case (rangée écran r, colonne c) dans l'anneau :
;   page + ((r + top) AND 31) × 64 + 2c   (+ $800 par ligne de pixel)
```
Limite importante : le défilement matériel déplace **toute** la largeur. Une zone fixe (panneau de score)
demande soit de la redessiner, soit une **rupture** (§5.4) qui la place dans une autre trame CRTC, en haut ou
en bas (jamais à gauche ou à droite).

Compléments tirés du Compendium (§2.3 et §2.9) :
- **défilement horizontal à l'octet** : R12/R13 avance par pas de 2 octets ; en passant en plus les 4 bits
  faibles de R3 de 5 à 4, l'image entière se décale d'un octet. On obtient un pas de 2 pixels en mode 0,
  4 pixels en mode 1, sans rien recopier (non observé dans le corpus) ;
- **la couture** : dès que le décalage n'est plus nul, une ligne d'écran est coupée quelque part en mémoire
  (après `$C7FF` vient `$C000`). Avec l'anneau ci-dessus (R1 = 32, pas d'une rangée entière), la couture
  tombe toujours entre deux rangées et les routines de dessin n'ont rien à prévoir. Avec un défilement
  horizontal matériel, ou un R1 qui ne divise pas 1 024, une tuile ou un sprite peut être à cheval dessus :
  il faut une routine spéciale pour la rangée concernée.

### 5.4 Ruptures (écran découpé en plusieurs trames CRTC) — *Pinball Dreams, intro et menu*
Journal CRTC observé en émulation pendant une image du menu :
- `R12`/`R13` réécrits **au milieu de l'image** (`$0612 : R12=$10`, `$061C : R13` alterné $00/$A0) ;
- `R4` (hauteur de trame) = $18 puis $0D, `R7` = $08 puis $7F (une seule VSYNC), `R6` = $04 : l'écran est
  découpé en zones qui ont **chacune leur adresse de début** (zone fixe + zone animée ou défilante) ;
- `R9 = 0`, `R4 = 0` sur une portion (`$0996`) : rangées d'**une seule ligne**, pour changer l'adresse à
  chaque ligne ;
- `R2` alterné **45/47 à chaque ligne** (`$08E2–$08FC`, 283 écritures CRTC par image) : décalage horizontal
  ligne à ligne (effet d'ondulation/entrelacement). Le Compendium (p. 134) décrit cette alternance de R2
  d'une ligne à l'autre comme un moyen de faire osciller la synchronisation horizontale autour d'une
  position.

Règles pour qu'une rupture simple marche sur les cinq types de CRTC (R4 jamais inférieur à la rangée en
cours, moment d'écriture de R12/R13 et de R7, comptage pendant les lignes de R5, retard d'1 µs des
`OUT (C),r` sur CRTC 3 et 4) : Compendium §3.1. Entrée dans une rupture ligne à ligne selon le type : §3.2.
Avant d'en faire une, vérifier qu'un découpage par interruption (§7.2, §12.5) ne suffit pas : lui ne dépend
pas du CRTC.

Écriture compacte d'une suite de registres CRTC (`$08FD`) :
```z80
; HL -> [nb, reg, val, reg, val, ...]
        ld bc,$BDBE     ; astuce : OUTI décrémente B AVANT d'écrire
.l:     outi            ; B=$BC : sélection du registre (HL)
        ld b,c          ; B = $BE
        outi            ; B=$BD : valeur (HL)
        dec a
        jr nz,.l
```

### 5.5 Code synchronisé au cycle près — *Pinball Dreams `$0855–$0891`, `$0480–$079C`*
Une « liste d'affichage » est exécutée **par la pile** : `POP HL` lit l'adresse de la prochaine routine,
`JP (HL)` y saute, la routine revient par `JP (IY)`. Chaque routine a une **durée fixe**, complétée par des
`NOP` et des boucles `DJNZ` calibrées (`LD B,14 / DJNZ $` ≈ une ligne), pour que le changement de registre
tombe toujours sur la même ligne et la même colonne du balayage :
```z80
$085D:  pop hl          ; prochaine entrée de la liste
        cp h
        jr nz,.wait
        ld h,d
        jp (hl)         ; routine d'effet (durée fixe), retour par JP (IY)
.wait:  ld b,14
        djnz $          ; attendre une ligne
        nop : nop : nop ; ajustement au NOP près
        dec h
        jr nz,.wait
```
C'est le prix des effets matériels : pas d'interruption, pas de branche à durée variable pendant la zone.
Méthodes pour écrire ce genre de code (égaliser deux branches avec une instruction de 1 NOP, routines
d'attente réglables, instructions « neutres » de 2 à 12 NOPs) : Compendium §5. Pour un code commun à tous
les CRTC, écrire les registres par `OUTI` : il agit au même moment partout, alors que `OUT (C),r` agit 1 µs
plus tard sur CRTC 3 et 4 (Compendium §2.6).

### 5.6 Écritures dispersées pilotées par la pile — *Pinball Dreams `$0498–$079C`*
```z80
        pop bc          ; C = valeur, B = octet bas de l'adresse     (3 NOPs)
        ld l,b          ; H = page fixe                                (1)
        ld (hl),c       ;                                              (2)
        ; ... répété, puis JP (IY)
```
6 NOPs par octet écrit **n'importe où dans une page de 256 octets**, sans boucle ni calcul d'adresse. Des
points d'entrée différents (table de `JP` en `$0480`) donnent le nombre d'écritures et le code est complété
pour garder une durée fixe. Utile pour : mettre à jour des octets épars (éléments animés, bouts de table
de couleurs, code automodifiant en série).

---

## 6. Synchronisation et rythme

### 6.1 Attente de VSYNC (toutes)
```z80
wait_vbl:
        ld b,$F5
.a:     in a,(c) : rra : jr c,.a        ; si on est DANS la VSYNC, attendre qu'elle finisse
.b:     in a,(c) : rra : jr nc,.b       ; attendre le début de la suivante
        ret
```
(Pinball Dreams `$006C/$0077`, R-Type 1988 `$01B3`.)

Cette forme est la bonne : elle se cale sur le **début** de la VSYNC, identique sur tous les CRTC (la fin
ne l'est pas : 8 ou 16 lignes selon le type). C'est aussi le moment sûr pour écrire R12/R13 (§5.2).
La boucle a une précision de 7 NOPs ; pour se caler au microseconde près, voir Compendium §5.

### 6.2 Compter les 6 interruptions — *Toki `$0928`, R-Type 1988 `$8400`*
```z80
; Toki : ne fait le travail lourd qu'une fois par image
isr:    di
        push af
        ld a,0          ; <- compteur stocké dans l'immédiat (automodifiant)
        inc a
        ld (isr+3),a
        cp 6
        jr nz,.fin
        xor a
        ld (isr+3),a
        ; ... sauver les registres, musique, cycle de couleurs ...
.fin:   pop af
        ei
        ret
```
R-Type 1988 : à la 4e et à la 5e interruption il change l'encre 3 (couleurs différentes selon la bande d'écran),
à la 6e il **attend la VSYNC** pour se recaler (`$843B`), remet le compteur à 0 et incrémente un compteur
d'images.

### 6.3 Rythme de jeu fixe — *R-Type 1988 `$8656–$86A0`*
```z80
main:   xor a
        ld ($7A8A),a            ; compteur d'images (incrémenté par l'interruption)
        call ...                ; toute la logique + le dessin
.w:     ld a,($7A8A)
        cp 3
        jr c,.w                 ; au moins 3 VBL par tour => 16,7 Hz stables
        jp main
```
La vitesse ne dépend pas de la charge ; si une image est trop lourde on ne ralentit pas le jeu, on garde la
cadence choisie. Choisir **1** (50 Hz), **2** (25 Hz) ou **3** (16,7 Hz) selon le budget mesuré.

### 6.4 Attendre avec `HALT`
Pinball Dreams : `HALT / HALT` (`$06D8`) = attendre 2 interruptions (≈ 1/3 d'image) sans calcul.
`EI / HALT` repart pile à l'interruption suivante : utile pour synchroniser un effet sur une bande d'écran.

---

## 7. Couleurs sans redessiner

### 7.1 Cycle de couleurs — *Toki `$0950–$0987`*
Toutes les 3 images, l'interruption fait tourner les encres 4, 5 et 10 à partir d'une table :
```z80
        ld a,(hl) : ld bc,$7F04 : out (c),c : out (c),a    ; encre 4
        inc hl : ld a,(hl) : ld c,5  : out (c),c : out (c),a ; encre 5
        inc hl : ld a,(hl) : ld c,10 : out (c),c : out (c),a ; encre 10
```
Eau, lave, lumières clignotantes, flèches… animées **gratuitement** : aucun octet d'écran ne change.

### 7.2 Palette par bande d'écran — *R-Type 1988 `$841E–$8437`*
Les interruptions tombent à des lignes fixes (toutes les 52 lignes) : changer une encre dans l'interruption
n° k la change pour tout ce qui est affiché en dessous. R-Type 1988 obtient ainsi plus de couleurs qu'un mode 1
(4 couleurs) : décor, vaisseau et panneau n'ont pas les mêmes encres.

### 7.3 Palette par ligne — *Pinball Dreams `$07CD–$07DF`*
Dans le code synchronisé (§5.5), `OUTI` envoie 3 encres par ligne depuis une table (dégradés « raster »).

### 7.4 Routine de palette avec données en ligne — *R-Type 1988 `$3E40`*
```z80
        call set_inks
        db 2,10,26,6            ; les données suivent l'appel
        ; ... le code reprend ici
set_inks:
        pop hl                  ; HL = adresse des données
        ; ... lit 4 octets, HL avance ...
        push hl                 ; nouvelle adresse de retour = après les données
        ret
```

---

## 8. Dessin : tuiles et sprites

### 8.1 Tuiles copiées par la pile, lignes en code de Gray — *Toki `$2543–$25D6`*
La routine la plus instructive. Pour une tuile de 2 octets × 8 lignes (4 px en mode 0) :
```z80
; DE = adresse écran d'une rangée de caractères (bits 5-3 de D = 0, E pair)
; HL = données de la tuile, PRÉ-RANGÉES dans l'ordre de dessin
        di                      ; SP va être détourné
        ld (.sp+1),sp           ; sauve SP dans l'immédiat du LD SP,nn final
        ld sp,hl                ; la pile pointe sur les données
        ex de,hl                ; HL = écran  (Toki fait exactement LD SP,HL / EX DE,HL)
        pop de : ld (hl),e : inc l : ld (hl),d      ; ligne 0 (gauche -> droite)
        set 3,h
        pop de : ld (hl),e : dec l : ld (hl),d      ; ligne 1 (droite -> gauche)
        set 4,h
        pop de : ld (hl),e : inc l : ld (hl),d      ; ligne 3
        res 3,h
        pop de : ld (hl),e : dec l : ld (hl),d      ; ligne 2
        set 5,h
        pop de : ld (hl),e : inc l : ld (hl),d      ; ligne 6
        set 3,h
        pop de : ld (hl),e : dec l : ld (hl),d      ; ligne 7
        res 4,h
        pop de : ld (hl),e : inc l : ld (hl),d      ; ligne 5
        res 3,h
        pop de : ld (hl),e : dec l : ld (hl),d      ; ligne 4
        ld bc,$E040 : add hl,bc                     ; rangée suivante (64 o/ligne)
.sp:    ld sp,0
        ei
```
Trois idées cumulées :
1. **`POP DE`** lit 2 octets en 3 NOPs (contre 4 pour deux `LD A,(HL)`/`INC L`) ;
2. **ordre de Gray des lignes** (0,1,3,2,6,7,5,4) : passer d'une ligne à la suivante ne change qu'**un bit**
   de H → un seul `SET`/`RES` (2 NOPs) au lieu de `LD A,H / ADD A,8 / LD H,A` (4 NOPs) ;
3. **zigzag** `INC L` / `DEC L` : on ne remet jamais L à sa valeur de départ.
Les données de la tuile sont **réordonnées une fois pour toutes** (au chargement ou à la conversion) :
ordre des lignes de Gray, et octets gauche/droite inversés une ligne sur deux.
Coût : ~10 NOPs par ligne, ~80 par tuile de 16 octets, contre ~128 pour une boucle `LD A,(HL)/LD (DE),A`.
Conditions : tuile alignée sur une rangée de caractères, L pair (pas de retenue sur `INC L`), `DI` pendant
que SP est détourné (fenêtres courtes : l'interruption attend).

### 8.2 Sprites masqués par table — *Toki `$126A`, table en `$2300`*
Mode 0 : chaque octet contient 2 pixels ; la couleur 0 est transparente. Une table de 256 octets **alignée
sur une page** donne le masque de n'importe quel octet (vérifié : 256/256 valeurs = « $AA si le pixel gauche
vaut 0, + $55 si le pixel droit vaut 0 ») :
```z80
        ld b,$23                ; page de la table de masques
.l:     ld a,(de)               ; octet du sprite
        ld c,a                  ; BC -> masque de cet octet
        ld a,(bc)
        and (hl)                ; garde le fond sous les pixels transparents
        or c                    ; pose les pixels du sprite
        ld (hl),a
        inc l
        inc de
        dec ixl
        jr nz,.l
```
Pas de masque stocké avec chaque sprite (mémoire divisée par deux). Coût, recompté avec la table du
Compendium (**correction** : la version précédente annonçait ~9 NOPs) : **18 NOPs par octet** tel quel, dont
7 pour la boucle (`INC DE` 2, `DEC IXL` 2, `JR NZ` 3) ; **11** si l'on déroule, 10 avec des données alignées
(`INC E`). En mode 1 : même principe (4 pixels par octet, pixel n = bits 7−n et 3−n).

Le sprite est dessiné **de bas en haut** (`LD A,$F8 / ADD A,H` = −$800 par ligne) avec rattrapage du bas de
rangée (`CP $C0 / JP P / ADD HL,$3FC0`).

### 8.3 Tables précalculées — *R-Type 1988*
- `$3E73` : table de **256 octets inversés bit à bit** en `$5D00` → retourner un sprite horizontalement =
  une lecture de table par octet ;
- graphismes du décor stockés **1 bit par pixel** (hérités du Spectrum), convertis au vol en mode 1 en ne
  remplissant qu'un plan de bits : quartet fort → un octet, quartet faible → l'octet voisin
  (`SRL A ×4` / `AND $0F`, `$86FD`) ; la couleur vient de la palette par bande (§7.2) ;
- défilement du décor par **pas pré-calculés** : compteur de phase modulo 4 (`$8A71`), la carte n'avance que
  tous les 4 pas.

### 8.4 Déroulage et `LDI`
Toutes les copies chaudes sont déroulées : R-Type 1988 `$1E64` (8 `LDI` à la suite), Pinball Dreams `$07E5`
(6 `LDI`). `LDIR` n'est utilisé que pour l'initialisation.

Quand la mémoire compte, dérouler à moitié : 10 `LDI` dans une boucle `DEC A / JR NZ` coûtent 5,4 NOPs par
octet pour 31 octets de code (5,2 avec 20 `LDI`), contre 6 en `LDIR` et 5 tout déroulé (Compendium §6).

---

## 9. Code : astuces transversales

| Technique | Exemple observé | Gain |
|---|---|---|
| **Variables dans les immédiats** (`LD A,n` dont on réécrit n) | Toki `$092A` (compteur d'interruptions), `$2035` (R12) ; Pinball `$05E4`, `$0623` | 1–2 NOPs par accès, pas de pointeur |
| **Activer/désactiver une fonction en patchant 1 octet** (`$C9` = `RET`, `$C3` = `JP`, `$00` = `NOP`) | Toki `$0B57 : LD A,$C9 / LD ($0927),A` ; `$059A` | zéro test dans la boucle chaude |
| **Crochet par adresse de `CALL` réécrite** | Toki `$0940` (routine appelée par l'interruption) | fonction virtuelle à 0 coût |
| **Pile comme lecteur de données** (`POP` = 2 octets en 3 NOPs) | Toki tuiles, Pinball listes, R-Type 1988 `$0852` | lecture séquentielle la plus rapide |
| **Tables alignées sur 256 octets** (`LD H,page / LD L,index / LD A,(HL)`) | Toki `$2300`, R-Type 1988 `$5D00`, Roller Ball `NIBHI` | indexation en 2 NOPs |
| **`JP (HL)` / `JP (IY)` au lieu de `CALL/RET`** | Pinball `$0862`, `$04B3` | 1 NOP (`JP (HL)`) ou 2 (`JP (IY)`) au lieu de 5 + 3, retour choisi |
| **Données après le `CALL`** | R-Type 1988 `$3E40` | pas de registre à préparer |
| **Registres secondaires `EXX`** | Pinball `$07C1` (palette au milieu d'une boucle) | 6 registres de plus en 1 NOP |
| **`IXL`/`IYL` comme compteurs** | Toki `$1275 : LD IXL,7` | libère B pour `DJNZ` ou les ports |
| **`RST` comme appels d'un octet** | R-Type 128K : `RST 8` = changer de banque, `RST $10` = changer de mode, `RST $18` + 1 octet = écrire au Gate Array la valeur qui suit | 1 octet au lieu de 3 et 4 NOPs au lieu de 5 par appel (un `CALL`) |
| **Numéro de banque écrit dans la banque elle-même** | R-Type 128K : l'octet `$4000` de chaque banque contient `$C4`/`$C5`/`$C6`/`$C0` ; l'interruption lit `($4000)` pour savoir quelle banque remettre | pas de variable « banque courante » à tenir à jour |

Autres astuces, non observées dans le corpus mais documentées dans le Compendium (§6) : champs d'une
structure rangés en tables parallèles sur des pages consécutives (`INC H` pour changer de champ), `ADD HL,BC`
transformé en `ADD HL,SP` par automodification pour qu'une seule routine de sprite déroulée serve à toutes
les hauteurs, `OUT (n),A` / `IN A,(n)` en 3 NOPs, `OUT (C),0`.

---

## 10. Son

- **Pinball Dreams** : lecteur **Arkos Tracker 2** (style AKG : compteurs `LD A,1 / DEC A / JP NZ` réécrits
  dans le code, trois voies copiées-collées, `$F3F6–$F9FF`), en banque 7, appelé une fois par image ;
  écriture directe des registres de l'AY par `$F4xx/$F6xx`.
- **Toki** : musique appelée par l'interruption une fois toutes les 6 (§6.2), via un crochet patchable.
- **R-Type 128K** : le lecteur (`SOUND.BIN`) vit en banque 7 ; l'interruption n° 1 lit l'octet `$4000`
  (numéro de la banque visible), passe en `$C7`, appelle le lecteur en `$4010`, puis remet la banque
  d'origine (`$007E–$008F`). Le jeu peut donc être dans n'importe quelle banque quand l'interruption tombe.
Règle : le lecteur est appelé **à un moment fixe** de l'image (dans l'interruption qui suit la VSYNC ou
juste après), jamais depuis la boucle de jeu à rythme variable.

---

## 11. Coûts comparés (pour décider vite)

| Tâche | Méthode naïve | Méthode des jeux | Gain |
|---|---|---|---|
| Copier 1 octet | `LDIR` 6 | `LDI` déroulé 5 ; `POP`/`PUSH` ≈ 3,5 | ×1,2 à ×1,7 |
| Remplir/effacer 2 octets | `LD (HL),A / INC HL` ×2 = 8 (6 avec `INC L`) | `PUSH DE` = 4 | ×1,5 à ×2 |
| Tuile 2 × 8 octets | boucle ≈ 128 | pile + Gray + zigzag ≈ 80 | ×1,6 |
| Faire défiler un écran de 12 Ko | recopie ≈ 43 000 (plus de 2 images) | R12/R13 ≈ 30 + une rangée de tuiles | ×100+ |
| Animer de l'eau / des lumières | redessiner | cycle de palette : 3 `OUT` | ×∞ |
| Test d'une option dans la boucle | `LD A,(flag) / OR A / JR` ≈ 7 | octet patché (`RET`/`NOP`) : 0 | — |
| Comparer 768 cases pour trouver les changements | boucle `CP (HL)` ≈ 12 × 768 ≈ 9 200 (46 % d'une image) | marquer les cases/rangées au moment de l'écriture | proportionnel aux changements |
| Tuiles tournées à gauche et à droite | 2 jeux de graphismes | 1 jeu + table « miroir » de 256 octets (R-Type 128K) | mémoire ÷ 2, +1 lecture par octet |

---

## 12. R-Type 128K (Easter Egg, 2012) — techniques observées

C'est le jeu le plus complet du corpus : 12 niveaux (0–9, A, B), environ 350 Ko de données compressées sur deux
faces, 128K obligatoires.

### 12.1 Disquette : système de fichiers maison et scores dans le catalogue
- Image double face, **10 secteurs de 512 octets par piste** (ID `$C1–$CA`, entrelacés) sauf la piste 0.
- Le catalogue AMSDOS (secteurs `$C1–$C2`) ne contient **qu'un seul vrai fichier**, `DISC.BIN` (512 octets,
  lancé par `RUN"DISC`). Les autres « entrées » sont en fait **la table des meilleurs scores** (« No.1 174500
  ABIKO »…) : le jeu sauvegarde ses scores directement dans des secteurs du catalogue.
- Le vrai répertoire est dans les secteurs `$C7–$C8` de la piste 0 : 63 entrées de **16 octets** :
  nom 8+3, **octet d'attributs** (bit 0 = face, bit 1 = compressé, bit 2 = exécutable), piste, secteur,
  longueur sur 16 bits. Les fichiers sont contigus, secteur après secteur.
- `DISC.BIN` utilise encore la ROM AMSDOS (commande disque `$84` « lire un secteur » via `RST $18`) pour lire ce
  répertoire, puis charge l'exécutable marqué (bit 2) à l'adresse **écrite dans son nom** (`9000.EXE` →
  `$9000`) et y saute. 512 octets suffisent pour démarrer.
- Ensuite le jeu utilise **son propre pilote FDC** (`$0800–$08C6` : `RECALIBRATE $07`, `SEEK $0F`,
  `SENSE INTERRUPT $08`, lecture des secteurs), sans firmware.

### 12.2 Démarrage en cascade
1. `9000.EXE` : écran noir (R1 = 0), **test des 128K** (`$91A0` : écrit le numéro de configuration en `$4000`
   sous `$C4…$C7` puis relit ; sinon affiche `128KONLY.RAW`), lecture du clavier au démarrage (touches maintenues
   → écran caché `SPECCY.RAW`).
2. Charge `DATA.C4.BIN` en banque 4, `MAIN.EXE` en banque 7, décompresse `INTRO.RAW` en `$0400` et lance
   l'intro (`$4809`).
3. Un stub de 13 octets recopié en `$0000` lance le jeu : `LD SP,$C000 / config $C1 / JP $C000` (le jeu est
   en banque 7, visible en `$C000` sous `$C1`).
4. `MAIN.EXE` est **auto-décompressable** : environ 370 octets de décompresseur Exomizer en tête, qui décompressent
   le reste de `$C16F` vers `$0000` puis font `RST 0`.

### 12.3 Compression par fichier et par banque
- Fichiers marqués « compressés » : **en-tête de 2 octets** puis flux Exomizer (vérifié : chaque fichier est
  consommé exactement) ; décompression par `$08CB` vers la destination voulue.
- Chaque niveau = `LEVELn.LVL` (données et code du niveau, décompressés en `$9000`, 3 à 5 Ko) + `MAPn.C4` et
  `MAPn.C5` (**une banque de 16 Ko chacun**, le décor) + `GFX_Ln.SPR` (sprites du niveau, banque 6) ;
  `GFX_BASE.SPR` et `SOUND.BIN` sont communs.
- Après chaque chargement, le jeu écrit en `$4000` le numéro de la banque (`$C4`, `$C5`, `$C6`, `$C0`) :
  n'importe quelle routine (dont l'interruption) sait quelle banque est visible en lisant cet octet.

### 12.4 Noyau : `RST` et interruption à aiguillage
```z80
$0008:  ld b,$7F : out (c),a : ret                  ; RST 8   : A = $C0-$C7 -> change de banque
$0010:  add a,$8C : ld b,$7F : out (c),a : ret      ; RST $10 : A = mode 0/1/2 (ROM coupées)
$0018:  pop hl : ld a,(hl) : inc hl : push hl       ; RST $18 : l'octet qui SUIT le RST est
        ld b,$7F : out (c),a : ret                  ;           envoyé au Gate Array
; exemple : RST $18 / DB $C4   => 2 octets pour changer de banque
```
Interruption (`$0038`) :
- compteur 0–7 **recalé sur la VSYNC** (si le bit VSYNC du PPI est à 1, le compteur repart) ;
- **table de 8 adresses** indexée par ce compteur : une routine différente par tranche de 52 lignes ;
- la table elle-même est remplaçable en réécrivant l'opérande de `LD HL,table` (`$005E`) : une table pour le
  titre (`$A75D`), une pour le jeu (`$0FFA`), une pour les écrans intermédiaires (`$12D2`).

### 12.5 Partage d'écran mode 0 / mode 1 (table d'interruptions du jeu, `$0FFA`)
- Interruption 0 (juste après la VSYNC, `$104C`) : **mode 0** (`$8C`), encres 0–3 de l'aire de jeu, encre
  du niveau, puis musique (§10).
- Interruption 4 (`$102F`) : attente calibrée (`LD B,8` + `NOP`s en boucle `DJNZ`) pour tomber au bon endroit du
  balayage, encres 0–3 du panneau (`$101A`), puis **mode 1** (`$8D`).
- Résultat : aire de jeu en **16 couleurs (mode 0)**, panneau des scores en **mode 1** (texte fin), avec des
  palettes indépendantes. Les palettes passent par une table de traduction (`$0406 + index`) : un fondu =
  changer de table.
- Pourquoi ça marche sur toutes les machines (Compendium §2.4 et §2.5) : le **mode** n'est appliqué qu'à la
  HSYNC suivante, donc toujours sur une ligne entière ; seules les **encres** changent au pixel près, d'où
  l'attente calibrée avant de les écrire. Le recalage du compteur sur le bit VSYNC (§12.4) est sûr aussi :
  la première interruption tombe 2 lignes après le début de la VSYNC, dans le signal qu'il dure 8 ou
  16 lignes, et la suivante 52 lignes plus tard, toujours en dehors.

### 12.6 Écran et moteur de cases « sales »
- CRTC en jeu (table `$0192`) : R1 = 32, R6 = 24, R12 = `$30` → **écran unique en `$C000`**, 64 octets par
  ligne, mode 0 (128 × 192 gros pixels). **Pas de défilement matériel** : R12/R13 ne changent pas pendant la
  partie. Le défilement est logiciel.
- Le moteur (`$18F4–$1948`) parcourt une **grille d'état de 32 × 20 cases** (IYH = 32 colonnes, IYL = 20
  rangées). Pour chaque case :
  ```z80
  .case:  ld a,(hl)           ; état de la case
          and $3F
          jr z,.suivante      ; 0 = rien à faire (la plupart des cases)
          add a,a
          exx
          ld l,a              ; table de routines alignée
          ld e,(hl) : inc l : ld d,(hl)
          ex de,hl
          jp (hl)             ; routine spécialisée pour ce type de case
  ; ... la routine dessine, puis la case est marquée « propre » (LD (HL),4)
  .suivante:
          inc e : inc e       ; case écran suivante (2 octets)
          inc l               ; état suivant
          dec iyh
          jr nz,.case
  ```
  On ne dessine **que les cases marquées**, et chaque type de case a sa routine (pas de test dans la boucle).
  Deux jeux de registres (`EXX`) : l'un pour parcourir la grille, l'autre pour dessiner.
- Une routine de case (`$194B`) :
  1. **change de banque pour cette case** (`OUT (C),A` avec la configuration lue dans les données de la case) :
     le décor est réparti sur plusieurs banques ;
  2. lit la tuile à travers une **table de 256 octets en `$B400` qui échange les deux pixels de chaque octet
     mode 0** (vérifié 256/256) : la tuile est dessinée **en miroir** ;
  3. écrit les 8 lignes en partant du bas (`OR $38` sur l'octet fort) dans l'ordre de Gray inversé
     (`RES 3`, `RES 4`, `SET 3`, `RES 5`…) et en zigzag (`INC E` / `DEC E`).
  ```z80
          ld b,$B4            ; page de la table « miroir »
  .l:     ld c,(hl)           ; octet de la tuile
          ld a,(bc)           ; ses deux pixels échangés
          ld (de),a
          inc l
  ```
  → une seule copie des graphismes sert pour les deux sens : **mémoire des tuiles divisée par deux**.
- Le même motif de dessin (zigzag + Gray) sert pour le texte (`$01D7`, police en `$BC00`).

### 12.7 Ce qu'il faut en retenir pour un portage
- **Écran unique + cases sales** plutôt que double tampon : on ne redessine pas un écran entier deux fois ;
  seules les cases marquées changent, et le défilement ne coûte que les cases dont le contenu change
  (les grands fonds unis ne sont jamais redessinés).
- **Aiguillage par type de case** (`JP (HL)` sur une table) plutôt que des tests.
- **Données découpées par banque de 16 Ko** et marquées par leur numéro, chargées niveau par niveau.
- **Miroirs par table** pour économiser la mémoire graphique.
- **Deux modes vidéo dans la même image** grâce à l'interruption : couleurs en haut, finesse en bas.

---

## 13. Application : portage Roller Ball (MSX → CPC)

Contexte du dépôt `Rolleball` (branche principale, commit `fa7f3b7`) : le code Z80 de la cartouche MSX tourne
tel quel ; un VDP virtuel (banque 5) reçoit les écritures ; `render.asm` convertit la table des noms et les
sprites TMS9918 vers un écran mode 1 256 × 192 en double tampon (`$8000`/`$C000`, R12 $20/$30). Le défilement
d'origine (une rangée par image sur 20 rangées, `$9264`) a été **remplacé par un saut de 20 rangées**
(`patches.asm`, `$921D`) parce que redessiner tout l'écran à chaque pas était trop lent.

### 13.1 Mesures faites sur `render.asm` (coûts en NOPs)
- `snap` recopie à chaque image la table des noms (768 o) + les sprites (128 o) par `LDIR` :
  ≈ 896 × 6 = **5 400 NOPs (27 % d'une image)**.
- `draw_cells` compare les 768 cases (`LD A,(DE) / CP (HL) / JR NZ / INC L / INC E / DJNZ`) :
  ≈ 12 × 768 = **9 200 NOPs (46 % d'une image)**, même quand rien n'a changé.
- dessin d'une case : ≈ 16 NOPs par ligne → **≈ 128 NOPs** + l'appel.
- sprites : décalage de 0 à 3 pixels **ligne par ligne** avec `SRL/RR/RR` en boucle `DJNZ` (jusqu'à 9
  décalages par ligne).

### 13.2 Gains sûrs, sans changer l'architecture (par ordre d'intérêt)
1. **Ne plus comparer 768 cases** : `hle_outi` et `rst $10` voient déjà chaque écriture de nom ; y marquer
   la **rangée** modifiée (24 drapeaux, ou un octet par case comme `tdirty`) et ne comparer que les rangées
   marquées. Gain : jusqu'à ~9 000 NOPs par image au repos.
2. **Supprimer la recopie `snap` de la table des noms** : lire directement la VRAM virtuelle pendant
   `draw_cells` (config `$C5`), ou ne recopier que les rangées marquées ; sinon au moins remplacer `LDIR` par
   une copie par la pile (§11) : 5 400 → ~3 200 NOPs.
3. **Dessin de case par la pile + Gray + zigzag** (§8.1) : ~128 → ~80 NOPs par case. Le cache de tuiles
   (`TCACHE`, 16 octets par tuile) peut être **stocké directement dans l'ordre de dessin** par
   `cache_tiles` : rien à changer ailleurs. Encadrer d'un `DI`/`EI` par case ou par petit groupe (la VSYNC
   reste en attente, voir §2.2).
4. **Sprites pré-décalés** : quand `spat_dirty` signale un motif changé, générer les 4 versions décalées
   (0 à 3 px) de chaque motif dans une banque libre ; le dessin n'a plus de boucle de décalage.
5. Dérouler les boucles `px_hi`/`px_lo` pour les 5 octets d'une ligne de sprite.
6. **Grille d'état + aiguillage comme R-Type 128K** (§12.6) : remplacer « comparer le numéro de tuile » par
   une grille de 768 octets d'état écrite par les crochets (0 = rien à faire, sinon type de travail : tuile
   à redessiner, tuile sous un sprite, etc.) et une table de routines (`JP (HL)`). Le parcours d'une case
   vide coûte à peu près autant qu'une comparaison (~12–14 NOPs) : le gain vient de ce qu'on n'a plus besoin
   de recopier la table des noms (`snap`) ni de tenir `SHOWN_A/B`, et de l'aiguillage sans tests. Combiné
   avec des drapeaux par rangée (point 1), on ne parcourt que les rangées touchées.

### 13.3 Rendre au défilement sa fluidité
Le MSX fait défiler la vue **d'une rangée (8 lignes) par image** : c'est **exactement** un pas de R12/R13 avec
R1 = 32 (§5.3). Deux obstacles : le panneau de score fixe à droite (colonnes 22–31) et le double tampon.

**Option A — défilement matériel + comparaison « dans l'anneau » (garde la mise en page MSX)**
- Chaque écran (A et B) devient un anneau de 32 rangées ; variables `top_A`, `top_B` ; R12/R13 = page +
  `top × 32` mots au moment de la bascule.
- La vue du jeu est lue dans la RAM du MSX (`$E26B`, rangée de début de vue) et publiée dans l'état
  partagé (trou de VRAM `SH`) par le crochet d'interruption ; le rendu en déduit `top`.
- `SHOWN_A/B` deviennent des tableaux indexés **en coordonnées d'anneau** (32 × 32) : la case écran (r, c)
  correspond à `SHOWN[(r + top) AND 31][c]`. Conséquence : la **table** de flipper ne change plus dans
  l'anneau (seule la rangée qui entre est nouvelle) ; seul le **panneau de droite**, fixe à l'écran, bouge dans
  l'anneau, et la comparaison ne redessine que ses cases qui diffèrent de celles d'au-dessus (les grandes
  zones bleues unies ne sont pas redessinées).
- `LT_LO/LT_HI` (table des lignes) passe à 256 entrées et s'indexe par `(y + top × 8) AND 255` pour les
  sprites.
- Estimation pendant un défilement : 22 cases de la table + environ 100 à 150 cases du panneau ≈ 10 000 à
  14 000 NOPs de dessin avec la routine du §8.1 → **25 à 50 images/s**, au lieu d'un saut.

**Option B — panneau déplacé dans une zone CRTC séparée (le plus fluide)**
Comme les ruptures de Pinball Dreams (§5.4) : zone haute = table défilante (sa propre adresse R12/R13 en
anneau), zone basse = panneau fixe (autre adresse), une seule VSYNC. Le défilement ne coûte plus que la
rangée qui entre. Inconvénients : le panneau doit passer **en bas ou en haut** (réagencer ses 10 colonnes sur
2–4 rangées pleine largeur) et les ruptures dépendent du type de CRTC (détection + variantes, §3.2).
D'après le Compendium (§3.1 de la synthèse), une rupture **simple** à deux zones de rangées entières peut
être écrite une seule fois pour les cinq types si l'on respecte ses règles (R4, R7, moment d'écriture de
R12/R13) ; la détection ne devient nécessaire que pour une rupture ligne à ligne.

**Option C — défilement logiciel accéléré (si on garde tout tel quel)**
Recopier la zone de table de l'écran affiché vers l'écran caché décalée d'une rangée (22 × 2 × 8 × 23 ≈ 8 Ko)
par la pile (~3,5–4 NOPs/octet ≈ 30 000 NOPs), puis dessiner la rangée qui entre : ~1,5 image par pas, donc un
défilement d'une rangée toutes les 2 images (0,8 s pour 20 rangées). Plus simple, moins fluide.

**Option D — écran unique et cases sales, à la R-Type 128K (§12.6)**
R-Type 128K fait défiler **sans** défilement matériel ni double tampon : un seul écran, et seules les cases
dont le contenu change sont redessinées. Pour Roller Ball, en abandonnant le double tampon, chaque pas de
défilement ne coûte que les cases dont la tuile diffère de celle de la rangée voisine (les fonds unis du
plateau ne bougent pas), dessinées **une seule fois** au lieu de deux. Risque : du scintillement sur la balle
et les batteurs si on les efface et redessine pendant que le faisceau passe (je n'ai pas vérifié comment
R-Type 128K gère ce point pour ses sprites).

Recommandation initiale : **A** d'abord, **B** pour 50 images/s constantes, **D** si la mémoire manque.
**Mesuré ensuite (voir §13.5) : A n'apporte rien sur Roller Ball** : le panneau fixe à droite coûte ~158
cases par pas de 2 rangées dans l'anneau, soit ~198 au total contre 120-310 en logiciel. C'est la solution
logicielle (moteur de cases sales + défilement par pas calé sur le rendu) qui a été retenue.

### 13.4 Autres idées issues des jeux
- **Cycle de couleurs** (§7.1) pour les lumières/flèches du plateau si elles clignotent par changement de
  couleur de tuile sur MSX : détecter ces tuiles et les remplacer par des encres animées dans l'interruption.
- **Palette par bande** (§7.2) : le mode 1 n'a que 4 encres ; avec une interruption placée à la limite
  table/panneau (ou par bandes horizontales), on peut offrir d'autres encres au panneau.
- **Rythme fixe** (§6.3) : si une image dépasse le budget, choisir 25 Hz stable plutôt que des saccades.
- **Mode 0 en haut, mode 1 en bas** (§12.5) : si le plateau gagne à avoir plus de couleurs, l'interruption
  peut passer en mode 0 pour une zone et revenir en mode 1 pour une autre (en largeur, c'est tout ou rien
  pour une ligne donnée ; le panneau à droite du MSX ne peut pas avoir un autre mode que le plateau).
- **Tuiles en miroir par table** (§12.6) : si le plateau MSX est symétrique (batteurs gauche/droite,
  couloirs), ne garder qu'une moitié des tuiles converties et dessiner l'autre à travers une table d'échange
  de pixels (mode 1 : inverser l'ordre des 4 pixels).
- **Scores dans le catalogue** (§12.1) : pour sauvegarder les meilleurs scores sans fichier AMSDOS.
- **Moment de la bascule R12** (§5.2) : vérifier dans `render.asm` que l'écriture de R12 (`$20`/`$30`) suit
  l'attente de VSYNC ; sinon la rangée du haut peut se couper sur CRTC 1. Non vérifié : le code du portage
  n'est pas dans ce dépôt.

### 13.5 Résultats obtenus (septembre 2026, dépôt `Rolleball`, `docs/OPTIMISATIONS.md`)
Images rendues pendant la partie : **10-13/s → 28-37/s** ; défilement entre sections rétabli (5 positions,
~0,46 s, réglable) au lieu d'un saut. Par ordre de gain :
1. **Préparer l'image suivante pendant l'attente de la bascule** (relevé et bookkeeping sans pixel écrit
   avant la VSYNC) : ~+22 % d’images à lui seul — à faire systématiquement en double tampon.
2. **Rangées marquées à l'écriture** (plus de recopie ni de comparaison des 768 cases) : ~+40 %.
3. **Sprites : boucle par ligne en registres** (plus d'appels ni de variables mémoire) : ~300 → ~150
   NOPs/ligne ; **sortie rapide pour les sprites cachés** (la gestion coûtait plus que le dessin).
4. Cases par la pile + Gray + zigzag (§8.1) ; `kbd_decode` en tests de bits (~700 → ~140 NOPs/trame).
Leçons : **mesurer d'abord** (le poste le plus lourd n'était pas celui attendu) ; **les attentes de VSYNC
sont du temps récupérable** ; **une cartouche qui lit le registre R rend la partie non déterministe** : pour
vérifier, comparer l'image incrémentale à un redessin complet dans la même partie (`tools/verif.py auto`).

---

## 14. Check-list pour Claude avant de proposer une optimisation CPC

- [ ] Ai-je mesuré (en NOPs) la routine visée et sa part dans l'image ?
- [ ] Le travail est-il proportionnel **aux changements** et pas à la taille de l'écran ?
- [ ] Le CRTC peut-il le faire (R12/R13 pour défiler ou basculer, R6 pour cacher, ruptures pour découper) ?
- [ ] Une palette peut-elle remplacer un redessin (cycle, bande, raster) ?
- [ ] Les données sont-elles **pré-rangées dans l'ordre d'utilisation** (pile, Gray, pré-décalage, tables
      alignées) ?
- [ ] Les boucles chaudes sont-elles déroulées, sans `LDIR`, sans test inutile (octets patchés) ?
- [ ] Les fenêtres `DI` (pile détournée) restent-elles courtes (< 32 lignes ≈ 2 000 NOPs si des
      interruptions découpent l'écran, < 52 lignes ≈ 3 300 NOPs dans tous les cas) ?
- [ ] R12/R13 sont-ils écrits juste après la VSYNC, et pas à un moment quelconque de l'image ?
- [ ] Mes réglages CRTC respectent-ils R2 + R3 ≤ R0 (CRTC 2) et R3 ≠ 0 ? Est-ce que je ne dépends ni de la
      longueur de la VSYNC ni de la position exacte d'une interruption sans `HALT` ?
- [ ] Le changement de banque se fait-il depuis une zone toujours visible (trampoline en banque 0) ?
- [ ] La musique est-elle appelée à un moment fixe de l'image ?
- [ ] Si j'utilise des ruptures : ai-je prévu les différents types de CRTC (Compendium §3), et un découpage
      par interruption ne suffirait-il pas ?
- [ ] Le parcours de l'écran saute-t-il vite ce qui n'a pas changé (grille d'état, aiguillage par table) ?
- [ ] Les graphismes symétriques sont-ils stockés une seule fois (miroir par table) ?
- [ ] En double tampon, le travail sans pixel (relevé, listes, rectangles) est-il fait pendant l'attente
      de la bascule plutôt qu'après ?
- [ ] Ai-je un moyen de vérifier au pixel près (auto-contrôle incrémental = redessin complet) ?
- [ ] Portage : l'affichage lit-il les **positions** dans les données du jeu, avec des graphismes CPC
      préparés à l'avance, au lieu d'intercepter et de convertir les dessins de la machine d'origine (§15) ?
- [ ] Portage : les objets **immobiles** (tombes, pots, échelles, décor animé lent) sont-ils dans le décor,
      et pas dans la liste des sprites ?

---

## 15. Porter un jeu d'une autre machine : garder la logique, refaire l'affichage

Leçon tirée du portage de Ghosts'n Goblins (ZX Spectrum → CPC 6128, 2026). La première version
gardait la logique d'origine **et** interceptait toutes ses routines de dessin pour reconstituer l'écran
du Spectrum en mode 0. Le résultat était exact au pixel près, mais trop lent dès que la scène se
chargeait : **9 images/s** avec 15 objets, contre 25 sur Spectrum. Ce qui coûtait (NOPs par image,
zone de la première échelle) :

| Poste | NOPs | Cause : l'affichage émulé |
|---|---|---|
| Gestion des sprites (listes, appariement des rectangles, recouvrements) | 27 000 | les appels de dessin arrivent sans identité d'objet : il faut réapparier chaque image |
| Dessin des sprites masqués | 20 000 | 15 « sprites », dont tombes, pots et échelle que la machine d'origine dessinait en sprites pour la priorité |
| Restauration du décor sous les sprites | 13 000 | idem |
| Conversions 1 bit → mode 0 à la volée + cache | 11 000 | graphismes lus au format d'origine (pré-décalages Spectrum, dont beaucoup sont des poses différentes, pas des copies décalées) |

**Démarche à suivre dès le départ :**

1. **Garder la logique d'origine telle quelle** et la vérifier tour de boucle par tour de boucle contre
   l'original (RAM comparée à chaque passage de la boucle principale) : c'est elle qui donne les
   sensations de jeu.
2. **Ne prendre de l'original que des positions** : table des objets (type, image, x, y), caméra,
   carte. L'affichage lit ces données ; il n'intercepte pas les routines de tracé (sauf pour les
   neutraliser et gagner leur temps). Un emplacement d'affichage fixe par objet du jeu évite tout
   appariement de rectangles.
3. **Graphismes au format CPC préparés hors ligne, par niveau, sur disque** : sprites en mode 0 avec
   leurs deux variantes (pixel pair / impair), masques précalculés, tuiles de décor converties. Une
   chaîne `original → PNG → format CPC` sert en même temps aux retouches de l'auteur des graphismes.
   Plus de conversion ni de cache à l'exécution.
4. **Ce qui ne bouge pas va dans le décor** (tombes, pots, échelles, plateformes du décor) : dessiné
   une fois dans le décor propre, jamais dans la liste des sprites. Seuls les objets mobiles sont des
   sprites.
5. **Faire faire au CRTC ce que la machine d'origine faisait à la main** : défilement matériel, double
   tampon, bandeau fixe par rupture (voir ci-dessous), couleurs par palette plutôt que par astuces
   d'attributs.

**Pièges rencontrés, valables pour tout portage « logique d'origine + affichage CPC » :**

- **Le code d'origine appelle parfois sa ROM par accident.** Dans GnG, une routine dépile mal pendant
  l'intro et « revient » dans la ROM du Spectrum ($3828 : `LD H,E / CP (HL) / RET P`), qui retourne par
  chance à l'appelant. Sur CPC, cette adresse tombait dans nos données : exécution d'octets quelconques
  qui écrasait notre code. Détecter toute exécution hors du code valide dans le simulateur (un
  garde-fou dans la boucle d'exécution), puis reproduire exactement l'effet de la ROM.
- **Le jeu écrit dans sa zone ROM** (sans effet sur la machine d'origine) : si cette zone devient de la
  RAM à nous, y réserver de quoi absorber ces écritures ou les neutraliser.
- **Détournements de pile** (lecture de tables par `POP`) : avec des interruptions actives, chaque
  sauvegarde / restauration de SP du jeu doit être encadrée par `DI` / `EI` (crochets sur
  `LD (nn),SP` et `LD SP,(nn)`), sinon l'interruption empile dans les tables du jeu.
- **Démarrage à froid ≠ instantané** : une image disque qui reprend au menu n'exécute pas le code de
  démarrage ; si on démarre le portage au démarrage à froid, vérifier qu'il n'écrase rien (GnG
  recopiait une page sur le haut de sa carte).
- Les simulateurs qui sautent le chargement (police copiée depuis la ROM du CPC, AMSDOS) ne montrent
  pas les défauts du démarrage : tester le menu et les touches **annoncées à l'écran** dans un vrai
  émulateur.

**Rupture CRTC pour un bandeau fixe au-dessus d'un défilement matériel (mesuré dans GnG) :**

- Un **cadre court** (le bandeau de 2 rangées) exige une écriture de R4 moins de 16 lignes après sa
  fin ; avec une interruption toutes les 52 lignes, cela impose d'attendre dans l'interruption. Mettre
  plutôt le bandeau **sous** l'image : son cadre porte aussi toute la partie cachée de la trame et la
  VSYNC (R4 = 16, R6 = 2, R7 = 8), et chaque écriture a plusieurs rangées de marge. Cadre du jeu :
  lignes 72-247, 22 rangées (R4 = 21) ; R7 et R6 hors d'atteinte pendant ce cadre.
- Stocker le bandeau en **deux variantes** (la seconde décalée d'un octet) si l'image du jeu utilise
  l'astuce R3 pour le défilement à l'octet : on affiche celle qui compense R3.
- **Compter le rang de l'interruption** (6 par trame), le VSYNC ne servant qu'à le recaler : le jeu
  coupe les interruptions jusqu'à ~900 NOPs pendant ses détournements de pile, et une interruption
  servie après la fin d'une VSYNC courte serait mal classée. VSYNC de 16 lignes (R3 bits 4-7 = 0).
- Le registre I peut servir de compteur commun aux deux configurations mémoire (bits 0-2 = rang dans
  la trame, bits 3-7 = trames) ; ses variables doivent être à la même adresse dans les deux vues.

**Cadence et mémoire (suite du portage GnG, nuit du 30 septembre 2026) :**

- **Mesurer la cadence de l'original avant de fixer celle du portage** (GnG Spectrum : 25 tours/s
  partout, même dans les scènes chargées). Règle retenue : la logique garde l'échéance de
  l'original (2 trames par tour) ; en retard, on **saute des dessins jusqu'à rattraper**, et on ne
  remet l'échéance à l'heure qu'au-delà de ~8 trames. Remettre à l'heure dès 2 trames de retard
  ralentissait le jeu à 19-21 tours/s : les sensations changeaient.
- Le jeu peut savoir tôt qu'un tour ne sera pas dessiné : le moteur publie son échéance dans une
  zone commune aux deux vues ; si elle est déjà dépassée quand le jeu prépare ce que le moteur lira
  (journal du décor), il ne le prépare pas et laisse la demande pour le tour suivant.
- **Échange des écrans par l'interruption du VSYNC** : le moteur dépose R12/R13/R3 en attente et rend
  la main au jeu tout de suite ; il n'attend qu'avant de redessiner l'écran qu'il vient de quitter
  (un VSYNC s'est-il produit depuis la demande ?). Gain mesuré : ~8 000 NOPs d'attente par image.
  Attention : toute variable que l'ancienne bascule recopiait (bandeau affiché ou non) doit être
  recopiée ailleurs, sinon elle se fige.
- Défilement matériel : la voie rapide (colonnes entrées + octets de garde) doit couvrir tous les
  écarts que les images sautées produisent (jusqu'à 16 octets), sinon l'écran caché est recopié en
  entier justement quand on est en retard.
- **Mémoire morte de la machine d'origine** : l'écran virtuel de l'original (6 Ko, ici en banque 5),
  inutile pendant la partie, sert de cache. Protéger chaque page par un **octet témoin** (en fin de
  page, hors des données) : si le jeu efface son écran (mort, changement de section), le témoin
  disparaît et la case est refaite. Vérifier aussi qu'aucune routine d'origine n'y dessine encore
  (instantanés de la zone entre deux tours ; GnG avait un type d'objet, les éclats d'armure, dessiné
  hors journal : invisible sur CPC jusqu'à ce qu'on le trouve ainsi).
- Code rarement utilisé (convertisseur des écrans de menu) : rangé dans une autre banque et recopié
  dans une zone de travail libre à ce moment-là (le journal du décor, inutile au menu).
- Cache de conversion : **seconde chance** (horloge) plutôt que tour de rôle ; mesurer les
  reconversions (images déjà vues) pour dimensionner le cache.
- Place dans un code découpé en blocs (autour de la mémoire vidéo du bandeau) : couper entre deux
  instructions quelconques hors boucle (listing à plat), et convertir en JR les JP proches.
- Couleurs du décor par motif : les octets de remplissage d'une matière pleine (roche, sol) prennent
  un fond noir opaque ; sinon les trous du motif laissent voir le ciel (le papier noir de l'original).
- **Défilement vertical d'un moteur d'origine par bandes** (GnG, niveau 2) : ne pas tout
  redessiner à chaque pas de 2 lignes. Tant que le décalage cumulé reste sous 8 lignes, le
  décor ne bouge pas et les sprites sont décalés d'autant (un `RST` vers une routine
  « y + décalage » coûte 1 octet par site) ; à 8 lignes, défilement matériel d'une rangée
  (origine de l'anneau ± largeur de rangée) et seule la bande découverte est dessinée.
  **Piège** : quand le jeu recycle une bande (rotation de sa liste), toutes les hauteurs
  bougent aussi uniformément (± hauteur d'une bande) : lire l'identité des bandes (tête de
  liste du jeu) avant de croire à un déplacement. Mesuré : 19 -> 24,6 tours/s.
- Place : une table construite au démarrage (128 octets) peut devenir une petite routine de
  calcul ; la zone libérée reçoit du code recopié au démarrage par la même LDIR que les
  tables voisines (destinations contiguës).
