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
        dcb.l   9,dos_null               ; 12..20 : LVO -72..-120 (DeleteFile, Rename, Lock, Examine... non impl.)
        dc.l    dos_fn_currentdir        ; 21 : LVO -126 CurrentDir(lock d1) -> ancien lock
        dc.l    dos_fn_ioerr             ; 22 : LVO -132 IoErr() -> pr_Result2
        dcb.l   2,dos_null               ; 23..24 : LVO -138/-144 (CreateProc, Exit non impl.)
                ifeq    LOADSEG_LVO_UNWIRED
        dc.l    dos_fn_loadseg           ; 25 : LVO -150 LoadSeg(name d1) -> BPTR seglist
                endc
                ifne    LOADSEG_LVO_UNWIRED
        dc.l    dos_null                 ; RED LOADSEG_LVO_UNWIRED : LoadSeg non câblé -> jsr -150 renvoie 0
                endc
        dc.l    dos_fn_unloadseg         ; 26 : LVO -156 UnLoadSeg(seglist d1)
        dcb.l   5,dos_null               ; 27..31 : LVO -162..-186 (non impl.)
        dc.l    dos_DateStamp            ; 32 : LVO -192
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
; Portée D3c : résolution device = 1er DeviceNode de di_DevInfo (un seul handler monté = DF0:) ; nom pris tel quel
; (pas de parsing de préfixe « DFx: »). StandardPacket local à la pile de l'appelant (process).

; Open(name d1 [C-string], accessMode d2 [= code ACTION_FIND*]) -> d0 = BPTR FileHandle | 0.
dos_fn_open:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,a4                   ; a4 = nom (C-string)
        move.l  d2,d7                   ; d7 = mode (= dp_Type ACTION_FINDINPUT)
        move.l  DL_ROOT(a6),a0          ; RootNode (APTR)
        move.l  RN_INFO(a0),d0          ; BPTR DosInfo
        lsl.l   #2,d0
        move.l  d0,a0                   ; DosInfo
        move.l  DI_DEVINFO(a0),d0       ; BPTR DeviceNode (tête de liste device)
        lsl.l   #2,d0
        beq     .op_fail_early          ; aucun device monté
        move.l  d0,a0                   ; DeviceNode
        move.l  DN_TASK(a0),a3          ; a3 = port du handler (APTR)
        move.l  a3,d0
        beq     .op_fail_early          ; handler non démarré
        move.l  ($4).w,a6               ; -> SysBase pour les appels exec
        move.l  #DOS_FH_ALLOC,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .op_fail_early
        move.l  d0,a2                   ; a2 = FileHandle
        lea     FH_SIZEOF(a2),a5        ; a5 = buffer BSTR du nom (long-aligné)
        lea     1(a5),a1                ; a1 -> caractères
        moveq   #0,d3                   ; d3 = longueur
.op_ncpy:
        move.b  (a4)+,d0
        beq.s   .op_ndone
        move.b  d0,(a1)+
        addq.l  #1,d3
        cmp.l   #38,d3                  ; borne du buffer
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
        moveq   #0,d2                   ; ARG2 = lock 0 (racine)
        move.l  a5,d3
        lsr.l   #2,d3                   ; ARG3 = BPTR(nom BSTR)
        jsr     dos_sendpkt             ; d0 = dp_Res1
        lea     SP_SIZEOF(sp),sp
        cmp.l   #DOSTRUE,d0
        bne.s   .op_fail_free
        move.l  a2,d0                   ; succès -> BPTR(FileHandle)
        lsr.l   #2,d0
        bra.s   .op_ret
.op_fail_free:
        move.l  a2,a1
        move.l  #DOS_FH_ALLOC,d0
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
        move.l  a2,a1                   ; libère le FileHandle
        move.l  #DOS_FH_ALLOC,d0
        jsr     LVO_FREEMEM(a6)
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

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Pose le nom, alloue RootNode + DosInfo séparément
; (AllocMem -> long-alignés), câble dl_Root (APTR) et rn_Info (BPTR = &DosInfo>>2), stocke le scaffold DL_DISHADOW.
dos_initfunc:
        movem.l d3/a2,-(sp)         ; a2/d3 non-scratch : préservés pour MakeLibrary (AllocMem les préserve aussi)
        move.l  d0,a2               ; a2 = DosBase
        lea     dos_name(pc),a0
        move.l  a0,LN_NAME(a2)      ; pose le nom (quirk V34)
        moveq   #RN_SIZEOF,d0       ; alloue RootNode
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .out                ; alloc échoue -> dl_Root reste 0 (preuve M6D échouera proprement)
        move.l  d0,DL_ROOT(a2)      ; dl_Root = RootNode (APTR, PAS BPTR)
        move.l  d0,d3               ; d3 = RootNode (APTR)
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
