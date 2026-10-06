; ===========================================================================
; input.asm - clavier et joystick du MSX -> joypad GB
;
;   Clavier : flèches, ESPACE = tir 1, M = tir 2, 1-4 = niveau (menu)
;   Joystick (port 1) : directions, bouton A = tir 1, bouton B = tir 2
; Clavier : ligne choisie par les bits 0-3 du port C du PPI ($AA), lue sur
; le port B ($A9), bits à 0 = touche appuyée. Joystick : registre 14 du PSG
; (port choisi par le bit 6 du registre 15).
; Deux réglages (menu) :
;   2 boutons : tir 1 = bouton A du GB (coup), tir 2 = bouton B (lob)
;   1 bouton  : un tir quelconque = frapper ; lob automatique quand
;               l'adversaire est au filet (comme les versions Spectrum et C64)
; Octet GB : bit0 A, bit1 B, bit4 droite, bit5 gauche, bit6 haut, bit7 bas.
; ===========================================================================

; A = ligne du clavier -> A = état (bit à 0 = appuyé)
read_row:
        ld c,a
        in a,(PPI_C)
        and $F0
        or c
        out (PPI_C),a
        in a,(PPI_B)
        ret

; Sortie : A = joypad GB (bit 0 tir 1, bit 1 tir 2), directions opposées
; annulées ; key_now = chiffre 1-4 appuyé ($FF : aucun).
read_pad:
        ld a,15                     ; joystick du port 1
        out (PSG_ADDR),a
        in a,(PSG_READ)
        and $BF
        or $03
        out (PSG_WRITE),a
        ld a,14
        out (PSG_ADDR),a
        in a,(PSG_READ)
        cpl
        ld c,a
        and $0F                     ; haut bas gauche droite -> bits 6 7 5 4
        ld l,a
        ld h,0
        ld de,joy_map
        add hl,de
        ld e,(hl)
        ld a,c                      ; boutons A et B -> tirs 1 et 2
        rrca
        rrca
        rrca
        rrca
        and 3
        or e
        ld e,a
        ld a,8                      ; ligne 8 : ESPACE, flèches
        call read_row
        cpl
        ld c,a
        and $F0                     ; gauche haut bas droite (bits 4-7)
        rrca
        rrca
        rrca
        rrca
        ld l,a
        ld h,0
        ld a,e
        ld de,arrow_map
        add hl,de
        or (hl)
        ld e,a
        bit 0,c                     ; ESPACE : tir 1
        jr z,.ns
        set 0,e
.ns:
        ld a,4                      ; ligne 4 : M (bit 2) : tir 2
        call read_row
        bit 2,a
        jr nz,.nm
        set 1,e
.nm:
        xor a                       ; ligne 0 : chiffres 1-4 (bits 1-4)
        call read_row
        rra                         ; (touche 0)
        ld b,1
        ld c,4
.d:
        rra
        jr nc,.dk                   ; chiffre B appuyé
        inc b
        dec c
        jr nz,.d
        ld b,$FF
.dk:
        ld a,b
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

; joystick bits 0-3 (haut bas gauche droite) -> joypad GB
joy_map:
        db $00, $40, $80, $C0, $20, $60, $A0, $E0
        db $10, $50, $90, $D0, $30, $70, $B0, $F0
; flèches bits 0-3 (gauche haut bas droite) -> joypad GB
arrow_map:
        db $00, $20, $40, $60, $80, $A0, $C0, $E0
        db $10, $30, $50, $70, $90, $B0, $D0, $F0

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
