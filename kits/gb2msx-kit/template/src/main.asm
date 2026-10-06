; ===========================================================================
; MSX Tennis - portage MSX1 du Tennis Game Boy (Nintendo, 1989), cartouche 32 Ko
; Assembleur : sjasmplus. La logique du jeu est la ROM GB traduite en Z80
; (gb/gb_logic.asm, comme pour le Spectrum, le CPC et la ColecoVision).
;
; Même VDP que la ColecoVision (TMS9918A) : mode graphique 2, le stade GB
; (256 pixels de large) remplit l'écran. Son : PSG AY-3-8910.
; Cadence : 60 ou 50 Hz selon la machine (octet $002B du BIOS). La logique
; garde le rythme du GB (59,7 Hz) : à 50 Hz, 6 pas toutes les 5 trames.
;
; Règle d'or du VDP (sur une vraie machine, un accès trop rapide pendant
; l'affichage est perdu) : la mémoire vidéo n'est modifiée que
;   - écran éteint, interruptions coupées (dessin du décor, du titre) ;
;   - dans l'interruption de trame, à partir de ce que la boucle principale
;     a préparé en RAM (frame_ready).
; tools/msxsim.py le vérifie à chaque accès.
; ===========================================================================

        DEVICE NOSLOT64K
        INCLUDE "defs.asm"
        INCLUDE "vars.asm"

; =====================================================================================
; Cartouche : $4000-$BFFF
; =====================================================================================
        ORG $4000
        db "AB"                     ; en-tête de cartouche MSX
        dw init                     ; appelée par le BIOS au démarrage
        dw 0, 0, 0                  ; instruction BASIC, périphérique, programme BASIC
        ds 6, 0

init:
        di
        ld sp,STACK_TOP
        ; la page $8000-$BFFF : même slot que la page $4000 (où le BIOS nous a appelés)
        call RSLREG
        rrca
        rrca
        and 3
        ld c,a
        ld b,0
        ld hl,EXPTBL
        add hl,bc
        ld a,(hl)
        and $80                     ; slot étendu ?
        or c
        ld c,a
        inc hl                      ; SLTTBL = EXPTBL + 4
        inc hl
        inc hl
        inc hl
        ld a,(hl)
        and $0C
        or c
        ld h,$80
        call ENASLT
        di
        ld hl,$C000                 ; notre RAM à zéro
        ld de,$C001
        ld bc,$7FF
        ld (hl),0
        ldir
        ld a,(MSXID1)               ; 50 ou 60 Hz
        and $80
        ld (hz50),a
        ld hl,IM2_TABLE             ; IM 2 : table de 257 octets $C5 -> $C5C5
        ld de,IM2_TABLE+1
        ld bc,256
        ld (hl),IM2_JUMP >> 8
        ldir
        ld a,$C3
        ld (IM2_JUMP),a
        ld hl,isr
        ld (IM2_JUMP+1),hl
        ld a,IM2_TABLE >> 8
        ld i,a
        im 2
        call vdp_init
        call sound_init
        ld a,1
        ld (W_LEVEL),a
        ld (two_buttons),a          ; 2 boutons par défaut (tir 1 : frapper, tir 2 : lob)
        ld a,3
        ld (sets),a
.loop:
        IFNDEF AUTOPLAY
        call menu
        ENDIF
        call play_match
        jr .loop

; --- Interruption du VDP : retour de trame -----------------------------------------
; Lit l'état du VDP (acquittement), puis envoie ce qui a été préparé.
; (La boucle principale ne touche au VDP qu'interruptions coupées.)
isr:
        push af
        push hl
        in a,(VDP_CTRL)             ; acquittement
        ld hl,frames
        inc (hl)
        ld a,(frame_ready)
        or a
        jr z,.out
        push bc
        push de
        call vblank_update
        pop de
        pop bc
        xor a
        ld (frame_ready),a
.out:
        pop hl
        pop af
        ei
        reti

; Attend la prochaine interruption de trame, en faisant tourner le hasard du
; jeu (comme la boucle principale du GB, qui appelle $00A9 en attendant).
wait_frame:
        ld a,(frames)
        ld (wn_last),a
.w:
        call G_00A9
        ld a,(wn_last)
        ld b,a
        ld a,(frames)
        cp b
        jr z,.w
        ret

; pas de logique par trame : à 60 Hz, 1 ; à 50 Hz, 2,1,1,1,1 (6 pour 5 trames)
tick_pat60: db 1, 1, 1, 1, 1
tick_pat50: db 2, 1, 1, 1, 1

; --- Match -------------------------------------------------------------------------

play_match:
        call court_screen
        call gb_new_match
        call spr_reset
        xor a
        ld (fire_mode),a
        call show_score_force
        ld a,(frames)
        ld (last_frame),a
.frame:
        call wait_frame
        ld a,(frames)               ; trames écoulées
        ld hl,last_frame
        sub (hl)
        cp 4                        ; au plus 3 trames de retard rattrapées
        jr c,.lag
        ld a,3
.lag:
        ld b,a
        ld (elapsed),a
        ld a,(frames)
        ld (hl),a
.due:
        ld a,(tick_phase)           ; pas de logique dus (rythme GB exact)
        ld e,a
        ld d,0
        ld hl,tick_pat60
        ld a,(hz50)
        or a
        jr z,.p60
        ld hl,tick_pat50
.p60:
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
        IFDEF AUTOPLAY
        ld a,(elapsed)
        cp 2                        ; test : trames en retard
        jr c,.ontime
        ld hl,(lag_count)
        inc hl
        ld (lag_count),hl
.ontime:
        call bot_pad
        ELSE
        call read_pad
        call apply_fire
        ENDIF
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
        call prepare_all
        call show_score
        IFDEF AUTOPLAY
        call show_lag
        ENDIF
        ld a,1                      ; tout est prêt pour la prochaine interruption
        ld (frame_ready),a
        call play_sfx
        ld a,(match_over)
        or a
        jp z,.frame
        ; fin du match
        call wait_frame
        ld a,(H_SETS)
        bit 7,a
        ld hl,txt_win
        jr z,.w
        ld hl,txt_lose
.w:
        call announce
        ld a,1
        ld (frame_ready),a
        ld b,150
.p:
        push bc
        call wait_frame
        call play_sfx
        pop bc
        djnz .p
        jp sound_off

txt_win:  db "YOU WIN!",0
txt_lose: db "CPU WINS",0

        IFDEF AUTOPLAY
; Test : trames en retard / 256 trames, dans le cadre du score
show_lag:
        ld hl,(total_count)
        inc hl
        ld (total_count),hl
        ld a,l                      ; affiché toutes les 64 trames seulement
        and 63
        ret nz
        ld hl,ann_buf
        ld (sb_ptr),hl
        ld a,(lag_count+1)
        call sb_num2
        ld a,'/'
        call sb_char
        ld a,(total_count+1)
        call sb_num2
        ld hl,VR_NAME + 32 + 8
        ld de,ann_buf
        ld b,5
        jp add_job
        INCLUDE "autoplay.asm"
        ENDIF

        INCLUDE "vdp.asm"
        INCLUDE "gb_support.asm"
        INCLUDE "render.asm"
        INCLUDE "proj.asm"
        INCLUDE "input.asm"
        INCLUDE "text.asm"
        INCLUDE "sound.asm"
        IFNDEF AUTOPLAY
        INCLUDE "menu.asm"
        INCLUDE "../gfx/title.asm"
        ENDIF
        INCLUDE "../gfx/court.asm"
        INCLUDE "../gfx/font.asm"
        INCLUDE "../gfx/sprites.asm"
        INCLUDE "../gb/gb_logic.asm"
rom_end:
        ASSERT rom_end <= $C000, "cartouche pleine"
        DISPLAY "cartouche : ", /D, rom_end - $4000, " octets sur 32768"

        SAVEBIN "../build/tennis.rom", $4000, $8000
