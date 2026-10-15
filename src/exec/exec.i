; src/exec/exec.i — constantes partagées exec.library (M2.3).
; Inclus par boot.s / lists.s / memory.s / library.s. Uniquement des EQU
; (faits d'ABI publics + carte mémoire du projet) : aucune logique, aucune donnée.
; Piste IMPLÉMENTATION (« clean ») : valeurs issues de docs/analysis/exec-spec.md,
; docs/exec-lvo-table.md et de l'ABI publique. AUCUNE lecture de la ROM.

                ifnd    EXEC_I
EXEC_I          equ     1

; --- Custom chip (Amiga HRM) ---
CUSTOM   EQU $DFF000
DMACON   EQU CUSTOM+$096
INTENA   EQU CUSTOM+$09A
INTREQ   EQU CUSTOM+$09C
INTENAR  EQU CUSTOM+$01C      ; M7g : lecture des interruptions activées
INTREQR  EQU CUSTOM+$01E      ; M7g : lecture des interruptions en attente
SERDAT   EQU CUSTOM+$030
SERPER   EQU CUSTOM+$032
SERDATR  EQU CUSTOM+$018
COLOR00  EQU CUSTOM+$180

; --- CIA-A (overlay / LED) ---
CIAA_PRA  EQU $BFE001
CIAA_DDRA EQU $BFE201

; --- Carte mémoire cible A500 512K ---
MAXCHIP      EQU $00080000
MH_CHIP      EQU $00000400     ; MemHeader chip
TST_LIST     EQU $00000420     ; scratch auto-test (listes)
TST_N1       EQU $00000440
TST_N2       EQU $00000460
HEAP_LOWER   EQU $00001000     ; tas géré
HEAP_UPPER   EQU $0007D000
FTEST_LO     EQU $0007D000     ; région DISJOINTE du tas pour le test multi-header
FTEST_HI     EQU $0007E000     ; (selftest M2.4a) ; = base basse de pile ensuite
EXECBASE     EQU $0007F000     ; SysBase (table V34 complète en dessous)
EXEC_NEGSIZE EQU $276          ; 105 vecteurs V34 (cf docs/exec-lvo-table.md)
EXEC_BLOCK   EQU EXECBASE-EXEC_NEGSIZE   ; bas de la jump table
EXEC_POSSIZE EQU $230
STACKTOP     EQU EXEC_BLOCK-$80 ; pile superviseur (gap de garde avant la table)

; --- Phases (RGB 12 bits) ---
C_RED    EQU $0F00
C_BLUE   EQU $000F
C_CYAN   EQU $00FF
C_WHITE  EQU $0FFF
C_FAIL   EQU $0F0F

SERPER_9600_PAL EQU 368
ROMBASE  EQU $FC0000

; --- Interruptions (hardware/intbits.i + autovecteurs 68000) ---
INTF_SETCLR  EQU $8000        ; INTENA/INTREQ : 1 = pose les bits, 0 = les efface
INTF_INTEN   EQU $4000        ; maître (INTEN)
INTF_COPER   EQU $0010        ; M7g : Copper (niveau 3, bit 4)
INTF_VERTB   EQU $0020        ; VBlank (niveau 3)
INTF_BLIT    EQU $0040        ; M7g : Blitter (niveau 3, bit 6)
INTF_PORTS   EQU $0008        ; INT2 / CIA-A
INTF_EXTER   EQU $2000        ; INT6 / CIA-B
AUTOVEC_L2   EQU $68          ; autovecteur 68000 niveau 2 (INT2 / CIA-A / PORTS)
AUTOVEC_L3   EQU $6C          ; vecteur d'exception 68000, interruption niveau 3
AUTOVEC_L6   EQU $78          ; autovecteur 68000 niveau 6 (INT6 / CIA-B / EXTER)
TRAP0_VEC    EQU $80          ; M7c : vecteur TRAP #0 (switch volontaire style Wait : sortante déjà rangée)
TRAP1_VEC    EQU $84          ; M7c : vecteur TRAP #1 (yield/reschedule : requeue sortante -> TaskReady)
; M7c — frame de contexte (miroir movem d0-d7/a0-a6 + {SR,PC} du CPU), posée sur la pile de la tâche.
; 15 longs GPR (60 o) + SR (mot, offset 60) + PC (long, offset 62) = 66 o (pair -> copie mot par mot).
FRAME_SR     EQU 60           ; offset du SR sauvegardé dans la frame (test du bit S = frontière user)
FRAME_SIZE   EQU 66           ; taille totale de la frame relocalisée (GPR+SR+PC)
INTB_PORTS   EQU 3            ; numéro d'interruption Paula PORTS (INT2) — cf. hardware/intbits.i
INTB_COPER   EQU 4            ; M7g : numéro COPER (INT3) — INTF_COPER=$0010=bit4
INTB_VERTB   EQU 5            ; M7f : numéro VERTB (INT3) — INTF_VERTB=$0020=bit5
INTB_BLIT    EQU 6            ; M7g : numéro BLIT (INT3) — INTF_BLIT=$0040=bit6
INTB_EXTER   EQU 13           ; numéro d'interruption Paula EXTER (INT6)
; struct Interrupt (exec/interrupts.i) — serveur / vecteur ICR
IS_DATA      EQU 14           ; APTR passé en a1 au serveur
IS_CODE      EQU 18           ; APTR code du serveur (appelé a1=data, a5=code, a6=SysBase, a0=$DFF000)
IS_SIZE      EQU 22           ; sizeof(struct Interrupt) = LN(14) + IS_DATA(4) + IS_CODE(4)
IS_STRIDE    EQU 24           ; IS_SIZE arrondi à un multiple de 4 (nœuds alignés dans un tableau)
; M7b — dispatcher par numéro : table IntVects (SetIntVector/AddIntServer). Chaque entrée IntVects[n]
; = {IV_DATA, IV_CODE} ; pour une chaîne (AddIntServer) IV_DATA=&svlist[n], IV_CODE=intr_chain_walker ;
; pour un vecteur exclusif (SetIntVector) IV_DATA/IV_CODE = IS_DATA/IS_CODE copiés. Les svlist[n] (struct
; List de serveurs, triés par LN_PRI) suivent les 16 vecteurs dans le même bloc AllocMem'd.
IV_DATA      EQU 0
IV_CODE      EQU 4
IV_SIZE      EQU 8
INTVECTS_NVEC EQU 16          ; numéros 0..15 (14 = INTEN inusité, 15 = NMI)
IV_LIST_SIZE EQU 14           ; sizeof(struct List) d'une chaîne de serveurs
INTVECTS_SVOFF EQU (INTVECTS_NVEC*IV_SIZE)                       ; offset des svlist dans le bloc
INTVECTS_TOTAL EQU (INTVECTS_NVEC*IV_SIZE+INTVECTS_NVEC*IV_LIST_SIZE) ; 128+224=352 (PAS d'espace : vasm tronque l'opérande à l'espace)
; CIA timer A — registres (offsets depuis la base CIA = registre<<8)
CIA_TALO     EQU $400         ; timer A low
CIA_TAHI     EQU $500         ; timer A high (l'écriture charge le latch)
CIA_CRA      EQU $E00         ; control register A (b0=START, b3=RUNMODE 1-shot, b4=LOAD)
VBL_COUNT    EQU $00000500    ; compteur VBlank en RAM basse réservée (sous le tas)
SCHED_ON     EQU $00000504    ; drapeau : 1 = ordonnanceur armé (le handler switch)
WP_HTASK     EQU $00000508    ; démo M3e/f : TCB de task_H (pour que task_L la signale)
WP_CONS      EQU $0000050C    ; démo M3e/f : réveils consommés par task_H (via yield-sur-Permit)
WP_PROD      EQU $00000510    ; démo M3e/f : itérations de task_L (producteur, ne bloque jamais)
WP_SPIN      EQU $00000514    ; démo M3f : itérations de task_S (dispatchée SEULEMENT par préemption)
WP_STAT      EQU $00000518    ; démo M3f : b0 = marqueur « M3F LIVE » déjà émis
RES_LASTPRI  EQU $0000051C    ; démo M4 : dernière RT_PRI initée (vérif ordre décroissant)
RES_COUNT    EQU $00000520    ; démo M4 : nombre de résidents démo initialisés
; $00000524 : ex-VBL_SVC (hook VBlank M6a) — RETIRÉ en M7f (timer_vblank est un serveur de chaîne VERTB)
VBL_SVCDATA  EQU $00000528    ; M6a : base du timer.device (passée en a1 au serveur ; lue par timer_micro_service)
CIAA_PTR     EQU $0000052C    ; M6b : base ciaa.resource (0 tant que non créé)
CIAB_PTR     EQU $00000530    ; M6b : base ciab.resource
CIA_FIRED    EQU $00000534    ; M6b : compteur — un vecteur ICR a été servi (preuve)
WP_TCONS     EQU $00000538    ; M7a démo : réveils de task_timer (bloque sur l'unité MICROHZ)
VBL_INSURG   EQU $0000053C    ; M7a : UBYTE — chirurgie de listes du scheduler EN COURS (vbl_handler).
                              ; Posé AVANT l'Enqueue/RemHead TaskReady, effacé APRÈS, à IPL7 (donc
                              ; invisible à INT6). Une source de niveau > 3 (INT6/CIA-B) qui l'observe
                              ; posée a préempté la chirurgie = hazard de ré-entrance -> incrémente VBL_CLASH.
VBL_CLASH    EQU $00000540    ; M7a : compteur de clashs observés (0 si le gate IPL7 tient ; > 0 en RED)
INT2_SRV2    EQU $00000544    ; M7b : compteur du 2e serveur de la chaîne PORTS (prouve AddIntServer)
INT2_ORDER_SNAP EQU $00000548 ; M7b : CIA_FIRED au 1er appel du 2e serveur (> 0 => cia pri 10 avant srv2 pri 0)
WP_HEART     EQU $0000054C    ; M7c : battement de la tâche user-mode (first-light : survit aux préemptions)
WP_UMODE     EQU $00000550    ; M7c : UBYTE — une tâche s'est observée en USER mode (SR bit S == 0)
M7C_STAT     EQU $00000554    ; M7c : UBYTE — b0 = marqueur « M7C USERMODE OK » déjà émis
WP_UPREEMPT  EQU $00000558    ; M7c : préemptions observées (VBL_COUNT au démarrage de la preuve)
; M7d — preuve de concurrence ports interrupt-safe : port partagé martelé par une TÂCHE et une INTERRUPTION
WP_SPORT     EQU $0000055C    ; APTR : port de stress partagé (0 tant que non créé)
WP_PORTT     EQU $00000560    ; itérations GetMsg+PutMsg de task_port (consommateur TÂCHE)
WP_PORTI     EQU $00000564    ; itérations GetMsg+PutMsg du service MICROHZ (producteur INTERRUPTION)
WP_PORTFAIL  EQU $00000568    ; != 0 : corruption détectée côté interruption (MAGIC/IN_HAND KO)
M7D_STAT     EQU $0000056C    ; UBYTE : b0 = « M7D PORTS OK » déjà émis
STRESS_TICK  EQU $0000056D    ; UBYTE : compteur pour rate-limiter le stress côté INT6 (1 sur 4)
; M7D_STRESS_MAX : 0 = démo de COEXISTENCE (task_port pri 0 + stress rate-limité 1/4, coexiste avec
; M3f/M7a/M7c). 1 = CONTENTION MAXIMALE (task_port pri haute + stress à chaque INT6) : config dédiée au
; RED A/B des ports interrupt-safe (Forbid corrompt la liste du port / Disable non). Défaut 0 (arbre).
M7D_STRESS_MAX EQU 0
; message de stress : struct Message (MN_SIZE=20) + MAGIC + IN_HAND (détecteurs de corruption de liste)
MSG_MAGIC_OFF  EQU 20         ; sentinelle : un GetMsg corrompu (mauvais pointeur) la rate
MSG_INHAND_OFF EQU 24         ; 1 = message « en main » hors liste ; un GetMsg qui le rend = doublon = corruption
STRESS_MSG_SIZE EQU 28
STRESS_MAGIC  EQU $5D7C0DE5   ; valeur MAGIC attendue
; M7e — fidélité IPL-par-niveau : les handlers tournent à leur IPL NATIF (vbl=3, int2=2, int6=6)
; au lieu d'IPL7 uniforme. Preuve SÉLECTIVE : INT6 (niveau 6) préempte le CORPS de vbl (niveau 3)
; MAIS la chirurgie de listes du scheduler reste atomique (section critique du switch montée à IPL7).
VBL_INBODY       EQU $0000056E ; UBYTE : corps de vbl_handler en cours (fenêtre préemptible par INT6)
VBL_IPL          EQU $0000056F ; UBYTE : IPL lu par vbl via « move sr » (value-check : doit == 3, pas 7)
VBL_PREEMPT_COUNT EQU $00000570 ; long : INT6 a observé VBL_INBODY posé (préempté le corps) -> > 0 en GREEN
IDLE_ENTERED     EQU $00000574 ; long : épisodes d'idle du dispatcher (instrumentation ; > 0 dans un run normal)
M7E_STAT         EQU $00000578 ; UBYTE : b0 = marqueur « M7E IPL OK » déjà émis
; Gates A/B M7e (reproductibilité ; défaut 0 = GREEN en arbre, comme M7D_STRESS_MAX) :
; M7E_SURGERY_INTENA=1 (RED1) : la chirurgie du switch est masquée par INTENA-off AU LIEU d'IPL7 ->
;   l'écriture INTENA a un délai de propagation -> INT6 chevauche la fenêtre VBL_INSURG -> VBL_CLASH>0
;   (overlap, précondition de corruption ; « M7A FAILED »). Prouve que l'IPL7 est load-bearing.
; M7E_PROLOGUE_IPL7=1 (RED2) : le prologue vbl remonte IPL7 (modèle M7a, tout le handler IPL7) -> INT6
;   ne préempte plus le CORPS de vbl -> VBL_PREEMPT_COUNT==0 -> « M7E IPL OK » jamais émis. Prouve que
;   l'IPL natif (absence d'IPL7 au prologue) est load-bearing, pas cosmétique.
M7E_SURGERY_INTENA EQU 0
M7E_PROLOGUE_IPL7  EQU 0
; M7E_COOP=1 : non-régression COOPÉRATIVE (SCHED_ON=0, préemption OFF). Retire les 2 spinners purs
; (task_S, task_port) qui monopoliseraient sans préemption, et met SPIN_THRESH=0 -> « M3F LIVE » émis
; par le seul chemin YIELD (trap1->dispatch->switch). Prouve que la voie yield->dispatch tient sans
; préemption après M7e. Défaut 0 (build préemptif complet M3f/M7a/M7c/M7d/M7e).
M7E_COOP           EQU 0
; M7f — VERTB en chaîne de serveurs. structs Interrupt (IS_SIZE=22) en RAM BASSE RÉSERVÉE (< HEAP_LOWER
; $1000 -> hors pool AllocMem ; AddIntServer les Enqueue donc elles doivent être inscriptibles).
SCHED_INT      EQU $00000580 ; struct Interrupt du serveur scheduler (quantum round-robin), pri 20
TIMER_VBL_INT  EQU $00000596 ; struct Interrupt du serveur VBLANK timer.device, pri 0
VBL_TAIL_INT   EQU $000005AC ; struct Interrupt du serveur de preuve (queue de chaîne), pri -10
VERTB_CHAIN_N  EQU $000005C2 ; long : incréments du serveur de queue -> prouve que le walker parcourt
                             ; TOUTE la chaîne VERTB (donc >= 2 serveurs avant lui)
M7F_STAT       EQU $000005C6 ; UBYTE : b0 = marqueur « M7F VERTB OK » déjà émis
VERTB_CHAIN_THRESH EQU 50     ; parcours complets de chaîne requis pour « M7F VERTB OK »
; Gate A/B M7f (reproductibilité ; défaut 0 = GREEN) :
; M7F_SCHED_STOPS_CHAIN=1 (RED) : sched_server retourne Z-CLAIR (« géré, stop ») au lieu de Z-set ->
;   le walker ARRÊTE la chaîne après sched -> timer_vblank + serveur de queue jamais appelés ->
;   VERTB_CHAIN_N figé + unité VBLANK morte (M6A échoue tôt). Prouve la sémantique « call-all » (Z-set)
;   de la chaîne = la marche dispatche BIEN les serveurs suivants en séquence.
M7F_SCHED_STOPS_CHAIN EQU 0
; M7g — décodage INTREQR multi-source : preuve qu'int3 dispatche une 2e source de niveau 3 (COPER)
COPER_FIRED    EQU $000005C8 ; long : appels de coper_test (2e source niveau 3, servie via le décodage)
COPER_TICK     EQU $000005CC ; UBYTE : rate-limiteur du déclenchement logiciel de COPER (1 VBlank sur 4)
M7G_STAT       EQU $000005CD ; UBYTE : b0 = marqueur « M7G MULTISRC OK » déjà émis
COPER_THRESH   EQU 20        ; appels de coper_test requis pour « M7G MULTISRC OK »
; Gate A/B M7g (reproductibilité ; défaut 0 = GREEN) :
; M7G_MONO_SOURCE=1 (RED) : int3 décode ET acke COPER/BLIT mais NE les DISPATCHE PAS (comportement
;   mono-dispatch) -> COPER_FIRED figé, pas de storm (COPER reste ackée), tout le reste identique ->
;   « M7G MULTISRC OK » absent. Prouve que le DISPATCH par source décodée est load-bearing.
M7G_MONO_SOURCE EQU 0
; M7h — quantum réel : sched_server préempte après M7H_QUANTUM ticks (comme exec, défaut 4) au lieu de
; chaque tick. QUANTUM_ELAPSED = ticks depuis le dernier changement de tâche (reset par dispatch_in sur
; changement RÉEL). QUANTUM_EXPIRE_N = nombre d'expirations (preuve du débit). Observable SEULEMENT en
; isolation (M7H_QUANTUM_DEMO) : dans la démo par défaut INT6 dispatche ~140/s -> ELAPSED reset avant
; d'atteindre le quantum -> quasi-no-op (non-régression : M3F passe via la rotation INT6, découverte M7f).
QUANTUM_ELAPSED EQU $000005CE ; UBYTE : ticks VBlank du time-slice courant
QUANTUM_EXPIRE_N EQU $000005D0 ; long : expirations de quantum (débit : ~VBL_COUNT/QUANTUM en isolation)
Q2_RUNS        EQU $000005D4 ; long : itérations du 2e spinner d'isolation (prouve la rotation réelle)
M7H_STAT       EQU $000005D8 ; UBYTE : b0 = marqueur « M7H QUANTUM OK » déjà émis
; M7H_QUANTUM : longueur du time-slice en ticks VBlank. GREEN=4 (fidèle exec). RED=1 (préemption chaque
; tick = ancien comportement M7f) -> en isolation, rotation chaque tick -> QUANTUM_EXPIRE_N≈VBL_COUNT ->
; le discriminant (EXPIRE_N*2 < VBL_COUNT) échoue -> « M7H QUANTUM OK » absent.
M7H_QUANTUM     EQU 4
; M7H_QUANTUM_DEMO=1 : démo d'ISOLATION (2 spinners pri 0, PAS d'autres tâches) pour rendre le quantum
; observable (aucun préempteur prioritaire ; INT6 tourne mais ne Signale personne -> ne fait pas tourner).
M7H_QUANTUM_DEMO EQU 0

; --- Offsets struct Node / List / Library / ExecBase (exec-spec.md) ---
LN_SUCC      EQU 0
LN_PRED      EQU 4
LN_TYPE      EQU 8
LN_PRI       EQU 9           ; priorité (BYTE signé) — tri Enqueue
LN_NAME      EQU 10
LH_TAIL      EQU 4
NT_LIBRARY   EQU 9
LIB_NEGSIZE  EQU $10
LIB_POSSIZE  EQU $12
LIB_VERSION  EQU $14
LIB_REVISION EQU $16
LIB_IDSTRING EQU $18
LIB_OPENCNT  EQU $20
LIB_SIZE     EQU 34            ; sizeof(struct Library) (base mini pour MakeLibrary)
TIMER_VBLQ   EQU LIB_SIZE      ; timer.device : liste de requêtes de l'unité VBLANK (struct List)
TIMER_MICROQ EQU LIB_SIZE+14   ; M7a : liste de requêtes de l'unité MICROHZ (CIA-B/INT6) (struct List)
TD_SIZE      EQU LIB_SIZE+28   ; taille de la base timer.device (Library + 2 listes d'unité)
UNIT_MICROHZ EQU 0             ; sélecteur d'unité dans IO_UNIT (= numérotation réelle timer.device)
UNIT_VBLANK  EQU 1             ; (OpenDevice poserait un struct Unit* ; notre impl minimale = l'index)
EB_CHKBASE    EQU $26
EB_MAXLOCMEM  EQU $3E
EB_THISTASK   EQU $114         ; tâche courante (struct Task *)
EB_IDNEST     EQU $126
EB_TDNEST     EQU $127
EB_ATTNFLAGS  EQU $128
EB_ATTNRESCHED EQU $12A         ; UWORD : reschedule en attente (posé par Signal, consommé
                                ; par Permit/Enable au déverrouillage du nesting = yield)
EB_RESMODULES EQU $12C          ; APTR : tableau NUL-terminé de struct Resident* (pri-trié)
EB_MEMLIST      EQU $142
EB_RESOURCELIST EQU $150
EB_DEVICELIST   EQU $15E
EB_INTRLIST     EQU $16C
EB_LIBLIST      EQU $17A
EB_PORTLIST     EQU $188
EB_TASKREADY    EQU $196
EB_TASKWAIT     EQU $1A4
EB_VBLANKFREQ   EQU $212
EB_POWERFREQ    EQU $213
EB_SEMLIST      EQU $214
EB_INTVECTS     EQU $222        ; M7b : APTR -> bloc IntVects (16 vecteurs + 16 svlist), AllocMem'd
                                ; à init_ints. Tient dans la zone positive ($222+4 <= EXEC_POSSIZE $230).

; struct MemHeader / MemChunk + attributs mémoire (exec/memory.i, V34)
NT_MEMORY     EQU 10
MEMF_PUBLIC   EQU $1
MEMF_CHIP     EQU $2
MEMF_FAST     EQU $4
MEMF_TYPEMASK EQU $7           ; bits de TYPE mémoire en V34 (PUBLIC|CHIP|FAST)
MEMF_CLEAR    EQU $10000
MEMF_LARGEST  EQU $20000       ; AvailMem : plus grand bloc contigu (pas la somme)
MH_ATTRIBUTES EQU 14
MH_FIRST      EQU 16          ; -> struct MemChunk
MH_LOWER      EQU 20
MH_UPPER      EQU 24
MH_FREE       EQU 28
MH_SIZE       EQU 32          ; sizeof(struct MemHeader)
MC_NEXT       EQU 0
MC_BYTES      EQU 4

; struct Task (exec/tasks.i) — base à LN_SIZE=14
NT_TASK       EQU 1
TS_RUN        EQU 2           ; tâche en cours d'exécution
TS_READY      EQU 3
TS_WAIT       EQU 4           ; tâche bloquée (Wait/WaitPort) -> liste TaskWait
TC_FLAGS      EQU 14
TC_STATE      EQU 15
TC_IDNESTCNT  EQU 16
TC_TDNESTCNT  EQU 17
TC_SIGALLOC   EQU 18
TC_SIGWAIT    EQU 22
TC_SIGRECVD   EQU 26
TC_SIGEXCEPT  EQU 30
TC_SPREG      EQU 54
TC_SPLOWER    EQU 58
TC_SPUPPER    EQU 62
TC_SIZE       EQU 92
SYS_SIGALLOC  EQU $FFFF        ; signaux 0-15 pré-alloués (réservés système)

; struct MsgPort (exec/ports.i) — base à LN_SIZE=14
NT_MSGPORT    EQU 4
NT_MESSAGE    EQU 5
NT_REPLYMSG   EQU 7
MP_FLAGS      EQU 14
MP_SIGBIT     EQU 15
MP_SIGTASK    EQU 16
MP_MSGLIST    EQU 20          ; struct List
MP_SIZE       EQU 34
PF_ACTION     EQU 3           ; masque des bits d'action
PA_SIGNAL     EQU 0
PA_IGNORE     EQU 2
; struct Message (exec/ports.i)
MN_REPLYPORT  EQU 14
MN_LENGTH     EQU 18
MN_SIZE       EQU 20

; struct IORequest (exec/io.i) / timerequest (devices/timer.i)
IO_DEVICE    EQU 20          ; struct Device *
IO_UNIT      EQU 24          ; struct Unit *
IO_COMMAND   EQU 28          ; UWORD
IO_FLAGS     EQU 30          ; UBYTE
IO_ERROR     EQU 31          ; BYTE
IO_SIZE      EQU 32
TR_TIME      EQU 32          ; struct timeval (dans une timerequest)
TV_SECS      EQU 32
TV_MICRO     EQU 36
TR_SIZE      EQU 40
TR_ADDREQUEST EQU 9          ; commande timer.device (= CMD_NONSTD)
TD_BEGINIO   EQU -30         ; offset BeginIO dans la jump table d'un device

; struct Resident (exec/resident.i, V34) — ROMTag scanné au boot pour bâtir l'OS
RTC_MATCHWORD EQU $4AFC        ; RT_MATCHWORD : signature d'un ROMTag
RTF_AUTOINIT  EQU $80          ; RT_FLAGS bit 7 : RT_INIT -> table auto-init (MakeLibrary)
RTF_COLDSTART EQU $01
NT_DEVICE     EQU 3
NT_RESOURCE   EQU 8
RT_MATCHWORD  EQU 0            ; UWORD
RT_MATCHTAG   EQU 2            ; APTR -> self (valide le match vs un $4AFC fortuit)
RT_ENDSKIP    EQU 6            ; APTR -> reprise du scan (fin du module)
RT_FLAGS      EQU 10           ; UBYTE
RT_VERSION    EQU 11           ; UBYTE
RT_TYPE       EQU 12           ; UBYTE
RT_PRI        EQU 13           ; BYTE signé (ordre d'init décroissant)
RT_NAME       EQU 14           ; APTR
RT_IDSTRING   EQU 18           ; APTR
RT_INIT       EQU 22           ; APTR -> routine d'init (ou table si AUTOINIT)
RT_SIZE       EQU 26
RESSCAN_LO    EQU ROMBASE          ; plage de scan des ROMTags = toute la ROM
RESSCAN_HI    EQU ROMBASE+$40000   ; (256K ; le padding/footer ne contient pas de ROMTag valide)
RESMAX        EQU 16              ; capacité du tableau ResModules (résidents + terminateur NUL)

; LVO (offsets négatifs confirmés par docs/analysis/exec-spec.md + exec-lvo-table.md)
LVO_OPEN     EQU -6
LVO_CLOSE    EQU -12
LVO_EXPUNGE  EQU -18
LVO_INITCODE     EQU -72
LVO_INITSTRUCT   EQU -78
LVO_MAKELIBRARY  EQU -84
LVO_MAKEFUNCTIONS EQU -90
LVO_FINDRESIDENT EQU -96
LVO_INITRESIDENT EQU -102
LVO_DISABLE  EQU -120
LVO_ENABLE   EQU -126
LVO_FORBID   EQU -132
LVO_PERMIT   EQU -138
LVO_SETINTVECTOR EQU -162
LVO_ADDINTSERVER EQU -168
LVO_REMINTSERVER EQU -174
LVO_ALLOCMEM EQU -198
LVO_FREEMEM  EQU -210
LVO_AVAILMEM EQU -216
LVO_INSERT   EQU -234
LVO_ADDHEAD  EQU -240
LVO_ADDTAIL  EQU -246
LVO_REMOVE   EQU -252
LVO_REMHEAD  EQU -258
LVO_REMTAIL  EQU -264
LVO_ENQUEUE  EQU -270
LVO_FINDNAME EQU -276
LVO_ADDTASK    EQU -282
LVO_FINDTASK   EQU -294
LVO_SETTASKPRI EQU -300
LVO_SETSIGNAL  EQU -306
LVO_WAIT       EQU -318
LVO_SIGNAL     EQU -324
LVO_ALLOCSIGNAL EQU -330
LVO_FREESIGNAL EQU -336
LVO_ADDPORT    EQU -354
LVO_REMPORT    EQU -360
LVO_PUTMSG     EQU -366
LVO_GETMSG     EQU -372
LVO_REPLYMSG   EQU -378
LVO_WAITPORT   EQU -384
LVO_FINDPORT   EQU -390
LVO_TYPEOFMEM EQU -534
LVO_ADDRESOURCE  EQU -486
LVO_OPENRESOURCE EQU -498

; cia.resource (M5b) — fonctions a6-relatives (base resource), struct, matériel.
CIA_ADDICRVECTOR EQU -6
CIA_REMICRVECTOR EQU -12
CIA_ABLEICR      EQU -18
CIA_SETICR       EQU -24
CIAR_HWBASE      EQU LIB_SIZE        ; APTR base matérielle CIA (après le nœud Library)
CIAR_ICRMASK     EQU LIB_SIZE+4      ; UBYTE shadow du masque ICR activé (+pad)
CIAR_VECTORS     EQU LIB_SIZE+6      ; 5 APTR : slots struct Interrupt* (timerA/B/TOD/ser/flag)
CIAR_SIZE        EQU LIB_SIZE+6+20
CIAA_HW          EQU $BFE001         ; base CIA-A
CIAB_HW          EQU $BFD000         ; base CIA-B
CIA_ICR_OFF      EQU $D00            ; offset du registre ICR (registre $D) depuis la base CIA

                endc
