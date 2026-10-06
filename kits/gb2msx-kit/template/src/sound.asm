; ===========================================================================
; sound.asm - bruitages sur le PSG AY-3-8910 du MSX (horloge 1,79 MHz)
; pour les numéros de son de la ROM ($3665) :
;   3 rebond  4 mur  5 élan  6/7 frappe  $0C filet  $0D corps
;   $25 applaudissements  $29/$31 annonce du score
; Mêmes sons que la version CPC (AY à 1 MHz) : périodes x 1,79.
; La logique demande un son (S_SOUND -> sfx_req) ; play_sfx le lance après
; l'affichage, puis fait décroître le volume à chaque trame.
; Voie A : sons brefs (son pur ou bruit) ; voie C : applaudissements (bruit).
; Registre 7 : les bits 7-6 restent à 10 (port B en sortie, port A en
; entrée : manettes).
; ===========================================================================

; A = registre, C = valeur
psg_write:
        out (PSG_ADDR),a
        ld a,c
        out (PSG_WRITE),a
        ret

sound_off:
sound_init:
        ld a,%10111111
        ld (mixer),a
        xor a
        ld (sfx_vol),a
        ld (sfx_vol+1),a
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
        db 7, %10111111             ; tout coupé (port A en entrée, B en sortie)
        db 8, 0
        db 9, 0
        db 10, 0
        db $FF


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
        dw 322
        db 13, 64                   ; rebond : son grave bref
        db $04, 1
        dw 21
        db 12, 64                   ; mur : bruit
        db $05, 1
        dw 7
        db 8, 96                    ; élan : souffle
        db $06, 0
        dw 161
        db 15, 80                   ; frappe
        db $07, 0
        dw 161
        db 15, 80
        db $0C, 1
        dw 43
        db 13, 40                   ; filet : bruit grave
        db $0D, 0
        dw 537
        db 12, 48                   ; corps
        db $25, 2
        dw 11
        db 12, 5                    ; applaudissements : bruit qui dure
        db $29, 0
        dw 215
        db 12, 24                   ; annonce du score
        db $31, 0
        dw 179
        db 12, 24
        db 0
