; src/exec/trackdisk.s — trackdisk.device (B1: resident skeleton + unit validation).
; 2nd DEVICE of the project (after timer.device). RTF_AUTOINIT ROMTag (pri 20) -> AUTOINIT path of InitResident
; (MakeLibrary + Enqueue DeviceList). V34 quirk: data table sets LN_TYPE + LIB_VERSION, init func sets LN_NAME.
;
; B1 delivers: the device EXISTS + validates its units (DF0-3). Real READING (CIA drive control, Paula disk DMA,
; MFM decoding, CMD_READ) comes in increments B2/B3/B4. Open(unit 0-3) -> success; unit >= 4 -> failure (OpenDevice
; convention: io_Error != 0, io_Device = 0). The B1 "units" are PLACEHOLDERS (reserved area per unit):
; a real trackdisk unit starts with a MsgPort (queue of the IORequests that BeginIO will enqueue) -> in B2 this
; area will become a struct Unit + MsgPort. The invariant locked by the M6T proof = "io_Unit points to the area of
; unit d0", NOT its size/contents (which will change).
;
; IMPLEMENTATION track ("clean"): AutoDocs trackdisk.device + exec + devices/trackdisk.i (public). NO ROM reading.

                include "exec.i"
                include "disk.i"

                xdef    td_read_track0
                xdef    td_read_track
                xdef    td_decode_track
                xdef    td_disk_present

; --- trackdisk constants (devices/trackdisk.i) + exec io errors (io.i) ---
NUMUNITS       EQU 4                 ; DF0..DF3
IOERR_BADLENGTH EQU -4               ; io_Offset/io_Length not a multiple of the sector size (M6z)
TDU_UNIT0      EQU LIB_SIZE          ; 34: start of the unit area (placeholder, -> Unit+MsgPort in B2)
TDU_UNITSZ     EQU 8                 ; bytes per unit (placeholder)
TDBASE_SIZE    EQU TDU_UNIT0+NUMUNITS*TDU_UNITSZ   ; 66: Library + 4 unit areas

; TD_NO_UNITCHECK=1 (RED): Open skips the unit number validation -> unit 4 (invalid) wrongly opens ->
; the "unit 4 fails" proof breaks -> "M6T TRACKDISK OK" absent. Isolates the unit validation. Default 0.
TD_NO_UNITCHECK EQU 0

; --- trackdisk.device ROMTag (scanned by build_reslist) ---
        EVEN
trackdisk_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    trackdisk_romtag     ; RT_MATCHTAG = self
        dc.l    trackdisk_end        ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,20   ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (20: trackdisk roadmap slot)
        dc.l    trackdisk_name       ; RT_NAME
        dc.l    trackdisk_name       ; RT_IDSTRING
        dc.l    trackdisk_inittab    ; RT_INIT -> AUTOINIT table
trackdisk_name:
        dc.b    "trackdisk.device",0
        EVEN
trackdisk_inittab:
        dc.l    TDBASE_SIZE          ; dataSize (Library + placeholder unit areas)
        dc.l    trackdisk_vectors    ; funcTable
        dc.l    trackdisk_datatab    ; dataTable (InitStruct)
        dc.l    trackdisk_initfunc   ; initFunc
trackdisk_vectors:                   ; ABSOLUTE table, standard device order, terminated by -1
        dc.l    trackdisk_open       ; LVO -6
        dc.l    trackdisk_close      ; LVO -12
        dc.l    trackdisk_expunge    ; LVO -18
        dc.l    trackdisk_null       ; LVO -24 (reserved)
        dc.l    trackdisk_beginio    ; LVO -30
        dc.l    trackdisk_abortio    ; LVO -36
        dc.l    -1
trackdisk_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)  ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34          ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(device a6, iorequest a1, unit d0, flags d1): validates the unit number (DF0-3). Success -> io_Unit = area of
; the unit, io_Device = base, io_Error = 0, OpenCnt++. Unit >= NUMUNITS -> failure (io_Error, io_Device = 0).
trackdisk_open:
                ifeq    TD_NO_UNITCHECK
        cmp.l   #NUMUNITS,d0
        bcc.s   .td_badunit          ; unit >= 4 (unsigned comparison) -> OpenDevice fails
                endc
        move.l  d0,d1                ; d1 = unit (flags no longer needed)
        lsl.l   #3,d1                ; unit * TDU_UNITSZ (8)
        lea     TDU_UNIT0(a6),a0
        add.l   d1,a0                ; a0 = &unit[unit]
        move.l  a0,IO_UNIT(a1)
        move.l  a6,IO_DEVICE(a1)     ; OpenDevice confirms the device in the request
        clr.b   IO_ERROR(a1)
        addq.w  #1,LIB_OPENCNT(a6)
        rts
.td_badunit:
        move.b  #IOERR_OPENFAIL,IO_ERROR(a1)
        clr.l   IO_DEVICE(a1)        ; io_Device = 0 -> OpenDevice failed (exec convention)
        rts

trackdisk_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
trackdisk_expunge:
        moveq   #0,d0                ; no expunge this milestone (resident base)
        rts
trackdisk_null:
        moveq   #0,d0
        rts

; BeginIO(device a6, iorequest a1): handles CMD_READ. Other commands -> IOERR_NOCMD. ReplyMsg if the request
; is NOT quick (B1 safeguard kept: otherwise DoIO waits forever). a6 = device base on entry/exit.
; M6z (prerequisite for D): MULTI-TRACK read. The byte offset is converted into (track, sector-in-track) via
; block = offset/512, track = block/11, sector = block%11; the loop reads each track touched (td_read_track +
; td_decode_track), copies up to the end of the track, and advances -> a request that CROSSES a track boundary
; is served in several reads (dos will read the filesystem beyond track 0). trackdisk contract: io_Offset
; and io_Length multiples of TD_SECTOR (512) -> IOERR_BADLENGTH guard otherwise; TD_DISKBYTES bound guard.
; LRU cache of TD_NCACHE decoded tracks (TD_CACHEBUF, allocated at the 1st CMD_READ; 1 slot if memory is short):
; a track only enters it if its 11 sectors have been decoded AND carry the requested number; flushed by /CHNG
; (td_check_change). The motor stays on between reads (td_motor_server turns it off after 2 s of inactivity).
; DEBT: a partially decoded track is not cached but its unreadable sectors return STALE
; bytes (no error) — "no bad-sector handling" debt; no impact on a clean disk.
trackdisk_beginio:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a2                ; a2 = ioreq
        bsr     td_lock
        clr.b   IO_ERROR(a2)
        move.w  IO_COMMAND(a2),d0
        cmp.w   #TD_FORMAT,d0        ; TD_FORMAT does not touch io_Actual (spec trackdisk-write-v34 §8, steps K and L)
        beq.s   .td_nact
        clr.l   IO_ACTUAL(a2)
.td_nact:
                ifeq    TD_READ_NOCMD
        cmp.w   #CMD_READ,d0
        beq.s   .td_read
                endc                 ; RED TD_READ_NOCMD: skips the recognition -> IOERR_NOCMD
        move.l  a6,a4                ; other commands: a4 = base, a6 = SysBase
        move.l  ($4).w,a6
        lea     td_cmdtab(pc),a0
.td_cmd:
        move.w  (a0)+,d1
        bmi.s   .td_nocmd
        move.w  (a0)+,d2
        cmp.w   d1,d0
        bne.s   .td_cmd
        lea     td_cmdtab(pc),a0
        jsr     0(a0,d2.w)           ; routine(a2 = request, a6 = SysBase)
        bra     .td_restore
.td_nocmd:
        move.b  #IOERR_NOCMD,IO_ERROR(a2)
        bra     .td_restore
.td_read:
        move.l  a6,a4                ; a4 = device base (saved; a6 -> SysBase for the exec calls)
        move.l  ($4).w,a6
        move.l  IO_OFFSET(a2),d3     ; d3 = current offset (bytes; advances per track)
        move.l  IO_LENGTH(a2),d2     ; d2 = remaining length (bytes)
        moveq   #0,d4               ; d4 = bytes transferred (accumulated io_Actual)
        ; alignment guard: offset AND length multiples of TD_SECTOR (512) — trackdisk contract
        move.l  d3,d0
        or.l    d2,d0
        and.l   #MFM_SECTSZ-1,d0
        beq.s   .td_aligned
        move.b  #IOERR_BADLENGTH,IO_ERROR(a2)
        bra     .td_restore
.td_aligned:
        ; bound guard: offset+length <= disk size
        move.l  d3,d0
        add.l   d2,d0
        cmp.l   #TD_DISKBYTES,d0
        bhi     .td_badrange
        bsr     td_check_change      ; disk changed/removed -> invalidates cache + head position
        tst.l   TD_CACHEBUF          ; track cache, allocated at the first CMD_READ (TD_NCACHE slots, 1 at worst)
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
        move.l  IO_DATA(a2),a5       ; a5 = destination (advances)
.td_bio_loop:
        tst.l   d2
        beq     .td_done_ok          ; nothing more to read -> success
        ; logical block -> (track, sector-in-track, byte-in-track)
        move.l  d3,d0
        lsr.l   #8,d0
        lsr.l   #1,d0                ; d0 = block = offset / 512  (< 1760)
        divu.w  #MFM_NSECT,d0        ; d0.w = track (quotient); high word = sector-in-track (remainder)
        move.l  d0,d1
        clr.w   d1
        swap    d1                   ; d1 = sector-in-track (0..10)
        and.l   #$FFFF,d0            ; d0 = track (0..159)
        lsl.l   #8,d1
        add.l   d1,d1                ; d1 = sector*512 = byte-in-track (lsl #9 forbidden on 68000)
        move.l  d1,d6                ; d6 = byte-in-track (preserved for the copy)
        move.l  #MFM_SECBUF,d5       ; n = min(remaining length, bytes up to the end of the track)
        sub.l   d6,d5                ; d5 = available up to the end of the track
        cmp.l   d2,d5
        bls.s   .td_n_ok
        move.l  d2,d5                ; otherwise n = remaining length
.td_n_ok:                           ; d5 = n (multiple of 512)
                ifne    TD_NOSEEK
        moveq   #0,d0               ; RED TD_NOSEEK: forces track 0 -> read succeeds, wrong contents
                endc
        ; LRU cache of decoded tracks: each 512-byte OFS block used to reread a WHOLE track; and OFS keeps
        ; alternating between the directory track and the data tracks (measured: 222 reads for 58 tracks at the
        ; Workbench boot with a single track in cache). A cached track is served without disk access.
        bsr     td_cache_slot        ; d1 = slot number, a3 = its buffer; Z = found in cache
        beq.s   .td_cached
        bsr     td_fill              ; d0 = 0 complete track (cached), 1 partial, -1 unreadable
        tst.l   d0
        bmi     .td_noread
        beq.s   .td_cached
        move.l  a0,d1                ; incomplete track: each requested sector must be part of it (never the
        move.l  d6,d0                ; stale contents of the buffer)
        lsr.l   #8,d0
        lsr.l   #1,d0                ; d0 = first requested sector
        move.l  d2,-(sp)
        move.l  d5,d2
        lsr.l   #8,d2
        lsr.l   #1,d2
        subq.l  #1,d2                ; d2 = requested sectors - 1
.td_pchk:
        btst    d0,d1
        beq.s   .td_pmiss
        addq.l  #1,d0
        dbra    d2,.td_pchk
        move.l  (sp)+,d2
        bra.s   .td_cached
.td_pmiss:
        move.l  (sp)+,d2
        bra     .td_noread
.td_cached:
        move.l  a3,a0                ; copy n bytes: src = sectorbuf + byte-in-track, dst = a5
        add.l   d6,a0
        move.l  a5,a1
        move.l  d5,d0
        lsr.l   #2,d0                ; n/4 longs (n multiple of 512 -> of 4); n/4 <= 1408 < 65536
        subq.l  #1,d0
.td_copy:
        move.l  (a0)+,(a1)+
        dbra    d0,.td_copy
        add.l   d5,a5                ; dst += n
        add.l   d5,d3                ; offset += n
        add.l   d5,d4                ; actual += n
        sub.l   d5,d2                ; remaining length -= n
        bra     .td_bio_loop
.td_done_ok:
        move.l  d4,IO_ACTUAL(a2)     ; bytes transferred
        clr.b   IO_ERROR(a2)
        bra.s   .td_restore
.td_noread:
        move.l  d4,IO_ACTUAL(a2)     ; bytes transferred before the failure (0 if the 1st track fails)
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
        bra.s   .td_restore          ; sectorbuf = persistent cache: never freed
.td_badrange:
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
        bra.s   .td_restore
.td_nomem:
        move.b  #TDERR_NotSpec,IO_ERROR(a2)
.td_restore:
        move.l  a4,a6                ; restore a6 = device base
        bsr     td_unlock
.td_reply:
        btst    #0,IO_FLAGS(a2)      ; IOF_QUICK (bit 0)?
        bne.s   .td_bdone
        move.l  a6,-(sp)             ; not quick -> ReplyMsg(ioreq)
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

; BeginIO runs in the caller's task, and the drive state (head, DSKPT, cache, TD_DMATASK) is global: without this
; lock, the DF0: handler's TD_CHANGESTATE deselects the drive in the middle of another task's DMA, and a second
; CMD_READ steals TD_DMATASK so the first waiter is never woken. Before multitasking there is no other task: no lock.
; Held across td_dmawait (re-entrant, like any exec semaphore). Preserve everything.
TD_SS_OWNER     EQU 40
td_lock:
        tst.b   SCHED_ON
        beq.s   .tl_ret
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  ($4).w,a6
        tst.l   EB_THISTASK(a6)
        beq.s   .tl_out
        lea     TD_SEM,a0
        jsr     LVO_OBTAINSEMAPHORE(a6)
.tl_out:
        movem.l (sp)+,d0-d1/a0-a1/a6
.tl_ret:
        rts

; Released only by its owner: a request started before multitasking took no lock.
td_unlock:
        movem.l d0-d1/a0-a1/a6,-(sp)
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),d0
        beq.s   .tu_out
        lea     TD_SEM,a0
        cmp.l   TD_SS_OWNER(a0),d0
        bne.s   .tu_out
        jsr     LVO_RELEASESEMAPHORE(a6)
.tu_out:
        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Sets the name (V34 quirk). The placeholder unit areas
; need no init in B1 (will become Unit+MsgPort to initialise in B2).
trackdisk_initfunc:
        clr.l   TD_CACHEBUF
        clr.l   TD_CHGCNT
        move.w  #1,TD_CNSLOTS
        bsr     td_cache_flush
        sf      TD_MOTORON
        sf      TD_BUSY
        clr.w   TD_MOTORCNT
        movem.l d0/a1,-(sp)
        lea     TD_SEM,a0
        jsr     LVO_INITSEMAPHORE(a6)
        lea     TD_VBLINT,a1         ; VBlank server that turns off the idle motor
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
        lea     TD_DSKINT,a1         ; DSKBLK vector (level 1): end of DMA by interrupt (td_dmawait)
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        lea     trackdisk_name(pc),a0
        move.l  a0,LN_NAME(a1)
        clr.l   IS_DATA(a1)
        move.l  #td_dskblk_int,IS_CODE(a1)
        moveq   #1,d0                ; INTB_DSKBLK
        jsr     LVO_SETINTVECTOR(a6)
        movem.l (sp)+,d0/a1
        move.l  d0,a1
        lea     trackdisk_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts

; td_cache_flush(): empties all the cache slots (disk changed, init). Preserves everything.
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

; td_cache_slot(d0.w = track) -> d1.w = slot number, a3 = its buffer (TD_CACHEBUF + n*5632), Z = 1 if the track is
; there (hit); otherwise slot to fill: an empty one, failing that the least recently used. Marks the access (LRU:
; TD_CAGE follows TD_CTRK). Clock overflow: ages reset to 0. Preserves d0/d2-d7/a0-a2/a4-a6.
td_cache_slot:
        movem.l d2-d5/a0,-(sp)
        addq.w  #1,TD_CTICK
        bne.s   .cs_tick
        lea     TD_CAGE,a0           ; clock wrapped to 0: restart from zero ages
        moveq   #TD_NCACHE-1,d1
.cs_clr:
        clr.w   (a0)+
        dbra    d1,.cs_clr
        move.w  #1,TD_CTICK
.cs_tick:
        move.w  TD_CNSLOTS,d2        ; d2 = number of slots
        lea     TD_CTRK,a0
        moveq   #0,d1
.cs_find:
        cmp.w   (a0)+,d0
        beq.s   .cs_hit
        addq.w  #1,d1
        cmp.w   d2,d1
        blo.s   .cs_find
        lea     TD_CTRK,a0           ; missing: first empty slot, otherwise the oldest
        moveq   #0,d1
        moveq   #0,d3                ; d3 = victim
        move.w  #$FFFF,d4            ; d4 = age of the victim
.cs_vict:
        cmp.w   #$FFFF,(a0)
        beq.s   .cs_miss             ; empty: d1
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
        moveq   #1,d5                ; Z = 0: to be read
        bra.s   .cs_mark
.cs_hit:
        moveq   #0,d5                ; Z = 1: in cache
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
        movem.l (sp)+,d2-d5/a0       ; movem does not touch the CCR
        rts

; td_motor_server (VERTB server): turns off the DF0 motor after TD_MOTORIDLE ticks without access (the original
; trackdisk also cuts the motor with a timer). Ignored during an access (TD_BUSY). Turn-off = selection with the motor
; bit high (latch off) then deselection. -> d0 = 0 (Z: the chain continues).
td_motor_server:
        tst.l   TD_DMATASK           ; DMA awaited by a task: delay counted down, at zero it is woken up
        beq.s   .ms_motor
        subq.w  #1,TD_DMATMO
        bgt.s   .ms_motor
        clr.w   TD_DMATMO
        move.l  TD_DMATASK,a1
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_SIGNAL(a6)
.ms_motor:
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

; td_check_change(): selects DF0 latching motor OFF and reads /CHNG (low = disk removed/changed since the
; last head step; only a step with a disk present releases it). Low -> invalidates the track cache AND the
; head position (recalibration). Clobbers d0. Cost: 3 PRB writes, no spin-up.
td_check_change:
        st      TD_BUSY
        move.b  #$FF,CIAB_DDRB
        tst.b   TD_MOTORON           ; the selection re-latches the motor state: keep the current state
        bne.s   .cc_on
        move.b  #PRB_OFF,CIAB_PRB
        move.b  #PRB_SEL0_OFF,CIAB_PRB
        btst    #DSKB_CHANGE,CIAA_PRA_HW
        sne     d0                   ; d0 = $FF if /CHNG high (no change)
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

; td_read_track0(a6=SysBase) -> d0 = chip buffer (raw MFM track) | 0 (timeout / no disk). MINIMAL B2:
; DDRB=$FF (suspect no. 1: without it PRB drives nothing); motor-on + select DF0 (motor latch via SEL0 edge);
; spin-up (busy-loop + DSKRDY poll with timeout, continues); seek (recalibration cyl 0 + step-in + side);
; WORDSYNC DMA of one track; INTREQR DSKBLK poll with timeout (never hangs).
; Writes ONLY CIA-B PRB/DDRB (ports) -> the CIA-B timers (MICROHZ/M7a unit) are not touched.
; B2b: td_read_track(d0 = track number) seeks to the track first; td_read_track0 = reads track 0 (wrapper for
; the existing callers: M6U/M6V, BeginIO). track = cylinder*2 + side. CYLINDER-TRACKING: we follow TD_CURCYL and
; step the DELTA towards the target (recalibration to 0 only if TD_CYLVALID==0) -> correct AND fast (cf. .rd_seek).
td_read_track0:
        moveq   #0,d0                 ; track 0
td_read_track:
        movem.l d2/d3/d6/a2,-(sp)
        move.l  d0,d6                 ; d6 = target track
        move.l  #TD_RAWBYTES,d0       ; raw track buffer in chip RAM (DMA reads ONLY chip)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .rd_ret               ; no chip -> 0
        move.l  d0,a2                 ; a2 = buffer
        bsr     td_position           ; motor, selection, seek, side (IRQs restored)
.rd_dma:
        move.w  #INTF_DSKBLK,INTREQ   ; clear pending DSKBLK
        move.w  #$7FFF,ADKCON         ; clear all ADKCON bits
                ifeq    TD_NO_DMA
        ; $9500 = SETCLR|MFMPREC|FAST|WORDSYNC. The FAST bit (rate 2 us/bit, standard DD) is the WinUAE FIX:
        ; without it (old $8400, FAST=0 = 4 us/bit) Paula samples the stream at the WRONG rhythm -> the bytes
        ; assemble (DSKBYT) but the bitstream is garbage -> $4489 never forms -> WORDEQUAL never ->
        ; read failed (proven stage=$53 on WinUAE). Lax FS-UAE decoded anyway. $9500 = official KS1.3
        ; read mode ($9100 = SETCLR|MFMPREC|FAST) + WORDSYNC. Cf. docs/analysis/trackdisk-official-timing.md.
        move.w  #(ADKF_SETCLR|ADKF_MFMPREC|ADKF_FAST|ADKF_WORDSYNC),ADKCON   ; $9500
        move.w  #TD_SYNC,DSKSYNC      ; $4489
        move.l  a2,DSKPT             ; DMA pointer = buffer (longword)
        move.w  #$4000,DSKLEN        ; reset/disable (quirk before arming)
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_DISK),DMACON  ; $8210: master + disk DMA
        move.w  #($8000|TD_RAWWORDS),DSKLEN   ; arms the read (DMAEN|len)
        move.w  #($8000|TD_RAWWORDS),DSKLEN   ; write 2x to start (hardware quirk)
                endc                 ; RED TD_NO_DMA: DMA not armed -> buffer stays at 0 -> no sync
        bsr     td_dmawait           ; end of DMA, or delay exceeded (no disk)
        bne.s   .rd_done
        bsr.s   .rd_stop             ; timeout -> free the buffer, return 0
        move.l  a2,a1
        move.l  #TD_RAWBYTES,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        bra.s   .rd_ret
.rd_done:
        bsr.s   .rd_stop
        move.l  a2,d0                ; d0 = buffer (success)
.rd_ret:
        movem.l (sp)+,d2/d3/d6/a2
        rts
.rd_stop:
        move.w  #$4000,DSKLEN        ; disable disk DMA
        move.w  #DMAF_DISK,DMACON    ; cut ONLY DSKEN (SETCLR=0 -> clear; do NOT touch MASTER = display)
        move.w  #INTF_DSKBLK,INTREQ  ; clear DSKBLK
        move.b  #PRB_MOTOR_ON,CIAB_PRB ; deselect, motor left on (latched): the next read avoids the spin-up
        move.w  #TD_MOTORIDLE,TD_MOTORCNT ; the VBlank server will turn it off after TD_MOTORIDLE idle ticks
        sf      TD_BUSY
        rts
; td_dmawait(a6 = SysBase; disk DMA armed) -> Z = 0 at the end of the DMA (DSKBLK), Z = 1 if it did not come in time.
; Multitasking running: DSKBLK is unmasked and the task waits for SIGF_SINGLE (td_dskblk_int, or the VBlank server
; after TD_DMATICKS frames): the processor stays available to the other tasks during the disk revolution, like 1.3;
; before that (boot, strap), INTREQR is polled in a loop. Preserves everything except the CCR.
TD_DMATICKS     EQU 50                ; 1 s: a track needs at most two revolutions (400 ms)
SIGF_SINGLE     EQU $10
td_dmawait:
        movem.l d0-d2/a0-a1,-(sp)
        tst.b   SCHED_ON
        beq.s   .dw_poll
        tst.l   EB_THISTASK(a6)
        beq.s   .dw_poll
        moveq   #0,d0
        moveq   #SIGF_SINGLE,d1
        jsr     LVO_SETSIGNAL(a6)    ; a leftover SIGF_SINGLE must not wake the wait
        sf      TD_DMADONE
        move.w  #TD_DMATICKS,TD_DMATMO
        move.l  EB_THISTASK(a6),TD_DMATASK
        move.w  #(INTF_SETCLR|INTF_DSKBLK),INTENA   ; (already finished: the interrupt fires at once)
.dw_wait:
        tst.b   TD_DMADONE
        bne.s   .dw_end
        tst.w   TD_DMATMO
        beq.s   .dw_end
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_WAIT(a6)
        bra.s   .dw_wait
.dw_end:
        move.w  #INTF_DSKBLK,INTENA
        clr.l   TD_DMATASK
        tst.b   TD_DMADONE           ; Z = 1: delay exceeded
        bra.s   .dw_ret
.dw_poll:
        move.l  #$00080000,d2        ; without a disk, the DMA never finishes: bound
.dw_lp:
        move.w  INTREQR,d0
        btst    #1,d0                ; DSKBLK
        bne.s   .dw_ret              ; Z = 0
        subq.l  #1,d2
        bne.s   .dw_lp               ; Z = 1 on exit
.dw_ret:
        movem.l (sp)+,d0-d2/a0-a1    ; (movem does not touch the CCR)
        rts

; td_dskblk_int: DSKBLK vector (level 1, int1_dispatch, a6 = SysBase): end of disk DMA -> masked, acknowledged,
; the waiting task is woken up.
td_dskblk_int:
        move.w  #INTF_DSKBLK,INTENA
        move.w  #INTF_DSKBLK,INTREQ
        st      TD_DMADONE
        move.l  TD_DMATASK,d0
        beq.s   .di_ret
        move.l  d0,a1
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_SIGNAL(a6)
.di_ret:
        rts

; td_position(d6 = track, a6 = SysBase): motor on (spin-up if needed), DF0 selected, head brought to the
; cylinder (cylinder tracking, recalibration if position unknown), side chosen. TD_BUSY set (cleared by the caller
; at the end of its access). Clobbers d0/d2/d3.
td_position:
        st      TD_BUSY               ; the VBlank server no longer touches the drive
        move.w  #INTF_DSKBLK,INTENA   ; makes sure DSKBLK is MASKED (we poll INTREQR, no spurious INT1 IRQ)
        move.b  #$FF,CIAB_DDRB        ; port B = OUTPUTS before writing PRB
        move.b  #PRB_MOTOR_ON,CIAB_PRB ; motor on (intention), everything deselected
        move.b  #PRB_SEL0_ON,CIAB_PRB  ; select DF0 -> the SEL0 edge latches motor=on
        tst.b   TD_MOTORON            ; motor left on since the previous read: already at speed
        bne.s   .rd_seek
        st      TD_MOTORON
        move.l  #$00040000,d2         ; spin-up: busy-loop + DSKRDY poll (timeout = drive absent/empty)
.rd_spin:
        btst    #DSKB_RDY,CIAA_PRA_HW ; DSKRDY = 0 when ready
        beq.s   .rd_seek
        subq.l  #1,d2
        bne.s   .rd_spin
        ; DSKRDY not asserted within the spin-up window. CORRECTION (real-A500 debt lifted): on a real A500 /
        ; timing-exact WinUAE, /RDY is SLOW or NEVER asserts in this window while the disk IS SPINNING
        ; -> the old hard gate "motor off + return 0" rejected EVERY valid disk (all reads failed under
        ; timing-exact WinUAE, proven stage=2). We NO LONGER FAIL here: the loop has already allowed ~0.5-1 s of motor
        ; spin-up; we CONTINUE to the seek+DMA, where the DMA's WORDSYNC sync is the REAL presence test (the
        ; pre-B2 behaviour). Without a disk -> no sync -> DMA timeout further down -> returns 0 (slower than
        ; the old "no disk" probe but CORRECT). /RDY remains the FAST path via the "beq.s .rd_seek" above.
.rd_seek:
        ; CRITICAL SECTION of the seek: the step pulses write CIAB_PRB, and the MICROHZ source (CIA-B
        ; timer A, INT6) shares the SAME chip. An INT6 IRQ landing between the PRB writes of a step corrupts the
        ; head positioning -> the next read falls over (hang observed on a big seek towards a high
        ; block, e.g. "flt-intro" on the Lemmings disk; invisible as long as the boot only reads low blocks).
        ; Proven by bisection: a pure inter-step DELAY does NOT fix it (so not a settle defect), masking
        ; the IRQs DOES (3/3). We mask only the SEEK (short); the downstream DMA polls INTREQR -> no IRQ needed.
        jsr     LVO_DISABLE(a6)     ; a6 = SysBase; balanced by LVO_ENABLE at .rd_pend
        ; --- seek to track d6 with CYLINDER TRACKING ---
        ; We remember the current cylinder (TD_CURCYL, reliable iff TD_CYLVALID) and step the DELTA towards the target
        ; (IN if deeper, OUT if closer to 0) instead of recalibrating to zero on EVERY read. Recalibration
        ; (step OUT until DSKTRACK0, cap 85) ONLY if the position is unknown. CLEANLY fixes bug C
        ; (reading track 0 after a seek read the wrong track): the delta brings the head back to the right cylinder
        ; whatever its position. Much faster (not 85 steps per read) -> unblocks the floppy boot under
        ; the scheduler. Side-select independent of the cylinder. Real-A500 DEBT: no invalidation on disk-change
        ; (position assumed persistent; OK under FS-UAE, to revisit for a real eject/swap + periodic recal).
        move.w  d6,d3               ; d3 = target cylinder = track / 2
        lsr.w   #1,d3
                ifne    TD_NO_CYLTRACK
        clr.b   TD_CYLVALID         ; RED: forces recalibration on EVERY read (old slow behaviour)
                endc
        tst.b   TD_CYLVALID         ; position known?
        bne.s   .rd_known
        move.w  #85,d2              ; recalibration: step OUT until DSKTRACK0 (cap 85)
.rd_recal:
        btst    #DSKB_TRACK0,CIAA_PRA_HW
        beq.s   .rd_recdone
        bsr     .rd_step_out        ; one OUT step (widened pulse: strict drive / real A500 compatible)
        bsr     .rd_stepwait
        dbra    d2,.rd_recal
.rd_recdone:
        bsr     .rd_settle
        clr.w   TD_CURCYL           ; known position = cylinder 0
        st      TD_CYLVALID
.rd_known:
                ifeq    SEEK_NOSTEP
        move.w  TD_CURCYL,d2
        sub.w   d3,d2               ; d2 = current - target
        beq.s   .rd_side            ; already on the right cylinder
        bmi.s   .rd_stepin          ; current < target -> step IN
.rd_stepout:                        ; current > target -> step OUT (towards 0) d2 times
        bsr     .rd_step_out        ; one OUT step (widened pulse)
        bsr     .rd_stepwait
        subq.w  #1,d2
        bne.s   .rd_stepout
        bra.s   .rd_seekdone
.rd_stepin:
        neg.w   d2                  ; |delta|
.rd_stepin_l:
        bsr     .rd_step_in         ; one IN step (widened pulse)
        bsr     .rd_stepwait
        subq.w  #1,d2
        bne.s   .rd_stepin_l
.rd_seekdone:
        bsr     .rd_settle          ; head settling ONCE, after the last step
        move.w  d3,TD_CURCYL        ; position = target
                endc                ; RED SEEK_NOSTEP: no step (nor TD_CURCYL update) -> stays in place
.rd_side:
        move.b  #$77,CIAB_PRB       ; side 0 (DSKSIDE=1, bit2=1; even track)
        btst    #0,d6
        beq.s   .rd_pend
        move.b  #$73,CIAB_PRB       ; side 1 (DSKSIDE=0, bit2=0; odd track)
.rd_pend:
        jsr     LVO_ENABLE(a6)      ; end of the seek critical section
        rts
; Head delays (subq/bne loops ~= 2.54 us per iteration at 7.09 MHz): 3 ms between two steps (step rate of a DD
; drive) and 18 ms of settling ONCE after the last step. Before: ~83 ms after EACH step (3.3 s for 40 cyl).
; Counter in d0: preserves d2 (step counter) AND d3 (target cylinder of the cylinder-tracking).
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

; One step with a WIDENED PULSE (STRICT drive / real A500 compatibility). WinUAE's cycle-exact floppy model IGNORES
; a too-short /STEP (3 back-to-back CIAB_PRB writes = ~1.4 us low): the head does not move -> no valid track
; under the head -> no $4489 sync (proven: all reads stage=3/$53, forced recal ineffective). We
; set the DIRECTION, let it settle, then hold /STEP low for TD_STEP_DLY before releasing -> each
; step is received. Clobbers d0; preserves d2 (step counter) and d3 (target cylinder). FS-UAE unchanged (same edge).
TD_STEP_DLY   EQU $40               ; ~160 us wide (well above the drive minimum; << settle 82 ms)
.rd_step_out:
        move.b  #$77,CIAB_PRB       ; direc OUT (bit1=1), step=1: sets the direction
        bsr.s   .rd_stepdly         ; setup: direction stable before the step edge
        move.b  #$76,CIAB_PRB       ; step=0: falling edge = the step
        bsr.s   .rd_stepdly         ; holds /STEP low (pulse width)
        move.b  #$77,CIAB_PRB       ; step=1: release
        rts
.rd_step_in:
        move.b  #$75,CIAB_PRB       ; direc IN (bit1=0), step=1
        bsr.s   .rd_stepdly
        move.b  #$74,CIAB_PRB       ; step=0: the step
        bsr.s   .rd_stepdly
        move.b  #$75,CIAB_PRB       ; step=1
        rts
.rd_stepdly:
        move.l  #TD_STEP_DLY,d0
.rd_sdloop:
        subq.l  #1,d0
        bne.s   .rd_sdloop
        rts

; table of the commands other than CMD_READ: (command, routine - td_cmdtab)
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
; TD_CHANGESTATE: io_Actual = 0 if a floppy is in the drive. /CHNG stays low after an ejection as long as
; no head step has taken place with a floppy: motor stopped, a probe step (td_disk_present, the "click"
; of the empty drive) tells whether a floppy has been inserted since (the file system polls this every second).
td_cmd_chgstate:
        bsr     td_check_change
        bsr     td_sense
        btst    #DSKB_CHANGE,d1
        bne.s   .cs_in
        tst.b   TD_MOTORON
        bne.s   .cs_out
        bsr     td_disk_present
        tst.l   d0
        bne.s   .cs_in
.cs_out:
        moveq   #1,d0
        bra.s   .cs_set
.cs_in:
        moveq   #0,d0
.cs_set:
        move.l  d0,IO_ACTUAL(a2)
        rts
; TD_PROTSTATUS: io_Actual != 0 if the floppy is write-protected.
td_cmd_prot:
        bsr     td_sense
        moveq   #0,d0
        btst    #DSKB_PROT,d1
        bne.s   .pr_rw
        moveq   #-1,d0
.pr_rw:
        move.l  d0,IO_ACTUAL(a2)
        rts
; TD_MOTOR: io_Length 0 = off (modified tracks stay in cache until CMD_UPDATE), 1 = on (the motor
; starts at the next access); io_Actual = previous state.
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
; CMD_CLEAR: the cache is forgotten, modified tracks included.
td_cmd_clear:
        bra     td_cache_flush
; CMD_UPDATE: the modified tracks are written to disk.
td_cmd_update:
        bsr     td_flush_all
        move.b  d0,IO_ERROR(a2)
        rts

; td_sense(a6) -> d1.b = CIA-A PRA read with DF0 selected (motor state kept): /CHNG, /WPRO... Clobbers d0.
td_sense:
        jsr     LVO_DISABLE(a6)
        move.b  #$FF,CIAB_DDRB
        move.b  #PRB_OFF,d0          ; selection re-latching the current motor state
        tst.b   TD_MOTORON
        beq.s   .se_off
        move.b  #PRB_MOTOR_ON,d0
.se_off:
        move.b  d0,CIAB_PRB
        and.b   #$F7,d0              ; SEL0 low
        move.b  d0,CIAB_PRB
        move.b  CIAA_PRA_HW,d1
        or.b    #$08,d0
        move.b  d0,CIAB_PRB
        jsr     LVO_ENABLE(a6)
        rts

; CMD_WRITE (io_Offset, io_Length multiples of 512): the sectors go into the cache tracks, marked modified;
; a partially covered track is read first. TD_FORMAT: whole tracks, never read, written immediately.
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
        move.l  d3,d0                ; TD_FORMAT: whole tracks
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
        bsr     td_cachebuf          ; cache allocated (first access)
        beq     .wr_err
        move.l  IO_DATA(a2),a5
.wr_loop:
        tst.l   d2
        beq     .wr_done
        move.l  d3,d0                ; track, byte in track, n = up to the end of the track
        lsr.l   #8,d0
        lsr.l   #1,d0
        divu.w  #MFM_NSECT,d0
        move.l  d0,d1
        clr.w   d1
        swap    d1
        and.l   #$FFFF,d0
        lsl.l   #8,d1
        add.l   d1,d1
        move.l  d1,d6                ; d6 = byte in track
        move.l  #MFM_SECBUF,d5
        sub.l   d6,d5
        cmp.l   d2,d5
        bls.s   .wr_n
        move.l  d2,d5
.wr_n:
        bsr     td_cache_slot        ; d1 = slot, a3 = buffer; Z = track in cache
        beq.s   .wr_have
        tst.l   d6                   ; whole track replaced: no read
        bne.s   .wr_read
        cmp.l   #MFM_SECBUF,d5
        bne.s   .wr_read
        move.w  d0,-(sp)
        move.w  d1,d0                ; the reused slot is written first if it was modified
        bsr     td_flush_slot
        move.w  (sp)+,d0
        lea     TD_CTRK,a0
        move.w  d1,d4
        add.w   d4,d4
        move.w  d0,0(a0,d4.w)
        moveq   #0,d4
        bra.s   .wr_have
.wr_read:
        bsr     td_fill              ; partially modified track: its complete contents first
        tst.l   d0
        bne.s   .wr_err              ; unreadable or incomplete: we do not write over it
.wr_have:
        move.l  a3,a1                ; copy into the cache
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
        tst.l   d7
        bne.s   .wr_noact
        add.l   d5,IO_ACTUAL(a2)
.wr_noact:
        sub.l   d5,d2
        bra     .wr_loop
.wr_done:
        tst.l   d7
        beq.s   .wr_ret
        bsr     td_flush_all         ; TD_FORMAT: write immediately
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

; td_cachebuf(a6): allocates the track cache at first access (TD_NCACHE slots, 1 if memory is short).
; Z = 1 if impossible. Clobbers d0/d1/a0/a1.
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

; td_fill(d0.w = track, d1.w = slot, a3 = its buffer, a6): the slot (written first if it was modified)
; receives the read and decoded track; it is only declared valid if its 11 sectors are good and carry that track.
; Incomplete track: reread up to TD_FILLTRIES times, the good sectors accumulating (a read of the wrong
; track cancels them). -> d0 = 0 complete track, 1 incomplete (not cached; a0 = mask of the good sectors), -1
; unreadable. Preserves d1-d7/a2-a6.
td_fill:
        movem.l d1-d7/a2-a5,-(sp)
        move.w  d0,d6                ; d6 = track
        move.w  d1,d5                ; d5 = slot
        move.w  d5,d0
        bsr     td_flush_slot
        lea     TD_CTRK,a0
        move.w  d5,d4
        add.w   d4,d4                ; d4 = offset of the slot
        move.w  #$FFFF,0(a0,d4.w)    ; empty as long as the track is not verified
        moveq   #0,d3                ; d3 = mask of the good sectors
        moveq   #TD_FILLTRIES-1,d2
.fi_try:
        moveq   #0,d0
        move.w  d6,d0
        bsr     td_read_track        ; d0 = raw buffer | 0
        tst.l   d0
        beq.s   .fi_end
        move.l  d0,d7
        move.l  d0,a0
        move.l  a3,a1
        bsr     td_decode_track      ; a0 = mask, d1 = track of the last valid sector
        move.l  a0,d0
        beq.s   .fi_free             ; nothing decoded: the buffer keeps the good sectors from before
        cmp.w   d6,d1
        beq.s   .fi_same
        moveq   #0,d3                ; wrong track: its sectors replaced the good ones
        bra.s   .fi_free
.fi_same:
        move.l  a0,d0
        or.l    d0,d3
.fi_free:
        move.l  d7,a1
        move.l  #TD_RAWBYTES,d0
        jsr     LVO_FREEMEM(a6)
        cmp.l   #TD_ALLSECT,d3
        beq.s   .fi_full
        dbra    d2,.fi_try
.fi_end:
        moveq   #-1,d0
        tst.l   d3
        beq.s   .fi_ret              ; no good sector: unreadable
        move.l  d3,a0
        moveq   #1,d0
        bra.s   .fi_ret
.fi_full:
        lea     TD_CTRK,a0
        move.w  d6,0(a0,d4.w)
        moveq   #0,d0
.fi_ret:
        movem.l (sp)+,d1-d7/a2-a5
        rts

; td_flush_all(a6) -> d0 = 0 | trackdisk error: writes all the modified tracks of the cache. Preserves d1-d7/a0-a6.
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
        move.l  d0,d2                ; first error kept
.fa_keep:
        move.l  (sp)+,d0
        addq.w  #1,d0
        bra.s   .fa_lp
.fa_ret:
        move.l  d2,d0
        movem.l (sp)+,d1-d2
        rts

; td_flush_slot(d0.w = slot, a6) -> d0 = 0 | error: if the slot is modified, its track is MFM-encoded and
; written, then declared clean. Preserves d1-d7/a0-a6.
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
        move.w  0(a0,d6.w),d6        ; d6 = track
        cmp.w   #$FFFF,d6
        beq.s   .fs_ok
        move.l  #TD_WRBYTES,d0       ; MFM track in chip memory (the DMA only sees chip)
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
        bsr     td_write_track       ; d0 = 0 | error
        move.l  d0,d7
        move.l  a4,a1
        move.l  #TD_WRBYTES,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d7,d0
        bra.s   .fs_ret
.fs_nomem:
        lea     TD_CDIRTY,a0         ; nothing written: the track remains to be written
        st      0(a0,d5.w)
        moveq   #TDERR_NotSpec,d0
        bra.s   .fs_ret
.fs_ok:
        moveq   #0,d0
.fs_ret:
        movem.l (sp)+,d1-d7/a0-a5
        rts

; td_encode_track(a0 = 11 decoded sectors, a1 = TD_WRBYTES destination, d0.w = track): track in AmigaDOS format.
; Guard; then per sector: preamble (encoded 0), sync $4489 $4489, header $FF.track.sector.(11 - sector) and label
; (16 null bytes) in odd bits then even bits, header checksum, data checksum, data (odd then
; even); the checksums are the exclusive OR of the encoded longs (data bits). The clock bits are then set
; (1 between two null data bits), except in the sync words. Preserves d2-d7/a2-a6.
td_encode_track:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a3                ; a3 = sectors
        move.l  a1,a2                ; a2 = output
        move.w  d0,d7                ; d7 = track
        move.l  #MFM_MASK,d6
        move.w  #TD_WRGAP/4-1,d1
.en_gap:
        move.l  #$AAAAAAAA,(a2)+     ; encoded zeros
        dbra    d1,.en_gap
        moveq   #0,d5                ; d5 = sector
.en_sec:
        move.l  a2,a4                ; a4 = start of the sector
        clr.l   (a2)+                ; preamble: two words of zeros
        move.l  #$44894489,(a2)+
        moveq   #-1,d0               ; header
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
        lea     8(a4),a0             ; header checksum: 10 longs
        moveq   #0,d0
        moveq   #9,d1
.en_hs:
        move.l  (a0)+,d2
        eor.l   d2,d0
        dbra    d1,.en_hs
        bsr.s   .en_long
        lea     8(a2),a1             ; data: odd then even, checksum along the way
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
        move.l  d4,d0                ; data checksum
        bsr.s   .en_long
        lea     1024(a2),a2
        lea     MFM_SECTSZ(a3),a3
        move.l  a4,a0                ; clock: preamble (after the previous long), then after the sync
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
        move.w  #TD_WRTAIL,(a2)+     ; tail word
        movem.l (sp)+,d2-d7/a2-a5
        rts
.en_long:                            ; d0 -> (a2)+: odd bits then even bits. Clobbers d2.
        move.l  d0,d2
        lsr.l   #1,d2
        and.l   d6,d2
        move.l  d2,(a2)+
        and.l   d6,d0
        move.l  d0,(a2)+
        rts
.en_clock:                           ; a0 = longs (data bits), d0.w = count, d1 = previous long
        movem.l d2-d4,-(sp)
        subq.w  #1,d0
.ec_lp:
        move.l  (a0),d2
        and.l   d6,d2
        move.l  d2,d3
        add.l   d3,d3                ; next neighbour (bit k-1 into k)
        move.l  d2,d4
        lsr.l   #1,d4                ; previous neighbour (bit k+1 into k)
        or.l    d4,d3
        and.l   #1,d1                ; bit 31: last bit of the previous long
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

; td_write_track(d0 = track, a0 = MFM track in chip, TD_WRBYTES, a6) -> d0 = 0 | error: positioning, protection
; check, write DMA (140 ns precompensation on the inner cylinders), wait for the end then for the last word.
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
        move.w  #$7F00,ADKCON        ; precompensation, MFM, rate, sync: cleared (audio bits intact)
        move.w  #(ADKF_SETCLR|ADKF_MFMPREC|ADKF_FAST),d0
        cmp.w   #TD_PCTRACK,d6
        blo.s   .wt_pc
        or.w    #ADKF_PRECOMP140,d0
.wt_pc:
        move.w  d0,ADKCON
        move.l  a2,DSKPT
        move.w  #$4000,DSKLEN
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_DISK),DMACON
        move.w  #($C000|TD_WRWORDS),DSKLEN   ; DMAEN | WRITE | length
        move.w  #($C000|TD_WRWORDS),DSKLEN
        bsr     td_dmawait
        bne.s   .wt_end
        moveq   #TDERR_NotSpec,d2
        bra.s   .wt_stop
.wt_end:
        move.l  #800,d0              ; ~2 ms: the last word leaves the head
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

; td_disk_present() -> d0 = -1 if a floppy is in DF0, 0 otherwise. /CHNG high: floppy present. Low: a
; step pulse re-arms the latch if a floppy has been inserted (the drive "clicks" like a Kickstart waiting
; for a floppy), then /CHNG is reread. Motor off; the head position is then considered unknown.
; Called outside any read (insert-disk screen), under Disable (step pulses on CIA-B). a6 = SysBase.
; Clobbers d0/d1.
td_disk_present:
        jsr     LVO_DISABLE(a6)
        move.b  #$FF,CIAB_DDRB
        move.b  #PRB_OFF,CIAB_PRB
        move.b  #PRB_SEL0_OFF,CIAB_PRB  ; DF0 selected, motor latched OFF
        btst    #DSKB_CHANGE,CIAA_PRA_HW
        bne.s   .dp_yes
        moveq   #$F7-$F7,d1          ; one step: inwards on track 0, otherwise outwards
        btst    #DSKB_TRACK0,CIAA_PRA_HW
        bne.s   .dp_out
        moveq   #2,d1                ; direction IN = bit 1 at 0
.dp_out:
        move.b  #$F7,d0
        sub.b   d1,d0
        move.b  d0,CIAB_PRB          ; direction set, /STEP high
        bsr.s   .dp_dly
        subq.b  #1,d0
        move.b  d0,CIAB_PRB          ; /STEP low: the step
        bsr.s   .dp_dly
        addq.b  #1,d0
        move.b  d0,CIAB_PRB          ; /STEP released
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

; td_decode_track(rawbuf a0, sectorbuf a1) -> d0 = number of DISTINCT sectors decoded+verified (header AND data
; checksums OK), a0 = their mask (bit n = sector n), d1 = track of the last valid sector.
; Scans the raw track for the $4489 syncs; for each sector: decodes info (combines odd/even),
; checks format=$FF and sector number < 11, checks the header checksum (XOR of the 10 MFM info+label longs & MASK
; == stored decoded checksum) and the data checksum (XOR of the 256 MFM data longs & MASK), then decodes the 512
; data bytes into sectorbuf + number*512. Format locked by Python round-trip. a6 not used.
td_decode_track:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a4                ; a4 = sectorbuf base
        lea     (TD_RAWBYTES-TD_SECBODY)(a0),a2 ; a2 = last possible header start: header + data in the
                                     ; buffer (a long track starting before the gap ends flush with the buffer)
        moveq   #0,d7                ; d7 = mask of the valid sectors
        moveq   #0,d5                ; d5 = track number of the last valid sector (returned in d1 -> B2b seek oracle)
.sc_loop:
        cmp.l   a2,a0
        bcc     .sc_done             ; p >= end -> finished
        cmp.w   #$4489,(a0)
        bne     .sc_adv              ; not a sync -> advance by 2
.sc_skipsync:
        addq.l  #2,a0                ; skip the consecutive $4489s (2 sync words)
        cmp.w   #$4489,(a0)
        beq.s   .sc_skipsync
        cmp.l   a2,a0
        bhi     .sc_done             ; sector cut by the end of the buffer
        move.l  a0,a3                ; a3 = sector header (info_odd)
        ; decode info = combine(info_odd, info_even)
        move.l  (a3),d0
        and.l   #MFM_MASK,d0
        add.l   d0,d0                ; <<1
        move.l  4(a3),d1
        and.l   #MFM_MASK,d1
        or.l    d1,d0                ; d0 = decoded info
        move.l  d0,d4                ; d4 = info (survives the checksum loops; used for the track number if valid)
        move.l  d0,d1
        rol.l   #8,d1
        cmp.b   #$FF,d1              ; format == $FF?
        bne     .sc_adv
        move.l  d0,d6
        lsr.l   #8,d6
        and.l   #$FF,d6              ; d6 = sector number
        cmp.l   #MFM_NSECT,d6
        bcc     .sc_adv              ; sector >= 11 -> ignore
        ; header checksum: XOR of the 10 longs (info+label) & MASK
        moveq   #0,d2
        move.l  a3,a5
        moveq   #10-1,d1
.sc_hc:
        move.l  (a5)+,d3
        eor.l   d3,d2
        dbra    d1,.sc_hc
        and.l   #MFM_MASK,d2         ; d2 = computed header checksum
        move.l  40(a3),d0            ; stored decoded = combine(hdrchk_odd, hdrchk_even)
        and.l   #MFM_MASK,d0
        add.l   d0,d0
        move.l  44(a3),d1
        and.l   #MFM_MASK,d1
        or.l    d1,d0
        cmp.l   d2,d0
        bne     .sc_adv              ; invalid header checksum -> ignore
        ; data checksum: XOR of the 256 longs (data odd+even) & MASK
        moveq   #0,d2
        lea     56(a3),a5
        move.w  #256-1,d1
.sc_dc:
        move.l  (a5)+,d3
        eor.l   d3,d2
        dbra    d1,.sc_dc
        and.l   #MFM_MASK,d2         ; d2 = computed data checksum
        move.l  48(a3),d0           ; stored decoded = combine(datachk_odd, datachk_even)
        and.l   #MFM_MASK,d0
        add.l   d0,d0
        move.l  52(a3),d1
        and.l   #MFM_MASK,d1
        or.l    d1,d0
        cmp.l   d2,d0
        bne     .sc_adv              ; invalid data checksum -> ignore
        ; decode the 512 data bytes (128 longs) into sectorbuf + sector*512
        move.l  a0,-(sp)            ; save the scan pointer (a0 reused as the even walker)
        move.l  d6,d0
        lsl.l   #8,d0               ; sector * 256
        add.l   d0,d0               ; * 2 -> sector * 512 (lsl #9 forbidden: max #8)
        move.l  a4,a1
        add.l   d0,a1               ; a1 = destination
        lea     56(a3),a5          ; a5 = data_odd[0]
        lea     (56+512)(a3),a0    ; a0 = data_even[0]
        move.w  #128-1,d1
.sc_data:
        move.l  (a5)+,d0
        and.l   #MFM_MASK,d0
                ifeq    MFM_BAD_DECODE
        add.l   d0,d0               ; <<1 (correct combine)
                endc                ; RED MFM_BAD_DECODE: skips the <<1 -> wrong data -> sector 0 != "DOS\0"
        move.l  (a0)+,d3
        and.l   #MFM_MASK,d3
        or.l    d3,d0
        move.l  d0,(a1)+
        dbra    d1,.sc_data
        move.l  (sp)+,a0            ; restore the scan pointer
        bset    d6,d7              ; valid sector (a sector reread at the end of the buffer only counts once)
        move.l  d4,d5              ; track number of this sector = (info>>16)&$FF
        swap    d5
        and.l   #$FF,d5            ; d5 = track (seek oracle: must equal the requested track)
        lea     1080(a3),a0        ; skip this sector (header 56 + data 1024) -> scan towards the next sync
        bra     .sc_loop
.sc_adv:
        addq.l  #2,a0
        bra     .sc_loop
.sc_done:
        moveq   #0,d0              ; d0 = number of valid sectors (bits of the mask)
        move.l  d7,d1
.sc_cnt:
        lsr.l   #1,d1
        bcc.s   .sc_cnt0
        addq.l  #1,d0
.sc_cnt0:
        tst.l   d1
        bne.s   .sc_cnt
        move.l  d7,a0              ; a0 = mask
        move.l  d5,d1              ; d1 = track number (of the last valid sector) -> B2b seek oracle
        movem.l (sp)+,d2-d7/a2-a5
        rts
trackdisk_end:
