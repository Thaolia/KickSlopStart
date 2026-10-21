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
                xdef    td_disk_present

; --- constantes trackdisk (devices/trackdisk.i) + erreurs exec io (io.i) ---
NUMUNITS       EQU 4                 ; DF0..DF3
IOERR_OPENFAIL EQU -1                ; OpenDevice a échoué
IOERR_BADLENGTH EQU -4               ; io_Offset/io_Length pas un multiple de la taille de secteur (M6z)
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
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,20   ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (20 : place roadmap trackdisk)
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

; BeginIO(device a6, iorequest a1) : traite CMD_READ. Autres commandes -> IOERR_NOCMD. ReplyMsg si la requête
; n'est PAS quick (garde-fou B1 tenu : sinon DoIO attend pour toujours). a6 = device base en entrée/sortie.
; M6z (prérequis D) : lecture MULTI-PISTE. L'offset octet est converti en (piste, secteur-dans-piste) via
; bloc = offset/512, piste = bloc/11, secteur = bloc%11 ; la boucle lit chaque piste touchée (td_read_track +
; td_decode_track), copie jusqu'à la fin de piste, et avance -> une requête qui TRAVERSE une frontière de piste
; est servie en plusieurs lectures (dos lira le filesystem au-delà de la piste 0). Contrat trackdisk : io_Offset
; et io_Length multiples de TD_SECTOR (512) -> garde IOERR_BADLENGTH sinon ; garde de borne TD_DISKBYTES.
; Cache LRU de TD_NCACHE pistes décodées (TD_CACHEBUF, alloué au 1er CMD_READ ; 1 emplacement si la mémoire manque) :
; une piste n'y entre que si ses 11 secteurs ont été décodés ET portent le n° demandé ; vidé par /CHNG
; (td_check_change). Le moteur reste allumé entre les lectures (td_motor_server l'éteint après 2 s d'inactivité).
; DETTE : une piste partiellement décodée n'est pas cachée mais ses secteurs illisibles renvoient des octets
; PÉRIMÉS (pas d'erreur) — dette « pas de gestion de secteur défectueux » ; sans impact sur un disque propre.
trackdisk_beginio:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a2                ; a2 = ioreq
        clr.l   IO_ACTUAL(a2)
        clr.b   IO_ERROR(a2)
        move.w  IO_COMMAND(a2),d0
                ifeq    TD_READ_NOCMD
        cmp.w   #CMD_READ,d0
        beq.s   .td_read
                endc                 ; RED TD_READ_NOCMD : saute la reconnaissance -> IOERR_NOCMD
        move.l  a6,a4                ; autres commandes : a4 = base, a6 = SysBase
        move.l  ($4).w,a6
        lea     td_cmdtab(pc),a0
.td_cmd:
        move.w  (a0)+,d1
        bmi.s   .td_nocmd
        move.w  (a0)+,d2
        cmp.w   d1,d0
        bne.s   .td_cmd
        lea     td_cmdtab(pc),a0
        jsr     0(a0,d2.w)           ; routine(a2 = requête, a6 = SysBase)
        bra     .td_restore
.td_nocmd:
        move.b  #IOERR_NOCMD,IO_ERROR(a2)
        bra     .td_restore
.td_read:
        move.l  a6,a4                ; a4 = device base (sauvé ; a6 -> SysBase pour les appels exec)
        move.l  ($4).w,a6
        move.l  IO_OFFSET(a2),d3     ; d3 = offset courant (octets ; avance par piste)
        move.l  IO_LENGTH(a2),d2     ; d2 = longueur restante (octets)
        moveq   #0,d4               ; d4 = octets transférés (io_Actual accumulé)
        ; garde d'alignement : offset ET length multiples de TD_SECTOR (512) — contrat trackdisk
        move.l  d3,d0
        or.l    d2,d0
        and.l   #MFM_SECTSZ-1,d0
        beq.s   .td_aligned
        move.b  #IOERR_BADLENGTH,IO_ERROR(a2)
        bra     .td_restore
.td_aligned:
        ; garde de borne : offset+length <= taille disque
        move.l  d3,d0
        add.l   d2,d0
        cmp.l   #TD_DISKBYTES,d0
        bhi     .td_badrange
        bsr     td_check_change      ; disque changé/retiré -> invalide cache + position de tête
        tst.l   TD_CACHEBUF          ; cache de pistes, alloué au premier CMD_READ (TD_NCACHE emplacements, 1 au pire)
        bne.s   .td_havebuf
        move.l  #MFM_SECBUF*TD_NCACHE,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.w  #TD_NCACHE,TD_CNSLOTS
        tst.l   d0
        bne.s   .td_gotcache
        move.l  #MFM_SECBUF,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.w  #1,TD_CNSLOTS
        tst.l   d0
        beq     .td_nomem
.td_gotcache:
        move.l  d0,TD_CACHEBUF
        bsr     td_cache_flush
.td_havebuf:
        move.l  IO_DATA(a2),a5       ; a5 = destination (avance)
.td_bio_loop:
        tst.l   d2
        beq     .td_done_ok          ; plus rien à lire -> succès
        ; bloc logique -> (piste, secteur-dans-piste, octet-dans-piste)
        move.l  d3,d0
        lsr.l   #8,d0
        lsr.l   #1,d0                ; d0 = bloc = offset / 512  (< 1760)
        divu.w  #MFM_NSECT,d0        ; d0.w = piste (quotient) ; mot haut = secteur-dans-piste (reste)
        move.l  d0,d1
        clr.w   d1
        swap    d1                   ; d1 = secteur-dans-piste (0..10)
        and.l   #$FFFF,d0            ; d0 = piste (0..159)
        lsl.l   #8,d1
        add.l   d1,d1                ; d1 = secteur*512 = octet-dans-piste (lsl #9 interdit sur 68000)
        move.l  d1,d6                ; d6 = octet-dans-piste (préservé pour la copie)
        move.l  #MFM_SECBUF,d5       ; n = min(longueur restante, octets jusqu'à la fin de la piste)
        sub.l   d6,d5                ; d5 = dispo jusqu'à la fin de la piste
        cmp.l   d2,d5
        bls.s   .td_n_ok
        move.l  d2,d5                ; sinon n = longueur restante
.td_n_ok:                           ; d5 = n (multiple de 512)
                ifne    TD_NOSEEK
        moveq   #0,d0               ; RED TD_NOSEEK : force la piste 0 -> lecture aboutit, mauvais contenu
                endc
        ; Cache LRU de pistes décodées : chaque bloc OFS de 512 o relisait une piste ENTIÈRE ; et l'OFS alterne sans
        ; cesse entre la piste des répertoires et celles des données (mesuré : 222 lectures pour 58 pistes au boot du
        ; Workbench avec une seule piste en cache). Une piste en cache est servie sans accès disque.
        bsr     td_cache_slot        ; d1 = n° d'emplacement, a3 = son tampon ; Z = trouvée en cache
        beq.s   .td_cached
        bsr     td_fill              ; d0 = 0 piste complète (cachée), 1 partielle, -1 illisible
        tst.l   d0
        bmi     .td_noread
.td_cached:
        move.l  a3,a0                ; copie n octets : src = sectorbuf + octet-dans-piste, dst = a5
        add.l   d6,a0
        move.l  a5,a1
        move.l  d5,d0
        lsr.l   #2,d0                ; n/4 longs (n multiple de 512 -> de 4) ; n/4 <= 1408 < 65536
        subq.l  #1,d0
.td_copy:
        move.l  (a0)+,(a1)+
        dbra    d0,.td_copy
        add.l   d5,a5                ; dst += n
        add.l   d5,d3                ; offset += n
        add.l   d5,d4                ; actual += n
        sub.l   d5,d2                ; longueur restante -= n
        bra     .td_bio_loop
.td_done_ok:
        move.l  d4,IO_ACTUAL(a2)     ; octets transférés
        clr.b   IO_ERROR(a2)
        bra.s   .td_restore
.td_noread:
        move.l  d4,IO_ACTUAL(a2)     ; octets transférés avant l'échec (0 si la 1re piste échoue)
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
        bra.s   .td_restore          ; sectorbuf = cache persistant : jamais libéré
.td_badrange:
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
        bra.s   .td_restore
.td_nomem:
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
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
        movem.l (sp)+,d2-d7/a2-a5
        rts
        even
trackdisk_abortio:
        moveq   #0,d0
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Pose le nom (quirk V34). Les aires d'unité placeholder
; ne nécessitent pas d'init en B1 (deviendront Unit+MsgPort à initialiser en B2).
trackdisk_initfunc:
        clr.l   TD_CACHEBUF
        clr.l   TD_CHGCNT
        move.w  #1,TD_CNSLOTS
        bsr     td_cache_flush
        sf      TD_MOTORON
        sf      TD_BUSY
        clr.w   TD_MOTORCNT
        movem.l d0/a1,-(sp)          ; serveur VBlank d'extinction du moteur inactif
        lea     TD_VBLINT,a1
        clr.l   LN_SUCC(a1)
        clr.l   LN_PRED(a1)
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        clr.b   LN_PRI(a1)
        lea     trackdisk_name(pc),a0
        move.l  a0,LN_NAME(a1)
        clr.l   IS_DATA(a1)
        move.l  #td_motor_server,IS_CODE(a1)
        moveq   #INTB_VERTB,d0
        jsr     LVO_ADDINTSERVER(a6)
        movem.l (sp)+,d0/a1
        move.l  d0,a1
        lea     trackdisk_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts

; td_cache_flush() : vide tous les emplacements du cache (disque changé, init). Préserve tout.
td_cache_flush:
        movem.l d0/a0-a1,-(sp)
        lea     TD_CTRK,a0
        lea     TD_CDIRTY,a1
        moveq   #TD_NCACHE-1,d0
.cf_lp:
        move.w  #$FFFF,(a0)+
        sf      (a1)+
        dbra    d0,.cf_lp
        movem.l (sp)+,d0/a0-a1
        rts

; td_cache_slot(d0.w = piste) -> d1.w = n° d'emplacement, a3 = son tampon (TD_CACHEBUF + n*5632), Z = 1 si la piste y
; est (succès) ; sinon emplacement à remplir : un vide, à défaut le moins récemment utilisé. Marque l'accès (LRU :
; TD_CAGE suit TD_CTRK). Débordement de l'horloge : âges remis à 0. Préserve d0/d2-d7/a0-a2/a4-a6.
td_cache_slot:
        movem.l d2-d5/a0,-(sp)
        addq.w  #1,TD_CTICK
        bne.s   .cs_tick
        lea     TD_CAGE,a0           ; horloge repassée à 0 : repart d'âges nuls
        moveq   #TD_NCACHE-1,d1
.cs_clr:
        clr.w   (a0)+
        dbra    d1,.cs_clr
        move.w  #1,TD_CTICK
.cs_tick:
        move.w  TD_CNSLOTS,d2        ; d2 = nombre d'emplacements
        lea     TD_CTRK,a0
        moveq   #0,d1
.cs_find:
        cmp.w   (a0)+,d0
        beq.s   .cs_hit
        addq.w  #1,d1
        cmp.w   d2,d1
        blo.s   .cs_find
        lea     TD_CTRK,a0           ; absente : premier emplacement vide, sinon le plus ancien
        moveq   #0,d1
        moveq   #0,d3                ; d3 = victime
        move.w  #$FFFF,d4            ; d4 = âge de la victime
.cs_vict:
        cmp.w   #$FFFF,(a0)
        beq.s   .cs_miss             ; vide : d1
        move.w  TD_CAGE-TD_CTRK(a0),d5
        cmp.w   d4,d5
        bhs.s   .cs_vnext
        move.w  d5,d4
        move.w  d1,d3
.cs_vnext:
        addq.l  #2,a0
        addq.w  #1,d1
        cmp.w   d2,d1
        blo.s   .cs_vict
        move.w  d3,d1
.cs_miss:
        moveq   #1,d5                ; Z = 0 : à lire
        bra.s   .cs_mark
.cs_hit:
        moveq   #0,d5                ; Z = 1 : en cache
.cs_mark:
        move.w  d1,d3
        add.w   d3,d3
        lea     TD_CAGE,a0
        move.w  TD_CTICK,0(a0,d3.w)
        moveq   #0,d3
        move.w  d1,d3
        mulu    #MFM_SECBUF,d3
        move.l  TD_CACHEBUF,a3
        add.l   d3,a3
        tst.l   d5
        movem.l (sp)+,d2-d5/a0       ; movem ne touche pas le CCR
        rts

; td_motor_server (serveur VERTB) : éteint le moteur DF0 après TD_MOTORIDLE ticks sans accès (le trackdisk d'origine
; coupe aussi le moteur par minuterie). Ignoré pendant un accès (TD_BUSY). Extinction = sélection avec le bit moteur
; haut (latch off) puis déselection. -> d0 = 0 (Z : la chaîne continue).
td_motor_server:
        tst.b   TD_MOTORON
        beq.s   .ms_ret
        tst.b   TD_BUSY
        bne.s   .ms_ret
        subq.w  #1,TD_MOTORCNT
        bgt.s   .ms_ret
        move.b  #PRB_OFF,CIAB_PRB
        move.b  #PRB_SEL0_OFF,CIAB_PRB
        move.b  #PRB_OFF,CIAB_PRB
        sf      TD_MOTORON
.ms_ret:
        moveq   #0,d0
        rts

; td_check_change() : sélectionne DF0 en latchant moteur OFF et lit /CHNG (bas = disque retiré/changé depuis le
; dernier pas de tête ; seul un pas avec disque présent le relâche). Bas -> invalide le cache de piste ET la
; position de tête (recalibration). Clobbe d0. Coût : 3 écritures PRB, sans spin-up.
td_check_change:
        st      TD_BUSY
        move.b  #$FF,CIAB_DDRB
        tst.b   TD_MOTORON           ; la sélection relatche l'état du moteur : garder l'état courant
        bne.s   .cc_on
        move.b  #PRB_OFF,CIAB_PRB
        move.b  #PRB_SEL0_OFF,CIAB_PRB
        btst    #DSKB_CHANGE,CIAA_PRA_HW
        sne     d0                   ; d0 = $FF si /CHNG haut (pas de changement)
        move.b  #PRB_OFF,CIAB_PRB
        bra.s   .cc_read
.cc_on:
        move.b  #PRB_MOTOR_ON,CIAB_PRB
        move.b  #PRB_SEL0_ON,CIAB_PRB
        btst    #DSKB_CHANGE,CIAA_PRA_HW
        sne     d0
        move.b  #PRB_MOTOR_ON,CIAB_PRB
.cc_read:
        sf      TD_BUSY
        tst.b   d0
        bne.s   .cc_ret
        bsr     td_cache_flush
        clr.b   TD_CYLVALID
        addq.l  #1,TD_CHGCNT
.cc_ret:
        rts

; td_read_track0(a6=SysBase) -> d0 = buffer chip (piste MFM brute) | 0 (timeout / pas de disque). B2 MINIMAL :
; DDRB=$FF (suspect n°1 : sans ça PRB ne pilote rien) ; moteur-on + select DF0 (latch moteur via front SEL0) ;
; spin-up (busy-loop + poll DSKRDY avec timeout, poursuit) ; seek (recalibration cyl 0 + step-in + side) ;
; DMA WORDSYNC d'une piste ; poll INTREQR DSKBLK avec timeout (jamais de hang).
; N'écrit QUE CIA-B PRB/DDRB (ports) -> les timers CIA-B (unité MICROHZ/M7a) ne sont pas touchés.
; B2b : td_read_track(d0 = n° de piste) seek d'abord vers la piste ; td_read_track0 = lit la piste 0 (wrapper pour
; les appelants existants : M6U/M6V, BeginIO). piste = cylindre*2 + face. CYLINDER-TRACKING : on suit TD_CURCYL et on
; steppe le DELTA vers la cible (recalibration à 0 seulement si TD_CYLVALID==0) -> correct ET rapide (cf. .rd_seek).
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
        bsr     td_position           ; moteur, sélection, seek, face (IRQ rétablies)
