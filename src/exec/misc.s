; src/exec/misc.s — misc.resource : arbitrage des bits matériels partagés série / parallèle (unités 0 = bits de
; données série, 1 = bits de contrôle série, 2 = ports parallèles, 3 = bits parallèles). serial.device (chargé
; depuis DEVS:) l'ouvre dans son init et alloue les unités 0 et 1 : sans cette ressource, son init échoue.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs misc.resource (AllocMiscResource / FreeMiscResource) +
; resources/misc.i. AUCUNE lecture ROM.

                include "exec.i"

MR_UNITS        EQU 4
MR_OWNERS       EQU LIB_SIZE         ; nom du propriétaire de chaque unité (0 = libre)
MR_SIZE         EQU LIB_SIZE+MR_UNITS*4

        EVEN
misc_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    misc_romtag          ; RT_MATCHTAG = self
        dc.l    misc_end             ; RT_ENDSKIP
        dc.b    RTF_COLDSTART,34,NT_RESOURCE,70  ; RT_FLAGS (COLDSTART, init directe), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    misc_name            ; RT_NAME
        dc.l    misc_name            ; RT_IDSTRING
        dc.l    misc_init            ; RT_INIT
misc_name:
        dc.b    "misc.resource",0
        EVEN
misc_vectors:
        dc.l    misc_alloc           ; -6  AllocMiscResource(unité d0, nom a1)
        dc.l    misc_free            ; -12 FreeMiscResource(unité d0)
        dc.l    -1

misc_init:
        lea     misc_vectors(pc),a0
        suba.l  a1,a1
        suba.l  a2,a2
        move.l  #MR_SIZE,d0
        moveq   #0,d1
        jsr     LVO_MAKELIBRARY(a6)
        tst.l   d0
        beq.s   .mi_ret
        move.l  d0,a1
        lea     misc_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        jsr     LVO_ADDRESOURCE(a6)
.mi_ret:
        moveq   #0,d0
        rts

; AllocMiscResource(unité d0, nom a1, a6 = ressource) -> d0 = 0 si l'unité est attribuée à l'appelant, sinon le nom
; du propriétaire actuel. Atomique (Disable).
misc_alloc:
        movem.l d2/a2/a6,-(sp)
        lsl.l   #2,d0
        lea     MR_OWNERS(a6,d0.l),a2   ; a2 = case de l'unité
        move.l  a1,d2                   ; d2 = nom demandeur
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.l  (a2),d0
        bne.s   .ma_busy
        move.l  d2,(a2)
.ma_busy:
        move.l  d0,d2
        jsr     LVO_ENABLE(a6)
        move.l  d2,d0
        movem.l (sp)+,d2/a2/a6
        rts

; FreeMiscResource(unité d0, a6 = ressource) : libère l'unité.
misc_free:
        lsl.l   #2,d0
        clr.l   MR_OWNERS(a6,d0.l)
        rts
misc_end:
