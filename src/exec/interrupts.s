; src/exec/interrupts.s — exec.library : plomberie d'interruptions + ordonnanceur
; préemptif (M3a..M7b) + M7c : tâches USER-MODE sur SSP partagée + switch DIFFÉRÉ.
;
; MODÈLE M7c (dérivé du spec public « The Exec Microkernel » d'AROS + mécanique 68000) :
; - Les tâches tournent en USER mode (SR bit S = 0), chacune sur SA pile user (USP). Les
;   interruptions et le noyau tournent sur UNE pile superviseur PARTAGÉE (SSP = région STACKTOP).
; - Le contexte d'une tâche vit sur SA pile user ; TC_SPREG pointe dessus.
; - PROLOGUE commun (vbl/int2/int6/trap) : IPL7 + movem.l d0-d7/a0-a6,-(sp) -> frame contiguë
;   [GPR 60][SR 2][PC 4] = 66 o sur la SSP. ÉPILOGUE commun (intr_exit) : si un switch est demandé
;   ET la SR SAUVÉE a S=0 (on interrompait une tâche user = frontière externe, pas une IRQ imbriquée),
;   -> dispatch ; sinon movem+rte (reprend l'interrompu). S=1 => imbriqué/noyau => jamais de switch
;   (le contexte user n'est pas disponible) : c'est le NEST-COUNT, lu directement dans le bit S.
; - dispatch : RELOCALISE la frame de la sortante SSP -> sa pile user (move usp,a0 ; copie 66 o ;
;   TC_SPREG<-), puis charge l'entrante (copie sa frame pile user -> SSP ; usp<-fin ; movem+rte ->
;   repart en USER mode). Sauve/restaure le nesting PAR-TÂCHE (TC_IDNESTCNT/TC_TDNESTCNT <-> EB_*)
;   et synchronise INTENA. => SSP jamais partagée entre contextes de tâches (hazard neutralisé).
; - Switch VOLONTAIRE (user-mode) : trap #0 (Wait : sortante déjà rangée) / trap #1 (yield : requeue
;   sortante->Ready). Le trap entre en superviseur (frame user sur SSP) et rejoint l'épilogue commun.
; - PRÉEMPTION : round-robin par tick VBlank (SCHED_ON && !Forbid && !Disable && TaskReady non vide).
;   FLAG DE DISPATCH DIFFÉRÉ (M7c) : int2/int6, si un serveur a réveillé une tâche PRIORITAIRE (Signal a
;   posé EB_ATTNRESCHED), demandent un switch à la SORTIE d'interruption (d7<-AttnResched) au lieu
;   d'attendre un Permit ou le prochain VBlank -> réveil déterministe (sans ça : résonance de phase).
;   Signal ne RESCHEDULE jamais depuis l'IRQ (pas de ré-entrance) : il POSE le flag, l'épilogue le consomme.
; - GATE M7a : le prologue commun monte IPL7, donc toute la chirurgie de listes du switch est atomique
;   vs une source de niveau > 3 (INT6/CIA-B). VBL_INSURG/VBL_CLASH reste le détecteur (cf. exec.i).
; À VENIR (M7e) : fidélité IPL-par-niveau, VERTB en chaîne de serveurs, décodage INTREQR, quantum, RemTask.
; Piste IMPLÉMENTATION (« clean ») : hardware/intbits.i (ABI publique) + HRM + spec AROS public.

                include "exec.i"

                xdef    init_ints
                xdef    exec_Wait
                xdef    reschedule
                xdef    dispatch_in        ; M7c : demi-restauration du switch (lancement 1re tâche = boot.s)
                xdef    exec_SetIntVector  ; M7b : dispatcher par numéro (vecteur exclusif)
                xdef    exec_AddIntServer  ; M7b : dispatcher par numéro (chaîne de serveurs)

                xref    newlist          ; lists.s (NEWLIST d'une chaîne de serveurs)
                xref    exec_Enqueue     ; lists.s (AddIntServer : insertion par priorité)
                xref    exec_AllocMem    ; memory.s (alloc du bloc IntVects à init_ints)
                xref    raw_enable       ; library.s (Enable NU : Wait réactive sans la queue reschedule)

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
        move.l  #INTVECTS_TOTAL,d0                ; M7b : bloc IntVects (16 vecteurs + 16 svlist)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)                  ; (préserve a6 ; CLEAR -> IV_CODE=0 = aucun handler)
        move.l  d0,EB_INTVECTS(a6)
        move.l  #vbl_handler,AUTOVEC_L3           ; autovecteur niveau 3 -> handler VBlank (scheduler)
        move.l  #int2_dispatch,AUTOVEC_L2         ; M7b : INT2/PORTS -> dispatcher générique par numéro
        move.l  #int6_dispatch,AUTOVEC_L6         ; M7b : INT6/EXTER -> dispatcher générique par numéro
        move.l  #trap0_handler,TRAP0_VEC          ; M7c : TRAP #0 = switch volontaire style Wait
        move.l  #trap1_handler,TRAP1_VEC          ; M7c : TRAP #1 = yield (reschedule)
        move.w  #INTF_VERTB,INTREQ                ; efface un VERTB pendant
        ; active VERTB + PORTS (INT2) + maître. EXTER(INT6, niveau 6 > VBlank 3) est activé
        ; PLUS TARD, au bringup de l'unité MICROHZ (boot.s M7a) : il peut désormais préempter le
        ; VBlank sans danger car la chirurgie de listes de vbl_handler est IPL7 (gate M7a), mais on
        ; le laisse éteint tant qu'aucune source CIA-B n'existe -> M4..M6 restent inchangés.
        move.w  #(INTF_SETCLR|INTF_INTEN|INTF_VERTB|INTF_PORTS),INTENA
        move.w  #$2000,sr                         ; superviseur, IPL=0 -> les interruptions passent
        rts

; vbl_handler : interruption VBlank (niveau 3). Prologue commun -> corps (compteur + service timer
; + décision round-robin) -> épilogue commun (intr_exit). Ne switche plus inline.
vbl_handler:
        move.w  #$2700,sr           ; PROLOGUE : IPL7 (légal, superviseur) -> gate M7a + atomicité
        movem.l d0-d7/a0-a6,-(sp)   ; frame [GPR][SR][PC] sur la SSP partagée
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
        moveq   #0,d7               ; d7 = switch demandé ? (0=non) ; d6 = requeue sortante ?
        tst.b   SCHED_ON
        beq.s   .vbl_exit           ; ordonnanceur non armé -> juste compter (M3a)
        tst.b   EB_TDNEST(a6)       ; Forbid() actif ? (préemption INVOLONTAIRE -> on respecte)
        bge.s   .vbl_exit
        tst.b   EB_IDNEST(a6)       ; Disable() actif ?
        bge.s   .vbl_exit
        move.l  EB_TASKREADY(a6),a0 ; TaskReady non vide ?
        tst.l   (a0)                ; (lh_Head)->Succ==0 <=> vide (MOVEA ne pose pas les flags -> tst)
        beq.s   .vbl_exit
        moveq   #1,d7               ; préemption round-robin demandée
        moveq   #1,d6               ; -> dispatch requeue la sortante dans TaskReady
.vbl_exit:
        bra     intr_exit

; intr_exit : ÉPILOGUE commun (vbl/int2/int6/trap). d7 = switch demandé. On switche SEULEMENT à la
; FRONTIÈRE USER : bit S de la SR SAUVÉE (FRAME_SR) == 0. S=1 (IRQ imbriquée / noyau) => contexte user
; indisponible => reprise simple. C'est le nest-count, lu directement dans le bit S. a6=SysBase.
intr_exit:
        tst.b   d7
        beq.s   .ie_noswitch
        move.w  FRAME_SR(sp),d0     ; SR sauvée sur la SSP
        and.w   #$2000,d0           ; bit S (superviseur) ?
        bne.s   .ie_noswitch        ; S=1 -> imbriqué -> pas de switch (reprend l'interrompu)
        bra     dispatch            ; frontière user -> relocalise + bascule (ne revient pas ici)
.ie_noswitch:
        movem.l (sp)+,d0-d7/a0-a6
        rte

; dispatch : RELOCALISE la frame de la sortante (SSP -> sa pile user) puis charge l'entrante. Entrée :
; sp = frame 66 o sur la SSP ; a6=SysBase ; d6=1 -> requeue la sortante dans TaskReady (round-robin),
; d6=0 -> sortante déjà rangée (Wait sur TaskWait). IPL7. Ne retourne pas (rte vers l'entrante).
dispatch:
        move.l  EB_THISTASK(a6),a1  ; sortante
        move.b  EB_IDNEST(a6),TC_IDNESTCNT(a1)  ; nesting PAR-TÂCHE : sauve l'état de la sortante
        move.b  EB_TDNEST(a6),TC_TDNESTCNT(a1)
        move.l  usp,a0              ; a0 = USP sortante (privilégié, OK superviseur)
        lea     -FRAME_SIZE(a0),a3  ; dest = pile user sortante - 66
        move.l  a3,TC_SPREG(a1)     ; TC_SPREG sortante = base de la frame relocalisée
        move.l  sp,a2               ; src = frame sur la SSP (piles disjointes -> copie ascendante sûre)
        moveq   #(FRAME_SIZE/2)-1,d0
.d_save:
        move.w  (a2)+,(a3)+         ; relocalise 66 o SSP -> pile user (33 mots, aucun long à cheval sur SR)
        dbf     d0,.d_save
        move.b  #1,VBL_INSURG       ; chirurgie des listes (Enqueue/RemHead) = section contendue (détect. M7a)
        tst.b   d6
        beq.s   .d_pick             ; sortante déjà rangée (Wait) -> pas de requeue
        move.b  #TS_READY,TC_STATE(a1)
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_ENQUEUE(a6)     ; round-robin : requeue la sortante (a1 préservé)
        clr.w   EB_ATTNRESCHED(a6)  ; un switch satisfait toute demande de reschedule
.d_pick:
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)     ; d0 = entrante | 0
        tst.l   d0
        bne.s   .d_have
        clr.b   VBL_INSURG          ; attente idle -> pas de surgery en cours (pas de faux clash)
.d_idle:                            ; personne de prêt (Wait sans autre tâche prête) : attendre un Signal
        move.w  #$2000,sr           ; IPL0 superviseur -> IRQ passe (frame imbriquée, S=1 -> pas de dispatch)
        nop
        move.w  #$2700,sr
        lea     EB_TASKREADY(a6),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .d_idle
.d_have:
        move.l  d0,a1               ; entrante
        clr.b   VBL_INSURG          ; chirurgie terminée (RemHead fait)
        ; tombe dans dispatch_in

; dispatch_in : demi-restauration — charge l'entrante (a1) et rte en USER mode. Aussi utilisée par le
; LANCEMENT de la 1re tâche (boot.s), qui réalise la transition superviseur->user. sp = slot 66 o SSP.
dispatch_in:
        move.l  a1,EB_THISTASK(a6)
        move.b  #TS_RUN,TC_STATE(a1)
        move.b  TC_IDNESTCNT(a1),EB_IDNEST(a6)  ; restaure le nesting de l'entrante
        move.b  TC_TDNESTCNT(a1),EB_TDNEST(a6)
        tst.b   EB_IDNEST(a6)
        bge.s   .di_dis             ; entrante Disabled -> INTEN off
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA  ; entrante permise -> INTEN on (ne touche QUE bit14)
        bra.s   .di_copy
.di_dis:
        move.w  #INTF_INTEN,INTENA  ; clear INTEN (bit14 ; sans SETCLR = efface)
.di_copy:
        move.l  TC_SPREG(a1),a2     ; src = frame de l'entrante (sa pile user)
        move.l  sp,a3               ; dest = slot SSP (réécrit l'emplacement de la frame sortante)
        moveq   #(FRAME_SIZE/2)-1,d0
.di_loop:
        move.w  (a2)+,(a3)+
        dbf     d0,.di_loop
        move.l  TC_SPREG(a1),a2
        lea     FRAME_SIZE(a2),a2   ; USP entrante = après sa frame restaurée
        move.l  a2,usp
        movem.l (sp)+,d0-d7/a0-a6   ; dépile les GPR de l'entrante
        rte                         ; dépile {SR,PC} -> repart en USER mode (SR sauvé S=0) sur sa USP

; exec_Wait(signalSet d0.l) -> d0 = signaux reçus. Bloque ThisTask (USER mode) jusqu'à réception.
; Section critique via Disable NU (INTENA, user-safe) ; blocage via trap #0 (entre en superviseur ->
; dispatch relocalise). Au réveil (re-dispatché après le trap), re-teste (robuste au spurious).
; Sortie NUE (raw_enable) : la réveillée tourne déjà -> pas de yield (préserve la sémantique M3d).
exec_Wait:
        addq.b  #1,EB_IDNEST(a6)    ; Disable NU : section critique vs scheduler
        move.w  #INTF_INTEN,INTENA  ; INTEN off (bit14)
        move.l  EB_THISTASK(a6),a1
        move.l  d0,TC_SIGWAIT(a1)
.wa_check:
        move.l  TC_SIGRECVD(a1),d0
        and.l   TC_SIGWAIT(a1),d0
        bne.s   .wa_got             ; un signal attendu est présent -> pas de blocage
        move.b  #TS_WAIT,TC_STATE(a1)
        lea     EB_TASKWAIT(a6),a0
        jsr     LVO_ADDTAIL(a6)     ; ThisTask (a1) -> TaskWait (a1 préservé)
        trap    #0                  ; -> superviseur -> dispatch (sortante déjà sur TaskWait, d6=0)
        move.l  EB_THISTASK(a6),a1  ; re-dispatchée : a6/a1 restaurés par le switch (reload défensif)
        bra.s   .wa_check           ; re-teste (spurious -> re-bloque)
.wa_got:
        eor.l   d0,TC_SIGRECVD(a1)  ; efface les bits qui réveillent (d0 ⊆ SIGRECVD)
        clr.l   TC_SIGWAIT(a1)
        bsr     raw_enable          ; INTEN on si IDNest<0 (sortie NUE, pas de queue reschedule)
        rts

; reschedule : YIELD synchrone volontaire (yield-sur-Permit, M3e). Appelé par Permit/Enable (USER mode,
; permis & enabled, AttnResched posé). trap #1 -> dispatch requeue la courante (d6=1) + bascule sur la
; réveillée prioritaire. Au retour (re-dispatchée), rts vers Permit/Enable.
reschedule:
        tst.w   EB_ATTNRESCHED(a6)  ; encore demandé ? (un tick a pu le consommer)
        beq.s   .rs_none
        move.l  EB_TASKREADY(a6),a0
        tst.l   (a0)                ; une prête dispo ? (défensif)
        beq.s   .rs_none
        trap    #1                  ; yield : dispatch requeue self->Ready + RemHead
        rts                         ; re-dispatchée -> retour Permit/Enable
.rs_none:
        clr.w   EB_ATTNRESCHED(a6)
        rts

; trap0_handler (TRAP #0) : switch volontaire style Wait — la sortante est DÉJÀ rangée (TaskWait).
; trap1_handler (TRAP #1) : yield — dispatch requeue la sortante dans TaskReady (round-robin).
; Le CPU a poussé {SR user, PC} au trap -> la SR sauvée a S=0 -> l'épilogue dispatch garanti.
trap0_handler:
        move.w  #$2700,sr
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
        moveq   #1,d7
        moveq   #0,d6               ; NE PAS requeue (sortante sur TaskWait)
        bra     intr_exit
trap1_handler:
        move.w  #$2700,sr
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
        moveq   #1,d7
        moveq   #1,d6               ; requeue sortante -> TaskReady
        bra     intr_exit

; ============================ dispatcher par numéro (M7b) ==========
; SetIntVector/AddIntServer + autovecteurs génériques INT2(PORTS)/INT6(EXTER) + walker de chaîne.
; CAVEAT (ledgeré) : dispatch PAR NUMÉRO (lookup IntVects[n] + chaîne de serveurs), PAS la fidélité
; IPL-PAR-NIVEAU (tourner à l'IPL de l'interruption) — on garde IPL7 à l'entrée (prologue commun).
; M7c : int2/int6 partagent le prologue (IPL7 + movem) et l'épilogue (intr_exit). FLAG DE DISPATCH
; DIFFÉRÉ (spec AROS « The Exec Microkernel ») : si un serveur a réveillé une tâche PRIORITAIRE (Signal
; a posé EB_ATTNRESCHED), l'épilogue dispatche IMMÉDIATEMENT à la sortie d'interruption (à la frontière
; user S=0) au lieu d'attendre un Permit/Enable ou le prochain VBlank. Sans ça, une tâche réveillée par
; IRQ dépend du hasard de phase (quelle tâche tourne + appelle Permit) -> réveil erratique (résonance).
; Signal ne RESCHEDULE jamais lui-même depuis l'interruption (pas de ré-entrance) : il POSE le flag,
; l'épilogue le consomme. VERTB garde son handler dédié (vbl_handler) : VERTB->chaîne = M7d.

; int2_dispatch ($68, niveau 2) : seule source de niveau 2 = PORTS -> dispatche IntVects[INTB_PORTS].
int2_dispatch:
        move.w  #$2700,sr           ; PROLOGUE commun (IPL7)
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
        moveq   #INTB_PORTS,d0
        bsr     intr_dispatch_number
        move.w  #INTF_PORTS,INTREQ  ; ack Paula INT2
        bra.s   intr_isr_defer
; int6_dispatch ($78, niveau 6) : seule source de niveau 6 = EXTER -> dispatche IntVects[INTB_EXTER].
int6_dispatch:
        move.w  #$2700,sr
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
        moveq   #INTB_EXTER,d0
        bsr     intr_dispatch_number
        move.w  #INTF_EXTER,INTREQ  ; ack Paula INT6
; intr_isr_defer : tail commun int2/int6 — flag de dispatch différé (EB_ATTNRESCHED).
intr_isr_defer:
        moveq   #1,d6               ; round-robin : requeue la tâche interrompue si on dispatche
        moveq   #0,d7
        tst.w   EB_ATTNRESCHED(a6)  ; un serveur a-t-il réveillé une tâche prioritaire ?
        beq.s   intr_isr_exit
        moveq   #1,d7               ; flag de dispatch différé -> switch à la sortie (si S=0)
intr_isr_exit:
        bra     intr_exit

; intr_dispatch_number(d0.l = numéro ; a6 = SysBase) : appelle le handler de IntVects[n]. Vecteur
; exclusif (SetIntVector) -> appel direct ; chaîne (AddIntServer) -> IV_CODE = intr_chain_walker.
; Convention (AutoDoc) : a0=$DFF000, a1=IS_DATA (ou &svlist), a5=IS_CODE (ou walker), a6=SysBase.
intr_dispatch_number:
        move.l  EB_INTVECTS(a6),a1
        move.l  a1,d1
        beq.s   .idn_ret            ; table non allouée (défensif)
        lsl.l   #3,d0               ; n * IV_SIZE(8)
        add.l   d0,a1               ; a1 = &IntVects[n]
        move.l  IV_CODE(a1),a5
        move.l  a5,d1
        beq.s   .idn_ret            ; aucun handler pour ce numéro
        move.l  IV_DATA(a1),a1      ; a1 = IS_DATA (ou &svlist)
        lea     CUSTOM,a0           ; a0 = $DFF000 (convention serveur)
        jsr     (a5)
.idn_ret:
        rts

; intr_chain_walker(a1 = &svlist, a0=$DFF000, a6=SysBase) : marche la chaîne par priorité (tête = plus
; haute pri, posée par Enqueue). Appelle chaque serveur jusqu'à Z clair (!=0 = « géré, stop ») ; Z mis
; (==0) = continue (AutoDoc AddIntServer ; les serveurs « call-all » type VERTB retournent Z mis).
; a2/a3 = marche, a4 = SysBase stashé — préservés par les serveurs (convention d2-d7/a2-a4).
intr_chain_walker:
        movem.l d2/a2-a4,-(sp)
        move.l  a6,a4               ; stash SysBase (a4 préservé par les serveurs)
        move.l  (a1),a2             ; a2 = lh_Head (1er noeud)
.cw_loop:
        move.l  (a2),d2             ; d2 = node->Succ (registre DONNÉES -> pose les flags ;
        beq.s   .cw_done            ; MOVEA vers Ax n'affecterait PAS les CC -> beq faux). 0 => tail.
        movea.l d2,a3               ; a3 = Succ (préservé par les serveurs : d2-d7/a2-a4)
        move.l  IS_DATA(a2),a1      ; a1 = IS_DATA du serveur
        move.l  IS_CODE(a2),a5
        lea     CUSTOM,a0           ; re-fournit a0=$DFF000 (un serveur a pu le clobber)
        move.l  a4,a6               ; re-fournit a6=SysBase
        jsr     (a5)
        bne.s   .cw_done            ; Z clair -> serveur a « géré » -> stop la chaîne
        movea.l a3,a2               ; noeud suivant
        bra.s   .cw_loop
.cw_done:
        movem.l (sp)+,d2/a2-a4
        rts

; SetIntVector(intNum d0, interrupt a1) -> d0 = ancien Interrupt (SIMPLIFIÉ : 0, cf. ledger). Vecteur
; EXCLUSIF : copie IS_DATA/IS_CODE dans IntVects[n] (a1=NULL -> efface). a6=SysBase.
exec_SetIntVector:
        move.l  EB_INTVECTS(a6),a0
        move.l  a0,d1
        beq.s   .siv_ret
        lsl.l   #3,d0               ; n * IV_SIZE
        add.l   d0,a0               ; a0 = &IntVects[n]
        move.l  a1,d1
        beq.s   .siv_null
        move.l  IS_DATA(a1),IV_DATA(a0)
        move.l  IS_CODE(a1),IV_CODE(a0)
        bra.s   .siv_ret
.siv_null:
        clr.l   IV_DATA(a0)
        clr.l   IV_CODE(a0)
.siv_ret:
        moveq   #0,d0               ; ancien Interrupt (non suivi -> 0)
        rts

; AddIntServer(intNum d0, interrupt a1) -> void. Ajoute le serveur à la chaîne du numéro, trié par
; LN_PRI. 1er serveur : NEWLIST la svlist, pose IV_DATA=&svlist / IV_CODE=intr_chain_walker. a6=SysBase.
exec_AddIntServer:
        movem.l d2/a2/a3,-(sp)
        move.l  a1,a2               ; a2 = interrupt (préservé par newlist/Enqueue)
        move.l  EB_INTVECTS(a6),a3  ; a3 = base table
        move.l  a3,d1
        beq.s   .ais_ret            ; table absente (défensif)
        move.l  d0,d2               ; d2 = numéro
        move.l  d2,d1               ; &IntVects[n] = base + n*8
        lsl.l   #3,d1
        lea     0(a3,d1.l),a0       ; a0 = &IntVects[n]
        cmp.l   #intr_chain_walker,IV_CODE(a0)
        beq.s   .ais_enq            ; déjà une chaîne
        move.l  d2,d1               ; 1er serveur : &svlist[n] = base + SVOFF + n*14
        mulu    #IV_LIST_SIZE,d1
        add.l   #INTVECTS_SVOFF,d1
        lea     0(a3,d1.l),a1       ; a1 = &svlist[n]
        move.l  a0,-(sp)            ; sauve &IntVects[n]
        move.l  a1,-(sp)            ; sauve &svlist[n]
        jsr     newlist             ; NEWLIST(a1) (clobbe a0)
        move.l  (sp)+,a1
        move.l  (sp)+,a0
        move.l  a1,IV_DATA(a0)
        move.l  #intr_chain_walker,IV_CODE(a0)
.ais_enq:
        move.l  d2,d1               ; &svlist[n] (robuste aux deux chemins)
        mulu    #IV_LIST_SIZE,d1
        add.l   #INTVECTS_SVOFF,d1
        lea     0(a3,d1.l),a0       ; a0 = &svlist[n]
        move.l  a2,a1               ; a1 = interrupt
        jsr     LVO_ENQUEUE(a6)     ; insère par LN_PRI (tête = plus haute pri)
.ais_ret:
        movem.l (sp)+,d2/a2/a3
        rts
