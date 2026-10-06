# Porter un jeu Game Boy sur ColecoVision : méthode

Ce guide tire les leçons du portage de **Coleco Tennis** (Tennis, Nintendo 1989) :
- le projet complet est dans `G:\Mon Drive\Coding\Tennis\Coleco` ;
- le modèle réutilisable est dans [template/](template/) ;

Les étapes communes (rétro-ingénierie de la ROM, fermeture de la logique, configuration, preuve de fidélité) sont décrites dans [../gb2zx-kit/PORTING.md](../gb2zx-kit/PORTING.md) (§4 à §6). La version MSX1, qui a le même VDP, a son propre kit : [../gb2msx-kit](../gb2msx-kit).

---

## 1. Le principe

La ColecoVision a un **Z80** : on utilise **le même traducteur** que pour le Spectrum et le CPC (`tools/gb2z80.py`). Une seule difficulté pour la logique : la console n'a que **1 Ko de RAM** (`$7000-$73FF`). Le traducteur déplace donc la RAM GB avec `RAM_MAP` (voir §3). Tout le reste est du travail sur le matériel, avec **une règle absolue pour le VDP** (voir §4).

## 2. Outils

| Outil | Rôle | Emplacement (machine de l'utilisateur) |
|---|---|---|
| **sjasmplus 1.24** | Assembleur Z80 | `%LOCALAPPDATA%\sjasmplus\sjasmplus-1.24.0.win\sjasmplus.exe` |
| **openMSX 21** | Émulateur (machine `ColecoVision`) | `%LOCALAPPDATA%\openMSX\openmsx.exe` |
| BIOS | `COLECO.ROM`, 8 Ko, SHA1 `45bedc4cbdeac66c7df59e9e599195c778d86a92` | `Documents\openMSX\share\systemroms\` (le nom du fichier est libre, openMSX le reconnaît au SHA1) |
| `tools/cvsim.py` | ColecoVision simulée (Z80 SkoolKit + VDP + NMI + manette) : **contrôle chaque accès VDP**, fait des captures | Fourni |
| `tools/diff_cv.py` | Comparaison pas à pas avec le jeu GB (PyBoy), RAM déplacée comprise | Fourni |

Lancer le jeu :

```powershell
& "$env:LOCALAPPDATA\openMSX\openmsx.exe" -machine ColecoVision -carta "<chemin>\build\tennis.rom"
```

openMSX peut signaler les accès VRAM trop rapides. Mettre dans un script tcl passé par `-script` :

```tcl
set VDP.too_fast_vram_access_callback warn_too_fast_vram_access
```

## 3. Mémoire

| Zone | Contenu |
|---|---|
| `$0000-$1FFF` | BIOS. Le jeu ne s'en sert pas, sauf le saut NMI `$0066` → `$8021` |
| `$7000-$73FF` | RAM (1 Ko, en miroir jusqu'à `$7FFF`) |
| `$8000-$FFFF` | Cartouche (32 Ko sans banques) |

En-tête de cartouche (`$8000`) :
- `$55,$AA` : démarrage direct, sans l'écran du BIOS (`$AA,$55` le montre) ;
- 4 mots pour les tables du BIOS (inutilisées) ;
- `$800A` : adresse de démarrage ;
- `$800C-$801B` : sauts des RST 08-30 ;
- `$801E` : RST 38 / IRQ ;
- `$8021` : **NMI** (interruption du VDP à chaque trame).

**Déplacer la RAM GB** : d'abord mesurer ce que la logique utilise vraiment (accès directs, `ldh`, immédiats 16 bits `ld hl/de,$C0xx`). Pour Tennis :
- la page `$C000-$C0FF` ;
- 34 octets de HRAM (`$FF80-$FFCB`) ;
- 1 octet en `$DD00`.

Dans `port_config.py` :

```python
def RAM_MAP(a):
    if 0xC000 <= a < 0xC100: return a - 0xC000 + 0x7000
    if 0xFF80 <= a <= 0xFFFF: return a - 0xFF00 + 0x7100
    if 0xDD00 <= a < 0xDE00: return a - 0xDD00 + 0x7200
    return None
```

`gb2z80.py` applique `RAM_MAP` :
- aux `ld (a16)`, aux `ldh`, et à l'octet haut des `ld (c)` ;
- aux immédiats 16 bits qui tombent dans la RAM déplacée.

Il avertit si un accès à la RAM GB n'est pas couvert.

Attention aux constantes qui **ressemblent** à des adresses (`ld de,$D001` = des coordonnées dans Tennis) : `RAM_MAP` ne touche qu'aux zones déclarées. **Vérifier ensuite par `diff_cv.py`.** Tennis : 2 755 pas identiques. Les 7 écarts relevés sont le réglage voulu des coups du joueur.

Le code écrit à la main utilise les adresses déplacées (`defs.asm`). Les variables du programme sont en RAM (`vars.asm`, `ds`), jamais dans la cartouche : `var: db 0` en ROM ne s'écrit pas !

## 4. Le VDP (TMS9918A) : la règle d'or

Sur une vraie console, **un accès à la mémoire vidéo trop rapproché pendant l'affichage est perdu**. Il faut 8 µs, soit ~29 cycles, entre deux accès. Pendant le retour de trame (~70 lignes, ~15 900 cycles), c'est libre. La VRAM n'est donc modifiée qu'à deux moments :

1. **écran éteint et NMI coupée** (`screen_off` … `screen_on`) pour dessiner le titre, le menu et le décor. On écrit alors à pleine vitesse ;
2. **dans la NMI**, depuis ce que la boucle principale a préparé en RAM :
   - motifs des sprites qui changent (`up_img`) ;
   - table des sprites (`sat_buf`) ;
   - textes (`add_job` : adresse VRAM, source, longueur).

La poignée de main `frame_ready` :
- la boucle attend la NMI, fait ses pas de logique, prépare, puis met `frame_ready = 1` ;
- la NMI envoie tout, puis remet `frame_ready = 0`.

**La NMI ne doit jamais couper une écriture d'adresse** (deux octets sur le port de contrôle). Le drapeau `vdp_free` règle ce cas :
- la NMI ne touche au VDP (même pas pour lire son état) que si `vdp_free = $A5` ;
- `screen_off` met `vdp_free` à 0 **avant** d'écrire le registre 1 ;
- `screen_on` met `vdp_free` à `$A5` **avant** de réactiver la NMI, dont le bit est écrit en dernier.

Après une NMI refusée, la ligne d'interruption reste basse. C'est sans danger : la réactivation du bit IE crée un nouveau front.

`cvsim.py` vérifie tout cela à chaque accès :
- écarts de moins de 29 cycles pendant l'affichage ;
- NMI au milieu d'une adresse ;
- durée de la NMI.

Tennis : aucune erreur, NMI de 9 600 cycles au plus.

## 5. Graphismes

- **Mode graphique 2** (256×192) : le stade GB fait 256 pixels de large et remplit l'écran (24 rangées sur 25 : on perd une rangée de sol).
- **2 couleurs par ligne de 8 pixels** : une ligne à plus de 2 teintes garde la paire la plus fidèle (`tms.encode_row`).
- Les 4 teintes GB deviennent les 4 verts du TMS : vert clair (3), vert (2), vert foncé (12), noir (1).
- L'écran est découpé en **3 tiers de 8 rangées, chacun avec ses 256 motifs**. La police est mise en 192-255 dans chaque tiers (`motif = code + 160`), le décor de 0 à 191.
- VRAM :

  | Adresse | Contenu |
  |---|---|
  | `$0000` | motifs |
  | `$1800` | carte |
  | `$1B00` | attributs des sprites |
  | `$2000` | couleurs |
  | `$3800` | motifs des sprites |

  Registres : `02 E2 06 FF 03 36 07 01` (`R1 = $82` écran éteint, `$E2` allumé + NMI).
- **Sprites** : 16×16, une couleur, **4 par ligne**.
  - Un joueur GB (3 teintes, jusqu'à 24×32) = **2 couches** : contour (teintes 2-3) dans la couleur du joueur, et teinte 1 en blanc. Soit 8 sprites au plus, 4 sur une même ligne.
  - Les motifs d'un objet sont recopiés par la NMI quand son image change : 32 octets par sprite, `outi` déroulé.
  - Balle et ombre passent en premier. L'ordre des joueurs, et de leurs sprites, s'inverse à chaque trame : un dépassement de 4 sprites clignote au lieu d'effacer toujours le même morceau.
- Table des sprites :
  - Y = ligne − 1 ;
  - **`$D0` termine la liste** : ne jamais placer un sprite visible à Y = `$D0`. On n'y met que les sprites visibles ;
  - X < 0 : bit EC (`$80` dans la couleur) et X + 32.

## 6. Son et manette

- **SN76489** (port `$FF`, horloge 3,58 MHz / 32) :
  - période SN = période AY (1 MHz) × 1,79 ;
  - atténuation = 15 − volume ;
  - bruit : `$E4 | vitesse` (0-2).
- **Manette** :
  - `OUT $C0` puis `IN $FC` : manche (bits 0-3 haut droite bas gauche) et bouton gauche (bit 6) ;
  - `OUT $80` puis `IN $FC` : pavé (bits 0-3) et bouton droit (bit 6) ;
  - bits à 0 = appuyé. Laisser quelques µs entre le `OUT` et le `IN` (`ex (sp),hl` ×2) ;
  - pavé, valeur lue → touche : `0:$0A 1:$0D 2:$07 3:$0C 4:$02 5:$03 6:$0E 7:$05 8:$01 9:$0B *:$09 #:$06`.

## 7. Cadence

60 Hz, un pas de logique GB par trame (59,7 Hz sur GB). La boucle rattrape au plus 3 trames de retard. Tennis : aucune trame en retard sur 5 000 trames jouées par le robot.

## 8. Pièges rencontrés

- `jr` hors de portée dans les grosses boucles de menu : mettre `jp`.
- Le code copié d'une autre version déclare des variables en `db` dans le code : en cartouche, c'est de la ROM. Tout déplacer dans `vars.asm`.
- Quand l'utilisateur renomme la cartouche (`Coleco Tennis.rom`), les outils qui l'ouvrent par défaut (`cvsim.py`) prennent un chemin en paramètre.
- openMSX a besoin du BIOS avant tout test. Sans lui, tester avec `cvsim.py`, qui simule la NMI sans BIOS (saut `$0066` → `$8021`).

## 9. Chiffres (Tennis)

| Élément | Taille |
|---|---|
| Logique traduite | ~12 Ko |
| Décor | 164 motifs, ~3 Ko avec la carte |
| Sprites | 140 motifs 16×16, 5,5 Ko |
| Cartouche | 24 Ko sur 32 |

Un pas de logique coûte 6 900 T en moyenne (Z80), 14 100 au pire.
