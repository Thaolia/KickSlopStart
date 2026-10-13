; src/exec/interrupts.s — exec.library : plomberie d'interruptions + ordonnanceur
; préemptif minimal (M3a plomberie + M3b switch round-robin, tâches SUPERVISEUR).
;   init_ints   : installe l'autovecteur 68000 niveau 3 (VBlank), active VERTB +
;                 le maître INTEN, abaisse le masque IPL -> les interruptions passent.
;   vbl_handler : point de préemption. SCHED_ON=0 -> compte juste VBL_COUNT (M3a).
;                 SCHED_ON=1 -> switch round-robin, SAUF si Forbid()/Disable() actif
;                 (M3c : EB_TDNEST/EB_IDNEST >= 0 -> switch déféré au prochain VBlank).
; Tâches en SUPERVISEUR : leur pile EST la pile superviseur, donc la frame {SR,PC}
; poussée par le CPU est déjà sur la pile de la tâche -> le switch est un simple
; échange de SP (pas de jonglage USP/SSP ; user-mode différé). Au IPL 3 : pas de
; ré-entrée mid-switch. À VENIR : dispatcher par niveau (décodage INTREQR),
; IntVects/SetIntVector/AddIntServer, quantum TQE, priorité réelle.
; M3d : exec_Wait = switch SYNCHRONE depuis une tâche (blocage). M3e : reschedule =
; yield synchrone SANS blocage (yield-sur-Permit : requeue la courante, bascule sur la
; réveillée prioritaire). Leurs frames de reprise sont le MIROIR EXACT de celle que
; vbl_handler sauve/restaure -> les trois chemins de dispatch (préemptif + Wait +
; reschedule) partagent le format ET la queue de switch commune (dispatch_head).
; Piste IMPLÉMENTATION (« clean ») : hardware/intbits.i (ABI publique) + HRM.

                include "exec.i"

                xdef    init_ints
                xdef    exec_Wait
                xdef    reschedule

; init_ints : arme l'interruption VBlank. a6 = SysBase. Clobbers d0/a0.
init_ints:
        lea     VBL_COUNT,a0
        clr.l   (a0)                              ; compteur à zéro
        clr.b   SCHED_ON                          ; ordonnanceur désarmé (count-only)
        move.l  #vbl_handler,AUTOVEC_L3           ; autovecteur niveau 3 -> handler
        move.w  #INTF_VERTB,INTREQ                ; efface un VERTB pendant
        move.w  #(INTF_SETCLR|INTF_INTEN|INTF_VERTB),INTENA   ; active VERTB + maître
        move.w  #$2000,sr                         ; superviseur, IPL=0 -> VERTB passe
        rts

; vbl_handler : interruption VBlank (niveau 3) = point de préemption.
vbl_handler:
        movem.l d0-d7/a0-a6,-(sp)   ; sauve les GPR (sous la frame {SR,PC} du CPU)
        move.l  ($4).w,a6           ; a6 = SysBase
        move.w  #INTF_VERTB,INTREQ  ; acquitte VERTB
        lea     VBL_COUNT,a0
        addq.l  #1,(a0)             ; compteur (preuve M3a conservée)
        tst.b   SCHED_ON
        beq.s   .vbl_ret            ; ordonnanceur non armé -> juste compter
        ; M3c : honore Forbid/Disable. TC_TDNESTCNT/IDNESTCNT sont GLOBAUX (ExecBase),
        ; pas par-TCB (le switch ne sauve/restaure que SP) ; comme une tâche interdite
        ; n'est jamais commutée, EB_TDNEST reflète toujours l'état de la tâche courante.
        ; -1 = permis (négatif -> bge non pris -> on switche) ; 0/+ = interdit -> on défère.
        tst.b   EB_TDNEST(a6)       ; Forbid() actif ?
        bge.s   .vbl_ret            ; oui -> pas de switch (repris au prochain VBlank)
        tst.b   EB_IDNEST(a6)       ; Disable() actif ? (ferme la fenêtre addq/INTENA de Disable)
        bge.s   .vbl_ret
        move.l  EB_TASKREADY(a6),a0 ; lh_Head de TaskReady
        move.l  (a0),d0             ; head->Succ ; 0 => liste vide
        beq.s   .vbl_ret            ; aucune autre tâche prête -> pas de switch
        move.l  EB_THISTASK(a6),a1  ; tâche sortante
        move.l  sp,TC_SPREG(a1)     ; sauve son contexte (= son SP courant)
        move.b  #TS_READY,TC_STATE(a1)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)     ; round-robin : requeue la sortante (FIFO à pri égale)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)     ; d0 = tâche entrante
        move.l  d0,a1
        move.l  a1,EB_THISTASK(a6)
        move.b  #TS_RUN,TC_STATE(a1)
        move.l  TC_SPREG(a1),sp     ; bascule sur la pile de l'entrante
.vbl_ret:
        movem.l (sp)+,d0-d7/a0-a6   ; restaure les GPR (entrante, ou courante si no-switch)
        rte                         ; dépile {SR,PC} de l'entrante

; Wait(signalSet d0.l) -> d0 = signaux reçus ayant provoqué le réveil.
; Bloque ThisTask jusqu'à réception d'au moins un bit de signalSet. C'est un switch
; VOLONTAIRE : la tâche ne peut pas continuer, on doit donc commuter IMMÉDIATEMENT
; (pas « au prochain VBlank »). La frame de reprise posée ici = miroir exact de
; vbl_handler : [d0-d7/a0-a6 (60 o)][SR word][PC long]. Au réveil, le dispatcher
; (vbl_handler OU un autre Wait) restaure via le MÊME movem+rte -> on reprend en
; .wa_resume. Le retour de l'appelant (empilé par jsr avant l'appel) joue le rôle du
; finalPC de AddTask (pas besoin de le reposer). IPL 7 autour de la surgery =
; atomicité vs VBlank. Hypothèse V34 : appel hors Forbid/Disable (Wait les romprait) ;
; on revient à IPL 0 (toutes les tâches tournent IPL 0 superviseur ce jalon).
exec_Wait:
        move.w  #$2700,sr           ; IPL 7 : section scheduler atomique vs VBlank
        move.l  EB_THISTASK(a6),a1
        move.l  d0,TC_SIGWAIT(a1)   ; mémorise les signaux attendus
.wa_check:
        move.l  TC_SIGRECVD(a1),d0
        and.l   TC_SIGWAIT(a1),d0
        bne.s   .wa_got             ; un signal attendu est déjà présent -> pas de blocage
        move.l  EB_TASKREADY(a6),a0 ; une autre tâche est-elle prête ?
        tst.l   (a0)                ; (lh_Head)==0 <=> TaskReady vide
        beq.s   .wa_idle            ; personne d'autre -> idle-spin (dégénéré, documenté)
        pea     .wa_resume(pc)      ; --- blocage : frame miroir dispatcher ---
        move.w  #$2000,-(sp)        ; SR de reprise (superviseur, IPL 0)
        movem.l d0-d7/a0-a6,-(sp)   ; GPR (comme vbl_handler)
        move.l  sp,TC_SPREG(a1)     ; contexte sauvé
        move.b  #TS_WAIT,TC_STATE(a1)
        lea     EB_TASKWAIT(a6),a0
        jsr     LVO_ADDTAIL(a6)     ; ThisTask (a1) -> TaskWait (a1 préservé)
        bra     dispatch_head       ; tail commun (RemHead TaskReady + bascule sur la tête)
.wa_resume:                         ; re-planifiée ici : GPR/a6 restaurés, SR=$2000
        move.w  #$2700,sr
        move.l  EB_THISTASK(a6),a1
        bra.s   .wa_check           ; re-teste (robuste à un réveil spurious -> re-bloque)
.wa_got:
        eor.l   d0,TC_SIGRECVD(a1)  ; efface les bits qui réveillent (d0 ⊆ SIGRECVD)
        clr.l   TC_SIGWAIT(a1)
        move.w  #$2000,sr           ; ré-autorise les interruptions
        rts
.wa_idle:                           ; aucune tâche prête : attendre un Signal d'IRQ
        move.w  #$2000,sr           ; fenêtre IPL 0 -> une interruption peut Signal
        nop
        move.w  #$2700,sr
        bra.s   .wa_check

; dispatch_head : TAIL COMMUN des switchs volontaires (Wait, reschedule). Bascule sur la
; TÊTE de TaskReady (la plus haute priorité). L'appelant a déjà rangé la tâche sortante
; (TaskWait pour Wait, TaskReady pour reschedule) et sauvé sa frame dans TC_SPREG.
; TaskReady NON vide garanti par l'appelant. a6 = SysBase, IPL 7.
dispatch_head:
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)     ; d0 = entrante
        move.l  d0,a1
        move.l  a1,EB_THISTASK(a6)
        move.b  #TS_RUN,TC_STATE(a1)
        move.l  TC_SPREG(a1),sp     ; bascule sur la pile de l'entrante
        movem.l (sp)+,d0-d7/a0-a6
        rte                         ; -> entrante (reprend SA frame)

; reschedule : YIELD synchrone volontaire SANS blocage (= yield-sur-Permit, M3e). Requeue
; la tâche courante dans TaskReady (round-robin par priorité) et bascule sur la tête (donc
; la tâche réveillée prioritaire qui a posé AttnResched). Appelé par Permit/Enable quand
; AttnResched est posé ET le nesting déverrouillé. Frame de reprise = miroir dispatcher
; (comme Wait) ; au retour en .rs_resume, rts vers l'appelant (Permit/Enable) une fois la
; tâche re-dispatchée. Fonctionne indépendamment de SCHED_ON (switch direct, pas d'IRQ).
reschedule:
        move.w  #$2700,sr           ; IPL 7 : atomique vs VBlank
        move.l  EB_TASKREADY(a6),a0
        tst.l   (a0)                ; TaskReady vide ? (défensif : AttnResched sans prête)
        beq.s   .rs_none
        clr.w   EB_ATTNRESCHED(a6)  ; demande consommée
        move.l  EB_THISTASK(a6),a1
        pea     .rs_resume(pc)      ; frame miroir dispatcher (PC de reprise)
        move.w  #$2000,-(sp)        ; SR de reprise (superviseur, IPL 0)
        movem.l d0-d7/a0-a6,-(sp)
        move.l  sp,TC_SPREG(a1)
        move.b  #TS_READY,TC_STATE(a1)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)     ; requeue la courante par priorité (a1 préservé)
        bra     dispatch_head       ; -> la tête (réveillée prioritaire)
.rs_none:                           ; rien à réveiller -> on reste courante
        clr.w   EB_ATTNRESCHED(a6)
        move.w  #$2000,sr
        rts
.rs_resume:                         ; re-dispatchée : GPR/a6 restaurés, SR=$2000 -> retour Permit
        rts
