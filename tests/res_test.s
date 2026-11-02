; tests/res_test.s - cia.resource, potgo.resource, misc.resource, disk.resource (implementation-side test of
; docs/analysis/resources-v34.md). Run from a startup-sequence (tests/garea_probe.sh <rom> <exe> <out>); results on
; the serial port, one "NAME value(s)" line per check. Expected:
;   CIABASE 0008 2000 0000 0000 00BFD000   level bits of ciaa/ciab, lib_Version 0 for both, ciab hardware base
;   CIAOWN 1                       AddICRVector(1) on ciaa returns the owner (timer.device), the vector's iv_Node
;   CIBADD 00000000 1              AddICRVector(1) on ciab -> 0, the bit is enabled at once
;   CISET 00000001                 SetICR($82): the vector runs at the next level-6 service
;   CILATCH 1 00000001 00000002 0  bit disabled: SetICR($82) latches it (no call), AbleICR($82) runs the vector and
;                                  clears it
;   CIREM 00000000 0 00000000      RemICRVector: 0, bit disabled, iv_Node NULL
;   PGBASE 06 0000                 potgo lib_Flags, lib_Version
;   PGALLOC 0000C000 00000000 0000C000   AllocPotBits($C000); FreePotBits($8000) frees nothing; FreePotBits($4000)
;                                  frees both
;   PGSTART 00001000 00000000      DATRX held as an input: START refused
;   PGOUT 00002000                 a lone OUT bit is granted while START is free
;   MRBASE 06 0022 0001            misc lib_Flags, version 34, revision 1
;   MRALLOC 00000000 1             AllocMiscResource(0,"A") then (0,"B") -> owner name "A"
;   DRBASE 0022 0001               disk.resource version 34, revision 1
;   DRALLOC 000000FF FFFFFFFF      AllocUnit(3) on a unit never opened; GetUnitID(2) without DF2

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
CIA_VEC1 EQU $40+12                     ; IntVector of ICR bit 1 in a CIA resource base

start:  move.l  4.w,a6
        lea     ciaaname(pc),a1
        jsr     -498(a6)                ; OpenResource
        move.l  d0,ciaa
        beq     .pot
        lea     ciabname(pc),a1
        jsr     -498(a6)
        move.l  d0,ciab
        beq     .pot

        lea     m_cbase(pc),a0          ; --- cia.resource
        bsr     puts
        move.l  ciaa,a0
        move.w  $26(a0),d0
        bsr     hex4
        move.l  ciab,a0
        move.w  $26(a0),d0
        bsr     hex4
        move.l  ciaa,a0
        move.w  $14(a0),d0
        bsr     hex4
        move.l  ciab,a0
        move.w  $14(a0),d0
        bsr     hex4
        move.l  ciab,a0
        move.l  $22(a0),d0
        bsr     hex8
        bsr     nl

        lea     m_cown(pc),a0
        bsr     puts
        move.l  ciaa,a6
        moveq   #1,d0
        lea     myint(pc),a1
        jsr     -6(a6)                  ; AddICRVector
        move.l  4.w,a6
        moveq   #0,d1
        tst.l   d0
        beq.s   .o1
        lea     myint(pc),a0
        cmp.l   a0,d0
        beq.s   .o1
        move.l  ciaa,a0
        cmp.l   CIA_VEC1+8(a0),d0
        bne.s   .o1
        moveq   #1,d1
.o1:    move.l  d1,d0
        bsr     dig
        bsr     nl

        lea     m_cadd(pc),a0
        bsr     puts
        move.l  ciab,a6
        moveq   #1,d0
        lea     myint(pc),a1
        jsr     -6(a6)
        bsr     hex8
        moveq   #0,d0
        jsr     -18(a6)                 ; AbleICR(0)
        lsr.b   #1,d0
        and.l   #1,d0
        move.l  4.w,a6
        bsr     dig
        bsr     nl

        lea     m_cset(pc),a0
        bsr     puts
        clr.l   count
        move.l  ciab,a6
        move.l  #$82,d0
        jsr     -24(a6)                 ; SetICR($82)
        move.l  4.w,a6
        bsr     delay
        move.l  count,d0
        bsr     hex8
        bsr     nl

        lea     m_clatch(pc),a0
        bsr     puts
        move.l  ciab,a6
        moveq   #$02,d0
        jsr     -18(a6)                 ; AbleICR($02): disable bit 1
        move.l  #$82,d0
        jsr     -24(a6)                 ; SetICR($82): latched only
        move.l  4.w,a6
        bsr     delay
        move.l  ciab,a6
        moveq   #0,d0
        jsr     -24(a6)                 ; SetICR(0): sample
        lsr.b   #1,d0
        and.l   #1,d0
        move.l  4.w,a6
        bsr     dig
        move.l  count,d0
        bsr     hex8
        move.l  ciab,a6
        move.l  #$82,d0
        jsr     -18(a6)                 ; AbleICR($82): the latched flag fires
        move.l  4.w,a6
        bsr     delay
        move.l  count,d0
        bsr     hex8
        move.l  ciab,a6
        moveq   #0,d0
        jsr     -24(a6)
        lsr.b   #1,d0
        and.l   #1,d0
        move.l  4.w,a6
        bsr     dig
        bsr     nl

        lea     m_crem(pc),a0
        bsr     puts
        move.l  ciab,a6
        moveq   #1,d0
        sub.l   a1,a1
        jsr     -12(a6)                 ; RemICRVector
        bsr     hex8
        moveq   #0,d0
        jsr     -18(a6)
        lsr.b   #1,d0
        and.l   #1,d0
        move.l  4.w,a6
        bsr     dig
        move.l  ciab,a0
        move.l  CIA_VEC1+8(a0),d0
        bsr     hex8
        bsr     nl

.pot:   lea     potname(pc),a1          ; --- potgo.resource
        jsr     -498(a6)
        tst.l   d0
        beq     .misc
        move.l  d0,a5
        lea     m_pbase(pc),a0
        bsr     puts
        move.b  14(a5),d0
        bsr     hex2
        move.w  $14(a5),d0
        bsr     hex4
        bsr     nl
        move.l  a5,a6
        lea     m_palloc(pc),a0
        bsr     puts
        move.l  #$C000,d0
        jsr     -6(a6)                  ; AllocPotBits
        bsr     hex8
        move.l  #$8000,d0
        jsr     -12(a6)                 ; FreePotBits: OUT alone frees nothing
        move.l  #$8000,d0
        jsr     -6(a6)
        bsr     hex8
        move.l  #$4000,d0
        jsr     -12(a6)                 ; DAT frees its OUT too
        move.l  #$C000,d0
        jsr     -6(a6)
        bsr     hex8
        move.l  #$4000,d0
        jsr     -12(a6)
        bsr     nl
        lea     m_pstart(pc),a0
        bsr     puts
        move.l  #$1000,d0
        jsr     -6(a6)
        bsr     hex8
        moveq   #1,d0
        jsr     -6(a6)
        bsr     hex8
        tst.l   d0
        beq.s   .p1
        moveq   #1,d0
        jsr     -12(a6)
.p1:    move.l  #$1000,d0
        jsr     -12(a6)
        bsr     nl
        lea     m_pout(pc),a0
        bsr     puts
        move.l  #$2000,d0
        jsr     -6(a6)
        bsr     hex8
        move.l  #$1000,d0
        jsr     -12(a6)                 ; frees DATRX and OUTRX
        bsr     nl
        move.l  4.w,a6

.misc:  lea     miscname(pc),a1         ; --- misc.resource
        jsr     -498(a6)
        tst.l   d0
        beq     .disk
        move.l  d0,a5
        lea     m_mbase(pc),a0
        bsr     puts
        move.b  14(a5),d0
        bsr     hex2
        move.w  $14(a5),d0
        bsr     hex4
        move.w  $16(a5),d0
        bsr     hex4
        bsr     nl
        lea     m_malloc(pc),a0
        bsr     puts
        move.l  a5,a6
        moveq   #0,d0
        lea     nameA(pc),a1
        jsr     -6(a6)
        bsr     hex8
        tst.l   d0
        bne.s   .m0
        moveq   #0,d0
        lea     nameB(pc),a1
        jsr     -6(a6)
        lea     nameA(pc),a0
        cmp.l   a0,d0
        seq     d0
        and.l   #1,d0
        bsr     dig
        moveq   #0,d0
        jsr     -12(a6)                 ; FreeMiscResource
.m0:    bsr     nl
        move.l  4.w,a6

.disk:  lea     diskname(pc),a1         ; --- disk.resource
        jsr     -498(a6)
        tst.l   d0
        beq     .end
        move.l  d0,a5
        lea     m_dbase(pc),a0
        bsr     puts
        move.w  $14(a5),d0
        bsr     hex4
        move.w  $16(a5),d0
        bsr     hex4
        bsr     nl
        lea     m_dalloc(pc),a0
        bsr     puts
        move.l  a5,a6
        moveq   #3,d0
        jsr     -6(a6)                  ; AllocUnit(3)
        bsr     hex8
        moveq   #3,d0
        jsr     -12(a6)                 ; FreeUnit(3)
        moveq   #2,d0
        jsr     -30(a6)                 ; GetUnitID(2)
        bsr     hex8
        bsr     nl
        move.l  4.w,a6
.end:   lea     m_end(pc),a0
        bsr     puts
        moveq   #0,d0
        rts

; myint: CIA vector, counts its calls.
myint_code:
        addq.l  #1,count
        moveq   #0,d0
        rts
; delay: about 20 ms of busy loop (interrupts on).
delay:  move.l  #20000,d1
.d:     subq.l  #1,d1
        bne.s   .d
        rts

dig:    add.b   #'0',d0
        lea     hbuf,a0
        move.b  d0,(a0)+
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bra.s   puts
nl:     lea     m_nl(pc),a0
; puts(a0): NUL-terminated string on the serial port. Clobbers d1/a0.
puts:   move.b  (a0)+,d1
        beq.s   .e
.w:     btst    #5,SERDATR              ; TBE (bit 13)
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        bra.s   puts
.e:     rts
; hex8(d0.l) / hex4(d0.w) / hex2(d0.b): hex digits and a space. d0 preserved.
hex8:   moveq   #7,d1
        bra.s   hexn
hex4:   swap    d0
        moveq   #3,d1
        bsr.s   hexn
        swap    d0
        rts
hex2:   ror.l   #8,d0
        moveq   #1,d1
        bsr.s   hexn
        rol.l   #8,d0
        rts
hexn:   lea     hbuf,a0
.dg:    rol.l   #4,d0
        move.l  d0,-(sp)
        and.w   #15,d0
        move.b  hexd(pc,d0.w),(a0)+
        move.l  (sp)+,d0
        dbra    d1,.dg
        move.b  #' ',(a0)+
        clr.b   (a0)
        move.l  d0,-(sp)
        lea     hbuf,a0
        bsr.s   puts
        move.l  (sp)+,d0
        rts
hexd:   dc.b    "0123456789ABCDEF"

        even
myint:  dc.l    0,0
        dc.b    2,0                     ; NT_INTERRUPT
        dc.l    0,0,myint_code          ; ln_Name, is_Data, is_Code
ciaaname: dc.b  "ciaa.resource",0
ciabname: dc.b  "ciab.resource",0
potname: dc.b   "potgo.resource",0
miscname: dc.b  "misc.resource",0
diskname: dc.b  "disk.resource",0
nameA:  dc.b    "A",0
nameB:  dc.b    "B",0
m_cbase: dc.b   13,10,"CIABASE ",0
m_cown: dc.b    "CIAOWN ",0
m_cadd: dc.b    "CIBADD ",0
m_cset: dc.b    "CISET ",0
m_clatch: dc.b  "CILATCH ",0
m_crem: dc.b    "CIREM ",0
m_pbase: dc.b   "PGBASE ",0
m_palloc: dc.b  "PGALLOC ",0
m_pstart: dc.b  "PGSTART ",0
m_pout: dc.b    "PGOUT ",0
m_mbase: dc.b   "MRBASE ",0
m_malloc: dc.b  "MRALLOC ",0
m_dbase: dc.b   "DRBASE ",0
m_dalloc: dc.b  "DRALLOC ",0
m_nl:   dc.b    13,10,0
m_end:  dc.b    "RES END",13,10,"GAP fin",13,10,0
        even

        section bss,bss
ciaa:   ds.l    1
ciab:   ds.l    1
count:  ds.l    1
hbuf:   ds.b    12
