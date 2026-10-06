; ===========================================================================
; gamecode.asm - code de la « vue jeu » (banque 4, $0200-$0FFF), appelé par
; la cartouche corrigée ou par l'interruption :
;   - isr_body : trames, NMI simulée à 60 Hz ;
;   - VDP virtuel : les routines d'accès au VDP de la cartouche ($8054,
;     $805D, $8067, $85B9, $85C8, $8BDE) ;
;   - écran d'options (remplace GAME_OPT du BIOS) ;
;   - manettes (clavier et joystick du CPC) ; son (SN76489 -> AY).
; Tout tourne en V_GAME : état partagé en banque 5 ($4000-$7FFF),
; VRAM en $C000.
; ===========================================================================

; --- Interruption (300 Hz) ----------------------------------------------------------
; Compte les trames (VSYNC lu sur le PPI ; si une interruption a été retardée
; au point de rater le VSYNC, on compte quand même toutes les 6) et lance la
; NMI du jeu une interruption sur 5 (60 Hz) si le VDP l'autorise.
isr_body:
        push de
        ld b,$F5
        in a,(c)
        ld hl,int_phase
        rra
        jr c,.vs
        inc (hl)
        ld a,(hl)
        cp 6
        jr c,.tick
.vs:    ld (hl),0
        ld hl,frame_cnt
        inc (hl)
.tick:
        ld hl,int_cnt
        inc (hl)
        ld a,(nmi_div)          ; tick de jeu : 1 interruption sur 6 (50 Hz,
        cp (hl)                 ; ColecoVision PAL) ou sur 5 (60 Hz, NTSC)
        jr z,.go
        jr nc,.ret
.go:    ld (hl),0
        ld a,(start_pend)       ; scène de départ choisie au menu
        or a
        call nz,start_apply
        ld a,(vblank_st)
        or $80
        ld (vblank_st),a
        ld a,(vregs+1)
        and $20
        jr z,.ret
        xor a
        ld (kbd_ok),a           ; manettes à relire
        exx
        push bc
        push de
        push hl
        exx
        push ix
        push iy
        call CART_NMI           ; se termine par EI / RETI
        pop iy
        pop ix
        exx
        pop hl
        pop de
        pop bc
        exx
.ret:   pop de
        ret

int_phase:  db 0
nmi_div:    db 6                ; 6 : 50 Hz (PAL, défaut), 5 : 60 Hz (NTSC)

; Scène de départ du menu : écrite pendant l'écran « PLAYER 1 » (état $0A),
; avant que le jeu ne construise le décor : $6054 = n°, $6059 = son affichage BCD.
start_apply:
        ld a,($6000)
        cp $0A
        ret nz
        ld a,($6005)            ; pas au milieu d'un tick du jeu
        or a
        ret nz
        xor a
        ld (start_pend),a
        ld a,(start_scene)
        ld ($6054),a
        ld c,0
.bcd:   cp 10
        jr c,.bd
        sub 10
        inc c
        jr .bcd
.bd:    ld b,a
        ld a,c
        rlca
        rlca
        rlca
        rlca
        or b
        ld ($6059),a
        jp $8752                ; le jeu réaffiche « SCENE-nn » ($3AFC)
tile_off1:  dw 0              ; - base des motifs de tuiles
tile_off2:  dw 0              ; - base des couleurs

; --- VDP virtuel -----------------------------------------------------------------------

; vput : écrit A à l'adresse VRAM HL (0-$3FFF) et note ce que l'écriture change.
; Sortie : HL = adresse suivante. Détruit AF ; garde BC, DE.
vput:
        push de
        ld e,a
        ld a,h
        add a,LOW class_tab
        ld (.cl+1),a
.cl:    ld a,(class_tab)
        or a
        jr nz,.spec
.plain: ld a,h                  ; octet ordinaire
        or HIGH VRAM_G
        ld h,a
        ld (hl),e
.next:  inc hl
        ld a,h
        and $3F
        ld h,a
        pop de
        ret
.spec:
        cp C_SAT
        jr nz,.spec2
        call sat_flush
        jr .plain
.spec2: ld d,a
        ld a,h
        or HIGH VRAM_G
        ld h,a
        ld a,e
        cp (hl)
        jr z,.next              ; même valeur : rien ne change
        ld (hl),e
        ld a,h
        and $3F
        ld e,l
        dec d
        jr z,.name
        ld d,a                  ; DE = adresse VRAM
        call mark_ts
        jr .next
.name:  ; case de la table des noms : ajouter à la liste si elle n'y est pas
        and 3
        ld d,a                  ; DE = case (0-767)
        call mark_cell
        jr .next

; DE = adresse VRAM d'un motif de sprite ou de tuile (genre de sa page) :
; marque le motif modifié. Garde BC, DE, HL.
mark_ts:
        push hl
        ld a,d
        add a,LOW class_tab
        ld (.cl+1),a
.cl:    ld a,(class_tab)
        cp C_TILE
        jr z,.tile
        ; motif de sprite 16x16 : n° = (adresse / 32) AND 63
        ld a,e
        rlca
        rlca
        rlca
        and 7
        ld l,a
        ld a,d
        and 7
        rlca
        rlca
        rlca
        or l
        ld l,a
        ld h,HIGH spr_dirty
        ld a,l
        add a,LOW spr_dirty
        ld l,a
        ld (hl),1
        ld a,1
        ld (spr_req),a          ; au moins un motif de sprite modifié
        pop hl
        ret
.tile:  ; motif ou couleur de tuile : n° = (adresse - base) / 8
        push bc
        ld hl,(tile_off1)       ; - base des motifs
        add hl,de
        ld a,h
        cp $18                  ; dans les 6 Ko des motifs ?
        jr c,.tin
        ld hl,(tile_off2)       ; - base des couleurs
        add hl,de
.tin:   srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld bc,pat_dirty
        add hl,bc
        ld (hl),1
        ld a,1
        ld (tile_req),a
        pop bc
        pop hl
        ret

; DE = case (0-767) : à redessiner (ajoutée à la liste si elle n'y est pas).
; Garde BC, DE, HL.
mark_cell:
        push hl
        ld hl,MEMO_OWN          ; case d'un rectangle mémorisé : il n'est plus en place
        add hl,de
        ld a,(hl)
        or a
        jr z,.nown
        ld (hl),0
        dec a
        rlca
        rlca
        rlca
        rlca
        ld l,a
        ld h,HIGH MEMO_TAB
        ld (hl),0
.nown:
        ld a,d
        add a,HIGH dirty_flag
        ld h,a
        ld l,e                  ; HL = dirty_flag + case (dirty_flag aligné sur 1 Ko)
        ld a,(hl)
        or a
        jr nz,.done
        inc (hl)
        push bc
        ld hl,(dirty_ptr)       ; liste courante
        ld a,(hl)               ; nombre d'entrées
        cp DIRTY_MAX
        jr nc,.full
        inc (hl)
        ld c,a
        ld b,0
        inc hl
        add hl,bc
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        pop bc
.done:  pop hl
        ret
.full:  ld a,1
        ld (names_ovf),a
        pop bc
        pop hl
        ret

; Registre du VDP : D = $80 + n, E = valeur
vreg_write:
        push hl
        push bc
        ld a,d
        and 7
        ld l,a
        ld h,0
        ld bc,vregs
        add hl,bc
        ld a,(hl)
        ld (hl),e
        cp e
        jr z,.done
        ld a,d
        and 7
        cp 1
        jr z,.done              ; registre 1 : lu par l'interruption et le rendu
        cp 5
        jr z,.r5                ; table des sprites : lue chaque trame
        cp 7
        jr z,.done              ; couleur de fond : le rendu suit
        call build_classes
        ld a,1
        ld (full_req),a
.done:  pop bc
        pop hl
        ret
.r5:    call build_classes
        jr .done

; Table des sprites laissée en RAM : la recopier en VRAM (avant une écriture
; qui la touche). Garde tous les registres.
sat_flush:
        push af
        push hl
        ld hl,(sat_src)
        ld a,h
        or l
        jr z,.done
        push bc
        push de
        ld de,(sat_base)
        ld a,d
        or HIGH VRAM_G
        ld d,a
        ld a,(sat_len)
        ld c,a
        ld b,0
        or a
        jr z,.z
        ldir
.z:     ld hl,0
        ld (sat_src),hl
        pop de
        pop bc
.done:  pop hl
        pop af
        ret

; Genre de chaque page de VRAM, d'après les registres (mode graphique 2)
; Oublie tous les rectangles mémorisés (tables changées, écritures directes).
; Garde BC, DE, HL.
memo_reset:
        push bc
        push de
        push hl
        ld hl,MEMO_TAB
        ld de,16
        ld b,e
.l:     ld (hl),0
        add hl,de
        djnz .l
        pop hl
        pop de
        pop bc
        ret

build_classes:
        call memo_reset
        call sat_flush
        push de
        ld hl,class_tab
        ld b,64
.clr:   ld (hl),C_PLAIN
        inc hl
        djnz .clr
        ; motifs des sprites : (R6 AND 7) x $800, 8 pages
        ld a,(vregs+6)
        and 7
        add a,a
        add a,a
        add a,a
        ld b,8
        ld c,C_SPAT
        call .mark
        ; noms : (R2 AND $0F) x $400, 3 pages
        ld a,(vregs+2)
        and $0F
        add a,a
        add a,a
        ld b,3
        ld c,C_NAME
        call .mark
        ; motifs des tuiles : (R4 AND 4) x $800, 24 pages
        ld a,(vregs+4)
        and 4
        add a,a
        add a,a
        add a,a
        ld e,a                  ; page de base
        ld b,24
        ld c,C_TILE
        call .mark
        xor a
        sub e
        ld (tile_off1+1),a      ; -base (octet fort ; octet faible = 0)
        xor a
        ld (tile_off1),a
        ; couleurs : (R3 AND $80) x $40, 24 pages
        ld a,(vregs+3)
        and $80
        rrca
        rrca
        rrca
        rrca                    ; $80 -> $08 ... x $40 = $2000 : page $20
        add a,a
        add a,a
        ld e,a
        ld b,24
        ld c,C_TILE
        call .mark
        xor a
        sub e
        ld (tile_off2+1),a
        xor a
        ld (tile_off2),a
        ; table des sprites : (R5 AND $7F) x $80
        ld a,(vregs+5)
        and $7F
        ld l,0
        srl a
        rr l
        ld h,a
        ld (sat_base),hl
        ld e,a
        ld d,0
        ld hl,class_tab
        add hl,de
        ld (hl),C_SAT
        pop de
        ret
.mark:  ; A = 1re page, B = nombre, C = genre
        ld l,a
        ld h,0
        push de
        ld de,class_tab
        add hl,de
        pop de
.mk:    ld (hl),c
        inc hl
        djnz .mk
        ret

; $8054 : écrit A en VRAM à l'adresse DE (garde tout) -------------------------
hle_wr:
        push hl
        push af
        ld a,d
        and $3F
        ld h,a
        add a,LOW class_tab
        ld (.cl+1),a
.cl:    ld a,(class_tab)
        cp C_NAME
        jr nz,.gen
        ; table des noms : le jeu réécrit souvent la même valeur (lianes...)
        ld l,e
        ld a,h
        or HIGH VRAM_G
        ld h,a
        pop af
        push af
        cp (hl)
        jr nz,.gen
        inc hl
        ld a,h
        and $3F
        ld h,a
        ld (vaddr),hl
        pop af
        pop hl
        ei
        ret
.gen:   ld a,d
        and $3F
        ld h,a
        ld l,e
        pop af
        push af
        call vput
        ld (vaddr),hl
        pop af
        pop hl
        ei
        ret

; $A125 : boucle de dessin des lianes, réécrite (même effet) : HL = données,
; DE = adresse dans la table des noms. Octets : $FF fin (puis B, C, D lus
; à la suite) ; $FC/$FD/$FE : avancer DE de $21/$20/$1F ; sinon, écrire
; l'octet (sauf s'il y est déjà : le jeu réécrit tout à chaque trame).
vine_loop:
        bit 7,h
        jp z,.run               ; données en RAM : pas de mémo
        ; mémo (comme nrect_wr, entrées 8-15 de MEMO_TAB) : +1 DE, +3 HL,
        ; +5 B, +6 C, +7 HL, +9 DE de sortie ; cases dans MEMO_OWN
        push ix
        ld a,e
        and 7
        or 8
        rlca
        rlca
        rlca
        rlca
        ld ixl,a
        ld a,HIGH MEMO_TAB
        ld ixh,a
        ld a,(ix+0)
        or a
        jr z,.miss
        ld a,(ix+1)
        cp e
        jr nz,.miss
        ld a,(ix+2)
        cp d
        jr nz,.miss
        ld a,(ix+3)
        cp l
        jr nz,.miss
        ld a,(ix+4)
        cp h
        jr nz,.miss
        ld l,(ix+7)             ; déjà en place : sorties de l'original
        ld h,(ix+8)
        ld e,(ix+9)
        ld d,(ix+10)
        ld b,(ix+5)
        ld c,(ix+6)
        pop ix
        ld a,$FF
        cp $FF
        ret
.miss:  ld (ix+0),0
        ld (ix+1),e
        ld (ix+2),d
        ld (ix+3),l
        ld (ix+4),h
        call .run
        ld (ix+7),l
        ld (ix+8),h
        ld (ix+9),e
        ld (ix+10),d
        ld (ix+5),b
        ld (ix+6),c
        push af
        push bc
        push de
        push hl
        ld a,ixl                ; n° = entrée + 1
        rrca
        rrca
        rrca
        rrca
        inc a
        ld (.own+1),a
        ld l,(ix+3)             ; reparcourt les données : cases écrites
        ld h,(ix+4)
        ld e,(ix+1)
        ld a,(ix+2)
        and 3
        ld d,a                  ; DE = case (adresse AND $3FF)
.ws:    push de
.wl:    ld a,(hl)
        inc hl
        cp $FC
        jr nc,.wc
        push hl
        ld hl,MEMO_OWN
        add hl,de
        ld a,(hl)
        or a
        jr z,.own
        ld b,a
        ld a,(.own+1)
        cp b
        jr z,.own
        ld a,b                  ; case d'un autre mémo : il est recouvert
        dec a
        rlca
        rlca
        rlca
        rlca
        push hl
        ld l,a
        ld h,HIGH MEMO_TAB
        ld (hl),0
        pop hl
.own:   ld (hl),0               ; (n° de l'entrée, posé plus haut)
        pop hl
        inc de
        jr .wl
.wc:    cp $FF
        jr z,.we
        ld b,a
        ld a,$1D
        sub b
        pop de
        add a,e
        ld e,a
        jr nc,.ws
        inc d
        jr .ws
.we:    pop de
        ld (ix+0),1
        pop hl
        pop de
        pop bc
        pop af
        pop ix
        ret
.run:
        ld a,d
        or HIGH VRAM_G
        ld d,a                  ; DE : copie de la VRAM (hle_wr ignore les bits hauts)
.seg:   push de
.l:     ld a,(hl)
        inc hl
        cp $FC
        jr nc,.ctl
        ex de,hl
        cp (hl)                 ; déjà en place ?
        ex de,hl
        jr nz,.wr
        inc de
        jr .l
.wr:    call hle_wr
        inc de
        jr .l
.ctl:   cp $FF
        jr z,.end
        ld b,a
        ld a,$1D
        sub b                   ; $FC -> $21, $FD -> $20, $FE -> $1F
        pop de
        add a,e
        ld e,a
        jr nc,.seg
        inc d
        jr .seg
.end:   pop de
        ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld d,(hl)
        ret

; $A448 : copie d'un rectangle dans la VRAM (B rangées de C octets, HL =
; données, DE = adresse ; rangées de $20). Version native : le jeu la
; rappelle à chaque tick (jets d'eau, jauges...) avec les mêmes octets,
; on ne passe par hle_wr que pour ceux qui changent. En sortie comme
; l'original : HL après les données, DE + B*$20, B = 0, A = E.
;
; Mémo : un rectangle copié depuis la ROM (HL >= $8000) dans la table des
; noms est noté dans MEMO_TAB (entrées 0-7, choisie par E AND 7) :
;   +0 valide, +1 DE, +3 HL, +5 C, +6 B, +7 HL de sortie, +9 DE de sortie
; et ses cases dans MEMO_OWN. Toute écriture qui change une de ces cases
; (mark_cell) l'invalide ; tant qu'il est valide, le même appel n'a rien à
; faire. (IX est gardé.)
nrect_wr:
        bit 7,h
        jp z,.run               ; données en RAM : pas de mémo
        ld a,b
        cp 9
        jp nc,.run              ; au plus 8 rangées (2 pages)
        push hl                 ; les deux pages : table des noms ?
        ld a,d
        and $3F
        add a,LOW class_tab
        ld l,a
        ld h,HIGH class_tab
        ld a,(hl)
        cp C_NAME
        jr nz,.nopg
        inc l
        ld a,(hl)
        cp C_NAME
.nopg:  pop hl
        jp nz,.run
        push ix
        ld a,e
        and 7                   ; entrées 0-7 (8-15 : lianes)
        rlca
        rlca
        rlca
        rlca
        ld ixl,a
        ld a,HIGH MEMO_TAB
        ld ixh,a
        ld a,(ix+0)
        or a
        jr z,.miss
        ld a,(ix+1)
        cp e
        jr nz,.miss
        ld a,(ix+2)
        cp d
        jr nz,.miss
        ld a,(ix+3)
        cp l
        jr nz,.miss
        ld a,(ix+4)
        cp h
        jr nz,.miss
        ld a,(ix+5)
        cp c
        jr nz,.miss
        ld a,(ix+6)
        cp b
        jr nz,.miss
        ld l,(ix+7)             ; déjà en place : sorties de l'original
        ld h,(ix+8)
        ld e,(ix+9)
        ld d,(ix+10)
        pop ix
        ld b,0
        ld a,e
        ret
.miss:  ld (ix+0),0
        ld (ix+1),e
        ld (ix+2),d
        ld (ix+3),l
        ld (ix+4),h
        ld (ix+5),c
        ld (ix+6),b
        call .run
        ld (ix+7),l
        ld (ix+8),h
        ld (ix+9),e
        ld (ix+10),d
        push af
        push bc
        push de
        push hl
        ld a,ixl                ; n° = entrée + 1
        rrca
        rrca
        rrca
        rrca
        inc a
        ld (.own+1),a
        ld e,(ix+1)             ; case = adresse AND $3FF (table alignée sur 1 Ko)
        ld a,(ix+2)
        and 3
        ld d,a
        ld hl,MEMO_OWN
        add hl,de
        ld b,(ix+6)
.orow:  push hl
        ld c,(ix+5)
.ocol:  ld a,(hl)
        or a
        jr z,.own
        ld e,a
        ld a,(.own+1)
        cp e
        jr z,.own
        ld a,e                  ; case d'un autre rectangle : il est recouvert
        dec a
        rlca
        rlca
        rlca
        rlca
        push hl
        ld l,a
        ld h,HIGH MEMO_TAB
        ld (hl),0
        pop hl
.own:   ld (hl),0
        inc hl
        dec c
        jr nz,.ocol
        pop hl
        ld de,32
        add hl,de
        djnz .orow
        ld (ix+0),1
        pop hl
        pop de
        pop bc
        pop af
        pop ix
        ret
.run:
        push hl
        ld a,b                  ; dernière adresse : DE + (B-1)*$20 + C-1
        dec a
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,c
        dec a
        add a,l
        ld l,a
        jr nc,.n1
        inc h
.n1:    add hl,de
        ld a,h                  ; ni la première ni la dernière page dans la
        and $3F                 ; table des sprites (tampon paresseux)
        add a,LOW class_tab
        ld l,a
        ld h,HIGH class_tab
        ld a,(hl)
        cp C_SAT
        jr z,.slow
        ld a,d
        and $3F
        add a,LOW class_tab
        ld l,a
        ld a,(hl)
        cp C_SAT
        jr z,.slow
        pop hl
        ld a,d
        and $C0
        ld (.top+1),a
        ld a,d
        or HIGH VRAM_G          ; DE : copie de la VRAM (hle_wr ignore les bits hauts)
        ld d,a
        ld a,c
        ld (.cc+1),a
        ld a,$20
        sub c
        ld (.st+1),a            ; saut en fin de rangée
.row:
.cc:    ld c,0
.col:   ld a,(de)
        cp (hl)
        jr nz,.wr
.nx:    inc hl
        inc de
        dec c
        jr nz,.col
.st:    ld a,0
        add a,e
        ld e,a
        jr nc,.n2
        inc d
.n2:    djnz .row
        ld a,(.cc+1)
        ld c,a
        ld a,d
        and $3F
.top:   or 0
        ld d,a
        ld a,e
        ret
.wr:    ld a,(hl)
        call hle_wr
        jr .nx
.slow:  pop hl
.srow:  push bc
        push de
.scol:  ld a,(hl)
        call hle_wr
        inc hl
        inc de
        dec c
        jr nz,.scol
        pop de
        ld a,$20
        add a,e
        ld e,a
        jr nc,.n3
        inc d
.n3:    pop bc
        djnz .srow
        ret

; $8664 : chaînes d'octets vers la VRAM. Adresse (2 octets), puis octets ;
; $FE : nouvelle adresse, $FF : fin (B = 0). Réécrites à chaque tick : on
; ne passe par hle_wr que pour les octets qui changent (sauf table des
; sprites, tamponnée). Garde C comme l'original.
nstr_wr:
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
.seg:   push hl                 ; table des sprites : toujours écrire
        ld a,d
        and $3F
        add a,LOW class_tab
        ld l,a
        ld h,HIGH class_tab
        ld a,(hl)
        pop hl
        cp C_SAT
        ld a,$20                ; jr nz
        jr nz,.s1
        ld a,$18                ; jr
.s1:    ld (.jr),a
.l:     ld a,(hl)
        inc hl
        ld b,a
        inc b
        ret z
        inc b
        jr z,nstr_wr
        ld b,a
        push hl
        ld l,e
        ld a,d
        or HIGH VRAM_G
        ld h,a
        ld a,b
        cp (hl)
        pop hl
.jr:    jr nz,.wr
        inc de
        jr .l
.wr:    call hle_wr
        inc de
        jr .l

; $805D : lit l'octet de VRAM à l'adresse DE dans A (garde F)
hle_rd:
        push hl
        push af
        ld a,d
        and $3F
        or HIGH VRAM_G
        ld h,a
        ld l,e
        ld a,(hl)
        ld (.v+1),a
        inc hl
        ld a,h
        and $3F
        ld h,a
        ld (vaddr),hl
        pop af
.v:     ld a,0
        pop hl
        ei
        ret

; $8067 : écriture de E puis D sur le port de contrôle ; sortie A = D, F gardé
hle_ctl:
        push af
        bit 7,d
        jr nz,.reg
        ld a,d
        and $3F
        ld (vaddr+1),a
        ld a,e
        ld (vaddr),a
        pop af
        ld a,d
        ret
.reg:   call vreg_write
        pop af
        ld a,d
        ret

; $85B9 : copie BC octets de HL vers la VRAM (adresse courante)
; sortie : HL après la source, BC = 0, A = 0, Z ; DE gardé
hle_block:
        push de
        ld de,(vaddr)
        ; la table des sprites recopiée depuis la RAM du jeu à chaque trame : on
        ; retient seulement d'où elle vient (le rendu la lira là)
        ld a,(sat_base+1)
        cp d
        jr nz,.copy
        ld a,(sat_base)
        cp e
        jr nz,.copy
        ld a,h
        and $FC
        cp HIGH COLECO_RAM
        jr nz,.copy
        ld a,b
        or a
        jr nz,.copy
        ld a,c
        cp 129
        jr nc,.copy
        ld (sat_src),hl
        ld (sat_len),a
        add hl,bc
        ex de,hl
        add hl,bc
        ld (vaddr),hl
        ex de,hl
        ld bc,0
        pop de
        xor a
        ei
        ret
.copy:  xor a
        ld (blk_mode),a
        call vblock
        ld (vaddr),de
        pop de
        xor a
        ei
        ret

; $85C8 : remplit BC octets de VRAM avec A à partir de DE
; sortie : H = valeur, A = 0, Z, BC = 0, DE gardé
hle_fill:
        push de
        push hl
        ld (blk_val),a
        ld a,1
        ld (blk_mode),a
        ld a,d
        and $3F
        ld d,a
        call vblock
        ld (vaddr),de
        pop hl
        ld a,(blk_val)
        ld h,a
        pop de
        xor a
        ei
        ret

; Copie (blk_mode = 0, source HL) ou remplissage (blk_mode = 1, blk_val) de
; BC octets en VRAM à partir de DE, par morceaux de 128 octets au plus :
; écriture directe, puis marque des motifs touchés ; la table des noms passe
; octet par octet par vput (seules les cases qui changent sont notées).
; Sortie : DE = adresse suivante, BC = 0, HL après la source.
vblock:
.loop:  ld a,b
        or c
        ret z
        ld a,e                  ; n = min(BC, 128 - (E AND $7F))
        and $7F
        cpl
        add a,129
        ld (blk_n),a
        ld a,b
        or a
        jr nz,.big
        ld a,(blk_n)
        cp c
        jr c,.big
        ld a,c
        ld (blk_n),a
.big:   ld a,d
        add a,LOW class_tab
        ld (.cl+1),a
.cl:    ld a,(class_tab)
        cp C_NAME
        jr z,.name
        ld (blk_cls),a
        cp C_SAT
        call z,sat_flush
        push bc
        push de
        ld a,(blk_n)
        ld c,a
        ld b,0
        ld a,d
        or HIGH VRAM_G
        ld d,a
        ld a,(blk_mode)
        or a
        jr nz,.fill
        ldir
        jr .dd
.fill:  ld a,(blk_val)
.f:     ld (de),a
        inc de
        dec c
        jr nz,.f
.dd:    pop de
        pop bc
        ld a,(blk_cls)
        or a
        jr z,.adv
        cp C_SAT
        jr z,.adv
        ; motifs touchés : le premier, puis un tous les 8 octets
        push bc
        push de
        ld a,(blk_n)
        ld b,a
        ld c,e
        call mark_ts
        ld a,e
.mk:    and $F8
        add a,8
        ld e,a
        sub c
        cp b
        jr nc,.mke
        call mark_ts
        ld a,e
        jr .mk
.mke:   pop de
        pop bc
.adv:   ld a,(blk_n)
        add a,e
        ld e,a
        ld a,d
        adc a,0
        and $3F
        ld d,a
.cnt:   push hl                 ; (HL déjà avancé par LDIR)
        ld a,(blk_n)
        ld l,a
        ld a,c
        sub l
        ld c,a
        ld a,b
        sbc a,0
        ld b,a
        pop hl
        jp .loop
.name:  push bc
        ld a,(blk_n)
        ld b,a
        ex de,hl                ; HL = adresse VRAM, DE = source
.nl:    ld a,(blk_mode)
        or a
        ld a,(blk_val)
        jr nz,.nv
        ld a,(de)
        inc de
.nv:    call vput
        djnz .nl
        ex de,hl
        pop bc
        ld a,(blk_n)
        push hl
        ld l,a
        ld a,c
        sub l
        ld c,a
        ld a,b
        sbc a,0
        ld b,a
        pop hl
        jp .loop

blk_mode:   db 0
blk_val:    db 0
blk_n:      db 0
blk_cls:    db 0

; $8BDE : écrit A B fois à l'adresse courante ; sortie B = 0
hle_rle:
        push hl
        push de
        ld d,a
        ld hl,(vaddr)
.l:     ld a,d
        call vput
        djnz .l
        ld (vaddr),hl
        ld a,d
        pop de
        pop hl
        ret

; --- Menu (remplace GAME_OPT du BIOS, $1F7C) --------------------------------------------
; Un joueur seulement : logo « Cabbage Patch Kids » (tuiles mode 0 posées
; directement par le rendu, drapeau logo_on), puis le niveau de difficulté,
; choisi au joystick (haut/bas, tir) ou avec les touches 1 à 4. Le jeu lit
; ensuite le pavé numérique : keypad_raw lui rend la touche du niveau choisi.
; VRAM : même disposition que le jeu (mode graphique 2). Tiers 0 et 1 : le
; logo (index des tuiles dans le tiers, 0 = vide) ; tiers 2 : police blanche
; en $20-$5A, jaune en $A0-$DA.
game_opt:
        call memo_reset         ; les noms sont écrits directement
        push ix
        ld hl,opt_regs
        ld d,$80
.r:     ld e,(hl)
        call vreg_write
        inc hl
        inc d
        ld a,d
        cp $88
        jr nz,.r
        ; noms : tuile vide du logo (rangées 0-15), espaces (16-23)
        ld hl,VRAM_G + $3800
        ld de,VRAM_G + $3801
        ld bc,511
        ld (hl),0
        ldir
        ld hl,VRAM_G + $3A00
        ld de,VRAM_G + $3A01
        ld bc,255
        ld (hl),$20
        ldir
        ; logo : LOGO_ROWS rangées de 28 cases, colonnes 2-29
        ld hl,logo_map
        ld de,VRAM_G + $3800 + 2
        ld b,LOGO_ROWS
.lg:    push bc
        ld bc,28
        ldir
        ex de,hl
        ld bc,4
        add hl,bc
        ex de,hl
        pop bc
        djnz .lg
        ld a,$D0                ; aucun sprite
        ld (VRAM_G + $3B00),a
        ; couleurs : noir partout, police blanche et jaune dans le tiers 2
        ld hl,VRAM_G + $0000
        ld de,VRAM_G + $0001
        ld bc,$17FF
        ld (hl),$10
        ldir
        ld hl,VRAM_G + $1000 + $20*8
        ld de,VRAM_G + $1000 + $20*8 + 1
        ld bc,59*8-1
        ld (hl),$F0
        ldir
        ld hl,VRAM_G + $1000 + $A0*8
        ld de,VRAM_G + $1000 + $A0*8 + 1
        ld bc,59*8-1
        ld (hl),$A0
        ldir
        ld de,VRAM_G + $3000 + $20*8
        call .font
        ld de,VRAM_G + $3000 + $A0*8
        call .font
        ; caractères de la ligne validée, une copie par couleur ($60-$95)
        ld hl,flash_tab
        ld b,FLASH_NC
        ld e,$60
.fk:    push bc
        ld a,(hl)
        inc hl
        push hl
        ld (.fcol+1),a
        ld hl,flash_chars
.fc:    ld a,(hl)
        or a
        jr z,.fke
        inc hl
        push hl
        push de
        sub $20
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,font4
        add hl,bc               ; HL = dessin du caractère
        push hl
        ld l,e
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,VRAM_G + $3000
        add hl,bc
        ex de,hl                ; DE = motif (tiers 2)
        pop hl
        ld bc,8
        ldir
        ex de,hl
        ld bc,-$2008            ; couleurs du même motif
        add hl,bc
.fcol:  ld a,0
        ld b,8
.fcf:   ld (hl),a
        inc hl
        djnz .fcf
        pop de
        inc e
        pop hl
        jr .fc
.fke:   pop hl
        pop bc
        djnz .fk
        ; textes fixes
        ld hl,opt_text
.t:     ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr z,.done
        ex de,hl
        ld bc,VRAM_G + $3800
        add hl,bc
        ex de,hl
.c:     ld a,(hl)
        inc hl
        or a
        jr z,.t
        ld (de),a
        inc de
        jr .c
.done:  ld a,1
        ld (logo_on),a
        ld (menu_on),a
        xor a
        ld (flash_n),a
        ld a,FLASH_NC - 1
        ld (flash_i),a
        ld a,$FF
        ld (joy_prev),a         ; tir et directions : attendre un relâchement
        ld a,(nmi_div)          ; ligne choisie : le mode en cours
        sub 6
        neg                     ; 6 (50 Hz) -> 0, 5 (60 Hz) -> 1
        ld (menu_sel),a
        call menu_draw
        call cheat_draw
        ld a,$08
        ld (t_prev),a           ; T : attendre un relâchement
        ld a,1
        ld (full_req),a
        pop ix
        ret
.font:  ld hl,font4
        ld bc,59*8
        ldir
        ret

opt_regs:   db $02,$C2,$0E,$7F,$07,$76,$03,$F1
opt_text:
        dw 16*32+8
        db "SELECT GAME MODE",0
        dw 23*32+7
        db "UP/DOWN THEN FIRE",0
        dw 0

; RST $10 ($82D7) : HL = $6050, nombre de vies
lives_dec:
        ld a,(infinite)
        or a
        ret nz
        dec (hl)
        ret

; Message des vies infinies (rangée 22), selon le drapeau
; Rangée 22 (en jaune) : « INFINITE LIVES  < SCENE nn > » quand le trainer
; est actif (T), sinon rien. Garde BC, DE, HL.
cheat_draw:
        push bc
        push de
        push hl
        ld hl,$3800 + 22*32 + 2
        ld a,(infinite)
        or a
        jr nz,.on
        ld b,28
.sp:    ld a,' '
        call vput
        djnz .sp
        jr .end
.on:    ld de,cheat_txt
        call .str
        ld a,(start_scene)
        ld c,'0' + $80
.t:     cp 10
        jr c,.u
        sub 10
        inc c
        jr .t
.u:     ld b,a
        ld a,c
        call vput
        ld a,b
        add a,'0' + $80
        call vput
        ld de,cheat_txt2
        call .str
.end:   pop hl
        pop de
        pop bc
        ret
.str:   ld a,(de)
        or a
        ret z
        add a,$80               ; en jaune
        call vput
        inc de
        jr .str
cheat_txt:  db "INFINITE LIVES  < SCENE ",0
cheat_txt2: db " >",0

infinite:   db 0
t_prev:     db $FF
menu_on:    db 0
menu_sel:   db 0
joy_prev:   db 0

; Lignes des modes (rangées 18-19, colonne 9), la choisie en jaune avec « > » :
; NORMAL MODE (50 Hz, comme la ColecoVision PAL), HARD MODE (60 Hz, NTSC).
menu_draw:
        push bc
        push de
        push hl
        ld c,0
        ld de,mode_txt
.l:     ld a,c
        add a,18
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        push de
        ld de,$3800 + 9
        add hl,de               ; HL = adresse VRAM
        pop de
        ld a,(menu_sel)
        cp c
        ld b,0                  ; décalage de police
        ld a,' '
        jr nz,.cur
        ld b,$80
        ld a,'>' + $80
.cur:   call vput
        ld a,' '
        add a,b
        call vput
.s:     ld a,(de)
        inc de
        or a
        jr z,.nx
        add a,b
        call vput
        jr .s
.nx:    inc c
        ld a,c
        cp 2
        jr nz,.l
        pop hl
        pop de
        pop bc
        ret
mode_txt:   db "NORMAL MODE",0,"HARD MODE  ",0

; Un tour de menu (appelé par keypad_raw) -> A = touche du pavé ($FF : rien)
menu_tick:
        push bc
        push de
        push hl
        call .tick
        pop hl
        pop de
        pop bc
        ret
.tick:  ld a,(flash_n)           ; niveau validé : la ligne change de couleur
        or a
        jr z,.norm
        dec a
        ld (flash_n),a
        jp z,.go2
        and 3
        call z,flash_col
        jp .none
.norm:  ld a,(kbd+6)            ; T (ligne 6, bit 3) : vies infinies
        cpl
        and $08
        ld b,a
        ld a,(t_prev)
        cpl
        and b                   ; vient d'être enfoncée
        ld a,b
        ld (t_prev),a
        jr z,.joy
        ld a,(infinite)
        xor 1
        ld (infinite),a
        call cheat_draw
.joy:   ld a,(joy_state)
        ld b,a
        ld a,(joy_prev)
        cpl
        and b                   ; nouvellement enfoncés
        ld c,a
        ld a,b
        ld (joy_prev),a
        call scene_keys         ; gauche / droite : scène de départ (garde BC)
        bit 0,c                 ; haut
        jr z,.dn
        ld a,(menu_sel)
        or a
        jr z,.none
        dec a
        jr .set
.dn:    bit 2,c                 ; bas
        jr z,.fire
        ld a,(menu_sel)
        cp 1
        jr nc,.none
        inc a
.set:   ld (menu_sel),a
        call menu_draw
        jr .none
.fire:  ld a,c
        and $C0                 ; tir 1 ou tir 2
        jr z,.none
.go:    call flash_col
        ld a,FLASH_T
        ld (flash_n),a
        jr .none
.go2:   ld a,(infinite)         ; scène de départ : trainer actif seulement
        or a
        jr z,.g0
        ld a,(start_scene)
        or a
        jr z,.g0
        ld a,1
        ld (start_pend),a       ; appliquée à l'écran « PLAYER 1 »
.g0:    ld a,(menu_sel)         ; mode : 0 -> 6 (50 Hz), 1 -> 5 (60 Hz)
        neg
        add a,6
        ld (nmi_div),a
        xor a
        ld (menu_on),a
        ld (logo_on),a
        ld a,$F0 + $0D          ; touche « 1 » du pavé (le niveau est ignoré par le jeu)
        ret
.none:  ld a,$FF
        ret

; --- Trainer : scène de départ (gauche / droite) -------------------------------------
; B = directions tenues, C = nouvellement enfoncées (bits Coleco : 1 droite,
; 3 gauche). Un pas par appui, puis un tous les 4 tours si on maintient.
scene_keys:
        ld a,(infinite)         ; seulement avec le trainer (T)
        or a
        ret z
        ld a,b
        and $0A
        jr z,.none
        ld a,c
        and $0A
        jr nz,.first
        ld hl,rep_cnt
        inc (hl)
        ld a,(hl)
        cp 18
        ret c
        ld (hl),14
        jr .step
.first: xor a
        ld (rep_cnt),a
.step:  ld a,(start_scene)
        bit 1,b                 ; droite
        jr z,.left
        inc a
        cp 100
        jr c,.set
        xor a
        jr .set
.left:  or a
        jr nz,.dec
        ld a,100
.dec:   dec a
.set:   ld (start_scene),a
        jp cheat_draw
.none:  xor a
        ld (rep_cnt),a
        ret

start_scene: db 0
start_pend: db 0
rep_cnt:    db 0

; Couleur suivante pour la ligne validée : elle est réécrite avec la copie
; de ses caractères dans cette couleur (seuls les noms changent).
FLASH_T     equ 56                  ; durée en ticks (≈ 1 s)
FLASH_NC    equ 6                   ; nombre de couleurs
flash_col:
        ld a,(flash_i)
        inc a
        cp FLASH_NC
        jr c,.k
        xor a
.k:     ld (flash_i),a
        ld c,a                  ; x 10 (caractères de flash_chars)
        add a,a
        add a,a
        add a,c
        add a,a
        add a,$60
        ld c,a                  ; C = premier caractère de cette couleur
        ld a,(menu_sel)
        add a,18
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,$3800 + 9
        add hl,de
        ld de,flash_norm
        ld a,(menu_sel)
        or a
        jr z,.l
        ld de,flash_hard
.l:     ld a,(de)
        inc de
        cp $FE
        ret z
        cp $FF
        jr z,.sp
        add a,c
        jr .put
.sp:    ld a,' '
.put:   call vput
        jr .l
flash_chars: db ">NORMALDEH",0          ; (6 couleurs x 10 : caractères $60-$9B)
flash_norm: db 0,$FF,1,2,3,4,5,6,$FF,4,2,7,8,$FE        ; « > NORMAL MODE »
flash_hard: db 0,$FF,9,5,3,7,$FF,4,2,7,8,$FE            ; « > HARD MODE »
flash_tab:  db $80,$B0,$30,$70,$D0,$F0      ; rouge, jaune, vert, cyan, magenta, blanc
flash_i:    db 0
flash_n:    db 0

; Données du menu : en base 0 (font4_data, logo_map_data), recopiées au
; démarrage par init (render.asm) dans le trou de la banque 4 après le cache
; des sprites, pour laisser la place au code.
BK4_DATA    equ $3B00
font4       equ BK4_DATA
logo_map    equ BK4_DATA + 59*8
        ASSERT logo_map + LOGO_ROWS*28 <= $4000

; --- Manettes ------------------------------------------------------------------------
; Clavier du CPC : ligne choisie par le port C du PPI, lue par le registre
; 14 du PSG. Balayé au plus une fois par tour de jeu (60 Hz), à la première
; lecture de la manette ; isr_body invalide le résultat à chaque tour.
; Le PPI sert aussi au son : interruptions coupées pendant l'accès.

kbd:        ds 10               ; état des lignes 0-9 (bit à 0 = enfoncée)
kbd_ok:     db 0                ; 1 = kbd, joy_state et pad_state à jour
joy_state:  db 0                ; bits Coleco actifs à 1 (voir read_joy)
pad_state:  db $FF              ; pavé : $F0 + code, $FF = rien

kbd_update:
        ld a,(kbd_ok)
        or a
        ret nz
        push bc
        push de
        push hl
        ld a,i                  ; P/V = IFF2
        push af
        di
        ld bc,$F40E
        out (c),c
        ld bc,$F6C0
        out (c),c
        ld bc,$F600
        out (c),c
        ld bc,$F792
        out (c),c
        ld hl,kbd
        ld a,$40
.l:     ld b,$F6
        out (c),a
        ld b,$F4
        in e,(c)
        ld (hl),e
        inc hl
        inc a
        cp $4A
        jr nz,.l
        ld bc,$F782
        out (c),c
        ld bc,$F600
        out (c),c
        pop af
        jp po,.di
        ei
.di:    ; manette virtuelle, format du joystick CPC (actif à 1) : bit0 haut,
        ; bit1 bas, bit2 gauche, bit3 droite, bit4 tir 2, bit5 tir 1
        ld a,(kbd+9)
        cpl
        and $3F
        ld e,a
        ld a,(kbd+0)            ; flèches haut, droite, bas
        rra
        jr c,$+4
        set 0,e
        rra
        jr c,$+4
        set 3,e
        rra
        jr c,$+4
        set 1,e
        ld a,(kbd+1)            ; flèche gauche, COPY
        rra
        jr c,$+4
        set 2,e
        rra
        jr c,$+4
        set 5,e
        ld a,(kbd+8)            ; Q (bit 3), A (bit 5)
        bit 3,a
        jr nz,$+4
        set 0,e
        bit 5,a
        jr nz,$+4
        set 1,e
        ld a,(kbd+3)            ; P (bit 3)
        bit 3,a
        jr nz,$+4
        set 3,e
        ld a,(kbd+4)            ; O (bit 2), M (bit 6)
        bit 2,a
        jr nz,$+4
        set 2,e
        bit 6,a
        jr nz,$+4
        set 4,e
        ld a,(kbd+5)            ; ESPACE (bit 7)
        bit 7,a
        jr nz,$+4
        set 5,e
        ld hl,joy_col
        ld d,0
        add hl,de
        ld a,(hl)
        ld (joy_state),a
        ld a,1
        ld (kbd_ok),a
        pop hl
        pop de
        pop bc
        ret

; Pavé (écrans de choix seulement) : lu à la demande
pad_update:
        push bc
        push de
        push hl
        ; pavé : un chiffre ne compte qu'une fois vu relâché (une 2e manette
        ; branchée partage la ligne 6 avec les touches 5 et 6)
        ld e,$FF
        ld hl,pad_map
.p:     ld a,(hl)
        cp $FF
        jr z,.pe
        push hl
        ld c,a
        ld b,0
        ld hl,kbd
        add hl,bc
        ld a,(hl)
        pop hl
        inc hl
        and (hl)                ; Z : enfoncée
        inc hl
        inc hl                  ; HL -> « armée »
        jr z,.pd
        ld (hl),1               ; relâchée : armée
        jr .pn
.pd:    ld a,(hl)
        or a
        jr z,.pn
        dec hl
        ld a,(hl)               ; code
        inc hl
        or $F0
        ld e,a
.pn:    inc hl
        jr .p
.pe:    ld a,e
        ld (pad_state),a
        pop hl
        pop de
        pop bc
        ret

; joystick CPC (6 bits) -> bits Coleco : bit0 haut, bit1 droite, bit2 bas,
; bit3 gauche, bit6 tir 1 (bouton gauche), bit7 tir 2
joy_col:
        LUA ALLPASS
        for v = 0, 63 do
            local c = 0
            if v & 1 ~= 0 then c = c | 0x01 end
            if v & 2 ~= 0 then c = c | 0x04 end
            if v & 4 ~= 0 then c = c | 0x08 end
            if v & 8 ~= 0 then c = c | 0x02 end
            if v & 16 ~= 0 then c = c | 0x80 end
            if v & 32 ~= 0 then c = c | 0x40 end
            _pc("db " .. c)
        end
        ENDLUA

; $8101 : « in a,(c) / cpl » en mode manette -> directions + tir 1 (bit 6)
joy_in:
        call kbd_update
        ld a,(joy_state)
        and $4F
        ret

; $8123 : « in a,(c) / cpl » en mode pavé -> bit 6 = tir 2
key_fire2:
        call kbd_update
        ld a,(joy_state)
        and $80
        rrca                    ; bit 7 -> bit 6
        ret

; $8137 : pavé numérique des deux manettes (actif à 0), bits 0-3 = code
keypad_raw:
        call kbd_update
        ld a,(menu_on)
        or a
        jp nz,menu_tick
        call pad_update
        ld a,(pad_state)
        IFDEF DEBUGKEY
        cp $FF
        ret z
        ; montre l'état du clavier en bas de l'écran et ignore la touche
        push bc
        push de
        push hl
        ld hl,$3800+22*32
        call .hex
        ld de,kbd
        ld b,10
.dl:    ld a,(de)
        call .hex
        inc de
        djnz .dl
        pop hl
        pop de
        pop bc
        ld a,$FF
        ret
.hex:   push af
        rrca
        rrca
        rrca
        rrca
        call .nib
        pop af
.nib:   and $0F
        add a,'0'
        cp '9'+1
        jr c,$+4
        add a,7
        jp vput
        ENDIF
        ret

