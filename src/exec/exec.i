; src/exec/exec.i — shared exec.library constants (M2.3).
; Included by boot.s / lists.s / memory.s / library.s. EQUs only
; (public ABI facts + the project's memory map): no logic, no data.
; IMPLEMENTATION track ("clean"): values taken from docs/analysis/exec-spec.md,
; docs/exec-lvo-table.md and the public ABI. NO reading of the ROM.

                ifnd    EXEC_I
EXEC_I          equ     1

; --- Custom chip (Amiga HRM) ---
CUSTOM   EQU $DFF000
DMACON   EQU CUSTOM+$096
INTENA   EQU CUSTOM+$09A
INTREQ   EQU CUSTOM+$09C
INTENAR  EQU CUSTOM+$01C      ; M7g: read of the enabled interrupts
INTREQR  EQU CUSTOM+$01E      ; M7g: read of the pending interrupts
SERDAT   EQU CUSTOM+$030
SERPER   EQU CUSTOM+$032
SERDATR  EQU CUSTOM+$018
COLOR00  EQU CUSTOM+$180
POTINP   EQU CUSTOM+$016      ; POTGOR: bit 10 (DATLY) = right button of port 0, active-low
JOY0DAT  EQU CUSTOM+$00A      ; port 0 mouse quadrature counters (low byte = X, high byte = Y; 8-bit wrap)

; --- CIA-A (overlay / LED) ---
CIAA_PRA  EQU $BFE001
CIAA_DDRA EQU $BFE201

; --- A500 512K target memory map ---
MAXCHIP      EQU $00080000
MH_CHIP      EQU $00000400     ; chip MemHeader
LOWVARS_LO   EQU $00000500     ; global variables in low RAM [LOWVARS_LO, LOWVARS_HI), zeroed at coldstart
LOWVARS_HI   EQU $00000800
TST_LIST     EQU $00000420     ; self-test scratch (lists)
TST_N1       EQU $00000440
TST_N2       EQU $00000460
; System area in LOW CHIP, just above the low-RAM variables: the top of chip stays free up to
; $80000 as on the real 1.3, because programs write there at absolute addresses (intros: stack at $7FFFE, routines
; at $7F000, planes at $70000+). ExecBase must not be located there.
EXEC_BLOCK   EQU $00001000     ; bottom of exec's jump table
EXEC_NEGSIZE EQU $276          ; 105 V34 vectors (cf docs/exec-lvo-table.md)
EXECBASE     EQU EXEC_BLOCK+EXEC_NEGSIZE ; SysBase (complete V34 table below)
EXEC_POSSIZE EQU $230
FTEST_LO     EQU $00001500     ; region DISJOINT from the heap for the multi-header test (M2.4a selftest); then free,
FTEST_HI     EQU $00002500     ; it serves as a margin below the supervisor stack (an overflow does not reach ExecBase)
SSP_LOWER    EQU $00002500     ; shared supervisor stack [SSP_LOWER, STACKTOP)
STACKTOP     EQU $00003500
HEAP_LOWER   EQU $00003500     ; managed heap (chip)
HEAP_UPPER   EQU MAXCHIP

; --- Phases (12-bit RGB) ---
C_RED    EQU $0F00
C_BLUE   EQU $000F
C_CYAN   EQU $00FF
C_WHITE  EQU $0FFF
C_FAIL   EQU $0F0F

SERPER_9600_PAL EQU 368
ROMBASE  EQU $FC0000

; --- Interrupts (hardware/intbits.i + 68000 autovectors) ---
INTF_SETCLR  EQU $8000        ; INTENA/INTREQ: 1 = sets the bits, 0 = clears them
INTF_INTEN   EQU $4000        ; master (INTEN)
INTF_COPER   EQU $0010        ; M7g: Copper (level 3, bit 4)
INTF_VERTB   EQU $0020        ; VBlank (level 3)
INTF_BLIT    EQU $0040        ; M7g: Blitter (level 3, bit 6)
INTF_PORTS   EQU $0008        ; INT2 / CIA-A
INTF_EXTER   EQU $2000        ; INT6 / CIA-B
INTF_RBF     EQU $0800        ; E1: bit 11 = RBF (serial receive buffer full); acknowledging -> clears SERDATR bit 14
AUTOVEC_L1   EQU $64          ; level 1 autovector (TBE / DSKBLK / SOFTINT)
AUTOVEC_L4   EQU $70          ; level 4 autovector (AUD0..AUD3)
AUTOVEC_L5   EQU $74          ; level 5 autovector (RBF / DSKSYNC)
INTM_L1      EQU $0007        ; level 1 sources
INTM_L4      EQU $0780        ; level 4 sources
INTM_L5      EQU $1800        ; level 5 sources
AUTOVEC_L2   EQU $68          ; 68000 level 2 autovector (INT2 / CIA-A / PORTS)
AUTOVEC_L3   EQU $6C          ; 68000 exception vector, level 3 interrupt
AUTOVEC_L6   EQU $78          ; 68000 level 6 autovector (INT6 / CIA-B / EXTER)
ROM_BASE     EQU $00FC0000     ; start of the ROM (256 KB)
PRIV_VEC     EQU $20          ; privilege violation: exec entry into supervisor (EXEC_SVC)
SVC_MAGIC    EQU $4AFC        ; word following the "ori.w #0,sr" of an EXEC_SVC site (ILLEGAL, never executed)

; EXEC_SVC service: switches to supervisor and jumps to "service" with an exception frame {SR, PC = return}, like
; a TRAP. Like the real exec, we use no TRAP vector (programs often install their code there to
; enter supervisor): in user mode, the privileged instruction triggers vector $20, whose handler
; recognises the site; in supervisor, the frame is built here.
EXEC_SVC     macro
        move.w  sr,-(sp)
        btst    #5,(sp)
        addq.l  #2,sp                ; (addq to An: flags intact)
        bne.s   .svs\@
        ori.w   #0,sr
        dc.w    SVC_MAGIC
        dc.l    \1
        bra.s   .svr\@
.svs\@:
        pea     .svr\@(pc)
        move.w  sr,-(sp)
        jmp     \1
.svr\@:
             endm
LVO_SUPERVISOR EQU -30        ; exec Supervisor(): calls a routine (a5) in supervisor mode (required by flt-intro)
; M7c — context frame (mirror of movem d0-d7/a0-a6 + CPU {SR,PC}), placed on the task's stack.
; 15 GPR longs (60 bytes) + SR (word, offset 60) + PC (long, offset 62) = 66 bytes (even -> word-by-word copy).
FRAME_SR     EQU 60           ; offset of the saved SR in the frame (S bit test = user boundary)
FRAME_SIZE   EQU 66           ; total size of the relocated frame (GPR+SR+PC)
INTB_PORTS   EQU 3            ; Paula PORTS interrupt number (INT2) — cf. hardware/intbits.i
INTB_COPER   EQU 4            ; M7g: COPER number (INT3) — INTF_COPER=$0010=bit4
INTB_VERTB   EQU 5            ; M7f: VERTB number (INT3) — INTF_VERTB=$0020=bit5
INTB_BLIT    EQU 6            ; M7g: BLIT number (INT3) — INTF_BLIT=$0040=bit6
INTB_EXTER   EQU 13           ; Paula EXTER interrupt number (INT6)
INTB_SOFTINT EQU 2            ; software interrupt (level 1) — Cause
INTF_SOFTINT EQU $0004
NT_SOFTINT   EQU 11            ; exec/nodes.i: Interrupt pending in the software queue
; struct Interrupt (exec/interrupts.i) — server / ICR vector
IS_DATA      EQU 14           ; APTR passed in a1 to the server
IS_CODE      EQU 18           ; APTR server code (called a1=data, a5=code, a6=SysBase, a0=$DFF000)
IS_SIZE      EQU 22           ; sizeof(struct Interrupt) = LN(14) + IS_DATA(4) + IS_CODE(4)
IS_STRIDE    EQU 24           ; IS_SIZE rounded to a multiple of 4 (aligned nodes in an array)
; M7b — by-number dispatcher: public ExecBase.IntVects[16] (exec/execbase.i, offset $54), entries struct
; IntVector {iv_Data, iv_Code, iv_Node}. Chain (AddIntServer): iv_Data = &svlist[n], iv_Code =
; intr_chain_walker; exclusive vector (SetIntVector): IS_DATA/IS_CODE copied, iv_Node = the Interrupt. Some
; programs read iv_Data directly (e.g. IntVects[INTB_BLIT].iv_Data = GfxBase). The svlist[n] (struct List of
; servers, sorted by LN_PRI) are in an AllocMem'd block (EB_INTSVL).
IV_DATA      EQU 0
IV_CODE      EQU 4
IV_NODE      EQU 8
IV_SIZE      EQU 12
INTVECTS_NVEC EQU 16          ; numbers 0..15 (14 = INTEN unused, 15 = NMI)
IV_LIST_SIZE EQU 14           ; sizeof(struct List) of a server chain
INTSVL_TOTAL EQU (INTVECTS_NVEC*IV_LIST_SIZE) ; 224 (NO space: vasm truncates the operand at the space)
; CIA timers A and B — registers (offsets from the CIA base = register<<8)
CIA_TALO     EQU $400         ; timer A low
CIA_TAHI     EQU $500         ; timer A high (writing loads the latch)
CIA_TBLO     EQU $600         ; timer B low
CIA_TBHI     EQU $700         ; timer B high (writing loads the latch)
CIA_CRA      EQU $E00         ; control register A (b0=START, b3=RUNMODE 1-shot, b4=LOAD)
CIA_CRB      EQU $F00         ; control register B (same bits; b7 = ALARM, b5-6 = INMODE)
VBL_COUNT    EQU $00000500    ; VBlank counter in reserved low RAM (below the heap)
SCHED_ON     EQU $00000504    ; flag: 1 = scheduler armed (the handler switches)
WP_HTASK     EQU $00000508    ; M3e/f demo: TCB of task_H (so that task_L signals it)
WP_CONS      EQU $0000050C    ; M3e/f demo: wake-ups consumed by task_H (via yield-on-Permit)
WP_PROD      EQU $00000510    ; M3e/f demo: iterations of task_L (producer, never blocks)
WP_SPIN      EQU $00000514    ; M3f demo: iterations of task_S (dispatched ONLY by preemption)
WP_STAT      EQU $00000518    ; M3f demo: b0 = "M3F LIVE" marker already emitted
RES_LASTPRI  EQU $0000051C    ; M4 demo: last RT_PRI initialised (descending order check)
RES_COUNT    EQU $00000520    ; M4 demo: number of demo residents initialised
; $00000524: ex-VBL_SVC (M6a VBlank hook) — REMOVED in M7f (timer_vblank is a VERTB chain server)
VBL_SVCDATA  EQU $00000528    ; M6a: timer.device base (passed in a1 to the server; read by timer_micro_service)
CIAA_PTR     EQU $0000052C    ; M6b: ciaa.resource base (0 until created)
CIAB_PTR     EQU $00000530    ; M6b: ciab.resource base
CIA_FIRED    EQU $00000534    ; M6b: counter — an ICR vector was served (proof)
WP_TCONS     EQU $00000538    ; M7a demo: wake-ups of task_timer (blocks on the MICROHZ unit)
VBL_INSURG   EQU $0000053C    ; M7a: UBYTE — scheduler list surgery IN PROGRESS (vbl_handler).
                              ; Set BEFORE the TaskReady Enqueue/RemHead, cleared AFTER, at IPL7 (hence
                              ; invisible to INT6). A source of level > 3 (INT6/CIA-B) that observes it
                              ; set has preempted the surgery = re-entry hazard -> increments VBL_CLASH.
VBL_CLASH    EQU $00000540    ; M7a: counter of observed clashes (0 if the IPL7 gate holds; > 0 in RED)
INT2_SRV2    EQU $00000544    ; M7b: counter of the 2nd server of the PORTS chain (proves AddIntServer)
INT2_ORDER_SNAP EQU $00000548 ; M7b: CIA_FIRED at the 1st call of the 2nd server (> 0 => cia pri 10 before srv2 pri 0)
WP_HEART     EQU $0000054C    ; M7c: heartbeat of the user-mode task (first-light: survives preemptions)
WP_UMODE     EQU $00000550    ; M7c: UBYTE — a task observed itself in USER mode (SR bit S == 0)
M7C_STAT     EQU $00000554    ; M7c: UBYTE — b0 = "M7C USERMODE OK" marker already emitted
WP_UPREEMPT  EQU $00000558    ; M7c: observed preemptions (VBL_COUNT at the start of the proof)
; M7d — concurrency proof of interrupt-safe ports: shared port hammered by a TASK and an INTERRUPT
WP_SPORT     EQU $0000055C    ; APTR: shared stress port (0 until created)
WP_PORTT     EQU $00000560    ; GetMsg+PutMsg iterations of task_port (TASK consumer)
WP_PORTI     EQU $00000564    ; GetMsg+PutMsg iterations of the MICROHZ service (INTERRUPT producer)
WP_PORTFAIL  EQU $00000568    ; != 0: corruption detected on the interrupt side (MAGIC/IN_HAND failed)
M7D_STAT     EQU $0000056C    ; UBYTE: b0 = "M7D PORTS OK" already emitted
STRESS_TICK  EQU $0000056D    ; UBYTE: counter to rate-limit the stress on the INT6 side (1 in 4)
; M7D_STRESS_MAX: 0 = COEXISTENCE demo (task_port pri 0 + stress rate-limited 1/4, coexists with
; M3f/M7a/M7c). 1 = MAXIMUM CONTENTION (task_port high pri + stress on every INT6): config dedicated to
; the A/B RED of the interrupt-safe ports (Forbid corrupts the port's list / Disable does not). Default 0 (tree).
M7D_STRESS_MAX EQU 0
; stress message: struct Message (MN_SIZE=20) + MAGIC + IN_HAND (list corruption detectors)
MSG_MAGIC_OFF  EQU 20         ; sentinel: a corrupted GetMsg (wrong pointer) misses it
MSG_INHAND_OFF EQU 24         ; 1 = message "in hand" outside the list; a GetMsg returning it = duplicate = corruption
STRESS_MSG_SIZE EQU 28
STRESS_MAGIC  EQU $5D7C0DE5   ; expected MAGIC value
; M7e — per-level IPL fidelity: the handlers run at their NATIVE IPL (vbl=3, int2=2, int6=6)
; instead of a uniform IPL7. SELECTIVE proof: INT6 (level 6) preempts the BODY of vbl (level 3)
; BUT the scheduler's list surgery stays atomic (critical section of the switch raised to IPL7).
VBL_INBODY       EQU $0000056E ; UBYTE: vbl_handler body in progress (window preemptible by INT6)
VBL_IPL          EQU $0000056F ; UBYTE: IPL read by vbl via "move sr" (value-check: must == 3, not 7)
VBL_PREEMPT_COUNT EQU $00000570 ; long: INT6 observed VBL_INBODY set (preempted the body) -> > 0 in GREEN
IDLE_ENTERED     EQU $00000574 ; long: idle episodes of the dispatcher (instrumentation; > 0 in a normal run)
M7E_STAT         EQU $00000578 ; UBYTE: b0 = "M7E IPL OK" marker already emitted
; M7e A/B gates (reproducibility; default 0 = GREEN in tree, like M7D_STRESS_MAX):
; M7E_SURGERY_INTENA=1 (RED1): the switch surgery is masked by INTENA-off INSTEAD of IPL7 ->
;   the INTENA write has a propagation delay -> INT6 overlaps the VBL_INSURG window -> VBL_CLASH>0
;   (overlap, precondition of corruption; "M7A FAILED"). Proves that IPL7 is load-bearing.
; M7E_PROLOGUE_IPL7=1 (RED2): the vbl prologue raises IPL7 (M7a model, whole handler at IPL7) -> INT6
;   no longer preempts the BODY of vbl -> VBL_PREEMPT_COUNT==0 -> "M7E IPL OK" never emitted. Proves that
;   the native IPL (absence of IPL7 in the prologue) is load-bearing, not cosmetic.
M7E_SURGERY_INTENA EQU 0
M7E_PROLOGUE_IPL7  EQU 0
; M7E_COOP=1: COOPERATIVE non-regression (SCHED_ON=0, preemption OFF). Removes the 2 pure spinners
; (task_S, task_port) that would hog the CPU without preemption, and sets SPIN_THRESH=0 -> "M3F LIVE" emitted
; through the YIELD path alone (trap1->dispatch->switch). Proves that the yield->dispatch path holds without
; preemption after M7e. Default 0 (full preemptive build M3f/M7a/M7c/M7d/M7e).
M7E_COOP           EQU 0
; PROD=1: PRODUCTION ROM — takes the DEVELOPMENT HARNESS out of the boot path. Gated: M7 demo tasks
; (task_h/l/s/timer/port/fa/fb), D3 test clients (echo d3a, d3c_client, d3d..d3j), M7d stress port,
; proof instrumentation (VERTB tail server vbl_tail, test COPER source). KEPT: exec init +
; resident scan -> ALL the real modules (cia/timer/gfx/intuition/dos/trackdisk...), CIA-B/MICROHZ timer,
; live gameport, DF0: mount (OFS handler + driver + DeviceNode), con_handler, feeder, strap (floppy boot
; OR insert-disk screen), Initial CLI. The diagnostic serial markers remain (POST; emitted by the REAL
; path, not by the harness). Default 0 = proven dev ROM, byte-identical. OVERRIDDEN by -DPROD=1 (make
; kick-prod) -> no source edit needed to produce the prod variant. The `ifnd` protects the default.
        ifnd    PROD
PROD               EQU 0
        endif
; LOADSCREEN_DEMO=1 (-DLOADSCREEN_DEMO=1): after the init, displays a LOADING SCREEN (src/graphics/
; loadscreen.s) — sets up a View on the console's text bitplane, writes "Chargement bigseg..." + a
; progress bar during the STREAMING read of "bigseg", then "OK". DOES NOT RETURN (holds the screen).
; Standalone demo of the loading visual feedback. Default 0 (normal boot).
        ifnd    LOADSCREEN_DEMO
LOADSCREEN_DEMO    EQU 0
        endif
; F2A_NO_HANDSHAKE=1 (RED F2a): kbd_selftest does NOT do the keyboard handshake (pulse CRA bit 6) -> the emulated
; keyboard stalls after the 1st byte -> $FE (terminate power-up) never received -> "F2 KBD OK" absent. Isolates the
; handshake (load-bearing: without ack, the keyboard stream does not progress). Default 0.
F2A_NO_HANDSHAKE   EQU 0
; F2B_NO_FEED=1 (RED F2b): kbd_interrupt decodes+handshakes but does NOT push the ASCII into the keyboard ring ->
; a command typed on the keyboard never reaches the shell -> "E2 SHELL ver OK" absent after injection. Isolates
; the keyboard->console wiring (load-bearing). Reception/decoding (F2a "F2 KBD OK") stays intact. Default 0.
F2B_NO_FEED        EQU 0
; INPUT_NO_PROPAGATE=1 (RED #2): IND_WRITEEVENT does NOT walk the handler chain -> the injected event
; reaches no handler -> "INPUT OK" absent (ADDHANDLER did succeed though). Isolates the propagation. Default 0.
INPUT_NO_PROPAGATE EQU 0
; CON_NO_BLIT=1 (RED #3a): CMD_WRITE advances the cursor but does NOT blit the glyph -> the bitplane stays at 0 ->
; the readback of the non-space cells does not match the glyphs -> "CONSOLE WRITE OK" absent. Isolates the blitter.
; Default 0.
CON_NO_BLIT        EQU 0
; CON_NO_READBUF=1 (RED #3b): console_input_handler cooks the RAWKEY but does NOT push it into the read buffer ->
; CMD_READ returns nothing -> "CONSOLE READ=v" absent. Isolates the input.device->console READ wiring. Default 0.
CON_NO_READBUF     EQU 0
; DV_CORRUPT=1 (RED #4): the disk-validator corrupts the bitmap block after reading (one byte flipped) -> its OFS
; checksum (sum of the longs == 0) fails -> dv_validate rejects -> "DISK VALID OK" absent. Isolates the integrity
; check. Default 0.
DV_CORRUPT         EQU 0
; KEYMAP_AZERTY=1: keymap.resource installs the FR AZERTY keymap by default (otherwise US QWERTY). Produces the
; AZERTY variant of the ROM (kbd_cook cooks according to AZERTY). Default 0 (US). Build: make kick after setting
; it to 1.
KEYMAP_AZERTY      EQU 0
; KM_NO_SHIFT=1 (RED #5): kbd_cook ignores the SHIFT qualifier (always the unshifted table) -> the test's
; q+SHIFT=='Q' assertion fails -> "KEYMAP OK" absent. Isolates qualifier handling. Default 0.
KM_NO_SHIFT        EQU 0
; FEEDER_NO_WRITEEVENT=1 (RED feeder): the feeder drains the ring but does NOT CALL IND_WRITEEVENT -> input.device
; receives nothing -> console.device receives nothing -> "FEEDER OK" absent. Isolates feeder -> input.device. Default 0.
FEEDER_NO_WRITEEVENT EQU 0
; SHELL_ON_SCREEN=1: the shell (Initial CLI) is plugged into the console handler backed by console.device (screen +
; serial mirror + keyboard via the feeder) instead of the serial con_handler. Default 0 (shell on serial; = control/RED
; of the swap).
SHELL_ON_SCREEN    EQU 0
; M7f — VERTB as a server chain. struct Interrupts (IS_SIZE=22) in RESERVED LOW RAM (< HEAP_LOWER
; $1000 -> outside the AllocMem pool; AddIntServer Enqueues them so they must be writable).
SCHED_INT      EQU $00000580 ; struct Interrupt of the scheduler server (round-robin quantum), pri 20
TIMER_VBL_INT  EQU $00000596 ; struct Interrupt of the timer.device VBLANK server, pri 0
VBL_TAIL_INT   EQU $000005AC ; struct Interrupt of the proof server (chain tail), pri -10
VERTB_CHAIN_N  EQU $000005C2 ; long: increments of the tail server -> proves that the walker goes through
                             ; the WHOLE VERTB chain (hence >= 2 servers before it)
M7F_STAT       EQU $000005C6 ; UBYTE: b0 = "M7F VERTB OK" marker already emitted
VERTB_CHAIN_THRESH EQU 50     ; complete chain walks required for "M7F VERTB OK"
; M7f A/B gate (reproducibility; default 0 = GREEN):
; M7F_SCHED_STOPS_CHAIN=1 (RED): sched_server returns Z-CLEAR ("handled, stop") instead of Z-set ->
;   the walker STOPS the chain after sched -> timer_vblank + tail server never called ->
;   VERTB_CHAIN_N frozen + VBLANK unit dead (M6A fails early). Proves the "call-all" semantics (Z-set)
;   of the chain = the walk DOES dispatch the following servers in sequence.
M7F_SCHED_STOPS_CHAIN EQU 0
; M7g — multi-source INTREQR decoding: proof that int3 dispatches a 2nd level 3 source (COPER)
COPER_FIRED    EQU $000005C8 ; long: calls of coper_test (2nd level 3 source, served via the decoding)
COPER_TICK     EQU $000005CC ; UBYTE: rate limiter of the software triggering of COPER (1 VBlank in 4)
M7G_STAT       EQU $000005CD ; UBYTE: b0 = "M7G MULTISRC OK" marker already emitted
COPER_THRESH   EQU 20        ; coper_test calls required for "M7G MULTISRC OK"
; M7g A/B gate (reproducibility; default 0 = GREEN):
; M7G_MONO_SOURCE=1 (RED): int3 decodes AND acks COPER/BLIT but does NOT DISPATCH them (mono-dispatch
;   behaviour) -> COPER_FIRED frozen, no storm (COPER stays acked), everything else identical ->
;   "M7G MULTISRC OK" absent. Proves that DISPATCH by decoded source is load-bearing.
M7G_MONO_SOURCE EQU 0
; M7h — real quantum: sched_server preempts after M7H_QUANTUM ticks (like exec, default 4) instead of
; every tick. QUANTUM_ELAPSED = ticks since the last task change (reset by dispatch_in on a
; REAL change). QUANTUM_EXPIRE_N = number of expirations (throughput proof). Observable ONLY in
; isolation (M7H_QUANTUM_DEMO): in the default demo INT6 dispatches ~140/s -> ELAPSED reset before
; reaching the quantum -> quasi-no-op (non-regression: M3F passes via the INT6 rotation, found in M7f).
QUANTUM_ELAPSED EQU $000005CE ; UBYTE: VBlank ticks of the current time slice
QUANTUM_EXPIRE_N EQU $000005D0 ; long: quantum expirations (throughput: ~VBL_COUNT/QUANTUM in isolation)
Q2_RUNS        EQU $000005D4 ; long: iterations of the 2nd isolation spinner (proves the real rotation)
M7H_STAT       EQU $000005D8 ; UBYTE: b0 = "M7H QUANTUM OK" marker already emitted
; M7H_QUANTUM: length of the time slice in VBlank ticks. GREEN=4 (faithful to exec). RED=1 (preemption every
; tick = old M7f behaviour) -> in isolation, rotation every tick -> QUANTUM_EXPIRE_N~=VBL_COUNT ->
; the discriminant (EXPIRE_N*2 < VBL_COUNT) fails -> "M7H QUANTUM OK" absent.
M7H_QUANTUM     EQU 4
; M7H_QUANTUM_DEMO=1: ISOLATION demo (2 spinners pri 0, NO other tasks) to make the quantum
; observable (no higher-priority preemptor; INT6 runs but Signals nobody -> does not rotate).
M7H_QUANTUM_DEMO EQU 0
; M7j — RemTask (life cycle): proof that a terminating task frees its stack + TCB (AvailMem goes back up)
RM_RUNS          EQU $000005DC ; long: iterations of task_rm before it RTSes (-> task_exit -> RemTask self)
M7J_AVAIL_BEFORE EQU $000005E0 ; long: AvailMem captured BEFORE the creation of task_rm (baseline)
M7J_STAT         EQU $000005E4 ; UBYTE: b0 = "M7J REMTASK OK" marker already emitted
RM_THRESH        EQU 20        ; iterations of task_rm before self-removal
M7J_RECOVER      EQU 1024      ; AvailMem must go back up by at least this much (stack 2048 + TCB) to prove the free
; M7J_DEMO=1: adds task_rm (task that runs RM_THRESH times then RTS -> RemTask self) and the AvailMem
; proof in a surviving task. Default 0 (RemTask compiled but not exercised -> non-regression).
M7J_DEMO         EQU 0
; M7J_NOFREE=1 (RED): RemTask marks/removes but SKIPS the FreeMems -> AvailMem does not go back up (leak) ->
; "M7J REMTASK OK" absent. Proves that the stack+TCB FreeMem is load-bearing.
M7J_NOFREE       EQU 0

; M7l — real us calibration of MICROHZ. The MICROHZ unit is clocked by CIA-A timer B (ciaa.resource, ICR bit 1,
; level 2, like 1.3: spec docs/analysis/timer-v34.md), in ONE-SHOT mode armed on the nearest deadline (at most
; TIMER_CAP E ticks). PAL E clock = 709379 Hz (= CPU 7.09379 MHz / 10). A request keeps its remainder as (seconds,
; E ticks within the second); the elapsed time is read from the CIA counter (more accurate than the nominal
; accounting of 1.3). The latency between end of one-shot and re-arming is not counted: arming wide (TIMER_CAP)
; makes it negligible. Empty queue: timer stopped. No CIA-B timer is programmed by the OS (games take them).
E_PER_SEC      EQU 709379     ; E-clock ticks per second (PAL)
TIMER_CAP      EQU $FFFF      ; maximum arming (~92 ms)
; Proof = cross-clock: a known LONG MICROHZ request, measured against the VBLANK clock (50 Hz,
; independent: display raster vs CPU E-clock). 0.5 s must elapse in ~25 VBLANK ticks. NOT tautological
; (the two clocks derive from different hardware): validates the E constant to ~+/-10 %.
M7L_CAL_US     EQU 500000     ; duration of the calibration request (us) = 0.5 s
M7L_LO         EQU 22         ; low band (VBLANK ticks); 0.5 s = 25 ticks; RED OLD_CONV -> ~0-1
M7L_HI         EQU 28         ; high band; scheduling latency can only INFLATE (never < 25)
M7L_VBL_BEFORE EQU $000005E8  ; long: VBL_COUNT at the start of the calibration request (T0)
M7L_ELAPSED    EQU $000005EC  ; long: VBLANK ticks elapsed during the calibration (measurement)
M7L_STAT       EQU $000005F0  ; UBYTE: b0 = "M7L MICROHZ CALIB OK" marker already emitted
GFX_COPLIST_PTR EQU $000005F4 ; M4a: long — chip address of the copper list (published by gfx_display_init)
DOS_HANDLERPORT EQU $000005F8 ; D3a: long — APTR of the pr_MsgPort of the echo handler process (published by the setup)
DOS_FSPORT      EQU $000005FC ; D3b: long — APTR of the pr_MsgPort of the DF0: (OFS) file-handler process
TD_CURCYL       EQU $00000600 ; trackdisk: word — current cylinder of the head (valid iff TD_CYLVALID != 0)
TD_CYLVALID     EQU $00000602 ; trackdisk: byte — 0 = unknown position (recalibrate); !=0 = TD_CURCYL reliable
DOS_CONPORT     EQU $00000604 ; E1: long — APTR of the serial console handler process's pr_MsgPort (published by setup)
CON_STATE       EQU $00000608 ; E1: long — APTR of the console handler state block (timer.device + reply port + request)
; F2b: SPSC keyboard ring (producer = kbd_interrupt/INT2; consumer = con_handler READ). Lock-free:
; the producer writes the data then advances KBD_TAIL; the consumer reads then advances KBD_HEAD. No masking.
KBD_RING        EQU $0000060C ; F2b: 64 bytes — circular buffer of decoded keyboard ASCII
KBD_RSIZE       EQU 64        ; ring size (power of 2)
KBD_RMASK       EQU 63        ; index mask (KBD_RSIZE-1)
KBD_HEAD        EQU $0000064C ; F2b: word — READ index (consumer: con_handler)
KBD_TAIL        EQU $0000064E ; F2b: word — WRITE index (producer: kbd_interrupt)

; --- input.device + InputEvent (#2) — public ABI (devices/input.i, devices/inputevent.i) ---
IND_ADDHANDLER  EQU 9            ; io_Command: adds a handler (struct Interrupt) to the chain
IND_REMHANDLER  EQU 10           ; io_Command: removes a handler from the chain
IND_WRITEEVENT  EQU 11           ; io_Command: injects a list of InputEvents into the handler chain
IND_SETTHRESH   EQU 12           ; io_Command: delay before the 1st repeat (timeval of the request)
IND_SETPERIOD   EQU 13           ; io_Command: period of the following repeats
ID_HANDLERS     EQU LIB_SIZE     ; input.device base: struct List (handler chain)
ID_THRESH       EQU LIB_SIZE+14  ; timeval: repeat delay (default 0.8 s)
ID_PERIOD       EQU LIB_SIZE+22  ; timeval: repeat period (default 0.1 s)
INPUT_SIZE      EQU LIB_SIZE+30
IECLASS_NULL    EQU 0            ; ie_Class: neutralised event (ignored by the following handlers)
IECLASS_RAWKEY  EQU 1            ; ie_Class: raw key (keycode + up/down)
IECLASS_RAWMOUSE EQU 2           ; ie_Class: raw mouse (button + position)
IECLASS_TIMER   EQU 6            ; ie_Class: input.device tick (10 per second)
IECLASS_DISKREMOVED EQU 15       ; ie_Class: floppy ejected (emitted by the file system, spec disk-change-v34 §3)
IECLASS_DISKINSERTED EQU 16      ; ie_Class: floppy inserted and mounted
IEQUALIFIER_REPEAT EQU $0200     ; ie_Qualifier: automatic key repeat event
IECODE_LBUTTON  EQU $68          ; ie_Code: left button (down; up = | $80)
IECODE_RBUTTON  EQU $69          ; ie_Code: right button (down; up = | $80)
IECODE_NOBUTTON EQU $FF          ; ie_Code: pure movement event (no button)
IECODE_UP_PREFIX EQU $80         ; ie_Code: release (button code | $80)
IE_NEXTEVENT    EQU 0            ; struct InputEvent: APTR next event
IE_CLASS        EQU 4            ; UBYTE class
IE_SUBCLASS     EQU 5            ; UBYTE subclass
IE_CODE         EQU 6            ; UWORD code (keycode for RAWKEY; button for RAWMOUSE)
IE_QUALIFIER    EQU 8            ; UWORD qualifiers
IE_X            EQU 10           ; WORD ie_position.ie_xy.ie_x (mouse position; absolute in our injection)
IE_Y            EQU 12           ; WORD ie_position.ie_xy.ie_y
IE_TIMESTAMP    EQU 14           ; struct timeval: system time of the event
IE_SIZEOF       EQU 22           ; sizeof(struct InputEvent)
; input.device proof globals (#2), reserved low RAM (set by the boot.s test handlers)
INPUT_SEQ       EQU $00000650 ; word: counter of handler call order (chain walk)
INPUT_H1_ORD    EQU $00000652 ; word: order in which the high-pri handler ran (must = 1)
INPUT_H2_ORD    EQU $00000654 ; word: order in which the low-pri handler ran (must = 2)
INPUT_CODE      EQU $00000656 ; word: ie_Code seen by the handlers (must = injected synthetic keycode)

; --- keymap.resource + cook (#5): keycode(+qualifiers) -> ASCII, US/AZERTY keymaps ---
KBD_QUAL     EQU $00000658 ; word: qualifier state tracked by kbd_interrupt (LSHIFT$01 RSHIFT$02 CAPS$04 CTRL$08)
KM_RESBASE   EQU $0000065A ; long: keymap.resource base (published at init; read by kbd_cook)
KMR_LO       EQU LIB_SIZE      ; keymap.resource base: APTR unshifted table (km_xx_lo)
KMR_HI       EQU LIB_SIZE+4    ; APTR shifted table (km_xx_hi)
KMR_SIZE     EQU LIB_SIZE+8
KQ_SHIFT     EQU $03           ; ie_Qualifier mask: LSHIFT | RSHIFT
KQB_CAPS     EQU 2             ; CAPSLOCK bit in ie_Qualifier ($04)
KQB_CTRL     EQU 3             ; CONTROL bit in ie_Qualifier ($08)
KQB_RCOMMAND EQU 7             ; right Amiga bit in ie_Qualifier ($80)
; keyboard feeder -> input.device (integration F, item 1): RAW ring fed by kbd_interrupt (raw tap at the same
; point as the cooked push, after the qualifier filter), drained by the feeder process -> IND_WRITEEVENT(RAWKEY).
KBD_FHEAD    EQU $0000065E ; word: head (consumer = feeder)
KBD_FTAIL    EQU $00000660 ; word: tail (producer = kbd_interrupt); indices = BYTE OFFSETS (step 2)
KBD_FEEDRING EQU $00000662 ; 32 bytes: 16 word entries = (KBD_QUAL<<8 | keycode) snapshotted per keystroke
KBD_FRMASK   EQU $1E       ; byte offset mask (size 32 - 2)
REQ_HIT      EQU $00000682 ; word: requester — gadget hit by a click (set by req_input_handler, proof)

; --- gameport.device (hardware mouse) + Intuition pointer accumulator (live M6R wiring) ---
; gameport reads JOY0DAT (quadrature deltas) + CIAA_PRA bit 6 (left button, active-low) every VBlank, computes
; the signed deltas (8-bit wraparound), detects the button edges, and injects RAWMOUSE InputEvents into
; input.device via IND_WRITEEVENT (keyboard feeder pattern; no input.task — documented deviation). The
; pointer_input_handler (intuition, pri 50) accumulates these RELATIVE deltas into an ABSOLUTE position clamped to
; the screen and rewrites ie_X/ie_Y -> the existing req_input_handler (pri 0) hit-tests in absolute, unchanged = the
; live wiring.
PTR_XMAX     EQU 320            ; screen bounds for the pointer clamp (320x256: console/bootscreen)
PTR_YMAX     EQU 256
GP_POLLS_THRESH EQU 25          ; VBlank polls (~0.5 s) before "GP VBLANK LIVE OK" (server lives in the system)
PTR_X        EQU $00000684 ; word: absolute pointer X (accumulated by pointer_input_handler, clamped)
PTR_Y        EQU $00000686 ; word: absolute pointer Y
INT_IBASE    EQU $00000740 ; long: IntuitionBase (set at its init) — the pointer handler moves the sprite with it
KBD_DEVBASE  EQU $00000744 ; long: keyboard.device base (set at its init) — kbd_interrupt hands each keycode to it
TD_CDIRTY    EQU $00000748 ; trackdisk: TD_NCACHE bytes — slot modified by CMD_WRITE, not yet written to disk
TD_CHGCNT    EQU $00000750 ; trackdisk: long — disk change counter (TD_CHANGENUM)
DOS_OWCTX    EQU $00000754 ; dos: long — OFS write context (ofswrite.s), allocated on first need
EXEC_SOFTLIST EQU $00000758 ; exec: struct List (14 bytes) of the pending software interrupts (Cause)
EXEC_ALERTSTUB EQU $00000766 ; exec: 6 bytes — JMP exec_Alert in RAM: Alert vector points here (not ROM, cf. setpatch-138.md)
DOS_HSEM     EQU $0000076C ; dos: SignalSemaphore (46 bytes, up to $799) — only one handler start at a time
HND_CTX      EQU $000007C0 ; dos: long — context of the DF0: file-handler (disk change, handler.s)
HND_REFVOL   EQU $000007C4 ; dos: long — BPTR of the absent volume of the DF0: handler's last 218 refusal ("replace")
MT_TABLE     EQU $0000079C ; long: allocation tracer table (diagnostic ROM -DMEMTRACK=1 only)
INT2_BUSY    EQU $000007A0 ; byte: int2_dispatch serves the PORTS chain (read by timer.device VBLANK server recovery)
TD_DMATASK   EQU $000007A2 ; trackdisk: long — task waiting for the end of a disk DMA (SIGF_SINGLE), 0: none
TD_DMATMO    EQU $000007A6 ; trackdisk: word — frames left before giving up on this DMA (counted down at VBlank)
TD_DMADONE   EQU $000007A8 ; trackdisk: byte — DSKBLK received for the current DMA
TD_DSKINT    EQU $000007AA ; trackdisk: struct Interrupt (22 bytes, up to $7BF) of the DSKBLK vector (level 1)
GP_PREV_JOY  EQU $00000688 ; word: previous JOY0DAT (delta base; primed at gp_install = current JOY0DAT, NOT 0)
GP_PREV_BTN  EQU $0000068A ; byte: previous left button (edge-detect; 0=released 1=pressed)
GP_PREV_RBTN EQU $0000068B ; byte: previous right button (same)
GP_POLLS     EQU $0000068C ; long: poll counter of gp_vblank_server (live proof: advances on real VBlanks)
GP_INPUTBASE EQU $00000690 ; long: input.device base for RAWMOUSE injection (0 = no injection)
GP_CAP_N     EQU $00000694 ; word: RAWMOUSE events seen by the capture handler (gameport tests)
GP_CAP_CODE  EQU $00000696 ; word: last captured ie_Code
GP_CAP_DX    EQU $00000698 ; word: last captured ie_X (delta)
GP_CAP_DY    EQU $0000069A ; word: last captured ie_Y (delta)
GP_LIVE_STAT EQU $0000069C ; byte: b0 = "GP VBLANK LIVE OK" already emitted +pad $69D
GP_VBL_INT   EQU $000006A0 ; struct Interrupt (IS_SIZE=22) of the gameport VBlank server -> $6A0..$6B5
; CONSUMER handlers of the requester, registered PERSISTENTLY on input.device in the M6R insert-disk branch
; (no teardown) -> the gameport->input.device->pointer->requester chain is LIVE in the running system
; (symmetric of the producer server gp_vblank_server). struct Interrupts in reserved low RAM.
PTR_INT      EQU $000006B6 ; struct Interrupt (22) of pointer_input_handler (pri 50) -> $6B6..$6CB
REQ_INT      EQU $000006CC ; struct Interrupt (22) of req_input_handler (pri 0) -> $6CC..$6E1
FORBID_TEST_FLAG EQU $000006E2 ; long: Forbid atomicity proof — task_fb sets it to 1 when it runs
FB_TASK      EQU $000006E6 ; long: TCB of task_fb (so that task_fa signals it)
SH_STK       EQU 8192       ; stack of the initial CLI (shell.s): the commands it launches run on it
TD_CACHEBUF  EQU $000006EA ; trackdisk: long — cache of decoded tracks (TD_CNSLOTS x 5632 bytes; 0 = not yet allocated)
TD_CNSLOTS   EQU $000006EE ; trackdisk: word — number of cache slots (TD_NCACHE, or 1 if memory is tight)
TD_MOTORON   EQU $00000700 ; trackdisk: byte — DF0 motor on (latched): no spin-up at the next read
TD_BUSY      EQU $00000701 ; trackdisk: byte — drive access in progress (the VBlank server does not turn the motor off)
TD_MOTORCNT  EQU $00000702 ; trackdisk: word — VBlank ticks before turning off the idle motor
TD_VBLINT    EQU $00000704 ; trackdisk: struct Interrupt (22 bytes) of the motor turn-off VBlank server
TD_MOTORIDLE EQU 100       ; 2 s of inactivity (50 Hz) before turn-off, like the delay of the original trackdisk
TD_CTICK     EQU $0000071A ; trackdisk: word — LRU clock of the track cache
TD_CTRK      EQU $00000720 ; trackdisk: TD_NCACHE words — track of each slot ($FFFF = empty)
TD_CAGE      EQU $00000730 ; trackdisk: TD_NCACHE words — last access (TD_CTICK) of each slot
TD_NCACHE    EQU 8         ; tracks kept in cache (8 x 5632 = 44 KB; 16: marginal gain measured, 87 s -> 83 s)
DOS_DOSBASE  EQU $000006F0 ; long: DosBase (set by dos initFunc) — the BCPL runtime does not have a6 = DosBase
; GP_NO_WRAP=1 (RED): gp_delta8 subtracts the 0..255 counters as WORDS (without byte sign-extend) -> when crossing
; $FF/$00 the delta is wrong ($FE->$01 gives -253 instead of +3) -> "GAMEPORT OK" absent (the wrap vector of the
; gp_poll test fails). Isolates the 8-bit wraparound model of the quadrature counters (load-bearing). Default 0.
GP_NO_WRAP   EQU 0

; SCHED_NO_FORBID_GATE=1 (RED Forbid atomicity): removes the EB_TDNEST/EB_IDNEST guard of intr_isr_defer -> a
; deferred dispatch (AttnResched) happens EVEN under Forbid -> a task printing under Forbid is preempted in
; the middle of ser_puts -> "FORBID ATOMIC OK" absent (task_fb preempts task_fa during its Forbid and sets the flag).
; M3F LIVE stays present (task_l's Forbid window is short + its yield-on-Permit wants task_h precisely).
; Isolates the Forbid guard at the preemption consumption point. Default 0.
SCHED_NO_FORBID_GATE EQU 0
; GP_NO_EDGE=1 (RED): gp_poll emits a button event on EVERY poll where the button is pressed (no edge) -> a
; HELD button produces N events instead of 1 -> the counter of the edge test (2 expected) goes to 3 -> "GAMEPORT OK"
; absent. Isolates edge-detection (load-bearing: without it, flood of down events). Default 0.
GP_NO_EDGE   EQU 0
; PTR_NO_CLAMP=1 (RED): pointer_input_handler does NOT clip the position to the screen bounds -> a movement that
; goes past an edge leaves the screen (negative) -> the accumulated position is wrong -> the gadget hit-test misses ->
; "M6R LIVE OK" absent. Isolates the clamp (load-bearing). Default 0.
PTR_NO_CLAMP EQU 0

; --- Max size of a buffered file (handler HS_BUF + LoadSeg): cap-bump 16K -> 32K (NOT streaming) ---
; The READ cap is the handler's whole-file buffer (HND_FILEMAX) + that of dos_loadseg (D2). We raise it
; to 32 KB (handles an executable up to 32 KB, was 16 KB); 2 concurrent buffers = 64 KB transient (safe on the
; A500 heap ~500 KB). Real incremental OFS reading (streaming, no whole-file buffer) remains a deferred DEBT.
; LOADSEG_CAP16K=1 (RED): re-caps at 16 KB -> an executable > 16 KB (bigseg) truncates at FINDINPUT -> does not
; load/run -> "LOADSEG BIG OK" absent (D3E/d3dtest, small, stays OK). Isolates the cap-bump (proves it is
; load-bearing). Default 0.
LOADSEG_CAP16K EQU 0
                ifne    LOADSEG_CAP16K
DOS_FILEMAX  EQU 16384
                endc
                ifeq    LOADSEG_CAP16K
DOS_FILEMAX  EQU 32768
                endc

; --- console.device (#3a): text rendering by blitting 8x8 glyphs into a bitplane (1 plane) ---
CON_COLS     EQU 40            ; character columns (320 px / 8)
CON_BYTEW    EQU 40            ; bytes per bitplane line (= CON_COLS, 1 byte = 8 px = 1 glyph wide)
CON_PXH      EQU 256           ; bitplane height in pixels (32 text lines)
CON_BMSIZE   EQU CON_BYTEW*CON_PXH ; 10240 bytes: bitplane size (chip RAM)
; console.device base = Library + text state
CONB_BITMAP  EQU LIB_SIZE      ; APTR bitplane
CONB_BWIDTH  EQU LIB_SIZE+4    ; UWORD bytes/line (stride)
CONB_PXROWS  EQU LIB_SIZE+6    ; UWORD height px
CONB_CURX    EQU LIB_SIZE+8    ; UWORD current char column (0..CON_COLS-1)
CONB_CURY    EQU LIB_SIZE+10   ; UWORD current pixel line (0,8,16,... multiple of 8)
; #3b: read buffer (keyboard via input.device) + struct Interrupt of the handler registered on input.device
CONB_RHEAD   EQU LIB_SIZE+12   ; UWORD read index of the read buffer (consumer = CMD_READ)
CONB_RTAIL   EQU LIB_SIZE+14   ; UWORD write index (producer = console_input_handler)
CONB_RBUF    EQU LIB_SIZE+16   ; 16 bytes: ASCII ring cooked from the RAWKEYs received via input.device
CONB_INT     EQU LIB_SIZE+32   ; struct Interrupt (IS_SIZE=22) of the handler registered via IND_ADDHANDLER
CONB_ESC     EQU LIB_SIZE+56   ; UBYTE state of the sequence filter: 0 normal, 1 after ESC, 2 inside a CSI
CONB_RQ      EQU LIB_SIZE+60   ; APTR queue of the pending CMD_READs (linked by LN_SUCC), open units
CONB_GFXBASE EQU LIB_SIZE+64   ; APTR GfxBase: rendering into the windows' RastPort (ConUnit units)
CONB_UNITS   EQU LIB_SIZE+68   ; APTR list of the open ConUnits (linked by CU_NEXT): key routing
CONB_IBASE   EQU LIB_SIZE+72   ; APTR IntuitionBase (looked up on first need: intuition initialises afterwards)
CONDEV_SIZE  EQU LIB_SIZE+76
CON_RBSIZE   EQU 16            ; read buffer size (power of 2)
CON_RBMASK   EQU 15
; M7L_OLD_CONV=1 (RED): restores the old VBLANK conversion (/20000) on the MICROHZ unit -> the 0.5 s
; request expires in ~25 interrupts ~= 9 ms < 1 VBLANK tick -> out of band -> "M7L" NOT emitted. The request
; value of the task_timer loop is gated in parallel (TT_MICRO_REQ) so that the PERIOD stays ~7 ms
; under both conversions -> surgical RED: only M7L falls, M3F..M7G stay green.
M7L_OLD_CONV   EQU 0

; --- struct Node / List / Library / ExecBase offsets (exec-spec.md) ---
LN_SUCC      EQU 0
LN_PRED      EQU 4
LN_TYPE      EQU 8
LN_PRI       EQU 9           ; priority (signed BYTE) — Enqueue sorting
LN_NAME      EQU 10
LH_TAIL      EQU 4
NT_LIBRARY   EQU 9
LIB_NEGSIZE  EQU $10
LIB_POSSIZE  EQU $12
LIB_VERSION  EQU $14
LIB_REVISION EQU $16
LIB_IDSTRING EQU $18
LIB_OPENCNT  EQU $20
LIB_SIZE     EQU 34            ; sizeof(struct Library) (minimal base for MakeLibrary)
LIB_FLAGS    EQU $0E           ; exec/libraries.i: lib_Flags
LIB_SUM      EQU $1C           ; lib_Sum: checksum of the vector table
LIBB_CHANGED EQU 1             ; LIBF_CHANGED: table modified (SetFunction), sum to recompute
LIBB_SUMUSED EQU 2             ; LIBF_SUMUSED: the sum is checked
TIMER_VBLQ   EQU LIB_SIZE      ; timer.device: request list of the VBLANK unit (struct List)
TIMER_MICROQ EQU LIB_SIZE+14   ; request list of the MICROHZ unit (CIA-A timer B, level 2) (struct List)
TIMER_SYSSECS EQU LIB_SIZE+28  ; system time: seconds at the reference (TR_SETSYSTIME)
TIMER_SYSVBL EQU LIB_SIZE+32   ; VBL_COUNT at the reference
TIMER_ARMED  EQU LIB_SIZE+36   ; long: E ticks armed on CIA-A timer B (0 = stopped)
TIMER_UNIQ   EQU LIB_SIZE+40   ; long: us added to time reads made within the TIMER_UVBL tick (strictly increasing time)
TIMER_UVBL   EQU LIB_SIZE+44   ; long: VBL_COUNT of the last time read
TD_SIZE      EQU LIB_SIZE+48   ; size of the timer.device base (Library + 2 unit lists + system time + arming)
UNIT_MICROHZ EQU 0             ; unit selector in IO_UNIT (= real timer.device numbering)
UNIT_VBLANK  EQU 1             ; (OpenDevice would set a struct Unit*; our minimal impl = the index)
EB_CHKBASE    EQU $26
EB_MAXLOCMEM  EQU $3E
EB_THISTASK   EQU $114         ; current task (struct Task *)
EB_IDNEST     EQU $126
EB_TDNEST     EQU $127
EB_ATTNFLAGS  EQU $128
EB_ATTNRESCHED EQU $12A         ; UWORD: pending reschedule (set by Signal, consumed
                                ; by Permit/Enable when the nesting unlocks = yield)
EB_RESMODULES EQU $12C          ; APTR: NUL-terminated array of struct Resident* (pri-sorted)
EB_TASKTRAPCODE EQU $130        ; APTR: default trap handler of the tasks
EB_MEMLIST      EQU $142
EB_RESOURCELIST EQU $150
EB_DEVICELIST   EQU $15E
EB_INTRLIST     EQU $16C
EB_LIBLIST      EQU $17A
EB_PORTLIST     EQU $188
EB_TASKREADY    EQU $196
EB_TASKWAIT     EQU $1A4
EB_LASTALERT    EQU $202       ; LastAlert[4]: number and second number of the last alert (-1: none)
EB_VBLANKFREQ   EQU $212
EB_POWERFREQ    EQU $213
EB_SEMLIST      EQU $214
EB_INTVECTS     EQU $54         ; IntVects[16] (struct IntVector, 12 bytes): public, up to ThisTask ($114)
EB_INTSVL       EQU $222        ; M7b: APTR -> block of the 16 server lists (AddIntServer), AllocMem'd
                                ; at init_ints. Fits in the positive area ($222+4 <= EXEC_POSSIZE $230).

; struct MemHeader / MemChunk + memory attributes (exec/memory.i, V34)
NT_MEMORY     EQU 10
MEMF_PUBLIC   EQU $1
MEMF_CHIP     EQU $2
MEMF_FAST     EQU $4
MEMF_TYPEMASK EQU $7           ; memory TYPE bits in V34 (PUBLIC|CHIP|FAST)
MEMF_CLEAR    EQU $10000
MEMF_LARGEST  EQU $20000       ; AvailMem: largest contiguous block (not the sum)
MH_ATTRIBUTES EQU 14
MH_FIRST      EQU 16          ; -> struct MemChunk
MH_LOWER      EQU 20
MH_UPPER      EQU 24
MH_FREE       EQU 28
MH_SIZE       EQU 32          ; sizeof(struct MemHeader)
MC_NEXT       EQU 0
MC_BYTES      EQU 4

; struct Task (exec/tasks.i) — base at LN_SIZE=14
NT_TASK       EQU 1
NT_INTERRUPT  EQU 2
TS_RUN        EQU 2           ; task running
TS_READY      EQU 3
TS_WAIT       EQU 4           ; task blocked (Wait/WaitPort) -> TaskWait list
TS_REMOVED    EQU 5           ; M7j: task being removed (RemTask)
TC_FLAGS      EQU 14
TC_STATE      EQU 15
TC_IDNESTCNT  EQU 16
TC_TDNESTCNT  EQU 17
TC_SIGALLOC   EQU 18
TC_SIGWAIT    EQU 22
TC_SIGRECVD   EQU 26
TC_SIGEXCEPT  EQU 30
TC_TRAPALLOC  EQU 34          ; UWORD: traps 0-15 allocated (AllocTrap)
TC_TRAPABLE   EQU 36
TC_TRAPDATA   EQU 46          ; APTR: free data of the task's trap handler
TC_TRAPCODE   EQU 50          ; APTR: handler of the task's CPU exceptions (0 -> TaskTrapCode)
TC_SPREG      EQU 54
TC_SPLOWER    EQU 58
TC_SPUPPER    EQU 62
TC_MEMENTRY   EQU 74          ; struct List: MemLists freed by RemTask (FreeEntry)
TC_SIZE       EQU 92
ML_NUMENTRIES EQU 14          ; exec/memory.i: struct MemList (Node, NumEntries, MemEntry[])
ML_ME         EQU 16
LVO_ALLOCENTRY EQU -222
LVO_FREEENTRY EQU -228
SYS_SIGALLOC  EQU $FFFF        ; signals 0-15 pre-allocated (reserved for the system)

; struct MsgPort (exec/ports.i) — base at LN_SIZE=14
NT_MSGPORT    EQU 4
NT_MESSAGE    EQU 5
NT_REPLYMSG   EQU 7
MP_FLAGS      EQU 14
MP_SIGBIT     EQU 15
MP_SIGTASK    EQU 16
MP_MSGLIST    EQU 20          ; struct List
MP_SIZE       EQU 34
PF_ACTION     EQU 3           ; mask of the action bits
PA_SIGNAL     EQU 0
PA_IGNORE     EQU 2
; struct Message (exec/ports.i)
MN_REPLYPORT  EQU 14
MN_LENGTH     EQU 18
MN_SIZE       EQU 20

; struct IORequest (exec/io.i) / timerequest (devices/timer.i)
IO_DEVICE    EQU 20          ; struct Device *
IO_UNIT      EQU 24          ; struct Unit *
IO_COMMAND   EQU 28          ; UWORD
IO_FLAGS     EQU 30          ; UBYTE
IO_ERROR     EQU 31          ; BYTE
IO_SIZE      EQU 32
IOSTD_ACTUAL EQU 32          ; struct IOStdReq
IOSTD_LENGTH EQU 36
IOSTD_DATA   EQU 40
IOSTD_OFFSET EQU 44
TR_TIME      EQU 32          ; struct timeval (in a timerequest)
TV_SECS      EQU 32
TV_MICRO     EQU 36
TR_SIZE      EQU 40
TR_ADDREQUEST EQU 9          ; timer.device command (= CMD_NONSTD)
TR_GETSYSTIME EQU 10
TR_SETSYSTIME EQU 11
IOERR_OPENFAIL EQU -1
IOF_QUICK    EQU 1           ; io_Flags: quick request (completed in place, no ReplyMsg)
IOERR_NOCMD  EQU -3
IOERR_ABORTED EQU -2
TD_BEGINIO   EQU -30         ; offset of BeginIO in a device's jump table

; struct Resident (exec/resident.i, V34) — ROMTag scanned at boot to build the OS
RTC_MATCHWORD EQU $4AFC        ; RT_MATCHWORD: signature of a ROMTag
RTF_AUTOINIT  EQU $80          ; RT_FLAGS bit 7: RT_INIT -> auto-init table (MakeLibrary)
RTF_COLDSTART EQU $01
NT_DEVICE     EQU 3
NT_RESOURCE   EQU 8
RT_MATCHWORD  EQU 0            ; UWORD
RT_MATCHTAG   EQU 2            ; APTR -> self (validates the match vs a stray $4AFC)
RT_ENDSKIP    EQU 6            ; APTR -> scan resume point (end of the module)
RT_FLAGS      EQU 10           ; UBYTE
RT_VERSION    EQU 11           ; UBYTE
RT_TYPE       EQU 12           ; UBYTE
RT_PRI        EQU 13           ; signed BYTE (descending init order)
RT_NAME       EQU 14           ; APTR
RT_IDSTRING   EQU 18           ; APTR
RT_INIT       EQU 22           ; APTR -> init routine (or table if AUTOINIT)
RT_SIZE       EQU 26
RESSCAN_LO    EQU ROMBASE          ; ROMTag scan range = the whole ROM
RESSCAN_HI    EQU ROMBASE+$40000   ; (256K; the padding/footer contains no valid ROMTag)
RESMAX        EQU 32              ; capacity of the ResModules array (residents + NUL terminator)

; LVOs (negative offsets confirmed by docs/analysis/exec-spec.md + exec-lvo-table.md)
LVO_OPEN     EQU -6
LVO_CLOSE    EQU -12
LVO_EXPUNGE  EQU -18
LVO_INITCODE     EQU -72
LVO_INITSTRUCT   EQU -78
LVO_MAKELIBRARY  EQU -84
LVO_MAKEFUNCTIONS EQU -90
LVO_FINDRESIDENT EQU -96
LVO_INITRESIDENT EQU -102
LVO_DISABLE  EQU -120
LVO_ENABLE   EQU -126
LVO_FORBID   EQU -132
LVO_PERMIT   EQU -138
LVO_SETINTVECTOR EQU -162
LVO_ADDINTSERVER EQU -168
LVO_REMINTSERVER EQU -174
LVO_ALLOCMEM EQU -198
LVO_FREEMEM  EQU -210
LVO_AVAILMEM EQU -216
LVO_INSERT   EQU -234
LVO_ADDHEAD  EQU -240
LVO_ADDTAIL  EQU -246
LVO_REMOVE   EQU -252
LVO_REMHEAD  EQU -258
LVO_REMTAIL  EQU -264
LVO_ENQUEUE  EQU -270
LVO_FINDNAME EQU -276
LVO_ADDTASK    EQU -282
LVO_REMTASK    EQU -288         ; M7j
LVO_FINDTASK   EQU -294
LVO_SETTASKPRI EQU -300
LVO_SETSIGNAL  EQU -306
LVO_WAIT       EQU -318
LVO_SIGNAL     EQU -324
LVO_ALLOCSIGNAL EQU -330
LVO_FREESIGNAL EQU -336
LVO_ADDPORT    EQU -354
LVO_REMPORT    EQU -360
LVO_PUTMSG     EQU -366
LVO_GETMSG     EQU -372
LVO_REPLYMSG   EQU -378
LVO_WAITPORT   EQU -384
LVO_FINDPORT   EQU -390
LVO_TYPEOFMEM EQU -534
LVO_OPENWINDOW   EQU -204         ; intuition.library
LVO_CLOSEWINDOW  EQU -72
LVO_ADDLIBRARY   EQU -396
LVO_REMLIBRARY   EQU -402
LVO_ADDDEVICE    EQU -432
LVO_REMDEVICE    EQU -438
LVO_OPENDEVICE   EQU -444
LVO_CLOSEDEVICE  EQU -450
LVO_DOIO         EQU -456
LVO_SENDIO       EQU -462
LVO_CHECKIO      EQU -468
LVO_WAITIO       EQU -474
LVO_ABORTIO      EQU -480
LVO_COPYMEM      EQU -624
LVO_COPYMEMQUICK EQU -630
LVO_ALERT        EQU -108       ; Alert(alertNum d7)
AN_TIMERCIARSRC  EQU $15058020  ; Alert: timer.device without ciaa.resource (AN_TimerDev|AG_OpenRes|AO_CIARsrc)
LVO_ADDMEMLIST   EQU -618       ; AddMemList(size d0, attributes d1, pri d2, base a0, name a1)
LVO_ADDRESOURCE  EQU -486
LVO_OPENRESOURCE EQU -498
LVO_OLDOPENLIBRARY EQU -408      ; pre-V33 OpenLibrary (without version gate)
LVO_CLOSELIBRARY   EQU -414
LVO_RAWDOFMT       EQU -522     ; RawDoFmt(fmt a0, data a1, putch a2, putchdata a3)
LVO_INITSEMAPHORE    EQU -558
LVO_OBTAINSEMAPHORE  EQU -564
LVO_RELEASESEMAPHORE EQU -570
LVO_ATTEMPTSEMAPHORE EQU -576
LVO_FINDSEMAPHORE    EQU -594
LVO_ADDSEMAPHORE     EQU -600
LVO_REMSEMAPHORE     EQU -606
LVO_OPENLIBRARY    EQU -552      ; OpenLibrary(libName a1, version d0)

; OPENLIB_NO_VERCHECK=1 (RED OpenLibrary): exec_OpenLibrary skips the version gate -> opening with
; too high a version WRONGLY succeeds instead of returning 0. Isolates the version comparison branch.
; Default 0 (tree).
OPENLIB_NO_VERCHECK EQU 0

; cia.resource (M5b) — a6-relative functions (resource base), struct, hardware.
CIA_ADDICRVECTOR EQU -6
CIA_REMICRVECTOR EQU -12
CIA_ABLEICR      EQU -18
CIA_SETICR       EQU -24
CIAR_HWBASE      EQU LIB_SIZE        ; APTR CIA hardware base (after the Library node)
CIAR_ICRMASK     EQU LIB_SIZE+4      ; UBYTE shadow of the enabled ICR mask (+pad)
CIAR_VECTORS     EQU LIB_SIZE+6      ; 5 APTR: struct Interrupt* slots (timerA/B/TOD/ser/flag)
CIAR_SIZE        EQU LIB_SIZE+6+20
CIAA_HW          EQU $BFE001         ; CIA-A base
CIAB_HW          EQU $BFD000         ; CIA-B base
CIA_ICR_OFF      EQU $D00            ; offset of the ICR register (register $D) from the CIA base

                endc
