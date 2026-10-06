; ===========================================================================
; proj.asm - projection court -> écran GB ($095D, $0951, $09C2) en Z80 natif,
; avec des tables (même méthode que la version C64, vérifiée par
; tools/test_proj.py contre la ROM traduite).
;   b = Y arrondi, c = X arrondi, dx = |$6C - c|, dy = |$B8 - b|
;   l = ((dx² x dy) / 256 / 72) / 4, opposé si b >= $B8
;   x = c + l si c < $6C, sinon c - l ;  y = $1C + b x 40 / 47
; La logique du jeu n'appelle jamais ces routines (affichage seulement).
; ===========================================================================


; HL -> Y (8.8), X (8.8). Sortie : B = y, C = x (pixels GB)
proj:
        ld a,(hl)                   ; b = Y arrondi
        add a,$80
        inc hl
        ld a,(hl)
        adc a,0
        ld (pj_b),a
        inc hl
        ld a,(hl)                   ; c = X arrondi
        add a,$80
        inc hl
        ld a,(hl)
        adc a,0
        ld (pj_c),a
        jr proj_bc

; $0951 : marque de rebond (Y et X sans arrondi, Y - 1 devant le filet)
proj_mark:
        inc hl
        ld a,(hl)
        cp $78
        jr nc,.f
        dec a
.f:
        ld (pj_b),a
        inc hl
        inc hl
        ld a,(hl)
        ld (pj_c),a

; b = pj_b, c = pj_c -> B = y, C = x
proj_bc:
        ld a,(pj_c)                 ; dx = |$6C - c|
        sub $6C
        jr nc,.dx
        neg
.dx:
        ld l,a
        ld h,0
        add hl,hl
        ld de,sq_tab
        add hl,de
        ld e,(hl)                   ; DE = dx²
        inc hl
        ld d,(hl)
        ld a,(pj_b)                 ; dy = |$B8 - b|
        sub $B8
        jr nc,.dy
        neg
.dy:
        ld hl,0                     ; C:H:L = DE x A (24 bits)
        ld c,l
        ld b,8
.m:
        add hl,hl
        rl c
        rla
        jr nc,.mn
        add hl,de
        jr nc,.mn
        inc c
.mn:
        djnz .m
        ld e,h                      ; C:E = produit / 256 (< 72 x 256)
        ld a,c                      ; quotient par 72 sur 8 bits -> E
        ld b,8
.d:
        sla e
        rla
        cp 72
        jr c,.dn
        sub 72
        inc e
.dn:
        djnz .d
        ld a,e                      ; l = quotient / 4
        srl a
        srl a
        ld e,a
        ld a,(pj_b)                 ; b >= $B8 : l = -l
        cp $B8
        jr c,.pos
        ld a,e
        neg
        ld e,a
.pos:
        ld a,(pj_c)                 ; x = c + l si c < $6C, sinon c - l
        cp $6C
        jr nc,.sub
        add a,e
        jr .x
.sub:
        sub e
.x:
        ld c,a
        ld a,(pj_b)                 ; y = $1C + b x 40 / 47
        ld l,a
        ld h,ytab >> 8
        ld b,(hl)
        ret

; $09C2 : hauteur de la balle -> B = y écran - hauteur
;   z' = z + z/8 si la balle est au service (état 2) ; l = z' x 6 / 16 + 1,
;   moins 1 à 3 pixels vers le fond (b < $C8, < $A8, < $78), sans passer 0.
lift:
        ld a,(B_Z)
        ld e,a
        ld a,(B_ST)
        cp 2
        ld a,e
        jr nz,.n
        srl a
        srl a
        srl a
        add a,e
.n:
        ld l,a
        ld h,lifttab >> 8
        ld e,(hl)                   ; z' x 6 / 16
        inc e
        ld a,(pj_b)
        cp $C8
        jr nc,.done
        dec e
        jr z,.done
        cp $A8
        jr nc,.done
        dec e
        jr z,.done
        cp $78
        jr nc,.done
        dec e
.done:
        ld a,b
        sub e
        ld b,a
        ret

sq_tab:
        LUA ALLPASS
        for i = 0, 255 do _pc(string.format("dw %d", i * i)) end
        ENDLUA
        ALIGN 256
ytab:
        LUA ALLPASS
        for b = 0, 255 do _pc(string.format("db %d", (28 + (b * 40) // 47) % 256)) end
        ENDLUA
lifttab:
        LUA ALLPASS
        for z = 0, 255 do _pc(string.format("db %d", (z * 6) // 16)) end
        ENDLUA
