; ===========================================================================
; menu.asm - écran de présentation et menu (flèches ou joystick)
;   haut/bas : choisir la ligne (niveau, sets, boutons)
;   gauche/droite : changer la valeur ; touches 1-4 : niveau
;   ESPACE, M ou un bouton : jouer
; Le décor du titre est dessiné écran éteint ; les valeurs qui changent
; passent par l'interruption (add_job).
; ===========================================================================

MENU_ROW    equ 15              ; 1re ligne du menu
CURSOR_COL  equ 7
VALUE_COL   equ 23

menu:
        call screen_off
        call spr_reset
        call clear_names
        call load_font
        ld hl,title_pat0
        ld de,VR_PAT
        ld bc,TITLE_N0 * 8
        call vdp_write
        ld hl,title_col0
        ld de,VR_COL
        ld bc,TITLE_N0 * 8
        call vdp_write
        ld hl,title_pat1
        ld de,VR_PAT + $800
        ld bc,TITLE_N1 * 8
        call vdp_write
        ld hl,title_col1
        ld de,VR_COL + $800
        ld bc,TITLE_N1 * 8
        call vdp_write
        ASSERT TITLE_N2 = 0
        ld hl,title_map
        ld de,VR_NAME
        ld bc,TITLE_ROWS * 32
        call vdp_write
        ld hl,menu_text             ; textes fixes : rangée, colonne, chaîne
.t:
        ld a,(hl)
        cp $FF
        jr z,.tdone
        inc hl
        ld e,(hl)                   ; DE = VR_NAME + rangée x 32 + colonne
        inc hl
        push hl
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld d,0
        add hl,de
        ld de,VR_NAME
        add hl,de
        call vdp_waddr
        pop hl
.c:
        ld a,(hl)
        inc hl
        or a
        jr z,.t
        add a,FONT_BASE - 32
        out (VDP_DATA),a
        jr .c
.tdone:
        call no_sprites
        call screen_on
        xor a
        ld (menu_sel),a
        ld a,$FF                    ; attendre qu'on relâche tout
        ld (menu_prev),a
        ld (key_prev),a
        call menu_refresh
.loop:
        ld a,1
        ld (frame_ready),a
        call wait_frame
        call read_pad
        ld c,a
        ld a,(menu_prev)
        cpl
        and c                       ; B = nouvellement appuyé
        ld b,a
        ld a,c
        ld (menu_prev),a
        ld a,b
        and PAD_A | PAD_B
        jr nz,.play
        ld a,(key_now)              ; pavé : 1-4 = niveau
        ld hl,key_prev
        cp (hl)
        ld (hl),a
        jr z,.dirs
        dec a
        cp 4
        jr nc,.dirs
        inc a
        ld (W_LEVEL),a
.dirs:
        bit 6,b                     ; haut
        jr z,.nu
        ld a,(menu_sel)
        dec a
        jp p,.su
        ld a,2
.su:
        ld (menu_sel),a
.nu:
        bit 7,b                     ; bas
        jr z,.nd
        ld a,(menu_sel)
        inc a
        cp 3
        jr c,.sd
        xor a
.sd:
        ld (menu_sel),a
.nd:
        ld a,b
        and PAD_L | PAD_R
        jr z,.done
        ld c,a
        ld a,(menu_sel)
        or a
        jr nz,.m1
        ld a,(W_LEVEL)              ; niveau 1-4
        bit 4,c
        jr z,.ll
        inc a
        cp 5
        jr c,.ls
        ld a,1
        jr .ls
.ll:
        dec a
        jr nz,.ls
        ld a,4
.ls:
        ld (W_LEVEL),a
        jr .done
.m1:
        dec a
        jr nz,.m2
        ld a,(sets)                 ; 1 ou 3 sets
        xor 2
        ld (sets),a
        jr .done
.m2:
        ld a,(two_buttons)          ; 1 ou 2 boutons
        xor 1
        ld (two_buttons),a
.done:
        call menu_refresh
        jp .loop
.play:
        ret

; Curseur et valeurs -> menu_buf, envoyés par l'interruption
menu_refresh:
        ld hl,menu_buf
        ld (sb_ptr),hl
        ld a,(menu_sel)
        ld c,a
        ld b,0
.cur:
        ld a,b
        cp c
        ld a,'>'
        jr z,.on
        ld a,' '
.on:
        call sb_char
        inc b
        ld a,b
        cp 3
        jr nz,.cur
        ld a,(W_LEVEL)
        add a,'0'
        call sb_char
        ld a,(sets)
        add a,'0'
        call sb_char
        ld a,(two_buttons)
        add a,'1'
        call sb_char
        ld hl,VR_NAME + MENU_ROW * 32 + CURSOR_COL
        ld de,menu_buf
        ld c,0
.j:
        push bc
        push hl
        push de
        ld b,1                      ; curseur
        call add_job
        pop de
        pop hl
        push hl
        push de
        ld bc,VALUE_COL - CURSOR_COL
        add hl,bc
        inc de
        inc de
        inc de
        ld b,1                      ; valeur
        call add_job
        pop de
        pop hl
        ld bc,32
        add hl,bc
        inc de
        pop bc
        inc c
        ld a,c
        cp 3
        jr nz,.j
        ret

;           rangée, colonne, texte
menu_text:
        db MENU_ROW, CURSOR_COL + 2, "LEVEL", 0
        db MENU_ROW + 1, CURSOR_COL + 2, "SETS", 0
        db MENU_ROW + 2, CURSOR_COL + 2, "BUTTONS", 0
        db 19, 3, "SPACE / FIRE A : HIT", 0
        db 20, 3, "M     / FIRE B : LOB", 0
        db 21, 3, "1 BUTTON: AUTO LOB AT NET", 0
        db 22, 7, "PRESS SPACE TO PLAY", 0
        db 23, 4, "BASED ON NINTENDO TENNIS", 0
        db $FF
