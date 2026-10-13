; src/exec/ports.s — exec.library : ports de messages, PARTIE NON BLOQUANTE (M2.4c).
;   AddPort/RemPort/FindPort : ports publics dans ExecBase.PortList.
;   PutMsg   : AddTail du message + Signal de la tâche cible (si PA_SIGNAL).
;   GetMsg   : RemHead du 1er message (FIFO) ou NULL.
;   ReplyMsg : renvoie le message à son MN_REPLYPORT, type NT_REPLYMSG.
;   WaitPort : M3d — BLOQUE jusqu'à ce qu'un message soit présent ; rend le 1er (sans le
;              retirer : c'est GetMsg qui le retire).
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
                xdef    exec_WaitPort

; M3c : AddPort/RemPort/PutMsg/GetMsg/ReplyMsg enveloppés en Forbid/Permit — la
; PortList et les files MP_MSGLIST sont partagées (émetteur vs propriétaire). Forbid
; (exclusion tâche-vs-tâche) suffit ce milestone : aucun service d'interruption n'y
; touche encore ; l'UPGRADE en Disable (protection interruption, pour les devices
; pilotés par IRQ) est différé à l'arrivée du code device + save/restore par-TCB du
; nesting. FindPort/FindName restent arbitrés par l'APPELANT (contrat exec V34).

; AddPort(port a1) : type NT_MSGPORT puis Enqueue dans PortList (ordre de priorité).
exec_AddPort:
        move.b  #NT_MSGPORT,LN_TYPE(a1)
        jsr     LVO_FORBID(a6)
        lea     EB_PORTLIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        jsr     LVO_PERMIT(a6)
        rts

; RemPort(port a1) : retire de PortList.
exec_RemPort:
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jsr     LVO_PERMIT(a6)
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
        jsr     LVO_FORBID(a6)       ; {chaînage + signal} atomique vs le propriétaire
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
        jsr     LVO_PERMIT(a6)       ; sortie unique
        move.l  (sp)+,a2
        rts

; GetMsg(port a0) -> d0 = message | 0 (RemHead de la file, FIFO).
exec_GetMsg:
        jsr     LVO_FORBID(a6)
        lea     MP_MSGLIST(a0),a0
        jsr     LVO_REMHEAD(a6)      ; d0 = message | 0
        jsr     LVO_PERMIT(a6)       ; préserve d0
        rts

; ReplyMsg(message a1) : renvoie au MN_REPLYPORT (si présent), type NT_REPLYMSG.
exec_ReplyMsg:
        move.l  a2,-(sp)
        move.l  a1,a2                ; a2 = message (PutMsg clobbe a1 scratch)
        jsr     LVO_FORBID(a6)       ; {renvoi + marquage} atomique : le propriétaire ne
                                     ; doit pas GetMsg le message avant son type NT_REPLYMSG
        move.l  MN_REPLYPORT(a1),d0
        beq.s   .rm_mark             ; pas de reply port -> juste marquer
        move.l  d0,a0                ; a0 = reply port
        jsr     LVO_PUTMSG(a6)       ; AddTail + signal (PutMsg imbrique Forbid/Permit)
.rm_mark:
        move.b  #NT_REPLYMSG,LN_TYPE(a2)   ; écrase -> type « répondu »
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a2
        rts

; WaitPort(port a0) -> d0 = 1er message (lh_Head), SANS le retirer. Bloque tant que la
; file est vide, via Wait(1<<MP_SIGBIT). Pas de lost-wakeup : PutMsg fait AddTail AVANT
; Signal, et le recheck SIGRECVD de Wait est atomique (IPL 7) -> un message arrivé juste
; avant/pendant le Wait est soit vu par le test de file, soit par le bit déjà posé (Wait
; rend immédiatement), puis la boucle relit la file. a2 préservé à travers Wait (sauvé/
; restauré dans la frame de blocage, intouché sur le fast-path).
exec_WaitPort:
        move.l  a2,-(sp)
        move.l  a0,a2                ; a2 = port (survit à Wait)
.wp_loop:
        move.l  MP_MSGLIST(a2),a0    ; lh_Head de la file du port
        tst.l   (a0)                 ; (lh_Head)==0 <=> file vide
        bne.s   .wp_has              ; non vide -> au moins un message
        moveq   #0,d0                ; file vide -> Wait sur le bit du port
        move.b  MP_SIGBIT(a2),d0
        moveq   #1,d1
        lsl.l   d0,d1                ; 1 << MP_SIGBIT
        move.l  d1,d0
        jsr     LVO_WAIT(a6)
        bra.s   .wp_loop
.wp_has:
        move.l  MP_MSGLIST(a2),d0    ; d0 = lh_Head = 1er message (non retiré)
        move.l  (sp)+,a2
        rts
