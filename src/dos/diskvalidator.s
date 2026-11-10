; src/dos/diskvalidator.s - OFS disk-validator: dv_validate (#4, boot proof) checks the allocation bitmap of DF0:;
; dv_rebuild rebuilds the bitmap of a volume whose root says it is not valid (file system handler, at mount).
;
; The real AmigaDOS disk-validator revalidates a floppy whose bitmap is flagged invalid (bm_flag=0) by
; rebuilding the bitmap from the directory tree. Scope #4 (bounded): INTEGRITY CHECK of the bitmap
; of a valid disk - (1) OFS checksum of the rootblock (sum of the 128 longs == 0), (2) sec_type = ST_ROOT,
; (3) bm_flag == $FFFFFFFF (bitmap flagged valid), (4) OFS checksum of the bitmap block, (5) CONSISTENCY: the
; rootblock (880) must be marked ALLOCATED (bit=0) in the bitmap. Returns valid/invalid. Reconstruction
; (bm_flag=0 -> rebuild) is deferred.
;
; Public OFS format + test ADF (asset): bitmap bits LSB-first, idx = block-2, long[1+idx/32] bit (idx%32),
; 1=free / 0=allocated. Via trackdisk CMD_READ (M6z). IMPLEMENTATION track: ADF-FAQ / AmigaDOS Tech Ref. NO ROM reading.

                include "exec.i"
                include "disk.i"
                include "ofs.i"

                xdef    dv_validate
                xdef    dv_rebuild
                xref    ofs_geo              ; ofs.s
                xref    ofs_hash
                xref    ow_rd                ; ofswrite.s
                xref    ow_keyok
                xref    ow_bmbit
                xref    vr_req               ; dos_lib.s: three-line system requester (Retry / Cancel)

; dv_validate(a6 = SysBase) -> d0 = 1 (valid disk) | 0 (invalid / no disk). Clobbers scratch + d2-d7/a2-a4 (saved).
dv_validate:
                movem.l d2-d7/a2-a4,-(sp)
                moveq   #0,d7                        ; d7 = result (invalid by default)
                lea     EB_DEVICELIST(a6),a0
                lea     dv_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .dv_ret                      ; no trackdisk
                move.l  d0,a2                        ; a2 = trackdisk base
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .dv_ret
                move.l  d0,a3                        ; a3 = ioreq; buffer = a3+IOREQ_SZ
                move.l  #OFS_ROOTBLK,d0              ; 1. read the rootblock (880)
                bsr     dv_read_block
                tst.l   d0
                beq     .dv_free                     ; read failed (no disk)
                lea     IOREQ_SZ(a3),a4              ; a4 = buffer
                bsr     dv_checksum                  ; OFS rootblock checksum: sum of longs == 0?
                tst.l   d0
                bne     .dv_free                     ; rootblock checksum failed
                cmp.l   #OFS_ST_ROOT,OFSB_SECTYPE(a4)
                bne     .dv_free                     ; not a rootblock
                move.l  OFSB_BMFLAG(a4),d0           ; 3. bm_flag == $FFFFFFFF?
                addq.l  #1,d0                        ; -1 + 1 = 0
                bne     .dv_free                     ; bitmap flagged invalid (revalidation deferred)
                move.l  OFSB_BMPAGES(a4),d5          ; d5 = bitmap block
                cmp.l   #2,d5
                blo     .dv_free
                cmp.l   #OFS_NBLK,d5
                bhs     .dv_free                     ; bitmap block number out of bounds
                move.l  d5,d0                        ; 4. read the bitmap block
                bsr     dv_read_block
                tst.l   d0
                beq     .dv_free
                lea     IOREQ_SZ(a3),a4
                ifne    DV_CORRUPT
                eori.b  #$FF,OFSB_BMBITS(a4)         ; RED: corrupts the bitmap -> checksum fails
                endc
                bsr     dv_checksum                  ; OFS checksum of the bitmap block
                tst.l   d0
                bne     .dv_free                     ; bitmap corrupted
                ; 5. consistency: rootblock (880) marked ALLOCATED in the bitmap.
                ; idx = 880-2 = 878; long index = 1 + 878/32 = 28 (byte 112);
                ; bit = 878 mod 32 = 14 (LSB-first); 0=allocated
                move.l  112(a4),d0                   ; long[28] of the bitmap block
                btst    #14,d0
                bne     .dv_free                     ; bit=1 (free) -> inconsistent: the root must be allocated
                moveq   #1,d7                        ; all checks pass -> valid disk
.dv_free:
                move.l  a3,a1
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
.dv_ret:
                move.l  d7,d0
                movem.l (sp)+,d2-d7/a2-a4
                rts

; dv_checksum(a4 = 512-byte block) -> d0 = sum of the 128 longs (0 = valid OFS checksum). Clobbers d0/d1/a0.
dv_checksum:
                move.l  a4,a0
                moveq   #0,d0
                move.w  #(OFS_BSIZE/4)-1,d1          ; 127 iterations
.cs_lp:
                add.l   (a0)+,d0
                dbra    d1,.cs_lp
                rts

; dv_read_block(d0=block, a2=trackdisk, a3=ioreq, a6=SysBase) -> d0 = 1 OK / 0 failed; fills a3+IOREQ_SZ.
; Scratch d0/d1/a0/a1 (BeginIO preserves d2-d7/a2-a5) -> the state of dv_validate survives.
dv_read_block:
                lsl.l   #8,d0
                lsl.l   #1,d0                        ; offset = block * 512
                move.l  a2,IO_DEVICE(a3)
                move.w  #CMD_READ,IO_COMMAND(a3)
                move.l  #OFS_BSIZE,IO_LENGTH(a3)
                lea     IOREQ_SZ(a3),a0
                move.l  a0,IO_DATA(a3)
                move.l  d0,IO_OFFSET(a3)
                move.b  #IOF_QUICK,IO_FLAGS(a3)
                clr.l   IO_ACTUAL(a3)
                move.l  a6,-(sp)
                move.l  a2,a6
                move.l  a3,a1
                jsr     -30(a6)                      ; BeginIO (trackdisk, -30)
                move.l  (sp)+,a6
                tst.b   IO_ERROR(a3)
                bne.s   .rb_fail
                cmp.l   #OFS_BSIZE,IO_ACTUAL(a3)
                bne.s   .rb_fail
                moveq   #1,d0
                rts
.rb_fail:
                moveq   #0,d0
                rts

dv_td_name:
                dc.b    "trackdisk.device",0
                even

; ------------------------------------------------------------------------------------------------------------------
; dv_rebuild(a5 = write context with its bitmap table and keys (ow_bmalloc), root block in OW_B1, a6) -> d0 = 1 / 0:
; validation of a volume whose root says "bitmap not valid" (spec rom-filesystem §2.3, dos-lvo-partial §1.4): the
; bitmap is rebuilt from the directory tree: every block free, then the root, the bitmap blocks and their extension
; blocks, and for each object reachable from the root its header, and for a file its extension blocks and the data
; blocks their tables list (OFS data blocks are not read: their keys are in the tables). A key outside the
; partition, a header with a bad checksum, type, key or parent, or a key met twice stops the walk with the requester
; "Error validating disk" / <volume> / "Key <n> out of range" (or "checksum error", "already used"), then
; "Disk structure corrupt" / "Use DISKDOCTOR to correct it"; Retry on either walks again, Cancel fails (the caller
; leaves the volume not validated: 213). The walk keeps no stack: it goes back up through the parent keys and finds
; its place in the parent from the hash of the name, as ExNext does. OW_B2 is the work buffer.
DV_RANGE        EQU 0                ; error kinds -> third line of the first requester
DV_CKSUM        EQU 1
DV_TWICE        EQU 2
dv_rebuild:
        movem.l d2-d7/a2-a4,-(sp)
.rb_again:
        bsr     dv_walk              ; d0 = 1 / 0, d1 = key, d2 = kind
        tst.l   d0
        bne.s   .rb_ret
        bsr     dv_tellbad           ; d0 = 1: Retry
        tst.l   d0
        bne.s   .rb_again
.rb_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; dv_walk(a5, a6) -> d0 = 1 rebuilt | 0 with d1 = key, d2 = DV_* kind. Clobbers d3-d7/a2-a4.
dv_walk:
        move.l  OW_BMTAB(a5),a2      ; every bit free, every bitmap block to be written
        move.l  OW_BMN(a5),d3
        bra.s   .wk_fnx
.wk_fill:
        st      BME_DIRTY(a2)
        lea     BME_DATA+4(a2),a0
        moveq   #127-1,d1
.wk_fl:
        move.l  #-1,(a0)+
        dbra    d1,.wk_fl
        lea     BME_SIZE(a2),a2
.wk_fnx:
        dbra    d3,.wk_fill
        bsr     ofs_geo
        move.l  GEO_ROOT(a0),d4      ; d4 = current directory
        move.l  d4,d0
        bsr     dv_mark
        beq     .wk_bad
        move.l  OW_BMTAB(a5),a2      ; the bitmap blocks
        move.l  OW_BMN(a5),d3
        bra.s   .wk_bnx
.wk_bm:
        move.l  BME_KEY(a2),d0
        bsr     dv_mark
        beq     .wk_bad
        lea     BME_SIZE(a2),a2
.wk_bnx:
        dbra    d3,.wk_bm
        move.l  OW_BMN(a5),d3        ; their extension blocks: one per 127 keys beyond the root's 25
        sub.l   #25,d3
        move.l  OW_B1+OFSB_BMEXT(a5),d5
.wk_ext:
        tst.l   d3
        ble.s   .wk_tree
        move.l  d5,d0
        bsr     dv_mark
        beq     .wk_bad
        move.l  d5,d0
        bsr     dv_read              ; no checksum in a bitmap extension block
        beq     .wk_bad
        move.l  OW_B2+OFS_BSIZE-4(a5),d5
        sub.l   #127,d3
        bra.s   .wk_ext
.wk_tree:
        moveq   #0,d5                ; d5 = next hash slot of the directory, d6 = next entry key | 0
        moveq   #0,d6
.wk_loop:
        tst.l   d6
        bne.s   .wk_entry
        move.l  d4,d0                ; next non-empty slot of the directory
        bsr     dv_read
        beq     .wk_bad
.wk_slot:
        cmp.l   #OFS_HTDEF,d5
        bhs.s   .wk_up
        move.l  d5,d0
        addq.l  #1,d5
        lsl.l   #2,d0
        lea     OW_B2+OFSB_HASHTAB(a5),a0
        move.l  0(a0,d0.l),d6
        beq.s   .wk_slot
        bra.s   .wk_loop
.wk_up:                              ; directory done: back to its parent, after its own entry
        bsr     ofs_geo
        cmp.l   GEO_ROOT(a0),d4
        beq     .wk_done
        move.l  OW_B2+OFSB_HASHCHAIN(a5),d6
        move.l  OW_B2+OFSB_PARENT(a5),d4
        lea     OW_B2+OFSB_NAME(a5),a0   ; slot of its name in the parent's table
        lea     OW_NAME(a5),a4
        moveq   #0,d0
        move.b  (a0)+,d0
        cmp.w   #30,d0
        bls.s   .wk_nl
        moveq   #30,d0
.wk_nl:
        move.l  a4,a1
        bra.s   .wk_nn
.wk_nc:
        move.b  (a0)+,(a1)+
.wk_nn:
        dbra    d0,.wk_nc
        clr.b   (a1)
        moveq   #OFS_HTDEF,d3
        jsr     ofs_hash             ; d1 = slot
        move.l  d1,d5
        addq.l  #1,d5
        bra     .wk_loop
.wk_entry:
        move.l  d6,d0
        bsr     dv_mark
        beq     .wk_bad
        move.l  d6,d0
        bsr     dv_header            ; checksum, type, key; parent = d4
        beq     .wk_bad
        move.l  d6,d7                ; d7 = this entry
        move.l  OW_B2+OFSB_HASHCHAIN(a5),d6
        move.l  OW_B2+OFSB_SECTYPE(a5),d0
        cmp.l   #OFS_ST_USERDIR,d0
        bne.s   .wk_file
        move.l  d7,d4                ; a directory: walked now, its chain resumed on the way up
        moveq   #0,d5
        moveq   #0,d6
        bra     .wk_loop
.wk_file:
        cmp.l   #OFS_ST_FILE,d0
        bne.s   .wk_cks              ; neither a file nor a directory
.wk_tab:                             ; data blocks of this table, then the next extension block
        lea     OW_B2+OFSB_HASHTAB(a5),a3
        moveq   #OFS_HTDEF-1,d3
.wk_tl:
        move.l  (a3)+,d0
        beq.s   .wk_tn
        move.l  d0,d7
        bsr     dv_mark
        beq.s   .wk_badd7
.wk_tn:
        dbra    d3,.wk_tl
        move.l  OW_B2+OFSB_EXTENSION(a5),d7
        beq     .wk_loop
        move.l  d7,d0
        bsr     dv_mark
        beq.s   .wk_badd7
        move.l  d7,d0
        bsr     dv_read
        beq.s   .wk_badd7
        bsr     dv_cksum
        bne.s   .wk_cksd7
        cmp.l   #16,OW_B2+OFSB_TYPE(a5)     ; T_LIST
        bne.s   .wk_cksd7
        bra.s   .wk_tab
.wk_cksd7:
        move.l  d7,d1
        moveq   #DV_CKSUM,d2
        bra.s   .wk_fail
.wk_badd7:
        move.l  d7,d1
        bra.s   .wk_bad
.wk_cks:
        move.l  d7,d1
        moveq   #DV_CKSUM,d2
        bra.s   .wk_fail
.wk_done:
        moveq   #1,d0
        rts
.wk_bad:                             ; d1 = key, d2 = kind (from dv_mark / dv_read / dv_header)
.wk_fail:
        moveq   #0,d0
        rts

; dv_mark(d0 = key, a5) -> Z = 0 if the key was free and inside the partition, now marked used; Z = 1 with d1 = key,
; d2 = DV_RANGE / DV_TWICE otherwise. Clobbers d0/a0/a1.
dv_mark:
        move.l  d0,d1
        movem.l d1,-(sp)
        jsr     ow_keyok
        movem.l (sp)+,d1             ; (movem keeps the flags)
        beq.s   .mk_range
        move.l  d1,d0
        move.l  d1,-(sp)
        jsr     ow_bmbit             ; a0 = long, d1 = bit
        move.l  (a0),d0
        bclr    d1,d0
        movem.l (sp)+,d1             ; Z of bclr: the bit was already clear (used)
        beq.s   .mk_twice
        move.l  d0,(a0)
        moveq   #1,d0
        rts
.mk_twice:
        moveq   #DV_TWICE,d2
        moveq   #0,d0
        rts
.mk_range:
        moveq   #DV_RANGE,d2
        moveq   #0,d0
        rts
; dv_read(d0 = key, a5) -> Z = 0 read into OW_B2; Z = 1 with d1 = key, d2 = DV_CKSUM (unreadable). Clobbers d0/a0/a1.
dv_read:
        move.l  d0,-(sp)
        lea     OW_B2(a5),a0
        jsr     ow_rd
        move.l  (sp)+,d1
        moveq   #DV_CKSUM,d2
        tst.l   d0
        rts
; dv_cksum(a5) -> Z = 1 if the sum of the longs of OW_B2 is 0. Clobbers d0/d1/a0.
dv_cksum:
        lea     OW_B2(a5),a0
        moveq   #0,d0
        moveq   #OFS_BSIZE/4-1,d1
.ck_lp:
        add.l   (a0)+,d0
        dbra    d1,.ck_lp
        tst.l   d0
        rts
; dv_header(d0 = key, d4 = directory expected as its parent, a5) -> Z = 0 if the block is a valid header in OW_B2;
; Z = 1 with d1 = key, d2 = DV_CKSUM otherwise. Clobbers d0/a0/a1.
dv_header:
        move.l  d0,-(sp)
        bsr.s   dv_read
        beq.s   .hd_bad
        bsr.s   dv_cksum
        bne.s   .hd_bad
        cmp.l   #OFS_T_SHORT,OW_B2+OFSB_TYPE(a5)
        bne.s   .hd_bad
        move.l  (sp),d0
        cmp.l   OW_B2+4(a5),d0       ; header key = its own block
        bne.s   .hd_bad
        cmp.l   OW_B2+OFSB_PARENT(a5),d4
        bne.s   .hd_bad
        addq.l  #4,sp
        moveq   #1,d0
        rts
.hd_bad:
        move.l  (sp)+,d1
        moveq   #DV_CKSUM,d2
        moveq   #0,d0
        rts

; dv_tellbad(d1 = key, d2 = kind, a5 = root block in OW_B1, a6) -> d0 = 1 if Retry: "Error validating disk" /
; <volume> / "Key <n> <kind>", then "Disk structure corrupt" / "Use DISKDOCTOR to correct it" (Retry / Cancel each;
; dos-lvo-partial §1.4). Retry on the first one retries at once. Clobbers d1-d5/a0-a4.
dv_tellbad:
        lea     -40(sp),sp           ; third line: "Key " + decimal + text
        move.l  sp,a1
        lea     dv_key(pc),a0
.tb_k:
        move.b  (a0)+,(a1)+
        bne.s   .tb_k
        subq.l  #1,a1
        move.l  d1,d0
        bsr     dv_dec
        lea     dv_range(pc),a0
        cmp.w   #DV_RANGE,d2
        beq.s   .tb_t
        lea     dv_cks(pc),a0
        cmp.w   #DV_CKSUM,d2
        beq.s   .tb_t
        lea     dv_twice(pc),a0
.tb_t:
        move.b  (a0)+,(a1)+
        bne.s   .tb_t
        lea     OW_B1+OFSB_NAME(a5),a4
        moveq   #0,d3
        move.b  (a4)+,d3
        lea     dv_err1(pc),a0
        move.l  sp,a1
        moveq   #0,d0
        jsr     vr_req
        tst.l   d0
        bne.s   .tb_ret
        lea     dv_corrupt(pc),a0    ; two lines: no volume name
        lea     dv_empty(pc),a4
        moveq   #0,d3
        lea     dv_doctor(pc),a1
        moveq   #0,d0
        jsr     vr_req
.tb_ret:
        lea     40(sp),sp
        rts
; dv_dec(d0 = unsigned value, a1 = destination) -> a1 after the digits (no NUL). Clobbers d0/d1/a0.
dv_dec:
        lea     -12(sp),sp
        move.l  sp,a0
.dc_lp:
        move.l  d0,d1                ; d0 / 10 in two 16-bit steps (32-bit value)
        clr.w   d1
        swap    d1
        divu    #10,d1
        move.w  d1,-(sp)             ; high quotient
        move.w  d0,d1
        divu    #10,d1               ; (remainder:low word) / 10
        swap    d1
        move.b  d1,(a0)+             ; remainder = digit
        swap    d1
        move.w  d1,d0
        swap    d0
        move.w  (sp)+,d0
        swap    d0                   ; d0 = quotient
        tst.l   d0
        bne.s   .dc_lp
.dc_out:
        move.b  -(a0),d1
        add.b   #'0',d1
        move.b  d1,(a1)+
        cmp.l   sp,a0
        bne.s   .dc_out
        lea     12(sp),sp
        rts
dv_key:         dc.b    "Key ",0
dv_range:       dc.b    " out of range",0
dv_cks:         dc.b    " checksum error",0
dv_twice:       dc.b    " already set",0
dv_err1:        dc.b    "Error validating disk",0
dv_corrupt:     dc.b    "Disk structure corrupt",0
dv_doctor:      dc.b    "Use DISKDOCTOR to correct it",0
dv_empty:       dc.b    0
                even
