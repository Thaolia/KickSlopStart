; src/graphics/layers.s — layers.library V34: rectangular layers stacked on a common BitMap.
;
; Each layer carries a list of ClipRects that tiles its bounds: visible (cr_lobs = 0, drawn directly
; into the common BitMap) or hidden (cr_lobs = the frontmost layer that covers them). For a
; LAYERSMART layer, a hidden ClipRect owns a backup BitMap (cr_BitMap) that keeps its contents; for a
; LAYERSIMPLE layer it has nothing: the re-exposed area is filled with pen 0, added to the DamageList
; (coordinates relative to the layer) and LAYERREFRESH is set.
; Origin of a backup BitMap: (MinX & ~15, MinY) of the ClipRect that created it, stored in cr_p1 (two
; words): the bit position modulo 16 is the same as on screen. Backups live in any RAM
; (MEMF_PUBLIC): graphics fills them with the CPU.
;
; REBUILD (lr_rebuild), after any change of order or bounds, creation or deletion:
;   1. new ClipRects for each layer (ly_crnew list), computed by subtracting rectangles;
;   2. phase A, screen still intact: each ClipRect of a smart layer that must receive contents (hidden,
;      or visible but moved / never visible at that place) receives a BitMap filled from the old
;      ClipRects (screen at the old position, or old backups);
;   3. exposed background (previously visible, no longer covered by any layer): cleared with pen 0;
;   4. phase B: writing the screen — temporary backups copied back then freed, re-exposed areas of simple
;      layers cleared and added to the damage;
;   5. old ClipRects (and their backups) freed, new lists installed.
; The areas written to the screen by phase B and step 3 are disjoint: the order does not matter.
; LAYERSUPER layers: treated as LAYERSMART (no separate SuperBitMap, ScrollLayer has no effect).
; Locks: each operation holds the Layer_Info semaphore and that of each layer (LockLayers); graphics
; holds the layer's one during a drawing.
; IMPLEMENTATION track ("clean"): layers.library AutoDocs + graphics/clip.h, layers.h, regions.h. LVOs:
; AutoDoc order, cross-checked against a public Pascal unit (layers.pas). NO ROM reading.

                include "exec.i"
                include "graphics.i"

                xref    rl_add
                xref    rl_sub
                xref    rl_and
                xref    rl_free

; --- struct Layer (graphics/clip.h) ---
LY_FRONT        EQU 0
LY_BACK         EQU 4
LY_CLIPRECT     EQU 8
LY_RP           EQU 12
LY_MINX         EQU 16
LY_MINY         EQU 18
LY_MAXX         EQU 20
LY_MAXY         EQU 22
LY_FLAGS        EQU 30
LY_SUPERBM      EQU 32
LY_CRNEW        EQU 56               ; list under construction (private field "crnew")
LY_SAVECR       EQU 64               ; "_cliprects": normal list during BeginUpdate
LY_LAYERINFO    EQU 68
LY_LOCK         EQU 72               ; struct SignalSemaphore
LY_OLDX         EQU 138              ; reserved2: position before the current operation
LY_OLDY         EQU 140
LY_NEW          EQU 142              ; byte: layer created by the current operation
LY_CLIPREGION   EQU 126              ; struct Region *: the application's clip region (InstallClipRegion)
LY_DAMAGE       EQU 156              ; struct Region *
LY_SIZE         EQU 160
LAYERSIMPLE     EQU 1
LAYERSMART      EQU 2
LAYERSUPER      EQU 4
LAYERUPDATING   EQU $10
LAYERBACKDROP   EQU $40
LAYERREFRESH    EQU $80
LAYER_CLIPRECTS_LOST EQU $0100       ; incomplete reduced list (insufficient memory)
; --- struct ClipRect ---
CR_NEXT         EQU 0
CR_PREV         EQU 4
CR_LOBS         EQU 8
CR_BITMAP       EQU 12
CR_MINX         EQU 16
CR_MINY         EQU 18
CR_MAXX         EQU 20
CR_MAXY         EQU 22
CR_ORGX         EQU 24               ; _p1: origin (X, Y) of the backup BitMap
CR_ORGY         EQU 26
CR_FLAGS        EQU 36               ; private: CRF_TEMP / CRF_BORROWED
CR_SIZE         EQU 40
CRF_TEMP        EQU 1                ; temporary backup (phase A -> B)
CRF_BORROWED    EQU 2                ; BitMap belonging to another ClipRect (BeginUpdate list)
CRF_EXPOSE      EQU 4                ; visible, in place, partly exposed: direct copy in phase B
; --- struct Layer_Info ---
LI_TOP          EQU 0
LI_LOCK         EQU 24
LI_GSHEAD       EQU 70
LI_FLAGS        EQU 88
LI_LOCKCNT      EQU 91               ; byte: LockLayers nesting level
LI_SIZE         EQU 102
NEWLAYERINFO_CALLED EQU 1
; --- rectangle list node (RegionRectangle) ---
RR_NEXT         EQU 0
RR_MINX         EQU 8
RR_SIZE         EQU 16
; --- library base ---
LB_GFX          EQU LIB_SIZE
LB_SIZE         EQU LIB_SIZE+4

LVO_BLTBITMAP_G EQU -30
LVO_INITRASTPORT_G EQU -198
LVO_ORRECTREGION_G EQU -510
LVO_NEWREGION_G EQU -516
LVO_CLEARREGION_G EQU -528
LVO_DISPOSEREGION_G EQU -534

        EVEN
layers_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    layers_romtag
        dc.l    layers_end
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,31
        dc.l    layers_name
        dc.l    layers_name
        dc.l    layers_inittab
layers_name:
        dc.b    "layers.library",0
lb_gfxname:
        dc.b    "graphics.library",0
        EVEN
layers_inittab:
        dc.l    LB_SIZE
        dc.l    layers_vectors
        dc.l    layers_datatab
        dc.l    layers_initfunc
layers_vectors:
        dc.l    ly_open              ; -6
        dc.l    ly_close             ; -12
        dc.l    ly_null              ; -18
        dc.l    ly_null              ; -24
        dc.l    ly_InitLayers        ; -30
        dc.l    ly_CreateUpfrontLayer ; -36
        dc.l    ly_CreateBehindLayer ; -42
        dc.l    ly_UpfrontLayer      ; -48
        dc.l    ly_BehindLayer       ; -54
        dc.l    ly_MoveLayer         ; -60
        dc.l    ly_SizeLayer         ; -66
        dc.l    ly_ScrollLayer       ; -72
        dc.l    ly_BeginUpdate       ; -78
        dc.l    ly_EndUpdate         ; -84
        dc.l    ly_DeleteLayer       ; -90
        dc.l    ly_LockLayer         ; -96
        dc.l    ly_UnlockLayer       ; -102
        dc.l    ly_LockLayers        ; -108
        dc.l    ly_UnlockLayers      ; -114
        dc.l    ly_LockLayerInfo     ; -120
        dc.l    ly_SwapBitsRastPortClipRect ; -126
        dc.l    ly_WhichLayer        ; -132
        dc.l    ly_UnlockLayerInfo   ; -138
        dc.l    ly_NewLayerInfo      ; -144
        dc.l    ly_DisposeLayerInfo  ; -150
        dc.l    ly_FattenLayerInfo   ; -156
        dc.l    ly_ThinLayerInfo     ; -162
        dc.l    ly_MoveLayerInFrontOf ; -168
        dc.l    ly_InstallClipRegion ; -174
        dc.l    -1
layers_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)
        dc.w    $D000,LIB_VERSION,34
        dc.b    0
        EVEN

