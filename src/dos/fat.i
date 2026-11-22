; src/dos/fat.i - FAT12/16/32 read-only backend of the ROM file-handler (fat.s). Layout of the FAT volume context,
; allocated when a FAT volume is mounted and found through HC_GEO+GEO_FAT (ofs.i). On-disk format: Microsoft
; "FAT: General Overview of On-Disk Format" (fatgen103, public). All on-disk fields are little-endian.

FAT_ROOTKEY     EQU 1             ; lock key of the root directory: an entry key is sector * 16 + index, and sector 0
                                  ; is the boot sector, so no entry has a key below 16
FAT_NAMEMAX     EQU 30            ; longest long name shown (AmigaDOS limit); a longer one shows its 8.3 name
FAT_LFNMAX      EQU 20            ; long-name entries per name (13 characters each, 255 characters at most)
FAT_COMPMAX     EQU 32            ; path component buffer: 31 characters + NUL (longer components match nothing)
FAT_DIRMAX      EQU 65536         ; entries a directory may hold (2 MB, fatgen103): bound of a directory walk
FAT_SCANMAX     EQU 512           ; FAT sectors counted for the free space when FSInfo gives no figure (256 KB)
FAT_CDATE       EQU 484           ; hnd_findvol (handler.s) reads the volume date at this offset of the context's
                                  ; block buffer and the volume name (BSTR) at OFSB_NAME: fat_mount puts them there

FC_OFSROOT      EQU 0             ; LONG: GEO_ROOT computed by hnd_open, given back when the volume goes
FC_TYPE         EQU 4             ; LONG: 12, 16 or 32
FC_SPC          EQU 8             ; LONG: sectors per cluster (power of 2, 1-128)
FC_SHIFT        EQU 12            ; LONG: log2 of FC_SPC
FC_FATSEC0      EQU 16            ; LONG: first sector of the FAT that is read (the active one on FAT32)
FC_FATSZ        EQU 20            ; LONG: sectors per FAT
FC_ROOTSEC      EQU 24            ; LONG: FAT12/16: first sector of the fixed root directory
FC_ROOTN        EQU 28            ; LONG: FAT12/16: sectors of the fixed root directory
FC_DATA         EQU 32            ; LONG: first sector of the data area (cluster 2)
FC_NCLUS        EQU 36            ; LONG: data clusters; valid cluster numbers are 2 .. FC_NCLUS + 1
FC_ROOTCL       EQU 40            ; LONG: FAT32: first cluster of the root directory; 0 on FAT12/16
FC_FREE         EQU 44            ; LONG: free clusters, -1 while unknown
FC_VDATE        EQU 48            ; DateStamp (3 LONGs): volume date
FC_KEY          EQU 60            ; LONG: key of the object fat_scan found last
FC_LKEY         EQU 64            ; LONG: key of the first long-name entry of the set being assembled
FC_LSEQ         EQU 68            ; BYTE: next long-name ordinal expected, 0 = none
FC_LCHK         EQU 69            ; BYTE: checksum the long-name entries carry
FC_LCNT         EQU 70            ; BYTE: long-name entries of the set (characters: 13 each)
FC_LDONE        EQU 71            ; BYTE: a complete set waits for its short entry
FC_ENT          EQU 72            ; 32 bytes: short entry of the object fat_scan found last
FC_NAME         EQU 104           ; C string: its name as shown (FAT_NAMEMAX + NUL)
FC_SNAME        EQU 136           ; C string: its 8.3 name (12 + NUL)
FC_VNAME        EQU 150           ; C string: volume name (11 + NUL)
FC_LFN          EQU 162           ; long name being assembled, Latin-1 (FAT_LFNMAX * 13 bytes)
FC_IO           EQU 424           ; IOStdReq of the cached sector reads (IOREQ_SZ)
FC_FATSEC       EQU 472           ; LONG: sector held in FC_FATSEC+4 (512 bytes), -1 = none
FC_DIRSEC       EQU FC_FATSEC+4+OFS_BSIZE ; LONG: sector held in FC_DIRSEC+4 (512 bytes), -1 = none
FC_SIZE         EQU FC_DIRSEC+4+OFS_BSIZE
