; tests/alert_probe.s - black-box PROBE bootblock for intuition DisplayAlert (TEST ASSET, NOT ROM code).
; Assembled as a raw binary (vasm -Fbin -m68000 -DMODE=n), placed at offset +12 of an ADF bootblock by
; tests/alert_probe.sh. AUTHOR'S code: uses only the public ABI (exec_lib.fd, intuition_lib.fd, NDK structures)
; and the public hardware registers; only private read: the word IntuitionBase+$546 (width printed on serial).
;
; A VBlank server (pri -10) counts frames and logs every change of the first word of the alert's raster
; (address predicted by an AllocMem/FreeMem of the same size just before the call): this measures the
; blink period of the frame, in frames.
;   MODE 0: opens a 320x200x1 screen, then DisplayAlert(0, text, 40) [left click expected],
;           then DisplayAlert($80000000, text, 60) [right click expected].
;   MODE 1: DisplayAlert(0, text, 7000) (raster cannot be allocated): immediate return expected.
;   MODE 2: DisplayAlert($80000000, text, 7000): fallback to exec Alert() expected (reboot, Guru on next boot).
; Serial lines "@A", "@B", "@C": emitted just before each DisplayAlert (the harness captures, then clicks).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
MARK     EQU $60000
        IFND MODE
MODE    EQU 0
        ENDC

start:
        movea.l 4.w,a6
        lea     m_head(pc),a0
        bsr     puts
        move.l  0.w,d0
        bsr     hex8
        move.l  $100.w,d0
        bsr     hex8
        move.l  $104.w,d0
        bsr     hex8
        move.l  $202(a6),d0         ; LastAlert[0]
        bsr     hex8
        move.l  $206(a6),d0         ; LastAlert[1]
        bsr     hex8
        move.l  MARK,d0
        bsr     hex8
        bsr     nl
        cmp.l   #'ALPR',MARK
        beq     idle
        move.l  #'ALPR',MARK
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)            ; OpenLibrary
        movea.l d0,a5               ; A5 = IntuitionBase
        lea     m_ib(pc),a0
        bsr     puts
        move.l  a5,d0
        bsr     hex8
        moveq   #0,d0
        move.w  $546(a5),d0
        bsr     hex8
        bsr     nl
        ; log + Interrupt in a cleared chip block
        move.l  #1024,d0
        move.l  #$10003,d1
        jsr     -198(a6)            ; AllocMem
        movea.l d0,a4               ; A4 = log: 0 frames, 4 watched address, 8 last word, 12 index, 16.. entries
        lea     $3E0(a4),a1         ; struct Interrupt
        move.b  #2,8(a1)            ; NT_INTERRUPT
        move.b  #-10,9(a1)          ; pri
        move.l  a4,14(a1)           ; is_Data
        lea     srv(pc),a0
        move.l  a0,18(a1)           ; is_Code
        moveq   #5,d0               ; INTB_VERTB
        jsr     -168(a6)            ; AddIntServer
        IFEQ    MODE
        lea     scrtitle(pc),a0
        lea     newscr(pc),a1
        move.l  a0,20(a1)           ; DefaultTitle (address known only at run time)
        movea.l a1,a0
        exg     a5,a6
        jsr     -198(a6)            ; OpenScreen
        exg     a5,a6
        lea     m_scr(pc),a0
        bsr     puts
        bsr     hex8
        bsr     nl
        moveq   #'A',d4
        moveq   #0,d5
        moveq   #40,d6
        lea     txta(pc),a3
        bsr     test
        moveq   #'B',d4
        move.l  #$80000000,d5
        moveq   #60,d6
        lea     txtb(pc),a3
        bsr     test
        ENDC
        IFEQ    MODE-1
        moveq   #'C',d4
        moveq   #0,d5
        move.l  #7000,d6
        lea     txta(pc),a3
        bsr     test
        ENDC
        IFEQ    MODE-2
        moveq   #'C',d4
        move.l  #$80000000,d5
        move.l  #7000,d6
        lea     txta(pc),a3
        bsr     test
        ENDC
idle:   lea     m_idle(pc),a0
        bsr     puts
.w:     bra.s   .w

; test: D4 = letter, D5 = code, D6 = height, A3 = text. Predicts the raster address (80 bytes per line).
test:   move.l  d6,d0
        mulu    #80,d0
        move.l  d0,d7
        moveq   #2,d1               ; MEMF_CHIP
        jsr     -198(a6)
        move.l  d0,4(a4)
        beq.s   .na
        movea.l d0,a1
        move.l  d7,d0
        jsr     -210(a6)            ; FreeMem
.na:    clr.l   12(a4)
        move.w  #$5555,8(a4)
        moveq   #'@',d0
        bsr     putc
        move.l  d4,d0
        bsr     putc
        moveq   #' ',d0
        bsr     putc
        move.l  4(a4),d0
        bsr     hex8
        move.l  (a4),d0
        bsr     hex8
        bsr     nl
        move.l  d5,d0
        movea.l a3,a0
        move.l  d6,d1
        exg     a5,a6
        jsr     -90(a6)             ; DisplayAlert
        exg     a5,a6
        move.l  d0,d3
        lea     m_res(pc),a0
        bsr     puts
        move.l  d3,d0
        bsr     hex8
        move.l  (a4),d0
        bsr     hex8
        move.w  $DFF002,d0          ; DMACONR
        bsr     hex8
        bsr     nl
        moveq   #0,d2
.lg:    cmp.l   12(a4),d2
        bcc.s   .le
        move.l  16(a4,d2.l),d0      ; frame.w | word.w
        bsr     hex8
        addq.l  #4,d2
        bra.s   .lg
.le:    bra     nl

; VBlank server: A1 = log
srv:    addq.l  #1,(a1)
        move.l  4(a1),d0
        beq.s   .x
        movea.l d0,a0
        move.w  (a0),d0
        cmp.w   8(a1),d0
        beq.s   .x
        move.w  d0,8(a1)
        move.l  12(a1),d1
        cmp.w   #240,d1
        bcc.s   .x
        move.w  2(a1),16(a1,d1.w)
        move.w  d0,18(a1,d1.w)
        addq.l  #4,12(a1)
.x:     moveq   #0,d0
        rts

hex8:   movem.l d0-d2,-(a7)
        move.l  d0,d2
        moveq   #7,d1
.h:     rol.l   #4,d2
        move.b  d2,d0
        and.b   #$F,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .o
        addq.b  #7,d0
.o:     bsr.s   putc
        dbra    d1,.h
        moveq   #' ',d0
        bsr.s   putc
        movem.l (a7)+,d0-d2
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

newscr: dc.w    0,0,320,200,1       ; Left, Top, Width, Height, Depth
        dc.b    0,1                 ; DetailPen, BlockPen
        dc.w    0,$000F             ; ViewModes, Type CUSTOMSCREEN
        dc.l    0,0                 ; Font, DefaultTitle (set at run time)
        dc.l    0,0                 ; Gadgets, CustomBitMap
; text A: two lines + one line at x >= 256 (x on 16 bits)
txta:   dc.b    0,38,15,"LIGNE1 X38 Y15",0,$FF
        dc.b    1,$30,15,"X304",0,$01
        dc.b    0,142,30,"LIGNE2 X142 Y30 0123456789",0,0
txtb:   dc.b    0,6,10,"DEADEND Y10",0,1
        dc.b    0,6,50,"Y50 BAS",0,0
intname: dc.b   "intuition.library",0
scrtitle: dc.b  "SONDE",0
m_head: dc.b    "ALP low0 100 104 LA0 LA1 mark ",0
m_ib:   dc.b    "IB base w546 ",0
m_scr:  dc.b    "SCR ",0
m_res:  dc.b    "RES d0 trames dmaconr / journal(trame.mot) ",13,10,0
m_idle: dc.b    "IDLE",13,10,0
        even
