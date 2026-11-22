; src/exec/ide.s — scsi.device for the A600/A1200 built-in IDE port (Gayle), and the mounting of its RDB partitions.
;
; COLDSTART resident (not AUTOINIT): it adds the device only when a Gayle answers its ID sequence, so a machine
; without one (A500, A2000) is left exactly as before. Units 0 (master) and 1 (slave), found by a software reset and
; IDENTIFY DEVICE. Transfers are PIO, polled, in the caller's context, one request at a time on the controller
; (signal semaphore); the drive's interrupt stays off (nIEN). LBA28 when IDENTIFY offers it, CHS otherwise.
; io_Offset is a byte offset (32 bits: 4 GB at most), io_Length a multiple of 512.
; At init, each unit's Rigid Disk Block (blocks 0-15) is read and each partition (PART block) with a DOS\0-DOS\3
; dostype and without PBFF_NOMOUNT goes through MakeDosNode + AddDosNode (expansion.library): dos.library mounts the
; nodes of eb_MountList at its init, served by the ROM filesystem. Partitions are never booted from (an A600's boot
; partition usually holds a 2.x/3.x system): the boot stays on the floppy.
; IMPLEMENTATION track ("clean"): ATA/ATAPI public drafts (task file, IDENTIFY, READ/WRITE SECTORS); Gayle register
; map from Linux drivers/ata/pata_gayle.c and arch/m68k/amiga/platform.c (hardware facts); Gayle ID sequence from
; Amiberry src/gayle.cpp (hardware fact); NDK devices/hardblocks.h, devices/trackdisk.h, dos/filehandler.h,
; AutoDocs expansion.library. NO ROM reading. Plan: docs/ide-a600-plan.md.

                include "exec.i"
                include "disk.i"

                xref    ser_puts
                xref    ser_puthex

GAYLE_ID        EQU $DE1000          ; write: restart the ID sequence; read: next ID bit in bit 7
GAYLE_INTEN     EQU $DAA000          ; Gayle interrupt enable (bit 7 = IDE)
IDE_DATA        EQU $DA0000          ; 16-bit data register
IDE_ERROR       EQU $DA0006          ; task file register n at $DA0002 + 4n
IDE_NSECT       EQU $DA000A
IDE_LBAL        EQU $DA000E
IDE_LBAM        EQU $DA0012
IDE_LBAH        EQU $DA0016
IDE_DEVHEAD     EQU $DA001A
IDE_STATUS      EQU $DA001E          ; read: status; write: command
IDE_CTL         EQU $DA101A          ; write: device control; read: alternate status
ST_BSY          EQU 7
ST_DRDY         EQU 6
ST_DRQ          EQU 3
ST_ERR          EQU 0
CTL_NIEN        EQU $02
CTL_SRST        EQU $04
ATA_READ        EQU $20              ; READ SECTORS (with retries)
ATA_WRITE       EQU $30              ; WRITE SECTORS
ATA_IDENTIFY    EQU $EC
TMO_CMD         EQU 2000000          ; poll loops for a command (several seconds on a 68000)
TMO_RESET       EQU 8000000          ; poll loops after a reset (a drive spins up)
TMO_SLAVE       EQU 200000           ; an absent slave must not delay the boot

; unit area (io_Unit points to it; its first bytes stand for a struct Unit)
SU_OPENCNT      EQU 36               ; unit_OpenCnt (struct Unit: MsgPort 34 + flags + pad)
SU_PRESENT      EQU 38               ; byte: a drive answered IDENTIFY
SU_LBA          EQU 39               ; byte: LBA addressing
SU_NUM          EQU 40               ; byte: 0 master, 1 slave
SU_HEADS        EQU 42               ; word: CHS geometry from IDENTIFY
SU_SECS         EQU 44               ; word
SU_CYLS         EQU 46               ; word
SU_TOTAL        EQU 48               ; long: sectors
SU_SIZE         EQU 52
SD_SEM          EQU LIB_SIZE         ; struct SignalSemaphore (46)
SD_UNITS        EQU LIB_SIZE+48
SD_SIZE         EQU SD_UNITS+2*SU_SIZE

IOERR_BADLEN    EQU -4
IOERR_BADADDR   EQU -5
LVO_INITSEM     EQU -558
LVO_OBTAINSEM   EQU -564
LVO_RELEASESEM  EQU -570
LVO_EXP_MAKEDOSNODE EQU -144
LVO_EXP_ADDDOSNODE  EQU -150

ID_RDSK         EQU $5244534B
ID_PART         EQU $50415254
RDB_SCAN        EQU 16               ; the RDB lies in one of the first 16 blocks
RDB_PARTLIST    EQU 28
PB_NEXT         EQU 16
PB_FLAGS        EQU 20
PB_DRIVENAME    EQU 36               ; BSTR, 32 bytes
PB_ENV          EQU 128              ; DosEnvec, 20 longs at most
PBFF_NOMOUNT    EQU 2
MAX_PARTS       EQU 32               ; bound of the PART walk (a corrupt list must not loop)
DE_MAXLONGS     EQU 20
DE_DOSTYPE      EQU 16               ; index in the DosEnvec
IDE_MAXDOSTYPE  EQU 3                ; DOS\0-DOS\3: OFS, FFS and their international modes (ROM filesystem)

        EVEN
ide_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    ide_romtag
        dc.l    ide_end
        dc.b    RTF_COLDSTART,34,NT_DEVICE,10
        dc.l    ide_name
        dc.l    ide_idstr
        dc.l    ide_init
ide_name:
        dc.b    "scsi.device",0
ide_idstr:
        dc.b    "scsi.device 34.1 (Gayle IDE)",13,10,0
ide_expname:
        dc.b    "expansion.library",0
ide_msg_unit:
        dc.b    "IDE UNIT ",0
ide_msg_mount:
        dc.b    "IDE MOUNT ",0
ide_msg_nl:
        dc.b    13,10,0
        EVEN
ide_vectors:
        dc.l    ide_open             ; -6
        dc.l    ide_close            ; -12
        dc.l    ide_null             ; -18 Expunge
        dc.l    ide_null             ; -24
        dc.l    ide_beginio          ; -30
        dc.l    ide_null             ; -36 AbortIO: requests complete inside BeginIO
        dc.l    -1

; ide_init(d0 = 0, a0 = segList, a6 = SysBase) -> d0 = device | 0.
ide_init:
        movem.l d2-d7/a2-a6,-(sp)
        bsr     gayle_present
        beq     .in_none
        lea     ide_vectors(pc),a0
        suba.l  a1,a1
        suba.l  a2,a2
        move.l  #SD_SIZE,d0
        moveq   #0,d1
        jsr     LVO_MAKELIBRARY(a6)
        tst.l   d0
        beq     .in_none
        move.l  d0,a5                ; a5 = device base
        move.b  #NT_DEVICE,LN_TYPE(a5)
        lea     ide_name(pc),a0
        move.l  a0,LN_NAME(a5)
        move.w  #34,LIB_VERSION(a5)
        move.w  #1,LIB_REVISION(a5)
        lea     SD_SEM(a5),a0
        jsr     LVO_INITSEM(a6)
        move.b  #0,GAYLE_INTEN       ; the previous system may have left Gayle interrupts on: no server for them here
        bsr     ide_probe
        move.l  a5,a1
        jsr     LVO_ADDDEVICE(a6)
        lea     SD_UNITS(a5),a4
        bsr     ide_mount
        lea     SD_UNITS+SU_SIZE(a5),a4
        bsr     ide_mount
        move.l  a5,d0
        bra.s   .in_ret
.in_none:
        moveq   #0,d0
.in_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; gayle_present -> Z clear when the Gayle ID sequence reads $D0 or $D1 (A600 / A1200). Clobbers d0/d1.
gayle_present:
        move.b  #0,GAYLE_ID
        moveq   #7,d1
        moveq   #0,d0
.gp_bit:
        add.b   d0,d0
        btst    #7,GAYLE_ID
        beq.s   .gp_zero
        addq.b  #1,d0
.gp_zero:
        dbra    d1,.gp_bit
        and.b   #$FE,d0
        cmp.b   #$D0,d0
        seq     d0
        tst.b   d0
        rts

; ide_probe(a5 = base): software reset of the port, then IDENTIFY on each unit; fills the unit areas.
ide_probe:
        move.b  #CTL_SRST|CTL_NIEN,IDE_CTL
        moveq   #50,d0               ; > 5 us held
.pr_hold:
        dbra    d0,.pr_hold
        move.b  #CTL_NIEN,IDE_CTL
        move.w  #5000,d0             ; > 2 ms before the status means anything
.pr_wait:
        tst.b   IDE_CTL
        dbra    d0,.pr_wait
        move.l  #512,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .pr_ret              ; no units: the device has nothing to open
        move.l  d0,a3                ; a3 = IDENTIFY buffer
        lea     SD_UNITS(a5),a4
        clr.b   SU_NUM(a4)
        move.l  #TMO_RESET,d3
        bsr     ide_identify
        lea     SD_UNITS+SU_SIZE(a5),a4
        move.b  #1,SU_NUM(a4)
        move.l  #TMO_SLAVE,d3
        bsr     ide_identify
        move.l  a3,a1
        move.l  #512,d0
        jsr     LVO_FREEMEM(a6)
.pr_ret:
        rts

; ide_identify(a4 = unit area, a3 = 512-byte buffer, d3 = timeout loops): selects the unit, IDENTIFY DEVICE,
; geometry and size. Absent drive: SU_PRESENT stays 0. Clobbers d0-d4/a0-a2.
ide_identify:
        bsr     ide_selunit
        cmp.b   #$FF,IDE_CTL         ; floating bus: no drive on the port, do not wait for BSY
        beq     .id_ret
        bsr     ide_waitbsy
        bne     .id_ret
        move.b  IDE_STATUS,d0
        beq     .id_ret              ; no drive drives the bus
        cmp.b   #$FF,d0
        beq     .id_ret
        move.b  #ATA_IDENTIFY,IDE_STATUS
        bsr     ide_waitdrq
        bne     .id_ret
        move.l  a3,a2
        bsr     ide_rdsect
        lea     ide_idwords(pc),a0   ; IDENTIFY words are little-endian: the data port gives them byte-swapped
.id_swap:
        move.w  (a0)+,d0
        bmi.s   .id_swapped
        move.w  (a3,d0.w),d1
        ror.w   #8,d1
        move.w  d1,(a3,d0.w)
        bra.s   .id_swap
.id_swapped:
        move.w  98(a3),d0            ; word 49: capabilities, bit 9 = LBA
        btst    #9,d0
        sne     SU_LBA(a4)
        move.w  2(a3),SU_CYLS(a4)    ; words 1, 3, 6: default cylinders, heads, sectors per track
        move.w  6(a3),SU_HEADS(a4)
        move.w  12(a3),SU_SECS(a4)
        move.w  122(a3),d0           ; words 60-61: LBA sectors, low word first
        swap    d0
        move.w  120(a3),d0
        tst.b   SU_LBA(a4)
        bne.s   .id_size
        move.w  SU_CYLS(a4),d0
        mulu    SU_HEADS(a4),d0
        move.w  SU_SECS(a4),d1
        bsr     mul32_16
.id_size:
        move.l  d0,SU_TOTAL(a4)
        beq.s   .id_ret
        tst.w   SU_SECS(a4)
        beq.s   .id_ret
        tst.w   SU_HEADS(a4)
        beq.s   .id_ret
        st      SU_PRESENT(a4)
        lea     ide_msg_unit(pc),a0
        jsr     ser_puts
        moveq   #0,d0
        move.b  SU_NUM(a4),d0
        jsr     ser_puthex
        move.l  SU_TOTAL(a4),d0
        swap    d0
        jsr     ser_puthex
        swap    d0
        jsr     ser_puthex
        lea     ide_msg_nl(pc),a0
        jsr     ser_puts
.id_ret:
        rts

ide_idwords:                         ; byte offsets of the IDENTIFY words used (1, 3, 6, 49, 60, 61)
        dc.w    2,6,12,98,120,122,-1

; mul32_16(d0.l, d1.w) -> d0 = d0 * d1 (low 32 bits). Clobbers d1/d2.
mul32_16:
        move.l  d0,d2
        swap    d2
        mulu    d1,d2
        swap    d2
        clr.w   d2
        mulu    d1,d0
        add.l   d2,d0
        rts

; div32_16(d0.l / d1.w) -> d0 = quotient (32 bits), d1 = remainder (word). Clobbers d2.
div32_16:
        moveq   #0,d2
        swap    d0
        move.w  d0,d2
        divu    d1,d2                ; high half: quotient in d2.w, remainder in d2 high
        swap    d0
        move.w  d2,-(sp)             ; quotient high
        move.w  d0,d2                ; remainder:low half
        divu    d1,d2
        move.w  d2,d0                ; quotient low
        swap    d0
        move.w  (sp)+,d0
        swap    d0
        swap    d2
        move.w  d2,d1
        rts

; ide_selunit(a4 = unit area): writes the device/head register (LBA mode bit when the unit has it, head 0).
; Clobbers d0.
ide_selunit:
        moveq   #0,d0
        move.b  SU_NUM(a4),d0
        lsl.b   #4,d0
        or.b    #$A0,d0
        tst.b   SU_LBA(a4)
        beq.s   .su_w
        or.b    #$40,d0
.su_w:
        move.b  d0,IDE_DEVHEAD
        tst.b   IDE_CTL              ; 400 ns before the status is valid
        tst.b   IDE_CTL
        tst.b   IDE_CTL
        tst.b   IDE_CTL
        rts

; ide_waitbsy(d3 = timeout loops) -> Z set when BSY cleared in time. Clobbers d0/d4.
ide_waitbsy:
        move.l  d3,d4
.wb_lp:
        btst    #ST_BSY,IDE_CTL
        beq.s   .wb_ok
        subq.l  #1,d4
        bne.s   .wb_lp
        moveq   #-1,d0               ; Z clear
        rts
.wb_ok:
        moveq   #0,d0
        rts

; ide_waitdrq(d3 = timeout loops) -> Z set when the drive is ready to move data (BSY clear, DRQ set, no ERR).
; Clobbers d0/d4.
ide_waitdrq:
        move.l  d3,d4
.wd_lp:
        move.b  IDE_CTL,d0
        btst    #ST_BSY,d0
        bne.s   .wd_nx
        btst    #ST_ERR,d0
        bne.s   .wd_bad
        btst    #ST_DRQ,d0
        bne.s   .wd_ok
.wd_nx:
        subq.l  #1,d4
        bne.s   .wd_lp
.wd_bad:
        moveq   #-1,d0
        rts
.wd_ok:
        moveq   #0,d0
        rts

; ide_rdsect(a2 = buffer): 256 words from the data register; a2 advances by 512. Clobbers d0/a0.
ide_rdsect:
        lea     IDE_DATA,a0
        moveq   #31,d0
.rs_lp:
        move.w  (a0),(a2)+
        move.w  (a0),(a2)+
        move.w  (a0),(a2)+
        move.w  (a0),(a2)+
        move.w  (a0),(a2)+
        move.w  (a0),(a2)+
        move.w  (a0),(a2)+
        move.w  (a0),(a2)+
        dbra    d0,.rs_lp
        rts

; ide_wrsect(a2 = buffer): 256 words to the data register; a2 advances by 512. Clobbers d0/a0.
ide_wrsect:
        lea     IDE_DATA,a0
        moveq   #31,d0
.ws_lp:
        move.w  (a2)+,(a0)
        move.w  (a2)+,(a0)
        move.w  (a2)+,(a0)
        move.w  (a2)+,(a0)
        move.w  (a2)+,(a0)
        move.w  (a2)+,(a0)
        move.w  (a2)+,(a0)
        move.w  (a2)+,(a0)
        dbra    d0,.ws_lp
        rts

; ata_xfer(a4 = unit area, d5 = first sector, d6 = count 1..256, a2 = buffer, d7 = 0 read / 1 write)
; -> d0 = 0 | TDERR_NotSpec; a2 advances by what was moved. Clobbers d0-d4/a0.
ata_xfer:
        move.l  #TMO_CMD,d3
        bsr     ide_selunit
        bsr     ide_waitbsy
        bne     .ax_err
        move.b  d6,IDE_NSECT         ; 256 -> 0
        tst.b   SU_LBA(a4)
        beq.s   .ax_chs
        move.l  d5,d0
        move.b  d0,IDE_LBAL
        lsr.l   #8,d0
        move.b  d0,IDE_LBAM
        lsr.l   #8,d0
        move.b  d0,IDE_LBAH
        lsr.l   #8,d0
        and.b   #$0F,d0
        moveq   #0,d1
        move.b  SU_NUM(a4),d1
        lsl.b   #4,d1
        or.b    #$E0,d1
        or.b    d1,d0
        move.b  d0,IDE_DEVHEAD
        bra.s   .ax_cmd
.ax_chs:
        move.l  d5,d0                ; sector = block % spt + 1, track = block / spt
        move.w  SU_SECS(a4),d1
        bsr     div32_16
        addq.w  #1,d1
        move.b  d1,IDE_LBAL
        move.w  SU_HEADS(a4),d1      ; head = track % heads, cylinder = track / heads
        bsr     div32_16
        move.b  d0,IDE_LBAM
        lsr.w   #8,d0
        move.b  d0,IDE_LBAH
        moveq   #0,d0
        move.b  SU_NUM(a4),d0
        lsl.b   #4,d0
        or.b    #$A0,d0
        and.b   #$0F,d1
        or.b    d1,d0
        move.b  d0,IDE_DEVHEAD
.ax_cmd:
        moveq   #ATA_READ,d0
        tst.b   d7
        beq.s   .ax_go
        moveq   #ATA_WRITE,d0
.ax_go:
        move.b  d0,IDE_STATUS
        move.w  d6,d1
        subq.w  #1,d1
.ax_sect:
        move.w  d1,-(sp)
        bsr     ide_waitdrq
        bne.s   .ax_pop
        tst.b   d7
        bne.s   .ax_wr
        bsr     ide_rdsect
        bra.s   .ax_nx
.ax_wr:
        bsr     ide_wrsect
.ax_nx:
        move.w  (sp)+,d1
        dbra    d1,.ax_sect
        bsr     ide_waitbsy          ; a write ends when the drive has taken the last sector
        bne.s   .ax_err
        btst    #ST_ERR,IDE_STATUS   ; reading the status also clears the drive's interrupt
        bne.s   .ax_err
        moveq   #0,d0
        rts
.ax_pop:
        addq.l  #2,sp
.ax_err:
        moveq   #TDERR_NotSpec,d0
        rts

; Open(ioreq a1, unit d0, flags d1, a6 = device): units 0 and 1 with a drive.
ide_open:
        cmp.l   #1,d0
        bhi.s   .op_fail
        mulu    #SU_SIZE,d0
        lea     SD_UNITS(a6,d0.l),a0
        tst.b   SU_PRESENT(a0)
        beq.s   .op_fail
        move.l  a0,IO_UNIT(a1)
        addq.w  #1,SU_OPENCNT(a0)
        addq.w  #1,LIB_OPENCNT(a6)
        clr.b   IO_ERROR(a1)
        rts
.op_fail:
        move.b  #IOERR_OPENFAIL,IO_ERROR(a1)
        rts

ide_close:
        move.l  IO_UNIT(a1),a0
        subq.w  #1,SU_OPENCNT(a0)
        clr.l   IO_UNIT(a1)
        clr.l   IO_DEVICE(a1)
        subq.w  #1,LIB_OPENCNT(a6)
ide_null:
        moveq   #0,d0
        rts

; BeginIO(ioreq a1, a6 = device): every command completes here; ReplyMsg unless IOF_QUICK.
ide_beginio:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a1,a3                ; a3 = request
        move.b  #NT_MESSAGE,LN_TYPE(a3)
        clr.b   IO_ERROR(a3)
        clr.l   IO_ACTUAL(a3)
        move.w  IO_COMMAND(a3),d0
        moveq   #0,d7
        cmp.w   #CMD_READ,d0
        beq.s   .bi_rw
        moveq   #1,d7
        cmp.w   #CMD_WRITE,d0
        beq.s   .bi_rw
        cmp.w   #TD_FORMAT,d0
        beq.s   .bi_rw
        cmp.w   #TD_GETNUMTRACKS,d0
        beq.s   .bi_tracks
        cmp.w   #CMD_UPDATE,d0       ; nothing is cached: no-ops, as are the floppy-only commands
        beq.s   .bi_done
        cmp.w   #CMD_CLEAR,d0
        beq.s   .bi_done
        cmp.w   #TD_MOTOR,d0
        beq.s   .bi_done
        cmp.w   #TD_SEEK,d0
        beq.s   .bi_done
        cmp.w   #TD_REMOVE,d0
        beq.s   .bi_done
        cmp.w   #TD_CHANGENUM,d0     ; io_Actual 0: never changed, a disk present, not protected
        beq.s   .bi_done
        cmp.w   #TD_CHANGESTATE,d0
        beq.s   .bi_done
        cmp.w   #TD_PROTSTATUS,d0
        beq.s   .bi_done
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
        bra.s   .bi_done
.bi_tracks:
        move.l  IO_UNIT(a3),a4
        move.w  SU_CYLS(a4),d0
        mulu    SU_HEADS(a4),d0
        move.l  d0,IO_ACTUAL(a3)
        bra.s   .bi_done
.bi_rw:
        bsr.s   ide_rw
        move.b  d0,IO_ERROR(a3)
.bi_done:
        btst    #0,IO_FLAGS(a3)      ; IOF_QUICK
        bne.s   .bi_ret
        move.l  a6,-(sp)
        move.l  a3,a1
        move.l  ($4).w,a6
        jsr     LVO_REPLYMSG(a6)
        move.l  (sp)+,a6
.bi_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; ide_rw(a3 = request, a6 = device, d7 = 0 read / 1 write) -> d0 = io_Error; io_Actual = bytes moved.
; Runs of 256 sectors at most, under the controller semaphore. Clobbers d0-d7/a0-a2/a4.
ide_rw:
        move.l  IO_UNIT(a3),a4
        move.l  IO_LENGTH(a3),d6
        move.l  IO_OFFSET(a3),d5
        move.l  d6,d0
        or.l    d5,d0
        and.w   #511,d0
        bne.s   .rw_badlen
        lsr.l   #8,d5                ; first sector
        lsr.l   #1,d5
        lsr.l   #8,d6                ; sectors
        lsr.l   #1,d6
        move.l  d5,d0
        add.l   d6,d0
        bcs.s   .rw_badaddr
        cmp.l   SU_TOTAL(a4),d0
        bhi.s   .rw_badaddr
        move.l  IO_DATA(a3),a2
        move.l  a6,-(sp)
        lea     SD_SEM(a6),a0
        move.l  ($4).w,a6
        jsr     LVO_OBTAINSEM(a6)
        move.l  d6,-(sp)             ; sectors left
.rw_lp:
        move.l  (sp),d0
        beq.s   .rw_end
        move.l  #256,d6
        cmp.l   d6,d0
        bhs.s   .rw_run
        move.l  d0,d6
.rw_run:
        movem.l d5-d6,-(sp)
        bsr     ata_xfer
        movem.l (sp)+,d5-d6
        tst.l   d0
        bne.s   .rw_end
        add.l   d6,d5
        sub.l   d6,(sp)
        move.l  d6,d1
        lsl.l   #8,d1
        add.l   d1,d1
        add.l   d1,IO_ACTUAL(a3)
        bra.s   .rw_lp
.rw_end:
        addq.l  #4,sp
        move.l  d0,-(sp)
        move.l  4(sp),a6
        lea     SD_SEM(a6),a0
        move.l  ($4).w,a6
        jsr     LVO_RELEASESEM(a6)
        move.l  (sp)+,d0
        move.l  (sp)+,a6
        rts
.rw_badlen:
        moveq   #IOERR_BADLEN,d0
        rts
.rw_badaddr:
        moveq   #IOERR_BADADDR,d0
        rts

; ide_mount(a4 = unit area, a6 = SysBase): partitions of the unit's RDB -> MakeDosNode + AddDosNode. Runs at cold
; start (no other user of the controller), on the boot stack: its buffers are allocated. Clobbers d0-d7/a0-a3.
MT_BLOCK        EQU 0                ; 512-byte block buffer
MT_NAME         EQU 512              ; C name of the partition (32)
MT_PARM         EQU MT_NAME+32       ; parmPacket: dos name, exec name, unit, flags, environment
MT_CNT          EQU MT_PARM+16+4*DE_MAXLONGS ; PART blocks left to walk
MT_SIZE         EQU MT_CNT+4
ide_mount:
        tst.b   SU_PRESENT(a4)
        beq     .mt_ret
        move.l  a5,-(sp)
        move.l  #MT_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .mt_nomem
        move.l  d0,a5                ; a5 = frame
        lea     ide_expname(pc),a1
        moveq   #33,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .mt_free
        move.l  d0,a3                ; a3 = ExpansionBase
        moveq   #0,d5                ; d5 = block of the RDB
.mt_find:
        bsr     .mt_read
        bne.s   .mt_nx
        cmp.l   #ID_RDSK,MT_BLOCK(a5)
        bne.s   .mt_nx
        bsr     .mt_sum
        beq.s   .mt_found
.mt_nx:
        addq.l  #1,d5
        cmp.l   #RDB_SCAN,d5
        blo.s   .mt_find
        bra     .mt_done
.mt_found:
        move.l  RDB_PARTLIST(a5),d5
        move.l  #MAX_PARTS,MT_CNT(a5)
.mt_part:
        cmp.l   #-1,d5
        beq     .mt_done
        bsr     .mt_read
        bne     .mt_done
        cmp.l   #ID_PART,MT_BLOCK(a5)
        bne     .mt_done
        bsr     .mt_sum
        bne     .mt_done
        move.l  PB_NEXT(a5),-(sp)    ; next PART block, read before the buffer is reused
        bsr     .mt_one
        move.l  (sp)+,d5
        subq.l  #1,MT_CNT(a5)
        bne     .mt_part
.mt_done:
        move.l  a3,a1
        jsr     LVO_CLOSELIBRARY(a6)
.mt_free:
        move.l  a5,a1
        move.l  #MT_SIZE,d0
        jsr     LVO_FREEMEM(a6)
.mt_nomem:
        move.l  (sp)+,a5
.mt_ret:
        rts

; .mt_read(d5 = block) -> Z set when read into the frame's block buffer. Clobbers d0-d4/d6-d7/a0/a2.
.mt_read:
        lea     MT_BLOCK(a5),a2
        moveq   #1,d6
        moveq   #0,d7
        bsr     ata_xfer
        tst.l   d0
        rts

; .mt_sum -> Z set when the longs counted by the block's second long add up to 0 (at most 128).
.mt_sum:
        lea     MT_BLOCK(a5),a0
        move.l  4(a0),d1
        cmp.l   #128,d1
        bhi.s   .ms_bad
        subq.w  #1,d1
        bmi.s   .ms_bad
        moveq   #0,d0
.ms_lp:
        add.l   (a0)+,d0
        dbra    d1,.ms_lp
        tst.l   d0
        rts
.ms_bad:
        moveq   #-1,d0
        rts

; .mt_one: the PART block in the frame: a mountable DOS partition -> DeviceNode in eb_MountList.
.mt_one:
        lea     MT_BLOCK(a5),a1      ; a1 = PART block
        btst    #1,PB_FLAGS+3(a1)    ; PBFF_NOMOUNT
        bne     .mo_ret
        lea     PB_ENV(a1),a0
        move.l  (a0),d0              ; de_TableSize
        cmp.l   #DE_DOSTYPE,d0
        blo.s   .mo_dos0             ; no dostype field: DOS\0
        cmp.l   #DE_MAXLONGS-1,d0
        bhi     .mo_ret
        move.l  DE_DOSTYPE*4(a0),d1
        move.l  d1,d3
        clr.b   d3
        cmp.l   #$444F5300,d3
        bne     .mo_ret
        cmp.b   #IDE_MAXDOSTYPE,d1
        bhi     .mo_ret
.mo_dos0:
        lea     MT_NAME(a5),a2       ; C name from the BSTR
        lea     PB_DRIVENAME(a1),a0
        moveq   #0,d1
        move.b  (a0)+,d1
        beq     .mo_ret
        cmp.w   #30,d1
        bhi     .mo_ret
        subq.w  #1,d1
.mo_name:
        move.b  (a0)+,(a2)+
        dbra    d1,.mo_name
        clr.b   (a2)
        lea     MT_PARM(a5),a2
        lea     MT_NAME(a5),a0
        move.l  a0,(a2)+
        lea     ide_name(pc),a0
        move.l  a0,(a2)+
        moveq   #0,d1
        move.b  SU_NUM(a4),d1
        move.l  d1,(a2)+
        clr.l   (a2)+
        lea     PB_ENV(a1),a0
        move.l  (a0),d1
.mo_env:
        move.l  (a0)+,(a2)+
        dbra    d1,.mo_env
        movem.l a1/a6,-(sp)
        lea     MT_PARM(a5),a0
        move.l  a3,a6
        jsr     LVO_EXP_MAKEDOSNODE(a6)
        movem.l (sp)+,a1/a6
        tst.l   d0
        beq.s   .mo_ret
        move.l  d0,a0
        moveq   #-128,d0             ; mounted only, never booted (user decision): the partition stays behind the
        moveq   #0,d1                ; DF0: BootNode (pri 5) even when marked bootable, so SYS: is always a floppy
        move.l  a6,-(sp)
        move.l  a3,a6
        jsr     LVO_EXP_ADDDOSNODE(a6)
        move.l  (sp)+,a6
        lea     ide_msg_mount(pc),a0
        jsr     ser_puts
        lea     MT_NAME(a5),a0
        jsr     ser_puts
        lea     ide_msg_nl(pc),a0
        jsr     ser_puts
.mo_ret:
        rts

ide_end:
