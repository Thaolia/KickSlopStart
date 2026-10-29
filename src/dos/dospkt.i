; src/dos/dospkt.i - Process / DOS packet / FileHandle constants (D3). V34 layout from docs/analysis/dos-v34-spec.md
; (analysis track, reviewed). IMPLEMENTATION track ("clean"): NO ROM reading. MP_*/MN_*/TC_*/LN_* are in exec.i.

; --- Process (V34: struct Task + dos fields, STOPS at pr_WindowPtr; pr_HomeDir+ = 2.0, NOT to be implemented) ---
PR_MSGPORT       EQU 92            ; 0x5C: embedded struct MsgPort (= TC_SIZE). CreateProc returns its APTR (not a BPTR)
PR_PAD           EQU 126           ; 0x7E: WORD
PR_SEGLIST       EQU 128           ; 0x80: BPTR
PR_STACKSIZE     EQU 132           ; 0x84: LONG
PR_GLOBVEC       EQU 136           ; 0x88: APTR (BCPL global vector; unused in C)
PR_TASKNUM       EQU 140           ; 0x8C: LONG (CLI number, 0 if not a CLI)
PR_STACKBASE     EQU 144           ; 0x90: BPTR
PR_RESULT2       EQU 148           ; 0x94: LONG (= IoErr)
PR_CURRENTDIR    EQU 152           ; 0x98: BPTR lock of the current directory
PR_CIS           EQU 156           ; 0x9C: BPTR CLI input FileHandle
PR_COS           EQU 160           ; 0xA0: BPTR CLI output FileHandle
PR_CONSOLETASK   EQU 164           ; 0xA4: APTR
PR_FILESYSTEMTASK EQU 168          ; 0xA8: APTR
PR_CLI           EQU 172           ; 0xAC: BPTR CommandLineInterface
PR_RETURNADDR    EQU 176           ; 0xB0: APTR
PR_PKTWAIT       EQU 180           ; 0xB4: APTR
PR_WINDOWPTR     EQU 184           ; 0xB8: APTR (last V34 field)
PR_SIZEOF        EQU 188           ; 0xBC: Process size in V34

NT_PROCESS       EQU 13            ; ln_Type of a Process (dosextens); the scheduler ignores ln_Type (demo = 0)
DOS_PORTSIG      EQU 8             ; SIGB_DOS: pr_MsgPort signal bit (reserved by SYS_SIGALLOC -> pre-allocated in main)

; --- DosPacket (48 bytes) ---
DP_LINK          EQU 0             ; APTR -> associated exec Message
DP_PORT          EQU 4             ; APTR -> reply port (refilled on every send)
DP_TYPE          EQU 8             ; LONG ACTION_* code
DP_RES1          EQU 12            ; LONG result (what the function would have returned)
DP_RES2          EQU 16            ; LONG error code (= IoErr)
DP_ARG1          EQU 20
DP_ARG2          EQU 24
DP_ARG3          EQU 28
DP_ARG4          EQU 32
DP_ARG5          EQU 36
DP_ARG6          EQU 40
DP_ARG7          EQU 44
DP_SIZEOF        EQU 48

; --- StandardPacket (68 bytes): sp_Msg (Message, 20 bytes) + sp_Pkt (DosPacket, 48 bytes) ---
SP_MSG           EQU 0             ; struct Message (MN_SIZE = 20)
SP_PKT           EQU 20            ; 0x14: struct DosPacket
SP_SIZEOF        EQU 68

; --- FileHandle (44 bytes): no fh_Port, fh_Type IS the port ---
FH_LINK          EQU 0
FH_INTERACTIVE   EQU 4
FH_TYPE          EQU 8             ; APTR = MsgPort of the handler
FH_BUF           EQU 12
FH_POS           EQU 16
FH_END           EQU 20
FH_FUNC1         EQU 24
FH_FUNC2         EQU 28
FH_FUNC3         EQU 32
FH_ARG1          EQU 36            ; LONG = private key of the file on the handler side
FH_ARG2          EQU 40
FH_SIZEOF        EQU 44
DOS_NAMEMAX      EQU 255           ; max length of a BSTR name (length byte)
FH_WBUF          EQU FH_SIZEOF+DOS_NAMEMAX+1 ; private (FileHandles opened by dos): deferred write buffer | 0
FH_WCNT          EQU FH_WBUF+4         ; private: bytes pending in that buffer
DOS_FH_ALLOC     EQU FH_WCNT+4         ; FileHandle + BSTR name buffer (at FH_SIZEOF) + private fields, in 1 AllocMem
RT_FHBUFLONGS    EQU 49            ; buffer of a BCPL runtime FileHandle: getvec(49) = 200 bytes (rdch; freed by Close)

; --- DeviceNode (44 bytes; chained in DosInfo.di_DevInfo) ---
DN_NEXT          EQU 0             ; BPTR
DN_TYPE          EQU 4
DN_TASK          EQU 8             ; APTR = MsgPort of the handler process (NULL -> start on 1st access)
DN_LOCK          EQU 12
DN_HANDLER       EQU 16            ; BSTR
DN_STACKSIZE     EQU 20
DN_PRIORITY      EQU 24
DN_STARTUP       EQU 28            ; BPTR FileSysStartupMsg
DN_SEGLIST       EQU 32            ; BPTR
DN_GLOBALVEC     EQU 36
DN_NAME          EQU 40            ; BSTR
DN_SIZEOF        EQU 44
FSSM_UNIT        EQU 0             ; struct FileSysStartupMsg (dosfilehandler.i)
FSSM_DEVICE      EQU 4             ; BSTR device name
FSSM_ENVIRON     EQU 8             ; BPTR DosEnvec
FSSM_FLAGS       EQU 12
FSSM_SIZEOF      EQU 16
; DosList node types (dn_Type / dol_Type): same layout for device, assign and volume (dol_Task @8,
; dol_Lock @12, dol_Name @40). An assign (DLT_DIRECTORY) carries a lock in dol_Lock; dol_Task = handler port.
DLT_DEVICE       EQU 0
DLT_DIRECTORY    EQU 1
DLT_VOLUME       EQU 2
DOL_VOLDATE      EQU 16            ; volume: creation DateStamp of the disk (3 longs)
DOL_LOCKLIST     EQU 28            ; volume: locks left while the disk is absent
DOL_DISKTYPE     EQU 32
DOL_USE          EQU 36            ; volume (dol_unused): locks and open files counted by our DF0: handler
DOL_NODESIZE     EQU DN_SIZEOF+32  ; node + BSTR of the name (31 characters) allocated together

; --- ACTION_* codes (= Open mode for the FIND*) ---
ACTION_FINDUPDATE  EQU 1004
ACTION_FINDINPUT   EQU 1005        ; = MODE_OLDFILE
ACTION_FINDOUTPUT  EQU 1006        ; = MODE_NEWFILE
ACTION_READ        EQU 82          ; 'R'
ACTION_WRITE       EQU 87          ; 'W'
ACTION_SEEK        EQU 1008
ACTION_END         EQU 1007
ACTION_LOCATE_OBJECT EQU 8          ; Lock: (ARG1 parent lock, ARG2 BSTR name, ARG3 mode) -> RES1 = BPTR lock
ACTION_FREE_LOCK   EQU 15          ; UnLock: (ARG1 BPTR lock) -> frees the lock
ACTION_EXAMINE_OBJECT EQU 23       ; Examine: (ARG1 BPTR lock, ARG2 BPTR fib) -> fills the FileInfoBlock
ACTION_EXAMINE_NEXT   EQU 24       ; ExNext: (ARG1 BPTR lock, ARG2 BPTR fib) -> next directory entry
ACTION_PARENT      EQU 29          ; ParentDir: (ARG1 BPTR lock) -> lock of the parent | 0
ACTION_DELETE_OBJECT EQU 16        ; DeleteFile: (ARG1 lock, ARG2 BSTR name) -> RES1 boolean
ACTION_RENAME_OBJECT EQU 17        ; Rename: (ARG1 lock, ARG2 BSTR name, ARG3 lock, ARG4 BSTR new name)
ACTION_CREATE_DIR  EQU 22          ; CreateDir: (ARG1 lock, ARG2 BSTR name) -> RES1 = BPTR lock
ACTION_COPY_DIR    EQU 19          ; DupLock: (ARG1 BPTR lock) -> new lock on the same object

MODE_OLDFILE     EQU 1005
MODE_NEWFILE     EQU 1006
MODE_READWRITE   EQU 1004

; access modes of a lock (dos.i)
SHARED_LOCK      EQU -2            ; shared lock (concurrent reading)
EXCLUSIVE_LOCK   EQU -1            ; exclusive lock (writing)

DOSTRUE          EQU -1
DOSFALSE         EQU 0

; dos.library LVOs (D3c subset) - vector N = -6*N
DOS_LVO_OPEN     EQU -30           ; Open(name d1, mode d2) -> BPTR FileHandle
DOS_LVO_CLOSE    EQU -36           ; Close(fh d1)
DOS_LVO_READ     EQU -42           ; Read(fh d1, buf d2, len d3) -> bytes
DOS_LVO_WRITE    EQU -48           ; Write(fh d1, buf d2, len d3) -> bytes written | -1
DOS_LVO_INPUT    EQU -54           ; Input() -> BPTR input FileHandle (pr_CIS)
DOS_LVO_OUTPUT   EQU -60           ; Output() -> BPTR output FileHandle (pr_COS)
DOS_LVO_SEEK     EQU -66           ; Seek(fh d1, position d2, mode d3) -> old position | -1
DOS_LVO_CURRENTDIR EQU -126        ; CurrentDir(lock d1) -> old pr_CurrentDir
DOS_LVO_LOADSEG  EQU -150          ; LoadSeg(name d1) -> BPTR seglist | 0 (open+read+parse hunks+reloc via Open/Read)
DOS_LVO_DELAY    EQU -198          ; Delay(ticks d1)
DOS_LVO_UNLOADSEG EQU -156         ; UnLoadSeg(seglist d1) -> frees the segment chain
DOS_LVO_IOERR    EQU -132          ; IoErr() -> d0 = pr_Result2 (error code of the last packet)
DOS_LVO_DELETEFILE EQU -72         ; DeleteFile(name d1) -> boolean
DOS_LVO_CREATEDIR EQU -120         ; CreateDir(name d1) -> BPTR lock | 0
DOS_LVO_DATESTAMP EQU -192         ; DateStamp(ds d1 APTR) -> ds
DOS_LVO_RENAME   EQU -78           ; Rename(old d1, new d2) -> boolean
DOS_LVO_LOCK     EQU -84           ; Lock(name d1, mode d2) -> BPTR lock | 0
DOS_LVO_UNLOCK   EQU -90           ; UnLock(lock d1) -> frees
DOS_LVO_EXAMINE  EQU -102          ; Examine(lock d1, fib d2) -> DOSTRUE/DOSFALSE
DOS_LVO_EXNEXT   EQU -108          ; ExNext(lock d1, fib d2) -> DOSTRUE/DOSFALSE (DOSFALSE + IoErr=232 -> end)

; Seek: modes (dos.i) + error codes (dos.i) used by the handler/IoErr
OFFSET_BEGINNING EQU -1            ; Seek from the beginning
OFFSET_CURRENT   EQU 0             ; Seek relative to the current position
OFFSET_END       EQU 1             ; Seek from the end
ERROR_OBJECT_NOT_FOUND EQU 205     ; dos/dos.i: file/object not found (Open of a missing name)
ERROR_FILE_NOT_OBJECT EQU 121      ; dos/dos.i: file not loadable (LoadSeg)
ERROR_NO_FREE_STORE EQU 103       ; dos/dos.i: not enough memory
; LoadSeg reader (loadseg.s ls_load_stream): buffer refilled by Read, or fixed buffer if LR_FH = 0
LR_BUF           EQU 0              ; buffer
LR_POS           EQU 4              ; next byte to read in the buffer
LR_LEN           EQU 8              ; valid bytes in the buffer
LR_FH            EQU 12             ; BPTR FileHandle | 0
LR_DOS           EQU 16             ; DOSBase (Read)
LR_CAP           EQU 20             ; buffer size
LR_EOF           EQU 24             ; WORD: end of data reached
LR_SIZE          EQU 26
LS_BUFSZ         EQU 2048           ; LoadSeg read buffer
ERROR_ACTION_NOT_KNOWN EQU 209     ; dos/dos.i: action/function not supported
ERROR_DEVICE_NOT_MOUNTED EQU 218   ; dos/dos.i: "xxx:" prefix unknown to the DosList
ERROR_RENAME_ACROSS_DEVICES EQU 215
ERROR_SEEK_ERROR EQU 303           ; dos/dos.i: Seek out of bounds
ERROR_NO_MORE_ENTRIES EQU 232      ; dos/dos.i: ExNext has exhausted the directory (normal end of enumeration)
ERROR_OBJECT_IN_USE EQU 202
ERROR_OBJECT_EXISTS EQU 203
ERROR_INVALID_COMPONENT_NAME EQU 210
ERROR_OBJECT_WRONG_TYPE EQU 212
ERROR_DISK_NOT_VALIDATED EQU 213
ERROR_DISK_WRITE_PROTECTED EQU 214
ERROR_DIRECTORY_NOT_EMPTY EQU 216
ERROR_DISK_FULL EQU 221
ERROR_NO_DISK   EQU 226           ; no floppy in the drive
ERROR_NOT_A_DOS_DISK EQU 225
ACTION_SET_PROTECT EQU 21          ; (ARG1 -, ARG2 lock, ARG3 BSTR name, ARG4 mask)
ACTION_SET_COMMENT EQU 28          ; (ARG1 -, ARG2 lock, ARG3 BSTR name, ARG4 BSTR comment)
ACTION_DISK_INFO EQU 25            ; (ARG1 BPTR InfoData)
ACTION_INFO      EQU 26            ; (ARG1 lock, ARG2 BPTR InfoData)

; --- FileLock (dos.i): V34 public prefix + PRIVATE enumeration cursor ---
; ACCEPTED clean-room deviation: real AmigaDOS keeps the ExNext cursor in the FIB (fib_DiskKey); we keep it
; in the lock (flp_Bucket/flp_ChainBlk). Consequence: Examine of a lock into one FIB then ExNext via ANOTHER FIB
; would desynchronise a caller that mixes FIBs. Sufficient for our harness (one lock = one enumeration).
; --- struct CommandLineInterface (dos/dosextens.i, public): pointed to as a BPTR by pr_CLI. The startup code of
; commands tests pr_CLI: 0 = launched by the Workbench (waits for the WBStartup message on pr_MsgPort); otherwise reads
; cli_CommandName (name of the current command) and the streams.
CLI_RESULT2         EQU 0          ; LONG
CLI_SETNAME         EQU 4          ; BSTR: name of the current directory
CLI_COMMANDDIR      EQU 8          ; BPTR: list of search paths
CLI_RETURNCODE      EQU 12         ; LONG: return code of the last command
CLI_COMMANDNAME     EQU 16         ; BSTR: name of the current command
CLI_FAILLEVEL       EQU 20         ; LONG
CLI_PROMPT          EQU 24         ; BSTR
CLI_STANDARDINPUT   EQU 28         ; BPTR FileHandle
CLI_CURRENTINPUT    EQU 32         ; BPTR FileHandle
CLI_COMMANDFILE     EQU 36         ; BSTR
CLI_INTERACTIVE     EQU 40         ; LONG boolean
CLI_BACKGROUND      EQU 44         ; LONG boolean
CLI_CURRENTOUTPUT   EQU 48         ; BPTR FileHandle
CLI_DEFAULTSTACK    EQU 52         ; LONG: default stack IN LONGS
CLI_STANDARDOUTPUT  EQU 56         ; BPTR FileHandle
CLI_MODULE          EQU 60         ; BPTR: seglist of the current command
CLI_SIZEOF          EQU 64
FL_LINK          EQU 0             ; BPTR: next lock (we keep 0: no chaining)
FL_KEY           EQU 4             ; LONG: header block of the locked object
FL_ACCESS        EQU 8             ; LONG : SHARED_LOCK / EXCLUSIVE_LOCK
FL_TASK          EQU 12            ; APTR: MsgPort of the handler (source of the port for UnLock/Examine/ExNext)
FL_VOLUME        EQU 16            ; BPTR: volume node (DosBase DL_VOLUME)
FLP_BUCKET       EQU 20            ; private LONG: current bucket index in the directory hashtable
FLP_CHAIN        EQU 24            ; private LONG: current block in the hash chain (0 = move on to the next bucket)
FL_SIZEOF        EQU 28

; --- FileInfoBlock (dos.i): minimally filled (DiskKey/DirEntryType/FileName/Size) ---
FIB_DISKKEY      EQU 0             ; LONG: disk key (= header block of the entry)
FIB_DIRENTRYTYPE EQU 4            ; LONG: <0 file (ST_FILE=-3), >0 directory (ST_ROOT=1/ST_USERDIR=2)
FIB_FILENAME     EQU 8             ; char[108]: BSTR on the packet side; C string after Examine/ExNext (dos converts)
FIB_PROTECTION   EQU 116           ; LONG: protection bits (RWED inverted + p, s, a)
FIB_ENTRYTYPE    EQU 120           ; LONG (= DirEntryType)
FIB_SIZE         EQU 124           ; LONG: file size in bytes (0 for a directory)
FIB_NUMBLOCKS    EQU 128           ; LONG: number of data blocks
FIB_DATE         EQU 132           ; DateStamp (3 LONGs: days, minutes, ticks)
FIB_COMMENT      EQU 144           ; char[80]: BSTR on the packet side; C string after Examine/ExNext
FIB_SIZEOF       EQU 260

; DOS_NO_IOERR=1 (RED): dos_sendpkt does NOT copy dp_Res2 -> pr_Result2 -> IoErr returns 0 even after a failed
; Open -> "DOS IOERR SEEK OK" missing. Isolates the IoErr wiring (dp_Res2 of the packet -> pr_Result2). Default 0.
DOS_NO_IOERR     EQU 0
; HND_NO_SEEK=1 (RED): the DF0: file handler does NOT serve ACTION_SEEK (HS_POS unchanged) -> after Seek(0,BEGINNING)
; the 2nd read restarts from the current position instead of the beginning -> different bytes -> "DOS IOERR SEEK OK"
; missing. Isolates the repositioning. Default 0.
HND_NO_SEEK      EQU 0
; DOS_NO_WRITE=1 (RED): dos_fn_write does NOT SEND the ACTION_WRITE packet -> con_handler emits nothing -> the marker
; "DOS WRITE OK" (emitted BY the Write via the console) is missing. Isolates the Write -> handler routing. Default 0.
DOS_NO_WRITE     EQU 0

; LOADSEG_LVO_UNWIRED=1 (RED LoadSeg): the LoadSeg vector (-150) points to dos_null instead of dos_fn_loadseg
; -> jsr -150(a6) returns 0 -> the d3e client gets no seglist -> "D3E LOADSEG LVO OK" + the run of the
; loaded program missing. d3d_client (inline load Open/Read/ls_load_hunks) stays GREEN -> isolates the wiring of the
; LoadSeg LVO vector (proves LoadSeg is really reachable via -150, not only via the internal machinery). Default 0.
LOADSEG_LVO_UNWIRED EQU 0

; D3A_NO_REPLY=1 (RED D3a): the echo handler does NOT ReplyMsg -> the driver stays blocked on WaitPort ->
; "D3A ... OK" never emitted. Isolates the packet round-trip (the PutMsg->serve->ReplyMsg->WaitPort path). Default 0.
D3A_NO_REPLY     EQU 0

; D3B_NO_READ=1 (RED D3b): the DF0: file handler does NOT serve ACTION_READ (returns EOF=0) -> the driver reads 0 bytes
; -> markers missing -> "D3B ... OK" missing (FINDINPUT/END still work). Isolates the READ service. Default 0.
D3B_NO_READ      EQU 0

; D3C_NO_FHTYPE=1 (RED D3c): dos Open does NOT set fh_Type (the handler port) in the FileHandle -> dos Read
; sees fh_Type=0 and does not route the packet (returns 0) -> contents not read -> "D3C ... OK" missing. Isolates the
; wiring of the Open->Read route (fh_Type). No crash (Read safeguard fh_Type==0). Default 0.
D3C_NO_FHTYPE    EQU 0

; D3D_NO_RUN=1 (RED D3d): the client loads the command via dos (Open/Read -> ls_load_hunks) but does NOT EXECUTE it
; (skips the JSR to the seglist) -> the command does not emit its marker -> "D3D ... OK" missing. Isolates execution of
; the command loaded by dos (loading/reloc remains proven by D2). Default 0.
D3D_NO_RUN       EQU 0

; E1_NO_WRITE=1 (RED E1): the console handler does NOT serve ACTION_WRITE (returns the count but EMITS NOTHING on
; serial) -> "E1 CON WRITE OK" missing (the client still opens/closes, the packet round-trip works). Isolates the
; WRITE service of the console handler (packet dispatch -> serial output via the handler). Default 0.
E1_NO_WRITE      EQU 0

; E2_NO_DISPATCH=1 (RED E2): the shell reads the line but does NOT DISPATCH the builtins (everything -> unknown "?") ->
; "E2 SHELL ver OK" missing on "ver", "echo X" not echoed back. Isolates parse/dispatch (the banner + read-echo
; still work). Default 0.
E2_NO_DISPATCH   EQU 0

; E3_NO_EXEC=1 (RED E3): an unknown typed command is indeed FOUND + LOADED from DF0: via dos (ls_load_hunks)
; but NOT EXECUTED (skips the JSR to the seglist) -> the command's marker missing (no "?" either: it is
; found). Isolates execution of the typed command (loading/reloc remains proven by D2/D3d). Default 0.
E3_NO_EXEC       EQU 0

; F1_NO_STARTUP=1 (RED F1): the Initial CLI does NOT read/execute the startup-sequence (goes straight to the
; interactive prompt) -> script markers ("F1BOOTOK", e3cmd) missing, but the interactive shell still works. Isolates
; execution of the startup-sequence at boot (the boot-gated creation of the Initial CLI does remain). Default 0.
F1_NO_STARTUP    EQU 0
