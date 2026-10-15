; src/exec/tasks.s — exec.library : tâches + signaux, PARTIE NON BLOQUANTE (M2.4b).
;   init_task   : crée le TCB « boot task » (ThisTask) depuis le tas.
;   FindTask    : NULL -> tâche courante ; sinon recherche dans TaskReady/TaskWait.
;   AllocSignal/FreeSignal/SetSignal : gestion des bits de signaux de ThisTask.
;   Signal      : pose les bits dans TC_SIGRECVD + RÉVEILLE la tâche si TS_WAIT (M3d) +
;                 demande un reschedule si la réveillée est prioritaire (M3e, AttnResched).
;   SetTaskPri  : change LN_PRI, retourne l'ancienne.
; M3b : AddTask (contexte initial + TaskReady). M3d : réveil-sur-Signal (ici) + Wait/
;   WaitPort (interrupts.s / ports.s). DIFFÉRÉ : RemTask, dispatch explicite
;   (Switch/Dispatch/Cause), re-Enqueue de SetTaskPri, yield immédiat sur Permit.
; Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : includes NDK exec/tasks.i (ABI publique).

                include "exec.i"

                xdef    init_task
                xdef    exec_AddTask
                xdef    exec_RemTask
                xdef    exec_FindTask
                xdef    exec_AllocSignal
                xdef    exec_FreeSignal
                xdef    exec_SetSignal
                xdef    exec_Signal
                xdef    exec_SetTaskPri

                xref    raw_enable       ; library.s (M7c : Signal = section critique NUE)

; init_task : alloue le TCB de la tâche de boot et le publie dans ThisTask.
; Appelé par coldstart APRÈS init_memory (AllocMem dispo) et AVANT selftest
; (sinon AllocSignal déréférencerait un ThisTask NULL -> écriture dans les
; vecteurs d'exception $0-$3FF). a6 = SysBase.
init_task:
        move.l  #TC_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a0                ; TCB (supposé non-NULL au boot)
        move.b  #NT_TASK,LN_TYPE(a0)
        move.b  #0,LN_PRI(a0)
        move.l  #task_name,LN_NAME(a0)
        move.b  #TS_RUN,TC_STATE(a0)
        move.b  #-1,TC_IDNESTCNT(a0) ; copies par-tâche (save/restore au switch M3)
        move.b  #-1,TC_TDNESTCNT(a0)
        move.l  #SYS_SIGALLOC,TC_SIGALLOC(a0)
        move.l  #FTEST_HI,TC_SPLOWER(a0)   ; bornes pile superviseur (informatif)
        move.l  #STACKTOP,TC_SPUPPER(a0)
        move.l  a0,EB_THISTASK(a6)
        rts

; AddTask(task a1, initialPC a2, finalPC a3) : prépare le contexte initial et met la tâche dans
; TaskReady. M7c : tâches USER-MODE (SR initial $0000, bit S = 0) sur leur pile user. Le contexte
; posé sur la pile de la tâche = MIROIR EXACT de ce que dispatch/dispatch_in relocalisent :
; [d0-d7/a0-a6 = 0 (60 o)][SR=$0000 (word)][PC=initialPC (long)][finalPC (long)]. TC_SPREG -> les GPR ;
; USP à la 1re entrée = TC_SPREG+FRAME_SIZE -> pointe sur finalPC (retour si la tâche fait RTS).
; Nesting PAR-TÂCHE initialisé à -1 (permis & enabled) — SANS ça MEMF_CLEAR laisserait 0 = Disabled/
; Forbidden au réveil (latent avant M7c car le scheduler lisait le nesting GLOBAL). Caller : SPLOWER/UPPER.
exec_AddTask:
        move.b  #NT_TASK,LN_TYPE(a1)
        move.b  #TS_READY,TC_STATE(a1)
        move.b  #-1,TC_IDNESTCNT(a1) ; nesting par-tâche : enabled
        move.b  #-1,TC_TDNESTCNT(a1) ; permis
        move.l  TC_SPUPPER(a1),a0    ; haut de pile user de la tâche
        move.l  a3,-(a0)             ; finalPC (retour si la tâche fait RTS)
        move.l  a2,-(a0)             ; PC initial
        move.w  #$0000,-(a0)         ; SR initial = USER mode, IPL0 (bit S = 0)
        moveq   #14,d0
.at_zero:
        clr.l   -(a0)                ; 15 longs GPR = 0
        dbf     d0,.at_zero
        move.l  a0,TC_SPREG(a1)      ; contexte -> GPR
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)      ; Enqueue(TaskReady, task)
        rts

