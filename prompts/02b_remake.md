# Prompt 2b : remake (réécriture native vérifiée)

Rôle : tu réalises un remake de [jeu] ([machine d'origine], [processeur d'origine]) pour [machine cible] ([modèle exact, processeur, fréquence, 50 ou 60 Hz], assembleur [assembleur]). Ce n'est pas un portage du programme d'origine : tu écris un jeu natif dont le **comportement est identique à l'original**, prouvé par comparaison avec lui. Vitesses, sauts, ennemis, collisions, minuteries, scores, sons et enchaînement des écrans doivent donner le même ressenti que le jeu d'origine.

À choisir plutôt que le prompt 2 (portage) quand le code d'origine ne peut pas servir de moteur sur la cible : trop lent, trop lié à l'affichage d'origine, ou processeur trop différent pour une traduction efficace.

Tu pars du travail de préparation, qui se trouve dans le dépôt (lis d'abord le fichier de reprise) : [chemins du listing réassemblable, du fichier de noms, de la frontière du portage, du simulateur de l'original, des parties de référence et sauvegardes d'état, d'un éventuel portage précédent réutilisable pour son savoir-faire].

## Principe

- **L'original est l'oracle.** Son simulateur rejoue les parties de référence ; le remake rejoue les mêmes parties et doit produire la même trace.
- **Conception native** : les techniques propres à la cible (sprites matériels ou logiciels, tuiles ou caractères pour le décor, défilement matériel, puce son), jamais une émulation de l'écran, du son ou des entrées d'origine. Données des niveaux préparées hors ligne par des outils.
- **Chaque règle du jeu vient du code d'origine** : vitesses, accélérations, minuteries, conditions de collision, de mort et de réussite, points, hasard. Dans le source du remake, chaque constante et chaque règle porte en commentaire l'adresse d'origine qui la justifie (ex. `; $3F93 : vitesse de l'oiseau`). Pas de spécification séparée qui doublerait le code.

## Le temps

- L'original avance souvent par tours de durée variable et déclenche chaque action tous les N tours. Mesure sur l'oracle la fréquence réelle de chaque action, en actions par seconde, et reproduis-la à une image près sur la cible. La table de conversion (action, fréquence d'origine mesurée, réglage sur la cible) est un fichier de constantes généré par un outil, relu par l'assemblage.
- **Les entrées des parties de référence sont datées en temps** (millisecondes ou images de la cible), pas en tours d'origine : l'oracle convertit ses scénarios une fois, et les deux côtés rejouent les mêmes appuis aux mêmes instants.
- La boucle du remake est calée sur l'image de la cible et tient toujours dans son budget.

## Le hasard

Reproduis la loi (mêmes plages, mêmes fréquences), pas forcément la suite exacte. Pour les comparaisons, une version de test du remake lit les valeurs aléatoires relevées sur l'oracle (table chargée à la place du générateur), dans le même ordre d'appel.

## Trace et comparaison

- **Format de trace commun**, indépendant de la mémoire de chaque machine : à chaque instant, chaque objet (type, x, y, état) et chaque événement (saut, mort, points, fin de niveau, son) avec sa date. Côté original, l'oracle l'extrait grâce au fichier de noms ; côté remake, la version de test l'écrit.
- **L'outil de comparaison** donne seul le diagnostic : premier événement manquant ou en trop, premier écart de position au-delà de la tolérance, objets en cause, règle du remake concernée.
- **Tolérances** : proposées par toi, chiffrées, puis validées par moi avant de servir (ex. mêmes événements dans le même ordre, écart de date < [1/25 s], écart de position < [1 case]). L'écart de date se mesure au maximum sur toute la partie, pas en moyenne : une fréquence légèrement fausse dérive sur une longue partie.
- Les écarts voulus (règle simplifiée, contenu retiré avec mon accord) sont inscrits dans la configuration de la comparaison avec leur raison en commentaire ; elle ne signale que les autres.

## À concevoir avant d'écrire du code (proposer, estimer, puis me faire valider)

- **Mémoire** : carte de la cible (code, données d'un niveau, graphismes, son, tampons), banques éventuelles, place libre.
- **Affichage** : ce qui est sprite, ce qui est décor ; limites par ligne et multiplexage ; défilement ; double écran ; résolution et proportions (recadrer, élargir, réduire la zone de jeu) ; couleurs choisies pour la cible.
- **Budget par image** : coût estimé de chaque partie (logique, sprites, décor, son, entrées) en % du temps d'une image, avec une marge pour le pire cas.
- **Collisions** : par cases ou par boîtes, équivalentes à celles de l'original (même résultat sur les parties de référence).
- **Données** : format des niveaux, outils de conversion, chargement (disquette, cassette, cartouche, banques) au début de chaque niveau.
- **Entrées** : [manette, clavier, touches redéfinies] ; **son** : conversion des musiques et effets.

## Vérification

Deux niveaux, pour ne pas payer le contrôle complet à chaque petite étape :

- **Contrôle rapide, à chaque étape (moins de 2 minutes)** : assemblage sans erreur, comparaison sur une seule courte partie de référence qui passe par le code modifié, coût mesuré de la routine modifiée, puis commit. Une optimisation sans gain mesuré est retirée.
- **Contrôle complet, aux paliers seulement** (fin d'un niveau, avant de me livrer une version) : toutes les parties de référence du niveau, profil en % du temps d'une image (moyenne et pire cas), essai sur un vrai émulateur de la cible avec chargement réel depuis le support, captures vérifiées.
- Un test de plus de 2 minutes tourne en tâche de fond et affiche sa progression ; on continue à travailler pendant ce temps.
- Si un contrôle trouve un écart, s'arrêter et le corriger avant d'aller plus loin. Ne jamais annoncer un résultat non mesuré.

## Méthode

1. Outils d'abord : trace commune côté oracle, conversion des scénarios en temps, table des fréquences, comparaison. Chacun avec son test.
2. **Un seul niveau** d'abord, choisi pour couvrir le plus de mécaniques (proposé par toi : [ou niveau imposé]), avec le héros, le but, la mort et la fin du niveau : règles, remake, comparaison, puis livraison pour essai. **Arrêt** : attends mon avis avant de généraliser.
3. Puis les autres niveaux un par un, puis menus, écrans, scores, sons.
4. Petites étapes, chacune vérifiée puis committée. Le fichier de noms, la carte de la mémoire du remake et la table des fréquences sont mis à jour dans le même commit.
5. Tiens à jour le fichier de reprise (format dans « Aller vite »).

Définition de fini, pour chaque niveau : toutes ses parties de référence passent la comparaison dans les tolérances validées, le pire cas tient dans le budget d'une image, et la version a été essayée sur un vrai émulateur.

## Livrables

- le remake (source, outils de conversion des données, script de reconstruction) et le support de la cible (disquette, cassette, ROM) ;
- l'extracteur de trace côté oracle, la conversion des scénarios, la table des fréquences, l'outil de comparaison et sa configuration (tolérances, écarts voulus) ;
- le fichier de reprise.

## Aller vite sans perdre en fiabilité

- **Outils de la préparation** : simulateur, parties de référence, sauvegardes d'état et `check.sh` sont dans le dépôt, cités par le fichier de reprise : s'en servir, ne pas les refaire. Pour atteindre un niveau ou une scène, recharger une sauvegarde au lieu de rejouer. S'il manque un outil, réutiliser d'abord les kits de `Portage_Opti` (skill `portage-retro`) et le savoir-faire d'un portage précédent ; sinon l'écrire comme en préparation (`prompts/01_preparation.md` de `Portage_Opti`) : générique et séparé du jeu, avec son test, installé par un script sans manipulation de ma part.
- **La trace de l'original se calcule une seule fois** par scénario, avec le MD5 de l'image et du scénario ; seule la trace du remake est refaite à chaque contrôle.
- **Construire et tester dans un dossier local**, hors du dossier synchronisé (Google Drive, OneDrive) : plus rapide et sans fichiers corrompus.
- **Tests longs en tâche de fond**, avec leur progression. Les tests indépendants se lancent en parallèle.
- **Une seule commande de contrôle** : `sh check.sh rapide` et `sh check.sh complet`. Elle enchaîne construction et tests, s'arrête à la première erreur et rend un code d'échec ; c'est elle qu'on lance, toujours la même, notée dans le fichier de reprise. Ne jamais juger un résultat à travers `tail` ou une sortie tronquée.
- **Ne pas relire ce qui est connu** : le fichier de reprise, le fichier de noms et la carte de la mémoire font foi. Chercher une adresse ou une routine par une recherche ciblée, pas en relisant tout le listing.
- **Fichier de reprise court** (une page environ), toujours dans le même ordre : 1. état ; 2. commandes (construction, `check.sh`, lancement) ; 3. prochaine action exacte ; 4. pièges. Le détail (mesures, essais abandonnés et pourquoi, historique) va dans un journal à part qu'il cite.
- **Limiter chaque piste** : après deux essais sans résultat, noter la piste et ce qui a été essayé dans le journal, puis passer à une autre approche, ou me proposer des concessions chiffrées si le choix me revient.
- **Émulateur réel aux paliers seulement**, une fenêtre à la fois ; entre deux paliers, l'oracle et la version de test suffisent.

## Économiser les tokens

- **Sorties courtes** : chaque outil (oracle, comparaison, profileur, `check.sh`) affiche par défaut un résumé de quelques lignes (ex. « rapide : OK, 12 tests, 48 s », ou le diagnostic d'un écart) et écrit le détail dans un fichier, lu seulement si besoin. Jamais de trace, de vidage mémoire ou de listing complet à l'écran.
- **Lire peu** : le listing, les traces et les fichiers générés se consultent par recherche ciblée ou par plage de lignes, jamais en entier.
- **Scripts plutôt que commandes à la suite** : toute séquence répétée (construire, tester, mesurer, capturer) devient un script lancé en une fois.
- **Images : comparer par calcul, regarder quand ça compte.** Les écrans se vérifient d'abord par comparaison chiffrée, plus fiable qu'un coup d'œil. Une image est regardée quand le calcul ne peut pas trancher : premier affichage d'un nouvel écran ou d'un nouveau graphisme, couleurs et palette, écart signalé par la comparaison, et toujours au palier avant de me livrer une version. On regarde alors la zone utile rognée, à la taille réelle ou agrandie, plutôt que l'écran entier réduit (la réduction cache les défauts d'un pixel).
- **Pas de sous-agents**, sauf pour un travail volumineux et indépendant.

Pas de texte entre deux étapes. Un compte rendu court et simple à chaque palier ou point d'arrêt, et un dernier à la fin : ce qui a été fait, ce qui est mesuré ou seulement estimé, ce qui reste.
