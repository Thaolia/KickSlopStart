; idcmp_test.s - IDCMP verification classes, DELTAMOVE and the RAWKEY dead-key history (implementation track, our own
; test program). Opens a window on the Workbench screen at (20,20), 300 x 120, with a one-item menu strip and a
; POINTREL DMRequest (one ENDGADGET button), and asks RAWKEY, MOUSEBUTTONS, MENUPICK, MENUVERIFY, SIZEVERIFY, NEWSIZE,
; REQSET, REQCLEAR, CLOSEWINDOW and DELTAMOVE. Every message is written to the CLI output as
;   "IM <class> <code> <mousex> <mousey> <extra>"
; in hex, extra = the 4 bytes IAddress points at for RAWKEY, IAddress itself otherwise. The first MENUHOT is replied
; MENUCANCEL, the later ones unchanged. Writes "IDCMP READY" once open, then reads nothing for 4 s (messages sent
; meanwhile pile up beyond intuition's pool); CLOSEWINDOW ends it ("IDCMP END").
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o idcmp_test tests/idcmp_test.s

        section code,code

start:
        move.l  ($4).w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        move.l  d0,a5                ; a5 = IntuitionBase
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,a4                ; a4 = DOSBase
        move.l  a5,a6
        lea     nw(pc),a0
        jsr     -204(a6)             ; OpenWindow
        tst.l   d0
        beq     .fail
        move.l  d0,a3                ; a3 = window
        move.l  a3,a0
        lea     menu(pc),a1
        jsr     -264(a6)             ; SetMenuStrip
        lea     req(pc),a0
        jsr     -138(a6)             ; InitRequester
        lea     req(pc),a0
        move.w  #120,8(a0)           ; Width
        move.w  #40,10(a0)           ; Height
        move.w  #-20,12(a0)          ; RelLeft
        move.w  #-10,14(a0)          ; RelTop
        lea     reqgad(pc),a1
        move.l  a1,16(a0)            ; ReqGadget
        move.w  #$0001,28(a0)        ; Flags: POINTREL
        move.b  #3,30(a0)            ; BackFill
        move.l  a3,a0
        lea     req(pc),a1
        jsr     -258(a6)             ; SetDMRequest
        lea     m_ready(pc),a0
        bsr     say
        move.l  a4,a6                ; 4 s without reading: the messages pile up beyond the pool
        move.l  #50*4,d1
        jsr     -198(a6)             ; Delay
        moveq   #0,d7                ; d7 = MENUHOT messages seen
.loop:
        move.l  86(a3),a0            ; UserPort
        move.l  ($4).w,a6
        jsr     -384(a6)             ; WaitPort
.get:
        move.l  86(a3),a0
        jsr     -372(a6)             ; GetMsg
        tst.l   d0
        beq.s   .loop
        move.l  d0,a2                ; a2 = IntuiMessage
        lea     line(pc),a1
        move.l  20(a2),d0            ; Class
        bsr     hex8
        move.w  24(a2),d0            ; Code
        bsr     hex4
        move.w  32(a2),d0            ; MouseX
        bsr     hex4
        move.w  34(a2),d0            ; MouseY
        bsr     hex4
        move.l  28(a2),d0            ; IAddress
        cmp.l   #$00000400,20(a2)    ; RAWKEY: what it points at
        bne.s   .extra
        move.l  d0,a0
        move.l  (a0),d0
.extra:
        bsr     hex8
        move.b  #10,-1(a1)
        lea     line0(pc),a0
        bsr     sayn
        cmp.l   #$00002000,20(a2)    ; MENUVERIFY
        bne.s   .reply
        cmp.w   #1,24(a2)            ; MENUHOT
        bne.s   .reply
        addq.w  #1,d7
        cmp.w   #1,d7
        bne.s   .reply
        move.w  #2,24(a2)            ; the first one: MENUCANCEL
.reply:
        move.l  20(a2),d6
        move.l  a2,a1
        move.l  ($4).w,a6
        jsr     -378(a6)             ; ReplyMsg
        cmp.l   #$00000200,d6        ; CLOSEWINDOW
        bne     .get
        move.l  a5,a6
        move.l  a3,a0
        jsr     -54(a6)              ; ClearMenuStrip
        move.l  a3,a0
        jsr     -72(a6)              ; CloseWindow
        lea     m_end(pc),a0
        bsr     say
        moveq   #0,d0
        rts
.fail:
        moveq   #20,d0
        rts

; hex8(d0.l) / hex4(d0.w): hex digits and a space at a1.
hex8:
        swap    d0
        bsr.s   hex4n
        swap    d0
        bsr.s   hex4n
        move.b  #' ',(a1)+
        rts
hex4:
        bsr.s   hex4n
        move.b  #' ',(a1)+
        rts
hex4n:
        moveq   #4-1,d1
.hx:
        rol.w   #4,d0
        move.w  d0,-(sp)
        and.w   #$F,d0
        move.b  digits(pc,d0.w),(a1)+
        move.w  (sp)+,d0
        dbra    d1,.hx
        rts
digits: dc.b    "0123456789ABCDEF"

; say(a0 = text ended by 0) / sayn (same, a0 = line0 and its length up to a1): Write(Output(), ...).
say:
        move.l  a0,a1
.sy_l:
        tst.b   (a1)+
        bne.s   .sy_l
        subq.l  #1,a1
sayn:
        movem.l d2-d3/a6,-(sp)
        move.l  a0,d2
        move.l  a1,d3
        sub.l   a0,d3
        move.l  a4,a6
        move.l  d2,-(sp)
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        move.l  (sp)+,d2
        jsr     -48(a6)              ; Write
        movem.l (sp)+,d2-d3/a6
        rts

nw:
        dc.w    20,20,300,120
        dc.b    0,1
        dc.l    $00102000|$00000400|$00000008|$00000100|$00000001|$00000002|$00000080|$00001000|$00000200
        dc.l    $0000100F            ; ACTIVATE | WINDOWCLOSE | WINDOWDEPTH | WINDOWDRAG | WINDOWSIZING
        dc.l    0,0,title,0,0
        dc.w    80,40,640,256
        dc.w    1                    ; WBENCHSCREEN
menu:
        dc.l    0                    ; NextMenu
        dc.w    0,0,60,10            ; LeftEdge, TopEdge, Width, Height
        dc.w    1                    ; MENUENABLED
        dc.l    mname,item
        dc.w    0,0,0,0
item:
        dc.l    0
        dc.w    0,0,80,10
        dc.w    $0052                ; ITEMTEXT | ITEMENABLED | HIGHCOMP
        dc.l    0,itext,0
        dc.b    0,0
        dc.l    0
        dc.w    0
itext:
        dc.b    0,1,1,0              ; FrontPen, BackPen, DrawMode JAM2
        dc.w    2,1
        dc.l    0,iname,0
req:    dcb.b   112,0
reqgad:
        dc.l    0
        dc.w    20,15,80,12          ; LeftEdge, TopEdge, Width, Height
        dc.w    0                    ; Flags: GADGHCOMP
        dc.w    $0005                ; Activation: RELVERIFY | ENDGADGET
        dc.w    $1001                ; GadgetType: BOOLGADGET | REQGADGET
        dc.l    0,0,gtext,0,0
        dc.w    0
        dc.l    0
gtext:
        dc.b    1,0,1,0
        dc.w    4,2
        dc.l    0,gname,0
line0:  dc.b    "IM "
line:   dcb.b   64,0
intname: dc.b    "intuition.library",0
dosname: dc.b    "dos.library",0
title:   dc.b    "IDCMP",0
mname:   dc.b    "Test",0
iname:   dc.b    "Item",0
gname:   dc.b    "OK",0
m_ready: dc.b    "IDCMP READY",10,0
m_end:   dc.b    "IDCMP END",10,0
        even
