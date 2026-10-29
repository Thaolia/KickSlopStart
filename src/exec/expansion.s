; src/exec/expansion.s — expansion.library 34: Zorro II autoconfig.
;
; Resident pri 110 (1st after exec, the slow RAM is already in the MemList). Its init frees the Zorro II memory space
; ($200000-$9FFFFF) and the I/O space ($E90000-$EFFFFF) in the table of 64 KB slots, then configures the chain at
; $E80000 (ConfigChain): each board read (ReadExpansionRom) receives a block of slots (first fit, I/O first
; for boards smaller than 8 slots), its address is written to it, its RAM becomes an "expansion ram" MemHeader
; (MEMF_FAST|MEMF_PUBLIC, pri 0) or its DiagArea is copied and executed; without room, the board is shut up.
; The ConfigDevs (including those of shut-up boards) are linked into eb_BoardList in chain order.
; IMPLEMENTATION track ("clean"): AutoDocs expansion.library, NDK configregs/configvars/expansionbase, spec
; docs/analysis/autoconfig-v34.md. NO ROM reading.

                include "exec.i"
                include "expansion.i"
                include "dos.i"
                include "dospkt.i"

                xref    newlist          ; lists.s

; --- expansion.library ROMTag (scanned by build_reslist) ---
                EVEN
expansion_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    expansion_romtag         ; RT_MATCHTAG = self
        dc.l    expansion_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,110  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    expansion_name           ; RT_NAME
        dc.l    expansion_name           ; RT_IDSTRING
        dc.l    expansion_inittab        ; RT_INIT -> AUTOINIT table
expansion_name:
        dc.b    "expansion.library",0
exp_ramname:
        dc.b    "expansion ram",0
exp_dosname:
        dc.b    "dos.library",0
        EVEN
expansion_inittab:
        dc.l    EXPANSIONBASE_SIZE       ; dataSize
        dc.l    expansion_vectors        ; funcTable
        dc.l    expansion_datatab        ; dataTable (InitStruct)
        dc.l    expansion_initfunc       ; initFunc
; ABSOLUTE table terminated by -1. Vector N -> LVO -6*N.
expansion_vectors:
        dc.l    exp_open                 ; 1:  LVO -6
        dc.l    exp_close                ; 2:  LVO -12
        dc.l    exp_expunge              ; 3:  LVO -18
        dc.l    exp_null                 ; 4:  LVO -24 (reserved)
        dc.l    exp_addconfigdev         ; 5:  LVO -30 AddConfigDev(cd a0)
        dc.l    exp_addram               ; 6:  LVO -36 (private) AddMemList "expansion ram"(size d0, attr d1, base a0)
        dc.l    exp_allocboardmem        ; 7:  LVO -42 AllocBoardMem(slotSpec d0)
        dc.l    exp_allocconfigdev       ; 8:  LVO -48 AllocConfigDev()
        dc.l    exp_allocexpmem          ; 9:  LVO -54 AllocExpansionMem(numSlots d0, startSlot d1)
        dc.l    exp_configboard          ; 10: LVO -60 ConfigBoard(board a0, cd a1)
        dc.l    exp_configchain          ; 11: LVO -66 ConfigChain(baseAddr a0)
        dc.l    exp_findconfigdev        ; 12: LVO -72 FindConfigDev(old a0, manu d0, prod d1)
        dc.l    exp_freeboardmem         ; 13: LVO -78 FreeBoardMem(startSlot d0, slotSpec d1)
        dc.l    exp_freeconfigdev        ; 14: LVO -84 FreeConfigDev(cd a0)
        dc.l    exp_freeexpmem           ; 15: LVO -90 FreeExpansionMem(startSlot d0, numSlots d1)
        dc.l    exp_readbyte             ; 16: LVO -96 ReadExpansionByte(board a0, offset d0)
        dc.l    exp_readrom              ; 17: LVO -102 ReadExpansionRom(board a0, cd a1)
        dc.l    exp_remconfigdev         ; 18: LVO -108 RemConfigDev(cd a0)
        dc.l    exp_writebyte            ; 19: LVO -114 WriteExpansionByte(board a0, offset d0, byte d1)
        dc.l    exp_obtainbinding        ; 20: LVO -120 ObtainConfigBinding()
        dc.l    exp_releasebinding       ; 21: LVO -126 ReleaseConfigBinding()
        dc.l    exp_setbinding           ; 22: LVO -132 SetCurrentBinding(binding a0, size d0)
        dc.l    exp_getbinding           ; 23: LVO -138 GetCurrentBinding(binding a0, size d0) -> 16
        dc.l    exp_makedosnode          ; 24: LVO -144 MakeDosNode(parmPacket a0)
        dc.l    exp_adddosnode           ; 25: LVO -150 AddDosNode(bootPri d0, flags d1, dosNode a0)
        dc.l    -1
expansion_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)  ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN
; er_Type & 7 -> number of 64 KB slots, then start slot of the general search (8 MB and 4 MB: $20).
sz_slots:
        dc.b    $80,$01,$02,$04,$08,$10,$20,$40
        dc.b    $20,$00,$00,$00,$00,$00,$00,$20

exp_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
exp_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
exp_expunge:
        moveq   #0,d0               ; resident base: no expunge
        rts
exp_null:
        moveq   #0,d0
        rts

; SetCurrentBinding(binding a0, size d0): min(size, 16) bytes to the base, padded to 16 with 0s.
; GetCurrentBinding(binding a0, size d0) -> 16: min(size, 16) bytes to the buffer, then 0s up to 16 bytes
; in the buffer (as in 1.3: the buffer must be 16 bytes).
exp_setbinding:
        lea     EB_BINDING(a6),a1    ; source = argument (a0), destination = base (a1)
        bra.s   exp_cpbinding
exp_getbinding:
        lea     EB_BINDING(a6),a1
        exg     a0,a1                ; source = base (a0), destination = argument (a1)
exp_cpbinding:
        move.l  d2,-(sp)
        moveq   #CB_SIZEOF,d1
        cmp.l   d1,d0
        bls.s   .cb_n
        move.l  d1,d0
.cb_n:
        sub.l   d0,d1                ; d1 = bytes to zero
        move.l  d0,d2
        bra.s   .cb_cpe
.cb_cp:
        move.b  (a0)+,(a1)+
.cb_cpe:
        dbra    d2,.cb_cp
        bra.s   .cb_ze
.cb_z:
        clr.b   (a1)+
.cb_ze:
        dbra    d1,.cb_z
        move.l  (sp)+,d2
        moveq   #CB_SIZEOF,d0
        rts

exp_obtainbinding:
        lea     EB_BINDSEM(a6),a0
        move.l  a6,-(sp)
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  (sp)+,a6
        rts
exp_releasebinding:
        lea     EB_BINDSEM(a6),a0
        move.l  a6,-(sp)
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        move.l  (sp)+,a6
        rts

; AddConfigDev(cd a0): at the tail of eb_BoardList, under Forbid.
exp_addconfigdev:
                ifne    EXP_NO_ENQUEUE
        rts                         ; RED EXP_NO_ENQUEUE: adds nothing -> FindConfigDev will fail
                endc
        move.l  a6,-(sp)
        move.l  a0,a1
        lea     EB_BOARDLIST(a6),a0
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_FORBID(a6)
        jsr     LVO_ADDTAIL(a6)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts
; RemConfigDev(cd a0): removes the ConfigDev from its list, under Forbid.
exp_remconfigdev:
        move.l  a6,-(sp)
        move.l  a0,a1
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; AllocConfigDev() -> d0 = ConfigDev* | 0 (zeroed).
exp_allocconfigdev:
        move.l  a6,-(sp)
        move.l  EB_EXECBASE(a6),a6
        moveq   #CD_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        rts
; FreeConfigDev(cd a0): does not remove it from the list (the caller does RemConfigDev beforehand).
exp_freeconfigdev:
        move.l  a6,-(sp)
        move.l  a0,a1
        moveq   #CD_SIZEOF,d0
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
        rts

; FindConfigDev(oldConfigDev a0, manufacturer d0, product d1) -> d0 = ConfigDev* | 0. old = 0: from the head, otherwise
; from the successor of old. -1 (long) = wildcard; otherwise comparison on the er_Manufacturer word / er_Product byte.
exp_findconfigdev:
        movem.l d2/d3/a2,-(sp)
        move.l  d0,d2
        move.l  d1,d3
        move.l  a0,d0
        bne.s   .fcd_fromsucc
        move.l  EB_BOARDLIST(a6),a2  ; lh_Head
        bra.s   .fcd_loop
.fcd_fromsucc:
        move.l  (a0),a2
.fcd_loop:
        move.l  (a2),d0              ; null Succ: a2 = tail sentinel -> end
        beq.s   .fcd_none
        cmp.l   #-1,d2
        beq.s   .fcd_chkprod
        cmp.w   ER_MANUFACTURER(a2),d2
        bne.s   .fcd_next
.fcd_chkprod:
        cmp.l   #-1,d3
        beq.s   .fcd_hit
        cmp.b   ER_PRODUCT(a2),d3
        bne.s   .fcd_next
.fcd_hit:
        move.l  a2,d0
        bra.s   .fcd_ret
.fcd_next:
        move.l  (a2),a2
        bra.s   .fcd_loop
.fcd_none:
        moveq   #0,d0
.fcd_ret:
        movem.l (sp)+,d2/d3/a2
        rts

; ReadExpansionByte(board a0, offset d0) -> d0: logical byte n carries its high nibble in the high nibble of
; board+4n, its low nibble in the high nibble of board+4n+2. Without inversion.
exp_readbyte:
        and.l   #$FF,d0
        lsl.w   #2,d0
        move.b  0(a0,d0.l),d1
        and.b   #$F0,d1
        move.b  2(a0,d0.l),d0
        lsr.b   #4,d0
        or.b    d1,d0
        and.l   #$FF,d0
        rts
; WriteExpansionByte(board a0, offset d0, byte d1) -> 0: low nibble at board+4n+2, then high nibble at board+4n
; (last: writing the high nibble of the address register is what makes the board take its address).
exp_writebyte:
        and.l   #$FF,d0
        lsl.w   #2,d0
        move.l  d1,a1
        lsl.b   #4,d1
        move.b  d1,2(a0,d0.l)
        move.l  a1,d1
        move.b  d1,0(a0,d0.l)
        moveq   #0,d0
        rts

; ReadExpansionRom(board a0, cd a1) -> d0 = 0 | EE_NOMEMORY (no board, invalid or unstable ROM). 17 logical
; bytes stored from cd_Rom: er_Type as is, the following ones inverted. Valid if er_Flags & $3F = 0,
; er_Reserved03 = 0, er_Manufacturer neither 0 nor $FFFF, and if 11 rereads of the first 16 bytes agree.
exp_readrom:
        movem.l d2-d4/a2-a3,-(sp)
        move.l  a0,a2
        lea     CD_ROM(a1),a3
        moveq   #0,d2
.rr_lp:
        bsr.s   rr_byte
        move.b  d0,0(a3,d2.w)
        addq.w  #1,d2
        cmp.w   #ER_ROMBYTES,d2
        blo.s   .rr_lp
        moveq   #EE_NOMEMORY,d4
        moveq   #$3F,d0
        and.b   ER_FLAGS-CD_ROM(a3),d0
        bne.s   .rr_ret
        tst.b   ER_RESERVED03-CD_ROM(a3)
        bne.s   .rr_ret
        move.w  ER_MANUFACTURER-CD_ROM(a3),d0
        beq.s   .rr_ret
        cmp.w   #$FFFF,d0
        beq.s   .rr_ret
        moveq   #ER_REREADS-1,d3
.rr_again:
        moveq   #0,d2
.rr_cmp:
        bsr.s   rr_byte
        cmp.b   0(a3,d2.w),d0
        bne.s   .rr_ret
        addq.w  #1,d2
        cmp.w   #16,d2
        blo.s   .rr_cmp
        dbra    d3,.rr_again
        moveq   #0,d4
