; ===========================================================================
; sound.asm - bruitages sur le buzzer du MO5 (bit 0 de $A7C1)
; pour les numéros de son de la ROM ($3665) :
;   3 rebond  4 mur  5 élan  6/7 frappe  $0C filet  $0D corps
;   $25 applaudissements  $29/$31 annonce du score
; Le buzzer n'a qu'un bit : un son est une suite de demi-périodes jouée
; d'un coup (2 à 4 ms, le jeu s'arrête pendant ce temps). Son pur : demi-
; période fixe ; bruit : demi-période tirée au hasard.
; ===========================================================================

; id, type (0 son pur, 1 bruit), demi-période (boucles de 5 cycles), demi-périodes
sfx_table
        fcb $03,0,60,10             ; rebond : grave et bref
        fcb $04,1,30,24             ; mur : bruit
        fcb $05,1,12,12             ; élan : souffle
        fcb $06,0,28,18             ; frappe
        fcb $07,0,28,18
        fcb $0C,1,50,20             ; filet : bruit grave
        fcb $0D,0,100,8             ; corps
        fcb $25,1,20,44             ; applaudissements
        fcb $29,0,40,20             ; annonce du score
        fcb $31,0,34,20
        fcb 0

play_sfx
        lda sfx_req
        beq psx_r
        clr sfx_req
        ldx #sfx_table
psx_f   ldb ,x
        beq psx_r
        pshs a
        cmpb ,s+
        beq psx_ok
        leax 4,x
        bra psx_f
psx_ok  ldb 3,x                     ; demi-périodes
psx_l   lda sfx_bit
        eora #1
        sta sfx_bit
        sta PIA_B
        lda 2,x                     ; demi-période
        tst 1,x
        beq psx_d
        lda tmp+1                   ; bruit : au hasard (1-63), x 5 + 1
        lsla
        lsla
        adda tmp+1
        inca
        sta tmp+1
        anda #$3F
        ora #1
psx_d   deca
        bne psx_d
        decb
        bne psx_l
psx_r   rts
