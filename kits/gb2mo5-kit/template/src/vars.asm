; ===========================================================================
; vars.asm - variables en RAM (adresses fixes : rien n'est chargé ici)
; Page directe ($9F06-$9F7F) : variables les plus utilisées.
; Zone de travail $9400-$9BFF : objets, images décalées, cases à redessiner.
; ===========================================================================
tick_sp     equ $9F06           ; (2) pile au début de gb_tick
sfx_req     equ $9F08           ; son demandé par la logique
match_over  equ $9F09
sets        equ $9F0A           ; 1 ou 3 sets
two_buttons equ $9F0B           ; 0 = 1 bouton (lob automatique), 1 = 2 boutons
fire_mode   equ $9F0C
frames      equ $9F0D           ; trames de 50 Hz écoulées
last_frame  equ $9F0E
ticks_due   equ $9F0F
tick_phase  equ $9F10
pad_now     equ $9F11
key_now     equ $9F12           ; chiffre 1-4 appuyé ($FF : aucun)
pj_b        equ $9F13           ; projection
pj_c        equ $9F14
pj_x        equ $9F15
pj_dy       equ $9F16
pj_t        equ $9F17
pj_sq       equ $9F18           ; (2)
menu_sel    equ $9F1A
menu_prev   equ $9F1B
key_prev    equ $9F1C
elapsed     equ $9F1D
tmp         equ $9F1E           ; (2)
; recomposition d'une case
cp_r        equ $9F20           ; rangée (0-24)
cp_c        equ $9F21           ; colonne du stade (0-31)
cp_row8     equ $9F22           ; (2) première ligne de la case (y écran)
cp_n        equ $9F24           ; lignes à fusionner
cp_colhi    equ $9F25           ; couleur de l'objet << 4
cp_stride   equ $9F26           ; (2) octets par ligne de l'image décalée (2 x nb)
cp_nb       equ $9F28           ; octets par ligne et par plan
dl_n        equ $9F29           ; cases dans la liste
sh_s        equ $9F2A           ; décalage (0-7)
sh_mul      equ $9F2B           ; 2^(8 - décalage)
sh_prev     equ $9F2C
sh_cnt      equ $9F2D
sh_rows     equ $9F2E
sh_wb       equ $9F2F
fbuf        equ $9F30           ; (8) forme de la case
cbuf        equ $9F38           ; (8) couleur de la case (= fbuf + 8)
txt_col     equ $9F40           ; texte : colonne (0-39)
txt_row     equ $9F41           ;         rangée (0-24)
txt_color   equ $9F42           ;         couleur (encre << 4 | fond)
shown_score equ $9F43           ; (8)
shown_ann   equ $9F4B
sfx_t       equ $9F4C           ; son en cours : demi-périodes restantes
sfx_p       equ $9F4D           ;                 demi-période (unités de boucle)
sfx_bit     equ $9F4E           ; état du buzzer
lag_count   equ $9F50           ; (2)
total_count equ $9F52           ; (2)
bot_cool    equ $9F54
bot_serve   equ $9F55
mk_x0       equ $9F56           ; marquage d'un rectangle de cases
mk_x1       equ $9F57
mk_y0       equ $9F58
mk_y1       equ $9F59
mk_c        equ $9F5A
ob_idx      equ $9F5B

; --- Objets (32 octets chacun) -------------------------------------------------
OBJS        equ $9400
OBJ_SIZE    equ 32
NOBJ        equ 5
O_VIS       equ 0               ; visible
O_IMG       equ 1
O_X         equ 2               ; (2) x du coin haut-gauche (pixels du stade, signé)
O_Y         equ 4               ; (2) y (lignes d'écran, signé)
O_COL       equ 6               ; couleur << 4
O_NB        equ 7               ; octets par ligne et par plan de l'image décalée
O_H         equ 8               ; hauteur
O_BUF       equ 9               ; (2) image décalée
O_BX0       equ 11              ; colonne (du stade) du 1er octet de l'image décalée (signée)
O_CX0       equ 12              ; cases couvertes (rectangle limité au stade)
O_CX1       equ 13
O_CY0       equ 14
O_CY1       equ 15
O_OVIS      equ 16              ; état affiché
O_OIMG      equ 17
O_OX        equ 18              ; (2)
O_OY        equ 20              ; (2)
O_OCX0      equ 22
O_OCX1      equ 23
O_OCY0      equ 24
O_OCY1      equ 25
O_SHIFT     equ 26              ; décalage de l'image décalée ($FF : à refaire)
O_BUFSZ     equ 27

SHBUF       equ $9500           ; images décalées : 256 octets par joueur, 64 sinon
DIRTY       equ $9800           ; 32 x 25 : case à redessiner
DLIST       equ $9B20           ; liste des cases (rangée, colonne), 112 au plus
DLIST_MAX   equ 112

; --- Page directe (suite) ---------------------------------------------------------
m_k0        equ $9F5C           ; fusion : 1re ligne de la case
m_srow      equ $9F5D           ;          1re ligne de l'image
n_vis       equ $9F5E           ; nouvel état d'un objet
n_img       equ $9F5F
n_x         equ $9F60           ; (2)
n_y         equ $9F62           ; (2)
n_ptr       equ $9F64           ; (2) image (en-tête)
pj_ax       equ $9F66           ; (2) point d'ancrage : x GB
pj_ay       equ $9F68           ; (2)                  y GB
spr_dir     equ $9F6A
pia_a       equ $9F6B
prev_init   equ $9F6D           ; dernier état du bit « image » de $A7E7
pj_y        equ $9F6C
