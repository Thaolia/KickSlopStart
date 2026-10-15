; src/exec/boot.s — exec.library : en-tête ROM, coldstart, build ExecBase,
; publication de SysBase, auto-vérification + auto-test. Module « glue » du
; coldstart (M2.3 : extrait de l'ancien coldstart.s monolithique).
; Piste IMPLÉMENTATION (« clean ») : écrit depuis docs/analysis/exec-spec.md +
; ABI publique. AUCUNE lecture de la ROM.
;
; Reset $FC00D2 -> superviseur + gel HW (ROUGE) -> coupe overlay + pile (BLEU)
; -> ExecBase + jump table (CYAN) -> publie SysBase, auto-vérif + auto-test des
; fonctions via la jump table -> BLANC si tout passe, MAGENTA sinon.
;
; Couleur -> phase (débogueur visuel) : rouge=entré, bleu=overlay off/pile,
; cyan=build ExecBase+table, blanc=SUCCÈS, magenta=échec d'une vérification.

                include "exec.i"

                xref    newlist          ; lists.s
                xref    build_jumptable  ; library.s
                xref    init_memory      ; memory.s
                xref    init_task        ; tasks.s
                xref    init_ints        ; interrupts.s
                xref    dispatch_in      ; interrupts.s (M7c : lancement 1re tâche = transition user-mode)
                xref    build_reslist    ; resident.s (scan des ROMTags)
                xref    timer_micro_int  ; timer.s (struct Interrupt de l'unité MICROHZ, vecteur ICR CIA-B)
                xref    ciaa_server      ; cia.s (serveur PORTS/INT2)
                xref    ciab_server      ; cia.s (serveur EXTER/INT6, vecteur exclusif)

DEMO_STK     EQU 2048         ; pile des tâches démo (frames de switch)
DEMO_SIG     EQU 16           ; bit de signal de task_H (hors 0-15 réservés système)
DEMO_PRI_H   EQU 10           ; task_H : haute priorité (cible du yield-sur-Permit)
DEMO_PRI_T   EQU 10           ; task_timer (M7a) : même pri que task_H -> partagent les dispatches
CONS_THRESH  EQU 100          ; réveils de task_H (via yield) requis pour « M3F LIVE »
SPIN_THRESH  EQU 5            ; itérations de task_S (via préemption) requises pour « M3F LIVE »
TCONS_THRESH EQU 50           ; réveils de task_timer (via l'IRQ MICROHZ) requis pour « M7A TIMER OK »
M7A_MINTICKS EQU 250          ; ET délai minimum (ticks VBlank = 5 s) écoulé avant d'émettre OK :
                              ; le détecteur de clash tourne à chaque INT6 (~2/s), donc en RED un
                              ; clash tombe BIEN AVANT 5 s -> « M7A FAILED » précède, OK n'apparaît pas.
                ifne    M7D_STRESS_MAX
DEMO_PRI_P   EQU 20           ; RED A/B : task_port martèle le port (contention max vs IRQ)
                else
DEMO_PRI_P   EQU 0            ; task_port (M7d) : pri 0 -> partage le CPU équitablement avec task_S/L
                endc
STRESS_K     EQU 4            ; nb de messages de stress circulant sur le port partagé
PORTT_THRESH EQU 60           ; itérations GetMsg+PutMsg de task_port requises pour « M7D PORTS OK »
PORTI_THRESH EQU 300          ; itérations côté interruption requises (producteur rapide ~INT6)
PEMPTY_LIMIT EQU 50000        ; M7d : GetMsg vides consécutifs = nœuds perdus (corruption) ; GREEN ~0
SENT_H       EQU $CAFE0010    ; sentinelles de contexte (doivent survivre à TOUT switch)
SENT_L       EQU $CAFE0020
SENT_S       EQU $CAFE0030
SENT_T       EQU $CAFE0040    ; sentinelle de task_timer (M7a)
SENT_P       EQU $CAFE0050    ; sentinelle de task_port (M7d)
CIAB_LATCH_HI EQU $00         ; latch timer A CIA-B = $00FF (~255 ticks E-clock ≈ 360 us/IRQ)
CIAB_LATCH_LO EQU $FF
; (FTEST_LO/FTEST_HI, région de test multi-header, sont dans exec.i — carte mémoire)

; L'en-tête doit atterrir à $FC0000 : boot.o est le PREMIER objet passé à vlink
; (cf. Makefile), son CODE porte donc le reset vector. hdr_start = offset 0 de la
; section ; le padding utilise une différence intra-section (constante en relogeable).
hdr_start:
        dc.w    $1111
        dc.w    $4EF9
        dc.l    coldstart        ; +04 PC de reset
        dc.l    $0000FFFF        ; +08
        dc.l    $00220005        ; +0C version ROM 34.5
        dc.l    $00220002        ; +10
        dc.l    $FFFFFFFF        ; +14
        dcb.b   $D0-(*-hdr_start),0
        dc.w    $4E70            ; $FC00D0 RESET (magic_reset)

coldstart:                        ; $FC00D2
        ; --- Phase 1 : superviseur + gel matériel (straight-line, pas de pile) ---
        move.w  #$2700,sr
        move.w  #$7FFF,DMACON
        move.w  #$7FFF,INTENA
        move.w  #$7FFF,INTREQ
        move.w  #C_RED,COLOR00

        ; --- Phase 2 : coupe overlay puis installe la pile ---
        move.b  #$03,CIAA_DDRA
        move.b  #$02,CIAA_PRA        ; OVL off -> RAM chip à $0
        move.l  #STACKTOP,sp
        move.w  #C_BLUE,COLOR00
        move.w  #SERPER_9600_PAL,SERPER
        lea     msg_cold(pc),a0
        bsr     ser_puts

        ; --- Phase 3 : ExecBase + jump table ---
        move.w  #C_CYAN,COLOR00
        lea     EXECBASE,a0          ; zéro-remplit la zone des champs positifs
        move.w  #(EXEC_POSSIZE/4)-1,d0
.zf:
        clr.l   (a0)+
        dbf     d0,.zf

        lea     EXECBASE,a6          ; a6 = SysBase (convention library base)
        move.b  #NT_LIBRARY,LN_TYPE(a6)
        move.l  #exec_name,LN_NAME(a6)
        move.w  #EXEC_NEGSIZE,LIB_NEGSIZE(a6)
        move.w  #EXEC_POSSIZE,LIB_POSSIZE(a6)
        move.w  #34,LIB_VERSION(a6)
        move.w  #2,LIB_REVISION(a6)
        move.l  #exec_id,LIB_IDSTRING(a6)
        move.l  #MAXCHIP,EB_MAXLOCMEM(a6)
        move.w  #0,EB_ATTNFLAGS(a6)
        move.b  #50,EB_VBLANKFREQ(a6)
        move.b  #50,EB_POWERFREQ(a6)
        move.b  #-1,EB_IDNEST(a6)
        move.b  #-1,EB_TDNEST(a6)
        move.l  #EXECBASE,d0
        not.l   d0
        move.l  d0,EB_CHKBASE(a6)

        lea     EB_MEMLIST(a6),a1
        jsr     newlist
        lea     EB_RESOURCELIST(a6),a1
        jsr     newlist
        lea     EB_DEVICELIST(a6),a1
        jsr     newlist
        lea     EB_INTRLIST(a6),a1
        jsr     newlist
        lea     EB_LIBLIST(a6),a1
        jsr     newlist
        lea     EB_PORTLIST(a6),a1
        jsr     newlist
        lea     EB_TASKREADY(a6),a1
        jsr     newlist
        lea     EB_TASKWAIT(a6),a1
        jsr     newlist
        lea     EB_SEMLIST(a6),a1
        jsr     newlist

        jsr     build_jumptable
        jsr     init_memory
        jsr     init_task            ; TCB « boot task » -> ThisTask (avant selftest)

        ; --- Phase 4 : publie SysBase, auto-vérif, auto-test ---
        move.l  a6,($4).w

        move.l  ($4).w,d0
        cmp.l   #EXECBASE,d0
        bne     eb_fail
        cmp.w   #34,LIB_VERSION(a6)
        bne     eb_fail
        move.l  a6,d0
        not.l   d0
        cmp.l   EB_CHKBASE(a6),d0
        bne     eb_fail
        move.l  EB_MEMLIST(a6),d0    ; lh_Head doit pointer sur le MemHeader ajouté
        cmp.l   #MH_CHIP,d0
        bne     eb_fail

        bsr     selftest             ; d0 = 0 (OK) / !=0 (échec)
        tst.l   d0
        bne     eb_fail
        ; --- M3a : arme VBlank et prouve que la chaîne d'interruptions tourne ---
        jsr     init_ints
        move.l  #$00100000,d1        ; timeout du spin (le GREEN sort sur count=5 bien avant)
.vbl_wait:
        lea     VBL_COUNT,a0
        move.l  (a0),d0              ; chargement DANS la boucle (le compteur évolue)
        cmp.l   #5,d0
        bcc.s   .vbl_live
        subq.l  #1,d1
        bne.s   .vbl_wait
        lea     msg_vbltimeout(pc),a0  ; interruptions mortes -> échec
        bsr     ser_puts
        bra     eb_fail
.vbl_live:
        lea     msg_vblok(pc),a0
        bsr     ser_puts

        move.w  #C_WHITE,COLOR00
        lea     msg_ok(pc),a0
        bsr     ser_puts             ; « self-test passed » émis AVANT le lancement (gate conservée)

        ; --- M4 : scan des résidents + InitCode (machinerie data-driven) ---
        ; Prouve la MACHINERIE de découverte de modules (scan ROM des ROMTags -> ResModules
        ; pri-trié -> InitResident/InitCode de chacun en ordre décroissant) avec des résidents
        ; DÉMO. N'EST PAS le handoff de boot : le handoff reste la démo M3f codée en dur
        ; ci-dessous (rte qui ne revient jamais) tant qu'aucun vrai module (cia/timer...)
        ; n'existe. Les résidents démo ne font qu'émettre leur nom ; rien n'est lancé par eux.
        move.l  #127,RES_LASTPRI     ; borne haute (toute RT_PRI <= 127 passe)
        clr.l   RES_COUNT
        jsr     build_reslist        ; scanne [RESSCAN_LO,HI) -> ExecBase->ResModules
        moveq   #0,d0                ; startClass (0 = toutes classes, phase coldstart)
        moveq   #0,d1                ; version minimale 0
        jsr     LVO_INITCODE(a6)     ; init chaque résident démo (émet son nom en ordre de pri)
        lea     res_mid_name(pc),a1  ; FindResident(nom) doit retrouver le bon résident
        jsr     LVO_FINDRESIDENT(a6)
        cmp.l   #res_mid,d0
        bne     res_fail
        cmp.l   #3,RES_COUNT         ; les 3 résidents démo direct-init initialisés ?
        bne     res_fail
        lea     msg_res_ok(pc),a0
        bsr     ser_puts             ; « M4 RESIDENTS OK »

        ; --- M5a : vérifier le résident AUTOINIT (demo.autolib) créé par MakeLibrary ---
        lea     EB_LIBLIST(a6),a0    ; la lib doit avoir été ajoutée à LibList
        lea     autolib_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     auto_fail            ; lib absente -> AUTOINIT/add KO
        move.l  d0,a2                ; a2 = base de la lib
        cmp.w   #40,LIB_VERSION(a2)  ; InitStruct (INITWORD) a posé la version ?
        bne     auto_fail
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; InitStruct (INITBYTE) a posé le type ?
        bne     auto_fail
        cmp.w   #$5A,LIB_REVISION(a2) ; l'init function a tourné (a posé la révision) ?
        bne     auto_fail
        move.l  a6,-(sp)             ; sauve SysBase
        move.l  a2,a6                ; a6 = base de la lib (convention d'appel)
        jsr     -6(a6)               ; appelle func0 via la jump table -> d0 (MakeFunctions OK ?)
        move.l  (sp)+,a6             ; restaure SysBase
        cmp.l   #$5A,d0
        bne     auto_fail
        lea     msg_auto_ok(pc),a0
        bsr     ser_puts             ; « M5A AUTOINIT OK »

        ; --- M5b : vérifier cia.resource (1er vrai module résident, direct-init) ---
        lea     ciab_test_name(pc),a1  ; OpenResource("ciab.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     cia_fail             ; resource absent -> KO
        move.l  d0,a2                ; a2 = base ciab
        cmp.l   #CIAB_HW,CIAR_HWBASE(a2)  ; bonne base matérielle ?
        bne     cia_fail
        move.l  a6,-(sp)             ; AbleICR($81 = enable bit0) via la jump table du resource
        move.l  a2,a6                ; a6 = base resource (convention d'appel)
        moveq   #$81,d0
        jsr     CIA_ABLEICR(a6)
        move.l  (sp)+,a6
        move.b  CIAR_ICRMASK(a2),d0  ; le shadow doit avoir le bit0 posé
        and.b   #1,d0
        beq     cia_fail
        move.l  a6,-(sp)             ; AddICRVector(bit1, dummy) -> doit rendre NULL (slot libre)
        move.l  a2,a6
        moveq   #1,d0
        lea     cia_dummy_int(pc),a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        tst.l   d0
        bne     cia_fail
        lea     msg_cia_ok(pc),a0
        bsr     ser_puts             ; « M5B CIA OK »

        ; --- M5c : vérifier timer.device (AUTOINIT, 2e vrai module résident) ---
        lea     EB_DEVICELIST(a6),a0 ; le device doit avoir été ajouté à DeviceList
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)     ; (= ce que fait OpenDevice en interne)
        tst.l   d0
        beq     timer_fail
        move.l  d0,a2                ; a2 = base device
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD) ?
        bne     timer_fail
        cmp.b   #NT_DEVICE,LN_TYPE(a2)  ; InitStruct (INITBYTE) ?
        bne     timer_fail
        move.l  a6,-(sp)             ; Open via la jump table du device -> LIB_OPENCNT++
        move.l  a2,a6                ; a6 = base device (convention)
        suba.l  a1,a1                ; iorequest = NULL (stub l'ignore)
        moveq   #0,d0                ; unit 0
        moveq   #0,d1                ; flags
        jsr     -6(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)   ; Open a bien incrémenté ?
        bne     timer_fail
        lea     msg_timer_ok(pc),a0
        bsr     ser_puts             ; « M5C TIMER OK »

        ; --- M6a : unité VBLANK de timer.device FONCTIONNELLE ---
        ; alloue reply port + timerequest, demande 100000 us (= 5 ticks), BeginIO, puis
        ; interroge le reply port (le service VBlank répond après ~5 VBlank). d6 = base timer,
        ; d7 = VBL_COUNT au départ (préservés par AllocMem/newlist/GetMsg).
        lea     EB_DEVICELIST(a6),a0
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,d6                ; d6 = base timer.device
        beq     m6a_fail
        move.l  #MP_SIZE,d0          ; reply port (PA_IGNORE : boot interroge par GetMsg)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m6a_fail
        move.l  d0,a2                ; a2 = port
        lea     MP_MSGLIST(a2),a1
        jsr     newlist
        move.b  #PA_SIGNAL,MP_FLAGS(a2)   ; PA_SIGNAL -> exerce exec_Signal DEPUIS le handler
        move.b  #16,MP_SIGBIT(a2)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a2)  ; signale la boot task (TS_RUN -> no-wake)
        move.l  #TR_SIZE,d0          ; timerequest
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m6a_fail
        move.l  d0,a3                ; a3 = timerequest
        move.l  a2,MN_REPLYPORT(a3)
        move.l  d6,IO_DEVICE(a3)
        move.l  #UNIT_VBLANK,IO_UNIT(a3)  ; unité VBLANK (le défaut de BeginIO est MICROHZ depuis M7a)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a3)
        clr.l   TV_SECS(a3)
        move.l  #100000,TV_MICRO(a3) ; 100000 us / 20000 = 5 ticks
        move.l  EB_THISTASK(a6),a0   ; efface le bit 16 de SIGRECVD (on le veut posé par la reply)
        move.l  TC_SIGRECVD(a0),d0
        bclr    #16,d0
        move.l  d0,TC_SIGRECVD(a0)
        move.l  VBL_COUNT,d7         ; T0
        move.l  a6,-(sp)             ; BeginIO (a6 = base timer, a1 = requête)
        move.l  d6,a6
        move.l  a3,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
.m6a_wait:
        move.l  VBL_COUNT,d0         ; garde-fou timeout (~4 s)
        sub.l   d7,d0
        cmp.l   #200,d0
        bcc     m6a_fail
        move.l  a2,a0                ; GetMsg(port) ?
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .m6a_wait
        cmp.l   a3,d0                ; le reply doit être NOTRE requête
        bne     m6a_fail
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)  ; marquée répondue ?
        bne     m6a_fail
        move.l  VBL_COUNT,d0         ; délai ≈ 5 ticks ? (marge [3..40])
        sub.l   d7,d0
        cmp.l   #3,d0
        bcs     m6a_fail
        cmp.l   #40,d0
        bhi     m6a_fail
        move.l  EB_THISTASK(a6),a0   ; exec_Signal (depuis le handler) a-t-il posé le bit 16 ?
        move.l  TC_SIGRECVD(a0),d0
        btst    #16,d0
        beq     m6a_fail
        lea     msg_m6a_ok(pc),a0
        bsr     ser_puts             ; « M6A TIMER OK »

        ; --- M7b : dispatcher par numéro — chaîne PORTS (INT2) via AddIntServer ---
        ; SCHED_ON encore 0 (aucune interaction scheduler/gate ; INT2 niveau 2 < 3 de toute façon).
        ; Enregistre DEUX serveurs sur PORTS : ciaa_server (pri 10, lit+acquitte l'ICR ciaa ->
        ; cia_test_vec incrémente CIA_FIRED) et int2_srv2 (pri 0, incrémente INT2_SRV2). La chaîne les
        ; appelle DANS L'ORDRE DE PRIORITÉ (cia avant srv2) -> prouve AddIntServer + walker + ordre.
        ; Structs serveur en RAM (Enqueue les chaîne). CIA-A Timer A en CONTINU déclenche INT2.
        ; Généralise M6b : cia.resource EST le handler PORTS (serveur), plus un autovecteur hardcodé.
        clr.l   CIA_FIRED
        clr.l   INT2_SRV2
        clr.l   INT2_ORDER_SNAP
        lea     ciaa_test_name(pc),a1   ; OpenResource("ciaa.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     m7b_fail
        move.l  d0,a2                ; a2 = base ciaa (survit au spin + cleanup)
        move.l  #(2*IS_STRIDE),d0    ; 2 struct Interrupt RAM alignées (Enqueue les chaîne -> pas en ROM)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7b_fail
        move.l  d0,a3                ; a3 = bloc serveurs : srvA=+0, srvB=+IS_STRIDE (aligné)
        move.b  #10,LN_PRI(a3)       ; srvA = ciaa_server, pri 10 (appelé en 1er)
        move.l  #ciaa_server,IS_CODE(a3)
        move.b  #0,IS_STRIDE+LN_PRI(a3) ; srvB = int2_srv2, pri 0 (appelé en 2e)
        move.l  #int2_srv2,IS_STRIDE+IS_CODE(a3)
        moveq   #INTB_PORTS,d0       ; AddIntServer(PORTS, srvA)
        move.l  a3,a1
        jsr     LVO_ADDINTSERVER(a6)
        moveq   #INTB_PORTS,d0       ; AddIntServer(PORTS, srvB)
        lea     IS_STRIDE(a3),a1
        jsr     LVO_ADDINTSERVER(a6)
        move.l  a6,-(sp)             ; AddICRVector(ciaa, bit0=timerA, &cia_test_int)
        move.l  a2,a6
        moveq   #0,d0
        lea     cia_test_int(pc),a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        move.l  CIAR_HWBASE(a2),a0   ; démarre CIA-A Timer A CONTINU, latch $00FF (~360 us/IRQ)
        move.b  #$FF,CIA_TALO(a0)
        move.b  #$00,CIA_TAHI(a0)
        move.b  #$11,CIA_CRA(a0)     ; START(b0)+LOAD(b4), continu (b3=0) -> INT2 périodique
        move.l  VBL_COUNT,d7         ; T0 (timeout)
.m7b_wait:
        move.l  VBL_COUNT,d0
        sub.l   d7,d0
        cmp.l   #150,d0
        bcc     m7b_fail             ; timeout -> chaîne non dispatchée
        tst.l   CIA_FIRED            ; 1er serveur (ciaa) appelé via la chaîne ?
        beq.s   .m7b_wait
        tst.l   INT2_SRV2            ; 2e serveur de la chaîne appelé ?
        beq.s   .m7b_wait
        move.l  CIAR_HWBASE(a2),a0   ; les deux tournent -> cleanup matériel
        move.b  #$00,CIA_CRA(a0)     ; stop Timer A
        move.l  a6,-(sp)             ; RemICRVector(bit0)
        move.l  a2,a6
        moveq   #0,d0
        suba.l  a1,a1
        jsr     CIA_REMICRVECTOR(a6)
        move.l  (sp)+,a6
        move.w  #INTF_PORTS,INTENA   ; désactive Paula PORTS -> pas d'INT2 pendant la démo
        tst.l   INT2_ORDER_SNAP      ; ordre : ciaa (pri 10) a tourné AVANT srv2 (pri 0) ?
        beq     m7b_fail
        lea     msg_m7b_ok(pc),a0
        bsr     ser_puts             ; « M7B PORTS OK »

        ; --- M7a + M3f : démo combinée (SCHED_ON=1) ---
        ; Setup entier à IPL7 pour qu'aucune IRQ ne parte avant le lancement (le CIA-B démarre
        ; mais son underflow reste pending jusqu'au rte). M7a : unité MICROHZ via CIA-B/INT6 +
        ; task_timer qui bloque dessus -> prouve (a) une TÂCHE réveillée par un timer d'interruption
        ; (Wait->wake) et (b) le GATE DE RÉ-ENTRANCE : INT6 (niveau 6) préempte vbl_handler, dont la
        ; chirurgie de listes est désormais IPL7 -> VBL_CLASH reste 0 (RED : IPL3 -> VBL_CLASH>0).
        ; M3f (rejoué, non-régression) : task_H/L/S prouvent la coexistence préemption + yield
        ; (marqueur « M3F LIVE »). GREEN = « M7A TIMER OK » émis, VBL_CLASH==0, sentinelles intactes.
        move.w  #$2700,sr            ; masque les interruptions pendant TOUT le setup
        clr.l   VBL_CLASH
        lea     ciab_test_name(pc),a1   ; OpenResource("ciab.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a2                ; a2 = base ciab
        moveq   #INTB_EXTER,d0       ; SetIntVector(EXTER, &ciab_server_int) : vecteur EXCLUSIF ->
        lea     ciab_server_int(pc),a1  ; INT6 passe par le dispatcher par numéro (ciab_server/cia_dispatch)
        jsr     LVO_SETINTVECTOR(a6)
        move.l  a6,-(sp)             ; AddICRVector(ciab, bit0 = timer A, &timer_micro_int)
        move.l  a2,a6
        moveq   #0,d0
        move.l  #timer_micro_int,a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        move.w  #(INTF_SETCLR|INTF_EXTER),INTENA   ; active Paula EXTER (INT6, niveau 6 > VBlank 3)
        move.l  CIAR_HWBASE(a2),a0   ; démarre CIA-B Timer A en CONTINU (IRQ périodique rapide)
        move.b  #CIAB_LATCH_LO,CIA_TALO(a0)
        move.b  #CIAB_LATCH_HI,CIA_TAHI(a0)   ; l'écriture de TAHI charge le latch
        move.b  #$11,CIA_CRA(a0)     ; START(b0) + LOAD(b4) ; b3=0 -> mode CONTINU (auto-reload)
        bsr     setup_stress_port    ; M7d : port partagé + K messages (martelé par tâche ET interruption)
        bsr     setup_demo_tasks     ; task_H(10) + task_L(0) + task_S(0) + task_timer(10, M7a) + task_port(0, M7d)
        move.b  #1,SCHED_ON          ; ARME la préemption périodique
        ; --- M7c : LANCEMENT de la 1re tâche = transition SUPERVISEUR -> USER mode ---
        ; La pile boot (STACKTOP) devient la SSP PARTAGÉE des interruptions ; chaque tâche a sa pile
        ; user (AllocMem'd). On réinitialise la SSP à STACKTOP (abandonne le contexte boot), on réserve
        ; un slot de frame, et dispatch_in relocalise la frame user de task_H -> SSP puis rte en USER mode.
        move.l  #STACKTOP,sp         ; SSP partagée propre (le contexte boot ne reprend jamais)
        lea     -FRAME_SIZE(sp),sp   ; slot 66 o pour dispatch_in (movem+rte ramènent sp à STACKTOP)
        lea     EB_TASKREADY(a6),a0  ; dispatch initial explicite
        jsr     LVO_REMHEAD(a6)      ; tête = task_H (pri 10) -> elle Wait d'abord
        move.l  d0,a1
        bra     dispatch_in          ; -> task_H en USER mode (SR=$0000 ; VBlank + INT6 + yield actifs)

eb_fail:
        move.w  #C_FAIL,COLOR00
        lea     msg_fail(pc),a0
        bsr     ser_puts
.ff:
        bra.s   .ff

; ser_puts : chaîne NUL-terminée sur le série (a0) ; timeout borné sur TBE
ser_puts:
        movem.l d0/d1/d2/a0,-(sp)
.lp:
        move.b  (a0)+,d0
        beq.s   .done
        move.w  #$2000,d2
.wt:
        move.w  SERDATR,d1
        btst    #13,d1
        bne.s   .tx
        dbra    d2,.wt
        bra.s   .done
.tx:
        and.w   #$00FF,d0
        or.w    #$0100,d0
        move.w  d0,SERDAT
        bra.s   .lp
.done:
        movem.l (sp)+,d0/d1/d2/a0
        rts

; ============================ auto-test (M2.1a+) ====================
; Exerce le dispatch jump-table et le comportement des fonctions.
; Retour : d0 = 0 (tout OK) / 1 (échec).
selftest:
        movem.l d6-d7/a2-a5,-(sp)
        ; baseline du tas chip : 1er chunk libre APRÈS les allocations permanentes
        ; de boot (TCB ThisTask...). Les asserts de coalescing comparent à cette
        ; baseline (robuste aux allocations permanentes, pas au tas vide).
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),a5     ; a5 = adresse baseline du 1er chunk
        move.l  MC_BYTES(a5),d7     ; d7 = taille baseline
        ; Forbid : TDNestCnt -1 -> 0 ; Permit : 0 -> -1
        jsr     LVO_FORBID(a6)
        cmp.b   #0,EB_TDNEST(a6)
        bne.w   .bad
        jsr     LVO_PERMIT(a6)
        cmp.b   #-1,EB_TDNEST(a6)
        bne.w   .bad
        ; Disable/Enable : IDNestCnt -1 -> 0 -> -1
        jsr     LVO_DISABLE(a6)
        cmp.b   #0,EB_IDNEST(a6)
        bne.w   .bad
        jsr     LVO_ENABLE(a6)
        cmp.b   #-1,EB_IDNEST(a6)
        bne.w   .bad

        ; liste : NEWLIST, AddTail(n1), AddTail(n2), FindName
        lea     TST_LIST,a1
        jsr     newlist
        move.l  #str_alpha,TST_N1+LN_NAME
        move.l  #str_beta,TST_N2+LN_NAME
        lea     TST_LIST,a0
        lea     TST_N1,a1
        jsr     LVO_ADDTAIL(a6)
        lea     TST_LIST,a0
        lea     TST_N2,a1
        jsr     LVO_ADDTAIL(a6)
        ; FindName("beta") == TST_N2
        lea     TST_LIST,a0
        move.l  #str_beta,a1
        jsr     LVO_FINDNAME(a6)
        cmp.l   #TST_N2,d0
        bne.w   .bad
        ; FindName("gamma") == 0
        lea     TST_LIST,a0
        move.l  #str_gamma,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.w   .bad
        ; Remove(n1) ; FindName("alpha") == 0
        lea     TST_N1,a1
        jsr     LVO_REMOVE(a6)
        lea     TST_LIST,a0
        move.l  #str_alpha,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.w   .bad
        ; AddHead(n1) ; FindName("alpha") == TST_N1
        lea     TST_LIST,a0
        lea     TST_N1,a1
        jsr     LVO_ADDHEAD(a6)
        lea     TST_LIST,a0
        move.l  #str_alpha,a1
        jsr     LVO_FINDNAME(a6)
        cmp.l   #TST_N1,d0
        bne.w   .bad
        ; Open/Close : OpenCnt +1 puis -1, Open retourne SysBase
        jsr     LVO_OPEN(a6)
        cmp.l   a6,d0
        bne.w   .bad
        jsr     LVO_CLOSE(a6)
        tst.w   LIB_OPENCNT(a6)
        bne.w   .bad
        lea     chk_core(pc),a0      ; checkpoint série : groupe « core » passé
        bsr     ser_puts

        ; --- mémoire : AllocMem / FreeMem ---
        move.l  #256,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; p1
        move.l  #256,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3                ; p2
        move.l  #$11111111,(a2)      ; non-recouvrement par motif
        move.l  #$22222222,(a3)
        cmp.l   #$11111111,(a2)
        bne.w   .bad
        cmp.l   #$22222222,(a3)
        bne.w   .bad
        move.l  #$DEADBEEF,(a2)      ; dirty p1, free, realloc CLEAR -> zéro
        move.l  a2,a1
        move.l  #256,d0
        jsr     LVO_FREEMEM(a6)
        move.l  #256,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a1
        tst.l   (a1)                 ; MEMF_CLEAR -> 1er longword == 0
        bne.w   .bad
        move.l  #256,d0              ; libère le bloc CLEAR puis p2
        jsr     LVO_FREEMEM(a6)
        move.l  a3,a1
        move.l  #256,d0
        jsr     LVO_FREEMEM(a6)

        ; coalescing : après tous les free, le tas doit être revenu à sa baseline
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),d0
        cmp.l   a5,d0
        bne.w   .bad
        move.l  d0,a0
        cmp.l   MC_BYTES(a0),d7
        bne.w   .bad
        lea     chk_mem(pc),a0       ; checkpoint : mémoire M2.1/M2.2 + coalescing
        bsr     ser_puts

        ; ===== M2.4a : multi-MemHeader + primitives de listes =====
        ; (1) 2e MemHeader « fast » sur la région DISJOINTE [FTEST_LO,FTEST_HI).
        ;     Struct allouée depuis le tas ; la région est fixe/disjointe (c'est
        ;     ainsi que fonctionne un vrai multi-header : régions physiques distinctes).
        move.l  #MH_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; a2 = H (header fast)
        move.b  #NT_MEMORY,LN_TYPE(a2)
        move.w  #(MEMF_FAST|MEMF_PUBLIC),MH_ATTRIBUTES(a2)
        move.l  #FTEST_LO,MH_LOWER(a2)
        move.l  #FTEST_HI,MH_UPPER(a2)
        move.l  #(FTEST_HI-FTEST_LO),MH_FREE(a2)
        move.l  #FTEST_LO,a0         ; chunk initial = toute la région
        clr.l   MC_NEXT(a0)
        move.l  #(FTEST_HI-FTEST_LO),MC_BYTES(a0)
        move.l  a0,MH_FIRST(a2)
        lea     EB_MEMLIST(a6),a0
        move.l  a2,a1
        jsr     LVO_ADDTAIL(a6)
        ; AvailMem(MEMF_FAST) == taille de la région
        moveq   #MEMF_FAST,d1
        jsr     LVO_AVAILMEM(a6)
        cmp.l   #(FTEST_HI-FTEST_LO),d0
        bne.w   .bad
        ; AllocMem(1024,MEMF_FAST) -> sélection par attribut -> adresse dans la région
        move.l  #1024,d0
        moveq   #MEMF_FAST,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3               ; a3 = bloc fast
        cmp.l   #FTEST_LO,d0
        bcs.w   .bad                ; < FTEST_LO
        cmp.l   #FTEST_HI,d0
        bcc.w   .bad                ; >= FTEST_HI
        ; TypeOfMem(bloc) a le bit MEMF_FAST (= bit 2)
        move.l  a3,a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #2,d0
        beq.w   .bad
        ; FreeMem(bloc fast) : l'owner-search doit retrouver H (pas le header chip)
        move.l  a3,a1
        move.l  #1024,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #MEMF_FAST,d1
        jsr     LVO_AVAILMEM(a6)
        cmp.l   #(FTEST_HI-FTEST_LO),d0   ; région de nouveau pleine -> owner-search OK
        bne.w   .bad
        ; retire H de la MemList + libère sa struct
        move.l  a2,a1
        jsr     LVO_REMOVE(a6)
        move.l  a2,a1
        move.l  #MH_SIZE,d0
        jsr     LVO_FREEMEM(a6)

        ; (2) Enqueue : 3 noeuds pri 0/10/5 -> ordre tête->queue 10,5,0 (FIFO à pri égale)
        move.l  #(3*16),d0          ; 3 noeuds (LN_SIZE=14 arrondi à 16)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3               ; a3 = n0=+0, n1=+16, n2=+32
        move.l  #16,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a4               ; a4 = struct List
        move.l  a4,a1
        jsr     newlist
        move.b  #0,LN_PRI(a3)
        move.b  #10,16+LN_PRI(a3)
        move.b  #5,32+LN_PRI(a3)
        move.l  a4,a0
        move.l  a3,a1               ; Enqueue n0 (pri 0)
        jsr     LVO_ENQUEUE(a6)
        move.l  a4,a0
        lea     16(a3),a1           ; Enqueue n1 (pri 10)
        jsr     LVO_ENQUEUE(a6)
        move.l  a4,a0
        lea     32(a3),a1           ; Enqueue n2 (pri 5)
        jsr     LVO_ENQUEUE(a6)
        ; ordre attendu : head=n1, n1->Succ=n2, n2->Succ=n0, n0->Succ=&lh_Tail
        move.l  (a4),a0             ; lh_Head
        lea     16(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n1->Succ
        lea     32(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n2->Succ
        move.l  a3,a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n0->Succ == &lh_Tail (= a4+LH_TAIL)
        lea     LH_TAIL(a4),a1
        cmp.l   a1,a0
        bne.w   .bad
        ; RemHead -> n1 ; nouvelle tête = n2
        move.l  a4,a0
        jsr     LVO_REMHEAD(a6)
        lea     16(a3),a1
        cmp.l   a1,d0
        bne.w   .bad
        move.l  (a4),a0
        lea     32(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        ; RemTail -> n0 (plus basse pri, en queue)
        move.l  a4,a0
        jsr     LVO_REMTAIL(a6)
        move.l  a3,a1
        cmp.l   a1,d0
        bne.w   .bad
        ; Insert(list, n0, pred=n2) -> n2->Succ == n0
        move.l  a4,a0
        move.l  a3,a1               ; node n0
        lea     32(a3),a2           ; pred n2
        jsr     LVO_INSERT(a6)
        lea     32(a3),a0
        move.l  (a0),a0             ; n2->Succ
        move.l  a3,a1
        cmp.l   a1,a0
        bne.w   .bad
        ; libère list + noeuds
        move.l  a4,a1
        move.l  #16,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a3,a1
        move.l  #(3*16),d0
        jsr     LVO_FREEMEM(a6)
        lea     chk_m24a(pc),a0      ; checkpoint : multi-header + listes
        bsr     ser_puts

        ; ===== M2.4b : tâches + signaux (non bloquants) =====
        ; FindTask(NULL) == ThisTask
        sub.l   a1,a1
        jsr     LVO_FINDTASK(a6)
        cmp.l   EB_THISTASK(a6),d0
        bne.w   .bad
        ; AllocSignal(-1) -> 16 (bits 0-15 pré-alloués via SYS_SIGALLOC)
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #16,d0
        bne.w   .bad
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #17,d0
        bne.w   .bad
        moveq   #16,d0               ; libère 16 -> redevient le plus petit libre
        jsr     LVO_FREESIGNAL(a6)
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #16,d0
        bne.w   .bad
        ; AllocSignal efface un SIGRECVD rémanent sur le bit alloué
        move.l  EB_THISTASK(a6),a2
        or.l    #$00100000,TC_SIGRECVD(a2)   ; bit 20 rémanent
        moveq   #20,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #20,d0
        bne.w   .bad
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00100000,d0
        bne.w   .bad                 ; le bit 20 doit avoir été effacé
        ; SetSignal : pose le bit 16, retourne l'ancien jeu
        move.l  #$00010000,d0
        move.l  #$00010000,d1
        jsr     LVO_SETSIGNAL(a6)
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00010000,d0
        beq.w   .bad
        ; Signal(ThisTask, bit 17) -> bit posé dans SIGRECVD
        move.l  a2,a1
        move.l  #$00020000,d0
        jsr     LVO_SIGNAL(a6)
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00020000,d0
        beq.w   .bad
        ; SetTaskPri(ThisTask,5) -> ancienne 0 ; LN_PRI == 5 ; puis restaure 0
        move.l  a2,a1
        moveq   #5,d0
        jsr     LVO_SETTASKPRI(a6)
        tst.l   d0
        bne.w   .bad
        cmp.b   #5,LN_PRI(a2)
        bne.w   .bad
        move.l  a2,a1
        moveq   #0,d0
        jsr     LVO_SETTASKPRI(a6)
        moveq   #16,d0               ; nettoie les signaux de test (16,17,20)
        jsr     LVO_FREESIGNAL(a6)
        moveq   #17,d0
        jsr     LVO_FREESIGNAL(a6)
        moveq   #20,d0
        jsr     LVO_FREESIGNAL(a6)
        move.l  #0,TC_SIGRECVD(a2)   ; remet SIGRECVD propre

        ; FindTask(nom) : nœud tâche factice dans TaskReady
        move.l  #TC_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3                ; tâche factice
        move.b  #NT_TASK,LN_TYPE(a3)
        move.l  #task_test_name,LN_NAME(a3)
        lea     EB_TASKREADY(a6),a0
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)
        move.l  #task_test_name,a1
        jsr     LVO_FINDTASK(a6)
        cmp.l   a3,d0
        bne.w   .bad
        move.l  #str_gamma,a1        ; nom inconnu -> 0
        jsr     LVO_FINDTASK(a6)
        tst.l   d0
        bne.w   .bad
        move.l  a3,a1                ; retire + libère la tâche factice
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1
        move.l  #TC_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        lea     chk_m24b(pc),a0      ; checkpoint : tâches + signaux
        bsr     ser_puts

        ; ===== M2.4c : ports / messages (non bloquants) =====
        moveq   #-1,d0               ; bit de signal pour le port
        jsr     LVO_ALLOCSIGNAL(a6)
        move.l  d0,d6                ; d6 = n° de bit
        move.l  #MP_SIZE,d0          ; port principal depuis le tas
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; a2 = port
        lea     MP_MSGLIST(a2),a1    ; le caller initialise la file
        jsr     newlist
        move.l  #str_port,LN_NAME(a2)
        move.b  #PA_SIGNAL,MP_FLAGS(a2)
        move.b  d6,MP_SIGBIT(a2)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a2)
        move.l  a2,a1
        jsr     LVO_ADDPORT(a6)
        ; FindPort(nom) == port ; FindPort(inconnu) == 0
        move.l  #str_port,a1
        jsr     LVO_FINDPORT(a6)
        cmp.l   a2,d0
        bne.w   .bad
        move.l  #str_gamma,a1
        jsr     LVO_FINDPORT(a6)
        tst.l   d0
        bne.w   .bad
        ; 2 messages depuis le tas (msg1=+0, msg2=+MN_SIZE)
        move.l  #(2*MN_SIZE),d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3
        ; PutMsg(msg1) doit poser le bit du port dans SIGRECVD de ThisTask
        move.l  EB_THISTASK(a6),a0
        clr.l   TC_SIGRECVD(a0)
        move.l  a2,a0
        move.l  a3,a1
        jsr     LVO_PUTMSG(a6)
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGRECVD(a0),d0
        moveq   #1,d1
        lsl.l   d6,d1
        and.l   d1,d0
        beq.w   .bad                 ; bit du port non posé
        ; PutMsg(msg2) ; GetMsg FIFO : msg1, msg2, puis 0 (vide)
        move.l  a2,a0
        lea     MN_SIZE(a3),a1
        jsr     LVO_PUTMSG(a6)
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        cmp.l   a3,d0
        bne.w   .bad
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        lea     MN_SIZE(a3),a1
        cmp.l   a1,d0
        bne.w   .bad
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        bne.w   .bad
        ; ReplyMsg : msg1 revient sur un reply port avec le type NT_REPLYMSG
        move.l  #MP_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a4                ; a4 = reply port
        lea     MP_MSGLIST(a4),a1
        jsr     newlist
        move.b  #PA_IGNORE,MP_FLAGS(a4)   ; pas de signal au reply
        move.l  a4,MN_REPLYPORT(a3)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        move.l  a4,a0
        jsr     LVO_GETMSG(a6)
        cmp.l   a3,d0                ; msg1 revenu sur le reply port
        bne.w   .bad
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne.w   .bad
        ; nettoyage : RemPort du port PUBLIC seulement (rport n'a jamais été
        ; AddPort'd -> le retirer appellerait Remove sur un noeud non chaîné, qui
        ; écrirait dans la low RAM $0/$4). free messages + ports + signal.
        move.l  a2,a1
        jsr     LVO_REMPORT(a6)
        move.l  a3,a1
        move.l  #(2*MN_SIZE),d0
        jsr     LVO_FREEMEM(a6)
        move.l  a4,a1
        move.l  #MP_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a2,a1
        move.l  #MP_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d6,d0
        jsr     LVO_FREESIGNAL(a6)
        lea     chk_m24c(pc),a0      ; checkpoint : ports + messages
        bsr     ser_puts

        ; invariant final : tas chip revenu à la baseline (chunk unique)
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),d0
        cmp.l   a5,d0
        bne.w   .bad
        move.l  d0,a0
        cmp.l   MC_BYTES(a0),d7
        bne.w   .bad

        moveq   #0,d0
        bra.s   .out
.bad:
        moveq   #1,d0
.out:
        movem.l (sp)+,d6-d7/a2-a5
        rts

; ============================ démo recombinaison (M3f) ==============
; Crée 3 tâches superviseur et les met dans TaskReady. Scaffolding de PREUVE (comme le
; selftest) : sera remplacé par la suite d'init exec (scan résidents) plus tard. Signal
; CÂBLÉ EN DUR (DEMO_SIG=16, hors 0-15 réservés) plutôt qu'AllocSignal (qui opère sur
; ThisTask = tâche de boot ; Wait/Signal ne consultent que le MASQUE). task_L signale
; task_H via son TCB publié dans WP_HTASK (posé AVANT lancement -> toujours valide).
;   task_H (pri 10) : cible du yield. task_L/task_S (pri 0) : round-robin préemptif.
setup_demo_tasks:                    ; a6 = SysBase ; clobbers scratch + d2/a2-a4 (sauvés)
        movem.l d2/a2-a4,-(sp)
        clr.l   WP_HTASK             ; RAM basse non garantie nulle au power-on -> explicite
        clr.l   WP_CONS
        clr.l   WP_PROD
        clr.l   WP_SPIN
        clr.l   WP_STAT
        clr.l   WP_TCONS             ; M7a : réveils de task_timer
        lea     task_h(pc),a2        ; task_H (pri 10) -> tête (Enqueue trie), publiée
        lea     task_h_name(pc),a3
        moveq   #DEMO_PRI_H,d2
        bsr     mk_demo_task
        move.l  a4,WP_HTASK
        lea     task_l(pc),a2        ; task_L (pri 0) : signale+yield+spin préemptible
        lea     task_l_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
        lea     task_s(pc),a2        ; task_S (pri 0) : spinner pur (dispatché par préemption)
        lea     task_s_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
        lea     task_timer(pc),a2    ; task_timer (pri 10, M7a) : bloque sur l'unité MICROHZ
        lea     task_t_name(pc),a3
        moveq   #DEMO_PRI_T,d2
        bsr     mk_demo_task
        lea     task_port(pc),a2     ; task_port (pri 0, M7d) : martèle le port partagé (consommateur TÂCHE)
        lea     task_p_name(pc),a3
        moveq   #DEMO_PRI_P,d2
        bsr     mk_demo_task
        movem.l (sp)+,d2/a2-a4
        rts

; setup_stress_port (M7d) : crée le port partagé + STRESS_K messages (MAGIC + IN_HAND=0), tous AddTail'd
; sur le port. a6 = SysBase. WP_SPORT est écrit EN DERNIER (une fois le port prêt) pour que le service
; MICROHZ (qui teste WP_SPORT) ne le voie qu'entièrement construit. clobbers scratch + d2/a2 (sauvés).
setup_stress_port:
        movem.l d2/a2,-(sp)
        clr.l   WP_SPORT             ; (RAM basse non garantie nulle)
        clr.l   WP_PORTT
        clr.l   WP_PORTI
        clr.l   WP_PORTFAIL
        clr.b   M7D_STAT
        move.l  #MP_SIZE,d0          ; alloue le port
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7d_fail
        move.l  d0,a2                ; a2 = port
        move.b  #NT_MSGPORT,LN_TYPE(a2)
        move.b  #PA_IGNORE,MP_FLAGS(a2)   ; action != PA_SIGNAL -> PutMsg saute la voie de signal
        move.l  a2,a1                ; NEWLIST(&port->MsgList)
        lea     MP_MSGLIST(a2),a1
        jsr     newlist
        moveq   #STRESS_K,d2         ; d2 = compteur de messages à créer
.sp_loop:
        move.l  #STRESS_MSG_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7d_fail
        move.l  d0,a1                ; a1 = message
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.l  #STRESS_MAGIC,MSG_MAGIC_OFF(a1)   ; MAGIC ; IN_HAND déjà 0 (MEMF_CLEAR)
        lea     MP_MSGLIST(a2),a0    ; AddTail(&port->MsgList, msg)
        jsr     LVO_ADDTAIL(a6)
        subq.l  #1,d2
        bne.s   .sp_loop
        move.l  a2,WP_SPORT          ; port prêt -> publié EN DERNIER
        movem.l (sp)+,d2/a2
        rts

; mk_demo_task : a2 = PC du corps, a3 = nom, d2.b = priorité -> a4 = TCB créé.
; AllocMem préserve a2/a3/d2 ; AddTask lit a2 (initPC) / a3 (finalPC=task_exit).
mk_demo_task:
        move.l  #TC_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a4                ; a4 = TCB
        move.l  a3,LN_NAME(a4)
        move.b  d2,LN_PRI(a4)
        move.l  #SYS_SIGALLOC,TC_SIGALLOC(a4)  ; bits 0-15 réservés -> AllocSignal rend 16+ (task_timer)
        move.l  #DEMO_STK,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,TC_SPLOWER(a4)
        add.l   #DEMO_STK,d0
        move.l  d0,TC_SPUPPER(a4)
        move.l  a4,a1
        lea     task_exit(pc),a3     ; finalPC (a3 = nom écrasé, déjà posé dans LN_NAME)
        jsr     LVO_ADDTASK(a6)      ; AddTask(a1=task, a2=initPC, a3=finalPC)
        rts

; Corps des tâches de démo M3f — PREUVE que préemption périodique et yield-sur-Permit
; COEXISTENT (SCHED_ON=1), sans corruption de contexte. Déterministe, indépendant du
; cadencement série (les compteurs avancent par l'ordonnancement, pas par l'émission).
;   task_H (pri 10) : boucle Wait(DEMO_SIG) ; WP_CONS++. Dispatchée par le yield de task_L.
;   task_L (pri 0)  : boucle Forbid/Signal(task_H)/Permit(<-yield) ; WP_PROD++. Ne bloque jamais.
;   task_S (pri 0)  : spinner PUR (WP_SPIN++) ; ne bloque/signale/yield JAMAIS -> ne tourne
;                     que si la PRÉEMPTION partage le CPU (sinon il monopoliserait -> RED).
; Chaque tâche garde une sentinelle en d7 (préservé par tout switch) et la revérifie :
; corruption -> « M3F FAILED ». « M3F LIVE » émis UNE fois quand WP_CONS >= CONS_THRESH
; (yield répété) ET WP_SPIN >= SPIN_THRESH (task_S a tourné via préemption).
; RED (SCHED_ON=0 = préemption OFF) : task_S (ou task_L) monopolise le CPU -> task_L ne
; peut plus signaler task_H -> WP_CONS gèle -> « M3F LIVE » jamais émis (absent).
task_h:                              ; haute priorité (les tâches démarrent a6=0)
        move.l  ($4).w,a6            ; SysBase (cf. frame AddTask qui zéro-remplit les GPR)
        move.l  #SENT_H,d7           ; sentinelle de contexte
.h_loop:
        moveq   #1,d0
        moveq   #DEMO_SIG,d1
        lsl.l   d1,d0               ; masque = 1 << DEMO_SIG (décalage registre : 68000 immédiat <= 8)
        jsr     LVO_WAIT(a6)         ; BLOQUE jusqu'au signal de task_L (dispatch via yield)
        cmp.l   #SENT_H,d7
        bne.w   demo_fail            ; contexte corrompu par un switch
        addq.l  #1,WP_CONS
        btst    #0,WP_STAT
        bne.s   .h_loop              ; marqueur déjà émis
        move.l  WP_CONS,d0
        cmp.l   #CONS_THRESH,d0
        bcs.s   .h_loop              ; WP_CONS < seuil -> continuer
        move.l  WP_SPIN,d0
        cmp.l   #SPIN_THRESH,d0
        bcs.s   .h_loop              ; WP_SPIN < seuil -> préemption pas encore prouvée
        bset    #0,WP_STAT           ; marque émis (une seule fois)
        jsr     LVO_FORBID(a6)       ; émission non fractionnée
        lea     msg_m3flive(pc),a0
        bsr     ser_puts
        tst.b   WP_UMODE             ; M7c : une tâche s'est observée en USER mode (SR bit S == 0) ?
        beq.s   .h_noum
        lea     msg_m7c_ok(pc),a0
        bsr     ser_puts             ; « M7C USERMODE OK » (user-mode + relocation + préemption prouvés)
.h_noum:
        jsr     LVO_PERMIT(a6)
        bra.s   .h_loop
task_l:                              ; basse priorité, ne bloque jamais
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_L,d7
.l_loop:
        jsr     LVO_FORBID(a6)       ; Signal sous Forbid -> yield reporté au Permit
        move.l  WP_HTASK,a1
        moveq   #1,d0
        moveq   #DEMO_SIG,d1
        lsl.l   d1,d0
        jsr     LVO_SIGNAL(a6)       ; réveille task_H + pose AttnResched (pri 10 > 0)
        jsr     LVO_PERMIT(a6)       ; <- YIELD : dispatche task_H immédiatement
        cmp.l   #SENT_L,d7
        bne.w   demo_fail
        addq.l  #1,WP_PROD
        bra.s   .l_loop
task_s:                              ; basse priorité, spinner PUR (jamais de blocage/yield)
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_S,d7
        move.w  sr,d0                ; M7c : preuve DIRECTE du user-mode (MOVE from SR non privilégié
        and.w   #$2000,d0            ; sur 68000) -> bit S attendu à 0
        bne.w   demo_fail            ; S=1 => tâche en superviseur => régression user-mode (sentinelle KO)
        move.b  #1,WP_UMODE          ; user mode confirmé (consommé par task_H -> « M7C USERMODE OK »)
.s_loop:
        cmp.l   #SENT_S,d7
        bne.w   demo_fail            ; contexte corrompu par une PRÉEMPTION
        addq.l  #1,WP_SPIN
        move.l  #$00001000,d0
.s_spin:
        subq.l  #1,d0
        bne.s   .s_spin
        bra.s   .s_loop

; task_timer (pri 10, M7a) : bloque sur l'unité MICROHZ (CIA-B/INT6). À chaque tour, arme une
; requête courte (1 tick CIA-B), Wait sur le reply port, vérifie la réponse. Prouve qu'une TÂCHE
; se réveille sur un timer d'interruption (Wait->wake par l'IRQ MICROHZ) ET surveille VBL_CLASH :
; si INT6 a préempté la chirurgie de listes de vbl_handler (gate violé en RED), VBL_CLASH>0 ->
; « M7A FAILED ». GREEN = TCONS_THRESH réveils accumulés avec VBL_CLASH toujours == 0.
; Setup en contexte tâche (AllocSignal opère bien sur task_timer). a4=base timer, a3=reply port,
; a2=timerequest, d6=bit de signal, d7=sentinelle — tous préservés par les appels exec (vérifié).
task_timer:
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_T,d7           ; sentinelle de contexte
        lea     EB_DEVICELIST(a6),a0 ; base timer.device
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a4                ; a4 = base timer.device
        moveq   #-1,d0               ; AllocSignal -> bit du reply port (task_timer a SYS_SIGALLOC)
        jsr     LVO_ALLOCSIGNAL(a6)
        move.l  d0,d6                ; d6 = n° de bit
        move.l  #MP_SIZE,d0          ; reply port
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a3                ; a3 = reply port
        lea     MP_MSGLIST(a3),a1
        jsr     newlist
        move.b  #PA_SIGNAL,MP_FLAGS(a3)
        move.b  d6,MP_SIGBIT(a3)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a3)   ; se signale elle-même
        move.l  #TR_SIZE,d0          ; timerequest
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a2                ; a2 = timerequest
        move.l  a3,MN_REPLYPORT(a2)
        move.l  a4,IO_DEVICE(a2)
        move.l  #UNIT_MICROHZ,IO_UNIT(a2)   ; unité MICROHZ (CIA-B/INT6)
        move.l  VBL_COUNT,d5         ; T0 (ticks VBlank au départ ; d5 préservé par les appels exec)
.tt_loop:
        cmp.l   #SENT_T,d7           ; contexte intact après chaque switch ?
        bne     m7a_fail
        tst.l   VBL_CLASH            ; le gate IPL7 a-t-il été violé ? (RED -> != 0)
        bne     m7a_fail
        clr.l   TV_SECS(a2)          ; (ré)arme une requête MICROHZ réaliste : 20 ticks CIA-B (~7 ms)
        move.l  #400000,TV_MICRO(a2) ; 400000/20000 = 20 ticks -> ~140 réveils/s (coexiste avec la démo M3f ;
                                     ; 1 tick préemptait ~2800/s via le dispatch différé et starverait task_s/L)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a2)
        move.l  a6,-(sp)             ; BeginIO(a4 = base, a2 = requête)
        move.l  a4,a6
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
        moveq   #1,d0                ; Wait(1<<bit) : BLOQUE jusqu'au réveil MICROHZ
        move.l  d6,d1
        lsl.l   d1,d0
        jsr     LVO_WAIT(a6)
        move.l  a3,a0                ; GetMsg(reply port)
        jsr     LVO_GETMSG(a6)
        cmp.l   a2,d0                ; doit être NOTRE requête
        bne     m7a_fail
        addq.l  #1,WP_TCONS          ; un réveil MICROHZ réussi de plus
        btst    #1,WP_STAT
        bne     .tt_loop             ; marqueur déjà émis (branche word : corps de boucle long)
        move.l  WP_TCONS,d0
        cmp.l   #TCONS_THRESH,d0
        bcs     .tt_loop             ; pas encore assez de réveils
        move.l  VBL_COUNT,d0         ; ET assez de temps écoulé ? (fenêtre où un clash RED serait tombé)
        sub.l   d5,d0
        cmp.l   #M7A_MINTICKS,d0
        bcs     .tt_loop
        bset    #1,WP_STAT           ; émet « M7A TIMER OK » une seule fois
        jsr     LVO_FORBID(a6)
        lea     msg_m7a_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
        bra     .tt_loop

; task_port (pri 0, M7d) : CONSOMMATEUR TÂCHE du port de stress partagé. Boucle serrée GetMsg+PutMsg ;
; le PRODUCTEUR est timer_micro_service (INTERRUPTION). Ports interrupt-safe (Disable) -> la course
; GetMsg(tâche)/PutMsg(IRQ) sur le même MP_MSGLIST est sûre. En RED (ports remis en Forbid) elle corrompt
; la liste. Vérifie MAGIC (mauvais pointeur) + IN_HAND==0 (doublon) à chaque message. a4 = port (préservé
; par GetMsg/PutMsg = scratch d0/d1/a0/a1). Émet « M7D PORTS OK » quand les 2 compteurs passent sans fail.
task_port:
        move.l  ($4).w,a6
        move.l  #SENT_P,d7
        moveq   #0,d6                ; d6 = compteur de GetMsg vides CONSÉCUTIFs (détecteur de nœuds perdus)
.pp_wait:
        move.l  WP_SPORT,a4          ; attendre que le port existe (créé pré-handoff -> déjà prêt)
        move.l  a4,d0
        beq.s   .pp_wait
.pp_loop:
        cmp.l   #SENT_P,d7
        bne.w   demo_fail            ; contexte corrompu par un switch
        move.l  a4,a0                ; GetMsg(SP)
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .pp_empty            ; vide -> compter (K messages circulent, le port n'est quasi
        move.l  d0,a1                ; jamais vide ; vide PROLONGÉ = nœuds perdus par corruption)
        cmp.l   #STRESS_MAGIC,MSG_MAGIC_OFF(a1)
        bne     m7d_fail             ; mauvais pointeur -> corruption de liste
        tst.l   MSG_INHAND_OFF(a1)
        bne     m7d_fail             ; déjà « en main » -> doublon = corruption
        move.l  #1,MSG_INHAND_OFF(a1)
        clr.l   MSG_INHAND_OFF(a1)
        move.l  a4,a0                ; PutMsg(SP, msg)
        jsr     LVO_PUTMSG(a6)
        addq.l  #1,WP_PORTT
        moveq   #0,d6                ; message obtenu -> reset du compteur de vides
        bra.s   .pp_emit
.pp_empty:
        addq.l  #1,d6
        cmp.l   #PEMPTY_LIMIT,d6
        bcc     m7d_fail             ; port vide trop longtemps -> nœuds perdus = corruption
.pp_emit:
        btst    #0,M7D_STAT
        bne     .pp_loop             ; marqueur déjà émis
        tst.l   WP_PORTFAIL          ; corruption vue côté interruption ?
        bne     m7d_fail
        move.l  WP_PORTT,d0
        cmp.l   #PORTT_THRESH,d0
        bcs     .pp_loop             ; pas assez d'itérations côté tâche
        move.l  WP_PORTI,d0
        cmp.l   #PORTI_THRESH,d0
        bcs     .pp_loop             ; pas assez côté interruption (producteur)
        bset    #0,M7D_STAT
        jsr     LVO_FORBID(a6)
        lea     msg_m7d_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
        bra     .pp_loop
m7d_fail:                            ; corruption de liste de port (RED) -> preuve
        jsr     LVO_FORBID(a6)
        lea     msg_m7d_fail(pc),a0
        bsr     ser_puts
.m7df_hang:
        bra.s   .m7df_hang

demo_fail:                           ; sentinelle KO -> preuve de corruption
        jsr     LVO_FORBID(a6)
        lea     msg_m3ffail(pc),a0
        bsr     ser_puts
.df_hang:
        bra.s   .df_hang
task_exit:                           ; filet si une tâche faisait RTS (ne doit pas arriver)
        bra.s   task_exit

; ============================ résidents démo (M4) ==================
; 3 ROMTags scannés par build_reslist puis initialisés par InitCode en ordre de PRIORITÉ
; DÉCROISSANTE (hi=60, mid=10, lo=-20). Chacun partage res_demo_init, qui vérifie que sa
; RT_PRI n'est PAS supérieure à la précédente (ordre décroissant maintenu) puis émet son
; nom. Preuve : noms émis hi->mid->lo dans le log + RES_COUNT==3.
; IMPORTANT : rangés en mémoire dans un ordre (mid, lo, hi) DIFFÉRENT de l'ordre de
; priorité, pour que le TRI de build_reslist soit load-bearing (sinon l'ordre de scan
; suffirait). ROMTags non-AUTOINIT (direct-init). Alignement PAIR obligatoire (le scan
; lit des mots à adresses paires ; RT_ENDSKIP doit rester pair).
        EVEN
res_mid:
        dc.w    RTC_MATCHWORD
        dc.l    res_mid              ; RT_MATCHTAG = self (valide le match)
        dc.l    res_mid_end          ; RT_ENDSKIP
        dc.b    0,1,NT_RESOURCE,10   ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    res_mid_name         ; RT_NAME
        dc.l    res_mid_name         ; RT_IDSTRING
        dc.l    res_mid_init         ; RT_INIT (routine propre au module)
res_mid_name:
        dc.b    "demo.res.mid",0
        EVEN
res_mid_end:
res_lo:
        dc.w    RTC_MATCHWORD
        dc.l    res_lo
        dc.l    res_lo_end
        dc.b    0,1,NT_RESOURCE,-20
        dc.l    res_lo_name
        dc.l    res_lo_name
        dc.l    res_lo_init
res_lo_name:
        dc.b    "demo.res.lo",0
        EVEN
res_lo_end:
res_hi:
        dc.w    RTC_MATCHWORD
        dc.l    res_hi
        dc.l    res_hi_end
        dc.b    0,1,NT_RESOURCE,60
        dc.l    res_hi_name
        dc.l    res_hi_name
        dc.l    res_hi_init
res_hi_name:
        dc.b    "demo.res.hi",0
        EVEN
res_hi_end:

; Routines d'init des résidents démo. Appelées par InitResident avec la convention ABI
; direct-init (D0=0, A0=segList, A6=SysBase) : le pointeur resident n'est PAS fourni, donc
; chaque routine connaît STATIQUEMENT sa priorité et son nom (comme un vrai module). Elles
; passent (d0=pri signée, a1=nom) à res_demo_common.
res_hi_init:
        moveq   #60,d0
        lea     res_hi_name(pc),a1
        bra.s   res_demo_common
res_mid_init:
        moveq   #10,d0
        lea     res_mid_name(pc),a1
        bra.s   res_demo_common
res_lo_init:
        moveq   #-20,d0
        lea     res_lo_name(pc),a1
        ; tombe dans res_demo_common
; res_demo_common : d0 = RT_PRI (signée, longword via moveq), a1 = nom. Vérifie l'ordre
; décroissant via RES_LASTPRI, compte dans RES_COUNT, émet le nom + CRLF. Retourne d0=0.
res_demo_common:
        cmp.l   RES_LASTPRI,d0
        bgt     res_fail             ; pri > précédente -> ordre CROISSANT = scan/tri FAUX
        move.l  d0,RES_LASTPRI
        addq.l  #1,RES_COUNT
        move.l  a1,a0                ; nom
        bsr     ser_puts             ; émet le nom (ordre visible hi->mid->lo)
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        moveq   #0,d0
        rts

res_fail:                            ; échec M4 (scan/ordre/dispatch) -> fige
        lea     msg_res_fail(pc),a0
        bsr     ser_puts
.resf_hang:
        bra.s   .resf_hang
auto_fail:                           ; échec M5a (AUTOINIT/MakeLibrary) -> fige
        lea     msg_auto_fail(pc),a0
        bsr     ser_puts
.autof_hang:
        bra.s   .autof_hang
cia_fail:                            ; échec M5b (cia.resource) -> fige
        lea     msg_cia_fail(pc),a0
        bsr     ser_puts
.ciaf_hang:
        bra.s   .ciaf_hang
timer_fail:                          ; échec M5c (timer.device) -> fige
        lea     msg_timer_fail(pc),a0
        bsr     ser_puts
.tmrf_hang:
        bra.s   .tmrf_hang
m6a_fail:                            ; échec M6a (unité VBLANK timer) -> fige
        lea     msg_m6a_fail(pc),a0
        bsr     ser_puts
.m6af_hang:
        bra.s   .m6af_hang
m7b_fail:                            ; échec M7b (dispatcher par numéro / chaîne PORTS) -> fige
        lea     msg_m7b_fail(pc),a0
        bsr     ser_puts
.m7bf_hang:
        bra.s   .m7bf_hang
m7a_fail:                            ; échec M7a (gate de ré-entrance / unité MICROHZ) -> fige
        jsr     LVO_FORBID(a6)       ; émission non fractionnée (atteint depuis le contexte tâche)
        lea     msg_m7a_fail(pc),a0
        bsr     ser_puts
.m7af_hang:
        bra.s   .m7af_hang
; struct Interrupt de test (M6b) : IS_CODE -> cia_test_vec (incrémente CIA_FIRED).
        EVEN
cia_test_int:
        dcb.b   14,0                 ; LN (non chaîné)
        dc.l    0                    ; IS_DATA
        dc.l    cia_test_vec         ; IS_CODE
cia_test_vec:                        ; serveur ICR (a1=data, a5=code, a6=SysBase)
        addq.l  #1,CIA_FIRED
        rts
cia_dummy_int:                       ; fausse struct Interrupt (AddICRVector ne stocke que le ptr)
        dc.l    0,0,0,0,0

; int2_srv2 (M7b) : 2e serveur de la chaîne PORTS (pri 0, après ciaa_server pri 10). Incrémente
; INT2_SRV2 et capture l'ordre (CIA_FIRED > 0 au 1er appel => ciaa_server a tourné avant = pri OK).
; a1=IS_DATA (inutilisé), a6=SysBase. Préserve d2-d7/a2-a4 (ne touche que d0 + mémoire). Z MIS (continue).
int2_srv2:
        addq.l  #1,INT2_SRV2
        tst.l   INT2_ORDER_SNAP      ; déjà capturé ?
        bne.s   .s2_z
        move.l  CIA_FIRED,d0         ; ciaa_server (pri 10) a-t-il déjà tourné dans CET INT2 ?
        beq.s   .s2_z                ; pas encore -> on capturera à un INT2 ultérieur
        move.l  d0,INT2_ORDER_SNAP   ; > 0 -> ordre de priorité confirmé (ciaa avant srv2)
.s2_z:
        moveq   #0,d0                ; Z set -> continue la chaîne
        rts

; ciab_server_int (M7b) : vecteur EXCLUSIF EXTER installé par SetIntVector -> ciab_server. Non chaîné
; (SetIntVector copie IS_DATA/IS_CODE) -> peut rester en ROM. IS_DATA inutilisé (ciab_server lit CIAB_PTR).
        EVEN
ciab_server_int:
        dc.l    0                    ; LN_SUCC
        dc.l    0                    ; LN_PRED
        dc.b    0                    ; LN_TYPE
        dc.b    0                    ; LN_PRI (inusité : vecteur exclusif)
        dc.l    srv_ciab_name        ; LN_NAME
        dc.l    0                    ; IS_DATA
        dc.l    ciab_server          ; IS_CODE
srv_ciab_name:
        dc.b    "ciab.exter",0
        EVEN

; ============================ résident AUTOINIT démo (M5a) =========
; ROMTag RTF_AUTOINIT (pri 40) -> InitResident appelle MakeLibrary avec la table de 4 longs.
; Prouve : jump table bâtie (func0 rend $5A), InitStruct pose version/type, init func pose
; la révision + le nom, lib ajoutée à LibList. Table de vecteurs ABSOLUE (longwords, -1).
; Data table = INITWORD(LIB_VERSION,40) + INITBYTE(LN_TYPE,NT_LIBRARY). Le nom (adresse) est
; posé par l'init func (PC-relative), pas par InitStruct (une adresse relogée ne peut pas être
; scindée en deux mots à l'assemblage).
        EVEN
res_auto:
        dc.w    RTC_MATCHWORD
        dc.l    res_auto             ; RT_MATCHTAG = self
        dc.l    res_auto_end         ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT,1,NT_LIBRARY,40  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    autolib_name         ; RT_NAME
        dc.l    autolib_name         ; RT_IDSTRING
        dc.l    autolib_inittab      ; RT_INIT -> table AUTOINIT (4 longs)
autolib_name:
        dc.b    "demo.autolib",0
        EVEN
autolib_inittab:
        dc.l    LIB_SIZE             ; dataSize (base mini)
        dc.l    autolib_vectors      ; funcTable
        dc.l    autolib_datatab      ; dataTable (InitStruct)
        dc.l    autolib_initfunc     ; initFunc
autolib_vectors:                     ; table RELATIVE (exerce la détection + l'arithmétique word)
        dc.w    -1                            ; marqueur : déplacements word relatifs à cette base
        dc.w    autolib_func0-autolib_vectors ; LVO -6
        dc.w    autolib_func1-autolib_vectors ; LVO -12
        dc.w    -1                            ; terminateur (word)
autolib_datatab:
        dc.w    $D000,LIB_VERSION,40          ; INITWORD(LIB_VERSION, 40)
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8) ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.b    0                             ; terminateur du flux InitStruct
        EVEN
autolib_func0:                       ; appelée via jsr -6(base) -> preuve MakeFunctions
        moveq   #$5A,d0
        rts
autolib_func1:                       ; LVO -12 (non exercée)
        moveq   #0,d0
        rts
autolib_initfunc:                    ; (D0=base, A0=segList, A6=ExecBase) -> D0 = base
        move.l  d0,a1                ; a1 = base
        move.w  #$5A,LIB_REVISION(a1) ; preuve : l'init func a tourné
        lea     autolib_name(pc),a0
        move.l  a0,LN_NAME(a1)       ; nom (adresse, PC-relative) -> OpenLibrary/FindName
        rts                          ; d0 = base inchangé
        EVEN
res_auto_end:

; ============================ données ==============================
exec_name:
        dc.b    "exec.library",0
exec_id:
        dc.b    "exec 34.2 (clean-room reimpl)",13,10,0
str_alpha:
        dc.b    "alpha",0
str_beta:
        dc.b    "beta",0
str_gamma:
        dc.b    "gamma",0
task_test_name:
        dc.b    "testtask",0
str_port:
        dc.b    "testport",0
task_h_name:
        dc.b    "demo.H",0
task_l_name:
        dc.b    "demo.L",0
task_s_name:
        dc.b    "demo.S",0
task_t_name:
        dc.b    "demo.timer",0
task_p_name:
        dc.b    "demo.port",0
msg_cold:
        dc.b    "EXEC coldstart: overlay off, stack live",13,10,0
msg_ok:
        dc.b    "EXEC ExecBase + jump table OK, self-test passed",13,10,0
msg_fail:
        dc.b    "EXEC self-check/self-test FAILED",13,10,0
chk_core:
        dc.b    "chk core",13,10,0
chk_mem:
        dc.b    "chk mem",13,10,0
chk_m24a:
        dc.b    "chk m24a",13,10,0
chk_m24b:
        dc.b    "chk m24b",13,10,0
chk_m24c:
        dc.b    "chk m24c",13,10,0
msg_vblok:
        dc.b    "M3 VBlank interrupts live",13,10,0
msg_vbltimeout:
        dc.b    "M3 VBL timeout",13,10,0
msg_m3flive:
        dc.b    "M3F LIVE: preemption + yield coexist (both scheduling paths OK)",13,10,0
msg_m3ffail:
        dc.b    "M3F FAILED: context sentinel corrupted across a switch",13,10,0
msg_res_ok:
        dc.b    "M4 RESIDENTS OK (scan + InitResident in priority order)",13,10,0
msg_auto_ok:
        dc.b    "M5A AUTOINIT OK (MakeLibrary + MakeFunctions + InitStruct)",13,10,0
msg_res_fail:
        dc.b    "M4 FAILED: resident scan/init incorrect",13,10,0
msg_auto_fail:
        dc.b    "M5A FAILED: AUTOINIT/MakeLibrary incorrect",13,10,0
msg_cia_ok:
        dc.b    "M5B CIA OK (cia.resource: OpenResource + AbleICR + AddICRVector)",13,10,0
msg_cia_fail:
        dc.b    "M5B FAILED: cia.resource incorrect",13,10,0
msg_timer_ok:
        dc.b    "M5C TIMER OK (timer.device AUTOINIT -> DeviceList, Open works)",13,10,0
msg_timer_fail:
        dc.b    "M5C FAILED: timer.device incorrect",13,10,0
msg_m6a_ok:
        dc.b    "M6A TIMER OK (VBLANK unit: request replied after ~5 ticks)",13,10,0
msg_m6a_fail:
        dc.b    "M6A FAILED: timer VBLANK unit incorrect",13,10,0
msg_m7b_ok:
        dc.b    "M7B PORTS OK (per-number dispatch: AddIntServer chain, 2 servers in pri order)",13,10,0
msg_m7b_fail:
        dc.b    "M7B FAILED: per-number interrupt dispatch / server chain incorrect",13,10,0
msg_m7a_ok:
        dc.b    "M7A TIMER OK (MICROHZ via CIA-B/INT6: task woke on timer, reentrancy gate held)",13,10,0
msg_m7a_fail:
        dc.b    "M7A FAILED: MICROHZ wake or scheduler-list reentrancy gate",13,10,0
msg_m7c_ok:
        dc.b    "M7C USERMODE OK (user-mode tasks on shared SSP, deferred Dispatch survives preemption)",13,10,0
msg_m7d_ok:
        dc.b    "M7D PORTS OK (interrupt-safe PutMsg/GetMsg: task vs IRQ race on shared port, no corruption)",13,10,0
msg_m7d_fail:
        dc.b    "M7D FAILED: shared-port list corrupted (task GetMsg vs IRQ PutMsg race)",13,10,0
ciaa_test_name:
        dc.b    "ciaa.resource",0
ciab_test_name:
        dc.b    "ciab.resource",0
timer_test_name:
        dc.b    "timer.device",0
msg_crlf:
        dc.b    13,10,0
        EVEN
