# CRTC, Gate Array, interruptions et temps fixe — ce qu'un jeu CPC doit savoir

> **Source** : *The Amstrad CPC CRTC Compendium* v1.11 (08.2026), Serge Querné (Longshot / Logon System),
> 296 pages, licence CC BY-NC-ND 4.0. Dans le dépôt Portage_Opti : `docs/references/ACCC1.11-EN.pdf`.
> Résultats vérifiés par l'auteur sur machines réelles avec son banc de test SHAKER
> (https://shaker.logonsystem.eu).
>
> **Mention à conserver** (demandée par la licence du document, y compris dans le code source et les
> crédits d'un programme ou d'un émulateur qui s'appuie sur ces informations) :
> `Technical information sourced from the "Amstrad CPC CRTC Compendium" by Longshot (CC BY-NC-ND).`
>
> **Ce fichier** n'est ni une traduction ni une copie : c'est un aide-mémoire en français, limité à ce qui
> sert pour écrire ou porter un **jeu**, avec les numéros de page du PDF pour aller lire le détail. Tout ce
> qui est écrit ici vient du Compendium, sauf les passages marqués **(déduit)**, qui sont des conséquences
> que j'en tire pour les jeux du corpus et qui n'ont pas été testées sur machine.
>
> Les numéros de section « §n » renvoient à `TECHNIQUES_OPTIMISATION_CPC.md` ; « p. n » au PDF.

---

## 0. Quand ouvrir le PDF (et à quelle page)

Le PDF est surtout un document pour démos et émulateurs : 80 % du texte décrit des compteurs au
microseconde près. Pour un jeu, ce fichier suffit presque toujours. Ouvre le PDF (outil de lecture avec une
plage de pages) seulement dans ces cas :

| Besoin | Pages |
|---|---|
| Types de CRTC, registres, qui lit/écrit quoi | 18–22 |
| Accès E/S : durées, moment exact de prise en compte, décodage des ports | 22–33 |
| Construction d'une trame (algorithme des compteurs C0, C9, C4, C5) | 34–37 |
| Synchronisation exacte sur la VSYNC (routine à la microseconde) | 38–41 |
| Gate Array : pixels par mode, moment exact d'un changement de couleur | 46–51 |
| Changement de mode graphique, partage de mode dans une ligne | 52–73 |
| R9, R5, R4, R0 : règles de comptage par CRTC, ruptures ligne à ligne, « RFD » du CRTC 1 | 74–130 |
| R3 et R2 : HSYNC, décalage horizontal d'un demi-caractère, CRTC 2 | 131–158 |
| R7 : VSYNC, conditions par CRTC | 159–175 |
| R1, R6, R8 : bord, affichage coupé, entrelacé | 176–241 |
| R12/R13 : quand l'adresse est prise en compte, écran de 32 Ko | 242–245 |
| Registres lisibles et registres d'état | 246–250 |
| Plein écran et centrage | 252–253 |
| Astuces de code Z80 | 254–269 |
| Programmation en temps fixe, routines d'attente | 270–281 |
| **Durée de toutes les instructions** | 282–283 |
| Interruptions (compteur du Gate Array, IM 1, IM 2, fiabilité) | 284–292 |
| Identifier le CRTC et la machine | 293–295 |

---

## 1. Les cinq types de CRTC

| Type | Circuit | Où |
|---|---|---|
| 0 | Hitachi HD6845S / UMC UM6845 | 464, 664, 6128 |
| 1 | UMC UM6845R (deux variantes, 1-A et 1-B) | 464, 664, 6128 |
| 2 | Motorola MC6845 | 464, 664, 6128 |
| 3 | ASIC 40489 | 464+/6128+/GX4000 |
| 4 | « pré-ASIC » 40226 | CPC tardifs à bas coût |

On ne peut pas savoir à l'avance quel type équipe une machine : un jeu doit marcher sur les cinq.
Les différences n'apparaissent que si l'on modifie des registres **pendant l'image** (ruptures), à des
moments particuliers (pendant une HSYNC ou une VSYNC), ou avec la valeur 0.

Vocabulaire du Compendium, repris ici : `Rn` = registre, `Cn` = compteur interne associé (C0 = caractère
dans la ligne, C9 = ligne dans la rangée, C4 = rangée, C5 = ligne d'ajustement), `VMA` = pointeur vidéo
courant, `VMA'` = pointeur du début de rangée. Trame CRTC = `(R4+1) × (R9+1) + R5` lignes.

---

## 2. Règles sûres pour un jeu (toutes machines)

### 2.1 R12/R13 : on ne peut pas les écrire « n'importe quand » (p. 243–244)

L'adresse de début est relue au début de la trame CRTC (C4 = C9 = C0 = 0), mais pas de la même façon
partout :

| CRTC | Quand R12/R13 sont pris en compte |
|---|---|
| 0, 3, 4 | une seule fois, quand C4, C9 et C0 passent à 0 |
| 1 | **à chaque début de ligne tant que C4 = 0**, donc pendant toute la première rangée de caractères |
| 2 | recopiés dans `VMA'` quand C0 atteint R1 **sur la dernière ligne** de la trame précédente ; après, c'est trop tard pour la trame suivante |

Règle qui marche partout : écrire R12 **et** R13
- après la première rangée de la trame (sinon, sur CRTC 1, l'adresse change au milieu de la rangée du haut) ;
- avant la partie affichée de la dernière ligne de la trame (sinon, sur CRTC 2, l'ancienne adresse reste une
  image de plus) ;
- les deux du même côté de cette limite (sinon une image mélange l'ancien R12 et le nouveau R13).

En pratique : **écrire R12/R13 juste après avoir détecté la VSYNC**. Avec les réglages standard (R4 = 38,
R7 = 30, R9 = 7), la trame suivante commence `(R4 + 1 − R7) × (R9 + 1) + R5` = 72 lignes après le début de
la VSYNC : on a environ 4 600 NOPs de marge. La zone à éviter sur CRTC 1 va de la 72e à la 80e ligne après
le début de la VSYNC (entre la 2e et la 3e interruption de l'image).

Le Compendium cite *007 The Living Daylights* (Domark, 1987) : l'adresse du panneau de score est écrite
trop tôt et, sur CRTC 1, remplace celle du décor.

**(déduit)** Une bascule de double tampon écrite à un moment quelconque de la boucle principale (Toki, §5.2)
peut donc produire, sur CRTC 1, une image dont la rangée du haut est coupée en deux. Le correctif est
gratuit : faire la bascule après l'attente de VSYNC.

### 2.2 VSYNC : sa longueur dépend du CRTC (p. 132, 159–171)

- La VSYNC du CRTC commence quand C4 atteint R7. Le Gate Array prend ensuite le relais : 26 lignes noires,
  dont 4 de signal pour le moniteur. La position verticale de l'image ne dépend que du **début** de la VSYNC.
- Longueur du signal lu sur le PPI (`$F5xx`, bit 0) : réglable par les 4 bits forts de R3 sur les CRTC 0, 3,
  4 (0 = 16 lignes) ; **toujours 16 lignes sur les CRTC 1 et 2**. La ROM programme R3 = `$8E`, donc 8 lignes
  sur 0/3/4 et 16 sur 1/2.
- Conséquences : ne jamais se caler sur la **fin** de la VSYNC ; ne pas tester le bit VSYNC entre la 8e et
  la 16e ligne en supposant un résultat. Si le code en dépend, reprogrammer R3 avec `$0E` (16 lignes
  partout). Exemple cité : *3D Starstrike* (1985), écrit sur CRTC 0, dont le viseur clignote sur CRTC 1 et 2.
- Sur CRTC 3 et 4, la VSYNC du CRTC doit durer au moins 3 lignes pour que le moniteur soit synchronisé.
- Écrire dans R7 la valeur courante de C4 déclenche une VSYNC immédiate sur CRTC 0, 1, 2 (sauf en tout début
  de ligne sur CRTC 0 et pendant la HSYNC sur CRTC 2), **jamais** sur CRTC 3 et 4 : R7 doit être programmé
  avant que C4 l'atteigne.
- L'image est visible à partir de la 34e ligne après le début de la VSYNC (moniteur CTM).

### 2.3 HSYNC : R2, R3 et le piège du CRTC 2 (p. 131–158)

- La HSYNC commence quand C0 = R2 et dure R3 (4 bits faibles) microsecondes. Le Gate Array affiche du noir
  environ 2 µs puis envoie au moniteur un signal de 4 µs au plus. R3 ≥ 6 donne le signal complet.
- **CRTC 2** : si la HSYNC est encore en cours quand la condition de VSYNC arrive (C0 = 0 de la ligne où
  C4 = R7), la VSYNC n'est jamais émise (« ghost VSYNC ») et l'image décroche. Il faut
  **R2 + R3 ≤ R0** (soit 63 en standard). R2 = 50 avec R3 = 14 ne marche pas sur CRTC 2 ; R2 = 50 demande
  R3 ≤ 13. C'est la raison historique des jeux « sans défilement sur Motorola » (*Get Dexter*, 1986).
- **R3 = 0** : pas de HSYNC, donc **plus d'interruptions**, sur CRTC 0 et 1 ; HSYNC de 16 µs sur 2, 3, 4.
  À ne jamais utiliser dans un jeu.
- Sur CRTC 3 et 4, la HSYNC est retardée de 1 µs par rapport aux CRTC 0, 1, 2 : l'image est décalée d'un
  caractère vers la gauche sur le même moniteur, et les interruptions arrivent 1 µs plus tard.
- Décalage horizontal de l'image entière :
  - R2 ± 1 = un caractère CRTC = 2 octets (16 pixels mode 2) ;
  - R3 (bits faibles) − 1, quand il est sous 6 = un **demi**-caractère = 1 octet vers la droite. Prendre la
    paire **5 ↔ 4** (écart exact sur tous les CRTC) et non 6 ↔ 5 (7 pixels au lieu de 8 sur CRTC 1) ; un
    moniteur mal réglé peut décrocher avec 4.
  - Combiné à R12/R13 (pas de 2 octets), cela donne un défilement horizontal matériel **à l'octet**
    (2 pixels mode 0, 4 pixels mode 1). Utilisé par *Skatewars* (1989).
  - Alterner R2 d'une ligne à l'autre fait osciller la position de synchronisation (p. 134).
    **(déduit)** C'est ce que montre le journal de Pinball Dreams (R2 alterné 45/47 à chaque ligne, §5.4).
- Changer R3 déplace aussi les interruptions, puisqu'elles suivent la fin de la HSYNC (§2.5 ci-dessous).

### 2.4 Mode graphique et couleurs : pas le même moment (p. 49–55)

- **Mode** : la valeur écrite au Gate Array n'est appliquée que **pendant la HSYNC suivante** (il faut une
  HSYNC d'au moins 2 µs). Un changement de mode écrit n'importe où dans la ligne N vaut proprement à partir
  de la ligne N + 1 : pas besoin de le placer au microseconde près, il suffit d'être sur la bonne ligne.
  C'est ce qui rend le partage mode 0 / mode 1 par interruption (§12.5) fiable sur toutes les machines.
- **Couleur d'une encre ou du bord** : appliquée tout de suite, au pixel près, donc visible au milieu d'une
  ligne. Pour une coupure nette, l'écrire pendant le bord ou la HSYNC, avec une attente calibrée.
  Le moment exact dépend de l'instruction (`OUT (C),r` ou `OUTI`, p. 50–51).
- Les pixels du mode 2 sont affichés 1/16 µs plus tôt que ceux des autres modes (sauf sur CPC+).
- Format d'un octet (p. 47) : mode 0 = 2 pixels, bits `A0 B0 A2 B2 A1 B1 A3 B3` (A = pixel gauche) ;
  mode 1 = 4 pixels, bits `A0 B0 C0 D0 A1 B1 C1 D1` ; mode 3 (non officiel) = 2 pixels en 4 couleurs.

### 2.5 Interruptions (p. 284–292)

- Le Gate Array compte les **fins de HSYNC** de 0 à 51 (compteur « R52 ») et demande une interruption quand
  il reboucle : toutes les 52 lignes, 6 par image. Il est remis à 0 à la fin de la 2e HSYNC qui suit le début
  de la VSYNC, ou par le bit 4 du registre de mode (écrire `%1001xxxx` en `$7Fxx`).
- L'interruption commence 1 µs après la fin de la HSYNC : sa position dans la ligne dépend de R2 + R3.
- Une interruption refusée (`DI`) reste en attente ; une seule peut attendre. Quand elle est enfin acceptée,
  le Gate Array efface le bit 5 de son compteur :
  - acceptée avec **moins de 32 lignes** de retard : rien ne change, les suivantes restent sur la grille ;
  - acceptée avec 32 à 51 lignes de retard : le compteur perd 32, **les interruptions suivantes sont
    décalées** jusqu'à la VSYNC suivante ;
  - au-delà de 52 lignes : une interruption est perdue.
  Donc : fenêtres `DI` de **moins de 32 lignes (≈ 2 000 NOPs)** si des interruptions servent à découper
  l'écran. Deux interruptions ne sont jamais séparées de moins de 20 lignes.
- Après `EI`, l'interruption ne peut arriver qu'après l'instruction suivante (`EI / RET` est sûr).
- Coût d'entrée : **5 NOPs en IM 1** (un `RST $38` dans le code en coûte 4), **7 NOPs en IM 2**.
- IM 2 : l'octet bas du vecteur est imprévisible sur CPC. Table de **257 octets identiques** et routine à
  une adresse dont les deux octets sont égaux (ex. table remplie de `$BC`, routine en `$BCBC`). Sert à
  libérer la page zéro (*The Great Escape*, 1986).
- Une interruption n'interrompt pas une instruction (sauf entre deux tours de `LDIR`, `OTIR`…) : elle arrive
  avec un retard qui dépend de l'instruction en cours. Pour tomber au microseconde près, faire précéder la
  zone sensible d'un **`HALT`** (*Trailblazer*, 1986). Sans `HALT`, ne pas compter sur la position exacte :
  selon le CRTC (surtout le type 1), une interruption peut passer une instruction plus tard.
- Sur CRTC 3 et 4, à réglages égaux, l'interruption arrive 1 µs plus tard.

### 2.6 Accès aux circuits (p. 22–33)

| Instruction | NOPs | Écriture prise en compte (CRTC 0, 1, 2) | (CRTC 3, 4) |
|---|---|---|---|
| `OUT (C),r` / `OUT (C),0` | 4 | 3e µs | **4e µs** |
| `OUT (n),A` | 3 | 3e µs | 3e µs |
| `OUTI` / `OUTD` | 5 | 5e µs | 5e µs |
| `IN r,(C)` | 4 | lecture à la 4e µs | idem |
| `INI` / `IND` | 5 | lecture à la 4e µs | idem |
| `IN A,(n)` | 3 | lecture à la 3e µs | idem |

- Pour du code calé au cycle près, `OUT (C),r` vers le CRTC agit **1 µs plus tard sur CRTC 3 et 4** ;
  `OUTI` agit au même moment partout. Préférer `OUTI` pour un code commun.
- `OUTI` décrémente B **avant** d'écrire : charger B avec le port + 1 (`$BE` pour écrire en `$BD`).
- `OUT (n),A` et `IN A,(n)` mettent **A** sur les 8 bits hauts de l'adresse : `LD A,$F5 / IN A,($FF)` lit le
  port B du PPI en 3 NOPs sans toucher B. `OUT ($FF),A` avec A = 12 sélectionne R12 (les bits 9–8 à 0
  = « sélection de registre ») : marche pour les registres 12, 8, 4, 0.
- `OUT (C),0` (`$ED $71`) envoie 0 sur le Z80 des CPC (255 sur un Z80 CMOS).
- **Le CRTC n'est pas relié à RD/WR** : un `IN` sur un port d'écriture du CRTC y **écrit** ce qui traîne
  sur le bus. Ne jamais faire de `IN` sur `$BCxx`/`$BDxx`.
- Décodage partiel (un bit à 0 sélectionne le circuit) : bit 15 = Gate Array (avec bit 14 à 1), bit 14 =
  CRTC (bits 9–8 : 00 sélection, 01 écriture, 10 état, 11 lecture), bit 13 = ROM, bit 12 = imprimante,
  bit 11 = PPI (bits 9–8 : ports A, B, C, contrôle), bit 10 = FDC. Garder à 1 les bits des circuits qu'on ne
  vise pas. Garder le bit 14 à 1 pour la configuration RAM (`$7Fxx`).
- Le numéro de registre du CRTC est tronqué à 5 bits et les valeurs à la largeur du registre.
- Ordre des écritures : quand on réécrit les mêmes registres à chaque ligne (R12/R13, ou plusieurs encres),
  alterner l'ordre d'une ligne à l'autre évite une sélection de registre par ligne (p. 254–255).

### 2.7 Couper l'affichage (p. 176, 189–192)

- **R1 = 0** : plus aucun caractère affiché, sur tous les CRTC. C'est le moyen sûr (R-Type 128K, §12.2).
- R6 = 0 marche aussi mais se comporte différemment en cours d'image : pris en compte tout de suite sur
  CRTC 0, 1, 2, seulement en début de ligne sur CRTC 3, 4. Écrire R6 = C4 allume le bord jusqu'à la trame
  suivante.
- Pendant que le bord est affiché, le pointeur vidéo continue d'avancer.

### 2.8 Plein écran (p. 252–253)

Sur un moniteur CTM on voit au plus **48 caractères (96 octets) × 272 lignes**. R2 = 50 (avec R3 ≥ 6) met
C0 = 0 à l'extrême gauche ; attention à la règle du CRTC 2 (§2.3) : R3 ≤ 13. Un écran de plus de 16 Ko se
fait sans rupture avec les bits 3–2 de R12 à `11` : le pointeur passe alors à la page suivante en fin de
bloc (p. 245).

### 2.9 Défilement matériel : la couture (p. 266–268)

Le pointeur vidéo reboucle tous les 1 024 mots tant que les bits 3–2 de R12 ne sont pas à `11`. Dès que
R12/R13 ne vaut plus 0, une ligne d'écran est donc **coupée** quelque part en mémoire (après `$C7FF` vient
`$C000`, pour chaque ligne de pixel). Conséquences pour les routines de dessin :
- « ligne suivante » = +`$800` ; en bas de rangée, ajouter `2 × R1` puis **remettre à 0 le bit 3 de
  l'octet fort** si l'addition a débordé du bloc de 2 Ko (exemple p. 267 pour un écran en `$C000`) ;
- un sprite ou une tuile peut être à cheval sur la couture : corriger le pointeur à chaque octet coûte trop
  cher ; prévoir une routine spéciale pour la seule rangée qui contient la couture.
- Avec R1 = 32 et un défilement vertical par rangées entières (§5.3), la couture tombe toujours entre deux
  rangées : aucun cas spécial. C'est une raison de plus de choisir 64 octets par ligne. Un défilement
  horizontal matériel casse cet alignement.

Test de fin de rangée selon la page de l'écran, après `LD A,H / ADD A,8 / LD H,A` (p. 266) : `$C000` →
retenue (`RET NC`) ; `$4000` → signe (`RET P`) ; `$0000` et `$8000` → `ADD A,A` puis test.

---

## 3. Ruptures : ce qui change d'un CRTC à l'autre

Ordre de préférence pour un jeu :
1. **découper par interruption** (palette, mode) : ne dépend pas du CRTC ;
2. **rupture simple** (quelques trames CRTC empilées, une par zone) : marche partout si l'on suit les règles
   ci-dessous ;
3. **rupture ligne à ligne** et au-delà : il faut une variante de code par famille de CRTC, du temps fixe et
   un test sur chaque type.

### 3.1 Rupture simple (zones de plusieurs rangées)

- Somme des lignes de toutes les trames CRTC = 312 ; **une seule VSYNC** par image : dans les autres
  trames, R7 doit valoir une valeur que C4 n'atteint pas (R7 est sur 7 bits : 127).
- **R4** : ne jamais écrire une valeur inférieure au C4 courant, sinon C4 continue jusqu'à 127 (p. 93–102).
  Écrire le R4 d'une zone au début de cette zone.
- **R12/R13 de la zone suivante** : pendant la zone courante, après sa première rangée (CRTC 1) et avant la
  fin de sa dernière ligne affichée (CRTC 2) — voir §2.1.
- **R7** : le programmer avant que C4 l'atteigne (CRTC 3, 4) ; pas pendant la HSYNC (CRTC 2) ; pas dans les
  2 premières µs d'une ligne (CRTC 0).
- **R5** (lignes d'ajustement) : pendant ces lignes, C4 vaut R4 + 1 une seule fois sur CRTC 0, continue de
  compter sur CRTC 1 et 2, **reste à R4** sur CRTC 3 et 4. Un R6 ou un R7 censé tomber dans les lignes
  d'ajustement ne donne donc pas le même résultat partout (p. 81–87, 293).
- **R9** : écrire une valeur inférieure au C9 courant fait déborder C9 jusqu'à 31 sur CRTC 0, 1, 2 ; sur
  CRTC 3 et 4, C9 repasse à 0 à la ligne suivante (p. 75–78).
- **R6** : pris en compte immédiatement (CRTC 0, 1, 2) ou en début de ligne (CRTC 3, 4).
- Toutes les écritures par `OUT (C),r` agissent 1 µs plus tard sur CRTC 3 et 4.
- Ne pas faire ces écritures depuis une interruption qui coupe du code quelconque : le retard variable de
  l'interruption (§2.5) imite une différence de CRTC.

### 3.2 Rupture ligne à ligne (R4 = R9 = 0 : une trame par ligne) (p. 93–102)

| CRTC | Comment entrer dans la rupture ligne à ligne |
|---|---|
| 1 | mettre R4 et R9 à 0 **quand C4 = C9 = 0** (première ligne) ; le plus simple |
| 3, 4 | pareil ; acceptent aussi la méthode du CRTC 0 |
| 0 | notion de « dernière ligne » évaluée pendant les 2 premières µs : mettre R9 et R4 à 0 sur la **dernière** ligne de la trame (après C0 = 1) |
| 2 | « dernière ligne » aussi, mais une ligne ne peut pas être reconnue dernière deux fois de suite : il faut faire varier R9 **pendant la HSYNC de chaque ligne** puis le remettre à 0 ; les écritures de R4/R9 pendant la HSYNC sont ignorées pour cette évaluation |

C'est exactement la séparation que fait Pinball Dreams (§3.2 : le code est modifié quand le CRTC n'est ni 0
ni 2). Sur CRTC 0, avec des trames de 2 µs, R12/R13 ne sont relus que toutes les 4 µs.

### 3.3 Particularités à connaître

- **CRTC 1, « RFD »** (p. 88–91) : passer R5 de 0 à une valeur non nulle exactement quand C0 = R0 laisse
  R12/R13 pris en compte à chaque ligne sans toucher à R4 ni R7. Propre au type 1, et une valeur (`$10`)
  ne se comporte pas pareil sur toutes les machines de ce type.
- **R1 > R0** : le pointeur de rangée n'est plus mis à jour, les rangées se répètent ; CRTC 0 et 2 ajoutent
  un octet de bord entre deux lignes (p. 178–188).
- **R8** : décalage du bord et coupure de l'affichage sur CRTC 0, 3, 4 seulement ; entrelacé différent sur
  chaque type (p. 193–241). À laisser à 0 dans un jeu.

---

## 4. Reconnaître le CRTC (p. 246–250, 293–295)

| Test | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| Relire R12/R13 en `$BFxx` | oui | non (0) | non (0) | oui | oui |
| Port `$BExx` | rien de fiable (255 ou 127 au hasard) | registre d'état : bit 5 = 1 quand C4 a atteint R6 (hors zone affichée) | 255 | **même chose que `$BFxx`** | idem 3 |
| Longueur de VSYNC avec R3 = `$8E` | 8 lignes | 16 | 16 | 8 | 8 |
| R3 = 0 | pas d'interruption | pas d'interruption | HSYNC de 16 µs | 16 µs | 16 µs |
| R14/R15 (curseur) relisibles | oui | oui | oui | oui | oui |
| Registres d'état R10/R11 lisibles | non | non | non | oui | oui |
| Fonctions « Plus » après la séquence de déverrouillage | non | non | non | **oui** | non |

Recette **(déduite des lignes ci-dessus, à tester sur émulateur précis ou sur machine)** :
1. sélectionner R12, y écrire une valeur de test, lire `$BFxx` : valeur relue → type 0, 3 ou 4 ; zéro → 1 ou 2 ;
2. parmi 1 et 2 : lire `$BExx` pendant la zone affichée puis pendant la VSYNC ; si le bit 5 change → type 1,
   sinon type 2 ;
3. parmi 0, 3, 4 : lire `$BExx` avec R12 sélectionné ; même valeur qu'en `$BFxx` → 3 ou 4, sinon 0 ;
4. 3 contre 4 : le 3 est un CPC+ (séquence de déverrouillage de l'ASIC, ou port C du PPI qui n'est pas
   remis à 0 par une écriture du registre de contrôle).
Remettre R12 à sa valeur ensuite. R14 et R15 ne servent à rien sur CPC et sont relisibles partout : on peut y
ranger le type trouvé.

Ne pas utiliser `$BExx` pour distinguer 0 de 2 : ces deux types n'ont pas de registre d'état.

---

## 5. Programmer en temps fixe (p. 270–281)

Sur CPC la durée d'une instruction ne dépend de rien d'autre que de l'instruction (et de la branche
prise) : on peut compter.

- **Principe** : toute routine dure sa durée **maximale** ; les branches courtes sont allongées.
- **Branches disjointes** : compléter la plus courte par des `NOP`.
- **Branche qui rejoint du code commun** : préparer les deux résultats avant le test, puis ne laisser dans
  la branche qu'une instruction de 1 NOP. `JR cc` coûte 2 (non pris) ou 3 (pris) : l'instruction de 1 NOP
  exécutée seulement quand le saut n'est pas pris égalise les deux chemins.
  ```z80
          ld a,(compteur)     ; 4
          dec a               ; 1
          ld b,10             ; 2   valeur de rechargement préparée dans tous les cas
          jr nz,.ok           ; 2 / 3
          ld a,b              ; 1 / 0
  .ok:    ld (compteur),a     ; 4      -> 14 NOPs sur les deux chemins
  ```
  Avec deux contextes complets, préparer l'un, `EXX`, préparer l'autre, puis `JR cc` par-dessus un `EXX`.
- **Aiguillage** : une table d'adresses indexée + `JP (HL)` dure toujours pareil ; une suite de `CP / JR`
  non.
- **Interruptions** : les couper, ou les compter (5 NOPs d'entrée en IM 1) et se recaler par `HALT`.
- **Attendre** : une suite de `NOP` dans laquelle on entre plus ou moins loin (`CALL attente + n`) donne
  toute durée de 8 à 64 NOPs ; pour plus long, une boucle `DEC DE / LD A,D / OR E / JR NZ` (7 NOPs par tour)
  terminée par un saut calculé dans des `NOP` (routines complètes p. 41, 278, 281).
- Instructions « neutres » pour perdre du temps en peu d'octets :

  | Séquence | NOPs | Octets | Attention |
  |---|---|---|---|
  | `NOP` | 1 | 1 | |
  | `CP (HL)` | 2 | 1 | modifie F |
  | `JR $+2` | 3 | 2 | |
  | `INC HL / DEC HL` | 4 | 2 | |
  | `INC (HL) / DEC (HL)` | 6 | 2 | modifie F, écrit en mémoire |
  | `PUSH HL / POP HL` | 7 | 2 | écrit sous la pile |
  | `EX (SP),HL` × 2 | 12 | 2 | |

- Un code en temps fixe sur 19 968 NOPs n'a plus besoin d'attendre la VSYNC. Se caler une fois au
  microseconde près : boucle de 19 969 NOPs qui « glisse » d'une µs par image jusqu'à voir le bit VSYNC
  (p. 39–41).
- Outil : un calculateur de durée (source Z80 sur logonsystem.eu) mesure le code entre deux adresses et
  permet de compenser automatiquement (p. 277–279).

---

## 6. Astuces Z80 du chapitre 24 (compléments au §9)

- **`JP (HL)` = 1 NOP**, `JP (IX)`/`JP (IY)` = 2. Liste d'adresses exécutée par la pile : chaque routine
  finit par `RET` (3 NOPs), SP pointe sur la table ; interruptions coupées (p. 261).
- **Pages de 256 octets** : `INC L` = 1 NOP, `INC HL` = 2. Ranger une structure de plusieurs champs en
  **tables parallèles** sur des pages consécutives : `LD E,(HL) / INC H / LD D,(HL) / INC H / LD C,(HL)`
  lit trois champs du même index en 8 NOPs. Si l'on garde des structures entrelacées, leur donner une taille
  qui divise 256 (quitte à ajouter un octet) pour ne jamais franchir une page (p. 262–264).
- Donnée alignée sur une adresse paire : alterner `INC L` / `INC HL` (le débordement de page n'arrive que
  sur une adresse impaire).
- **Dérouler à moitié** : 10 `LDI` + `DEC A / JR NZ` pour 2 000 octets = 10 799 NOPs et 31 octets, contre
  12 008 en `LDIR` et 10 006 (mais 4 006 octets) tout déroulé. Avec 20 `LDI` par tour : 10 407 NOPs (p. 260).
  Le code peut aussi générer le code déroulé au démarrage.
- **Automodification** (p. 256–259) : étiquette placée sur l'opérande (`var equ $-1`) ; `XOR 1` sur le code
  d'un `INC r` en fait un `DEC r` (`XOR 8` pour les registres 16 bits) ; le 2e octet d'un `OUT (C),r`
  choisit le registre (`$79` A, `$41` B, `$49` C, `$51` D, `$59` E, `$61` H, `$69` L, `$71` zéro) ;
  pour neutraliser un `OUT (C),C` sans changer sa durée, le remplacer par `INC HL / DEC HL` (4 NOPs).
- **`ADD HL,BC` (`$09`) ↔ `ADD HL,SP` (`$39`)** : dans une routine de sprite déroulée, avec BC = `$800` et
  SP = `$C800 + 2 × R1`, modifier cet octet choisit « ligne suivante » ou « rangée suivante » : une seule
  routine sert pour toutes les positions verticales (p. 259).
- `OUTI`/`OUTD` : C et N sont mis à 1 quand valeur envoyée + L (après incrément) dépasse 255 ; permet de
  détecter une fin de table sans compteur (p. 256).
- Boucle 16 bits : `DEC BC / INC B / DJNZ` avec BC = nombre + 255 ne touche pas A (p. 265) ; `CPI / JP PE`
  avance HL et compte BC en 7 NOPs.
- Pointeur de table qui sert aussi de port : placer des tables en `$BCxx`, `$BDxx`, `$BExx`, `$7Fxx` pour
  que B soit à la fois l'octet fort du pointeur et le port (p. 255).
- Remplacements : `CPL / ADD A,d+1` pour `NEG / ADD A,d` ; `ADD A,A / JP M` pour `BIT 6,A / JP NZ` ;
  `XOR A / SUB r` pour `LD A,r / NEG` ; `OR A` pour `CP 0` ; `CPL` pour `XOR $FF` (p. 269).

---

## 7. Durée des instructions en NOPs (p. 282–283)

`r` = A, B, C, D, E, H, L ; `rr` = BC, DE, HL, SP ; `op` = ADD, ADC, SUB, SBC, AND, OR, XOR, CP ;
`x/y` = saut pris / non pris.

| NOPs | Instructions |
|---|---|
| 1 | `NOP`, `LD r,r'`, `INC r`, `DEC r`, `op r`, `RLCA`, `RRCA`, `RLA`, `RRA`, `CPL`, `DAA`, `SCF`, `CCF`, `EX DE,HL`, `EX AF,AF'`, `EXX`, `DI`, `EI`, `HALT`, **`JP (HL)`** |
| 2 | `LD r,n`, `LD r,(HL)`, `LD (HL),r`, `LD A,(BC/DE)`, `LD (BC/DE),A`, `op n`, `op (HL)`, `INC rr`, `DEC rr`, `LD SP,HL`, `NEG`, `IM n`, rotations et décalages `CB` sur `r`, `BIT/SET/RES b,r`, `JP (IX/IY)`, `LD`/`INC`/`DEC`/`op` sur `IXH/IXL/IYH/IYL` |
| 3 | `LD rr,nn`, `LD (HL),n`, `INC (HL)`, `DEC (HL)`, `ADD HL,rr`, `POP rr`, `RET`, `JP nn`, `JP cc,nn` (pris ou non), `JR e`, `BIT b,(HL)`, `OUT (n),A`, `IN A,(n)`, `INC IX`, `DEC IX`, `LD IXH,n`, `LD SP,IX`, `LD A,I`, `LD A,R` |
| 4 | `PUSH rr`, `LD A,(nn)`, `LD (nn),A`, `OUT (C),r`, `OUT (C),0`, `IN r,(C)`, `ADC HL,rr`, `SBC HL,rr`, `ADD IX,rr`, `LD IX,nn`, `POP IX`, `RST n`, `RETI`, `RETN`, `CPI`, `CPD`, rotations et décalages sur `(HL)`, `SET/RES b,(HL)` |
| 5 | `CALL nn`, `LD HL,(nn)`, `LD (nn),HL`, `LDI`, `LDD`, `OUTI`, `OUTD`, `INI`, `IND`, `RLD`, `RRD`, `PUSH IX`, `LD r,(IX+d)`, `LD (IX+d),r`, `op (IX+d)` |
| 6 | `LD rr,(nn)` et `LD (nn),rr` pour BC, DE, SP, IX, IY ; `EX (SP),HL` ; `LD (IX+d),n` ; `INC (IX+d)` ; `DEC (IX+d)` ; `BIT b,(IX+d)` |
| 7 | `EX (SP),IX` ; rotations, décalages, `SET/RES` sur `(IX+d)` |
| 3/2 | `JR cc,e` |
| 4/3 | `DJNZ e` |
| 4/2 | `RET cc` |
| 5/3 | `CALL cc,nn` |
| 6/5 | `LDIR`, `LDDR`, `OTIR`, `OTDR`, `INIR`, `INDR` (par tour / dernier tour) |
| 6/4 | `CPIR`, `CPDR` |
| — | entrée dans une interruption : 5 (IM 1), 7 (IM 2) |

Pièges fréquents : `LD (nn),SP` coûte 6 (et non 5 comme `LD (nn),HL`) ; tout ce qui passe par `IXH/IXL`
coûte 1 NOP de plus que le registre simple ; `(IX+d)` coûte 3 NOPs de plus que `(HL)`.