; (ligne, bit, code du pavé Coleco)
; (ligne, bit, code du pavé Coleco, armée)
pad_map:
        db 8,$01,$0D,0, 8,$02,$07,0, 7,$02,$0C,0, 7,$01,$02,0     ; 1 2 3 4
        db 6,$02,$03,0, 6,$01,$0E,0, 5,$02,$05,0, 5,$01,$01,0     ; 5 6 7 8
        db 4,$02,$0B,0, 4,$01,$0A,0                               ; 9 0
        db $FF

; --- Son : SN76489 (port $FF) -> AY-3-8912 --------------------------------------------
; Tons : période AY = N x 0,5587 (horloges 3,58 MHz / 32 et 1 MHz / 16).
; Volume : atténuation SN (0 = fort, 15 = coupé) -> volume AY par table.
; Bruit : sur la voie C de l'AY, avec le plus fort des volumes 2 et 3.

sn_write_addhl:                 ; $B9FD : « out ($FF),a / add hl,hl »
        call sn_write
        add hl,hl
        ret

sn_write:
        push af
        push bc
        push de
        push hl
        bit 7,a
        jr z,.data
        ld c,a                  ; octet de sélection : 1 cc t dddd
        rrca
        rrca
        rrca
        rrca
        and 7
        ld (sn_latch),a
        ld b,a
        ld a,c
        and $0F
        ld c,a
        bit 0,b
        jr nz,.vol
        ; ton (ou bruit) : 4 bits de poids faible
        ld a,b
        cp 6
        jr z,.noise
        call .tone_ptr          ; HL = &ton[voie]
        ld a,(hl)
        and $F0
        or c
        ld (hl),a
        jr .upd_tone
.data:  and $3F                 ; octet de données : 6 bits de poids fort
        ld c,a
        ld a,(sn_latch)
        ld b,a
        bit 0,b
        jr nz,.vol
        cp 6
        jr z,.noise
        call .tone_ptr
        ld a,c                  ; ton = (C << 4) | (ton AND $0F)
        rlca
        rlca
        rlca
        rlca
        ld e,a
        and $F0
        ld d,a
        ld a,(hl)
        and $0F
        or d
        ld (hl),a
        inc hl
        ld a,e
        and $0F
        ld (hl),a
        dec hl
.upd_tone:
        ; B = 2 x voie ; période AY = N/2 + N x 15 / 256
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = N (10 bits, 0 = 1024)
        ld a,d
        or e
        jr nz,.nz
        ld d,4
.nz:    ld h,d
        ld l,e
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; N x 16
        or a
        sbc hl,de               ; N x 15
        ld l,h
        ld h,0                  ; / 256
        srl d
        rr e                    ; N / 2
        add hl,de
        ld a,b                  ; registre AY = voie x 2
        ld c,l
        call psg_write
        inc a
        ld c,h
        call psg_write
        ld a,b
        cp 4
        jr nz,.end
        ld a,(sn_regs+6)        ; bruit calé sur la voie 2 : suivre
        and 3
        cp 3
        call z,.noise_period
        jr .end
.noise: ; C = contrôle du bruit (bits 0-1 : vitesse)
        ld a,c
        ld (sn_regs+6),a
        call .noise_period
        jr .end
.vol:   ; B = 2 x voie + 1, C = atténuation
        ld hl,sn_vols
        ld a,b
        rrca
        and 3
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        cp c
        jr z,.end               ; inchangé
        ld (hl),c
        ld a,e
        cp 2
        jr nc,.volc
        ld hl,sn_att            ; voie A ou B : son seul registre de volume
        ld e,c
        add hl,de
        ld c,(hl)
        add a,8
        call psg_write
        jr .end
.volc:  call .mix               ; voie 2 ou bruit : voie C et mélangeur
.end:   pop hl
        pop de
        pop bc
        pop af
        ret

.tone_ptr:                      ; B = 2 x voie -> HL = &ton[voie]
        ld hl,sn_regs
        ld e,b
        ld d,0
        add hl,de
        ret

.noise_period:
        ld a,(sn_regs+6)
        and 3
        ld hl,noise_tab
        ld e,a
        ld d,0
        add hl,de
        ld c,(hl)
        cp 3
        jr nz,.np
        ld a,(sn_regs+4)        ; période de la voie 2 (N / 2 environ) / 2
        ld c,a
        ld a,(sn_regs+5)
        rra
        rr c                    ; N / 2
        ld a,(sn_regs+5)
        and $FE
        jr z,.np1
        ld c,31                 ; N >= 512 : période maximale
.np1:   ld a,c
        or a
        jr nz,.np0
        inc c
.np0:   cp 32
        jr c,.np
        ld c,31
.np:    ld a,6
        jp psg_write

; Volume de la voie C (voie 2 ou bruit, le plus fort) et mélangeur
.mix:
        ld hl,sn_vols+2
        ld de,sn_att
        ld b,%00111000          ; bruits coupés, tons actifs
        ld a,(hl)               ; voie 2
        call .v
        push bc
        inc hl
        ld a,(hl)               ; bruit
        call .v
        ld a,c
        pop bc
        or a
        jr z,.nonoise
        res 5,b                 ; bruit sur la voie C
        cp c
        jr c,.nonoise
        ld c,a                  ; le plus fort des deux
.nonoise:
        ld a,10
        call psg_write
        ld c,b
        ld a,7
        jp psg_write
.v:     ; A = atténuation -> C = volume AY
        push hl
        ld l,a
        ld h,0
        add hl,de
        ld c,(hl)
        pop hl
        ret

sn_vols:    db 15,15,15,15
sn_att:     db 15,13,12,11,10,9,8,7,6,5,4,3,2,1,0,0
noise_tab:  db 9,18,31,0

; A = registre, C = valeur (garde tout) ; rien si la valeur ne change pas
psg_write:
        push af
        push bc
        push de
        push hl
        ld e,a
        ld d,0
        ld hl,ay_cache
        add hl,de
        ld a,(hl)
        cp c
        jr z,.same
        ld (hl),c
        ld a,i
        push af
        di
        ld d,c
        ld b,$F4
        out (c),e
        ld bc,$F6C0
        out (c),c
        ld bc,$F600
        out (c),c
        ld b,$F4
        out (c),d
        ld bc,$F680
        out (c),c
        ld bc,$F600
        out (c),c
        pop af
        jp po,.same
        ei
.same:  pop hl
        pop de
        pop bc
        pop af
        ret

ay_cache:   db 0,0,0,0,0,0,0,%00111111,0,0,0,0,0,0
