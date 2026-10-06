; ===========================================================================
; input.asm - clavier du MO5 -> joypad GB
;
;   flèches : se déplacer ; ESPACE : frapper (lob automatique au filet)
; Une touche se teste en écrivant son numéro dans les bits 1-6 de $A7C1
; (colonne << 1 | (7 - ligne) << 4), puis en lisant le bit 7 (0 = appuyée).
; La lecture de $A7C1 efface l'indicateur de trame : poll_frame le compte
; juste avant.
; Un seul bouton : ESPACE = frapper ; lob automatique quand l'adversaire
; est au filet (comme les versions Spectrum et C64).
; Octet GB : bit0 A, bit1 B, bit4 droite, bit5 gauche, bit6 haut, bit7 bas.
; ===========================================================================

K_UP        equ $62
K_LEFT      equ $52
K_DOWN      equ $42
K_RIGHT     equ $32
K_SPACE     equ $40
K_M         equ $34
K_ENTER     equ $68
K_S         equ $46
K_B         equ $44
K_1         equ $5E
K_2         equ $4E
K_3         equ $3E
K_4         equ $2E

; B = touche -> N = 1 si relâchée (bit 7 de A), 0 si appuyée
key_test
        jsr poll_frame
        orb sfx_bit                 ; (bit 0 : buzzer)
        stb PIA_B
        lda PIA_B
        rts

; Sortie : A = joypad GB (bit 0 tir 1, bit 1 tir 2), directions opposées annulées
read_pad
        clr tmp
        ldx #key_tab
rp_l    ldb ,x+
        beq rp_e
        bsr key_test
        bmi rp_n
        lda ,x
        ora tmp
        sta tmp
rp_n    leax 1,x
        bra rp_l
rp_e    lda tmp
        tfr a,b                     ; haut + bas, gauche + droite : annulés ($2225)
        andb #$C0
        cmpb #$C0
        bne rp_v
        anda #$3F
rp_v    tfr a,b
        andb #$30
        cmpb #$30
        bne rp_h
        anda #$CF
rp_h    rts

key_tab fcb K_UP,PAD_U,K_DOWN,PAD_D,K_LEFT,PAD_L,K_RIGHT,PAD_R
        fcb K_SPACE,PAD_A,0

; --- Réglage du tir : 1 ou 2 boutons -----------------------------------------------
ZONE_NET    equ $0C             ; carré de service (près du filet)

; A = joypad lu -> A = joypad GB
apply_fire
        tst two_buttons
        bne af_r                    ; 2 boutons : ESPACE = A, M = B
        tfr a,b
        andb #PAD_A+PAD_B
        bne af_held
        clr fire_mode               ; relâché
af_r    rts
af_held pshs a
        lda fire_mode
        bne af_out
        lda #1                      ; nouvel appui : coup normal par défaut
        ldb P1_STATE
        cmpb #1                     ; en échange seulement (pas au service)
        bne af_set
        ldb P2_ZONE
        andb #ZONE_NET
        cmpb #ZONE_NET
        bne af_set                  ; adversaire pas au filet
        ldb P1_ZONE
        andb #ZONE_NET
        cmpb #ZONE_NET
        beq af_set                  ; joueur lui-même au filet
        lda #2                      ; lob
af_set  sta fire_mode
af_out  puls a
        anda #$FC                   ; directions seules
        ldb fire_mode
        cmpb #1
        bne af_lob
        ora #PAD_A
        rts
af_lob  ora #PAD_B
        rts

; A -> key_now : chiffre 1-4 appuyé, $FF sinon
read_digit
        ldx #digit_tab
        lda #1
rd_l    ldb ,x+
        pshs a
        jsr key_test
        puls b
        bpl rd_k
        tfr b,a
        inca
        cmpa #5
        bne rd_l
        lda #$FF
        sta key_now
        rts
rd_k    stb key_now
        rts

digit_tab fcb K_1,K_2,K_3,K_4
