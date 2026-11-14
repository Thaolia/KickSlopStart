; src/exec/diag.s - power-on diagnostic of the cold path, and the screen of a CPU exception taken before exec's own
; vectors are installed. IMPLEMENTATION track: designed from public hardware documentation (HRM register map, the
; Wikipedia description of the later Kickstarts' colour test); the real 1.3 runs no such test (coldstart-hardware-v34
; §1.3) and its only coldstart colours are grey, green and yellow, so our colours are deliberately different
; (README "Power-on diagnostic").
;
; diag_run (cold path only: everything it writes is zeroed by coldstart's CLRMEM afterwards) tests the chip RAM, then
; shows a text screen and tests Agnus (beam counter, blitter), Paula (INTENA, ADKCON), the two CIAs (timer A) and the
; ROM checksum. Passed: the display is switched off again and the boot goes on. Failed: the screen stays, its
; background in the colour of the first failed class, the power LED blinks and the left mouse button restarts the
; machine. A chip RAM fault leaves no RAM for a screen: only the colour (and a report on the serial port).
                include "exec.i"

                xdef    diag_vectors
                xdef    diag_run
                xref    font8x8
                xref    kss_idstr

DG_VPOSR        EQU CUSTOM+$004
DG_DMACONR      EQU CUSTOM+$002
DG_ADKCONR      EQU CUSTOM+$010
DG_BLTCON0      EQU CUSTOM+$040
DG_BLTCON1      EQU CUSTOM+$042
DG_BLTAFWM      EQU CUSTOM+$044
DG_BLTDPT       EQU CUSTOM+$054
DG_BLTSIZE      EQU CUSTOM+$058
DG_BLTDMOD      EQU CUSTOM+$066
DG_COP1LC       EQU CUSTOM+$080
DG_COPJMP1      EQU CUSTOM+$088
DG_DIWSTRT      EQU CUSTOM+$08E
DG_DIWSTOP      EQU CUSTOM+$090
DG_DDFSTRT      EQU CUSTOM+$092
DG_DDFSTOP      EQU CUSTOM+$094
DG_ADKCON       EQU CUSTOM+$09E
DG_BPLCON0      EQU CUSTOM+$100
DG_BPLCON1      EQU CUSTOM+$102
DG_BPLCON2      EQU CUSTOM+$104
DG_BPL1MOD      EQU CUSTOM+$108
DG_COLOR01      EQU CUSTOM+$182
DG_CIAA         EQU $BFE001
DG_CIAB         EQU $BFD000

; Low chip RAM the diagnostic uses (above the boot stack; zeroed by the cold path afterwards).
DG_COP          EQU $3800                ; copper list: the two plane pointer halves, then the end
DG_FLAGS        EQU $3880                ; byte: bit 0 = copy the text to the serial port
DG_SCRATCH      EQU $3900                ; word written by the blitter test
DG_TBASE        EQU $4000                ; the RAM tests start here; below: vectors, low variables, boot stack
DG_PLANE        EQU $4000                ; 640 x 200, one plane
DG_ROWBYTES     EQU 80
DG_LINE         EQU DG_ROWBYTES*10       ; one text line: 8 glyph rows and 2 blank ones
DG_MINCHIP      EQU $80000               ; KickSlopStart needs 512 KB of chip RAM (coldstart clears that much)

; diag_vectors: points the exception vectors 2-47 at one stub each; the stub's address gives the vector number.
; exec replaces them with its own (init_ints). Clobbers d0/a0/a1.
diag_vectors:
        lea     ($8).w,a0
        lea     dg_stubs(pc),a1
        moveq   #46-1,d0
.dv:
        move.l  a1,(a0)+
        addq.l  #4,a1
        dbra    d0,.dv
        rts
dg_stubs:
        rept    46
        bsr.w   dg_exc
        endr

; dg_exc: a CPU exception before exec's vectors. The stub's return address gives the vector; on a 68000 a bus or
; address error pushes 8 more bytes before SR and PC. Never returns.
dg_exc:
        move.w  #$2700,sr
        move.l  (sp)+,d6
        sub.l   #dg_stubs+4,d6
        lsr.l   #2,d6
        addq.l  #2,d6                ; d6 = vector number
        cmp.w   #4,d6
        bhs     .ex_frame
        addq.l  #8,sp
.ex_frame:
        move.w  (sp),d5              ; SR
        move.l  2(sp),d7             ; PC
        move.l  #STACKTOP,sp
        move.w  #SERPER_RAW,SERPER
        move.b  #1,DG_FLAGS
        move.w  #DG_CPU,d4
        bsr     dg_screen
        lea     dg_t_exc(pc),a0
        bsr     dg_puts
        bsr     dg_nl
        lea     dg_t_vec(pc),a0
        bsr     dg_puts
        move.l  d6,d0
        bsr     dg_dec
        lea     dg_vnames(pc),a0
        moveq   #2,d0
.ex_name:
        cmp.w   d6,d0
        beq     .ex_named
        tst.b   (a0)
        beq     .ex_pc
.ex_skip:
        tst.b   (a0)+
        bne     .ex_skip
        addq.w  #1,d0
        bra     .ex_name
.ex_named:
        tst.b   (a0)
        beq     .ex_pc
        move.l  a0,-(sp)
        lea     dg_t_open(pc),a0
        bsr     dg_puts
        move.l  (sp)+,a0
        bsr     dg_puts
        moveq   #')',d0
        bsr     dg_putc
.ex_pc:
        bsr     dg_nl
        lea     dg_t_pc(pc),a0
        bsr     dg_puts
        move.l  d7,d0
        moveq   #8,d1
        bsr     dg_hex
        lea     dg_t_sr(pc),a0
        bsr     dg_puts
        move.w  d5,d0
        moveq   #4,d1
        bsr     dg_hex
        bsr     dg_nl
        bsr     dg_nl
        bra     dg_failed

; diag_run: the cold-path test (see the file header). Preserves every register when everything passes.
diag_run:
        movem.l d0-d7/a0-a6,-(sp)
        sub.l   a3,a3                ; no screen yet
                ifeq    PROD
        move.b  #1,DG_FLAGS          ; dev ROM: the whole report on the serial port too
                else
        clr.b   DG_FLAGS             ; production ROM: only a failure goes to the serial port
                endc
                ifeq    DIAG_FAKE-7
        illegal                      ; test build: an exception before exec's vectors
                endc
        bsr     dg_chip
        tst.l   d0
        beq     .dr_chipok
        move.w  #DG_CHIP,COLOR00     ; no RAM to draw in: the colour and the serial port only
        move.b  #1,DG_FLAGS
        lea     dg_t_chipbad(pc),a0
        bsr     dg_puts
        subq.l  #1,d0
        bne     .dr_fault
        lea     dg_t_small(pc),a0
        bsr     dg_puts
        move.l  d1,d0
        moveq   #10,d1
        lsr.l   d1,d0
        bsr     dg_dec
        lea     dg_t_kb(pc),a0
        bsr     dg_puts
        bra     .dr_chipend
.dr_fault:
        lea     dg_t_at(pc),a0
        bsr     dg_puts
        move.l  d2,d0
        moveq   #6,d1
        bsr     dg_hex
        lea     dg_t_wrote(pc),a0
        bsr     dg_puts
        move.l  d3,d0
        moveq   #8,d1
        bsr     dg_hex
        lea     dg_t_read(pc),a0
        bsr     dg_puts
        move.l  d4,d0
        moveq   #8,d1
        bsr     dg_hex
.dr_chipend:
        bsr     dg_nl
        bra     dg_halt
.dr_chipok:
        move.l  d1,d7                ; d7 = chip size
        move.w  #DG_OK,d4
        bsr     dg_screen
        lea     kss_idstr,a0         ; "KickSlopStart v..."

        bsr     dg_puts
        lea     dg_t_title2(pc),a0
        bsr     dg_puts
        bsr     dg_nl
        bsr     dg_nl
        moveq   #0,d6                ; d6 = colour of the first failure, 0 = none
        lea     dg_t_ram(pc),a0
        bsr     dg_puts
        lea     dg_t_ok(pc),a0
        bsr     dg_puts
        lea     dg_t_open(pc),a0
        bsr     dg_puts
        move.l  d7,d0
        moveq   #10,d1
        lsr.l   d1,d0
        bsr     dg_dec
        lea     dg_t_kbc(pc),a0
        bsr     dg_puts
        bsr     dg_nl
        lea     dg_t_beam(pc),a0
        lea     dg_beam(pc),a1
        bsr     dg_item
        lea     dg_t_blit(pc),a0
        lea     dg_blit(pc),a1
        bsr     dg_item
        lea     dg_t_paula(pc),a0
        lea     dg_paula(pc),a1
        bsr     dg_item
        lea     dg_t_ciaa(pc),a0
        lea     dg_ciaa(pc),a1
        bsr     dg_item
        lea     dg_t_ciab(pc),a0
        lea     dg_ciab(pc),a1
        bsr     dg_item
        lea     dg_t_rom(pc),a0
        bsr     dg_puts
        bsr     dg_romsum
        beq     .dr_romok
        tst.w   d6
        bne     .dr_romc
        move.w  #DG_ROM,d6
.dr_romc:
        move.l  d0,-(sp)
        lea     dg_t_rom(pc),a0
        bsr     dg_serlabel
        lea     dg_t_bad(pc),a0
        bsr     dg_puts
        lea     dg_t_sum(pc),a0
        bsr     dg_puts
        move.l  (sp)+,d0
        moveq   #8,d1
        bsr     dg_hex
        moveq   #')',d0
        bsr     dg_putc
        bra     .dr_romend
.dr_romok:
        lea     dg_t_ok(pc),a0
        bsr     dg_puts
.dr_romend:
        bsr     dg_nl
        bsr     dg_nl
        tst.w   d6
        bne     .dr_fail
                ifeq    PROD
        lea     dg_t_pass(pc),a0     ; dev ROM: the serial marker of a passed test
        bsr     dg_puts
        bsr     dg_nl
                endc
        move.w  #$7FFF,DMACON        ; display off again, as the coldstart left it
        move.w  #$0200,DG_BPLCON0
        move.w  #C_BOOT3,COLOR00
        movem.l (sp)+,d0-d7/a0-a6
        rts
.dr_fail:
        move.w  d6,COLOR00
        move.b  #1,DG_FLAGS
        bra     dg_failed

; dg_item(a0 = label, a1 = test, d6 = first failure colour): prints the label, runs the test (-> d0 = 0 passed, else
; the colour of its class) and prints OK or FAILED (a failure also on the serial port). Clobbers d0-d5/a0-a2.
dg_item:
        move.l  a0,a2
        bsr     dg_puts
        jsr     (a1)
        tst.w   d0
        beq     .it_ok
        tst.w   d6
        bne     .it_bad
        move.w  d0,d6
.it_bad:
        move.l  a2,a0
        bsr     dg_serlabel
        lea     dg_t_bad(pc),a0
        bra     .it_out
.it_ok:
        lea     dg_t_ok(pc),a0
.it_out:
        bsr     dg_puts
        bra     dg_nl

; dg_failed: the screen shows a failure; the restart line is added, then dg_halt.
dg_failed:
        lea     dg_t_restart(pc),a0
        bsr     dg_puts
        bsr     dg_nl

; dg_halt: the power LED blinks; the left mouse button (released first) restarts the machine through the RESET
; instruction in front of coldstart. CPU delays only: a dead Agnus stops the beam.
dg_halt:
        move.w  #$2700,sr
.hl_rel:
        btst    #6,DG_CIAA
        beq     .hl_rel
.hl_lp:
        bchg    #1,DG_CIAA
        move.l  #120000,d0
.hl_wait:
        btst    #6,DG_CIAA
        beq     .hl_reset
        subq.l  #1,d0
        bne     .hl_wait
        bra     .hl_lp
.hl_reset:
        lea     ROMBASE+$D0,a0       ; RESET, then coldstart
        jmp     (a0)

; dg_chip -> d0 = 0 and d1 = chip RAM size; d0 = 1 and d1 = size below DG_MINCHIP; d0 = 2 and d2 = address, d3 =
; written, d4 = read for a data, address or cell fault. Every long it writes is put back. Clobbers d1-d7/a0-a2.
dg_chip:
        ifeq    DIAG_FAKE-1
        moveq   #2,d0                ; test build: a cell fault
        move.l  #$012340,d2
        move.l  #$A55A5AA5,d3
        move.l  #$A55A5AA4,d4
        rts
        endc
        lea     DG_TBASE,a0
        move.l  (a0),d5
        move.l  #$40000,d1           ; size: the first 256 KB step that is missing or mirrors the bottom
.sz:
        cmp.l   #$200000,d1
        beq     .szend
        lea     0(a0,d1.l),a1
        move.l  (a1),d6
        move.l  #$5AA5C33C,(a1)
        clr.l   (a0)                 ; also drives the bus to 0: a missing RAM does not read the pattern back
        move.l  (a1),d2
        move.l  d6,(a1)
        cmp.l   #$5AA5C33C,d2
        bne     .szend
        add.l   #$40000,d1
        bra     .sz
.szend:
        move.l  d5,(a0)
        cmp.l   #DG_MINCHIP,d1
        bhs     .data
        moveq   #1,d0
        rts
.data:                               ; data lines: fixed patterns and a walking one at the base, bus driven between
        lea     dg_pats(pc),a2
        moveq   #4-1,d7
.dp:
        move.l  (a2)+,d3
        bsr     .cell
        bne     .bad
        dbra    d7,.dp
        moveq   #1,d3
.dw:
        bsr     .cell
        bne     .bad
        add.l   d3,d3
        bne     .dw
        moveq   #2,d2                ; address lines: a different value at the base + 2^n, all written before any
        move.l  sp,a2                ; is read; the old values on the stack
.ad_save:
        moveq   #1,d3
        lsl.l   d2,d3
        lea     0(a0,d3.l),a1
        cmpa.l  d1,a1
        bhs     .ad_fill
        move.l  (a1),-(sp)
        addq.w  #1,d2
        bra     .ad_save
.ad_fill:
        move.l  d2,d6                ; d6 = first exponent past the size
        move.l  (a0),-(sp)
        move.l  #$C0DE0000,(a0)
        moveq   #2,d2
.ad_wr:
        cmp.w   d6,d2
        beq     .ad_chk
        moveq   #1,d3
        lsl.l   d2,d3
        move.l  d2,d4
        or.l    #$C0DE0000,d4
        move.l  d4,0(a0,d3.l)
        addq.w  #1,d2
        bra     .ad_wr
.ad_chk:
        moveq   #0,d0
        move.l  (a0),d4
        move.l  #$C0DE0000,d3
        move.l  a0,d2
        cmp.l   d3,d4
        bne     .ad_rest
        moveq   #2,d5
.ad_rd:
        cmp.w   d6,d5
        beq     .ad_rest
        moveq   #1,d2
        lsl.l   d5,d2
        move.l  d5,d3
        or.l    #$C0DE0000,d3
        move.l  0(a0,d2.l),d4
        add.l   a0,d2
        cmp.l   d3,d4
        bne     .ad_bad
        addq.w  #1,d5
        bra     .ad_rd
.ad_bad:
        moveq   #2,d0
.ad_rest:
        move.l  (sp)+,(a0)           ; the old values back, from the highest address down
        move.l  d6,d5
.ad_put:
        subq.w  #1,d5
        cmp.w   #2,d5
        blo     .ad_done
        moveq   #1,d7
        lsl.l   d5,d7
        move.l  (sp)+,0(a0,d7.l)
        bra     .ad_put
.ad_done:
        tst.l   d0
        bne     .ret
        move.l  a0,a1                ; cells: one long every 256 bytes up to the top, two patterns each
.sw:
        move.l  (a1),d5
        move.l  #$A55A5AA5,d3
        move.l  d3,(a1)
        move.l  (a1),d4
        cmp.l   d3,d4
        bne     .sw_bad
        not.l   d3
        move.l  d3,(a1)
        move.l  (a1),d4
        cmp.l   d3,d4
        bne     .sw_bad
        move.l  d5,(a1)
        lea     256(a1),a1
        cmpa.l  d1,a1
        blo     .sw
        moveq   #0,d0
.ret:
        rts
.sw_bad:
        move.l  d5,(a1)
        move.l  a1,d2
        moveq   #2,d0
        rts
.bad:
        move.l  a0,d2
        moveq   #2,d0
        rts
; .cell(d3 = pattern, a0 = base): writes it, drives the bus with its complement elsewhere, reads it back.
; -> Z = 1 when it matches; d4 = value read. The old long is put back.
.cell:
        move.l  (a0),d5
        move.l  d3,(a0)
        move.l  d3,d4
        not.l   d4
        move.l  4(a0),-(sp)
        move.l  d4,4(a0)
        move.l  (sp)+,4(a0)
        move.l  (a0),d4
        move.l  d5,(a0)
        cmp.l   d3,d4
        rts

dg_pats:
        dc.l    $00000000,$FFFFFFFF,$55555555,$AAAAAAAA

; dg_beam -> d0 = 0 when the vertical beam counter moves (Agnus), else DG_CUSTOM. Clobbers d1/d2.
dg_beam:
        ifeq    DIAG_FAKE-2
        move.w  #DG_CUSTOM,d0        ; test build: Agnus fault
        rts
        endc
        move.l  DG_VPOSR,d1
        lsr.l   #8,d1
        and.w   #$1FF,d1
        move.l  #20000,d2
.bm:
        move.l  DG_VPOSR,d0
        lsr.l   #8,d0
        and.w   #$1FF,d0
        cmp.w   d1,d0
        bne     .bm_ok
        subq.l  #1,d2
        bne     .bm
        move.w  #DG_CUSTOM,d0
        rts
.bm_ok:
        moveq   #0,d0
        rts

; dg_blit -> d0 = 0 when two one-word blits (D = 0, then D = $FFFF) land in chip RAM and the blitter ends, else
; DG_CUSTOM. The blitter DMA is switched off again. Clobbers d1/d2.
dg_blit:
        move.w  #$1234,DG_SCRATCH
        move.w  #$8240,DMACON
        move.w  #$0100,d1            ; USED, minterm 0
        moveq   #0,d2
        bsr     .one
        bne     .bad
        move.w  #$01FF,d1            ; USED, minterm $FF
        moveq   #-1,d2
        bsr     .one
        bne     .bad
        moveq   #0,d0
        bra     .end
.bad:
        move.w  #DG_CUSTOM,d0
.end:
        move.w  #$0040,DMACON
        rts
.one:
        move.l  #-1,DG_BLTAFWM
        move.w  d1,DG_BLTCON0
        clr.w   DG_BLTCON1
        move.l  #DG_SCRATCH,DG_BLTDPT
        clr.w   DG_BLTDMOD
        move.w  #(1<<6)|1,DG_BLTSIZE
        move.l  #100000,d0
        btst    #6,DG_DMACONR        ; the first BBUSY read may lag the start
.wt:
        btst    #6,DG_DMACONR
        beq     .done
        subq.l  #1,d0
        bne     .wt
        moveq   #-1,d0
        rts
.done:
        cmp.w   DG_SCRATCH,d2
        rts

; dg_paula -> d0 = 0 when INTENA/INTENAR and ADKCON/ADKCONR keep two patterns each, else DG_CUSTOM. INTENA is left
; all clear (as coldstart leaves it), ADKCON as it was. Clobbers d1-d3.
dg_paula:
        ifeq    DIAG_FAKE-4
        move.w  #DG_CUSTOM,d0        ; test build: Paula fault
        rts
        endc
        move.w  DG_ADKCONR,d3
        moveq   #0,d0
        move.w  #$2AAA,d1
        bsr     .int
        move.w  #$1555,d1
        bsr     .int
        move.w  #$00AA,d1            ; audio attach bits only: no UART break, no disk settings
        bsr     .adk
        move.w  #$0055,d1
        bsr     .adk
        move.w  #$7FFF,INTENA
        move.w  #$7FFF,DG_ADKCON
        or.w    #$8000,d3
        move.w  d3,DG_ADKCON
        rts
.int:
        move.w  #$7FFF,INTENA
        move.w  d1,d2
        or.w    #$8000,d2
        move.w  d2,INTENA
        move.w  INTENAR,d2
        and.w   #$7FFF,d2
        cmp.w   d1,d2
        beq     .ok
        move.w  #DG_CUSTOM,d0
.ok:
        rts
.adk:
        move.w  #$00FF,DG_ADKCON
        move.w  d1,d2
        or.w    #$8000,d2
        move.w  d2,DG_ADKCON
        move.w  DG_ADKCONR,d2
        and.w   #$00FF,d2
        cmp.w   d1,d2
        beq     .ok
        move.w  #DG_CUSTOM,d0
        rts

; dg_ciaa / dg_ciab -> d0 = 0 when timer A counts down, else DG_CUSTOM. Afterwards the timer is stopped, its other
; CRA bits as they were, and the counter reloaded from the power-up latch $FFFF. Clobbers d1-d3/a1.
dg_ciaa:
        ifeq    DIAG_FAKE-5
        move.w  #DG_CUSTOM,d0        ; test build: CIA-A fault
        rts
        endc
        lea     DG_CIAA,a1
        bra     dg_cia
dg_ciab:
        lea     DG_CIAB,a1
dg_cia:
        move.b  CIA_CRA(a1),d3
        and.b   #$EE,d3              ; START and LOAD off: the restore below
        move.b  d3,CIA_CRA(a1)
        st      CIA_TALO(a1)
        st      CIA_TAHI(a1)
        move.b  d3,d1
        and.b   #$C6,d1              ; TODIN, SPMODE, OUTMODE, PBON kept; E clock, continuous
        or.b    #$11,d1              ; force load, start
        move.b  d1,CIA_CRA(a1)
        move.b  CIA_TALO(a1),d1
        move.w  #200,d2
.cw:
        dbra    d2,.cw
        move.b  CIA_TALO(a1),d2
        move.b  d3,CIA_CRA(a1)
        or.b    #$10,d3
        move.b  d3,CIA_CRA(a1)       ; stopped, counter = latch again
        moveq   #0,d0
        cmp.b   d1,d2
        bne     .cr
        move.w  #DG_CUSTOM,d0
.cr:
        rts

; dg_romsum -> Z = 1 when the end-around-carry sum of the 65,536 longs of the image is $FFFFFFFF (the checksum
; romtool and the ROM's last-but-one long maintain); d0 = the sum. Clobbers d1/d2/a0.
dg_romsum:
        lea     ROMBASE,a0
        moveq   #0,d0
        moveq   #0,d2
        move.w  #65536/8-1,d1
.rs:
        rept    8
        add.l   (a0)+,d0
        addx.l  d2,d0
        endr
        dbra    d1,.rs
        ifeq    DIAG_FAKE-6
        addq.l  #1,d0                ; test build: a corrupted image
        endc
        cmp.l   #-1,d0
        rts

; dg_screen(d4 = background colour): a 640 x 200 one-plane text screen in low chip RAM, white text. The text
; cursor starts on its first line: a3 = line start, a4 = output address. Clobbers d0/d1/a0.
dg_screen:
        move.w  #$7FFF,DMACON
        move.w  d4,COLOR00
        move.w  #$0FFF,DG_COLOR01
        lea     DG_PLANE,a0
        move.w  #(DG_ROWBYTES*200)/4-1,d0
.cl:
        clr.l   (a0)+
        dbra    d0,.cl
        lea     DG_COP,a0
        move.l  #DG_PLANE,d0
        move.w  #$00E0,(a0)+         ; BPL1PTH
        swap    d0
        move.w  d0,(a0)+
        move.w  #$00E2,(a0)+         ; BPL1PTL
        swap    d0
        move.w  d0,(a0)+
        move.l  #$FFFFFFFE,(a0)
        move.w  #$2C81,DG_DIWSTRT
        move.w  #$F4C1,DG_DIWSTOP
        move.w  #$003C,DG_DDFSTRT
        move.w  #$00D4,DG_DDFSTOP
        move.w  #$9200,DG_BPLCON0    ; high resolution, one plane, colour
        clr.w   DG_BPLCON1
        clr.w   DG_BPLCON2
        clr.w   DG_BPL1MOD
        move.l  #DG_COP,DG_COP1LC
        move.w  d0,DG_COPJMP1
        move.w  #$8380,DMACON        ; DMA, bitplanes, copper
        lea     DG_PLANE+DG_LINE,a3
        lea     2(a3),a4
        rts

; dg_nl: next text line (screen and serial). dg_puts(a0 = text): prints a NUL-terminated string. dg_putc(d0.b).
; The screen part only runs once dg_screen has set a3/a4 (a3 = 0 before). Preserve everything but a0 (dg_puts).
dg_nl:
        move.l  d0,-(sp)
        moveq   #13,d0
        bsr     dg_ser
        moveq   #10,d0
        bsr     dg_ser
        cmpa.l  #DG_PLANE,a3
        blo     .nl_end
        lea     DG_LINE(a3),a3
        lea     2(a3),a4
.nl_end:
        move.l  (sp)+,d0
        rts
dg_puts:
        move.l  d0,-(sp)
.ps:
        move.b  (a0)+,d0
        beq     .ps_end
        bsr     dg_putc
        bra     .ps
.ps_end:
        move.l  (sp)+,d0
        rts
dg_putc:
        movem.l d0/a0-a1,-(sp)
        bsr     dg_ser
        cmpa.l  #DG_PLANE,a3         ; no screen yet (chip RAM report)
        blo     .pc_end
        and.w   #$FF,d0
        sub.w   #$20,d0
        cmp.w   #$5F,d0
        bls     .pc_g
        moveq   #'?'-$20,d0
.pc_g:
        lsl.w   #3,d0
        lea     font8x8,a0
        add.w   d0,a0
        move.l  a4,a1
        moveq   #8-1,d0
.pc_row:
        move.b  (a0)+,(a1)
        lea     DG_ROWBYTES(a1),a1
        dbra    d0,.pc_row
        addq.l  #1,a4
.pc_end:
        movem.l (sp)+,d0/a0-a1
        rts
; dg_serlabel(a0 = label): a failure goes to the serial port too; when the report was not copied there so far
; (production ROM), the failed test's label is sent first. Clobbers a0.
dg_serlabel:
        btst    #0,DG_FLAGS
        bne     .sl_end
        move.b  #1,DG_FLAGS
        move.l  d0,-(sp)
.sl_lp:
        move.b  (a0)+,d0
        beq     .sl_out
        bsr     dg_ser
        bra     .sl_lp
.sl_out:
        move.l  (sp)+,d0
.sl_end:
        rts
; dg_ser(d0.b): to the serial port when DG_FLAGS bit 0 is set (polled, bounded wait). Preserves everything.
dg_ser:
        btst    #0,DG_FLAGS
        beq     .se_end
        move.l  d1,-(sp)
        move.w  #$4000,d1
.se_wt:
        btst    #13-8,SERDATR
        dbne    d1,.se_wt
        move.w  d0,-(sp)
        and.w   #$FF,(sp)
        or.w    #$100,(sp)
        move.w  (sp)+,SERDAT
        move.l  (sp)+,d1
.se_end:
        rts

; dg_hex(d0 = value, d1 = digits) / dg_dec(d0.w = value): print a number. Preserve everything.
dg_hex:
        movem.l d0-d2,-(sp)
        move.l  d0,d2
        moveq   #'$',d0
        bsr     dg_putc
        moveq   #8,d0
        sub.w   d1,d0
        lsl.w   #2,d0
        rol.l   d0,d2
        subq.w  #1,d1
.hx:
        rol.l   #4,d2
        move.b  d2,d0
        and.b   #$F,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls     .hx_d
        addq.b  #'A'-'9'-1,d0
.hx_d:
        bsr     dg_putc
        dbra    d1,.hx
        movem.l (sp)+,d0-d2
        rts
dg_dec:
        movem.l d0-d2,-(sp)
        and.l   #$FFFF,d0
        moveq   #0,d2                ; digits pushed
.dc_div:
        divu    #10,d0
        swap    d0
        move.w  d0,-(sp)
        clr.w   d0
        swap    d0
        addq.w  #1,d2
        tst.w   d0
        bne     .dc_div
.dc_out:
        move.w  (sp)+,d0
        add.b   #'0',d0
        bsr     dg_putc
        subq.w  #1,d2
        bne     .dc_out
        movem.l (sp)+,d0-d2
        rts

dg_t_title2:    dc.b    " - power-on diagnostic",0
dg_t_ram:       dc.b    "Chip RAM   data, address, cells . ",0
dg_t_kb:        dc.b    " KB",0
dg_t_kbc:       dc.b    " KB)",0
dg_t_beam:      dc.b    "Agnus      beam counter ......... ",0
dg_t_blit:      dc.b    "Agnus      blitter .............. ",0
dg_t_paula:     dc.b    "Paula      INTENA, ADKCON ....... ",0
dg_t_ciaa:      dc.b    "CIA-A      timer A .............. ",0
dg_t_ciab:      dc.b    "CIA-B      timer A .............. ",0
dg_t_rom:       dc.b    "ROM        checksum ............. ",0
dg_t_ok:        dc.b    "OK",0
dg_t_bad:       dc.b    "FAILED",0
dg_t_sum:       dc.b    " (sum ",0
dg_t_pass:      dc.b    "DIAG OK",0
dg_t_restart:   dc.b    "Left mouse button: restart.",0
dg_t_chipbad:   dc.b    "KickSlopStart diagnostic: chip RAM FAILED",0
dg_t_small:     dc.b    ": only ",0
dg_t_at:        dc.b    " at ",0
dg_t_wrote:     dc.b    ", wrote ",0
dg_t_read:      dc.b    ", read ",0
dg_t_exc:       dc.b    "KickSlopStart: CPU exception before exec was ready",0
dg_t_vec:       dc.b    "Vector ",0
dg_t_open:      dc.b    " (",0
dg_t_pc:        dc.b    "PC ",0
dg_t_sr:        dc.b    "  SR ",0
; names of vectors 2, 3, ... (an empty one ends the list)
dg_vnames:      dc.b    "bus error",0,"address error",0,"illegal instruction",0,"divide by zero",0
                dc.b    "CHK",0,"TRAPV",0,"privilege violation",0,"trace",0,"line-A opcode",0
                dc.b    "line-F opcode",0,0
                even
