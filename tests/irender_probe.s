; tests/irender_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "intuition rendering" (docs/analysis/intuition-render-v34.md §8, expected values §7):
; DrawBorder, DrawImage, PrintIText, IntuiTextLength and SetWindowTitles through their public LVOs.
; Run from the startup-sequence of a floppy without SetPatch and without devs:system-configuration
; (tests/irender_probe.sh). Results go to the direct serial port (SERDAT).
; Test BitMap: 64 x 32, up to 3 planes (BytesPerRow 8, 256 bytes per plane) in CHIP, between two 512-byte guards.
; Header per test: "<id> fg bg dm mk cp fl 1f lp ys th as f8" = FgPen BgPen DrawMode Mask cp_x,cp_y Flags, byte +$1F,
; LinePtrn, rp_Font YSize, TxHeight, AlgoStyle, rp_Font == the topaz 8 font set before the call (1/0).
; Before every BitMap test, Flags and the byte +$1F are cleared after the Move, so that the RastPort restore is seen.
; Border/image rows: "<y> <one colour digit per x>" ('.' = 0). Text tests print only per-colour bounding boxes and
; pixel counts (" c:x0-x1,y0-y1=n"), never glyph rows. Screen rows are printed as colour runs " x0-x1:c".
; No italic and no negative x on the layerless BitMap (§5): the italic test runs in a window RastPort.
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -m68000 -o build/irender_probe tests/irender_probe.s
; Authored code; public structures (intuition/intuition.h, screens.h, graphics/rastport.h, gfx.h, text.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
O_G0     EQU 0           ; guard before the planes (512 bytes)
O_PL0    EQU 512         ; plane 0 (256 bytes)
O_PL1    EQU 768         ; plane 1
O_PL2    EQU 1024        ; plane 2
O_G1     EQU 1280        ; guard after the planes (512 bytes)
O_IMG    EQU 1792        ; P1 P0 P1 P2, 6 bytes each (§7.2 data)
O_P0     EQU O_IMG+6
O_P1     EQU O_IMG+12
O_P1B    EQU O_IMG
O_D8     EQU 1816        ; DI8: 2 rows of 2 words
CHIPSZ   EQU 1824
GUARD    EQU $A5

; intuition LVOs checked against AROS rom/intuition/intuition.conf (bias 30, 6 bytes per slot)
LVO_CloseScreen      EQU -66
LVO_CloseWindow      EQU -72
LVO_DrawBorder       EQU -108
LVO_DrawImage        EQU -114
LVO_OpenScreen       EQU -198
LVO_OpenWindow       EQU -204
LVO_PrintIText       EQU -216
LVO_SetWindowTitles  EQU -276
LVO_ShowTitle        EQU -282
LVO_IntuiTextLength  EQU -330
LVO_ActivateWindow   EQU -450
; graphics LVOs checked against AROS rom/graphics/graphics.conf
LVO_SetFont      EQU -66
LVO_OpenFont     EQU -72
LVO_CloseFont    EQU -78
LVO_SetSoftStyle EQU -90
LVO_InitRastPort EQU -198
LVO_WaitBlit     EQU -228
LVO_Move         EQU -240
LVO_SetAPen      EQU -342
LVO_SetBPen      EQU -348
LVO_SetDrMd      EQU -354
LVO_InitBitMap   EQU -390
; exec / dos LVOs checked against AROS rom/exec/exec.conf, rom/dos/dos.conf
LVO_Forbid       EQU -132
LVO_Permit       EQU -138
LVO_AllocMem     EQU -198
LVO_FreeMem      EQU -210
LVO_AvailMem     EQU -216
LVO_CloseLibrary EQU -414
LVO_OpenLibrary  EQU -552
LVO_Delay        EQU -222

; RastPort (rastport.h)
RP_BM    EQU $04
RP_MASK  EQU $18
RP_FG    EQU $19
RP_BG    EQU $1A
RP_MODE  EQU $1C
RP_PC    EQU $1F
RP_FLAGS EQU $20
RP_LPTRN EQU $22
RP_CPX   EQU $24
RP_CPY   EQU $26
RP_FONT  EQU $34
RP_ALGO  EQU $38
RP_TXH   EQU $3A
TF_YSIZE EQU $14
TF_ACC   EQU $1E
GB_DFONT EQU $9A         ; GfxBase.DefaultFont
; Screen / Window (intuition.h, screens.h)
SC_FLAGS EQU 20
SC_TITLE EQU 22
SC_BARH  EQU 30
SC_BARVB EQU 31
SC_BARHB EQU 32
SC_WBORT EQU 35
SC_WBORL EQU 36
SC_FONT  EQU 40
SC_BM    EQU 184
WD_LEFT  EQU 4
WD_TOP   EQU 6
WD_WIDTH EQU 8
WD_FLAGS EQU 24
WD_TITLE EQU 32
WD_SCR   EQU 46
WD_RPORT EQU 50
WD_BT    EQU 55
WD_STIT  EQU 104
NW_SCR   EQU 30

GFX             macro
                move.l  gfxb-vars(a4),a6
                endm
INT             macro
                move.l  intb-vars(a4),a6
                endm
; --- BORD id,border,dx,dy,mask,lineptrn: DrawBorder on 2 planes filled 0, JAM2, Move(40,14); rows 0..13 x 0..47
BORD             macro
                moveq   #2,d0
                moveq   #0,d1
                moveq   #1,d2
                moveq   #40,d3
                moveq   #14,d4
                bsr     setup
                move.b  #\5,rp+RP_MASK-vars(a4)
                move.w  #\6,rp+RP_LPTRN-vars(a4)
                lea     rp-vars(a4),a0
                move.l  #\2,a1
                move.l  #\3,d0
                move.l  #\4,d1
                INT
                jsr     LVO_DrawBorder(a6)
                lea     \1(pc),a0
                bsr     hdrt
                moveq   #0,d6
                moveq   #13,d7
                moveq   #48,d5
                bsr     rows
                endm
; --- IMAG id,image,dx,dy,fill,mask,mode: DrawImage on 3 planes, Move(40,10); rows 1..5 x 0..31
IMAG             macro
                moveq   #3,d0
                moveq   #\5,d1
                moveq   #\7,d2
                moveq   #40,d3
                moveq   #10,d4
                bsr     setup
                move.b  #\6,rp+RP_MASK-vars(a4)
                lea     rp-vars(a4),a0
                move.l  #\2,a1
                move.l  #\3,d0
                move.l  #\4,d1
                INT
                jsr     LVO_DrawImage(a6)
                lea     \1(pc),a0
                bsr     hdrt
                moveq   #1,d6
                moveq   #5,d7
                moveq   #32,d5
                bsr     rows
                endm
; --- ITXT id,itext,dx,dy,fill,mask,algo: PrintIText on 2 planes, rp topaz 8, Fg 3 Bg 0 JAM1, Move(50,20); boxes
ITXT             macro
                moveq   #2,d0
                moveq   #\5,d1
                moveq   #0,d2
                moveq   #50,d3
                moveq   #20,d4
                bsr     setup
                move.b  #\6,rp+RP_MASK-vars(a4)
                moveq   #\7,d0
                bsr     algo
                lea     rp-vars(a4),a0
                move.l  #\2,a1
                move.l  #\3,d0
                move.l  #\4,d1
                INT
                jsr     LVO_PrintIText(a6)
                lea     \1(pc),a0
                bsr     hdrt
                bsr     bmbox
                endm
; --- ITL label,itext: "label=<dec>" of IntuiTextLength
ITL             macro
                lea     \1(pc),a0
                bsr     puts
                lea     \2-vars(a4),a0
                INT
                jsr     LVO_IntuiTextLength(a6)
                bsr     pdec
                bsr     nl
                endm
; --- SWT label,window,title,stitle (pointers: label in vars, or -1/0 given as #imm through \3 \4 macros below)
SWT             macro
                move.l  \2-vars(a4),a0
                \3
                \4
                INT
                jsr     LVO_SetWindowTitles(a6)
                lea     \1(pc),a0
                bsr     puts
                move.l  \2-vars(a4),a3
                bsr     titles
                endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  4.w,a6
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,gfxb-vars(a4)
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,intb-vars(a4)
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     LVO_OpenLibrary(a6)
                move.l  d0,dosb-vars(a4)
                tst.l   gfxb-vars(a4)
                beq     .out
                tst.l   intb-vars(a4)
                beq     .out
                tst.l   dosb-vars(a4)
                beq     .out
                move.l  #CHIPSZ,d0
                move.l  #$10002,d1
                jsr     LVO_AllocMem(a6)
                move.l  d0,chip-vars(a4)
                beq     .out
                move.l  d0,a5
                lea     m_start(pc),a0
                bsr     puts
                bsr     initchip

; --- fonts: DefaultFont size, topaz 8 and 9 opened for the whole run
                GFX
                lea     m_dflt(pc),a0
                bsr     puts
                move.l  GB_DFONT(a6),a0
                move.w  TF_YSIZE(a0),d0
                bsr     pdec
                lea     ta8-vars(a4),a0
                jsr     LVO_OpenFont(a6)
                move.l  d0,t8-vars(a4)
                lea     ta9-vars(a4),a0
                jsr     LVO_OpenFont(a6)
                move.l  d0,t9-vars(a4)
                lea     m_t8(pc),a0
                bsr     puts
                move.l  t8-vars(a4),a0
                bsr     fys
                lea     m_t9(pc),a0
                bsr     puts
                move.l  t9-vars(a4),a0
                bsr     fys
                bsr     nl

; --- R0 registers of DrawBorder, DrawImage, PrintIText, IntuiTextLength (SetWindowTitles in R5)
                moveq   #2,d0
                moveq   #0,d1
                moveq   #1,d2
                moveq   #40,d3
                moveq   #14,d4
                bsr     setup
                lea     rp-vars(a4),a0
                lea     db9-vars(a4),a1
                move.l  #LVO_DrawBorder,d7
                lea     m_r0db(pc),a3
                bsr     regcall
                moveq   #3,d0
                moveq   #0,d1
                moveq   #1,d2
                moveq   #40,d3
                moveq   #10,d4
                bsr     setup
                lea     rp-vars(a4),a0
                lea     di1-vars(a4),a1
                move.l  #LVO_DrawImage,d7
                lea     m_r0di(pc),a3
                bsr     regcall
                moveq   #2,d0
                moveq   #0,d1
                moveq   #0,d2
                moveq   #50,d3
                moveq   #20,d4
                bsr     setup
                lea     rp-vars(a4),a0
                lea     pt3-vars(a4),a1
                move.l  #LVO_PrintIText,d7
                lea     m_r0pt(pc),a3
                bsr     regcall
                lea     tl1-vars(a4),a0
                move.l  #LVO_IntuiTextLength,d7
                lea     m_r0tl(pc),a3
                bsr     regcall

; --- R1 DrawBorder (§7.1)
                lea     m_r1(pc),a0
                bsr     puts
                BORD     m_db0,dbnull,0,0,$FF,$FFFF
                BORD     m_db1,db1,4,1,1,$FFFF
                BORD     m_db2,db2,0,0,$FF,$FFFF
                BORD     m_db3,db3,0,0,$FF,$FFFF
                BORD     m_db4,db4,0,0,$FF,$FFFF
                BORD     m_db4b,db4b,0,0,$FF,$FFFF
                BORD     m_db5,db5,2,0,$FF,$FFFF
                BORD     m_db6,db6,5,-1,$FF,$FFFF
                BORD     m_db7,db7,0,0,$FF,$F0F0
                BORD     m_db8,db8,0,0,$FF,$FFFF
                BORD     m_db9,db9,0,0,$FF,$FFFF
                BORD     m_db10,db10,0,0,1,$FFFF

; --- R2 DrawImage (§7.2), image L2 T1 + offsets (1,1) = (3,2)
                lea     m_r2(pc),a0
                bsr     puts
                IMAG     m_di1,di1,1,1,7,$FF,1
                IMAG     m_di2,di2,1,1,0,$FF,1
                IMAG     m_di3,di3,1,1,0,$FF,1
                IMAG     m_di4,di4,1,1,0,$FF,1
                IMAG     m_di5,di5,1,1,0,$FF,1
                IMAG     m_di6,di6,1,1,0,1,1
                IMAG     m_di7,di7,3,2,0,$FF,1
                IMAG     m_di8,di8,1,1,0,$FF,1
                IMAG     m_di9,di9,1,1,0,$FF,1
                IMAG     m_di10,di10,1,1,7,$FF,1
                IMAG     m_di11,di11,1,1,0,$FF,1
                IMAG     m_di12,di12,1,1,0,$FF,2
                IMAG     m_di13,dinull,1,1,0,$FF,1
; AvailMem(MEMF_CHIP) around DrawImage DI2 (two unpicked planes: zero and ones planes allocated), twice
                moveq   #1,d7
.av:            move.l  4.w,a6
                moveq   #2,d1
                jsr     LVO_AvailMem(a6)
                move.l  d0,d6
                lea     rp-vars(a4),a0
                lea     di2-vars(a4),a1
                moveq   #1,d0
                moveq   #1,d1
                INT
                jsr     LVO_DrawImage(a6)
                GFX
                jsr     LVO_WaitBlit(a6)
                move.l  4.w,a6
                moveq   #2,d1
                jsr     LVO_AvailMem(a6)
                move.l  d0,d5
                lea     m_av(pc),a0
                bsr     puts
                move.l  d6,d0
                bsr     phex8
                lea     m_after(pc),a0
                bsr     puts
                move.l  d5,d0
                bsr     phex8
                lea     m_diff(pc),a0
                bsr     puts
                move.l  d6,d0
                sub.l   d5,d0
                bsr     phex8
                bsr     nl
                dbra    d7,.av

; --- R3 PrintIText (§7.3), rp font topaz 8
                lea     m_r3(pc),a0
                bsr     puts
                ITXT     m_pt1,pt1,3,4,0,1,0
                ITXT     m_pt2a,pt2a,0,0,0,$FF,0
                ITXT     m_pt2,pt2,0,0,0,$FF,0
                ITXT     m_pt3a,pt3,0,0,0,$FF,0
                bsr     bmrow7
                ITXT     m_pt3b,pt3,0,0,0,$FF,2
                bsr     bmrow7
                ITXT     m_pt4,pt4,0,0,0,$FF,0
                ITXT     m_pt5,pt5,2,1,0,$FF,0
                ITXT     m_pt6,pt6,2,1,0,$FF,0
                ITXT     m_pt7,pt7,0,0,3,$FF,0
                ITXT     m_pt8,pt8,0,0,0,$FF,0
                ITXT     m_pt10,pt10,0,0,0,$FF,2

; --- R4 IntuiTextLength (§7.4)
                lea     m_r4(pc),a0
                bsr     puts
                ITL     m_tl1,tl1
                lea     m_acc9(pc),a0
                bsr     puts
                move.l  t9-vars(a4),a0
                bsr     facc
                bsr     nl
                ITL     m_tl2,tl2
                lea     m_acc9(pc),a0
                bsr     puts
                move.l  t9-vars(a4),a0
                bsr     facc
                bsr     nl
                ITL     m_tl3,tl3
                ITL     m_tl4,tl4
                ITL     m_tl5,tl5
                ITL     m_tl6,tl6
                ITL     m_tl7,tl7
                move.l  t9-vars(a4),d0
                lea     m_tl8(pc),a0
                bsr     dfswap
                move.l  t8-vars(a4),d0
                lea     m_tl8b(pc),a0
                bsr     dfswap

                bsr     r5

; --- end: guards, fonts, memory
                lea     m_guard(pc),a0
                bsr     puts
                lea     O_G0(a5),a0
                move.w  #511,d1
                moveq   #0,d0
.g0:            cmp.b   #GUARD,(a0)+
                beq.s   .g0n
                addq.w  #1,d0
.g0n:           dbra    d1,.g0
                lea     O_G1(a5),a0
                move.w  #511,d1
.g1:            cmp.b   #GUARD,(a0)+
                beq.s   .g1n
                addq.w  #1,d0
.g1n:           dbra    d1,.g1
                bsr     pdec
                bsr     nl
                GFX
                jsr     LVO_WaitBlit(a6)
                move.l  t8-vars(a4),d0
                beq.s   .nc8
                move.l  d0,a1
                jsr     LVO_CloseFont(a6)
.nc8:           move.l  t9-vars(a4),d0
                beq.s   .nc9
                move.l  d0,a1
                jsr     LVO_CloseFont(a6)
.nc9:           lea     m_end(pc),a0
                bsr     puts
                move.l  4.w,a6
                move.l  a5,a1
                move.l  #CHIPSZ,d0
                jsr     LVO_FreeMem(a6)
.out:           move.l  4.w,a6
                move.l  dosb-vars(a4),d0
                beq.s   .o1
                move.l  d0,a1
                jsr     LVO_CloseLibrary(a6)
.o1:            move.l  intb-vars(a4),d0
                beq.s   .o2
                move.l  d0,a1
                jsr     LVO_CloseLibrary(a6)
.o2:            move.l  gfxb-vars(a4),d0
                beq.s   .o3
                move.l  d0,a1
                jsr     LVO_CloseLibrary(a6)
.o3:            movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- R5 SetWindowTitles, R0 for it, R6 layer clipping, italic PrintIText in a window
r5:             lea     m_r5(pc),a0
                bsr     puts
                INT
                lea     nscr-vars(a4),a0
                jsr     LVO_OpenScreen(a6)
                move.l  d0,scr-vars(a4)
                beq     .noscr
                move.l  d0,a3
                lea     m_scr(pc),a0
                bsr     puts
                moveq   #0,d0
                move.b  SC_BARH(a3),d0
                bsr     pdec
                bsr     sp1
                move.b  SC_BARVB(a3),d0
                bsr     pdec
                bsr     sp1
                move.b  SC_BARHB(a3),d0
                bsr     pdec
                bsr     sp1
                move.l  SC_FONT(a3),a0
                move.w  4(a0),d0
                bsr     pdec
                lea     m_wbor(pc),a0
                bsr     puts
                move.b  SC_WBORT(a3),d0
                bsr     pdec
                bsr     sp1
                move.b  SC_WBORL(a3),d0
                bsr     pdec
                bsr     sflags
                move.l  a3,nw1+NW_SCR-vars(a4)
                move.l  a3,nw2+NW_SCR-vars(a4)
                move.l  a3,nwbd+NW_SCR-vars(a4)
                lea     nw1-vars(a4),a0
                jsr     LVO_OpenWindow(a6)
                move.l  d0,win-vars(a4)
                beq     .now
                moveq   #25,d1
                bsr     delay
                move.l  win-vars(a4),a3
                lea     m_open(pc),a0
                bsr     puts
                bsr     titles
                lea     m_bt(pc),a0
                bsr     puts
                moveq   #0,d0
                move.b  WD_BT(a3),d0
                bsr     pdec
                bsr     nl
                bsr     wrows

                SWT     m_a1,win,<lea s_changed(pc),a1>,<move.l #-1,a2>
                bsr     wrows
                SWT     m_a2,win,<move.l #-1,a1>,<lea s_scrt(pc),a2>
                bsr     srows
                SWT     m_a3,win,<move.l #-1,a1>,<sub.l a2,a2>
                bsr     srows
                SWT     m_a4,win,<sub.l a1,a1>,<move.l #-1,a2>
                bsr     wrows
                bsr     gsum
                move.l  d0,sum0-vars(a4)
                SWT     m_a5,win,<lea s_long(pc),a1>,<lea s_back(pc),a2>
                bsr     wrows
                bsr     gsum
                lea     m_gsum(pc),a0
                bsr     puts
                cmp.l   sum0-vars(a4),d0
                seq     d0
                and.w   #1,d0
                bsr     pdec
                bsr     nl
                bsr     ssum
                move.l  d0,d6
                SWT     m_a6,win,<move.l #-1,a1>,<move.l #-1,a2>
                bsr     ssum
                bsr     psame

; R0 for SetWindowTitles: (w, "R0", -1)
                move.l  win-vars(a4),a0
                lea     s_r0(pc),a1
                move.l  #-1,a2
                move.l  #LVO_SetWindowTitles,d7
                lea     m_r0sw(pc),a3
                bsr     regcall2

; R6 DrawImage clipped by the window layer
                lea     m_r6(pc),a0
                bsr     puts
                move.l  win-vars(a4),a3
                move.l  WD_RPORT(a3),a0
                lea     isol3-vars(a4),a1
                moveq   #-4,d0
                moveq   #20,d1
                INT
                jsr     LVO_DrawImage(a6)
                move.l  win-vars(a4),a3
                move.l  WD_RPORT(a3),a0
                lea     isol2-vars(a4),a1
                move.w  WD_WIDTH(a3),d0
                subq.w  #6,d0
                ext.l   d0
                moveq   #30,d1
                INT
                jsr     LVO_DrawImage(a6)
                lea     m_w20(pc),a0
                moveq   #20,d1
                bsr     wrun
                lea     m_w30(pc),a0
                moveq   #30,d1
                bsr     wrun

; PT9 italic topaz 8 at (8,40) vs plain at (8,60) in the window RastPort (layer)
                move.l  win-vars(a4),a3
                move.l  WD_RPORT(a3),a1
                clr.w   RP_FLAGS(a1)
                clr.b   RP_PC(a1)
                lea     m_pt9pre(pc),a0
                bsr     hdr
                move.l  win-vars(a4),a3
                move.l  WD_RPORT(a3),a0
                lea     pt9-vars(a4),a1
                moveq   #8,d0
                moveq   #40,d1
                INT
                jsr     LVO_PrintIText(a6)
                move.l  win-vars(a4),a3
                move.l  WD_RPORT(a3),a1
                lea     m_pt9(pc),a0
                bsr     hdr
                moveq   #40,d0
                bsr     wbox
                moveq   #40,d0
                bsr     wtop
                move.l  win-vars(a4),a3
                move.l  WD_RPORT(a3),a0
                lea     pt9p-vars(a4),a1
                moveq   #8,d0
                moveq   #60,d1
                INT
                jsr     LVO_PrintIText(a6)
                lea     m_pt9p(pc),a0
                bsr     puts
                moveq   #60,d0
                bsr     wbox
                moveq   #60,d0
                bsr     wtop

; B1: another window active, then titles on the inactive test window
                INT
                lea     nw2-vars(a4),a0
                jsr     LVO_OpenWindow(a6)
                move.l  d0,win2-vars(a4)
                beq     .now2
                move.l  d0,a0
                jsr     LVO_ActivateWindow(a6)
                moveq   #25,d1
                bsr     delay
                lea     m_b1pre(pc),a0
                bsr     puts
                move.l  win-vars(a4),a3
                bsr     titles
                SWT     m_b1,win,<lea s_inact(pc),a1>,<lea s_scr2(pc),a2>
                bsr     wrows
                INT
                lea     nwbd-vars(a4),a0
                jsr     LVO_OpenWindow(a6)
                move.l  d0,bdw-vars(a4)
                beq     .nobd
                moveq   #10,d1
                bsr     delay
                lea     m_bdbt(pc),a0
                bsr     puts
                move.l  bdw-vars(a4),a3
                moveq   #0,d0
                move.b  WD_BT(a3),d0
                bsr     pdec
                bsr     nl
                bsr     ssum
                move.l  d0,d6
                SWT     m_b2,bdw,<lea s_x(pc),a1>,<move.l #-1,a2>
                bsr     ssum
                bsr     psame
                INT
                move.l  win-vars(a4),a0
                jsr     LVO_ActivateWindow(a6)
                moveq   #25,d1
                bsr     delay
                lea     m_b3(pc),a0
                bsr     puts
                move.l  win-vars(a4),a3
                bsr     titles

; S1: ShowTitle(FALSE) then a screen title on the active backdrop window, ShowTitle(TRUE)
                INT
                move.l  bdw-vars(a4),a0
                jsr     LVO_ActivateWindow(a6)
                moveq   #25,d1
                bsr     delay
                lea     m_s0(pc),a0
                bsr     puts
                bsr     sflags
                INT
                move.l  scr-vars(a4),a0
                moveq   #0,d0
                jsr     LVO_ShowTitle(a6)
                SWT     m_s1,bdw,<move.l #-1,a1>,<lea s_hid(pc),a2>
                bsr     sflags
                bsr     srows
                INT
                move.l  scr-vars(a4),a0
                moveq   #1,d0
                jsr     LVO_ShowTitle(a6)
                moveq   #10,d1
                bsr     delay
                lea     m_s2(pc),a0
                bsr     puts
                bsr     sflags
                bsr     srows

                INT
                move.l  bdw-vars(a4),a0
                jsr     LVO_CloseWindow(a6)
.nobd:          INT
                move.l  win2-vars(a4),a0
                jsr     LVO_CloseWindow(a6)
.now2:          INT
                move.l  win-vars(a4),a0
                jsr     LVO_CloseWindow(a6)
.now:           INT
                move.l  scr-vars(a4),a0
                jsr     LVO_CloseScreen(a6)
                lea     m_closed(pc),a0
                bsr     puts
                bsr     phex8
                bsr     nl
                rts
.noscr:         lea     m_noscr(pc),a0
                bra     puts

; --- initchip: guards, image data (§7.2)
initchip:       lea     O_G0(a5),a0
                move.w  #511,d0
.a:             move.b  #GUARD,(a0)+
                dbra    d0,.a
                lea     O_G1(a5),a0
                move.w  #511,d0
.b:             move.b  #GUARD,(a0)+
                dbra    d0,.b
                lea     O_IMG(a5),a0
                lea     imgdata(pc),a1
                moveq   #(O_D8+8-O_IMG)/2-1,d0
.c:             move.w  (a1)+,(a0)+
                dbra    d0,.c
                lea     dfix(pc),a0
.d:             move.w  (a0)+,d0
                bmi.s   .e
                move.w  (a0)+,d1
                lea     0(a5,d1.w),a1
                move.l  a1,10(a4,d0.w)
                bra.s   .d
.e:             rts

; --- setup(d0 depth, d1 fill colour, d2 mode, d3 cp_x, d4 cp_y): test BitMap and rp (topaz 8, Fg 3, Bg 0)
setup:          movem.l d0-d4,-(sp)
                GFX
                jsr     LVO_WaitBlit(a6)
                movem.l (sp),d0-d4
                lea     bm-vars(a4),a0
                moveq   #64,d1
                moveq   #32,d2
                jsr     LVO_InitBitMap(a6)
                lea     bm+8-vars(a4),a0
                lea     O_PL0(a5),a1
                move.l  a1,(a0)+
                lea     O_PL1(a5),a1
                move.l  a1,(a0)+
                lea     O_PL2(a5),a1
                move.l  a1,(a0)+
                movem.l (sp),d0-d4
                lea     O_PL0(a5),a0
                moveq   #2,d2
.pl:            moveq   #0,d3
                lsr.b   #1,d1
                bcc.s   .f
                moveq   #-1,d3
.f:             move.w  #63,d0
.fl:            move.l  d3,(a0)+
                dbra    d0,.fl
                dbra    d2,.pl
                lea     rp-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     bm-vars(a4),a0
                move.l  a0,rp+RP_BM-vars(a4)
                move.l  t8-vars(a4),d0
                beq.s   .nf
                move.l  d0,a0
                lea     rp-vars(a4),a1
                jsr     LVO_SetFont(a6)
.nf:            lea     rp-vars(a4),a1
                moveq   #3,d0
                jsr     LVO_SetAPen(a6)
                lea     rp-vars(a4),a1
                moveq   #0,d0
                jsr     LVO_SetBPen(a6)
                movem.l (sp),d0-d4
                move.l  d2,d0
                lea     rp-vars(a4),a1
                jsr     LVO_SetDrMd(a6)
                movem.l (sp)+,d0-d4
                lea     rp-vars(a4),a1
                move.l  d3,d0
                move.l  d4,d1
                jsr     LVO_Move(a6)
                clr.w   rp+RP_FLAGS-vars(a4)
                clr.b   rp+RP_PC-vars(a4)
                rts

; --- algo(d0 style): SetSoftStyle(rp, style, $FF) when style != 0
algo:           tst.b   d0
                beq.s   .r
                GFX
                moveq   #-1,d1
                lea     rp-vars(a4),a1
                jsr     LVO_SetSoftStyle(a6)
.r:             rts

; --- dfswap(d0 font, a0 label): DefaultFont := font under Forbid, IntuiTextLength(tl1), restore
dfswap:         bsr     puts
                move.l  d0,d5
                beq.s   .z
                move.l  4.w,a6
                jsr     LVO_Forbid(a6)
                GFX
                move.l  GB_DFONT(a6),d6
                move.l  d5,GB_DFONT(a6)
                lea     tl1-vars(a4),a0
                INT
                jsr     LVO_IntuiTextLength(a6)
                move.l  d0,d7
                GFX
                move.l  d6,GB_DFONT(a6)
                move.l  4.w,a6
                jsr     LVO_Permit(a6)
                move.l  d7,d0
                bsr     pdec
.z:             bra     nl

; --- regcall(a0, a1 args, d7 LVO, a3 label): D0 D1 = 0 0 (DrawBorder etc. offsets), markers elsewhere
; regcall2: same with A2 as an argument. Prints the registers that changed and the returned D0.
regcall:        move.l  #$1111000A,a2
regcall2:       movem.l d2-d7/a2-a6,-(sp)
                move.l  a3,-(sp)
                move.l  a0,rin+32-vars(a4)
                move.l  a1,rin+36-vars(a4)
                move.l  a2,rin+40-vars(a4)
                clr.l   rin-vars(a4)
                clr.l   rin+4-vars(a4)
                lea     rin+8-vars(a4),a0
                moveq   #2,d0
.m:             move.l  d0,d1
                or.l    #$11110000,d1
                move.l  d1,(a0)+
                addq.w  #1,d0
                cmp.w   #8,d0
                blo.s   .m
                move.l  #$1111000B,rin+44-vars(a4)
                move.l  #$1111000C,rin+48-vars(a4)
                move.l  #$1111000D,rin+52-vars(a4)
                move.l  intb-vars(a4),a6
                move.l  a6,rin+56-vars(a4)
                add.l   a6,d7
                move.l  d7,rtarget-vars(a4)
                pea     .ret(pc)
                move.l  d7,-(sp)
                movem.l rin-vars(a4),d0-d7/a0-a6
                rts
.ret:           move.l  a4,-(sp)
                lea     vars(pc),a4
                movem.l d0-d7/a0-a3,rout-vars(a4)
                move.l  (sp)+,rout+48-vars(a4)
                move.l  a5,rout+52-vars(a4)
                move.l  a6,rout+56-vars(a4)
                move.l  (sp)+,a0
                bsr     puts
                lea     m_chg(pc),a0
                bsr     puts
                lea     rin-vars(a4),a0
                lea     rout-vars(a4),a1
                lea     rnames(pc),a2
                moveq   #14,d2
.c:             cmpm.l  (a0)+,(a1)+
                beq.s   .s
                bsr     sp1
                move.b  (a2),d1
                bsr     putc
                move.b  1(a2),d1
                bsr     putc
.s:             addq.l  #2,a2
                dbra    d2,.c
                lea     m_d0(pc),a0
                bsr     puts
                move.l  rout-vars(a4),d0
                bsr     phex8
                bsr     nl
                movem.l (sp)+,d2-d7/a2-a6
                rts
rnames:         dc.b    "D0D1D2D3D4D5D6D7A0A1A2A3A4A5A6"

; --- hdrt(a0 label): hdr of the test rp; hdr(a0 label, a1 rp)
hdrt:           lea     rp-vars(a4),a1
hdr:            move.l  a1,a3
                bsr     puts
                lea     m_fg(pc),a0
                bsr     puts
                move.b  RP_FG(a3),d0
                bsr     phex2
                lea     m_bg(pc),a0
                bsr     puts
                move.b  RP_BG(a3),d0
                bsr     phex2
                lea     m_dm(pc),a0
                bsr     puts
                move.b  RP_MODE(a3),d0
                bsr     phex2
                lea     m_mk(pc),a0
                bsr     puts
                move.b  RP_MASK(a3),d0
                bsr     phex2
                lea     m_cp(pc),a0
                bsr     puts
                move.w  RP_CPX(a3),d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  RP_CPY(a3),d0
                bsr     pdec
                lea     m_fl(pc),a0
                bsr     puts
                move.w  RP_FLAGS(a3),d0
                bsr     phex4
                lea     m_1f(pc),a0
                bsr     puts
                move.b  RP_PC(a3),d0
                bsr     phex2
                lea     m_lp(pc),a0
                bsr     puts
                move.w  RP_LPTRN(a3),d0
                bsr     phex4
                lea     m_ys(pc),a0
                bsr     puts
                move.l  RP_FONT(a3),a0
                bsr     fys
                lea     m_th(pc),a0
                bsr     puts
                move.w  RP_TXH(a3),d0
                bsr     pdec
                lea     m_as(pc),a0
                bsr     puts
                move.b  RP_ALGO(a3),d0
                bsr     phex2
                lea     m_f8(pc),a0
                bsr     puts
                move.l  RP_FONT(a3),d0
                cmp.l   t8-vars(a4),d0
                seq     d0
                and.w   #1,d0
                bsr     pdec
                bra     nl

; --- fys(a0 font or 0): YSize in decimal; facc(a0 font): accessors
fys:            moveq   #0,d0
                move.l  a0,d1
                beq.s   .p
                move.w  TF_YSIZE(a0),d0
.p:             bra     pdec
facc:           moveq   #0,d0
                move.l  a0,d1
                beq.s   .p
                move.w  TF_ACC(a0),d0
.p:             bra     pdec

; --- pixc(a2 BitMap, d0 x, d1 y) -> d2 colour
pixc:           movem.l d0/d1/d3-d5/a0/a1,-(sp)
                moveq   #0,d3
                move.w  (a2),d3
                mulu    d1,d3
                moveq   #0,d4
                move.w  d0,d4
                lsr.w   #3,d4
                add.l   d4,d3
                not.b   d0
                moveq   #0,d2
                moveq   #0,d5
                move.b  5(a2),d5
                lea     8(a2),a0
                moveq   #0,d4
                bra.s   .n
.p:             move.l  (a0)+,a1
                btst    d0,0(a1,d3.l)
                beq.s   .z
                bset    d4,d2
.z:             addq.w  #1,d4
.n:             dbra    d5,.p
                movem.l (sp)+,d0/d1/d3-d5/a0/a1
                rts

; --- wblit: WaitBlit, a6 kept
wblit:          move.l  a6,-(sp)
                GFX
                jsr     LVO_WaitBlit(a6)
                move.l  (sp)+,a6
                rts

; --- rows(d6 first y, d7 last y, d5 columns) of the test BitMap, one colour digit per pixel
rows:           bsr     wblit
                lea     bm-vars(a4),a2
.r:             move.w  d6,d0
                cmp.w   #10,d0
                bhs.s   .w
                bsr     sp1
.w:             bsr     pdec
                bsr     sp1
                moveq   #0,d0
.c:             move.w  d6,d1
                bsr     pixc
                moveq   #'.',d1
                tst.w   d2
                beq.s   .o
                moveq   #'0',d1
                add.w   d2,d1
.o:             bsr     putc
                addq.w  #1,d0
                cmp.w   d5,d0
                blo.s   .c
                bsr     nl
                addq.w  #1,d6
                cmp.w   d7,d6
                bls.s   .r
                rts

; --- runs(a2 BitMap, d1 y, d3 first x, d4 last x, d5 x bias): " x0-x1:c" with x - bias
runs:           movem.l d0-d7,-(sp)
                bsr     wblit
                move.w  d3,d0
                bsr     pixc
                move.w  d2,d6
                move.w  d3,d7
.l:             addq.w  #1,d0
                cmp.w   d4,d0
                bgt.s   .e
                bsr     pixc
                cmp.w   d2,d6
                beq.s   .l
                bsr.s   .pr
                move.w  d2,d6
                move.w  d0,d7
                bra.s   .l
.e:             bsr.s   .pr
                movem.l (sp)+,d0-d7
                rts
.pr:            movem.l d0/d1,-(sp)
                bsr     sp1
                move.w  d0,d3
                move.w  d7,d0
                sub.w   d5,d0
                bsr     pdec
                moveq   #'-',d1
                bsr     putc
                move.w  d3,d0
                subq.w  #1,d0
                sub.w   d5,d0
                bsr     pdec
                moveq   #':',d1
                bsr     putc
                move.w  d6,d0
                bsr     pdec
                movem.l (sp)+,d0/d1
                rts

; --- region(a2 BitMap; rx0 rx1 ry0 ry1 rbx rby in vars): " c:x0-x1,y0-y1=n" for each colour present
region:         movem.l d0-d7/a0-a3,-(sp)
                bsr     wblit
                lea     rtab-vars(a4),a0
                moveq   #7,d0
.i:             clr.l   (a0)+
                move.l  #$7FFF8000,(a0)+
                move.l  #$7FFF8000,(a0)+
                dbra    d0,.i
                lea     rtab-vars(a4),a0
                move.w  ry0-vars(a4),d1
.y:             move.w  rx0-vars(a4),d0
.x:             bsr     pixc
                move.w  d2,d3
                mulu    #12,d3
                lea     0(a0,d3.w),a1
                addq.l  #1,(a1)
                cmp.w   4(a1),d0
                bge.s   .a
                move.w  d0,4(a1)
.a:             cmp.w   6(a1),d0
                ble.s   .b
                move.w  d0,6(a1)
.b:             cmp.w   8(a1),d1
                bge.s   .c
                move.w  d1,8(a1)
.c:             cmp.w   10(a1),d1
                ble.s   .d
                move.w  d1,10(a1)
.d:             addq.w  #1,d0
                cmp.w   rx1-vars(a4),d0
                ble.s   .x
                addq.w  #1,d1
                cmp.w   ry1-vars(a4),d1
                ble.s   .y
                move.l  a0,a3
                moveq   #0,d7
.p:             tst.l   (a3)
                beq.s   .q
                bsr     sp1
                move.w  d7,d0
                bsr     pdec
                moveq   #':',d1
                bsr     putc
                move.w  4(a3),d0
                sub.w   rbx-vars(a4),d0
                bsr     pdec
                moveq   #'-',d1
                bsr     putc
                move.w  6(a3),d0
                sub.w   rbx-vars(a4),d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  8(a3),d0
                sub.w   rby-vars(a4),d0
                bsr     pdec
                moveq   #'-',d1
                bsr     putc
                move.w  10(a3),d0
                sub.w   rby-vars(a4),d0
                bsr     pdec
                moveq   #'=',d1
                bsr     putc
                move.l  (a3),d0
                bsr     pdecu
.q:             lea     12(a3),a3
                addq.w  #1,d7
                cmp.w   #8,d7
                blo.s   .p
                bsr     nl
                movem.l (sp)+,d0-d7/a0-a3
                rts

; --- bmbox: region of the whole test BitMap
bmbox:          clr.l   rx0-vars(a4)
                move.w  #63,rx1-vars(a4)
                clr.w   ry0-vars(a4)
                move.w  #31,ry1-vars(a4)
                clr.l   rbx-vars(a4)
                lea     m_box(pc),a0
                bsr     puts
                lea     bm-vars(a4),a2
                bra     region

; --- bmrow7: region of row 7 (below the topaz 8 baseline row 6) of the test BitMap
bmrow7:         move.w  #7,ry0-vars(a4)
                move.w  #7,ry1-vars(a4)
                lea     m_row7(pc),a0
                bsr     puts
                lea     bm-vars(a4),a2
                bra     region

; --- wbox(d0 window y): region of the test window, rows y..y+7, x 6..60, window-relative
wbox:           bsr     wbox0
                lea     m_box(pc),a0
                bsr     puts
                move.l  scr-vars(a4),a2
                lea     SC_BM(a2),a2
                bra     region
wbox0:          move.l  win-vars(a4),a3
                move.w  WD_TOP(a3),d1
                move.w  d1,rby-vars(a4)
                add.w   d1,d0
                move.w  d0,ry0-vars(a4)
                addq.w  #7,d0
                move.w  d0,ry1-vars(a4)
                move.w  WD_LEFT(a3),d1
                move.w  d1,rbx-vars(a4)
                addq.w  #6,d1
                move.w  d1,rx0-vars(a4)
                add.w   #54,d1
                move.w  d1,rx1-vars(a4)
                rts

; --- wtop(d0 window y): region of the single window row y, x 6..60, window-relative
wtop:           move.w  d0,-(sp)
                bsr     wbox0
                move.w  (sp)+,d0
                lea     m_top(pc),a0
                bsr     puts
                move.w  rby-vars(a4),d1
                add.w   d1,d0
                move.w  d0,ry0-vars(a4)
                move.w  d0,ry1-vars(a4)
                move.l  scr-vars(a4),a2
                lea     SC_BM(a2),a2
                bra     region

; --- wrun(a0 label, d1 window y): runs of a test-window row, x -10..W+9, window-relative
wrun:           move.w  d1,-(sp)
                bsr     puts
                move.w  (sp)+,d1
                move.l  win-vars(a4),a3
                add.w   WD_TOP(a3),d1
                move.w  WD_LEFT(a3),d5
                move.w  d5,d3
                sub.w   #10,d3
                move.w  d5,d4
                add.w   WD_WIDTH(a3),d4
                add.w   #9,d4
                move.l  scr-vars(a4),a2
                lea     SC_BM(a2),a2
                bsr     runs
                bra     nl

; --- wrows: title-bar rows 2 and 6 of the test window, x 0..W-1, window-relative
wrows:          moveq   #2,d6
.r:             lea     m_row(pc),a0
                bsr     puts
                move.w  d6,d0
                bsr     pdec
                move.l  win-vars(a4),a3
                move.w  d6,d1
                add.w   WD_TOP(a3),d1
                move.w  WD_LEFT(a3),d5
                move.w  d5,d3
                move.w  d5,d4
                add.w   WD_WIDTH(a3),d4
                subq.w  #1,d4
                move.l  scr-vars(a4),a2
                lea     SC_BM(a2),a2
                bsr     runs
                bsr     nl
                addq.w  #4,d6
                cmp.w   #6,d6
                bls.s   .r
                rts

; --- srows: screen rows 0, 4, 9, 10, x 0..319
srows:          lea     srowtab(pc),a3
.r:             moveq   #0,d6
                move.b  (a3)+,d6
                bmi.s   .e
                lea     m_srow(pc),a0
                bsr     puts
                move.w  d6,d0
                bsr     pdec
                move.w  d6,d1
                moveq   #0,d3
                move.w  #319,d4
                moveq   #0,d5
                move.l  scr-vars(a4),a2
                lea     SC_BM(a2),a2
                bsr     runs
                bsr     nl
                bra.s   .r
.e:             rts
srowtab:        dc.b    0,4,9,10,-1
                even

; --- sflags: " sflags=<hex4>" + newline
sflags:         lea     m_sfl(pc),a0
                bsr     puts
                move.l  scr-vars(a4),a3
                move.w  SC_FLAGS(a3),d0
                bsr     phex4
                bra     nl

; --- ssum -> d0: sum of the longwords of the screen BitMap planes
ssum:           bsr     wblit
                move.l  scr-vars(a4),a2
                lea     SC_BM(a2),a2
                moveq   #0,d0
                moveq   #0,d1
                move.b  5(a2),d1
                subq.w  #1,d1
                lea     8(a2),a1
.p:             move.l  (a1)+,a0
                move.w  (a2),d2
                mulu    2(a2),d2
                lsr.l   #2,d2
                subq.w  #1,d2
.l:             add.l   (a0)+,d0
                dbra    d2,.l
                dbra    d1,.p
                rts

; --- gsum -> d0: sum of the colours x (1 + x) over the depth-gadget area (W-54..W-1, rows 0..BT-1)
gsum:           bsr     wblit
                move.l  win-vars(a4),a3
                move.l  scr-vars(a4),a2
                lea     SC_BM(a2),a2
                moveq   #0,d5
                move.w  WD_TOP(a3),d1
                moveq   #0,d6
                move.b  WD_BT(a3),d6
                add.w   d1,d6
.y:             move.w  WD_LEFT(a3),d0
                add.w   WD_WIDTH(a3),d0
                move.w  d0,d7
                sub.w   #54,d0
.x:             bsr     pixc
                mulu    d0,d2
                add.l   d2,d5
                add.l   d2,d5
                addq.w  #1,d0
                cmp.w   d7,d0
                blo.s   .x
                addq.w  #1,d1
                cmp.w   d6,d1
                blo.s   .y
                move.l  d5,d0
                rts

; --- psame(d6 before, d0 after): " same=<1/0>"
psame:          lea     m_same(pc),a0
                bsr     puts
                cmp.l   d0,d6
                seq     d0
                and.w   #1,d0
                bsr     pdec
                bra     nl

; --- titles(a3 window): " wt=.. wst=.. st=.. act=<0/1>"
titles:         lea     m_wt(pc),a0
                bsr     puts
                move.l  WD_TITLE(a3),a0
                bsr     pstr
                lea     m_wst(pc),a0
                bsr     puts
                move.l  WD_STIT(a3),a0
                bsr     pstr
                lea     m_st(pc),a0
                bsr     puts
                move.l  WD_SCR(a3),a0
                move.l  SC_TITLE(a0),a0
                bsr     pstr
                lea     m_act(pc),a0
                bsr     puts
                move.w  WD_FLAGS+2(a3),d0
                lsr.w   #8,d0
                lsr.w   #5,d0
                and.w   #1,d0
                bsr     pdec
                bra     nl

; --- pstr(a0): "text" or NULL
pstr:           move.l  a0,d0
                bne.s   .s
                lea     m_null(pc),a0
                bra     puts
.s:             moveq   #'"',d1
                bsr     putc
                bsr     puts
                moveq   #'"',d1
                bra     putc

; --- delay(d1 ticks)
delay:          move.l  a6,-(sp)
                move.l  dosb-vars(a4),a6
                jsr     LVO_Delay(a6)
                move.l  (sp)+,a6
                rts

; --- printing helpers
nl:             moveq   #10,d1
                bra.s   putc
sp1:            moveq   #' ',d1
                bra.s   putc
; pdec: d0.w signed, in decimal
pdec:           ext.l   d0
                bpl.s   pdecu
                neg.l   d0
                moveq   #'-',d1
                bsr.s   putc
; pdecu: d0.l unsigned (< 655360), in decimal
pdecu:          divu    #10,d0
                move.l  d0,-(sp)
                and.l   #$FFFF,d0
                beq.s   .d
                bsr.s   pdecu
.d:             move.l  (sp)+,d0
                swap    d0
                add.b   #'0',d0
                move.b  d0,d1
putc:           move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
                rts
phex8:          swap    d0
                bsr.s   phex4
                swap    d0
phex4:          move.w  d0,-(sp)
                lsr.w   #8,d0
                bsr.s   phex2
                move.w  (sp)+,d0
phex2:          move.w  d0,-(sp)
                lsr.b   #4,d0
                bsr.s   .n
                move.w  (sp)+,d0
.n:             move.w  d0,-(sp)
                and.w   #$F,d0
                move.b  hexd(pc,d0.w),d1
                bsr.s   putc
                move.w  (sp)+,d0
                rts
hexd:           dc.b    "0123456789ABCDEF"
puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr.s   putc
                bra.s   puts
.e:             rts

; image data (§7.2): P1 P0 P1 P2, then the DI8 plane
imgdata:        dc.w    $2000,$7000,$2000
                dc.w    $F800,$8800,$F800
                dc.w    $2000,$7000,$2000
                dc.w    $FFFF,$0000,$FFFF
                dc.w    $AAAA,$F000,$5555,$F000
; ImageData fix-ups: Image offset in vars, data offset in the chip block; -1 ends
dfix:           dc.w    di1-vars,O_P0
                dc.w    di2-vars,O_P0
                dc.w    di4-vars,O_P0
                dc.w    di5-vars,O_P0
                dc.w    di6-vars,O_P0
                dc.w    di7-vars,O_P1B
                dc.w    di7b-vars,O_P0
                dc.w    di8-vars,O_D8
                dc.w    di9-vars,O_P0
                dc.w    di10-vars,O_P0
                dc.w    di11-vars,O_P0
                dc.w    di12-vars,O_P0
                dc.w    -1

gfxname:        dc.b    "graphics.library",0
intname:        dc.b    "intuition.library",0
dosname:        dc.b    "dos.library",0
s_topaz:        dc.b    "topaz.font",0
s_nosuch:       dc.b    "nosuch.font",0
s_ab:           dc.b    "AB",0
s_a:            dc.b    "A",0
s_b:            dc.b    "B",0
s_c:            dc.b    "C",0
s_mm:           dc.b    "MM",0
s_empty:        dc.b    0
s_hello:        dc.b    "Hello",0
s_more:         dc.b    "more text",0
s_hi:           dc.b    "Hi",0
s_scrdef:       dc.b    "Probe screen",0
s_wtitle:       dc.b    "Test window",0
s_other:        dc.b    "Other",0
s_changed:      dc.b    "Changed",0
s_scrt:         dc.b    "Screen T",0
s_long:         dc.b    "This window title is fifty-one characters long. OK!",0
s_back:         dc.b    "Back",0
s_r0:           dc.b    "R0",0
s_inact:        dc.b    "Inactive",0
s_scr2:         dc.b    "Scr2",0
s_x:            dc.b    "X",0
s_hid:          dc.b    "Hidden T",0
m_start:        dc.b    10,"IRP debut",10,0
m_dflt:         dc.b    "defaultfont ys=",0
m_t8:           dc.b    " topaz8=",0
m_t9:           dc.b    " topaz9=",0
m_r0db:         dc.b    "R0 DrawBorder",0
m_r0di:         dc.b    "R0 DrawImage",0
m_r0pt:         dc.b    "R0 PrintIText",0
m_r0tl:         dc.b    "R0 IntuiTextLength",0
m_r0sw:         dc.b    "R0 SetWindowTitles",0
m_chg:          dc.b    " chg=",0
m_d0:           dc.b    " d0=",0
m_r1:           dc.b    "R1 DrawBorder",10,0
m_db0:          dc.b    "DB0",0
m_db1:          dc.b    "DB1",0
m_db2:          dc.b    "DB2",0
m_db3:          dc.b    "DB3",0
m_db4:          dc.b    "DB4",0
m_db4b:         dc.b    "DB4b",0
m_db5:          dc.b    "DB5",0
m_db6:          dc.b    "DB6",0
m_db7:          dc.b    "DB7",0
m_db8:          dc.b    "DB8",0
m_db9:          dc.b    "DB9",0
m_db10:         dc.b    "DB10",0
m_r2:           dc.b    "R2 DrawImage",10,0
m_di1:          dc.b    "DI1",0
m_di2:          dc.b    "DI2",0
m_di3:          dc.b    "DI3",0
m_di4:          dc.b    "DI4",0
m_di5:          dc.b    "DI5",0
m_di6:          dc.b    "DI6",0
m_di7:          dc.b    "DI7",0
m_di8:          dc.b    "DI8",0
m_di9:          dc.b    "DI9",0
m_di10:         dc.b    "DI10",0
m_di11:         dc.b    "DI11",0
m_di12:         dc.b    "DI12",0
m_di13:         dc.b    "DI0 null",0
m_av:           dc.b    "AV chip before=",0
m_after:        dc.b    " after=",0
m_diff:         dc.b    " diff=",0
m_r3:           dc.b    "R3 PrintIText",10,0
m_pt1:          dc.b    "PT1",0
m_pt2a:         dc.b    "PT2a",0
m_pt2:          dc.b    "PT2",0
m_pt3a:         dc.b    "PT3a",0
m_pt3b:         dc.b    "PT3b",0
m_pt4:          dc.b    "PT4",0
m_pt5:          dc.b    "PT5",0
m_pt6:          dc.b    "PT6",0
m_pt7:          dc.b    "PT7",0
m_pt8:          dc.b    "PT8",0
m_pt10:         dc.b    "PT10 bold-rp topaz9-chain",0
m_pt9pre:       dc.b    "PT9 window rp before",0
m_pt9:          dc.b    "PT9 italic (8,40)",0
m_pt9p:         dc.b    "PT9 plain (8,60)",0
m_box:          dc.b    " box",0
m_r4:           dc.b    "R4 IntuiTextLength",10,0
m_tl1:          dc.b    "TL1 Hello null=",0
m_tl2:          dc.b    "TL2 Hello topaz9=",0
m_tl3:          dc.b    "TL3 Hello next=",0
m_tl4:          dc.b    "TL4 Hello topaz8 bold=",0
m_tl5:          dc.b    "TL5 empty=",0
m_tl6:          dc.b    "TL6 Hello nosuch=",0
m_tl7:          dc.b    "TL7 Hi L77 T9=",0
m_tl8:          dc.b    "TL8 Hello null dflt=topaz9 ",0
m_tl8b:         dc.b    "TL8b Hello null dflt=topaz8 ",0
m_acc9:         dc.b    " topaz9 acc=",0
m_r5:           dc.b    "R5 SetWindowTitles",10,0
m_scr:          dc.b    "screen barh/barvb/barhb/fontys=",0
m_wbor:         dc.b    " wbortop/left=",0
m_row7:         dc.b    " row7",0
m_top:          dc.b    " toprow",0
m_noscr:        dc.b    "OpenScreen failed",10,0
m_open:         dc.b    "open",0
m_bt:           dc.b    "win bt=",0
m_a1:           dc.b    "A1",0
m_a2:           dc.b    "A2",0
m_a3:           dc.b    "A3",0
m_a4:           dc.b    "A4",0
m_a5:           dc.b    "A5",0
m_a6:           dc.b    "A6",0
m_gsum:         dc.b    "A5 depth gadgets intact=",0
m_r6:           dc.b    "R6 DrawImage in window layer",10,0
m_w20:          dc.b    "R6 row20",0
m_w30:          dc.b    "R6 row30",0
m_b1pre:        dc.b    "B1 before",0
m_b1:           dc.b    "B1",0
m_bdbt:         dc.b    "backdrop bt=",0
m_b2:           dc.b    "B2",0
m_b3:           dc.b    "B3 after ActivateWindow(w)",0
m_s0:           dc.b    "S0 before showtitle",0
m_s1:           dc.b    "S1 showtitle false",0
m_s2:           dc.b    "S2 showtitle true",0
m_sfl:          dc.b    " sflags=",0
m_closed:       dc.b    "closescreen=",0
m_row:          dc.b    " wrow",0
m_srow:         dc.b    " srow",0
m_same:         dc.b    " screen unchanged=",0
m_wt:           dc.b    " wt=",0
m_wst:          dc.b    " wst=",0
m_st:           dc.b    " st=",0
m_act:          dc.b    " act=",0
m_null:         dc.b    "NULL",0
m_fg:           dc.b    " fg=",0
m_bg:           dc.b    " bg=",0
m_dm:           dc.b    " dm=",0
m_mk:           dc.b    " mk=",0
m_cp:           dc.b    " cp=",0
m_fl:           dc.b    " fl=",0
m_1f:           dc.b    " 1f=",0
m_lp:           dc.b    " lp=",0
m_ys:           dc.b    " ys=",0
m_th:           dc.b    " th=",0
m_as:           dc.b    " as=",0
m_f8:           dc.b    " f8=",0
m_guard:        dc.b    "guards bad bytes=",0
m_end:          dc.b    "IRP fin",10,0
                even

vars:
gfxb:           dc.l    0
intb:           dc.l    0
dosb:           dc.l    0
chip:           dc.l    0
t8:             dc.l    0
t9:             dc.l    0
scr:            dc.l    0
win:            dc.l    0
win2:           dc.l    0
bdw:            dc.l    0
rtarget:        dc.l    0
sum0:           dc.l    0
rin:            ds.l    15
rout:           ds.l    15
rx0:            dc.w    0
rx1:            dc.w    0
ry0:            dc.w    0
ry1:            dc.w    0
rbx:            dc.w    0
rby:            dc.w    0
rtab:           ds.b    8*12
bm:             ds.b    40
rp:             ds.b    100
; TextAttr: name, YSize, Style (FSF_UNDERLINED 1, FSF_BOLD 2, FSF_ITALIC 4), Flags
ta8:            dc.l    s_topaz
                dc.w    8
                dc.b    0,0
ta9:            dc.l    s_topaz
                dc.w    9
                dc.b    0,0
ta8b:           dc.l    s_topaz
                dc.w    8
                dc.b    2,0
ta8i:           dc.l    s_topaz
                dc.w    8
                dc.b    4,0
tanos:          dc.l    s_nosuch
                dc.w    8
                dc.b    0,0

; Border: LeftEdge, TopEdge, FrontPen, BackPen, DrawMode, Count, XY, NextBorder
dbnull          EQU     0
db1:            dc.w    2,3
                dc.b    1,2,0,3
                dc.l    xy1,0
db2:            dc.w    2,3
                dc.b    2,0,0,0
                dc.l    xy2,0
db3:            dc.w    2,3
                dc.b    2,0,0,1
                dc.l    xy2,0
db4:            dc.w    0,0
                dc.b    2,0,0,200
                dc.l    xy4,0
db4b:           dc.w    0,0
                dc.b    3,0,0,129
                dc.l    xy4,0
db5:            dc.w    1,1
                dc.b    3,0,0,5
                dc.l    xy5,db5b
db5b:           dc.w    0,0
                dc.b    1,0,2,2
                dc.l    xy5b,0
db6:            dc.w    -2,10
                dc.b    1,0,0,2
                dc.l    xy6,0
db7:            dc.w    0,0
                dc.b    1,2,1,3
                dc.l    xy7,0
db8:            dc.w    0,0
                dc.b    1,0,1,3
                dc.l    xy8,0
db9:            dc.w    0,0
                dc.b    3,0,2,3
                dc.l    xy9,0
db10:           dc.w    0,0
                dc.b    2,0,0,2
                dc.l    xy10,0
xy1:            dc.w    0,0,10,0,10,5
xy2:            dc.w    5,5,10,0
xy4:            dc.w    1,1,10,1,10,8
xy5:            dc.w    0,0,20,0,20,10,0,10,0,0
xy5b:           dc.w    0,6,20,6
xy6:            dc.w    -3,-4,30,-4
xy7:            dc.w    0,2,40,2,40,10
xy8:            dc.w    5,5,5,5,5,5
xy9:            dc.w    2,3,20,3,20,9
xy10:           dc.w    0,2,20,2

; Image: LeftEdge, TopEdge, Width, Height, Depth, ImageData (set by dfix), PlanePick, PlaneOnOff, NextImage
dinull          EQU     0
di1:            dc.w    2,1,5,3,2
                dc.l    0
                dc.b    3,0
                dc.l    0
di2:            dc.w    2,1,5,3,2
                dc.l    0
                dc.b    1,6
                dc.l    0
di3:            dc.w    2,1,7,2,0
                dc.l    0
                dc.b    0,5
                dc.l    0
di4:            dc.w    2,1,5,3,1
                dc.l    0
                dc.b    5,0
                dc.l    0
di5:            dc.w    2,1,5,3,2
                dc.l    0
                dc.b    $FF,0
                dc.l    0
di6:            dc.w    2,1,5,3,2
                dc.l    0
                dc.b    3,4
                dc.l    0
di7:            dc.w    0,0,5,3,2
                dc.l    0
                dc.b    3,0
                dc.l    di7b
di7b:           dc.w    10,0,5,3,2
                dc.l    0
                dc.b    3,0
                dc.l    0
di8:            dc.w    2,1,20,2,1
                dc.l    0
                dc.b    1,0
                dc.l    0
di9:            dc.w    2,1,0,3,1
                dc.l    0
                dc.b    1,2
                dc.l    0
di10:           dc.w    2,1,5,3,1
                dc.l    0
                dc.b    0,0
                dc.l    0
di11:           dc.w    2,1,5,3,2
                dc.l    0
                dc.b    2,0
                dc.l    0
di12:           dc.w    2,1,5,3,1
                dc.l    0
                dc.b    1,0
                dc.l    0
isol3:          dc.w    0,0,10,4,0
                dc.l    0
                dc.b    0,3
                dc.l    0
isol2:          dc.w    0,0,10,4,0
                dc.l    0
                dc.b    0,2
                dc.l    0

; IntuiText: FrontPen, BackPen, DrawMode, pad, LeftEdge, TopEdge, ITextFont, IText, NextText
pt1:            dc.b    1,2,1,0
                dc.w    1,2
                dc.l    0,s_ab,0
pt2a:           dc.b    3,0,0,0
                dc.w    20,0
                dc.l    ta9,s_b,0
pt2:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    0,s_a,pt2b
pt2b:           dc.b    2,0,0,0
                dc.w    20,0
                dc.l    ta9,s_b,pt2c
pt2c:           dc.b    3,0,0,0
                dc.w    40,0
                dc.l    0,s_c,0
pt3:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    0,s_mm,0
pt4:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    tanos,s_mm,0
pt5:            dc.b    1,0,0,0
                dc.w    5,3
                dc.l    0,0,0
pt6:            dc.b    1,2,1,0
                dc.w    0,0
                dc.l    0,s_empty,0
pt7:            dc.b    1,2,2,0
                dc.w    0,0
                dc.l    0,s_mm,0
pt8:            dc.b    1,2,5,0
                dc.w    0,0
                dc.l    0,s_mm,0
; PT10: bold rp, chain "A" (null font) -> "B" (topaz 9) -> "C" (null font): rp style/font back after
pt10:           dc.b    1,0,0,0
                dc.w    0,0
                dc.l    0,s_a,pt10b
pt10b:          dc.b    2,0,0,0
                dc.w    20,0
                dc.l    ta9,s_b,pt10c
pt10c:          dc.b    3,0,0,0
                dc.w    40,0
                dc.l    0,s_c,0
pt9:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    ta8i,s_mm,0
pt9p:           dc.b    1,0,0,0
                dc.w    0,0
                dc.l    ta8,s_mm,0
tl1:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    0,s_hello,0
tl2:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    ta9,s_hello,0
tl3:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    0,s_hello,tl3b
tl3b:           dc.b    1,0,0,0
                dc.w    0,0
                dc.l    0,s_more,0
tl4:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    ta8b,s_hello,0
tl5:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    0,s_empty,0
tl6:            dc.b    1,0,0,0
                dc.w    0,0
                dc.l    tanos,s_hello,0
tl7:            dc.b    1,0,0,0
                dc.w    77,9
                dc.l    0,s_hi,0

; NewScreen: Left, Top, Width, Height, Depth, DetailPen, BlockPen, ViewModes (HIRES), Type (CUSTOMSCREEN), Font,
; DefaultTitle, Gadgets, CustomBitMap
nscr:           dc.w    0,0,640,200,2
                dc.b    0,1
                dc.w    $8000,$000F
                dc.l    ta8,s_scrdef,0,0
; NewWindow: Left, Top, Width, Height, DetailPen, BlockPen, IDCMP, Flags, FirstGadget, CheckMark, Title, Screen,
; BitMap, MinW, MinH, MaxW, MaxH, Type (CUSTOMSCREEN)
nw1:            dc.w    100,40,300,80
                dc.b    0,1
                dc.l    0,$100F,0,0,s_wtitle,0,0
                dc.w    50,20,640,200,$000F
nw2:            dc.w    420,40,200,60
                dc.b    0,1
                dc.l    0,$000E,0,0,s_other,0,0
                dc.w    50,20,640,200,$000F
nwbd:           dc.w    0,12,640,188
                dc.b    0,1
                dc.l    0,$0900,0,0,0,0,0
                dc.w    50,20,640,200,$000F
