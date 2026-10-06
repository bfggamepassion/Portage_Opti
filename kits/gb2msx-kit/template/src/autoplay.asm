; ===========================================================================
; autoplay.asm - robot joueur 1 (version de test : sh build.sh -DAUTOPLAY)
; Même logique que les robots des versions Spectrum (outils) et C64 :
; servir, se placer sous la balle qui arrive, frapper, revenir au centre.
; Sortie : A = joypad GB.
; ===========================================================================

bot_pad:
        ld a,(bot_cool)
        or a
        jr z,.c
        dec a
        ld (bot_cool),a
.c:
        ld a,(P1_STATE)
        cp 5                        ; service : frapper après 20 trames
        jr nz,.s6
        ld a,(bot_serve)
        inc a
        ld (bot_serve),a
        cp 20
        jr nz,.none
        ld a,PAD_A
        ret
.s6:
        cp 6                        ; balle lancée : frapper quand elle redescend
        jr nz,.rally
        ld a,($C052)
        bit 7,a
        jr z,.none
        ld a,(B_Z)
        cp $50
        jr nc,.none
        ld a,(bot_cool)
        or a
        jr nz,.none
        ld a,10
        ld (bot_cool),a
        ld a,PAD_A
        ret
.none:
        xor a
        ret
.rally:
        xor a
        ld (bot_serve),a
        ld e,0                      ; touches
        ld a,(B_ST)                 ; balle en jeu qui vient vers nous ?
        cp 3
        jr z,.come
        cp 4
        jr nz,.center
.come:
        ld a,($C04F)
        bit 7,a
        jr nz,.center
        ld a,($C043)
        cp $60
        jr c,.center
        ld a,($C045)                ; cible x = balle - 10
        sub 10
        ld d,a
        ld a,($C005)
        add a,2
        cp d
        jr nc,.nr
        ld e,PAD_R
        jr .hit
.nr:
        ld a,($C005)
        sub 2
        cp d
        jr c,.hit
        jr z,.hit
        ld e,PAD_L
.hit:
        ld a,(P1_STATE)
        cp 1
        jr nz,.out
        ld a,(bot_cool)
        or a
        jr nz,.out
        ld a,($C043)                ; 0 < y joueur - y balle < 16
        ld d,a
        ld a,($C003)
        sub d
        jr z,.out
        cp 16
        jr nc,.out
        ld a,12
        ld (bot_cool),a
        ld a,e
        or PAD_A
        ret
.center:
        ld a,(P1_STATE)
        cp 1
        jr nz,.out
        ld a,($C005)
        cp $68
        jr nc,.nc
        ld e,PAD_R
        jr .back
.nc:
        cp $71
        jr c,.back
        ld e,PAD_L
.back:
        ld a,($C003)
        cp $BB
        jr c,.out
        ld a,e
        or PAD_U
        ld e,a
.out:
        ld a,e
        ret
