; ===========================================================================
; main.asm - squelette d'un portage Game Boy -> ZX Spectrum 48K (sjasmplus)
; Repris de ZX Tennis. Les parties propres au jeu sont marquées « À FAIRE ».
;
; La logique du jeu est la ROM GB traduite en Z80 (gb/gb_logic.asm, généré
; par tools/gb2z80.py). Ce fichier fournit le reste : démarrage, interruption,
; menu, boucle de jeu, chargeur de la cassette.
;
; Cadence : affichage à 50 images/s ; la logique garde le rythme du GB
; (59,7 Hz) : 6 pas de logique toutes les 5 trames (motif 2,1,1,1,1), avec
; rattrapage plafonné si une image a pris du retard.
; ===========================================================================

        DEVICE ZXSPECTRUM48
        INCLUDE "defs.asm"

; Profilage (assembler avec -DPROFILE) : couleur de bordure pendant chaque
; partie de la boucle, mesurée par tools/zxrun.py. Sinon, bordure unie.
        MACRO PROF col
        IFDEF PROFILE
        ld a,col
        out ($FE),a
        ENDIF
        ENDM

; =====================================================================================
; Zone lente $6000-$7FFF : démarrage, menu, texte, décor
; =====================================================================================
        ORG CODE_START
start:
        di
        ld sp,CODE_START
        ; interruption IM2 : table de 257 x $FD -> saut en $FDFD -> isr
        ld hl,IM2_TABLE
        ld de,IM2_TABLE+1
        ld bc,256
        ld (hl),IM2_ISR >> 8
        ldir
        ld a,$C3
        ld (IM2_ISR),a
        ld hl,isr
        ld (IM2_ISR+1),hl
        ld a,IM2_TABLE >> 8
        ld i,a
        im 2
        ei
.loop:
        call menu
        call play_game
        jr .loop

cls:
        ld hl,SCREEN
        ld de,SCREEN+1
        ld bc,6143
        ld (hl),0
        ldir
        ld hl,ATTRS
        ld de,ATTRS+1
        ld bc,767
        ld (hl),ATTR_GAME
        ldir
        ld a,BORDER_COL
        out ($FE),a
        ret

; Menu : écran titre (le même que l'écran de chargement) + options
menu:
        xor a
        out ($FE),a
        ld hl,title_rle
        ld de,SCREEN
        call unrle
        ld bc,20*256 + 10
        ld hl,txt_play
        call print_at
.wait:
        call wait_frame
        ld a,$BF                    ; ENTRÉE L K J H
        in a,($FE)
        rra
        jr c,.wait
        ret

txt_play:   db "ENTER : play",0

        INCLUDE "text.asm"
        INCLUDE "unrle.asm"
        INCLUDE "../gfx/title.asm"
cold_end:
        ASSERT cold_end <= HOT_START    ; la zone lente ne doit pas déborder

; =====================================================================================
; Zone rapide $8000-$BFFF : tout ce qui tourne à chaque image
; =====================================================================================
        ORG HOT_START

isr:
        push af
        ld a,(frames)
        inc a
        ld (frames),a
        pop af
        ei
        reti

frames:     db 0

; Attend la prochaine trame. Sur GB, la boucle principale fait souvent
; tourner le générateur de hasard en attendant le VBlank : l'appeler ici
; aussi (Tennis : call G_00A9) pour garder le même comportement.
wait_frame:
        ld a,(frames)
        ld b,a
.w:
        ; call G_RANDOM              ; À FAIRE : hasard de la ROM, si besoin
        ld a,(frames)
        cp b
        jr z,.w
        ret

tick_pattern: db 2, 1, 1, 1, 1
tick_phase:   db 0
ticks_due:    db 0
last_frame:   db 0
pad_now:      db 0

play_game:
        call cls
        call spr_init
        call gb_new_game
        ld a,(frames)
        ld (last_frame),a
.frame:
        call wait_frame
        PROF 2
        call draw_all               ; juste après l'interruption : effacer + dessiner
        PROF 1
        ; pas de logique dus pour les trames écoulées (rythme GB exact)
        ld a,(frames)
        ld hl,last_frame
        sub (hl)
        cp 7                        ; au plus 6 trames de retard rattrapées
        jr c,.lag
        ld a,6
.lag:
        ld b,a
        ld a,(frames)
        ld (hl),a
.due:
        ld a,(tick_phase)
        ld e,a
        ld d,0
        ld hl,tick_pattern
        add hl,de
        ld a,(ticks_due)
        add a,(hl)
        ld (ticks_due),a
        ld a,e
        inc a
        cp 5
        jr c,.ph
        xor a
.ph:
        ld (tick_phase),a
        djnz .due
        call read_pad
        ld (pad_now),a
.tick:
        ld a,(ticks_due)
        or a
        jr z,.ticked
        dec a
        ld (ticks_due),a
        ld a,(pad_now)
        call gb_set_pad
        call gb_tick
        jr .tick
.ticked:
        PROF 3
        call prepare_all            ; positions des sprites d'après la RAM GB
        PROF BORDER_COL
        call play_sfx
        ld a,(game_over)
        or a
        jr z,.frame
        ret

; À FAIRE : lire la RAM GB (objets) et placer les sprites (spr_prepare /
; spr_hide), comme les routines d'affichage de la ROM (listes OAM).
prepare_all:
        ret

draw_all:
        ld a,1
        call spr_restore
        xor a
        call spr_restore
        xor a
        call spr_draw
        ld a,1
        jp spr_draw

        INCLUDE "gb_support.asm"
        INCLUDE "input.asm"
        INCLUDE "sprite.asm"
        INCLUDE "sound.asm"
        INCLUDE "../gb/gb_logic.asm"
hot_end:
        ASSERT hot_end <= GB_WRAM       ; ne pas déborder sur la RAM GB

; =====================================================================================
; Graphismes des sprites en $E000
; =====================================================================================
        ORG GFX_START
        INCLUDE "../gfx/sprites.asm"
gfx_end:
        ASSERT gfx_end <= IM2_ISR
        ASSERT gfx_end <= basic

; --- Cassette : chargeur BASIC + écran de chargement + code -------------------------
;   10 CLEAR VAL "24575": LOAD ""SCREEN$ : POKE VAL "23739",VAL "111":
;      LOAD ""CODE : LOAD ""CODE : LOAD ""CODE : RANDOMIZE USR VAL "24576"
; Le POKE (CURCHL) coupe l'affichage des en-têtes "Bytes:" par-dessus l'écran.
; VAL "..." : un nombre en texte prend moins de place que sa forme binaire.
        ORG $F800
basic:
        db 0, 10                    ; numéro de ligne
        dw basic_end - basic_line
basic_line:
        db $FD, $B0, '"24575"', ':'             ; CLEAR VAL "24575":
        db $EF, '""', $AA, ':'                  ; LOAD ""SCREEN$ :
        db $F4, $B0, '"23739"', ',', $B0, '"111"', ':'  ; POKE VAL "23739",VAL "111":
        db $EF, '""', $AF, ':'                  ; LOAD ""CODE :
        db $EF, '""', $AF, ':'                  ; LOAD ""CODE :
        db $EF, '""', $AF, ':'                  ; LOAD ""CODE :
        db $F9, $C0, $B0, '"24576"', $0D        ; RANDOMIZE USR VAL "24576"
basic_end:

        ORG SCREEN                  ; écran de chargement (mémoire de l'assembleur seulement)
        INCBIN "../gfx/title.scr"

; À FAIRE : nom du jeu (10 caractères au plus par bloc)
        EMPTYTAP "../build/game.tap"
        SAVETAP "../build/game.tap", BASIC, "GAME", basic, basic_end - basic, 10
        SAVETAP "../build/game.tap", CODE, "screen", SCREEN, 6912
        SAVETAP "../build/game.tap", CODE, "game1", CODE_START, cold_end - CODE_START
        SAVETAP "../build/game.tap", CODE, "game2", HOT_START, hot_end - HOT_START
        SAVETAP "../build/game.tap", CODE, "game3", GFX_START, gfx_end - GFX_START
