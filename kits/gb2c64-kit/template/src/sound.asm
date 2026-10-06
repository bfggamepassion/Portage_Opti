; ===========================================================================
; sound.asm - bruitages au SID pour les numéros de son de la ROM ($3665)
;   3 rebond  4 mur  5 élan  6/7 frappe  $0C filet  $0D corps
;   $25 applaudissements  $29/$31 annonce du score
; La logique demande un son (S_SOUND -> sfx_req) ; play_sfx le lance après
; l'affichage, sur la voix 1 (la voix 3 pour les applaudissements, qui
; durent). Chaque son : forme d'onde, fréquence, enveloppe, durée en trames.
; ===========================================================================

SID         = $D400

sound_init
        ldx #$18
        lda #0
-       sta SID,x
        dex
        bpl -
        lda #$08                    ; largeur d'impulsion 50 %
        sta SID+3
        sta SID+17
        lda #$0F                    ; volume
        sta SID+24
        rts

sfx_time    .byte 0, 0              ; trames restantes (voix 1, voix 3)
sfx_wave    .byte 0, 0

; Chaque trame : fin des sons en cours, puis nouveau son demandé
play_sfx
        ldx #1
-       lda sfx_time,x
        beq +
        dec sfx_time,x
        bne +
        ldy voice_off,x             ; porte fermée : relâchement
        lda sfx_wave,x
        and #$FE
        sta SID+4,y
+       dex
        bpl -
        ldy #0
        lda sfx_req
        beq _r
        sty sfx_req
        ldx #0
-       cmp sfx_table,x
        beq _found
        pha
        txa
        clc
        adc #7
        tax
        pla
        ldy sfx_table,x
        bne -
        ldy #0
_r      rts
_found  ldy #0                      ; voix 1, ou 3 pour les applaudissements
        cmp #$25
        bne +
        ldy #1
+       lda sfx_table+6,x
        sta sfx_time,y
        lda sfx_table+1,x
        sta sfx_wave,y
        lda voice_off,y
        tay
        lda #0                      ; porte fermée d'abord : l'enveloppe repart
        sta SID+4,y
        lda sfx_table+2,x
        sta SID+1,y                 ; fréquence (octet haut)
        lda #0
        sta SID+0,y
        lda sfx_table+3,x
        sta SID+5,y                 ; attaque / déclin
        lda sfx_table+4,x
        sta SID+6,y                 ; maintien / relâchement
        lda sfx_table+1,x
        sta SID+4,y                 ; forme d'onde + porte ouverte
        ldy #0
        rts

voice_off   .byte 0, 14

; numéro GB, forme d'onde (porte ouverte), fréquence haute, AD, SR, (libre), durée
sfx_table
        .byte $03, $11, $0C, $08, $00, 0, 3     ; rebond : triangle court
        .byte $04, $81, $18, $08, $00, 0, 3     ; mur : bruit
        .byte $05, $81, $40, $04, $00, 0, 2     ; élan : souffle
        .byte $06, $41, $1C, $08, $00, 0, 3     ; frappe : impulsion
        .byte $07, $41, $1C, $08, $00, 0, 3
        .byte $0C, $81, $06, $0A, $00, 0, 6     ; filet : bruit grave
        .byte $0D, $11, $05, $09, $00, 0, 5     ; corps
        .byte $25, $81, $50, $4A, $A9, 0, 50    ; applaudissements : bruit, attaque lente
        .byte $29, $11, $22, $08, $00, 0, 8     ; annonce du score
        .byte $31, $11, $28, $08, $00, 0, 8
        .byte 0
