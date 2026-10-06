; ===========================================================================
; defs.asm - carte mémoire de la ColecoVision, variables GB, VDP
;
; La logique du jeu est la ROM Game Boy traduite en Z80 (gb/gb_logic.asm).
; La console n'a que 1 Ko de RAM : la RAM GB utilisée par la logique y est
; déplacée par le traducteur (port_config.py, RAM_MAP) :
;   GB $C000-$C0FF -> $7000   GB $FF80-$FFFE -> $7180   GB $DD00 -> $7200
; ===========================================================================

; --- Carte mémoire -------------------------------------------------------------
;   $0000-$1FFF  BIOS (le jeu ne s'en sert pas, sauf le saut NMI $0066 -> $8021)
;   $7000-$70FF  RAM GB ($C000)
;   $7100-$717F  variables (vars.asm, partie 1)
;   $7180-$71FF  HRAM GB ($FF80)
;   $7200        son GB ($DD00) ; $7201-$73FF variables (partie 2), puis pile
;   $8000-$FFFF  cartouche (32 Ko)
GB_WRAM     equ $7000
GB_HRAM     equ $7180
GB_SNDRAM   equ $7200
STACK_TOP   equ $7400

; --- Variables GB utilisées par le code ColecoVision (adresses déplacées) --------
P1_STATE    equ $7000           ; joueur 1 : état, image, Y (8.8), X (8.8)
P1_FRAME    equ $7001
P1_Y        equ $7002
P1_X        equ $7004
P2_STATE    equ $7020
P2_FRAME    equ $7021
P2_Y        equ $7022
P2_X        equ $7024
B_ST        equ $7040           ; balle : état, Y, X, hauteur
B_Y         equ $7042
B_X         equ $7044
B_Z         equ $7047
B_VX        equ $7050           ; vitesse latérale (signe-module)
B_VZ        equ $7052           ; vitesse de montée
B_MARK      equ $7060           ; marque de rebond : délai, position
B_MARKY     equ $7062
B_MARKX     equ $7064
P1_ZONE     equ $700B           ; zones calculées par la ROM ($09FA)
P2_ZONE     equ $702B
W_PTS1      equ $70DD           ; points (codes GB)
W_PTS2      equ $70DE
W_LEVEL     equ $70DF           ; niveau 1-4
W_GAMES1    equ $70E0           ; jeux par set
W_GAMES2    equ $70E3

H_SCREEN    equ $718A           ; écran GB (3 = court, $0A = fin de match)
H_SIDE95    equ $7195
H_OPT       equ $7196           ; options
H_PAD98     equ $7198
H_PRS99     equ $7199
H_PAD1      equ $719A           ; joypad J1 : maintenu / pressé
H_PRS1      equ $719B
H_PADPREV   equ $719E           ; joypad précédent ($21ED)
H_RNG       equ $71A4           ; hasard
H_HIT       equ $71AD           ; bit 7 = c'est au joueur 2 de frapper
H_SETS      equ $71C4
H_ANN       equ $71C2           ; annonce ($C1 score, $C4 faute, $C5 let, $C6 dehors)

; --- Joypad GB --------------------------------------------------------------
PAD_A       equ $01
PAD_B       equ $02
PAD_START   equ $08
PAD_R       equ $10
PAD_L       equ $20
PAD_U       equ $40
PAD_D       equ $80

; --- VDP TMS9918A ---------------------------------------------------------------
VDP_DATA    equ $BE
VDP_CTRL    equ $BF
; VRAM (mode graphique 2)
VR_PAT      equ $0000           ; motifs : 3 tiers de 2 Ko
VR_NAME     equ $1800           ; carte 32x24
VR_SAT      equ $1B00           ; attributs des sprites
VR_COL      equ $2000           ; couleurs : 3 tiers de 2 Ko
VR_SPAT     equ $3800           ; motifs des sprites (64 x 32 octets)
; registre 1 : 16 Ko, sprites 16x16, + écran allumé (bit 6), + NMI (bit 5)
R1_OFF      equ $82
R1_ON       equ $C2
R1_ON_NMI   equ $E2
VDP_FREE    equ $A5             ; vdp_free : la NMI peut utiliser le VDP

; --- Son SN76489 -----------------------------------------------------------------
PSG         equ $FF

; --- Manettes -------------------------------------------------------------------
CTRL_KEYPAD equ $80             ; OUT : mode pavé numérique (+ bouton droit)
CTRL_JOY    equ $C0             ; OUT : mode manche (+ bouton gauche)
CTRL1       equ $FC             ; IN : manette 1
CTRL2       equ $FF             ; IN : manette 2
