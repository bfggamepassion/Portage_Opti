# Leçons et pièges

Ce qui a coûté des heures sur une vingtaine de portages et d'optimisations (CPC, C64, ZX Spectrum, MSX,
ColecoVision, Thomson, Master System, Game Boy, Oric, arcade). À lire avant de commencer ; la skill
`portage-retro` en reprend l'essentiel.

## Méthode

- **La logique vient du code d'origine, jamais de l'observation.** Les sensations de jeu (vitesses,
  collisions, physique, IA) ne se reproduisent fidèlement qu'en gardant ou en traduisant le code.
- **Ne jamais émuler l'écran d'origine sur la cible.** Convertir en continu la mémoire écran source
  (octets de 6 pixels Oric, attributs Spectrum, VRAM TMS9918…) laisse le jeu 2 à 4 fois trop lent et garde
  les défauts de la machine source. Refaire l'affichage avec les moyens de la cible : sprites matériels
  pour ce qui bouge, caractères/tuiles ou bitmap pour le décor, dessiné une fois par niveau.
- Si la logique **relit son écran** (collisions), garder l'écran source en RAM comme carte de collisions
  invisible, au même coût que sur la machine d'origine ; ne convertir que le décor quand il change.
- Positions des objets : les lire dans les tables d'objets du jeu plutôt qu'intercepter ses routines de dessin.
- **Les variables d'affichage lues par la logique** (écran caché, compteur d'images ou d'interruptions)
  servent souvent de hasard ou de « un tour sur deux » : elles changent de sens quand l'affichage est découplé.
- Certains jeux écrivent directement à l'écran depuis la logique (texte, flèche, dalle) : les recenser, sinon plantage ou trace dans une seule pièce.
- La **RAM** est la vraie contrainte, pas le disque : un fichier par niveau ou par écran chargé à la demande
  vaut mieux que sacrifier une fonction. Un écran entier peut être chargé directement dans un tampon vidéo, à coût mémoire permanent nul.
