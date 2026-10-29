; src/dos/ofs.s - OFS read-only (D1): ofs_read_file(name, dest, max) -> size read | 0.
; INTERNAL filesystem machinery (NO packets / BCPL file-handler yet = D3). Relies on trackdisk
; CMD_READ (M6z multi-track) to read 512-byte logical blocks of DF0:. OFS algorithm locked down
; empirically on a test ADF (asset, NOT the ROM): root@880; hash h=len, h=(h*13+toupper(c))&$7FF,
; idx=h%ht_size; hash table -> header (BCPL name, sec_type, first_data, hash_chain); OFS data block
; (type 8, data_size, next_data, data @+24). Clean-room: ADF-FAQ / AmigaDOS Technical Reference (public)
; + AROS rom/filesys (read-only). NO ROM reading.
;
; ACCEPTED deviations/scope: read-only; traversal of subdirectories via '/'-separated paths (intermediate
; USERDIRs -> final file; ht_size of USERDIRs = 72 by default, long[3] not populated = measured on the ADF);
; names case-insensitive for ASCII a-z (non-international OFS); hash-chain/data loops are CAPPED
; (anti-hang on a corrupted disk). FFS (no data block header) not supported (1.3 boots from OFS).

                include "exec.i"
                include "disk.i"
                include "ofs.i"
                include "dospkt.i"       ; FIB_* (filling of the FileInfoBlock by ofs_fib_fill)

                xdef    ofs_read_file
                xdef    ofs_name_to_block    ; resolves a path -> header block (Lock)
                xdef    ofs_fill_fib         ; fills a FIB from a header block (Examine)
                xdef    ofs_dir_next         ; enumerates the next entry of a directory (ExNext)
                xdef    ofs_stream_open      ; opens a file for streaming (state -> first data block)
                xdef    ofs_stream_read      ; incremental read (data block by data block, no whole-file buffer)
                xdef    ofs_stream_seek      ; repositions the streaming cursor
                xdef    ofs_hash             ; OFS writing (ofswrite.s): hash index of a name
                xdef    ofs_read_block       ; reading of a block (handler.s: hnd_bootclock)
                xdef    ofs_namecmp          ; OFS writing: case-insensitive name comparison

; ofs_read_file(a6=SysBase, a0=NUL-terminated path, a1=dest, d0=max bytes) -> d0 = size read | 0.
; Resolves a PATH of '/'-separated components (e.g. "s/startup-sequence"): traverses the intermediate USERDIR
; subdirectories then reads the final FILE. A single-component path ("kickslop") = root lookup
; (D1 compat). Names compared case-INSENSITIVELY. Reads via trackdisk.device (FindName).
ofs_read_file:
                movem.l d2-d7/a2-a5,-(sp)
                lea     -OFS_FRAME(sp),sp           ; local frame: [comp buf][path cursor][last flag]
                move.l  a0,LF_PATHCUR(sp)           ; initial path cursor (a0 = path)
                move.l  a1,a5                        ; a5 = dest (advances with each data block)
                move.l  d0,d7                        ; d7 = max bytes remaining (buffer guard)
                moveq   #0,d6                        ; d6 = total read (return value)
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .fail_nofree                 ; no trackdisk.device
                move.l  d0,a2                        ; a2 = trackdisk base
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fail_nofree
                move.l  d0,a3                        ; a3 = ioreq; block buffer = a3 + IOREQ_SZ
                move.l  #OFS_ROOTBLK,d4             ; d4 = current directory block (starts at the root)
.nextcomp:
                lea     LF_COMP(sp),a4             ; a4 = component buffer (NUL-terminated by ofs_split)
                move.l  LF_PATHCUR(sp),a0          ; a0 = path cursor
                bsr     ofs_split                    ; copies the component -> (a4); a0 advances; d0 = 1 if last
                move.l  a0,LF_PATHCUR(sp)
                move.b  d0,LF_LAST(sp)
                bsr     ofs_dir_lookup               ; (d4=dir, a4=comp) -> d0 = header block found | 0
                tst.l   d0
                beq     .exit                        ; component not found -> failure
                move.l  d0,d4                        ; d4 = block of the component found
                move.l  d4,d0                         ; re-read this block (sectype; and file header if last)
                bsr     ofs_read_block
                tst.l   d0
                beq     .exit
                lea     IOREQ_SZ(a3),a0
                tst.b   LF_LAST(sp)
                bne.s   .comp_last
                cmp.l   #OFS_ST_USERDIR,OFSB_SECTYPE(a0) ; intermediate component -> must be a DIRECTORY
                bne     .exit
                bra     .nextcomp                    ; descend: d4 = this userdir, next component
.comp_last:
                cmp.l   #OFS_ST_FILE,OFSB_SECTYPE(a0)    ; last component -> must be a FILE
                bne     .exit
                ; --- read the data chain (the file header is already in the buffer) ---
                move.l  OFSB_FIRSTDATA(a0),d2        ; first data block
                move.w  #OFS_NBLK,d5                 ; data chain cap
.dloop:
                bsr     ofs_blk_valid
                beq.s   .exit                        ; 0 / invalid -> end
                move.l  d2,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .exit
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_DATA,OFSB_TYPE(a0)    ; validate: OFS data block
                bne.s   .exit
                move.l  OFSB_DSIZE(a0),d0            ; d0 = data_size
                cmp.l   #OFS_DMAX,d0
                bhi.s   .exit                        ; absurd data_size -> stop
                cmp.l   d7,d0
                bhi.s   .exit                        ; would overflow the buffer (guard) -> stop
                lea     OFSB_DATA(a0),a0             ; a0 = data (@+24)
                move.l  d0,d1
                beq.s   .dnext                       ; empty block
                subq.l  #1,d1
.dcopy:
                move.b  (a0)+,(a5)+                  ; copy data_size bytes (<=488)
                dbra    d1,.dcopy
.dnext:
                add.l   d0,d6                        ; total += data_size
                sub.l   d0,d7                        ; max remaining -= data_size
                ifne    OFS_NO_DATACHAIN
                bra.s   .exit                        ; RED: does NOT follow next_data -> only the 1st data block read
                endc
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_NEXT(a0),d2             ; next data block
                subq.w  #1,d5
                bne.s   .dloop
.exit:
                move.l  a3,a1                        ; free ioreq + block buffer
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d6,d0                        ; return = total read
                bra.s   .ret
.fail_nofree:
                moveq   #0,d0
.ret:
                lea     OFS_FRAME(sp),sp             ; free the local frame
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ofs_dir_lookup(d4=directory block, a4=NUL-terminated component; a2=trackdisk, a3=ioreq, a6=SysBase) -> d0 = header
; block of the name (file OR subdir) | 0. Match by NAME (unique within a directory); the driver checks the
; sectype. ht_size: read from the block (root=72); 0 (userdir) or >=128 (corrupted) -> default OFS_HTDEF. Preserves
; d4/d6/d7/a4/a5; clobbers d0-d3/d5/a0/a1 (ofs_read_block preserves d2-d7/a2-a5).
ofs_dir_lookup:
                move.l  d4,d0
                bsr     ofs_read_block               ; read the current directory block
                tst.l   d0
                beq.s   .dl_fail
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_SHORT,OFSB_TYPE(a0)
                bne.s   .dl_fail
                move.l  OFSB_HTSIZE(a0),d3           ; stored hash_table_size
                beq.s   .dl_htdef                    ; 0 (userdir: long[3] not populated) -> default
                cmp.l   #OFS_HTMAX,d3
                blo.s   .dl_hthave
.dl_htdef:
                moveq   #OFS_HTDEF,d3                ; 72 = BSIZE/4 - 56
.dl_hthave:
                bsr     ofs_hash                     ; a4=comp, d3=ht_size -> d1 = idx
                lea     IOREQ_SZ(a3),a0
                lsl.l   #2,d1                        ; idx * 4 (bytes)
                lea     OFSB_HASHTAB(a0),a0
                move.l  0(a0,d1.l),d2                ; d2 = current header block (bucket)
                move.w  #OFS_NBLK,d5                 ; anti-loop cap
.dl_chain:
                bsr     ofs_blk_valid
                beq.s   .dl_fail                     ; block 0 / outside [2,1760) -> end of chain, not found
                move.l  d2,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .dl_fail
                lea     IOREQ_SZ(a3),a0
                lea     OFSB_NAME(a0),a1             ; stored BCPL name
                move.l  a4,a0                        ; query = component
                bsr     ofs_namecmp                  ; Z=1 if equal (case-insensitive)
                beq.s   .dl_hit
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_HASHCHAIN(a0),d2        ; next header in the same bucket
                subq.w  #1,d5
                bne.s   .dl_chain
.dl_fail:
                moveq   #0,d0
                rts
.dl_hit:
                move.l  d2,d0                        ; header block found (name OK; sectype checked by the driver)
                rts

; ofs_split(a0=path cursor, a4=dest buffer) -> copies the component [a0..] (up to '/' or NUL) into (a4) and
; NUL-terminates it; a0 advances PAST the '/' (or stays on the NUL); d0 = 1 if last component (NUL-terminated), else 0.
; Capped at OFS_COMPMAX-1 chars (the rest of a too-long component is swallowed). Clobbers d0/d1/a0/a1 (a4 preserved).
; RED OFS_NO_SUBDIR: '/' treated as a normal char -> the whole path becomes a single (last) component.
ofs_split:
                move.l  a4,a1                        ; a1 = dest (a4 preserved)
                moveq   #OFS_COMPMAX-1,d1            ; cap
.sp_lp:
                move.b  (a0),d0
                beq.s   .sp_nul
                ifeq    OFS_NO_SUBDIR
                cmp.b   #'/',d0
                beq.s   .sp_slash
                endc
                move.b  d0,(a1)+
                addq.l  #1,a0
                subq.l  #1,d1
                bne.s   .sp_lp
.sp_eat:                                             ; cap reached: swallow the rest of the component (up to '/' or NUL)
                move.b  (a0),d0
                beq.s   .sp_nul
                ifeq    OFS_NO_SUBDIR
                cmp.b   #'/',d0
                beq.s   .sp_slash
                endc
                addq.l  #1,a0
                bra.s   .sp_eat
.sp_slash:
                addq.l  #1,a0                        ; skip the '/'
                clr.b   (a1)                         ; NUL-terminate the component
                moveq   #0,d0                        ; not the last one
                rts
.sp_nul:
                clr.b   (a1)                         ; NUL-terminate the component
                moveq   #1,d0                        ; last component (NUL-terminated)
                rts

; ofs_read_block(d0=block num, a2=trackdisk, a3=ioreq, a6=SysBase) -> d0 = 1 OK / 0 failed; fills a3+IOREQ_SZ.
; Only uses d0/d1/a0/a1 as scratch (BeginIO preserves d2-d7/a2-a5) -> the caller's loop state survives.
ofs_read_block:
                lsl.l   #8,d0
                lsl.l   #1,d0                        ; offset = block * 512 (< 901120, no 32-bit overflow)
                move.l  a2,IO_DEVICE(a3)
                move.w  #CMD_READ,IO_COMMAND(a3)
                move.l  #OFS_BSIZE,IO_LENGTH(a3)
                lea     IOREQ_SZ(a3),a0
                move.l  a0,IO_DATA(a3)
                move.l  d0,IO_OFFSET(a3)
                move.b  #IOF_QUICK,IO_FLAGS(a3)
                clr.l   IO_ACTUAL(a3)
                move.l  a6,-(sp)                     ; BeginIO via vector -30 (a6=trackdisk, a1=ioreq)
                move.l  a2,a6
                move.l  a3,a1
                jsr     -30(a6)
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

; ofs_blk_valid(d2=block) -> Z=1 if INVALID (0 or outside [2,1760)). Clobbers d0 only (flags via moveq).
ofs_blk_valid:
                cmp.l   #2,d2
                blo.s   .bv_inv
                cmp.l   #OFS_NBLK,d2
                bhs.s   .bv_inv
                moveq   #-1,d0                       ; valid -> Z=0
                rts
.bv_inv:
                moveq   #0,d0                        ; invalid -> Z=1
                rts

; ofs_hash(a4=NUL-terminated name, d3=ht_size) -> d1 = idx. Clobbers d0/d1/a0. h=len; h=(h*13+toupper(c))&$7FF;
; idx = h mod ht_size. toupper = ASCII a-z only (non-international OFS DOS\0).
ofs_hash:
                move.l  a4,a0
                moveq   #0,d1                        ; d1 = h (initialised to the length)
.hlen:
                tst.b   (a0)+
                beq.s   .hgo
                addq.l  #1,d1
                bra.s   .hlen
.hgo:
                move.l  a4,a0                        ; re-read from the start (d1 = len = initial h)
.hc:
                moveq   #0,d0
                move.b  (a0)+,d0
                beq.s   .hdone
                cmp.b   #'a',d0
                blo.s   .hnoup
                cmp.b   #'z',d0
                bhi.s   .hnoup
                sub.b   #$20,d0                      ; toupper
.hnoup:
                mulu    #13,d1                       ; h*13 (h<=$7FF -> <26624, fits in a word)
                add.l   d0,d1
                and.l   #$7FF,d1
                bra.s   .hc
.hdone:
                divu.w  d3,d1                        ; d1 / ht_size -> remainder in the high word
                clr.w   d1
                swap    d1                           ; d1 = remainder = idx
                rts

; ofs_namecmp(a0=NUL-terminated query, a1=BCPL name [length byte + chars]) -> Z=1 if equal (ASCII case-insensitive).
; Preserves d2/a0/a1 (movem does not touch the CCR -> the Z of the last moveq survives the rts).
ofs_namecmp:
                movem.l d2/a0/a1,-(sp)
                moveq   #0,d1
                move.b  (a1)+,d1                     ; d1 = stored length
.nc_loop:
                tst.l   d1
                beq.s   .nc_qend                     ; stored name exhausted
                moveq   #0,d0
                move.b  (a0)+,d0                     ; query char
                beq.s   .nc_ne                       ; query shorter -> different
                cmp.b   #'a',d0
                blo.s   .nc_u0
                cmp.b   #'z',d0
                bhi.s   .nc_u0
                sub.b   #$20,d0
.nc_u0:
                moveq   #0,d2
                move.b  (a1)+,d2                     ; stored char
                cmp.b   #'a',d2
                blo.s   .nc_u1
                cmp.b   #'z',d2
                bhi.s   .nc_u1
                sub.b   #$20,d2
.nc_u1:
                cmp.b   d0,d2
                bne.s   .nc_ne
                subq.l  #1,d1
                bra.s   .nc_loop
.nc_qend:
                tst.b   (a0)                         ; stored name finished -> query must be at the NUL
                bne.s   .nc_ne
                moveq   #0,d0                        ; equal -> set Z=1
                bra.s   .nc_ret
.nc_ne:
                moveq   #1,d0                        ; different -> set Z=0
.nc_ret:
                movem.l (sp)+,d2/a0/a1               ; movem does not modify the CCR
                rts

; ofs_fib_fill(d0=header block, a1=fib; block ALREADY read into IOREQ_SZ(a3)): fills the FileInfoBlock like a packet
; handler: DiskKey = block; DirEntryType = EntryType = sec_type (<0 file, >0 directory); FileName and Comment
; as BSTRs (length byte + chars + NUL; dos.library converts them to C strings for Examine/ExNext, BCPL clients
; that send the packet themselves read the BSTR); Protection, DateStamp; file: Size = byte_size and
; NumBlocks = OFS data blocks. The root (ST_ROOT) has neither protection nor comment at these offsets (bm_pages).
; Names capped (30 / 79 chars, anti-corruption bound). Clobbers d0/d1/a0/a1.
ofs_fib_fill:
                move.l  d2,-(sp)
                move.l  d0,FIB_DISKKEY(a1)
                lea     IOREQ_SZ(a3),a0              ; a0 = header block buffer
                move.l  OFSB_SECTYPE(a0),d0          ; secondary type
                move.l  d0,FIB_DIRENTRYTYPE(a1)
                move.l  d0,FIB_ENTRYTYPE(a1)
                move.l  OFSB_DAYS(a0),FIB_DATE(a1)
                move.l  OFSB_MINS(a0),FIB_DATE+4(a1)
                move.l  OFSB_TICKS(a0),FIB_DATE+8(a1)
                clr.l   FIB_SIZE(a1)
                clr.l   FIB_NUMBLOCKS(a1)
                clr.l   FIB_PROTECTION(a1)
                clr.b   FIB_COMMENT(a1)
                clr.b   FIB_COMMENT+1(a1)
                cmp.l   #OFS_ST_ROOT,d0
                beq.s   .ff_name
                move.l  OFSB_PROTECT(a0),FIB_PROTECTION(a1)
                movem.l a0-a1,-(sp)
                lea     OFSB_COMMENT(a0),a0
                lea     FIB_COMMENT(a1),a1
                moveq   #79,d2
                bsr.s   ofs_fib_bstr
                movem.l (sp)+,a0-a1
                tst.l   FIB_DIRENTRYTYPE(a1)
                bpl.s   .ff_name                     ; directory: size 0
                move.l  OFSB_FILESIZE(a0),d0
                move.l  d0,FIB_SIZE(a1)
                add.l   #OFS_DMAX-1,d0               ; data blocks = ceil(size / 488)
                divu    #OFS_DMAX,d0
                and.l   #$0000FFFF,d0
                move.l  d0,FIB_NUMBLOCKS(a1)
.ff_name:
                lea     OFSB_NAME(a0),a0
                lea     FIB_FILENAME(a1),a1
                moveq   #30,d2
                bsr.s   ofs_fib_bstr
                move.l  (sp)+,d2
                rts

; ofs_fib_bstr(a0 = source BSTR, a1 = dest, d2 = max length): copies the BSTR (length capped) + a final NUL.
; Clobbers d0/d1/a0/a1.
ofs_fib_bstr:
                moveq   #0,d0
                move.b  (a0)+,d0
                cmp.l   d2,d0
                bls.s   .fb_cap
                move.l  d2,d0
.fb_cap:
                move.b  d0,(a1)+
                move.l  d0,d1
                bra.s   .fb_next
.fb_cpy:
                move.b  (a0)+,(a1)+
.fb_next:
                dbra    d1,.fb_cpy
                clr.b   (a1)
                rts

; ofs_name_to_block(a0=NUL-terminated path, d0=starting directory block (0 = root), a6=SysBase) -> d0 = header block
; of the object | 0. AmigaDOS semantics: "xxx:" prefix -> starts from the ROOT (dos has already chosen the volume);
; otherwise starts from the given directory (key of the parent lock). Empty path -> the starting directory itself.
; '/'-separated components; an EMPTY component (leading "/" or "//") goes up to the PARENT; a final '/' after a name
; is neutral. The final component may be a file OR a directory. Reuses ofs_split / ofs_dir_lookup / ofs_read_block.
ofs_name_to_block:
                movem.l d2-d7/a2-a5,-(sp)
                move.l  d0,d4                        ; d4 = current directory
                bne.s   .n2b_start
                move.l  #OFS_ROOTBLK,d4
.n2b_start:
                move.l  a0,a1                        ; a1 = scan for an "xxx:" prefix
.n2b_colon:
                move.b  (a1)+,d0
                beq.s   .n2b_nocolon                 ; NUL -> no ':'
                cmp.b   #':',d0
                bne.s   .n2b_colon
                move.l  a1,a0                         ; a0 = just after the ':'
                move.l  #OFS_ROOTBLK,d4              ; "xxx:" -> root of the volume
.n2b_nocolon:
                tst.b   (a0)
                bne.s   .n2b_resolve
                move.l  d4,d0                         ; empty path -> the starting directory (no alloc)
                movem.l (sp)+,d2-d7/a2-a5
                rts
.n2b_resolve:
                lea     -OFS_FRAME(sp),sp            ; local frame (comp + path cursor + last flag)
                move.l  a0,LF_PATHCUR(sp)
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .n2b_fail                    ; no trackdisk (nothing allocated)
                move.l  d0,a2
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .n2b_fail                    ; no RAM (nothing to free)
                move.l  d0,a3
                moveq   #0,d6                         ; d6 = 0 as long as no component has been processed
.n2b_nextcomp:
                lea     LF_COMP(sp),a4
                move.l  LF_PATHCUR(sp),a0
                bsr     ofs_split                    ; (a4) = component; a0 advances; d0 = 1 if last
                move.l  a0,LF_PATHCUR(sp)
                move.b  d0,LF_LAST(sp)
                tst.b   (a4)
                bne.s   .n2b_lookup
                tst.b   LF_LAST(sp)                  ; empty component:
                beq.s   .n2b_parent                  ;   in the middle ("/", "//") -> parent
                tst.l   d6
                bne.s   .n2b_hit                     ;   final, after a name ("dir/") -> neutral
.n2b_parent:
                move.l  d4,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .n2b_notfound
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_PARENT(a0),d4           ; go up one level
                beq.s   .n2b_notfound                ; parent of the root -> invalid
                bra.s   .n2b_compdone
.n2b_lookup:
                bsr     ofs_dir_lookup               ; (d4, a4) -> d0 = block | 0 (preserves d4/d6/a4)
                tst.l   d0
                beq.s   .n2b_notfound                ; component not found
                move.l  d0,d4                         ; d4 = block of the component
                tst.b   LF_LAST(sp)
                bne.s   .n2b_hit                      ; last -> final object (file OR dir)
                move.l  d4,d0                         ; intermediate: must be a USERDIR
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .n2b_notfound
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_ST_USERDIR,OFSB_SECTYPE(a0)
                bne.s   .n2b_notfound                ; not a subdir -> invalid path
.n2b_compdone:
                moveq   #1,d6
                tst.b   LF_LAST(sp)
                beq.s   .n2b_nextcomp
.n2b_hit:
                move.l  d4,d7                         ; d7 = result block
                bra.s   .n2b_free
.n2b_notfound:
                moveq   #0,d7
.n2b_free:
                move.l  a3,a1                         ; free ioreq + buffer
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d7,d0
                lea     OFS_FRAME(sp),sp
                movem.l (sp)+,d2-d7/a2-a5
                rts
.n2b_fail:
                moveq   #0,d0                         ; failure before/during alloc -> nothing to free
                lea     OFS_FRAME(sp),sp
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ofs_fill_fib(d0=header block, a1=fib, a6=SysBase) -> d0 = 1 OK / 0 failed. Reads the block then fills the FIB
; (ofs_fib_fill). Internal trackdisk/ioreq setup. Resetting the enumeration cursor is up to the caller.
ofs_fill_fib:
                movem.l d2-d7/a2-a5,-(sp)
                moveq   #0,d7                         ; default result
                move.l  d0,d4                         ; d4 = block
                move.l  a1,a5                         ; a5 = fib
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq.s   .fib_ret                     ; no trackdisk (nothing allocated)
                move.l  d0,a2
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .fib_ret                     ; no RAM (nothing to free)
                move.l  d0,a3
                move.l  d4,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .fib_free                    ; read failed
                move.l  d4,d0
                move.l  a5,a1
                bsr     ofs_fib_fill
                moveq   #1,d7
.fib_free:
                move.l  a3,a1
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
.fib_ret:
                move.l  d7,d0
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ofs_dir_next(d0=dirblock, d1=bucket, d2=chain, a1=fib, a6=SysBase) -> d0 = 1 found / 0 end; d1 = updated bucket,
; d2 = updated chain (cursor to pass back as is on the next call). Walks the current hash chain then advances
; bucket by bucket through the directory hashtable; fills the FIB of the entry found. Internal trackdisk/ioreq
; setup. Reuses ofs_read_block / ofs_blk_valid / ofs_fib_fill. Preserves d3-d7/a2-a5; returns in d0/d1/d2
; (outside the movem). RED OFS_NO_DIRNEXT: returns found=0 straight away (ExNext never finds anything).
ofs_dir_next:
                movem.l d3-d7/a2-a5,-(sp)
                move.l  d0,d4                         ; d4 = dirblock
                move.l  d1,d5                         ; d5 = bucket
                move.l  d2,d6                         ; d6 = chain
                move.l  a1,a5                         ; a5 = fib
                ifne    OFS_NO_DIRNEXT
                moveq   #0,d0                         ; RED: immediate end (nothing allocated)
                move.l  d5,d1
                move.l  d6,d2
                movem.l (sp)+,d3-d7/a2-a5
                rts
                endc
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .dn_noalloc
                move.l  d0,a2
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .dn_noalloc
                move.l  d0,a3
.dn_loop:
                tst.l   d6                            ; current chain not empty?
                beq.s   .dn_advbucket
                move.l  d6,d2                         ; validate the chain block
                bsr     ofs_blk_valid
                beq.s   .dn_chainend                  ; invalid -> end of chain -> advance bucket
                move.l  d6,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .dn_end_notfound
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_HASHCHAIN(a0),d3         ; d3 = next chain entry (before fib_fill touches the buffer)
                move.l  d6,d0                         ; current block = DiskKey
                move.l  a5,a1
                bsr     ofs_fib_fill
                move.l  d3,d6                         ; the chain cursor advances
                moveq   #1,d7                         ; found
                bra.s   .dn_end
.dn_chainend:
                moveq   #0,d6                         ; force the bucket advance
.dn_advbucket:
                move.l  d4,d0                         ; (re)read the dir block: ht_size + hashtab[bucket]
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .dn_end_notfound
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_SHORT,OFSB_TYPE(a0)
                bne.s   .dn_end_notfound              ; not a directory block
                move.l  OFSB_HTSIZE(a0),d7            ; ht_size (stored for root; userdir long[3]=0 -> default)
                beq.s   .dn_htdef
                cmp.l   #OFS_HTMAX,d7
                blo.s   .dn_scan
.dn_htdef:
                moveq   #OFS_HTDEF,d7
.dn_scan:
                cmp.l   d7,d5                         ; bucket >= ht_size ?
                bhs.s   .dn_end_notfound              ; buckets exhausted -> end of enumeration
                lea     IOREQ_SZ(a3),a0
                move.l  d5,d0
                lsl.l   #2,d0
                lea     OFSB_HASHTAB(a0),a0
                move.l  0(a0,d0.l),d6                 ; chain = hashtab[bucket]
                addq.l  #1,d5                         ; bucket++ (does not rescan the current bucket)
                tst.l   d6
                beq.s   .dn_scan                      ; empty bucket -> next
                bra.s   .dn_loop                      ; chain not empty -> emit
.dn_end_notfound:
                moveq   #0,d7
.dn_end:
                move.l  a3,a1                         ; free ioreq + buffer
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d7,d0                         ; found
                move.l  d5,d1                         ; updated bucket
                move.l  d6,d2                         ; updated chain
                movem.l (sp)+,d3-d7/a2-a5
                rts
.dn_noalloc:
                moveq   #0,d0
                move.l  d5,d1
                move.l  d6,d2
                movem.l (sp)+,d3-d7/a2-a5
                rts

; ofs_stream_open(a0=NUL-terminated path, a1=SS_* state, d0=starting directory (0 = root), a6=SysBase) -> d0 = 1 OK /
; 0 failed. Resolves the path -> header block
; (must be a FILE), FindName trackdisk -> SS_TRACKDISK, reads the header via the state's ioreq, stores SS_SIZE
; (byte_size) + SS_FIRSTDATA, initialises the cursor (POS=0, CURBLK=first_data, BLKBASE=0). Allocates NOTHING (the
; state, ioreq + block buffer included, is allocated by the caller = the handler).
ofs_stream_open:
                movem.l d2-d7/a2-a5,-(sp)
                move.l  a1,a5                        ; a5 = state
                bsr     ofs_name_to_block            ; (a0=path, d0=start) -> d0 = block | 0 (preserves a5)
                tst.l   d0
                beq.s   .so_fail
                move.l  d0,d4                         ; d4 = header block
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq.s   .so_fail
                move.l  d0,SS_TRACKDISK(a5)
                move.l  d0,a2                         ; a2 = trackdisk
                lea     SS_IOREQ(a5),a3               ; a3 = ioreq of the state (block buffer at +IOREQ_SZ)
                move.l  d4,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .so_fail
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_SHORT,OFSB_TYPE(a0)
                bne.s   .so_fail                      ; not a header
                cmp.l   #OFS_ST_FILE,OFSB_SECTYPE(a0)
                bne.s   .so_fail                      ; not a FILE (dir -> failure, like the old ofs_read_file)
                move.l  OFSB_FILESIZE(a0),SS_SIZE(a5)
                move.l  d4,SS_HEADER(a5)
                move.l  OFSB_FIRSTDATA(a0),d0
                move.l  d0,SS_FIRSTDATA(a5)
                move.l  d0,SS_CURBLK(a5)
                clr.l   SS_POS(a5)
                clr.l   SS_BLKBASE(a5)
                moveq   #1,d0
                bra.s   .so_ret
.so_fail:
                moveq   #0,d0
.so_ret:
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ofs_stream_read(a1=state, a2=dest, d0=len, a6=SysBase) -> d0 = bytes copied (0 = EOF). Incremental loop: loads
; the current data block (512 bytes), advances block by block via next_data when the block is exhausted, copies
; min(rest of block, rest requested, rest up to EOF). Keeps the cursor (POS/CURBLK/BLKBASE) in the state between calls.
; Preserves d2-d7/a2-a5 (dest reassigned to a4); a single 512-byte buffer, NEVER a whole-file buffer.
ofs_stream_read:
                movem.l d2-d7/a2-a5,-(sp)
                move.l  a1,a5                         ; a5 = state
                move.l  a2,a4                         ; a4 = dest (advances)
                move.l  d0,d6                         ; d6 = rest requested
                moveq   #0,d5                         ; d5 = total copied
                move.l  SS_SIZE(a5),d7                ; d7 = effective size (EOF)
                ifne    STREAM_CAP32K
                cmp.l   #32768,d7
                bls.s   .sr_capok                     ; RED: re-caps the read at 32 KB -> file > 32 KB truncated
                move.l  #32768,d7
.sr_capok:
                endc
                move.l  SS_TRACKDISK(a5),a2           ; a2 = trackdisk
                lea     SS_IOREQ(a5),a3               ; a3 = ioreq (buffer at +IOREQ_SZ)
.sr_loop:
                tst.l   d6
                beq     .sr_done                      ; nothing more requested
                move.l  SS_POS(a5),d0
                cmp.l   d7,d0
                bhs     .sr_done                      ; pos >= effective size -> EOF
                move.l  SS_CURBLK(a5),d2
                bsr     ofs_blk_valid
                beq     .sr_done                      ; invalid block (0 / out of bounds) -> end
                move.l  SS_CURBLK(a5),d0
                bsr     ofs_read_block
                tst.l   d0
                beq     .sr_done
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_DATA,OFSB_TYPE(a0)
                bne     .sr_done                      ; not an OFS data block -> end
                move.l  OFSB_DSIZE(a0),d3             ; data_size of the block
                cmp.l   #OFS_DMAX,d3
                bls.s   .sr_dsok
                move.l  #OFS_DMAX,d3                  ; absurd data_size -> clamp (anti-corruption)
.sr_dsok:
                move.l  SS_POS(a5),d0
                sub.l   SS_BLKBASE(a5),d0             ; within = pos - blkbase
                cmp.l   d3,d0
                blo.s   .sr_haveblock                 ; within < data_size -> copy from this block
                add.l   d3,SS_BLKBASE(a5)             ; block exhausted -> advance to the next one
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_NEXT(a0),SS_CURBLK(a5)
                bra     .sr_loop
.sr_haveblock:
                move.l  d3,d4
                sub.l   d0,d4                         ; avail = data_size - within
                cmp.l   d6,d4
                bls.s   .sr_clampeof
                move.l  d6,d4                         ; n = min(avail, rest requested)
.sr_clampeof:
                move.l  d7,d1
                sub.l   SS_POS(a5),d1                 ; rest up to EOF
                cmp.l   d1,d4
                bls.s   .sr_copy
                move.l  d1,d4                         ; n = min(n, rest to EOF)
.sr_copy:
                lea     IOREQ_SZ(a3),a0
                lea     OFSB_DATA(a0),a0
                add.l   d0,a0                         ; src = buffer + data + within
                move.l  d4,d1
                beq     .sr_loop                      ; n == 0 (guard) -> loop again (EOF/advance on the next round)
.sr_cpy:
                move.b  (a0)+,(a4)+
                subq.l  #1,d1
                bne.s   .sr_cpy
                add.l   d4,SS_POS(a5)                 ; pos += n
                add.l   d4,d5                         ; total += n
                sub.l   d4,d6                         ; rest requested -= n
                move.l  d0,d1                          ; d1 = within (d0) + n (d4)
                add.l   d4,d1
                cmp.l   d3,d1                          ; reached the block edge (within+n == data_size)?
                blo     .sr_loop                      ; no -> loop again (EOF or rest requested exhausted, no re-read)
                add.l   d3,SS_BLKBASE(a5)             ; at edge -> advance via the ALREADY loaded buffer (no re-read)
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_NEXT(a0),SS_CURBLK(a5)
                bra     .sr_loop                      ; (loop top also advances after a seek: within >= data_size)
.sr_done:
                move.l  d5,d0
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ofs_stream_seek(a1=state, d0=absolute target position, a6=SysBase). Repositions the cursor. Outside the current
; block, data block number pos/488 is taken directly from the header table (72 blocks) then from extension blocks, like
; the filesystem: a few reads instead of following the chain block by block (a game that reads its data file
; through Seek + Read used to re-read hundreds of blocks per Seek). Unreadable table: back to the first data block,
; the forward walk happening on the next Read. Clamping to [0, SS_SIZE] is up to the caller (handler). Clobbers a0/a1.
ofs_stream_seek:
                movem.l d2-d4/a2-a3/a5,-(sp)
                move.l  a1,a5
                move.l  d0,SS_POS(a5)
                move.l  d0,d1
                sub.l   SS_BLKBASE(a5),d1
                bcs.s   .sk_direct
                cmp.l   #OFS_DMAX,d1
                blo.s   .sk_ret                       ; within the current block
.sk_direct:                                           ; block number k = pos / 488: header then extensions, 72 per block
                move.l  d0,d4
                divu    #OFS_DMAX,d4
                and.l   #$FFFF,d4                     ; d4 = k
                move.l  d4,d2
                move.l  SS_TRACKDISK(a5),a2
                lea     SS_IOREQ(a5),a3
                move.l  SS_HEADER(a5),d3
.sk_ext:
                move.l  d3,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .sk_chain
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_TABLE,d2
                blo.s   .sk_tab
                move.l  OFSB_EXTENSION(a0),d3
                beq.s   .sk_chain
                sub.l   #OFS_TABLE,d2
                bra.s   .sk_ext
.sk_tab:
                moveq   #OFS_TABLE-1,d0               ; reversed table: the 1st block is the last long
                sub.l   d2,d0
                lsl.l   #2,d0
                move.l  OFSB_HASHTAB(a0,d0.l),d1
                beq.s   .sk_chain
                move.l  d1,SS_CURBLK(a5)
                mulu    #OFS_DMAX,d4
                move.l  d4,SS_BLKBASE(a5)
                bra.s   .sk_ret
.sk_chain:                                            ; unreadable table (end of file...): walk the chain
                move.l  SS_POS(a5),d0
                cmp.l   SS_BLKBASE(a5),d0
                bhs.s   .sk_ret
                move.l  SS_FIRSTDATA(a5),SS_CURBLK(a5)
                clr.l   SS_BLKBASE(a5)
.sk_ret:
                movem.l (sp)+,d2-d4/a2-a3/a5
                rts
OFS_TABLE       EQU 72                        ; data block numbers per header / extension

ofs_td_name:
                dc.b    "trackdisk.device",0
                even
