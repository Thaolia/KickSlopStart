; src/exec/timer.s — timer.device — M5c (création AUTOINIT) + M6a (unité VBLANK fonctionnelle).
; 2e vrai module résident, 1er DEVICE. ROMTag RTF_AUTOINIT (pri 50) -> chemin AUTOINIT de
; InitResident (MakeLibrary + Enqueue DeviceList). Quirk V34 : la data table pose LN_TYPE +
; LIB_VERSION et l'init func pose LN_NAME="timer.device" + initialise l'unité VBLANK + enregistre
; le service VBlank (hook VBL_SVC appelé par le handler VBlank chaque tick).
;
; M6a — UNITÉ VBLANK FONCTIONNELLE (sans CIA) :
;   BeginIO(TR_ADDREQUEST) : convertit la timeval en TICKS (secs*50 + micro/20000), stocke le
;     décompte dans TR_TIME, enqueue la requête sur la file de l'unité VBLANK. Disable autour de
;     la manip (la file est partagée avec le handler VBlank = interruption, pas juste des tâches).
;   timer_vblank_service : appelé depuis le handler VBlank (IPL 3) chaque tick. Décrémente chaque
;     requête ; à 0 -> la retire et la « répond ». La réponse utilise des PRIMITIVES BRUTES
;     (AddTail au reply port + exec_Signal) et NON PutMsg/ReplyMsg : ces derniers appellent Permit
;     qui ferait un reschedule SYNCHRONE au milieu de l'interruption. Signal pose AttnResched sans
;     rescheduler -> le switch se fait à la fin du handler (round-robin existant).
; M7a — UNITÉ MICROHZ (via CIA-B / INT6) :
;   2e file d'unité (TIMER_MICROQ) décrémentée par timer_micro_service, enregistré comme vecteur
;   ICR du timer A de ciab.resource (déclenché à chaque underflow CIA-B -> INT6 niveau 6). BeginIO
;   route par IO_UNIT (0=MICROHZ, 1=VBLANK). Prouve une TÂCHE qui BLOQUE sur un timer (Wait->wake
;   par l'IRQ MICROHZ) ET le GATE DE RÉ-ENTRANCE : INT6 (niveau 6 > VBlank 3) peut préempter
;   vbl_handler ; sa chirurgie de listes est désormais IPL7 (interrupts.s). Le service pose le
;   détecteur VBL_CLASH si jamais il observe vbl_handler en pleine chirurgie (= 0 avec le fix).
; DIFFÉRÉ (ledgeré) : unité ECLOCK, calibration µs réelle de MICROHZ (latch E-clock : ici « 1 tick
;   = 1 interruption CIA-B », le chemin IRQ/réveil est prouvé, pas la résolution microseconde),
;   OpenDevice (la preuve remplit IO_DEVICE/IO_UNIT à la main), conversion timeval complète.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs timer.device + exec. AUCUNE lecture ROM.

                include "exec.i"

                xdef    timer_micro_int   ; M7a : struct Interrupt de l'unité MICROHZ (vecteur ICR CIA-B)

                xref    newlist           ; lists.s (NEWLIST de la file d'unité)
                xref    raw_enable        ; library.s (M7c : timer_reply = section critique NUE)

; --- ROMTag timer.device (scanné par build_reslist) ---
        EVEN
timer_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    timer_romtag         ; RT_MATCHTAG = self
        dc.l    timer_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT,34,NT_DEVICE,50  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    timer_name           ; RT_NAME
        dc.l    timer_name           ; RT_IDSTRING
        dc.l    timer_inittab        ; RT_INIT -> table AUTOINIT
timer_name:
        dc.b    "timer.device",0
        EVEN
timer_inittab:
        dc.l    TD_SIZE              ; dataSize (Library + file d'unité VBLANK)
        dc.l    timer_vectors        ; funcTable
        dc.l    timer_datatab        ; dataTable (InitStruct)
        dc.l    timer_initfunc       ; initFunc
timer_vectors:                       ; table ABSOLUE, terminée par -1 (ordre device standard)
        dc.l    timer_open           ; LVO -6
        dc.l    timer_close          ; LVO -12
        dc.l    timer_expunge        ; LVO -18
        dc.l    timer_null           ; LVO -24 (réservé / ExtFunc)
        dc.l    timer_beginio        ; LVO -30
        dc.l    timer_abortio        ; LVO -36
        dc.l    -1
timer_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)  ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34          ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(device a6, iorequest a1, unit d0, flags d1) : incrémente le compte d'ouverture.
timer_open:
        addq.w  #1,LIB_OPENCNT(a6)
        rts
timer_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
timer_expunge:
        moveq   #0,d0
        rts
timer_null:
        moveq   #0,d0
        rts

; BeginIO(device a6, iorequest a1) : M6a — enqueue une requête TR_ADDREQUEST sur l'unité VBLANK.
; Convertit la timeval en ticks (secs*50 + micro/20000, mini 1), stocke le décompte dans TV_SECS.
; Disable autour (file partagée avec le handler VBlank).
timer_beginio:
        movem.l d2/a2-a3,-(sp)
        move.l  a6,a2                ; a2 = base device
        move.l  a1,a3                ; a3 = iorequest
        move.l  ($4).w,a6            ; a6 = SysBase (pour les appels exec)
        jsr     LVO_DISABLE(a6)
        move.l  TV_SECS(a3),d0
        mulu    #50,d0               ; secs*50 (suppose secs petit)
        move.l  TV_MICRO(a3),d1
        divu    #20000,d1            ; micro/20000 (0..49)
        and.l   #$0000FFFF,d1        ; quotient (mot bas)
        add.l   d1,d0                ; ticks
        bne.s   .bio_store
        moveq   #1,d0                ; mini 1 tick (évite expiration immédiate)
.bio_store:
        move.l  d0,TV_SECS(a3)       ; décompte en ticks (TV_SECS réutilisé)
        clr.l   TV_MICRO(a3)
        move.b  #NT_MESSAGE,LN_TYPE(a3)
        lea     TIMER_MICROQ(a2),a0  ; route par IO_UNIT : défaut MICROHZ (unité 0, CIA-B/INT6)
        cmp.l   #UNIT_VBLANK,IO_UNIT(a3)
        bne.s   .bio_q
        lea     TIMER_VBLQ(a2),a0    ; unité VBLANK (le handler VBlank décrémente cette file)
.bio_q:
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)      ; enqueue (sous Disable -> atomique vs VBlank ET INT6)
        jsr     LVO_ENABLE(a6)
        move.l  a2,a6                ; restaure a6 = base device
        movem.l (sp)+,d2/a2-a3
        rts
timer_abortio:
        moveq   #0,d0
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Pose le nom (quirk V34),
; NEWLIST l'unité VBLANK, enregistre le service VBlank.
timer_initfunc:
        move.l  d0,a1                ; a1 = base
        lea     timer_name(pc),a0
        move.l  a0,LN_NAME(a1)
        move.l  d0,-(sp)             ; sauve la base
        lea     TIMER_VBLQ(a1),a1    ; NEWLIST file d'unité VBLANK
        jsr     newlist              ; (clobbe a0 ; a6 préservé)
        move.l  (sp),a1              ; relit la base (sans dépiler)
        lea     TIMER_MICROQ(a1),a1  ; M7a : NEWLIST file d'unité MICROHZ (CIA-B/INT6)
        jsr     newlist
        move.l  (sp)+,d0             ; base
        move.l  #timer_vblank_service,VBL_SVC   ; enregistre le hook VBlank (unité VBLANK)
        move.l  d0,VBL_SVCDATA       ; data = base device (lue aussi par timer_micro_service)
        rts                          ; d0 = base inchangé

; timer_vblank_service(a1 = base device, a6 = SysBase) : appelé par le handler VBlank chaque tick.
; TRANSPARENT (sauve tout ce qu'il clobbe, préserve a6). Décrémente chaque requête de la file ;
; à 0 -> Remove + reply (bas-niveau, sans Permit -> pas de reschedule mid-interruption).
timer_vblank_service:
        movem.l d0-d2/a0-a4,-(sp)
        move.l  a1,a2                ; a2 = base device
        lea     TIMER_VBLQ(a2),a4
        move.l  (a4),a3              ; a3 = lh_Head (1re requête ou sentinelle)
.svc_loop:
        move.l  (a3),d2              ; d2 = a3->Succ ; 0 => sentinelle tail -> fin
        beq.s   .svc_done
        subq.l  #1,TV_SECS(a3)       ; décompte ce tick
        bgt.s   .svc_cont            ; > 0 -> pas encore expiré
        move.l  a3,a1                ; expiré : Remove(a3)
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1                ; reply(a3) en bas-niveau
        bsr.s   timer_reply
.svc_cont:
        move.l  d2,a3                ; a3 = Succ sauvé (valide même après Remove)
        bra.s   .svc_loop
.svc_done:
        movem.l (sp)+,d0-d2/a0-a4
        rts

; timer_reply(a1 = requête/message, a6 = SysBase) : répond SANS PutMsg/ReplyMsg (pas de Permit).
; Marque NT_REPLYMSG, AddTail au MN_REPLYPORT, Signal la tâche cible si PA_SIGNAL.
timer_reply:
        move.b  #NT_REPLYMSG,LN_TYPE(a1)
        move.l  MN_REPLYPORT(a1),d0
        beq.s   .tr_ret              ; pas de reply port
        move.l  d0,a0                ; a0 = reply port
        movem.l a0/a1,-(sp)
        lea     MP_MSGLIST(a0),a0    ; AddTail(&port->MsgList, msg)
        ; M7c : section critique NUE (Disable INTENA, user-safe) — timer_reply est appelé AUSSI depuis
        ; timer_beginio en USER mode (reply immédiat time==0) où « move #imm,sr » trapperait. Le msglist
        ; peut être partagé entre l'unité VBLANK (IPL3) et MICROHZ (INT6) -> AddTail atomique vs INT6.
        addq.b  #1,EB_IDNEST(a6)
        move.w  #INTF_INTEN,INTENA   ; INTEN off (bit14)
        jsr     LVO_ADDTAIL(a6)
        bsr     raw_enable           ; INTEN on si IDNest<0 (sortie NUE, pas de queue reschedule)
        movem.l (sp)+,a0/a1
        moveq   #0,d0                ; action du port
        move.b  MP_FLAGS(a0),d0
        and.b   #PF_ACTION,d0
        bne.s   .tr_ret              ; != PA_SIGNAL -> pas de signal
        move.l  MP_SIGTASK(a0),d0
        beq.s   .tr_ret
        move.l  d0,a1                ; a1 = tâche à signaler
        moveq   #0,d0
        move.b  MP_SIGBIT(a0),d0
        moveq   #1,d1
        lsl.l   d0,d1
        move.l  d1,d0
        jsr     LVO_SIGNAL(a6)       ; pose les bits + AttnResched (PAS de reschedule ici)
.tr_ret:
        rts

; timer_micro_service(a6 = SysBase ; a1 = IS_DATA, inutilisé) : M7a — vecteur ICR de l'unité
; MICROHZ, appelé par cia_dispatch depuis int6_handler (CIA-B / INT6, IPL7) à chaque underflow
; du timer CIA-B. Miroir de timer_vblank_service mais sur TIMER_MICROQ ; la base device est lue
; dans VBL_SVCDATA. AVANT toute manip : détecte si on a préempté la chirurgie de listes de
; vbl_handler (VBL_INSURG posé) = hazard de ré-entrance de niveau > 3 -> VBL_CLASH++ (= preuve
; que le gate IPL7 de M7a est load-bearing : ce compteur reste 0 avec le fix, > 0 sans).
; Convention serveur ICR : préserve d2/d3/a2 (variables de boucle de cia_dispatch) -> ne
; sauve/clobbe que d0-d2/a0-a4 et ne touche jamais d3/a5.
timer_micro_service:
        tst.b   VBL_INSURG          ; vbl_handler est-il en pleine chirurgie de listes ?
        beq.s   .mic_ok
        addq.l  #1,VBL_CLASH        ; OUI -> INT6 a préempté la section critique = gate violé (RED)
.mic_ok:
        movem.l d0-d2/a0-a4,-(sp)
        move.l  VBL_SVCDATA,a2      ; a2 = base device (lue depuis le hook VBLANK, même base)
        move.l  a2,d0
        beq.s   .mic_done           ; timer non initialisé -> rien
        lea     TIMER_MICROQ(a2),a4
        move.l  (a4),a3             ; a3 = lh_Head (1re requête ou sentinelle)
.mic_loop:
        move.l  (a3),d2             ; d2 = a3->Succ ; 0 => sentinelle tail -> fin
        beq.s   .mic_done
        subq.l  #1,TV_SECS(a3)      ; décompte ce tick CIA-B
        bgt.s   .mic_cont           ; > 0 -> pas encore expiré
        move.l  a3,a1               ; expiré : Remove(a3)
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1               ; reply(a3) bas-niveau (AddTail IPL7 + Signal, sans Permit)
        bsr     timer_reply
.mic_cont:
        move.l  d2,a3              ; a3 = Succ sauvé (valide même après Remove)
        bra.s   .mic_loop
.mic_done:
        movem.l (sp)+,d0-d2/a0-a4
        rts

; struct Interrupt de l'unité MICROHZ : enregistrée sur ciab.resource (ICR bit 0 = timer A) via
; AddICRVector. IS_CODE -> timer_micro_service. IS_DATA inutilisé (le service lit VBL_SVCDATA).
        EVEN
timer_micro_int:
        dcb.b   14,0                ; struct Node (non chaîné ; AddICRVector ne stocke que le ptr)
        dc.l    0                   ; IS_DATA
        dc.l    timer_micro_service ; IS_CODE
        EVEN
timer_end:
