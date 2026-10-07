# Prompt 2 : portage

Rôle : tu portes un jeu de [machine d'origine] ([processeur d'origine]) vers [machine cible] ([processeur cible, fréquence], assembleur [assembleur]). Tu pars du travail de préparation, qui se trouve dans le dépôt : [chemins du listing, du fichier de noms, de la frontière du portage, de l'outil de comparaison, du fichier de reprise].

## Principe

La logique du jeu reste identique à l'original : mêmes calculs, mêmes résultats, même vitesse de jeu.

L'affichage, le son et les entrées sont réécrits avec les techniques propres à la machine cible, jamais en émulant ceux de la machine d'origine.

## Stratégie selon le processeur

**Même processeur** : garder le programme d'origine en mémoire et le corriger aux points de la frontière du portage. Les routines d'affichage, de son et d'entrées sont remplacées par des appels à un moteur natif, et leurs effets non graphiques sont conservés.

**Processeur différent** : traduction statique en code natif (pas d'interpréteur), routine par routine, avec une table d'équivalences. Pièges à traiter :
- indicateurs (flags) qui ne se comportent pas pareil ;
- ordre des octets des valeurs sur 16 ou 32 bits ;
- code qui se modifie lui-même ;
- données lues comme du code ;
- astuces de pile ;
- boucles d'attente calées sur la vitesse du processeur d'origine.

## À concevoir avant d'écrire du code (proposer, estimer, puis me faire valider)

- **Mémoire** : carte de la machine cible (jeu, moteur, écrans, graphismes, son), banques éventuelles, place libre.
- **Affichage** : selon la machine, dessin logiciel (mode graphique, sprites avec masques, effacement, double écran) ou puce graphique (sprites et tuiles matériels, limites par ligne, moments où la mémoire vidéo est accessible). Défilement. Résolution et proportions différentes : recadrer, élargir ou réduire la zone de jeu. Budget de temps par tour.
- **Cadence** : la logique tourne au rythme de l'original. Si les fréquences diffèrent (50 Hz / 60 Hz), décider comment garder la vitesse du jeu. L'affichage peut sauter des images, jamais ralentir la logique.
- **Graphismes** : conversion vers le format de la cible par des outils hors ligne (images modifiables → données de la cible), base d'un futur éditeur.
- **Son, entrées** (clavier, joystick, redéfinition des touches), **chargements**.

## Vérification

Deux niveaux, pour ne pas payer le contrôle complet à chaque petite étape :

- **Contrôle rapide, à chaque étape (moins de 2 minutes)** : assemblage sans erreur, et l'outil de comparaison (qui donne seul le diagnostic d'un écart) sur une seule courte partie scriptée (quelques centaines de tours, un niveau) qui passe par le code modifié : mémoire du jeu identique à l'original, tour par tour.
- **Contrôle complet, aux paliers seulement** (fin d'une partie du moteur, avant de me livrer une version) : parties scriptées dans plusieurs niveaux, coût mesuré de chaque partie du moteur en % du budget d'un tour, puis démarrage, chargements et affichage vérifiés sur un vrai émulateur de la machine cible.
- Le coût du moteur ne se remesure que si l'étape touche l'affichage, le son ou la cadence.
- Un test de plus de 2 minutes tourne en tâche de fond et affiche sa progression ; on continue à travailler pendant ce temps.
- Si le contrôle rapide trouve un écart, s'arrêter et le corriger avant d'aller plus loin.

## Méthode

- Avancer par petites étapes, chacune vérifiée puis committée.
- Documenter au fil de l'eau : chaque partie du jeu comprise met à jour le fichier de noms et la carte de la mémoire dans le même commit.
- Tenir à jour le fichier de reprise (format dans « Aller vite »).
- Ne jamais promettre un résultat sans l'avoir mesuré.

## Aller vite sans perdre en fiabilité

- **Outils de la préparation** : simulateur, comparaison (traces de l'original déjà calculées), sauvegardes d'état et `check.sh` sont dans le dépôt, cités par le fichier de reprise : s'en servir, ne pas les refaire. Pour atteindre un niveau ou une scène, recharger une sauvegarde au lieu de rejouer. S'il manque un outil, réutiliser d'abord les kits de `Portage_Opti` (skill `portage-retro`) ; sinon l'écrire comme en préparation (`prompts/01_preparation.md` de `Portage_Opti`) : générique et séparé du jeu, avec son test, installé par un script sans manipulation de ma part.
- **Construire et tester dans un dossier local**, hors du dossier synchronisé (Google Drive, OneDrive) : plus rapide et sans fichiers corrompus.
- **Tests longs en tâche de fond**, avec leur progression. Les tests indépendants se lancent en parallèle.
- **Une seule commande de contrôle** : `sh check.sh rapide` et `sh check.sh complet`. Elle enchaîne construction et tests, s'arrête à la première erreur et rend un code d'échec ; c'est elle qu'on lance, toujours la même, notée dans le fichier de reprise. Ne jamais juger un résultat à travers `tail` ou une sortie tronquée.
- **Ne pas relire ce qui est connu** : le fichier de reprise, le fichier de noms et la carte de la mémoire font foi. Chercher une adresse ou une routine par une recherche ciblée, pas en relisant tout le listing.
- **Fichier de reprise court** (une page environ), toujours dans le même ordre : 1. état ; 2. commandes (construction, `check.sh`, lancement) ; 3. prochaine action exacte ; 4. pièges. Le détail (mesures, essais abandonnés et pourquoi, historique) va dans un journal à part qu'il cite.
- **Limiter chaque piste** : après deux essais sans résultat, noter la piste et ce qui a été essayé dans le journal, puis passer à une autre approche, ou me proposer des concessions chiffrées si le choix me revient.
- **Émulateur réel aux paliers seulement**, une fenêtre à la fois ; entre deux paliers, le simulateur suffit.

## Économiser les tokens

- **Sorties courtes** : chaque outil (simulateur, comparaison, profileur, `check.sh`) affiche par défaut un résumé de quelques lignes (ex. « rapide : OK, 12 tests, 48 s », ou le diagnostic d'un écart) et écrit le détail dans un fichier, lu seulement si besoin. Jamais de trace, de vidage mémoire ou de listing complet à l'écran.
- **Lire peu** : le listing, les traces et les fichiers générés se consultent par recherche ciblée ou par plage de lignes, jamais en entier.
- **Code traduit** : le code produit par un traducteur ne se relit ni ne se modifie : on corrige le traducteur ou le fichier de noms, puis on régénère.
- **Scripts plutôt que commandes à la suite** : toute séquence répétée (construire, tester, mesurer, capturer) devient un script lancé en une fois.
- **Images : comparer par calcul, regarder quand ça compte.** Les écrans se vérifient d'abord par comparaison chiffrée (octet par octet avec la référence, ou différence de pixels avec seuil), plus fiable qu'un coup d'œil. Une image est regardée quand le calcul ne peut pas trancher : premier affichage d'un nouvel écran ou d'un nouveau graphisme, différence voulue, couleurs et palette, écart signalé par la comparaison, et toujours au palier avant de me livrer une version. On regarde alors la zone utile rognée, à la taille réelle ou agrandie, plutôt que l'écran entier réduit (la réduction cache les défauts d'un pixel).

Pas de texte entre deux étapes. Un compte rendu court et simple à chaque palier ou point d'arrêt, et un dernier à la fin : ce qui a été fait, ce qui est mesuré ou seulement estimé, ce qui reste.