.rr_ret:
        move.l  d4,d0
        movem.l (sp)+,d2-d4/a2-a3
        rts
; rr_byte(a2 = board, d2.w = index) -> d0.b = logical byte, inverted except index 0. Clobbers d0/d1/a0.
rr_byte:
        move.l  a2,a0
        moveq   #0,d0
        move.w  d2,d0
        bsr     exp_readbyte
        tst.w   d2
        beq.s   .rb_r
        not.b   d0
.rb_r:
        rts

; AllocExpansionMem(numSlots d0, startSlot d1) -> d0 = first slot | -1. Fewer than 8 slots: try in the I/O space
; [$E8, $F0) in steps of numSlots; then in [start, 256) in steps of numSlots. First entirely free block: taken.
exp_allocexpmem:
        movem.l d2/d4,-(sp)
        move.l  d0,d2
        beq.s   .ae_fail
        add.l   d1,d0
        cmp.l   #256,d0
        bhi.s   .ae_fail
        move.l  d1,-(sp)
        cmp.l   #7,d2
        bhi.s   .ae_gen
        move.l  #E_IOSLOT_LO,d4
        move.l  #E_IOSLOT_HI,d1
        bsr.s   ae_scan
        tst.l   d0
        bpl.s   .ae_got
.ae_gen:
        move.l  (sp),d4
        move.l  #256,d1
        bsr.s   ae_scan
.ae_got:
        addq.l  #4,sp
        bra.s   .ae_ret
.ae_fail:
        moveq   #-1,d0
.ae_ret:
        movem.l (sp)+,d2/d4
        rts
; ae_scan(d2 = slots, d4 = first candidate, d1 = exclusive end) -> d0 = slot | -1. Clobbers d0/d4/a0.
ae_scan:
        move.l  d4,d0
        add.l   d2,d0
        cmp.l   d1,d0
        bhi.s   .sc_none
        lea     EB_ALLOCTABLE(a6,d4.l),a0
        move.l  d2,d0
        subq.l  #1,d0
.sc_chk:
        tst.b   (a0)+
        beq.s   .sc_next
        dbra    d0,.sc_chk
        lea     EB_ALLOCTABLE(a6,d4.l),a0
        move.l  d2,d0
        subq.l  #1,d0
.sc_mark:
        clr.b   (a0)+
        dbra    d0,.sc_mark
        move.l  d4,d0
        rts
.sc_next:
        add.l   d2,d4
        bra.s   ae_scan
.sc_none:
        moveq   #-1,d0
        rts

; FreeExpansionMem(startSlot d0, numSlots d1): slots made free. Outside the table, or slot already free: Alert
; AN_BADEXPFREE and stop (the previous slots remain freed).
exp_freeexpmem:
        move.l  d0,a0
        add.l   d1,d0
        cmp.l   #256,d0
        bhi.s   .fe_bad
        add.l   a6,a0
        lea     EB_ALLOCTABLE(a0),a0
        bra.s   .fe_e
.fe_lp:
        tst.b   (a0)
        bne.s   .fe_bad
        st      (a0)+
.fe_e:
        subq.l  #1,d1
        bpl.s   .fe_lp
        rts
.fe_bad:
        movem.l d7/a6,-(sp)
        move.l  #AN_BADEXPFREE,d7
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_ALERT(a6)
        movem.l (sp)+,d7/a6
        rts

; AllocBoardMem(slotSpec d0) -> d0 = slot | -1; FreeBoardMem(startSlot d0, slotSpec d1). slotSpec = er_Type & 7.
exp_allocboardmem:
        and.l   #7,d0
        lea     sz_slots(pc),a0
        moveq   #0,d1
        move.b  8(a0,d0.w),d1
        move.b  0(a0,d0.w),d0
        and.l   #$FF,d0
        bra     exp_allocexpmem
exp_freeboardmem:
        and.l   #7,d1
        lea     sz_slots(pc),a0
        move.b  0(a0,d1.w),d1
        and.l   #$FF,d1
        bra.s   exp_freeexpmem

; ConfigBoard(board a0, cd a1) -> d0 = 0 | EE_NOEXPANSION. Clogged chain (EBB_CLOGGED): nothing. Room found: fields
; of the ConfigDev, CDF_CONFIGME, address written to the board, then its RAM added (ERTF_MEMLIST) or its DiagArea
; processed (ERTF_DIAGVALID). Without room: board shut up (CDF_SHUTUP, EBB_SHORTMEM); a board that refuses shut-up
; (ERFF_NOSHUTUP) stays at $E80000 and clogs the chain (EBB_CLOGGED, slot -1) — without post-configuration here: in
; 1.3 it would run at address -1, which can only corrupt memory.
exp_configboard:
        movem.l d2/a2-a3,-(sp)
        move.l  a0,a2
        move.l  a1,a3
        moveq   #0,d0
        btst    #EBB_CLOGGED,EB_FLAGS(a6)
        bne.s   .cb_ret
        moveq   #7,d2
        and.b   ER_TYPE(a3),d2
        move.l  d2,d0
        bsr.s   exp_allocboardmem
        tst.l   d0
        bmi.s   .cb_full
        bsr.s   cb_fill
        bset    #CDB_CONFIGME,CD_FLAGS(a3)
        move.l  d0,d1
        move.l  a2,a0
        moveq   #EC_BASEADDR,d0
        bsr     exp_writebyte
        bsr.s   cb_post
        moveq   #0,d0
        bra.s   .cb_ret
.cb_full:
        btst    #ERFB_NOSHUTUP,ER_FLAGS(a3)
        bne.s   .cb_clog
        move.l  a2,a0
        moveq   #EC_SHUTUP,d0
        moveq   #0,d1
        bsr     exp_writebyte
        bset    #CDB_SHUTUP,CD_FLAGS(a3)
        bset    #EBB_SHORTMEM,EB_FLAGS(a6)
        moveq   #EE_NOEXPANSION,d0
        bra.s   .cb_ret
.cb_clog:
        bset    #EBB_CLOGGED,EB_FLAGS(a6)
        bsr.s   cb_fill              ; d0 = -1
        move.l  a2,a0
        moveq   #EC_BASEADDR,d0
        move.l  #E_IOSLOT_LO,d1
        bsr     exp_writebyte
.cb_ret:
        movem.l (sp)+,d2/a2-a3
        rts
; cb_fill(d0 = slot, d2 = slotSpec, a3 = cd): cd_SlotAddr/BoardAddr/SlotSize/BoardSize. Preserves d0.
cb_fill:
        move.w  d0,CD_SLOTADDR(a3)
        move.l  d0,d1
        swap    d1
        clr.w   d1
        move.l  d1,CD_BOARDADDR(a3)
        lea     sz_slots(pc),a0
        moveq   #0,d1
        move.b  0(a0,d2.w),d1
        move.w  d1,CD_SLOTSIZE(a3)
        swap    d1
        move.l  d1,CD_BOARDSIZE(a3)
        rts
; cb_post(a3 = configured cd, a6 = ExpansionBase): board RAM added, or DiagArea (board without RAM).
cb_post:
        btst    #ERTB_MEMLIST,ER_TYPE(a3)
        beq.s   .cp_diag
        move.l  CD_BOARDSIZE(a3),d0
        moveq   #MEMF_PUBLIC|MEMF_FAST,d1
        move.l  CD_BOARDADDR(a3),a0
        bra.s   exp_addram
.cp_diag:
        btst    #ERTB_DIAGVALID,ER_TYPE(a3)
        bne.s   exp_diag
        rts

; (LVO -36, private) (size d0, attributes d1, base a0): AddMemList(size, attributes, pri 0, base, "expansion ram").
exp_addram:
        movem.l d2/a6,-(sp)
        moveq   #0,d2
        lea     exp_ramname(pc),a1
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_ADDMEMLIST(a6)
        movem.l (sp)+,d2/a6
        rts

; exp_diag(a3 = configured cd, a6 = ExpansionBase): DiagArea at cd_BoardAddr + er_InitDiagVec, taken into account if
; (da_Config & $30) = DAC_CONFIGTIME and the bus width is known; copied (da_Size bytes, according to the width) into
; an AllocMem(da_Size, 0) stored in er_Reserved0c; DiagPoint (if it exists) called with A0 = board, A2 = copy,
; A3 = ConfigDev, A5 = ExpansionBase, A6 = ExecBase; a return of 0 frees the copy (er_Reserved0c = 0).
exp_diag:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        moveq   #0,d0
        move.w  ER_INITDIAGVEC(a3),d0
        beq     .dg_ret
        move.l  CD_BOARDADDR(a3),a4
        add.l   d0,a4                ; a4 = DiagArea in the board
        move.b  DA_CONFIG(a4),d4
        moveq   #DAC_BOOTTIME,d0
        and.b   d4,d0
        cmp.b   #DAC_CONFIGTIME,d0
        bne     .dg_ret
        and.b   #DAC_BUSWIDTH,d4
        cmp.b   #DAC_BUSWIDTH,d4
        beq.s   .dg_ret
        lea     -DA_HDRSIZE(sp),sp   ; header copied according to the width
        move.l  a4,a0
        move.l  sp,a1
        moveq   #DA_HDRSIZE,d0
        bsr.s   dg_copy
        moveq   #0,d5
        move.w  DA_SIZE(sp),d5
        moveq   #0,d6
        move.w  DA_DIAGPOINT(sp),d6
        lea     DA_HDRSIZE(sp),sp
        tst.l   d5
        beq.s   .dg_ret
        move.l  d5,d0
        moveq   #0,d1
        move.l  EB_EXECBASE(a5),a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .dg_ret
        move.l  d0,a2
        move.l  a4,a0
        move.l  a2,a1
        move.l  d5,d0
        bsr.s   dg_copy
        move.l  a2,ER_RESERVED0C(a3)
        tst.l   d6
        beq.s   .dg_ret
        lea     0(a2,d6.l),a1
        move.l  CD_BOARDADDR(a3),a0
        movem.l d5/a2-a3/a5,-(sp)    ; the board's code may clobber everything
        move.l  EB_EXECBASE(a5),a6
        jsr     (a1)
        movem.l (sp)+,d5/a2-a3/a5
        tst.l   d0
        bne.s   .dg_ret
        move.l  a2,a1
        move.l  d5,d0
        move.l  EB_EXECBASE(a5),a6
        jsr     LVO_FREEMEM(a6)
        clr.l   ER_RESERVED0C(a3)
.dg_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts
; dg_copy(a0 = DiagArea in the board, a1 = destination, d0 = bytes, d4 = width): WORDWIDE contiguous; BYTEWIDE one
; byte out of two; NIBBLEWIDE byte = high nibbles of +0 and +2, step 4. a5 = ExpansionBase. Clobbers d0/d1/d7/a0/a1.
dg_copy:
        cmp.b   #DAC_WORDWIDE,d4
        beq.s   .dc_word
        subq.l  #1,d0
        bmi.s   .dc_ret
        cmp.b   #DAC_BYTEWIDE,d4
        beq.s   .dc_byte
.dc_nib:
        move.b  (a0),d1
        and.b   #$F0,d1
        move.b  2(a0),d7
        lsr.b   #4,d7
        or.b    d7,d1
        move.b  d1,(a1)+
        addq.l  #4,a0
        dbra    d0,.dc_nib
        rts
.dc_byte:
        move.b  (a0),(a1)+
        addq.l  #2,a0
        dbra    d0,.dc_byte
.dc_ret:
        rts
.dc_word:
        move.l  a6,-(sp)
        move.l  EB_EXECBASE(a5),a6
        jsr     LVO_COPYMEM(a6)
        move.l  (sp)+,a6
        rts

; ConfigChain(baseAddr a0) -> d0 = 0 | EE_NOMEMORY (no more memory for a ConfigDev). As long as a valid board
; answers at baseAddr: ConfigBoard; configured or shut up -> AddConfigDev; otherwise end of chain.
exp_configchain:
        movem.l a2-a3,-(sp)
        move.l  a0,a2
.cc_lp:
        moveq   #0,d0
        btst    #EBB_CLOGGED,EB_FLAGS(a6)
        bne.s   .cc_ret
        bsr     exp_allocconfigdev
        tst.l   d0
        beq.s   .cc_nomem
        move.l  d0,a3
        move.l  a2,a0
        move.l  a3,a1
        bsr     exp_readrom
        tst.l   d0
        bne.s   .cc_end
        move.l  a2,a0
        move.l  a3,a1
        bsr     exp_configboard
        tst.l   d0
        beq.s   .cc_add
        cmp.l   #EE_NOEXPANSION,d0
        bne.s   .cc_end
.cc_add:
        move.l  a3,a0
        bsr     exp_addconfigdev
        bra.s   .cc_lp
.cc_end:
        move.l  a3,a0
        bsr     exp_freeconfigdev
        moveq   #0,d0
        bra.s   .cc_ret
.cc_nomem:
        moveq   #EE_NOMEMORY,d0
.cc_ret:
        movem.l (sp)+,a2-a3
        rts

; MakeDosNode(parmPacket a0) -> d0 = DeviceNode | 0. parmPacket: DOS name (C), exec device name (C), unit,
; OpenDevice flags, then the environment (de_TableSize first). Five PUBLIC|CLEAR blocks (AllocEntry): DeviceNode,
; FileSysStartupMsg, copy of the environment ((de_TableSize + 1) longs), BSTR of the DOS name, BSTR of the device name.
; dn_StackSize = 600, dn_Priority = 10.
MD_ML           EQU 0                ; template MemList on the stack (5 entries)
MD_SIZE         EQU ML_ME+5*8
exp_makedosnode:
        movem.l d2-d3/a2-a4/a6,-(sp)
        lea     -MD_SIZE(sp),sp
        move.l  a0,a2
        move.w  #5,ML_NUMENTRIES(sp)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        lea     ML_ME(sp),a0
        move.l  d1,(a0)+
        move.l  #DN_SIZEOF,(a0)+
        move.l  d1,(a0)+
        move.l  #FSSM_SIZEOF,(a0)+
        move.l  d1,(a0)+
        move.l  16(a2),d0            ; de_TableSize
        addq.l  #1,d0
        lsl.l   #2,d0
        move.l  d0,d3                ; d3 = environment bytes
        move.l  d0,(a0)+
        move.l  d1,(a0)+
        move.l  (a2),a1
        bsr     md_bstrsize
        move.l  d0,(a0)+
        move.l  d1,(a0)+
        move.l  4(a2),a1
        bsr     md_bstrsize
        move.l  d0,(a0)+
        move.l  sp,a0
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_ALLOCENTRY(a6)
        tst.l   d0
        bmi.s   .md_fail
        move.l  d0,a4
        lea     ML_ME(a4),a4         ; a4 -> me_Addr of the 5 blocks
        move.l  (a4),a3              ; a3 = DeviceNode
        move.l  #600,DN_STACKSIZE(a3)
        move.l  #10,DN_PRIORITY(a3)
        move.l  8(a4),a1             ; FileSysStartupMsg
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_STARTUP(a3)
        move.l  8(a2),FSSM_UNIT(a1)
        move.l  12(a2),FSSM_FLAGS(a1)
        move.l  16(a4),d0            ; environment
        move.l  d0,d2
        lsr.l   #2,d0
        move.l  d0,FSSM_ENVIRON(a1)
        move.l  32(a4),d0            ; BSTR of the device name
        move.l  d0,a0
        lsr.l   #2,d0
        move.l  d0,FSSM_DEVICE(a1)
        move.l  4(a2),a1
        bsr.s   md_bstr
        move.l  24(a4),d0            ; BSTR of the DOS name
        move.l  d0,a0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a3)
        move.l  (a2),a1
        bsr.s   md_bstr
        lea     16(a2),a0
        move.l  d2,a1
        move.l  d3,d0
        jsr     LVO_COPYMEM(a6)
        move.l  a3,d0
        bra.s   .md_ret
.md_fail:
        moveq   #0,d0
.md_ret:
        lea     MD_SIZE(sp),sp
        movem.l (sp)+,d2-d3/a2-a4/a6
        rts
; md_bstrsize(a1 = C string) -> d0 = length + 2 (length byte, characters, NUL). Preserves a0/d1.
md_bstrsize:
        moveq   #2,d0
.bs_lp:
        tst.b   (a1)+
        beq.s   .bs_r
        addq.l  #1,d0
        bra.s   .bs_lp
.bs_r:
        rts
; md_bstr(a0 = destination, a1 = C string): BSTR (length byte then characters; block already zeroed).
md_bstr:
        move.l  a0,d1
        addq.l  #1,a0
.mb_lp:
        move.b  (a1)+,(a0)+
        bne.s   .mb_lp
        sub.l   d1,a0
        subq.l  #2,a0
        move.l  d1,a1
        move.l  a0,d1
        move.b  d1,(a1)
        rts

; AddDosNode(bootPri d0, flags d1, dosNode a0) -> d0 = 1 | 0. dos.library present: the DeviceNode enters the list
; of DOS devices (DosInfo->di_DevInfo, under Forbid). Otherwise: BootNode (ln_Pri = bootPri, bn_Flags = flags,
; bn_DeviceNode, ln_Name = name of the DeviceNode) inserted by priority into eb_MountList, mounted later.
exp_adddosnode:
        movem.l d2-d3/a2-a3/a6,-(sp)
        move.l  a0,d2
        beq.s   .ad_fail
        move.l  a0,a2
        move.l  d0,d2
        move.l  d1,d3
        move.l  a6,a3
        move.l  EB_EXECBASE(a6),a6
        lea     exp_dosname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   .ad_boot
        move.l  d0,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  (sp),a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_INFO(a0),d0
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  DI_DEVINFO(a0),DN_NEXT(a2)
        move.l  a2,d0
        lsr.l   #2,d0
        move.l  d0,DI_DEVINFO(a0)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a1
        jsr     LVO_CLOSELIBRARY(a6)
        bra.s   .ad_ok
.ad_boot:
        moveq   #BN_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ad_fail
        move.l  d0,a1
        move.b  d2,LN_PRI(a1)
        move.w  d3,BN_FLAGS(a1)
        move.l  a2,BN_DEVICENODE(a1)
        move.l  DN_NAME(a2),d0
        lsl.l   #2,d0
        addq.l  #1,d0
        move.l  d0,LN_NAME(a1)
        lea     EB_MOUNTLIST(a3),a0
        jsr     LVO_ENQUEUE(a6)
.ad_ok:
        moveq   #1,d0
        bra.s   .ad_ret
.ad_fail:
        moveq   #0,d0
.ad_ret:
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

; initFunc (d0 = base, a0 = segList, a6 = ExecBase) -> d0 = base: frees the Zorro II memory space (slots $20-$9F)
; and the I/O space (slots $E9-$EF; $E8 = configuration address, never free), then configures the chain at $E80000.
expansion_initfunc:
        movem.l d2/a2/a6,-(sp)
        move.l  d0,a2
        lea     expansion_name(pc),a1
        move.l  a1,LN_NAME(a2)
        move.l  a6,EB_EXECBASE(a2)
        move.l  a0,EB_SEGLIST(a2)
        lea     EB_BINDSEM(a2),a0
        jsr     LVO_INITSEMAPHORE(a6)
        move.l  a2,a6
        moveq   #$20,d0
        move.l  #$80,d1
        bsr     exp_freeexpmem
        move.l  #E_IOSLOT_LO+1,d0
        moveq   #E_IOSLOT_HI-E_IOSLOT_LO-1,d1
        bsr     exp_freeexpmem
        lea     EB_BOARDLIST(a6),a1
        jsr     newlist
        lea     EB_MOUNTLIST(a6),a1
        jsr     newlist
        lea     $E80000,a0
        bsr     exp_configchain
        move.l  a6,d0
        movem.l (sp)+,d2/a2/a6
        rts

        EVEN
expansion_end:
