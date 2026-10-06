; ===========================================================================
; sound.asm - bruitages sur le SN76489 de la ColecoVision (3,58 MHz / 32)
; pour les numéros de son de la ROM ($3665) :
;   3 rebond  4 mur  5 élan  6/7 frappe  $0C filet  $0D corps
;   $25 applaudissements  $29/$31 annonce du score
; Mêmes sons que la version CPC (AY) : période AY x 1,79 = période SN.
; La logique demande un son (S_SOUND -> sfx_req) ; play_sfx le lance, puis
; fait décroître le volume à chaque trame.
; Voie son 0 : sons purs ; voie de bruit : bruits (mur, élan, filet, public).
; Octets du SN76489 : %1cc0dddd fréquence (4 bits bas) puis %00dddddd (6 bits
; hauts) ; %1cc1aaaa atténuation (0 = fort, 15 = coupé) ; cc = 3 : bruit.
; ===========================================================================

sound_init:
sound_off:
        ld a,$9F                    ; les 4 voies coupées
        out (PSG),a
        ld a,$BF
        out (PSG),a
        ld a,$DF
        out (PSG),a
        ld a,$FF
        out (PSG),a
        xor a
        ld (sfx_vol),a
        ld (sfx_vol+1),a
        ret

; Chaque trame : volumes qui décroissent, puis nouveau son demandé
play_sfx:
        ld a,(sfx_vol)              ; voie son
        or a
        jr z,.n
        ld hl,sfx_frac
        ld a,(sfx_decay)
        call .decay
        ld hl,sfx_vol
        call .apply
        or $90
        out (PSG),a
.n:
        ld a,(sfx_vol+1)            ; bruit
        or a
        jr z,.new
        ld hl,sfx_frac+1
        ld a,(sfx_decay+1)
        call .decay
        ld hl,sfx_vol+1
        call .apply
        or $F0
        out (PSG),a
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
; volume (HL) -= E, sans passer sous 0 -> A = atténuation (15 - volume)
.apply:
        ld a,(hl)
        sub e
        jr nc,.ok
        xor a
.ok:
        ld (hl),a
        cpl
        and $0F
        ret
.new:
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
        ld a,(hl)                   ; type : 0 son pur, 1 bruit
        inc hl
        ld e,(hl)                   ; son : période (10 bits) ; bruit : %1xx (vitesse)
        inc hl
        ld d,(hl)
        inc hl
        ld b,(hl)                   ; volume de départ
        inc hl
        ld c,(hl)                   ; décroissance
        or a
        jr nz,.noise
        ld a,b
        ld (sfx_vol),a
        ld a,c
        ld (sfx_decay),a
        ld a,e                      ; période : 4 bits bas
        and $0F
        or $80
        out (PSG),a
        ld a,e                      ; 6 bits hauts
        srl d
        rra
        srl d
        rra
        srl d
        rra
        srl d
        rra
        and $3F
        out (PSG),a
        ld a,b
        cpl
        and $0F
        or $90
        out (PSG),a
        ret
.noise:
        ld a,b
        ld (sfx_vol+1),a
        ld a,c
        ld (sfx_decay+1),a
        ld a,e                      ; bruit blanc, vitesse 0-2
        or $E4
        out (PSG),a
        ld a,b
        cpl
        and $0F
        or $F0
        out (PSG),a
        ret

; numéro GB, type, période (16 bits), volume, décroissance (1/16 par trame)
sfx_table:
        db $03, 0
        dw 322
        db 13, 64                   ; rebond : son grave bref
        db $04, 1
        dw 1
        db 12, 64                   ; mur : bruit
        db $05, 1
        dw 0
        db 8, 96                    ; élan : souffle
        db $06, 0
        dw 161
        db 15, 80                   ; frappe
        db $07, 0
        dw 161
        db 15, 80
        db $0C, 1
        dw 2
        db 13, 40                   ; filet : bruit grave
        db $0D, 0
        dw 537
        db 12, 48                   ; corps
        db $25, 1
        dw 0
        db 12, 5                    ; applaudissements : bruit qui dure
        db $29, 0
        dw 215
        db 12, 24                   ; annonce du score
        db $31, 0
        dw 179
        db 12, 24
        db 0
