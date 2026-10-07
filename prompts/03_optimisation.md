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

Tableau par poste, en % du budget, avant/après, avec ce qui dépasse. Le fichier de reprise est tenu à jour : mesures, essais abandonnés et pourquoi, prochaine étape.

NE SOIT PAS VERBEUX !! EXPLIQUE MOI CE QUE TU AS FAIT A LA TOUTE FIN.
