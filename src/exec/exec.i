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
POTINP   EQU CUSTOM+$016      ; POTGOR : bit 10 (DATLY) = bouton droit du port 0, actif-bas
JOY0DAT  EQU CUSTOM+$00A      ; compteurs quadrature souris port 0 (octet bas = X, octet haut = Y ; 8 bits wrap)

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
INTF_RBF     EQU $0800        ; E1 : bit 11 = RBF (serial receive buffer full) ; acquitter -> efface SERDATR bit 14
AUTOVEC_L1   EQU $64          ; autovecteur niveau 1 (TBE / DSKBLK / SOFTINT)
AUTOVEC_L4   EQU $70          ; autovecteur niveau 4 (AUD0..AUD3)
AUTOVEC_L5   EQU $74          ; autovecteur niveau 5 (RBF / DSKSYNC)
INTM_L1      EQU $0007        ; sources du niveau 1
INTM_L4      EQU $0780        ; sources du niveau 4
INTM_L5      EQU $1800        ; sources du niveau 5
AUTOVEC_L2   EQU $68          ; autovecteur 68000 niveau 2 (INT2 / CIA-A / PORTS)
AUTOVEC_L3   EQU $6C          ; vecteur d'exception 68000, interruption niveau 3
AUTOVEC_L6   EQU $78          ; autovecteur 68000 niveau 6 (INT6 / CIA-B / EXTER)
TRAP0_VEC    EQU $80          ; M7c : vecteur TRAP #0 (switch volontaire style Wait : sortante déjà rangée)
TRAP1_VEC    EQU $84          ; M7c : vecteur TRAP #1 (yield/reschedule : requeue sortante -> TaskReady)
TRAP2_VEC    EQU $88          ; M7j : vecteur TRAP #2 (RemTask-self : libère + bascule définitivement)
TRAP3_VEC    EQU $8C          ; vecteur TRAP #3 (exec_Supervisor : exécute a5 en mode superviseur)
LVO_SUPERVISOR EQU -30        ; exec Supervisor() : appelle une routine (a5) en mode superviseur (requis par flt-intro)
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
; PROD=1 : ROM de PRODUCTION — sort le HARNAIS DE DÉVELOPPEMENT du chemin de boot. Gaté : tâches démo M7
; (task_h/l/s/timer/port/fa/fb), clients de test D3 (echo d3a, d3c_client, d3d..d3j), port de stress M7d,
; instrumentation de preuve (serveur de queue VERTB vbl_tail, source COPER de test). GARDÉ : init exec +
; scan résident -> TOUS les vrais modules (cia/timer/gfx/intuition/dos/trackdisk...), timer CIA-B/MICROHZ,
; gameport live, montage DF0: (handler OFS + driver + DeviceNode), con_handler, feeder, strap (boot floppy
; OU écran insert-disk), Initial CLI. Les marqueurs série de diagnostic restent (POST ; émis par le chemin
; RÉEL, pas par le harnais). Défaut 0 = ROM dev prouvée, byte-identique. SURCHARGÉ par -DPROD=1 (make
; kick-prod) -> aucune édition de source pour produire la variante prod. Le `ifnd` protège le défaut.
        ifnd    PROD
PROD               EQU 0
        endif
; LOADSCREEN_DEMO=1 (-DLOADSCREEN_DEMO=1) : après l'init, affiche un ÉCRAN DE CHARGEMENT (src/graphics/
; loadscreen.s) — monte une View sur le bitplane texte de la console, écrit « Chargement bigseg... » + une
; barre de progression pendant la lecture STREAMING de « bigseg », puis « OK ». NE REVIENT PAS (tient l'écran).
; Démo autonome du feedback visuel de chargement. Défaut 0 (boot normal).
        ifnd    LOADSCREEN_DEMO
LOADSCREEN_DEMO    EQU 0
        endif
; F2A_NO_HANDSHAKE=1 (RED F2a) : kbd_selftest NE fait PAS le handshake clavier (pulse CRA bit 6) -> le clavier
; émulé stalle après le 1er octet -> $FE (terminate power-up) jamais reçu -> « F2 KBD OK » absent. Isole le
; handshake (load-bearing : sans ack, le flux clavier ne progresse pas). Défaut 0.
F2A_NO_HANDSHAKE   EQU 0
; F2B_NO_FEED=1 (RED F2b) : kbd_interrupt décode+handshake mais NE pousse PAS l'ASCII dans le ring clavier ->
; une commande tapée au clavier n'atteint jamais le shell -> « E2 SHELL ver OK » absent après injection. Isole
; le câblage clavier->console (load-bearing). La réception/décodage (F2a « F2 KBD OK ») reste intacte. Défaut 0.
F2B_NO_FEED        EQU 0
; INPUT_NO_PROPAGATE=1 (RED #2) : IND_WRITEEVENT ne parcourt PAS la chaîne de handlers -> l'event injecté
; n'atteint aucun handler -> « INPUT OK » absent (ADDHANDLER a pourtant réussi). Isole la propagation. Défaut 0.
INPUT_NO_PROPAGATE EQU 0
; CON_NO_BLIT=1 (RED #3a) : CMD_WRITE avance le curseur mais NE blitte PAS le glyphe -> le bitplane reste à 0 ->
; le readback des cellules non-espace ne correspond pas aux glyphes -> « CONSOLE WRITE OK » absent. Isole le blitter. Défaut 0.
CON_NO_BLIT        EQU 0
; CON_NO_READBUF=1 (RED #3b) : console_input_handler cuit le RAWKEY mais NE le pousse PAS dans le read buffer ->
; CMD_READ ne rend rien -> « CONSOLE READ=v » absent. Isole le câblage input.device->console READ. Défaut 0.
CON_NO_READBUF     EQU 0
; DV_CORRUPT=1 (RED #4) : le disk-validator corrompt le bloc bitmap après lecture (flip d'un octet) -> son checksum
; OFS (somme des longs == 0) échoue -> dv_validate rejette -> « DISK VALID OK » absent. Isole la vérif d'intégrité. Défaut 0.
DV_CORRUPT         EQU 0
; KEYMAP_AZERTY=1 : la keymap.resource installe par défaut la keymap FR AZERTY (sinon US QWERTY). Produit la
; variante AZERTY de la ROM (kbd_cook cuit selon AZERTY). Défaut 0 (US). Build : make kick après avoir mis à 1.
KEYMAP_AZERTY      EQU 0
; KM_NO_SHIFT=1 (RED #5) : kbd_cook ignore le qualifieur SHIFT (toujours la table non-shiftée) -> l'assertion
; q+SHIFT=='Q' du test échoue -> « KEYMAP OK » absent. Isole la gestion des qualifieurs. Défaut 0.
KM_NO_SHIFT        EQU 0
; FEEDER_NO_WRITEEVENT=1 (RED feeder) : le feeder draine le ring mais N'APPELLE PAS IND_WRITEEVENT -> input.device
; ne reçoit rien -> console.device ne reçoit rien -> « FEEDER OK » absent. Isole le feeder -> input.device. Défaut 0.
FEEDER_NO_WRITEEVENT EQU 0
; SHELL_ON_SCREEN=1 : le shell (Initial CLI) est branché sur le handler console backé par console.device (écran +
; miroir série + clavier via le feeder) au lieu du con_handler série. Défaut 0 (shell sur série ; = contrôle/RED du swap).
SHELL_ON_SCREEN    EQU 0
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
; M7j — RemTask (cycle de vie) : preuve qu'une tâche qui se termine libère sa pile + TCB (AvailMem remonte)
RM_RUNS          EQU $000005DC ; long : itérations de task_rm avant qu'elle ne RTS (-> task_exit -> RemTask self)
M7J_AVAIL_BEFORE EQU $000005E0 ; long : AvailMem capturé AVANT la création de task_rm (baseline)
M7J_STAT         EQU $000005E4 ; UBYTE : b0 = marqueur « M7J REMTASK OK » déjà émis
RM_THRESH        EQU 20        ; itérations de task_rm avant auto-retrait
M7J_RECOVER      EQU 1024      ; AvailMem doit remonter d'au moins ça (pile 2048 + TCB) pour prouver le free
; M7J_DEMO=1 : ajoute task_rm (tâche qui tourne RM_THRESH fois puis RTS -> RemTask self) et la preuve
; AvailMem dans une tâche survivante. Défaut 0 (RemTask compilé mais non exercé -> non-régression).
M7J_DEMO         EQU 0
; M7J_NOFREE=1 (RED) : RemTask marque/retire mais SAUTE les FreeMem -> AvailMem ne remonte pas (fuite) ->
; « M7J REMTASK OK » absent. Prouve que le FreeMem pile+TCB est load-bearing.
M7J_NOFREE       EQU 0

; M7l — calibration µs réelle MICROHZ. L'unité MICROHZ est cadencée par l'underflow du timer A de CIA-B
; (latch $00FF = 255 ticks E-clock). Horloge E PAL = 709379 Hz (= horloge CPU 7,09379 MHz / 10), donc
; 255 / 709379 ≈ 359,5 µs par interruption, soit ≈ 2782 interruptions/s. timer_beginio convertit désormais
; TV_MICRO en interruptions CIA-B via ces constantes (au lieu du facteur VBLANK /20000 qui faisait d'une
; requête « 400000 µs » ~7 ms au lieu de 400 ms). Résolution = 1 interruption ≈ 360 µs (la bande de preuve
; absorbe ~±10 %) ; la résolution sub-interruption (lecture live du latch E) reste différée (« ECLOCK »).
; Hypothèse PAL, cohérente avec /20000=50 Hz et M7A_MINTICKS=250=5 s.
US_PER_INT     EQU 359        ; µs réelles par interruption CIA-B (255 ticks E / 709379 Hz)
INTS_PER_SEC   EQU 2782       ; interruptions CIA-B par seconde (709379 / 255)
; Preuve = inter-horloges : une requête MICROHZ LONGUE connue, mesurée contre l'horloge VBLANK (50 Hz,
; indépendante : raster display vs E-clock CPU). 0,5 s doit s'écouler en ~25 ticks VBLANK. NON tautologique
; (les deux horloges dérivent de matériels différents) : valide la constante E à ~±10 %.
M7L_CAL_US     EQU 500000     ; durée de la requête de calibration (µs) = 0,5 s
M7L_LO         EQU 22         ; bande basse (ticks VBLANK) ; 0,5 s = 25 ticks ; RED OLD_CONV -> ~0-1
M7L_HI         EQU 28         ; bande haute ; la latence d'ordonnancement ne fait qu'INFLATER (jamais < 25)
M7L_VBL_BEFORE EQU $000005E8  ; long : VBL_COUNT au départ de la requête de calibration (T0)
M7L_ELAPSED    EQU $000005EC  ; long : ticks VBLANK écoulés pendant la calibration (mesure)
M7L_STAT       EQU $000005F0  ; UBYTE : b0 = marqueur « M7L MICROHZ CALIB OK » déjà émis
GFX_COPLIST_PTR EQU $000005F4 ; M4a : long — adresse chip de la copper list (publiée par gfx_display_init)
DOS_HANDLERPORT EQU $000005F8 ; D3a : long — APTR du pr_MsgPort du process handler echo (publié par le setup)
DOS_FSPORT      EQU $000005FC ; D3b : long — APTR du pr_MsgPort du process file-handler DF0: (OFS)
TD_CURCYL       EQU $00000600 ; trackdisk : word — cylindre courant de la tête (valide ssi TD_CYLVALID != 0)
TD_CYLVALID     EQU $00000602 ; trackdisk : byte — 0 = position inconnue (recalibrer) ; !=0 = TD_CURCYL fiable
DOS_CONPORT     EQU $00000604 ; E1 : long — APTR du pr_MsgPort du process handler console-série (publié par le setup)
CON_STATE       EQU $00000608 ; E1 : long — APTR du bloc d'état du handler console (timer.device + reply port + requête)
; F2b : ring clavier SPSC (producteur = kbd_interrupt/INT2 ; consommateur = con_handler READ). Lock-free :
; le producteur écrit la donnée puis avance KBD_TAIL ; le consommateur lit puis avance KBD_HEAD. Pas de masquage.
KBD_RING        EQU $0000060C ; F2b : 64 octets — tampon circulaire d'ASCII décodé du clavier
KBD_RSIZE       EQU 64        ; taille du ring (puissance de 2)
KBD_RMASK       EQU 63        ; masque d'index (KBD_RSIZE-1)
KBD_HEAD        EQU $0000064C ; F2b : word — index de LECTURE (consommateur : con_handler)
KBD_TAIL        EQU $0000064E ; F2b : word — index d'ÉCRITURE (producteur : kbd_interrupt)

; --- input.device + InputEvent (#2) — ABI publique (devices/input.i, devices/inputevent.i) ---
IND_ADDHANDLER  EQU 9            ; io_Command : ajoute un handler (struct Interrupt) à la chaîne
IND_REMHANDLER  EQU 10           ; io_Command : retire un handler de la chaîne
IND_WRITEEVENT  EQU 11           ; io_Command : injecte une liste d'InputEvents dans la chaîne de handlers
IECLASS_RAWKEY  EQU 1            ; ie_Class : touche brute (keycode + up/down)
IECLASS_RAWMOUSE EQU 2           ; ie_Class : souris brute (bouton + position)
IECODE_LBUTTON  EQU $68          ; ie_Code : bouton gauche (down ; up = | $80)
IECODE_RBUTTON  EQU $69          ; ie_Code : bouton droit (down ; up = | $80)
IECODE_NOBUTTON EQU $FF          ; ie_Code : event de mouvement pur (aucun bouton)
IECODE_UP_PREFIX EQU $80         ; ie_Code : relâchement (code bouton | $80)
IE_NEXTEVENT    EQU 0            ; struct InputEvent : APTR event suivant
IE_CLASS        EQU 4            ; UBYTE classe
IE_SUBCLASS     EQU 5            ; UBYTE sous-classe
IE_CODE         EQU 6            ; UWORD code (keycode pour RAWKEY ; bouton pour RAWMOUSE)
IE_QUALIFIER    EQU 8            ; UWORD qualifieurs
IE_X            EQU 10           ; WORD ie_position.ie_xy.ie_x (position souris ; absolue dans notre injection)
IE_Y            EQU 12           ; WORD ie_position.ie_xy.ie_y
IE_SIZEOF       EQU 22           ; sizeof(struct InputEvent)
; proof globals input.device (#2), RAM basse réservée (positionnés par les handlers de test de boot.s)
INPUT_SEQ       EQU $00000650 ; word : compteur d'ordre d'appel des handlers (parcours de chaîne)
INPUT_H1_ORD    EQU $00000652 ; word : ordre où le handler pri-haute a tourné (doit = 1)
INPUT_H2_ORD    EQU $00000654 ; word : ordre où le handler pri-basse a tourné (doit = 2)
INPUT_CODE      EQU $00000656 ; word : ie_Code vu par les handlers (doit = keycode synthétique injecté)

; --- keymap.resource + cook (#5) : keycode(+qualifiers) -> ASCII, keymaps US/AZERTY ---
KBD_QUAL     EQU $00000658 ; word : état des qualifieurs suivi par kbd_interrupt (LSHIFT$01 RSHIFT$02 CAPS$04 CTRL$08)
KM_RESBASE   EQU $0000065A ; long : base keymap.resource (publiée à l'init ; lue par kbd_cook)
KMR_LO       EQU LIB_SIZE      ; base keymap.resource : APTR table non-shiftée (km_xx_lo)
KMR_HI       EQU LIB_SIZE+4    ; APTR table shiftée (km_xx_hi)
KMR_SIZE     EQU LIB_SIZE+8
KQ_SHIFT     EQU $03           ; masque ie_Qualifier : LSHIFT | RSHIFT
KQB_CAPS     EQU 2             ; bit CAPSLOCK dans ie_Qualifier ($04)
KQB_CTRL     EQU 3             ; bit CONTROL dans ie_Qualifier ($08)
; feeder clavier -> input.device (intégration F, item 1) : ring BRUT alimenté par kbd_interrupt (raw tap au même
; point que le push cuit, après filtre qualifieurs), drainé par le process feeder -> IND_WRITEEVENT(RAWKEY).
KBD_FHEAD    EQU $0000065E ; word : tête (consommateur = feeder)
KBD_FTAIL    EQU $00000660 ; word : queue (producteur = kbd_interrupt) ; indices = OFFSETS OCTET (pas de 2)
KBD_FEEDRING EQU $00000662 ; 32 octets : 16 entrées word = (KBD_QUAL<<8 | keycode) snapshotées par frappe
KBD_FRMASK   EQU $1E       ; masque d'offset octet (taille 32 - 2)
REQ_HIT      EQU $00000682 ; word : requester — gadget touché par un clic (posé par req_input_handler, preuve)

; --- gameport.device (souris matérielle) + accumulateur de pointeur Intuition (câblage M6R live) ---
; gameport lit JOY0DAT (deltas quadrature) + CIAA_PRA bit 6 (bouton gauche, actif-bas) chaque VBlank, calcule
; les deltas signés (wraparound 8 bits), détecte les fronts de bouton, et injecte des InputEvents RAWMOUSE dans
; input.device via IND_WRITEEVENT (pattern du feeder clavier ; pas d'input.task — déviation documentée). Le
; pointer_input_handler (intuition, pri 50) accumule ces deltas RELATIFS en position ABSOLUE clampée à l'écran et
; réécrit ie_X/ie_Y -> le req_input_handler (pri 0) existant hit-teste en absolu, inchangé = le câblage live.
PTR_XMAX     EQU 320            ; bornes écran pour le clamp du pointeur (320x256 : console/bootscreen)
PTR_YMAX     EQU 256
GP_POLLS_THRESH EQU 25          ; polls VBlank (~0,5 s) avant « GP VBLANK LIVE OK » (serveur vit dans le système)
PTR_X        EQU $00000684 ; word : pointeur absolu X (accumulé par pointer_input_handler, clampé)
PTR_Y        EQU $00000686 ; word : pointeur absolu Y
INT_IBASE    EQU $00000740 ; long : IntuitionBase (posé à son init) — le handler de pointeur y déplace le sprite
KBD_DEVBASE  EQU $00000744 ; long : base keyboard.device (posée à son init) — kbd_interrupt lui remet chaque keycode
GP_PREV_JOY  EQU $00000688 ; word : JOY0DAT précédent (base du delta ; primé à gp_install = JOY0DAT courant, PAS 0)
GP_PREV_BTN  EQU $0000068A ; byte : bouton gauche précédent (edge-detect ; 0=relâché 1=pressé)
GP_PREV_RBTN EQU $0000068B ; byte : bouton droit précédent (idem)
GP_POLLS     EQU $0000068C ; long : compteur de polls de gp_vblank_server (preuve live : avance sur VBlanks réels)
GP_INPUTBASE EQU $00000690 ; long : base input.device pour l'injection RAWMOUSE (0 = pas d'injection)
GP_CAP_N     EQU $00000694 ; word : events RAWMOUSE vus par le handler de capture (tests gameport)
GP_CAP_CODE  EQU $00000696 ; word : dernier ie_Code capturé
GP_CAP_DX    EQU $00000698 ; word : dernier ie_X (delta) capturé
GP_CAP_DY    EQU $0000069A ; word : dernier ie_Y (delta) capturé
GP_LIVE_STAT EQU $0000069C ; byte : b0 = « GP VBLANK LIVE OK » déjà émis +pad $69D
GP_VBL_INT   EQU $000006A0 ; struct Interrupt (IS_SIZE=22) du serveur gameport VBlank -> $6A0..$6B5
; Handlers CONSOMMATEURS du requester, enregistrés PERSISTANTS sur input.device dans la branche M6R insert-disk
; (pas de teardown) -> la chaîne gameport->input.device->pointeur->requester est VIVANTE dans le système tournant
; (symétrique du serveur producteur gp_vblank_server). structs Interrupt en RAM basse réservée.
PTR_INT      EQU $000006B6 ; struct Interrupt (22) de pointer_input_handler (pri 50) -> $6B6..$6CB
REQ_INT      EQU $000006CC ; struct Interrupt (22) de req_input_handler (pri 0) -> $6CC..$6E1
FORBID_TEST_FLAG EQU $000006E2 ; long : preuve d'atomicité Forbid — task_fb le pose à 1 quand elle tourne
FB_TASK      EQU $000006E6 ; long : TCB de task_fb (pour que task_fa la signale)
SH_STK       EQU 8192       ; pile du CLI initial (shell.s) : les commandes lancées tournent dessus
TD_CACHEBUF  EQU $000006EA ; trackdisk : long — cache de pistes décodées (TD_CNSLOTS x 5632 o ; 0 = pas encore alloué)
TD_CNSLOTS   EQU $000006EE ; trackdisk : word — nombre d'emplacements du cache (TD_NCACHE, ou 1 si mémoire juste)
TD_MOTORON   EQU $00000700 ; trackdisk : byte — moteur DF0 allumé (latché) : pas de spin-up à la prochaine lecture
TD_BUSY      EQU $00000701 ; trackdisk : byte — accès au lecteur en cours (le serveur VBlank ne coupe pas le moteur)
TD_MOTORCNT  EQU $00000702 ; trackdisk : word — ticks VBlank avant extinction du moteur inactif
TD_VBLINT    EQU $00000704 ; trackdisk : struct Interrupt (22 o) du serveur VBlank d'extinction du moteur
TD_MOTORIDLE EQU 100       ; 2 s d'inactivité (50 Hz) avant extinction, comme le délai du trackdisk d'origine
TD_CTICK     EQU $0000071A ; trackdisk : word — horloge LRU du cache de pistes
TD_CTRK      EQU $00000720 ; trackdisk : TD_NCACHE words — piste de chaque emplacement ($FFFF = vide)
TD_CAGE      EQU $00000730 ; trackdisk : TD_NCACHE words — dernier accès (TD_CTICK) de chaque emplacement
TD_NCACHE    EQU 8         ; pistes gardées en cache (8 x 5632 = 44 Ko ; 16 : gain marginal mesuré, 87 s -> 83 s)
DOS_DOSBASE  EQU $000006F0 ; long : DosBase (posé par dos initFunc) — le runtime BCPL n'a pas a6 = DosBase
; GP_NO_WRAP=1 (RED) : gp_delta8 soustrait en MOT les compteurs 0..255 (sans sign-extend octet) -> au passage
; $FF/$00 le delta est faux ($FE->$01 donne -253 au lieu de +3) -> « GAMEPORT OK » absent (le vecteur de wrap du
; test gp_poll échoue). Isole le modèle de wraparound 8 bits des compteurs quadrature (load-bearing). Défaut 0.
GP_NO_WRAP   EQU 0

; SCHED_NO_FORBID_GATE=1 (RED atomicité Forbid) : retire la garde EB_TDNEST/EB_IDNEST d'intr_isr_defer -> un
; dispatch différé (AttnResched) se produit MÊME sous Forbid -> une tâche émettrice sous Forbid est préemptée en
; plein ser_puts -> « FORBID ATOMIC OK » absent (task_fb préempte task_fa pendant son Forbid et pose le flag).
; M3F LIVE reste présent (la fenêtre Forbid de task_l est courte + son yield-sur-Permit veut justement task_h).
; Isole la garde Forbid au point de consommation de la préemption. Défaut 0.
SCHED_NO_FORBID_GATE EQU 0
; GP_NO_EDGE=1 (RED) : gp_poll émet un event bouton à CHAQUE poll où le bouton est pressé (pas de front) -> un
; bouton TENU produit N events au lieu d'1 -> le compteur du test edge (2 attendus) passe à 3 -> « GAMEPORT OK »
; absent. Isole l'edge-detection (load-bearing : sans elle, flood d'events down). Défaut 0.
GP_NO_EDGE   EQU 0
; PTR_NO_CLAMP=1 (RED) : pointer_input_handler n'écrête PAS la position aux bornes écran -> un mouvement qui
; dépasse un bord sort de l'écran (négatif) -> la position accumulée est fausse -> le hit-test du gadget rate ->
; « M6R LIVE OK » absent. Isole le clamp (load-bearing). Défaut 0.
PTR_NO_CLAMP EQU 0

; --- Taille max d'un fichier bufferisé (handler HS_BUF + LoadSeg) : cap-bump 16K -> 32K (PAS du streaming) ---
; Le cap de LECTURE est le buffer whole-file du handler (HND_FILEMAX) + celui de LoadSeg (LS_LOADMAX). On le relève
; à 32 Ko (handles un exécutable jusqu'à 32 Ko, était 16 Ko) ; 2 buffers concurrents = 64 Ko transitoire (sûr sur le
; tas A500 ~500 Ko). La lecture incrémentale OFS réelle (streaming, pas de buffer whole-file) reste une DETTE différée.
; LOADSEG_CAP16K=1 (RED) : re-plafonne à 16 Ko -> un exécutable > 16 Ko (bigseg) tronque à FINDINPUT -> ne charge/tourne
; pas -> « LOADSEG BIG OK » absent (D3E/d3dtest, petit, reste OK). Isole le cap-bump (prouve qu'il est load-bearing). Défaut 0.
LOADSEG_CAP16K EQU 0
                ifne    LOADSEG_CAP16K
DOS_FILEMAX  EQU 16384
                endc
                ifeq    LOADSEG_CAP16K
DOS_FILEMAX  EQU 32768
                endc

; --- console.device (#3a) : rendu texte via blitter de glyphes 8x8 dans un bitplane (1 plan) ---
CON_COLS     EQU 40            ; colonnes de caractères (320 px / 8)
CON_BYTEW    EQU 40            ; octets par ligne du bitplane (= CON_COLS, 1 octet = 8 px = 1 glyphe de large)
CON_PXH      EQU 256           ; hauteur du bitplane en pixels (32 lignes de texte)
CON_BMSIZE   EQU CON_BYTEW*CON_PXH ; 10240 octets : taille du bitplane (chip RAM)
; base console.device = Library + état texte
CONB_BITMAP  EQU LIB_SIZE      ; APTR bitplane
CONB_BWIDTH  EQU LIB_SIZE+4    ; UWORD octets/ligne (stride)
CONB_PXROWS  EQU LIB_SIZE+6    ; UWORD hauteur px
CONB_CURX    EQU LIB_SIZE+8    ; UWORD colonne char courante (0..CON_COLS-1)
CONB_CURY    EQU LIB_SIZE+10   ; UWORD ligne pixel courante (0,8,16,... multiple de 8)
; #3b : buffer de lecture (clavier via input.device) + struct Interrupt du handler enregistré sur input.device
CONB_RHEAD   EQU LIB_SIZE+12   ; UWORD index de lecture du read buffer (consommateur = CMD_READ)
CONB_RTAIL   EQU LIB_SIZE+14   ; UWORD index d'écriture (producteur = console_input_handler)
CONB_RBUF    EQU LIB_SIZE+16   ; 16 octets : ring ASCII cuit depuis les RAWKEY reçus via input.device
CONB_INT     EQU LIB_SIZE+32   ; struct Interrupt (IS_SIZE=22) du handler enregistré via IND_ADDHANDLER
CONB_ESC     EQU LIB_SIZE+56   ; UBYTE état du filtre de séquences : 0 normal, 1 après ESC, 2 dans un CSI
CONB_RQ      EQU LIB_SIZE+60   ; APTR file des CMD_READ en attente (chaînée par LN_SUCC), unités ouvertes
CONB_GFXBASE EQU LIB_SIZE+64   ; APTR GfxBase : rendu dans le RastPort des fenêtres (unités ConUnit)
CONB_UNITS   EQU LIB_SIZE+68   ; APTR liste des ConUnit ouvertes (chaînées par CU_NEXT) : routage des touches
CONB_IBASE   EQU LIB_SIZE+72   ; APTR IntuitionBase (cherchée au premier besoin : intuition s'initialise après)
CONDEV_SIZE  EQU LIB_SIZE+76
CON_RBSIZE   EQU 16            ; taille du read buffer (puissance de 2)
CON_RBMASK   EQU 15
; M7L_OLD_CONV=1 (RED) : restaure l'ancienne conversion VBLANK (/20000) sur l'unité MICROHZ -> la requête
; de 0,5 s expire en ~25 interruptions ≈ 9 ms < 1 tick VBLANK -> hors bande -> « M7L » NON émis. La valeur
; de requête de la boucle task_timer est gatée en parallèle (TT_MICRO_REQ) pour que la PÉRIODE reste ~7 ms
; sous les deux conversions -> RED chirurgical : seul M7L tombe, M3F..M7G restent verts.
M7L_OLD_CONV   EQU 0

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
TIMER_SYSSECS EQU LIB_SIZE+28  ; heure système : secondes à la référence (TR_SETSYSTIME)
TIMER_SYSVBL EQU LIB_SIZE+32   ; VBL_COUNT à la référence
TD_SIZE      EQU LIB_SIZE+36   ; taille de la base timer.device (Library + 2 listes d'unité + heure système)
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
EB_TASKTRAPCODE EQU $130        ; APTR : gestionnaire de traps par défaut des tâches
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
NT_INTERRUPT  EQU 2
TS_RUN        EQU 2           ; tâche en cours d'exécution
TS_READY      EQU 3
TS_WAIT       EQU 4           ; tâche bloquée (Wait/WaitPort) -> liste TaskWait
TS_REMOVED    EQU 5           ; M7j : tâche en cours de retrait (RemTask)
TC_FLAGS      EQU 14
TC_STATE      EQU 15
TC_IDNESTCNT  EQU 16
TC_TDNESTCNT  EQU 17
TC_SIGALLOC   EQU 18
TC_SIGWAIT    EQU 22
TC_SIGRECVD   EQU 26
TC_SIGEXCEPT  EQU 30
TC_TRAPDATA   EQU 46          ; APTR : donnée libre du gestionnaire de traps de la tâche
TC_TRAPCODE   EQU 50          ; APTR : gestionnaire des exceptions CPU de la tâche (0 -> TaskTrapCode)
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
IOSTD_ACTUAL EQU 32          ; struct IOStdReq
IOSTD_LENGTH EQU 36
IOSTD_DATA   EQU 40
IOSTD_OFFSET EQU 44
TR_TIME      EQU 32          ; struct timeval (dans une timerequest)
TV_SECS      EQU 32
TV_MICRO     EQU 36
TR_SIZE      EQU 40
TR_ADDREQUEST EQU 9          ; commande timer.device (= CMD_NONSTD)
TR_GETSYSTIME EQU 10
TR_SETSYSTIME EQU 11
IOERR_NOCMD  EQU -3
IOERR_ABORTED EQU -2
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
RESMAX        EQU 32              ; capacité du tableau ResModules (résidents + terminateur NUL)

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
LVO_REMTASK    EQU -288         ; M7j
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
LVO_OPENWINDOW   EQU -204         ; intuition.library
LVO_CLOSEWINDOW  EQU -72
LVO_ADDLIBRARY   EQU -396
LVO_REMLIBRARY   EQU -402
LVO_ADDDEVICE    EQU -432
LVO_REMDEVICE    EQU -438
LVO_OPENDEVICE   EQU -444
LVO_CLOSEDEVICE  EQU -450
LVO_DOIO         EQU -456
LVO_SENDIO       EQU -462
LVO_CHECKIO      EQU -468
LVO_WAITIO       EQU -474
LVO_ABORTIO      EQU -480
LVO_COPYMEM      EQU -624
LVO_COPYMEMQUICK EQU -630
LVO_ADDRESOURCE  EQU -486
LVO_OPENRESOURCE EQU -498
LVO_OLDOPENLIBRARY EQU -408      ; OpenLibrary pré-V33 (sans gate de version)
LVO_CLOSELIBRARY   EQU -414
LVO_RAWDOFMT       EQU -522     ; RawDoFmt(fmt a0, data a1, putch a2, putchdata a3)
LVO_INITSEMAPHORE    EQU -558
LVO_OBTAINSEMAPHORE  EQU -564
LVO_RELEASESEMAPHORE EQU -570
LVO_ATTEMPTSEMAPHORE EQU -576
LVO_FINDSEMAPHORE    EQU -594
LVO_ADDSEMAPHORE     EQU -600
LVO_REMSEMAPHORE     EQU -606
LVO_OPENLIBRARY    EQU -552      ; OpenLibrary(libName a1, version d0)

; OPENLIB_NO_VERCHECK=1 (RED OpenLibrary) : exec_OpenLibrary saute la gate de version -> une ouverture
; en version trop haute réussit À TORT au lieu de renvoyer 0. Isole la branche de comparaison de version.
; Défaut 0 (arbre).
OPENLIB_NO_VERCHECK EQU 0

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
