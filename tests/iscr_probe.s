; iscr_probe.s - black-box probe of intuition screen management (ANALYSIS TRACK).
; TEST ASSET, NOT ROM code. Authored code; public structures (intuition 1.3: NewScreen,
; Screen, public IntuitionBase; graphics: View, ViewPort, BitMap, ColorMap).
; Two pieces in the same source (same scheme as gdisp_probe.s):
;   - LOADER defined: bootblock that reads BLOBSZ bytes at disk offset 1024 into CHIP and jumps there;
;   - otherwise: the probe body, a position-independent raw binary.
; Output on the serial port (SERDAT, polled), in hexadecimal.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
BLOBSZ   EQU 12288

        IFD LOADER
boot:   movea.l a1,a5
        move.l  #BLOBSZ,d0
        move.l  #$10002,d1              ; MEMF_CHIP|MEMF_CLEAR
        jsr     -198(a6)                ; AllocMem
        tst.l   d0
        beq.s   .ko
        movea.l d0,a4
        move.w  #2,28(a5)               ; CMD_READ
        move.l  #BLOBSZ,36(a5)
        move.l  a4,40(a5)
        move.l  #1024,44(a5)
        movea.l a5,a1
        jsr     -456(a6)                ; DoIO
        jmp     (a4)
.ko:    moveq   #-1,d0
        rts
        ELSE

; ---------------------------------------------------------------- variables (a4 base)
O_EXEC   EQU 0
O_GFX    EQU 4
O_INT    EQU 8
O_S1     EQU 12
O_S2     EQU 16
O_S3     EQU 20
O_WB     EQU 24
O_CBM    EQU 28                         ; user BitMap 40 bytes
O_BUF    EQU 68                         ; GetScreenData buffer 400 bytes
O_END    EQU 468

start:  lea     vars(pc),a4
        move.l  4.w,a6
        move.l  a6,O_EXEC(a4)
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,O_GFX(a4)
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,O_INT(a4)
        movea.l d0,a6                   ; a6 = IntuitionBase for the whole probe
        bsr     reloc
        lea     m_head(pc),a0
        bsr     puts
        move.l  a6,d0
        bsr     hex8
        bsr     nl
        lea     m_t0(pc),a0
        bsr     state

; ----- OpenWorkBench twice
        jsr     -210(a6)
        move.l  d0,O_WB(a4)
        lea     m_owb(pc),a0
        bsr     puts
        bsr     hex8
        jsr     -210(a6)
        bsr     hex8
        bsr     nl
        bsr     wait
        lea     m_t1(pc),a0
        bsr     state
        movea.l O_WB(a4),a0
        bsr     dscr

; ----- S1: lores, Height -1, NS_EXTENDED, LeftEdge 7
        lea     ns1(pc),a0
        jsr     -198(a6)
        move.l  d0,O_S1(a4)
        lea     m_os1(pc),a0
        bsr     puts
        bsr     hex8
        bsr     nl
        bsr     wait
        lea     m_t2(pc),a0
        bsr     state
        movea.l O_S1(a4),a0
        bsr     dscr

; ----- MoveScreen
        movea.l O_S1(a4),a0
        moveq   #50,d0
        moveq   #60,d1
        jsr     -162(a6)
        lea     m_mv1(pc),a0
        bsr     state
        movea.l O_S1(a4),a0
        moveq   #0,d0
        move.l  #-500,d1
        jsr     -162(a6)
        lea     m_mv2(pc),a0
        bsr     state
        movea.l O_S1(a4),a0
        moveq   #0,d0
        move.l  #300,d1
        jsr     -162(a6)
        lea     m_mv3(pc),a0
        bsr     state
        movea.l O_S1(a4),a0
        moveq   #0,d0
        move.l  #-200,d1
        jsr     -162(a6)
        lea     m_mv4(pc),a0
        bsr     state

; ----- depth arrangement
        movea.l O_S1(a4),a0
        jsr     -246(a6)                ; ScreenToBack
        lea     m_stb(pc),a0
        bsr     state
        movea.l O_S1(a4),a0
        jsr     -252(a6)                ; ScreenToFront
        lea     m_stf(pc),a0
        bsr     state
        jsr     -342(a6)                ; WBenchToFront
        lea     m_wtf(pc),a0
        bsr     puts
        bsr     hex8
        bsr     nl
        lea     m_t3(pc),a0
        bsr     state
        jsr     -336(a6)                ; WBenchToBack
        lea     m_wtb(pc),a0
        bsr     puts
        bsr     hex8
        bsr     nl
        lea     m_t4(pc),a0
        bsr     state

; ----- ShowTitle
        movea.l O_S1(a4),a0
        moveq   #0,d0
        jsr     -282(a6)
        lea     m_sh0(pc),a0
        bsr     puts
        bsr     shflags
        movea.l O_S1(a4),a0
        moveq   #1,d0
        jsr     -282(a6)
        lea     m_sh1(pc),a0
        bsr     puts
        bsr     shflags

; ----- S2: hires LACE, Height -1, BEHIND|QUIET, topaz 8 supplied
        lea     ns2(pc),a0
        jsr     -198(a6)
        move.l  d0,O_S2(a4)
        lea     m_os2(pc),a0
        bsr     puts
        bsr     hex8
        bsr     nl
        bsr     wait
        lea     m_t5(pc),a0
        bsr     state
        movea.l O_S2(a4),a0
        bsr     dscr

; ----- S3: CUSTOMBITMAP, font not found, one user gadget
        movea.l O_EXEC(a4),a6
        move.l  #2*40*50,d0
        move.l  #$10002,d1
        jsr     -198(a6)
        move.l  d0,d3
        movea.l O_GFX(a4),a6
        lea     O_CBM(a4),a0
        moveq   #2,d0
        move.l  #320,d1
        moveq   #50,d2
        jsr     -390(a6)                ; InitBitMap
        move.l  d3,O_CBM+8(a4)
        add.l   #40*50,d3
        move.l  d3,O_CBM+12(a4)
        movea.l O_INT(a4),a6
        lea     ns3(pc),a0
        lea     O_CBM(a4),a1
        move.l  a1,28(a0)
        lea     ugad(pc),a1
        move.l  a1,24(a0)
        jsr     -198(a6)
        move.l  d0,O_S3(a4)
        lea     m_os3(pc),a0
        bsr     puts
        bsr     hex8
        bsr     nl
        bsr     wait
        lea     m_t6(pc),a0
        bsr     state
        movea.l O_S3(a4),a0
        bsr     dscr

; ----- GetScreenData / ViewAddress
        lea     O_BUF(a4),a0
        move.l  #400,d0
        moveq   #15,d1
        movea.l O_S3(a4),a1
        jsr     -426(a6)
        lea     m_gsd(pc),a0
        bsr     puts
        bsr     hex8
        lea     O_BUF+346(a4),a0
        move.l  (a0),d0
        bsr     hex8
        lea     O_BUF+8(a4),a0
        move.l  (a0),d0
        bsr     hex8
        lea     O_BUF(a4),a0
        moveq   #20,d0
        moveq   #1,d1
        suba.l  a1,a1
        jsr     -426(a6)
        bsr     hex8
        lea     O_BUF(a4),a0
        moveq   #20,d0
        moveq   #2,d1
        suba.l  a1,a1
        jsr     -426(a6)
        bsr     hex8
        jsr     -294(a6)                ; ViewAddress
        bsr     hex8
        bsr     nl

; ----- closing
        movea.l O_S3(a4),a0
        jsr     -66(a6)
        movea.l O_S2(a4),a0
        jsr     -66(a6)
        movea.l O_S1(a4),a0
        jsr     -66(a6)
        bsr     wait
        lea     m_t7(pc),a0
        bsr     state
        jsr     -78(a6)                 ; CloseWorkBench
        lea     m_cwb(pc),a0
        bsr     puts
        bsr     hex8
        jsr     -78(a6)
        bsr     hex8
        bsr     nl
        bsr     wait
        lea     m_t8(pc),a0
        bsr     state
        lea     O_BUF(a4),a0
        moveq   #20,d0
        moveq   #1,d1
        suba.l  a1,a1
        jsr     -426(a6)
        lea     m_gsw(pc),a0
        bsr     puts
        bsr     hex8
        bsr     nl
        bsr     wait
        lea     m_t9(pc),a0
        bsr     state
        jsr     -78(a6)
        lea     m_cwb(pc),a0
        bsr     puts
        bsr     hex8
        bsr     nl
        lea     ns1(pc),a0
        jsr     -198(a6)
        move.l  d0,O_S1(a4)
        movea.l d0,a0
        jsr     -66(a6)                 ; last screen closed
        bsr     wait
        lea     m_t10(pc),a0
        bsr     state

; ----- final state for the capture: S1 lores 3 planes in front, TopEdge 100
        lea     ns1(pc),a0
        move.w  #100,2(a0)
        jsr     -198(a6)
        move.l  d0,O_S1(a4)
        bsr     wait
        lea     m_t11(pc),a0
        bsr     state
        lea     m_end(pc),a0
        bsr     puts
.fin:   bra.s   .fin

; ---------------------------------------------------------------- absolute pointers to the data
; the blob is loaded at an arbitrary address: the dc.l to labels are set at run time
reloc:  lea     ns1(pc),a1
        lea     t_s1(pc),a0
        move.l  a0,20(a1)
        lea     ns2(pc),a1
        lea     t_s2(pc),a0
        move.l  a0,20(a1)
        lea     ta8(pc),a0
        move.l  a0,16(a1)
        lea     ns3(pc),a1
        lea     t_s3(pc),a0
        move.l  a0,20(a1)
        lea     tabad(pc),a0
        move.l  a0,16(a1)
        lea     topaz(pc),a0
        lea     ta8(pc),a1
        move.l  a0,(a1)
        lea     badf(pc),a0
        lea     tabad(pc),a1
        move.l  a0,(a1)
        rts

; ---------------------------------------------------------------- wait ~0.6 s (intuition deferred work)
wait:   movem.l d0-d2/a0-a1/a6,-(a7)
        movea.l O_GFX(a4),a6
        moveq   #30-1,d2
.w:     jsr     -270(a6)                ; WaitTOF
        dbra    d2,.w
        movem.l (a7)+,d0-d2/a0-a1/a6
        rts

; ---------------------------------------------------------------- IntuitionBase state
; a0 = label
state:  movem.l d0-d2/a0-a2,-(a7)
        bsr     puts
        movea.l a6,a2
        move.l  $3C(a2),d0              ; FirstScreen
        bsr     hex8
        move.l  $38(a2),d0              ; ActiveScreen
        bsr     hex8
        move.l  $34(a2),d0              ; ActiveWindow
        bsr     hex8
        move.l  $40(a2),d0              ; Flags
        bsr     hex8
        lea     m_view(pc),a0
        bsr     puts
        lea     $22(a2),a0              ; View: 9 words
        moveq   #9-1,d1
        bsr     dumpw
        lea     m_lim(pc),a0
        bsr     puts
        lea     $44(a2),a0              ; MouseY MouseX ... up to $58
        moveq   #10-1,d1
        bsr     dumpw
        lea     m_misc(pc),a0
        bsr     puts
        move.w  $378(a2),d0
        bsr     hex4
        move.w  $542(a2),d0
        bsr     hex4
        move.w  $544(a2),d0
        bsr     hex4
        move.w  $546(a2),d0
        bsr     hex4
        bsr     nl
        movea.l $22(a2),a1              ; ViewPort chain
.vp:    move.l  a1,d0
        beq.s   .vpe
        lea     m_vp(pc),a0
        bsr     puts
        bsr     hex8
        move.w  24(a1),d0               ; DWidth
        bsr     hex4
        move.w  26(a1),d0               ; DHeight
        bsr     hex4
        move.w  28(a1),d0               ; DxOffset
        bsr     hex4
        move.w  30(a1),d0               ; DyOffset
        bsr     hex4
        move.w  32(a1),d0               ; Modes
        bsr     hex4
        bsr     nl
        movea.l (a1),a1
        bra.s   .vp
.vpe:   movea.l $3C(a2),a1              ; screen list
.sc:    move.l  a1,d0
        beq.s   .sce
        lea     m_sc(pc),a0
        bsr     puts
        bsr     hex8
        move.w  8(a1),d0
        bsr     hex4
        move.w  10(a1),d0
        bsr     hex4
        move.w  12(a1),d0
        bsr     hex4
        move.w  14(a1),d0
        bsr     hex4
        move.w  20(a1),d0
        bsr     hex4
        bsr     nl
        movea.l (a1),a1
        bra.s   .sc
.sce:   movem.l (a7)+,d0-d2/a0-a2
        rts

shflags: movem.l d0/a0-a1,-(a7)
        movea.l O_S1(a4),a1
        move.w  20(a1),d0
        bsr     hex4
        movea.l $14E(a1),a0
        move.w  $1E(a0),d0              ; Layer.Flags of the BarLayer
        bsr     hex4
        move.l  4(a0),d0                ; Layer.back
        bsr     hex8
        move.l  (a0),d0                 ; Layer.front
        bsr     hex8
        bsr     nl
        movem.l (a7)+,d0/a0-a1
        rts

; ---------------------------------------------------------------- dump of a screen (a0)
dscr:   movem.l d0-d3/a0-a3,-(a7)
        movea.l a0,a2
        move.l  a2,d0
        beq     .x
        lea     m_s0(pc),a0             ; Screen +0..+$2B (22 words)
        bsr     puts
        movea.l a2,a0
        moveq   #22-1,d1
        bsr     dumpw
        lea     m_s1(pc),a0             ; ViewPort +$2C (20 words)
        bsr     puts
        lea     $2C(a2),a0
        moveq   #20-1,d1
        bsr     dumpw
        lea     m_s2(pc),a0             ; RastPort +$54 (50 words)
        bsr     puts
        lea     $54(a2),a0
        moveq   #50-1,d1
        bsr     dumpw
        lea     m_s3(pc),a0             ; BitMap +$B8 (20 words)
        bsr     puts
        lea     $B8(a2),a0
        moveq   #20-1,d1
        bsr     dumpw
        lea     m_s4(pc),a0             ; +$146..+$159 (10 words)
        bsr     puts
        lea     $146(a2),a0
        moveq   #10-1,d1
        bsr     dumpw
        lea     m_s5(pc),a0             ; TextAttr of Screen.Font
        bsr     puts
        movea.l $28(a2),a0
        move.l  a0,d0
        beq.s   .nf
        moveq   #4-1,d1
        bsr     dumpw
.nf:    lea     m_s6(pc),a0             ; RasInfo
        bsr     puts
        movea.l $50(a2),a0
        moveq   #6-1,d1
        bsr     dumpw
        lea     m_s7(pc),a0             ; BarLayer: first 20 words + font of the rp
        bsr     puts
        movea.l $14E(a2),a3
        movea.l a3,a0
        moveq   #20-1,d1
        bsr     dumpw
        movea.l 12(a3),a0
        move.l  52(a0),d0               ; rp_Font
        bsr     hex8
        move.l  $88(a2),d0              ; Screen.RastPort.Font
        bsr     hex8
        movea.l d0,a0
        move.w  20(a0),d0               ; tf_YSize
        bsr     hex4
        bsr     nl
        movea.l $146(a2),a3             ; gadgets
.g:     move.l  a3,d0
        beq.s   .ge
        lea     m_g(pc),a0
        bsr     puts
        bsr     hex8
        movea.l a3,a0
        moveq   #22-1,d1
        bsr     dumpw
        movea.l (a3),a3
        bra.s   .g
.ge:    lea     m_col(pc),a0            ; colours 0..31
        bsr     puts
        movea.l $30(a2),a3              ; vp_ColorMap
        moveq   #0,d3
.c:     movea.l a3,a0
        move.l  d3,d0
        move.l  a6,-(a7)
        movea.l O_GFX(a4),a6
        jsr     -582(a6)                ; GetRGB4
        movea.l (a7)+,a6
        bsr     hex4
        addq.w  #1,d3
        cmp.w   #16,d3
        bne.s   .c2
        bsr     nl
.c2:    cmp.w   #32,d3
        blt.s   .c
        bsr     nl
.x:     movem.l (a7)+,d0-d3/a0-a3
        rts

; ---------------------------------------------------------------- serial output
; a0 = address, d1 = number of words - 1
dumpw:  move.l  d2,-(a7)
        moveq   #0,d2
.w:     move.w  (a0)+,d0
        bsr     hex4
        addq.w  #1,d2
        move.w  d2,d0
        and.w   #15,d0
        bne.s   .n
        bsr     nl
.n:     dbra    d1,.w
        and.w   #15,d2
        beq.s   .e
        bsr     nl
.e:     move.l  (a7)+,d2
        rts

hex8:   movem.l d0-d2,-(a7)
        moveq   #7,d1
        bra.s   hexn
hex4:   movem.l d0-d2,-(a7)
        swap    d0
        moveq   #3,d1
hexn:   rol.l   #4,d0
        move.l  d0,d2
        and.b   #$F,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .o
        addq.b  #7,d0
.o:     bsr.s   putc
        move.l  d2,d0
        dbra    d1,hexn
        moveq   #' ',d0
        bsr.s   putc
        movem.l (a7)+,d0-d2
        tst.l   d0
        rts
nl:     move.l  d0,-(a7)
        moveq   #13,d0
        bsr.s   putc
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
putc:   movem.l d0/d2,-(a7)
        move.w  #$4000,d2
.wt:    btst    #13-8,SERDATR
        bne.s   .tx
        dbra    d2,.wt
.tx:    and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (a7)+,d0/d2
        rts

; ---------------------------------------------------------------- data
        CNOP    0,4
; NewScreen : Left, Top, Width, Height, Depth, DP, BP, ViewModes, Type, Font, DefaultTitle, Gadgets, CustomBitMap
ns1:    dc.w    7,40,320,-1,3
        dc.b    2,3
        dc.w    $0000,$100F
        dc.l    0,0,0,0
ns2:    dc.w    0,20,640,-1,1
        dc.b    0,1
        dc.w    $8004,$018F
        dc.l    0,0,0,0                 ; Font, title: set by reloc
ns3:    dc.w    0,150,320,50,2
        dc.b    1,2
        dc.w    $0000,$004F
        dc.l    0,0,0,0
ta8:    dc.l    0                       ; -> topaz (reloc)
        dc.w    8
        dc.b    0,0
tabad:  dc.l    0                       ; -> badf (reloc)
        dc.w    8
        dc.b    0,0
; boolean user gadget 20x10 at (100,2), no rendering
ugad:   dc.l    0
        dc.w    100,2,20,10,$0003,$0001,$0001
        dc.l    0,0,0,0,0
        dc.w    7
        dc.l    0

topaz:  dc.b    "topaz.font",0
badf:   dc.b    "nonexist.font",0
t_s1:   dc.b    "S1",0
t_s2:   dc.b    "S2",0
t_s3:   dc.b    "S3",0
gfxname: dc.b   "graphics.library",0
intname: dc.b   "intuition.library",0
m_head: dc.b    13,10,"ISCR ibase ",0
m_t0:   dc.b    "== T0 initial FS AS AW FL ",0
m_t1:   dc.b    "== T1 apres OpenWorkBench ",0
m_t2:   dc.b    "== T2 apres S1 ",0
m_t3:   dc.b    "== T3 apres WBenchToFront ",0
m_t4:   dc.b    "== T4 apres WBenchToBack ",0
m_t5:   dc.b    "== T5 apres S2 ",0
m_t6:   dc.b    "== T6 apres S3 ",0
m_t7:   dc.b    "== T7 apres Close S3 S2 S1 ",0
m_t8:   dc.b    "== T8 apres CloseWorkBench ",0
m_t9:   dc.b    "== T9 apres GetScreenData(WB) ",0
m_t10:  dc.b    "== T10 apres Open+Close S1 (dernier) ",0
m_t11:  dc.b    "== T11 final ",0
m_mv1:  dc.b    "== MV +50,+60 ",0
m_mv2:  dc.b    "== MV 0,-500 ",0
m_mv3:  dc.b    "== MV 0,+300 ",0
m_mv4:  dc.b    "== MV 0,-200 ",0
m_stb:  dc.b    "== ScreenToBack S1 ",0
m_stf:  dc.b    "== ScreenToFront S1 ",0
m_owb:  dc.b    "OWB ",0
m_os1:  dc.b    "OS1 ",0
m_os2:  dc.b    "OS2 ",0
m_os3:  dc.b    "OS3 ",0
m_wtf:  dc.b    "WTF ",0
m_wtb:  dc.b    "WTB ",0
m_sh0:  dc.b    "SHOWTITLE0 flags lflags back front ",0
m_sh1:  dc.b    "SHOWTITLE1 flags lflags back front ",0
m_gsd:  dc.b    "GSD custom / buf+346 / buf+8 / wb20 / type2 / ViewAddress ",0
m_cwb:  dc.b    "CWB ",0
m_gsw:  dc.b    "GSD(WB) ",0
m_view: dc.b    13,10," VIEW ",0
m_lim:  dc.b    " MY MX Sec Mic Lim ",0
m_misc: dc.b    " 378 542 544 546 ",0
m_vp:   dc.b    " VP ",0
m_sc:   dc.b    " SC L T W H F ",0
m_s0:   dc.b    "SCR+0",13,10,0
m_s1:   dc.b    "VP",13,10,0
m_s2:   dc.b    "RP",13,10,0
m_s3:   dc.b    "BM",13,10,0
m_s4:   dc.b    "S146",13,10,0
m_s5:   dc.b    "TA ",0
m_s6:   dc.b    "RI ",0
m_s7:   dc.b    "BARLAYER",13,10,0
m_g:    dc.b    "GAD ",0
m_col:  dc.b    "COL",13,10,0
m_end:  dc.b    "END",13,10,0
        CNOP    0,4
vars:   ds.b    O_END
        ENDC
