; ===========================================================================
; menu.asm - écran de présentation et menu, au clavier
;   1-4 : niveau ; S : 1 ou 3 sets ; ESPACE : jouer
; ===========================================================================

M_ROW       equ 9               ; 1re ligne du menu
M_VAL       equ 30              ; colonne des valeurs

clear_screen
        lda #PIA_COLOR
        sta PIA_A
        ldx #0
        clra
cls_c   sta ,x+
        cmpx #8000
        bne cls_c
        lda #PIA_FORM
        sta PIA_A
        ldx #0
        clra
cls_f   sta ,x+
        cmpx #8000
        bne cls_f
        rts

menu
        bsr clear_screen
        ldu #menu_text
mn_t    lda ,u+                     ; textes fixes : rangée, colonne, couleur, chaîne
        bmi mn_td
        sta txt_row
        lda ,u+
        sta txt_col
        lda ,u+
        sta txt_color
        tfr u,x
        jsr print_str
        tfr x,u
        bra mn_t
mn_td   lda #$FF                    ; attendre qu'on relâche tout
        sta menu_prev
mn_loop bsr menu_values
        jsr read_digit
        lda key_now
        bmi mn_k
        sta W_LEVEL
mn_k    clr tmp                     ; touches : bit 0 ESPACE, bit 1 S
        ldb #K_SPACE
        jsr key_test
        bmi mn_1
        inc tmp
mn_1    ldb #K_S
        jsr key_test
        bmi mn_2
        lda tmp
        ora #2
        sta tmp
mn_2    lda menu_prev               ; nouvellement appuyées
        coma
        anda tmp
        ldb tmp
        stb menu_prev
        bita #1
        bne mn_play
        bita #2
        beq mn_4
        ldb sets                    ; 1 <-> 3
        eorb #2
        stb sets
mn_4    bra mn_loop
mn_play rts

menu_values
        lda #TXT_WHITE
        sta txt_color
        lda #M_VAL
        sta txt_col
        lda #M_ROW
        sta txt_row
        lda W_LEVEL
        adda #'0'
        jsr draw_char
        lda #M_ROW+2
        sta txt_row
        lda sets
        adda #'0'
        jmp draw_char

;           rangée, colonne, couleur, texte
menu_text
        fcb 3,15,$30
        fcc "MO5 TENNIS"
        fcb 0
        fcb M_ROW,8,$70
        fcc "1-4  LEVEL"
        fcb 0
        fcb M_ROW+2,8,$70
        fcc "S    SETS"
        fcb 0
        fcb 17,8,$A0
        fcc "ARROWS : MOVE"
        fcb 0
        fcb 18,8,$A0
        fcc "SPACE  : HIT"
        fcb 0
        fcb 19,8,$A0
        fcc "AUTO LOB AT NET"
        fcb 0
        fcb 22,11,$F0
        fcc "PRESS SPACE TO PLAY"
        fcb 0
        fcb 24,8,$80
        fcc "BASED ON NINTENDO TENNIS"
        fcb 0
        fcb $FF
