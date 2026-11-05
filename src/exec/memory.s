; src/exec/memory.s — exec.library memory: Allocate/Deallocate, AllocMem/FreeMem/AvailMem/AllocAbs/TypeOfMem,
; AddMemList, AllocEntry/FreeEntry; init_memory (chip MemHeader @ MH_CHIP) and the slow RAM header.
; Amiga convention: scratch = d0/d1/a0/a1; a6 = library base.
; IMPLEMENTATION track ("clean"): docs/analysis/exec-spec.md, exec-memory-semaphores-v34.md + public ABI.

                include "exec.i"
                include "dospkt.i"
                ifd     MEMTRACK
                xref    ser_puts
                xref    ser_puthex
                endc

                xdef    exec_AllocMem
                xref    ram_expungeall   ; ramlib.s
                xref    td_lowmem        ; trackdisk.s
                xdef    exec_FreeMem
                xdef    exec_AvailMem
                xdef    exec_TypeOfMem
                xdef    exec_Allocate
                xdef    exec_Deallocate
                xdef    exec_AllocAbs
                xdef    exec_AddMemList
                xdef    exec_AllocEntry
                xdef    exec_FreeEntry
                xdef    init_memory
                xdef    add_slow_memory
                xdef    slow_probe

; Behaviour and register contracts: docs/analysis/exec-memory-semaphores-v34.md (§2, §5). Every allocator works in
; 8-byte units: sizes round up; a freed or AllocAbs'd range has its start rounded down and its end rounded up. A
; header matches a request when its attributes hold every bit of the request's low word (upper-word bits such as
; MEMF_CLEAR or MEMF_LARGEST never take part). A size that rounds to 0 fails (1.3 returned a block without consuming
; it for $FFFFFFF9-$FFFFFFFF: deliberately not reproduced).

; Allocate(memHeader a0, byteSize d0) -> d0 = block | 0: first chunk (lowest address) large enough, carved from its
; start. No Forbid (the caller protects the header). Changes d0 and a1 (the block on success) only.
exec_Allocate:
        movem.l d2-d3/a2-a3,-(sp)
        addq.l  #7,d0
        and.l   #-8,d0
        move.l  d0,d2                ; d2 = rounded size
        beq.s   .al_fail
        cmp.l   MH_FREE(a0),d2
        bhi.s   .al_fail
        lea     MH_FIRST(a0),a3      ; a3 = previous link
.al_scan:
        move.l  (a3),a1              ; a1 = chunk
        move.l  a1,d0
        beq.s   .al_fail
        move.l  MC_BYTES(a1),d3
        cmp.l   d2,d3
        bcs.s   .al_next
        beq.s   .al_whole
        lea     0(a1,d2.l),a2        ; split: the remainder starts after the block
        move.l  (a1),(a2)
        sub.l   d2,d3
        move.l  d3,MC_BYTES(a2)
        move.l  a2,(a3)
        bra.s   .al_got
.al_whole:
        move.l  (a1),(a3)
.al_got:
        sub.l   d2,MH_FREE(a0)
        move.l  a1,d0
        bra.s   .al_ret
.al_next:
        move.l  a1,a3
        bra.s   .al_scan
.al_fail:
        moveq   #0,d0
.al_ret:
        movem.l (sp)+,d2-d3/a2-a3
        rts

; AllocMem(size d0, requirements d1) -> d0 = block | 0: headers in MemList order, the first matching one with a
; fitting chunk (Allocate); MEMF_CLEAR zeroes the rounded size. Under Forbid, single exit for a single Permit.
; Changes d0, a0 (the header used) and a1 (the block); d1 is preserved.
exec_AllocMem:
        movem.l d1-d5/a2-a4,-(sp)
        jsr     LVO_FORBID(a6)
        moveq   #0,d3                ; d3 = second attempt done
        move.l  d1,d4                ; d4 = requirements
        move.l  d0,d2                ; d2 = requested size
        addq.l  #7,d0
        and.l   #-8,d0
        beq.s   .am_nomem            ; rounds to 0: no header is tried, nothing to expunge
.am_first:
        lea     EB_MEMLIST(a6),a4
        move.l  (a4),a4              ; a4 = first header
.am_hdr:
        move.l  (a4),d0              ; Succ
        beq.s   .am_fail             ; end of the list
        move.w  MH_ATTRIBUTES(a4),d0
        and.w   d4,d0
        cmp.w   d4,d0
        bne.s   .am_nexth            ; a requested low-word bit is missing
        move.l  a4,a0
        move.l  d2,d0
        bsr     exec_Allocate
        tst.l   d0
        bne.s   .am_got
.am_nexth:
        move.l  (a4),a4
        bra.s   .am_hdr
.am_got:
        btst    #16,d4               ; MEMF_CLEAR?
        beq.s   .am_exit
        move.l  d0,a2
        move.l  d2,d1
        addq.l  #7,d1
        lsr.l   #3,d1                ; rounded size / 8
.am_clr:
        clr.l   (a2)+
        clr.l   (a2)+
        subq.l  #1,d1
        bne.s   .am_clr
        bra.s   .am_exit
.am_fail:                            ; 1.3 (ramlib-v34 §6): modules nobody has open are expunged, then one more try
        tst.w   d3
        bne.s   .am_nomem
        tst.b   RAM_LOWMEM
        bne.s   .am_nomem
        moveq   #1,d3
        st      RAM_LOWMEM
        jsr     td_lowmem            ; the trackdisk multi-track cache goes back first
        jsr     ram_expungeall
        sf      RAM_LOWMEM
        bra.s   .am_first
.am_nomem:
        move.l  EB_THISTASK(a6),d0   ; a process gets ERROR_NO_FREE_STORE
        beq.s   .am_none
        move.l  d0,a0
        cmp.b   #NT_PROCESS,LN_TYPE(a0)
        bne.s   .am_none
        moveq   #103,d0
        move.l  d0,PR_RESULT2(a0)
.am_none:
        moveq   #0,d0
.am_exit:
                ifd     MEMTRACK
        move.l  32(sp),d4            ; caller of AllocMem (above the saved d1-d5/a2-a4)
        bsr     mt_allocc            ; d0 = block | 0, d2 = size, d4 = caller
                endc
        move.l  a4,a0                ; header used (or where the walk ended)
        move.l  d0,a1
        jsr     LVO_PERMIT(a6)       ; Permit preserves the registers
        movem.l (sp)+,d1-d5/a2-a4
        rts

; Deallocate(memHeader a0, memoryBlock a1, byteSize d0): the rounded range goes back into the header's chunk list
; (address order), merged with the chunk that ends at its start and the one that starts at its end. A range that
; overlaps a free chunk is the dead-end Alert(AN_FreeTwice), raised before any change (1.3 links some of them
; first). No range check against the header, no Forbid. Changes d0 (rounded size), d1 and a1 (rounded start).
exec_Deallocate:
        tst.l   d0
        beq.s   .de_ret
        movem.l d2-d3/a2-a3,-(sp)
        move.l  a1,d1
        add.l   d1,d0
        addq.l  #7,d0
        and.l   #-8,d0               ; end rounded up
        and.w   #$FFF8,d1            ; start rounded down
        move.l  d1,a1
        sub.l   d1,d0                ; d0 = rounded size
        beq.s   .de_done
        lea     MH_FIRST(a0),a3      ; a3 = previous link (mh_First acts as a chunk whose next field is at +0)
.de_find:
        move.l  (a3),a2              ; a2 = chunk
        move.l  a2,d2
        beq.s   .de_ins
        cmp.l   a1,a2
        bhi.s   .de_ins              ; first chunk above the start
        add.l   MC_BYTES(a2),d2
        cmp.l   a1,d2
        bhi.s   .de_twice            ; a chunk below the start runs past it
        move.l  a2,a3
        bra.s   .de_find
.de_ins:
        move.l  a1,d3
        add.l   d0,d3                ; d3 = end
        move.l  a2,d2
        beq.s   .de_link
        cmp.l   a2,d3
        bhi.s   .de_twice            ; the range runs into the next chunk
.de_link:
        add.l   d0,MH_FREE(a0)
        cmp.l   a2,d3
        bne.s   .de_nonext
        move.l  (a2),(a1)            ; merged with the next chunk
        add.l   MC_BYTES(a2),d0
        bra.s   .de_size
.de_nonext:
        move.l  a2,(a1)
