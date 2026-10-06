; ===========================================================================
; defs.asm - carte mémoire et constantes (valeurs de ZX Tennis, à adapter)
;
; Principe : la logique GB traduite garde ses adresses de RAM d'origine
; ($C000-$DFFF, $FF80-$FFFE). Le programme Spectrum se loge autour.
; ===========================================================================

; --- Carte mémoire (48K) ----------------------------------------------------
; $4000-$5AFF écran. $5B00-$5FFF variables système / pile.
; $6000-$7FFF : mémoire « contendue » (ralentie par l'ULA) -> code froid :
;               démarrage, menu, texte, décor, écran titre compressé.
; $8000-$FFFF : mémoire rapide -> tout ce qui tourne à chaque image.
SCREEN      equ $4000
ATTRS       equ $5800
CODE_START  equ $6000           ; zone lente (pile juste en dessous)
HOT_START   equ $8000           ; zone rapide : boucle, logique traduite, sprites
GB_WRAM     equ $C000           ; RAM GB utilisée par le jeu (vérifier l'étendue !)
SPRMEM      equ $D400           ; caches et tampons des sprites
GFX_START   equ $E000           ; graphismes des sprites
IM2_ISR     equ $FDFD           ; saut vers la routine d'interruption
IM2_TABLE   equ $FE00           ; table IM2 : 257 x $FD
GB_HRAM     equ $FF80           ; HRAM GB $FF80-$FFFE

; --- Joypad GB --------------------------------------------------------------
PAD_A       equ $01
PAD_B       equ $02
PAD_SELECT  equ $04
PAD_START   equ $08
PAD_R       equ $10
PAD_L       equ $20
PAD_U       equ $40
PAD_D       equ $80

; --- Sprites (voir sprite.asm) ----------------------------------------------
NSLOTS      equ 2               ; emplacements, dessinés dans l'ordre, effacés à l'envers
        MACRO SLOT_BIG          ; 1 = grand slot (joueurs), 0 = petit (balle...)
        db 1, 0
        ENDM

; --- Couleurs ------------------------------------------------------------------
BORDER_COL  equ 4               ; bordure pendant le jeu
ATTR_GAME   equ %01100000       ; BRIGHT 1, PAPER 4 (vert), INK 0 (noir)
