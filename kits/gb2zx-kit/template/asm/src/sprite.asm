; ===========================================================================
; sprite.asm (repris tel quel de ZX Tennis ; à régler : NSLOTS, SLOT_BIG,
;   SPRMEM, BIGCACHE/BIGSAVE selon la taille des sprites du jeu)
; sprite.asm - sprites logiciels masqués, en deux temps
;   1. spr_prepare (pendant la logique) : position ; si l'image ou le décalage
;      change, le sprite est décalé au pixel près dans le cache du slot.
;   2. Juste après l'interruption : spr_restore de tous les slots (ordre
;      inverse) puis spr_draw de chacun (sauvegarde du fond + dessin masqué,
;      boucles déroulées, données lues par la pile).
; Format d'un sprite (gfx/sprites.asm) : largeur W (octets), hauteur H,
;   décalage X et Y (signés, depuis le point d'ancrage = pieds), puis H lignes
;   de W paires (masque, dessin). Écran = (écran AND masque) OR dessin.
; ===========================================================================

; Bloc de 16 octets par slot (SlotTab)
ST_ON    equ 0
ST_N     equ 1
ST_SH    equ 2
ST_W1    equ 3
ST_H     equ 4
ST_COL   equ 5
ST_TOP   equ 6          ; 16 bits signé
ST_CACHE equ 8          ; 16 bits
ST_BUF   equ 10         ; 16 bits

BIGCACHE  equ 256       ; 32 lignes x 4 paires
BIGSAVE   equ 200       ; 2 + 32 lignes x (2 + 4)
SMALLCACHE equ 32
SMALLSAVE equ 32

SlotTab:    ds 16 * NSLOTS
slot_big:   SLOT_BIG                    ; défini dans defs.asm : 1 = grand slot (32 lignes x 4 octets)

; Initialise les slots : caches et tampons dans SPRMEM
spr_init:
        ld ix,SlotTab
        ld hl,SPRMEM
        ld de,slot_big
        ld b,NSLOTS
.l:
        ld (ix+ST_ON),0
        ld (ix+ST_N),$FF
        ld (ix+ST_CACHE),l
        ld (ix+ST_CACHE+1),h
        ld a,(de)
        or a
        push de
        ld de,SMALLCACHE
        jr z,.c
        ld de,BIGCACHE
.c:
        add hl,de
        ld (ix+ST_BUF),l
        ld (ix+ST_BUF+1),h
        ld (hl),0                   ; tampon vide
        pop de
        ld a,(de)
        or a
        push de
        ld de,SMALLSAVE
        jr z,.s
        ld de,BIGSAVE
.s:
        add hl,de
        pop de
        inc de
        push de
        ld de,16
        add ix,de
        pop de
        djnz .l
        ret

; IX = entrée du slot A
slot_ix:
        add a,a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld ix,SlotTab
        add ix,de
        ret

spr_hide:
        call slot_ix
        ld (ix+ST_ON),0
        ret

; Prépare le sprite E dans le slot A, point d'ancrage x = C, y = HL (signé)
spr_prepare:
        push hl
        push de
        call slot_ix
        pop de
        ld a,e
        ld (sp_n),a
        ; HL = adresse du sprite
        ld l,a
        ld h,0
        add hl,hl
        ld de,SprTable
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (sp_p),hl
        ld a,(hl)
        ld (sp_w),a
        inc hl
        ld a,(hl)
        ld (sp_h),a
        inc hl
        ld e,(hl)                   ; décalage X signé
        ld d,0
        bit 7,e
        jr z,.xo
        dec d
.xo:
        inc hl
        ld a,(hl)                   ; décalage Y signé
        ld (sp_yo),a
        ; left = x + xo, borné à [0, 256 - 8*(w+1)]
        ld l,c
        ld h,0
        add hl,de
        bit 7,h
        jr z,.lpos
        ld hl,0
.lpos:
        ld a,(sp_w)
        inc a
        add a,a
        add a,a
        add a,a                     ; 8*(w+1)
        neg                         ; 256 - 8*(w+1)
        ld e,a
        ld d,0
        ld a,h
        or a
        jr nz,.clamp
        ld a,l
        cp e
        jr c,.lok
.clamp:
        ld l,e
.lok:
        ld a,l
        and 7
        ld (sp_sh),a
        ld a,l
        rrca
        rrca
        rrca
        and $1F
        ld (sp_col),a
        ; top = y + yo
        pop hl
        ld a,(sp_yo)
        ld e,a
        ld d,0
        bit 7,e
        jr z,.yo
        dec d
.yo:
        add hl,de
        ld (sp_top),hl
        call .commit
        ; recaler le sprite si l'image ou le décalage ont changé
        ld a,(sp_n)
        cp (ix+ST_N)
        jr nz,.shift
        ld a,(sp_sh)
        cp (ix+ST_SH)
        ret z
.shift:
        ld a,(sp_n)
        ld (ix+ST_N),a
        ld a,(sp_sh)
        ld (ix+ST_SH),a
        ld a,(sp_w)
        inc a
        ld (ix+ST_W1),a
        ld a,(sp_h)
        ld (ix+ST_H),a
        ld l,(ix+ST_CACHE)
        ld h,(ix+ST_CACHE+1)
        ld (ss_dst),hl
        ld hl,(sp_p)
        ld de,4
        add hl,de
        ld (ss_src),hl
        jp spr_shift
.commit:
        ld a,(sp_col)
        ld (ix+ST_COL),a
        ld hl,(sp_top)
        ld (ix+ST_TOP),l
        ld (ix+ST_TOP+1),h
        ld (ix+ST_ON),1
        ret

sp_col:       db 0
sp_top:       dw 0

sp_n:   db 0
sp_p:   dw 0
sp_w:   db 0
sp_h:   db 0
sp_yo:  db 0
sp_sh:  db 0

; Décale sp_h lignes de sp_w paires (ss_src) vers ss_dst : sp_w+1 paires/ligne.
; Une ligne est chargée dans les registres : masques dans B C D E, dessins
; dans B' C' D' E'. Elle est décalée par rotations : s passes vers la droite
; (s = 0-4) ou 8-s passes vers la gauche (s = 5-7), jamais plus de 4.
; Bits entrants : 1 pour le masque (SCF), 0 pour le dessin (OR A).
; Une routine de ligne par largeur (1-3 octets) et par sens.
; L'interruption n'utilise que AF : les registres alternés sont libres.
spr_shift:
        ld a,(sp_sh)
        cp 5
        jr nc,.left
        ld (ss_n),a                 ; 0 à 4 passes vers la droite
        ld hl,.right_rows
        jr .go
.left:
        neg
        add a,8
        ld (ss_n),a                 ; 1 à 3 passes vers la gauche
        ld hl,.left_rows
.go:
        ld a,(sp_w)
        dec a
        add a,a
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (.call+1),hl
        ld a,(sp_h)
        ld ixl,a
        ld hl,(ss_dst)              ; HL' = destination
        exx
        ld hl,(ss_src)              ; HL = source
.rowloop:
.call:
        call 0
        dec ixl
        jr nz,.rowloop
        ret
.right_rows: dw sh_r1, sh_r2, sh_r3
.left_rows:  dw sh_l1, sh_l2, sh_l3

; Charge une paire (masque, dessin) de la source dans r et r'
        MACRO SH_LOAD r
        ld r,(hl)
        inc hl
        ld a,(hl)
        inc hl
        exx
        ld r,a
        exx
        ENDM

; Octet de remplissage : masque $FF, dessin 0
        MACRO SH_FILL r
        ld r,$FF
        exx
        ld r,0
        exx
        ENDM

; Range la paire r, r' à la destination (HL')
        MACRO SH_STORE r
        ld a,r
        exx
        ld (hl),a
        inc hl
        ld (hl),r
        inc hl
        exx
        ENDM

; Passes de décalage (A = nombre de passes, conservé par OR A)
        MACRO SH_RIGHT
        ld a,(ss_n)
        or a
        jr z,.st
.p:
        scf
        rr b
        rr c
        rr d
        rr e
        exx
        or a
        rr b
        rr c
        rr d
        rr e
        exx
        dec a
        jr nz,.p
.st:
        ENDM

        MACRO SH_LEFT
        ld a,(ss_n)
.p:
        scf
        rl e
        rl d
        rl c
        rl b
        exx
        or a
        rl e
        rl d
        rl c
        rl b
        exx
        dec a
        jr nz,.p
        ENDM

sh_r1:
        SH_LOAD b
        SH_FILL c
        SH_FILL d
        SH_FILL e
        SH_RIGHT
        SH_STORE b
        SH_STORE c
        ret
sh_r2:
        SH_LOAD b
        SH_LOAD c
        SH_FILL d
        SH_FILL e
        SH_RIGHT
        SH_STORE b
        SH_STORE c
        SH_STORE d
        ret
sh_r3:
        SH_LOAD b
        SH_LOAD c
        SH_LOAD d
        SH_FILL e
        SH_RIGHT
        SH_STORE b
        SH_STORE c
        SH_STORE d
        SH_STORE e
        ret
sh_l1:
        SH_FILL b
        SH_LOAD c
        SH_FILL d
        SH_FILL e
        SH_LEFT
        SH_STORE b
        SH_STORE c
        ret
