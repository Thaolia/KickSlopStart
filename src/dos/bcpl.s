; src/dos/bcpl.s - BCPL runtime of dos.library: BCPL call/return (A5/A6 registers), arithmetic, global vector
; (GV), runtime segment in BCPL format and globals. The Workbench 1.3 c: commands (AddBuffers, CD, Path,
; Execute...) call NO library through LVOs: everything goes through the globals of the GV pointed to by A2.
; IMPLEMENTATION track ("clean"): public convention (Bill Kinnersley documentation), AROS arch/m68k-all/dos
; (read-only, nothing copied), spec docs/analysis/bcpl-runtime-v34.md (clean-room reviewed). NO ROM reading.
;
; Convention: A0 = 0, A1 = current BCPL frame, A2 = GV (address of slot 0), A4 = current routine, A5 = bcpl_call,
; A6 = bcpl_ret. Call: d0 = size of the caller's frame (offset of the new A1), a4 = called routine,
; d1-d4 = first 4 arguments (the following ones are written by the caller at 16, 20... of the new frame).
; Below the new frame: old A1 (-12), return address (-8), entry of the called routine (-4). Result in d1.
; Scratch for a routine: d0, d2-d7, a3, a4; A1/A2/A5/A6 returned intact; A0 returned as 0.
;
; How a command gets the runtime (spec §3.3): its hunk 0 (stub) calls findsegarray (89), getvec (29) and
; globin (28) of the CLI's GV to create a PRIVATE GV for itself, installs every segment of the pr_SegList segarray
; in it, then its own seglist. Our runtime is therefore published as a BCPL-FORMAT SEGMENT (bcpl_rtseg) in the
; CLI's segarray.

                include "exec.i"
                include "dos.i"
                include "dospkt.i"

                xdef    bcpl_call            ; A5 register of BCPL programs
                xdef    bcpl_ret             ; A6 register
                xdef    bcpl_cli_setup       ; GV + segarray of a CLI process
                xdef    bcpl_starthandler
                xdef    bcpl_cli_register    ; rn_TaskArray slot + pr_TaskNum of the initial CLI
                xdef    bcpl_execute         ; Execute LVO (dos_lib.s)
                xdef    rt_fault             ; text of a dos error via C:FAULT (shell.s)
                xref    rcli_seg
                xref    dos_bufwrite         ; dos_lib.s: deferred writing (wrch & co to a file)
                xref    dos_flushout
                xref    dos_pktretry         ; dos_lib.s: "Please replace volume" requester
                xref    dos_setnow           ; dos_lib.s: sets the system time (setdatstamp)
                xref    proc_create          ; process.s: Process + stack + pr_MsgPort + AddTask
                xref    ser_puts
                xref    ser_puthex
                xref    dos_resolve          ; dos_lib.s: name -> handler port + lock (deviceproc)
                xref    dos_sendpkt          ; process.s: synchronous packet (a0 = StandardPacket, a1 = port)

GV_NEGSLOTS     EQU 50               ; slots -50..-1
GV_MAX          EQU 150              ; GV[0] = highest allowed global
GV_NEG          EQU GV_NEGSLOTS*4
GV_POS          EQU (GV_MAX+1)*4
GV_SIZE         EQU GV_NEG+GV_POS    ; 804 bytes
ERR_GLOBIN      EQU 111              ; Result2 of globin when a global exceeds GV[0]
ERR_BADTEMPLATE EQU 120              ; Result2 of rdargs on error
ACTION_MORE_CACHE EQU 18
WF_BUFSZ        EQU 128              ; local output buffer of writef & co (flushed when full and at the end)
CP_STKEXTRA     EQU 4096             ; 68000 stack margin of processes created by createproc

; --- call / return (A5 / A6) - multiply MUST be at bcpl_call+$10, divide at +$12 ("jsr $10(a5)" calls) ---
; The ABI fixes this entry at 16 bytes (frame -12/-8/-4, jumps at +$10/+$12): the sequence is therefore identical to
; that of AROS's BCPL_jsr/BCPL_rts (arch/m68k-all/dos/bcpl.S), as noted by the audit docs/audit/aros-similarity.md.
bcpl_call:
        move.l  (sp)+,a3             ; return address (the call is made by jsr (a5))
        movem.l a1/a3-a4,-12(a1,d0.l) ; below the new frame: old A1, return, called routine
        adda.l  d0,a1                ; A1 = new frame
        movem.l d1-d4,(a1)           ; arguments
        jmp     (a4)
        bra.s   bcpl_mul             ; bcpl_call+$10
        bra.s   bcpl_divmod          ; bcpl_call+$12
bcpl_ret:
        movem.l -12(a1),a1/a3        ; old A1 and return address
        move.l  -4(a1),a4            ; routine of the caller's frame
        jmp     (a3)

; bcpl_mul: d1 = d1 * d2 (low 32 bits, signed or not). Other registers preserved.
bcpl_mul:
        movem.l d0/d3-d4,-(sp)
        move.l  d1,d3
        swap    d3
        mulu.w  d2,d3                ; high word of a * low word of b
        move.l  d2,d4
        swap    d4
        mulu.w  d1,d4                ; low word of a * high word of b
        add.w   d4,d3
        swap    d3
        clr.w   d3                   ; (sum of the cross products) << 16
        mulu.w  d2,d1                ; low words
        add.l   d3,d1
        movem.l (sp)+,d0/d3-d4
        rts

; bcpl_divmod: d1 = d1 / d2 (truncation towards 0), d2 = remainder (sign of the dividend). Division by 0 -> 0, 0.
bcpl_divmod:
        movem.l d0/d3-d5,-(sp)
        tst.l   d2
        bne     .dm_go
        moveq   #0,d1
        bra     .dm_out
.dm_go:
        moveq   #0,d5                ; bit0 = negative quotient, bit1 = negative remainder
        tst.l   d1
        bpl     .dm_apos
        neg.l   d1
        bchg    #0,d5
        bset    #1,d5
.dm_apos:
        tst.l   d2
        bpl     .dm_bpos
        neg.l   d2
        bchg    #0,d5
.dm_bpos:
        bsr     udivmod32            ; d1 = quotient, d3 = remainder (unsigned)
        btst    #0,d5
        beq     .dm_qpos
        neg.l   d1
.dm_qpos:
        btst    #1,d5
        beq     .dm_rpos
        neg.l   d3
.dm_rpos:
        move.l  d3,d2
.dm_out:
        movem.l (sp)+,d0/d3-d5
        rts

; udivmod32(d1 = dividend, d2 = non-zero divisor) -> d1 = quotient, d3 = remainder (unsigned). Clobbers d4.
udivmod32:
        moveq   #0,d3
        moveq   #31,d4
.ud_lp:                              ; shift-subtract division (68000: no divu.l)
        add.l   d1,d1
        addx.l  d3,d3
        cmp.l   d2,d3
        blo     .ud_nb
        sub.l   d2,d3
        addq.l  #1,d1
.ud_nb:
        dbra    d4,.ud_lp
        rts


; bcpl_cli_setup(a6 = SysBase, a0 = Process): creates the CLI's GV (pr_GlobVec) and its segarray (pr_SegList =
; [2, runtime, 0]). GV: each slot gets the diagnostic stub for its offset, then globin of the runtime; GV[0] = 150.
; No RAM -> fields left at 0. Preserves everything.
bcpl_cli_setup:
        movem.l d0-d2/a0-a3,-(sp)
        move.l  a0,a3                ; a3 = process
        move.l  #GV_SIZE,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .cs_ret
        move.l  d0,a0                ; filling with the stubs, from slot -50 to slot 150
        lea     bcpl_stubs(pc),a1
        move.w  #(GV_SIZE/4)-1,d2
.cs_fill:
        move.l  a1,(a0)+
        addq.l  #BCPL_STUBSZ,a1
        dbra    d2,.cs_fill
        add.l   #GV_NEG,d0
        move.l  d0,a2                ; a2 = slot 0
        move.l  #GV_MAX,(a2)
        lea     bcpl_rtseg(pc),a0
        move.l  a0,d1
        lsr.l   #2,d1
        bsr     rt_globin            ; installs the runtime in this GV
        move.l  a2,PR_GLOBVEC(a3)    ; APTR (not BPTR)
        lea     bcpl_intuiname(pc),a1  ; GV[92] = IntuitionBase (openwindow, CloseWindow of the handlers)
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,92*4(a2)
        moveq   #4,d1                ; segarray [4, runtime, 0, 0, ROM CLI]: Run copies the parent's V!1 and V!2
        bsr     rt_getvec_raw        ; (V!2 = 0: globin of 0 = nothing); NewCLI copies entries 0..4 and starts
        tst.l   d0                   ; its CLI on entry 4 lacking a "CLI" resident; getvec block, freeable by freevec
        beq     .cs_ret
        move.l  d0,a0
        add.l   a0,a0
        add.l   a0,a0
        move.l  #4,(a0)
        lea     bcpl_rtseg(pc),a1
        move.l  a1,d1
        lsr.l   #2,d1
        move.l  d1,4(a0)
        clr.l   8(a0)
        clr.l   12(a0)
        move.l  #rcli_seg,d1
        lsr.l   #2,d1
        move.l  d1,16(a0)
        move.l  d0,PR_SEGLIST(a3)
.cs_ret:
        movem.l (sp)+,d0-d2/a0-a3
        rts

; rt_makeglobvec(d1 = segarray BPTR, a6 = SysBase) -> d0 = BPTR of slot 0 of a new GV | 0 (Result2 = 103). Size =
; largest "max" of the segments of V!1..V!n (floor 15), + 50 negative slots; GV[0] = that max (spec §8.1, 13).
; Slots -50..150 get the diagnostic stubs (the ROM leaves them undefined), beyond that 0. Preserves d1-d7/a2-a6.
rt_makeglobvec:
        movem.l d1-d4/a0-a1,-(sp)
        moveq   #15,d3               ; d3 = max retained
        lsl.l   #2,d1
        beq.s   .mg_alloc
        move.l  d1,a0
        move.l  (a0)+,d2             ; n
        bra.s   .mg_next
.mg_seglp:
        move.l  (a0)+,d1             ; V!i: chain of hunks
.mg_hunk:
        lsl.l   #2,d1
        beq.s   .mg_next
        move.l  d1,a1
        move.l  (a1),d1              ; next hunk
        move.l  4(a1),d4             ; N (longs)
        lsl.l   #2,d4
        move.l  0(a1,d4.l),d4        ; last long = max
        cmp.l   d3,d4
        ble.s   .mg_hunk
        move.l  d4,d3
        bra.s   .mg_hunk
.mg_next:
        subq.l  #1,d2
        bpl.s   .mg_seglp
.mg_alloc:
        move.l  d3,d1
        add.l   #GV_NEGSLOTS,d1      ; slots -50..max
        bsr     rt_getvec_raw
        tst.l   d0
        beq.s   .mg_fail
        move.l  d0,d4
        lsl.l   #2,d0
        move.l  d0,a0                ; a0 = slot -50
        lea     bcpl_stubs(pc),a1
        move.l  d3,d2
        add.l   #GV_NEGSLOTS,d2      ; d2 = number of slots - 1
        moveq   #-GV_NEGSLOTS,d1     ; d1 = number of the current slot
.mg_fill:
        cmp.l   #GV_MAX,d1
        bgt.s   .mg_zero
        move.l  a1,(a0)+
        addq.l  #BCPL_STUBSZ,a1
        bra.s   .mg_fnext
.mg_zero:
        clr.l   (a0)+
.mg_fnext:
        addq.l  #1,d1
        dbra    d2,.mg_fill
        move.l  d4,d0
        add.l   #GV_NEGSLOTS,d0      ; BPTR of slot 0
        move.l  d0,a0
        add.l   a0,a0
        add.l   a0,a0
        move.l  d3,(a0)              ; GV[0] = max
        bra.s   .mg_ret
.mg_fail:
        moveq   #103,d0
        bsr     rt_setr2
        moveq   #0,d0
.mg_ret:
        movem.l (sp)+,d1-d4/a0-a1
        rts

; bcpl_starthandler(a2 = DeviceNode, a0 = full C name (e.g. "NEWCON:0/0/640/200/T")) -> d0 = MsgPort of the handler
; | 0 (Result2 = error), Result2 := dn_Lock on success. Spec §13.3 (global 112): loads dn_Handler into
; dn_SegList if it is empty (only once); dn_GlobalVec = -1 -> C handler (process launched directly on the code
; of the first hunk, stack dn_StackSize in BYTES); otherwise BCPL handler: segarray [3, runtime, 0, dn_SegList], GV =
; dn_GlobalVec (shared) or makeglobvec, createproc (stack in LONGS, pri dn_Priority, name dn_Name). Then a synchronous
; startup packet: Arg1 = BSTR of the full name, Arg2 = dn_Startup, Arg3 = BPTR of the node, Res2 = GV (BCPL);
; success if the handler replies Res1 != 0. dn_Task is not written here (that is the handler's job). The caller must
; be a process (the reply arrives on its pr_MsgPort). Preserves d1-d7/a0-a6.
bcpl_starthandler:
        movem.l d1-d7/a0-a6,-(sp)
        move.l  a0,a5                ; a5 = full name
        move.l  ($4).w,a6
        move.l  DN_SEGLIST(a2),d0
        bne.s   .sh_seg
        lea     -256(sp),sp
        move.l  DN_HANDLER(a2),d1
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  ($4).w,a6
        lea     256(sp),sp
        tst.l   d0
        beq     .sh_fail0            ; Result2 left by LoadSeg
        move.l  d0,DN_SEGLIST(a2)
.sh_seg:
        move.l  d0,d3                ; d3 = seglist of the handler
        moveq   #3,d1                ; segarray [3, runtime, 0, seglist]
        bsr     rt_getvec_raw
        move.l  d0,d5
        beq     .sh_nomem
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  #3,(a0)+
        lea     bcpl_rtseg(pc),a1
        move.l  a1,d1
        lsr.l   #2,d1
        move.l  d1,(a0)+
        clr.l   (a0)+
        move.l  d3,(a0)
        move.l  a5,a0                ; BSTR of the full name (getvec, freed after the reply)
        moveq   #0,d4
.sh_len:
        tst.b   (a0)+
        beq.s   .sh_lend
        addq.l  #1,d4
        cmp.l   #255,d4
        bcs.s   .sh_len
.sh_lend:
        move.l  d4,d1
        lsr.l   #2,d1                ; (L+1)/4 rounded: getvec(L/4) = L/4+1 longs >= L+1 bytes
        bsr     rt_getvec_raw
        move.l  d0,a4                ; a4 = BPTR of the BSTR
        tst.l   d0
        beq     .sh_nomem
        lsl.l   #2,d0
        move.l  d0,a0
        move.b  d4,(a0)+
        move.l  a5,a1
        bra.s   .sh_cnext
.sh_ccpy:
        move.b  (a1)+,(a0)+
.sh_cnext:
        dbra    d4,.sh_ccpy
        move.l  DN_PRIORITY(a2),d7
        move.l  DN_STACKSIZE(a2),d6
        move.l  DN_GLOBALVEC(a2),d1
        cmp.l   #-1,d1
        beq.s   .sh_chandler
        lsl.l   #2,d6                ; BCPL: stack in longs
        add.l   #CP_STKEXTRA,d6
        lsl.l   #2,d1
        bne.s   .sh_gv
        move.l  d5,d1
        bsr     rt_makeglobvec
        tst.l   d0
        beq     .sh_freename
        move.l  d0,d1
        lsl.l   #2,d1
.sh_gv:
        move.l  d1,d2
        lsr.l   #2,d2                ; d2 = Res2 of the packet = BPTR of the GV
        move.l  DN_NAME(a2),d4
        bsr     rt_createproc        ; d0 = port | 0
        tst.l   d0
        beq     .sh_freename
        bra.s   .sh_started
.sh_chandler:                        ; C handler: process directly on the code, C name = dn_Name (NUL guaranteed)
        move.l  DN_NAME(a2),d0
        lsl.l   #2,d0
        move.l  d0,a0
        addq.l  #1,a0
        move.l  d3,d0
        lsl.l   #2,d0
        move.l  d0,a1
        addq.l  #4,a1                ; entry = first hunk
        move.l  d7,d0
        move.l  d6,d1
        jsr     LVO_FORBID(a6)
        jsr     proc_create
        move.l  d0,d4                ; d4 = port (Permit clobbers d0/d1)
        beq.s   .sh_cfail
        move.l  d0,a0
        lea     -PR_MSGPORT(a0),a0
        move.l  d5,PR_SEGLIST(a0)
        bsr     rt_this
        move.l  PR_CONSOLETASK(a3),PR_CONSOLETASK(a0)
        move.l  PR_FILESYSTEMTASK(a3),PR_FILESYSTEMTASK(a0)
        move.l  PR_WINDOWPTR(a3),PR_WINDOWPTR(a0)
        jsr     LVO_PERMIT(a6)
        move.l  d4,d0
        moveq   #0,d2                ; Res2 = 0 (no GV)
        bra.s   .sh_started
.sh_cfail:
        jsr     LVO_PERMIT(a6)
        moveq   #103,d0
        bsr     rt_setr2
        bra     .sh_freename
.sh_started:
        move.l  d0,a3                ; a3 = handler port
        lea     -(SP_SIZEOF+2)(sp),sp ; startup packet, long-aligned (the handler receives it as a BPTR)
        move.l  sp,d0
        btst    #1,d0
        beq.s   .sh_palign
        addq.l  #2,d0
.sh_palign:
        move.l  d0,a1                ; a1 = message
        move.l  d0,a0
        moveq   #SP_SIZEOF/2-1,d0
.sh_pclr:
        clr.w   (a0)+
        dbra    d0,.sh_pclr
        lea     SP_PKT(a1),a0        ; a0 = packet
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.w  #DP_SIZEOF,MN_LENGTH(a1)
        move.l  a0,LN_NAME(a1)
        move.l  a1,DP_LINK(a0)
        move.l  EB_THISTASK(a6),d0
        add.l   #PR_MSGPORT,d0
        move.l  d0,d6                ; d6 = our reply port
        move.l  d0,MN_REPLYPORT(a1)
        move.l  d0,DP_PORT(a0)
        move.l  a4,DP_ARG1(a0)
        move.l  DN_STARTUP(a2),DP_ARG2(a0)
        move.l  a2,d0
        lsr.l   #2,d0
        move.l  d0,DP_ARG3(a0)
        move.l  d2,DP_RES2(a0)
        move.l  a3,a0
        jsr     LVO_PUTMSG(a6)       ; PutMsg(port a0, message a1)
.sh_wait:
        move.l  d6,a0
        jsr     LVO_WAITPORT(a6)
        move.l  d6,a0
        jsr     LVO_GETMSG(a6)
        move.l  sp,d1
        btst    #1,d1
        beq.s   .sh_galign
        addq.l  #2,d1
.sh_galign:
        cmp.l   d1,d0
        bne.s   .sh_wait
        move.l  d0,a0
        move.l  SP_PKT+DP_RES1(a0),d7
        move.l  SP_PKT+DP_RES2(a0),d2
        lea     SP_SIZEOF+2(sp),sp
        bsr.s   .sh_free_a4
        tst.l   d7
        beq.s   .sh_refused
        move.l  DN_LOCK(a2),d0
        bsr     rt_setr2
        move.l  a3,d0
        bra.s   .sh_ret
.sh_refused:
        move.l  d2,d0
        bsr     rt_setr2
        moveq   #0,d0
        bra.s   .sh_ret
.sh_nomem:
        moveq   #103,d0
        bsr     rt_setr2
        bra.s   .sh_fail0
.sh_freename:
        bsr.s   .sh_free_a4
.sh_fail0:
        moveq   #0,d0
.sh_ret:
        movem.l (sp)+,d1-d7/a0-a6
        rts
.sh_free_a4:                         ; free the BSTR of the full name (a4 = BPTR | 0)
        move.l  a4,d0
        lsl.l   #2,d0
        beq.s   .sh_fr
        move.l  d0,a1
        subq.l  #4,a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
.sh_fr:
        rts

; bcpl_cli_register(a0 = Process): takes the first free slot of rn_TaskArray for this CLI (taskid = MsgPort) and
; sets pr_TaskNum. Preserves everything.
bcpl_cli_register:
        movem.l d0-d1/a0-a2/a6,-(sp)
        move.l  a0,a2
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  DOS_DOSBASE,a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_TASKARRAY(a0),d0
        lsl.l   #2,d0
        beq.s   .cr_done
        move.l  d0,a0
        move.l  (a0)+,d1             ; size
        moveq   #1,d0
.cr_lp:
        cmp.l   d1,d0
        bhi.s   .cr_done             ; full
        tst.l   (a0)
        beq.s   .cr_take
        addq.l  #4,a0
        addq.l  #1,d0
        bra.s   .cr_lp
.cr_take:
        lea     PR_MSGPORT(a2),a1
        move.l  a1,(a0)
        move.l  d0,PR_TASKNUM(a2)
.cr_done:
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d0-d1/a0-a2/a6
        rts

; bcpl_proc_entry: body of every process created by createproc (spec §2.4). Stack filled with $ABABABAB, base BCPL
; frame at the BOTTOM of the stack (!1 = -1, !2 = upper limit), GV[12] := BPTR(base), globin of every segment of
; the segarray into pr_GlobVec, wait for the startup packet, then start(pkt) (global 1, 32-byte frame). On return:
; end of process.
BP_STKMARGIN    EQU 256              ; area not filled below the current SP (trampoline stack)
bcpl_proc_entry:
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a3   ; a3 = process
        move.l  TC_SPLOWER(a3),a0
        lea     -BP_STKMARGIN(sp),a1
        move.l  #$ABABABAB,d0
.pe_fill:
        cmp.l   a1,a0
        bhs.s   .pe_filled
        move.l  d0,(a0)+
        bra.s   .pe_fill
.pe_filled:
        move.l  TC_SPLOWER(a3),a4    ; a4 = base frame
        moveq   #-1,d0
        move.l  d0,4(a4)
        move.l  TC_SPUPPER(a3),d0
        sub.l   #160,d0
        move.l  d0,8(a4)
        move.l  PR_GLOBVEC(a3),a2    ; a2 = GV
        move.l  a4,d0
        lsr.l   #2,d0
        move.l  d0,12*4(a2)          ; GV[12] = currco / BCPL stack base
        move.l  PR_SEGLIST(a3),d0    ; globin of V!1..V!n
        lsl.l   #2,d0
        beq.s   .pe_wait
        move.l  d0,a5
        move.l  (a5)+,d7             ; n
.pe_glob:
        subq.l  #1,d7
        bmi.s   .pe_wait
        move.l  (a5)+,d1
        movem.l d7/a3-a5,-(sp)
        bsr     rt_globin
        movem.l (sp)+,d7/a3-a5
        bra.s   .pe_glob
.pe_wait:                            ; startup packet
        lea     PR_MSGPORT(a3),a0
        jsr     LVO_WAITPORT(a6)
        lea     PR_MSGPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .pe_wait
        move.l  d0,a0
        move.l  LN_NAME(a0),d1
        lsr.l   #2,d1                ; d1 = BPTR of the packet
        clr.l   -(sp)                ; pr_ReturnAddr -> this long: stop(n) does SP := ReturnAddr-4 then rts ->
        move.l  sp,PR_RETURNADDR(a3) ; returns to .pe_end (otherwise SP = -4: fault on the first stop)
        pea     .pe_end(pc)
        sub.l   a0,a0
        move.l  a4,a1                ; a1 = base frame
        move.l  4(a2),a4             ; start = GV[1]
        moveq   #32,d0
        lea     bcpl_call(pc),a5
        lea     bcpl_ret(pc),a6
        jsr     (a5)                 ; start(pkt); normal return or stop -> .pe_end
.pe_end:
        move.l  ($4).w,a6
        sub.l   a1,a1
        jsr     LVO_REMTASK(a6)      ; end of process (RemTask(0) does not return)
.pe_hang:
        bra.s   .pe_hang

; ===================================== internal primitives (68000 convention) ===================================

; rt_globin(d1 = BPTR segment chain, a2 = GV) -> d0 = -1 (success) / 0 (Result2 = 111). For each segment
; (link at the head), reads the table at the end of the hunk: last long = max (ignored), then pairs (global, byte
; offset from the start of the data) going down until a zero offset. GV[n] := data + offset. Clobbers d0-d3/a0.
rt_globin:
.gi_seg:
        lsl.l   #2,d1
        beq     .gi_ok
        move.l  d1,a0                ; a0 = segment
        move.l  (a0),d1              ; next link (BPTR)
        lea     4(a0),a0             ; a0 = start of the data (long N)
        move.l  (a0),d2
        lsl.l   #2,d2
        lea     -4(a0,d2.l),a1       ; a1 -> "max" long
.gi_pair:
        move.l  -(a1),d3             ; offset (0 = terminator)
        beq     .gi_seg
        move.l  -(a1),d2             ; global number
        cmp.l   (a2),d2
        bgt     .gi_fail             ; > GV[0] (signed: negative ones pass)
        add.l   a0,d3
        lsl.l   #2,d2
        move.l  d3,0(a2,d2.l)
        bra     .gi_pair
.gi_ok:
        moveq   #-1,d0
        rts
.gi_fail:
        moveq   #ERR_GLOBIN,d0
        bsr     rt_setr2
        moveq   #0,d0
        rts

; rt_getvec_raw(d1 = n, a6 = SysBase) -> d0 = BPTR of a vector of n+1 longs (not cleared) | 0. Hidden header at -4 =
; total size in bytes (for freevec). Preserves d1-d7/a2-a6.
rt_getvec_raw:
        movem.l d1/a0-a1,-(sp)
        moveq   #0,d0
        tst.l   d1
        bmi     .gv_ret
        addq.l  #2,d1                ; n+1 longs + header
        lsl.l   #2,d1
        move.l  d1,-(sp)
        move.l  d1,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,d1
        tst.l   d0
        beq     .gv_ret
        move.l  d0,a0
        move.l  d1,(a0)+             ; header = size
        move.l  a0,d0
        lsr.l   #2,d0
.gv_ret:
        movem.l (sp)+,d1/a0-a1
        rts

; rt_setr2(d0): pr_Result2 of ThisTask := d0. Preserves everything.
rt_setr2:
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  d0,PR_RESULT2(a0)
        move.l  (sp)+,a0
        rts

; rt_this() -> a3 = ThisTask (process). Preserves everything else.
rt_this:
        move.l  ($4).w,a3
        move.l  EB_THISTASK(a3),a3
        rts

; rt_write(a0 = buffer, d0 = length): Write(output(), ...) via dos. Preserves everything.
rt_write:
        movem.l d0-d3/a0-a1/a3/a6,-(sp)
        tst.l   d0
        beq     .wr_ret
        move.l  d0,d3
        move.l  a0,d2
        bsr     rt_this
        move.l  PR_COS(a3),d1
        beq     .wr_ret
        jsr     dos_bufwrite            ; dos_lib.s: deferred to a file, immediate to a console
.wr_ret:
        movem.l (sp)+,d0-d3/a0-a1/a3/a6
        rts

; rt_cstr(d1 = BSTR (BPTR), a0 = buffer >= 256 bytes): copies into a NUL-terminated C string. Preserves everything.
rt_cstr:
        movem.l d0-d1/a0-a1,-(sp)
        lsl.l   #2,d1
        beq     .cs_empty
        move.l  d1,a1
        moveq   #0,d0
        move.b  (a1)+,d0
        bra     .cs_next
.cs_cpy:
        move.b  (a1)+,(a0)+
.cs_next:
        dbra    d0,.cs_cpy
.cs_empty:
        clr.b   (a0)
        movem.l (sp)+,d0-d1/a0-a1
        rts

; rt_upper(d0.b) -> d0.b in upper case (a-z). Preserves the rest.
rt_upper:
        cmp.b   #'a',d0
        blo     .up_ret
        cmp.b   #'z',d0
        bhi     .up_ret
        sub.b   #'a'-'A',d0
.up_ret:
        rts

; --- input stream (FileHandle layout §5.1: fh_Buf BPTR, fh_Pos/fh_End byte indexes) ---
; rt_rdch() -> d0 = character (0..255) | -1 (EOF), on input(). Fills the buffer (200 bytes) by Read if exhausted.
; Preserves everything except d0.
rt_rdch:
        movem.l d1-d3/a0-a1/a3/a6,-(sp)
        bsr     rt_this
        move.l  PR_CIS(a3),d0
        lsl.l   #2,d0
        beq     .rc_eof
        move.l  d0,a3                ; a3 = FileHandle
        move.l  FH_POS(a3),d0
        cmp.l   FH_END(a3),d0
        bge     .rc_refill
.rc_take:
        move.l  FH_BUF(a3),d1
        lsl.l   #2,d1
        move.l  d1,a0
        moveq   #0,d1
        move.b  0(a0,d0.l),d1
        addq.l  #1,FH_POS(a3)
        move.l  d1,d0
        bra     .rc_ret
.rc_refill:
        tst.l   FH_END(a3)
        beq     .rc_eof              ; fh_End = 0: EOF without contacting the handler
        tst.l   FH_BUF(a3)
        bne     .rc_read
        move.l  ($4).w,a6
        moveq   #RT_FHBUFLONGS,d1    ; lazy 200-byte buffer (Close recognises it by its size)
        bsr     rt_getvec_raw
        move.l  d0,FH_BUF(a3)
        beq     .rc_fail
.rc_read:
        move.l  a3,-(sp)
        bsr     rt_this
        move.l  PR_COS(a3),d1
        move.l  (sp)+,a3
        jsr     dos_flushout         ; prompt without newline: visible before waiting for input
        move.l  a3,d1
        lsr.l   #2,d1                ; fh (BPTR)
        move.l  FH_BUF(a3),d2
        lsl.l   #2,d2
        move.l  #200,d3
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_READ(a6)
        tst.l   d0
        ble     .rc_fail
        move.l  d0,FH_END(a3)
        clr.l   FH_POS(a3)
        moveq   #0,d0
        bra     .rc_take
.rc_fail:
        clr.l   FH_POS(a3)
        clr.l   FH_END(a3)
.rc_eof:
        moveq   #-1,d0
.rc_ret:
        movem.l (sp)+,d1-d3/a0-a1/a3/a6
        rts

; rt_unrdch() -> d0 = -1 if the character is given back (fh_Pos > 0, or re-readable EOF fh_End = 0), 0 otherwise.
rt_unrdch:
        move.l  a3,-(sp)
        bsr     rt_this
        move.l  PR_CIS(a3),d0
        lsl.l   #2,d0
        beq     .ur_no
        move.l  d0,a3
        tst.l   FH_POS(a3)
        ble     .ur_end
        subq.l  #1,FH_POS(a3)
        bra     .ur_yes
.ur_end:
        tst.l   FH_END(a3)
        bne     .ur_no
.ur_yes:
        moveq   #-1,d0
        bra     .ur_ret
.ur_no:
        moveq   #0,d0
.ur_ret:
        move.l  (sp)+,a3
        rts

; --- output buffer of writef & co: a3 = position, a5 = start (on the caller's stack, WF_BUFSZ) ---
; WF_BUFSZ(a5) = wrch routine to send the characters to, 0 = straight to the output stream. BCPL output goes through
; the wrch of the GV: Ed points global 56 at its own screen buffer around its writef calls (cursor positioning),
; so the characters must reach that routine, not the current stream.
WF_WRCH         EQU WF_BUFSZ
WF_FRAMEGAP     EQU 128              ; the called wrch's frame starts this far above the global's frame (its arguments)
; wf_putc(d0.b): appends a character, flushes if full. Preserves everything except a3.
wf_putc:
        move.b  d0,(a3)+
        move.l  d0,-(sp)
        move.l  a3,d0
        sub.l   a5,d0
        cmp.l   #WF_BUFSZ,d0
        movem.l (sp)+,d0             ; movem does not touch the CCR
        blo     wf_ret
wf_flush:                            ; flushes the buffer (a5..a3); preserves everything except a3 (reset to a5)
        tst.l   WF_WRCH(a5)
        bne.s   wf_gvout
        movem.l d0/a0,-(sp)
        move.l  a3,d0
        sub.l   a5,d0
        move.l  a5,a0
        bsr     rt_write
        move.l  a5,a3
        movem.l (sp)+,d0/a0
wf_ret:
        rts
wf_gvout:                            ; one BCPL call per character, with the global's own frame and GV
        movem.l d0-d7/a0-a6,-(sp)
        move.l  WF_WRCH(a5),-(sp)    ; 8(sp) = routine
        move.l  a3,-(sp)             ; 4(sp) = end
        move.l  a5,-(sp)             ; (sp) = cursor
        move.l  WF_WRCH+4+4(a5),a1   ; a1 and a2 saved by BENTER just above the buffer
        move.l  WF_WRCH+4+8(a5),a2
.gv_lp:
        move.l  (sp),a3
        cmp.l   4(sp),a3
        bhs.s   .gv_end
        moveq   #0,d1
        move.b  (a3)+,d1
        move.l  a3,(sp)
        move.l  8(sp),a4
        sub.l   a0,a0
        move.l  #WF_FRAMEGAP,d0
        lea     bcpl_call(pc),a5
        lea     bcpl_ret(pc),a6
        jsr     (a5)
        bra.s   .gv_lp
.gv_end:
        lea     12(sp),sp
        movem.l (sp)+,d0-d7/a0-a6
        move.l  a5,a3
        rts

; wf_gvsel(a5 = buffer opened right after BENTER): WF_WRCH := global 56 of the caller's GV if it is no longer our wrch.
wf_gvsel:
        movem.l d0/a0,-(sp)
        move.l  WF_WRCH+4+8(a5),a0   ; a2 = GV, saved by BENTER
        move.l  56*4(a0),d0
        lea     g_wrch(pc),a0
        cmp.l   a0,d0
        bne.s   .gs_set
        moveq   #0,d0
.gs_set:
        move.l  d0,WF_WRCH(a5)
        movem.l (sp)+,d0/a0
        rts

; wf_bstr(d1 = BSTR) -> writes the characters; d2 = number written. Preserves d1.
wf_bstr:
        movem.l d1/a0,-(sp)
        moveq   #0,d2
        lsl.l   #2,d1
        beq     .wb_ret
        move.l  d1,a0
        moveq   #0,d1
        move.b  (a0)+,d1
        move.l  d1,d2
        bra     .wb_next
.wb_lp:
        move.b  (a0)+,d0
        bsr     wf_putc
.wb_next:
        dbra    d1,.wb_lp
.wb_ret:
        movem.l (sp)+,d1/a0
        rts

; wf_spaces(d0 = count): writes d0 spaces (nothing if <= 0).
wf_spaces:
        move.l  d1,-(sp)
        move.l  d0,d1
        bra     .sp_next
.sp_lp:
        moveq   #' ',d0
        bsr     wf_putc
.sp_next:
        subq.l  #1,d1
        bpl     .sp_lp
        move.l  (sp)+,d1
        rts

; wf_num(d1 = value, d2 = width, d3 = base 10/16/8, d4 = mode): mode 0 = signed decimal right-aligned on d2
; (spaces before the sign); 1 = unsigned decimal right-aligned; 2 = exactly d2 digits (leading zeros, high
; bits truncated; d2 <= 1 -> 1 digit) - upper-case hex / octal. Preserves d1-d7.
wf_num:
        movem.l d1-d7/a0,-(sp)
        lea     -16(sp),sp
        lea     16(sp),a0            ; digits written from right to left
        moveq   #0,d6                ; d6 = 1 if negative
        cmp.w   #2,d4
        beq     .wn_fixed
        tst.w   d4
        bne     .wn_conv
        tst.l   d1
        bpl     .wn_conv
        neg.l   d1
        moveq   #1,d6
.wn_conv:
        move.l  d2,d7                ; d7 = width
        move.l  d3,d2                ; divisor
.wn_dlp:
        movem.l d4,-(sp)
        bsr     udivmod32            ; d1 /= base, d3 = digit
        movem.l (sp)+,d4
        bsr     .wn_digit
        tst.l   d1
        bne     .wn_dlp
        tst.w   d6
        beq     .wn_pad
        move.b  #'-',-(a0)
.wn_pad:
        lea     16(sp),a1
        move.l  a1,d0
        sub.l   a0,d0                ; length produced
        sub.l   d0,d7
        move.l  d7,d0
        bsr     wf_spaces
        bra     .wn_out
.wn_fixed:                           ; exactly d2 digits
        move.l  d2,d7
        cmp.l   #1,d7
        bge     .wn_fx
        moveq   #1,d7
.wn_fx:
        cmp.l   #16,d7
        ble     .wn_fx2
        moveq   #16,d7
.wn_fx2:
        move.l  d3,d2
        move.l  d7,d5
.wn_flp:
        movem.l d4,-(sp)
        bsr     udivmod32
        movem.l (sp)+,d4
        bsr     .wn_digit
        subq.l  #1,d5
        bne     .wn_flp
.wn_out:
        lea     16(sp),a1
.wn_emit:
        cmp.l   a1,a0
        bhs     .wn_done
        move.b  (a0)+,d0
        bsr     wf_putc
        bra     .wn_emit
.wn_done:
        lea     16(sp),sp
        movem.l (sp)+,d1-d7/a0
        rts
.wn_digit:                           ; d3 = digit -> -(a0)
        move.b  d3,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls     .wd_ok
        addq.b  #7,d0
.wd_ok:
        move.b  d0,-(a0)
        rts

; ====================================== globals (BCPL convention) =============================================
; Entry: a1 = frame, d1-d4 = arguments. BENTER saves a0-a2/a5-a6 and copies the frame into a4; BLEAVE restores them
; (A0 = 0 included) and returns through A6 with the result in d1.
BENTER          MACRO
        movem.l a0-a2/a5-a6,-(sp)
        move.l  a1,a4
                ENDM
BLEAVE          MACRO
        movem.l (sp)+,a0-a2/a5-a6
        jmp     (a6)
                ENDM

; 2 stop(code): command exit -> SP := pr_ReturnAddr - 4 then rts with d0 = code (the launcher restores everything).
g_stop:
        bsr     rt_this
        move.l  d1,d0
        move.l  PR_RETURNADDR(a3),sp
        subq.l  #4,sp
        rts

; 10 result2(set, v): set = 0 -> returns pr_Result2; otherwise returns the old one and writes v.
g_result2:
        bsr     rt_this
        move.l  PR_RESULT2(a3),d0
        tst.l   d1
        beq     .r2_get
        move.l  d2,PR_RESULT2(a3)
.r2_get:
        move.l  d0,d1
        jmp     (a6)

; 14 taskid() -> MsgPort of the current process.
g_taskid:
        bsr     rt_this
        lea     PR_MSGPORT(a3),a3
        move.l  a3,d1
        jmp     (a6)

; 28 globin(seg) -> -1 / 0 (Result2 = 111), into the current GV (A2).
g_globin:
        BENTER
        bsr     rt_globin
        move.l  d0,d1
        BLEAVE

; 29 getvec(n) -> BPTR of a vector of n+1 longs | 0.
g_getvec:
        BENTER
        move.l  ($4).w,a6
        bsr     rt_getvec_raw
        move.l  d0,d1
        BLEAVE

; 30 freevec(v): frees a getvec vector (v = 0: nothing).
g_freevec:
        BENTER
        lsl.l   #2,d1
        beq     .fv_ret
        move.l  d1,a1
        subq.l  #4,a1
        move.l  (a1),d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
.fv_ret:
        BLEAVE

; 35 parentdir(lock) -> lock of the parent directory | 0 (root): ACTION_PARENT (29) packet to the lock's handler.
g_parentdir:
        BENTER
        move.l  d1,d0
        lsl.l   #2,d0
        beq     .pd_root
        move.l  d0,a0
        move.l  FL_TASK(a0),a1       ; handler port
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        moveq   #ACTION_PARENT,d0
        moveq   #0,d2
        moveq   #0,d3
        move.l  ($4).w,a6
        jsr     dos_sendpkt          ; d0 = dp_Res1; Result2 set
        lea     SP_SIZEOF(sp),sp
        move.l  d0,d1
        BLEAVE
.pd_root:
        moveq   #0,d1
        BLEAVE

; 114 errorreq(...): disk error requester -> TRUE = abort, FALSE = retry (observed in c:Dir, which loops again
; on ExNext as long as errorreq returns 0). No Intuition requester at this stage: always TRUE.
g_errorreq:
        moveq   #-1,d1
        jmp     (a6)

; 17 level() -> caller's frame (APTR); 18 longjump(level, label): resumes at label in frame level.
g_level:
        move.l  -12(a1),d1
        jmp     (a6)
g_longjump:
        move.l  d1,a1                ; target frame
        move.l  -4(a1),a4            ; routine owning this frame
        move.l  d2,a3
        jmp     (a3)

; 19 getmem(n, flags): like getvec but with the given AllocMem attributes (e.g. MEMF_PUBLIC|MEMF_CLEAR).
g_getmem:
        BENTER
        moveq   #0,d0
        tst.l   d1
        bmi.s   .gm_ret
        addq.l  #2,d1
        lsl.l   #2,d1
        move.l  d1,d3                ; d3 = total size
        move.l  d1,d0
        move.l  d2,d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .gm_ret
        move.l  d0,a0
        move.l  d3,(a0)+
        move.l  a0,d0
        lsr.l   #2,d0
.gm_ret:
        move.l  d0,d1
        BLEAVE

; 47 delay(ticks) : 1/50 s (= LVO Delay).
g_delay:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_DELAY(a6)
        moveq   #0,d1
        BLEAVE

; 59 findinput(name) / 60 findoutput(name) -> FileHandle (BPTR) | 0; 93 endstream(fh); 63 endread() / 64 endwrite().
g_findinput:
        move.l  #MODE_OLDFILE,d2
        bra.s   g_findstream
g_findoutput:
        move.l  #MODE_NEWFILE,d2
g_findstream:
        BENTER
        lea     -256(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE
g_endread:
        bsr     rt_this
        move.l  PR_CIS(a3),d1
        bra.s   g_endstream
g_endwrite:
        bsr     rt_this
        move.l  PR_COS(a3),d1
g_endstream:
        BENTER
        tst.l   d1
        beq.s   .es_ret
        bsr     rt_this
        move.l  PR_RESULT2(a3),d7    ; Result2 preserved (spec §5.1)
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_CLOSE(a6)
        move.l  d7,d0
        bsr     rt_setr2
.es_ret:
        BLEAVE

; 81 load(name) -> seglist (LoadSeg, BSTR name); 82 unloadseg(seg).
g_load:
        BENTER
        lea     -256(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE
g_unloadseg:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
        BLEAVE

; 88 callexec(lvo, d0, d1, a0, a1, a2) / 103 calllib(base, lvo, d0, d1, a0, a1) -> d0 of the called function.
g_callexec:
        BENTER
        move.l  d1,d7                ; lvo
        move.l  d2,d0
        move.l  d3,d1
        move.l  d4,a0
        movem.l 16(a4),a1-a2
        move.l  ($4).w,a6
        jsr     0(a6,d7.l)
        move.l  d0,d1
        BLEAVE
g_calllib:
        BENTER
        move.l  d1,a6                ; base
        move.l  d2,d7                ; lvo
        move.l  d3,d0
        move.l  d4,d1
        movem.l 16(a4),a0-a1
        jsr     0(a6,d7.l)
        move.l  d0,d1
        BLEAVE

; 90 deleteobj(name) -> boolean (ACTION_DELETE_OBJECT) / 125 createdir(name) -> lock | 0 (ACTION_CREATE_DIR): BSTR
; name, through the DeleteFile / CreateDir LVOs (name resolution and handler startup included).
g_deleteobj:
        moveq   #DOS_LVO_DELETEFILE,d0
        bra.s   g_namelvo
g_createdir:
        moveq   #DOS_LVO_CREATEDIR,d0
g_namelvo:
        BENTER
        lea     -256(sp),sp
        move.l  d0,d7
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     0(a6,d7.w)
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE

; 91 rename(old, new): BSTR names -> boolean (Rename LVO: ACTION_RENAME_OBJECT; different handlers ->
; Result2 = 215).
g_rename:
        BENTER
        lea     -512(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  d2,d1
        lea     256(sp),a0
        bsr     rt_cstr
        move.l  sp,d1
        lea     256(sp),a0
        move.l  a0,d2
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_RENAME(a6)
        move.l  d0,d1
        lea     512(sp),sp
        BLEAVE

; 113 copydir(lock) -> DupLock (ACTION_COPY_DIR to the lock's handler); 0 -> 0.
g_copydir:
        BENTER
        move.l  d1,d0
        lsl.l   #2,d0
        beq.s   .cp_zero
        move.l  d0,a0
        move.l  FL_TASK(a0),a1
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        moveq   #ACTION_COPY_DIR,d0
        moveq   #0,d2
        moveq   #0,d3
        move.l  ($4).w,a6
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        move.l  d0,d1
        BLEAVE
.cp_zero:
        moveq   #0,d1
        BLEAVE

; -2 copyvec(src, dst, n): copies n+1 longs from BADDR(src) to BADDR(dst).
g_copyvec:
        lsl.l   #2,d1
        move.l  d1,a3
        lsl.l   #2,d2
        move.l  d2,a4                ; (a4 reloaded by bcpl_ret)
.cv_lp:
        move.l  (a3)+,(a4)+
        subq.l  #1,d3
        bpl.s   .cv_lp
        jmp     (a6)

; 107 splitname(prefix, char, string, pos): copies the characters of the BSTR string from position pos (1 = 1st
; character) up to char (excluded) into the BSTR prefix (30 characters max) -> position after char | 0 if char absent.
g_splitname:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a0                ; a0 = prefix
        lsl.l   #2,d3
        move.l  d3,a3                ; a3 = string
        moveq   #0,d5
        move.b  (a3),d5              ; d5 = length of the string
        moveq   #0,d6                ; d6 = length of the prefix
        move.l  d4,d7                ; d7 = current position
.sn_lp:
        cmp.l   d5,d7
        bgt.s   .sn_none
        move.b  0(a3,d7.l),d0
        addq.l  #1,d7
        cmp.b   d2,d0
        beq.s   .sn_hit
        cmp.l   #30,d6
        bhs.s   .sn_lp
        addq.l  #1,d6
        move.b  d0,0(a0,d6.l)
        bra.s   .sn_lp
.sn_hit:
        move.b  d6,(a0)
        move.l  d7,d1
        BLEAVE
.sn_none:
        move.b  d6,(a0)
        moveq   #0,d1
        BLEAVE

; rt_devinfo() -> a0 = DosInfo (address). Clobbers d0.
rt_devinfo:
        move.l  DOS_DOSBASE,a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_INFO(a0),d0
        lsl.l   #2,d0
        move.l  d0,a0
        rts

; 85 makedevnode(name): BSTR name without ":". DosList node of 11 longs (getvec) + copy of the name (followed by a NUL),
; fields at 0 except dn_Name and dn_GlobalVec (left to the caller), inserted at the head of di_DevInfo under Forbid.
; -> BPTR of the node | 0 (Result2 = 103).
g_makedevnode:
        BENTER
        move.l  ($4).w,a6
        move.l  d1,d5                ; d5 = name
        moveq   #10,d1
        bsr     rt_getvec_raw
        move.l  d0,d6                ; d6 = node (BPTR)
        beq     .md_fail
        move.l  d5,d0
        lsl.l   #2,d0
        move.l  d0,a3                ; a3 = source name
        moveq   #0,d1
        move.b  (a3),d1
        addq.l  #1,d1
        lsr.l   #2,d1                ; getvec((L+1)/4) = (L+1)/4+1 longs >= L+2 bytes (length + L chars + NUL)
        bsr     rt_getvec_raw
        tst.l   d0
        beq     .md_free
        move.l  d0,d7                ; d7 = copy of the name (BPTR)
        lsl.l   #2,d0
        move.l  d0,a4
        moveq   #0,d1
        move.b  (a3),d1
.md_cpy:
        move.b  (a3)+,(a4)+
        dbra    d1,.md_cpy
        clr.b   (a4)                 ; NUL after the name (CreateProc of a C handler uses it as a C string)
        move.l  d6,d0
        lsl.l   #2,d0
        move.l  d0,a3                ; a3 = node
        moveq   #DN_GLOBALVEC/4-1,d1
        move.l  a3,a4
.md_clr:
        clr.l   (a4)+
        dbra    d1,.md_clr
        move.l  d7,DN_NAME(a3)
        jsr     LVO_FORBID(a6)
        bsr     rt_devinfo
        move.l  DI_DEVINFO(a0),DN_NEXT(a3)
        move.l  d6,DI_DEVINFO(a0)
        jsr     LVO_PERMIT(a6)
        move.l  d6,d1
        BLEAVE
.md_free:
        move.l  d6,d0
        lsl.l   #2,d0
        move.l  d0,a1
        subq.l  #4,a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
.md_fail:
        moveq   #103,d0              ; ERROR_NO_FREE_STORE
        bsr     rt_setr2
        moveq   #0,d1
        BLEAVE

; 124 finddevinfo(name): BSTR name without ":", case-insensitive -> first DLT_DEVICE node of that name, otherwise the
; last same-name node of another type, otherwise 0. Result2 unchanged.
g_finddevinfo:
        BENTER
        move.l  d1,d5                ; d5 = name looked up
        moveq   #0,d6                ; d6 = last same-name non-device
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        bsr     rt_devinfo
        move.l  DI_DEVINFO(a0),d7
.fd_lp:
        lsl.l   #2,d7
        beq.s   .fd_end
        move.l  d7,a3
        move.l  DN_NAME(a3),d1
        move.l  d5,d2
        movem.l a3,-(sp)
        bsr     rt_compbstr
        movem.l (sp)+,a3
        tst.l   d0
        bne.s   .fd_next
        move.l  a3,d0
        lsr.l   #2,d0
        tst.l   DN_TYPE(a3)
        beq.s   .fd_dev
        move.l  d0,d6
.fd_next:
        move.l  DN_NEXT(a3),d7
        bra.s   .fd_lp
.fd_dev:
        move.l  d0,d6
.fd_end:
        jsr     LVO_PERMIT(a6)
        move.l  d6,d1
        BLEAVE

; -26 IsInteractive(fh): returns the raw fh_Interactive (not normalised, as in V34).
g_isinteractive:
        lsl.l   #2,d1
        beq.s   .ia_ret
        move.l  d1,a3
        move.l  FH_INTERACTIVE(a3),d1
.ia_ret:
        jmp     (a6)

; 33 createproc(segarray, stack, pri, name, gv): stack in LONGS, BSTR name, BPTR gv (5th argument; 0 -> creator's GV).
; Process + stack (proc_create), inherits ConsoleTask/FileSystemTask/WindowPtr, starts in bcpl_proc_entry. Under
; Forbid until the fields are set. -> taskid (MsgPort) | 0 (Result2 = 103).
g_createproc:
        BENTER
        move.l  d1,d5                ; segarray
        move.l  d2,d6
        lsl.l   #2,d6                ; stack in bytes
        add.l   #CP_STKEXTRA,d6      ; margin: our runtime uses the 68000 stack (buffers, packets)
        move.l  d3,d7                ; pri
        move.l  16(a4),d1            ; gv (5th argument)
        lsl.l   #2,d1
        bsr     rt_createproc
        move.l  d0,d1
        BLEAVE

; rt_createproc(d1 = GV APTR (0 -> creator's GV), d4 = BSTR name, d5 = BPTR segarray, d6 = stack in bytes, d7 = pri)
; -> d0 = taskid (MsgPort) | 0 (Result2 = 103). Process starting in bcpl_proc_entry; inherits ConsoleTask,
; FileSystemTask, WindowPtr from the creator; fields set under Forbid. Preserves d1-d7/a0-a6.
rt_createproc:
        movem.l d1-d2/a0-a1/a3/a6,-(sp)
        move.l  ($4).w,a6
        move.l  d1,d2                ; d2 = GV
        moveq   #32,d0               ; C name (lives as long as the process)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .cp_fail
        move.l  d0,a0
        move.l  d4,d1
        lsl.l   #2,d1
        beq.s   .cp_named
        move.l  d1,a1
        moveq   #0,d1
        move.b  (a1)+,d1
        cmp.w   #31,d1
        bls.s   .cp_ncpy
        moveq   #31,d1
        bra.s   .cp_ncpy
.cp_nlp:
        move.b  (a1)+,(a0)+
.cp_ncpy:
        dbra    d1,.cp_nlp
.cp_named:
        move.l  d0,-(sp)             ; C name (freed if the creation fails)
        move.l  d0,a0
        jsr     LVO_FORBID(a6)
        lea     bcpl_proc_entry(pc),a1
        move.l  d7,d0
        move.l  d6,d1
        jsr     proc_create          ; d0 = &pr_MsgPort | 0
        move.l  (sp)+,a3             ; (Permit may clobber a0/a1)
        tst.l   d0
        beq.s   .cp_failp
        move.l  d0,a0
        lea     -PR_MSGPORT(a0),a0   ; a0 = new process
        bsr     rt_this              ; a3 = creator
        move.l  d5,PR_SEGLIST(a0)
        tst.l   d2
        bne.s   .cp_gv
        move.l  PR_GLOBVEC(a3),d2
.cp_gv:
        move.l  d2,PR_GLOBVEC(a0)
        move.l  PR_CONSOLETASK(a3),PR_CONSOLETASK(a0)
        move.l  PR_FILESYSTEMTASK(a3),PR_FILESYSTEMTASK(a0)
        move.l  PR_WINDOWPTR(a3),PR_WINDOWPTR(a0)
        jsr     LVO_PERMIT(a6)
        bra.s   .cp_ret
.cp_failp:
        jsr     LVO_PERMIT(a6)
        move.l  a3,a1
        moveq   #32,d0
        jsr     LVO_FREEMEM(a6)
.cp_fail:
        moveq   #103,d0
        bsr     rt_setr2
        moveq   #0,d0
.cp_ret:
        movem.l (sp)+,d1-d2/a0-a1/a3/a6
        rts

; 34 endtask(): end of the current process.
g_endtask:
        move.l  ($4).w,a6
        sub.l   a1,a1
        jsr     LVO_REMTASK(a6)
.et_hang:
        bra.s   .et_hang

; 40 readbytes(adr, n) / 43 writebytes(adr, n): Read(input(), ...) / Write(output(), ...) on a byte address.
g_readbytes:
        BENTER
        move.l  d2,d3
        move.l  d1,d2
        bsr     rt_this
        move.l  PR_CIS(a3),d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_READ(a6)
        move.l  d0,d1
        BLEAVE
g_writebytes:
        BENTER
        move.l  d2,d3
        move.l  d1,d2
        bsr     rt_this
        move.l  PR_COS(a3),d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_WRITE(a6)
        move.l  d0,d1
        BLEAVE

; 41 taskwait() -> BPTR of the next packet received on the process port.
g_taskwait:
        BENTER
        bsr     rt_this
        move.l  ($4).w,a6
.tw_lp:
        lea     PR_MSGPORT(a3),a0
        jsr     LVO_WAITPORT(a6)
        lea     PR_MSGPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .tw_lp
        move.l  d0,a0
        move.l  LN_NAME(a0),d1
        lsr.l   #2,d1
        BLEAVE

; 42 qpkt(pkt): sends the packet to dp_Port (message dp_Link, ln_Name := packet); dp_Port := process port (the
; reply will come back here). dp_Link <= 0 -> 0 (Result2 = 101); otherwise -1.
; 49 returnpkt(pkt, res1, res2): sets the results then qpkt (return to the sender).
g_returnpkt:
        move.l  d1,d0
        lsl.l   #2,d0
        move.l  d0,a3
        move.l  d2,DP_RES1(a3)
        move.l  d3,DP_RES2(a3)
g_qpkt:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a4                ; a4 = packet
        move.l  DP_LINK(a4),d0
        ble.s   .qp_bad
        bsr     rt_this
        lea     PR_MSGPORT(a3),a3    ; a3 = process port
        move.l  d0,a1                ; message
        move.l  a4,LN_NAME(a1)       ; message -> packet
        move.l  DP_PORT(a4),a0       ; destination
        move.l  a3,DP_PORT(a4)
        move.l  a3,MN_REPLYPORT(a1)
        move.l  ($4).w,a6
        jsr     LVO_PUTMSG(a6)
        moveq   #-1,d1
        BLEAVE
.qp_bad:
        moveq   #101,d0
        bsr     rt_setr2
        moveq   #0,d1
        BLEAVE

; 121 runcommand(seg, stack, args, len): runs the first hunk of seg on a new stack of "stack" longs (spec §4.3),
; plus the CP_STKEXTRA margin (our runtime takes its buffers and packets on the command's 68000 stack):
; a0 = BADDR(args), d0 = len, 4(sp) = size, pr_ReturnAddr -> this long, A1 = calling frame, A2 = current GV, A3 =
; segment, A5/A6 = BCPL call/return. -> return code (d0 of the command); -1 if stack impossible. Result2 intact.
g_runcommand:
        BENTER
        move.l  d1,d5                ; seg
        move.l  d2,d6                ; stack (longs)
        move.l  d3,d7                ; args (BPTR)
        move.l  a4,d3                ; d3 = calling frame (a1 is clobbered by AllocMem)
        move.l  ($4).w,a6
        add.l   #CP_STKEXTRA/4,d6    ; margin: our runtime uses the command's 68000 stack (buffers, packets)
        move.l  d6,d1
        bsr     rt_getvec_raw
        tst.l   d0
        beq     .rcm_fail
        bsr     rt_this              ; a3 = process
        move.l  PR_RETURNADDR(a3),-(sp)   ; restored on return
        move.l  d0,-(sp)             ; stack (BPTR), freed on return
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  d6,d1
        addq.l  #1,d1
        lsl.l   #2,d1
        add.l   d1,a0                ; a0 = top of the vector
        lsl.l   #2,d6                ; d6 = size in bytes
        move.l  sp,-(a0)             ; old SP (8(sp) on entry)
        move.l  d6,-(a0)             ; size (4(sp) on entry)
        move.l  a0,PR_RETURNADDR(a3)
        move.l  d5,d0
        lsl.l   #2,d0
        move.l  d0,a3                ; a3 = segment
        lea     4(a3),a4             ; a4 = entry point
        lsl.l   #2,d7                ; d7 = address of the arguments
        move.l  d4,d0                ; d0 = length
        move.l  d6,d2                ; d2 = size (not contractual)
        move.l  a0,sp                ; switch to the new stack
        move.l  d7,a0                ; a0 = arguments
        move.l  d3,a1                ; a1 = calling frame
        moveq   #0,d1
        lea     bcpl_call(pc),a5
        lea     bcpl_ret(pc),a6
        jsr     (a4)                 ; d0 = return code
        addq.l  #4,sp
        move.l  (sp),sp              ; back on the caller's stack
        move.l  d0,d5
        move.l  (sp)+,d7             ; stack
        bsr     rt_this
        move.l  (sp)+,PR_RETURNADDR(a3)
        lsl.l   #2,d7
        move.l  d7,a1
        subq.l  #4,a1
        move.l  (a1),d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  d5,d1
        BLEAVE
.rcm_fail:
        moveq   #-1,d1
        BLEAVE

; bcpl_execute: Execute LVO(cmd d1 [C], in d2, out d3) -> d0 = DOSTRUE | DOSFALSE (global 101, spec §8.2): loads
; C:Run, selects in/out, pr_Result2 := BSTR of the command, runcommand(Run, 600 longs); Run creates a background CLI
; that executes the command then reads the rest from "in" (Execute("", window, 0) = interactive CLI in the window).
; The caller must have a GV (pr_GlobVec: inherited through CreateProc). Streams and Result2 restored on return.
EX_FRAME        EQU 256                 ; BCPL frame of the caller built on the stack (Run makes its first calls there)
bcpl_execute:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,a4                   ; a4 = C command
        move.l  d2,d6                   ; d6/d7 = in/out
        move.l  d3,d7
        bsr     rt_this
        tst.l   PR_GLOBVEC(a3)
        beq     .ex_fail
        bsr     rt_devinfo              ; Run's background CLI needs a CLI segment: "CLI" resident ...
        move.l  DI_RESLIST(a0),d0
.ex_res:
        lsl.l   #2,d0
        beq.s   .ex_cons
        move.l  d0,a0
        cmp.b   #3,12(a0)
        bne.s   .ex_rnx
        move.l  12(a0),d0
        and.l   #$FFDFDFDF,d0
        cmp.l   #$03434C49,d0           ; BSTR "CLI" (case ignored)
        beq.s   .ex_go
.ex_rnx:
        move.l  (a0),d0
        bra.s   .ex_res
.ex_cons:
        move.l  DOS_DOSBASE,a0          ; ... or rn_ConsoleSegment (the ROM CLI of shell.s); otherwise failure,
        move.l  DL_ROOT(a0),a0          ; as before the "resident CLI L:Shell-Seg" of the startup-sequence
        tst.l   RN_CONSOLESEG(a0)
        beq     .ex_fail
.ex_go:
        move.l  ($4).w,a6
        moveq   #64,d1                  ; BSTR of the command (255 bytes at most) in a getvec vector
        bsr     rt_getvec_raw
        move.l  d0,d5                   ; d5 = BPTR of the command
        beq     .ex_fail
        lsl.l   #2,d0
        move.l  d0,a0
        lea     1(a0),a1
        moveq   #0,d0
.ex_cpy:
        move.b  (a4)+,d1
        beq.s   .ex_cpyd
        move.b  d1,(a1)+
        addq.b  #1,d0
        cmp.b   #255,d0
        bne.s   .ex_cpy
.ex_cpyd:
        move.b  d0,(a0)
        move.l  DOS_DOSBASE,a6
        move.l  #ex_runname,d1
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  d0,d4                   ; d4 = Run
        beq     .ex_free
        bsr     rt_this
        move.l  PR_SEGLIST(a3),-(sp)    ; caller's segarray: during Run, [2, V!1, V!2] (Run's stub does
        lea     -16(sp),sp              ; globin of each entry: the seglist of a C program, entry 3 of a
        move.l  sp,d0                   ; CreateProc process, is not a BCPL segment)
        addq.l  #3,d0
        and.w   #-4,d0                  ; long-aligned (BPTR)
        move.l  d0,a0
        move.l  #2,(a0)
        move.l  PR_SEGLIST(a3),d1
        lsl.l   #2,d1
        beq.s   .ex_noseg
        move.l  d1,a1
        move.l  4(a1),4(a0)
        move.l  8(a1),8(a0)
.ex_noseg:
        lsr.l   #2,d0
        move.l  d0,PR_SEGLIST(a3)
        move.l  PR_CONSOLETASK(a3),-(sp) ; console, streams and Result2 of the caller, restored on return
        move.l  PR_CIS(a3),-(sp)
        move.l  PR_COS(a3),-(sp)
        move.l  PR_RESULT2(a3),-(sp)
        move.l  d5,-(sp)                ; command vector and Run: d4/d5 do not survive runcommand
        move.l  d4,-(sp)
        clr.l   -(sp)                   ; (sp) = output opened here (to be closed again if Run fails)
        move.l  d6,d0                   ; input on a handler: it becomes the console ("*") of the caller, hence
        lsl.l   #2,d0                   ; of the CLI that Run creates; null output -> "*" on that console (AutoDoc:
        beq.s   .ex_streams             ; output in the current window)
        move.l  d0,a0
        move.l  FH_TYPE(a0),d0
        beq.s   .ex_streams
        move.l  d0,PR_CONSOLETASK(a3)
        tst.l   d7
        bne.s   .ex_streams
        move.l  DOS_DOSBASE,a6
        move.l  #ex_star,d1
        move.l  #MODE_NEWFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,d7
        move.l  d0,(sp)
        bsr     rt_this
.ex_streams:
        move.l  d6,PR_CIS(a3)
        move.l  d7,PR_COS(a3)
        move.l  d5,PR_RESULT2(a3)
        move.l  PR_GLOBVEC(a3),a2
        lea     -EX_FRAME(sp),sp
        move.l  sp,a1                   ; BCPL frame: Run writes above it (upwards), the 68000 stack grows down
        move.l  d4,d1                   ; runcommand(Run, 600, no injected arguments: command in Result2)
        move.l  #600,d2
        moveq   #0,d3
        moveq   #0,d4
        lea     .ex_back(pc),a6         ; runcommand's BLEAVE returns through jmp (a6)
        bra     g_runcommand
.ex_back:
        lea     EX_FRAME(sp),sp
        move.l  d1,d2                   ; d2 = return code (-1: stack impossible)
        move.l  (sp)+,d3                ; output opened here
        move.l  (sp)+,d4
        move.l  (sp)+,d5
        bsr     rt_this
        move.l  (sp)+,PR_RESULT2(a3)
        move.l  (sp)+,PR_COS(a3)
        move.l  (sp)+,PR_CIS(a3)
        move.l  (sp)+,PR_CONSOLETASK(a3)
        lea     16(sp),sp
        move.l  (sp)+,PR_SEGLIST(a3)
        move.l  DOS_DOSBASE,a6
        tst.l   d2
        bpl.s   .ex_owned               ; the created CLI owns the output
        move.l  d3,d1
        beq.s   .ex_owned
        jsr     DOS_LVO_CLOSE(a6)
.ex_owned:
        move.l  d4,d1
        jsr     DOS_LVO_UNLOADSEG(a6)
        bsr.s   .ex_vfree
        moveq   #-1,d0
        tst.l   d2
        bpl.s   .ex_ret
        moveq   #0,d0
        bra.s   .ex_ret
.ex_free:
        bsr.s   .ex_vfree
.ex_fail:
        moveq   #0,d0
.ex_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts
.ex_vfree:                              ; free the command vector (getvec header)
        move.l  d5,d0
        lsl.l   #2,d0
        move.l  d0,a1
        subq.l  #4,a1
        move.l  (a1),d0
        move.l  ($4).w,a6
        jmp     LVO_FREEMEM(a6)
ex_runname:
        dc.b    "C:Run",0
ex_star:
        dc.b    "*",0
        even

; 3 mult(a, b) -> a*b; 4 div(a, b) -> a/b (truncation towards 0); 5 rem(a, b) -> remainder (sign of the dividend).
g_mult:
        bsr     bcpl_mul
        jmp     (a6)
g_div:
        bsr     bcpl_divmod
        jmp     (a6)
g_rem:
        bsr     bcpl_divmod
        move.l  d2,d1
        jmp     (a6)

; -20 clearvec(v, n): clears the n+1 longs of BADDR(v).
g_clearvec:
        lsl.l   #2,d1
        move.l  d1,a3
.clv_lp:
        clr.l   (a3)+
        subq.l  #1,d2
        bpl.s   .clv_lp
        jmp     (a6)

; -1 Open(C name, mode) / -3 Read(fh, buffer, n) / -6 Write(fh, buffer, n) / -8 Seek(fh, pos, mode): C ABI adapters
; (the arguments d1-d3 are already those of the dos LVOs).
g_copen:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,d1
        BLEAVE
g_cread:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_READ(a6)
        move.l  d0,d1
        BLEAVE
g_cwrite:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_WRITE(a6)
        move.l  d0,d1
        BLEAVE
g_cseek:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_SEEK(a6)
        move.l  d0,d1
        BLEAVE

; 37 testflags(m): tests AND clears the CTRL bits of m (bit0 = CTRL-C ... bit3 = CTRL-F) -> -1 if one was set.
g_testflags:
        BENTER
        moveq   #12,d0
        lsl.l   d0,d1                ; SIGBREAKB_CTRL_C = 12
        move.l  d1,d2
        moveq   #0,d0
        move.l  ($4).w,a6
        jsr     LVO_SETSIGNAL(a6)    ; d0 = new (0), d1 = mask -> clears and returns the old state
        and.l   d2,d0
        sne     d1
        ext.w   d1
        ext.l   d1
        BLEAVE

; 36 setflags(taskid, m): Signal of the CTRL bits of m (bit0 = CTRL-C ... bit3 = CTRL-F) to the process whose taskid is
; the MsgPort (its task = mp_SigTask). taskid 0: nothing.
g_setflags:
        BENTER
        tst.l   d1
        beq.s   .sf_ret
        move.l  d1,a0
        move.l  MP_SIGTASK(a0),a1
        moveq   #12,d0
        lsl.l   d0,d2
        move.l  d2,d0
        move.l  ($4).w,a6
        jsr     LVO_SIGNAL(a6)
.sf_ret:
        BLEAVE

; 6 setio(iob, cmd, data, len, offset): iob BPTR of an IOStdReq; io_Command (word) := cmd, io_Data := BADDR(data),
; io_Length := len, io_Offset := offset (5th argument).
g_setio:
        lsl.l   #2,d1
        move.l  d1,a3
        move.w  d2,IO_COMMAND(a3)
        lsl.l   #2,d3
        move.l  d3,IOSTD_DATA(a3)
        move.l  d4,IOSTD_LENGTH(a3)
        move.l  16(a1),IOSTD_OFFSET(a3)
        jmp     (a6)

; 21 doio(iob) -> io_Error (DoIO); 22 sendio(iob, pkt): links the request to the packet (ln_Name = packet, dp_Link =
; request: taskwait will return this packet on the reply) then SendIO; 32 closedevice(iob).
g_doio:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a1
        move.l  ($4).w,a6
        jsr     LVO_DOIO(a6)
        move.l  d0,d1
        BLEAVE
g_sendio:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a1
        lsl.l   #2,d2
        move.l  d2,LN_NAME(a1)
        move.l  d2,a0
        move.l  a1,DP_LINK(a0)
        move.l  ($4).w,a6
        jsr     LVO_SENDIO(a6)
        BLEAVE
g_closedevice:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a1
        move.l  ($4).w,a6
        jsr     LVO_CLOSEDEVICE(a6)
        BLEAVE

; 31 opendevice(iob, name, unit, flags): BSTR name followed by a NUL; ln_Name := name, reply port := MsgPort of the
; process, mn_Length := 12 (V34 values) -> -1 success | 0.
g_opendevice:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a1
        lsl.l   #2,d2
        addq.l  #1,d2
        move.l  d2,a0                ; C name
        move.l  a0,LN_NAME(a1)
        bsr     rt_this
        lea     PR_MSGPORT(a3),a3
        move.l  a3,MN_REPLYPORT(a1)
        move.w  #12,MN_LENGTH(a1)
        move.l  d3,d0
        move.l  d4,d1
        move.l  ($4).w,a6
        jsr     LVO_OPENDEVICE(a6)
        tst.l   d0
        seq     d1
        ext.w   d1
        ext.l   d1
        BLEAVE

; 50 openwindow(x, y, w, h, title) -> APTR Window | 0: OpenWindow (IntuitionBase = GV[92]) with a NewWindow on the
; stack (handlers spec §supplement): pens $FF/$FF, IDCMP 0, Flags $00021007, title = BADDR(title) (C string),
; Min 120x50, Max $FFFFx$FFFF, Type WBENCHSCREEN.
OW_NWSIZE       EQU 48
g_openwindow:
        BENTER
        lea     -OW_NWSIZE(sp),sp
        move.l  sp,a0
        move.w  d1,(a0)+             ; LeftEdge
        move.w  d2,(a0)+             ; TopEdge
        move.w  d3,(a0)+             ; Width
        move.w  d4,(a0)+             ; Height
        move.w  #$FFFF,(a0)+         ; DetailPen, BlockPen
        clr.l   (a0)+                ; IDCMPFlags
        move.l  #$00021007,(a0)+     ; Flags
        clr.l   (a0)+                ; FirstGadget
        clr.l   (a0)+                ; CheckMark
        move.l  16(a4),d0
        lsl.l   #2,d0
        move.l  d0,(a0)+             ; Title
        clr.l   (a0)+                ; Screen
        clr.l   (a0)+                ; BitMap
        move.l  #(120<<16)|50,(a0)+  ; MinWidth, MinHeight
        move.l  #$FFFFFFFF,(a0)+     ; MaxWidth, MaxHeight
        move.w  #1,(a0)              ; Type = WBENCHSCREEN
        move.l  sp,a0
        move.l  92*4(a2),a6          ; IntuitionBase
        jsr     LVO_OPENWINDOW(a6)
        move.l  d0,d1
        lea     OW_NWSIZE(sp),sp
        BLEAVE

; 86 datstamp(v): DateStamp into v!0..v!2 (days, minutes, ticks) -> v.
g_datstamp:
        BENTER
        move.l  d1,d5
        lsl.l   #2,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_DATESTAMP(a6)
        move.l  d5,d1
        BLEAVE

; 128 setdatstamp(v): sets the system time to the vector [days, minutes, ticks] (BPTR); result not
; significant. 126 compstamp(a, b): 0 if equal, +1 if a is more recent than b, -1 otherwise (days, minutes, ticks).
g_setdatstamp:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a0
        jsr     dos_setnow
        moveq   #0,d1
        BLEAVE
g_compstamp:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a0
        lsl.l   #2,d2
        move.l  d2,a1
        moveq   #2,d3
.cs_lp:
        move.l  (a0)+,d0
        cmp.l   (a1)+,d0
        bgt.s   .cs_newer
        blt.s   .cs_older
        dbra    d3,.cs_lp
        moveq   #0,d1
        BLEAVE
.cs_newer:
        moveq   #1,d1
        BLEAVE
.cs_older:
        moveq   #-1,d1
        BLEAVE

g_rootstruct:
        move.l  DOS_DOSBASE,a3
        move.l  DL_ROOT(a3),d1
        lsr.l   #2,d1
        jmp     (a6)

; 48 sendpkt(_, port, type, res1, res2, arg1...): the ARGUMENT FRAME is the DosPacket (Link, Port, Type, Res1,
; Res2, Arg1...). Synchronous send to the port, reply on the process port; -> dp_Res1; Result2 := dp_Res2.
g_sendpkt:
        BENTER
        move.l  DP_PORT(a4),-(sp)    ; destination, kept for a resend
        lea     -MN_SIZE(sp),sp      ; exec Message on the 68000 stack
        move.l  sp,a0
        moveq   #(MN_SIZE/2)-1,d0
.sp_clr:
        clr.w   (a0)+
        dbra    d0,.sp_clr
        move.l  sp,a0
        move.b  #NT_MESSAGE,LN_TYPE(a0)
        move.l  a4,LN_NAME(a0)       ; msg -> packet (= the frame)
        bsr     rt_this
        lea     PR_MSGPORT(a3),a3    ; reply port
        move.l  a3,MN_REPLYPORT(a0)
        move.l  a0,DP_LINK(a4)
        move.l  ($4).w,a6
.sk_send:
        move.l  a3,DP_PORT(a4)       ; the handler replies to the process port
        move.l  sp,a1                ; a1 = message
        move.l  MN_SIZE(sp),a0       ; a0 = destination (argument 2)
        jsr     LVO_PUTMSG(a6)       ; PutMsg(port a0, message a1)
.sk_wait:
        move.l  a3,a0
        jsr     LVO_WAITPORT(a6)
        move.l  a3,a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq     .sk_wait
        move.l  DP_RES1(a4),d0
        move.l  DP_RES2(a4),d1
        jsr     dos_pktretry         ; volume ejected: "Please replace volume", Retry -> resend
        tst.l   d0
        beq.s   .sk_done
        clr.l   DP_RES1(a4)
        clr.l   DP_RES2(a4)
        bra.s   .sk_send
.sk_done:
        move.l  DP_RES2(a4),d0
        bsr     rt_setr2
        move.l  DP_RES1(a4),d1
        lea     MN_SIZE+4(sp),sp
        BLEAVE

; 51 currentdir(set, lock): set = 0 -> returns pr_CurrentDir; otherwise returns the old one and writes lock.
g_currentdir:
        bsr     rt_this
        move.l  PR_CURRENTDIR(a3),d0
        tst.l   d1
        beq     .cd_get
        move.l  d2,PR_CURRENTDIR(a3)
.cd_get:
        move.l  d0,d1
        jmp     (a6)

; 54 rdch() / 55 unrdch() / 56 wrch(c)
g_rdch:
        BENTER
        bsr     rt_rdch
        move.l  d0,d1
        BLEAVE
g_unrdch:
        BENTER
        bsr     rt_unrdch
        move.l  d0,d1
        BLEAVE
g_wrch:
        BENTER
        move.b  d1,-(sp)
        move.l  sp,a0
        moveq   #1,d0
        bsr     rt_write
        addq.l  #2,sp                ; (move.b -(sp) decrements by 2: SP stays even)
        BLEAVE

; 61 selectinput(fh) / 62 selectoutput(fh) / 65 input() / 66 output()
g_selectinput:
        bsr     rt_this
        move.l  d1,PR_CIS(a3)
        jmp     (a6)
g_selectoutput:
        bsr     rt_this
        move.l  d1,PR_COS(a3)
        jmp     (a6)
g_input:
        bsr     rt_this
        move.l  PR_CIS(a3),d1
        jmp     (a6)
g_output:
        bsr     rt_this
        move.l  PR_COS(a3),d1
        jmp     (a6)

; --- formatted output: each global opens a WF_BUFSZ buffer on the stack (a5 = start, a3 = position) ---
WFOPEN          MACRO                ; in a BCPL global, right after BENTER
        lea     -WF_BUFSZ-4(sp),sp
        move.l  sp,a5
        move.l  sp,a3
        bsr     wf_gvsel
                ENDM
WFRAW           MACRO                ; called from assembly (no GV): straight to the output stream
        lea     -WF_BUFSZ-4(sp),sp
        move.l  sp,a5
        move.l  sp,a3
        clr.l   WF_WRCH(a5)
                ENDM
WFCLOSE         MACRO
        bsr     wf_flush
        lea     WF_BUFSZ+4(sp),sp
                ENDM

; 53 writet(s, w): BSTR then spaces up to w columns.
g_writet:
        BENTER
        WFOPEN
        move.l  d2,d3
        bsr     wf_bstr
        move.l  d3,d0
        sub.l   d2,d0
        bsr     wf_spaces
        WFCLOSE
        BLEAVE

; 68 newline()
g_newline:
        BENTER
        WFOPEN
        moveq   #10,d0
        bsr     wf_putc
        WFCLOSE
        BLEAVE

; 69 writed(n, w) / 70 writen(n) / 71 writehex(n, d) / 72 writeoct(n, d)
g_writed:
        BENTER
        moveq   #10,d3
        moveq   #0,d4
        bra     g_numout
g_writen:
        BENTER
        moveq   #0,d2
        moveq   #10,d3
        moveq   #0,d4
        bra     g_numout
g_writehex:
        BENTER
        moveq   #16,d3
        moveq   #2,d4
        bra     g_numout
g_writeoct:
        BENTER
        moveq   #8,d3
        moveq   #2,d4
g_numout:
        WFOPEN
        bsr     wf_num
        WFCLOSE
        BLEAVE

; 73 writes(s): writes the BSTR s.
g_writes:
        BENTER
        WFOPEN
        bsr     wf_bstr
        WFCLOSE
        BLEAVE

; 74 writef(fmt, a1, a2, ...): BSTR fmt; arguments = following longs of the frame. Codes (case-insensitive):
; %S BSTR, %T BSTR on width w, %C character, %N decimal, %I decimal width w, %U unsigned width w, %X hex w
; digits, %O octal w digits, %$ skips an argument; other letter: written as is (%% -> %). Width =
; next character: 0-9, or letter (A = 10...).
g_writef:
        BENTER
        WFOPEN
        lea     4(a4),a2             ; a2 = next argument (a2 restored by BLEAVE)
        move.l  d1,d0
        lsl.l   #2,d0
        beq     .wf_end
        move.l  d0,a0                ; a0 = format (BSTR)
        moveq   #0,d5
        move.b  (a0)+,d5             ; d5 = remaining characters
.wf_lp:
        subq.l  #1,d5
        bmi     .wf_end
        move.b  (a0)+,d0
        cmp.b   #'%',d0
        beq     .wf_pct
        bsr     wf_putc
        bra     .wf_lp
.wf_pct:
        subq.l  #1,d5
        bmi     .wf_end
        move.b  (a0)+,d0
        bsr     rt_upper
        cmp.b   #'S',d0
        beq     .wf_s
        cmp.b   #'T',d0
        beq     .wf_t
        cmp.b   #'C',d0
        beq     .wf_c
        cmp.b   #'N',d0
        beq     .wf_n
        cmp.b   #'I',d0
        beq     .wf_i
        cmp.b   #'U',d0
        beq     .wf_u
        cmp.b   #'X',d0
        beq     .wf_x
        cmp.b   #'O',d0
        beq     .wf_o
        cmp.b   #'$',d0
        beq     .wf_skip
        bsr     wf_putc              ; unknown letter (including %): written as is
        bra     .wf_lp
.wf_s:
        move.l  (a2)+,d1
        bsr     wf_bstr
        bra     .wf_lp
.wf_t:
        bsr     .wf_width
        move.l  (a2)+,d1
        move.l  d2,d3
        bsr     wf_bstr
        move.l  d3,d0
        sub.l   d2,d0
        bsr     wf_spaces
        bra     .wf_lp
.wf_c:
        move.l  (a2)+,d0
        bsr     wf_putc
        bra     .wf_lp
.wf_n:
        moveq   #0,d2
        moveq   #10,d3
        moveq   #0,d4
        bra     .wf_num
.wf_i:
        bsr     .wf_width
        moveq   #10,d3
        moveq   #0,d4
        bra     .wf_num
.wf_u:
        bsr     .wf_width
        moveq   #10,d3
        moveq   #1,d4
        bra     .wf_num
.wf_x:
        bsr     .wf_width
        moveq   #16,d3
        moveq   #2,d4
        bra     .wf_num
.wf_o:
        bsr     .wf_width
        moveq   #8,d3
        moveq   #2,d4
.wf_num:
        move.l  (a2)+,d1
        bsr     wf_num
        bra     .wf_lp
.wf_skip:
        addq.l  #4,a2
        bra     .wf_lp
.wf_width:                           ; d2 = width read from the next character (0-9, letter -> 10+)
        moveq   #0,d2
        subq.l  #1,d5
        bmi     .ww_ret
        move.b  (a0)+,d0
        bsr     rt_upper
        cmp.b   #'9',d0
        bhi     .ww_let
        sub.b   #'0',d0
        bra     .ww_set
.ww_let:
        sub.b   #'A'-10,d0
.ww_set:
        and.l   #$FF,d0
        move.l  d0,d2
.ww_ret:
        rts
.wf_end:
        WFCLOSE
        BLEAVE

; 75 capitalch(c) / 76 compch(a, b) / 77 compstring(s1, s2) (0 = equal, case-insensitive)
g_capitalch:
        move.l  d1,d0
        bsr     rt_upper
        and.l   #$FF,d0
        move.l  d0,d1
        jmp     (a6)
g_compch:
        move.l  d1,d0
        bsr     rt_upper
        and.l   #$FF,d0
        move.l  d0,d1
        move.l  d2,d0
        bsr     rt_upper
        and.l   #$FF,d0
        sub.l   d0,d1
        jmp     (a6)
g_compstring:
        BENTER
        bsr     rt_compbstr
        move.l  d0,d1
        BLEAVE

; rt_compbstr(d1, d2 = BSTR) -> d0 = 0 if equal (case-insensitive), otherwise difference at the first mismatch (or of
; the lengths). Clobbers d1-d4/a0/a1.
rt_compbstr:
        lsl.l   #2,d1
        lsl.l   #2,d2
        move.l  d1,a0
        move.l  d2,a1
        moveq   #0,d3
        moveq   #0,d4
        move.b  (a0)+,d3
        move.b  (a1)+,d4
.cb_lp:
        tst.l   d3
        beq     .cb_len
        tst.l   d4
        beq     .cb_len
        move.b  (a0)+,d0
        bsr     rt_upper
        move.b  d0,d1
        move.b  (a1)+,d0
        bsr     rt_upper
        and.l   #$FF,d0
        and.l   #$FF,d1
        sub.l   d0,d1
        bne     .cb_diff
        subq.l  #1,d3
        subq.l  #1,d4
        bra     .cb_lp
.cb_len:
        move.l  d3,d0
        sub.l   d4,d0
        rts
.cb_diff:
        move.l  d1,d0
        rts

; 79 rditem(v, n) -> 1 item, 2 quoted item, 0 end of line, -2 lone "=", -1 error. Item stored as a BSTR in the
; vector v (n+1 longs, cleared at the start). Spec §5.3.
g_rditem:
        BENTER
        bsr     rt_rditem
        move.l  d0,d1
        BLEAVE

; rt_rditem(d1 = BPTR v, d2 = n) -> d0 = result (see g_rditem). Preserves everything except d0.
rt_rditem:
        movem.l d1-d4/a0-a1,-(sp)
        lsl.l   #2,d1
        move.l  d1,a0                ; a0 = vector (BSTR)
        move.l  d2,d3
        addq.l  #1,d3
        move.l  d3,d4
        lsl.l   #2,d4
        subq.l  #1,d4                ; d4 = capacity in characters
        move.l  a0,a1
.ri_clr:
        clr.l   (a1)+
        subq.l  #1,d3
        bgt     .ri_clr
        moveq   #0,d3                ; d3 = length
.ri_skip:
        bsr     rt_rdch
        cmp.b   #' ',d0
        beq     .ri_skip
        cmp.b   #9,d0
        beq     .ri_skip
        cmp.l   #'"',d0
        beq     .ri_quoted
        cmp.l   #10,d0
        beq     .ri_end0
        cmp.l   #';',d0
        beq     .ri_end0
        tst.l   d0
        bmi     .ri_end0
        cmp.l   #'=',d0
        bne     .ri_plain
        moveq   #-2,d0
        bra     .ri_ret
.ri_end0:
        bsr     rt_unrdch
        moveq   #0,d0
        bra     .ri_ret
.ri_plain:
        bsr     .ri_store
        bmi     .ri_err
        bsr     rt_rdch
        cmp.l   #10,d0
        beq     .ri_plainend
        cmp.l   #';',d0
        beq     .ri_plainend
        cmp.l   #' ',d0
        beq     .ri_plainend
        cmp.l   #9,d0
        beq     .ri_plainend
        cmp.l   #'=',d0
        beq     .ri_plainend
        tst.l   d0
        bpl     .ri_plain
.ri_plainend:
        bsr     rt_unrdch
        moveq   #1,d0
        bra     .ri_ret
.ri_quoted:
        bsr     rt_rdch
        cmp.l   #'"',d0
        beq     .ri_qend
        cmp.l   #10,d0
        beq     .ri_err
        tst.l   d0
        bmi     .ri_err
        cmp.l   #'*',d0
        bne     .ri_qstore
        bsr     rt_rdch              ; *N -> LF, *E -> ESC, *x -> x
        cmp.l   #10,d0
        beq     .ri_err
        tst.l   d0
        bmi     .ri_err
        move.l  d0,d1
        bsr     rt_upper
        cmp.b   #'N',d0
        bne     .ri_qe
        moveq   #10,d0
        bra     .ri_qstore
.ri_qe:
        cmp.b   #'E',d0
        bne     .ri_qx
        moveq   #27,d0
        bra     .ri_qstore
.ri_qx:
        move.l  d1,d0
.ri_qstore:
        bsr     .ri_store
        bmi     .ri_err
        bra     .ri_quoted
.ri_qend:
        moveq   #2,d0
        bra     .ri_ret
.ri_err:
        moveq   #-1,d0
.ri_ret:
        movem.l (sp)+,d1-d4/a0-a1
        rts
.ri_store:                           ; d0.b -> item; N = 1 (and Z) if the capacity is exceeded
        cmp.l   d4,d3
        bhs     .rs_full
        addq.l  #1,d3
        move.b  d0,0(a0,d3.l)
        move.b  d3,(a0)
        moveq   #0,d0                ; N = 0
        rts
.rs_full:
        moveq   #-1,d0               ; N = 1
        rts

; 80 findarg(tpl, item) -> index of the key one of whose aliases equals item (case-insensitive) | -1.
g_findarg:
        BENTER
        bsr     rt_findarg
        move.l  d0,d1
        BLEAVE

; rt_findarg(d1 = BSTR template, d2 = BSTR item) -> d0 = index | -1. Preserves d1-d7/a0-a6 except d0.
rt_findarg:
        movem.l d1-d6/a0-a1,-(sp)
        lsl.l   #2,d1
        lsl.l   #2,d2
        move.l  d1,a0                ; a0 = template
        moveq   #0,d5
        move.b  (a0)+,d5             ; d5 = remaining characters of the template
        moveq   #0,d6                ; d6 = current key index
.fa_alias:                           ; compare the current alias (up to = / , end) with the item
        move.l  d2,a1
        moveq   #0,d4
        move.b  (a1)+,d4             ; d4 = length of the item
        moveq   #1,d3                ; d3 = 1 as long as the alias matches
.fa_ch:
        tst.l   d5
        beq     .fa_aend
        move.b  (a0),d0
        cmp.b   #'=',d0
        beq     .fa_aend
        cmp.b   #'/',d0
        beq     .fa_aend
        cmp.b   #',',d0
        beq     .fa_aend
        addq.l  #1,a0
        subq.l  #1,d5
        tst.l   d4
        beq     .fa_miss
        bsr     rt_upper
        move.b  d0,d1
        move.b  (a1)+,d0
        subq.l  #1,d4
        bsr     rt_upper
        cmp.b   d0,d1
        beq     .fa_ch
.fa_miss:
        moveq   #0,d3
        bra     .fa_ch
.fa_aend:
        tst.l   d3
        beq     .fa_next
        tst.l   d4
        bne     .fa_next             ; item longer than the alias
        move.l  d6,d0
        bra     .fa_found
.fa_next:
        tst.l   d5
        beq     .fa_none
        move.b  (a0)+,d0
        subq.l  #1,d5
        cmp.b   #'=',d0
        beq     .fa_alias            ; next alias of the same key
        cmp.b   #',',d0
        bne     .fa_next             ; qualifiers (/A /K /S): advance up to , or =
        addq.l  #1,d6                ; next key
        bra     .fa_alias
.fa_none:
        moveq   #-1,d0
.fa_found:
        movem.l (sp)+,d1-d6/a0-a1
        rts

; rt_tplflags(d1 = BSTR template, d2 = key index) -> d0 = flags (bit0 /A, bit1 /K, bit2 /S); d0 = -1 if the
; key does not exist. Preserves the rest.
rt_tplflags:
        movem.l d1-d5/a0,-(sp)
        lsl.l   #2,d1
        move.l  d1,a0
        moveq   #0,d5
        move.b  (a0)+,d5
        moveq   #0,d3                ; current index
        moveq   #0,d4                ; flags of the current key
.tf_lp:
        tst.l   d5
        beq     .tf_end
        move.b  (a0)+,d0
        subq.l  #1,d5
        cmp.b   #',',d0
        bne     .tf_slash
        cmp.l   d2,d3
        beq     .tf_hit
        addq.l  #1,d3
        moveq   #0,d4
        bra     .tf_lp
.tf_slash:
        cmp.b   #'/',d0
        bne     .tf_lp
        tst.l   d5
        beq     .tf_end
        move.b  (a0)+,d0
        subq.l  #1,d5
        bsr     rt_upper
        cmp.b   #'A',d0
        bne     .tf_k
        bset    #0,d4
.tf_k:
        cmp.b   #'K',d0
        bne     .tf_s
        bset    #1,d4
.tf_s:
        cmp.b   #'S',d0
        bne     .tf_lp
        bset    #2,d4
        bra     .tf_lp
.tf_end:
        cmp.l   d2,d3
        beq     .tf_hit
        moveq   #-1,d0
        bra     .tf_ret
.tf_hit:
        move.l  d4,d0
.tf_ret:
        movem.l (sp)+,d1-d5/a0
        rts

; rt_tplcount(d1 = BSTR template) -> d0 = number of keys (0 for an empty template).
rt_tplcount:
        movem.l d1/d5/a0,-(sp)
        moveq   #0,d0
        lsl.l   #2,d1
        move.l  d1,a0
        moveq   #0,d5
        move.b  (a0)+,d5
        beq     .tc_ret
        moveq   #1,d0
.tc_lp:
        cmp.b   #',',(a0)+
        bne     .tc_next
        addq.l  #1,d0
.tc_next:
        subq.l  #1,d5
        bne     .tc_lp
.tc_ret:
        movem.l (sp)+,d1/d5/a0
        rts

; 78 rdargs(tpl, argv, n) -> BPTR of the first free long of argv (success) | 0 (Result2 = 120). Spec §5.4:
; argv!i = 0 absent, -1 /S switch present, otherwise BPTR of a BSTR stored in the free area of argv (after the keys).
; During parsing, argv!i (0..7) = flags of the key = "not filled".
g_rdargs:
        BENTER
        move.l  d1,d5                ; d5 = template
        move.l  d2,d6
        lsl.l   #2,d6
        move.l  d6,a3                ; a3 = argv (address)
        move.l  d3,d7                ; d7 = size of argv in longs
        bsr     rt_tplcount
        move.l  d0,d4                ; d4 = number of keys
        cmp.l   d7,d4
        bgt     .ra_err
        moveq   #0,d2
.ra_init:
        cmp.l   d4,d2
        bhs     .ra_initd
        move.l  d5,d1
        bsr     rt_tplflags
        move.l  d2,d1
        lsl.l   #2,d1
        move.l  d0,0(a3,d1.l)
        addq.l  #1,d2
        bra     .ra_init
.ra_initd:
        move.l  d4,d0
        lsl.l   #2,d0
        lea     0(a3,d0.l),a2        ; a2 = free area (a2 restored by BLEAVE)
        sub.l   d4,d7                ; d7 = free longs
.ra_item:
        subq.l  #1,d7
        bmi     .ra_err
        addq.l  #1,d7
        move.l  a2,d1
        lsr.l   #2,d1
        move.l  d7,d2
        subq.l  #1,d2
        bsr     rt_rditem
        tst.l   d0
        beq     .ra_done
        cmp.l   #-2,d0
        beq     .ra_item             ; isolated "=": ignored
        tst.l   d0
        bmi     .ra_err
        cmp.l   #2,d0
        beq     .ra_positional       ; quoted item: never a keyword
        cmp.w   #$013F,(a2)          ; "?" followed by LF: displays the template and re-reads a line
        bne     .ra_kw
        bsr     rt_rdch
        cmp.l   #10,d0
        beq     .ra_help
        bsr     rt_unrdch
.ra_kw:
        move.l  d5,d1
        move.l  a2,d2
        lsr.l   #2,d2
        bsr     rt_findarg
        tst.l   d0
        bmi     .ra_positional
        move.l  d0,d3                ; d3 = key
        lsl.l   #2,d3
        move.l  0(a3,d3.l),d0
        btst    #2,d0
        beq     .ra_keyval
        cmp.l   #7,d0
        bhi     .ra_keyval
        moveq   #-1,d0               ; /S switch
        move.l  d0,0(a3,d3.l)
        bra     .ra_item
.ra_keyval:                          ; keyword: the value is the next item (possibly after "=")
        move.l  a2,d1
        lsr.l   #2,d1
        move.l  d7,d2
        subq.l  #1,d2
        bsr     rt_rditem
        cmp.l   #-2,d0
        bne     .ra_kv2
        bsr     rt_rditem
.ra_kv2:
        tst.l   d0
        ble     .ra_err
        bsr     .ra_take             ; d0 = BPTR of the item, free area advanced
        move.l  d0,0(a3,d3.l)
        bra     .ra_item
.ra_positional:                      ; first unfilled key that is neither /K nor /S
        moveq   #0,d3
.ra_pfind:
        cmp.l   d4,d3
        bhs     .ra_err
        move.l  d3,d1
        lsl.l   #2,d1
        move.l  0(a3,d1.l),d0
        cmp.l   #7,d0
        bhi     .ra_pnext
        and.l   #6,d0
        bne     .ra_pnext
        bsr     .ra_take
        move.l  d0,0(a3,d1.l)
        bra     .ra_item
.ra_pnext:
        addq.l  #1,d3
        bra     .ra_pfind
.ra_help:
        lea     -256(sp),sp          ; "<template>: "
        move.l  sp,a0
        move.l  d5,d1
        bsr     rt_cstr
        move.l  sp,a0
        moveq   #-1,d0
.ra_hlen:
        addq.l  #1,d0
        tst.b   (a0)+
        bne     .ra_hlen
        move.l  sp,a0
        bsr     rt_write
        lea     ra_colon(pc),a0
        moveq   #2,d0
        bsr     rt_write
        lea     256(sp),sp
        bra     .ra_item
.ra_take:                            ; -> d0 = BPTR of the item at a2; advances a2/d7 by its size. Clobbers d2.
        move.l  a2,d0
        lsr.l   #2,d0
        moveq   #0,d2
        move.b  (a2),d2
        addq.l  #4,d2
        lsr.l   #2,d2                ; longs used = (length + 1 + 3) / 4
        sub.l   d2,d7
        lsl.l   #2,d2
        add.l   d2,a2
        rts
.ra_done:
        moveq   #0,d3                ; unfilled keys: /A -> error, otherwise 0 (absent)
.ra_chk:
        cmp.l   d4,d3
        bhs     .ra_ok
        move.l  d3,d1
        lsl.l   #2,d1
        move.l  0(a3,d1.l),d0
        cmp.l   #7,d0
        bhi     .ra_cnext
        btst    #0,d0
        bne     .ra_err
        clr.l   0(a3,d1.l)
.ra_cnext:
        addq.l  #1,d3
        bra     .ra_chk
.ra_ok:
        bsr     rt_rdch              ; consume the terminator (LF or ;)
        move.l  a2,d1
        lsr.l   #2,d1
        BLEAVE
.ra_err:
.ra_eskip:                           ; skip the rest of the line
        bsr     rt_rdch
        cmp.l   #10,d0
        beq     .ra_efin
        cmp.l   #';',d0
        beq     .ra_efin
        tst.l   d0
        bpl     .ra_eskip
.ra_efin:
        moveq   #ERR_BADTEMPLATE,d0
        bsr     rt_setr2
        moveq   #0,d1
        BLEAVE

; 13 makeglobvec(segarray) -> BPTR of slot 0 of a new GV | 0 (Result2 = 103).
g_makeglobvec:
        BENTER
        move.l  ($4).w,a6
        bsr     rt_makeglobvec
        move.l  d0,d1
        BLEAVE

; 112 starthandler(node, name): node = BPTR of the DeviceNode, name = full BSTR -> MsgPort | 0; Result2 = dn_Lock.
g_starthandler:
        BENTER
        lea     -256(sp),sp
        move.l  d1,d5                ; node
        move.l  d2,d1
        move.l  sp,a0
        bsr     rt_cstr
        lsl.l   #2,d5
        move.l  d5,a2
        bsr     bcpl_starthandler
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE

; 89 findsegarray() -> pr_SegList (BPTR of the segarray)
g_findsegarray:
        bsr     rt_this
        move.l  PR_SEGLIST(a3),d1
        jmp     (a6)

; 102 deviceproc(name) -> MsgPort of the handler | 0 (Result2 = 218); Result2 = associated lock (assign) otherwise 0.
g_deviceproc:
        BENTER
        lea     -256(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,a4                ; a4 = C name (dos_resolve)
        move.l  DOS_DOSBASE,a6
        bsr     rt_this
        move.l  a3,a5                ; a5 = process (survives dos_resolve)
        jsr     dos_resolve          ; a3 = port | 0, d6 = lock
        move.l  a3,d1
        beq     .dp_ret              ; dos_resolve has set Result2 = 218
        move.l  d6,PR_RESULT2(a5)
.dp_ret:
        lea     256(sp),sp
        BLEAVE

; 104 fault(code) (spec fault-v34 §2): code != 0 -> the error text is written by C:FAULT (rt_fault).
g_fault:
        BENTER
        move.l  d1,d0
        bsr     rt_fault
        BLEAVE

; rt_fault(d0 = code): nothing for 0. Otherwise C:FAULT is loaded without a requester (pr_WindowPtr = -1 during the
; load, no Resident list), pr_Result2 := code AFTER the load (C:Fault reads the code there and then writes only
; the text and a newline), launched by runcommand on 400 longs without arguments (caller's outputs), then
; unloaded. Not found, or runcommand returns -1: "Error code <n>" and a newline. pr_Result2 = code on return.
; Preserves everything.
FT_STACK        EQU 400
rt_fault:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  d0,d7                ; d7 = code
        beq     .rf_ret
        bsr     rt_this
        move.l  PR_WINDOWPTR(a3),d6
        moveq   #-1,d0
        move.l  d0,PR_WINDOWPTR(a3)
        move.l  #ft_cfault,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  d0,d5                ; d5 = seglist | 0
        bsr     rt_this
        move.l  d6,PR_WINDOWPTR(a3)
        move.l  d7,PR_RESULT2(a3)
        tst.l   d5
        beq.s   .rf_fallback
        move.l  PR_GLOBVEC(a3),d0
        beq.s   .rf_unload           ; without a global vector: no BCPL command possible
        move.l  d0,a2
        movem.l d5/d7,-(sp)          ; runcommand uses d5-d7
        lea     -EX_FRAME(sp),sp
        move.l  sp,a1                ; BCPL frame of the caller built on the stack
        move.l  d5,d1
        move.l  #FT_STACK,d2
        moveq   #0,d3
        moveq   #0,d4
        lea     .rf_back(pc),a6      ; runcommand's BLEAVE returns through jmp (a6)
        bra     g_runcommand
.rf_back:
        lea     EX_FRAME(sp),sp
        move.l  d1,d6                ; d6 = return code (-1: not launched)
        movem.l (sp)+,d5/d7
        move.l  d5,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
        cmp.l   #-1,d6
        bne.s   .rf_ret
        bra.s   .rf_fallback
.rf_unload:
        move.l  d5,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
.rf_fallback:
        WFRAW
        lea     ft_msg(pc),a0
.rf_lp:
        move.b  (a0)+,d0
        beq     .rf_num
        bsr     wf_putc
        bra     .rf_lp
.rf_num:
        move.l  d7,d1
        moveq   #0,d2
        moveq   #10,d3
        moveq   #0,d4
        bsr     wf_num
        moveq   #10,d0
        bsr     wf_putc
        WFCLOSE
        bsr     rt_this
        move.l  d7,PR_RESULT2(a3)
.rf_ret:
        movem.l (sp)+,d0-d7/a0-a6
        rts

; 108 locateobj(name) / 123 lock(name, mode) -> shared lock | 0; 109 freeobj(lock).
g_locateobj:
g_lock:
        BENTER
        lea     -256(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        moveq   #SHARED_LOCK,d2
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE
g_freeobj:
        BENTER
        bsr     rt_this
        move.l  PR_RESULT2(a3),d7    ; Result2 preserved
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOCK(a6)
        move.l  d7,d0
        bsr     rt_setr2
        BLEAVE

; 110 getlong(i, base) / 111 putlong(i, base, v): long at INDEX i (in longs) from the machine address base,
; i.e. base + 4*i. Observed in c:Run: getlong(11, taskid) = pr_GlobVec (MsgPort $5C + 44 = $88), getlong(20,
; taskid) = pr_CLI, putlong(12, taskid, slot) = pr_TaskNum. (The analysis spec §8.1 had base/index swapped: fixed.)
g_getlong:
        move.l  d2,a3
        lsl.l   #2,d1
        move.l  0(a3,d1.l),d1
        jmp     (a6)
g_putlong:
        move.l  d2,a3
        lsl.l   #2,d1
        move.l  d3,0(a3,d1.l)
        jmp     (a6)

; 115 copystring(src, dst): copies the BSTR src (length + 1 bytes) into dst.
g_copystring:
        lsl.l   #2,d1
        move.l  d1,a3
        lsl.l   #2,d2
        move.l  d2,a4                ; (a4 reloaded by bcpl_ret)
        moveq   #0,d0
        move.b  (a3),d0
.cy_lp:
        move.b  (a3)+,(a4)+
        dbra    d0,.cy_lp
        jmp     (a6)

; 134 findcli() -> pr_CLI (BPTR)
g_findcli:
        bsr     rt_this
        move.l  PR_CLI(a3),d1
        jmp     (a6)

; consoletask() (105) / filesystemtask() (106) -> pr_ConsoleTask / pr_FileSystemTask of the process (handler ports)
g_consoletask:
        bsr     rt_this
        move.l  PR_CONSOLETASK(a3),d1
        jmp     (a6)
g_filesystemtask:
        bsr     rt_this
        move.l  PR_FILESYSTEMTASK(a3),d1
        jmp     (a6)

ft_msg:
        dc.b    "Error code ",0
ft_cfault:
        dc.b    "C:FAULT",0
ra_colon:
        dc.b    ": "
        EVEN

; --- runtime segment in BCPL format (spec §3.1): [link][N][0][pairs (global, offset)]...[max] ---
GLOB            MACRO
        dc.l    \1,\2-bcpl_rtdata
                ENDM
        cnop    0,4
bcpl_rtseg:
        dc.l    0                    ; link: single segment
bcpl_rtdata:
        dc.l    (bcpl_rtend-bcpl_rtdata)/4
        dc.l    0                    ; terminator of the table
        GLOB    -26,g_isinteractive
        GLOB    -20,g_clearvec
        GLOB    -8,g_cseek
        GLOB    -6,g_cwrite
        GLOB    -3,g_cread
        GLOB    -2,g_copyvec
        GLOB    -1,g_copen
        GLOB    2,g_stop
        GLOB    3,g_mult
        GLOB    4,g_div
        GLOB    5,g_rem
        GLOB    6,g_setio
        GLOB    10,g_result2
        GLOB    13,g_makeglobvec
        GLOB    14,g_taskid
        GLOB    17,g_level
        GLOB    18,g_longjump
        GLOB    19,g_getmem
        GLOB    21,g_doio
        GLOB    22,g_sendio
        GLOB    28,g_globin
        GLOB    29,g_getvec
        GLOB    30,g_freevec
        GLOB    31,g_opendevice
        GLOB    32,g_closedevice
        GLOB    33,g_createproc
        GLOB    34,g_endtask
        GLOB    35,g_parentdir
        GLOB    36,g_setflags
        GLOB    37,g_testflags
        GLOB    39,g_rootstruct
        GLOB    40,g_readbytes
        GLOB    41,g_taskwait
        GLOB    42,g_qpkt
        GLOB    43,g_writebytes
        GLOB    47,g_delay
        GLOB    48,g_sendpkt
        GLOB    49,g_returnpkt
        GLOB    50,g_openwindow
        GLOB    51,g_currentdir
        GLOB    53,g_writet
        GLOB    54,g_rdch
        GLOB    55,g_unrdch
        GLOB    56,g_wrch
        GLOB    59,g_findinput
        GLOB    60,g_findoutput
        GLOB    61,g_selectinput
        GLOB    62,g_selectoutput
        GLOB    63,g_endread
        GLOB    64,g_endwrite
        GLOB    65,g_input
        GLOB    66,g_output
        GLOB    68,g_newline
        GLOB    69,g_writed
        GLOB    70,g_writen
        GLOB    71,g_writehex
        GLOB    72,g_writeoct
        GLOB    73,g_writes
        GLOB    74,g_writef
        GLOB    75,g_capitalch
        GLOB    76,g_compch
        GLOB    77,g_compstring
        GLOB    78,g_rdargs
        GLOB    79,g_rditem
        GLOB    80,g_findarg
        GLOB    81,g_load
        GLOB    82,g_unloadseg
        GLOB    85,g_makedevnode
        GLOB    86,g_datstamp
        GLOB    88,g_callexec
        GLOB    89,g_findsegarray
        GLOB    90,g_deleteobj
        GLOB    91,g_rename
        GLOB    93,g_endstream
        GLOB    102,g_deviceproc
        GLOB    103,g_calllib
        GLOB    104,g_fault
        GLOB    105,g_consoletask
        GLOB    106,g_filesystemtask
        GLOB    107,g_splitname
        GLOB    108,g_locateobj
        GLOB    109,g_freeobj
        GLOB    110,g_getlong
        GLOB    111,g_putlong
        GLOB    112,g_starthandler
        GLOB    113,g_copydir
        GLOB    114,g_errorreq
        GLOB    115,g_copystring
        GLOB    121,g_runcommand
        GLOB    123,g_lock
        GLOB    124,g_finddevinfo
        GLOB    125,g_createdir
        GLOB    126,g_compstamp
        GLOB    128,g_setdatstamp
        GLOB    134,g_findcli
        dc.l    134                  ; highest global of the segment
bcpl_rtend:

; --- diagnostic stubs (CLI GV): one per slot (-50..150). Stub i does bsr.w bcpl_unimpl: the return
; address gives the offset of the called slot, emitted on serial ("BCPL GLOBAL xxxx NON IMPL"), then BCPL return d1 = 0.
; (A command's PRIVATE GV does not see them: its stub fills the undefined slots with $474C0001+2n.)
BCPL_STUB       MACRO
        bsr.w   bcpl_unimpl          ; FIXED size (bsr.w): the stubs must be identical
                ENDM
bcpl_stubs:
        BCPL_STUB
bcpl_stub1:
BCPL_STUBSZ     EQU bcpl_stub1-bcpl_stubs   ; 4 = size of a slot: the offset computation of bcpl_unimpl depends on it
                rept    (GV_SIZE/4)-1
        BCPL_STUB
                endr
bcpl_unimpl:
        movem.l d0/a0,-(sp)
        move.l  8(sp),d0             ; return = stub + BCPL_STUBSZ
        sub.l   #bcpl_stubs+BCPL_STUBSZ,d0   ; = index * 4
        sub.l   #GV_NEG,d0           ; -> offset of the slot in the GV
        lea     bcpl_msg_unimpl(pc),a0
        jsr     ser_puts
        jsr     ser_puthex
        lea     bcpl_msg_crlf(pc),a0
        jsr     ser_puts
        movem.l (sp)+,d0/a0
        addq.l  #4,sp                ; remove the stub's return address
        moveq   #0,d1
        jmp     (a6)
bcpl_intuiname:
        dc.b    "intuition.library",0
        EVEN
bcpl_msg_unimpl:
        dc.b    "BCPL GLOBAL ",0
bcpl_msg_crlf:
        dc.b    " NON IMPL",13,10,0
        EVEN
