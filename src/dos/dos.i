; src/dos/dos.i - dos.library V34 layout + M6 constants (skeleton + BPTR + DateStamp).
; IMPLEMENTATION track ("clean"): NDK dos/dosextens.i + dos.i, lvo/dos_lib.i, FD/dos_lib.fd (public). NO ROM reading.
; LIB_SIZE / MEMF_* / LVO_ALLOCMEM are defined in exec.i (included BEFORE this file).

; --- DosLibrary: Library node + dos fields (dosextens.i) ---
; dl_Root is a direct APTR (NOT a BPTR); the BPTR convention applies to rn_Info (RootNode -> DosInfo).
DL_ROOT          EQU LIB_SIZE          ; 34: APTR -> RootNode
DL_GV            EQU DL_ROOT+4         ; 38: APTR BCPL global vector (deferred)
DL_A2            EQU DL_GV+4           ; 42: BCPL standard registers (deferred)
DL_A5            EQU DL_A2+4           ; 46
DL_A6            EQU DL_A5+4           ; 50
DL_ERRORS        EQU DL_A6+4           ; 54: APTR error message table (private, deferred)
DL_TIMEREQ       EQU DL_ERRORS+4       ; 58: APTR timer request (deferred -> DateStamp reads an unset clock = 0,0,0)
DL_UTILITYBASE   EQU DL_TIMEREQ+4      ; 62: APTR utility.library (deferred)
DL_INTUITIONBASE EQU DL_UTILITYBASE+4  ; 66: APTR intuition.library (deferred)
DL_SIZEOF        EQU DL_INTUITIONBASE+4 ; 70: end of the public DosLibrary struct
; Skeleton scaffold (outside the public struct): raw APTR to DosInfo. Lets the M6D proof check the BPTR encoding
; of rn_Info by compute-then-compare (rn_Info<<2 == &DosInfo) WITHOUT dereferencing a possibly badly encoded
; pointer (RED anti-bus-error safeguard). Removed when the real DOS makes &DosInfo reachable by traversal.
DL_DISHADOW      EQU DL_SIZEOF         ; 70
DL_VOLUME        EQU DL_DISHADOW+4     ; 74: BPTR: volume node of the floppy mounted in DF0: (set by its handler) | 0
DL_BOOTDEV       EQU DL_VOLUME+4       ; 78: APTR DeviceNode of the boot device (head of eb_MountList; 0: DF0)
DOSBASE_DATASIZE EQU DL_BOOTDEV+4      ; 82: dataSize for MakeLibrary (Library base + dos fields + scaffold)

; --- RootNode (dosextens.i): only rn_Info is wired up in this milestone ---
; offset 0 rn_TaskArray(BPTR), 4 rn_ConsoleSegment(BPTR), 8 rn_Time(DateStamp,12), 20 rn_RestartSeg(LONG)
RN_TASKARRAY     EQU 0                 ; BPTR -> [size, taskid CLI 1, taskid CLI 2, ...] (CLI slots: Run, EndCLI)
RN_CONSOLESEG    EQU 4                 ; BPTR: Run's default CLI segment if no "CLI" resident exists (ROM CLI, shell.s)
RN_TASKSLOTS     EQU 20                ; number of simultaneous CLIs (array size)
RN_TIME          EQU 8                 ; DateStamp: cache of the time, updated by every DateStamp
RN_INFO          EQU 24                ; BPTR -> DosInfo (Info structure)
RN_SIZEOF        EQU 56                ; complete struct RootNode (rn_CliList/rn_Flags... set to 0)

; --- DosInfo (dosextens.i): minimal block (pointer fields) ---
; offset 0 di_McName(BPTR), 4 di_DevInfo(BPTR, empty device list), 8 di_Devices, 12 di_Handlers, 16 di_NetHand
DI_RESLIST       EQU 16                ; BPTR -> resident segments (!0 next, !1 use count, !2 seglist, BSTR at +12)
RS_USAGE         EQU 4                 ; Resident node: !1 use count (-1 = system)
RS_SEGLIST       EQU 8                 ; !2 seglist (BPTR)
RS_NAME          EQU 12                ; BSTR of the name
RS_SIZEOF        EQU 16                ; node of the ROM "CLI" (3-letter name)
DI_DEVINFO       EQU 4                 ; BPTR -> device list (empty: no handler mounted in this milestone)
DOSINFO_SIZE     EQU 20               ; skeleton: pointer fields only; 3 SignalSemaphore locks deferred

; --- DateStamp (dos.i) ---
DS_SIZEOF        EQU 12                ; ds_Days(LONG) + ds_Minute(LONG) + ds_Tick(LONG)

; --- LVO dos.library (lvo/dos_lib.i, autoritatif) ---
LVO_DATESTAMP    EQU -192              ; DateStamp(date d1) -> d0 = date (vector 32)

; M6: dos.library as a resident module (skeleton + BPTR convention + DateStamp). M6D_BAD_BPTR=1 (RED): initfunc
; stores rn_Info as a raw APTR instead of &DosInfo>>2 -> the "rn_Info<<2 == &DosInfo" round-trip fails (address
; mismatch, no crash) -> "M6D DOS LIB OK" missing. Isolates the new primitive: the BPTR encoding (dos's signature
; quirk). NT_LIBRARY->LibList routing is already RED-proven (M4C1_WRONG_TYPE); DateStamp is load-bearing in GREEN.
M6D_BAD_BPTR     EQU 0
