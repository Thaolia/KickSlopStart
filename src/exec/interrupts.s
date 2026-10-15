; src/exec/interrupts.s — exec.library : plomberie d'interruptions + ordonnanceur préemptif (M3a..M7b)
; + M7c : tâches USER-MODE sur SSP partagée + switch DIFFÉRÉ + M7e : IPL-par-niveau + M7f : VERTB en chaîne.
;
; MODÈLE M7c/M7e/M7f (dérivé du spec public « The Exec Microkernel » d'AROS + mécanique 68000) :
; - Les tâches tournent en USER mode (SR bit S = 0), chacune sur SA pile user (USP). Les
;   interruptions et le noyau tournent sur UNE pile superviseur PARTAGÉE (SSP = région STACKTOP).
; - Le contexte d'une tâche vit sur SA pile user ; TC_SPREG pointe dessus.
; - M7f : les 3 autovecteurs utilisés sont UNIFORMES — int2_dispatch(PORTS)/int3_dispatch(VERTB)/
;   int6_dispatch(EXTER) passent tous par intr_dispatch_number(n) -> chaîne de serveurs IntVects[n].
;   La décision d'ordonnancement (quantum round-robin) est sched_server, un serveur de la chaîne VERTB.
; - PROLOGUE commun : movem.l d0-d7/a0-a6,-(sp) -> frame contiguë [GPR 60][SR 2][PC 4] = 66 o sur la SSP.
;   M7e : les handlers tournent à leur IPL NATIF (int2=2, int3/vbl=3, int6=6, posé par le CPU ; plus de
;   montée IPL7) -> INT6 peut préempter le corps de vbl/int2. ÉPILOGUE commun
;   (intr_exit) : si un switch est demandé
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
; - GATE M7a/M7e : la chirurgie de listes du switch (dispatch) est rendue atomique par IPL7 (« move
;   #imm,sr » = interne CPU, INSTANTANÉ) autour de l'Enqueue/RemHead. PAS par INTENA-off : l'écriture
;   INTENA a un délai de propagation (quirk Amiga modélisé par FS-UAE) -> un INT6 déjà asserté chevauche
;   la fenêtre (prouvé, RED1). VBL_INSURG/VBL_CLASH = détecteur d'OVERLAP (INT6 chevauche la fenêtre),
;   PAS un détecteur de corruption ; l'overlap est la PRÉCONDITION de corruption (INT6->ReplyMsg->
;   Signal Enqueue la même TaskReady que la chirurgie marche). M7e : VBL_INBODY/VBL_PREEMPT_COUNT prouvent
;   qu'INT6 préempte BIEN le corps de vbl (IPL3 natif) sans jamais chevaucher la chirurgie (IPL7). La
;   relocalisation de frame (SSP->pile user) tourne à l'IPL natif sans masque : INT6 s'imbrique sous sp,
;   la frame sortante est intacte.
; - HONNÊTETÉ (cohérence M7d) : la fenêtre write-delay touche TOUTE section masquée par INTENA appelable
;   en USER mode — Signal, PutMsg/GetMsg/ReplyMsg (ports M7d), Wait — car une tâche user ne peut pas
;   monter l'IPL (« move to SR » privilégié, manuel 68000). Elles gardent donc ce caveat, toléré par le
;   re-check (Wait re-teste au réveil) et empiriquement bénin pour les ports M7d même en contention-max.
;   SEUL le switch côté superviseur a été promu à l'IPL7 (il le peut : il tourne en superviseur).
; À VENIR (M7f) : VERTB en chaîne de serveurs, décodage INTREQR multi-source, quantum, RemTask.
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

; init_ints : arme l'interruption VBlank + enregistre sched_server sur la chaîne VERTB (M7f).
; a6 = SysBase. Clobbers d0/d1/a0/a1 (via AllocMem + AddIntServer).
init_ints:
        lea     VBL_COUNT,a0
        clr.l   (a0)                              ; compteur à zéro
        clr.b   SCHED_ON                          ; ordonnanceur désarmé (count-only)
        clr.l   CIAA_PTR                          ; M6b : handlers CIA no-op tant que cia non créé
        clr.l   CIAB_PTR
        clr.l   CIA_FIRED
        clr.b   VBL_INSURG                        ; M7a : aucune chirurgie en cours au départ
        clr.l   VBL_CLASH                         ; M7a : compteur de clashs de ré-entrance
        clr.b   VBL_INBODY                        ; M7e : corps de vbl pas encore entré
        clr.b   VBL_IPL                           ; M7e : IPL observé (rempli par vbl)
        clr.l   VBL_PREEMPT_COUNT                 ; M7e : préemptions du corps de vbl par INT6
        clr.l   IDLE_ENTERED                      ; M7e : épisodes d'idle du dispatcher
        clr.l   VERTB_CHAIN_N                     ; M7f : parcours complets de la chaîne VERTB
        clr.b   M7F_STAT                          ; M7f : marqueur « M7F VERTB OK » pas encore émis
        move.l  #INTVECTS_TOTAL,d0                ; M7b : bloc IntVects (16 vecteurs + 16 svlist)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)                  ; (préserve a6 ; CLEAR -> IV_CODE=0 = aucun handler)
        move.l  d0,EB_INTVECTS(a6)
        move.l  #int3_dispatch,AUTOVEC_L3         ; M7f : VERTB (INT3) -> dispatcher générique par numéro
        move.l  #int2_dispatch,AUTOVEC_L2         ; M7b : INT2/PORTS -> dispatcher générique par numéro
        move.l  #int6_dispatch,AUTOVEC_L6         ; M7b : INT6/EXTER -> dispatcher générique par numéro
        move.l  #trap0_handler,TRAP0_VEC          ; M7c : TRAP #0 = switch volontaire style Wait
        move.l  #trap1_handler,TRAP1_VEC          ; M7c : TRAP #1 = yield (reschedule)
        ; M7f : enregistre le serveur SCHEDULER (quantum round-robin) sur la chaîne VERTB. Faithful :
        ; le vrai exec a un serveur VBlank qui pose la flag AttnResched. pri 20 -> tête de chaîne.
        clr.l   SCHED_INT+LN_SUCC                 ; (RAM basse réservée, non garantie nulle au power-on)
        clr.l   SCHED_INT+IS_DATA                 ; serveur scheduler : IS_DATA inutilisé (lit les globals)
        move.b  #20,SCHED_INT+LN_PRI              ; pri 20 : s'exécute avant timer_vblank(0)/vbl_tail(-10)
        move.l  #sched_server,SCHED_INT+IS_CODE
        moveq   #INTB_VERTB,d0                    ; AddIntServer(VERTB, &SCHED_INT)
        lea     SCHED_INT,a1
        bsr     exec_AddIntServer
        move.w  #INTF_VERTB,INTREQ                ; efface un VERTB pendant
        ; active VERTB + PORTS (INT2) + maître. EXTER(INT6, niveau 6 > VBlank 3) est activé
        ; PLUS TARD, au bringup de l'unité MICROHZ (boot.s M7a) : il préempte désormais le CORPS de
        ; int3_dispatch (chaîne VERTB, IPL natif 3), mais la chirurgie de listes du switch reste atomique
        ; car la section critique du switch (dispatch) monte brièvement IPL7. On le laisse éteint tant qu'aucune
        ; source CIA-B n'existe -> M4..M6 restent inchangés.
        move.w  #(INTF_SETCLR|INTF_INTEN|INTF_VERTB|INTF_PORTS),INTENA
        move.w  #$2000,sr                         ; superviseur, IPL=0 -> les interruptions passent
        rts

; int3_dispatch (AUTOVEC_L3, niveau 3) : M7f — VERTB (seule source de niveau 3 utilisée, mono-source
; comme int2/int6) passe par le dispatcher PAR NUMÉRO + chaîne de serveurs, au lieu d'un handler dédié.
; Corps = M7g DÉCODAGE MULTI-SOURCE : lit INTREQR & INTENAR, dispatche+acke CHAQUE source de niveau 3
; en attente (COPER bit4, VERTB bit5, BLIT bit6) via IntVects[n], au lieu de supposer VERTB seule.
; VERTB -> compteur M3a + chaîne (sched/timer/tail). Épilogue = intr_isr_defer (consomme AttnResched).
; VBL_INBODY (gate M7e) couvre tout le corps (préemptible par INT6). Bonus : sur un INT3 SPURIOUS (délai
; de propagation d'ack, cf. M7e) les 3 btst échouent -> on ne dispatche RIEN (plus correct que M7f qui
; dispatchait VERTB inconditionnellement). d2 = masque des sources en attente, PRÉSERVÉ par la convention
; serveur (walker: movem d2/a2-a4 ; coper_test: ne touche que COPER_FIRED) à travers les dispatch.
int3_dispatch:
                ifne    M7E_PROLOGUE_IPL7
        move.w  #$2700,sr           ; RED2 M7e : modèle M7a (tout le handler IPL7) -> INT6 ne préempte PAS
                                    ; le corps -> VBL_PREEMPT_COUNT==0 -> « M7E IPL OK » jamais émis.
                endc
        movem.l d0-d7/a0-a6,-(sp)   ; PROLOGUE M7e : IPL NATIF (niveau 3) — INT6 (6) peut préempter CE corps
        move.l  ($4).w,a6           ; a6 = SysBase
        st      VBL_INBODY          ; M7e : fenêtre préemptible = décodage+dispatch niveau 3 (détecteur INT6)
        move.w  sr,d0               ; M7e value-check : IPL natif observé (doit == 3, pas 7 ; « move from
        lsr.w   #8,d0               ; SR » non privilégié sur 68000, superviseur ici)
        and.w   #7,d0
        move.b  d0,VBL_IPL
        move.w  INTREQR,d2          ; M7g : sources en attente ...
        and.w   INTENAR,d2          ; ... ET activées (d2 préservé à travers les dispatch)
        btst    #INTB_VERTB,d2      ; --- VERTB (bit 5) ---
        beq.s   .i3_coper
        move.w  #INTF_VERTB,INTREQ  ; ack VERTB (SETCLR=0 -> efface ce seul bit)
        addq.l  #1,VBL_COUNT        ; compteur M3a (SEULEMENT si VERTB réellement en attente)
        moveq   #INTB_VERTB,d0
        bsr     intr_dispatch_number ; chaîne VERTB (sched + timer_vblank + vbl_tail)
        move.l  ($4).w,a6           ; recharge a6 (le walker ne le restaure pas)
.i3_coper:
        btst    #INTB_COPER,d2      ; --- COPER (bit 4) ---
        beq.s   .i3_blit
        move.w  #INTF_COPER,INTREQ  ; ack COPER (toujours, même en RED -> pas de storm)
                ifeq    M7G_MONO_SOURCE
        moveq   #INTB_COPER,d0
        bsr     intr_dispatch_number ; dispatch IntVects[COPER] (= coper_test en démo)
        move.l  ($4).w,a6
                endc                ; RED M7G_MONO_SOURCE=1 : ackée mais NON dispatchée -> COPER_FIRED figé
.i3_blit:
        btst    #INTB_BLIT,d2       ; --- BLIT (bit 6 ; non utilisé en démo -> dormant) ---
        beq.s   .i3_done
        move.w  #INTF_BLIT,INTREQ   ; ack BLIT
                ifeq    M7G_MONO_SOURCE
        moveq   #INTB_BLIT,d0
        bsr     intr_dispatch_number ; dispatch IntVects[BLIT]
        move.l  ($4).w,a6
                endc
.i3_done:
        clr.b   VBL_INBODY          ; M7e : fin de la fenêtre avant dispatch (disjointe de VBL_INSURG)
        bra     intr_isr_defer      ; tail commun : recharge a6 + dispatch différé si AttnResched (S=0)

; sched_server : serveur VERTB de l'ORDONNANCEUR (quantum round-robin). Pose EB_ATTNRESCHED quand une
; préemption est due — SCHED_ON && !Forbid && !Disable && TaskReady non vide (mêmes gardes que l'ancien
; vbl_handler : le round-robin RESPECTE Forbid/Disable). Faithful : le vrai exec a un serveur VBlank qui
; pose la flag AttnResched ; intr_isr_defer la consomme à la sortie d'IRQ (comme un réveil INT6).
; Convention serveur : a6=SysBase (re-fourni par le walker), a1=IS_DATA (libre), préserve d2-d7/a2-a4 ;
; retourne Z-SET (d0=0) = « continue la chaîne » (serveur call-all).
sched_server:
        tst.b   SCHED_ON
        beq.s   .sched_cont         ; ordonnanceur non armé -> ne rien demander (M3a/count-only)
        tst.b   EB_TDNEST(a6)       ; Forbid() actif ? (préemption INVOLONTAIRE respectée)
        bge.s   .sched_cont
        tst.b   EB_IDNEST(a6)       ; Disable() actif ?
        bge.s   .sched_cont
        move.l  EB_TASKREADY(a6),a1 ; TaskReady non vide ? (a1 = IS_DATA, libre) M7e : torn read possible
        tst.l   (a1)                ; vs un AddTail d'INT6 -> bénin (demande spurious/manquée ; RemHead protégé)
        beq.s   .sched_cont
        ; M7h : QUANTUM — ne préempte qu'après M7H_QUANTUM ticks de time-slice (pas chaque tick).
        addq.b  #1,QUANTUM_ELAPSED  ; +1 tick pour la tâche courante
        cmp.b   #M7H_QUANTUM,QUANTUM_ELAPSED
        bcs.s   .sched_cont         ; ELAPSED < QUANTUM -> le time-slice continue (pas de reschedule)
        clr.b   QUANTUM_ELAPSED     ; quantum écoulé -> reset + demande un reschedule différé (round-robin)
        addq.l  #1,QUANTUM_EXPIRE_N ; preuve du débit (≈ VBL_COUNT/QUANTUM en isolation ; ≈0 en démo par défaut)
        move.w  #1,EB_ATTNRESCHED(a6) ; consommé par intr_isr_defer (à la sortie d'IRQ)
.sched_cont:
                ifne    M7F_SCHED_STOPS_CHAIN
        moveq   #1,d0               ; RED2 M7f : Z-CLAIR -> le walker ARRÊTE la chaîne après sched
                else
        moveq   #0,d0               ; Z-SET -> continue la chaîne (call-all : timer_vblank + vbl_tail après)
                endc
        rts

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
; d6=0 -> sortante déjà rangée (Wait sur TaskWait). M7e : relocalisation à l'IPL natif de l'appelant,
; puis chirurgie masquée par IPL7 bref. Ne retourne pas (rte vers l'entrante, à l'IPL/S de la SR restaurée).
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
        dbf     d0,.d_save          ; (relocalisation SÛRE à l'IPL natif : INT6 s'imbrique SOUS sp, frame intacte)
        ; M7e : masque la chirurgie par IPL7 (écriture SR = interne CPU, INSTANTANÉE). PAS INTENA-off :
        ; l'écriture INTENA a un DÉLAI DE PROPAGATION (quirk Amiga modélisé par FS-UAE) -> un INT6 déjà
        ; asserté sur les lignes IPL chevauche la fenêtre VBL_INSURG = clash (prouvé empiriquement, RED1).
        ; POURQUOI l'IPL ici mais INTENA ailleurs (Signal/ports/Wait) : la chirurgie tourne en SUPERVISEUR
        ; (atteinte via intr_exit/trap) -> « move #imm,sr » LÉGAL. Signal/PutMsg/GetMsg/Wait sont appelables
        ; depuis une tâche USER-MODE où « move to SR » est PRIVILÉGIÉ (manuel 68000) -> impossible de monter
        ; l'IPL -> ils doivent utiliser INTENA-Disable, qui porte donc le caveat write-delay (cf. en-tête).
                ifne    M7E_SURGERY_INTENA
        move.w  #INTF_INTEN,INTENA  ; RED1 : masque par INTENA-off (délai de propagation) -> clash observé
                else
        move.w  #$2700,sr           ; GREEN : masque par IPL7 (instantané)
                endc
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
        addq.l  #1,IDLE_ENTERED     ; M7e : instrumentation (épisode d'idle ; doit être > 0 dans un run normal)
.d_idle:                            ; personne de prêt (Wait sans autre tâche prête) : attendre un Signal
        clr.b   VBL_INSURG          ; attente idle -> pas de surgery en cours (pas de faux clash)
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA ; M7e : ré-active INTEN pour recevoir le Signal réveilleur
                                    ; (le chemin Wait->idle arrive INTEN-off depuis exec_Wait -> nécessaire)
        move.w  #$2000,sr           ; IPL0 superviseur -> toute IRQ passe (frame imbriquée, S=1 -> pas de dispatch)
        nop
        move.w  #$2700,sr           ; IPL7 : masque la chirurgie du RemHead (instantané, cf. non-idle)
        move.b  #1,VBL_INSURG
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
        cmp.l   EB_THISTASK(a6),a1  ; M7h : changement RÉEL de tâche (entrante != sortante) ?
        beq.s   .di_samequantum
        clr.b   QUANTUM_ELAPSED     ; oui -> nouveau time-slice (pas de reset sur dispatch-vers-soi)
.di_samequantum:
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
; M7e : plus de montée IPL7 — le trap entre à l'IPL de la tâche (0) ; l'atomicité du switch repose
; ENTIÈREMENT sur le Disable de dispatch. trap0 (Wait) arrive déjà Disabled (exec_Wait a fait INTEN-off
; avant trap #0) -> Disable idempotent. trap1 (yield) arrive INTEN-on -> Disable neuf mais correct.
trap0_handler:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
        moveq   #1,d7
        moveq   #0,d6               ; NE PAS requeue (sortante sur TaskWait)
        bra     intr_exit
trap1_handler:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  ($4).w,a6
        moveq   #1,d7
        moveq   #1,d6               ; requeue sortante -> TaskReady
        bra     intr_exit

; ============================ dispatcher par numéro (M7b) ==========
; SetIntVector/AddIntServer + autovecteurs génériques INT2(PORTS)/INT6(EXTER) + walker de chaîne.
; M7e : dispatch PAR NUMÉRO (lookup IntVects[n] + chaîne de serveurs) À L'IPL NATIF — int2 tourne à
; IPL2, int6 à IPL6 (plus de montée IPL7). INT6 peut donc préempter int2 et le corps de vbl. L'atomicité
; du scheduler ne vient plus de l'IPL mais du Disable (INTEN off) autour de la chirurgie dans dispatch.
; M7c : int2/int6 partagent le prologue (movem) et l'épilogue (intr_exit). FLAG DE DISPATCH
; DIFFÉRÉ (spec AROS « The Exec Microkernel ») : si un serveur a réveillé une tâche PRIORITAIRE (Signal
; a posé EB_ATTNRESCHED), l'épilogue dispatche IMMÉDIATEMENT à la sortie d'interruption (à la frontière
; user S=0) au lieu d'attendre un Permit/Enable ou le prochain VBlank. Sans ça, une tâche réveillée par
; IRQ dépend du hasard de phase (quelle tâche tourne + appelle Permit) -> réveil erratique (résonance).
; Signal ne RESCHEDULE jamais lui-même depuis l'interruption (pas de ré-entrance) : il POSE le flag,
; l'épilogue le consomme. M7f : VERTB passe AUSSI par ce dispatcher (int3_dispatch -> chaîne VERTB :
; sched_server + timer_vblank + vbl_tail) -> modèle UNIFORME PORTS(int2)/VERTB(int3)/EXTER(int6).

; int2_dispatch ($68, niveau 2) : seule source de niveau 2 = PORTS -> dispatche IntVects[INTB_PORTS].
int2_dispatch:
        movem.l d0-d7/a0-a6,-(sp)   ; PROLOGUE M7e : IPL NATIF (niveau 2) — préemptible par vbl(3)/int6(6)
        move.l  ($4).w,a6
        moveq   #INTB_PORTS,d0
        bsr     intr_dispatch_number
        move.w  #INTF_PORTS,INTREQ  ; ack Paula INT2
        bra.s   intr_isr_defer
; int6_dispatch ($78, niveau 6) : seule source de niveau 6 = EXTER -> dispatche IntVects[INTB_EXTER].
int6_dispatch:
        movem.l d0-d7/a0-a6,-(sp)   ; PROLOGUE M7e : IPL NATIF (niveau 6) — niveau max utilisé, jamais préempté
        move.l  ($4).w,a6
        moveq   #INTB_EXTER,d0
        bsr     intr_dispatch_number
        move.w  #INTF_EXTER,INTREQ  ; ack Paula INT6
; intr_isr_defer : tail commun int2/int3/int6 — flag de dispatch différé (EB_ATTNRESCHED).
intr_isr_defer:
        move.l  ($4).w,a6           ; M7f : RECHARGE a6=SysBase — le walker ne restaure PAS a6 après le
                                    ; dernier serveur, qui a pu le clobber (convention préserve d2-d7/a2-a4
                                    ; seulement). Sans ça, les lectures EB_* ci-dessous liraient du garbage.
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
