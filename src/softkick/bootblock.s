; src/softkick/bootblock.s - boot code of the soft-kick disk (src/softkick/mkadf.py puts it at +12 of the bootblock).
; Run by the strap of the Kickstart already in the machine: loads the KickSlopStart image (make kick-ram, linked
; at $C00000) from blocks 2..513 and starts it. First choice: Zorro II fast RAM, the highest free 64 KB-aligned
; block of 256 KB in $200000-$9FFFFF; the host's boards are then recorded in low chip RAM for the image's relay
; (src/exec/relay.i), which configures them again after a reset before entering the image. Otherwise, with slow RAM,
; the image goes to $C00000 as linked. Otherwise it goes into chip RAM above 512 KB, as high as a free 64 KB-aligned
; block allows (a 2.x/3.x Kickstart may keep its supervisor stack at the very top). Away from $C00000 the relocation
; table of blocks 514.. (src/softkick/mkreloc.py) moves its addresses. The image re-arms ColdCapture at each boot,
; so a reset comes back to it; switching the machine off returns to the Kickstart in ROM.
; Entry (bootblock convention, RKRM Devices): A1 = trackdisk IOStdReq, A6 = SysBase. The block runs at any
; address, possibly inside slow RAM: everything is PC-relative, and the final copy to slow RAM runs from a copy of
; go placed after the image and the board record in the chip buffer. When something is missing (memory, read error, bad image) it boots the
; disk normally: D0 = 0, A0 = dos.library init.

                include "relay.i"

IMG_BASE    EQU $C00000          ; link address of the image; slow RAM (A501 trapdoor)
IMG_SIZE    EQU $40000
IMG_OFFSET  EQU 2*512            ; blocks 2..513
REL_OFFSET  EQU IMG_OFFSET+IMG_SIZE ; blocks 514..521: relocation table (src/softkick/mkadf.py, RELOC_BLOCKS)
REL_SIZE    EQU 8*512
CSUM_OFF    EQU IMG_SIZE-$18     ; Kickstart checksum longword of the footer
COLD_OFF    EQU $D2              ; the image's reset PC, from its start
CHIP_MIN    EQU $80000           ; the image's coldstart uses the first 512 KB of chip RAM as its own
STEP        EQU $10000           ; candidate addresses are 64 KB aligned
CHUNK       EQU $10000           ; placed images go through a chip buffer (1.x trackdisk reads into chip only)
MEMF_CHIP   EQU 2
CMD_READ    EQU 2
TD_MOTOR    EQU 9
IO_COMMAND  EQU 28
IO_ERROR    EQU 31
IO_LENGTH   EQU 36
IO_DATA     EQU 40
IO_OFFSET   EQU 44
RT_INIT     EQU 22
LIB_VERSION EQU 20
EB_COLDCAPTURE EQU $2A
EB_MAXLOCMEM   EQU $3E
EB_ATTNFLAGS   EQU $128
AFB_68040      EQU 3
CD_FLAGS       EQU 14            ; struct ConfigDev (NDK libraries/configvars.h)
CD_ROM         EQU 16
CD_BOARDADDR   EQU 32
ERT_TYPEMASK   EQU $C0
ERT_ZORROII    EQU $C0
LVO_FindConfigDev EQU -72        ; expansion.library
LVO_Supervisor   EQU -30
LVO_FindResident EQU -96
LVO_SetSR        EQU -144
LVO_AllocMem     EQU -198
LVO_AllocAbs     EQU -204
LVO_FreeMem      EQU -210
LVO_CloseLibrary EQU -414
LVO_DoIO         EQU -456
LVO_TypeOfMem    EQU -534
LVO_OpenLibrary  EQU -552
LVO_CopyMem      EQU -624
LVO_CacheClearU  EQU -636        ; V36+
INTENA      EQU $DFF09A
INTREQ      EQU $DFF09C
DMACON      EQU $DFF096
BUF_SIZE    EQU IMG_SIZE+RL_HDRSIZE+(go_end-go)
KSS_RESIDENT EQU $4B53534B       ; "KSSK": the image already runs (src/exec/strap.s: no alert for it)

