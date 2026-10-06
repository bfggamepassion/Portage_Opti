; ===========================================================================
; render.asm - moteur de rendu (base 0), tâche de fond qui remplace la boucle
; d'attente du jeu. Il recopie l'état du VDP virtuel dans l'écran caché puis
; bascule les écrans au VSYNC (double tampon : aucun clignotement).
;
; Une trame :
;   grab       (V_B5) registres du VDP, liste des cases modifiées par le jeu
;   vram_pass  (V_B7) table des sprites, noms des cases modifiées, tuiles et
;              sprites à reconvertir (via des tampons en base)
;   draw_cells (V_BASE) cases modifiées (cette trame et la précédente) et
;              cases sous les sprites de l'avant-dernière trame, depuis le
;              cache des tuiles converties
;   draw_sprites (V_B4) sprites masqués, du dernier au premier (le sprite 0
;              passe devant), depuis le cache des masques
;   flip       R12 du CRTC -> attendre le VSYNC -> palette
;
; Écran : case (0-767) -> octet = base + 2 x case (+ $800 par ligne de pixels).
; ===========================================================================

; --- Données dans les trous des écrans (512 octets en $x600 de chaque bloc
;     de 2 Ko : visibles dans toutes les vues du rendu) ---------------------------
CHG0        equ $8600           ; listes de cases changées : mot (nombre) + mots
CHG1        equ $8E00
CHG_MAX     equ 255
SAT_BUF     equ $9600           ; copie de la table des sprites (128)
RECTS_A     equ $9680           ; rectangles des sprites dessinés : nombre + 32 x 4
RECTS_B     equ $9710
CONV_TMP    equ $9E00           ; 32 tuiles converties (512)
SPR_TMP     equ $A600           ; motif de sprite lu en VRAM (32)
SPR_M       equ $A620           ; 8 pixels CPC de chaque ligne du motif (16)
ROWBUF      equ $A630           ; masques d'une ligne (5)
PAT_LIST    equ $AE00           ; motifs de tuile à reconvertir : mot + 255 mots
SPR_LIST    equ $B600           ; motifs de sprite à reconvertir : nombre + 64

; --- Base 0 --------------------------------------------------------------------------
CADDR       equ $3800           ; adresse dans le cache de la tuile de chaque case (768 mots)
STAMPS      equ $7300           ; (base 1) trame du dernier dessin de chaque case (768)
ENTTAB      equ $BE00           ; (trou d'écran) adresse de l'entrée k du cache des sprites
LT_LO       equ $C600           ; (trous d'écran) adresse d'une ligne y, sans la base
LT_HI       equ $CE00
RSTACK      equ $4000           ; pile ($3E00-$3FFF)

; A = vue : change la configuration mémoire (et cur_view, lue par l'interruption)
set_view:
        di
        ld (cur_view),a
        ld b,GA
        out (c),a
        ei
        ret

; === Démarrage (après le chargeur, en base 0) ===========================================
init:
        di
        ld sp,RSTACK
        im 1
        ld bc,GA*256 + GA_MODE0
        out (c),c
        ld a,V_BASE
        ld (cur_view),a
        ld b,GA
        out (c),a
        ; CRTC : 32 caractères (64 octets) x 24 rangées, écran A en $8000
        ld hl,crtc_regs
        ld e,0
.cr:    ld a,(hl)
        inc hl
        ld bc,$BC00
        out (c),e
        ld b,$BD
        out (c),a
        inc e
        ld a,e
        cp 14
        jr nz,.cr
        ; encres noires
        ld e,17
        ld c,0
.ink:   ld b,GA
        out (c),c
        ld a,$54
        out (c),a
        inc c
        dec e
        jr nz,.ink
        ; AY : tout coupé, port A en entrée
        ld a,7
        ld c,%00111111
        call psg_w0
        ld a,8
        ld c,0
        call psg_w0
        ld a,9
        call psg_w0
        ld a,10
        call psg_w0
        ; écrans, base 1 (cache des tuiles), données du rendu
        ld hl,$4000
        ld de,$4001
        ld bc,$BFFF
        ld (hl),0
        ldir
        ; données du menu -> banque 4 (BK4_DATA, vue du jeu), après le cache
        ; des sprites (interruptions coupées : pas de set_view)
        ld bc,GA*256 + V_B4
        out (c),c
        ld hl,font4_data
        ld de,$4000 + font4
        ld bc,59*8
        ldir
        ld hl,logo_map_data
        ld bc,LOGO_ROWS*28
        ldir
        ld bc,GA*256 + V_BASE
        out (c),c
        ld hl,CADDR
        ld de,CADDR+1
        ld bc,$05FF
        ld (hl),0
        ldir
        ; entrée k du cache des sprites (84 octets) : 3 par page de 256, pour
        ; qu'aucune ne traverse une page (dessin par INC L) : 128 entrées,
        ; SCACHE .. SCACHE + 42 x 256 + 252
        ld hl,ENTTAB
        ld de,SCACHE
        ld c,3
.et:    ld (hl),e
        inc l
        ld (hl),d
        inc l
        dec c
        jr z,.etp
        ld a,e
        add a,84
        ld e,a
        jr .etn
.etp:   ld c,3
        ld e,LOW SCACHE
        inc d
.etn:   ld a,l
        or a
        jr nz,.et
        ; adresses des lignes : (y AND 7) x $800 + (y / 8) x 64
        ld c,0
.lt:    ld a,c
        and $F8
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,c
        and 7
        add a,a
        add a,a
        add a,a
        add a,h
        ld b,a
        ld h,HIGH LT_LO
        ld a,l
        ld l,c
        ld (hl),a
        ld h,HIGH LT_HI
        ld (hl),b
        inc c
        ld a,c
        cp 192
        jr nz,.lt
        ld a,1
        ld (need_names),a
        ld a,SCR_B/256
        ld (back_base),a
        ld a,$30
        ld (back_page),a
        ld a,2
        ld (full_screens),a
        ld a,$FF
        ld (pal_state),a
        ld hl,CHG0
        ld (chg_cur),hl
        ld hl,CHG1
        ld (chg_old),hl
        ; état partagé (banque 5) : liste courante, tables de genres
        ld a,V_B5
        ld (cur_view),a
        ld b,GA
        out (c),a
        ld hl,dirty_la
        ld (dirty_ptr),hl
        ld a,V_BASE
        ld (cur_view),a
        ld b,GA
        out (c),a
        ld a,V_GAME
        ld (cur_view),a         ; le jeu démarre (les interruptions arriveront en vue jeu)
        jp go_game

crtc_regs:
        db 63, 32, 42, $8E, 38, 0, 24, 30, 0, 7, 0, 0, $20, 0

; A = registre, C = valeur (initialisation seulement)
psg_w0:
        ld b,$F4
        out (c),a
        ld b,$F6
        ld e,$C0
        out (c),e
        ld e,0
        out (c),e
        ld b,$F4
        out (c),c
        ld b,$F6
        ld e,$80
        out (c),e
        ld e,0
        out (c),e
        ret

; === Boucle du rendu ======================================================================
render_main:
        call grab
        call vram_pass
.loop:  call draw_cells
        call draw_sprites
        call flip_req           ; bascule demandée pour le prochain VSYNC...
        call grab               ; ... pendant ce temps, préparer la suivante
        call vram_pass
        call flip_wait
        jr .loop

; --- grab (V_B5) : registres, liste des cases modifiées -------------------------------------
grab:
        ld a,V_B5
        call set_view
        ld hl,vregs
        ld de,r_regs
        ld bc,8
        ldir
        ; table des sprites restée en RAM Coleco ?
        di
        xor a
        ld (r_satlen),a
        ld hl,(sat_src)
        ld a,h
        or l
        jr z,.nosat
        ld a,(sat_len)
        ld (r_satlen),a
        ld c,a
        ld b,0
        or a
        jr z,.nosat
        ld de,SAT_BUF
        ldir
.nosat: ei
        di
        ld a,(logo_on)
        ld hl,r_logo
        cp (hl)
        ld (hl),a
        ld a,(full_req)
        jr z,$+4
        ld a,1                  ; logo affiché ou retiré : tout reconvertir
        ld c,a                  ; C = registres changés : tout reconvertir
        ld a,(tile_req)
        ld b,a                  ; B = motifs de tuile modifiés
        ld a,(names_ovf)
        or b
        ld b,a                  ; (ou liste des cases pleine)
        xor a
        ld (full_req),a
        ld (tile_req),a
        ld (names_ovf),a
        ld hl,(dirty_ptr)       ; échange des listes : le jeu écrit dans l'autre
        ld (grab_list),hl
        ld de,dirty_la
        or a
        sbc hl,de
        ld hl,dirty_lb
        jr z,.sw
        ld hl,dirty_la
.sw:    ld (dirty_ptr),hl
        ei
        ld a,c
        or b
        jr z,.partial
        ; tout redessiner : toutes les cases, tous les drapeaux
        ld a,2
        ld (full_screens),a
        ld a,1
        ld (need_names),a
        push bc
        ld hl,dirty_flag
        call clr768
        ld hl,(grab_list)
        ld (hl),0
        pop bc
        ld a,c
        or a
        jr z,.collect
        ; registres changés : toutes les tuiles et tous les sprites
        ld hl,pat_dirty
        call clr768
        ld hl,$FFFF
        ld (PAT_LIST),hl
        ld hl,spr_dirty
        ld de,spr_dirty+1
        ld bc,63
        ld (hl),1
        ldir
        ld a,1
        ld (spr_req),a
        jr .spr
.collect:
        call collect_pats
        jr .spr
.partial:
        ; cases de la liste : effacer d'abord le drapeau (une écriture qui suit
        ; remettra la case dans l'autre liste), puis la copier
        ld hl,(grab_list)
        ld a,(hl)
        ld (hl),0
        or a
        jr z,.spr
        ld b,a
        inc hl
        ld ix,(chg_cur)
.cp:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,dirty_flag
        add hl,de
        ld (hl),0
        pop hl
        call chg_add
        djnz .cp
.spr:   ; motifs de sprites modifiés (spr_req : au moins un ; remis à 0 avant
        ; le parcours, une marque qui arrive pendant sera vue au tour suivant)
        ld a,(spr_req)
        or a
        jr z,.sn0
        xor a
        ld (spr_req),a
        ld hl,spr_dirty
        ld de,SPR_LIST+1
        ld c,0
        ld b,64
.sl:    ld a,(hl)
        or a
        jr z,.sn
        ld (hl),0
        ld a,64
        sub b
        ld (de),a
        inc de
        inc c
.sn:    inc hl
        djnz .sl
        ld a,c
.sn0:   ld (SPR_LIST),a
        ld a,V_BASE
        jp set_view

; Efface 768 octets en HL (aligné sur une page), interruptions permises.
; Pas de « LD (HL),0 / LDIR » : le jeu (interruption) écrit dans ces
; drapeaux pendant l'effacement, et un 1 posé sous le curseur du LDIR serait
; recopié dans tous les octets suivants (cases perdues pour toujours).
clr768: xor a
        ld c,3
.p:     ld b,64
.o:     ld (hl),a
        inc l
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        djnz .o
        inc h
        dec c
        jr nz,.p
        ret

; DE = case -> ajoutée à la liste courante (plus de place : tout refaire)
chg_add:
        push hl
        ld hl,(chg_cur)
        ld a,(hl)
        cp CHG_MAX
        jr nc,.full
        inc (hl)
        push bc
        ld c,a
        ld b,0
        inc hl
        inc hl
        add hl,bc
        add hl,bc
        pop bc
        ld (hl),e
        inc hl
        ld (hl),d
        pop hl
        ret
.full:  ld a,2
        ld (full_screens),a
        pop hl
        ret

; Motifs de tuile marqués (banque 5, pat_dirty) -> PAT_LIST ; trop nombreux : tous
collect_pats:
        ld hl,pat_dirty
        ld de,PAT_LIST+2
        ld bc,0                 ; nombre trouvé
        ld ix,768
.l:     ld a,(hl)
        or a
        jr z,.n
        ld (hl),0
        ld a,b
        or a
        jr nz,.n                ; déjà plus de 255 : on continue d'effacer
        ld a,c
        cp 255
        jr nz,.add
        ld b,1                  ; débordement : on reconvertira tout
        jr .n
.add:   push hl
        ld a,l                  ; n° = HL - pat_dirty
        sub LOW pat_dirty
        ld (de),a
        inc de
        ld a,h
        sbc a,HIGH pat_dirty
        ld (de),a
        inc de
        pop hl
        inc c
.n:     inc hl
        dec ix
        ld a,ixh
        or ixl
        jr nz,.l
        ld a,b
        or a
        jr z,.ok
        ld hl,$FFFF             ; tout reconvertir
        ld (PAT_LIST),hl
        ret
.ok:    ld (PAT_LIST),bc
        ret

; --- vram_pass (V_B7) --------------------------------------------------------------------------
vram_pass:
        ld a,V_B7
        call set_view
        ; table des sprites
        ld a,(r_regs+5)
        and $7F
        ld l,0
        srl a
        rr l
        add a,HIGH VRAM_R
        ld h,a                  ; HL = table en VRAM
        ld a,(r_satlen)         ; octets déjà pris en RAM
        ld e,a
        ld d,0
        add hl,de
        ld a,128
        sub e
        jr z,.satok
        ld c,a
        ld b,0
        ld de,SAT_BUF
        ld a,(r_satlen)
        add a,e
        ld e,a
        di
        ldir
        ei
.satok:
        ; adresse de la table des noms (vue V_B7)
        ld a,(r_regs+2)
        and $0F
        add a,a
        add a,a
        add a,HIGH VRAM_R
        ld (names_hi),a
        ld a,(need_names)
        or a
        jr z,.list
        xor a
        ld (need_names),a
        ld de,0                 ; toutes les cases
.nf:    call .setc
        inc de
        ld a,d
        cp 3
        jr c,.nf
        jr .tiles
.list:  ; noms des cases de la liste
        ld hl,(chg_cur)
        ld b,(hl)
        inc hl
        inc hl
        ld a,b
        or a
        jr z,.tiles
.nl:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        call .setc
        pop hl
        djnz .nl
        jr .tiles
; DE = case : CADDR[case] = TCACHE + (tiers x 256 + nom) x 16
.setc:  ld a,(names_hi)
        add a,d
        ld h,a
        ld l,e
        ld a,(hl)               ; nom
        ld l,a
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld h,a
        ld a,d
        add a,a
        add a,a
        add a,a
        add a,a
        add a,h
        add a,HIGH TCACHE
        ld c,a
        ld a,l
        add a,a
        add a,a
        add a,a
        add a,a
        ld hl,CADDR
        add hl,de
        add hl,de
        ld (hl),a
        inc hl
        ld (hl),c
        ret
.tiles:
        ld hl,(PAT_LIST)
        ld a,h
        or l
        jr z,.sprites
        call retile
        ld hl,0
        ld (PAT_LIST),hl
.sprites:
        ld a,(SPR_LIST)
        or a
        jr z,.done
        call respr
        xor a
        ld (SPR_LIST),a
.done:  ld a,V_BASE
        jp set_view

; Reconvertit les tuiles de PAT_LIST ($FFFF = toutes), par lots de 32 :
; conversion en V_B7 vers CONV_TMP, puis copie dans le cache en V_BASE.
retile:
        ; bases des motifs et des couleurs (vue V_B7)
        ld a,(r_regs+4)
        and 4
        add a,a
        add a,a
        add a,a
        add a,HIGH VRAM_R
        ld (pat_hi),a
        ld a,(r_regs+3)
        and $80
        rrca
        rrca
        add a,HIGH VRAM_R
        ld (col_hi),a
        ld hl,(PAT_LIST)
        inc hl
        ld a,h
        or l
        jr nz,.some
        ; toutes : 768 motifs dans l'ordre
        ld hl,0
.all:   push hl
        ld b,32
        call conv_run           ; HL = 1er motif, B = nombre
        pop hl
        ld de,32
        add hl,de
        ld a,h
        cp 3
        jr c,.all
        ret
.some:  ; liste : un par un (peu nombreux)
        ld hl,PAT_LIST+2
        ld bc,(PAT_LIST)
.s:     ld a,b
        or c
        ret z
        push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ex de,hl
        ld b,1
        call conv_run
        pop hl
        pop bc
        dec bc
        jr .s

; HL = premier motif (0-767), B = nombre (1-32) : convertit et range dans le cache
; (appelé en V_B7, rend la main en V_B7)
conv_run:
        push hl
        push bc
        ld ix,CONV_TMP
.t:     push bc
        push hl
        call logo_src           ; tuile du logo ? DE = sa source (mode 0)
        jr z,.cv
        ld b,16
.lc:    ld a,(de)
        ld (ix+0),a
        inc de
        inc ix
        djnz .lc
        jr .nx
.cv:    ; DE = motif (VRAM), BC = couleurs (VRAM) : n x 8
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(pat_hi)
        add a,h
        ld d,a
        ld e,l
        ld a,(col_hi)
        add a,h
        ld b,a
        ld c,l
        ld a,8
.row:   push af
        ld a,(de)               ; motif
        inc de
        ld l,a
        ld h,HIGH SELR
        ld a,(hl)               ; page de l'octet droit
        dec h
        ld h,(hl)               ; page de l'octet gauche
        push af
        ld a,(bc)               ; couleurs
        inc bc
        ld l,a
        ld a,(hl)
        ld (ix+0),a
        pop af
        ld h,a
        ld a,(hl)
        ld (ix+1),a
        inc ix
        inc ix
        pop af
        dec a
        jr nz,.row
.nx:    pop hl
        inc hl
        pop bc
        djnz .t
        ; copie dans le cache (V_BASE)
        ld a,V_BASE
        call set_view
        pop bc
        pop hl
        push bc
        push hl
        add hl,hl               ; TCACHE + n x 16
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,TCACHE
        add hl,de
        ex de,hl
        ; rangées dans l'ordre de dessin de draw_cell : lignes 0 1 3 2 6 7 5 4
        ; (code de Gray : une seule ligne d'adresse change), octets gauche
        ; droite, puis droite gauche une ligne sur deux (zigzag)
        ld ix,CONV_TMP
.cp:
        ld a,(ix+0)
        ld (de),a
        inc de
        ld a,(ix+1)
        ld (de),a
        inc de
        ld a,(ix+3)
        ld (de),a
        inc de
        ld a,(ix+2)
        ld (de),a
        inc de
        ld a,(ix+6)
        ld (de),a
        inc de
        ld a,(ix+7)
        ld (de),a
        inc de
        ld a,(ix+5)
        ld (de),a
        inc de
        ld a,(ix+4)
        ld (de),a
        inc de
        ld a,(ix+12)
        ld (de),a
        inc de
        ld a,(ix+13)
        ld (de),a
        inc de
        ld a,(ix+15)
        ld (de),a
        inc de
        ld a,(ix+14)
        ld (de),a
        inc de
        ld a,(ix+10)
        ld (de),a
        inc de
        ld a,(ix+11)
        ld (de),a
        inc de
        ld a,(ix+9)
        ld (de),a
        inc de
        ld a,(ix+8)
        ld (de),a
        inc de
        push de
        ld de,16
        add ix,de
        pop de
        djnz .cp
        pop hl
        pop bc
        ld a,V_B7
        jp set_view

; HL = n° de motif (0-767) : NZ et DE = tuile mode 0 si c'est une tuile du
; logo affiché par le menu (tiers 0 : 0..LOGO_N0-1 ; tiers 1 : 0..LOGO_N1-1)
logo_src:
        ld a,(r_logo)
        or a
        ret z
        ld a,h
        or a
        jr nz,.t1
        ld a,l
        cp LOGO_N0
        jr nc,.no
        ld de,logo_t0
        jr .ad
.t1:    dec a
        jr nz,.no
        ld a,l
        cp LOGO_N1
        jr nc,.no
        ld de,logo_t1
.ad:    push hl
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,de
        ex de,hl
        pop hl
        ld a,1
        or a
        ret
.no:    xor a
        ret

; Reconvertit les motifs de sprite de SPR_LIST (appelé en V_B7, rend la main en V_B7)
respr:
        ld hl,SPR_LIST+1
        ld a,(SPR_LIST)
        ld b,a
.l:     push bc
        ld a,(hl)
        inc hl
        push hl
        ld (spr_q),a
        ; motif q : (R6 AND 7) x $800 + q x 32
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(r_regs+6)
        and 7
        add a,a
        add a,a
        add a,a
        add a,HIGH VRAM_R
        add a,h
        ld h,a
        ld de,SPR_TMP
        ld bc,32
        ldir
        ld a,V_B4
        call set_view
        call build_sprite
        ld a,V_B7
        call set_view
        pop hl
        pop bc
        djnz .l
        ret

build_sprite:
; Masques du motif SPR_TMP (32 octets de VRAM) pour les décalages 0 et 1 ->
; cache (V_B4). Ligne : 8 pixels CPC m (bit 7 = gauche) -> 5 octets (gen5).
; Entrée du cache (84 octets) : r0, nr, b0, w (boîte des octets non vides),
; puis nr x w masques INVERSÉS. nr = 0 : rien à dessiner.
        ; 1) m de chaque ligne (SPR_M), union, première et dernière ligne non vides
        ld ix,SPR_TMP
        ld iy,SPR_M
        ld bc,16*256            ; B = lignes, C = union
        ld de,$FF00             ; D = r0 (255 : aucune), E = r1
.m:     ld h,HIGH SPRN
        ld l,(ix+0)             ; 8 pixels Coleco de gauche
        ld a,(hl)
        rlca
        rlca
        rlca
        rlca
        ld l,(ix+16)            ; 8 pixels de droite
        or (hl)
        ld (iy+0),a
        inc ix
        inc iy
        or a
        jr z,.me
        or c
        ld c,a
        ld a,16
        sub b                   ; n° de ligne
        ld e,a
        inc d
        jr z,.first
        dec d
        jr .me
.first: ld d,a
.me:    djnz .m
        ld a,c
        ld (pk_u),a
        ; 2) entrée du cache (décalage 0) : ENTTAB[2q]
        ld a,(spr_q)
        add a,a
        add a,a
        ld l,a
        ld h,HIGH ENTTAB
        ld a,(hl)
        inc l
        ld h,(hl)
        ld l,a
        ld a,d
        cp $FF
        jr nz,.some
        ; motif vide : nr = 0 pour les deux décalages
        inc hl
        ld (hl),0
        call .ent1
        inc hl
        ld (hl),0
        ret
; HL = entrée du décalage 1 du motif spr_q : ENTTAB[2q + 1]
.ent1:  ld a,(spr_q)
        add a,a
        add a,a
        add a,2
        ld l,a
        ld h,HIGH ENTTAB
        ld a,(hl)
        inc l
        ld h,(hl)
        ld l,a
        ret
.some:  ld (pk_r0),a
        ld a,e
        ld (pk_r1),a
        xor a
        call .pack
        call .ent1
        ld a,1

; A = décalage, HL = entrée -> remplit l'entrée
.pack:  ld (pk_s),a
        push hl
        ; colonnes : octets non vides de l'union
        ld a,(pk_u)
        call .gen5
        ld de,ROWBUF
        ld b,0
.c0:    ld a,(de)
        or a
        jr nz,.c0f
        inc de
        inc b
        jr .c0
.c0f:   ld a,b
        ld (pk_b0),a
        ld de,ROWBUF+4
        ld b,4
.c1:    ld a,(de)
        or a
        jr nz,.c1f
        dec de
        dec b
        jr .c1
.c1f:   ld a,b
        ld hl,pk_b0
        sub (hl)
        inc a
        ld (pk_w),a
        pop hl
        push hl
        ld a,(pk_r0)
        ld (hl),a               ; r0
        inc hl
        ld c,a
        ld a,(pk_r1)
        sub c
        inc a
        ld (hl),a               ; nr
        inc hl
        ld b,a
        ld a,(pk_b0)
        ld (hl),a               ; b0
        inc hl
        ld a,(pk_w)
        ld (hl),a               ; w
        inc hl
        ex de,hl                ; DE = données
        ld a,c                  ; r0
        add a,LOW SPR_M
        ld l,a
        ld h,HIGH SPR_M         ; (SPR_M ne traverse pas de page)
.row:   push bc
        push hl
        ld a,(hl)
        call .gen5
        ld a,(pk_b0)
        add a,LOW ROWBUF
        ld l,a
        ld h,HIGH ROWBUF
        ld a,(pk_w)
        ld b,a
.cp:    ld a,(hl)
        cpl
        ld (de),a
        inc l
        inc de
        djnz .cp
        pop hl
        inc l
        pop bc
        djnz .row
        pop hl
        ret

; A = m (8 pixels CPC) -> ROWBUF : 5 octets de masque pour le décalage pk_s
.gen5:  ld c,a
        ld a,(pk_s)
        or a
        ld a,c
        jr z,.g0
        srl a                   ; décalage 1 : m >> 1, bit 0 -> 5e octet
.g0:    push af
        ld hl,ROWBUF
        rrca
        rrca
        rrca
        and $1E                 ; (m >> 4) x 2
        call .n2
        pop af
        push af
        add a,a
        and $1E                 ; (m AND 15) x 2
        call .n2
        pop af
        ld a,(pk_s)
        or a
        ld a,0
        jr z,.g4
        bit 0,c
        jr z,.g4
        ld a,$AA
.g4:    ld (hl),a
        ret
.n2:    push hl
        add a,LOW N2
        ld l,a
        ld h,HIGH N2
        ld a,(hl)
        inc l
        ld b,(hl)
        pop hl
        ld (hl),a
        inc hl
        ld (hl),b
        inc hl
        ret

pk_u:       db 0
pk_r0:      db 0
pk_r1:      db 0
pk_b0:      db 0
pk_w:       db 0
pk_s:       db 0

; --- draw_cells (V_BASE) --------------------------------------------------------------------
draw_cells:
        ld a,(stamp)
        inc a
        jr nz,.st
        ld hl,STAMPS            ; tous les 255 tours : remise à zéro
        ld de,STAMPS+1
        ld bc,767
        ld (hl),0
        ldir
        ld a,1
.st:    ld (stamp),a
        ld a,(back_base)        ; écran caché, dans draw_cell (auto-modifié)
        ld (draw_cell.bb+1),a
        ld a,(full_screens)
        or a
        jr z,.part
        dec a
        ld (full_screens),a
        ; tout l'écran
        ld de,0
.all:   push de
        call draw_cell
        pop de
        inc de
        ld a,d
        cp 3
        jr c,.all
        ret
.part:  ld hl,(chg_cur)
        call .list
        ld hl,(chg_old)
        call .list
        ; cases sous les sprites dessinés dans cet écran il y a deux trames
        call rects_ptr          ; HL = rectangles de l'écran caché
        ld a,(hl)
        or a
        ret z
        ld b,a
        inc hl
.r:     push bc
        ld c,(hl)               ; x0
        inc hl
        ld b,(hl)               ; y0
        inc hl
        ld a,(hl)               ; x1
        sub c
        inc a
        ld (rc_w),a
        inc hl
        ld a,(hl)               ; y1
        sub b
        inc a
        inc hl
        push hl
        ld l,b                  ; case = y0 x 32 + x0
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld b,a                  ; B = hauteur
        ld a,c
        add a,l
        ld e,a
        ld d,h
        ld a,(rc_w)
        ld c,a
.ry:    push bc
        push de
.rx:    ld hl,STAMPS            ; déjà dessinée à cette trame ?
        add hl,de
        ld a,(stamp)
        cp (hl)
        jr z,.rxs
        ld (hl),a
        push de                 ; (draw_cell garde BC)
        call draw_cell
        pop de
.rxs:   inc de
        dec c
        jr nz,.rx
        pop de
        ld hl,32
        add hl,de
        ex de,hl
        pop bc
        djnz .ry
        pop hl
        pop bc
        djnz .r
        ret
.list:  ld a,(hl)
        or a
        ret z
        ld b,a
        inc hl
        inc hl
        ld a,(stamp)
        ld c,a                  ; C = numéro de trame
.l:     ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,STAMPS            ; déjà dessinée à cette trame ?
        add hl,de
        ld a,c
        cp (hl)
        jr z,.ls
        ld (hl),a
        call draw_cell          ; (garde BC)
.ls:    pop hl
        djnz .l
        ret

; HL = rectangles de l'écran caché
rects_ptr:
        ld a,(back_base)
        cp SCR_A/256
        ld hl,RECTS_A
        ret z
        ld hl,RECTS_B
        ret

; DE = case (0-767) : copie la tuile du cache dans l'écran caché. Les
; données sont lues par la pile (POP : 2 octets en 3 NOPs), dans l'ordre
; rangé par conv_run : lignes 0 1 3 2 6 7 5 4, où passer à la ligne suivante
; ne change qu'un bit de H (SET/RES), en zigzag (INC L / DEC L).
; Interruptions coupées pendant que SP est détourné (~80 NOPs). Garde BC.
draw_cell:
        ld hl,CADDR
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                  ; HL = tuile convertie
        ex de,hl                ; écran : base + 2 x case
        add hl,hl
        ld a,h
.bb:    add a,0                 ; (back_base, posé par draw_cells)
        ld h,a
        di
        ld (.sp+1),sp
        ex de,hl
        ld sp,hl                ; SP = données
        ex de,hl                ; HL = écran
        pop de                  ; ligne 0
        ld (hl),e
        inc l
        ld (hl),d
        set 3,h
        pop de                  ; ligne 1
        ld (hl),e
        dec l
        ld (hl),d
        set 4,h
        pop de                  ; ligne 3
        ld (hl),e
        inc l
        ld (hl),d
        res 3,h
        pop de                  ; ligne 2
        ld (hl),e
        dec l
        ld (hl),d
        set 5,h
        pop de                  ; ligne 6
        ld (hl),e
        inc l
        ld (hl),d
        set 3,h
        pop de                  ; ligne 7
        ld (hl),e
        dec l
        ld (hl),d
        res 4,h
        pop de                  ; ligne 5
        ld (hl),e
        inc l
        ld (hl),d
        res 3,h
        pop de                  ; ligne 4
        ld (hl),e
        dec l
        ld (hl),d
.sp:    ld sp,0
        ei
        ret

; --- draw_sprites (V_B4) ------------------------------------------------------------------
; Sprites 16x16 de la copie SAT_BUF, du dernier au premier. Chacun est noté
; (rectangle de cases) pour être effacé dans cet écran deux trames plus tard.
draw_sprites:
        ld a,V_B4
        call set_view
        call rects_ptr
        ld (rect_ptr),hl
        ld (hl),0
        inc hl
        ld (rect_wr),hl
        ; nombre de sprites (jusqu'au Y = $D0), puis du dernier au premier
        ld hl,SAT_BUF
        ld de,4
        ld b,32
.cnt:   ld a,(hl)
        cp $D0
        jr z,.go
        add hl,de
        djnz .cnt
.go:    ld a,32
        sub b
        jr z,.end
        ld b,a
        push hl
        pop iy                  ; IY = entrée suivant la dernière
        ld de,-4
.spr:   add iy,de
        ld a,(iy+3)
        and $0F                 ; couleur 0 : transparent
        jr z,.nx
        push bc
        call draw_sprite
        pop bc
        ld de,-4
.nx:    djnz .spr
.end:   ld a,V_BASE
        jp set_view

; IY = entrée de la table des sprites (Y, X, motif, couleur), A = couleur (1-15)
draw_sprite:
        ld hl,COLB
        add a,l
        ld l,a
        ld a,(hl)
        ld (spr_cb),a           ; couleur (2 pixels)
        ; Y écran = Y + 1 (Y >= $E1 : négatif) -> BC (signé)
        ld a,(iy+0)
        inc a
        ld c,a
        ld b,0
        cp $E2
        jr c,.ypos
        cp -16
        ret c                   ; au-dessus de l'écran
        dec b
        jr .yok
.ypos:  cp 192
        ret nc                  ; sous l'écran
.yok:   ; X écran = X (- 32) ; colonne d'octets = X / 4, décalage = bit 1
        ld l,(iy+1)
        ld h,0
        bit 7,(iy+3)
        jr z,.xp
        ld de,-32
        add hl,de
.xp:    ld a,l
        and 2
        ld e,a                  ; E = décalage (0 ou 2)
        sra h
        rr l
        sra h
        rr l
        ld d,l                  ; D = colonne d'octets (-8..63)
        ; entrée du cache : ENTTAB[2 x (motif / 4) + décalage]
        ld a,(iy+2)
        and $FC
        or e
        ld l,a
        ld h,HIGH ENTTAB
        ld a,(hl)
        inc l
        ld h,(hl)
        ld l,a
        ; r0, nr, b0, w (une entrée ne traverse pas de page)
        ld a,(hl)               ; r0 : BC = y_top = y + r0
        inc l
        add a,c
        ld c,a
        jr nc,$+3
        inc b
        ld a,(hl)               ; nr
        inc l
        or a
        ret z                   ; motif vide
        ld e,a                  ; E = nr
        ld a,(hl)               ; b0 : D = x_byte = colonne + b0
        inc l
        add a,d
        ld d,a
        ld a,(hl)               ; w
        inc l
        ld (spr_w),a
        ; entièrement visible ? (0 <= y_top, y_top + nr <= 192, 0 <= x_byte,
        ; x_byte + w <= 64) : pas de découpage
        inc b
        dec b
        jr nz,.clip
        ld a,c
        add a,e
        jr c,.clip
        cp 193
        jr nc,.clip
        bit 7,d
        jr nz,.clip
        ld a,(spr_w)
        add a,d
        cp 65
        jr nc,.clip
        ld a,c
        ld (spr_ys),a
        ld a,e
        ld (spr_nr),a
        ld a,d
        ld (spr_xs),a
        ld a,(spr_w)
        ld (spr_nb),a
        ld (spr_src),hl
        jr .draw
.clip:  ld (spr_src),hl
        ld l,c
        ld h,b                  ; HL = y_top (signé)
        ld b,e                  ; B = lignes
        ld e,d                  ; E = x_byte (signé)
        ; lignes : coupe en haut (y < 0) et en bas (192)
        ld c,0                  ; C = lignes sautées en haut
        bit 7,h
        jr z,.yt
        ld a,l
        neg
        ld c,a                  ; -y_top
        ld hl,0
.yt:    ld a,b                  ; lignes restantes
        sub c
        ret z
        ret c
        ld b,a
        ld a,h
        or a
        ret nz                  ; y >= 256 : invisible
        ld a,l
        cp 192
        ret nc
        ld (spr_ys),a           ; première ligne visible
        add a,b
        sub 192
        jr c,.yb
        jr z,.yb
        ld d,a                  ; dépasse le bas de D lignes
        ld a,b
        sub d
        ld b,a
.yb:    ld a,b
        ld (spr_nr),a
        ; colonnes : coupe à gauche (< 0) et à droite (64)
        ld a,(spr_w)
        ld d,a                  ; D = largeur visible
        ld b,0                  ; B = colonnes sautées à gauche
        bit 7,e
        jr z,.xl
        ld a,e
        neg
        ld b,a
        ld a,d
        sub b
        ret z
        ret c
        ld d,a
        ld e,0
.xl:    ld a,e
        cp 64
        ret nc
        add a,d
        sub 64
        jr c,.xr
        jr z,.xr
        ld l,a
        ld a,d
        sub l
        ld d,a
.xr:    ld a,e
        ld (spr_xs),a
        ld a,d
        ld (spr_nb),a
        ; source = données + lignes sautées x w + colonnes sautées
        ld hl,(spr_src)
        ld a,c
        or a
        jr z,.sr
        push bc
        ld b,a
        ld a,(spr_w)
        ld e,a
        ld d,0
.sm:    add hl,de
        djnz .sm
        pop bc
.sr:    ld e,b
        ld d,0
        add hl,de
        ld (spr_src),hl
.draw:  ; rectangle de cases à effacer plus tard
        call spr_rect
        ; destination
        ld a,(spr_ys)
        call line_addr
        ld a,(spr_xs)
        add a,l
        ld l,a
        ex de,hl                ; DE = écran
        ld a,(spr_cb)
        ld c,a                  ; C = couleur (2 pixels)
        ld a,(spr_nr)
        ld b,a
        ld a,(spr_nb)
        ld ixl,a
        ld a,(spr_w)
        cp ixl
        ld hl,(spr_src)
        jr nz,.gen
        ; largeur entière : boucle déroulée selon w (saut auto-modifié)
        dec a
        add a,a
        add a,LOW .kt
        ld l,a
        ld h,HIGH .kt
        jr nc,$+3
        inc h
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (.jk+1),hl
        ld hl,(spr_src)
.jk:    jp 0
.kt:    dw spk1, spk2, spk3, spk4, spk5
.gen:   ; sprite coupé par un bord : ixl octets par ligne, pas de w
.gr:    push bc
        push de
        ld b,ixl
.gb:    ld a,(de)
        xor c
        and (hl)
        xor c
        ld (de),a
        inc l                   ; (une entrée ne traverse pas de page)
        inc e
        djnz .gb
        pop de
        ld a,(spr_w)
        sub ixl
        add a,l
        ld l,a
        jr nc,$+3
        inc h
        pop bc
        call next_line
        djnz .gr
        ret

        MACRO SPRK n, lab
lab:
        REPT n
        ld a,(de)
        xor c
        and (hl)
        xor c
        ld (de),a
        inc l                   ; (une entrée ne traverse pas de page)
        inc e
        ENDR
        ld a,e
        sub n
        ld e,a
        ld a,d
        add a,8
        ld d,a
        and $38
        jr nz,$+10
        ld a,e
        add a,64
        ld e,a
        ld a,d
        adc a,-$40
        ld d,a
        djnz lab
        ret
        ENDM

        SPRK 1, spk1
        SPRK 2, spk2
        SPRK 3, spk3
        SPRK 4, spk4
        SPRK 5, spk5

; DE = adresse écran -> ligne suivante
next_line:
        ld a,d
        add a,8
        ld d,a
        and $38
        ret nz
        ld a,e
        add a,64
        ld e,a
        ld a,d
        adc a,-$40
        ld d,a
        ret

; A = y (0-191) -> HL = adresse de la ligne dans l'écran caché (tables)
line_addr:
        ld l,a
        ld h,HIGH LT_HI
        ld a,(back_base)
        add a,(hl)
        ld h,HIGH LT_LO
        ld l,(hl)
        ld h,a
        ret

; Rectangle de cases couvert par la partie visible du sprite (octets
; spr_xs .. +spr_nb-1, lignes spr_ys .. +spr_nr-1) -> liste de l'écran caché,
; fusionné avec le précédent s'ils se touchent (les sprites superposés d'un
; même personnage ne font qu'un rectangle). Entrée : x0, y0, x1, y1 (cases).
spr_rect:
        ld a,(spr_xs)           ; colonnes de cases = octets / 2
        srl a
        ld b,a                  ; B = x0
        ld a,(spr_xs)
        ld hl,spr_nb
        add a,(hl)
        dec a
        srl a
        ld c,a                  ; C = x1
        ld a,(spr_ys)           ; rangées = lignes / 8
        rrca
        rrca
        rrca
        and $1F
        ld d,a                  ; D = y0
        ld a,(spr_ys)
        ld hl,spr_nr
        add a,(hl)
        dec a
        rrca
        rrca
        rrca
        and $1F
        ld e,a                  ; E = y1
        ld hl,(rect_ptr)
        ld a,(hl)
        or a
        jr z,.new
        ; précédent : se touchent-ils ? (x0 <= px1+1, px0 <= x1+1, idem en y)
        push hl
        ld hl,(rect_wr)
        dec hl
        dec hl
        dec hl
        dec hl                  ; HL = précédent
        ld a,(hl)               ; px0
        dec a
        cp c
        jr z,.t1
        jr nc,.nomerge          ; px0 - 1 > x1
.t1:    inc hl
        inc hl
        ld a,(hl)               ; px1
        inc a
        cp b
        jr c,.nomerge2          ; px1 + 1 < x0
        dec hl
        ld a,(hl)               ; py0
        dec a
        cp e
        jr z,.t2
        jr nc,.nomerge1
.t2:    inc hl
        inc hl
        ld a,(hl)               ; py1
        inc a
        cp d
        jr c,.nomerge3
        ; union
        dec hl
        dec hl
        dec hl                  ; px0
        ld a,(hl)
        cp b
        jr c,$+3
        ld (hl),b
        inc hl
        ld a,(hl)
        cp d
        jr c,$+3
        ld (hl),d
        inc hl
        ld a,(hl)
        cp c
        jr nc,$+3
        ld (hl),c
        inc hl
        ld a,(hl)
        cp e
        jr nc,$+3
        ld (hl),e
        pop hl
        ret
.nomerge3:
        dec hl
.nomerge2:
.nomerge1:
.nomerge:
        pop hl
        ld a,(hl)
        cp 32
        ret nc
.new:   inc (hl)
        ld hl,(rect_wr)
        ld (hl),b
        inc hl
        ld (hl),d
        inc hl
        ld (hl),c
        inc hl
        ld (hl),e
        inc hl
        ld (rect_wr),hl
        ret

; --- flip ----------------------------------------------------------------------------------
flip_req:
        ld a,V_B5
        call set_view
        di
        ld a,(frame_cnt)
        ld (flip_f0),a
        ld a,(back_page)
        ld bc,$BC0C
        out (c),c
        ld b,$BD
        out (c),a
        ei
        ld a,V_BASE
        call set_view
        ; listes : la courante devient l'ancienne, l'ancienne est vidée
        ld hl,(chg_old)
        ld de,(chg_cur)
        ld (chg_old),de
        ld (chg_cur),hl
        ld (hl),0
        ret

flip_wait:
        ld a,V_B5
        call set_view
        ld a,(flip_f0)
        ld e,a
.w:     ld a,(frame_cnt)
        cp e
        jr z,.w
        ld a,V_BASE
        call set_view
        call update_palette
        ld a,(back_base)
        xor (SCR_A ^ SCR_B)/256
        ld (back_base),a
        ld a,(back_page)
        xor $10
        ld (back_page),a
        ret

; Encres : couleur n du TMS = encre n ; encre 0 et bordure = couleur de fond
; (registre 7) ; écran éteint (registre 1, bit 6) : tout en couleur de fond
update_palette:
        ld a,(r_regs+7)
        and $0F
        ld e,a
        ld a,(r_regs+1)
        and $40
        xor $40
        rlca                    ; bit 7 = éteint
        or e
        ld hl,pal_state
        cp (hl)
        ret z
        ld (hl),a
        ld d,a
        ld hl,INKHW
        ld a,e
        add a,l
        ld l,a
        ld e,(hl)               ; couleur de fond (matérielle)
        ld hl,INKHW
        ld c,0
.i:     ld b,GA
        out (c),c
        bit 7,d
        jr nz,.bg
        ld a,c
        or a
        jr z,.bg
        ld a,(hl)
        jr .set
.bg:    ld a,e
.set:   out (c),a
        inc hl
        inc c
        ld a,c
        cp 16
        jr nz,.i
        ld a,$10
        out (c),a
        out (c),e
        ret

; --- Variables du rendu (base 0) ------------------------------------------------------------------
back_base:  db 0                ; octet fort de l'écran caché ($80 ou $C0)
back_page:  db 0                ; R12 correspondant ($20 ou $30)
full_screens: db 0              ; écrans à redessiner en entier
need_names: db 0
pal_state:  db 0
stamp:      db 0
r_regs:     ds 8
grab_list:  dw 0
chg_cur:    dw 0
chg_old:    dw 0
names_hi:   db 0
pat_hi:     db 0
col_hi:     db 0
spr_q:      db 0
spr_col:    db 0
spr_cb:     db 0
spr_src:    dw 0
spr_nb:     db 0
spr_nr:     db 0
spr_w:      db 0
spr_ys:     db 0
spr_xs:     db 0
rect_ptr:   dw 0
rect_wr:    dw 0
rc_x:       db 0
rc_w:       db 0
rc_h:       db 0
r_satlen:   db 0
flip_f0:    db 0
r_logo:     db 0
