; tests/imenu_probe.s - black-box probe of the intuition 1.3 input engine and menus
; (TEST ASSET, NOT ROM code; ANALYSIS track, docs/analysis/intuition-input-menus-v34.md).
; AUTHORED code: uses only the public ABI (exec/intuition/graphics .fd, NDK 1.3 structures,
; input.device IND_WRITEEVENT); private reads displayed for information only:
; IntuitionBase +$50..+$56 (pointer bounds), +$378, +$544, +$546.
;
; Assembled as a raw binary (vasm -Fbin -m68000), placed at offset 12 of an ADF by tests/imenu_probe.sh.
; Stage 1 (in the bootblock): reads the first 32 KB of the floppy back into chip RAM and jumps there.
; Stage 2: opens two windows on the Workbench screen (A with a menu, B without), then injects a sequence
; of events through input.device IND_WRITEEVENT (absolute IECLASS_POINTERPOS positions, buttons,
; keys) and logs every IntuiMessage received on the serial port:
;   M <win> <Class> <Code> <Qualifier> <IAddress> <MouseX> <MouseY> <Seconds> <Micros>
;   (IAddress "=A"/"=B" = the window; Seconds/Micros = injected timestamp: step/rank)
;   P <code> <flags>: NextSelect chain of a MENUPICK (code and Flags of each item)
; "@S x": the harness takes screenshot x; "@T n": start of step n; "IDLE": end.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
LOADSZ   EQU 32768

; variables (relative to A5)
v_ib     EQU 0
v_gfx    EQU 4
v_wa     EQU 8
v_wb     EQU 12
v_scr    EQU 16
v_cancel EQU 20
v_hold   EQU 22
v_step   EQU 24
v_rank   EQU 26
v_spin   EQU 28
v_port   EQU 32          ; MsgPort (34 bytes)
v_io     EQU 72          ; IOStdReq (48 bytes)
v_ev     EQU 124         ; InputEvent (22 bytes)
v_lptr   EQU 148         ; write pointer of the RAM log
v_size   EQU 160

start:
; ---------------------------------------------------------------- stage 1 (bootblock)
        movea.l 4.w,a6
        movea.l a1,a2
        move.l  #LOADSZ,d0
        move.l  #$10003,d1
        jsr     -198(a6)            ; AllocMem
        tst.l   d0
        beq.s   *
        movea.l d0,a3
        movea.l a2,a1
        move.w  #2,28(a1)           ; CMD_READ
        move.l  a3,40(a1)
        move.l  #LOADSZ,36(a1)
        clr.l   44(a1)
        jsr     -456(a6)            ; DoIO
        movea.l a2,a1
        move.w  #9,28(a1)           ; TD_MOTOR off
        clr.l   36(a1)
        jsr     -456(a6)
        lea     12(a3),a0
        jmp     stage2-start(a0)

; ---------------------------------------------------------------- stage 2
stage2:
        lea     start(pc),a4
        lea     reloc(pc),a0
.rl:    move.l  (a0)+,d0
        bmi.s   .rd
        move.l  a4,d1
        add.l   d1,0(a4,d0.l)
        bra.s   .rl
.rd:    lea     vars(pc),a5
        lea     logbuf(pc),a0
        move.l  a0,v_lptr(a5)
        movea.l 4.w,a6
        lea     m_hello(pc),a0
        bsr     puts
        suba.l  a1,a1
        jsr     -294(a6)            ; FindTask(0): priority and Forbid/Disable of the context
        movea.l d0,a0
        moveq   #0,d0
        move.b  9(a0),d0
        bsr     hex2s
        move.b  $127(a6),d0         ; TDNestCnt
        bsr     hex2s
        move.b  $126(a6),d0         ; IDNestCnt
        bsr     hex2s
        bsr     nl
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,v_ib(a5)
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,v_gfx(a5)
        ; windows
        movea.l v_ib(a5),a6
        lea     nwa(pc),a0
        jsr     -204(a6)            ; OpenWindow
        move.l  d0,v_wa(a5)
        beq     failed
        lea     nwb(pc),a0
        jsr     -204(a6)
        move.l  d0,v_wb(a5)
        beq     failed
        movea.l v_wa(a5),a0
        move.l  46(a0),v_scr(a5)    ; WScreen
        lea     menu0(pc),a1
        jsr     -264(a6)            ; SetMenuStrip
        bsr     dumpgeo
        ; port + input.device
        movea.l 4.w,a6
        moveq   #-1,d0
        jsr     -330(a6)            ; AllocSignal
        lea     v_port(a5),a2
        move.b  #4,8(a2)            ; NT_MSGPORT
        clr.b   14(a2)              ; PA_SIGNAL
        move.b  d0,15(a2)
        suba.l  a1,a1
        jsr     -294(a6)            ; FindTask(0)
        move.l  d0,16(a2)
        lea     20(a2),a0           ; NewList
        move.l  a0,8(a0)
        addq.l  #4,a0
        clr.l   (a0)
        move.l  a0,-4(a0)
        lea     v_io(a5),a1
        move.b  #5,8(a1)
        move.l  a2,14(a1)
        move.w  #48,18(a1)
        lea     inpname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        jsr     -444(a6)            ; OpenDevice
        tst.l   d0
        bne     failed
        lea     m_ready(pc),a0
        bsr     puts
        bsr     flush
        moveq   #50,d7
        bsr     pumpn
        bsr     runscript
        lea     m_idle(pc),a0
        bsr     puts
        bsr     flush
.idle:  moveq   #50,d7
        bsr     pumpn
        bra.s   .idle
failed:   lea     m_fail(pc),a0
        bsr     puts
        bsr     flush
        bra.s   *

; ---------------------------------------------------------------- geometry
dumpgeo:
        lea     m_scr(pc),a0
        bsr     puts
        movea.l v_scr(a5),a2
        move.w  12(a2),d0           ; Width
        bsr     hex4s
        move.w  14(a2),d0           ; Height
        bsr     hex4s
        moveq   #$1E,d2             ; BarHeight..WBorBottom
.sb:    moveq   #0,d0
        move.b  0(a2,d2.w),d0
        bsr     hex2s
        addq.w  #1,d2
        cmp.w   #$27,d2
        bne.s   .sb
        movea.l 40(a2),a0           ; Font (TextAttr)
        move.w  4(a0),d0
        bsr     hex4s
        move.w  $4C(a2),d0          ; ViewPort.Modes
        bsr     hex4s
        bsr     nl
        lea     m_ibl(pc),a0
        bsr     puts
        movea.l v_ib(a5),a2
        move.w  $50(a2),d0
        bsr     hex4s
        move.w  $52(a2),d0
        bsr     hex4s
        move.w  $54(a2),d0
        bsr     hex4s
        move.w  $56(a2),d0
        bsr     hex4s
        move.w  $378(a2),d0
        bsr     hex4s
        move.w  $544(a2),d0
        bsr     hex4s
        move.w  $546(a2),d0
        bsr     hex4s
        bsr     nl
        lea     m_win(pc),a0
        bsr     puts
        movea.l v_wa(a5),a2
        moveq   #$36,d2
.wb:    moveq   #0,d0
        move.b  0(a2,d2.w),d0
        bsr     hex2s
        addq.w  #1,d2
        cmp.w   #$3A,d2
        bne.s   .wb
        bsr     nl
        lea     menu0(pc),a2
.mn:    lea     m_menu(pc),a0
        bsr     puts
        move.w  22(a2),d0
        bsr     hex4s
        move.w  24(a2),d0
        bsr     hex4s
        move.w  26(a2),d0
        bsr     hex4s
        move.w  28(a2),d0
        bsr     hex4s
        bsr     nl
        move.l  (a2),d0
        beq.s   .me
        movea.l d0,a2
        bra.s   .mn
.me:    rts

; ---------------------------------------------------------------- script interpreter
; words: op, arguments
runscript:
        lea     script(pc),a3
.next:  move.w  (a3)+,d0
        beq     .end
        cmp.w   #1,d0
        beq     .opP
        cmp.w   #2,d0
        beq     .opB
        cmp.w   #3,d0
        beq     .opK
        cmp.w   #4,d0
        beq     .opS
        cmp.w   #5,d0
        beq     .opT
        cmp.w   #6,d0
        beq     .opC
        cmp.w   #7,d0
        beq     .opR
        cmp.w   #8,d0
        beq     .opM
        cmp.w   #9,d0
        beq     .opV
        cmp.w   #10,d0
        beq     .opH
        cmp.w   #11,d0
        beq     .opU
        cmp.w   #12,d0
        beq     .opPH
        cmp.w   #13,d0
        beq     .opPI
        cmp.w   #14,d0
        beq     .opPS
        cmp.w   #15,d0
        beq     .opD
        bra     failed
.end:   rts
.opP:   move.w  (a3)+,d1
        move.w  (a3)+,d2
        add.w   d2,d2               ; non-interlaced screen: IB Y = 2 x screen Y
        bsr     ptrpos
        bra     .next
.opB:   bsr     clrev
        move.b  #2,4(a0)            ; IECLASS_RAWMOUSE
        move.w  (a3)+,6(a0)
        move.w  #$8000,8(a0)
        bsr     inject
        bra     .next
.opK:   bsr     clrev
        move.b  #1,4(a0)            ; IECLASS_RAWKEY
        move.w  (a3)+,6(a0)
        move.w  (a3)+,8(a0)
        bsr     inject
        bra     .next
.opS:   lea     m_shot(pc),a0
        bsr     puts
        move.w  (a3)+,d0
        bsr     putc
        bsr     nl
        bsr     flush
        move.w  #150,d7
        bsr     pumpn
        bra     .next
.opT:   lea     m_step(pc),a0
        bsr     puts
        move.w  (a3)+,d0
        move.w  d0,v_step(a5)
        clr.w   v_rank(a5)
        bsr     hex4
        bsr     nl
        bsr     flush
        bra     .next
.opC:   move.w  #1,v_cancel(a5)
        bra     .next
.opR:   movea.l v_ib(a5),a6
        movea.l v_wa(a5),a0
        move.w  (a3)+,d0
        ext.l   d0
        jsr     -234(a6)            ; ReportMouse(bool D0, window A0)
        movea.l 4.w,a6
        bra     .next
.opM:   movea.l v_wa(a5),a0
        tst.w   (a3)+
        beq.s   .m0
        or.l    #$10000,24(a0)      ; RMBTRAP
        bra     .next
.m0:    and.l   #$FFFEFFFF,24(a0)
        bra     .next
.opV:   movea.l v_ib(a5),a6
        movea.l v_wa(a5),a0
        move.l  #$C37FE,d0
        tst.w   (a3)+
        beq.s   .v0
        or.l    #$200000,d0         ; VANILLAKEY
.v0:    jsr     -150(a6)            ; ModifyIDCMP
        movea.l 4.w,a6
        bra     .next
.opD:   movem.w (a3)+,d2-d5         ; y0, y1, x0, x1: colours of the screen pixels (planes 0 and 1)
        movea.l v_scr(a5),a2
        lea     $B8(a2),a2          ; Screen.BitMap
.dy:    lea     m_row(pc),a0
        bsr     puts
        move.w  d2,d0
        bsr     hex4s
        move.w  d4,d6
.dx:    move.w  (a2),d0             ; BytesPerRow
        mulu    d2,d0
        move.w  d6,d1
        lsr.w   #3,d1
        add.w   d1,d0               ; d0 = byte offset
        move.w  d6,d1
        not.w   d1
        and.w   #7,d1               ; bit
        moveq   #0,d7
        movea.l 8(a2),a0            ; plane 0
        btst    d1,0(a0,d0.l)
        beq.s   .p1
        moveq   #1,d7
.p1:    movea.l 12(a2),a0           ; plane 1
        btst    d1,0(a0,d0.l)
        beq.s   .p2
        addq.w  #2,d7
.p2:    move.w  d7,d0
        add.b   #'0',d0
        bsr     putc
        addq.w  #1,d6
        cmp.w   d5,d6
        blt.s   .dx
        bsr     nl
        addq.w  #1,d2
        cmp.w   d3,d2
        ble.s   .dy
        bsr     flush
        bra     .next
.opH:   move.w  #1,v_hold(a5)
        bra     .next
.opU:   clr.w   v_hold(a5)
        moveq   #10,d7
        bsr     pumpn
        bra     .next
.opPH:  move.w  (a3)+,d0            ; centre of the title of menu n
        bsr     menun
        movea.l v_scr(a5),a1
        move.w  4(a0),d1            ; LeftEdge
        moveq   #0,d0
        move.b  $1F(a1),d0          ; BarVBorder
        add.w   d0,d1
        move.w  8(a0),d0
        lsr.w   #1,d0
        add.w   d0,d1
        moveq   #0,d2
        move.b  $1E(a1),d2          ; BarHeight
        bra     .pyx
.opPI:  move.w  (a3)+,d0            ; centre of item i of menu n
        bsr     menun
        move.w  4(a0),d1
        movea.l 18(a0),a0           ; FirstItem
        move.w  (a3)+,d0
        bsr     nthn
        bsr     itemxy
        bra     .pyx2
.opPS:  move.w  (a3)+,d0            ; centre of sub-item s of item i of menu n
        bsr     menun
        move.w  4(a0),d1
        movea.l 18(a0),a0
        move.w  (a3)+,d0
        bsr     nthn
        add.w   4(a0),d1            ; + item.LeftEdge
        move.w  6(a0),d4            ; item.TopEdge
        movea.l 28(a0),a0           ; SubItem
        move.w  (a3)+,d0
        bsr     nthn
        bsr     itemxy
        add.w   d4,d2
.pyx2:  move.w  d2,d0               ; d2 = screen Y of the centre
        move.w  d0,d2
        add.w   d2,d2
        bsr     ptrpos
        bra     .next
.pyx:   ; d2 = BarHeight: Y = BarHeight/2, then x2 for the IB
        lsr.w   #1,d2
        add.w   d2,d2
        bsr     ptrpos
        bra     .next

; a0 = menu n (d0)
menun:  lea     menu0(pc),a0
nthn:   subq.w  #1,d0
        bmi.s   .r
.l:     movea.l (a0),a0
        dbra    d0,.l
.r:     rts
; a0 = item, d1 = menu.LeftEdge (+ item.LeftEdge for a sub-item); returns d1 = X, d2 = Y (screen)
; X = d1 + BarVBorder + L + W/2; Y = BarHeight + MenuVBorder - 1 + T + H/2
itemxy: movea.l v_scr(a5),a1
        moveq   #0,d0
        move.b  $1F(a1),d0
        add.w   d0,d1
        add.w   4(a0),d1
        move.w  8(a0),d0
        lsr.w   #1,d0
        add.w   d0,d1
        moveq   #0,d2
        move.b  $1E(a1),d2
        moveq   #0,d0
        move.b  $21(a1),d0
        add.w   d0,d2
        subq.w  #1,d2
        add.w   6(a0),d2
        move.w  10(a0),d0
        lsr.w   #1,d0
        add.w   d0,d2
        rts

clrev:  lea     v_ev(a5),a0
        clr.l   (a0)
        clr.l   4(a0)
        clr.l   8(a0)
        clr.l   12(a0)
        clr.l   16(a0)
        clr.w   20(a0)
        rts
; d1 = X IB, d2 = Y IB
ptrpos: bsr     clrev
        move.b  #4,4(a0)            ; IECLASS_POINTERPOS
        move.w  #$FF,6(a0)          ; IECODE_NOBUTTON
        move.w  d1,10(a0)
        move.w  d2,12(a0)
        ; falls through into inject

; injects v_ev (timestamp = step / rank), then lets 3 frames settle
inject: lea     v_ev(a5),a0
        moveq   #0,d0
        move.w  v_step(a5),d0
        move.l  d0,14(a0)
        addq.w  #1,v_rank(a5)
        move.w  v_rank(a5),d0
        move.l  d0,18(a0)
        lea     v_io(a5),a1
        move.w  #11,28(a1)          ; IND_WRITEEVENT
        move.l  a0,40(a1)
        move.l  #22,36(a1)
        movea.l 4.w,a6
        jsr     -462(a6)            ; SendIO
.w:     tst.w   v_hold(a5)
        bne.s   .nh
        bsr     pump
        movea.l v_gfx(a5),a6
        jsr     -270(a6)            ; WaitTOF: yields the CPU while waiting
        movea.l 4.w,a6
        addq.w  #1,v_spin(a5)
        cmp.w   #100,v_spin(a5)
        bne.s   .nh
        clr.w   v_spin(a5)
        moveq   #'w',d0
        bsr     putc
.nh:    lea     v_io(a5),a1
        jsr     -468(a6)            ; CheckIO
        tst.l   d0
        beq.s   .w
        lea     v_io(a5),a1
        jsr     -474(a6)            ; WaitIO
        tst.w   v_hold(a5)
        bne.s   .r
        moveq   #3,d7
        bsr     pumpn
.r:     rts

; pumps d7 frames
pumpn:  bsr     pump
        movea.l v_gfx(a5),a6
        jsr     -270(a6)            ; WaitTOF
        movea.l 4.w,a6
        subq.w  #1,d7
        bne.s   pumpn
        rts

; drains both ports
pump:   movem.l d0-d7/a0-a4/a6,-(a7)
        movea.l 4.w,a6
        movea.l v_wa(a5),a2
        moveq   #'A',d6
        bsr.s   drain
        movea.l v_wb(a5),a2
        moveq   #'B',d6
        bsr.s   drain
        movem.l (a7)+,d0-d7/a0-a4/a6
        rts
drain:  movea.l 86(a2),a0           ; UserPort
        move.l  a0,d0
        beq.s   .r
        jsr     -372(a6)            ; GetMsg
        tst.l   d0
        beq.s   .r
        movea.l d0,a3
        bsr     logmsg
        cmp.l   #$2000,20(a3)       ; MENUVERIFY
        bne.s   .nv
        cmp.w   #1,24(a3)           ; MENUHOT
        bne.s   .nv
        tst.w   v_cancel(a5)
        beq.s   .nv
        clr.w   v_cancel(a5)
        move.w  #2,24(a3)           ; MENUCANCEL
        lea     m_cancel(pc),a0
        bsr     puts
.nv:    cmp.l   #$100,20(a3)        ; MENUPICK
        bne.s   .np
        bsr     chain
.np:    movea.l a3,a1
        jsr     -378(a6)            ; ReplyMsg
        bra.s   drain
.r:     rts

logmsg: lea     m_m(pc),a0
        bsr     puts
        move.b  d6,d0
        bsr     putc
        bsr     space
        move.l  20(a3),d0           ; Class
        bsr     hex8s
        move.w  24(a3),d0           ; Code
        bsr     hex4s
        move.w  26(a3),d0           ; Qualifier
        bsr     hex4s
        move.l  28(a3),d0           ; IAddress
        cmp.l   v_wa(a5),d0
        bne.s   .1
        lea     m_ea(pc),a0
        bsr     puts
        bra.s   .3
.1:     cmp.l   v_wb(a5),d0
        bne.s   .2
        lea     m_eb(pc),a0
        bsr     puts
        bra.s   .3
.2:     bsr     hex8s
.3:     move.w  32(a3),d0
        bsr     hex4s
        move.w  34(a3),d0
        bsr     hex4s
        move.l  36(a3),d0
        bsr     hex8s
        move.l  40(a3),d0
        bsr     hex8s
        movea.l 44(a3),a0           ; IDCMPWindow
        moveq   #'A',d0
        cmpa.l  v_wa(a5),a0
        beq.s   .4
        moveq   #'B',d0
        cmpa.l  v_wb(a5),a0
        beq.s   .4
        moveq   #'?',d0
.4:     bsr     putc
        bsr     nl
        rts

chain:  move.w  24(a3),d4
        moveq   #8,d5
.c:     cmp.w   #$FFFF,d4
        beq.s   .r
        lea     m_p(pc),a0
        bsr     puts
        move.w  d4,d0
        bsr     hex4s
        movea.l v_ib(a5),a6
        lea     menu0(pc),a0
        moveq   #0,d0
        move.w  d4,d0
        jsr     -144(a6)            ; ItemAddress
        movea.l 4.w,a6
        tst.l   d0
        beq.s   .z
        movea.l d0,a0
        move.w  12(a0),d0
        bsr     hex4s
        move.w  32(a0),d4           ; NextSelect
        bsr     nl
        subq.w  #1,d5
        bne.s   .c
.r:     rts
.z:     bsr     nl
        rts

; ---------------------------------------------------------------- serial output
hex8s:  bsr.s   hex8
        bra.s   space
hex4s:  bsr.s   hex4
        bra.s   space
hex2s:  moveq   #1,d1
        bsr.s   hexn
        bra.s   space
