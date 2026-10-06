; ===========================================================================
; text.asm - texte (repris de C64 Tennis)
;
; Police : recopiée au démarrage depuis la ROM de caractères du C64 (codes
; écran 0-63), en caractères 128-191 du jeu de caractères du jeu : pas de
; police de Commodore distribuée avec le programme. (La banque VIC 1 ne voit
; pas la ROM de caractères : il faut ce jeu de caractères en RAM.)
; Chaînes : codage "c64txt" (A-Z = $01-$1A), terminées par 0.
; Pour du texte sur fond clair, C64 Tennis recopie aussi la police inversée.
; ===========================================================================

        .enc "c64txt"
        .cdef " ?", $20
        .cdef "AZ", $01
        .enc "none"

TXT_SCR     = zW                ; pointeur écran du prochain caractère
TXT_COL     = zW+2              ; pointeur couleur
FONT        = CHARSET + 128 * 8

font_init
        sei
        lda #$33                    ; ROM de caractères visible en $D000
        sta $01
        ldx #0
-       lda $D000,x
        sta FONT,x
        lda $D100,x
        sta FONT+$100,x
        inx
        bne -
        lda #MEM_IO
        sta $01
        cli
        rts

txt_page    .byte >SCREEN       ; écran où l'on écrit
txt_ink     .byte 1             ; couleur des cases de texte

; X = rangée, A = colonne
text_at clc
        adc row_lo,x
        sta TXT_SCR
        sta TXT_COL
        lda row_hi,x
        adc #0
        pha
        adc txt_page
        sta TXT_SCR+1
        pla
        clc
        adc #>COLRAM
        sta TXT_COL+1
        rts

row_lo  .byte <(range(25) * 40)
row_hi  .byte >(range(25) * 40)

; A = code écran (0-63)
print_char
        ldy #0
        ora #$80
        sta (TXT_SCR),y
        lda txt_ink
        sta (TXT_COL),y
        inc TXT_SCR
        inc TXT_COL
        bne +
        inc TXT_SCR+1
        inc TXT_COL+1
+       rts

; zL/zH = chaîne
print_str
        ldy #0
        lda (zL),y
        beq +
        jsr print_char
        inc zL
        bne print_str
        inc zH
        jmp print_str
+       rts

; X = rangée, A = colonne, zL/zH = chaîne
print_at
        jsr text_at
        jmp print_str

; A = nombre 0-99, sans zéro de tête
print_num
        ldx #$2F
        sec
-       inx
        sbc #10
        bcs -
        adc #$3A
        pha
        txa
        cmp #$30
        beq +
        jsr print_char
+       pla
        jmp print_char

; #prt rangée, colonne, "TEXTE"
prt     .macro row, col, text
        lda #<_s
        sta zL
        lda #>_s
        sta zH
        ldx #\row
        lda #\col
        jsr print_at
        jmp _e
        .enc "c64txt"
_s      .null \text
        .enc "none"
_e
        .endm
