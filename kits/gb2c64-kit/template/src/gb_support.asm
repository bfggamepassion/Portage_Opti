; ===========================================================================
; gb_support.asm - ce que la logique GB traduite (gb/gb_logic_*.asm) attend
;
;   Registres GB en page zéro (voir zp.asm), Y = 0 en permanence.
;   G_RST08 / G_RST18 / G_RST28 : les routines RST de la ROM ($0008-$0023),
;     appelées par JSR (l'adresse dépilée vaut « suite - 1 » : on ajoute 1).
;     Mêmes effets sur les registres et indicateurs que sur GB.
;   G_GETF / G_SETF : registre F du GB (PUSH AF / POP AF).
;   S_SOUND, S_RET, S_SCREEN : remplaçants des routines de la ROM.
;   gb_new_game, gb_tick, gb_set_pad : séquences de la boucle principale GB.
; Les routines RST sont celles de Tennis (conventions courantes chez
; Nintendo, mais à vérifier dans chaque ROM : $0000-$003F).
; ===========================================================================

; HL = HL + 1 (A conservé)
inc_hl  inc zL
        bne +
        inc zH
+       rts

; Dépile l'adresse de retour dans HL, + 1
pop_ret .macro
        pla
        sta zL
        pla
        sta zH
        jsr inc_hl
        .endm

; $0008 : saut indexé. A = index, table de .word juste après le JSR.
;   pop hl / add a / ld e,a / ld d,0 / add hl,de / ld a,[hl+] / ld h,[hl] / ld l,a / jp hl
G_RST08 #pop_ret
        lda zA                      ; add a
        asl a
        sta zA
        sta zZ
        sta zE                      ; ld e,a / ld d,0
        sty zD
        clc                         ; add hl,de
        adc zL
        sta zL
        lda zH
        adc #0
        sta zH
        lda #0
        rol a
        sta zCY
        lda (zL),y                  ; ld a,[hl+] / ld h,[hl] / ld l,a
        sta zA
        iny
        lda (zL),y
        ldy #0
        sta zH
        lda zA
        sta zL
        jmp (zL)

; $0018 : lecture indexée. Après le JSR : .byte N puis N octets.
; Renvoie A = octet[A] et reprend après la table.
;   pop hl / ld c,a / ld b,0 / ld a,[hl+] / push hl / add hl,bc / ld c,a
;   ld a,[hl] / pop hl / add hl,bc / jp hl
G_RST18 #pop_ret
        lda zA
        sta zC
        sty zB
        lda (zL),y
        sta zA
        jsr inc_hl
        clc
        lda zL
        adc zC
        sta zT
        lda zH
        adc #0
        sta zT+1
        lda zA
        sta zC
        lda (zT),y
        sta zA
        clc
        lda zL
        adc zC
        sta zL
        lda zH
        adc #0
        sta zH
        lda #0
        rol a
        sta zCY
        jmp (zL)

; $0028 : copie en ligne. Après le JSR : .byte N puis N octets copiés vers (DE).
;   pop hl / ld a,[hl+] / ld b,a / boucle : ld a,[hl+] / ld [de],a / inc de
;   dec b / jr nz / jp hl
G_RST28 #pop_ret
        lda (zL),y
        sta zB
        jsr inc_hl
-       lda (zL),y
        sta zA
        sta (zE),y
        jsr inc_hl
        inc zE
        bne +
        inc zD
+       dec zB
        bne -
        sty zZ                      ; Z = 1
        jmp (zL)

; F du GB : bit 7 = Z, bit 4 = C. Sortie : A = F (Y conservé)
G_GETF  lda zCY
        and #1
        asl a
        asl a
        asl a
        asl a
        ldx zZ
        bne +
        ora #$80
+       rts

; A = F du GB -> zZ, zCY
G_SETF  tax
        lsr a
        lsr a
        lsr a
        lsr a
        sta zCY
        txa
        and #$80
        eor #$80
        sta zZ
        rts

; Demande de son (A = numéro GB), jouée après l'affichage (sound.asm)
S_SOUND lda zA
        sta sfx_req
S_RET   rts

; Changement d'écran demandé par la ROM : sur GB, souvent un redémarrage
; (LD SP,...). On abandonne le reste du pas de logique (retour direct à
; l'appelant de gb_tick) ; À FAIRE : décider quoi faire selon l'écran.
S_SCREEN
        ldx tick_sp
        txs
        lda #1
        sta game_over
        rts

; Nouvelle partie : reproduire la séquence de la ROM (mise à zéro de la RAM,
; options, appels d'initialisation), lue dans le désassemblage.
; Tourne avec toute la RAM visible (RAM GB éventuelle en $D000-$DFFF).
gb_new_game
        lda #MEM_RAM
        sta $01
        lda #0
        tax
-       sta $C000,x                 ; RAM GB à zéro (étendue à adapter)
        inx
        bne -
        ldx #$4F
-       sta $FF80,x                 ; HRAM (vecteurs 6502 en $FFFA épargnés)
        dex
        bpl -
        ldy #0
        tsx
        stx tick_sp
        jsr G_INIT                  ; ex. Tennis : G_0A9D, G_3297, G_2159
        lda #0
        sta game_over
        lda #MEM_IO
        sta $01
        rts

; Joypad : même mise à jour que la routine joypad de la ROM (A = touches du
; moment). Adresses de Tennis ($21ED) : à relever dans chaque jeu.
H_PAD       = $FF9A             ; maintenu
H_PRS       = $FF9B             ; nouvellement pressé
H_PADPREV   = $FF9E
gb_set_pad
        sta zW
        eor H_PADPREV
        and zW
        sta H_PRS
        lda zW
        sta H_PAD
        sta H_PADPREV
        rts

; Un pas de logique : les appels de la boucle principale GB pendant le jeu.
; Appelé avec $01 = MEM_RAM. Sortie anticipée possible par S_SCREEN.
gb_tick ldy #0
        tsx
        stx tick_sp
        jmp G_TICK                  ; ex. Tennis : G_1F8E, G_0B7D, G_10ED, G_17A0, G_2720

tick_sp     .byte 0
sfx_req     .byte 0
game_over   .byte 0
