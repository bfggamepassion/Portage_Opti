# Porter un jeu ColecoVision sur Amstrad CPC 6128

Méthode tirée du portage de *Cabbage Patch Kids: Adventures in the Park*
(Coleco, 1983), `G:\Mon Drive\Coding\Cabbage\`. Le template (`template/`)
est ce portage complet, rendu générique : avec la ROM de Cabbage il produit
un binaire identique octet pour octet. On le copie, puis on l'adapte au
nouveau jeu en suivant ce document.

---

## 1. Principe

**Le code Z80 de la cartouche tourne tel quel sur le CPC.** Les deux machines
ont un Z80 (3,58 MHz Coleco, ~3,3 MHz effectifs CPC). On ne traduit rien :
on remplace seulement chaque instruction d'entrée-sortie (`in`/`out` vers le
VDP, le son, les manettes) par un appel à du code CPC (HLE), dans
`src/patches.asm`.

- **VDP virtuel.** La VRAM du TMS9918 (16 Ko) est une banque de RAM (banque 7),
  ses registres des variables. Chaque écriture passe par `vput`, qui note ce
  qui a changé : case de la table des noms (liste de cases), motif ou couleur
  de tuile, motif de sprite.
- **NMI simulée.** L'interruption du CPC tombe à 300 Hz ; une sur cinq appelle
  la NMI du jeu : 60 Hz, la cadence de la Coleco NTSC. Le jeu garde son propre
  anti-réentrée (s'il n'a pas fini son tick, la NMI suivante est ignorée), donc
  le jeu tourne exactement à la même vitesse que sur la console.
- **Le rendu remplace la boucle d'attente du jeu** (`jr $` dans le programme
  principal, remplacé par `rst $08`) : tout le temps libre du processeur sert
  à recopier l'image du VDP dans l'écran caché, en mode 0, puis à basculer les
  deux écrans au VSYNC. Double tampon : aucun clignotement.
- **Mode 0 : 160 pixels de large, dont 128 utilisés** (256 pixels Coleco / 2),
  16 couleurs = les 15 couleurs du TMS + le fond. Deux pixels Coleco donnent un
  pixel CPC.

Résultat sur Cabbage : 22-25 images/s, logique identique à la Coleco tick
pour tick (vérifié par `ticks.py`, §6).

## 2. Avant de commencer : trois vérifications sur la ROM

1. **Taille de la cartouche.** Cabbage fait 16 Ko ($8000-$BFFF) : elle tient
   dans la banque 6, vue en $8000 dans la configuration « jeu » (V_GAME =
   banques 4 5 6 7). **Une cartouche de 24 ou 32 Ko ne tient pas telle quelle** :
   $C000-$FFFF est la VRAM virtuelle (banque 7). Il faudra déplacer la VRAM
   (et donc toutes les vues du rendu qui la lisent), ou basculer une partie de
   la cartouche. C'est la première décision d'architecture à prendre.
2. **Appels au BIOS.** `grep -n "call \$0\|call \$1\|jp \$0\|jp \$1" re/<GAME>.lst`.
   Cabbage n'appelle que `GAME_OPT` ($1F7C, l'écran d'options), remplacé par
   un menu à nous. Un jeu qui utilise les routines du BIOS (écriture VRAM
   $1FDF, `POLLER` $1FEB, `PLAY_SONGS`, tables de sprites...) demande soit de
   les réécrire (HLE), soit de charger le vrai BIOS : $0000-$1FFF est occupé
   par notre code commun et la banque 4, donc à étudier.
3. **Sites d'entrée-sortie.** `python tools/cvrun.py 3000 --keys "..."` puis
   `re/io.txt` : chaque `in`/`out` exécuté avec son PC. Ceux en $8000-$BFFF
   sont à corriger ; ceux en $0000-$1FFF sont le BIOS (voir point 2). Jouer
   plusieurs niveaux avec `--keys` pour tout couvrir (la couverture s'ajoute
   d'une exécution à l'autre dans `re/coverage.bin`).

## 3. Démarrer un nouveau portage

1. Nouveau dépôt, puis copier `template/*` dedans.
2. `re/<GAME>.col` (la ROM), `re/coleco_bios.rom` (le BIOS, pour `cvrun` ; à
   reprendre dans `G:\Mon Drive\Coding\Cabbage\re\`).
3. `tools/port_config.py` : `GAME`, `DSK_NAME`. Les autres réglages
   (valeurs de Cabbage en exemple) se remplissent au fil de l'étude.
4. Étudier le jeu original :
   - `python tools/cvrun.py 3000 --shot 600,1200 --keys "700:K1"` : images
     `build/cv_*.png`, couverture, `re/io.txt` ;
   - `python tools/disasm.py` : `re/<GAME>.lst` (descente récursive + couverture ;
     compléter `DISASM_ENTRIES`, `INLINE_JUMP_TABLES`, `INLINE_DATA` quand le
     listing montre du code pris pour des données) ;
   - `python tools/zdis.py ADR N` : désassembler une plage.
5. Repérer dans le listing (ce que `src/defs.asm` et `src/patches.asm` citent) :
   - `CART_START` : mot en $800A de l'en-tête ; `CART_NMI` : cible du saut en $8021 ;
   - la boucle d'attente (`jr $`, souvent juste après l'initialisation) → `CART_IDLE` ;
   - les routines VDP du jeu : écrire un octet, lire, port de contrôle, copier un
     bloc, remplir. **Leurs conventions de registres sont propres au jeu**
     (Cabbage : A = valeur, DE = adresse) : adapter l'entrée de `hle_wr`,
     `hle_rd`, `hle_ctl`, `hle_block`, `hle_fill` ;
   - les lectures de l'état du VDP (`in a,($BF)`) : remplacées par `ld a,0`
     ou des `nop` (le jeu n'utilisait pas la collision) — vérifier ce que le
     jeu fait du bit 7 (trame) et du bit 5 (collision) ;
   - manettes (`out ($80/$C0)` = mode, `in ($FC/$FF)`) et son (`out ($FF)`).
6. Réécrire `src/patches.asm` avec ces adresses (`CART_ORG adr` … `ENT`).
   **Règle : aucun octet remplacé au-delà du premier ne doit être une
   destination de saut** (vérifier les `<- xxxx` du listing).
7. `sh build.sh` puis `python tools/cpcsim.py 1500 --shot 400,800,1200` : images
   `build/cpc_*.png`. Quand l'image est bonne, `sh run.sh` lance Caprice32
   pour l'utilisateur.
8. Vérifier la logique avec `ticks.py` (§6), puis la cadence avec `level.py` (§7).

## 4. Carte mémoire (CPC 6128)

Configurations du Gate Array (`$7Fxx <- $C0 + n`) :

| Vue | Valeur | $0000 | $4000 | $8000 | $C000 | Usage |
|---|---|---|---|---|---|---|
| V_GAME | $C2 | banque 4 | banque 5 | banque 6 | banque 7 | le jeu (vue « Coleco ») |
| V_BASE | $C0 | base 0 | base 1 | base 2 | base 3 | dessin des cases |
| V_B4 | $C4 | base 0 | banque 4 | base 2 | base 3 | dessin des sprites |
| V_B5 | $C5 | base 0 | banque 5 | base 2 | base 3 | état partagé |
| V_B7 | $C7 | base 0 | banque 7 | base 2 | base 3 | lecture de la VRAM |

- **base 0** : $0000-$01FF code commun ; $0200-$2FFF rendu ; $3000 tables ;
  $3800 `CADDR` (adresse en cache de la tuile de chaque case) ; pile du rendu $3E00.
- **base 1** : $4000-$6FFF cache des tuiles converties (768 × 16 octets) ;
  $7000 noms affichés ; $7300 tampons de trame par case.
- **bases 2 et 3** : écrans A ($8000) et B ($C000), 64 octets × 192 lignes ;
  les trous de 512 octets en $x600 de chaque bloc de 2 Ko servent de tampons
  (listes, table des sprites copiée, tables de lignes) : visibles dans toutes
  les vues du rendu.
- **banque 4** : $0000-$01FF commun ; $0200-$0FFF code « vue jeu »
  (`gamecode.asm` : VDP virtuel, menu, manettes, son ; ~450 octets libres sur
  Cabbage, `ASSERT $ <= $1000`) ; $1000-$3AFF cache des masques de sprites
  (3 entrées par page) ; $3B00-$3FFF données du menu recopiées par `init`.
- **banque 5** : $4000-$5FFF état partagé jeu ↔ rendu (`defs.asm`), pile de la
  NMI ($5F00) ; $6000-$63FF la RAM de la Coleco (1 Ko, à la même adresse).
- **banque 6** : la cartouche corrigée. **banque 7** : la VRAM.

**Le code commun $0000-$01FF doit être identique octet pour octet en base 0 et
en banque 4** : l'interruption peut tomber dans n'importe quelle vue. `cur_view`
(lu par l'interruption) vaut V_GAME en banque 4 et la vue du rendu en base 0.
Les RST libres ($08 rendu, $10 exemple de patch d'un octet) sont précieux pour
remplacer une instruction d'un seul octet.

Fichier `<GAME>.BIN` chargé en $0400-$A5FF par `RUN"<GAME>"`, puis le chargeur
($9E00) répartit : cartouche → banque 6, base 0, code de la banque 4.

## 5. Le rendu (`src/render.asm`)

Boucle : `grab` → `vram_pass` → `draw_cells` → `draw_sprites` → `flip_req`,
et la préparation de l'image suivante (`grab`, `vram_pass`) pendant l'attente
du VSYNC (`flip_wait`).

- **Tuiles.** Chaque motif (8 lignes, 2 couleurs par ligne) est converti une fois
  en mode 0 dans le cache (16 octets). Paire de pixels mixte : **la couleur
  minoritaire gagne** (garde les traits fins). Seuls les motifs modifiés sont
  reconvertis (`PAT_LIST`).
- **Cases.** Le jeu note les cases modifiées dans une liste (`mark_cell`) ; le
  rendu redessine ces cases sur les **deux** écrans (liste de la trame et de la
  précédente) et les cases sous les sprites de l'avant-dernière trame.
- **Sprites.** 16×16, masques inversés en cache (2 décalages), boîte englobante
  réduite ; dessinés du dernier au premier (le sprite 0 devant), fusion OR.
- **Table des sprites paresseuse.** Beaucoup de jeux recopient à chaque NMI la
  table des sprites de la RAM vers la VRAM : `hle_block` ne garde qu'un
  pointeur (`sat_src`), le rendu lit la RAM directement. Toute écriture dans la
  page de la table des sprites doit d'abord la recopier (`sat_flush`, classe
  `C_SAT`).
- **Classes de pages** (`class_tab`, 64 pages de 256 octets) : chaque écriture
  VRAM sait en O(1) si elle touche les noms, les motifs/couleurs de tuiles, les
  motifs de sprites ou la table des sprites. Recalculées quand un registre de
  base change (`build_classes`).
- **Débordement de la liste de cases** (> 255 cases dans un tick, ex. changement
  de décor) : `names_ovf` = redessiner toutes les cases **sans reconvertir les
  tuiles**. Ne pas utiliser `full_req` pour ça (reconversion complète à chaque
  trame = écran noir : c'était le bug « niveau suivant tout noir »).
- **Police.** La police 8 pixels du jeu devient illisible à 4 pixels de large :
  `gen_tables.py` la remplace dans la ROM par une police 3×7 doublée
  (`tools/font4.py`, `port_config.FONT_PATCH`), que la conversion 2:1 rend
  sans perte.
- **Sprites aux détails fins** (visages, yeux d'un pixel) : la fusion des paires
  les rend illisibles (le visage d'Anna Lee devenait une bande rouge, « on ne
  sait pas si ce sont ses yeux ou sa bouche »). `tools/sprite_fix.py` les
  redessine en pixels CPC (8 par ligne) et `gen_tables.py` les réinjecte dans
  la ROM (chaque pixel CPC = deux pixels Coleco identiques). Trouver les motifs
  en ROM en cherchant les 32 octets de la VRAM des sprites (`cvrun`) ; ceux que
  le jeu fabrique (miroirs) suivent. Sans effet sur la logique si le jeu
  n'utilise pas la collision du VDP (vérifier avec `ticks.py`).
- **Logo du menu** (`logo_on`) : tuiles mode 0 prêtes (`tools/logo.py` depuis
  `gfx/logo.png`), posées directement par la conversion au lieu des motifs VDP.

## 6. Vérifier la logique : `tools/ticks.py`

`python tools/ticks.py N [secondes] [--walk]` fait tourner **la vraie ROM avec
son BIOS** (`cvrun`) et le portage (`cpcsim`) au niveau N, et compare la RAM
Coleco au début de chaque tick exécuté, depuis l'entrée en jeu.

- Cadence : ticks exécutés / NMI par seconde des deux côtés (60/60 attendu).
- État : « 0 différents » = la logique du portage est exacte. Si une différence
  apparaît, `--show A,B,... --from T --to T` affiche ces octets tick par tick.
- Réglages (`port_config.py`) :
  - `ALIGN` : l'octet d'état « partie en cours » (alignement des deux relevés) ;
  - `NMI_ACCEPT` / `NMI_SKIP` : dans la NMI du jeu, le point où le tick est
    accepté et celui où il est ignoré (anti-réentrée) ;
  - `SYNC_AT_ALIGN` : compteurs recopiés de la Coleco au départ (le compteur de
    trames du jeu : il cadence les animations, sa valeur dépend du temps passé
    dans les menus) ;
  - `TICKS_IGNORE` : ce qui diffère légitimement (pile, manettes, compteurs du
    BIOS, son). À trouver avec `--detail` ;
  - `ld a,r` : le hasard tiré du registre R diffère forcément (il dépend du
    nombre d'instructions exécutées) ; l'outil donne la même suite de valeurs
    aux deux machines (`--realr` pour garder le vrai R).
- `level_pokes(n)` : où écrire pour sauter au niveau n (trouver la variable de
  niveau dans le listing ; chez Cabbage $6054, et $6059 n'est que son affichage
  BCD — ne pas confondre).

**Toujours passer par là avant d'attribuer une différence ressentie au
portage.** Sur Cabbage, « les balles de l'écran 26 sont plus dures » : la
logique était identique tick pour tick ; la différence venait du retard
d'affichage (§7). Et le niveau de difficulté du menu n'a *aucun* effet dans le
jeu original (valeur calculée puis jetée en $8146) : RAM identique pour les
4 niveaux, sur les deux machines.

## 7. Performances

Méthode (voir aussi la skill `cpc-optimisation` si elle est installée) :
mesurer d'abord, compter en NOPs (1 trame = 19 968), donner avant/après.
La bascule d'écran se fait sur un VSYNC : une image dure 1, 2 ou 3 trames,
jamais entre les deux. Un décor à « 20 images/s » alterne des images de 2 et
3 trames : c'est ce qui se voit comme une saccade. L'objectif utile est donc
de passer **sous le seuil** (rendu + jeu ≤ 2 trames = 39 936 NOPs par image).

Outils (dans le simulateur, pas dans l'émulateur) :

- `python tools/budget.py [N ...]` : par image, NOPs de rendu / jeu / attente
  du VSYNC, et images/s ;
- `python tools/rprof.py [N ...]` : temps du rendu par routine (NOPs/image) ;
- `python tools/level.py N [s] [--walk] [--prof]` : images/s, captures,
  profil complet (rendu / « vue jeu » / cartouche) ;
- `python tools/render_check.py REF.bin [NOUVEAU.bin] [--quick]` : **contrôle
  d'une optimisation du rendu** — 27 situations (menu, décors, en marche et
  en saut) ; le jeu est figé (NMI neutralisée) après le même nombre de ticks,
  touches et saut de niveau réglés sur les ticks, hasard `ld a,r` identique ;
  les deux écrans relevés à une bascule doivent être identiques octet pour
  octet. Garder une copie du binaire avant de commencer ;
- `python tools/ticks.py N --walk` : logique identique à la Coleco (pour
  tout changement côté jeu).

Ce qui a marché sur Cabbage (décors chargés 20 → 25 images/s, le plus lourd
14,8 → 19,5 ; les décors normaux passent de 25 à 27-40) :

- **Rendu des cases par la pile** (§8.1 de la référence) : le cache des tuiles
  est rangé par `conv_run` dans l'ordre de dessin (lignes 0 1 3 2 6 7 5 4,
  octets inversés une ligne sur deux) ; `draw_cell` lit par `POP DE`, change
  de ligne par un seul `SET`/`RES` sur H, en zigzag `INC L`/`DEC L`, sous `DI`
  (~80 NOPs). Plus le contrôle « déjà dessinée » en ligne dans la boucle et
  l'écran caché en valeur immédiate auto-modifiée.
- **Entrées du cache des sprites alignées** (3 par page de 256) : dessin par
  `INC L` au lieu de `INC HL`. `build_sprite` retrouve l'entrée du décalage 1
  par `ENTTAB`, pas en ajoutant 84.
- **Préparation des sprites** : chemin rapide « entièrement visible » en
  registres ; découpage seulement pour les sprites coupés par un bord ; saut
  auto-modifié vers la boucle déroulée. Boucle des 32 entrées par IY, sprites
  transparents rejetés sans appel.
- **`grab`** ne parcourt les 64 drapeaux de motifs de sprites que si l'un a
  changé (`spr_req`, posé par `mark_ts`) : ~770 NOPs par image de moins.
- **Côté jeu : ce que le jeu réécrit à l'identique.** Beaucoup de jeux Coleco
  redessinent des éléments entiers à chaque tick (lianes, jets d'eau, jauges) :
  sur la Coleco un `out` coûte 11 cycles, chez nous chaque octet passe par
  `hle_wr` (~60 µs). Réécrire en natif la boucle du jeu qui fait ça
  (`vine_loop` $A125, `nrect_wr` $A448, `nstr_wr` $8664), en comparant avec la
  copie de la VRAM (DE passé une fois en adresse de la copie : `EX DE,HL /
  CP (HL)`), puis **mémoriser** : un rectangle ou une liane copié depuis la
  ROM est noté (`MEMO_TAB`) avec ses cases (`MEMO_OWN`, une par case de la
  table des noms) ; toute écriture qui change une de ces cases (`mark_cell`)
  invalide l'entrée ; tant qu'elle est valide, le même appel rend directement
  les registres de sortie mémorisés. Réinitialisé par `build_classes` et par
  le menu (écritures directes). 89 % d'appels évités sur les jets d'eau.
  - Un seul compteur global de modifications ne marche **pas** (toute écriture
    invalidait tout) : il faut l'invalidation par case.
  - Reproduire **exactement** les registres de sortie de l'original (lire
    chaque appelant) ; ne pas sauter l'écriture dans la page de la table des
    sprites (`C_SAT`).
- **Place** : la banque 4 est pleine ; les données du menu (police, carte du
  logo) sont en base 0 et recopiées par `init` dans le trou de la banque 4
  après le cache des sprites (`BK4_DATA` = $3B00).

**Course critique à connaître** (présente dès la première version, révélée
par le changement de rythme) : effacer un tableau de drapeaux que le jeu
écrit pendant ses ticks par `LD (HL),0 / LDIR`, interruptions permises. Si
le tick marque l'octet sous le curseur, le `LDIR` recopie ce 1 dans tous les
octets suivants : ces cases restent « déjà dans la liste » sans y être, et ne
sont plus jamais redessinées (tuile d'un objet animé figée). Effacer par une
boucle qui écrit une constante (`clr768` dans `render.asm`).

Contrôle absolu : `python tools/tile_check.py BINAIRE` vérifie, jeu figé,
que chaque case sans sprite de l'écran affiché est la conversion de sa tuile
en VRAM (28 situations, dont des parties longues avec changements de décor).
C'est lui qui a trouvé la course ci-dessus ; `render_check` ne voit que les
différences avec la référence, pas les défauts qu'elle partage.

Pièges rencontrés en mesurant :

- un outil qui fige ou pilote le jeu **sur les trames** donne des faux
  écarts : une fenêtre `DI` du rendu décale un tick d'une trame à l'autre.
  Tout régler sur le **nombre de ticks** exécutés, et appliquer les touches
  dès le début du tick (sinon le clavier est lu avant la mise à jour) ;
- un instantané de l'écran caché peut tomber au milieu d'un dessin : relever
  les écrans au moment d'une bascule (écriture de R12) ;
- un drapeau « non nul » posé avec A : A peut valoir 0 (n° de motif 0) — poser 1.

Limites restantes : la boucle de dessin des sprites est proche de l'optimum
(10 NOPs par octet, `XOR`/`AND`/`XOR` avec masque inversé) ; seul le passage
d'une ligne à l'autre (17 NOPs) pourrait encore baisser. Le retard
d'affichage (~5 ticks à 25 images/s) baisse avec la cadence.

## 8. Entrées, menu, son

- **Clavier et joystick** : PPI port C (ligne) + registre 14 du PSG. Balayés
  **une fois par tick** (`kbd_update`), interruptions coupées pendant l'accès
  (le PPI sert aussi au son). Joystick CPC → bits Coleco par table (`joy_col`).
- **Pavé numérique** : touches 0-9 du CPC. Une touche doit avoir été vue
  relâchée avant de compter (« armée ») : l'autotype de Caprice32 laisse des
  touches enfoncées (8, [) et le jeu démarrait seul en 2 joueurs.
- **Menu** (remplace `GAME_OPT` du BIOS) : 1 joueur, niveau au joystick, logo,
  ligne validée qui change de couleur (copies colorées des caractères
  préparées d'avance : on ne change que les noms, sinon chaque changement de
  couleur fait tout reconvertir), triche T = vies infinies (`rst $10` à la
  place du `dec (hl)` des vies). `menu_tick` est appelé à la place de la
  lecture du pavé : **il doit préserver BC, DE, HL** (le jeu garde C à travers
  l'appel ; oubli = états qui sautent, départ automatique).
- **Cadence PAL / NTSC** : le tick du jeu part toutes les `nmi_div`
  interruptions du CPC (300 Hz) : 6 = 50 Hz, comme une ColecoVision PAL
  (Europe, jeu 17 % plus lent), 5 = 60 Hz (NTSC). Cabbage démarre en PAL
  (les souvenirs d'un joueur européen sont ceux de la version 50 Hz) :
  le menu propose « NORMAL MODE » (50 Hz) et « HARD MODE » (60 Hz). Le choix
  SKILL 1-4 du BIOS a été retiré : Cabbage ignore le niveau ($8146).
- **Trainer** (T : vies infinies) : scène de départ au menu (gauche/droite,
  visible seulement trainer actif), écrite pendant
  l'écran « PLAYER 1 » (état $0A, hors tick en cours) puis bandeau réaffiché
  par la routine du jeu ($8752).
- **Son** : SN76489 → AY-3-8912. Période AY = N × 0,5587 ; atténuation SN →
  volume AY par table ; bruit sur la voie C avec le plus fort des volumes 2/3.
  Le registre 7 (mélangeur) est mis en cache.

## 9. Pièges rencontrés

- **Google Drive** : assembler dans le dossier synchronisé corrompt les
  fichiers écrits bloc par bloc → `build.sh` assemble dans `%LOCALAPPDATA%`
  puis recopie.
- **Écrire les fichiers en UTF-8** (`encoding='utf-8'`) : Python sous Windows
  écrit en cp1252 par défaut (accents cassés dans les .asm).
- **sjasmplus** : les étiquettes sont globales à tous les fichiers inclus (un
  `rect_wr` existait déjà dans `render.asm`) ; `jr` hors de portée → `jp` ;
  `ENT` pour fermer un `DISP`.
- **Simulateur CPC** : `c.ram` n'est à jour pour les banques visibles qu'après
  un changement de configuration ; lire la RAM courante par `c.mem` (voir
  `portsim.cpc_peek`).
- **Registres écrasés dans le rendu** (D dans `grab`) : redessins complets
  en permanence, sans erreur visible. Profiler tôt.
- **Caprice32** :
  - lancer depuis **bash**, pas PowerShell (qui perd les guillemets :
    `runGAME` → Syntax error) : `sh run.sh` ;
  - `-O system.model=2` pour un 6128 ;
  - l'autotype laisse des touches enfoncées : ne pas conclure à un bug
    d'entrée sur une capture automatique ;
  - `CAP32_SNAPSHOT` ne produit rien ; pour voir un état interne, un build
    de débogage qui l'affiche à l'écran (`-D...`).
- **Variables mal identifiées** : vérifier une hypothèse (« $6051 = niveau de
  difficulté ») en comparant la RAM de plusieurs parties dans `cvrun` avant
  d'en tirer une conclusion ($6051 était le numéro d'étape).

## 10. Travailler avec l'utilisateur

- Il teste visuellement dans Caprice32 et décrit ce qui ne va pas. Déboguer dans
  les simulateurs (`cpcsim`, `cvrun`, `ticks.py`), **pas** par une série de
  lancements de l'émulateur : une capture par étape visible au plus, puis
  `sh run.sh` pour lui.
- Toujours laisser le build normal (pas un build de profil ou de débogage)
  dans `build/`.
- Textes du jeu en anglais ; échanges en français.

## 11. Le template

```
template/
  build.sh            tables, logo, sjasmplus (hors Drive), disquette build/<GAME>.dsk
  run.sh              lance Caprice32 (6128) avec RUN"<GAME>"
  src/
    defs.asm          carte mémoire, vues, état partagé, adresses du jeu (CART_*)   [adapter]
    main.asm          découpage du fichier, chargeur                                 [taille cartouche]
    common.asm        $0000-$01FF commun : ISR, RST, cur_view                          [RST du jeu]
    patches.asm       les corrections de la cartouche                                 [à refaire]
    gamecode.asm      VDP virtuel, NMI, menu, manettes, son                            [conventions du jeu]
                      + exemples propres à Cabbage : vine_loop, nrect_wr, nstr_wr,
                        lives_dec/cheat_draw, game_opt (menu, logo, skill_codes)
    render.asm        moteur de rendu (générique)
    tables.asm, font4.asm   générés par gen_tables.py
    logo_tiles.asm, logo_map.asm   générés par logo.py (logo de Cabbage)
  tools/
    port_config.py    TOUT ce qui est propre au jeu, pour les outils                 [adapter]
    cvrun.py cvsim.py ColecoVision simulée (vrai BIOS / sans BIOS, contrôle des accès VDP)
    cpcsim.py sim64.py  CPC 6128 simulé (Z80 SkoolKit)
    disasm.py z80dis.py zdis.py   désassemblage
    ticks.py          comparaison Coleco / CPC tick par tick
    render_check.py   contrôle d'une optimisation du rendu (écrans identiques octet pour octet)
    tile_check.py     contrôle absolu : chaque case affichée = conversion de sa tuile en VRAM
    budget.py rprof.py   NOPs par image (rendu / jeu / attente), rendu par routine
    sprite_fix.py sprite_editor.py/.html   sprites redessinés (gfx/sprites_cpc.json) et leur éditeur
    level.py          images/s et profil d'un niveau
    prof.py fps.py rtime.py preview_cpc.py   mesures, aperçu de conversion
    gen_tables.py font4.py cpcpal.py tms.py   tables, police, palettes
    logo.py           logo mode 0 depuis une image (réglages de détourage propres à l'affiche de Cabbage)
    make_dsk.py cpcshot.sh   disquette, capture Caprice32
```

Outils nécessaires : Python 3 + Pillow + SkoolKit (`skoolkit.simutils`),
sjasmplus 1.24 (`%LOCALAPPDATA%\sjasmplus\sjasmplus-1.24.0.win\`), Caprice32
(`%LOCALAPPDATA%\Caprice32\cap32-win64\`).
