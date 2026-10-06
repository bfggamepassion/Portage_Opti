; ===========================================================================
; text.asm - score et annonces
;
; Les textes sont des motifs de la police (FONT_BASE + code - 32), écrits
; dans la carte par la NMI (add_job) à partir de tampons en RAM :
;   score_buf : cadre du score, rangées 0-4, colonnes 25-31 (dans le public)
;       YOU CPU
;        15  30    points
;         6   4    jeux, set 1
;         ...      sets 2 et 3
;   ann_buf   : annonces, rangée 1 (mur du fond), colonnes 8-23
; ===========================================================================

SCORE_COL   equ 25
ANN_ROW     equ 1
ANN_COL     equ 8

; A = caractère (32-95) -> (sb_ptr), puis avance
sb_char:
        push hl
        ld hl,(sb_ptr)
        add a,FONT_BASE - 32
        ld (hl),a
        inc hl
        ld (sb_ptr),hl
        pop hl
        ret

; HL = chaîne (0 à la fin)
sb_str:
        ld a,(hl)
        or a
        ret z
        call sb_char
        inc hl
        jr sb_str

; A = nombre 0-99 sur 2 caractères (espace à la place du zéro des dizaines)
sb_num2:
        ld b,'0'-1
.tens:
        inc b
        sub 10
        jr nc,.tens
        add a,10+'0'
        push af
        ld a,b
        cp '0'
        jr nz,.t
        ld a,' '
.t:
        call sb_char
        pop af
        jp sb_char

; --- Score ------------------------------------------------------------------------
show_score:
        ld hl,W_PTS1
        ld de,shown_score
        ld b,2
.c1:
        ld a,(de)
        cp (hl)
        jr nz,show_score_force
        inc hl
        inc de
        djnz .c1
        ld hl,W_GAMES1
        ld b,6
.c2:
        ld a,(de)
        cp (hl)
        jr nz,show_score_force
        inc hl
        inc de
        djnz .c2
        jr show_ann
show_score_force:
        ld hl,W_PTS1
        ld de,shown_score
        ldi
        ldi
        ld hl,W_GAMES1
        ld bc,6
        ldir
        ld hl,score_buf
        ld (sb_ptr),hl
        ld hl,txt_head
        call sb_str
        ld a,(W_PTS1)
        call sb_points
        ld a,' '
        call sb_char
        ld a,(W_PTS2)
        call sb_points
        ld hl,W_GAMES1
.g:
        push hl
        ld a,' '
        call sb_char
        ld a,(hl)
        call sb_num2
        ld a,' '
        call sb_char
        ld a,' '
        call sb_char
        pop hl
        push hl
        inc hl                      ; W_GAMES2 = W_GAMES1 + 3
        inc hl
        inc hl
        ld a,(hl)
        call sb_num2
        pop hl
        inc hl
        ld a,l
        cp (W_GAMES1 + 3) & $FF
        jr nz,.g
        ld hl,VR_NAME + SCORE_COL   ; 5 rangées de 7
        ld de,score_buf
        ld c,5
.j:
        ld b,7
        push hl
        push de
        push bc
        call add_job
        pop bc
        pop de
        pop hl
        push bc
        ld bc,32
        add hl,bc
        ex de,hl
        ld bc,7
        add hl,bc
        ex de,hl
        pop bc
        dec c
        jr nz,.j
show_ann:
        ld a,(H_ANN)
        bit 6,a
        jr nz,.a
        xor a
.a:
        ld hl,shown_ann
        cp (hl)
        ret z
        ld (hl),a
        or a
        ld hl,0
        jr z,.p                     ; plus d'annonce : on efface
        and $0F
        ld hl,txt_fault
        cp 4
        jr z,.p
        ld hl,txt_let
        cp 5
        jr z,.p
        ld hl,txt_out
        cp 6
        jr z,.p
        cp 1
        ret nz
        ld a,(W_PTS1)
        ld c,a
        ld a,(W_PTS2)
        cp 6
        jr z,.adv
        ld b,a
        ld a,c
        cp 6
        jr z,.adv
        cp 5
        ret nz
        ld a,b
        cp 5
        ret nz
        ld hl,txt_deuce
        jr .p
.adv:
        ld hl,txt_adv
.p:
        ; (suite dans announce)

; HL = texte (0 : effacer) : rangée des annonces = mur du stade + texte centré
announce:
        push hl
        ld hl,court_map + ANN_ROW * 32 + ANN_COL
        ld de,ann_buf
        ld bc,16
        ldir
        pop hl
        ld a,h
        or l
        jr z,.job
        push hl                     ; longueur -> colonne (16 - n) / 2
        ld b,0
.len:
        ld a,(hl)
        or a
        jr z,.lend
        inc b
        inc hl
        jr .len
.lend:
        ld a,16
        sub b
        srl a
        ld e,a
        ld d,0
        ld hl,ann_buf
        add hl,de
        ld (sb_ptr),hl
        pop hl
        call sb_str
.job:
        ld hl,VR_NAME + ANN_ROW * 32 + ANN_COL
        ld de,ann_buf
        ld b,16
        jp add_job

; A = code de points GB -> 3 caractères (1:0 2:15 3:30 4/5:40 6:AD 0:40 ; >= 7 tie-break)
sb_points:
        push af
        ld a,' '
        call sb_char
        pop af
        cp 7
        jr c,.n
        sub 7
        jp sb_num2
.n:
        add a,a
        ld l,a
        ld h,0
        ld de,points_txt
        add hl,de
        ld a,(hl)
        call sb_char
        inc hl
        ld a,(hl)
        jp sb_char

points_txt: db "40", " 0", "15", "30", "40", "40", "AD"
txt_head:   db "YOU CPU",0
txt_fault:  db " FAULT ",0
txt_let:    db " LET ",0
txt_out:    db " OUT ",0
txt_deuce:  db " DEUCE ",0
txt_adv:    db " ADVANTAGE ",0
