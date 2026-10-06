; ===========================================================================
; gb_support.asm - ce que la logique GB traduite attend autour d'elle
;
;   G_RST08 / G_RST18 / G_RST28 : les routines RST de la ROM ($0008-$0033),
;     appelées par CALL (mêmes effets : table de sauts, lecture et copie de
;     données placées juste après l'appel).
;   S_SOUND  : remplace $3665 (jouer un son) : mémorise la demande.
;   S_SCREEN : remplace $016D (changement d'écran selon $FF8A).
;   S_RET    : remplace $1F6B (musique) et $227C (mode démo).
;   gb_new_match / gb_tick : séquences d'appel reprises de la ROM.
; ===========================================================================

; $0008 : saut indexé. A = index, table de DW juste après le CALL.
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

; $0018 : lecture indexée. Après le CALL : DB N puis N octets.
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

; $0028 : copie en ligne. Après le CALL : DB N puis N octets copiés vers (DE).
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

; $3665 : demande de son (A = numéro GB). Tous les registres sont conservés.
S_SOUND:
        ld (sfx_req),a
        ret

S_RET:
        ret

; $016D : la ROM change d'écran selon $FF8A. Comme sur GB (qui repart de
; zéro avec LD SP,$DFFF), le reste du pas de jeu est abandonné : on revient
; directement à l'appelant de gb_tick. Ici on reste sur le court :
;   3    : fin d'un jeu -> nouveau jeu ($02F2 : appel de $2159)
;   8    : changement de côté au tie-break -> on continue
;   $0A  : fin du match
S_SCREEN:
        ld sp,(tick_sp)
        ld a,(H_SCREEN)
        cp $0A
        jr z,.over
        cp 3
        ret nz
        jp G_2159
.over:
        ld a,1
        ld (match_over),a
        ret

; --- Réglage de jouabilité (hors ROM) ------------------------------------------
; Coups du joueur 1 en échange avec gauche, droite ou haut tenu à l'impact :
; vitesse latérale (B_VX, GB $C050) et vitesse de montée (B_VZ, GB $C052) x SHOT_SCALE/256.
; La longueur d'un coup dépend de sa vitesse de montée (la gravité, calculée
; par $165C, suit la vitesse de profondeur) : -10 % de montée = coup ~10 %
; moins long. Pour retrouver le comportement exact du Game Boy, retirer la
; ligne $10A6 de PATCHES dans tools/gb2z80.py.
SHOT_SCALE  equ 230                 ; ~90 %

S_P1SHOT:
        push af
        push bc
        ld a,(H_PAD1)
        and PAD_L | PAD_R | PAD_U
        jr z,.go
        ld a,(B_VX)                ; vx (signe-module)
        ld c,a
        and $7F
        call shot_scale
        ld b,a
        ld a,c
        and $80
        or b
        ld (B_VX),a
        ld a,(B_VZ)                ; vz, si la balle monte (pas le smash)
        bit 7,a
        jr nz,.go
        call shot_scale
        ld (B_VZ),a
.go:
        pop bc
        pop af
        jp G_165C

; A = A * SHOT_SCALE / 256
shot_scale:
        ld e,SHOT_SCALE
        call mul8
        ld a,h
        ret

; Nouveau match : séquence de la ROM après la sélection du niveau
; ($0574 : $0A9D, puis $02E3 : $FFC4, $FF95, $3297, puis $02F2 : $2159).
gb_new_match:
        ld a,(W_LEVEL)
        push af
        ld hl,GB_WRAM               ; RAM GB à zéro ($3027)
        ld de,GB_WRAM+1
        ld bc,$FF
        ld (hl),0
        ldir
        pop af
        ld (W_LEVEL),a
        ld hl,GB_HRAM
        ld de,GB_HRAM+1
        ld bc,$7E
        ld (hl),0
        ldir
        ld a,$FF                    ; son : canaux libres ($361C)
        ld (GB_SNDRAM),a
        ld a,(sets)                 ; options après l'écran titre ($0293) :
        cp 1                        ; bit 2 musique, bit 3 match en 1 set ($2105)
        ld a,4
        jr nz,.opt
        set 3,a
.opt:
        ld (H_OPT),a
        call G_0A9D                 ; fiche de niveau
        xor a
        ld (H_SETS),a
        dec a
        ld (H_SIDE95),a
        call G_3297                 ; remise à zéro du match
        call G_2159                 ; nouveau jeu
        ld a,3                      ; écran : court ($038B)
        ld (H_SCREEN),a
        xor a
        ld (match_over),a
        ret

; Un pas de jeu : les appels de $0680 (hors pause, lien série, défilement
; et IA de démonstration) : déroulement du match, J1, J2, balle, IA.
gb_tick:
        ld (tick_sp),sp             ; pile à restaurer si la ROM change d'écran
        call G_1F8E
        call G_0B7D
        call G_10ED
        call G_17A0
        jp G_2720

; Joypad : même mise à jour que $21ED (A = touches du moment)
gb_set_pad:
        ld c,a
        ld a,(H_PADPREV)
        xor c
        and c
        ld (H_PRS1),a
        ld (H_PRS99),a
        ld a,c
        ld (H_PAD1),a
        ld (H_PADPREV),a
        ld (H_PAD98),a
        ret


; H:L = A x E (8 x 8 bits ; repris de la version Spectrum)
mul8:
        ld h,a
        ld l,0
        ld d,0
        ld b,8
.l:
        add hl,hl
        jr nc,.n
        add hl,de
.n:
        djnz .l
        ret
