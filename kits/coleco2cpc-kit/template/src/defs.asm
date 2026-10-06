; ===========================================================================
; defs.asm - Cabbage Patch Kids (ColecoVision 1984) sur Amstrad CPC 6128
;
; Principe : le code Z80 d'origine de la cartouche tourne TEL QUEL sur le
; CPC. Seules ses instructions d'entrée-sortie (VDP TMS9918, son SN76489,
; manettes) sont remplacées par des appels (patches.asm) :
;   - VDP virtuel : la VRAM (16 Ko) est une banque de RAM, les registres des
;     variables ; chaque écriture dans la table des noms marque la case ;
;   - la NMI de trame est simulée par l'interruption du CPC (300 Hz / 5 =
;     60 Hz, la cadence de la ColecoVision NTSC) ;
;   - un moteur de rendu (render.asm), qui remplace la boucle d'attente du
;     jeu, recopie l'image du VDP en mode 0 (16 couleurs, 128 x 192 : deux
;     pixels Coleco donnent un pixel CPC) dans l'écran caché, puis bascule
;     les deux écrans au retour de trame : aucun clignotement.
;
; --- Configurations mémoire (Gate Array, $7Fxx <- $C0 + n) ---------------------
;   V_GAME  $C2 : banques 4 5 6 7            (le jeu : vue « Coleco »)
;   V_BASE  $C0 : base 0 1 2 3               (dessin des cases)
;   V_B4    $C4 : base0, banque 4, base2, base3  (dessin des sprites)
;   V_B5    $C5 : base0, banque 5, base2, base3  (état partagé)
;   V_B7    $C7 : base0, banque 7, base2, base3  (lecture de la VRAM)
;
; --- Contenu ----------------------------------------------------------------
;   base0  $0000-$01FF code commun (aussi en banque 4) : interruption, bascules
;          $0200-$3FFF moteur de rendu, tables, pile du rendu
;   base1  $4000-$6FFF cache des tuiles converties (768 x 16 octets)
;          $7000-$72FF noms affichés, $7300-$75FF tampons de trame par case
;   base2  $8000 écran A ; base3 $C000 écran B (64 octets x 192 lignes ;
;          trous de 512 octets en $x600-$x7FF de chaque bloc de 2 Ko)
;   banque 4 $0000-$01FF commun, $0200-$0FFF code « vue jeu » (VDP virtuel,
;          son, manettes), $1000-$3FFF cache des sprites (vue V_B4 : $5000)
;   banque 5 $4000-$5FFF état partagé jeu <-> rendu, pile de la NMI ;
;          $6000-$63FF RAM de la ColecoVision (1 Ko)
;   banque 6 $8000-$BFFF cartouche (corrigée)
;   banque 7 VRAM du TMS9918 (vue jeu : $C000 ; vue V_B7 : $4000)
; ===========================================================================

V_BASE      equ $C0
V_GAME      equ $C2
V_B4        equ $C4
V_B5        equ $C5
V_B7        equ $C7

GA          equ $7F
GA_MODE0    equ %10001100       ; mode 0, ROM basse et haute coupées

; --- Cartouche --------------------------------------------------------------------
CART_START  equ $80C6           ; démarrage du jeu (en-tête $800A)
CART_NMI    equ $807C           ; routine de NMI du jeu
CART_IDLE   equ $80E8           ; « jr $ » : boucle d'attente -> moteur de rendu
COLECO_RAM  equ $6000

; --- VRAM ----------------------------------------------------------------------
VRAM_G      equ $C000           ; VRAM vue du jeu
VRAM_R      equ $4000           ; VRAM vue du rendu (V_B7)

; --- Banque 5 : état partagé (mêmes adresses en V_GAME et V_B5) --------------------
SH          equ $4000
dirty_flag  equ SH+$0000        ; 768 octets : 1 = case déjà dans la liste
spr_dirty   equ SH+$0300        ; 64 octets : 1 = motif de sprite 16x16 modifié
class_tab   equ SH+$0340        ; 64 octets : genre de chaque page de VRAM
vaddr       equ SH+$0380        ; adresse VRAM courante (0-$3FFF)
vregs       equ SH+$0382        ; registres 0-7 du VDP
vlatch      equ SH+$038A        ; 1er octet d'une écriture de contrôle
vlatch_f    equ SH+$038B        ; 1 = 1er octet reçu
dirty_n     equ SH+$038C        ; nombre de cases dans la liste (mot)
full_req    equ SH+$038E        ; 1 = motifs/couleurs changés : tout refaire
spr_req     equ SH+$038F        ; 1 = au moins un motif de sprite modifié
frame_cnt   equ SH+$0390        ; trames (incrémenté au VSYNC par l'interruption)
int_cnt     equ SH+$0391        ; interruptions (300 Hz), cycle de 5
nmi_busy    equ SH+$0392        ; profondeur de NMI simulée
sn_latch    equ SH+$0393        ; SN76489 : dernier registre choisi
sn_regs     equ SH+$0394        ; 8 valeurs : ton0, vol0, ton1, vol1, ton2, vol2, bruit, vol3 (mots pour les tons)
ay_mix      equ SH+$03A4        ; registre 7 de l'AY
ctl_mode    equ SH+$03A5        ; 0 = manette, 1 = pavé numérique
vblank_st   equ SH+$03A6        ; indicateur de trame (bit 7) du registre d'état
dirty_ptr   equ SH+$03A8        ; liste où le jeu ajoute (dirty_la ou dirty_lb)
tile_req    equ SH+$03AA        ; 1 = au moins un motif/couleur de tuile modifié
sat_src     equ SH+$03AC        ; table des sprites laissée en RAM Coleco (0 = en VRAM)
sat_len     equ SH+$03AE        ; ... sa longueur
sat_base    equ SH+$03B0        ; adresse VRAM de la table des sprites
logo_on     equ SH+$03B3        ; 1 = menu : tuiles du logo posées par le rendu
names_ovf   equ SH+$03B2        ; 1 = liste des cases pleine : redessiner les cases (sans reconvertir)
DIRTY_MAX   equ 255
dirty_la    equ SH+$0400        ; listes : 1 octet (nombre) + 255 mots (cases 0-767)
dirty_lb    equ SH+$0600
pat_dirty   equ SH+$0800        ; 768 octets : 1 = motif de tuile n modifié
MEMO_OWN    equ SH+$0B00        ; 768 octets : n° (1-16) du rectangle mémorisé qui a écrit la case (0 : aucun)
MEMO_TAB    equ SH+$0E00        ; 16 rectangles mémorisés x 16 octets (voir nrect_wr)
GAME_STACK  equ $6000           ; pile de la NMI simulée ($5F00-$5FFF)

; classes des pages de VRAM
C_PLAIN     equ 0
C_NAME      equ 1
C_TILE      equ 2               ; motifs ou couleurs des tuiles
C_SPAT      equ 3               ; motifs des sprites
C_SAT       equ 4               ; table des sprites (copie paresseuse)

; --- base1 (vue V_BASE) ---------------------------------------------------------------
TCACHE      equ $4000           ; tuiles converties : 768 x 16
RNAMES      equ $7000           ; nom affiché de chaque case
STAMP       equ $7300           ; numéro de trame du dernier dessin de la case

; --- banque 4 vue en V_B4 --------------------------------------------------------------
SCACHE      equ $5000           ; 64 motifs x 2 décalages x 80 octets (masques inversés)

; --- Écrans --------------------------------------------------------------------------
SCR_A       equ $8000
SCR_B       equ $C000
