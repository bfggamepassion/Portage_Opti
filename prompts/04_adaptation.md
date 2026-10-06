# Prompt 4 : adaptation (trancher dans le gras)

Rôle : tu adaptes le portage d'un jeu de [machine d'origine] vers [machine cible] ([processeur, fréquence], assembleur [assembleur]). Le jeu d'origine est trop gros pour la cible : mémoire, support, mémoire vidéo, temps de calcul, sprites, couleurs ou son dépassent ce que la machine permet. Tu décides ce qu'on garde, compresse, réduit, transforme ou retire, avec des chiffres, puis tu l'appliques. Le travail de préparation (listing, fichier de noms, frontière du portage, outil de comparaison, fichier de reprise) est dans le dépôt : [chemins]. Réutilise-le, ne le refais pas.

## Principe

- Chaque coupe est justifiée par une mesure. Aucune coupe « au feeling », aucun élément gardé « par nostalgie » si le budget ne le permet pas.
- Priorité : la sensation de jeu (vitesses, timings, collisions, physique, difficulté, ordre des ennemis) passe avant le décor, qui passe avant le son, qui passe avant les détails.
- Tout ce qui est retiré ou dégradé est consigné et réversible.
- RIEN n'est coupé, réduit, transformé ou retiré sans en avoir discuté avec moi avant. Les étapes 1 à 4 sont de l'analyse seule : aucun fichier du jeu n'est modifié. L'étape 5 est un arrêt obligatoire.

## 1. Budget de la cible

Tableau chiffré, avec la source de chaque valeur : taille du support et banques, RAM utilisable, mémoire vidéo (tuiles, sprites, palettes), cycles par tour de jeu, sprites au total et par ligne, couleurs, résolution, canaux et puces sonores, entrées, temps de chargement toléré. Marge de sécurité retenue pour chaque ligne (ex. 10 % de temps libre pour les pics).

## 2. Inventaire du jeu d'origine

Mesuré avec les outils du préparateur, pas estimé :
- code par module, routines les plus coûteuses en temps ;
- données de niveaux (taille, redondance) ;
- graphismes : tuiles et sprites uniques, images d'animation par entité, fonds, écrans fixes, police ;
- palettes par écran ;
- sons : musiques, effets, échantillons ;
- contenu annexe : modes, menus, démos, test et service d'arcade, protections ;
- code et données jamais exécutés ni lus (adresses relevées en simulation sur plusieurs parties et niveaux).

Tableau « origine contre budget », avec l'écart pour chaque ligne. Les écarts les plus bloquants fixent l'ordre des coupes.

## 3. Ce qui fait ce jeu

Liste de 5 à 10 éléments sans lesquels ce ne serait plus ce jeu (mécaniques, sensations, identité visuelle, musiques emblématiques, progression). C'est le garde-fou : aucun de ces éléments n'est retiré sans ma validation.

## 4. Triage

Pour chaque élément : coût (octets, tuiles, cycles, sprites par ligne), valeur (gameplay, identité, visibilité), puis une seule décision :
- **GARDER** tel quel ;
- **COMPRESSER** : même contenu stocké plus petit (RLE, LZ, déduplication de tuiles, miroirs, banques) ;
- **RÉDUIRE** : moins d'images d'animation, sprites plus petits, palette réduite, tuiles partagées, musique simplifiée ;
- **TRANSFORMER** : équivalent propre à la cible (fond redessiné pour la grille de tuiles, effet refait avec le matériel de la cible) ;
- **PROCÉDURAL** : calcul à la place de données quand le temps le permet ;
- **DIFFÉRER** : chargement à la demande, par banque ou par niveau ;
- **SUPPRIMER**.

