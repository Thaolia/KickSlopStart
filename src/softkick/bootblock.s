; src/softkick/bootblock.s - boot code of the soft-kick disk (src/softkick/mkadf.py puts it at +12 of the bootblock).
; Run by the strap of the Kickstart already in the machine: loads the KickSlopStart image (make kick-ram, linked
; at $C00000) from blocks 2..513 into slow RAM and starts it. The image re-arms ColdCapture at each boot, so a
; reset comes back to it; switching the machine off returns to the Kickstart in ROM.
; Entry (bootblock convention, RKRM Devices): A1 = trackdisk IOStdReq, A6 = SysBase. The block runs at any
; address, possibly inside slow RAM: everything is PC-relative, and the final copy runs from a stub placed after
; the image in the chip buffer. When something is missing (slow RAM, memory, read error, bad image) it boots the
; disk normally: D0 = 0, A0 = dos.library init.

IMG_BASE    EQU $C00000          ; slow RAM (A501 trapdoor)
IMG_SIZE    EQU $40000
IMG_OFFSET  EQU 2*512            ; blocks 2..513
MEMF_CHIP   EQU 2
CMD_READ    EQU 2
TD_MOTOR    EQU 9
IO_COMMAND  EQU 28
IO_ERROR    EQU 31
IO_LENGTH   EQU 36
IO_DATA     EQU 40
IO_OFFSET   EQU 44
RT_INIT     EQU 22
EB_COLDCAPTURE EQU $2A
LVO_Supervisor   EQU -30
LVO_FindResident EQU -96
LVO_SetSR        EQU -144
LVO_AllocMem     EQU -198
LVO_FreeMem      EQU -210
LVO_DoIO         EQU -456
LVO_TypeOfMem    EQU -534
INTENA      EQU $DFF09A
INTREQ      EQU $DFF09C
DMACON      EQU $DFF096
BUF_SIZE    EQU IMG_SIZE+(stub_end-stub)

boot:
        movem.l d2/a2-a5,-(sp)
        move.l  a1,a4                ; a4 = IOStdReq
        move.l  EB_COLDCAPTURE(a6),d0 ; KickSlopStart already runs from slow RAM (its ColdCapture points into the
        cmp.l   #IMG_BASE,d0          ; image): fail, so that its strap shows the insert-disk screen and boots
        blo.s   .load                 ; the next disk inserted
        cmp.l   #IMG_BASE+IMG_SIZE,d0
        blo     .fail
.load:
        lea     IMG_BASE+IMG_SIZE/2,a1 ; slow RAM must cover the image (the MemHeader at $C00000 is not
        jsr     LVO_TypeOfMem(a6)    ; inside its own [mh_Lower, mh_Upper) range)
        tst.l   d0
        beq     .normal
        lea     IMG_BASE+IMG_SIZE-4,a1
        jsr     LVO_TypeOfMem(a6)
        tst.l   d0
        beq     .normal
        move.l  #BUF_SIZE,d0         ; chip: trackdisk of a 1.x Kickstart reads into chip only
        moveq   #MEMF_CHIP,d1
        jsr     LVO_AllocMem(a6)
        tst.l   d0
        beq     .normal
        move.l  d0,a3                ; a3 = buffer
        move.l  a4,a1
        move.w  #CMD_READ,IO_COMMAND(a1)
        move.l  #IMG_SIZE,IO_LENGTH(a1)
        move.l  a3,IO_DATA(a1)
        move.l  #IMG_OFFSET,IO_OFFSET(a1)
        jsr     LVO_DoIO(a6)
        move.b  IO_ERROR(a4),d2
        move.l  a4,a1
        move.w  #TD_MOTOR,IO_COMMAND(a1)
        clr.l   IO_LENGTH(a1)
        jsr     LVO_DoIO(a6)
        tst.b   d2
        bne.s   .free
        cmp.w   #$1111,(a3)          ; 256K Kickstart image...
        bne.s   .free
        move.l  4(a3),d0             ; ...whose reset PC lies inside it...
        cmp.l   #IMG_BASE,d0
        blo.s   .free
        cmp.l   #IMG_BASE+IMG_SIZE,d0
        bhs.s   .free
        move.l  a3,a0                ; ...and whose Kickstart sum (end-around carry) is $FFFFFFFF
        move.w  #IMG_SIZE/4-1,d0
        moveq   #0,d1
.sum:
        add.l   (a0)+,d1
        bcc.s   .nc
        addq.l  #1,d1
.nc:
        dbra    d0,.sum
        not.l   d1
        bne.s   .free
        lea     stub(pc),a0
        move.l  a3,a1
        add.l   #IMG_SIZE,a1
        move.l  a1,a5
        moveq   #(stub_end-stub)/2-1,d0
.cp:
        move.w  (a0)+,(a1)+
        dbra    d0,.cp
        moveq   #0,d0                ; SetSR(0,0) = current SR: the strap may already run in supervisor mode
        moveq   #0,d1
        jsr     LVO_SetSR(a6)
        btst    #13,d0
        bne.s   .super
        jsr     LVO_Supervisor(a6)   ; -> stub in supervisor mode, a3 = buffer; does not return
.super:
        jmp     (a5)
.free:
        move.l  a3,a1
        move.l  #BUF_SIZE,d0
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
        movem.l (sp)+,d2/a2-a5
        rts

; From here on the running system is overwritten (slow RAM may hold its structures): interrupts and DMA off.
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
