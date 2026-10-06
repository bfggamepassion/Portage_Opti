; ===========================================================================
; gb_support.asm - ce que la logique GB traduite attend autour d'elle (6809)
;
;   G_RST08 / G_RST18 / G_RST28 : les routines RST de la ROM ($0008-$0033),
;     appelées par JSR (mêmes effets sur les registres GB que la version Z80 :
;     table de sauts, lecture et copie de données placées après l'appel).
;   S_SOUND  : remplace $3665 (jouer un son) : mémorise la demande.
;   S_SCREEN : remplace $016D (changement d'écran selon $FF8A).
;   S_RET    : remplace $1F6B (musique) et $227C (mode démo).
;   gb_new_match / gb_tick : séquences d'appel reprises de la ROM.
; Registres GB : A = A du 6809, B C D E H L = rB ... rL (page directe).
; ===========================================================================

; $0008 : saut indexé. A = index, table de FDB juste après le JSR.
; (GB : add a,a ; e = a ; d = 0 ; hl += de ; a = l ; jp (hl))
G_RST08
        puls x                      ; table
        lsla
        sta <rE
        clr <rD
        tfr a,b
        abx
        ldx ,x                      ; cible
        stx <rH
        lda <rL
        jmp ,x

; $0018 : lecture indexée. Après le JSR : FCB N puis N octets.
; A = octet[A] ; B = 0, C = N, HL = fin de la table ; on reprend après.
G_RST18
        puls x                      ; -> N
        ldb ,x+
        stb <rC
        clr <rB
        pshs x
        tfr a,b
        abx
        lda ,x
        puls x
        ldb <rC
        abx
        stx <rH
        jmp ,x

; $0028 : copie en ligne. Après le JSR : FCB N puis N octets copiés vers (DE).
G_RST28
        puls x
        ldb ,x+
        stb <rB
        ldu <rD
rst28_l lda ,x+
        sta ,u+
        dec <rB
        bne rst28_l
        stu <rD
        stx <rH
        jmp ,x

; $3665 : demande de son (A = numéro GB). Registres et indicateurs conservés.
S_SOUND
        pshs cc
        sta sfx_req
        puls cc,pc

S_RET
        rts

; $016D : la ROM change d'écran selon $FF8A. Comme sur GB (qui repart de
; zéro avec LD SP,$DFFF), le reste du pas de jeu est abandonné : on revient
; directement à l'appelant de gb_tick. Ici on reste sur le court :
;   3    : fin d'un jeu -> nouveau jeu ($02F2 : appel de $2159)
;   8    : changement de côté au tie-break -> on continue
;   $0A  : fin du match
S_SCREEN
        lds tick_sp
        lda H_SCREEN
        cmpa #$0A
        beq scr_over
        cmpa #3
        bne scr_ret
        jmp G_2159
scr_over
        lda #1
        sta match_over
scr_ret rts

; --- Réglage de jouabilité (hors ROM) ------------------------------------------
; Coups du joueur 1 en échange avec gauche, droite ou haut tenu à l'impact :
; vitesse latérale (B_VX) et vitesse de montée (B_VZ) x SHOT_SCALE/256
; (-10 % : coups ~10 % moins longs). Pour retrouver le comportement exact du
; Game Boy, retirer la ligne $10A6 de PATCHES dans port_config.py.
SHOT_SCALE  equ 230

S_P1SHOT
        pshs a,b,cc
        lda H_PAD1
        anda #PAD_L+PAD_R+PAD_U
        beq p1s_go
        lda B_VX                    ; vx (signe-module)
        tfr a,b
        andb #$7F
        lda #SHOT_SCALE
        mul                         ; A = |vx| x 230 / 256
        ldb B_VX
        andb #$80
        pshs b
        ora ,s+
        sta B_VX
        lda B_VZ                    ; vz, si la balle monte (pas le smash)
        bmi p1s_go
        tfr a,b
        lda #SHOT_SCALE
        mul
        sta B_VZ
p1s_go  puls a,b,cc
        jmp G_165C

; Nouveau match : séquence de la ROM après la sélection du niveau
; ($0574 : $0A9D, puis $02E3 : $FFC4, $FF95, $3297, puis $02F2 : $2159).
gb_new_match
        lda W_LEVEL
        pshs a
        ldx #GB_WRAM                ; RAM GB à zéro ($3027)
        clrb
nm_w    clr ,x+
        decb
        bne nm_w
        puls a
        sta W_LEVEL
        ldx #GB_HRAM
        ldb #$7E
nm_h    clr ,x+
        decb
        bne nm_h
        lda #$FF                    ; son : canaux libres ($361C)
        sta GB_SNDRAM
        lda #4                      ; options ($0293) : bit 2 musique,
        ldb sets                    ; bit 3 match en 1 set ($2105)
        cmpb #1
        bne nm_opt
        ora #8
nm_opt  sta H_OPT
        jsr G_0A9D                  ; fiche de niveau
        clr H_SETS
        lda #$FF
        sta H_SIDE95
        jsr G_3297                  ; remise à zéro du match
        jsr G_2159                  ; nouveau jeu
        lda #3                      ; écran : court ($038B)
        sta H_SCREEN
        clr match_over
        rts

; Un pas de jeu : les appels de $0680 (hors pause, lien série, défilement
; et IA de démonstration) : déroulement du match, J1, J2, balle, IA.
gb_tick
        sts tick_sp                 ; pile à restaurer si la ROM change d'écran
        jsr G_1F8E
        jsr G_0B7D
        jsr G_10ED
        jsr G_17A0
        jmp G_2720

; Joypad : même mise à jour que $21ED (A = touches du moment)
gb_set_pad
        pshs a
        eora H_PADPREV
        anda ,s
        sta H_PRS1
        sta H_PRS99
        puls a
        sta H_PAD1
        sta H_PADPREV
        sta H_PAD98
        rts
