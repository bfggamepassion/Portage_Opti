; ===========================================================================
; defs.asm - carte mémoire du MO5, registres et variables GB, matériel
;
; La logique du jeu est la ROM Game Boy traduite en 6809 (gb/gb_logic.asm,
; tools/gb2m6809.py) :
;   - A du GB = A du 6809 ; B C D E H L du GB en page directe (rB ... rL) ;
;   - RAM GB déplacée (port_config.py, RAM_MAP) :
;       GB $C000-$C0FF -> $9D00   GB $DD00 -> $9E00   GB $FF80 -> $9F80
;   - page directe (DP = $9F) : registres GB, variables rapides, HRAM GB.
; ===========================================================================

; --- Carte mémoire -------------------------------------------------------------
;   $0000-$1FFF  écran : forme (pixels) ou couleur, selon le bit 0 de $A7C0
;   $2000-$2FFF  moniteur et BASIC (non utilisés une fois le jeu lancé)
;   $3000-$93FF  programme (chargé par LOADM) ; $9400-$9BFF travail
;   $9C00-$9CFF  pile
;   $9D00-$9DFF  RAM GB ($C000)
;   $9E00        son GB ($DD00) ; $9E01-$9EFF variables
;   $9F00-$9F7F  registres GB, variables rapides (page directe)
;   $9F80-$9FFF  HRAM GB ($FF80)
GB_WRAM     equ $9D00
GB_SNDRAM   equ $9E00
GB_HRAM     equ $9F80
DPAGE       equ $9F
STACK_TOP   equ $9D00

; --- Registres GB (page directe) ------------------------------------------------
rB          equ $9F00
rC          equ $9F01
rD          equ $9F02
rE          equ $9F03
rH          equ $9F04
rL          equ $9F05

; --- Variables GB utilisées par le code MO5 (adresses déplacées) -----------------
P1_STATE    equ $9D00           ; joueur 1 : état, image, Y (8.8), X (8.8)
P1_FRAME    equ $9D01
P1_Y        equ $9D02
P1_X        equ $9D04
P2_STATE    equ $9D20
P2_FRAME    equ $9D21
P2_Y        equ $9D22
P2_X        equ $9D24
B_ST        equ $9D40           ; balle : état, Y, X, hauteur
B_Y         equ $9D42
B_X         equ $9D44
B_Z         equ $9D47
B_VX        equ $9D50           ; vitesse latérale (signe-module)
B_VZ        equ $9D52           ; vitesse de montée
B_MARK      equ $9D60           ; marque de rebond : délai, position
B_MARKY     equ $9D62
B_MARKX     equ $9D64
P1_ZONE     equ $9D0B           ; zones calculées par la ROM ($09FA)
P2_ZONE     equ $9D2B
W_PTS1      equ $9DDD           ; points (codes GB)
W_PTS2      equ $9DDE
W_LEVEL     equ $9DDF           ; niveau 1-4
W_GAMES1    equ $9DE0           ; jeux par set
W_GAMES2    equ $9DE3

H_SCREEN    equ $9F8A           ; écran GB (3 = court, $0A = fin de match)
H_SIDE95    equ $9F95
H_OPT       equ $9F96           ; options
H_PAD98     equ $9F98
H_PRS99     equ $9F99
H_PAD1      equ $9F9A           ; joypad J1 : maintenu / pressé
H_PRS1      equ $9F9B
H_PADPREV   equ $9F9E           ; joypad précédent ($21ED)
H_RNG       equ $9FA4           ; hasard
H_HIT       equ $9FAD           ; bit 7 = c'est au joueur 2 de frapper
H_SETS      equ $9FC4
H_ANN       equ $9FC2           ; annonce ($C1 score, $C4 faute, $C5 let, $C6 dehors)

; --- Joypad GB --------------------------------------------------------------
PAD_A       equ $01
PAD_B       equ $02
PAD_START   equ $08
PAD_R       equ $10
PAD_L       equ $20
PAD_U       equ $40
PAD_D       equ $80

; --- Matériel du MO5 -------------------------------------------------------------
PIA_A       equ $A7C0           ; bit 0 : 1 = forme, 0 = couleur ; bits 1-4 : bordure
PIA_B       equ $A7C1           ; bit 0 : buzzer ; bits 1-6 : touche ; bit 7 : 0 = appuyée
PIA_CRA     equ $A7C2
PIA_CRB     equ $A7C3
GA_INIT     equ $A7E7           ; bit 7 : 1 pendant l'image (200 lignes)
