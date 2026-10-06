; ===========================================================================
; zp.asm - page zéro : registres du Game Boy pour la logique traduite
; Paires rangées octet bas puis haut, pour servir de pointeurs (zL),y.
; ===========================================================================
zL      = $02           ; HL
zH      = $03
zC      = $04           ; BC
zB      = $05
zE      = $06           ; DE
zD      = $07
zA      = $08
zZ      = $09           ; indicateur Z du GB : Z <=> zZ = 0
zCY     = $0A           ; indicateur C du GB : bit 0
zT      = $0B           ; pointeur de travail (2 octets)
zW      = $0D           ; travail des routines de calcul (4 octets)
