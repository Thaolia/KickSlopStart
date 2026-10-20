; src/exec/audio.s — audio.device : attribution des 4 canaux Paula et lecture d'échantillons par DMA.
;
; ATTRIBUTION : chaque canal porte une clé (0 = libre) et une précédence. ADCMD_ALLOCATE essaie les combinaisons
; (ioa_Data) dans l'ordre : la première sans canal à voler l'emporte, sinon celle qui vole les précédences les plus
; basses, toujours strictement inférieures à ln_Pri. Un canal volé perd ses E/S (IOERR_ABORTED) et sa clé change.
; Un canal verrouillé (ADCMD_LOCK) n'est pas volé directement : son verrou est rendu avec ADIOERR_CHANNELSTOLEN et
; l'allocation attend que le canal soit libéré. Les allocations en attente sont retentées à chaque ADCMD_FREE,
; ADCMD_SETPREC et CloseDevice.
; LECTURE : Paula déclenche l'interruption AUDn chaque fois qu'il recharge position et longueur, c'est-à-dire au
; début de chaque passage (cycle) dans l'échantillon. Le compteur ACH_CNT compte ces débuts ; quand le dernier
; cycle commence, on charge déjà l'échantillon suivant de la file (enchaînement sans trou) ou un mot de silence ;
; au début suivant, l'écriture terminée est rendue et la suivante devient courante.
; Écarts assumés : les commandes s'exécutent directement sous Disable (pas de file de commandes séparée) ;
; ADCMD_FINISH immédiat rend l'écriture avec IOERR_ABORTED, synchronisé (ADIOF_SYNCCYCLE) sans erreur.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs audio.device + devices/audio.h + HRM (Paula audio). AUCUNE lecture ROM.

                include "exec.i"

; --- struct IOAudio (devices/audio.h) ---
IO_UNITB        EQU IO_UNIT+3        ; octet bas de io_Unit = carte des canaux
IOA_ALLOCKEY    EQU 32
IOA_DATA        EQU 34
IOA_LENGTH      EQU 38
IOA_PERIOD      EQU 42
IOA_VOLUME      EQU 44
IOA_CYCLES      EQU 46
IOA_WRITEMSG    EQU 48
LN_PRIO         EQU 9

CMD_RESET       EQU 1
CMD_NONSTD      EQU 9
ADCMD_ALLOCATE  EQU 32
ADIOB_PERVOL    EQU 4
ADIOB_SYNCCYCLE EQU 5
ADIOB_NOWAIT    EQU 6
ADIOB_WRITEMESSAGE EQU 7
ADIOERR_NOALLOCATION EQU -10
ADIOERR_ALLOCFAILED EQU -11
ADIOERR_CHANNELSTOLEN EQU -12

; --- état d'un canal ---
ACH_KEY         EQU 0                ; word : clé d'attribution (0 = libre)
ACH_PREC        EQU 2                ; byte : précédence
ACH_STOP        EQU 3                ; byte : arrêté par CMD_STOP
ACH_CUR         EQU 4                ; long : écriture en cours (0 = aucune)
ACH_CNT         EQU 8                ; word : débuts de cycle vus pour l'écriture en cours
ACH_TARGET      EQU 10               ; word : cycles à jouer (0 = infini)
ACH_NEXT        EQU 12               ; byte : déjà chargé pour l'après-dernier cycle (0 rien, 1 suivante, 2 silence)
ACH_PPV         EQU 13               ; byte : période/volume en attente (ADCMD_PERVOL synchronisé)
ACH_PPER        EQU 14               ; word
ACH_PVOL        EQU 16               ; word
ACH_LOCK        EQU 18               ; long : requête ADCMD_LOCK (0 = non verrouillé)
ACH_WQ          EQU 22               ; struct List : CMD_WRITE en file
ACH_CQ          EQU 36               ; struct List : ADCMD_WAITCYCLE en attente
ACH_INT         EQU 50               ; struct Interrupt (vecteur AUDn)
ACH_NUM         EQU 72               ; word : n° de canal
ACH_DEV         EQU 74               ; long : base du device
ACH_SIZE        EQU 78
; --- base du device ---
AD_KEYGEN       EQU LIB_SIZE         ; word : dernière clé générée
AD_SILENCE      EQU LIB_SIZE+2       ; long : mot nul en chip (alloué à la première écriture)
AD_ALLOCQ       EQU LIB_SIZE+6       ; struct List : ADCMD_ALLOCATE en attente
AD_CH           EQU LIB_SIZE+20      ; 4 x ACH_SIZE
AD_SIZE         EQU AD_CH+4*ACH_SIZE

AUD0LC          EQU CUSTOM+$0A0      ; canal n : +16*n ; LC.l, LEN.w (+4), PER.w (+6), VOL.w (+8)
ADKCON_A        EQU CUSTOM+$09E
DMACON_A        EQU CUSTOM+$096
INTB_AUD0       EQU 7
DMAF_MASTER_A   EQU $0200

        EVEN
audio_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    audio_romtag
        dc.l    audio_end
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,40
        dc.l    audio_name
        dc.l    audio_name
        dc.l    audio_inittab
audio_name:
        dc.b    "audio.device",0
        EVEN
audio_inittab:
        dc.l    AD_SIZE
        dc.l    audio_vectors
        dc.l    audio_datatab
        dc.l    audio_initfunc
audio_vectors:
        dc.l    ad_open              ; -6
        dc.l    ad_close             ; -12
        dc.l    ad_expunge           ; -18
        dc.l    ad_expunge           ; -24
        dc.l    ad_beginio           ; -30
        dc.l    ad_abortio           ; -36
        dc.l    -1
audio_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)
        dc.w    $D000,LIB_VERSION,34
        dc.b    0
        EVEN

; initFunc (d0 = base) : état vierge. Le matériel n'est touché qu'à la première attribution (CMD_RESET du canal).
audio_initfunc:
        movem.l d2/a2,-(sp)
        move.l  d0,a2
        lea     audio_name(pc),a0
        move.l  a0,LN_NAME(a2)
        lea     AD_KEYGEN(a2),a0
        move.w  #(AD_SIZE-AD_KEYGEN)/2-1,d1
.ai_clr:
        clr.w   (a0)+
        dbra    d1,.ai_clr
        lea     AD_ALLOCQ(a2),a0
        bsr     ad_newlist
        lea     AD_CH(a2),a1
        moveq   #0,d2
.ai_ch:
        move.w  d2,ACH_NUM(a1)
        move.l  a2,ACH_DEV(a1)
        move.b  #-128,ACH_PREC(a1)
        lea     ACH_WQ(a1),a0
        bsr     ad_newlist
        lea     ACH_CQ(a1),a0
        bsr     ad_newlist
        move.b  #NT_INTERRUPT,ACH_INT+LN_TYPE(a1)
        move.l  a1,ACH_INT+IS_DATA(a1)
        lea     ach_int(pc),a0
        move.l  a0,ACH_INT+IS_CODE(a1)
        lea     ACH_SIZE(a1),a1
        addq.w  #1,d2
        cmp.w   #4,d2
        bcs.s   .ai_ch
        move.l  a2,d0
        movem.l (sp)+,d2/a2
        rts

ad_newlist:
        move.l  a0,8(a0)
        clr.l   4(a0)
        addq.l  #4,a0
        move.l  a0,-4(a0)
        rts

ad_expunge:
        moveq   #0,d0
        rts

; OpenDevice(unité d0 ignorée, ioreq a1, flags d1 ignorés) : clé chargée, attribution sans attente si ioa_Length.
ad_open:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a1,a3
        move.l  ($4).w,a6
        addq.w  #1,LIB_OPENCNT(a5)
        clr.b   IO_ERROR(a3)
        jsr     LVO_DISABLE(a6)
        tst.l   IOA_LENGTH(a3)
        bne.s   .ao_alloc
        bsr     ad_needkey
        bra.s   .ao_out
.ao_alloc:
        bsr     ad_tryalloc
        tst.l   d0
        beq.s   .ao_out
        move.b  #ADIOERR_ALLOCFAILED,IO_ERROR(a3)
        clr.l   IO_UNIT(a3)
        moveq   #-1,d0
        move.l  d0,IO_DEVICE(a3)
        subq.w  #1,LIB_OPENCNT(a5)
.ao_out:
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,d2-d7/a2-a6
        rts

; CloseDevice(ioreq a1) : libère les canaux de io_Unit tenus avec la clé, puis io_Device = -1, io_Unit = 0.
ad_close:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a1,a3
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        lea     ach_free(pc),a2
        bsr     ad_forchan
        bsr     ad_retry
        jsr     LVO_ENABLE(a6)
        clr.b   IO_ERROR(a3)
        moveq   #-1,d0
        move.l  d0,IO_DEVICE(a3)
        clr.l   IO_UNIT(a3)
        subq.w  #1,LIB_OPENCNT(a5)
        moveq   #0,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; BeginIO(ioreq a1, device a6). Chaque commande tourne sous Disable avec a3 = ioreq, a5 = device, a6 = SysBase ;
