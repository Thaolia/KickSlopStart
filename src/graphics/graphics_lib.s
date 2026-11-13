; src/graphics/graphics_lib.s — graphics.library (M4c1: resident skeleton).
; 1st real LIBRARY module of the project (cia.resource/timer.device were resource/device). ROMTag RTF_AUTOINIT
; (pri 65, between cia 80 and timer 50) -> AUTOINIT path of InitResident: MakeLibrary creates GfxBase, then
; Enqueue into EB_LIBLIST according to RT_TYPE=NT_LIBRARY (1st time the NT_LIBRARY->LibList branch is exercised;
; until now only NT_DEVICE->DeviceList was, with timer.device). V34 quirk: the data table sets LN_TYPE +
; LIB_VERSION, the init func sets LN_NAME="graphics.library". The display functions (MakeVPort/MrgCop/
; LoadView...) are DEFERRED to M4c2: this milestone only delivers Open/Close/Expunge/Reserved (the skeleton
; that M4c2 AND intuition/M5 will open). GfxBase = minimal Library base (extended in M4c2).
;
; IMPLEMENTATION track ("clean"): graphics.library AutoDocs + exec (RKRM/NDK). NO ROM reading.

                include "exec.i"
                include "graphics.i"

; --- graphics.library ROMTag (scanned by build_reslist) ---
        EVEN
; drawing primitives: src/graphics/draw.s
                xdef    gfx_DisownBlitter
                xref    gfx_BltTemplate
                xref    gfx_SyncSBitMap
                xref    gfx_CopySBitMap
                xref    gfx_InitArea
                xref    gfx_InitTmpRas
                xref    gfx_BltPattern
                xref    gfx_AreaMove
                xref    gfx_AreaDraw
                xref    gfx_AreaEllipse
                xref    gfx_AreaEnd
                xref    gfx_DrawEllipse
                xref    gfx_Flood
                xref    gfx_ClearEOL
                xref    gfx_ClearScreen
                xref    gfx_Text
                xref    gfx_TextLength
                xref    gfx_SetFont
                xref    gfx_InitRastPort
                xref    gfx_fontinit
                xref    gfx_OpenFont
                xref    gfx_CloseFont
                xref    gfx_AskSoftStyle
                xref    gfx_SetSoftStyle
                xref    gfx_AskFont
                xref    gfx_AddFont
                xref    gfx_RemFont
                xref    gfx_AllocRaster
                xref    gfx_FreeRaster
                xref    gfx_AddBob
                xref    gfx_AddVSprite
                xref    gfx_DoCollision
                xref    gfx_DrawGList
                xref    gfx_InitGels
                xref    gfx_InitMasks
                xref    gfx_RemIBob
                xref    gfx_RemVSprite
                xref    gfx_SetCollision
                xref    gfx_SortGList
                xref    gfx_AddAnimOb
                xref    gfx_Animate
                xref    gfx_GetGBuffers
                xref    gfx_InitGMasks
                xref    gfx_FreeGBuffers
                xref    gfx_SetRast
                xref    gfx_Move
                xref    gfx_Draw
                xref    gfx_RectFill
                xref    gfx_WritePixel
                xref    gfx_SetAPen
                xref    gfx_SetBPen
                xref    gfx_SetDrMd
                xref    gfx_InitBitMap
                xref    gfx_ScrollRaster
                xref    gfx_BltBitMapRastPort
                xref    gfx_BltBitMap
                xref    gfx_ReadPixel
                xref    gfx_LockLayerRom
                xref    gfx_UnlockLayerRom
                xref    gfx_AttemptLockLayerRom
                xref    gfx_BltMaskBitMapRastPort
                xref    gfx_ClipBlit
                xref    newlist
                xref    gfx_AndRectRegion
                xref    gfx_OrRectRegion
                xref    gfx_NewRegion
                xref    gfx_ClearRectRegion
                xref    gfx_ClearRegion
                xref    gfx_DisposeRegion
                xref    gfx_XorRectRegion
                xref    gfx_OrRegionRegion
                xref    gfx_XorRegionRegion
                xref    gfx_AndRegionRegion
graphics_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    graphics_romtag          ; RT_MATCHTAG = self
        dc.l    graphics_end             ; RT_ENDSKIP
                ifne    M4C1_WRONG_TYPE
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,65   ; RED: RT_TYPE device -> routed to DeviceList, not LibList
                else
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,65  ; RT_FLAGS/VERSION/TYPE/PRI (65: between cia 80/timer 50)
                endc
        dc.l    graphics_name            ; RT_NAME
        dc.l    graphics_name            ; RT_IDSTRING
        dc.l    graphics_inittab         ; RT_INIT -> AUTOINIT table
graphics_name:
        dc.b    "graphics.library",0
        EVEN
graphics_inittab:
        dc.l    GFXBASE_SIZE             ; dataSize: public V34 GfxBase + private fields
        dc.l    graphics_vectors         ; funcTable
        dc.l    graphics_datatab         ; dataTable (InitStruct)
        dc.l    graphics_initfunc        ; initFunc
; ABSOLUTE table terminated by -1. Vector N -> LVO -6*N. We fill up to LoadView (-222 = vector 37); the
; unimplemented vectors 5..34 (-30..-204) point to graphics_null (dcb avoids any manual miscount).
graphics_vectors:                    ; ABSOLUTE table, vector N -> LVO -6*N, complete V34 set (109 vectors)
        dc.l    graphics_open            ; 1: LVO -6
        dc.l    graphics_close           ; 2: LVO -12
        dc.l    graphics_expunge         ; 3: LVO -18
        dc.l    graphics_null            ; 4: LVO -24 (reserved)
        dc.l    gfx_BltBitMap            ; 5: LVO -30
        dc.l    gfx_BltTemplate          ; 6: LVO -36 BltTemplate(src a0,xSrc d0,mod d1,rp a1,x d2,y d3,w d4,h d5)
        dc.l    gfx_ClearEOL             ; 7: LVO -42
        dc.l    gfx_ClearScreen          ; 8: LVO -48
        dc.l    gfx_TextLength           ; 9: LVO -54
        dc.l    gfx_Text                 ; 10: LVO -60
        dc.l    gfx_SetFont              ; 11: LVO -66
        dc.l    gfx_OpenFont             ; 12: LVO -72
        dc.l    gfx_CloseFont            ; 13: LVO -78
        dc.l    gfx_AskSoftStyle         ; 14: LVO -84
        dc.l    gfx_SetSoftStyle         ; 15: LVO -90
        dc.l    gfx_AddBob               ; 16: LVO -96
        dc.l    gfx_AddVSprite           ; 17: LVO -102
        dc.l    gfx_DoCollision          ; 18: LVO -108
        dc.l    gfx_DrawGList            ; 19: LVO -114
        dc.l    gfx_InitGels             ; 20: LVO -120
        dc.l    gfx_InitMasks            ; 21: LVO -126
        dc.l    gfx_RemIBob              ; 22: LVO -132
        dc.l    gfx_RemVSprite           ; 23: LVO -138
        dc.l    gfx_SetCollision         ; 24: LVO -144
        dc.l    gfx_SortGList            ; 25: LVO -150
        dc.l    gfx_AddAnimOb            ; 26: LVO -156
        dc.l    gfx_Animate              ; 27: LVO -162
        dc.l    gfx_GetGBuffers          ; 28: LVO -168
        dc.l    gfx_InitGMasks           ; 29: LVO -174
        dc.l    gfx_DrawEllipse          ; 30: LVO -180 DrawEllipse(rp a1, cx d0, cy d1, a d2, b d3)
        dc.l    gfx_AreaEllipse          ; 31: LVO -186 AreaEllipse(rp a1, cx d0, cy d1, a d2, b d3)
        dc.l    gfx_LoadRGB4             ; 32: LVO -192 LoadRGB4(vp a0, colours a1, count d0)
        dc.l    gfx_InitRastPort         ; 33: LVO -198
        dc.l    gfx_InitVPort            ; 34: LVO -204 InitVPort(vp a0)
        dc.l    gfx_MrgCop               ; 35: LVO -210
        dc.l    gfx_MakeVPort            ; 36: LVO -216
        dc.l    gfx_LoadView             ; 37: LVO -222
        dc.l    gfx_WaitBlit             ; 38: LVO -228
        dc.l    gfx_SetRast              ; 39: LVO -234
        dc.l    gfx_Move                 ; 40: LVO -240
        dc.l    gfx_Draw                 ; 41: LVO -246
        dc.l    gfx_AreaMove             ; 42: LVO -252 AreaMove(rp a1, x d0, y d1)
        dc.l    gfx_AreaDraw             ; 43: LVO -258 AreaDraw(rp a1, x d0, y d1)
        dc.l    gfx_AreaEnd              ; 44: LVO -264 AreaEnd(rp a1)
        dc.l    gfx_WaitTOF              ; 45: LVO -270 WaitTOF()
        dc.l    gfx_QBlit                ; 46: LVO -276 QBlit(bltnode a1)
        dc.l    gfx_InitArea             ; 47: LVO -282 InitArea(areaInfo a0, buffer a1, maxVectors d0)
        dc.l    gfx_SetRGB4              ; 48: LVO -288 SetRGB4(vp a0, n d0, r d1, g d2, b d3)
        dc.l    gfx_QBSBlit              ; 49: LVO -294 QBSBlit(bltnode a1)
        dc.l    gfx_BltClear             ; 50: LVO -300 BltClear(memory a1, size d0, flags d1)
        dc.l    gfx_RectFill             ; 51: LVO -306
        dc.l    gfx_BltPattern           ; 52: LVO -312 BltPattern(rp a1, mask a0, xl d0, yl d1, maxX d2, maxY d3, bpr d4)
        dc.l    gfx_ReadPixel            ; 53: LVO -318
        dc.l    gfx_WritePixel           ; 54: LVO -324
        dc.l    gfx_Flood                ; 55: LVO -330 Flood(rp a1, mode d2, x d0, y d1)
        dc.l    gfx_PolyDraw             ; 56: LVO -336 PolyDraw(rp a1, count d0, points a0)
        dc.l    gfx_SetAPen              ; 57: LVO -342
        dc.l    gfx_SetBPen              ; 58: LVO -348
        dc.l    gfx_SetDrMd              ; 59: LVO -354
        dc.l    gfx_InitView             ; 60: LVO -360 InitView(view a1)
        dc.l    gfx_CBump                ; 61: LVO -366 CBump(ucl a1)
        dc.l    gfx_CMove                ; 62: LVO -372 CMove(ucl a1, register d0, value d1)
        dc.l    gfx_CWait                ; 63: LVO -378 CWait(ucl a1, v d0, h d1)
        dc.l    gfx_VBeamPos             ; 64: LVO -384 VBeamPos()
        dc.l    gfx_InitBitMap           ; 65: LVO -390
        dc.l    gfx_ScrollRaster         ; 66: LVO -396
        dc.l    gfx_WaitBOVP             ; 67: LVO -402 WaitBOVP(vp a0)
        dc.l    gfx_GetSprite            ; 68: LVO -408
        dc.l    gfx_FreeSprite           ; 69: LVO -414 FreeSprite(number d0)
        dc.l    gfx_ChangeSprite         ; 70: LVO -420
        dc.l    gfx_MoveSprite           ; 71: LVO -426
        dc.l    gfx_LockLayerRom         ; 72: LVO -432
        dc.l    gfx_UnlockLayerRom       ; 73: LVO -438
        dc.l    gfx_SyncSBitMap          ; 74: LVO -444 SyncSBitMap(layer a0)
        dc.l    gfx_CopySBitMap          ; 75: LVO -450 CopySBitMap(layer a0)
        dc.l    gfx_OwnBlitter           ; 76: LVO -456
        dc.l    gfx_DisownBlitter        ; 77: LVO -462
        dc.l    gfx_InitTmpRas           ; 78: LVO -468 InitTmpRas(tmpRas a0, buffer a1, size d0)
        dc.l    gfx_AskFont              ; 79: LVO -474
        dc.l    gfx_AddFont              ; 80: LVO -480
        dc.l    gfx_RemFont              ; 81: LVO -486
        dc.l    gfx_AllocRaster          ; 82: LVO -492
        dc.l    gfx_FreeRaster           ; 83: LVO -498
        dc.l    gfx_AndRectRegion        ; 84: LVO -504
        dc.l    gfx_OrRectRegion         ; 85: LVO -510
        dc.l    gfx_NewRegion            ; 86: LVO -516
        dc.l    gfx_ClearRectRegion      ; 87: LVO -522
        dc.l    gfx_ClearRegion          ; 88: LVO -528
        dc.l    gfx_DisposeRegion        ; 89: LVO -534
        dc.l    gfx_FreeVPortCopLists    ; 90: LVO -540
        dc.l    gfx_FreeCopList          ; 91: LVO -546 FreeCopList(coplist a0)
        dc.l    gfx_ClipBlit             ; 92: LVO -552 ClipBlit(source rp a0, ..., dest rp a1, ..., minterm d6)
        dc.l    gfx_XorRectRegion        ; 93: LVO -558
        dc.l    gfx_FreeCprList          ; 94: LVO -564 FreeCprList(cprlist a0)
        dc.l    gfx_GetColorMap          ; 95: LVO -570 GetColorMap(entries d0) -> d0
        dc.l    gfx_FreeColorMap         ; 96: LVO -576 FreeColorMap(colormap a0)
        dc.l    gfx_GetRGB4              ; 97: LVO -582 GetRGB4(colormap a0, n d0)
        dc.l    gfx_ScrollVPort          ; 98: LVO -588 ScrollVPort(vp a0)
        dc.l    gfx_UCopperListInit      ; 99: LVO -594 UCopperListInit(ucl a0, count d0)
        dc.l    gfx_FreeGBuffers         ; 100: LVO -600
        dc.l    gfx_BltBitMapRastPort    ; 101: LVO -606
        dc.l    gfx_OrRegionRegion       ; 102: LVO -612
        dc.l    gfx_XorRegionRegion      ; 103: LVO -618
        dc.l    gfx_AndRegionRegion      ; 104: LVO -624
        dc.l    gfx_SetRGB4CM            ; 105: LVO -630 SetRGB4CM(colormap a0, n d0, r d1, g d2, b d3)
        dc.l    gfx_BltMaskBitMapRastPort ; 106: LVO -636 BltMaskBitMapRastPort(..., minterm d6, mask a2)
        dcb.l   2,graphics_private       ; 107..108: LVO -642/-648 (private)
        dc.l    gfx_AttemptLockLayerRom  ; 109: LVO -654 AttemptLockLayerRom(layer a5) -> d0
        dc.l    -1
