; src/exec/library.s — exec.library : construction de la jump table LVO et
; fonctions « library/forbid/disable » (Open, Close, Expunge, Forbid, Permit,
; Disable, Enable). Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : docs/analysis/exec-spec.md +
; docs/exec-lvo-table.md + ABI publique. AUCUNE lecture de la ROM.
;
; M2.1a couvre : le MÉCANISME de dispatch (jump table) et le COMPORTEMENT des
; fonctions. Il ne prouve PAS la compatibilité d'offsets avec l'AmigaOS 1.3 réel
; (on appelle ce qu'on a soi-même patché) — validé par cross-check exec_lib.fd V34.

                include "exec.i"

                xdef    build_jumptable
                xdef    exec_Open
                xdef    exec_Close
                xdef    exec_Expunge
                xdef    exec_Forbid
                xdef    exec_Permit
                xdef    exec_Disable
                xdef    exec_Enable

                xref    exec_AddHead     ; lists.s
                xref    exec_AddTail
                xref    exec_Insert
                xref    exec_Remove
                xref    exec_RemHead
                xref    exec_RemTail
                xref    exec_Enqueue
                xref    exec_FindName
                xref    exec_AllocMem    ; memory.s
                xref    exec_FreeMem
                xref    exec_AvailMem
                xref    exec_TypeOfMem

; ============================ jump table ============================
; Remplit les 105 entrées (V34) avec _unimpl puis patche les LVO implémentés.
build_jumptable:                     ; a6 = SysBase ; clobbers d0/d1/a0
        lea     EXEC_BLOCK,a0
        move.w  #(EXEC_NEGSIZE/6)-1,d0
        move.l  #_unimpl,d1
.fill:
        move.w  #$4EF9,(a0)+
        move.l  d1,(a0)+
        dbf     d0,.fill
        move.w  #$4EF9,LVO_OPEN(a6)
        move.l  #exec_Open,LVO_OPEN+2(a6)
        move.w  #$4EF9,LVO_CLOSE(a6)
        move.l  #exec_Close,LVO_CLOSE+2(a6)
        move.w  #$4EF9,LVO_EXPUNGE(a6)
        move.l  #exec_Expunge,LVO_EXPUNGE+2(a6)
        move.w  #$4EF9,LVO_DISABLE(a6)
        move.l  #exec_Disable,LVO_DISABLE+2(a6)
        move.w  #$4EF9,LVO_ENABLE(a6)
        move.l  #exec_Enable,LVO_ENABLE+2(a6)
        move.w  #$4EF9,LVO_FORBID(a6)
        move.l  #exec_Forbid,LVO_FORBID+2(a6)
        move.w  #$4EF9,LVO_PERMIT(a6)
        move.l  #exec_Permit,LVO_PERMIT+2(a6)
        move.w  #$4EF9,LVO_ADDHEAD(a6)
        move.l  #exec_AddHead,LVO_ADDHEAD+2(a6)
        move.w  #$4EF9,LVO_ADDTAIL(a6)
        move.l  #exec_AddTail,LVO_ADDTAIL+2(a6)
        move.w  #$4EF9,LVO_INSERT(a6)
        move.l  #exec_Insert,LVO_INSERT+2(a6)
        move.w  #$4EF9,LVO_REMOVE(a6)
        move.l  #exec_Remove,LVO_REMOVE+2(a6)
        move.w  #$4EF9,LVO_REMHEAD(a6)
        move.l  #exec_RemHead,LVO_REMHEAD+2(a6)
        move.w  #$4EF9,LVO_REMTAIL(a6)
        move.l  #exec_RemTail,LVO_REMTAIL+2(a6)
        move.w  #$4EF9,LVO_ENQUEUE(a6)
        move.l  #exec_Enqueue,LVO_ENQUEUE+2(a6)
        move.w  #$4EF9,LVO_FINDNAME(a6)
        move.l  #exec_FindName,LVO_FINDNAME+2(a6)
        move.w  #$4EF9,LVO_ALLOCMEM(a6)
        move.l  #exec_AllocMem,LVO_ALLOCMEM+2(a6)
        move.w  #$4EF9,LVO_FREEMEM(a6)
        move.l  #exec_FreeMem,LVO_FREEMEM+2(a6)
        move.w  #$4EF9,LVO_AVAILMEM(a6)
        move.l  #exec_AvailMem,LVO_AVAILMEM+2(a6)
        move.w  #$4EF9,LVO_TYPEOFMEM(a6)
        move.l  #exec_TypeOfMem,LVO_TYPEOFMEM+2(a6)
        rts

_unimpl:
        moveq   #0,d0                ; LVO non implémenté : retour neutre
        rts

; ============================ fonctions exec ========================
exec_Open:                           ; -> d0 = SysBase
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
exec_Close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
exec_Expunge:
        moveq   #0,d0                ; exec ne s'expulse jamais
        rts

exec_Forbid:
        addq.b  #1,EB_TDNEST(a6)
        rts
exec_Permit:
        subq.b  #1,EB_TDNEST(a6)
        rts
exec_Disable:
        addq.b  #1,EB_IDNEST(a6)
        move.w  #$4000,INTENA        ; clear INTEN (bit14)
        rts
exec_Enable:
        subq.b  #1,EB_IDNEST(a6)
        bge.s   .nest
        move.w  #$C000,INTENA        ; SET + INTEN
.nest:
        rts
