# Comment ces jeux C64 arrivent à être si fluides — expliqué simplement

Ce document raconte, sans jargon (ou presque), les astuces trouvées en ouvrant les disquettes de
**Galencia**, **Zeta Wing** et **Sam's Journey**. La version technique, avec le code et les adresses, est
dans [`TECHNIQUES_OPTIMISATION_C64.md`](skills/c64-optimisation/references/TECHNIQUES_OPTIMISATION_C64.md).

| Jeu | Genre | Ce qu'il a de remarquable |
|---|---|---|
| **Galencia** | tir façon Galaga | 31 vaisseaux à l'écran sur une machine qui n'en gère que 8 |
| **Zeta Wing** | tir à défilement vertical | un décor qui défile sans un seul à-coup |
| **Sam's Journey** | plates-formes | un défilement dans toutes les directions, rapide, en couleurs |

Pour les étudier, j'ai fait tourner chaque jeu dans un émulateur en enregistrant **chaque instruction
exécutée et l'instant où elle l'est**. Les durées citées plus bas sont donc mesurées, pas estimées.

---

## Le problème de départ : le C64 a très peu de temps

L'écran est redessiné 50 fois par seconde. Entre deux images, le processeur a environ **19 600 « petits
pas »** (des *cycles*, un millionième de seconde chacun). Et la puce vidéo lui en reprend un millier au
passage pour ses propres besoins.

Pour te donner une idée :
- recopier **un seul octet** d'un endroit à un autre coûte 8 à 13 pas ;
- l'écran, c'est **1 000 cases** de dessin, plus **1 000 cases** de couleur ;
- donc faire glisser tout l'écran d'un cran coûte environ **18 000 pas** : toute l'image y passe, et il
  ne reste rien pour le jeu, les ennemis ou la musique.

Conclusion : un jeu fluide ne peut **pas** tout refaire à chaque image. Toutes les astuces qui suivent
servent à en faire le moins possible, ou à étaler le travail.

---

## 1. Couper un gros travail en tranches

C'est l'idée la plus rentable des trois jeux.

### Zeta Wing : un défilement en 8 petits travaux
Le décor descend d'un pixel par image. Tous les 8 pixels, il faut décaler tout l'écran d'une case. Au
lieu de le faire d'un coup (18 000 pas), Zeta Wing **prépare le prochain écran en cachette pendant les 8
images** qui précèdent :

| Image | Ce qui est fait |
|---|---|
| 1 à 6 | recopier un sixième de l'écran (4 rangées) sur l'écran caché, une case plus bas |
| 7 | dessiner la nouvelle rangée qui arrive en haut |
| 8 | montrer l'écran caché, et déplacer les couleurs |

Résultat : jamais plus de **2 700 pas** par image, au lieu de 18 000 d'un seul coup.

*Image : un déménagement. Tout porter en un voyage est impossible ; un carton par jour pendant une
semaine, personne ne le remarque.*

### Sam's Journey : même idée, en plus difficile
Sam court vite : le décor avance de 3 pixels par image, dans n'importe quelle direction. Le travail est
réparti sur 3 images : l'écran caché d'abord, les couleurs ensuite. J'ai mesuré jusqu'à 9 800 pas de
défilement dans une image, la moitié du temps disponible, et le jeu tient quand même ses 50 images par
seconde.

---

## 2. Deux écrans : on dessine sur celui qu'on ne voit pas

Zeta Wing et Sam's Journey gardent **deux écrans en mémoire**. On en montre un, on prépare l'autre, puis
on dit à la puce vidéo « montre l'autre ». Ce changement coûte **une seule écriture**.

*Image : deux tableaux noirs. Le prof écrit sur celui du fond pendant que la classe regarde celui de
devant, puis il les échange d'un coup.*

Mais il y a un piège propre au C64 : **les couleurs, elles, n'existent qu'en un seul exemplaire.** Pas
de deuxième tableau pour elles. D'où les deux astuces suivantes.

---

## 3. Les couleurs : tricher sur le dessin, ou courir devant le pinceau

### Zeta Wing triche sur le dessin
Tout le décor est fait de **pavés de 3 cases de large sur 2 de haut, d'une seule couleur chacun**. Du
coup :
- quand on connaît la couleur d'une case, on connaît celle de ses deux voisines : on lit une fois, on
  écrit trois fois ;
- quand le décor descend d'une case, **une rangée sur deux garde sa couleur** : il n'y a que la moitié du
  travail à faire.

Mesuré : **2 680 pas** pour toutes les couleurs de l'écran, au lieu d'environ 8 400. Trois fois moins.

*Image : repeindre un carrelage. Si les carreaux sont grands et unis, un coup de rouleau par carreau
suffit ; s'ils sont minuscules et tous différents, c'est un travail de fourmi.*

C'est un choix de graphiste autant que de programmeur : le décor a été dessiné **pour** que le moteur
aille vite.

### Sam's Journey court devant le pinceau
Sam's Journey veut des couleurs libres, case par case. Pas de raccourci. Alors il joue sur le moment.

L'écran du téléviseur est peint de haut en bas par un faisceau, 50 fois par seconde. Si on change les
couleurs **juste avant** le passage du faisceau, personne ne voit l'ancien état. Le jeu fait donc :
1. le haut de l'écran pendant que le faisceau est encore tout en bas (dans le panneau du score) ;
2. le bas de l'écran pendant que le faisceau redescend sur le haut, déjà prêt.

Le programme va plus vite que le faisceau et garde toujours de l'avance.

*Image : un peintre qui refait un mur pendant qu'un projecteur le balaie de haut en bas. Tant qu'il
peint en avance sur la tache de lumière, le public ne voit que de la peinture fraîche, jamais le
chantier.*

---

## 4. Plus de 8 vaisseaux avec seulement 8 sprites

Le C64 sait afficher **8 sprites** (des images qui bougent librement). Galencia en montre 31, Zeta Wing
24.

L'astuce s'appelle le *multiplexage*. Le faisceau dessine de haut en bas : dès qu'un sprite a été
dessiné **en haut**, il ne sert plus à rien pour cette image. On le **reprogramme aussitôt** (nouvelle
position, nouvelle forme, nouvelle couleur) pour qu'il réapparaisse plus bas. Un même sprite sert
ainsi 3 ou 4 fois par image.

*Image : huit acteurs pour une pièce de trente rôles. Dès qu'un acteur sort de scène côté jardin, il
change de costume en coulisse et rentre côté cour dans un autre rôle.*

Cela demande trois choses, et chaque jeu a ses trouvailles.

### Trier les vaisseaux de haut en bas, très vite
Pour savoir dans quel ordre réutiliser les sprites, il faut les trier par hauteur. Trier 24 objets à
chaque image, c'est long… sauf si on se souvient de l'ordre de l'image précédente. Les vaisseaux ayant
peu bougé, la liste est **déjà presque triée** : il suffit de corriger deux ou trois inversions.

Mesuré dans Zeta Wing : **414 pas** pour trier 24 sprites.

*Image : remettre en ordre un jeu de cartes où seules deux cartes ont été interverties, plutôt que de le
retrier entièrement.*

### Préparer la liste avant, exécuter pendant
Pendant que le faisceau descend, il faut agir vite et au bon moment. Zeta Wing **prépare tout à
l'avance** : le programme écrit directement, dans le morceau de code qui sera exécuté au moment voulu,
les valeurs à envoyer. Le moment venu, ce code n'a plus rien à calculer ni à chercher : il recopie.

*Image : une liste de courses rédigée dans l'ordre exact des rayons. Au magasin, on ne réfléchit plus,
on remplit le chariot.*

### Viser le milieu du trou
Entre un sprite qui finit et le suivant qui commence, il y a quelques lignes de libre. Sam's Journey
programme le changement **exactement au milieu** de cet intervalle. S'il arrive un peu en retard ou un
peu en avance, ça passe quand même.

---

## 5. Du code qui se modifie lui-même

Sur une machine moderne, c'est interdit. Sur C64, c'est un outil de tous les jours, et les trois jeux
s'en servent.

### La boucle sans compteur
Normalement, pour répéter une action 20 fois, on compte : « 1, fait. 2, fait… ». Compter prend du temps.
Ces jeux écrivent plutôt l'action **20 fois de suite** dans le programme, sans compter.

Mais si aujourd'hui il ne faut la faire que 13 fois ? Galencia et Zeta Wing ont la même parade : ils
vont **poser un panneau « stop » dans le code** après la 13ᵉ copie, lancent le tout, puis retirent le
panneau.

*Image : un couloir de 20 portes à ouvrir une par une. Plutôt que de compter les portes, on pose une
barrière après la 13ᵉ.*

### L'aiguillage posé une fois
Dans Sam's Journey, selon que l'écran glisse à gauche, à droite, en haut ou en diagonale, il faut
appeler une routine différente. Au lieu de se reposer la question à chaque image, le jeu **réécrit
l'adresse de destination** dans l'instruction de saut. Tant que la direction ne change pas, le saut part
tout seul au bon endroit.

*Image : un aiguillage de chemin de fer. On le règle une fois ; ensuite tous les trains passent sans
s'arrêter pour demander leur chemin.*

---

## 6. Le score hors de l'écran (Galencia)

Autour de l'image du C64, il y a un **cadre** de couleur unie où, en principe, rien ne peut s'afficher.
Galencia fait croire à la puce vidéo, à un instant très précis, que l'écran est un peu plus petit qu'il
ne l'est. Résultat : elle « oublie » de refermer le cadre en bas, puis en haut.

Dans ce cadre désormais ouvert, seuls les sprites peuvent s'afficher. Galencia y place donc **le score
en haut** et **les vies en bas**, avec des sprites.

Gain : les 25 rangées de l'écran restent entièrement au jeu, et afficher le score ne demande plus
d'écrire dans l'écran.

*Image : écrire dans la marge d'une feuille, là où l'imprimante n'est pas censée aller.*

Le dégradé métallique des chiffres vient d'une astuce voisine : la couleur des sprites est changée
**toutes les quelques lignes** pendant que le faisceau les dessine.

---

## 7. Un ciel étoilé pour presque rien (Galencia)

Le fond de Galencia est un champ d'étoiles qui défile à trois vitesses. Déplacer des dizaines d'étoiles
une par une coûterait cher. Le jeu y consacre **371 pas** par image, moins de 2 % du temps.

Comment : l'écran du C64 est fait de **caractères**, de petits dessins de 8 × 8 points, comme des
tampons. Si on modifie le dessin d'un tampon, **toutes les cases** qui utilisent ce tampon changent en
même temps.

Galencia remplit l'écran, une fois pour toutes, avec 50 tampons rangés de façon que chaque colonne
forme un long ruban vertical. Ensuite, pour faire descendre une étoile, il suffit d'**éteindre un point
et d'en allumer un autre** dans le dessin des tampons. Le jeu ne déplace que 4 points… et l'écran en
montre des dizaines.

*Image : un papier peint dont le motif est gravé sur un rouleau. On retouche un point sur le rouleau, et
le point apparaît partout sur le mur.*

---

## 8. Être à l'heure, au millionième de seconde

Pour changer quelque chose **au milieu** de l'image (passer du décor au panneau du score, par exemple),
il faut agir à un instant exact. La puce vidéo sait prévenir le processeur quand le faisceau atteint une
ligne donnée : c'est une *interruption*.

Problème : le processeur finit toujours ce qu'il était en train de faire avant de répondre. Il arrive
donc avec un retard **variable**, et la coupure tremble à l'écran.

### Le double réveil (Sam's Journey)
Sam's Journey demande deux interruptions de suite. À la première, le processeur se met à **ne rien faire
du tout**, dans une boucle minuscule. Quand la seconde arrive, il n'a rien à finir : il répond à l'heure
exacte.

*Image : pour être sûr de se lever à 7 h 00 pile, on met un premier réveil à 6 h 58, on s'assoit au bord
du lit, et on attend le second.*

### La bande noire qui cache la couture
Entre le décor et le panneau du bas, Sam's Journey affiche une fine bande noire. Pour l'obtenir, il
demande à la puce vidéo une combinaison de réglages **qui n'existe pas**. Faute de savoir quoi afficher,
elle affiche du noir. C'est exactement ce qu'il fallait pour cacher la ligne où le défilement s'arrête,
qui sinon apparaîtrait déchirée.

### Ne prendre que ce dont on a besoin
À chaque interruption, le processeur doit mettre de côté ce qu'il faisait. Ces jeux ne mettent de côté
que le strict nécessaire, et le rangent à l'endroit le plus rapide d'accès. On gagne une dizaine de pas
à chaque fois, et il y a jusqu'à 20 interruptions par image.

---

## 9. Ne jamais attendre les bras croisés (Sam's Journey)

Quand un jeu a fini son travail pour l'image en cours, il attend la suivante. En général il tourne en
rond sans rien faire.

Sam's Journey, lui, profite de cette attente pour **avancer une tâche de fond** : parcourir la liste des
objets du niveau et réveiller ceux qui approchent de l'écran. À chaque tour de la boucle d'attente, il
regarde un objet de plus.

Quand le jeu est calme, la tâche avance vite. Quand il est chargé, elle avance lentement, et ce n'est
pas grave : rien d'urgent n'en dépend.

*Image : un serveur de restaurant qui plie des serviettes entre deux commandes. Salle vide, il en plie
beaucoup ; en plein coup de feu, presque pas ; mais il n'est jamais inactif.*

---

## 10. Ranger la mémoire et charger sans s'arrêter (Sam's Journey)

Sam's Journey tient sur 4 disquettes, pour une machine de 64 Ko. Il faut donc charger et jeter des
données sans arrêt.

### Deux piles qui se font face
La mémoire libre est gérée comme une étagère qu'on remplit **par les deux bouts** : ce qui sert
longtemps d'un côté, ce qui ne sert qu'à un niveau de l'autre. Pour libérer un niveau, on retire les
derniers objets posés de ce côté-là, et c'est tout : pas de trous à reboucher.

### Un chargeur qui ne bloque rien
Le lecteur de disquettes du C64 est lent, et les chargeurs rapides habituels obligent à éteindre l'écran
et couper la musique. Celui de Sam's Journey est fait autrement : c'est **l'ordinateur qui donne le
rythme**. Il dit « envoie », le lecteur envoie deux bits, et ainsi de suite. Si l'ordinateur est occupé
un instant (par la musique, l'affichage), le lecteur attend simplement.

*Image : une dictée où c'est l'élève qui dit « suivant » quand il a fini d'écrire. Personne ne perd le
fil, même s'il s'arrête pour tailler son crayon.*

### Décompresser pendant qu'on charge
Les fichiers sont compressés. Le jeu les décompresse **au fil de l'arrivée** des octets, sans stocker
d'abord le fichier compressé quelque part. Galencia utilise le même compresseur (Exomizer) autrement :
il garde des morceaux compressés en mémoire et les déballe au moment de passer de l'intro au jeu.

---

## 11. Des tableaux plutôt que des calculs

Le processeur du C64 ne sait ni multiplier ni diviser, et même un décalage prend du temps. Alors on
**calcule à l'avance** et on range les réponses dans des tableaux :

- **le joystick** (Sam's Journey) : un tableau de 32 cases traduit directement l'état brut de la manette
  en directions… et annule au passage les combinaisons impossibles (haut et bas en même temps) ;
- **le mouvement de la formation** (Galencia) : une seule courbe ondulée en mémoire ; pour un mouvement
  deux fois plus petit, on divise par deux, ce qui est la seule division que le processeur fait
  vite ;
- **les objets du jeu** (les trois) : au lieu d'une fiche par ennemi, un tableau par information (toutes
  les positions ensemble, tous les états ensemble…). Le processeur y accède beaucoup plus vite.

*Image : la table de multiplication apprise par cœur. On ne recalcule pas 7 × 8, on se souvient de 56.*

---

## Ce qu'il faut retenir

1. **Mesurer.** Aucun de ces jeux n'est « à fond » : ils gardent entre un tiers et deux tiers de leur
   temps en réserve, pour encaisser les moments chargés.
2. **Étaler** le travail trop gros sur plusieurs images plutôt que chercher à l'accélérer.
3. **Laisser faire la puce vidéo** : deux écrans, tampons redessinés, sprites dans les marges.
4. **Préparer avant, exécuter pendant** : tout ce qui doit tomber au bon instant est calculé à l'avance.
5. **Dessiner pour le moteur** : des pavés unis de 3 × 2 cases ont rendu les couleurs de Zeta Wing trois
   fois moins chères.
6. **Ne rien refaire d'inutile** : repartir du tri de l'image précédente, n'écrire que ce qui a changé.

Pour réutiliser tout cela dans un projet, la skill
[`c64-optimisation`](skills/c64-optimisation/SKILL.md) donne la marche à suivre et renvoie vers le
document technique, section par section.
