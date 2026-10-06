# Comment ces jeux CPC arrivent à être si rapides — expliqué simplement

Ce document raconte, sans jargon (ou presque), les astuces trouvées en ouvrant les disquettes de
**Pinball Dreams**, **Toki GGP** et **R-Type**. La version technique, avec le code et les adresses, est dans
[`TECHNIQUES_OPTIMISATION_CPC.md`](skills/cpc-optimisation/references/TECHNIQUES_OPTIMISATION_CPC.md).

La section 7 s'appuie sur un autre genre de source : le *CRTC Compendium* de Longshot (`ACCC1.11-EN.pdf`),
un manuel de 296 pages sur la puce vidéo du CPC, résumé dans
[`CRTC_COMPENDIUM.md`](skills/cpc-optimisation/references/CRTC_COMPENDIUM.md).

> **Deux R-Type** : le dépôt contient le bon, **R-Type 128K** d'Easter Egg (2012, signé Fano, TotO et
> Julien dans un fichier caché `WTF.TXT`), et l'ancien `rtypeed.dsk`, le jeu commercial de 1988 (adapté
> du Spectrum, disquette « Cracked and compacted by Nich Campbell »), envoyé par erreur. Je garde quelques
> astuces du second, marquées « R-Type 1988 », parce qu'elles servent aussi pour un portage.

---

## Le problème de départ : le CPC a très peu de temps

L'écran est redessiné 50 fois par seconde. Entre deux images, le processeur (Z80) a environ
**20 000 « petits pas »** (des microsecondes, qu'on appelle des *NOPs* sur CPC). C'est tout.

Pour te donner une idée :
- recopier **un seul octet** avec l'instruction « facile » (`LDIR`) coûte 6 pas ;
- l'écran de jeu fait **12 000 à 16 000 octets** ;
- donc rien que recopier tout l'écran prendrait **plus de 3 images**.

Conclusion : un jeu rapide ne peut **pas** redessiner tout l'écran à chaque image. Toutes les astuces qui
suivent servent à en faire le moins possible.

---

## 1. Faire faire le travail à la puce vidéo plutôt qu'au processeur

Le CPC a une puce vidéo, le **CRTC**, qui lit la mémoire pour fabriquer l'image. On peut lui dire **où
commencer à lire** (registres R12/R13).

### Le double écran (Toki, Pinball Dreams, et ton Roller Ball)
On a deux écrans en mémoire. Pendant qu'on montre l'un, on dessine l'autre en cachette, puis on dit au CRTC
« montre l'autre maintenant ». Changer d'écran = **deux écritures**, quasi gratuit.
*Image : deux tableaux noirs. Le prof écrit sur celui du fond pendant que la classe regarde celui de devant,
puis il les échange d'un coup.*

### Le défilement « gratuit »
Si on dit au CRTC « commence à lire une ligne plus bas », **tout l'écran monte** sans qu'on ait bougé un
seul octet. Il ne reste qu'à dessiner la bande qui apparaît en bas.
*Image : un rouleau de papier peint qu'on fait glisser devant une fenêtre ; on ne repeint que le bout qui
entre dans la fenêtre.*
Avec un écran de 256 pixels de large (comme ton Roller Ball), la mémoire forme même une **boucle** : ce qui
sort en haut revient en bas, sans fin.

### Découper l'écran en morceaux (les « ruptures » de Pinball Dreams)
Pinball Dreams change les réglages du CRTC **au milieu de l'image** : le haut de l'écran montre une zone de
la mémoire, le bas une autre. On peut ainsi faire défiler la table de flipper tout en gardant le score
immobile. C'est comme un écran partagé.
Contrepartie : il faut changer les réglages **au bon moment, à la microseconde près**, et il existe
plusieurs modèles de CRTC qui ne réagissent pas pareil. Pinball Dreams **détecte le modèle** au démarrage
et adapte son code en conséquence.

---

## 2. Changer les couleurs au lieu de redessiner

Sur CPC, l'écran ne stocke pas des couleurs mais des **numéros d'encre** (« encre 1 », « encre 2 »…). On
choisit ensuite quelle couleur réelle correspond à chaque encre.

- **Toki** fait tourner les couleurs de 3 encres toutes les 3 images : l'eau, les lumières ou les objets qui
  brillent semblent bouger alors qu'**aucun pixel n'a été redessiné**. *Comme une guirlande de Noël : les
  ampoules ne bougent pas, seules les couleurs s'allument à tour de rôle.*
- **R-Type 1988** change une encre en cours d'image : le haut de l'écran et le bas n'ont pas les mêmes
  couleurs. On obtient plus de couleurs que les 4 normalement permises en mode 1.
- **R-Type 128K** va plus loin : il change **de mode graphique** en cours d'image. L'aire de jeu est en
  mode 0 (16 couleurs, gros pixels) et le panneau des scores en bas en mode 1 (4 couleurs, pixels fins,
  texte plus net). *Comme une page de BD : une grande case en couleur et un bandeau de texte en dessous.*
- **Pinball Dreams** va jusqu'à changer des couleurs **à chaque ligne** pour faire des dégradés.

---

## 3. Dessiner plus vite ce qu'on doit vraiment dessiner

### Lire les données « en rafale » avec la pile (Toki)
Le Z80 a une « pile », faite pour ranger des adresses de retour. Elle a une particularité : elle lit
**2 octets d'un coup, très vite**. Toki la détourne pour lire les dessins des tuiles du décor à toute
vitesse. Il faut juste couper les interruptions pendant ce temps (sinon le processeur rangerait n'importe quoi
au milieu des données).
*Image : au lieu de prendre les briques une par une sur une étagère, on a un tapis roulant qui les apporte
deux par deux.*

### Parcourir les lignes dans un ordre malin (Toki)
Sur CPC, les 8 lignes d'une tuile ne se suivent pas en mémoire : elles sont espacées de 2 Ko. Passer d'une
ligne à la suivante demande normalement un petit calcul. Toki dessine les lignes dans l'ordre
**0, 1, 3, 2, 6, 7, 5, 4** : avec cet ordre, passer d'une ligne à l'autre ne change qu'**un seul chiffre** de
l'adresse, donc une seule instruction très courte. En plus, il dessine une ligne de gauche à droite et la
suivante de droite à gauche, comme un laboureur qui fait demi-tour au bout du champ au lieu de revenir au
début.
Pour que ça marche, les données de chaque tuile sont **rangées à l'avance dans cet ordre**. Résultat :
environ 40 % de temps gagné par tuile.

### La transparence des sprites par « table de réponses » (Toki)
Pour poser un personnage sur le décor, il faut savoir, pour chaque pixel, s'il est transparent. Au lieu de
calculer, Toki a une **table de 256 réponses toutes prêtes** : on lui donne un octet du personnage, elle
renvoie directement le masque. *Comme une table de multiplication apprise par cœur : on ne recalcule pas
7 × 8, on connaît la réponse.* Bonus : pas besoin de stocker un masque avec chaque sprite, ce qui économise
la moitié de la mémoire des sprites.

### Tout préparer à l'avance (R-Type 1988)
R-Type 1988 prépare au démarrage une table qui donne l'image **miroir** de chaque octet (pour retourner les
sprites sans calcul), et garde son décor dans le format simple du Spectrum (un bit par pixel), converti au
dernier moment avec un minimum d'opérations.

### Des tuiles en miroir (R-Type 128K)
Beaucoup de morceaux de décor existent « à l'endroit » et « à l'envers » (un tuyau qui part à gauche, le même
qui part à droite). R-Type 128K n'en garde **qu'une version** : pour dessiner l'autre, il lit les octets dans
l'autre sens et passe chacun dans une **table toute prête qui échange ses deux pixels**. La mémoire des
graphismes est divisée par deux. *Comme imprimer un tampon à l'envers au lieu d'en graver un deuxième.*

### Ne redessiner que les cases marquées (R-Type 128K, et les autres)
R-Type 128K découpe l'écran en **640 cases** (32 × 20). Chaque case a une petite étiquette : « rien à faire »
ou « à redessiner, de telle façon ». À chaque image, le jeu passe sur les étiquettes, saute les cases
tranquilles, et pour les autres **saute directement à la bonne routine** de dessin (pas de série de tests
« est-ce que c'est ceci ? cela ? »). Quand le décor défile, les grandes zones unies (l'espace noir) ne
changent pas d'une case à l'autre, donc ne sont jamais redessinées.
Il n'utilise **pas** le défilement matériel : un seul écran, et tout le travail est concentré sur les cases
qui bougent vraiment.
*Image : un gardien de musée qui ne repeint que les tableaux étiquetés « abîmé ».*

