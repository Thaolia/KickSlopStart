; src/exec/keymap.s — keymap.resource (#5) + kbd_cook : keycode(+qualifiers) -> ASCII.
;
; ROMTag direct-init (pri 100, place roadmap keymap.resource). km_init crée la resource via MakeLibrary (base
; library-like + jump table SetKeyMapDefault/AskKeyMapDefault), installe la keymap PAR DÉFAUT (US QWERTY, ou FR
; AZERTY si KEYMAP_AZERTY=1), publie KM_RESBASE (lu par kbd_cook), AddResource. Les tables (km_us_lo/hi, km_fr_lo/hi)
; sont HAND-AUTHORED (tests/mk_keymaps.py -> keymapdata.s) — JAMAIS extraites de la ROM.
;
; kbd_cook(keycode, qualifiers) -> ASCII applique SHIFT (table _hi), CAPS (majuscule des lettres), CTRL (char & $1F).
; Déviation assumée : représentation SIMPLIFIÉE (2 tables lo/hi + règles caps/ctrl) au lieu de la struct KeyMap V34
; complète (octets de type par touche + entrées chaîne pour dead-keys) ; dead-keys/compose différés.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs keymap.resource + layouts clavier publics. AUCUNE lecture ROM.

                include "exec.i"

                xdef    kbd_cook
                xref    km_us_lo
                xref    km_us_hi
                xref    km_fr_lo
                xref    km_fr_hi

; --- ROMTag keymap.resource (scanné par build_reslist ; direct-init) ---
                EVEN
km_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    km_romtag            ; RT_MATCHTAG = self
        dc.l    km_end               ; RT_ENDSKIP
        dc.b    0,34,NT_RESOURCE,100 ; RT_FLAGS (0 = direct-init), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    km_name              ; RT_NAME
        dc.l    km_name              ; RT_IDSTRING
        dc.l    km_init              ; RT_INIT (direct-init)
km_name:
        dc.b    "keymap.resource",0
        EVEN
km_vectors:                          ; table ABSOLUE, terminée par -1
        dc.l    km_SetKeyMapDefault  ; LVO -6
        dc.l    km_AskKeyMapDefault  ; LVO -12
        dc.l    -1

; km_init : direct-init (D0=0, A0=segList, A6=ExecBase) -> D0=0. Crée la resource + keymap par défaut.
km_init:
        movem.l d2/a2,-(sp)
        lea     km_vectors(pc),a0
        suba.l  a1,a1                ; structure = NULL
        suba.l  a2,a2                ; init = NULL
        move.l  #KMR_SIZE,d0
        moveq   #0,d1                ; segList = 0
        jsr     LVO_MAKELIBRARY(a6)  ; -> d0 = base (jump table bâtie)
        tst.l   d0
        beq.s   .ki_ret
        move.l  d0,a2                ; a2 = base resource
        lea     km_name(pc),a0
        move.l  a0,LN_NAME(a2)
        move.b  #NT_RESOURCE,LN_TYPE(a2)
                ifne    KEYMAP_AZERTY
        move.l  #km_fr_lo,KMR_LO(a2) ; keymap par défaut = FR AZERTY
        move.l  #km_fr_hi,KMR_HI(a2)
                else
        move.l  #km_us_lo,KMR_LO(a2) ; keymap par défaut = US QWERTY
        move.l  #km_us_hi,KMR_HI(a2)
                endc
        move.l  a2,KM_RESBASE        ; publie la base pour kbd_cook
        move.l  a2,a1
        jsr     LVO_ADDRESOURCE(a6)  ; AddResource(a1=base)
.ki_ret:
        moveq   #0,d0
        movem.l (sp)+,d2/a2
        rts

; km_AskKeyMapDefault() -> d0 = base resource (notre détenteur de keymap). a6 = base resource.
km_AskKeyMapDefault:
        move.l  KM_RESBASE,d0
        rts
; km_SetKeyMapDefault(keymap a0) : a0 = struct {lo@0, hi@4} -> remplace les tables actives. a6 = base resource.
km_SetKeyMapDefault:
        move.l  KM_RESBASE,a1
        move.l  a1,d0
        beq.s   .skd_ret
        move.l  (a0),KMR_LO(a1)
        move.l  4(a0),KMR_HI(a1)
.skd_ret:
        rts

; kbd_cook(keycode d0.b [0..0x5F], qualifiers d1.w) -> d0.b = ASCII (0 = non mappé). Applique SHIFT/CAPS/CTRL.
; Clobbe d0 ; préserve d2/a0/a1 (et le reste). Lit la keymap active via KM_RESBASE (keymap.resource).
kbd_cook:
        movem.l d2/a0/a1,-(sp)
        moveq   #0,d2
        move.b  d0,d2                ; d2 = keycode
        cmp.w   #$60,d2
        bhs.s   .kc_zero             ; >= 0x60 (qualifieurs/spéciaux) -> non mappé
        move.l  KM_RESBASE,a1
        move.l  a1,d0
        beq.s   .kc_zero             ; keymap.resource absente
                ifeq    KM_NO_SHIFT
        move.w  d1,d0                ; SHIFT ?
        and.w   #KQ_SHIFT,d0
        beq.s   .kc_lo
        move.l  KMR_HI(a1),a0        ; table shiftée
        move.b  0(a0,d2.w),d0
        bne.s   .kc_have             ; variante shiftée existe
                endc                 ; RED KM_NO_SHIFT : ignore SHIFT -> toujours la table non-shiftée
.kc_lo:
        move.l  KMR_LO(a1),a0        ; table non-shiftée (défaut + repli)
        move.b  0(a0,d2.w),d0
.kc_have:
        tst.b   d0
        beq.s   .kc_done             ; non mappé
        btst    #KQB_CAPS,d1         ; CAPS : majuscule des lettres a-z
        beq.s   .kc_noc
        cmp.b   #'a',d0
        blo.s   .kc_noc
        cmp.b   #'z',d0
        bhi.s   .kc_noc
        sub.b   #$20,d0
.kc_noc:
        btst    #KQB_CTRL,d1         ; CTRL : lettre -> char & $1F
        beq.s   .kc_done
        move.b  d0,d2
        and.b   #$DF,d2              ; vers majuscule (approx)
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
