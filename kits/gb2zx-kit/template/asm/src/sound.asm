; ===========================================================================
; sound.asm - bruitages beeper (48K) pour les numéros de son de la ROM
; La logique demande un son (S_SOUND -> sfx_req) ; play_sfx le joue après
; l'affichage. Chaque son ne bloque le processeur que quelques ms : les
; garder courts (un beeper occupe 100 % du CPU pendant qu'il sonne).
; ===========================================================================

play_sfx:
        ld a,(sfx_req)
        or a
        ret z
        ld c,a
        xor a
        ld (sfx_req),a
        ld hl,sfx_table
.find:
        ld a,(hl)
        or a
        ret z
        cp c
        jr z,.found
        inc hl
        inc hl
        inc hl
        inc hl
        jr .find
.found:
        inc hl
        ld a,(hl)                   ; période (0 = bruit)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)                   ; nombre de demi-périodes
        or a
        jr z,noise
; A = période, DE = demi-périodes
beep:
        ld c,a
        ld a,BORDER_COL
.l:
        xor $10
        out ($FE),a
        ld b,c
.w:
        djnz .w
        dec de
        ld h,a
        ld a,d
        or e
        ld a,h
        jr nz,.l
        and $EF
        out ($FE),a
        ret

; Bruit : demi-périodes tirées des octets de la ROM Spectrum ($0000...)
noise:
        ld hl,0
        ld a,BORDER_COL
.l:
        ld b,a
        ld a,(hl)
        and $1F
        or 1
        inc hl
        ld c,a
        ld a,b
        xor $10
        out ($FE),a
        ld b,c
.w:
        djnz .w
        dec de
        ld b,a
        ld a,d
        or e
        ld a,b
        jr nz,.l
        and $EF
        out ($FE),a
        ret

; numéro de son GB, période (0 = bruit), nombre de demi-périodes (16 bits)
; Exemples de Tennis : $03 rebond, $06 frappe, $0C filet, $25 applaudissements
sfx_table:
        db $03, 90
        dw 16
        db $06, 40
        dw 40
        db $0C, 0
        dw 40
        db $25, 0
        dw 250
        db 0
