; ===========================================================================
; defs.asm - carte mémoire du CPC664 et constantes (celles de CPC Tennis)
;
; La logique du jeu est la ROM GB traduite en Z80 (gb/gb_logic.asm, par
; tools/gb2z80.py) : elle travaille sur la RAM GB à ses adresses d'origine,
; que le CPC réserve. L'écran (16 Ko) est donc déplacé de $C000 en $4000.
; ===========================================================================

; --- Carte mémoire -------------------------------------------------------------
;   $0000-$003F  vecteurs (IM 1 : saut en $0038), $0100-$01FF pile
;   $0200-$3FFF  programme (partie A), chargé par RUN"GAME"
;   $4000-$7FFF  écran (mode 1). Dans le fichier : bloc déplacé au démarrage
;                vers $C100, images de base et tables lues au démarrage
;   $8000-$A5FF  programme (partie B) ; $A600-$BFFF libre une fois le firmware
;                coupé (images décalées des sprites)
;   $C000-$C0FF  RAM GB (étendue à vérifier pour chaque jeu) ; $FF80 HRAM GB
; Le fichier chargé par AMSDOS doit tenir sous HIMEM ($A67B sur 664) : $0200-$A5FF.
LOAD_ADDR   equ $0200
SCREEN      equ $4000
RELOC       equ $C100
RELOC_END   equ $D000
GB_WRAM     equ $C000
GB_HRAM     equ $FF80

; --- Joypad GB --------------------------------------------------------------
PAD_A       equ $01
PAD_B       equ $02
PAD_START   equ $08
PAD_R       equ $10
PAD_L       equ $20
PAD_U       equ $40
PAD_D       equ $80

; --- Sprites (À FAIRE : emplacements du jeu) ---------------------------------
; Un emplacement = un objet affiché. Chaque emplacement qui change est effacé
; puis redessiné dans l'ordre du balayage (update.asm).
NSLOTS      equ 1
S_DEMO      equ 0

; --- Matériel du CPC -----------------------------------------------------------
GA          equ $7F             ; Gate Array : encres, mode, ROM (OUT ($7Fxx))
GA_MODE1    equ %10001101       ; mode 1, ROM basse et haute coupées
GA_MODE1_LROM equ %10001001     ; mode 1, ROM basse visible (police)
GA_MODE0    equ %10001100       ; mode 0 (16 couleurs), ROM coupées
