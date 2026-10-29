; tests/itextstate.s - HUNK test executable (TEST ASSET, NOT ROM code): RastPort state after PrintIText
; and DrawBorder. Sets pen A = 5, pen B = 6, JAM2 mode on a private RastPort (one-plane chip BitMap), calls
; PrintIText (IntuiText pens 2/1, JAM1) then DrawBorder (Border pen 3, COMPLEMENT) and writes to the CLI
; output "IT before after" and "BD before after", each value = FgPen<<16 | BgPen<<8 | DrawMode. Black-box probe:
; a ROM that restores the pens gives the same value before and after. Clean-room: public structures, author's code.

RP_FG    EQU 25
RP_BG    EQU 26
RP_DRMD  EQU 28
RP_BM    EQU 4

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                move.l  d0,d6
                beq     .ret
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,d7
                beq     .ret
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                lea     dosbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                move.l  #800,d0              ; plane 320 x 20
                move.l  #$10002,d1           ; MEMF_CHIP | MEMF_CLEAR
                jsr     -198(a6)             ; AllocMem
                tst.l   d0
                beq     .ret
                lea     bitmap(pc),a0
                move.l  d0,8(a0)             ; Planes[0]
                move.l  d6,a6
                moveq   #1,d0
                move.l  #320,d1
                moveq   #20,d2
                jsr     -390(a6)             ; InitBitMap(bm a0, depth, width, height)
                lea     rport(pc),a1
                jsr     -198(a6)             ; InitRastPort
                lea     rport(pc),a1
                lea     bitmap(pc),a0
                move.l  a0,RP_BM(a1)
                bsr     setstate
                bsr     getstate
                move.l  d0,d4
                lea     rport(pc),a0
                lea     itext(pc),a1
                lea     txt(pc),a2
                move.l  a2,12(a1)            ; IText
                moveq   #4,d0
                moveq   #2,d1
                move.l  d7,a6
                jsr     -216(a6)             ; PrintIText(rp a0, itext a1, x d0, y d1)
                bsr     getstate
                move.l  d0,d5
                lea     t_it(pc),a0
                bsr     report
                move.l  d6,a6
                bsr     setstate
                bsr     getstate
                move.l  d0,d4
                lea     rport(pc),a0
                lea     border(pc),a1
                lea     bxy(pc),a2
                move.l  a2,8(a1)             ; XY
                moveq   #0,d0
                moveq   #0,d1
                move.l  d7,a6
                jsr     -108(a6)             ; DrawBorder(rp a0, border a1, x d0, y d1)
                bsr     getstate
                move.l  d0,d5
                lea     t_bd(pc),a0
                bsr     report
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

setstate:                                    ; a6 = GfxBase : A = 5, B = 6, JAM2
                lea     rport(pc),a1
                moveq   #5,d0
                jsr     -342(a6)             ; SetAPen
                lea     rport(pc),a1
                moveq   #6,d0
                jsr     -348(a6)             ; SetBPen
                lea     rport(pc),a1
                moveq   #1,d0
                jmp     -354(a6)             ; SetDrMd
getstate:                                    ; -> d0 = Fg<<16 | Bg<<8 | DrawMode
                lea     rport(pc),a0
                moveq   #0,d0
                move.b  RP_FG(a0),d0
                swap    d0
                move.b  RP_BG(a0),d0
                lsl.w   #8,d0
                move.b  RP_DRMD(a0),d0
                rts
report:                                      ; a0 = label, d4 = before, d5 = after: one line on Output()
                lea     line(pc),a1
.cp:
                move.b  (a0)+,(a1)+
                bne.s   .cp
                subq.l  #1,a1
                move.l  d4,d0
                bsr.s   puthex
                move.l  d5,d0
                bsr.s   puthex
                move.b  #10,(a1)+
                lea     line(pc),a0
                move.l  a1,d3
                sub.l   a0,d3                ; length
                move.l  a6,-(sp)
                move.l  dosbase(pc),a6
                jsr     -60(a6)              ; Output
                move.l  d0,d1
                lea     line(pc),a0
                move.l  a0,d2
                jsr     -48(a6)              ; Write(fh d1, buffer d2, length d3)
                move.l  (sp)+,a6
                rts
; puthex(d0): 8 hexadecimal digits then a space, to (a1)+.
puthex:
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
                move.b  d1,(a1)+
                dbra    d3,.h
                move.b  #' ',(a1)+
                rts

gfxname:        dc.b    "graphics.library",0
intname:        dc.b    "intuition.library",0
dosname:        dc.b    "dos.library",0
txt:            dc.b    "AB",0
t_it:           dc.b    "IT ",0
t_bd:           dc.b    "BD ",0
                even
itext:          dc.b    2,1,0,0              ; FrontPen, BackPen, DrawMode JAM1, pad
                dc.w    0,0                  ; LeftEdge, TopEdge
                dc.l    0,0,0                ; ITextFont, IText, NextText
border:         dc.w    0,0                  ; LeftEdge, TopEdge
                dc.b    3,0,2,2              ; FrontPen, BackPen, DrawMode COMPLEMENT, Count
                dc.l    0,0                  ; XY, NextBorder
bxy:            dc.w    0,0,10,5
bitmap:         ds.b    40
rport:          ds.b    100
dosbase:        dc.l    0
line:           ds.b    40
