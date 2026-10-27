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
ADKF_FAST     EQU $0100        ; débit disque : 1 = 2 us/bit (standard DD) ; 0 = 4 us/bit -> mauvais rythme = garbage
ADKF_MFMPREC  EQU $1000        ; MFM precompensation (mode lecture par défaut du KS1.3 officiel = $9100)
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
DSKB_CHANGE    EQU 2           ; /CHNG (0 = disque retiré/changé depuis le dernier pas)
PRB_SEL0_OFF   EQU $F7         ; SEL0=0 moteur=1 : sélectionne DF0 en latchant moteur OFF (lecture /CHNG)

; --- lecture de piste brute ---
TD_RAWWORDS  EQU $1900         ; mots lus = 6400 (12800 o, > une piste DD) ; tient dans un compteur dbra 16 bits
TD_RAWBYTES  EQU TD_RAWWORDS*2
TD_SECBODY   EQU 1080          ; octets MFM d'un secteur après ses syncs : en-tête 56 + données 1024
TD_ALLSECT   EQU $7FF          ; masque des 11 secteurs d'une piste
TD_FILLTRIES EQU 4             ; lectures d'une piste incomplète avant de rendre une erreur
TD_SYNC      EQU $4489         ; mot de synchro MFM standard Amiga (impossible dans du MFM normal -> 0 faux positif)

; TD_NO_DMA=1 (RED B2) : la lecture n'arme PAS le DMA disque (ni DMACON DSKEN ni DSKLEN start) -> le buffer
; MEMF_CLEAR reste à 0 -> aucun mot $4489 -> « M6U TRACKDISK READ OK » absent. Isole l'armement du DMA. Défaut 0.
TD_NO_DMA EQU 0

; --- décodage MFM (B3) ---
MFM_MASK      EQU $55555555   ; masque des bits de DONNÉES (les bits d'horloge MFM sont en $AAAAAAAA)
MFM_SECTSZ    EQU 512         ; octets de données décodées par secteur
MFM_NSECT     EQU 11          ; secteurs par piste (DD)
MFM_SECBUF    EQU MFM_SECTSZ*MFM_NSECT   ; 5632 : buffer des secteurs décodés (indexés par numéro logique) = octets/piste
; --- géométrie DD (M6z : CMD_READ multi-piste) ---
TD_NTRACKS    EQU 160                    ; 80 cylindres x 2 faces (pistes 0..159)
TD_DISKBYTES  EQU TD_NTRACKS*MFM_SECBUF  ; 901120 : taille totale du disque DD (garde de borne CMD_READ)
; offsets dans un secteur MFM depuis info_odd (format public Amiga/ADF-FAQ ; verrouillé par round-trip Python) :
;   +0 info(odd,even,2 longs) +8 label(4 odd+4 even,8 longs) +40 hdrchk(odd,even) +48 datachk(odd,even)
;   +56 data_odd(128 longs=512o) +568 data_even(128 longs=512o) ; fin du secteur à +1080
; MFM_BAD_DECODE=1 (RED B3) : saute le <<1 du combine des DATA -> données décodées fausses -> secteur 0 != « DOS\0 »
; -> « M6V TRACKDISK DECODE OK » absent (les checksums, calculés sur le MFM BRUT, passent quand même -> isole
; spécifiquement la correction du décodage des données). Défaut 0.
MFM_BAD_DECODE EQU 0

; --- CMD_READ (B4) : BeginIO device ---
CMD_READ      EQU 2            ; commande standard de lecture (io.i : INVALID=0, RESET=1, READ=2)
IO_ACTUAL     EQU 32           ; IOStdReq : octets réellement transférés
IO_LENGTH     EQU 36           ; octets demandés
IO_DATA       EQU 40           ; APTR buffer destination
IO_OFFSET     EQU 44           ; offset octet sur le disque (secteur logique * 512)
TDERR_NotSpec EQU 20           ; erreur trackdisk générique (trackdisk.i : TDERR_NotSpecified)
TDERR_WriteProt EQU 28         ; disquette protégée en écriture
CMD_RESET     EQU 1
CMD_WRITE     EQU 3
CMD_UPDATE    EQU 4
CMD_CLEAR     EQU 5
CMD_STOP      EQU 6
CMD_START     EQU 7
CMD_FLUSH     EQU 8
TD_MOTOR      EQU 9
TD_SEEK       EQU 10
TD_FORMAT     EQU 11
TD_REMOVE     EQU 12
TD_CHANGENUM  EQU 13
TD_CHANGESTATE EQU 14
TD_PROTSTATUS EQU 15
TD_GETNUMTRACKS EQU 19
TD_ADDCHANGEINT EQU 20
TD_REMCHANGEINT EQU 21
DSKB_PROT     EQU 3            ; CIA-A PRA : /WPRO (0 = disquette protégée)
ADKF_PRECOMP140 EQU $2000      ; précompensation 140 ns (pistes >= TD_PCTRACK)
TD_PCTRACK    EQU 81             ; première piste (cylindre*2 + face) écrite avec précompensation (spec trackdisk-write-v34)
; écriture d'une piste (spec trackdisk-write-v34 §2) : garde de 1660 octets en tête, 11 secteurs de 1088 octets MFM
; (préambule, sync, en-tête, label, sommes, données), mot de queue : 6815 mots, ~218 ms. La piste dépasse nettement un
; tour : la fin recouvre la garde, jamais un secteur, même sur un lecteur lent (~+4 %) ; aucun reste de l'ancienne piste.
TD_WRGAP      EQU 1660
TD_SECRAW     EQU 1088
TD_WRTAIL     EQU $AAA8          ; mot de queue après le dernier secteur
TD_WRBYTES    EQU TD_WRGAP+MFM_NSECT*TD_SECRAW+2
TD_WRWORDS    EQU TD_WRBYTES/2
; TD_READ_NOCMD=1 (RED B4) : BeginIO ne reconnaît PAS CMD_READ (retombe sur IOERR_NOCMD) -> io_Data reste à 0 ->
; secteur lu != « DOS\0 » -> « M6W TRACKDISK CMD_READ OK » absent. Isole le handler de commande. Défaut 0.
TD_READ_NOCMD EQU 0

; SEEK_NOSTEP=1 (RED B2b) : td_read_track saute le step-in -> la tête reste à la piste 0 -> lire la piste 2 renvoie
; en fait la piste 0 -> le n° de piste décodé != 2 -> « M6X TRACKDISK SEEK OK » absent. Isole le seek. Défaut 0.
SEEK_NOSTEP EQU 0

; TD_NO_CYLTRACK=1 (RED cylinder-tracking) : force la recalibration (step OUT jusqu'à DSKTRACK0) à CHAQUE lecture
; au lieu de stepper le delta depuis TD_CURCYL -> lectures LENTES (ancien comportement C). Correct mais lent :
; sous l'ordonnanceur, le boot disquette complet ne tient plus dans WAIT=90 -> « D3B HANDLER OK » absent à ce WAIT.
; Isole le GAIN de vitesse du cylinder-tracking (discriminant = D3B présent à WAIT serré). Défaut 0.
TD_NO_CYLTRACK EQU 0

; TD_NOSEEK=1 (RED M6z) : BeginIO CMD_READ ignore la composante PISTE de l'offset et lit TOUJOURS la piste 0 (le
; secteur-dans-piste et l'octet-dans-piste restent corrects -> la lecture aboutit, pas de hors-borne). Une lecture
; du root block (bloc 880 = piste 80) renvoie alors la piste 0 (bootblock) -> « DOS\0 » != T_SHORT ; une lecture
; spanning renvoie des secteurs de la piste 0 -> marqueurs faux -> « M6Z ... OK » absent. Isole le mapping
; offset->piste SANS crash (discipline RED M6D_BAD_BPTR : la lecture aboutit, c'est la comparaison qui échoue). Défaut 0.
TD_NOSEEK EQU 0
