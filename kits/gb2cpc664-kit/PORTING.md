# Porter un jeu Game Boy sur Amstrad CPC664 : méthode

Ce guide tire les leçons du portage de **CPC Tennis** (Tennis, Nintendo 1989) :
- le code complet de ce portage est dans `G:\Mon Drive\Coding\Tennis\Amstrad` ;
- le kit réutilisable est dans [template/](template/) ;

Les étapes communes (rétro-ingénierie de la ROM, fermeture de la logique, configuration, preuve de fidélité) sont décrites dans [../gb2zx-kit/PORTING.md](../gb2zx-kit/PORTING.md) (§4 à §6).

---

## 1. Le principe, et la bonne nouvelle

Comme pour les autres portages, **la logique du jeu est la ROM Game Boy traduite automatiquement**. Le CPC a un **Z80**, comme le Spectrum : c'est **le même traducteur** (`tools/gb2z80.py`) et **la même logique traduite**. Tennis : `gb_logic.asm` est identique au fichier du Spectrum, déjà vérifié pas à pas contre le vrai jeu (outil `diff_gb.py` du kit Spectrum). Il n'y a donc pas de nouveau traducteur à écrire. Tout le travail porte sur le matériel du CPC.

## 2. Outils

| Outil | Rôle | Emplacement (machine de l'utilisateur) |
|---|---|---|
| **sjasmplus 1.24** | Assembleur Z80 (`DEVICE NOSLOT64K`, `DISP`, `LUA`, `SAVEBIN`) | `%LOCALAPPDATA%\sjasmplus\sjasmplus-1.24.0.win\sjasmplus.exe` |
| **Caprice32** | Émulateur CPC (464/664/6128/Plus). **Se lance depuis son dossier**, car il cherche ses ROM dans le dossier courant | `%LOCALAPPDATA%\Caprice32\cap32-win64\cap32.exe`, `-O system.model=1` = 664 |
| `tools/make_dsk.py` | Disquette `.dsk` (format DATA, en-tête AMSDOS) | Fourni |
| `tools/cpcshot.sh` | Capture automatique dans Caprice32 | Fourni |
| `tools/sim64.py` | Simulateur Z80 de SkoolKit **avec 64 Ko de RAM**. Celui de SkoolKit ignore les écritures en `$0000-$3FFF`, la ROM du Spectrum, alors que c'est de la RAM sur CPC | Fourni (GPL v3) |

**Automatiser Caprice32** : l'option `-a` tape du texte au démarrage. Il faut un **vrai** retour à la ligne (en bash : `$'run"game\n'`), suivi des commandes :
- `\(CAP32_DELAY)` : attendre ;
- `\(CAP32_SCRNSHOT)` : capture d'écran (dans `-O file.sdump_dir=...`) ;
- `\(CAP32_EXIT)` : quitter.

Deux pièges :
- Les touches tapées pendant l'initialisation (fabrication des sprites) sont perdues : laisser des délais.
- Les captures sont nommées à la seconde : deux captures dans la même seconde s'écrasent.

**Lancer le jeu pour l'utilisateur** (PowerShell) :

```powershell
Start-Process -FilePath "$env:LOCALAPPDATA\Caprice32\cap32-win64\cap32.exe" -WorkingDirectory "$env:LOCALAPPDATA\Caprice32\cap32-win64" -ArgumentList '-O','system.model=1','-a',"run`"game`n",'"<chemin>\build\game.dsk"'
```

**Préférence de l'utilisateur** : il teste lui-même à l'œil. Garder les vérifications automatiques courtes (une capture, une simulation), puis relancer l'émulateur pour lui. **Toujours reconstruire la version normale** après une version de test (robot, profilage) : un jour, la disquette livrée contenait le robot et pas de menu.

## 3. Décisions à prendre avec l'utilisateur

Mêmes questions que pour les autres machines, plus :
- **Mode graphique** : Tennis est en mode 1 pour le jeu et en mode 0 (16 couleurs) pour le titre et le menu.
- **Boutons** : le joystick CPC a **2 boutons**. Tennis propose le choix 1 ou 2 boutons dans le menu. Avec 1 bouton, le lob est automatique ; avec 2, le tir 2 correspond au bouton B du Game Boy.
- **Le nom du jeu** : « CPC Tennis » était un choix provisoire de Claude, qui reste à faire confirmer par l'utilisateur.

## 4. Mémoire (le vrai défi du 664 : 64 Ko)

- **Écran déplacé en `$4000`** (CRTC R12 = `$10`, R13 = 0), parce que la RAM GB (`$C000-$C0FF`, `$DD00`, `$FF80`) tombe sur l'écran par défaut en `$C000`.
- **Firmware coupé** au démarrage :
  - interruptions coupées, ROM basse et haute masquées (Gate Array `%10001101`) ;
  - IM 1 avec un `jp isr` écrit en `$0038`.
- **Chargement** : `RUN"GAME"` charge un binaire AMSDOS (type 2, avec adresse d'exécution). Le fichier doit tenir **sous HIMEM**, soit `$0200-$A5FF`.
- **Zone `$4000-$7FFF` du fichier** : elle deviendra l'écran, mais sert d'abord au démarrage. Elle contient :
  - un bloc de données **déplacé en `$C100`** (`DISP`), avec les tuiles, la carte et la table des lignes ;
  - les **images de base** des sprites et les **tables de décalage**, lues au démarrage puis écrasées par l'écran.
- **Police** : lue dans la **ROM basse** (`$3800`) avant de couper le firmware. Le code qui la copie doit être **au-dessus de `$4000`**, puisque la ROM basse recouvre `$0000-$3FFF`.
- **RAM libérée par le firmware** (`$A600-$BFFF`, puis `$D000-$DCFF` et `$DE00-$FF7F` chez Tennis) : elle reçoit les images décalées.
- **Surveiller les parties A et B** avec des `ASSERT`. La mémoire a été juste pendant tout le projet. Le passage tout-XOR a libéré ~1,1 Ko en A et ~4 Ko en B.

## 5. Affichage

### Décor (mode 1)
- **Mode 1** : 320×200, 4 encres. Les 4 teintes GB deviennent les 4 encres, **sans aucune perte** (`cpcgfx.tile_mode1`).
- **Image GB entière à l'échelle 1** : 32 tuiles de large, placées en colonnes CPC 4-35, sur 25 rangées. Les colonnes 0-3 et 36-39 restent libres pour le score.
- **Adresse d'une ligne** : `$4000 + (y AND 7) × $800 + (y / 8) × 80`, via une table (`line_tab`). Pour passer à la ligne suivante : `h += 8`, et en cas de débordement (`jp p`), `+ $C050`.
- **Couleurs** matérielles du Gate Array : voir `cpcgfx.HW`. Tennis : vert pâle, vert vif, vert, noir.

### Sprites logiciels : la leçon principale
1. **Décalages** : les 4 décalages au pixel près sont **fabriqués au démarrage** par les tables SHR/CAR : décaler en jeu coûtait trop cher. Seules les images de base sont stockées dans le fichier.
2. **Lignes rognées** : chaque ligne stocke un décalage, une longueur et ses seuls octets utiles, soit −36 % de travail.
3. **Dessin masqué, avec sauvegarde et restauration du fond** : c'était **trop lent**. Au début, avec des boucles génériques, le jeu tournait à 25 images/s. Et ça clignotait.
4. **Tout en XOR** (choix final) : redessiner au même endroit efface. Pas de sauvegarde ni de masque, et l'ordre ne compte pas. Les couleurs se mélangent là où un sprite passe sur un décor non vide ou sur un autre sprite, et l'utilisateur l'accepte.
5. **Ne redessiner que ce qui change** (`update.asm`) : chaque sprite modifié est effacé puis **aussitôt** redessiné, **dans l'ordre du balayage** (du haut vers le bas).
6. **Anti-clignotement : se caler sur le VSYNC.** On attend le début du signal en lisant le port B du PPI (`$F5`, bit 0). Compter les interruptions (300 Hz) pour trouver le VSYNC **s'est révélé peu fiable** : une interruption retardée faisait démarrer le dessin trop tard, et le faisceau l'attrapait. Les interruptions ne servent qu'à **compter le temps** : une trame toutes les 6.
7. **Diagnostic** : assembler avec `-DPROFILE` (bordure colorée pendant le dessin). Si la bande colorée s'arrête avant le haut de l'image, le dessin est fini à temps.

### Écran titre en mode 0 (16 couleurs)
- 160 pixels de large, soit **exactement la largeur de l'écran GB** : la bande titre GB remplit l'écran.
- **Mémoire** : les tuiles restent en mode 1 (4 teintes) et sont **converties au dessin**, avec une **palette de 4 encres par rangée** et une table de 512 octets construite dans une zone libre. On obtient ainsi du « CPC » rouge, vert et bleu, et un logo blanc.
- **Texte en mode 0** : 20 caractères par ligne, donc des textes courts.
- **Retour au jeu** : repasser en mode 1 et remettre les encres du décor.

## 6. Entrées et son
- **Clavier et joystick** : on choisit la ligne de la matrice par le port C du PPI (`$F6`), puis on lit le registre 14 du PSG (port A, `$F4`, mis en entrée par `$F792`). Le joystick est la ligne 9 : bits 0-3 pour les directions, bit 5 pour le tir 1, bit 4 pour le tir 2.
- **Touches de Tennis** : `Q A O P` + `ESPACE` (tir 1) + `M` (tir 2) ; menu `1-4`, `S`, `B`, `RETURN`.
- **AY-3-8912** (horloge 1 MHz) : on écrit un registre en passant par le PPI.
  - Table « numéro de son GB → type (son ou bruit), période, volume, décroissance ».
  - Voie A pour les sons brefs, voie C pour les applaudissements.
  - **Registre 7 : bits 6-7 à 0**, sinon le port A cesse d'être en entrée et le clavier n'est plus lu.

## 7. Vitesse
- **Mesure** : `tools/prof_cpc.py` du repo Tennis mesure les cycles de chaque partie sur des états réels du jeu (PyBoy + simulateur 64 Ko). Un CPC arrondit chaque accès mémoire : compter **~+20 %** en temps réel. Budget : 19 968 µs par trame.
- **Tennis** :
  - un pas de logique coûte ~3 800 cycles ;
  - la projection, réécrite en Z80 natif avec des tables, passe de 3 900 à 1 300 cycles par appel. Elle est vérifiée contre la ROM traduite : **0 différence sur 2 000 cas** (`test_proj.py`) ;
  - au final, ~89 % des trames sont à l'heure (~45 images/s).
- **Robot de test** (`-DAUTOPLAY`) avec un compteur de trames en retard, affiché **toutes les 64 trames seulement** : l'afficher à chaque trame faussait la mesure.

## 8. Pièges rencontrés

| Piège | Solution |
|---|---|
| Caprice32 ne trouve pas ses ROM | Le lancer depuis son dossier |
| `\n` tapé en toutes lettres par l'autotype | Vrai retour à la ligne dans la commande |
| Le simulateur de SkoolKit boucle sans fin sur du code en `$0000-$3FFF` | `tools/sim64.py` (écritures partout) |
| Le simulateur Python de SkoolKit n'a pas `trace()` | `sim.run(start, stop)`, ou `sim.run()` pour un pas |
| Macro sjasmplus avec des étiquettes `\@` | Sauts relatifs `$+n` |
| `jr` hors de portée après ajout de code | `jp` |
| Table censée tenir dans une page, qui déborde quand le code bouge | Addition 16 bits, ou `ALIGN` / `ASSERT` |
| Bloc de dessin déroulé à cheval sur deux pages | `IF ($ & $FF) > ... : ALIGN 256` |
| `pop af` qui écrase le test d'un `or a` | Tester après le `pop`, ou garder la valeur dans un autre registre |
| Rangée sauvegardée avant l'installation du décor | Sauvegarder après |
| Guillemets et `\n` dans les scripts Python passés en heredoc bash | Écrire le script dans un fichier |
| Disquette livrée compilée en version de test | Reconstruire la version normale à la fin |

## 9. Chiffres de référence (CPC Tennis)

| Mesure | Valeur |
|---|---|
| Logique | 3 794 instructions GB, identiques au Spectrum |
| Décor | 109 tuiles (1,7 Ko) + carte 25×32 |
| Sprites | 45 images, 4 décalages fabriqués au démarrage (~21 Ko de RAM) |
| Titre mode 0 | 78 tuiles, converties au dessin |
| Binaire | ~37 Ko (`$0200-$9470`) |
| Vitesse | ~89 % des trames à l'heure |

## 10. CPC Plus / GX4000 (fait : `G:\Mon Drive\Coding\Tennis\GX4000`)

Les sprites matériels de l'ASIC règlent tout : plus de dessin par le processeur, pas de trame en retard, joueurs en couleurs. Ce qu'il faut savoir :
- **Cartouche `.cpr`** : `RIFF` + taille + `AMS!`, puis des pages `cbNN` de 16 Ko. La page 0 est vue en `$0000` à la mise sous tension.
- **Démarrage** : la page 0 recopie les pages 1 et 2 en RAM. Les écritures vont en RAM même sous une ROM ; on lit la page n en ROM haute via `&DF80+n`. Elle saute ensuite dans un petit code en RAM qui coupe les ROM.
- **Rien n'est initialisé** : pas de ROM système, donc il faut **les 14 registres du CRTC** (sinon, écran = bordure : c'est arrivé), le **PPI** (`&F782`) et une **police embarquée** (celle du jeu GB).
- **ASIC** :
  - déverrouillage : 17 octets vers `&BCxx` ;
  - RMR2 `&B8` : registres en `&4000-&7FFF` ; `&A0` ou `&B0` : les masquer.
  - Sprite n : pixels en `&4000+256n` (1 octet par pixel, encre 1-15), X/Y/agrandissement en `&6000+8n`.
  - **Agrandissement %1001** : X ×2, et X est en pixels du mode 2, donc 1 pixel de sprite = 1 pixel du mode 1.
  - Palette en `&6400` : `%RRRRBBBB`, `%0000GGGG` ; encre 16 = bordure, 17-31 = sprites.
- **GX4000 = pas de clavier** : menu à la manette (haut/bas, gauche/droite, tir), 2 boutons par défaut.
- **Colorer une partie du décor en mode 1 (4 encres)** :
  - réserver une encre à cette partie (le public : des pixels de petites silhouettes), le reste du décor passant sa teinte en sombre ;
  - la faire changer de couleur toutes les 8 lignes par **interruption raster de l'ASIC** (PRI en `&6800`, numéro de ligne ; 0 = interruptions normales). Avec PRI actif, les interruptions à 300 Hz du Gate Array s'arrêtent : il faut compter la trame dans l'interruption d'une ligne fixe (200) ;
  - comme l'interruption mappe l'ASIC, elle doit remettre l'état voulu par le programme, retenu dans une variable **avant** chaque changement.
- Tester dans Caprice32 avec `-O system.model=3` (6128+) et la cartouche en argument.

## 11. Pour aller plus loin
- **6128** : 64 Ko de plus. On pourrait faire un double écran, avec des sprites masqués et zéro clignotement. Le mode 0 ne fait que 160 pixels de large, trop étroit pour une image GB de 256 pixels.
- **Plus** : il reste 5 sprites libres (Mario en couleurs ?) et des interruptions raster, pour changer la palette selon la ligne.