.rd_dma:
        move.w  #INTF_DSKBLK,INTREQ   ; clear DSKBLK pendant
        move.w  #$7FFF,ADKCON         ; clear tous les bits ADKCON
                ifeq    TD_NO_DMA
        ; $9500 = SETCLR|MFMPREC|FAST|WORDSYNC. Le bit FAST (débit 2 us/bit, standard DD) est le FIX WinUAE :
        ; sans lui (ancien $8400, FAST=0 = 4 us/bit) Paula échantillonne le flux au MAUVAIS rythme -> les octets
        ; s'assemblent (DSKBYT) mais le bitstream est garbage -> $4489 ne se forme jamais -> WORDEQUAL jamais ->
        ; lecture KO (prouvé stage=$53 sur WinUAE). FS-UAE lâche décodait quand même. $9500 = mode lecture officiel
        ; KS1.3 ($9100 = SETCLR|MFMPREC|FAST) + WORDSYNC. Cf. docs/analysis/trackdisk-official-timing.md.
        move.w  #(ADKF_SETCLR|ADKF_MFMPREC|ADKF_FAST|ADKF_WORDSYNC),ADKCON   ; $9500
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
        move.b  #PRB_MOTOR_ON,CIAB_PRB ; déselect, moteur laissé allumé (latché) : la lecture suivante évite le spin-up
        move.w  #TD_MOTORIDLE,TD_MOTORCNT ; le serveur VBlank l'éteindra après TD_MOTORIDLE ticks d'inactivité
        sf      TD_BUSY
        rts
; td_position(d6 = piste, a6 = SysBase) : moteur allumé (spin-up si besoin), DF0 sélectionné, tête amenée au
; cylindre (suivi de cylindre, recalibration si position inconnue), face choisie. TD_BUSY posé (rendu par l'appelant
; à la fin de son accès). Clobbe d0/d2/d3.
td_position:
        st      TD_BUSY               ; le serveur VBlank ne touche plus au lecteur
        move.w  #INTF_DSKBLK,INTENA   ; s'assure que DSKBLK est MASQUÉ (on poll INTREQR, pas d'IRQ INT1 spurious)
        move.b  #$FF,CIAB_DDRB        ; port B = SORTIES avant d'écrire PRB
        move.b  #PRB_MOTOR_ON,CIAB_PRB ; moteur on (intention), tout déselectionné
        move.b  #PRB_SEL0_ON,CIAB_PRB  ; select DF0 -> le front SEL0 latche moteur=on
        tst.b   TD_MOTORON            ; moteur resté allumé depuis la lecture précédente : déjà à vitesse
        bne.s   .rd_seek
        st      TD_MOTORON
        move.l  #$00040000,d2         ; spin-up : busy-loop + poll DSKRDY (timeout = lecteur absent/vide)
.rd_spin:
        btst    #DSKB_RDY,CIAA_PRA_HW ; DSKRDY = 0 quand prêt
        beq.s   .rd_seek
        subq.l  #1,d2
        bne.s   .rd_spin
        ; DSKRDY pas asservi dans la fenêtre de spin-up. CORRECTION (dette vraie-A500 levée) : sur un vrai A500 /
        ; WinUAE timing-exact, /RDY est LENT ou ne s'asserte JAMAIS dans cette fenêtre alors que le disque TOURNE
        ; -> l'ancien gate dur « moteur off + renvoie 0 » rejetait TOUT disque valide (toutes lectures KO sous
        ; WinUAE timing-exact, prouvé stage=2). On NE FAIL PLUS ici : la boucle a déjà laissé ~0,5-1 s de spin-up
        ; moteur ; on POURSUIT vers le seek+DMA, où le sync WORDSYNC du DMA est le VRAI test de présence (le
        ; comportement d'avant B2). Sans disque -> pas de sync -> timeout DMA plus bas -> renvoie 0 (plus lent que
        ; l'ancien probe « sans disque » mais CORRECT). /RDY reste le chemin RAPIDE via le « beq.s .rd_seek » plus haut.
.rd_seek:
        ; SECTION CRITIQUE du seek : les pulses de pas écrivent CIAB_PRB, et la source MICROHZ (timer A de
        ; CIA-B, INT6) partage la MÊME puce. Une IRQ INT6 tombant entre les écritures PRB d'un pas corrompt le
        ; positionnement de la tête -> la lecture suivante se vautre (hang observé sur un gros seek vers un bloc
        ; haut, ex. « flt-intro » sur le disque Lemmings ; invisible tant que le boot ne lit que des blocs bas).
        ; Prouvé par bissection : un DÉLAI inter-pas pur ne corrige PAS (donc pas un défaut de settle), masquer
        ; les IRQ, OUI (3/3). On masque le seul SEEK (court) ; le DMA en aval poll INTREQR -> pas d'IRQ requise.
        jsr     LVO_DISABLE(a6)     ; a6 = SysBase ; équilibré par LVO_ENABLE à .rd_pend
        ; --- seek vers la piste d6 avec SUIVI DU CYLINDRE (cylinder-tracking) ---
        ; On mémorise le cylindre courant (TD_CURCYL, fiable ssi TD_CYLVALID) et on steppe le DELTA vers la cible
        ; (IN si plus profond, OUT si plus près de 0) au lieu de recalibrer à zéro à CHAQUE lecture. Recalibration
        ; (step OUT jusqu'à DSKTRACK0, cap 85) SEULEMENT si la position est inconnue. Corrige PROPREMENT le bug C
        ; (lire la piste 0 après un seek lisait la mauvaise piste) : le delta ramène la tête au bon cylindre quelle
        ; que soit sa position. Beaucoup plus rapide (pas 85 pas par lecture) -> débloque le boot disquette sous
        ; l'ordonnanceur. Side-select indépendant du cylindre. DETTE vraie-A500 : pas d'invalidation sur disk-change
        ; (position supposée persistante ; OK sous FS-UAE, à revoir pour l'eject/swap réel + recal périodique).
        move.w  d6,d3               ; d3 = cylindre cible = piste / 2
        lsr.w   #1,d3
                ifne    TD_NO_CYLTRACK
        clr.b   TD_CYLVALID         ; RED : force la recalibration à CHAQUE lecture (ancien comportement lent)
                endc
        tst.b   TD_CYLVALID         ; position connue ?
        bne.s   .rd_known
        move.w  #85,d2              ; recalibration : step OUT jusqu'à DSKTRACK0 (cap 85)
.rd_recal:
        btst    #DSKB_TRACK0,CIAA_PRA_HW
        beq.s   .rd_recdone
        bsr     .rd_step_out        ; un pas OUT (pulse élargi : compatible drive strict / vrai A500)
        bsr     .rd_stepwait
        dbra    d2,.rd_recal
.rd_recdone:
        bsr     .rd_settle
        clr.w   TD_CURCYL           ; position connue = cylindre 0
        st      TD_CYLVALID
.rd_known:
                ifeq    SEEK_NOSTEP
        move.w  TD_CURCYL,d2
        sub.w   d3,d2               ; d2 = courant - cible
        beq.s   .rd_side            ; déjà sur le bon cylindre
        bmi.s   .rd_stepin          ; courant < cible -> stepper IN
.rd_stepout:                        ; courant > cible -> stepper OUT (vers 0) d2 fois
        bsr     .rd_step_out        ; un pas OUT (pulse élargi)
        bsr     .rd_stepwait
        subq.w  #1,d2
        bne.s   .rd_stepout
        bra.s   .rd_seekdone
.rd_stepin:
        neg.w   d2                  ; |delta|
.rd_stepin_l:
        bsr     .rd_step_in         ; un pas IN (pulse élargi)
        bsr     .rd_stepwait
        subq.w  #1,d2
        bne.s   .rd_stepin_l
.rd_seekdone:
        bsr     .rd_settle          ; stabilisation de la tête UNE fois, après le dernier pas
        move.w  d3,TD_CURCYL        ; position = cible
                endc                ; RED SEEK_NOSTEP : pas de step (ni MAJ TD_CURCYL) -> reste sur place
.rd_side:
        move.b  #$77,CIAB_PRB       ; face 0 (DSKSIDE=1, bit2=1 ; piste paire)
        btst    #0,d6
        beq.s   .rd_pend
        move.b  #$73,CIAB_PRB       ; face 1 (DSKSIDE=0, bit2=0 ; piste impaire)
.rd_pend:
        jsr     LVO_ENABLE(a6)      ; fin de la section critique du seek
        rts
; Délais de la tête (boucles subq/bne ≈ 2,54 us par tour à 7,09 MHz) : 3 ms entre deux pas (débit de pas d'un lecteur
; DD) et 18 ms de stabilisation UNE fois après le dernier pas. Avant : ~83 ms après CHAQUE pas (3,3 s pour 40 cyl).
; Compteur en d0 : préserve d2 (compteur de pas) ET d3 (cylindre cible du cylinder-tracking).
TD_STEPWAIT   EQU 1180              ; 3 ms
TD_SETTLE     EQU 7090              ; 18 ms
.rd_stepwait:
        move.l  #TD_STEPWAIT,d0
        bra.s   .rd_sloop
.rd_settle:
        move.l  #TD_SETTLE,d0
.rd_sloop:
        subq.l  #1,d0
        bne.s   .rd_sloop
        rts

; Un pas à PULSE ÉLARGI (compatibilité drive STRICT / vrai A500). Le modèle floppy cycle-exact de WinUAE IGNORE
; un /STEP trop bref (3 écritures CIAB_PRB dos-à-dos = ~1,4 us de bas) : la tête ne bouge pas -> aucune piste
; valide sous la tête -> pas de sync $4489 (prouvé : toutes lectures stage=3/$53, recal forcée inefficace). On
; pose la DIRECTION, on la laisse se stabiliser, puis on tient /STEP bas TD_STEP_DLY avant de relâcher -> chaque
; pas est reçu. Clobbe d0 ; préserve d2 (compteur de pas) et d3 (cylindre cible). FS-UAE inchangé (edge identique).
TD_STEP_DLY   EQU $40               ; ~160 us de largeur (très au-dessus du minimum drive ; << settle 82 ms)
.rd_step_out:
        move.b  #$77,CIAB_PRB       ; direc OUT (bit1=1), step=1 : pose la direction
        bsr.s   .rd_stepdly         ; setup : direction stable avant le front de pas
        move.b  #$76,CIAB_PRB       ; step=0 : front descendant = le pas
        bsr.s   .rd_stepdly         ; maintient /STEP bas (largeur du pulse)
        move.b  #$77,CIAB_PRB       ; step=1 : relâche
        rts
.rd_step_in:
        move.b  #$75,CIAB_PRB       ; direc IN (bit1=0), step=1
        bsr.s   .rd_stepdly
        move.b  #$74,CIAB_PRB       ; step=0 : le pas
        bsr.s   .rd_stepdly
        move.b  #$75,CIAB_PRB       ; step=1
        rts
.rd_stepdly:
        move.l  #TD_STEP_DLY,d0
.rd_sdloop:
        subq.l  #1,d0
        bne.s   .rd_sdloop
        rts

; table des commandes autres que CMD_READ : (commande, routine - td_cmdtab)
TDCMD           MACRO
        dc.w    \1,\2-td_cmdtab
                ENDM
td_cmdtab:
        TDCMD   CMD_WRITE,td_cmd_write
        TDCMD   TD_FORMAT,td_cmd_format
        TDCMD   CMD_UPDATE,td_cmd_update
        TDCMD   CMD_CLEAR,td_cmd_clear
        TDCMD   TD_MOTOR,td_cmd_motor
        TDCMD   TD_PROTSTATUS,td_cmd_prot
        TDCMD   TD_CHANGENUM,td_cmd_chgnum
        TDCMD   TD_CHANGESTATE,td_cmd_chgstate
        TDCMD   TD_GETNUMTRACKS,td_cmd_ntracks
        TDCMD   CMD_RESET,td_cmd_nop
        TDCMD   CMD_STOP,td_cmd_nop
        TDCMD   CMD_START,td_cmd_nop
        TDCMD   CMD_FLUSH,td_cmd_nop
        TDCMD   TD_SEEK,td_cmd_nop
        TDCMD   TD_REMOVE,td_cmd_nop
        TDCMD   TD_ADDCHANGEINT,td_cmd_nop
        TDCMD   TD_REMCHANGEINT,td_cmd_nop
        dc.w    -1

td_cmd_nop:
        rts
td_cmd_ntracks:
        move.l  #TD_NTRACKS,IO_ACTUAL(a2)
        rts
td_cmd_chgnum:
        bsr     td_check_change
        move.l  TD_CHGCNT,IO_ACTUAL(a2)
        rts
; TD_CHANGESTATE : io_Actual = 0 si une disquette est dans le lecteur.
td_cmd_chgstate:
        bsr     td_check_change
        bsr     td_sense
        moveq   #0,d0
        btst    #DSKB_CHANGE,d1
        bne.s   .cs_in
        moveq   #1,d0
.cs_in:
        move.l  d0,IO_ACTUAL(a2)
        rts
; TD_PROTSTATUS : io_Actual != 0 si la disquette est protégée en écriture.
td_cmd_prot:
        bsr     td_sense
        moveq   #0,d0
        btst    #DSKB_PROT,d1
        bne.s   .pr_rw
        moveq   #-1,d0
.pr_rw:
        move.l  d0,IO_ACTUAL(a2)
        rts
; TD_MOTOR : io_Length 0 = arrêt (les pistes modifiées restent en cache jusqu'à CMD_UPDATE), 1 = marche (le moteur
; démarre au prochain accès) ; io_Actual = état précédent.
td_cmd_motor:
        moveq   #0,d0
        tst.b   TD_MOTORON
        beq.s   .mo_was
        moveq   #1,d0
.mo_was:
        move.l  d0,IO_ACTUAL(a2)
        tst.l   IO_LENGTH(a2)
        bne.s   .mo_ret
        tst.b   TD_MOTORON
        beq.s   .mo_ret
        jsr     LVO_DISABLE(a6)
        move.b  #PRB_OFF,CIAB_PRB
        move.b  #PRB_SEL0_OFF,CIAB_PRB
        move.b  #PRB_OFF,CIAB_PRB
        sf      TD_MOTORON
        jsr     LVO_ENABLE(a6)
.mo_ret:
        rts
; CMD_CLEAR : le cache est oublié, pistes modifiées comprises.
td_cmd_clear:
        bra     td_cache_flush
; CMD_UPDATE : les pistes modifiées sont écrites sur le disque.
td_cmd_update:
        bsr     td_flush_all
        move.b  d0,IO_ERROR(a2)
        rts

; td_sense(a6) -> d1.b = CIA-A PRA lu avec DF0 sélectionné (état du moteur conservé) : /CHNG, /WPRO... Clobbe d0.
td_sense:
        jsr     LVO_DISABLE(a6)
        move.b  #$FF,CIAB_DDRB
        move.b  #PRB_OFF,d0          ; sélection en relatchant l'état courant du moteur
        tst.b   TD_MOTORON
        beq.s   .se_off
        move.b  #PRB_MOTOR_ON,d0
.se_off:
        move.b  d0,CIAB_PRB
        and.b   #$F7,d0              ; SEL0 bas
        move.b  d0,CIAB_PRB
        move.b  CIAA_PRA_HW,d1
        or.b    #$08,d0
        move.b  d0,CIAB_PRB
        jsr     LVO_ENABLE(a6)
        rts

; CMD_WRITE (io_Offset, io_Length multiples de 512) : les secteurs vont dans les pistes du cache, marquées modifiées ;
; une piste couverte en partie est d'abord lue. TD_FORMAT : pistes entières, jamais lues, écrites aussitôt.
td_cmd_format:
        moveq   #1,d7
        bra.s   td_wr
td_cmd_write:
        moveq   #0,d7
td_wr:
        move.l  IO_OFFSET(a2),d3
        move.l  IO_LENGTH(a2),d2
        moveq   #0,d4
        move.l  d3,d0
        or.l    d2,d0
        and.l   #MFM_SECTSZ-1,d0
        bne     .wr_badlen
        tst.l   d7
        beq.s   .wr_lenok
        move.l  d3,d0                ; TD_FORMAT : pistes entières
        divu    #MFM_SECBUF,d0
        swap    d0
        tst.w   d0
        bne     .wr_badlen
        move.l  d2,d0
        divu    #MFM_SECBUF,d0
        swap    d0
        tst.w   d0
        bne     .wr_badlen
.wr_lenok:
        move.l  d3,d0
        add.l   d2,d0
        cmp.l   #TD_DISKBYTES,d0
        bhi     .wr_err
        bsr     td_check_change
        bsr     td_sense
        btst    #DSKB_PROT,d1
        beq     .wr_prot
        bsr     td_cachebuf          ; cache alloué (premier accès)
        beq     .wr_err
        move.l  IO_DATA(a2),a5
.wr_loop:
        tst.l   d2
        beq     .wr_done
        move.l  d3,d0                ; piste, octet dans la piste, n = jusqu'à la fin de la piste
        lsr.l   #8,d0
        lsr.l   #1,d0
        divu.w  #MFM_NSECT,d0
        move.l  d0,d1
        clr.w   d1
        swap    d1
        and.l   #$FFFF,d0
        lsl.l   #8,d1
        add.l   d1,d1
        move.l  d1,d6                ; d6 = octet dans la piste
        move.l  #MFM_SECBUF,d5
        sub.l   d6,d5
        cmp.l   d2,d5
        bls.s   .wr_n
        move.l  d2,d5
.wr_n:
        bsr     td_cache_slot        ; d1 = emplacement, a3 = tampon ; Z = piste en cache
        beq.s   .wr_have
        tst.l   d6                   ; piste entière remplacée : pas de lecture
        bne.s   .wr_read
        cmp.l   #MFM_SECBUF,d5
        bne.s   .wr_read
        move.w  d0,-(sp)
        move.w  d1,d0                ; l'emplacement repris est d'abord écrit s'il était modifié
        bsr     td_flush_slot
        move.w  (sp)+,d0
        lea     TD_CTRK,a0
        move.w  d1,d4
        add.w   d4,d4
        move.w  d0,0(a0,d4.w)
        moveq   #0,d4
        bra.s   .wr_have
.wr_read:
        bsr     td_fill              ; piste modifiée en partie : son contenu complet d'abord
        tst.l   d0
        bne.s   .wr_err              ; illisible ou incomplète : on n'écrit pas par-dessus
.wr_have:
        move.l  a3,a1                ; copie dans le cache
        add.l   d6,a1
        move.l  a5,a0
        move.l  d5,d0
        lsr.l   #2,d0
        subq.l  #1,d0
.wr_cp:
        move.l  (a0)+,(a1)+
        dbra    d0,.wr_cp
        lea     TD_CDIRTY,a0
        st      0(a0,d1.w)
        add.l   d5,a5
        add.l   d5,d3
        add.l   d5,IO_ACTUAL(a2)
        sub.l   d5,d2
        bra     .wr_loop
.wr_done:
        tst.l   d7
        beq.s   .wr_ret
        bsr     td_flush_all         ; TD_FORMAT : écrit tout de suite
        move.b  d0,IO_ERROR(a2)
.wr_ret:
        rts
.wr_badlen:
        move.b  #IOERR_BADLENGTH,IO_ERROR(a2)
        rts
.wr_prot:
        move.b  #TDERR_WriteProt,IO_ERROR(a2)
        rts
.wr_err:
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
        rts

; td_cachebuf(a6) : alloue le cache de pistes au premier accès (TD_NCACHE emplacements, 1 si la mémoire manque).
; Z = 1 si impossible. Clobbe d0/d1/a0/a1.
td_cachebuf:
        tst.l   TD_CACHEBUF
        bne.s   .cb_ok
        move.l  #MFM_SECBUF*TD_NCACHE,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.w  #TD_NCACHE,TD_CNSLOTS
        tst.l   d0
        bne.s   .cb_got
        move.l  #MFM_SECBUF,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.w  #1,TD_CNSLOTS
        tst.l   d0
        beq.s   .cb_ret
.cb_got:
        move.l  d0,TD_CACHEBUF
        bsr     td_cache_flush
.cb_ok:
        moveq   #1,d0                ; Z = 0
.cb_ret:
        rts

; td_fill(d0.w = piste, d1.w = emplacement, a3 = son tampon, a6) : l'emplacement (écrit d'abord s'il était modifié)
; reçoit la piste lue et décodée ; il n'est déclaré valide que si ses 11 secteurs sont bons et portent cette piste.
; -> d0 = 0 piste complète, 1 incomplète (contenu partiel, non cachée), -1 illisible. Préserve d1-d7/a2-a6.
td_fill:
        movem.l d1-d7/a2-a5,-(sp)
        move.w  d0,d6                ; d6 = piste
        move.w  d1,d5                ; d5 = emplacement
        move.w  d5,d0
        bsr     td_flush_slot
        lea     TD_CTRK,a0
        move.w  d5,d4
        add.w   d4,d4                ; d4 = offset de l'emplacement
        move.w  #$FFFF,0(a0,d4.w)    ; vide tant que la piste n'est pas vérifiée
        moveq   #0,d0
        move.w  d6,d0
        bsr     td_read_track        ; d0 = tampon brut | 0
        tst.l   d0
        beq.s   .fi_none
        move.l  d0,d7
        move.l  d0,a0
        move.l  a3,a1
        bsr     td_decode_track      ; d0 = secteurs valides, d1 = piste du dernier secteur valide
        moveq   #1,d2
        cmp.w   #MFM_NSECT,d0
        bne.s   .fi_free
        cmp.w   d6,d1
        bne.s   .fi_free
        lea     TD_CTRK,a0
        move.w  d6,0(a0,d4.w)
        moveq   #0,d2
.fi_free:
        move.l  d7,a1
        move.l  #TD_RAWBYTES,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d2,d0
        bra.s   .fi_ret
.fi_none:
        moveq   #-1,d0
.fi_ret:
        movem.l (sp)+,d1-d7/a2-a5
        rts

; td_flush_all(a6) -> d0 = 0 | erreur trackdisk : écrit toutes les pistes modifiées du cache. Préserve d1-d7/a0-a6.
td_flush_all:
        movem.l d1-d2,-(sp)
        moveq   #0,d2
        moveq   #0,d0
.fa_lp:
        cmp.w   TD_CNSLOTS,d0
        bhs.s   .fa_ret
        move.l  d0,-(sp)
        bsr.s   td_flush_slot
        tst.l   d2
        bne.s   .fa_keep
        move.l  d0,d2                ; première erreur gardée
.fa_keep:
        move.l  (sp)+,d0
        addq.w  #1,d0
        bra.s   .fa_lp
.fa_ret:
        move.l  d2,d0
        movem.l (sp)+,d1-d2
        rts

; td_flush_slot(d0.w = emplacement, a6) -> d0 = 0 | erreur : si l'emplacement est modifié, sa piste est codée en MFM et
; écrite, puis déclarée propre. Préserve d1-d7/a0-a6.
td_flush_slot:
        movem.l d1-d7/a0-a5,-(sp)
        move.w  d0,d5
        lea     TD_CDIRTY,a0
        tst.b   0(a0,d5.w)
        beq.s   .fs_ok
        sf      0(a0,d5.w)
        lea     TD_CTRK,a0
        move.w  d5,d6
        add.w   d6,d6
        move.w  0(a0,d6.w),d6        ; d6 = piste
        cmp.w   #$FFFF,d6
        beq.s   .fs_ok
        move.l  #TD_WRBYTES,d0       ; piste MFM en mémoire chip (le DMA ne voit qu'elle)
        move.l  #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .fs_nomem
        move.l  d0,a4
        moveq   #0,d0
        move.w  d5,d0
        mulu    #MFM_SECBUF,d0
        move.l  TD_CACHEBUF,a0
        add.l   d0,a0
        move.l  a4,a1
        move.w  d6,d0
        bsr     td_encode_track
        moveq   #0,d0
        move.w  d6,d0
        move.l  a4,a0
        bsr     td_write_track       ; d0 = 0 | erreur
        move.l  d0,d7
        move.l  a4,a1
        move.l  #TD_WRBYTES,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d7,d0
        bra.s   .fs_ret
.fs_nomem:
        lea     TD_CDIRTY,a0         ; rien d'écrit : la piste reste à écrire
        st      0(a0,d5.w)
        moveq   #TDERR_NotSpec,d0
        bra.s   .fs_ret
.fs_ok:
        moveq   #0,d0
.fs_ret:
        movem.l (sp)+,d1-d7/a0-a5
        rts

; td_encode_track(a0 = 11 secteurs décodés, a1 = destination TD_WRBYTES, d0.w = piste) : piste au format AmigaDOS.
; Garde ; puis par secteur : préambule (0 codé), sync $4489 $4489, en-tête $FF.piste.secteur.(11 - secteur) et label
; (16 o nuls) en bits impairs puis pairs, somme de contrôle de l'en-tête, somme des données, données (impairs puis
; pairs) ; les sommes sont le OU exclusif des longs codés (bits de données). Les bits d'horloge sont ensuite posés
; (1 entre deux bits de données nuls), sauf dans les mots de sync. Préserve d2-d7/a2-a6.
td_encode_track:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a3                ; a3 = secteurs
        move.l  a1,a2                ; a2 = sortie
        move.w  d0,d7                ; d7 = piste
        move.l  #MFM_MASK,d6
        move.w  #TD_WRGAP/4-1,d1
.en_gap:
        move.l  #$AAAAAAAA,(a2)+     ; zéros codés
        dbra    d1,.en_gap
        moveq   #0,d5                ; d5 = secteur
.en_sec:
        move.l  a2,a4                ; a4 = début du secteur
        clr.l   (a2)+                ; préambule : deux mots de zéros
        move.l  #$44894489,(a2)+
        moveq   #-1,d0               ; en-tête
        move.b  d7,d0
        lsl.w   #8,d0
        move.b  d5,d0
        lsl.l   #8,d0
        moveq   #MFM_NSECT,d1
        sub.b   d5,d1
        move.b  d1,d0
        bsr.s   .en_long
        moveq   #7,d1                ; label
.en_lab:
        clr.l   (a2)+
        dbra    d1,.en_lab
        lea     8(a4),a0             ; somme de l'en-tête : 10 longs
        moveq   #0,d0
        moveq   #9,d1
.en_hs:
        move.l  (a0)+,d2
        eor.l   d2,d0
        dbra    d1,.en_hs
        bsr.s   .en_long
        lea     8(a2),a1             ; données : impairs puis pairs, somme au passage
        lea     512(a1),a5
        move.l  a3,a0
        moveq   #0,d4
        move.w  #127,d1
.en_dat:
        move.l  (a0)+,d0
        move.l  d0,d2
        lsr.l   #1,d2
        and.l   d6,d2
        move.l  d2,(a1)+
        eor.l   d2,d4
        and.l   d6,d0
        move.l  d0,(a5)+
        eor.l   d0,d4
        dbra    d1,.en_dat
        move.l  d4,d0                ; somme des données
        bsr.s   .en_long
        lea     1024(a2),a2
        lea     MFM_SECTSZ(a3),a3
        move.l  a4,a0                ; horloge : préambule (après le long précédent), puis après la sync
        moveq   #1,d0
        move.l  -4(a4),d1
        bsr.s   .en_clock
        lea     8(a4),a0
        move.w  #(TD_SECRAW-8)/4,d0
        move.l  #$44894489,d1
        bsr.s   .en_clock
        addq.w  #1,d5
        cmp.w   #MFM_NSECT,d5
        blo     .en_sec
        movem.l (sp)+,d2-d7/a2-a5
        rts
.en_long:                            ; d0 -> (a2)+ : bits impairs puis pairs. Clobbe d2.
        move.l  d0,d2
        lsr.l   #1,d2
        and.l   d6,d2
        move.l  d2,(a2)+
        and.l   d6,d0
        move.l  d0,(a2)+
        rts
.en_clock:                           ; a0 = longs (bits de données), d0.w = nombre, d1 = long précédent
        movem.l d2-d4,-(sp)
        subq.w  #1,d0
.ec_lp:
        move.l  (a0),d2
        and.l   d6,d2
        move.l  d2,d3
        add.l   d3,d3                ; voisin suivant (bit k-1 en k)
        move.l  d2,d4
        lsr.l   #1,d4                ; voisin précédent (bit k+1 en k)
        or.l    d4,d3
        and.l   #1,d1                ; bit 31 : dernier bit du long précédent
        ror.l   #1,d1
        or.l    d1,d3
        not.l   d3
        and.l   #$AAAAAAAA,d3
        or.l    d3,d2
        move.l  d2,(a0)+
        move.l  d2,d1
        dbra    d0,.ec_lp
        movem.l (sp)+,d2-d4
        rts

; td_write_track(d0 = piste, a0 = piste MFM en chip, TD_WRBYTES, a6) -> d0 = 0 | erreur : positionnement, contrôle de la
; protection, DMA d'écriture (précompensation 140 ns sur les cylindres internes), attente de fin puis du dernier mot.
td_write_track:
        movem.l d2/d3/d6/a2,-(sp)
        move.l  d0,d6
        move.l  a0,a2
        bsr     td_position
        btst    #DSKB_PROT,CIAA_PRA_HW
        bne.s   .wt_rw
        moveq   #TDERR_WriteProt,d2
        bra.s   .wt_stop
.wt_rw:
        move.w  #INTF_DSKBLK,INTREQ
        move.w  #$7F00,ADKCON        ; précompensation, MFM, débit, sync : effacés (bits audio intacts)
        move.w  #(ADKF_SETCLR|ADKF_MFMPREC|ADKF_FAST),d0
        cmp.w   #TD_NTRACKS/2,d6
        blo.s   .wt_pc
        or.w    #ADKF_PRECOMP140,d0
.wt_pc:
        move.w  d0,ADKCON
        move.l  a2,DSKPT
        move.w  #$4000,DSKLEN
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_DISK),DMACON
        move.w  #($C000|TD_WRWORDS),DSKLEN   ; DMAEN | WRITE | longueur
        move.w  #($C000|TD_WRWORDS),DSKLEN
        move.l  #$00080000,d2
.wt_wait:
        move.w  INTREQR,d3
        btst    #1,d3                ; DSKBLK
        bne.s   .wt_end
        subq.l  #1,d2
        bne.s   .wt_wait
        moveq   #TDERR_NotSpec,d2
        bra.s   .wt_stop
.wt_end:
        move.l  #800,d0              ; ~2 ms : le dernier mot quitte la tête
.wt_tail:
        subq.l  #1,d0
        bne.s   .wt_tail
        moveq   #0,d2
.wt_stop:
        move.w  #$4000,DSKLEN
        move.w  #DMAF_DISK,DMACON
        move.w  #INTF_DSKBLK,INTREQ
        move.b  #PRB_MOTOR_ON,CIAB_PRB
        move.w  #TD_MOTORIDLE,TD_MOTORCNT
        sf      TD_BUSY
        move.l  d2,d0
        movem.l (sp)+,d2/d3/d6/a2
        rts

; td_disk_present() -> d0 = -1 si une disquette est dans DF0, 0 sinon. /CHNG haut : disquette présente. Bas : une
; impulsion de pas réarme le verrou si une disquette a été insérée (le lecteur « clique » comme un Kickstart en attente
; de disquette), puis /CHNG est relu. Moteur coupé ; la position de tête est ensuite tenue pour inconnue.
; Appelé hors de toute lecture (écran insert-disk), sous Disable (impulsions de pas sur CIA-B). a6 = SysBase.
; Clobbe d0/d1.
td_disk_present:
        jsr     LVO_DISABLE(a6)
        move.b  #$FF,CIAB_DDRB
        move.b  #PRB_OFF,CIAB_PRB
        move.b  #PRB_SEL0_OFF,CIAB_PRB  ; DF0 sélectionné, moteur latché OFF
        btst    #DSKB_CHANGE,CIAA_PRA_HW
        bne.s   .dp_yes
        moveq   #$F7-$F7,d1          ; un pas : vers l'intérieur sur la piste 0, sinon vers l'extérieur
        btst    #DSKB_TRACK0,CIAA_PRA_HW
        bne.s   .dp_out
        moveq   #2,d1                ; direction IN = bit 1 à 0
.dp_out:
        move.b  #$F7,d0
        sub.b   d1,d0
        move.b  d0,CIAB_PRB          ; direction posée, /STEP haut
        bsr.s   .dp_dly
        subq.b  #1,d0
        move.b  d0,CIAB_PRB          ; /STEP bas : le pas
        bsr.s   .dp_dly
        addq.b  #1,d0
        move.b  d0,CIAB_PRB          ; /STEP relâché
        bsr.s   .dp_dly
        clr.b   TD_CYLVALID
        btst    #DSKB_CHANGE,CIAA_PRA_HW
        bne.s   .dp_yes
        move.b  #PRB_OFF,CIAB_PRB
        jsr     LVO_ENABLE(a6)
        moveq   #0,d0
        rts
.dp_yes:
        move.b  #PRB_OFF,CIAB_PRB
        jsr     LVO_ENABLE(a6)
        moveq   #-1,d0
        rts
.dp_dly:
        move.l  #TD_STEP_DLY,d1
.dp_dl:
        subq.l  #1,d1
        bne.s   .dp_dl
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
