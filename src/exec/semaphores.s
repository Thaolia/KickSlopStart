; src/exec/semaphores.s — sémaphores de signal d'exec (struct SignalSemaphore, exec/semaphores.h).
;
; ss_QueueCount compte les prises en cours moins un (-1 = libre) : chaque Obtain l'incrémente, chaque Release le
; décrémente. ss_NestCount compte les prises imbriquées du propriétaire. Un demandeur bloqué pose une
; SemaphoreRequest sur sa pile dans ss_WaitQueue et attend SIGF_SINGLE ; le Release qui libère le sémaphore le
; lui transmet directement (propriétaire et imbrication posés pour lui) avant de le signaler.
; Tout se fait sous Forbid : le réveil d'un demandeur n'a lieu qu'au Permit.
; ObtainSemaphoreList / ReleaseSemaphoreList / Procure / Vacate ne sont pas fournis (restent neutres).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs exec.library + exec/semaphores.h. AUCUNE lecture ROM.

                include "exec.i"

                xdef    exec_InitSemaphore
                xdef    exec_ObtainSemaphore
                xdef    exec_ReleaseSemaphore
                xdef    exec_AttemptSemaphore
                xdef    exec_AddSemaphore
                xdef    exec_RemSemaphore
                xdef    exec_FindSemaphore

SS_NESTCOUNT    EQU 14
SS_WAITQUEUE    EQU 16               ; struct MinList (12)
SS_OWNER        EQU 40
SS_QUEUECOUNT   EQU 44
SS_SIZE         EQU 46
SR_WAITER       EQU 8                ; struct SemaphoreRequest : MinNode + sr_Waiter
SR_SIZE         EQU 12
NT_SIGNALSEM    EQU 15
SIGF_SINGLE     EQU $10

; InitSemaphore(sigSem a0) : nœud et compteurs remis à zéro, file d'attente vide, libre. Le nom (ln_Name) et la
; priorité sont conservés (AddSemaphore les utilise).
exec_InitSemaphore:
        move.b  #NT_SIGNALSEM,LN_TYPE(a0)
        clr.w   SS_NESTCOUNT(a0)
        lea     SS_WAITQUEUE+4(a0),a1
        move.l  a1,SS_WAITQUEUE(a0)  ; mlh_Head = &mlh_Tail
        clr.l   (a1)+                ; mlh_Tail
        move.l  a0,(a1)
        add.l   #SS_WAITQUEUE,(a1)   ; mlh_TailPred = &mlh_Head
        lea     SS_WAITQUEUE+12(a0),a1
        clr.l   (a1)+                ; ss_MultipleLink (SemaphoreRequest, inutilisée)
        clr.l   (a1)+
        clr.l   (a1)+
        clr.l   SS_OWNER(a0)
        move.w  #-1,SS_QUEUECOUNT(a0)
        rts

; ObtainSemaphore(sigSem a0) : prise exclusive, imbriquable par son propriétaire ; bloque sinon.
exec_ObtainSemaphore:
        movem.l a2-a3,-(sp)
        move.l  a0,a2
        jsr     LVO_FORBID(a6)
        move.l  EB_THISTASK(a6),a3
        addq.w  #1,SS_QUEUECOUNT(a2)
        beq.s   .ob_take             ; était libre
        cmp.l   SS_OWNER(a2),a3
        beq.s   .ob_nest
        lea     -SR_SIZE(sp),sp      ; demande en file, transmise par le Release qui libère
        move.l  a3,SR_WAITER(sp)
        lea     SS_WAITQUEUE(a2),a0
        move.l  sp,a1
        jsr     LVO_ADDTAIL(a6)
        moveq   #0,d0
        moveq   #SIGF_SINGLE,d1
        jsr     LVO_SETSIGNAL(a6)    ; un SIGF_SINGLE resté posé ne doit pas réveiller l'attente
.ob_wait:
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_WAIT(a6)
        cmp.l   SS_OWNER(a2),a3
        bne.s   .ob_wait             ; signal d'une autre origine : toujours pas propriétaire
        lea     SR_SIZE(sp),sp
        bra.s   .ob_out
.ob_take:
        move.l  a3,SS_OWNER(a2)
.ob_nest:
        addq.w  #1,SS_NESTCOUNT(a2)
.ob_out:
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,a2-a3
        rts

; ReleaseSemaphore(sigSem a0) : défait une prise ; à la dernière, le premier demandeur en file devient propriétaire.
exec_ReleaseSemaphore:
        move.l  a2,-(sp)
        move.l  a0,a2
        jsr     LVO_FORBID(a6)
        subq.w  #1,SS_QUEUECOUNT(a2)
        subq.w  #1,SS_NESTCOUNT(a2)
        bne.s   .rl_out              ; encore tenu (imbrication)
        clr.l   SS_OWNER(a2)
        tst.w   SS_QUEUECOUNT(a2)
        bmi.s   .rl_out              ; personne n'attend
        lea     SS_WAITQUEUE(a2),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .rl_out
        move.l  d0,a0
        move.l  SR_WAITER(a0),a1
        move.l  a1,SS_OWNER(a2)
        move.w  #1,SS_NESTCOUNT(a2)
        moveq   #SIGF_SINGLE,d0
        jsr     LVO_SIGNAL(a6)
.rl_out:
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a2
        rts

; AttemptSemaphore(sigSem a0) -> d0 = 1 si pris (libre ou déjà à nous), 0 sinon ; ne bloque jamais.
exec_AttemptSemaphore:
        jsr     LVO_FORBID(a6)
        move.l  EB_THISTASK(a6),a1
        cmp.w   #-1,SS_QUEUECOUNT(a0)
        beq.s   .at_take
        cmp.l   SS_OWNER(a0),a1
        bne.s   .at_no
.at_take:
        addq.w  #1,SS_QUEUECOUNT(a0)
        addq.w  #1,SS_NESTCOUNT(a0)
        move.l  a1,SS_OWNER(a0)
        jsr     LVO_PERMIT(a6)
        moveq   #1,d0
        rts
.at_no:
        jsr     LVO_PERMIT(a6)
        moveq   #0,d0
        rts

; AddSemaphore(sigSem a1) : initialise puis publie dans ExecBase->SemaphoreList (triée par priorité).
exec_AddSemaphore:
        move.l  a1,-(sp)
        move.l  a1,a0
        bsr     exec_InitSemaphore
        jsr     LVO_FORBID(a6)
        move.l  (sp)+,a1
        lea     EB_SEMLIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        jmp     LVO_PERMIT(a6)

; RemSemaphore(sigSem a1) : retire de la liste publique.
exec_RemSemaphore:
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jmp     LVO_PERMIT(a6)

; FindSemaphore(name a1) -> d0 = sémaphore public de ce nom, ou 0.
exec_FindSemaphore:
        lea     EB_SEMLIST(a6),a0
        jmp     LVO_FINDNAME(a6)
