; ===========================================================================
; vdp.asm - accès au VDP TMS9918A
;
; Deux façons d'écrire dans la mémoire vidéo, et seulement deux :
;   1. écran éteint (screen_off ... screen_on) : interruptions coupées, on
;      écrit à pleine vitesse (vdp_write, vdp_fill) ;
;   2. dans l'interruption de trame (vblank_update) : motifs des sprites qui
;      changent, table des sprites, textes (add_job).
; La boucle principale ne touche jamais au VDP écran allumé.
; ===========================================================================

; A = valeur, C = numéro de registre
vdp_reg:
        out (VDP_CTRL),a
        ld a,c
        or $80
        out (VDP_CTRL),a
        ret

; HL = adresse VRAM (écriture)
vdp_waddr:
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        or $40
        out (VDP_CTRL),a
        ret

; HL = source, DE = adresse VRAM, BC = nombre d'octets (écran éteint)
vdp_write:
        ex de,hl
        call vdp_waddr
        ex de,hl
.l:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.l
        ret

; HL = adresse VRAM, BC = nombre d'octets, E = valeur (écran éteint)
vdp_fill:
        call vdp_waddr
.l:
        ld a,e
        out (VDP_DATA),a
        dec bc
        ld a,b
        or c
        jr nz,.l
        ret

; Écran éteint, interruptions coupées : la boucle principale peut écrire en VRAM.
screen_off:
        di
        ld a,R1_OFF
        ld c,1
        jp vdp_reg

; Écran allumé, interruption de trame en marche.
screen_on:
        xor a
        ld (frame_ready),a
        ld (job_n),a
        ld a,R1_ON_INT
        ld c,1
        call vdp_reg
        ei
        ret

vdp_regs:
        db $02                      ; R0 : mode graphique 2
        db R1_OFF                   ; R1 : 16 Ko, écran éteint, sprites 16x16
        db VR_NAME / $400           ; R2 : carte en $1800
        db $FF                      ; R3 : couleurs en $2000 (mode 2)
        db $03                      ; R4 : motifs en $0000 (mode 2)
        db VR_SAT / $80             ; R5 : attributs des sprites en $1B00
        db VR_SPAT / $800           ; R6 : motifs des sprites en $3800
        db $01                      ; R7 : bordure noire

vdp_init:
        ld hl,vdp_regs
        ld c,0
.r:
        ld a,(hl)
        call vdp_reg
        inc hl
        inc c
        ld a,c
        cp 8
        jr nz,.r
        ld hl,0                     ; VRAM à zéro
        ld bc,$4000
        ld e,0
        jp vdp_fill

; Police (motifs FONT_BASE-255, blanc sur noir) dans les 3 tiers (écran éteint)
load_font:
        ld de,VR_PAT + FONT_BASE * 8
        call .third
        ld de,VR_PAT + $800 + FONT_BASE * 8
        call .third
        ld de,VR_PAT + $1000 + FONT_BASE * 8
.third:
        push de
        ld hl,font
        ld bc,64 * 8
        call vdp_write
        pop hl
        ld de,VR_COL - VR_PAT
        add hl,de
        ld bc,64 * 8
        ld e,TEXT_COLOR
        jp vdp_fill

; Carte entière : espaces (écran éteint)
clear_names:
        ld hl,VR_NAME
        ld bc,768
        ld e,FONT_BASE
        jp vdp_fill

; Aucun sprite (écran éteint)
no_sprites:
        ld hl,VR_SAT
        ld bc,1
        ld e,$D0
        jp vdp_fill

; --- Travaux de texte : copie RAM -> carte, faite par l'interruption -----------------------
; HL = adresse VRAM, DE = source, B = longueur. À appeler quand frame_ready = 0.
add_job:
        ld a,(job_n)
        cp MAX_JOBS
        ret nc
        push hl                     ; VRAM
        ld l,a                      ; 5 octets par travail
        add a,a
        add a,a
        add a,l
        ld l,a
        ld h,0
        push de
        ld de,jobs
        add hl,de
        pop de
        ex (sp),hl                  ; HL = VRAM, (SP) = case
        ld c,l
        ld a,h
        pop hl
        ld (hl),c
        inc hl
        ld (hl),a
        inc hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),b
        ld hl,job_n
        inc (hl)
        ret

; --- Retour de trame (appelé par l'interruption) --------------------------------------------
; Budget : ~70 lignes x 228 cycles (~15 900 T) avant le haut de l'image.
vblank_update:
        ; 1. motifs des sprites dont l'image a changé
        ld b,0
.obj:
        ld hl,up_img
        ld a,b
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        cp $FF
        jr z,.next
        ld (hl),$FF
        push bc
        ld hl,obj_slot
        ld c,b
        ld b,0
        add hl,bc
        ld e,(hl)
        call up_image
        pop bc
.next:
        inc b
        ld a,b
        cp NOBJ
        jr nz,.obj
        ; 2. table des sprites
        ld a,(sat_len)
        or a
        jr z,.jobs
        ld hl,VR_SAT
        call vdp_waddr
        ld a,(sat_len)
        ld b,a
        ld c,VDP_DATA
        ld hl,sat_buf
        otir
.jobs:
        ; 3. textes
        ld a,(job_n)
        or a
        ret z
        ld hl,jobs
.j:
        push af
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ex de,hl
        call vdp_waddr
        ex de,hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld b,(hl)
        inc hl
        push hl
        ex de,hl
        ld c,VDP_DATA
        otir
        pop hl
        pop af
        dec a
        jr nz,.j
        ld (job_n),a
        ret

; A = image, E = premier emplacement (sprite 16x16) : recopie ses motifs
up_image:
        ld l,a
        ld h,0
        add hl,hl
        ld bc,spr_img
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                      ; HL = image
        push hl
        ld l,e                      ; VRAM = VR_SPAT + emplacement x 32
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,VR_SPAT
        add hl,de
        call vdp_waddr
        pop hl
        ld b,(hl)                   ; nombre de sprites
        inc hl
.s:
        push bc
        inc hl                      ; dx, dy, couleur
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ex de,hl
        ld c,VDP_DATA
        DUP 32
        outi
        EDUP
        pop hl
        pop bc
        djnz .s
        ret
