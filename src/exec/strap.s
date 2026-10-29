; src/exec/strap.s — strap (romboot): reads, validates and EXECUTES the bootblock of DF0: (milestone C "it boots!").
; strap_boot(a6=SysBase) -> d0 = 0 if NO bootable volume (the caller displays the insert-disk screen),
;                           d0 != 0 if the bootblock was executed successfully (a real boot would not return).
;
; Chain: FindName("trackdisk.device") -> CMD_READ(offset 0, len 1024 = sectors 0+1 = bootblock, IN track 0)
; via BeginIO -30 (pattern proven by M6w) -> validates magic "DOS" + additive checksum -> JSR to the boot code at +12.
;
; 1.3 bootability criterion (public, verified empirically on a formatted ADF): magic "DOS" AND one's-complement
; checksum (sum with END-AROUND carry of the 256 longs == $FFFFFFFF). A formatted, non-installed ADF has
; checksum=0 -> not bootable -> the insert-disk screen appears BECAUSE the bootblock of DF0: does not validate:
; this is the REAL 1.3 trigger (no longer the "always return 0" scaffolding of M6r).
;
; ACCEPTED clean-room deviations (milestone without dos):
;  - The real convention also returns A0 = handoff address (dos) that the strap would JMP to; here we only
;    return "booted" without following A0 (no dos.library yet — D/E/F).
;  - A real bootblock does not return (it takes over); our test bootblock returns (D0=0) + we FreeMem.
;  - Own internal boot mechanism (the real 1.3 does not expose `AddBootNode`, V36/2.0+); we reproduce the
;    observable BEHAVIOUR, not the ROM internals.
; IMPLEMENTATION track ("clean"): AutoDocs exec + RKRM Devices (boot process) + devices/bootblock.i (public).
; NO ROM reading.

                include "exec.i"

                xdef    strap_boot
                xdef    strap_romboot

; IO constants not present in exec.i (read-specific) — documented literals (strap does not include disk.i)
CMD_READ       EQU 2
IO_ACTUAL      EQU 32               ; bytes actually transferred
IO_LENGTH      EQU 36               ; bytes requested
IO_DATA        EQU 40               ; APTR destination buffer
IO_OFFSET      EQU 44               ; byte offset on the disk
TD_LVO_BEGINIO EQU -30              ; standard device BeginIO vector
BB_SIZE        EQU 1024             ; bootblock = 2 sectors of 512 bytes
BB_ENTRY       EQU 12               ; offset of the boot code in the bootblock (after magic/checksum/rootptr)
IOREQ_SIZE     EQU 48               ; IOStdReq

; STRAP_FAKE_BOOTDEV=1 (RED inherited from M6r): simulates a successful boot up front -> neither insert-disk nor screen.
; Default 0.
STRAP_FAKE_BOOTDEV EQU 0
; STRAP_BAD_CSUM=1 (RED C): INVERTS the checksum decision -> a VALID bootblock is rejected -> boot_c.adf
; is not booted -> "M6Y" + "CBOOT" absent, insert-disk instead. Isolates the VALIDATION (proves that the
; "accepts a good block" path is not empty). Default 0.
STRAP_BAD_CSUM EQU 0
; STRAP_NO_EXEC=1 (RED C): validates the bootblock but SKIPS the JSR to the boot code -> the "CBOOT" marker of
; the bootblock is absent, but the strap still returns "booted" (M6Y present). Isolates the EXECUTION. Default 0.
STRAP_NO_EXEC  EQU 0

strap_boot:
                ifne    STRAP_FAKE_BOOTDEV
        moveq   #1,d0                ; RED: pretends to have booted -> no insert-disk
        rts
                endc
        movem.l a2/a3,-(sp)          ; only returns d0; a2/a3 preserved (convention)
        lea     EB_DEVICELIST(a6),a0
        lea     strap_td_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .nb_nofree           ; no trackdisk.device -> not bootable
        move.l  d0,a2                ; a2 = trackdisk base
        move.l  #IOREQ_SIZE+BB_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .nb_nofree           ; no RAM -> not bootable
        move.l  d0,a3                ; a3 = ioreq; bootblock buffer = a3 + IOREQ_SIZE
        move.l  a2,IO_DEVICE(a3)
        move.w  #CMD_READ,IO_COMMAND(a3)
        move.l  #BB_SIZE,IO_LENGTH(a3)
        lea     IOREQ_SIZE(a3),a0
        move.l  a0,IO_DATA(a3)
        clr.l   IO_OFFSET(a3)        ; bootblock = sectors 0+1 (offset 0, in track 0)
        move.b  #IOF_QUICK,IO_FLAGS(a3)
        move.l  a6,-(sp)             ; BeginIO via -30 (a6 = trackdisk, a1 = ioreq)
        move.l  a2,a6
        move.l  a3,a1
        jsr     TD_LVO_BEGINIO(a6)
        move.l  (sp)+,a6             ; restore a6 = SysBase
        tst.b   IO_ERROR(a3)
        bne     .reject              ; read failed (no disk in DF0:) -> insert-disk
        cmp.l   #BB_SIZE,IO_ACTUAL(a3)
        bne     .reject
        ; --- validation: magic "DOS" + additive checksum ---
        lea     IOREQ_SIZE(a3),a2    ; a2 = bootblock (trackdisk base no longer needed)
        move.l  (a2),d0
        and.l   #$FFFFFF00,d0
        cmp.l   #$444F5300,d0        ; "DOS" (flag byte ignored)
        bne     .reject
        ; one's-complement checksum: sum with END-AROUND carry of the 256 longs == $FFFFFFFF (ADD, NOT XOR:
        ; the bootblock checksum is ADDITIVE, unlike the per-sector MFM checksums of td_decode_track)
        move.l  a2,a0
        moveq   #0,d0
        move.w  #256-1,d1
.cs:
        add.l   (a0)+,d0
        bcc.s   .cs_nc
        addq.l  #1,d0                ; end-around carry
.cs_nc:
        dbra    d1,.cs
        addq.l  #1,d0                ; $FFFFFFFF+1 -> 0 (Z) iff checksum valid
                ifeq    STRAP_BAD_CSUM
        bne     .reject              ; invalid checksum -> not bootable (disk present but not installed)
                endc
                ifne    STRAP_BAD_CSUM
        beq     .reject              ; RED STRAP_BAD_CSUM: rejects a VALID block -> isolates the validation
                endc
        ; --- valid bootblock -> execute the boot code at +BB_ENTRY ---
                ifeq    STRAP_NO_EXEC
        move.l  a3,-(sp)             ; protect the ioreq (any boot code may clobber a3)
        lea     BB_ENTRY(a2),a0
        move.l  a3,a1                ; A1 = reusable ioreq; A6 = SysBase (bootblock convention)
        jsr     (a0)                 ; D0 = bootblock return (0 = success); A0 (dos handoff) IGNORED in C
        move.l  (sp)+,a3
        move.l  ($4).w,a6            ; reload SysBase (the bootblock may have clobbered a6)
        tst.l   d0
        bne.s   .boot_failed         ; the boot code reported an error -> insert-disk
                endc                 ; RED STRAP_NO_EXEC: skips the JSR -> "CBOOT" absent, but "booted"
        bsr.s   .free
        moveq   #1,d0                ; booted -> the caller does NOT show the insert-disk
        bra.s   .ret
.boot_failed:
        bsr.s   .free
        moveq   #0,d0
        bra.s   .ret
.reject:
        bsr.s   .free                ; disk present but not bootable -> free then insert-disk
        moveq   #0,d0
        bra.s   .ret
.nb_nofree:
        moveq   #0,d0                ; nothing allocated -> nothing to free
.ret:
        movem.l (sp)+,a2/a3
        rts
.free:
        move.l  a3,a1
        move.l  #IOREQ_SIZE+BB_SIZE,d0
        jsr     LVO_FREEMEM(a6)      ; a6 = SysBase on all paths that arrive here
        rts

; strap_romboot(a6 = SysBase): DF0: is not bootable -> once only, RomBoot() of romboot.library (BootPoint of the
; boards, spec uae-hd-boot-v34 §3 item 3). A BootPoint that starts dos does not return. Preserves d2-d7/a2-a6.
strap_romboot:
        move.l  a6,-(sp)
        lea     strap_rb_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   .rb_ret
        move.l  d0,a6
        jsr     -30(a6)              ; RomBoot()
        move.l  a6,a1
        move.l  ($4).w,a6
        jsr     LVO_CLOSELIBRARY(a6)
.rb_ret:
        move.l  (sp)+,a6
        rts

strap_td_name:
        dc.b    "trackdisk.device",0
strap_rb_name:
        dc.b    "romboot.library",0
        even
