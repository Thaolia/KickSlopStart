; src/exec/keymap.s — keymap.resource (#5) + kbd_cook: keycode(+qualifiers) -> ASCII.
;
; Direct-init ROMTag (pri 100, keymap.resource roadmap slot). km_init creates the resource via MakeLibrary
; (library-like base + SetKeyMapDefault/AskKeyMapDefault jump table), installs the DEFAULT keymap (US QWERTY, or
; FR AZERTY if KEYMAP_AZERTY=1), publishes KM_RESBASE (read by kbd_cook), AddResource. The tables (km_us_lo/hi,
; km_fr_lo/hi) are HAND-AUTHORED (tests/mk_keymaps.py -> keymapdata.s) — NEVER extracted from the ROM.
;
; kbd_cook(keycode, qualifiers) -> ASCII applies SHIFT (_hi table), CAPS (upper case of letters), CTRL (char & $1F).
; Accepted deviation: SIMPLIFIED representation (2 lo/hi tables + caps/ctrl rules) instead of the complete V34
; struct KeyMap (type bytes per key + string entries for dead keys); dead keys/compose deferred.
; IMPLEMENTATION track ("clean"): AutoDocs keymap.resource + public keyboard layouts. NO ROM reading.

                include "exec.i"

                xdef    kbd_cook
                xref    km_us_lo
                xref    km_us_hi
                xref    km_fr_lo
                xref    km_fr_hi

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
        EVEN
km_vectors:                          ; ABSOLUTE table, terminated by -1
        dc.l    km_SetKeyMapDefault  ; LVO -6
        dc.l    km_AskKeyMapDefault  ; LVO -12
        dc.l    -1

; km_init: direct-init (D0=0, A0=segList, A6=ExecBase) -> D0=0. Creates the resource + default keymap.
km_init:
        movem.l d2/a2,-(sp)
        lea     km_vectors(pc),a0
        suba.l  a1,a1                ; structure = NULL
        suba.l  a2,a2                ; init = NULL
        move.l  #KMR_SIZE,d0
        moveq   #0,d1                ; segList = 0
        jsr     LVO_MAKELIBRARY(a6)  ; -> d0 = base (jump table built)
        tst.l   d0
        beq.s   .ki_ret
        move.l  d0,a2                ; a2 = resource base
        lea     km_name(pc),a0
        move.l  a0,LN_NAME(a2)
        move.b  #NT_RESOURCE,LN_TYPE(a2)
                ifne    KEYMAP_AZERTY
        move.l  #km_fr_lo,KMR_LO(a2) ; default keymap = FR AZERTY
        move.l  #km_fr_hi,KMR_HI(a2)
                else
        move.l  #km_us_lo,KMR_LO(a2) ; default keymap = US QWERTY
        move.l  #km_us_hi,KMR_HI(a2)
                endc
        move.l  a2,KM_RESBASE        ; publish the base for kbd_cook
        move.l  a2,a1
        jsr     LVO_ADDRESOURCE(a6)  ; AddResource(a1=base)
.ki_ret:
        moveq   #0,d0
        movem.l (sp)+,d2/a2
        rts

; km_AskKeyMapDefault() -> d0 = resource base (our keymap holder). a6 = resource base.
km_AskKeyMapDefault:
        move.l  KM_RESBASE,d0
        rts
; km_SetKeyMapDefault(keymap a0): a0 = struct {lo@0, hi@4} -> replaces the active tables. a6 = resource base.
km_SetKeyMapDefault:
        move.l  KM_RESBASE,a1
        move.l  a1,d0
        beq.s   .skd_ret
        move.l  (a0),KMR_LO(a1)
        move.l  4(a0),KMR_HI(a1)
.skd_ret:
        rts

; kbd_cook(keycode d0.b [0..0x5F], qualifiers d1.w) -> d0.b = ASCII (0 = unmapped). Applies SHIFT/CAPS/CTRL.
; Clobbers d0; preserves d2/a0/a1 (and the rest). Reads the active keymap via KM_RESBASE (keymap.resource).
kbd_cook:
        movem.l d2/a0/a1,-(sp)
        moveq   #0,d2
        move.b  d0,d2                ; d2 = keycode
        cmp.w   #$60,d2
        bhs.s   .kc_zero             ; >= 0x60 (qualifiers/specials) -> unmapped
        move.l  KM_RESBASE,a1
        move.l  a1,d0
        beq.s   .kc_zero             ; keymap.resource missing
                ifeq    KM_NO_SHIFT
        move.w  d1,d0                ; SHIFT?
        and.w   #KQ_SHIFT,d0
        beq.s   .kc_lo
        move.l  KMR_HI(a1),a0        ; shifted table
        move.b  0(a0,d2.w),d0
        bne.s   .kc_have             ; shifted variant exists
                endc                 ; RED KM_NO_SHIFT: ignores SHIFT -> always the unshifted table
.kc_lo:
        move.l  KMR_LO(a1),a0        ; unshifted table (default + fallback)
        move.b  0(a0,d2.w),d0
.kc_have:
        tst.b   d0
        beq.s   .kc_done             ; unmapped
        btst    #KQB_CAPS,d1         ; CAPS: upper case of letters a-z
        beq.s   .kc_noc
        cmp.b   #'a',d0
        blo.s   .kc_noc
        cmp.b   #'z',d0
        bhi.s   .kc_noc
        sub.b   #$20,d0
.kc_noc:
        btst    #KQB_CTRL,d1         ; CTRL: letter -> char & $1F
        beq.s   .kc_done
        move.b  d0,d2
        and.b   #$DF,d2              ; to upper case (approx)
        cmp.b   #'A',d2
        blo.s   .kc_done
        cmp.b   #'Z',d2
        bhi.s   .kc_done
        and.b   #$1F,d0
.kc_done:
        movem.l (sp)+,d2/a0/a1
        rts
.kc_zero:
        moveq   #0,d0
        movem.l (sp)+,d2/a0/a1
        rts

        EVEN
km_end:
