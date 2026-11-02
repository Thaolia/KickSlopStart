; tests/lmisc_test.s - layers Fatten/ThinLayerInfo, console CDInputHandler, dos WaitForChar (implementation-side test:
; layers-v34 §5.10, console-keymap-v34 §6.1, dos-exit-packets-v34 §2). Run from a startup-sequence
; (tests/garea_probe.sh <rom> <exe> <out>); results on the serial port. Expected:
;   NLI 0001 00 0042             NewLayerInfo: Flags NEWLAYERINFO_CALLED, fatten_count 0, extra_size $42
;   FAT 00000001 0001 01         FattenLayerInfo returns 1, count 1
;   THN 0000 00 / 0000 FF        two ThinLayerInfo: flag cleared, count 0 then -1
;   CDI 00000000                 CDInputHandler(NULL, console base) returns 0
;   WFC 00000000 00000000 n 1    on a RAW: window, WaitForChar(fh, 0) = 0 at once, WaitForChar(fh, 300000) = 0 after
;                                n frames (n >= 10)

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
LI_FLAGS EQU $58
LI_FAT   EQU $5A
LI_XSZ   EQU $5C

start:  move.l  4.w,a6
        move.l  a6,execb
        lea     layname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,layb
        beq     .out
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)
        move.l  d0,dosb
        beq     .out

        move.l  layb,a6                 ; --- NewLayerInfo / Fatten / Thin
        jsr     -144(a6)
        move.l  d0,li
        beq     .out
        lea     m_nli(pc),a0
        bsr     puts
        bsr     listate
        bsr     nl
        move.l  li,a0
        jsr     -156(a6)                ; FattenLayerInfo
        move.l  d0,-(sp)
        lea     m_fat(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     hex8
        bsr     listate2
        bsr     nl
        lea     m_thn(pc),a0
        bsr     puts
        move.l  li,a0
        jsr     -162(a6)                ; ThinLayerInfo
        bsr     listate2
        lea     m_sl(pc),a0
        bsr     puts
        move.l  li,a0
        jsr     -162(a6)
        bsr     listate2
        bsr     nl
        move.l  li,a0
        addq.b  #1,LI_FAT(a0)           ; back to "fat once" before DisposeLayerInfo thins it
        jsr     -150(a6)                ; DisposeLayerInfo

        move.l  execb,a6                ; --- CDInputHandler(NULL)
        jsr     -132(a6)                ; Forbid
        lea     $15E(a6),a0             ; DeviceList
        lea     conname(pc),a1
        jsr     -276(a6)                ; FindName
        jsr     -138(a6)                ; Permit
        move.l  d0,a1
        sub.l   a0,a0
        move.l  d0,-(sp)
        beq.s   .nocon
        move.l  a1,a6
        jsr     -42(a6)
        move.l  d0,(sp)
.nocon: lea     m_cdi(pc),a0
        bsr     puts
        move.l  (sp)+,d0
        bsr     hex8
        bsr     nl

        move.l  dosb,a6                 ; --- WaitForChar on a RAW: window (ROM console handler)
        move.l  #rawname,d1
        move.l  #1006,d2                ; MODE_NEWFILE
        jsr     -30(a6)                 ; Open
        move.l  d0,outfh
        beq     .out
        move.l  d0,d1
        moveq   #0,d2
        jsr     -204(a6)
        move.l  d0,r1
        move.l  outfh,d1
        move.l  #300000,d2
        bsr     vbcount
        move.l  d0,d6
        jsr     -204(a6)
        move.l  d0,r2
        bsr     vbcount
        sub.l   d6,d0
        move.l  d0,d7                   ; frames elapsed
        lea     m_wfc(pc),a0
        bsr     puts
        move.l  r1,d0
        bsr     hex8
        move.l  r2,d0
        bsr     hex8
        move.l  d7,d0                   ; frames elapsed (diagnostic)
        bsr     hex8
        moveq   #0,d0
        cmp.l   #10,d7
        blo.s   .w1
        moveq   #1,d0
.w1:    add.b   #'0',d0
        lea     hbuf,a0
        move.b  d0,(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bsr     puts
        bsr     nl
        move.l  outfh,d1
        jsr     -36(a6)                 ; Close
        lea     m_end(pc),a0
        bsr     puts
.out:   moveq   #0,d0
        rts

; vbcount -> d0 = CIA-A TOD (counts vertical syncs, 50 Hz in PAL).
vbcount:
        moveq   #0,d0
        move.b  $BFEA01,d0              ; TODHI
        swap    d0
        move.b  $BFE901,d0              ; TODMID
        lsl.w   #8,d0
        move.b  $BFE801,d0              ; TODLO (reading it releases the latch)
        rts

; listate: Flags (word), fatten_count (byte), extra_size (word) of li. listate2: Flags and fatten_count.
listate:
        bsr.s   listate2
        move.l  li,a1
        move.w  LI_XSZ(a1),d0
        bra.s   hex4
listate2:
        move.l  li,a1
        move.w  LI_FLAGS(a1),d0
        bsr.s   hex4
        move.l  li,a1
        move.b  LI_FAT(a1),d0
        bra.s   hex2
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
; hex8(d0.l) / hex4(d0.w) / hex2(d0.b): hex digits and a space. Clobbers d0/d1/a0.
hex8:   moveq   #7,d1
        bra.s   hexn
hex4:   swap    d0
        moveq   #3,d1
        bra.s   hexn
hex2:   ror.l   #8,d0
        moveq   #1,d1
hexn:   lea     hbuf,a0
.dg:    rol.l   #4,d0
        move.l  d0,-(sp)
        and.w   #15,d0
        move.b  hexd(pc,d0.w),(a0)+
        move.l  (sp)+,d0
        dbra    d1,.dg
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bra.s   puts
hexd:   dc.b    "0123456789ABCDEF"
layname: dc.b   "layers.library",0
dosname: dc.b   "dos.library",0
conname: dc.b   "console.device",0
rawname: dc.b   "RAW:0/0/320/60/WFC",0
m_nli:  dc.b    13,10,"NLI ",0
m_fat:  dc.b    "FAT ",0
m_thn:  dc.b    "THN ",0
m_sl:   dc.b    "/ ",0
m_cdi:  dc.b    "CDI ",0
m_wfc:  dc.b    "WFC ",0
m_nl:   dc.b    13,10,0
m_end:  dc.b    "LMISC END",13,10,0
        even

        section bss,bss
execb:  ds.l    1
layb:   ds.l    1
dosb:   ds.l    1
li:     ds.l    1
outfh:  ds.l    1
r1:     ds.l    1
r2:     ds.l    1
hbuf:   ds.b    12
