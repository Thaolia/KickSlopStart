; src/dos/ofs.i - OFS constants (Old File System, D1 read-only). PUBLIC format (ADF-FAQ / AmigaDOS Technical
; Reference) LOCKED DOWN empirically on a test ADF (asset, NOT the ROM). NO ROM reading.
; 512-byte block = 128 longs; "end of block" offsets = (128 - k) longs.

OFS_BSIZE       EQU 512
OFS_ROOTBLK     EQU 880           ; root block of a DD disk (1760 logical blocks, 0..1759)
OFS_NBLK        EQU 1760          ; total number of blocks -> valid block in [2,1760) (0/1 = bootblock)
IOREQ_SZ        EQU 48            ; IOStdReq (the block buffer follows at +IOREQ_SZ)

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
OFSB_PARENT     EQU 500           ; long[125] (= (128-3)): parent directory block (0 for the root)
OFSB_SECTYPE    EQU 508           ; long[127] (= (128-1)): secondary type (ST_FILE=-3)
; allocation bitmap (root block) - disk-validator (#4), offsets checked on the test ADF
OFSB_BMFLAG     EQU 312           ; long[78] (= BSIZE-200): bm_flag ($FFFFFFFF = bitmap valid; 0 = needs revalidation)
OFSB_BMPAGES    EQU 316           ; long[79] (= BSIZE-196): bm_pages[0] = number of the 1st bitmap block
OFSB_BMBITS     EQU 4             ; bitmap block: long[0] = checksum; the bits start at long[1] (@4)

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
SS_IOREQ        EQU 32            ; IOStdReq (IOREQ_SZ bytes); the block buffer follows at +IOREQ_SZ (OFS_BSIZE bytes)
WS_VOL          EQU 36            ; BPTR: volume node of a write state (ofswrite.s), like SS_VOL
SS_ALLOC        EQU SS_IOREQ+IOREQ_SZ+OFS_BSIZE   ; total AllocMem size of the state

; STREAM_CAP32K=1 (RED streaming): ofs_stream_read re-caps the read at 32768 bytes (= the old whole-file cap)
; -> a file > 32 KB (BigData, 48000 bytes) is truncated -> "OFS STREAM OK" missing. All files < 32 KB
; (kickslop/d3dtest/e3cmd/bigseg/startup-sequence) are still read ENTIRELY -> D3B/D3C/D3D/E3/F1/D3E/LOADSEG BIG
; stay GREEN = isolates PRECISELY the raising of the cap (the streaming payoff) from the rest of the read path.
; Default 0.
STREAM_CAP32K   EQU 0
