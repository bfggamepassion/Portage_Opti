; ===========================================================================
; render.asm - places des sprites (À FAIRE pour chaque jeu)
;
; Comme les routines d'affichage de la ROM (listes OAM) : position GB =
; projection / coordonnées de l'objet + décalage de l'image. Le CPC montrant
; toute l'image GB (256 pixels de large, rangées GB 2 à 26 chez Tennis) :
;   x écran = x GB + 32 ; y écran = y GB - 8 x (première rangée affichée).
; spr_prepare : A = emplacement, E = image, HL = ancrage y (signé), BC = ancrage x.
; Tennis : Amstrad/src/render.asm et proj.asm (projection native, vérifiée
; contre la ROM traduite par tools/test_proj.py).
; ===========================================================================

; Démonstration : la balle traverse l'écran.
demo_x: db 0

prepare_all:
        ld a,(demo_x)
        inc a
        ld (demo_x),a
        ld c,a
        ld b,0
        ld hl,32                    ; x écran = x + 32
        add hl,bc
        ld b,h
        ld c,l
        ld hl,100                   ; y écran
        ld e,0                      ; image 0
        ld a,S_DEMO
        jp spr_prepare
