# Prompt 1 : préparation

Rôle : tu prépares le portage d'un jeu de [machine d'origine] ([processeur(s)]) vers [machine cible]. La logique du jeu sera gardée telle quelle ; l'affichage, le son et les entrées seront refaits avec les moyens de la machine cible. Ce travail doit te servir à toi, pendant tout le portage et à chaque reprise de session.

Fichier(s) fourni(s) : [nom(s)]. Ce peut être une image disque, une cassette, une cartouche, une ROM, un instantané mémoire, un ensemble de ROMs d'arcade, etc.

## 1. Extraire le programme

Identifie le format et ce qu'il contient : chargeur, protection, compression, blocs chargés en cours de partie, banques de cartouche, processeurs multiples (ex. processeur son séparé en arcade).

Écris un outil qui produit, depuis le fichier d'origine, l'image de référence : la mémoire au moment où le jeu démarre, avec les registres. Il en faut une par bloc chargé plus tard, par banque et par processeur. Note leurs sommes de contrôle (MD5).

Le conteneur lui-même (chargeur, protection, compression) n'est ni reconstruit ni décrit : l'outil d'extraction en tient lieu.

## 2. Faire tourner l'original

Un simulateur ou un émulateur pilotable par script qui lance l'image de référence avec des touches scriptées. Il doit permettre de :
- sauter à un niveau ;
- relever la mémoire à chaque tour de jeu ;
- noter les adresses exécutées.

Prépare dès maintenant l'outil de comparaison qui servira pendant tout le portage : même partie scriptée sur l'original et sur le portage, mémoire du jeu comparée tour par tour. Il enregistre une fois pour toutes les traces de l'original par scénario (voir « Aller vite »), et le simulateur sait sauvegarder et recharger un état. En cas d'écart, il donne seul le diagnostic : premier tour différent, adresses en cause, instruction qui les a écrites de chaque côté, dernières routines appelées.

## 3. Listing et noms

Un listing désassemblé régénérable. La séparation code / données vient des adresses exécutées dans plusieurs parties et plusieurs niveaux, complétée par un désassemblage depuis les points d'entrée (démarrage, interruptions, tables de sauts). Les zones incertaines sont signalées.

Un seul fichier de noms (adresse, nom, commentaire en une ligne), lu par le désassembleur. Au départ, seulement ce qui est sûr.

## 4. La frontière du portage (le plus important)

Liste, avec adresses et appelants, tout ce qui dépend de la machine d'origine :
- écriture à l'écran (sprites, décor, textes, score) et effacement, ou accès à la puce graphique ;
- fabrication des graphismes en mémoire (décompression, pré-décalages, miroirs) ;
- lecture du clavier, du joystick, de la manette ;
- son ;
- interruptions, attente de l'image, cadence de la boucle principale (50 ou 60 Hz, nombre de trames par tour) ;
- chargements et changements de banques.

Pour chacune, indique ses effets en dehors de l'affichage (variables, tampons, pile), qu'il faudra garder. Note aussi les zones de mémoire que la logique ne lit jamais (vérifié en simulation) : c'est de la place récupérable.

## 5. Carte de la mémoire, minimale

Les variables utiles au portage (niveau ou section, joueur, objets ou ennemis, score, vies, touches, et toute variable lue par les routines de l'étape 4) vont dans le fichier de noms. La carte ne garde que ce qu'il ne peut pas dire : format des tables et d'une entrée d'objet, zones libres, profondeur de la pile.

### Règles

Rien n'est noté comme sûr sans vérification, en simulation ou par lecture du code appelant. Les hypothèses sont marquées comme telles.

Tiens à jour le fichier de reprise (format dans « Aller vite »).

## 6. Vérification des livrables

Le listing doit se réassembler en une ROM identique octet pour octet à l'original (même MD5). Fournis le script de reconstruction (assembleur installé si besoin, constantes pour tous les noms de RAM et de registres) et lance-le : un listing qui ne redonne pas la ROM d'origine n'est pas livré. Relance ce test après chaque modification du fichier de noms ou du désassembleur.

Chaque livrable est vérifié par un test automatique qui passe, lancé par `check.sh` : le fichier de reprise cite la commande, pas les résultats.

## 7. Ne rien laisser en suspens

Tout ce qui peut se faire avec les outils disponibles est fait avant de rendre la main : installer un outil manquant, simuler une deuxième machine (câble, deuxième joueur), une sauvegarde d'état par niveau (voir « Sauvegardes d'état »), trancher une hypothèse qu'une trace ou une lecture du code permet de vérifier.

Ne restent en suspens que les décisions qui me reviennent (machine cible, choix de jeu) ou ce qui est réellement impossible. Pour chacune, le fichier de reprise donne la raison précise.

Définition de fini : chaque tâche est classée **obligatoire** (le portage en a besoin : extraction, simulateur, comparaison, listing réassemblé, frontière, carte mémoire, reprise) ou **souhaitable** (le reste : deuxième machine, câble, modes rares, finitions de noms…). Les obligatoires sont toutes faites ; les souhaitables seulement si elles coûtent peu, sinon elles sont listées dans le compte rendu final avec leur intérêt et leur coût estimé.

## Livrables

- l'outil d'extraction et les images de référence ;
- le simulateur et l'outil de comparaison ;
- le listing, le fichier de noms et le script qui les réassemble en une ROM / un disque identique à l'original (§6) ;
- le document « frontière du portage » avec la carte de la mémoire ;
- le fichier de reprise.

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

Pas de texte entre deux étapes. Un compte rendu court et simple à chaque palier ou point d'arrêt, et un dernier à la fin : ce qui a été fait, ce qui est mesuré ou seulement estimé, ce qui reste.