Les autres jeux font pareil à leur manière : tous retiennent ce qui est déjà affiché et ne redessinent que
ce qui a changé.

---

## 4. Garder un rythme stable

### Compter les tops de l'horloge vidéo
Le CPC envoie **6 « tops »** (interruptions) par image. Les jeux les comptent :
- Toki ne fait son travail lourd (musique, couleurs) qu'**au 6e top**, donc une fois par image ;
- R-Type 1988 change des couleurs aux 4e et 5e tops (bandes de couleur), et se recale au 6e ;
- R-Type 128K a un **carnet de rendez-vous** : une liste de 8 cases, une par top, qui dit quoi faire à ce
  moment-là (changer de mode, de couleurs, jouer la musique…). Pour passer du menu au jeu, il change
  simplement de carnet.

### Un jeu qui ne ralentit pas
R-Type 1988 décide que le jeu avance **toutes les 3 images** (environ 17 fois par seconde), toujours. Même quand
l'écran est chargé d'ennemis, la vitesse ne change pas. C'est mieux qu'un jeu qui tourne parfois vite et
parfois lentement. *Comme un métronome : on joue toujours au même tempo.*

### Du code réglé à la microseconde (Pinball Dreams)
Pour ses effets d'écran découpé, Pinball Dreams a du code dont **chaque instruction est comptée** : il ajoute
des pauses exactes (`NOP`) pour que chaque réglage tombe pile sur la bonne ligne de l'écran.

---

## 5. Prendre toute la machine pour soi

### Éteindre le « système d'exploitation »
Le CPC a un logiciel intégré (le *firmware*) qui gère clavier, disque, écran… Il est pratique mais il prend
de la mémoire et du temps à chaque interruption. Les trois jeux **l'éteignent** et font tout eux-mêmes : ils
récupèrent la mémoire et le temps processeur.

### Lire le clavier en une seule fois
Pinball Dreams lit **les 10 lignes du clavier d'un coup** une fois par image et range le résultat ; ensuite
le jeu regarde simplement ce tableau.

### Utiliser les 128 Ko (Pinball Dreams, Toki)
Le Z80 ne voit que 64 Ko à la fois. Pour utiliser la mémoire en plus, on « bascule » des blocs de 16 Ko. Pinball
Dreams garde de minuscules routines d'aiguillage dans une zone **toujours visible**, qui servent de
passerelles entre les blocs (comme un couloir qui relie des pièces). La musique vit dans un bloc à part et
est appelée une fois par image.

R-Type 128K ajoute deux astuces :
- chaque bloc porte **son propre numéro écrit dans son premier octet** : quand la musique interrompt le jeu,
  elle lit ce numéro pour savoir quel bloc remettre après. *Comme une étiquette sur chaque classeur.*
- les opérations les plus fréquentes (changer de bloc, de mode…) sont des **instructions d'un seul octet**
  (`RST`) : plus court et plus rapide qu'un appel normal.

---

## 6. Le disque et la compression

### Une disquette « maison » (Pinball Dreams)
- Pinball Dreams met **10 secteurs par piste au lieu de 9** : 11 % de place en plus.
- Il **décale la numérotation** des secteurs d'une piste à l'autre : quand la tête passe à la piste
  suivante, le bon secteur arrive juste sous elle, sans attendre un tour complet de disque. Le chargement
  est plus rapide.
- Il pilote **lui-même** le contrôleur de disquette, sans passer par le système.
- Il ajoute de faux fichiers invisibles dans le catalogue pour qu'AMSDOS croie le disque plein et n'écrive
  jamais par-dessus les données.

### Un système de fichiers fait maison (R-Type 128K)
- Le catalogue normal de la disquette ne contient **qu'un seul vrai fichier**, un lanceur de 512 octets. Le
  reste de ce catalogue sert… à **sauvegarder la table des meilleurs scores** !
- Le vrai sommaire du jeu (63 fichiers sur les deux faces) est rangé ailleurs, dans un format à lui : nom,
  face, piste, secteur, taille, et trois petits drapeaux (« compressé », « à lancer »…).
