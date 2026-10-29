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
                xdef    gfx_OwnBlitter       ; draw.s (ScrollRaster with the blitter)
                xdef    gfx_DisownBlitter
                xref    gfx_BltTemplate
                xref    gfx_InitArea
                xref    gfx_InitTmpRas
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
        dc.l    graphics_null            ; 34: LVO -204 (not implemented)
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
        dc.l    gfx_QBlit                ; 49: LVO -294 QBSBlit(bltnode a1): like QBlit (spec §9.4, gb_VBlank = 0)
        dc.l    gfx_BltClear             ; 50: LVO -300 BltClear(memory a1, size d0, flags d1)
        dc.l    gfx_RectFill             ; 51: LVO -306
        dc.l    graphics_null            ; 52: LVO -312 (not implemented)
        dc.l    gfx_ReadPixel            ; 53: LVO -318
        dc.l    gfx_WritePixel           ; 54: LVO -324
        dc.l    gfx_Flood                ; 55: LVO -330 Flood(rp a1, mode d2, x d0, y d1)
        dc.l    gfx_PolyDraw             ; 56: LVO -336 PolyDraw(rp a1, count d0, points a0)
        dc.l    gfx_SetAPen              ; 57: LVO -342
        dc.l    gfx_SetBPen              ; 58: LVO -348
        dc.l    gfx_SetDrMd              ; 59: LVO -354
        dc.l    graphics_null            ; 60: LVO -360 InitView (not impl.)
        dc.l    gfx_CBump                ; 61: LVO -366 CBump(ucl a1)
        dc.l    gfx_CMove                ; 62: LVO -372 CMove(ucl a1, register d0, value d1)
        dc.l    gfx_CWait                ; 63: LVO -378 CWait(ucl a1, v d0, h d1)
        dc.l    gfx_VBeamPos             ; 64: LVO -384 VBeamPos()
        dc.l    gfx_InitBitMap           ; 65: LVO -390
        dc.l    gfx_ScrollRaster         ; 66: LVO -396
        dc.l    graphics_null            ; 67: LVO -402 WaitBOVP (not implemented)
        dc.l    gfx_GetSprite            ; 68: LVO -408
        dc.l    gfx_FreeSprite           ; 69: LVO -414 FreeSprite(number d0)
        dc.l    gfx_ChangeSprite         ; 70: LVO -420
        dc.l    gfx_MoveSprite           ; 71: LVO -426
        dc.l    gfx_LockLayerRom         ; 72: LVO -432
        dc.l    gfx_UnlockLayerRom       ; 73: LVO -438
        dcb.l   2,graphics_null          ; 74..75: LVO -444..-450 (not implemented)
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
        dc.l    graphics_null            ; 91: LVO -546 FreeCopList (not implemented)
        dc.l    gfx_ClipBlit             ; 92: LVO -552 ClipBlit(source rp a0, ..., dest rp a1, ..., minterm d6)
        dc.l    gfx_XorRectRegion        ; 93: LVO -558
        dcb.l   3,graphics_null          ; 94..96: LVO -564..-576 (not implemented)
        dc.l    gfx_GetRGB4              ; 97: LVO -582 GetRGB4(colormap a0, n d0)
        dc.l    graphics_null            ; 98: LVO -588 ScrollVPort (not implemented)
        dc.l    gfx_UCopperListInit      ; 99: LVO -594 UCopperListInit(ucl a0, count d0)
        dc.l    gfx_FreeGBuffers         ; 100: LVO -600
        dc.l    gfx_BltBitMapRastPort    ; 101: LVO -606
        dc.l    gfx_OrRegionRegion       ; 102: LVO -612
        dc.l    gfx_XorRegionRegion      ; 103: LVO -618
        dc.l    gfx_AndRegionRegion      ; 104: LVO -624
        dc.l    gfx_SetRGB4CM            ; 105: LVO -630 SetRGB4CM(colormap a0, n d0, r d1, g d2, b d3)
        dc.l    gfx_BltMaskBitMapRastPort ; 106: LVO -636 BltMaskBitMapRastPort(..., minterm d6, mask a2)
        dcb.l   2,graphics_null          ; 107..108: LVO -642/-648 (private)
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
        move.b  #50,gb_VBlank(a2)    ; PAL display (European A500): public values read by programs
        move.w  #GFX_COLOR_BIT,gb_system_bplcon0(a2)
        move.w  #DISPF_PAL,gb_DisplayFlags(a2)
        move.w  #312,gb_MaxDisplayRow(a2)
        move.w  #452,gb_MaxDisplayColumn(a2)
        move.w  #256,gb_NormalDisplayRows(a2)
        move.w  #640,gb_NormalDisplayColumns(a2)
        move.w  #1280,gb_NormalDPMX(a2)
        move.w  #1280,gb_NormalDPMY(a2)
        move.w  #64*256,gb_MicrosPerLine(a2)
        lea     gb_BlitSem(a2),a0
        jsr     LVO_INITSEMAPHORE(a6)
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_BLITTER),DMACON ; blitter permanently enabled, like 1.3: a
        jsr     gfx_fontinit         ; program that saves then restores DMACON must find it again
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
        bsr.s   gfx_intinit
        moveq   #INTB_VERTB,d0
        jsr     LVO_ADDINTSERVER(a6)
        lea     gb_bltsrv(a2),a1     ; blitter vector: some programs look for GfxBase there (iv_Data)
        lea     gfx_bltint(pc),a0
        bsr.s   gfx_intinit
        moveq   #INTB_BLIT,d0
        jsr     LVO_SETINTVECTOR(a6)
        move.l  a2,d0
        move.l  (sp)+,a2
        rts

; gfx_intinit(interrupt a1, code a0, GfxBase a2): NT_INTERRUPT node named "graphics.library", is_Data = GfxBase.
gfx_intinit:
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        move.l  a0,IS_CODE(a1)
        lea     graphics_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.l  a2,IS_DATA(a1)
        rts

; gfx_bltint(a0 = $DFF000): end of blitter operation; our blits are synchronous (WaitBlit): acknowledge only.
gfx_bltint:
        move.w  #INTF_BLIT,INTREQ-CUSTOM(a0)
        rts

; gfx_vblank(a1 = GfxBase): VBlank server. Reloads COP2LC with the list of the displayed view: a program that writes
; COP2LC with interrupts off sees its list executed by the copinit until it re-enables them (Caesar's FLT
; intro). Returns Z = 1 (the chain continues).
gfx_vblank:
        tst.l   gb_ActiView(a1)
        beq.s   .vb_ret
        move.l  gb_LOFlist(a1),d0
        beq.s   .vb_ret
        move.l  d0,COP2LC
.vb_ret:
        moveq   #0,d0
        rts
GFX_VBPRI       EQU 10

gfx_copinit:
        dc.w    $0C01,$FFFE          ; WAIT line 12
        dc.w    COPJMP2-CUSTOM,0     ; jump to COP2LC
        dc.w    $FFFF,$FFFE
GFX_COPINIT_SIZE EQU 12

; === M4c2: display engine (copper list GENERATED from the structures) ===
; Amiga convention for the 3 functions: a6 = GfxBase, preserve d2-d7/a2-a6, scratch d0/d1/a0/a1.
; AllocMem requires a6 = SysBase -> we save/restore a6 and take SysBase via ($4).w.