- Code compilé naïf (variables 16 bits statiques, bibliothèque d'exécution) : une traduction directe
  instruction par instruction est trop grosse ; décompiler vers une représentation intermédiaire puis générer.
- Quand une optimisation s'enlise après un ou deux essais : **proposer des concessions chiffrées**
  (sprites matériels pour les personnages, moins de couleurs, pas de défilement plus gros) au lieu de s'acharner.
- Ne jamais affirmer une absence à partir d'un relevé filtré ; ne jamais affirmer un comportement sur
  machine réelle quand seul un émulateur a servi.

## Vérification

- Comparaison **tour par tour** de la mémoire du jeu, original contre portage, sur parties scriptées et au
  hasard reproductible. Rendre le hasard identique (registre R du Z80, compteurs) et caler les compteurs d'images.
- Convention à fixer une fois : si le portage lit ses entrées en fin d'image, il reçoit les touches du
  tour k+1 quand l'original reçoit celles du tour k. Ne pas « corriger » ensuite.
- Un simulateur maison ne voit ni le firmware, ni le DOS, ni le chargeur, ni la police copiée depuis la
  ROM : **toute disquette ou cartouche se vérifie dans un vrai émulateur** avant d'être annoncée.
- Tester comme un joueur : appuyer sur la touche que l'écran annonce, lire les textes à l'œil.
- Capturer tôt et en rafale : une séquence écran de démarrage → reset peut durer moins de 5 s.
- Pour localiser une panne de démarrage : variantes qui posent une couleur de bordure et bouclent sur place.
- Mesures non reproductibles d'une exécution d'émulateur à l'autre : faire une seule exécution avec point d'arrêt et vidages mémoire.
- Un outil de test long doit afficher sa progression ; `tail` après un build masque un échec (résultats périmés) : enchaîner build + tests dans un seul script qui s'arrête à la première erreur.

## Chaîne d'outils (Windows)

- **Construire hors de Google Drive / OneDrive** (dossier sous `%LOCALAPPDATA%`) : la synchronisation a
  corrompu des `.tap`/`.dsk` et provoqué des « Permission denied » parasites. Les `build.sh` des kits le font.
- **Heredocs de l'outil Bash (Git Bash)** : un niveau de `\` disparaît, même dans `<<'EOF'` (`b'\\x00'`
  devient `b'\x00'`), et les très longs heredocs sont tronqués. Écrire le code qui contient des `\` avec les outils Write/Edit.
- Chercher les outils déjà installés avant d'en télécharger (voir `INSTALLATION.md`).
- Tout code d'interruption n'utilise jamais les variables temporaires en page zéro (ou registres de travail) du programme principal.
- 64tass : une étiquette globale au milieu d'une routine casse les étiquettes `_locales` qui suivent ; toujours `-C`.
- sjasmplus : une table alignée sur 256 peut coûter 256 octets d'un coup si on ajoute du code avant elle ; ajouter après les tables.

## Amstrad CPC / Caprice32

- Caprice32 (fork ColinPitrat) se lance **depuis son dossier** (sinon « Couldn't open ROM file »), en tâche
  de fond. Lancement automatique : `./cap32.exe '--autocmd=RUN"JEU' 'C:\chemin\jeu.dsk'` — pas de `\"` ni de
  `\n` (il lit `\` comme une touche spéciale et ajoute Entrée lui-même).
- Avec `-a`, ne jamais construire la chaîne par `printf %b` (il mange le `\` de `\(CAP32_DELAY)`).
  `\(CAP32_DELAY)` et `\(CAP32_SCRNSHOT)` injectent de fausses pressions des touches 8 et 9 (matrice 33 et 40) :
  les builds de test doivent les ignorer. `\(CAP32_SNAPSHOT)` ne produit aucun fichier.
- Modèle 0 (464) : pas de disque sans `-O rom.slot07=amsdos.rom`.
- Une seule fenêtre d'émulateur à la fois : `taskkill //IM cap32.exe //F` avant de relancer.
- `RUN"fichier"` d'un binaire réinitialise le firmware : les routines CAS visent la cassette. Réinitialiser
  AMSDOS au démarrage : `ld c,7 : ld de,#0040 : ld hl,#ABFF : call #BCCE` (KL INIT BACK), puis `POKE #BE78,#FF`
  pour taire les erreurs disque. Tampon AMSDOS jamais sous la ROM haute.
- Rendre la main au firmware pour un accès disque : restaurer `&38` et BC', puis recharger les 16 encres.
- Un jeu qui relance le firmware avant chaque accès disque peut ne survivre qu'à l'état laissé par son
  propre chargeur : garder le chargeur d'origine et patcher le jeu, plutôt que réécrire un chargeur sans avoir tracé la ROM.
- Compter en NOPs (19 968 par image). Trouver la VSYNC sur le PPI, pas en comptant les interruptions (300 Hz).

## Commodore 64 / VICE

- VICE 3.10 : `x64sc`, `c1541` dans `%LOCALAPPDATA%\VICE\GTK3VICE-3.10-win64\bin`. Captures sans fenêtre :
  `-limitcycles N -exitscreenshot f.png`. Sans fenêtre visible, VICE cale à vitesse normale : forcer `-warp`.
- Moniteur distant : un port différent par exécution (éviter une instance restante) ; il perd parfois la
  connexion au démarrage — réessayer. Beaucoup de commandes + warp peuvent tuer VICE : préférer un simulateur 6502 (py65).
- `keybuf` : lettres en minuscules (majuscule = SHIFT). Certains jeux vident le tampon clavier : injecter une touche à la fois.
- Chronomètre du moniteur : il reboucle à 2^32, le remettre à zéro par commande.
- Chargeur rapide 1541 : avec un secteur transféré en ~119 ms, un entrelacement de 20 tombe sur le secteur suivant.
- Ne tuer que les instances `x64sc` qu'on a lancées (filtrer sur la ligne de commande).

## ColecoVision / MSX / openMSX

- VRAM TMS9918 écrite seulement écran et NMI coupés, ou dans la NMI depuis des tampons en RAM.
- BIOS Coleco à copier dans `Documents\openMSX\share\systemroms` (non distribuable). MSX : C-BIOS suffit.
- Captures scriptées openMSX : pas de `throttle off`. Registre 7 de l'AY sur MSX : bits 7-6 = 10.

## Thomson MO5 / DCMOTO

- DCMOTO n'a pas de ligne de commande : « Simuler le clavier » pour taper `LOADM"",,R`.
- Compter les images sur les fronts du bit 7 de `$A7E7`.

## Travailler avec l'utilisateur

- Français ; textes du jeu en anglais sauf décision contraire.
- Silencieux pendant le travail, compte rendu clair à la fin (ou toutes les 15-30 min sur une longue tâche :
  ce qui est fait, chiffres avant/après, problèmes, suite). Langage simple, sans adresses mémoire dans le résumé.
- Ne pas s'arrêter entre deux étapes d'un plan validé ; s'arrêter seulement pour une décision qui lui revient ou un vrai blocage.
- Il teste visuellement et à l'oreille : déboguer en simulateur, peu de lancements d'émulateur, et le son se valide à l'écoute.
- Ne jamais envoyer de touches ni capturer l'écran sur son bureau : il utilise le PC en même temps.
- Toujours laisser la version **normale** (pas autoplay/test/profil) dans `build/` ; archiver chaque support livré avec un numéro de version.
