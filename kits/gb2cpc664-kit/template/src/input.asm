; ===========================================================================
; input.asm - clavier et joystick du CPC -> joypad GB
;
; Matrice du clavier : ligne choisie par le port C du PPI ($F6), lue par le
; registre 14 du PSG (port A du PPI, $F4). Joystick = ligne 9.
;   Clavier : Q haut, A bas, O gauche, P droite, ESPACE tir 1, M tir 2
;   Joystick : directions, tir 1, tir 2
; Deux réglages : 1 bouton (règle du jeu pour B, à écrire) ou 2 boutons
; (tir 1 = A, tir 2 = B du GB).
; Octet GB : bit0 A, bit1 B, bit4 droite, bit5 gauche, bit6 haut, bit7 bas.
; ===========================================================================

two_buttons:    db 0            ; 0 = 1 bouton (lob automatique), 1 = 2 boutons

; A = ligne (0-9) -> A = état de la ligne (bit à 0 = touche appuyée)
read_line:
        ld d,a
        ld bc,$F40E                 ; registre 14 du PSG
        out (c),c
        ld bc,$F6C0                 ; sélection du registre
        out (c),c
        ld bc,$F600
        out (c),c
        ld bc,$F792                 ; port A du PPI en entrée
        out (c),c
        ld a,d
        or $40                      ; lecture du PSG, ligne D
        ld b,$F6
        out (c),a
        ld b,$F4
        in a,(c)
        ld bc,$F782                 ; port A du PPI en sortie
        out (c),c
        ld bc,$F600
        out (c),c
        ret

; Sortie : A = joypad GB (bit 0 = tir 1, bit 1 = tir 2), directions opposées annulées
read_pad:
        ld e,0
        ld a,9                      ; joystick
        call read_line
        cpl
        ld l,a
        and $0F                     ; haut bas gauche droite -> bits 6 7 5 4
        ld c,a
        ld b,0
        push hl
        ld hl,joy_map
        add hl,bc
        ld e,(hl)
        pop hl
        bit 5,l                     ; tir 1
        jr z,.nf1
        set 0,e
.nf1:
        bit 4,l                     ; tir 2
        jr z,.nf2
        set 1,e
.nf2:
        ld hl,key_tab               ; clavier : (ligne, bit, touche GB)
.k:
        ld a,(hl)
        cp $FF
        jr z,.cancel
        push hl
        push de
        call read_line
        pop de
        pop hl
        inc hl
        and (hl)
        inc hl
        jr nz,.up
        ld a,e
        or (hl)
        ld e,a
.up:
        inc hl
        jr .k
.cancel:
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

;             ligne, bit, touche GB
key_tab:    db 8, $08, PAD_U            ; Q
            db 8, $20, PAD_D            ; A
            db 4, $04, PAD_L            ; O
            db 3, $08, PAD_R            ; P
            db 5, $80, PAD_A            ; ESPACE : tir 1
            db 4, $40, PAD_B            ; M : tir 2
            db $FF

; joystick bits 0-3 (haut bas gauche droite) -> joypad GB
joy_map:
        db $00, $40, $80, $C0, $20, $60, $A0, $E0
        db $10, $50, $90, $D0, $30, $70, $B0, $F0

; --- Réglage du tir : 1 ou 2 boutons ---------------------------------------------
; 2 boutons : tir 1 = bouton A du GB, tir 2 = bouton B.
; 1 bouton : un tir quelconque = bouton A. À FAIRE : règle du jeu pour B
; (Tennis : lob automatique quand l'adversaire est au filet, décidé à
; l'appui ; voir Amstrad/src/input.asm du repo Tennis).
apply_fire:
        ld c,a
        ld a,(two_buttons)
        or a
        ld a,c
        ret nz
        and PAD_A | PAD_B
        ld a,c
        ret z
        and $FC
        or PAD_A
        ret
