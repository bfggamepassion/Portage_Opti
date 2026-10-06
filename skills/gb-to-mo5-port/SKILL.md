---
name: gb-to-mo5-port
description: Porter un jeu Game Boy vers le Thomson MO5 (cassette) en traduisant la ROM GB (SM83) en assembleur 6809 (asm6809) avec le kit gb2mo5-kit — traducteur SM83→6809, émulateur 6809 maison, faits matériels MO5 (banques vidéo, octet de couleur, clavier, synchro $A7E7), recomposition de cases au lieu de sprites, format .k7, tests DCMOTO. À utiliser pour porter un jeu Game Boy vers un Thomson MO5 (ou machines 6809 MO6/TO7), ou pour toute question de traduction SM83→6809.
---

# Game Boy → Thomson MO5

Méthode générale : skill `portage-retro`.

## Où est tout

- Kit : `<DEPOT>\kits\gb2mo5-kit\`
  - `PORTING.md` : **méthode, à lire en entier** — modèle du traducteur 6809 (registres GB en page directe,
    Z/C natifs, vivacité interprocédurale des indicateurs) ; trous de la vérification (initialisation,
    rejouer de vraies entrées) ; faits matériels MO5 tirés de MAME ; recomposition de cases ; format `.k7` ; buzzer.
  - `template/` : outils et sources complets (ROM dans `re/game.gb`) : `gb2m6809.py`, `m6809.py` +
    `test_m6809.py`, `mo5sim.py`, `diff_mo5.py`, `make_k7.py`, `gen_mo5gfx.py`.
- Rétro-ingénierie commune : `<DEPOT>\kits\gb2zx-kit\PORTING.md` §4-6.

## Démarrer

1. Lire `gb2mo5-kit\PORTING.md`.
2. Poser les décisions : MO5 seul ou MO6 aussi, cassette ou disquette, contrôles, nom, langue.
3. Copier `template/*`, ROM dans `re/game.gb`, remplir `port_config.py` ; vérifier l'appariement PUSH AF/POP AF et que les tables de pointeurs `DATA_BLOCKS` restent petit-boutistes.
4. Vérifier la logique avec `diff_mo5.py`, comparer aussi l'initialisation à une version Z80 et rejouer de vraies entrées.
5. Adapter `gen_mo5gfx.py` et `render.asm`, contrôler avec `mo5sim.py`. DCMOTO n'a pas de ligne de commande : indiquer « Simuler le clavier » pour `LOADM"",,R`.

## Non négociable

- Ne jamais éditer `gb/gb_logic.asm`.
- Compter les images sur les fronts descendants du bit 7 de `$A7E7`, pas sur l'indicateur 50 Hz du PIA.
- Ne rien affirmer sur le matériel réel : seul DCMOTO a servi de test.
