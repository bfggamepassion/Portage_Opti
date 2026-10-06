; ===========================================================================
; sprite.asm - sprites logiciels en mode 1 (CPC), dessinés en XOR
;
; Images (gfx/sprites_meta.asm) : les 4 décalages au pixel près sont
; fabriqués au démarrage (init_sprites) ; le dessin ne décale donc rien.
; Chaque ligne d'une image décalée est rognée : décalage (octets
; transparents à gauche), longueur, puis les seuls octets utiles.
; XOR : dessiner deux fois au même endroit rend le décor intact, sans rien
; sauvegarder ; l'encre 0 (transparente) ne change rien. Là où un sprite
; passe sur une ligne ou un autre sprite, les couleurs se mêlent.
;   1. spr_prepare (après la logique) : position, image, découpage vertical.
;   2. Juste après le balayage vertical (update.asm) : chaque sprite qui a
;      changé est effacé (xor_erase) puis aussitôt redessiné (xor_draw),
;      dans l'ordre du balayage.
; ===========================================================================

; Emplacements (NSLOTS) et numéros d'images : définis dans defs.asm.

; Bloc de 16 octets par emplacement
ST_ON    equ 0                  ; à dessiner
ST_PTR   equ 1                  ; 16 bits : image décalée (après découpage)
ST_W     equ 3                  ; largeur maximale (octets), pour les chevauchements
ST_H     equ 4                  ; lignes visibles
ST_Y     equ 5                  ; première ligne écran
ST_COL   equ 6                  ; colonne (octets)
ST_SROWS equ 8                  ; fond sauvegardé : lignes (0 = rien)
ST_SY    equ 9
ST_SCOL  equ 10
ST_SW    equ 11                 ; largeur maximale sauvegardée
ST_DIRTY equ 7                  ; à effacer et redessiner cette trame
ST_SPTR  equ 14                 ; 16 bits : image dessinée (décalages et longueurs)

; --- Fabrication des images décalées (au démarrage) ---------------------------
init_sprites:
        xor a
.img:
        ld (.i),a
        ld l,a                      ; source non décalée
        ld h,0
        add hl,hl
        ld de,spr_raw_tab
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (.src),hl
        ld a,(.i)
        ld e,a
        ld d,0
        ld hl,spr_htab
        add hl,de
        ld a,(hl)
        ld (.h),a
        ld a,(.i)                   ; largeur non décalée = spr_wtab[numéro x 4]
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld bc,spr_wtab
        add hl,bc
        ld a,(hl)
        ld (.wb),a
        xor a
.shift:
        ld (.s),a
        ld a,(.i)                   ; index = numéro x 4 + décalage
        add a,a
        add a,a
        ld hl,.s
        add a,(hl)
        ld e,a
        ld d,0
        ld hl,spr_wtab
        add hl,de
        ld a,(hl)
        ld (.w),a
        ld hl,spr_ptr
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (.dst),hl
        ld a,(.s)                   ; pages des tables SHR / CAR du décalage
        add a,a
        add a,SHR0_TAB >> 8
        ld (.shr+1),a
        inc a
        ld (.car+1),a
        ld hl,(.src)
        ld a,(.h)
        ld b,a
.row:
        push bc
        ld de,rowbuf                ; ligne décalée complète -> rowbuf
        ld c,0                      ; octet précédent
        ld a,(.w)
        ld b,a
        ld a,(.wb)
        ld (.k),a
.byte:
        ld a,(.k)                   ; au-delà de la largeur : 0
        or a
        ld a,0
        jr z,.pad
        ld a,(.k)
        dec a
        ld (.k),a
        ld a,(hl)
        inc hl
.pad:
        push hl
        push af
        ld l,c                      ; CAR[précédent]
.car:   ld h,0
        ld c,(hl)
        pop af
        ld l,a                      ; SHR[octet]
.shr:   ld h,0
        ld a,(hl)
        or c
        ld (de),a
        inc de
        ld c,l                      ; précédent = octet
        pop hl
        djnz .byte
        push hl
        call .trim
        pop hl
        pop bc
        djnz .row
        ld a,(.s)
        inc a
        cp 4
        jp nz,.shift
        ld a,(.i)
        inc a
        cp NSPRITES
        jp nz,.img
        ret
; rowbuf (.w octets) -> (.dst) : décalage, longueur, octets utiles
.trim:
        ld hl,rowbuf
        ld a,(.w)
        ld b,a
        ld c,0                      ; décalage
.first:
        ld a,(hl)
        or a
        jr nz,.found
        inc hl
        inc c
        djnz .first
        ld hl,(.dst)                ; ligne vide
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (.dst),hl
        ret
.found:
        push hl                     ; HL = premier octet utile
        ld hl,rowbuf-1              ; dernier octet utile : depuis la fin
        ld a,(.w)
        ld e,a
        ld d,0
        add hl,de
.last:
        ld a,(hl)
        or a
        jr nz,.lok
        dec hl
        jr .last
.lok:
        pop de
        or a
        sbc hl,de
        inc hl                      ; longueur
        ld b,l
        ex de,hl                    ; HL = premier octet utile
        ld de,(.dst)
        ld a,c
        ld (de),a                   ; décalage
        inc de
        ld a,b
        ld (de),a                   ; longueur
        inc de
        ld c,b
        ld b,0
        ldir
        ld (.dst),de
        ret