- Le jeu charge ensuite chaque niveau morceau par morceau : le décor en deux blocs de 16 Ko, les sprites
  dans un troisième, le code du niveau, puis décompresse chaque morceau dans son bloc.
- Le programme principal **se décompresse tout seul** : ses premières instructions sont le décompresseur.

### Deux compresseurs selon le besoin
- **Exomizer** : compresse très fort mais décompresse lentement → pour ce qu'on charge une seule fois
  (Pinball Dreams, tous les fichiers `.PCK` de Toki, et presque tous les fichiers de R-Type 128K).
- **ZX7** : compresse un peu moins mais décompresse vite → pour ce qu'on décompresse pendant le jeu
  (Pinball Dreams).
*Comme ranger ses vêtements : sous vide pour la cave (ça prend du temps à ouvrir), plié simplement dans
l'armoire pour ce qu'on porte tous les jours.*

---

## 7. Le piège : il n'y a pas un CPC, il y en a cinq

Amstrad a acheté sa puce vidéo chez plusieurs fabricants, puis l'a refaite lui-même deux fois. Résultat :
**cinq modèles de CRTC** (numérotés de 0 à 4), qu'on trouve au hasard dans les machines. Tant qu'on règle la
puce une fois et qu'on n'y touche plus, ils font tous pareil. Dès qu'on change un réglage **pendant** que
l'image se dessine, chacun a ses manies. *Comme cinq cuisiniers à qui on donne la même recette : le plat est
le même, sauf si on leur crie un changement au milieu de la cuisson.*

Un passionné, Longshot, a passé des années à mesurer ces manies sur de vraies machines et en a tiré un
manuel de 296 pages. La plus grande partie sert aux démos et aux émulateurs. Voici ce qu'un jeu doit en
retenir.

### Changer d'écran : pas n'importe quand
Dire au CRTC « montre l'autre écran » (le double écran du début) a l'air sans risque. En fait, un des cinq
modèles relit cette consigne pendant qu'il dessine les 8 premières lignes de l'image : si on la change à ce
moment-là, le haut de l'image est coupé en deux pendant un instant. Un autre modèle note la consigne un peu
avant la fin de l'image : trop tard, et il a une image de retard.
La parade ne coûte rien : donner la consigne **juste après le top de fin d'image**, quand plus rien n'est
affiché. Les documents techniques disaient « n'importe quand » : c'est corrigé.

### Le top de fin d'image n'a pas la même durée partout
Le signal qui dit « l'image est finie » dure 8 lignes sur certains modèles et 16 sur d'autres. Un jeu qui
se cale sur le **début** du signal marche partout. Un jeu qui se cale sur la **fin** marche sur la machine
de son auteur et clignote sur celle du voisin (c'est arrivé à un jeu de 1985).

### Changer de mode graphique est plus simple qu'on ne croit
Le CPC n'applique un changement de mode qu'**entre deux lignes**, jamais au milieu. Pas besoin de viser à la
microseconde : il suffit d'être sur la bonne ligne. C'est pour ça que l'écran de R-Type 128K (jeu en
16 couleurs, scores en pixels fins) est propre sur toutes les machines. Les **couleurs**, elles, changent
tout de suite, au pixel près : là il faut viser.

### Les 6 tops par image peuvent se décaler
Un jeu peut dire « ne me dérange pas » pendant qu'il fait un travail délicat (lire des dessins avec la
pile, par exemple). Si ça dure peu, le top attend et rien n'est perdu. Si ça dure plus de 32 lignes
d'écran, les tops suivants arrivent **en retard jusqu'à l'image suivante** : tout ce qui était calé dessus
(bandes de couleurs, changement de mode) se retrouve au mauvais endroit. Règle : des moments « ne me
dérange pas » courts.

### Faire défiler de côté, finement
Le défilement gratuit de la section 1 avance par pas de 2 octets, ce qui est saccadé. Le manuel décrit un
réglage qui décale toute l'image d'**un** octet de plus : en combinant les deux, on obtient un défilement
horizontal deux fois plus fin, toujours sans rien recopier. Aucun des jeux étudiés ici ne s'en sert.

### Écran partagé : simple ou compliqué
Couper l'écran en deux grandes zones (le jeu en haut, les scores en bas) peut s'écrire une seule fois pour
les cinq modèles, à condition de suivre quelques règles. Ce qui demande de détecter le modèle et d'écrire
plusieurs versions du code, c'est de changer de zone **à chaque ligne**, comme le fait Pinball Dreams dans
son menu.

### Un tableau des durées
Le manuel donne la durée exacte de chaque instruction du Z80 sur CPC. En recomptant avec ce tableau, une
estimation des documents techniques s'est révélée fausse : poser un octet de sprite à la manière de Toki
coûte 18 pas dans sa boucle, pas 9. Le principe reste bon, mais il faut écrire la boucle « à plat » (sans
revenir en arrière à chaque octet) pour descendre à 10 ou 11.

---

## 8. Et pour ton Roller Ball ?

Ton portage fait tourner le vrai programme MSX sur le CPC et traduit l'écran MSX en écran CPC. C'est malin,
mais aujourd'hui, à chaque image :
- il **recopie** toute la liste des cases de l'écran MSX (environ un quart du temps disponible) ;
- il **compare** les 768 cases une par une pour trouver celles qui ont changé (presque la moitié du temps),
  même quand rien ne bouge ;
- et pour le défilement du plateau, qui aurait demandé de tout redessiner, il a fallu **sauter** directement
  d'une section à l'autre au lieu de faire défiler.

Ce que les jeux étudiés suggèrent, du plus simple au plus ambitieux :
1. **Noter les changements au moment où ils arrivent** (le portage voit déjà passer chaque écriture du jeu
   MSX) au lieu de tout comparer après coup.
2. **Dessiner les cases à la manière de Toki** (pile + ordre de lignes malin) : environ 40 % plus rapide
   par case.
3. **Préparer les sprites déjà décalés** (4 versions) au lieu de les décaler pixel par pixel à chaque
   ligne.
4. **Faire défiler avec la puce vidéo** : le MSX monte le plateau d'une rangée par image, et c'est
   **exactement** ce que le CRTC du CPC sait faire gratuitement. La seule difficulté est le panneau des scores
   à droite, qui doit rester immobile : soit on redessine seulement ses parties qui changent (en gardant la
   disposition du MSX), soit on le place en bas de l'écran dans une zone séparée, comme Pinball Dreams.
   Dans les deux cas on retrouve un vrai défilement fluide au lieu d'un saut.
5. **Ou faire comme R-Type 128K** : un seul écran, des étiquettes « à redessiner » sur les cases, et on ne
   redessine que les cases qui changent vraiment quand le plateau défile. Moins de mémoire, et chaque case
   n'est dessinée qu'une fois au lieu de deux.
6. **Tuiles en miroir** : le plateau de flipper est souvent symétrique (batteurs gauche et droit) ; une seule
   moitié des dessins pourrait suffire.
7. **Vérifier le moment où le portage change d'écran** (section 7) : si la consigne au CRTC n'est pas donnée
   juste après le top de fin d'image, le haut de l'image peut se couper sur certains CPC. À contrôler dans
   le code du portage, que je n'ai pas sous les yeux dans ce dépôt.

Le document technique détaille chaque option avec des estimations chiffrées.

---

## Petit lexique

| Mot | Sens |
|---|---|
| **NOP** | l'unité de temps du CPC : 1 microseconde. Une image = ~20 000 NOPs. |
| **CRTC** | la puce qui fabrique l'image à partir de la mémoire. |
| **Gate Array** | la puce qui gère les couleurs, le mode graphique et les blocs de mémoire. |
| **Interruption** | un « top » envoyé 6 fois par image qui fait sauter le processeur dans une routine choisie. |
| **VSYNC** | le moment où l'image recommence en haut de l'écran. |
| **Double tampon** | deux écrans en mémoire : on montre l'un, on dessine l'autre. |
| **Rupture** | changer les réglages du CRTC en cours d'image pour découper l'écran. |
| **Banque** | un bloc de 16 Ko de mémoire qu'on peut faire apparaître ou disparaître. |
| **Sprite** | un objet mobile dessiné par-dessus le décor (balle, personnage). |
| **Tuile** | un petit carré de décor réutilisable (ici 8 × 8 pixels). |
| **Pile** | une zone mémoire que le processeur sait lire et écrire 2 octets à la fois, très vite. |
| **Code automodifiant** | un programme qui modifie ses propres instructions pour aller plus vite. |
