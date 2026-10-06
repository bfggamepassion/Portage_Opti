; ===========================================================================
; patches.asm - corrections de la cartouche : chaque entrée-sortie du
; matériel Coleco devient un appel au code de la « vue jeu ». Adresses et
; contexte : re/cabbage.lst (tools/disasm.py). Aucun des octets remplacés
; au-delà du premier n'est une destination de saut.
; ===========================================================================

; --- VDP ---------------------------------------------------------------------------
        CART_ORG $8054          ; écrire A en VRAM (DE)
        jp hle_wr
        ENT
        CART_ORG $805D          ; lire la VRAM (DE)
        jp hle_rd
        ENT
        CART_ORG $8067          ; port de contrôle : E puis D
        jp hle_ctl
        ENT
        CART_ORG $8088          ; NMI : lecture de l'état
        ld a,0
        ENT
        CART_ORG $80AD          ; fin de NMI : lecture de l'état
        ld a,0
        ENT
        CART_ORG $80E5          ; démarrage : lecture de l'état
        ld a,0
        ENT
        CART_ORG $80E8          ; « jr $ » : le processeur libre sert au rendu
        rst $08
        nop
        ENT
        CART_ORG $85A0          ; lecture de l'état (entre push/pop af)
        nop
        nop
        ENT
        CART_ORG $85B9          ; copie d'un bloc en VRAM
        jp hle_block
        ENT
        CART_ORG $85C8          ; remplissage de VRAM
        jp hle_fill
        ENT
        CART_ORG $8BDE          ; « out ($BE),a / nop / nop / djnz » : A répété B fois
        call hle_rle
        nop
        nop
        nop
        ENT
        CART_ORG $B8AD          ; lecture de l'état (entre push/pop af)
        nop
        nop
        ENT

        CART_ORG $A125          ; boucle de dessin des lianes -> version native
        jp vine_loop
        ENT

        CART_ORG $A448          ; copie de rectangle -> version native
        jp nrect_wr
        ENT

        CART_ORG $8664          ; chaînes vers la VRAM -> version native
        jp nstr_wr
        ENT
        CART_ORG $8668
        jp nstr_wr.seg
        ENT

        CART_ORG $82D7          ; « dec (hl) » des vies ($6050) : sauf vies infinies
        rst $10
        ENT

; --- BIOS : écran d'options ----------------------------------------------------------------
        CART_ORG $81D6
        call game_opt
        ENT

; --- Manettes ------------------------------------------------------------------------------
        CART_ORG $80F4          ; mode manette
        nop
        nop
        ENT
        CART_ORG $8101          ; « in a,(c) / cpl » : directions + tir 1
        call joy_in
        ENT
        CART_ORG $811E          ; mode pavé
        nop
        nop
        ENT
        CART_ORG $8123          ; « in a,(c) / cpl » : tir 2
        call key_fire2
        ENT
        CART_ORG $8132          ; mode pavé
        nop
        nop
        ENT
        CART_ORG $8137          ; pavés des deux manettes
        call keypad_raw
        nop
        nop
        nop
        ENT

; --- Écritures sur le port $00 (reste d'une autre machine ; sans effet sur Coleco) ------------------
        CART_ORG $8562
        nop
        nop
        ENT
        CART_ORG $8566
        nop
        nop
        ENT
        CART_ORG $8571
        nop
        nop
        ENT
        CART_ORG $8574
        nop
        nop
        ENT

; --- Son --------------------------------------------------------------------------------------
        CART_ORG $B9A7          ; « out ($FF),a / ret »
        jp sn_write
        ENT
        CART_ORG $B9FD          ; « out ($FF),a / add hl,hl »
        call sn_write_addhl
        ENT
        CART_ORG $BA06          ; « out ($FF),a / ret »
        jp sn_write
        ENT
