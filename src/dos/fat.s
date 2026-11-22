; src/dos/fat.s - FAT12/16/32 volumes, read-only, in the ROM file-handler (handler.s).
;
; hnd_mount hands a partition whose first block is not "DOS\n" to fat_mount: a valid FAT boot sector mounts the volume
; (context fat.i, pointer in HC_GEO+GEO_FAT). From then on the six read entries of ofs.s (name -> key, Examine,
; ExNext, open, read, seek) branch here (ofs_isfat), the handler refuses every modification with 214 (write-protected)
; and asks fat_diskinfo for INFO / DISK_INFO. The handler keeps the rest (packets, locks, volume node, disk change).
;
; Keys: an object's key is the place of its first directory entry, sector * 16 + index (its first long-name entry when
; it has a valid long name), so Examine and ExNext re-read it from the key alone; the root is FAT_ROOTKEY. Names: the
; long name (VFAT, Latin-1, '?' outside it) when it has at most 30 characters, otherwise the 8.3 name; a lookup
; matches either, ignoring case (Latin-1). Data are read sector by sector through the file's state buffer, or straight
; into the caller's buffer for whole sectors of one cluster; no cluster is ever held in memory.
;
; IMPLEMENTATION track ("clean"): Microsoft "FAT: General Overview of On-Disk Format" (fatgen103, public: boot sector
; and BPB, FAT type by cluster count, FSInfo, directory entries, long names and their checksum, dates). Kickstart 1.3
; has no FAT filesystem: there is nothing of the ROM to look at. NO ROM reading.

                include "exec.i"
                include "disk.i"
                include "ofs.i"
                include "fat.i"
                include "dospkt.i"

                xdef    fat_mount
                xdef    fat_unmount
                xdef    fat_name_to_block
                xdef    fat_fill_fib
                xdef    fat_dir_next
                xdef    fat_stream_open
                xdef    fat_stream_read
                xdef    fat_stream_seek
                xdef    fat_diskinfo
                xref    exec_CopyMem

FAT_IDVALID     EQU 82               ; InfoData.id_DiskState ID_VALIDATED (the handler turns it into write-protected)