; RemTask(task a1) : retire une tâche et libère sa pile (TC_SPLOWER..TC_SPUPPER) + son TCB (TC_SIZE).
; a1 = 0 ou ThisTask -> SELF : passe en superviseur via trap #2 (libère sur la SSP puis bascule sur la
; tâche suivante, NE REVIENT PAS). Sinon NON-SELF (tâche ready/waiting) : Remove de sa liste + FreeMem,
; en contexte tâche. FreeMem utilise Forbid/Permit (Permit yield) -> on l'enveloppe dans un Forbid EXTERNE
; (le Permit interne voit TDNEST>=0 -> pas de yield) + Disable (atomique vs une IRQ touchant les listes).
; tc_MemEntry non géré (aucune tâche démo n'en alloue) -> hors scope M7j.
exec_RemTask:
        move.l  a1,d0
        bne.s   .rt_chk
        move.l  EB_THISTASK(a6),a1   ; NULL -> self
.rt_chk:
        cmp.l   EB_THISTASK(a6),a1
        beq.s   .rt_self
        ; --- NON-SELF : la cible n'est pas courante (sur TaskReady ou TaskWait) ---
        movem.l d4-d6,-(sp)
        move.l  TC_SPLOWER(a1),d4    ; bornes pile AVANT tout free
        move.l  TC_SPUPPER(a1),d5
        sub.l   d4,d5                ; d5 = taille pile
        move.l  a1,d6                ; d6 = TCB
        jsr     LVO_FORBID(a6)       ; Forbid externe -> suppr. yield du Permit interne de FreeMem
        addq.b  #1,EB_IDNEST(a6)     ; Disable -> Remove atomique vs une IRQ (Signal) touchant les listes
        move.w  #INTF_INTEN,INTENA
        move.l  d6,a1                ; Remove(a1) de sa liste (SUCC/PRED du noeud -> liste quelconque)
        jsr     LVO_REMOVE(a6)
                ifeq    M7J_NOFREE
        move.l  d4,a1                ; FreeMem(pile)
        move.l  d5,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d6,a1                ; FreeMem(TCB)
        move.l  #TC_SIZE,d0
        jsr     LVO_FREEMEM(a6)
                endc
        bsr     raw_enable           ; INTEN on (sortie nue, pas de queue reschedule)
        jsr     LVO_PERMIT(a6)       ; fin du Forbid externe (yield ici OK : contexte tâche, après RemTask)
        movem.l (sp)+,d4-d6
        rts
.rt_self:
        trap    #2                   ; -> trap2_handler (superviseur : libère + bascule, NE REVIENT PAS)
        rts                          ; filet (jamais atteint)

; FindTask(name a1) -> d0 = task | 0 ; a1 == NULL -> tâche courante
exec_FindTask:
        move.l  a1,d0
        bne.s   .ft_named
        move.l  EB_THISTASK(a6),d0
        rts
.ft_named:
        move.l  a2,-(sp)
        move.l  a1,a2                ; conserve le nom (FindName clobbe a1)
        lea     EB_TASKREADY(a6),a0
        move.l  a2,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.s   .ft_done
        lea     EB_TASKWAIT(a6),a0
        move.l  a2,a1
        jsr     LVO_FINDNAME(a6)
.ft_done:
        move.l  (sp)+,a2
        rts

; AllocSignal(signum d0.l) -> d0 = n° de bit alloué | -1
; signum == -1 : alloue le plus petit bit libre ; sinon alloue ce bit précis.
; Le bit alloué est effacé dans SIGWAIT/SIGRECVD/SIGEXCEPT (départ propre).
exec_AllocSignal:
        move.l  d2,-(sp)
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGALLOC(a0),d1   ; masque des bits alloués
        tst.l   d0
        bpl.s   .as_spec             ; bit précis demandé
        moveq   #0,d0                ; cherche le plus petit bit libre
.as_scan:
        btst    d0,d1
        beq.s   .as_got
        addq.l  #1,d0
        cmp.l   #32,d0
        bne.s   .as_scan
        moveq   #-1,d0               ; aucun libre
        move.l  (sp)+,d2
        rts
.as_spec:
        btst    d0,d1
        bne.s   .as_fail             ; déjà alloué
.as_got:
        bset    d0,d1
        move.l  d1,TC_SIGALLOC(a0)
        moveq   #1,d2
        lsl.l   d0,d2                ; masque = 1<<bit
        not.l   d2
        and.l   d2,TC_SIGWAIT(a0)
        and.l   d2,TC_SIGRECVD(a0)
        and.l   d2,TC_SIGEXCEPT(a0)
        move.l  (sp)+,d2
        rts
.as_fail:
        moveq   #-1,d0
        move.l  (sp)+,d2
        rts

; FreeSignal(signum d0)
exec_FreeSignal:
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGALLOC(a0),d1
        bclr    d0,d1
        move.l  d1,TC_SIGALLOC(a0)
        rts

; SetSignal(newSignals d0, signalSet d1) -> d0 = anciens TC_SIGRECVD
exec_SetSignal:
        move.l  d2,-(sp)
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGRECVD(a0),d2   ; anciens
        and.l   d1,d0                ; newSignals & mask
        not.l   d1                   ; ~mask
        and.l   d2,d1                ; old & ~mask
        or.l    d1,d0                ; new = (old&~mask) | (newSignals&mask)
        move.l  d0,TC_SIGRECVD(a0)
        move.l  d2,d0                ; retourne les anciens
        move.l  (sp)+,d2
        rts

; Signal(task a1, signalSet d0) : pose les bits dans TC_SIGRECVD de la tâche ; si elle est bloquée
; (TS_WAIT) sur l'un de ces bits, la réveille (TaskWait -> TaskReady).
; M7c : appelée depuis une tâche USER-MODE OU depuis une interruption (service timer). L'atomicité
; vs le scheduler passe par une SECTION CRITIQUE NUE : Disable nu à l'entrée (INTENA, user-safe),
; raw_enable à la sortie — PAS exec_Enable, dont la queue déclencherait reschedule->trap en contexte
; IRQ (ré-entrance du scheduler, cf. ledger M7c). Signal ne switche jamais : il POSE AttnResched (si
; la réveillée est prioritaire), consommé par le prochain Permit/Enable (yield) ou tick VBlank.
; Remove/Enqueue préservent a1. La réveillée part en TaskReady (modèle « défère »).
exec_Signal:
        addq.b  #1,EB_IDNEST(a6)     ; Disable NU (section critique vs scheduler)
        move.w  #INTF_INTEN,INTENA   ; INTEN off (bit14)
        or.l    d0,TC_SIGRECVD(a1)
        cmp.b   #TS_WAIT,TC_STATE(a1)
        bne.s   .sig_done            ; pas en attente -> juste poser les bits
        move.l  TC_SIGRECVD(a1),d0
        and.l   TC_SIGWAIT(a1),d0
        beq.s   .sig_done            ; en attente, mais pas sur ces bits-là
        move.b  #TS_READY,TC_STATE(a1)
        jsr     LVO_REMOVE(a6)       ; retire la cible (a1) de TaskWait
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)      ; insère la cible (a1) dans TaskReady (par priorité)
        ; M3e : si la réveillée est PLUS prioritaire que la courante, demander un reschedule différé.
        move.l  EB_THISTASK(a6),a0
        move.b  LN_PRI(a1),d0        ; priorité de la réveillée (octet signé)
        cmp.b   LN_PRI(a0),d0        ; réveillée - courante
        ble.s   .sig_done            ; réveillée <= courante -> pas de préemption
        move.w  #1,EB_ATTNRESCHED(a6)
.sig_done:
        bsr     raw_enable           ; sortie NUE (INTEN on si IDNest<0 ; pas de queue reschedule)
        rts

; SetTaskPri(task a1, pri d0.b) -> d0 = ancienne priorité (longword signé)
exec_SetTaskPri:
        moveq   #0,d1
        move.b  LN_PRI(a1),d1
        ext.w   d1
        ext.l   d1                   ; ancienne pri, signée
        move.b  d0,LN_PRI(a1)        ; nouvelle
        move.l  d1,d0
        ; M3 : re-Enqueue si la tâche est dans TaskReady (maintien de l'ordre). Différé.
        rts

task_name:
        dc.b    "exec.task",0
        EVEN
