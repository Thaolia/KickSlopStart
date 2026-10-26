; src/dos/dos.i — layout dos.library V34 + constantes M6 (squelette + BPTR + DateStamp).
; Piste IMPLÉMENTATION (« clean ») : NDK dos/dosextens.i + dos.i, lvo/dos_lib.i, FD/dos_lib.fd (public). AUCUNE lecture ROM.
; LIB_SIZE / MEMF_* / LVO_ALLOCMEM sont définis dans exec.i (inclus AVANT ce fichier).

; --- DosLibrary : nœud Library + champs dos (dosextens.i) ---
; dl_Root est un APTR direct (PAS un BPTR) ; la convention BPTR s'applique à rn_Info (RootNode -> DosInfo).
DL_ROOT          EQU LIB_SIZE          ; 34 : APTR -> RootNode
DL_GV            EQU DL_ROOT+4         ; 38 : APTR BCPL global vector (différé)
DL_A2            EQU DL_GV+4           ; 42 : registres standard BCPL (différés)
DL_A5            EQU DL_A2+4           ; 46
DL_A6            EQU DL_A5+4           ; 50
DL_ERRORS        EQU DL_A6+4           ; 54 : APTR table de messages d'erreur (privé, différé)
DL_TIMEREQ       EQU DL_ERRORS+4       ; 58 : APTR timer request (différé -> DateStamp lit une horloge non réglée = 0,0,0)
DL_UTILITYBASE   EQU DL_TIMEREQ+4      ; 62 : APTR utility.library (différé)
DL_INTUITIONBASE EQU DL_UTILITYBASE+4  ; 66 : APTR intuition.library (différé)
DL_SIZEOF        EQU DL_INTUITIONBASE+4 ; 70 : fin de la struct DosLibrary publique
; Scaffold squelette (hors struct publique) : APTR brut vers DosInfo. Permet à la preuve M6D de vérifier l'encodage
; BPTR de rn_Info par compute-then-compare (rn_Info<<2 == &DosInfo) SANS déréférencer un pointeur potentiellement
; mal encodé (garde-fou RED anti-bus-error). Retiré quand le vrai DOS rendra &DosInfo atteignable par traversée.
DL_DISHADOW      EQU DL_SIZEOF         ; 70
DL_VOLUME        EQU DL_DISHADOW+4     ; 74 : BPTR du nœud volume du disque de boot (fl_Volume des locks DF0:)
DL_BOOTDEV       EQU DL_VOLUME+4       ; 78 : APTR DeviceNode du périphérique de démarrage (tête de eb_MountList ; 0 : DF0)
DOSBASE_DATASIZE EQU DL_BOOTDEV+4      ; 82 : dataSize pour MakeLibrary (base Library + champs dos + scaffold)

; --- RootNode (dosextens.i) : seul rn_Info est câblé ce milestone ---
; offset 0 rn_TaskArray(BPTR) · 4 rn_ConsoleSegment(BPTR) · 8 rn_Time(DateStamp,12) · 20 rn_RestartSeg(LONG)
RN_TASKARRAY     EQU 0                 ; BPTR -> [taille, taskid CLI 1, taskid CLI 2, ...] (slots des CLI : Run, EndCLI)
RN_CONSOLESEG    EQU 4                 ; BPTR : segment CLI par défaut de Run quand aucun résident « CLI » (CLI ROM, shell.s)
RN_TASKSLOTS     EQU 20                ; nombre de CLI simultanés (taille du tableau)
RN_TIME          EQU 8                 ; DateStamp : cache de l'heure, mis à jour par chaque DateStamp
RN_INFO          EQU 24                ; BPTR -> DosInfo (Info structure)
RN_SIZEOF        EQU 56                ; struct RootNode complète (rn_CliList/rn_Flags... mis à 0)

; --- DosInfo (dosextens.i) : bloc minimal (champs pointeurs) ---
; offset 0 di_McName(BPTR) · 4 di_DevInfo(BPTR, device list vide) · 8 di_Devices · 12 di_Handlers · 16 di_NetHand
DI_RESLIST       EQU 16                ; BPTR -> segments résidents (!0 suivant, !1 usage, !2 seglist, BSTR à +12)
RS_USAGE         EQU 4                 ; nœud Resident : !1 compteur d'usage (-1 = système)
RS_SEGLIST       EQU 8                 ; !2 seglist (BPTR)
RS_NAME          EQU 12                ; BSTR du nom
RS_SIZEOF        EQU 16                ; nœud du « CLI » de la ROM (nom de 3 lettres)
DI_DEVINFO       EQU 4                 ; BPTR -> device list (vide : aucun handler monté ce milestone)
DOSINFO_SIZE     EQU 20               ; squelette : champs pointeurs seulement ; 3 verrous SignalSemaphore différés

; --- DateStamp (dos.i) ---
DS_SIZEOF        EQU 12                ; ds_Days(LONG) + ds_Minute(LONG) + ds_Tick(LONG)

; --- LVO dos.library (lvo/dos_lib.i, autoritatif) ---
LVO_DATESTAMP    EQU -192              ; DateStamp(date d1) -> d0 = date (vecteur 32)

; M6 : dos.library comme module résident (squelette + convention BPTR + DateStamp). M6D_BAD_BPTR=1 (RED) : initfunc
; stocke rn_Info comme APTR brut au lieu de &DosInfo>>2 -> le round-trip « rn_Info<<2 == &DosInfo » échoue (mismatch
; d'adresse, pas de crash) -> « M6D DOS LIB OK » absent. Isole la primitive neuve : l'encodage BPTR (quirk signature
; de dos). Le routage NT_LIBRARY->LibList est déjà RED-prouvé (M4C1_WRONG_TYPE) ; DateStamp est load-bearing en GREEN.
M6D_BAD_BPTR     EQU 0