boot:
        movem.l d2-d5/a2-a5,-(sp)
        move.l  a1,a4                ; a4 = IOStdReq
        move.l  EB_COLDCAPTURE(a6),d0 ; KickSlopStart already runs (its ColdCapture is the reset PC of an image, or
        cmp.l   #RELAY_LO+RL_CODE,d0 ; the relay of an image in fast RAM): fail with KSS_RESIDENT, which its strap
        bne.s   .notrelay            ; takes for "not bootable" without the boot-error alert, so that it shows the
        cmp.l   #RL_MAGIC_V,RELAY_LO+RL_MAGIC ; insert-disk screen
        beq.s   .resident
.notrelay:
        cmp.l   #$1000,d0
        blo.s   .load
        btst    #0,d0
        bne.s   .load
        move.l  d0,a0
        lea     -COLD_OFF(a0),a0
        cmp.w   #$1111,(a0)
        bne.s   .load
        cmp.l   4(a0),d0
        bne.s   .load
.resident:
        move.l  #KSS_RESIDENT,d0
        bra     .ret
.load:
        move.l  #RL_ZEND-IMG_SIZE,d3
        move.l  #RL_ZBASE,d5
        bsr     place                ; Zorro II fast RAM
        lea     IMG_BASE+IMG_SIZE/2,a1 ; slow RAM must cover the image (the MemHeader at $C00000 is not
        jsr     LVO_TypeOfMem(a6)    ; inside its own [mh_Lower, mh_Upper) range)
        tst.l   d0
        beq.s   .chip
        lea     IMG_BASE+IMG_SIZE-4,a1
        jsr     LVO_TypeOfMem(a6)
        tst.l   d0
        beq.s   .chip
        move.l  #BUF_SIZE,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_AllocMem(a6)
        tst.l   d0
        beq.s   .normal
        move.l  d0,a3                ; a3 = buffer
        move.l  a3,a0
        move.l  #IMG_SIZE,d0
        move.l  #IMG_OFFSET,d1
        bsr     read
        bne.s   .free
        bsr     check
        bne.s   .free
        move.l  a3,a2                ; buffer: image, board record, copy of go
        add.l   #IMG_SIZE,a2
        move.l  #IMG_BASE,d3
        bsr     record
        lea     go(pc),a0
        lea     RL_HDRSIZE(a2),a1
        move.l  a1,a5
        moveq   #(go_end-go)/2-1,d0
.cp:
        move.w  (a0)+,(a1)+
        dbra    d0,.cp
        bra     start
.free:
        move.l  a3,a1
        move.l  #BUF_SIZE,d0
        jsr     LVO_FreeMem(a6)
        bra.s   .normal
.chip:
        move.l  EB_MAXLOCMEM(a6),d3  ; from the top of chip RAM down
        sub.l   #IMG_SIZE,d3
        and.l   #-STEP,d3
        move.l  #CHIP_MIN,d5
        bsr.s   place
.normal:
        lea     dos_name(pc),a1
        jsr     LVO_FindResident(a6)
        tst.l   d0
        beq.s   .fail
        move.l  d0,a0
        move.l  RT_INIT(a0),a0
        moveq   #0,d0
        bra.s   .ret
.fail:
        moveq   #-1,d0
.ret:
        movem.l (sp)+,d2-d5/a2-a5
        rts

; place(d3 = highest candidate address, d5 = lowest, both 64 KB aligned): AllocAbs of 256 KB at the first candidate
; that is free, from the top down; the image read there through a chip buffer, checked as linked, relocated; the
; host's boards recorded (record), which a placement in Zorro II space cannot do without. Does not return when all
; went well (go); otherwise returns with everything freed. a4 = IOStdReq, a6 = SysBase.
; Registers: d2 = read offset, d3 = image, d4 = relay area taken (0: no), a2 = buffer, a3 = image.
place:
        cmp.l   d5,d3
        blo.s   .p_ret
.p_try:
        move.l  #IMG_SIZE,d0
        move.l  d3,a1
        jsr     LVO_AllocAbs(a6)
        tst.l   d0
        bne.s   .p_got
        sub.l   #STEP,d3
        cmp.l   d5,d3
        bhs.s   .p_try
.p_ret:
        rts
.p_got:
        move.l  d3,a3
        move.l  #RELAY_HI-RELAY_LO,d0 ; the relay area taken first when free: the buffer then cannot lie there
        lea     RELAY_LO,a1
        jsr     LVO_AllocAbs(a6)
        move.l  d0,d4
        move.l  #CHUNK,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_AllocMem(a6)
        tst.l   d0
        beq.w   .p_img
        move.l  d0,a2
        moveq   #0,d2
.p_rd:
        move.l  a2,a0
        move.l  #CHUNK,d0
        move.l  #IMG_OFFSET,d1
        add.l   d2,d1
        bsr     rdon
        bne.s   .p_motor
        move.l  a2,a0
        move.l  a3,a1
        add.l   d2,a1
        move.l  #CHUNK,d0
        jsr     LVO_CopyMem(a6)
        add.l   #CHUNK,d2
        cmp.l   #IMG_SIZE,d2
        blo.s   .p_rd
        move.l  a2,a0
        move.l  #REL_SIZE,d0
        move.l  #REL_OFFSET,d1
        bsr     read
        bne.s   .p_free
        bsr     check
        bne.s   .p_free
        bsr     reloc
        bne.s   .p_free
        bsr     record
        beq.s   .p_go
        cmp.l   #RL_ZBASE,d3         ; Zorro II space: every board must be in the record, for the relay
        bhs.s   .p_free
.p_go:
        lea     go(pc),a5
        bra     start
.p_motor:
        bsr     motoff
.p_free:
        move.l  a2,a1
        move.l  #CHUNK,d0
        jsr     LVO_FreeMem(a6)
.p_img:
        tst.l   d4
        beq.s   .p_nors
        move.l  d4,a1
        move.l  #RELAY_HI-RELAY_LO,d0
        jsr     LVO_FreeMem(a6)
.p_nors:
        move.l  a3,a1
        move.l  #IMG_SIZE,d0
        jmp     LVO_FreeMem(a6)

; start: runs a5 (go, in place or copied) in supervisor mode, with the host left behind; does not return.
; d4 = the host's CPU flags, for go. A 2.x/3.x Kickstart may run with caches on: CacheClearU first.
start:
        move.w  EB_ATTNFLAGS(a6),d4
        cmp.w   #36,LIB_VERSION(a6)
        blo.s   .nocache
        jsr     LVO_CacheClearU(a6)
.nocache:
        moveq   #0,d0                ; SetSR(0,0) = current SR: the strap may already run in supervisor mode
        moveq   #0,d1
        jsr     LVO_SetSR(a6)
        btst    #13,d0
        bne.s   .super
        jsr     LVO_Supervisor(a6)
.super:
        jmp     (a5)

; record(a2 = buffer, d3 = image): the host's Zorro II boards (expansion.library FindConfigDev, chain order, at most
; RL_MAXENT) at the start of the buffer, for the relay and the image's expansion.library, which no longer finds the
; boards the host configured. Other boards are left out. -> d5 = 0 and Z set: all boards recorded; d5 = 1: recorded
; without some non-Zorro II board; d5 = -1: no record (its magic stays 0), also when this boot code lies in the relay
; area, which go overwrites. Clobbers d0/d1/a0/a1/a5.
record:
        move.l  a3,-(sp)
        move.l  a2,a0
        moveq   #RL_HDRSIZE/4-1,d0
.r_clr:
        clr.l   (a0)+
        dbra    d0,.r_clr
        moveq   #-1,d5
        lea     boot(pc),a0
        cmp.l   #RELAY_HI,a0
        bhs.s   .r_out
        lea     boot_end(pc),a0
        cmp.l   #RELAY_LO,a0
        bhi.s   .r_ret
.r_out:
        move.l  d3,RL_IMAGE(a2)
        lea     exp_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OpenLibrary(a6)
        move.l  d0,a5
        tst.l   d0
        beq.s   .r_ret
        lea     RL_ENTRIES(a2),a3
        sub.l   a0,a0
.r_cd:
        moveq   #-1,d0
        moveq   #-1,d1
        exg     a5,a6
        jsr     LVO_FindConfigDev(a6)
        exg     a5,a6
        move.l  d0,a0
        tst.l   d0
        beq.s   .r_done
        move.b  CD_ROM(a0),d1
        and.b   #ERT_TYPEMASK,d1
        cmp.b   #ERT_ZORROII,d1
        beq.s   .r_z2
        moveq   #1,d5
        bra.s   .r_cd
.r_z2:
        cmp.w   #RL_MAXENT,RL_COUNT(a2)
        bhs.s   .r_close
        lea     CD_ROM(a0),a1
        move.l  (a1)+,(a3)+
        move.l  (a1)+,(a3)+
        move.l  (a1)+,(a3)+
        move.l  (a1)+,(a3)+
        move.w  CD_BOARDADDR(a0),(a3)+ ; RE_SLOT: the high word of the board address
        moveq   #0,d1
        move.b  CD_FLAGS(a0),d1
        move.w  d1,(a3)+             ; RE_FLAGS
        addq.w  #1,RL_COUNT(a2)
        bra.s   .r_cd
.r_done:
        move.l  #RL_MAGIC_V,RL_MAGIC(a2)
        tst.l   d5
        bpl.s   .r_close
        moveq   #0,d5
.r_close:
        move.l  a5,a1
        jsr     LVO_CloseLibrary(a6)
.r_ret:
        tst.l   d5
        move.l  (sp)+,a3             ; keeps Z
        rts

; read(a0 = buffer, d0 = length, d1 = disk offset), then the motor off -> Z set when the read succeeded.
; rdon: the same read with the motor left on. a4 = IOStdReq. Clobbers d0/d1/a0/a1.
read:
        bsr.s   rdon
        sne     -(sp)
        bsr.s   motoff
        tst.b   (sp)+
        rts
motoff:
        move.l  a4,a1
        move.w  #TD_MOTOR,IO_COMMAND(a1)
        clr.l   IO_LENGTH(a1)
        jmp     LVO_DoIO(a6)
rdon:
        move.l  a4,a1
        move.w  #CMD_READ,IO_COMMAND(a1)
        move.l  d0,IO_LENGTH(a1)
        move.l  a0,IO_DATA(a1)
        move.l  d1,IO_OFFSET(a1)
        jsr     LVO_DoIO(a6)
        tst.b   IO_ERROR(a4)
        rts

; check(a3 = image as linked) -> Z set for a 256K Kickstart image whose reset PC lies inside it and whose Kickstart
; sum (end-around carry) is $FFFFFFFF. Clobbers d0/d1/a0.
check:
        cmp.w   #$1111,(a3)
        bne.s   .ck_ret
        move.l  4(a3),d0
        cmp.l   #IMG_BASE,d0
        blo.s   .ck_bad
        cmp.l   #IMG_BASE+IMG_SIZE,d0
        bhs.s   .ck_bad
        bsr.s   sum
        not.l   d1
.ck_ret:
        rts
.ck_bad:
        moveq   #-1,d0               ; Z clear
        rts

; sum(a3 = image) -> d1 = sum of its longwords with end-around carry. Clobbers d0/a0.
sum:
        move.l  a3,a0
        move.w  #IMG_SIZE/4-1,d0
        moveq   #0,d1
.sm:
        add.l   (a0)+,d1
        bcc.s   .sm_nc
        addq.l  #1,d1
.sm_nc:
        dbra    d0,.sm
        rts

; reloc(a2 = relocation table, a3 = image as linked, d3 = its load address) -> Z set when applied: each listed
; longword moved by load address - IMG_BASE, then the image's own Kickstart checksum. Clobbers d0-d2/a0/a1.
reloc:
        move.l  (a2),d0              ; d0 = count of relocated longwords
        cmp.l   #(REL_SIZE-4)/2,d0
        bhi.s   .rc_bad
        lea     4(a2),a0
        move.l  a3,a1
        move.l  d3,d1
        sub.l   #IMG_BASE,d1
        moveq   #0,d2
        bra.s   .rc_next
.rc:
        move.w  (a0)+,d2
        add.l   d2,a1
        add.l   d2,a1
        add.l   d1,(a1)
.rc_next:
        subq.l  #1,d0
        bcc.s   .rc
        move.l  a3,a1
        add.l   #CSUM_OFF,a1
        clr.l   (a1)
        bsr.s   sum
        not.l   d1
        move.l  d1,(a1)
        moveq   #0,d0
        rts
.rc_bad:
        moveq   #-1,d0
        rts

; Supervisor mode from here on: the running system is overwritten or left behind, so interrupts and DMA go off.
; go: a3 = the image, d4 = the host's AttnFlags, a2 = the board record. A 68040 under a 2.x/3.x host may run with
; copyback caches, the MMU and transparent translation on, which 1.3 code does not know: the caches are pushed and
; switched off, translation off. An image whose reset PC lies at IMG_BASE or above is still in the chip buffer of
; the slow-RAM placement (go then runs from its copy in that buffer, since slow RAM may hold the running system and
; this boot code): it is copied to IMG_BASE. A placed image already runs where it lies. A valid record goes to the
; relay area (which may have held the host's data) and ExecBase is dropped, so that the image starts cold.
go:
        move.w  #$2700,sr
        move.w  #$7FFF,INTENA
        move.w  #$7FFF,DMACON
        move.w  #$7FFF,INTREQ
        btst    #AFB_68040,d4
        beq.s   .g_cpu
        moveq   #0,d0
        dc.w    $F4F8                ; cpusha bc (68040)
        dc.w    $4E7B,$0002          ; movec d0,cacr
        dc.w    $4E7B,$0003          ; movec d0,tc
        dc.w    $4E7B,$0004          ; movec d0,itt0
        dc.w    $4E7B,$0005          ; movec d0,itt1
        dc.w    $4E7B,$0006          ; movec d0,dtt0
        dc.w    $4E7B,$0007          ; movec d0,dtt1
.g_cpu:
        lea     IMG_BASE,a1
        cmp.l   4(a3),a1
        bhi.s   .g_placed
        move.w  #IMG_SIZE/4-1,d0
.g_copy:
        move.l  (a3)+,(a1)+
        dbra    d0,.g_copy
        lea     IMG_BASE,a3
.g_placed:
        cmp.l   #RL_MAGIC_V,(a2)
        bne.s   .g_enter
        lea     RELAY_LO,a1
        move.l  a2,a0
        moveq   #RL_HDRSIZE/4-1,d0
.g_rec:
        move.l  (a0)+,(a1)+
        dbra    d0,.g_rec
        clr.l   ($4).w
.g_enter:
        move.l  4(a3),a0
        jmp     (a0)
go_end:

dos_name:
        dc.b    "dos.library",0
exp_name:
        dc.b    "expansion.library",0
        even
boot_end:
