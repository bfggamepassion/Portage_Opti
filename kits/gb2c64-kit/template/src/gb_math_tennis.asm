; ===========================================================================
; gb_math_tennis.asm - EXEMPLE (non inclus) : routines de calcul de la ROM de
; Tennis réécrites en 6502 natif, avec exactement les mêmes sorties
; (registres, indicateurs, octets de travail HRAM). Méthode : les déclarer
; dans CFG.STUBS et CFG.STUB_FLAGS, puis vérifier avec diff_gb6502.py.
; ===========================================================================

; --- Calculs de la ROM, réécrits en 6502 (mêmes résultats, registres,
; indicateurs et octets de travail $FFC7/$FFC8 que la ROM) ------------------

; $30D0 / $30F8 : HL x A (16 x 8 bits). Sortie : produit sur 24 bits dans
; C:H:L, A = C = [T2] = octet haut, D = ancien L, E = 0, B = 0, Z = 1, C = 0.
; [T1] = multiplicateur tourné jusqu'à amener son bit fort en bit 7 (ce que
; laisse la boucle de la ROM). T1/T2 : $FFC7/$FFC8 ($30D0), $FFD1/$FFD2 ($30F8).
mul16x8 .macro T1, T2
        lda zA
        beq +
        bmi +
-       asl a
        adc #0
        bpl -
+       sta \T1
        lda zL                      ; multiplicande sur 24 bits
        sta zW
        sta zD
        lda zH
        sta zW+1
        lda zA
        sta zW+3                    ; multiplicateur
        sty zW+2
        sty zL
        sty zH
        sty zC
        sty zE
        sty zB
-       lsr zW+3
        bcc +
        clc
        lda zL
        adc zW
        sta zL
        lda zH
        adc zW+1
        sta zH
        lda zC
        adc zW+2
        sta zC
+       lda zW+3
        beq +
        asl zW
        rol zW+1
        rol zW+2
        jmp -
+       lda zC
        sta zA
        sta \T2
        sty zZ
        sty zCY
        rts
        .endm

S_MUL   #mul16x8 $FFC7, $FFC8
S_MUL2  #mul16x8 $FFD1, $FFD2

; $308F : A x E (8 x 8 bits) -> HL. A conservé, DE = E << 7, Z = 0, C = 0.
S_MUL8  lda zE
        sta zW
        sty zW+1
        lda zA
        sta zW+2
        sty zL
        sty zH
        ldx #8
-       lsr zW+2
        bcc +
        clc
        lda zL
        adc zW
        sta zL
        lda zH
        adc zW+1
        sta zH
+       dex
        beq +
        asl zW
        rol zW+1
        jmp -
+       lda zW
        sta zE
        lda zW+1
        sta zD
        lda #1
        sta zZ
        sty zCY
        rts

; $3143 : HL / A (16 / 8 bits, déroulée dans la ROM). Sortie : HL = quotient,
; A = reste, C = diviseur, Z = 0, C = emprunt de la dernière soustraction
; (ou de la comparaison, si elle a échoué).
S_DIV8  lda zA
        sta zC
        lda #0
        ldx #16
_d8     asl zL
        rol zH
        rol a
        bcs _ovf
        cmp zC
        bcc _no
        sbc zC                      ; (C = 1 : pas d'emprunt)
        inc zL
        sty zW
        jmp _nx
_ovf    sec                         ; dépassement : on soustrait toujours
        sbc zC
        inc zL
        sty zW
        bcs _nx
        inc zW                      ; emprunt sur 8 bits (comme le GB)
        jmp _nx
_no     sty zW
        inc zW
_nx     dex
        bne _d8
        sta zA
        lda zW
        sta zCY
        lda #1
        sta zZ
        rts

; $31D5 : HL / DE (16 / 16 bits, division avec restauration).
; Sortie : HL = quotient, B:C = reste (A = B = [$FFC7] = octet haut),
; [$FFC8] = dernier essai de soustraction (octet bas), Z = 1,
; C = 1 si la dernière soustraction a été refusée.
S_DIV   sty zC
        sty zW                      ; reste, octet haut
        ldx #16
-       asl zL
        rol zH
        rol zC
        rol zW
        sec
        lda zC
        sbc zE
        sta zW+1
        lda zW
        sbc zD
        bcc +
        sta zW
        lda zW+1
        sta zC
        inc zL
+       dex
        bne -
        lda #0
        rol a
        eor #1
        sta zCY
        lda zW+1
        sta $FFC8
        lda zW
        sta $FFC7
        sta zB
        sta zA
        sty zZ
        rts

