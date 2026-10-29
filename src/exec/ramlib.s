; src/exec/ramlib.s — loading of libraries and devices from disk (role of ramlib.library).
; OpenLibrary / OpenDevice call ram_loadmodule when the name is missing from the system lists: LoadSeg of
; "LIBS:name" or "DEVS:name", search for the ROMTag (RTC_MATCHWORD whose RT_MATCHTAG points to itself) in the
; loaded segments, then InitResident(romtag, seglist) which adds it to the system list (AUTOINIT) or calls its init.
; Scope: the caller must be a PROCESS (LoadSeg goes through DOS packets replied on its pr_MsgPort); a plain task
; gets the usual failure (the real ramlib delegates to its own process: not reproduced).
; IMPLEMENTATION track ("clean"): RKRM Libraries (ramlib, LIBS:/DEVS:), Resident format (exec/resident.i),
; AutoDocs exec OpenLibrary/OpenDevice/InitResident, dos LoadSeg/UnLoadSeg. NO ROM reading.

                include "exec.i"
                include "dospkt.i"

                xdef    ram_loadmodule

RL_PATHMAX      EQU 64

; ram_loadmodule(a0 = C prefix ("LIBS:" / "DEVS:"), a1 = C name, a6 = SysBase) -> d0 = -1 if a module was
; loaded and initialised, 0 otherwise. A name already containing ':' is loaded as is. Preserves d1-d7/a0-a6.
ram_loadmodule:
        movem.l d1-d4/a0-a3/a6,-(sp)
        move.l  DOS_DOSBASE,d0
        beq     .rl_fail             ; dos not there yet (boot phase)
        move.l  EB_THISTASK(a6),a2
        cmp.b   #NT_PROCESS,LN_TYPE(a2)
        bne     .rl_fail
        lea     -RL_PATHMAX(sp),sp
        move.l  sp,a2                ; a2 = path
        move.l  a1,a3
.rl_colon:
        move.b  (a3)+,d0
        beq.s   .rl_prefix
        cmp.b   #':',d0
        bne.s   .rl_colon
        bra.s   .rl_name             ; name with volume/assign: as is
.rl_prefix:
        move.b  (a0)+,(a2)+
        bne.s   .rl_prefix
        subq.l  #1,a2
.rl_name:
        moveq   #RL_PATHMAX-8,d1
.rl_ncpy:
        move.b  (a1)+,(a2)+
        beq.s   .rl_load
        subq.l  #1,d1
        bne.s   .rl_ncpy
        clr.b   (a2)
.rl_load:
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  ($4).w,a6
        lea     RL_PATHMAX(sp),sp
        move.l  d0,d3                ; d3 = seglist
        beq     .rl_fail
        move.l  d0,d2                ; walk the segments: [size at BADDR-4][link][contents]
.rl_seg:
        lsl.l   #2,d2
        beq     .rl_none
        move.l  d2,a0
        move.l  -4(a0),d4            ; block size (8-byte header included)
        lea     -4(a0,d4.l),a2       ; end of block
        lea     4(a0),a1             ; start of contents
        sub.l   #RT_SIZE,a2
.rl_scan:
        cmp.l   a2,a1
        bhi.s   .rl_next
        cmp.w   #RTC_MATCHWORD,(a1)
        bne.s   .rl_adv
        cmp.l   RT_MATCHTAG(a1),a1
        beq.s   .rl_found
.rl_adv:
        addq.l  #2,a1
        bra.s   .rl_scan
.rl_next:
        move.l  (a0),d2              ; next segment (BPTR)
        bra.s   .rl_seg
.rl_found:
        move.l  d3,d1                ; InitResident(a1 = romtag, d1 = seglist)
        jsr     LVO_INITRESIDENT(a6)
        tst.l   d0
        beq     .rl_none
        moveq   #-1,d0
        bra.s   .rl_ret
.rl_none:
        move.l  d3,d1                ; no ROMTag / init refused: unload
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
.rl_fail:
        moveq   #0,d0
.rl_ret:
        movem.l (sp)+,d1-d4/a0-a3/a6
        rts
