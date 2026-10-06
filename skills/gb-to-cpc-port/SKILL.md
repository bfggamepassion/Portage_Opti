---
name: gb-to-cpc-port
description: Porter un jeu Game Boy vers l'Amstrad CPC (464/664/6128) en traduisant la ROM GB (SM83) en assembleur Z80 (sjasmplus) avec le kit gb2cpc664-kit — plan mémoire 64K, sprites logiciels XOR pré-décalés, synchro VSYNC, mode 0/1, son AY, disquettes, tests Caprice32. À utiliser pour porter, convertir ou adapter un jeu Game Boy vers le CPC, ou pour toute question de sprites logiciels CPC, de conversion des graphismes GB en mode 0/1, de son AY, d'images disque ou de tests Caprice32.
---

# Game Boy → Amstrad CPC

Méthode générale : skill `portage-retro`. Optimisation CPC : skill `cpc-optimisation`.

## Où est tout

- Kit : `<DEPOT>\kits\gb2cpc664-kit\`
  - `PORTING.md` : **méthode CPC, à lire en entier** — plan mémoire 64K (écran en $4000, firmware coupé,
    données de démarrage dans la fenêtre $4000 du fichier) ; sprites logiciels (XOR, lignes rognées,
    4 pré-décalages construits au démarrage, redessin des seuls sprites changés dans l'ordre du faisceau,
    synchro sur le front de VSYNC lu sur le PPI) ; titre mode 0 avec palette par rangée ; clavier/joystick
    par le PSG ; son AY ; automatisation de Caprice32, pièges, chiffres.
  - `template/` : `gb2z80.py` (même traducteur que le Spectrum, avec `RAM_MAP`), `cpcgfx.py`,
    `make_dsk.py`, `cpcshot.sh`, `sim64.py` et un squelette sjasmplus qui démarre dans Caprice32 et déplace un sprite.
- Rétro-ingénierie et vérification communes : `<DEPOT>\kits\gb2zx-kit\PORTING.md` §4-6 ; la logique Z80
  se vérifie avec `diff_gb.py` du kit Spectrum.

## Démarrer

1. Lire `gb2cpc664-kit\PORTING.md`.
2. Poser les décisions : modèle cible, mode graphique, 1 ou 2 boutons, nom, langue.
3. Copier `template/*`, ROM dans `re/game.gb`, remplir `port_config.py`, traduire et vérifier comme pour le Spectrum.
4. Remplacer les graphismes de démonstration par ceux du jeu (`cpcgfx.py`), écrire `render.asm` d'après les routines OAM de la ROM, puis le menu.
5. Après chaque étape visible : une capture Caprice32, puis lancement pour l'utilisateur.

## Non négociable

- Ne jamais éditer `gb/gb_logic.asm` ; tout remplacement à la main est vérifié contre la ROM traduite.
- Surveiller les `ASSERT` des parties A et B : la mémoire est juste sur un 64K.
- Dessiner les sprites juste après le front de VSYNC lu sur le PPI ; jamais trouver la VSYNC en comptant les interruptions.
