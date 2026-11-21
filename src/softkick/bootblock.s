; src/softkick/bootblock.s - boot code of the soft-kick disk (src/softkick/mkadf.py puts it at +12 of the bootblock).
; Run by the strap of the Kickstart already in the machine: loads the KickSlopStart image (make kick-ram, linked
; at $C00000) from blocks 2..513 and starts it. With slow RAM the image goes to $C00000 as linked. Without it, it
; goes into chip RAM above 512 KB, as high as a free 64 KB-aligned block allows (a 2.x/3.x Kickstart may keep its
; supervisor stack at the very top), and the relocation table of blocks 514.. (src/softkick/mkreloc.py) moves its
; addresses there. The image re-arms ColdCapture at each boot, so a reset comes back to it; switching the machine
; off returns to the Kickstart in ROM.
; Entry (bootblock convention, RKRM Devices): A1 = trackdisk IOStdReq, A6 = SysBase. The block runs at any
; address, possibly inside slow RAM: everything is PC-relative, and the final copy to slow RAM runs from a stub
; placed after the image in the chip buffer. When something is missing (memory, read error, bad image) it boots the
; disk normally: D0 = 0, A0 = dos.library init.

IMG_BASE    EQU $C00000          ; link address of the image; slow RAM (A501 trapdoor)
IMG_SIZE    EQU $40000
IMG_OFFSET  EQU 2*512            ; blocks 2..513
REL_OFFSET  EQU IMG_OFFSET+IMG_SIZE ; blocks 514..521: relocation table (src/softkick/mkadf.py, RELOC_BLOCKS)
REL_SIZE    EQU 8*512
CSUM_OFF    EQU IMG_SIZE-$18     ; Kickstart checksum longword of the footer
COLD_OFF    EQU $D2              ; the image's reset PC, from its start
CHIP_MIN    EQU $80000           ; the image's coldstart uses the first 512 KB of chip RAM as its own
CHIP_STEP   EQU $10000
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
LVO_Supervisor   EQU -30
LVO_FindResident EQU -96
LVO_SetSR        EQU -144
LVO_AllocMem     EQU -198
LVO_AllocAbs     EQU -204
LVO_FreeMem      EQU -210
LVO_DoIO         EQU -456
LVO_TypeOfMem    EQU -534
LVO_CacheClearU  EQU -636        ; V36+
INTENA      EQU $DFF09A
INTREQ      EQU $DFF09C
DMACON      EQU $DFF096
BUF_SIZE    EQU IMG_SIZE+(stub_end-stub)
KSS_RESIDENT EQU $4B53534B       ; "KSSK": the image already runs (src/exec/strap.s: no alert for it)

boot:
        movem.l d2-d4/a2-a5,-(sp)
        move.l  a1,a4                ; a4 = IOStdReq
        move.l  EB_COLDCAPTURE(a6),d0 ; KickSlopStart already runs (its ColdCapture is the reset PC of an image):
        cmp.l   #$1000,d0            ; fail with KSS_RESIDENT, which its strap takes for "not bootable" without the
        blo.s   .load                ; boot-error alert, so that it shows the insert-disk screen
        btst    #0,d0
        bne.s   .load
        move.l  d0,a0
        lea     -COLD_OFF(a0),a0
        cmp.w   #$1111,(a0)
        bne.s   .load
        cmp.l   4(a0),d0
        bne.s   .load
        move.l  #KSS_RESIDENT,d0
        bra     .ret
.load:
        lea     IMG_BASE+IMG_SIZE/2,a1 ; slow RAM must cover the image (the MemHeader at $C00000 is not
        jsr     LVO_TypeOfMem(a6)    ; inside its own [mh_Lower, mh_Upper) range)
        tst.l   d0
        beq     .chip
        lea     IMG_BASE+IMG_SIZE-4,a1
        jsr     LVO_TypeOfMem(a6)
        tst.l   d0
        beq     .chip
        move.l  #BUF_SIZE,d0         ; chip: trackdisk of a 1.x Kickstart reads into chip only
        moveq   #MEMF_CHIP,d1
        jsr     LVO_AllocMem(a6)
        tst.l   d0
        beq     .normal
        move.l  d0,a3                ; a3 = buffer
        move.l  a3,a0
        move.l  #IMG_SIZE,d0
        move.l  #IMG_OFFSET,d1
        bsr     read
        bne.s   .free
        bsr     check
        bne.s   .free
        lea     stub(pc),a0
        move.l  a3,a1
        add.l   #IMG_SIZE,a1
        move.l  a1,a5
        moveq   #(stub_end-stub)/2-1,d0
.cp:
        move.w  (a0)+,(a1)+
        dbra    d0,.cp
        bra     .start
.free:
        move.l  a3,a1
        move.l  #BUF_SIZE,d0
        jsr     LVO_FreeMem(a6)
        bra     .normal

.chip:
        move.l  EB_MAXLOCMEM(a6),d3  ; d3 = candidate address, from the top of chip RAM down
        sub.l   #IMG_SIZE,d3
        and.l   #-CHIP_STEP,d3
.try:
        cmp.l   #CHIP_MIN,d3
        blo     .normal
        move.l  #IMG_SIZE,d0
        move.l  d3,a1
        jsr     LVO_AllocAbs(a6)     ; d3 is 64 KB aligned: AllocAbs gives it back as is, or 0
        tst.l   d0
        bne.s   .got
        sub.l   #CHIP_STEP,d3
        bra.s   .try
.got:
        move.l  d3,a3                ; a3 = image in place
        move.l  #REL_SIZE,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_AllocMem(a6)
        tst.l   d0
        beq     .cfree
        move.l  d0,a2                ; a2 = relocation table
        move.l  a2,a0
        move.l  #REL_SIZE,d0
        move.l  #REL_OFFSET,d1
        bsr     read
        bne     .tfree
        move.l  a3,a0
        move.l  #IMG_SIZE,d0
        move.l  #IMG_OFFSET,d1
        bsr     read
        bne     .tfree
        bsr     check
        bne     .tfree
        move.l  (a2),d0              ; d0 = count of relocated longwords
        cmp.l   #(REL_SIZE-4)/2,d0
        bhi     .tfree
        lea     4(a2),a0
        move.l  a3,a1
        move.l  d3,d1
        sub.l   #IMG_BASE,d1         ; d1 = load address - link address
        moveq   #0,d2
        bra.s   .rl_next
.rl:
        move.w  (a0)+,d2
        add.l   d2,a1
        add.l   d2,a1
        add.l   d1,(a1)
.rl_next:
        subq.l  #1,d0
        bcc.s   .rl
        move.l  a3,a1                ; the relocated image gets its own Kickstart checksum
        add.l   #CSUM_OFF,a1
        clr.l   (a1)
        bsr     sum
        not.l   d1
        move.l  d1,(a1)
        move.l  a2,a1
        move.l  #REL_SIZE,d0
        jsr     LVO_FreeMem(a6)
        cmp.w   #36,LIB_VERSION(a6)  ; a 2.x/3.x Kickstart may run with the instruction cache on
        blo.s   .nocache
        jsr     LVO_CacheClearU(a6)
.nocache:
        lea     go(pc),a5
.start:
        moveq   #0,d0                ; SetSR(0,0) = current SR: the strap may already run in supervisor mode
        moveq   #0,d1
        jsr     LVO_SetSR(a6)
        btst    #13,d0
        bne.s   .super
        jsr     LVO_Supervisor(a6)   ; -> a5 in supervisor mode, a3 = image or buffer; does not return
.super:
        jmp     (a5)
.tfree:
        move.l  a2,a1
        move.l  #REL_SIZE,d0
        jsr     LVO_FreeMem(a6)
.cfree:
        move.l  a3,a1
        move.l  #IMG_SIZE,d0
        jsr     LVO_FreeMem(a6)
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
        movem.l (sp)+,d2-d4/a2-a5
        rts

; read(a0 = buffer, d0 = length, d1 = disk offset), then the motor off -> Z set when the read succeeded.
; a4 = IOStdReq. Clobbers d0/d1/a0/a1.
read:
        move.l  d2,-(sp)
        move.l  a4,a1
        move.w  #CMD_READ,IO_COMMAND(a1)
        move.l  d0,IO_LENGTH(a1)
        move.l  a0,IO_DATA(a1)
        move.l  d1,IO_OFFSET(a1)
        jsr     LVO_DoIO(a6)
        move.b  IO_ERROR(a4),d2
        move.l  a4,a1
        move.w  #TD_MOTOR,IO_COMMAND(a1)
        clr.l   IO_LENGTH(a1)
        jsr     LVO_DoIO(a6)
        tst.b   d2
        movem.l (sp)+,d2             ; keeps Z
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

; Supervisor mode from here on: the running system is overwritten or left behind, so interrupts and DMA go off.
; go: the image is in place (chip RAM), a3 = its start.
go:
        move.w  #$2700,sr
        move.w  #$7FFF,INTENA
        move.w  #$7FFF,DMACON
        move.w  #$7FFF,INTREQ
        move.l  4(a3),a0
        jmp     (a0)

; stub: copied after the image in the chip buffer (slow RAM may hold the running system's structures).
stub:
        move.w  #$2700,sr
        move.w  #$7FFF,INTENA
        move.w  #$7FFF,DMACON
        move.w  #$7FFF,INTREQ
        lea     IMG_BASE,a1
        move.w  #IMG_SIZE/4-1,d0
.copy:
        move.l  (a3)+,(a1)+
        dbra    d0,.copy
        move.l  IMG_BASE+4,a0
        jmp     (a0)
stub_end:

dos_name:
        dc.b    "dos.library",0
        even
