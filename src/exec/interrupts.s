; src/exec/interrupts.s — exec.library : plomberie d'interruptions + ordonnanceur
; préemptif minimal (M3a plomberie + M3b switch round-robin, tâches SUPERVISEUR).
;   init_ints   : installe l'autovecteur 68000 niveau 3 (VBlank), active VERTB +
;                 le maître INTEN, abaisse le masque IPL -> les interruptions passent.
;   vbl_handler : point de préemption. SCHED_ON=0 -> compte juste VBL_COUNT (M3a).
;                 SCHED_ON=1 -> switch round-robin, SAUF si Forbid()/Disable() actif
;                 (M3c : EB_TDNEST/EB_IDNEST >= 0 -> switch déféré au prochain VBlank).
; Tâches en SUPERVISEUR : leur pile EST la pile superviseur, donc la frame {SR,PC}
; poussée par le CPU est déjà sur la pile de la tâche -> le switch est un simple
; échange de SP (pas de jonglage USP/SSP ; user-mode différé). À VENIR : dispatcher
; par niveau (décodage INTREQR), IntVects/SetIntVector/AddIntServer, quantum TQE, priorité réelle.
; M7a (GATE DE RÉ-ENTRANCE) : vbl_handler (niveau 3) faisait sa chirurgie de listes du scheduler
; (Enqueue/RemHead TaskReady) à IPL3 -> une source de niveau > 3 (INT6/CIA-B, l'unité MICROHZ) pouvait
; la préempter et corrompre la liste via son propre exec_Signal. Fix : IPL7 autour de la SEULE section
; critique (requeue_and_dispatch -> dispatch_head), pas tout le handler (INT6 doit préempter le VBlank
; ailleurs). Détecteur VBL_INSURG/VBL_CLASH prouve l'invariant (cf. exec.i).
; M3d : exec_Wait = switch SYNCHRONE depuis une tâche (blocage). M3e : reschedule =
; yield synchrone SANS blocage (yield-sur-Permit : requeue la courante, bascule sur la
; réveillée prioritaire). M3f (recombinaison) : les TROIS chemins de dispatch (préemption
; périodique du handler + Wait + reschedule) partagent la même frame miroir ET les mêmes
; tails — dispatch_head (RemHead + bascule) et requeue_and_dispatch (requeue round-robin +
; efface AttnResched + dispatch_head), ce dernier partagé par le handler et reschedule. Le
; handler efface AttnResched à chaque switch -> un tick satisfait une demande de yield en
; attente, pas de reschedule redondant au Permit suivant ; reschedule re-teste AttnResched
; à IPL 7 (idempotent). Préemption et yield coexistent sans corruption.
; Piste IMPLÉMENTATION (« clean ») : hardware/intbits.i (ABI publique) + HRM.

                include "exec.i"

                xdef    init_ints
                xdef    exec_Wait
                xdef    reschedule

                xref    int2_handler     ; cia.s (autovecteur INT2 / CIA-A)
                xref    int6_handler     ; cia.s (autovecteur INT6 / CIA-B)

; init_ints : arme l'interruption VBlank. a6 = SysBase. Clobbers d0/a0.
init_ints:
        lea     VBL_COUNT,a0
        clr.l   (a0)                              ; compteur à zéro
        clr.b   SCHED_ON                          ; ordonnanceur désarmé (count-only)
        clr.l   VBL_SVC                           ; aucun service VBlank tant que timer non init
        clr.l   CIAA_PTR                          ; M6b : handlers CIA no-op tant que cia non créé
        clr.l   CIAB_PTR
        clr.l   CIA_FIRED
        clr.b   VBL_INSURG                        ; M7a : aucune chirurgie en cours au départ
        clr.l   VBL_CLASH                         ; M7a : compteur de clashs de ré-entrance
        move.l  #vbl_handler,AUTOVEC_L3           ; autovecteur niveau 3 -> handler VBlank
        move.l  #int2_handler,AUTOVEC_L2          ; M6b : INT2 (CIA-A / PORTS)
        move.l  #int6_handler,AUTOVEC_L6          ; M6b/M7a : INT6 (CIA-B / EXTER)
        move.w  #INTF_VERTB,INTREQ                ; efface un VERTB pendant
        ; active VERTB + PORTS (INT2) + maître. EXTER(INT6, niveau 6 > VBlank 3) est activé
        ; PLUS TARD, au bringup de l'unité MICROHZ (boot.s M7a) : il peut désormais préempter le
        ; VBlank sans danger car la chirurgie de listes de vbl_handler est IPL7 (gate M7a), mais on
        ; le laisse éteint tant qu'aucune source CIA-B n'existe -> M4..M6 restent inchangés.
        move.w  #(INTF_SETCLR|INTF_INTEN|INTF_VERTB|INTF_PORTS),INTENA
        move.w  #$2000,sr                         ; superviseur, IPL=0 -> les interruptions passent
        rts

; vbl_handler : interruption VBlank (niveau 3) = point de préemption.
vbl_handler:
        movem.l d0-d7/a0-a6,-(sp)   ; sauve les GPR (sous la frame {SR,PC} du CPU)
        move.l  ($4).w,a6           ; a6 = SysBase
        move.w  #INTF_VERTB,INTREQ  ; acquitte VERTB
        lea     VBL_COUNT,a0
        addq.l  #1,(a0)             ; compteur (preuve M3a conservée)
        move.l  VBL_SVC,d0          ; M6a : service timer VBLANK enregistré ?
        beq.s   .vbl_nosvc
        move.l  VBL_SVCDATA,a1
        move.l  d0,a0
        jsr     (a0)                ; service(a1=base device, a6=SysBase) ; transparent (a6 préservé)
.vbl_nosvc:
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
        move.l  sp,TC_SPREG(a1)     ; sauve son contexte (frame {SR,PC} du CPU + GPR)
        bra     requeue_and_dispatch ; M3f : tail commun (requeue sortante + efface AttnResched
                                    ; + bascule sur la tête), partagé avec reschedule
.vbl_ret:
        movem.l (sp)+,d0-d7/a0-a6   ; restaure les GPR (courante, pas de switch)
        rte                         ; dépile {SR,PC}

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

; requeue_and_dispatch : commit d'un switch ROUND-ROBIN (M3f). a1 = tâche sortante (sa frame
; est déjà dans TC_SPREG). Requeue la sortante dans TaskReady par priorité (FIFO à pri égale),
; efface AttnResched (un switch SATISFAIT toute demande de reschedule en attente -> pas de
; yield redondant au prochain Permit), puis tombe dans dispatch_head. Partagé par vbl_handler
; (préemption périodique) ET reschedule (yield-sur-Permit). a6 = SysBase, IPL >= 3.
requeue_and_dispatch:
        ; M7a — GATE DE RÉ-ENTRANCE : la chirurgie des listes du scheduler (Enqueue ici +
        ; RemHead dans dispatch_head) DOIT être atomique vs une interruption de niveau > 3.
        ; vbl_handler (niveau 3) y entrait à IPL3 ; INT6/CIA-B (niveau 6) pouvait donc le
        ; préempter en plein Enqueue(TaskReady) pendant que son propre exec_Signal faisait
        ; aussi Enqueue(TaskReady) sur la même liste à moitié mise à jour -> corruption. On
        ; monte à IPL7 pour la SEULE section critique (pas tout vbl_handler : INT6 doit pouvoir
        ; préempter le VBlank ailleurs). reschedule/exec_Wait y entrent déjà à IPL7 (idempotent).
        move.w  #$2700,sr
        move.b  #1,VBL_INSURG       ; fenêtre de chirurgie ouverte (détecteur de clash, cf. exec.i)
        move.b  #TS_READY,TC_STATE(a1)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)     ; round-robin : requeue la sortante (a1 préservé)
        clr.w   EB_ATTNRESCHED(a6)  ; un switch satisfait toute demande de reschedule
        ; tombe dans dispatch_head

; dispatch_head : TAIL COMMUN de tous les switchs (préemption, Wait, reschedule). Bascule sur
; la TÊTE de TaskReady (la plus haute priorité). L'appelant a déjà rangé la sortante (TaskWait
; pour Wait, TaskReady pour requeue_and_dispatch) et sauvé sa frame dans TC_SPREG. TaskReady
; NON vide garanti par l'appelant. a6 = SysBase, IPL >= 3.
dispatch_head:
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)     ; d0 = entrante
        move.l  d0,a1
        move.l  a1,EB_THISTASK(a6)
        move.b  #TS_RUN,TC_STATE(a1)
        clr.b   VBL_INSURG          ; M7a : chirurgie des listes terminée (RemHead fait)
        move.l  TC_SPREG(a1),sp     ; bascule sur la pile de l'entrante
        movem.l (sp)+,d0-d7/a0-a6
        rte                         ; -> entrante (reprend SA frame ; le rte restaure son SR/IPL)

; reschedule : YIELD synchrone volontaire SANS blocage (= yield-sur-Permit, M3e). Requeue la
; tâche courante dans TaskReady (round-robin par priorité) et bascule sur la tête (la réveillée
; prioritaire). Appelé par Permit/Enable quand AttnResched est posé ET le nesting déverrouillé.
; M3f : re-teste AttnResched à IPL 7 (idempotent : un tick a pu consommer la demande entre la
; lecture IPL0 de Permit et cet appel -> on ne switche pas inutilement). Frame de reprise =
; miroir dispatcher ; au retour en .rs_resume, rts vers l'appelant une fois re-dispatchée.
; Fonctionne indépendamment de SCHED_ON (switch direct, pas d'IRQ).
reschedule:
        move.w  #$2700,sr           ; IPL 7 : atomique vs VBlank
        tst.w   EB_ATTNRESCHED(a6)  ; encore demandé ? (un tick a pu le consommer entre-temps)
        beq.s   .rs_none
        move.l  EB_TASKREADY(a6),a0
        tst.l   (a0)                ; prête dispo ? (défensif : AttnResched sans tâche prête)
        beq.s   .rs_none
        move.l  EB_THISTASK(a6),a1
        pea     .rs_resume(pc)      ; frame miroir dispatcher (PC de reprise)
        move.w  #$2000,-(sp)        ; SR de reprise (superviseur, IPL 0)
        movem.l d0-d7/a0-a6,-(sp)
        move.l  sp,TC_SPREG(a1)
        bra     requeue_and_dispatch ; requeue courante + efface AttnResched + bascule sur la tête
.rs_none:                           ; rien à faire -> consommer la demande et revenir
        clr.w   EB_ATTNRESCHED(a6)
        move.w  #$2000,sr
        rts
.rs_resume:                         ; re-dispatchée : GPR/a6 restaurés, SR=$2000 -> retour Permit
        rts
