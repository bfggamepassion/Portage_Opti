; ===========================================================================
; autoplay.asm - robot joueur 1 (version de test : sh build.sh AUTOPLAY)
; Même logique que les robots des autres versions : servir, se placer sous
; la balle qui arrive, frapper, revenir au centre. Sortie : A = joypad GB.
; ===========================================================================
bot_pad
        lda bot_cool
        beq bp_c
        deca
        sta bot_cool
bp_c    lda P1_STATE
        cmpa #5                     ; service : frapper après 20 trames
        bne bp_s6
        inc bot_serve
        lda bot_serve
        cmpa #20
        bne bp_none
        lda #PAD_A
        rts
bp_s6   cmpa #6                     ; balle lancée : frapper quand elle redescend
        bne bp_ral
        lda B_VZ
        bpl bp_none
        lda B_Z
        cmpa #$50
        bhs bp_none
        tst bot_cool
        bne bp_none
        lda #10
        sta bot_cool
        lda #PAD_A
        rts
bp_none clra
        rts
bp_ral  clr bot_serve
        clr tmp
        lda B_ST                    ; balle en jeu qui vient vers nous ?
        cmpa #3
        beq bp_come
        cmpa #4
        bne bp_cen
bp_come lda $9D4F
        bmi bp_cen
        lda $9D43
        cmpa #$60
        blo bp_cen
        lda $9D45                   ; cible x = balle - 10
        suba #10
        sta tmp+1
        lda $9D05
        adda #2
        cmpa tmp+1
        bhs bp_nr
        lda #PAD_R
        sta tmp
        bra bp_hit
bp_nr   lda $9D05
        suba #2
        cmpa tmp+1
        bls bp_hit
        lda #PAD_L
        sta tmp
bp_hit  lda P1_STATE
        cmpa #1
        bne bp_out
        tst bot_cool
        bne bp_out
        lda $9D03                   ; 0 < y joueur - y balle < 16
        suba $9D43
        beq bp_out
        cmpa #16
        bhs bp_out
        lda #12
        sta bot_cool
        lda tmp
        ora #PAD_A
        rts
bp_cen  lda P1_STATE
        cmpa #1
        bne bp_out
        lda $9D05
        cmpa #$68
        bhs bp_nc
        lda #PAD_R
        sta tmp
        bra bp_back
bp_nc   cmpa #$71
        blo bp_back
        lda #PAD_L
        sta tmp
bp_back lda $9D03
        cmpa #$BB
        blo bp_out
        lda tmp
        ora #PAD_U
        sta tmp
bp_out  lda tmp
        rts
