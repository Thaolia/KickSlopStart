; tests/gtext_probe.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe "graphics.library text and fonts" (docs/analysis/graphics-text-v34.md §11, expected values §10).
; Run from the startup-sequence of a floppy without SetPatch and without devs:system-configuration
; (tests/gtext_probe.sh). Calls Text, TextLength, SetFont, OpenFont, CloseFont, AskFont, AddFont, RemFont,
; AskSoftStyle, SetSoftStyle, ClearEOL and ClearScreen through their public LVOs on layerless BitMaps in CHIP and
; writes the results to the direct serial port (SERDAT). Every Text vector uses the synthetic font "probe.font"
; of §10.1 (authored here); topaz is only asked for line numbers and returned values, never drawn.
; No Text with a negative destination x and no italic at cp_x 0 (corrupts memory on 1.3 without a layer, §7.6).
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/gtext_probe tests/gtext_probe.s
; Authored code; public structures (graphics/text.h, rastport.h, gfx.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
CHIPSZ   EQU 1024
O_PL0    EQU 0           ; plane 0 (128 bytes)
O_PL1    EQU 128         ; plane 1 (128 bytes)
O_STRK   EQU 256         ; probe.font strike, 8 rows x 2 bytes
O_LOC    EQU 272         ; CharLoc, 5 longs (A, B, C, D, default)
O_SPC    EQU 292         ; CharSpace, 5 words
O_KRN    EQU 302         ; CharKern, 5 words
O_PAT    EQU 312         ; area pattern for ClearEOL
O_PFONT  EQU 320         ; TextFont probe.font
O_FA     EQU 384         ; contest font A
O_FB     EQU 448         ; contest font B
O_FF     EQU 512         ; AddFont/RemFont/CloseFont font
NCT      EQU 22          ; number of OpenFont contests (ctab)

; LVOs checked against AROS rom/graphics/graphics.conf (bias 30, 6 bytes per slot)
LVO_ClearEOL     EQU -42
LVO_ClearScreen  EQU -48
LVO_TextLength   EQU -54
LVO_Text         EQU -60
LVO_SetFont      EQU -66
LVO_OpenFont     EQU -72
LVO_CloseFont    EQU -78
LVO_AskSoftStyle EQU -84
LVO_SetSoftStyle EQU -90
LVO_InitRastPort EQU -198
LVO_WaitBlit     EQU -228
LVO_SetAPen      EQU -342
LVO_SetBPen      EQU -348
LVO_SetDrMd      EQU -354
LVO_AskFont      EQU -474
LVO_AddFont      EQU -480
LVO_RemFont      EQU -486

; TextFont (text.h)
TF_TYPE  EQU $08
TF_PRI   EQU $09
TF_NAME  EQU $0A
TF_YSIZE EQU $14
TF_STYLE EQU $16
TF_FLAGS EQU $17
TF_XSIZE EQU $18
TF_BASE  EQU $1A
TF_SMEAR EQU $1C
TF_ACC   EQU $1E
TF_LO    EQU $20
TF_HI    EQU $21
TF_DATA  EQU $22
TF_MOD   EQU $26
TF_LOC   EQU $28
TF_SPACE EQU $2C
TF_KERN  EQU $30
TF_SIZE  EQU 52
; RastPort (rastport.h)
RP_PTRN  EQU $08
RP_FG    EQU $19
RP_PTSZ  EQU $1D
RP_CPX   EQU $24
RP_CPY   EQU $26
RP_FONT  EQU $34
RP_ALGO  EQU $38
RP_TXH   EQU $3A
RP_TXW   EQU $3C
RP_TXB   EQU $3E
RP_TXSP  EQU $40
GB_FONTS EQU $8C         ; GfxBase.TextFonts

; --- SETUP bpr,depth,fill0,fill1,rows: BitMap + fill + InitRastPort + rp_BitMap + SetFont(probe.font)
SETUP           macro
                move.w  #\1,d0
                move.w  #\2,d1
                move.w  #\3,d2
                move.w  #\4,d3
                move.w  #\5,d4
                bsr     tsetup
                endm
PEN             macro
                move.l  #\1,d0
                lea     rp-vars(a4),a1
                jsr     LVO_SetAPen(a6)
                endm
BPEN            macro
                move.l  #\1,d0
                lea     rp-vars(a4),a1
                jsr     LVO_SetBPen(a6)
                endm
MODE            macro
                move.l  #\1,d0
                lea     rp-vars(a4),a1
                jsr     LVO_SetDrMd(a6)
                endm
STYLE           macro
                move.l  #\1,d0
                move.l  #$FF,d1
                lea     ssblk-vars(a4),a2
                lea     rp-vars(a4),a1
                jsr     LVO_SetSoftStyle(a6)
                endm
; --- TXT name,string,count,x,y: cp := (x,y), Text, then header "name cpx=<dec>" and rows 1..10
TXT             macro
                move.w  #\4,rp+RP_CPX-vars(a4)
                move.w  #\5,rp+RP_CPY-vars(a4)
                lea     \2(pc),a0
                move.l  #\3,d0
                lea     rp-vars(a4),a1
                jsr     LVO_Text(a6)
                lea     \1(pc),a0
                bsr     tdump
                endm
; --- TLEN label,string,count: prints "label=<hex8>" of TextLength
TLEN            macro
                lea     \1(pc),a0
                bsr     puts
                lea     \2(pc),a0
                move.l  #\3,d0
                lea     rp-vars(a4),a1
                jsr     LVO_TextLength(a6)
                bsr     phex8
                bsr     nl
                endm
; --- TOPZ label,size: OpenFont("topaz.font"/label, size), prints "label=<YSize dec or 0>", CloseFont
TOPZ            macro
                lea     \1(pc),a0
                move.w  #\2,d0
                bsr     topz
                endm
; --- CEOL label,mode: ClearEOL vector on 2 planes 4 x 12 filled $FF, cp (12,7), Fg 1, Bg 2
CEOL            macro
                move.w  #\2,d6
                lea     \1(pc),a0
                bsr     ceol
                endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  4.w,a6
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,gfxb-vars(a4)
                beq     .out
                move.l  #CHIPSZ,d0
                move.l  #$10003,d1
                jsr     -198(a6)
                move.l  d0,chip-vars(a4)
                beq     .close
                move.l  d0,a5
                lea     m_start(pc),a0
                bsr     puts
                move.l  gfxb-vars(a4),a6
                move.b  #$40,ssblk+$16-vars(a4)

; --- InitRastPort defaults (no system-configuration: 1.3 gives the topaz 9 DefaultFont)
                lea     rp-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     m_irp(pc),a0
                bsr     puts
                move.w  rp+RP_TXH-vars(a4),d0
                bsr     pdec
                bsr     slash
                move.w  rp+RP_TXW-vars(a4),d0
                bsr     pdec
                bsr     slash
                move.w  rp+RP_TXB-vars(a4),d0
                bsr     pdec
                bsr     nl

; --- OpenFont of topaz.font (case-sensitive name) at several sizes
                TOPZ    m_o7,7
                TOPZ    m_o8,8
                TOPZ    m_o9,9
                TOPZ    m_o10,10
                TOPZ    m_o11,11
                TOPZ    m_o200,200
                TOPZ    m_o600,600
                lea     tname2-vars(a4),a0
                move.l  a0,ta-vars(a4)
                lea     m_oT8(pc),a0
                moveq   #8,d0
                bsr     topz1
                lea     tname-vars(a4),a0
                move.l  a0,ta-vars(a4)

; --- AskFont / AskSoftStyle / SetSoftStyle on topaz 9, AskSoftStyle on topaz 8
                move.w  #9,ta+4-vars(a4)
                clr.w   ta+6-vars(a4)
                lea     ta-vars(a4),a0
                jsr     LVO_OpenFont(a6)
                move.l  d0,d7
                beq     .not9
                lea     rp-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     rp-vars(a4),a1
                move.l  d7,a0
                jsr     LVO_SetFont(a6)
                lea     ta2-vars(a4),a0
                lea     rp-vars(a4),a1
                jsr     LVO_AskFont(a6)
                lea     m_ask9(pc),a0
                bsr     puts
                move.w  ta2+4-vars(a4),d0
                bsr     pdec
                bsr     sp1
                move.b  ta2+6-vars(a4),d0
                bsr     phex2
                bsr     sp1
                move.b  ta2+7-vars(a4),d0
                bsr     phex2
                bsr     sp1
                move.l  ta2-vars(a4),a0
                bsr     puts
                bsr     nl
                lea     m_ass9(pc),a0
                bsr     puts
                moveq   #0,d1
                lea     rp-vars(a4),a1
                jsr     LVO_AskSoftStyle(a6)
                bsr     phex8
                bsr     nl
                lea     m_sss9(pc),a0
                bsr     puts
                move.l  #$FF,d0
                move.l  #$FF,d1
                lea     ssblk-vars(a4),a2
                lea     rp-vars(a4),a1
                jsr     LVO_SetSoftStyle(a6)
                bsr     phex8
                lea     m_algo(pc),a0
                bsr     puts
                move.b  rp+RP_ALGO-vars(a4),d0
                bsr     phex2
                bsr     nl
                move.l  d7,a1
                jsr     LVO_CloseFont(a6)
.not9:
                move.w  #8,ta+4-vars(a4)
                lea     ta-vars(a4),a0
                jsr     LVO_OpenFont(a6)
                move.l  d0,d7
                beq     .not8
                lea     rp-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     rp-vars(a4),a1
                move.l  d7,a0
                jsr     LVO_SetFont(a6)
                lea     m_ass8(pc),a0
                bsr     puts
                moveq   #0,d1
                lea     rp-vars(a4),a1
                jsr     LVO_AskSoftStyle(a6)
                bsr     phex8
                bsr     nl
                move.l  d7,a1
                jsr     LVO_CloseFont(a6)
.not8:

; --- probe.font (§10.1): strike, CharLoc, TextFont, AddFont, OpenFont
                lea     O_STRK(a5),a0
                moveq   #0,d0
                move.b  #$80,d1
.strk:          move.b  #$F4,(a0)+
                move.b  d1,(a0)+
                lsr.b   #1,d1
                addq.w  #1,d0
                cmp.w   #8,d0
                blo.s   .strk
                lea     O_LOC(a5),a0
                move.l  #$00000004,(a0)+
                move.l  #$00040003,(a0)+
                move.l  #$00080008,(a0)+
                move.l  #$00000000,(a0)+
                move.l  #$00000002,(a0)+
                lea     O_SPC(a5),a0
                move.l  #$0005000C,(a0)+
                move.l  #$00080003,(a0)+
                move.w  #4,(a0)+
                lea     O_KRN(a5),a0
                move.l  #$FFFE0003,(a0)+
                clr.l   (a0)+
                move.w  #1,(a0)+
                lea     O_PAT(a5),a0
                move.l  #$AAAA0000,(a0)
                lea     O_PFONT(a5),a0
                lea     pname(pc),a1
                moveq   #8,d0
                moveq   #0,d1
                moveq   #2,d2
                moveq   #0,d3
                bsr     mkfont
                lea     O_PFONT(a5),a1
                jsr     LVO_AddFont(a6)
                lea     pname(pc),a0
                move.l  a0,ta-vars(a4)
                move.w  #8,ta+4-vars(a4)
                clr.w   ta+6-vars(a4)
                lea     ta-vars(a4),a0
                jsr     LVO_OpenFont(a6)
                lea     m_popen(pc),a0
                bsr     puts
                lea     O_PFONT(a5),a0
                cmp.l   a0,d0
                seq     d0
                and.b   #1,d0
                bsr     phex2
                lea     m_acc(pc),a0
                bsr     puts
                move.w  O_PFONT+TF_ACC(a5),d0
                bsr     pdec
                bsr     nl

; --- §10.2 Text on 1 plane, 8 bytes x 16 rows, JAM2, Fg -1, Bg 0
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                TXT     m_v1,s_abcd,4,8,8
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                TXT     m_v2,s_z10at,3,8,8
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                STYLE   2
                move.l  d0,d7
                lea     m_v3ss(pc),a0
                bsr     puts
                move.l  d7,d0
                bsr     phex8
                bsr     nl
                TXT     m_v3,s_abcd,3,8,8
                move.w  #2,O_PFONT+TF_SMEAR(a5)
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                STYLE   2
                TXT     m_v3b,s_c,1,8,8
                move.w  #1,O_PFONT+TF_SMEAR(a5)
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                STYLE   4
                TXT     m_v4,s_cb,2,16,8
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                STYLE   1
                TXT     m_v5,s_abd,3,8,8
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                STYLE   7
                TXT     m_v5b,s_c,1,16,8
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                move.w  #2,rp+RP_TXSP-vars(a4)
                TXT     m_v7,s_10a,2,8,8
                SETUP   4,1,0,0,16
                PEN     255
                MODE    1
                TXT     m_v8,s_10a,10,8,8
                SETUP   8,1,0,0,16
                PEN     255
                MODE    1
                TXT     m_v9,s_abcd,0,8,8

; --- §10.3 modes on 2 planes, "AB" at (8,8)
                SETUP   8,2,$00,$FF,16
                PEN     1
                BPEN    0
                MODE    0
                TXT     m_v6,s_abcd,2,8,8
                SETUP   8,2,$00,$00,16
                PEN     1
                BPEN    2
                MODE    1
                TXT     m_v6b,s_abcd,2,8,8
                SETUP   8,2,$0F,$00,16
                MODE    2
                TXT     m_v6c,s_abcd,2,8,8
                SETUP   8,2,$00,$00,16
                PEN     1
                BPEN    2
                MODE    4
                TXT     m_v6d,s_abcd,2,8,8
                SETUP   8,2,$00,$00,16
                PEN     1
                BPEN    2
                MODE    5
                TXT     m_v6e,s_abcd,2,8,8
                SETUP   8,2,$00,$FF,16
                PEN     3
                BPEN    0
                MODE    1
                move.b  #1,rp+$18-vars(a4)
                TXT     m_v6f,s_abcd,2,8,8

; --- V12 proportional font (CharSpace/CharKern), JAM2 Fg 1 Bg 2, "AB" at (16,8)
                lea     O_SPC(a5),a0
                move.l  a0,O_PFONT+TF_SPACE(a5)
                lea     O_KRN(a5),a0
                move.l  a0,O_PFONT+TF_KERN(a5)
                SETUP   8,2,$00,$00,16
                PEN     1
                BPEN    2
                MODE    1
                TXT     m_v12,s_abcd,2,16,8

; --- TextLength (§10.3, §6)
                TLEN    m_tl1,s_abcd,2
                TLEN    m_tl2,s_abcd,4
                TLEN    m_tl3,s_z10at,1
                clr.l   O_PFONT+TF_SPACE(a5)
                clr.l   O_PFONT+TF_KERN(a5)
                SETUP   8,1,0,0,16
                TLEN    m_tl4,s_abcd,4
                move.w  #3,rp+RP_TXSP-vars(a4)
                TLEN    m_tl5,s_abcd,4
                STYLE   7
                TLEN    m_tl6,s_abcd,4
                SETUP   8,1,0,0,16
                move.w  #-16,rp+RP_TXSP-vars(a4)
                TLEN    m_tl7,s_10a,2
                SETUP   8,1,0,0,16
                TLEN    m_tl8,s_10a,$10002

; --- SetFont resets AlgoStyle, keeps TxSpacing; AskSoftStyle / SetSoftStyle on probe.font (§10.5)
                SETUP   8,1,0,0,16
                move.b  #7,rp+RP_ALGO-vars(a4)
                move.w  #3,rp+RP_TXSP-vars(a4)
                lea     O_PFONT(a5),a0
                lea     rp-vars(a4),a1
                jsr     LVO_SetFont(a6)
                lea     m_sfa(pc),a0
                bsr     puts
                move.b  rp+RP_ALGO-vars(a4),d0
                bsr     phex2
                lea     m_sfs(pc),a0
                bsr     puts
                move.w  rp+RP_TXSP-vars(a4),d0
                bsr     pdec
                bsr     nl
                lea     m_assp(pc),a0
                bsr     puts
                moveq   #0,d1
                lea     rp-vars(a4),a1
                jsr     LVO_AskSoftStyle(a6)
                bsr     phex8
                bsr     nl
                STYLE   2
                move.l  #$F5,d0
                move.l  #$0F,d1
                lea     ssblk-vars(a4),a2
                lea     rp-vars(a4),a1
                jsr     LVO_SetSoftStyle(a6)
                move.l  d0,d7
                lea     m_ssp(pc),a0
                bsr     puts
                move.b  rp+RP_ALGO-vars(a4),d0
                bsr     phex2
                lea     m_ret(pc),a0
                bsr     puts
                move.l  d7,d0
                bsr     phex8
                bsr     nl

; --- §10.4 OpenFont contests between two fonts named w.font
                lea     ctab(pc),a3
                moveq   #1,d7
.ct:            lea     O_FA(a5),a0
                lea     wname(pc),a1
                moveq   #0,d0
                move.b  (a3)+,d0
                move.b  (a3)+,d1
                move.b  (a3)+,d2
                move.b  (a3)+,d3
                bsr     mkfont
                lea     O_FB(a5),a0
                lea     wname(pc),a1
                moveq   #0,d0
                move.b  (a3)+,d0
                move.b  (a3)+,d1
                move.b  (a3)+,d2
                move.b  (a3)+,d3
                bsr     mkfont
                lea     O_FA(a5),a1
                jsr     LVO_AddFont(a6)
                lea     O_FB(a5),a1
                jsr     LVO_AddFont(a6)
                lea     wname(pc),a0
                move.l  a0,ta-vars(a4)
                moveq   #0,d0
                move.b  (a3)+,d0
                move.w  d0,ta+4-vars(a4)
                move.b  (a3)+,ta+6-vars(a4)
                move.b  (a3)+,ta+7-vars(a4)
                addq.l  #1,a3
                lea     ta-vars(a4),a0
                jsr     LVO_OpenFont(a6)
                move.l  d0,d6
                lea     m_c(pc),a0
                bsr     puts
                move.w  d7,d0
                bsr     pdec
                moveq   #'=',d1
                bsr     putc
                moveq   #'0',d1
                tst.l   d6
                beq.s   .cw
                moveq   #'?',d1
                lea     O_FA(a5),a0
                cmp.l   a0,d6
                bne.s   .cb
                moveq   #'A',d1
.cb:            lea     O_FB(a5),a0
                cmp.l   a0,d6
                bne.s   .cw
                moveq   #'B',d1
.cw:            bsr     putc
                bsr     nl
                tst.l   d6
                beq.s   .cr
                move.l  d6,a1
                jsr     LVO_CloseFont(a6)
.cr:            lea     O_FA(a5),a1
                jsr     LVO_RemFont(a6)
                lea     O_FB(a5),a1
                jsr     LVO_RemFont(a6)
                addq.w  #1,d7
                cmp.w   #NCT,d7
                bls     .ct

; --- §10.5 AddFont / RemFont / CloseFont sequence
                lea     O_FF(a5),a0
                lea     fname(pc),a1
                moveq   #8,d0
                moveq   #0,d1
                moveq   #2,d2
                moveq   #0,d3
                bsr     mkfont
                move.w  #5,O_FF+TF_ACC(a5)
                lea     m_f0(pc),a0
                bsr     fstate
                lea     O_FF(a5),a1
                jsr     LVO_AddFont(a6)
                lea     m_f1(pc),a0
                bsr     fstate
                lea     fname(pc),a0
                move.l  a0,ta-vars(a4)
                move.w  #8,ta+4-vars(a4)
                clr.w   ta+6-vars(a4)
                lea     ta-vars(a4),a0
                jsr     LVO_OpenFont(a6)
                lea     O_FF(a5),a0
                cmp.l   a0,d0
                seq     d0
                and.b   #1,d0
                move.b  d0,fopen-vars(a4)
                lea     m_f2(pc),a0
                bsr     fstate
                lea     O_FF(a5),a1
                jsr     LVO_RemFont(a6)
                lea     m_f3(pc),a0
                bsr     fstate
                lea     O_FF(a5),a1
                jsr     LVO_CloseFont(a6)
                lea     m_f4(pc),a0
                bsr     fstate
                lea     O_FF(a5),a1
                jsr     LVO_CloseFont(a6)
                lea     m_f5(pc),a0
                bsr     fstate
                lea     O_FF(a5),a1
                jsr     LVO_CloseFont(a6)
                lea     m_f6(pc),a0
                bsr     fstate

; --- §10.5 ClearEOL on 2 planes 4 bytes x 12 rows filled $FF, cp (12,7), Fg 1, Bg 2
                CEOL    m_e1,1
                CEOL    m_e2,0
                CEOL    m_e3,$100
                CEOL    m_e4,2
                CEOL    m_e5,5
                CEOL    m_e6,4

; --- §10.5 ClearScreen on 2 planes 4 bytes x 16 rows filled $FF, JAM2, Fg 1, Bg 2, cp (12,8) then (12,14)
                lea     m_s1(pc),a0
                moveq   #8,d6
                bsr     cscr
                lea     m_s2(pc),a0
                moveq   #14,d6
                bsr     cscr

; --- cleanup: probe.font off the list before its memory goes
                jsr     LVO_WaitBlit(a6)
                lea     O_PFONT(a5),a1
                jsr     LVO_CloseFont(a6)
                lea     O_PFONT(a5),a1
                jsr     LVO_RemFont(a6)
                lea     m_end(pc),a0
                bsr     puts
                move.l  a5,a1
                move.l  #CHIPSZ,d0
                move.l  4.w,a6
                jsr     -210(a6)
.close:         move.l  4.w,a6
                move.l  gfxb-vars(a4),a1
                jsr     -414(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- tsetup(d0 bpr, d1 depth, d2 fill0, d3 fill1, d4 rows): BitMap, planes, InitRastPort, rp_BitMap, SetFont
tsetup:         movem.l d0-d4,-(sp)
                jsr     LVO_WaitBlit(a6)
                movem.l (sp)+,d0-d4
                lea     bm-vars(a4),a0
                move.w  d0,(a0)
                move.w  d4,2(a0)
                clr.b   4(a0)
                move.b  d1,5(a0)
                clr.w   6(a0)
                lea     O_PL0(a5),a1
                move.l  a1,8(a0)
                lea     O_PL1(a5),a1
                move.l  a1,12(a0)
                lea     16(a0),a1
                moveq   #5,d4
.cb:            clr.l   (a1)+
                dbra    d4,.cb
                move.w  d0,bpr-vars(a4)
                lea     O_PL0(a5),a1
                move.w  #127,d4
.f0:            move.b  d2,(a1)+
                dbra    d4,.f0
                move.w  #127,d4
.f1:            move.b  d3,(a1)+
                dbra    d4,.f1
                lea     rp-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     rp-vars(a4),a1
                lea     bm-vars(a4),a0
                move.l  a0,4(a1)
                lea     O_PFONT(a5),a0
                jsr     LVO_SetFont(a6)
                rts

; --- tdump(a0 name): "name cpx=<dec>", then rows 1..10
tdump:          bsr     puts
                lea     m_cpx(pc),a0
                bsr     puts
                move.w  rp+RP_CPX-vars(a4),d0
                bsr     pdec
                bsr     nl
                moveq   #1,d6
                moveq   #10,d7
                bra     dumpr

; --- dumpr(d6 first row, d7 last row): "<plane0> | <plane1>", min(6, bpr) bytes each
dumpr:          jsr     LVO_WaitBlit(a6)
.r:             move.w  d6,d3
                mulu    bpr-vars(a4),d3
                move.l  a5,a2
                add.l   d3,a2
                bsr     prow
                lea     m_bar(pc),a0
                bsr     puts
                move.l  a5,a2
                add.l   d3,a2
                lea     O_PL1(a2),a2
                bsr     prow
                bsr     nl
                addq.w  #1,d6
                cmp.w   d7,d6
                bls.s   .r
                rts
prow:           move.w  bpr-vars(a4),d4
                cmp.w   #6,d4
                bls.s   .n
                moveq   #6,d4
.n:             subq.w  #1,d4
.b:             move.b  (a2)+,d0
                bsr     phex2
                dbra    d4,.b
                rts

; --- topz(a0 label, d0 size): OpenFont("topaz.font", size) -> "label=<YSize or 0>", CloseFont
topz:           lea     tname-vars(a4),a1
                move.l  a1,ta-vars(a4)
topz1:          move.w  d0,ta+4-vars(a4)
                clr.w   ta+6-vars(a4)
                bsr     puts
                lea     ta-vars(a4),a0
                jsr     LVO_OpenFont(a6)
                move.l  d0,d7
                moveq   #0,d0
                tst.l   d7
                beq.s   .p
                move.l  d7,a0
                move.w  TF_YSIZE(a0),d0
.p:             bsr     pdec
                bsr     nl
                tst.l   d7
                beq.s   .r
                move.l  d7,a1
                jsr     LVO_CloseFont(a6)
.r:             rts

; --- mkfont(a0 font, a1 name, d0 YSize, d1 Style, d2 Flags, d3 Pri): a TextFont over the probe strike
mkfont:         move.l  a0,a2
                moveq   #TF_SIZE/2-1,d4
.c:             clr.w   (a2)+
                dbra    d4,.c
                move.b  d3,TF_PRI(a0)
                move.l  a1,TF_NAME(a0)
                move.w  #TF_SIZE,$12(a0)
                move.w  d0,TF_YSIZE(a0)
                move.b  d1,TF_STYLE(a0)
                move.b  d2,TF_FLAGS(a0)
                move.w  #8,TF_XSIZE(a0)
                move.w  #6,TF_BASE(a0)
                move.w  #1,TF_SMEAR(a0)
                move.b  #'A',TF_LO(a0)
                move.b  #'D',TF_HI(a0)
                lea     O_STRK(a5),a1
                move.l  a1,TF_DATA(a0)
                move.w  #2,TF_MOD(a0)
                lea     O_LOC(a5),a1
                move.l  a1,TF_LOC(a0)
                rts

; --- fstate(a0 label): "label acc=<dec> type=<hex> flags=<hex> list=<0/1> open=<0/1>" of the O_FF font
fstate:         bsr     puts
                lea     m_acc(pc),a0
                bsr     puts
                move.w  O_FF+TF_ACC(a5),d0
                bsr     pdec
                lea     m_type(pc),a0
                bsr     puts
                move.b  O_FF+TF_TYPE(a5),d0
                bsr     phex2
                lea     m_flg(pc),a0
                bsr     puts
                move.b  O_FF+TF_FLAGS(a5),d0
                bsr     phex2
                lea     m_list(pc),a0
                bsr     puts
                lea     O_FF(a5),a1
                moveq   #0,d0
                move.l  GB_FONTS(a6),a0
.l:             tst.l   (a0)
                beq.s   .e
                cmp.l   a0,a1
                beq.s   .y
                move.l  (a0),a0
                bra.s   .l
.y:             moveq   #1,d0
.e:             bsr     phex2
                lea     m_open(pc),a0
                bsr     puts
                move.b  fopen-vars(a4),d0
                bsr     phex2
                bra     nl

; --- ceol(a0 label, d6 mode; $100 = JAM1 + AreaPtrn {$AAAA,$0000} AreaPtSz 1)
ceol:           move.l  a0,-(sp)
                SETUP   4,2,$FF,$FF,12
                PEN     1
                BPEN    2
                move.w  d6,d0
                and.l   #$FF,d0
                lea     rp-vars(a4),a1
                jsr     LVO_SetDrMd(a6)
                cmp.w   #$100,d6
                bne.s   .np
                lea     O_PAT(a5),a0
                move.l  a0,rp+RP_PTRN-vars(a4)
                move.b  #1,rp+RP_PTSZ-vars(a4)
.np:            move.w  #12,rp+RP_CPX-vars(a4)
                move.w  #7,rp+RP_CPY-vars(a4)
                lea     rp-vars(a4),a1
                jsr     LVO_ClearEOL(a6)
                move.l  (sp)+,a0
                bra     cpost

; --- cscr(a0 label, d6 cp_y): ClearScreen at (12, d6)
cscr:           move.l  a0,-(sp)
                SETUP   4,2,$FF,$FF,16
                PEN     1
                BPEN    2
                MODE    1
                move.w  #12,rp+RP_CPX-vars(a4)
                move.w  d6,rp+RP_CPY-vars(a4)
                lea     rp-vars(a4),a1
                jsr     LVO_ClearScreen(a6)
                move.l  (sp)+,a0
; --- cpost(a0 label): "label fg=<hex> ptrn=<hex8> cp=<x>,<y>", then rows 0..15
cpost:          bsr     puts
                lea     m_fg(pc),a0
                bsr     puts
                move.b  rp+RP_FG-vars(a4),d0
                bsr     phex2
                lea     m_ptrn(pc),a0
                bsr     puts
                move.l  rp+RP_PTRN-vars(a4),d0
                beq.s   .z
                sub.l   a5,d0
.z:             bsr     phex4
                lea     m_cp(pc),a0
                bsr     puts
                move.w  rp+RP_CPX-vars(a4),d0
                bsr     pdec
                moveq   #',',d1
                bsr     putc
                move.w  rp+RP_CPY-vars(a4),d0
                bsr     pdec
                bsr     nl
                moveq   #0,d6
                moveq   #15,d7
                bra     dumpr

; --- printing helpers
slash:          moveq   #'/',d1
                bra.s   putc
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

; OpenFont contests (§10.4): A (YSize, Style, Flags, Pri), B (same), request (YSize, Style, Flags), pad.
; Expected winners, in order: B B A A B A B B A B A A A B 0 B A B A A A A
ctab:           dc.b    8,4,0,0,     7,0,0,0,     8,0,0,0
                dc.b    8,1,0,0,     7,0,0,0,     8,0,0,0
                dc.b    8,0,0,0,     7,1,0,0,     8,1,0,0
                dc.b    9,0,0,0,     4,0,0,0,     8,0,0,0
                dc.b    9,0,0,0,     5,0,0,0,     8,0,0,0
                dc.b    9,0,0,0,     3,0,0,0,     8,0,0,0
                dc.b    8,0,$20,0,   7,0,0,0,     8,0,0,0
                dc.b    8,0,0,0,     8,0,$20,0,   8,0,$20,0
                dc.b    8,0,0,0,     7,0,$20,0,   8,0,$20,0
                dc.b    8,2,0,0,     7,0,0,0,     8,0,0,0
                dc.b    8,0,0,0,     7,2,0,0,     8,2,0,0
                dc.b    8,0,0,0,     7,4,0,0,     8,4,0,0
                dc.b    8,8,0,0,     8,0,0,0,     8,0,0,0
                dc.b    8,0,0,0,     8,0,0,5,     8,0,0,0
                dc.b    0,0,0,0,     0,0,0,0,     8,0,0,0
                dc.b    8,0,$02,0,   8,0,$01,0,   8,0,$01,0
                dc.b    8,0,$08,0,   7,0,0,0,     8,0,0,0
                dc.b    8,0,$04,0,   8,0,0,0,     8,0,0,0
                dc.b    8,0,0,0,     8,0,$04,0,   8,0,0,0
                dc.b    8,0,$80,0,   8,0,0,0,     8,0,0,0
                dc.b    8,$10,0,0,   8,0,0,0,     8,0,0,0
                dc.b    8,$80,0,0,   8,0,0,0,     8,0,0,0

s_abcd:         dc.b    "ABCD"
s_z10at:        dc.b    "Z",$10,"@"
s_c:            dc.b    "C"
s_cb:           dc.b    "CB"
s_abd:          dc.b    "ABD"
s_10a:          dc.b    "AAAAAAAAAA"
gfxname:        dc.b    "graphics.library",0
pname:          dc.b    "probe.font",0
wname:          dc.b    "w.font",0
fname:          dc.b    "f.font",0
m_start:        dc.b    10,"GTX debut",10,0
m_irp:          dc.b    "irp=",0
m_o7:           dc.b    "topaz7=",0
m_o8:           dc.b    "topaz8=",0
m_o9:           dc.b    "topaz9=",0
m_o10:          dc.b    "topaz10=",0
m_o11:          dc.b    "topaz11=",0
m_o200:         dc.b    "topaz200=",0
m_o600:         dc.b    "topaz600=",0
m_oT8:          dc.b    "Topaz8=",0
m_ask9:         dc.b    "askfont9=",0
m_ass9:         dc.b    "asksoft9=",0
m_sss9:         dc.b    "setsoft9 ret=",0
m_algo:         dc.b    " algo=",0
m_ass8:         dc.b    "asksoft8=",0
m_popen:        dc.b    "probeopen=",0
m_acc:          dc.b    " acc=",0
m_type:         dc.b    " type=",0
m_flg:          dc.b    " flags=",0
m_list:         dc.b    " list=",0
m_open:         dc.b    " open=",0
m_cpx:          dc.b    " cpx=",0
m_bar:          dc.b    " | ",0
m_v1:           dc.b    "V1",0
m_v2:           dc.b    "V2",0
m_v3ss:         dc.b    "V3 setsoft ret=",0
m_v3:           dc.b    "V3",0
m_v3b:          dc.b    "V3b",0
m_v4:           dc.b    "V4",0
m_v5:           dc.b    "V5",0
m_v5b:          dc.b    "V5b",0
m_v7:           dc.b    "V7",0
m_v8:           dc.b    "V8",0
m_v9:           dc.b    "V9",0
m_v6:           dc.b    "V6",0
m_v6b:          dc.b    "V6b",0
m_v6c:          dc.b    "V6c",0
m_v6d:          dc.b    "V6d",0
m_v6e:          dc.b    "V6e",0
m_v6f:          dc.b    "V6f",0
m_v12:          dc.b    "V12",0
m_tl1:          dc.b    "tl_AB_prop=",0
m_tl2:          dc.b    "tl_ABCD_prop=",0
m_tl3:          dc.b    "tl_Z_prop=",0
m_tl4:          dc.b    "tl_ABCD=",0
m_tl5:          dc.b    "tl_ABCD_sp3=",0
m_tl6:          dc.b    "tl_ABCD_sp3_styles=",0
m_tl7:          dc.b    "tl_AA_spm16=",0
m_tl8:          dc.b    "tl_count10002=",0
m_sfa:          dc.b    "setfont algo=",0
m_sfs:          dc.b    " txspacing=",0
m_assp:         dc.b    "asksoftprobe=",0
m_ssp:          dc.b    "setsoft_F5_0F algo=",0
m_ret:          dc.b    " ret=",0
m_c:            dc.b    "C",0
m_f0:           dc.b    "F0 built",0
m_f1:           dc.b    "F1 addfont",0
m_f2:           dc.b    "F2 openfont",0
m_f3:           dc.b    "F3 remfont",0
m_f4:           dc.b    "F4 closefont",0
m_f5:           dc.b    "F5 closefont",0
m_f6:           dc.b    "F6 closefont",0
m_e1:           dc.b    "E1 JAM2",0
m_e2:           dc.b    "E2 JAM1",0
m_e3:           dc.b    "E3 JAM1+ptrn",0
m_e4:           dc.b    "E4 COMPLEMENT",0
m_e5:           dc.b    "E5 JAM2|INV",0
m_e6:           dc.b    "E6 JAM1|INV",0
m_s1:           dc.b    "S1 cpy8",0
m_s2:           dc.b    "S2 cpy14",0
m_fg:           dc.b    " fg=",0
m_ptrn:         dc.b    " ptrn=",0
m_cp:           dc.b    " cp=",0
m_end:          dc.b    "GTX fin",10,0
                even

vars:
gfxb:           dc.l    0
chip:           dc.l    0
ta:             dc.l    0
                dc.w    0
                dc.b    0,0
ta2:            ds.b    8
tname:          dc.b    "topaz.font",0
tname2:         dc.b    "Topaz.font",0
fopen:          dc.b    0
                even
bpr:            dc.w    0
bm:             ds.b    40
rp:             ds.b    100
ssblk:          ds.b    32
