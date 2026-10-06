; ===========================================================================
; vars.asm - variables en RAM (1 Ko en tout, partagé avec la RAM GB)
; Toute la RAM est mise à zéro au démarrage.
; ===========================================================================

MAX_JOBS    equ 8
SAT_MAX     equ 19              ; balle, ombre, marque, 2 x 8 (joueurs)

        ORG $7100               ; partie 1 : $7100-$717F (HRAM GB ensuite)
frames:         ds 1            ; trames écoulées (NMI)
vdp_free:       ds 1            ; VDP_FREE : la NMI peut utiliser le VDP
frame_ready:    ds 1            ; 1 : sat_buf, up_img, jobs prêts pour la NMI
wn_last:        ds 1
last_frame:     ds 1
ticks_due:      ds 1
pad_now:        ds 1
tick_sp:        ds 2
sfx_req:        ds 1
match_over:     ds 1
two_buttons:    ds 1            ; 0 = 1 bouton (lob automatique), 1 = 2 boutons
sets:           ds 1            ; 1 ou 3 sets
fire_mode:      ds 1
cur_img:        ds 5            ; image affichée de chaque objet ($FE : aucune)
up_img:         ds 5            ; image dont les motifs sont à recopier ($FF : rien)
sat_len:        ds 1            ; octets de sat_buf à envoyer (0 : rien)
sat_ptr:        ds 2
spr_dir:        ds 1
po_obj:         ds 1
po_n:           ds 1
po_k:           ds 1
po_pat:         ds 1
po_base:        ds 2
po_x:           ds 2
po_y:           ds 2
ps_x:           ds 1
ps_y:           ds 1
ps_ec:          ds 1
pj_b:           ds 1            ; b : lu par lift ($FFCD dans la ROM)
pj_c:           ds 1
job_n:          ds 1
sb_ptr:         ds 2
shown_score:    ds 8
shown_ann:      ds 1
sfx_vol:        ds 2            ; son : volume (voie son, bruit)
sfx_decay:      ds 2
sfx_frac:       ds 2
menu_sel:       ds 1
menu_prev:      ds 1
key_prev:       ds 1
key_now:        ds 1            ; touche du pavé (0-9, 10 *, 11 #, $FF aucune)
lag_count:      ds 2
total_count:    ds 2
bot_cool:       ds 1
bot_serve:      ds 1
vars1_end:
        ASSERT vars1_end <= $7180, "variables (partie 1) : trop grandes"

        ORG $7201               ; partie 2 : après l'octet de son GB ($7200)
jobs:           ds 5 * MAX_JOBS ; textes : adresse VRAM, source, longueur
sat_buf:        ds 4 * SAT_MAX + 1
score_buf:      ds 5 * 7        ; cadre du score : 5 rangées x 7 colonnes
ann_buf:        ds 16           ; annonces : rangée 1, colonnes 8-23
menu_buf:       ds 6            ; menu : 3 curseurs, 3 valeurs
vars2_end:
        ASSERT vars2_end <= STACK_TOP - 160, "variables (partie 2) : trop grandes (pile)"
