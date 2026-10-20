; src/exec/potgo.s — potgo.resource : partage du registre POTGO (ports analogiques / broches 5 et 9 des manettes).
;
; AllocPotBits accorde des bits START / DATxx non pris (un DATxx en entrée exige qu'aucun autre ne tienne START :
; un START étranger relancerait ses compteurs ; START exige qu'aucun DATxx en entrée ne soit déjà pris). Les OUTxx
; demandés avec un DATxx accordé sont mémorisés. WritePotgo écrit les bits du masque ; l'octet haut est conservé
; pour les écritures suivantes, START n'est jamais conservé (écrit seulement quand il est demandé explicitement).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs potgo.resource + hardware/custom.i. AUCUNE lecture ROM.

                include "exec.i"

POTGO_HW        EQU CUSTOM+$034
PG_ALLOC        EQU LIB_SIZE         ; UWORD bits attribués (START, DATxx et leurs OUTxx)
PG_SHADOW       EQU LIB_SIZE+2       ; UWORD octet haut conservé de POTGO
PG_SIZE         EQU LIB_SIZE+4
PGF_START       EQU $0001
PGM_DAT         EQU $5500            ; DATLX/DATLY/DATRX/DATRY (bits 8/10/12/14), OUTxx = bit suivant

        EVEN
potgo_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    potgo_romtag
        dc.l    potgo_end
        dc.b    RTF_COLDSTART,34,NT_RESOURCE,100
        dc.l    potgo_name
        dc.l    potgo_name
        dc.l    potgo_init
potgo_name:
        dc.b    "potgo.resource",0
        EVEN
potgo_vectors:
        dc.l    pg_alloc             ; -6  AllocPotBits(bits d0)
        dc.l    pg_free              ; -12 FreePotBits(bits d0)
        dc.l    pg_write             ; -18 WritePotgo(word d0, mask d1)
        dc.l    -1

potgo_init:
        lea     potgo_vectors(pc),a0
        suba.l  a1,a1
        suba.l  a2,a2
        move.l  #PG_SIZE,d0
        moveq   #0,d1
        jsr     LVO_MAKELIBRARY(a6)
        tst.l   d0
        beq.s   .pi_ret
        move.l  d0,a1
        clr.l   PG_ALLOC(a1)         ; PG_ALLOC + PG_SHADOW
        lea     potgo_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        jsr     LVO_ADDRESOURCE(a6)
.pi_ret:
        moveq   #0,d0
        rts

; pg_inputs : d1 = bits attribués -> d1 = DATxx attribués en entrée (OUTxx correspondant à 0), Z si aucun. Utilise d0.
pg_inputs:
        move.w  d1,d0
        lsr.w   #1,d0                ; OUTxx ramenés sur la position de leur DATxx
        not.w   d0
        and.w   #PGM_DAT,d0
        and.w   d0,d1
        rts

; AllocPotBits(bits d0) -> d0 = bits START/DATxx accordés. Atomique (Disable).
pg_alloc:
        movem.l d2-d4/a6,-(sp)
        move.w  d0,d2                ; d2 = demande
        move.l  a6,a0
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.w  PG_ALLOC(a0),d3      ; d3 = déjà attribués
        moveq   #0,d4                ; d4 = accordés (DATxx + OUTxx + START)
        moveq   #3,d1
        move.w  #$0100,d0            ; d0 = DATxx courant
.pa_dat:
        move.w  d0,-(sp)
        and.w   d2,d0
        beq.s   .pa_next             ; non demandé
        and.w   d3,d0
        bne.s   .pa_next             ; déjà pris
        move.w  (sp),d0
        add.w   d0,d0                ; OUTxx
        and.w   d2,d0
        bne.s   .pa_grant            ; sortie : START étranger sans effet
        btst    #0,d3
        bne.s   .pa_next             ; entrée alors qu'un autre tient START
.pa_grant:
        or.w    (sp),d4
        or.w    d0,d4                ; OUTxx demandé avec le DATxx
.pa_next:
        move.w  (sp)+,d0
        lsl.w   #2,d0
        dbra    d1,.pa_dat
        btst    #0,d2
        beq.s   .pa_done
        btst    #0,d3
        bne.s   .pa_done             ; START déjà pris
        move.w  d3,d1
        bsr.s   pg_inputs
        bne.s   .pa_done             ; des DATxx en entrée sont déjà pris
        or.w    #PGF_START,d4
.pa_done:
        or.w    d4,PG_ALLOC(a0)
        jsr     LVO_ENABLE(a6)
        move.w  d4,d0
        and.l   #PGM_DAT|PGF_START,d0
        movem.l (sp)+,d2-d4/a6
        rts

; FreePotBits(bits d0) : libère les START/DATxx donnés et les OUTxx associés.
pg_free:
        and.w   #PGM_DAT|PGF_START,d0
        move.w  d0,d1
        and.w   #PGM_DAT,d1
        add.w   d1,d1
        or.w    d1,d0                ; + OUTxx des DATxx libérés
        not.w   d0
        and.w   d0,PG_ALLOC(a6)      ; and.w mémoire : indivisible sur 68000
        rts

; WritePotgo(word d0, mask d1).
pg_write:
        movem.l d2/a6,-(sp)
        move.l  a6,a0
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.w  d1,d2
        and.w   #$FF00,d2
        not.w   d2
        and.w   PG_SHADOW(a0),d2     ; octet haut conservé hors masque
        and.w   d0,d1                ; bits demandés
        move.w  d1,d0
        and.w   #$FF00,d0
        or.w    d0,d2
        move.w  d2,PG_SHADOW(a0)
        and.w   #PGF_START,d1
        or.w    d1,d2                ; START seulement s'il est écrit maintenant
        move.w  d2,POTGO_HW
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,d2/a6
        rts
potgo_end:
