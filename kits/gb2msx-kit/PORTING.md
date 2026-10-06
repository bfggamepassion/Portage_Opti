# Porter un jeu Game Boy sur MSX1 : méthode

Ce guide tire les leçons du portage de **MSX Tennis** (Tennis, Nintendo 1989) :
- le projet complet est dans `G:\Mon Drive\Coding\Tennis\MSX` ;
- le modèle réutilisable est dans [template/](template/) ;

Le MSX1 a **le même VDP que la ColecoVision** (TMS9918A) et le même Z80. La version MSX est partie de la version ColecoVision : **lire d'abord [../gb2coleco-kit/PORTING.md](../gb2coleco-kit/PORTING.md)** (règle du VDP, mode 2, sprites en couches, `RAM_MAP`). Ce guide ne décrit que les différences. Les étapes communes (rétro-ingénierie, fermeture, configuration, preuve de fidélité) sont dans [../gb2zx-kit/PORTING.md](../gb2zx-kit/PORTING.md) §4 à §6.

---

## 1. Outils

| Outil | Rôle | Emplacement |
|---|---|---|
| **sjasmplus 1.24** | Assembleur Z80 | `%LOCALAPPDATA%\sjasmplus\sjasmplus-1.24.0.win\sjasmplus.exe` |
| **openMSX 21** | Émulateur. **C-BIOS est fourni** : aucun BIOS à copier | `%LOCALAPPDATA%\openMSX\openmsx.exe` |
| `tools/msxsim.py` | MSX simulé (faux BIOS) : contrôle des accès VDP, du registre 7 du PSG, captures ; `--50` pour 50 Hz | Fourni |
| `tools/diff_msx.py` | Comparaison pas à pas avec le jeu GB | Fourni |

Machines : `C-BIOS_MSX1_EU` (50 Hz) et `C-BIOS_MSX1` (60 Hz). Il faut tester les deux :

```powershell
& "$env:LOCALAPPDATA\openMSX\openmsx.exe" -machine C-BIOS_MSX1_EU -cart "<chemin>\build\tennis.rom"
```

**Automatiser openMSX** : passer un script tcl avec `-script`. On peut y mettre :
- `after time 5 {screenshot -raw -prefix "C:/…/shot"}` : une capture ;
- `keymatrixdown 8 1` / `keymatrixup 8 1` : appuyer puis relâcher ESPACE ;
- `peek 0xC100` : lire la mémoire ;
- `after time 15 {exit}` : quitter.

**Ne pas mettre `set throttle off`** : les images sautées donnent des captures noires.

## 2. Mémoire et cartouche

- Cartouche de 32 Ko en `$4000-$BFFF` :
  - en-tête `"AB"`, puis l'adresse `INIT` (appelée par le BIOS), 3 mots à 0 et 6 octets à 0 ;
  - le BIOS n'ouvre que la page `$4000`. À `INIT`, **ouvrir la page `$8000` dans le même slot** : `RSLREG` (`$0138`), `EXPTBL` (`$FCC1`), `SLTTBL` (`EXPTBL+4`), puis `ENASLT` (`$0024`) avec H = `$80`. Voir `main.asm`.
- RAM : `$C000-$FFFF` existe sur tout MSX de 16 Ko ou plus. La page GB `$C000` garde son adresse. La **HRAM `$FF80` est la zone système du MSX** : elle est déplacée en `$C180`, et `$DD00` en `$C200` (`RAM_MAP`).
- Après le démarrage, on ne rappelle plus le BIOS. L'interruption est à nous :
  - `IM 2`, table de 257 octets `$C5` en `$C400`, saut en `$C5C5` ;
  - l'octet présent sur le bus pendant l'interruption vaut `$FF` sur MSX, d'où la table de 257 octets.

## 3. VDP : différences avec la ColecoVision

- Ports `$98` (données) et `$99` (contrôle).
- L'interruption du VDP est une **interruption normale** (IM 2), pas une NMI. Plus besoin de `vdp_free` : la boucle principale coupe les interruptions (`di`) pendant qu'elle dessine écran éteint. `screen_on` écrit le registre 1 (`$E2`) puis fait `ei`.
- L'interruption lit l'état du VDP (acquittement), compte la trame, puis envoie ce que la boucle a préparé (`frame_ready`), comme sur Coleco.
- Budget du retour de trame : 70 lignes à 60 Hz (~15 960 cycles), 121 lignes à 50 Hz. Le MSX ajoute un cycle d'attente par lecture d'instruction : les vrais écarts sont un peu plus grands que ceux de `msxsim.py`, donc plus sûrs.

## 4. Son : AY-3-8910

- Ports `$A0` (registre), `$A1` (écriture), `$A2` (lecture). Horloge 1,79 MHz : période = période du CPC (AY à 1 MHz) × 1,79.
- **Le registre 7 doit garder ses bits 7-6 à `10`** : port B en sortie, port A en entrée, pour les joysticks. Le mixer de base est `%10111111`. `msxsim.py` signale toute autre valeur.

## 5. Clavier et joystick

- **Clavier** :
  - choisir la ligne dans les bits 0-3 du port C du PPI (`$AA`), en gardant les bits 4-7 ;
  - lire le port B (`$A9`), bits à 0 = appuyé ;
  - ligne 8 : bit 0 ESPACE, 4 gauche, 5 haut, 6 bas, 7 droite ;
  - ligne 4 : bit 2 M ;
  - ligne 0 : bits 0-7 = chiffres 0-7.
- **Joystick du port 1** :
  - registre 15 du PSG : bit 6 à 0 (port 1), bits 0-1 à 1 ;
  - puis lire le registre 14 : bits 0-3 haut bas gauche droite, bits 4-5 boutons A et B, à 0 = appuyé.

## 6. 50 Hz et 60 Hz

L'octet `$002B` du BIOS dit la fréquence (bit 7 : 1 = 50 Hz). La logique garde le rythme du GB (59,7 Hz) :
- à 60 Hz, un pas par trame ;
- à 50 Hz, 6 pas pour 5 trames (motif 2,1,1,1,1, comme sur CPC).

Tennis : aucune trame en retard, à 50 comme à 60 Hz.

## 7. Pièges rencontrés

- Une ligne de commande bash qui contient beaucoup d'apostrophes françaises (`l'interruption`) casse le « heredoc » : écrire les scripts de correction dans des fichiers.
- Quand l'utilisateur renomme la cartouche (`MSX Tennis.rom`), passer le chemin aux outils.

## 8. Chiffres (Tennis)

- Cartouche : 24 Ko sur 32.
- Interruption la plus longue : 9 600 cycles à 60 Hz, 11 700 à 50 Hz.
