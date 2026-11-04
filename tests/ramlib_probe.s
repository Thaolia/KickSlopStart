; tests/ramlib_probe.s - disk loading of libraries/devices and the low-memory expunge (implementation-side probe of
; docs/analysis/ramlib-v34.md §8.1; expected 1.3 values in §8). Public ABI only: exec/dos .fd (LVOs checked against
; AROS exec.conf/dos.conf), exec/libraries.h, exec/io.h, dos/dosextens.h.
; Run from a startup-sequence (no SetPatch) on a copy of the Workbench 1.3.3 disk, by tests/ramlib_probe.sh.
; One line per step, "RL <step> name=value...", values in hex, written through Write(Output()) AND on the serial
; port registers (busy-wait on TBE), then "RL DONE".
; dos LoadSeg (-150) is wrapped with SetFunction for the run so that each step also reports, on an "RL <step> LS"
; line, how many LoadSeg calls went through the dos vector and the name passed to the last one.
; Steps: VEC (information), T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, CONC. The TASK step of §8.1 is not done.
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -o ramlib_probe tests/ramlib_probe.s

SERDAT          EQU $DFF030
SERDATR         EQU $DFF018
CIAA_TODHI      EQU $BFEA01
CIAA_TODMID     EQU $BFE901
CIAA_TODLO      EQU $BFE801

_Forbid         EQU -132
_Permit         EQU -138
_AllocMem       EQU -198
_FreeMem        EQU -210
_FindName       EQU -276
_FindTask       EQU -294
_CloseLibrary   EQU -414
_SetFunction    EQU -420
_OpenDevice     EQU -444
_OpenLibrary    EQU -552

_Write          EQU -48
_Output         EQU -60
_IoErr          EQU -132
_CreateProc     EQU -138
_LoadSeg        EQU -150
_Delay          EQU -198

EB_DEVICELIST   EQU 350
EB_LIBLIST      EQU 378
LN_NAME         EQU 10
LIB_VERSION     EQU 20
LIB_REVISION    EQU 22
LIB_OPENCNT     EQU 32
PR_RESULT2      EQU 148
IO_DEVICE       EQU 20
IO_ERROR        EQU 31
IOSIZE          EQU 48
RAMLIB_POSSIZE  EQU 178
BIGMEM          EQU $7FFFF0

start:
        move.l  4.w,a6
        lea     n_dos(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,dosb
        beq     quit
        move.l  d0,a6
        jsr     _Output(a6)
        move.l  d0,outfh
        move.l  4.w,a6
        move.l  dosb,a1
        move.w  #_LoadSeg,a0
        move.l  #ls_stub,d0
        jsr     _SetFunction(a6)
        move.l  d0,ls_old

; --- VEC (information): where the seven exec vectors ramlib patches on 1.3 point --------------------------------------
        lea     n_ramlib(pc),a1
        bsr     findlib
        move.l  d0,d5                   ; d5 = ramlib base | 0
        lea     m_vec(pc),a0
        bsr     pstr
        lea     m_rlb(pc),a0
        bsr     pv
        lea     veclvo(pc),a2
        moveq   #6,d3
.vec:
        move.w  (a2)+,d0
        move.l  2(a6,d0.w),d4           ; JMP target of the vector
        lea     m_sp(pc),a0
        move.l  d4,d0
        bsr     pv
        moveq   #0,d0
        tst.l   d5
        beq.s   .vout
        cmp.l   d5,d4
        blo.s   .vout
        move.l  d5,d1
        add.l   #RAMLIB_POSSIZE,d1
        cmp.l   d1,d4
        bhs.s   .vout
        moveq   #1,d0
.vout:
        lea     m_in(pc),a0
        bsr     pvb
        dbra    d3,.vec
        bsr     pnl
        lea     m_vec2(pc),a0
        bsr     pstr
        moveq   #0,d0
        moveq   #0,d1
        tst.l   d5
        beq.s   .vnor
        move.l  d5,a0
        move.w  LIB_OPENCNT(a0),d0
        move.l  LIB_VERSION(a0),d1      ; version.revision
.vnor:
        lea     m_cnt(pc),a0
        bsr     pv
        move.l  d1,d0
        lea     m_verrev(pc),a0
        bsr     pv
        bsr     pnl

; --- T1: OpenLibrary("diskfont.library", 0) loads it --------------------------------------------------------------
        bsr     lsclear
        bsr     doscnt
        move.l  d0,dosc0
        sub.l   a1,a1
        jsr     _FindTask(a6)
        move.l  d0,d6
        lea     n_df(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,dfbase
        sub.l   a1,a1
        jsr     _FindTask(a6)
        move.l  d0,d7
        lea     m_t1(pc),a0
        bsr     pstr
        move.l  dfbase,d0
        lea     m_base(pc),a0
        bsr     pv
        bsr     dfver
        lea     m_ver(pc),a0
        bsr     pv
        lea     n_df(pc),a1
        bsr     findlib
        cmp.l   dfbase,d0
        seq     d0
        lea     m_listed(pc),a0
        bsr     pvb
        cmp.l   d6,d7
        seq     d0
        lea     m_sametask(pc),a0
        bsr     pvb
        move.l  dosc0,d0
        lea     m_dosc0(pc),a0
        bsr     pv
        bsr     doscnt
        lea     m_dosc1(pc),a0
        bsr     pv
        bsr     dfcnt
        lea     m_cnt(pc),a0
        bsr     pv
        bsr     pnl
        lea     m_t1(pc),a0
        bsr     pls

; --- T2: same again, no load ----------------------------------------------------------------------------------------
        lea     n_df(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,dfbase2
        lea     m_t2(pc),a0
        bsr     pstr
        lea     m_base(pc),a0
        bsr     pv
        cmp.l   dfbase,d0
        seq     d0
        lea     m_same(pc),a0
        bsr     pvb
        bsr     pnl
        lea     m_t2(pc),a0
        bsr     pls

; --- T3: CloseLibrary x2, diskfont stays listed ----------------------------------------------------------------------
        moveq   #-1,d6
        moveq   #-1,d7
        move.l  dfbase2,d0
        beq.s   .t3a
        move.l  d0,a1
        jsr     _CloseLibrary(a6)
        move.l  d0,d6
.t3a:
        move.l  dfbase,d0
        beq.s   .t3b
        move.l  d0,a1
        jsr     _CloseLibrary(a6)
        move.l  d0,d7
.t3b:
        lea     m_t3(pc),a0
        bsr     pstr
        move.l  d6,d0
        lea     m_d0a(pc),a0
        bsr     pv
        move.l  d7,d0
        lea     m_d0b(pc),a0
        bsr     pv
        lea     n_df(pc),a1
        bsr     findlib
        sne     d0
        lea     m_listed(pc),a0
        bsr     pvb
        bsr     dfcnt
        lea     m_cnt(pc),a0
        bsr     pv
        bsr     pnl

; --- T4: version 99 of a library in memory: failure, no disk access, IoErr untouched ---------------------------------
        bsr     lsclear
        move.l  #$5A5A5A5A,d0
        bsr     setres2
        bsr     gettod
        move.l  d0,d6
        lea     n_df(pc),a1
        moveq   #99,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,d4
        bsr     gettod
        move.l  d0,d7
        bsr     ioerr
        move.l  d0,d5
        move.l  d4,d0
        beq.s   .t4c
        move.l  d0,a1
        jsr     _CloseLibrary(a6)
.t4c:
        lea     m_t4(pc),a0
        bsr     pstr
        move.l  d4,d0
        lea     m_res(pc),a0
        bsr     pv
        move.l  d5,d0
        lea     m_ioerr(pc),a0
        bsr     pv
        move.l  d7,d0
        sub.l   d6,d0
        lea     m_frames(pc),a0
        bsr     pv
        bsr     pnl
        lea     m_t4(pc),a0
        bsr     pls

; --- T5: AllocMem failure expunges every unopened library and device -------------------------------------------------
        moveq   #0,d0
        bsr     setres2
        move.l  #BIGMEM,d0
        moveq   #0,d1
        jsr     _AllocMem(a6)
        move.l  d0,d4
        bsr     ioerr
        move.l  d0,d5
        bsr     bigfree
        lea     m_t5(pc),a0
        bsr     pstr
        move.l  d4,d0
        lea     m_res(pc),a0
        bsr     pv
        move.l  d5,d0
        lea     m_ioerr(pc),a0
        bsr     pv
        lea     n_df(pc),a1
        bsr     findlib
        sne     d0
        lea     m_df(pc),a0
        bsr     pvb
        lea     n_ramlib(pc),a1
        bsr     findlib
        sne     d0
        lea     m_ramlib(pc),a0
        bsr     pvb
        move.l  dosc0,d0
        lea     m_dosc0(pc),a0
        bsr     pv
        bsr     doscnt
        lea     m_dosc1(pc),a0
        bsr     pv
        bsr     pnl
        lea     m_t5i(pc),a0            ; information: ROM modules with no opener
        bsr     pstr
        lea     n_mathffp(pc),a1
        bsr     findlib
        sne     d0
        lea     m_mathffp(pc),a0
        bsr     pvb
        lea     n_audio(pc),a1
        bsr     finddev
        sne     d0
        lea     m_audio(pc),a0
        bsr     pvb
        bsr     pnl

; --- T6: version 99 of a library not in memory: loaded, left in the list, open fails --------------------------------
        bsr     lsclear
        moveq   #0,d0
        bsr     setres2
        lea     n_df(pc),a1
        moveq   #99,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,d4
        bsr     ioerr
        move.l  d0,d5
        move.l  d4,d0
        beq.s   .t6c
        move.l  d0,a1
        jsr     _CloseLibrary(a6)
.t6c:
        lea     n_df(pc),a1
        bsr     findlib
        move.l  d0,dfbase
        lea     m_t6(pc),a0
        bsr     pstr
        move.l  d4,d0
        lea     m_res(pc),a0
        bsr     pv
        move.l  d5,d0
        lea     m_ioerr(pc),a0
        bsr     pv
        move.l  dfbase,d0
        sne     d0
        lea     m_listed(pc),a0
        bsr     pvb
        bsr     dfver
        lea     m_ver(pc),a0
        bsr     pv
        bsr     dfcnt
        lea     m_cnt(pc),a0
        bsr     pv
        bsr     pnl
        lea     m_t6(pc),a0
        bsr     pls

; --- T7: expunge again, then OpenLibrary("LIBS:diskfont.library", 0) -------------------------------------------------
        moveq   #0,d0
        bsr     setres2
        move.l  #BIGMEM,d0
        moveq   #0,d1
        jsr     _AllocMem(a6)
        move.l  d0,d4
        bsr     ioerr
        move.l  d0,d5
        bsr     bigfree
        lea     n_df(pc),a1
        bsr     findlib
        move.l  d0,d6                   ; d6 = diskfont node after the expunge (0 expected)
        bsr     lsclear
        lea     n_libsdf(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,dfbase
        lea     m_t7(pc),a0
        bsr     pstr
        move.l  d4,d0
        lea     m_alloc(pc),a0
        bsr     pv
        move.l  d5,d0
        lea     m_ioerr(pc),a0
        bsr     pv
        tst.l   d6
        sne     d0
        lea     m_df(pc),a0
        bsr     pvb
        move.l  dfbase,d0
        lea     m_base(pc),a0
        bsr     pv
        move.l  dfbase,a1
        lea     n_df(pc),a0
        bsr     nameis
        lea     m_nameok(pc),a0
        bsr     pvb
        lea     n_df(pc),a1
        bsr     findlib
        cmp.l   dfbase,d0
        seq     d0
        lea     m_listed(pc),a0
        bsr     pvb
        bsr     pnl
        lea     m_t7(pc),a0
        bsr     pls
        move.l  dfbase,d0
        beq.s   .t7c
        move.l  d0,a1
        jsr     _CloseLibrary(a6)
.t7c:

; --- T8: OpenLibrary("SYS:libs/icon.library", 0) -------------------------------------------------------------------
        bsr     lsclear
        lea     n_sysicon(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,iconbase
        lea     m_t8(pc),a0
        bsr     pstr
        lea     m_base(pc),a0
        bsr     pv
        move.l  iconbase,a1
        lea     n_icon(pc),a0
        bsr     nameis
        lea     m_nameok(pc),a0
        bsr     pvb
        moveq   #0,d0
        moveq   #0,d1
        move.l  iconbase,d2
        beq.s   .t8n
        move.l  d2,a0
        move.l  LIB_VERSION(a0),d0
        move.w  LIB_OPENCNT(a0),d1
.t8n:
        lea     m_verrev(pc),a0
        bsr     pv
        move.l  d1,d0
        lea     m_cnt(pc),a0
        bsr     pv
        bsr     pnl
        lea     m_t8(pc),a0
        bsr     pls

; --- T9: OpenDevice("nosuch.device") ---------------------------------------------------------------------------------
        bsr     lsclear
        lea     ior,a0
        moveq   #IOSIZE/4-1,d0
.t9z:
        clr.l   (a0)+
        dbra    d0,.t9z
        moveq   #0,d0
        bsr     setres2
        lea     n_nodev(pc),a0
        lea     ior,a1
        moveq   #0,d0
        moveq   #0,d1
        jsr     _OpenDevice(a6)
        move.l  d0,d4
        bsr     ioerr
        move.l  d0,d5
        lea     m_t9(pc),a0
        bsr     pstr
        move.l  d4,d0
        lea     m_d0(pc),a0
        bsr     pv
        lea     ior,a1
        moveq   #0,d0
        move.b  IO_ERROR(a1),d0
        lea     m_ioerror(pc),a0
        bsr     pv
        move.l  IO_DEVICE(a1),d0
        lea     m_iodev(pc),a0
        bsr     pv
        move.l  d5,d0
        lea     m_ioerr(pc),a0
        bsr     pv
        bsr     pnl
        lea     m_t9(pc),a0
        bsr     pls

; --- T10: OpenLibrary("nosuch.library", 0) --------------------------------------------------------------------------
        bsr     lsclear
        moveq   #0,d0
        bsr     setres2
        lea     n_nolib(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,d4
        bsr     ioerr
        move.l  d0,d5
        lea     m_t10(pc),a0
        bsr     pstr
        move.l  d4,d0
        lea     m_res(pc),a0
        bsr     pv
        move.l  d5,d0
        lea     m_ioerr(pc),a0
        bsr     pv
        bsr     pnl
        lea     m_t10(pc),a0
        bsr     pls

; --- CONC: two processes open info.library at the same time ---------------------------------------------------------
        bsr     lsclear
        lea     n_info(pc),a1
        bsr     findlib
        move.l  d0,d6                   ; d6 = info.library already in memory (0 expected)
        jsr     _Forbid(a6)
        move.l  dosb,a6
        move.l  #n_ch1,d1
        moveq   #0,d2
        move.l  #seg1,d3
        lsr.l   #2,d3
        move.l  #8192,d4
        jsr     _CreateProc(a6)
        move.l  d0,d7
        move.l  #n_ch2,d1
        moveq   #0,d2
        move.l  #seg2,d3
        lsr.l   #2,d3
        move.l  #8192,d4
        jsr     _CreateProc(a6)
        tst.l   d0
        bne.s   .cpok
        moveq   #0,d7                   ; d7 = 0 if a CreateProc failed
.cpok:
        move.l  4.w,a6
        jsr     _Permit(a6)
        move.w  #300,d5                 ; wait up to 30 s for both children
.cw:
        tst.l   cdone
        beq.s   .cw1
        tst.l   cdone+4
        bne.s   .cwok
.cw1:
        move.l  dosb,a6
        moveq   #5,d1
        jsr     _Delay(a6)
        move.l  4.w,a6
        subq.w  #1,d5
        bne.s   .cw
.cwok:
        lea     m_conc(pc),a0
        bsr     pstr
        tst.l   d6
        sne     d0
        lea     m_pre(pc),a0
        bsr     pvb
        tst.l   d7
        sne     d0
        lea     m_procs(pc),a0
        bsr     pvb
        move.l  cdone,d0
        lea     m_done1(pc),a0
        bsr     pv
        move.l  cdone+4,d0
        lea     m_done2(pc),a0
        bsr     pv
        move.l  cbase,d0
        lea     m_base1(pc),a0
        bsr     pv
        move.l  cbase+4,d0
        lea     m_base2(pc),a0
        bsr     pv
        move.l  cbase,d0
        cmp.l   cbase+4,d0
        seq     d0
        lea     m_same(pc),a0
        bsr     pvb
        lea     n_info(pc),a1
        bsr     countlib
        lea     m_nodes(pc),a0
        bsr     pv
        bsr     pnl
        lea     m_conc(pc),a0
        bsr     pls
        move.l  dosb,a6                 ; let the children end before their code goes away
        moveq   #50,d1
        jsr     _Delay(a6)
        move.l  4.w,a6
        lea     cbase,a2
        moveq   #1,d3
.ccl:
        move.l  (a2)+,d0
        beq.s   .ccn
        move.l  d0,a1
        jsr     _CloseLibrary(a6)
.ccn:
        dbra    d3,.ccl

; --- end ------------------------------------------------------------------------------------------------------------
        move.l  iconbase,d0
        beq.s   .noicon
        move.l  d0,a1
        jsr     _CloseLibrary(a6)
.noicon:
        move.l  dosb,a1
        move.w  #_LoadSeg,a0
        move.l  ls_old,d0
        jsr     _SetFunction(a6)
        lea     m_done(pc),a0
        bsr     pstr
        bsr     pnl
        move.l  dosb,a1
        jsr     _CloseLibrary(a6)
quit:
        moveq   #0,d0
        rts

; ---------------------------------------------------------------------------------------------------------------------
; Children of CONC (started by CreateProc on the fake one-hunk seglists below).
child1: moveq   #0,d7
        bra.s   child
child2: moveq   #4,d7
child:  move.l  4.w,a6
        lea     n_info(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        lea     cbase,a0
        move.l  d0,0(a0,d7.w)
        lea     cdone,a0
        move.l  #1,0(a0,d7.w)
        moveq   #0,d0
        rts

; LoadSeg wrapper: counts the calls and keeps the name of the last one (d1), then goes on to the previous function.
ls_stub:
        addq.l  #1,ls_cnt
        movem.l d0/a0-a1,-(sp)
        move.l  d1,a0
        lea     ls_name,a1
        moveq   #39,d0
.lc:    move.b  (a0)+,(a1)+
        dbeq    d0,.lc
        clr.b   (a1)
        movem.l (sp)+,d0/a0-a1
        move.l  ls_old,-(sp)
        rts

; ---------------------------------------------------------------------------------------------------------------------
; Helpers. All preserve every register except d0 when they return a value. a6 = ExecBase on entry and exit.

; findlib / finddev (a1 = name) -> d0 = node | 0
findlib:
        movem.l d1-d2/a0-a1,-(sp)
        lea     EB_LIBLIST(a6),a0
        bra.s   findn
finddev:
        movem.l d1-d2/a0-a1,-(sp)
        lea     EB_DEVICELIST(a6),a0
findn:
        jsr     _Forbid(a6)
        jsr     _FindName(a6)
        move.l  d0,d2                   ; d2: exec calls may change d0/d1/a0/a1
        jsr     _Permit(a6)
        move.l  d2,d0
        movem.l (sp)+,d1-d2/a0-a1
        tst.l   d0
        rts

; countlib (a1 = name) -> d0 = number of LibList nodes of that name
countlib:
        movem.l d1-d2/a0-a2,-(sp)
        move.l  a1,a2
        moveq   #0,d2
        jsr     _Forbid(a6)
        lea     EB_LIBLIST(a6),a0
.cl:
        move.l  a2,a1
        jsr     _FindName(a6)
        tst.l   d0
        beq.s   .cle
        addq.l  #1,d2
        move.l  d0,a0
        bra.s   .cl
.cle:
        jsr     _Permit(a6)
        move.l  d2,d0
        movem.l (sp)+,d1-d2/a0-a2
        rts

; nameis (a1 = node | 0, a0 = expected name) -> d0.b = $FF if ln_Name equals it
nameis:
        movem.l a0-a2,-(sp)
        moveq   #0,d0
        move.l  a1,d1
        beq.s   .nr
        move.l  LN_NAME(a1),d1
        beq.s   .nr
        move.l  d1,a2
.nc:
        move.b  (a0)+,d1
        cmp.b   (a2)+,d1
        bne.s   .nr
        tst.b   d1
        bne.s   .nc
        moveq   #-1,d0
.nr:
        movem.l (sp)+,a0-a2
        rts

; doscnt -> d0 = lib_OpenCnt of dos.library
doscnt:
        move.l  a0,-(sp)
        move.l  dosb,a0
        moveq   #0,d0
        move.w  LIB_OPENCNT(a0),d0
        move.l  (sp)+,a0
        rts

; dfver / dfcnt -> d0 = version.revision / lib_OpenCnt of dfbase (0 if none)
dfver:
        moveq   #0,d0
        move.l  a0,-(sp)
        move.l  dfbase,a0
        cmp.w   #0,a0
        beq.s   .dv
        move.l  LIB_VERSION(a0),d0
.dv:    move.l  (sp)+,a0
        rts
dfcnt:
        moveq   #0,d0
        move.l  a0,-(sp)
        move.l  dfbase,a0
        cmp.w   #0,a0
        beq.s   .dc
        move.w  LIB_OPENCNT(a0),d0
.dc:    move.l  (sp)+,a0
        rts

; setres2 (d0) -> pr_Result2 of this process = d0
setres2:
        movem.l d0-d1/a0-a1,-(sp)
        sub.l   a1,a1
        jsr     _FindTask(a6)
        move.l  d0,a0
        move.l  (sp),PR_RESULT2(a0)
        movem.l (sp)+,d0-d1/a0-a1
        rts

; ioerr -> d0 = IoErr()
ioerr:
        movem.l d1/a0-a1/a6,-(sp)
        move.l  dosb,a6
        jsr     _IoErr(a6)
        movem.l (sp)+,d1/a0-a1/a6
        rts

; bigfree (d4 = AllocMem(BIGMEM) result) frees it if it ever succeeded
bigfree:
        movem.l d0-d1/a0-a1,-(sp)
        tst.l   d4
        beq.s   .bf
        move.l  d4,a1
        move.l  #BIGMEM,d0
        jsr     _FreeMem(a6)
.bf:    movem.l (sp)+,d0-d1/a0-a1
        rts

; gettod -> d0 = CIA-A TOD (frame counter); reading the high byte latches until the low byte is read
gettod:
        moveq   #0,d0
        move.b  CIAA_TODHI,d0
        lsl.l   #8,d0
        move.b  CIAA_TODMID,d0
        lsl.l   #8,d0
        move.b  CIAA_TODLO,d0
        rts

lsclear:
        clr.l   ls_cnt
        clr.b   ls_name
        rts

; pls (a0 = step prefix "RL Tn"): "RL Tn LS cnt=<n> name=<last LoadSeg name>", then the counter is cleared
pls:
        movem.l d0/a0,-(sp)
        bsr     pstr
        move.l  ls_cnt,d0
        lea     m_ls(pc),a0
        bsr     pv
        lea     m_name(pc),a0
        bsr     pstr
        lea     ls_name,a0
        bsr     pstr
        bsr     pnl
        bsr     lsclear
        movem.l (sp)+,d0/a0
        rts

; pvb (a0 = label, d0.b = 0 / non-zero): label then 0 or 1
pvb:
        movem.l d0/a0,-(sp)
        bsr     pstr
        move.l  lptr,a0
        tst.b   d0
        sne     d0
        and.b   #1,d0
        add.b   #'0',d0
        move.b  d0,(a0)+
        move.l  a0,lptr
        movem.l (sp)+,d0/a0
        rts

; pv (a0 = label, d0 = value): label then 8 hex digits
pv:
        movem.l d0-d2/a0,-(sp)
        bsr     pstr
        moveq   #7,d2
        move.l  lptr,a0
.hx:    rol.l   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        move.b  hexd(pc,d1.w),(a0)+
        dbra    d2,.hx
        move.l  a0,lptr
        movem.l (sp)+,d0-d2/a0
        rts
hexd:   dc.b    "0123456789ABCDEF"

; pstr (a0 = C string) appended to the line
pstr:
        movem.l a0-a1,-(sp)
        move.l  lptr,a1
.ps:    move.b  (a0)+,(a1)+
        bne.s   .ps
        subq.l  #1,a1
        move.l  a1,lptr
        movem.l (sp)+,a0-a1
        rts

; pnl: ends the line, writes it to Output() and to the serial port
pnl:
        movem.l d0-d3/a0-a1/a6,-(sp)
        move.l  lptr,a0
        move.b  #10,(a0)+
        lea     lbuf,a1
        move.l  a0,d3
        sub.l   a1,d3                   ; d3 = length
        move.l  d3,d0
        subq.w  #1,d0
.sp:    move.b  (a1)+,d1
.sw:    btst    #5,SERDATR
        beq.s   .sw
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        dbra    d0,.sp
        move.l  outfh,d1
        beq.s   .nout
        move.l  #lbuf,d2
        move.l  dosb,a6
        jsr     _Write(a6)
.nout:
        move.l  #lbuf,lptr
        movem.l (sp)+,d0-d3/a0-a1/a6
        rts

veclvo: dc.w    -198,-552,-444,-414,-450,-402,-438

n_dos:      dc.b    "dos.library",0
n_ramlib:   dc.b    "ramlib.library",0
n_df:       dc.b    "diskfont.library",0
n_libsdf:   dc.b    "LIBS:diskfont.library",0
n_sysicon:  dc.b    "SYS:libs/icon.library",0
n_icon:     dc.b    "icon.library",0
n_nodev:    dc.b    "nosuch.device",0
n_nolib:    dc.b    "nosuch.library",0
n_info:     dc.b    "info.library",0
n_mathffp:  dc.b    "mathffp.library",0
n_audio:    dc.b    "audio.device",0
n_ch1:      dc.b    "rlprobe1",0
n_ch2:      dc.b    "rlprobe2",0
m_vec:      dc.b    "RL VEC",0
m_vec2:     dc.b    "RL VEC ramlib",0
m_t1:       dc.b    "RL T1",0
m_t2:       dc.b    "RL T2",0
m_t3:       dc.b    "RL T3",0
m_t4:       dc.b    "RL T4",0
m_t5:       dc.b    "RL T5",0
m_t5i:      dc.b    "RL T5 info",0
m_t6:       dc.b    "RL T6",0
m_t7:       dc.b    "RL T7",0
m_t8:       dc.b    "RL T8",0
m_t9:       dc.b    "RL T9",0
m_t10:      dc.b    "RL T10",0
m_conc:     dc.b    "RL CONC",0
m_done:     dc.b    "RL DONE",0
m_rlb:      dc.b    " ramlib=",0
m_sp:       dc.b    " ",0
m_in:       dc.b    "/",0
m_cnt:      dc.b    " cnt=",0
m_verrev:   dc.b    " verrev=",0
m_base:     dc.b    " base=",0
m_ver:      dc.b    " verrev=",0
m_listed:   dc.b    " listed=",0
m_sametask: dc.b    " sametask=",0
m_dosc0:    dc.b    " doscnt0=",0
m_dosc1:    dc.b    " doscnt=",0
m_same:     dc.b    " same=",0
m_d0a:      dc.b    " close1=",0
m_d0b:      dc.b    " close2=",0
m_res:      dc.b    " res=",0
m_ioerr:    dc.b    " ioerr=",0
m_frames:   dc.b    " frames=",0
m_df:       dc.b    " diskfont=",0
m_ramlib:   dc.b    " ramliblisted=",0
m_mathffp:  dc.b    " mathffp=",0
m_audio:    dc.b    " audio=",0
m_alloc:    dc.b    " alloc=",0
m_nameok:   dc.b    " nameok=",0
m_d0:       dc.b    " d0=",0
m_ioerror:  dc.b    " io_Error=",0
m_iodev:    dc.b    " io_Device=",0
m_pre:      dc.b    " pre=",0
m_procs:    dc.b    " procs=",0
m_done1:    dc.b    " done1=",0
m_done2:    dc.b    " done2=",0
m_base1:    dc.b    " base1=",0
m_base2:    dc.b    " base2=",0
m_nodes:    dc.b    " nodes=",0
m_ls:       dc.b    " LS cnt=",0
m_name:     dc.b    " name=",0

        cnop    0,4
seg1:   dc.l    0                       ; fake seglists for CreateProc: link, then the code
        jmp     child1
seg2:   dc.l    0
        jmp     child2

dosb:       dc.l    0
outfh:      dc.l    0
ls_old:     dc.l    0
ls_cnt:     dc.l    0
dosc0:      dc.l    0
dfbase:     dc.l    0
dfbase2:    dc.l    0
iconbase:   dc.l    0
cbase:      dc.l    0,0
cdone:      dc.l    0,0
lptr:       dc.l    lbuf
ior:        ds.b    IOSIZE
ls_name:    ds.b    44
lbuf:       ds.b    320