sh_l2:
        SH_FILL b
        SH_LOAD c
        SH_LOAD d
        SH_FILL e
        SH_LEFT
        SH_STORE b
        SH_STORE c
        SH_STORE d
        ret
sh_l3:
        SH_FILL b
        SH_LOAD c
        SH_LOAD d
        SH_LOAD e
        SH_LEFT
        SH_STORE b
        SH_STORE c
        SH_STORE d
        SH_STORE e
        ret

ss_src:  dw 0
ss_dst:  dw 0
ss_n:    db 0

; Dessine le slot A (s'il est affiché)
spr_draw:
        add a,a
        add a,a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld de,SlotTab
        add hl,de
        ld a,(hl)
        or a
        ret z
        di
        ld (sd_ix),ix
        inc hl
        inc hl
        inc hl
        ld a,(hl)                   ; largeur + 1
        ld (sd_w1),a
        add a,a
        ld (sd_w2),a
        ld a,(sd_w1)                ; entrée dans la boucle déroulée
        ld c,a
        ld a,5
        sub c
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        push hl
        ld hl,.unroll
        add hl,de
        ld (.jmp+1),hl
        pop hl
        inc hl
        ld b,(hl)                   ; hauteur
        inc hl
        ld a,(hl)
        ld (sd_col),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)                   ; DE = haut (signé)
        inc hl
        ld a,(hl)
        ld (sd_data),a
        inc hl
        ld a,(hl)
        ld (sd_data+1),a
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                      ; HL = tampon de sauvegarde
        ld (sd_buf),hl
        ld (hl),0
        ld c,0                      ; lignes coupées en haut
        bit 7,d
        jr z,.topok
.cliptop:
        inc c
        inc de
        dec b
        jp z,.empty
        bit 7,d
        jr nz,.cliptop
.topok:
        ld a,d
        or a
        jp nz,.empty
        ld a,e
        cp 192
        jp nc,.empty
        ld a,192                    ; hauteur visible = min(h, 192 - y)
        sub e
        cp b
        jr nc,.hok
        ld b,a
.hok:
        ld a,b
        ld (sd_n),a
        push hl
        ld hl,(sd_data)
        ld a,c
        or a
        jr z,.nds
        ld a,(sd_w2)
        ld d,0
.ds:
        push de
        ld e,a
        add hl,de
        pop de
        dec c
        jr nz,.ds
.nds:
        ld (sd_data),hl
        pop hl
        ld a,(sd_n)
        ld (hl),a
        inc hl
        ld a,(sd_w1)
        ld (hl),a
        inc hl
        ld a,e                      ; adresse écran de la première ligne
        and 7
        or $40
        ld d,a
        ld a,e
        rra
        rra
        rra
        and $18
        or d
        ld d,a
        ld a,e
        rla
        rla
        and $E0
        ld e,a
        ld a,(sd_col)
        or e
        ld e,a
        ld ixl,b
        ld (sd_sp),sp
        ld sp,(sd_data)
.rowl:
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
.jmp:
        jp .unroll
.unroll:
        REPT 5
        pop bc
        ld a,(de)
        ld (hl),a
        inc hl
        and c
        or b
        ld (de),a
        inc e
        ENDR
        ld a,(sd_col)               ; ligne suivante
        ld c,a
        ld a,e
        and $E0
        or c
        ld e,a
        inc d
        ld a,d
        and 7
        jr nz,.nl
        ld a,e
        add a,32
        ld e,a
        jr c,.nl
        ld a,d
        sub 8
        ld d,a
.nl:
        dec ixl
        jp nz,.rowl
        ld sp,(sd_sp)
.done:
        ld ix,(sd_ix)
        ei
        ret
.empty:
        ld hl,(sd_buf)
        ld (hl),0
        jr .done

sd_sp:   dw 0
sd_ix:   dw 0
sd_data: dw 0
sd_buf:  dw 0
sd_w1:   db 0
sd_w2:   db 0
sd_col:  db 0
sd_n:    db 0

; Remet le fond sauvegardé du slot A
spr_restore:
        call slot_ix
        ld l,(ix+ST_BUF)
        ld h,(ix+ST_BUF+1)
        ld a,(hl)
        or a
        ret z
        push hl
        ld (sr_n),a
        inc hl
        ld a,(hl)                   ; largeur + 1
        inc hl
        ld c,a
        ld a,5
        sub c
        add a,a
        ld e,a
        ld d,0
        push hl
        ld hl,.unroll
        add hl,de
        ld (.jmp+1),hl
        pop hl
        ld bc,$FFFF
.row:
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
.jmp:
        jp .unroll
.unroll:
        REPT 5
        ldi
        ENDR
        ld a,(sr_n)
        dec a
        ld (sr_n),a
        jr nz,.row
        pop hl
        ld (hl),0
        ret

sr_n:   db 0