graphics_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)   ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34            ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(lib a6): increments the open count, returns the base (OpenLibrary convention).
graphics_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
graphics_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
graphics_expunge:
        moveq   #0,d0               ; no expunge in this milestone (resident base)
        rts
graphics_null:
        moveq   #0,d0
        rts
; graphicsPrivate1/2: d0 = a6, nothing else (graphics-raster §10.5).
graphics_private:
        move.l  a6,d0
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Sets the name (V34 quirk) and allocates the empty sprite.
graphics_initfunc:
        move.l  a2,-(sp)
        move.l  d0,a2
        lea     graphics_name(pc),a0
        move.l  a0,LN_NAME(a2)
        moveq   #8,d0                ; empty sprite (POS/CTL = 0: channel off), read by DMA -> chip
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,gb_SprNull(a2)
        lea     gb_SprSS(a2),a0
        move.l  a0,gb_SimpleSprites(a2)
        move.w  #GFX_COLOR_BIT,gb_system_bplcon0(a2)
        bsr     gfx_detect_std       ; PAL or NTSC: public GfxBase values + ExecBase VBlankFrequency
        bsr     gfx_longframe
        lea     gb_TOFWaitQ(a2),a1
        jsr     newlist
        lea     gb_BlitSem(a2),a0
        jsr     LVO_INITSEMAPHORE(a6)
        move.w  #-1,gb_BlitLock(a2)
        move.w  #-1,gb_BlitNest(a2)
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_BLITTER),DMACON ; blitter permanently enabled, like 1.3: a
                                     ; program that saves then restores DMACON must find it again
        move.l  #-1,CUSTOM+$044      ; known masks at startup: direct blitter users can inherit this state
        jsr     gfx_fontinit
        moveq   #GFX_COPINIT_SIZE,d0 ; copinit (COP1LC): wait for line 12 then jump to COP2LC
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,gb_copinit(a2)
        beq.s   .gi_vb
        move.l  d0,a0
        lea     gfx_copinit(pc),a1
        moveq   #GFX_COPINIT_SIZE/2-1,d0
.gi_ci:
        move.w  (a1)+,(a0)+
        dbra    d0,.gi_ci
.gi_vb:
        lea     gb_vbsrv(a2),a1
        move.b  #GFX_VBPRI,LN_PRI(a1)
        lea     gfx_vblank(pc),a0
        bsr     gfx_intinit
        moveq   #INTB_VERTB,d0
        jsr     LVO_ADDINTSERVER(a6)
        lea     gb_bltsrv(a2),a1     ; blitter vector: some programs look for GfxBase there (iv_Data)
        lea     gfx_bltint(pc),a0
        bsr     gfx_intinit
        moveq   #INTB_BLIT,d0
        jsr     LVO_SETINTVECTOR(a6)
        move.l  a2,d0
        move.l  (sp)+,a2
        rts

; gfx_detect_std(GfxBase a2, SysBase a6): the standard is the Agnus's, read from the beam as 1.3 does
; (graphics-display-v34 §8.1; the Agnus ID bits of VPOSR are never used): a line above 270 means PAL; wrapping to the
; top without passing 270 means NTSC. A wrap counts only when the sample just before it was past line 240, i.e. the
; end of the frame was watched: an interrupt that keeps this loop away for more than about 40 lines can jump from a
; PAL line below 270 to the next frame (A15: PAL A500s booted as NTSC). Two such wraps are needed, so a VPOSR/VHPOSR
; pair torn at line 256 cannot decide either. Bounded loop (PAL if the beam never moves).
; Fills the standard-dependent GfxBase fields (§1.8) and ExecBase VBlankFrequency. Clobbers d0/d1/a0.
gfx_detect_std:
        movem.l d2-d3,-(sp)
        move.l  #10000,d2            ; ~20 us per pass on a 7 MHz 68000: ~10 frames before giving up
        moveq   #0,d1                ; d1 = previous line
        moveq   #0,d3                ; d3 = watched NTSC wraps
.ds_lp:
        bsr     gfx_VBeamPos
        cmp.w   #270,d0
        bhi.s   .ds_pal
        cmp.w   d1,d0
        bcc.s   .ds_next             ; no wrap
        cmp.w   #240,d1
        bls.s   .ds_next             ; the frame's end was not watched
        addq.b  #1,d3
        cmp.b   #2,d3
        beq.s   .ds_ntsc
.ds_next:
        move.w  d0,d1
        subq.l  #1,d2
        bne.s   .ds_lp
.ds_pal:
        lea     gfx_std_pal(pc),a0
        bra.s   .ds_set
.ds_ntsc:
        lea     gfx_std_ntsc(pc),a0
.ds_set:
        move.b  (a0)+,EB_VBLANKFREQ(a6)
        addq.l  #1,a0
        move.w  (a0)+,gb_DisplayFlags(a2)
        move.w  (a0)+,gb_MaxDisplayRow(a2)
        move.w  (a0),PTR_YLIM        ; the intuition pointer stays within the display height
        move.w  (a0)+,gb_NormalDisplayRows(a2)
        move.w  (a0)+,gb_NormalDPMX(a2)
        move.w  (a0)+,gb_NormalDPMY(a2)
        move.w  #$1D1,gb_MaxDisplayColumn(a2) ; the same for both standards
        move.w  #640,gb_NormalDisplayColumns(a2)
        move.w  #$3F9D,gb_MicrosPerLine(a2)
        move.w  #$30,gb_MinDisplayColumn(a2)
        movem.l (sp)+,d2-d3
        rts
; VBlankFrequency (+ pad), DisplayFlags, MaxDisplayRow, NormalDisplayRows, NormalDPMX, NormalDPMY (spec §1.8, §8.2)
gfx_std_pal:
        dc.b    50,0
        dc.w    DISPF_PAL,311,256,$4CA,$513
gfx_std_ntsc:
        dc.b    60,0
        dc.w    DISPF_NTSC,261,200,$500,$44A

; gfx_intinit(interrupt a1, code a0, GfxBase a2): NT_INTERRUPT node named "graphics.library", is_Data = GfxBase.
gfx_intinit:
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        move.l  a0,IS_CODE(a1)
        lea     graphics_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.l  a2,IS_DATA(a1)
        rts

; gfx_bltint(a0 = $DFF000): task-side engines serialize register programming; this vector acknowledges completion.
gfx_bltint:
        move.w  #INTF_BLIT,INTREQ-CUSTOM(a0)
        rts

; gfx_vblank(a1 = GfxBase, a6 = SysBase): VBlank server (graphics-display-v34 §7.2). Clears gb_VBlank, reloads
; COP2LC with gb_LOFlist (the displayed view's list, or the empty list after LoadView(NULL)), as 1.3 does: a program
; that writes COP2LC with interrupts off sees its list executed by the copinit until it re-enables them (Caesar's
; FLT intro). Interlace: gb_SHFlist on short frames (VPOSR LOF bit clear), for the copinit's jump at line 12.
; Then CIA-B's TOD (an HSYNC counter) restarts from the current line, and every WaitTOF task gets SIGF_SINGLE.
; Returns Z = 1 (the chain continues). Clobbers d0/d1/a0/a1/a5.
gfx_vblank:
        clr.b   gb_VBlank(a1)
        move.l  gb_LOFlist(a1),d0
        beq.s   .vb_tod
        btst    #2,gb_Modes+1(a1)
        beq.s   .vb_set
        tst.w   VPOSR
        bmi.s   .vb_set
        move.l  gb_SHFlist(a1),d1
        beq.s   .vb_set
        move.l  d1,d0
.vb_set:
        move.l  d0,COP2LC
.vb_tod:
        lea     CIAB_HW,a0
        bclr    #7,$F00(a0)          ; CRB ALARM = 0: the writes set the time
        moveq   #0,d0                ; MOVE, not CLR (a CLR reads TODHI first, which latches the TOD)
        move.b  d0,$A00(a0)          ; TODHI
        move.b  d0,$900(a0)          ; TODMID
        move.b  VHPOSR,$800(a0)      ; TODLO = current line, counting restarts
        bset    #7,$F00(a0)          ; left on ALARM, as 1.3 leaves it
        move.l  gb_TOFWaitQ(a1),a5
.vb_sig:
        tst.l   (a5)
        beq.s   .vb_ret
        move.l  LN_NAME(a5),a1
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_SIGNAL(a6)
        move.l  (a5),a5
        bra.s   .vb_sig
.vb_ret:
        moveq   #0,d0
        rts
GFX_VBPRI       EQU 10
SIGF_SINGLE     EQU $10
WT_NODE         EQU 14           ; struct Node

gfx_copinit:
        dc.w    $0C01,$FFFE          ; WAIT line 12
        dc.w    COPJMP2-CUSTOM,0     ; jump to COP2LC
        dc.w    $FFFF,$FFFE
GFX_COPINIT_SIZE EQU 12
GFX_COPINIT_END  EQU 8               ; offset of the final WAIT: the empty list of LoadView(NULL)

; === M4c2: display engine (copper list GENERATED from the structures) ===
; Amiga convention for the 3 functions: a6 = GfxBase, preserve d2-d7/a2-a6, scratch d0/d1/a0/a1.
; AllocMem requires a6 = SysBase -> we save/restore a6 and take SysBase via ($4).w.

; gfx_MakeVPort(view a0, vp a1): builds the ViewPort's copper fragment in vp_DspIns (chip RAM), layout in graphics.i.
; GENERIC (like the real graphics.library, spec graphics-display §4.2-4.5): settings at the lead-in line L0 with the
; planes off - DIW (vertical window open from line 5 to $140, BPLCON0 cuts each ViewPort out), DDF, BPLCON0-2,
; modulos, one BPLxPT per plane, the colours -; then WAIT(top) + BPLCON0 on, the user instructions, WAIT(bottom) +
; BPLCON0 off. Lines are relative to the top of the ViewPort: MrgCop adds View.DyOffset + vp.DyOffset, so moving a
; ViewPort only needs MrgCop. Horizontal window from DWidth, vp.DxOffset, View.DxOffset and RxOffset (mv_horz, §4.4:
; right and left clipping, fine scroll, fetch). Colours: ncol (§4.2), plus COLOR16.. with SPRITES. An existing
; fragment is reused.
; Modes: BPLCON0 takes HIRES, HAM and DUALPF from vp.Modes, BPLCON2 takes PFBA. DUALPF with RasInfo->Next: playfield 1
; (RasInfo) feeds BPL1/3/5, playfield 2 (Next) BPL2/4/6, each with its own scroll (BPLCON1 low/high nibble), modulo
; and offset; the one that starts fetching later gets the common DDFSTRT and fetches one word more (§4.4). Depth
; capped at 5 unless HAM, DUALPF or EXTRA_HALFBRITE.
; Interlace (§4.2-4.5): a LACE vp counts its lines in interlaced lines (MrgCop halves them); BPLCON0 carries the
; View's LACE bit; with View and vp LACE the modulo skips the other field's line and MrgCop gives the short-frame
; list the plane pointers + BytesPerRow.
MV_OFF   EQU -2                      ; BPLCON0 with the planes off
MV_DDF   EQU -4                      ; DDFSTRT
MV_DDFE  EQU -6                      ; DDFSTOP
MV_MOD1  EQU -8
MV_MOD2  EQU -10
MV_CON1  EQU -12                     ; BPLCON1
MV_DIWS  EQU -14                     ; horizontal start and stop of the display window
MV_DIWE  EQU -16
MV_DEPTH EQU -18                     ; planes, both playfields
MV_OFF1  EQU -22                     ; plane offsets
MV_OFF2  EQU -26
MV_BM2   EQU -30                     ; BitMap of playfield 2 | 0
MV_VIEW  EQU -34
MV_GFX   EQU -38                     ; GfxBase
MV_S1    EQU -40                     ; fine scrolls of the two playfields
MV_S2    EQU -42
MV_LOC   EQU 42
gfx_MakeVPort:
        GTRACE  2
        movem.l d2-d7/a2-a6,-(sp)
        link    a5,#-MV_LOC
        move.l  a0,MV_VIEW(a5)
        move.l  a6,MV_GFX(a5)
        move.w  v_Modes(a0),d0
        and.w   #V_LACE,d0
        or.w    #GFX_COLOR_BIT,d0
        move.w  d0,MV_OFF(a5)
        move.l  a1,a2                ; a2 = ViewPort
        move.l  vp_DspIns(a2),d0
        bne.s   .mv_have
        move.l  ($4).w,a6            ; a6 = SysBase
        move.l  #GFX_FRAG_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .mv_ret              ; alloc failed -> vp_DspIns stays 0
.mv_have:
        move.l  d0,a3                ; a3 = fragment (chip)
        move.l  a3,a1
        move.w  #(GFX_FRAG_SIZE/2)-1,d1
.mv_clr:
        clr.w   (a1)+
        dbra    d1,.mv_clr
        move.l  vp_RasInfo(a2),a0
        move.l  ri_BitMap(a0),a4     ; a4 = BitMap of playfield 1
        bsr     gfx_vpbm2
        move.l  d0,MV_BM2(a5)
        move.w  d1,MV_DEPTH(a5)
        lea     4(a3),a1             ; a1 = write pointer, after the header (0: not merged)
        moveq   #-1,d0               ; lead-in line L0: -2 with more than 4 planes (not DUALPF), or more than 3
        move.w  MV_DEPTH(a5),d1      ; with SPRITES; doubled for a LACE vp
        cmp.w   #4,d1
        bls.s   .mv_l0s3
        btst    #2,vp_Modes(a2)      ; DUALPF ($0400)
        beq.s   .mv_l0m2
.mv_l0s3:
        cmp.w   #3,d1
        bls.s   .mv_l0
        btst    #6,vp_Modes(a2)      ; SPRITES ($4000)
        beq.s   .mv_l0
.mv_l0m2:
        moveq   #-2,d0
.mv_l0:
        btst    #2,vp_Modes+1(a2)    ; LACE vp: interlaced lines
        beq.s   .mv_l0s
        add.w   d0,d0
.mv_l0s:
        moveq   #0,d1
        bsr     gfx_pwait
        move.l  a1,-(sp)
        moveq   #0,d5                ; horizontal window of playfield 1 (with the scroll of playfield 2 for xmax)
        tst.l   MV_BM2(a5)
        beq.s   .mv_h1
        move.l  vp_RasInfo(a2),a1
        move.l  ri_Next(a1),a1
        bsr     mv_sraw
        move.w  d0,d5
.mv_h1:
        move.l  vp_RasInfo(a2),a1
        bsr     mv_horz
        move.w  d0,MV_DDF(a5)
        move.w  d1,MV_DDFE(a5)
        move.w  d2,MV_S1(a5)
        move.w  d2,MV_S2(a5)
        move.w  d3,MV_DIWS(a5)
        move.w  d4,MV_DIWE(a5)
        move.l  d7,MV_OFF1(a5)
        move.l  d7,MV_OFF2(a5)
        move.l  MV_BM2(a5),d0
        beq.s   .mv_fetch
        move.l  vp_RasInfo(a2),a1    ; playfield 2
        bsr     mv_sraw
        move.w  d0,d5
        move.l  ri_Next(a1),a1
        move.l  a4,-(sp)
        move.l  MV_BM2(a5),a4
        bsr     mv_horz
        move.l  (sp)+,a4
        move.w  d2,MV_S2(a5)
        move.l  d7,MV_OFF2(a5)
        cmp.w   MV_S1(a5),d2
        beq.s   .mv_same
        subq.w  #1,MV_DIWE(a5)       ; different scrolls: one pixel less on the right
.mv_same:
        moveq   #2,d6                ; the playfield that starts fetching later fetches one word earlier
        tst.w   vp_Modes(a2)
        bpl.s   .mv_step
        moveq   #4,d6
.mv_step:
        cmp.w   MV_DDF(a5),d0
        beq.s   .mv_stop
        bhi.s   .mv_pf2late
        sub.l   d6,MV_OFF1(a5)
        move.w  d0,MV_DDF(a5)
        bra.s   .mv_stop
.mv_pf2late:
        sub.l   d6,MV_OFF2(a5)
.mv_stop:
        cmp.w   MV_DDFE(a5),d1
        bls.s   .mv_fetch
        move.w  d1,MV_DDFE(a5)
.mv_fetch:
        move.w  MV_DDFE(a5),d2       ; bytes fetched per line: HIRES ((STOP - STRT) / 2 + 6) & ~3, LORES
        sub.w   MV_DDF(a5),d2        ; (STOP - STRT) / 4 + 2; modulo = BytesPerRow - that (§4.4 point 9)
        tst.w   vp_Modes(a2)
        bpl.s   .mv_flo
        lsr.w   #1,d2
        addq.w  #6,d2
        and.w   #~3,d2
        bra.s   .mv_fset
.mv_flo:
        lsr.w   #2,d2
        addq.w  #2,d2
.mv_fset:
        move.w  bm_BytesPerRow(a4),d6
        sub.w   d2,d6
        move.w  MV_OFF(a5),d0
        bsr     gfx_lacemod
        move.w  d6,MV_MOD1(a5)
        move.w  d6,MV_MOD2(a5)
        move.l  MV_BM2(a5),d0
        beq.s   .mv_con
        move.l  a4,-(sp)
        move.l  d0,a4
        move.w  bm_BytesPerRow(a4),d6
        sub.w   d2,d6
        move.w  MV_OFF(a5),d0
        bsr     gfx_lacemod
        move.w  d6,MV_MOD2(a5)
        move.l  (sp)+,a4
.mv_con:
        move.w  MV_S2(a5),d0         ; BPLCON1 = s1 | s2 << 4
        lsl.w   #4,d0
        or.w    MV_S1(a5),d0
        move.w  d0,MV_CON1(a5)
        move.l  (sp)+,a1
        move.w  #DIWSTRT-CUSTOM,(a1)+
        move.w  MV_DIWS(a5),d0
        and.w   #$00FF,d0
        or.w    #$0500,d0
        move.w  d0,(a1)+
        move.w  #DIWSTOP-CUSTOM,(a1)+
        move.w  MV_DIWE(a5),d0
        and.w   #$00FF,d0
        or.w    #$4000,d0
        move.w  d0,(a1)+
        move.w  #DDFSTRT-CUSTOM,(a1)+
        move.w  MV_DDF(a5),(a1)+
        move.w  #DDFSTOP-CUSTOM,(a1)+
        move.w  MV_DDFE(a5),(a1)+
        move.w  #BPLCON0-CUSTOM,(a1)+
        move.w  MV_OFF(a5),(a1)+     ; planes off until the top of the ViewPort
        move.w  #BPLCON1-CUSTOM,(a1)+
        move.w  MV_CON1(a5),(a1)+    ; fine scroll
        move.w  #BPLCON2-CUSTOM,(a1)+
        move.w  vp_Modes(a2),d0
        and.w   #V_PFBA,d0
        or.w    #GFX_BPLCON2,d0      ; sprites in front of both playfields (pointer visible everywhere)
        move.w  d0,(a1)+
        move.w  #BPL1MOD-CUSTOM,(a1)+
        move.w  MV_MOD1(a5),(a1)+
        move.w  #BPL2MOD-CUSTOM,(a1)+
        move.w  MV_MOD2(a5),(a1)+
        ; bitplane pointers: register k = plane k of playfield 1, or with two playfields plane k/2 of playfield
        ; 1 (k even) or 2 (k odd)
        moveq   #0,d4                ; d4 = k
        move.w  #BPL1PTH-CUSTOM,d3   ; d3 = offset of the current BPLxPTH register
.mv_plane:
        cmp.w   MV_DEPTH(a5),d4
        bhs.s   .mv_planes
        move.w  d4,d0
        move.l  a4,a0
        move.l  MV_OFF1(a5),d5
        tst.l   MV_BM2(a5)
        beq.s   .mv_pidx
        lsr.w   #1,d0
        btst    #0,d4
        beq.s   .mv_pidx
        move.l  MV_BM2(a5),a0
        move.l  MV_OFF2(a5),d5
.mv_pidx:
        lsl.w   #2,d0
        add.l   bm_Planes(a0,d0.w),d5 ; d5 = address of the plane + offset
        move.w  d3,(a1)+             ; BPLxPTH
        move.l  d5,d2
        swap    d2
        move.w  d2,(a1)+             ; HIGH word
        addq.w  #2,d3                ; -> BPLxPTL
        move.w  d3,(a1)+
        move.w  d5,(a1)+             ; LOW word
        addq.w  #2,d3                ; -> BPL(x+1)PTH
        addq.w  #1,d4
        bra.s   .mv_plane
.mv_planes:
        ; colours (§4.2-4.3): ncol = 16 with HAM or DUALPF, otherwise 1 << min(depth, 5), emitted whatever Count is;
        ; with SPRITES and fewer than 5 planes also COLOR16..COLOR(Count-1) (Count at most 32; 32 without ColorMap)
        lea     gfx_defcolors(pc),a0
        moveq   #32,d5               ; d5 = Count
        move.l  vp_ColorMap(a2),d0
        beq.s   .mv_ctab
        move.l  d0,a0
        move.w  cm_Count(a0),d5
        cmp.w   #32,d5
        bls.s   .mv_cnt
        moveq   #32,d5
.mv_cnt:
        move.l  cm_ColorTable(a0),a0
.mv_ctab:
        move.l  a0,d2                ; d2 = colour table
        moveq   #16,d4               ; d4 = ncol
        move.w  vp_Modes(a2),d0
        and.w   #V_HAM|V_DUALPF,d0
        bne.s   .mv_ncol
        move.w  MV_DEPTH(a5),d0
        cmp.w   #5,d0
        bls.s   .mv_nd
        moveq   #5,d0
.mv_nd:
        moveq   #1,d4
        lsl.w   d0,d4
.mv_ncol:
        move.w  #COLOR00-CUSTOM,d3
        bsr.s   .mv_cols
        btst    #6,vp_Modes(a2)      ; SPRITES: the sprite colours too
        beq.s   .mv_cend
        cmp.w   #5,MV_DEPTH(a5)
        bhs.s   .mv_cend
        move.w  d5,d4
        sub.w   #16,d4
        ble.s   .mv_cend
        move.l  d2,a0
        lea     32(a0),a0
        move.w  #COLOR00-CUSTOM+32,d3
        bsr.s   .mv_cols
        bra.s   .mv_cend
.mv_cols:                            ; d4 colours from (a0) into COLOR registers from d3
        move.w  d3,(a1)+
        move.w  (a0)+,(a1)+
        addq.w  #2,d3
        subq.w  #1,d4
        bne.s   .mv_cols
        rts
.mv_cend:
        moveq   #0,d0                ; top of the ViewPort: planes on
        moveq   #0,d1
        bsr     gfx_pwait
        move.w  MV_DEPTH(a5),d2
        lsl.w   #8,d2
        lsl.w   #4,d2                ; depth << 12
        or.w    MV_OFF(a5),d2        ; | COLOR | View LACE
        move.w  vp_Modes(a2),d0
        and.w   #V_HIRES|V_HAM|V_DUALPF,d0
        or.w    d0,d2                ; same bits in BPLCON0
        move.w  #BPLCON0-CUSTOM,(a1)+
        move.w  d2,(a1)+
        move.w  vp_DHeight(a2),d0    ; bottom of the ViewPort: planes off
        moveq   #0,d1
        bsr     gfx_pwait
        move.w  #BPLCON0-CUSTOM,(a1)+
        move.w  MV_OFF(a5),(a1)+
        move.w  #GFX_PSEUDO,(a1)+    ; end of the fragment
        move.w  #GFX_PEND,(a1)+
        move.l  a3,vp_DspIns(a2)     ; publishes the fragment
.mv_ret:
        unlk    a5
        movem.l (sp)+,d2-d7/a2-a6
        rts

; gfx_vpbm2(vp a2, BitMap of playfield 1 a4) -> d0 = BitMap of playfield 2 (DUALPF with RasInfo->Next and a BitMap),
; else 0; d1.w = planes of both, capped at 5 unless HAM, DUALPF or EXTRA_HALFBRITE, and at 6. Clobbers a6.
gfx_vpbm2:
        moveq   #0,d1
        move.b  bm_Depth(a4),d1
        moveq   #0,d0
        btst    #2,vp_Modes(a2)      ; DUALPF
        beq.s   .b2_cap
        move.l  vp_RasInfo(a2),a6
        move.l  ri_Next(a6),d0
        beq.s   .b2_cap
        move.l  d0,a6
        move.l  ri_BitMap(a6),d0
        beq.s   .b2_cap
        move.l  d0,a6
        moveq   #0,d0
        move.b  bm_Depth(a6),d0
        add.w   d0,d1
        move.l  a6,d0
.b2_cap:
        cmp.w   #5,d1
        bls.s   .b2_ret
        move.l  d0,-(sp)
        move.w  vp_Modes(a2),d0
        and.w   #V_HAM|V_DUALPF|V_EHB,d0
        movem.l (sp)+,d0             ; (flags kept)
        bne.s   .b2_six
        moveq   #5,d1
.b2_six:
        cmp.w   #6,d1
        bls.s   .b2_ret
        moveq   #6,d1
.b2_ret:
        rts

; gfx_shfplanes(a0 = first BPLxPTH MOVE of a ViewPort in a short-frame list, a1 = vp): each plane pointer one row
; further (BytesPerRow of the playfield the plane belongs to). Clobbers d0-d3/a0/a6.
gfx_shfplanes:
        move.l  a2,-(sp)
        move.l  a4,-(sp)
        move.l  a1,a2
        move.l  vp_RasInfo(a2),a6
        move.l  ri_BitMap(a6),a4
        bsr.s   gfx_vpbm2
        move.l  d0,d3                ; d3 = BitMap of playfield 2 | 0
        move.w  d1,d2                ; d2 = planes
        moveq   #0,d1                ; d1 = k
.sp_lp:
        cmp.w   d2,d1
        bhs.s   .sp_ret
        move.l  a4,a6
        tst.l   d3
        beq.s   .sp_bpr
        btst    #0,d1
        beq.s   .sp_bpr
        move.l  d3,a6
.sp_bpr:
        move.w  2(a0),d0
        swap    d0
        move.w  6(a0),d0
        add.w   bm_BytesPerRow(a6),d0 ; (BytesPerRow < 64 KB: carry handled below)
        bcc.s   .sp_nc
        add.l   #$10000,d0
.sp_nc:
        move.w  d0,6(a0)
        swap    d0
        move.w  d0,2(a0)
        addq.l  #8,a0
        addq.w  #1,d1
        bra.s   .sp_lp
.sp_ret:
        move.l  (sp)+,a4
        move.l  (sp)+,a2
        rts

; gfx_lacemod(d0.w = View Modes (only LACE is read), a2 = vp, a4 = BitMap, d6.w = modulo): with View and vp both
; LACE, each field skips the other one's lines: modulo + BytesPerRow (§4.4 point 9).
gfx_lacemod:
        btst    #2,vp_Modes+1(a2)
        beq.s   .lm_ret
        and.w   #V_LACE,d0
        beq.s   .lm_ret
        add.w   bm_BytesPerRow(a4),d6
.lm_ret:
        rts

; gfx_shfpos(a6 = GfxBase, d0 = address in the active View's long-frame list) -> d0 = the same place in its
; short-frame list, which MrgCop lays out word for word like the long one; 0 if the View is not interlaced.
; Clobbers a1.
gfx_shfpos:
        move.l  gb_ActiView(a6),a1
        cmpa.w  #0,a1
        beq.s   .sh_none
        btst    #2,v_Modes+1(a1)
        beq.s   .sh_none
        tst.l   v_SHFCprList(a1)
        beq.s   .sh_none
        sub.l   v_LOFCprList(a1),d0
        add.l   v_SHFCprList(a1),d0
        rts
.sh_none:
        moveq   #0,d0
        rts

; gfx_pwait(a1 = write pointer, d0.w = line relative to the top of the ViewPort, d1.w = horizontal position):
; writes the 3-entry pseudo-WAIT that MrgCop translates (graphics.i). a1 advances by 12.
gfx_pwait:
        move.w  #GFX_PSEUDO,(a1)+
        move.w  d0,(a1)+
        move.w  d1,(a1)+
        clr.w   (a1)+
        move.w  #GFX_NOP,(a1)+
        clr.w   (a1)+
        rts

; mv_sraw(a1 = RasInfo, a2 = vp) -> d0.w = fine scroll the RasInfo asks for: (-RxOffset) & 15, in HIRES
; (-(RxOffset >> 1)) & 7 (spec graphics-display §4.4 point 1). Preserves the rest.
mv_sraw:
        move.w  ri_RxOffset(a1),d0
        tst.w   vp_Modes(a2)
        bpl.s   .sr_lo
        asr.w   #1,d0
        neg.w   d0
        and.w   #7,d0
        rts
.sr_lo:
        neg.w   d0
        and.w   #15,d0
        rts

; mv_horz(a1 = RasInfo, a2 = vp, a4 = its BitMap, a5 = MakeVPort frame, d5.w = scroll of the other playfield | 0)
; -> d0 = DDFSTRT, d1 = DDFSTOP, d2 = fine scroll, d3/d4 = horizontal start/stop of the display window, d7 = plane
; offset (spec graphics-display §4.4 points 1-10: w, x and rx halved in HIRES; right clipping at MaxDisplayColumn,
; 10 earlier with a scroll; the shift of the window folded into the fine scroll; one more word fetched for a scroll;
; left clipping at MinDisplayColumn / 2 by moving the start right and starting again; DDFSTOP capped at $D8, $D4 in
; HIRES). Clobbers d6/a0.
mv_horz:
        movem.l d5/a1,-(sp)
        lea     -6(sp),sp            ; w, x, rx before halving (moved by the left clipping)
        move.w  vp_DWidth(a2),(sp)
        move.w  vp_DxOffset(a2),2(sp)
        move.w  ri_RxOffset(a1),4(sp)
.hz_again:
        move.w  (sp),d4              ; d4 = w
        move.w  2(sp),d3             ; d3 = x
        move.w  4(sp),d1             ; d1 = rx
        moveq   #15,d6               ; d6 = m
        tst.w   vp_Modes(a2)
        bpl.s   .hz_lo
        asr.w   #1,d4
        asr.w   #1,d3
        asr.w   #1,d1
        moveq   #7,d6
.hz_lo:
        move.w  d1,d2
        neg.w   d2
        and.w   d6,d2                ; d2 = s
        move.l  MV_GFX(a5),a0
        move.w  gb_MaxDisplayColumn(a0),d0
        tst.w   d2
        bne.s   .hz_sx
        tst.w   d5
        beq.s   .hz_xm
.hz_sx:
        sub.w   #10,d0               ; xmax
.hz_xm:
        move.l  MV_VIEW(a5),a0
        add.w   v_DxOffset(a0),d3    ; d3 = x on the screen
        move.w  d3,d7
        add.w   d4,d7
        cmp.w   d0,d7
        ble.s   .hz_w
        move.w  d0,d4                ; right clipping
        sub.w   d3,d4
.hz_w:
        moveq   #0,d5
        tst.w   d2
        sne     d5                   ; d5 = S (one more word fetched)
        move.w  bm_BytesPerRow(a4),d7 ; offset = RyOffset x BytesPerRow + 2 x (rx >> 4, >> 3 in HIRES)
        muls    ri_RyOffset(a1),d7
        move.w  d1,d0
        asr.w   #4,d0
        tst.w   vp_Modes(a2)
        bpl.s   .hz_ox
        move.w  d1,d0
        asr.w   #3,d0
.hz_ox:
        add.w   d0,d0
        ext.l   d0
        add.l   d0,d7
        sub.w   #$81,d3              ; d3 = x'
        move.w  d3,d0                ; s += x' & m; past m it wraps and the extra word is not needed
        and.w   d6,d0
        add.w   d0,d2
        cmp.w   d6,d2
        bls.s   .hz_s
        and.w   d6,d2
        moveq   #0,d5
.hz_s:
        moveq   #$38,d0              ; d0 = B
        tst.w   vp_Modes(a2)
        bpl.s   .hz_b
        moveq   #$3C,d0
.hz_b:
        tst.b   d5
        beq.s   .hz_bs
        subq.w  #8,d0
        tst.w   vp_Modes(a2)
        bpl.s   .hz_bs
        subq.l  #2,d7
.hz_bs:
        move.w  d3,d5                ; DDFSTRT = B + ((x' >> 1) & ~7, ~3 in HIRES)
        asr.w   #1,d5
        and.w   #~7,d5
        tst.w   vp_Modes(a2)
        bpl.s   .hz_st
        move.w  d3,d5
        asr.w   #1,d5
        and.w   #~3,d5
.hz_st:
        add.w   d5,d0
        move.l  MV_GFX(a5),a0
        move.w  gb_MinDisplayColumn(a0),d5
        lsr.w   #1,d5
        cmp.w   d5,d0
        bge.s   .hz_stop
        sub.w   d0,d5                ; left clipping: d = 2 x gap (x 2 again in HIRES), then again
        add.w   d5,d5
        tst.w   vp_Modes(a2)
        bpl.s   .hz_d
        add.w   d5,d5
.hz_d:
        add.w   d5,4(sp)
        add.w   d5,2(sp)
        sub.w   d5,(sp)
        bra     .hz_again
.hz_stop:
        move.w  d4,d5                ; DDFSTOP = (((w + 15) >> 1) & ~7) + DDFSTRT - (rx & m ? 0 : 8)
        add.w   #15,d5
        asr.w   #1,d5
        and.w   #~7,d5
        add.w   d0,d5
        and.w   d6,d1
        bne.s   .hz_e
        subq.w  #8,d5
.hz_e:
        cmp.w   #$D8,d5
        ble.s   .hz_e1
        move.w  #$D8,d5
.hz_e1:
        tst.w   vp_Modes(a2)
        bpl.s   .hz_e2
        subq.w  #4,d5
        cmp.w   #$D4,d5
        ble.s   .hz_e2
        move.w  #$D4,d5
.hz_e2:
        move.w  d5,d1
        add.w   #$81,d3              ; display window: x, x + w
        add.w   d3,d4
        lea     6(sp),sp
        movem.l (sp)+,d5/a1
        rts

; gfx_fragmst(vp a0) -> d0 = address in the displayed master list of the ViewPort's first MOVEs (the fragment's
; header, graphics.i), or 0 (not in the active View, hidden, or not merged). Clobbers a1.
gfx_fragmst:
        move.l  gb_ActiView(a6),d0
        beq.s   .fm_ret
        move.l  d0,a1
        tst.l   v_LOFCprList(a1)
        beq.s   .fm_none
        move.l  v_ViewPort(a1),a1
.fm_vp:
        cmpa.w  #0,a1
        beq.s   .fm_none
        cmpa.l  a0,a1
        beq.s   .fm_in
        move.l  vp_Next(a1),a1
        bra.s   .fm_vp
.fm_in:
        move.l  vp_DspIns(a0),d0
        beq.s   .fm_ret
        move.l  d0,a1
        move.l  (a1),d0
        rts
.fm_none:
        moveq   #0,d0
.fm_ret:
        rts

; ScrollVPort(vp a0): re-applies RasInfo RxOffset/RyOffset (both playfields) to the ViewPort's DDFSTRT, BPLCON1,
; modulos and plane pointers, in its fragment (rebuilt by MakeVPort with the active View) and in the displayed lists,
; without MrgCop/LoadView (spec graphics-display §7.3), once the beam is past the ViewPort's first line. VP_HIDE or
; no fragment: nothing. Deviation: the 1.3 interlace frame swap is not reproduced (the short-frame list gets its own
; plane pointers).
gfx_ScrollVPort:
        movem.l d2-d3/a2-a3/a6,-(sp)
        move.l  a0,a2
        move.w  vp_Modes(a2),d0
        and.w   #VP_HIDE,d0
        bne.s   .sv_ret
        move.l  vp_DspIns(a2),d0
        beq.s   .sv_ret
        move.l  d0,a3
        move.l  (a3),-(sp)           ; where MrgCop put the fragment: MakeVPort clears it
        move.l  gb_ActiView(a6),d0
        bne.s   .sv_view
        lea     gfx_nullview(pc),a0
        move.l  a0,d0
.sv_view:
        move.l  d0,a0
        move.l  a2,a1
        bsr     gfx_MakeVPort
        move.l  (sp)+,(a3)
        move.w  vp_DyOffset(a2),d2   ; wait for the line after the ViewPort's first one
        addq.w  #1,d2
        move.l  gb_ActiView(a6),d0
        beq.s   .sv_wait
        move.l  d0,a0
        add.w   v_DyOffset(a0),d2
.sv_wait:
        bsr     gfx_VBeamPos
        cmp.w   d2,d0
        blt.s   .sv_wait
        move.l  a2,a0
        bsr     gfx_fragmst
        tst.l   d0
        beq.s   .sv_ret
        move.l  d0,d2                ; d2 = the fragment in the long-frame list
        move.l  d0,a1                ; the same settings MOVEs into the displayed lists
        bsr.s   .sv_put
        move.l  d2,d0
        bsr     gfx_shfpos
        tst.l   d0
        beq.s   .sv_ret
        move.l  d0,a1
        bsr.s   .sv_put
        btst    #2,vp_Modes+1(a2)
        beq.s   .sv_ret
        move.l  a1,a0
        move.l  a2,a1
        bsr     gfx_shfplanes        ; short frame: one row further
.sv_ret:
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts
; .sv_put(a1 = fragment's first MOVEs in a hardware list, a3 = fragment): copies the settings MOVEs there, up to
; the first colour; a1 is left on the first BPLxPTH MOVE. Clobbers d0/a0.
.sv_put:
        lea     16(a3),a0
        moveq   #9-1,d0
.sv_cs:
        move.l  (a0)+,(a1)+
        dbra    d0,.sv_cs
        move.l  a1,-(sp)
.sv_cpp:
        cmp.w   #COLOR00-CUSTOM,(a0)
        beq.s   .sv_pe
        move.l  (a0)+,(a1)+
        bra.s   .sv_cpp
.sv_pe:
        move.l  (sp)+,a1
        rts
gfx_nullview:
        dcb.b   v_SIZEOF,0
        even

; gfx_LoadRGB4(vp a0, colours a1, count d0): the first "count" colours ($0RGB) via SetRGB4.
gfx_LoadRGB4:
        movem.l d2-d5/a2-a3,-(sp)
        move.l  a0,a2
        move.l  a1,a3
        move.w  d0,d5                ; d5 = count
        moveq   #0,d4                ; d4 = colour number
.lr_lp:
        cmp.w   d5,d4
        bhs.s   .lr_ret
        move.w  (a3)+,d1
        move.w  d1,d3                ; b
        move.w  d1,d2
        lsr.w   #4,d2                ; g
        lsr.w   #8,d1                ; r
        move.w  d4,d0
        move.l  a2,a0
        bsr.s   gfx_SetRGB4
        addq.w  #1,d4
        bra.s   .lr_lp
.lr_ret:
        movem.l (sp)+,d2-d5/a2-a3
        rts

; gfx_SetRGB4(vp a0, n d0, r d1, g d2, b d3) -> d0 = 0, or -1 if n > 31 or n is outside the ColorMap (spec
; graphics-display §3). vp NULL: the COLORn register is written directly. Otherwise ColorTable[n] = 4-bit RGB, and
; the already generated MOVE COLORn is patched in the ViewPort's fragment and, if it belongs to the displayed view,
; at its place in the master list.
gfx_SetRGB4:
        movem.l d2-d3,-(sp)
        and.w   #15,d1
        lsl.w   #4,d1
        and.w   #15,d2
        or.w    d2,d1
        lsl.w   #4,d1
        and.w   #15,d3
        or.w    d3,d1                ; d1 = $0RGB
        cmp.w   #31,d0
        bgt.s   .sr_bad
        cmpa.w  #0,a0
        bne.s   .sr_vp
        add.w   d0,d0
        lea     COLOR00,a1
        move.w  d1,0(a1,d0.w)
        bra.s   .sr_ok
.sr_vp:
        move.l  vp_ColorMap(a0),a1
        cmpa.w  #0,a1
        beq.s   .sr_ok
        cmp.w   cm_Count(a1),d0
        bhs.s   .sr_bad
        move.l  cm_ColorTable(a1),a1
        add.w   d0,d0
        move.w  d1,0(a1,d0.w)
        add.w   #COLOR00-CUSTOM,d0   ; d0 = COLORn register
        move.l  vp_DspIns(a0),d2
        beq.s   .sr_ok
        move.l  d2,a1
        move.w  #GFX_FRAG_WORDS/2-1,d3
.sr_find:
        cmp.w   (a1),d0
        beq.s   .sr_hit
        addq.l  #4,a1
        dbra    d3,.sr_find
        bra.s   .sr_ok
.sr_hit:
        move.w  d1,2(a1)
        sub.l   d2,a1                ; a1 = position of the MOVE in the fragment
        move.l  a1,d3
        move.w  d1,d2
        bsr     gfx_fragmst
        tst.l   d0
        beq.s   .sr_ok               ; ViewPort not in the displayed view
        move.l  d0,a1
        add.l   d3,a1
        move.w  d2,-16+2(a1)         ; master = header + fragment offset - 16 (header, lead-in WAIT)
        move.l  a1,d0
        bsr     gfx_shfpos
        tst.l   d0
        beq.s   .sr_ok
        move.l  d0,a1
        move.w  d2,-2(a1)
.sr_ok:
        moveq   #0,d0
        bra.s   .sr_ret
.sr_bad:
        moveq   #-1,d0
.sr_ret:
        movem.l (sp)+,d2-d3
        rts

; gfx_FreeVPortCopLists(vp a0): frees the ViewPort's copper fragment (vp_DspIns := 0).
gfx_FreeVPortCopLists:
        movem.l a2-a3/a6,-(sp)
        move.l  a0,a2
        move.l  ($4).w,a6
        move.l  vp_DspIns(a2),d0
        beq.s   .fv_ucl
        clr.l   vp_DspIns(a2)
        move.l  d0,a1
        move.l  #GFX_FRAG_SIZE,d0
        jsr     LVO_FREEMEM(a6)
.fv_ucl:
        move.l  vp_SprIns(a2),d0     ; DrawGList's VSprite block (its size in its first long)
        beq.s   .fv_ucl2
        clr.l   vp_SprIns(a2)
        move.l  d0,a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
.fv_ucl2:
        move.l  vp_UCopIns(a2),d0    ; user list: its CopLists (instructions included) then the header
        beq.s   .fv_ret
        clr.l   vp_UCopIns(a2)
        move.l  d0,a3
        move.l  ucl_FirstCopList(a3),a0
        bsr     gfx_freecl
        move.l  a3,a1
        moveq   #UCL_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.fv_ret:
        movem.l (sp)+,a2-a3/a6
        rts

; FreeCopList(coplist a0): frees each block of the chain (its instructions, then the 34-byte header).
gfx_FreeCopList:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        bsr.s   gfx_freecl
        move.l  (sp)+,a6
        rts
; gfx_freecl(coplist a0, a6 = SysBase). Clobbers d0/d1/a0/a1.
gfx_freecl:
        move.l  a2,-(sp)
        move.l  a0,a2
.fc_lp:
        move.l  a2,d0
        beq.s   .fc_ret
        move.l  cl_CopIns(a2),a1
        moveq   #0,d0
        move.w  cl_MaxCount(a2),d0
        mulu    #CI_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a2,a1
        move.l  cl_Next(a2),a2
        moveq   #CL_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .fc_lp
.fc_ret:
        move.l  (sp)+,a2
        rts

; UCopperListInit(ucl a0, count d0) -> d0 = CopList | 0 (graphics-display §6): an existing FirstCopList is reused
; with every block of its chain emptied, otherwise a CopList of "count" instructions; it becomes the current one.
gfx_UCopperListInit:
        move.l  a2,-(sp)
        move.l  a0,a2
        move.l  ucl_FirstCopList(a2),d1
        beq.s   .ui_new
        move.l  d1,a0
.ui_rst:
        clr.w   cl_Count(a0)
        move.l  cl_CopIns(a0),cl_CopPtr(a0)
        move.l  cl_Next(a0),d0
        move.l  d0,a0
        bne.s   .ui_rst
        move.l  d1,d0
        bra.s   .ui_set
.ui_new:
        bsr.s   gfx_clalloc
        tst.l   d0
        beq.s   .ui_ret
        move.l  d0,ucl_FirstCopList(a2)
.ui_set:
        move.l  d0,ucl_CopList(a2)
.ui_ret:
        move.l  (sp)+,a2
        rts
; gfx_clalloc(d0.w = instructions) -> d0 = new CopList (CopIns = CopPtr, MaxCount) | 0. Clobbers d1/a0/a1.
gfx_clalloc:
        movem.l d2/a2/a6,-(sp)
        move.w  d0,d2
        move.l  ($4).w,a6
        moveq   #CL_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ca_ret
        move.l  d0,a2
        moveq   #0,d0
        move.w  d2,d0
        mulu    #CI_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        bne.s   .ca_ok
        move.l  a2,a1
        moveq   #CL_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        bra.s   .ca_ret
.ca_ok:
        move.l  d0,cl_CopIns(a2)
        move.l  d0,cl_CopPtr(a2)
        move.w  d2,cl_MaxCount(a2)
        move.l  a2,d0
.ca_ret:
        movem.l (sp)+,d2/a2/a6
        rts

; CMove(ucl a1, register d0, value d1) / CWait(ucl a1, v d0, h d1): write the current instruction without advancing
; (no current CopList: UCopperListInit(ucl, 16) first); CBump(ucl a1) moves to the next one, a full block going on
; to the next one of its chain (16 instructions, reused or allocated). No memory: the instruction is ignored.
gfx_CMove:
        movem.l d2-d3,-(sp)
        moveq   #0,d2                ; COPPER_MOVE
        bra.s   gfx_cput
gfx_CWait:
        movem.l d2-d3,-(sp)
        moveq   #1,d2                ; COPPER_WAIT
gfx_cput:
        move.l  ucl_CopList(a1),d3
        bne.s   .cp_have
        movem.l d0-d1/a1,-(sp)
        move.l  a1,a0
        moveq   #16,d0
        bsr     gfx_UCopperListInit
        move.l  d0,d3
        movem.l (sp)+,d0-d1/a1
        tst.l   d3
        beq.s   .cp_ret
.cp_have:
        move.l  d3,a0
        move.w  cl_Count(a0),d3
        cmp.w   cl_MaxCount(a0),d3
        bhs.s   .cp_ret
        move.l  cl_CopPtr(a0),a0
        move.w  d2,ci_OpCode(a0)
        move.w  d0,ci_Word1(a0)
        move.w  d1,ci_Word2(a0)
.cp_ret:
        movem.l (sp)+,d2-d3
        rts
gfx_CBump:
        move.l  ucl_CopList(a1),d0
        beq.s   .cb_ret
        move.l  d0,a0
        move.w  cl_Count(a0),d0
        cmp.w   cl_MaxCount(a0),d0
        bhs.s   .cb_ret              ; (its next block could not be allocated)
        addq.w  #1,cl_Count(a0)
        addq.l  #CI_SIZEOF,cl_CopPtr(a0)
        addq.w  #1,d0
        cmp.w   cl_MaxCount(a0),d0
        blo.s   .cb_ret
        move.l  cl_Next(a0),d0
        bne.s   .cb_on
        movem.l a0-a1,-(sp)
        moveq   #16,d0
        bsr     gfx_clalloc
        movem.l (sp)+,a0-a1
        tst.l   d0
        beq.s   .cb_ret
        move.l  d0,cl_Next(a0)
.cb_on:
        move.l  d0,ucl_CopList(a1)
.cb_ret:
        rts

; gfx_MrgCop(view a1): builds v_LOFCprList (master, chip RAM, layout in graphics.i) as on 1.3 (graphics-display §5):
; the sprite pointers, then the streams of every ViewPort that is not VP_HIDE (its fragment, its VSprite stream
; vp_SprIns, its UCopList read directly) merged by line: each stream's MOVEs up to its next WAIT go out together, then
; the WAIT with the smallest key (vp.DyOffset + v [/2 for a LACE vp]) * 1024 + h, the stream examined first winning a
; tie (streams are examined in the reverse order of the chain: bottom ViewPort first, UCopList before VSprites before
; the fragment). A WAIT lands on View.DyOffset + that line, capped at MaxDisplayRow - 1; the first line past 255 is
; preceded by WAIT (255, $DE), or (255, last DDFSTRT) after a HIRES 4-plane BPLCON0 with DDFSTOP $D4; a WAIT equal to
; the previous one is dropped. Each fragment's header receives where its first MOVEs landed. The list is reused if it
; is big enough, otherwise freed and reallocated. Gated by M4C2_NO_MRGCOP (RED): no fragment -> blank screen.
; Interlaced View (§5.1-5.2): v_SHFCprList, created or reused only then, is a copy of the long-frame list in which
; the plane pointers of each LACE ViewPort point one row further; each list ends by loading COP2LC with the other one.
MC_LAST  EQU -4                      ; last WAIT emitted (long)
MC_CON0  EQU -6                      ; last BPLCON0, DDFSTRT, DDFSTOP emitted
MC_DSTRT EQU -8
MC_DSTOP EQU -10
MC_NREC  EQU -12                     ; streams
MC_CROSS EQU -14                     ; != 0: line 255 passed
MC_RECS  EQU -18                     ; stream records
MC_LIST  EQU -22                     ; the list (a3)
MC_LOC   EQU 22
; stream record
R_PTR    EQU 0                       ; current instruction, 0 = stream over
R_VP     EQU 4
R_CL     EQU 8                       ; UCopList: current CopList; fragment: its header; VSprites: 0
R_KIND   EQU 12                      ; 0 = fragment format, 1 = CopIns (UCopList)
R_LEFT   EQU 14                      ; UCopList: instructions left in the current CopList
R_SIZE   EQU 16
gfx_MrgCop:
        GTRACE  1
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5                ; a5 = GfxBase
        move.l  a1,a2                ; a2 = View
        move.l  #GFX_MASTER_FIXED,d3 ; d3 = size of the block
        moveq   #0,d4                ; d4 = streams
        move.l  v_ViewPort(a2),a0
.mc_cnt:
        move.l  a0,d0
        beq.s   .mc_sized
        move.l  vp_DspIns(a0),d0
        beq.s   .mc_c1
        move.l  d0,a1
        clr.l   (a1)                 ; header: not merged
.mc_c1:
        move.w  vp_Modes(a0),d0
        and.w   #VP_HIDE,d0
        bne.s   .mc_cn
        tst.l   vp_DspIns(a0)
        beq.s   .mc_c2
        addq.w  #1,d4
        add.l   #GFX_FRAG_SIZE-4,d3
.mc_c2:
        move.l  vp_SprIns(a0),d0
        beq.s   .mc_c3
        move.l  d0,a1
        addq.w  #1,d4
        add.l   4(a1),d3
.mc_c3:
        move.l  vp_UCopIns(a0),d0
        beq.s   .mc_cn
        move.l  d0,a1
        move.l  ucl_FirstCopList(a1),d0
        beq.s   .mc_cn
        addq.w  #1,d4
.mc_ccl:
        move.l  d0,a1
        moveq   #0,d0
        move.w  cl_Count(a1),d0
        lsl.l   #3,d0                ; 8 bytes per instruction at most (two WAITs past line 255)
        add.l   d0,d3
        move.l  cl_Next(a1),d0
        bne.s   .mc_ccl
.mc_cn:
        move.l  vp_Next(a0),a0
        bra.s   .mc_cnt
.mc_sized:
        tst.w   d4                   ; no CopList at all: the existing lists are left alone (graphics-display §5.1)
        beq     .mc_ret
        move.l  v_LOFCprList(a2),d0
        beq.s   .mc_alloc
        move.l  d0,a3
        cmp.l   -4(a3),d3
        bls.s   .mc_have             ; big enough: rewritten in place
        move.l  d0,a0
        bsr     gfx_FreeCprList
        clr.l   v_LOFCprList(a2)
.mc_alloc:
        move.l  ($4).w,a6            ; SysBase
        move.l  d3,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .mc_ret
        move.l  d0,a3
        move.l  d3,(a3)+             ; size of the block, then the list
.mc_have:
        move.l  a3,a4                ; a4 = write pointer
        bsr     gfx_sprmoves         ; at the head: SPR0PT..SPR7PT (rewritten by LoadView/ChangeSprite)
                ifeq    M4C2_NO_MRGCOP
        move.w  gb_MaxDisplayRow(a5),d6
        subq.w  #1,d6                ; d6 = last line a WAIT may name
        link    a6,#-MC_LOC
        move.l  a3,MC_LIST(a6)
        clr.l   MC_LAST(a6)
        clr.l   MC_DSTOP(a6)         ; MC_DSTOP, MC_DSTRT
        clr.w   MC_CON0(a6)
        clr.w   MC_CROSS(a6)
        move.w  d4,MC_NREC(a6)
        moveq   #0,d0
        move.w  d4,d0
        lsl.l   #4,d0                ; R_SIZE per stream
        sub.l   d0,sp
        move.l  sp,MC_RECS(a6)
        move.l  sp,a1                ; records in chain order: fragment, VSprites, UCopList
        move.l  v_ViewPort(a2),a0
.mc_fill:
        move.l  a0,d0
        beq.s   .mc_loop
        move.w  vp_Modes(a0),d0
        and.w   #VP_HIDE,d0
        bne.s   .mc_fn
        move.l  vp_DspIns(a0),d0
        beq.s   .mc_f2
        move.l  d0,R_CL(a1)
        addq.l  #4,d0
        bsr     .mc_rec
.mc_f2:
        move.l  vp_SprIns(a0),d0
        beq.s   .mc_f3
        clr.l   R_CL(a1)
        add.l   #GFX_SPRI_HDR,d0
        bsr     .mc_rec
.mc_f3:
        move.l  vp_UCopIns(a0),d0
        beq.s   .mc_fn
        move.l  d0,a3
        move.l  ucl_FirstCopList(a3),d0
        beq.s   .mc_fn
        move.l  d0,a3
        move.l  a3,R_CL(a1)
        move.l  cl_CopIns(a3),R_PTR(a1)
        move.l  a0,R_VP(a1)
        move.w  #1,R_KIND(a1)
        move.w  cl_Count(a3),R_LEFT(a1)
        lea     R_SIZE(a1),a1
.mc_fn:
        move.l  vp_Next(a0),a0
        bra.s   .mc_fill
.mc_loop:                            ; 1. each stream's MOVEs up to its next WAIT
        move.l  MC_RECS(a6),a3
        move.w  MC_NREC(a6),d5
        bra.s   .mc_m_nx
.mc_m:
        move.l  R_PTR(a3),d0
        beq.s   .mc_m_adv
        move.l  d0,a0
        tst.w   R_KIND(a3)
        bne.s   .mc_mu
.mc_ms:
        cmp.w   #GFX_PSEUDO,(a0)
        beq.s   .mc_mse
        move.w  (a0)+,d0
        move.w  (a0)+,d1
        bsr     .mc_move
        bra.s   .mc_ms
.mc_mse:
        cmp.w   #GFX_PEND,2(a0)
        bne.s   .mc_mst
.mc_mend:
        sub.l   a0,a0                ; end of the stream
.mc_mst:
        move.l  a0,R_PTR(a3)
.mc_m_adv:
        lea     R_SIZE(a3),a3
.mc_m_nx:
        dbra    d5,.mc_m
        bra.s   .mc_pick
.mc_mu:
        tst.w   R_LEFT(a3)
        bne.s   .mc_mu1
        move.l  R_CL(a3),a1          ; this CopList is over: the next one of the chain
        move.l  cl_Next(a1),d0
        beq.s   .mc_mend
        move.l  d0,a1
        move.l  a1,R_CL(a3)
        move.l  cl_CopIns(a1),a0
        move.w  cl_Count(a1),R_LEFT(a3)
        bra.s   .mc_mu
.mc_mu1:
        tst.w   ci_OpCode(a0)
        bne.s   .mc_muw
        move.w  ci_Word1(a0),d0
        and.w   #$1FE,d0
        move.w  ci_Word2(a0),d1
        bsr     .mc_move
        addq.l  #CI_SIZEOF,a0
        subq.w  #1,R_LEFT(a3)
        bra.s   .mc_mu
.mc_muw:
        cmp.w   #10000,ci_Word1(a0)
        bge.s   .mc_mend             ; CEND
        bra.s   .mc_mst
.mc_pick:                            ; 2. the WAIT with the smallest key, last record first
        move.w  MC_NREC(a6),d5
        moveq   #0,d0
        move.w  d5,d0
        lsl.l   #4,d0
        move.l  MC_RECS(a6),a3
        add.l   d0,a3
        moveq   #0,d7                ; d7 = chosen record
        bra.s   .mc_p_nx
.mc_p:
        lea     -R_SIZE(a3),a3
        move.l  R_PTR(a3),d0
        beq.s   .mc_p_nx
        move.l  d0,a0
        bsr     .mc_wpos
        ext.l   d0
        asl.l   #8,d0
        asl.l   #2,d0
        and.l   #$FFFF,d1
        add.l   d1,d0                ; key
        tst.l   d7
        beq.s   .mc_take
        cmp.l   d4,d0
        bge.s   .mc_p_nx
.mc_take:
        move.l  a3,d7
        move.l  d0,d4                ; d4 = smallest key
.mc_p_nx:
        dbra    d5,.mc_p
        tst.l   d7
        beq     .mc_done
        move.l  d7,a3                ; 3. its WAIT
        move.l  R_PTR(a3),a0
        bsr     .mc_wpos
        add.w   v_DyOffset(a2),d0    ; absolute line
        bpl.s   .mc_lo
        moveq   #0,d0
.mc_lo:
        cmp.w   d6,d0
        ble.s   .mc_hi
        move.w  d6,d0
.mc_hi:
        and.w   #$FE,d1
        or.w    #1,d1
        cmp.w   #255,d0
        ble.s   .mc_w
        sub.w   #256,d0              ; past line 255, lines are named modulo 256
        tst.w   MC_CROSS(a6)
        bne.s   .mc_w
        st      MC_CROSS(a6)
        move.w  #$DE,d2              ; the first time: wait for the end of line 255
        move.w  MC_CON0(a6),d3
        and.w   #$F000,d3
        cmp.w   #$C000,d3
        bne.s   .mc_hx
        cmp.w   #$D4,MC_DSTOP(a6)
        bne.s   .mc_hx
        move.w  MC_DSTRT(a6),d2      ; HIRES 4 planes up to $D4: no copper cycle at $DE
.mc_hx:
        and.w   #$FE,d2
        or.w    #$FF01,d2
        swap    d2
        move.w  #$FFFE,d2
        move.l  d2,(a4)+
        move.l  d2,MC_LAST(a6)
.mc_w:
        lsl.w   #8,d0
        or.w    d1,d0
        swap    d0
        move.w  #$FFFE,d0
        cmp.l   MC_LAST(a6),d0
        beq.s   .mc_same             ; the same WAIT again: dropped
        move.l  d0,(a4)+
        move.l  d0,MC_LAST(a6)
.mc_same:
        tst.w   R_KIND(a3)
        bne.s   .mc_au
        lea     12(a0),a0            ; past the 3 entries of the pseudo-WAIT
        move.l  a0,R_PTR(a3)
        move.l  R_CL(a3),d0
        beq     .mc_loop
        clr.l   R_CL(a3)
        move.l  d0,a1
        move.l  a4,(a1)              ; fragment header: where its first MOVEs land
        bra     .mc_loop
.mc_au:
        addq.l  #CI_SIZEOF,a0
        move.l  a0,R_PTR(a3)
        subq.w  #1,R_LEFT(a3)
        bra     .mc_loop
; .mc_rec(a0 = vp, a1 = record, d0 = first entry of a fragment-format stream; R_CL set): fills it, a1 to the next.
.mc_rec:
        move.l  d0,R_PTR(a1)
        move.l  a0,R_VP(a1)
        clr.l   R_KIND(a1)           ; R_KIND, R_LEFT
        lea     R_SIZE(a1),a1
        rts
; .mc_wpos(a0 = current WAIT, a3 = record) -> d0.w = vp.DyOffset + line [/2 for a LACE vp], d1.w = h. Clobbers a1.
.mc_wpos:
        tst.w   R_KIND(a3)
        bne.s   .wp_u
        move.w  2(a0),d0
        move.w  4(a0),d1
        bra.s   .wp_c
.wp_u:
        move.w  ci_Word1(a0),d0
        move.w  ci_Word2(a0),d1
.wp_c:
        move.l  R_VP(a3),a1
        add.w   vp_DyOffset(a1),d0
        btst    #2,vp_Modes+1(a1)
        beq.s   .wp_r
        asr.w   #1,d0                ; interlaced lines -> lines
.wp_r:
        rts
; .mc_move(d0.w = register offset, d1.w = value): emits the MOVE, noting BPLCON0/DDFSTRT/DDFSTOP for line 255.
.mc_move:
        move.w  d0,(a4)+
        move.w  d1,(a4)+
        cmp.w   #BPLCON0-CUSTOM,d0
        bne.s   .mv_ds
        move.w  d1,MC_CON0(a6)
        rts
.mv_ds:
        cmp.w   #DDFSTRT-CUSTOM,d0
        bne.s   .mv_de
        move.w  d1,MC_DSTRT(a6)
        rts
.mv_de:
        cmp.w   #DDFSTOP-CUSTOM,d0
        bne.s   .mv_r
        move.w  d1,MC_DSTOP(a6)
.mv_r:
        rts
.mc_done:
        move.l  MC_LIST(a6),a3
        unlk    a6
                endc
        btst    #2,v_Modes+1(a2)
        beq.s   .mc_fin
        move.l  a4,d7                ; d7 = COP2LCH MOVE, filled once both lists exist
        move.l  #(COP2LC-CUSTOM)<<16,(a4)+
        move.l  #(COP2LC+2-CUSTOM)<<16,(a4)+
.mc_fin:
        move.l  #$FFFFFFFE,(a4)+     ; WAIT $FFFF,$FFFE = end of list
        move.l  a3,v_LOFCprList(a2)  ; publishes the master
        btst    #2,v_Modes+1(a2)
        beq.s   .mc_ret
        bsr     gfx_mkshf
.mc_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; gfx_mkshf(a2 = View, a3 = its new long-frame list, a4 = end of it, d7 = its COP2LCH MOVE, a5 = GfxBase): the
; short-frame list as a copy of the long one (reused if big enough, as MrgCop does with the long one), plane
; pointers of LACE ViewPorts + BytesPerRow, COP2LC of each list = the other. No memory: the View stays without
; one and is shown on long frames only. Clobbers d0-d6/a0/a1/a6.
gfx_mkshf:
        move.l  -4(a3),d3            ; same block size
        move.l  v_SHFCprList(a2),d0
        beq.s   .ms_alloc
        move.l  d0,a0
        cmp.l   -4(a0),d3
        bls.s   .ms_have
        bsr     gfx_FreeCprList
        clr.l   v_SHFCprList(a2)
.ms_alloc:
        move.l  ($4).w,a6
        move.l  d3,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .ms_ret
        move.l  d0,a0
        move.l  d3,(a0)+
        move.l  a0,d0
.ms_have:
        move.l  d0,a0                ; a0 = short-frame list
        move.l  a3,a1
.ms_cp:
        move.l  (a1)+,(a0)+
        cmpa.l  a4,a1
        blo.s   .ms_cp
        move.l  d0,d6                ; d6 = short-frame list
        sub.l   a3,d7
        move.l  d7,a1
        add.l   a3,a1                ; long frame: COP2LC = short-frame list
        move.w  d6,6(a1)
        swap    d6
        move.w  d6,2(a1)
        swap    d6
        add.l   d6,d7
        move.l  d7,a1                ; short frame: COP2LC = long-frame list
        move.l  a3,d0
        move.w  d0,6(a1)
        swap    d0
        move.w  d0,2(a1)
        move.l  v_ViewPort(a2),a1
.ms_vp:
        cmpa.w  #0,a1
        beq.s   .ms_pub
        btst    #2,vp_Modes+1(a1)
        beq.s   .ms_nvp
        move.l  vp_DspIns(a1),d0
        beq.s   .ms_nvp
        move.l  d0,a0
        move.l  (a0),d0              ; where the fragment landed in the long-frame list (0: not merged)
        beq.s   .ms_nvp
        sub.l   a3,d0
        add.l   d6,d0
        move.l  d0,a0
        lea     9*4(a0),a0           ; past the 9 settings MOVEs: BPLxPTH/L pairs
        move.l  a1,-(sp)
        bsr     gfx_shfplanes
        move.l  (sp)+,a1
.ms_nvp:
        move.l  vp_Next(a1),a1
        bra.s   .ms_vp
.ms_pub:
        move.l  d6,v_SHFCprList(a2)
.ms_ret:
        rts

; gfx_sprmoves(a4 = write pointer, a5 = GfxBase): 8 pairs of SPRxPTH/SPRxPTL MOVEs (gb_SprData[x], else the empty
; sprite); a4 advances by GFX_SPRCOP_SIZE. Clobbers d0-d2/a0.
gfx_sprmoves:
        lea     gb_SprData(a5),a0
        move.w  #SPR0PTH-CUSTOM,d1
        moveq   #7,d2
.sm_lp:
        move.l  (a0)+,d0
        bne.s   .sm_have
        move.l  gb_SprNull(a5),d0
.sm_have:
        move.w  d1,(a4)+             ; SPRxPTH
        swap    d0
        move.w  d0,(a4)+
        addq.w  #2,d1
        move.w  d1,(a4)+             ; SPRxPTL
        swap    d0
        move.w  d0,(a4)+
        addq.w  #2,d1
        dbra    d2,.sm_lp
        rts

; gfx_LoadView(view a1): a1 != 0 -> rewrites the sprite pointers of v_LOFCprList, installs it (COP2LC, behind the
; COP1LC copinit) + enables Copper/bitplane/sprite DMA + sets gb_ActiView. A running copper is not restarted: the new
; list takes over at the next frame, as on 1.3 (graphics-display-v34 §7.1); a mid-frame COPJMP1 would run the new
; list's past WAITs at once and show one garbled frame (issues #22/#25). a1 == 0 (NULL view), as on 1.3
; (graphics-display-v34 §7.1, custom-chips-v34 §2): the DMA stays on, the copinit now jumps to an empty list
; (no system list overwrites the caller's hardware set-up any more) and the CPU resets the display registers to
; the system defaults. A program that only loads COP1LC afterwards finds the copper running.
gfx_LoadView:
        GTRACE  0
        move.l  a1,gb_ActiView(a6)   ; GfxBase.ActiView = view (0 if NULL)
        move.l  a1,d0
        beq.s   .lv_null             ; NULL view -> stop the system display
        move.l  v_LOFCprList(a1),d0
        beq.s   .lv_ret              ; no copper list -> nothing
        move.w  v_Modes(a1),gb_Modes(a6)
        move.l  d0,gb_LOFlist(a6)
        clr.l   gb_SHFlist(a6)
        movem.l d2/a4/a5,-(sp)       ; current sprite pointers (a list built earlier is up to date);
        move.l  d0,a4                ; d2 preserved (gfx_sprmoves overwrites it, library contract)
        move.l  a6,a5
        bsr     gfx_sprmoves
        btst    #2,v_Modes+1(a1)
        beq.s   .lv_lof
        move.l  v_SHFCprList(a1),d0
        beq.s   .lv_lof
        move.l  d0,gb_SHFlist(a6)
        move.l  d0,a4
        bsr     gfx_sprmoves
.lv_lof:
        movem.l (sp)+,d2/a4/a5
        move.l  gb_LOFlist(a6),d0
        addq.l  #2,d0
        move.l  d0,gb_SprCop(a6)     ; value word of SPR0PTH
        subq.l  #2,d0
        move.l  d0,COP2LC            ; COP2LC = master, executed via the copinit (COP1LC)
        move.l  gb_copinit(a6),d0
        bne.s   .lv_ci
        move.l  gb_LOFlist(a6),d0    ; no copinit (memory): master directly
.lv_ci:
        move.l  d0,COP1LC
        move.w  CUSTOM+$002,d1       ; DMACONR
        move.w  #GFX_DMA_ON,DMACON   ; master DMA + Copper + bitplane
        and.w   #DMAF_MASTER|DMAF_COPPER,d1
        cmp.w   #DMAF_MASTER|DMAF_COPPER,d1
        beq.s   .lv_ret              ; copper running: it takes COP1LC at the next frame (no mid-frame restart)
        move.w  #0,COPJMP1           ; copper was off: start it on the new list now
.lv_ret:
        rts
.lv_null:
        clr.l   gb_SprCop(a6)
        clr.w   gb_Modes(a6)
        clr.l   gb_SHFlist(a6)
        move.l  gb_copinit(a6),d0
        beq.s   .lv_nregs
        addq.l  #GFX_COPINIT_END,d0  ; the copinit's own end-of-list WAIT = an empty list
        move.l  d0,gb_LOFlist(a6)
        move.l  d0,COP2LC            ; at once, not only at the next VBlank
.lv_nregs:
        move.w  gb_system_bplcon0(a6),d0
        or.w    #$1200,d0            ; 1 plane + COLOR
        move.w  d0,BPLCON0
        move.w  #0,BPLCON1
        move.w  #GFX_BPLCON2,BPLCON2
        move.w  #0,BPL1MOD
        move.w  #0,BPL2MOD
        move.w  #$2C81,DIWSTRT       ; standard 320x256 window and fetch
        move.w  #$F4C1,DIWSTOP
        move.w  #$0038,DDFSTRT
        move.w  #$00D0,DDFSTOP
        bra     gfx_longframe

; gfx_longframe: forces a long frame, as 1.3's init and LoadView(NULL) do (graphics-display-v34 §7.2): out of power-on
; LOF may stay 0 for good (non-interlaced Agnus never toggles it), and programs wait for line 312, which only a long
; PAL frame has (Andromeda "D.O.S."). VPOSW also rewrites line bit 8, so it is written back as read, outside lines
; $xFF where that bit is about to change. The wait is bounded in case the beam does not move. Clobbers d0.
gfx_longframe:
        move.w  #2000,d0
.lf_wait:
        cmp.b   #$FF,VHPOSR
        dbne    d0,.lf_wait
        move.w  VPOSR,d0
        or.w    #$8000,d0
        move.w  d0,VPOSW
        rts

; gfx_WaitBlit(): waits until the blitter is idle (poll DMACONR, bit 14 = BBUSY). Double read (A1000 quirk).
gfx_WaitBlit:
        btst    #6,CUSTOM+$002       ; DMACONR high byte, bit 6 = bit 14 (BBUSY) — dummy read (quirk)
.wb_loop:
        btst    #6,CUSTOM+$002
        bne.s   .wb_loop
        rts

; QBlit(bltnode a1) / QBSBlit(bltnode a1) (spec graphics-blitter-v34 §9): the node's function is called right
; away, in the caller's context (A0 = $DFF000, A1 = node, A6 = GfxBase), and called again with the blitter idle as
; long as it returns Z = 0; then, blitter idle, cleanup if stat & CLEANUP. Deviation: a blit in progress is awaited
; instead of being relayed by the BLIT interrupt.
BN_FUNCTION     EQU 4
BN_STAT         EQU 8
BN_CLEANUP      EQU $E
BNB_CLEANUP     EQU 6
; QBSBlit waits, in the caller, for the beam to reach the node's beamsync line while gb_VBlank says that DrawGList
; ran in this frame; a new frame (gb_VBlank cleared by the VBlank server) ends the wait, as 1.3's synchronised queue
; is then run without waiting. Without GELs it is QBlit (spec §9.4). Line 0 counts as MaxDisplayRow + 1.
BN_BEAMSYNC     EQU $C
gfx_QBSBlit:
        tst.b   gb_VBlank(a6)
        beq.s   gfx_QBlit
        bsr     gfx_VBeamPos
        tst.w   d0
        bne.s   .qs_line
        move.w  gb_MaxDisplayRow(a6),d0
        addq.w  #1,d0
.qs_line:
        cmp.w   BN_BEAMSYNC(a1),d0
        blo.s   gfx_QBSBlit
gfx_QBlit:
        movem.l a2/a5-a6,-(sp)
        move.l  a1,a2                ; a2 = node
        clr.l   (a2)                 ; n = NULL
.qb_call:
        bsr.s   gfx_WaitBlit
        lea     CUSTOM,a0
        move.l  a2,a1
        move.l  BN_FUNCTION(a2),a5
        jsr     (a5)                 ; Z = 1: node finished
        movem.l 4(sp),a5-a6          ; (movem does not touch the condition codes)
        bne.s   .qb_call
        bsr.s   gfx_WaitBlit
        btst    #BNB_CLEANUP,BN_STAT(a2)
        beq.s   .qb_ret
        lea     CUSTOM,a0
        move.l  a2,a1
        move.l  BN_CLEANUP(a2),a5
        jsr     (a5)
.qb_ret:
        movem.l (sp)+,a2/a5-a6
        rts

; gfx_OwnBlitter(): takes the blitter (gb_BlitSem semaphore: waits until no other task owns it), then waits
; for it to be idle. ScrollRaster only uses the blitter when nobody holds it (AttemptSemaphore). The public
; BlitLock counts the requesters - 1 as on 1.3 (0 while one task holds it).
gfx_OwnBlitter:
        addq.w  #1,gb_BlitLock(a6)
        move.l  a6,-(sp)
        lea     gb_BlitSem(a6),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  (sp)+,a6
        bra     gfx_WaitBlit

; gfx_DisownBlitter(): releases the blitter. No effect if the current task does not own it.
gfx_DisownBlitter:
        move.l  a6,-(sp)
        lea     gb_BlitSem(a6),a0
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),d0
        cmp.l   GB_SS_OWNER(a0),d0
        bne.s   .db_ret
        move.l  (sp),a1
        subq.w  #1,gb_BlitLock(a1)
        addq.b  #1,EB_TDNEST(a6)     ; ReleaseSemaphore inline when held once and nobody waits
        cmp.w   #1,GB_SS_NESTCOUNT(a0)
        bne.s   .db_slow
        tst.w   GB_SS_QUEUECOUNT(a0)
        bne.s   .db_slow
        clr.w   GB_SS_NESTCOUNT(a0)
        move.w  #-1,GB_SS_QUEUECOUNT(a0)
        clr.l   GB_SS_OWNER(a0)
        bra.s   .db_rel
.db_slow:
        jsr     LVO_RELEASESEMAPHORE(a6)
.db_rel:
        jsr     LVO_PERMIT(a6)
.db_ret:
        move.l  (sp)+,a6
        rts
; GetSprite(sprite a0, pick d0) -> d0 = hardware sprite reserved in GfxBase SpriteReserved | -1 (custom-chips §4.1):
; pick -1 = the first free one (intuition takes 0 for the pointer), otherwise pick & 7 if free. Its number goes to
; SimpleSprite.num.
gfx_GetSprite:
        moveq   #0,d1
        move.b  gb_SpriteReserved(a6),d1
        tst.w   d0
        bpl.s   .gs_one
        moveq   #0,d0
.gs_find:
        btst    d0,d1
        beq.s   .gs_take
        addq.w  #1,d0
        cmp.w   #8,d0
        blo.s   .gs_find
        bra.s   .gs_fail
.gs_one:
        and.w   #7,d0
        btst    d0,d1
        bne.s   .gs_fail
.gs_take:
        bset    d0,gb_SpriteReserved(a6)
        move.w  d0,ss_num(a0)
        ext.l   d0
        rts
.gs_fail:
        moveq   #-1,d0
        rts

; FreeSprite(pick d0): the sprite becomes free again for GetSprite.
gfx_FreeSprite:
        and.w   #7,d0
        bclr    d0,gb_SpriteReserved(a6)
        rts

; VBeamPos() -> d0 = current video beam line (0..312 in PAL).
gfx_VBeamPos:
        move.l  CUSTOM+$004,d0       ; VPOSR (bit 0 = line 8) then VHPOSR (line 0-7 in the high byte)
        lsr.l   #8,d0
        and.l   #$1FF,d0
        rts
; WaitTOF(): sleeps until the next VBlank (graphics-display-v34 §7.4): a node naming the task joins TOF_WaitQ under
; Disable, the VBlank server signals it (SIGF_SINGLE). Before multitasking (our strap runs the bootblock before the
; scheduler starts) nothing could wake a Wait: the beam is watched until it goes back to the top.
gfx_WaitTOF:
        tst.b   SCHED_ON
        beq.s   .wt_beam
        move.l  ($4).w,a0
        tst.l   EB_THISTASK(a0)
        beq.s   .wt_beam
        movem.l a2/a6,-(sp)
        lea     -WT_NODE(sp),sp      ; the node lives on the caller's stack
        move.l  a6,a2
        move.l  ($4).w,a6
        sub.l   a1,a1
        jsr     LVO_FINDTASK(a6)
        move.l  d0,LN_NAME(sp)
        jsr     LVO_DISABLE(a6)
        moveq   #0,d0
        moveq   #SIGF_SINGLE,d1
        jsr     LVO_SETSIGNAL(a6)
        lea     gb_TOFWaitQ(a2),a0
        move.l  sp,a1
        jsr     LVO_ADDTAIL(a6)
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_WAIT(a6)
        move.l  sp,a1
        jsr     LVO_REMOVE(a6)
        jsr     LVO_ENABLE(a6)
        lea     WT_NODE(sp),sp
        movem.l (sp)+,a2/a6
        rts
.wt_beam:
        move.l  d2,-(sp)
        bsr     gfx_VBeamPos
.wb_lp:
        move.l  d0,d2
        bsr     gfx_VBeamPos
        cmp.l   d2,d0
        bhs.s   .wb_lp
        move.l  (sp)+,d2
        rts

; SetRGB4CM(colormap a0, n d0, r d1, g d2, b d3): colour n of the ColorMap only (the display is not touched).
; Index outside the ColorMap: nothing.
gfx_SetRGB4CM:
        cmpa.w  #0,a0
        beq.s   .sc_ret
        cmp.w   cm_Count(a0),d0
        bhs.s   .sc_ret
        move.l  d4,-(sp)
        and.w   #$F,d1
        lsl.w   #8,d1
        move.w  d2,d4
        and.w   #$F,d4
        lsl.w   #4,d4
        or.w    d4,d1
        move.w  d3,d4
        and.w   #$F,d4
        or.w    d4,d1
        move.l  cm_ColorTable(a0),a0
        add.w   d0,d0
        move.w  d1,0(a0,d0.w)
        move.l  (sp)+,d4
.sc_ret:
        rts

; GetRGB4(colormap a0, n d0) -> d0 = colour n ($0RGB), -1 if the ColorMap or the index are not suitable.
gfx_GetRGB4:
        cmpa.w  #0,a0
        beq.s   .gr_bad
        cmp.w   cm_Count(a0),d0
        bhs.s   .gr_bad
        move.l  cm_ColorTable(a0),a0
        add.w   d0,d0
        moveq   #0,d1
        move.w  0(a0,d0.w),d1
        move.l  d1,d0
        rts
.gr_bad:
        moveq   #-1,d0
        rts

; InitView(view a1): all 18 bytes cleared, then the standard display origin (spec graphics-display §1.1).
gfx_InitView:
        move.l  a1,a0
        moveq   #v_SIZEOF/2-1,d0
.iv_clr:
        clr.w   (a0)+
        dbra    d0,.iv_clr
        move.w  #$2C,v_DyOffset(a1)
        move.w  #$81,v_DxOffset(a1)
        rts

; InitVPort(vp a0): all 40 bytes cleared, SpritePriorities := $24 (spec §1.2).
gfx_InitVPort:
        move.l  a0,a1
        moveq   #vp_SIZEOF/2-1,d0
.ip_clr:
        clr.w   (a1)+
        dbra    d0,.ip_clr
        move.b  #$24,vp_SpritePri(a0)
        rts

; GetColorMap(entries d0) -> d0 = ColorMap | 0. The table starts with the default colours (spec §3); for more than
; 32 entries the rest is cleared (1.3 copies past its table).
gfx_GetColorMap:
        movem.l d2/a2/a6,-(sp)
        move.l  ($4).w,a6
        move.w  d0,d2
        moveq   #GCM_SIZEOF,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .gc_ret
        move.l  d0,a2
        clr.w   (a2)                 ; Flags, Type
        move.w  d2,cm_Count(a2)
        moveq   #0,d0
        move.w  d2,d0
        add.l   d0,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,cm_ColorTable(a2)
        bne.s   .gc_fill
        move.l  a2,a1
        moveq   #GCM_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        bra.s   .gc_ret
.gc_fill:
        move.l  d0,a1
        lea     gfx_defcolors(pc),a0
        cmp.w   #32,d2
        bls.s   .gc_n
        moveq   #32,d2
.gc_n:
        subq.w  #1,d2
        bmi.s   .gc_done
.gc_cp:
        move.w  (a0)+,(a1)+
        dbra    d2,.gc_cp
.gc_done:
        move.l  a2,d0
.gc_ret:
        movem.l (sp)+,d2/a2/a6
        rts

; FreeColorMap(colormap a0): frees the table then the structure.
gfx_FreeColorMap:
        movem.l a2/a6,-(sp)
        move.l  ($4).w,a6
        move.l  a0,a2
        move.l  cm_ColorTable(a2),a1
        moveq   #0,d0
        move.w  cm_Count(a2),d0
        add.l   d0,d0
        beq.s   .fm_hdr
        jsr     LVO_FREEMEM(a6)
.fm_hdr:
        move.l  a2,a1
        moveq   #GCM_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,a2/a6
        rts

; FreeCprList(cprlist a0): our View copper list (what MrgCop stores in v_LOFCprList) is one chip block whose size
; sits in the long before it; freed whole. NULL: nothing. Nothing in the View is reset (as on 1.3).
gfx_FreeCprList:
        move.l  a0,d0
        beq.s   .fp_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        lea     -4(a0),a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.fp_ret:
        rts

; WaitBOVP(vp a0): busy wait until the beam reaches the line after the ViewPort's last one
; (View.DyOffset + vp.DyOffset + DHeight, at most MaxDisplayRow - 1). Interlace: DHeight is not halved (spec §7.4).
gfx_WaitBOVP:
        move.l  d2,-(sp)
        move.w  vp_DyOffset(a0),d2
        add.w   vp_DHeight(a0),d2
        move.l  gb_ActiView(a6),d0
        beq.s   .wb_cap
        move.l  d0,a1
        add.w   v_DyOffset(a1),d2
.wb_cap:
        move.w  gb_MaxDisplayRow(a6),d0
        subq.w  #1,d0
        cmp.w   d0,d2
        ble.s   .wb_lp
        move.w  d0,d2
.wb_lp:
        bsr     gfx_VBeamPos
        cmp.w   d2,d0
        blt.s   .wb_lp
        move.l  (sp)+,d2
        rts

; Default colours of a new ColorMap (observable through GetRGB4, spec graphics-display §3).
gfx_defcolors:
        dc.w    $000,$F00,$0F0,$FF0,$00F,$F0F,$0FF,$FFF,$620,$E50,$9F1,$EB0,$55F,$92F,$0F8,$CCC
        dc.w    $000,$111,$222,$333,$444,$555,$666,$777,$888,$999,$AAA,$BBB,$CCC,$DDD,$EEE,$FFF

; BltClear(memory a1, size d0, flags d1): zeroes the area. Flag bit 1: d0 = rows (high word) x bytes per
; row (low word), otherwise a byte count. The CPU does it: waiting for completion (bit 0) is therefore implied.
gfx_BltClear:
        bsr     gfx_WaitBlit
        btst    #1,d1
        beq.s   .bc_n
        move.l  d0,d1
        swap    d1
        mulu    d1,d0                ; rows x bytes (low word of d0)
.bc_n:
        move.l  a1,d1
        btst    #0,d1
        beq.s   .bc_al
        tst.l   d0
        beq.s   .bc_ret
        clr.b   (a1)+
        subq.l  #1,d0
.bc_al:
        move.l  d0,d1
        lsr.l   #2,d1
        bra.s   .bc_le
.bc_l:
        clr.l   (a1)+
.bc_le:
        subq.l  #1,d1
        bpl.s   .bc_l
        btst    #1,d0
        beq.s   .bc_b
        clr.w   (a1)+
.bc_b:
        btst    #0,d0
        beq.s   .bc_ret
        clr.b   (a1)+
.bc_ret:
        rts

; PolyDraw(rp a1, count d0 (unsigned word), points a0): Draw through its vector (SetFunction honoured) to each of the
; points (pairs of words x, y) from the current position (spec graphics-line-v34 §9.1).
gfx_PolyDraw:
        movem.l d2/a1-a2,-(sp)
        move.l  a0,a2
        moveq   #0,d2
        move.w  d0,d2
        bra.s   .pd_e
.pd_l:
        movem.w (a2)+,d0-d1
        move.l  4(sp),a1
        jsr     LVO_DRAW(a6)
.pd_e:
        subq.l  #1,d2
        bpl.s   .pd_l
        movem.l (sp)+,d2/a1-a2
        rts

; ChangeSprite(vp a0, sprite a1, data a2): new image (POS, CTL, 2 words per line, 0, 0), then MoveSprite with the
; sprite's current position (custom-chips §4.1).
gfx_ChangeSprite:
        move.l  a2,ss_posctldata(a1)
        move.w  ss_x(a1),d0
        move.w  ss_y(a1),d1
;       (continued in gfx_MoveSprite)

; MoveSprite(vp a0, sprite a1, x d0, y d1) (custom-chips §4.1): the sprite goes into GfxBase->SimpleSprites, takes
; x/y, and its POS/CTL words are written into its data: with a ViewPort x is halved for HIRES and y for LACE, and the
; ViewPort's DyOffset added; then the active View's DxOffset/DyOffset; VSTART at least 21, VSTOP = VSTART + height,
; CTL bits 3-7 (ATTACH) kept. The copper lists' SPRxPT of that sprite then point at the data, or at the empty
; sprite when the ViewPort is hidden or y is past its DHeight. The even half of an attached pair (ATTACH in the odd
; sprite's CTL) moves its partner too. No register is written: sprite DMA takes the change at the next frame.
gfx_MoveSprite:
        movem.l d2-d6/a2-a3,-(sp)
        move.l  a0,a2                ; a2 = ViewPort | 0
        move.l  a1,a3                ; a3 = SimpleSprite
        move.w  d0,d5                ; d5/d6 = x, y as given
        move.w  d1,d6
.ms_one:
        move.w  d5,ss_x(a3)
        move.w  d6,ss_y(a3)
        move.w  ss_num(a3),d2
        and.w   #7,d2                ; d2 = hardware sprite
        move.w  d2,d0
        lsl.w   #2,d0
        lea     gb_SprSS(a6),a1
        move.l  a3,0(a1,d0.w)
        move.w  d5,d3                ; d3 = HSTART
        move.w  d6,d4                ; d4 = VSTART
        cmpa.w  #0,a2
        beq.s   .ms_view
        tst.w   vp_Modes(a2)
        bpl.s   .ms_lx
        asr.w   #1,d3
.ms_lx:
        btst    #2,vp_Modes+1(a2)
        beq.s   .ms_ly
        asr.w   #1,d4
.ms_ly:
        add.w   vp_DyOffset(a2),d4
.ms_view:
        move.l  gb_ActiView(a6),d0
        beq.s   .ms_min
        move.l  d0,a1
        add.w   v_DxOffset(a1),d3
        add.w   v_DyOffset(a1),d4
.ms_min:
        cmp.w   #21,d4
        bge.s   .ms_pos
        moveq   #21,d4
.ms_pos:
        move.l  ss_posctldata(a3),d0
        beq     .ms_next             ; no image yet
        move.l  d0,a1
        move.w  d4,d0                ; POS = VSTART[7:0] << 8 | HSTART[8:1]
        lsl.w   #8,d0
        move.w  d3,d1
        lsr.w   #1,d1
        move.b  d1,d0
        move.w  d0,(a1)
        move.w  d4,d1
        add.w   ss_height(a3),d1     ; d1 = VSTOP
        move.w  d1,d0                ; CTL = VSTOP[7:0] << 8 | old bits 3-7 | VSTART8 << 2 | VSTOP8 << 1 | HSTART0
        lsl.w   #8,d0
        move.b  3(a1),d0
        and.b   #$F8,d0
        btst    #8,d4
        beq.s   .ms_v8
        bset    #2,d0
.ms_v8:
        btst    #8,d1
        beq.s   .ms_e8
        bset    #1,d0
.ms_e8:
        btst    #0,d3
        beq.s   .ms_h0
        bset    #0,d0
.ms_h0:
        move.w  d0,2(a1)
        move.l  a1,d0                ; shown, unless its ViewPort hides it
        cmpa.w  #0,a2
        beq.s   .ms_show
        move.w  vp_Modes(a2),d1
        and.w   #VP_HIDE,d1
        bne.s   .ms_hide
        cmp.w   vp_DHeight(a2),d6
        ble.s   .ms_show
.ms_hide:
        moveq   #0,d0
.ms_show:
        bsr.s   gfx_sprptr
.ms_next:
        btst    #0,d2                ; even half of an attached pair: its partner follows
        bne.s   .ms_ret
        addq.w  #1,d2
        lsl.w   #2,d2
        lea     gb_SprSS(a6),a1
        move.l  0(a1,d2.w),d0
        beq.s   .ms_ret
        move.l  d0,a1
        move.l  ss_posctldata(a1),d1
        beq.s   .ms_ret
        exg     d1,a1
        btst    #7,3(a1)             ; ATTACH
        beq.s   .ms_ret
        move.l  d1,a3
        bra     .ms_one
.ms_ret:
        movem.l (sp)+,d2-d6/a2-a3
        rts

; gfx_sprptr(d2.w = hardware sprite, d0 = its data | 0 for the empty sprite, a6 = GfxBase): what the SPRxPT MOVEs of
; the loaded copper lists (long frame, and short frame in interlace) and of the lists MrgCop builds next point at.
; Clobbers d0/d1/a0/a1.
gfx_sprptr:
        move.w  d2,d1
        lsl.w   #2,d1
        lea     gb_SprData(a6),a0
        move.l  d0,0(a0,d1.w)
        bne.s   .sp_data
        move.l  gb_SprNull(a6),d0
.sp_data:
        move.l  d0,-(sp)
        move.l  gb_SprCop(a6),d0
        beq.s   .sp_done
        move.w  d2,d1
        lsl.w   #3,d1                ; 8 bytes per sprite (2 MOVEs)
        add.w   d1,d0
        move.l  d0,a0
        move.w  (sp),(a0)            ; SPRxPTH
        move.w  2(sp),4(a0)          ; SPRxPTL
        bsr     gfx_shfpos
        tst.l   d0
        beq.s   .sp_done
        move.l  d0,a0
        move.w  (sp),(a0)
        move.w  2(sp),4(a0)
.sp_done:
        addq.l  #4,sp
        rts

graphics_end:
