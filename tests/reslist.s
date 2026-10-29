; tests/reslist.s - test HUNK executable (TEST ASSET, NOT ROM code): list of the dos resident segments.
; Follows DOSBase->dl_Root->rn_Info->DosInfo+16 (BPTR, chain !0) and emits one line per node on the serial port:
; "RS address usage seglist name". Black-box probe to compare the initial list of the real 1.3 with ours.
; Clean-room: public dos structures (RootNode, DosInfo, Resident nodes), authored code.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                tst.l   d0
                beq.s   .ret
                move.l  d0,a5
                jsr     -132(a6)             ; Forbid
                move.l  34(a5),a0            ; dl_Root
                move.l  24(a0),d0            ; rn_Info (BPTR)
                lsl.l   #2,d0
                move.l  d0,a0
                move.l  16(a0),d4            ; ResList (BPTR)
.lp:
                lsl.l   #2,d4
                beq.s   .end
                move.l  d4,a2
                lea     t_rs(pc),a0
                bsr.s   puts
                move.l  a2,d0
                bsr.s   puthex
                move.l  4(a2),d0
                bsr.s   puthex
                move.l  8(a2),d0
                bsr.s   puthex
                moveq   #0,d4
                move.b  12(a2),d4            ; BSTR at +12
                lea     13(a2),a3
.nm:
                subq.w  #1,d4
                bmi.s   .nmd
                move.b  (a3)+,d1
                bsr.s   putc
                bra.s   .nm
.nmd:
                moveq   #10,d1
                bsr.s   putc
                move.l  (a2),d4
                bra.s   .lp
.end:
                lea     t_end(pc),a0
                bsr.s   puts
                jsr     -138(a6)             ; Permit
                move.l  a5,a1
                jsr     -414(a6)             ; CloseLibrary
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

puts:
                move.b  (a0)+,d1
                beq.s   .r
                bsr.s   putc
                bra.s   puts
.r:
                rts
; putc(d1.b): waits until the transmit buffer is free, then transmits (8 bits + stop).
putc:
                move.w  SERDATR,d2
                btst    #13,d2
                beq.s   putc
                and.w   #$00FF,d1
                or.w    #$0100,d1
                move.w  d1,SERDAT
                rts
; puthex(d0): 8 hexadecimal digits followed by a space.
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
                bsr.s   putc
                dbra    d3,.h
                moveq   #' ',d1
                bra.s   putc

dosname:        dc.b    "dos.library",0
t_rs:           dc.b    "RS ",0
t_end:          dc.b    "RS-FIN",10,0
