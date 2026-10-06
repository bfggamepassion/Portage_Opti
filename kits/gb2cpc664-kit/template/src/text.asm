; ===========================================================================
; text.asm - texte (police de la ROM du CPC, lue au démarrage) et score
;   print_at : B = rangée (0-24), C = colonne (0-39), HL = chaîne (0 à la fin)
;   Caractères 32-95 (majuscules, chiffres, ponctuation), 8x8 en mode 1.
;   Couleurs : txt_fg / txt_bg = motif d'une encre (encre 0 $00, 1 $F0,
;   2 $0F, 3 $FF).
; ===========================================================================

INK0        equ $00
INK1        equ $F0
INK2        equ $0F
INK3        equ $FF

txt_pos:    dw 0                ; adresse écran du prochain caractère
txt_fg:     db INK0             ; lettres vert clair
txt_bg:     db INK3             ; sur fond noir

; B = rangée, C = colonne -> txt_pos
text_at:
        ld a,b
        add a,a
        add a,a
        add a,a
        push bc
        call line_addr
        pop bc
        ld a,c
        add a,a
        ld e,a
        ld d,0
        add hl,de
        ld (txt_pos),hl
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

; A = caractère (32-95)
print_char:
        sub 32
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,font
        add hl,de
        ex de,hl                    ; DE = motif
        ld hl,(txt_pos)
        ld b,8
.row:
        push bc
        ld a,(de)
        inc de
        push af
        rrca                        ; 4 pixels de gauche
        rrca
        rrca
        rrca
        call .conv
        ld (hl),a
        inc hl
        pop af
        call .conv                  ; 4 pixels de droite
        ld (hl),a
        dec hl
        ld a,h
        add a,8
        ld h,a
        pop bc
        djnz .row
        ld hl,(txt_pos)
        inc hl
        inc hl
        ld (txt_pos),hl
        ret
; A (bits 0-3) = 4 pixels -> octet mode 1 en txt_fg / txt_bg
.conv:
        and $0F
        ld b,a
        rlca
        rlca
        rlca
        rlca
        or b                        ; masque des pixels allumés
        ld c,a
        ld a,(txt_fg)
        and c
        ld b,a
        ld a,c
        cpl
        ld c,a
        ld a,(txt_bg)
        and c
        or b
        ret

; A = nombre 0-99, sans zéro de tête
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
