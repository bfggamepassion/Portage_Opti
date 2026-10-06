; ===========================================================================
; render.asm - sprites matériels (repris de C64 Tennis)
;
; Principe : la position GB d'un objet se calcule comme dans les routines
; d'affichage de la ROM (projection + décalage de l'image). Le C64 montrant
; toute l'image GB (256 pixels de large), position C64 = position GB +
; décalage fixe, sans défilement.
; prepare_all (à écrire pour chaque jeu) remplit des registres fantômes ;
; l'interruption les recopie dans le VIC pendant le bas de l'écran.
; ===========================================================================

SPR_X0      = 24 + 32           ; X sprite = x GB + 56 (colonnes C64 4-35 = GB 0-31)
SPR_Y0      = 50 - 16           ; Y sprite = y GB + 34 (rangée C64 0 = rangée GB 2)

spr_x       .fill 8
spr_y       .fill 8
spr_ptr     .fill 8
spr_xhi     .byte 0
spr_on      .byte 0
spr_pri     .byte 0
bitmask     .byte 1, 2, 4, 8, 16, 32, 64, 128
ball_b      .byte 0             ; projection de la balle (avant la hauteur)
ball_c      .byte 0
ball_pri    .byte 0

sprites_init
        lda #0                      ; noir, blanc : couleurs communes (multicolore)
        sta $D025
        lda #1
        sta $D026
        ldx #7
-       lda spr_colors,x
        sta $D027,x
        dex
        bpl -
        lda #SPR_MC                 ; sprites multicolores
        sta $D01C
        lda #0
        sta $D017
        sta $D01D
        sta spr_on
        rts

spr_colors  .byte 0, 1, 2, 2, 6, 6, 0, 0       ; À FAIRE : couleur propre de chaque sprite
SPR_MC      = %00111100                        ; À FAIRE : sprites multicolores

; Pendant l'interruption du bas de l'écran : registres fantômes -> VIC
vbl_sprites
        ldx #7
-       txa
        asl a
        tay
        lda spr_x,x
        sta $D000,y
        lda spr_y,x
        sta $D001,y
        lda spr_ptr,x
        sta SPRPTR,x
        dex
        bpl -
        lda spr_xhi
        sta $D010
        lda spr_pri
        sta $D01B
        lda spr_on
        sta $D015
        rts

; Place le sprite X : position GB (zC, zB) + décalage signé (zW, zW+1)
place   ldy #0
        lda zW
        bpl +
        dey
+       clc
        lda zC
        adc #SPR_X0
        sta zT
        lda #0
        adc #0
        sta zT+1
        clc
        lda zT
        adc zW
        sta spr_x,x
        tya
        adc zT+1
        lsr a                       ; bit 8 de X -> C
        lda bitmask,x
        bcc +
        ora spr_xhi
        sta spr_xhi
        jmp _y
+       eor #$FF
        and spr_xhi
        sta spr_xhi
_y      ldy #0
        lda zW+1
        bpl +
        dey
+       clc
        lda zB
        adc #SPR_Y0
        sta zT
        lda #0
        adc #0
        sta zT+1
        clc
        lda zT
        adc zW+1
        sta zT
        tya
        adc zT+1
        beq +
        lda #0                      ; hors de l'écran : caché dans la bordure
        sta zT
+       lda zT
        sta spr_y,x
        ldy #0
        rts

; Allume (A = masque) ou éteint des sprites
spr_show
        ora spr_on
        sta spr_on
        rts
spr_hide
        eor #$FF
        and spr_on
        sta spr_on
        rts

; À FAIRE : lire la RAM GB (objets) et placer les sprites, comme les routines
; d'affichage de la ROM. Exemple (Tennis, joueur 1 en sprites 2-3) :
;   projeter $C002 -> zB (y), zC (x) ; image = $C001 -> pointeurs et décalages
;   ldx #2 / jsr place ; ldx #3 / jsr place (21 lignes plus bas) ; spr_show
; Voir C64/src/render.asm du repo Tennis (projection native vérifiée par
; tools/test_proj.py contre la ROM traduite).
prepare_all
        rts
