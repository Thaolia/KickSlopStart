; src/exec/expansion.s — expansion.library (autoconfig) : résident minimal faithful.
;
; Module résident de PARITÉ (pri 110, 1er après exec dans la carte). Rôle réel sur Amiga : énumération des cartes
; autoconfig (ConfigDev) + montage des DeviceNode de boot. Portée ici : la librairie s'ouvre (OpenLibrary réussit)
; et la LISTE DES ConfigDev fonctionne (AllocConfigDev / AddConfigDev / FindConfigDev / FreeConfigDev) — le cœur de
; l'autoconfig, prouvable sans matériel d'extension. Différé : ConfigBoard/ReadExpansionRom (probe matériel réel),
; MakeDosNode/AddBootNode/AddDosNode (montage de volumes), AllocBoardMem (slots).
;
; NOTE Lemmings : le bootblock fait OpenLibrary("expansion.library", 37) = version KS 2.0. Notre ROM est V34 ->
; le gate de version renvoie 0 -> le bootblock SAUTE sa branche expansion (il la tolère). Ce module ne change donc
; PAS le boot de Lemmings ; c'est de la parité honnête, pas un déblocage. Preuve : « EXPANSION OK » + gate v37.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs expansion.library + libraries/configregs.i. AUCUNE lecture ROM.

                include "exec.i"
                include "expansion.i"

                xref    newlist          ; lists.s (NEWLIST de la liste ConfigDev)

; --- ROMTag expansion.library (scanné par build_reslist) ---
                EVEN
expansion_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    expansion_romtag         ; RT_MATCHTAG = self
        dc.l    expansion_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,110  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (110 : place roadmap)
        dc.l    expansion_name           ; RT_NAME
        dc.l    expansion_name           ; RT_IDSTRING
        dc.l    expansion_inittab        ; RT_INIT -> table AUTOINIT
expansion_name:
        dc.b    "expansion.library",0
        EVEN
expansion_inittab:
        dc.l    EXPANSIONBASE_SIZE       ; dataSize
        dc.l    expansion_vectors        ; funcTable
        dc.l    expansion_datatab        ; dataTable (InitStruct)
        dc.l    expansion_initfunc       ; initFunc
; table ABSOLUE terminée par -1. Vecteur N -> LVO -6*N. Slots 1-4 = Open/Close/Expunge/Reserved (standard lib) ;
; les fonctions expansion commencent au slot 5 = -30. Impl. réelles : AddConfigDev(-30)/AllocConfigDev(-48)/
; FindConfigDev(-72)/FreeConfigDev(-84) ; le reste = exp_null (non impl. ce milestone).
expansion_vectors:
        dc.l    exp_open                 ; 1  : LVO -6
        dc.l    exp_close                ; 2  : LVO -12
        dc.l    exp_expunge              ; 3  : LVO -18
        dc.l    exp_null                 ; 4  : LVO -24 (réservé)
        dc.l    exp_addconfigdev         ; 5  : LVO -30 AddConfigDev(cd a0)
        dc.l    exp_null                 ; 6  : LVO -36 AddBootNode
        dc.l    exp_null                 ; 7  : LVO -42 AllocBoardMem
        dc.l    exp_allocconfigdev       ; 8  : LVO -48 AllocConfigDev()
        dc.l    exp_null                 ; 9  : LVO -54 AllocExpansionMem
        dc.l    exp_null                 ; 10 : LVO -60 ConfigBoard
        dc.l    exp_null                 ; 11 : LVO -66 ConfigChain
        dc.l    exp_findconfigdev        ; 12 : LVO -72 FindConfigDev(start a0, manu d0, prod d1)
        dc.l    exp_null                 ; 13 : LVO -78 FreeBoardMem
        dc.l    exp_freeconfigdev        ; 14 : LVO -84 FreeConfigDev(cd a0)
        dc.l    exp_null                 ; 15 : LVO -90 FreeExpansionMem
        dc.l    exp_null                 ; 16 : LVO -96 ReadExpansionByte
        dc.l    exp_null                 ; 17 : LVO -102 ReadExpansionRom
        dc.l    exp_null                 ; 18 : LVO -108 RemConfigDev
        dc.l    exp_null                 ; 19 : LVO -114 WriteExpansionByte
        dc.l    exp_null                 ; 20 : LVO -120 ObtainConfigBinding (pas de concurrence à arbitrer)
        dc.l    exp_null                 ; 21 : LVO -126 ReleaseConfigBinding
        dc.l    exp_setbinding           ; 22 : LVO -132 SetCurrentBinding(binding a0, taille d0)
        dc.l    exp_getbinding           ; 23 : LVO -138 GetCurrentBinding(binding a0, taille d0) -> taille
        dc.l    exp_null                 ; 24 : LVO -144 MakeDosNode (échec : 0)
        dc.l    exp_null                 ; 25 : LVO -150 AddDosNode (échec : 0)
        dc.l    -1
expansion_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)  ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

exp_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0                ; retourne la base (convention OpenLibrary)
        rts
exp_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
exp_expunge:
        moveq   #0,d0               ; base résidente : pas d'expunge
        rts
; SetCurrentBinding(binding a0, taille d0) / GetCurrentBinding(binding a0, taille d0) -> d0 = taille de la structure :
; copie min(taille, CB_SIZEOF) octets vers / depuis la CurrentBinding de la base (utilisée par BindDrivers et les
; drivers de SYS:Expansion qu'il lance).
exp_setbinding:
        lea     EB_BINDING(a6),a1    ; source = argument (a0), destination = base (a1)
        bra.s   exp_cpbinding
exp_getbinding:
        lea     EB_BINDING(a6),a1
        exg     a0,a1                ; source = base (a0), destination = argument (a1)
exp_cpbinding:
        cmp.l   #CB_SIZEOF,d0
        bls.s   .cb_go
        moveq   #CB_SIZEOF,d0
.cb_go:
        subq.l  #1,d0
        bmi.s   .cb_ret
.cb_lp:
        move.b  (a0)+,(a1)+
        dbra    d0,.cb_lp
.cb_ret:
        moveq   #CB_SIZEOF,d0
        rts

exp_null:
        moveq   #0,d0
        rts

; AddConfigDev(cd a0) : ajoute le ConfigDev en queue de EB_CONFIGLIST. a6 = ExpansionBase. Clobbe a0/a1 + d0/d1.
exp_addconfigdev:
                ifne    EXP_NO_ENQUEUE
        rts                         ; RED EXP_NO_ENQUEUE : n'ajoute rien -> FindConfigDev échouera
                endc
        move.l  a6,-(sp)            ; sauve ExpansionBase
        move.l  a0,a1               ; a1 = cd (nœud à ajouter)
        lea     EB_CONFIGLIST(a6),a0 ; a0 = liste
        move.l  ($4).w,a6           ; SysBase pour AddTail
        jsr     LVO_ADDTAIL(a6)
        move.l  (sp)+,a6
        rts

; AllocConfigDev() -> d0 = ConfigDev* | 0 (CLEAR). a6 = ExpansionBase (bascule SysBase pour AllocMem).
exp_allocconfigdev:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  #CD_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        rts

; FreeConfigDev(cd a0). a6 = ExpansionBase. (Ne retire PAS de la liste : l'appelant fait Remove avant, comme AmigaOS.)
exp_freeconfigdev:
        move.l  a6,-(sp)
        move.l  a0,a1               ; a1 = cd
        move.l  #CD_SIZEOF,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
        rts

; FindConfigDev(oldConfigDev a0, manufacturer d0, product d1) -> d0 = ConfigDev* | 0. a6 = ExpansionBase.
; oldConfigDev=0 -> cherche depuis la tête ; sinon depuis oldConfigDev->Succ. manufacturer/product = -1 -> wildcard.
; Parcourt EB_CONFIGLIST et compare er_Manufacturer (UWORD) + er_Product (UBYTE). Préserve d2/d3/a2.
exp_findconfigdev:
        movem.l d2/d3/a2,-(sp)
        move.l  d0,d2               ; d2 = manufacturer (test -1 en long + match en word)
        move.l  d1,d3               ; d3 = product (test -1 en long + match en octet)
        move.l  a0,d0
        bne.s   .fcd_fromsucc
        lea     EB_CONFIGLIST(a6),a0
        move.l  (a0),a2             ; a2 = lh_Head
        bra.s   .fcd_loop
.fcd_fromsucc:
        move.l  a0,a2
        move.l  (a2),a2             ; a2 = oldConfigDev->Succ
.fcd_loop:
        move.l  (a2),d0             ; d0 = a2->Succ ; 0 => a2 = sentinelle de queue -> fin
        beq.s   .fcd_none
        ; match manufacturer ?
        cmp.l   #-1,d2
        beq.s   .fcd_chkprod        ; wildcard
        move.w  ER_MANUFACTURER(a2),d0
        cmp.w   d2,d0
        bne.s   .fcd_next
.fcd_chkprod:
        cmp.l   #-1,d3
        beq.s   .fcd_hit            ; wildcard
        moveq   #0,d0
        move.b  ER_PRODUCT(a2),d0
        cmp.b   d3,d0
        bne.s   .fcd_next
.fcd_hit:
        move.l  a2,d0               ; trouvé
        bra.s   .fcd_ret
.fcd_next:
        move.l  (a2),a2             ; a2 = Succ
        bra.s   .fcd_loop
.fcd_none:
        moveq   #0,d0
.fcd_ret:
        movem.l (sp)+,d2/d3/a2
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0=base. Pose le nom (quirk V34), clear eb_Flags, NEWLIST la liste.
expansion_initfunc:
        move.l  d0,a1
        lea     expansion_name(pc),a0
        move.l  a0,LN_NAME(a1)
        clr.b   EB_FLAGS(a1)
        move.l  d0,-(sp)            ; sauve la base (newlist clobbe a0/d0)
        lea     EB_CONFIGLIST(a1),a1
        jsr     newlist
        move.l  (sp)+,d0
        rts

        EVEN
expansion_end:
