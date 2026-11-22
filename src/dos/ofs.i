; src/dos/ofs.i - OFS constants (Old File System, D1 read-only). PUBLIC format (ADF-FAQ / AmigaDOS Technical
; Reference) LOCKED DOWN empirically on a test ADF (asset, NOT the ROM). NO ROM reading.
; 512-byte block = 128 longs; "end of block" offsets = (128 - k) longs.

OFS_BSIZE       EQU 512
OFS_ROOTBLK     EQU 880           ; root block of a DD disk (1760 logical blocks, 0..1759): default geometry
OFS_NBLK        EQU 1760          ; total number of blocks of a DD disk -> valid block in [2,1760) (0/1 = bootblock)
OFS_CHAINMAX    EQU 1760          ; bound on a hash chain or a data chain walk (a corrupted chain that loops)
OFS_BMBITS_N    EQU 127*32        ; blocks covered by one bitmap block (127 longs after its checksum)
IOREQ_SZ        EQU 48            ; IOStdReq (the block buffer follows at +IOREQ_SZ)

; File-handler context (handler.s), one per drive or partition, in tc_UserData of its process: the OFS layer (ofs.s,
; ofswrite.s) runs in that process and takes from it the device and unit to read (HC_TDIO, opened from the
; FileSysStartupMsg of its DeviceNode), the partition geometry (HC_GEO) and the write context. Other callers (boot
; probes, tc_UserData = 0) read DF0 with the DD geometry (ofs_geodef).
HC_TDIO         EQU 0             ; device IOStdReq (disk change queries), then a 512-byte block buffer
HC_OWCTX        EQU HC_TDIO+IOREQ_SZ+OFS_BSIZE   ; APTR: write context (ofswrite.s), allocated on first need | 0
HC_GEO          EQU HC_OWCTX+4    ; partition geometry (GEO_*)
; geometry (blocks are numbered from the start of the partition; the device sees (GEO_POFF + 512 * block))
GEO_ROOT        EQU 0             ; LONG: root block = (GEO_NBLK - 1 + GEO_RES) / 2
GEO_NBLK        EQU 4             ; LONG: blocks in the partition; a valid key is in [GEO_RES, GEO_NBLK)
GEO_RES         EQU 8             ; LONG: reserved blocks at the start (de_Reserved: boot blocks)
GEO_POFF        EQU 12            ; LONG: byte offset of the partition on the device (de_LowCyl * cylinder size)
GEO_PORT        EQU 16            ; APTR: reply port of the handler's I/O requests (devices that queue them) | 0
GEO_TICKS       EQU 20            ; LONG: write-back countdown, set to 3 on every transfer (rom-filesystem §8.4)
GEO_WPROT       EQU 24            ; LONG: the disk was write-protected when mounted (TD_PROTSTATUS) | 0
GEO_DOSTYPE     EQU 28            ; LONG: last byte of the mounted disk's "DOS\n" (0-3), taken from its first reserved
                                  ; block at mount time: bit GEOB_FFS = data blocks without header, bit GEOB_INTL =
                                  ; international name hash and comparison. 0 (OFS) outside a file-handler.
GEO_SIZE        EQU 32
GEOB_FFS        EQU 0
GEOB_INTL       EQU 1

; LONG offsets (in bytes from the start of the block)
OFSB_TYPE       EQU 0             ; long[0]: primary type (T_SHORT=2 / T_DATA=8)
OFSB_HTSIZE     EQU 12            ; long[3]: hash_table_size (root)
OFSB_DSIZE      EQU 12            ; long[3]: data_size (OFS data block) - same offset
OFSB_FIRSTDATA  EQU 16            ; long[4]: first_data (file header)
OFSB_NEXT       EQU 16            ; long[4]: next_data (OFS data block) - same offset
OFSB_HASHTAB    EQU 24            ; long[6]: start of the hash table (header)
OFSB_DATA       EQU 24            ; OFS data block: data bytes @ +24
OFSB_FILESIZE   EQU 324           ; long[81] (= BSIZE-188): byte_size of a file header (size in bytes).
                                  ; Checked on the test ADF: kickslop (block 866) -> 1024. The boot assertion
                                  ; fib_Size==1024 reconfirms it (read@324 -> write@124 -> readback). NO ROM reading.
OFSB_PROTECT    EQU 320           ; long[80] (= BSIZE-192): protection bits (file / directory header)
OFSB_COMMENT    EQU 328           ; long[82] (= BSIZE-184): BCPL comment (length byte + 79 chars max)
OFSB_DAYS       EQU 420           ; long[105] (= BSIZE-92): modification DateStamp (days, minutes, ticks)
OFSB_MINS       EQU 424
OFSB_TICKS      EQU 428
OFSB_NAME       EQU 432           ; long[108] (= (128-20)): BCPL name (length byte + chars)
OFSB_HASHCHAIN  EQU 496           ; long[124] (= (128-4)): hash_chain (next header in the same bucket)
OFSB_EXTENSION  EQU 504           ; long[126]: extension block (72 more data blocks) | 0
OFSB_TABEND     EQU OFSB_HASHTAB+71*4 ; header / extension: last table entry = first data block of the group
OFS_T_LIST      EQU 16            ; primary type of a file extension block
OFSB_PARENT     EQU 500           ; long[125] (= (128-3)): parent directory block (0 for the root)
OFSB_SECTYPE    EQU 508           ; long[127] (= (128-1)): secondary type (ST_FILE=-3)
; allocation bitmap (root block) - disk-validator (#4), offsets checked on the test ADF
OFSB_BMFLAG     EQU 312           ; long[78] (= BSIZE-200): bm_flag ($FFFFFFFF = bitmap valid; 0 = needs revalidation)
OFSB_BMPAGES    EQU 316           ; long[79] (= BSIZE-196): bm_pages[0] = number of the 1st bitmap block
OFSB_BMBITS     EQU 4             ; bitmap block: long[0] = checksum; the bits start at long[1] (@4)
OFSB_BMEXT      EQU 416           ; long[104]: first bitmap extension block (127 keys, then the next extension) | 0
OFSB_CKSUM      EQU 20            ; long[5]: checksum of a header / data / extension block (sum of the longs = 0)

; write context of a file-handler (ofswrite.s, allocated on first need; pointer in HC_OWCTX)
OW_TD           EQU 0             ; APTR: device
OW_IO           EQU 4             ; IOStdReq
OW_BMST         EQU OW_IO+IOREQ_SZ ; LONG: bitmap state: 0 not read, 1 loaded, -1 validation failed (213)
OW_BMN          EQU OW_BMST+4     ; LONG: bitmap blocks of the partition
OW_BMKEYS       EQU OW_BMN+4      ; APTR: OW_BMN keys (the bitmap blocks), followed by the OW_BMNS cache entries | 0
OW_DIRTY        EQU OW_BMKEYS+4   ; LONG: volume modified since the last write-back (root flag 0 on the disk)
OW_HINT         EQU OW_DIRTY+4    ; LONG: every block in [root + 1, OW_HINT) is in use (allocation starts there)
OW_ERR          EQU OW_HINT+4     ; LONG: last error (dos code)
OW_BMNS         EQU OW_ERR+4      ; LONG: cache entries (BME_*): min(OW_BMN, OW_BMCACHE)
OW_BMSLOT       EQU OW_BMNS+4     ; APTR: the first cache entry
OW_BMLAST       EQU OW_BMSLOT+4   ; APTR: the entry used last (looked at first)
OW_BMTICK       EQU OW_BMLAST+4   ; LONG: use counter (BME_AGE: least recently used entry replaced)
OW_BMFREE       EQU OW_BMTICK+4   ; LONG: free blocks of the partition (counted at load, then kept up to date)
OW_BMFL         EQU OW_BMFREE+4   ; 25 BYTEs, one per bitmap block of the root's table: bit 0 modified since the last
                                  ; write-back, bit 1 already moved for the coming one (ow_bmmove). Addressed as
                                  ; OW_BMFL(a5,Dn): must stay below offset 128 (8-bit displacement)
OW_B1           EQU OW_BMFL+28    ; two block buffers
OW_B2           EQU OW_B1+OFS_BSIZE
OW_PATH         EQU OW_B2+OFS_BSIZE  ; path copy (OW_PATHMAX)
OW_PATHMAX      EQU 128
OW_NAME         EQU OW_PATH+OW_PATHMAX   ; final name (32)
OW_RB           EQU OW_NAME+32    ; the root block, for the bitmap flag (first change, write-back)
OW_SIZE         EQU OW_RB+OFS_BSIZE
OW_BMCACHE      EQU 8             ; bitmap blocks held in memory at most, whatever the size of the partition
; one cached bitmap block
BME_IDX         EQU 0             ; LONG: its index in the bitmap (its key: OW_BMKEYS) | -1 (empty)
BME_AGE         EQU 4             ; LONG: OW_BMTICK at its last use
BME_DIRTY       EQU 8             ; BYTE: modified since written
BME_DATA        EQU 12            ; the 512-byte block (checksum at long 0)
BME_SIZE        EQU BME_DATA+OFS_BSIZE

OFS_T_SHORT     EQU 2             ; primary type root/header
OFS_T_DATA      EQU 8             ; primary type OFS data block
OFS_ST_FILE     EQU -3            ; secondary type of a file
OFS_ST_ROOT     EQU 1             ; secondary type of the root block
OFS_ST_USERDIR  EQU 2             ; secondary type of a user directory (subdir)
OFS_DMAX        EQU 488           ; max data bytes per OFS data block (BSIZE-24)
OFS_HTMAX       EQU 128           ; bound on hash_table_size (must be 72; rejects a corrupted root)
OFS_HTDEF       EQU 72            ; default hash_table_size (BSIZE/4-56): USERDIRs leave long[3]=0 (measured)

; path traversal (subdirectories, '/'-separated) - local frame of ofs_read_file
OFS_COMPMAX     EQU 32            ; max length of a path component (+NUL); AmigaDOS names <= 30
LF_COMP         EQU 0             ; NUL-terminated component buffer (OFS_COMPMAX bytes)
LF_PATHCUR      EQU 32            ; LONG: current cursor in the path
LF_LAST         EQU 36            ; BYTE: 1 if the current component is the last one (-> file, otherwise -> userdir)
OFS_FRAME       EQU 40            ; size of the local frame (even)
; OFS_NO_SUBDIR=1 (RED): ofs_split does NOT treat '/' as a separator -> the whole path = 1 component looked up
; in the root -> "s/startup-sequence" not found -> startup-sequence not read -> F1BOOTOK/E3 missing. Default 0.
OFS_NO_SUBDIR   EQU 0

; OFS_NO_DATACHAIN=1 (RED D1): the read does NOT follow the next_data chain -> only the 1st data block (488 B) copied
; -> returned size == 488 != 1024 -> "D1 OFS READ OK" missing. Isolates the chaining of OFS data blocks. Default 0.
OFS_NO_DATACHAIN EQU 0

; OFS_NO_DIRNEXT=1 (RED Lock/Examine): ofs_dir_next immediately returns found=0 (end) -> ExNext NEVER finds an
; entry -> the enumeration part of "DOS LOCK EXAMINE OK" fails -> marker missing. ofs_read_file (D1) and
; ofs_name_to_block/ofs_fill_fib stay intact -> "D1 OFS READ OK" GREEN = isolates directory enumeration from the
; proven read path. Default 0.
OFS_NO_DIRNEXT  EQU 0

; --- OFS STREAMING state (one per FileHandle open on DF0:): incremental reading data block by data block,
; WITHOUT a whole-file buffer. A single AllocMem (SS_ALLOC) holds the fields + the IOStdReq + a 512-byte block buffer.
; The handler no longer caps the size of a file (the old DOS_FILEMAX cap was the whole-file buffer).
SS_TRACKDISK    EQU 0             ; APTR: trackdisk.device base (FindName at open time)
SS_SIZE         EQU 4             ; LONG: total byte_size (from the file header @324)
SS_POS          EQU 8             ; LONG: current absolute read position
SS_FIRSTDATA    EQU 12            ; LONG: first data block (rewind on backward seek)
SS_CURBLK       EQU 16            ; LONG: current data block (the one starting at SS_BLKBASE)
SS_BLKBASE      EQU 20            ; LONG: absolute offset of the start of the data of SS_CURBLK
SS_HEADER       EQU 24            ; LONG: header block of the file (block tables: direct seek)
SS_VOL          EQU 28            ; BPTR: volume node of the disk on which the file was opened (handler)
SS_LOCK         EQU 32            ; APTR: shared FileLock held while the file is open (handler)
SS_BUFBLK       EQU 36            ; LONG: data block held in the block buffer (0 = none): READ does not fetch it again
SS_WS           EQU 40            ; APTR: write state (ofswrite.s) taken at the first WRITE, which serves the file from
                                  ; then on (rom-filesystem §5.1: a FINDINPUT handle accepts writes) | 0
SS_TBLK         EQU 44            ; LONG: FFS: header or extension block held in the table buffer | 0
SS_TGRP         EQU 48            ; LONG: FFS: its group (0 = header, n = n-th extension block)
SS_FFS          EQU 52            ; LONG: the file was opened on an FFS volume (data blocks found through the tables)
SS_ASIZE        EQU 56            ; LONG: size of the AllocMem (FFS states end with the table buffer, SS_TBUF)
SS_IOREQ        EQU 60            ; IOStdReq (IOREQ_SZ bytes); the block buffer follows at +IOREQ_SZ (OFS_BSIZE bytes)
WS_HDR          EQU 4             ; LONG: header block of a write state (ofswrite.s)
WS_VOL          EQU 36            ; BPTR: volume node of a write state (ofswrite.s), like SS_VOL
WS_LOCK         EQU 64            ; APTR: exclusive FileLock held while a write state is open (handler)
SS_ALLOC        EQU SS_IOREQ+IOREQ_SZ+OFS_BSIZE   ; AllocMem size of an OFS state
SS_TBUF         EQU SS_ALLOC      ; FFS: table buffer (OFS_BSIZE bytes) after the block buffer
SS_ALLOCFFS     EQU SS_TBUF+OFS_BSIZE             ; AllocMem size of an FFS state

; STREAM_CAP32K=1 (RED streaming): ofs_stream_read re-caps the read at 32768 bytes (= the old whole-file cap)
; -> a file > 32 KB (BigData, 48000 bytes) is truncated -> "OFS STREAM OK" missing. All files < 32 KB
; (kickslop/d3dtest/e3cmd/bigseg/startup-sequence) are still read ENTIRELY -> D3B/D3C/D3D/E3/F1/D3E/LOADSEG BIG
; stay GREEN = isolates PRECISELY the raising of the cap (the streaming payoff) from the rest of the read path.
; Default 0.
STREAM_CAP32K   EQU 0
