; src/exec/ports.s — exec.library : ports de messages, PARTIE NON BLOQUANTE (M2.4c).
;   AddPort/RemPort/FindPort : ports publics dans ExecBase.PortList.
;   PutMsg   : AddTail du message + Signal de la tâche cible (si PA_SIGNAL).
;   GetMsg   : RemHead du 1er message (FIFO) ou NULL.
;   ReplyMsg : renvoie le message à son MN_REPLYPORT, type NT_REPLYMSG.
; DIFFÉRÉ À M3 : WaitPort (bloquant) -> _unimpl.
; « Vert » ici = file de messages manipulée correctement, pas de concurrence réelle.
; Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : includes NDK exec/ports.i (ABI publique).
; Le caller initialise MP_MSGLIST (NEWLIST) et MP_FLAGS/MP_SIGBIT/MP_SIGTASK
; avant AddPort (contrat V34 ; CreateMsgPort n'existe qu'en V36+).

                include "exec.i"

                xdef    exec_AddPort
                xdef    exec_RemPort
                xdef    exec_FindPort
                xdef    exec_PutMsg
                xdef    exec_GetMsg
                xdef    exec_ReplyMsg

; AddPort(port a1) : type NT_MSGPORT puis Enqueue dans PortList (ordre de priorité).
exec_AddPort:
        move.b  #NT_MSGPORT,LN_TYPE(a1)
        lea     EB_PORTLIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        rts

; RemPort(port a1) : retire de PortList.
exec_RemPort:
        jsr     LVO_REMOVE(a6)
        rts

; FindPort(name a1) -> d0 = port | 0 (recherche dans PortList).
exec_FindPort:
        lea     EB_PORTLIST(a6),a0
        jsr     LVO_FINDNAME(a6)
        rts

; PutMsg(port a0, message a1) : chaîne le message puis signale la tâche (PA_SIGNAL).
exec_PutMsg:
        move.l  a2,-(sp)
        move.l  a0,a2                ; a2 = port
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        lea     MP_MSGLIST(a2),a0    ; AddTail(&port->MsgList, msg)
        jsr     LVO_ADDTAIL(a6)
        moveq   #0,d0
        move.b  MP_FLAGS(a2),d0
        and.b   #PF_ACTION,d0
        bne.s   .pm_done             ; action != PA_SIGNAL -> pas de signal
        move.l  MP_SIGTASK(a2),d0
        beq.s   .pm_done             ; aucune tâche cible
        move.l  d0,a1                ; a1 = tâche à signaler
        moveq   #0,d0
        move.b  MP_SIGBIT(a2),d0
        moveq   #1,d1
        lsl.l   d0,d1                ; 1 << MP_SIGBIT
        move.l  d1,d0
        jsr     LVO_SIGNAL(a6)       ; Signal(task a1, sigmask d0)
.pm_done:
        move.l  (sp)+,a2
        rts

; GetMsg(port a0) -> d0 = message | 0 (RemHead de la file, FIFO).
exec_GetMsg:
        lea     MP_MSGLIST(a0),a0
        jsr     LVO_REMHEAD(a6)
        rts

; ReplyMsg(message a1) : renvoie au MN_REPLYPORT (si présent), type NT_REPLYMSG.
exec_ReplyMsg:
        move.l  a2,-(sp)
        move.l  a1,a2                ; a2 = message (PutMsg clobbe a1 scratch)
        move.l  MN_REPLYPORT(a1),d0
        beq.s   .rm_mark             ; pas de reply port -> juste marquer
        move.l  d0,a0                ; a0 = reply port
        jsr     LVO_PUTMSG(a6)       ; AddTail + signal (met NT_MESSAGE)
.rm_mark:
        move.b  #NT_REPLYMSG,LN_TYPE(a2)   ; écrase -> type « répondu »
        move.l  (sp)+,a2
        rts
