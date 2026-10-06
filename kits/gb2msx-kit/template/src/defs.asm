; ===========================================================================
; defs.asm - carte mémoire du MSX1, variables GB, VDP, PSG
;
; La logique du jeu est la ROM Game Boy traduite en Z80 (gb/gb_logic.asm).
; La RAM GB $C000-$C0FF garde son adresse (RAM du MSX) ; la HRAM ($FF80,
; zone système du MSX) et l'octet de son sont déplacés par le traducteur
; (port_config.py, RAM_MAP) : GB $FF80-$FFFE -> $C180, GB $DD00 -> $C200.
; ===========================================================================

; --- Carte mémoire -------------------------------------------------------------
;   $0000-$3FFF  BIOS (appelé seulement au démarrage : RSLREG, ENASLT)
;   $4000-$BFFF  cartouche (32 Ko ; la page $8000 est ouverte au démarrage)
;   $C000-$C0FF  RAM GB ($C000)
;   $C100-$C17F  variables (vars.asm, partie 1)
;   $C180-$C1FF  HRAM GB ($FF80)
;   $C200        son GB ($DD00) ; $C201-$C3FF variables (partie 2)
;   $C400-$C500  table des vecteurs IM 2 (octets $C5) ; $C5C5 : JP isr
;   $C600-$C7FF  pile
GB_WRAM     equ $C000
GB_HRAM     equ $C180
GB_SNDRAM   equ $C200
IM2_TABLE   equ $C400
IM2_JUMP    equ $C5C5
STACK_TOP   equ $C800

; --- Variables GB utilisées par le code ColecoVision (adresses déplacées) --------
P1_STATE    equ $C000           ; joueur 1 : état, image, Y (8.8), X (8.8)
P1_FRAME    equ $C001
P1_Y        equ $C002
P1_X        equ $C004
P2_STATE    equ $C020
P2_FRAME    equ $C021
P2_Y        equ $C022
P2_X        equ $C024
B_ST        equ $C040           ; balle : état, Y, X, hauteur
B_Y         equ $C042
B_X         equ $C044
B_Z         equ $C047
B_VX        equ $C050           ; vitesse latérale (signe-module)
B_VZ        equ $C052           ; vitesse de montée
B_MARK      equ $C060           ; marque de rebond : délai, position
B_MARKY     equ $C062
B_MARKX     equ $C064
P1_ZONE     equ $C00B           ; zones calculées par la ROM ($09FA)
P2_ZONE     equ $C02B
W_PTS1      equ $C0DD           ; points (codes GB)
W_PTS2      equ $C0DE
W_LEVEL     equ $C0DF           ; niveau 1-4
W_GAMES1    equ $C0E0           ; jeux par set
W_GAMES2    equ $C0E3

H_SCREEN    equ $C18A           ; écran GB (3 = court, $0A = fin de match)
H_SIDE95    equ $C195
H_OPT       equ $C196           ; options
H_PAD98     equ $C198
H_PRS99     equ $C199
H_PAD1      equ $C19A           ; joypad J1 : maintenu / pressé
H_PRS1      equ $C19B
H_PADPREV   equ $C19E           ; joypad précédent ($21ED)
H_RNG       equ $C1A4           ; hasard
H_HIT       equ $C1AD           ; bit 7 = c'est au joueur 2 de frapper
H_SETS      equ $C1C4
H_ANN       equ $C1C2           ; annonce ($C1 score, $C4 faute, $C5 let, $C6 dehors)

; --- Joypad GB --------------------------------------------------------------
PAD_A       equ $01
PAD_B       equ $02
PAD_START   equ $08
PAD_R       equ $10
PAD_L       equ $20
PAD_U       equ $40
PAD_D       equ $80

; --- VDP TMS9918A ---------------------------------------------------------------
VDP_DATA    equ $98
VDP_CTRL    equ $99
; VRAM (mode graphique 2)
VR_PAT      equ $0000           ; motifs : 3 tiers de 2 Ko
VR_NAME     equ $1800           ; carte 32x24
VR_SAT      equ $1B00           ; attributs des sprites
VR_COL      equ $2000           ; couleurs : 3 tiers de 2 Ko
VR_SPAT     equ $3800           ; motifs des sprites (64 x 32 octets)
; registre 1 : 16 Ko, sprites 16x16, + écran allumé (bit 6), + interruption (bit 5)
R1_OFF      equ $82
R1_ON_INT   equ $E2

; --- PSG AY-3-8910 (1,79 MHz) : son et manettes ------------------------------------
PSG_ADDR    equ $A0
PSG_WRITE   equ $A1
PSG_READ    equ $A2

; --- Clavier : PPI (ligne choisie par les bits 0-3 du port C, lue sur le port B) ---
PPI_B       equ $A9
PPI_C       equ $AA

; --- BIOS (au démarrage seulement) -------------------------------------------------
ENASLT      equ $0024
MSXID1      equ $002B           ; bit 7 : 1 = 50 Hz, 0 = 60 Hz
RSLREG      equ $0138
EXPTBL      equ $FCC1