hex8:   moveq   #7,d1
        bra.s   hexn
hex4:   moveq   #3,d1
hexn:   movem.l d0-d2,-(a7)
        move.l  d0,d2
        move.w  d1,d0
        addq.w  #1,d0
        lsl.w   #2,d0
        ror.l   d0,d2
.h:     rol.l   #4,d2
        move.b  d2,d0
        and.b   #15,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        ble.s   .o
        addq.b  #7,d0
.o:     bsr.s   putc
        dbra    d1,.h
        movem.l (a7)+,d0-d2
        rts
space:  move.l  d0,-(a7)
        moveq   #' ',d0
        bsr.s   putc
        move.l  (a7)+,d0
        rts
nl:     move.l  d0,-(a7)
        moveq   #10,d0
        bsr.s   putc
        move.l  (a7)+,d0
        rts
puts:   move.l  d0,-(a7)
.p:     move.b  (a0)+,d0
        beq.s   .e
        bsr.s   putc
        bra.s   .p
.e:     move.l  (a7)+,d0
        rts
; the log is buffered in RAM and flushed to the serial port at quiet points (markers):
; writing the serial port character by character during activity floods the FS-UAE event queue.
putc:   move.l  a0,-(a7)
        movea.l v_lptr(a5),a0
        move.b  d0,(a0)+
        move.l  a0,v_lptr(a5)
        movea.l (a7)+,a0
        rts
flush:  movem.l d0/a0,-(a7)
        lea     logbuf(pc),a0
.f:     cmpa.l  v_lptr(a5),a0
        bhs.s   .e
        move.b  (a0)+,d0
        bsr.s   serc
        bra.s   .f
.e:     lea     logbuf(pc),a0
        move.l  a0,v_lptr(a5)
        movem.l (a7)+,d0/a0
        rts
serc:   movem.l d0/d2,-(a7)
        move.w  #$4000,d2
.wt:    btst    #13-8,SERDATR
        bne.s   .tx
        dbra    d2,.wt
.tx:    and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (a7)+,d0/d2
        rts

; ---------------------------------------------------------------- script
; 1 P x y | 2 B code | 3 K code qual | 4 S c | 5 T n | 6 C | 7 R b | 8 M b | 9 V b | 10 H | 11 U
; 12 PH m | 13 PI m i | 14 PS m i s
script:
        dc.w    5,1                         ; activation by click
        dc.w    1,500,60, 2,$68, 2,$E8
        dc.w    1,100,80, 2,$68, 2,$E8
        dc.w    5,2                         ; simple menu
        dc.w    12,0, 2,$69, 4,'a', 13,0,1, 4,'b', 15,0,54,0,200, 2,$E9
        dc.w    5,3                         ; multiple selection
        dc.w    12,0, 2,$69, 13,0,0, 2,$68, 2,$E8, 13,0,1, 2,$68, 2,$E8, 1,300,150, 2,$E9
        dc.w    5,4                         ; re-selection of the head
        dc.w    12,0, 2,$69, 13,0,0, 2,$68, 2,$E8, 13,0,1, 2,$68, 2,$E8, 13,0,0, 2,$68, 2,$E8
        dc.w    1,300,150, 2,$E9
        dc.w    5,5                         ; CHECKIT / MENUTOGGLE / MutualExclude
        dc.w    12,1, 2,$69, 13,1,0, 4,'c', 2,$E9
        dc.w    12,1, 2,$69, 13,1,0, 2,$E9
        dc.w    12,1, 2,$69, 13,1,1, 2,$E9
        dc.w    12,1, 2,$69, 4,'d', 15,0,40,60,240, 1,300,150, 2,$E9
        dc.w    5,6                         ; MENUCANCEL
        dc.w    6, 12,0, 2,$69, 13,0,0, 2,$E9
        dc.w    5,7                         ; right / left Amiga shortcuts
        dc.w    3,$10,$80, 3,$90,$80, 3,$21,$80, 3,$A1,$80, 3,$22,$80, 3,$A2,$80
        dc.w    3,$10,$40, 3,$90,$40
        dc.w    5,8                         ; submenu
        dc.w    12,0, 2,$69, 13,0,3, 4,'e', 14,0,3,1, 4,'f', 15,38,66,0,260, 2,$E9
        dc.w    5,9                         ; disabled items / menus
        dc.w    12,0, 2,$69, 13,0,2, 2,$E9
        dc.w    12,2, 2,$69, 4,'g', 13,2,0, 2,$E9
        dc.w    5,10                        ; REPORTMOUSE without reading the port
        dc.w    7,1, 10, 1,100,50, 1,101,50, 1,102,50, 1,103,51, 1,104,52, 1,105,53, 11, 7,0
        dc.w    5,11                        ; RMBTRAP
        dc.w    8,1, 2,$69, 2,$E9, 8,0
        dc.w    5,12                        ; VANILLAKEY
        dc.w    9,1, 3,$20,0, 3,$A0,0, 3,$4C,0, 3,$CC,0, 3,$20,$40, 3,$A0,$40, 9,0
        dc.w    5,13                        ; mouse from the keyboard (Amiga + arrows / Alt)
        dc.w    1,100,80, 7,1, 3,$4E,$40, 3,$CE,$40, 3,$4E,$41, 3,$CE,$41, 3,$4E,$240, 3,$4E,$240
        dc.w    3,$CE,$40, 3,$4C,$40, 3,$CC,$40, 7,0
        dc.w    1,100,80, 3,$64,$50, 3,$E4,$40
        dc.w    5,14                        ; click on the screen background
        dc.w    1,300,190, 2,$68, 2,$E8, 3,$20,0, 3,$A0,0
        dc.w    1,100,80, 2,$68, 2,$E8
        dc.w    5,15                        ; menu opened over window B (no menu)
        dc.w    1,500,60, 2,$68, 2,$E8, 12,0, 2,$69, 4,'h', 2,$E9
        dc.w    1,100,80, 2,$68, 2,$E8
        dc.w    0

; ---------------------------------------------------------------- data
reloc:  dc.l    nwa+26, nwb+26
        dc.l    menu0, menu0+14, menu0+18, menu1, menu1+14, menu1+18, menu2+14, menu2+18
        dc.l    i00, i00+18, i01, i01+18, i02, i02+18, i03+18, i03+28
        dc.l    s00, s00+18, s01+18
        dc.l    i10, i10+18, i11, i11+18, i12+18, i20+18
        dc.l    t_open+12, t_quit+12, t_grey+12, t_sub+12, t_s0+12, t_s1+12
        dc.l    t_tog+12, t_ea+12, t_eb+12, t_d+12
        dc.l    -1

        cnop    0,4
nwa:    dc.w    0,12,400,120
        dc.b    0,1
        dc.l    $C37FE, $100E, 0, 0, s_wa, 0, 0
        dc.w    60,30,640,256,1
nwb:    dc.w    420,12,210,100
        dc.b    0,1
        dc.l    $C2408, $6, 0, 0, s_wb, 0, 0
        dc.w    60,30,640,256,1

; Menu: Next, Left, Top, Width, Height, Flags, Name, FirstItem, Jazz/Beat
menu0:  dc.l    menu1
        dc.w    0,0,64,10,1
        dc.l    s_m0, i00
        dc.w    0,0,0,0
menu1:  dc.l    menu2
        dc.w    72,0,72,10,1
        dc.l    s_m1, i10
        dc.w    0,0,0,0
menu2:  dc.l    0
        dc.w    152,0,56,10,0
        dc.l    s_m2, i20
        dc.w    0,0,0,0
; MenuItem: Next, Left, Top, Width, Height, Flags, MutEx, ItemFill, SelectFill, Command, pad, SubItem, NextSelect
i00:    dc.l    i01
        dc.w    0,0,140,10,$52
        dc.l    0, t_open, 0
        dc.b    0,0
        dc.l    0
        dc.w    $FFFF
i01:    dc.l    i02
        dc.w    0,10,140,10,$56
        dc.l    0, t_quit, 0
        dc.b    'Q',0
        dc.l    0
        dc.w    $FFFF
i02:    dc.l    i03
        dc.w    0,20,140,10,$42
        dc.l    0, t_grey, 0
        dc.b    0,0
        dc.l    0
        dc.w    $FFFF
i03:    dc.l    0
        dc.w    0,30,140,10,$92
        dc.l    0, t_sub, 0
        dc.b    0,0
        dc.l    s00
        dc.w    $FFFF
s00:    dc.l    s01
        dc.w    100,0,90,10,$52
        dc.l    0, t_s0, 0
        dc.b    0,0
        dc.l    0
        dc.w    $FFFF
s01:    dc.l    0
        dc.w    100,10,90,10,$56
        dc.l    0, t_s1, 0
        dc.b    'S',0
        dc.l    0
        dc.w    $FFFF
i10:    dc.l    i11
        dc.w    0,0,140,10,$5B
        dc.l    0, t_tog, 0
        dc.b    0,0
        dc.l    0
        dc.w    $FFFF
i11:    dc.l    i12
        dc.w    0,10,140,10,$53
        dc.l    4, t_ea, 0
        dc.b    0,0
        dc.l    0
        dc.w    $FFFF
i12:    dc.l    0
        dc.w    0,20,140,10,$153
        dc.l    2, t_eb, 0
        dc.b    0,0
        dc.l    0
        dc.w    $FFFF
i20:    dc.l    0
        dc.w    0,0,140,10,$56
        dc.l    0, t_d, 0
        dc.b    'D',0
        dc.l    0
        dc.w    $FFFF
; IntuiText: FrontPen, BackPen, DrawMode, pad, Left, Top, Font, Text, Next
t_open: dc.b    0,1,1,0
        dc.w    2,1
        dc.l    0, s_open, 0
t_quit: dc.b    0,1,1,0
        dc.w    2,1
        dc.l    0, s_quit, 0
t_grey: dc.b    0,1,1,0
        dc.w    2,1
        dc.l    0, s_grey, 0
t_sub:  dc.b    0,1,1,0
        dc.w    2,1
        dc.l    0, s_sub, 0
t_s0:   dc.b    0,1,1,0
        dc.w    2,1
        dc.l    0, s_s0, 0
t_s1:   dc.b    0,1,1,0
        dc.w    2,1
        dc.l    0, s_s1, 0
t_tog:  dc.b    0,1,1,0
        dc.w    19,1
        dc.l    0, s_tog, 0
t_ea:   dc.b    0,1,1,0
        dc.w    19,1
        dc.l    0, s_ea, 0
t_eb:   dc.b    0,1,1,0
        dc.w    19,1
        dc.l    0, s_eb, 0
t_d:    dc.b    0,1,1,0
        dc.w    2,1
        dc.l    0, s_d, 0

intname: dc.b   "intuition.library",0
gfxname: dc.b   "graphics.library",0
inpname: dc.b   "input.device",0
s_wa:   dc.b    "Fenetre A",0
s_wb:   dc.b    "B",0
s_m0:   dc.b    "Projet",0
s_m1:   dc.b    "Option",0
s_m2:   dc.b    "Off",0
s_open: dc.b    "Ouvrir",0
s_quit: dc.b    "Quitter",0
s_grey: dc.b    "Grise",0
s_sub:  dc.b    "Sous-menu",0
s_s0:   dc.b    "Sous 0",0
s_s1:   dc.b    "Sous 1",0
s_tog:  dc.b    "Bascule",0
s_ea:   dc.b    "Excl A",0
s_eb:   dc.b    "Excl B",0
s_d:    dc.b    "Desact",0
m_hello: dc.b   "IMENU sonde",10,0
m_ready: dc.b   "READY",10,0
m_idle: dc.b    "IDLE",10,0
m_fail: dc.b    "FAIL",10,0
m_scr:  dc.b    "SCR w h BarH BarV BarH MenV MenH WT WL WR WB font modes : ",0
m_ibl:  dc.b    "IB minx maxx miny maxy 378 544 546 : ",0
m_win:  dc.b    "WIN A borders L T R B : ",0
m_menu: dc.b    "MENU jazzX jazzY beatX beatY : ",0
m_shot: dc.b    "@S ",0
m_row:  dc.b    "R ",0
m_step: dc.b    "@T ",0
m_cancel: dc.b  "   (MENUCANCEL)",10,0
m_m:    dc.b    "M ",0
m_p:    dc.b    "   P ",0
m_ea:   dc.b    "=A ",0
m_eb:   dc.b    "=B ",0
        cnop    0,4
vars:   ds.b    v_size
logbuf:
endprog:
