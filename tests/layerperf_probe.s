; tests/layerperf_probe.s - speed of layer operations over overlapping windows (implementation track, authored).
; On its own 640 x 200, 2-plane screen with three overlapping windows (SMART, SIMPLE, SMART), times in DateStamp
; ticks (1/50 s) and counts the exec AllocMem calls (SetFunction for the duration of each loop) of:
;   "LP MENU <ticks> <allocs> <of 16 bytes or less> <of 17-64 bytes>"   300 x CreateUpfrontLayer(SMART) over the three windows + DeleteLayer, as a menu box;
;   "LP MOVE <ticks> <allocs>"   300 x MoveLayer of the middle window by +6/+4 then back, as a window drag;
; each followed by "LP SCR <plane 0 sum> <plane 1 sum> <layer flags> <damage bounds>" (screen pixels; Flags and
; DamageList bounds of the middle, SIMPLE_REFRESH window's layer: two ROMs must agree), then "LP END". Run by tests/layerperf_probe.sh; compare two ROMs.
; LVOs: AutoDocs offsets (exec SetFunction -420, AllocMem -198; layers CreateUpfrontLayer -36, MoveLayer -60,
; DeleteLayer -90; intuition OpenScreen -198, OpenWindow -204, CloseWindow -72, CloseScreen -66; dos DateStamp -192).

        section code,code
start:
        move.l  ($4).w,a6
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,intb
        beq     .ret
        lea     laysname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,layb
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,dosb
        move.l  intb(pc),a6
        lea     nscreen(pc),a0
        jsr     -198(a6)             ; OpenScreen
        move.l  d0,scr
        beq     .close
        lea     nwins(pc),a2
        lea     wins(pc),a3
        moveq   #3-1,d7
.ow:
        move.l  scr(pc),30(a2)       ; nw_Screen
        move.l  a2,a0
        jsr     -204(a6)             ; OpenWindow
        move.l  d0,(a3)+
        lea     48(a2),a2
        dbra    d7,.ow

        bsr     hook
        bsr     stamp
        move.l  d0,d6
        move.w  #300-1,d7
.menu:
        move.l  layb(pc),a6
        move.l  scr(pc),a0
        lea     184(a0),a1           ; sc_BitMap
        lea     224(a0),a0           ; sc_LayerInfo
        move.l  #100,d0
        moveq   #20,d1
        move.l  #420,d2
        move.l  #150,d3
        moveq   #2,d4                ; LAYERSMART
        suba.l  a2,a2
        jsr     -36(a6)              ; CreateUpfrontLayer
        tst.l   d0
        beq.s   .mnext
        move.l  d0,a1
        suba.l  a0,a0
        jsr     -90(a6)              ; DeleteLayer
.mnext:
        dbra    d7,.menu
        bsr     stamp
        sub.l   d6,d0
        lea     m_menu(pc),a0
        bsr     report
        bsr     scrsum

        bsr     hook
        bsr     stamp
        move.l  d0,d6
        move.w  #300-1,d7
.move:
        move.l  layb(pc),a6
        move.l  wins+4(pc),a1
        move.l  124(a1),a1           ; wd_WLayer
        suba.l  a0,a0
        moveq   #6,d0
        moveq   #4,d1
        btst    #0,d7
        beq.s   .mv
        moveq   #-6,d0
        moveq   #-4,d1
.mv:
        jsr     -60(a6)              ; MoveLayer
        dbra    d7,.move
        bsr     stamp
        sub.l   d6,d0
        lea     m_move(pc),a0
        bsr     report
        bsr     scrsum

        move.l  intb(pc),a6
        lea     wins(pc),a3
        moveq   #3-1,d7
.cw:
        move.l  (a3)+,a0
        jsr     -72(a6)              ; CloseWindow
        dbra    d7,.cw
        move.l  scr(pc),a0
        jsr     -66(a6)              ; CloseScreen
.close:
        lea     m_end(pc),a0
        bsr     puts
.ret:
        moveq   #0,d0
        rts

; scrsum: "LP SCR" line (see the header).
scrsum:
        lea     m_scr(pc),a0
        bsr     puts
        move.l  scr(pc),a1
        lea     184(a1),a1           ; sc_BitMap
        moveq   #2-1,d3
        moveq   #0,d4
.ss_pl:
        move.l  8(a1,d4.w),a0        ; bm_Planes
        moveq   #0,d0
        move.w  #80*200/4-1,d1
.ss_l:
        rol.l   #3,d0
        add.l   (a0)+,d0
        dbra    d1,.ss_l
        bsr     phex8
        addq.w  #4,d4
        dbra    d3,.ss_pl
        move.l  wins+4(pc),a1
        move.l  124(a1),a1           ; wd_WLayer
        moveq   #0,d0
        move.w  30(a1),d0            ; lr_Flags
        bsr     phex8
        move.l  156(a1),a0           ; lr_DamageList
        move.l  (a0),d0              ; bounds MinX/MinY
        bsr     phex8
        move.l  4(a0),d0             ; MaxX/MaxY
        bsr     phex8
        bra     nl

; hook: AllocMem counted through SetFunction (counter cleared; the first call installs the patch).
hook:
        clr.l   nalloc
        clr.l   nsmall
        clr.l   nmid
        tst.l   oldalloc
        bne.s   .h_r
        move.l  ($4).w,a6
        move.l  a6,a1
        move.w  #-198,a0
        move.l  #counter,d0
        jsr     -420(a6)             ; SetFunction
        move.l  d0,oldalloc
.h_r:
        rts
counter:
        addq.l  #1,nalloc
        cmp.l   #16,d0
        bhi.s   .c_mid
        addq.l  #1,nsmall
        bra.s   .c_go
.c_mid:
        cmp.l   #64,d0
        bhi.s   .c_go
        addq.l  #1,nmid
.c_go:
        move.l  oldalloc(pc),-(sp)
        rts

; report(a0 = label, d0 = ticks): "<label> <ticks> <allocs>", then the old AllocMem back.
report:
        move.l  a0,-(sp)
        move.l  d0,-(sp)
        move.l  ($4).w,a6
        move.l  a6,a1
        move.w  #-198,a0
        move.l  oldalloc(pc),d0
        jsr     -420(a6)
        clr.l   oldalloc
        move.l  (sp)+,d0
        move.l  (sp)+,a0
        move.l  nalloc(pc),-(sp)
        move.l  d0,-(sp)
        bsr     puts
        move.l  (sp)+,d0
        bsr     phex8
        move.l  (sp)+,d0
        bsr     phex8
        move.l  nsmall(pc),d0
        bsr     phex8
        move.l  nmid(pc),d0
        bsr     phex8
        bra     nl

; stamp -> d0 = minutes * 3000 + ticks
stamp:
        movem.l d1-d3/a0-a1/a6,-(sp)
        move.l  dosb(pc),a6
        move.l  #dstamp,d1
        jsr     -192(a6)
        move.l  dstamp+4(pc),d0
        mulu.w  #3000,d0
        add.l   dstamp+8(pc),d0
        movem.l (sp)+,d1-d3/a0-a1/a6
        rts

puts:
        move.l  d1,-(sp)
.p:     move.b  (a0)+,d1
        beq.s   .pr
        bsr.s   putc
        bra.s   .p
.pr:    move.l  (sp)+,d1
        rts
nl:     moveq   #10,d1
        bra.s   putc
phex8:
        movem.l d0-d2,-(sp)
        moveq   #' ',d1
        bsr.s   putc
        moveq   #7,d2
.h:     rol.l   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        move.b  digits(pc,d1.w),d1
        bsr.s   putc
        dbra    d2,.h
        movem.l (sp)+,d0-d2
        rts
digits: dc.b    "0123456789ABCDEF"
putc:
        move.w  d0,-(sp)
.w:     move.w  $DFF018,d0           ; SERDATR: wait for TBE
        btst    #13,d0
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1             ; stop bit
        move.w  d1,$DFF030           ; SERDAT
        move.w  (sp)+,d0
        rts

        cnop    0,4
intb:     dc.l  0
layb:     dc.l  0
dosb:     dc.l  0
scr:      dc.l  0
wins:     dc.l  0,0,0
nalloc:   dc.l  0
nsmall:   dc.l  0
nmid:     dc.l  0
oldalloc: dc.l  0
dstamp:   dc.l  0,0,0
nscreen:  dc.w  0,0,640,200,2
          dc.b  0,1
          dc.w  $8000,15             ; HIRES, CUSTOMSCREEN
          dc.l  0,0,0,0
nwins:    dc.w  40,30,300,120        ; SMART
          dc.b  0,1
          dc.l  0,$100E,0,0,0,0,0    ; flags: DRAG|DEPTH|SIZE|ACTIVATE... (SMART_REFRESH = 0)
          dc.w  50,30,640,200,15
          dc.w  200,60,300,120       ; SIMPLE_REFRESH
          dc.b  0,1
          dc.l  0,$104E,0,0,0,0,0
          dc.w  50,30,640,200,15
          dc.w  360,40,260,140       ; SMART
          dc.b  0,1
          dc.l  0,$100E,0,0,0,0,0
          dc.w  50,30,640,200,15
intname:  dc.b  "intuition.library",0
laysname: dc.b  "layers.library",0
dosname:  dc.b  "dos.library",0
m_menu:   dc.b  "LP MENU",0
m_move:   dc.b  "LP MOVE",0
m_end:    dc.b  "LP END",10,0
m_scr:    dc.b  "LP SCR",0