.de_size:
        move.l  d0,MC_BYTES(a1)
        lea     MH_FIRST(a0),a2
        cmp.l   a2,a3
        beq.s   .de_noprev
        move.l  a3,d2
        add.l   MC_BYTES(a3),d2
        cmp.l   a1,d2
        bne.s   .de_noprev
        move.l  (a1),(a3)            ; merged into the previous chunk
        add.l   d0,MC_BYTES(a3)
        bra.s   .de_done
.de_noprev:
        move.l  a1,(a3)
.de_done:
        movem.l (sp)+,d2-d3/a2-a3
.de_ret:
        rts
.de_twice:
        move.l  d7,-(sp)
        move.l  #AN_FREETWICE,d7
        jsr     LVO_ALERT(a6)        ; dead end
        move.l  (sp)+,d7
        bra.s   .de_done

; FreeMem(memoryBlock a1, byteSize d0): size 0 returns at once (any a1); otherwise, under Forbid, Deallocate in the
; header with mh_Lower <= a1 < mh_Upper; no such header is the dead-end Alert(AN_MemCorrupt). Changes d0, d1, a0;
; a1 is preserved.
exec_FreeMem:
        tst.l   d0
        beq.s   .fm_ret
        jsr     LVO_FORBID(a6)
                ifd     MEMTRACK
        bsr     mt_free              ; check (a1, d0) against the table; (sp) = caller of FreeMem
                endc
        move.l  a1,-(sp)
        bsr.s   mem_owner            ; a0 = header | 0
        beq.s   .fm_bad
        bsr     exec_Deallocate
.fm_done:
        move.l  (sp)+,a1
        jsr     LVO_PERMIT(a6)
.fm_ret:
        rts
.fm_bad:
        move.l  d7,-(sp)
        move.l  #AN_MEMCORRUPT,d7
        jsr     LVO_ALERT(a6)        ; dead end
        move.l  (sp)+,d7
        bra.s   .fm_done

; mem_owner(a1 = address, a6) -> a0 = MemHeader containing it | 0 (Z = 1 if none). Preserves d0/a1.
mem_owner:
        lea     EB_MEMLIST(a6),a0
        move.l  (a0),a0
.mo_hdr:
        tst.l   (a0)                 ; Succ
        beq.s   .mo_none
        cmp.l   MH_LOWER(a0),a1
        bcs.s   .mo_next
        cmp.l   MH_UPPER(a0),a1
        bcs.s   .mo_found
.mo_next:
        move.l  (a0),a0
        bra.s   .mo_hdr
.mo_none:
        sub.l   a0,a0
.mo_found:
        cmp.w   #0,a0                ; Z according to a0 (cmpa.w extends the word: a0 = 0 <=> Z)
        rts

; AllocAbs(byteSize d0, location a1) -> d0 = rounded-down location | 0 when the rounded range is not entirely inside
; one free chunk of the header holding its start. Size 0 inside a chunk succeeds and splits it in two adjacent
; chunks (as 1.3). Under Forbid. Changes d0, a0, a1; d1 is preserved.
exec_AllocAbs:
        movem.l d1-d4/a2-a3,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a1,d2
        and.w   #$FFF8,d2            ; d2 = start
        add.l   a1,d0
        addq.l  #7,d0
        and.l   #-8,d0
        move.l  d0,d4                ; d4 = end
        move.l  d4,d3
        sub.l   d2,d3                ; d3 = size
        move.l  d2,a1
        bsr.s   mem_owner
        beq.s   .aa_fail
        move.l  a0,a2                ; a2 = header
        lea     MH_FIRST(a2),a3      ; a3 = previous link
.aa_scan:
        move.l  (a3),a0
        move.l  a0,d0
        beq.s   .aa_fail
        cmp.l   d2,d0
        bhi.s   .aa_fail             ; sorted chunks: the start is in no free chunk
        add.l   MC_BYTES(a0),d0      ; d0 = end of the chunk
        cmp.l   d2,d0
        bhi.s   .aa_in               ; the start is inside this chunk
        move.l  a0,a3
        bra.s   .aa_scan
.aa_in:
        cmp.l   d4,d0
        bcs.s   .aa_fail             ; the range runs past the chunk
        cmp.l   a0,d2
        bne.s   .aa_split
        tst.l   d3
        beq.s   .aa_got              ; size 0 at the start of a chunk: nothing to carve
.aa_split:
        sub.l   d4,d0                ; d0 = remainder after the range
        beq.s   .aa_nosuf
        move.l  d4,a1                ; tail chunk
        move.l  (a0),(a1)
        move.l  d0,MC_BYTES(a1)
        move.l  a1,(a0)              ; linked after the current chunk
.aa_nosuf:
        move.l  d2,d0
        sub.l   a0,d0                ; d0 = part before the range
        beq.s   .aa_noprefix
        move.l  d0,MC_BYTES(a0)
        bra.s   .aa_got
.aa_noprefix:
        move.l  (a0),(a3)            ; current chunk removed (its tail, if any, takes its place)
.aa_got:
        sub.l   d3,MH_FREE(a2)
        move.l  d2,d0
                ifd     MEMTRACK
        exg     d2,d3
        bsr     mt_alloc             ; d0 = block, d2 = size
        exg     d2,d3
                endc
        bra.s   .aa_exit
.aa_fail:
        moveq   #0,d0
.aa_exit:
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d1-d4/a2-a3
        rts

; AddMemList(size d0, attributes d1, pri d2, base a0, name a1): the area becomes a MemHeader (at its start) Enqueued
; into the MemList by priority; mh_Lower = base+32 rounded up, mh_Upper = base+size rounded down, one free chunk.
exec_AddMemList:
        movem.l d2-d3/a2,-(sp)
        move.l  a0,a2
        move.b  #NT_MEMORY,LN_TYPE(a2)
        move.b  d2,LN_PRI(a2)
        move.l  a1,LN_NAME(a2)
        move.w  d1,MH_ATTRIBUTES(a2)
        move.l  a2,d2
        add.l   d0,d2
        and.w   #$FFF8,d2
        move.l  d2,MH_UPPER(a2)
        lea     MH_SIZE+7(a2),a1
        move.l  a1,d3
        and.w   #$FFF8,d3
        move.l  d3,a1                ; a1 = first chunk
        move.l  a1,MH_LOWER(a2)
        move.l  a1,MH_FIRST(a2)
        sub.l   d3,d2
        move.l  d2,MH_FREE(a2)
        clr.l   MC_NEXT(a1)
        move.l  d2,MC_BYTES(a1)
        jsr     LVO_FORBID(a6)
        lea     EB_MEMLIST(a6),a0
        move.l  a2,a1
        jsr     LVO_ENQUEUE(a6)
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d2-d3/a2
        rts

; AvailMem(requirements d1) -> d0 = free bytes of the matching headers, or their largest chunk with MEMF_LARGEST.
; No MEMF_TOTAL in V34 (bit 19 is ignored like the other upper-word bits). d1 is preserved.
exec_AvailMem:
        movem.l d2-d4,-(sp)
        jsr     LVO_FORBID(a6)       ; consistent read of the shared chunks
        moveq   #0,d4                ; accumulator
        lea     EB_MEMLIST(a6),a0
        move.l  (a0),a0              ; first node
.av_hdr:
        move.l  (a0),d0              ; Succ
        beq.s   .av_done
        move.w  MH_ATTRIBUTES(a0),d0
        and.w   d1,d0
        cmp.w   d1,d0
        bne.s   .av_nexth            ; a requested low-word bit is missing
        btst    #17,d1               ; MEMF_LARGEST ($20000)?
        bne.s   .av_largest
        add.l   MH_FREE(a0),d4       ; sum of the free memory
        bra.s   .av_nexth
.av_largest:
        move.l  MH_FIRST(a0),a1      ; walk the chunks -> max MC_BYTES
.av_lchunk:
        move.l  a1,d0
        beq.s   .av_nexth
        move.l  MC_BYTES(a1),d0
        cmp.l   d4,d0
        bls.s   .av_lnext
        move.l  d0,d4
.av_lnext:
        move.l  (a1),a1
        bra.s   .av_lchunk
.av_nexth:
        move.l  (a0),a0
        bra.s   .av_hdr
.av_done:
        jsr     LVO_PERMIT(a6)       ; single exit; Permit does not touch d4
        move.l  d4,d0
        movem.l (sp)+,d2-d4
        rts

; TypeOfMem(address a1) -> d0 = attributes of the header containing the address | 0
; M3c: Forbid/Permit (walks the shared MemList). Single exit .tom_done.
exec_TypeOfMem:
        jsr     LVO_FORBID(a6)
        lea     EB_MEMLIST(a6),a0
        move.l  (a0),a0              ; first node
.tom_hdr:
        move.l  (a0),d0              ; Succ
        beq.s   .tom_none
        cmp.l   MH_LOWER(a0),a1
        bcs.s   .tom_nexth           ; a1 < MH_LOWER
        cmp.l   MH_UPPER(a0),a1
        bcc.s   .tom_nexth           ; a1 >= MH_UPPER
        moveq   #0,d0
        move.w  MH_ATTRIBUTES(a0),d0 ; found -> attributes
        bra.s   .tom_done
.tom_nexth:
        move.l  (a0),a0
        bra.s   .tom_hdr
.tom_none:
        moveq   #0,d0
.tom_done:
        jsr     LVO_PERMIT(a6)       ; preserves d0
        rts

; AllocEntry(memList a0) -> d0 = new MemList | failure code. The copy is AllocMem(16 + 8n, MEMF_CLEAR) (node fields
; zero, ml_NumEntries copied); each entry in order: me_Length copied unchanged, then me_Addr = AllocMem(me_Length,
; me_Reqs) through the vector, or 0 without a call for a zero length (exec-memory-semaphores-v34 §2.8).
; Failure of an entry: the entries already obtained are freed (FreeMem vector, in order) and d0 = me_Reqs of the
; failing entry | $80000000; the new MemList is NOT freed (1.3 leaks it; callers test bit 31 only). Failure of the
; MemList itself: d0 = $80010000. ml_NumEntries = 0 gives an empty list (1.3 processes one entry past its block).
; The source list is never written. Changes d0, d1, a0, a1.
exec_AllocEntry:
        movem.l d2-d3/a2-a3,-(sp)
        move.l  a0,a2                ; a2 = template
        moveq   #0,d2
        move.w  ML_NUMENTRIES(a2),d2
        move.l  d2,d0
        lsl.l   #3,d0
        add.l   #ML_ME,d0
        move.l  #MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ae_nolist
        move.l  d0,a3                ; a3 = copy
        move.w  d2,ML_NUMENTRIES(a3)
        moveq   #0,d3                ; d3 = entries done
.ae_lp:
        cmp.l   d2,d3
        beq.s   .ae_ok
        move.l  d3,d0
        lsl.l   #3,d0
        lea     ML_ME(a2,d0.l),a0
        lea     ML_ME(a3,d0.l),a1
        move.l  4(a0),d0             ; me_Length
        move.l  d0,4(a1)
        beq.s   .ae_next             ; me_Addr stays 0
        move.l  (a0),d1              ; me_Reqs
        move.l  a1,-(sp)
        jsr     LVO_ALLOCMEM(a6)     ; preserves d1
        move.l  (sp)+,a1
        move.l  d0,(a1)
        beq.s   .ae_fail
.ae_next:
        addq.l  #1,d3
        bra.s   .ae_lp
.ae_ok:
        move.l  a3,d0
        bra.s   .ae_ret
.ae_fail:
        move.l  d1,d2                ; failing requirements
        lea     ML_ME(a3),a2
        bra.s   .ae_fnext
.ae_free:
        move.l  (a2)+,a1
        move.l  (a2)+,d0             ; zero length: FreeMem returns at once
        jsr     LVO_FREEMEM(a6)
.ae_fnext:
        subq.l  #1,d3
        bcc.s   .ae_free
        move.l  d2,d0
        bset    #31,d0
        bra.s   .ae_ret
.ae_nolist:
        move.l  #$80000000|MEMF_CLEAR,d0
.ae_ret:
        movem.l (sp)+,d2-d3/a2-a3
        rts

; FreeEntry(memList a0): FreeMem (vector) of every entry with a non-zero length, in order, then
; FreeMem(list, 16 + 8 x ml_NumEntries). a0 as in exec_lib.fd (icon.library chains RemHead -> FreeEntry with the
; MemList in a0). Changes d0, d1, a0, a1.
exec_FreeEntry:
        movem.l d2/a2,-(sp)
        move.l  a0,a2
        moveq   #0,d2
        move.w  ML_NUMENTRIES(a2),d2
        lea     ML_ME(a2),a0
        bra.s   .fe_nx
.fe_lp:
        move.l  (a0)+,a1
        move.l  (a0)+,d0
        beq.s   .fe_nx
        move.l  a0,-(sp)
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a0
.fe_nx:
        dbra    d2,.fe_lp
        moveq   #0,d0
        move.w  ML_NUMENTRIES(a2),d0
        lsl.l   #3,d0
        add.l   #ML_ME,d0
        move.l  a2,a1
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,d2/a2
        rts

; init_memory: sizes the chip RAM, then chip MemHeader @ MH_CHIP + initial chunk covering the heap.
; Sizing as on 1.3 (spec coldstart-hardware-v34.md §2): a long written at each 4 KB boundary must read back while
; the sentinel long at $0 stays 0 (a mirror of a smaller chip wraps onto $0), up to 2 MB. The first MAXCHIP bytes
; are assumed: they already hold ExecBase, the stack and the low variables.
CHIP_LIMIT      EQU $00200000
CHIP_STEP       EQU $00001000
CHIP_PATTERN    EQU $5AA5C33C
init_memory:                         ; a6 = SysBase (jump table already built)
                ifd     MEMTRACK
        clr.l   MT_TABLE             ; low RAM not cleared at reset
                endc
        move.l  #MAXCHIP,d1          ; d1 = chip size
        clr.l   ($0).w
.im_size:
        cmp.l   #CHIP_LIMIT,d1
        beq.s   .im_sized
        move.l  d1,a1
        move.l  #CHIP_PATTERN,(a1)
        tst.l   ($0).w
        bne.s   .im_mirror
        cmp.l   #CHIP_PATTERN,(a1)
        bne.s   .im_sized
        add.l   #CHIP_STEP,d1
        bra.s   .im_size
.im_mirror:
        clr.l   ($0).w
.im_sized:
        move.l  d1,EB_MAXLOCMEM(a6)
        lea     MH_CHIP,a0
        moveq   #7,d0                ; 32 bytes to zero
        move.l  a0,a1
.im_z:
        clr.l   (a1)+
        dbf     d0,.im_z
        move.b  #NT_MEMORY,LN_TYPE(a0)
        move.b  #-10,LN_PRI(a0)      ; as in 1.3: the boards' fast RAM (pri 0) goes before chip
        move.l  #mh_name,LN_NAME(a0)
        move.w  #(MEMF_CHIP|MEMF_PUBLIC),MH_ATTRIBUTES(a0)
        move.l  #HEAP_LOWER,MH_LOWER(a0)
        move.l  d1,MH_UPPER(a0)
        sub.l   #HEAP_LOWER,d1
        move.l  d1,MH_FREE(a0)
        move.l  #HEAP_LOWER,a1       ; initial chunk = the whole heap
        clr.l   MC_NEXT(a1)
        move.l  d1,MC_BYTES(a1)
        move.l  a1,MH_FIRST(a0)
        lea     EB_MEMLIST(a6),a0    ; AddTail(MemList, MemHeader)
        lea     MH_CHIP,a1
        jsr     LVO_ADDTAIL(a6)
        rts

; slow_probe: detects the A500 "slow" RAM (trapdoor, $C00000..). Called by coldstart BEFORE ExecBase is built,
; since ExecBase goes into that RAM when it exists. Without slow RAM, the area may mirror the custom registers
; ($DFF000, partial decoding): each probe is at offset $1FE/$3FE of a block (= NO-OP register if mirrored ->
; harmless write). Two crossed patterns written to TWO addresses before reading back: a floating bus that retains
; the last written value does not pass. Following blocks: rejected if alias of block 0 (incomplete decoding).
; RAMKICK: the image occupies the first SLOW_RSV bytes, so the probes start above it.
; Returns d0 = end of the slow RAM (the MaxExtMem value), 0 = none. Clobbers d1/a0/a1.
slow_probe:
        movem.l d2-d4,-(sp)
        moveq   #0,d0                ; d0 = detected size
.sp_blk:
        cmp.l   #(SLOW_MAXBLK*SLOW_STEP),d0
        beq.s   .sp_end
        lea     SLOW_BASE+SLOW_RSV,a0
        add.l   d0,a0                ; a0 = candidate block (+ reserved image area)
        move.w  $1FE(a0),d2          ; probed words put back: a warm reset keeps the slow RAM, ExecBase and the
        move.w  $3FE(a0),d3          ; KickMem modules included (coldstart-hardware-v34 §5.2)
        moveq   #-1,d1               ; d1 = block rejected until proven
        move.w  #$5A3C,$1FE(a0)
        move.w  #$A5C3,$3FE(a0)
        cmp.w   #$5A3C,$1FE(a0)
        bne.s   .sp_rest
        move.w  #$A5C3,$1FE(a0)
        move.w  #$5A3C,$3FE(a0)
        cmp.w   #$A5C3,$1FE(a0)
        bne.s   .sp_rest
        moveq   #0,d1
        tst.l   d0                   ; block 0: no alias possible
        beq.s   .sp_rest
        lea     SLOW_BASE+SLOW_RSV,a1
        move.w  $1FE(a1),d4
        move.w  #$1234,$1FE(a1)      ; mark block 0...
        move.w  #$4321,$1FE(a0)      ; ...write the current block...
        cmp.w   #$1234,$1FE(a1)      ; ...has block 0 changed? -> alias
        sne     d1
        move.w  d4,$1FE(a1)
.sp_rest:
        move.w  d2,$1FE(a0)
        move.w  d3,$3FE(a0)
        tst.b   d1
        bne.s   .sp_end
        add.l   #SLOW_STEP,d0
        bra.s   .sp_blk
.sp_end:
        tst.l   d0
        beq.s   .sp_ret
        add.l   #SLOW_BASE,d0
.sp_ret:
        movem.l (sp)+,d2-d4
        rts

; add_slow_memory: adds the slow RAM found by slow_probe (ExecBase MaxExtMem) before chip, below true fast RAM
; (MEMF_FAST|MEMF_PUBLIC, priority -5) -> chip stays for DMA; later priority-0 Zorro RAM is preferred. A game that
; requests ~400 KB of CHIP (Lemmings) only fits under this condition on a 512K chip + 512K slow config.
; ExecBase sits at the bottom of that RAM, so the MemHeader starts right after its positive part. a6 = SysBase.
; Called after the memory selftest (which assumes chip at the head of the list). Returns d0 = bytes of slow RAM
; (0 = none).
add_slow_memory:
        move.l  EB_MAXEXTMEM(a6),d0
        beq.s   .as_ret
        move.l  d0,-(sp)
        lea     EXEC_POSSIZE+7(a6),a0
        move.l  a0,d1
        and.w   #$FFF8,d1
        move.l  d1,a0                ; a0 = MemHeader, 1st chunk right after
        moveq   #(MH_SIZE/4)-1,d1
        move.l  a0,a1
.as_z:
        clr.l   (a1)+
        dbf     d1,.as_z
        move.b  #NT_MEMORY,LN_TYPE(a0)
        move.b  #-5,LN_PRI(a0)
        move.l  #slow_name,LN_NAME(a0)
        move.w  #(MEMF_FAST|MEMF_PUBLIC),MH_ATTRIBUTES(a0)
        lea     MH_SIZE(a0),a1       ; a1 = 1st chunk
        move.l  a1,MH_LOWER(a0)
        move.l  a1,MH_FIRST(a0)
        move.l  d0,MH_UPPER(a0)
        sub.l   a1,d0                ; d0 = free bytes
        move.l  d0,MH_FREE(a0)
        clr.l   MC_NEXT(a1)
        move.l  d0,MC_BYTES(a1)
        move.l  a0,a1                ; AddHead(MemList, header)
        lea     EB_MEMLIST(a6),a0
        jsr     LVO_ADDHEAD(a6)
        move.l  (sp)+,d0
        sub.l   #SLOW_BASE,d0
.as_ret:
        rts

slow_name:
        dc.b    "Fast Memory",0
        EVEN

mh_name:
        dc.b    "Chip Memory",0
        EVEN

                ifd     MEMTRACK
; --- allocation tracer (diagnostic ROM, -DMEMTRACK=1): each successful AllocMem is recorded (address, size, caller) in
; a table of MT_N entries (AllocAbs too); each FreeMem is looked up in it: different size -> "MTSZ address returned-size
; recorded-size caller", unknown address -> "MTUNK address size caller". Under Forbid (callers).
MT_N            EQU 3000
; mt_alloc(d0 = block | 0, d2 = size, a6) / mt_allocc (same, d4 = caller): preserve everything. Entries of
; 12 bytes: address, size, caller (0 for AllocAbs); the blocks still allocated stay in the table (debugger dump).
mt_alloc:
        move.l  d4,-(sp)
        moveq   #0,d4
        bsr.s   mt_allocc
        move.l  (sp)+,d4
        rts
mt_allocc:
        movem.l d0-d1/a0-a1,-(sp)
        tst.l   d0
        beq.s   .ma_ret
        move.l  MT_TABLE,d1
        bne.s   .ma_have
        cmp.l   #MT_N*12,d2          ; the table itself (allocated below) is not recorded
        beq.s   .ma_ret
        move.l  #MT_N*12,d0
        move.l  #MEMF_CHIP|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,MT_TABLE
        beq.s   .ma_ret
        move.l  d0,d1
        move.l  (sp),d0
.ma_have:
        move.l  d1,a0
        move.w  #MT_N-1,d1
.ma_lp:
        tst.l   (a0)
        beq.s   .ma_put
        lea     12(a0),a0
        dbra    d1,.ma_lp
        bra.s   .ma_ret              ; table full
.ma_put:
        move.l  d0,(a0)+
        move.l  d2,(a0)+
        move.l  d4,(a0)
.ma_ret:
        movem.l (sp)+,d0-d1/a0-a1
        rts
; mt_free(a1 = block, d0 = size, a6): called by FreeMem after its Forbid; 4(sp) = caller of FreeMem.
mt_free:
        movem.l d0-d3/a0-a1,-(sp)
        move.l  MT_TABLE,d1
        beq.s   .mf_ret
        move.l  d1,a0
        move.w  #MT_N-1,d1
.mf_lp:
        cmp.l   (a0),a1
        beq.s   .mf_found
        lea     12(a0),a0
        dbra    d1,.mf_lp
        lea     mt_unk(pc),a0        ; address never allocated (or already returned)
        jsr     ser_puts
        move.l  a1,d0
        bsr     mt_hex
        move.l  (sp),d0
        bsr     mt_hex
        move.l  24+4(sp),d0
        bsr     mt_hex
        bsr     mt_task
        bra.s   .mf_ret
.mf_found:
        clr.l   (a0)+
        move.l  (a0),d2              ; recorded size
        move.l  d0,d3
        addq.l  #7,d3
        and.l   #-8,d3
        move.l  d2,d1
        addq.l  #7,d1
        and.l   #-8,d1
        cmp.l   d1,d3
        beq.s   .mf_ret
        lea     mt_sz(pc),a0
        jsr     ser_puts
        move.l  a1,d0
        bsr     mt_hex
        move.l  (sp),d0
        bsr     mt_hex
        move.l  d2,d0
        bsr     mt_hex
        move.l  24+4(sp),d0
        bsr     mt_hex
.mf_ret:
        movem.l (sp)+,d0-d3/a0-a1
        rts
; mt_task: "name-of-the-current-task" appended to the line (identifies the freer when the caller is generic).
mt_task:
        move.l  EB_THISTASK(a6),d0
        beq.s   .mt_tret
        move.l  d0,a0
        move.l  LN_NAME(a0),d0
        beq.s   .mt_tret
        lea     mt_sp(pc),a0
        jsr     ser_puts
        move.l  EB_THISTASK(a6),a0
        move.l  LN_NAME(a0),a0
        jsr     ser_puts
.mt_tret:
        rts
mt_hex:
        swap    d0
        jsr     ser_puthex
        swap    d0
        jsr     ser_puthex
        rts
mt_unk: dc.b    13,10,"MTUNK ",0
mt_sz:  dc.b    13,10,"MTSZ ",0
mt_sp:  dc.b    " ",0
        even
                endc
