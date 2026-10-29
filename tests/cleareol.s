; tests/cleareol.s - test HUNK executable (TEST ASSET, NOT ROM code): area cleared by ClearEOL and
; ClearScreen. Private RastPort on a chip BitMap 320 x 20 x 2 planes, default font (topaz 8). For each call:
; SetRast(1), Move(100, 10), settings, call, then ReadPixel of 6 points; writes to the CLI output a line
; "EOL/SCR" + one hexadecimal digit per point. EOL: JAM2, B pen = 2. SCR: JAM1 (colour 0 expected).
; Points: (99,8) (100,4) (319,11) (100,3) (100,12) (0,19). Black-box probe, real ROM compared with ours.
; Clean-room: public structures, authored code.

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
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                lea     dosbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                move.l  #1600,d0             ; 2 planes of 320 x 20
                move.l  #$10002,d1           ; MEMF_CHIP | MEMF_CLEAR
                jsr     -198(a6)             ; AllocMem
                tst.l   d0
                beq     .ret
                lea     bitmap(pc),a0
                move.l  d0,8(a0)             ; Planes[0]
                add.l   #800,d0
                move.l  d0,12(a0)            ; Planes[1]
                move.l  d6,a6
                moveq   #2,d0
                move.l  #320,d1
                moveq   #20,d2
                jsr     -390(a6)             ; InitBitMap(bm a0, depth, width, height)
                lea     rport(pc),a1
                jsr     -198(a6)             ; InitRastPort
                lea     rport(pc),a1
                lea     bitmap(pc),a0
                move.l  a0,RP_BM(a1)
                bsr     prep
                lea     rport(pc),a1
                moveq   #2,d0
                jsr     -348(a6)             ; SetBPen
                lea     rport(pc),a1
                moveq   #1,d0
                jsr     -354(a6)             ; SetDrMd JAM2
                lea     rport(pc),a1
                jsr     -42(a6)              ; ClearEOL
                lea     t_eol(pc),a0
                bsr     report
                bsr     prep
                lea     rport(pc),a1
                moveq   #0,d0
                jsr     -354(a6)             ; SetDrMd JAM1
                lea     rport(pc),a1
                jsr     -48(a6)              ; ClearScreen
                lea     t_scr(pc),a0
                bsr     report
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

prep:                                        ; SetRast(1) then Move(100, 10)
                lea     rport(pc),a1
                moveq   #1,d0
                jsr     -234(a6)             ; SetRast
                lea     rport(pc),a1
                moveq   #100,d0
                moveq   #10,d1
                jmp     -240(a6)             ; Move
report:                                      ; a0 = label; reads the 6 points and writes the line to Output()
                lea     line(pc),a1
.cp:
                move.b  (a0)+,(a1)+
                bne.s   .cp
                subq.l  #1,a1
                lea     points(pc),a2
                moveq   #5,d7
.pt:
                move.l  a1,-(sp)
                lea     rport(pc),a1
                move.w  (a2)+,d0
                move.w  (a2)+,d1
                ext.l   d0
                ext.l   d1
                jsr     -318(a6)             ; ReadPixel -> d0
                move.l  (sp)+,a1
                and.b   #15,d0
                add.b   #'0',d0
                move.b  d0,(a1)+
                dbra    d7,.pt
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

gfxname:        dc.b    "graphics.library",0
dosname:        dc.b    "dos.library",0
t_eol:          dc.b    "EOL ",0
t_scr:          dc.b    "SCR ",0
                even
points:         dc.w    99,8, 100,4, 319,11, 100,3, 100,12, 0,19
bitmap:         ds.b    40
rport:          ds.b    100
dosbase:        dc.l    0
line:           ds.b    40
