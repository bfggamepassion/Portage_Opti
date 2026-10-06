; ===========================================================================
; main.asm - squelette d'un portage Game Boy -> Amstrad CPC664 (sjasmplus)
; Repris de CPC Tennis. Les parties propres au jeu sont marquées « À FAIRE ».
;
; La logique du jeu est la ROM GB traduite en Z80 (gb/gb_logic.asm, généré
; par tools/gb2z80.py, le même traducteur que pour le Spectrum). Ce fichier :
; démarrage (firmware coupé, écran en $4000), interruption, boucle de jeu.
; Cadence : 50 trames/s ; la logique garde le rythme du GB (59,7 Hz) : 6 pas
; toutes les 5 trames (motif 2,1,1,1,1).
; ===========================================================================

        DEVICE NOSLOT64K
        INCLUDE "defs.asm"

        MACRO PROF col                  ; profilage : couleur de bordure (-DPROFILE)
        IFDEF PROFILE
        ld bc,$7F10
        out (c),c
        ld a,col
        out (c),a
        ENDIF
        ENDM

; =====================================================================================
; Partie A : $0200-$3FFF
; =====================================================================================
        ORG LOAD_ADDR
start:
        di
        ld sp,LOAD_ADDR             ; pile en $0100-$01FF
        call font_grab              ; police de la ROM (code en $8000+ : la ROM
                                    ; basse recouvre $0000-$3FFF)
        ld hl,reloc_src             ; bloc de données -> $C100
        ld de,RELOC
        ld bc,reloc_end - RELOC
        ldir
        call init_sprites           ; images décalées (lues en $4000, avant l'écran)
        ld bc,$7F00 + GA_MODE1      ; mode 1, ROM coupées
        out (c),c
        ld a,$C3                    ; IM 1 : saut en $0038 vers isr
        ld ($0038),a
        ld hl,isr
        ld ($0039),hl
        im 1
        ld bc,$BC0C                 ; CRTC R12/R13 : écran en $4000
        out (c),c
        ld bc,$BD10
        out (c),c
        ld bc,$BC0D
        out (c),c
        ld bc,$BD00
        out (c),c
        call sound_init
        ei
.loop:
        call menu
        call play_game
        jr .loop

; --- Interruption (300 Hz, 6 par trame) : compte le temps écoulé -------------
; (le début du dessin, lui, se cale sur le signal VSYNC : voir wait_frame)
isr:
        push af
        ld a,(int6)
        inc a
        cp 6
        jr c,.s
        ld a,(frames)
        inc a
        ld (frames),a
        xor a
.s:
        ld (int6),a
        pop af
        ei
        ret

frames: db 0
int6:   db 0

; Attend le début du signal VSYNC (PPI port B, bit 0). Le dessin commence
; alors en haut de la bordure, ~72 lignes avant que le faisceau n'atteigne
; l'image : pas de clignotement. (Compter les interruptions pour trouver le
; VSYNC s'est révélé peu fiable : une interruption retardée décalait le dessin.)
wait_frame:
        ld b,$F5
        in a,(c)
        rra
        ret c                       ; déjà dans le VSYNC (en retard de peu) : y aller
.w:
        call gb_idle
        ld b,$F5
        in a,(c)
        rra
        jr nc,.w
        ret

; Cale le compteur de trames sur le VSYNC : l'interruption qui suit le début
; du VSYNC (2 lignes après) devient la 1re des 6, et frames avance donc juste
; après chaque début de VSYNC, avant que la boucle de jeu ne le lise.
sync_frames:
        ld b,$F5
.a:
        in a,(c)
        rra
        jr c,.a                     ; attendre la fin du VSYNC en cours
.b:
        in a,(c)
        rra
        jr nc,.b                    ; puis le début du suivant
        xor a
        ld (int6),a
        ret

; --- Écran ------------------------------------------------------------------------

set_inks:
        ld hl,court_inks
        ld c,0
.l:
        ld b,GA
        out (c),c                   ; encre c
        ld a,(hl)
        out (c),a                   ; couleur
        inc hl
        inc c
        ld a,c
        cp 4
        jr nz,.l
        ld bc,$7F10                 ; bordure
        out (c),c
        ld a,COURT_BORDER
        out (c),a
        ret

; A = y (0-199) -> HL = adresse écran de la ligne
line_addr:
        ld l,a
        ld h,0
        add hl,hl
        ld de,line_tab
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; Écran noir (encre 3) puis décor : 25 rangées x 32 tuiles, colonnes 4-35
draw_court:
        ld hl,SCREEN
        ld de,SCREEN+1
        ld bc,$3FFF
        ld (hl),$FF
        ldir
        xor a
.r:
        push af
        call draw_court_row
        pop af
        inc a
        cp 25
        jr nz,.r
        ret

; A = rangée (0-24) : redessine les 32 tuiles de cette rangée
draw_court_row:
        ld l,a                      ; IX = court_map + rangée x 32
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,court_map
        add hl,de
        push hl
        pop ix
        add a,a
        add a,a
        add a,a
        call line_addr
        ld de,8                     ; colonne 4 = octet 8
        add hl,de
        ld b,32
.col:
        push bc
        push hl
        ld l,(ix+0)
        inc ix
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,court_tiles
        add hl,de
        ex de,hl
        pop hl
        push hl
        ld b,8
.ln:
        ld a,(de)
        ld (hl),a
        inc de
        inc hl
        ld a,(de)
        ld (hl),a
        inc de
        dec hl
        ld a,h
        add a,8
        ld h,a
        djnz .ln
        pop hl
        inc hl
        inc hl
        pop bc
        djnz .col
        ret

; À FAIRE : écran titre et menu (Tennis : titre en mode 0, 16 couleurs, et
; choix 1/2 boutons ; voir Amstrad/src/menu.asm du repo Tennis)
menu:
        ld bc,$7F00 + GA_MODE1
        out (c),c
        call set_inks
        call draw_court
        ld bc,12*256 + 11
        ld hl,txt_press
        call print_at
.w:
        call wait_frame
        ld a,5                      ; ESPACE
        call read_line
        and $80
        jr z,.go
        ld a,9                      ; tir 1 du joystick
        call read_line
        and $20
        jr nz,.w
.go:
        call wait_frame             ; relâchement
        ld a,5
        call read_line
        and $80
        jr z,.go
        ret
txt_press:  db "PRESS SPACE",0

; --- Partie ------------------------------------------------------------------------

tick_pattern: db 2, 1, 1, 1, 1
tick_phase:   db 0
ticks_due:    db 0
last_frame:   db 0
pad_now:      db 0

play_game:
        call draw_court             ; À FAIRE : décor du jeu
        call spr_init
        call gb_new_game
        call sync_frames
        ld a,(frames)
        ld (last_frame),a
.frame:
        call wait_frame
        PROF $4C
        call draw_all               ; juste après le début du VSYNC
        PROF $54
        ld a,(frames)               ; pas de logique dus pour les trames écoulées
        ld hl,last_frame
        sub (hl)
        cp 7                        ; au plus 6 trames de retard rattrapées
        jr c,.lag
        ld a,6
.lag:
        ld b,a
        ld a,(frames)
        ld (hl),a
        or a
        ld a,b
        or a
        jr z,.nodue
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
.nodue:
        call read_pad
        call apply_fire
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
        call prepare_all            ; places des sprites d'après la RAM GB
        call play_sfx
        ld a,(game_over)
        or a
        jp z,.frame
        ret

        INCLUDE "gb_support.asm"
        INCLUDE "render.asm"
        INCLUDE "update.asm"
        INCLUDE "input.asm"
        INCLUDE "text.asm"
        INCLUDE "sound.asm"
        INCLUDE "sprite.asm"
        INCLUDE "../gfx/sprites_meta.asm"
SlotTab:        ds 16 * NSLOTS
        INCLUDE "../gb/gb_logic.asm"
part_a_end:
        ASSERT part_a_end <= SCREEN, "partie A pleine"

; =====================================================================================
; Bloc de données déplacé en $C100 au démarrage (dans le fichier : en $4000)
; =====================================================================================
        ORG SCREEN
reloc_src:
        DISP RELOC
        INCLUDE "../gfx/court.asm"
        INCLUDE "../gfx/lines.asm"
reloc_end:
        ENT
        ASSERT reloc_end <= RELOC_END, "bloc déplacé trop grand"
        INCLUDE "../gfx/sprites_raw.asm"    ; lues au démarrage, puis écrasées par l'écran
        INCLUDE "../gfx/sprite_shift_tables.asm"
        ASSERT $ <= $8000

; =====================================================================================
; Partie B : $8000-$A5FF
; =====================================================================================
        ORG $8000
; Police de la ROM basse ($3800 : 8 octets par caractère) -> font (codes 32-95).
; Appelée avant de couper le firmware, interruptions coupées. La police
; d'Amstrad n'est pas distribuée avec le jeu : elle est lue dans la machine.
font_grab:
        ld bc,$7F00 + GA_MODE1_LROM
        out (c),c
        ld hl,$3800 + 32 * 8
        ld de,font
        ld bc,64 * 8
        ldir
        ld bc,$7F00 + GA_MODE1
        out (c),c
        ret
font:   ds 64 * 8

spr_area_b:     ds SPR_AREA_B_SIZE

part_b_end:
        ASSERT part_b_end <= $A600, "partie B pleine"

        SAVEBIN "../build/game.bin", LOAD_ADDR, part_b_end - LOAD_ADDR
