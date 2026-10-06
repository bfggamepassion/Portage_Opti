; ===========================================================================
; update.asm - mise à jour de l'écran, juste après le balayage vertical
;
; Tous les sprites sont en XOR : le résultat ne dépend pas de l'ordre, et
; chaque sprite qui a changé est effacé puis aussitôt redessiné, dans l'ordre
; du balayage (de haut en bas) : il ne disparaît que le temps de son propre
; dessin.
; ===========================================================================

draw_all:
        call mark_changed
        call build_tasks
.next:
        ld hl,tasks                 ; tâche la plus haute à l'écran
        ld b,NSLOTS
        ld c,$FF
        ld de,0
.find:
        ld a,(hl)
        cp c
        jr nc,.nf
        ld c,a
        ld d,h
        ld e,l
.nf:
        inc hl
        inc hl
        djnz .find
        ld a,c
        cp $FF
        ret z
        ex de,hl
        ld (hl),$FF                 ; tâche faite
        inc hl
        ld a,(hl)                   ; emplacement : effacer puis dessiner
        push af
        call xor_erase
        pop af
        call xor_draw
        jr .next

tasks:  ds 2 * NSLOTS           ; (clé = ligne la plus haute, emplacement) ; clé $FF = rien

; Une tâche par emplacement qui a changé
build_tasks:
        ld hl,tasks
        xor a
.s:
        push af
        push hl
        call slot_ix
        pop hl
        ld e,$FF
        ld a,(ix+ST_DIRTY)
        or a
        call nz,top_line
        ld (hl),e
        inc hl
        pop af
        ld (hl),a
        inc hl
        inc a
        cp NSLOTS
        jr c,.s
        ret

; IX = emplacement -> E = ligne la plus haute (ancienne place, nouvelle place)
top_line:
        ld e,$FE
        ld a,(ix+ST_SROWS)
        or a
        jr z,.n
        ld a,(ix+ST_SY)
        cp e
        jr nc,.n
        ld e,a
.n:
        ld a,(ix+ST_ON)
        or a
        ret z
        ld a,(ix+ST_Y)
        cp e
        ret nc
        ld e,a
        ret

; Emplacement changé : à afficher et différent de ce qui est dessiné, ou
; dessiné et plus à afficher -> ST_DIRTY
mark_changed:
        ld ix,SlotTab
        ld b,NSLOTS
.m:
        ld c,(ix+ST_ON)
        ld e,(ix+ST_SROWS)          ; E = lignes dessinées (0 = rien)
        ld a,c
        or e
        jr z,.clean                 ; rien à dessiner, rien de dessiné
        ld a,c
        or a
        jr z,.dirty                 ; dessiné, plus à afficher
        ld a,e
        or a
        jr z,.dirty                 ; à afficher, rien de dessiné
        ld a,(ix+ST_PTR)            ; même image, même place ?
        cp (ix+ST_SPTR)
        jr nz,.dirty
        ld a,(ix+ST_PTR+1)
        cp (ix+ST_SPTR+1)
        jr nz,.dirty
        ld a,(ix+ST_Y)
        cp (ix+ST_SY)
        jr nz,.dirty
        ld a,(ix+ST_COL)
        cp (ix+ST_SCOL)
        jr nz,.dirty
        ld a,(ix+ST_H)
        cp (ix+ST_SROWS)
        jr nz,.dirty
.clean:
        ld (ix+ST_DIRTY),0
        jr .n
.dirty:
        ld (ix+ST_DIRTY),1
.n:
        ld de,16
        add ix,de
        djnz .m
        ret
