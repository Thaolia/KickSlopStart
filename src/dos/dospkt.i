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

; --- codes ACTION_* (= mode d'Open pour les FIND*) ---
ACTION_FINDUPDATE  EQU 1004
ACTION_FINDINPUT   EQU 1005        ; = MODE_OLDFILE
ACTION_FINDOUTPUT  EQU 1006        ; = MODE_NEWFILE
ACTION_READ        EQU 82          ; 'R'
ACTION_WRITE       EQU 87          ; 'W'
ACTION_SEEK        EQU 1008
ACTION_END         EQU 1007
ACTION_LOCATE_OBJECT EQU 8
ACTION_FREE_LOCK   EQU 15

MODE_OLDFILE     EQU 1005
MODE_NEWFILE     EQU 1006
MODE_READWRITE   EQU 1004

DOSTRUE          EQU -1
DOSFALSE         EQU 0

; D3A_NO_REPLY=1 (RED D3a) : le handler echo ne fait PAS ReplyMsg -> le driver reste bloqué sur WaitPort ->
; « D3A ... OK » jamais émis. Isole l'aller-retour packet (le chemin PutMsg->serve->ReplyMsg->WaitPort). Défaut 0.
D3A_NO_REPLY     EQU 0

; D3B_NO_READ=1 (RED D3b) : le handler file DF0: ne sert PAS ACTION_READ (renvoie EOF=0) -> le driver lit 0 octet
; -> marqueurs absents -> « D3B ... OK » absent (FINDINPUT/END marchent encore). Isole le service READ. Défaut 0.
D3B_NO_READ      EQU 0
