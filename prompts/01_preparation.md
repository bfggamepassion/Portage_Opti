# Prompt 1 : préparation

Rôle : tu prépares le portage d'un jeu de [machine d'origine] ([processeur(s)]) vers [machine cible]. La logique du jeu sera gardée telle quelle ; l'affichage, le son et les entrées seront refaits avec les moyens de la machine cible. Ce travail doit te servir à toi, pendant tout le portage et à chaque reprise de session.

Fichier(s) fourni(s) : [nom(s)]. Ce peut être une image disque, une cassette, une cartouche, une ROM, un instantané mémoire, un ensemble de ROMs d'arcade, etc.

## 1. Extraire le programme

Identifie le format et ce qu'il contient : chargeur, protection, compression, blocs chargés en cours de partie, banques de cartouche, processeurs multiples (ex. processeur son séparé en arcade).

Écris un outil qui produit, depuis le fichier d'origine, l'image de référence : la mémoire au moment où le jeu démarre, avec les registres. Il en faut une par bloc chargé plus tard, par banque et par processeur. Note leurs sommes de contrôle (MD5).

Le conteneur lui-même (chargeur, protection, compression) est décrit brièvement mais pas reconstruit.

## 2. Faire tourner l'original

Un simulateur ou un émulateur pilotable par script qui lance l'image de référence avec des touches scriptées. Il doit permettre de :
- sauter à un niveau ;
- relever la mémoire à chaque tour de jeu ;
- noter les adresses exécutées.

Prépare dès maintenant l'outil de comparaison qui servira pendant tout le portage : même partie scriptée sur l'original et sur le portage, mémoire du jeu comparée tour par tour. Il enregistre une fois pour toutes les traces de l'original par scénario (voir « Aller vite »), et le simulateur sait sauvegarder et recharger un état.

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

Les variables utiles au portage : niveau ou section, joueur (position, état), liste des objets ou ennemis (format d'une entrée), score, vies, touches, et toute variable lue par les routines de l'étape 4.

### Règles

Rien n'est noté comme sûr sans vérification, en simulation ou par lecture du code appelant. Les hypothèses sont marquées comme telles.

Tiens à jour un fichier de reprise : outils et comment les lancer, état du travail, pièges rencontrés, prochaine action exacte.

## 6. Vérification des livrables

Le listing doit se réassembler en une ROM identique octet pour octet à l'original (même MD5). Fournis le script de reconstruction (assembleur installé si besoin, constantes pour tous les noms de RAM et de registres) et lance-le : un listing qui ne redonne pas la ROM d'origine n'est pas livré. Relance ce test après chaque modification du fichier de noms ou du désassembleur.

Chaque livrable est vérifié par un test automatique qui passe, et ce test est noté dans le fichier de reprise avec son résultat.

## 7. Ne rien laisser en suspens

Tout ce qui peut se faire avec les outils disponibles est fait avant de rendre la main : installer un outil manquant, simuler une deuxième machine (câble, deuxième joueur), atteindre chaque niveau en jouant plutôt qu'en le forçant (une fois, en gardant une sauvegarde d'état par niveau pour la suite), trancher une hypothèse qu'une trace ou une lecture du code permet de vérifier.

Ne restent en suspens que les décisions qui me reviennent (machine cible, choix de jeu) ou ce qui est réellement impossible. Pour chacune, le fichier de reprise donne la raison précise.

## Livrables

- l'outil d'extraction et les images de référence ;
- le simulateur et l'outil de comparaison ;
- le listing et le fichier de noms ;
- le document « frontière du portage » avec la carte de la mémoire ;
- le fichier de reprise ;
- une rom / disque etc etc … recompilé à l'identique de ceux / celle que je t'ai fournit.

## Aller vite sans perdre en fiabilité

- **Réutiliser avant d'écrire** : les kits et outils de `Portage_Opti` (skill `portage-retro`) et ceux déjà dans le dépôt. N'écrire un outil que s'il n'existe pas.
- **La référence de l'original se calcule une seule fois** : ses traces (mémoire par tour, écrans, écritures son) sont enregistrées par scénario avec le MD5 de l'image et du scénario. Les comparaisons ne refont tourner que la version modifiée ; la référence n'est recalculée que si l'image ou le scénario change.
- **Sauvegardes d'état** : pour atteindre un niveau ou une scène, recharger une sauvegarde au lieu de rejouer la partie depuis le début. Chaque niveau est atteint une fois en jouant, puis sa sauvegarde sert à tous les tests suivants.
- **Construire et tester dans un dossier local**, hors du dossier synchronisé (Google Drive, OneDrive) : plus rapide et sans fichiers corrompus.
- **Tests longs en tâche de fond**, avec leur progression ; travailler pendant ce temps, jamais d'attente active. Les tests indépendants se lancent en parallèle.
- **Ne pas relire ce qui est connu** : le fichier de reprise, le fichier de noms et la carte de la mémoire font foi. Chercher une adresse ou une routine par une recherche ciblée, pas en relisant tout le listing.
- **Limiter chaque piste** : après deux essais sans résultat, noter la piste et ce qui a été essayé dans le fichier de reprise, puis passer à une autre approche ou me poser la question si le choix me revient.
- **Émulateur réel aux paliers seulement**, une fenêtre à la fois ; entre deux paliers, le simulateur suffit.

NE SOIT PAS VERBEUX !! EXPLIQUE MOI CE QUE TU AS FAIT A LA TOUTE FIN.
