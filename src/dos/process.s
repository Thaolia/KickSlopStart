; src/dos/process.s — Process + CreateProc (D3a). Machinerie INTERNE dos : un Process = struct Task exec +
; pr_MsgPort embarqué (@PR_MSGPORT) + champs V34 jusqu'à pr_WindowPtr. proc_create bâtit le Process, initialise
; ENTIÈREMENT son pr_MsgPort dans le parent (sigbit réservé DOS_PORTSIG pré-alloué via TC_SIGALLOC -> pas de race :
; signaux level-latched + WaitPort teste la liste d'abord), puis AddTask. Renvoie l'APTR du port (PAS un BPTR).
;
; Piste IMPLÉMENTATION (« clean ») : docs/analysis/dos-v34-spec.md §4 (comportement CreateProc) + AutoDocs exec
; (AddTask/MsgPort) + AROS rom/dos (lecture seule). AUCUNE lecture ROM.
; Portée D3a : création + port ; pas de pr_GlobVec/pr_CLI/pr_CurrentDir câblés (CLI = plus tard). Les corps de
; process démarrent GPR à zéro (frame AddTask) -> ils rechargent SysBase depuis ($4).w eux-mêmes.

                include "exec.i"
                include "dospkt.i"

                xdef    proc_create

; proc_create(a6=SysBase, a0=nom, a1=entryPC, d0=priorité.b, d1=taille pile) -> d0 = APTR &pr_MsgPort | 0.
proc_create:
                movem.l d2-d4/a2-a4,-(sp)
                move.l  a0,a2                ; a2 = nom
                move.l  a1,a3                ; a3 = entryPC (corps du process)
                move.b  d0,d3                ; d3 = priorité
                move.l  d1,d4                ; d4 = taille pile
                move.l  #PR_SIZEOF,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fail
                move.l  d0,a4                ; a4 = Process (= base Task)
                move.l  a2,LN_NAME(a4)
                move.b  d3,LN_PRI(a4)
                move.b  #NT_PROCESS,LN_TYPE(a4)
                move.l  #SYS_SIGALLOC,TC_SIGALLOC(a4)   ; bits 0-15 réservés (dont DOS_PORTSIG=8)
                move.l  d4,d0                ; pile
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .fail_task
                move.l  d0,TC_SPLOWER(a4)
                add.l   d4,d0
                move.l  d0,TC_SPUPPER(a4)
                ; --- initialiser ENTIÈREMENT pr_MsgPort dans le parent (pas de handshake) ---
                lea     PR_MSGPORT(a4),a0    ; a0 = &pr_MsgPort
                move.b  #NT_MSGPORT,LN_TYPE(a0)
                move.b  #PA_SIGNAL,MP_FLAGS(a0)
                move.b  #DOS_PORTSIG,MP_SIGBIT(a0)
                move.l  a4,MP_SIGTASK(a0)    ; PutMsg signalera CE process sur son propre port
                lea     MP_MSGLIST(a0),a1    ; NEWLIST(mp_MsgList) en ligne
                move.l  a1,d0
                addq.l  #4,d0
                move.l  d0,(a1)              ; lh_Head = &lh_Tail
                clr.l   4(a1)                ; lh_Tail = 0
                move.l  a1,8(a1)             ; lh_TailPred = &lh_Head
                ; --- AddTask(a1=task, a2=initPC, a3=finalPC) ---
                move.l  a4,a1
                move.l  a3,a2                ; initPC = entryPC
                lea     proc_exit(pc),a3     ; finalPC (filet : un corps qui revient bloque)
                jsr     LVO_ADDTASK(a6)
                lea     PR_MSGPORT(a4),a0    ; renvoie l'APTR du port
                move.l  a0,d0
                bra.s   .ret
.fail_task:
                move.l  a4,a1
                move.l  #PR_SIZEOF,d0
                jsr     LVO_FREEMEM(a6)
.fail:
                moveq   #0,d0
.ret:
                movem.l (sp)+,d2-d4/a2-a4
                rts

; Filet de sécurité : si un corps de process RETOURNE (ne devrait pas — ils bouclent), bloquer pour toujours
; (Wait(0) ne se réveille jamais) plutôt que laisser AddTask sauter dans le vide.
proc_exit:
                move.l  ($4).w,a6
.pe:
                moveq   #0,d0
                jsr     LVO_WAIT(a6)
                bra.s   .pe
