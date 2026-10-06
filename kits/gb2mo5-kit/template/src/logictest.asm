; Test de la logique traduite seule (tools/diff_mo5.py) : pas d'affichage.
        include "defs.asm"
        include "vars.asm"
        org $2600
        setdp DPAGE
logic_start
        include "gb_support.asm"
        include "../gb/gb_logic.asm"
logic_end
