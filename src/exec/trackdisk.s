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

; BeginIO(device a6, iorequest a1) : STUB B1 — aucune commande trackdisk implémentée (CMD_READ/TD_MOTOR... = B2+).
; ⚠️ COMPAT-AVANT : un vrai BeginIO sur une requête NON quick DOIT faire ReplyMsg, sinon un appelant qui fait DoIO
; attend pour toujours. Ici PERSONNE ne l'appelle (inerte) ; dès qu'un consommateur réel existera (strap CMD_READ,
; incrément C), CE STUB DEVRA ReplyMsg après avoir posé io_Error.
trackdisk_beginio:
        move.b  #IOERR_NOCMD,IO_ERROR(a1)
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
; spin-up (busy-loop + poll DSKRDY avec timeout, poursuit) ; DMA WORDSYNC d'une piste (position COURANTE de la
; tête = piste 0 au reset) ; poll INTREQR DSKBLK avec timeout (jamais de hang). PAS de step ni side-select
; (polarités non vérifiées -> incrément ultérieur ; le compte de syncs se fiche de quelle piste est lue).
; N'écrit QUE CIA-B PRB/DDRB (ports) -> les timers CIA-B (unité MICROHZ/M7a) ne sont pas touchés.
td_read_track0:
        movem.l d2/d3/a2,-(sp)
        move.l  #TD_RAWBYTES,d0        ; buffer piste brute en chip RAM (le DMA ne lit QUE la chip)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .rd_ret               ; pas de chip -> 0
        move.l  d0,a2                 ; a2 = buffer
        move.w  #INTF_DSKBLK,INTENA   ; s'assure que DSKBLK est MASQUÉ (on poll INTREQR, pas d'IRQ INT1 spurious)
        move.b  #$FF,CIAB_DDRB        ; port B = SORTIES avant d'écrire PRB
        move.b  #PRB_MOTOR_ON,CIAB_PRB ; moteur on (intention), tout déselectionné
        move.b  #PRB_SEL0_ON,CIAB_PRB  ; select DF0 -> le front SEL0 latche moteur=on
        move.l  #$00040000,d2         ; spin-up : busy-loop + poll DSKRDY (timeout, poursuit)
.rd_spin:
        btst    #DSKB_RDY,CIAA_PRA_HW ; DSKRDY = 0 quand prêt
        beq.s   .rd_dma
        subq.l  #1,d2
        bne.s   .rd_spin
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
        movem.l (sp)+,d2/d3/a2
        rts
.rd_stop:
        move.w  #$4000,DSKLEN        ; disable DMA disque
        move.w  #DMAF_DISK,DMACON    ; coupe SEULEMENT DSKEN (SETCLR=0 -> clear ; NE PAS toucher MASTER = affichage)
        move.w  #INTF_DSKBLK,INTREQ  ; clear DSKBLK
        move.b  #PRB_OFF,CIAB_PRB    ; moteur off + déselect
        rts
trackdisk_end:
