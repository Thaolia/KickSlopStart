; src/intuition/sysreq.s - intuition.library: system requester (spec intuition-requesters-v34 §5).
; BuildSysRequest opens at (0,0), on the screen of the given window (failing that the Workbench screen), a "System
; Request" window (or one with that window's title) and puts up in it, via Request, a NOISYREQ requester over its whole
; interior: background in pen 1, frame, body, positive gadget (bottom left, ID 1) and negative gadget (bottom right,
; ID 0). All the memory is in a Remember list stored in Window->UserData; FreeSysRequest removes the requester, frees
; it and closes the window. AutoRequest is built on top of it.
; Deviation: without a window or requester (memory), no DisplayAlert fallback: FALSE.
; IMPLEMENTATION track ("clean"): AutoDocs intuition AutoRequest / BuildSysRequest / FreeSysRequest + public
; structures + spec. NO ROM reading.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xdef    intuition_AutoRequest
                xdef    intuition_BuildSysRequest
                xdef    intuition_FreeSysRequest
                xref    intuition_OpenWindow
                xref    intuition_CloseWindow
                xref    intuition_IntuiTextLength
                xref    intuition_AllocRemember
                xref    intuition_FreeRemember
                xref    intuition_Request
                xref    intuition_EndRequest
                xref    intuition_ScreenToFront

SR_SIMPLE       EQU $0040            ; NewWindow: SIMPLE_REFRESH
SR_NOCARE       EQU $00020000        ; NOCAREREFRESH
SR_FLAGS        EQU SR_NOCARE|ACTIVATE|SR_SIMPLE|WINDOWDEPTH|WINDOWDRAG|WINDOWSIZING
SR_LCOMMAND     EQU $40              ; qualifier: left Amiga
SR_KEYV         EQU $34              ; Amiga-V: positive
SR_KEYB         EQU $35              ; Amiga-B: negative

; allocated block: 2 gadgets, 5 borders (Border + 9 points), the NewWindow, the Requester
SR_BDSZ         EQU 16+9*4
SR_GADP         EQU 0
SR_GADN         EQU SR_GADP+GG_SIZEOF
SR_BREQ         EQU SR_GADN+GG_SIZEOF ; requester border
SR_BP           EQU SR_BREQ+SR_BDSZ  ; positive gadget: inner rule then outer border
SR_BN           EQU SR_BP+2*SR_BDSZ
SR_NW           EQU SR_BN+2*SR_BDSZ
SR_NWSIZE       EQU 48               ; struct NewWindow
SR_REQ          EQU SR_NW+SR_NWSIZE
SR_SIZE         EQU SR_REQ+RQ_SIZEOF

; AutoRequest(window a0, body a1, positive a2, negative a3, posFlags d0, negFlags d1, width d2, height d3)
; -> d0 = TRUE (positive gadget, Amiga-V or IDCMP event from posFlags) / FALSE (negative, Amiga-B, negFlags, or
; failure). Without positive text, only the negative gadget exists; Amiga-V then has no effect.
intuition_AutoRequest:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a6,a5                ; a5 = IntuitionBase
        move.l  a2,d6                ; d6 = positive text | 0
        move.l  d0,d4                ; d4 = positive flags
        move.l  d1,d5                ; d5 = negative flags
        or.l    d1,d0
        or.l    #GADGETUP|RAWKEY,d0
        bsr     intuition_BuildSysRequest
        cmp.l   #1,d0                ; 0 / 1: no window, direct answer
        bls     .ar_ret
        move.l  d0,a3                ; a3 = requester window
        move.l  WD_WSCREEN(a3),a0    ; its screen to the front if it is not already
        cmp.l   IB_FIRSTSCREEN(a5),a0
        beq.s   .ar_front
        move.l  a5,a6
        jsr     intuition_ScreenToFront
.ar_front:
        move.l  ($4).w,a6
.ar_wait:
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_WAITPORT(a6)
.ar_get:
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .ar_wait
        move.l  d0,a1
        move.l  IM_CLASS(a1),d0
        moveq   #-1,d2               ; d2 = answer (-1: not yet)
        move.l  d0,d1
        and.l   d5,d1
        beq.s   .ar_pos
        moveq   #0,d2
        bra.s   .ar_reply
.ar_pos:
        move.l  d0,d1
        and.l   d4,d1
        beq.s   .ar_gad
        moveq   #1,d2
        bra.s   .ar_reply
.ar_gad:
        cmp.l   #GADGETUP,d0
        bne.s   .ar_key
        move.l  IM_IADDRESS(a1),a0
        moveq   #0,d2
        tst.w   GG_GADGETID(a0)
        beq.s   .ar_reply
        moveq   #1,d2
        bra.s   .ar_reply
.ar_key:
        cmp.l   #RAWKEY,d0
        bne.s   .ar_reply
        btst    #6,IM_QUALIFIER+1(a1) ; left Amiga
        beq.s   .ar_reply
        cmp.w   #SR_KEYB,IM_CODE(a1)
        bne.s   .ar_kv
        moveq   #0,d2
        bra.s   .ar_reply
.ar_kv:
        cmp.w   #SR_KEYV,IM_CODE(a1)
        bne.s   .ar_reply
        tst.l   d6                   ; only if there is a positive gadget
        beq.s   .ar_reply
        moveq   #1,d2
.ar_reply:
        jsr     LVO_REPLYMSG(a6)
        tst.l   d2
        bmi.s   .ar_get
        move.l  a3,a0
        move.l  a5,a6
        bsr     intuition_FreeSysRequest
        move.l  d2,d0
.ar_ret:
        move.l  a5,a6
        movem.l (sp)+,d2-d7/a2-a5
        rts

; BuildSysRequest(window a0, body a1, positive a2, negative a3, IDCMP d0, width d2, height d3) -> d0 = requester
; window, or 0 (memory, window or requester impossible).
intuition_BuildSysRequest:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a6,a5                ; a5 = IntuitionBase
        move.l  a0,d7                ; d7 = reference window | 0
        move.l  a1,d6                ; d6 = body
        move.l  d0,d4                ; d4 = IDCMP
        movem.w d2-d3,-(sp)          ; 4(sp) = width, 6(sp) = height (after the key)
        clr.l   -(sp)                ; (sp) = key of the Remember list
        move.l  sp,a0
        move.l  #SR_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     intuition_AllocRemember
        tst.l   d0
        beq     .bs_fail
        move.l  d0,a4                ; a4 = block
        move.l  a2,SR_GADP+GG_GADGETTEXT(a4)
        move.l  a3,SR_GADN+GG_GADGETTEXT(a4)
        lea     SR_NW(a4),a0
        move.w  4(sp),NW_WIDTH(a0)
        move.w  6(sp),NW_HEIGHT(a0)
        move.w  4(sp),NW_MAXWIDTH(a0)
        move.w  6(sp),NW_MAXHEIGHT(a0)
        move.w  #88,NW_MINWIDTH(a0)
        move.w  #24,NW_MINHEIGHT(a0)
        move.w  #$FFFF,NW_DETAILPEN(a0) ; screen pens
        move.l  d4,NW_IDCMPFLAGS(a0)
        move.l  #SR_FLAGS,NW_FLAGS(a0)
        lea     sr_title(pc),a1
        move.l  a1,NW_TITLE(a0)
        move.w  #WBENCHSCREEN,NW_TYPE(a0)
        tst.l   d7
        beq.s   .bs_open
        move.l  d7,a1
        move.b  WD_DETAILPEN(a1),NW_DETAILPEN(a0)
        move.b  WD_BLOCKPEN(a1),NW_BLOCKPEN(a0)
        tst.l   WD_TITLE(a1)
        beq.s   .bs_scr
        move.l  WD_TITLE(a1),NW_TITLE(a0)
.bs_scr:
        move.l  WD_WSCREEN(a1),a1
        move.l  a1,NW_SCREEN(a0)
        move.w  SC_FLAGS(a1),d0
        and.w   #$0F,d0
        move.w  d0,NW_TYPE(a0)
.bs_open:
        jsr     intuition_OpenWindow
        tst.l   d0
        beq     .bs_free
        move.l  d0,a3                ; a3 = requester window
        lea     SR_REQ(a4),a2        ; requester (block zeroed: InitRequester unnecessary) over the interior
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        move.w  d0,RQ_LEFTEDGE(a2)
        move.w  4(sp),d2
        sub.w   d0,d2
        move.b  WD_BORDERRIGHT(a3),d0
        sub.w   d0,d2
        move.w  d2,RQ_WIDTH(a2)
        move.b  WD_BORDERTOP(a3),d0
        move.w  d0,RQ_TOPEDGE(a2)
        move.w  6(sp),d3
        sub.w   d0,d3
        move.b  WD_BORDERBOTTOM(a3),d0
        sub.w   d0,d3
        move.w  d3,RQ_HEIGHT(a2)
        move.b  #1,RQ_BACKFILL(a2)
        move.w  #NOISYREQ,RQ_FLAGS(a2)
        move.l  d6,RQ_REQTEXT(a2)
        lea     SR_BREQ(a4),a0
        move.l  a0,RQ_REQBORDER(a2)
        move.w  d2,d0
        move.w  d3,d1
        moveq   #1,d2
        moveq   #0,d3
        bsr     sr_frame             ; requester border: inset 1, pen 0
        move.l  a5,a6
        lea     SR_GADN(a4),a0       ; negative: 13 pixels from the right edge, ID 0
        lea     SR_BN(a4),a1
        bsr     sr_mkgad
        or.w    #GRELRIGHT,GG_FLAGS(a0)
        move.w  GG_WIDTH(a0),d0
        add.w   #13,d0
        neg.w   d0
        move.w  d0,GG_LEFTEDGE(a0)
        move.l  a0,RQ_REQGADGET(a2)
        tst.l   SR_GADP+GG_GADGETTEXT(a4)
        beq.s   .bs_req
        lea     SR_GADP(a4),a0       ; positive: 14 pixels from the left edge, ID 1, at the head of the list
        lea     SR_BP(a4),a1
        bsr     sr_mkgad
        move.w  #14,GG_LEFTEDGE(a0)
        move.w  #1,GG_GADGETID(a0)
        move.l  RQ_REQGADGET(a2),GG_NEXTGADGET(a0)
        move.l  a0,RQ_REQGADGET(a2)
.bs_req:
        move.l  a2,a0
        move.l  a3,a1
        jsr     intuition_Request
        tst.l   d0
        bne.s   .bs_ok
        move.l  a3,a0
        jsr     intuition_CloseWindow
.bs_free:
        move.l  sp,a0
        moveq   #-1,d0
        jsr     intuition_FreeRemember
.bs_fail:
        moveq   #0,d0
        bra.s   .bs_ret
.bs_ok:
        move.l  (sp),WD_USERDATA(a3) ; the Remember list, for FreeSysRequest
        move.l  a3,d0
.bs_ret:
        addq.l  #8,sp
        move.l  a5,a6
        movem.l (sp)+,d2-d7/a2-a5
        rts

; FreeSysRequest(window a0): its requester removed, its Remember list (Window->UserData) freed, window closed.
intuition_FreeSysRequest:
        movem.l a3/a5,-(sp)
        move.l  a6,a5
        move.l  a0,d0
        beq.s   .fs_ret
        move.l  a0,a3
        move.l  WD_FIRSTREQUEST(a3),d0
        beq.s   .fs_mem
        move.l  d0,a0
        move.l  a3,a1
        jsr     intuition_EndRequest
.fs_mem:
        lea     WD_USERDATA(a3),a0
        moveq   #-1,d0
        move.l  a5,a6
        jsr     intuition_FreeRemember
        move.l  a3,a0
        move.l  a5,a6
        jsr     intuition_CloseWindow
.fs_ret:
        move.l  a5,a6
        movem.l (sp)+,a3/a5
        rts

; sr_mkgad(a0 = gadget (text already set), a1 = its two borders, a3 = window, a6 = IntuitionBase): requester boolean
; button, release-verified, width = text (first IntuiText) + 12, height = font + 6, 4 pixels above the bottom
; of the domain; rendering = inner rule (pen 0) then a one-pixel outer border (pen 3), highlight by
; complement. Preserves a0/a2-a6.
sr_mkgad:
        movem.l d2-d3/a0-a2,-(sp)
        move.l  a0,a2
        move.w  #REQGADGET|BOOLGADGET,GG_GADGETTYPE(a2)
        move.w  #$0100|RELVERIFY,GG_ACTIVATION(a2)
        move.w  #GRELBOTTOM,GG_FLAGS(a2)
        move.l  a1,GG_GADGETRENDER(a2)
        moveq   #12,d2               ; width
        move.l  WD_WSCREEN(a3),a0
        move.w  SC_RASTPORT+rp_TxHeight(a0),d3
        move.l  GG_GADGETTEXT(a2),d0
        beq.s   .mg_size
        move.l  d0,a0
        move.l  IT_ITEXTFONT(a0),d1
        beq.s   .mg_w
        move.l  d1,a1
        move.w  ta_YSize(a1),d3
.mg_w:
        jsr     intuition_IntuiTextLength
        add.w   d0,d2
.mg_size:
        addq.w  #6,d3                ; height
        move.w  d2,GG_WIDTH(a2)
        move.w  d3,GG_HEIGHT(a2)
        move.w  d3,d0
        addq.w  #4,d0
        neg.w   d0
        move.w  d0,GG_TOPEDGE(a2)
        move.l  GG_GADGETRENDER(a2),a0
        move.w  d2,d0
        move.w  d3,d1
        moveq   #1,d2
        moveq   #0,d3
        bsr.s   sr_frame             ; inner rule, pen 0 (drawn first)
        lea     SR_BDSZ(a0),a1
        move.l  a1,BD_NEXTBORDER(a0)
        move.l  a1,a0
        move.w  GG_WIDTH(a2),d0
        move.w  GG_HEIGHT(a2),d1
        moveq   #-1,d2
        moveq   #3,d3
        bsr.s   sr_frame             ; one-pixel outer border, pen 3
        movem.l (sp)+,d2-d3/a0-a2
        rts

; sr_frame(a0 = Border followed by 9 points, d0.w/d1.w = width/height, d2.w = inset, d3.b = pen): rectangle
; inset by d2 with two-pixel vertical sides, JAM1, Count 9, without a next Border. Clobbers d0-d3;
; preserves a0/a1.
sr_frame:
        move.l  a1,-(sp)
        clr.l   BD_LEFTEDGE(a0)
        move.b  d3,BD_FRONTPEN(a0)
        clr.b   BD_FRONTPEN+1(a0)
        move.b  #JAM1,BD_DRAWMODE(a0)
        move.b  #9,BD_COUNT(a0)
        clr.l   BD_NEXTBORDER(a0)
        lea     16(a0),a1
        move.l  a1,BD_XY(a0)
        subq.w  #1,d0                ; d0 = width - 1 - inset, d1 = height - 1 - inset
        sub.w   d2,d0
        subq.w  #1,d1
        sub.w   d2,d1
        move.w  d2,(a1)+             ; (r,r)
        move.w  d2,(a1)+
        move.w  d0,(a1)+             ; (W'-r,r)
        move.w  d2,(a1)+
        move.w  d0,(a1)+             ; (W'-r,H'-r)
        move.w  d1,(a1)+
        move.w  d2,(a1)+             ; (r,H'-r)
        move.w  d1,(a1)+
        move.w  d2,(a1)+             ; (r,r)
        move.w  d2,(a1)+
        move.w  d2,d3
        addq.w  #1,d3                ; d3 = s = r + 1
        move.w  d3,(a1)+             ; (s,r)
        move.w  d2,(a1)+
        move.w  d3,(a1)+             ; (s,H'-r)
        move.w  d1,(a1)+
        subq.w  #1,d0                ; d0 = W'-s
        move.w  d0,(a1)+             ; (W'-s,H'-r)
        move.w  d1,(a1)+
        move.w  d0,(a1)+             ; (W'-s,r)
        move.w  d2,(a1)+
        move.l  (sp)+,a1
        rts

sr_title:
        dc.b    "System Request",0
        even