.i:     db 0
.s:     db 0
.h:     db 0
.w:     db 0
.wb:    db 0
.k:     db 0
.src:   dw 0
.dst:   dw 0
rowbuf: ds 8

; --- Emplacements ------------------------------------------------------------------
spr_init:
        ld ix,SlotTab
        ld b,NSLOTS
.l:
        ld (ix+ST_ON),0
        ld (ix+ST_SROWS),0
        ld de,16
        add ix,de
        djnz .l
        ret

; IX = emplacement A
slot_ix:
        add a,a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld ix,SlotTab
        add ix,de
        ret

spr_hide:
        call slot_ix
        ld (ix+ST_ON),0
        ret

; A = emplacement, E = image, HL = ancrage y (lignes écran, signé),
; BC = ancrage x (pixels écran)
spr_prepare:
        push hl
        push bc
        push de
        call slot_ix
        pop de
        ld d,0
        ld hl,spr_x0tab             ; x = ancrage + x0 (signé)
        add hl,de
        ld a,(hl)
        ld l,a
        rla
        sbc a,a
        ld h,a
        pop bc
        add hl,bc
        ld a,l
        and 3
        ld (.s),a
        srl h                       ; colonne = x / 4
        rr l
        srl h
        rr l
        ld (ix+ST_COL),l
        ld hl,spr_y0tab             ; y = ancrage + y0 (signé)
        add hl,de
        ld a,(hl)
        ld l,a
        rla
        sbc a,a
        ld h,a
        pop bc
        add hl,bc
        push hl                     ; y (signé)
        ld hl,spr_htab
        add hl,de
        ld a,(hl)
        ld (.h),a
        ld a,e                      ; index = numéro x 4 + décalage
        add a,a
        add a,a
        ld hl,.s
        add a,(hl)
        ld e,a
        ld hl,spr_wtab
        add hl,de
        ld a,(hl)
        ld (ix+ST_W),a
        ld hl,spr_ptr
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                      ; HL = image
        pop de                      ; DE = y
        bit 7,d
        jr z,.top_ok
.skip:                              ; découpage en haut : sauter -y lignes
        inc hl
        ld c,(hl)                   ; longueur de la ligne
        inc hl
        ld b,0
        add hl,bc
        ld a,(.h)
        dec a
        jr z,.off
        ld (.h),a
        inc de
        bit 7,d
        jr nz,.skip
.top_ok:
        ld a,d                      ; y >= 200 : invisible
        or a
        jr nz,.off
        ld a,e
        cp 200
        jr nc,.off
        ld (ix+ST_Y),a
        ld (ix+ST_PTR),l
        ld (ix+ST_PTR+1),h
        ld b,a                      ; découpage en bas : h = min(h, 200 - y)
        ld a,200
        sub b
        ld b,a
        ld a,(.h)
        cp b
        jr c,.hok
        ld a,b
.hok:
        ld (ix+ST_H),a
        ld (ix+ST_ON),1
        ret
.off:
        ld (ix+ST_ON),0
        ret
.s:     db 0
.h:     db 0

; --- Sprites en XOR (balle, ombre, marque) ------------------------------------------
; Dessiner deux fois au même endroit rend le décor intact : pas de sauvegarde.
; xor_draw : dessine l'emplacement A à sa nouvelle place (et la retient) ;
; xor_erase : l'efface de la place retenue.
xor_draw:
        call slot_ix
        ld a,(ix+ST_ON)
        or a
        ret z
        ld a,(ix+ST_W)
        ld (ix+ST_SW),a
        ld a,(ix+ST_H)
        ld (ix+ST_SROWS),a
        ld b,a
        ld a,(ix+ST_Y)
        ld (ix+ST_SY),a
        ld c,a
        ld a,(ix+ST_COL)
        ld (ix+ST_SCOL),a
        ld e,(ix+ST_PTR)
        ld d,(ix+ST_PTR+1)
        ld (ix+ST_SPTR),e
        ld (ix+ST_SPTR+1),d
        jr xor_rows

xor_erase:
        call slot_ix
        ld a,(ix+ST_SROWS)
        or a
        ret z
        ld (ix+ST_SROWS),0
        ld b,a
        ld c,(ix+ST_SY)
        ld a,(ix+ST_SCOL)
        ld e,(ix+ST_SPTR)
        ld d,(ix+ST_SPTR+1)
; B = lignes, C = première ligne, A = colonne, DE = image (lignes rognées)
xor_rows:
        push de
        push bc
        push af
        ld a,c
        call line_addr
        pop af
        ld e,a
        ld d,0
        add hl,de                   ; HL = écran
        pop bc
        pop de
.row:
        push bc
        push hl
        ld a,(de)                   ; décalage
        inc de
        add a,l
        ld l,a
        jr nc,.s1
        inc h
.s1:
        ld a,(de)                   ; longueur
        inc de
        or a
        jr z,.next
        ld b,a
.x:
        ld a,(de)
        inc de
        xor (hl)
        ld (hl),a
        inc hl
        djnz .x
.next:
        pop hl
        ld a,h                      ; ligne suivante
        add a,8
        ld h,a
        jp p,.nl
        ld bc,$C050
        add hl,bc
.nl:
        pop bc
        djnz .row
        ret
