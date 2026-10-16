; src/exec/trackdisk.s — trackdisk.device (B1 : squelette résident + validation d'unité).
; 2e DEVICE du projet (après timer.device). ROMTag RTF_AUTOINIT (pri 20) -> chemin AUTOINIT de InitResident
; (MakeLibrary + Enqueue DeviceList). Quirk V34 : data table pose LN_TYPE + LIB_VERSION, init func pose LN_NAME.
;
; B1 livre : le device EXISTE + valide ses unités (DF0-3). La LECTURE réelle (contrôle drive CIA, disk DMA Paula,
; décodage MFM, CMD_READ) vient aux incréments B2/B3/B4. Open(unité 0-3) -> succès ; unité >= 4 -> échec (convention
; OpenDevice : io_Error != 0, io_Device = 0). Les « unités » B1 sont des PLACEHOLDERS (aire réservée par unité) :
; une vraie unité trackdisk commence par un MsgPort (file des IORequests que BeginIO mettra en queue) -> en B2 cette
; aire deviendra une struct Unit + MsgPort. L'invariant verrouillé par la preuve M6T = « io_Unit pointe l'aire de
; l'unité d0 », PAS sa taille/son contenu (qui changeront).
;
; Piste IMPLÉMENTATION (« clean ») : AutoDocs trackdisk.device + exec + devices/trackdisk.i (public). AUCUNE lecture ROM.

                include "exec.i"
                include "disk.i"

                xdef    td_read_track0
                xdef    td_read_track
                xdef    td_decode_track

; --- constantes trackdisk (devices/trackdisk.i) + erreurs exec io (io.i) ---
NUMUNITS       EQU 4                 ; DF0..DF3
IOERR_OPENFAIL EQU -1                ; OpenDevice a échoué
IOERR_NOCMD    EQU -3                ; commande non supportée
TDU_UNIT0      EQU LIB_SIZE          ; 34 : début de l'aire des unités (placeholder, -> Unit+MsgPort en B2)
TDU_UNITSZ     EQU 8                 ; octets par unité (placeholder)
TDBASE_SIZE    EQU TDU_UNIT0+NUMUNITS*TDU_UNITSZ   ; 66 : Library + 4 aires d'unité

; TD_NO_UNITCHECK=1 (RED) : Open saute la validation du numéro d'unité -> l'unité 4 (invalide) ouvre à tort ->
; la preuve « unité 4 échoue » casse -> « M6T TRACKDISK OK » absent. Isole la validation d'unité. Défaut 0.
TD_NO_UNITCHECK EQU 0

; --- ROMTag trackdisk.device (scanné par build_reslist) ---
        EVEN
trackdisk_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    trackdisk_romtag     ; RT_MATCHTAG = self
        dc.l    trackdisk_end        ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT,34,NT_DEVICE,20   ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (20 : place roadmap trackdisk)
        dc.l    trackdisk_name       ; RT_NAME
        dc.l    trackdisk_name       ; RT_IDSTRING
        dc.l    trackdisk_inittab    ; RT_INIT -> table AUTOINIT
trackdisk_name:
        dc.b    "trackdisk.device",0
        EVEN
trackdisk_inittab:
        dc.l    TDBASE_SIZE          ; dataSize (Library + aires d'unité placeholder)
        dc.l    trackdisk_vectors    ; funcTable
        dc.l    trackdisk_datatab    ; dataTable (InitStruct)
        dc.l    trackdisk_initfunc   ; initFunc
trackdisk_vectors:                   ; table ABSOLUE, ordre device standard, terminée par -1
        dc.l    trackdisk_open       ; LVO -6
        dc.l    trackdisk_close      ; LVO -12
        dc.l    trackdisk_expunge    ; LVO -18
        dc.l    trackdisk_null       ; LVO -24 (réservé)
        dc.l    trackdisk_beginio    ; LVO -30
        dc.l    trackdisk_abortio    ; LVO -36
        dc.l    -1
trackdisk_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)  ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34          ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(device a6, iorequest a1, unit d0, flags d1) : valide le numéro d'unité (DF0-3). Succès -> io_Unit = aire de
; l'unité, io_Device = base, io_Error = 0, OpenCnt++. Unité >= NUMUNITS -> échec (io_Error, io_Device = 0).
trackdisk_open:
                ifeq    TD_NO_UNITCHECK
        cmp.l   #NUMUNITS,d0
        bcc.s   .td_badunit          ; unité >= 4 (comparaison non signée) -> OpenDevice échoue
                endc
        move.l  d0,d1                ; d1 = unité (flags plus nécessaires)
        lsl.l   #3,d1                ; unité * TDU_UNITSZ (8)
        lea     TDU_UNIT0(a6),a0
        add.l   d1,a0                ; a0 = &unit[unité]
        move.l  a0,IO_UNIT(a1)
        move.l  a6,IO_DEVICE(a1)     ; OpenDevice confirme le device dans la requête
        clr.b   IO_ERROR(a1)
        addq.w  #1,LIB_OPENCNT(a6)
        rts
.td_badunit:
        move.b  #IOERR_OPENFAIL,IO_ERROR(a1)
        clr.l   IO_DEVICE(a1)        ; io_Device = 0 -> OpenDevice a échoué (convention exec)
        rts

trackdisk_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
trackdisk_expunge:
        moveq   #0,d0                ; pas d'expunge ce milestone (base résidente)
        rts
trackdisk_null:
        moveq   #0,d0
        rts

; BeginIO(device a6, iorequest a1) : B4 — traite CMD_READ (lecture de secteurs logiques via td_read_track0 +
; td_decode_track, copie vers io_Data). Autres commandes -> IOERR_NOCMD. ReplyMsg si la requête n'est PAS quick
; (garde-fou B1 tenu : sinon DoIO attend pour toujours). Limité à la piste 0 (offset+length <= 11*512) tant que
; le step/seek (B2b) n'existe pas. a6 = device base en entrée/sortie.
trackdisk_beginio:
        movem.l d2-d5/a2-a4,-(sp)
        move.l  a1,a2                ; a2 = ioreq
        clr.l   IO_ACTUAL(a2)
                ifeq    TD_READ_NOCMD
        cmp.w   #CMD_READ,IO_COMMAND(a2)
        beq.s   .td_read
                endc                 ; RED TD_READ_NOCMD : saute la reconnaissance -> IOERR_NOCMD
        move.b  #IOERR_NOCMD,IO_ERROR(a2)
        bra     .td_reply
.td_read:
        move.l  a6,a4                ; a4 = device base (sauvé ; a6 -> SysBase pour les appels exec)
        move.l  ($4).w,a6
        bsr     td_read_track0       ; d0 = rawbuf chip | 0
        move.l  d0,d3
        bne.s   .td_haveraw
        move.b  #TDERR_NotSpec,IO_ERROR(a2)   ; pas de disque / lecture KO
        bra     .td_restore
.td_haveraw:
        move.l  #512*11,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,d4                ; d4 = sectorbuf
        bne.s   .td_havebuf
        move.l  d3,a1                ; plus de RAM -> libère rawbuf
        move.l  #$1900*2,d0
        jsr     LVO_FREEMEM(a6)
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
        bra     .td_restore
.td_havebuf:
        move.l  d3,a0
        move.l  d4,a1
        bsr     td_decode_track      ; décode la piste (secteurs rangés par n°)
        move.l  IO_OFFSET(a2),d5     ; offset octet
        move.l  IO_LENGTH(a2),d2     ; longueur octet
        move.l  d5,d0
        add.l   d2,d0
        cmp.l   #512*11,d0           ; offset+length dans la piste 0 ?
        bhi     .td_badrange         ; hors piste 0 (seek = B2b) -> erreur
        move.l  d4,a0
        add.l   d5,a0                ; src = sectorbuf + offset
        move.l  IO_DATA(a2),a1       ; dest = io_Data
        move.l  d2,d0
        lsr.l   #2,d0                ; octets -> longs (length multiple de 512)
        beq.s   .td_copied
        subq.l  #1,d0
.td_copy:
        move.l  (a0)+,(a1)+
        dbra    d0,.td_copy
.td_copied:
        move.l  d2,IO_ACTUAL(a2)     ; octets transférés
        clr.b   IO_ERROR(a2)
        bra     .td_freebufs
.td_badrange:
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
.td_freebufs:
        move.l  d4,a1                ; libère sectorbuf
        move.l  #512*11,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d3,a1                ; libère rawbuf
        move.l  #$1900*2,d0
        jsr     LVO_FREEMEM(a6)
.td_restore:
        move.l  a4,a6                ; restaure a6 = device base
.td_reply:
        btst    #0,IO_FLAGS(a2)      ; IOF_QUICK (bit 0) ?
        bne.s   .td_bdone
        move.l  a6,-(sp)             ; non quick -> ReplyMsg(ioreq)
        move.l  ($4).w,a6
        move.l  a2,a1
        jsr     LVO_REPLYMSG(a6)
        move.l  (sp)+,a6
.td_bdone:
        movem.l (sp)+,d2-d5/a2-a4
        rts
trackdisk_abortio:
        moveq   #0,d0
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Pose le nom (quirk V34). Les aires d'unité placeholder
; ne nécessitent pas d'init en B1 (deviendront Unit+MsgPort à initialiser en B2).
trackdisk_initfunc:
        move.l  d0,a1
        lea     trackdisk_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts

; td_read_track0(a6=SysBase) -> d0 = buffer chip (piste MFM brute) | 0 (timeout / pas de disque). B2 MINIMAL :
; DDRB=$FF (suspect n°1 : sans ça PRB ne pilote rien) ; moteur-on + select DF0 (latch moteur via front SEL0) ;
; spin-up (busy-loop + poll DSKRDY avec timeout, poursuit) ; seek (recalibration cyl 0 + step-in + side) ;
; DMA WORDSYNC d'une piste ; poll INTREQR DSKBLK avec timeout (jamais de hang).
; N'écrit QUE CIA-B PRB/DDRB (ports) -> les timers CIA-B (unité MICROHZ/M7a) ne sont pas touchés.
; B2b : td_read_track(d0 = n° de piste) seek d'abord vers la piste ; td_read_track0 = lit la piste 0 (wrapper pour
; les appelants existants : M6U/M6V, BeginIO). piste = cylindre*2 + face. C : la recalibration est TOUJOURS faite
; (lecture depuis une position connue) -> td_read_track0 lit la piste 0 correctement même après un seek précédent.
td_read_track0:
        moveq   #0,d0                 ; piste 0
