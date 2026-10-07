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

- **Contrôle rapide, à chaque étape (moins de 2 minutes)** : assemblage sans erreur, et l'outil de comparaison sur une seule courte partie scriptée (quelques centaines de tours, un niveau) qui passe par le code modifié : mémoire du jeu identique à l'original, tour par tour.
- **Contrôle complet, aux paliers seulement** (fin d'une partie du moteur, avant de me livrer une version) : parties scriptées dans plusieurs niveaux, coût mesuré de chaque partie du moteur en % du budget d'un tour, puis démarrage, chargements et affichage vérifiés sur un vrai émulateur de la machine cible.
- Le coût du moteur ne se remesure que si l'étape touche l'affichage, le son ou la cadence.
- Un test de plus de 2 minutes tourne en tâche de fond et affiche sa progression ; on continue à travailler pendant ce temps.
- Si le contrôle rapide trouve un écart, s'arrêter et le corriger avant d'aller plus loin.

## Méthode

- Avancer par petites étapes, chacune vérifiée puis committée.
- Documenter au fil de l'eau : chaque partie du jeu comprise met à jour le fichier de noms et la carte de la mémoire dans le même commit.
- Tenir à jour le fichier de reprise.
- Ne jamais promettre un résultat sans l'avoir mesuré.

NE SOIT PAS VERBEUX !! EXPLIQUE MOI CE QUE TU AS FAIT A LA TOUTE FIN.
