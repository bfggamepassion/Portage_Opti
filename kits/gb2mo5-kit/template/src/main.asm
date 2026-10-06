; ===========================================================================
; MO5 Tennis - portage Thomson MO5 du Tennis Game Boy (Nintendo, 1989)
; Assembleur : asm6809. La logique du jeu est la ROM GB traduite en 6809
; (gb/gb_logic.asm, tools/gb2m6809.py), vérifiée pas à pas contre le jeu.
; Cassette : LOADM"",,R (chargement en $3000, lancement en start).
;
; Écran : 320x200, 2 couleurs par groupe de 8 pixels. Le stade GB entier
; (256 pixels de large, rangées 2 à 26) est au centre, le score sur les côtés.
; Cadence : trames de 50 Hz (fin de l'image lue sur $A7E7, sans interruption).
; La logique garde le rythme du GB (59,7 Hz) : 6 pas toutes les 5 trames.
; L'image est recomposée après les pas de jeu dus (render.asm) : ~25 images/s.
; ===========================================================================

        include "defs.asm"
        include "vars.asm"
        include "config.asm"

        org $3000
        setdp DPAGE

start   orcc #$50                   ; interruptions coupées
        lds #STACK_TOP
        lda #DPAGE
        tfr a,dp
        ldx #$9400                  ; RAM de travail à zéro ($9400-$9FFF)
st_z    clr ,x+
        cmpx #$A000
        bne st_z
        lda #PIA_FORM
        sta PIA_A
        sta pia_a
        lda #1
        sta W_LEVEL
        clr two_buttons             ; un seul bouton (ESPACE), lob automatique
        lda #3
        sta sets
        clr sfx_bit
st_loop
        if AUTOPLAY==0
        jsr menu
        endif
        jsr play_match
        bra st_loop

; Compte les trames : fin de l'image (bit 7 de $A7E7 qui passe de 1 à 0).
; Appelée souvent (attente, clavier, chaque case redessinée, entre les pas
; de jeu). Registres conservés.
poll_frame
        pshs a
        lda GA_INIT
        anda #$80
        cmpa prev_init
        beq pf_r
        sta prev_init
        bne pf_r                    ; début de l'image : rien
        inc frames                  ; fin de l'image : une trame de plus
pf_r    puls a,pc

; Attend une nouvelle trame, en faisant tourner le hasard du jeu (comme la
; boucle principale du GB, qui appelle $00A9 en attendant l'interruption)
wait_frame
wf_l    jsr G_00A9
        jsr poll_frame
        lda frames
        cmpa last_frame
        beq wf_l
        rts

; pas de logique par trame de 50 Hz : 2,1,1,1,1 (6 pour 5 trames)
tick_pat fcb 2,1,1,1,1

; --- Match -------------------------------------------------------------------------
play_match
        jsr court_screen
        jsr gb_new_match
        clr fire_mode
        lda #$FF
        sta shown_ann
        jsr show_score_force
        lda frames
        sta last_frame
pm_frame
        jsr wait_frame
        lda frames                  ; trames écoulées (6 au plus)
        suba last_frame
        cmpa #6
        bls pm_e
        lda #6
pm_e    sta elapsed
        ldb frames
        stb last_frame
        tfr a,b
pm_due  pshs b                      ; pas dus (rythme GB exact)
        ldx #tick_pat
        ldb tick_phase
        lda b,x
        adda ticks_due
        sta ticks_due
        incb
        cmpb #5
        blo pm_ph
        clrb
pm_ph   stb tick_phase
        puls b
        decb
        bne pm_due
        if AUTOPLAY
        lda elapsed                 ; test : trames perdues (plus de 3 par image)
        cmpa #4
        blo pm_ot
        ldd lag_count
        addd #1
        std lag_count
pm_ot   jsr bot_pad
        else
        jsr read_pad
        jsr apply_fire
        endif
        sta pad_now
pm_tick lda ticks_due
        beq pm_tk
        deca
        sta ticks_due
        lda pad_now
        jsr gb_set_pad
        jsr gb_tick
        jsr poll_frame
        bra pm_tick
pm_tk   jsr prepare_all
        jsr compose_dirty
        jsr show_score
        jsr play_sfx
        if AUTOPLAY
        ldd total_count
        addd #1
        std total_count
        endif
        tst match_over
        lbeq pm_frame
        ; fin du match
        ldx #txt_win
        lda H_SETS
        bpl pm_w
        ldx #txt_lose
pm_w    jsr announce
        ldb #150
pm_p    pshs b
        lda frames
        sta last_frame
        jsr wait_frame
        puls b
        decb
        bne pm_p
        rts

txt_win  fcc " YOU WIN! "
         fcb 0
txt_lose fcc " CPU WINS "
         fcb 0

        if AUTOPLAY
        include "autoplay.asm"
        endif

        include "menu.asm"
        include "gb_support.asm"
        include "render.asm"
        include "proj.asm"
        include "text.asm"
        include "input.asm"
        include "sound.asm"
        include "../gfx/court.asm"
        include "../gfx/tables.asm"
        include "../gfx/font.asm"
        include "../gfx/sprites.asm"
        include "../gb/gb_logic.asm"
prog_end
        if prog_end>$9400
        error "programme trop grand (zone de travail en $9400)"
        endif
