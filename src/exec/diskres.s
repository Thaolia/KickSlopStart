; src/exec/diskres.s — disk.resource: arbitration of the disk hardware between drivers (trackdisk, NDOS loaders).
;
; AllocUnit/FreeUnit reserve a unit (DRF_ALLOCn bits); GetUnit/GiveUnit lend the disk controller to ONE
; driver at a time (subsequent requesters wait in dr_Waiting and receive ReplyMsg of their DRU when the
; controller becomes free); GetUnitID returns the drive identifier read at startup. The resource owns the
; DSKBLK / DSKSYNC interrupts and the CIA-B FLG index and relays them to the interrupts of the current DRU.
; IMPLEMENTATION track ("clean"): AutoDocs disk.resource + resources/disk.h + HRM (drive identifier).
; NO ROM reading.

                include "exec.i"
                include "disk.i"

                xref    newlist          ; lists.s

; --- struct DiscResourceUnit (resources/disk.h) ---
DRU_DISCBLOCK   EQU MN_SIZE          ; struct Interrupt
DRU_DISCSYNC    EQU MN_SIZE+IS_SIZE
DRU_INDEX       EQU MN_SIZE+2*IS_SIZE
DRU_SIZE        EQU MN_SIZE+3*IS_SIZE
; --- struct DiscResource ---
DR_CURRENT      EQU LIB_SIZE         ; current owner DRU (or last owner)
DR_FLAGS        EQU LIB_SIZE+4
DR_SYSLIB       EQU LIB_SIZE+6
DR_CIARES       EQU LIB_SIZE+10
DR_UNITID       EQU LIB_SIZE+14      ; ULONG[4]
DR_WAITING      EQU LIB_SIZE+30      ; struct List
DR_DISCBLOCK    EQU DR_WAITING+14   ; sizeof(struct List)
DR_DISCSYNC     EQU DR_DISCBLOCK+IS_SIZE
DR_INDEX        EQU DR_DISCSYNC+IS_SIZE
DR_CURRTASK     EQU DR_INDEX+IS_SIZE
DR_NOBODY       EQU DR_CURRTASK+4    ; empty DRU: "last driver" as long as nobody has taken the controller
DR_SIZE         EQU DR_NOBODY+DRU_SIZE

DRB_ACTIVE      EQU 7
DR_NUNITS       EQU 4
INTB_DSKBLK     EQU 1
INTB_DSKSYNC    EQU 12
INTF_DSKSYNC    EQU $1000
CIAICRB_FLG     EQU 4                ; CIA-B FLG = drive index pulse
CIAF_DSKSEL1    EQU $10

        EVEN
diskres_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    diskres_romtag
        dc.l    diskres_end
        dc.b    RTF_COLDSTART,34,NT_RESOURCE,70
        dc.l    diskres_name
        dc.l    diskres_name
        dc.l    diskres_init
diskres_name:
        dc.b    "disk.resource",0
ciab_resname:
        dc.b    "ciab.resource",0
        EVEN
diskres_vectors:
        dc.l    dr_allocunit         ; -6  AllocUnit(unit d0)
        dc.l    dr_freeunit          ; -12 FreeUnit(unit d0)
        dc.l    dr_getunit           ; -18 GetUnit(dru a1)
        dc.l    dr_giveunit          ; -24 GiveUnit()
        dc.l    dr_getunitid         ; -30 GetUnitID(unit d0)
        dc.l    -1

diskres_init:
        movem.l d2-d3/a2-a3,-(sp)
        lea     diskres_vectors(pc),a0
        suba.l  a1,a1
        suba.l  a2,a2
        move.l  #DR_SIZE,d0
        moveq   #0,d1
        jsr     LVO_MAKELIBRARY(a6)
        tst.l   d0
        beq     .ri_ret
        move.l  d0,a3                ; a3 = DiscResource (MakeLibrary does not zero the positive area)
        lea     LIB_SIZE(a3),a0
        move.w  #(DR_SIZE-LIB_SIZE)/2-1,d1
.ri_clr:
        clr.w   (a0)+
        dbra    d1,.ri_clr
        lea     diskres_name(pc),a0
        move.l  a0,LN_NAME(a3)
        move.b  #NT_RESOURCE,LN_TYPE(a3)
        move.l  a6,DR_SYSLIB(a3)
        lea     DR_NOBODY(a3),a0
        move.l  a0,DR_CURRENT(a3)
        lea     DR_WAITING(a3),a1
        jsr     newlist
        ; identifiers: DF0 has no identification register (always DRT_AMIGA = 0)
        moveq   #1,d2
.ri_id:
        bsr     dr_readid
        move.l  d2,d1
        lsl.l   #2,d1
        move.l  d0,DR_UNITID(a3,d1.l)
        addq.l  #1,d2
        cmp.l   #DR_NUNITS,d2
        bcs.s   .ri_id
        ; exclusive DSKBLK / DSKSYNC vectors + CIA-B index (left disabled: AbleICR up to the driver)
        lea     DR_DISCBLOCK(a3),a1
        lea     dr_blkint(pc),a0
        moveq   #INTB_DSKBLK,d0
        bsr     dr_setint
        lea     DR_DISCSYNC(a3),a1
        lea     dr_syncint(pc),a0
        moveq   #INTB_DSKSYNC,d0
        bsr     dr_setint
        lea     ciab_resname(pc),a1
        jsr     LVO_OPENRESOURCE(a6)
        move.l  d0,DR_CIARES(a3)
        beq.s   .ri_add
        move.l  d0,a6
        lea     DR_INDEX(a3),a1
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        move.l  a3,IS_DATA(a1)
        lea     dr_idxint(pc),a0
        move.l  a0,IS_CODE(a1)
        moveq   #CIAICRB_FLG,d0
        jsr     -6(a6)               ; AddICRVector(FLG, &dr_Index)
        moveq   #1<<CIAICRB_FLG,d0
        jsr     -18(a6)              ; AbleICR(FLG): disable
        move.l  ($4).w,a6
.ri_add:
        move.l  a3,a1
        jsr     LVO_ADDRESOURCE(a6)
.ri_ret:
        moveq   #0,d0
        movem.l (sp)+,d2-d3/a2-a3
        rts

; dr_setint: a1 = struct Interrupt of the resource, a0 = code, d0 = interrupt number; a3 = resource.
dr_setint:
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        move.l  a3,IS_DATA(a1)
        move.l  a0,IS_CODE(a1)
        jmp     LVO_SETINTVECTOR(a6)

; dr_readid: d2 = unit 1..3 -> d0 = 32-bit identifier (HRM: motor on then off with the drive selected
; resets its identification register; then 32 successive selections, each one presents one bit on
; /RDY, most significant first, bit = 1 when /RDY is high). Absent -> $FFFFFFFF (DRT_EMPTY).
dr_readid:
        moveq   #CIAF_DSKSEL1>>1,d3
        lsl.b   d2,d3
        not.b   d3                   ; d3 = PRB with SELn low, the rest high (motor off)
        move.b  #$FF,CIAB_DDRB
        move.b  #PRB_OFF,CIAB_PRB
        move.b  #PRB_MOTOR_ON,CIAB_PRB
        move.b  d3,d0
        and.b   #PRB_MOTOR_ON,d0
        move.b  d0,CIAB_PRB          ; selection with motor low: latches motor on
        move.b  #PRB_OFF,CIAB_PRB
        move.b  d3,CIAB_PRB          ; selection with motor high: latches motor off
        move.b  #PRB_OFF,CIAB_PRB
        moveq   #0,d0
        moveq   #31,d1
.rd_bit:
        move.b  d3,CIAB_PRB
        add.l   d0,d0
        btst    #DSKB_RDY,CIAA_PRA_HW
        beq.s   .rd_lo
        addq.l  #1,d0
.rd_lo:
        move.b  #PRB_OFF,CIAB_PRB
        dbra    d1,.rd_bit
        rts

; AllocUnit(unit d0) -> d0 = 1 if the unit is granted, 0 if already taken or invalid. bset = indivisible
; read-modify-write on 68000 (no interrupt between the test and the set).
dr_allocunit:
        cmp.l   #DR_NUNITS,d0
        bcc.s   .au_no
        bset    d0,DR_FLAGS(a6)
        bne.s   .au_no
        moveq   #1,d0
        rts
.au_no:
        moveq   #0,d0
        rts

; FreeUnit(unit d0).
dr_freeunit:
        cmp.l   #DR_NUNITS,d0
        bcc.s   .fu_r
        bclr    d0,DR_FLAGS(a6)
.fu_r:
        rts

; GetUnitID(unit d0) -> d0 = drive type.
dr_getunitid:
        cmp.l   #DR_NUNITS,d0
        bcc.s   .gi_empty
        lsl.l   #2,d0
        move.l  DR_UNITID(a6,d0.l),d0
        rts
.gi_empty:
        moveq   #-1,d0
        rts

; GetUnit(dru a1) -> d0 = DRU of the last driver if the controller is free (it passes to a1), otherwise 0 and a1 is
; put on hold: GiveUnit will ReplyMsg it, the caller then retries GetUnit.
dr_getunit:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  DR_SYSLIB(a2),a6
        jsr     LVO_DISABLE(a6)
        bset    #DRB_ACTIVE,DR_FLAGS(a2)
        bne.s   .gu_busy
        move.l  DR_CURRENT(a2),d0
        move.l  a1,DR_CURRENT(a2)
        bra.s   .gu_out
.gu_busy:
        lea     DR_WAITING(a2),a0
        jsr     LVO_ADDTAIL(a6)
        moveq   #0,d0
.gu_out:
        move.l  d0,-(sp)
        jsr     LVO_ENABLE(a6)
        move.l  (sp)+,d0
        movem.l (sp)+,a2/a6
        rts

; GiveUnit(): frees the controller and wakes up the first waiting driver.
dr_giveunit:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  DR_SYSLIB(a2),a6
        jsr     LVO_DISABLE(a6)
        bclr    #DRB_ACTIVE,DR_FLAGS(a2)
        lea     DR_WAITING(a2),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .gv_out
        move.l  d0,a1
        jsr     LVO_REPLYMSG(a6)
.gv_out:
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,a2/a6
        rts

; Interrupt relay (a1 = resource): acknowledges then calls the corresponding interrupt of the current DRU,
; only if a driver holds the controller and has set an IS_CODE (called with a1 = IS_DATA).
dr_blkint:
        move.w  #INTF_DSKBLK,INTREQ
        moveq   #DRU_DISCBLOCK,d0
        bra.s   dr_relay
dr_syncint:
        move.w  #INTF_DSKSYNC,INTREQ
        moveq   #DRU_DISCSYNC,d0
        bra.s   dr_relay
dr_idxint:
        moveq   #DRU_INDEX,d0        ; the CIA dispatch has already acknowledged the ICR
dr_relay:
        btst    #DRB_ACTIVE,DR_FLAGS(a1)
        beq.s   .rl_r
        move.l  DR_CURRENT(a1),a0
        add.l   d0,a0
        move.l  IS_CODE(a0),d1
        beq.s   .rl_r
        move.l  d1,-(sp)
        move.l  IS_DATA(a0),a1
.rl_r:
        rts                          ; with IS_CODE pushed: jump to the handler, which returns to our caller
diskres_end:
