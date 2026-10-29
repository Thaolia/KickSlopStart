; src/exec/audio.s — audio.device: allocation of the 4 Paula channels and sample playback by DMA.
;
; ALLOCATION: each channel carries a key (0 = free) and a precedence. ADCMD_ALLOCATE tries the combinations
; (ioa_Data) in order: the first one with no channel to steal wins, otherwise the one that steals the lowest
; precedences, always strictly lower than ln_Pri. A stolen channel loses its I/O (IOERR_ABORTED) and its key changes.
; A locked channel (ADCMD_LOCK) is not stolen directly: its lock is returned with ADIOERR_CHANNELSTOLEN and
; the allocation waits until the channel is freed. Pending allocations are retried at each ADCMD_FREE,
; ADCMD_SETPREC and CloseDevice.
; PLAYBACK: Paula raises the AUDn interrupt each time it reloads position and length, i.e. at the
; start of each pass (cycle) through the sample. The ACH_CNT counter counts these starts; when the last
; cycle starts, we already load the next sample of the queue (gapless chaining) or a silence word;
; at the following start, the completed write is returned and the next one becomes current.
; Accepted deviations: commands are executed directly under Disable (no separate command queue);
; immediate ADCMD_FINISH returns the write with IOERR_ABORTED, synchronised (ADIOF_SYNCCYCLE) without error.
; IMPLEMENTATION track ("clean"): AutoDocs audio.device + devices/audio.h + HRM (Paula audio). NO ROM reading.

                include "exec.i"

; --- struct IOAudio (devices/audio.h) ---
IO_UNITB        EQU IO_UNIT+3        ; low byte of io_Unit = channel map
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

; --- channel state ---
ACH_KEY         EQU 0                ; word: allocation key (0 = free)
ACH_PREC        EQU 2                ; byte: precedence
ACH_STOP        EQU 3                ; byte: stopped by CMD_STOP
ACH_CUR         EQU 4                ; long: write in progress (0 = none)
ACH_CNT         EQU 8                ; word: cycle starts seen for the write in progress
ACH_TARGET      EQU 10               ; word: cycles to play (0 = infinite)
ACH_NEXT        EQU 12               ; byte: already loaded for after the last cycle (0 nothing, 1 next, 2 silence)
ACH_PPV         EQU 13               ; byte: pending period/volume (synchronised ADCMD_PERVOL)
ACH_PPER        EQU 14               ; word
ACH_PVOL        EQU 16               ; word
ACH_LOCK        EQU 18               ; long: ADCMD_LOCK request (0 = not locked)
ACH_WQ          EQU 22               ; struct List: queued CMD_WRITEs
ACH_CQ          EQU 36               ; struct List: pending ADCMD_WAITCYCLEs
ACH_INT         EQU 50               ; struct Interrupt (AUDn vector)
ACH_NUM         EQU 72               ; word: channel number
ACH_DEV         EQU 74               ; long: device base
ACH_SIZE        EQU 78
; --- device base ---
AD_KEYGEN       EQU LIB_SIZE         ; word: last generated key
AD_SILENCE      EQU LIB_SIZE+2       ; long: null word in chip (allocated at the first write)
AD_ALLOCQ       EQU LIB_SIZE+6       ; struct List: pending ADCMD_ALLOCATEs
AD_CH           EQU LIB_SIZE+20      ; 4 x ACH_SIZE
AD_SIZE         EQU AD_CH+4*ACH_SIZE

AUD0LC          EQU CUSTOM+$0A0      ; channel n: +16*n; LC.l, LEN.w (+4), PER.w (+6), VOL.w (+8)
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

; initFunc (d0 = base): blank state. The hardware is only touched at the first allocation (CMD_RESET of the channel).
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

; OpenDevice(unit d0 ignored, ioreq a1, flags d1 ignored): key loaded, allocation without waiting if ioa_Length.
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

; CloseDevice(ioreq a1): frees the channels of io_Unit held with the key, then io_Device = -1, io_Unit = 0.
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

; BeginIO(ioreq a1, device a6). Each command runs under Disable with a3 = ioreq, a5 = device, a6 = SysBase;
; it returns d0 = 0 (completed: reply unless IOF_QUICK) or 1 (asynchronous: IOF_QUICK cleared, reply later).
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

; --- multi-channel commands: ad_forchan applies operation a2 to each channel of io_Unit whose key is
; that of the request (a4 = channel, d7 = number); the others leave io_Unit with ADIOERR_NOALLOCATION. ---
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
; ADCMD_LOCK: asynchronous if the key is right (returned when all its channels are freed, or stolen).
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
        moveq   #0,d6                ; d6 = channels processed
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

; ad_single: first channel of io_Unit -> a4 (key checked), io_Unit reduced to that channel. d0 = 0 if valid.
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

; CMD_READ: ioa_Data = write in progress of the channel (0 if none).
ad_read:
        bsr.s   ad_single
        bne.s   .ar_r
        move.l  ACH_CUR(a4),IOA_DATA(a3)
.ar_r:
        moveq   #0,d0
        rts

; ADCMD_WAITCYCLE: waits for the end of the current cycle if there is a write, otherwise replies at once.
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

; CMD_WRITE: write queue of the channel; starts at once if the channel is idle and not stopped.
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
        cmp.b   #2,ACH_NEXT(a4)      ; last cycle already started with silence behind: chain onto this one
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
        bne.s   .aa_wait             ; locked channels to free: wait even with ADIOF_NOWAIT
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

; ad_needkey: ioa_AllocKey = new unique key if null.
ad_needkey:
        tst.w   IOA_ALLOCKEY(a3)
        bne.s   .nk_r
        addq.w  #1,AD_KEYGEN(a5)
        bne.s   .nk_set
        addq.w  #1,AD_KEYGEN(a5)     ; never 0
.nk_set:
        move.w  AD_KEYGEN(a5),IOA_ALLOCKEY(a3)
.nk_r:
        rts

; ad_tryalloc (a3 = ioreq) -> d0 = 0 allocated (io_Unit, key set), 1 impossible, 2 waiting for locked channels.
; d2 = chosen combination, d3 = its max stolen precedence, d4 = requested key, d5 = combination being tested.
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
        bsr     ad_maxprec           ; d0.w = max stolen precedence (-129 if no theft)
        cmp.w   #-129,d0
        beq.s   .ta_free
        move.b  LN_PRIO(a3),d6
        ext.w   d6
        cmp.w   d6,d0
        bge.s   .ta_nextc            ; stealing requires a strictly lower precedence
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
        ; locks in the chosen combination: returned with ADIOERR_CHANNELSTOLEN, we wait for their release
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
        bsr     ach_reset            ; I/O of a possible stolen owner: IOERR_ABORTED
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

; ad_maxprec: d5 = combination, d4 = requester's key -> d0.w = max precedence of the channels held by others
; (-129 if none). Uses d6/d7/a4.
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

; ad_retry: retries each pending ADCMD_ALLOCATE; those that succeed are returned.
ad_retry:
        move.l  a3,-(sp)
        move.l  AD_ALLOCQ(a5),a3
.rt_lp:
        move.l  (a3),d0
        beq.s   .rt_out
        move.l  d0,-(sp)             ; successor, before a possible Remove
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

; --- per-channel operations (a4 = channel, d7 = number, a3 = request, a5 = device, a6 = SysBase) ---
ach_nop:
        rts

ach_setprec:
        move.b  LN_PRIO(a3),ACH_PREC(a4)
        rts

ach_lock:
        move.l  a3,ACH_LOCK(a4)
        rts

; ach_free: reset, key cleared; a lock loses this channel and is returned when it has none left.
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

; ach_reset: audio and modulation registers at zero, AUDn vector set, I/O cancelled, channel not stopped.
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
        move.w  d0,ADKCON_A          ; USEn: modulations from/to this channel cut
        moveq   #INTB_AUD0,d0
        add.w   d7,d0
        lea     ACH_INT(a4),a1
        jmp     LVO_SETINTVECTOR(a6)

; ach_flush: cuts the channel, returns the write in progress, the queue and the ADCMD_WAITCYCLEs with IOERR_ABORTED.
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
; ach_abortlist: a0 = list -> each request removed and returned with IOERR_ABORTED.
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

; ach_start: a stopped channel resumes its write from the start, or starts the next one in the queue.
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

; ach_finish: stops the write in progress, at once (IOERR_ABORTED) or at the end of its cycle (without error).
ach_finish:
        move.l  ACH_CUR(a4),d0
        beq.s   .fi_r
        btst    #ADIOB_SYNCCYCLE,IO_FLAGS(a3)
        beq.s   .fi_now
        move.w  ACH_CNT(a4),d0
        beq.s   .fi_now              ; no cycle started: nothing to let finish
        move.w  d0,ACH_TARGET(a4)    ; the next cycle start ends the write
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

; ach_pervol: period/volume of the write in progress, at once or at the next cycle start.
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

; ach_regs: a0 = hardware registers of channel d7 (preserves d0/d1).
ach_regs:
        move.w  d7,a0
        add.w   a0,a0
        add.w   a0,a0
        add.w   a0,a0
        add.w   a0,a0
        add.l   #AUD0LC,a0
        rts

; ach_off: DMA and interrupt of the channel cut, chaining state cleared.
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

; ach_startnext: idle and not stopped channel -> plays the first write of the queue.
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

; ach_play: a0 = write -> becomes current and starts (DMA + channel interrupt).
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

; ach_begin: a0 = write that starts -> position/length (+ period/volume if ADIOF_PERVOL), start message
; (ADIOF_WRITEMESSAGE). Preserves a0.
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

; ach_load: a0 = write -> AUDnLC / AUDnLEN (taken into account at Paula's next reload).
ach_load:
        move.l  a0,a1
        bsr     ach_regs
        move.l  IOA_DATA(a1),(a0)
        move.l  IOA_LENGTH(a1),d0
        lsr.l   #1,d0
        move.w  d0,4(a0)             ; 65536 words -> 0
        rts

; ach_loadafter: loads what follows the last cycle: the next write of the queue, otherwise silence.
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

; ach_int: AUDn interrupt (a1 = channel). A cycle start: end of the previous one (ADCMD_WAITCYCLEs returned),
; completed write returned at the start following its last cycle, preloading at the start of the last cycle.
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
        move.w  d0,INTENA            ; no write: orphan interrupt cut
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
        bsr     ach_replylist        ; end of a cycle
.in_fin:
        move.w  ACH_TARGET(a4),d0
        beq     .in_out              ; infinite cycles
        addq.w  #1,d0
        cmp.w   ACH_CNT(a4),d0
        bne.s   .in_last
        move.l  ACH_CUR(a4),a1       ; last cycle completed: write returned
        clr.l   ACH_CUR(a4)
        clr.b   IO_ERROR(a1)
        jsr     LVO_REPLYMSG(a6)
        cmp.b   #1,ACH_NEXT(a4)
        bne.s   .in_stop
        lea     ACH_WQ(a4),a0        ; the next one is already playing (preloaded)
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
        bsr     ach_loadafter        ; last cycle started: prepare what follows
.in_out:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ach_replylist: a0 = list -> each request removed and returned without error.
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

; AbortIO(ioreq a1, device a6): write in progress -> stopped; queued request -> removed; returned IOERR_ABORTED.
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

; ad_inlist: a0 = list, a3 = request -> Z if the request is in it.
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