td_read_track:
        movem.l d2/d3/d6/a2,-(sp)
        move.l  d0,d6                 ; d6 = piste cible
        move.l  #TD_RAWBYTES,d0       ; buffer piste brute en chip RAM (le DMA ne lit QUE la chip)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .rd_ret               ; pas de chip -> 0
        move.l  d0,a2                 ; a2 = buffer
        move.w  #INTF_DSKBLK,INTENA   ; s'assure que DSKBLK est MASQUÉ (on poll INTREQR, pas d'IRQ INT1 spurious)
        move.b  #$FF,CIAB_DDRB        ; port B = SORTIES avant d'écrire PRB
        move.b  #PRB_MOTOR_ON,CIAB_PRB ; moteur on (intention), tout déselectionné
        move.b  #PRB_SEL0_ON,CIAB_PRB  ; select DF0 -> le front SEL0 latche moteur=on
        move.l  #$00040000,d2         ; spin-up : busy-loop + poll DSKRDY (timeout = lecteur absent/vide)
.rd_spin:
        btst    #DSKB_RDY,CIAA_PRA_HW ; DSKRDY = 0 quand prêt
        beq.s   .rd_seek
        subq.l  #1,d2
        bne.s   .rd_spin
        ; timeout DSKRDY : aucun disque prêt (lecteur absent ou vide) -> inutile de recalibrer (85x) et d'armer le
        ; DMA (tout timeouterait) ; moteur off + libère le buffer + renvoie 0. Rend le probe « sans disque » rapide.
        ; ⚠️ DETTE vraie-A500 (C) : ce gate est désormais PORTEUR (avant B2 : timeout -> on continuait, le sync DMA
        ; était le signal de présence). Nouvelle hypothèse : un disque lisible asserte DSKRDY dans la fenêtre du
        ; timeout spin-up. CONFIRMÉ sous FS-UAE, mais la marge timeout(accès CIA, ~2us/it) vs spin-up moteur MÉCANIQUE
        ; (~0,3-0,5 s) n'est PAS vérifiée sur vrai lecteur -> un DSKRDY lent pourrait rejeter un disque valide (M7).
        move.b  #PRB_OFF,CIAB_PRB
        move.l  a2,a1
        move.l  #TD_RAWBYTES,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        bra     .rd_ret
.rd_seek:
        ; --- seek vers la piste d6 : recalibration cylindre 0 (step OUT jusqu'à DSKTRACK0) + step IN + side-select ---
        ; Recalibration TOUJOURS effectuée (y compris piste 0) : on lit toujours depuis une position CONNUE, quelle
        ; que soit la position laissée par une lecture précédente (ex. le strap lit la piste 0 APRÈS que M6X ait
        ; seeké au cylindre 1 — sans recalibration on lirait la mauvaise piste SILENCIEUSEMENT). C'est le « vrai
        ; fix » promis en C : correctness > performance (un vrai lecteur mémoriserait le cylindre courant et
        ; stepperait le delta ; on recalibre à chaque lecture — correct, juste plus lent). Le cap 85 évite un
        ; busy-loop infini SANS lecteur (DSKTRACK0 jamais asserté). Polarités DSKDIREC/DSKSIDE validées par M6X.
        move.w  #85,d2               ; cap de recalibration (évite de steper à l'infini si polarité fausse / pas de lecteur)
.rd_recal:
        btst    #DSKB_TRACK0,CIAA_PRA_HW   ; tête sur la piste 0 ?
        beq.s   .rd_seekin
        move.b  #$77,CIAB_PRB        ; direc OUT (bit1=1), step=1
        move.b  #$76,CIAB_PRB        ; step=0 : le front descendant déclenche un pas
        move.b  #$77,CIAB_PRB        ; step=1
        bsr     .rd_settle
        dbra    d2,.rd_recal
.rd_seekin:
                ifeq    SEEK_NOSTEP
        move.w  d6,d2
        lsr.w   #1,d2               ; cylindre cible = piste / 2
        beq.s   .rd_side
.rd_stepin:
        move.b  #$75,CIAB_PRB       ; direc IN (bit1=0), step=1
        move.b  #$74,CIAB_PRB       ; step=0 : pas vers l'intérieur
        move.b  #$75,CIAB_PRB       ; step=1
        bsr     .rd_settle
        subq.w  #1,d2
        bne.s   .rd_stepin
                endc                ; RED SEEK_NOSTEP : pas de step-in -> reste à la piste 0
.rd_side:
        move.b  #$77,CIAB_PRB       ; face 0 (DSKSIDE=1, bit2=1 ; piste paire)
        btst    #0,d6
        beq.s   .rd_dma
        move.b  #$73,CIAB_PRB       ; face 1 (DSKSIDE=0, bit2=0 ; piste impaire)
.rd_dma:
        move.w  #INTF_DSKBLK,INTREQ   ; clear DSKBLK pendant
        move.w  #$7FFF,ADKCON         ; clear tous les bits ADKCON
                ifeq    TD_NO_DMA
        move.w  #(ADKF_SETCLR|ADKF_WORDSYNC),ADKCON   ; $8400 : SETCLR | WORDSYNC (DD, FAST=0)
        move.w  #TD_SYNC,DSKSYNC      ; $4489
        move.l  a2,DSKPT             ; pointeur DMA = buffer (longword)
        move.w  #$4000,DSKLEN        ; reset/disable (quirk avant armement)
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_DISK),DMACON  ; $8210 : DMA maître + disque
        move.w  #($8000|TD_RAWWORDS),DSKLEN   ; arme la lecture (DMAEN|len)
        move.w  #($8000|TD_RAWWORDS),DSKLEN   ; écrit 2x pour démarrer (quirk hardware)
                endc                 ; RED TD_NO_DMA : DMA non armé -> buffer reste à 0 -> aucun sync
        move.l  #$00080000,d2        ; poll DSKBLK avec timeout (jamais de hang si pas de disque)
.rd_wait:
        move.w  INTREQR,d3
        btst    #1,d3                ; DSKBLK (bit 1) ?
        bne.s   .rd_done
        subq.l  #1,d2
        bne.s   .rd_wait
        bsr.s   .rd_stop             ; timeout -> libère le buffer, renvoie 0
        move.l  a2,a1
        move.l  #TD_RAWBYTES,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        bra.s   .rd_ret
.rd_done:
        bsr.s   .rd_stop
        move.l  a2,d0                ; d0 = buffer (succès)
.rd_ret:
        movem.l (sp)+,d2/d3/d6/a2
        rts
.rd_stop:
        move.w  #$4000,DSKLEN        ; disable DMA disque
        move.w  #DMAF_DISK,DMACON    ; coupe SEULEMENT DSKEN (SETCLR=0 -> clear ; NE PAS toucher MASTER = affichage)
        move.w  #INTF_DSKBLK,INTREQ  ; clear DSKBLK
        move.b  #PRB_OFF,CIAB_PRB    ; moteur off + déselect
        rts
.rd_settle:
        move.l  #$00008000,d3        ; délai de stabilisation du pas (settle ; préserve d2 = compteur de pas)
.rd_sloop:
        subq.l  #1,d3
        bne.s   .rd_sloop
        rts

; td_decode_track(rawbuf a0, sectorbuf a1) -> d0 = nombre de secteurs décodés+vérifiés (checksums en-tête ET data OK).
; Scanne la piste brute à la recherche des syncs $4489 ; pour chaque secteur : décode info (combine odd/even),
; vérifie format=$FF et numéro de secteur < 11, vérifie le checksum en-tête (XOR des 10 longs MFM info+label & MASK
; == checksum stocké décodé) et le checksum data (XOR des 256 longs MFM data & MASK), puis décode les 512 o de
; données vers sectorbuf + numéro*512. Format verrouillé par round-trip Python. a6 non utilisé.
td_decode_track:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a4                ; a4 = base sectorbuf
        lea     (TD_RAWBYTES-1200)(a0),a2  ; a2 = fin de scan (laisse 1200 o pour le dernier secteur)
        moveq   #0,d7                ; d7 = compteur de secteurs valides
        moveq   #0,d5                ; d5 = n° de piste du dernier secteur valide (renvoyé en d1 -> oracle seek B2b)
.sc_loop:
        cmp.l   a2,a0
        bcc     .sc_done             ; p >= fin -> terminé
        cmp.w   #$4489,(a0)
        bne     .sc_adv              ; pas un sync -> avance de 2
.sc_skipsync:
        addq.l  #2,a0                ; saute les $4489 consécutifs (2 mots de sync)
        cmp.w   #$4489,(a0)
        beq.s   .sc_skipsync
        move.l  a0,a3                ; a3 = en-tête du secteur (info_odd)
        ; décode info = combine(info_odd, info_even)
        move.l  (a3),d0
        and.l   #MFM_MASK,d0
        add.l   d0,d0                ; <<1
        move.l  4(a3),d1
        and.l   #MFM_MASK,d1
        or.l    d1,d0                ; d0 = info décodé
        move.l  d0,d4                ; d4 = info (survit aux boucles checksum ; sert au n° de piste si valide)
        move.l  d0,d1
        rol.l   #8,d1
        cmp.b   #$FF,d1              ; format == $FF ?
        bne     .sc_adv
        move.l  d0,d6
        lsr.l   #8,d6
        and.l   #$FF,d6              ; d6 = numéro de secteur
        cmp.l   #MFM_NSECT,d6
        bcc     .sc_adv              ; secteur >= 11 -> ignore
        ; checksum en-tête : XOR des 10 longs (info+label) & MASK
        moveq   #0,d2
        move.l  a3,a5
        moveq   #10-1,d1
.sc_hc:
        move.l  (a5)+,d3
        eor.l   d3,d2
        dbra    d1,.sc_hc
        and.l   #MFM_MASK,d2         ; d2 = checksum en-tête calculé
        move.l  40(a3),d0            ; stocké décodé = combine(hdrchk_odd, hdrchk_even)
        and.l   #MFM_MASK,d0
        add.l   d0,d0
        move.l  44(a3),d1
        and.l   #MFM_MASK,d1
        or.l    d1,d0
        cmp.l   d2,d0
        bne     .sc_adv              ; checksum en-tête invalide -> ignore
        ; checksum data : XOR des 256 longs (data odd+even) & MASK
        moveq   #0,d2
        lea     56(a3),a5
        move.w  #256-1,d1
.sc_dc:
        move.l  (a5)+,d3
        eor.l   d3,d2
        dbra    d1,.sc_dc
        and.l   #MFM_MASK,d2         ; d2 = checksum data calculé
        move.l  48(a3),d0           ; stocké décodé = combine(datachk_odd, datachk_even)
        and.l   #MFM_MASK,d0
        add.l   d0,d0
        move.l  52(a3),d1
        and.l   #MFM_MASK,d1
        or.l    d1,d0
        cmp.l   d2,d0
        bne     .sc_adv              ; checksum data invalide -> ignore
        ; décode les 512 o de data (128 longs) vers sectorbuf + secteur*512
        move.l  a0,-(sp)            ; sauve le pointeur de scan (a0 réutilisé comme walker even)
        move.l  d6,d0
        lsl.l   #8,d0               ; secteur * 256
        add.l   d0,d0               ; * 2 -> secteur * 512 (lsl #9 interdit : max #8)
        move.l  a4,a1
        add.l   d0,a1               ; a1 = destination
        lea     56(a3),a5          ; a5 = data_odd[0]
        lea     (56+512)(a3),a0    ; a0 = data_even[0]
        move.w  #128-1,d1
.sc_data:
        move.l  (a5)+,d0
        and.l   #MFM_MASK,d0
                ifeq    MFM_BAD_DECODE
        add.l   d0,d0               ; <<1 (combine correct)
                endc                ; RED MFM_BAD_DECODE : saute le <<1 -> données fausses -> secteur 0 != "DOS\0"
        move.l  (a0)+,d3
        and.l   #MFM_MASK,d3
        or.l    d3,d0
        move.l  d0,(a1)+
        dbra    d1,.sc_data
        move.l  (sp)+,a0            ; restaure le pointeur de scan
        addq.l  #1,d7              ; secteur valide
        move.l  d4,d5              ; n° de piste de ce secteur = (info>>16)&$FF
        swap    d5
        and.l   #$FF,d5            ; d5 = track (oracle du seek : doit valoir la piste demandée)
        lea     1080(a3),a0        ; saute ce secteur (header 56 + data 1024) -> scan vers le sync suivant
        bra     .sc_loop
.sc_adv:
        addq.l  #2,a0
        bra     .sc_loop
.sc_done:
        move.l  d7,d0              ; d0 = nombre de secteurs valides
        move.l  d5,d1              ; d1 = n° de piste (du dernier secteur valide) -> oracle du seek B2b
        movem.l (sp)+,d2-d7/a2-a5
        rts
trackdisk_end:
