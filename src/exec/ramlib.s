; src/exec/ramlib.s — loading of libraries and devices from disk, and the low-memory expunge (the role of 1.3's
; ramlib.library, spec docs/analysis/ramlib-v34.md). Everything runs in the calling task, as on 1.3:
; - ram_loadmodule: after OpenLibrary/OpenDevice found neither the name as given nor its base name, a ROM resident
;   of the base name is initialised, otherwise (process callers only: a plain task crashes on 1.3, it simply fails
;   here) LoadSeg of the name as given, from "LIBS:"/"DEVS:" unless it holds a volume; the RomTag of the first hunk
;   is initialised with InitResident(tag, seglist), or the first hunk is called when it has none; the module is kept
;   only if a node of the base name is then in the list.
; - ram_expungeall: when AllocMem fails, every library and device with no opener is expunged (RemLibrary/RemDevice)
;   and the seglist it gives back is freed; exec then retries the allocation once.
; IMPLEMENTATION track ("clean"): docs/analysis/ramlib-v34.md + AutoDocs exec OpenLibrary/OpenDevice/InitResident,
; dos LoadSeg. NO ROM reading.

                include "exec.i"
                include "dospkt.i"

                xdef    ram_loadmodule
                xdef    ram_basename
                xdef    ram_expungeall
                xdef    ram_freeseg

RL_PATHMAX      EQU 64

; ram_basename(a1 = C name) -> a0 = the part after the last '/', else after the last ':', else the name itself.
; Uses d0.
ram_basename:
        movem.l d1-d2/a1,-(sp)
        moveq   #0,d1                ; d1 = after the last '/'
        moveq   #0,d2                ; d2 = after the last ':'
.bn_lp:
        move.b  (a1)+,d0
        beq.s   .bn_end
        cmp.b   #'/',d0
        bne.s   .bn_c
        move.l  a1,d1
        bra.s   .bn_lp
.bn_c:
        cmp.b   #':',d0
        bne.s   .bn_lp
        move.l  a1,d2
        bra.s   .bn_lp
.bn_end:
        move.l  d1,a0
        tst.l   d1
        bne.s   .bn_r
        move.l  d2,a0
        tst.l   d2
        bne.s   .bn_r
        move.l  8(sp),a0
.bn_r:
        movem.l (sp)+,d1-d2/a1
        rts

; ram_loadmodule(a0 = C prefix ("LIBS:" / "DEVS:"), a1 = C name as given, a2 = list (LibList / DeviceList),
; a6 = SysBase) -> d0 = node of the base name now in the list, or 0. Preserves d1-d7/a0-a6.
; Loads of the same base name are serialised (spec §4): a request record {next, base name, waiters} is chained
; from RAM_LOADS while its task loads; another task asking for that name chains a {next, task} record into the
; waiters and waits on SIGF_SINGLE, then looks again (a failed load is retried by each waiter).
RQ_NAME         EQU 4
RQ_WAIT         EQU 8
RQ_SIZE         EQU 12
SIGF_SINGLE     EQU $10
ram_loadmodule:
        movem.l d1-d4/a0-a5,-(sp)
        move.l  a0,a4                ; a4 = prefix
        move.l  a1,a5                ; a5 = name as given
        bsr     ram_basename
        move.l  a0,a3                ; a3 = base name
        lea     -RQ_SIZE(sp),sp      ; sp = own request record
.rl_chk:
        jsr     LVO_FORBID(a6)
        move.l  RQ_SIZE+24(sp),a0    ; the list (saved a2)
        move.l  a3,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .rl_have             ; loaded meanwhile by another task
        lea     RAM_LOADS,a0
.rl_q:
        move.l  (a0),d0
        beq.s   .rl_mine
        move.l  d0,a0
        move.l  RQ_NAME(a0),a1
        move.l  a3,a2
.rl_cmp:
        cmpm.b  (a1)+,(a2)+
        bne.s   .rl_q
        tst.b   -1(a1)
        bne.s   .rl_cmp
        move.l  EB_THISTASK(a6),-(sp) ; same name in progress: wait for it
        move.l  RQ_WAIT(a0),-(sp)
        move.l  sp,RQ_WAIT(a0)
        moveq   #0,d0
        moveq   #SIGF_SINGLE,d1
        jsr     LVO_SETSIGNAL(a6)
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_WAIT(a6)
        addq.l  #8,sp
        jsr     LVO_PERMIT(a6)
        bra.s   .rl_chk
.rl_have:
        jsr     LVO_PERMIT(a6)
        bra.s   .rl_out
.rl_mine:
        move.l  RAM_LOADS,(sp)
        move.l  a3,RQ_NAME(sp)
        clr.l   RQ_WAIT(sp)
        move.l  sp,RAM_LOADS
        jsr     LVO_PERMIT(a6)
        move.l  RQ_SIZE+24(sp),a2
        bsr.s   rl_load
        move.l  d0,d2                ; d2 = result
        jsr     LVO_FORBID(a6)
        lea     RAM_LOADS,a0
.rl_un:
        cmp.l   (a0),sp              ; own record unlinked from the chain
        beq.s   .rl_unl
        move.l  (a0),a0
        bra.s   .rl_un
.rl_unl:
        move.l  (sp),(a0)
        move.l  RQ_WAIT(sp),d3
.rl_wake:
        beq.s   .rl_woken
        move.l  d3,a0
        move.l  (a0),d3              ; next waiter read before its task may run
        move.l  4(a0),a1
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_SIGNAL(a6)
        tst.l   d3
        bra.s   .rl_wake
.rl_woken:
        jsr     LVO_PERMIT(a6)
        move.l  d2,d0
.rl_out:
        lea     RQ_SIZE(sp),sp
        movem.l (sp)+,d1-d4/a0-a5
        rts

; rl_load(a2 = list, a3 = base name, a4 = prefix, a5 = name as given, a6 = SysBase) -> d0 = node | 0: the load
; itself. Clobbers d1/d3/d4/a0-a2.
rl_load:
        move.l  a3,a1                ; a ROM resident of that name first
        jsr     LVO_FINDRESIDENT(a6)
        tst.l   d0
        beq.s   .rl_disk
        move.l  d0,a1
        moveq   #0,d1
        jsr     LVO_INITRESIDENT(a6)
        bra     .rl_find
.rl_disk:
        move.l  DOS_DOSBASE,d0
        beq     .rl_fail             ; dos not there yet (boot phase)
        move.l  EB_THISTASK(a6),a0
        cmp.b   #NT_PROCESS,LN_TYPE(a0)
        bne     .rl_fail
        move.l  a2,-(sp)
        lea     -RL_PATHMAX(sp),sp
        move.l  sp,a0                ; a0 = path
        move.l  a5,a1
.rl_colon:
        move.b  (a1)+,d0
        beq.s   .rl_prefix
        cmp.b   #':',d0
        bne.s   .rl_colon
        bra.s   .rl_name             ; name with a volume or an assign: as is
.rl_prefix:
        move.l  a4,a1
.rl_pcpy:
        move.b  (a1)+,(a0)+
        bne.s   .rl_pcpy
        subq.l  #1,a0
.rl_name:
        move.l  a5,a1
        moveq   #RL_PATHMAX-8,d1
.rl_ncpy:
        move.b  (a1)+,(a0)+
        beq.s   .rl_load
        subq.l  #1,d1
        bne.s   .rl_ncpy
        clr.b   (a0)
.rl_load:
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  ($4).w,a6
        lea     RL_PATHMAX(sp),sp
        move.l  (sp)+,a2
        move.l  d0,d3                ; d3 = seglist
        beq     .rl_fail
        lsl.l   #2,d0                ; the RomTag of the first hunk only: [size at BADDR-4][link][contents]
        move.l  d0,a0
        move.l  -4(a0),d4            ; block size (8-byte header included)
        lea     -4(a0,d4.l),a1       ; end of the hunk
        sub.l   #RT_SIZE,a1
        move.l  a1,d4                ; d4 = last place a RomTag fits
        lea     4(a0),a1             ; start of its contents
.rl_scan:
        cmp.l   d4,a1
        bhi.s   .rl_call
        cmp.w   #RTC_MATCHWORD,(a1)
        bne.s   .rl_adv
        cmp.l   RT_MATCHTAG(a1),a1
        beq.s   .rl_tag
.rl_adv:
        addq.l  #2,a1
        bra.s   .rl_scan
.rl_tag:
        move.l  a2,-(sp)
        move.l  d3,d1                ; InitResident(a1 = romtag, d1 = seglist)
        jsr     LVO_INITRESIDENT(a6)
        move.l  (sp)+,a2
        bra.s   .rl_kept
.rl_call:
        move.l  d3,a0                ; no RomTag: the first hunk's code makes the module itself
        move.l  d3,d0                ; (a6 = SysBase, a0 = seglist, a1 = d0 = the hunk link)
        lsl.l   #2,d0
        move.l  d0,a1
        movem.l d3/a2-a3/a6,-(sp)
        jsr     4(a1)
        movem.l (sp)+,d3/a2-a3/a6
.rl_kept:
        move.l  a2,a0
        move.l  a3,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .rl_ret
        move.l  d3,d1                ; no node of the base name: unloaded
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
        move.l  ($4).w,a6
        bra.s   .rl_fail
.rl_find:
        move.l  a2,a0
        move.l  a3,a1
        jmp     LVO_FINDNAME(a6)
.rl_fail:
        moveq   #0,d0
.rl_ret:
        rts

; ram_freeseg(d0 = value returned by a Close or Expunge vector, a0 = address that vector jumped to, a6 = SysBase):
; a non-zero value is a seglist to free (spec §2.2, §5), but only for a module whose code is in RAM: our ROM
; modules make no such promise about D0. A seglist marked $0000ABCD (second longword of its first hunk) is not
; freed: Alert AN_BadSegList (recoverable). Preserves all registers.
ram_freeseg:
        movem.l d0-d1/d7/a0-a1,-(sp)
        tst.l   d0
        beq.s   .fs_ret
        cmpa.l  #$00F80000,a0
        bhs.s   .fs_ret
        lsl.l   #2,d0
        move.l  d0,a1
        cmp.l   #$0000ABCD,8(a1)
        bne.s   .fs_hunk
        move.l  #$08000001,d7
        jsr     LVO_ALERT(a6)
        bra.s   .fs_ret
.fs_hunk:
        move.l  d0,a1                ; each hunk [size][link] freed
        move.l  (a1),-(sp)
        subq.l  #4,a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,d0
        lsl.l   #2,d0
        bne.s   .fs_hunk
.fs_ret:
        movem.l (sp)+,d0-d1/d7/a0-a1
        rts

; ram_expungeall(a6 = SysBase, under Forbid): every library, then every device, whose open count is 0 is removed
; through RemLibrary/RemDevice (its Expunge vector), which frees the seglist it gives back. Preserves all
; registers.
ram_expungeall:
        movem.l d0-d2/a0-a3,-(sp)
        lea     EB_LIBLIST(a6),a2
        move.w  #LVO_REMLIBRARY,d2
        bsr.s   .ex_list
        lea     EB_DEVICELIST(a6),a2
        move.w  #LVO_REMDEVICE,d2
        bsr.s   .ex_list
        movem.l (sp)+,d0-d2/a0-a3
        rts
.ex_list:
        move.l  (a2),a3              ; a3 = node, its successor read before the call
.ex_node:
        move.l  (a3),d1
        beq.s   .ex_r
        tst.w   LIB_OPENCNT(a3)
        bne.s   .ex_next
        cmp.w   #$4EF9,-18(a3)       ; only a node with a real Expunge vector (JMP): a bare List node is left alone
        bne.s   .ex_next
        move.l  d1,-(sp)
        move.l  a3,a1
        jsr     0(a6,d2.w)
        move.l  (sp)+,d1
.ex_next:
        move.l  d1,a3
        bra.s   .ex_node
.ex_r:
        rts
