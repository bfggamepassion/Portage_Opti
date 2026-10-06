# Porter un jeu Game Boy sur Commodore 64 : méthode

Ce guide tire les leçons du portage de **C64 Tennis** (Tennis, Nintendo 1989) :
- le code complet de ce portage est dans `G:\Mon Drive\Coding\Tennis\C64` ;
- le kit réutilisable est dans [template/](template/) ;

Le guide Spectrum ([../gb2zx-kit/PORTING.md](../gb2zx-kit/PORTING.md)) couvre les étapes communes, qui ne sont que résumées ici : la rétro-ingénierie de la ROM, la fermeture et la configuration.

---

## 1. Le principe : traduire la ROM

Comme pour le Spectrum, **la logique du jeu est la ROM Game Boy traduite automatiquement**, ici du SM83 vers le 6502. Elle n'est jamais réécrite en observant le jeu. La fidélité se prouve en comparant pas à pas avec le vrai jeu (§5).

Ce qui change par rapport au Spectrum :
- **Le processeur est plus éloigné.** Le 6502 n'a que 3 registres 8 bits, pas de registre 16 bits, une retenue inversée pour les soustractions, et `LDA` modifie ses indicateurs. Chaque instruction GB devient 3 à 6 instructions 6502.
- **Le matériel est plus riche.**
  - Sprites matériels : pas de moteur de sprites logiciel.
  - Caractères de 8×8 : une tuile GB devient un caractère C64.
  - Couleurs par case.
  - SID pour le son.
  - Écran de 320 pixels de large, qui **montre l'image GB entière à l'échelle 1** (256 de large), sans défilement.

---

## 2. Outils

| Outil | Rôle | Emplacement (machine de l'utilisateur) |
|---|---|---|
| **64tass 1.60** | Assembleur 6502. **Toujours avec `-C`** (majuscules ≠ minuscules). | `%LOCALAPPDATA%\64tass\64tass-1.60.3243\64tass.exe` |
| **VICE 3.10** | Émulateur C64 exact au cycle (`x64sc`) | `%LOCALAPPDATA%\VICE\GTK3VICE-3.10-win64\bin\x64sc.exe` |
| **py65** | Simulateur 6502 en Python, pour la comparaison et les tests | `pip install py65` |
| **PyBoy** | Émulateur GB piloté en Python | `pip install pyboy` |
| **Pillow**, **mgbdis** | Images ; désassembleur GB (fourni) | `pip install pillow` |

**Lancer le jeu pour l'utilisateur** (PowerShell) :

```powershell
Start-Process "$env:LOCALAPPDATA\VICE\GTK3VICE-3.10-win64\bin\x64sc.exe" -ArgumentList '-autostart','"<chemin>\build\game.prg"'
```

**Tester sans fenêtre, avec capture d'écran à la fin.** L'option `-warp` accélère l'exécution, mais coupe l'enregistrement du son (`-sounddev wav`).

```sh
x64sc -default -sounddev dummy -warp -autostartprgmode 1 -limitcycles 60000000 \
      -exitscreenshot shot.png -autostart game.prg
```

---

## 3. Décisions à prendre avec l'utilisateur

Mêmes questions que pour le Spectrum (fidélité, modes, contrôles, un seul bouton, langue), plus :
- **PAL ou NTSC.** Tennis est fait pour le PAL, à 50 Hz, avec 6 pas de logique toutes les 5 trames. En NTSC, à 60 Hz, il faudrait 1 pas par trame.
- **Le nom du jeu.** « C64 Tennis » était un choix provisoire de Claude, qui reste à faire confirmer par l'utilisateur.
- **Les options du menu.** Le joystick port 2 et le clavier (QAOP + ESPACE) fonctionnent ensemble, sans avoir à choisir.

---

## 4. Le modèle de traduction (`tools/gb2m6502.py`)

- **Registres GB en page zéro** (`src/zp.asm`) : `zL/zH`, `zC/zB`, `zE/zD`, rangés « bas, haut » pour servir de pointeurs. `[hl]` devient `(zL),y`, avec **Y = 0 en permanence** : toute routine écrite à la main doit rendre Y = 0. A et X du 6502 servent de brouillon.
- **Indicateurs** : seuls Z et C sont gérés, et il faut vérifier que la logique n'utilise pas DAA. Ils sont stockés en mémoire :
  - `zZ` contient le dernier résultat (Z du GB ⇔ `zZ` = 0) ;
  - `zCY` contient la retenue en bit 0.

  Seules les instructions GB qui écrivent un indicateur le sauvegardent. C'est indispensable : les `LD` du GB ne touchent pas les indicateurs, alors que les `LDA` du 6502 les modifient.
- **Soustractions** : la retenue du 6502 vaut « pas d'emprunt ». On la remet dans le sens GB avec `ROL zCY` puis `INC zCY`, ce qui inverse le bit 0.
- **Pile** : la pile GB est celle du 6502. `CALL` devient `JSR`, `RET` devient `RTS`. `JSR` empile « retour − 1 », donc :
  - les adresses de code empilées par la ROM (`CODE_PTRS`) sont traduites en `étiquette−1` ;
  - les routines RST, écrites à la main, ajoutent 1 à l'adresse qu'elles dépilent.
- **Mémoire** : la RAM GB garde ses adresses. Pendant chaque pas de logique, `$01 = $34` rend toute la RAM visible : la RAM GB en `$D000-$DFFF` passe sous les entrées/sorties, et Tennis y a son octet de son en `$DD00`. Le reste du temps, `$01 = $35`.
  - L'interruption sauvegarde `$01`, remet les entrées/sorties, puis restaure.
  - Les ROM du C64 sont coupées, et les vecteurs `$FFFA-$FFFF` sont en RAM. Il faut donc que la HRAM du jeu s'arrête avant `$FFFA` : chez Tennis, elle s'arrête à `$FFCB`.
- **Découpage** : ~24 Ko de 6502 pour ~3 800 instructions GB. Le code est coupé en morceaux (`SPLIT_AT`) à des frontières sans continuité. Tennis utilise les zones `$0801-$3FFF` et `$8000-$BFFF`, autour de la banque VIC.
- **Durée de vie des indicateurs** : une analyse arrière sur le graphe du code GB retire les sauvegardes que rien ne lit. Elle est prudente : au `RET`, tout est supposé vivant. Déclarer les effets des routines écrites à la main dans `STUB_FLAGS` et `RST_FLAG_DEFS`. Gain sur Tennis : −7 %.
- **Nettoyage final** : un `sta X` suivi d'un `lda X` perd son `lda`.

---

## 5. Prouver la fidélité, puis optimiser

- `tools/diff_gb6502.py` : le vrai jeu tourne dans PyBoy, piloté par un robot. À chaque pas, l'état GB est injecté dans le 6502 simulé (py65), qui exécute un seul `gb_tick` ; puis on compare la RAM obtenue avec celle du GB. L'outil donne aussi **le coût en cycles** de chaque pas. Tennis : 0 différence sur 2 755 pas.
- **Garder une version exacte.** Les réglages de jouabilité sont placés sous `.if !GB_EXACT`, et la vérification se fait avec `sh build.sh -D GB_EXACT=1`.
- **Budget d'un C64 PAL** : ~19 650 cycles par trame, moins ~1 000 pour les lignes où le VIC lit l'écran, moins le temps pris par les sprites. Pour Tennis, avant optimisation, un pas de logique coûtait 8 700 cycles en moyenne et 19 600 au pire, sans compter l'affichage.
- **Profiler par routine GB** : faire un histogramme des cycles selon l'étiquette `G_xxxx` la plus proche. Chez Tennis, **les routines de calcul de la ROM** (multiplications, divisions) prenaient 35 % du temps.
- **Réécrire les routines chaudes en 6502 natif**, déclarées en `STUBS`, avec **exactement** les mêmes sorties : registres, indicateurs et octets de travail HRAM. Un exemple se trouve dans [template/src/gb_math_tennis.asm](template/src/gb_math_tennis.asm).
- **Les tester contre la ROM traduite.** On fait une version de référence sans ces stubs (variable d'environnement dans la config), puis on compare les deux versions sur des entrées tirées au hasard. C'est le rôle de `C64/tools/test_math.py` et `test_proj.py` dans le repo Tennis.
- **Les routines d'affichage appelées à chaque trame** (la projection de Tennis, `$095D`) ne servent qu'à l'affichage. Si la logique ne les appelle jamais, et si rien d'autre ne lit leurs octets de travail, on peut les réécrire librement en 6502 natif avec des tables : 3 400 → 600 cycles chez Tennis, toujours vérifié contre la ROM traduite.
- **Mesurer la vitesse réelle dans VICE.** Une version de test (`-D AUTOPLAY=1`) fait jouer un robot et affiche le nombre de trames en retard. Tennis : ~88 % des trames à l'heure, soit ~44 images/s.

---

## 6. Affichage

### Décor : l'image GB entière, en caractères
- **Rejouer la construction de l'écran par le jeu** : les copies de tuiles vers la VRAM, puis le décodeur de tilemap (voir le kit Spectrum et `gbgfx.py`). On obtient ainsi la tilemap 32×32.
- **Afficher 25 rangées sur 32**, en colonnes C64 4-35. Les colonnes 0-3 et 36-39 restent libres : Tennis y affiche le score.
- **Utiliser le mode multicolore mixte**, où le bit 3 de la couleur de chaque case choisit le mode :
  - une tuile à deux couleurs dont le fond devient un caractère **haute résolution**, exact au pixel ;
  - sinon, elle devient un caractère **multicolore** à pixels doubles, en gardant le plus foncé des deux pixels GB pour ne pas perdre les traits fins.

  Voir `tools/c64gfx.py`.
- **Couleurs**. Les 3 couleurs communes (`$D021-$D023`) peuvent être 0-15, mais la couleur propre d'une case est limitée à **0-7**. Chez Tennis :
  - fond vert clair, peau, noir ;
  - public coloré **spectateur par spectateur** (composantes connexes des pixels, pas case par case) ;
  - murs et bords : la teinte 1 prend la couleur de la case (vert) ;
  - filet en haute résolution noire, ce qui garde le maillage.
- **Moins de 256 caractères** : le stade de Tennis en utilise 117. La police est placée en 128-191.
- **Police** : elle est **recopiée au démarrage depuis la ROM de caractères du C64** (`$01 = $33`), pour ne pas distribuer celle de Commodore. La banque VIC 1 ne voit pas la ROM de caractères. Pour écrire sur un fond clair, recopier la police inversée.

### Sprites matériels
- **Joueurs** : 24 pixels de large, jusqu'à 32 de haut. Chacun utilise **2 sprites multicolores empilés** (noir `$D025`, blanc `$D026`, couleur propre : joueur 1 rouge, joueur 2 bleu).
- **Balle** : 2 sprites haute résolution superposés (contour noir devant, intérieur blanc derrière). Ombre et marque : 1 sprite chacune. Tennis utilise ainsi les 8 sprites.
- **Position** : la même que dans les routines d'affichage de la ROM, c'est-à-dire projection, plus décalage de l'image, moins défilement. Sur C64, sans défilement : `X = x GB + 56`, `Y = y GB + 34 − 8 × première rangée`.
- **Priorité derrière le décor** (`$D01B`) : c'est l'équivalent du bit de priorité OAM du GB (balle derrière le filet).
- **Mise à jour sans déchirement** : l'affichage remplit des registres fantômes au début de la boucle, et l'interruption raster (ligne 250) les recopie dans le VIC.

### Texte et encodage
- Utiliser l'encodage personnel **`c64txt`** (`.cdef "AZ", $01`) : l'encodage `"screen"` de 64tass envoie les majuscules en `$41-$5A`, hors de la police recopiée.
- `str` est une fonction de 64tass : ne pas l'utiliser comme nom de macro.

---

## 7. Son, entrées, écrans

- **SID** : une table « numéro de son GB → forme d'onde, fréquence, enveloppe, durée en trames ». Les sons courts vont sur la voix 1 ; les applaudissements, qui durent, sur la voix 3.
- **Entrées** : le joystick du port 2 (`$DC00`) et le clavier (colonne écrite dans `$DC00`, rangée lue dans `$DC01`) sont lus ensemble. Il faut remettre `$DC00 = $FF` après le balayage. Le port 1 est à éviter, car il se mélange au clavier.
- **Un seul bouton** : même règle automatique que sur Spectrum (lob quand l'adversaire est au filet).
- **Écran titre** : un 2e jeu de caractères dans la banque VIC (écran `$6400`, caractères `$6800`, `$D018 = $9A`). Chez Tennis :
  - la bande TENNIS du GB en multicolore, sur fond noir ;
  - « C64 » écrit avec la police du jeu GB agrandie ×3 ;
  - les options en police ROM.

---

## 8. Pièges rencontrés

| Piège | Solution |
|---|---|
| 64tass confond `TITLE_COLORS` et `title_colors` | Option `-C` |
| `-D NOM=1` refusé si `NOM` est défini dans le source | Défaut dans un bloc `.weak` … `.endweak` |
| Majuscules hors police avec `.enc "screen"` | Encodage personnel `c64txt` |
| Macro nommée `str` | `str` est une fonction de 64tass : nommer la macro `prt` |
| Zone de code pleine (`.cerror`) | Déplacer `SPLIT_AT` |
| Rangée sauvegardée avant l'installation des couleurs du décor | Sauvegarder après avoir installé les couleurs |
| Un fichier PRG unique chargé à travers `$D000-$DFFF` écrirait dans les entrées/sorties | Ne rien charger au-delà de `$CFFF` (ou déplacer au démarrage) |
| Le mode `-warp` de VICE n'enregistre pas le son | Enregistrer en temps réel |
| Chaînes de caractères dans les heredocs du shell | Écrire les fichiers avec l'outil d'écriture, pas avec `cat <<` |

---

## 9. Chiffres de référence (C64 Tennis)

| Mesure | Valeur |
|---|---|
| Logique traduite | ~3 600 instructions GB → ~24 Ko de 6502, en 2 morceaux |
| Pas de logique | 6 100 cycles en moyenne, 12 300 au maximum (après optimisation) |
| Projection d'affichage | 3 400 → 600 cycles (6502 natif avec tables) |
| Décor | 117 caractères |
| Sprites | 73 images (4,7 Ko) |
| Écran titre | 84 caractères |
| Programme | ~43 Ko (`.prg` chargé en `$0801`) |
| Vitesse dans VICE (PAL) | ~88 % des trames à l'heure (~44 images/s) |