; initFunc (d0 = base, a6 = SysBase): name, GfxBase (graphics, pri 65, is already there).
layers_initfunc:
        move.l  a2,-(sp)
        move.l  d0,a2
        lea     layers_name(pc),a0
        move.l  a0,LN_NAME(a2)
        lea     lb_gfxname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,LB_GFX(a2)
        move.l  a2,d0
        move.l  (sp)+,a2
        rts

ly_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
ly_close:
        subq.w  #1,LIB_OPENCNT(a6)
ly_null:
        moveq   #0,d0
        rts

; ============================ Layer_Info and locks ============================

; InitLayers(li a0): empty Layer_Info, semaphore initialised.
ly_InitLayers:
        move.l  a6,-(sp)
        move.l  a0,a1
        moveq   #LI_SIZE/2-1,d0
.il_clr:
        clr.w   (a1)+
        dbra    d0,.il_clr
        move.l  a0,-(sp)
        lea     LI_LOCK(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_INITSEMAPHORE(a6)
        move.l  (sp)+,a0
        lea     LI_GSHEAD+4(a0),a1   ; empty MinList
        move.l  a1,LI_GSHEAD(a0)
        clr.l   LI_GSHEAD+4(a0)
        lea     LI_GSHEAD(a0),a1
        move.l  a1,LI_GSHEAD+8(a0)
        move.l  (sp)+,a6
        rts

; NewLayerInfo() -> d0 = ready Layer_Info, or 0.
ly_NewLayerInfo:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  ($4).w,a6
        moveq   #LI_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .nl_r
        move.l  d0,-(sp)
        move.l  d0,a0
        move.l  a2,a6
        bsr     ly_InitLayers
        move.l  (sp)+,d0
        move.l  d0,a0
        or.w    #NEWLAYERINFO_CALLED,LI_FLAGS(a0)
.nl_r:
        movem.l (sp)+,a2/a6
        rts

; DisposeLayerInfo(li a0).
ly_DisposeLayerInfo:
        move.l  a6,-(sp)
        move.l  a0,a1
        moveq   #LI_SIZE,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
        rts

; FattenLayerInfo(li a0) -> TRUE; ThinLayerInfo(li a0): nothing to add or remove here.
ly_FattenLayerInfo:
        moveq   #-1,d0
        rts
ly_ThinLayerInfo:
        rts

; LockLayerInfo(li a0) / UnlockLayerInfo(li a0).
ly_LockLayerInfo:
        lea     LI_LOCK(a0),a0
        bra     ly_obtain
ly_UnlockLayerInfo:
        lea     LI_LOCK(a0),a0
        bra     ly_release
; LockLayer(dummy a0, l a1) / UnlockLayer(l a0).
ly_LockLayer:
        lea     LY_LOCK(a1),a0
ly_obtain:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  (sp)+,a6
        rts
ly_UnlockLayer:
        lea     LY_LOCK(a0),a0
ly_release:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        move.l  (sp)+,a6
        rts

; LockLayers(li a0): Layer_Info then each layer, from front to back. At the first level, the reduced list
; of each layer that has a ClipRegion is undone: layer operations work on the normal lists.
ly_LockLayers:
        movem.l a2-a4,-(sp)
        move.l  a0,a3
        bsr     ly_LockLayerInfo
        move.l  LI_TOP(a3),a2
.ll_lp:
        cmpa.w  #0,a2
        beq.s   .ll_cnt
        lea     LY_LOCK(a2),a0
        bsr     ly_obtain
        move.l  LY_BACK(a2),a2
        bra.s   .ll_lp
.ll_cnt:
        addq.b  #1,LI_LOCKCNT(a3)
        cmp.b   #1,LI_LOCKCNT(a3)
        bne.s   .ll_r
        move.l  LI_TOP(a3),a4
.ll_reg:
        cmpa.w  #0,a4
        beq.s   .ll_r
        tst.l   LY_CLIPREGION(a4)
        beq.s   .ll_rn
        bsr     lr_unclip
.ll_rn:
        move.l  LY_BACK(a4),a4
        bra.s   .ll_reg
.ll_r:
        movem.l (sp)+,a2-a4
        rts
; UnlockLayers(li a0). At the last level, the reduced list of each layer that has a ClipRegion is rebuilt
; on the new arrangement.
ly_UnlockLayers:
        movem.l a2/a4,-(sp)
        move.l  a0,-(sp)
        subq.b  #1,LI_LOCKCNT(a0)
        bne.s   .ul_go
        move.l  LI_TOP(a0),a4
.ul_reg:
        cmpa.w  #0,a4
        beq.s   .ul_go
        tst.l   LY_CLIPREGION(a4)
        beq.s   .ul_rn
        bsr     lr_unclip            ; (region installed during the lock by the same task)
        bsr     lr_clip
.ul_rn:
        move.l  LY_BACK(a4),a4
        bra.s   .ul_reg
.ul_go:
        move.l  (sp),a0
        move.l  LI_TOP(a0),a2
.ul_lp:
        cmpa.w  #0,a2
        beq.s   .ul_li
        lea     LY_LOCK(a2),a0
        bsr     ly_release
        move.l  LY_BACK(a2),a2
        bra.s   .ul_lp
.ul_li:
        move.l  (sp)+,a0
        bsr     ly_UnlockLayerInfo
        movem.l (sp)+,a2/a4
        rts

; WhichLayer(li a0, x d0, y d1) -> d0 = frontmost layer containing the point, or 0.
ly_WhichLayer:
        move.l  LI_TOP(a0),a0
.wl_lp:
        cmpa.w  #0,a0
        beq.s   .wl_no
        cmp.w   LY_MINX(a0),d0
        blt.s   .wl_next
        cmp.w   LY_MAXX(a0),d0
        bgt.s   .wl_next
        cmp.w   LY_MINY(a0),d1
        blt.s   .wl_next
        cmp.w   LY_MAXY(a0),d1
        bgt.s   .wl_next
        move.l  a0,d0
        rts
.wl_next:
        move.l  LY_BACK(a0),a0
        bra.s   .wl_lp
.wl_no:
        moveq   #0,d0
        rts

; ============================ layer order ============================
; A LAYERBACKDROP layer always stays behind the others.

; lr_unlink(a4 = layer): removes it from its Layer_Info's stack.
lr_unlink:
        move.l  LY_LAYERINFO(a4),a0
        move.l  LY_FRONT(a4),d0
        move.l  LY_BACK(a4),d1
        tst.l   d0
        bne.s   .un_f
        move.l  d1,LI_TOP(a0)
        bra.s   .un_b
.un_f:
        move.l  d0,a1
        move.l  d1,LY_BACK(a1)
.un_b:
        tst.l   d1
        beq.s   .un_r
        move.l  d1,a1
        move.l  d0,LY_FRONT(a1)
.un_r:
        clr.l   LY_FRONT(a4)
        clr.l   LY_BACK(a4)
        rts

; lr_insert(a4 = layer, a0 = layer in front of which to insert it, 0 = at the very back).
lr_insert:
        move.l  LY_LAYERINFO(a4),a1
        cmpa.w  #0,a0
        bne.s   .in_before
        move.l  LI_TOP(a1),d0        ; at the back: after the last one
        bne.s   .in_last
        move.l  a4,LI_TOP(a1)
        rts
.in_last:
        move.l  d0,a0
.in_lp:
        tst.l   LY_BACK(a0)
        beq.s   .in_tail
        move.l  LY_BACK(a0),a0
        bra.s   .in_lp
.in_tail:
        move.l  a4,LY_BACK(a0)
        move.l  a0,LY_FRONT(a4)
        rts
.in_before:
        move.l  LY_FRONT(a0),d0
        move.l  d0,LY_FRONT(a4)
        move.l  a0,LY_BACK(a4)
        move.l  a4,LY_FRONT(a0)
        tst.l   d0
        bne.s   .in_mid
        move.l  a4,LI_TOP(a1)
        rts
.in_mid:
        move.l  d0,a0
        move.l  a4,LY_BACK(a0)
        rts

; lr_frontpos(a4 = layer outside the stack) -> a0 = layer in front of which to place it "at the very front": the first
; one for a normal layer, the first backdrop layer for a backdrop (0 = at the back).
lr_frontpos:
        move.l  LY_LAYERINFO(a4),a0
        move.l  LI_TOP(a0),a0
        btst    #6,LY_FLAGS+1(a4)    ; LAYERBACKDROP
        beq.s   .fp_r
        bra     lr_firstbackdrop
.fp_r:
        rts
; lr_backpos(a4) -> a0 = "at the very back" position: first backdrop for a normal layer, 0 for a backdrop.
lr_backpos:
        suba.l  a0,a0
        btst    #6,LY_FLAGS+1(a4)
        bne.s   .bp_r
        move.l  LY_LAYERINFO(a4),a0
        move.l  LI_TOP(a0),a0
        bra     lr_firstbackdrop
.bp_r:
        rts
; lr_firstbackdrop(a0 = start) -> a0 = first backdrop layer starting from a0, or 0.
lr_firstbackdrop:
        cmpa.w  #0,a0
        beq.s   .fb_r
        btst    #6,LY_FLAGS+1(a0)
        bne.s   .fb_r
        move.l  LY_BACK(a0),a0
        bra     lr_firstbackdrop
.fb_r:
        rts

; ============================ creation / deletion ============================

; CreateUpfrontLayer(li a0, bm a1, x0 d0, y0 d1, x1 d2, y1 d3, flags d4, bm2 a2) -> d0 = layer or 0.
ly_CreateUpfrontLayer:
        movem.l d2-d7/a2-a6,-(sp)
        moveq   #0,d7
        bra     lr_create
; CreateBehindLayer(...): same thing, placed behind.
ly_CreateBehindLayer:
        movem.l d2-d7/a2-a6,-(sp)
        moveq   #1,d7
; lr_create: d7 = 0 in front / 1 behind; caller's registers already pushed.
lr_create:
        move.l  d7,-(sp)             ; requested position
        move.l  a6,a5                ; a5 = LayersBase
        move.l  a0,a3                ; a3 = Layer_Info
        movem.w d0-d3,-(sp)          ; bounds
        move.l  a1,-(sp)             ; common BitMap
        move.l  ($4).w,a6
        move.l  #LY_SIZE+rp_SIZEOF,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .cr_fail
        move.l  d0,a4                ; a4 = layer, RastPort right after it
        move.l  (sp)+,d5             ; d5 = BitMap
        movem.w (sp)+,d0-d3
        movem.w d0-d3,LY_MINX(a4)
        move.w  d0,LY_OLDX(a4)
        move.w  d1,LY_OLDY(a4)
        move.b  #1,LY_NEW(a4)
        move.w  d4,LY_FLAGS(a4)
        move.l  a2,LY_SUPERBM(a4)
        move.l  a3,LY_LAYERINFO(a4)
        lea     LY_LOCK(a4),a0
        jsr     LVO_INITSEMAPHORE(a6)
        move.l  LB_GFX(a5),a6
        jsr     LVO_NEWREGION_G(a6)
        move.l  d0,LY_DAMAGE(a4)
        lea     LY_SIZE(a4),a1
        move.l  a1,LY_RP(a4)
        jsr     LVO_INITRASTPORT_G(a6)
        move.l  LY_RP(a4),a1
        move.l  a4,rp_Layer(a1)
        move.l  d5,rp_BitMap(a1)
        move.l  a3,a0
        bsr     ly_LockLayers
        move.l  (sp)+,d7
        tst.l   d7
        bne.s   .cr_back
        bsr     lr_frontpos
        bra.s   .cr_ins
.cr_back:
        bsr     lr_backpos
.cr_ins:
        bsr     lr_insert
        lea     LY_LOCK(a4),a0       ; the new layer is locked like the others during the operation
        bsr     ly_obtain
        move.l  a3,a0
        suba.l  a1,a1
        bsr     lr_rebuild
        move.l  a3,a0
        bsr     ly_UnlockLayers
        move.l  a4,d0
        bra.s   .cr_out
.cr_fail:
        lea     16(sp),sp            ; BitMap + bounds + position
        moveq   #0,d0
.cr_out:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; DeleteLayer(dummy a0, l a1) -> TRUE. The layers behind and the background get the area back. Three steps called
; with their argument on the stack (C convention): lock of the whole Layer_Info, removal of the layer, unlock.
; The entry word is followed by a branch to the body, whose three BSRs are the only ones in the sequence:
; that is how SetPatch 1.38 finds these three steps for its own DeleteLayer (docs/analysis/setpatch-138.md §1.8).
ly_DeleteLayer:
        nop
        bra.s   ly_dl_body
; ly_dl_lock(Layer_Info) -> d0 = 1: layers and Layer_Info locked. C convention (preserves d2-d7/a2-a6).
ly_dl_lock:
        move.l  4(sp),a0
        bsr     ly_LockLayers
        moveq   #1,d0
        rts
; ly_dl_unlock(Layer_Info).
ly_dl_unlock:
        move.l  4(sp),a0
        bra     ly_UnlockLayers
ly_dl_body:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,a4
        move.l  LY_LAYERINFO(a4),a3
        move.l  a3,-(sp)
        bsr.s   ly_dl_lock
        move.l  a4,(sp)
        bsr.s   ly_dl_remove
        move.l  a3,(sp)
        bsr.s   ly_dl_unlock
        addq.l  #4,sp
        moveq   #-1,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts
; ly_dl_remove(layer, a6 = LayersBase): the layer leaves the stack, the area is given back to the layers behind and
; to the background, then its ClipRects, damage region and memory are freed. The Layer_Info stays locked.
ly_dl_remove:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  44+4(sp),a4          ; layer (above the 11 saved registers and the return address)
        move.l  a6,a5
        move.l  LY_LAYERINFO(a4),a3
        bsr     lr_unlink
        move.l  a3,a0
        move.l  a4,a1                ; old ClipRects of the deleted layer: background to expose
        bsr     lr_rebuild
        lea     LY_LOCK(a4),a0       ; its lock is no longer released by UnlockLayers (it has left the stack)
        bsr     ly_release
        lea     LY_CLIPRECT(a4),a2
        bsr     lr_freecrs
        move.l  LB_GFX(a5),a6
        move.l  LY_DAMAGE(a4),a0
        jsr     LVO_DISPOSEREGION_G(a6)
        move.l  ($4).w,a6
        move.l  a4,a1
        move.l  #LY_SIZE+rp_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ============================ order, position, size ============================
; lr_op_enter(a1 = layer): a5 = LayersBase, a4 = layer, a3 = Layer_Info, everything locked.
; lr_op_leave: rebuilds, unlocks, d0 = TRUE. (Frame: d2-d7/a2-a6 pushed by the caller.)
lr_op_enter:
        move.l  a6,a5
        move.l  a1,a4
        move.l  LY_LAYERINFO(a4),a3
        move.l  a3,a0
        bra     ly_LockLayers
lr_op_leave:
        move.l  a3,a0
        suba.l  a1,a1
        bsr     lr_rebuild
        move.l  a3,a0
        bsr     ly_UnlockLayers
        moveq   #-1,d0
        rts

; UpfrontLayer(dummy a0, l a1) -> TRUE.
ly_UpfrontLayer:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     lr_op_enter
        bsr     lr_unlink
        bsr     lr_frontpos
        bra     lr_reorder
; BehindLayer(dummy a0, l a1) -> TRUE.
ly_BehindLayer:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     lr_op_enter
        bsr     lr_unlink
        bsr     lr_backpos
lr_reorder:
        bsr     lr_insert
        bsr     lr_op_leave
        movem.l (sp)+,d2-d7/a2-a6
        rts
; MoveLayerInFrontOf(l a0, other a1) -> TRUE: l just in front of other.
ly_MoveLayerInFrontOf:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,-(sp)
        move.l  a0,a1
        bsr     lr_op_enter
        bsr     lr_unlink
        move.l  (sp)+,a0
        bra     lr_reorder

; MoveLayer(dummy a0, l a1, dx d0, dy d1) -> TRUE.
ly_MoveLayer:
        movem.l d2-d7/a2-a6,-(sp)
        movem.w d0-d1,-(sp)
        bsr     lr_op_enter
        movem.w (sp)+,d0-d1
        add.w   d0,LY_MINX(a4)
        add.w   d0,LY_MAXX(a4)
        add.w   d1,LY_MINY(a4)
        add.w   d1,LY_MAXY(a4)
        bsr     lr_op_leave
        movem.l (sp)+,d2-d7/a2-a6
        rts

; SizeLayer(dummy a0, l a1, dx d0, dy d1) -> TRUE: bottom-right corner moved, contents kept in the common part.
ly_SizeLayer:
        movem.l d2-d7/a2-a6,-(sp)
        movem.w d0-d1,-(sp)
        bsr     lr_op_enter
        movem.w (sp)+,d0-d1
        add.w   d0,LY_MAXX(a4)
        add.w   d1,LY_MAXY(a4)
        bsr     lr_op_leave
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ScrollLayer(dummy a0, l a1, dx d0, dy d1): reserved for SuperBitMaps, not handled here.
ly_ScrollLayer:
        rts

; ============================ BeginUpdate / EndUpdate ============================

; BeginUpdate(l a0) -> TRUE: the ClipRect list becomes its part within the DamageList (∩ ClipRegion if there is
; one), so that only the damaged areas are redrawn. The layer stays locked until EndUpdate.
ly_BeginUpdate:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a4
        lea     LY_LOCK(a4),a0
        bsr     ly_obtain
        bsr     lr_unclip
        or.w    #LAYERUPDATING,LY_FLAGS(a4)
        bsr     lr_clip
        moveq   #-1,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; InstallClipRegion(l a0, region a1) -> d0 = old region. The ClipRect list becomes its part within the region
; (layer coordinates): a snapshot, a modified region must be reinstalled. NULL: normal list.
ly_InstallClipRegion:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a4
        move.l  a1,a2
        lea     LY_LOCK(a4),a0
        bsr     ly_obtain
        move.l  LY_CLIPREGION(a4),d5
        bsr     lr_unclip
        move.l  a2,LY_CLIPREGION(a4)
        bsr     lr_clip
        lea     LY_LOCK(a4),a0
        bsr     ly_release
        move.l  d5,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_unclip(a4 = layer): reduced list (BeginUpdate or ClipRegion) freed, normal list restored. Preserves
; d2-d7/a2-a6.
lr_unclip:
        tst.l   LY_SAVECR(a4)
        beq.s   .uc_r
        move.l  a2,-(sp)
        lea     LY_CLIPRECT(a4),a2
        bsr     lr_freecrs           ; borrowed ClipRects: BitMaps not freed
        move.l  LY_SAVECR(a4),LY_CLIPRECT(a4)
        clr.l   LY_SAVECR(a4)
        move.l  (sp)+,a2
.uc_r:
        rts

; lr_clip(a4 = layer, normal list in place): C = DamageList (∩ ClipRegion) during BeginUpdate, else ClipRegion;
; without C, nothing. Otherwise the normal list is kept in ly__cliprects and replaced by its ClipRects ∩ C: visible,
; and hidden with backup (borrowed BitMap: drawing into it writes the backup). Region without rectangles: no
; ClipRect. Insufficient memory: partial list and LAYER_CLIPRECTS_LOST. Preserves d2-d7/a2-a6.
lr_clip:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  LY_CLIPREGION(a4),d6 ; d6 = 1st region, d7 = 2nd (0: none)
        moveq   #0,d7
        btst    #4,LY_FLAGS+1(a4)    ; LAYERUPDATING
        beq.s   .cl_reg
        move.l  d6,d7
        move.l  LY_DAMAGE(a4),d6
        bra.s   .cl_build
.cl_reg:
        tst.l   d6
        beq     .cl_ret
.cl_build:
        clr.l   -(sp)                ; cell of the new list
        move.l  sp,a5
        move.l  LY_CLIPRECT(a4),a3
.cb_cr:
        cmpa.w  #0,a3
        beq     .cb_done
        tst.l   CR_LOBS(a3)
        beq.s   .cb_use
        tst.l   CR_BITMAP(a3)
        beq.s   .cb_next             ; hidden without backup: nothing to draw
.cb_use:
        tst.l   d6
        beq.s   .cb_next
        move.l  d6,a0
        move.l  8(a0),a2
.cb_r1:
        cmpa.w  #0,a2
        beq.s   .cb_next
        move.l  d6,a0
        bsr     lr_dmgrect
        lea     CR_MINX(a3),a0
        bsr     lr_isect
        bgt.s   .cb_n1
        tst.l   d7
        bne.s   .cb_two
        bsr.s   .cb_add
        bra.s   .cb_n1
.cb_two:
        movem.w d0-d3,-(sp)          ; ClipRect ∩ rectangle of the 1st region
        move.l  d7,a0
        move.l  8(a0),a6
.cb_r2:
        cmpa.w  #0,a6
        beq.s   .cb_e2
        exg     a2,a6
        move.l  d7,a0
        bsr     lr_dmgrect
        exg     a2,a6
        move.l  sp,a0
        bsr     lr_isect
        bgt.s   .cb_n2
        bsr.s   .cb_add
.cb_n2:
        move.l  RR_NEXT(a6),a6
        bra.s   .cb_r2
.cb_e2:
        addq.l  #8,sp
.cb_n1:
        move.l  RR_NEXT(a2),a2
        bra.s   .cb_r1
.cb_next:
        move.l  CR_NEXT(a3),a3
        bra.s   .cb_cr
.cb_add:                             ; ClipRect d0..d3 at the head of the list (a5), same lobs/backup as a3
        move.l  a5,a1
        bsr     lr_newcr
        cmpa.w  #0,a0
        beq.s   .ca_lost
        move.l  CR_LOBS(a3),CR_LOBS(a0)
        move.l  CR_BITMAP(a3),CR_BITMAP(a0)
        move.l  CR_ORGX(a3),CR_ORGX(a0)
        move.b  #CRF_BORROWED,CR_FLAGS+3(a0)
        rts
.ca_lost:
        or.w    #LAYER_CLIPRECTS_LOST,LY_FLAGS(a4)
        rts
.cb_done:
        move.l  LY_CLIPRECT(a4),LY_SAVECR(a4)
        move.l  (sp)+,LY_CLIPRECT(a4)
.cl_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_isect(d0..d3 = rectangle, a0 = bounds (4 words)) -> d0..d3 ∩ bounds; condition GT if the intersection is empty.
lr_isect:
        cmp.w   (a0),d0
        bge.s   .is_1
        move.w  (a0),d0
.is_1:
        cmp.w   2(a0),d1
        bge.s   .is_2
        move.w  2(a0),d1
.is_2:
        cmp.w   4(a0),d2
        ble.s   .is_3
        move.w  4(a0),d2
.is_3:
        cmp.w   6(a0),d3
        ble.s   .is_4
        move.w  6(a0),d3
.is_4:
        cmp.w   d2,d0
        bgt.s   .is_r
        cmp.w   d3,d1
.is_r:
        rts

; lr_dmgrect(a4 = layer, a0 = region relative to the layer, a2 = its rectangle) -> d0..d3 = absolute rectangle.
; Clobbers d4.
lr_dmgrect:
        movem.w RR_MINX(a2),d0-d3
        move.w  (a0),d4              ; region: bounds relative to the layer
        add.w   LY_MINX(a4),d4
        add.w   d4,d0
        add.w   d4,d2
        move.w  2(a0),d4
        add.w   LY_MINY(a4),d4
        add.w   d4,d1
        add.w   d4,d3
        rts

; EndUpdate(l a0, flag d0): normal list restored (or reduced to the ClipRegion); flag != 0 -> damage cleared and
; LAYERREFRESH removed.
ly_EndUpdate:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a4
        move.l  d0,d7
        move.l  a6,a5
        btst    #4,LY_FLAGS+1(a4)    ; LAYERUPDATING
        beq.s   .eu_flag
        bsr     lr_unclip
        and.w   #~LAYERUPDATING,LY_FLAGS(a4)
        bsr     lr_clip              ; ClipRegion only, if there is one
.eu_flag:
        tst.l   d7
        beq.s   .eu_unlock
        move.l  LB_GFX(a5),a6
        move.l  LY_DAMAGE(a4),a0
        jsr     LVO_CLEARREGION_G(a6)
        and.w   #~LAYERREFRESH,LY_FLAGS(a4)
.eu_unlock:
        lea     LY_LOCK(a4),a0
        bsr     ly_release
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ============================ SwapBitsRastPortClipRect ============================

; SwapBitsRastPortClipRect(rp a0, cr a1): swaps the contents of the ClipRect's area in the RastPort's BitMap
; with that of the ClipRect's BitMap (same bit alignment: byte-by-byte swap, edges masked).
ly_SwapBitsRastPortClipRect:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  CR_BITMAP(a1),d0
        beq     .sw_r
        move.l  d0,a3                ; a3 = BitMap of the ClipRect
        move.l  rp_BitMap(a0),a2     ; a2 = BitMap of the RastPort
        move.w  CR_MINX(a1),d4
        move.w  CR_MAXX(a1),d5
        move.w  d4,d0                ; edge masks
        and.w   #7,d0
        moveq   #-1,d6
        lsr.b   d0,d6                ; d6.b = left mask
        move.w  d5,d0
        and.w   #7,d0
        moveq   #7,d1
        sub.w   d0,d1
        moveq   #-1,d7
        lsl.b   d1,d7                ; d7.b = right mask
        lsr.w   #3,d4                ; start / end bytes (screen)
        lsr.w   #3,d5
        cmp.w   d4,d5
        bne.s   .sw_m
        and.b   d7,d6
.sw_m:
        move.w  CR_MINY(a1),d3       ; d3 = screen row
        moveq   #0,d2                ; d2 = backup row
        move.w  CR_ORGX(a1),d0
        lsr.w   #3,d0
        move.w  d0,a6                ; a6 = byte offset of the backup's origin
.sw_row:
        cmp.w   CR_MAXY(a1),d3
        bgt     .sw_r
        moveq   #0,d1                ; plane
.sw_plane:
        cmp.b   bm_Depth(a2),d1
        bge.s   .sw_rnext
        cmp.b   bm_Depth(a3),d1
        bge.s   .sw_rnext
        move.w  d1,d0
        lsl.w   #2,d0
        move.l  bm_Planes(a2,d0.w),a4
        move.l  bm_Planes(a3,d0.w),a5
        moveq   #0,d0
        move.w  bm_BytesPerRow(a2),d0
        mulu    d3,d0
        add.l   d0,a4
        add.w   d4,a4                ; a4 = first screen byte
        moveq   #0,d0
        move.w  bm_BytesPerRow(a3),d0
        mulu    d2,d0
        add.l   d0,a5
        move.w  d4,d0
        sub.w   a6,d0
        add.w   d0,a5                ; a5 = first backup byte
        movem.l d1-d3,-(sp)
        move.w  d4,d3                ; d3 = current byte
.sw_byte:
        moveq   #-1,d0               ; d0.b = mask of the byte
        cmp.w   d4,d3
        bne.s   .sw_nf
        and.b   d6,d0
.sw_nf:
        cmp.w   d5,d3
        bne.s   .sw_nl
        and.b   d7,d0
.sw_nl:
        move.b  (a4),d1              ; masked swap
        move.b  (a5),d2
        eor.b   d2,d1
        and.b   d0,d1                ; d1 = bits to toggle
        eor.b   d1,(a4)+
        eor.b   d1,(a5)+
        addq.w  #1,d3
        cmp.w   d5,d3
        ble.s   .sw_byte
        movem.l (sp)+,d1-d3
        addq.w  #1,d1
        bra.s   .sw_plane
.sw_rnext:
        addq.w  #1,d3
        addq.w  #1,d2
        bra     .sw_row
.sw_r:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; ============================ ClipRect tools ============================

; lr_newcr(d0..d3 = bounds, a1 = list cell) -> a0 = zeroed ClipRect, at the head of the list, or 0.
; Preserves d0-d7/a1-a6.
lr_newcr:
        movem.l d0-d3/a1/a6,-(sp)
        move.l  ($4).w,a6
        moveq   #CR_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a0
        movem.l (sp)+,d0-d3/a1/a6
        cmpa.w  #0,a0
        beq.s   .nc_r
        movem.w d0-d3,CR_MINX(a0)
        move.l  (a1),CR_NEXT(a0)
        move.l  a0,(a1)
.nc_r:
        rts

; lr_freecrs(a2 = list cell): frees the ClipRects and the BitMaps they own (not borrowed ones).
lr_freecrs:
        movem.l a3/a6,-(sp)
        move.l  ($4).w,a6
.fc_lp:
        move.l  (a2),d0
        beq.s   .fc_r
        move.l  d0,a3
        move.l  CR_NEXT(a3),(a2)
        btst    #1,CR_FLAGS+3(a3)    ; CRF_BORROWED
        bne.s   .fc_cr
        move.l  CR_BITMAP(a3),d0
        beq.s   .fc_cr
        move.l  d0,a0
        bsr     lr_freebm
.fc_cr:
        move.l  a3,a1
        moveq   #CR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .fc_lp
.fc_r:
        movem.l (sp)+,a3/a6
        rts

; lr_bmsize(a0 = backup BitMap) -> d0 = size of the allocation (struct + contiguous planes).
lr_bmsize:
        moveq   #0,d0
        move.w  bm_BytesPerRow(a0),d0
        mulu    bm_Rows(a0),d0
        moveq   #0,d1
        move.b  bm_Depth(a0),d1
        mulu    d1,d0
        add.l   #bm_SIZEOF,d0
        rts
; lr_freebm(a0 = backup BitMap, a6 = SysBase).
lr_freebm:
        bsr     lr_bmsize
        move.l  a0,a1
        jmp     LVO_FREEMEM(a6)

; lr_allocbm(a3 = ClipRect, d7.b = depth) -> cr_BitMap + origin set (0 if insufficient memory).
; Contiguous planes after the structure, zeroed. Preserves d2-d7/a2-a6.
lr_allocbm:
        movem.l d2-d4/a6,-(sp)
        move.w  CR_MINX(a3),d2
        and.w   #~15,d2              ; X origin aligned to 16
        move.w  d2,CR_ORGX(a3)
        move.w  CR_MINY(a3),CR_ORGY(a3)
        move.w  CR_MAXX(a3),d3
        sub.w   d2,d3
        lsr.w   #4,d3
        addq.w  #1,d3
        add.w   d3,d3                ; d3 = bytes per row
        move.w  CR_MAXY(a3),d4
        sub.w   CR_MINY(a3),d4
        addq.w  #1,d4                ; d4 = rows
        moveq   #0,d0
        move.w  d3,d0
        mulu    d4,d0
        moveq   #0,d1
        move.b  d7,d1
        mulu    d1,d0                ; planes x depth
        add.l   #bm_SIZEOF,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,CR_BITMAP(a3)
        beq.s   .ab_r
        move.l  d0,a0
        move.w  d3,bm_BytesPerRow(a0)
        move.w  d4,bm_Rows(a0)
        move.b  d7,bm_Depth(a0)
        moveq   #0,d1                ; planes
        move.w  d3,d1
        mulu    d4,d1                ; d1 = size of one plane
        lea     bm_SIZEOF(a0),a1
        moveq   #0,d0
.ab_pl:
        cmp.b   d7,d0
        bge.s   .ab_r
        move.w  d0,d2
        lsl.w   #2,d2
        move.l  a1,bm_Planes(a0,d2.w)
        add.l   d1,a1
        addq.w  #1,d0
        bra.s   .ab_pl
.ab_r:
        movem.l (sp)+,d2-d4/a6
        rts

; lr_blt: BltBitMap(src a0, sx d0, sy d1, dst a1, dx d2, dy d3, w d4, h d5, minterm d6) via graphics (a5 =
; LayersBase). Preserves d2-d7/a2-a6.
lr_blt:
        movem.l d7/a6,-(sp)
        moveq   #-1,d7
        move.l  LB_GFX(a5),a6
        jsr     LVO_BLTBITMAP_G(a6)
        movem.l (sp)+,d7/a6
        rts

; lr_clear(a0 = BitMap, d0..d3 = absolute rectangle): area set to pen 0 (all planes at 0). Preserves d0-d7/a2-a6.
lr_clear:
        movem.l d0-d6,-(sp)
        move.w  d2,d4
        sub.w   d0,d4
        addq.w  #1,d4
        move.w  d3,d5
        sub.w   d1,d5
        addq.w  #1,d5
        move.w  d0,d2
        move.w  d1,d3
        move.l  a0,a1
        moveq   #0,d6                ; minterm 0: null result
        bsr     lr_blt
        movem.l (sp)+,d0-d6
        rts

; lr_damage(a4 = layer, d0..d3 = absolute rectangle): added to the DamageList (relative to the layer), LAYERREFRESH.
; Preserves d0-d7/a2-a6 (not a0/a1).
lr_damage:
        movem.l d0-d3/a6,-(sp)
        sub.w   LY_MINX(a4),d0
        sub.w   LY_MINX(a4),d2
        sub.w   LY_MINY(a4),d1
        sub.w   LY_MINY(a4),d3
        movem.w d0-d3,-(sp)
        move.l  sp,a1
        move.l  LY_DAMAGE(a4),d0
        beq.s   .dm_none
        move.l  d0,a0
        move.l  LB_GFX(a5),a6
        jsr     LVO_ORRECTREGION_G(a6)
.dm_none:
        addq.l  #8,sp
        or.w    #LAYERREFRESH,LY_FLAGS(a4)
        movem.l (sp)+,d0-d3/a6
        rts

; lr_screenbm(a4 = layer) -> a0 = common BitMap (the one of its RastPort).
lr_screenbm:
        move.l  LY_RP(a4),a0
        move.l  rp_BitMap(a0),a0
        rts

; lr_moved(a4) -> Z = 0 if the layer changed position during the operation.
lr_moved:
        move.w  LY_MINX(a4),d0
        cmp.w   LY_OLDX(a4),d0
        bne.s   .mv_r
        move.w  LY_MINY(a4),d0
        cmp.w   LY_OLDY(a4),d0
.mv_r:
        rts

; ============================ rebuild ============================

; lr_rebuild(a3 = Layer_Info, a1 = deleted layer or 0, a5 = LayersBase). Layers locked by the caller.
lr_rebuild:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,-(sp)             ; (sp) = deleted layer
        move.l  LI_TOP(a3),a4        ; 1. new ClipRects
.rb_1:
        cmpa.w  #0,a4
        beq.s   .rb_2
        bsr     lr_newcrs
        move.l  LY_BACK(a4),a4
        bra.s   .rb_1
.rb_2:
        move.l  LI_TOP(a3),a4        ; 2. phase A (smart layers)
.rb_2l:
        cmpa.w  #0,a4
        beq.s   .rb_3
        move.w  LY_FLAGS(a4),d0
        and.w   #LAYERSMART|LAYERSUPER,d0
        beq.s   .rb_2n
        bsr     lr_phasea
.rb_2n:
        move.l  LY_BACK(a4),a4
        bra.s   .rb_2l
.rb_3:
        move.l  (sp),a1
        bsr     lr_background        ; 3. exposed background
        move.l  LI_TOP(a3),a4        ; 4. phase B
.rb_4l:
        cmpa.w  #0,a4
        beq.s   .rb_5
        bsr     lr_phaseb
        move.l  LY_BACK(a4),a4
        bra.s   .rb_4l
.rb_5:
        move.l  LI_TOP(a3),a4        ; 5. installation
.rb_5l:
        cmpa.w  #0,a4
        beq.s   .rb_out
        lea     LY_CLIPRECT(a4),a2
        bsr     lr_freecrs
        move.l  LY_CRNEW(a4),a0
        move.l  a0,LY_CLIPRECT(a4)
        clr.l   LY_CRNEW(a4)
        suba.l  a1,a1                ; back links
.rb_prev:
        cmpa.w  #0,a0
        beq.s   .rb_pd
        move.l  a1,CR_PREV(a0)
        move.l  a0,a1
        move.l  CR_NEXT(a0),a0
        bra.s   .rb_prev
.rb_pd:
        move.w  LY_MINX(a4),LY_OLDX(a4)
        move.w  LY_MINY(a4),LY_OLDY(a4)
        clr.b   LY_NEW(a4)
        move.l  LY_BACK(a4),a4
        bra.s   .rb_5l
.rb_out:
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_newcrs(a4 = layer, a3 = Layer_Info): ly_crnew = ClipRects of its bounds against the layers in front.
; rest = {bounds}; for each layer A in front (from front to back): (rest ∩ A) -> ClipRects hidden
; by A, rest -= A; what remains is visible.
lr_newcrs:
        movem.l d2-d7/a2-a6,-(sp)
        clr.l   LY_CRNEW(a4)
        clr.l   -(sp)                ; 4(sp) = rest, (sp) = temporary
        clr.l   -(sp)
        lea     4(sp),a2
        lea     LY_MINX(a4),a1
        bsr     rl_add
        move.l  LI_TOP(a3),a6        ; a6 = current front layer
.nc_front:
        cmp.l   a4,a6
        beq.s   .nc_vis
        move.l  sp,a2                ; temporary = copy of rest ∩ A
        move.l  4(sp),a0
.nc_copy:
        cmpa.w  #0,a0
        beq.s   .nc_and
        move.l  a0,-(sp)
        lea     RR_MINX(a0),a1
        lea     4(sp),a2
        bsr     rl_add
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra.s   .nc_copy
.nc_and:
        move.l  sp,a2
        lea     LY_MINX(a6),a1
        bsr     rl_and
        move.l  (sp),a0              ; pieces hidden by A
        move.l  a6,d4
        bsr     lr_rr2cr
        move.l  sp,a2
        bsr     rl_free
        lea     4(sp),a2
        lea     LY_MINX(a6),a1
        bsr     rl_sub
        move.l  LY_BACK(a6),a6
        bra.s   .nc_front
.nc_vis:
        move.l  4(sp),a0             ; visible pieces
        moveq   #0,d4
        bsr     lr_rr2cr
        lea     4(sp),a2
        bsr     rl_free
        addq.l  #8,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts
; lr_rr2cr(a0 = first rectangle node, d4 = lobs, a4 = layer): one ClipRect per rectangle, in ly_crnew.
lr_rr2cr:
        cmpa.w  #0,a0
        beq.s   .rc_r
        move.l  a0,-(sp)
        movem.w RR_MINX(a0),d0-d3
        lea     LY_CRNEW(a4),a1
        bsr     lr_newcr
        cmpa.w  #0,a0
        beq.s   .rc_n
        move.l  d4,CR_LOBS(a0)
.rc_n:
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra     lr_rr2cr
.rc_r:
        rts

; lr_phasea(a4 = smart layer): backups of the new ClipRects that must receive contents.
lr_phasea:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     lr_screenbm
        move.b  bm_Depth(a0),d7      ; depth of the backups
        move.l  LY_CRNEW(a4),a3
.pa_lp:
        cmpa.w  #0,a3
        beq.s   .pa_r
        tst.l   CR_LOBS(a3)
        bne.s   .pa_save             ; hidden: permanent backup
        tst.b   LY_NEW(a4)
        bne.s   .pa_temp
        bsr     lr_moved
        bne.s   .pa_temp
        bsr     lr_oldviscovers      ; already visible here and not moved: the screen is correct
        beq.s   .pa_next
        move.b  #CRF_EXPOSE,CR_FLAGS+3(a3)   ; in place: only the exposed parts will go to the screen (phase B)
        bra.s   .pa_next
.pa_temp:
        move.b  #CRF_TEMP,CR_FLAGS+3(a3)
.pa_save:
        bsr     lr_allocbm
        tst.l   CR_BITMAP(a3)
        beq.s   .pa_next
        bsr     lr_fill
.pa_next:
        move.l  CR_NEXT(a3),a3
        bra.s   .pa_lp
.pa_r:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_oldviscovers(a3 = ClipRect, a4 = layer) -> Z = 1 if its bounds are covered by the layer's old visible
; ClipRects (at the same position).
lr_oldviscovers:
        movem.l d2-d7/a2-a6,-(sp)
        clr.l   -(sp)
        move.l  sp,a2
        lea     CR_MINX(a3),a1
        bsr     rl_add
        move.l  LY_CLIPRECT(a4),a3
.oc_lp:
        cmpa.w  #0,a3
        beq.s   .oc_end
        tst.l   CR_LOBS(a3)
        bne.s   .oc_n
        lea     CR_MINX(a3),a1
        bsr     rl_sub
.oc_n:
        move.l  CR_NEXT(a3),a3
        bra.s   .oc_lp
.oc_end:
        move.l  (sp),d2              ; remainder?
        bsr     rl_free
        addq.l  #4,sp
        tst.l   d2
        movem.l (sp)+,d2-d7/a2-a6    ; movem to registers: Z intact
        rts

; lr_fill(a3 = new ClipRect with backup, a4 = layer): contents from the old ClipRects (offset by the
; move), then the part without old contents (enlargement) as damage, except for a new layer.
lr_fill:
        movem.l d2-d7/a2-a6,-(sp)
        move.w  LY_MINX(a4),d6
        sub.w   LY_OLDX(a4),d6       ; d6 = X offset (new - old)
        move.w  LY_MINY(a4),d7
        sub.w   LY_OLDY(a4),d7       ; d7 = Y offset
        clr.l   -(sp)                ; area without old contents
        move.l  sp,a2
        lea     CR_MINX(a3),a1
        bsr     rl_add
        move.l  LY_CLIPRECT(a4),a6   ; a6 = old ClipRect
.fi_lp:
        cmpa.w  #0,a6
        beq     .fi_new
        movem.w CR_MINX(a6),d0-d3    ; old area, in new coordinates
        add.w   d6,d0
        add.w   d6,d2
        add.w   d7,d1
        add.w   d7,d3
        movem.w d0-d3,-(sp)
        move.l  sp,a1
        lea     8(sp),a2
        bsr     rl_sub               ; removed from the area without contents
        movem.w (sp)+,d0-d3
        cmp.w   CR_MINX(a3),d0       ; ∩ new ClipRect
        bge.s   .fi_1
        move.w  CR_MINX(a3),d0
.fi_1:
        cmp.w   CR_MINY(a3),d1
        bge.s   .fi_2
        move.w  CR_MINY(a3),d1
.fi_2:
        cmp.w   CR_MAXX(a3),d2
        ble.s   .fi_3
        move.w  CR_MAXX(a3),d2
.fi_3:
        cmp.w   CR_MAXY(a3),d3
        ble.s   .fi_4
        move.w  CR_MAXY(a3),d3
.fi_4:
        cmp.w   d2,d0
        bgt.s   .fi_next
        cmp.w   d3,d1
        bgt.s   .fi_next
        sub.w   d0,d2
        addq.w  #1,d2
        move.w  d2,d4                ; d4 = width
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  d3,d5                ; d5 = height
        move.w  d0,d2                ; destination: coordinates within a3's backup
        sub.w   CR_ORGX(a3),d2
        move.w  d1,d3
        sub.w   CR_ORGY(a3),d3
        sub.w   d6,d0                ; source: old absolute position
        sub.w   d7,d1
        tst.l   CR_LOBS(a6)
        bne.s   .fi_bk
        bsr     lr_screenbm          ; old visible area: the screen
        bra.s   .fi_do
.fi_bk:
        move.l  CR_BITMAP(a6),a0
        cmpa.w  #0,a0
        beq.s   .fi_next             ; old hidden area without backup
        sub.w   CR_ORGX(a6),d0
        sub.w   CR_ORGY(a6),d1
.fi_do:
        move.l  CR_BITMAP(a3),a1
        movem.l d6-d7,-(sp)
        moveq   #-$40,d6             ; minterm $C0 (copy)
        bsr     lr_blt
        movem.l (sp)+,d6-d7
.fi_next:
        move.l  CR_NEXT(a6),a6
        bra     .fi_lp
.fi_new:
        tst.b   LY_NEW(a4)
        bne.s   .fi_free
        move.l  (sp),a0
.fi_dmg:
        cmpa.w  #0,a0
        beq.s   .fi_free
        movem.w RR_MINX(a0),d0-d3
        move.l  a0,-(sp)             ; lr_damage overwrites a0/a1
        bsr     lr_damage
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra.s   .fi_dmg
.fi_free:
        move.l  sp,a2
        bsr     rl_free
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_expose(a3 = new visible ClipRect, a4 = smart layer that stayed in place): its previously hidden and backed-up
; parts are copied from their backup to the screen; the parts without old contents (enlargement)
; are cleared and damaged. Parts already visible are not touched.
lr_expose:
        movem.l d2-d7/a2-a6,-(sp)
        clr.l   -(sp)                ; area without old contents
        move.l  sp,a2
        lea     CR_MINX(a3),a1
        bsr     rl_add
        move.l  LY_CLIPRECT(a4),a6   ; a6 = old ClipRect
.ex_lp:
        cmpa.w  #0,a6
        beq     .ex_new
        movem.w CR_MINX(a6),d0-d3
        movem.w d0-d3,-(sp)
        move.l  sp,a1
        lea     8(sp),a2
        bsr     rl_sub
        movem.w (sp)+,d0-d3
        tst.l   CR_LOBS(a6)
        beq.s   .ex_next             ; previously visible: already on screen
        move.l  CR_BITMAP(a6),d4
        beq.s   .ex_next             ; hidden without backup
        cmp.w   CR_MINX(a3),d0       ; ∩ new ClipRect
        bge.s   .ex_1
        move.w  CR_MINX(a3),d0
.ex_1:
        cmp.w   CR_MINY(a3),d1
        bge.s   .ex_2
        move.w  CR_MINY(a3),d1
.ex_2:
        cmp.w   CR_MAXX(a3),d2
        ble.s   .ex_3
        move.w  CR_MAXX(a3),d2
.ex_3:
        cmp.w   CR_MAXY(a3),d3
        ble.s   .ex_4
        move.w  CR_MAXY(a3),d3
.ex_4:
        cmp.w   d2,d0
        bgt.s   .ex_next
        cmp.w   d3,d1
        bgt.s   .ex_next
        bsr     lr_screenbm
        move.l  a0,a1                ; destination: the screen, at the same place
        move.l  d4,a0                ; source: the backup
        sub.w   d0,d2
        addq.w  #1,d2
        move.w  d2,d4                ; width
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  d3,d5                ; height
        move.w  d0,d2
        move.w  d1,d3
        sub.w   CR_ORGX(a6),d0
        sub.w   CR_ORGY(a6),d1
        moveq   #-$40,d6             ; minterm $C0 (copy)
        bsr     lr_blt
.ex_next:
        move.l  CR_NEXT(a6),a6
        bra     .ex_lp
.ex_new:
        move.l  (sp),a0
.ex_dmg:
        cmpa.w  #0,a0
        beq.s   .ex_free
        movem.w RR_MINX(a0),d0-d3
        move.l  a0,-(sp)             ; lr_damage overwrites a0/a1
        bsr     lr_screenbm
        bsr     lr_clear
        bsr     lr_damage
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra.s   .ex_dmg
.ex_free:
        move.l  sp,a2
        bsr     rl_free
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_phaseb(a4 = layer): writing the screen for its visible ClipRects.
lr_phaseb:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  LY_CRNEW(a4),a3
.pb_lp:
        cmpa.w  #0,a3
        beq     .pb_r
        tst.l   CR_LOBS(a3)
        bne     .pb_next
        move.w  LY_FLAGS(a4),d0
        and.w   #LAYERSMART|LAYERSUPER,d0
        beq.s   .pb_simple
        btst    #0,CR_FLAGS+3(a3)    ; CRF_TEMP: temporary backup -> screen, then freed
        bne.s   .pb_temp
        btst    #2,CR_FLAGS+3(a3)    ; CRF_EXPOSE
        beq     .pb_next
        bsr     lr_expose
        clr.b   CR_FLAGS+3(a3)
        bra     .pb_next
.pb_temp:
        move.l  CR_BITMAP(a3),a0
        movem.w CR_MINX(a3),d0-d3
        sub.w   d0,d2
        addq.w  #1,d2
        move.w  d2,d4
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  d3,d5
        move.w  d0,d2                ; screen destination
        move.w  d1,d3
        sub.w   CR_ORGX(a3),d0       ; source: backup
        sub.w   CR_ORGY(a3),d1
        move.l  a0,-(sp)
        bsr     lr_screenbm
        move.l  a0,a1
        move.l  (sp)+,a0
        moveq   #-$40,d6
        bsr     lr_blt
        move.l  ($4).w,a6
        move.l  CR_BITMAP(a3),a0
        bsr     lr_freebm
        clr.l   CR_BITMAP(a3)
        clr.b   CR_FLAGS+3(a3)
        bra.s   .pb_next
.pb_simple:
        movem.w CR_MINX(a3),d0-d3
        tst.b   LY_NEW(a4)
        bne.s   .pb_clr              ; new layer: background only
        bsr     lr_moved
        bne.s   .pb_dmg              ; moved: everything must be redrawn
        clr.l   -(sp)                ; not moved: only the previously hidden part
        move.l  sp,a2
        lea     CR_MINX(a3),a1
        bsr     rl_add
        move.l  LY_CLIPRECT(a4),a6
.pb_old:
        cmpa.w  #0,a6
        beq.s   .pb_exp
        tst.l   CR_LOBS(a6)
        bne.s   .pb_on
        lea     CR_MINX(a6),a1
        bsr     rl_sub
.pb_on:
        move.l  CR_NEXT(a6),a6
        bra.s   .pb_old
.pb_exp:
        move.l  (sp),a0
.pb_e:
        cmpa.w  #0,a0
        beq.s   .pb_efree
        movem.w RR_MINX(a0),d0-d3
        move.l  a0,-(sp)
        bsr     lr_screenbm
        bsr     lr_clear
        bsr     lr_damage
        move.l  (sp)+,a0
        move.l  RR_NEXT(a0),a0
        bra.s   .pb_e
.pb_efree:
        move.l  sp,a2
        bsr     rl_free
        addq.l  #4,sp
        bra.s   .pb_next
.pb_dmg:
        bsr     lr_damage
.pb_clr:
        bsr     lr_screenbm
        bsr     lr_clear
.pb_next:
        move.l  CR_NEXT(a3),a3
        bra     .pb_lp
.pb_r:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; lr_background(a3 = Layer_Info, a1 = deleted layer or 0, a5 = LayersBase): previously visible areas
; that no layer covers any more -> pen 0. List = old visible ClipRects of all layers (and of the
; deleted one), minus the current bounds of each layer. d6 = common BitMap, d7 = deleted layer.
lr_background:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a1,d7
        moveq   #0,d6
        clr.l   -(sp)                ; (sp) = list
        move.l  LI_TOP(a3),a4
.bg_all:
        cmpa.w  #0,a4
        beq.s   .bg_del
        bsr     .bg_add1
        move.l  LY_BACK(a4),a4
        bra.s   .bg_all
.bg_del:
        move.l  d7,a4
        cmpa.w  #0,a4
        beq.s   .bg_sub
        bsr     .bg_add1
.bg_sub:
        move.l  LI_TOP(a3),a4
.bg_s:
        cmpa.w  #0,a4
        beq.s   .bg_clear
        move.l  sp,a2
        lea     LY_MINX(a4),a1
        bsr     rl_sub
        move.l  LY_BACK(a4),a4
        bra.s   .bg_s
.bg_clear:
        tst.l   d6
        beq.s   .bg_free
        move.l  (sp),a2
.bg_c:
        cmpa.w  #0,a2
        beq.s   .bg_free
        movem.w RR_MINX(a2),d0-d3
        move.l  d6,a0
        bsr     lr_clear
        move.l  RR_NEXT(a2),a2
        bra.s   .bg_c
.bg_free:
        move.l  sp,a2
        bsr     rl_free
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a6
        rts
; .bg_add1(a4 = layer): its old visible ClipRects added to the list (cell at 4(sp) from here on).
.bg_add1:
        move.l  LY_RP(a4),a0
        move.l  rp_BitMap(a0),d6
        move.l  LY_CLIPRECT(a4),a6
.ba_lp:
        cmpa.w  #0,a6
        beq.s   .ba_r
        tst.l   CR_LOBS(a6)
        bne.s   .ba_n
        lea     CR_MINX(a6),a1
        lea     4(sp),a2
        bsr     rl_add
.ba_n:
        move.l  CR_NEXT(a6),a6
        bra.s   .ba_lp
.ba_r:
        rts
layers_end:
