# Porter un jeu Game Boy sur ZX Spectrum 48K : méthode


---

## 1. Le principe : traduire la ROM, pas réécrire le jeu

On ne réécrit pas le jeu en observant comment il se comporte. **La logique du jeu est la ROM Game Boy elle-même, traduite instruction par instruction du SM83 vers le Z80.** Cela couvre le déroulement de la partie, les objets, la physique, l'IA et le score. Ce qu'on écrit à la main, c'est tout ce qui touche au matériel : affichage, entrées, son, cadence et menus.

Pourquoi c'est la bonne approche :
- **Fidélité exacte.** Les deux jeux ont la même physique, la même IA et les mêmes timings. L'utilisateur l'exigeait (« ne repars pas du Basic mais de la ROM ! »), et une réécriture « à l'œil » s'en écarte toujours.
- **Vérifiable.** Le même état RAM, soumis au même pas de logique, doit donner le même résultat sur GB et sur Spectrum. Un outil le compare automatiquement (§6).
- **Rapide.** Le SM83 est un cousin du Z80 : la plupart des instructions existent telles quelles. Dans Tennis, 3794 instructions ont été traduites automatiquement.

**Pourquoi l'assembleur plutôt que Boriel Basic.** Tennis a d'abord été porté en Boriel Basic, puis refait en assembleur. Le Basic a coûté cher : bugs du compilateur (voir §11), accès lents à la RAM GB, et une logique réécrite qui divergeait de l'original. En assembleur, la logique traduite s'insère directement et le moteur d'affichage peut être optimisé au cycle près. **Partir directement en assembleur (sjasmplus).**

---

## 2. Outils

| Outil | Rôle | Installation / emplacement (machine de l'utilisateur) |
|---|---|---|
| **sjasmplus 1.24** | Assembleur Z80 : `DEVICE ZXSPECTRUM48`, `SAVETAP`, `MACRO`, `ASSERT` | `%LOCALAPPDATA%\sjasmplus\sjasmplus-1.24.0.win\sjasmplus.exe` |
| **mgbdis** | Désassembleur GB (copié dans `template/tools/mgbdis`, licence MIT) | Fourni |
| **SkoolKit** | Simulateur Z80/Spectrum en Python (`CSimulator`), `tap2sna.py` | `pip install skoolkit` |
| **PyBoy** | Émulateur GB piloté en Python, pour la comparaison pas à pas | `pip install pyboy` |
| **Pillow** | Images (captures, extraction des graphismes) | `pip install pillow` |
| **ZEsarUX 13** | Émulateur Spectrum pour jouer (l'utilisateur teste lui-même) | `%LOCALAPPDATA%\ZEsarUX\ZEsarUX_windows-13.0\zesarux.exe` |

Lancer le jeu pour l'utilisateur (PowerShell) :
```powershell
& "$env:LOCALAPPDATA\ZEsarUX\ZEsarUX_windows-13.0\zesarux.exe" --noconfigfile --machine 48k --zoom 2 --fastautoload "<chemin>\asm\build\game.tap"
```

Sous Windows, lancer Python avec `python -X utf8` : les sorties contiennent des accents.

---

## 3. Étape 0 : décisions à prendre avec l'utilisateur

À demander au début. Ce sont les choix qui ont structuré Tennis :

| Question | Choix pour Tennis |
|---|---|
| Fidélité exacte à la ROM, ou adaptation libre ? | Exacte (logique traduite) |
| Machine cible ? | 48K |
| Son ? | Bruitages au beeper seulement, pas de musique |
| Couleurs ? | Terrain monochrome, couleurs dans le décor (public, arbitre) et l'écran titre |
| Modes de jeu ? | 1 joueur contre l'ordinateur seulement (pas de câble link) |
| Contrôles ? | Clavier QAOP + ESPACE, et joystick Kempston |
| Boutons A/B du GB avec un seul bouton ? | Voir §9 : une règle automatique, décidée selon le contexte |
| Langue des textes ? | Anglais |

L'utilisateur veut **voir le jeu tourner après chaque étape** : faire des captures avec `zxrun.py`, puis relancer ZEsarUX.

---

## 4. Étape 1 : rétro-ingénierie de la ROM

Placer la ROM dans `re/game.gb` et copier `template/` à la racine du nouveau repo.

1. **Tracer le code** : `python tools/gb_trace.py`. Le script sépare le code des données en suivant le flot d'exécution depuis les vecteurs. Il signale les `jp hl` non résolus : trouver leurs cibles à la main et les ajouter à `TRACE_ENTRIES`. Il signale aussi les routines appelées qui commencent par `pop hl`, qui indiquent souvent des données placées après le `CALL`.
2. **Désassembler** : `python tools/mgbdis/mgbdis.py re/game.gb --tiny --print-hex --overwrite`, qui utilise le `.sym` produit par le traceur.
3. **Lire les RST** (`$0000-$003F`). Les jeux Nintendo s'en servent comme d'instructions maison. Pour Tennis :
   - `rst $08` : saut indexé par A, suivi d'une table de `dw`. C'est ce qui fait tourner toutes les machines à états.
   - `rst $18` : lecture indexée, suivie de `db N` et de N octets.
   - `rst $28` : copie vers `[DE]`, même format.

   Les déclarer dans `RST_JUMPTABLE` et `RST_INLINE_DATA`, puis relancer le traceur jusqu'à ce que le rapport soit propre.
4. **Écrire une fiche du jeu** (`re/FICHE_JEU.md`, cf. Tennis) :
   - carte de la ROM ;
   - carte de la RAM (objets, états, score) ;
   - boucle principale et routine VBlank ;
   - machine à états des écrans ;
   - utilitaires (hasard, multiplications) ;
   - format des graphismes et des tilemaps.

   Marquer **(à confirmer)** ce qui n'a pas été lu ligne à ligne.
5. **Trouver les racines de la logique.** Ce sont les routines que la boucle principale appelle pendant le jeu (Tennis : match, joueur 1, joueur 2, balle, IA), séparées de l'affichage : copie OAM, VRAM, défilement.

---

## 5. Étape 2 : fermeture et traduction

1. Remplir `ROOTS` dans `port_config.py`, puis lancer `python tools/gb_closure.py`. Le script liste :
   - **les accès au matériel GB** (`$FF00-$FF7F`, VRAM, OAM). Chacun devient un **stub** (`STUBS` : adresse → routine Spectrum `S_xxx`), ou la routine qui les contient n'est pas traduite. Dans Tennis, les stubs étaient le son `$3665`, le changement d'écran `$016D`, la musique et la démo (`S_RET`) ;
   - **les immédiats 16 bits < $8000**, à classer un par un :
     - adresse de code (`CODE_PTRS`, par exemple les adresses de retour empilées) ;
     - adresse de données (`DATA_PTRS` et `DATA_BLOCKS`, recopiées sous forme d'étiquettes `D_xxxx`) ;
     - simple constante.
2. **Traduire** : `python tools/gb2z80.py` écrit `asm/gb/gb_logic.asm`. Chaque ligne garde l'adresse GB en commentaire. On ne modifie jamais ce fichier à la main : on change la config et on relance.

**Règles de traduction** (appliquées par l'outil) :
- La RAM GB garde ses adresses : `$C000-$DFFF` et `$FF80-$FFFE` sont réservées côté Spectrum, donc `ldh [$xx],a` devient `ld ($FFxx),a`.
- Tous les `jr` deviennent des `jp` : le code traduit est plus long, et un `jr` serait souvent hors de portée.
- `ld a,[hl+]` devient `ld a,(hl)` + `inc hl`.
- `swap a` devient `rrca` ×4 + `or a` (mêmes flags).
- `rst` devient `call G_RSTxx`, suivi de sa table ou de ses données.
- `reti` devient `ret`. Les routines traduites ne sont jamais des gestionnaires d'interruption.

**Différences SM83/Z80 à surveiller** (signalées par l'outil) :
- `rlca/rrca/rla/rra` : le GB met Z à 0, le Z80 ne touche pas à Z. Un saut sur Z qui suit l'une d'elles est signalé.
- `add sp,e`, `ld hl,sp+e`, `ld [a16],sp`, `stop` n'existent pas en Z80. L'outil émet `ASSERT 0`, qui fait échouer l'assemblage à l'endroit exact à traiter.
- `ld [$ff00+c]` est traduit via BC, mais vérifier s'il s'agit d'un registre matériel.
- Le **hasard** : dans Tennis, la ROM fait tourner son générateur (`$00A9`) en boucle pendant l'attente du VBlank. Il faut l'appeler aussi dans `wait_frame`, sinon l'IA devient prévisible.

**Réglages volontaires** : `PATCHES` remplace une instruction GB par un `jp` vers du code Spectrum. Dans Tennis, `$10A6 → jp S_P1SHOT` atténue de 10 % les coups croisés du joueur. Le réglage reste isolé et documenté, et il suffit de le retirer pour revenir au comportement GB exact.

---

### Déplacer la RAM GB (`RAM_MAP`)

Sur une machine sans RAM en `$C000-$DFFF` / `$FF80-$FFFE` (ColecoVision : 1 Ko en `$7000` ; MSX : zone système en `$FF80`), on définit dans `port_config.py` une fonction `RAM_MAP(adresse GB) -> adresse cible ou None`. `gb2z80.py` l'applique :
- aux `ld (a16)` et aux `ldh` ;
- à l'octet haut des `ld (c)` ;
- aux immédiats 16 bits `ld rr,d16` qui tombent dans la RAM déplacée.

Il avertit si un accès RAM n'est pas couvert. On mesure d'abord ce que la logique utilise vraiment, puis on vérifie par la comparaison pas à pas. Voir [../gb2coleco-kit/PORTING.md](../gb2coleco-kit/PORTING.md) §3.

## 6. Étape 3 : le code de liaison (`asm/src/gb_support.asm`)

- **`G_RSTxx`** : les RST réécrits en Z80. Ce sont des `call`, avec l'adresse de retour qui pointe sur la table ou les données.
- **`S_SOUND`** mémorise le numéro de son. Il est joué après l'affichage, parce que le beeper bloque le CPU.
- **`S_SCREEN`** : sur GB, un changement d'écran repart souvent de zéro (`ld sp,...`). On fait la même chose : `gb_tick` mémorise SP (`tick_sp`) et `S_SCREEN` le restaure. **Le reste du pas de logique est donc abandonné, comme sur GB.** Sans ça, dans Tennis, la balle avançait d'un pas de trop en fin de jeu.
- **`gb_new_game`** et **`gb_tick`** reproduisent les séquences d'appel lues dans la ROM : mise à zéro de la RAM, options, fiche de niveau, puis les racines de la logique dans l'ordre de la boucle principale.
- **`gb_set_pad`** reproduit la routine joypad de la ROM (touches maintenues et touches nouvellement pressées).

### Valider : `python tools/diff_gb.py 2000`

Le vrai jeu tourne dans PyBoy, piloté par un robot (`Bot` dans la config). À chaque trame, l'état RAM GB est injecté dans le Spectrum simulé, qui exécute un seul `gb_tick`. On compare ensuite la RAM obtenue à celle du GB. Il faut exclure de la comparaison le joypad, le hasard s'il avance pendant l'attente, et ce que seul l'affichage GB écrit (tampons de texte, OAM, défilement).

Résultat sur Tennis : 11 241 pas identiques, hors transitions d'écran. Il ne reste que les écarts dus au patch volontaire. **C'est la preuve de fidélité : la relancer après chaque changement de la config ou du code de liaison.**

---

## 7. Étape 4 : affichage

### Graphismes
- **Rejouer ce que fait le jeu** au lieu de chercher les images au hasard. `gbgfx.VRAM` rejoue les copies de tuiles vers `$8000-$9FFF` et le décodeur de tilemap du jeu (propre à chaque jeu ; celui de Tennis est en `$326B`, voir `re/extract_gfx.py` du repo Tennis), puis rend l'écran en PNG.
- **Sprites** : assembler les listes OAM du jeu (`gbgfx.sprite_from_oam_list`), puis les convertir avec `mono_sprite.to_mono`. Teintes : 3 → encre, 2 → trame d'un pixel sur deux, 1 → papier opaque, 0 → transparent. Chaque sprite a un masque.
- **Projection.** L'écran GB fait 160×144, le Spectrum 256×192. Dans Tennis, les sprites sont gardés à l'échelle 1 et seules **les positions** sont projetées : même formule que la ROM, mise à l'échelle ×1,25 en X et ×0,8 en Y. Le décor (court, lignes) est redessiné en vectoriel à la résolution Spectrum.
- **Couleurs** : 2 couleurs par case de 8×8. La zone de jeu reste monochrome (encre noire sur papier vert) et la couleur va dans le décor fixe : public, arbitre, cadre, scores. Des pixels clairs de sprite qui effacent une ligne du court sont un comportement fidèle au GB.

### Moteur de sprites (`template/asm/src/sprite.asm`, repris tel quel)
- **Deux temps.** Pendant la logique, `spr_prepare` calcule la position. Si l'image ou le décalage au pixel a changé, le sprite est **pré-décalé** dans le cache de son emplacement. Juste après l'interruption, `draw_all` fait tous les `spr_restore` en ordre inverse, puis tous les `spr_draw` : sauvegarde du fond, puis dessin masqué.
- **Boucles déroulées.** Les données sont lues par `pop` (SP pointé sur le sprite, interruptions coupées) et la restauration se fait par `LDI`.
- **Décalage par rotations de registres** : masques dans B-E, dessins dans les registres alternés. On fait s passes à droite, ou 8−s passes à gauche, donc jamais plus de 4.
- **Piège** : un `push` pendant que SP pointe sur les données du sprite les écrase. Sauvegarder dans un registre.
- **Ne pas étaler les re-décalages sur plusieurs images pour gagner du temps.** Tennis l'a essayé : les personnages ne bougeaient plus de façon fluide et l'utilisateur a refusé. La fluidité passe avant.

---

## 8. Étape 5 : cadence et mémoire

- **Interruption IM2** : table de 257 × `$FD` en `$FE00`, et saut en `$FDFD`. La routine d'interruption ne fait qu'incrémenter `frames`.
- **Rythme GB exact** : le GB tourne à 59,7 Hz et le Spectrum à 50 Hz. On fait donc 6 pas de logique toutes les 5 trames (motif 2,1,1,1,1). On rattrape les trames en retard, avec un plafond de 6.
- **Mémoire contendue.** Sur un vrai 48K, `$4000-$7FFF` est ralentie par l'ULA. On y place le code **froid** (démarrage, menu, texte, décor, écran titre) et tout ce qui tourne à chaque image en `$8000+`. Après ce déplacement (et l'optimisation du décalage des sprites), Tennis affiche environ 83 % des images sur vrai matériel, soit ~42 images/s, mesuré avec `zxrun.py --cmio`.
- **Carte mémoire de Tennis** :

  | Zone | Contenu |
  |---|---|
  | `$6000-$7FFF` | Code froid |
  | `$8000-$BFFF` | Code chaud et logique traduite |
  | `$C000-$C0FF` | RAM GB |
  | `$D400` | Caches des sprites |
  | `$DD00` | Octet son GB |
  | `$E000` | Graphismes des sprites |
  | `$F800` | Chargeur BASIC (assemblé seulement) |
  | `$FDFD` / `$FE00` | Interruption IM2 |
  | `$FF80` | HRAM GB |

  Des `ASSERT` vérifient que les zones ne se chevauchent pas.
- **Cassette** : BASIC, puis `SCREEN$`, puis 3 blocs `CODE` (froid, chaud, graphismes). Le BASIC s'écrit en `db`, avec les nombres en `VAL "..."` (plus court). `POKE 23739,111` empêche les en-têtes « Bytes: » de s'écrire sur l'écran de chargement.

---

## 9. Étape 6 : entrées, son, écrans

- **Un seul bouton.** Le joystick Spectrum n'a qu'un bouton de tir, alors que le GB a A et B. Dans Tennis, B (le lob) est **déclenché automatiquement** quand l'adversaire est au filet et que le joueur n'y est pas. La décision est prise à l'appui et tenue jusqu'au relâchement. L'utilisateur a **refusé** les combinaisons tir + direction (« trop de la bidouille ») et l'« armement » pendant le coup adverse (« nul comme gameplay ») : préférer une règle automatique simple et invisible.
- Directions opposées annulées, comme le fait la ROM.
- **Son** : table « numéro de son GB → période et durée » au beeper, avec du bruit pour les sons percussifs (filet, public). Garder les sons très courts : le beeper occupe tout le CPU pendant qu'il sonne.
- **Écran titre** : composé en Python avec `zxscreen.Screen`. Pour Tennis :
  - le logo GB repris des tuiles de la ROM ;
  - « ZX » en police ROM ×4 grasse ;
  - les rayures arc-en-ciel du Spectrum.

  Il sert deux fois : comme écran de chargement (`title.scr`, bloc `SCREEN$`) et comme fond du menu (compressé en RLE, 6912 → ~1300 octets, décompressé par `unrle.asm`).
- **Menu** : niveau, nombre de sets, clavier ou Kempston, rappel des touches, ENTER pour jouer.

---

## 10. Tester

- `sh asm/build.sh` : traduction, génération des graphismes, assemblage. Tout est régénéré à chaque fois.
- `python tools/zxrun.py asm/build/game.tap --frames 1500 --keys "60-62:ENTER" --bot --sheet 50`
  - **Chargement réaliste** : le `.tap` passe par `tap2sna`, et c'est le BASIC qui charge le code.
  - **Touches scriptées** par plages de trames. `--bot` fait jouer le robot de la config.
  - **Sorties** : planche contact (`--sheet`), GIF (`--gif`), PNG.
  - **`--cmio`** : contention de la mémoire et des entrées/sorties, comme un vrai 48K. Indispensable pour juger la vitesse.
  - **Profilage** : assembler avec `-DPROFILE`. Chaque partie de la boucle change la couleur de la bordure, et `zxrun` affiche le temps passé dans chaque couleur.
- **Tests ciblés** : écrire un petit script qui force une situation en écrivant dans la RAM GB et qui compte des événements. Exemple : `tools/test_smash.py` du repo Tennis, avec `--view` pour regarder en temps réel.
- Puis relancer ZEsarUX pour l'utilisateur (commande au §2).

---

## 11. Pièges rencontrés (et solutions)

| Piège | Solution |
|---|---|
| **Google Drive** corrompt la cassette écrite bloc par bloc (bloc manquant, ancienne version) | Assembler dans une copie locale (`%LOCALAPPDATA%`), puis recopier (voir `build.sh`) |
| `jr` hors de portée dans du code long | `jp` |
| `push` avec SP pointé sur les données d'un sprite | Garder la valeur dans un registre |
| Étiquette de données émise deux fois par le traducteur (`D_0B3D`) | Une seule émission par adresse (`data_blocks()` de `gb2z80.py`) |
| Le changement d'écran GB laissait finir le pas de logique | `tick_sp` + `S_SCREEN` (§6) |
| `tap2sna.py` prend `C:/...` pour une URL | Chemins relatifs |
| Hasard figé | Faire tourner le générateur de la ROM pendant l'attente de trame |
| Boriel Basic : `a AND (b=0)` faux avec un octet brut, paramètres de macro re-substitués, `ELSEIF` sur une ligne, variables lues seulement en ASM supprimées | Ne pas utiliser Boriel pour ce genre de portage |

---

## 12. Chiffres de référence (ZX Tennis)

| Mesure | Valeur |
|---|---|
| Logique traduite | 3794 instructions GB (7314 octets de code GB) |
| Comparaison pas à pas | 11 241 pas identiques (hors transitions d'écran et patch volontaire) |
| Sprites | 45 (20 images par joueur, 3 balles, ombre, marque) |
| Décor | 2160 octets |
| Écran titre compressé | 1319 octets |
| Vitesse sur vrai 48K | ~83 % des images (~42 images/s) |
