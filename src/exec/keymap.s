; src/exec/keymap.s — keymap.resource (V34 layout) + key conversion through a struct KeyMap.
;
; Direct-init ROMTag (pri 100). km_init allocates the V34 resource (spec console-keymap-v34 §1.1): Node, kr_List and
; one built-in KeyMapNode whose struct KeyMap points to our hand-authored tables (US QWERTY, or FR AZERTY if
; KEYMAP_AZERTY=1; tests/mk_keymaps.py -> keymapdata.s, NEVER extracted from the ROM). No function vectors, like
; V34. Disk keymaps (SetMap) are added to kr_List by their loader. KM_DEFKM points to the current default KeyMap:
; this node at first, then console.device's copy (which CD_SETDEFAULTKEYMAP replaces).
;
; km_conv converts one RAWKEY event through a KeyMap (spec §5.2): repeat filter, NOP, key-up (KCF_DOWNUP), Shift /
; Caps (Capsable keys) / Alt / Ctrl, combination index, VANILLA (with the Ctrl rule), plain bytes or byte array,
; KCF_STRING, KCF_DEAD (dead keys and modifiable keys, previous keys read from ie_X / ie_Y).
; kbd_cook(keycode, qualifiers) -> one byte through the current default KeyMap (0 if none or more than one byte).
; IMPLEMENTATION track ("clean"): devices/keymap.h + spec console-keymap-v34. NO ROM reading.

                include "exec.i"

                xdef    kbd_cook
                xdef    km_conv
                xref    km_us
                xref    km_fr

; --- keymap.resource ROMTag (scanned by build_reslist; direct-init) ---
                EVEN
km_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    km_romtag            ; RT_MATCHTAG = self
        dc.l    km_end               ; RT_ENDSKIP
        dc.b    RTF_COLDSTART,34,NT_RESOURCE,100 ; RT_FLAGS (COLDSTART, direct init), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    km_name              ; RT_NAME
        dc.l    km_name              ; RT_IDSTRING
        dc.l    km_init              ; RT_INIT (direct-init)
km_name:
        dc.b    "keymap.resource",0
km_nodename:
                ifne    KEYMAP_AZERTY
        dc.b    "f",0
                else
        dc.b    "usa",0
                endc
        EVEN

; km_init: direct-init (D0=0, A0=segList, A6=ExecBase) -> D0=0. Resource + built-in KeyMapNode, AddResource.
km_init:
        move.l  a2,-(sp)
        move.l  #KMR_SIZE,d0
        move.l  #MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ki_ret
        move.l  d0,a2
        move.b  #NT_RESOURCE,LN_TYPE(a2)
        lea     km_name(pc),a0
        move.l  a0,LN_NAME(a2)
        lea     KR_NODE(a2),a0       ; the node is the only element of kr_List
        lea     KR_LIST+LH_TAIL(a2),a1
        move.l  a0,KR_LIST(a2)       ; lh_Head
        move.l  a0,KR_LIST+8(a2)     ; lh_TailPred
        move.l  a1,LN_SUCC(a0)
        lea     KR_LIST(a2),a1
        move.l  a1,LN_PRED(a0)
        lea     km_nodename(pc),a1
        move.l  a1,LN_NAME(a0)
                ifne    KEYMAP_AZERTY
        lea     km_fr,a1
                else
        lea     km_us,a1
                endc
        lea     KN_KEYMAP(a0),a0
        move.l  a0,KM_DEFKM
        moveq   #KM_SIZEOF/4-1,d0
.ki_cp:
        move.l  (a1)+,(a0)+
        dbra    d0,.ki_cp
        move.l  a2,KM_RESBASE
        move.l  a2,a1
        jsr     LVO_ADDRESOURCE(a6)
.ki_ret:
        moveq   #0,d0
        move.l  (sp)+,a2
        rts

; kbd_cook(keycode d0.b, qualifiers d1.w) -> d0.b = the character the current default KeyMap gives for that key
; press (0 if it gives nothing, or a sequence). Preserves everything except d0.
kbd_cook:
        movem.l d1/a0-a2,-(sp)
        lea     -24(sp),sp           ; InputEvent (22 bytes) + 1-byte result
        move.l  sp,a0
        clr.l   IE_NEXTEVENT(a0)
        move.b  #IECLASS_RAWKEY,IE_CLASS(a0)
        and.w   #$00FF,d0
        move.w  d0,IE_CODE(a0)
                ifne    KM_NO_SHIFT
        and.w   #~KQ_SHIFT,d1        ; RED: Shift ignored
                endc
        move.w  d1,IE_QUALIFIER(a0)
        clr.l   IE_X(a0)
        moveq   #0,d0
        move.l  KM_DEFKM,d1
        beq.s   .kc_ret
        move.l  d1,a2
        lea     22(sp),a1
        moveq   #1,d1
        bsr.s   km_conv
        subq.l  #1,d0
        bne.s   .kc_zero
        move.b  22(sp),d0
        bra.s   .kc_ret
.kc_zero:
        moveq   #0,d0
.kc_ret:
        lea     24(sp),sp
        movem.l (sp)+,d1/a0-a2
        rts

; km_conv(event a0, buffer a1, room d1.l, keymap a2) -> d0.l = bytes written for this RAWKEY event (0 = nothing),
; -1 if they do not fit (spec console-keymap-v34 §5.2). Preserves everything except d0.
km_conv:
        movem.l d1-d7/a0-a4,-(sp)
        move.l  d1,d7                ; d7 = room
        move.l  a1,a4                ; a4 = output
        move.w  IE_X(a0),d6          ; previous key (dead keys): code, qualifier
        swap    d6
        move.w  IE_Y(a0),d6          ; the key before it
        move.w  IE_CODE(a0),d2
        move.w  IE_QUALIFIER(a0),d3
        bsr     km_entry             ; d0 = state | 0, d4 = type, d5 = combination, d1 = long
        move.l  d1,a1                ; a1 = the key's long (value or descriptor)
        tst.w   d0
        beq     .kv_zero
        btst    #6,d4                ; KCF_STRING
        bne.s   .kv_str
        btst    #5,d4                ; KCF_DEAD
        bne     .kv_dead
        move.b  d4,d1
        and.b   #7,d1
        cmp.b   #7,d1                ; KC_VANILLA
        bne.s   .kv_plain
        move.l  a1,d1
        btst    #2,d0                ; Ctrl: first %01xxxxxx byte from the Shift/Alt one, & $1F
        beq.s   .kv_lsb
        and.w   #3,d5
        moveq   #3,d4
.kv_rot:
        bsr     .kv_byte
        move.b  d0,d3
        and.b   #$C0,d3
        cmp.b   #$40,d3
        beq.s   .kv_ctl
        addq.w  #1,d5
        and.w   #3,d5
        dbra    d4,.kv_rot
        bsr     .kv_byte             ; none: the selected byte as is
        bra.s   .kv_one
.kv_ctl:
        and.b   #$1F,d0
        bra.s   .kv_one
.kv_plain:
        move.l  a1,d1
        move.b  d4,d0                ; number of qualifier bits in the type
        and.w   #$0F,d0
        moveq   #0,d3
.kv_cnt:
        lsr.w   #1,d0
        bcc.s   .kv_cn
        addq.w  #1,d3
.kv_cn:
        tst.w   d0
        bne.s   .kv_cnt
        cmp.w   #2,d3                ; up to 4 combinations: bytes of the long
        bls.s   .kv_lsb
        move.l  d1,a0                ; more: the long points to a byte array
        moveq   #0,d0
        move.b  0(a0,d5.w),d0
        bra.s   .kv_one
.kv_lsb:
        bsr.s   .kv_byte
.kv_one:
        tst.l   d7
        beq.s   .kv_over
        move.b  d0,(a4)
        moveq   #1,d0
        bra.s   .kv_ret
.kv_str:                             ; pairs (length, offset from the descriptor)
        move.l  a1,a0
        add.w   d5,d5
        moveq   #0,d0
        move.b  0(a0,d5.w),d0
        moveq   #0,d4
        move.b  1(a0,d5.w),d4
        add.w   d4,a0
        cmp.l   d7,d0
        bhi.s   .kv_over
        move.w  d0,d4
        bra.s   .kv_se
.kv_sc:
        move.b  (a0)+,(a4)+
.kv_se:
        dbra    d4,.kv_sc
        bra.s   .kv_ret
.kv_dead:                            ; pairs (flag, value)
        move.l  a1,a3
        add.w   d5,d5
        move.b  0(a3,d5.w),d4
        moveq   #0,d0
        move.b  1(a3,d5.w),d0
        btst    #3,d4                ; DPF_DEAD: dead key, nothing returned
        bne.s   .kv_zero
        btst    #0,d4                ; DPF_MOD: table indexed by the dead key pressed just before
        beq.s   .kv_one
        add.w   d0,a3                ; a3 = translation table
        move.l  d6,d2
        swap    d2
        bsr     km_deadidx           ; d0 = index of the previous key if it was dead
        move.w  d0,d4
        lsr.w   #4,d4                ; double dead key: (high x low) + low index of the key before
        beq.s   .kv_k
        and.w   #$0F,d0
        mulu    d4,d0
        move.w  d0,d4
        move.w  d6,d2
        bsr     km_deadidx
        and.w   #$0F,d0
        add.w   d4,d0
.kv_k:
        move.b  0(a3,d0.w),d0
        bra.s   .kv_one
.kv_over:
        moveq   #-1,d0
        bra.s   .kv_ret
.kv_zero:
        moveq   #0,d0
.kv_ret:
        movem.l (sp)+,d1-d7/a0-a4
        rts
.kv_byte:                            ; d0 = byte d5 of d1, counted from the least significant
        move.l  d1,d0
        move.w  d5,-(sp)
        lsl.w   #3,d5
        lsr.l   d5,d0
        move.w  (sp)+,d5
        and.l   #$FF,d0
        rts

; km_deadidx(d2.w = key code (high byte) and qualifier (low byte), a2 = keymap) -> d0.w = its dead-key index if that
; key, pressed with that qualifier, is a dead key; 0 otherwise. Preserves everything except d0.
km_deadidx:
        movem.l d1-d5/a0/a3,-(sp)
        moveq   #0,d3
        move.b  d2,d3                ; qualifier byte
        lsr.w   #8,d2                ; code (key down)
        bsr.s   km_entry
        tst.w   d0
        beq.s   .kd_no
        btst    #5,d4
        beq.s   .kd_no
        move.l  d1,a0
        add.w   d5,d5
        btst    #3,0(a0,d5.w)        ; DPF_DEAD
        beq.s   .kd_no
        moveq   #0,d0
        move.b  1(a0,d5.w),d0
        bra.s   .kd_ret
.kd_no:
        moveq   #0,d0
.kd_ret:
        movem.l (sp)+,d1-d5/a0/a3
        rts

; km_entry(d2.w = code (bit 7 = key up), d3.w = qualifier, a2 = keymap) -> d0.w = 0 if the key gives nothing, else
; state | $100 (bit 0 Shift, 1 Alt, 2 Ctrl, 3 key up); d4.b = type, d5.w = combination index, d1.l = the key's
; long. Clobbers a0/a3.
km_entry:
        move.w  d2,d1
        and.w   #$7F,d1
        cmp.w   #$77,d1
        bhi     .ke_none
        move.l  a2,a3                ; Lo tables
        cmp.w   #$40,d1
        blo.s   .ke_lo
        lea     16(a2),a3            ; Hi tables
        sub.w   #$40,d1
.ke_lo:
        btst    #9,d3                ; IEQUALIFIER_REPEAT ($0200)
        beq.s   .ke_norep
        move.l  12(a3),a0            ; not Repeatable: nothing
        bsr     .ke_bit
        beq     .ke_none
.ke_norep:
        move.l  (a3),a0
        move.b  0(a0,d1.w),d4        ; type
        bmi.s   .ke_none             ; KCF_NOP
        moveq   #0,d0
        move.w  d3,d5
        and.w   #$03,d5              ; Shift
        beq.s   .ke_ns
        bset    #0,d0
.ke_ns:
        btst    #2,d3                ; Caps Lock on a Capsable key = Shift
        beq.s   .ke_nc
        move.l  8(a3),a0
        bsr.s   .ke_bit
        beq.s   .ke_nc
        bset    #0,d0
.ke_nc:
        move.w  d3,d5
        and.w   #$30,d5              ; Alt
        beq.s   .ke_na
        bset    #1,d0
.ke_na:
        btst    #3,d3                ; Ctrl
        beq.s   .ke_nt
        bset    #2,d0
.ke_nt:
        btst    #7,d2                ; key up: only KCF_DOWNUP keys
        beq.s   .ke_dn
        btst    #3,d4
        beq.s   .ke_none
        bset    #3,d0
.ke_dn:
        movem.l d6-d7,-(sp)          ; combination index: qualifier bits of the type, weights 1, 2, 4...
        moveq   #0,d5
        moveq   #1,d6
        moveq   #0,d7
.ke_ix:
        btst    d7,d4
        beq.s   .ke_ixn
        btst    d7,d0
        beq.s   .ke_ixw
        or.w    d6,d5
.ke_ixw:
        add.w   d6,d6
.ke_ixn:
        addq.w  #1,d7
        cmp.w   #4,d7
        blo.s   .ke_ix
        movem.l (sp)+,d6-d7
        move.l  4(a3),a0
        add.w   d1,d1
        add.w   d1,d1
        move.l  0(a0,d1.w),d1
        or.w    #$100,d0
        rts
.ke_none:
        moveq   #0,d0
        rts
.ke_bit:                             ; Z = 0 if bit d1 of the bit array a0 is set
        movem.l d1/d4,-(sp)
        move.w  d1,d4
        lsr.w   #3,d4
        move.b  0(a0,d4.w),d4
        and.w   #7,d1
        btst    d1,d4
        movem.l (sp)+,d1/d4
        rts

        EVEN
km_end:
