; ===========================================================================
; proj.asm - projection court -> écran GB ($095D, $0951, $09C2) en 6809,
; reprise de la version Z80 (vérifiée contre la ROM par tools/test_proj.py
; des versions CPC) :
;   b = Y arrondi, c = X arrondi, dx = |$6C - c|, dy = |$B8 - b|
;   l = ((dx² x dy) / 256 / 72) / 4, opposé si b >= $B8
;   x = c + l si c < $6C, sinon c - l ;  y = $1C + b x 40 / 47
; Sorties : pj_x, pj_y (pixels GB). La logique n'appelle jamais ces routines.
; ===========================================================================

; X -> Y (8.8), X (8.8) (octet de fraction d'abord, comme sur GB)
proj
        lda ,x                      ; b = Y arrondi
        adda #$80
        lda 1,x
        adca #0
        sta pj_b
        lda 2,x                     ; c = X arrondi
        adda #$80
        lda 3,x
        adca #0
        sta pj_c
        bra proj_bc

; $0951 : marque de rebond (Y et X sans arrondi, Y - 1 devant le filet)
proj_mark
        lda 1,x
        cmpa #$78
        bhs pm_f
        deca
pm_f    sta pj_b
        lda 3,x
        sta pj_c

; pj_b, pj_c -> pj_x, pj_y
proj_bc
        lda pj_c                    ; dx = |c - $6C|
        suba #$6C
        bcc pb_dx
        nega
pb_dx   tfr a,b                     ; dx²
        clra
        lslb
        rola
        ldx #sq_tab
        ldd d,x
        std pj_sq
        lda pj_b                    ; dy = |b - $B8|
        suba #$B8
        bcc pb_dy
        nega
pb_dy   sta pj_dy
        ldb pj_sq+1                 ; (dx² x dy) / 256 = hi x dy + (lo x dy) / 256
        mul
        sta pj_t
        lda pj_dy
        ldb pj_sq
        mul
        addb pj_t
        adca #0
        ldx #8                      ; quotient par 72 (8 bits) -> B
pb_d    lslb
        rola
        cmpa #72
        blo pb_dn
        suba #72
        incb
pb_dn   leax -1,x
        bne pb_d
        lsrb                        ; l = quotient / 4
        lsrb
        lda pj_b                    ; b >= $B8 : l = -l
        cmpa #$B8
        blo pb_pos
        negb
pb_pos  stb pj_t
        lda pj_c                    ; x = c + l si c < $6C, sinon c - l
        cmpa #$6C
        bhs pb_sub
        adda pj_t
        bra pb_x
pb_sub  suba pj_t
pb_x    sta pj_x
        ldx #ytab                   ; y = $1C + b x 40 / 47
        ldb pj_b
        abx
        lda ,x
        sta pj_y
        rts

; $09C2 : hauteur de la balle : pj_y -= lift
;   z' = z + z/8 si la balle est au service (état 2) ; l = z' x 6 / 16 + 1,
;   moins 1 à 3 pixels vers le fond (b < $C8, < $A8, < $78), sans passer 0.
lift
        lda B_Z
        ldb B_ST
        cmpb #2
        bne lf_n
        lsra
        lsra
        lsra
        adda B_Z
lf_n    ldx #lifttab
        tfr a,b
        abx
        ldb ,x
        incb
        lda pj_b
        cmpa #$C8
        bhs lf_d
        decb
        beq lf_d
        cmpa #$A8
        bhs lf_d
        decb
        beq lf_d
        cmpa #$78
        bhs lf_d
        decb
lf_d    stb pj_t
        lda pj_y
        suba pj_t
        sta pj_y
        rts

; tables sq_tab, ytab, lifttab : gfx/tables.asm
