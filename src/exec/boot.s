; src/exec/boot.s — exec.library: ROM header, coldstart, ExecBase build,
; SysBase publication, self-check + self-test. "Glue" module of the
; coldstart (M2.3: extracted from the old monolithic coldstart.s).
; IMPLEMENTATION track ("clean"): written from docs/analysis/exec-spec.md +
; public ABI. NO reading of the ROM.
;
; Reset $FC00D2 -> supervisor + HW freeze (RED) -> overlay off + stack (BLUE)
; -> ExecBase + jump table (CYAN) -> publishes SysBase, self-check + self-test of the
; functions via the jump table -> WHITE if everything passes, MAGENTA otherwise.
;
; Colour -> phase (visual debugger): red=entered, blue=overlay off/stack,
; cyan=build ExecBase+table, white=SUCCESS, magenta=failure of a check.

                include "exec.i"
                include "dospkt.i"       ; D3: Process/packet constants for the proof scaffold
                include "dos.i"          ; D3c: DL_ROOT/RN_INFO/DI_DEVINFO (DeviceNode mount)
                include "expansion.i"    ; expansion.library: EXP_LVO_*/ConfigDev (round-trip proof)

                xref    newlist          ; lists.s
                xref    build_jumptable  ; library.s
                xref    init_memory      ; memory.s
                xref    add_slow_memory  ; memory.s (slow RAM $C00000 at the head of the MemList)
                xref    init_task        ; tasks.s
                xref    init_ints        ; interrupts.s
                xref    dispatch_in      ; interrupts.s (M7c: launch of the 1st task = user-mode transition)
                xref    build_reslist    ; resident.s (scan of the ROMTags)
                xref    task_alloc
                xref    ciaa_server      ; cia.s (PORTS/INT2 server)
                xref    ciab_server      ; cia.s (EXTER/INT6 server, exclusive vector)
                xref    gfx_display_init ; graphics/gfx.s (M4a: first Copper-driven display)
                xref    strap_boot       ; exec/strap.s (M6r: boot decision -> insert-disk if not bootable)
                xref    alert_boothook   ; exec/execmisc.s (role of alert.hook)
                xref    kbd_selftest     ; exec/keyboard.s (F2a: CIA-A keyboard reception+decoding)
                xref    kbd_devevent     ; exec/kbddev.s (keyboard.device: synthetic raw keycode for the proof)
                xref    kbd_install      ; exec/keyboard.s (F2b: installs the LIVE interrupt-driven keyboard driver)
                xref    font8x8          ; graphics/font8x8.s (#3a: 8x8 glyphs — console.device proof readback)
                xref    dv_validate      ; dos/diskvalidator.s (#4: validates the OFS bitmap of DF0:)
                xref    kbd_cook         ; exec/keymap.s (#5: cook keycode(+qualifiers)->ASCII, US/AZERTY)
                xref    req_draw         ; intuition/requester.s (requester: border+text rendering)
                xdef    boot_dos_start   ; dos/dos_lib.s (rt_Init of dos.library)
                xref    dos_mountlist
                xref    strap_romboot    ; exec/strap.s
                xref    dos_df0bootnode  ; dos/dos_lib.s
                xref    req_input_handler ; intuition/requester.s (requester: click handler on input.device)
                xref    td_read_track0   ; exec/trackdisk.s (B2: read of a raw MFM track of DF0)
                xref    td_decode_track  ; exec/trackdisk.s (B3: MFM decoding track -> 512-byte sectors)
                xref    td_read_track    ; exec/trackdisk.s (B2b: seek + read of an arbitrary track)
                xref    td_disk_present  ; exec/trackdisk.s (insert-disk screen: floppy inserted?)
                xref    ofs_read_file    ; dos/ofs.s (D1: read-only OFS -> read a file by name)
                xref    dos_loadseg      ; dos/loadseg.s (D2: load a hunk executable from the OFS + reloc)
                xref    dos_unloadseg    ; dos/loadseg.s (D2: free a seglist)
                xref    proc_create      ; dos/process.s (D3: create a Process + pr_MsgPort)
                xref    dos_sendpkt      ; dos/process.s (D3: send a DOS packet + WaitPort/GetMsg)
                xref    dos_handler      ; dos/handler.s (D3b: floppy OFS file-handler process, one per drive)
                xref    ls_load_hunks    ; dos/loadseg.s (D3d: parse hunks from a buffer read via dos)
                xref    con_handler      ; dos/conhandler.s (E1: serial console handler process)
                xref    exec_AddTail     ; exec/lists.s (ExecBase in LibList at coldstart)
                xref    shell_main       ; dos/shell.s (E2: minimal interactive shell)
                xref    feeder_main      ; dos/feeder.s (integration F: keyboard feeder -> input.device)
                ifne    LOADSCREEN_DEMO
                xref    loadscreen_demo  ; graphics/loadscreen.s (loading screen, gated by LOADSCREEN_DEMO)
                endc
                xref    gp_delta8        ; exec/gameport.s (mouse: signed delta with 8-bit wraparound)
                xref    gp_poll          ; exec/gameport.s (mouse: poll logic -> RAWMOUSE InputEvent via IND_WRITEEVENT)
                xref    gp_install       ; exec/gameport.s (mouse: arms gp_vblank_server on the VERTB chain)
                xref    pointer_input_handler ; intuition/pointer.s (accumulator relative deltas -> absolute position)

                xref    exec_softint_init
                xdef    ser_puts         ; serial output (diagnostics of the BCPL runtime)
                xdef    ser_puthex
                xdef    ser_lock         ; atomic serial output (Forbid gated by SCHED_ON) — used by conhandler/feeder/shell
                xdef    ser_unlock

DEMO_STK     EQU 2048         ; stack of the demo tasks (switch frames)
D3_STK       EQU 4096         ; stack of the D3 processes (driver/handler: ser_puts + ofs/loadseg later)
LYT_PIX      macro                    ; pixel (\1, \2) of the layers probe BitMap == \3, otherwise failure
        moveq   #\1,d0
        moveq   #\2,d1
        moveq   #\3,d2
        bsr     lyt_px
        bne     lyt_fail
             endm
LYT_RPIX     macro                    ; ReadPixel(L2, \1, \2) == \3, otherwise failure
        moveq   #\1,d0
        moveq   #\2,d1
        moveq   #\3,d2
        bsr     lyt_rpx
        bne     lyt_fail
             endm
AUT_KEY      EQU 32           ; IOAudio ioa_AllocKey / ioa_Data / ioa_Length / ioa_Period / ioa_Volume / ioa_Cycles
AUT_DATA     EQU 34
AUT_LENGTH   EQU 38
AUT_PERIOD   EQU 42
AUT_VOLUME   EQU 44
AUT_CYCLES   EQU 46
SEMT_NEST    EQU 14           ; SignalSemaphore ss_NestCount / ss_Owner / ss_QueueCount (semaphore probe)
SEMT_OWNER   EQU 40
SEMT_QC      EQU 44
SEMT_SIZE    EQU 48
KDT_ACTUAL   EQU 32           ; IOStdReq io_Actual / io_Length / io_Data (keyboard.device probe)
KDT_LENGTH   EQU 36
KDT_DATA     EQU 40
IOF_QUICK_K  EQU 1
INP_IO_DATA  EQU 40           ; #2: IOStdReq io_Data (boot.s does not include disk.i -> local EQU)
INPUT_TESTBLK EQU 120         ; #2: input.device test block = ioreq(48)+h1(24)+h2(24)+event(22), rounded even
CMD_WRITE_BO EQU 3            ; #3a: io_Command CMD_WRITE (local EQU)
CMD_READ_BO  EQU 2            ; #3b: io_Command CMD_READ (local EQU)
IO_LEN_BO    EQU 36           ; #3a: IOStdReq io_Length (local EQU)
; D3b: fs-driver block (a single AllocMem, long-aligned sub-parts for the BPTRs)
FSD_SP       EQU 0            ; StandardPacket (68)
FSD_FH       EQU 68           ; FileHandle (44)
FSD_BUF      EQU 112          ; read buffer (2048)
FSD_NAME     EQU 2160         ; BSTR name (len + "kickslop")
FSD_TOTAL    EQU 2176
DEMO_SIG     EQU 16           ; signal bit of task_H (outside the 0-15 reserved for the system)
DEMO_PRI_H   EQU 10           ; task_H: high priority (target of the yield-on-Permit)
FB_SIG       EQU 17           ; signal bit of task_fb (Forbid atomicity proof; outside 0-15, != DEMO_SIG)
FB_PRI_FA    EQU 3            ; task_fa: low priority (holds the Forbid)
FB_PRI_FB    EQU 7            ; task_fb: HIGH priority (would preempt fa if Forbid were not respected)
DEMO_PRI_T   EQU 10           ; task_timer (M7a): same pri as task_H -> they share the dispatches
CONS_THRESH  EQU 100          ; wake-ups of task_H (via yield) required for "M3F LIVE"
                ifne    M7E_COOP
SPIN_THRESH  EQU 0            ; cooperative: no task_S -> "M3F LIVE" through the yield alone
                else
SPIN_THRESH  EQU 5            ; iterations of task_S (via preemption) required for "M3F LIVE"
                endc
TCONS_THRESH EQU 50           ; wake-ups of task_timer (via the MICROHZ IRQ) required for "M7A TIMER OK"
M7A_MINTICKS EQU 250          ; AND minimum delay (VBlank ticks = 5 s) elapsed before emitting OK:
                              ; the clash detector runs at each INT6 (~2/s), so in RED a
                              ; clash happens WELL BEFORE 5 s -> "M7A FAILED" comes first, OK does not appear.
                ifne    M7D_STRESS_MAX
DEMO_PRI_P   EQU 20           ; RED A/B: task_port hammers the port (max contention vs IRQ)
                else
DEMO_PRI_P   EQU 0            ; task_port (M7d): pri 0 -> shares the CPU fairly with task_S/L
                endc
STRESS_K     EQU 4            ; number of stress messages circulating on the shared port
PORTT_THRESH EQU 60           ; GetMsg+PutMsg iterations of task_port required for "M7D PORTS OK"
PORTI_THRESH EQU 300          ; interrupt-side iterations required (fast producer ~INT6)
PEMPTY_LIMIT EQU 50000        ; M7d: consecutive empty GetMsgs = lost nodes (corruption); GREEN ~0
SENT_H       EQU $CAFE0010    ; context sentinels (must survive EVERY switch)
SENT_L       EQU $CAFE0020
SENT_S       EQU $CAFE0030
SENT_T       EQU $CAFE0040    ; sentinel of task_timer (M7a)
SENT_P       EQU $CAFE0050    ; sentinel of task_port (M7d)
SENT_Q2      EQU $CAFE0060    ; sentinel of task_q2 (M7h, isolation spinner-2)
SENT_RM      EQU $CAFE0070    ; sentinel of task_rm (M7j, terminating task)
M7H_MINTICKS EQU 150          ; min VBlank ticks before emitting "M7H QUANTUM OK" (stable ratio, ~3 s)
                ifne    M7L_OLD_CONV
TT_MICRO_REQ EQU 400000       ; RED M7L_OLD_CONV: /20000 -> 20 int -> ~7.2 ms (period unchanged)
                else
TT_MICRO_REQ EQU 7000         ; M7l: 7000 REAL us (~= old rate ~140/s)
                endc
; (FTEST_LO/FTEST_HI, multi-header test region, are in exec.i — memory map)

; The header must land at $FC0000: boot.o is the FIRST object passed to vlink
; (cf. Makefile), so its CODE carries the reset vector. hdr_start = offset 0 of the
; section; the padding uses an intra-section difference (constant in relocatable output).
hdr_start:
        dc.w    $1111
        dc.w    $4EF9
        dc.l    coldstart        ; +04 reset PC
        dc.l    $0000FFFF        ; +08
        dc.l    $00220005        ; +0C ROM version 34.5
        dc.l    $00220002        ; +10
        dc.l    $FFFFFFFF        ; +14
        dcb.b   $D0-(*-hdr_start),0
        dc.w    $4E70            ; $FC00D0 RESET (magic_reset)

coldstart:                        ; $FC00D2
        ; --- Phase 1: supervisor + hardware freeze (straight-line, no stack) ---
        move.w  #$2700,sr
        move.w  #$7FFF,DMACON
        move.w  #$7FFF,INTENA
        move.w  #$7FFF,INTREQ
        move.w  #C_RED,COLOR00

        ; --- Phase 2: overlay off then install the stack ---
        move.b  #$03,CIAA_DDRA
        move.b  #$02,CIAA_PRA        ; OVL off -> chip RAM at $0
        move.l  #STACKTOP,sp
        lea     LOWVARS_LO,a0        ; low-RAM variables zeroed: RAM is not null at power-on on a
        move.w  #(LOWVARS_HI-LOWVARS_LO)/4-1,d0 ; real machine nor under WinUAE (an odd keyboard buffer index there
.lv_clr:                             ; caused an address error at the 1st key press; FS-UAE clears RAM)
        clr.l   (a0)+
        dbra    d0,.lv_clr
        move.w  #C_BLUE,COLOR00
        move.w  #SERPER_9600_PAL,SERPER
        lea     msg_cold(pc),a0
        bsr     ser_puts

        ; --- F2a: CIA-A keyboard reception+decoding (EARLY, interrupts still masked -> no race with the
        ; cia_wrapper that cleared the SP flag). Decodes the power-up stream of the emulated keyboard ($FD initiate +
        ; $FE terminate), proving the keyboard path WITHOUT injector. d0 = flags; d0==3 = both seen. ---
        jsr     kbd_selftest         ; keyboard.o linked far away -> absolute jsr
        cmp.b   #3,d0
        bne.s   .f2a_nokbd
        lea     msg_f2kbd(pc),a0
        bsr     ser_puts             ; "F2 KBD OK"
.f2a_nokbd:

        ; --- Phase 3: ExecBase + jump table ---
        move.w  #C_CYAN,COLOR00
        lea     EXECBASE,a0          ; zero-fill the area of the positive fields
        move.w  #(EXEC_POSSIZE/4)-1,d0
.zf:
        clr.l   (a0)+
        dbf     d0,.zf

        lea     EXECBASE,a6          ; a6 = SysBase (library base convention)
        move.b  #NT_LIBRARY,LN_TYPE(a6)
        move.l  #exec_name,LN_NAME(a6)
        move.w  #EXEC_NEGSIZE,LIB_NEGSIZE(a6)
        move.w  #EXEC_POSSIZE,LIB_POSSIZE(a6)
        move.w  #34,LIB_VERSION(a6)
        move.w  #2,LIB_REVISION(a6)
        move.l  #exec_id,LIB_IDSTRING(a6)
        move.l  #MAXCHIP,EB_MAXLOCMEM(a6)
        move.w  #0,EB_ATTNFLAGS(a6)
        move.b  #50,EB_VBLANKFREQ(a6)
        move.b  #50,EB_POWERFREQ(a6)
        move.b  #-1,EB_IDNEST(a6)
        move.b  #-1,EB_TDNEST(a6)
        move.l  #EXECBASE,d0
        not.l   d0
        move.l  d0,EB_CHKBASE(a6)

        lea     EB_MEMLIST(a6),a1
        jsr     newlist
        lea     EB_RESOURCELIST(a6),a1
        jsr     newlist
        lea     EB_DEVICELIST(a6),a1
        jsr     newlist
        lea     EB_INTRLIST(a6),a1
        jsr     newlist
        lea     EB_LIBLIST(a6),a1
        jsr     newlist
        lea     EB_LIBLIST(a6),a0    ; exec.library is the 1st library of LibList (programs
        move.l  a6,a1                ; derive GfxBase from it: ExecBase->ln_Succ->ln_Succ, after expansion)
        jsr     exec_AddTail
        lea     EB_PORTLIST(a6),a1
        jsr     newlist
        lea     EB_TASKREADY(a6),a1
        jsr     newlist
        lea     EB_TASKWAIT(a6),a1
        jsr     newlist
        lea     EB_SEMLIST(a6),a1
        jsr     newlist

        jsr     build_jumptable
        jsr     init_memory
        jsr     init_task            ; "boot task" TCB -> ThisTask (before selftest)

        ; --- Phase 4: publish SysBase, self-check, self-test ---
        move.l  a6,($4).w

        move.l  ($4).w,d0
        cmp.l   #EXECBASE,d0
        bne     eb_fail
        cmp.w   #34,LIB_VERSION(a6)
        bne     eb_fail
        move.l  a6,d0
        not.l   d0
        cmp.l   EB_CHKBASE(a6),d0
        bne     eb_fail
        move.l  EB_MEMLIST(a6),d0    ; lh_Head must point to the added MemHeader
        cmp.l   #MH_CHIP,d0
        bne     eb_fail

        bsr     selftest             ; d0 = 0 (OK) / !=0 (failure)
        tst.l   d0
        bne     eb_fail
        jsr     add_slow_memory      ; after the memory selftest (which assumes chip at the head of the list)
        lsr.l   #8,d0                ; bytes -> KB (512 KB = $0200)
        lsr.l   #2,d0
        move.w  d0,d2
        lea     msg_memslow(pc),a0
        bsr     ser_puts             ; "MEM SLOW KB="
        move.w  d2,d0
        bsr     ser_puthex
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        bsr     rdf_selftest         ; RawDoFmt (-522): formatting compared with an expected string
        ; --- M3a: arm VBlank and prove that the interrupt chain runs ---
        jsr     init_ints
        jsr     exec_softint_init    ; software interrupt queue (Cause) + SOFTINT server
        move.l  #$00100000,d1        ; spin timeout (GREEN exits on count=5 well before)
.vbl_wait:
        lea     VBL_COUNT,a0
        move.l  (a0),d0              ; load INSIDE the loop (the counter changes)
        cmp.l   #5,d0
        bcc.s   .vbl_live
        subq.l  #1,d1
        bne.s   .vbl_wait
        lea     msg_vbltimeout(pc),a0  ; dead interrupts -> failure
        bsr     ser_puts
        bra     eb_fail
.vbl_live:
        lea     msg_vblok(pc),a0
        bsr     ser_puts

        move.w  #C_WHITE,COLOR00
        lea     msg_ok(pc),a0
        bsr     ser_puts             ; "self-test passed" emitted BEFORE the launch (gate kept)

        ; --- M4: resident scan + InitCode (data-driven machinery) ---
        ; Proves the module discovery MACHINERY (ROM scan of the ROMTags -> pri-sorted ResModules
        ; -> InitResident/InitCode of each in descending order) with DEMO residents.
        ; It is NOT the boot handoff: the handoff remains the hard-coded M3f demo
        ; below (rte that never returns) as long as no real module (cia/timer...)
        ; exists. The demo residents only emit their name; nothing is launched by them.
        move.l  #127,RES_LASTPRI     ; upper bound (any RT_PRI <= 127 passes)
        clr.l   RES_COUNT
        jsr     build_reslist        ; scans [RESSCAN_LO,HI) -> ExecBase->ResModules
        moveq   #RTF_COLDSTART,d0    ; startClass: cold-start residents
        moveq   #0,d1                ; minimum version 0
        jsr     LVO_INITCODE(a6)     ; init each demo resident (emits its name in pri order)
        lea     res_mid_name(pc),a1  ; FindResident(name) must find the right resident
        jsr     LVO_FINDRESIDENT(a6)
        cmp.l   #res_mid,d0
        bne     res_fail
        cmp.l   #3,RES_COUNT         ; the 3 direct-init demo residents initialised?
        bne     res_fail
        lea     msg_res_ok(pc),a0
        bsr     ser_puts             ; "M4 RESIDENTS OK"

        ; --- M5a: check the AUTOINIT resident (demo.autolib) created by MakeLibrary ---
        lea     EB_LIBLIST(a6),a0    ; the lib must have been added to LibList
        lea     autolib_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     auto_fail            ; lib missing -> AUTOINIT/add failed
        move.l  d0,a2                ; a2 = lib base
        cmp.w   #40,LIB_VERSION(a2)  ; did InitStruct (INITWORD) set the version?
        bne     auto_fail
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; did InitStruct (INITBYTE) set the type?
        bne     auto_fail
        cmp.w   #$5A,LIB_REVISION(a2) ; did the init function run (did it set the revision)?
        bne     auto_fail
        move.l  a6,-(sp)             ; save SysBase
        move.l  a2,a6                ; a6 = lib base (calling convention)
        jsr     -6(a6)               ; call func0 via the jump table -> d0 (MakeFunctions OK?)
        move.l  (sp)+,a6             ; restore SysBase
        cmp.l   #$5A,d0
        bne     auto_fail
        lea     msg_auto_ok(pc),a0
        bsr     ser_puts             ; "M5A AUTOINIT OK"

        ; --- M5b: check cia.resource (1st real resident module, direct-init) ---
        lea     ciab_test_name(pc),a1  ; OpenResource("ciab.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     cia_fail             ; resource missing -> failed
        move.l  d0,a2                ; a2 = ciab base
        cmp.l   #CIAB_HW,CIAR_HWBASE(a2)  ; right hardware base?
        bne     cia_fail
        move.l  a6,-(sp)             ; AbleICR($81 = enable bit0) via the resource's jump table
        move.l  a2,a6                ; a6 = resource base (calling convention)
        moveq   #$81,d0
        jsr     CIA_ABLEICR(a6)
        move.l  (sp)+,a6
        move.b  CIAR_ICRMASK(a2),d0  ; the shadow must have bit0 set
        and.b   #1,d0
        beq     cia_fail
        move.l  a6,-(sp)             ; AddICRVector(bit1, dummy) -> must return NULL (free slot)
        move.l  a2,a6
        moveq   #1,d0
        lea     cia_dummy_int(pc),a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        tst.l   d0
        bne     cia_fail
        move.l  a6,-(sp)             ; the test gives back what it took: dummy vector removed, bit 0 disabled (otherwise
        move.l  a2,a6                ; CIA-B timer B stayed busy for applications, e.g. the OctaMED player)
        moveq   #1,d0
        lea     cia_dummy_int(pc),a1
        jsr     CIA_REMICRVECTOR(a6)
        moveq   #$01,d0
        jsr     CIA_ABLEICR(a6)
        move.l  (sp)+,a6
        lea     msg_cia_ok(pc),a0
        bsr     ser_puts             ; "M5B CIA OK"

        ; --- M5c: check timer.device (AUTOINIT, 2nd real resident module) ---
        lea     EB_DEVICELIST(a6),a0 ; the device must have been added to DeviceList
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)     ; (= what OpenDevice does internally)
        tst.l   d0
        beq     timer_fail
        move.l  d0,a2                ; a2 = device base
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD)?
        bne     timer_fail
        cmp.b   #NT_DEVICE,LN_TYPE(a2)  ; InitStruct (INITBYTE)?
        bne     timer_fail
        move.l  a6,-(sp)             ; Open via the device's jump table -> LIB_OPENCNT++
        move.l  a2,a6                ; a6 = device base (convention)
        suba.l  a1,a1                ; iorequest = NULL (the stub ignores it)
        moveq   #0,d0                ; unit 0
        moveq   #0,d1                ; flags
        jsr     -6(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)   ; did Open increment?
        bne     timer_fail
        lea     msg_timer_ok(pc),a0
        bsr     ser_puts             ; "M5C TIMER OK"

        ; --- M4c1: check graphics.library (AUTOINIT, 1st LIBRARY -> LibList) ---
        ; Mirror of the M5c proof, but on EB_LIBLIST (NT_LIBRARY->LibList branch, new). Skip-on-fail:
        ; in RED (RT_TYPE=NT_DEVICE) GfxBase is routed to DeviceList -> FindName(LibList) misses -> marker
        ; absent, without "FAILED" (the rest of the boot continues).
        lea     EB_LIBLIST(a6),a0
        lea     graphics_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   m4c1_done
        move.l  d0,a2                ; a2 = GfxBase
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD)?
        bne.s   m4c1_done
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; InitStruct (INITBYTE)? (a misrouted device would not get here either)
        bne.s   m4c1_done
        move.l  a6,-(sp)             ; Open via the jump table -> LIB_OPENCNT++
        move.l  a2,a6
        jsr     -6(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)
        bne.s   m4c1_done
        lea     msg_m4c1_ok(pc),a0
        bsr     ser_puts             ; "M4C1 GFX LIB OK"
m4c1_done:

        ; --- M5: check intuition.library (resident skeleton + ViewAddress) ---
        ; Mirror of the M4c1 proof on EB_LIBLIST, extended with a REAL ABI call: ViewAddress (LVO -294) must
        ; return &ib_ViewLord (= IntuitionBase + IB_VIEWLORD). Skip-on-fail: if one of the checks fails
        ; (or RED M5I_BAD_VIEWADDR -> ViewAddress=0), the "M5I INTUI LIB OK" marker is absent, without FAILED.
        lea     EB_LIBLIST(a6),a0
        lea     intuition_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   m5i_done
        move.l  d0,a2                ; a2 = IntuitionBase
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD)?
        bne.s   m5i_done
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; InitStruct (INITBYTE)? (a misrouted device would not pass FindName either)
        bne.s   m5i_done
        move.l  a6,-(sp)             ; Open via the jump table -> LIB_OPENCNT++
        move.l  a2,a6
        jsr     LVO_OPEN(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)
        bne.s   m5i_done
        move.l  a6,-(sp)             ; ViewAddress() via the jump table (a6 = IntuitionBase)
        move.l  a2,a6
        jsr     -294(a6)             ; LVO_VIEWADDRESS = -294 (literal: boot.s only includes exec.i)
        move.l  (sp)+,a6
        lea     LIB_SIZE(a2),a1      ; expected: &ib_ViewLord (IB_VIEWLORD = LIB_SIZE: the ViewLord follows the Library base)
        cmp.l   a1,d0
        bne.s   m5i_done
        lea     msg_m5i_ok(pc),a0
        bsr     ser_puts             ; "M5I INTUI LIB OK"
m5i_done:

        ; --- OpenLibrary: opening by name + version gate (exec) ---
        ; 1) OpenLibrary("intuition.library",34) == base & OpenCnt+1; 2) version 99 -> 0 (version gate);
        ; 3) nonexistent lib -> 0; 3b) OldOpenLibrary == base (without gate); 4) CloseLibrary -> OpenCnt-1.
        ; RED OPENLIB_NO_VERCHECK: (2) WRONGLY opens
        ; (d0 != 0) -> assertion fails -> "M5O OPENLIB OK" absent. a2 = IntuitionBase, d3 = OpenCnt baseline.
        lea     EB_LIBLIST(a6),a0
        lea     intuition_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   m5o_done
        move.l  d0,a2                ; a2 = IntuitionBase
        move.w  LIB_OPENCNT(a2),d3   ; d3 = OpenCnt baseline (N)
        lea     intuition_test_name(pc),a1   ; 1) success version 34
        moveq   #34,d0
        jsr     LVO_OPENLIBRARY(a6)
        cmp.l   a2,d0                ; == IntuitionBase?
        bne.s   m5o_done
        move.w  LIB_OPENCNT(a2),d0
        subq.w  #1,d0
        cmp.w   d3,d0                ; OpenCnt == N+1?
        bne.s   m5o_done
        lea     intuition_test_name(pc),a1   ; 2) version 99 too high -> 0, OpenCnt unchanged
        move.w  #99,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        bne.s   m5o_done             ; RED OPENLIB_NO_VERCHECK: returns base != 0 -> M5O absent
        move.w  LIB_OPENCNT(a2),d0
        subq.w  #1,d0
        cmp.w   d3,d0                ; still N+1 (no opening)?
        bne.s   m5o_done
        lea     noexist_test_name(pc),a1     ; 3) nonexistent lib -> 0
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        bne.s   m5o_done
        lea     intuition_test_name(pc),a1   ; 3b) OldOpenLibrary (pre-V33, without version gate) == base
        jsr     LVO_OLDOPENLIBRARY(a6)
        cmp.l   a2,d0
        bne.s   m5o_done
        move.l  a2,a1                ; rebalance opening 3b (net zero) before step 4
        jsr     LVO_CLOSELIBRARY(a6)
        move.l  a2,a1                ; 4) CloseLibrary -> OpenCnt goes back to N
        jsr     LVO_CLOSELIBRARY(a6)
        move.w  LIB_OPENCNT(a2),d0
        cmp.w   d3,d0                ; OpenCnt == N?
        bne.s   m5o_done
        lea     msg_m5o_ok(pc),a0
        bsr     ser_puts             ; "M5O OPENLIB OK"
m5o_done:

        ; --- M6: check dos.library (resident skeleton + BPTR convention + DateStamp) ---
        ; Mirror of the M4c1/M5 proofs on EB_LIBLIST, extended with two checks: (a) BPTR round-trip — dl_Root (APTR) ->
        ; RootNode, rn_Info (BPTR) <<2 must equal &DosInfo (read via the DL_DISHADOW scaffold, compute-then-compare,
        ; WITHOUT dereferencing the decoded pointer: in RED the failure is an address mismatch, never a bus error);
        ; (b) DateStamp(-192) fills (0,0,0) "clock not set" and returns the pointer. Skip-on-fail: any
        ; failed check (or RED M6D_BAD_BPTR) -> "M6D DOS LIB OK" absent, without FAILED. a6 = ExecBase.
        lea     EB_LIBLIST(a6),a0
        lea     dos_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m6d_done
        move.l  d0,a2                ; a2 = DosBase
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD)?
        bne     m6d_done
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; InitStruct (INITBYTE)?
        bne     m6d_done
        move.l  a6,-(sp)             ; Open via the jump table -> LIB_OPENCNT++
        move.l  a2,a6
        jsr     LVO_OPEN(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)
        bne     m6d_done
        ; (a) BPTR round-trip — NO dereferencing of the decoded pointer
        move.l  LIB_SIZE(a2),a3      ; a3 = dl_Root (DL_ROOT = LIB_SIZE = 34) = RootNode (APTR)
        move.l  a3,d0
        beq     m6d_done             ; RootNode allocated?
        move.l  70(a2),d2            ; d2 = DL_DISHADOW (offset 70) = &DosInfo (raw APTR, known)
        beq     m6d_done             ; DosInfo allocated?
        move.l  24(a3),d0            ; d0 = rn_Info (RN_INFO = 24); safe read (a3 = valid RootNode, GREEN and RED)
        lsl.l   #2,d0                ; BPTR -> APTR
        cmp.l   d2,d0                ; == &DosInfo?  RED M6D_BAD_BPTR: raw rn_Info -> 4*&DosInfo != shadow
        bne     m6d_done
        ; (b) DateStamp -> (0,0,0) + returns the pointer. 12-byte buffer on the stack, pre-dirtied.
        lea     -12(sp),sp           ; buf = sp (DS_SIZEOF = 12)
        move.l  #$5A5A5A5A,(sp)      ; dirty the 3 longs: "set to 0" becomes discriminating
        move.l  #$5A5A5A5A,4(sp)
        move.l  #$5A5A5A5A,8(sp)
        move.l  sp,d1                ; d1 = &date (dos convention: arg in d1)
        move.l  a6,-(sp)             ; swap a6 -> DosBase (shifts sp by 4; d1 = absolute address, unchanged)
        move.l  a2,a6
        jsr     -192(a6)             ; LVO_DATESTAMP = -192; d0 = &date, date = {0,0,0}
        move.l  (sp)+,a6             ; restore a6 = ExecBase (sp back at the buffer)
        cmp.l   sp,d0                ; does it return the pointer passed?
        bne.s   m6d_ds_pop
        tst.l   (sp)                 ; ds_Days == 0?
        bne.s   m6d_ds_pop
        tst.l   4(sp)               ; ds_Minute == 0?
        bne.s   m6d_ds_pop
        tst.l   8(sp)               ; ds_Tick == 0?
        bne.s   m6d_ds_pop
        lea     12(sp),sp            ; free the buffer (success)
        lea     msg_m6d_ok(pc),a0
        bsr     ser_puts             ; "M6D DOS LIB OK"
        bra.s   m6d_done
m6d_ds_pop:
        lea     12(sp),sp            ; free the buffer (DateStamp failure)
m6d_done:

        ; --- expansion.library: v37 version gate + round-trip of the ConfigDev list (Alloc->Add->Find) ---
        ; (1) OpenLibrary("expansion.library", 37) MUST fail (KS 2.0 gate; this is what makes the Lemmings
        ; bootblock skip its expansion branch on our V34); OpenLibrary(..., 34) succeeds. (2) AllocConfigDev -> sets
        ; manufacturer/product -> AddConfigDev -> FindConfigDev finds them (exact + product wildcard) + an absent ID
        ; does not match -> "EXPANSION OK". Robust cleanup: Remove ONLY if the node is linked (ln_Succ!=0),
        ; otherwise (RED EXP_NO_ENQUEUE: not added) we only free. Synchronous (pure lib functions, no packets).
        lea     expansion_test_name(pc),a1
        moveq   #37,d0               ; v37 (KS 2.0) -> MUST return 0 on our V34
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        bne     exp_done             ; v37 wrongly opens (broken gate) -> do not emit
        lea     expansion_test_name(pc),a1
        moveq   #34,d0               ; V34 -> must succeed
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     exp_done
        move.l  d0,a2                ; a2 = ExpansionBase (preserved by exec + the exp_* functions)
        move.l  a2,a6
        jsr     EXP_LVO_ALLOCCONFIGDEV(a6)   ; d0 = ConfigDev | 0
        tst.l   d0
        beq     exp_close1
        move.l  d0,a3                ; a3 = ConfigDev
        move.w  #$0202,ER_MANUFACTURER(a3)   ; test IDs (manufacturer word + product byte)
        move.b  #$42,ER_PRODUCT(a3)
        move.l  a2,a6                ; AddConfigDev(cd a0)
        move.l  a3,a0
        jsr     EXP_LVO_ADDCONFIGDEV(a6)
        move.l  a2,a6                ; FindConfigDev(0, $0202, $42) -> must == a3
        suba.l  a0,a0
        move.l  #$0202,d0
        move.l  #$42,d1
        jsr     EXP_LVO_FINDCONFIGDEV(a6)
        cmp.l   a3,d0
        bne     exp_rem
        move.l  a2,a6                ; FindConfigDev(0, $0202, -1) product wildcard -> a3
        suba.l  a0,a0
        move.l  #$0202,d0
        moveq   #-1,d1
        jsr     EXP_LVO_FINDCONFIGDEV(a6)
        cmp.l   a3,d0
        bne     exp_rem
        move.l  a2,a6                ; FindConfigDev(0, $9999, $42) -> no match -> 0
        suba.l  a0,a0
        move.l  #$9999,d0
        move.l  #$42,d1
        jsr     EXP_LVO_FINDCONFIGDEV(a6)
        tst.l   d0
        bne     exp_rem
        lea     msg_expansion_ok(pc),a0
        bsr     ser_puts             ; "EXPANSION OK"
exp_rem:
        tst.l   (a3)                 ; ln_Succ != 0 -> the ConfigDev is indeed linked into the list
        beq.s   exp_freeonly
        move.l  ($4).w,a6
        move.l  a3,a1
        jsr     LVO_REMOVE(a6)       ; Remove(cd) before free
exp_freeonly:
        move.l  a2,a6
        move.l  a3,a0
        jsr     EXP_LVO_FREECONFIGDEV(a6)
exp_close1:
        move.l  ($4).w,a6
        move.l  a2,a1
        jsr     LVO_CLOSELIBRARY(a6)
exp_done:
        move.l  ($4).w,a6            ; restore a6 = ExecBase for what follows (M6t)

        ; --- mathffp.library: FFP vector table (LVO, d0, d1, expected result computed outside the ROM) ---
        ; Each call goes through the LVO vector of the opened base; a mismatch -> "MATHFFP FAIL" + faulting LVO.
        ; The loop keeps its state in d4/d5/a2/a3: a function that does not preserve d2-d7 breaks the proof.
        movem.l d4-d5/a2-a3,-(sp)
        lea     mathffp_test_name(pc),a1
        moveq   #34,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   mft_done
        move.l  d0,a3
        lea     mft_table(pc),a2
        moveq   #(mft_table_end-mft_table)/14-1,d5
mft_lp:
        move.w  (a2)+,d4
        move.l  (a2)+,d0
        move.l  (a2)+,d1
        move.l  a3,a6
        jsr     0(a6,d4.w)
        cmp.l   (a2)+,d0
        bne.s   mft_fail
        dbra    d5,mft_lp
        lea     msg_mathffp_ok(pc),a0
        bsr     ser_puts
        bra.s   mft_close
mft_fail:
        lea     msg_mathffp_fail(pc),a0
        bsr     ser_puts
        move.w  d4,d0
        bsr     ser_puthex
        lea     msg_crlf_mft(pc),a0
        bsr     ser_puts
mft_close:
        move.l  ($4).w,a6
        move.l  a3,a1
        jsr     LVO_CLOSELIBRARY(a6)
mft_done:
        movem.l (sp)+,d4-d5/a2-a3
        move.l  ($4).w,a6

        ; --- disk.resource: AllocUnit/FreeUnit, GetUnitID, then GetUnit/GiveUnit with a wait queue ---
        ; dru1 takes the controller (GetUnit returns the "last driver", non-null and != dru1); dru2 is put on hold
        ; (GetUnit = 0); GiveUnit ReplyMsgs it (without port: LN_TYPE -> NT_REPLYMSG); dru2 retries and gets
        ; dru1 as last driver. The DRUs live on the stack: DR_CURRENT then remains a mere witness (never
        ; dereferenced outside controller ownership). The DF1 identifier read at startup is displayed.
        movem.l d4/a2-a4,-(sp)
        lea     diskres_test_name(pc),a1
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     drt_done
        move.l  d0,a2
        lea     -176(sp),sp
        move.l  sp,a3                ; a3 = dru1, a4 = dru2 (88 bytes each, zeroed)
        lea     88(a3),a4
        move.l  a3,a0
        moveq   #43,d0
drt_clr:
        clr.l   (a0)+
        dbra    d0,drt_clr
        move.l  a2,a6
        moveq   #0,d0
        jsr     -6(a6)               ; AllocUnit(0) -> 1
        cmp.l   #1,d0
        bne     drt_fail
        moveq   #0,d0
        jsr     -6(a6)               ; already taken -> 0
        tst.l   d0
        bne     drt_fail
        moveq   #0,d0
        jsr     -12(a6)              ; FreeUnit(0)
        moveq   #0,d0
        jsr     -6(a6)               ; free again -> 1
        cmp.l   #1,d0
        bne     drt_fail
        moveq   #0,d0
        jsr     -12(a6)
        moveq   #4,d0
        jsr     -6(a6)               ; invalid unit -> 0
        tst.l   d0
        bne     drt_fail
        moveq   #0,d0
        jsr     -30(a6)              ; GetUnitID(0) = DRT_AMIGA
        tst.l   d0
        bne     drt_fail
        moveq   #1,d0
        jsr     -30(a6)
        move.l  d0,d4                ; d4 = DF1 identifier
        move.l  a3,a1
        jsr     -18(a6)              ; GetUnit(dru1): free
        tst.l   d0
        beq     drt_fail
        cmp.l   a3,d0
        beq     drt_fail
        move.b  #NT_MESSAGE,LN_TYPE(a4)
        move.l  a4,a1
        jsr     -18(a6)              ; GetUnit(dru2): busy -> 0, put on hold
        tst.l   d0
        bne     drt_fail
        jsr     -24(a6)              ; GiveUnit -> ReplyMsg(dru2)
        cmp.b   #NT_REPLYMSG,LN_TYPE(a4)
        bne     drt_fail
        move.l  a4,a1
        jsr     -18(a6)              ; dru2 retries: last driver = dru1
        cmp.l   a3,d0
        bne     drt_fail
        jsr     -24(a6)
        lea     msg_diskres_ok(pc),a0
        bsr     ser_puts
        move.l  d4,d0
        swap    d0
        bsr     ser_puthex
        move.l  d4,d0
        bsr     ser_puthex
        lea     msg_crlf_mft(pc),a0
        bsr     ser_puts
        bra.s   drt_free
drt_fail:
        lea     msg_diskres_fail(pc),a0
        bsr     ser_puts
drt_free:
        lea     176(sp),sp
drt_done:
        movem.l (sp)+,d4/a2-a4
        move.l  ($4).w,a6

        ; --- potgo.resource: START / DATxx allocation rules + high byte kept by WritePotgo ---
        ; (expected: AutoDoc AllocPotBits; a caller can block itself, the resource does not track
        ; owners). POTGO is reset to 0 (all pins as input, reset value) at the end.
        move.l  a2,-(sp)
        lea     potgo_test_name(pc),a1
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     pgt_done
        move.l  d0,a6
        move.l  d0,a2
        move.w  #$0101,d0
        jsr     -6(a6)               ; START + DATLX as input -> granted
        cmp.w   #$0101,d0
        bne     pgt_fail
        move.w  #$0400,d0
        jsr     -6(a6)               ; DATLY as input while START is held -> refused
        tst.w   d0
        bne     pgt_fail
        move.w  #$0C00,d0
        jsr     -6(a6)               ; DATLY as output -> granted
        cmp.w   #$0400,d0
        bne     pgt_fail
        move.w  #$0100,d0
        jsr     -6(a6)               ; DATLX already taken -> refused
        tst.w   d0
        bne     pgt_fail
        move.w  #$0101,d0
        jsr     -12(a6)              ; FreePotBits(START + DATLX)
        moveq   #1,d0
        jsr     -6(a6)               ; START: only DATLY (output) remains taken -> granted
        cmp.w   #1,d0
        bne     pgt_fail
        move.w  #$0401,d0
        jsr     -12(a6)
        move.w  #$0C01,d0
        move.w  #$0C01,d1
        jsr     -18(a6)              ; WritePotgo: high byte kept, START not kept
        cmp.w   #$0C00,LIB_SIZE+2(a2)
        bne     pgt_fail
        moveq   #0,d0
        move.w  #$FF00,d1
        jsr     -18(a6)
        tst.w   LIB_SIZE+2(a2)
        bne     pgt_fail
        lea     msg_potgo_ok(pc),a0
        bsr     ser_puts
        bra.s   pgt_done
pgt_fail:
        lea     msg_potgo_fail(pc),a0
        bsr     ser_puts
pgt_done:
        move.l  (sp)+,a2
        move.l  ($4).w,a6

        ; --- keyboard.device: matrix, KBD_READEVENT (buffer / pending request returned by the event),
        ; CMD_CLEAR, AbortIO, reset handler list. SYNTHETIC keycodes handed to kbd_devevent (the same
        ; entry point as kbd_interrupt); the matrix is left empty (keys released) and the buffer emptied.
        ; Stack: IOStdReq 48 bytes, buffer 24 bytes (InputEvent / matrix), struct Interrupt 24 bytes.
        movem.l a2-a3,-(sp)
        lea     -96(sp),sp
        move.l  sp,a3
        move.l  a3,a0
        moveq   #23,d0
kdt_clr:
        clr.l   (a0)+
        dbra    d0,kdt_clr
        lea     kbddev_test_name(pc),a0
        moveq   #0,d0
        move.l  a3,a1
        moveq   #0,d1
        jsr     LVO_OPENDEVICE(a6)
        tst.b   d0
        bne     kdt_fail0
        move.l  IO_DEVICE(a3),a2
        bsr     kdt_matrix           ; empty matrix at start (keys $20-$27 = byte 4)
        tst.l   48+4(a3)
        bne     kdt_fail
        moveq   #$20,d0              ; "A" pressed
        jsr     kbd_devevent
        bsr     kdt_matrix
        cmp.b   #1,48+4(a3)
        bne     kdt_fail
        move.b  #IOF_QUICK_K,IO_FLAGS(a3)
        bsr     kdt_read             ; served from the buffer
        cmp.b   #IECLASS_RAWKEY,48+IE_CLASS(a3)
        bne     kdt_fail
        cmp.w   #$20,48+IE_CODE(a3)
        bne     kdt_fail
        cmp.l   #IE_SIZEOF,KDT_ACTUAL(a3)
        bne     kdt_fail
        move.l  #$A0,d0              ; "A" released
        jsr     kbd_devevent
        bsr     kdt_matrix
        tst.b   48+4(a3)
        bne     kdt_fail
        bsr     kdt_clear
        clr.b   IO_FLAGS(a3)         ; empty buffer: the request waits for an event
        move.b  #NT_MESSAGE,LN_TYPE(a3)
        bsr     kdt_read
        cmp.b   #NT_MESSAGE,LN_TYPE(a3)
        bne     kdt_fail
        moveq   #$45,d0              ; Escape pressed -> returns the pending request
        jsr     kbd_devevent
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne     kdt_fail
        cmp.w   #$45,48+IE_CODE(a3)
        bne     kdt_fail
        move.l  #$C5,d0              ; Escape released (buffered then cleared)
        jsr     kbd_devevent
        bsr     kdt_clear
        move.b  #NT_MESSAGE,LN_TYPE(a3)
        move.b  #IOF_QUICK_K,IO_FLAGS(a3)
        bsr     kdt_read             ; nothing buffered: IOF_QUICK cleared, request pending
        btst    #0,IO_FLAGS(a3)
        bne     kdt_fail
        move.l  a3,a1
        move.l  a2,a6
        jsr     -36(a6)              ; AbortIO
        move.l  ($4).w,a6
        cmp.b   #IOERR_ABORTED,IO_ERROR(a3)
        bne     kdt_fail
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne     kdt_fail
        lea     72(a3),a0            ; reset handler: added then removed
        move.b  #NT_INTERRUPT,LN_TYPE(a0)
        move.l  a0,KDT_DATA(a3)
        move.w  #11,IO_COMMAND(a3)   ; KBD_ADDRESETHANDLER
        bsr     kdt_io
        lea     72(a3),a0
        cmp.l   LIB_SIZE+30(a2),a0   ; head of the handler list
        bne     kdt_fail
        move.w  #12,IO_COMMAND(a3)   ; KBD_REMRESETHANDLER
        bsr     kdt_io
        move.l  LIB_SIZE+30(a2),a0
        tst.l   (a0)                 ; empty list: the head is the tail node
        bne     kdt_fail
        lea     msg_kbddev_ok(pc),a0
        bsr     ser_puts
        bra.s   kdt_close
kdt_fail:
        lea     msg_kbddev_fail(pc),a0
        bsr     ser_puts
kdt_close:
        move.l  a3,a1
        jsr     LVO_CLOSEDEVICE(a6)
        bra.s   kdt_done
kdt_fail0:
        lea     msg_kbddev_fail(pc),a0
        bsr     ser_puts
kdt_done:
        lea     96(sp),sp
        movem.l (sp)+,a2-a3
        move.l  ($4).w,a6
        bra     kdt_end
; subroutines of the keyboard.device probe (a3 = IOStdReq, a2 = device; return a6 = SysBase)
kdt_matrix:
        move.w  #10,IO_COMMAND(a3)   ; KBD_READMATRIX
        move.b  #IOF_QUICK_K,IO_FLAGS(a3)
        moveq   #16,d0
        bra.s   kdt_rd2
kdt_read:
        move.w  #9,IO_COMMAND(a3)    ; KBD_READEVENT
        moveq   #IE_SIZEOF,d0
kdt_rd2:
        move.l  d0,KDT_LENGTH(a3)
        lea     48(a3),a0
        move.l  a0,KDT_DATA(a3)
kdt_io:
        move.l  a3,a1
        move.l  a2,a6
        jsr     -30(a6)              ; BeginIO
        move.l  ($4).w,a6
        rts
kdt_clear:
        move.w  #5,IO_COMMAND(a3)    ; CMD_CLEAR
        move.b  #IOF_QUICK_K,IO_FLAGS(a3)
        bra.s   kdt_io
kdt_end:

        ; --- audio.device: allocation (without DMA or interrupt: synchronous at boot) ---
        ; ioa1 = channel 0 at pri 0; ioa2 at pri -10 cannot steal it (ALLOCFAILED) but gets channel 1 through the
        ; 2nd combination; ioa3 at pri 10 steals channel 0 (ioa1's key no longer counts there: NOALLOCATION); ioa3
        ; locks it; ioa2 at pri 20 claims it: the lock is returned ADIOERR_CHANNELSTOLEN and ioa2 waits; ioa3
        ; frees -> ioa2 is served by the retry. Stack: 3 IOAudio (72 bytes each).
        movem.l a2-a3,-(sp)
        lea     -216(sp),sp
        move.l  sp,a3
        move.l  a3,a0
        moveq   #53,d0
aut_clr:
        clr.l   (a0)+
        dbra    d0,aut_clr
        lea     audio_test_name(pc),a0
        moveq   #0,d0
        move.l  a3,a1
        moveq   #0,d1
        jsr     LVO_OPENDEVICE(a6)
        tst.b   d0
        bne     aut_fail0
        move.l  IO_DEVICE(a3),a2
        tst.w   AUT_KEY(a3)
        beq     aut_fail
        move.l  a2,IO_DEVICE+72(a3)
        move.l  a2,IO_DEVICE+144(a3)
        lea     0(a3),a1             ; ioa1: channel 0, pri 0
        lea     aut_ch0(pc),a0
        moveq   #0,d0
        bsr     aut_alloc
        bne     aut_fail
        cmp.b   #1,IO_UNIT+3(a3)
        bne     aut_fail
        lea     72(a3),a1            ; ioa2: channel 0 at pri -10 -> refused
        lea     aut_ch0(pc),a0
        moveq   #-10,d0
        bsr     aut_alloc
        cmp.b   #-11,d0
        bne     aut_fail
        lea     72(a3),a1            ; ioa2: {channel 0, channel 1} -> channel 1 (without theft)
        lea     aut_ch0or1(pc),a0
        moveq   #-10,d0
        moveq   #2,d1
        bsr     aut_allocn
        bne     aut_fail
        cmp.b   #2,IO_UNIT+3+72(a3)
        bne     aut_fail
        move.w  AUT_KEY+72(a3),d0
        cmp.w   AUT_KEY(a3),d0
        beq     aut_fail             ; distinct keys
        lea     72(a3),a1            ; ioa2 frees channel 1
        moveq   #9,d0                ; ADCMD_FREE
        bsr     aut_cmd
        bne     aut_fail
        lea     144(a3),a1           ; ioa3: channel 0 at pri 10 -> theft
        lea     aut_ch0(pc),a0
        moveq   #10,d0
        bsr     aut_alloc
        bne     aut_fail
        cmp.b   #1,IO_UNIT+3+144(a3)
        bne     aut_fail
        move.b  #1,IO_UNIT+3(a3)     ; ioa1: CMD_RESET of the stolen channel -> NOALLOCATION
        lea     0(a3),a1
        moveq   #1,d0
        bsr     aut_cmd
        cmp.b   #-10,d0
        bne     aut_fail
        lea     144(a3),a1           ; ioa3: ADCMD_LOCK (asynchronous)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        clr.b   IO_FLAGS(a1)
        move.w  #13,IO_COMMAND(a1)
        bsr     aut_io
        cmp.b   #NT_MESSAGE,LN_TYPE+144(a3)
        bne     aut_fail
        lea     72(a3),a1            ; ioa2: channel 0 at pri 20 -> lock stolen, waiting (despite NOWAIT)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        lea     aut_ch0(pc),a0
        moveq   #20,d0
        bsr     aut_alloc
        cmp.b   #NT_REPLYMSG,LN_TYPE+144(a3)
        bne     aut_fail
        cmp.b   #-12,IO_ERROR+144(a3)
        bne     aut_fail
        cmp.b   #NT_MESSAGE,LN_TYPE+72(a3)
        bne     aut_fail
        lea     144(a3),a1           ; ioa3 frees -> ioa2 served
        move.b  #1,IO_UNIT+3(a1)
        moveq   #9,d0
        bsr     aut_cmd
        bne     aut_fail
        cmp.b   #NT_REPLYMSG,LN_TYPE+72(a3)
        bne     aut_fail
        tst.b   IO_ERROR+72(a3)
        bne     aut_fail
        cmp.b   #1,IO_UNIT+3+72(a3)
        bne     aut_fail
        lea     72(a3),a1
        moveq   #9,d0
        bsr     aut_cmd
        lea     msg_audio_ok(pc),a0
        bsr     ser_puts
        bra.s   aut_close
aut_fail:
        lea     msg_audio_fail(pc),a0
        bsr     ser_puts
aut_close:
        move.l  a3,a1
        jsr     LVO_CLOSEDEVICE(a6)
        bra.s   aut_done
aut_fail0:
        lea     msg_audio_fail(pc),a0
        bsr     ser_puts
aut_done:
        lea     216(sp),sp
        movem.l (sp)+,a2-a3
        move.l  ($4).w,a6
        bra     aut_end
; subroutines (a1 = IOAudio, a2 = device) -> d0.b = io_Error, condition codes set; a6 = SysBase on exit
aut_alloc:
        moveq   #1,d1
aut_allocn:
        move.b  d0,LN_PRI(a1)
        move.l  a0,AUT_DATA(a1)
        move.l  d1,AUT_LENGTH(a1)
        moveq   #32,d0               ; ADCMD_ALLOCATE
aut_cmd:
        move.w  d0,IO_COMMAND(a1)
        move.b  #$41,IO_FLAGS(a1)    ; IOF_QUICK | ADIOF_NOWAIT
aut_io:
        move.l  a1,-(sp)
        move.l  a2,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        move.l  (sp)+,a1
        move.b  IO_ERROR(a1),d0
        rts
aut_ch0:
        dc.b    $01
aut_ch0or1:
        dc.b    $01,$02
        EVEN
aut_end:

        ; --- exec semaphores: publication (Add/Find), nested Attempt + Obtain, Release until free. In dev,
        ; the semaphore stays HELD for task_semw (blocked in Obtain) which task_semr unblocks with Release. ---
        move.l  a2,-(sp)
        moveq   #SEMT_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     semt_done
        move.l  d0,a2
        lea     semt_name(pc),a0
        move.l  a0,LN_NAME(a2)
        move.l  a2,a1
        jsr     LVO_ADDSEMAPHORE(a6)
        lea     semt_name(pc),a1
        jsr     LVO_FINDSEMAPHORE(a6)
        cmp.l   a2,d0
        bne     semt_fail
        cmp.w   #-1,SEMT_QC(a2)
        bne     semt_fail
        move.l  a2,a0
        jsr     LVO_ATTEMPTSEMAPHORE(a6)
        cmp.l   #1,d0
        bne     semt_fail
        move.l  a2,a0
        jsr     LVO_OBTAINSEMAPHORE(a6)    ; nested: does not block
        cmp.w   #2,SEMT_NEST(a2)
        bne     semt_fail
        cmp.w   #1,SEMT_QC(a2)
        bne     semt_fail
        move.l  a2,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        move.l  a2,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        cmp.w   #-1,SEMT_QC(a2)
        bne     semt_fail
        tst.w   SEMT_NEST(a2)
        bne     semt_fail
        tst.l   SEMT_OWNER(a2)
        bne     semt_fail
        lea     msg_sem_ok(pc),a0
        bsr     ser_puts
                ifeq    PROD
        move.l  a2,a0
        jsr     LVO_OBTAINSEMAPHORE(a6)    ; held for the wait proof (task_semw / task_semr)
        bra.s   semt_done
                else
        bra.s   semt_free
                endc
semt_fail:
        lea     msg_sem_fail(pc),a0
        bsr     ser_puts
semt_free:
        move.l  a2,a1
        jsr     LVO_REMSEMAPHORE(a6)
        move.l  a2,a1
        moveq   #SEMT_SIZE,d0
        jsr     LVO_FREEMEM(a6)
semt_done:
        move.l  (sp)+,a2

        ; --- graphics Regions: Or/And/ClearRect/Xor on rectangles then Or/Xor/And of regions; areas, bounds and
        ; point membership compared with a model based on pixel sets (computed outside the ROM). ---
        movem.l d2/a2-a5,-(sp)
        lea     graphics_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     rgt_done
        exg     a5,a6
        jsr     -516(a6)             ; R1 = NewRegion
        move.l  d0,a2
        jsr     -516(a6)             ; R2
        move.l  d0,a3
        jsr     -516(a6)             ; R3
        move.l  d0,a4
        move.l  a2,d0
        beq     rgt_fail
        move.l  a3,d0
        beq     rgt_fail
        move.l  a4,d0
        beq     rgt_fail
        lea     rgt_rects(pc),a1
        move.l  a2,a0
        jsr     -510(a6)             ; R1 |= (0,0,9,9)
        lea     rgt_rects+8(pc),a1
        move.l  a2,a0
        jsr     -510(a6)             ; R1 |= (5,5,14,14)
        move.l  #175,d2
        bsr     rgt_check1
        bne     rgt_fail
        lea     rgt_rects+16(pc),a1
        move.l  a2,a0
        jsr     -504(a6)             ; R1 &= (3,3,11,11)
        moveq   #73,d2
        bsr     rgt_check1
        bne     rgt_fail
        lea     rgt_rects+24(pc),a1
        move.l  a2,a0
        jsr     -522(a6)             ; R1 -= (6,6,7,7)
        moveq   #69,d2
        bsr     rgt_check1
        bne     rgt_fail
        lea     rgt_rects+32(pc),a1
        move.l  a2,a0
        jsr     -558(a6)             ; R1 ^= (10,10,21,21)
        move.l  #205,d2
        bsr     rgt_check1
        bne     rgt_fail
        cmp.l   #$00030003,(a2)      ; bounds (3,3,21,21)
        bne     rgt_fail
        cmp.l   #$00150015,4(a2)
        bne     rgt_fail
        lea     rgt_pts(pc),a1       ; points: (x, y, expected)
        moveq   #7,d2
rgt_pt:
        move.w  (a1)+,d0
        move.w  (a1)+,d1
        move.l  a2,a0
        bsr     rgt_has
        cmp.w   (a1)+,d0
        bne     rgt_fail
        dbra    d2,rgt_pt
        lea     rgt_rects+40(pc),a1
        move.l  a3,a0
        jsr     -510(a6)             ; R2 = (3,3,4,4) | (30,0,31,1)
        lea     rgt_rects+48(pc),a1
        move.l  a3,a0
        jsr     -510(a6)
        move.l  a2,a0
        move.l  a4,a1
        jsr     -612(a6)             ; R3 = R1
        move.l  a3,a0
        move.l  a4,a1
        jsr     -612(a6)             ; R3 |= R2
        move.l  a4,a0
        bsr     rgt_area
        cmp.l   #209,d0
        bne     rgt_fail
        cmp.l   #$00030000,(a4)      ; bounds (3,0,31,21)
        bne     rgt_fail
        cmp.l   #$001F0015,4(a4)
        bne     rgt_fail
        move.l  a4,a0
        jsr     -528(a6)             ; ClearRegion(R3)
        tst.l   8(a4)
        bne     rgt_fail
        move.l  a2,a0
        move.l  a4,a1
        jsr     -612(a6)             ; R3 = R1
        move.l  a3,a0
        move.l  a4,a1
        jsr     -618(a6)             ; R3 ^= R2
        move.l  a4,a0
        bsr     rgt_area
        cmp.l   #205,d0
        bne     rgt_fail
        move.l  a3,a0
        move.l  a2,a1
        jsr     -624(a6)             ; R1 &= R2
        move.l  a2,a0
        bsr     rgt_area
        cmp.l   #4,d0
        bne     rgt_fail
        cmp.l   #$00030003,(a2)
        bne     rgt_fail
        cmp.l   #$00040004,4(a2)
        bne     rgt_fail
        lea     msg_regions_ok(pc),a0
        bra.s   rgt_msg
rgt_fail:
        lea     msg_regions_fail(pc),a0
rgt_msg:
        exg     a5,a6
        bsr     ser_puts
        exg     a5,a6
        move.l  a2,a0
        jsr     -534(a6)             ; DisposeRegion (0 accepted)
        move.l  a3,a0
        jsr     -534(a6)
        move.l  a4,a0
        jsr     -534(a6)
        exg     a5,a6
        move.l  a5,a1
        jsr     LVO_CLOSELIBRARY(a6)
rgt_done:
        movem.l (sp)+,d2/a2-a5
        bra     rgt_end
; rgt_check1: area of R1 (a2) compared with d2 -> Z if equal.
rgt_check1:
        move.l  a2,a0
        bsr.s   rgt_area
        cmp.l   d2,d0
        rts
; rgt_area(a0 = region) -> d0 = sum of the areas of its rectangles.
rgt_area:
        moveq   #0,d0
        move.l  8(a0),a0
rgt_ar:
        cmpa.w  #0,a0
        beq.s   rgt_ar_r
        move.w  14(a0),d1
        sub.w   10(a0),d1
        addq.w  #1,d1
        move.w  d1,-(sp)             ; height
        move.w  12(a0),d1
        sub.w   8(a0),d1
        addq.w  #1,d1                ; width
        mulu    (sp)+,d1
        add.l   d1,d0
        move.l  (a0),a0
        bra.s   rgt_ar
rgt_ar_r:
        rts
; rgt_has(a0 = region, d0 = x, d1 = y) -> d0.w = 1 if the point is in the region, otherwise 0. Preserves a1.
rgt_has:
        sub.w   (a0),d0
        sub.w   2(a0),d1
        move.l  8(a0),a0
rgt_hl:
        cmpa.w  #0,a0
        beq.s   rgt_hno
        cmp.w   8(a0),d0
        blt.s   rgt_hn
        cmp.w   12(a0),d0
        bgt.s   rgt_hn
        cmp.w   10(a0),d1
        blt.s   rgt_hn
        cmp.w   14(a0),d1
        bgt.s   rgt_hn
        moveq   #1,d0
        rts
rgt_hn:
        move.l  (a0),a0
        bra.s   rgt_hl
rgt_hno:
        moveq   #0,d0
        rts
rgt_rects:
        dc.w    0,0,9,9, 5,5,14,14, 3,3,11,11, 6,6,7,7, 10,10,21,21, 3,3,4,4, 30,0,31,1
rgt_pts:
        dc.w    3,3,1, 6,6,0, 7,8,1, 10,10,0, 11,11,0, 12,12,1, 21,21,1, 0,0,0
rgt_end:

        ; --- fonts (graphics): OpenFont topaz 8 = default font (access counted), topaz 9 -> the nearest one (8),
        ; unknown name -> 0; InitRastPort sets the default font; TextLength (spacing included); software
        ; styles (italic refused); bold Text of "I" in a 32x8 BitMap read back: glyph | glyph >> 1. ---
FNT_RP          EQU 0                ; RastPort (100 bytes)
FNT_BM          EQU 100              ; BitMap (40)
FNT_DATA        EQU 140              ; 32x8 plane (32)
FNT_FRAME       EQU 172
        movem.l d2-d3/a2-a5,-(sp)
        lea     graphics_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     fnt_done
        exg     a5,a6                ; a6 = GfxBase, a5 = SysBase
        lea     -FNT_FRAME(sp),sp
        move.l  sp,a4
        lea     fnt_ta8(pc),a0
        jsr     -72(a6)              ; OpenFont(topaz 8)
        move.l  d0,a2
        cmp.l   154(a6),d0           ; gb_DefaultFont
        bne     fnt_fail
        tst.l   d0
        beq     fnt_fail
        move.w  30(a2),d3            ; tf_Accessors after the opening
        lea     fnt_ta9(pc),a0
        jsr     -72(a6)              ; OpenFont(topaz 9) -> topaz 8
        cmp.l   a2,d0
        bne     fnt_fail
        addq.w  #1,d3
        cmp.w   30(a2),d3
        bne     fnt_fail
        lea     fnt_tanone(pc),a0
        jsr     -72(a6)
        tst.l   d0
        bne     fnt_fail
        move.l  a2,a1
        jsr     -78(a6)              ; CloseFont x2
        move.l  a2,a1
        jsr     -78(a6)
        subq.w  #2,d3
        cmp.w   30(a2),d3
        bne     fnt_fail
        lea     FNT_RP(a4),a1
        jsr     -198(a6)             ; InitRastPort
        cmp.l   FNT_RP+52(a4),a2     ; rp_Font
        bne     fnt_fail
        cmp.l   #$00080008,FNT_RP+58(a4)   ; TxHeight, TxWidth
        bne     fnt_fail
        cmp.w   #6,FNT_RP+62(a4)     ; TxBaseline
        bne     fnt_fail
        lea     FNT_RP(a4),a1
        lea     fnt_abc(pc),a0
        moveq   #3,d0
        jsr     -54(a6)              ; TextLength("Abc") = 24
        cmp.l   #24,d0
        bne     fnt_fail
        move.w  #2,FNT_RP+64(a4)     ; TxSpacing = 2 -> 30
        lea     FNT_RP(a4),a1
        lea     fnt_abc(pc),a0
        moveq   #3,d0
        jsr     -54(a6)
        cmp.l   #30,d0
        bne     fnt_fail
        clr.w   FNT_RP+64(a4)
        lea     FNT_RP(a4),a1
        jsr     -84(a6)              ; AskSoftStyle = underlined | bold
        cmp.l   #3,d0
        bne     fnt_fail
        lea     FNT_RP(a4),a1
        moveq   #6,d0                ; bold | italic
        moveq   #-1,d1
        jsr     -90(a6)              ; SetSoftStyle -> bold only
        cmp.l   #2,d0
        bne     fnt_fail
        cmp.b   #2,FNT_RP+56(a4)     ; rp_AlgoStyle
        bne     fnt_fail
        lea     FNT_BM(a4),a0
        moveq   #1,d0
        moveq   #32,d1
        moveq   #8,d2
        jsr     -390(a6)             ; InitBitMap(1 plane, 32x8)
        lea     FNT_DATA(a4),a0
        move.l  a0,FNT_BM+8(a4)
        moveq   #7,d0
fnt_clr:
        clr.l   (a0)+
        dbra    d0,fnt_clr
        lea     FNT_BM(a4),a0
        move.l  a0,FNT_RP+4(a4)      ; rp_BitMap
        clr.b   FNT_RP+28(a4)        ; JAM1
        move.l  #$00000006,FNT_RP+36(a4)   ; cp = (0, baseline 6)
        lea     FNT_RP(a4),a1
        lea     fnt_i(pc),a0
        moveq   #1,d0
        jsr     -60(a6)              ; Text("I")
        cmp.w   #8,FNT_RP+36(a4)     ; cp_x advanced by 8
        bne     fnt_fail
        lea     font8x8+($49-$20)*8,a0
        lea     FNT_DATA(a4),a1
        moveq   #7,d2
fnt_row:
        moveq   #0,d0
        move.b  (a0)+,d0
        move.w  d0,d1
        lsl.w   #8,d1
        lsl.w   #7,d0
        or.w    d0,d1                ; bold: pixels of the glyph and their right-hand neighbours (9 pixels)
        cmp.b   1(a1),d1
        bne     fnt_fail
        lsr.w   #8,d1
        cmp.b   (a1),d1
        bne     fnt_fail
        tst.w   2(a1)
        bne     fnt_fail
        addq.l  #4,a1
        dbra    d2,fnt_row
        lea     msg_fonts_ok(pc),a0
        bra.s   fnt_msg
fnt_fail:
        lea     msg_fonts_fail(pc),a0
fnt_msg:
        exg     a5,a6
        bsr     ser_puts
        lea     FNT_FRAME(sp),sp
        move.l  a5,a1
        jsr     LVO_CLOSELIBRARY(a6)
fnt_done:
        movem.l (sp)+,d2-d3/a2-a5

        ; --- GELs (graphics): Bob 16x4x2 (OVERLAY + SAVEBACK, mask from InitMasks) placed at a non-aligned x on a
        ; colour-1 background and read back per pixel (area outside the mask transparent); collision with a VSprite
        ; (CollMask) -> routine 1; movement: original background restored, new position drawn and clipped at the
        ; edge; exit to the right of the bounds -> routine 0 (RIGHTHIT); SortGList; RemIBob restores the background. ---
GLT_GI          EQU 0
GLT_HEAD        EQU 40
GLT_TAIL        EQU 100
GLT_COLL        EQU 160
GLT_VS1         EQU 224
GLT_BOB         EQU 284
GLT_VS2         EQU 316
GLT_RP          EQU 376
GLT_BM          EQU 476
GLT_PL0         EQU 516
GLT_PL1         EQU 580
GLT_IMG         EQU 644
GLT_MASK        EQU 660
GLT_BORD        EQU 668
GLT_SAVE        EQU 670
GLT_MASK2       EQU 686
GLT_OB          EQU 696              ; AnimOb (42)
GLT_CA          EQU 740              ; AnimComp A, B (38)
GLT_CB          EQU 780
GLT_BA          EQU 820              ; their Bobs (32) and VSprites (60)
GLT_BB          EQU 852
GLT_VA          EQU 884
GLT_VB          EQU 944
GLT_KEY         EQU 1004
GLT_SIZE        EQU 1008
        movem.l d2-d3/a2-a5,-(sp)
        lea     graphics_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     glt_done
        move.l  #GLT_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a4
        tst.l   d0
        beq     glt_close
        exg     a5,a6                ; a6 = GfxBase, a5 = SysBase
        lea     GLT_IMG(a4),a0       ; image: plane 0 = $FF00, plane 1 = $F0F0 (colours 3,1,2,- per quarter)
        moveq   #3,d0
glt_img:
        move.w  #$FF00,(a0)
        move.w  #$F0F0,8(a0)
        move.w  #$FFFF,GLT_MASK2-GLT_IMG(a0)
        addq.l  #2,a0
        dbra    d0,glt_img
        lea     GLT_VS1(a4),a0
        move.w  #6,20(a0)            ; SAVEBACK | OVERLAY
        move.l  #$00020003,22(a0)    ; Y = 2, X = 3
        move.l  #$00040001,26(a0)    ; Height 4, Width 1 word
        move.w  #2,30(a0)            ; Depth
        move.l  #$00020003,32(a0)    ; MeMask = 2, HitMask = 3 (border + type 1)
        lea     GLT_IMG(a4),a1
        move.l  a1,36(a0)
        lea     GLT_BORD(a4),a1
        move.l  a1,40(a0)
        lea     GLT_MASK(a4),a1
        move.l  a1,44(a0)
        lea     GLT_BOB(a4),a1
        move.l  a1,52(a0)
        move.b  #3,56(a0)            ; PlanePick
        move.l  a0,18(a1)            ; bob->BobVSprite
        lea     GLT_SAVE(a4),a0
        move.l  a0,2(a1)             ; SaveBuffer
        lea     GLT_MASK(a4),a0
        move.l  a0,6(a1)             ; ImageShadow
        lea     GLT_VS2(a4),a0
        move.w  #1,20(a0)            ; VSPRITE
        move.l  #$00040008,22(a0)    ; Y = 4, X = 8
        move.l  #$00040001,26(a0)
        move.l  #$00020002,32(a0)
        lea     GLT_MASK2(a4),a1
        move.l  a1,44(a0)
        lea     GLT_GI(a4),a0
        lea     GLT_COLL(a4),a1
        move.l  a1,18(a0)            ; collHandler
        move.l  #$0000001F,22(a0)    ; leftmost 0, rightmost 31
        move.l  #$0000000F,26(a0)    ; topmost 0, bottommost 15
        lea     GLT_BM(a4),a0
        moveq   #2,d0
        moveq   #32,d1
        moveq   #16,d2
        jsr     -390(a6)             ; InitBitMap
        lea     GLT_PL0(a4),a0
        move.l  a0,GLT_BM+8(a4)
        lea     GLT_PL1(a4),a0
        move.l  a0,GLT_BM+12(a4)
        lea     GLT_RP(a4),a1
        jsr     -198(a6)             ; InitRastPort
        lea     GLT_BM(a4),a0
        move.l  a0,GLT_RP+4(a4)
        lea     GLT_GI(a4),a0
        move.l  a0,GLT_RP+20(a4)     ; rp_GelsInfo
        lea     GLT_RP(a4),a1
        moveq   #1,d0
        jsr     -234(a6)             ; SetRast(1)
        lea     GLT_HEAD(a4),a0
        lea     GLT_TAIL(a4),a1
        lea     GLT_GI(a4),a2
        jsr     -120(a6)             ; InitGels
        lea     GLT_VS1(a4),a0
        jsr     -126(a6)             ; InitMasks
        cmp.l   #$FFF0FFF0,GLT_MASK(a4)
        bne     glt_fail
        cmp.w   #$FFF0,GLT_BORD(a4)
        bne     glt_fail
        moveq   #0,d0
        lea     glt_coll0(pc),a0
        lea     GLT_GI(a4),a1
        jsr     -144(a6)             ; SetCollision(0)
        moveq   #1,d0
        lea     glt_coll1(pc),a0
        lea     GLT_GI(a4),a1
        jsr     -144(a6)             ; SetCollision(1)
        lea     GLT_BOB(a4),a0
        lea     GLT_RP(a4),a1
        jsr     -96(a6)              ; AddBob
        lea     GLT_RP(a4),a1
        suba.l  a0,a0
        jsr     -114(a6)             ; DrawGList
        lea     glt_px1(pc),a2
        bsr     glt_check
        bne     glt_fail
        lea     GLT_VS2(a4),a0
        lea     GLT_RP(a4),a1
        jsr     -102(a6)             ; AddVSprite
        lea     GLT_RP(a4),a1
        jsr     -108(a6)             ; DoCollision: Bob x VSprite -> routine 1
        cmp.w   #1,GLT_VS1+58(a4)
        bne     glt_fail
        cmp.w   #1,GLT_VS2+58(a4)
        bne     glt_fail
        move.l  #$00080014,GLT_VS1+22(a4)   ; Y = 8, X = 20
        lea     GLT_RP(a4),a1
        jsr     -150(a6)             ; SortGList: VSprite (Y 4) then Bob (Y 8)
        lea     GLT_VS2(a4),a0
        cmp.l   GLT_HEAD(a4),a0
        bne     glt_fail
        lea     GLT_RP(a4),a1
        suba.l  a0,a0
        jsr     -114(a6)             ; DrawGList
        lea     glt_px2(pc),a2
        bsr     glt_check
        bne     glt_fail
        lea     GLT_RP(a4),a1
        jsr     -108(a6)             ; DoCollision: right border -> routine 0
        cmp.w   #8,GLT_VS1+58(a4)    ; RIGHTHIT
        bne     glt_fail
        cmp.w   #1,GLT_VS2+58(a4)    ; no more overlap
        bne     glt_fail
        lea     GLT_BOB(a4),a0
        lea     GLT_RP(a4),a1
        suba.l  a2,a2
        jsr     -132(a6)             ; RemIBob
        lea     glt_px3(pc),a2
        bsr     glt_check
        bne     glt_fail
        btst    #3,GLT_BOB(a4)       ; BOBNIX
        beq     glt_fail
        lea     GLT_VS2(a4),a0
        cmp.l   GLT_HEAD(a4),a0      ; head->Next = VSprite
        bne     glt_fail
        ; animation: components A and B in a ring (TimeSet 2), object at (5, 7) + 1 pixel/call in X (6-bit fraction)
        lea     GLT_OB(a4),a0
        move.l  #(5<<6)<<16|(7<<6),16(a0)  ; AnY, AnX
        move.w  #1<<6,22(a0)         ; XVel
        lea     GLT_CA(a4),a1
        move.l  a1,36(a0)            ; HeadComp = A
        lea     GLT_CB(a4),a2
        move.w  #2,4(a1)
        move.w  #2,4(a2)
        move.l  a2,14(a1)            ; A.NextSeq = B
        move.l  a1,14(a2)            ; B.NextSeq = A
        move.l  #$00010002,26(a1)    ; A: YTrans 1, XTrans 2
        lea     GLT_BA(a4),a0
        move.l  a0,34(a1)
        lea     GLT_VA(a4),a1
        move.l  a1,18(a0)
        lea     GLT_BB(a4),a0
        move.l  a0,34(a2)
        lea     GLT_VB(a4),a1
        move.l  a1,18(a0)
        lea     GLT_IMG(a4),a2
        lea     GLT_VA(a4),a0
        move.l  #$00010001,26(a0)    ; 1 line, 1 word, depth 1
        move.w  #1,30(a0)
        move.l  a2,36(a0)
        move.l  #$00010001,26(a1)
        move.w  #1,30(a1)
        move.l  a2,36(a1)
        lea     GLT_OB(a4),a0
        lea     GLT_RP(a4),a1
        moveq   #0,d0
        jsr     -168(a6)             ; GetGBuffers
        tst.w   d0
        beq     glt_fail
        tst.l   GLT_BA+2(a4)         ; SaveBuffer
        beq     glt_fail
        tst.l   GLT_VB+44(a4)        ; CollMask of B
        beq     glt_fail
        lea     GLT_OB(a4),a0
        jsr     -174(a6)             ; InitGMasks
        move.l  GLT_VB+44(a4),a0
        cmp.w   #$FF00,(a0)
        bne     glt_fail
        lea     GLT_OB(a4),a0
        lea     GLT_KEY(a4),a1
        lea     GLT_RP(a4),a2
        jsr     -156(a6)             ; AddAnimOb
        lea     GLT_OB(a4),a0
        cmp.l   GLT_KEY(a4),a0
        bne     glt_fail
        cmp.l   #$00060009,GLT_VA+22(a4)   ; (5 + 1, 7 + 2)
        bne     glt_fail
        bsr     glt_anim
        cmp.w   #10,GLT_VA+24(a4)
        bne     glt_fail
        cmp.w   #1,GLT_CA+2(a4)      ; Timer
        bne     glt_fail
        bsr     glt_anim             ; timer at 0: B replaces A
        lea     GLT_CB(a4),a0
        cmp.l   GLT_OB+36(a4),a0
        bne     glt_fail
        btst    #2,GLT_BA(a4)        ; BOBSAWAY
        beq     glt_fail
        cmp.l   #$00050009,GLT_VB+22(a4)
        bne     glt_fail
        cmp.w   #2,GLT_CB+2(a4)
        bne     glt_fail
        cmp.l   #2,GLT_OB+8(a4)      ; Clock
        bne     glt_fail
        lea     GLT_RP(a4),a1
        suba.l  a0,a0
        jsr     -114(a6)             ; DrawGList: A removed (BOBNIX)
        btst    #3,GLT_BA(a4)
        beq     glt_fail
        lea     GLT_OB(a4),a0
        lea     GLT_RP(a4),a1
        moveq   #0,d0
        jsr     -600(a6)             ; FreeGBuffers
        tst.l   GLT_BA+2(a4)
        bne     glt_fail
        tst.l   GLT_VB+44(a4)
        bne     glt_fail
        lea     msg_gels_ok(pc),a0
        bra.s   glt_msg
glt_fail:
        lea     msg_gels_fail(pc),a0
glt_msg:
        exg     a5,a6
        bsr     ser_puts
        move.l  a4,a1
        move.l  #GLT_SIZE,d0
        jsr     LVO_FREEMEM(a6)
glt_close:
        move.l  a5,a1
        jsr     LVO_CLOSELIBRARY(a6)
glt_done:
        movem.l (sp)+,d2-d3/a2-a5
        bra     glt_end
glt_anim:
        lea     GLT_KEY(a4),a0
        lea     GLT_RP(a4),a1
        jmp     -162(a6)             ; Animate
; glt_check(a2 = table (x, y, expected)... terminated by -1, a4, a6 = GfxBase): Z = 1 if every ReadPixel matches.
glt_check:
        move.w  (a2)+,d0
        bmi.s   glt_ck_ok
        move.w  (a2)+,d1
        lea     GLT_RP(a4),a1
        jsr     -318(a6)             ; ReadPixel
        cmp.w   (a2)+,d0
        beq.s   glt_check
        rts
glt_ck_ok:
        moveq   #0,d0
        rts
; collision routines (C convention): count in VUserExt (offset 58) of each gel; borders: flags.
glt_coll1:
        move.l  4(sp),a0
        addq.w  #1,58(a0)
        move.l  8(sp),a0
        addq.w  #1,58(a0)
        rts
glt_coll0:
        move.l  4(sp),a0
        move.w  10(sp),58(a0)
        rts
glt_px1:                             ; Bob at (3, 2): 3,3 | 1 | 2 | transparent; background 1 around
        dc.w    3,2,3, 6,2,3, 7,2,1, 10,2,1, 11,2,2, 14,2,2, 15,2,1, 18,2,1
        dc.w    5,1,1, 5,5,3, 5,6,1, 2,3,1, -1
glt_px2:                             ; old location restored; Bob at (20, 8), clipped at x = 31
        dc.w    3,2,1, 7,2,1, 11,2,1, 6,5,1
        dc.w    20,8,3, 23,8,3, 24,8,1, 27,8,1, 28,8,2, 31,8,2, 20,11,3, 20,12,1, 19,8,1, -1
glt_px3:                             ; RemIBob: background restored
        dc.w    20,8,1, 24,8,1, 28,8,1, 31,11,1, -1
glt_end:

        ; --- layers.library: a SIMPLE layer (L1) and a SMART one (L2) on an off-screen 64x32x2 BitMap. Drawing,
        ; BehindLayer (simple area uncovered again: cleared + damage; hidden smart area: saved), drawing in the
        ; hidden part of L2 (read by ReadPixel), BeginUpdate/EndUpdate of L1, UpfrontLayer (restoration), MoveLayer,
        ; SizeLayer of L2 (smart enlargement: damage), DeleteLayer (background and layer below), SizeLayer of L1,
        ; WhichLayer. Expected: pixel-level Python model. ---
        movem.l d2-d7/a2-a5,-(sp)
        lea     -16(sp),sp
        move.l  sp,a5                ; 0 BitMap, 4 L1, 8 L2, 12 Layer_Info
        clr.l   (a5)
        clr.l   4(a5)
        clr.l   8(a5)
        clr.l   12(a5)
        lea     graphics_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a2                ; a2 = GfxBase
        lea     layers_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a3                ; a3 = LayersBase
        move.l  a2,d0
        beq     lyt_fail0
        move.l  a3,d0
        beq     lyt_fail0
        move.l  #40+512,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,(a5)
        beq     lyt_fail0
        move.l  d0,a0
        moveq   #2,d0
        moveq   #64,d1
        moveq   #32,d2
        exg     a2,a6
        jsr     -390(a6)             ; InitBitMap(bm, 2, 64, 32)
        exg     a2,a6
        move.l  (a5),a0
        lea     40(a0),a1
        move.l  a1,8(a0)             ; planes
        lea     256(a1),a1
        move.l  a1,12(a0)
        exg     a3,a6
        jsr     -144(a6)             ; NewLayerInfo
        exg     a3,a6
        move.l  d0,12(a5)
        beq     lyt_fail
        moveq   #0,d0                ; L1 = simple (0,0)-(31,15)
        moveq   #0,d1
        moveq   #31,d2
        moveq   #15,d3
        moveq   #1,d4
        bsr     lyt_create
        move.l  d0,4(a5)
        beq     lyt_fail
        moveq   #1,d0
        bsr     lyt_setrast1
        moveq   #16,d0               ; L2 = smart (16,8)-(47,23)
        moveq   #8,d1
        moveq   #47,d2
        moveq   #23,d3
        moveq   #2,d4
        bsr     lyt_create
        move.l  d0,8(a5)
        beq     lyt_fail
        move.l  8(a5),a1
        move.l  12(a1),a1
        moveq   #2,d0
        exg     a2,a6
        jsr     -234(a6)             ; SetRast(L2, 2)
        exg     a2,a6
        LYT_PIX 20,10,2
        LYT_PIX 5,5,1
        LYT_PIX 40,20,2
        LYT_PIX 50,5,0
        move.l  4(a5),a1             ; L1: RectFill 3 over the whole layer (only its visible part changes)
        moveq   #3,d0
        bsr     lyt_fill
        LYT_PIX 20,10,2
        LYT_PIX 5,5,3
        move.l  8(a5),a1
        moveq   #-54,d7              ; BehindLayer(L2)
        bsr     lyt_lcall
        LYT_PIX 20,10,0
        LYT_PIX 5,5,3
        LYT_PIX 40,20,2
        move.l  4(a5),a0
        btst    #7,31(a0)            ; L1: LAYERREFRESH
        beq     lyt_fail
        LYT_RPIX 4,2,2
        move.l  8(a5),a1             ; drawing in the hidden part of L2: (0,0)-(7,3) with pen 1
        moveq   #1,d0
        moveq   #0,d4
        moveq   #0,d5
        moveq   #7,d6
        moveq   #3,d7
        bsr     lyt_rect
        LYT_PIX 20,10,0
        LYT_RPIX 4,2,1
        move.l  4(a5),a0             ; BeginUpdate(L1) + RectFill 3 + EndUpdate(L1, TRUE)
        exg     a3,a6
        jsr     -78(a6)
        exg     a3,a6
        move.l  4(a5),a1
        moveq   #3,d0
        bsr     lyt_fill
        move.l  4(a5),a0
        moveq   #1,d0
        exg     a3,a6
        jsr     -84(a6)
        exg     a3,a6
        LYT_PIX 20,10,3
        LYT_PIX 5,5,3
        move.l  4(a5),a0
        btst    #7,31(a0)
        bne     lyt_fail
        move.l  8(a5),a1
        moveq   #-48,d7              ; UpfrontLayer(L2): contents restored from the backup
        bsr     lyt_lcall
        LYT_PIX 20,10,1
        LYT_PIX 30,14,2
        LYT_PIX 5,5,3
        move.l  8(a5),a1             ; MoveLayer(L2, +8, +4)
        moveq   #8,d0
        moveq   #4,d1
        moveq   #-60,d7
        bsr     lyt_lcall
        LYT_PIX 28,14,1
        LYT_PIX 17,9,0
        LYT_PIX 20,10,0
        LYT_PIX 50,26,2
        move.l  8(a5),a1             ; SizeLayer(L2 smart, +4, +2): contents kept, enlarged part at 0 and damaged
        moveq   #4,d0
        moveq   #2,d1
        moveq   #-66,d7
        bsr     lyt_lcall
        LYT_PIX 50,26,2
        LYT_PIX 57,28,0
        move.l  8(a5),a0
        btst    #7,31(a0)
        beq     lyt_fail
        move.l  4(a5),a0
        btst    #7,31(a0)
        beq     lyt_fail
        bsr     lyt_clrdmg
        move.l  8(a5),a1             ; DeleteLayer(L2)
        moveq   #-90,d7
        bsr     lyt_lcall
        clr.l   8(a5)
        LYT_PIX 28,14,0
        LYT_PIX 50,20,0
        LYT_PIX 5,5,3
        move.l  4(a5),a0
        btst    #7,31(a0)
        beq     lyt_fail
        bsr     lyt_clrdmg
        move.l  4(a5),a1             ; SizeLayer(L1, +8, +4)
        moveq   #8,d0
        moveq   #4,d1
        moveq   #-66,d7
        bsr     lyt_lcall
        LYT_PIX 35,17,0
        LYT_PIX 5,5,3
        move.l  4(a5),a0
        btst    #7,31(a0)
        beq     lyt_fail
        move.l  12(a5),a0            ; WhichLayer
        moveq   #5,d0
        moveq   #5,d1
        exg     a3,a6
        jsr     -132(a6)
        exg     a3,a6
        cmp.l   4(a5),d0
        bne     lyt_fail
        move.l  12(a5),a0
        moveq   #60,d0
        moveq   #30,d1
        exg     a3,a6
        jsr     -132(a6)
        exg     a3,a6
        tst.l   d0
        bne     lyt_fail
        lea     msg_layers_ok(pc),a0
        bra.s   lyt_msg
lyt_fail:
        lea     msg_layers_fail(pc),a0
lyt_msg:
        bsr     ser_puts
        moveq   #8,d6                ; remaining layers deleted, then Layer_Info and BitMap returned
lyt_del:
        move.l  0(a5,d6.w),d0
        beq.s   lyt_deln
        move.l  d0,a1
        moveq   #-90,d7
        bsr     lyt_lcall
lyt_deln:
        subq.w  #4,d6
        bne.s   lyt_del
        move.l  12(a5),d0
        beq.s   lyt_nli
        move.l  d0,a0
        exg     a3,a6
        jsr     -150(a6)             ; DisposeLayerInfo
        exg     a3,a6
lyt_nli:
        move.l  (a5),a1
        move.l  #40+512,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   lyt_close
lyt_fail0:
        lea     msg_layers_fail(pc),a0
        bsr     ser_puts
lyt_close:
        move.l  a2,a1
        jsr     LVO_CLOSELIBRARY(a6)
        move.l  a3,a1
        jsr     LVO_CLOSELIBRARY(a6)
        lea     16(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        bra     lyt_end
; subroutines of the layers probe (a2 = GfxBase, a3 = LayersBase, a5 = frame, a6 = SysBase)
lyt_create:                          ; CreateUpfrontLayer(li, bm, d0..d3, flags d4) -> d0
        move.l  12(a5),a0
        move.l  (a5),a1
        movem.l a2,-(sp)
        suba.l  a2,a2
        exg     a3,a6
        jsr     -36(a6)
        exg     a3,a6
        movem.l (sp)+,a2
        rts
lyt_setrast1:                        ; SetRast(L1, d0)
        move.l  4(a5),a1
        move.l  12(a1),a1
        exg     a2,a6
        jsr     -234(a6)
        exg     a2,a6
        rts
lyt_fill:                            ; a1 = layer, d0 = pen: RectFill of the whole initial layer (0,0)-(31,15)
        moveq   #0,d4
        moveq   #0,d5
        moveq   #31,d6
        moveq   #15,d7
lyt_rect:                            ; a1 = layer, d0 = pen, d4..d7 = relative rectangle
        move.l  12(a1),a1
        exg     a2,a6
        jsr     -342(a6)             ; SetAPen
        move.w  d4,d0
        move.w  d5,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     -306(a6)             ; RectFill
        exg     a2,a6
        rts
lyt_lcall:                           ; layers(dummy a0, layer a1, d0, d1) at LVO d7
        suba.l  a0,a0
        exg     a3,a6
        jsr     0(a6,d7.w)
        exg     a3,a6
        rts
lyt_clrdmg:                          ; damage of L1 cleared (BeginUpdate + EndUpdate TRUE)
        move.l  4(a5),a0
        exg     a3,a6
        jsr     -78(a6)
        move.l  4(a5),a0
        moveq   #1,d0
        jsr     -84(a6)
        exg     a3,a6
        rts
; lyt_px(d0 = x, d1 = y) -> d0 = colour read directly from the two planes of the BitMap; d2 = expected -> Z if equal.
lyt_px:
        move.l  (a5),a0
        lsl.w   #3,d1                ; 8 bytes per line
        move.w  d0,d3
        lsr.w   #3,d3
        add.w   d3,d1
        not.w   d0
        and.w   #7,d0
        moveq   #0,d3
        move.l  12(a0),a1
        btst    d0,0(a1,d1.w)
        beq.s   lyt_p1
        moveq   #2,d3
lyt_p1:
        move.l  8(a0),a1
        btst    d0,0(a1,d1.w)
        beq.s   lyt_p2
        addq.w  #1,d3
lyt_p2:
        cmp.w   d2,d3
        rts
; lyt_rpx(d0 = x, d1 = y relative to L2): ReadPixel(L2) compared with d2.
lyt_rpx:
        move.l  8(a5),a1
        move.l  12(a1),a1
        exg     a2,a6
        jsr     -318(a6)
        exg     a2,a6
        cmp.w   d2,d0
        rts
lyt_end:

        ; --- M6t: check trackdisk.device (resident skeleton + unit validation) ---
        ; FindName(DeviceList) + version 34 + NT_DEVICE + Open(unit 0) OK (OpenCnt==1, io_Error==0, io_Unit ==
        ; base+LIB_SIZE = EXACT area of unit 0, io_Device==base) + Open(unit 4) FAILS (io_Error!=0,
        ; io_Device==0, OpenCnt unchanged). RED TD_NO_UNITCHECK: unit 4 wrongly opens -> M6T absent. a6=ExecBase.
        lea     EB_DEVICELIST(a6),a0
        lea     trackdisk_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m6t_done
        move.l  d0,a2                ; a2 = TDBase
        cmp.w   #34,LIB_VERSION(a2)
        bne     m6t_done
        cmp.b   #NT_DEVICE,LN_TYPE(a2)
        bne     m6t_done
        lea     -32(sp),sp           ; IORequest on the stack (IO_SIZE=32), zeroed
        move.l  sp,a3                ; a3 = ioreq
        moveq   #(32/4)-1,d0
        move.l  a3,a0
.m6t_clr:
        clr.l   (a0)+
        dbf     d0,.m6t_clr
        move.l  a6,-(sp)             ; Open(unit 0) via vector -6 (a6=dev, a1=ioreq, d0=unit, d1=flags)
        move.l  a2,a6
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        jsr     -6(a6)               ; trackdisk Open (LVO -6, literal: boot.s only includes exec.i)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)   ; OpenCnt==1?
        bne.s   m6t_pop
        tst.b   IO_ERROR(a3)         ; io_Error==0?
        bne.s   m6t_pop
        move.l  IO_DEVICE(a3),d0     ; io_Device==TDBase?
        cmp.l   a2,d0
        bne.s   m6t_pop
        lea     LIB_SIZE(a2),a0      ; expected io_Unit = base + TDU_UNIT0 (TDU_UNIT0 = LIB_SIZE = 34)
        cmp.l   IO_UNIT(a3),a0       ; io_Unit == base+TDU_UNIT0? (proves the base offset + io_Unit set; the per-unit
        bne.s   m6t_pop              ;   stride is a placeholder, proven again when the units become real in B2)
        move.l  a6,-(sp)             ; Open(unit 4) -> must FAIL
        move.l  a2,a6
        move.l  a3,a1
        moveq   #4,d0
        moveq   #0,d1
        jsr     -6(a6)
        move.l  (sp)+,a6
        tst.b   IO_ERROR(a3)         ; io_Error != 0 (failure)?
        beq.s   m6t_pop              ; RED TD_NO_UNITCHECK: io_Error==0 -> wrongly opens -> M6T absent
        move.l  IO_DEVICE(a3),d0     ; io_Device == 0 (OpenDevice failure)?
        bne.s   m6t_pop
        cmp.w   #1,LIB_OPENCNT(a2)   ; OpenCnt still 1 (unit 4 did not count)?
        bne.s   m6t_pop
        lea     32(sp),sp            ; free the IORequest (success)
        lea     msg_m6t_ok(pc),a0
        bsr     ser_puts             ; "M6T TRACKDISK OK"
        bra.s   m6t_done
m6t_pop:
        lea     32(sp),sp            ; free the IORequest (failure)
m6t_done:

        ; --- M6u/M6v: raw read (B2) + MFM decoding (B3) — A SINGLE read of DF0 ---
        ; td_read_track0 reads the raw track; M6U counts the $4489 sync words (impossible in normal MFM -> 0
        ; false positives), M6V decodes the sectors (combine odd/even) + checks the header AND data checksums. A
        ; single read for both (a 2nd timeout without a disk would shift the M7A proof). Without a disk -> nothing,
        ; without FAILED.
        moveq   #0,d4                ; d4 = "disk present" flag (M6W gate: avoids a 2nd timeout without a disk)
        bsr     td_read_track0
        tst.l   d0
        beq     m6uv_done
        moveq   #1,d4                ; disk present
        move.l  d0,a4                ; a4 = chip rawbuf (raw track; preserved until the FreeMem)
        ; M6U: count the sync words
        move.l  a4,a0
        move.l  #$1900-1,d2          ; TD_RAWWORDS-1 (disk.i): 6399 < 65535 -> dbra OK
        moveq   #0,d3
.m6u_scan:
        cmp.w   #$4489,(a0)+         ; TD_SYNC (disk.i)
        bne.s   .m6u_next
        addq.l  #1,d3
.m6u_next:
        dbra    d2,.m6u_scan
        lea     msg_m6u_syncs(pc),a0
        bsr     ser_puts             ; "M6U SYNCS="
        move.w  d3,d0
        bsr     ser_puthex
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        cmp.l   #5,d3                ; threshold: at least 5 syncs (a formatted track has ~22)
        blt.s   .m6v_decode
        lea     msg_m6u_ok(pc),a0
        bsr     ser_puts             ; "M6U TRACKDISK READ OK"
.m6v_decode:
        ; M6V: decode the track into 512-byte sectors + check the checksums
        move.l  #512*11,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .m6uv_freeraw        ; no RAM -> just free rawbuf
        move.l  d0,a3                ; a3 = sectorbuf
        move.l  a4,a0
        move.l  a3,a1
        jsr     td_decode_track      ; d0 = number of sectors decoded+verified
        move.l  d0,d5
        lea     msg_m6v_sect(pc),a0
        bsr     ser_puts             ; "M6V SECTORS="
        move.w  d5,d0
        bsr     ser_puthex
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        cmp.l   #11,d5               ; 11 valid sectors?
        bne.s   .m6v_free
        cmp.l   #$444F5300,(a3)      ; decoded sector 0 == "DOS\0" (OFS bootblock)?
        bne.s   .m6v_free
        lea     msg_m6v_ok(pc),a0
        bsr     ser_puts             ; "M6V TRACKDISK DECODE OK"
.m6v_free:
        move.l  a3,a1                ; free sectorbuf
        move.l  #512*11,d0
        jsr     LVO_FREEMEM(a6)
.m6uv_freeraw:
        move.l  a4,a1                ; free rawbuf (TD_RAWBYTES = $1900*2)
        move.l  #$1900*2,d0
        jsr     LVO_FREEMEM(a6)
m6uv_done:

        ; --- M6w: trackdisk CMD_READ (B4) — ONLY if disk present (d4=1; avoids a 2nd timeout without a disk) ---
        ; Sets up an IOStdReq (CMD_READ, offset 0, length 512, IOF_QUICK), calls BeginIO via vector -30, checks
        ; io_Error==0 + io_Actual==512 + sector read == "DOS\0". RED TD_READ_NOCMD -> io_Data stays empty -> absent.
        tst.l   d4
        beq     m6w_done
        lea     EB_DEVICELIST(a6),a0
        lea     trackdisk_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m6w_done
        move.l  d0,a2                ; a2 = trackdisk base
        move.l  #48+512,d0           ; IOStdReq (48) + databuf (512)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   m6w_done
        move.l  d0,a3                ; a3 = ioreq
        move.l  a2,IO_DEVICE(a3)     ; io_Device = trackdisk
        move.w  #2,IO_COMMAND(a3)    ; CMD_READ (= 2)
        move.l  #512,36(a3)          ; IO_LENGTH (offset 36) = 512
        lea     48(a3),a0
        move.l  a0,40(a3)            ; IO_DATA (offset 40) = databuf (ioreq+48)
        clr.l   44(a3)               ; IO_OFFSET (offset 44) = 0 (logical sector 0)
        move.b  #1,IO_FLAGS(a3)      ; IOF_QUICK -> BeginIO does not ReplyMsg
        move.l  a6,-(sp)             ; BeginIO via vector -30 (a6 = trackdisk, a1 = ioreq)
        move.l  a2,a6
        move.l  a3,a1
        jsr     -30(a6)
        move.l  (sp)+,a6
        tst.b   IO_ERROR(a3)         ; io_Error == 0?
        bne.s   .m6w_free
        cmp.l   #512,32(a3)          ; IO_ACTUAL (offset 32) == 512 bytes transferred?
        bne.s   .m6w_free
        lea     48(a3),a0            ; databuf
        cmp.l   #$444F5300,(a0)      ; sector 0 read == "DOS\0" (bootblock)?
        bne.s   .m6w_free
        lea     msg_m6w_ok(pc),a0
        bsr     ser_puts             ; "M6W TRACKDISK CMD_READ OK"
.m6w_free:
        move.l  a3,a1
        move.l  #48+512,d0
        jsr     LVO_FREEMEM(a6)
m6w_done:

        ; --- M6x: trackdisk SEEK + side-select (B2b) — read TRACK 2 (cylinder 1, side 0) ---
        ; td_read_track(2) seeks to cylinder 1 + side 0; td_decode_track returns d1 = track number of the sectors.
        ; Success = 11 valid sectors AND track == 2 (proves the seek AND the side: a wrong side would read track 3).
        ; Gated on d4 (disk present): no 2nd timeout without a disk. RED SEEK_NOSTEP -> stays on track 0 -> absent.
        tst.l   d4
        beq     m6x_done
        moveq   #2,d0
        bsr     td_read_track        ; d0 = rawbuf (track 2) | 0
        tst.l   d0
        beq     m6x_done
        move.l  d0,a4                ; a4 = rawbuf
        move.l  #512*11,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .m6x_freeraw
        move.l  d0,a3                ; a3 = sectorbuf
        move.l  a4,a0
        move.l  a3,a1
        jsr     td_decode_track      ; d0 = number of valid sectors, d1 = track number read
        move.l  d1,d5                ; d5 = track read (saved before d1 is clobbered)
        move.l  d0,d2                ; d2 = count (saved: ser_puthex clobbers d0-d3)
        lea     msg_m6x_track(pc),a0
        bsr     ser_puts             ; "M6X TRACK=" (diagnostic: track actually reached by the seek)
        move.w  d5,d0
        bsr     ser_puthex
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        cmp.l   #11,d2               ; 11 valid sectors?
        bne.s   .m6x_free
        cmp.l   #2,d5                ; track read == 2 (seek + side correct)?
        bne.s   .m6x_free
        lea     msg_m6x_ok(pc),a0
        bsr     ser_puts             ; "M6X TRACKDISK SEEK OK"
.m6x_free:
        move.l  a3,a1
        move.l  #512*11,d0
        jsr     LVO_FREEMEM(a6)
.m6x_freeraw:
        move.l  a4,a1
        move.l  #$1900*2,d0
        jsr     LVO_FREEMEM(a6)
m6x_done:

        ; --- M6z: MULTI-TRACK CMD_READ (prerequisite for D) — ONLY if disk present (d4=1) ---
        ; Two reads via BeginIO (the real device path that dos will call) prove the offset->track mapping:
        ;  (1) root block @ block 880 = track 80 (cyl 40) -> primary type +0 == 2 (T_SHORT) AND secondary type
        ;      +508 == 1 (ST_ROOT). A wrong mapping would return track 0 (bootblock "DOS\0") -> fails.
        ;  (2) SPANNING read: offset 10*512, length 1024 = blocks 10+11 -> CROSSES the track 0/1 boundary.
        ;      Block 10 (track 0, sector 10) carries "SPAN0010", block 11 (track 1, sector 0) "SPAN0011"
        ;      (set by patch_bootblock.py). Both markers present <=> the loop read TWO tracks and
        ;      assembled them. RED TD_NOSEEK (always reads track 0) -> both checks fail -> M6Z absent.
        tst.l   d4
        beq     m6z_done
        lea     EB_DEVICELIST(a6),a0
        lea     trackdisk_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m6z_done
        move.l  d0,a2                ; a2 = trackdisk base
        move.l  #48+1024,d0          ; IOStdReq (48) + databuf (1024 = spanning read of 2 blocks)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m6z_done
        move.l  d0,a3                ; a3 = ioreq; databuf = a3+48
        move.l  a2,IO_DEVICE(a3)
        move.w  #2,IO_COMMAND(a3)    ; CMD_READ
        ; (1) root block @ block 880 (track 80)
        move.l  #512,36(a3)          ; IO_LENGTH = 512
        lea     48(a3),a0
        move.l  a0,40(a3)            ; IO_DATA = databuf
        move.l  #880*512,44(a3)      ; IO_OFFSET = block 880 (track 80, cyl 40)
        move.b  #1,IO_FLAGS(a3)      ; IOF_QUICK
        move.l  a6,-(sp)             ; BeginIO via vector -30
        move.l  a2,a6
        move.l  a3,a1
        jsr     -30(a6)
        move.l  (sp)+,a6
        tst.b   IO_ERROR(a3)
        bne     .m6z_free
        cmp.l   #512,32(a3)          ; io_Actual == 512?
        bne     .m6z_free
        lea     48(a3),a0            ; databuf = root block
        cmp.l   #2,(a0)              ; +0 == T_SHORT (0x00000002)?
        bne.s   .m6z_free
        cmp.l   #1,508(a0)           ; +508 == ST_ROOT (0x00000001)?
        bne.s   .m6z_free
        ; (2) spanning read track 0/1: blocks 10+11 (offset 10*512, length 1024)
        move.l  #1024,36(a3)         ; IO_LENGTH = 1024
        lea     48(a3),a0
        move.l  a0,40(a3)            ; IO_DATA = databuf
        move.l  #10*512,44(a3)       ; IO_OFFSET = block 10 (last sector of track 0)
        move.b  #1,IO_FLAGS(a3)      ; IOF_QUICK
        move.l  a6,-(sp)
        move.l  a2,a6
        move.l  a3,a1
        jsr     -30(a6)
        move.l  (sp)+,a6
        tst.b   IO_ERROR(a3)
        bne.s   .m6z_free
        cmp.l   #1024,32(a3)         ; io_Actual == 1024?
        bne.s   .m6z_free
        lea     48(a3),a0           ; databuf: [0..511]=block 10 (track 0), [512..1023]=block 11 (track 1)
        cmp.l   #$5350414E,(a0)      ; block 10 "SPAN"?
        bne.s   .m6z_free
        cmp.l   #$30303130,4(a0)     ; block 10 "0010"?
        bne.s   .m6z_free
        cmp.l   #$5350414E,512(a0)   ; block 11 "SPAN" (track 1)?
        bne.s   .m6z_free
        cmp.l   #$30303131,516(a0)   ; block 11 "0011"?
        bne.s   .m6z_free
        lea     msg_m6z_ok(pc),a0
        bsr     ser_puts             ; "M6Z TRACKDISK CMD_READ MULTI-TRACK OK"
.m6z_free:
        move.l  a3,a1
        move.l  #48+1024,d0
        jsr     LVO_FREEMEM(a6)
m6z_done:

        ; --- D1: read-only OFS — read the file "KickSlop" of DF0: BY NAME (gated on disk d4) ---
        ; ofs_read_file walks the OFS filesystem (root 880 -> hash -> header via hash chain -> chain of
        ; data blocks) relying on trackdisk CMD_READ (M6z). Proof: returned size == 1024 (RED
        ; OFS_NO_DATACHAIN -> 488) AND markers at the OFS data block boundaries: @0 "D1OFSOK0", @488
        ; "D1OFSOK1" (2nd block, 488 bytes/OFS block), @976 "D1OFSOK2" (3rd block). Proves found-BY-NAME — request
        ; "kickslop" vs stored "KickSlop" exercises the toupper hash + case-insensitive compare — AND the
        ; complete data chain. RED OFS_NO_DATACHAIN -> size 488 -> D1 absent (isolates the chaining).
        tst.l   d4
        beq     d1_done
        move.l  #2048,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     d1_done
        move.l  d0,a4                ; a4 = destination buffer (preserved by ofs_read_file: movem d2-d7/a2-a5)
        lea     ofs_test_name(pc),a0 ; "kickslop" (different case from the stored name)
        move.l  a4,a1
        move.l  #2048,d0             ; max bytes (buffer guard)
        jsr     ofs_read_file        ; d0 = size read | 0 (absolute jsr: ofs.o linked out of 16-bit bsr range)
        cmp.l   #1024,d0             ; complete file read?
        bne.s   .d1_free
        cmp.l   #$44314F46,(a4)      ; @0 "D1OF"
        bne.s   .d1_free
        cmp.l   #$534F4B30,4(a4)     ; @0 "SOK0"
        bne.s   .d1_free
        cmp.l   #$534F4B31,492(a4)   ; @488 "SOK1" (2nd OFS data block)
        bne.s   .d1_free
        cmp.l   #$534F4B32,980(a4)   ; @976 "SOK2" (3rd OFS data block)
        bne.s   .d1_free
        lea     msg_d1_ok(pc),a0
        bsr     ser_puts             ; "D1 OFS READ OK"
.d1_free:
        move.l  a4,a1
        move.l  #2048,d0
        jsr     LVO_FREEMEM(a6)
d1_done:

        ; --- D2: LoadSeg — load "D2Test" from the OFS, relocate, EXECUTE (gated on disk d4) ---
        ; dos_loadseg reads the hunk executable via ofs_read_file (D1), allocates the segments, APPLIES the relocations
        ; and returns the BPTR of the seglist. We execute the loaded code: entry = (BPTR<<2)+4. The code ITSELF emits
        ; "D2LOADSEG OK" (proof that it runs from RAM WITH relocation applied — same logic as CBOOT in
        ; C). RED D2_NO_RELOC: load OK but pointer not relocated -> the code reads low RAM -> marker absent.
        tst.l   d4
        beq     d2_done
        lea     ls_test_name(pc),a0
        jsr     dos_loadseg          ; d0 = BPTR of 1st segment | 0 (absolute jsr: loadseg.o out of bsr range)
        tst.l   d0
        beq.s   d2_done              ; load failure -> no marker
        move.l  d0,-(sp)             ; BPTR on the stack (survives the loaded code)
        lsl.l   #2,d0
        addq.l  #4,d0                ; entry = (BPTR<<2)+4 = contents of the 1st hunk (CODE)
        move.l  d0,a0
        jsr     (a0)                 ; execute the loaded code (A6=SysBase) -> emits "D2LOADSEG OK"
        move.l  ($4).w,a6            ; reload SysBase (the loaded code may have clobbered a6)
        move.l  (sp)+,d0             ; BPTR
        jsr     dos_unloadseg        ; free the segments
d2_done:

        ; --- M6a: FUNCTIONAL VBLANK unit of timer.device ---
        ; allocates reply port + timerequest, requests 100000 us (= 5 ticks), BeginIO, then
        ; polls the reply port (the VBlank service replies after ~5 VBlanks). d6 = timer base,
        ; d7 = VBL_COUNT at start (preserved by AllocMem/newlist/GetMsg).
        lea     EB_DEVICELIST(a6),a0
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,d6                ; d6 = timer.device base
        beq     m6a_fail
        move.l  #MP_SIZE,d0          ; reply port (PA_IGNORE: boot polls with GetMsg)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m6a_fail
        move.l  d0,a2                ; a2 = port
        lea     MP_MSGLIST(a2),a1
        jsr     newlist
        move.b  #PA_SIGNAL,MP_FLAGS(a2)   ; PA_SIGNAL -> exercises exec_Signal FROM the handler
        move.b  #16,MP_SIGBIT(a2)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a2)  ; signals the boot task (TS_RUN -> no-wake)
        move.l  #TR_SIZE,d0          ; timerequest
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m6a_fail
        move.l  d0,a3                ; a3 = timerequest
        move.l  a2,MN_REPLYPORT(a3)
        move.l  d6,IO_DEVICE(a3)
        move.l  #UNIT_VBLANK,IO_UNIT(a3)  ; VBLANK unit (BeginIO's default is MICROHZ since M7a)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a3)
        clr.l   TV_SECS(a3)
        move.l  #100000,TV_MICRO(a3) ; 100000 us / 20000 = 5 ticks
        move.l  EB_THISTASK(a6),a0   ; clear bit 16 of SIGRECVD (we want it set by the reply)
        move.l  TC_SIGRECVD(a0),d0
        bclr    #16,d0
        move.l  d0,TC_SIGRECVD(a0)
        move.l  VBL_COUNT,d7         ; T0
        move.l  a6,-(sp)             ; BeginIO (a6 = timer base, a1 = request)
        move.l  d6,a6
        move.l  a3,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
.m6a_wait:
        move.l  VBL_COUNT,d0         ; timeout safeguard (~4 s)
        sub.l   d7,d0
        cmp.l   #200,d0
        bcc     m6a_fail
        move.l  a2,a0                ; GetMsg(port)?
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .m6a_wait
        cmp.l   a3,d0                ; the reply must be OUR request
        bne     m6a_fail
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)  ; marked replied?
        bne     m6a_fail
        move.l  VBL_COUNT,d0         ; delay ~= 5 ticks? (margin [3..40])
        sub.l   d7,d0
        cmp.l   #3,d0
        bcs     m6a_fail
        cmp.l   #40,d0
        bhi     m6a_fail
        move.l  EB_THISTASK(a6),a0   ; did exec_Signal (from the handler) set bit 16?
        move.l  TC_SIGRECVD(a0),d0
        btst    #16,d0
        beq     m6a_fail
        lea     msg_m6a_ok(pc),a0
        bsr     ser_puts             ; "M6A TIMER OK"

        ; --- M7b: by-number dispatcher — PORTS chain (INT2) via AddIntServer ---
        ; SCHED_ON still 0 (no scheduler/gate interaction; INT2 level 2 < 3 anyway).
        ; Registers TWO servers on PORTS: ciaa_server (pri 10, reads+acknowledges the ciaa ICR ->
        ; cia_test_vec increments CIA_FIRED) and int2_srv2 (pri 0, increments INT2_SRV2). The chain
        ; calls them IN PRIORITY ORDER (cia before srv2) -> proves AddIntServer + walker + order.
        ; Server structs in RAM (Enqueue links them). A CIA-A Timer A one-shot triggers INT2.
        ; Generalises M6b: cia.resource IS the PORTS handler (server), no longer a hardcoded autovector.
        clr.l   CIA_FIRED
        clr.l   INT2_SRV2
        clr.l   INT2_ORDER_SNAP
        lea     ciaa_test_name(pc),a1   ; OpenResource("ciaa.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     m7b_fail
        move.l  d0,a2                ; a2 = ciaa base (survives the spin + cleanup)
        move.l  #(2*IS_STRIDE),d0    ; 2 aligned RAM struct Interrupts (Enqueue links them -> not in ROM)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7b_fail
        move.l  d0,a3                ; a3 = server block: srvA=+0, srvB=+IS_STRIDE (aligned)
        move.b  #10,LN_PRI(a3)       ; srvA = ciaa_server, pri 10 (called 1st)
        move.l  #ciaa_server,IS_CODE(a3)
        move.b  #0,IS_STRIDE+LN_PRI(a3) ; srvB = int2_srv2, pri 0 (called 2nd)
        move.l  #int2_srv2,IS_STRIDE+IS_CODE(a3)
        moveq   #INTB_PORTS,d0       ; AddIntServer(PORTS, srvA)
        move.l  a3,a1
        jsr     LVO_ADDINTSERVER(a6)
        moveq   #INTB_PORTS,d0       ; AddIntServer(PORTS, srvB)
        lea     IS_STRIDE(a3),a1
        jsr     LVO_ADDINTSERVER(a6)
        move.l  a6,-(sp)             ; AddICRVector(ciaa, bit0=timerA, &cia_test_int)
        move.l  a2,a6
        moveq   #0,d0
        lea     cia_test_int(pc),a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        move.l  CIAR_HWBASE(a2),a0   ; CIA-A Timer A in ONE-SHOT, latch $00FF (~360 us): ONE interrupt is enough to
        move.b  #$FF,CIA_TALO(a0)    ; exercise the chain. In continuous mode, it saturated level 2 as soon as a board added a
        move.b  #$00,CIA_TAHI(a0)    ; PORTS server (UAE DiagPoint, spec uae-int2-v34): the code that stops it no
        move.b  #$19,CIA_CRA(a0)     ; longer ran. START(b0) + one-shot(b3) + LOAD(b4)
        move.l  VBL_COUNT,d7         ; T0 (timeout)
.m7b_wait:
        move.l  VBL_COUNT,d0
        sub.l   d7,d0
        cmp.l   #150,d0
        bcc     m7b_fail             ; timeout -> chain not dispatched
        tst.l   CIA_FIRED            ; 1st server (ciaa) called via the chain?
        beq.s   .m7b_wait
        tst.l   INT2_SRV2            ; 2nd server of the chain called?
        beq.s   .m7b_wait
        move.l  CIAR_HWBASE(a2),a0   ; both run -> hardware cleanup
        move.b  #$00,CIA_CRA(a0)     ; stop Timer A (continuous mode: writing the latch does not restart it)
        move.b  #$FF,CIA_TALO(a0)    ; latch reset to $FFFF, its power-on value: some programs (OctaMED)
        move.b  #$FF,CIA_TAHI(a0)    ; start this timer without reloading it; at $00FF it ran at ~2.8 kHz
        move.l  a6,-(sp)             ; RemICRVector(bit0)
        move.l  a2,a6
        moveq   #0,d0
        suba.l  a1,a1
        jsr     CIA_REMICRVECTOR(a6)
        move.l  (sp)+,a6
        move.w  #INTF_PORTS,INTENA   ; disables Paula PORTS -> no INT2 during the demo
        tst.l   INT2_ORDER_SNAP      ; order: did ciaa (pri 10) run BEFORE srv2 (pri 0)?
        beq     m7b_fail
        moveq   #INTB_PORTS,d0       ; the test server leaves the chain (ciaa_server, the real one, stays)
        lea     IS_STRIDE(a3),a1
        jsr     LVO_REMINTSERVER(a6)
        lea     msg_m7b_ok(pc),a0
        bsr     ser_puts             ; "M7B PORTS OK"

        jsr     kbd_install          ; F2b: installs the LIVE keyboard driver (AddICRVector bit 3 -> kbd_interrupt)
        tst.l   d0
        bne.s   .f2b_nokbd
        lea     msg_f2bkbd(pc),a0
        bsr     ser_puts             ; "F2B KBD OK" (live keyboard driver installed; the CLI can be driven from the keyboard)
.f2b_nokbd:

        ; --- input.device (#2): OpenDevice (FindName) + IND_ADDHANDLER x2 (pri) + IND_WRITEEVENT -> chain ---
        ; Proves IN ISOLATION the core of input.device: the pri-sorted handler chain + the propagation of an
        ; InputEvent via IND_WRITEEVENT (public injection point, the one Intuition uses). Two handlers at
        ; pri 10 / 0: the call order (h1 before h2) proves the sorting; the relayed keycode proves the propagation.
        clr.w   INPUT_SEQ
        clr.w   INPUT_H1_ORD
        clr.w   INPUT_H2_ORD
        clr.w   INPUT_CODE
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1   ; FindName("input.device") (= what OpenDevice does internally)
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .input_done             ; no input.device (should not happen) -> skip
        move.l  d0,a2                   ; a2 = input.device base (survives the BeginIOs)
        move.l  #INPUT_TESTBLK,d0       ; RAM block: ioreq(48) + h1(24) + h2(24) + event(22) -> writable structs
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .input_done
        move.l  d0,a3                   ; a3 = block; ioreq=+0, h1=+48, h2=+72, event=+96
        lea     48(a3),a0               ; h1: handler pri 10 (called 1st)
        move.b  #10,LN_PRI(a0)
        move.l  #input_test_h1,IS_CODE(a0)
        lea     72(a3),a0               ; h2: handler pri 0 (called 2nd)
        move.l  #input_test_h2,IS_CODE(a0)
        lea     96(a3),a0               ; event: RAWKEY, code $34 ('v')
        move.b  #IECLASS_RAWKEY,IE_CLASS(a0)
        move.w  #$0034,IE_CODE(a0)
        move.l  a2,IO_DEVICE(a3)
        lea     48(a3),a0               ; ADDHANDLER h1
        move.w  #IND_ADDHANDLER,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        lea     72(a3),a0               ; ADDHANDLER h2
        move.w  #IND_ADDHANDLER,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        lea     96(a3),a0               ; WRITEEVENT event -> walks the chain
        move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        cmp.w   #$0034,INPUT_CODE       ; keycode relayed by the chain?
        bne.s   .input_free
        cmp.w   #1,INPUT_H1_ORD         ; did h1 (pri 10) run 1st?
        bne.s   .input_free
        cmp.w   #2,INPUT_H2_ORD         ; did h2 (pri 0) run 2nd?
        bne.s   .input_free
        lea     msg_input_ok(pc),a0
        bsr     ser_puts                ; "INPUT OK"
.input_free:
        lea     48(a3),a0               ; REMHANDLER h1 (cleanup)
        move.w  #IND_REMHANDLER,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        lea     72(a3),a0               ; REMHANDLER h2
        move.w  #IND_REMHANDLER,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        move.l  a3,a1
        move.l  #INPUT_TESTBLK,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .input_done
.input_beginio:                         ; helper: BeginIO(input, a3=ioreq) + reloads SysBase. a2=device base.
        move.l  a3,a1
        move.l  a2,a6
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)                 ; input_beginio (LVO -30)
        move.l  ($4).w,a6               ; reload a6 = SysBase (BeginIO exits with a6 = device base)
        rts
.input_done:

        ; --- console.device (#3a): CMD_WRITE of a string -> blit of 8x8 glyphs -> READBACK of the bitplane ---
        ; Proves the blitter + the font WITHOUT display: we write a known string via CMD_WRITE then read back
        ; each cell of the bitplane and compare it with the font8x8 glyph. Correct address math + right bytes
        ; = "CONSOLE WRITE OK". Headless (serial, no Xvfb); RED CON_NO_BLIT -> readback != glyphs -> absent.
        lea     EB_DEVICELIST(a6),a0
        lea     console_dev_name(pc),a1  ; FindName("console.device")
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .con_done
        move.l  d0,a2                    ; a2 = console.device base
        move.l  #64,d0                   ; ioreq (48 -> rounded to 64)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .con_done
        move.l  d0,a3                    ; a3 = ioreq (survives until the free)
        move.l  a2,IO_DEVICE(a3)
        move.w  #CMD_WRITE_BO,IO_COMMAND(a3)
        lea     con_test_str(pc),a0
        move.l  a0,INP_IO_DATA(a3)       ; io_Data = string
        move.l  #con_test_end-con_test_str,IO_LEN_BO(a3)  ; io_Length
        move.l  a3,a1
        move.l  a2,a6
        jsr     -30(a6)                  ; console BeginIO (CMD_WRITE -> blit into the bitplane)
        move.l  ($4).w,a6
        ; readback: each cell (col, lines 0..7) == font8x8 glyph of the corresponding char?
        move.l  CONB_BITMAP(a2),d0       ; bitplane allocated by the 1st write?
        beq     .con_free
        move.l  d0,a5                    ; a5 = bitplane
        moveq   #0,d4
        move.w  CONB_BWIDTH(a2),d4       ; d4 = stride
        lea     con_test_str(pc),a4      ; a4 = rendered string
        moveq   #0,d5                    ; d5 = column
.con_rb:
        moveq   #0,d0
        move.b  (a4)+,d0
        beq.s   .con_match               ; end of string (NUL) -> all cells OK
        subi.w  #$20,d0
        lsl.l   #3,d0                    ; (char-0x20)*8
        move.l  #font8x8,a0
        add.l   d0,a0                    ; a0 = glyph
        move.l  a5,a1
        add.l   d5,a1                    ; a1 = bitplane + col (cury=0)
        moveq   #7,d2                    ; 8 lines
.con_rbrow:
        move.b  (a0)+,d0                 ; expected glyph byte
        cmp.b   (a1),d0                  ; byte actually blitted
        bne.s   .con_mismatch
        add.w   d4,a1                    ; next line (+stride)
        dbra    d2,.con_rbrow
        addq.l  #1,d5                    ; next column
        bra.s   .con_rb
.con_mismatch:
        bra.s   .con_free                ; a cell differs -> no marker
.con_match:
        lea     msg_console_ok(pc),a0
        bsr     ser_puts                 ; "CONSOLE WRITE OK"
.con_free:
        move.l  CONB_BITMAP(a2),d0       ; the test's bitplane is returned: nothing displays the windowless console,
        beq.s   .con_nobm                ; it would keep 10 KB of chip RAM (re-allocated if something writes there)
        clr.l   CONB_BITMAP(a2)
        clr.w   CONB_CURX(a2)
        clr.w   CONB_CURY(a2)
        move.l  d0,a1
        move.l  #CON_BMSIZE,d0
        jsr     LVO_FREEMEM(a6)
.con_nobm:
        move.l  a3,a1
        move.l  #64,d0
        jsr     LVO_FREEMEM(a6)
.con_done:

        ; --- console.device READ via input.device (#3b): IND_WRITEEVENT RAWKEY -> console handler -> CMD_READ ---
        ; The console.device handler (registered on input.device at init) cooks the RAWKEY -> ASCII -> read buffer;
        ; CMD_READ serves it back. We inject a RAWKEY 'v' ($34) through the PUBLIC path IND_WRITEEVENT (Intuition's)
        ; -> chain #2 becomes load-bearing with console as a real consumer. (Keyboard feeder->input.device = F.)
        lea     EB_DEVICELIST(a6),a0
        lea     console_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .conr_done
        move.l  d0,a2                    ; a2 = console.device base
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .conr_done
        move.l  d0,a4                    ; a4 = input.device base
        move.l  #96,d0                   ; block: ioreq@0(48) + event@48(22) + readbuf@80
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .conr_done
        move.l  d0,a3                    ; a3 = block
        move.l  a2,IO_DEVICE(a3)         ; drain the read buffer (leftovers of test #2)
        move.w  #CMD_READ_BO,IO_COMMAND(a3)
        lea     80(a3),a0
        move.l  a0,INP_IO_DATA(a3)
        move.l  #16,IO_LEN_BO(a3)
        bsr     .conr_bio_con
        lea     48(a3),a0               ; build the RAWKEY event 'v' ($34)
        move.b  #IECLASS_RAWKEY,IE_CLASS(a0)
        move.w  #$0034,IE_CODE(a0)
        clr.l   IE_NEXTEVENT(a0)
        move.l  a4,IO_DEVICE(a3)        ; IND_WRITEEVENT -> input.device -> chain -> console handler
        move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
        lea     48(a3),a0
        move.l  a0,INP_IO_DATA(a3)
        move.l  a3,a1
        move.l  a4,a6
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)                 ; input BeginIO WRITEEVENT
        move.l  ($4).w,a6
        clr.b   80(a3)                  ; console CMD_READ 1 byte -> must be cooked 'v'
        move.l  a2,IO_DEVICE(a3)
        move.w  #CMD_READ_BO,IO_COMMAND(a3)
        lea     80(a3),a0
        move.l  a0,INP_IO_DATA(a3)
        move.l  #1,IO_LEN_BO(a3)
        bsr     .conr_bio_con
        cmp.b   #'v',80(a3)             ; char returned by CMD_READ == the cooked keycode?
        bne.s   .conr_free
        lea     msg_conread_ok(pc),a0
        bsr     ser_puts                ; "CONSOLE READ=v"
.conr_free:
        move.l  a3,a1
        move.l  #96,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .conr_done
.conr_bio_con:                          ; helper: console BeginIO(a3=ioreq) + reloads SysBase. a2=console base.
        move.l  a3,a1
        move.l  a2,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts
.conr_done:

        ; --- disk-validator (#4): validates the OFS allocation bitmap of DF0: ---
        ; (on ADF: rootblock+bitmap OFS checksums + valid bm_flag + root marked allocated; NODISK: no disk -> 0)
        jsr     dv_validate          ; diskvalidator.o linked far away -> absolute jsr
        tst.l   d0
        beq.s   .dv4_done
        lea     msg_diskvalid(pc),a0
        bsr     ser_puts             ; "DISK VALID OK"
.dv4_done:

        ; --- keymap (#5): cook keycode(+qualifiers) via keymap.resource (US QWERTY or FR AZERTY depending on the build) ---
                ifeq    KEYMAP_AZERTY
        moveq   #$10,d0             ; 'q' unshifted
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #'q',d0
        bne     .km5_done
        moveq   #$10,d0             ; SHIFT -> 'Q'
        moveq   #$01,d1
        jsr     kbd_cook
        cmp.b   #'Q',d0
        bne     .km5_done
        moveq   #$10,d0             ; CAPS -> 'Q'
        moveq   #$04,d1
        jsr     kbd_cook
        cmp.b   #'Q',d0
        bne     .km5_done
        moveq   #$01,d0             ; '1' unshifted; SHIFT -> '!'
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #'1',d0
        bne     .km5_done
        moveq   #$01,d0
        moveq   #$01,d1
        jsr     kbd_cook
        cmp.b   #'!',d0
        bne     .km5_done
        moveq   #$33,d0             ; CTRL+'c' -> $03
        moveq   #$08,d1
        jsr     kbd_cook
        cmp.b   #3,d0
        bne     .km5_done
        lea     msg_keymap_ok(pc),a0
        bsr     ser_puts            ; "KEYMAP OK"
                else
        moveq   #$10,d0             ; AZERTY: keycode $10 -> 'a'
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #'a',d0
        bne     .km5_done
        moveq   #$01,d0             ; AZERTY: $01 unshifted -> '&'
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #'&',d0
        bne     .km5_done
        moveq   #$01,d0             ; SHIFT -> '1'
        moveq   #$01,d1
        jsr     kbd_cook
        cmp.b   #'1',d0
        bne     .km5_done
        moveq   #$02,d0             ; AZERTY: $02 unshifted -> e-acute ($E9)
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #$E9,d0
        bne     .km5_done
        lea     msg_keymap_azerty(pc),a0
        bsr     ser_puts            ; "KEYMAP AZERTY OK"
                endc
.km5_done:

        ; --- clickable "insert disk" Intuition requester: rendering (readback) + click (RAWMOUSE via input.device) ---
        ; (1) req_draw -> border + text in a bitplane -> readback (top border + glyph 'I'). (2) req_input_handler on
        ; input.device -> IND_WRITEEVENT of a RAWMOUSE INSIDE the gadget (hit) then OUTSIDE (miss) -> proves the hit-test.
        move.l  #CON_BMSIZE,d0          ; test bitplane (chip, cleared)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .req_done
        move.l  d0,a2                   ; a2 = bitplane (survives)
        move.l  a2,a0
        moveq   #CON_BYTEW,d0
        jsr     req_draw                ; draws the requester
        move.l  a2,a0
        cmp.b   #$FF,(64*CON_BYTEW)+10(a0)  ; top border (row 64, byte 10) drawn?
        bne     .req_dfree
        move.l  #font8x8,a1             ; expected glyph 'I'
        move.l  #('I'-$20)*8,d0
        add.l   d0,a1
        lea     (72*CON_BYTEW)+12(a0),a3    ; rendered cell (col 12, row 72)
        moveq   #7,d2
.req_rb:
        move.b  (a1)+,d0
        cmp.b   (a3),d0
        bne.s   .req_dfree
        add.w   #CON_BYTEW,a3
        dbra    d2,.req_rb
        lea     msg_req_drawn(pc),a0
        bsr     ser_puts                ; "REQUESTER DRAWN OK"
.req_dfree:
        move.l  a2,a1
        move.l  #CON_BMSIZE,d0
        jsr     LVO_FREEMEM(a6)
        lea     EB_DEVICELIST(a6),a0    ; click via input.device
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .req_done
        move.l  d0,a4                   ; a4 = input.device base
        move.l  #96,d0                  ; block: req_int(24) + ioreq(48@24) + event(22@72)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .req_done
        move.l  d0,a3                   ; a3 = block
        move.b  #0,LN_PRI(a3)           ; req_int: handler pri 0
        move.l  #req_input_handler,IS_CODE(a3)
        lea     24(a3),a1              ; ADDHANDLER req_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .req_bio
        lea     72(a3),a0              ; RAWMOUSE event INSIDE the gadget (160,112)
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a0)
        move.w  #IECODE_LBUTTON,IE_CODE(a0)
        move.w  #160,IE_X(a0)
        move.w  #112,IE_Y(a0)
        clr.w   REQ_HIT
        lea     24(a3),a1             ; WRITEEVENT (click inside)
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a1)
        lea     72(a3),a0
        move.l  a0,INP_IO_DATA(a1)
        bsr     .req_bio
        cmp.w   #1,REQ_HIT            ; click INSIDE -> must have set REQ_HIT
        bne.s   .req_cfree
        lea     72(a3),a0            ; RAWMOUSE event OUTSIDE (5,5)
        move.w  #5,IE_X(a0)
        move.w  #5,IE_Y(a0)
        clr.w   REQ_HIT
        lea     24(a3),a1
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a1)
        lea     72(a3),a0
        move.l  a0,INP_IO_DATA(a1)
        bsr     .req_bio
        tst.w   REQ_HIT              ; click OUTSIDE -> REQ_HIT must stay 0
        bne.s   .req_cfree
        lea     msg_req_click(pc),a0
        bsr     ser_puts             ; "REQUESTER CLICK OK"
.req_cfree:
        lea     24(a3),a1            ; REMHANDLER
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_REMHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .req_bio
        move.l  a3,a1
        move.l  #96,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .req_done
.req_bio:                            ; helper: input BeginIO(a1=ioreq) + reloads SysBase. a4=input base.
        move.l  a4,a6
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts
.req_done:

        ; --- gameport.device (hardware mouse): LOGIC proven by SYNTHETIC register snapshots ---
        ; (headless: JOY0DAT not drivable + invisible framebuffer -> we prove the LOGIC, not the hardware; the
        ; VBlank server is proven separately, LIVE, by GP_POLLS in the running system). (1) gp_delta8:
        ; 8-bit wraparound vectors. (2) gp_poll: movement (dx incl. wrap) + button edge, captured by a
        ; handler on input.device (IND_WRITEEVENT = the real injection path, like the keyboard feeder).
        moveq   #5,d0                   ; gp_delta8(cur,prev): (5,2) -> +3
        moveq   #2,d1
        jsr     gp_delta8
        cmp.w   #3,d0
        bne     .gp_done
        moveq   #2,d0                   ; (2,5) -> -3
        moveq   #5,d1
        jsr     gp_delta8
        cmp.w   #-3,d0
        bne     .gp_done
        move.w  #$01,d0                 ; ($01,$FE) -> +3 (wrap low->high)
        move.w  #$FE,d1
        jsr     gp_delta8
        cmp.w   #3,d0
        bne     .gp_done
        move.w  #$FE,d0                 ; ($FE,$01) -> -3 (wrap high->low)
        move.w  #$01,d1
        jsr     gp_delta8
        cmp.w   #-3,d0
        bne     .gp_done
        lea     EB_DEVICELIST(a6),a0    ; capture via a handler on input.device
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .gp_done
        move.l  d0,a4                   ; a4 = input.device base
        move.l  d0,GP_INPUTBASE         ; injection target of gp_poll
        move.l  #72,d0                  ; block: gp_int(24) + ioreq(48@24)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .gp_done
        move.l  d0,a3                   ; a3 = block
        move.b  #0,LN_PRI(a3)           ; gp_int: capture handler pri 0
        move.l  #gp_cap_handler,IS_CODE(a3)
        lea     24(a3),a1               ; ADDHANDLER gp_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .gp_bio
        move.w  #$00FE,GP_PREV_JOY      ; movement+wrap: prev (X=$FE,Y=$00), poll JOY=$0001 (X=$01,Y=$00) -> dx=+3 dy=0
        clr.b   GP_PREV_BTN
        clr.b   GP_PREV_RBTN
        clr.w   GP_CAP_N
        move.w  #$0001,d0
        move.w  #$00FF,d1               ; CIAA_PRA bit6=1 -> button released
        jsr     gp_poll
        cmp.w   #1,GP_CAP_N             ; one event (pure movement)
        bne.s   .gp_cfree
        cmp.w   #IECODE_NOBUTTON,GP_CAP_CODE
        bne.s   .gp_cfree
        cmp.w   #3,GP_CAP_DX            ; dx=+3 when crossing $FE->$01 (RED GP_NO_WRAP -> -253)
        bne.s   .gp_cfree
        tst.w   GP_CAP_DY               ; dy=0
        bne.s   .gp_cfree
        move.w  #$1234,GP_PREV_JOY      ; button edge: CONSTANT position (cur==prev -> dx=dy=0) to isolate the edge
        clr.b   GP_PREV_BTN             ; released at start
        clr.w   GP_CAP_N
        move.w  #$1234,d0               ; A: pressed (bit6=0, $BF) -> edge -> LBUTTON down
        move.w  #$00BF,d1
        jsr     gp_poll
        move.w  #$1234,d0               ; B: held -> GREEN nothing / RED GP_NO_EDGE a 2nd down
        move.w  #$00BF,d1
        jsr     gp_poll
        move.w  #$1234,d0               ; C: held -> GREEN nothing / RED a 3rd down
        move.w  #$00BF,d1
        jsr     gp_poll
        move.w  #$1234,d0               ; D: released (bit6=1) -> edge -> LBUTTON up
        move.w  #$00FF,d1
        jsr     gp_poll
        cmp.w   #2,GP_CAP_N             ; exactly 2 events (down + up); RED GP_NO_EDGE -> 3
        bne.s   .gp_cfree
        cmp.w   #(IECODE_LBUTTON|IECODE_UP_PREFIX),GP_CAP_CODE  ; last = up ($E8)
        bne.s   .gp_cfree
        lea     msg_gameport_ok(pc),a0
        bsr     ser_puts                ; "GAMEPORT OK"
.gp_cfree:
        lea     24(a3),a1               ; REMHANDLER
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_REMHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .gp_bio
        clr.l   GP_INPUTBASE            ; gp_install will republish it for the live server
        move.l  a3,a1
        move.l  #72,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .gp_done
.gp_bio:                                ; input BeginIO(a1=ioreq) + reloads SysBase. a4=input base.
        move.l  a4,a6
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts
.gp_done:

        ; --- LIVE M6R wiring: RELATIVE RAWMOUSE deltas -> pointer accumulator (absolute, clamped) -> requester ---
        ; The live link: pointer_input_handler (pri 50) integrates the deltas into a clamped absolute position and
        ; rewrites ie_X/ie_Y -> req_input_handler (pri 0, UNCHANGED) hit-tests in absolute. The JOY->RAWMOUSE path is
        ; proven in the GAMEPORT block; here we inject relative RAWMOUSEs (= gameport's output) via IND_WRITEEVENT.
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .m6r_done
        move.l  d0,a4                   ; a4 = input.device base
        move.l  #120,d0                 ; block: ptr_int(24) + req_int(24@24) + ioreq(48@48) + event(22@96)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .m6r_done
        move.l  d0,a3                   ; a3 = block
        move.b  #50,LN_PRI(a3)          ; ptr_int: accumulator pri 50 (BEFORE the requester in the chain)
        move.l  #pointer_input_handler,IS_CODE(a3)
        move.b  #0,LN_PRI+24(a3)        ; req_int: requester pri 0
        move.l  #req_input_handler,IS_CODE+24(a3)
        lea     48(a3),a1               ; ADDHANDLER ptr_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .m6r_bio
        lea     48(a3),a1               ; ADDHANDLER req_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        lea     24(a3),a0
        move.l  a0,INP_IO_DATA(a1)
        bsr     .m6r_bio
        move.w  #10,PTR_X               ; start (10,10)
        move.w  #10,PTR_Y
        lea     96(a3),a0               ; relative RAWMOUSE event (-50,-50) NOBUTTON -> clamp (0,0)
        clr.l   IE_NEXTEVENT(a0)
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a0)
        move.w  #IECODE_NOBUTTON,IE_CODE(a0)
        move.w  #-50,IE_X(a0)
        move.w  #-50,IE_Y(a0)
        bsr     .m6r_write
        lea     96(a3),a0               ; movement +160,+112 -> (160,112) on the gadget
        move.w  #IECODE_NOBUTTON,IE_CODE(a0)
        move.w  #160,IE_X(a0)
        move.w  #112,IE_Y(a0)
        clr.l   IE_NEXTEVENT(a0)
        bsr     .m6r_write
        cmp.w   #160,PTR_X              ; correct absolute position (RED PTR_NO_CLAMP -> 120: base -40)
        bne.s   .m6r_free
        cmp.w   #112,PTR_Y              ; (RED -> 72)
        bne.s   .m6r_free
        clr.w   REQ_HIT                 ; LBUTTON click (null delta) -> pointer rewritten abs (160,112) -> hit-test INSIDE
        lea     96(a3),a0
        move.w  #IECODE_LBUTTON,IE_CODE(a0)
        move.w  #0,IE_X(a0)
        move.w  #0,IE_Y(a0)
        clr.l   IE_NEXTEVENT(a0)
        bsr     .m6r_write
        cmp.w   #1,REQ_HIT              ; click INSIDE the gadget -> REQ_HIT set
        bne.s   .m6r_free
        lea     96(a3),a0               ; move OUTSIDE: (160,112) -155 -> (5,112)
        move.w  #IECODE_NOBUTTON,IE_CODE(a0)
        move.w  #-155,IE_X(a0)
        move.w  #0,IE_Y(a0)
        clr.l   IE_NEXTEVENT(a0)
        bsr     .m6r_write
        clr.w   REQ_HIT
        lea     96(a3),a0               ; click OUTSIDE (5,112): x<120 -> miss
        move.w  #IECODE_LBUTTON,IE_CODE(a0)
        move.w  #0,IE_X(a0)
        move.w  #0,IE_Y(a0)
        clr.l   IE_NEXTEVENT(a0)
        bsr     .m6r_write
        tst.w   REQ_HIT                 ; click OUTSIDE -> REQ_HIT stays 0
        bne.s   .m6r_free
        lea     msg_m6r_live_ok(pc),a0
        bsr     ser_puts                ; "M6R LIVE OK"
.m6r_free:
        lea     48(a3),a1               ; REMHANDLER ptr_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_REMHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .m6r_bio
        lea     48(a3),a1               ; REMHANDLER req_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_REMHANDLER,IO_COMMAND(a1)
        lea     24(a3),a0
        move.l  a0,INP_IO_DATA(a1)
        bsr     .m6r_bio
        move.l  a3,a1
        move.l  #120,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .m6r_done
.m6r_write:                             ; IND_WRITEEVENT(event @ 96(a3)); a4=input base, a3=block. Clobbers a0/a1.
        lea     48(a3),a1
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a1)
        lea     96(a3),a0
        move.l  a0,INP_IO_DATA(a1)
.m6r_bio:
        move.l  a4,a6
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts
.m6r_done:

                ifne    LOADSCREEN_DEMO
        ; Loading screen DEMO: all modules are up (console/graphics/trackdisk) + disk in DF0:.
        ; loadscreen_demo sets up the display, reads "bigseg" by streaming with a progress bar, holds the screen.
        move.l  ($4).w,a6            ; a6 = SysBase
        jsr     loadscreen_demo      ; DOES NOT RETURN
                endc
        ; --- M7a + M3f: combined demo (SCHED_ON=1) ---
        ; Whole setup at IPL7 so that no IRQ fires before the launch (CIA-B starts
        ; but its underflow stays pending until the rte). M7a: MICROHZ unit (CIA-A timer B, level 2) +
        ; task_timer blocking on it -> proves (a) a TASK woken by an interrupt timer
        ; (Wait->wake) and (b) per-level IPL fidelity (M7e, dev ROM: level 6 probe on CIA-B
        ; timer A, m7_int6_probe): INT6 (level 6) preempts the BODY of
        ; vbl_handler (native IPL 3) -> VBL_PREEMPT_COUNT>0, BUT the switch's list surgery stays
        ; atomic (brief IPL7) -> VBL_CLASH==0 (overlap, not corruption). RED1 (M7E_SURGERY_INTENA=1:
        ; INTENA-off instead of IPL7) -> VBL_CLASH>0; RED2 (M7E_PROLOGUE_IPL7=1: IPL7 in the prologue) ->
        ; VBL_PREEMPT_COUNT==0. M3f (replayed, non-regression): task_H/L/S prove
        ; the coexistence of preemption + yield ("M3F LIVE"). GREEN = "M7A TIMER OK" + "M7E IPL OK".
        move.w  #$2700,sr            ; masks interrupts during the WHOLE setup
                ifeq    PROD            ; PROD: vbl_tail is a PROOF server (M7e/M7f) -> out of prod
        clr.l   VBL_CLASH
        clr.l   VBL_PREEMPT_COUNT    ; M7e: baseline of the vbl body preemptions (INT6 armed right after)
        clr.b   M7E_STAT             ; M7e: "M7E IPL OK" marker not yet emitted
        clr.l   VERTB_CHAIN_N        ; M7f: baseline of the VERTB chain walks
        clr.b   M7F_STAT             ; M7f: "M7F VERTB OK" marker not yet emitted
        ; M7f: registers vbl_tail_server (PROOF server, pri -10) at the TAIL of the VERTB chain
        ; (after sched_server pri 20 + timer_vblank pri 0). Its counter VERTB_CHAIN_N proves the complete walk.
        move.b  #-10,VBL_TAIL_INT+LN_PRI
        clr.l   VBL_TAIL_INT+IS_DATA
        move.l  #vbl_tail_server,VBL_TAIL_INT+IS_CODE
        moveq   #INTB_VERTB,d0
        lea     VBL_TAIL_INT,a1
        jsr     LVO_ADDINTSERVER(a6)
                endc                    ; end of the VERTB proof block (PROD=0)
        ; hardware mouse: arms the gameport.device poller (gp_vblank_server) on the VERTB chain of the running
        ; system — PERSISTENT LIVE wiring (counterpart of the keyboard feeder). GP_POLLS will advance on real VBlanks;
        ; headless (static JOY0DAT) the poller injects nothing (prev primed = current) -> inert with regard to M7.
        jsr     gp_install
                ifeq    PROD            ; PROD: COPER = PROOF source (M7g multi-source int3) -> out of prod
        ; M7g: 2nd LEVEL 3 source (COPER) to prove int3's multi-source INTREQR decoding.
        ; coper_test (EXCLUSIVE vector) increments COPER_FIRED; vbl_tail triggers COPER by software.
        clr.l   COPER_FIRED
        clr.b   COPER_TICK
        clr.b   M7G_STAT
        moveq   #INTB_COPER,d0          ; SetIntVector(COPER, &coper_int)
        lea     coper_int(pc),a1
        jsr     LVO_SETINTVECTOR(a6)
        move.w  #(INTF_SETCLR|INTF_COPER),INTENA ; enables COPER (level 3); vbl_tail triggers it
                endc                    ; end of the COPER proof source (PROD=0); MICROHZ/CIA-B kept below
        lea     ciab_test_name(pc),a1   ; OpenResource("ciab.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a2                ; a2 = ciab base
        moveq   #INTB_EXTER,d0       ; SetIntVector(EXTER, &ciab_server_int): EXCLUSIVE vector ->
        lea     ciab_server_int(pc),a1  ; INT6 goes through the by-number dispatcher (ciab_server/cia_dispatch)
        jsr     LVO_SETINTVECTOR(a6)
                ifeq    PROD            ; dev ROM: level 6 source of the M7d/M7e proofs (the production ROM
        move.l  a6,-(sp)             ; programs no CIA-B timer, like 1.3: games take them)
        move.l  a2,a6                ; AddICRVector(ciab, bit0 = timer A, &m7_int6_int)
        moveq   #0,d0
        move.l  #m7_int6_int,a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        lea     CIAB_HW,a0           ; CIA-B timer A in a one-shot of 255 ticks (~360 us), re-armed at the end of each
        move.b  #$FF,CIA_TALO(a0)    ; service: the period includes the service duration, no accumulation of INT6s
        move.b  #$00,CIA_TAHI(a0)
        move.b  #$19,CIA_CRA(a0)     ; START + one-shot + LOAD
                endc
        move.w  #(INTF_SETCLR|INTF_EXTER),INTENA   ; enables Paula EXTER (INT6, level 6 > VBlank 3)
        bsr     setup_stress_port    ; M7d: shared port + K messages (hammered by task AND interrupt)
        bsr     setup_demo_tasks     ; task_H(10) + task_L(0) + task_S(0) + task_timer(10, M7a) + task_port(0, M7d)
        ; --- M6r/M6y: strap (romboot) — reads, validates and EXECUTES the bootblock of DF0: (milestone C "it boots!") ---
        ; strap_boot reads sectors 0+1 (bootblock) of DF0:, validates magic "DOS" + additive checksum, and jumps
        ; to the boot code at +12. d0=0 = no bootable volume (no disk, or invalid checksum = formatted, not
        ; installed) -> insert-disk BOOT SCREEN (M6R). d0!=0 = bootblock executed -> NO insert-disk (M6Y);
        ; the "CBOOT" marker is emitted by the bootblock ITSELF during its execution (proof of the jump).
        ; Both branches converge towards SCHED_ON (the complete M7 set follows in both cases).
        ; RED STRAP_FAKE_BOOTDEV: d0!=0 without reading -> M6Y present but CBOOT absent. RED STRAP_NO_EXEC: validates
        ; but does not jump -> CBOOT absent, M6Y present. RED STRAP_BAD_CSUM: rejects a good block -> M6R.
        jsr     alert_boothook       ; alert.hook: Guru of a dead-end alert from before the reset, before the strap
        bsr     strap_boot
        tst.l   d0
        bne.s   .m6r_floppy
        jsr     strap_romboot        ; DF0: not bootable: BootPoint of the boards (a BootPoint that starts dos jumps to
                                     ; boot_dos_start and does not return)
        lea     msg_m6r_ok(pc),a0
        bsr     ser_puts             ; "M6R STRAP OK (no bootable volume -> insert-disk)"
        jsr     gfx_display_init     ; M6s: BOOT SCREEN (32-colour kitten image) via the graphics.library ABI
        lea     msg_m6s_ok(pc),a0
        bsr     ser_puts             ; "M6S BOOTSCR OK" (screen set up; VISUAL discriminant = colours)
        bsr     m6r_wire_requester   ; LIVE wiring: PERSISTENT pointer+requester handlers on input.device
        lea     dw_name(pc),a0       ; DF0: watch: an inserted floppy reboots the machine (boot)
        move.l  #disk_watch,a1
        moveq   #-1,d0
        move.l  #DW_STK,d1
        jsr     proc_create
        bra.s   boot_strap_done
.m6r_floppy:
        jsr     dos_df0bootnode      ; DF0: BootNode (pri 5) in eb_MountList, as after a 1.3 bootblock
; boot_dos_start: dos startup (after a DF0: bootblock, or from the rt_Init of dos.library called by the
; BootPoint of a board): mount list -> boot device, then Initial CLI. Does not return.
boot_dos_start:
        move.l  ($4).w,a6
        jsr     dos_mountlist
        lea     msg_m6y_ok(pc),a0
        bsr     ser_puts             ; "M6Y STRAP BOOTED OK" (bootblock executed; CBOOT emitted by the bootblock)
        bsr     ptr_wire             ; mouse: on-screen pointer (sprite) in the running system
        ; --- F1: BOOTABLE disk -> create the Initial CLI (shell). GATED on the boot (this is the F vs E line):
        ; on a non-bootable disk (M6R insert-disk branch), NO Initial CLI is created. The shell first runs
        ; s:startup-sequence (root) then moves on to the interactive prompt. a6 = SysBase (strap restored it).
        lea     sh_cname(pc),a0
        move.l  #shell_main,a1       ; absolute: shell.o linked out of 16-bit lea(pc) range
        moveq   #2,d0                ; Initial CLI pri 2 (sole consumer of the console)
        move.l  #SH_STK,d1           ; the commands it launches run on this stack
        jsr     proc_create
boot_strap_done:
                ifeq    M7E_COOP
        move.b  #1,SCHED_ON          ; ARMS periodic preemption (default)
                endc                 ; M7E_COOP=1: SCHED_ON stays 0 -> yield-only non-regression
        ; --- M7c: LAUNCH of the 1st task = SUPERVISOR -> USER mode transition ---
        ; The boot stack (STACKTOP) becomes the SHARED SSP of the interrupts; each task has its own
        ; user stack (AllocMem'd). We reset the SSP to STACKTOP (abandon the boot context), reserve
        ; a frame slot, and dispatch_in relocates task_H's user frame -> SSP then rte's in USER mode.
        move.l  #STACKTOP,sp         ; clean shared SSP (the boot context never resumes)
        lea     -FRAME_SIZE(sp),sp   ; 66-byte slot for dispatch_in (movem+rte bring sp back to STACKTOP)
        lea     EB_TASKREADY(a6),a0  ; explicit initial dispatch
        jsr     LVO_REMHEAD(a6)      ; head = task_H (pri 10) -> it Waits first
        move.l  d0,a1
        bra     dispatch_in          ; -> task_H in USER mode (SR=$0000; VBlank + INT6 + yield active)

eb_fail:
        move.w  #C_FAIL,COLOR00
        lea     msg_fail(pc),a0
        bsr     ser_puts
.ff:
        bra.s   .ff

; ser_puts: NUL-terminated string on the serial port (a0); bounded timeout on TBE
ser_puts:
        movem.l d0/d1/d2/a0,-(sp)
        bsr     ser_lock             ; ATOMIC output (no other printer interleaves)
.lp:
        move.b  (a0)+,d0
        beq.s   .done
        move.w  #$2000,d2
.wt:
        move.w  SERDATR,d1
        btst    #13,d1
        bne.s   .tx
        dbra    d2,.wt
        bra.s   .done
.tx:
        and.w   #$00FF,d0
        or.w    #$0100,d0
        move.w  d0,SERDAT
        bra.s   .lp
.done:
        bsr     ser_unlock
        movem.l (sp)+,d0/d1/d2/a0
        rts

; ser_lock / ser_unlock: make ALL serial output atomic between tasks (Forbid gated by SCHED_ON — no-op before
; multitasking). Mechanism = mutual exclusion by Forbid (no task switch during the output), already proven
; (task_timer). Preserve ALL registers (Forbid/Permit preserve them; only a6 is touched, saved/restored).
; All concurrent printers (ser_puts, ser_puthex, con_handler WRITE, feeder, binaries loaded via the Forbid of
; their caller) use them -> no more byte-by-byte interleaving of the markers (no more false GREEN).
ser_lock:
        tst.b   SCHED_ON
        beq.s   .slk_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  (sp)+,a6
.slk_ret:
        rts
ser_unlock:
        tst.b   SCHED_ON
        beq.s   .sulk_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
.sulk_ret:
        rts

; ser_puthex(d0.w): emits the 4 hex digits of d0 (word) on the serial port (MSB first). Scratch saved (d0-d3).
ser_puthex:
        movem.l d0-d3,-(sp)
        bsr     ser_lock             ; atomic output
        move.w  d0,d3                ; d3 = value to display
        moveq   #3,d2                ; 4 nibbles
.ph_nib:
        rol.w   #4,d3                ; brings the next most significant nibble into bits 0-3
        move.w  #$2000,d1            ; TBE timeout
.ph_wt:
        move.w  SERDATR,d0
        btst    #13,d0               ; TBE (transmit buffer empty)?
        bne.s   .ph_send
        dbra    d1,.ph_wt
        bra.s   .ph_next             ; timeout -> skip this digit
.ph_send:
        move.w  d3,d0
        and.w   #$000F,d0
        add.w   #'0',d0
        cmp.w   #'9',d0
        bls.s   .ph_out
        addq.w  #7,d0                ; 'A'..'F'
.ph_out:
        and.w   #$00FF,d0
        or.w    #$0100,d0            ; 8 bits
        move.w  d0,SERDAT
.ph_next:
        dbra    d2,.ph_nib
        bsr     ser_unlock
        movem.l (sp)+,d0-d3
        rts

; ============================ self-test (M2.1a+) ====================
; Exercises the jump-table dispatch and the behaviour of the functions.
; Return: d0 = 0 (all OK) / 1 (failure).
selftest:
        movem.l d6-d7/a2-a5,-(sp)
        ; chip heap baseline: 1st free chunk AFTER the permanent boot
        ; allocations (ThisTask TCB...). The coalescing asserts compare against this
        ; baseline (robust to permanent allocations, not to an empty heap).
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),a5     ; a5 = baseline address of the 1st chunk
        move.l  MC_BYTES(a5),d7     ; d7 = baseline size
        ; Forbid: TDNestCnt -1 -> 0; Permit: 0 -> -1
        jsr     LVO_FORBID(a6)
        cmp.b   #0,EB_TDNEST(a6)
        bne.w   .bad
        jsr     LVO_PERMIT(a6)
        cmp.b   #-1,EB_TDNEST(a6)
        bne.w   .bad
        ; Disable/Enable: IDNestCnt -1 -> 0 -> -1
        jsr     LVO_DISABLE(a6)
        cmp.b   #0,EB_IDNEST(a6)
        bne.w   .bad
        jsr     LVO_ENABLE(a6)
        cmp.b   #-1,EB_IDNEST(a6)
        bne.w   .bad

        ; list: NEWLIST, AddTail(n1), AddTail(n2), FindName
        lea     TST_LIST,a1
        jsr     newlist
        move.l  #str_alpha,TST_N1+LN_NAME
        move.l  #str_beta,TST_N2+LN_NAME
        lea     TST_LIST,a0
        lea     TST_N1,a1
        jsr     LVO_ADDTAIL(a6)
        lea     TST_LIST,a0
        lea     TST_N2,a1
        jsr     LVO_ADDTAIL(a6)
        ; FindName("beta") == TST_N2
        lea     TST_LIST,a0
        move.l  #str_beta,a1
        jsr     LVO_FINDNAME(a6)
        cmp.l   #TST_N2,d0
        bne.w   .bad
        ; FindName("gamma") == 0
        lea     TST_LIST,a0
        move.l  #str_gamma,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.w   .bad
        ; Remove(n1); FindName("alpha") == 0
        lea     TST_N1,a1
        jsr     LVO_REMOVE(a6)
        lea     TST_LIST,a0
        move.l  #str_alpha,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.w   .bad
        ; AddHead(n1); FindName("alpha") == TST_N1
        lea     TST_LIST,a0
        lea     TST_N1,a1
        jsr     LVO_ADDHEAD(a6)
        lea     TST_LIST,a0
        move.l  #str_alpha,a1
        jsr     LVO_FINDNAME(a6)
        cmp.l   #TST_N1,d0
        bne.w   .bad
        ; Open/Close: OpenCnt +1 then -1, Open returns SysBase
        jsr     LVO_OPEN(a6)
        cmp.l   a6,d0
        bne.w   .bad
        jsr     LVO_CLOSE(a6)
        tst.w   LIB_OPENCNT(a6)
        bne.w   .bad
        lea     chk_core(pc),a0      ; serial checkpoint: "core" group passed
        bsr     ser_puts

        ; --- memory: AllocMem / FreeMem ---
        move.l  #256,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; p1
        move.l  #256,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3                ; p2
        move.l  #$11111111,(a2)      ; non-overlap by pattern
        move.l  #$22222222,(a3)
        cmp.l   #$11111111,(a2)
        bne.w   .bad
        cmp.l   #$22222222,(a3)
        bne.w   .bad
        move.l  #$DEADBEEF,(a2)      ; dirty p1, free, realloc CLEAR -> zero
        move.l  a2,a1
        move.l  #256,d0
        jsr     LVO_FREEMEM(a6)
        move.l  #256,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a1
        tst.l   (a1)                 ; MEMF_CLEAR -> 1st longword == 0
        bne.w   .bad
        move.l  #256,d0              ; free the CLEAR block then p2
        jsr     LVO_FREEMEM(a6)
        move.l  a3,a1
        move.l  #256,d0
        jsr     LVO_FREEMEM(a6)

        ; coalescing: after all the frees, the heap must be back to its baseline
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),d0
        cmp.l   a5,d0
        bne.w   .bad
        move.l  d0,a0
        cmp.l   MC_BYTES(a0),d7
        bne.w   .bad
        lea     chk_mem(pc),a0       ; checkpoint: M2.1/M2.2 memory + coalescing
        bsr     ser_puts

        ; ===== M2.4a: multi-MemHeader + list primitives =====
        ; (1) 2nd "fast" MemHeader on the DISJOINT region [FTEST_LO,FTEST_HI).
        ;     Struct allocated from the heap; the region is fixed/disjoint (that is
        ;     how a real multi-header works: distinct physical regions).
        move.l  #MH_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; a2 = H (fast header)
        move.b  #NT_MEMORY,LN_TYPE(a2)
        move.w  #(MEMF_FAST|MEMF_PUBLIC),MH_ATTRIBUTES(a2)
        move.l  #FTEST_LO,MH_LOWER(a2)
        move.l  #FTEST_HI,MH_UPPER(a2)
        move.l  #(FTEST_HI-FTEST_LO),MH_FREE(a2)
        move.l  #FTEST_LO,a0         ; initial chunk = the whole region
        clr.l   MC_NEXT(a0)
        move.l  #(FTEST_HI-FTEST_LO),MC_BYTES(a0)
        move.l  a0,MH_FIRST(a2)
        lea     EB_MEMLIST(a6),a0
        move.l  a2,a1
        jsr     LVO_ADDTAIL(a6)
        ; AvailMem(MEMF_FAST) == size of the region
        moveq   #MEMF_FAST,d1
        jsr     LVO_AVAILMEM(a6)
        cmp.l   #(FTEST_HI-FTEST_LO),d0
        bne.w   .bad
        ; AllocMem(1024,MEMF_FAST) -> selection by attribute -> address in the region
        move.l  #1024,d0
        moveq   #MEMF_FAST,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3               ; a3 = fast block
        cmp.l   #FTEST_LO,d0
        bcs.w   .bad                ; < FTEST_LO
        cmp.l   #FTEST_HI,d0
        bcc.w   .bad                ; >= FTEST_HI
        ; TypeOfMem(block) has the MEMF_FAST bit (= bit 2)
        move.l  a3,a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #2,d0
        beq.w   .bad
        ; FreeMem(fast block): the owner search must find H (not the chip header)
        move.l  a3,a1
        move.l  #1024,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #MEMF_FAST,d1
        jsr     LVO_AVAILMEM(a6)
        cmp.l   #(FTEST_HI-FTEST_LO),d0   ; region full again -> owner search OK
        bne.w   .bad
        ; remove H from the MemList + free its struct
        move.l  a2,a1
        jsr     LVO_REMOVE(a6)
        move.l  a2,a1
        move.l  #MH_SIZE,d0
        jsr     LVO_FREEMEM(a6)

        ; (2) Enqueue: 3 nodes pri 0/10/5 -> head->tail order 10,5,0 (FIFO at equal pri)
        move.l  #(3*16),d0          ; 3 nodes (LN_SIZE=14 rounded to 16)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3               ; a3 = n0=+0, n1=+16, n2=+32
        move.l  #16,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a4               ; a4 = struct List
        move.l  a4,a1
        jsr     newlist
        move.b  #0,LN_PRI(a3)
        move.b  #10,16+LN_PRI(a3)
        move.b  #5,32+LN_PRI(a3)
        move.l  a4,a0
        move.l  a3,a1               ; Enqueue n0 (pri 0)
        jsr     LVO_ENQUEUE(a6)
        move.l  a4,a0
        lea     16(a3),a1           ; Enqueue n1 (pri 10)
        jsr     LVO_ENQUEUE(a6)
        move.l  a4,a0
        lea     32(a3),a1           ; Enqueue n2 (pri 5)
        jsr     LVO_ENQUEUE(a6)
        ; expected order: head=n1, n1->Succ=n2, n2->Succ=n0, n0->Succ=&lh_Tail
        move.l  (a4),a0             ; lh_Head
        lea     16(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n1->Succ
        lea     32(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n2->Succ
        move.l  a3,a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n0->Succ == &lh_Tail (= a4+LH_TAIL)
        lea     LH_TAIL(a4),a1
        cmp.l   a1,a0
        bne.w   .bad
        ; RemHead -> n1; new head = n2
        move.l  a4,a0
        jsr     LVO_REMHEAD(a6)
        lea     16(a3),a1
        cmp.l   a1,d0
        bne.w   .bad
        move.l  (a4),a0
        lea     32(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        ; RemTail -> n0 (lowest pri, at the tail)
        move.l  a4,a0
        jsr     LVO_REMTAIL(a6)
        move.l  a3,a1
        cmp.l   a1,d0
        bne.w   .bad
        ; Insert(list, n0, pred=n2) -> n2->Succ == n0
        move.l  a4,a0
        move.l  a3,a1               ; node n0
        lea     32(a3),a2           ; pred n2
        jsr     LVO_INSERT(a6)
        lea     32(a3),a0
        move.l  (a0),a0             ; n2->Succ
        move.l  a3,a1
        cmp.l   a1,a0
        bne.w   .bad
        ; free list + nodes
        move.l  a4,a1
        move.l  #16,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a3,a1
        move.l  #(3*16),d0
        jsr     LVO_FREEMEM(a6)
        lea     chk_m24a(pc),a0      ; checkpoint: multi-header + lists
        bsr     ser_puts

        ; ===== M2.4b: tasks + signals (non-blocking) =====
        ; FindTask(NULL) == ThisTask
        sub.l   a1,a1
        jsr     LVO_FINDTASK(a6)
        cmp.l   EB_THISTASK(a6),d0
        bne.w   .bad
        ; AllocSignal(-1) -> 16 (bits 0-15 pre-allocated via SYS_SIGALLOC)
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #16,d0
        bne.w   .bad
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #17,d0
        bne.w   .bad
        moveq   #16,d0               ; free 16 -> becomes the lowest free one again
        jsr     LVO_FREESIGNAL(a6)
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #16,d0
        bne.w   .bad
        ; AllocSignal clears a leftover SIGRECVD on the allocated bit
        move.l  EB_THISTASK(a6),a2
        or.l    #$00100000,TC_SIGRECVD(a2)   ; leftover bit 20
        moveq   #20,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #20,d0
        bne.w   .bad
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00100000,d0
        bne.w   .bad                 ; bit 20 must have been cleared
        ; SetSignal: sets bit 16, returns the old set
        move.l  #$00010000,d0
        move.l  #$00010000,d1
        jsr     LVO_SETSIGNAL(a6)
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00010000,d0
        beq.w   .bad
        ; Signal(ThisTask, bit 17) -> bit set in SIGRECVD
        move.l  a2,a1
        move.l  #$00020000,d0
        jsr     LVO_SIGNAL(a6)
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00020000,d0
        beq.w   .bad
        ; SetTaskPri(ThisTask,5) -> old 0; LN_PRI == 5; then restore 0
        move.l  a2,a1
        moveq   #5,d0
        jsr     LVO_SETTASKPRI(a6)
        tst.l   d0
        bne.w   .bad
        cmp.b   #5,LN_PRI(a2)
        bne.w   .bad
        move.l  a2,a1
        moveq   #0,d0
        jsr     LVO_SETTASKPRI(a6)
        moveq   #16,d0               ; clean up the test signals (16,17,20)
        jsr     LVO_FREESIGNAL(a6)
        moveq   #17,d0
        jsr     LVO_FREESIGNAL(a6)
        moveq   #20,d0
        jsr     LVO_FREESIGNAL(a6)
        move.l  #0,TC_SIGRECVD(a2)   ; reset SIGRECVD clean

        ; FindTask(name): dummy task node in TaskReady
        move.l  #TC_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3                ; dummy task
        move.b  #NT_TASK,LN_TYPE(a3)
        move.l  #task_test_name,LN_NAME(a3)
        lea     EB_TASKREADY(a6),a0
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)
        move.l  #task_test_name,a1
        jsr     LVO_FINDTASK(a6)
        cmp.l   a3,d0
        bne.w   .bad
        move.l  #str_gamma,a1        ; unknown name -> 0
        jsr     LVO_FINDTASK(a6)
        tst.l   d0
        bne.w   .bad
        move.l  a3,a1                ; remove + free the dummy task
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1
        move.l  #TC_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        lea     chk_m24b(pc),a0      ; checkpoint: tasks + signals
        bsr     ser_puts

        ; ===== M2.4c: ports / messages (non-blocking) =====
        moveq   #-1,d0               ; signal bit for the port
        jsr     LVO_ALLOCSIGNAL(a6)
        move.l  d0,d6                ; d6 = bit number
        move.l  #MP_SIZE,d0          ; main port from the heap
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; a2 = port
        lea     MP_MSGLIST(a2),a1    ; the caller initialises the queue
        jsr     newlist
        move.l  #str_port,LN_NAME(a2)
        move.b  #PA_SIGNAL,MP_FLAGS(a2)
        move.b  d6,MP_SIGBIT(a2)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a2)
        move.l  a2,a1
        jsr     LVO_ADDPORT(a6)
        ; FindPort(name) == port; FindPort(unknown) == 0
        move.l  #str_port,a1
        jsr     LVO_FINDPORT(a6)
        cmp.l   a2,d0
        bne.w   .bad
        move.l  #str_gamma,a1
        jsr     LVO_FINDPORT(a6)
        tst.l   d0
        bne.w   .bad
        ; 2 messages from the heap (msg1=+0, msg2=+MN_SIZE)
        move.l  #(2*MN_SIZE),d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3
        ; PutMsg(msg1) must set the port's bit in ThisTask's SIGRECVD
        move.l  EB_THISTASK(a6),a0
        clr.l   TC_SIGRECVD(a0)
        move.l  a2,a0
        move.l  a3,a1
        jsr     LVO_PUTMSG(a6)
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGRECVD(a0),d0
        moveq   #1,d1
        lsl.l   d6,d1
        and.l   d1,d0
        beq.w   .bad                 ; port bit not set
        ; PutMsg(msg2); GetMsg FIFO: msg1, msg2, then 0 (empty)
        move.l  a2,a0
        lea     MN_SIZE(a3),a1
        jsr     LVO_PUTMSG(a6)
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        cmp.l   a3,d0
        bne.w   .bad
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        lea     MN_SIZE(a3),a1
        cmp.l   a1,d0
        bne.w   .bad
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        bne.w   .bad
        ; ReplyMsg: msg1 comes back on a reply port with type NT_REPLYMSG
        move.l  #MP_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a4                ; a4 = reply port
        lea     MP_MSGLIST(a4),a1
        jsr     newlist
        move.b  #PA_IGNORE,MP_FLAGS(a4)   ; no signal on reply
        move.l  a4,MN_REPLYPORT(a3)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        move.l  a4,a0
        jsr     LVO_GETMSG(a6)
        cmp.l   a3,d0                ; msg1 back on the reply port
        bne.w   .bad
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne.w   .bad
        ; cleanup: RemPort of the PUBLIC port only (rport was never
        ; AddPort'd -> removing it would call Remove on an unlinked node, which
        ; would write into low RAM $0/$4). free messages + ports + signal.
        move.l  a2,a1
        jsr     LVO_REMPORT(a6)
        move.l  a3,a1
        move.l  #(2*MN_SIZE),d0
        jsr     LVO_FREEMEM(a6)
        move.l  a4,a1
        move.l  #MP_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a2,a1
        move.l  #MP_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d6,d0
        jsr     LVO_FREESIGNAL(a6)
        lea     chk_m24c(pc),a0      ; checkpoint: ports + messages
        bsr     ser_puts

        ; final invariant: chip heap back to the baseline (single chunk)
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),d0
        cmp.l   a5,d0
        bne.w   .bad
        move.l  d0,a0
        cmp.l   MC_BYTES(a0),d7
        bne.w   .bad

        moveq   #0,d0
        bra.s   .out
.bad:
        moveq   #1,d0
.out:
        movem.l (sp)+,d6-d7/a2-a5
        rts

; ============================ recombination demo (M3f) ==============
; Creates 3 supervisor tasks and puts them into TaskReady. PROOF scaffolding (like the
; selftest): will be replaced by the exec init sequence (resident scan) later. Signal
; HARD-WIRED (DEMO_SIG=16, outside the reserved 0-15) rather than AllocSignal (which operates on
; ThisTask = boot task; Wait/Signal only look at the MASK). task_L signals
; task_H via its TCB published in WP_HTASK (set BEFORE launch -> always valid).
;   task_H (pri 10): yield target. task_L/task_S (pri 0): preemptive round-robin.
setup_demo_tasks:                    ; a6 = SysBase; clobbers scratch + d2/a2-a4 (saved)
        movem.l d2/a2-a4,-(sp)
        clr.l   WP_HTASK             ; low RAM not guaranteed zero at power-on -> explicit
        clr.l   FB_TASK              ; Forbid atomicity proof: TCB of task_fb (set at creation)
        clr.l   FORBID_TEST_FLAG     ; "fb ran" flag (task_fa clears it again before its test)
        clr.l   WP_CONS
        clr.l   WP_PROD
        clr.l   WP_SPIN
        clr.l   WP_STAT
        clr.l   WP_TCONS             ; M7a: wake-ups of task_timer
        clr.b   QUANTUM_ELAPSED      ; M7h: current time slice
        clr.l   QUANTUM_EXPIRE_N     ; M7h: quantum expirations
        clr.l   Q2_RUNS              ; M7h: iterations of the 2nd spinner
        clr.b   M7H_STAT             ; M7h: "M7H QUANTUM OK" marker not yet emitted
        clr.l   RM_RUNS              ; M7j: iterations of task_rm
        clr.b   M7J_STAT             ; M7j: "M7J REMTASK OK" marker not yet emitted
                ifne    M7H_QUANTUM_DEMO
        ; === M7h: quantum ISOLATION demo — ONLY 2 spinners pri 0, no higher-priority ===
        ; preemptor nor yield -> the rotation is driven ONLY by the VBlank quantum (observable).
        lea     task_s(pc),a2        ; spinner-1 (counter WP_SPIN)
        lea     task_s_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
        lea     task_q2(pc),a2       ; spinner-2 (counter Q2_RUNS + emits "M7H QUANTUM OK")
        lea     task_q2_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
                else
                ifeq    PROD            ; PROD: M7 demo tasks (scheduler proofs: H/L/S/timer/port/fa/fb) -> out of prod
        lea     task_h(pc),a2        ; task_H (pri 10) -> head (Enqueue sorts), published
        lea     task_h_name(pc),a3
        moveq   #DEMO_PRI_H,d2
        bsr     mk_demo_task
        move.l  a4,WP_HTASK
        lea     task_l(pc),a2        ; task_L (pri 0): signals+yields+preemptible spin
        lea     task_l_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
                ifeq    M7E_COOP
        lea     task_s(pc),a2        ; task_S (pri 0): pure spinner (dispatched by preemption)
        lea     task_s_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task         ; M7E_COOP=1: removed (would hog the CPU without preemption)
        ; Forbid atomicity proof (SCHED_ON=1 only): fb (pri 7) created+published BEFORE fa (pri 3) so as to be in
        ; Wait when fa signals it under Forbid. fa checks that fb does NOT preempt its Forbid -> "FORBID ATOMIC OK".
        lea     task_fb(pc),a2       ; task_fb (pri 7): high-priority victim
        lea     task_fb_name(pc),a3
        moveq   #FB_PRI_FB,d2
        bsr     mk_demo_task
        move.l  a4,FB_TASK           ; publish fb's TCB (fa signals it)
        lea     task_fa(pc),a2       ; task_fa (pri 3): holds the Forbid + signals fb + checks the atomicity
        lea     task_fa_name(pc),a3
        moveq   #FB_PRI_FA,d2
        bsr     mk_demo_task
                endc
        lea     task_semw(pc),a2     ; task_semw (pri 5): blocks in ObtainSemaphore (semaphore held by the boot)
        lea     task_semw_name(pc),a3
        moveq   #5,d2
        bsr     mk_demo_task
        lea     task_semr(pc),a2     ; task_semr (pri 0): ReleaseSemaphore -> hands over to task_semw
        lea     task_semr_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
        lea     task_aud(pc),a2      ; task_aud (pri 5): DMA playback by audio.device ("AUDIO PLAY OK"); above
        lea     task_aud_name(pc),a3 ; the shell and the console, otherwise a boot that prints a lot starves it and it
        moveq   #5,d2                ; misses the "w1 returned, w2 in progress" window it must observe
        bsr     mk_demo_task
        lea     task_timer(pc),a2    ; task_timer (pri 10, M7a): blocks on the MICROHZ unit
        lea     task_t_name(pc),a3
        moveq   #DEMO_PRI_T,d2
        bsr     mk_demo_task
                ifeq    M7E_COOP
        lea     task_port(pc),a2     ; task_port (pri 0, M7d): hammers the shared port (TASK consumer)
        lea     task_p_name(pc),a3
        moveq   #DEMO_PRI_P,d2
        bsr     mk_demo_task         ; M7E_COOP=1: removed (pure spinner, would hog the CPU without preemption)
                endc
                endc                    ; end of the M7 demo tasks (PROD=0)
        ; --- D3a: create the file-handler process (echo) + the driver process (they run after dispatch_in) ---
        ; Created in BOTH modes (GREEN SCHED_ON=1 AND COOP): driver/handler block on WaitPort (synchronous
        ; M3d switch) -> cooperative packet round-trip. proc_create via jsr (process.o out of bsr range).
        ; HIGH-PRIORITY echo pair (8/7) above the OFS pair (6/5): its round-trip (fast, no disk)
        ; completes EARLY -> "D3A" emitted well before the slow OFS read -> no serial output concurrent with D3B.
                ifeq    PROD            ; PROD: D3a echo pair = packet round-trip proof (D3A) -> out of prod
        lea     d3a_hname(pc),a0
        lea     d3a_handler(pc),a1
        moveq   #8,d0                ; echo handler pri 8
        move.l  #D3_STK,d1
        jsr     proc_create
        move.l  d0,DOS_HANDLERPORT   ; publish the handler's port for the driver
        lea     d3a_dname(pc),a0
        lea     d3a_driver(pc),a1
        moveq   #7,d0                ; echo driver pri 7
        move.l  #D3_STK,d1
        jsr     proc_create
                endc                    ; end of the D3a echo pair (PROD=0)
        ; --- D3b: create the DF0: file-handler process (OFS) — INFRASTRUCTURE (the CLI resolves DF0: through it). The
        ; fs-driver that follows is a PROOF CLIENT (reads "kickslop" -> "D3B HANDLER OK") -> gated in prod. ---
        lea     d3b_hname(pc),a0
        move.l  #dos_handler,a1      ; absolute: handler.o linked out of 16-bit lea(pc) range
        moveq   #6,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        move.l  d0,DOS_FSPORT        ; publish the port of the OFS file-handler
                ifeq    PROD            ; PROD: fs-driver = D3b proof client (reads kickslop) -> out of prod; the handler stays
        lea     d3b_dname(pc),a0
        lea     dos_fsdriver(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
                endc                    ; end of the D3b proof fs-driver (PROD=0)
        ; --- D3c: mount a DF0: DeviceNode in DosInfo.di_DevInfo (dn_Task = OFS handler port) + dos client ---
        lea     EB_LIBLIST(a6),a0
        lea     dos_libname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .d3c_noclient        ; no dos.library (should not happen) -> no client
        move.l  d0,a2                ; a2 = DosBase
        move.l  DOS_FSPORT,d0        ; dn_Task = port of the OFS file-handler process
        moveq   #0,d1
        bsr     fl_node
        beq     .d3c_noclient
        move.l  a0,a3                ; a3 = DeviceNode of DF0:
        move.l  DL_ROOT(a2),a0       ; RootNode (APTR)
        move.l  RN_INFO(a0),d0       ; BPTR DosInfo
        lsl.l   #2,d0
        move.l  d0,a0                ; DosInfo
        move.l  a3,d0
        lsr.l   #2,d0                ; BPTR(DeviceNode)
        move.l  d0,DI_DEVINFO(a0)    ; di_DevInfo = BPTR(DeviceNode) -> dos Open resolves DF0: through this node
        bsr     mount_df1
                ifeq    PROD            ; PROD: D3 test clients (d3c..d3j read kickslop/D3DTest/bigseg/BigData,
                                        ; absent from a real Workbench disk) -> out of prod; the DF0: MOUNT above stays
        lea     d3c_cname(pc),a0
        lea     d3c_client(pc),a1
        moveq   #4,d0                ; client pri 4 (blocks on packets; below echo/OFS)
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3d: client that loads+executes "D3DTest" THROUGH dos (Open/Read by packets -> ls_load_hunks -> run)
        lea     d3d_cname(pc),a0
        lea     d3d_client(pc),a1
        moveq   #3,d0                ; pri 3 (below the D3c client)
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3e: client that loads "D3DTest" via the REAL LVO vector LoadSeg(-150) of dos.library (which composes
        ; Open/Read/Close + ls_load_hunks INTERNALLY) then UnLoadSeg(-156). Proves LoadSeg by LVO vector; d3d
        ; (inline load) remains the baseline independent of the layer below -> RED LOADSEG_LVO_UNWIRED isolates d3e.
        lea     d3e_cname(pc),a0
        lea     d3e_client(pc),a1
        moveq   #5,d0                ; pri 5: ABOVE the shell (Initial CLI pri 2) -> d3e loads+emits EARLY, outside
                                     ; the late startup-sequence window (otherwise its marker interleaves "E3 CMD RAN OK")
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3f: client proving IoErr(-132) + Seek(-66). pri 5 + emits under Forbid (same discipline as d3e: early,
        ; outside the startup window, atomic). IoErr: Open of a missing file -> 0 + IoErr != 0; Open d3dtest -> IoErr 0.
        ; Seek: Read 4 -> Seek(0,BEGINNING) -> Read 4 identical (repositioning).
        lea     d3f_cname(pc),a0
        lea     d3f_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3g: client proving CurrentDir(-126) + Input(-54) + Output(-60) + Write(-48). pri 5. CurrentDir/Input
        ; round-trip, then pr_COS = console FileHandle (fh_Type = DOS_CONPORT); Write(Output(), marker) -> the
        ; "DOS WRITE OK" marker is emitted BY the Write via con_handler (proves all 4 at once).
        lea     d3g_cname(pc),a0
        lea     d3g_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3h: client proving the LoadSeg cap-bump. Loads "bigseg" (> 16 KB) via LoadSeg(-150) + executes it:
        ; the binary checks a sentinel at the end of its big DATA and emits "LOADSEG BIG OK" if everything was read.
        lea     d3h_cname(pc),a0
        lea     d3h_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3i: client proving Lock(-84)/UnLock(-90)/Examine(-102)/ExNext(-108). pri 5 (same discipline: early, outside
        ; the startup window, emits under ser_lock). Lock("kickslop")->Examine (file, 1024 bytes); Lock(":")->ExNext finds
        ; kickslop by enumerating the root directory.
        lea     d3i_cname(pc),a0
        lea     d3i_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3j: client proving REAL OFS STREAMING. pri 5. Opens "BigData" (48000 bytes > old 32 KB cap), reads it
        ; entirely in chunks (incremental read without a whole-file buffer) + cross-block seek -> "OFS STREAM OK".
        lea     d3j_cname(pc),a0
        lea     d3j_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
                endc                    ; end of the D3 test clients (PROD=0)
        ; --- E1: serial console handler (pri 6, like the OFS handler). INFRASTRUCTURE -> created unconditionally.
        ; The shell (Initial CLI, F1) is NOT created here: it is GATED on a bootable disk (.m6r_booted branch).
        lea     e1_hname(pc),a0
        move.l  #con_handler,a1      ; absolute: conhandler.o linked out of 16-bit lea(pc) range
        moveq   #6,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        move.l  d0,DOS_CONPORT       ; publish the console handler's port
        ; --- keyboard feeder -> input.device (integration F, item 1): INFRASTRUCTURE, created unconditionally.
        ; Drains the raw keyboard ring (KBD_FEEDRING) and injects the RAWKEYs into input.device (IND_WRITEEVENT).
        lea     fd_cname(pc),a0
        move.l  #feeder_main,a1      ; absolute: feeder.o linked out of 16-bit lea(pc) range
        moveq   #4,d0                ; pri 4 (below the console handler)
        move.l  #D3_STK,d1
        jsr     proc_create
.d3c_noclient:
                ifne    M7J_DEMO
        ; M7j: capture AvailMem BEFORE creating task_rm (baseline); after its self-removal, AvailMem
        ; must go back up by at least M7J_RECOVER (stack+TCB freed). task_timer checks the increase.
        moveq   #0,d1                ; AvailMem(requirements=0) -> total free
        jsr     LVO_AVAILMEM(a6)
        move.l  d0,M7J_AVAIL_BEFORE
        lea     task_rm(pc),a2       ; task with a finite lifetime (RTS -> task_exit -> RemTask self)
        lea     task_rm_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
                endc
                endc
        movem.l (sp)+,d2/a2-a4
        rts

; setup_stress_port (M7d): creates the shared port + STRESS_K messages (MAGIC + IN_HAND=0), all AddTail'd
; on the port. a6 = SysBase. WP_SPORT is written LAST (once the port is ready) so that the MICROHZ
; service (which tests WP_SPORT) only sees it fully built. clobbers scratch + d2/a2 (saved).
setup_stress_port:
                ifne    PROD            ; PROD: no M7d stress; clears WP_SPORT -> the MICROHZ service sees it
        clr.l   WP_SPORT             ; null and skips the stress path (otherwise random power-up value = crash)
        rts
                endc
        movem.l d2/a2,-(sp)
        clr.l   WP_SPORT             ; (low RAM not guaranteed zero)
        clr.l   WP_PORTT
        clr.l   WP_PORTI
        clr.l   WP_PORTFAIL
        clr.b   M7D_STAT
        move.l  #MP_SIZE,d0          ; allocate the port
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7d_fail
        move.l  d0,a2                ; a2 = port
        move.b  #NT_MSGPORT,LN_TYPE(a2)
        move.b  #PA_IGNORE,MP_FLAGS(a2)   ; action != PA_SIGNAL -> PutMsg skips the signal path
        move.l  a2,a1                ; NEWLIST(&port->MsgList)
        lea     MP_MSGLIST(a2),a1
        jsr     newlist
        moveq   #STRESS_K,d2         ; d2 = counter of messages to create
.sp_loop:
        move.l  #STRESS_MSG_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7d_fail
        move.l  d0,a1                ; a1 = message
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.l  #STRESS_MAGIC,MSG_MAGIC_OFF(a1)   ; MAGIC; IN_HAND already 0 (MEMF_CLEAR)
        lea     MP_MSGLIST(a2),a0    ; AddTail(&port->MsgList, msg)
        jsr     LVO_ADDTAIL(a6)
        subq.l  #1,d2
        bne.s   .sp_loop
        move.l  a2,WP_SPORT          ; port ready -> published LAST
        movem.l (sp)+,d2/a2
        rts

; --- D3a: body of the ECHO file-handler process + of the driver process (process proof + packet round-trip) ---
; The bodies start with GPRs at zero (AddTask frame) -> reload SysBase from ($4).w. The handler loops
; WaitPort/GetMsg on ITS pr_MsgPort and returns dp_Res1 = dp_Arg1 (echo). The driver sets up a StandardPacket,
; PutMsg to the handler's port, WaitPort(its port)/GetMsg, checks the echo, emits "D3A", then blocks forever.
; Round-trip via WaitPort = SYNCHRONOUS switch (M3d) -> works in GREEN (preemption) AND in COOP.
d3a_handler:
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a2
        lea     PR_MSGPORT(a2),a2    ; a2 = pr_MsgPort of the handler (its own)
.h_loop:
        move.l  a2,a0
        jsr     LVO_WAITPORT(a6)     ; blocks until a message arrives
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)       ; d0 = Message | 0
        tst.l   d0
        beq.s   .h_loop
        move.l  d0,a1                ; a1 = Message (= &sp_Msg)
        move.l  LN_NAME(a1),a3       ; a3 = &sp_Pkt (convention: msg->ln_Name -> DosPacket)
                ifeq    D3A_NO_REPLY
        move.l  DP_ARG1(a3),DP_RES1(a3)   ; ECHO: res1 = arg1
        jsr     LVO_REPLYMSG(a6)     ; back to mn_ReplyPort (the driver's port)
                endc                 ; RED D3A_NO_REPLY: does not reply -> the driver stays blocked -> "D3A" absent
        bra.s   .h_loop
d3a_driver:
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a4
        lea     PR_MSGPORT(a4),a4    ; a4 = pr_MsgPort of the driver (reply port)
        move.l  #SP_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .d_block
        move.l  d0,a2                ; a2 = StandardPacket (&sp_Msg)
        lea     SP_PKT(a2),a3        ; a3 = &sp_Pkt (DosPacket)
        move.b  #NT_MESSAGE,LN_TYPE(a2)
        move.l  a4,MN_REPLYPORT(a2)  ; ReplyMsg will come back here
        move.w  #DP_SIZEOF,MN_LENGTH(a2)
        move.l  a3,LN_NAME(a2)       ; sp_Msg.ln_Name -> sp_Pkt
        move.l  a2,DP_LINK(a3)
        move.l  a4,DP_PORT(a3)
        move.l  #ACTION_READ,DP_TYPE(a3)   ; test value (echo does not interpret it)
        move.l  #$D3A0CAFE,DP_ARG1(a3)     ; magic to echo
        move.l  DOS_HANDLERPORT,a0
        move.l  a2,a1
        jsr     LVO_PUTMSG(a6)       ; PutMsg(handlerPort, &sp_Msg) -> signals the handler
        move.l  a4,a0
        jsr     LVO_WAITPORT(a6)     ; waits for the reply (synchronous switch -> handler)
        move.l  a4,a0
        jsr     LVO_GETMSG(a6)
        lea     SP_PKT(a2),a3
        cmp.l   #$D3A0CAFE,DP_RES1(a3)    ; correct echo?
        bne.s   .d_free
        jsr     LVO_FORBID(a6)       ; atomic output (avoids serial interleaving with the fs-driver)
        lea     msg_d3a_ok(pc),a0
        bsr     ser_puts             ; "D3A ... OK"
        jsr     LVO_PERMIT(a6)
.d_free:
        move.l  a2,a1
        move.l  #SP_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.d_block:
        moveq   #0,d0                ; done -> block forever (does not spin)
        jsr     LVO_WAIT(a6)
        bra.s   .d_block

; --- D3b: body of the fs-driver — opens/reads/closes "kickslop" THROUGH the DF0: file-handler process via packets ---
; FINDINPUT(BPTR fh, 0, BSTR name) -> DOSTRUE + fh_Arg1 = key; READ(key, buf, 1024) -> 1024 + markers;
; END(key). Emits "D3B" if all OK. Uses dos_sendpkt (process.s). a5 = block, d6 = success flag, d7 = key.
dos_fsdriver:
        move.l  ($4).w,a6
        move.l  #FSD_TOTAL,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .fd_block
        move.l  d0,a5                ; a5 = block (persistent)
        moveq   #0,d6                ; d6 = success flag
        ; build the BSTR name {8,"kickslop"} at a5+FSD_NAME
        lea     FSD_NAME(a5),a1
        move.b  #8,(a1)+
        lea     fsd_name_src(pc),a0
        moveq   #8-1,d0
.fd_ncpy:
        move.b  (a0)+,(a1)+
        dbra    d0,.fd_ncpy
        ; --- FINDINPUT: arg1 = BPTR(fh), arg2 = 0, arg3 = BPTR(name) ---
        lea     FSD_SP(a5),a0
        move.l  DOS_FSPORT,a1
        move.l  #ACTION_FINDINPUT,d0
        move.l  a5,d1
        add.l   #FSD_FH,d1
        lsr.l   #2,d1                ; BPTR(FileHandle)
        moveq   #0,d2                ; lock 0 (root)
        move.l  a5,d3
        add.l   #FSD_NAME,d3
        lsr.l   #2,d3                ; BPTR(name)
        jsr     dos_sendpkt          ; d0 = dp_Res1
        cmp.l   #DOSTRUE,d0
        bne     .fd_free
        move.l  a5,a0                ; key = fh.FH_ARG1 (set by the handler)
        add.l   #FSD_FH,a0
        move.l  FH_ARG1(a0),d7       ; d7 = file key
        ; --- READ: arg1 = key, arg2 = buffer (APTR), arg3 = 1024 ---
        lea     FSD_SP(a5),a0
        move.l  DOS_FSPORT,a1
        move.l  #ACTION_READ,d0
        move.l  d7,d1
        move.l  a5,d2
        add.l   #FSD_BUF,d2          ; dest = buffer (APTR, NOT a BPTR)
        move.l  #1024,d3
        jsr     dos_sendpkt          ; d0 = bytes read
        cmp.l   #1024,d0
        bne.s   .fd_close
        lea     FSD_BUF(a5),a0       ; check the markers (same as D1: @0/@488/@976)
        cmp.l   #$44314F46,(a0)      ; "D1OF"
        bne.s   .fd_close
        cmp.l   #$534F4B30,4(a0)     ; "SOK0"
        bne.s   .fd_close
        cmp.l   #$534F4B31,492(a0)   ; "SOK1"
        bne.s   .fd_close
        cmp.l   #$534F4B32,980(a0)   ; "SOK2"
        bne.s   .fd_close
        moveq   #1,d6                ; success
.fd_close:
        ; --- END: arg1 = key (always closes, even if READ failed) ---
        lea     FSD_SP(a5),a0
        move.l  DOS_FSPORT,a1
        move.l  #ACTION_END,d0
        move.l  d7,d1
        moveq   #0,d2
        moveq   #0,d3
        jsr     dos_sendpkt
        tst.l   d6
        beq.s   .fd_free
        jsr     LVO_FORBID(a6)       ; atomic output (avoids serial interleaving with the echo-driver)
        lea     msg_d3b_ok(pc),a0
        bsr     ser_puts             ; "D3B ... OK"
        jsr     LVO_PERMIT(a6)
.fd_free:
        move.l  a5,a1
        move.l  #FSD_TOTAL,d0
        jsr     LVO_FREEMEM(a6)
.fd_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .fd_block

; --- D3c: body of the dos client process — OpenLibrary(dos) + Open/Read/Close "kickslop" via the dos LVOs ---
; Proves the user-facing dos layer (Open/Read/Close build the packets to the handler, called from a
; PROCESS that supplies its pr_MsgPort as reply port). a4 = DosBase, a5 = buffer, d6 = bytes, d7 = BPTR fh.
d3c_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)  ; DosBase | 0
        tst.l   d0
        beq     .c_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  #2048,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .c_closelib
        move.l  d0,a5                ; a5 = read buffer
        move.l  a4,a6                ; a6 = DosBase for the dos calls
        lea     ofs_test_name(pc),a0
        move.l  a0,d1                ; name = "kickslop" (C-string)
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)     ; d0 = BPTR FileHandle | 0
        tst.l   d0
        beq     .c_free
        move.l  d0,d7                ; d7 = BPTR fh
        move.l  d7,d1
        move.l  a5,d2
        move.l  #1024,d3
        jsr     DOS_LVO_READ(a6)     ; d0 = bytes read
        move.l  d0,d6
        move.l  d7,d1
        jsr     DOS_LVO_CLOSE(a6)
        move.l  ($4).w,a6            ; -> SysBase (ser_puts / Forbid / FreeMem)
        cmp.l   #1024,d6             ; complete file read via dos?
        bne.s   .c_free
        cmp.l   #$44314F46,(a5)      ; "D1OF"
        bne.s   .c_free
        cmp.l   #$534F4B30,4(a5)     ; "SOK0"
        bne.s   .c_free
        cmp.l   #$534F4B31,492(a5)   ; "SOK1"
        bne.s   .c_free
        cmp.l   #$534F4B32,980(a5)   ; "SOK2"
        bne.s   .c_free
        jsr     LVO_FORBID(a6)
        lea     msg_d3c_ok(pc),a0
        bsr     ser_puts             ; "D3C ... OK"
        jsr     LVO_PERMIT(a6)
.c_free:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #2048,d0
        jsr     LVO_FREEMEM(a6)
.c_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.c_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .c_block

; --- D3d: body of the client — loads "D3DTest" THROUGH dos (Open/Read by packets) then EXECUTES it ---
; OpenLibrary(dos); dos Open/Read/Close "d3dtest" into a filebuf; ls_load_hunks(filebuf,size) -> seglist;
; JSR (seglist<<2)+4 -> the command emits "D3D LOADSEG-VIA-DOS OK" from RAM. Proves the complete chain
; "load a command via dos". a4=DosBase, a5=filebuf, d6=size, d7=fh then BPTR seglist.
d3d_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .q_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  #16384,d0            ; filebuf (>= size of a hunk executable)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .q_closelib
        move.l  d0,a5                ; a5 = filebuf
        move.l  a4,a6                ; a6 = DosBase for the dos calls
        lea     d3d_fname(pc),a0
        move.l  a0,d1                ; "d3dtest"
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)     ; BPTR fh | 0
        tst.l   d0
        beq     .q_free
        move.l  d0,d7                ; d7 = BPTR fh
        move.l  d7,d1
        move.l  a5,d2                ; buffer
        move.l  #16384,d3            ; len (the handler returns the real size)
        jsr     DOS_LVO_READ(a6)     ; d0 = bytes read = file size
        move.l  d0,d6
        move.l  d7,d1
        jsr     DOS_LVO_CLOSE(a6)
        move.l  ($4).w,a6            ; -> SysBase
        tst.l   d6
        beq     .q_free              ; nothing read
        move.l  a5,a0
        move.l  d6,d0
        jsr     ls_load_hunks        ; d0 = BPTR seglist | 0 (jsr: loadseg.o far away)
        tst.l   d0
        beq     .q_free
        move.l  d0,d7                ; d7 = BPTR seglist
                ifeq    D3D_NO_RUN
        move.l  d7,d0                ; entry = (seglist<<2)+4 = contents of the 1st hunk (CODE)
        lsl.l   #2,d0
        addq.l  #4,d0
        move.l  d0,a0
        bsr     ser_lock             ; the loaded binary prints under Forbid -> its marker stays atomic
        jsr     (a0)                 ; executes D3DTest -> emits "D3D LOADSEG-VIA-DOS OK"
        bsr     ser_unlock
        move.l  ($4).w,a6            ; reload SysBase (the loaded code may have clobbered a6)
                endc                 ; RED D3D_NO_RUN: skips the run -> command not executed -> D3D absent
        move.l  d7,d0
        jsr     dos_unloadseg        ; free the seglist
.q_free:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #16384,d0
        jsr     LVO_FREEMEM(a6)
.q_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.q_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .q_block

; d3e_client: loads "D3DTest" via the REAL LVO vector LoadSeg(-150) of dos.library (which opens/reads/parses/relocs
; INTERNALLY via Open/Read), proves a non-null seglist ("D3E LOADSEG LVO OK"), then UnLoadSeg(-156). Does NOT
; re-execute the program (d3d already does) -> no double marker. a6 = SysBase on entry (process body).
d3e_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   .e_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  a4,a6
        lea     d3d_fname(pc),a0     ; "d3dtest" (same executable as d3d, proven loadable)
        move.l  a0,d1
        jsr     DOS_LVO_LOADSEG(a6)  ; -150: opens+reads+parses hunks+relocs via Open/Read -> BPTR seglist | 0
        tst.l   d0
        beq.s   .e_closelib          ; RED LOADSEG_LVO_UNWIRED: -150 = dos_null -> 0 -> no marker
        move.l  d0,d7                ; d7 = BPTR seglist (non-null = loaded+relocated via the LVO vector)
        move.l  ($4).w,a6            ; emit the marker under Forbid (atomicity vs the other serial printers)
        jsr     LVO_FORBID(a6)
        lea     msg_d3e_loadseg(pc),a0
        bsr     ser_puts             ; "D3E LOADSEG LVO OK"
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        move.l  a4,a6
        move.l  d7,d1
        jsr     DOS_LVO_UNLOADSEG(a6) ; -156: frees the seglist
.e_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.e_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .e_block

; d3f_client: proves IoErr(-132) + Seek(-66) via the real LVO vectors. a6 = SysBase on entry (process body).
d3f_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .f_block
        move.l  d0,a4                ; a4 = DosBase
        ; IoErr: Open of an ABSENT name -> 0 then IoErr != 0
        move.l  a4,a6
        lea     d3f_badname(pc),a0
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        tst.l   d0
        bne     .f_closelib          ; wrongly opened an absent name -> abort
        move.l  a4,a6
        jsr     DOS_LVO_IOERR(a6)    ; must be != 0 (ERROR_OBJECT_NOT_FOUND); RED DOS_NO_IOERR -> 0
        tst.l   d0
        beq     .f_closelib
        ; Open d3dtest; IoErr must go back to 0
        move.l  a4,a6
        lea     d3d_fname(pc),a0
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        tst.l   d0
        beq     .f_closelib
        move.l  d0,d7                ; d7 = BPTR fh
        move.l  a4,a6
        jsr     DOS_LVO_IOERR(a6)    ; must be 0 after a successful Open
        tst.l   d0
        bne     .f_close
        ; Seek: Read 4 @0 -> Seek(0,BEGINNING) -> Read 4 identical
        lea     -8(sp),sp            ; 2 buffers of 4 bytes (buf1=sp, buf2=sp+4)
        move.l  a4,a6
        move.l  d7,d1
        move.l  sp,d2
        moveq   #4,d3
        jsr     DOS_LVO_READ(a6)     ; reads 4 @ pos 0 -> buf1
        cmp.l   #4,d0
        bne     .f_free8
        move.l  a4,a6                ; Seek(fh, 0, OFFSET_BEGINNING) -> old pos (= 4)
        move.l  d7,d1
        moveq   #0,d2
        moveq   #OFFSET_BEGINNING,d3
        jsr     DOS_LVO_SEEK(a6)
        cmp.l   #4,d0                ; Seek returns the OLD position (4); RED HND_NO_SEEK -> 4 too but pos not reset
        bne     .f_free8
        move.l  a4,a6                ; Read 4 again -> buf2
        move.l  d7,d1
        move.l  sp,d2
        addq.l  #4,d2
        moveq   #4,d3
        jsr     DOS_LVO_READ(a6)
        cmp.l   #4,d0
        bne     .f_free8
        move.l  (sp),d0              ; buf1 == buf2? (Seek did bring it back to the start)
        cmp.l   4(sp),d0
        bne     .f_free8
        lea     8(sp),sp
        move.l  ($4).w,a6            ; success -> emit under Forbid (serial atomicity)
        jsr     LVO_FORBID(a6)
        lea     msg_d3f_ok(pc),a0
        bsr     ser_puts             ; "DOS IOERR SEEK OK"
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        bra.s   .f_close
.f_free8:
        lea     8(sp),sp
.f_close:
        move.l  a4,a6
        move.l  d7,d1
        jsr     DOS_LVO_CLOSE(a6)
.f_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.f_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .f_block

; d3g_client: proves CurrentDir(-126) + Input(-54) + Output(-60) + Write(-48). a6 = SysBase on entry (process).
d3g_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .g_block
        move.l  d0,a4                ; a4 = DosBase
        ; CurrentDir round-trip: set $1234, then 0 (must return $1234)
        move.l  a4,a6
        move.l  #$1234,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        move.l  a4,a6
        moveq   #0,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        cmp.l   #$1234,d0
        bne     .g_closelib
        ; Input: set pr_CIS = $5678, read back via Input()
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  #$5678,PR_CIS(a0)
        move.l  a4,a6
        jsr     DOS_LVO_INPUT(a6)
        cmp.l   #$5678,d0
        bne     .g_closelib
        ; console FileHandle (fh_Type = DOS_CONPORT) for Output/Write
        move.l  DOS_CONPORT,d7
        tst.l   d7
        beq     .g_closelib          ; no console
        move.l  ($4).w,a6
        move.l  #FH_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .g_closelib
        move.l  d0,a5                ; a5 = FileHandle
        move.l  d7,FH_TYPE(a5)       ; fh_Type = con_handler port
        move.l  ($4).w,a0            ; pr_COS = BPTR(a5)
        move.l  EB_THISTASK(a0),a0
        move.l  a5,d0
        lsr.l   #2,d0
        move.l  d0,PR_COS(a0)
        move.l  a4,a6                ; Output() must return BPTR(a5)
        jsr     DOS_LVO_OUTPUT(a6)
        move.l  a5,d1
        lsr.l   #2,d1
        cmp.l   d1,d0
        bne.s   .g_free
        move.l  d0,d1                ; Write(Output() [BPTR], msg, len)
        move.l  #msg_dos_write,d2
        move.l  #msg_dos_write_len,d3
        move.l  a4,a6
        jsr     DOS_LVO_WRITE(a6)    ; con_handler emits "DOS WRITE OK" on serial (= the marker)
.g_free:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #FH_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.g_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.g_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .g_block

; d3h_client: proves the LoadSeg cap-bump. Loads "bigseg" (> 16 KB) via LoadSeg(-150) + executes it (the binary
; checks the sentinel at the end of its big DATA -> emits "LOADSEG BIG OK" IFF everything was read). a6 = SysBase on entry.
d3h_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .h_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  a4,a6
        lea     d3h_fname(pc),a0     ; "bigseg"
        move.l  a0,d1
        jsr     DOS_LVO_LOADSEG(a6)  ; -150: loads the executable > 16 KB (cap 32 KB)
        tst.l   d0
        beq.s   .h_closelib
        move.l  d0,d7                ; d7 = BPTR seglist
        move.l  d7,d0                ; entry = (seglist<<2)+4
        lsl.l   #2,d0
        addq.l  #4,d0
        move.l  d0,a0
        bsr     ser_lock             ; the binary prints under Forbid -> atomic marker
        jsr     (a0)                 ; executes bigseg -> "LOADSEG BIG OK" if the sentinel (end of the big DATA) is right
        bsr     ser_unlock
        move.l  ($4).w,a6
        move.l  a4,a6
        move.l  d7,d1
        jsr     DOS_LVO_UNLOADSEG(a6)
.h_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.h_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .h_block

; d3i_client: proves Lock(-84) + UnLock(-90) + Examine(-102) + ExNext(-108) via the real LVO vectors. a6 = SysBase
; on entry (process body). (A) Lock("kickslop") -> Examine -> fib: DirEntryType < 0 (file) AND Size == 1024
; (ORACLE byte_size@324 confirmed on the ADF). (B) Lock(":") [root] -> Examine -> DirEntryType > 0 (directory) ->
; ExNext in a loop -> finds the 1024-byte file entry (= kickslop specifically, advisor note). The enumeration
; cursor lives in the lock (flp_Bucket/flp_ChainBlk) -> documented deviation (the real OS keeps it in the FIB).
d3i_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .i_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  ($4).w,a6            ; long-aligned FileInfoBlock (AllocMem -> reversible BPTR)
        move.l  #FIB_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .i_closelib
        move.l  d0,a5                ; a5 = fib
        ; --- (A) Examine a FILE: Lock("kickslop") ---
        move.l  a4,a6
        lea     ofs_test_name(pc),a0 ; "kickslop"
        move.l  a0,d1
        move.l  #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)     ; -84 -> BPTR lock
        tst.l   d0
        beq     .i_freefib
        move.l  d0,d6                ; d6 = BPTR lock (file)
        move.l  a4,a6
        move.l  d6,d1
        move.l  a5,d2               ; fib
        jsr     DOS_LVO_EXAMINE(a6)  ; -102
        tst.l   d0
        beq     .i_unlockfile
        move.l  FIB_DIRENTRYTYPE(a5),d0
        bpl     .i_unlockfile        ; >= 0 -> not a file
        move.l  FIB_SIZE(a5),d0
        cmp.l   #1024,d0            ; ORACLE: size read @324 -> write@124 -> readback
        bne     .i_unlockfile
        moveq   #1,d3               ; d3 = (A) file OK
        bra.s   .i_fileok
.i_unlockfile:
        moveq   #0,d3
.i_fileok:
        move.l  a4,a6               ; UnLock(file)
        move.l  d6,d1
        jsr     DOS_LVO_UNLOCK(a6)   ; -90
        tst.l   d3
        beq     .i_freefib
        ; --- (B) Examine + ExNext a DIRECTORY: Lock(":") ---
        move.l  a4,a6
        lea     d3i_rootname(pc),a0  ; ":"
        move.l  a0,d1
        move.l  #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        tst.l   d0
        beq     .i_freefib
        move.l  d0,d6               ; d6 = BPTR lock (root)
        move.l  a4,a6               ; Examine root -> must be a directory
        move.l  d6,d1
        move.l  a5,d2
        jsr     DOS_LVO_EXAMINE(a6)
        tst.l   d0
        beq     .i_unlockroot
        move.l  FIB_DIRENTRYTYPE(a5),d0
        ble     .i_unlockroot        ; <= 0 -> not a directory
        moveq   #0,d4               ; d4 = "kickslop found by ExNext" flag
        moveq   #24,d5              ; iteration cap (anti-loop)
.i_exloop:
        move.l  a4,a6
        move.l  d6,d1
        move.l  a5,d2
        jsr     DOS_LVO_EXNEXT(a6)   ; -108
        tst.l   d0
        beq.s   .i_exdone            ; DOSFALSE -> end of enumeration (ERROR_NO_MORE_ENTRIES)
        move.l  FIB_DIRENTRYTYPE(a5),d0
        bpl.s   .i_exnextit          ; directory -> not kickslop
        move.l  FIB_SIZE(a5),d0
        cmp.l   #1024,d0            ; 1024-byte file entry = kickslop (unique on the ADF)
        bne.s   .i_exnextit
        moveq   #1,d4
.i_exnextit:
        subq.l  #1,d5
        bne.s   .i_exloop
.i_exdone:
        move.l  a4,a6               ; UnLock(root)
        move.l  d6,d1
        jsr     DOS_LVO_UNLOCK(a6)
        tst.l   d4
        beq.s   .i_freefib           ; enumeration did not find kickslop
        bsr     ser_lock             ; (A) && (B) OK -> emit under ser_lock (serial atomicity)
        lea     msg_d3i_ok(pc),a0
        bsr     ser_puts             ; "DOS LOCK EXAMINE OK"
        bsr     ser_unlock
        bra.s   .i_freefib
.i_unlockroot:
        move.l  a4,a6
        move.l  d6,d1
        jsr     DOS_LVO_UNLOCK(a6)
.i_freefib:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #FIB_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.i_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.i_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .i_block

D3J_BUFSZ       EQU 4096             ; size of the read chunks (not a multiple of 488 -> crosses the data blocks)
D3J_SIZE        EQU 48000            ; size of BigData (> old 32 KB cap)

; d3j_client: proves REAL OFS STREAMING. Opens "BigData" (48000 bytes, > old whole-file cap DOS_FILEMAX=32 KB)
; via dos Open, reads it ENTIRELY in 4096-byte chunks (12 Reads, the cursor advances in the streaming state between
; calls), checks total == 48000 AND sentinel $B16B00B5 in the last 4 bytes. Then Seek(500, BEGINNING) +
; Read(4) == $A5EE3780 (cross-block seek: rewind + forward walk up to the block containing byte 500). The old
; whole-file handler would have truncated at 32 KB -> self-sufficient proof of the lifted cap. a6 = SysBase on entry.
; pri 5, under ser_lock.
d3j_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .j_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  ($4).w,a6
        move.l  #D3J_BUFSZ,d0        ; read buffer
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .j_closelib
        move.l  d0,a5               ; a5 = buffer
        move.l  a4,a6
        lea     d3j_fname(pc),a0     ; "BigData"
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        tst.l   d0
        beq     .j_freebuf
        move.l  d0,d7               ; d7 = BPTR fh
        moveq   #0,d5               ; d5 = total read
        moveq   #0,d4               ; d4 = last 4 bytes of the stream
.j_rloop:
        move.l  a4,a6
        move.l  d7,d1
        move.l  a5,d2
        move.l  #D3J_BUFSZ,d3
        jsr     DOS_LVO_READ(a6)    ; reads an incremental chunk (data block by data block on the handler side)
        tst.l   d0
        ble.s   .j_rdone            ; 0 (EOF) or error
        add.l   d0,d5               ; total += n
        cmp.l   #4,d0
        blo.s   .j_rloop            ; chunk < 4 bytes (cannot happen here) -> continue
        move.l  d0,d1
        subq.l  #4,d1               ; offset of the last 4 bytes of this chunk
        move.l  0(a5,d1.l),d4       ; d4 = last 4 bytes (= sentinel at the last chunk)
        bra.s   .j_rloop
.j_rdone:
        cmp.l   #D3J_SIZE,d5        ; total == 48000? (the old handler would have truncated at 32768)
        bne     .j_close
        cmp.l   #$B16B00B5,d4       ; sentinel read up to the end?
        bne     .j_close
        move.l  a4,a6               ; cross-block seek: Seek(500, BEGINNING)
        move.l  d7,d1
        move.l  #500,d2
        moveq   #OFFSET_BEGINNING,d3
        jsr     DOS_LVO_SEEK(a6)
        move.l  a4,a6               ; Read(4) @500
        move.l  d7,d1
        move.l  a5,d2
        moveq   #4,d3
        jsr     DOS_LVO_READ(a6)
        cmp.l   #4,d0
        bne.s   .j_close
        move.l  (a5),d0             ; long@500 expected $A5EE3780 (deterministic pattern)
        cmp.l   #$A5EE3780,d0
        bne.s   .j_close
        bsr     ser_lock            ; all OK -> emit under ser_lock
        lea     msg_d3j_ok(pc),a0
        bsr     ser_puts            ; "OFS STREAM OK"
        bsr     ser_unlock
.j_close:
        move.l  a4,a6
        move.l  d7,d1
        jsr     DOS_LVO_CLOSE(a6)
.j_freebuf:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #D3J_BUFSZ,d0
        jsr     LVO_FREEMEM(a6)
.j_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.j_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .j_block

; task_semw: blocks on "kicksem.test" (taken at boot); once woken, it must own it with a
; nesting of 1. It releases it then removes it and gives it back.
task_semw:
        move.l  ($4).w,a6
        lea     semt_name(pc),a1
        jsr     LVO_FINDSEMAPHORE(a6)
        tst.l   d0
        beq.s   .sw_fail
        move.l  d0,a2
        move.l  a2,a0
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  EB_THISTASK(a6),d0
        cmp.l   SEMT_OWNER(a2),d0
        bne.s   .sw_fail
        cmp.w   #1,SEMT_NEST(a2)
        bne.s   .sw_fail
        move.l  a2,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        cmp.w   #-1,SEMT_QC(a2)
        bne.s   .sw_fail
        move.l  a2,a1
        jsr     LVO_REMSEMAPHORE(a6)
        move.l  a2,a1
        moveq   #SEMT_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        lea     msg_semw_ok(pc),a0
        bra.s   .sw_out
.sw_fail:
        lea     msg_semw_fail(pc),a0
.sw_out:
        jsr     LVO_FORBID(a6)
        bsr     ser_puts
        jmp     LVO_PERMIT(a6)
; task_semr: releases the boot's hold (the owner is not checked, as in V34).
task_semr:
        move.l  ($4).w,a6
        lea     semt_name(pc),a1
        jsr     LVO_FINDSEMAPHORE(a6)
        tst.l   d0
        beq.s   .sr_r
        move.l  d0,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
.sr_r:
        rts

; task_aud: real CMD_WRITE on channel 0 (volume 0: DMA and interrupts without audible sound). w1 then w2 (30 cycles
; each) queued; ADCMD_WAITCYCLE must be returned before w1 (end of the 1st cycle), w1 before w2 (chaining
; through the queue), CMD_READ returns w1 during playback then 0, and the channel's DMA is cut at the end.
; Stack: 3 IOAudio (ioa1 = commands, w1, w2). d5 = order findings (b0 WAITCYCLE before w1, b1 w1 before w2).
task_aud:
        move.l  ($4).w,a6
        lea     -216(sp),sp
        move.l  sp,a3
        move.l  a3,a0
        moveq   #53,d0
.ta_clr:
        clr.l   (a0)+
        dbra    d0,.ta_clr
        moveq   #64,d0
        move.l  #MEMF_CHIP|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a4                ; a4 = sample (64 bytes of zeros in chip)
        tst.l   d0
        beq     .ta_fail0
        lea     audio_test_name(pc),a0
        moveq   #0,d0
        move.l  a3,a1
        moveq   #0,d1
        jsr     LVO_OPENDEVICE(a6)
        tst.b   d0
        bne     .ta_fail1
        move.l  IO_DEVICE(a3),a2
        move.l  a3,a1
        lea     aut_ch0(pc),a0
        moveq   #0,d0
        bsr     aut_alloc
        bne     .ta_fail
        lea     72(a3),a1            ; w1 and w2: same device, key and channel as ioa1
        moveq   #30,d2               ; ~210 ms: much more than a preemption quantum
        bsr     .ta_mkw
        lea     144(a3),a1
        moveq   #30,d2               ; "w1 returned, w2 in progress" window of ~210 ms, observable despite preemption
        bsr     .ta_mkw
        jsr     LVO_FORBID(a6)       ; start + CMD_READ + WAITCYCLE without preemption (IRQs stay active)
        lea     72(a3),a1
        bsr     aut_io               ; CMD_WRITE w1 (starts)
        lea     144(a3),a1
        bsr     aut_io               ; CMD_WRITE w2 (queued)
        move.l  a3,a1
        moveq   #2,d0                ; CMD_READ -> w1
        bsr     aut_cmd
        lea     72(a3),a0
        cmp.l   AUT_DATA(a3),a0
        bne     .ta_failp
        move.l  a3,a1                ; ADCMD_WAITCYCLE (asynchronous)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        clr.b   IO_FLAGS(a1)
        move.w  #14,IO_COMMAND(a1)
        bsr     aut_io
        jsr     LVO_PERMIT(a6)
        moveq   #0,d5
        move.l  #2000000,d4
.ta_poll:
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne.s   .ta_p1
        cmp.b   #NT_REPLYMSG,LN_TYPE+72(a3)
        beq.s   .ta_p1
        bset    #0,d5                ; WAITCYCLE returned, w1 still in progress
.ta_p1:
        cmp.b   #NT_REPLYMSG,LN_TYPE+72(a3)
        bne.s   .ta_p2
        cmp.b   #NT_REPLYMSG,LN_TYPE+144(a3)
        beq.s   .ta_p2
        bset    #1,d5                ; w1 returned, w2 still in progress
.ta_p2:
        cmp.b   #NT_REPLYMSG,LN_TYPE+144(a3)
        beq.s   .ta_end
        subq.l  #1,d4
        bne.s   .ta_poll
        bra     .ta_fail
.ta_end:
        cmp.b   #3,d5
        bne     .ta_fail
        tst.b   IO_ERROR+72(a3)
        bne     .ta_fail
        tst.b   IO_ERROR+144(a3)
        bne     .ta_fail
        btst    #0,$DFF003           ; DMACONR AUD0EN: channel cut
        bne     .ta_fail
        move.l  a3,a1
        move.b  #1,IO_UNIT+3(a1)
        moveq   #2,d0                ; CMD_READ -> no more write
        bsr     aut_cmd
        tst.l   AUT_DATA(a3)
        bne     .ta_fail
        jsr     LVO_FORBID(a6)
        lea     msg_audplay_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
        bra.s   .ta_free
.ta_failp:
        jsr     LVO_PERMIT(a6)
.ta_fail:
        jsr     LVO_FORBID(a6)
        lea     msg_audplay_fail(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.ta_free:
        move.l  a3,a1
        move.b  #1,IO_UNIT+3(a1)
        moveq   #9,d0                ; ADCMD_FREE
        bsr     aut_cmd
        move.l  a3,a1
        jsr     LVO_CLOSEDEVICE(a6)
.ta_fail1:
        move.l  a4,a1
        moveq   #64,d0
        jsr     LVO_FREEMEM(a6)
.ta_fail0:
        lea     216(sp),sp
        rts
; .ta_mkw: a1 = IOAudio to prepare as a CMD_WRITE of d2 cycles (period 400, volume 0, ADIOF_PERVOL).
.ta_mkw:
        move.l  a2,IO_DEVICE(a1)
        move.w  AUT_KEY(a3),AUT_KEY(a1)
        move.b  #1,IO_UNIT+3(a1)
        move.w  #3,IO_COMMAND(a1)
        move.b  #$10,IO_FLAGS(a1)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.l  a4,AUT_DATA(a1)
        moveq   #64,d0
        move.l  d0,AUT_LENGTH(a1)
        move.w  #400,AUT_PERIOD(a1)
        clr.w   AUT_VOLUME(a1)
        move.w  d2,AUT_CYCLES(a1)
        rts

; fl_node(d0 = port of the file-handler, d1 = trackdisk unit, a6) -> a0 = DeviceNode "DF<unit>" (dn_Type =
; DLT_DEVICE, FileSysStartupMsg: unit, "trackdisk.device", DD geometry), not linked; Z = 1 if no memory.
; Clobbers d0/d1/a1.
fl_node:
        movem.l d2-d3,-(sp)
        move.l  d0,d2
        move.l  d1,d3
        move.l  #DN_SIZEOF+4+FSSM_SIZEOF,d0  ; + BSTR "DFn" + FileSysStartupMsg (long-aligned: BPTR)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .fn_ret
        move.l  d0,a0                ; dn_Type = DLT_DEVICE = 0 via MEMF_CLEAR
        move.l  d2,DN_TASK(a0)
        move.l  #$03444630,d0        ; BSTR: length 3, "DF0" + unit
        add.l   d3,d0
        move.l  d0,DN_SIZEOF(a0)
        lea     DN_SIZEOF(a0),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a0)       ; dn_Name -> dos resolves "DFn:" through this node
        lea     DN_SIZEOF+4(a0),a1   ; FileSysStartupMsg
        move.l  d3,FSSM_UNIT(a1)
        lea     df0_device(pc),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_SIZEOF+4+FSSM_DEVICE(a0)
        lea     df0_environ(pc),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_SIZEOF+4+FSSM_ENVIRON(a0)
        lea     DN_SIZEOF+4(a0),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_STARTUP(a0)    ; Z = 0
.fn_ret:
        movem.l (sp)+,d2-d3          ; (movem does not touch the CCR)
        rts

; mount_df1(a3 = DeviceNode of DF0:, a6): if disk.resource identified a 3.5" drive as unit 1 (HRM external-drive
; protocol, read at its startup), a second file-handler process and its "DF1" DeviceNode, linked after DF0:. The
; handler takes its unit from the node (dn_Task = its port), linked before it first runs. Preserves everything.
mount_df1:
        movem.l d0-d1/a0-a1,-(sp)
        lea     diskres_test_name(pc),a1
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq.s   .m1_ret
        move.l  a6,-(sp)
        move.l  d0,a6
        moveq   #1,d0
        jsr     -30(a6)              ; GetUnitID(1) (disk.resource LVO -30)
        move.l  (sp)+,a6
        tst.l   d0                   ; DRT_AMIGA = 0
        bne.s   .m1_ret
        lea     df1_hname(pc),a0
        move.l  #dos_handler,a1
        moveq   #6,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        tst.l   d0
        beq.s   .m1_ret
        moveq   #1,d1
        bsr     fl_node
        beq.s   .m1_ret
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,DN_NEXT(a3)
.m1_ret:
        movem.l (sp)+,d0-d1/a0-a1
        rts
df1_hname:
        dc.b    "dos.handler.df1",0
        even

; mk_demo_task: a2 = PC of the body, a3 = name, d2.b = priority -> a4 = created TCB.
; AllocMem preserves a2/a3/d2; AddTask reads a2 (initPC) / a3 (finalPC=task_exit).
mk_demo_task:
        move.l  #TC_SIZE,d0          ; TCB + stack in tc_MemEntry (no DMA: slow RAM first)
        move.l  #DEMO_STK,d1
        jsr     task_alloc
        move.l  d0,a4                ; a4 = TCB
        move.l  a3,LN_NAME(a4)
        move.b  d2,LN_PRI(a4)
        move.l  #SYS_SIGALLOC,TC_SIGALLOC(a4)  ; bits 0-15 reserved -> AllocSignal returns 16+ (task_timer)
        move.l  a4,a1
        lea     task_exit(pc),a3     ; finalPC (a3 = name overwritten, already set in LN_NAME)
        jsr     LVO_ADDTASK(a6)      ; AddTask(a1=task, a2=initPC, a3=finalPC)
        rts

; Bodies of the M3f demo tasks — PROOF that periodic preemption and yield-on-Permit
; COEXIST (SCHED_ON=1), without context corruption. Deterministic, independent of the
; serial timing (the counters advance through scheduling, not through output).
;   task_H (pri 10): loop Wait(DEMO_SIG); WP_CONS++. Dispatched by task_L's yield.
;   task_L (pri 0): loop Forbid/Signal(task_H)/Permit(<-yield); WP_PROD++. Never blocks.
;   task_S (pri 0): PURE spinner (WP_SPIN++); NEVER blocks/signals/yields -> only runs
;                     if PREEMPTION shares the CPU (otherwise it would hog it -> RED).
; Each task keeps a sentinel in d7 (preserved by every switch) and re-checks it:
; corruption -> "M3F FAILED". "M3F LIVE" emitted ONCE when WP_CONS >= CONS_THRESH
; (repeated yield) AND WP_SPIN >= SPIN_THRESH (task_S ran via preemption).
; RED (SCHED_ON=0 = preemption OFF): task_S (or task_L) hogs the CPU -> task_L can
; no longer signal task_H -> WP_CONS freezes -> "M3F LIVE" never emitted (absent).
task_h:                              ; high priority (tasks start with a6=0)
        move.l  ($4).w,a6            ; SysBase (cf. AddTask frame which zero-fills the GPRs)
        move.l  #SENT_H,d7           ; context sentinel
.h_loop:
        moveq   #1,d0
        moveq   #DEMO_SIG,d1
        lsl.l   d1,d0               ; mask = 1 << DEMO_SIG (register shift: 68000 immediate <= 8)
        jsr     LVO_WAIT(a6)         ; BLOCKS until task_L's signal (dispatch via yield)
        cmp.l   #SENT_H,d7
        bne.w   demo_fail            ; context corrupted by a switch
        addq.l  #1,WP_CONS
        btst    #0,WP_STAT
        bne.s   .h_loop              ; marker already emitted
        move.l  WP_CONS,d0
        cmp.l   #CONS_THRESH,d0
        bcs.s   .h_loop              ; WP_CONS < threshold -> continue
        move.l  WP_SPIN,d0
        cmp.l   #SPIN_THRESH,d0
        bcs.s   .h_loop              ; WP_SPIN < threshold -> preemption not yet proven
        bset    #0,WP_STAT           ; mark emitted (only once)
        jsr     LVO_FORBID(a6)       ; unsplit output
        lea     msg_m3flive(pc),a0
        bsr     ser_puts
        tst.b   WP_UMODE             ; M7c: did a task observe itself in USER mode (SR bit S == 0)?
        beq.s   .h_noum
        lea     msg_m7c_ok(pc),a0
        bsr     ser_puts             ; "M7C USERMODE OK" (user mode + relocation + preemption proven)
.h_noum:
        jsr     LVO_PERMIT(a6)
        bra.s   .h_loop
task_l:                              ; low priority, never blocks
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_L,d7
.l_loop:
        jsr     LVO_FORBID(a6)       ; Signal under Forbid -> yield postponed to the Permit
        move.l  WP_HTASK,a1
        moveq   #1,d0
        moveq   #DEMO_SIG,d1
        lsl.l   d1,d0
        jsr     LVO_SIGNAL(a6)       ; wakes task_H + sets AttnResched (pri 10 > 0)
        jsr     LVO_PERMIT(a6)       ; <- YIELD: dispatches task_H immediately
        cmp.l   #SENT_L,d7
        bne.w   demo_fail
        addq.l  #1,WP_PROD
        bra.s   .l_loop
task_s:                              ; low priority, PURE spinner (never blocks/yields)
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_S,d7
        move.w  sr,d0                ; M7c: DIRECT proof of user mode (MOVE from SR not privileged
        and.w   #$2000,d0            ; on 68000) -> S bit expected at 0
        bne.w   demo_fail            ; S=1 => task in supervisor => user-mode regression (sentinel failed)
        move.b  #1,WP_UMODE          ; user mode confirmed (consumed by task_H -> "M7C USERMODE OK")
.s_loop:
        cmp.l   #SENT_S,d7
        bne.w   demo_fail            ; context corrupted by a PREEMPTION
        addq.l  #1,WP_SPIN
        move.l  #$00001000,d0
.s_spin:
        subq.l  #1,d0
        bne.s   .s_spin
        bra.s   .s_loop

; task_fb (pri 7, Forbid atomicity proof): BLOCKS on FB_SIG; when it runs, sets FORBID_TEST_FLAG=1.
; If it runs DURING task_fa's Forbid (pri 3), preemption did NOT respect Forbid (bug).
task_fb:
        move.l  ($4).w,a6            ; SysBase (GPRs zero-filled by the AddTask frame)
.fb_loop:
        moveq   #1,d0
        moveq   #FB_SIG,d1
        lsl.l   d1,d0                ; mask = 1 << FB_SIG (REGISTER shift: count > 8 OK on 68000)
        jsr     LVO_WAIT(a6)         ; blocks until task_fa's signal
        move.l  #1,FORBID_TEST_FLAG  ; "I ran" (observed by task_fa)
        bra.s   .fb_loop

; task_fa (pri 3, Forbid atomicity proof): takes Forbid, wakes task_fb (pri 7 > 3 -> arms AttnResched),
; waits 2 VBlanks UNDER Forbid (guarantees >= 1 IRQ exit during the Forbid, where intr_isr_defer could switch).
; If FORBID_TEST_FLAG stayed 0 -> task_fb did NOT preempt under Forbid -> "FORBID ATOMIC OK". Runs ONCE
; then blocks (no hogging). RED SCHED_NO_FORBID_GATE: fb preempts during the Forbid -> flag=1 -> absent.
task_fa:
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)       ; atomic output section to be proven
        clr.l   FORBID_TEST_FLAG
        move.l  FB_TASK,a1           ; wakes task_fb (pri 7 > current 3 -> exec_Signal sets AttnResched)
        moveq   #1,d0
        moveq   #FB_SIG,d1
        lsl.l   d1,d0
        jsr     LVO_SIGNAL(a6)
        move.l  VBL_COUNT,d2         ; waits for VBL_COUNT to advance by 2 (>= 1 VBlank IRQ exit during the Forbid)
        addq.l  #2,d2
.fa_wait:
        cmp.l   VBL_COUNT,d2
        bhi.s   .fa_wait             ; VBL_COUNT incremented by the VBlank IRQ (fires even under Forbid)
        tst.l   FORBID_TEST_FLAG     ; did task_fb run during the Forbid?
        bne.s   .fa_perm             ; yes -> Forbid violated -> do NOT emit
        lea     msg_forbid_ok(pc),a0
        bsr     ser_puts             ; "FORBID ATOMIC OK" (under the held Forbid -> atomic output)
.fa_perm:
        jsr     LVO_PERMIT(a6)       ; yield -> task_fb finally runs (sets the flag, too late to skew the proof)
.fa_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .fa_block

; task_q2 (M7h): 2nd ISOLATION spinner (pri 0; M7H_QUANTUM_DEMO config only). Rotation with task_s
; driven ONLY by the VBlank quantum (no higher-priority preemptor). Emits "M7H QUANTUM OK" when
; the expiration rate proves a quantum > 1 tick: QUANTUM_EXPIRE_N*2 < VBL_COUNT (GREEN N=4: ~VBL/4;
; RED N=1: ~VBL -> fails). Also checks that task_s ran (WP_SPIN>0) = real rotation.
task_q2:
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_Q2,d7
.q2_loop:
        cmp.l   #SENT_Q2,d7
        bne.w   demo_fail            ; context corrupted by a PREEMPTION
        addq.l  #1,Q2_RUNS
        btst    #0,M7H_STAT
        bne.s   .q2_spin             ; already emitted -> just spin
        move.l  VBL_COUNT,d0
        cmp.l   #M7H_MINTICKS,d0     ; enough ticks for a stable ratio?
        bcs.s   .q2_spin
        tst.l   WP_SPIN              ; did task_s (spinner-1) run? (real rotation, not hogged)
        beq.s   .q2_spin
        move.l  QUANTUM_EXPIRE_N,d1
        add.l   d1,d1                ; EXPIRE_N * 2
        cmp.l   VBL_COUNT,d1         ; EXPIRE_N*2 >= VBL_COUNT? (quantum ~1 tick -> RED)
        bcc.s   .q2_spin             ; yes -> quantum too short -> not proven
        bset    #0,M7H_STAT          ; EXPIRE_N*2 < VBL_COUNT -> quantum > ~2 ticks proven
        jsr     LVO_FORBID(a6)
        lea     msg_m7h_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.q2_spin:
        move.l  #$00001000,d0
.q2_delay:
        subq.l  #1,d0
        bne.s   .q2_delay
        bra.s   .q2_loop

; task_rm (M7j, pri 0; M7J_DEMO config only): task with a FINITE LIFETIME. Runs RM_THRESH times
; (RM_RUNS++) then does RTS -> finalPC task_exit -> RemTask(self) -> frees its stack + TCB and switches.
; Proves the life cycle: AvailMem goes back up after its self-removal (checked by task_timer).
task_rm:
        move.l  ($4).w,a6
        move.l  #SENT_RM,d7
.rm_loop:
        cmp.l   #SENT_RM,d7
        bne.w   demo_fail            ; context corrupted by a preemption
        addq.l  #1,RM_RUNS
        move.l  RM_RUNS,d0
        cmp.l   #RM_THRESH,d0
        bcc.s   .rm_done             ; RM_RUNS >= RM_THRESH -> terminate (RTS)
        move.l  #$00008000,d0        ; delay (lets the others' counters advance)
.rm_delay:
        subq.l  #1,d0
        bne.s   .rm_delay
        bra.s   .rm_loop
.rm_done:
        rts                          ; -> task_exit -> RemTask(self) (does not return)

; task_timer (pri 10, M7a): blocks on the MICROHZ unit (CIA-B/INT6). On each round, arms a
; short request (1 CIA-B tick), Waits on the reply port, checks the reply. Proves that a TASK
; wakes up on an interrupt timer (Wait->wake by the MICROHZ IRQ) AND watches VBL_CLASH:
; if INT6 preempted vbl_handler's list surgery (gate violated in RED), VBL_CLASH>0 ->
; "M7A FAILED". GREEN = TCONS_THRESH wake-ups accumulated with VBL_CLASH always == 0.
; Setup in task context (AllocSignal does operate on task_timer). a4=timer base, a3=reply port,
; a2=timerequest, d6=signal bit, d7=sentinel — all preserved by the exec calls (verified).
task_timer:
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_T,d7           ; context sentinel
        lea     EB_DEVICELIST(a6),a0 ; timer.device base
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a4                ; a4 = timer.device base
        moveq   #-1,d0               ; AllocSignal -> reply port bit (task_timer has SYS_SIGALLOC)
        jsr     LVO_ALLOCSIGNAL(a6)
        move.l  d0,d6                ; d6 = bit number
        move.l  #MP_SIZE,d0          ; reply port
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a3                ; a3 = reply port
        lea     MP_MSGLIST(a3),a1
        jsr     newlist
        move.b  #PA_SIGNAL,MP_FLAGS(a3)
        move.b  d6,MP_SIGBIT(a3)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a3)   ; signals itself
        move.l  #TR_SIZE,d0          ; timerequest
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a2                ; a2 = timerequest
        move.l  a3,MN_REPLYPORT(a2)
        move.l  a4,IO_DEVICE(a2)
        move.l  #UNIT_MICROHZ,IO_UNIT(a2)   ; MICROHZ unit (CIA-B/INT6)
        ; M7l — REAL us CALIBRATION (once, before the loop): a known LONG MICROHZ request
        ; (M7L_CAL_US = 0.5 s), measured against the VBLANK clock (50 Hz, INDEPENDENT: display raster vs
        ; CPU E-clock). 0.5 s of real us must elapse in ~25 VBLANK ticks. Out of band -> M7L not emitted
        ; (RED OLD_CONV: the request expires in ~0-1 tick); we still fall into the loop (M7A stays provable).
        move.l  VBL_COUNT,M7L_VBL_BEFORE    ; T0 on the VBLANK clock
        clr.l   TV_SECS(a2)
        move.l  #M7L_CAL_US,TV_MICRO(a2)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a2)
        move.l  a6,-(sp)             ; BeginIO(a4 = base, a2 = request)
        move.l  a4,a6
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
        moveq   #1,d0                ; Wait(1<<bit): BLOCKS until the calibration request expires
        move.l  d6,d1
        lsl.l   d1,d0
        jsr     LVO_WAIT(a6)
        move.l  a3,a0                ; GetMsg(reply port) -> must be OUR request
        jsr     LVO_GETMSG(a6)
        cmp.l   a2,d0
        bne     m7a_fail
        move.l  VBL_COUNT,d0         ; T1; elapsed = T1 - T0 (VBLANK ticks during 0.5 s of MICROHZ)
        sub.l   M7L_VBL_BEFORE,d0
        move.l  d0,M7L_ELAPSED
        cmp.l   #M7L_LO,d0           ; within the band [M7L_LO, M7L_HI]? (0.5 s ~= 25 ticks)
        bcs.s   .tt_cal_done         ; too fast (RED OLD_CONV) -> M7L not emitted, we continue
        cmp.l   #M7L_HI+1,d0
        bcc.s   .tt_cal_done         ; too slow (constant grossly wrong) -> M7L not emitted
        bset    #0,M7L_STAT          ; emits "M7L MICROHZ CALIB OK" only once
        jsr     LVO_FORBID(a6)
        lea     msg_m7l_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_cal_done:
        move.l  VBL_COUNT,d5         ; T0 (VBlank ticks at start; d5 preserved by the exec calls)
.tt_loop:
        cmp.l   #SENT_T,d7           ; context intact after each switch?
        bne     m7a_fail
        tst.l   VBL_CLASH            ; was the IPL7 gate violated? (RED -> != 0)
        bne     m7a_fail
        clr.l   TV_SECS(a2)          ; (re)arms a MICROHZ request of ~7 ms (TT_MICRO_REQ REAL us since M7l)
        move.l  #TT_MICRO_REQ,TV_MICRO(a2) ; 7000 us / 359 = 19 CIA-B ints -> ~140 wake-ups/s (coexists with M3f;
                                     ; a single int would preempt ~2800/s via the deferred dispatch and starve task_s/L)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a2)
        move.l  a6,-(sp)             ; BeginIO(a4 = base, a2 = request)
        move.l  a4,a6
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
        moveq   #1,d0                ; Wait(1<<bit): BLOCKS until the MICROHZ wake-up
        move.l  d6,d1
        lsl.l   d1,d0
        jsr     LVO_WAIT(a6)
        move.l  a3,a0                ; GetMsg(reply port)
        jsr     LVO_GETMSG(a6)
        cmp.l   a2,d0                ; must be OUR request
        bne     m7a_fail
        addq.l  #1,WP_TCONS          ; one more successful MICROHZ wake-up
        btst    #0,M7E_STAT          ; M7e: per-level IPL marker already emitted? (tested at every wake-up,
        bne.s   .tt_m7e_done         ; independently of the M7a flag; -> falls through to the M7F check (do NOT skip)
        move.l  VBL_PREEMPT_COUNT,d0 ; has INT6(6) already preempted the BODY of vbl(3)? (native IPL fidelity)
        beq.s   .tt_m7e_done         ; not yet observed -> not proven (but check M7F anyway)
        tst.l   VBL_CLASH            ; AND did the switch's surgery stay atomic? (must == 0)
        bne.s   .tt_m7e_done         ; clash -> the check at the top of the loop will take m7a_fail at the next round
        bset    #0,M7E_STAT          ; emits "M7E IPL OK" only once
        jsr     LVO_FORBID(a6)
        lea     msg_m7e_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_m7e_done:
        btst    #0,M7F_STAT          ; M7f: VERTB chain marker already emitted?
        bne.s   .tt_m7f_done         ; -> falls through to the M7G check (do NOT skip)
        move.l  VERTB_CHAIN_N,d0     ; did the walker walk the VERTB chain down to the TAIL (vbl_tail)?
        cmp.l   #VERTB_CHAIN_THRESH,d0  ; (proves sched_server pri 20 + timer_vblank pri 0 BEFORE vbl_tail pri -10)
        bcs.s   .tt_m7f_done         ; not yet enough complete chain walks (but check M7G)
        bset    #0,M7F_STAT          ; emits "M7F VERTB OK" only once
        jsr     LVO_FORBID(a6)
        lea     msg_m7f_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_m7f_done:
        btst    #0,M7G_STAT          ; M7g: multi-source marker already emitted?
        bne.s   .tt_m7g_done
        move.l  COPER_FIRED,d0       ; was the 2nd level 3 source (COPER) served via the decoding?
        cmp.l   #COPER_THRESH,d0
        bcs.s   .tt_m7g_done         ; not yet enough coper_test calls (but check M7J)
        bset    #0,M7G_STAT          ; emits "M7G MULTISRC OK" only once
        jsr     LVO_FORBID(a6)
        lea     msg_m7g_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_m7g_done:
        btst    #0,GP_LIVE_STAT      ; gameport: live VBlank mouse server already proven?
        bne.s   .tt_gp_done          ; -> falls through to the M7J check (do NOT skip)
        move.l  GP_POLLS,d0          ; does gp_vblank_server run on the REAL VBlanks of the running system?
        cmp.l   #GP_POLLS_THRESH,d0
        bcs.s   .tt_gp_done          ; not yet enough polls (check M7J anyway)
        bset    #0,GP_LIVE_STAT      ; emits "GP VBLANK LIVE OK" only once
        jsr     LVO_FORBID(a6)
        lea     msg_gp_live_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_gp_done:
        btst    #0,M7J_STAT          ; M7j: life-cycle marker already emitted?
        bne.s   .tt_m7a
        move.l  RM_RUNS,d0           ; has task_rm finished its iterations (then removed itself)?
        cmp.l   #RM_THRESH,d0
        bcs.s   .tt_m7a              ; not yet -> wait (in RED NOFREE we stay here: AvailMem frozen)
        moveq   #0,d1                ; AvailMem(now)
        jsr     LVO_AVAILMEM(a6)     ; (preserves d2-d7/a2-a6; clobbers d0/d1/a0/a1)
        move.l  M7J_AVAIL_BEFORE,d1
        sub.l   #M7J_RECOVER,d1      ; threshold = baseline - M7J_RECOVER
        cmp.l   d1,d0                ; AvailMem(now) >= baseline - RECOVER? (stack+TCB really freed)
        bcs.s   .tt_m7a              ; < threshold -> not back up (leak = RED) -> not proven
        bset    #0,M7J_STAT          ; emits "M7J REMTASK OK" only once
        jsr     LVO_FORBID(a6)
        lea     msg_m7j_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_m7a:
        btst    #1,WP_STAT
        bne     .tt_loop             ; marker already emitted (word branch: long loop body)
        move.l  WP_TCONS,d0
        cmp.l   #TCONS_THRESH,d0
        bcs     .tt_loop             ; not yet enough wake-ups
        move.l  VBL_COUNT,d0         ; AND enough time elapsed? (window in which a RED clash would have occurred)
        sub.l   d5,d0
        cmp.l   #M7A_MINTICKS,d0
        bcs     .tt_loop
        bset    #1,WP_STAT           ; emits "M7A TIMER OK" only once
        jsr     LVO_FORBID(a6)
        lea     msg_m7a_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
        bra     .tt_loop

; task_port (pri 0, M7d): TASK CONSUMER of the shared stress port. Tight GetMsg+PutMsg loop;
; the PRODUCER is timer_micro_service (INTERRUPT). Interrupt-safe ports (Disable) -> the
; GetMsg(task)/PutMsg(IRQ) race on the same MP_MSGLIST is safe. In RED (ports back to Forbid) it corrupts
; the list. Checks MAGIC (wrong pointer) + IN_HAND==0 (duplicate) on each message. a4 = port (preserved
; by GetMsg/PutMsg = scratch d0/d1/a0/a1). Emits "M7D PORTS OK" when both counters pass without failure.
task_port:
        move.l  ($4).w,a6
        move.l  #SENT_P,d7
        moveq   #0,d6                ; d6 = counter of CONSECUTIVE empty GetMsgs (lost node detector)
.pp_wait:
        move.l  WP_SPORT,a4          ; wait for the port to exist (created before the handoff -> already ready)
        move.l  a4,d0
        beq.s   .pp_wait
.pp_loop:
        cmp.l   #SENT_P,d7
        bne.w   demo_fail            ; context corrupted by a switch
        move.l  a4,a0                ; GetMsg(SP)
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .pp_empty            ; empty -> count (K messages circulate, the port is almost
        move.l  d0,a1                ; never empty; PROLONGED emptiness = nodes lost by corruption)
        cmp.l   #STRESS_MAGIC,MSG_MAGIC_OFF(a1)
        bne     m7d_fail             ; wrong pointer -> list corruption
        tst.l   MSG_INHAND_OFF(a1)
        bne     m7d_fail             ; already "in hand" -> duplicate = corruption
        move.l  #1,MSG_INHAND_OFF(a1)
        clr.l   MSG_INHAND_OFF(a1)
        move.l  a4,a0                ; PutMsg(SP, msg)
        jsr     LVO_PUTMSG(a6)
        addq.l  #1,WP_PORTT
        moveq   #0,d6                ; message obtained -> reset of the empty counter
        bra.s   .pp_emit
.pp_empty:
        addq.l  #1,d6
        cmp.l   #PEMPTY_LIMIT,d6
        bcc     m7d_fail             ; port empty for too long -> lost nodes = corruption
.pp_emit:
        btst    #0,M7D_STAT
        bne     .pp_loop             ; marker already emitted
        tst.l   WP_PORTFAIL          ; corruption seen on the interrupt side?
        bne     m7d_fail
        move.l  WP_PORTT,d0
        cmp.l   #PORTT_THRESH,d0
        bcs     .pp_loop             ; not enough iterations on the task side
        move.l  WP_PORTI,d0
        cmp.l   #PORTI_THRESH,d0
        bcs     .pp_loop             ; not enough on the interrupt side (producer)
        bset    #0,M7D_STAT
        jsr     LVO_FORBID(a6)
        lea     msg_m7d_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
        bra     .pp_loop
m7d_fail:                            ; port list corruption (RED) -> proof
        jsr     LVO_FORBID(a6)
        lea     msg_m7d_fail(pc),a0
        bsr     ser_puts
.m7df_hang:
        bra.s   .m7df_hang

demo_fail:                           ; sentinel failed -> proof of corruption
        jsr     LVO_FORBID(a6)
        lea     msg_m3ffail(pc),a0
        bsr     ser_puts
.df_hang:
        bra.s   .df_hang
task_exit:                           ; M7j: finalPC — a task did RTS (end of body) -> removes
        move.l  ($4).w,a6            ; itself via RemTask(self). RemTask does not return (switches).
        suba.l  a1,a1                ; a1 = 0 -> RemTask interprets NULL as the current task
        jsr     LVO_REMTASK(a6)
        bra.s   task_exit            ; safety net (must never be reached)

; ============================ demo residents (M4) ==================
; 3 ROMTags scanned by build_reslist then initialised by InitCode in DESCENDING
; PRIORITY order (hi=60, mid=10, lo=-20). Each one shares res_demo_init, which checks that its
; RT_PRI is NOT higher than the previous one (descending order maintained) then emits its
; name. Proof: names emitted hi->mid->lo in the log + RES_COUNT==3.
; IMPORTANT: stored in memory in an order (mid, lo, hi) DIFFERENT from the priority
; order, so that the SORT of build_reslist is load-bearing (otherwise the scan order
; would suffice). Non-AUTOINIT ROMTags (direct-init). EVEN alignment mandatory (the scan
; reads words at even addresses; RT_ENDSKIP must stay even).
        EVEN
res_mid:
        dc.w    RTC_MATCHWORD
        dc.l    res_mid              ; RT_MATCHTAG = self (validates the match)
        dc.l    res_mid_end          ; RT_ENDSKIP
        dc.b    RTF_COLDSTART,1,NT_RESOURCE,10   ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    res_mid_name         ; RT_NAME
        dc.l    res_mid_name         ; RT_IDSTRING
        dc.l    res_mid_init         ; RT_INIT (module's own routine)
res_mid_name:
        dc.b    "demo.res.mid",0
        EVEN
res_mid_end:
res_lo:
        dc.w    RTC_MATCHWORD
        dc.l    res_lo
        dc.l    res_lo_end
        dc.b    RTF_COLDSTART,1,NT_RESOURCE,-20
        dc.l    res_lo_name
        dc.l    res_lo_name
        dc.l    res_lo_init
res_lo_name:
        dc.b    "demo.res.lo",0
        EVEN
res_lo_end:
res_hi:
        dc.w    RTC_MATCHWORD
        dc.l    res_hi
        dc.l    res_hi_end
        dc.b    RTF_COLDSTART,1,NT_RESOURCE,60
        dc.l    res_hi_name
        dc.l    res_hi_name
        dc.l    res_hi_init
res_hi_name:
        dc.b    "demo.res.hi",0
        EVEN
res_hi_end:

; Init routines of the demo residents. Called by InitResident with the direct-init ABI
; convention (D0=0, A0=segList, A6=SysBase): the resident pointer is NOT supplied, so
; each routine knows its priority and name STATICALLY (like a real module). They
; pass (d0=signed pri, a1=name) to res_demo_common.
res_hi_init:
        moveq   #60,d0
        lea     res_hi_name(pc),a1
        bra.s   res_demo_common
res_mid_init:
        moveq   #10,d0
        lea     res_mid_name(pc),a1
        bra.s   res_demo_common
res_lo_init:
        moveq   #-20,d0
        lea     res_lo_name(pc),a1
        ; falls through into res_demo_common
; res_demo_common: d0 = RT_PRI (signed, longword via moveq), a1 = name. Checks the descending
; order via RES_LASTPRI, counts in RES_COUNT, emits the name + CRLF. Returns d0=0.
res_demo_common:
        cmp.l   RES_LASTPRI,d0
        bgt     res_fail             ; pri > previous -> ASCENDING order = scan/sort WRONG
        move.l  d0,RES_LASTPRI
        addq.l  #1,RES_COUNT
        move.l  a1,a0                ; name
        bsr     ser_puts             ; emits the name (visible order hi->mid->lo)
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        moveq   #0,d0
        rts

res_fail:                            ; M4 failure (scan/order/dispatch) -> freezes
        lea     msg_res_fail(pc),a0
        bsr     ser_puts
.resf_hang:
        bra.s   .resf_hang
auto_fail:                           ; M5a failure (AUTOINIT/MakeLibrary) -> freezes
        lea     msg_auto_fail(pc),a0
        bsr     ser_puts
.autof_hang:
        bra.s   .autof_hang
cia_fail:                            ; M5b failure (cia.resource) -> freezes
        lea     msg_cia_fail(pc),a0
        bsr     ser_puts
.ciaf_hang:
        bra.s   .ciaf_hang
timer_fail:                          ; M5c failure (timer.device) -> freezes
        lea     msg_timer_fail(pc),a0
        bsr     ser_puts
.tmrf_hang:
        bra.s   .tmrf_hang
m6a_fail:                            ; M6a failure (timer VBLANK unit) -> freezes
        lea     msg_m6a_fail(pc),a0
        bsr     ser_puts
.m6af_hang:
        bra.s   .m6af_hang
m7b_fail:                            ; M7b failure (by-number dispatcher / PORTS chain) -> freezes
        lea     msg_m7b_fail(pc),a0
        bsr     ser_puts
.m7bf_hang:
        bra.s   .m7bf_hang
m7a_fail:                            ; M7a failure (re-entry gate / MICROHZ unit) -> freezes
        jsr     LVO_FORBID(a6)       ; unsplit output (reached from the task context)
        lea     msg_m7a_fail(pc),a0
        bsr     ser_puts
.m7af_hang:
        bra.s   .m7af_hang
; test struct Interrupt (M6b): IS_CODE -> cia_test_vec (increments CIA_FIRED).
        EVEN
cia_test_int:
        dcb.b   14,0                 ; LN (not linked)
        dc.l    0                    ; IS_DATA
        dc.l    cia_test_vec         ; IS_CODE
cia_test_vec:                        ; ICR server (a1=data, a5=code, a6=SysBase)
        addq.l  #1,CIA_FIRED
        rts
cia_dummy_int:                       ; fake struct Interrupt (AddICRVector only stores the ptr)
        dc.l    0,0,0,0,0

; int2_srv2 (M7b): 2nd server of the PORTS chain (pri 0, after ciaa_server pri 10). Increments
; INT2_SRV2 and captures the order (CIA_FIRED > 0 at the 1st call => ciaa_server ran before = pri OK).
; a1=IS_DATA (unused), a6=SysBase. Preserves d2-d7/a2-a4 (only touches d0 + memory). Z SET (continue).
int2_srv2:
        addq.l  #1,INT2_SRV2
        tst.l   INT2_ORDER_SNAP      ; already captured?
        bne.s   .s2_z
        move.l  CIA_FIRED,d0         ; has ciaa_server (pri 10) already run in THIS INT2?
        beq.s   .s2_z                ; not yet -> we will capture at a later INT2
        move.l  d0,INT2_ORDER_SNAP   ; > 0 -> priority order confirmed (ciaa before srv2)
.s2_z:
        moveq   #0,d0                ; Z set -> continue the chain
        rts

; input_test_h1 / input_test_h2 (#2): test input.device handlers. Convention: a0 = InputEvent list,
; a1 = is_Data; returns d0 = list (pass-through). h1 (pri 10) runs before h2 (pri 0) -> INPUT_SEQ orders them.
; h1 also records the keycode of the 1st event (propagation proof). Clobbers d0 (+ memory); preserves a0-a6/d1-d7.
input_test_h1:
        addq.w  #1,INPUT_SEQ
        move.w  INPUT_SEQ,INPUT_H1_ORD   ; call order (must = 1)
        move.w  IE_CODE(a0),INPUT_CODE   ; keycode relayed by the chain
        move.l  a0,d0                    ; return the list unchanged
        rts
input_test_h2:
        addq.w  #1,INPUT_SEQ
        move.w  INPUT_SEQ,INPUT_H2_ORD   ; call order (must = 2)
        move.l  a0,d0
        rts

; gp_cap_handler(a0 = InputEvent list, a1 = is_Data) -> d0 = list: capture handler of the GAMEPORT block.
; Counts the RAWMOUSEs seen (GP_CAP_N) and remembers ie_Code/ie_X/ie_Y of the last one (single injected events ->
; head only). Scratch d0/d1/a1 only (preserves d2-d7/a2-a4, handler convention).
gp_cap_handler:
        move.l  a0,d1
        beq.s   .gc_ret
        move.l  a0,a1
        cmp.b   #IECLASS_RAWMOUSE,IE_CLASS(a1)
        bne.s   .gc_ret
        addq.w  #1,GP_CAP_N
        move.w  IE_CODE(a1),GP_CAP_CODE
        move.w  IE_X(a1),GP_CAP_DX
        move.w  IE_Y(a1),GP_CAP_DY
.gc_ret:
        move.l  a0,d0
        rts

; disk_watch: process of the insert-disk screen (pri -1). Every DW_TICKS: td_disk_present; an inserted
; floppy (drive previously seen empty) -> cold reboot (Supervisor: RESET then jump to the ROM entry): the boot
; then finds it as at power-on. Does not return.
DW_TICKS        EQU 25               ; 0.5 s between two polls
DW_STK          EQU 1024
disk_watch:
        move.l  ($4).w,a6
        moveq   #0,d7                ; d7 != 0: drive seen empty (a non-bootable floppy already present does not
.dw_lp:                              ; reboot the machine: it must be removed and then another one inserted)
        move.l  DOS_DOSBASE,a6
        moveq   #DW_TICKS,d1
        jsr     DOS_LVO_DELAY(a6)
        move.l  ($4).w,a6
        jsr     td_disk_present
        tst.l   d0
        bne.s   .dw_in
        moveq   #-1,d7
        bra.s   .dw_lp
.dw_in:
        tst.l   d7
        beq.s   .dw_lp
        lea     dw_reboot(pc),a5
        jsr     LVO_SUPERVISOR(a6)   ; does not return
        bra.s   .dw_lp
; dw_reboot (supervisor): RESET reinitialises the chips (the overlay puts the ROM back at $0); the JMP must be in the
; same long word as the RESET (already prefetched). Entry = initial PC of the ROM (long at $FC0004).
        cnop    0,4
dw_reboot:
        move.w  #$2700,sr
        move.l  ($FC0004).l,a0
        bra.s   dw_rst
        cnop    0,4
dw_rst:
        reset
        jmp     (a0)
dw_name:
        dc.b    "DF0 watch",0
        even

; ptr_wire: installs the PERSISTENT pointer handler (PTR_INT, pri 50) on input.device: RAWMOUSE deltas ->
; absolute position PTR_X/PTR_Y + pointer sprite. Called on both boot branches (insert-disk and floppy).
; a6 = SysBase. Preserves d2-d7/a2-a6.
ptr_wire:
        movem.l a2/a4,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .pw_ret
        move.l  d0,a4
        clr.l   PTR_INT+LN_SUCC          ; pointer struct Interrupt (pri 50), reserved low RAM
        move.b  #50,PTR_INT+LN_PRI
        clr.l   PTR_INT+IS_DATA
        move.l  #pointer_input_handler,PTR_INT+IS_CODE
        lea     -48(sp),sp               ; IOStdReq scratch
        move.l  sp,a1
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        move.l  #PTR_INT,INP_IO_DATA(a1)
        move.l  a4,a6
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)
        move.l  ($4).w,a6
        lea     48(sp),sp
.pw_ret:
        movem.l (sp)+,a2/a4
        rts

; m6r_wire_requester: wires the PERSISTENT CONSUMER handlers (pointer pri 50 + requester pri 0) on
; input.device (NO teardown) -> the gameport -> input.device -> pointer -> requester chain lives in the
; running system (symmetric of the persistent producer gp_vblank_server). Then SYNCHRONOUS self-check: injects via
; the persistent handlers a relative move -> gadget then a click -> REQ_HIT -> "M6R WIRED OK". a6 = SysBase.
; Called once in the M6R insert-disk branch (IRQs masked; IND_WRITEEVENT is synchronous). Preserves a2-a4.
m6r_wire_requester:
        movem.l a2-a4,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .mw_ret
        move.l  d0,a4                    ; a4 = input.device base
        bsr     ptr_wire                 ; pointer handler pri 50 (PERSISTENT)
        clr.l   REQ_INT+LN_SUCC          ; requester struct Interrupt (pri 0)
        clr.b   REQ_INT+LN_PRI
        clr.l   REQ_INT+IS_DATA
        move.l  #req_input_handler,REQ_INT+IS_CODE
        lea     -48(sp),sp               ; IOStdReq scratch
        move.l  sp,a2                    ; a2 = ioreq
        lea     REQ_INT,a0               ; ADDHANDLER requester (PERSISTENT)
        bsr.s   .mw_add
        clr.w   PTR_X                    ; self-check: do the persistent handlers respond?
        clr.w   PTR_Y
        clr.w   REQ_HIT
        lea     -24(sp),sp               ; InputEvent scratch
        move.l  sp,a3                    ; a3 = event
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a3)
        clr.b   IE_SUBCLASS(a3)
        clr.w   IE_QUALIFIER(a3)
        clr.l   IE_NEXTEVENT(a3)
        move.w  #IECODE_NOBUTTON,IE_CODE(a3)  ; relative move -> (160,112) on the gadget
        move.w  #160,IE_X(a3)
        move.w  #112,IE_Y(a3)
        bsr.s   .mw_write
        move.w  #IECODE_LBUTTON,IE_CODE(a3)   ; click (null delta) -> hit-test (160,112) -> REQ_HIT
        clr.w   IE_X(a3)
        clr.w   IE_Y(a3)
        clr.l   IE_NEXTEVENT(a3)
        bsr.s   .mw_write
        lea     24(sp),sp                ; free the scratch event
        cmp.w   #1,REQ_HIT               ; did the PERSISTENT handlers process the click?
        bne.s   .mw_done
        lea     msg_m6r_wired(pc),a0
        bsr     ser_puts                 ; "M6R WIRED OK"
.mw_done:
        clr.w   PTR_X                    ; reset the pointer to zero for the real mouse (handlers STAY wired)
        clr.w   PTR_Y
        clr.w   REQ_HIT
        lea     48(sp),sp                ; free the scratch ioreq
.mw_ret:
        movem.l (sp)+,a2-a4
        rts
.mw_add:                                 ; IND_ADDHANDLER(a0 = struct Interrupt); a2=ioreq, a4=input base
        move.l  a4,IO_DEVICE(a2)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a2)
        move.l  a0,INP_IO_DATA(a2)
        bra.s   .mw_bio
.mw_write:                               ; IND_WRITEEVENT(a3 = event); a2=ioreq, a4=input base
        move.l  a4,IO_DEVICE(a2)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a2)
        move.l  a3,INP_IO_DATA(a2)
.mw_bio:
        move.l  a2,a1
        move.l  a4,a6
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts

; vbl_tail_server (M7f): lowest-priority VERTB server (-10). Increments VERTB_CHAIN_N ->
; proves that the walker goes through the WHOLE VERTB chain (sched_server pri 20 + timer_vblank pri 0 therefore
; ran BEFORE it). a1=IS_DATA (unused), a6=SysBase. Preserves d2-d7/a2-a4 (only touches d0+memory).
vbl_tail_server:
        addq.l  #1,VERTB_CHAIN_N
        ; M7g: triggers COPER by SOFTWARE (2nd level 3 source), rate-limited 1 VBlank in 4, to prove
        ; int3's multi-source decoding (COPER will be served at the next INT3). Scratch d0 (preserves d2-d7/a2-a4).
        addq.b  #1,COPER_TICK
        move.b  COPER_TICK,d0
        and.b   #3,d0
        bne.s   .vt_z
        move.w  #(INTF_SETCLR|INTF_COPER),INTREQ ; sets the COPER request (Paula)
.vt_z:
        moveq   #0,d0                ; Z set -> continue (last node: end of chain anyway)
        rts

; coper_test (M7g): EXCLUSIVE handler of the COPER source (level 3), installed by SetIntVector. Proves
; that int3's INTREQR decoding dispatches a 2nd level 3 source. a0=$DFF000, a1=IS_DATA (unused),
; a6=SysBase. Preserves d2-d7/a2-a4 (only touches COPER_FIRED -> int3_dispatch's d2 survives).
coper_test:
        addq.l  #1,COPER_FIRED
        rts

; coper_int (M7g): struct Interrupt of the EXCLUSIVE COPER vector (SetIntVector copies IS_DATA/IS_CODE ->
; can stay in ROM). IS_CODE -> coper_test. IS_DATA unused.
        EVEN
coper_int:
        dc.l    0                    ; LN_SUCC
        dc.l    0                    ; LN_PRED
        dc.b    0                    ; LN_TYPE
        dc.b    0                    ; LN_PRI (unused: exclusive vector)
        dc.l    coper_int_name       ; LN_NAME
        dc.l    0                    ; IS_DATA
        dc.l    coper_test           ; IS_CODE
coper_int_name:
        dc.b    "test.coper",0

                ifeq    PROD
; m7_int6_probe (dev ROM): ICR bit 0 vector of ciab.resource (continuous CIA-B timer A), called by cia_dispatch
; from level 6. Two exclusive detectors BEFORE any manipulation:
;   - VBL_INSURG set -> INT6 preempted the switch SURGERY -> VBL_CLASH++ (must stay 0: Disable makes it
;     atomic vs any IPL; > 0 = RED1);
;   - otherwise VBL_INBODY set -> INT6 preempted the BODY of vbl -> VBL_PREEMPT_COUNT++ (must be > 0: proof that vbl
;     runs at native IPL3; == 0 = RED2).
; Then M7d: stress of the SHARED PORT on the interrupt side (race against task_port). ICR vector convention: preserves
; d2/d3/a2 (loop variables of cia_dispatch).
        EVEN
m7_int6_probe:
        tst.b   VBL_INSURG          ; is vbl_handler in the middle of list SURGERY?
        beq.s   .ip_notsurg
        addq.l  #1,VBL_CLASH        ; YES -> INT6 preempted the critical section = Disable violated (RED1)
        bra.s   .ip_ok
.ip_notsurg:
        tst.b   VBL_INBODY          ; otherwise, is vbl in its BODY (outside surgery)?
        beq.s   .ip_ok
        addq.l  #1,VBL_PREEMPT_COUNT ; YES -> INT6(6) preempted the BODY of vbl(3) = per-level IPL fidelity
.ip_ok:
        movem.l d0-d1/a0-a1,-(sp)
        move.l  WP_SPORT,d0
        beq.s   .ip_ret             ; port not yet created
        addq.b  #1,STRESS_TICK      ; rate-limit: 1 INT6 in 4
        move.b  STRESS_TICK,d1
                ifne    M7D_STRESS_MAX
        and.b   #0,d1               ; RED A/B: every INT6 (max contention)
                else
        and.b   #3,d1
                endc
        bne.s   .ip_ret
        move.l  d0,a0
        jsr     LVO_GETMSG(a6)      ; GetMsg(SP)
        tst.l   d0
        beq.s   .ip_ret
        move.l  d0,a1
        cmp.l   #STRESS_MAGIC,MSG_MAGIC_OFF(a1)
        bne.s   .ip_pfail           ; wrong pointer -> list corruption
        tst.l   MSG_INHAND_OFF(a1)
        bne.s   .ip_pfail           ; already "in hand" -> duplicate = corruption
        move.l  #1,MSG_INHAND_OFF(a1)
        clr.l   MSG_INHAND_OFF(a1)
        move.l  WP_SPORT,a0
        jsr     LVO_PUTMSG(a6)      ; PutMsg(SP, msg)
        addq.l  #1,WP_PORTI
        bra.s   .ip_ret
.ip_pfail:
        st      WP_PORTFAIL
.ip_ret:
        move.b  #$19,CIAB_HW+CIA_CRA ; re-arms the one-shot (LOAD: latch 255)
        movem.l (sp)+,d0-d1/a0-a1
        rts
        EVEN
m7_int6_int:
        dcb.b   14,0                ; struct Node (not linked: AddICRVector only stores the pointer)
        dc.l    0                   ; IS_DATA
        dc.l    m7_int6_probe       ; IS_CODE
                endc

; ciab_server_int (M7b): EXCLUSIVE EXTER vector installed by SetIntVector -> ciab_server. Not linked
; (SetIntVector copies IS_DATA/IS_CODE) -> can stay in ROM. IS_DATA unused (ciab_server reads CIAB_PTR).
        EVEN
ciab_server_int:
        dc.l    0                    ; LN_SUCC
        dc.l    0                    ; LN_PRED
        dc.b    0                    ; LN_TYPE
        dc.b    0                    ; LN_PRI (unused: exclusive vector)
        dc.l    srv_ciab_name        ; LN_NAME
        dc.l    0                    ; IS_DATA
        dc.l    ciab_server          ; IS_CODE
srv_ciab_name:
        dc.b    "ciab.exter",0
        EVEN

; ============================ demo AUTOINIT resident (M5a) =========
; RTF_AUTOINIT ROMTag (pri 40) -> InitResident calls MakeLibrary with the table of 4 longs.
; Proves: jump table built (func0 returns $5A), InitStruct sets version/type, init func sets
; the revision + the name, lib added to LibList. ABSOLUTE vector table (longwords, -1).
; Data table = INITWORD(LIB_VERSION,40) + INITBYTE(LN_TYPE,NT_LIBRARY). The name (address) is
; set by the init func (PC-relative), not by InitStruct (a relocated address cannot be
; split into two words at assembly time).
        EVEN
res_auto:
        dc.w    RTC_MATCHWORD
        dc.l    res_auto             ; RT_MATCHTAG = self
        dc.l    res_auto_end         ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,1,NT_LIBRARY,40  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    autolib_name         ; RT_NAME
        dc.l    autolib_name         ; RT_IDSTRING
        dc.l    autolib_inittab      ; RT_INIT -> AUTOINIT table (4 longs)
autolib_name:
        dc.b    "demo.autolib",0
        EVEN
autolib_inittab:
        dc.l    LIB_SIZE             ; dataSize (minimal base)
        dc.l    autolib_vectors      ; funcTable
        dc.l    autolib_datatab      ; dataTable (InitStruct)
        dc.l    autolib_initfunc     ; initFunc
autolib_vectors:                     ; RELATIVE table (exercises the detection + the word arithmetic)
        dc.w    -1                            ; marker: word displacements relative to this base
        dc.w    autolib_func0-autolib_vectors ; LVO -6
        dc.w    autolib_func1-autolib_vectors ; LVO -12
        dc.w    -1                            ; terminator (word)
autolib_datatab:
        dc.w    $D000,LIB_VERSION,40          ; INITWORD(LIB_VERSION, 40)
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8) ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.b    0                             ; terminator of the InitStruct stream
        EVEN
autolib_func0:                       ; called via jsr -6(base) -> MakeFunctions proof
        moveq   #$5A,d0
        rts
autolib_func1:                       ; LVO -12 (not exercised)
        moveq   #0,d0
        rts
autolib_initfunc:                    ; (D0=base, A0=segList, A6=ExecBase) -> D0 = base
        move.l  d0,a1                ; a1 = base
        move.w  #$5A,LIB_REVISION(a1) ; proof: the init func ran
        lea     autolib_name(pc),a0
        move.l  a0,LN_NAME(a1)       ; name (address, PC-relative) -> OpenLibrary/FindName
        rts                          ; d0 = base unchanged
        EVEN
res_auto_end:

; ============================ data ==============================
exec_name:
        dc.b    "exec.library",0
exec_id:
        dc.b    "exec 34.2 (clean-room reimpl)",13,10,0
str_alpha:
        dc.b    "alpha",0
str_beta:
        dc.b    "beta",0
str_gamma:
        dc.b    "gamma",0
task_test_name:
        dc.b    "testtask",0
str_port:
        dc.b    "testport",0
task_h_name:
        dc.b    "demo.H",0
task_l_name:
        dc.b    "demo.L",0
task_s_name:
        dc.b    "demo.S",0
task_t_name:
        dc.b    "demo.timer",0
task_p_name:
        dc.b    "demo.port",0
task_fa_name:
        dc.b    "demo.forbidA",0
task_fb_name:
        dc.b    "demo.forbidB",0
task_q2_name:
        dc.b    "demo.q2",0
task_rm_name:
        dc.b    "demo.rm",0
msg_cold:
        dc.b    "EXEC coldstart: overlay off, stack live",13,10,0
msg_f2kbd:
        dc.b    "F2 KBD OK (CIA-A keyboard: power-up stream received+decoded, $FD initiate + $FE terminate; handshake drives the stream)",13,10,0
msg_f2bkbd:
        dc.b    "F2B KBD OK (live keyboard driver: AddICRVector SP bit3 -> kbd_interrupt -> keymap -> ring; console READ drains it)",13,10,0
msg_input_ok:
        dc.b    "INPUT OK (input.device: IND_ADDHANDLER pri-sorted chain + IND_WRITEEVENT propagates RAWKEY; 2 handlers in pri order, keycode relayed)",13,10,0
input_dev_name:
        dc.b    "input.device",0
msg_console_ok:
        dc.b    "CONSOLE WRITE OK (console.device CMD_WRITE: 8x8 glyph blitter into bitplane; readback matches font)",13,10,0
console_dev_name:
        dc.b    "console.device",0
msg_conread_ok:
        dc.b    "CONSOLE READ=v (console.device input handler on input.device cooked a RAWKEY -> read buffer -> CMD_READ)",13,10,0
msg_diskvalid:
        dc.b    "DISK VALID OK (disk-validator: OFS rootblock+bitmap checksums, bm_flag valid, rootblock allocated in bitmap)",13,10,0
msg_keymap_ok:
        dc.b    "KEYMAP OK (keymap.resource US QWERTY: kbd_cook keycode+SHIFT/CAPS/CTRL -> q/Q/Q, 1/!, ctrl-C=$03)",13,10,0
msg_keymap_azerty:
        dc.b    "KEYMAP AZERTY OK (keymap.resource FR AZERTY: kbd_cook keycode $10->a, $01->& (SHIFT->1), $02->e-acute)",13,10,0
msg_req_drawn:
        dc.b    "REQUESTER DRAWN OK (insert-disk requester: border + text rendered via font8x8; bitplane readback matches)",13,10,0
msg_req_click:
        dc.b    "REQUESTER CLICK OK (RAWMOUSE via input.device: click inside gadget -> hit, click outside -> miss)",13,10,0
msg_gameport_ok:
        dc.b    "GAMEPORT OK (gameport.device logic: gp_delta8 8-bit wraparound, button edge-detect, RAWMOUSE emitted via IND_WRITEEVENT)",13,10,0
msg_m6r_live_ok:
        dc.b    "M6R LIVE OK (relative RAWMOUSE deltas -> pointer accumulator -> absolute clamped pos -> requester hit-test: on gadget -> hit, off -> miss)",13,10,0
msg_gp_live_ok:
        dc.b    "GP VBLANK LIVE OK (gameport VBlank server runs on real frame interrupts in the running system: GP_POLLS advancing)",13,10,0
msg_m6r_wired:
        dc.b    "M6R WIRED OK (pointer+requester handlers registered PERSISTENTLY on input.device in the running system; injected click -> REQ_HIT)",13,10,0
        EVEN
con_test_str:
        dc.b    "CONSOLE WRITE OK 0123456789"
con_test_end:
        dc.b    0
        EVEN
msg_ok:
        dc.b    "EXEC ExecBase + jump table OK, self-test passed",13,10,0
msg_fail:
        dc.b    "EXEC self-check/self-test FAILED",13,10,0
chk_core:
        dc.b    "chk core",13,10,0
chk_mem:
        dc.b    "chk mem",13,10,0
chk_m24a:
        dc.b    "chk m24a",13,10,0
chk_m24b:
        dc.b    "chk m24b",13,10,0
chk_m24c:
        dc.b    "chk m24c",13,10,0
msg_vblok:
        dc.b    "M3 VBlank interrupts live",13,10,0
msg_vbltimeout:
        dc.b    "M3 VBL timeout",13,10,0
msg_m3flive:
        dc.b    "M3F LIVE: preemption + yield coexist (both scheduling paths OK)",13,10,0
msg_forbid_ok:
        dc.b    "FORBID ATOMIC OK (deferred reschedule honors Forbid: pri-7 task signaled under a pri-3 Forbid did NOT preempt it; intr_isr_defer gates on TDNestCnt)",13,10,0
msg_m3ffail:
        dc.b    "M3F FAILED: context sentinel corrupted across a switch",13,10,0
msg_res_ok:
        dc.b    "M4 RESIDENTS OK (scan + InitResident in priority order)",13,10,0
msg_auto_ok:
        dc.b    "M5A AUTOINIT OK (MakeLibrary + MakeFunctions + InitStruct)",13,10,0
msg_res_fail:
        dc.b    "M4 FAILED: resident scan/init incorrect",13,10,0
msg_auto_fail:
        dc.b    "M5A FAILED: AUTOINIT/MakeLibrary incorrect",13,10,0
msg_cia_ok:
        dc.b    "M5B CIA OK (cia.resource: OpenResource + AbleICR + AddICRVector)",13,10,0
msg_cia_fail:
        dc.b    "M5B FAILED: cia.resource incorrect",13,10,0
msg_timer_ok:
        dc.b    "M5C TIMER OK (timer.device AUTOINIT -> DeviceList, Open works)",13,10,0
msg_m4c1_ok:
        dc.b    "M4C1 GFX LIB OK (graphics.library AUTOINIT -> LibList, NT_LIBRARY routing, Open works)",13,10,0
msg_timer_fail:
        dc.b    "M5C FAILED: timer.device incorrect",13,10,0
msg_m6a_ok:
        dc.b    "M6A TIMER OK (VBLANK unit: request replied after ~5 ticks)",13,10,0
msg_m6a_fail:
        dc.b    "M6A FAILED: timer VBLANK unit incorrect",13,10,0
msg_m7b_ok:
        dc.b    "M7B PORTS OK (per-number dispatch: AddIntServer chain, 2 servers in pri order)",13,10,0
msg_m7b_fail:
        dc.b    "M7B FAILED: per-number interrupt dispatch / server chain incorrect",13,10,0
msg_m7a_ok:
        dc.b    "M7A TIMER OK (MICROHZ via CIA-A/INT2: task woke on timer, reentrancy gate held)",13,10,0
msg_m7a_fail:
        dc.b    "M7A FAILED: MICROHZ wake or scheduler-list reentrancy gate",13,10,0
msg_m7c_ok:
        dc.b    "M7C USERMODE OK (user-mode tasks on shared SSP, deferred Dispatch survives preemption)",13,10,0
msg_m7d_ok:
        dc.b    "M7D PORTS OK (interrupt-safe PutMsg/GetMsg: task vs IRQ race on shared port, no corruption)",13,10,0
msg_m7d_fail:
        dc.b    "M7D FAILED: shared-port list corrupted (task GetMsg vs IRQ PutMsg race)",13,10,0
msg_m7e_ok:
        dc.b    "M7E IPL OK (native-IPL: INT6 preempts vbl body; scheduler surgery IPL7-atomic, no overlap)",13,10,0
msg_m7f_ok:
        dc.b    "M7F VERTB OK (VERTB is a server chain: sched+timer+tail walked in pri order via int3_dispatch)",13,10,0
msg_m7g_ok:
        dc.b    "M7G MULTISRC OK (int3 decodes INTREQR, services each pending level-3 source; COPER, not just VERTB)",13,10,0
msg_m7h_ok:
        dc.b    "M7H QUANTUM OK (isolation: 2 equal-pri spinners rotate every ~QUANTUM ticks, not every tick)",13,10,0
msg_m7j_ok:
        dc.b    "M7J REMTASK OK (task ended -> RemTask self freed its stack+TCB, AvailMem recovered)",13,10,0
msg_m7l_ok:
        dc.b    "M7L MICROHZ CALIB OK (TV_MICRO = real us: 0.5s MICROHZ request elapsed ~25 VBLANK ticks)",13,10,0
msg_m6t_ok:
        dc.b    "M6T TRACKDISK OK (trackdisk.device AUTOINIT -> DeviceList; Open unit 0 OK + io_Unit=base+34; Open unit 4 -> OpenDevice fail: io_Error, io_Device=0)",13,10,0
msg_m6u_syncs:
        dc.b    "M6U SYNCS=",0
msg_m6u_ok:
        dc.b    "M6U TRACKDISK READ OK (raw MFM track read from DF0 via disk DMA; $4489 sync words found)",13,10,0
msg_m6v_sect:
        dc.b    "M6V SECTORS=",0
msg_m6v_ok:
        dc.b    "M6V TRACKDISK DECODE OK (MFM decoded: 11 sectors, header+data checksums valid, sector 0 = DOS bootblock)",13,10,0
msg_m6w_ok:
        dc.b    "M6W TRACKDISK CMD_READ OK (BeginIO CMD_READ: 512 bytes read from DF0 sector 0 = DOS bootblock)",13,10,0
msg_m6x_track:
        dc.b    "M6X TRACK=",0
msg_m6x_ok:
        dc.b    "M6X TRACKDISK SEEK OK (step/seek + side-select: read track 2, decoded sectors report track==2)",13,10,0
msg_m6z_ok:
        dc.b    "M6Z TRACKDISK CMD_READ MULTI-TRACK OK (offset->track: block 880 = root block @track 80; spanning read blocks 10+11 crosses track 0/1 boundary)",13,10,0
msg_d1_ok:
        dc.b    "D1 OFS READ OK (read file 'KickSlop' by name from DF0: via OFS root->hash->header->data chain; 1024 bytes, case-insensitive, 3 OFS data blocks)",13,10,0
msg_d3a_ok:
        dc.b    "D3A PACKET OK (Process+CreateProc; driver -> StandardPacket PutMsg -> handler process -> ReplyMsg -> driver got echo)",13,10,0
msg_d3b_ok:
        dc.b    "D3B HANDLER OK (file-handler process served FINDINPUT/READ/END packets; read 'kickslop' 1024 bytes via OFS, markers match)",13,10,0
msg_d3c_ok:
        dc.b    "D3C DOS OK (client process: dos.library Open/Read/Close 'kickslop' via packets -> DeviceNode handler; 1024 bytes, markers match)",13,10,0
; device name and DD geometry of the DF0 disk (dosfilehandler.i: DosEnvec), referenced by BPTR from the FSSM
        cnop    0,4
df0_device:
        dc.b    16,"trackdisk.device",0
        cnop    0,4
df0_environ:
        dc.l    12                   ; de_TableSize
        dc.l    128                  ; de_SizeBlock (longs)
        dc.l    0                    ; de_SecOrg
        dc.l    2                    ; de_Surfaces
        dc.l    1                    ; de_SectorPerBlock
        dc.l    11                   ; de_BlocksPerTrack
        dc.l    2                    ; de_Reserved
        dc.l    11                   ; de_PreAlloc
        dc.l    0                    ; de_Interleave
        dc.l    0                    ; de_LowCyl
        dc.l    79                   ; de_HighCyl
        dc.l    5                    ; de_NumBuffers
        dc.l    3                    ; de_BufMemType
dos_libname:
        dc.b    "dos.library",0
d3c_cname:
        dc.b    "dos.client",0
d3d_cname:
        dc.b    "dos.cmdclient",0
d3d_fname:
        dc.b    "d3dtest",0
d3e_cname:
        dc.b    "dos.loadsegclient",0
msg_d3e_loadseg:
        dc.b    "D3E LOADSEG LVO OK (dos.library LoadSeg -150: file opened+read+hunk-parsed+relocated via real LVO -> seglist; UnLoadSeg -156)",13,10,0
d3f_cname:
        dc.b    "dos.ioseekclient",0
d3f_badname:
        dc.b    "nosuchfile",0
msg_d3f_ok:
        dc.b    "DOS IOERR SEEK OK (IoErr -132 reflects Open-not-found then 0; Seek -66 ACTION_SEEK rewinds, re-read matches)",13,10,0
d3g_cname:
        dc.b    "dos.ioclient",0
d3h_cname:
        dc.b    "dos.bigclient",0
d3h_fname:
        dc.b    "bigseg",0
d3i_cname:
        dc.b    "dos.lockclient",0
d3i_rootname:
        dc.b    ":",0                ; volume root (ACTION_LOCATE_OBJECT -> OFS_ROOTBLK)
msg_d3i_ok:
        dc.b    "DOS LOCK EXAMINE OK (Lock -84 'kickslop' -> Examine -102: file, size 1024@fib_Size; Lock ':' -> ExNext -108 enumerates root, finds kickslop; UnLock -90)",13,10,0
d3j_cname:
        dc.b    "dos.streamclient",0
d3j_fname:
        dc.b    "BigData",0
msg_d3j_ok:
        dc.b    "OFS STREAM OK (dos Open/Read 'BigData' 48000 bytes > 32K old cap, incremental per-datablock stream, sentinel reached; Seek -66 cross-block re-reads @500)",13,10,0
        even
; marker emitted BY the Write itself (con_handler), not NUL-terminated (Write uses an explicit length).
msg_dos_write:
        dc.b    "DOS WRITE OK (dos Write -48 -> ACTION_WRITE -> con_handler -> serial; Input -54/Output -60/CurrentDir -126 ok)",13,10
msg_dos_write_end:
msg_dos_write_len EQU msg_dos_write_end-msg_dos_write
        even
e1_hname:
        dc.b    "con.handler",0
sh_cname:
        dc.b    "shell",0
fd_cname:
        dc.b    "feeder",0
        even
d3a_hname:
        dc.b    "dos.handler.echo",0
d3a_dname:
        dc.b    "dos.driver",0
d3b_hname:
        dc.b    "dos.handler.df0",0
d3b_dname:
        dc.b    "dos.fsdriver",0
fsd_name_src:
        dc.b    "kickslop"
        even
ofs_test_name:
        dc.b    "kickslop",0
        even
ls_test_name:
        dc.b    "d2test",0
        even
msg_m6r_ok:
        dc.b    "M6R STRAP OK (strap read DF0: bootblock and found NO bootable volume -> insert-disk; real 1.3 trigger: DOS-magic+additive-checksum invalid, or no disk)",13,10,0
msg_m6s_ok:
        dc.b    "M6S BOOTSCR OK (boot screen 320x256x5 = 32-color image displayed via graphics.library ABI; visual proof = RMSE vs reference)",13,10,0
msg_m6y_ok:
        dc.b    "M6Y STRAP BOOTED OK (strap read+validated+executed DF0: bootblock; CBOOT marker came from the bootblock itself; no insert-disk)",13,10,0
msg_m5i_ok:
        dc.b    "M5I INTUI LIB OK (intuition.library AUTOINIT -> LibList; ViewAddress -294 returns &ib_ViewLord)",13,10,0
msg_m5o_ok:
        dc.b    "M5O OPENLIB OK (OpenLibrary by name + version gate + Open vector; too-high ver -> 0; OldOpenLibrary; CloseLibrary)",13,10,0
msg_m6d_ok:
        dc.b    "M6D DOS LIB OK (dos.library AUTOINIT -> LibList; rn_Info BPTR round-trips &DosInfo; DateStamp -192 -> 0,0,0 unset + returns ptr)",13,10,0
expansion_test_name:
        dc.b    "expansion.library",0
        EVEN
msg_expansion_ok:
        dc.b    "EXPANSION OK (expansion.library: OpenLibrary v37 gated->0 / v34 ok; AllocConfigDev->AddConfigDev->FindConfigDev exact+wildcard, absent ID miss)",13,10,0
mathffp_test_name:
        dc.b    "mathffp.library",0
msg_mathffp_ok:
        dc.b    "MATHFFP OK (mathffp.library: SPFlt/SPFix/SPAdd/SPSub/SPMul/SPDiv/SPCmp/SPTst/SPNeg/SPFloor/SPCeil + div0 overflow)",13,10,0
msg_mathffp_fail:
        dc.b    "MATHFFP FAIL LVO ",0
msg_crlf_mft:
        dc.b    13,10,0
task_aud_name:
        dc.b    "task_aud",0
msg_audplay_ok:
        dc.b    "AUDIO PLAY OK (audio.device: CMD_WRITE DMA 30 cycles + queued write chained, WAITCYCLE before end, CMD_READ, channel off)",13,10,0
msg_audplay_fail:
        dc.b    "AUDIO PLAY FAIL",13,10,0
msg_gels_ok:
        dc.b    "GELS OK (graphics: InitGels/InitMasks, Bob OVERLAY+SAVEBACK drawn/moved/restored at pixel level, Bob x VSprite + border collisions, SortGList, RemIBob, Get/FreeGBuffers, InitGMasks, AddAnimOb, Animate sequence switch)",13,10,0
msg_gels_fail:
        dc.b    "GELS FAIL",13,10,0
msg_fonts_ok:
        dc.b    "FONTS OK (graphics: OpenFont topaz 8/9/unknown + accessors, InitRastPort default font, TextLength + TxSpacing, soft styles, bold Text readback)",13,10,0
msg_fonts_fail:
        dc.b    "FONTS FAIL",13,10,0
fnt_ta8:
        dc.l    fnt_topaz
        dc.w    8
        dc.b    0,0
fnt_ta9:
        dc.l    fnt_topaz
        dc.w    9
        dc.b    0,0
fnt_tanone:
        dc.l    fnt_nope
        dc.w    8
        dc.b    0,0
fnt_topaz:
        dc.b    "TOPAZ.font",0
fnt_nope:
        dc.b    "nope.font",0
fnt_abc:
        dc.b    "Abc"
fnt_i:
        dc.b    "I"
        even
msg_regions_ok:
        dc.b    "REGIONS OK (graphics: Or/And/ClearRect/XorRect + Or/Xor/AndRegionRegion: areas, bounds, points vs pixel-set model)",13,10,0
msg_regions_fail:
        dc.b    "REGIONS FAIL",13,10,0
layers_test_name:
        dc.b    "layers.library",0
msg_layers_ok:
        dc.b    "LAYERS OK (layers.library: simple+smart layers, behind/upfront backing store, damage+BeginUpdate, move, delete, size, WhichLayer)",13,10,0
msg_layers_fail:
        dc.b    "LAYERS FAIL",13,10,0
semt_name:
        dc.b    "kicksem.test",0
msg_sem_ok:
        dc.b    "SEM OK (exec semaphores: Add/FindSemaphore, Attempt + nested Obtain, Release to free)",13,10,0
msg_sem_fail:
        dc.b    "SEM FAIL",13,10,0
msg_semw_ok:
        dc.b    "SEM WAIT OK (blocked ObtainSemaphore handed over by ReleaseSemaphore: owner + nest set, woken)",13,10,0
msg_semw_fail:
        dc.b    "SEM WAIT FAIL",13,10,0
task_semw_name:
        dc.b    "task_semw",0
task_semr_name:
        dc.b    "task_semr",0
audio_test_name:
        dc.b    "audio.device",0
msg_audio_ok:
        dc.b    "AUDIO ALLOC OK (audio.device: precedence, combo order, steal + key invalidation, lock stolen, wait + retry on free)",13,10,0
msg_audio_fail:
        dc.b    "AUDIO ALLOC FAIL",13,10,0
kbddev_test_name:
        dc.b    "keyboard.device",0
msg_kbddev_ok:
        dc.b    "KBDDEV OK (keyboard.device: READMATRIX, READEVENT buffered + pending replied by event, CMD_CLEAR, AbortIO, ADD/REMRESETHANDLER)",13,10,0
msg_kbddev_fail:
        dc.b    "KBDDEV FAIL",13,10,0
potgo_test_name:
        dc.b    "potgo.resource",0
msg_potgo_ok:
        dc.b    "POTGO OK (potgo.resource: AllocPotBits START/DATxx in/out rules, FreePotBits, WritePotgo keeps high byte not START)",13,10,0
msg_potgo_fail:
        dc.b    "POTGO FAIL",13,10,0
diskres_test_name:
        dc.b    "disk.resource",0
msg_diskres_ok:
        dc.b    "DISKRES OK (disk.resource: AllocUnit/FreeUnit, GetUnitID(0)=DRT_AMIGA, GetUnit busy->queue, GiveUnit->ReplyMsg) DF1 ID=",0
msg_diskres_fail:
        dc.b    "DISKRES FAIL",13,10,0
        EVEN
; LVO.w, d0.l, d1.l, expected.l — 3.0=$C0000042, -10.0=$A00000C4, 1.0=$80000041, -2.5=$A00000C2.
mft_table:
        dc.w    -36
        dc.l    3,0,$C0000042                    ; SPFlt(3)
        dc.w    -36
        dc.l    -10,0,$A00000C4                  ; SPFlt(-10)
        dc.w    -78
        dc.l    $C0000042,$A00000C4,$F00000C5    ; SPMul(3,-10) = -30
        dc.w    -30
        dc.l    $F00000C5,0,-30                  ; SPFix(-30.0)
        dc.w    -84
        dc.l    $80000041,$C0000042,$AAAAAB3F    ; SPDiv: 1/3 rounded to nearest
        dc.w    -78
        dc.l    $AAAAAB3F,$C0000042,$80000041    ; SPMul(1/3,3) = 1.0 after rounding
        dc.w    -66
        dc.l    $C0000042,$A00000C4,$E00000C3    ; SPAdd(3,-10) = -7
        dc.w    -72
        dc.l    $C0000042,$A00000C4,$D0000044    ; SPSub: 3 - (-10) = 13
        dc.w    -42
        dc.l    $C0000042,$A00000C4,1            ; SPCmp(3,-10) -> +1
        dc.w    -42
        dc.l    $A00000C4,$C0000042,-1           ; SPCmp(-10,3) -> -1
        dc.w    -48
        dc.l    0,$A00000C4,-1                   ; SPTst(-10) in d1 -> -1
        dc.w    -60
        dc.l    $C0000042,0,$C00000C2            ; SPNeg(3) = -3
        dc.w    -90
        dc.l    $A00000C2,0,$C00000C2            ; SPFloor(-2.5) = -3
        dc.w    -96
        dc.l    $A00000C2,0,$800000C2            ; SPCeil(-2.5) = -2
        dc.w    -90
        dc.l    $C0000042,0,$C0000042            ; SPFloor(3) = 3
        dc.w    -36
        dc.l    123456,0,$F1200051               ; SPFlt(123456)
        dc.w    -30
        dc.l    $F1200051,0,123456               ; SPFix -> exact round trip
        dc.w    -84
        dc.l    $C0000042,0,$FFFFFF7F            ; SPDiv(3/0) -> largest positive
mft_table_end:
ciaa_test_name:
        dc.b    "ciaa.resource",0
ciab_test_name:
        dc.b    "ciab.resource",0
timer_test_name:
        dc.b    "timer.device",0
trackdisk_test_name:
        dc.b    "trackdisk.device",0
graphics_test_name:
        dc.b    "graphics.library",0
intuition_test_name:
        dc.b    "intuition.library",0
noexist_test_name:
        dc.b    "inexistante.library",0
dos_test_name:
        dc.b    "dos.library",0
msg_memslow:
        dc.b    "MEM SLOW KB=",0
        EVEN

; rdf_selftest: RawDoFmt via the jump table (LVO -522) into a stack buffer, compared byte by byte (NUL included) with
; rdf_expect -> "RAWDOFMT OK" or "RAWDOFMT FAILED". Covers signed d/ld, width, left justification, '0' fill
; with sign, x, s, c, and the restoring of a3. a6 = SysBase. Preserves everything.
rdf_selftest:
        movem.l d0-d1/a0-a3,-(sp)
        lea     -64(sp),sp
        lea     rdf_fmt(pc),a0
        lea     rdf_data(pc),a1
        lea     rdf_putch(pc),a2
        move.l  sp,a3
        jsr     LVO_RAWDOFMT(a6)
        cmp.l   sp,a3                ; a3 must be restored (calling convention)
        bne.s   .rdf_bad
        move.l  sp,a0
        lea     rdf_expect(pc),a1
.rdf_cmp:
        move.b  (a1)+,d0
        cmp.b   (a0)+,d0
        bne.s   .rdf_bad
        tst.b   d0
        bne.s   .rdf_cmp
        lea     msg_rdf_ok(pc),a0
        bra.s   .rdf_out
.rdf_bad:
        lea     msg_rdf_bad(pc),a0
.rdf_out:
        bsr     ser_puts
        lea     64(sp),sp
        movem.l (sp)+,d0-d1/a0-a3
        rts
rdf_putch:
        move.b  d0,(a3)+
        rts
rdf_fmt:
        dc.b    "%d|%5ld|%-3x|%s|%04x|%c|%05ld",0
rdf_expect:
        dc.b    "-42| 1234|AB |hi|001F|Z|-0007",0
rdf_hi:
        dc.b    "hi",0
        EVEN
rdf_data:
        dc.w    -42
        dc.l    1234
        dc.w    $AB
        dc.l    rdf_hi
        dc.w    $1F
        dc.w    'Z'
        dc.l    -7
msg_rdf_ok:
        dc.b    "RAWDOFMT OK (exec RawDoFmt -522: d/ld, width, left-justify, zero-pad with sign, x, s, c)",13,10,0
msg_rdf_bad:
        dc.b    "RAWDOFMT FAILED",13,10,0
        EVEN
msg_crlf:
        dc.b    13,10,0
        EVEN
