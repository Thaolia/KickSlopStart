; src/exec/memory.s — exec.library: multi-MemHeader memory allocator.
;   AllocMem: walks the MemList, selects the 1st header satisfying the
;              requested TYPE bits, then first-fit + split on that header.
;   FreeMem  : finds the owning header (by address range) then
;              two-sided coalescing (body IDENTICAL to M2.2, verified).
;   AvailMem: sums the free memory of compatible headers (or largest block).
;   TypeOfMem: attributes of the header containing an address (0 if none).
;   init_memory: single chip MemHeader @ MH_CHIP.
; Amiga convention: scratch = d0/d1/a0/a1; a6 = library base.
; IMPLEMENTATION track ("clean"): docs/analysis/exec-spec.md + public ABI.

                include "exec.i"
                ifd     MEMTRACK
                xref    ser_puts
                xref    ser_puthex
                endc

                xdef    exec_AllocMem
                xdef    exec_FreeMem
                xdef    exec_AvailMem
                xdef    exec_TypeOfMem
                xdef    exec_Allocate
                xdef    exec_Deallocate
                xdef    exec_AllocAbs
                xdef    exec_AddMemList
                xdef    init_memory
                xdef    add_slow_memory

; Allocate(memHeader a0, byteSize d0) -> d0 = block | 0: first-fit + split within the chunks of ONE MemHeader, size
; rounded to 8 bytes (AutoDoc: the caller protects the header, Forbid or semaphore). Clobbers d1/a0/a1.
exec_Allocate:
        movem.l d2-d3/a2-a3,-(sp)
        addq.l  #7,d0
        and.l   #-8,d0
        move.l  d0,d2                ; d2 = size
        beq.s   .al_fail
        cmp.l   MH_FREE(a0),d2
        bhi.s   .al_fail
        move.l  a0,a2                ; a2 = header
        lea     MH_FIRST(a2),a3      ; a3 = previous link
.al_scan:
        move.l  (a3),a0              ; chunk = *prev
        move.l  a0,d0
        beq.s   .al_fail             ; header exhausted
        move.l  MC_BYTES(a0),d3
        cmp.l   d2,d3
        bcs.s   .al_next             ; mc_Bytes < size
        beq.s   .al_whole
        move.l  a0,a1                ; split: new chunk = chunk + size
        add.l   d2,a1
        move.l  (a0),(a1)
        sub.l   d2,d3
        move.l  d3,MC_BYTES(a1)
        move.l  a1,(a3)
        bra.s   .al_got
.al_whole:
        move.l  (a0),(a3)            ; whole chunk removed
.al_got:
        sub.l   d2,MH_FREE(a2)
        move.l  a0,d0
        bra.s   .al_ret
.al_next:
        move.l  a0,a3
        bra.s   .al_scan
.al_fail:
        moveq   #0,d0
.al_ret:
        movem.l (sp)+,d2-d3/a2-a3
        rts

; AllocMem(size d0, flags d1) -> d0 = block | 0: first MemHeader whose attributes cover the requested TYPE bits
; and that can serve the size (Allocate); MEMF_CLEAR zeroes the block. Under Forbid (shared MemList),
; single exit for a single Permit.
exec_AllocMem:
        movem.l d2-d5/a2-a4,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  d1,d4                ; flags (for MEMF_CLEAR)
        move.l  d1,d5
        and.w   #MEMF_TYPEMASK,d5    ; reqType = requested TYPE bits (V34)
        move.l  d0,d2                ; requested size
        lea     EB_MEMLIST(a6),a4
        move.l  (a4),a4              ; a4 = first header
.am_hdr:
        move.l  (a4),d0              ; Succ
        beq.s   .am_fail             ; sentinel: no satisfying header
        move.w  MH_ATTRIBUTES(a4),d0
        and.w   d5,d0
        cmp.w   d5,d0
        bne.s   .am_nexth            ; (MH_ATTR & reqType) != reqType
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
        move.l  d0,a1
        move.l  d2,d1
        addq.l  #7,d1
        lsr.l   #3,d1                ; size rounded / 8
.am_clr:
        clr.l   (a1)+
        clr.l   (a1)+
        subq.l  #1,d1
        bne.s   .am_clr
        bra.s   .am_exit
.am_fail:
        moveq   #0,d0
.am_exit:
                ifd     MEMTRACK
        bsr     mt_alloc             ; d0 = block | 0, d2 = size
                endc
        jsr     LVO_PERMIT(a6)       ; Permit does not touch d0
        movem.l (sp)+,d2-d5/a2-a4
        rts

; Deallocate(memHeader a0, memoryBlock a1, byteSize d0): returns the block to the header's sorted chunk list, with
; merging with the next and the previous chunk if they are contiguous. Size rounded to 8. Clobbers d0/d1/a0/a1.
exec_Deallocate:
        move.l  a1,d1
        beq.s   .de_ret
        addq.l  #7,d0
        and.l   #-8,d0
        beq.s   .de_ret
        movem.l d2-d3/a2-a3,-(sp)
        move.l  a0,a2                ; a2 = header
        add.l   d0,MH_FREE(a2)
        lea     MH_FIRST(a2),a3      ; a3 = previous link
.de_find:
        move.l  (a3),a0              ; a0 = current chunk
        move.l  a0,d2
        beq.s   .de_ins              ; end of list
        cmp.l   a1,a0
        bhi.s   .de_ins              ; chunk > block -> insert before
        move.l  a0,a3
        bra.s   .de_find
.de_ins:
        move.l  a0,(a1)              ; block->Next = current chunk
        move.l  d0,MC_BYTES(a1)
        move.l  a1,(a3)
        move.l  a1,d2                ; merge with the NEXT one: block + size == current?
        add.l   d0,d2
        cmp.l   a0,d2
        bne.s   .de_nonext
        move.l  (a0),(a1)
        move.l  MC_BYTES(a0),d3
        add.l   d3,MC_BYTES(a1)
.de_nonext:
        lea     MH_FIRST(a2),a0      ; merge with the PREVIOUS one (if it exists)
        cmp.l   a0,a3
        beq.s   .de_done
        move.l  a3,d2
        add.l   MC_BYTES(a3),d2
        cmp.l   a1,d2
        bne.s   .de_done
        move.l  (a1),(a3)
        move.l  MC_BYTES(a1),d3
        add.l   d3,MC_BYTES(a3)
.de_done:
        movem.l (sp)+,d2-d3/a2-a3
.de_ret:
        rts

; FreeMem(ptr a1, size d0): owning header (MH_LOWER <= ptr < MH_UPPER) then Deallocate, under Forbid. The
; NULL / size 0 guards exit before the Forbid.
exec_FreeMem:
        move.l  a1,d1
        beq.s   .fm_ret
        tst.l   d0
        beq.s   .fm_ret
        jsr     LVO_FORBID(a6)
                ifd     MEMTRACK
        bsr     mt_free              ; check (a1, d0) against the table; (sp) = caller of FreeMem
                endc
        bsr.s   mem_owner            ; a0 = header | 0
        beq.s   .fm_done             ; no owning header -> ignored
        bsr     exec_Deallocate
.fm_done:
        jsr     LVO_PERMIT(a6)
.fm_ret:
        rts

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

; AllocAbs(byteSize d0, location a1) -> d0 = block (location rounded down to 8) | 0 if the area is not
; entirely free within one chunk. Under Forbid.
exec_AllocAbs:
        movem.l d2-d4/a2-a3,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  a1,d2
        and.l   #-8,d2               ; d2 = start
        add.l   a1,d0
        sub.l   d2,d0
        addq.l  #7,d0
        and.l   #-8,d0
        move.l  d0,d3                ; d3 = size
        beq.s   .aa_fail
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
        move.l  d2,d4
        add.l   d3,d4                ; d4 = requested end
        cmp.l   d4,d0
        bcc.s   .aa_found
        move.l  a0,a3
        bra.s   .aa_scan
.aa_found:
        sub.l   d4,d0                ; d0 = remainder after the area
        beq.s   .aa_nosuf
        move.l  d4,a1                ; tail chunk
        move.l  (a0),(a1)
        move.l  d0,MC_BYTES(a1)
        move.l  a1,(a0)              ; linked after the current chunk
.aa_nosuf:
        move.l  d2,d0
        sub.l   a0,d0                ; d0 = part before the area
        beq.s   .aa_noprefix
        move.l  d0,MC_BYTES(a0)
        bra.s   .aa_got
.aa_noprefix:
        move.l  (a0),(a3)            ; current chunk removed (its possible tail takes its place)
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
        movem.l (sp)+,d2-d4/a2-a3
        rts

; AddMemList(size d0, attributes d1, pri d2, base a0, name a1): the area becomes a MemHeader (at the start of the
; area) inserted into the MemList by priority; a single free chunk covers it after the header.
exec_AddMemList:
        movem.l d2-d3/a2,-(sp)
        move.l  a0,a2
        move.b  #NT_MEMORY,LN_TYPE(a2)
        move.b  d2,LN_PRI(a2)
        move.l  a1,LN_NAME(a2)
        move.w  d1,MH_ATTRIBUTES(a2)
        move.l  a2,d2
        add.l   d0,d2
        move.l  d2,MH_UPPER(a2)
        lea     MH_SIZE+7(a2),a1
        move.l  a1,d3
        and.l   #-8,d3
        move.l  d3,a1                ; a1 = first chunk
        move.l  a1,MH_LOWER(a2)
        move.l  a1,MH_FIRST(a2)
        sub.l   d3,d2
        and.l   #-8,d2
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

; AvailMem(requirements d1) -> d0 = compatible free bytes (or largest block)
exec_AvailMem:
        movem.l d2-d4,-(sp)
        jsr     LVO_FORBID(a6)       ; M3c: consistent read of the shared chunks
        move.l  d1,d2                ; requirements
        move.l  d1,d3
        and.w   #MEMF_TYPEMASK,d3    ; reqType
        moveq   #0,d4                ; accumulator
        lea     EB_MEMLIST(a6),a0
        move.l  (a0),a0              ; first node
.av_hdr:
        move.l  (a0),d0              ; Succ
        beq.s   .av_done
        move.w  MH_ATTRIBUTES(a0),d0
        and.w   d3,d0
        cmp.w   d3,d0
        bne.s   .av_nexth            ; incompatible header
        btst    #17,d2               ; MEMF_LARGEST ($20000)?
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

; init_memory: chip MemHeader @ MH_CHIP + initial chunk covering the heap
init_memory:                         ; a6 = SysBase (jump table already built)
                ifd     MEMTRACK
        clr.l   MT_TABLE             ; low RAM not cleared at reset
                endc
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
        move.l  #HEAP_UPPER,MH_UPPER(a0)
        move.l  #(HEAP_UPPER-HEAP_LOWER),MH_FREE(a0)
        move.l  #HEAP_LOWER,a1       ; initial chunk = the whole heap
        clr.l   MC_NEXT(a1)
        move.l  #(HEAP_UPPER-HEAP_LOWER),MC_BYTES(a1)
        move.l  a1,MH_FIRST(a0)
        lea     EB_MEMLIST(a6),a0    ; AddTail(MemList, MemHeader)
        lea     MH_CHIP,a1
        jsr     LVO_ADDTAIL(a6)
        rts

; add_slow_memory: detects the A500 "slow" RAM (trapdoor, $C00000..) and adds it AT THE HEAD of the MemList
; (MEMF_FAST|MEMF_PUBLIC) -> allocations without MEMF_CHIP go there first; chip stays for DMA. A game that
; requests ~400 KB of CHIP (Lemmings) only fits under this condition on a 512K chip + 512K slow config.
; Without slow RAM, the area may mirror the custom registers ($DFF000, partial decoding): each probe is at
; offset $1FE/$3FE of a block (= NO-OP register if mirrored -> harmless write). Two crossed patterns written
; to TWO addresses before reading back: a floating bus that retains the last written value does not pass.
; Following blocks: rejected if alias of block 0 (incomplete decoding). a6 = SysBase. Called after the memory
; selftest (which assumes chip at the head of the list). Returns d0 = bytes of slow RAM detected (0 = none).
SLOW_BASE       EQU $00C00000
SLOW_STEP       EQU $00080000        ; 512 KB granularity
SLOW_MAXBLK     EQU 3                ; up to 1.5 MB ($C00000-$D7FFFF)
add_slow_memory:
        movem.l d2-d4/a2-a3,-(sp)
        moveq   #0,d2                ; d2 = detected size
.as_blk:
        cmp.l   #(SLOW_MAXBLK*SLOW_STEP),d2
        beq.s   .as_add
        lea     SLOW_BASE,a2
        add.l   d2,a2                ; a2 = candidate block
        move.w  #$5A3C,$1FE(a2)
        move.w  #$A5C3,$3FE(a2)
        cmp.w   #$5A3C,$1FE(a2)
        bne.s   .as_add
        move.w  #$A5C3,$1FE(a2)
        move.w  #$5A3C,$3FE(a2)
        cmp.w   #$A5C3,$1FE(a2)
        bne.s   .as_add
        tst.l   d2                   ; block 0: no alias possible
        beq.s   .as_ok
        lea     SLOW_BASE,a3
        move.w  #$1234,$1FE(a3)      ; mark block 0...
        move.w  #$4321,$1FE(a2)      ; ...write the current block...
        cmp.w   #$1234,$1FE(a3)      ; ...has block 0 changed? -> alias
        bne.s   .as_add
.as_ok:
        add.l   #SLOW_STEP,d2
        bra.s   .as_blk
.as_add:
        move.l  d2,d4                ; d4 = detected size (return value)
        beq.s   .as_ret              ; no slow RAM: nothing to do
        lea     SLOW_BASE,a0         ; MemHeader at the start of the area, 1st chunk right after
        moveq   #(MH_SIZE/4)-1,d0
        move.l  a0,a1
.as_z:
        clr.l   (a1)+
        dbf     d0,.as_z
        move.b  #NT_MEMORY,LN_TYPE(a0)
        move.l  #slow_name,LN_NAME(a0)
        move.w  #(MEMF_FAST|MEMF_PUBLIC),MH_ATTRIBUTES(a0)
        lea     MH_SIZE(a0),a1       ; a1 = 1st chunk
        move.l  a1,MH_LOWER(a0)
        move.l  a1,MH_FIRST(a0)
        move.l  d2,d3
        add.l   a0,d3
        move.l  d3,MH_UPPER(a0)
        sub.l   #MH_SIZE,d2          ; d2 = free bytes
        move.l  d2,MH_FREE(a0)
        clr.l   MC_NEXT(a1)
        move.l  d2,MC_BYTES(a1)
        move.l  a0,a1                ; AddHead(MemList, header)
        lea     EB_MEMLIST(a6),a0
        jsr     LVO_ADDHEAD(a6)
.as_ret:
        move.l  d4,d0
        movem.l (sp)+,d2-d4/a2-a3
        rts

slow_name:
        dc.b    "Fast Memory",0
        EVEN

mh_name:
        dc.b    "Chip Memory",0
        EVEN

                ifd     MEMTRACK
; --- allocation tracer (diagnostic ROM, -DMEMTRACK=1): each successful AllocMem is recorded (address, size) in
; a table of MT_N entries (AllocAbs too); each FreeMem is looked up in it: different size -> "MTSZ address returned-size
; recorded-size caller", unknown address -> "MTUNK address size caller". Under Forbid (callers).
MT_N            EQU 3000
; mt_alloc(d0 = block | 0, d2 = size, a6): preserves everything.
mt_alloc:
        movem.l d0-d1/a0-a1,-(sp)
        tst.l   d0
        beq.s   .ma_ret
        move.l  MT_TABLE,d1
        bne.s   .ma_have
        cmp.l   #MT_N*8,d2           ; the table itself (allocated below) is not recorded
        beq.s   .ma_ret
        move.l  #MT_N*8,d0
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
        addq.l  #8,a0
        dbra    d1,.ma_lp
        bra.s   .ma_ret              ; table full
.ma_put:
        move.l  d0,(a0)+
        move.l  d2,(a0)
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
        addq.l  #8,a0
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
