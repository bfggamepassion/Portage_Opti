; ===========================================================================
; text.asm - texte à l'écran avec la police de la ROM Spectrum ($3D00)
;   print_at : B = ligne (0-23), C = colonne (0-31), HL = chaîne terminée par 0
;   print_num : A = nombre (0-99), à la position courante
; ===========================================================================

txt_pos:    dw 0                    ; adresse écran du prochain caractère

; B = ligne, C = colonne -> txt_pos
text_at:
        ld a,b
        and $18
        or $40
        ld d,a
        ld a,b
        and 7
        rrca
        rrca
        rrca
        or c
        ld e,a
        ld (txt_pos),de
        ret

print_at:
        push hl
        call text_at
        pop hl
print_str:
        ld a,(hl)
        or a
        ret z
        push hl
        call print_char
        pop hl
        inc hl
        jr print_str

; A = caractère (32-127)
print_char:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,$3C00                 ; $3D00 - 32*8
        add hl,de
        ld de,(txt_pos)
        ld b,8
.row:
        ld a,(hl)
        ld (de),a
        inc hl
        inc d
        djnz .row
        ld de,(txt_pos)
        inc e
        ld (txt_pos),de
        ret

; A = nombre 0-99 (sans zéro de tête)
print_num:
        ld b,'0'-1
.tens:
        inc b
        sub 10
        jr nc,.tens
        add a,10+'0'
        push af
        ld a,b
        cp '0'
        call nz,print_char
        pop af
        jp print_char
