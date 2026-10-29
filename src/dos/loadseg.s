; src/dos/loadseg.s - LoadSeg (D2): loads an AmigaDOS "hunk" executable from OFS, APPLIES the
; relocations, builds a BPTR seglist, and returns the BPTR of the first segment. INTERNAL machinery (no
; dos.library packets yet = D3). Relies on ofs_read_file (D1) to read the file, then parses the hunk format.
;
; Hunk format LOCKED DOWN empirically (vlink -s -bamigahunk binary, NOT the ROM): HUNK_HEADER (resident libs=0,
; table_size, first, last, N sizes [bits 30-31 = memory flags to mask off]); body = per hunk: CODE/DATA (nlongs
; + data) or BSS (nlongs, no data), HUNK_RELOC32 relocations ($3EC: repeated [count][hunk_ref][offsets...], 0 =
; end), HUNK_END; NAME/SYMBOL/DEBUG ignored (no effect on loading). $3FC (compact RELOC32) -> clean failure
; (no silent skipping of a relocation). Clean-room: AmigaDOS Technical Reference /
; RKRM (public hunk format) + AROS rom/dos InternalLoadSeg (read-only). NO ROM reading.
;
; Seglist (AmigaDOS convention): each segment = AllocMem block [LONG size][BPTR next][contents...]; the BPTR
; points to the next field (block+4) -> contents at (BPTR<<2)+4 = block+8; size at block+0 (for UnLoadSeg).
; HUNK_HEADER memory flags honoured (bit 30 -> MEMF_CHIP, bit 31 -> MEMF_FAST; 11 = V37 extended attributes ->
; clean failure). D2 deviations/scope ACCEPTED: first != 0, resident libs,
; RELOC32SHORT, overlays -> not supported (clean failure). Enough to load our executables.
; Anti-corruption guards: index of the current hunk and hunk referenced by RELOC32 < hunkcount. DEBT: the
; relocation offset (`offset < hunk size`) and the contents size are not bounds-checked -> a corrupted binary can
; still write outside its hunk. Proven on a real disk binary (HolidayLemmings: 4 hunks, chip BSS of
; 363 KB, chip/any CODE hunks, multi-reference RELOC32, hunk ids carrying the memory flags).

                include "exec.i"
                include "ofs.i"
                include "dospkt.i"

                xdef    dos_loadseg
                xdef    dos_unloadseg
                xdef    ls_load_hunks
                xdef    ls_load_stream
                xref    ofs_read_file

HUNK_HEADER     EQU $3F3
HUNK_CODE       EQU $3E9
HUNK_DATA       EQU $3EA
HUNK_BSS        EQU $3EB
HUNK_RELOC32    EQU $3EC
HUNK_END        EQU $3F2
HUNK_NAME       EQU $3E8
HUNK_SYMBOL     EQU $3F0
HUNK_DEBUG      EQU $3F1
LS_FILEMAX      EQU DOS_FILEMAX    ; max size of a loaded hunk executable (cap-bump 32K, exec.i)
LS_MAXHUNKS     EQU 64            ; bound on the number of hunks (anti-corruption)

; D2_NO_RELOC=1 (RED D2): reads the relocations but does NOT APPLY them -> the absolute pointer stays the link-time
; offset (0 in the DATA hunk) -> the loaded code reads low RAM -> wrong bytes -> "D2LOADSEG OK" missing,
; WITHOUT a bus error. Isolates the application of relocations. Default 0.
D2_NO_RELOC     EQU 0

; dos_loadseg(a6=SysBase, a0=NUL-terminated filename) -> d0 = BPTR of 1st segment | 0. Wrapper: reads the ENTIRE file
; via ofs_read_file (D1) into a filebuf, then ls_load_hunks parses it. (D3d calls ls_load_hunks directly on
; a buffer read via dos Open/Read -> loading THROUGH the packets/handler.)
dos_loadseg:
                movem.l d2/a2,-(sp)
                move.l  a0,d2                ; d2 = filename
                move.l  #LS_FILEMAX,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .dl_fail0
                move.l  d0,a2                ; a2 = filebuf
                move.l  d2,a0                ; filename
                move.l  a2,a1                ; dest
                move.l  #LS_FILEMAX,d0
                jsr     ofs_read_file        ; d0 = size | 0
                tst.l   d0
                beq.s   .dl_freefb           ; not found / empty
                move.l  a2,a0                ; a0 = filebuf, d0 = size
                bsr     ls_load_hunks        ; d0 = BPTR seglist | 0
                move.l  d0,d2                ; save seglist
                move.l  a2,a1                ; free filebuf
                move.l  #LS_FILEMAX,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d2,d0                ; return seglist
                bra.s   .dl_ret
.dl_freefb:
                move.l  a2,a1
                move.l  #LS_FILEMAX,d0
                jsr     LVO_FREEMEM(a6)
.dl_fail0:
                moveq   #0,d0
.dl_ret:
                movem.l (sp)+,d2/a2
                rts

; ls_load_hunks(a6=SysBase, a0=filebuf, d0=size) -> d0 = BPTR of 1st segment | 0, d1 = dos error code if 0.
; Parses the hunk format from a buffer already in memory (dos_loadseg, D3d client). Does NOT free filebuf.
ls_load_hunks:
                lea     -LR_SIZE(sp),sp
                move.l  a0,LR_BUF(sp)
                clr.l   LR_POS(sp)
                move.l  d0,LR_LEN(sp)
                clr.l   LR_FH(sp)            ; no file: the end of the buffer is the end of the data
                move.l  sp,a0
                bsr.s   ls_load_stream
                lea     LR_SIZE(sp),sp
                rts

; ls_load_stream(a6=SysBase, a0=LR_* reader) -> d0 = BPTR of 1st segment | 0, d1 = 103 (memory) or 121 (format) if 0.
; Reader: LR_BUF buffer of LR_CAP bytes refilled by Read(LR_FH) via LR_DOS (LoadSeg), or fixed buffer of LR_LEN
; bytes if LR_FH = 0. Large content blocks are read directly into place.
; a5=reader, a4=contentAddr[], d2=hidx, d4=hunkcount, d5=BPTR of 1st segment, d6=previous block, d7=scratch.
ls_load_stream:
                movem.l d2-d7/a2-a5,-(sp)
                move.l  a0,a5
                clr.w   LR_EOF(a5)
                moveq   #0,d5
                sub.l   a4,a4
                ; --- HUNK_HEADER ---
                bsr     ls_rdl
                cmp.l   #HUNK_HEADER,d0
                bne     .fail_fmt
                bsr     ls_rdl               ; resident libs
                tst.l   d0
                bne     .fail_fmt            ; != 0 not supported
                bsr     ls_rdl               ; table_size -> d4
                move.l  d0,d4
                beq     .fail_fmt
                cmp.l   #LS_MAXHUNKS,d4
                bhi     .fail_fmt
                bsr     ls_rdl               ; first (must be 0)
                tst.l   d0
                bne     .fail_fmt
                bsr     ls_rdl               ; last
                addq.l  #1,d0                ; hunkcount = last+1
                cmp.l   d4,d0
                bhi     .fail_fmt            ; hunkcount > table_size -> corrupted
                move.l  d0,d4                ; d4 = hunkcount (= number of sizes to read)
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                move.l  d4,d0                ; contentAddr[] (d4 longs)
                lsl.l   #2,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fail_mem
                move.l  d0,a4                ; a4 = contentAddr table
                ; --- allocate each segment + chain ---
                moveq   #0,d2                ; i
                moveq   #0,d6                ; previous block (0 = none)
.alloc_loop:
                cmp.l   d4,d2
                bhs.s   .alloc_done
                bsr     ls_rdl               ; size field (longs + memory flags)
                move.l  d0,d3
                rol.l   #2,d3
                and.l   #3,d3                ; d3 = bits 31-30 -> 1-0: bit0 = CHIP, bit1 = FAST
                cmp.w   #3,d3
                beq     .fail_fmt            ; 11 = extended attributes (V37+) -> not supported in 1.3
                and.l   #$3FFFFFFF,d0
                lsl.l   #2,d0                ; content bytes
                addq.l  #8,d0                ; + header [size][next]
                move.l  d0,d7                ; d7 = alloc size (saved)
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                btst    #0,d3
                beq.s   .no_chip
                or.l    #MEMF_CHIP,d1        ; CHIP hunk (program's BSS/DMA data)
.no_chip:
                btst    #1,d3
                beq.s   .no_fast
                or.l    #MEMF_FAST,d1
.no_fast:
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fail_mem            ; alloc failed -> free the segments already done
                move.l  d0,a0                ; a0 = block
                move.l  d7,(a0)              ; block[0] = alloc size
                move.l  a0,d1
                addq.l  #8,d1                ; contents = block+8
                move.l  d2,d0
                lsl.l   #2,d0
                move.l  d1,0(a4,d0.l)        ; contentAddr[i] = block+8
                move.l  a0,d1
                addq.l  #4,d1
                lsr.l   #2,d1                ; d1 = BPTR_i = (block+4)>>2
                tst.l   d6
                bne.s   .chain
                move.l  d1,d5                ; 1st -> BPTR to return
                bra.s   .chain_prev
.chain:
                move.l  d6,a0
                move.l  d1,4(a0)             ; prev_block[4] = BPTR_i
.chain_prev:
                move.l  d1,d6
                lsl.l   #2,d6
                subq.l  #4,d6                ; d6 = this block (= BPTR<<2 - 4)
                addq.l  #1,d2
                bra.s   .alloc_loop
.alloc_done:
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                ; --- body: contents + relocations, up to the end of the data ---
                moveq   #0,d2                ; hidx = 0 (first==0 validated)
.body_loop:
                bsr     ls_rdl               ; hunk id
                tst.w   LR_EOF(a5)
                bne     .body_done           ; file consumed
                and.l   #$3FFFFFFF,d0        ; the id carries a copy of the memory flags (e.g. $400003EB = chip BSS)
                cmp.l   #HUNK_CODE,d0
                beq.s   .b_content
                cmp.l   #HUNK_DATA,d0
                beq.s   .b_content
                cmp.l   #HUNK_BSS,d0
                beq.s   .b_bss
                cmp.l   #HUNK_RELOC32,d0
                beq     .b_reloc
                cmp.l   #HUNK_END,d0
                beq.s   .b_end
                cmp.l   #HUNK_NAME,d0
                beq.s   .b_skip
                cmp.l   #HUNK_DEBUG,d0
                beq.s   .b_skip
                cmp.l   #HUNK_SYMBOL,d0
                beq.s   .b_symbol
                bra     .fail_fmt            ; unsupported hunk ($3FC, overlay...) -> clean failure
.b_skip:                                     ; NAME / DEBUG: [nlongs][data] ignored
                bsr     ls_rdl
                lsl.l   #2,d0
                bsr     ls_skip
                bra.s   .b_chk
.b_symbol:                                   ; SYMBOL: ([name nlongs][name][value])* then 0, ignored
                bsr     ls_rdl
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                tst.l   d0
                beq.s   .body_loop
                addq.l  #1,d0                ; name + value
                lsl.l   #2,d0
                bsr     ls_skip
                bra.s   .b_symbol
.b_bss:
                bsr     ls_rdl               ; nlongs (no data; memory already CLEAR)
                bra.s   .b_chk
.b_end:
                addq.l  #1,d2                ; next hunk
                bra     .body_loop
.b_content:
                cmp.l   d4,d2
                bhs     .fail_fmt            ; more content hunks than declared -> corrupted
                bsr     ls_rdl               ; nlongs
                move.l  d2,d1
                lsl.l   #2,d1
                move.l  0(a4,d1.l),a0        ; dest = contentAddr[hidx]
                lsl.l   #2,d0
                bsr     ls_rdbytes
.b_chk:
                tst.w   LR_EOF(a5)
                bne     .fail_fmt            ; end of data in the middle of a hunk
                bra     .body_loop
.b_reloc:
                bsr     ls_rdl               ; count
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                tst.l   d0
                beq     .body_loop           ; 0 -> end of the RELOC32 block
                move.l  d0,d7                ; d7 = count
                cmp.l   d4,d2
                bhs     .fail_fmt            ; RELOC32 outside a declared hunk -> corrupted
                bsr     ls_rdl               ; referenced hunk
                cmp.l   d4,d0
                bhs     .fail_fmt            ; reference to a nonexistent hunk -> corrupted
                lsl.l   #2,d0
                move.l  0(a4,d0.l),d3        ; d3 = contentAddr[ref] (addend)
                move.l  d2,d0
                lsl.l   #2,d0
                move.l  0(a4,d0.l),a2        ; a2 = contentAddr[hidx] (base to patch)
.rl_off:
                bsr     ls_rdl               ; offset within the current hunk
                tst.w   LR_EOF(a5)
                bne     .fail_fmt
                ifeq    D2_NO_RELOC
                add.l   d3,0(a2,d0.l)        ; *(contentAddr[hidx]+offset) += contentAddr[ref]
                endc                         ; RED D2_NO_RELOC: skips the application (offset still read)
                subq.l  #1,d7
                bne.s   .rl_off
                bra.s   .b_reloc             ; next (count,ref,offsets) block
.body_done:
                move.l  a4,a1                ; success: free contentAddr (temp)
                move.l  d4,d0
                lsl.l   #2,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d5,d0                ; return BPTR of 1st segment
                bra.s   .ret
.fail_mem:
                moveq   #ERROR_NO_FREE_STORE,d7
                bra.s   .fail
.fail_fmt:
                moveq   #ERROR_FILE_NOT_OBJECT,d7
.fail:
                move.l  d5,d0                ; free the segments already allocated (BPTR chain)
                bsr     dos_unloadseg
                move.l  a4,d0
                beq.s   .fail_ret
                move.l  a4,a1                ; free contentAddr
                move.l  d4,d0
                lsl.l   #2,d0
                jsr     LVO_FREEMEM(a6)
.fail_ret:
                move.l  d7,d1
                moveq   #0,d0
.ret:
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ls_rdl(a5 = reader) -> d0 = next long (0 and LR_EOF set if bytes are missing). Clobbers d1/a0/a1.
ls_rdl:
                clr.l   -(sp)
                move.l  sp,a0
                moveq   #4,d0
                bsr.s   ls_rdbytes
                move.l  (sp)+,d0
                rts

; ls_skip(d0 = bytes, a5 = reader): skips d0 bytes (re-read into the buffer). Clobbers d0/d1/a0/a1.
ls_skip:
                sub.l   a0,a0                ; null destination: nothing is copied
; ls_rdbytes(a0 = destination | 0, d0 = bytes, a5 = reader): copies d0 bytes from the stream; LR_EOF set if the stream
; ends before that. Clobbers d0/d1/a0/a1.
ls_rdbytes:
                movem.l d2-d3/a2,-(sp)
                move.l  a0,a2                ; a2 = destination
                move.l  d0,d2                ; d2 = remaining to read
.rb_lp:
                tst.l   d2
                beq.s   .rb_ret
                move.l  LR_LEN(a5),d1
                sub.l   LR_POS(a5),d1        ; d1 = available in the buffer
                bne.s   .rb_copy
                tst.l   LR_FH(a5)
                beq.s   .rb_eof
                move.l  a2,d0                ; buffer empty, large block to a real destination: direct Read
                beq.s   .rb_fill
                cmp.l   LR_CAP(a5),d2
                blo.s   .rb_fill
                move.l  d2,d3
                bsr.s   ls_read              ; d0 = bytes read into (a2)
                tst.l   d0
                ble.s   .rb_eof
                add.l   d0,a2
                sub.l   d0,d2
                bra.s   .rb_lp
.rb_fill:
                move.l  a2,-(sp)
                move.l  LR_BUF(a5),a2
                move.l  LR_CAP(a5),d3
                bsr.s   ls_read
                move.l  (sp)+,a2
                clr.l   LR_POS(a5)
                move.l  d0,LR_LEN(a5)
                bgt.s   .rb_lp
                clr.l   LR_LEN(a5)
.rb_eof:
                st      LR_EOF(a5)
.rb_ret:
                movem.l (sp)+,d2-d3/a2
                rts
.rb_copy:
                cmp.l   d2,d1
                bls.s   .rb_n
                move.l  d2,d1                ; d1 = bytes taken from the buffer
.rb_n:
                sub.l   d1,d2
                move.l  LR_BUF(a5),a0
                add.l   LR_POS(a5),a0
                add.l   d1,LR_POS(a5)
                move.l  a2,d0
                beq.s   .rb_lp               ; skip: nothing to copy
.rb_cp:
                move.b  (a0)+,(a2)+
                subq.l  #1,d1
                bne.s   .rb_cp
                bra.s   .rb_lp

; ls_read(a2 = destination, d3 = bytes, a5 = reader) -> d0 = Read(LR_FH, a2, d3) via LR_DOS. Clobbers d0/d1/a0/a1.
ls_read:
                movem.l d2/a6,-(sp)
                move.l  LR_DOS(a5),a6
                move.l  LR_FH(a5),d1
                move.l  a2,d2
                jsr     DOS_LVO_READ(a6)
                movem.l (sp)+,d2/a6
                rts

; dos_unloadseg(a6=SysBase, d0=BPTR of 1st segment): frees the segment chain (FreeMem block+size). d0=0 -> no-op.
dos_unloadseg:
                movem.l d2,-(sp)
                move.l  d0,d2                ; d2 = current BPTR
.ul_loop:
                tst.l   d2
                beq.s   .ul_done
                move.l  d2,d0
                lsl.l   #2,d0                ; d0 = BPTR<<2 = &next (= block+4)
                move.l  d0,a1
                move.l  (a1),d2              ; d2 = next BPTR (read before freeing)
                subq.l  #4,d0
                move.l  d0,a1                ; a1 = block
                move.l  (a1),d0              ; d0 = size (block[0])
                jsr     LVO_FREEMEM(a6)
                bra.s   .ul_loop
.ul_done:
                movem.l (sp)+,d2
                rts
