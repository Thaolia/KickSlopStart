; src/dos/dos_lib.s — dos.library (M6 : squelette résident + convention BPTR + DateStamp).
; Calqué sur intuition_lib.s (M5) : ROMTag RTF_AUTOINIT NT_LIBRARY, auto-scanné par build_reslist -> MakeLibrary
; crée DosBase, Enqueue dans EB_LIBLIST. Pri 0 (place roadmap dos : init en dernier, après tous les autres résidents).
;
; Déviation clean-room assumée : le vrai dos.library 1.3 est un portage BCPL (init via glue BCPL, global vector).
; On reproduit l'ABI OBSERVABLE (DosBase + RootNode + DosInfo liés par BPTR, DateStamp), pas le mécanisme BCPL —
; même approche qu'AROS rom/dos (réécriture C en conservant BPTR). Hors M6 (différé) : packets, LoadSeg, handlers,
; Open/Read/Lock..., strap/trackdisk, écran insert-disk (-> incréments M6 ultérieurs).
;
; Convention BPTR (quirk signature de dos) : un BPTR est une adresse divisée par 4 (addr>>2). La réversibilité du
; <<2/>>2 EXIGE des structures long-alignées -> RootNode et DosInfo sont alloués SÉPARÉMENT via AllocMem (exec aligne
; >= 8), jamais embarqués dans DosBase (dont la fin, offset 70, n'est pas multiple de 4).
;
; Piste IMPLÉMENTATION (« clean ») : AutoDocs dos.library + NDK includes/.fd (public). AUCUNE lecture ROM.

                include "exec.i"
                include "dos.i"
                include "dospkt.i"       ; D3c : FileHandle / DosPacket / ACTION_* / DeviceNode / PR_MSGPORT

                xref    dos_sendpkt      ; dos/process.s (D3 : envoi d'un DOS packet)
                xref    ls_load_hunks    ; dos/loadseg.s (parse hunk d'un buffer -> seglist BPTR)
                xref    dos_unloadseg    ; dos/loadseg.s (libère une chaîne de segments)
                xref    newlist          ; exec/lists.s (NEWLIST du port de Delay)
                xref    bcpl_starthandler ; dos/bcpl.s (démarrage du handler d'un DeviceNode)
                xref    proc_create      ; dos/process.s (Process + pile + pr_MsgPort + AddTask)
                xdef    dos_boot_assigns ; appelé par le CLI initial (shell.s) une fois le disque de boot lisible
                xdef    dos_resolve      ; runtime BCPL (deviceproc)

LS_LOADMAX      EQU DOS_FILEMAX       ; buffer de lecture LoadSeg (cap-bump 32K, exec.i ; cf. HND_FILEMAX)

; --- ROMTag dos.library (scanné par build_reslist) ---
        EVEN
dos_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    dos_romtag               ; RT_MATCHTAG = self
        dc.l    dos_end                  ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT,34,NT_LIBRARY,0   ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (0 : place roadmap dos)
        dc.l    dos_name                 ; RT_NAME
        dc.l    dos_name                 ; RT_IDSTRING
        dc.l    dos_inittab              ; RT_INIT -> table AUTOINIT
dos_name:
        dc.b    "dos.library",0
        EVEN
dos_inittab:
        dc.l    DOSBASE_DATASIZE         ; dataSize : base Library + champs dos + scaffold DL_DISHADOW
        dc.l    dos_vectors              ; funcTable
        dc.l    dos_datatab              ; dataTable (InitStruct)
        dc.l    dos_initfunc             ; initFunc
; table ABSOLUE terminée par -1. Vecteur N -> LVO -6*N. D3c : Open(-30,v5)/Close(-36,v6)/Read(-42,v7) implémentés
; (via packets vers le file-handler). LoadSeg(-150,v25)/UnLoadSeg(-156,v26) composent Open/Read + ls_load_hunks.
; Les autres vecteurs pointent sur dos_null (non impl.).
dos_vectors:
        dc.l    dos_open                 ; 1 : LVO -6  (Open LIBRAIRIE : OpenCnt++)
        dc.l    dos_close                ; 2 : LVO -12 (Close LIBRAIRIE)
        dc.l    dos_expunge              ; 3 : LVO -18
        dc.l    dos_null                 ; 4 : LVO -24 (réservé)
        dc.l    dos_fn_open              ; 5 : LVO -30 Open(name d1, mode d2) -> BPTR FileHandle
        dc.l    dos_fn_close             ; 6 : LVO -36 Close(fh d1)
        dc.l    dos_fn_read              ; 7 : LVO -42 Read(fh d1, buf d2, len d3) -> octets
        dc.l    dos_fn_write             ; 8  : LVO -48 Write(fh d1, buf d2, len d3) -> octets écrits
        dc.l    dos_fn_input             ; 9  : LVO -54 Input() -> BPTR pr_CIS
        dc.l    dos_fn_output            ; 10 : LVO -60 Output() -> BPTR pr_COS
        dc.l    dos_fn_seek              ; 11 : LVO -66 Seek(fh d1, position d2, mode d3)
        dc.l    dos_fn_deletefile        ; 12 : LVO -72  DeleteFile(name d1)
        dc.l    dos_fn_rename            ; 13 : LVO -78  Rename(ancien d1, nouveau d2)
        dc.l    dos_fn_lock              ; 14 : LVO -84  Lock(name d1, mode d2) -> BPTR FileLock
        dc.l    dos_fn_unlock            ; 15 : LVO -90  UnLock(lock d1)
        dc.l    dos_null                 ; 16 : LVO -96  (DupLock non impl.)
        dc.l    dos_fn_examine           ; 17 : LVO -102 Examine(lock d1, fib d2)
        dc.l    dos_fn_exnext            ; 18 : LVO -108 ExNext(lock d1, fib d2)
        dc.l    dos_null                 ; 19 : LVO -114 (Info non impl.)
        dc.l    dos_fn_createdir         ; 20 : LVO -120 CreateDir(name d1) -> BPTR lock
        dc.l    dos_fn_currentdir        ; 21 : LVO -126 CurrentDir(lock d1) -> ancien lock
        dc.l    dos_fn_ioerr             ; 22 : LVO -132 IoErr() -> pr_Result2
        dc.l    dos_fn_createproc        ; 23 : LVO -138 CreateProc(nom d1, pri d2, seglist d3, pile d4)
        dc.l    dos_null                 ; 24 : LVO -144 (Exit non impl.)
                ifeq    LOADSEG_LVO_UNWIRED
        dc.l    dos_fn_loadseg           ; 25 : LVO -150 LoadSeg(name d1) -> BPTR seglist
                endc
                ifne    LOADSEG_LVO_UNWIRED
        dc.l    dos_null                 ; RED LOADSEG_LVO_UNWIRED : LoadSeg non câblé -> jsr -150 renvoie 0
                endc
        dc.l    dos_fn_unloadseg         ; 26 : LVO -156 UnLoadSeg(seglist d1)
        dcb.l   5,dos_null               ; 27..31 : LVO -162..-186 (non impl.)
        dc.l    dos_DateStamp            ; 32 : LVO -192
        dc.l    dos_fn_delay             ; 33 : LVO -198 Delay(ticks d1)
        dc.l    dos_fn_waitforchar       ; 34 : LVO -204 WaitForChar(fh d1, µs d2)
        dc.l    dos_fn_parentdir         ; 35 : LVO -210 ParentDir(lock d1)
        dc.l    dos_fn_isinteractive     ; 36 : LVO -216 IsInteractive(fh d1)
        dc.l    dos_fn_execute           ; 37 : LVO -222 Execute(cmd d1, in d2, out d3) — dernier LVO V34
        dc.l    -1
dos_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)   ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34            ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(lib a6) : incrémente le compte d'ouverture, retourne la base (convention OpenLibrary).
dos_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
dos_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
dos_expunge:
        moveq   #0,d0               ; pas d'expunge ce milestone (base résidente)
        rts
dos_null:
        moveq   #0,d0
        rts

; DateStamp(date d1) (a6 = DosBase) -> d0 = date. AutoDoc : « All three elements are zero if the date is unset ».
; Notre horloge n'est PAS réglée (ni battclock ni dl_TimeReq câblés ce milestone) -> (0,0,0) est le comportement
; FIDÈLE V34, pas un stub. Renvoie le pointeur passé (compat pré-V36). Arg en d1 (dos BCPL-dérivé : args en D1..).
dos_DateStamp:
        move.l  d1,a0
        clr.l   (a0)                ; ds_Days   = 0
        clr.l   4(a0)               ; ds_Minute = 0
        clr.l   8(a0)               ; ds_Tick   = 0
        move.l  d1,d0               ; renvoie &date
        rts

; --- D3c : Open / Read / Close user-facing (via DOS packets vers le file-handler DF0:) ---
; Appelées depuis un PROCESS (dos_sendpkt utilise ThisTask->pr_MsgPort comme port de réponse). a6 = DosBase à
; l'entrée (convention librairie) ; on bascule a6 = SysBase pour les appels exec (AllocMem/FreeMem/dos_sendpkt).
; Pas de DoPkt public V34 : dos_sendpkt est l'équivalent interne. Convention d'args BCPL-dérivée (D1, D2, D3...).
; Résolution du nom par dos_resolve (préfixe device/assign/volume, sinon répertoire courant). StandardPacket local à
; la pile de l'appelant (process).

; Open(name d1 [C-string], accessMode d2 [= code ACTION_FIND*]) -> d0 = BPTR FileHandle | 0.
dos_fn_open:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,a4                   ; a4 = nom (C-string)
        move.l  d2,d7                   ; d7 = mode (= dp_Type ACTION_FINDINPUT)
        bsr     dos_resolve             ; a3 = port du handler, d6 = lock de départ, a4 = nom à transmettre
        move.l  a3,d0
        beq     .op_fail_early          ; device inconnu / handler non démarré
        move.l  ($4).w,a6               ; -> SysBase pour les appels exec
        move.l  #DOS_FH_ALLOC+4,d0      ; FileHandle au format getvec : [taille][FileHandle + nom]
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .op_fail_early
        move.l  d0,a2
        move.l  #DOS_FH_ALLOC+4,(a2)+   ; a2 = FileHandle (long-aligné : BPTR)
        lea     FH_SIZEOF(a2),a5        ; a5 = buffer BSTR du nom (long-aligné)
        lea     1(a5),a1                ; a1 -> caractères
        moveq   #0,d3                   ; d3 = longueur
.op_ncpy:
        move.b  (a4)+,d0
        beq.s   .op_ndone
        move.b  d0,(a1)+
        addq.l  #1,d3
        cmp.l   #DOS_NAMEMAX,d3         ; borne du buffer (BSTR)
        bcs.s   .op_ncpy
.op_ndone:
        move.b  d3,(a5)                 ; octet de longueur BCPL
                ifeq    D3C_NO_FHTYPE
        move.l  a3,FH_TYPE(a2)          ; fh_Type = port du handler (route des Read/Close suivants)
                endc                    ; RED D3C_NO_FHTYPE : fh_Type reste 0 -> Read ne route pas
        lea     -SP_SIZEOF(sp),sp       ; StandardPacket sur la pile du process
        move.l  sp,a0
        move.l  a3,a1                   ; port du handler
        move.l  d7,d0                   ; dp_Type = mode (ACTION_FINDINPUT)
        move.l  a2,d1
        lsr.l   #2,d1                   ; ARG1 = BPTR(FileHandle) (le handler y pose fh_Arg1)
        move.l  d6,d2                   ; ARG2 = lock du répertoire de départ
        move.l  a5,d3
        lsr.l   #2,d3                   ; ARG3 = BPTR(nom BSTR)
        jsr     dos_sendpkt             ; d0 = dp_Res1
        lea     SP_SIZEOF(sp),sp
        cmp.l   #DOSTRUE,d0
        bne.s   .op_fail_free
        moveq   #-1,d0
        move.l  d0,FH_POS(a2)           ; fh_Pos = fh_End = -1 : tampon BCPL vide (rdch remplira par Read)
        move.l  d0,FH_END(a2)
        move.l  a2,d0                   ; succès -> BPTR(FileHandle)
        lsr.l   #2,d0
        bra.s   .op_ret
.op_fail_free:
        lea     -4(a2),a1
        move.l  #DOS_FH_ALLOC+4,d0
        jsr     LVO_FREEMEM(a6)
.op_fail_early:
        moveq   #0,d0
.op_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Read(fh d1 [BPTR FileHandle], buf d2, len d3) -> d0 = octets lus (0 = EOF, -1 = erreur).
dos_fn_read:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d2,d5                   ; buf
        move.l  d3,d6                   ; len
        move.l  d1,d4
        lsl.l   #2,d4
        beq.s   .rd_err                 ; fh nul -> erreur (pas de lecture de l'adresse $8)
        move.l  d4,a2                   ; a2 = BADDR(fh)
        move.l  FH_TYPE(a2),a3          ; port du handler
        move.l  a3,d0
        beq.s   .rd_zero                ; fh_Type==0 (non routé) -> 0 (garde-fou RED D3C_NO_FHTYPE)
        move.l  FH_ARG1(a2),d4          ; clé du fichier
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_READ,d0
        move.l  d4,d1                   ; ARG1 = clé
        move.l  d5,d2                   ; ARG2 = buffer
        move.l  d6,d3                   ; ARG3 = longueur
        jsr     dos_sendpkt             ; d0 = octets lus
        lea     SP_SIZEOF(sp),sp
        bra.s   .rd_ret
.rd_err:
        moveq   #-1,d0
        bra.s   .rd_ret
.rd_zero:
        moveq   #0,d0
.rd_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Close(fh d1 [BPTR FileHandle]) -> d0 = DOSTRUE.
dos_fn_close:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,d4
        lsl.l   #2,d4
        beq     .cl_null                ; fh nul -> rien à fermer
        move.l  d4,a2                   ; a2 = BADDR(fh)
        move.l  FH_TYPE(a2),a3
        move.l  a3,d0
        beq.s   .cl_free                ; non routé -> juste libérer
        move.l  FH_ARG1(a2),d4          ; clé
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_END,d0
        move.l  d4,d1                   ; ARG1 = clé
        moveq   #0,d2
        moveq   #0,d3
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        bra.s   .cl_free2
.cl_free:
        move.l  ($4).w,a6
.cl_free2:
        ; FileHandle = bloc getvec (taille à -4, spec BCPL §5.1) : ceux construits par les programmes BCPL (ex. le
        ; FileHandle mémoire de c:Run) arrivent ici aussi -> libération par la taille de l'en-tête, jamais une taille fixe.
        ; fh_Buf n'est libéré que s'il appartient au runtime (tampon getvec de rdch, HORS du bloc du FileHandle).
        move.l  -4(a2),d5               ; d5 = taille du bloc du FileHandle (en-tête compris)
        move.l  FH_BUF(a2),d0
        lsl.l   #2,d0
        beq.s   .cl_nobuf
        move.l  d0,a1
        move.l  a2,d1
        subq.l  #4,d1                   ; début du bloc du FileHandle
        cmp.l   d1,a1
        bcs.s   .cl_bufown
        add.l   d5,d1
        cmp.l   d1,a1
        bcs.s   .cl_nobuf               ; tampon interne au bloc (FileHandle mémoire) : rien à libérer
.cl_bufown:
        cmp.l   #(RT_FHBUFLONGS+2)*4,-4(a1)
        bne.s   .cl_nobuf               ; pas un tampon du runtime : ne pas y toucher
        subq.l  #4,a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
.cl_nobuf:
        lea     -4(a2),a1               ; libère le FileHandle (bloc getvec)
        move.l  d5,d0
        jsr     LVO_FREEMEM(a6)
.cl_null:
        moveq   #-1,d0                  ; DOSTRUE
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Seek(fh d1 [BPTR FileHandle], position d2, mode d3 [OFFSET_BEGINNING/-CURRENT/-END]) -> d0 = ancienne position | -1.
; Envoie ACTION_SEEK au handler (ARG1=clé, ARG2=position, ARG3=mode). Le handler bufferise tout le fichier -> le
; repositionnement est un simple ajustement de HS_POS. a6 = DosBase à l'entrée. Depuis un PROCESS (comme Read).
dos_fn_seek:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d2,d5                   ; position
        move.l  d3,d6                   ; mode
        move.l  d1,d4
        lsl.l   #2,d4
        beq.s   .sk_err                 ; fh nul
        move.l  d4,a2                   ; a2 = BADDR(fh)
        move.l  FH_TYPE(a2),a3          ; port du handler
        move.l  a3,d0
        beq.s   .sk_err                 ; non routé
        move.l  FH_ARG1(a2),d4          ; clé du fichier
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_SEEK,d0
        move.l  d4,d1                   ; ARG1 = clé
        move.l  d5,d2                   ; ARG2 = position
        move.l  d6,d3                   ; ARG3 = mode
        jsr     dos_sendpkt             ; d0 = dp_Res1 (ancienne pos | -1) ; pr_Result2 posé par dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        bra.s   .sk_ret
.sk_err:
        moveq   #-1,d0
.sk_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; IoErr() -> d0 = pr_Result2 de ThisTask (code d'erreur du dernier packet dos). a6 = DosBase (non utilisé).
dos_fn_ioerr:
        move.l  ($4).w,a0              ; SysBase
        move.l  EB_THISTASK(a0),a0
        move.l  PR_RESULT2(a0),d0
        rts

; Write(fh d1 [BPTR FileHandle], buf d2, len d3) -> d0 = octets écrits | -1. Envoie ACTION_WRITE au handler
; (ARG1=clé, ARG2=buf, ARG3=len). Vers con_handler -> émission série ; vers l'OFS DF0: (lecture seule) -> erreur.
; a6 = DosBase à l'entrée. Depuis un PROCESS (comme Read). Mirror de dos_fn_read.
dos_fn_write:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d2,d5                   ; buf
        move.l  d3,d6                   ; len
        move.l  d1,d4
        lsl.l   #2,d4
        beq.s   .wr_err                 ; fh nul
        move.l  d4,a2                   ; a2 = BADDR(fh)
        move.l  FH_TYPE(a2),a3          ; port du handler
        move.l  a3,d0
        beq.s   .wr_err                 ; non routé
        move.l  FH_ARG1(a2),d4          ; clé
                ifne    DOS_NO_WRITE
        moveq   #0,d0                   ; RED DOS_NO_WRITE : n'envoie pas -> rien émis
        bra.s   .wr_ret
                endc
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_WRITE,d0
        move.l  d4,d1                   ; ARG1 = clé
        move.l  d5,d2                   ; ARG2 = buf
        move.l  d6,d3                   ; ARG3 = len
        jsr     dos_sendpkt             ; d0 = octets écrits ; pr_Result2 posé par dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        bra.s   .wr_ret
.wr_err:
        moveq   #-1,d0
.wr_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Input() -> d0 = BPTR pr_CIS de ThisTask (FileHandle d'entrée standard). a6 = DosBase (non utilisé).
dos_fn_input:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_CIS(a0),d0
        rts

; Output() -> d0 = BPTR pr_COS de ThisTask (FileHandle de sortie standard). a6 = DosBase (non utilisé).
dos_fn_output:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_COS(a0),d0
        rts

; CurrentDir(lock d1 [BPTR]) -> d0 = ANCIEN pr_CurrentDir. Pose le nouveau lock du répertoire courant. a6 = DosBase.
dos_fn_currentdir:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_CURRENTDIR(a0),d0    ; ancien (valeur de retour)
        move.l  d1,PR_CURRENTDIR(a0)    ; nouveau
        rts

; --- LoadSeg / UnLoadSeg (vecteurs LVO -150 / -156) : chargement d'exécutable hunk VIA LES VRAIS Open/Read ---
; Appelées depuis un PROCESS (comme Open/Read : dos_sendpkt utilise ThisTask->pr_MsgPort comme reply port).

; LoadSeg(name d1 [C-string]) -> d0 = BPTR seglist | 0. Ouvre le fichier via dos Open (-30, MODE_OLDFILE), le lit
; ENTIER via dos Read (-42, boucle jusqu'à EOF ; le file-handler est séquentiel) dans un buffer AllocMem'd, le parse
; (ls_load_hunks : hunks CODE/DATA/BSS + relocations RELOC32 -> seglist BPTR), referme (-36), libère le buffer. Portée
; milestone (cf. Lemmings) : charge NOS exécutables hunk via le vrai chemin LVO ; whole-file bufferisé (<= LS_LOADMAX,
; pas de streaming), handler OFS DF0: seul -> ne suffit PAS à exécuter du logiciel commercial (Lock/Seek/Examine/Write,
; expansion.library, streaming... manquent). a4 = DosBase (préservé par Open/Read/Close/ls_load_hunks/AllocMem).
dos_fn_loadseg:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a4                  ; a4 = DosBase (survit à tous les appels)
        move.l  #MODE_OLDFILE,d2       ; Open(name d1 [déjà posé], mode d2 = ACTION_FINDINPUT)
        bsr     dos_fn_open            ; d0 = BPTR fh | 0 ; a6 restauré = DosBase
        move.l  d0,d7                  ; d7 = BPTR fh
        beq     .ls_fail0
        move.l  ($4).w,a6              ; SysBase pour AllocMem
        move.l  #LS_LOADMAX,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ls_close              ; pas de RAM -> referme fh, 0
        move.l  d0,a2                  ; a2 = buffer de lecture
        moveq   #0,d5                  ; d5 = total lu
.ls_rloop:
        move.l  #LS_LOADMAX,d6
        sub.l   d5,d6                  ; restant
        ble.s   .ls_rdone              ; buffer plein -> stop
        move.l  a4,a6                  ; Read via DosBase
        move.l  d7,d1                  ; fh
        move.l  a2,d2
        add.l   d5,d2                  ; buf + total (le handler avance HS_POS)
        move.l  d6,d3                  ; restant
        bsr     dos_fn_read            ; d0 = octets lus (0 = EOF)
        tst.l   d0
        ble.s   .ls_rdone              ; 0 (EOF) ou <0 (err) -> stop
        add.l   d0,d5
        bra.s   .ls_rloop
.ls_rdone:
        move.l  ($4).w,a6              ; ls_load_hunks attend a6 = SysBase
        move.l  a2,a0                  ; buffer
        move.l  d5,d0                  ; taille lue
        jsr     ls_load_hunks          ; d0 = BPTR seglist | 0 (loadseg.o loin -> jsr)
        move.l  d0,d6                  ; d6 = seglist
        move.l  a2,a1                  ; libère le buffer
        move.l  #LS_LOADMAX,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a4,a6                  ; referme fh via DosBase
        move.l  d7,d1
        bsr     dos_fn_close
        move.l  d6,d0                  ; renvoie seglist
        bra.s   .ls_ret
.ls_close:
        move.l  a4,a6
        move.l  d7,d1
        bsr     dos_fn_close
.ls_fail0:
        moveq   #0,d0
.ls_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; UnLoadSeg(seglist d1 [BPTR]) -> d0 = 0. Libère la chaîne de segments (dos_unloadseg : d0 = BPTR, a6 = SysBase).
dos_fn_unloadseg:
        move.l  a6,-(sp)
        move.l  d1,d0                  ; d0 = BPTR seglist
        move.l  ($4).w,a6             ; SysBase (FreeMem)
        jsr     dos_unloadseg          ; (loadseg.o loin -> jsr) ; d0=0 -> no-op
        moveq   #0,d0
        move.l  (sp)+,a6
        rts

; --- Lock / UnLock / Examine / ExNext (vecteurs LVO -84 / -90 / -102 / -108) : locks + lecture de répertoire OFS ---
; Appelées depuis un PROCESS (dos_sendpkt = reply port = ThisTask->pr_MsgPort). Le handler DF0: (handler.s) alloue
; le FileLock, remplit le FileInfoBlock et énumère via la machinerie OFS (ofs_name_to_block/ofs_fill_fib/ofs_dir_next).

; Lock(name d1 [C-string], mode d2 [SHARED_LOCK/EXCLUSIVE_LOCK]) -> d0 = BPTR FileLock | 0. dos_resolve donne le port
; du handler et le lock parent, le nom est converti en BSTR LONG-ALIGNÉ (BPTR exige l'alignement), puis
; ACTION_LOCATE_OBJECT (ARG1 = lock parent, ARG2 = nom, ARG3 = mode). a6 = DosBase.
dos_fn_lock:
        move.l  #ACTION_LOCATE_OBJECT,d0 ; ARG3 = mode (d2)
        bra.s   dos_namepkt

; CreateDir(name d1) -> BPTR lock du répertoire créé | 0 (ACTION_CREATE_DIR). DeleteFile(name d1) -> DOSTRUE/DOSFALSE
; (ACTION_DELETE_OBJECT). a6 = DosBase.
dos_fn_createdir:
        move.l  #ACTION_CREATE_DIR,d0
        bra.s   dos_namepkt
dos_fn_deletefile:
        move.l  #ACTION_DELETE_OBJECT,d0

; dos_namepkt(d0 = action, d1 = nom C, d2 = ARG3, a6 = DosBase) -> d0 = dp_Res1 (0 si le nom ne résout pas ; IoErr
; posé). Résout le nom (dos_resolve : démarre le handler au besoin), puis envoie ARG1 = lock de départ, ARG2 =
; BPTR du nom restant en BSTR, ARG3 au handler. Ne modifie aucun registre de l'appelant hors d0/d1/a0/a1 (convention
; LVO : d2-d7/a2-a6 préservés).
dos_namepkt:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d0,d5                   ; d5 = action
        move.l  d1,a4                   ; a4 = nom (C-string)
        move.l  d2,d7                   ; d7 = ARG3
        bsr     dos_resolve             ; a3 = port du handler, d6 = lock parent, a4 = nom à transmettre
        move.l  a3,d0
        beq     .np_fail                ; device inconnu / handler impossible à démarrer
        move.l  ($4).w,a6               ; SysBase
        lea     -(DOS_NAMEMAX+5)(sp),sp ; zone BSTR sur la pile (taille paire : SP reste pair)
        move.l  sp,d0
        addq.l  #3,d0
        and.l   #-4,d0                  ; arrondi au long supérieur -> BSTR long-aligné (BPTR réversible)
        move.l  d0,a5                   ; a5 = BSTR
        lea     1(a5),a1               ; a1 -> caractères
        moveq   #0,d3                   ; d3 = longueur
.np_ncpy:
        move.b  (a4)+,d0
        beq.s   .np_ndone
        move.b  d0,(a1)+
        addq.l  #1,d3
        cmp.l   #DOS_NAMEMAX,d3         ; borne du buffer (BSTR)
        bcs.s   .np_ncpy
.np_ndone:
        move.b  d3,(a5)                 ; octet de longueur BCPL
        lea     -SP_SIZEOF(sp),sp       ; StandardPacket
        move.l  sp,a0
        move.l  a3,a1                   ; port du handler
        move.l  d5,d0
        move.l  d6,d1                   ; ARG1 = lock parent
        move.l  a5,d2
        lsr.l   #2,d2                   ; ARG2 = BPTR(nom BSTR)
        move.l  d7,d3                   ; ARG3
        jsr     dos_sendpkt             ; d0 = dp_Res1
        lea     SP_SIZEOF(sp),sp
        lea     DOS_NAMEMAX+5(sp),sp    ; libère la zone BSTR
        bra.s   .np_ret
.np_fail:
        moveq   #0,d0
.np_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Rename(ancien d1, nouveau d2) -> DOSTRUE/DOSFALSE : ACTION_RENAME_OBJECT (ARG1 lock, ARG2 BSTR ancien nom, ARG3
; lock, ARG4 BSTR nouveau nom) au handler commun ; handlers différents -> IoErr = ERROR_RENAME_ACROSS_DEVICES.
DOS_RNFRAME     EQU 2*(DOS_NAMEMAX+1)+4    ; deux BSTR de 256 octets + marge d'alignement
dos_fn_rename:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d2,d7                   ; d7 = nouveau nom
        move.l  d1,a4
        bsr     dos_resolve
        move.l  a3,d0
        beq     .rn_fail
        move.l  a3,a5                   ; a5 = port, d5 = lock, a2 = nom (ancien)
        move.l  d6,d5
        move.l  a4,a2
        move.l  d7,a4
        bsr     dos_resolve
        move.l  a3,d0
        beq     .rn_fail
        cmp.l   a3,a5
        beq.s   .rn_same
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  #ERROR_RENAME_ACROSS_DEVICES,PR_RESULT2(a0)
        bra     .rn_fail
.rn_same:
        lea     -DOS_RNFRAME(sp),sp
        move.l  sp,d0
        addq.l  #3,d0
        and.l   #-4,d0
        move.l  d0,a0                   ; BSTR ancien nom (long-aligné)
        move.l  a2,a1
        bsr     dos_c2bstr
        move.l  a0,d2
        lsr.l   #2,d2                   ; ARG2
        lea     DOS_NAMEMAX+1(a0),a0    ; BSTR nouveau nom (+256 : reste long-aligné)
        move.l  a4,a1
        bsr     dos_c2bstr
        move.l  a0,d4
        lsr.l   #2,d4                   ; ARG4
        move.l  d5,d1                   ; ARG1
        move.l  d6,d3                   ; ARG3
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a5,a1
        move.l  #ACTION_RENAME_OBJECT,d0
        jsr     dos_sendpkt
        lea     SP_SIZEOF+DOS_RNFRAME(sp),sp
        bra.s   .rn_ret
.rn_fail:
        moveq   #0,d0
.rn_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; dos_c2bstr(a0 = destination long-alignée, a1 = C-string) : BSTR (DOS_NAMEMAX caractères max). Préserve a0 ; a1
; avancé.
dos_c2bstr:
        movem.l d0-d1/a2,-(sp)
        lea     1(a0),a2
        moveq   #0,d1
.cb_lp:
        move.b  (a1)+,d0
        beq.s   .cb_end
        move.b  d0,(a2)+
        addq.l  #1,d1
        cmp.l   #DOS_NAMEMAX,d1
        bcs.s   .cb_lp
.cb_end:
        move.b  d1,(a0)
        movem.l (sp)+,d0-d1/a2
        rts

; UnLock(lock d1 [BPTR]) -> d0 = 0. Récupère le port du handler via fl_Task du lock, envoie ACTION_FREE_LOCK.
dos_fn_unlock:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,d4                   ; BPTR lock
        move.l  d4,d0
        lsl.l   #2,d0
        beq.s   .ul_ret                 ; lock 0 -> no-op
        move.l  d0,a2                   ; BADDR(lock)
        move.l  FL_TASK(a2),a3          ; port du handler
        move.l  a3,d0
        beq.s   .ul_ret
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  #ACTION_FREE_LOCK,d0
        move.l  d4,d1                   ; ARG1 = BPTR lock
        moveq   #0,d2
        moveq   #0,d3
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
.ul_ret:
        moveq   #0,d0
        movem.l (sp)+,d2-d7/a2-a6
        rts

; Examine(lock d1 [BPTR], fib d2 [APTR long-aligné]) -> d0 = DOSTRUE/DOSFALSE. ExNext même signature (entrée suivante).
; Port via fl_Task du lock. ARG2 = BPTR(fib) (le FIB doit être long-aligné -> AllocMem côté appelant). a6 = DosBase.
dos_fn_examine:
        move.l  #ACTION_EXAMINE_OBJECT,d0
        bra.s   dos_examine_pkt
dos_fn_exnext:
        move.l  #ACTION_EXAMINE_NEXT,d0
dos_examine_pkt:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d0,d6                   ; d6 = code action
        move.l  d1,d4                   ; BPTR lock
        move.l  d2,d5                   ; APTR fib
        move.l  d4,d0
        lsl.l   #2,d0
        beq.s   .exc_fail
        move.l  d0,a2                   ; BADDR(lock)
        move.l  FL_TASK(a2),a3          ; port du handler
        move.l  a3,d0
        beq.s   .exc_fail
        move.l  ($4).w,a6               ; SysBase
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        move.l  a3,a1
        move.l  d6,d0                   ; action (EXAMINE_OBJECT / EXAMINE_NEXT)
        move.l  d4,d1                   ; ARG1 = BPTR lock
        move.l  d5,d2
        lsr.l   #2,d2                   ; ARG2 = BPTR(fib)
        moveq   #0,d3
        jsr     dos_sendpkt             ; d0 = dp_Res1 (DOSTRUE/DOSFALSE)
        lea     SP_SIZEOF(sp),sp
        tst.l   d0
        beq.s   .exc_ret
        move.l  d5,a0                   ; le handler rend des BSTR : l'API C veut des chaînes NUL-terminées
        lea     FIB_FILENAME(a0),a0
        bsr.s   dos_bstr2c
        move.l  d5,a0
        lea     FIB_COMMENT(a0),a0
        bsr.s   dos_bstr2c
        bra.s   .exc_ret
.exc_fail:
        moveq   #0,d0                   ; DOSFALSE
.exc_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; dos_bstr2c(a0 = BSTR) : convertit sur place en chaîne C (décale les caractères d'un octet, NUL final).
; Préserve d0. Clobbe d1/a0/a1.
dos_bstr2c:
        moveq   #0,d1
        move.b  (a0),d1
        lea     1(a0),a1
        bra.s   .b2c_next
.b2c_cpy:
        move.b  (a1)+,(a0)+
.b2c_next:
        dbra    d1,.b2c_cpy
        clr.b   (a0)
        rts

; --- LVO -198..-222 : la table s'arrêtait à DateStamp ; un appel au-delà (SetClock : Delay, Execute) tombait dans la
; mémoire sous la jump table. ---

; Delay(ticks d1) : attend d1 cinquantièmes de seconde en BLOQUANT la tâche sur une requête timer.device (unité
; VBLANK, port et requête sur la pile) : une attente active affamerait les process de même priorité (Wait du
; startup-sequence pendant que le CLI de fond de Run exécute StartupII). Repli en attente active seulement si
; aucun signal n'est libre ou si timer.device est absent. a6 = DosBase.
DL_MAXTICKS     EQU 65535*50         ; TV_SECS est converti par mulu (16 bits)
DL_FRAME        EQU MP_SIZE+TR_SIZE
dos_fn_delay:
        movem.l d2-d3/a2-a4/a6,-(sp)
        move.l  d1,d2
        ble     .dl_done
        cmp.l   #DL_MAXTICKS,d2
        bls.s   .dl_ticks
        move.l  #DL_MAXTICKS,d2
.dl_ticks:
        move.l  ($4).w,a6
        lea     EB_DEVICELIST(a6),a0
        lea     dl_timername(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .dl_busy
        move.l  d0,a4                ; a4 = timer.device
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        move.l  d0,d3
        bmi     .dl_busy
        lea     -DL_FRAME(sp),sp
        move.l  sp,a0
        moveq   #DL_FRAME/2-1,d0
.dl_clr:
        clr.w   (a0)+
        dbra    d0,.dl_clr
        move.l  sp,a3                ; a3 = reply port
        lea     MP_SIZE(sp),a2       ; a2 = timerequest
        move.b  #NT_MSGPORT,LN_TYPE(a3)
        move.b  #PA_SIGNAL,MP_FLAGS(a3)
        move.b  d3,MP_SIGBIT(a3)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a3)
        lea     MP_MSGLIST(a3),a1
        jsr     newlist
        move.l  a3,MN_REPLYPORT(a2)
        move.l  a4,IO_DEVICE(a2)
        move.l  #UNIT_VBLANK,IO_UNIT(a2)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a2)
        divu    #50,d2
        moveq   #0,d0
        move.w  d2,d0
        move.l  d0,TV_SECS(a2)
        swap    d2
        mulu    #20000,d2
        move.l  d2,TV_MICRO(a2)
        move.l  a6,-(sp)
        move.l  a4,a6
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
.dl_wait:
        moveq   #0,d0
        bset    d3,d0
        jsr     LVO_WAIT(a6)
        move.l  a3,a0
        jsr     LVO_GETMSG(a6)
        cmp.l   a2,d0
        bne.s   .dl_wait
        lea     DL_FRAME(sp),sp
        move.l  d3,d0
        jsr     LVO_FREESIGNAL(a6)
        bra.s   .dl_done
.dl_busy:
        move.l  VBL_COUNT,d0
        add.l   d2,d0
.dl_spin:
        cmp.l   VBL_COUNT,d0
        bgt.s   .dl_spin
.dl_done:
        moveq   #0,d0
        movem.l (sp)+,d2-d3/a2-a4/a6
        rts
dl_timername:
        dc.b    "timer.device",0
        even

; CreateProc(nom d1 [C], pri d2, seglist d3 [BPTR], pile d4 [octets]) -> d0 = MsgPort du process | 0 (AutoDoc dos).
; Le process démarre directement sur le code du premier segment ; nom recopié (l'appelant peut libérer le sien),
; segarray [3, V!1, V!2 du créateur, seglist] (spec BCPL §8.3, globale -18), ConsoleTask/FileSystemTask/WindowPtr
; hérités du créateur, répertoire courant nul. Champs posés sous Forbid avant le premier passage du process.
CP_NAMEMAX      EQU 32
dos_fn_createproc:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,a2                   ; a2 = nom
        move.l  d2,d5                   ; d5 = pri
        move.l  d3,d6                   ; d6 = seglist
        move.l  d4,d7                   ; d7 = pile
        move.l  ($4).w,a6
        moveq   #CP_NAMEMAX+20,d0       ; nom (32) + segarray avec en-tête getvec (5 longs)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .cpr_fail
        move.l  d0,a3                   ; a3 = nom recopié
        move.l  a3,a0
        moveq   #CP_NAMEMAX-2,d1
.cpr_ncpy:
        move.b  (a2)+,(a0)+
        dbeq    d1,.cpr_ncpy
        lea     CP_NAMEMAX(a3),a4       ; a4 = en-tête getvec du segarray
        move.l  #20,(a4)                ; taille (pour un freevec éventuel)
        move.l  #3,4(a4)
        move.l  d6,16(a4)
        move.l  EB_THISTASK(a6),a0
        cmp.b   #NT_PROCESS,LN_TYPE(a0)
        bne.s   .cpr_noparent
        move.l  PR_SEGLIST(a0),d0
        lsl.l   #2,d0
        beq.s   .cpr_noparent
        move.l  d0,a1
        cmp.l   #2,(a1)
        blt.s   .cpr_noparent
        move.l  4(a1),8(a4)             ; V!1, V!2 du créateur
        move.l  8(a1),12(a4)
.cpr_noparent:
        jsr     LVO_FORBID(a6)
        move.l  a3,a0
        move.l  d6,d0
        lsl.l   #2,d0
        move.l  d0,a1
        addq.l  #4,a1                   ; entrée = premier segment
        move.l  d5,d0
        move.l  d7,d1
        jsr     proc_create             ; d0 = &pr_MsgPort | 0
        move.l  d0,d4
        beq.s   .cpr_failp
        move.l  d0,a0
        lea     -PR_MSGPORT(a0),a0      ; a0 = nouveau process
        lea     4(a4),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,PR_SEGLIST(a0)
        move.l  EB_THISTASK(a6),a1
        cmp.b   #NT_PROCESS,LN_TYPE(a1)
        bne.s   .cpr_started
        move.l  PR_CONSOLETASK(a1),PR_CONSOLETASK(a0)
        move.l  PR_FILESYSTEMTASK(a1),PR_FILESYSTEMTASK(a0)
        move.l  PR_WINDOWPTR(a1),PR_WINDOWPTR(a0)
.cpr_started:
        jsr     LVO_PERMIT(a6)
        move.l  d4,d0
        bra.s   .cpr_ret
.cpr_failp:
        jsr     LVO_PERMIT(a6)
        move.l  a3,a1
        moveq   #CP_NAMEMAX+20,d0
        jsr     LVO_FREEMEM(a6)
.cpr_fail:
        moveq   #0,d0
.cpr_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; WaitForChar(fh d1, µs d2) -> DOSFALSE : pas de caractère disponible (la console ne gère pas encore ce packet).
dos_fn_waitforchar:
        moveq   #0,d0
        rts

; ParentDir(lock d1) -> lock du parent | 0 (racine) : ACTION_PARENT au handler du lock. a6 = DosBase.
dos_fn_parentdir:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,d0
        lsl.l   #2,d0
        beq.s   .pd_zero
        move.l  d0,a0
        move.l  FL_TASK(a0),a1
        move.l  ($4).w,a6
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        moveq   #ACTION_PARENT,d0
        moveq   #0,d2
        moveq   #0,d3
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        bra.s   .pd_ret
.pd_zero:
        moveq   #0,d0
.pd_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts

; IsInteractive(fh d1) -> fh_Interactive (brut, comme la V34 : non normalisé à -1).
dos_fn_isinteractive:
        move.l  d1,d0
        lsl.l   #2,d0
        beq.s   .ii_ret
        move.l  d0,a0
        move.l  FH_INTERACTIVE(a0),d0
.ii_ret:
        rts

; Execute(cmd d1, in d2, out d3) -> DOSFALSE. Non implémenté : la V34 lance C:Run avec la commande (spec BCPL §8.2,
; globale 101) ; demande un CLI de fond (Run/createproc) que nous n'avons pas encore. IoErr = action inconnue.
dos_fn_execute:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  #ERROR_ACTION_NOT_KNOWN,PR_RESULT2(a0)
        moveq   #0,d0
        rts

; dos_resolve(a4 = nom C-string, a6 = DosBase) -> a3 = port du handler | 0, d6 = BPTR lock de départ, a4 = nom à
; transmettre au handler. Sémantique AmigaDOS : « xxx:reste » -> nœud « xxx » de la DosList (insensible à la casse) :
; assign (DLT_DIRECTORY) -> son lock + son handler, on transmet « reste » ; device/volume -> son handler, lock 0, nom
; complet (le handler ignore le préfixe et part de la racine). « :reste » -> volume du répertoire courant, racine.
; Sans ':' -> relatif à pr_CurrentDir (lock 0 = racine du handler par défaut pr_FileSystemTask, sinon DF0:).
; Préfixe inconnu -> a3 = 0 et IoErr = ERROR_DEVICE_NOT_MOUNTED. Clobbe d0-d2/a0-a1.
dos_resolve:
        movem.l d3-d4/a2,-(sp)
        move.l  a4,a0
.rs_scan:
        move.b  (a0)+,d0
        beq     .rs_rel                 ; pas de ':' -> relatif au répertoire courant
        cmp.b   #':',d0
        bne.s   .rs_scan
        move.l  a0,d3
        sub.l   a4,d3
        subq.l  #1,d3                   ; d3 = longueur du préfixe
        beq     .rs_volroot             ; « :reste »
        move.l  DL_ROOT(a6),a2
        move.l  RN_INFO(a2),d0
        lsl.l   #2,d0
        move.l  d0,a2
        move.l  DI_DEVINFO(a2),d0
.rs_node:
        lsl.l   #2,d0
        beq.s   .rs_unknown
        move.l  d0,a2                   ; a2 = nœud courant
        move.l  DN_NAME(a2),d0
        lsl.l   #2,d0
        beq.s   .rs_next
        move.l  d0,a0
        moveq   #0,d4
        move.b  (a0)+,d4                ; longueur du nom du nœud
        cmp.l   d3,d4
        bne.s   .rs_next
        move.l  a4,a1
.rs_cmp:
        move.b  (a0)+,d0
        bsr     dos_upper
        move.b  d0,d1
        move.b  (a1)+,d0
        bsr     dos_upper
        cmp.b   d0,d1
        bne.s   .rs_next
        subq.l  #1,d4
        bne.s   .rs_cmp
        cmp.l   #DLT_DIRECTORY,DN_TYPE(a2)
        bne.s   .rs_devvol
        move.l  DN_LOCK(a2),d6          ; assign : lock du répertoire assigné
        move.l  d6,d0
        lsl.l   #2,d0
        beq.s   .rs_unknown
        move.l  d0,a0
        move.l  FL_TASK(a0),a3
        lea     1(a4,d3.l),a4           ; transmet ce qui suit le ':'
        bra.s   .rs_ret
.rs_devvol:
        moveq   #0,d6
        move.l  DN_TASK(a2),a3
        move.l  a3,d0
        bne.s   .rs_ret
        tst.l   DN_TYPE(a2)             ; device sans tâche : démarre son handler (spec BCPL §13.3)
        bne.s   .rs_ret
        move.l  a4,a0                   ; nom complet (le handler peut y lire des paramètres : NEWCON:x/y/l/h/titre)
        jsr     bcpl_starthandler       ; d0 = port | 0 (Result2 posé)
        move.l  d0,a3
        move.l  DN_LOCK(a2),d6
        bra.s   .rs_ret
.rs_next:
        move.l  DN_NEXT(a2),d0
        bra.s   .rs_node
.rs_unknown:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  #ERROR_DEVICE_NOT_MOUNTED,PR_RESULT2(a0)
        sub.l   a3,a3
        bra.s   .rs_ret
.rs_volroot:
        bsr     dos_cdport
        moveq   #0,d6                   ; le handler repart de la racine (il ignore le ':')
        bra.s   .rs_ret
.rs_rel:
        bsr     dos_cdport
.rs_ret:
        movem.l (sp)+,d3-d4/a2
        rts

; dos_cdport() -> d6 = pr_CurrentDir de ThisTask, a3 = port du handler qui porte ce lock (lock 0 -> pr_FileSystemTask,
; ou le file-handler DF0: si non posé). Clobbe d0/a0.
dos_cdport:
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  PR_CURRENTDIR(a0),d6
        move.l  d6,d0
        lsl.l   #2,d0
        beq.s   .cd_default
        move.l  d0,a0
        move.l  FL_TASK(a0),a3
        rts
.cd_default:
        move.l  PR_FILESYSTEMTASK(a0),a3
        move.l  a3,d0
        bne.s   .cd_ret
        move.l  DOS_FSPORT,a3
.cd_ret:
        rts

; dos_upper(d0.b) -> d0.b en majuscule (ASCII a-z seulement).
dos_upper:
        cmp.b   #'a',d0
        blo.s   .up_ret
        cmp.b   #'z',d0
        bhi.s   .up_ret
        sub.b   #'a'-'A',d0
.up_ret:
        rts

; dos_boot_assigns(a6 = DosBase) : appelé par le CLI initial (process) une fois le disque de boot monté. Crée le nœud
; VOLUME (nom lu par Examine de la racine), l'assign SYS: (racine) et les assigns C: S: L: DEVS: LIBS: FONTS: pour
; chaque répertoire présent sur DF0:, puis pose pr_CurrentDir = racine. Sans disque lisible -> rien. Préserve tout.
dos_boot_assigns:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  a6,a5                   ; a5 = DosBase
        bsr     ba_ramnode
        lea     ba_root(pc),a0
        move.l  a0,d1
        moveq   #SHARED_LOCK,d2
        bsr     dos_fn_lock
        move.l  d0,d7                   ; d7 = lock racine (conservé par SYS:)
        beq     .ba_ret
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  FL_TASK(a0),a4          ; a4 = port du handler DF0:
        move.l  ($4).w,a6
        move.l  #FIB_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a3                   ; a3 = FIB | 0
        tst.l   d0
        beq.s   .ba_sys
        move.l  a5,a6
        move.l  d7,d1
        move.l  a3,d2
        bsr     dos_fn_examine
        tst.l   d0
        beq.s   .ba_nofib
        moveq   #DLT_VOLUME,d0
        moveq   #0,d1
        lea     FIB_FILENAME(a3),a0
        move.l  a4,a1
        bsr     ba_addnode              ; volume « <nom du disque> »
.ba_nofib:
        move.l  ($4).w,a6
        move.l  a3,a1
        move.l  #FIB_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.ba_sys:
        moveq   #DLT_DIRECTORY,d0
        move.l  d7,d1
        lea     ba_sysname(pc),a0
        move.l  a4,a1
        bsr     ba_addnode
        lea     ba_tab(pc),a2           ; paires (nom d'assign, chemin) terminées par un nom vide
.ba_loop:
        tst.b   (a2)
        beq.s   .ba_cd
        move.l  a2,a3                   ; a3 = nom d'assign
.ba_skip1:
        tst.b   (a2)+
        bne.s   .ba_skip1               ; a2 = chemin
        move.l  a5,a6
        move.l  a2,d1
        moveq   #SHARED_LOCK,d2
        bsr     dos_fn_lock
.ba_skip2:
        tst.b   (a2)+
        bne.s   .ba_skip2               ; a2 = paire suivante
        tst.l   d0
        beq.s   .ba_loop                ; répertoire absent -> pas d'assign
        move.l  d0,d1
        moveq   #DLT_DIRECTORY,d0
        move.l  a3,a0
        move.l  a4,a1
        bsr     ba_addnode
        bra.s   .ba_loop
.ba_cd:
        move.l  a5,a6                   ; répertoire courant initial = racine du disque de boot
        lea     ba_root(pc),a0
        move.l  a0,d1
        moveq   #SHARED_LOCK,d2
        bsr     dos_fn_lock
        move.l  d0,d1
        beq.s   .ba_ret
        bsr     dos_fn_currentdir
.ba_ret:
        movem.l (sp)+,d0-d7/a0-a6
        rts

; ba_ramnode(a5 = DosBase) : nœud device « RAM » (handler BCPL L:RAM-HANDLER chargé au premier accès, pile 300 longs,
; pri 0, GV neuf : spec handlers §1) inséré en tête de di_DevInfo. Le handler écrit lui-même dn_Task et crée le
; volume « RAM DISK ». Clobbe d0-d1/a0-a1.
ba_ramnode:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  #DN_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .rn_ret
        move.l  d0,a0
        lea     ba_ramhandler(pc),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_HANDLER(a0)
        move.l  #300,DN_STACKSIZE(a0)
        lea     ba_ramname(pc),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a0)
        jsr     LVO_FORBID(a6)
        move.l  DL_ROOT(a5),a1
        move.l  RN_INFO(a1),d0
        lsl.l   #2,d0
        move.l  d0,a1
        move.l  DI_DEVINFO(a1),DN_NEXT(a0)
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,DI_DEVINFO(a1)
        jsr     LVO_PERMIT(a6)
.rn_ret:
        move.l  (sp)+,a6
        rts
        cnop    0,4
ba_ramhandler:
        dc.b    13,"L:RAM-HANDLER",0
        cnop    0,4
ba_ramname:
        dc.b    3,"RAM",0
        EVEN

; ba_addnode(d0 = type, d1 = BPTR lock, a0 = nom C-string, a1 = port du handler) : alloue un nœud DosList (+ BSTR du
; nom juste après, long-aligné) et l'insère en tête de di_DevInfo sous Forbid. Clobbe d0-d2/a0-a1.
BA_NAMEMAX      EQU 31
ba_addnode:
        movem.l d3-d4/a2/a6,-(sp)
        move.l  d0,d3
        move.l  d1,d4
        move.l  a0,a2
        move.l  a1,-(sp)
        move.l  ($4).w,a6
        move.l  #DN_SIZEOF+BA_NAMEMAX+1,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a1
        tst.l   d0
        beq.s   .an_ret
        move.l  d0,a0                   ; a0 = nœud
        move.l  d3,DN_TYPE(a0)
        move.l  a1,DN_TASK(a0)
        move.l  d4,DN_LOCK(a0)
        lea     DN_SIZEOF(a0),a1        ; BSTR du nom
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a0)
        moveq   #0,d1
.an_cpy:
        move.b  (a2)+,d0
        beq.s   .an_len
        move.b  d0,1(a1,d1.l)
        addq.l  #1,d1
        cmp.l   #BA_NAMEMAX-1,d1
        bcs.s   .an_cpy
.an_len:
        move.b  d1,(a1)
        jsr     LVO_FORBID(a6)
        move.l  DL_ROOT(a5),a1
        move.l  RN_INFO(a1),d0
        lsl.l   #2,d0
        move.l  d0,a1                   ; DosInfo
        move.l  DI_DEVINFO(a1),DN_NEXT(a0)
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,DI_DEVINFO(a1)
        jsr     LVO_PERMIT(a6)
.an_ret:
        movem.l (sp)+,d3-d4/a2/a6
        rts

ba_root:
        dc.b    "DF0:",0
ba_sysname:
        dc.b    "SYS",0
ba_tab:
        dc.b    "C",0,"DF0:c",0
        dc.b    "S",0,"DF0:s",0
        dc.b    "L",0,"DF0:l",0
        dc.b    "DEVS",0,"DF0:devs",0
        dc.b    "LIBS",0,"DF0:libs",0
        dc.b    "FONTS",0,"DF0:fonts",0
        dc.b    0
        EVEN

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Pose le nom, alloue RootNode + DosInfo séparément
; (AllocMem -> long-alignés), câble dl_Root (APTR) et rn_Info (BPTR = &DosInfo>>2), stocke le scaffold DL_DISHADOW.
dos_initfunc:
        movem.l d3/a2,-(sp)         ; a2/d3 non-scratch : préservés pour MakeLibrary (AllocMem les préserve aussi)
        move.l  d0,a2               ; a2 = DosBase
        move.l  d0,DOS_DOSBASE      ; publié pour le runtime BCPL (pas de a6 = DosBase dans le code BCPL)
        lea     dos_name(pc),a0
        move.l  a0,LN_NAME(a2)      ; pose le nom (quirk V34)
        moveq   #RN_SIZEOF,d0       ; alloue RootNode
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .out                ; alloc échoue -> dl_Root reste 0 (preuve M6D échouera proprement)
        move.l  d0,DL_ROOT(a2)      ; dl_Root = RootNode (APTR, PAS BPTR)
        move.l  d0,d3               ; d3 = RootNode (APTR)
        move.l  #(RN_TASKSLOTS+1)*4,d0  ; rn_TaskArray : [taille, slots] (Run y prend un slot libre)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .out
        move.l  d0,a0
        move.l  #RN_TASKSLOTS,(a0)
        lsr.l   #2,d0
        move.l  d3,a0
        move.l  d0,RN_TASKARRAY(a0)
        moveq   #DOSINFO_SIZE,d0    ; alloue DosInfo (champs pointeurs ; verrous différés)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .out                ; DosInfo manque -> rn_Info reste 0
        move.l  d0,DL_DISHADOW(a2)  ; scaffold : &DosInfo (APTR brut, connu de la preuve)
        move.l  d3,a0               ; a0 = RootNode
        ifeq    M6D_BAD_BPTR
        lsr.l   #2,d0               ; APTR DosInfo -> BPTR (convention dos : BPTR = addr>>2)
        endc                        ; RED M6D_BAD_BPTR : stocke l'APTR brute -> round-trip <<2 faux (mismatch, pas crash)
        move.l  d0,RN_INFO(a0)      ; rn_Info = BPTR(DosInfo)
.out:
        move.l  a2,d0               ; retourne DosBase
        movem.l (sp)+,d3/a2
        rts
dos_end:
