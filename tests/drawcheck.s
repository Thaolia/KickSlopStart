; tests/drawcheck.s - HUNK test executable (TEST ASSET, NOT ROM code): fingerprint of the pixels produced by
; Draw, RectFill (solid and patterned), SetRast, ClearEOL, ClearScreen, Text and
; BltTemplate. Serves as a non-regression check when these primitives
; change implementation: two ROMs that draw the same way write the same file.
; Run "drawcheck >df0:dc.out". Assemble with -kick1hunks.
; CUSTOMSCREEN|SCREENQUIET 640x200 HIRES 2-plane screen. SCREEN part: each test starts from planes cleared by
; the CPU, then "Tn s0 s1" = fingerprint of each plane. WINDOW part: the same tests, cumulative, in a
; BORDERLESS window partly covered by a second one (hidden ClipRects with backing save); after each test,
; a fingerprint of the screen, and a last one after closing the second window (the hidden part reappears).
; Clean-room: public structures (NewScreen, NewWindow, Screen, Window, RastPort, BitMap), authored code.

RP_AREAPTRN     EQU 8
RP_MASK         EQU 24
RP_AREAPTSZ     EQU 29

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     line(pc),a4
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                move.l  d0,dosbase
                beq     .ret
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,gfxbase
                beq     .ret
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,intbase
                beq     .ret
                move.l  d0,a6
                lea     ns(pc),a0
                jsr     -198(a6)             ; OpenScreen
                move.l  d0,scr
                beq     .ret
                lea     nw1(pc),a0
                move.l  d0,30(a0)
                lea     nw2(pc),a0
                move.l  d0,30(a0)
                ; --- screen ---
                move.l  scr(pc),a0
                lea     84(a0),a2            ; Screen.RastPort
                lea     s_scr(pc),a0
                bsr     ps
                bsr     nl
                moveq   #1,d7                ; clear before each test
                bsr     tests
                ; --- covered window ---
                move.l  scr(pc),a0
                lea     84(a0),a2
                bsr     clear
                move.l  intbase(pc),a6
                lea     nw1(pc),a0
                jsr     -204(a6)             ; OpenWindow
                move.l  d0,win1
                beq     .cs
                lea     nw2(pc),a0
                jsr     -204(a6)
                move.l  d0,win2
                beq     .cw1
                move.l  win1(pc),a0
                move.l  50(a0),a2            ; wd_RPort
                lea     s_win(pc),a0
                bsr     ps
                bsr     nl
                moveq   #0,d7                ; cumulative tests
                bsr     tests
                move.l  intbase(pc),a6
                move.l  win2(pc),a0
                jsr     -72(a6)              ; CloseWindow
                lea     s_fin(pc),a0
                bsr     ps
                bsr     cks
.cw1:
                move.l  intbase(pc),a6
                move.l  win1(pc),a0
                jsr     -72(a6)
.cs:
                move.l  intbase(pc),a6
                move.l  scr(pc),a0
                jsr     -66(a6)              ; CloseScreen
                lea     t_end(pc),a0
                bsr     ps
                bsr     nl
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; tests(a2 = RastPort, d7 = 1: clear the screen planes before each test)
tests:
                lea     tlist(pc),a3
.t:
                move.l  (a3)+,d0
                beq.s   .r
                move.l  d0,-(sp)
                tst.w   d7
                beq.s   .nc
                move.l  scr(pc),a0
                movem.l a2,-(sp)
                lea     84(a0),a2
                bsr     clear
                movem.l (sp)+,a2
.nc:
                bsr     rstpen
                move.l  (sp)+,a0
                jsr     (a0)
                move.l  (a3)+,a0             ; label
                bsr     ps
                bsr     cks
                bra.s   .t
.r:
                rts
tlist:          dc.l    t_star,s_t1, t_starc,s_t2, t_rect,s_t3, t_pat,s_t4, t_rast,s_t5, t_hv,s_t6, t_mask,s_t7, t_text,s_t8, t_tmpl,s_t9, 0

; rstpen(a2): pens 1/0, JAM1, full mask, no pattern
rstpen:
                move.l  gfxbase(pc),a6
                move.l  a2,a1
                moveq   #1,d0
                jsr     -342(a6)             ; SetAPen
                move.l  a2,a1
                moveq   #0,d0
                jsr     -348(a6)             ; SetBPen
                move.l  a2,a1
                moveq   #0,d0
                jsr     -354(a6)             ; SetDrMd JAM1
                st      RP_MASK(a2)
                clr.l   RP_AREAPTRN(a2)
                clr.b   RP_AREAPTSZ(a2)
                rts

; T1: 3-colour star, from the centre to points on the perimeter (some outside the RastPort)
t_star:
                moveq   #0,d4
.lp:
                move.l  a2,a1
                moveq   #0,d0
                move.w  d4,d0
                divu    #3,d0
                swap    d0
                addq.w  #1,d0
                jsr     -342(a6)
                bsr     starpt
                addq.w  #1,d4
                cmp.w   #NSTAR,d4
                blt.s   .lp
                rts
; T2: same star in COMPLEMENT, twice with an offset (overlaps cancel out or not)
t_starc:
                move.l  a2,a1
                moveq   #2,d0
                jsr     -354(a6)             ; COMPLEMENT
                move.l  a2,a1
                moveq   #3,d0
                jsr     -342(a6)
                moveq   #0,d4
.lp:
                bsr     starpt
                addq.w  #3,d4
                cmp.w   #NSTAR,d4
                blt.s   .lp
                rts
; starpt(d4 = index): Move(centre) then Draw(point d4)
starpt:
                move.l  a2,a1
                move.w  #200,d0
                moveq   #70,d1
                jsr     -240(a6)             ; Move
                move.w  d4,d0
                add.w   d0,d0
                add.w   d0,d0
                lea     pts(pc),a0
                move.l  a2,a1
                movem.w 0(a0,d0.w),d0-d1
                jmp     -246(a6)             ; Draw

; T3: solid rectangles, various starts and widths, pens 0..3, overflows
t_rect:
                lea     rects(pc),a5
; rlist(a5 = list of rectangles)
rlist:
                move.w  (a5)+,d0
                bmi.s   .r
                move.l  a2,a1
                jsr     -342(a6)
                move.l  a2,a1
                movem.w (a5)+,d0-d3
                jsr     -306(a6)             ; RectFill
                bra.s   rlist
.r:
                rts
; T4: patterned rectangles: JAM1, JAM2, COMPLEMENT; 2- and 4-line patterns
t_pat:
                lea     pat2(pc),a0
                move.l  a0,RP_AREAPTRN(a2)
                move.b  #1,RP_AREAPTSZ(a2)
                move.l  a2,a1
                moveq   #2,d0
                jsr     -348(a6)             ; SetBPen 2
                bsr     t_rect               ; JAM1
                lea     pat4(pc),a0
                move.l  a0,RP_AREAPTRN(a2)
                move.b  #2,RP_AREAPTSZ(a2)
                move.l  a2,a1
                moveq   #1,d0
                jsr     -354(a6)             ; JAM2
                lea     rects2(pc),a5
                bsr     rlist
                move.l  a2,a1
                moveq   #2,d0
                jsr     -354(a6)             ; COMPLEMENT
                lea     rects3(pc),a5
                bsr     rlist
                move.l  a2,a1
                moveq   #5,d0
                jsr     -354(a6)             ; JAM2|INVERSVID
                lea     rects4(pc),a5
                bra     rlist
; T5: SetRast, then ClearEOL and ClearScreen in JAM2 (B pen) from a text position
t_rast:
                move.l  a2,a1
                moveq   #2,d0
                jsr     -234(a6)             ; SetRast(2)
                move.l  a2,a1
                moveq   #1,d0
                jsr     -354(a6)             ; JAM2
                move.l  a2,a1
                moveq   #1,d0
                jsr     -348(a6)             ; SetBPen 1
                move.l  a2,a1
                moveq   #37,d0
                moveq   #30,d1
                jsr     -240(a6)
                move.l  a2,a1
                jsr     -42(a6)              ; ClearEOL
                move.l  a2,a1
                moveq   #3,d0
                jsr     -348(a6)
                move.l  a2,a1
                move.w  #123,d0
                moveq   #90,d1
                jsr     -240(a6)
                move.l  a2,a1
                jsr     -48(a6)              ; ClearScreen
                move.l  a2,a1
                moveq   #0,d0
                jsr     -354(a6)             ; JAM1: ClearEOL clears to 0
                move.l  a2,a1
                moveq   #5,d0
                moveq   #60,d1
                jsr     -240(a6)
                move.l  a2,a1
                jmp     -42(a6)
; T6: crossing horizontal and vertical lines in COMPLEMENT, including single points and reversed directions
t_hv:
                move.l  a2,a1
                moveq   #2,d0
                jsr     -354(a6)
                move.l  a2,a1
                moveq   #3,d0
                jsr     -342(a6)
                lea     hv(pc),a5
.lp:
                move.w  (a5)+,d0
                cmp.w   #$7fff,d0
                beq.s   .r
                move.w  (a5)+,d1
                move.l  a2,a1
                jsr     -240(a6)
                movem.w (a5)+,d0-d1
                move.l  a2,a1
                jsr     -246(a6)
                bra.s   .lp
.r:
                rts
; T7: plane mask 1 (plane 0 only): star + rectangles
t_mask:
                move.b  #1,RP_MASK(a2)
                move.l  a2,a1
                moveq   #3,d0
                jsr     -342(a6)
                moveq   #0,d4
.lp:
                bsr     starpt
                addq.w  #2,d4
                cmp.w   #NSTAR,d4
                blt.s   .lp
                lea     rects(pc),a5
                bra     rlist

; T8: Text in all modes and styles, unaligned x positions, lines crossing the second window
t_text:
                lea     tx(pc),a5
.lp:
                move.w  (a5)+,d0
                bmi.s   .r
                move.l  a2,a1
                jsr     -354(a6)             ; SetDrMd
                move.b  (a5)+,56(a2)         ; rp_AlgoStyle
                move.l  a2,a1
                moveq   #0,d0
                move.b  (a5)+,d0
                jsr     -342(a6)             ; SetAPen
                move.l  a2,a1
                moveq   #2,d0
                jsr     -348(a6)             ; SetBPen 2
                move.l  a2,a1
                movem.w (a5)+,d0-d1
                jsr     -240(a6)             ; Move
                move.l  a2,a1
                lea     msg(pc),a0
                moveq   #MSGLEN,d0
                jsr     -60(a6)              ; Text
                bra.s   .lp
.r:
                clr.b   56(a2)
                rts

; T9: BltTemplate (64 x 12 template, starting at bit 3, 61 pixels wide) in all modes
t_tmpl:
                lea     bt(pc),a5
.lp:
                move.w  (a5)+,d0
                bmi.s   .r
                move.l  a2,a1
                jsr     -354(a6)             ; SetDrMd
                move.l  a2,a1
                moveq   #0,d0
                move.w  (a5)+,d0
                jsr     -342(a6)             ; SetAPen
                move.l  a2,a1
                moveq   #1,d0
                jsr     -348(a6)             ; SetBPen 1
                lea     tmpl(pc),a0
                moveq   #3,d0                ; xSrc
                moveq   #8,d1                ; srcMod
                move.l  a2,a1
                movem.w (a5)+,d2-d3
                moveq   #61,d4
                moveq   #12,d5
                jsr     -36(a6)              ; BltTemplate
                bra.s   .lp
.r:
                rts

; clear(a2 = screen RastPort): planes cleared by the CPU
clear:
                move.l  4(a2),a0             ; rp_BitMap
                moveq   #0,d0
                move.b  5(a0),d0             ; bm_Depth
                subq.w  #1,d0
                lea     8(a0),a1
.pl:
                move.l  (a1)+,a0
                move.w  #640/8*200/4-1,d1
.c:
                clr.l   (a0)+
                dbra    d1,.c
                dbra    d0,.pl
                rts
; cks: fingerprint of each plane of the screen BitMap, appended to the line, then the line is written
cks:
                move.l  scr(pc),a0
                lea     84(a0),a0
                move.l  4(a0),a0
                moveq   #0,d2
                move.b  5(a0),d2
                subq.w  #1,d2
                lea     8(a0),a1
.pl:
                move.l  (a1)+,a0
                move.w  #640/8*200/4-1,d1
                moveq   #0,d0
.c:
                rol.l   #5,d0
                add.l   (a0)+,d0
                dbra    d1,.c
                bsr     ph
                dbra    d2,.pl
                bra     nl

ps:                                          ; copies the string a0 to (a4)+
                move.b  (a0)+,(a4)+
                bne.s   ps
                subq.l  #1,a4
                rts
ph:                                          ; d0 as 8 digits + space
                movem.l d1/d3,-(sp)
                moveq   #7,d3
.h:
                rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:
                move.b  d1,(a4)+
                dbra    d3,.h
                move.b  #' ',(a4)+
                movem.l (sp)+,d1/d3
                rts
nl:                                          ; terminates the line and writes it to Output()
                movem.l d0-d3/a0-a1/a6,-(sp)
                move.b  #10,(a4)+
                lea     line(pc),a0
                move.l  a4,d3
                sub.l   a0,d3
                move.l  a0,d2
                move.l  dosbase(pc),a6
                jsr     -60(a6)              ; Output
                move.l  d0,d1
                jsr     -48(a6)              ; Write
                lea     line(pc),a4
                movem.l (sp)+,d0-d3/a0-a1/a6
                rts

dosname:        dc.b    "dos.library",0
gfxname:        dc.b    "graphics.library",0
intname:        dc.b    "intuition.library",0
s_scr:          dc.b    "ECRAN",0
s_win:          dc.b    "FENETRE",0
s_fin:          dc.b    "FIN ",0
s_t1:           dc.b    "T1 ",0
s_t2:           dc.b    "T2 ",0
s_t3:           dc.b    "T3 ",0
s_t4:           dc.b    "T4 ",0
s_t5:           dc.b    "T5 ",0
s_t6:           dc.b    "T6 ",0
s_t7:           dc.b    "T7 ",0
t_end:          dc.b    "END",0
s_t8:           dc.b    "T8 ",0
s_t9:           dc.b    "T9 ",0
msg:            dc.b    "Quick fox 0123 {|}~ jumps!"
MSGLEN          EQU *-msg
                even
; perimeter: (x, y) points relative to the RastPort, some beyond the edges
pts:            dc.w    -40,-30, 0,-5, 37,0, 81,-12, 120,3, 199,0, 200,-50, 241,1, 300,-7, 333,15
                dc.w    399,0, 420,22, 460,40, 700,-20, 640,70, 450,70, 391,99, 420,143, 380,149, 300,140
                dc.w    260,260, 201,150, 200,140, 199,139, 150,145, 90,160, 30,149, 0,120, -60,100, 3,71
                dc.w    0,70, 10,69, 7,40, -1,-1, 201,71, 202,70, 200,71, 263,98, 137,42, 380,70
NSTAR           EQU 40
; rectangles: pen, x0, y0, x1, y1; -1 = end
rects:          dc.w    1, 0,0,0,0
                dc.w    2, 3,2,3,40
                dc.w    3, 5,5,12,9
                dc.w    1, 7,11,8,11
                dc.w    2, 15,13,16,30
                dc.w    3, 17,20,47,25
                dc.w    1, 31,27,32,60
                dc.w    0, 20,22,40,23
                dc.w    2, 50,3,130,50
                dc.w    3, 61,40,190,44
                dc.w    1, 99,46,100,90
                dc.w    2, -20,80,25,95
                dc.w    3, 380,100,450,170
                dc.w    1, 200,-10,240,5
                dc.w    2, 140,100,139,120
                dc.w    3, 250,60,251,61
                dc.w    1, 255,62,384,63
                dc.w    2, 257,65,382,75
                dc.w    0, 300,66,301,140
                dc.w    -1
rects2:         dc.w    1, 9,100,170,130
                dc.w    3, 2,40,6,140
                dc.w    0, 175,5,395,35
                dc.w    -1
rects3:         dc.w    3, 0,0,399,149
                dc.w    1, 33,33,77,111
                dc.w    -1
rects4:         dc.w    2, 101,51,301,91
                dc.w    -1
pat2:           dc.w    $aaaa,$5555
pat4:           dc.w    $f00f,$3c3c,$0ff0,$c3c3
; texts: mode.w, style.b, pen.b, x.w, y.w; -1 = end. Styles: 1 underlined, 2 bold. Modes: 0 JAM1, 1 JAM2,
; 2 COMPLEMENT, 4 INVERSVID.
tx:             dc.w    1
                dc.b    0,1
                dc.w    0,10
                dc.w    1
                dc.b    0,3
                dc.w    5,20
                dc.w    0
                dc.b    0,1
                dc.w    3,30
                dc.w    0
                dc.b    0,3
                dc.w    200,30
                dc.w    2
                dc.b    0,1
                dc.w    7,40
                dc.w    2
                dc.b    0,1
                dc.w    9,43
                dc.w    5
                dc.b    0,1
                dc.w    11,55
                dc.w    4
                dc.b    0,2
                dc.w    13,65
                dc.w    0
                dc.b    2,1
                dc.w    1,80
                dc.w    1
                dc.b    1,3
                dc.w    6,95
                dc.w    1
                dc.b    3,1
                dc.w    250,100
                dc.w    0
                dc.b    3,2
                dc.w    290,120
                dc.w    1
                dc.b    0,1
                dc.w    300,140
                dc.w    0
                dc.b    0,3
                dc.w    -20,6
                dc.w    1
                dc.b    0,1
                dc.w    380,150
                dc.w    -1
; BltTemplate: mode, pen, x, y; -1 = end
bt:             dc.w    0,3,5,5, 1,2,70,9, 2,3,13,20, 4,1,140,30, 5,3,201,41, 1,3,350,100, 0,2,370,130
                dc.w    2,1,-30,60, 1,1,300,140, -1
tmpl:           dc.b    $f0,$0f,$aa,$55,$ff,$00,$81,$7e, $3c,$c3,$5a,$a5,$0f,$f0,$e7,$18
                dc.b    $ff,$ff,$00,$00,$12,$34,$56,$78, $9a,$bc,$de,$f0,$01,$80,$cc,$33
                dc.b    $80,$40,$20,$10,$08,$04,$02,$01, $01,$02,$04,$08,$10,$20,$40,$80
                dc.b    $aa,$aa,$aa,$aa,$55,$55,$55,$55, $fe,$dc,$ba,$98,$76,$54,$32,$10
                dc.b    $00,$ff,$00,$ff,$00,$ff,$00,$ff, $c0,$03,$e0,$07,$f0,$0f,$f8,$1f
                dc.b    $69,$96,$69,$96,$69,$96,$69,$96, $11,$22,$44,$88,$11,$22,$44,$88
; horizontals/verticals: x0,y0,x1,y1; $7fff = end
hv:             dc.w    10,10,300,10, 300,12,10,12, 150,0,150,149, 152,149,152,0, 20,10,20,10
                dc.w    0,50,399,50, 5,48,5,52, 6,47,6,53, 7,46,7,54, 8,45,8,55, 380,-20,380,300
                dc.w    -50,100,500,100, 33,33,33,33, 34,33,34,33, 395,140,410,140, 1,1,8,1
                dc.w    $7fff
ns:             dc.w    0,0,640,200,2        ; NewScreen
                dc.b    0,1
                dc.w    $8000,$010f          ; HIRES; CUSTOMSCREEN|SCREENQUIET
                dc.l    0,0,0,0
nw1:            dc.w    100,20,400,150       ; NewWindow
                dc.b    0,1
                dc.l    0,$0800              ; BORDERLESS
                dc.l    0,0,0,0,0
                dc.w    0,0,0,0,$000f
nw2:            dc.w    420,110,120,60
                dc.b    0,1
                dc.l    0,$0800
                dc.l    0,0,0,0,0
                dc.w    0,0,0,0,$000f
                even
dosbase:        dc.l    0
gfxbase:        dc.l    0
intbase:        dc.l    0
scr:            dc.l    0
win1:           dc.l    0
win2:           dc.l    0
line:           ds.b    200