; ------------------------------------------------------------------------------------------------------------------
; fat_mount(a3 = handler context, its block buffer holding the partition's first block, a6) -> d0 = 1: a FAT volume
; is mounted (context allocated, GEO_ROOT = FAT_ROOTKEY, volume name and date where hnd_findvol reads them) / 0.
; Refused: no boot sector signature or jump, sectors other than 512 bytes, inconsistent BPB, a volume that ends beyond
; 4 GB on the device (io_Offset is a 32-bit byte offset). Preserves d2-d7/a2-a6.
fat_mount:
                movem.l d2-d7/a2-a5,-(sp)
                lea     HC_TDIO+IOREQ_SZ(a3),a2      ; a2 = boot sector
                cmp.b   #$55,510(a2)
                bne     .mn_no
                cmp.b   #$AA,511(a2)
                bne     .mn_no
                cmp.b   #$EB,(a2)
                beq.s   .mn_jmp
                cmp.b   #$E9,(a2)
                bne     .mn_no
.mn_jmp:
                lea     11(a2),a0
                bsr     fat_le16
                cmp.l   #OFS_BSIZE,d0
                bne     .mn_no
                move.l  #FC_SIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .mn_no
                move.l  d0,a5
                moveq   #0,d0
                move.b  13(a2),d0                    ; sectors per cluster: a power of 2
                beq     .mn_free
                move.l  d0,FC_SPC(a5)
                moveq   #-1,d1
.mn_sh:
                addq.l  #1,d1
                lsr.l   #1,d0
                bcc.s   .mn_sh
                tst.l   d0
                bne     .mn_free
                move.l  d1,FC_SHIFT(a5)
                lea     14(a2),a0
                bsr     fat_le16
                move.l  d0,d3                        ; d3 = reserved sectors
                beq     .mn_free
                moveq   #0,d4
                move.b  16(a2),d4                    ; d4 = FATs
                beq     .mn_free
                cmp.b   #2,d4
                bhi     .mn_free
                lea     17(a2),a0
                bsr     fat_le16
                move.l  d0,d5                        ; d5 = root entries (0 on FAT32)
                lea     19(a2),a0
                bsr     fat_le16
                move.l  d0,d6                        ; d6 = sectors of the volume
                bne.s   .mn_tot
                lea     32(a2),a0
                bsr     fat_le32
                move.l  d0,d6
                beq     .mn_free
.mn_tot:
                lea     22(a2),a0
                bsr     fat_le16
                move.l  d0,d7                        ; d7 = sectors per FAT (FAT12/16 field)
                bne.s   .mn_fsz
                lea     36(a2),a0
                bsr     fat_le32
                tst.l   d0
                beq     .mn_free
.mn_fsz:
                move.l  d0,FC_FATSZ(a5)
                move.l  d3,FC_FATSEC0(a5)
                move.l  d3,d1                        ; d1 = reserved + FATs
                add.l   d0,d1
                cmp.b   #1,d4
                beq.s   .mn_one
                add.l   d0,d1
.mn_one:
                move.l  d1,FC_ROOTSEC(a5)
                move.l  d5,d0
                add.l   #15,d0
                lsr.l   #4,d0                        ; 16 entries per sector
                move.l  d0,FC_ROOTN(a5)
                add.l   d0,d1
                move.l  d1,FC_DATA(a5)
                move.l  d6,d0
                sub.l   d1,d0
                bls     .mn_free                     ; no data area
                move.l  FC_SHIFT(a5),d1
                lsr.l   d1,d0
                move.l  d0,FC_NCLUS(a5)
                beq     .mn_free
                move.l  HC_GEO+GEO_POFF(a3),d1       ; the end of the volume must stay below 4 GB
                not.l   d1
                moveq   #9,d0
                lsr.l   d0,d1
                cmp.l   d1,d6
                bhi     .mn_free
                moveq   #12,d0                       ; the cluster count decides the type (fatgen103)
                cmp.l   #4085,FC_NCLUS(a5)
                blo.s   .mn_type
                moveq   #16,d0
                cmp.l   #65525,FC_NCLUS(a5)
                blo.s   .mn_type
                moveq   #32,d0
.mn_type:
                move.l  d0,FC_TYPE(a5)
                moveq   #-1,d0
                move.l  d0,FC_FATSEC(a5)
                move.l  d0,FC_DIRSEC(a5)
                move.l  d0,FC_FREE(a5)
                moveq   #38,d2                       ; d2 = offset of the extended boot signature (FAT12/16)
                cmp.l   #32,FC_TYPE(a5)
                bne     .mn_fixed
                tst.l   d5                           ; FAT32: no fixed root, the 32-bit FAT size
                bne     .mn_free
                tst.l   d7
                bne     .mn_free
                clr.l   FC_ROOTN(a5)
                lea     44(a2),a0
                bsr     fat_le32
                bsr     fat_clok
                beq     .mn_free
                move.l  d0,FC_ROOTCL(a5)
                btst    #7,40(a2)                    ; ExtFlags bit 7: mirroring off, only the active FAT counts
                beq.s   .mn_fsi
                moveq   #15,d0
                and.b   40(a2),d0
                cmp.l   d4,d0
                bhs     .mn_free
                move.l  FC_FATSZ(a5),d1
.mn_act:
                subq.l  #1,d0
                bmi.s   .mn_fsi
                add.l   d1,FC_FATSEC0(a5)
                bra.s   .mn_act
.mn_fsi:
                lea     48(a2),a0
                bsr     fat_le16                     ; FSInfo sector, inside the reserved area
                tst.l   d0
                beq.s   .mn_fsend
                cmp.l   d3,d0
                bhs.s   .mn_fsend
                lea     FC_DIRSEC(a5),a0
                bsr     fat_cache
                beq.s   .mn_fsend
                move.l  a0,a1
                bsr     fat_le32
                cmp.l   #$41615252,d0                ; lead signature "RRaA"
                bne.s   .mn_fsend
                lea     484(a1),a0
                bsr     fat_le32
                cmp.l   #$61417272,d0                ; structure signature "rrAa"
                bne.s   .mn_fsend
                lea     488(a1),a0
                bsr     fat_le32                     ; free count, $FFFFFFFF when unknown
                cmp.l   FC_NCLUS(a5),d0
                bhi.s   .mn_fsend
                move.l  d0,FC_FREE(a5)
.mn_fsend:
                moveq   #66,d2                       ; FAT32 extended boot signature
                bra.s   .mn_label
.mn_fixed:
                tst.l   d5                           ; FAT12/16: a fixed root directory
                beq     .mn_free
.mn_label:
                lea     fat_noname(pc),a0            ; volume name: the root's label entry, else the BPB's, else
                cmp.b   #$29,0(a2,d2.w)              ; "NO NAME"
                bne.s   .mn_bpb
                lea     5(a2,d2.w),a0
.mn_bpb:
                bsr     fat_vname
                lea     1(a2,d2.w),a0                ; volume serial number: told apart in the volume date
                bsr     fat_le32
                move.l  d0,d7
                bsr     fat_vlabel                   ; label entry of the root directory: name and date
                move.l  d7,d0
                swap    d0                           ; the two halves of the serial folded, modulo 3000 ticks
                eor.w   d7,d0
                and.l   #$FFFF,d0
                divu    #3000,d0
                clr.w   d0
                swap    d0
                move.l  d0,FC_VDATE+8(a5)
                lea     OFSB_NAME(a2),a1             ; what hnd_findvol reads: name as a BSTR, date
                lea     FC_VNAME(a5),a0
                moveq   #0,d0
.mn_vn:
                addq.b  #1,d0
                move.b  (a0)+,0(a1,d0.w)
                bne.s   .mn_vn
                subq.b  #1,d0
                move.b  d0,(a1)
                lea     FAT_CDATE(a2),a1
                move.l  FC_VDATE(a5),(a1)+
                move.l  FC_VDATE+4(a5),(a1)+
                move.l  FC_VDATE+8(a5),(a1)
                move.l  HC_GEO+GEO_ROOT(a3),FC_OFSROOT(a5)
                moveq   #FAT_ROOTKEY,d0
                move.l  d0,HC_GEO+GEO_ROOT(a3)
                clr.l   HC_GEO+GEO_DOSTYPE(a3)
                move.l  a5,HC_GEO+GEO_FAT(a3)
                moveq   #1,d0
                bra.s   .mn_ret
.mn_free:
                move.l  a5,a1
                move.l  #FC_SIZE,d0
                jsr     LVO_FREEMEM(a6)
.mn_no:
                moveq   #0,d0
.mn_ret:
                movem.l (sp)+,d2-d7/a2-a5
                rts
fat_noname:
                dc.b    "NO NAME    "
                even

; fat_vname(a0 = 11-character label, a5): FC_VNAME = the label without its trailing spaces ("NO NAME" when empty).
; Clobbers d0/d1/a0/a1.
fat_vname:
                lea     FC_VNAME(a5),a1
                move.l  a1,d1                        ; d1 = just after the last non-space
                moveq   #10,d0
.vn_lp:
                move.b  (a0)+,(a1)+
                cmp.b   #' ',-1(a1)
                beq.s   .vn_sp
                move.l  a1,d1
.vn_sp:
                dbra    d0,.vn_lp
                move.l  d1,a1
                clr.b   (a1)
                tst.b   FC_VNAME(a5)
                bne.s   .vn_ret
                lea     fat_noname(pc),a0
                bra.s   fat_vname
.vn_ret:
                rts

; fat_vlabel(a5): the label entry of the root directory (attribute VOLUME_ID, not a long-name entry), when there is
; one, gives FC_VNAME and FC_VDATE (its write date). Preserves d2-d7/a2-a6.
fat_vlabel:
                movem.l d2-d4,-(sp)
                moveq   #0,d0
                bsr     fat_dirstart
                move.l  d0,d2                        ; d2 = sector
                beq.s   .vl_ret
                move.l  #FAT_DIRMAX,d4
.vl_sec:
                move.l  d2,d0
                lea     FC_DIRSEC(a5),a0
                bsr     fat_cache
                beq.s   .vl_ret
                moveq   #15,d3
.vl_ent:
                subq.l  #1,d4
                beq.s   .vl_ret
                tst.b   (a0)
                beq.s   .vl_ret                      ; end of the directory
                cmp.b   #$E5,(a0)
                beq.s   .vl_nx
                moveq   #$3F,d0
                and.b   11(a0),d0
                cmp.b   #$0F,d0
                beq.s   .vl_nx                       ; a long-name entry
                btst    #3,d0
                bne.s   .vl_hit
.vl_nx:
                lea     32(a0),a0
                dbra    d3,.vl_ent
                move.l  d2,d0
                bsr     fat_dsnext
                move.l  d0,d2
                bne.s   .vl_sec
                bra.s   .vl_ret
.vl_hit:
                move.l  a0,d2
                bsr     fat_vname
                move.l  d2,a0
                lea     22(a0),a0
                bsr     fat_le16
                move.l  d0,d1                        ; time
                move.l  d2,a0
                lea     24(a0),a0
                bsr     fat_le16                     ; date
                lea     FC_VDATE(a5),a1
                bsr     fat_dstamp
.vl_ret:
                movem.l (sp)+,d2-d4
                rts

; fat_unmount(a3 = handler context, a6): the FAT context of a volume mounted before, if any, is freed and GEO_ROOT
; given back (the next disk may be an OFS one). Preserves everything.
fat_unmount:
                movem.l d0-d1/a0-a1,-(sp)
                move.l  HC_GEO+GEO_FAT(a3),d0
                beq.s   .um_ret
                move.l  d0,a1
                move.l  FC_OFSROOT(a1),HC_GEO+GEO_ROOT(a3)
                clr.l   HC_GEO+GEO_FAT(a3)
                move.l  #FC_SIZE,d0
                jsr     LVO_FREEMEM(a6)
.um_ret:
                movem.l (sp)+,d0-d1/a0-a1
                rts

; ------------------------------------------------------------------------------------------------------------------
; Entries called by ofs.s in the handler process (a6 = SysBase): same interfaces as their ofs_* counterparts.

; fat_name_to_block(a0 = NUL-terminated path, d0 = key of the starting directory (0 = root), a6) -> d0 = key | 0,
; d1 = 0 or the error when d0 = 0 (205 not found, 212 path through a file). AmigaDOS paths as in ofs_name_to_block:
; "xxx:" starts from the root, an empty component goes up to the parent, a final '/' after a name is neutral.
; Preserves d2-d7/a2-a6.
fat_name_to_block:
                movem.l d2-d7/a2-a5,-(sp)
                bsr     fat_fc
                lea     -FAT_COMPMAX(sp),sp          ; component buffer
                move.l  d0,d4                        ; d4 = current object
                bne.s   .nb_start
                moveq   #FAT_ROOTKEY,d4
.nb_start:
                move.l  a0,a1
.nb_colon:
                move.b  (a1)+,d0
                beq.s   .nb_nocolon
                cmp.b   #':',d0
                bne.s   .nb_colon
                moveq   #FAT_ROOTKEY,d4
                move.l  a1,a0
.nb_nocolon:
                moveq   #0,d6                        ; d6 = 1 once a component has been processed
                tst.b   (a0)
                beq.s   .nb_hit                      ; empty path: the starting directory
.nb_next:
                move.l  sp,a4
                bsr     fat_split
                move.l  d0,d5                        ; d5 = 1: last component
                tst.b   (a4)
                bne.s   .nb_look
                tst.l   d5
                beq.s   .nb_up                       ; empty in the middle ("/", "//"): parent
                tst.l   d6
                bne.s   .nb_hit                      ; final, after a name ("dir/"): neutral
.nb_up:
                move.l  d4,d0
                bsr     fat_parent
                move.l  d0,d4
                beq.s   .nb_nf                       ; parent of the root
                bra.s   .nb_done
.nb_look:
                move.l  d4,d0
                bsr     fat_keydir                   ; d0 = cluster of the current directory | -1: a file
                tst.l   d0
                bmi.s   .nb_wt
                move.l  a0,-(sp)
                bsr     fat_find
                move.l  (sp)+,a0
                tst.l   d0
                beq.s   .nb_nf
                move.l  FC_KEY(a5),d4
.nb_done:
                moveq   #1,d6
                tst.l   d5
                beq.s   .nb_next
.nb_hit:
                move.l  d4,d0
                moveq   #0,d1
                bra.s   .nb_ret
.nb_wt:
                moveq   #0,d0
                move.l  #ERROR_OBJECT_WRONG_TYPE,d1
                bra.s   .nb_ret
.nb_nf:
                moveq   #0,d0
                move.l  #ERROR_OBJECT_NOT_FOUND,d1
.nb_ret:
                lea     FAT_COMPMAX(sp),sp
                movem.l (sp)+,d2-d7/a2-a5
                rts

; fat_fill_fib(d0 = key, a1 = FileInfoBlock, a6) -> d0 = 1 / 0 (no such object). Preserves d1-d7/a0-a6.
fat_fill_fib:
                movem.l d1-d7/a0-a5,-(sp)
                bsr     fat_fc
                move.l  a1,a4
                move.l  d0,FIB_DISKKEY(a4)
                cmp.l   #FAT_ROOTKEY,d0
                beq.s   .ff_root
                bsr     fat_getobj
                tst.l   d0
                beq.s   .ff_ret
                bsr     fat_fibent
                bra.s   .ff_ok
.ff_root:
                bsr     fat_fibroot
.ff_ok:
                moveq   #1,d0
.ff_ret:
                movem.l (sp)+,d1-d7/a0-a5
                rts

; fat_dir_next(d0 = key of the directory, a1 = FileInfoBlock, a6) -> d0 = 1 (the FIB holds the next entry) / 0 (no
; more). Stateless: the FIB's DiskKey is the entry returned last (the directory itself: start from the first).
; Preserves d1-d7/a0-a6.
fat_dir_next:
                movem.l d1-d7/a0-a5,-(sp)
                bsr     fat_fc
                move.l  a1,a4
                move.l  d0,d4                        ; d4 = directory
                bsr     fat_keydir
                tst.l   d0
                bmi.s   .dx_end
                bsr     fat_dirstart
                move.l  d0,d2                        ; d2/d3 = sector and index of the walk
                beq.s   .dx_end
                moveq   #0,d3
                move.l  FIB_DISKKEY(a4),d0
                cmp.l   d4,d0
                beq.s   .dx_scan
                move.l  d0,d5                        ; go on after the entry returned last
                move.l  d0,d2
                lsr.l   #4,d2
                moveq   #15,d3
                and.l   d0,d3
                bsr     fat_scan
                tst.l   d0
                beq.s   .dx_end
                cmp.l   FC_KEY(a5),d5
                bne.s   .dx_end
.dx_scan:
                bsr     fat_scan
                tst.l   d0
                beq.s   .dx_end
                move.l  FC_KEY(a5),FIB_DISKKEY(a4)
                bsr     fat_fibent
                moveq   #1,d0
                bra.s   .dx_ret
.dx_end:
                moveq   #0,d0
.dx_ret:
                movem.l (sp)+,d1-d7/a0-a5
                rts

; fat_stream_open(a0 = NUL-terminated path, a1 = SS_* state (ofs.i), d0 = starting directory (0 = root), a6) ->
; d0 = 1 / 0 with d1 = 205 or 212. The state's fields: SS_SIZE, SS_HEADER = key, SS_FIRSTDATA and SS_CURBLK = first
; cluster, SS_BLKBASE = file offset of SS_CURBLK, SS_BUFBLK = sector in the block buffer (0 = none). Preserves
; d2-d7/a2-a6.
fat_stream_open:
                movem.l d2-d7/a2-a5,-(sp)
                move.l  a1,a3                        ; a3 = state
                bsr     fat_name_to_block
                tst.l   d0
                beq.s   .so_ret
                bsr     fat_fc
                cmp.l   #FAT_ROOTKEY,d0
                beq.s   .so_dir
                move.l  d0,d4
                bsr     fat_getobj
                tst.l   d0
                beq.s   .so_nf
                btst    #4,FC_ENT+11(a5)
                bne.s   .so_dir
                move.l  d4,SS_HEADER(a3)
                lea     FC_ENT+28(a5),a0
                bsr     fat_le32
                move.l  d0,SS_SIZE(a3)
                bsr     fat_entcl
                move.l  d0,SS_FIRSTDATA(a3)
                move.l  d0,SS_CURBLK(a3)
                clr.l   SS_POS(a3)
                clr.l   SS_BLKBASE(a3)
                clr.l   SS_BUFBLK(a3)
                clr.l   SS_FFS(a3)
                move.l  EB_THISTASK(a6),a0
                move.l  TC_USERDATA(a0),a0
                move.l  HC_TDIO+IO_DEVICE(a0),SS_TRACKDISK(a3)
                moveq   #1,d0
                bra.s   .so_ret
.so_dir:
                moveq   #0,d0
                move.l  #ERROR_OBJECT_WRONG_TYPE,d1
                bra.s   .so_ret
.so_nf:
                moveq   #0,d0
                move.l  #ERROR_OBJECT_NOT_FOUND,d1
.so_ret:
                movem.l (sp)+,d2-d7/a2-a5
                rts

; fat_stream_read(a1 = state, a2 = destination, d0 = length, a6) -> d0 = bytes copied (0 = end of file) | -1 (a read
; failed or the cluster chain ends before the file does, with nothing copied). Preserves d1-d7/a0-a6.
fat_stream_read:
                movem.l d1-d7/a0-a5,-(sp)
                bsr     fat_fc
                move.l  a1,a3                        ; a3 = state
                move.l  a2,a4                        ; a4 = destination
                move.l  d0,d6                        ; d6 = bytes still wanted
                moveq   #0,d5                        ; d5 = bytes copied
                move.l  #OFS_BSIZE,d4
                move.l  FC_SHIFT(a5),d0
                lsl.l   d0,d4                        ; d4 = bytes per cluster
.rd_lp:
                tst.l   d6
                ble     .rd_done
                move.l  SS_POS(a3),d0
                move.l  SS_SIZE(a3),d1
                sub.l   d0,d1                        ; d1 = bytes up to the end of the file
                bls     .rd_done
                move.l  d0,d2
                sub.l   SS_BLKBASE(a3),d2            ; d2 = offset in the current cluster
                cmp.l   d4,d2
                blo.s   .rd_in
                move.l  SS_CURBLK(a3),d0             ; past it: the next one of the chain
                bsr     fat_next
                tst.l   d0
                beq     .rd_err
                move.l  d0,SS_CURBLK(a3)
                add.l   d4,SS_BLKBASE(a3)
                bra.s   .rd_lp
.rd_in:
                cmp.l   d6,d1
                bls.s   .rd_min
                move.l  d6,d1                        ; d1 = bytes for this pass, before the sector bound
.rd_min:
                move.l  SS_CURBLK(a3),d0
                bsr     fat_clok
                beq     .rd_err
                bsr     fat_c2s
                move.l  d2,d7
                lsr.l   #8,d7
                lsr.l   #1,d7                        ; d7 = sector of the cluster
                add.l   d7,d0                        ; d0 = sector
                and.l   #OFS_BSIZE-1,d2              ; d2 = offset in that sector
                bne.s   .rd_part
                cmp.l   #OFS_BSIZE,d1
                blo.s   .rd_part
                move.l  a4,d3
                btst    #0,d3
                bne.s   .rd_part                     ; odd destination: devices move words
                move.l  d1,d3
                lsr.l   #8,d3
                lsr.l   #1,d3                        ; d3 = whole sectors wanted
                neg.l   d7
                add.l   FC_SPC(a5),d7                ; d7 = sectors left in the cluster
                cmp.l   d7,d3
                bls.s   .rd_run
                move.l  d7,d3
.rd_run:
                move.l  d3,d1
                move.l  a4,a1
                move.l  a3,-(sp)
                lea     SS_IOREQ(a3),a3
                bsr     fat_rd
                move.l  (sp)+,a3
                tst.l   d0
                beq.s   .rd_err
                moveq   #9,d0
                lsl.l   d0,d3
                move.l  d3,d1                        ; d1 = bytes read
                add.l   d1,a4
                bra.s   .rd_adv
.rd_part:
                cmp.l   SS_BUFBLK(a3),d0
                beq.s   .rd_have
                movem.l d0-d1/a3,-(sp)
                lea     SS_IOREQ+IOREQ_SZ(a3),a1
                lea     SS_IOREQ(a3),a3
                moveq   #1,d1
                bsr     fat_rd
                move.l  d0,d3
                movem.l (sp)+,d0-d1/a3
                tst.l   d3
                beq.s   .rd_err
                move.l  d0,SS_BUFBLK(a3)
.rd_have:
                move.l  #OFS_BSIZE,d3
                sub.l   d2,d3                        ; bytes left in the sector
                cmp.l   d3,d1
                bls.s   .rd_cp
                move.l  d3,d1
.rd_cp:
                lea     SS_IOREQ+IOREQ_SZ(a3),a0
                add.l   d2,a0
                move.l  a4,a1
                move.l  d1,d0
                move.l  d1,-(sp)
                jsr     exec_CopyMem                 ; a1 comes back past the bytes
                move.l  (sp)+,d1
                move.l  a1,a4
.rd_adv:
                add.l   d1,SS_POS(a3)
                add.l   d1,d5
                sub.l   d1,d6
                bra     .rd_lp
.rd_err:
                tst.l   d5
                bne.s   .rd_done
                moveq   #-1,d5
.rd_done:
                move.l  d5,d0
                movem.l (sp)+,d1-d7/a0-a5
                rts

; fat_stream_seek(a1 = state, d0 = absolute position, within the file): backwards, the cursor goes back to the first
; cluster; the read walks the chain forward from where it is. Preserves everything.
fat_stream_seek:
                cmp.l   SS_BLKBASE(a1),d0
                bhs.s   .sk_fwd
                move.l  SS_FIRSTDATA(a1),SS_CURBLK(a1)
                clr.l   SS_BLKBASE(a1)
.sk_fwd:
                move.l  d0,SS_POS(a1)
                rts

; fat_diskinfo(a0 = InfoData, a1 = BPTR of the volume node, a6): blocks are the sectors of the data area; used ones
; from the free cluster count (all of them while it is unknown). Preserves d2-d7/a2-a6.
fat_diskinfo:
                movem.l d2/a2/a5,-(sp)
                move.l  a0,a2
                moveq   #8,d0
.di_clr:
                clr.l   (a0)+
                dbra    d0,.di_clr
                bsr     fat_fc
                move.l  #FAT_IDVALID,8(a2)
                move.l  FC_NCLUS(a5),d0
                move.l  FC_SHIFT(a5),d1
                lsl.l   d1,d0
                move.l  d0,12(a2)                    ; id_NumBlocks
                bsr     fat_free
                move.l  FC_NCLUS(a5),d2
                tst.l   d0
                bmi.s   .di_used
                sub.l   d0,d2
.di_used:
                move.l  FC_SHIFT(a5),d1
                lsl.l   d1,d2
                move.l  d2,16(a2)                    ; id_NumBlocksUsed
                move.l  #OFS_BSIZE,20(a2)            ; id_BytesPerBlock
                move.l  #$444F5300,24(a2)            ; id_DiskType "DOS\0" (1.3 programs know no other)
                move.l  a1,28(a2)                    ; id_VolumeNode
                movem.l (sp)+,d2/a2/a5
                rts

; ------------------------------------------------------------------------------------------------------------------
; Internal routines: a5 = FAT context, a6 = SysBase.

; fat_fc(a6) -> a5 = FAT context of the calling file-handler. Preserves the rest.
fat_fc:
                move.l  EB_THISTASK(a6),a5
                move.l  TC_USERDATA(a5),a5
                move.l  HC_GEO+GEO_FAT(a5),a5
                rts

; fat_rd(d0 = sector of the partition, d1 = sectors, a1 = buffer, a3 = IOStdReq, a6) -> d0 = 1 / 0 (Z). Device, unit,
; reply port and partition offset of the calling handler's context. Clobbers d1/a0/a1.
fat_rd:
                move.l  a1,IO_DATA(a3)
                lsl.l   #8,d1
                add.l   d1,d1
                move.l  d1,IO_LENGTH(a3)
                lsl.l   #8,d0
                add.l   d0,d0
                move.l  EB_THISTASK(a6),a0
                move.l  TC_USERDATA(a0),a0
                move.l  HC_TDIO+IO_DEVICE(a0),IO_DEVICE(a3)
                move.l  HC_TDIO+IO_UNIT(a0),IO_UNIT(a3)
                move.l  HC_GEO+GEO_PORT(a0),MN_REPLYPORT(a3)
                add.l   HC_GEO+GEO_POFF(a0),d0
                move.l  d0,IO_OFFSET(a3)
                move.w  #CMD_READ,IO_COMMAND(a3)
                clr.l   IO_ACTUAL(a3)
                move.l  a3,a1
                jsr     LVO_DOIO(a6)
                tst.b   IO_ERROR(a3)
                bne.s   .rd_fail
                move.l  IO_LENGTH(a3),d0
                cmp.l   IO_ACTUAL(a3),d0
                bne.s   .rd_fail
                moveq   #1,d0
                rts
.rd_fail:
                moveq   #0,d0
                rts

; fat_cache(d0 = sector, a0 = cache slot (LONG sector, then 512 bytes), a5, a6) -> a0 = the sector's data | 0 (Z = 1:
; read error, the slot emptied). Preserves d0-d7/a1-a6.
fat_cache:
                cmp.l   (a0)+,d0
                beq.s   .ch_hit
                movem.l d0-d1/a1/a3,-(sp)
                move.l  d0,-4(a0)
                move.l  a0,-(sp)
                move.l  a0,a1
                moveq   #1,d1
                lea     FC_IO(a5),a3
                bsr     fat_rd
                move.l  (sp)+,a0
                tst.l   d0
                bne.s   .ch_ok
                moveq   #-1,d0
                move.l  d0,-4(a0)
                suba.l  a0,a0
.ch_ok:
                movem.l (sp)+,d0-d1/a1/a3
.ch_hit:
                cmpa.w  #0,a0
                rts

; fat_le16(a0 = address) -> d0 = little-endian word there (zero-extended). fat_le32: little-endian long. Byte reads:
; any alignment. Preserve the rest.
fat_le16:
                moveq   #0,d0
                move.b  1(a0),d0
                lsl.w   #8,d0
                move.b  (a0),d0
                rts
fat_le32:
                move.b  3(a0),d0
                lsl.l   #8,d0
                move.b  2(a0),d0
                lsl.l   #8,d0
                move.b  1(a0),d0
                lsl.l   #8,d0
                move.b  (a0),d0
                rts

; fat_clok(d0 = cluster, a5) -> Z = 0 when it is a data cluster (2 .. FC_NCLUS + 1). Preserves everything else.
fat_clok:
                move.l  d1,-(sp)
                moveq   #0,d1
                cmp.l   #2,d0
                blo.s   .ck_ret
                move.l  FC_NCLUS(a5),d1
                addq.l  #2,d1
                cmp.l   d1,d0
                slo     d1
.ck_ret:
                tst.b   d1
                movem.l (sp)+,d1
                rts

; fat_c2s(d0 = data cluster, a5) -> d0 = its first sector. Preserves the rest.
fat_c2s:
                move.l  d1,-(sp)
                subq.l  #2,d0
                move.l  FC_SHIFT(a5),d1
                lsl.l   d1,d0
                add.l   FC_DATA(a5),d0
                move.l  (sp)+,d1
                rts

; fat_fatptr(d0 = byte offset in the FAT, a5, a6) -> a0 = that byte in the FAT cache | Z = 1 on a read error.
; Preserves d0-d7/a1-a6.
fat_fatptr:
                movem.l d0-d1,-(sp)
                move.l  d0,d1
                and.l   #OFS_BSIZE-1,d1
                lsr.l   #8,d0
                lsr.l   #1,d0
                add.l   FC_FATSEC0(a5),d0
                lea     FC_FATSEC(a5),a0
                bsr     fat_cache
                beq.s   .fp_ret
                add.l   d1,a0                        ; adda: Z left as fat_cache set it (clear)
.fp_ret:
                movem.l (sp)+,d0-d1
                rts

; fat_entry(d0 = cluster, a5, a6) -> d0 = its FAT entry (28 bits on FAT32) | -1 on a read error. Preserves the rest.
fat_entry:
                movem.l d1-d2/a0,-(sp)
                move.l  d0,d2                        ; d2 = cluster
                move.l  FC_TYPE(a5),d1
                cmp.w   #16,d1
                beq.s   .en_16
                bhi.s   .en_32
                lsr.l   #1,d0                        ; FAT12: 12 bits at byte c + c / 2, maybe across two sectors
                add.l   d2,d0
                bsr     fat_fatptr
                beq.s   .en_err
                moveq   #0,d1
                move.b  (a0),d1
                addq.l  #1,d0
                bsr     fat_fatptr
                beq.s   .en_err
                moveq   #0,d0
                move.b  (a0),d0
                lsl.w   #8,d0
                or.w    d1,d0
                btst    #0,d2
                beq.s   .en_even
                lsr.w   #4,d0
.en_even:
                and.w   #$FFF,d0
                bra.s   .en_ret
.en_16:
                add.l   d0,d0
                bsr     fat_fatptr
                beq.s   .en_err
                bsr     fat_le16
                bra.s   .en_ret
.en_32:
                lsl.l   #2,d0
                bsr     fat_fatptr
                beq.s   .en_err
                bsr     fat_le32
                and.l   #$0FFFFFFF,d0
                bra.s   .en_ret
.en_err:
                moveq   #-1,d0
.en_ret:
                movem.l (sp)+,d1-d2/a0
                rts

; fat_next(d0 = cluster, a5, a6) -> d0 = next data cluster of its chain | 0 (end of chain, free, bad, out of range or
; read error). Preserves the rest.
fat_next:
                bsr.s   fat_entry
                bsr     fat_clok
                bne.s   .nx_ret
                moveq   #0,d0
.nx_ret:
                rts

; fat_free(a5, a6) -> d0 = free clusters | -1 (unknown). Without an FSInfo figure, the FAT is counted once when it is
; small (FAT_SCANMAX sectors), never on a big FAT32. Preserves the rest.
fat_free:
                move.l  FC_FREE(a5),d0
                bpl.s   .fr_ret
                cmp.l   #FAT_SCANMAX,FC_FATSZ(a5)
                bhi.s   .fr_ret
                movem.l d1-d3,-(sp)
                moveq   #0,d3
                moveq   #2,d1
                move.l  FC_NCLUS(a5),d2
                addq.l  #2,d2
.fr_lp:
                cmp.l   d2,d1
                bhs.s   .fr_end
                move.l  d1,d0
                bsr     fat_entry
                tst.l   d0
                bne.s   .fr_nx
                addq.l  #1,d3
.fr_nx:
                addq.l  #1,d1
                bra.s   .fr_lp
.fr_end:
                move.l  d3,d0
                move.l  d0,FC_FREE(a5)
                movem.l (sp)+,d1-d3
.fr_ret:
                rts

; fat_dirstart(d0 = first cluster of a directory, 0 = root, a5) -> d0 = its first sector | 0 (invalid cluster).
; Preserves the rest.
fat_dirstart:
                tst.l   d0
                bne.s   .ds_cl
                move.l  FC_ROOTCL(a5),d0
                bne.s   .ds_cl                       ; FAT32: the root is a chain of clusters
                move.l  FC_ROOTSEC(a5),d0
                rts
.ds_cl:
                bsr     fat_clok
                beq.s   .ds_bad
                bra     fat_c2s
.ds_bad:
                moveq   #0,d0
                rts

; fat_dsnext(d0 = sector of a directory, a5, a6) -> d0 = the directory's next sector | 0 (no more). A sector below
; the data area belongs to the fixed root of FAT12/16. Preserves the rest.
fat_dsnext:
                movem.l d1-d2,-(sp)
                move.l  d0,d1
                sub.l   FC_DATA(a5),d1
                bcc.s   .dn_cl
                addq.l  #1,d0
                move.l  FC_ROOTSEC(a5),d1
                add.l   FC_ROOTN(a5),d1
                cmp.l   d1,d0
                blo.s   .dn_ret
                bra.s   .dn_end
.dn_cl:
                addq.l  #1,d1
                move.l  FC_SPC(a5),d2
                subq.l  #1,d2
                and.l   d1,d2
                beq.s   .dn_chain                    ; past the last sector of the cluster
                addq.l  #1,d0
                bra.s   .dn_ret
.dn_chain:
                subq.l  #1,d1
                move.l  FC_SHIFT(a5),d2
                lsr.l   d2,d1
                addq.l  #2,d1
                move.l  d1,d0
                bsr     fat_next
                tst.l   d0
                beq.s   .dn_ret
                bsr     fat_c2s
                bra.s   .dn_ret
.dn_end:
                moveq   #0,d0
.dn_ret:
                movem.l (sp)+,d1-d2
                rts

; fat_scan(d2 = sector, d3 = index in it (0-16), a5, a6) -> d0 = 1: the next object at or after that place, with
; FC_KEY, FC_ENT (its short entry), FC_NAME and FC_SNAME; d2/d3 = the place after it / 0: end of the directory.
; Skips free and deleted entries, labels, "." and "..", and long-name entries that do not belong to the short entry
; after them (ordinals out of sequence, checksum). Preserves d1/d4-d7/a0-a6.
fat_scan:
                movem.l d1/d4-d7/a0-a2,-(sp)
                clr.b   FC_LSEQ(a5)
                sf      FC_LDONE(a5)
                move.l  #FAT_DIRMAX,d4
.sc_lp:
                subq.l  #1,d4
                beq     .sc_end
                cmp.l   #16,d3
                blo.s   .sc_in
                moveq   #0,d3
                move.l  d2,d0
                bsr     fat_dsnext
                move.l  d0,d2
                beq     .sc_end
.sc_in:
                move.l  d2,d0
                lea     FC_DIRSEC(a5),a0
                bsr     fat_cache
                beq     .sc_end
                move.l  d3,d0
                lsl.w   #5,d0
                add.w   d0,a0                        ; a0 = the entry
                move.l  d2,d5
                lsl.l   #4,d5
                add.l   d3,d5                        ; d5 = its key
                addq.l  #1,d3
                move.b  (a0),d0
                beq     .sc_end                      ; never used: nothing after it
                cmp.b   #$E5,d0
                beq.s   .sc_drop
                moveq   #$3F,d1
                and.b   11(a0),d1
                cmp.b   #$0F,d1
                beq.s   .sc_lfn
                btst    #3,d1
                bne.s   .sc_drop                     ; volume label
                cmp.b   #'.',d0
                bne     .sc_short
.sc_drop:
                clr.b   FC_LSEQ(a5)
                sf      FC_LDONE(a5)
                bra.s   .sc_lp
.sc_lfn:
                sf      FC_LDONE(a5)
                moveq   #0,d1
                move.b  d0,d1                        ; ordinal
                bclr    #6,d1
                beq.s   .sl_mid
                tst.b   d1                           ; the last part of a name comes first: a new set
                beq.s   .sc_drop
                cmp.b   #FAT_LFNMAX,d1
                bhi.s   .sc_drop
                move.b  13(a0),FC_LCHK(a5)
                move.l  d5,FC_LKEY(a5)
                move.b  d1,FC_LCNT(a5)
                bra.s   .sl_store
.sl_mid:
                tst.b   FC_LSEQ(a5)
                beq.s   .sc_drop
                cmp.b   FC_LSEQ(a5),d1
                bne.s   .sc_drop
                move.b  13(a0),d0
                cmp.b   FC_LCHK(a5),d0
                bne.s   .sc_drop
.sl_store:
                move.l  d1,d0                        ; 13 UCS-2 characters to FC_LFN + (ordinal - 1) * 13
                subq.l  #1,d0
                mulu    #13,d0
                lea     FC_LFN(a5),a1
                add.l   d0,a1
                lea     fat_lfnoff(pc),a2
                moveq   #12,d6
.sl_ch:
                moveq   #0,d0
                move.b  (a2)+,d0
                move.b  1(a0,d0.w),d7                ; high byte
                move.b  0(a0,d0.w),d0                ; low byte
                tst.b   d7
                beq.s   .sl_put                      ; Latin-1, or the terminating 0
                cmp.b   #$FF,d7
                bne.s   .sl_q
                cmp.b   #$FF,d0
                bne.s   .sl_q
                moveq   #0,d0                        ; $FFFF: padding after the terminator
                bra.s   .sl_put
.sl_q:
                moveq   #'?',d0
.sl_put:
                move.b  d0,(a1)+
                dbra    d6,.sl_ch
                subq.b  #1,d1
                move.b  d1,FC_LSEQ(a5)
                bne     .sc_lp
                st      FC_LDONE(a5)                 ; complete: its short entry must come next
                bra     .sc_lp
.sc_short:
                moveq   #0,d1                        ; checksum of the 11 name bytes
                moveq   #10,d6
                move.l  a0,a1
.ss_sum:
                ror.b   #1,d1
                add.b   (a1)+,d1
                dbra    d6,.ss_sum
                move.l  d5,FC_KEY(a5)
                lea     FC_ENT(a5),a1
                moveq   #7,d6
.ss_cp:
                move.l  (a0)+,(a1)+
                dbra    d6,.ss_cp
                bsr     fat_sname
                tst.b   FC_LDONE(a5)
                beq.s   .ss_8n3
                cmp.b   FC_LCHK(a5),d1
                bne.s   .ss_8n3
                move.l  FC_LKEY(a5),FC_KEY(a5)       ; the object starts at its first long-name entry
                lea     FC_LFN(a5),a0
                moveq   #0,d0
                move.b  FC_LCNT(a5),d0
                mulu    #13,d0                       ; d0 = room the set gives
                moveq   #0,d6
.ss_len:
                cmp.l   d0,d6
                beq.s   .ss_lend
                tst.b   0(a0,d6.l)
                beq.s   .ss_lend
                addq.l  #1,d6
                bra.s   .ss_len
.ss_lend:
                tst.l   d6
                beq.s   .ss_8n3
                cmp.l   #FAT_NAMEMAX,d6
                bhi.s   .ss_8n3
                lea     FC_NAME(a5),a1
                subq.w  #1,d6
.ss_ln:
                move.b  (a0)+,(a1)+
                dbra    d6,.ss_ln
                clr.b   (a1)
                bra.s   .ss_found
.ss_8n3:
                lea     FC_SNAME(a5),a0
                lea     FC_NAME(a5),a1
.ss_sn:
                move.b  (a0)+,(a1)+
                bne.s   .ss_sn
.ss_found:
                moveq   #1,d0
                bra.s   .sc_ret
.sc_end:
                moveq   #0,d0
.sc_ret:
                movem.l (sp)+,d1/d4-d7/a0-a2
                rts
fat_lfnoff:                                          ; offsets of the 13 characters of a long-name entry
                dc.b    1,3,5,7,9,14,16,18,20,22,24,28,30
                even

; fat_sname(a5): FC_SNAME = 8.3 name of FC_ENT, spaces dropped, a dot before a non-empty extension; the case flags of
; byte 12 (bit 3 base, bit 4 extension: lower case) applied; a first byte $05 stands for $E5. Preserves everything.
fat_sname:
                movem.l d0-d2/a0-a2,-(sp)
                lea     FC_ENT(a5),a0
                lea     FC_SNAME(a5),a1
                move.b  12(a0),d2
                lsr.b   #3,d2                        ; bit 0: base in lower case, bit 1: extension
                moveq   #8,d1
                bsr.s   .sn_cp
                cmp.b   #$05,FC_SNAME(a5)
                bne.s   .sn_ext
                move.b  #$E5,FC_SNAME(a5)
.sn_ext:
                cmp.b   #' ',(a0)
                beq.s   .sn_end
                move.b  #'.',(a1)+
                lsr.b   #1,d2
                moveq   #3,d1
                bsr.s   .sn_cp
.sn_end:
                clr.b   (a1)
                movem.l (sp)+,d0-d2/a0-a2
                rts
.sn_cp:                                              ; d1 characters a0 -> a1, trailing spaces dropped
                move.l  a1,a2                        ; a2 = just after the last non-space
                subq.w  #1,d1
.sn_lp:
                move.b  (a0)+,d0
                btst    #0,d2
                beq.s   .sn_put
                cmp.b   #'A',d0
                blo.s   .sn_put
                cmp.b   #'Z',d0
                bhi.s   .sn_put
                add.b   #$20,d0
.sn_put:
                move.b  d0,(a1)+
                cmp.b   #' ',d0
                beq.s   .sn_sp
                move.l  a1,a2
.sn_sp:
                dbra    d1,.sn_lp
                move.l  a2,a1
                rts

; fat_upper(d0.b) -> d0.b in upper case: a-z and the Latin-1 letters 224-254 but 247. Preserves the rest.
fat_upper:
                cmp.b   #'a',d0
                blo.s   .up_ret
                cmp.b   #'z',d0
                bls.s   .up_sub
                cmp.b   #224,d0
                blo.s   .up_ret
                cmp.b   #254,d0
                bhi.s   .up_ret
                cmp.b   #247,d0
                beq.s   .up_ret
.up_sub:
                sub.b   #$20,d0
.up_ret:
                rts

; fat_cmp(a0, a1 = C strings) -> Z = 1 when equal ignoring case. Preserves everything else.
fat_cmp:
                movem.l d0-d1/a0-a1,-(sp)
.cm_lp:
                move.b  (a0)+,d0
                bsr.s   fat_upper
                move.b  d0,d1
                move.b  (a1)+,d0
                bsr.s   fat_upper
                cmp.b   d0,d1
                bne.s   .cm_ret
                tst.b   d0
                bne.s   .cm_lp
.cm_ret:
                movem.l (sp)+,d0-d1/a0-a1
                rts

; fat_split(a0 = path cursor, a4 = FAT_COMPMAX buffer) -> (a4) = next component (up to '/' or NUL; characters past
; the 31st dropped), a0 past it and its '/'; d0 = 1 when it is the last one. Clobbers d1/a1.
fat_split:
                move.l  a4,a1
                moveq   #FAT_COMPMAX-1,d1
.sp_lp:
                move.b  (a0),d0
                beq.s   .sp_last
                addq.l  #1,a0
                cmp.b   #'/',d0
                beq.s   .sp_mid
                subq.l  #1,d1
                bmi.s   .sp_lp
                move.b  d0,(a1)+
                bra.s   .sp_lp
.sp_mid:
                clr.b   (a1)
                moveq   #0,d0
                rts
.sp_last:
                clr.b   (a1)
                moveq   #1,d0
                rts

; fat_find(d0 = first cluster of a directory (0 = root), a4 = name, a5, a6) -> d0 = 1: found (FC_KEY, FC_ENT) / 0.
; The shown name or the 8.3 name, ignoring case. Preserves the rest.
fat_find:
                movem.l d2-d3/a0-a1,-(sp)
                bsr     fat_dirstart
                move.l  d0,d2
                beq.s   .fd_ret
                moveq   #0,d3
.fd_lp:
                bsr     fat_scan
                tst.l   d0
                beq.s   .fd_ret
                move.l  a4,a0
                lea     FC_NAME(a5),a1
                bsr     fat_cmp
                beq.s   .fd_yes
                lea     FC_SNAME(a5),a1
                bsr     fat_cmp
                bne.s   .fd_lp
.fd_yes:
                moveq   #1,d0
.fd_ret:
                movem.l (sp)+,d2-d3/a0-a1
                rts

; fat_getobj(d0 = key of an object, not the root, a5, a6) -> d0 = 1: FC_* describe it / 0: no object starts there.
; Preserves the rest.
fat_getobj:
                movem.l d1-d3,-(sp)
                move.l  d0,d1
                move.l  d0,d2
                lsr.l   #4,d2
                moveq   #15,d3
                and.l   d0,d3
                bsr     fat_scan
                tst.l   d0
                beq.s   .go_ret
                cmp.l   FC_KEY(a5),d1
                seq     d0
                and.l   #1,d0
.go_ret:
                movem.l (sp)+,d1-d3
                rts

; fat_ecl(a0 = directory entry, a5) -> d0 = its first cluster (the high word only on FAT32). fat_entcl: of FC_ENT.
; Preserve the rest.
fat_entcl:
                move.l  a0,-(sp)
                lea     FC_ENT(a5),a0
                bsr.s   fat_ecl
                move.l  (sp)+,a0
                rts
fat_ecl:
                move.l  d1,-(sp)
                moveq   #0,d1
                cmp.l   #32,FC_TYPE(a5)
                bne.s   .ec_lo
                move.b  21(a0),d1
                lsl.w   #8,d1
                move.b  20(a0),d1
                swap    d1
.ec_lo:
                move.l  a0,-(sp)
                lea     26(a0),a0
                bsr     fat_le16
                move.l  (sp)+,a0
                or.l    d1,d0
                move.l  (sp)+,d1
                rts

; fat_keydir(d0 = key, a5, a6) -> d0 = first cluster of that directory (0 = root) | -1: not a directory (or not
; found). Preserves the rest.
fat_keydir:
                cmp.l   #FAT_ROOTKEY,d0
                bne.s   .kd_obj
                moveq   #0,d0
                rts
.kd_obj:
                bsr     fat_getobj
                tst.l   d0
                beq.s   .kd_no
                btst    #4,FC_ENT+11(a5)
                beq.s   .kd_no
                bra.s   fat_entcl
.kd_no:
                moveq   #-1,d0
                rts

; fat_parent(d0 = key, a5, a6) -> d0 = key of the directory holding that object (FAT_ROOTKEY for the root's
; children) | 0: the root itself, or not found. The entry's sector gives a cluster of the parent's chain; its first
; cluster is the one whose first entry is "." naming itself (a walk back through the FAT otherwise, slow on a big
; volume), and its key comes from the grandparent ("..") holding a directory entry with that cluster.
; Preserves the rest.
fat_parent:
                movem.l d1-d2,-(sp)
                cmp.l   #FAT_ROOTKEY,d0
                beq.s   .pa_none
                lsr.l   #4,d0                        ; sector of the object's entry
                move.l  d0,d1
                sub.l   FC_DATA(a5),d1
                bcs.s   .pa_root                     ; in the fixed root of FAT12/16
                move.l  FC_SHIFT(a5),d2
                lsr.l   d2,d1
                addq.l  #2,d1                        ; d1 = cluster holding the entry
                bsr.s   fat_dirhead
                tst.l   d0
                beq.s   .pa_root
                bmi.s   .pa_none
                bsr     fat_dirkey
                bra.s   .pa_ret
.pa_root:
                moveq   #FAT_ROOTKEY,d0
                bra.s   .pa_ret
.pa_none:
                moveq   #0,d0
.pa_ret:
                movem.l (sp)+,d1-d2
                rts

; fat_dirhead(d1 = a cluster of a directory's chain, a5, a6) -> d0 = the directory's first cluster | 0 (the FAT32
; root) | -1 (not found). Preserves the rest.
fat_dirhead:
                movem.l d1-d4/a0,-(sp)
                move.l  #FAT_DIRMAX,d4               ; bound on the steps back
.dh_lp:
                cmp.l   FC_ROOTCL(a5),d1
                beq.s   .dh_root
                move.l  d1,d0
                bsr     fat_c2s
                lea     FC_DIRSEC(a5),a0
                bsr     fat_cache
                beq.s   .dh_fail
                cmp.b   #'.',(a0)
                bne.s   .dh_back
                cmp.b   #' ',1(a0)
                bne.s   .dh_back
                btst    #4,11(a0)
                beq.s   .dh_back
                bsr     fat_ecl
                cmp.l   d1,d0
                beq.s   .dh_ret
.dh_back:
                subq.l  #1,d4
                beq.s   .dh_fail
                moveq   #2,d2                        ; the cluster whose FAT entry is d1
                move.l  FC_NCLUS(a5),d3
                addq.l  #2,d3
.dh_scan:
                cmp.l   d3,d2
                bhs.s   .dh_fail
                move.l  d2,d0
                bsr     fat_entry
                cmp.l   d1,d0
                beq.s   .dh_prev
                addq.l  #1,d2
                bra.s   .dh_scan
.dh_prev:
                move.l  d2,d1
                bra.s   .dh_lp
.dh_root:
                moveq   #0,d0
                bra.s   .dh_ret
.dh_fail:
                moveq   #-1,d0
.dh_ret:
                movem.l (sp)+,d1-d4/a0
                rts

; fat_dirkey(d0 = first cluster of a directory other than the root, a5, a6) -> d0 = its key | 0. Preserves the rest.
fat_dirkey:
                movem.l d1-d3/a0,-(sp)
                move.l  d0,d1                        ; d1 = the directory's cluster
                bsr     fat_c2s
                lea     FC_DIRSEC(a5),a0
                bsr     fat_cache
                beq.s   .dk_fail
                lea     32(a0),a0                    ; ".." is its second entry
                cmp.b   #'.',(a0)
                bne.s   .dk_fail
                cmp.b   #'.',1(a0)
                bne.s   .dk_fail
                bsr     fat_ecl                      ; parent's cluster, 0 for the root
                cmp.l   FC_ROOTCL(a5),d0
                bne.s   .dk_go
                moveq   #0,d0                        ; some systems write the FAT32 root's own cluster there
.dk_go:
                bsr     fat_dirstart
                move.l  d0,d2
                beq.s   .dk_fail
                moveq   #0,d3
.dk_lp:
                bsr     fat_scan
                tst.l   d0
                beq.s   .dk_fail
                btst    #4,FC_ENT+11(a5)
                beq.s   .dk_lp
                bsr     fat_entcl
                cmp.l   d1,d0
                bne.s   .dk_lp
                move.l  FC_KEY(a5),d0
                bra.s   .dk_ret
.dk_fail:
                moveq   #0,d0
.dk_ret:
                movem.l (sp)+,d1-d3/a0
                rts

; fat_fibent(a4 = FileInfoBlock, a5): fills it from FC_ENT and FC_NAME (DiskKey left to the caller). File -3,
; directory 2; read-only attribute: write and delete protected; size and 512-byte blocks; write date; no comment.
; Clobbers d0/d1/a0/a1.
fat_fibent:
                moveq   #-3,d0
                btst    #4,FC_ENT+11(a5)
                beq.s   .fe_type
                moveq   #2,d0
.fe_type:
                move.l  d0,FIB_DIRENTRYTYPE(a4)
                move.l  d0,FIB_ENTRYTYPE(a4)
                moveq   #0,d1
                btst    #0,FC_ENT+11(a5)
                beq.s   .fe_prot
                moveq   #5,d1                        ; FIBF_WRITE | FIBF_DELETE
.fe_prot:
                move.l  d1,FIB_PROTECTION(a4)
                clr.l   FIB_SIZE(a4)
                clr.l   FIB_NUMBLOCKS(a4)
                tst.l   d0
                bpl.s   .fe_date
                lea     FC_ENT+28(a5),a0
                bsr     fat_le32
                move.l  d0,FIB_SIZE(a4)
                add.l   #OFS_BSIZE-1,d0              ; ceil(size / 512), the carry shifted back in
                roxr.l  #1,d0
                lsr.l   #8,d0
                move.l  d0,FIB_NUMBLOCKS(a4)
.fe_date:
                lea     FC_ENT+22(a5),a0
                bsr     fat_le16
                move.l  d0,d1                        ; time
                lea     FC_ENT+24(a5),a0
                bsr     fat_le16                     ; date
                lea     FIB_DATE(a4),a1
                bsr     fat_dstamp
                clr.w   FIB_COMMENT(a4)
                lea     FC_NAME(a5),a0
                bra.s   fat_fibname

; fat_fibroot(a4 = FileInfoBlock, a5): the root: directory 2, volume name and date. Clobbers d0/a0/a1.
fat_fibroot:
                moveq   #2,d0
                move.l  d0,FIB_DIRENTRYTYPE(a4)
                move.l  d0,FIB_ENTRYTYPE(a4)
                clr.l   FIB_PROTECTION(a4)
                clr.l   FIB_SIZE(a4)
                clr.l   FIB_NUMBLOCKS(a4)
                move.l  FC_VDATE(a5),FIB_DATE(a4)
                move.l  FC_VDATE+4(a5),FIB_DATE+4(a4)
                move.l  FC_VDATE+8(a5),FIB_DATE+8(a4)
                clr.w   FIB_COMMENT(a4)
                lea     FC_VNAME(a5),a0

; fat_fibname(a0 = C name, a4 = FileInfoBlock): fib_FileName as a BSTR followed by a NUL. Clobbers d0/a0/a1.
fat_fibname:
                lea     FIB_FILENAME+1(a4),a1
                moveq   #0,d0
.fn_lp:
                move.b  (a0)+,(a1)+
                beq.s   .fn_end
                addq.b  #1,d0
                bra.s   .fn_lp
.fn_end:
                move.b  d0,FIB_FILENAME(a4)
                rts

; fat_dstamp(d0 = FAT date, d1 = FAT time, a1 = DateStamp): days since 1978-01-01, minutes, ticks (the FAT keeps
; 2-second steps); an invalid date gives 0, an invalid time midnight. Preserves everything.
fat_dstamp:
                movem.l d0-d5/a0,-(sp)
                clr.l   (a1)
                clr.l   4(a1)
                clr.l   8(a1)
                move.l  d1,d5                        ; d5 = time
                move.l  d0,d2
                lsr.w   #5,d2
                and.w   #15,d2                       ; d2 = month
                beq     .dt_ret
                cmp.w   #12,d2
                bhi     .dt_ret
                moveq   #31,d3
                and.w   d0,d3                        ; d3 = day
                beq     .dt_ret
                moveq   #0,d4
                move.w  d0,d4
                lsr.w   #8,d4
                lsr.w   #1,d4                        ; d4 = years since 1980
                move.l  d4,d0
                mulu    #365,d0
                move.l  d4,d1
                addq.l  #3,d1
                lsr.l   #2,d1                        ; leap years 1980 .. year - 1
                add.l   d1,d0
                cmp.w   #120,d4
                bls.s   .dt_c
                subq.l  #1,d0                        ; 2100 is not one
.dt_c:
                add.l   #730,d0                      ; 1978 and 1979
                lea     fat_cumdays(pc),a0
                moveq   #0,d1
                move.w  d2,d1
                subq.w  #1,d1
                add.w   d1,d1
                move.w  0(a0,d1.w),d1
                add.l   d1,d0
                cmp.w   #2,d2
                bls.s   .dt_d
                moveq   #3,d1
                and.w   d4,d1
                bne.s   .dt_d
                cmp.w   #120,d4
                beq.s   .dt_d
                addq.l  #1,d0                        ; leap year, past February
.dt_d:
                add.l   d3,d0
                subq.l  #1,d0
                move.l  d0,(a1)
                moveq   #0,d0
                move.w  d5,d0
                lsr.w   #8,d0
                lsr.w   #3,d0                        ; hours
                cmp.w   #23,d0
                bhi.s   .dt_ret
                mulu    #60,d0
                moveq   #0,d1
                move.w  d5,d1
                lsr.w   #5,d1
                and.w   #63,d1
                cmp.w   #59,d1
                bhi.s   .dt_ret
                add.l   d1,d0
                move.l  d0,4(a1)
                moveq   #31,d0
                and.w   d5,d0
                cmp.w   #29,d0
                bhi.s   .dt_ret
                mulu    #100,d0                      ; 2 s = 100 ticks
                move.l  d0,8(a1)
.dt_ret:
                movem.l (sp)+,d0-d5/a0
                rts
fat_cumdays:
                dc.w    0,31,59,90,120,151,181,212,243,273,304,334
