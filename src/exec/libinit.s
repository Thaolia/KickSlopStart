; src/exec/libinit.s — exec.library: creation of libraries/devices (M5a, AUTOINIT).
;   MakeFunctions: builds a jump table (absolute JMPs) below a base, from an array
;                   of vectors (absolute longwords, or relative words if 1st word = -1).
;   MakeLibrary   : allocates (negSize jump table + dataSize data), builds the jump table,
;                   InitStructs the data table, calls the init function; returns the base.
;   InitStruct    : interprets a stream of "ddssnnnn" commands (exec/InitStruct format).
; Used by the AUTOINIT path of InitResident (resident.s) to create the resident devices/libs
; (RTF_AUTOINIT) from their table of 4 longs {dataSize, funcTab, dataTab, init}.
; Amiga convention: scratch = d0/d1/a0/a1; a6 = library base.
; IMPLEMENTATION track ("clean"): AutoDocs exec MakeLibrary/MakeFunctions/InitStruct
; + exec/initializers.i (public ABI). NO reading of the ROM.

                include "exec.i"

                xdef    exec_MakeLibrary
                xdef    exec_MakeFunctions
                xdef    exec_InitStruct

; MakeFunctions(target a0, funcArray a1, funcDispBase a2) -> d0 = size (bytes).
; Places the entries [JMP $4EF9][long address] (6 bytes) below `target`, downwards (LVO -6, -12...).
; funcArray: 1st word = -1 -> WORD displacements relative to funcDispBase, terminated by word -1;
; otherwise absolute LONG pointers, terminated by long -1.
exec_MakeFunctions:
                movem.l d2/a3-a4,-(sp)
                move.l  a0,d2               ; d2 = original target (for the size)
                move.l  a0,a3               ; a3 = table cursor (decreasing)
                move.l  a1,a4               ; a4 = funcArray cursor
                cmp.w   #-1,(a4)
                bne.s   .mf_abs
                addq.l  #2,a4               ; relative: skip the -1 marker
.mf_rel:
                move.w  (a4)+,d0
                cmp.w   #-1,d0
                beq.s   .mf_end
                ext.l   d0
                move.l  a2,a0
                add.l   d0,a0               ; address = funcDispBase + offset(word)
                subq.l  #6,a3
                move.w  #$4EF9,(a3)
                move.l  a0,2(a3)
                bra.s   .mf_rel
.mf_abs:
                move.l  (a4)+,d0
                cmp.l   #-1,d0
                beq.s   .mf_end
                move.l  d0,a0               ; absolute address
                subq.l  #6,a3
                move.w  #$4EF9,(a3)
                move.l  a0,2(a3)
                bra.s   .mf_abs
.mf_end:
                move.l  d2,d0
                sub.l   a3,d0               ; size = target - cursor
                movem.l (sp)+,d2/a3-a4
                rts

; MakeLibrary(vectors a0, structure a1, init a2, dataSize d0, segList d1) -> d0 = base | 0.
; Allocates negSize (jump table) + dataSize (MEMF_CLEAR), the base = alloc + negSize. Builds the
; jump table, sets LIB_NEGSIZE/LIB_POSSIZE, InitStructs the data table (if != NULL), calls
; the init (if != NULL) with D0=base, A0=segList, A6=ExecBase (its return value becomes the
; base). Does NOT fill name/type/version from the ROMTag (V34 quirk: the module does it).
exec_MakeLibrary:
                movem.l d2-d5/a3-a5,-(sp)
                move.l  a0,a3               ; a3 = vectors
                move.l  a1,a4               ; a4 = structure (data table InitStruct)
                move.l  a2,a5               ; a5 = init function
                move.l  d0,d2               ; d2 = dataSize
                move.l  d1,d3               ; d3 = segList
                move.l  a3,a0               ; count the vectors -> negSize
                bsr.s   count_vectors       ; -> d0 = number of vectors
                mulu    #6,d0               ; negSize = number * 6
                move.l  d0,d4               ; d4 = negSize
                add.l   d2,d0               ; total = negSize + dataSize
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1 ; no DMA: slow RAM first if present (chip RAM is left for programs)
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .ml_fail
                add.l   d4,d0               ; d0 = base = alloc + negSize
                move.l  d0,d5               ; d5 = base (kept)
                move.l  d0,a0               ; MakeFunctions(target=base, vectors, dispBase=vectors)
                move.l  a3,a1
                move.l  a3,a2
                jsr     LVO_MAKEFUNCTIONS(a6)
                move.l  d5,a2               ; a2 = base
                move.w  d4,LIB_NEGSIZE(a2)
                move.w  d2,LIB_POSSIZE(a2)
                move.l  a4,d0               ; data table present?
                beq.s   .ml_noinitstruct
                move.l  a4,a1               ; InitStruct(initTable=structure, memory=base, size=dataSize)
                move.l  d5,a2
                move.l  d2,d0
                jsr     LVO_INITSTRUCT(a6)
.ml_noinitstruct:
                move.l  a5,d0               ; init function present?
                beq.s   .ml_done
                move.l  d5,d0               ; D0 = base
                move.l  d3,a0               ; A0 = segList
                move.l  a5,a1
                jsr     (a1)                ; init(D0=base, A0=segList, A6=ExecBase) -> D0 = base'
                move.l  d0,d5               ; the return value becomes the base
.ml_done:
                move.l  d5,d0               ; -> base
                movem.l (sp)+,d2-d5/a3-a5
                rts
.ml_fail:
                moveq   #0,d0
                movem.l (sp)+,d2-d5/a3-a5
                rts

; count_vectors(a0 = funcArray) -> d0 = number of vectors (excluding marker/terminator).
count_vectors:
                move.l  a0,a1
                moveq   #0,d0
                cmp.w   #-1,(a1)
                bne.s   .cv_abs
                addq.l  #2,a1               ; relative: skip the -1 marker
.cv_rel:
                cmp.w   #-1,(a1)
                beq.s   .cv_done
                addq.l  #2,a1
                addq.l  #1,d0
                bra.s   .cv_rel
.cv_abs:
                cmp.l   #-1,(a1)
                beq.s   .cv_done
                addq.l  #4,a1
                addq.l  #1,d0
                bra.s   .cv_abs
.cv_done:
                rts

; InitStruct(initTable a1, memory a2, size d0) (AutoDoc exec): first clears `size` bytes of memory (0 = none), then
; executes the "ddssnnnn" command stream: dd = 00 copy at the current position, 01 repeat one same value,
; 10 offset on 1 byte, 11 offset on 3 bytes; ss = 00 long, 01 word, 10 byte; nnnn = number of elements - 1.
; The stream is realigned on a word after each command (command byte + 8-bit offset + byte data).
; Null command byte = end.
exec_InitStruct:
                movem.l d2-d4/a3,-(sp)
                move.l  a2,a3               ; a3 = current destination
                move.l  d0,d1
                beq.s   .is_cmd
                move.l  a2,a0
.is_clr:
                clr.b   (a0)+
                subq.l  #1,d1
                bne.s   .is_clr
.is_cmd:
                moveq   #0,d0
                move.b  (a1)+,d0            ; ddssnnnn
                beq     .is_done
                moveq   #15,d3
                and.b   d0,d3               ; d3 = nnnn (elements - 1)
                move.b  d0,d4
                lsr.b   #4,d4
                and.w   #3,d4               ; d4 = ss
                move.b  d0,d1
                lsr.b   #6,d1               ; d1 = dd
                cmp.b   #2,d1
                bcs.s   .is_data            ; 00 / 01: current position
                bne.s   .is_off24
                moveq   #0,d2               ; 10: 8-bit offset
                move.b  (a1)+,d2
                bra.s   .is_setdst
.is_off24:
                moveq   #0,d2               ; 11: 24-bit offset
                move.b  (a1)+,d2
                lsl.l   #8,d2
                move.b  (a1)+,d2
                lsl.l   #8,d2
                move.b  (a1)+,d2
.is_setdst:
                lea     0(a2,d2.l),a3
                moveq   #0,d1               ; offset: copy (like dd = 00)
.is_data:
                cmp.w   #2,d4
                beq.s   .is_bytes
                move.l  a1,d2               ; word/long data: aligned on a word
                btst    #0,d2
                beq.s   .is_aligned
                addq.l  #1,a1
.is_aligned:
                tst.w   d4
                beq.s   .is_longs
.is_words:
                move.w  (a1),(a3)+
                tst.b   d1                  ; 01 = repeat: the source does not move
                bne.s   .is_wnext
                addq.l  #2,a1
.is_wnext:
                dbra    d3,.is_words
                tst.b   d1
                beq.s   .is_cmd
                addq.l  #2,a1
                bra.s   .is_cmd
.is_longs:
                move.l  (a1),(a3)+
                tst.b   d1
                bne.s   .is_lnext
                addq.l  #4,a1
.is_lnext:
                dbra    d3,.is_longs
                tst.b   d1
                beq.s   .is_cmd
                addq.l  #4,a1
                bra.s   .is_cmd
.is_bytes:
                move.b  (a1),(a3)+
                tst.b   d1
                bne.s   .is_bnext
                addq.l  #1,a1
.is_bnext:
                dbra    d3,.is_bytes
                tst.b   d1
                beq.s   .is_balign
                addq.l  #1,a1
.is_balign:
                move.l  a1,d2               ; realign the stream on a word
                btst    #0,d2
                beq     .is_cmd
                addq.l  #1,a1
                bra     .is_cmd
.is_done:
                movem.l (sp)+,d2-d4/a3
                rts
