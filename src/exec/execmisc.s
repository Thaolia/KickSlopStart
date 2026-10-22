; src/exec/execmisc.s — exec.library : fonctions V34 documentées qui manquaient à la table de vecteurs (SetFunction,
; SumLibrary, Cause et la file des interruptions logicielles, Alert, SetSR, SuperState/UserState, GetCC,
; RemIntServer, AllocEntry/FreeEntry, SetExcept, AllocTrap/FreeTrap, RemResource, Raw*, Obtain/ReleaseSemaphoreList).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs exec + includes publics (exec/libraries.i, exec/tasks.i, exec/memory.i).
; AUCUNE lecture ROM.

                include "exec.i"

                xdef    exec_SetFunction
                xdef    exec_SumLibrary
                xdef    exec_Cause
                xdef    exec_softint_init
                xdef    exec_Alert
                xdef    exec_SetSR
                xdef    exec_SuperState
                xdef    exec_UserState
                xdef    exec_GetCC
                xdef    exec_RemIntServer
                xdef    exec_AllocEntry
                xdef    exec_FreeEntry
                xdef    exec_SetExcept
                xdef    exec_AllocTrap
                xdef    exec_FreeTrap
                xdef    exec_RemResource
                xdef    exec_RawIOInit
                xdef    exec_RawMayGetChar
                xdef    exec_RawPutChar
                xdef    exec_ObtainSemaphoreList
                xdef    exec_ReleaseSemaphoreList

LVO_SUPERVISOR_X EQU -30
ME_SIZE         EQU 8                ; struct MemEntry : me_Reqs|me_Addr, me_Length
INTENA_INTEN    EQU 14               ; bit maître de INTENA

; SetFunction(library a1, funcOffset a0.w, newFunction d0) -> d0 = ancienne fonction. Le vecteur devient
; JMP newFunction ; la bibliothèque est marquée modifiée et sa somme recalculée. Sous Forbid.
exec_SetFunction:
        move.l  d0,d1
        move.w  a0,d0
        ext.l   d0
        lea     0(a1,d0.l),a0        ; a0 = vecteur
        jsr     LVO_FORBID(a6)
        move.l  2(a0),-(sp)          ; ancienne fonction
        move.w  #$4EF9,(a0)
        move.l  d1,2(a0)
        bset    #LIBB_CHANGED,LIB_FLAGS(a1)
        bsr.s   exec_SumLibrary
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,d0
        rts

; SumLibrary(library a1) : somme des mots de la table de vecteurs. Table modifiée (LIBF_CHANGED) ou somme non
; vérifiée : la somme est enregistrée et LIBF_CHANGED effacé. (Pas d'alerte sur écart : aucune table n'est
; protégée ici.) Clobbe d0/d1/a0.
exec_SumLibrary:
        moveq   #0,d0
        moveq   #0,d1
        move.w  LIB_NEGSIZE(a1),d1
        lsr.w   #1,d1
        move.l  a1,a0
        sub.l   d1,a0
        sub.l   d1,a0                ; a0 = début de la table
        bra.s   .sl_nx
.sl_lp:
        add.w   (a0)+,d0
.sl_nx:
        dbra    d1,.sl_lp
        move.l  d0,LIB_SUM(a1)
        bclr    #LIBB_CHANGED,LIB_FLAGS(a1)
        rts

; Cause(interrupt a1) : l'interruption logicielle est mise en file (une seule fois tant qu'elle attend) puis
; SOFTINT est demandée ; le serveur de niveau 1 l'exécute (a1 = is_Data, a5 = is_Code, a6 = SysBase). Appelable
; depuis une interruption : masquage par INTENA (état maître restauré), jamais Disable/Enable (qui peuvent céder).
exec_Cause:
        move.w  INTENAR,d1
        move.w  #INTF_INTEN,INTENA
        cmp.b   #NT_SOFTINT,LN_TYPE(a1)
        beq.s   .ca_done             ; déjà en attente
        move.b  #NT_SOFTINT,LN_TYPE(a1)
        move.l  d1,-(sp)
        lea     EXEC_SOFTLIST,a0
        jsr     LVO_ADDTAIL(a6)
        move.l  (sp)+,d1
        move.w  #(INTF_SETCLR|INTF_SOFTINT),INTREQ
.ca_done:
        btst    #INTENA_INTEN,d1
        beq.s   .ca_ret
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
.ca_ret:
        rts

; exec_softint_init(a6) : file vide, serveur SOFTINT installé (vecteur exclusif du niveau 1) et source activée.
; Après init_ints (table IntVects allouée).
exec_softint_init:
        lea     EXEC_SOFTLIST,a0
        move.l  a0,8(a0)             ; lh_TailPred = &lh_Head
        addq.l  #LH_TAIL,a0
        move.l  a0,-LH_TAIL(a0)      ; lh_Head = &lh_Tail
        clr.l   (a0)                 ; lh_Tail = 0
        moveq   #INTB_SOFTINT,d0
        lea     softint_is(pc),a1
        jsr     LVO_SETINTVECTOR(a6)
        move.w  #INTF_SOFTINT,INTREQ
        move.w  #(INTF_SETCLR|INTF_SOFTINT),INTENA
        rts

; softint_server (niveau 1, a6 = SysBase) : acquitte SOFTINT puis exécute les interruptions en attente dans l'ordre.
softint_server:
        move.w  #INTF_SOFTINT,INTREQ
.ss_lp:
        move.w  #INTF_INTEN,INTENA
        lea     EXEC_SOFTLIST,a0
        jsr     LVO_REMHEAD(a6)
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
        tst.l   d0
        beq.s   .ss_ret
        move.l  d0,a1
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        move.l  IS_CODE(a1),a5
        move.l  IS_DATA(a1),a1
        jsr     (a5)
        move.l  ($4).w,a6
        bra.s   .ss_lp
.ss_ret:
        rts

; Alert(alertNum d7) : message série. Alerte récupérable (bit 31 à 0) : retour à l'appelant. Sans issue : machine
; arrêtée (interruptions coupées, écran rouge).
exec_Alert:
        movem.l d0-d2/a0,-(sp)
        lea     al_dead(pc),a0
        tst.l   d7
        bmi.s   .al_msg
        lea     al_rec(pc),a0
.al_msg:
        bsr.s   raw_puts
        move.l  d7,d2
        moveq   #7,d1
.al_hex:
        rol.l   #4,d2
        moveq   #15,d0
        and.w   d2,d0
        move.b  al_digits(pc,d0.w),d0
        bsr.s   exec_RawPutChar
        dbra    d1,.al_hex
        moveq   #10,d0
        bsr.s   exec_RawPutChar
        tst.l   d7
        bmi.s   .al_halt
        movem.l (sp)+,d0-d2/a0
        rts
.al_halt:
        move.w  #$7FFF,INTENA
.al_stop:
        move.w  #$0F00,COLOR00
        bra.s   .al_stop
al_digits:
        dc.b    "0123456789ABCDEF"

; raw_puts(a0 = chaîne C) : émission série par RawPutChar. Clobbe d0/a0.
raw_puts:
        move.b  (a0)+,d0
        beq.s   .rp_ret
        bsr.s   exec_RawPutChar
        bra.s   raw_puts
.rp_ret:
        rts

; RawIOInit() : le port série est déjà réglé au démarrage. RawMayGetChar() -> d0 = caractère reçu | -1.
; RawPutChar(char d0) : attente bornée de TBE puis émission (8 bits + bit d'arrêt). Préserve d1-d2/a0/a1.
exec_RawIOInit:
        rts
exec_RawMayGetChar:
        move.w  SERDATR,d0
        btst    #14,d0               ; RBF
        beq.s   .rg_none
        and.l   #$FF,d0
        move.w  #INTF_RBF,INTREQ
        rts
.rg_none:
        moveq   #-1,d0
        rts
exec_RawPutChar:
        movem.l d1-d2,-(sp)
        move.w  #$2000,d1
.rpc_wt:
        move.w  SERDATR,d2
        btst    #13,d2               ; TBE
        dbne    d1,.rpc_wt
        and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (sp)+,d1-d2
        rts

; SetSR(newSR d0, mask d1) -> d0 = ancien SR : les bits de mask prennent la valeur de newSR (via Supervisor ; le SR
; empilé par le trap est modifié puis rétabli par RTE).
exec_SetSR:
        move.l  a5,-(sp)
        lea     .sr_super(pc),a5
        jsr     LVO_SUPERVISOR_X(a6)
        move.l  (sp)+,a5
        rts
.sr_super:
        move.w  (sp),a1              ; ancien SR
        and.w   d1,d0
        not.w   d1
        and.w   d1,(sp)
        or.w    d0,(sp)
        move.w  a1,d0
        and.l   #$FFFF,d0
        rte

; SuperState() -> d0 = pile superviseur à rendre à UserState (0 si déjà en superviseur) : la suite s'exécute en
; superviseur sur la pile utilisateur.
exec_SuperState:
        move.w  sr,d0
        btst    #13,d0
        bne.s   .su_already
        move.l  a5,a1
        lea     .su_super(pc),a5
        jsr     LVO_SUPERVISOR_X(a6) ; revient en superviseur par .su_super
        rts
.su_already:
        moveq   #0,d0
        rts
.su_super:
        move.l  a1,a5
        move.l  2(sp),a0             ; reprise : après le trap de Supervisor
        addq.l  #6,sp                ; frame du trap retiré
        move.l  sp,d0                ; pile superviseur
        move.l  usp,a1
        move.l  a1,sp                ; on continue sur la pile utilisateur
        jmp     (a0)

; UserState(sysStack d0) : retour en mode utilisateur sur la pile courante, la pile superviseur redevient sysStack.
; d0 = 0 (SuperState appelé en superviseur) : rien à faire.
exec_UserState:
        tst.l   d0
        beq.s   .us_ret
        move.l  (sp)+,a0
        move.l  sp,a1
        move.l  a1,usp
        move.l  d0,sp
        and.w   #$DFFF,sr
        jmp     (a0)
.us_ret:
        rts

; GetCC() -> d0 = codes condition (68000 : MOVE depuis SR permis en mode utilisateur).
exec_GetCC:
        move.w  sr,d0
        and.l   #$FF,d0
        rts

; RemIntServer(intNum d0, interrupt a1) : le serveur quitte sa chaîne, interruptions masquées pendant le retrait.
exec_RemIntServer:
        move.w  INTENAR,d1
        move.w  #INTF_INTEN,INTENA
        move.l  d1,-(sp)
        jsr     LVO_REMOVE(a6)
        move.l  (sp)+,d1
        btst    #INTENA_INTEN,d1
        beq.s   .ri_ret
        move.w  #(INTF_SETCLR|INTF_INTEN),INTENA
.ri_ret:
        rts

; AllocEntry(memList a0) -> d0 = nouvelle MemList (adresses remplies) | exigences de l'entrée en échec avec le bit 31
; posé (rien ne reste alloué). FreeEntry(memList a0) libère les entrées puis la MemList (a0 comme AllocEntry : exec_lib.fd ;
; icon.library enchaîne RemHead -> FreeEntry avec la MemList dans a0 et la liste encore dans a1).
exec_AllocEntry:
        movem.l d2-d3/a2-a3,-(sp)
        move.l  a0,a2                ; a2 = modèle
        moveq   #0,d2
        move.w  ML_NUMENTRIES(a2),d2
        move.l  d2,d0
        lsl.l   #3,d0
        add.l   #ML_ME,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ae_nolist
        move.l  d0,a3                ; a3 = copie
        move.w  d2,ML_NUMENTRIES(a3)
        moveq   #0,d3                ; d3 = entrées allouées
.ae_lp:
        cmp.w   d2,d3
        beq.s   .ae_ok
        move.l  d3,d0
        lsl.l   #3,d0
        lea     ML_ME(a2,d0.l),a0
        lea     ML_ME(a3,d0.l),a1
        move.l  4(a0),4(a1)          ; me_Length
        move.l  (a0),-(sp)           ; me_Reqs
        move.l  4(a0),d0
        move.l  (sp),d1
        move.l  a1,-(sp)
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a1
        move.l  (sp)+,d1
        tst.l   d0
        beq.s   .ae_fail
        move.l  d0,(a1)              ; me_Addr
        addq.w  #1,d3
        bra.s   .ae_lp
.ae_ok:
        move.l  a3,d0
        bra.s   .ae_ret
.ae_fail:
        move.l  d1,-(sp)             ; exigences en échec
        move.w  d3,ML_NUMENTRIES(a3) ; seules les entrées obtenues sont rendues
        move.l  a3,a0
        bsr.s   exec_FreeEntry
        move.l  (sp)+,d0
        bset    #31,d0
        bra.s   .ae_ret
.ae_nolist:
        moveq   #-1,d0               ; la MemList elle-même n'a pu être allouée
.ae_ret:
        movem.l (sp)+,d2-d3/a2-a3
        rts
exec_FreeEntry:
        movem.l d2/a2,-(sp)
        move.l  a0,a2
        moveq   #0,d2
        move.w  ML_NUMENTRIES(a2),d2
        lea     ML_ME(a2),a0
        bra.s   .fe_nx
.fe_lp:
        move.l  (a0)+,a1
        move.l  (a0)+,d0
        move.l  a0,-(sp)
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a0
.fe_nx:
        dbra    d2,.fe_lp
        moveq   #0,d0
        move.w  ML_NUMENTRIES(a2),d0
        lsl.l   #3,d0
        add.l   #ML_ME,d0
        move.l  a2,a1
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,d2/a2
        rts

; SetExcept(newSignals d0, signalMask d1) -> d0 = ancien tc_SigExcept (bits de mask remplacés).
exec_SetExcept:
        move.l  d2,-(sp)
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGEXCEPT(a0),d2
        and.l   d1,d0
        not.l   d1
        and.l   d2,d1
        or.l    d1,d0
        move.l  d0,TC_SIGEXCEPT(a0)
        move.l  d2,d0
        move.l  (sp)+,d2
        rts

; AllocTrap(trapNum d0 | -1 = n'importe lequel) -> d0 = n° de trap attribué à la tâche | -1. FreeTrap(trapNum d0).
exec_AllocTrap:
        move.l  EB_THISTASK(a6),a0
        move.w  TC_TRAPALLOC(a0),d1
        cmp.l   #-1,d0
        bne.s   .at_one
        moveq   #15,d0
.at_lp:
        btst    d0,d1
        beq.s   .at_got
        dbra    d0,.at_lp
        bra.s   .at_fail
.at_one:
        cmp.l   #15,d0
        bhi.s   .at_fail
        btst    d0,d1
        bne.s   .at_fail
.at_got:
        bset    d0,d1
        move.w  d1,TC_TRAPALLOC(a0)
        ext.l   d0
        rts
.at_fail:
        moveq   #-1,d0
        rts
exec_FreeTrap:
        move.l  EB_THISTASK(a6),a0
        move.w  TC_TRAPALLOC(a0),d1
        bclr    d0,d1
        move.w  d1,TC_TRAPALLOC(a0)
        rts

; RemResource(resource a1) : retrait de la liste des ressources, sous Forbid.
exec_RemResource:
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jmp     LVO_PERMIT(a6)

; ObtainSemaphoreList(list a0) / ReleaseSemaphoreList(list a0) : chaque SignalSemaphore de la liste, dans l'ordre.
exec_ObtainSemaphoreList:
        move.l  #LVO_OBTAINSEMAPHORE,d0
        bra.s   sem_walk
exec_ReleaseSemaphoreList:
        move.l  #LVO_RELEASESEMAPHORE,d0
sem_walk:
        movem.l d2/a2,-(sp)
        move.l  d0,d2
        move.l  (a0),a2
.sw_lp:
        tst.l   (a2)
        beq.s   .sw_ret
        move.l  a2,a0
        jsr     0(a6,d2.l)
        move.l  (a2),a2
        bra.s   .sw_lp
.sw_ret:
        movem.l (sp)+,d2/a2
        rts

softint_is:
        dcb.b   IS_DATA,0
        dc.l    0                    ; IS_DATA
        dc.l    softint_server       ; IS_CODE
al_dead:
        dc.b    10,"Software Failure ALERT ",0
al_rec:
        dc.b    10,"Recoverable Alert ",0
        even
