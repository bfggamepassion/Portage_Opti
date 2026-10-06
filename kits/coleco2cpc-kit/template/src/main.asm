; ===========================================================================
; main.asm - Cabbage Patch Kids, Amstrad CPC 6128 (sjasmplus)
;
; Un seul fichier CABBAGE.BIN, chargé en $0400-$A5FF par RUN"CABBAGE" :
;   $0400-$33FF  cartouche $8000-$AFFF   -> banque 6
;   $4000-$7FFF  image de la base 0 (commun + rendu) -> $0000
;   $8000-$8FFF  cartouche $B000-$BFFF   -> banque 6
;   $9000-$9DFF  code « vue jeu » ($0200-$0FFF de la banque 4)
;   $9E00-$A5FF  chargeur (exécuté en premier)
; ===========================================================================

        DEVICE NOSLOT64K
        INCLUDE "defs.asm"

        MACRO CART_ORG addr
        IF (addr) < $B000
        ORG $0400 + (addr) - $8000
        ELSE
        ORG $8000 + (addr) - $B000
        ENDIF
        DISP addr
        ENDM

; --- Cartouche (corrigée par tools/gen_tables.py : police fine) ---------------------------------
        ORG $0400
        INCBIN "../build/cart.bin", 0, $3000
        ORG $8000
        INCBIN "../build/cart.bin", $3000, $1000

; --- Base 0 ------------------------------------------------------------------------------------
        ORG $4000
        DISP $0000
        INCLUDE "common.asm"
        INCLUDE "render.asm"
        INCLUDE "logo_tiles.asm"
        INCLUDE "font4.asm"             ; recopiés en banque 4 par init
        INCLUDE "logo_map.asm"
        ASSERT $ <= $3000
        ds $3000 - $, 0
        INCLUDE "tables.asm"
        ASSERT $ <= CADDR
        ENT

; --- Banque 4 : code « vue jeu » -----------------------------------------------------------------
        ORG $9000
        DISP $0200
        INCLUDE "gamecode.asm"
        ASSERT $ <= $1000
        ENT

; --- Chargeur -------------------------------------------------------------------------------------
        ORG $9E00
loader:
        di
        ld sp,$BFFE
        ld bc,GA*256 + GA_MODE0
        out (c),c
        ; cartouche -> banque 6
        ld bc,GA*256 + $C6
        out (c),c
        ld hl,$0400
        ld de,$4000
        ld bc,$3000
        ldir
        ld hl,$8000
        ld de,$7000
        ld bc,$1000
        ldir
        ; commun ($4000-$41FF du fichier) -> tampon, puis banque 4
        ld bc,GA*256 + $C0
        out (c),c
        ld hl,$4000
        ld de,$A600
        ld bc,$0200
        ldir
        ld bc,GA*256 + $C4
        out (c),c
        ld hl,$4000             ; banque 4 à zéro
        ld de,$4001
        ld bc,$3FFF
        ld (hl),0
        ldir
        ld hl,$A600
        ld de,$4000
        ld bc,$0200
        ldir
        ld hl,$9000
        ld de,$4200
        ld bc,$0E00
        ldir
        ; banques 5 et 7 à zéro
        ld bc,GA*256 + $C5
        out (c),c
        call .clear
        ld bc,GA*256 + $C7
        out (c),c
        call .clear
        ; base 0
        ld bc,GA*256 + $C0
        out (c),c
        ld hl,$4000
        ld de,$0000
        ld bc,$4000
        ldir
        jp init
.clear: ld hl,$4000
        ld de,$4001
        ld bc,$3FFF
        ld (hl),0
        ldir
        ret
        ASSERT $ <= $A600

; --- Corrections de la cartouche -------------------------------------------------------------------
        INCLUDE "patches.asm"

        SAVEBIN "../build/game.bin", $0400, $A600 - $0400
