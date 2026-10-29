; src/dos/ofswrite.s - OFS writing for the DF0: handler: creation of files and directories, write streams,
; deletion, renaming/moving, protection, comment, disk information. Blocks go through
; trackdisk.device (CMD_WRITE into its track cache, CMD_UPDATE at the end of each operation).
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
                xdef    ws_write
                xdef    ws_close
                xref    ofs_name_to_block
                xref    ofs_hash
                xref    ofs_namecmp
                xref    dos_now              ; dos_lib.s: system time as a DateStamp

OFS_T_LIST      EQU 16               ; extension block
OFSB_KEY        EQU 4                ; key (the block itself)
OFSB_HIGHSEQ    EQU 8                ; header: blocks in its table; data: sequence number
OFSB_CKSUM      EQU 20
OFSB_EXT        EQU 504              ; next extension block
OFS_TABN        EQU 72               ; table entries of a header / of an extension
OFSB_TABEND     EQU OFSB_HASHTAB+(OFS_TABN-1)*4  ; last entry = first data block
WS_MAGICV       EQU $57524954        ; "WRIT": write state (the read state starts with the trackdisk base)
ID_VALIDATED    EQU 82
OFSB_VDAYS      EQU 472              ; root: date of the last modification of the disk

; write context (a single one, allocated on first need; pointer in DOS_OWCTX)
OW_TD           EQU 0
OW_IO           EQU 4                ; IOStdReq
OW_BMBLK        EQU OW_IO+IOREQ_SZ   ; bitmap block (0 = not read yet)
OW_BMDIRTY      EQU OW_BMBLK+4
OW_ERR          EQU OW_BMDIRTY+4     ; last I/O error (dos code)
OW_BM           EQU OW_ERR+4         ; bitmap (512)
OW_B1           EQU OW_BM+OFS_BSIZE
OW_B2           EQU OW_B1+OFS_BSIZE
OW_PATH         EQU OW_B2+OFS_BSIZE  ; path copy (OW_PATHMAX)
OW_PATHMAX      EQU 128
OW_NAME         EQU OW_PATH+OW_PATHMAX   ; final name (32)
OW_SIZE         EQU OW_NAME+32

; write state of an open file (FINDOUTPUT)
WS_MAGIC        EQU 0
WS_HDR          EQU 4                ; header block
WS_SIZE         EQU 8                ; bytes written
WS_NBLK         EQU 12               ; data blocks
WS_CUR          EQU 16               ; current data block (0 = none)
WS_CURLEN       EQU 20               ; bytes in the current block
WS_EXT          EQU 24               ; current extension (0 = the header's table)
WS_EXTN         EQU 28               ; entries in the current table
WS_FIRST        EQU 32               ; first data block
WS_HBUF         EQU 40               ; (WS_VOL at 36: ofs.i)
WS_XBUF         EQU WS_HBUF+OFS_BSIZE
WS_DBUF         EQU WS_XBUF+OFS_BSIZE
WS_SIZEOF       EQU WS_DBUF+OFS_BSIZE

; ------------------------------------------------------------------------------------------------------------------
; ow_ctx(a6) -> a5 = context (allocated on first call, bitmap not read yet); Z = 1 if impossible. Clobbers d0/d1/a0/a1.
ow_ctx:
        move.l  DOS_OWCTX,d0
        bne.s   .cx_have
        move.l  #OW_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .cx_ret
        move.l  d0,a5
        lea     EB_DEVICELIST(a6),a0
        lea     ow_tdname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,OW_TD(a5)
        beq.s   .cx_free
        move.l  a5,DOS_OWCTX
        move.l  a5,d0
.cx_have:
        move.l  d0,a5
.cx_ret:
        rts
.cx_free:
        move.l  a5,a1
        move.l  #OW_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        rts

; ow_io(d0 = block, a0 = buffer, d1.w = command, a5, a6) -> d0 = 1 ok / 0 (OW_ERR set). Preserves d2-d7/a2-a6.
ow_io:
        move.l  a2,-(sp)
        lea     OW_IO(a5),a1
        move.l  OW_TD(a5),a2
        move.l  a2,IO_DEVICE(a1)
        move.w  d1,IO_COMMAND(a1)
        move.l  a0,IO_DATA(a1)
        move.l  #OFS_BSIZE,IO_LENGTH(a1)
        lsl.l   #8,d0
        add.l   d0,d0
        move.l  d0,IO_OFFSET(a1)
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        clr.l   IO_ACTUAL(a1)
        move.l  a6,-(sp)
        move.l  a2,a6
        jsr     -30(a6)
        move.l  (sp)+,a6
        move.l  (sp)+,a2
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
        moveq   #2,d1                ; CMD_READ
        bra.s   ow_io
; ow_wr(d0 = block, a0 = buffer): checksum set (long 5), then write into the trackdisk cache.
ow_wr:
        move.l  d0,-(sp)
        bsr.s   ow_cksum
        move.l  (sp)+,d0
        moveq   #3,d1                ; CMD_WRITE
        bra.s   ow_io
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
        clr.l   OW_BMBLK(a5)
        clr.l   OW_BMDIRTY(a5)
.ih_ret:
        addq.l  #4,sp
        move.l  (sp)+,a5
        rts

; ow_sync(a5) -> d0 = 1 ok / 0: bitmap written if modified, then CMD_UPDATE (cached tracks to the disk).
ow_sync:
        tst.l   OW_BMDIRTY(a5)
        beq.s   .sy_upd
        clr.l   OW_BMDIRTY(a5)
        lea     OW_BM(a5),a0         ; bitmap checksum at long 0
        clr.l   (a0)
        moveq   #0,d0
        moveq   #127,d1
.sy_sum:
        add.l   (a0)+,d0
        dbra    d1,.sy_sum
        neg.l   d0
        move.l  d0,OW_BM(a5)
        move.l  OW_BMBLK(a5),d0
        lea     OW_BM(a5),a0
        moveq   #3,d1
        bsr     ow_io
        tst.l   d0
        beq.s   .sy_ret
.sy_upd:
        moveq   #0,d0
        lea     OW_B2(a5),a0
        moveq   #4,d1                ; CMD_UPDATE
        bsr     ow_io
.sy_ret:
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

; ow_bmload(a5) -> d0 = 1 ok / 0: the bitmap (designated by the root block) is read once and kept.
ow_bmload:
        tst.l   OW_BMBLK(a5)
        bne.s   .bl_ok
        move.l  #OFS_ROOTBLK,d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .bl_ret
        lea     OW_B1(a5),a0
        moveq   #-1,d0               ; bitmap not validated: no writing
        cmp.l   OFSB_BMFLAG(a0),d0
        bne.s   .bl_nv
        move.l  OFSB_BMPAGES(a0),d0
        move.l  d0,-(sp)
        lea     OW_BM(a5),a0
        bsr     ow_rd
        move.l  (sp)+,d1
        tst.l   d0
        beq.s   .bl_ret
        move.l  d1,OW_BMBLK(a5)
.bl_ok:
        moveq   #1,d0
.bl_ret:
        rts
.bl_nv:
        move.l  #ERROR_DISK_NOT_VALIDATED,OW_ERR(a5)
        moveq   #0,d0
        rts
; ow_bmbit(d0 = block) -> a0 = bitmap long, d1 = bit number. Clobbers d0.
ow_bmbit:
        subq.l  #2,d0
        move.l  d0,d1
        lsr.l   #5,d0
        lsl.l   #2,d0
        lea     OW_BM+4(a5),a0
        add.l   d0,a0
        and.w   #31,d1
        rts
; ow_alloc(a5) -> d0 = free block taken from the bitmap (search from the root, then from the start) | 0.
ow_alloc:
        movem.l d2-d3,-(sp)
        move.l  #OFS_ROOTBLK+1,d2
        move.l  #OFS_NBLK,d3
.al_lp:
        cmp.l   d3,d2
        blo.s   .al_try
        cmp.l   #OFS_NBLK,d3
        bne.s   .al_full
        moveq   #2,d2                ; second pass: from the start to the root
        move.l  #OFS_ROOTBLK,d3
.al_try:
        move.l  d2,d0
        bsr.s   ow_bmbit
        move.l  (a0),d0
        btst    d1,d0
        bne.s   .al_got
        addq.l  #1,d2
        bra.s   .al_lp
.al_got:
        bclr    d1,d0
        move.l  d0,(a0)
        st      OW_BMDIRTY(a5)
        move.l  d2,d0
        bra.s   .al_ret
.al_full:
        move.l  #ERROR_DISK_FULL,OW_ERR(a5)
        moveq   #0,d0
.al_ret:
        movem.l (sp)+,d2-d3
        rts
; ow_free(d0 = block, a5): the block becomes free again (blocks outside the disk ignored).
ow_free:
        cmp.l   #2,d0
        blo.s   .fr_ret
        cmp.l   #OFS_NBLK,d0
        bhs.s   .fr_ret
        bsr.s   ow_bmbit
        move.l  (a0),d0
        bset    d1,d0
        move.l  d0,(a0)
        st      OW_BMDIRTY(a5)
.fr_ret:
        rts

; ow_parent(a0 = path, d0 = starting directory (0 = root), a5) -> d0 = directory containing the object | 0,
; a1 = final name (OW_NAME). The path is cut after its last "/" or ":"; the prefix (separator included:
; "vol:" = root, "/" = parent) is resolved by ofs_name_to_block. Empty name or > 30: failure. B2 = the directory.
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
        lea     OW_NAME(a5),a1       ; name: 1 to 30 characters
        moveq   #30,d1               ; 30 characters + NUL at most
.pa_nc:
        move.b  (a0)+,(a1)+
        dbeq    d1,.pa_nc
        bne.s   .pa_bad
        lea     OW_NAME(a5),a1
        tst.b   (a1)
        beq.s   .pa_bad
        move.l  d2,d0
        tst.l   d3
        beq.s   .pa_dir
        move.l  d3,a0                ; the prefix ends at the separator, included
        clr.b   (a0)
        lea     OW_PATH(a5),a0
        move.l  d2,d0
        jsr     ofs_name_to_block
.pa_dir:
        tst.l   d0
        bne.s   .pa_rd
        move.l  #OFS_ROOTBLK,d0
        tst.l   d3
        bne.s   .pa_nf
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
        bne.s   .pa_nf
.pa_ok:
        lea     OW_NAME(a5),a1
        move.l  d2,d0
        bra.s   .pa_ret
.pa_bad:
        move.l  #ERROR_INVALID_COMPONENT_NAME,OW_ERR(a5)
        moveq   #0,d0
        bra.s   .pa_ret
.pa_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
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
        tst.l   d5
        beq.s   .lk_no
        cmp.l   #OFS_NBLK,d5
        bhs.s   .lk_no
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
; at the head of its index's chain in the directory; the object then the directory are written. B2 is used.
ow_link:
        move.l  a4,-(sp)
        move.l  a1,a4
        moveq   #OFS_HTDEF,d3
        jsr     ofs_hash
        move.l  (sp)+,a4
        lsl.l   #2,d1
        move.l  d1,-(sp)
        move.l  d4,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        move.l  (sp)+,d1
        tst.l   d0
        beq.s   .lnk_ret
        lea     OW_B2(a5),a0
        move.l  OFSB_HASHTAB(a0,d1.l),OW_B1+OFSB_HASHCHAIN(a5)
        move.l  d5,OFSB_HASHTAB(a0,d1.l)
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_wr
        tst.l   d0
        beq.s   .lnk_ret
        lea     OW_B2(a5),a0         ; the directory changes: so does its date
        bsr     ow_stamp
        move.l  d4,d0
        bsr     ow_wr
.lnk_ret:
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
        beq.s   .fo_ret
        cmp.l   #OFS_NBLK,d5
        bhs.s   .fo_ret
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
        move.l  d0,d5                ; already exists: a file is replaced
        cmp.l   #OFS_ST_FILE,d7
        bne.s   .cr_exists
        cmp.l   #OFS_ST_FILE,OW_B2+OFSB_SECTYPE(a5)
        bne.s   .cr_exists
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
        cmp.l   #OFS_ST_USERDIR,OW_B2+OFSB_SECTYPE(a5)
        bne.s   .de_go
        lea     OW_B2+OFSB_HASHTAB(a5),a0  ; directory not empty: refused
        moveq   #OFS_TABN-1,d0
.de_em:
        tst.l   (a0)+
        bne.s   .de_full
        dbra    d0,.de_em
.de_go:
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
.de_full:
        move.l  #ERROR_DIRECTORY_NOT_EMPTY,OW_ERR(a5)
        bra     ow_fail
.de_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
        bra     ow_fail

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

; ow_setfield(a0 = path, d0 = start, d1 = 0 protection (d2 = mask) / 1 comment (d2 = BPTR BSTR), a6) ->
; d0 = -1 / 0, d1 = error.
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
        beq     ow_fail
        bsr     ow_lookup
        tst.l   d0
        beq.s   .sf_nf
        move.l  d0,d5
        lea     OW_B2(a5),a0
        tst.l   d7
        bne.s   .sf_com
        move.l  a3,OFSB_PROTECT(a0)
        bra.s   .sf_w
.sf_com:
        move.l  a3,d0                ; BSTR comment, 79 characters at most
        lsl.l   #2,d0
        move.l  d0,a1
        lea     OFSB_COMMENT(a0),a0
        moveq   #0,d0
        move.b  (a1),d0
        cmp.w   #79,d0
        bls.s   .sf_cl
        moveq   #79,d0
.sf_cl:
        move.b  d0,(a0)+
        addq.l  #1,a1
        bra.s   .sf_cn
.sf_cc:
        move.b  (a1)+,(a0)+
.sf_cn:
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

; ow_diskinfo(a0 = InfoData, a1 = volume node (BPTR), a6) -> d0 = -1: disk state (validated), blocks, used blocks
; counted in the bitmap, 488 bytes per block, type DOS\0.
ow_diskinfo:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a2
        move.l  a1,d6
        move.l  a2,a0
        moveq   #8,d0
.di_clr:
        clr.l   (a0)+
        dbra    d0,.di_clr
        move.l  #ID_VALIDATED,8(a2)  ; id_DiskState
        move.l  #OFS_NBLK-2,12(a2)   ; id_NumBlocks
        move.l  #OFS_DMAX,20(a2)     ; id_BytesPerBlock
        move.l  #$444F5300,24(a2)    ; id_DiskType "DOS\0"
        move.l  d6,28(a2)            ; id_VolumeNode
        bsr     ow_ctx
        beq.s   .di_ret
        bsr     ow_bmload
        beq.s   .di_ret
        moveq   #0,d2                ; free blocks: set bits of the bitmap
        lea     OW_BM+4(a5),a0
        move.w  #OFS_NBLK-2-1,d3
        moveq   #0,d1
.di_bit:
        move.w  d1,d0
        lsr.w   #5,d0
        lsl.w   #2,d0
        move.l  0(a0,d0.w),d0
        move.w  d1,d4
        and.w   #31,d4
        btst    d4,d0
        beq.s   .di_used
        addq.l  #1,d2
.di_used:
        addq.w  #1,d1
        dbra    d3,.di_bit
        move.l  #OFS_NBLK-2,d0
        sub.l   d2,d0
        move.l  d0,16(a2)            ; id_NumBlocksUsed
.di_ret:
        moveq   #-1,d0
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ------------------------------------------------------------------------------------------------------------------
; ws_open(a0 = path, d0 = start, a6) -> d0 = write state | 0, d1 = error: creates (or replaces) the file.
ws_open:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a2
        move.l  d0,d6
        move.l  #WS_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .wo_mem
        move.l  d0,a3                ; a3 = state
        move.l  a2,a0
        move.l  d6,d0
        moveq   #OFS_ST_FILE,d1
        bsr     ow_create
        tst.l   d0
        beq.s   .wo_fail
        move.l  #WS_MAGICV,WS_MAGIC(a3)
        move.l  d0,WS_HDR(a3)
        move.l  DOS_OWCTX,a5         ; header (written empty by ow_create) kept in the state
        lea     OW_B1(a5),a0
        lea     WS_HBUF(a3),a1
        moveq   #127,d1
.wo_cp:
        move.l  (a0)+,(a1)+
        dbra    d1,.wo_cp
        move.l  a3,d0
        moveq   #0,d1
        bra.s   .wo_ret
.wo_fail:
        move.l  d1,-(sp)
        move.l  a3,a1
        move.l  #WS_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,d1
        moveq   #0,d0
        bra.s   .wo_ret
.wo_mem:
        move.l  #ERROR_DISK_FULL,d1
        moveq   #0,d0
.wo_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ws_write(a1 = state, a0 = data, d0 = length, a6) -> d0 = length | -1, d1 = error. Data blocks are filled
; one by one; a full block is written when the next one is allocated (its link to it is then known).
ws_write:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a3
        move.l  a0,a2
        move.l  d0,d7                ; d7 = remaining
        move.l  d0,d6                ; d6 = requested
        bsr     ow_ctx
        beq     .ww_err
.ww_lp:
        tst.l   d7
        beq     .ww_ok
        tst.l   WS_CUR(a3)
        beq.s   .ww_new
        cmp.l   #OFS_DMAX,WS_CURLEN(a3)
        blo.s   .ww_copy
.ww_new:
        bsr     ow_alloc
        tst.l   d0
        beq     .ww_err
        move.l  d0,d5                ; d5 = new block
        move.l  WS_CUR(a3),d0
        beq.s   .ww_first
        lea     WS_DBUF(a3),a0       ; previous block: complete, linked to the new one
        move.l  #OFS_DMAX,OFSB_DSIZE(a0)
        move.l  d5,OFSB_NEXT(a0)
        bsr     ow_wr
        tst.l   d0
        beq     .ww_err
        bra.s   .ww_init
.ww_first:
        move.l  d5,WS_FIRST(a3)
.ww_init:
        lea     WS_DBUF(a3),a0
        bsr     ow_clear
        move.l  #OFS_T_DATA,OFSB_TYPE(a0)
        move.l  WS_HDR(a3),OFSB_KEY(a0)
        addq.l  #1,WS_NBLK(a3)
        move.l  WS_NBLK(a3),OFSB_HIGHSEQ(a0)
        move.l  d5,WS_CUR(a3)
        clr.l   WS_CURLEN(a3)
        move.l  d5,d0
        bsr     ws_tabadd
        tst.l   d0
        beq     .ww_err
.ww_copy:
        move.l  #OFS_DMAX,d4         ; n = min(room, remaining)
        sub.l   WS_CURLEN(a3),d4
        cmp.l   d7,d4
        bls.s   .ww_n
        move.l  d7,d4
.ww_n:
        lea     WS_DBUF+OFSB_DATA(a3),a1
        add.l   WS_CURLEN(a3),a1
        move.l  d4,d0
        bra.s   .ww_cn
.ww_cp:
        move.b  (a2)+,(a1)+
.ww_cn:
        dbra    d0,.ww_cp
        add.l   d4,WS_CURLEN(a3)
        add.l   d4,WS_SIZE(a3)
        sub.l   d4,d7
        bra     .ww_lp
.ww_ok:
        move.l  d6,d0
        moveq   #0,d1
        bra.s   .ww_ret
.ww_err:
        moveq   #-1,d0
        move.l  #ERROR_DISK_FULL,d1
        move.l  DOS_OWCTX,d2
        beq.s   .ww_ret
        move.l  d2,a5
        move.l  OW_ERR(a5),d1
.ww_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ws_tabadd(d0 = data block, a3 = state, a5) -> d0 = 1/0: the block enters the current table (filled from the
; end); a full table causes an extension to be allocated, chained from the header or the previous extension (written).
ws_tabadd:
        move.l  d2,-(sp)
        move.l  d0,d2
        cmp.l   #OFS_TABN,WS_EXTN(a3)
        blo.s   .ta_put
        bsr     ow_alloc             ; new extension
        tst.l   d0
        beq.s   .ta_ret
        move.l  d0,-(sp)
        tst.l   WS_EXT(a3)
        bne.s   .ta_prev
        move.l  d0,WS_HBUF+OFSB_EXT(a3)
        bra.s   .ta_newx
.ta_prev:
        lea     WS_XBUF(a3),a0       ; extension full: linked to the new one and written
        move.l  d0,OFSB_EXT(a0)
        move.l  #OFS_TABN,OFSB_HIGHSEQ(a0)
        move.l  WS_EXT(a3),d0
        bsr     ow_wr
        tst.l   d0
        beq.s   .ta_fail
.ta_newx:
        lea     WS_XBUF(a3),a0
        bsr     ow_clear
        move.l  #OFS_T_LIST,OFSB_TYPE(a0)
        move.l  (sp),OFSB_KEY(a0)
        move.l  WS_HDR(a3),OFSB_PARENT(a0)
        move.l  #OFS_ST_FILE,OFSB_SECTYPE(a0)
        move.l  (sp)+,WS_EXT(a3)
        clr.l   WS_EXTN(a3)
.ta_put:
        lea     WS_HBUF(a3),a0
        tst.l   WS_EXT(a3)
        beq.s   .ta_tab
        lea     WS_XBUF(a3),a0
.ta_tab:
        move.l  WS_EXTN(a3),d0
        lsl.l   #2,d0
        neg.l   d0
        lea     OFSB_TABEND(a0),a0
        move.l  d2,0(a0,d0.l)
        addq.l  #1,WS_EXTN(a3)
        moveq   #1,d0
.ta_ret:
        move.l  (sp)+,d2
        rts
.ta_fail:
        addq.l  #4,sp
        moveq   #0,d0
        bra.s   .ta_ret

; ws_close(a1 = state, a6) -> d0 = -1 / 0: last data block, current extension and header (size, number of
; blocks in its table, first block) written, bitmap and cache flushed; the state is freed.
ws_close:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a3
        moveq   #0,d7                ; d7 = result
        bsr     ow_ctx
        beq.s   .wc_free
        move.l  WS_CUR(a3),d0
        beq.s   .wc_ext
        lea     WS_DBUF(a3),a0
        move.l  WS_CURLEN(a3),OFSB_DSIZE(a0)
        clr.l   OFSB_NEXT(a0)
        bsr     ow_wr
        tst.l   d0
        beq.s   .wc_free
.wc_ext:
        move.l  WS_EXT(a3),d0
        beq.s   .wc_hdr
        lea     WS_XBUF(a3),a0
        move.l  WS_EXTN(a3),OFSB_HIGHSEQ(a0)
        bsr     ow_wr
        tst.l   d0
        beq.s   .wc_free
.wc_hdr:
        lea     WS_HBUF(a3),a0
        move.l  WS_SIZE(a3),OFSB_FILESIZE(a0)
        move.l  WS_FIRST(a3),OFSB_FIRSTDATA(a0)
        move.l  WS_NBLK(a3),d0
        cmp.l   #OFS_TABN,d0
        bls.s   .wc_hs
        moveq   #OFS_TABN,d0
.wc_hs:
        move.l  d0,OFSB_HIGHSEQ(a0)
        bsr     ow_stamp
        move.l  WS_HDR(a3),d0
        bsr     ow_wr
        tst.l   d0
        beq.s   .wc_free
        bsr     ow_sync
        tst.l   d0
        beq.s   .wc_free
        moveq   #-1,d7
.wc_free:
        move.l  a3,a1
        move.l  #WS_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d7,d0
        movem.l (sp)+,d2-d7/a2-a5
        rts

ow_tdname:
        dc.b    "trackdisk.device",0
        even
