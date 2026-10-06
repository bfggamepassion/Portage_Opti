; ===========================================================================
; common.asm - $0000-$01FF, identique en base 0 (vues du rendu) et en
; banque 4 (vue du jeu) : le code qui change de configuration mémoire
; doit exister, octet pour octet, des deux côtés.
;
; cur_view : en base 0, la vue courante du moteur de rendu (écrite par
; set_view) ; en banque 4, toujours V_GAME. L'interruption lit donc la
; bonne valeur quelle que soit la vue qu'elle interrompt.
; ===========================================================================

        jp $                    ; $0000 : piège
        ds $0008 - $, 0
        jp render_entry         ; RST $08 : la boucle d'attente du jeu ($80E8)
        ds $0010 - $, 0
        jp lives_dec            ; RST $10 : perte d'une vie ($82D7, vue jeu)
        ds $0038 - $, 0

; --- Interruption du CPC (IM 1, 300 Hz) -----------------------------------------
isr:
        push af
        push bc
        push hl
        ld a,(cur_view)
        cp V_GAME
        jr z,.game
        ; interrompt le moteur de rendu : passer en vue jeu, sur la pile de la NMI
        ld (isr_sp),sp          ; (en base 0)
        ld bc,GA*256 + V_GAME
        out (c),c
        ld sp,GAME_STACK
        push af                 ; vue à rétablir
        call isr_body
        di                      ; (la NMI du jeu a pu faire EI)
        pop af
        ld b,GA
        out (c),a
        ld sp,(isr_sp)
        pop hl
        pop bc
        pop af
        ei
        ret
.game:
        call isr_body
        pop hl
        pop bc
        pop af
        ei
        ret

cur_view:   db V_GAME
isr_sp:     dw 0

; --- Passage du jeu au moteur de rendu (la boucle « jr $ » du jeu y saute) ---------
render_entry:
        di
        ld bc,GA*256 + V_BASE
        out (c),c
        ld a,V_BASE
        ld (cur_view),a
        ld sp,RSTACK
        ei
        jp render_main

; --- Démarrage du jeu (depuis init, en base 0) -----------------------------------------
go_game:
        ld bc,GA*256 + V_GAME
        out (c),c
        jp CART_START

        ASSERT $ <= $0200
        ds $0200 - $, 0
