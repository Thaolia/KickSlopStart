; tests/lineclip_probe.s - clipped line pieces drawn by the CPU (implementation track, authored).
; Opens a CUSTOMSCREEN|SCREENQUIET 640 x 200 hires 2-plane screen, a borderless window W1 (400 x 150) and two
; windows W2/W3 over parts of it, so W1 has visible and backed-up ClipRects. Draws 5 x 200 pseudo-random lines in W1
; whose ends lie up to 60 pixels outside it, in five modes: JAM1 pattern $F3C9, JAM2 pattern $AAAA, COMPLEMENT
; pattern $FF00, COMPLEMENT solid with ONE_DOT, JAM1 pattern $FFF0 with ONE_DOT. Closes W3 and W2 (W1 repaired from
; its backup) and prints on the serial line:
;   "LC TICKS <ticks>"      DateStamp ticks spent drawing the lines (50 per second)
;   "LC CKS <p0> <p1>"      fingerprint of each screen plane
;   "LC END"
; Two ROMs that draw lines the same way print the same fingerprints. Run by tests/lineclip_probe.sh as a CLI command
; from a startup-sequence. Public structures (NewScreen, NewWindow, Screen, Window, RastPort, BitMap).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

LVO_OpenLibrary  EQU -552
LVO_CloseLibrary EQU -414
LVO_OpenScreen   EQU -198
LVO_CloseScreen  EQU -66
LVO_OpenWindow   EQU -204
LVO_CloseWindow  EQU -72
LVO_Move         EQU -240
LVO_Draw         EQU -246
LVO_SetAPen      EQU -342
LVO_SetBPen      EQU -348
LVO_SetDrMd      EQU -354
LVO_DateStamp    EQU -192
wd_RPort         EQU 50
sc_RastPort      EQU 84
rp_BitMap        EQU 4
rp_linpatcnt     EQU 30
rp_Flags         EQU 32
rp_LinePtrn      EQU 34
FRST_DOT         EQU 1
ONE_DOT          EQU 2
NLINES           EQU 200

                section code,code
start:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  4.w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a4                ; a4 = IntuitionBase
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5                ; a5 = GfxBase
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        lea     dosbase(pc),a0
        move.l  d0,(a0)
        lea     m_begin(pc),a0
        bsr     puts
        move.l  a4,a6
        lea     ns(pc),a0
        jsr     LVO_OpenScreen(a6)
        lea     scr(pc),a0
        move.l  d0,(a0)
        beq     .end
        lea     nw1(pc),a0
        move.l  d0,30(a0)
        lea     nw2(pc),a0
        move.l  d0,30(a0)
        lea     nw3(pc),a0
        move.l  d0,30(a0)
        lea     nw1(pc),a0
        jsr     LVO_OpenWindow(a6)
        move.l  d0,d7                ; d7 = W1
        beq     .cs
        lea     nw2(pc),a0
        jsr     LVO_OpenWindow(a6)
        lea     w2(pc),a0
        move.l  d0,(a0)
        lea     nw3(pc),a0
        jsr     LVO_OpenWindow(a6)
        lea     w3(pc),a0
        move.l  d0,(a0)
        move.l  d7,a0
        move.l  wd_RPort(a0),a3      ; a3 = W1 RastPort
        lea     ds0(pc),a0
        bsr     stamp
        lea     modes(pc),a2
.mode:
        move.w  (a2)+,d0             ; draw mode, A pen, B pen, LinePtrn, Flags bits
        bmi.s   .drawn
        move.l  a5,a6
        move.l  a3,a1
        jsr     LVO_SetDrMd(a6)
        move.l  a3,a1
        move.w  (a2)+,d0
        jsr     LVO_SetAPen(a6)
        move.l  a3,a1
        move.w  (a2)+,d0
        jsr     LVO_SetBPen(a6)
        move.w  (a2)+,rp_LinePtrn(a3)
        move.b  #15,rp_linpatcnt(a3)
        move.w  rp_Flags(a3),d0
        and.w   #~(FRST_DOT|ONE_DOT),d0
        or.w    (a2)+,d0
        move.w  d0,rp_Flags(a3)
        move.w  #NLINES-1,d6
.line:
        bsr     rx
        move.w  d0,d4
        bsr     ry
        move.w  d0,d5
        move.l  a3,a1
        move.w  d4,d0
        move.w  d5,d1
        jsr     LVO_Move(a6)
        bsr     rx
        move.w  d0,d4
        bsr     ry
        move.w  d0,d1
        move.w  d4,d0
        move.l  a3,a1
        jsr     LVO_Draw(a6)
        dbra    d6,.line
        bra.s   .mode
.drawn:
        lea     ds1(pc),a0
        bsr     stamp
        lea     m_ticks(pc),a0
        bsr     puts
        move.l  ds1(pc),d0           ; (days1 - days0) * 4320000 + (min1 - min0) * 3000 + tick1 - tick0
        sub.l   ds0(pc),d0
        mulu    #3000,d0             ; the run never spans a day boundary in practice; minutes fit a word
        move.l  ds1+4(pc),d1
        sub.l   ds0+4(pc),d1
        mulu    #3000,d1
        add.l   d1,d0
        add.l   ds1+8(pc),d0
        sub.l   ds0+8(pc),d0
        bsr     phex8
        bsr     nl
        move.l  a4,a6
        move.l  w3(pc),d0
        beq.s   .n3
        move.l  d0,a0
        jsr     LVO_CloseWindow(a6)
.n3:
        move.l  w2(pc),d0
        beq.s   .n2
        move.l  d0,a0
        jsr     LVO_CloseWindow(a6)
.n2:
        lea     m_cks(pc),a0
        bsr     puts
        move.l  scr(pc),a0
        move.l  sc_RastPort+rp_BitMap(a0),a0
        moveq   #1,d2
        lea     8(a0),a1             ; bm_Planes
.pl:
        move.l  (a1)+,a0
        move.w  #640/8*200/4-1,d1
        moveq   #0,d0
.ck:
        rol.l   #5,d0
        add.l   (a0)+,d0
        dbra    d1,.ck
        bsr     phex8
        dbra    d2,.pl
        bsr     nl
        move.l  d7,a0
        jsr     LVO_CloseWindow(a6)
.cs:
        move.l  scr(pc),a0
        jsr     LVO_CloseScreen(a6)
.end:
        lea     m_end(pc),a0
        bsr     puts
        move.l  4.w,a6
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
        move.l  a4,a1
        jsr     LVO_CloseLibrary(a6)
        move.l  dosbase(pc),a1
        jsr     LVO_CloseLibrary(a6)
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts

; stamp(a0 = DateStamp buffer). Keeps a6 = GfxBase.
stamp:
        move.l  a6,-(sp)
        move.l  a0,d1
        move.l  dosbase(pc),a6
        jsr     LVO_DateStamp(a6)
        move.l  (sp)+,a6
        rts
; rx / ry -> d0.w = pseudo-random x in [-60, 460) / y in [-40, 190) (W1 coordinates). Clobbers d1.
rx:
        bsr.s   rnd
        divu    #520,d0
        swap    d0
        sub.w   #60,d0
        rts
ry:
        bsr.s   rnd
        divu    #230,d0
        swap    d0
        sub.w   #40,d0
        rts
; rnd -> d0.l = next 16-bit value of a linear congruential generator, zero-extended.
rnd:
        lea     seed(pc),a0
        move.w  (a0),d0
        mulu    #25173,d0
        add.w   #13849,d0
        move.w  d0,(a0)
        and.l   #$FFFF,d0
        rts

puts:
        move.b  (a0)+,d1
        beq.s   .r
        bsr.s   putc
        bra.s   puts
.r:     rts
nl:     moveq   #10,d1
        bra.s   putc
; phex8(d0.l): " XXXXXXXX"
phex8:
        movem.l d0/d2,-(sp)
        moveq   #' ',d1
        bsr.s   putc
        moveq   #7,d2
.h:     rol.l   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        add.b   #'0',d1
        cmp.b   #'9',d1
        bls.s   .o
        addq.b  #7,d1
.o:     bsr.s   putc
        dbra    d2,.h
        movem.l (sp)+,d0/d2
        rts
putc:
        move.w  d0,-(sp)
.w:     move.w  SERDATR,d0
        btst    #13,d0
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        move.w  (sp)+,d0
        rts

; per mode: DrawMode (JAM1 0, JAM2 1, COMPLEMENT 2), APen, BPen, LinePtrn, rp_Flags bits; -1 ends
modes:  dc.w    0,1,0,$F3C9,FRST_DOT
        dc.w    1,2,1,$AAAA,FRST_DOT
        dc.w    2,1,0,$FF00,FRST_DOT
        dc.w    2,3,0,$FFFF,ONE_DOT
        dc.w    0,3,0,$FFF0,ONE_DOT|FRST_DOT
        dc.w    -1
; struct NewScreen: Left, Top, Width, Height, Depth, Detail, Block, ViewModes, Type, Font, Title, Gadgets, BitMap
ns:     dc.w    0,0,640,200,2
        dc.b    0,1
        dc.w    $8000,$010f          ; HIRES; CUSTOMSCREEN|SCREENQUIET
        dc.l    0,0,0,0
; struct NewWindow: Left, Top, Width, Height, Detail, Block, IDCMP, Flags, FirstGadget, CheckMark, Title, Screen,
; BitMap, MinW, MinH, MaxW, MaxH, Type (CUSTOMSCREEN = $000f)
nw1:    dc.w    100,20,400,150
        dc.b    0,1
        dc.l    0,$0800              ; BORDERLESS
        dc.l    0,0,0,0,0
        dc.w    0,0,0,0,$000f
nw2:    dc.w    420,110,120,60
        dc.b    0,1
        dc.l    0,$0800
        dc.l    0,0,0,0,0
        dc.w    0,0,0,0,$000f
nw3:    dc.w    180,50,90,70
        dc.b    0,1
        dc.l    0,$0800
        dc.l    0,0,0,0,0
        dc.w    0,0,0,0,$000f
                cnop    0,4
scr:    dc.l    0
w2:     dc.l    0
w3:     dc.l    0
dosbase: dc.l   0
ds0:    ds.l    3
ds1:    ds.l    3
seed:   dc.w    $1234

intname:  dc.b  "intuition.library",0
gfxname:  dc.b  "graphics.library",0
dosname:  dc.b  "dos.library",0
m_begin:  dc.b  "LC BEGIN",10,0
m_ticks:  dc.b  "LC TICKS",0
m_cks:    dc.b  "LC CKS",0
m_end:    dc.b  "LC END",10,0
                even
