; src/dos/conhandler.s - serial console handler process (E1). Same shape as dos_handler_df0 (D3b): body of a
; Process (created by proc_create) that loops WaitPort/GetMsg on its pr_MsgPort and serves the DOS packets of a
; CONSOLE instead of an OFS file. It stands in for console.device: in the real Bootstrap (F) THIS handler is
; replaced by a console.device without touching the shell binary (the shell does all its IO via DOS FileHandles).
;
; Actions served:
;   FINDINPUT / FINDOUTPUT (open "CON:")     -> RES1 = non-null key (global console, no per-handle state). A name
;                                               "CON:x/y/w/h/title" additionally opens the console window (con_openwin).
;   WRITE (ARG1=key, ARG2=src, ARG3=len)     -> emits len bytes on serial (TX, bounded TBE poll). RES1 = len.
;   READ  (ARG1=key, ARG2=dest, ARG3=len)    -> reads ONE LINE up to CR, with echo. RES1 = bytes. Input
;                                               sources: the LIVE keyboard ring (F2b, con_ring_get) THEN the serial RBF.
;   END (close)                              -> RES1 = DOSTRUE.
;
; READ blocks CLEANLY (COOP-safe): polls on a timer.device MICROHZ tick (BeginIO TR_ADDREQUEST + Wait, precedent
; task_timer), drains RBF on every wakeup. NO busy-poll (incompatible with COOP); NO level-5 RBF interrupt
; (deferred to F, see M7k). Latency ~1 tick, overrun on bursts (Paula RX = 1 byte) -> slow human typing OK.
; IMPLEMENTATION track ("clean"): dos analysis spec + exec AutoDocs (timer.device/MsgPort) + HRM (serial).
; NO ROM reading.

                include "exec.i"
                include "dospkt.i"

                xdef    con_handler
                xref    ser_lock             ; exec/boot.s (atomic serial output)
                xref    ser_unlock

CON_POLL_US     EQU 20000            ; 20 ms per RX poll tick (input latency ~1 tick)
CON_CMD_READ    EQU 2                ; io_Command CMD_READ (console.device)
CON_CMD_WRITE   EQU 3                ; io_Command CMD_WRITE
CON_IODATA      EQU 40               ; IOStdReq io_Data (local: conhandler does not include disk.i)
CON_IOLEN       EQU 36               ; IOStdReq io_Length
CON_IOACT       EQU 32               ; IOStdReq io_Actual

; state block (AllocMem at startup, pointer published in CON_STATE)
CS_TBASE        EQU 0                ; APTR base timer.device
CS_RPORT        EQU 4                ; APTR reply MsgPort (timer tick)
CS_TREQ         EQU 8                ; APTR reused timerequest
CS_SIGMASK      EQU 12               ; LONG signal mask of the reply port
CS_DEST         EQU 16               ; APTR current READ destination
CS_MAX          EQU 20               ; LONG max READ size
CS_CNT          EQU 24               ; LONG bytes accumulated by READ
; SHELL_ON_SCREEN (integration F, item 2): the handler ALSO renders to the screen via console.device + reads the
; keyboard via console.device (fed by the feeder). Fields always present (negligible cost if the flag is off).
CS_CONBASE      EQU 28               ; APTR base console.device
CS_ECHO         EQU 32               ; BYTE 1-byte echo buffer (screen CMD_WRITE)
CS_CONIO        EQU 36               ; IOStdReq (48) for console.device BeginIO
; console window (opening of a name "CON:x/y/w/h/title", e.g. the initial CLI "AmigaSlopDOS"): output and echo
; rendered in the window by console.device (the serial mirror stays); closed on the last END of a named stream.
CS_WIN          EQU 84               ; APTR Window | 0
CS_OPENS        EQU 88               ; LONG named streams open
CS_NOKBD        EQU 92               ; BYTE window closed (endcli): READ no longer reads the keyboard, only serial
CS_WECHO        EQU 93               ; BYTE 1-byte echo buffer (window)
CS_WIO          EQU 96               ; IOStdReq (48) console.device on the window
CS_NW           EQU 144              ; NewWindow (48)
CS_TITLE        EQU 192              ; title (C string, CS_TITLEMAX bytes)
CS_TITLEMAX     EQU 32
CS_SIZE         EQU CS_TITLE+CS_TITLEMAX
; NewWindow (intuition/intuition.h) and console window constants
NW_LEFTEDGE     EQU 0
NW_DETAILPEN    EQU 8
NW_FLAGS        EQU 14
NW_TITLE        EQU 26
NW_MINWIDTH     EQU 38
NW_TYPE         EQU 46
CON_WINFLAGS    EQU $00021007        ; SIZING, DRAG, DEPTH, ACTIVATE, NOCAREREFRESH (standard CON: window)
CON_WBSCREEN    EQU 1                ; nw_Type WBENCHSCREEN

; con_handler: process body. GPRs at zero on entry (AddTask frame) -> reload SysBase.
con_handler:
                move.l  ($4).w,a6
                clr.l   CON_STATE            ; default: no state -> READ returns EOF (WRITE works anyway)
                ; --- set up timer.device MICROHZ (once): base + signal + reply port + timerequest ---
                lea     EB_DEVICELIST(a6),a0
                lea     con_timername(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .setup_done          ; no timer -> WRITE works, READ -> EOF
                move.l  d0,d2                ; d2 = timer.device base
                move.l  #CS_SIZE,d0          ; state block
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .setup_done
                move.l  d0,a4                ; a4 = state (temp; reassigned in the loop)
                move.l  d2,CS_TBASE(a4)
                moveq   #-1,d0               ; AllocSignal -> reply port bit
                jsr     LVO_ALLOCSIGNAL(a6)
                move.l  d0,d3                ; d3 = bit number
                moveq   #1,d1
                lsl.l   d0,d1                ; d1 = 1<<bit
                move.l  d1,CS_SIGMASK(a4)
                move.l  #MP_SIZE,d0          ; reply port
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .setup_done          ; state left allocated (boot time, harmless) -> CON_STATE stays 0
                move.l  d0,a3                ; a3 = reply port (temp)
                move.l  d0,CS_RPORT(a4)
                move.b  #NT_MSGPORT,LN_TYPE(a3)
                move.b  #PA_SIGNAL,MP_FLAGS(a3)
                move.b  d3,MP_SIGBIT(a3)
                move.l  EB_THISTASK(a6),MP_SIGTASK(a3)
                lea     MP_MSGLIST(a3),a1    ; NEWLIST(mp_MsgList) inline
                move.l  a1,d0
                addq.l  #4,d0
                move.l  d0,(a1)
                clr.l   4(a1)
                move.l  a1,8(a1)
                move.l  #TR_SIZE,d0          ; timerequest
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .setup_done
                move.l  d0,a1
                move.l  d0,CS_TREQ(a4)
                move.l  CS_RPORT(a4),MN_REPLYPORT(a1)
                move.l  CS_TBASE(a4),IO_DEVICE(a1)
                move.l  #UNIT_MICROHZ,IO_UNIT(a1)
                ifne    SHELL_ON_SCREEN
                lea     EB_DEVICELIST(a6),a0 ; item 2: console.device base (screen output + keyboard input via feeder)
                lea     con_consolename(pc),a1
                jsr     LVO_FINDNAME(a6)
                move.l  d0,CS_CONBASE(a4)    ; 0 if absent -> screen WRITE/READ degrade cleanly
                endc
                move.l  a4,CON_STATE         ; publish the state -> READ enabled
.setup_done:
                move.l  EB_THISTASK(a6),a2
                lea     PR_MSGPORT(a2),a2    ; a2 = its own pr_MsgPort
.hl:
                move.l  a2,a0
                jsr     LVO_WAITPORT(a6)
                move.l  a2,a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .hl
                move.l  d0,a3                ; a3 = Message
                move.l  LN_NAME(a3),a4       ; a4 = DosPacket
                clr.l   DP_RES2(a4)
                move.l  DP_TYPE(a4),d0
                cmp.l   #ACTION_FINDINPUT,d0
                beq     .open
                cmp.l   #ACTION_FINDOUTPUT,d0
                beq     .open
                cmp.l   #ACTION_WRITE,d0
                beq     .write
                cmp.l   #ACTION_READ,d0
                beq     .read
                cmp.l   #ACTION_END,d0
                beq     .end
                cmp.l   #ACTION_DISK_INFO,d0
                beq     .info
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  #ERROR_ACTION_NOT_KNOWN,DP_RES2(a4)
                bra     .reply

.open:
                move.l  #1,DP_RES1(a4)       ; non-null key (global console)
                move.l  CON_STATE,d0
                beq     .reply
                move.l  d0,a0
                move.l  DP_ARG3(a4),d0       ; name (BSTR): only named opens are counted
                beq     .reply
                addq.l  #1,CS_OPENS(a0)
                tst.l   CS_WIN(a0)
                bne     .reply
                bsr     con_openwin          ; "CON:x/y/w/h/title" -> window (otherwise nothing)
                bra     .reply
.end:
                move.l  #DOSTRUE,DP_RES1(a4)
                move.l  CON_STATE,d0
                beq     .reply
                move.l  d0,a0
                tst.l   CS_OPENS(a0)
                beq     .reply
                subq.l  #1,CS_OPENS(a0)
                bne     .reply
                bsr     con_closewin         ; last named stream closed (endcli of the initial CLI)
                bra     .reply

.write:
                ifne    E1_NO_WRITE
                move.l  DP_ARG3(a4),DP_RES1(a4)  ; RED E1_NO_WRITE: pretends to write, emits nothing
                bra     .reply
                endc
                move.l  DP_ARG3(a4),DP_RES1(a4)  ; RES1 = len
                move.l  DP_ARG2(a4),a0
                move.l  DP_ARG3(a4),d0
                bsr     con_win_write        ; console window (if open)
                ifne    SHELL_ON_SCREEN
                ; item 2: renders the WHOLE buffer on screen via console.device CMD_WRITE (the serial mirror follows)
                move.l  CON_STATE,a0
                move.l  a0,d0
                beq.s   .wr_mirror
                move.l  CS_CONBASE(a0),d0
                beq.s   .wr_mirror
                lea     CS_CONIO(a0),a1
                move.l  d0,IO_DEVICE(a1)
                move.w  #CON_CMD_WRITE,IO_COMMAND(a1)
                move.l  DP_ARG2(a4),CON_IODATA(a1)
                move.l  DP_ARG3(a4),CON_IOLEN(a1)
                move.l  d0,a6                ; a6 = console.device base for BeginIO
                jsr     -30(a6)              ; console BeginIO (screen CMD_WRITE)
                move.l  ($4).w,a6            ; restore a6 = SysBase
.wr_mirror:
                endc
                move.l  DP_ARG2(a4),a5       ; src (a5 survives con_putc)
                move.l  DP_ARG3(a4),d3       ; len (d3 survives con_putc)
                tst.l   d3
                beq     .reply
                jsr     ser_lock             ; whole buffer atomic on serial (no marker interleaving)
.wr_lp:
                move.b  (a5)+,d0
                bsr     con_putc
                subq.l  #1,d3
                bne.s   .wr_lp
                jsr     ser_unlock
                bra     .reply

.read:
                move.l  CON_STATE,d0
                beq     .rd_eof              ; no timer -> EOF
                move.l  d0,a0
                move.l  DP_ARG2(a4),CS_DEST(a0)
                move.l  DP_ARG3(a4),CS_MAX(a0)
                clr.l   CS_CNT(a0)
.rd_tick:
                bsr     con_poll_wait        ; ~20 ms (preserves a2/a3/a4/a6)
.rd_drain:
                ifne    SHELL_ON_SCREEN
                bsr     con_scr_read         ; item 2: source = console.device CMD_READ (keyboard via feeder)
                beq.s   .rd_tick             ; nothing this tick -> wait for the next one
                else
                move.l  CON_STATE,a0
                tst.b   CS_NOKBD(a0)
                bne.s   .rd_ser              ; window closed: the keyboard belongs to the screen's windows
                bsr     con_kbdmine          ; another window is active: its keys are not for us
                beq.s   .rd_ser              ; (console.device routes them to it; the ring is emptied)
                bsr     con_ring_get         ; F2b: LIVE keyboard first (SPSC ring, consumer)
                bne.s   .rd_got              ; a key available -> d0.b = ASCII
.rd_ser:
                move.w  SERDATR,d0
                btst    #14,d0               ; otherwise serial RBF: byte received?
                beq.s   .rd_tick             ; nothing from either this tick -> wait for the next one
                and.w   #$00FF,d0            ; byte received (serial)
                move.w  #INTF_RBF,INTREQ     ; acknowledge RBF
                endc
.rd_got:
                move.l  d0,d4                ; d4 = byte (survives con_putc)
                bsr     con_putc             ; serial echo (mirror)
                move.b  d4,d0
                bsr     con_win_emit         ; window echo
                ifne    SHELL_ON_SCREEN
                move.b  d4,d0
                bsr     con_scr_emit         ; screen echo
                endc
                cmp.b   #13,d4
                bne.s   .rd_store
                moveq   #10,d0               ; CR -> also LF for display
                bsr     con_putc
                moveq   #10,d0
                bsr     con_win_emit
                ifne    SHELL_ON_SCREEN
                moveq   #10,d0
                bsr     con_scr_emit         ; CR -> LF on screen too
                endc
.rd_store:
                move.l  CON_STATE,a0
                move.l  CS_CNT(a0),d1
                cmp.l   CS_MAX(a0),d1
                bge.s   .rd_done             ; buffer full
                move.l  CS_DEST(a0),a1
                move.b  d4,(0,a1,d1.l)       ; dest[cnt] = byte
                addq.l  #1,CS_CNT(a0)
                cmp.b   #13,d4               ; end of line?
                beq.s   .rd_done
                bra.s   .rd_drain            ; drain other bytes available this tick
.rd_done:
                move.l  CON_STATE,a0
                move.l  CS_CNT(a0),DP_RES1(a4)
                bra     .reply
.rd_eof:
                clr.l   DP_RES1(a4)
                bra     .reply
; DISK_INFO (ARG1 = BPTR InfoData): console disk type "CON\0", the window as volume node, and in id_InUse the
; console IOStdReq of the window (SetMap sends CD_SETKEYMAP to its unit), 0 without a window.
.info:
                move.l  #DOSTRUE,DP_RES1(a4)
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .reply
                move.l  d0,a0
                move.l  #$434F4E00,24(a0)    ; id_DiskType
                clr.l   28(a0)               ; id_VolumeNode
                clr.l   32(a0)               ; id_InUse
                move.l  CON_STATE,d0
                beq.s   .reply
                move.l  d0,a1
                move.l  CS_WIN(a1),d0
                beq.s   .reply
                move.l  d0,28(a0)
                lea     CS_WIO(a1),a1
                move.l  a1,32(a0)
; reply through dp_Port (returnpkt): BCPL-style senders such as SetMap do not set mn_ReplyPort
.reply:
                move.l  DP_PORT(a4),a0
                move.l  a2,DP_PORT(a4)
                move.l  a3,a1
                jsr     LVO_PUTMSG(a6)
                bra     .hl

; con_putc: emits d0.b on serial (bounded TBE poll). Clobbers d0/d1/d2; preserves the rest.
con_putc:
                and.w   #$00FF,d0
                or.w    #$0100,d0
                move.w  #$2000,d2
.cp_w:
                move.w  SERDATR,d1
                btst    #13,d1               ; TBE (TX buffer empty)?
                bne.s   .cp_tx
                dbra    d2,.cp_w
                rts                          ; timeout -> give up (bounded)
.cp_tx:
                move.w  d0,SERDAT
                rts

; con_poll_wait: one wait of ~CON_POLL_US via timer.device MICROHZ. Preserves the whole loop context.
con_poll_wait:
                movem.l d0-d2/a0-a4,-(sp)
                move.l  CON_STATE,a2
                move.l  CS_TREQ(a2),a1
                clr.l   TV_SECS(a1)
                move.l  #CON_POLL_US,TV_MICRO(a1)
                move.w  #TR_ADDREQUEST,IO_COMMAND(a1)
                move.l  CS_TBASE(a2),a0      ; device base
                move.l  a6,-(sp)
                move.l  a0,a6
                jsr     TD_BEGINIO(a6)       ; BeginIO(a6=base, a1=request)
                move.l  (sp)+,a6
                move.l  CS_SIGMASK(a2),d0
                jsr     LVO_WAIT(a6)         ; BLOCKS ~20 ms (yield -> COOP-safe)
                move.l  CS_RPORT(a2),a0
                jsr     LVO_GETMSG(a6)       ; remove the reply (request reused on the next tick)
                movem.l (sp)+,d0-d2/a0-a4
                rts

; con_kbdmine(a0 = state) -> Z = 0 if the keyboard is for this console: no window, no active window, or
; its window is intuition's active window. Otherwise the keyboard ring is emptied (Z = 1). Preserves d2-d7/a2-a6.
con_kbdmine:
                movem.l a2/a6,-(sp)
                move.l  CS_WIN(a0),d1
                beq.s   .km_yes
                move.l  ($4).w,a6
                lea     EB_LIBLIST(a6),a0
                lea     con_intname(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq.s   .km_yes
                move.l  d0,a2
                move.l  52(a2),d0            ; ib_ActiveWindow
                beq.s   .km_yes
                move.l  CON_STATE,a0
                cmp.l   CS_WIN(a0),d0
                beq.s   .km_yes
.km_drain:
                bsr     con_ring_get
                bne.s   .km_drain
                moveq   #0,d0                ; Z = 1
                bra.s   .km_ret
.km_yes:
                moveq   #1,d0                ; Z = 0
.km_ret:
                movem.l (sp)+,a2/a6
                rts

; con_ring_get: F2b - removes one byte from the keyboard ring (SPSC consumer). -> d0.b = ASCII (clean), Z=0
; (obtained) | Z=1 (ring empty). Reads KBD_HEAD/KBD_TAIL, advances KBD_HEAD. Lock-free (no masking: the
; producer kbd_interrupt writes the data BEFORE advancing KBD_TAIL). Clobbers d0/d1/a0 (reassigned by the READ loop).
con_ring_get:
                move.w  KBD_HEAD,d1
                cmp.w   KBD_TAIL,d1
                beq.s   .crg_empty           ; HEAD==TAIL -> empty
                lea     KBD_RING,a0
                moveq   #0,d0
                move.b  0(a0,d1.w),d0        ; d0 = byte read
                addq.w  #1,d1
                and.w   #KBD_RMASK,d1
                move.w  d1,KBD_HEAD          ; advance HEAD (publishes the consumption)
                moveq   #1,d1
                tst.b   d1                   ; Z=0 -> byte obtained
                rts
.crg_empty:
                moveq   #0,d1
                tst.b   d1                   ; Z=1 -> ring empty
                rts

                ifne    SHELL_ON_SCREEN
; con_scr_read (item 2): reads 1 byte via console.device CMD_READ (keyboard cooked by its handler, via the feeder).
; -> d0.b = byte, Z=0 (obtained) | Z=1 (nothing this tick). a6=SysBase. Preserves d4/a2-a4 (console BeginIO saves them).
con_scr_read:
                move.l  CON_STATE,a1
                move.l  a1,d0
                beq.s   .sr_empty
                move.l  CS_CONBASE(a1),d0
                beq.s   .sr_empty
                lea     CS_CONIO(a1),a0
                move.l  d0,IO_DEVICE(a0)
                move.w  #CON_CMD_READ,IO_COMMAND(a0)
                move.l  a1,d1
                add.l   #CS_ECHO,d1
                move.l  d1,CON_IODATA(a0)    ; io_Data = &CS_ECHO (1 byte)
                move.l  #1,CON_IOLEN(a0)
                clr.l   CON_IOACT(a0)
                move.l  d0,a6                ; a6 = console.device base
                move.l  a0,a1
                jsr     -30(a6)              ; console BeginIO (CMD_READ)
                move.l  ($4).w,a6            ; restore SysBase
                move.l  CON_STATE,a0
                lea     CS_CONIO(a0),a1
                move.l  CON_IOACT(a1),d0     ; bytes actually read
                beq.s   .sr_empty
                moveq   #0,d0
                move.b  CS_ECHO(a0),d0       ; d0.b = byte read
                moveq   #1,d1
                tst.b   d1                   ; Z=0 -> obtained
                rts
.sr_empty:
                moveq   #0,d1
                tst.b   d1                   ; Z=1 -> nothing
                rts

; con_scr_emit (item 2): writes d0.b on screen via console.device CMD_WRITE (1 byte). a6=SysBase. Preserves d4/a2-a4.
con_scr_emit:
                move.l  CON_STATE,a1
                move.l  a1,d1
                beq.s   .se_ret
                move.l  CS_CONBASE(a1),d1
                beq.s   .se_ret
                move.b  d0,CS_ECHO(a1)
                lea     CS_CONIO(a1),a0
                move.l  d1,IO_DEVICE(a0)
                move.w  #CON_CMD_WRITE,IO_COMMAND(a0)
                move.l  a1,d0
                add.l   #CS_ECHO,d0
                move.l  d0,CON_IODATA(a0)
                move.l  #1,CON_IOLEN(a0)
                move.l  d1,a6                ; a6 = console.device base
                move.l  a0,a1
                jsr     -30(a6)              ; console BeginIO (CMD_WRITE 1 byte)
                move.l  ($4).w,a6
.se_ret:
                rts

con_consolename:
                dc.b    "console.device",0
                EVEN
                endc

; con_openwin(a0 = state, d0 = BPTR of the BSTR name): name "CON:x/y/w/h/title" -> NewWindow (screen pens, flags
; of a CON: window, Workbench screen) + OpenWindow + console.device on the window (CS_WIO). Other name or failure:
; nothing (output stays on serial). a6 = SysBase. Preserves d2-d7/a2-a6.
con_openwin:
                movem.l d2-d4/a2-a3/a5,-(sp)
                move.l  a0,a5                ; a5 = state
                lsl.l   #2,d0
                move.l  d0,a2                ; a2 = BSTR
                moveq   #0,d3
                move.b  (a2)+,d3             ; d3 = remaining length
                cmp.w   #4,d3
                blo     .ow_ret
                move.b  (a2)+,d0             ; "CON:" prefix (case-insensitive)
                and.b   #$DF,d0
                cmp.b   #'C',d0
                bne     .ow_ret
                move.b  (a2)+,d0
                and.b   #$DF,d0
                cmp.b   #'O',d0
                bne     .ow_ret
                move.b  (a2)+,d0
                and.b   #$DF,d0
                cmp.b   #'N',d0
                bne     .ow_ret
                cmp.b   #':',(a2)+
                bne     .ow_ret
                subq.w  #4,d3
                lea     CS_NW(a5),a3         ; 4 decimal numbers separated by '/' -> Left, Top, Width, Height
                moveq   #3,d4
.ow_num:
                moveq   #0,d1
.ow_dig:
                tst.w   d3
                beq     .ow_ret              ; incomplete specification
                subq.w  #1,d3
                moveq   #0,d0
                move.b  (a2)+,d0
                cmp.b   #'/',d0
                beq.s   .ow_sep
                sub.b   #'0',d0
                cmp.b   #9,d0
                bhi     .ow_ret
                mulu    #10,d1
                add.w   d0,d1
                bra.s   .ow_dig
.ow_sep:
                move.w  d1,(a3)+
                dbra    d4,.ow_num
                lea     CS_TITLE(a5),a0      ; title = the rest
                moveq   #CS_TITLEMAX-2,d0
.ow_tcpy:
                tst.w   d3
                beq.s   .ow_tend
                subq.w  #1,d3
                move.b  (a2)+,(a0)+
                dbra    d0,.ow_tcpy
.ow_tend:
                clr.b   (a0)
                lea     CS_NW(a5),a0
                move.w  #$FFFF,NW_DETAILPEN(a0)  ; DetailPen = BlockPen = -1: those of the screen
                move.l  #CON_WINFLAGS,NW_FLAGS(a0)
                lea     CS_TITLE(a5),a1
                move.l  a1,NW_TITLE(a0)
                move.l  #$00780032,NW_MINWIDTH(a0)   ; MinWidth 120, MinHeight 50
                move.l  #$FFFFFFFF,NW_MINWIDTH+4(a0) ; MaxWidth/MaxHeight unlimited
                move.w  #CON_WBSCREEN,NW_TYPE(a0)
                lea     con_intname(pc),a1
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq.s   .ow_ret
                move.l  d0,a3                ; a3 = IntuitionBase
                lea     CS_NW(a5),a0
                move.l  a6,-(sp)
                move.l  a3,a6
                jsr     LVO_OPENWINDOW(a6)
                move.l  (sp)+,a6
                tst.l   d0
                beq.s   .ow_close
                move.l  d0,d2                ; d2 = window
                lea     CS_WIO(a5),a1
                move.l  d2,CON_IODATA(a1)
                lea     con_cdevname(pc),a0
                moveq   #0,d0
                moveq   #0,d1
                jsr     LVO_OPENDEVICE(a6)
                tst.l   d0
                bne.s   .ow_nodev
                move.l  d2,CS_WIN(a5)
                bra.s   .ow_close            ; IntuitionBase stays open through the window (CloseWindow)
.ow_nodev:
                move.l  d2,a0
                move.l  a6,-(sp)
                move.l  a3,a6
                jsr     LVO_CLOSEWINDOW(a6)
                move.l  (sp)+,a6
.ow_close:
.ow_ret:
                movem.l (sp)+,d2-d4/a2-a3/a5
                rts

; con_closewin(a0 = state): closes console.device and the window; READ then stops reading the keyboard.
; a6 = SysBase. Preserves d2-d7/a2-a6.
con_closewin:
                movem.l a2-a3,-(sp)
                move.l  a0,a2
                move.l  CS_WIN(a2),d0
                beq.s   .cw_ret
                lea     CS_WIO(a2),a1
                jsr     LVO_CLOSEDEVICE(a6)
                lea     con_intname(pc),a1
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq.s   .cw_ret
                move.l  d0,a3
                move.l  CS_WIN(a2),a0
                clr.l   CS_WIN(a2)
                st      CS_NOKBD(a2)
                move.l  a6,-(sp)
                move.l  a3,a6
                jsr     LVO_CLOSEWINDOW(a6)
                move.l  (sp)+,a6
                move.l  a3,a1
                jsr     LVO_CLOSELIBRARY(a6)
.cw_ret:
                movem.l (sp)+,a2-a3
                rts

; con_win_write(a0 = data, d0 = length): CMD_WRITE on the console window (IOF_QUICK: complete on return).
; a6 = SysBase. Preserves d2-d7/a2-a6.
con_win_write:
                move.l  CON_STATE,d1
                beq.s   .ww_ret
                move.l  d1,a1
                tst.l   CS_WIN(a1)
                beq.s   .ww_ret
                lea     CS_WIO(a1),a1
                move.w  #CON_CMD_WRITE,IO_COMMAND(a1)
                move.b  #IOF_QUICK,IO_FLAGS(a1)
                move.l  a0,CON_IODATA(a1)
                move.l  d0,CON_IOLEN(a1)
                move.l  a6,-(sp)
                move.l  IO_DEVICE(a1),a6
                jsr     -30(a6)              ; BeginIO
                move.l  (sp)+,a6
.ww_ret:
                rts

; con_win_emit(d0.b): one byte on the console window. Preserves d2-d7/a2-a6.
con_win_emit:
                move.l  CON_STATE,d1
                beq.s   .we_ret
                move.l  d1,a1
                move.b  d0,CS_WECHO(a1)
                lea     CS_WECHO(a1),a0
                moveq   #1,d0
                bra.s   con_win_write
.we_ret:
                rts

con_intname:
                dc.b    "intuition.library",0
con_cdevname:
                dc.b    "console.device",0
con_timername:
                dc.b    "timer.device",0
                EVEN
