; ===========================================================================
; render.asm - décor du stade et sprites (joueurs, balle, ombre, marque)
;
; Comme les routines d'affichage de la ROM ($486F, $4A90, $1B50), avec la
; projection du jeu réécrite en Z80 natif (proj.asm). L'écran montre le stade
; GB à partir de la rangée 2 : x écran = x GB, y écran = y GB - 16.
;
; prepare_all remplit sat_buf (table des sprites, envoyée par la NMI) et
; demande la recopie des motifs d'un objet quand son image change (up_img).
; Sprites du TMS9918A : 4 au plus par ligne. Balle et ombre passent en
; premier (toujours visibles) ; l'ordre des joueurs et de leurs sprites
; s'inverse à chaque trame, pour qu'un dépassement clignote au lieu de
; faire disparaître toujours le même morceau.
; ===========================================================================

OBJ_BALL    equ 0
OBJ_SHADOW  equ 1
OBJ_MARK    equ 2
OBJ_P1      equ 3
OBJ_P2      equ 4
NOBJ        equ 5
SPR_P2      equ 20              ; images : 0-19 J1, 20-39 J2, 40-42 balle, 43 ombre, 44 marque
SPR_BALL    equ 40
SPR_SHADOW  equ 43
SPR_MARK    equ 44

; premier emplacement (sprite 16x16) des motifs de chaque objet
obj_slot:   db 16, 17, 18, 0, 8

; --- Décor (écran éteint) ------------------------------------------------------------
court_screen:
        call screen_off
        ld hl,court_pat0
        ld de,VR_PAT
        ld bc,COURT_N0 * 8
        call vdp_write
        ld hl,court_col0
        ld de,VR_COL
        ld bc,COURT_N0 * 8
        call vdp_write
        ld hl,court_pat1
        ld de,VR_PAT + $800
        ld bc,COURT_N1 * 8
        call vdp_write
        ld hl,court_col1
        ld de,VR_COL + $800
        ld bc,COURT_N1 * 8
        call vdp_write
        ld hl,court_pat2
        ld de,VR_PAT + $1000
        ld bc,COURT_N2 * 8
        call vdp_write
        ld hl,court_col2
        ld de,VR_COL + $1000
        ld bc,COURT_N2 * 8
        call vdp_write
        call load_font
        ld hl,court_map
        ld de,VR_NAME
        ld bc,768
        call vdp_write
        call no_sprites
        call spr_reset
        jp screen_on

; Aucun objet affiché, toutes les images à recopier
spr_reset:
        ld hl,cur_img
        ld b,NOBJ
.c:
        ld (hl),$FE
        inc hl
        djnz .c
        ld b,NOBJ                   ; up_img suit cur_img
.u:
        ld (hl),$FF
        inc hl
        djnz .u
        xor a
        ld (sat_len),a
        ret

; --- Sprites d'une trame -------------------------------------------------------------
prepare_all:
        ld hl,sat_buf
        ld (sat_ptr),hl
        ld a,(frames)
        and 1
        ld (spr_dir),a
        ; balle et ombre ($1B50)
        ld a,(B_ST)
        or a
        jr z,.mark
        ld hl,B_Y
        call proj
        push bc                     ; ombre : au sol
        call lift                   ; balle : moins la hauteur ($09C2)
        ld a,(B_Z)                  ; taille : hauteur < $40, < $60, sinon grande
        ld e,SPR_BALL
        cp $40
        jr c,.sz
        inc e
        cp $60
        jr c,.sz
        inc e
.sz:
        ld a,OBJ_BALL
        call put_obj
        pop bc
        ld e,SPR_SHADOW
        ld a,OBJ_SHADOW
        call put_obj
.mark:
        ; marque de rebond ($0951)
        ld a,(B_MARK)
        or a
        jr z,.pl
        ld hl,B_MARKY
        call proj_mark
        ld e,SPR_MARK
        ld a,OBJ_MARK
        call put_obj
.pl:
        ld a,(spr_dir)
        or a
        jr nz,.p21
        call put_p1
        call put_p2
        jr .end
.p21:
        call put_p2
        call put_p1
.end:
        ld hl,(sat_ptr)
        ld (hl),$D0                 ; fin de la table
        ld de,sat_buf - 1
        or a
        sbc hl,de
        ld a,l
        ld (sat_len),a
        ret

; joueur 1 ($486F) : invisible si (état AND 3) = 0
put_p1:
        ld a,(P1_STATE)
        and 3
        ret z
        ld hl,P1_Y
        call proj
        ld a,(P1_FRAME)
        ld e,a
        ld a,OBJ_P1
        jr put_obj

; joueur 2 ($4A90)
put_p2:
        ld a,(P2_STATE)
        and 3
        ret z
        ld hl,P2_Y
        call proj
        ld a,(P2_FRAME)
        add a,SPR_P2
        ld e,a
        ld a,OBJ_P2
        ; (suite dans put_obj)

; A = objet, E = image, B = y GB, C = x GB (point d'ancrage)
put_obj:
        ld (po_obj),a
        ld hl,cur_img               ; image changée : motifs à recopier
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        cp e
        jr z,.same
        ld (hl),e
        ld a,l
        add a,NOBJ                  ; up_img
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld (hl),e
.same:
        ld l,b                      ; y écran = y GB - 16
        ld h,0
        push de
        ld de,-16
        add hl,de
        ld (po_y),hl
        ld l,c
        ld h,0
        ld (po_x),hl
        ld a,(po_obj)               ; 1er motif = emplacement x 4
        ld hl,obj_slot
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        add a,a
        add a,a
        ld (po_pat),a
        pop de
        ld l,e                      ; HL = image
        ld h,0
        add hl,hl
        ld de,spr_img
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,(hl)                   ; nombre de sprites
        or a
        ret z
        ld (po_n),a
        inc hl
        ld (po_base),hl
        ld a,(spr_dir)              ; sens de parcours : k croissant ou décroissant
        or a
        ld a,0
        jr z,.k
        ld a,(po_n)
        dec a
.k:
        ld (po_k),a
.each:
        ld a,(po_k)                 ; HL = sprite k (5 octets)
        ld l,a
        add a,a
        add a,a
        add a,l
        ld l,a
        ld h,0
        ld de,(po_base)
        add hl,de
        call put_spr
        ld a,(spr_dir)
        or a
        ld a,(po_k)
        jr nz,.dec
        inc a
        jr .nx
.dec:
        dec a
.nx:
        ld (po_k),a
        ld hl,po_n
        dec (hl)
        jr nz,.each
        ret

; HL = sprite (dx, dy, couleur, motif) de l'objet en cours, po_k = son rang
; -> une entrée de plus dans sat_buf, s'il est visible
put_spr:
        ld a,(hl)                   ; x = ancrage + dx
        inc hl
        ld e,a
        add a,a
        sbc a,a
        ld d,a
        push hl
        ld hl,(po_x)
        add hl,de
        ld a,h
        or a
        jr z,.xok
        inc a
        jr nz,.skip                 ; >= 256 (ou très à gauche)
        ld a,l                      ; x < 0 : décalage de 32 pixels (bit EC)
        cp $E0
        jr c,.skip
        add a,32
        ld (ps_x),a
        ld a,$80
        jr .xs
.xok:
        ld a,l
        ld (ps_x),a
        xor a
.xs:
        ld (ps_ec),a
        pop hl
        ld a,(hl)                   ; y = ancrage + dy
        inc hl
        ld e,a
        add a,a
        sbc a,a
        ld d,a
        push hl
        ld hl,(po_y)
        add hl,de
        ld a,h
        or a
        jr nz,.neg
        ld a,l
        cp 192
        jr nc,.skip                 ; sous l'écran
        jr .yok
.neg:
        inc a
        jr nz,.skip
        ld a,l
        cp $F1                      ; y >= -15 : en partie visible
        jr c,.skip
.yok:
        ld a,l
        dec a                       ; le TMS affiche le sprite à la ligne Y + 1
        ld (ps_y),a
        pop hl
        ld a,(ps_ec)                ; couleur + bit EC
        or (hl)
        ld e,a
        ld hl,(sat_ptr)
        ld a,(ps_y)
        ld (hl),a
        inc hl
        ld a,(ps_x)
        ld (hl),a
        inc hl
        ld a,(po_k)
        add a,a
        add a,a
        ld d,a
        ld a,(po_pat)
        add a,d
        ld (hl),a
        inc hl
        ld (hl),e
        inc hl
        ld (sat_ptr),hl
        ret
.skip:
        pop hl
        ret
