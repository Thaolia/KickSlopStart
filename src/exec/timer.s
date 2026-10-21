; src/exec/timer.s — timer.device — M5c (création AUTOINIT) + M6a (unité VBLANK fonctionnelle).
; 2e vrai module résident, 1er DEVICE. ROMTag RTF_AUTOINIT (pri 50) -> chemin AUTOINIT de
; InitResident (MakeLibrary + Enqueue DeviceList). Quirk V34 : la data table pose LN_TYPE +
; LIB_VERSION et l'init func pose LN_NAME="timer.device" + initialise l'unité VBLANK + enregistre
; le service VBlank (M7f : timer_vblank_service est un SERVEUR de la chaîne VERTB via AddIntServer,
; dispatché par int3_dispatch — plus l'ancien hook VBL_SVC).
;
; M6a — UNITÉ VBLANK FONCTIONNELLE (sans CIA) :
;   BeginIO(TR_ADDREQUEST) : convertit la timeval en TICKS (secs*50 + micro/20000), stocke le
;     décompte dans TR_TIME, enqueue la requête sur la file de l'unité VBLANK. Disable autour de
;     la manip (la file est partagée avec le handler VBlank = interruption, pas juste des tâches).
;   timer_vblank_service : appelé depuis le handler VBlank (IPL 3) chaque tick. Décrémente chaque
;     requête ; à 0 -> la retire et répond via ReplyMsg (M7i). HISTORIQUE : jusqu'en M7h la réponse
;     utilisait une routine bespoke (timer_reply) car PutMsg/ReplyMsg appelaient Permit (reschedule
;     SYNCHRONE interdit en interruption). M7d a rendu PutMsg/ReplyMsg interrupt-safe (Disable INTENA +
;     raw_enable, SANS tail Permit/yield) -> M7i a supprimé timer_reply et appelle directement ReplyMsg.
;     Signal (via PutMsg) pose AttnResched sans rescheduler -> le switch se fait à la sortie du handler.
; M7a — UNITÉ MICROHZ (via CIA-B / INT6) :
;   2e file d'unité (TIMER_MICROQ) décrémentée par timer_micro_service, enregistré comme vecteur
;   ICR du timer A de ciab.resource (déclenché à chaque underflow CIA-B -> INT6 niveau 6). BeginIO
;   route par IO_UNIT (0=MICROHZ, 1=VBLANK). Prouve une TÂCHE qui BLOQUE sur un timer (Wait->wake
;   par l'IRQ MICROHZ) ET le GATE DE RÉ-ENTRANCE : INT6 (niveau 6 > VBlank 3) peut préempter
;   vbl_handler ; sa chirurgie de listes est désormais IPL7 (interrupts.s). Le service pose le
;   détecteur VBL_CLASH si jamais il observe vbl_handler en pleine chirurgie (= 0 avec le fix).
; M7l — CALIBRATION µs RÉELLE MICROHZ : timer_beginio convertit TV_MICRO en interruptions CIA-B via
;   US_PER_INT/INTS_PER_SEC (E-clock PAL 709379 Hz / latch 255 ≈ 359 µs/int) au lieu du facteur VBLANK
;   /20000. TV_MICRO signifie donc des µs réelles, à la résolution d'une interruption (≈ 360 µs). Prouvé
;   par inter-horloges : une requête de 0,5 s s'écoule en ~25 ticks VBLANK (horloge display indépendante).
; DIFFÉRÉ (ledgeré) : unité ECLOCK + résolution SUB-interruption (lecture live du latch E, < 360 µs),
;   OpenDevice (la preuve remplit IO_DEVICE/IO_UNIT à la main), conversion timeval complète.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs timer.device + exec. AUCUNE lecture ROM.

                include "exec.i"

                xdef    timer_now         ; heure système (dos DateStamp)
                xdef    timer_setnow      ; réglage de l'heure système (globale BCPL setdatstamp)
                xdef    timer_micro_int   ; M7a : struct Interrupt de l'unité MICROHZ (vecteur ICR CIA-B)
                xdef    timer_micro_start ; premier armement du one-shot MICROHZ (boot, après AddICRVector)

                xref    newlist           ; lists.s (NEWLIST de la file d'unité)

; --- ROMTag timer.device (scanné par build_reslist) ---
        EVEN
timer_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    timer_romtag         ; RT_MATCHTAG = self
        dc.l    timer_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,50  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
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
; timer_systime(a2 = base timer.device) -> d0 = secondes, d1 = µs de l'heure système : secondes à la référence
; (TR_SETSYSTIME) + trames écoulées depuis (50 Hz). Préserve d2-d7/a0-a6.
timer_systime:
        move.l  d2,-(sp)
        move.l  VBL_COUNT,d0
        sub.l   TIMER_SYSVBL(a2),d0  ; ticks écoulés depuis la référence (division 32/16 en deux temps)
        swap    d0
        moveq   #0,d1
        move.w  d0,d1
        divu    #50,d1               ; mot haut
        move.w  d1,d2
        swap    d2
        swap    d0
        move.w  d0,d1                ; reste:mot bas
        divu    #50,d1
        move.w  d1,d2                ; d2 = secondes écoulées
        swap    d1
        mulu    #20000,d1            ; reste (ticks) -> µs
        add.l   TIMER_SYSSECS(a2),d2
        move.l  d2,d0
        move.l  (sp)+,d2
        rts

; timer_setsys(a2 = base, d0 = secondes, d1 = µs) : nouvelle référence ; l'heure système vaut ensuite
; d0 + (VBL_COUNT - référence) / 50. Clobbe d0/d1.
timer_setsys:
        move.l  d0,TIMER_SYSSECS(a2)
        divu    #20000,d1
        and.l   #$0000FFFF,d1
        move.l  VBL_COUNT,d0
        sub.l   d1,d0
        move.l  d0,TIMER_SYSVBL(a2)
        rts

; timer_setnow(a6 = SysBase, d0 = secondes, d1 = µs) : règle l'heure système (TR_SETSYSTIME sans IORequest).
; Préserve d2-d7/a2-a6.
timer_setnow:
        movem.l d0-d1/a2,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     timer_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,a2
        movem.l (sp)+,d0-d1
        cmpa.w  #0,a2
        beq.s   .ts_ret
        bsr.s   timer_setsys
.ts_ret:
        move.l  (sp)+,a2
        rts

; timer_now(a6 = SysBase) -> d0 = secondes, d1 = µs de l'heure système (0 / 0 sans timer.device). Pour DateStamp.
; Préserve d2-d7/a2-a6.
timer_now:
        move.l  a2,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     timer_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .tn_none
        move.l  d0,a2
        bsr     timer_systime
        move.l  (sp)+,a2
        rts
.tn_none:
        moveq   #0,d1
        move.l  (sp)+,a2
        rts

timer_beginio:
        movem.l d2/a2-a4,-(sp)
        move.l  a6,a2                ; a2 = base device
        move.l  a1,a3                ; a3 = iorequest
        move.l  ($4).w,a6            ; a6 = SysBase (pour les appels exec)
        clr.b   IO_ERROR(a3)
        move.w  IO_COMMAND(a3),d0
        cmp.w   #TR_ADDREQUEST,d0
        beq.s   .bio_add
        cmp.w   #TR_GETSYSTIME,d0
        beq.s   .bio_get
        cmp.w   #TR_SETSYSTIME,d0
        beq.s   .bio_set
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
        bra.s   .bio_done
.bio_set:
        move.l  TV_SECS(a3),d0
        move.l  TV_MICRO(a3),d1
        bsr     timer_setsys
        bra.s   .bio_done
.bio_get:
        bsr     timer_systime
        move.l  d0,TV_SECS(a3)
        move.l  d1,TV_MICRO(a3)
.bio_done:
        btst    #0,IO_FLAGS(a3)      ; IOF_QUICK : terminé sur place ; sinon réponse au reply port
        bne.s   .bio_ret
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
.bio_ret:
        move.l  a2,a6
        movem.l (sp)+,d2/a2-a4
        rts
.bio_add:
        jsr     LVO_DISABLE(a6)      ; files partagées avec le serveur VBlank et l'INT6 du CIA-B
        move.b  #NT_MESSAGE,LN_TYPE(a3)
        bclr    #0,IO_FLAGS(a3)      ; requête mise en file : jamais rapide (DoIO attendra la réponse)
        cmp.l   #UNIT_VBLANK,IO_UNIT(a3)
        beq.s   .bio_vbl
        bsr     tm_conv              ; MICROHZ : reste en (secondes, ticks E)
        move.l  a3,-(sp)
        bsr     tm_account           ; temps écoulé imputé aux requêtes déjà en file AVANT d'ajouter celle-ci
        move.l  (sp)+,a1
        lea     TIMER_MICROQ(a2),a0
        jsr     LVO_ADDTAIL(a6)
        bsr     tm_rearm
        bra.s   .bio_queued
.bio_vbl:
        move.l  TV_SECS(a3),d0       ; VBLANK : décompte en ticks 50 Hz (1 tick = 20000 µs)
        move.l  TV_MICRO(a3),d1
        mulu    #50,d0
        divu    #20000,d1
        and.l   #$0000FFFF,d1        ; quotient divu (mot bas)
        add.l   d1,d0
        bne.s   .bio_store
        moveq   #1,d0                ; mini 1 (évite expiration immédiate)
.bio_store:
        move.l  d0,TV_SECS(a3)       ; décompte (TV_SECS réutilisé)
        clr.l   TV_MICRO(a3)
        lea     TIMER_VBLQ(a2),a0
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)
.bio_queued:
        jsr     LVO_ENABLE(a6)
        move.l  a2,a6                ; restaure a6 = base device
        movem.l (sp)+,d2/a2-a4
        rts

; tm_div1000(d0 = dividende) -> d0 = quotient, d1 = reste de la division par 1000. Préserve d2-d7/a0-a6.
tm_div1000:
        move.l  d2,-(sp)
        moveq   #0,d1
        swap    d0
        move.w  d0,d1
        divu    #1000,d1             ; d1 = reste : quotient du mot haut
        move.w  d1,d2
        swap    d0
        move.w  d0,d1                ; reste : mot bas
        divu    #1000,d1
        swap    d2
        move.w  d1,d2                ; d2 = quotient complet
        clr.w   d1
        swap    d1                   ; d1 = reste
        move.l  d2,d0
        move.l  (sp)+,d2
        rts

; tm_conv(a3 = requête MICROHZ) : timeval -> reste (TV_SECS secondes, TV_MICRO ticks E dans la seconde), au moins
; 1 tick. µs normalisées (>= 1 s reportées dans les secondes). Clobbe d0/d1.
tm_conv:
                ifne    M7L_OLD_CONV
        move.l  TV_SECS(a3),d0       ; RED : ancienne conversion VBLANK (/20000) appliquée à des pas de 255 ticks
        mulu    #50,d0
        move.l  TV_MICRO(a3),d1
        divu    #20000,d1
        and.l   #$0000FFFF,d1
        add.l   d1,d0
        mulu    #255,d0
        clr.l   TV_SECS(a3)
                else
        move.l  TV_MICRO(a3),d0
        bsr.s   tm_div1000           ; d0 = ms, d1 = µs (0-999)
        move.l  d1,-(sp)
        bsr.s   tm_div1000           ; d0 = secondes en plus, d1 = ms (0-999)
        add.l   d0,TV_SECS(a3)
        move.l  d1,d0
        mulu    #E_PER_SEC/1000,d0   ; ms -> ticks : ms × 709,379
        mulu    #E_PER_SEC//1000,d1
        divu    #1000,d1
        and.l   #$0000FFFF,d1
        add.l   d1,d0
        move.l  (sp)+,d1
        mulu    #E_PER_SEC/1000,d1   ; µs -> ticks : µs × 0,709
        divu    #1000,d1
        and.l   #$0000FFFF,d1
        add.l   d1,d0
                endc
        tst.l   TV_SECS(a3)
        bne.s   .tc_set
        tst.l   d0
        bne.s   .tc_set
        moveq   #1,d0
.tc_set:
        move.l  d0,TV_MICRO(a3)
        rts

; tm_account(a2 = base, a6 = SysBase ; INT6 masquée) : arrête le timer A de CIA-B, impute le temps écoulé depuis son
; armement à chaque requête MICROHZ, répond à celles qui sont échues. Clobbe d0-d2/a0/a1/a3/a4.
tm_account:
        move.l  TIMER_ARMED(a2),d2
        beq.s   .ta_ret
        clr.l   TIMER_ARMED(a2)
        lea     CIAB_HW,a0
        btst    #0,CIA_CRA(a0)
        beq.s   .ta_spent            ; START retombé : le one-shot est arrivé au bout
        move.b  #$08,CIA_CRA(a0)     ; arrêt (compteur figé)
        moveq   #0,d0
        move.b  CIA_TAHI(a0),d0
        lsl.w   #8,d0
        move.b  CIA_TALO(a0),d0
        cmp.l   d2,d0
        bhs.s   .ta_spent            ; compteur rechargé : arrivé au bout juste avant l'arrêt
        sub.l   d0,d2                ; écoulé = armé - restant
.ta_spent:
        lea     TIMER_MICROQ(a2),a3
        move.l  (a3),a3
.ta_loop:
        move.l  (a3),a4              ; a4 = suivant (0 : sentinelle de fin)
        cmpa.w  #0,a4
        beq.s   .ta_ret
        move.l  TV_MICRO(a3),d0
        sub.l   d2,d0
        bpl.s   .ta_nb
        add.l   #E_PER_SEC,d0        ; emprunt d'une seconde (écoulé < 1 s)
        subq.l  #1,TV_SECS(a3)
.ta_nb:
        move.l  d0,TV_MICRO(a3)
        tst.l   TV_SECS(a3)
        bmi.s   .ta_exp
        bne.s   .ta_next
        tst.l   d0
        bne.s   .ta_next
.ta_exp:
        move.l  a3,a1
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)     ; interrupt-safe (Disable/raw_enable, pas de yield)
.ta_next:
        move.l  a4,a3
        bra.s   .ta_loop
.ta_ret:
        rts

; tm_rearm(a2 = base ; INT6 masquée, timer arrêté par tm_account) : arme le one-shot sur l'échéance la plus proche,
; au plus TIMER_CAP ticks. File vide : arrêté en production, TIMER_IDLE en dev (INT6 périodique des preuves M7).
; Clobbe d0/d2/a0.
tm_rearm:
        lea     TIMER_MICROQ(a2),a0
        move.l  (a0),a0
        tst.l   (a0)
                ifne    PROD
        beq.s   .tr_ret
                else
        bne.s   .tr_some
        move.l  #TIMER_IDLE,d2
        bra.s   .tr_arm
.tr_some:
                endc
        move.l  #TIMER_CAP,d2
.tr_loop:
        tst.l   (a0)
        beq.s   .tr_arm
        tst.l   TV_SECS(a0)
        bne.s   .tr_next             ; au moins 1 s : plafond
        move.l  TV_MICRO(a0),d0
        cmp.l   d2,d0
        bhs.s   .tr_next
        move.l  d0,d2
.tr_next:
        move.l  (a0),a0
        bra.s   .tr_loop
.tr_arm:
        lea     CIAB_HW,a0
        move.b  d2,CIA_TALO(a0)
        move.w  d2,d0
        lsr.w   #8,d0
        move.b  d0,CIA_TAHI(a0)      ; one-shot : l'écriture du poids fort charge le compteur
        move.b  #$19,CIA_CRA(a0)     ; START + one-shot + LOAD
        move.l  d2,TIMER_ARMED(a2)
.tr_ret:
        rts

; timer_micro_start : premier armement du timer MICROHZ, une fois le vecteur ICR de CIA-B posé. Préserve tout.
timer_micro_start:
        movem.l d0-d2/a0-a2/a6,-(sp)
        move.l  ($4).w,a6
        move.l  VBL_SVCDATA,a2
        jsr     LVO_DISABLE(a6)
        bsr     tm_rearm
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,d0-d2/a0-a2/a6
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
        move.l  d0,VBL_SVCDATA       ; data = base device (lue aussi par timer_micro_service, INT6)
        ; M7f : timer_vblank devient un SERVEUR de la chaîne VERTB (remplace l'ancien hook VBL_SVC).
        ; struct Interrupt en RAM basse réservée (AddIntServer l'Enqueue). pri 0 : après sched_server(20).
        move.b  #0,TIMER_VBL_INT+LN_PRI
        move.l  d0,TIMER_VBL_INT+IS_DATA        ; IS_DATA = base device -> passée en a1 au service
        move.l  #timer_vblank_service,TIMER_VBL_INT+IS_CODE
        move.l  d0,-(sp)             ; sauve la base (AddIntServer clobbe d0/d1/a0/a1)
        moveq   #INTB_VERTB,d0       ; AddIntServer(VERTB, &TIMER_VBL_INT)
        lea     TIMER_VBL_INT,a1
        jsr     LVO_ADDINTSERVER(a6)
        move.l  (sp)+,d0             ; d0 = base (valeur de retour inchangée)
        rts

; timer_vblank_service(a1 = IS_DATA = base device, a6 = SysBase) : M7f — SERVEUR de la chaîne VERTB
; (plus un hook). Décrémente chaque requête de la file VBLANK ; à 0 -> Remove + ReplyMsg (M7i :
; interrupt-safe, sans Permit). Convention serveur : préserve d2-d7/a2-a4 (movem d0-d2/a0-a4 couvre
; d2/a2-a4 ; ne touche PAS d3-d7/a5) et retourne Z-SET (d0=0) = « continue la chaîne » (call-all).
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
        move.l  a3,a1                ; M7i : ReplyMsg(a3) — interrupt-safe depuis M7d (Disable/raw_enable,
        jsr     LVO_REPLYMSG(a6)     ; PAS de Permit/yield) ; préserve d2/a2/a4 (invariants de boucle)
.svc_cont:
        move.l  d2,a3                ; a3 = Succ sauvé (valide même après Remove)
        bra.s   .svc_loop
.svc_done:
        movem.l (sp)+,d0-d2/a0-a4
        moveq   #0,d0               ; M7f : Z-SET -> « continue la chaîne » (serveur call-all VERTB)
        rts

; M7i : timer_reply (routine bespoke M7c) SUPPRIMÉE — remplacée par ReplyMsg. M7d a rendu PutMsg/GetMsg/
; ReplyMsg interrupt-safe (Disable INTENA + raw_enable, SANS tail Permit/yield), donc le hack bas-niveau
; qui évitait le reschedule synchrone de Permit n'a plus de raison d'être : les services VBLANK/MICROHZ
; appellent directement LVO_REPLYMSG (AddTail + Signal + marque NT_REPLYMSG, atomique, aucun yield en IRQ).

; timer_micro_service(a6 = SysBase ; a1 = IS_DATA, inutilisé) : M7a — vecteur ICR de l'unité
; MICROHZ, appelé par cia_dispatch depuis int6_dispatch (CIA-B / INT6, IPL natif 6 depuis M7e) à chaque
; underflow du timer CIA-B. Miroir de timer_vblank_service mais sur TIMER_MICROQ ; la base device est
; lue dans VBL_SVCDATA. AVANT toute manip, DEUX détecteurs exclusifs (M7a + M7e) :
;   - VBL_INSURG posé -> INT6 a préempté la CHIRURGIE du switch -> VBL_CLASH++ (doit rester 0 : le Disable
;     la rend atomique vs tout IPL ; > 0 = RED1, Disable retiré).
;   - sinon VBL_INBODY posé -> INT6 a préempté le CORPS de vbl -> VBL_PREEMPT_COUNT++ (doit être > 0 :
;     preuve que vbl tourne bien à IPL3 natif, pas IPL7 ; == 0 = RED2, IPL7 remis au prologue).
; Convention serveur ICR : préserve d2/d3/a2 (variables de boucle de cia_dispatch) -> ne
; sauve/clobbe que d0-d2/a0-a4 et ne touche jamais d3/a5.
timer_micro_service:
        tst.b   VBL_INSURG          ; vbl_handler est-il en pleine CHIRURGIE de listes ?
        beq.s   .mic_notsurg
        addq.l  #1,VBL_CLASH        ; OUI -> INT6 a préempté la section critique = Disable violé (RED1)
        bra.s   .mic_ok             ; doit rester 0 : le Disable rend la chirurgie atomique vs tout IPL
.mic_notsurg:
        tst.b   VBL_INBODY          ; M7e : sinon, vbl est-il dans son CORPS (hors chirurgie) ?
        beq.s   .mic_ok
        addq.l  #1,VBL_PREEMPT_COUNT ; OUI -> INT6(6) a préempté le CORPS de vbl(3) = fidélité IPL-par-niveau
.mic_ok:                            ; (doit être > 0 en GREEN ; == 0 si on remet IPL7 au prologue = RED2)
        movem.l d0-d2/a0-a4,-(sp)
        move.l  VBL_SVCDATA,a2      ; a2 = base device (lue depuis le hook VBLANK, même base)
        move.l  a2,d0
        beq.s   .mic_done           ; timer non initialisé -> rien
        bsr     tm_account
        bsr     tm_rearm
.mic_done:
        ; M7d : stress du PORT PARTAGÉ (producteur INTERRUPTION) -> course vs task_port (consommateur
        ; TÂCHE). GetMsg/PutMsg sont interrupt-safe (Disable) depuis M7d -> aucune corruption. En RED
        ; (ports remis en Forbid) cette course corrompt la liste du port. Scratch d0/a0/a1 (dans le
        ; budget movem d0-d2/a0-a4 ; a6=SysBase ; la marche de file est terminée -> a2-a4/d2 libres).
        move.l  WP_SPORT,d0
        beq.s   .mic_ret            ; port pas encore créé
        addq.b  #1,STRESS_TICK      ; rate-limit : 1 INT6 sur 4 (allège la charge sur task_timer sans
        move.b  STRESS_TICK,d1      ; tuer le taux de collision ; le RED se joue sur une longue fenêtre)
                ifne    M7D_STRESS_MAX
        and.b   #0,d1               ; RED A/B : chaque INT6 (contention max)
                else
        and.b   #3,d1               ; normal : 1 INT6 sur 4
                endc
        bne.s   .mic_ret
        move.l  d0,a0
        jsr     LVO_GETMSG(a6)      ; GetMsg(SP)
        tst.l   d0
        beq.s   .mic_ret            ; vide (les 2 acteurs tiennent tout) -> rien
        move.l  d0,a1
        cmp.l   #STRESS_MAGIC,MSG_MAGIC_OFF(a1)
        bne.s   .mic_pfail          ; mauvais pointeur -> corruption de liste
        tst.l   MSG_INHAND_OFF(a1)
        bne.s   .mic_pfail          ; déjà « en main » -> doublon = corruption
        move.l  #1,MSG_INHAND_OFF(a1)
        clr.l   MSG_INHAND_OFF(a1)
        move.l  WP_SPORT,a0
        jsr     LVO_PUTMSG(a6)      ; PutMsg(SP, msg)
        addq.l  #1,WP_PORTI
        bra.s   .mic_ret
.mic_pfail:
        st      WP_PORTFAIL         ; corruption détectée côté interruption
.mic_ret:
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
