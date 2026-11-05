; src/dos/ofswrite.s - OFS writing for the floppy handlers: creation of files and directories, write streams,
; deletion, renaming/moving, protection, comment, disk information. Blocks go through
; the device of the handler's partition (trackdisk: CMD_WRITE into its track cache; CMD_UPDATE at the end of each
; operation). The bitmap may span several blocks (bm_pages, then bitmap extension blocks) on a hard-disk partition.
; Public OFS format (ADF-FAQ / AmigaDOS Technical Reference): header (type 2, key = its own block, high_seq, first_data,
; data block table filled from the end, size, name, hash chain, parent, extension, secondary
; type), data block (type 8, header key, sequence number, size, next, 488 bytes), extension block
; (type 16), bitmap (bit set = free block, bit 0 of long 1 = block 2, checksum at long 0), checksum of the
; other blocks at long 5 (sum of all longs = 0).
; IMPLEMENTATION track ("clean"): public format + dos AutoDocs. NO ROM reading.

                include "exec.i"
                include "ofs.i"
                include "disk.i"
                include "dospkt.i"

                xdef    ow_create
                xdef    ow_delete
                xdef    ow_rename
                xdef    ow_setfield
                xdef    ow_diskinfo
                xdef    ow_inhibit
                xdef    ws_open
                xdef    ws_openold
                xdef    ws_write
                xdef    ws_read
                xdef    ws_seek
                xdef    ws_close
                xdef    ws_discard
                xdef    ow_relabel
                xdef    ow_ready
                xref    ofs_name_to_block
                xref    ofs_hash
                xref    ofs_namecmp
                xref    ofs_geo              ; ofs.s: geometry of the handler's partition
                xref    dv_rebuild           ; diskvalidator.s: bitmap rebuilt from the directory tree
                xdef    ow_mount
                xdef    ow_rd                ; for the validator
                xdef    ow_keyok
                xdef    ow_bmbit
                xref    dos_now              ; dos_lib.s: system time as a DateStamp
                xref    hnd_busy             ; handler.s: lock conflict check (spec rom-filesystem §3.1)

OFS_T_LIST      EQU 16               ; extension block
OFSB_KEY        EQU 4                ; key (the block itself)
OFSB_HIGHSEQ    EQU 8                ; header: blocks in its table; data: sequence number
OFSB_EXT        EQU 504              ; next extension block
OFS_TABN        EQU 72               ; table entries of a header / of an extension
OFSB_TABEND     EQU OFSB_HASHTAB+(OFS_TABN-1)*4  ; last entry = first data block
WS_MAGICV       EQU $57524954        ; "WRIT": write state (the read state starts with the trackdisk base)
ID_VALIDATED    EQU 82
ID_VALIDATING   EQU 81
OFSB_VDAYS      EQU 472              ; root: date of the last modification of the disk

; write context (one per file-handler, allocated on first need; pointer in HC_OWCTX of its context): OW_* in ofs.i.

; write state of an open file (FINDOUTPUT, FINDUPDATE): a position anywhere in [0, size]. Every data block but the
; last holds OFS_DMAX bytes, so block index = position / OFS_DMAX. Block tables: group 0 = the header's, group
; g >= 1 = the g-th extension block; only the last group grows.
WS_MAGIC        EQU 0
WS_SIZE         EQU 8                ; file size (highest position written)
WS_NBLK         EQU 12               ; data blocks
WS_CUR          EQU 16               ; data block held in DBUF (0 = none)
WS_CURIDX       EQU 20               ; its index in the file
WS_EXT          EQU 24               ; extension block held in XBUF
WS_EXTN         EQU 28               ; entries in the last group's table
WS_FIRST        EQU 32               ; first data block
WS_POS          EQU 40               ; (WS_VOL at 36: ofs.i) current position
WS_GRP          EQU 44               ; index of the last group
WS_XGRP         EQU 48               ; group held in XBUF (0 = none)
WS_DDIRTY       EQU 52               ; DBUF modified
WS_XDIRTY       EQU 56               ; XBUF modified
WS_MOD          EQU 60               ; file modified: header rewritten at close
WS_HBUF         EQU 68               ; (WS_LOCK at 64: ofs.i)
WS_XBUF         EQU WS_HBUF+OFS_BSIZE
WS_DBUF         EQU WS_XBUF+OFS_BSIZE
WS_SIZEOF       EQU WS_DBUF+OFS_BSIZE

; ------------------------------------------------------------------------------------------------------------------
; ow_ctx(a6) -> a5 = context of this file-handler (allocated on first call, bitmap not read yet, requests on the
; handler's device, unit and partition); Z = 1 if impossible. Clobbers d0/d1/a0/a1.
ow_ctx:
        bsr.s   ow_slot
        beq.s   .cx_ret              ; not a file-handler
        move.l  (a0),d0
        bne.s   .cx_have
        tst.l   HC_TDIO+IO_DEVICE-HC_OWCTX(a0)
        beq.s   .cx_ret              ; device not opened
        move.l  a0,-(sp)
        move.l  #OW_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a0
        tst.l   d0
        beq.s   .cx_ret
        move.l  d0,a5
        move.l  HC_TDIO+IO_DEVICE-HC_OWCTX(a0),OW_TD(a5)
        move.l  HC_TDIO+IO_UNIT-HC_OWCTX(a0),OW_IO+IO_UNIT(a5)
        move.l  HC_GEO+GEO_PORT-HC_OWCTX(a0),OW_IO+MN_REPLYPORT(a5)
        move.l  a5,(a0)
        move.l  a5,d0
.cx_have:
        move.l  d0,a5
.cx_ret:
        rts
; ow_slot(a6) -> a0 = &HC_OWCTX of the calling file-handler; Z = 1 (a0 = 0) if the task is not one. Preserves d0-d1.
ow_slot:
        move.l  EB_THISTASK(a6),a0
        move.l  TC_USERDATA(a0),a0
        cmpa.w  #0,a0
        beq.s   .sl_ret
        lea     HC_OWCTX(a0),a0
.sl_ret:
        rts

; ow_io(d0 = block, a0 = buffer, d1.w = command, a5, a6) -> d0 = 1 ok / 0 (OW_ERR set): one 512-byte block at
; (partition offset + 512 * block), through DoIO; the write-back countdown is re-armed. Preserves d2-d7/a2-a6.
ow_io:
        movem.l a2-a3,-(sp)
        move.l  a0,a2                ; a2 = buffer
        bsr     ofs_geo
        move.l  a0,a3                ; a3 = geometry
        lea     OW_IO(a5),a1
        move.l  OW_TD(a5),IO_DEVICE(a1)
        move.w  d1,IO_COMMAND(a1)
        move.l  a2,IO_DATA(a1)
        move.l  #OFS_BSIZE,IO_LENGTH(a1)
        lsl.l   #8,d0
        add.l   d0,d0
        add.l   GEO_POFF(a3),d0
        move.l  d0,IO_OFFSET(a1)
        clr.l   IO_ACTUAL(a1)
        moveq   #3,d0
        move.l  d0,GEO_TICKS(a3)
        jsr     LVO_DOIO(a6)
        movem.l (sp)+,a2-a3
        lea     OW_IO(a5),a1
        move.b  IO_ERROR(a1),d0
        beq.s   .io_ok
        move.l  #ERROR_DISK_WRITE_PROTECTED,d1
        cmp.b   #28,d0
        beq.s   .io_err
        move.l  #ERROR_OBJECT_NOT_FOUND,d1
.io_err:
        move.l  d1,OW_ERR(a5)
        moveq   #0,d0
        rts
.io_ok:
        moveq   #1,d0
        rts
ow_rd:
        moveq   #CMD_READ,d1
        bra.s   ow_io
; ow_wr(d0 = block, a0 = buffer): checksum set (long 5), then written to the device.
ow_wr:
        move.l  d0,-(sp)
        bsr     ow_cksum
        move.l  (sp)+,d0
        moveq   #CMD_WRITE,d1
        bra.s   ow_io
; ow_mount(a6) -> d0 = 1 validated / 0: a DOS disk was mounted: the bitmap of the previous one is forgotten and
; this one's is loaded, or rebuilt when its root says it is not valid (ow_bmload). Preserves d2-d7/a2-a6.
ow_mount:
        movem.l d2-d7/a2-a5,-(sp)
        moveq   #0,d0
        bsr     ow_ctx
        beq.s   .mt_ret
        bsr     ow_bmfree
        bsr     ow_bmload
.mt_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts
; ow_inhibit(d0 = Arg1 of ACTION_INHIBIT, a6): inhibit -> modified bitmap written (the disk is about to be rewritten by
; someone else, DiskCopy); release -> bitmap forgotten, re-read on next access (the disk may have changed).
; Preserves d2-d7/a2-a6.
ow_inhibit:
        move.l  a5,-(sp)
        move.l  d0,-(sp)
        bsr     ow_ctx
        beq.s   .ih_ret
        tst.l   (sp)
        beq.s   .ih_off
        bsr.s   ow_sync
        bra.s   .ih_ret
.ih_off:
        bsr     ow_bmfree
.ih_ret:
        addq.l  #4,sp
        move.l  (sp)+,a5
        rts

; ow_sync(a5) -> d0 = 1 ok / 0: the modified bitmap blocks written, then CMD_UPDATE (cached tracks to the disk).
ow_sync:
        bsr.s   ow_bmwrite
        tst.l   d0
        beq.s   .sy_ret
        moveq   #0,d0
        lea     OW_B2(a5),a0
        moveq   #CMD_UPDATE,d1
        bra     ow_io
.sy_ret:
        rts
; ow_bmwrite(a5) -> d0 = 1 ok / 0: the bitmap blocks modified since written (checksum at long 0).
ow_bmwrite:
        movem.l d2/a2,-(sp)
        moveq   #1,d0
        tst.l   OW_BMST(a5)
        ble.s   .sy_ret              ; no bitmap in memory: nothing of it to write
        move.l  OW_BMTAB(a5),a2
        move.l  OW_BMN(a5),d2
        bra.s   .sy_nx
.sy_lp:
        tst.b   BME_DIRTY(a2)
        beq.s   .sy_next
        sf      BME_DIRTY(a2)
        lea     BME_DATA(a2),a0      ; checksum at long 0
        clr.l   (a0)
        moveq   #0,d0
        moveq   #127,d1
.sy_sum:
        add.l   (a0)+,d0
        dbra    d1,.sy_sum
        neg.l   d0
        move.l  d0,BME_DATA(a2)
        move.l  BME_KEY(a2),d0
        lea     BME_DATA(a2),a0
        moveq   #CMD_WRITE,d1
        bsr     ow_io
        tst.l   d0
        beq.s   .sy_ret
.sy_next:
        lea     BME_SIZE(a2),a2
.sy_nx:
        dbra    d2,.sy_lp
        moveq   #1,d0
.sy_ret:
        movem.l (sp)+,d2/a2
        rts
; ow_cksum(a0 = block): long 5 = -(sum of the other longs). Preserves a0 and d2-d7.
ow_cksum:
        clr.l   OFSB_CKSUM(a0)
        move.l  a0,a1
        moveq   #0,d0
        moveq   #127,d1
.ck_sum:
        add.l   (a1)+,d0
        dbra    d1,.ck_sum
        neg.l   d0
        move.l  d0,OFSB_CKSUM(a0)
        rts

; ow_bmfree(a5, a6): the bitmap in memory is forgotten (state "not read"). Preserves d2-d7/a2-a6.
ow_bmfree:
        move.l  OW_BMTAB(a5),d0
        beq.s   .bf_st
        move.l  d0,a1
        move.l  OW_BMN(a5),d0
        mulu    #BME_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        clr.l   OW_BMTAB(a5)
.bf_st:
        clr.l   OW_BMST(a5)
        clr.l   OW_HINT(a5)
        rts

; ow_bmload(a5) -> d0 = 1 ok / 0 (OW_ERR): the bitmap of the volume is read once and kept: one bitmap block per
; OFS_BMBITS_N blocks of the partition, designated by bm_pages (25 in the root block) then by bitmap extension
; blocks (root long 104: 127 keys, the next extension in the last long). A root flagged "bitmap not valid" (or a
; bitmap block with a bad checksum) is validated: the bitmap is rebuilt from the directory tree (dv_rebuild) and,
; unless the disk is write-protected (then it stays in memory, as on 1.3: writes get 214, not 213), written back
; with the root flagged valid. A failed validation leaves the volume not validated: 213 until the next mount.
ow_bmload:
        tst.l   OW_BMST(a5)
        bgt     .bl_ok
        bmi     .bl_nv
        movem.l d2-d4/a2-a3,-(sp)
        bsr     ofs_geo
        move.l  GEO_ROOT(a0),d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq     .bl_ret
        bsr     ow_bmalloc           ; d0 = 1 / 0: table, keys from the root and its extensions
        tst.l   d0
        beq     .bl_bmerr
        moveq   #-1,d0
        cmp.l   OW_B1+OFSB_BMFLAG(a5),d0
        bne.s   .bl_rebuild          ; bitmap not validated
        move.l  OW_BMTAB(a5),a2
        move.l  OW_BMN(a5),d2
        bra.s   .bl_rnx
.bl_rlp:
        move.l  BME_KEY(a2),d0
        lea     BME_DATA(a2),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .bl_rebuild
        lea     BME_DATA(a2),a0
        moveq   #0,d0
        moveq   #127,d1
.bl_sum:
        add.l   (a0)+,d0
        dbra    d1,.bl_sum
        tst.l   d0
        bne.s   .bl_rebuild          ; bitmap block checksum
        lea     BME_SIZE(a2),a2
.bl_rnx:
        dbra    d2,.bl_rlp
        bra.s   .bl_valid
.bl_rebuild:
        jsr     dv_rebuild
        tst.l   d0
        beq.s   .bl_failed
        bsr     ofs_geo
        tst.l   GEO_WPROT(a0)
        bne.s   .bl_valid            ; read-only disk: validated in memory only
        bsr     ow_writeback
        tst.l   d0
        beq.s   .bl_failed
.bl_valid:
        move.l  #1,OW_BMST(a5)
        moveq   #1,d0
.bl_ret:
        movem.l (sp)+,d2-d4/a2-a3
        rts
.bl_bmerr:                           ; no memory: tried again later; a bad bitmap key: not validated
        cmp.l   #ERROR_NO_FREE_STORE,OW_ERR(a5)
        beq.s   .bl_ret
.bl_failed:
        bsr     ow_bmfree
        move.l  #-1,OW_BMST(a5)
        move.l  #ERROR_DISK_NOT_VALIDATED,OW_ERR(a5)
        moveq   #0,d0
        bra.s   .bl_ret
.bl_nv:
        move.l  #ERROR_DISK_NOT_VALIDATED,OW_ERR(a5)
        moveq   #0,d0
        rts
.bl_ok:
        moveq   #1,d0
        rts

; ow_writeback(a5, root block in OW_B1, a6) -> d0 = 1 / 0: the modified bitmap blocks, then the root block with its
; bitmap flagged valid and the disk's modification date (longs 118-120, boot-clock-v34 §5) set to now, then
; CMD_UPDATE (cached tracks to the disk).
ow_writeback:
        bsr     ow_bmwrite
        tst.l   d0
        beq.s   .wb_ret
        move.l  #-1,OW_B1+OFSB_BMFLAG(a5)
        lea     OW_B1+OFSB_VDAYS(a5),a0
        jsr     dos_now
        bsr     ofs_geo
        move.l  GEO_ROOT(a0),d0
        lea     OW_B1(a5),a0
        bsr     ow_wr
        tst.l   d0
        beq.s   .wb_ret
        moveq   #0,d0
        lea     OW_B2(a5),a0
        moveq   #CMD_UPDATE,d1
        bsr     ow_io
.wb_ret:
        rts

; ow_bmalloc(a5, root block in B1) -> d0 = 1 / 0 (OW_ERR: 103 no memory, 213 a key outside the partition): the
; bitmap table (OW_BMN entries, cleared) and the key of each bitmap block. B2 holds the last extension read.
; Clobbers d1-d4/a0-a3.
ow_bmalloc:
        bsr     ofs_geo
        move.l  GEO_NBLK(a0),d0
        sub.l   GEO_RES(a0),d0
        add.l   #OFS_BMBITS_N-1,d0
        divu    #OFS_BMBITS_N,d0
        and.l   #$FFFF,d0
        move.l  d0,OW_BMN(a5)
        move.l  d0,d2                ; d2 = bitmap blocks
        mulu    #BME_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  #ERROR_NO_FREE_STORE,OW_ERR(a5)
        move.l  d0,OW_BMTAB(a5)
        beq.s   .ba_fail
        move.l  d0,a2
        lea     OW_B1+OFSB_BMPAGES(a5),a3   ; a3 = next key, d3 = keys left in this block
        moveq   #25,d3
        move.l  OW_B1+OFSB_BMEXT(a5),d4     ; d4 = next extension
        bra.s   .ba_nx
.ba_lp:
        tst.l   d3
        bne.s   .ba_key
        move.l  d4,d0                ; this block's keys are used up: next extension
        bsr     ow_keyok
        beq.s   .ba_range
        move.l  d4,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .ba_free
        lea     OW_B2(a5),a3
        moveq   #127,d3
        move.l  OW_B2+OFS_BSIZE-4(a5),d4
.ba_key:
        move.l  (a3)+,d0
        subq.l  #1,d3
        move.l  d0,BME_KEY(a2)
        bsr     ow_keyok
        beq.s   .ba_range
        lea     BME_SIZE(a2),a2
.ba_nx:
        dbra    d2,.ba_lp
        moveq   #1,d0
        rts
.ba_range:
        move.l  #ERROR_DISK_NOT_VALIDATED,OW_ERR(a5)
.ba_free:
        move.l  OW_ERR(a5),-(sp)
        bsr     ow_bmfree
        move.l  (sp)+,OW_ERR(a5)
.ba_fail:
        clr.l   OW_BMTAB(a5)
        moveq   #0,d0
        rts
; ow_keyok(d0 = key, a6) -> Z = 0 if inside the partition ([reserved, blocks)). Clobbers d1/a0.
ow_keyok:
        bsr     ofs_geo
        moveq   #0,d1
        cmp.l   GEO_RES(a0),d0
        blo.s   .ko_ret
        cmp.l   GEO_NBLK(a0),d0
        bhs.s   .ko_ret
        moveq   #1,d1
.ko_ret:
        tst.l   d1
        rts

; ow_bmbit(d0 = block, a5) -> a1 = bitmap entry of the block, a0 = its bitmap long, d1 = bit number (bits LSB first,
; bit set = free; index = block - reserved). Clobbers d0.
ow_bmbit:
        bsr     ofs_geo
        sub.l   GEO_RES(a0),d0
        divu    #OFS_BMBITS_N,d0     ; low word: bitmap block, high word: index in it
        moveq   #0,d1
        move.w  d0,d1
        mulu    #BME_SIZE,d1
        move.l  OW_BMTAB(a5),a1
        add.l   d1,a1
        clr.w   d0
        swap    d0
        move.l  d0,d1
        and.w   #31,d1
        lsr.w   #5,d0
        add.w   d0,d0
        add.w   d0,d0
        lea     BME_DATA+4(a1,d0.w),a0
        rts
; ow_scan(d2 = first block, d3 = end (excluded), a5) -> d0 = a free block taken from the bitmap | 0; d2 advanced.
; A long with no free block is skipped as a whole. Clobbers d1/a0/a1.
ow_scan:
        cmp.l   d3,d2
        bhs.s   .sc_none
        move.l  d2,d0
        bsr.s   ow_bmbit
        move.l  (a0),d0
        bne.s   .sc_bit
        moveq   #32,d0               ; no free block in this long: to the next long
        sub.l   d1,d0
        add.l   d0,d2
        bra.s   ow_scan
.sc_bit:
        btst    d1,d0
        bne.s   .sc_got
        addq.l  #1,d2
        bra.s   ow_scan
.sc_got:
        bclr    d1,d0
        move.l  d0,(a0)
        st      BME_DIRTY(a1)
        move.l  d2,d0
        rts
.sc_none:
        moveq   #0,d0
        rts
; ow_alloc(a5) -> d0 = free block taken from the bitmap (the first free one above the root, then from the start) |
; 0. The search above the root starts at OW_HINT (all in use below it), which keeps the cost of a nearly full region
; once and not per block. The bitmap is (re)loaded first: a disk change or an inhibit forgets it while a file may
; still be open for writing.
ow_alloc:
        movem.l d2-d3,-(sp)
        bsr     ow_bmload
        tst.l   d0
        beq.s   .al_ret
        bsr     ofs_geo
        move.l  GEO_ROOT(a0),d2
        addq.l  #1,d2
        cmp.l   OW_HINT(a5),d2
        bhs.s   .al_up
        move.l  OW_HINT(a5),d2
.al_up:
        move.l  GEO_NBLK(a0),d3
        bsr.s   ow_scan
        tst.l   d0
        beq.s   .al_low
        move.l  d2,OW_HINT(a5)       ; ow_scan left d2 on the block taken
        addq.l  #1,OW_HINT(a5)
        bra.s   .al_ret
.al_low:
        move.l  d3,OW_HINT(a5)       ; nothing free above the root
        bsr     ofs_geo              ; second pass: from the start to the root
        move.l  GEO_RES(a0),d2
        move.l  GEO_ROOT(a0),d3
        bsr.s   ow_scan
        tst.l   d0
        bne.s   .al_ret
        move.l  #ERROR_DISK_FULL,OW_ERR(a5)
.al_ret:
        movem.l (sp)+,d2-d3
        rts
; ow_free(d0 = block, a5): the block becomes free again (blocks outside the partition, or no bitmap: ignored).
ow_free:
        tst.l   OW_BMST(a5)
        ble.s   .fr_ret
        move.l  d0,-(sp)
        bsr     ow_keyok
        movem.l (sp)+,d0             ; (movem keeps the Z of ow_keyok)
        beq.s   .fr_ret
        move.l  d0,-(sp)
        bsr     ow_bmbit
        move.l  (a0),d0
        bset    d1,d0
        move.l  d0,(a0)
        st      BME_DIRTY(a1)
        move.l  (sp)+,d0
        cmp.l   OW_HINT(a5),d0
        bhs.s   .fr_ret
        move.l  d0,OW_HINT(a5)       ; free again: the next search above the root starts there
.fr_ret:
        rts

; ow_parent(a0 = path, d0 = starting directory (0 = root), a5) -> d0 = directory containing the object | 0,
; a1 = final name (OW_NAME). The path is cut after its last "/" or ":"; the prefix (separator included:
; "vol:" = root, "/" = parent) is resolved by ofs_name_to_block. A final name longer than 30 characters is truncated
; (spec rom-filesystem §2.2); an empty one designates the lock itself: 205. A prefix through a file, or a parent
; that is not a directory: 212. B2 = the directory.
ow_parent:
        movem.l d2-d3,-(sp)
        move.l  d0,d2
        lea     OW_PATH(a5),a1
        moveq   #OW_PATHMAX-2,d1
        moveq   #0,d3                ; d3 = position after the last separator | 0
.pa_cp:
        move.b  (a0)+,d0
        move.b  d0,(a1)+
        beq.s   .pa_end
        cmp.b   #'/',d0
        beq.s   .pa_sep
        cmp.b   #':',d0
        bne.s   .pa_nx
.pa_sep:
        move.l  a1,d3
.pa_nx:
        dbra    d1,.pa_cp
        clr.b   (a1)
.pa_end:
        lea     OW_PATH(a5),a0       ; a0 = name (the whole path if there is no separator)
        tst.l   d3
        beq.s   .pa_name
        move.l  d3,a0
.pa_name:
        lea     OW_NAME(a5),a1       ; name: up to 30 characters, the rest dropped
        moveq   #30-1,d1
.pa_nc:
        move.b  (a0)+,(a1)+
        dbeq    d1,.pa_nc
        clr.b   (a1)
        lea     OW_NAME(a5),a1
        tst.b   (a1)
        beq.s   .pa_nf
        move.l  d2,d0
        tst.l   d3
        beq.s   .pa_dir
        move.l  d3,a0                ; the prefix ends at the separator, included
        clr.b   (a0)
        lea     OW_PATH(a5),a0
        move.l  d2,d0
        jsr     ofs_name_to_block    ; d1 = its error (205, 212)
.pa_dir:
        tst.l   d0
        bne.s   .pa_rd
        bsr     ofs_geo
        move.l  GEO_ROOT(a0),d0
        tst.l   d3
        bne.s   .pa_err
.pa_rd:
        move.l  d0,d2                ; the parent must be a directory
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .pa_nf
        lea     OW_B2(a5),a0
        move.l  OFSB_SECTYPE(a0),d0
        cmp.l   #OFS_ST_ROOT,d0
        beq.s   .pa_ok
        cmp.l   #OFS_ST_USERDIR,d0
        bne.s   .pa_wt
.pa_ok:
        lea     OW_NAME(a5),a1
        move.l  d2,d0
        bra.s   .pa_ret
.pa_wt:
        move.l  #ERROR_OBJECT_WRONG_TYPE,d1
        bra.s   .pa_err
.pa_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,d1
.pa_err:
        move.l  d1,OW_ERR(a5)
        moveq   #0,d0
.pa_ret:
        movem.l (sp)+,d2-d3
        rts

; ow_lookup(d0 = directory, a1 = name, a5) -> d0 = block of the object | 0; d2 = predecessor in the chain (0 = the
; directory's table), d3 = hash index. B2 holds the object found. Clobbers d1/a0/a1/a4.
ow_lookup:
        movem.l d4-d5,-(sp)
        move.l  d0,d4                ; d4 = directory
        move.l  a1,a4
        moveq   #OFS_HTDEF,d3
        jsr     ofs_hash             ; d1 = index
        move.l  d1,d3
        move.l  d4,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .lk_no
        lea     OW_B2(a5),a0
        move.l  d3,d0
        lsl.l   #2,d0
        move.l  OFSB_HASHTAB(a0,d0.l),d5 ; d5 = current block
        moveq   #0,d2
.lk_lp:
        move.l  d5,d0
        bsr     ow_keyok
        beq.s   .lk_no
        move.l  d5,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .lk_no
        lea     OW_B2+OFSB_NAME(a5),a1
        move.l  a4,a0
        jsr     ofs_namecmp
        beq.s   .lk_hit
        move.l  d5,d2
        move.l  OW_B2+OFSB_HASHCHAIN(a5),d5
        bra.s   .lk_lp
.lk_hit:
        move.l  d5,d0
        bra.s   .lk_ret
.lk_no:
        moveq   #0,d0
.lk_ret:
        movem.l (sp)+,d4-d5
        rts

; ow_unlink(d4 = directory, d5 = object (in B2), d2 = predecessor, d3 = index, a5) -> d0 = 1/0: the object leaves the
; hash chain of its directory. B1 is used, B2 preserved.
ow_unlink:
        move.l  OW_B2+OFSB_HASHCHAIN(a5),-(sp)   ; next of the object
        move.l  d2,d0
        bne.s   .ul_pred
        move.l  d4,d0
.ul_pred:
        move.l  d0,-(sp)
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .ul_fail
        lea     OW_B1(a5),a0
        tst.l   d2
        bne.s   .ul_chain
        move.l  d3,d0
        lsl.l   #2,d0
        move.l  4(sp),OFSB_HASHTAB(a0,d0.l)
        bra.s   .ul_w
.ul_chain:
        move.l  4(sp),OFSB_HASHCHAIN(a0)
.ul_w:
        move.l  (sp),d0
        bsr     ow_wr
        addq.l  #8,sp
        rts
.ul_fail:
        addq.l  #8,sp
        moveq   #0,d0
        rts

; ow_link(d4 = directory, d5 = object, a1 = its name, a5) -> d0 = 1/0: the object (in B1, name/parent already set) goes
; at the end of its index's chain in the directory; the object, the directory (date) and the previous last entry
; are written. B2 is used; d3 is clobbered.
ow_link:
        move.l  a4,-(sp)
        move.l  a1,a4
        moveq   #OFS_HTDEF,d3
        jsr     ofs_hash
        move.l  (sp)+,a4
        lsl.l   #2,d1
        move.l  d2,-(sp)
        move.l  d1,d2                ; d2 = offset of the slot in the table
        move.l  d4,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .lnk_ret
        clr.l   OW_B1+OFSB_HASHCHAIN(a5)
        lea     OW_B2+OFSB_HASHTAB(a5),a0
        move.l  0(a0,d2.l),d3        ; d3 = first entry of the slot | 0
        bne.s   .lnk_obj
        move.l  d5,0(a0,d2.l)        ; empty slot: the new entry heads it
.lnk_obj:
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_wr
        tst.l   d0
        beq.s   .lnk_ret
        lea     OW_B2(a5),a0         ; the directory changes: so does its date
        bsr     ow_stamp
        move.l  d4,d0
        bsr     ow_wr
        tst.l   d0
        beq.s   .lnk_ret
        move.w  #OFS_CHAINMAX,d2     ; bound on the walk (a chain that loops)
.lnk_walk:                           ; otherwise it goes at the end of the chain (spec rom-filesystem §6.3)
        tst.l   d3
        beq.s   .lnk_ok
        move.l  d3,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .lnk_ret
        move.l  OW_B2+OFSB_HASHCHAIN(a5),d0
        beq.s   .lnk_end
        move.l  d0,d3
        dbra    d2,.lnk_walk
        moveq   #0,d0
        bra.s   .lnk_ret
.lnk_end:
        move.l  d5,OW_B2+OFSB_HASHCHAIN(a5)
        move.l  d3,d0
        lea     OW_B2(a5),a0
        bsr     ow_wr
        bra.s   .lnk_ret
.lnk_ok:
        moveq   #1,d0
.lnk_ret:
        move.l  (sp)+,d2
        rts

; ow_setname(a0 = block, a1 = C name): BCPL name (length + characters) at long 108.
ow_setname:
        lea     OFSB_NAME+1(a0),a0
        moveq   #0,d0
.sn_lp:
        move.b  (a1)+,d1
        beq.s   .sn_end
        move.b  d1,(a0)+
        addq.w  #1,d0
        bra.s   .sn_lp
.sn_end:
        sub.l   d0,a0
        move.b  d0,-1(a0)
        rts

; ow_clear(a0 = block): 128 longs set to 0. Preserves a0.
ow_clear:
        move.l  a0,a1
        moveq   #127,d0
.cl_lp:
        clr.l   (a1)+
        dbra    d0,.cl_lp
        rts

; ow_stamp(a0 = header block): modification date (+420) = now; for the root, also the disk's date
; (+472). Preserves everything except d0.
ow_stamp:
        move.l  a0,-(sp)
        lea     OFSB_DAYS(a0),a0
        jsr     dos_now
        move.l  (sp)+,a0
        cmp.l   #OFS_ST_ROOT,OFSB_SECTYPE(a0)
        bne.s   .st_ret
        move.l  a0,-(sp)
        lea     OFSB_VDAYS(a0),a0
        jsr     dos_now
        move.l  (sp)+,a0
.st_ret:
        rts

; ow_touch(d0 = directory, a5) -> d0 = 1/0: the directory (read into B1) gets today's date and is rewritten.
ow_touch:
        move.l  d0,-(sp)
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .to_fail
        lea     OW_B1(a5),a0
        bsr.s   ow_stamp
        move.l  (sp)+,d0
        bra     ow_wr
.to_fail:
        addq.l  #4,sp
        rts

; ow_freeobj(d5 = object (in B2), a5): frees its blocks: header, and for a file its data blocks and extensions.
ow_freeobj:
        movem.l d2-d3/d5,-(sp)
        lea     OW_B2(a5),a0         ; header table copied into B1 (B2 is then used for the extensions)
        lea     OW_B1(a5),a1
        moveq   #127,d0
.fo_cp:
        move.l  (a0)+,(a1)+
        dbra    d0,.fo_cp
        move.l  d5,d0
        bsr     ow_free
        cmp.l   #OFS_ST_FILE,OW_B1+OFSB_SECTYPE(a5)
        bne.s   .fo_ret
.fo_tab:
        lea     OW_B1+OFSB_HASHTAB(a5),a0
        moveq   #OFS_TABN-1,d2
.fo_ent:
        move.l  (a0)+,d0
        move.l  a0,-(sp)
        bsr     ow_free
        move.l  (sp)+,a0
        dbra    d2,.fo_ent
        move.l  OW_B1+OFSB_EXT(a5),d5
        move.l  d5,d0
        bsr     ow_keyok
        beq.s   .fo_ret
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .fo_ret
        move.l  d5,d0
        bsr     ow_free
        bra.s   .fo_tab
.fo_ret:
        movem.l (sp)+,d2-d3/d5
        rts

; ------------------------------------------------------------------------------------------------------------------
; ow_create(a0 = path, d0 = starting directory, d1 = secondary type (file -3 / directory 2), a6) -> d0 = block
; of the new object | 0, d1 = dos error. An existing file of the same name is replaced; a directory is refused.
ow_create:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  d1,d7                ; d7 = secondary type
        move.l  d0,d6
        move.l  a0,a2
        bsr     ow_ctx
        beq     ow_fail0
        bsr     ow_bmload
        beq     ow_fail
        move.l  a2,a0
        move.l  d6,d0
        bsr     ow_parent            ; d0 = directory, a1 = name
        tst.l   d0
        beq     ow_fail
        move.l  d0,d4
        move.l  a1,a3                ; a3 = name
        bsr     ow_lookup
        tst.l   d0
        beq.s   .cr_new
        move.l  d0,d5                ; already exists: FINDOUTPUT replaces it under the rules of DELETE (a file or an
        cmp.l   #OFS_ST_FILE,d7      ; empty directory); CREATE_DIR answers 203, which the spec allows (2.0 does)
        bne.s   .cr_exists
        bsr     ow_canremove
        tst.l   d0
        beq     ow_fail
        bsr     ow_unlink
        tst.l   d0
        beq     ow_fail
        bsr     ow_freeobj
.cr_new:
        bsr     ow_alloc
        tst.l   d0
        beq     ow_fail
        move.l  d0,d5                ; d5 = new block
        lea     OW_B1(a5),a0
        bsr     ow_clear
        move.l  #OFS_T_SHORT,OFSB_TYPE(a0)
        move.l  d5,OFSB_KEY(a0)
        move.l  d4,OFSB_PARENT(a0)
        move.l  d7,OFSB_SECTYPE(a0)
        bsr     ow_stamp
        move.l  a3,a1
        bsr     ow_setname
        move.l  a3,a1
        bsr     ow_link
        tst.l   d0
        beq     ow_fail
        bsr     ow_sync
        tst.l   d0
        beq     ow_fail
        move.l  d5,d0
        moveq   #0,d1
        bra     ow_ret
.cr_exists:
        move.l  #ERROR_OBJECT_EXISTS,OW_ERR(a5)
ow_fail:
        move.l  OW_ERR(a5),d1
        moveq   #0,d0
ow_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts
ow_fail0:
        move.l  #ERROR_OBJECT_NOT_FOUND,d1
        moveq   #0,d0
        bra.s   ow_ret

; ow_delete(a0 = path, d0 = starting directory, a6) -> d0 = -1 / 0, d1 = error. A directory must be empty.
ow_delete:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  d0,d6
        move.l  a0,a2
        bsr     ow_ctx
        beq.s   ow_fail0
        bsr     ow_bmload
        beq.s   ow_fail
        move.l  a2,a0
        move.l  d6,d0
        bsr     ow_parent
        tst.l   d0
        beq.s   ow_fail
        move.l  d0,d4
        bsr     ow_lookup
        tst.l   d0
        beq.s   .de_nf
        move.l  d0,d5
        bsr     ow_canremove
        tst.l   d0
        beq     ow_fail
        bsr     ow_unlink
        tst.l   d0
        beq     ow_fail
        bsr     ow_freeobj
        move.l  d4,d0
        bsr     ow_touch
        tst.l   d0
        beq     ow_fail
        bsr     ow_sync
        tst.l   d0
        beq     ow_fail
        moveq   #-1,d0
        moveq   #0,d1
        bra.s   ow_ret
.de_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
        bra     ow_fail

; ow_ready(a6) -> d0 = 0, or 213 when the disk in the drive has no valid bitmap: the first precondition of every
; modification, checked before any name is looked at (spec rom-filesystem §2.3).
ow_ready:
        movem.l d2-d7/a2-a5,-(sp)
        bsr     ow_ctx
        beq.s   .ry_ok
        bsr     ow_bmload
        bne.s   .ry_ok
        move.l  OW_ERR(a5),d0
        cmp.l   #ERROR_DISK_NOT_VALIDATED,d0
        beq.s   .ry_ret
.ry_ok:
        moveq   #0,d0
.ry_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ow_canremove(d5 = object, read into B2, a5) -> d0 = 1 / 0 with OW_ERR: 202 a lock is held on it (an open file
; holds one), 222 delete bit set, 216 directory not empty. The rules of DELETE_OBJECT (spec rom-filesystem §6.1),
; also applied when FINDOUTPUT replaces an object.
ow_canremove:
        move.l  d5,d0
        moveq   #EXCLUSIVE_LOCK,d1
        jsr     hnd_busy
        tst.l   d0
        bne.s   .cn_err
        move.l  #ERROR_DELETE_PROTECTED,d0
        btst    #0,OW_B2+OFSB_PROTECT+3(a5)
        bne.s   .cn_err
        cmp.l   #OFS_ST_USERDIR,OW_B2+OFSB_SECTYPE(a5)
        bne.s   .cn_ok
        lea     OW_B2+OFSB_HASHTAB(a5),a0
        moveq   #OFS_TABN-1,d1
.cn_em:
        tst.l   (a0)+
        bne.s   .cn_full
        dbra    d1,.cn_em
.cn_ok:
        moveq   #1,d0
        rts
.cn_full:
        move.l  #ERROR_DIRECTORY_NOT_EMPTY,d0
.cn_err:
        move.l  d0,OW_ERR(a5)
        moveq   #0,d0
        rts

; ow_rename(a0 = old path, d0 = its start, a1 = new path, d1 = its start, a6) -> d0 = -1 / 0, d1 = error.
; The object leaves its directory's chain, takes the new name and the new parent, enters the new chain.
ow_rename:
        movem.l d2-d7/a2-a5,-(sp)
        movem.l d1/a1,-(sp)          ; new (start, path)
        move.l  d0,d6
        move.l  a0,a2
        bsr     ow_ctx
        beq     .rn_f0
        bsr     ow_bmload
        beq     .rn_f
        move.l  a2,a0
        move.l  d6,d0
        bsr     ow_parent
        tst.l   d0
        beq     .rn_f
        move.l  d0,d4
        bsr     ow_lookup
        tst.l   d0
        beq     .rn_nf
        move.l  d0,d5                ; d5 = object
        bsr     ow_unlink            ; removed from the old directory (B2 = the object)
        tst.l   d0
        beq     .rn_f
        movem.l (sp),d1/a0           ; new directory and name
        move.l  d1,d0
        bsr     ow_parent
        tst.l   d0
        beq.s   .rn_relink           ; invalid destination: the object goes back where it came from
        move.l  d0,d7
        cmp.l   d5,d0
        beq.s   .rn_self
        move.l  a1,a3
        move.l  d7,d0
        bsr     ow_lookup            ; name already taken -> refused (the object goes back where it came from)
        tst.l   d0
        bne.s   .rn_taken
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq     .rn_f
        lea     OW_B1+OFSB_NAME(a5),a0   ; old name cleared (32 bytes)
        moveq   #7,d0
.rn_cn:
        clr.l   (a0)+
        dbra    d0,.rn_cn
        lea     OW_B1(a5),a0
        move.l  a3,a1
        bsr     ow_setname
        move.l  d7,OW_B1+OFSB_PARENT(a5)
        move.l  d7,d4
        move.l  a3,a1
        bsr     ow_link
        tst.l   d0
        beq.s   .rn_f
        bsr     ow_sync
        tst.l   d0
        beq.s   .rn_f
        addq.l  #8,sp
        moveq   #-1,d0
        moveq   #0,d1
        bra     ow_ret
.rn_self:
        move.l  #ERROR_OBJECT_IN_USE,OW_ERR(a5)    ; a directory moved into itself (spec §6.2)
        bra.s   .rn_relink
.rn_taken:
        move.l  #ERROR_OBJECT_EXISTS,OW_ERR(a5)
.rn_relink:
        move.l  OW_ERR(a5),-(sp)     ; put back into its original directory under its name
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        lea     OW_B1+OFSB_NAME+1(a5),a0   ; C name rebuilt in OW_PATH
        lea     OW_PATH(a5),a1
        moveq   #0,d0
        move.b  OW_B1+OFSB_NAME(a5),d0
        bra.s   .rl_nx
.rl_cp:
        move.b  (a0)+,(a1)+
.rl_nx:
        dbra    d0,.rl_cp
        clr.b   (a1)
        move.l  OW_B1+OFSB_PARENT(a5),d4
        lea     OW_PATH(a5),a1
        bsr     ow_link
        bsr     ow_sync
        move.l  (sp)+,OW_ERR(a5)
        bra.s   .rn_f
.rn_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
.rn_f:
        addq.l  #8,sp
        bra     ow_fail
.rn_f0:
        addq.l  #8,sp
        bra     ow_fail0

; ow_setfield(a0 = path, d0 = start, d1 = 0 protection (d2 = mask) / 1 comment (d2 = BPTR BSTR) / 2 date (d2 = APTR
; DateStamp), a6) -> d0 = -1 / 0, d1 = error: 202 if a lock is held on the object (exclusive access, spec §6.4),
; 220 for a comment longer than 80 characters.
ow_setfield:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  d1,d7
        move.l  d0,d6
        move.l  a0,a2
        move.l  d2,a3
        bsr     ow_ctx
        beq     ow_fail0
        move.l  a2,a0
        move.l  d6,d0
        bsr     ow_parent
        tst.l   d0
        bne.s   .sf_dir
        tst.b   OW_NAME(a5)
        bne     ow_fail
        move.l  #ERROR_OBJECT_WRONG_TYPE,OW_ERR(a5)   ; the root itself (empty name): 212 (spec §6.4)
        bra     ow_fail
.sf_dir:
        bsr     ow_lookup
        tst.l   d0
        beq.s   .sf_nf
        move.l  d0,d5
        moveq   #EXCLUSIVE_LOCK,d1
        jsr     hnd_busy
        tst.l   d0
        bne.s   .sf_err
        lea     OW_B2(a5),a0
        tst.l   d7
        beq.s   .sf_prot
        subq.l  #1,d7
        beq.s   .sf_com
        move.l  (a3)+,OFSB_DAYS(a0)  ; date: the three longs of the DateStamp
        move.l  (a3)+,OFSB_MINS(a0)
        move.l  (a3),OFSB_TICKS(a0)
        bra.s   .sf_w
.sf_prot:
        move.l  a3,OFSB_PROTECT(a0)
        bra.s   .sf_w
.sf_com:
        move.l  a3,d0                ; BSTR comment copied with its length byte
        lsl.l   #2,d0
        move.l  d0,a1
        moveq   #0,d0
        move.b  (a1),d0
        cmp.w   #80,d0
        bhi.s   .sf_long
        lea     OFSB_COMMENT(a0),a0
.sf_cc:
        move.b  (a1)+,(a0)+
        dbra    d0,.sf_cc
.sf_w:
        move.l  d5,d0
        lea     OW_B2(a5),a0
        bsr     ow_wr
        tst.l   d0
        beq     ow_fail
        bsr     ow_sync
        tst.l   d0
        beq     ow_fail
        moveq   #-1,d0
        moveq   #0,d1
        bra     ow_ret
.sf_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
        bra     ow_fail
.sf_long:
        move.l  #ERROR_COMMENT_TOO_BIG,d0
.sf_err:
        move.l  d0,OW_ERR(a5)
        bra     ow_fail

; ow_relabel(a0 = BSTR new volume name, a6) -> d0 = -1 / 0, d1 = error (210: empty, longer than 30 characters, or
; with ':' or '/'): the root block takes the new name (spec rom-filesystem §6.5); the handler renames the node.
ow_relabel:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a2
        bsr     ow_ctx
        beq     ow_fail0
        moveq   #0,d0
        move.b  (a2),d0
        beq.s   .rl_bad
        cmp.w   #30,d0
        bhi.s   .rl_bad
        lea     1(a2),a0
        subq.w  #1,d0
.rl_chk:
        move.b  (a0)+,d1
        cmp.b   #':',d1
        beq.s   .rl_bad
        cmp.b   #'/',d1
        beq.s   .rl_bad
        dbra    d0,.rl_chk
        bsr     ow_bmload            ; a validated disk is in the drive (213 otherwise)
        beq     ow_fail
        bsr     ofs_geo
        move.l  GEO_ROOT(a0),d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq     ow_fail
        lea     OW_B1+OFSB_NAME(a5),a0
        move.l  a2,a1
        moveq   #0,d0
        move.b  (a1),d0
.rl_cp:
        move.b  (a1)+,(a0)+
        dbra    d0,.rl_cp
        bsr     ofs_geo
        move.l  GEO_ROOT(a0),d0
        lea     OW_B1(a5),a0
        bsr     ow_wr
        tst.l   d0
        beq     ow_fail
        bsr     ow_sync
        tst.l   d0
        beq     ow_fail
        moveq   #-1,d0
        moveq   #0,d1
        bra     ow_ret
.rl_bad:
        move.l  #ERROR_INVALID_COMPONENT_NAME,d1
        moveq   #0,d0
        bra     ow_ret

; ow_diskinfo(a0 = InfoData, a1 = volume node (BPTR), a6) -> d0 = -1: disk state (validated), blocks of the partition
; but the reserved ones, used blocks counted in the bitmap, 488 bytes per block, type DOS\0.
ow_diskinfo:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a2
        move.l  a1,d6
        move.l  a2,a0
        moveq   #8,d0
.di_clr:
        clr.l   (a0)+
        dbra    d0,.di_clr
        bsr     ofs_geo
        move.l  GEO_NBLK(a0),d7
        sub.l   GEO_RES(a0),d7       ; d7 = blocks the bitmap covers
        move.l  #ID_VALIDATING,8(a2) ; id_DiskState: validated once the bitmap is in memory
        move.l  d7,12(a2)            ; id_NumBlocks
        move.l  #OFS_DMAX,20(a2)     ; id_BytesPerBlock
        move.l  #$444F5300,24(a2)    ; id_DiskType "DOS\0"
        move.l  d6,28(a2)            ; id_VolumeNode
        bsr     ow_ctx
        beq.s   .di_ret
        bsr     ow_bmload
        beq.s   .di_ret              ; not validated: no used/free figures (dos-lvo-partial §1.4)
        move.l  #ID_VALIDATED,8(a2)
        moveq   #0,d2                ; d2 = free blocks: set bits of the bitmap
        move.l  d7,d3                ; d3 = bits left to count
        move.l  OW_BMTAB(a5),a3
.di_blk:
        lea     BME_DATA+4(a3),a0
        moveq   #127-1,d5            ; longs of this bitmap block
.di_long:
        tst.l   d3
        beq.s   .di_done
        moveq   #32,d4
        cmp.l   d4,d3
        bhs.s   .di_n
        move.l  d3,d4                ; d4 = bits of this long inside the partition
.di_n:
        sub.l   d4,d3
        move.l  (a0)+,d0
        beq.s   .di_nx
        cmp.l   #-1,d0
        bne.s   .di_bits
        cmp.w   #32,d4
        bne.s   .di_bits
        add.l   d4,d2
        bra.s   .di_nx
.di_bits:
        subq.w  #1,d4
.di_bit:
        lsr.l   #1,d0
        bcc.s   .di_used
        addq.l  #1,d2
.di_used:
        dbra    d4,.di_bit
.di_nx:
        dbra    d5,.di_long
        lea     BME_SIZE(a3),a3
        bra.s   .di_blk
.di_done:
        move.l  d7,d0
        sub.l   d2,d0
        move.l  d0,16(a2)            ; id_NumBlocksUsed
.di_ret:
        moveq   #-1,d0
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ------------------------------------------------------------------------------------------------------------------
; ws_alloc(a6) -> a3 = cleared write state with its magic | Z = 1: no memory. Clobbers d0/d1/a0/a1.
ws_alloc:
        move.l  #WS_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a3
        tst.l   d0
        beq     .wa_ret
        move.l  #WS_MAGICV,WS_MAGIC(a3)
.wa_ret:
        rts

; ws_open(a0 = path, d0 = start, a6) -> d0 = write state | 0, d1 = error: creates (or replaces) the file.
ws_open:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a2
        move.l  d0,d6
        bsr     ws_alloc
        beq     ws_omem
        move.l  a2,a0
        move.l  d6,d0
        moveq   #OFS_ST_FILE,d1
        bsr     ow_create
        tst.l   d0
        beq     ws_ofail
        move.l  d0,WS_HDR(a3)
        st      WS_MOD(a3)
        bsr     ow_slot
        move.l  (a0),a5              ; header (written empty by ow_create) kept in the state
        lea     OW_B1(a5),a0
        lea     WS_HBUF(a3),a1
        moveq   #127,d1
.wo_cp:
        move.l  (a0)+,(a1)+
        dbra    d1,.wo_cp
ws_ook:
        move.l  a3,d0
        moveq   #0,d1
        bra     ws_oret
ws_ofail:
        move.l  d1,-(sp)
        move.l  a3,a1
        bsr     ws_discard
        move.l  (sp)+,d1
        moveq   #0,d0
        bra     ws_oret
ws_omem:
        move.l  #ERROR_NO_FREE_STORE,d1
        moveq   #0,d0
ws_oret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ws_openold(d0 = header block of an existing object, a6) -> d0 = write state | 0, d1 = error: a file opened in place
; (FINDUPDATE) at position 0; nothing is written unless it is modified. A directory gives 212.
ws_openold:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  d0,d6
        bsr     ws_alloc
        beq     ws_omem
        bsr     ow_ctx
        beq     .uo_mem
        move.l  d6,d0
        lea     WS_HBUF(a3),a0
        bsr     ow_rd
        tst.l   d0
        beq     .uo_io
        lea     WS_HBUF(a3),a0
        move.l  #ERROR_OBJECT_WRONG_TYPE,d1
        cmp.l   #OFS_T_SHORT,OFSB_TYPE(a0)
        bne     ws_ofail
        cmp.l   #OFS_ST_FILE,OFSB_SECTYPE(a0)
        bne     ws_ofail
        move.l  OFSB_FILESIZE(a0),d0
        cmp.l   #$FFFF*OFS_DMAX,d0
        bhi     ws_ofail             ; more data blocks than a 16-bit block index: not a header we can follow
        move.l  d6,WS_HDR(a3)
        move.l  OFSB_FIRSTDATA(a0),WS_FIRST(a3)
        move.l  d0,WS_SIZE(a3)
        add.l   #OFS_DMAX-1,d0
        divu    #OFS_DMAX,d0
        and.l   #$FFFF,d0
        move.l  d0,WS_NBLK(a3)       ; full blocks but the last
        moveq   #0,d1
        tst.l   d0
        beq     .uo_grp
        subq.l  #1,d0
        divu    #OFS_TABN,d0
        and.l   #$FFFF,d0
        move.l  d0,d1
.uo_grp:
        move.l  d1,WS_GRP(a3)
        mulu    #OFS_TABN,d1
        move.l  WS_NBLK(a3),d0
        sub.l   d1,d0
        move.l  d0,WS_EXTN(a3)
        bra     ws_ook
.uo_mem:
        move.l  #ERROR_NO_FREE_STORE,d1
        bra     ws_ofail
.uo_io:
        move.l  OW_ERR(a5),d1
        bra     ws_ofail

; ws_discard(a1 = state, a6): the state is freed and nothing is written (also END of a file whose volume is gone).
ws_discard:
        move.l  #WS_SIZEOF,d0
        jmp     LVO_FREEMEM(a6)

; ws_dflush(a3, a5) -> d0 = 1 ok / 0: DBUF written if modified. Clobbers d1/a0/a1.
ws_dflush:
        tst.b   WS_DDIRTY(a3)
        beq     .df_ok
        move.l  WS_CUR(a3),d0
        lea     WS_DBUF(a3),a0
        bsr     ow_wr
        tst.l   d0
        beq     .df_ret
        sf      WS_DDIRTY(a3)
.df_ok:
        moveq   #1,d0
.df_ret:
        rts

; ws_xflush(a3, a5) -> d0 = 1/0: XBUF written if modified, its high_seq = its number of entries. Clobbers d1/a0/a1.
ws_xflush:
        tst.b   WS_XDIRTY(a3)
        beq     .xf_ok
        lea     WS_XBUF(a3),a0
        moveq   #OFS_TABN,d0
        move.l  WS_XGRP(a3),d1
        cmp.l   WS_GRP(a3),d1
        bne     .xf_n
        move.l  WS_EXTN(a3),d0
.xf_n:
        move.l  d0,OFSB_HIGHSEQ(a0)
        move.l  WS_EXT(a3),d0
        bsr     ow_wr
        tst.l   d0
        beq     .xf_ret
        sf      WS_XDIRTY(a3)
.xf_ok:
        moveq   #1,d0
.xf_ret:
        rts

; ws_tab(d0 = group, a3, a5) -> d0 = 1 and a0 = buffer holding that group's table | d0 = 0. An extension is found by
; following the chain from the header. Clobbers d1/a1.
ws_tab:
        lea     WS_HBUF(a3),a0
        tst.l   d0
        beq     .tb_ok
        cmp.l   WS_XGRP(a3),d0
        beq     .tb_x
        movem.l d2-d3,-(sp)
        move.l  d0,d2                ; d2 = group wanted
        bsr     ws_xflush
        tst.l   d0
        beq     .tb_fail
        clr.l   WS_XGRP(a3)
        move.l  WS_HBUF+OFSB_EXT(a3),d3
.tb_lp:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
        tst.l   d3
        beq     .tb_fail             ; chain shorter than the size says
        move.l  d3,d0
        lea     WS_XBUF(a3),a0
        bsr     ow_rd
        tst.l   d0
        beq     .tb_fail
        move.l  d3,WS_EXT(a3)
        addq.l  #1,WS_XGRP(a3)
        move.l  WS_XBUF+OFSB_EXT(a3),d3
        cmp.l   WS_XGRP(a3),d2
        bne     .tb_lp
        movem.l (sp)+,d2-d3
.tb_x:
        lea     WS_XBUF(a3),a0
.tb_ok:
        moveq   #1,d0
        rts
.tb_fail:
        clr.l   WS_XGRP(a3)
        movem.l (sp)+,d2-d3
        moveq   #0,d0
        rts

; ws_dload(d0 = block index, a3, a5) -> d0 = 1/0: DBUF holds that data block (the previous one written if modified).
; Clobbers d1/a0/a1.
ws_dload:
        tst.l   WS_CUR(a3)
        beq     .dl_get
        cmp.l   WS_CURIDX(a3),d0
        bne     .dl_get
        moveq   #1,d0
        rts
.dl_get:
        movem.l d2-d3,-(sp)
        move.l  d0,d2
        bsr     ws_dflush
        tst.l   d0
        beq     .dl_ret
        clr.l   WS_CUR(a3)
        move.l  d2,d0
        divu    #OFS_TABN,d0         ; group, entry
        move.l  d0,d3
        and.l   #$FFFF,d0
        bsr     ws_tab
        tst.l   d0
        beq     .dl_ret
        clr.w   d3
        swap    d3
        lsl.l   #2,d3
        neg.l   d3
        lea     OFSB_TABEND(a0),a0
        move.l  0(a0,d3.l),d3        ; d3 = data block
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
        moveq   #0,d0
        tst.l   d3
        beq     .dl_ret              ; hole in the table
        move.l  d3,d0
        lea     WS_DBUF(a3),a0
        bsr     ow_rd
        tst.l   d0
        beq     .dl_ret
        move.l  d3,WS_CUR(a3)
        move.l  d2,WS_CURIDX(a3)
        moveq   #1,d0
.dl_ret:
        movem.l (sp)+,d2-d3
        rts

; ws_tabadd(d0 = data block, a3, a5) -> d0 = 1/0: the block enters the last table (filled from the end); a full table
; gets a new extension chained from it (an extension that fills up is written).
ws_tabadd:
        movem.l d2-d3,-(sp)
        move.l  d0,d2
        cmp.l   #OFS_TABN,WS_EXTN(a3)
        blo     .ta_put
        bsr     ow_alloc
        move.l  d0,d3                ; d3 = new extension
        beq     .ta_ret
        move.l  WS_GRP(a3),d0
        bsr     ws_tab
        tst.l   d0
        beq     .ta_undo
        move.l  d3,OFSB_EXT(a0)
        tst.l   WS_GRP(a3)
        beq     .ta_hdr              ; the header's link is written at END
        st      WS_XDIRTY(a3)
.ta_hdr:
        bsr     ws_xflush
        tst.l   d0
        beq     .ta_ret
        lea     WS_XBUF(a3),a0
        bsr     ow_clear
        move.l  #OFS_T_LIST,OFSB_TYPE(a0)
        move.l  d3,OFSB_KEY(a0)
        move.l  WS_HDR(a3),OFSB_PARENT(a0)
        move.l  #OFS_ST_FILE,OFSB_SECTYPE(a0)
        move.l  d3,WS_EXT(a3)
        addq.l  #1,WS_GRP(a3)
        move.l  WS_GRP(a3),WS_XGRP(a3)
        clr.l   WS_EXTN(a3)
        st      WS_XDIRTY(a3)
.ta_put:
        move.l  WS_GRP(a3),d0
        bsr     ws_tab
        tst.l   d0
        beq     .ta_ret
        move.l  WS_EXTN(a3),d0
        lsl.l   #2,d0
        neg.l   d0
        lea     OFSB_TABEND(a0),a1
        move.l  d2,0(a1,d0.l)
        addq.l  #1,WS_EXTN(a3)
        tst.l   WS_GRP(a3)
        beq     .ta_ok
        st      WS_XDIRTY(a3)
.ta_ok:
        moveq   #1,d0
.ta_ret:
        movem.l (sp)+,d2-d3
        rts
.ta_undo:
        move.l  d3,d0
        bsr     ow_free
        moveq   #0,d0
        bra     .ta_ret

; ws_append(a3, a5) -> d0 = 1/0: a new data block at index WS_NBLK (the position is at the end of a file whose
; last block is full), linked from the previous last block, entered in the table; DBUF holds it, empty.
ws_append:
        move.l  d2,-(sp)
        bsr     ow_alloc
        move.l  d0,d2                ; d2 = new data block
        beq     .ap_ret
        move.l  WS_NBLK(a3),d0
        beq     .ap_first
        subq.l  #1,d0
        bsr     ws_dload             ; previous last block, linked to the new one
        tst.l   d0
        beq     .ap_free
        move.l  d2,d0
        bsr     ws_tabadd
        tst.l   d0
        beq     .ap_free
        move.l  d2,WS_DBUF+OFSB_NEXT(a3)
        st      WS_DDIRTY(a3)
        bsr     ws_dflush
        tst.l   d0
        beq     .ap_ret
        bra     .ap_init
.ap_first:
        move.l  d2,d0
        bsr     ws_tabadd
        tst.l   d0
        beq     .ap_free
        move.l  d2,WS_FIRST(a3)
.ap_init:
        lea     WS_DBUF(a3),a0
        bsr     ow_clear
        move.l  #OFS_T_DATA,OFSB_TYPE(a0)
        move.l  WS_HDR(a3),OFSB_KEY(a0)
        move.l  WS_NBLK(a3),d0
        move.l  d0,WS_CURIDX(a3)
        addq.l  #1,d0
        move.l  d0,OFSB_HIGHSEQ(a0)  ; sequence number
        move.l  d0,WS_NBLK(a3)
        move.l  d2,WS_CUR(a3)
        st      WS_DDIRTY(a3)
        moveq   #1,d0
.ap_ret:
        move.l  (sp)+,d2
        rts
.ap_free:
        move.l  d2,d0
        bsr     ow_free
        moveq   #0,d0
        bra     .ap_ret

; ws_write(a1 = state, a0 = data, d0 = length, a6) -> d0 = length | -1, d1 = error. Writes at the current position:
; inside the file the bytes are replaced, at its end blocks are added. A zero or negative length writes nothing.
; A write that does not fit returns -1 with position and size unchanged; the blocks it allocated stay in the
; file and are reused by the next writes (disk-full-write-v34 §3.1).
ws_write:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a3
        move.l  a0,a2
        move.l  d0,d7                ; d7 = remaining
        move.l  d0,d6                ; d6 = requested
        move.l  WS_POS(a3),d3        ; d3/a4 = position and size before the call
        move.l  WS_SIZE(a3),a4
        bsr     ow_ctx
        beq     .ww_fail
        tst.l   d7
        bgt     .ww_lp
        moveq   #0,d6
        bra     .ww_ok
.ww_lp:
        move.l  WS_POS(a3),d0
        divu    #OFS_DMAX,d0
        moveq   #0,d5
        swap    d0
        move.w  d0,d5                ; d5 = offset in the block
        clr.w   d0
        swap    d0                   ; d0 = block index
        cmp.l   WS_NBLK(a3),d0
        blo     .ww_have
        bsr     ws_append
        bra     .ww_chk
.ww_have:
        bsr     ws_dload
.ww_chk:
        tst.l   d0
        beq     .ww_fail
        move.l  #OFS_DMAX,d4         ; n = min(room, remaining)
        sub.l   d5,d4
        cmp.l   d7,d4
        bls     .ww_n
        move.l  d7,d4
.ww_n:
        lea     WS_DBUF+OFSB_DATA(a3),a1
        add.l   d5,a1
        move.l  d4,d0
        bra     .ww_cn
.ww_cp:
        move.b  (a2)+,(a1)+
.ww_cn:
        dbra    d0,.ww_cp
        add.l   d4,d5                ; end of the bytes in this block
        cmp.l   WS_DBUF+OFSB_DSIZE(a3),d5
        bls     .ww_ds
        move.l  d5,WS_DBUF+OFSB_DSIZE(a3)
.ww_ds:
        st      WS_DDIRTY(a3)
        st      WS_MOD(a3)
        add.l   d4,WS_POS(a3)
        move.l  WS_POS(a3),d0
        cmp.l   WS_SIZE(a3),d0
        bls     .ww_sz
        move.l  d0,WS_SIZE(a3)
.ww_sz:
        sub.l   d4,d7
        bne     .ww_lp
.ww_ok:
        move.l  d6,d0
        moveq   #0,d1
        bra     ws_rwret
.ww_fail:
        move.l  d3,WS_POS(a3)
        move.l  a4,WS_SIZE(a3)
ws_rwerr:
        moveq   #-1,d0
        move.l  #ERROR_DISK_FULL,d1
        bsr     ow_slot
        beq     ws_rwret
        move.l  (a0),d2
        beq     ws_rwret
        move.l  d2,a5
        move.l  OW_ERR(a5),d1
ws_rwret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ws_read(a1 = state, a0 = dest, d0 = length, a6) -> d0 = bytes read (0 = end of file) | -1, d1 = error: reading at
; the current position of a file open for writing (MODE_READWRITE, or after Seek on a new file).
ws_read:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a3
        move.l  a0,a2
        moveq   #0,d6                ; d6 = bytes read
        move.l  WS_SIZE(a3),d7
        sub.l   WS_POS(a3),d7        ; d7 = min(length, size - position)
        tst.l   d0
        bgt     .wr_len
        moveq   #0,d7
.wr_len:
        cmp.l   d0,d7
        bls     .wr_go
        move.l  d0,d7
.wr_go:
        tst.l   d7
        beq     .wr_ok
        bsr     ow_ctx
        beq     ws_rwerr
.wr_lp:
        move.l  WS_POS(a3),d0
        divu    #OFS_DMAX,d0
        moveq   #0,d5
        swap    d0
        move.w  d0,d5                ; d5 = offset in the block
        clr.w   d0
        swap    d0                   ; d0 = block index
        bsr     ws_dload
        tst.l   d0
        beq     ws_rwerr
        move.l  #OFS_DMAX,d4
        sub.l   d5,d4
        cmp.l   d7,d4
        bls     .wr_n
        move.l  d7,d4
.wr_n:
        lea     WS_DBUF+OFSB_DATA(a3),a0
        add.l   d5,a0
        move.l  d4,d0
        bra     .wr_cn
.wr_cp:
        move.b  (a0)+,(a2)+
.wr_cn:
        dbra    d0,.wr_cp
        add.l   d4,WS_POS(a3)
        add.l   d4,d6
        sub.l   d4,d7
        bne     .wr_lp
.wr_ok:
        move.l  d6,d0
        moveq   #0,d1
        bra     ws_rwret

; ws_seek(a1 = state, d1 = offset, d2 = mode: < 0 from the start, 0 from the current position, > 0 from the end)
; -> d0 = old position | -1 (target outside [0, size]: position unchanged).
ws_seek:
        move.l  WS_POS(a1),d0
        tst.l   d2
        blt     .sk_chk
        beq     .sk_cur
        add.l   WS_SIZE(a1),d1
        bra     .sk_chk
.sk_cur:
        add.l   d0,d1
.sk_chk:
        tst.l   d1
        bmi     .sk_bad
        cmp.l   WS_SIZE(a1),d1
        bhi     .sk_bad
        move.l  d1,WS_POS(a1)
        rts
.sk_bad:
        moveq   #-1,d0
        rts

; ws_close(a1 = state, a6) -> d0 = -1 / 0: if the file was modified, DBUF, XBUF and the header (size, first block,
; entries of its table, date) are written, then the bitmap and the cache; the state is freed.
ws_close:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a3
        moveq   #-1,d7               ; d7 = result
        tst.b   WS_MOD(a3)
        beq     .wc_free
        moveq   #0,d7
        bsr     ow_ctx
        beq     .wc_free
        bsr     ws_dflush
        tst.l   d0
        beq     .wc_free
        bsr     ws_xflush
        tst.l   d0
        beq     .wc_free
        lea     WS_HBUF(a3),a0
        move.l  WS_SIZE(a3),OFSB_FILESIZE(a0)
        move.l  WS_FIRST(a3),OFSB_FIRSTDATA(a0)
        moveq   #OFS_TABN,d0
        tst.l   WS_GRP(a3)
        bne     .wc_hs
        move.l  WS_EXTN(a3),d0
.wc_hs:
        move.l  d0,OFSB_HIGHSEQ(a0)
        bsr     ow_stamp
        move.l  WS_HDR(a3),d0
        bsr     ow_wr
        tst.l   d0
        beq     .wc_free
        bsr     ow_sync
        tst.l   d0
        beq     .wc_free
        moveq   #-1,d7
.wc_free:
        move.l  a3,a1
        bsr     ws_discard
        move.l  d7,d0
        movem.l (sp)+,d2-d7/a2-a5
        rts
