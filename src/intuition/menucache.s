; SPDX-License-Identifier: MIT
; Session-local surfaces for plain text menus. Exact byte snapshots validate all pixel-affecting source data;
; changed data or unsupported renderings use the regular renderer. No application pointers own cached storage.
                include "exec.i"
                include "graphics.i"
                include "intuition.i"
                xdef mn_cache_lookup,mn_cache_store,mn_cache_dispose,mn_cache_clear
                xref mn_boxfree
NC_NEXT         EQU 0
NC_MENU         EQU 4
NC_RP           EQU 8
NC_BYTES        EQU 12
NC_KEY          EQU 16
CK_MODE         EQU 0
CK_PTR          EQU 2
CK_LIMIT        EQU 6
CK_N            EQU 10
CK_OK           EQU 14
CK_SIZE         EQU 16
KEY_LIMIT       EQU 16384

; Lookup(a2 = Menu, a4 = Screen, a5 = IntuitionBase) -> d0 = staged RastPort | 0.
mn_cache_lookup:
        movem.l d2-d7/a2-a6,-(sp)
        lea     IB_MENUCACHE(a5),a6
.loop:
        move.l  (a6),d0
        beq.s   .ret
        move.l  d0,a3
        cmp.l   NC_MENU(a3),a2
        beq.s   .found
        move.l  a3,a6
        bra.s   .loop
.found:
        move.l  NC_BYTES(a3),d1
        sub.l   #NC_KEY,d1
        lea     NC_KEY(a3),a0
        moveq   #2,d0
        bsr     mc_key
        tst.l   d0
        beq.s   .stale
        move.l  NC_RP(a3),d0
        bra.s   .ret
.stale:
        move.l  NC_NEXT(a3),(a6)
        bsr     mc_free
        moveq   #0,d0
.ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Store(a2 = Menu, a3 = staged RastPort, a4 = Screen, a5 = IntuitionBase). Failure keeps ordinary ownership.
mn_cache_store:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  IB_MENUCACHE(a5),a6
.exists:
        cmpa.w  #0,a6
        beq.s   .new
        cmp.l   NC_RP(a6),a3
        beq     .ret
        move.l  NC_NEXT(a6),a6
        bra.s   .exists
.new:
        moveq   #0,d0
        move.l  #KEY_LIMIT,d1
        suba.l  a0,a0
        bsr     mc_key
        tst.l   d0
        beq.s   .ret
        move.l  d0,d7
        add.l   #NC_KEY,d0
        moveq   #MEMF_PUBLIC,d1
        move.l  4.w,a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ret
        move.l  d0,a6
        move.l  a2,NC_MENU(a6)
        move.l  a3,NC_RP(a6)
        move.l  d7,d0
        add.l   #NC_KEY,d0
        move.l  d0,NC_BYTES(a6)
        lea     NC_KEY(a6),a0
        move.l  d7,d1
        moveq   #1,d0
        bsr     mc_key
        tst.l   d0
        beq.s   .discard
        move.l  IB_MENUCACHE(a5),NC_NEXT(a6)
        move.l  a6,IB_MENUCACHE(a5)
        bra.s   .ret
.discard:
        move.l  NC_BYTES(a6),d0
        move.l  a6,a1
        move.l  4.w,a6
        jsr     LVO_FREEMEM(a6)
.ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Dispose(a3 = surface): free only when the session cache did not retain it.
mn_cache_dispose:
        movem.l d0/a0,-(sp)
        move.l  IB_MENUCACHE(a5),a0
.loop:
        cmpa.w  #0,a0
        beq.s   .free
        cmp.l   NC_RP(a0),a3
        beq.s   .ret
        move.l  NC_NEXT(a0),a0
        bra.s   .loop
.free:
        jsr     mn_boxfree
.ret:
        movem.l (sp)+,d0/a0
        rts

mn_cache_clear:
        movem.l d2/a3,-(sp)
        move.l  IB_MENUCACHE(a5),a3
        clr.l   IB_MENUCACHE(a5)
.loop:
        cmpa.w  #0,a3
        beq.s   .ret
        move.l  NC_NEXT(a3),d2
        bsr.s   mc_free
        move.l  d2,a3
        bra.s   .loop
.ret:
        movem.l (sp)+,d2/a3
        rts
mc_free:
        movem.l d0-d1/a1/a3/a6,-(sp)
        move.l  NC_BYTES(a3),d0
        move.l  a3,a1
        move.l  NC_RP(a3),a3
        movem.l d0/a1,-(sp)
        jsr     mn_boxfree
        movem.l (sp)+,d0/a1
        move.l  4.w,a6
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,d0-d1/a1/a3/a6
        rts

; Serialize/count/compare one canonical rendering key. d0 = mode (0 count, 1 copy, 2 compare), d1 = capacity,
; a0 = key bytes; a2/a4/a5 = menu/screen/IntuitionBase. Return byte count on success, zero otherwise.
mc_key:
        movem.l d2-d7/a2-a6,-(sp)
        lea     -CK_SIZE(sp),sp
        move.l  sp,a3
        move.w  d0,CK_MODE(a3)
        move.l  a0,CK_PTR(a3)
        move.l  d1,CK_LIMIT(a3)
        clr.l   CK_N(a3)
        st      CK_OK(a3)
        lea     SC_LEFTEDGE(a4),a0
        moveq   #8,d0
        bsr     mc_bytes
        lea     SC_BARHEIGHT(a4),a0
        moveq   #5,d0
        bsr     mc_bytes
        lea     SC_VIEWPORT+vp_Modes(a4),a0
        moveq   #2,d0
        bsr     mc_bytes
        lea     SC_BITMAP+bm_Depth(a4),a0
        moveq   #1,d0
        bsr     mc_bytes
        lea     SC_RASTPORT+rp_AlgoStyle(a4),a0
        moveq   #1,d0
        bsr     mc_bytes
        move.l  IB_MENUWIN(a5),a0
        cmpa.w  #0,a0
        beq     .bad
        lea     WD_DETAILPEN(a0),a0
        moveq   #2,d0
        bsr     mc_bytes
        move.l  SC_RASTPORT+rp_Font(a4),a6
        cmpa.w  #0,a6
        beq     .bad
        move.l  a6,a0
        moveq   #tf_SIZEOF,d0
        bsr     mc_bytes
        moveq   #0,d2
        move.b  tf_HiChar(a6),d2
        moveq   #0,d0
        move.b  tf_LoChar(a6),d0
        sub.w   d0,d2
        bmi     .bad
        addq.w  #2,d2
        moveq   #0,d0
        move.w  tf_Modulo(a6),d0
        mulu    tf_YSize(a6),d0
        beq     .bad
        cmp.l   #8192,d0
        bhi     .bad
        move.l  tf_CharData(a6),a0
        cmpa.w  #0,a0
        beq     .bad
        bsr     mc_bytes
        move.l  tf_CharLoc(a6),a0
        cmpa.w  #0,a0
        beq     .bad
        move.l  d2,d0
        lsl.l   #2,d0
        bsr     mc_bytes
        move.l  tf_CharSpace(a6),d0
        beq.s   .kern
        move.l  d0,a0
        move.l  d2,d0
        add.l   d0,d0
        bsr     mc_bytes
.kern:
        move.l  tf_CharKern(a6),d0
        beq.s   .menu
        move.l  d0,a0
        move.l  d2,d0
        add.l   d0,d0
        bsr     mc_bytes
.menu:
        move.l  a2,a0
        moveq   #12,d0
        bsr     mc_bytes
        move.w  MU_FLAGS(a2),d0
        and.w   #MENUENABLED,d0
        move.w  d0,-(sp)
        move.l  sp,a0
        moveq   #2,d0
        bsr     mc_bytes
        addq.l  #2,sp
        lea     MU_MENUNAME(a2),a0
        moveq   #16,d0
        bsr     mc_bytes
        move.l  MU_FIRSTITEM(a2),a2
.item:
        tst.b   CK_OK(a3)
        beq     .done
        cmpa.w  #0,a2
        beq     .done
        move.w  MI_FLAGS(a2),d0
        and.w   #7,d0               ; ITEMTEXT, CHECKIT, COMMSEQ
        cmp.w   #ITEMTEXT,d0
        bne     .bad
        tst.l   MI_SUBITEM(a2)
        bne     .bad
        move.l  MI_ITEMFILL(a2),d0
        beq     .bad
        move.l  d0,a6
        tst.l   IT_ITEXTFONT(a6)
        bne     .bad
        tst.l   IT_NEXTTEXT(a6)
        bne     .bad
        move.l  a2,a0
        moveq   #12,d0
        bsr     mc_bytes
        move.w  MI_FLAGS(a2),d0
        and.w   #$8fff,d0            ; exclude HIGHITEM, ISDRAWN and MENUTOGGLED working flags
        move.w  d0,-(sp)
        move.l  sp,a0
        moveq   #2,d0
        bsr     mc_bytes
        addq.l  #2,sp
        lea     14(a2),a0
        moveq   #18,d0
        bsr     mc_bytes
        move.l  a6,a0
        moveq   #20,d0
        bsr     mc_bytes
        move.l  IT_ITEXT(a6),d0
        beq.s   .next
        move.l  d0,a0
        move.l  a0,a1
        moveq   #0,d0
.length:
        addq.l  #1,d0
        cmp.l   #2048,d0
        bhi.s   .bad
        tst.b   (a1)+
        bne.s   .length
        bsr     mc_bytes
.next:
        move.l  MI_NEXTITEM(a2),a2
        bra     .item
.bad:
        sf      CK_OK(a3)
.done:
        moveq   #0,d0
        tst.b   CK_OK(a3)
        beq.s   .ret
        move.l  CK_N(a3),d0
        tst.w   CK_MODE(a3)
        beq.s   .ret
        cmp.l   CK_LIMIT(a3),d0
        beq.s   .ret
        moveq   #0,d0
.ret:
        lea     CK_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Consume a0/d0 bytes. Length/capacity is checked before any cache read or write.
mc_bytes:
        tst.b   CK_OK(a3)
        beq.s   .ret
        add.l   d0,CK_N(a3)
        move.l  CK_N(a3),d1
        cmp.l   CK_LIMIT(a3),d1
        bhi.s   .bad
        tst.w   CK_MODE(a3)
        beq.s   .ret
        move.l  CK_PTR(a3),a1
        subq.l  #1,d0
        bmi.s   .ret
        cmp.w   #1,CK_MODE(a3)
        bne.s   .compare
.copy:
        move.b  (a0)+,(a1)+
        subq.l  #1,d0
        bpl.s   .copy
        bra.s   .save
.compare:
        cmpm.b  (a0)+,(a1)+
        bne.s   .bad
        subq.l  #1,d0
        bpl.s   .compare
.save:
        move.l  a1,CK_PTR(a3)
.ret:
        rts
.bad:
        sf      CK_OK(a3)
        rts
