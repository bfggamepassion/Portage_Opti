; ===========================================================================
; gb_support.asm - ce que la logique GB traduite attend autour d'elle
;
; À écrire pour chaque jeu, en lisant la ROM :
;   G_RSTxx   : les routines RST de la ROM ($0000-$003F), appelées par CALL.
;               Celles-ci sont les conventions de Tennis (courantes chez
;               Nintendo, mais à vérifier dans chaque ROM).
;   S_xxx     : remplaçants des routines non traduites (CFG.STUBS) : son,
;               VRAM, changements d'écran...
;   gb_new_game / gb_tick : les séquences d'appel de la boucle principale GB.
; ===========================================================================

; rst $08 : saut indexé. A = index, table de DW juste après le CALL.
G_RST08:
        pop hl
        add a,a
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

; rst $18 : lecture indexée. Après le CALL : DB N puis N octets.
; Renvoie A = octet[A] et reprend après la table.
G_RST18:
        pop hl
        ld c,a
        ld b,0
        ld a,(hl)
        inc hl
        push hl
        add hl,bc
        ld c,a
        ld a,(hl)
        pop hl
        add hl,bc
        jp (hl)

; rst $28 : copie en ligne. Après le CALL : DB N puis N octets copiés vers (DE).
G_RST28:
        pop hl
        ld b,(hl)
        inc hl
.copy:
        ld a,(hl)
        inc hl
        ld (de),a
        inc de
        dec b
        jr nz,.copy
        jp (hl)

; Demande de son (A = numéro GB) : mémorisée, jouée par play_sfx après
; l'affichage. Tous les registres sont conservés.
S_SOUND:
        ld (sfx_req),a
        ret

S_RET:
        ret

; Appelé en boucle pendant l'attente de la trame (wait_frame). Beaucoup de
; jeux GB font tourner leur générateur de hasard en attendant le VBlank :
; l'appeler ici (Tennis : jp G_00A9), sinon l'IA devient prévisible.
gb_idle:
        ret

; Changement d'écran demandé par la ROM. Sur GB, cela repart souvent de zéro
; (LD SP,...) : on abandonne le reste du pas de logique en revenant
; directement à l'appelant de gb_tick, puis on décide quoi faire.
S_SCREEN:
        ld sp,(tick_sp)
        ld a,1
        ld (game_over),a
        ret

; Nouvelle partie : reproduire la séquence de la ROM (mise à zéro de la RAM,
; options, appels d'initialisation), lue dans le désassemblage.
gb_new_game:
        ld hl,GB_WRAM
        ld de,GB_WRAM+1
        ld bc,$FF
        ld (hl),0
        ldir
        ld hl,GB_HRAM
        ld de,GB_HRAM+1
        ld bc,$7E
        ld (hl),0
        ldir
        call G_INIT                 ; ex. Tennis : G_0A9D, G_3297, G_2159
        xor a
        ld (game_over),a
        ret

; Un pas de logique : les appels de la boucle principale GB pendant le jeu
; (sans l'affichage, le lien série, la démo...).
gb_tick:
        ld (tick_sp),sp             ; pile à restaurer si la ROM change d'écran
        jp G_TICK                   ; ex. Tennis : G_1F8E, G_0B7D, G_10ED, G_17A0, G_2720

; Joypad : même mise à jour que la routine joypad de la ROM (A = touches
; du moment). Adresses de Tennis ($21ED) : à relever dans chaque jeu.
H_PAD       equ $FF9A               ; maintenu
H_PRS       equ $FF9B               ; nouvellement pressé
H_PADPREV   equ $FF9E
gb_set_pad:
        ld c,a
        ld a,(H_PADPREV)
        xor c
        and c
        ld (H_PRS),a
        ld a,c
        ld (H_PAD),a
        ld (H_PADPREV),a
        ret

tick_sp:    dw 0
sfx_req:    db 0
game_over:  db 0
