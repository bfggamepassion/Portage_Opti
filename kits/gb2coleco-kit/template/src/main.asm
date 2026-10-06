; ===========================================================================
; Coleco Tennis - portage ColecoVision du Tennis Game Boy (Nintendo, 1989)
; Assembleur : sjasmplus. La logique du jeu est la ROM GB traduite en Z80
; (gb/gb_logic.asm, comme pour le Spectrum et le CPC), avec la RAM GB
; déplacée dans le 1 Ko de la console (voir defs.asm).
;
; Écran : mode graphique 2 du TMS9918A (256x192). Le stade GB fait 256
; pixels de large : il remplit l'écran (rangées GB 2 à 25).
; Cadence : 60 trames/s, un pas de logique GB par trame (59,7 Hz sur GB).
;
; Règle d'or du VDP (sur une vraie console, un accès trop rapide pendant
; l'affichage est perdu) : la mémoire vidéo n'est modifiée que
;   - écran éteint et NMI coupée (dessin du décor, du titre) ;
;   - dans la NMI, pendant le retour de trame, à partir de ce que la boucle
;     principale a préparé en RAM (frame_ready).
; tools/cvsim.py le vérifie à chaque accès.
; ===========================================================================

        DEVICE NOSLOT64K
        INCLUDE "defs.asm"
        INCLUDE "vars.asm"

; =====================================================================================
; Cartouche : $8000-$FFFF
; =====================================================================================
        ORG $8000
        db $55, $AA                 ; $55 $AA : démarrage direct (sans l'écran du BIOS)
        dw 0, 0, 0, 0               ; tables du BIOS (inutilisées)
        dw start
        jp rst_ret                  ; $800C-$801B : RST 08 à 30
        jp rst_ret
        jp rst_ret
        jp rst_ret
        jp rst_ret
        jp rst_ret
        jp irq                      ; $801E : RST 38 / IRQ
        jp nmi                      ; $8021 : NMI (VDP, à chaque trame)
        db "COLECO TENNIS/NINTENDO GAME BOY PORT/2026"

rst_ret:
        ret
irq:
        ei
        reti

start:
        di
        xor a                       ; d'abord : la NMI ne touche plus au VDP
        ld (vdp_free),a
        ld sp,STACK_TOP
        ld hl,$7000                 ; RAM à zéro (vdp_free = 0 : NMI inactive)
        ld de,$7001
        ld bc,$3FF
        ld (hl),0
        ldir
        call vdp_init
        call sound_init
        ld a,1
        ld (W_LEVEL),a
        ld (two_buttons),a          ; 2 boutons par défaut (gauche : frapper, droit : lob)
        ld a,3
        ld (sets),a
.loop:
        IFNDEF AUTOPLAY
        call menu
        ENDIF
        call play_match
        jr .loop

; --- NMI : retour de trame ---------------------------------------------------------
; Si la boucle principale n'est pas en train d'utiliser le VDP (vdp_free),
; lit l'état du VDP (acquittement) puis envoie ce qui a été préparé.
nmi:
        push af
        push hl
        ld hl,frames
        inc (hl)
        ld a,(vdp_free)
        cp VDP_FREE
        jr nz,.out                  ; VDP en cours d'utilisation : ne pas y toucher
        in a,(VDP_CTRL)             ; acquittement
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
        retn

; Attend la prochaine NMI, en faisant tourner le hasard du jeu (comme la
; boucle principale du GB, qui appelle $00A9 en attendant l'interruption).
wait_nmi:
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
        call wait_nmi
        ld a,(frames)               ; pas de logique : un par trame écoulée
        ld hl,last_frame
        sub (hl)
        cp 4                        ; au plus 3 trames de retard rattrapées
        jr c,.lag
        ld a,3
.lag:
        ld (ticks_due),a
        ld a,(frames)
        ld (hl),a
        IFDEF AUTOPLAY
        ld a,(ticks_due)
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
        ld a,1                      ; tout est prêt pour la prochaine NMI
        ld (frame_ready),a
        call play_sfx
        ld a,(match_over)
        or a
        jr z,.frame
        ; fin du match
        call wait_nmi
        ld a,(H_SETS)
        bit 7,a
        ld hl,txt_win
        jr z,.w
        ld hl,txt_lose
.w:
        call announce
        ld a,1
        ld (frame_ready),a
        ld b,180
.p:
        push bc
        call wait_nmi
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
        ASSERT rom_end <= $10000, "cartouche pleine"
        DISPLAY "cartouche : ", /D, rom_end - $8000, " octets sur 32768"

        SAVEBIN "../build/tennis.rom", $8000, $8000
