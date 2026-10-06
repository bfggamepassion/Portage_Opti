; ===========================================================================
; text.asm - texte (police du Tennis GB) et score
;   print_at : txt_row (0-24), txt_col (0-39), X = chaîne (0 à la fin),
;   couleur txt_color (encre << 4 | fond). Caractères 32-95.
; Score dans les marges (colonnes 0-3 et 36-39), comme la version CPC ;
; annonces sur le mur du fond (rangée 1), effacées en redessinant la rangée.
; ===========================================================================

ANN_ROW     equ 1
TXT_WHITE   equ $70             ; blanc sur noir
TXT_GREEN   equ $A0             ; vert clair sur noir

print_str
ps_l    lda ,x+
        beq ps_r
        pshs x
        bsr draw_char
        puls x
        inc txt_col
        bra ps_l
ps_r    rts

; A = caractère, à (txt_row, txt_col)
draw_char
        suba #32
        ldb #8
        mul
        addd #font
        tfr d,x
        ldb txt_row
        lslb
        ldy #rowaddr
        ldu b,y
        ldb txt_col
        leau b,u
        lda ,x
        sta ,u
        lda 1,x
        sta 40,u
        lda 2,x
        sta 80,u
        lda 3,x
        sta 120,u
        lda 4,x
        sta 160,u
        lda 5,x
        sta 200,u
        lda 6,x
        sta 240,u
        lda 7,x
        sta 280,u
        lda #PIA_COLOR
        sta PIA_A
        lda txt_color
        sta ,u
        sta 40,u
        sta 80,u
        sta 120,u
        sta 160,u
        sta 200,u
        sta 240,u
        sta 280,u
        lda #PIA_FORM
        sta PIA_A
        rts

; A = nombre 0-99, sans zéro de tête
print_num
        ldb #'0'-1
pn_t    incb
        suba #10
        bcc pn_t
        adda #10+'0'
        pshs a
        cmpb #'0'
        beq pn_u
        tfr b,a
        bsr draw_char
        inc txt_col
pn_u    puls a
        jsr draw_char
        inc txt_col
        rts

; --- Score ------------------------------------------------------------------------
show_score
        ldx #W_PTS1
        ldu #shown_score
        ldd ,x
        cmpd ,u
        bne show_score_force
        ldx #W_GAMES1
        ldb #6
ss_c    lda ,x+
        cmpa 2,u
        bne show_score_force
        leau 1,u
        decb
        bne ss_c
        bra show_ann
show_score_force
        ldd W_PTS1
        std shown_score
        ldx #W_GAMES1
        ldu #shown_score+2
        ldb #6
ssf_c   lda ,x+
        sta ,u+
        decb
        bne ssf_c
        lda #TXT_GREEN
        sta txt_color
        lda #1
        sta txt_row
        clr txt_col
        ldx #txt_you
        jsr print_str
        lda #36
        sta txt_col
        ldx #txt_cpu
        jsr print_str
        ldx #W_GAMES1
        lda #1
        jsr print_games
        ldx #W_GAMES2
        lda #37
        jsr print_games
        lda #7
        sta txt_row
        clr txt_col
        lda W_PTS1
        jsr print_points
        lda #36
        sta txt_col
        lda W_PTS2
        jsr print_points
show_ann
        lda H_ANN
        bita #$40
        bne sa_a
        clra
sa_a    cmpa shown_ann
        beq sa_r
        sta shown_ann
        pshs a
        jsr erase_ann               ; efface : le mur est redessiné
        puls a
        tsta
        beq sa_r
        anda #$0F
        ldx #txt_fault
        cmpa #4
        beq sa_p
        ldx #txt_let
        cmpa #5
        beq sa_p
        ldx #txt_out
        cmpa #6
        beq sa_p
        cmpa #1
        bne sa_r
        lda W_PTS2
        cmpa #6
        beq sa_adv
        lda W_PTS1
        cmpa #6
        beq sa_adv
        cmpa #5
        bne sa_r
        lda W_PTS2
        cmpa #5
        bne sa_r
        ldx #txt_deuce
        bra sa_p
sa_adv  ldx #txt_adv
sa_p    jmp announce
sa_r    rts

; X = texte : centré sur le mur du fond (rangée 1)
announce
        pshs x
        jsr compose_dirty           ; (les cases du mur effacées d'abord)
        puls x
        ldb #0                      ; longueur
        pshs x
an_l    tst ,x+
        beq an_e
        incb
        bra an_l
an_e    puls x
        lda #32
        pshs b
        suba ,s+
        lsra
        adda #4
        sta txt_col
        lda #ANN_ROW
        sta txt_row
        lda #TXT_WHITE
        sta txt_color
        jmp print_str

; rangée des annonces à redessiner (cases du stade)
erase_ann
        ldd #$001F
        std mk_x0
        lda #ANN_ROW
        sta mk_y0
        sta mk_y1
        jmp mark_rect

; X = 3 compteurs de jeux, A = colonne : rangées 3 à 5
print_games
        sta tmp
        lda #3
pg_l    sta txt_row
        pshs a,x
        lda tmp
        sta txt_col
        lda #' '
        jsr draw_char
        inc txt_col
        ldx 1,s
        lda ,x
        jsr print_num
        lda #' '
        jsr draw_char
        puls a,x
        leax 1,x
        inca
        cmpa #6
        bne pg_l
        rts

; A = code de points GB -> texte (1:0 2:15 3:30 4/5:40 6:AD 0:40 ; >= 7 tie-break)
print_points
        pshs a
        lda #' '
        jsr draw_char
        inc txt_col
        puls a
        cmpa #7
        blo pp_n
        suba #7
        jsr print_num
        bra pp_sp
pp_n    lsla
        ldx #points_txt
        leax a,x
        pshs x
        lda ,x
        jsr draw_char
        inc txt_col
        puls x
        lda 1,x
        jsr draw_char
        inc txt_col
pp_sp   lda #' '
        jmp draw_char

points_txt  fcc "40 015304040AD"
txt_you     fcc " YOU"
            fcb 0
txt_cpu     fcc " CPU"
            fcb 0
txt_fault   fcc " FAULT "
            fcb 0
txt_let     fcc " LET "
            fcb 0
txt_out     fcc " OUT "
            fcb 0
txt_deuce   fcc " DEUCE "
            fcb 0
txt_adv     fcc " ADVANTAGE "
            fcb 0