Ordre des coupes, de la moins douloureuse à la plus douloureuse :
1. gaspillage et redondance (code mort, données dupliquées, modes de test) ;
2. compression sans perte ;
3. pertes peu visibles (images d'animation intermédiaires, détails de fond, transitions) ;
4. transformation graphique et sonore ;
5. contenu secondaire (cinématiques, variantes de fonds, variantes d'ennemis) ;
6. suppression de contenu de jeu, en dernier recours.

Chaque décision indique : gain mesuré, impact sur le joueur, réversibilité.

## 5. Discussion avant toute coupe (arrêt obligatoire)

Tu t'arrêtes ici et tu me présentes l'analyse. Tu ne passes à l'étape 6 qu'après mon accord explicite.
- Présente d'abord l'essentiel : les écarts les plus bloquants, ce que le triage permet de récupérer, et ce qui manque encore.
- Pour chaque coupe importante (tout ce qui touche à l'ADN du jeu, au contenu de jeu, ou au ressenti), donne les options possibles avec leur gain mesuré et leur impact sur le joueur, ta recommandation, et la raison. Une coupe à la fois ou par petits groupes, pas une liste de 80 lignes.
- Pose-moi les questions dont les réponses changent le triage (ex. « je garde les 50 niveaux avec des fonds simplifiés, ou 30 niveaux fidèles ? », « musique complète en moins bonne qualité, ou thèmes principaux seulement ? »).
- Les coupes sans impact joueur (code mort, données jamais lues, compression sans perte) sont listées d'un bloc : je valide d'un coup.
- Si le budget reste insuffisant après toutes les coupes raisonnables, dis-le et propose des options (autre support ou mapper, découpage en parties, périmètre réduit) au lieu de livrer un jeu amputé en silence.
- À la fin de la discussion, tu écris les décisions validées dans le journal des décisions. Seules ces décisions sont appliquées.
- Si un élément nouveau apparaît pendant la mise en œuvre et force une coupe non validée, tu t'arrêtes sur cet élément et tu me consultes.

## 6. Mise en œuvre

- Outils hors ligne reproductibles : conversion des graphismes, empaquetage des niveaux, conversion des musiques. Un script unique régénère tout depuis les sources.
- Petites étapes, chacune vérifiée puis committée. Le fichier de noms, la carte de la mémoire et le journal des décisions sont mis à jour dans le même commit.
- Pour tout ce qui est gardé, la logique reste identique à l'original : l'outil de comparaison montre une mémoire du jeu identique, tour par tour, sur des parties scriptées.
- Là où la logique doit changer (niveau retiré, ennemi retiré, règle simplifiée), l'écart est consigné dans une liste d'écarts, et la comparaison est adaptée pour ne signaler que les écarts non listés.
- Si le temps de calcul dépasse le budget : répartir le travail sur plusieurs tours, mettre à jour moins souvent les objets éloignés, simplifier les collisions, sans changer la sensation de jeu. Signaler les astuces risquées et leurs précautions.

## 7. Vérification

- Taille finale par catégorie, pic de temps par tour, maximum de sprites par ligne rencontré, mémoire vidéo utilisée : tout est mesuré, dans la scène la plus chargée.
- Démarrage, chargements, affichage et son vérifiés sur un vrai émulateur de la cible.
- Bilan de fidélité : identique, dégradé, absent, avec l'impact estimé sur le joueur.
- Chaque livrable est vérifié par un test automatique qui passe, noté dans le fichier de reprise avec son résultat.

## Règles

- Rien n'est noté comme sûr sans mesure. Les hypothèses sont marquées comme telles.
- Réutilise l'existant avant d'écrire quelque chose.
- Tout ce qui peut se faire avec les outils disponibles est fait avant de rendre la main. Ne restent en suspens que les décisions qui me reviennent (toute coupe en fait partie) ou ce qui est réellement impossible, avec la raison précise dans le fichier de reprise.
- Tiens à jour le fichier de reprise : mesures, essais abandonnés et pourquoi, prochaine action exacte.

## Livrables

- le budget de la cible et l'inventaire « origine contre budget » ;
- la liste de ce qui fait le jeu ;
- le journal des décisions (élément, décision, coût, gain, impact, réversibilité) et la liste d'écarts ;
- les outils de conversion et le code adapté, avec le script de reconstruction ;
- le bilan de fidélité ;
- le fichier de reprise ;
- une ROM / un disque etc. fonctionnel pour la cible.

NE SOIT PAS VERBEUX !! EXPLIQUE MOI CE QUE TU AS FAIT A LA TOUTE FIN.
