; tests/memmap.s - HUNK test executable (TEST ASSET, NOT ROM code): map of free memory.
; Walks ExecBase->MemList under Forbid and sends to the serial port (SERDAT, like cmd_e3.s) one line per MemHeader
; ("MH lower upper free attributes") then one line per free block ("FR address size"). Used to compare the
; memory layout of our ROM with that of the real 1.3 at the same point of a startup-sequence (programs that
; write to absolute addresses). Clean-room: public exec structures (MemHeader/MemChunk), authored code.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
EB_MEMLIST EQU $142
MH_ATTR  EQU 14
MH_FIRST EQU 16
MH_LOWER EQU 20
MH_UPPER EQU 24
MH_FREE  EQU 28

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                jsr     -132(a6)             ; Forbid
                move.l  EB_MEMLIST(a6),a2    ; 1st MemHeader
.mh:
                tst.l   (a2)
                beq.s   .end
                lea     t_mh(pc),a0
                bsr.s   puts
                move.l  MH_LOWER(a2),d0
                bsr.s   puthex
                move.l  MH_UPPER(a2),d0
                bsr.s   puthex
                move.l  MH_FREE(a2),d0
                bsr.s   puthex
                moveq   #0,d0
                move.w  MH_ATTR(a2),d0
                bsr.s   puthex
                bsr.s   putnl
                move.l  MH_FIRST(a2),a3
.fr:
                move.l  a3,d0
                beq.s   .nmh
                lea     t_fr(pc),a0
                bsr.s   puts
                move.l  a3,d0
                bsr.s   puthex
                move.l  4(a3),d0
                bsr.s   puthex
                bsr.s   putnl
                move.l  (a3),a3
                bra.s   .fr
.nmh:
                move.l  (a2),a2
                bra.s   .mh
.end:
                jsr     -138(a6)             ; Permit
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
putnl:
                moveq   #10,d1
; putc(d1.b): waits for the transmit buffer to be empty, then sends (8 bits + stop).
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

t_mh:           dc.b    "MH ",0
t_fr:           dc.b    "FR ",0
