# Prompt 3 : optimisation

Rôle : tu optimises le portage d'un jeu sur [machine cible] ([processeur, fréquence], assembleur [assembleur]). Le portage fonctionne et sa logique est vérifiée identique à l'original. Le code, les outils et la documentation sont dans le dépôt : [chemins].

## Objectif

Le jeu tient sa cadence d'origine ([ex. 25 tours/s, 50 Hz, 60 Hz]) dans le pire cas, c'est-à-dire la scène la plus chargée.

Budget par tour = [N trames × durée d'une trame], dans l'unité naturelle de la machine ([ex. NOPs sur CPC, cycles sur 6502/68000, T-states sur Spectrum/MSX]). La logique et l'affichage partagent ce budget.

Contraintes matérielles : [ex. accès à la mémoire vidéo seulement pendant le retour de trame, sprites par ligne, banques].

## Règles

- La logique ne change pas : la comparaison avec l'original reste identique, tour par tour.
- Le rendu ne change pas, sauf amélioration voulue : écran comparé octet par octet, avec une version à cadence fixe.
- Ne rien affirmer sans l'avoir mesuré. Une estimation est notée comme telle, puis remplacée par la mesure.
- Chaque optimisation indique son coût en mémoire (octets, emplacement). Budget mémoire : [carte de la mémoire / zones libres].

## Méthode, dans cet ordre

1. **Mesurer.** Un profileur sur des parties réelles, dans plusieurs niveaux, donne le coût de chaque grande partie en % du budget : logique, dessin des sprites, gestion des sprites, décor, défilement, son, attente. Relever la moyenne et le pire cas.
2. **Architecture d'abord.** Pour les deux ou trois plus gros postes, chercher quel travail peut être supprimé plutôt qu'accéléré : ne pas redessiner ce qui n'a pas changé, préparer hors ligne plutôt que pendant le jeu, se servir du matériel (défilement, sprites matériels, double écran, puce graphique). Pour chaque proposition : gain estimé, coût en mémoire, risque, ampleur du travail. Me faire valider avant de coder.
3. **Micro-optimisation ensuite**, seulement sur les routines les plus chaudes, en appliquant [skill ou liste d'astuces propres à la machine]. Signaler les astuces risquées et leurs précautions :
   - pile détournée : couper les interruptions ;
   - code qui se modifie : attention aux banques et à l'interruption ;
   - tables alignées : attention au passage de page.
4. **Vérifier chaque changement**, en deux niveaux :
   - **contrôle rapide, à chaque changement (moins de 2 minutes)** : coût avant/après de la routine modifiée, mesuré sur une scène chargée qui l'exécute ; logique et rendu identiques sur une seule courte partie scriptée qui passe par ce code ; puis commit. Une optimisation sans gain mesurable est retirée ;
   - **contrôle complet, aux paliers seulement** (fin d'un chantier, avant de me livrer une version) : profil de tous les postes en % du budget, moyenne et pire cas, logique et rendu identiques sur des parties dans plusieurs niveaux, essai sur un vrai émulateur ;
   - un test de plus de 2 minutes tourne en tâche de fond et affiche sa progression ; si le contrôle rapide trouve un écart, s'arrêter et le corriger avant d'aller plus loin.
5. **La logique du jeu en dernier**, seulement s'il manque quelques %. D'abord supprimer le travail resté pour l'affichage de la machine d'origine, puis accélérer les routines les plus lourdes, sous contrôle de la comparaison avec l'original.

## Comptes rendus

Pas de texte entre deux étapes. À chaque palier ou point d'arrêt, et à la fin, un compte rendu court : tableau par poste, en % du budget, avant/après, avec ce qui dépasse ; ce qui est mesuré ou seulement estimé ; prochaine étape. Mesures et essais abandonnés vont dans le journal, pas dans le fichier de reprise.

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
- **Scripts plutôt que commandes à la suite** : toute séquence répétée (construire, tester, mesurer, capturer) devient un script lancé en une fois.
- **Images : comparer par calcul, regarder quand ça compte.** Les écrans se vérifient d'abord par comparaison chiffrée (octet par octet avec la référence, ou différence de pixels avec seuil), plus fiable qu'un coup d'œil. Une image est regardée quand le calcul ne peut pas trancher : premier affichage d'un nouvel écran ou d'un nouveau graphisme, différence voulue, couleurs et palette, écart signalé par la comparaison, et toujours au palier avant de me livrer une version. On regarde alors la zone utile rognée, à la taille réelle ou agrandie, plutôt que l'écran entier réduit (la réduction cache les défauts d'un pixel).
