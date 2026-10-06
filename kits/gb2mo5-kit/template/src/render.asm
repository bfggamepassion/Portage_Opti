; ===========================================================================
; render.asm - stade et objets (joueurs, balle, ombre, marque)
;
; Pas de sprites matériels sur MO5 : l'écran est recomposé par cases de 8x8.
; Quand un objet bouge ou change d'image, les cases de son ancien et de son
; nouveau rectangle sont marquées (DIRTY / DLIST). Chaque case marquée est
; recomposée d'un seul coup : tuile du stade, puis tous les objets qui la
; touchent (masque et encre), et enfin 8 octets de forme et 8 de couleur
; écrits à l'écran. Il n'y a jamais d'état intermédiaire effacé : pas de
; clignotement.
; Une ligne de l'image d'un objet : masque (pixels opaques), puis encre
; (pixels foncés, dessinés dans la couleur de l'objet) ; « l'image décalée »
; est l'image décalée de x AND 7 pixels (nb = largeur + 1 octets par plan).
; Coordonnées : colonne du stade 0-31 = colonne d'écran 4-35 ; x du stade
; = x GB ; y écran = y GB - 16 (rangée GB 2 en haut).
; ===========================================================================

OBJ_MARK    equ 0               ; ordre de dessin : marque, ombre, J2, J1, balle
OBJ_SHADOW  equ 1
OBJ_P2      equ 2
OBJ_P1      equ 3
OBJ_BALL    equ 4
SPR_P2      equ 20              ; images : 0-19 J1, 20-39 J2, 40-42 balle, 43 ombre, 44 marque
SPR_BALL    equ 40
SPR_SHADOW  equ 43
SPR_MARK    equ 44
PIA_FORM    equ $01             ; $A7C0 : banque forme, bordure noire
PIA_COLOR   equ $00

; image décalée et couleur (<< 4) de chaque objet
obj_init
        fdb SHBUF+$200
        fcb $20                     ; marque : vert
        fdb SHBUF+$240
        fcb $00                     ; ombre : noir
        fdb SHBUF
        fcb $40                     ; J2 : bleu
        fdb SHBUF+$100
        fcb $10                     ; J1 : rouge
        fdb SHBUF+$280
        fcb $70                     ; balle : blanc

; adresse d'écran de chaque rangée de cases (rangée x 320) : rowaddr (gfx/tables.asm)

; --- Objets : état initial ------------------------------------------------------------
objs_reset
        ldy #OBJS
        ldx #obj_init
        ldb #NOBJ
or_l    pshs b
        clr O_VIS,y
        clr O_OVIS,y
        lda #$FF
        sta O_SHIFT,y
        sta O_OIMG,y
        ldd ,x++
        std O_BUF,y
        lda ,x+
        sta O_COL,y
        leay OBJ_SIZE,y
        puls b
        decb
        bne or_l
        clr dl_n
        rts

; --- Écran entier : fond noir, puis le stade (objets cachés) ---------------------------
court_screen
        lda #PIA_COLOR
        sta PIA_A
        ldx #0
        clra
cs_c    sta ,x+                     ; couleur : noir sur noir
        cmpx #8000
        bne cs_c
        lda #PIA_FORM
        sta PIA_A
        sta pia_a
        ldx #0
        clra
cs_f    sta ,x+
        cmpx #8000
        bne cs_f
        jsr objs_reset
        clr cp_r
cs_r    clr cp_c
cs_k    jsr compose_cell
        inc cp_c
        lda cp_c
        cmpa #32
        bne cs_k
        inc cp_r
        lda cp_r
        cmpa #25
        bne cs_r
        rts

; --- Recomposition d'une case (cp_r, cp_c) -----------------------------------------------
compose_cell
        lda cp_r                    ; tuile
        ldb #32
        mul
        addb cp_c
        adca #0
        ldx #court_map
        ldb d,x
        lda #16
        mul
        ldx #court_tiles
        leax d,x
        ldd ,x
        std fbuf
        ldd 2,x
        std fbuf+2
        ldd 4,x
        std fbuf+4
        ldd 6,x
        std fbuf+6
        ldd 8,x
        std cbuf
        ldd 10,x
        std cbuf+2
        ldd 12,x
        std cbuf+4
        ldd 14,x
        std cbuf+6
        lda cp_r                    ; 1re ligne de la case
        ldb #8
        mul
        std cp_row8
        ldy #OBJS                   ; objets qui touchent la case
        ldb #NOBJ
cc_o    pshs b
        tst O_VIS,y
        beq cc_n
        lda cp_c
        cmpa O_CX0,y
        blo cc_n
        cmpa O_CX1,y
        bhi cc_n
        lda cp_r
        cmpa O_CY0,y
        blo cc_n
        cmpa O_CY1,y
        bhi cc_n
        bsr merge_obj
cc_n    leay OBJ_SIZE,y
        puls b
        decb
        bne cc_o
        ; écriture : 8 octets de forme, puis 8 de couleur
        ldx #rowaddr
        ldb cp_r
        lslb
        abx
        ldu ,x
        ldb cp_c
        addb #4
        leau b,u
        lda fbuf
        sta ,u
        lda fbuf+1
        sta 40,u
        lda fbuf+2
        sta 80,u
        lda fbuf+3
        sta 120,u
        lda fbuf+4
        sta 160,u
        lda fbuf+5
        sta 200,u
        lda fbuf+6
        sta 240,u
        lda fbuf+7
        sta 280,u
        lda #PIA_COLOR
        sta PIA_A
        lda cbuf
        sta ,u
        lda cbuf+1
        sta 40,u
        lda cbuf+2
        sta 80,u
        lda cbuf+3
        sta 120,u
        lda cbuf+4
        sta 160,u
        lda cbuf+5
        sta 200,u
        lda cbuf+6
        sta 240,u
        lda cbuf+7
        sta 280,u
        lda #PIA_FORM
        sta PIA_A
        rts

; Y = objet qui touche la case : fusionne ses lignes dans fbuf / cbuf
merge_obj
        ldd O_OY,y
        subd cp_row8                ; D = y objet - y case
        bpl mo_pos
        coma                        ; l'objet commence au-dessus : ligne -D de l'image
        comb
        addd #1
        stb m_srow
        clr m_k0
        bra mo_cnt
mo_pos  stb m_k0                    ; l'objet commence dans la case, ligne B
        clr m_srow
mo_cnt  lda O_H,y                   ; lignes = min(H - srow, 8 - k0)
        suba m_srow
        ldb #8
        subb m_k0
        pshs b
        cmpa ,s+
        bls mo_n
        tfr b,a
mo_n    sta cp_n
        ldb O_NB,y                  ; pas d'une ligne : 2 x nb
        lslb
        stb cp_stride+1
        clr cp_stride
        lda m_srow                  ; source : image décalée + srow x pas + colonne
        mul
        addd O_BUF,y
        tfr d,x
        ldb cp_c
        subb O_BX0,y
        abx
        ldb O_NB,y                  ; U : plan d'encre
        leau b,x
        lda O_COL,y
        sta cp_colhi
        pshs y
        ldy #fbuf
        ldb m_k0
        leay b,y
mo_row  lda ,x                      ; forme = (fond AND NOT masque) OR encre
        coma
        anda ,y
        ora ,u
        sta ,y
        ldb ,u                      ; de l'encre : couleur de l'objet dans ce groupe
        beq mo_ni
        lda 8,y
        anda #$0F
        ora cp_colhi
        sta 8,y
mo_ni   ldd cp_stride
        leax d,x
        leau d,u
        leay 1,y
        dec cp_n
        bne mo_row
        puls y,pc

; --- Cases à redessiner ----------------------------------------------------------------
; mk_x0..mk_x1, mk_y0..mk_y1 (cases, déjà limitées au stade)
mark_rect
        lda mk_y0
mr_r    sta mk_c
        ldb #32
        mul
        addb mk_x0
        adca #0
        addd #DIRTY
        tfr d,x
        ldb mk_x0
mr_c    tst ,x
        bne mr_n
        lda dl_n
        cmpa #DLIST_MAX
        bhs mr_n
        inc ,x
        pshs x,b
        ldx #DLIST
        ldb dl_n
        clra
        lslb
        rola
        leax d,x
        lda mk_c
        sta ,x
        lda ,s
        sta 1,x
        puls b,x
        inc dl_n
mr_n    leax 1,x
        incb
        cmpb mk_x1
        bls mr_c
        lda mk_c
        inca
        cmpa mk_y1
        bls mr_r
        rts

; Recompose toutes les cases de la liste, puis la vide
compose_dirty
        ldx #DLIST
        lda dl_n
        beq cd_done
cd_l    pshs a,x
        jsr poll_frame
        ldd ,x
        sta cp_r
        stb cp_c
        ldb #32                     ; case propre
        mul
        addb cp_c
        adca #0
        addd #DIRTY
        tfr d,x
        clr ,x
        jsr compose_cell
        puls a,x
        leax 2,x
        deca
        bne cd_l
        clr dl_n
cd_done rts

; --- Mise à jour d'un objet --------------------------------------------------------------
; A = objet. Caché : hide_obj. Visible : n_img, n_ptr, n_x, n_y (set_obj les calcule).
obj_ptr
        ldb #OBJ_SIZE
        mul
        addd #OBJS
        tfr d,y
        rts

hide_obj
        bsr obj_ptr
        tst O_OVIS,y
        beq ho_r
        bsr mark_old
        clr O_OVIS,y
ho_r    clr O_VIS,y
        rts

; ancien rectangle -> cases à redessiner
mark_old
        ldd O_OCX0,y
        std mk_x0
        ldd O_OCY0,y
        std mk_y0
        jmp mark_rect

; A = objet, B = image, pj_ax / pj_ay = point d'ancrage (x, y GB)
set_obj
        pshs a
        stb n_img
        ldx #spr_img
        lslb
        abx
        ldx ,x
        stx n_ptr
        ldb 2,x                     ; x = ancrage + x0
        sex
        addd pj_ax
        std n_x
        ldb 3,x                     ; y = ancrage - 16 + y0
        sex
        addd pj_ay
        subd #16
        std n_y
        puls a
        bsr obj_ptr
        ; inchangé ?
        tst O_OVIS,y
        beq so_new
        lda n_img
        cmpa O_OIMG,y
        bne so_chg
        ldd n_x
        cmpd O_OX,y
        bne so_chg
        ldd n_y
        cmpd O_OY,y
        bne so_chg
        lda #1
        sta O_VIS,y
        rts
so_chg  bsr mark_old
so_new  ldx n_ptr
        lda ,x                      ; nb = largeur + 1, hauteur
        inca
        sta O_NB,y
        lda 1,x
        sta O_H,y
        lda n_x+1                   ; image décalée à refaire ?
        anda #7
        cmpa O_SHIFT,y
        bne so_sh
        lda n_img
        cmpa O_OIMG,y
        beq so_rect
so_sh   lda n_x+1
        anda #7
        sta O_SHIFT,y
        jsr build_shift
so_rect ldd n_x                     ; colonne du 1er octet : x >> 3 (signé)
        asra
        rorb
        asra
        rorb
        asra
        rorb
        stb O_BX0,y
        tstb                        ; rectangle limité au stade (colonnes 0-31)
        bpl so_x0
        clrb
so_x0   stb O_CX0,y
        ldb O_BX0,y
        addb O_NB,y
        decb
        bmi so_off
        cmpb #31
        ble so_x1
        ldb #31
so_x1   stb O_CX1,y
        cmpb O_CX0,y
        blt so_off
        ldd n_y                     ; rangées : y >> 3 ... (y + h - 1) >> 3
        asra
        rorb
        asra
        rorb
        asra
        rorb
        tsta
        bpl so_y0
        clrb
so_y0   cmpb #24
        bgt so_off
        stb O_CY0,y
        ldb O_H,y
        clra
        addd n_y
        subd #1
        bmi so_off
        asra
        rorb
        asra
        rorb
        asra
        rorb
        cmpb #24
        bls so_y1
        ldb #24
so_y1   stb O_CY1,y
        ; visible : nouveau rectangle marqué, état retenu
        lda #1
        sta O_VIS,y
        sta O_OVIS,y
        lda n_img
        sta O_OIMG,y
        ldd n_x
        std O_OX,y
        ldd n_y
        std O_OY,y
        ldd O_CX0,y
        std O_OCX0,y
        std mk_x0
        ldd O_CY0,y
        std O_OCY0,y
        std mk_y0
        jmp mark_rect
so_off  clr O_VIS,y                 ; hors du stade
        clr O_OVIS,y
        rts

; Image décalée de l'objet Y (image n_ptr, décalage O_SHIFT) -> O_BUF
build_shift
        ldx n_ptr
        lda ,x
        sta sh_wb
        lda 1,x
        sta sh_rows
        leax 4,x
        ldu O_BUF,y
        lda O_SHIFT,y
        sta sh_s
        beq bs_copy
        ldb #1                      ; multiplicateur : 2^(8 - décalage)
        lda #8
        suba sh_s
bs_m    lslb
        deca
        bne bs_m
        stb sh_mul
bs_row  bsr bs_plane                ; masque
        bsr bs_plane                ; encre
        dec sh_rows
        bne bs_row
        rts
bs_plane
        clr sh_prev
        lda sh_wb
        sta sh_cnt
bs_b    ldb ,x+                     ; A = octet >> s, B = octet << (8 - s)
        lda sh_mul
        mul
        ora sh_prev
        sta ,u+
        stb sh_prev
        dec sh_cnt
        bne bs_b
        lda sh_prev
        sta ,u+
        rts
bs_copy bsr bs_cp                   ; décalage 0 : copie, octet final à 0
        bsr bs_cp
        dec sh_rows
        bne bs_copy
        rts
bs_cp   ldb sh_wb
bs_c    lda ,x+
        sta ,u+
        decb
        bne bs_c
        clr ,u+
        rts

; --- Les objets d'une trame (comme $1B50, $486F, $4A90, $0951) ---------------------------
prepare_all
        ; balle et ombre ($1B50)
        lda B_ST
        bne pa_ball
        lda #OBJ_BALL
        jsr hide_obj
        lda #OBJ_SHADOW
        jsr hide_obj
        bra pa_mark
pa_ball ldx #B_Y
        jsr proj
        jsr anchor
        lda #OBJ_SHADOW             ; ombre : au sol
        ldb #SPR_SHADOW
        jsr set_obj
        jsr lift                    ; balle : moins la hauteur ($09C2)
        jsr anchor
        ldb #SPR_BALL               ; taille : hauteur < $40, < $60, sinon grande
        lda B_Z
        cmpa #$40
        blo pa_sz
        incb
        cmpa #$60
        blo pa_sz
        incb
pa_sz   lda #OBJ_BALL
        jsr set_obj
pa_mark lda B_MARK                  ; marque de rebond ($0951)
        bne pa_mv
        lda #OBJ_MARK
        jsr hide_obj
        bra pa_p2
pa_mv   ldx #B_MARKY
        jsr proj_mark
        jsr anchor
        lda #OBJ_MARK
        ldb #SPR_MARK
        jsr set_obj
pa_p2   lda P2_STATE                ; joueur 2 ($4A90) : invisible si (état AND 3) = 0
        anda #3
        bne pa_p2v
        lda #OBJ_P2
        jsr hide_obj
        bra pa_p1
pa_p2v  ldx #P2_Y
        jsr proj
        jsr anchor
        ldb P2_FRAME
        addb #SPR_P2
        lda #OBJ_P2
        jsr set_obj
pa_p1   lda P1_STATE                ; joueur 1 ($486F)
        anda #3
        bne pa_p1v
        lda #OBJ_P1
        jmp hide_obj
pa_p1v  ldx #P1_Y
        jsr proj
        jsr anchor
        ldb P1_FRAME
        lda #OBJ_P1
        jmp set_obj

; pj_x, pj_y (projection) -> point d'ancrage 16 bits
anchor
        clra
        ldb pj_x
        std pj_ax
        ldb pj_y
        std pj_ay
        rts
