; ===========================================================================
; input.asm - manette ColecoVision (manette 1) -> joypad GB
;
; La manette se lit en deux modes (bits à 0 = appuyé) :
;   OUT (CTRL_JOY) puis IN (CTRL1) : bits 0-3 haut droite bas gauche,
;                                    bit 6 bouton gauche
;   OUT (CTRL_KEYPAD) puis IN (CTRL1) : bits 0-3 touche du pavé,
;                                       bit 6 bouton droit
; Deux réglages (menu) :
;   2 boutons : gauche = bouton A du GB (coup), droit = bouton B (lob)
;   1 bouton  : l'un ou l'autre = frapper ; lob automatique quand
;               l'adversaire est au filet (comme les versions Spectrum et C64)
; Octet GB : bit0 A, bit1 B, bit4 droite, bit5 gauche, bit6 haut, bit7 bas.
; ===========================================================================

; Sortie : A = joypad GB (bit 0 bouton gauche, bit 1 bouton droit),
; directions opposées annulées. Touche du pavé : read_key.
read_pad:
        out (CTRL_JOY),a
        ex (sp),hl                  ; laisser le temps à la manette
        ex (sp),hl
        in a,(CTRL1)
        cpl
        ld c,a
        and $0F
        ld l,a
        ld h,0
        ld de,joy_map
        add hl,de
        ld e,(hl)
        bit 6,c                     ; bouton gauche
        jr z,.nl
        set 0,e
.nl:
        out (CTRL_KEYPAD),a
        ex (sp),hl
        ex (sp),hl
        in a,(CTRL1)
        bit 6,a                     ; bouton droit (0 = appuyé)
        jr nz,.nr
        set 1,e
.nr:
        and $0F
        ld l,a
        ld h,0
        ld bc,key_map
        add hl,bc
        ld a,(hl)
        ld (key_now),a
        ld a,e                      ; directions opposées annulées ($2225)
        and $C0
        cp $C0
        jr nz,.v
        ld a,e
        and $3F
        ld e,a
.v:
        ld a,e
        and $30
        cp $30
        jr nz,.h
        ld a,e
        and $CF
        ld e,a
.h:
        ld a,e
        ret

; manche bits 0-3 (haut droite bas gauche) -> joypad GB
joy_map:
        db $00, $40, $10, $50, $80, $C0, $90, $D0
        db $20, $60, $30, $70, $A0, $E0, $B0, $F0

; pavé (bits 0-3 lus) -> touche : 0-9, 10 '*', 11 '#', $FF aucune
key_map:
        db $FF, 8, 4, 5, $FF, 7, 11, 2, $FF, 10, 0, 9, 3, 1, 6, $FF

; --- Réglage du tir : 1 ou 2 boutons -----------------------------------------------
ZONE_NET    equ $0C             ; carré de service (près du filet)

; A = joypad lu (bit 0 bouton gauche, bit 1 bouton droit) -> A = joypad GB
apply_fire:
        ld c,a
        ld a,(two_buttons)
        or a
        ld a,c
        ret nz                      ; 2 boutons : gauche = A, droit = B
        and PAD_A | PAD_B           ; 1 bouton : un bouton quelconque
        jr nz,.held
        xor a                       ; relâché
        ld (fire_mode),a
        ld a,c
        ret
.held:
        ld a,(fire_mode)
        or a
        jr nz,.out
        ld b,1                      ; nouvel appui : coup normal par défaut
        ld a,(P1_STATE)
        cp 1                        ; en échange seulement (pas au service)
        jr nz,.set
        ld a,(P2_ZONE)
        and ZONE_NET
        cp ZONE_NET
        jr nz,.set                  ; adversaire pas au filet
        ld a,(P1_ZONE)
        and ZONE_NET
        cp ZONE_NET
        jr z,.set                   ; joueur lui-même au filet
        ld b,2                      ; lob
.set:
        ld a,b
        ld (fire_mode),a
.out:
        ld b,a
        ld a,c
        and $FC                     ; directions seules
        dec b
        jr nz,.lob
        or PAD_A
        ret
.lob:
        or PAD_B
        ret
