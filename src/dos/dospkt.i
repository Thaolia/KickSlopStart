; src/dos/dospkt.i — constantes Process / DOS packet / FileHandle (D3). Layout V34 de docs/analysis/dos-v34-spec.md
; (piste analyse, relue). Piste IMPLÉMENTATION (« clean ») : AUCUNE lecture ROM. MP_*/MN_*/TC_*/LN_* sont dans exec.i.

; --- Process (V34 : struct Task + champs dos, S'ARRÊTE à pr_WindowPtr ; pr_HomeDir+ = 2.0, à NE PAS implémenter) ---
PR_MSGPORT       EQU 92            ; 0x5C : struct MsgPort embarqué (= TC_SIZE). CreateProc renvoie son APTR (pas BPTR)
PR_PAD           EQU 126           ; 0x7E : WORD
PR_SEGLIST       EQU 128           ; 0x80 : BPTR
PR_STACKSIZE     EQU 132           ; 0x84 : LONG
PR_GLOBVEC       EQU 136           ; 0x88 : APTR (vecteur global BCPL ; non utilisé en C)
PR_TASKNUM       EQU 140           ; 0x8C : LONG (n° CLI, 0 si pas CLI)
PR_STACKBASE     EQU 144           ; 0x90 : BPTR
PR_RESULT2       EQU 148           ; 0x94 : LONG (= IoErr)
PR_CURRENTDIR    EQU 152           ; 0x98 : BPTR lock du répertoire courant
PR_CIS           EQU 156           ; 0x9C : BPTR FileHandle entrée CLI
PR_COS           EQU 160           ; 0xA0 : BPTR FileHandle sortie CLI
PR_CONSOLETASK   EQU 164           ; 0xA4 : APTR
PR_FILESYSTEMTASK EQU 168          ; 0xA8 : APTR
PR_CLI           EQU 172           ; 0xAC : BPTR CommandLineInterface
PR_RETURNADDR    EQU 176           ; 0xB0 : APTR
PR_PKTWAIT       EQU 180           ; 0xB4 : APTR
PR_WINDOWPTR     EQU 184           ; 0xB8 : APTR (dernier champ V34)
PR_SIZEOF        EQU 188           ; 0xBC : taille Process en V34

NT_PROCESS       EQU 13            ; ln_Type d'un Process (dosextens) ; le scheduler ignore ln_Type (démo = 0)
DOS_PORTSIG      EQU 8             ; SIGB_DOS : bit de signal du pr_MsgPort (réservé par SYS_SIGALLOC -> pré-alloué main)

; --- DosPacket (48 o) ---
DP_LINK          EQU 0             ; APTR -> Message exec associé
DP_PORT          EQU 4             ; APTR -> port de réponse (re-rempli à chaque envoi)
DP_TYPE          EQU 8             ; LONG code ACTION_*
DP_RES1          EQU 12            ; LONG résultat (ce que la fonction aurait renvoyé)
DP_RES2          EQU 16            ; LONG code d'erreur (= IoErr)
DP_ARG1          EQU 20
DP_ARG2          EQU 24
DP_ARG3          EQU 28
DP_ARG4          EQU 32
DP_ARG5          EQU 36
DP_ARG6          EQU 40
DP_ARG7          EQU 44
DP_SIZEOF        EQU 48

; --- StandardPacket (68 o) : sp_Msg (Message, 20 o) + sp_Pkt (DosPacket, 48 o) ---
SP_MSG           EQU 0             ; struct Message (MN_SIZE = 20)
SP_PKT           EQU 20            ; 0x14 : struct DosPacket
SP_SIZEOF        EQU 68

; --- FileHandle (44 o) : pas de fh_Port, fh_Type EST le port ---
FH_LINK          EQU 0
FH_INTERACTIVE   EQU 4
FH_TYPE          EQU 8             ; APTR = MsgPort du handler
FH_BUF           EQU 12
FH_POS           EQU 16
FH_END           EQU 20
FH_FUNC1         EQU 24
FH_FUNC2         EQU 28
FH_FUNC3         EQU 32
FH_ARG1          EQU 36            ; LONG = clé privée du fichier côté handler
FH_ARG2          EQU 40
FH_SIZEOF        EQU 44
DOS_NAMEMAX      EQU 255           ; longueur max d'un nom BSTR (octet de longueur)
FH_WBUF          EQU FH_SIZEOF+DOS_NAMEMAX+1 ; privé (FileHandles ouverts par dos) : tampon d'écriture différée | 0
FH_WCNT          EQU FH_WBUF+4         ; privé : octets en attente dans ce tampon
DOS_FH_ALLOC     EQU FH_WCNT+4         ; FileHandle + buffer BSTR du nom (à FH_SIZEOF) + champs privés, en 1 AllocMem
RT_FHBUFLONGS    EQU 49            ; tampon d'un FileHandle du runtime BCPL : getvec(49) = 200 octets (rdch ; libéré par Close)

; --- DeviceNode (44 o ; chaîné dans DosInfo.di_DevInfo) ---
DN_NEXT          EQU 0             ; BPTR
DN_TYPE          EQU 4
DN_TASK          EQU 8             ; APTR = MsgPort du process handler (NULL -> démarrer au 1er accès)
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
FSSM_DEVICE      EQU 4             ; BSTR nom du device
FSSM_ENVIRON     EQU 8             ; BPTR DosEnvec
FSSM_FLAGS       EQU 12
FSSM_SIZEOF      EQU 16
; types de nœud de la DosList (dn_Type / dol_Type) : même layout pour device, assign et volume (dol_Task @8,
; dol_Lock @12, dol_Name @40). Un assign (DLT_DIRECTORY) porte un lock dans dol_Lock ; dol_Task = port du handler.
DLT_DEVICE       EQU 0
DLT_DIRECTORY    EQU 1
DLT_VOLUME       EQU 2

; --- codes ACTION_* (= mode d'Open pour les FIND*) ---
ACTION_FINDUPDATE  EQU 1004
ACTION_FINDINPUT   EQU 1005        ; = MODE_OLDFILE
ACTION_FINDOUTPUT  EQU 1006        ; = MODE_NEWFILE
ACTION_READ        EQU 82          ; 'R'
ACTION_WRITE       EQU 87          ; 'W'
ACTION_SEEK        EQU 1008
ACTION_END         EQU 1007
ACTION_LOCATE_OBJECT EQU 8          ; Lock : (ARG1 parent lock, ARG2 BSTR nom, ARG3 mode) -> RES1 = BPTR lock
ACTION_FREE_LOCK   EQU 15          ; UnLock : (ARG1 BPTR lock) -> libère le lock
ACTION_EXAMINE_OBJECT EQU 23       ; Examine : (ARG1 BPTR lock, ARG2 BPTR fib) -> remplit le FileInfoBlock
ACTION_EXAMINE_NEXT   EQU 24       ; ExNext : (ARG1 BPTR lock, ARG2 BPTR fib) -> entrée suivante du répertoire
ACTION_PARENT      EQU 29          ; ParentDir : (ARG1 BPTR lock) -> lock du parent | 0
ACTION_DELETE_OBJECT EQU 16        ; DeleteFile : (ARG1 lock, ARG2 BSTR nom) -> RES1 booléen
ACTION_RENAME_OBJECT EQU 17        ; Rename : (ARG1 lock, ARG2 BSTR nom, ARG3 lock, ARG4 BSTR nouveau nom)
ACTION_CREATE_DIR  EQU 22          ; CreateDir : (ARG1 lock, ARG2 BSTR nom) -> RES1 = BPTR lock
ACTION_COPY_DIR    EQU 19          ; DupLock : (ARG1 BPTR lock) -> nouveau lock sur le même objet

MODE_OLDFILE     EQU 1005
MODE_NEWFILE     EQU 1006
MODE_READWRITE   EQU 1004

; modes d'accès d'un lock (dos.i)
SHARED_LOCK      EQU -2            ; lock partagé (lecture concurrente)
EXCLUSIVE_LOCK   EQU -1            ; lock exclusif (écriture)

DOSTRUE          EQU -1
DOSFALSE         EQU 0

; LVO dos.library (sous-ensemble D3c) — vecteur N = -6*N
DOS_LVO_OPEN     EQU -30           ; Open(name d1, mode d2) -> BPTR FileHandle
DOS_LVO_CLOSE    EQU -36           ; Close(fh d1)
DOS_LVO_READ     EQU -42           ; Read(fh d1, buf d2, len d3) -> octets
DOS_LVO_WRITE    EQU -48           ; Write(fh d1, buf d2, len d3) -> octets écrits | -1
DOS_LVO_INPUT    EQU -54           ; Input() -> BPTR FileHandle d'entrée (pr_CIS)
DOS_LVO_OUTPUT   EQU -60           ; Output() -> BPTR FileHandle de sortie (pr_COS)
DOS_LVO_SEEK     EQU -66           ; Seek(fh d1, position d2, mode d3) -> ancienne position | -1
DOS_LVO_CURRENTDIR EQU -126        ; CurrentDir(lock d1) -> ancien pr_CurrentDir
DOS_LVO_LOADSEG  EQU -150          ; LoadSeg(name d1) -> BPTR seglist | 0 (ouvre+lit+parse hunk+reloc via Open/Read)
DOS_LVO_DELAY    EQU -198          ; Delay(ticks d1)
DOS_LVO_UNLOADSEG EQU -156         ; UnLoadSeg(seglist d1) -> libère la chaîne de segments
DOS_LVO_IOERR    EQU -132          ; IoErr() -> d0 = pr_Result2 (code d'erreur du dernier packet)
DOS_LVO_DELETEFILE EQU -72         ; DeleteFile(name d1) -> booléen
DOS_LVO_CREATEDIR EQU -120         ; CreateDir(name d1) -> BPTR lock | 0
DOS_LVO_DATESTAMP EQU -192         ; DateStamp(ds d1 APTR) -> ds
DOS_LVO_RENAME   EQU -78           ; Rename(ancien d1, nouveau d2) -> booléen
DOS_LVO_LOCK     EQU -84           ; Lock(name d1, mode d2) -> BPTR lock | 0
DOS_LVO_UNLOCK   EQU -90           ; UnLock(lock d1) -> libère
DOS_LVO_EXAMINE  EQU -102          ; Examine(lock d1, fib d2) -> DOSTRUE/DOSFALSE
DOS_LVO_EXNEXT   EQU -108          ; ExNext(lock d1, fib d2) -> DOSTRUE/DOSFALSE (DOSFALSE + IoErr=232 -> fin)

; Seek : modes (dos.i) + codes d'erreur (dos.i) utilisés par le handler/IoErr
OFFSET_BEGINNING EQU -1            ; Seek depuis le début
OFFSET_CURRENT   EQU 0             ; Seek relatif à la position courante
OFFSET_END       EQU 1             ; Seek depuis la fin
ERROR_OBJECT_NOT_FOUND EQU 205     ; dos/dos.i : fichier/objet introuvable (Open d'un nom absent)
ERROR_ACTION_NOT_KNOWN EQU 209     ; dos/dos.i : action/fonction non supportée
ERROR_DEVICE_NOT_MOUNTED EQU 218   ; dos/dos.i : préfixe « xxx: » inconnu de la DosList
ERROR_RENAME_ACROSS_DEVICES EQU 215
ERROR_SEEK_ERROR EQU 303           ; dos/dos.i : Seek hors bornes
ERROR_NO_MORE_ENTRIES EQU 232      ; dos/dos.i : ExNext a épuisé le répertoire (fin d'énumération normale)
ERROR_OBJECT_IN_USE EQU 202
ERROR_OBJECT_EXISTS EQU 203
ERROR_INVALID_COMPONENT_NAME EQU 210
ERROR_OBJECT_WRONG_TYPE EQU 212
ERROR_DISK_NOT_VALIDATED EQU 213
ERROR_DISK_WRITE_PROTECTED EQU 214
ERROR_DIRECTORY_NOT_EMPTY EQU 216
ERROR_DISK_FULL EQU 221
ACTION_SET_PROTECT EQU 21          ; (ARG1 -, ARG2 lock, ARG3 BSTR nom, ARG4 masque)
ACTION_SET_COMMENT EQU 28          ; (ARG1 -, ARG2 lock, ARG3 BSTR nom, ARG4 BSTR commentaire)
ACTION_DISK_INFO EQU 25            ; (ARG1 BPTR InfoData)
ACTION_INFO      EQU 26            ; (ARG1 lock, ARG2 BPTR InfoData)

; --- FileLock (dos.i) : préfixe public V34 + curseur d'énumération PRIVÉ ---
; Déviation clean-room ASSUMÉE : le vrai AmigaDOS garde le curseur d'ExNext dans le FIB (fib_DiskKey) ; on le garde
; dans le lock (flp_Bucket/flp_ChainBlk). Conséquence : Examine d'un lock dans un FIB puis ExNext via un AUTRE FIB
; désynchroniserait un appelant qui mélange les FIB. Suffisant pour notre harnais (un lock = une énumération).
; --- struct CommandLineInterface (dos/dosextens.i, public) : pointée en BPTR par pr_CLI. Le code de démarrage des
; commandes teste pr_CLI : 0 = lancé par le Workbench (attend le message WBStartup sur pr_MsgPort) ; sinon lit
; cli_CommandName (nom de la commande en cours) et les flux.
CLI_RESULT2         EQU 0          ; LONG
CLI_SETNAME         EQU 4          ; BSTR : nom du répertoire courant
CLI_COMMANDDIR      EQU 8          ; BPTR : liste de chemins de recherche
CLI_RETURNCODE      EQU 12         ; LONG : code retour de la dernière commande
CLI_COMMANDNAME     EQU 16         ; BSTR : nom de la commande en cours
CLI_FAILLEVEL       EQU 20         ; LONG
CLI_PROMPT          EQU 24         ; BSTR
CLI_STANDARDINPUT   EQU 28         ; BPTR FileHandle
CLI_CURRENTINPUT    EQU 32         ; BPTR FileHandle
CLI_COMMANDFILE     EQU 36         ; BSTR
CLI_INTERACTIVE     EQU 40         ; LONG booléen
CLI_BACKGROUND      EQU 44         ; LONG booléen
CLI_CURRENTOUTPUT   EQU 48         ; BPTR FileHandle
CLI_DEFAULTSTACK    EQU 52         ; LONG : pile par défaut EN LONGS
CLI_STANDARDOUTPUT  EQU 56         ; BPTR FileHandle
CLI_MODULE          EQU 60         ; BPTR : seglist de la commande en cours
CLI_SIZEOF          EQU 64
FL_LINK          EQU 0             ; BPTR : lock suivant (on garde 0 : pas de chaînage)
FL_KEY           EQU 4             ; LONG : bloc header de l'objet locké
FL_ACCESS        EQU 8             ; LONG : SHARED_LOCK / EXCLUSIVE_LOCK
FL_TASK          EQU 12            ; APTR : MsgPort du handler (source du port pour UnLock/Examine/ExNext)
FL_VOLUME        EQU 16            ; BPTR : noeud volume (DosBase DL_VOLUME)
FLP_BUCKET       EQU 20            ; LONG privé : index de bucket courant dans la hashtable du répertoire
FLP_CHAIN        EQU 24            ; LONG privé : bloc courant dans la chaîne hash (0 = passer au bucket suivant)
FL_SIZEOF        EQU 28

; --- FileInfoBlock (dos.i) : rempli minimalement (DiskKey/DirEntryType/FileName/Size) ---
FIB_DISKKEY      EQU 0             ; LONG : clé disque (= bloc header de l'entrée)
FIB_DIRENTRYTYPE EQU 4            ; LONG : <0 fichier (ST_FILE=-3), >0 répertoire (ST_ROOT=1/ST_USERDIR=2)
FIB_FILENAME     EQU 8             ; char[108] : BSTR côté packet ; chaîne C après Examine/ExNext (dos convertit)
FIB_PROTECTION   EQU 116           ; LONG : bits de protection (RWED inversés + p, s, a)
FIB_ENTRYTYPE    EQU 120           ; LONG (= DirEntryType)
FIB_SIZE         EQU 124           ; LONG : taille du fichier en octets (0 pour un répertoire)
FIB_NUMBLOCKS    EQU 128           ; LONG : nombre de blocs de données
FIB_DATE         EQU 132           ; DateStamp (3 LONG : jours, minutes, ticks)
FIB_COMMENT      EQU 144           ; char[80] : BSTR côté packet ; chaîne C après Examine/ExNext
FIB_SIZEOF       EQU 260

; DOS_NO_IOERR=1 (RED) : dos_sendpkt NE copie PAS dp_Res2 -> pr_Result2 -> IoErr renvoie 0 même après un Open
; raté -> « DOS IOERR SEEK OK » absent. Isole le câblage IoErr (dp_Res2 du packet -> pr_Result2). Défaut 0.
DOS_NO_IOERR     EQU 0
; HND_NO_SEEK=1 (RED) : le handler file DF0: ne sert PAS ACTION_SEEK (HS_POS inchangé) -> après Seek(0,BEGINNING)
; la 2e lecture repart de la position courante au lieu du début -> octets différents -> « DOS IOERR SEEK OK »
; absent. Isole le repositionnement. Défaut 0.
HND_NO_SEEK      EQU 0
; DOS_NO_WRITE=1 (RED) : dos_fn_write N'ENVOIE PAS le packet ACTION_WRITE -> con_handler n'émet rien -> le marqueur
; « DOS WRITE OK » (émis PAR le Write via la console) est absent. Isole le routage Write -> handler. Défaut 0.
DOS_NO_WRITE     EQU 0

; LOADSEG_LVO_UNWIRED=1 (RED LoadSeg) : le vecteur LoadSeg (-150) pointe sur dos_null au lieu de dos_fn_loadseg
; -> jsr -150(a6) renvoie 0 -> le client d3e n'obtient pas de seglist -> « D3E LOADSEG LVO OK » + le run du
; programme chargé absents. d3d_client (load inline Open/Read/ls_load_hunks) reste VERT -> isole le câblage du
; vecteur LVO LoadSeg (prouve que LoadSeg est bien atteignable via -150, pas seulement via la machinerie interne). Défaut 0.
LOADSEG_LVO_UNWIRED EQU 0

; D3A_NO_REPLY=1 (RED D3a) : le handler echo ne fait PAS ReplyMsg -> le driver reste bloqué sur WaitPort ->
; « D3A ... OK » jamais émis. Isole l'aller-retour packet (le chemin PutMsg->serve->ReplyMsg->WaitPort). Défaut 0.
D3A_NO_REPLY     EQU 0

; D3B_NO_READ=1 (RED D3b) : le handler file DF0: ne sert PAS ACTION_READ (renvoie EOF=0) -> le driver lit 0 octet
; -> marqueurs absents -> « D3B ... OK » absent (FINDINPUT/END marchent encore). Isole le service READ. Défaut 0.
D3B_NO_READ      EQU 0

; D3C_NO_FHTYPE=1 (RED D3c) : dos Open ne pose PAS fh_Type (le port du handler) dans le FileHandle -> dos Read
; voit fh_Type=0 et ne route pas le packet (renvoie 0) -> contenu non lu -> « D3C ... OK » absent. Isole le câblage
; de la route Open->Read (fh_Type). Pas de crash (Read garde-fou fh_Type==0). Défaut 0.
D3C_NO_FHTYPE    EQU 0

; D3D_NO_RUN=1 (RED D3d) : le client charge la commande via dos (Open/Read -> ls_load_hunks) mais NE l'EXÉCUTE PAS
; (saute le JSR au seglist) -> la commande n'émet pas son marqueur -> « D3D ... OK » absent. Isole l'exécution de
; la commande chargée-par-dos (le chargement/reloc reste prouvé par D2). Défaut 0.
D3D_NO_RUN       EQU 0

; E1_NO_WRITE=1 (RED E1) : le handler console ne sert PAS ACTION_WRITE (renvoie le compte mais N'ÉMET RIEN sur le
; série) -> « E1 CON WRITE OK » absent (le client ouvre/ferme encore, le round-trip packet marche). Isole le service
; WRITE du handler console (dispatch packet -> émission série via le handler). Défaut 0.
E1_NO_WRITE      EQU 0

; E2_NO_DISPATCH=1 (RED E2) : le shell lit la ligne mais NE DISPATCHE PAS les builtins (tout -> « ? » inconnu) ->
; « E2 SHELL ver OK » absent sur « ver », « echo X » non renvoyé. Isole le parse/dispatch (la banner + le read-echo
; marchent encore). Défaut 0.
E2_NO_DISPATCH   EQU 0

; E3_NO_EXEC=1 (RED E3) : une commande tapée inconnue est bien TROUVÉE + CHARGÉE depuis DF0: via dos (ls_load_hunks)
; mais NON EXÉCUTÉE (saute le JSR au seglist) -> le marqueur de la commande absent (pas de « ? » non plus : elle est
; trouvée). Isole l'exécution de la commande tapée (le chargement/reloc reste prouvé par D2/D3d). Défaut 0.
E3_NO_EXEC       EQU 0

; F1_NO_STARTUP=1 (RED F1) : l'Initial CLI NE lit/exécute PAS la startup-sequence (va directement à l'invite
; interactive) -> marqueurs du script (« F1BOOTOK », e3cmd) absents, mais le shell interactif marche encore. Isole
; l'exécution de la startup-sequence au boot (la création gatée-sur-boot de l'Initial CLI reste, elle). Défaut 0.
F1_NO_STARTUP    EQU 0
