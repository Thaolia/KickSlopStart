; src/dos/diskvalidator.s - OFS disk-validator (#4): validates the allocation bitmap of DF0:.
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
