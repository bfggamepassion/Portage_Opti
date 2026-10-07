# Prompts génériques pour porter ou optimiser un jeu rétro

Prompts à coller dans Claude Code, au début d'une session, dans le dépôt du jeu. Ils valent pour n'importe
quel jeu et n'importe quelle paire de machines : remplir les champs entre `[ ]`.

Les quatre premiers s'enchaînent : la préparation produit ce dont le portage a besoin, le portage ce dont
l'optimisation a besoin. L'adaptation s'intercale quand le jeu ne tient pas sur la cible.

| Fichier | Quand |
|---|---|
| [01_preparation.md](01_preparation.md) | Avant tout : extraire, simuler, désassembler, délimiter la frontière du portage |
| [02a_portage.md](02a_portage.md) | Écrire le portage (logique identique, affichage/son/entrées natifs) |
| [02b_remake.md](02b_remake.md) | Ou réécrire le jeu en natif quand le code d'origine ne peut pas servir de moteur, comportement prouvé identique par l'oracle |
| [03_optimisation.md](03_optimisation.md) | Le portage marche mais ne tient pas la cadence |
| [04_adaptation.md](04_adaptation.md) | Le jeu est trop gros pour la cible : trancher, avec l'accord de l'utilisateur |
| [05_optimisation_sans_portage.md](05_optimisation_sans_portage.md) | Accélérer un jeu sur sa propre machine |
| [format_image_cpc.md](format_image_cpc.md) | Prompt pour générer des graphismes au format CPC mode 0 (ChatGPT ou autre) |

Conseils :
- Installer d'abord les skills (`installer.ps1` à la racine) : Claude choisit seul le kit et les références
  de la machine (skill `portage-retro`, puis `gb-to-*-port`, `coleco-to-cpc-port`, `cpc-optimisation`, `c64-optimisation`).
- Une phase par session. En reprise de session : « Lis le fichier de reprise et continue. »
- Le fichier de reprise (REPRISE.md) est la mémoire du projet : il doit suffire pour reprendre après une coupure.
