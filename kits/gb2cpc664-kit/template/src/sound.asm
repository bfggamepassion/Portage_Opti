; ===========================================================================
; sound.asm - bruitages sur la puce AY-3-8912 du CPC (horloge 1 MHz)
; pour les numéros de son de la ROM ($3665) :
;   3 rebond  4 mur  5 élan  6/7 frappe  $0C filet  $0D corps
;   $25 applaudissements  $29/$31 annonce du score
; La logique demande un son (S_SOUND -> sfx_req) ; play_sfx le lance après
; l'affichage, puis fait décroître le volume à chaque trame.
; Voie A : sons brefs (son pur ou bruit) ; voie C : applaudissements (bruit).
; Accès au PSG : registre par le port A du PPI ($F4), commande par le port C
; ($F6 : $C0 choisir, $80 écrire, $00 inactif).
; ===========================================================================

; A = registre, C = valeur
psg_write:
        ld b,$F4
        out (c),a
        ld b,$F6
        ld a,$C0
        out (c),a
        xor a
        out (c),a
        ld b,$F4
        out (c),c
        ld b,$F6
        ld a,$80
        out (c),a
        xor a
        out (c),a
        ret

sound_init:
        ld hl,psg_init
.l:
        ld a,(hl)
        cp $FF
        ret z
        inc hl
        ld c,(hl)
        inc hl
        push hl
        call psg_write
        pop hl
        jr .l
psg_init:
        db 7, %00111111             ; tout coupé (bits 6-7 à 0 : port A en entrée)
        db 8, 0
        db 9, 0
        db 10, 0
        db $FF

sfx_vol:    db 0, 0                 ; volume en cours (voie A, voie C)
sfx_decay:  db 0, 0                 ; baisse par trame (en 1/16)
sfx_frac:   db 0, 0
mixer:      db %00111111

; Chaque trame : volumes qui décroissent, puis nouveau son demandé
play_sfx:
        ld a,(sfx_vol)              ; voie A
        or a
        jr z,.c
        ld hl,sfx_frac
        ld a,(sfx_decay)
        call .decay
        ld hl,sfx_vol
        call .apply
        ld a,8
        call psg_write
.c:
        ld a,(sfx_vol+1)            ; voie C
        or a
        jr z,.new
        ld hl,sfx_frac+1
        ld a,(sfx_decay+1)
        call .decay
        ld hl,sfx_vol+1
        call .apply
        ld a,10
        call psg_write
        jr .new
; (HL) += A (fraction sur 4 bits) -> E = pas entiers de décroissance
.decay:
        add a,(hl)
        ld e,a
        and $0F
        ld (hl),a
        ld a,e
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld e,a
        ret
; volume (HL) -= E, sans passer sous 0 -> C = volume
.apply:
        ld a,(hl)
        sub e
        jr nc,.ok
        xor a
.ok:
        ld (hl),a
        ld c,a
        ret
.new:
        ; nouveau son
        ld a,(sfx_req)
        or a
        ret z
        ld c,a
        xor a
        ld (sfx_req),a
        ld hl,sfx_table
.find:
        ld a,(hl)
        or a
        ret z
        cp c
        jr z,.found
        ld de,6
        add hl,de
        jr .find
.found:
        inc hl
        ld a,(hl)                   ; type : 0 son pur (voie A), 1 bruit (A), 2 bruit (C)
        inc hl
        ld e,(hl)                   ; période (son : 12 bits ; bruit : 5 bits)
        inc hl
        ld d,(hl)
        inc hl
        ld b,(hl)                   ; volume de départ
        inc hl
        ld c,(hl)                   ; décroissance
        cp 2
        jr z,.voiceC
        ; voie A
        push af
        ld a,b
        ld (sfx_vol),a
        ld a,c
        ld (sfx_decay),a
        pop af
        or a
        jr nz,.noiseA
        ld c,e                      ; période du son (registres 0 et 1)
        xor a
        call psg_write
        ld c,d
        ld a,1
        call psg_write
        ld a,(mixer)                ; son A oui, bruit A non
        and %11110110
        or %00001000
        jr .mix
.noiseA:
        ld c,e
        ld a,6
        call psg_write
        ld a,(mixer)                ; bruit A oui, son A non
        and %11110110
        or %00000001
.mix:
        ld (mixer),a
        ld c,a
        ld a,7
        call psg_write
        ld a,(sfx_vol)
        ld c,a
        ld a,8
        jp psg_write
.voiceC:
        ld a,b
        ld (sfx_vol+1),a
        ld a,c
        ld (sfx_decay+1),a
        ld c,e
        ld a,6
        call psg_write
        ld a,(mixer)                ; bruit C oui
        and %11011111
        or %00000100
        ld (mixer),a
        ld c,a
        ld a,7
        call psg_write
        ld a,(sfx_vol+1)
        ld c,a
        ld a,10
        jp psg_write

; numéro GB, type, période (16 bits), volume, décroissance (1/16 par trame)
sfx_table:
        db $03, 0
        dw 180
        db 13, 64                   ; rebond : son grave bref
        db $04, 1
        dw 12
        db 12, 64                   ; mur : bruit
        db $05, 1
        dw 4
        db 8, 96                    ; élan : souffle
        db $06, 0
        dw 90
        db 15, 80                   ; frappe
        db $07, 0
        dw 90
        db 15, 80
        db $0C, 1
        dw 24
        db 13, 40                   ; filet : bruit grave
        db $0D, 0
        dw 300
        db 12, 48                   ; corps
        db $25, 2
        dw 6
        db 12, 5                    ; applaudissements : bruit qui dure
        db $29, 0
        dw 120
        db 12, 24                   ; annonce du score
        db $31, 0
        dw 100
        db 12, 24
        db 0
