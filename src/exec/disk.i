; src/exec/disk.i — registres disque Paula/OCS + bits de contrôle drive (B2). Clean-room (HRM + NDK hardware/*).
; CUSTOM / CIAA_HW / CIAB_HW / DMACON / INTREQ / INTREQR sont définis dans exec.i (inclus AVANT ce fichier).

; --- registres disque custom (offsets depuis CUSTOM = $DFF000) ---
DSKPT    EQU CUSTOM+$020       ; pointeur DMA disque (longword, chip RAM)
DSKLEN   EQU CUSTOM+$024       ; longueur en MOTS | DMAEN(b15) | WRITE(b14)
DSKSYNC  EQU CUSTOM+$07E       ; mot de synchro recherché quand WORDSYNC actif
ADKCON   EQU CUSTOM+$09E       ; contrôle audio/disque (SETCLR|WORDSYNC...)
DSKBYTR  EQU CUSTOM+$01A       ; état octet disque (lecture)

; --- bits DMACON / ADKCON / INTREQ (dmabits.i, adkbits.i, intbits.i) ---
DMAF_DISK     EQU $0010        ; DMACON : canal DMA disque (DSKEN)
DMAF_MASTER   EQU $0200        ; DMA maître
DMAF_SETCLR   EQU $8000
ADKF_SETCLR   EQU $8000
ADKF_WORDSYNC EQU $0400        ; active la recherche du mot DSKSYNC par le DMA de lecture
ADKF_FAST     EQU $0100        ; 2 us/bit (à essayer si WORDSYNC seul ne synchronise pas)
INTF_DSKBLK   EQU $0002        ; INTREQ/INTREQR : fin du DMA bloc disque (niveau 1)

; --- CIA-B PRB (contrôle drive, $BFD100) — toutes les lignes sont ACTIVES BAS (0 = asserté) ---
CIAB_PRB      EQU CIAB_HW+$0100
CIAB_DDRB     EQU CIAB_HW+$0300
CIAF_DSKMOTOR EQU $80          ; moteur (0 = allumé)
CIAF_DSKSEL0  EQU $08          ; select DF0 (0 = sélectionné)
CIAF_DSKSIDE  EQU $04          ; face
CIAF_DSKDIREC EQU $02          ; direction de seek
CIAF_DSKSTEP  EQU $01          ; impulsion de pas
; valeurs PRB précalculées (B2 minimal) : tout haut sauf moteur / moteur+select
PRB_MOTOR_ON   EQU $7F         ; moteur=0 (on), SEL/side/dir/step=1 (déselectionné) — pose l'intention moteur
PRB_SEL0_ON    EQU $77         ; moteur=0, SEL0=0 (DF0) — le front SEL0 latche moteur=on
PRB_OFF        EQU $FF         ; tout haut : moteur off + déselectionné

; --- CIA-A PRA (statut drive, $BFE001) — ACTIF BAS ---
CIAA_PRA_HW    EQU CIAA_HW     ; = $BFE001
DSKB_RDY       EQU 5           ; DSKRDY (0 = prêt)
DSKB_TRACK0    EQU 4           ; DSKTRACK0 (0 = tête sur piste 0)

; --- lecture de piste brute ---
TD_RAWWORDS  EQU $1900         ; mots lus = 6400 (12800 o, > une piste DD) ; tient dans un compteur dbra 16 bits
TD_RAWBYTES  EQU TD_RAWWORDS*2
TD_SYNC      EQU $4489         ; mot de synchro MFM standard Amiga (impossible dans du MFM normal -> 0 faux positif)

; TD_NO_DMA=1 (RED B2) : la lecture n'arme PAS le DMA disque (ni DMACON DSKEN ni DSKLEN start) -> le buffer
; MEMF_CLEAR reste à 0 -> aucun mot $4489 -> « M6U TRACKDISK READ OK » absent. Isole l'armement du DMA. Défaut 0.
TD_NO_DMA EQU 0

; --- décodage MFM (B3) ---
MFM_MASK      EQU $55555555   ; masque des bits de DONNÉES (les bits d'horloge MFM sont en $AAAAAAAA)
MFM_SECTSZ    EQU 512         ; octets de données décodées par secteur
MFM_NSECT     EQU 11          ; secteurs par piste (DD)
MFM_SECBUF    EQU MFM_SECTSZ*MFM_NSECT   ; 5632 : buffer des secteurs décodés (indexés par numéro logique)
; offsets dans un secteur MFM depuis info_odd (format public Amiga/ADF-FAQ ; verrouillé par round-trip Python) :
;   +0 info(odd,even,2 longs) +8 label(4 odd+4 even,8 longs) +40 hdrchk(odd,even) +48 datachk(odd,even)
;   +56 data_odd(128 longs=512o) +568 data_even(128 longs=512o) ; fin du secteur à +1080
; MFM_BAD_DECODE=1 (RED B3) : saute le <<1 du combine des DATA -> données décodées fausses -> secteur 0 != « DOS\0 »
; -> « M6V TRACKDISK DECODE OK » absent (les checksums, calculés sur le MFM BRUT, passent quand même -> isole
; spécifiquement la correction du décodage des données). Défaut 0.
MFM_BAD_DECODE EQU 0
