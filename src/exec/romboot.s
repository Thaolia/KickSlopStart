; src/exec/romboot.s — romboot.library 34 (spec docs/analysis/uae-hd-boot-v34.md §2): COLDSTART resident pri -40.
; At its init, for each autoconfig board to configure (CDF_CONFIGME) whose DiagArea was copied to RAM (valid
; Diag, CONFIGTIME moment), the first ROMTag found in that copy is initialised (InitResident), the board
; being the "current binding" of expansion (hard disk driver of a board: uaehf.device under UAE). RomBoot
; (LVO -30), called by strap when DF0: is not bootable, calls the BootPoint of each bootable BootNode of
; eb_MountList (ln_Type NT_BOOTNODE, ln_Name = ConfigDev of the board); a BootPoint that starts dos does not return.
; IMPLEMENTATION track ("clean"): AutoDocs expansion + NDK libraries/configvars.i, configregs.i, expansionbase.i
; + spec. NO ROM reading.

                include "exec.i"
                include "expansion.i"

                xdef    romboot_romtag

                EVEN
romboot_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    romboot_romtag
        dc.l    romboot_end
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,-40
        dc.l    romboot_name
        dc.l    romboot_name
        dc.l    romboot_inittab
romboot_name:
        dc.b    "romboot.library",0
rb_expname:
        dc.b    "expansion.library",0
        EVEN
romboot_inittab:
        dc.l    LIB_SIZE
        dc.l    romboot_vectors
        dc.l    romboot_datatab
        dc.l    romboot_initfunc
romboot_vectors:
        dc.l    rb_open              ; -6
        dc.l    rb_close             ; -12
        dc.l    rb_null              ; -18
        dc.l    rb_null              ; -24
        dc.l    rb_romboot           ; -30 RomBoot()
        dc.l    -1
romboot_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)
        dc.w    $D000,LIB_VERSION,34
        dc.b    0
        EVEN

rb_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
rb_close:
        subq.w  #1,LIB_OPENCNT(a6)
rb_null:
        moveq   #0,d0
        rts

; rb_diag(a2 = ConfigDev) -> a0 = RAM copy of its DiagArea if it is usable (valid Diag, copy present,
; CONFIGTIME moment), Z = 1 otherwise. Preserves everything else.
rb_diag:
        suba.l  a0,a0
        btst    #ERTB_DIAGVALID,ER_TYPE(a2)
        beq.s   .dg_ret
        move.l  ER_RESERVED0C(a2),a0
        cmpa.w  #0,a0
        beq.s   .dg_ret
        btst    #4,DA_CONFIG(a0)     ; DAC_CONFIGTIME
        bne.s   .dg_ret              ; Z = 0: usable
        suba.l  a0,a0
        cmpa.w  #0,a0                ; Z = 1
.dg_ret:
        rts

; initFunc (d0 = base, a6 = SysBase) -> d0 = base: name, then ROMTags of the boards (spec §2.1).
romboot_initfunc:
        movem.l d2-d3/a2-a5,-(sp)
        move.l  d0,a4                ; a4 = RombootBase
        lea     romboot_name(pc),a0
        move.l  a0,LN_NAME(a4)
        lea     rb_expname(pc),a1
        moveq   #33,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .in_ret
        move.l  d0,a5                ; a5 = ExpansionBase
        move.l  EB_BOARDLIST(a5),a2  ; a2 = current ConfigDev
.in_cd:
        tst.l   (a2)
        beq.s   .in_done
        btst    #CDB_CONFIGME,CD_FLAGS(a2)
        beq.s   .in_next
        move.l  a6,-(sp)
        move.l  a5,a6
        jsr     EXP_LVO_OBTAINBINDING(a6)
        clr.l   -(sp)                ; CurrentBinding: ConfigDev, then null FileName / ProductString / ToolTypes
        clr.l   -(sp)
        clr.l   -(sp)
        move.l  a2,-(sp)
        move.l  sp,a0
        moveq   #CB_SIZEOF,d0
        jsr     EXP_LVO_SETBINDING(a6)
        lea     CB_SIZEOF(sp),sp
        move.l  (sp)+,a6
        bsr.s   rb_diag
        beq.s   .in_rel
        moveq   #0,d2
        move.w  DA_SIZE(a0),d2       ; d2 = bytes to scan
        move.l  a0,a3
.in_scan:
        subq.l  #2,d2
        bmi.s   .in_rel
        cmp.w   #RTC_MATCHWORD,(a3)
        bne.s   .in_step
        cmpa.l  RT_MATCHTAG(a3),a3
        bne.s   .in_step
        move.l  a3,a1                ; first ROMTag of the board: initialised (only one)
        moveq   #0,d1
        jsr     LVO_INITRESIDENT(a6)
        bra.s   .in_rel
.in_step:
        addq.l  #2,a3
        bra.s   .in_scan
.in_rel:
        move.l  a6,-(sp)
        move.l  a5,a6
        jsr     EXP_LVO_RELEASEBINDING(a6)
        move.l  (sp)+,a6
.in_next:
        move.l  (a2),a2
        bra.s   .in_cd
.in_done:
        move.l  a5,a1
        jsr     LVO_CLOSELIBRARY(a6)
.in_ret:
        move.l  a4,d0
        movem.l (sp)+,d2-d3/a2-a5
        rts

; RomBoot() (a6 = RombootBase) -> d0 = 0: BootPoint of each bootable BootNode of eb_MountList, in list order
; (spec §2.2), with A0 = called address, A1 = ConfigDev (also at 4(sp)), A6 = ExecBase; a BootPoint that
; returns lets the next one go. A null BootPoint is ignored (instead of jumping to the start of the copy).
rb_romboot:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  ($4).w,a6
        lea     rb_expname(pc),a1
        moveq   #33,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   .rb_ret
        move.l  d0,a5                ; a5 = ExpansionBase
        move.l  EB_MOUNTLIST(a5),a4  ; a4 = current BootNode
.rb_node:
        move.l  (a4),d7              ; d7 = next (reread before the call)
        beq.s   .rb_done
        tst.l   BN_DEVICENODE(a4)
        beq.s   .rb_next
        cmp.b   #NT_BOOTNODE,LN_TYPE(a4)
        bne.s   .rb_next
        move.l  LN_NAME(a4),d0
        beq.s   .rb_next
        move.l  d0,a2                ; a2 = ConfigDev
        bsr     rb_diag
        beq.s   .rb_next
        moveq   #0,d0
        move.w  DA_BOOTPOINT(a0),d0
        beq.s   .rb_next
        add.l   d0,a0                ; a0 = BootPoint
        move.l  a2,a1
        movem.l d7/a4-a5,-(sp)
        move.l  a2,-(sp)             ; 4(sp) on entry to the BootPoint
        move.l  ($4).w,a6
        jsr     (a0)
        addq.l  #4,sp
        movem.l (sp)+,d7/a4-a5
        move.l  ($4).w,a6
.rb_next:
        move.l  d7,a4
        bra.s   .rb_node
.rb_done:
        move.l  a5,a1
        jsr     LVO_CLOSELIBRARY(a6)
.rb_ret:
        moveq   #0,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

romboot_end:
