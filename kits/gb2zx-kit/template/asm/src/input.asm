; ===========================================================================
; input.asm - clavier + joystick Kempston -> octet joypad GB
;   Clavier : Q haut, A bas, O gauche, P droite, ESPACE = feu (bouton A)
;   Kempston (port $1F) : directions, feu
;   Octet GB : bit0 A, bit1 B, bit2 Select, bit3 Start, bit4 droite,
;              bit5 gauche, bit6 haut, bit7 bas. Directions opposées annulées.
; Le joystick Spectrum n'a qu'un bouton : pour B / Start / Select, choisir
; une règle adaptée au jeu (Tennis : B = lob automatique selon la situation,
; voir PORTING.md) ou une touche du clavier.
; ===========================================================================

use_kempston:   db 0

; Sortie : A = joypad GB
read_pad:
        ld c,0
        ld a,$FB                    ; Q W E R T
        in a,($FE)
        rra
        jr c,.nq
        set 6,c
.nq:
        ld a,$FD                    ; A S D F G
        in a,($FE)
        rra
        jr c,.na
        set 7,c
.na:
        ld a,$DF                    ; P O I U Y
        in a,($FE)
        rra
        jr c,.np
        set 4,c
.np:
        rra
        jr c,.no
        set 5,c
.no:
        ld a,$7F                    ; ESPACE SYM M N B
        in a,($FE)
        rra
        jr c,.nsp
        set 0,c
.nsp:
        ld a,(use_kempston)
        or a
        jr z,.cancel
        in a,($1F)
        rra
        jr nc,.kr
        set 4,c
.kr:
        rra
        jr nc,.kl
        set 5,c
.kl:
        rra
        jr nc,.kd
        set 7,c
.kd:
        rra
        jr nc,.ku
        set 6,c
.ku:
        rra
        jr nc,.cancel
        set 0,c
.cancel:
        ld a,c
        and $C0
        cp $C0
        jr nz,.v
        ld a,c
        and $3F
        ld c,a
.v:
        ld a,c
        and $30
        cp $30
        jr nz,.h
        ld a,c
        and $CF
        ld c,a
.h:
        ld a,c
        ret
