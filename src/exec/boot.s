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
                xref    build_reslist    ; resident.s (scan des ROMTags)

DEMO_STK     EQU 2048         ; pile des tâches démo (frames de switch)
DEMO_SIG     EQU 16           ; bit de signal de task_H (hors 0-15 réservés système)
DEMO_PRI_H   EQU 10           ; task_H : haute priorité (cible du yield-sur-Permit)
CONS_THRESH  EQU 100          ; réveils de task_H (via yield) requis pour « M3F LIVE »
SPIN_THRESH  EQU 5            ; itérations de task_S (via préemption) requises pour « M3F LIVE »
SENT_H       EQU $CAFE0010    ; sentinelles de contexte (doivent survivre à TOUT switch)
SENT_L       EQU $CAFE0020
SENT_S       EQU $CAFE0030
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

        ; --- M3f : démo recombinaison yield + préemption (SCHED_ON=1) ---
        ; Préemption périodique RÉARMÉE, coexistant avec le yield-sur-Permit. 3 tâches :
        ; task_H (pri 10, cible du yield), task_L (pri 0, signale+yield+spin préemptible),
        ; task_S (pri 0, spinner pur). WP_CONS n'avance que si la préemption laisse task_L
        ; tourner (malgré task_S qui monopoliserait sans préemption) ET si le yield
        ; dispatche task_H -> preuve de coexistence.
        move.w  #$2700,sr            ; masque les interruptions pendant le setup
        bsr     setup_demo_tasks     ; task_H (pri 10) + task_L (pri 0) + task_S (pri 0)
        move.b  #1,SCHED_ON          ; ARME la préemption périodique
        lea     EB_TASKREADY(a6),a0  ; dispatch initial explicite (abandonne le contexte boot)
        jsr     LVO_REMHEAD(a6)      ; tête = task_H (pri 10) -> elle Wait d'abord
        move.l  d0,a1
        move.l  a1,EB_THISTASK(a6)
        move.b  #TS_RUN,TC_STATE(a1)
        move.l  TC_SPREG(a1),sp      ; bascule sur la pile de la 1re tâche
        movem.l (sp)+,d0-d7/a0-a6
        rte                          ; -> task_H (SR=$2000 : VBlank préempte + yield actif)

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
        movem.l (sp)+,d2/a2-a4
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
.s_loop:
        cmp.l   #SENT_S,d7
        bne.w   demo_fail            ; contexte corrompu par une PRÉEMPTION
        addq.l  #1,WP_SPIN
        move.l  #$00001000,d0
.s_spin:
        subq.l  #1,d0
        bne.s   .s_spin
        bra.s   .s_loop
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
msg_crlf:
        dc.b    13,10,0
        EVEN
