; src/exec/interrupts.s — exec.library : plomberie d'interruptions + ordonnanceur
; préemptif minimal (M3a plomberie + M3b switch round-robin, tâches SUPERVISEUR).
;   init_ints   : installe l'autovecteur 68000 niveau 3 (VBlank), active VERTB +
;                 le maître INTEN, abaisse le masque IPL -> les interruptions passent.
;   vbl_handler : point de préemption. SCHED_ON=0 -> compte juste VBL_COUNT (M3a).
;                 SCHED_ON=1 -> switch round-robin entre les tâches de TaskReady.
; Tâches en SUPERVISEUR : leur pile EST la pile superviseur, donc la frame {SR,PC}
; poussée par le CPU est déjà sur la pile de la tâche -> le switch est un simple
; échange de SP (pas de jonglage USP/SSP ; user-mode = M3c). Au IPL 3 : pas de
; ré-entrée mid-switch. À VENIR : dispatcher par niveau (décodage INTREQR),
; IntVects/SetIntVector/AddIntServer, Wait/WaitPort, réveil-sur-signal, quantum TQE.
; Piste IMPLÉMENTATION (« clean ») : hardware/intbits.i (ABI publique) + HRM.

                include "exec.i"

                xdef    init_ints

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
