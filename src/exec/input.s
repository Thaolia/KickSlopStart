; src/exec/input.s — input.device (#2) : device résident gérant la CHAÎNE DE HANDLERS d'InputEvents.
;
; ABI publique (devices/input.i + devices/inputevent.i). ROMTag RTF_AUTOINIT NT_DEVICE pri 40 -> MakeLibrary
; (chemin AUTOINIT) crée la base, Enqueue dans EB_DEVICELIST. BeginIO dispatche par io_Command :
;   IND_ADDHANDLER / IND_REMHANDLER : Enqueue / Remove le struct Interrupt du handler (io_Data) dans la chaîne,
;     triée par LN_PRI décroissant (tête = plus haute priorité) — même mécanique qu'AddIntServer.
;   IND_WRITEEVENT : parcourt la chaîne ; chaque handler reçoit a0 = liste d'InputEvents, a1 = is_Data,
;     a5 = is_Code, et REND en d0 la liste (éventuellement modifiée) passée au handler suivant.
; IND_WRITEEVENT est le point d'injection PUBLIC de première classe (Intuition s'en sert pour injecter des
; events). Le câblage clavier LIVE -> input.device -> console sera fait en #3 (console.device réel), où
; console.device est le consommateur naturel d'IND_ADDHANDLER. Synchrone (pas de ReplyMsg : l'appelant lit
; io_Error directement, comme trackdisk). Déviation #2 : pas d'input.task ni d'ouverture keyboard/gameport
; (la chaîne tourne dans le contexte de l'appelant d'IND_WRITEEVENT) — fidèle côté ABI handler-chain.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs input.device + includes NDK publics. AUCUNE lecture ROM.

                include "exec.i"

                xref    newlist          ; lists.s (NEWLIST de la chaîne de handlers)

IO_DATA2        EQU 40               ; IOStdReq : io_Data (APTR) — défini localement (évite d'inclure disk.i)
ID_HANDLERS     EQU LIB_SIZE         ; base input.device : struct List (chaîne des handlers) après le nœud Library
INPUT_SIZE      EQU LIB_SIZE+14      ; Library + 1 struct List

; --- ROMTag input.device (scanné par build_reslist) ---
                EVEN
input_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    input_romtag         ; RT_MATCHTAG = self
        dc.l    input_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,40  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (40 : place roadmap input)
        dc.l    input_name           ; RT_NAME
        dc.l    input_name           ; RT_IDSTRING
        dc.l    input_inittab        ; RT_INIT -> table AUTOINIT
input_name:
        dc.b    "input.device",0
        EVEN
input_inittab:
        dc.l    INPUT_SIZE           ; dataSize
        dc.l    input_vectors        ; funcTable
        dc.l    input_datatab        ; dataTable (InitStruct)
        dc.l    input_initfunc       ; initFunc
input_vectors:                       ; table ABSOLUE, terminée par -1 (ordre device standard)
        dc.l    input_open           ; LVO -6
        dc.l    input_close          ; LVO -12
        dc.l    input_expunge        ; LVO -18
        dc.l    input_null           ; LVO -24 (réservé)
        dc.l    input_beginio        ; LVO -30
        dc.l    input_abortio        ; LVO -36
        dc.l    -1
input_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)   ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(device a6, ioreq a1, unit d0, flags d1) : incrémente le compte d'ouverture.
input_open:
        addq.w  #1,LIB_OPENCNT(a6)
        rts
input_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
input_expunge:
        moveq   #0,d0                ; base résidente : pas d'expunge
        rts
input_null:
        moveq   #0,d0
        rts
input_abortio:
        moveq   #0,d0
        rts

; input_beginio(device a6, ioreq a1) : dispatch par io_Command. Synchrone. a6 ressort = base device (conv.
; BeginIO : l'appelant recharge SysBase s'il en a besoin). Préserve a2-a5 ; clobbe d0/d1/a0/a1.
input_beginio:
        movem.l a2-a5,-(sp)
        move.l  a6,a2                ; a2 = base device
        move.l  a1,a3                ; a3 = ioreq
        move.l  ($4).w,a6            ; a6 = SysBase (pour Enqueue/Remove)
        clr.b   IO_ERROR(a3)
        move.w  IO_COMMAND(a3),d0
        cmp.w   #IND_ADDHANDLER,d0
        beq.s   .bi_add
        cmp.w   #IND_REMHANDLER,d0
        beq.s   .bi_rem
        cmp.w   #IND_WRITEEVENT,d0
        beq.s   .bi_write
        move.b  #IOERR_NOCMD,IO_ERROR(a3)   ; commande non reconnue
        bra.s   .bi_done
.bi_add:
        lea     ID_HANDLERS(a2),a0   ; chaîne de handlers
        move.l  IO_DATA2(a3),a1      ; a1 = &struct Interrupt du handler
        jsr     LVO_ENQUEUE(a6)      ; insère trié par LN_PRI (tête = plus haute pri)
        bra.s   .bi_done
.bi_rem:
        move.l  IO_DATA2(a3),a1
        jsr     LVO_REMOVE(a6)       ; Remove(node a1)
        bra.s   .bi_done
.bi_write:
                ifne    INPUT_NO_PROPAGATE
        bra.s   .bi_done             ; RED INPUT_NO_PROPAGATE : NE parcourt PAS la chaîne -> aucun handler appelé
                endc
        move.l  IO_DATA2(a3),a0      ; a0 = liste d'InputEvents (passée au 1er handler)
        lea     ID_HANDLERS(a2),a1
        move.l  (a1),a4              ; a4 = lh_Head (1er handler ou sentinelle tail)
.bi_wloop:
        move.l  (a4),d0              ; d0 = a4->Succ ; 0 => a4 = sentinelle tail -> fin
        beq.s   .bi_done
        move.l  d0,-(sp)             ; sauve Succ (robuste si un handler modifie la chaîne)
        move.l  IS_DATA(a4),a1       ; a1 = is_Data
        move.l  IS_CODE(a4),a5       ; a5 = is_Code
        jsr     (a5)                 ; handler(a0 = events, a1 = data) -> d0 = liste pour le suivant
        move.l  d0,a0                ; résultat = entrée du handler suivant
        move.l  (sp)+,a4             ; a4 = Succ (avance)
        bra.s   .bi_wloop
.bi_done:
        move.l  a2,a6                ; a6 = base device (convention BeginIO)
        movem.l (sp)+,a2-a5
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Pose le nom (quirk V34), NEWLIST la chaîne de handlers.
input_initfunc:
        move.l  d0,a1
        lea     input_name(pc),a0
        move.l  a0,LN_NAME(a1)       ; pose le nom
        move.l  d0,-(sp)             ; sauve la base (newlist clobbe a0)
        lea     ID_HANDLERS(a1),a1   ; NEWLIST(chaîne de handlers)
        jsr     newlist
        move.l  (sp)+,d0             ; d0 = base (valeur de retour)
        rts

        EVEN
input_end:
