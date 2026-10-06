; ===========================================================================
; main.asm - squelette d'un portage Game Boy -> Commodore 64 (64tass -C)
; Repris de C64 Tennis. Les parties propres au jeu sont marquées « À FAIRE ».
;
; La logique du jeu est la ROM GB traduite en 6502 (gb/gb_logic_*.asm,
; générés par tools/gb2m6502.py). Ce fichier fournit le reste : démarrage,
; banques mémoire, interruption, boucle de jeu, entrées.
;
; Carte mémoire (celle de C64 Tennis) :
;   $0002-$0010  registres GB (zp.asm)
;   $0801-$3FFF  programme + 1er morceau de la logique traduite
;   $4000-$7FFF  banque VIC 1 : écran $4000, caractères $4800, sprites $5000-
;   $8000-$BFFF  2e morceau de la logique traduite
;   $C000-$C0FF  RAM GB ; $D000-$DFFF : RAM GB éventuelle, sous les E/S
;   $FF80-$FFCB  HRAM GB ; $FFFA-$FFFF vecteurs 6502 (ROM du C64 coupées)
; La logique tourne avec toute la RAM visible ($01 = $34) ; le reste du
; temps, $01 = $35 (RAM + entrées/sorties, sans BASIC ni KERNAL).
;
; Cadence : 50 trames/s (C64 PAL). La logique garde le rythme du GB
; (59,7 Hz) : 6 pas toutes les 5 trames (motif 2,1,1,1,1).
; ===========================================================================
        .cpu "6502"
        .include "zp.asm"

SCREEN      = $4000
CHARSET     = $4800
SPRITES     = $5000
SPRPTR      = SCREEN + $3F8
COLRAM      = $D800
MEM_IO      = $35               ; RAM + entrées/sorties
MEM_RAM     = $34               ; RAM partout (pour la logique)
BG_COLOR    = 5                 ; À FAIRE : couleurs du décor
PAD_A       = $01
PAD_B       = $02
PAD_R       = $10
PAD_L       = $20
PAD_U       = $40
PAD_D       = $80

        * = $0801                   ; ligne BASIC : 10 SYS start
        .word (+), 10
        .null $9e, format("%d", start)
+       .word 0

start   sei
        cld
        ldx #$FF
        txs
        lda #MEM_IO                 ; coupe BASIC et KERNAL
        sta $01
        lda #<nmi                   ; vecteurs en RAM
        sta $FFFA
        lda #>nmi
        sta $FFFB
        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF
        lda #$7F                    ; coupe les interruptions des CIA
        sta $DC0D
        sta $DD0D
        lda $DC0D
        lda $DD0D
        jsr video_init
        jsr sprites_init
        jsr font_init
        jsr sound_init
        lda #$01                    ; interruption raster, ligne 250
        sta $D01A
        lda #250
        sta $D012
        lda $D011
        and #$7F
        sta $D011
        lsr $D019
        ldy #0
        cli
-       jsr menu
        jsr play_game
        jmp -

nmi     rti

; Interruption raster : compte les trames, recopie les sprites. Peut arriver
; pendant la logique ($01 = $34) : on remet les entrées/sorties le temps de
; la traiter.
irq     pha
        lda $01
        pha
        lda #MEM_IO
        sta $01
        txa
        pha
        tya
        pha
        inc frames
        jsr vbl_sprites
        lsr $D019
        pla
        tay
        pla
        tax
        pla
        sta $01
        pla
        rti

frames  .byte 0

wait_frame
        lda frames
-       cmp frames
        beq -
        rts

video_init
        lda #$0B                    ; écran éteint pendant l'installation
        sta $D011
        lda $DD02                   ; banque VIC 1 ($4000-$7FFF)
        ora #3
        sta $DD02
        lda $DD00
        and #$FC
        ora #2
        sta $DD00
        lda #$02                    ; écran $4000, caractères $4800
        sta $D018
        lda #$08                    ; 40 colonnes (+$10 : multicolore)
        sta $D016
        lda #0
        sta $D020
        sta $D021
        ldx #0                      ; écran vide
        lda #$A0                    ; (caractère 128+32 : espace de la police)
-       sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2E8,x
        inx
        bne -
        lda #$1B
        sta $D011
        rts

; À FAIRE : écran titre et menu (voir C64/src/menu.asm du repo Tennis)
menu    #prt 12, 10, "PRESS FIRE TO PLAY"
-       jsr wait_frame
        lda $DC00
        and #$10
        bne -
-       jsr wait_frame              ; relâchement
        lda $DC00
        and #$10
        beq -
        rts

; --- Partie ------------------------------------------------------------------------
tick_pattern .byte 2, 1, 1, 1, 1
tick_phase  .byte 0
ticks_due   .byte 0
last_frame  .byte 0
pad_now     .byte 0

play_game
        lda #BG_COLOR               ; À FAIRE : installer le décor du jeu
        sta $D021
        jsr gb_new_game
        lda frames
        sta last_frame
_frame  jsr wait_frame
        jsr prepare_all             ; sprites d'après l'état du dernier pas
        jsr play_sfx
        ; pas de logique dus pour les trames écoulées (rythme GB exact)
        lda frames
        sec
        sbc last_frame
        cmp #7                      ; au plus 6 trames de retard rattrapées
        bcc +
        lda #6
+       tax
        lda frames
        sta last_frame
_due    ldy tick_phase
        lda ticks_due
        clc
        adc tick_pattern,y
        sta ticks_due
        iny
        cpy #5
        bcc +
        ldy #0
+       sty tick_phase
        dex
        bne _due
        ldy #0
        jsr read_pad
        sta pad_now
_tick   lda ticks_due
        beq _ticked
        dec ticks_due
        lda pad_now
        jsr gb_set_pad
        lda #MEM_RAM
        sta $01
        jsr gb_tick
        lda #MEM_IO
        sta $01
        jmp _tick
_ticked lda game_over
        beq _frame
        rts

; Joystick port 2 + clavier (Q A O P ESPACE) -> joypad GB
read_pad
        jsr read_keys
        sta zW+1
        lda $DC00
        eor #$FF
        and #$1F
        tax
        lda pad_map,x
        ora zW+1
        rts

; $DC00 : bit 0 haut, 1 bas, 2 gauche, 3 droite, 4 feu (0 = appuyé)
pad_map .for i := 0, i < 32, i += 1
        .byte ((i & 1) << 6) | ((i & 2) << 6) | ((i & 4) << 3) | ((i & 8) << 1) | ((i & 16) >> 4)
        .next

read_keys
        lda #0
        sta zW
        ldx #4
-       lda pk_row,x
        sta $DC00
        lda $DC01
        and pk_bit,x
        bne +
        lda zW
        ora pk_pad,x
        sta zW
+       dex
        bpl -
        lda #$FF
        sta $DC00
        lda zW
        rts
;           Q    A    O    P    ESPACE
pk_row  .byte $7F, $FD, $EF, $DF, $7F
pk_bit  .byte $40, $04, $40, $02, $10
pk_pad  .byte PAD_U, PAD_D, PAD_L, PAD_R, PAD_A

        .include "gb_support.asm"
        .include "render.asm"
        .include "text.asm"
        .include "sound.asm"
        .include "../gb/gb_logic_1.asm"
part1_end
        .cerror part1_end > SCREEN, "zone $0801-$3FFF pleine : ", part1_end

; =====================================================================================
; Banque VIC 1 : écran, jeu de caractères, sprites (À FAIRE : graphismes du jeu)
; =====================================================================================
        * = SPRITES
        .fill 64, 0                 ; image de sprite 64 ($5000) : vide
        .cerror * > $8000, "banque VIC pleine"

; =====================================================================================
; $8000-$BFFF : 2e morceau de la logique traduite
; =====================================================================================
        * = $8000
        .include "../gb/gb_logic_2.asm"
part2_end
        .cerror part2_end > $C000, "zone $8000-$BFFF pleine : ", part2_end
