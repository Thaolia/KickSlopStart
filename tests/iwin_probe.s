; tests/iwin_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "intuition windows" (docs/analysis/intuition-windows-v34.md §9, expected values §8):
; CloseWindow, MoveWindow, SizeWindow, WindowToFront, WindowToBack and WindowLimits through their public LVOs.
; Run from the startup-sequence of a floppy without SetPatch (tests/iwin_probe.sh). Results go to the direct serial
; port (SERDAT), one "IW <step> ..." line per observation, hexadecimal fields, "IW END" at the end.
; Window labels: our windows A..G by letter, "0" = NULL, "?xxxxxxxx" = any other window (the boot CLI window).
; Layer labels: a window's WLayer by its letter, "b" = the screen's BarLayer, "r" = the requester layer of step 5.
; Message lists: IntuiMessage Class in hex, "-" = empty port; "class:win" adds the IDCMPWindow label.
; Waits are dos Delay(10) (the spec's WaitTOF x 10).
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -o build/iwin_probe tests/iwin_probe.s
; Authored code; public structures (intuition/intuition.h, screens.h, exec/ports.h, exec/tasks.h, graphics/clip.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032

; intuition LVOs checked against AROS rom/intuition/intuition.conf (bias 30, 6 bytes per slot)
LVO_CloseWindow      EQU -72
LVO_InitRequester    EQU -138
LVO_ModifyIDCMP      EQU -150
LVO_MoveWindow       EQU -168
LVO_OpenWindow       EQU -204
LVO_Request          EQU -240
LVO_SetWindowTitles  EQU -276
LVO_SizeWindow       EQU -288
LVO_WindowToBack     EQU -306
LVO_WindowToFront    EQU -312
LVO_WindowLimits     EQU -318
LVO_ActivateWindow   EQU -450
; graphics LVOs checked against AROS rom/graphics/graphics.conf
LVO_ReadPixel    EQU -318
; layers LVOs checked against AROS rom/hyperlayers/layers.conf
LVO_DeleteLayer  EQU -90
; exec / dos LVOs checked against src/exec/exec.i and AROS rom/exec/exec.conf, rom/dos/dos.conf
LVO_Forbid       EQU -132
LVO_Permit       EQU -138
LVO_AvailMem     EQU -216
LVO_FindTask     EQU -294
LVO_GetMsg       EQU -372
LVO_ReplyMsg     EQU -378
LVO_CloseLibrary EQU -414
LVO_OpenLibrary  EQU -552
LVO_Delay        EQU -222

; ExecBase / Task / MsgPort / IntuiMessage
EB_PORTLIST EQU $188
TC_SIGALLOC EQU $12
MP_SIGBIT   EQU $0F
MP_MSGLIST  EQU $14
IM_CLASS    EQU $14
IM_CODE     EQU $18
IM_WIN      EQU $2C
; IntuitionBase
IB_ACTWIN   EQU $34
IB_ACTSCR   EQU $38
; Screen
SC_FIRSTWIN EQU $04
SC_TITLE    EQU $16
SC_DEFTITLE EQU $1A
SC_RPORT    EQU $54
SC_LINFO    EQU $E0
SC_BARLAYER EQU $14E
; Window
WD_LEFT     EQU $04
WD_TOP      EQU $06
WD_WIDTH    EQU $08
WD_HEIGHT   EQU $0A
WD_MINW     EQU $10
WD_SCREEN   EQU $2E
WD_PARENT   EQU $42
WD_DESC     EQU $46
WD_UPORT    EQU $56
WD_WLAYER   EQU $7C
; Requester
RQ_LEFT     EQU $04
RQ_TOP      EQU $06
RQ_WIDTH    EQU $08
RQ_HEIGHT   EQU $0A
RQ_FLAGS    EQU $1C
RQ_BACKFILL EQU $1E
RQ_LAYER    EQU $20
RQ_SIZE     EQU 112
REQACTIVE   EQU $2000
; Layer
LY_BACK     EQU $04
LY_WINDOW   EQU $28

NWIN        EQU 7

INT             macro
                move.l  intb-vars(a4),a6
                endm
EXEC            macro
                move.l  4.w,a6
                endm
; MSG string: prints the string (puts)
MSG             macro
                lea     \1(pc),a0
                bsr     puts
                endm
; WIN n: a0 = window n (0 = A)
WIN             macro
                move.l  wins+4*\1-vars(a4),a0
                endm

_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a4
                move.w  #372,SERPER
                EXEC
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,gfxb-vars(a4)
                beq     pout
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,intb-vars(a4)
                beq     pout
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,dosb-vars(a4)
                beq     pout
                lea     layname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,layb-vars(a4)
                beq     pout
                MSG     m_begin
                bsr     wait
                EXEC
                moveq   #0,d1
                jsr     LVO_AvailMem(a6)
                move.l  d0,av0-vars(a4)

; --- 1: A then B (ACTIVATE), Parent/Descendant chain
                lea     nwA(pc),a0
                moveq   #0,d0
                bsr     openw
                bsr     wait
                lea     nwB(pc),a0
                moveq   #1,d0
                bsr     openw
                bsr     wait
                WIN     0
                move.l  WD_SCREEN(a0),scr-vars(a4)
                MSG     m_1
                WIN     0
                move.l  WD_PARENT(a0),d0
                MSG     m_ap
                bsr     lbl
                WIN     0
                move.l  WD_DESC(a0),d0
                MSG     m_ad
                bsr     lbl
                WIN     1
                move.l  WD_PARENT(a0),d0
                MSG     m_bp
                bsr     lbl
                WIN     1
                move.l  WD_DESC(a0),d0
                MSG     m_bd
                bsr     lbl
                bsr     pact
                bsr     nl
                MSG     m_1m
                WIN     0
                bsr     drain
                MSG     m_bc
                WIN     1
                bsr     drain
                bsr     nl

; --- 2: SetWindowTitles(B, -1, "T2")
                WIN     1
                move.l  #-1,a1
                lea     s_t2(pc),a2
                INT
                jsr     LVO_SetWindowTitles(a6)
                bsr     wait
                MSG     m_2
                WIN     0
                bsr     drain
                MSG     m_bc
                WIN     1
                bsr     drain
                bsr     nl

; --- 3: CloseWindow(B): at once ActiveWindow, Screen.Title, A's port; after the wait title and A's messages
                moveq   #1,d0
                bsr     closew
                MSG     m_3
                bsr     pact
                MSG     m_t2
                move.l  scr-vars(a4),a0
                lea     s_t2(pc),a1
                cmp.l   SC_TITLE(a0),a1
                bsr     pbool
                MSG     m_fw
                move.l  scr-vars(a4),a0
                move.l  SC_FIRSTWIN(a0),d0
                bsr     lbl
                MSG     m_acnt
                WIN     0
                move.l  WD_UPORT(a0),a0
                bsr     count
                bsr     phexz
                bsr     nl
                bsr     wait
                MSG     m_3b
                move.l  scr-vars(a4),a0
                move.l  SC_DEFTITLE(a0),d0
                cmp.l   SC_TITLE(a0),d0
                bsr     pbool
                MSG     m_ac
                WIN     0
                bsr     drain
                bsr     nl

; --- 4: shared port. C (IDCMP 0) and D (ACTIVE|INACTIVE), C.UserPort := D.UserPort
                lea     nwC(pc),a0
                moveq   #2,d0
                bsr     openw
                lea     nwD(pc),a0
                moveq   #3,d0
                bsr     openw
                bsr     wait
                WIN     3
                move.l  WD_UPORT(a0),a1
                move.l  a1,port-vars(a4)
                moveq   #0,d0
                move.b  MP_SIGBIT(a1),d0
                move.l  d0,sigbit-vars(a4)
                WIN     2
                move.l  a1,WD_UPORT(a0)
                move.l  #$C0000,d0
                INT
                jsr     LVO_ModifyIDCMP(a6)
                WIN     2
                INT
                jsr     LVO_ActivateWindow(a6)
                bsr     wait
                WIN     3
                INT
                jsr     LVO_ActivateWindow(a6)
                bsr     wait
                MSG     m_4
                bsr     pport
                MSG     m_sig
                move.l  sigbit-vars(a4),d0
                bsr     phexz
                bsr     psig
                bsr     pact
                bsr     nl
                moveq   #2,d0
                bsr     closew
                MSG     m_4b
                bsr     pportfreed
                bsr     psig
                MSG     m_dang
                WIN     3
                move.l  port-vars(a4),d0
                cmp.l   WD_UPORT(a0),d0
                bsr     pbool
                bsr     pact
                bsr     nl
                bsr     wait
                MSG     m_4bb
                WIN     0
                bsr     drain
                bsr     nl
                WIN     3
                clr.l   WD_UPORT(a0)
                moveq   #3,d0
                bsr     closew
                MSG     m_4c
                bsr     pact
                bsr     wait
                MSG     m_ac
                WIN     0
                bsr     drain
                bsr     nl

; --- 5: requester left up on a SMART window, then CloseWindow
                lea     nwE(pc),a0
                moveq   #4,d0
                bsr     openw
                bsr     wait
                lea     req-vars(a4),a0
                INT
                jsr     LVO_InitRequester(a6)
                lea     req-vars(a4),a0
                move.w  #20,RQ_LEFT(a0)
                move.w  #20,RQ_TOP(a0)
                move.w  #120,RQ_WIDTH(a0)
                move.w  #30,RQ_HEIGHT(a0)
                move.b  #3,RQ_BACKFILL(a0)
                WIN     4
                move.l  a0,a1
                lea     req-vars(a4),a0
                jsr     LVO_Request(a6)
                MSG     m_5
                bsr     phexz
                bsr     wait
                lea     req-vars(a4),a0
                move.l  RQ_LAYER(a0),reql-vars(a4)
                MSG     m_rl
                tst.l   reql-vars(a4)
                sne     d0
                bsr     pb
                MSG     m_pen
                bsr     rqpen
                bsr     nl
                WIN     4
                move.l  a0,olde-vars(a4)
                moveq   #4,d0
                bsr     closew
                bsr     wait
                MSG     m_5b
                lea     req-vars(a4),a0
                tst.l   RQ_LAYER(a0)
                sne     d0
                bsr     pb
                MSG     m_ra
                lea     req-vars(a4),a0
                move.w  RQ_FLAGS(a0),d0
                and.w   #REQACTIVE,d0
                sne     d0
                bsr     pb
                MSG     m_lnk
                bsr     reqlinked
                move.l  d0,d2
                bsr     phexz
                MSG     m_lw
                moveq   #0,d0
                tst.l   d2
                beq.s   .nolw
                move.l  reql-vars(a4),a0
                move.l  LY_WINDOW(a0),d0
                cmp.l   olde-vars(a4),d0
                seq     d0
.nolw:          bsr     pb
                MSG     m_pen
                bsr     rqpen
                bsr     pact
                bsr     nl
                MSG     m_lyr
                bsr     layers
                bsr     nl
                tst.l   d2
                beq.s   .nodel
                move.l  reql-vars(a4),a1
                sub.l   a0,a0
                move.l  layb-vars(a4),a6
                jsr     LVO_DeleteLayer(a6)
                MSG     m_del
                bsr     phexz
                bsr     nl
.nodel:         clr.l   reql-vars(a4)

; --- 6: SizeWindow on the active F and the inactive G
                lea     nwF(pc),a0
                moveq   #5,d0
                bsr     openw
                bsr     wait
                MSG     m_6
                WIN     5
                bsr     drain
                bsr     nl
                WIN     5
                move.l  #200,d0
                moveq   #0,d1
                INT
                jsr     LVO_SizeWindow(a6)
                MSG     m_6a
                bsr     pfsize
                bsr     wait
                bsr     pfsize
                MSG     m_fc
                WIN     5
                bsr     drain
                bsr     nl
                WIN     5
                moveq   #0,d0
                moveq   #0,d1
                INT
                jsr     LVO_SizeWindow(a6)
                bsr     wait
                MSG     m_6b
                bsr     pfsize
                MSG     m_fc
                WIN     5
                bsr     drain
                bsr     nl
                lea     nwG(pc),a0
                moveq   #6,d0
                bsr     openw
                bsr     wait
                MSG     m_6c
                bsr     pact
                MSG     m_fc
                WIN     5
                bsr     drain
                MSG     m_gc
                WIN     6
                bsr     drain
                bsr     nl
                WIN     6
                moveq   #20,d0
                moveq   #10,d1
                INT
                jsr     LVO_SizeWindow(a6)
                bsr     wait
                MSG     m_6d
                WIN     6
                bsr     psize
                MSG     m_fc
                WIN     5
                bsr     drain
                MSG     m_gc
                WIN     6
                bsr     drain
                bsr     nl
                WIN     5
                move.l  #-350,d0
                moveq   #0,d1
                INT
                jsr     LVO_SizeWindow(a6)
                bsr     wait
                MSG     m_6e
                bsr     pfsize
                MSG     m_fc
                WIN     5
                bsr     drain
                MSG     m_gc
                WIN     6
                bsr     drain
                bsr     nl

; --- 7: WindowLimits on F at 400 wide, the seven calls of V15
                WIN     5
                move.l  #350,d0
                moveq   #0,d1
                INT
                jsr     LVO_SizeWindow(a6)
                bsr     wait
                MSG     m_7
                bsr     pfsize
                MSG     m_fc
                WIN     5
                bsr     drain
                bsr     nl
                lea     limtab(pc),a2
                moveq   #7-1,d7
.lim:           WIN     5
                movem.l (a2)+,d0-d3
                INT
                jsr     LVO_WindowLimits(a6)
                MSG     m_7l
                bsr     phex8
                MSG     m_mm
                WIN     5
                lea     WD_MINW(a0),a3
                moveq   #4-1,d3
.limw:          bsr     sp1
                move.w  (a3)+,d0
                bsr     phex4
                dbra    d3,.limw
                bsr     nl
                dbra    d7,.lim

; --- 8: MoveWindow
                WIN     5
                moveq   #10,d0
                moveq   #5,d1
                INT
                jsr     LVO_MoveWindow(a6)
                MSG     m_8
                bsr     pfpos
                bsr     wait
                bsr     pfpos
                MSG     m_fc
                WIN     5
                bsr     drain
                bsr     nl
                WIN     5
                moveq   #0,d0
                moveq   #0,d1
                INT
                jsr     LVO_MoveWindow(a6)
                bsr     wait
                MSG     m_8b
                WIN     5
                move.l  WD_UPORT(a0),a0
                bsr     count
                bsr     phexz
                MSG     m_gc
                WIN     6
                bsr     drain
                bsr     nl
                WIN     5
                move.l  #-350,d0
                moveq   #0,d1
                INT
                jsr     LVO_SizeWindow(a6)
                bsr     wait
                MSG     m_8c
                bsr     pfsize
                bsr     pfpos
                WIN     5
                move.l  #560,d0
                moveq   #0,d1
                INT
                jsr     LVO_MoveWindow(a6)
                bsr     wait
                bsr     pfpos
                bsr     fhome
                bsr     pfpos
                WIN     5
                moveq   #-100,d0
                moveq   #0,d1
                INT
                jsr     LVO_MoveWindow(a6)
                bsr     wait
                bsr     pfpos
                bsr     fhome
                bsr     pfpos
                MSG     m_fc
                WIN     5
                bsr     drain
                MSG     m_gc
                WIN     6
                bsr     drain
                bsr     nl

; --- 9: depth, G in front of F
                MSG     m_9
                bsr     layers
                bsr     nl
                WIN     6
                INT
                jsr     LVO_WindowToBack(a6)
                MSG     m_9a
                bsr     topg
                bsr     layers
                bsr     nl
                bsr     wait
                MSG     m_9b
                bsr     layers
                bsr     nl
                WIN     6
                INT
                jsr     LVO_WindowToFront(a6)
                bsr     wait
                MSG     m_9c
                bsr     topg
                bsr     layers
                MSG     m_fc
                WIN     5
                bsr     drain
                MSG     m_gc
                WIN     6
                bsr     drain
                bsr     nl

; --- 10: requests queued then CloseWindow before any wait
                WIN     5
                moveq   #5,d0
                moveq   #5,d1
                INT
                jsr     LVO_MoveWindow(a6)
                WIN     5
                moveq   #5,d0
                moveq   #5,d1
                jsr     LVO_SizeWindow(a6)
                WIN     5
                jsr     LVO_WindowToFront(a6)
                moveq   #5,d0
                bsr     closew
                bsr     wait
                MSG     m_alive
                bsr     pact
                bsr     nl
                moveq   #6,d0
                bsr     closew
                bsr     wait
                moveq   #0,d0
                bsr     closew
                bsr     wait

; --- 11: memory balance
                EXEC
                moveq   #0,d1
                jsr     LVO_AvailMem(a6)
                move.l  d0,d2
                MSG     m_11
                move.l  av0-vars(a4),d0
                bsr     phex8
                MSG     m_av1
                move.l  d2,d0
                bsr     phex8
                MSG     m_avd
                sub.l   av0-vars(a4),d0
                bsr     phex8
                bsr     nl
pend:           MSG     m_end
pout:           EXEC
                lea     libs-vars(a4),a2
                moveq   #4-1,d2
.cl:            move.l  (a2)+,d0
                beq.s   .cln
                move.l  d0,a1
                jsr     LVO_CloseLibrary(a6)
.cln:           dbra    d2,.cl
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- window helpers
; openw(a0 = NewWindow, d0 = index): wins[index] := OpenWindow; failure prints "IW OPENFAIL" and ends the run
openw:          move.l  d0,-(sp)
                INT
                jsr     LVO_OpenWindow(a6)
                move.l  (sp)+,d1
                lsl.w   #2,d1
                lea     wins-vars(a4),a0
                move.l  d0,0(a0,d1.w)
                bne.s   .ok
                addq.l  #4,sp
                MSG     m_ofail
                bra     pend
.ok:            rts
; closew(d0 = index): CloseWindow(wins[index]), wins[index] := 0
closew:         lsl.w   #2,d0
                lea     wins-vars(a4),a0
                add.w   d0,a0
                move.l  (a0),d0
                clr.l   (a0)
                move.l  d0,a0
                INT
                jmp     LVO_CloseWindow(a6)

wait:           move.l  dosb-vars(a4),a6
                moveq   #10,d1
                jmp     LVO_Delay(a6)

; fhome: MoveWindow(F, 50 - LeftEdge, 0), wait
fhome:          WIN     5
                moveq   #50,d0
                sub.w   WD_LEFT(a0),d0
                ext.l   d0
                moveq   #0,d1
                INT
                jsr     LVO_MoveWindow(a6)
                bra.s   wait

; drain(a0 = window): " <class>" for each message taken from its UserPort (replied), " -" when empty
drain:          movem.l d2/a2-a3,-(sp)
                move.l  a0,a3
                moveq   #0,d2
                EXEC
.lp:            move.l  WD_UPORT(a3),d0
                beq.s   .end
                move.l  d0,a0
                jsr     LVO_GetMsg(a6)
                tst.l   d0
                beq.s   .end
                move.l  d0,a2
                bsr     sp1
                move.l  IM_CLASS(a2),d0
                bsr     phexz
                move.l  a2,a1
                jsr     LVO_ReplyMsg(a6)
                moveq   #1,d2
                bra.s   .lp
.end:           tst.l   d2
                bne.s   .ret
                MSG     m_none
.ret:           movem.l (sp)+,d2/a2-a3
                rts

; count(a0 = port) -> d0 = messages in mp_MsgList (stops at 64)
count:          moveq   #0,d0
                move.l  MP_MSGLIST(a0),a0
.lp:            tst.l   (a0)
                beq.s   .x
                move.l  (a0),a0
                addq.l  #1,d0
                cmp.w   #64,d0
                blo.s   .lp
.x:             rts

; pport: " n=<count> inl=<in PortList> <class>:<win>/<code> ..." for the shared port, messages left queued
pport:          movem.l d2/a2,-(sp)
                MSG     m_n
                move.l  port-vars(a4),a0
                bsr.s   count
                bsr     phexz
                bsr     pinl
                move.l  port-vars(a4),a0
                move.l  MP_MSGLIST(a0),a2
                moveq   #16-1,d2
.lp:            tst.l   (a2)
                beq.s   .x
                bsr     sp1
                move.l  IM_CLASS(a2),d0
                bsr     phexz
                moveq   #':',d1
                bsr     putc
                move.l  IM_WIN(a2),d0
                bsr     lbl
                moveq   #'/',d1
                bsr     putc
                moveq   #0,d0
                move.w  IM_CODE(a2),d0
                bsr     phexz
                move.l  (a2),a2
                dbra    d2,.lp
.x:             movem.l (sp)+,d2/a2
                rts
; pportfreed: " n=<count read from the freed port> inl=<in PortList>"
pportfreed:     MSG     m_n
                move.l  port-vars(a4),a0
                bsr.s   count
                bsr     phexz
; pinl: " inl=1/0", port in ExecBase->PortList
pinl:           movem.l d2,-(sp)
                MSG     m_inl
                EXEC
                jsr     LVO_Forbid(a6)
                moveq   #0,d2
                move.l  EB_PORTLIST(a6),a0
.lp:            tst.l   (a0)
                beq.s   .x
                cmp.l   port-vars(a4),a0
                seq     d2
                beq.s   .x
                move.l  (a0),a0
                bra.s   .lp
.x:             jsr     LVO_Permit(a6)
                move.l  d2,d0
                bsr     pb
                movem.l (sp)+,d2
                rts
; psig: " alloc=1/0", the port's signal bit in the calling task's tc_SigAlloc
psig:           MSG     m_alloc
                EXEC
                sub.l   a1,a1
                jsr     LVO_FindTask(a6)
                move.l  d0,a0
                move.l  TC_SIGALLOC(a0),d0
                move.l  sigbit-vars(a4),d1
                btst    d1,d0
                sne     d0
                bra     pb

; pact: " act=<ActiveWindow> scr=<1 if ActiveScreen is the Workbench screen>"
pact:           MSG     m_act
                move.l  intb-vars(a4),a0
                move.l  IB_ACTWIN(a0),d0
                bsr     lbl
                MSG     m_ascr
                move.l  intb-vars(a4),a0
                move.l  IB_ACTSCR(a0),d0
                cmp.l   scr-vars(a4),d0
                seq     d0
                bra     pb

; pfsize / psize(a0 = window): " <Width>x<Height>"
pfsize:         WIN     5
psize:          move.l  a0,-(sp)
                bsr     sp1
                move.w  WD_WIDTH(a0),d0
                bsr     phex4
                moveq   #'x',d1
                bsr     putc
                move.l  (sp)+,a0
                move.w  WD_HEIGHT(a0),d0
                bra     phex4
; pfpos: " <LeftEdge>,<TopEdge>" of F
pfpos:          bsr     sp1
                WIN     5
                move.w  WD_LEFT(a0),d0
                bsr     phex4
                moveq   #',',d1
                bsr     putc
                WIN     5
                move.w  WD_TOP(a0),d0
                bra     phex4

; rqpen: "<pen>" read on the screen RastPort at the centre of the step 5 requester (screen 280,115)
rqpen:          move.l  scr-vars(a4),a1
                lea     SC_RPORT(a1),a1
                move.l  #280,d0
                moveq   #115,d1
                move.l  gfxb-vars(a4),a6
                jsr     LVO_ReadPixel(a6)
                bra     phexz

; reqlinked -> d0 = 1 if the saved requester layer is in the screen's layer list
reqlinked:      moveq   #0,d0
                move.l  reql-vars(a4),d1
                beq.s   .x
                move.l  scr-vars(a4),a0
                move.l  SC_LINFO(a0),a0
                moveq   #32-1,d0
.lp:            cmp.l   a0,d1
                beq.s   .y
                move.l  LY_BACK(a0),a0
                cmp.w   #0,a0
                dbeq    d0,.lp
                moveq   #0,d0
.x:             rts
.y:             moveq   #1,d0
                rts

; topg: " topG=1/0" whether top_layer is G's WLayer
topg:           MSG     m_topg
                move.l  scr-vars(a4),a0
                move.l  SC_LINFO(a0),d0
                WIN     6
                cmp.l   WD_WLAYER(a0),d0
                seq     d0
                bra     pb

; layers: " <label>" for each layer of the screen from top_layer to the back
layers:         movem.l d2/a2,-(sp)
                move.l  scr-vars(a4),a0
                move.l  SC_LINFO(a0),a2
                moveq   #16-1,d2
.lp:            move.l  a2,d0
                beq.s   .x
                bsr     sp1
                bsr     llbl
                move.l  LY_BACK(a2),a2
                dbra    d2,.lp
.x:             movem.l (sp)+,d2/a2
                rts
; llbl(d0 = layer)
llbl:           movem.l d0/d2/a0-a1,-(sp)
                lea     wins-vars(a4),a1
                moveq   #0,d2
.lp:            move.l  (a1)+,d1
                beq.s   .nx
                move.l  d1,a0
                cmp.l   WD_WLAYER(a0),d0
                beq.s   .hit
.nx:            addq.w  #1,d2
                cmp.w   #NWIN,d2
                blo.s   .lp
                moveq   #'b',d1
                move.l  scr-vars(a4),a0
                cmp.l   SC_BARLAYER(a0),d0
                beq.s   .ch
                moveq   #'r',d1
                cmp.l   reql-vars(a4),d0
                beq.s   .ch
                moveq   #'?',d1
                bsr     putc
                bsr     phex8
                bra.s   .ret
.hit:           moveq   #'A',d1
                add.b   d2,d1
.ch:            bsr     putc
.ret:           movem.l (sp)+,d0/d2/a0-a1
                rts

; lbl(d0 = window): letter, "0" or "?xxxxxxxx"
lbl:            movem.l d0/d2/a0,-(sp)
                moveq   #'0',d1
                tst.l   d0
                beq.s   .ch
                lea     wins-vars(a4),a0
                moveq   #0,d2
.lp:            cmp.l   (a0)+,d0
                beq.s   .hit
                addq.w  #1,d2
                cmp.w   #NWIN,d2
                blo.s   .lp
                moveq   #'?',d1
                bsr     putc
                bsr     phex8
                bra.s   .ret
.hit:           moveq   #'A',d1
                add.b   d2,d1
.ch:            bsr     putc
.ret:           movem.l (sp)+,d0/d2/a0
                rts

; pbool: Z set -> "1", else "0"; pb(d0.b): non-zero -> "1"
pbool:          seq     d0
pb:             moveq   #'0',d1
                tst.b   d0
                beq.s   .z
                moveq   #'1',d1
.z:             bra.s   putc

; --- printing helpers
nl:             moveq   #10,d1
                bra.s   putc
sp1:            moveq   #' ',d1
putc:           move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
                rts
; phexz(d0.l): hexadecimal without leading zeros
phexz:          movem.l d0/d2-d3/a0,-(sp)
                move.l  d0,d3
                moveq   #7,d2
.sk:            tst.w   d2
                beq.s   .pr
                move.l  d3,d0
                rol.l   #4,d0
                and.w   #$F,d0
                bne.s   .pr
                lsl.l   #4,d3
                subq.w  #1,d2
                bra.s   .sk
.pr:            rol.l   #4,d3
                move.l  d3,d0
                and.w   #$F,d0
                lea     hexd(pc),a0
                move.b  0(a0,d0.w),d1
                bsr.s   putc
                dbra    d2,.pr
                movem.l (sp)+,d0/d2-d3/a0
                rts
phex8:          swap    d0
                bsr.s   phex4
                swap    d0
phex4:          move.w  d0,-(sp)
                lsr.w   #8,d0
                bsr.s   phex2
                move.w  (sp)+,d0
phex2:          move.w  d0,-(sp)
                lsr.b   #4,d0
                bsr.s   .n
                move.w  (sp)+,d0
.n:             move.w  d0,-(sp)
                and.w   #$F,d0
                move.b  hexd(pc,d0.w),d1
                bsr.s   putc
                move.w  (sp)+,d0
                rts
hexd:           dc.b    "0123456789ABCDEF"
puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr     putc
                bra.s   puts
.e:             rts

; WindowLimits arguments (D0, D1, D2, D3) of V15, in call order
limtab:         dc.l    100,50,300,150
                dc.l    0,0,0,0
                dc.l    $10000,0,0,0
                dc.l    0,0,$10500,0
                dc.l    500,0,0,0
                dc.l    -5,0,0,0
                dc.l    100,0,0,0

; NewWindow: Left, Top, Width, Height, DetailPen, BlockPen, IDCMP, Flags, FirstGadget, CheckMark, Title, Screen,
; BitMap, MinWidth, MinHeight, MaxWidth, MaxHeight, Type (WBENCHSCREEN)
nwA:            dc.w    40,30,300,100
                dc.b    -1,-1
                dc.l    $C0206,$104F,0,0,s_a,0,0
                dc.w    60,30,640,256,1
nwB:            dc.w    100,60,300,100
                dc.b    -1,-1
                dc.l    $C0206,$104F,0,0,s_b,0,0
                dc.w    60,30,640,256,1
nwC:            dc.w    60,140,200,60
                dc.b    -1,-1
                dc.l    0,$000F,0,0,s_c,0,0
                dc.w    60,30,640,256,1
nwD:            dc.w    300,140,200,60
                dc.b    -1,-1
                dc.l    $C0000,$000F,0,0,s_d,0,0
                dc.w    60,30,640,256,1
nwE:            dc.w    200,80,250,100
                dc.b    -1,-1
                dc.l    0,$100F,0,0,s_e,0,0
                dc.w    60,30,640,256,1
nwF:            dc.w    40,30,200,80
                dc.b    -1,-1
                dc.l    6,$1047,0,0,s_f,0,0
                dc.w    100,50,640,150,1
nwG:            dc.w    300,120,200,80
                dc.b    -1,-1
                dc.l    6,$0047,0,0,s_g,0,0
                dc.w    100,50,640,150,1

gfxname:        dc.b    "graphics.library",0
intname:        dc.b    "intuition.library",0
dosname:        dc.b    "dos.library",0
layname:        dc.b    "layers.library",0
s_a:            dc.b    "A",0
s_b:            dc.b    "B",0
s_c:            dc.b    "C",0
s_d:            dc.b    "D",0
s_e:            dc.b    "E",0
s_f:            dc.b    "F",0
s_g:            dc.b    "G",0
s_t2:           dc.b    "T2",0
m_begin:        dc.b    10,"IW BEGIN",10,0
m_end:          dc.b    "IW END",10,0
m_ofail:        dc.b    "IW OPENFAIL",10,0
m_1:            dc.b    "IW 1",0
m_ap:           dc.b    " A.par=",0
m_ad:           dc.b    " A.desc=",0
m_bp:           dc.b    " B.par=",0
m_bd:           dc.b    " B.desc=",0
m_1m:           dc.b    "IW 1m A:",0
m_bc:           dc.b    " B:",0
m_2:            dc.b    "IW 2 A:",0
m_3:            dc.b    "IW 3",0
m_t2:           dc.b    " titleT2=",0
m_fw:           dc.b    " first=",0
m_acnt:         dc.b    " Acnt=",0
m_3b:           dc.b    "IW 3b dflt=",0
m_ac:           dc.b    " A:",0
m_4:            dc.b    "IW 4",0
m_4b:           dc.b    "IW 4b",0
m_4bb:          dc.b    "IW 4bb A:",0
m_4c:           dc.b    "IW 4c",0
m_sig:          dc.b    " sigbit=",0
m_n:            dc.b    " n=",0
m_inl:          dc.b    " inl=",0
m_alloc:        dc.b    " alloc=",0
m_dang:         dc.b    " D.port=old:",0
m_act:          dc.b    " act=",0
m_ascr:         dc.b    " ascrWB=",0
m_5:            dc.b    "IW 5 req=",0
m_rl:           dc.b    " layer=",0
m_pen:          dc.b    " pen=",0
m_5b:           dc.b    "IW 5b layer=",0
m_ra:           dc.b    " reqactive=",0
m_lnk:          dc.b    " linked=",0
m_lw:           dc.b    " lwin=E:",0
m_lyr:          dc.b    "IW 5c layers:",0
m_del:          dc.b    "IW 5d DeleteLayer=",0
m_6:            dc.b    "IW 6 F:",0
m_6a:           dc.b    "IW 6a",0
m_6b:           dc.b    "IW 6b",0
m_6c:           dc.b    "IW 6c",0
m_6d:           dc.b    "IW 6d G",0
m_6e:           dc.b    "IW 6e",0
m_fc:           dc.b    " F:",0
m_gc:           dc.b    " G:",0
m_7:            dc.b    "IW 7",0
m_7l:           dc.b    "IW 7l d0=",0
m_mm:           dc.b    " lim",0
m_8:            dc.b    "IW 8",0
m_8b:           dc.b    "IW 8b Fcnt=",0
m_8c:           dc.b    "IW 8c",0
m_9:            dc.b    "IW 9 layers:",0
m_9a:           dc.b    "IW 9a",0
m_9b:           dc.b    "IW 9b layers:",0
m_9c:           dc.b    "IW 9c",0
m_topg:         dc.b    " topG=",0
m_alive:        dc.b    "IW ALIVE",0
m_11:           dc.b    "IW 11 av0=",0
m_av1:          dc.b    " av1=",0
m_avd:          dc.b    " diff=",0
m_none:         dc.b    " -",0
                even

vars:
libs:
gfxb:           dc.l    0
intb:           dc.l    0
dosb:           dc.l    0
layb:           dc.l    0
wins:           dcb.l   NWIN,0
scr:            dc.l    0
port:           dc.l    0
sigbit:         dc.l    0
reql:           dc.l    0
olde:           dc.l    0
av0:            dc.l    0
req:            dcb.b   RQ_SIZE,0
