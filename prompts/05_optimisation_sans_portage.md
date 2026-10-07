# Prompt 5 : optimisation sans portage

Rôle : tu optimises le jeu [nom] sur [machine] ([processeur, fréquence], assembleur [assembleur]), à partir du fichier fourni : [nom du fichier]. Ce peut être une image disque, une cassette, une cartouche, une ROM, un instantané mémoire ou un ensemble de ROMs d'arcade. Le jeu reste sur la même machine. On garde sa logique et on réécrit tout ou partie de son affichage, de son son et de sa gestion du temps pour qu'il aille plus vite.

## Objectif

- **Priorité 1** : tenir la cadence d'origine du jeu dans le pire cas, c'est-à-dire la scène la plus chargée de chaque niveau. La cadence d'origine n'est pas donnée d'avance : elle est mesurée à l'étape 5, niveau par niveau, avec le simulateur vérifié (étape 2). Si elle varie selon la scène, me présenter les mesures et me faire choisir la valeur retenue.
- **Priorité 2** : employer le temps gagné à [plus d'images par seconde à vitesse de jeu égale / pas plus petits / plus d'objets / autre]. Ne jamais accélérer le jeu lui-même, sauf demande explicite.

Budget par tour = nombre de trames par tour mesuré × durée d'une trame, dans l'unité réelle de la machine ([NOPs, cycles, T-states]). La logique, l'affichage, le son et l'attente se partagent ce budget.

Machine visée : [modèle exact, ex. CPC 6128]. Mémoire en plus disponible : [ex. 64 Ko de banques]. Contraintes matérielles : [ex. mémoire vidéo, banques, accès vidéo limités, sprites par ligne].

Décisions qui me reviennent (à me poser au début, puis à chaque fois qu'une mesure les remet en cause) : vitesse du jeu, précision de la caméra (arrondis acceptés ou non), taille de la zone de jeu, différences visuelles ou sonores tolérées.

## Règles permanentes

- **La logique ne change pas.** La mémoire du jeu est comparée à l'original tour par tour, sur des parties aux touches scriptées et au hasard rendu identique. Toute différence bloque, sauf pour les variables qui dépendent du temps (compteurs d'interruptions, état du lecteur de sons, variables d'affichage) : elles sont exclues une par une, dans la configuration de l'outil de comparaison, avec la raison de chaque exclusion en commentaire.
- **Le rendu ne change pas, sauf amélioration voulue.** Les écrans sont comparés octet par octet avec une version de référence à cadence fixe. Une amélioration voulue (images intermédiaires, par exemple) se désactive par une option pour pouvoir refaire cette comparaison.
- **Le son ne change pas.** Les écritures dans la puce sonore sont comparées à la référence. Si une optimisation saute des écritures, prouver au simulateur que chacune aurait réécrit la valeur déjà présente.
- **Rien sans mesure.** Une estimation est marquée « estimation », puis remplacée par la mesure. Une optimisation sans gain mesurable est retirée. Une mesure faite avec un autre scénario ou un autre comptage que la référence n'est pas comparable : refaire la référence dans les mêmes conditions.
- Chaque changement indique son coût en mémoire : nombre d'octets et emplacement. La carte des zones libres est tenue à jour.
- Décisions d'architecture validées par moi avant d'être codées. Si une décision validée doit changer, demander de nouveau avant de changer de voie.
- Commit et push réguliers sur [branche]. Un commit = un changement vérifié (logique identique, rendu identique ou différence voulue).
- Fichier de reprise tenu à jour en continu (format dans « Aller vite ») : il doit suffire pour reprendre après une coupure de session. Mesures et essais abandonnés vont dans le journal qu'il cite.

## Étape 1 : extraire

- Identifier le format et son contenu : chargeur, protection, compression, blocs chargés en cours de partie, banques, programmes multiples (ex. une partie 1 et une partie 2), processeurs multiples.
- Écrire l'outil qui produit, depuis le fichier d'origine, une image de référence par programme, bloc, banque et processeur : la mémoire au démarrage du jeu, avec les registres et une somme de contrôle (MD5).
- Ne pas reconstruire ni décrire le conteneur : l'outil d'extraction en tient lieu. Exception : les parties qu'il faudra modifier pour charger le nouveau code (menu, chargeur), repérées dès maintenant et notées dans la carte de la mémoire avec leurs limites de place.

## Étape 2 : simulateur et outils de contrôle

- Un simulateur pilotable par script : touches scriptées, hasard rendu identique, saut à un niveau, sauvegarde et reprise d'état, adresses exécutées, mémoire relevée à chaque tour.
- Avant toute mesure, vérifier le simulateur contre la vraie machine : un test qui contrôle la durée d'une trentaine d'instructions (dont les copies de blocs, les empilements, les entrées-sorties, les accès 16 bits en mémoire, les sauts pris et non pris) dans l'unité réelle de la machine, le nombre d'interruptions par trame et la durée d'une trame. Ce test reste dans le dépôt.
- Vérifier que les parties scriptées jouent vraiment : identifier le mode de commande que le jeu lit (clavier, manette, touches redéfinies) et contrôler que le personnage bouge.
- Préparer les outils suivants **au moment où ils servent**, jamais après : chaque outil existe et est testé avant le premier changement qui en a besoin (la comparaison des écritures son avant de toucher au son, celle des écrans avant de toucher au rendu…). Ceux qu'exige l'étape 5 (simulateur vérifié, profileur, compteur d'images, sauvegardes de scènes chargées) se font en premier :
  - la comparaison de logique tour par tour (original contre version modifiée), avec des parties au hasard reproductibles par une graine en plus du scénario fixe ; les traces de l'original sont calculées une fois et gardées (voir « Aller vite ») ; en cas d'écart, elle donne seule le diagnostic : premier tour différent, adresses en cause, instruction qui les a écrites de chaque côté, dernières routines appelées ;
  - la comparaison d'écrans octet par octet ;
  - la comparaison des écritures dans la puce sonore ;
  - la mesure de couverture : part des instructions du jeu exécutées par l'ensemble des essais, et liste des zones jamais exécutées ;
  - le profileur : temps par routine et par grande partie, en % du budget ;
  - le compteur d'images : intervalles entre deux images affichées, tours par seconde, nombre de tours qui n'affichent qu'une image.
- Ces outils doivent accepter chaque programme du jeu (partie 1, partie 2…) dès le départ.
- Préparer un jeu de sauvegardes de parties : les scènes les plus chargées de chaque niveau et de chaque programme. C'est là que se mesure le pire cas.

## Étape 3 : source réassemblable

- Produire un source qui, réassemblé, redonne exactement les binaires d'origine (vérifié par comparaison). La séparation code/données vient des adresses exécutées dans plusieurs parties et niveaux, complétée par un désassemblage depuis les points d'entrée. Les zones incertaines sont signalées.
- Un fichier de noms unique (adresse, nom, commentaire), sans conflit entre programmes.
- Avant de déplacer du code, recenser :
  - les pointeurs cachés dans les données, par comparaison entre deux assemblages à adresses différentes ET par un balayage statique de tous les mots de données dont la valeur tombe dans une zone de code ou de données déplaçable (le contrôle par exécution ne voit que le code exécuté) ;
  - le code resté en octets bruts qui contient des adresses ;
  - le code qui se modifie lui-même, y compris les opérandes écrits par une autre routine ;
  - les adresses écrites par le chargeur ou le menu (options de triche, redéfinition des touches) ;
  - les tables qui doivent rester à une adresse fixe et les segments pleins à l'octet.
- Vérifier en déplaçant tout le code et en contrôlant que la logique reste identique. Donner la couverture atteinte par ce contrôle. Ce contrôle complet se refait aux paliers ; entre deux, l'assemblage identique à l'original suffit.

## Étape 4 : frontière et carte de la mémoire (pour chaque programme)

- Lister, avec adresses et appelants, tout ce qui touche à l'affichage (décor, sprites, textes, score, effacement, bascule d'écran), à la fabrication des graphismes (miroirs, décalages), aux entrées, au son (avec sa cadence d'appel), aux interruptions, à l'attente de l'image, à la cadence de la boucle principale et aux changements de banques.
- Pour chacune : ses effets hors affichage (variables, tampons, pile, valeurs de registres en sortie), qu'il faudra garder.
- Repérer ce que la logique lit sur l'écran ou dans les images (collisions, hauteurs d'image modifiées en cours de tour…).
- Repérer les variables d'affichage que la logique lit (numéro de l'écran caché, compteur d'images, compteur d'interruptions) : elles servent souvent de « un tour sur deux » ou de hasard, et changent de sens dès que l'affichage est découplé.
- Recenser tout ce que le jeu écrit directement à l'écran dans la zone de jeu (textes, compteurs, effets), sur un écran ou sur les deux : si les dessins sont plus tard notés puis rendus, ces écritures passent dans le mauvais ordre.
- Carte de la mémoire (les variables utiles vont dans le fichier de noms) : zones jamais lues ni écrites par le jeu (vérifiées sur de longues parties qui atteignent bien le jeu, démarrage compris : tables construites à l'initialisation), zones remises à zéro par le chargeur, zones non chargées qui gardent des restes du fichier, profondeur maximale de la pile.
- Comparer les programmes entre eux. Si deux programmes partagent le même moteur, le noter avec ses différences (paramètres, tables, fenêtre de jeu, modes rares). Pour chaque mode rare, dire comment l'atteindre ou le forcer en simulation.

## Étape 5 : mesurer, puis s'arrêter

- Cadence réelle de l'original : tours par seconde et trames par tour, par niveau, moyenne et pire cas.
- Coût de chaque grande partie en % du budget : logique, décor, défilement, dessin des sprites, préparation des sprites, son, clavier, attente. Moyenne et pire cas, pour chaque programme.
- Plafond utile : de combien le jeu déplace la caméra et les objets par tour (en points, en octets, en lignes), dans quelles directions, et quels pas le matériel sait décaler sans redessiner. En déduire le nombre d'images différentes qu'on peut montrer par seconde. Au-delà, on montrerait deux fois la même image.
- **Point d'arrêt** : me présenter le tableau de départ et le plafond calculé, et attendre ma décision de continuer, avec quel objectif.

## Étape 6 : architecture (me faire valider)

- Pour les deux ou trois plus gros postes, chercher d'abord le travail à supprimer plutôt qu'à accélérer :
  - ne pas redessiner ce qui n'a pas changé ;
  - préparer hors ligne ou une seule fois (tables, copies retournées, graphismes précompilés) ;
  - se servir du matériel (défilement, double écran, découpe d'écran, mémoire en plus) ;
  - déplacer le moteur dans une banque libre ;
  - découpler l'affichage de la logique (dessins notés puis rendus, cadence fixe, images intermédiaires).
- Pour chaque proposition : gain estimé en % du budget, coût en mémoire, risque, ampleur du travail, effet visuel (ex. « caméra par pas de 8 lignes »), et ce qu'elle rapporte au regard du plafond de l'étape 5. Me les présenter, puis attendre mon choix.
- Si l'affichage est découplé de la logique, traiter dès la conception : les écritures directes à l'écran recensées à l'étape 4, les dessins demandés en cours de tour alors qu'une image attend encore d'être montrée, et les variables d'affichage lues par la logique.

## Étape 7 : micro-optimisation

- Seulement sur les routines les plus chaudes, en appliquant [skill ou liste d'astuces de la machine].
- Signaler chaque astuce risquée et sa précaution :
  - pile détournée : interruptions coupées, durée maximale sans interruption, pile valide à chaque réactivation ;
  - code qui se modifie : banques, interruptions, adresses calculées depuis les étiquettes et jamais en dur ;
  - tables alignées : passage de page ;
  - tampons et caches : débordement et calculs sur 16 bits.
- Garder l'ancienne routine derrière une option d'assemblage tant que la nouvelle n'a pas été comparée octet par octet.

## Étape 8 : vérifier chaque changement

Deux niveaux, pour ne pas payer le contrôle complet à chaque changement :

- **Contrôle rapide, à chaque changement (moins de 2 minutes)** : coût avant/après de la routine modifiée, mesuré sur une sauvegarde de scène chargée qui l'exécute ; logique, rendu et son identiques sur une seule courte partie (scénario fixe) qui passe par ce code ; puis commit. Si un écart apparaît, s'arrêter et le corriger avant d'aller plus loin.
- **Contrôle complet, aux paliers seulement** (fin d'un chantier, avant de me livrer un support de test) : coût avant/après en % du budget (moyenne et pire cas), logique identique sur le scénario fixe et sur plusieurs parties au hasard, rendu identique (ou différence voulue vérifiée sur captures), son identique, couverture des essais indiquée, longue partie sans plantage (mort, fin de partie, retour au menu, changement de niveau, modes rares).
- Un test de plus de 2 minutes tourne en tâche de fond et affiche sa progression ; on continue à travailler pendant ce temps.
- À chaque palier, produire le support de test (disquette, ROM, cassette) et me le faire essayer sur émulateur ou machine réelle : le simulateur ne voit pas tout (chargement, menu, ressenti manette en main).

## Étape 9 : employer le temps gagné (si demandé)

- Exemple : images intermédiaires à mi-chemin, affichées à heures fixes, et sautées proprement quand le temps manque.
- Mesures : images par seconde, régularité des intervalles, nombre de tours à une seule image, vitesse du jeu (tours par seconde) strictement égale à l'original. La régularité compte autant que la moyenne.

## Étape 10 : la logique en dernier

- Seulement s'il manque quelques %. D'abord supprimer le travail resté pour l'ancien affichage, puis accélérer les routines lourdes, sous contrôle de la comparaison avec l'original.
- Ne pas changer la cadence d'une routine dont le résultat en dépend (son, compteurs), sans compensation.

## Comptes rendus

À chaque palier ou point d'arrêt (fin d'une étape ou d'un chantier), et à la fin, en langage simple et court :
- tableau par poste en % du budget, avant/après, en signalant ce qui dépasse ;
- résultat visible (images/s, régularité, vitesse du jeu) ;
- ce qui est mesuré et ce qui n'est qu'estimé ;
- couverture des essais et ce qui n'a pas été testé ;
- questions éventuelles.

Pas de texte entre deux comptes rendus.

## Livrables

- outils d'extraction, de simulation (avec son test de durées), de comparaison (logique, écrans, son), de couverture, de profilage et de comptage d'images ;
- source réassemblable et fichier de noms ;
- document « frontière et mémoire » pour chaque programme ;
- disquette, ROM ou cassette de test à jour ;
- fichier de reprise.

## Aller vite sans perdre en fiabilité

- **Réutiliser avant d'écrire** : les kits et outils de `Portage_Opti` (skill `portage-retro`) et ceux déjà dans le dépôt. N'écrire un outil que s'il n'existe pas.
- **Outils génériques séparés du jeu** : un outil qui ne dépend pas du jeu (processeur, puce vidéo ou son, format de disquette ou de cassette, banc de comparaison) est écrit sans rien de propre au jeu, dans son propre fichier, avec son test. À la fin, me proposer la liste de ceux qui méritent d'entrer dans `Portage_Opti` ; je valide l'ajout.
- **Simulateur rapide** : mesurer sa vitesse dès qu'il tourne (tours de jeu par seconde) et la noter dans le journal. S'il est trop lent pour les contrôles (contrôle rapide de plus de 2 minutes), l'accélérer avant de s'en servir : cœur rapide déjà disponible par pip (ex. simulateur en C de SkoolKit pour le Z80), PyPy, ou vrai émulateur piloté sans fenêtre par script.
- **Rien à installer à la main** : tout outil supplémentaire (paquet, interpréteur, émulateur) est installé par un script du dépôt, sans compilateur ni manipulation de ma part. Si ce n'est pas possible, me proposer une autre solution.
- **La référence de l'original se calcule une seule fois** : ses traces (mémoire par tour, écrans, écritures son) sont enregistrées par scénario avec le MD5 de l'image et du scénario. Les comparaisons ne refont tourner que la version modifiée ; la référence n'est recalculée que si l'image ou le scénario change.
- **Sauvegardes d'état** : pour atteindre un niveau ou une scène, recharger une sauvegarde au lieu de rejouer la partie depuis le début. Chaque sauvegarde est faite une fois et sert à tous les tests suivants. Un niveau peut être forcé (saut direct) au lieu d'être atteint en jouant, à condition d'avoir vérifié sur un niveau que l'état forcé est identique à l'état atteint en jouant ; si ce n'est pas le cas pour un niveau, celui-là est atteint en jouant.
- **Construire et tester dans un dossier local**, hors du dossier synchronisé (Google Drive, OneDrive) : plus rapide et sans fichiers corrompus.
- **Tests longs en tâche de fond**, avec leur progression. Les tests indépendants se lancent en parallèle.
- **Une seule commande de contrôle** : `sh check.sh rapide` et `sh check.sh complet`. Elle enchaîne construction et tests, s'arrête à la première erreur et rend un code d'échec ; c'est elle qu'on lance, toujours la même, notée dans le fichier de reprise. Ne jamais juger un résultat à travers `tail` ou une sortie tronquée.
- **Ne pas relire ce qui est connu** : le fichier de reprise, le fichier de noms et la carte de la mémoire font foi. Chercher une adresse ou une routine par une recherche ciblée, pas en relisant tout le listing.
- **Fichier de reprise court** (une page environ), toujours dans le même ordre : 1. état ; 2. commandes (construction, `check.sh`, lancement) ; 3. prochaine action exacte ; 4. pièges. Le détail (mesures, essais abandonnés et pourquoi, historique) va dans un journal à part qu'il cite.
- **Limiter chaque piste** : après deux essais sans résultat, noter la piste et ce qui a été essayé dans le journal, puis passer à une autre approche, ou me proposer des concessions chiffrées si le choix me revient.
- **Émulateur réel aux paliers seulement**, une fenêtre à la fois ; entre deux paliers, le simulateur suffit.

## Économiser les tokens

- **Sorties courtes** : chaque outil (simulateur, comparaison, profileur, `check.sh`) affiche par défaut un résumé de quelques lignes (ex. « rapide : OK, 12 tests, 48 s », ou le diagnostic d'un écart) et écrit le détail dans un fichier, lu seulement si besoin. Jamais de trace, de vidage mémoire ou de listing complet à l'écran.
- **Lire peu** : le listing, les traces et les fichiers générés se consultent par recherche ciblée ou par plage de lignes, jamais en entier. Le listing est découpé en fichiers inclus par un fichier principal (un par banque ou par module, coupés aux frontières de routines) : il reste lisible et se réassemble toujours à l'identique (même MD5, test relancé après le découpage).
- **Scripts plutôt que commandes à la suite** : toute séquence répétée (construire, tester, mesurer, capturer) devient un script lancé en une fois.
- **Images : comparer par calcul, regarder quand ça compte.** Les écrans se vérifient d'abord par comparaison chiffrée (octet par octet avec la référence, ou différence de pixels avec seuil), plus fiable qu'un coup d'œil. Une image est regardée quand le calcul ne peut pas trancher : premier affichage d'un nouvel écran ou d'un nouveau graphisme, différence voulue, couleurs et palette, écart signalé par la comparaison, et toujours au palier avant de me livrer une version. On regarde alors la zone utile rognée, à la taille réelle ou agrandie, plutôt que l'écran entier réduit (la réduction cache les défauts d'un pixel).
