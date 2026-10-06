; ===========================================================================
; unrle.asm - décompresse un écran produit par tools/zxscreen.py (rle)
;   HL = données, DE = destination (SCREEN pour un écran complet)
; Paquets : n (1-127) + n octets, ou $80+n + octet répété n fois ; 0 = fin.
; ===========================================================================

unrle:
.pkt:
        ld a,(hl)
        inc hl
        or a
        ret z
        ld c,a
        ld b,0
        jp m,.run
        ldir                        ; n octets littéraux
        jr .pkt
.run:
        and $7F
        ld b,a
        ld a,(hl)
        inc hl
.rep:
        ld (de),a
        inc de
        djnz .rep
        jr .pkt
