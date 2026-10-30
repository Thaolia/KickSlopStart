; src/exec/disk.i — Paula/OCS disk registers + drive control bits (B2). Clean-room (HRM + NDK hardware/*).
; CUSTOM / CIAA_HW / CIAB_HW / DMACON / INTREQ / INTREQR are defined in exec.i (included BEFORE this file).

; --- custom disk registers (offsets from CUSTOM = $DFF000) ---
DSKPT    EQU CUSTOM+$020       ; disk DMA pointer (longword, chip RAM)
DSKLEN   EQU CUSTOM+$024       ; length in WORDS | DMAEN(b15) | WRITE(b14)
DSKSYNC  EQU CUSTOM+$07E       ; sync word searched for when WORDSYNC is active
ADKCON   EQU CUSTOM+$09E       ; audio/disk control (SETCLR|WORDSYNC...)
DSKBYTR  EQU CUSTOM+$01A       ; disk byte status (read)

; --- DMACON / ADKCON / INTREQ bits (dmabits.i, adkbits.i, intbits.i) ---
DMAF_DISK     EQU $0010        ; DMACON: disk DMA channel (DSKEN)
DMAF_MASTER   EQU $0200        ; DMA master
DMAF_SETCLR   EQU $8000
ADKF_SETCLR   EQU $8000
ADKF_WORDSYNC EQU $0400        ; enables the search for the DSKSYNC word by the read DMA
ADKF_FAST     EQU $0100        ; disk rate: 1 = 2 us/bit (standard DD); 0 = 4 us/bit -> wrong rhythm = garbage
ADKF_MFMPREC  EQU $1000        ; MFM precompensation (default read mode of the official KS1.3 = $9100)
INTF_DSKBLK   EQU $0002        ; INTREQ/INTREQR: end of disk block DMA (level 1)

; --- CIA-B PRB (drive control, $BFD100) — all lines are ACTIVE LOW (0 = asserted) ---
CIAB_PRB      EQU CIAB_HW+$0100
CIAB_DDRB     EQU CIAB_HW+$0300
CIAF_DSKMOTOR EQU $80          ; motor (0 = on)
CIAF_DSKSEL0  EQU $08          ; select DF0 (0 = selected)
CIAF_DSKSIDE  EQU $04          ; side
CIAF_DSKDIREC EQU $02          ; seek direction
CIAF_DSKSTEP  EQU $01          ; step pulse
; precomputed PRB values (minimal B2): all high except motor / motor+select
PRB_MOTOR_ON   EQU $7F         ; motor=0 (on), SEL/side/dir/step=1 (deselected) — sets the motor intention
PRB_OFF        EQU $FF         ; all high: motor off + deselected

; --- CIA-A PRA (drive status, $BFE001) — ACTIVE LOW ---
CIAA_PRA_HW    EQU CIAA_HW     ; = $BFE001
DSKB_RDY       EQU 5           ; DSKRDY (0 = ready)
DSKB_TRACK0    EQU 4           ; DSKTRACK0 (0 = head on track 0)
DSKB_CHANGE    EQU 2           ; /CHNG (0 = disk removed/changed since the last step)

; --- raw track read ---
TD_RAWWORDS  EQU $1900         ; words read = 6400 (12800 bytes, > one DD track); fits in a 16-bit dbra counter
TD_RAWBYTES  EQU TD_RAWWORDS*2
TD_SECBODY   EQU 1080          ; MFM bytes of a sector after its syncs: header 56 + data 1024
TD_ALLSECT   EQU $7FF          ; mask of the 11 sectors of a track
TD_FILLTRIES EQU 4             ; reads of an incomplete track before returning an error
TD_SYNC      EQU $4489         ; standard Amiga MFM sync word (impossible in normal MFM -> 0 false positives)

; TD_NO_DMA=1 (RED B2): the read does NOT arm the disk DMA (neither DMACON DSKEN nor DSKLEN start) -> the MEMF_CLEAR
; buffer stays at 0 -> no $4489 word -> "M6U TRACKDISK READ OK" absent. Isolates the DMA arming. Default 0.
TD_NO_DMA EQU 0

; --- MFM decoding (B3) ---
MFM_MASK      EQU $55555555   ; mask of the DATA bits (the MFM clock bits are in $AAAAAAAA)
MFM_SECTSZ    EQU 512         ; decoded data bytes per sector
MFM_NSECT     EQU 11          ; sectors per track (DD)
MFM_SECBUF    EQU MFM_SECTSZ*MFM_NSECT   ; 5632: buffer of the decoded sectors (indexed by logical number) = bytes/track
; --- DD geometry (M6z: multi-track CMD_READ) ---
TD_NTRACKS    EQU 160                    ; 80 cylinders x 2 sides (tracks 0..159)
TD_DISKBYTES  EQU TD_NTRACKS*MFM_SECBUF  ; 901120: total size of the DD disk (CMD_READ bound guard)
; offsets within an MFM sector from info_odd (public Amiga/ADF-FAQ format; locked by Python round-trip):
;   +0 info(odd,even,2 longs) +8 label(4 odd+4 even,8 longs) +40 hdrchk(odd,even) +48 datachk(odd,even)
;   +56 data_odd(128 longs=512b) +568 data_even(128 longs=512b); end of the sector at +1080
; MFM_BAD_DECODE=1 (RED B3): skips the <<1 of the DATA combine -> wrong decoded data -> sector 0 != "DOS\0"
; -> "M6V TRACKDISK DECODE OK" absent (the checksums, computed on the RAW MFM, still pass -> specifically
; isolates the correctness of the data decoding). Default 0.
MFM_BAD_DECODE EQU 0

; --- CMD_READ (B4): device BeginIO ---
CMD_READ      EQU 2            ; standard read command (io.i: INVALID=0, RESET=1, READ=2)
IO_ACTUAL     EQU 32           ; IOStdReq: bytes actually transferred
IO_LENGTH     EQU 36           ; bytes requested
IO_DATA       EQU 40           ; APTR destination buffer
IO_OFFSET     EQU 44           ; byte offset on the disk (logical sector * 512)
TDERR_NotSpec EQU 20           ; generic trackdisk error (trackdisk.i: TDERR_NotSpecified)
TDERR_WriteProt EQU 28         ; write-protected floppy
CMD_RESET     EQU 1
CMD_WRITE     EQU 3
CMD_UPDATE    EQU 4
CMD_CLEAR     EQU 5
CMD_STOP      EQU 6
CMD_START     EQU 7
CMD_FLUSH     EQU 8
TD_MOTOR      EQU 9
TD_SEEK       EQU 10
TD_FORMAT     EQU 11
TD_REMOVE     EQU 12
TD_CHANGENUM  EQU 13
TD_CHANGESTATE EQU 14
TD_PROTSTATUS EQU 15
TD_GETNUMTRACKS EQU 19
TD_ADDCHANGEINT EQU 20
TD_REMCHANGEINT EQU 21
DSKB_PROT     EQU 3            ; CIA-A PRA: /WPRO (0 = protected floppy)
ADKF_PRECOMP140 EQU $2000      ; 140 ns precompensation (tracks >= TD_PCTRACK)
TD_PCTRACK    EQU 81             ; first track (cylinder*2 + side) written with precompensation (spec trackdisk-write-v34)
; writing a track (spec trackdisk-write-v34 §2): 1660-byte guard at the head, 11 sectors of 1088 MFM bytes
; (preamble, sync, header, label, sums, data), tail word: 6815 words, ~218 ms. The track clearly exceeds one
; revolution: the end overlaps the guard, never a sector, even on a slow drive (~+4 %); nothing left of the old track.
TD_WRGAP      EQU 1660
TD_SECRAW     EQU 1088
TD_WRTAIL     EQU $AAA8          ; tail word after the last sector
TD_WRBYTES    EQU TD_WRGAP+MFM_NSECT*TD_SECRAW+2
TD_WRWORDS    EQU TD_WRBYTES/2
; TD_READ_NOCMD=1 (RED B4): BeginIO does NOT recognise CMD_READ (falls back to IOERR_NOCMD) -> io_Data stays at 0 ->
; sector read != "DOS\0" -> "M6W TRACKDISK CMD_READ OK" absent. Isolates the command handler. Default 0.
TD_READ_NOCMD EQU 0

; SEEK_NOSTEP=1 (RED B2b): td_read_track skips the step-in -> the head stays at track 0 -> reading track 2 actually
; returns track 0 -> the decoded track number != 2 -> "M6X TRACKDISK SEEK OK" absent. Isolates the seek. Default 0.
SEEK_NOSTEP EQU 0

; TD_NO_CYLTRACK=1 (RED cylinder-tracking): forces recalibration (step OUT until DSKTRACK0) on EVERY read
; instead of stepping the delta from TDU_CYL -> SLOW reads (old C behaviour). Correct but slow:
; under the scheduler, the full floppy boot no longer fits in WAIT=90 -> "D3B HANDLER OK" absent at that WAIT.
; Isolates the speed GAIN of cylinder-tracking (discriminant = D3B present at tight WAIT). Default 0.
TD_NO_CYLTRACK EQU 0

; TD_NOSEEK=1 (RED M6z): BeginIO CMD_READ ignores the TRACK component of the offset and ALWAYS reads track 0 (the
; sector-in-track and byte-in-track remain correct -> the read succeeds, no out-of-bounds). A read
; of the root block (block 880 = track 80) then returns track 0 (bootblock) -> "DOS\0" != T_SHORT; a spanning
; read returns sectors of track 0 -> wrong markers -> "M6Z ... OK" absent. Isolates the offset->track
; mapping WITHOUT crash (RED M6D_BAD_BPTR discipline: the read succeeds, the comparison fails). Default 0.
TD_NOSEEK EQU 0