; elle rend d0 = 0 (terminée : réponse sauf IOF_QUICK) ou 1 (asynchrone : IOF_QUICK effacé, réponse plus tard).
ad_beginio:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a1,a3
        move.l  ($4).w,a6
        clr.b   IO_ERROR(a3)
        jsr     LVO_DISABLE(a6)
        move.w  IO_COMMAND(a3),d0
        cmp.w   #ADCMD_ALLOCATE,d0
        bne.s   .ab_tab
        bsr     ad_allocate
        bra.s   .ab_end
.ab_tab:
        subq.w  #1,d0
        cmp.w   #CMD_NONSTD+5,d0
        bcc.s   .ab_nocmd
        add.w   d0,d0
        move.w  ad_cmdtab(pc,d0.w),d0
        jsr     ad_cmdtab(pc,d0.w)
        bra.s   .ab_end
.ab_nocmd:
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
        moveq   #0,d0
.ab_end:
        tst.l   d0
        beq.s   .ab_sync
        bclr    #0,IO_FLAGS(a3)
        bra.s   .ab_out
.ab_sync:
        btst    #0,IO_FLAGS(a3)
        bne.s   .ab_out
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
.ab_out:
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,d2-d7/a2-a6
        rts
ad_cmdtab:
        dc.w    ad_reset-ad_cmdtab   ; 1 CMD_RESET
        dc.w    ad_read-ad_cmdtab    ; 2 CMD_READ
        dc.w    ad_write-ad_cmdtab   ; 3 CMD_WRITE
        dc.w    ad_nop-ad_cmdtab     ; 4 CMD_UPDATE
        dc.w    ad_nop-ad_cmdtab     ; 5 CMD_CLEAR
        dc.w    ad_stop-ad_cmdtab    ; 6 CMD_STOP
        dc.w    ad_start-ad_cmdtab   ; 7 CMD_START
        dc.w    ad_flush-ad_cmdtab   ; 8 CMD_FLUSH
        dc.w    ad_free-ad_cmdtab    ; 9 ADCMD_FREE
        dc.w    ad_setprec-ad_cmdtab ; 10 ADCMD_SETPREC
        dc.w    ad_finish-ad_cmdtab  ; 11 ADCMD_FINISH
        dc.w    ad_pervol-ad_cmdtab  ; 12 ADCMD_PERVOL
        dc.w    ad_lock-ad_cmdtab    ; 13 ADCMD_LOCK
        dc.w    ad_waitcycle-ad_cmdtab ; 14 ADCMD_WAITCYCLE

; --- commandes multi-canaux : ad_forchan applique l'opération a2 à chaque canal de io_Unit dont la clé est
; celle de la requête (a4 = canal, d7 = n°) ; les autres sortent de io_Unit avec ADIOERR_NOALLOCATION. ---
ad_nop:
        lea     ach_nop(pc),a2
        bra.s   ad_multi
ad_reset:
        lea     ach_reset(pc),a2
        bra.s   ad_multi
ad_stop:
        lea     ach_stop(pc),a2
        bra.s   ad_multi
ad_start:
        lea     ach_start(pc),a2
        bra.s   ad_multi
ad_flush:
        lea     ach_flush(pc),a2
        bra.s   ad_multi
ad_finish:
        lea     ach_finish(pc),a2
        bra.s   ad_multi
ad_pervol:
        lea     ach_pervol(pc),a2
ad_multi:
        bsr     ad_forchan
        moveq   #0,d0
        rts
ad_free:
        lea     ach_free(pc),a2
        bsr     ad_forchan
        bsr     ad_retry
        moveq   #0,d0
        rts
ad_setprec:
        lea     ach_setprec(pc),a2
        bsr     ad_forchan
        bsr     ad_retry
        moveq   #0,d0
        rts
; ADCMD_LOCK : asynchrone si la clé est bonne (rendu quand tous ses canaux sont libérés, ou volé).
ad_lock:
        lea     ach_lock(pc),a2
        bsr     ad_forchan
        moveq   #0,d0
        tst.b   IO_ERROR(a3)
        bne.s   .al_r
        tst.b   IO_UNITB(a3)
        beq.s   .al_r
        moveq   #1,d0
.al_r:
        rts

ad_forchan:
        moveq   #0,d6                ; d6 = canaux traités
        lea     AD_CH(a5),a4
        moveq   #0,d7
.fc_lp:
        btst    d7,IO_UNITB(a3)
        beq.s   .fc_next
        move.w  ACH_KEY(a4),d0
        beq.s   .fc_bad
        cmp.w   IOA_ALLOCKEY(a3),d0
        bne.s   .fc_bad
        bset    d7,d6
        jsr     (a2)
        bra.s   .fc_next
.fc_bad:
        move.b  #ADIOERR_NOALLOCATION,IO_ERROR(a3)
.fc_next:
        lea     ACH_SIZE(a4),a4
        addq.w  #1,d7
        cmp.w   #4,d7
        bcs.s   .fc_lp
        move.b  d6,IO_UNITB(a3)
        rts

; ad_single : premier canal de io_Unit -> a4 (clé vérifiée), io_Unit réduit à ce canal. d0 = 0 si valable.
ad_single:
        lea     AD_CH(a5),a4
        moveq   #0,d7
.sg_lp:
        btst    d7,IO_UNITB(a3)
        bne.s   .sg_have
        lea     ACH_SIZE(a4),a4
        addq.w  #1,d7
        cmp.w   #4,d7
        bcs.s   .sg_lp
        bra.s   .sg_bad
.sg_have:
        move.w  ACH_KEY(a4),d0
        beq.s   .sg_bad
        cmp.w   IOA_ALLOCKEY(a3),d0
        bne.s   .sg_bad
        moveq   #0,d0
        bset    d7,d0
        move.b  d0,IO_UNITB(a3)
        moveq   #0,d0
        rts
.sg_bad:
        move.b  #ADIOERR_NOALLOCATION,IO_ERROR(a3)
        clr.b   IO_UNITB(a3)
        moveq   #-1,d0
        rts

; CMD_READ : ioa_Data = écriture en cours du canal (0 si aucune).
ad_read:
        bsr.s   ad_single
        bne.s   .ar_r
        move.l  ACH_CUR(a4),IOA_DATA(a3)
.ar_r:
        moveq   #0,d0
        rts

; ADCMD_WAITCYCLE : attend la fin du cycle en cours s'il y a une écriture, sinon répond tout de suite.
ad_waitcycle:
        bsr.s   ad_single
        bne.s   .aw_sync
        tst.l   ACH_CUR(a4)
        beq.s   .aw_sync
        lea     ACH_CQ(a4),a0
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)
        moveq   #1,d0
        rts
.aw_sync:
        moveq   #0,d0
        rts

; CMD_WRITE : file d'écriture du canal ; démarre tout de suite si le canal est inactif et non arrêté.
ad_write:
        bsr.s   ad_single
        bne.s   .wr_sync
        tst.l   AD_SILENCE(a5)
        bne.s   .wr_q
        moveq   #8,d0
        move.l  #MEMF_CHIP|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,AD_SILENCE(a5)
        bne.s   .wr_q
        move.b  #IOERR_ABORTED,IO_ERROR(a3)
.wr_sync:
        moveq   #0,d0
        rts
.wr_q:
        lea     ACH_WQ(a4),a0
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)
        tst.l   ACH_CUR(a4)
        beq.s   .wr_go
        cmp.b   #2,ACH_NEXT(a4)      ; dernier cycle déjà lancé avec silence derrière : enchaîner sur celle-ci
        bne.s   .wr_async
        move.l  a3,a0
        bsr     ach_load
        move.b  #1,ACH_NEXT(a4)
        bra.s   .wr_async
.wr_go:
        bsr     ach_startnext
.wr_async:
        moveq   #1,d0
        rts

; ADCMD_ALLOCATE.
ad_allocate:
        tst.l   IOA_LENGTH(a3)
        bne.s   .aa_try
        bsr     ad_needkey
        clr.l   IO_UNIT(a3)
        moveq   #0,d0
        rts
.aa_try:
        bsr     ad_tryalloc
        tst.l   d0
        beq.s   .aa_r
        cmp.l   #1,d0
        bne.s   .aa_wait             ; canaux verrouillés à libérer : attendre même en ADIOF_NOWAIT
        btst    #ADIOB_NOWAIT,IO_FLAGS(a3)
        beq.s   .aa_wait
        move.b  #ADIOERR_ALLOCFAILED,IO_ERROR(a3)
        clr.l   IO_UNIT(a3)
        moveq   #0,d0
.aa_r:
        rts
.aa_wait:
        lea     AD_ALLOCQ(a5),a0
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)
        moveq   #1,d0
        rts

; ad_needkey : ioa_AllocKey = nouvelle clé unique si nulle.
ad_needkey:
        tst.w   IOA_ALLOCKEY(a3)
        bne.s   .nk_r
        addq.w  #1,AD_KEYGEN(a5)
        bne.s   .nk_set
        addq.w  #1,AD_KEYGEN(a5)     ; jamais 0
.nk_set:
        move.w  AD_KEYGEN(a5),IOA_ALLOCKEY(a3)
.nk_r:
        rts

; ad_tryalloc (a3 = ioreq) -> d0 = 0 attribué (io_Unit, clé posés), 1 impossible, 2 attente de canaux verrouillés.
; d2 = combinaison retenue, d3 = sa précédence volée max, d4 = clé demandée, d5 = combinaison testée.
ad_tryalloc:
        move.w  IOA_ALLOCKEY(a3),d4
        moveq   #-1,d2
        move.w  #128,d3
        move.l  IOA_DATA(a3),a0
        move.l  IOA_LENGTH(a3),d1
        cmp.l   #16,d1
        bls.s   .ta_n
        moveq   #16,d1
.ta_n:
        subq.w  #1,d1
.ta_combo:
        moveq   #$0F,d5
        and.b   (a0)+,d5
        bsr     ad_maxprec           ; d0.w = précédence volée max (-129 si aucun vol)
        cmp.w   #-129,d0
        beq.s   .ta_free
        move.b  LN_PRIO(a3),d6
        ext.w   d6
        cmp.w   d6,d0
        bge.s   .ta_nextc            ; voler exige une précédence strictement inférieure
        cmp.w   d3,d0
        bge.s   .ta_nextc
        move.w  d0,d3
        move.w  d5,d2
.ta_nextc:
        dbra    d1,.ta_combo
        tst.w   d2
        bpl.s   .ta_steal
        moveq   #1,d0
        rts
.ta_free:
        move.w  d5,d2
        bra.s   .ta_take
.ta_steal:
        ; verrous dans la combinaison retenue : rendus avec ADIOERR_CHANNELSTOLEN, on attend leur libération
        moveq   #0,d5
        lea     AD_CH(a5),a4
        moveq   #0,d7
.ta_lk:
        btst    d7,d2
        beq.s   .ta_lknext
        move.l  ACH_LOCK(a4),d0
        beq.s   .ta_lknext
        move.l  d0,a1
        clr.l   ACH_LOCK(a4)
        move.b  #ADIOERR_CHANNELSTOLEN,IO_ERROR(a1)
        jsr     LVO_REPLYMSG(a6)
        moveq   #1,d5
.ta_lknext:
        lea     ACH_SIZE(a4),a4
        addq.w  #1,d7
        cmp.w   #4,d7
        bcs.s   .ta_lk
        tst.w   d5
        beq.s   .ta_take
        moveq   #2,d0
        rts
.ta_take:
        bsr     ad_needkey
        move.w  IOA_ALLOCKEY(a3),d4
        lea     AD_CH(a5),a4
        moveq   #0,d7
.ta_set:
        btst    d7,d2
        beq.s   .ta_setnext
        bsr     ach_reset            ; E/S d'un éventuel propriétaire volé : IOERR_ABORTED
        move.w  d4,ACH_KEY(a4)
        move.b  LN_PRIO(a3),ACH_PREC(a4)
.ta_setnext:
        lea     ACH_SIZE(a4),a4
        addq.w  #1,d7
        cmp.w   #4,d7
        bcs.s   .ta_set
        clr.l   IO_UNIT(a3)
        move.b  d2,IO_UNITB(a3)
        moveq   #0,d0
        rts

; ad_maxprec : d5 = combinaison, d4 = clé du demandeur -> d0.w = précédence max des canaux tenus par d'autres
; (-129 si aucun). Utilise d6/d7/a4.
ad_maxprec:
        move.w  #-129,d0
        lea     AD_CH(a5),a4
        moveq   #0,d7
.mp_lp:
        btst    d7,d5
        beq.s   .mp_next
        move.w  ACH_KEY(a4),d6
        beq.s   .mp_next
        cmp.w   d4,d6
        beq.s   .mp_next
        move.b  ACH_PREC(a4),d6
        ext.w   d6
        cmp.w   d0,d6
        ble.s   .mp_next
        move.w  d6,d0
.mp_next:
        lea     ACH_SIZE(a4),a4
        addq.w  #1,d7
        cmp.w   #4,d7
        bcs.s   .mp_lp
        rts

; ad_retry : retente chaque ADCMD_ALLOCATE en attente ; celles qui aboutissent sont rendues.
ad_retry:
        move.l  a3,-(sp)
        move.l  AD_ALLOCQ(a5),a3
.rt_lp:
        move.l  (a3),d0
        beq.s   .rt_out
        move.l  d0,-(sp)             ; successeur, avant un éventuel Remove
        bsr     ad_tryalloc
        tst.l   d0
        bne.s   .rt_next
        move.l  a3,a1
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
.rt_next:
        move.l  (sp)+,a3
        bra.s   .rt_lp
.rt_out:
        move.l  (sp)+,a3
        rts

; --- opérations par canal (a4 = canal, d7 = n°, a3 = requête, a5 = device, a6 = SysBase) ---
ach_nop:
        rts

ach_setprec:
        move.b  LN_PRIO(a3),ACH_PREC(a4)
        rts

ach_lock:
        move.l  a3,ACH_LOCK(a4)
        rts

; ach_free : remise à zéro, clé effacée ; un verrou perd ce canal et est rendu quand il n'en a plus.
ach_free:
        bsr.s   ach_reset
        clr.w   ACH_KEY(a4)
        move.b  #-128,ACH_PREC(a4)
        move.l  ACH_LOCK(a4),d0
        beq.s   .af_r
        clr.l   ACH_LOCK(a4)
        move.l  d0,a1
        bclr    d7,IO_UNITB(a1)
        tst.b   IO_UNITB(a1)
        bne.s   .af_r
        jsr     LVO_REPLYMSG(a6)
.af_r:
        rts

; ach_reset : registres audio et modulation à zéro, vecteur AUDn posé, E/S annulées, canal non arrêté.
ach_reset:
        bsr.s   ach_flush
        clr.b   ACH_STOP(a4)
        bsr     ach_regs
        clr.w   6(a0)                ; AUDnPER
        clr.w   8(a0)                ; AUDnVOL
        moveq   #0,d0
        bset    d7,d0
        move.w  d0,d1
        lsl.w   #4,d1
        or.w    d1,d0
        move.w  d0,ADKCON_A          ; USEn : modulations de/vers ce canal coupées
        moveq   #INTB_AUD0,d0
        add.w   d7,d0
        lea     ACH_INT(a4),a1
        jmp     LVO_SETINTVECTOR(a6)

; ach_flush : coupe le canal, rend l'écriture en cours, la file et les ADCMD_WAITCYCLE avec IOERR_ABORTED.
ach_flush:
        bsr     ach_off
        move.l  ACH_CUR(a4),d0
        beq.s   .fl_q
        clr.l   ACH_CUR(a4)
        move.l  d0,a1
        bsr     ach_abortreply
.fl_q:
        lea     ACH_WQ(a4),a0
        bsr.s   ach_abortlist
        lea     ACH_CQ(a4),a0
; ach_abortlist : a0 = liste -> chaque requête retirée et rendue avec IOERR_ABORTED.
ach_abortlist:
        move.l  a0,-(sp)
.al_lp:
        move.l  (sp),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .al_out
        move.l  d0,a1
        bsr.s   ach_abortreply
        bra.s   .al_lp
.al_out:
        addq.l  #4,sp
        rts
ach_abortreply:
        move.b  #IOERR_ABORTED,IO_ERROR(a1)
        jmp     LVO_REPLYMSG(a6)

ach_stop:
        move.b  #1,ACH_STOP(a4)
        bra     ach_off

; ach_start : un canal arrêté reprend son écriture depuis le début, ou démarre la suivante de la file.
ach_start:
        tst.b   ACH_STOP(a4)
        beq.s   .st_r
        clr.b   ACH_STOP(a4)
        move.l  ACH_CUR(a4),d0
        beq     ach_startnext
        move.l  d0,a0
        bra     ach_play
.st_r:
        rts

; ach_finish : arrête l'écriture en cours, tout de suite (IOERR_ABORTED) ou à la fin de son cycle (sans erreur).
ach_finish:
        move.l  ACH_CUR(a4),d0
        beq.s   .fi_r
        btst    #ADIOB_SYNCCYCLE,IO_FLAGS(a3)
        beq.s   .fi_now
        move.w  ACH_CNT(a4),d0
        beq.s   .fi_now              ; aucun cycle commencé : rien à laisser finir
        move.w  d0,ACH_TARGET(a4)    ; le prochain début de cycle termine l'écriture
        tst.b   ACH_NEXT(a4)
        bne.s   .fi_r
        bra     ach_loadafter
.fi_now:
        bsr     ach_off
        move.l  ACH_CUR(a4),a1
        clr.l   ACH_CUR(a4)
        bsr.s   ach_abortreply
        bra     ach_startnext
.fi_r:
        rts

; ach_pervol : période/volume de l'écriture en cours, tout de suite ou au prochain début de cycle.
ach_pervol:
        tst.l   ACH_CUR(a4)
        beq.s   .pv_r
        btst    #ADIOB_SYNCCYCLE,IO_FLAGS(a3)
        bne.s   .pv_sync
        bsr     ach_regs
        move.w  IOA_PERIOD(a3),6(a0)
        move.w  IOA_VOLUME(a3),8(a0)
        rts
.pv_sync:
        move.w  IOA_PERIOD(a3),ACH_PPER(a4)
        move.w  IOA_VOLUME(a3),ACH_PVOL(a4)
        move.b  #1,ACH_PPV(a4)
.pv_r:
        rts

; ach_regs : a0 = registres matériels du canal d7 (préserve d0/d1).
ach_regs:
        move.w  d7,a0
        add.w   a0,a0
        add.w   a0,a0
        add.w   a0,a0
        add.w   a0,a0
        add.l   #AUD0LC,a0
        rts

; ach_off : DMA et interruption du canal coupés, état d'enchaînement effacé.
ach_off:
        moveq   #0,d0
        bset    d7,d0
        move.w  d0,DMACON_A
        lsl.w   #INTB_AUD0,d0
        move.w  d0,INTENA
        move.w  d0,INTREQ
        clr.b   ACH_NEXT(a4)
        clr.b   ACH_PPV(a4)
        rts

; ach_startnext : canal inactif et non arrêté -> joue la première écriture de la file.
ach_startnext:
        tst.b   ACH_STOP(a4)
        bne.s   .sn_r
        tst.l   ACH_CUR(a4)
        bne.s   .sn_r
        lea     ACH_WQ(a4),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .sn_r
        move.l  d0,a0
        bra.s   ach_play
.sn_r:
        rts

; ach_play : a0 = écriture -> devient courante et démarre (DMA + interruption du canal).
ach_play:
        move.l  a0,ACH_CUR(a4)
        clr.w   ACH_CNT(a4)
        move.w  IOA_CYCLES(a0),ACH_TARGET(a4)
        clr.b   ACH_NEXT(a4)
        clr.b   ACH_PPV(a4)
        bsr.s   ach_begin
        moveq   #0,d0
        bset    d7,d0
        lsl.w   #INTB_AUD0,d0
        move.w  d0,INTREQ
        or.w    #INTF_SETCLR,d0
        move.w  d0,INTENA
        moveq   #0,d0
        bset    d7,d0
        or.w    #INTF_SETCLR|DMAF_MASTER_A,d0
        move.w  d0,DMACON_A
        rts

; ach_begin : a0 = écriture qui commence -> position/longueur (+ période/volume si ADIOF_PERVOL), message de
; démarrage (ADIOF_WRITEMESSAGE). Préserve a0.
ach_begin:
        move.l  a0,-(sp)
        bsr.s   ach_load
        move.l  (sp),a1
        btst    #ADIOB_PERVOL,IO_FLAGS(a1)
        beq.s   .bg_msg
        bsr     ach_regs
        move.w  IOA_PERIOD(a1),6(a0)
        move.w  IOA_VOLUME(a1),8(a0)
.bg_msg:
        btst    #ADIOB_WRITEMESSAGE,IO_FLAGS(a1)
        beq.s   .bg_r
        lea     IOA_WRITEMSG(a1),a1
        jsr     LVO_REPLYMSG(a6)
.bg_r:
        move.l  (sp)+,a0
        rts

; ach_load : a0 = écriture -> AUDnLC / AUDnLEN (pris en compte au prochain rechargement de Paula).
ach_load:
        move.l  a0,a1
        bsr     ach_regs
        move.l  IOA_DATA(a1),(a0)
        move.l  IOA_LENGTH(a1),d0
        lsr.l   #1,d0
        move.w  d0,4(a0)             ; 65536 mots -> 0
        rts

; ach_loadafter : charge ce qui suit le dernier cycle : la prochaine écriture de la file, sinon le silence.
ach_loadafter:
        move.l  ACH_WQ(a4),a0
        tst.l   (a0)
        beq.s   .la_sil
        bsr.s   ach_load
        move.b  #1,ACH_NEXT(a4)
        rts
.la_sil:
        bsr     ach_regs
        move.l  AD_SILENCE(a5),(a0)
        move.w  #1,4(a0)
        move.b  #2,ACH_NEXT(a4)
        rts

; ach_int : interruption AUDn (a1 = canal). Un début de cycle : fin du précédent (ADCMD_WAITCYCLE rendues),
; écriture terminée rendue au début qui suit son dernier cycle, préchargement au début du dernier cycle.
ach_int:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a4
        move.l  ACH_DEV(a4),a5
        move.w  ACH_NUM(a4),d7
        move.l  ($4).w,a6
        moveq   #0,d0
        bset    d7,d0
        lsl.w   #INTB_AUD0,d0
        move.w  d0,INTREQ
        tst.l   ACH_CUR(a4)
        bne.s   .in_cur
        move.w  d0,INTENA            ; aucune écriture : interruption orpheline coupée
        bra     .in_out
