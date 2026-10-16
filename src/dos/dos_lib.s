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
; table ABSOLUE terminée par -1. Vecteur N -> LVO -6*N. On remplit jusqu'à DateStamp (-192 = vecteur 32) ; les
; vecteurs 5..31 (-30..-186 : Open, Read, Lock... non impl.) pointent sur dos_null (dcb évite tout miscount manuel).
dos_vectors:
        dc.l    dos_open                 ; 1 : LVO -6
        dc.l    dos_close                ; 2 : LVO -12
        dc.l    dos_expunge              ; 3 : LVO -18
        dc.l    dos_null                 ; 4 : LVO -24 (réservé)
        dcb.l   27,dos_null              ; 5..31 : LVO -30..-186 (Open -30, IoErr -132, DeviceProc -174... non impl.)
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