; gfx_MakeVPort(view a0, vp a1): generates the ViewPort's copper fragment in vp_DspIns (chip RAM).
; GENERIC (like the real graphics.library): display window according to the mode (HIRES 640 px; low resolution
; 320 px, or overscan 352x272 if DWidth > 320), height = DHeight (standard windows), modulo = BytesPerRow - bytes
; fetched per row; BPLCON0 from BitMap.Depth; ONE BPLxPT pointer per plane (BitMap.Planes[0..depth-1]); cm_Count
; colours COLOR00..COLOR(Count-1) from ColorTable. An existing fragment is reused (cleared then rewritten).
; view unused (only 1 ViewPort). No final WAIT (added by MrgCop).
gfx_MakeVPort:
        movem.l d2/d3/d4/d5/a2/a3/a4/a6,-(sp)
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
        clr.w   (a1)+                ; remainder = inert MOVEs (see GFX_FRAG_WORDS)
        dbra    d1,.mv_clr
        move.l  a3,a1                ; a1 = write pointer
        move.l  vp_RasInfo(a2),a0
        move.l  ri_BitMap(a0),a4     ; a4 = BitMap
        lea     gfx_win_over(pc),a0  ; a0 = DIWSTRT, DDFSTRT, DDFSTOP, bytes fetched per row
        move.w  #GFX_DIWSTOP,d1
        tst.w   vp_Modes(a2)
        bpl.s   .mv_lo
        lea     gfx_win_hires(pc),a0
        bra.s   .mv_std
.mv_lo:
        cmp.w   #320,vp_DWidth(a2)
        bhi.s   .mv_emit             ; > 320 px in low resolution: overscan
        lea     gfx_win_lores(pc),a0
.mv_std:
        move.w  vp_DHeight(a2),d1    ; DIWSTOP: vstop = $2C + DHeight (V8 derived from V7 by the hardware)
        add.w   #$2C,d1
        lsl.w   #8,d1
        move.b  #$C1,d1
.mv_emit:
        move.w  #DIWSTRT-CUSTOM,(a1)+
        move.w  (a0)+,(a1)+
        move.w  #DIWSTOP-CUSTOM,(a1)+
        move.w  d1,(a1)+
        move.w  #DDFSTRT-CUSTOM,(a1)+
        move.w  (a0)+,(a1)+
        move.w  #DDFSTOP-CUSTOM,(a1)+
        move.w  (a0)+,(a1)+
        move.w  bm_BytesPerRow(a4),d5
        sub.w   (a0)+,d5             ; d5 = modulo
        moveq   #0,d4
        move.b  bm_Depth(a4),d4      ; d4 = depth (plane counter)
        move.w  d4,d2
        lsl.w   #8,d2
        lsl.w   #4,d2                ; depth << 12
        or.w    #GFX_COLOR_BIT,d2    ; | COLOR
        tst.w   vp_Modes(a2)
        bpl.s   .mv_lores
        or.w    #GFX_HIRES_BIT,d2    ; | HIRES (vp_Modes bit 15)
.mv_lores:
        move.w  #BPLCON0-CUSTOM,(a1)+
        move.w  d2,(a1)+
        move.w  #BPLCON1-CUSTOM,(a1)+
        move.w  #0,(a1)+
        move.w  #BPLCON2-CUSTOM,(a1)+
        move.w  #GFX_BPLCON2,(a1)+   ; sprites in front of both playfields (pointer visible everywhere)
        move.w  #BPL1MOD-CUSTOM,(a1)+
        move.w  d5,(a1)+
        move.w  #BPL2MOD-CUSTOM,(a1)+
        move.w  d5,(a1)+
        ; bitplane pointers: one BPLxPTH/L per plane (Planes[i])
        lea     bm_Planes(a4),a0     ; a0 = &Planes[0]
        move.w  #BPL1PTH-CUSTOM,d3   ; d3 = offset of the current BPLxPTH register
.mv_plane:
        move.l  (a0)+,d5             ; d5 = address of plane i
        move.w  d3,(a1)+             ; BPLxPTH
        move.l  d5,d2
        swap    d2
        move.w  d2,(a1)+             ; HIGH word
        addq.w  #2,d3                ; -> BPLxPTL
        move.w  d3,(a1)+
        move.w  d5,(a1)+             ; LOW word
        addq.w  #2,d3                ; -> BPL(x+1)PTH
        subq.w  #1,d4
        bne.s   .mv_plane
        ; colours: cm_Count MOVEs COLOR00..COLOR(Count-1)
        move.l  vp_ColorMap(a2),a0
        move.w  cm_Count(a0),d4      ; d4 = number of colours
        move.l  cm_ColorTable(a0),a0 ; a0 = ColorTable
        move.w  #COLOR00-CUSTOM,d3   ; d3 = offset of the current COLORxx register
.mv_color:
        move.w  d3,(a1)+
        move.w  (a0)+,(a1)+          ; COLORxx = ColorTable[xx]
        addq.w  #2,d3
        subq.w  #1,d4
        bne.s   .mv_color
        bsr     gfx_ucopemit         ; user instructions (vp_UCopIns) at the end of the fragment
        move.l  a3,vp_DspIns(a2)     ; publishes the fragment
.mv_ret:
        movem.l (sp)+,d2/d3/d4/d5/a2/a3/a4/a6
        rts

; gfx_ucopemit(a1 = write pointer in the fragment, a2 = ViewPort, a3 = fragment): copies the instructions of
; vp_UCopIns (the user's CMove/CWait) to the end of the fragment, in the remaining space. A WAIT gives line
; v + $2C + DyOffset of the ViewPort (beyond 255, preceded by the passing WAIT $FFDF); v >= 10000 = end of list
; (CEND). Clobbers d0/d1/a0.
gfx_ucopemit:
        movem.l d2-d4/a4,-(sp)
        move.l  vp_UCopIns(a2),d0
        beq.s   .ue_ret
        move.l  d0,a0
        move.l  ucl_FirstCopList(a0),d0
        beq.s   .ue_ret
        move.l  d0,a4
        move.l  cl_CopIns(a4),a0
        move.w  cl_Count(a4),d2      ; d2 = instructions
        lea     GFX_FRAG_SIZE(a3),a4 ; a4 = end of the fragment
        moveq   #0,d4                ; d4 = passing WAIT for line 255 already emitted
.ue_lp:
        subq.w  #1,d2
        bmi.s   .ue_ret
        move.l  a4,d0
        sub.l   a1,d0
        cmp.l   #8,d0                ; room for one instruction (+ a passing WAIT)
        blo.s   .ue_ret
        move.w  ci_Word1(a0),d0
        move.w  ci_Word2(a0),d1
        tst.w   ci_OpCode(a0)
        bne.s   .ue_wait
        and.w   #$1FE,d0             ; register: offset within the custom registers
        move.w  d0,(a1)+
        move.w  d1,(a1)+
        bra.s   .ue_nx
.ue_wait:
        cmp.w   #10000,d0
        bge.s   .ue_ret              ; CEND
        add.w   #$2C,d0
        add.w   vp_DyOffset(a2),d0
        bpl.s   .ue_pos
        moveq   #0,d0
.ue_pos:
        cmp.w   #255,d0
        ble.s   .ue_line
        tst.w   d4
        bne.s   .ue_line
        st      d4
        move.w  #$FFDF,(a1)+         ; waits for the end of line 255
        move.w  #$FFFE,(a1)+
.ue_line:
        lsl.w   #8,d0                ; line (low 8 bits) in VP
        and.w   #$FE,d1              ; even horizontal position
        or.w    d1,d0
        or.w    #1,d0
        move.w  d0,(a1)+
        move.w  #$FFFE,(a1)+
.ue_nx:
        addq.l  #CI_SIZEOF,a0
        bra.s   .ue_lp
.ue_ret:
        movem.l (sp)+,d2-d4/a4
        rts

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

; gfx_SetRGB4(vp a0, n d0, r d1, g d2, b d3): ColorTable[n] = 4-bit RGB, and the already generated MOVE COLORn is
; patched in the ViewPort's fragment and, if it belongs to the displayed view, at its place in the master list.
gfx_SetRGB4:
        cmpa.w  #0,a0
        beq     .sr_ret
        move.l  vp_ColorMap(a0),a1
        cmpa.w  #0,a1
        beq.s   .sr_ret
        and.w   #15,d1
        lsl.w   #4,d1
        and.w   #15,d2
        or.w    d2,d1
        lsl.w   #4,d1
        and.w   #15,d3
        or.w    d3,d1                ; d1 = $0RGB
        cmp.w   cm_Count(a1),d0
        bhs.s   .sr_ret
        move.l  cm_ColorTable(a1),a1
        add.w   d0,d0
        move.w  d1,0(a1,d0.w)
        add.w   #COLOR00-CUSTOM,d0   ; d0 = COLORn register
        move.l  vp_DspIns(a0),d2
        beq.s   .sr_ret
        move.l  d2,a1
        moveq   #GFX_FRAG_WORDS/2-1,d3
.sr_find:
        cmp.w   (a1),d0
        beq.s   .sr_hit
        addq.l  #4,a1
        dbra    d3,.sr_find
        bra.s   .sr_ret
.sr_hit:
        move.w  d1,2(a1)
        sub.l   d2,a1                ; a1 = position of the MOVE in the fragment
        move.l  gb_ActiView(a6),d3
        beq.s   .sr_ret
        move.l  a0,d2                ; d2 = ViewPort
        move.l  d3,a0
        move.l  v_LOFCprList(a0),d3
        beq.s   .sr_ret
        add.l   #GFX_SPRCOP_SIZE,d3  ; master list: sprites, then one fragment per ViewPort (that has one), in
        move.l  v_ViewPort(a0),a0    ; view order
.sr_vp:
        cmpa.w  #0,a0
        beq.s   .sr_ret              ; ViewPort not in the displayed view
        cmp.l   a0,d2
        beq.s   .sr_mst
        tst.l   vp_DspIns(a0)
        beq.s   .sr_vnx
        add.l   #GFX_FRAG_SIZE,d3
.sr_vnx:
        move.l  vp_Next(a0),a0
        bra.s   .sr_vp
.sr_mst:
        add.l   d3,a1
        move.w  d1,2(a1)
.sr_ret:
        rts

; PAL display windows: DIWSTRT, DDFSTRT, DDFSTOP, bytes fetched per row (DIWSTOP: fixed in overscan, otherwise
; computed from DHeight)
gfx_win_over:
        dc.w    GFX_DIWSTRT,GFX_DDFSTRT,GFX_DDFSTOP,GFX_BOOT_BYTES
gfx_win_lores:
        dc.w    $2C81,$0038,$00D0,40
gfx_win_hires:
        dc.w    $2C81,$003C,$00D4,80

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
        move.l  vp_UCopIns(a2),d0    ; user list: its CopLists (instructions included) then the header
        beq.s   .fv_ret
        clr.l   vp_UCopIns(a2)
        move.l  d0,-(sp)
        move.l  d0,a0
        move.l  ucl_FirstCopList(a0),a3
.fv_cl:
        move.l  a3,d0
        beq.s   .fv_hdr
        move.l  cl_CopIns(a3),a1
        move.w  cl_MaxCount(a3),d0
        mulu    #CI_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a3,a1
        move.l  cl_Next(a3),a3
        moveq   #CL_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .fv_cl
.fv_hdr:
        move.l  (sp)+,a1
        moveq   #UCL_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.fv_ret:
        movem.l (sp)+,a2-a3/a6
        rts

; UCopperListInit(ucl a0, count d0) -> d0 = CopList | 0: CopList of "count" instructions, current and first.
gfx_UCopperListInit:
        movem.l d2/a2-a3/a6,-(sp)
        move.l  a0,a2
        move.w  d0,d2
        move.l  ($4).w,a6
        moveq   #CL_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ui_ret
        move.l  d0,a3
        moveq   #0,d0
        move.w  d2,d0
        mulu    #CI_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        bne.s   .ui_ok
        move.l  a3,a1
        moveq   #CL_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        bra.s   .ui_ret
.ui_ok:
        move.l  d0,cl_CopIns(a3)
        move.l  d0,cl_CopPtr(a3)
        move.w  d2,cl_MaxCount(a3)
        move.l  a3,ucl_FirstCopList(a2)
        move.l  a3,ucl_CopList(a2)
        move.l  a3,d0
.ui_ret:
        movem.l (sp)+,d2/a2-a3/a6
        rts

; CMove(ucl a1, register d0, value d1) / CWait(ucl a1, v d0, h d1): write the current instruction; CBump(ucl a1)
; moves to the next one. List full: instruction ignored.
gfx_CMove:
        movem.l d2-d3,-(sp)
        moveq   #0,d2                ; COPPER_MOVE
        bra.s   gfx_cput
gfx_CWait:
        movem.l d2-d3,-(sp)
        moveq   #1,d2                ; COPPER_WAIT
gfx_cput:
        move.l  ucl_CopList(a1),a0
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
        move.l  ucl_CopList(a1),a0
        move.w  cl_Count(a0),d0
        cmp.w   cl_MaxCount(a0),d0
        bhs.s   .cb_ret
        addq.w  #1,cl_Count(a0)
        addq.l  #CI_SIZEOF,cl_CopPtr(a0)
.cb_ret:
        rts

; gfx_MrgCop(view a1): merges the vp_DspIns fragment of each ViewPort into v_LOFCprList (master, chip RAM)
; + final WAIT. An existing list is reused. 1 ViewPort here. Gated by M4C2_NO_MRGCOP (RED): skips the merge ->
; master = WAIT only -> white screen.
gfx_MrgCop:
        movem.l d2/a2/a3/a4/a5/a6,-(sp)
        move.l  a6,a5                ; a5 = GfxBase
        move.l  a1,a2                ; a2 = View
        move.l  v_LOFCprList(a2),d0  ; list already allocated: rewritten in place (fixed size)
        bne.s   .mc_have
        move.l  ($4).w,a6            ; SysBase
        move.l  #GFX_MASTER_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .mc_ret
.mc_have:
        move.l  d0,a3                ; a3 = master
        move.l  a3,a4                ; a4 = write pointer
        bsr     gfx_sprmoves         ; at the head: SPR0PT..SPR7PT (fixed position, rewritten by LoadView/ChangeSprite)
                ifeq    M4C2_NO_MRGCOP
        move.l  v_ViewPort(a2),a0    ; 1st ViewPort
.mc_vp:
        move.l  a0,d2
        beq.s   .mc_end
        move.l  vp_DspIns(a0),a1     ; fragment of this ViewPort
        move.l  a1,d2
        beq.s   .mc_next             ; no fragment
        move.w  #(GFX_FRAG_SIZE/2)-1,d2
.mc_copy:
        move.w  (a1)+,(a4)+
        dbf     d2,.mc_copy
.mc_next:
        move.l  vp_Next(a0),a0       ; next ViewPort
        bra.s   .mc_vp
.mc_end:
                endc
        move.w  #$FFFF,(a4)+         ; WAIT $FFFF,$FFFE = end of list
        move.w  #$FFFE,(a4)+
        move.l  a3,v_LOFCprList(a2) ; publishes the master
.mc_ret:
        movem.l (sp)+,d2/a2/a3/a4/a5/a6
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
; COP1LC copinit) + enables
; Copper/bitplane/sprite DMA + sets
; gb_ActiView. a1 == 0 (NULL view) -> BLANKS the display: turns off the system's bitplane (RASTER) AND copper
; DMA, so that the caller (e.g. flt-intro) can set up ITS own COP1LC + bitplanes without our boot copper
; overwriting them. REQUIRED by flt-intro, which does LoadView(NULL) before taking over the hardware.
gfx_LoadView:
        move.l  a1,gb_ActiView(a6)   ; GfxBase.ActiView = view (0 if NULL)
        move.l  a1,d0
        beq.s   .lv_null             ; NULL view -> stop the system display
        move.w  v_Modes(a1),gb_Modes(a6)
        move.l  v_LOFCprList(a1),d0
        beq.s   .lv_ret              ; no copper list -> nothing
        move.l  d0,gb_LOFlist(a6)
        movem.l d2/a4/a5,-(sp)       ; current sprite pointers (a list built earlier is up to date);
        move.l  d0,a4                ; d2 preserved (gfx_sprmoves overwrites it, library contract)
        move.l  a6,a5
        bsr     gfx_sprmoves
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
        move.w  #GFX_DMA_ON,DMACON   ; master DMA + Copper + bitplane
        move.w  #0,COPJMP1           ; strobe COP1
.lv_ret:
        rts
.lv_null:
        clr.l   gb_SprCop(a6)
        move.w  #(DMAF_RASTER|DMAF_COPPER|DMAF_SPRITE),DMACON  ; clear (SETCLR=0) bitplane/copper/sprite DMA -> system
        rts                                        ; display stopped (flt-intro will install its own COP1LC/bitplanes)

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
; instead of being relayed by the BLIT interrupt, and QBSBlit does not wait for the beam (like 1.3 outside GELs).
BN_FUNCTION     EQU 4
BN_STAT         EQU 8
BN_CLEANUP      EQU $E
BNB_CLEANUP     EQU 6
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
; for it to be idle. The system uses it too (ScrollRaster): a program that holds it holds it for everyone.
gfx_OwnBlitter:
        move.l  a6,-(sp)
        lea     gb_BlitSem(a6),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  (sp)+,a6
        bra.s   gfx_WaitBlit

; gfx_DisownBlitter(): releases the blitter. No effect if the current task does not own it.
gfx_DisownBlitter:
        move.l  a6,-(sp)
        lea     gb_BlitSem(a6),a0
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),d0
        cmp.l   GB_SS_OWNER(a0),d0
        bne.s   .db_ret
        jsr     LVO_RELEASESEMAPHORE(a6)
.db_ret:
        move.l  (sp)+,a6
        rts
; GetSprite(sprite a0, number d0) -> d0 = reserved channel | -1. d0 = -1: first free channel (0 reserved for the
; pointer).
gfx_GetSprite:
        move.w  gb_SprUsed(a6),d1
        tst.w   d0
        bpl.s   .gs_one
        moveq   #1,d0
.gs_find:
        btst    d0,d1
        beq.s   .gs_take
        addq.w  #1,d0
        cmp.w   #8,d0
        blo.s   .gs_find
        bra.s   .gs_fail
.gs_one:
        cmp.w   #8,d0
        bhs.s   .gs_fail
        btst    d0,d1
        bne.s   .gs_fail
.gs_take:
        bset    d0,d1
        move.w  d1,gb_SprUsed(a6)
        move.w  d0,ss_num(a0)
        ext.l   d0
        rts
.gs_fail:
        moveq   #-1,d0
        rts

; FreeSprite(number d0): the channel becomes free again for GetSprite.
gfx_FreeSprite:
        cmp.w   #8,d0
        bhs.s   .fs_ret
        move.w  gb_SprUsed(a6),d1
        bclr    d0,d1
        move.w  d1,gb_SprUsed(a6)
.fs_ret:
        rts

; VBeamPos() -> d0 = current video beam line (0..312 in PAL).
gfx_VBeamPos:
        move.l  CUSTOM+$004,d0       ; VPOSR (bit 0 = line 8) then VHPOSR (line 0-7 in the high byte)
        lsr.l   #8,d0
        and.l   #$1FF,d0
        rts
; WaitTOF(): waits for the start of the next frame (the beam returns to the top of the screen).
gfx_WaitTOF:
        move.l  d2,-(sp)
        bsr.s   gfx_VBeamPos
.wt_lp:
        move.l  d0,d2
        bsr.s   gfx_VBeamPos
        cmp.l   d2,d0
        bhs.s   .wt_lp
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

; BltClear(memory a1, size d0, flags d1): zeroes the area. Flag bit 1: d0 = rows (high word) x bytes per
; row (low word), otherwise a byte count. The CPU does it: waiting for completion (bit 0) is therefore implied.
gfx_BltClear:
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

; PolyDraw(rp a1, count d0, points a0): Draw to each of the points (pairs of words x, y) from the current
; position.
gfx_PolyDraw:
        movem.l d2/a2,-(sp)
        move.l  a0,a2
        move.w  d0,d2
        bra.s   .pd_e
.pd_l:
        movem.w (a2)+,d0-d1
        bsr     gfx_Draw
.pd_e:
        dbra    d2,.pd_l
        movem.l (sp)+,d2/a2
        rts

; ChangeSprite(vp a0, sprite a1, data a2): new image for channel ss_num (POS/CTL recomputed from ss_x/ss_y);
; the channel pointer is also written into the loaded copper list.
gfx_ChangeSprite:
        movem.l a2-a3,-(sp)
        move.l  a2,ss_posctldata(a1)
        move.w  ss_num(a1),d0
        and.w   #7,d0
        move.w  d0,d1
        lsl.w   #2,d1
        lea     gb_SprData(a6),a3
        move.l  a2,0(a3,d1.w)
        move.l  gb_SprCop(a6),d1
        beq.s   .cs_move
        move.l  d1,a3
        lsl.w   #3,d0                ; 8 bytes per channel (2 MOVEs)
        add.w   d0,a3
        move.l  a2,d1
        swap    d1
        move.w  d1,(a3)              ; SPRxPTH
        swap    d1
        move.w  d1,4(a3)             ; SPRxPTL
.cs_move:
        movem.l (sp)+,a2-a3
        move.w  ss_x(a1),d0
        move.w  ss_y(a1),d1
        bra.s   gfx_MoveSprite

; MoveSprite(vp a0, sprite a1, x d0, y d1): positions the sprite; coordinates in low-resolution pixels, relative to
; the top-left corner of the ViewPort's display window (vp, otherwise that of the active View).
gfx_MoveSprite:
        movem.l d2-d4,-(sp)
        move.w  d0,ss_x(a1)
        move.w  d1,ss_y(a1)
        move.l  ss_posctldata(a1),d2
        beq.s   .ms_ret
        move.w  #$80,d2              ; origins: standard window (DIWSTRT $2C81)
        move.w  #$2C,d3
        move.l  a0,d4
        bne.s   .ms_vp
        move.l  gb_ActiView(a6),d4
        beq.s   .ms_org
        move.l  d4,a0
        move.l  v_ViewPort(a0),a0
        move.l  a0,d4
        beq.s   .ms_org
.ms_vp:
        tst.w   vp_Modes(a0)
        bmi.s   .ms_org              ; HIRES: standard window
        cmp.w   #320,vp_DWidth(a0)
        bls.s   .ms_org
        move.w  #(GFX_DIWSTRT&$FF)-1,d2 ; low-resolution overscan
        move.w  #GFX_DIWSTRT>>8,d3
.ms_org:
        add.w   d0,d2                ; d2 = hstart
        add.w   d1,d3                ; d3 = vstart
        move.w  d3,d4
        add.w   ss_height(a1),d4     ; d4 = vstop
        move.l  ss_posctldata(a1),a0
        move.w  d3,d0                ; POS = vstart(7..0) << 8 | hstart(8..1)
        lsl.w   #8,d0
        move.w  d2,d1
        lsr.w   #1,d1
        move.b  d1,d0
        move.w  d0,(a0)+
        move.w  d4,d0                ; CTL = vstop(7..0) << 8 | vstart(8) << 2 | vstop(8) << 1 | hstart(0)
        lsl.w   #8,d0
        btst    #8,d3
        beq.s   .ms_v8
        bset    #2,d0
.ms_v8:
        btst    #8,d4
        beq.s   .ms_e8
        bset    #1,d0
.ms_e8:
        btst    #0,d2
        beq.s   .ms_h0
        bset    #0,d0
.ms_h0:
        move.w  d0,(a0)
.ms_ret:
        movem.l (sp)+,d2-d4
        rts

graphics_end:
