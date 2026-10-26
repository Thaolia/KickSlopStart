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
; UNITÉ MICROHZ (timer B de CIA-A, niveau 2, comme la 1.3 — spec docs/analysis/timer-v34.md) :
;   l'init prend le bit 1 (timer B) de ciaa.resource par AddICRVector ; timer_micro_service est appelé par
;   cia_dispatch (serveur PORTS) à chaque fin de one-shot. Le one-shot est armé sur l'échéance la plus proche ; le
;   temps écoulé est relu sur le compteur. Aucun timer de CIA-B : un jeu qui détourne le vecteur $78 (niveau 6) sans
;   chaîner ne casse plus les délais système. Conversion en µs réelles (E-clock PAL 709379 Hz).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs timer.device + exec + spec docs/analysis/timer-v34.md. AUCUNE lecture ROM.

                include "exec.i"

                xdef    timer_now         ; heure système (dos DateStamp)
                xdef    timer_setnow      ; réglage de l'heure système (globale BCPL setdatstamp)

                xref    newlist           ; lists.s (NEWLIST de la file d'unité)
                xref    ciaa_server       ; cia.s (distribution des vecteurs ICR de CIA-A)

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
timer_cianame:
        dc.b    "ciaa.resource",0
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
        dc.l    timer_addtime        ; LVO -42 AddTime(dest a0, src a1)
        dc.l    timer_subtime        ; LVO -48 SubTime(dest a0, src a1)
        dc.l    timer_cmptime        ; LVO -54 CmpTime(dest a0, src a1) -> d0
        dc.l    -1
timer_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)  ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34          ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(device a6, iorequest a1, unit d0, flags d1) : unité 0 (MICROHZ) ou 1 (VBLANK) -> io_Unit = unité, compte
; d'ouverture + 1 ; unité >= 2 -> io_Error = IOERR_OPENFAIL, rien de compté (comme la 1.3).
timer_open:
        cmp.l   #UNIT_VBLANK,d0
        bhi.s   .to_fail
        move.l  d0,IO_UNIT(a1)
        addq.w  #1,LIB_OPENCNT(a6)
        rts
.to_fail:
        move.b  #IOERR_OPENFAIL,IO_ERROR(a1)
        rts
; Close(device a6, iorequest a1) : io_Device = io_Unit = -1, compte d'ouverture - 1.
timer_close:
        moveq   #-1,d0
        move.l  d0,IO_DEVICE(a1)
        move.l  d0,IO_UNIT(a1)
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
timer_expunge:
        moveq   #0,d0
        rts
timer_null:
        moveq   #0,d0
        rts

; AddTime(dest a0, src a1) : dest += src, puis tant que micro >= 1 000 000 : une seconde reportée (un micro négatif
; n'est pas corrigé, comme en 1.3). SubTime(dest a0, src a1) : dest -= src, puis tant que micro < 0 : une seconde
; empruntée (un micro >= 1 000 000 n'est pas corrigé). Ne lisent pas a6 ; détruisent d0/d1.
timer_addtime:
        move.l  TV_SECS-IO_SIZE(a1),d0
        add.l   d0,TV_SECS-IO_SIZE(a0)
        move.l  TV_MICRO-IO_SIZE(a1),d0
        add.l   TV_MICRO-IO_SIZE(a0),d0
        move.l  #1000000,d1
.at_lp:
        cmp.l   d1,d0
        blt.s   .at_set
        sub.l   d1,d0
        addq.l  #1,TV_SECS-IO_SIZE(a0)
        bra.s   .at_lp
.at_set:
        move.l  d0,TV_MICRO-IO_SIZE(a0)
        rts
timer_subtime:
        move.l  TV_SECS-IO_SIZE(a1),d0
        sub.l   d0,TV_SECS-IO_SIZE(a0)
        move.l  TV_MICRO-IO_SIZE(a0),d0
        sub.l   TV_MICRO-IO_SIZE(a1),d0
.st_lp:
        tst.l   d0
        bpl.s   .st_set
        add.l   #1000000,d0
        subq.l  #1,TV_SECS-IO_SIZE(a0)
        bra.s   .st_lp
.st_set:
        move.l  d0,TV_MICRO-IO_SIZE(a0)
        rts
; CmpTime(dest a0, src a1) -> d0 = 0 si égaux, +1 si src > dest, -1 si src < dest (secondes puis µs, sans signe).
timer_cmptime:
        move.l  TV_SECS-IO_SIZE(a1),d0
        cmp.l   TV_SECS-IO_SIZE(a0),d0
        bne.s   .ct_diff
        move.l  TV_MICRO-IO_SIZE(a1),d0
        cmp.l   TV_MICRO-IO_SIZE(a0),d0
        bne.s   .ct_diff
        moveq   #0,d0
        rts
.ct_diff:
        bhi.s   .ct_gt
        moveq   #-1,d0
        rts
.ct_gt:
        moveq   #1,d0
        rts

; BeginIO(device a6, iorequest a1) : M6a — enqueue une requête TR_ADDREQUEST sur l'unité VBLANK.
; Convertit la timeval en ticks (secs*50 + micro/20000, mini 1), stocke le décompte dans TV_SECS.
; Disable autour (file partagée avec le handler VBlank).
; timer_systime(a2 = base timer.device, a6 = SysBase) -> d0 = secondes, d1 = µs de l'heure système : secondes à la
; référence (TR_SETSYSTIME) + trames écoulées depuis (50 Hz), plus 1 µs par lecture déjà faite dans la même trame :
; deux lectures successives ne rendent jamais la même heure (comme la 1.3). Préserve d2-d7/a0-a6.
timer_systime:
        move.l  d2,-(sp)
        jsr     LVO_DISABLE(a6)
        move.l  VBL_COUNT,d0
        cmp.l   TIMER_UVBL(a2),d0
        beq.s   .sy_same
        move.l  d0,TIMER_UVBL(a2)
        clr.l   TIMER_UNIQ(a2)
.sy_same:
        move.l  TIMER_UNIQ(a2),-(sp)
        addq.l  #1,TIMER_UNIQ(a2)
        jsr     LVO_ENABLE(a6)
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
        add.l   (sp)+,d1             ; + rang de la lecture dans la trame
        add.l   TIMER_SYSSECS(a2),d2
        move.l  d2,d0
        move.l  (sp)+,d2
        rts

; timer_setsys(a2 = base, d0 = secondes, d1 = µs) : nouvelle référence ; l'heure système vaut ensuite
; d0 + (VBL_COUNT - référence) / 50. Clobbe d0/d1.
timer_setsys:
        clr.l   TIMER_UNIQ(a2)
        move.l  VBL_COUNT,TIMER_UVBL(a2)
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
        jsr     LVO_DISABLE(a6)      ; files partagées avec le serveur VBlank et l'interruption du CIA-A
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
        move.l  TV_SECS(a3),d0       ; VBLANK : échéance au k-ième VBLANK, k = max(1, ⌈T / 20000 µs⌉)
        move.l  TV_MICRO(a3),d1
        mulu    #50,d0
        add.l   #20000-1,d1
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

; tm_account(a2 = base, a6 = SysBase ; sous Disable ou dans l'interruption) : arrête le timer B de CIA-A, impute le temps
; écoulé depuis son armement à chaque requête MICROHZ, répond à celles qui sont échues. Clobbe d0-d2/a0/a1/a3/a4.
tm_account:
        move.l  TIMER_ARMED(a2),d2
        beq.s   .ta_ret
        clr.l   TIMER_ARMED(a2)
        lea     CIAA_HW,a0
        btst    #0,CIA_CRB(a0)
        beq.s   .ta_spent            ; START retombé : le one-shot est arrivé au bout
        bclr    #0,CIA_CRB(a0)       ; arrêt (compteur figé) : seul START, comme la 1.3
        moveq   #0,d0
        move.b  CIA_TBHI(a0),d0
        lsl.w   #8,d0
        move.b  CIA_TBLO(a0),d0
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

; tm_rearm(a2 = base ; timer arrêté par tm_account) : arme le one-shot sur l'échéance la plus proche, au plus
; TIMER_CAP ticks ; file vide : timer laissé arrêté. Clobbe d0/d2/a0.
tm_rearm:
        lea     TIMER_MICROQ(a2),a0
        move.l  (a0),a0
        tst.l   (a0)
        beq.s   .tr_ret
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
        lea     CIAA_HW,a0
        move.b  d2,CIA_TBLO(a0)
        move.w  d2,d0
        lsr.w   #8,d0
        move.b  d0,CIA_TBHI(a0)      ; one-shot : l'écriture du poids fort charge le compteur
        move.b  #$19,CIA_CRB(a0)     ; START + one-shot + LOAD, horloge E, ALARM = 0 (TOD en mode heure)
        move.l  d2,TIMER_ARMED(a2)
.tr_ret:
        rts

; AbortIO(device a6, iorequest a1) -> d0 : une requête encore en file (ln_Type = NT_MESSAGE et IOF_QUICK à 0) est
; retirée et rendue avec io_Error = IOERR_ABORTED, d0 = 0 ; une requête qui n'est pas en file est laissée telle
; quelle, d0 = -1 (comme en 1.3).
; (Sans ce retrait, une requête abandonnée par un programme qui se termine expirait plus tard et répondait sur son
; port libéré, dans de la mémoire réutilisée.)
timer_abortio:
        movem.l a2/a6,-(sp)
        move.l  a1,a2
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        moveq   #-1,d0
        cmp.b   #NT_MESSAGE,LN_TYPE(a2)
        bne.s   .ab_done
        btst    #0,IO_FLAGS(a2)      ; IOF_QUICK : terminée sur place (DoIO), jamais mise en file -> rien à retirer
        bne.s   .ab_done
        move.l  a2,a1
        jsr     LVO_REMOVE(a6)
        move.b  #IOERR_ABORTED,IO_ERROR(a2)
        move.l  a2,a1
        jsr     LVO_REPLYMSG(a6)
        moveq   #0,d0
.ab_done:
        move.l  d0,-(sp)
        jsr     LVO_ENABLE(a6)
        move.l  (sp)+,d0
        movem.l (sp)+,a2/a6
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
        lea     TIMER_MICROQ(a1),a1  ; NEWLIST file d'unité MICROHZ (timer B de CIA-A)
        jsr     newlist
        move.l  (sp)+,d0             ; base
        move.l  d0,VBL_SVCDATA       ; data = base device (lue aussi par timer_micro_service)
        ; M7f : timer_vblank devient un SERVEUR de la chaîne VERTB (remplace l'ancien hook VBL_SVC).
        ; struct Interrupt en RAM basse réservée (AddIntServer l'Enqueue). pri 0 : après sched_server(20).
        move.b  #0,TIMER_VBL_INT+LN_PRI
        move.l  d0,TIMER_VBL_INT+IS_DATA        ; IS_DATA = base device -> passée en a1 au service
        move.l  #timer_vblank_service,TIMER_VBL_INT+IS_CODE
        move.l  d0,-(sp)             ; sauve la base (AddIntServer clobbe d0/d1/a0/a1)
        moveq   #INTB_VERTB,d0       ; AddIntServer(VERTB, &TIMER_VBL_INT)
        lea     TIMER_VBL_INT,a1
        jsr     LVO_ADDINTSERVER(a6)
        move.b  #$08,CIAA_HW+CIA_CRB ; timer B de CIA-A : one-shot, horloge E, arrêté
        lea     timer_cianame(pc),a1 ; MICROHZ : bit 1 (timer B) de ciaa.resource -> niveau 2
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq.s   .ti_nocia
        move.l  a6,-(sp)
        move.l  d0,a6
        moveq   #1,d0
        lea     timer_micro_int(pc),a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        move.l  (sp)+,d0             ; d0 = base (valeur de retour inchangée)
        rts
.ti_nocia:
        move.l  d7,-(sp)
        move.l  #AN_TIMERCIARSRC,d7  ; ciaa.resource absente : comme la 1.3, alerte et pas de timer.device
        jsr     LVO_ALERT(a6)
        move.l  (sp)+,d7
        addq.l  #4,sp
        moveq   #0,d0
        rts

; timer_vblank_service(a1 = IS_DATA = base device, a6 = SysBase) : M7f — SERVEUR de la chaîne VERTB
; (plus un hook). Décrémente chaque requête de la file VBLANK ; à 0 -> Remove + ReplyMsg (M7i :
; interrupt-safe, sans Permit). Convention serveur : préserve d2-d7/a2-a4 (movem d0-d2/a0-a4 couvre
; d2/a2-a4 ; ne touche PAS d3-d7/a5) et retourne Z-SET (d0=0) = « continue la chaîne » (call-all).
timer_vblank_service:
        movem.l d0-d2/a0-a5,-(sp)
        move.l  a1,a2                ; a2 = base device
        tst.b   INT2_BUSY            ; reprise d'une interruption de CIA-A perdue : one-shot MICROHZ armé, arrivé au
        bne.s   .svc_vbl             ; bout (START retombé), et aucune interruption de niveau 2 en cours pour le servir
        tst.l   TIMER_ARMED(a2)      ; (événement d'ICR perdu : course de lecture du 8520, ou file d'événements pleine
        beq.s   .svc_vbl             ; sous FS-UAE). Le CIA-A garderait sinon son bit IR levé et ne demanderait plus
        btst    #0,CIAA_HW+CIA_CRB   ; jamais d'interruption (clavier compris) : on lit l'ICR et on distribue ici.
        bne.s   .svc_vbl
        jsr     ciaa_server
.svc_vbl:
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
        movem.l (sp)+,d0-d2/a0-a5
        moveq   #0,d0               ; M7f : Z-SET -> « continue la chaîne » (serveur call-all VERTB)
        rts

; M7i : timer_reply (routine bespoke M7c) SUPPRIMÉE — remplacée par ReplyMsg. M7d a rendu PutMsg/GetMsg/
; ReplyMsg interrupt-safe (Disable INTENA + raw_enable, SANS tail Permit/yield), donc le hack bas-niveau
; qui évitait le reschedule synchrone de Permit n'a plus de raison d'être : les services VBLANK/MICROHZ
; appellent directement LVO_REPLYMSG (AddTail + Signal + marque NT_REPLYMSG, atomique, aucun yield en IRQ).

; timer_micro_service(a6 = SysBase ; a1 = IS_DATA, inutilisé) : vecteur ICR bit 1 de ciaa.resource, appelé par
; cia_dispatch (serveur PORTS, niveau 2) à chaque fin de one-shot du timer B de CIA-A. Base lue dans VBL_SVCDATA.
; Convention vecteur ICR : préserve d2/d3/a2 (variables de boucle de cia_dispatch).
timer_micro_service:
        movem.l d0-d2/a0-a4,-(sp)
        move.l  VBL_SVCDATA,a2
        move.l  a2,d0
        beq.s   .mic_ret             ; timer non initialisé -> rien
        bsr     tm_account
        bsr     tm_rearm
.mic_ret:
        movem.l (sp)+,d0-d2/a0-a4
        rts

; struct Interrupt de l'unité MICROHZ : enregistrée sur ciaa.resource (ICR bit 1 = timer B) via AddICRVector.
; IS_CODE -> timer_micro_service. IS_DATA inutilisé (le service lit VBL_SVCDATA).
        EVEN
timer_micro_int:
        dcb.b   14,0                ; struct Node (non chaîné ; AddICRVector ne stocke que le ptr)
        dc.l    0                   ; IS_DATA
        dc.l    timer_micro_service ; IS_CODE
        EVEN
timer_end:
