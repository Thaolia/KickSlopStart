; src/dos/workbench.s — résident workbench.task : le process que lance c:LoadWB.
; Spec : docs/analysis/workbench-task-v34.md (relue clean-room). Contrat avec LoadWB :
;   - ROMTag NT_TASK sans drapeau de classe : présent dans ResModules (FindResident) mais jamais initialisé au boot ;
;   - LoadWB fait CreateProc(..., seglist = BPTR(ROMTag+42), ...) : la troncature donne un faux segment à ROMTag+40
;     (lien) et un point d'entrée à ROMTag+44 (ROMTag aligné sur 4) ;
;   - le process doit répondre au message de LoadWB (28 octets : +$14 = BPTR du chemin, +$18 = drapeau -debug) dès son
;     initialisation, sinon LoadWB reste bloqué ; il se nomme « Workbench » (LoadWB le retrouve par FindTask) et
;     tourne en priorité 1.
; Portée : Workbench MINIMAL — ouvre l'écran Workbench (OpenWorkBench), sans bureau (ni fenêtre de fond, ni icônes :
; layers.library et icon.library/mathffp.library manquent). Le process vit indéfiniment comme le vrai et répond à
; tout message reçu sur son port public « Workbench ».
; Piste IMPLÉMENTATION (« clean ») : spec ci-dessus + AutoDocs exec/dos/workbench (WBStartup). AUCUNE lecture ROM.

                include "exec.i"
                include "dospkt.i"

LVO_OPENWORKBENCH EQU -210           ; intuition.library (intuition_lib.fd)

WB_MSGPATH      EQU $14              ; message de LoadWB : BPTR du chemin (-> cli_CommandDir)

                cnop    0,4
wb_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    wb_romtag            ; RT_MATCHTAG = self
        dc.l    wb_end               ; RT_ENDSKIP
        dc.b    0,34,NT_TASK,0       ; RT_FLAGS (aucune classe : lancé par LoadWB), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    wb_taskname          ; RT_NAME
        dc.l    wb_idstring          ; RT_IDSTRING
        dc.l    wb_entry             ; RT_INIT
        dcb.b   40-26,0              ; jusqu'au faux segment
        dc.l    0                    ; ROMTag+40 : lien du faux segment (fin de chaîne)
wb_entry:                            ; ROMTag+44 : point d'entrée du process créé par LoadWB
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a4   ; a4 = ce process
        lea     wb_procname(pc),a0
        move.l  a0,LN_NAME(a4)
        move.l  a4,a1
        moveq   #1,d0
        jsr     LVO_SETTASKPRI(a6)
        moveq   #CLI_SIZEOF,d0       ; faux CLI : les outils lancés plus tard y trouvent le chemin de commandes
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a3                ; a3 = CLI | 0
        tst.l   d0
        beq.s   .we_nocli
        lsr.l   #2,d0
        move.l  d0,PR_CLI(a4)
.we_nocli:
        lea     PR_MSGPORT(a4),a0    ; message de démarrage de LoadWB
        jsr     LVO_WAITPORT(a6)
        lea     PR_MSGPORT(a4),a0
        jsr     LVO_GETMSG(a6)
        move.l  d0,a1
        move.l  a3,d1
        beq.s   .we_reply
        move.l  WB_MSGPATH(a1),CLI_COMMANDDIR(a3)
.we_reply:
        jsr     LVO_REPLYMSG(a6)     ; réponse immédiate : LoadWB continue
        lea     wb_intname(pc),a1    ; écran Workbench (les fenêtres CON:/NEWCON: s'y ouvrent)
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   .we_noscr
        move.l  d0,a6
        jsr     LVO_OPENWORKBENCH(a6)
        move.l  ($4).w,a6
.we_noscr:
        moveq   #MP_SIZE,d0          ; port public « Workbench »
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .we_idle
        move.l  d0,a3                ; a3 = port
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        move.b  d0,MP_SIGBIT(a3)
        bmi.s   .we_idle
        move.l  a4,MP_SIGTASK(a3)
        move.b  #PA_SIGNAL,MP_FLAGS(a3)
        move.b  #NT_MSGPORT,LN_TYPE(a3)
        lea     wb_procname(pc),a0
        move.l  a0,LN_NAME(a3)
        move.l  a3,a1
        jsr     LVO_ADDPORT(a6)
.we_loop:                            ; boucle principale : répond à tout message (pas d'objets Workbench à gérer)
        move.l  a3,a0
        jsr     LVO_WAITPORT(a6)
.we_drain:
        move.l  a3,a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .we_loop
        move.l  d0,a1
        jsr     LVO_REPLYMSG(a6)
        bra.s   .we_drain
.we_idle:                            ; sans port : attente sans fin (le process ne se termine pas, comme le vrai)
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .we_idle

wb_taskname:
        dc.b    "workbench.task",0
wb_intname:
        dc.b    "intuition.library",0
wb_procname:
        dc.b    "Workbench",0
wb_idstring:
        dc.b    "workbench.task 34.1 (minimal)",13,10,0
        EVEN
wb_end:
