; tests/lowmem_probe.s - CLI probe: free fast memory before and after an AllocMem that cannot succeed.
; Prints "LOWMEM A=<hex> B=<hex> R=<hex>": A and B are AvailMem(MEMF_FAST) before and after
; AllocMem($7FFFFFF0, MEMF_FAST), R is that AllocMem's result (0 expected). After a failure exec expunges unused
; modules and trackdisk gives its multi-track cache back, so B - A shows what the failure path released.
; Run from a disk that was read before (the cache is allocated at the first read). Build:
;   vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -o lowmem_probe tests/lowmem_probe.s
                include "exec.i"
                include "dospkt.i"
MEMF_FAST_      EQU 4
                section code,code
_start:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a5                ; a5 = DOSBase
        tst.l   d0
        beq.s   .out
        moveq   #MEMF_FAST_,d1
        jsr     LVO_AVAILMEM(a6)
        move.l  d0,d5                ; d5 = A
        move.l  #$7FFFFFF0,d0
        moveq   #MEMF_FAST_,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,d7                ; d7 = R
        moveq   #MEMF_FAST_,d1
        jsr     LVO_AVAILMEM(a6)
        move.l  d0,d6                ; d6 = B
        lea     line(pc),a2
        lea     hexa(pc),a0
        move.l  d5,d0
        bsr.s   hex8
        lea     hexb(pc),a0
        move.l  d6,d0
        bsr.s   hex8
        lea     hexr(pc),a0
        move.l  d7,d0
        bsr.s   hex8
        move.l  a5,a6
        jsr     DOS_LVO_OUTPUT(a6)
        move.l  d0,d1
        move.l  a2,d2
        moveq   #linelen,d3
        jsr     DOS_LVO_WRITE(a6)
        move.l  a5,a1
        move.l  4.w,a6
        jsr     LVO_CLOSELIBRARY(a6)
.out:
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts
; hex8(d0 = value, a0 = 8-character field): writes the value in upper-case hexadecimal.
hex8:
        moveq   #7,d2
.hx:
        rol.l   #4,d0
        move.b  d0,d1
        and.w   #15,d1
        move.b  digits(pc,d1.w),(a0)+
        dbra    d2,.hx
        rts
digits: dc.b    "0123456789ABCDEF"
dosname: dc.b   "dos.library",0
line:   dc.b    "LOWMEM A="
hexa:   dc.b    "00000000 B="
hexb:   dc.b    "00000000 R="
hexr:   dc.b    "00000000",10
linelen EQU *-line
        even