.in_cur:
        addq.w  #1,ACH_CNT(a4)
        tst.b   ACH_PPV(a4)
        beq.s   .in_cq
        clr.b   ACH_PPV(a4)
        bsr     ach_regs
        move.w  ACH_PPER(a4),6(a0)
        move.w  ACH_PVOL(a4),8(a0)
.in_cq:
        cmp.w   #1,ACH_CNT(a4)
        beq.s   .in_fin
        move.l  a4,a0
        add.w   #ACH_CQ,a0
        bsr     ach_replylist        ; fin d'un cycle
.in_fin:
        move.w  ACH_TARGET(a4),d0
        beq     .in_out              ; cycles infinis
        addq.w  #1,d0
        cmp.w   ACH_CNT(a4),d0
        bne.s   .in_last
        move.l  ACH_CUR(a4),a1       ; dernier cycle achevé : écriture rendue
        clr.l   ACH_CUR(a4)
        clr.b   IO_ERROR(a1)
        jsr     LVO_REPLYMSG(a6)
        cmp.b   #1,ACH_NEXT(a4)
        bne.s   .in_stop
        lea     ACH_WQ(a4),a0        ; la suivante joue déjà (préchargée)
        jsr     LVO_REMHEAD(a6)
        move.l  d0,a0
        move.l  a0,ACH_CUR(a4)
        move.w  #1,ACH_CNT(a4)
        move.w  IOA_CYCLES(a0),ACH_TARGET(a4)
        clr.b   ACH_NEXT(a4)
        move.l  a0,a1
        btst    #ADIOB_PERVOL,IO_FLAGS(a1)
        beq.s   .in_wm
        bsr     ach_regs
        move.w  IOA_PERIOD(a1),6(a0)
        move.w  IOA_VOLUME(a1),8(a0)
.in_wm:
        btst    #ADIOB_WRITEMESSAGE,IO_FLAGS(a1)
        beq.s   .in_last
        lea     IOA_WRITEMSG(a1),a1
        jsr     LVO_REPLYMSG(a6)
        bra.s   .in_last
.in_stop:
        bsr     ach_off
        bsr     ach_startnext
        bra.s   .in_out
.in_last:
        move.w  ACH_TARGET(a4),d0
        beq.s   .in_out
        cmp.w   ACH_CNT(a4),d0
        bne.s   .in_out
        tst.b   ACH_NEXT(a4)
        bne.s   .in_out
        bsr     ach_loadafter        ; dernier cycle commencé : préparer la suite
.in_out:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ach_replylist : a0 = liste -> chaque requête retirée et rendue sans erreur.
ach_replylist:
        move.l  a0,-(sp)
.rl_lp:
        move.l  (sp),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .rl_out
        move.l  d0,a1
        clr.b   IO_ERROR(a1)
        jsr     LVO_REPLYMSG(a6)
        bra.s   .rl_lp
.rl_out:
        addq.l  #4,sp
        rts

; AbortIO(ioreq a1, device a6) : écriture en cours -> arrêtée ; requête en file -> retirée ; rendue IOERR_ABORTED.
ad_abortio:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        move.l  a1,a3
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        lea     AD_CH(a5),a4
        moveq   #0,d7
.ab_ch:
        cmp.l   ACH_CUR(a4),a3
        bne.s   .ab_lists
        bsr     ach_off
        clr.l   ACH_CUR(a4)
        move.l  a3,a1
        bsr     ach_abortreply
        bsr     ach_startnext
        bra.s   .ab_out
.ab_lists:
        lea     ACH_WQ(a4),a0
        bsr.s   ad_inlist
        beq.s   .ab_rem
        lea     ACH_CQ(a4),a0
        bsr.s   ad_inlist
        beq.s   .ab_rem
        lea     ACH_SIZE(a4),a4
        addq.w  #1,d7
        cmp.w   #4,d7
        bcs.s   .ab_ch
        lea     AD_ALLOCQ(a5),a0
        bsr.s   ad_inlist
        bne.s   .ab_out
.ab_rem:
        move.l  a3,a1
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1
        bsr     ach_abortreply
.ab_out:
        jsr     LVO_ENABLE(a6)
        moveq   #0,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ad_inlist : a0 = liste, a3 = requête -> Z si la requête y est.
ad_inlist:
        move.l  (a0),a0
.il_lp:
        tst.l   (a0)
        beq.s   .il_no
        cmp.l   a0,a3
        beq.s   .il_r
        move.l  (a0),a0
        bra.s   .il_lp
.il_no:
        moveq   #1,d0                ; Z = 0
.il_r:
        rts
audio_end:
