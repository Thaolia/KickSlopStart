; src/exec/expansion.s — expansion.library 34 : autoconfig Zorro II.
;
; Résident pri 110 (1er après exec, la slow RAM est déjà dans la MemList). Son init libère l'espace mémoire Zorro II
; ($200000-$9FFFFF) et l'espace E/S ($E90000-$EFFFFF) dans la table des slots de 64 Ko, puis configure la chaîne en
; $E80000 (ConfigChain) : chaque carte lue (ReadExpansionRom) reçoit un bloc de slots (premier ajusté, E/S d'abord
; pour les cartes de moins de 8 slots), son adresse lui est écrite, sa RAM devient un MemHeader « expansion ram »
; (MEMF_FAST|MEMF_PUBLIC, pri 0) ou sa DiagArea est copiée et exécutée ; sans place, la carte est mise en sommeil.
; Les ConfigDev (y compris ceux des cartes en sommeil) sont chaînés dans eb_BoardList dans l'ordre de la chaîne.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs expansion.library, NDK configregs/configvars/expansionbase, spec
; docs/analysis/autoconfig-v34.md. AUCUNE lecture ROM.

                include "exec.i"
                include "expansion.i"
                include "dos.i"
                include "dospkt.i"

                xref    newlist          ; lists.s

; --- ROMTag expansion.library (scanné par build_reslist) ---
                EVEN
expansion_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    expansion_romtag         ; RT_MATCHTAG = self
        dc.l    expansion_end            ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_LIBRARY,110  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    expansion_name           ; RT_NAME
        dc.l    expansion_name           ; RT_IDSTRING
        dc.l    expansion_inittab        ; RT_INIT -> table AUTOINIT
expansion_name:
        dc.b    "expansion.library",0
exp_ramname:
        dc.b    "expansion ram",0
exp_dosname:
        dc.b    "dos.library",0
        EVEN
expansion_inittab:
        dc.l    EXPANSIONBASE_SIZE       ; dataSize
        dc.l    expansion_vectors        ; funcTable
        dc.l    expansion_datatab        ; dataTable (InitStruct)
        dc.l    expansion_initfunc       ; initFunc
; table ABSOLUE terminée par -1. Vecteur N -> LVO -6*N.
expansion_vectors:
        dc.l    exp_open                 ; 1  : LVO -6
        dc.l    exp_close                ; 2  : LVO -12
        dc.l    exp_expunge              ; 3  : LVO -18
        dc.l    exp_null                 ; 4  : LVO -24 (réservé)
        dc.l    exp_addconfigdev         ; 5  : LVO -30 AddConfigDev(cd a0)
        dc.l    exp_addram               ; 6  : LVO -36 (privé) AddMemList « expansion ram »(taille d0, attr d1, base a0)
        dc.l    exp_allocboardmem        ; 7  : LVO -42 AllocBoardMem(slotSpec d0)
        dc.l    exp_allocconfigdev       ; 8  : LVO -48 AllocConfigDev()
        dc.l    exp_allocexpmem          ; 9  : LVO -54 AllocExpansionMem(numSlots d0, slotDépart d1)
        dc.l    exp_configboard          ; 10 : LVO -60 ConfigBoard(board a0, cd a1)
        dc.l    exp_configchain          ; 11 : LVO -66 ConfigChain(baseAddr a0)
        dc.l    exp_findconfigdev        ; 12 : LVO -72 FindConfigDev(old a0, manu d0, prod d1)
        dc.l    exp_freeboardmem         ; 13 : LVO -78 FreeBoardMem(startSlot d0, slotSpec d1)
        dc.l    exp_freeconfigdev        ; 14 : LVO -84 FreeConfigDev(cd a0)
        dc.l    exp_freeexpmem           ; 15 : LVO -90 FreeExpansionMem(startSlot d0, numSlots d1)
        dc.l    exp_readbyte             ; 16 : LVO -96 ReadExpansionByte(board a0, offset d0)
        dc.l    exp_readrom              ; 17 : LVO -102 ReadExpansionRom(board a0, cd a1)
        dc.l    exp_remconfigdev         ; 18 : LVO -108 RemConfigDev(cd a0)
        dc.l    exp_writebyte            ; 19 : LVO -114 WriteExpansionByte(board a0, offset d0, octet d1)
        dc.l    exp_obtainbinding        ; 20 : LVO -120 ObtainConfigBinding()
        dc.l    exp_releasebinding       ; 21 : LVO -126 ReleaseConfigBinding()
        dc.l    exp_setbinding           ; 22 : LVO -132 SetCurrentBinding(binding a0, taille d0)
        dc.l    exp_getbinding           ; 23 : LVO -138 GetCurrentBinding(binding a0, taille d0) -> 16
        dc.l    exp_makedosnode          ; 24 : LVO -144 MakeDosNode(parmPacket a0)
        dc.l    exp_adddosnode           ; 25 : LVO -150 AddDosNode(bootPri d0, flags d1, dosNode a0)
        dc.l    -1
expansion_datatab:
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8)  ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN
; er_Type & 7 -> nombre de slots de 64 Ko, puis slot de départ de la recherche générale (8 Mo et 4 Mo : $20).
sz_slots:
        dc.b    $80,$01,$02,$04,$08,$10,$20,$40
        dc.b    $20,$00,$00,$00,$00,$00,$00,$20

exp_open:
        addq.w  #1,LIB_OPENCNT(a6)
        move.l  a6,d0
        rts
exp_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
exp_expunge:
        moveq   #0,d0               ; base résidente : pas d'expunge
        rts
exp_null:
        moveq   #0,d0
        rts

; SetCurrentBinding(binding a0, taille d0) : min(taille, 16) octets vers la base, complétés à 16 par des 0.
; GetCurrentBinding(binding a0, taille d0) -> 16 : min(taille, 16) octets vers le tampon, puis des 0 jusqu'à 16 octets
; dans le tampon (comme en 1.3 : le tampon doit faire 16 octets).
exp_setbinding:
        lea     EB_BINDING(a6),a1    ; source = argument (a0), destination = base (a1)
        bra.s   exp_cpbinding
exp_getbinding:
        lea     EB_BINDING(a6),a1
        exg     a0,a1                ; source = base (a0), destination = argument (a1)
exp_cpbinding:
        move.l  d2,-(sp)
        moveq   #CB_SIZEOF,d1
        cmp.l   d1,d0
        bls.s   .cb_n
        move.l  d1,d0
.cb_n:
        sub.l   d0,d1                ; d1 = octets à mettre à zéro
        move.l  d0,d2
        bra.s   .cb_cpe
.cb_cp:
        move.b  (a0)+,(a1)+
.cb_cpe:
        dbra    d2,.cb_cp
        bra.s   .cb_ze
.cb_z:
        clr.b   (a1)+
.cb_ze:
        dbra    d1,.cb_z
        move.l  (sp)+,d2
        moveq   #CB_SIZEOF,d0
        rts

exp_obtainbinding:
        lea     EB_BINDSEM(a6),a0
        move.l  a6,-(sp)
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  (sp)+,a6
        rts
exp_releasebinding:
        lea     EB_BINDSEM(a6),a0
        move.l  a6,-(sp)
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_RELEASESEMAPHORE(a6)
        move.l  (sp)+,a6
        rts

; AddConfigDev(cd a0) : en queue de eb_BoardList, sous Forbid.
exp_addconfigdev:
                ifne    EXP_NO_ENQUEUE
        rts                         ; RED EXP_NO_ENQUEUE : n'ajoute rien -> FindConfigDev échouera
                endc
        move.l  a6,-(sp)
        move.l  a0,a1
        lea     EB_BOARDLIST(a6),a0
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_FORBID(a6)
        jsr     LVO_ADDTAIL(a6)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts
; RemConfigDev(cd a0) : retire le ConfigDev de sa liste, sous Forbid.
exp_remconfigdev:
        move.l  a6,-(sp)
        move.l  a0,a1
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_FORBID(a6)
        jsr     LVO_REMOVE(a6)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

; AllocConfigDev() -> d0 = ConfigDev* | 0 (mis à zéro).
exp_allocconfigdev:
        move.l  a6,-(sp)
        move.l  EB_EXECBASE(a6),a6
        moveq   #CD_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a6
        rts
; FreeConfigDev(cd a0) : ne le retire pas de la liste (l'appelant fait RemConfigDev avant).
exp_freeconfigdev:
        move.l  a6,-(sp)
        move.l  a0,a1
        moveq   #CD_SIZEOF,d0
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
        rts

; FindConfigDev(oldConfigDev a0, manufacturer d0, product d1) -> d0 = ConfigDev* | 0. old = 0 : depuis la tête, sinon
; depuis le suivant de old. -1 (long) = joker ; sinon comparaison sur le mot er_Manufacturer / l'octet er_Product.
exp_findconfigdev:
        movem.l d2/d3/a2,-(sp)
        move.l  d0,d2
        move.l  d1,d3
        move.l  a0,d0
        bne.s   .fcd_fromsucc
        move.l  EB_BOARDLIST(a6),a2  ; lh_Head
        bra.s   .fcd_loop
.fcd_fromsucc:
        move.l  (a0),a2
.fcd_loop:
        move.l  (a2),d0              ; Succ nul : a2 = sentinelle de queue -> fin
        beq.s   .fcd_none
        cmp.l   #-1,d2
        beq.s   .fcd_chkprod
        cmp.w   ER_MANUFACTURER(a2),d2
        bne.s   .fcd_next
.fcd_chkprod:
        cmp.l   #-1,d3
        beq.s   .fcd_hit
        cmp.b   ER_PRODUCT(a2),d3
        bne.s   .fcd_next
.fcd_hit:
        move.l  a2,d0
        bra.s   .fcd_ret
.fcd_next:
        move.l  (a2),a2
        bra.s   .fcd_loop
.fcd_none:
        moveq   #0,d0
.fcd_ret:
        movem.l (sp)+,d2/d3/a2
        rts

; ReadExpansionByte(board a0, offset d0) -> d0 : l'octet logique n porte son quartet haut dans le quartet haut de
; board+4n, son quartet bas dans le quartet haut de board+4n+2. Sans inversion.
exp_readbyte:
        and.l   #$FF,d0
        lsl.w   #2,d0
        move.b  0(a0,d0.l),d1
        and.b   #$F0,d1
        move.b  2(a0,d0.l),d0
        lsr.b   #4,d0
        or.b    d1,d0
        and.l   #$FF,d0
        rts
; WriteExpansionByte(board a0, offset d0, octet d1) -> 0 : quartet bas en board+4n+2, puis quartet haut en board+4n
; (en dernier : c'est l'écriture du quartet haut du registre d'adresse qui fait prendre son adresse à la carte).
exp_writebyte:
        and.l   #$FF,d0
        lsl.w   #2,d0
        move.l  d1,a1
        lsl.b   #4,d1
        move.b  d1,2(a0,d0.l)
        move.l  a1,d1
        move.b  d1,0(a0,d0.l)
        moveq   #0,d0
        rts

; ReadExpansionRom(board a0, cd a1) -> d0 = 0 | EE_NOMEMORY (pas de carte, ROM invalide ou instable). 17 octets
; logiques rangés à partir de cd_Rom : er_Type tel quel, les suivants inversés. Valide si er_Flags & $3F = 0,
; er_Reserved03 = 0, er_Manufacturer ni 0 ni $FFFF, et si 11 relectures des 16 premiers octets concordent.
exp_readrom:
        movem.l d2-d4/a2-a3,-(sp)
        move.l  a0,a2
        lea     CD_ROM(a1),a3
        moveq   #0,d2
.rr_lp:
        bsr.s   rr_byte
        move.b  d0,0(a3,d2.w)
        addq.w  #1,d2
        cmp.w   #ER_ROMBYTES,d2
        blo.s   .rr_lp
        moveq   #EE_NOMEMORY,d4
        moveq   #$3F,d0
        and.b   ER_FLAGS-CD_ROM(a3),d0
        bne.s   .rr_ret
        tst.b   ER_RESERVED03-CD_ROM(a3)
        bne.s   .rr_ret
        move.w  ER_MANUFACTURER-CD_ROM(a3),d0
        beq.s   .rr_ret
        cmp.w   #$FFFF,d0
        beq.s   .rr_ret
        moveq   #ER_REREADS-1,d3
.rr_again:
        moveq   #0,d2
.rr_cmp:
        bsr.s   rr_byte
        cmp.b   0(a3,d2.w),d0
        bne.s   .rr_ret
        addq.w  #1,d2
        cmp.w   #16,d2
        blo.s   .rr_cmp
        dbra    d3,.rr_again
        moveq   #0,d4
.rr_ret:
        move.l  d4,d0
        movem.l (sp)+,d2-d4/a2-a3
        rts
; rr_byte(a2 = carte, d2.w = index) -> d0.b = octet logique, inversé sauf l'index 0. Clobbe d0/d1/a0.
rr_byte:
        move.l  a2,a0
        moveq   #0,d0
        move.w  d2,d0
        bsr     exp_readbyte
        tst.w   d2
        beq.s   .rb_r
        not.b   d0
.rb_r:
        rts

; AllocExpansionMem(numSlots d0, slotDépart d1) -> d0 = premier slot | -1. Moins de 8 slots : essai dans l'espace E/S
; [$E8, $F0) par pas de numSlots ; puis dans [départ, 256) par pas de numSlots. Premier bloc entièrement libre : pris.
exp_allocexpmem:
        movem.l d2/d4,-(sp)
        move.l  d0,d2
        beq.s   .ae_fail
        add.l   d1,d0
        cmp.l   #256,d0
        bhi.s   .ae_fail
        move.l  d1,-(sp)
        cmp.l   #7,d2
        bhi.s   .ae_gen
        move.l  #E_IOSLOT_LO,d4
        move.l  #E_IOSLOT_HI,d1
        bsr.s   ae_scan
        tst.l   d0
        bpl.s   .ae_got
.ae_gen:
        move.l  (sp),d4
        move.l  #256,d1
        bsr.s   ae_scan
.ae_got:
        addq.l  #4,sp
        bra.s   .ae_ret
.ae_fail:
        moveq   #-1,d0
.ae_ret:
        movem.l (sp)+,d2/d4
        rts
; ae_scan(d2 = slots, d4 = premier candidat, d1 = fin exclusive) -> d0 = slot | -1. Clobbe d0/d4/a0.
ae_scan:
        move.l  d4,d0
        add.l   d2,d0
        cmp.l   d1,d0
        bhi.s   .sc_none
        lea     EB_ALLOCTABLE(a6,d4.l),a0
        move.l  d2,d0
        subq.l  #1,d0
.sc_chk:
        tst.b   (a0)+
        beq.s   .sc_next
        dbra    d0,.sc_chk
        lea     EB_ALLOCTABLE(a6,d4.l),a0
        move.l  d2,d0
        subq.l  #1,d0
.sc_mark:
        clr.b   (a0)+
        dbra    d0,.sc_mark
        move.l  d4,d0
        rts
.sc_next:
        add.l   d2,d4
        bra.s   ae_scan
.sc_none:
        moveq   #-1,d0
        rts

; FreeExpansionMem(startSlot d0, numSlots d1) : slots rendus libres. Hors table, ou slot déjà libre : Alert
; AN_BADEXPFREE et arrêt (les slots précédents restent libérés).
exp_freeexpmem:
        move.l  d0,a0
        add.l   d1,d0
        cmp.l   #256,d0
        bhi.s   .fe_bad
        add.l   a6,a0
        lea     EB_ALLOCTABLE(a0),a0
        bra.s   .fe_e
.fe_lp:
        tst.b   (a0)
        bne.s   .fe_bad
        st      (a0)+
.fe_e:
        subq.l  #1,d1
        bpl.s   .fe_lp
        rts
.fe_bad:
        movem.l d7/a6,-(sp)
        move.l  #AN_BADEXPFREE,d7
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_ALERT(a6)
        movem.l (sp)+,d7/a6
        rts

; AllocBoardMem(slotSpec d0) -> d0 = slot | -1 ; FreeBoardMem(startSlot d0, slotSpec d1). slotSpec = er_Type & 7.
exp_allocboardmem:
        and.l   #7,d0
        lea     sz_slots(pc),a0
        moveq   #0,d1
        move.b  8(a0,d0.w),d1
        move.b  0(a0,d0.w),d0
        and.l   #$FF,d0
        bra     exp_allocexpmem
exp_freeboardmem:
        and.l   #7,d1
        lea     sz_slots(pc),a0
        move.b  0(a0,d1.w),d1
        and.l   #$FF,d1
        bra.s   exp_freeexpmem

; ConfigBoard(board a0, cd a1) -> d0 = 0 | EE_NOEXPANSION. Chaîne bouchée (EBB_CLOGGED) : rien. Place trouvée : champs
; du ConfigDev, CDF_CONFIGME, adresse écrite à la carte, puis sa RAM ajoutée (ERTF_MEMLIST) ou sa DiagArea traitée
; (ERTF_DIAGVALID). Sans place : carte mise en sommeil (CDF_SHUTUP, EBB_SHORTMEM) ; une carte qui refuse le sommeil
; (ERFF_NOSHUTUP) reste en $E80000 et bouche la chaîne (EBB_CLOGGED, slot -1) — sans post-configuration ici : en 1.3
; elle tournerait sur l'adresse -1, ce qui ne peut que corrompre la mémoire.
exp_configboard:
        movem.l d2/a2-a3,-(sp)
        move.l  a0,a2
        move.l  a1,a3
        moveq   #0,d0
        btst    #EBB_CLOGGED,EB_FLAGS(a6)
        bne.s   .cb_ret
        moveq   #7,d2
        and.b   ER_TYPE(a3),d2
        move.l  d2,d0
        bsr.s   exp_allocboardmem
        tst.l   d0
        bmi.s   .cb_full
        bsr.s   cb_fill
        bset    #CDB_CONFIGME,CD_FLAGS(a3)
        move.l  d0,d1
        move.l  a2,a0
        moveq   #EC_BASEADDR,d0
        bsr     exp_writebyte
        bsr.s   cb_post
        moveq   #0,d0
        bra.s   .cb_ret
.cb_full:
        btst    #ERFB_NOSHUTUP,ER_FLAGS(a3)
        bne.s   .cb_clog
        move.l  a2,a0
        moveq   #EC_SHUTUP,d0
        moveq   #0,d1
        bsr     exp_writebyte
        bset    #CDB_SHUTUP,CD_FLAGS(a3)
        bset    #EBB_SHORTMEM,EB_FLAGS(a6)
        moveq   #EE_NOEXPANSION,d0
        bra.s   .cb_ret
.cb_clog:
        bset    #EBB_CLOGGED,EB_FLAGS(a6)
        bsr.s   cb_fill              ; d0 = -1
        move.l  a2,a0
        moveq   #EC_BASEADDR,d0
        move.l  #E_IOSLOT_LO,d1
        bsr     exp_writebyte
.cb_ret:
        movem.l (sp)+,d2/a2-a3
        rts
; cb_fill(d0 = slot, d2 = slotSpec, a3 = cd) : cd_SlotAddr/BoardAddr/SlotSize/BoardSize. Préserve d0.
cb_fill:
        move.w  d0,CD_SLOTADDR(a3)
        move.l  d0,d1
        swap    d1
        clr.w   d1
        move.l  d1,CD_BOARDADDR(a3)
        lea     sz_slots(pc),a0
        moveq   #0,d1
        move.b  0(a0,d2.w),d1
        move.w  d1,CD_SLOTSIZE(a3)
        swap    d1
        move.l  d1,CD_BOARDSIZE(a3)
        rts
; cb_post(a3 = cd configuré, a6 = ExpansionBase) : RAM de la carte ajoutée, ou DiagArea (carte sans RAM).
cb_post:
        btst    #ERTB_MEMLIST,ER_TYPE(a3)
        beq.s   .cp_diag
        move.l  CD_BOARDSIZE(a3),d0
        moveq   #MEMF_PUBLIC|MEMF_FAST,d1
        move.l  CD_BOARDADDR(a3),a0
        bra.s   exp_addram
.cp_diag:
        btst    #ERTB_DIAGVALID,ER_TYPE(a3)
        bne.s   exp_diag
        rts

; (LVO -36, privé) (taille d0, attributs d1, base a0) : AddMemList(taille, attributs, pri 0, base, « expansion ram »).
exp_addram:
        movem.l d2/a6,-(sp)
        moveq   #0,d2
        lea     exp_ramname(pc),a1
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_ADDMEMLIST(a6)
        movem.l (sp)+,d2/a6
        rts

; exp_diag(a3 = cd configuré, a6 = ExpansionBase) : DiagArea en cd_BoardAddr + er_InitDiagVec, prise en compte si
; (da_Config & $30) = DAC_CONFIGTIME et la largeur de bus est connue ; copiée (da_Size octets, selon la largeur) dans
; un AllocMem(da_Size, 0) rangé dans er_Reserved0c ; DiagPoint (s'il existe) appelé avec A0 = carte, A2 = copie,
; A3 = ConfigDev, A5 = ExpansionBase, A6 = ExecBase ; un retour 0 libère la copie (er_Reserved0c = 0).
exp_diag:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a6,a5
        moveq   #0,d0
        move.w  ER_INITDIAGVEC(a3),d0
        beq     .dg_ret
        move.l  CD_BOARDADDR(a3),a4
        add.l   d0,a4                ; a4 = DiagArea dans la carte
        move.b  DA_CONFIG(a4),d4
        moveq   #DAC_BOOTTIME,d0
        and.b   d4,d0
        cmp.b   #DAC_CONFIGTIME,d0
        bne     .dg_ret
        and.b   #DAC_BUSWIDTH,d4
        cmp.b   #DAC_BUSWIDTH,d4
        beq.s   .dg_ret
        lea     -DA_HDRSIZE(sp),sp   ; en-tête recopié selon la largeur
        move.l  a4,a0
        move.l  sp,a1
        moveq   #DA_HDRSIZE,d0
        bsr.s   dg_copy
        moveq   #0,d5
        move.w  DA_SIZE(sp),d5
        moveq   #0,d6
        move.w  DA_DIAGPOINT(sp),d6
        lea     DA_HDRSIZE(sp),sp
        tst.l   d5
        beq.s   .dg_ret
        move.l  d5,d0
        moveq   #0,d1
        move.l  EB_EXECBASE(a5),a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .dg_ret
        move.l  d0,a2
        move.l  a4,a0
        move.l  a2,a1
        move.l  d5,d0
        bsr.s   dg_copy
        move.l  a2,ER_RESERVED0C(a3)
        tst.l   d6
        beq.s   .dg_ret
        lea     0(a2,d6.l),a1
        move.l  CD_BOARDADDR(a3),a0
        movem.l d5/a2-a3/a5,-(sp)    ; le code de la carte peut tout écraser
        move.l  EB_EXECBASE(a5),a6
        jsr     (a1)
        movem.l (sp)+,d5/a2-a3/a5
        tst.l   d0
        bne.s   .dg_ret
        move.l  a2,a1
        move.l  d5,d0
        move.l  EB_EXECBASE(a5),a6
        jsr     LVO_FREEMEM(a6)
        clr.l   ER_RESERVED0C(a3)
.dg_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts
; dg_copy(a0 = DiagArea dans la carte, a1 = destination, d0 = octets, d4 = largeur) : WORDWIDE contigu ; BYTEWIDE un
; octet sur deux ; NIBBLEWIDE octet = quartets hauts de +0 et +2, pas de 4. a5 = ExpansionBase. Clobbe d0/d1/d7/a0/a1.
dg_copy:
        cmp.b   #DAC_WORDWIDE,d4
        beq.s   .dc_word
        subq.l  #1,d0
        bmi.s   .dc_ret
        cmp.b   #DAC_BYTEWIDE,d4
        beq.s   .dc_byte
.dc_nib:
        move.b  (a0),d1
        and.b   #$F0,d1
        move.b  2(a0),d7
        lsr.b   #4,d7
        or.b    d7,d1
        move.b  d1,(a1)+
        addq.l  #4,a0
        dbra    d0,.dc_nib
        rts
.dc_byte:
        move.b  (a0),(a1)+
        addq.l  #2,a0
        dbra    d0,.dc_byte
.dc_ret:
        rts
.dc_word:
        move.l  a6,-(sp)
        move.l  EB_EXECBASE(a5),a6
        jsr     LVO_COPYMEM(a6)
        move.l  (sp)+,a6
        rts

; ConfigChain(baseAddr a0) -> d0 = 0 | EE_NOMEMORY (plus de mémoire pour un ConfigDev). Tant qu'une carte valide
; répond en baseAddr : ConfigBoard ; configurée ou mise en sommeil -> AddConfigDev ; sinon fin de chaîne.
exp_configchain:
        movem.l a2-a3,-(sp)
        move.l  a0,a2
.cc_lp:
        moveq   #0,d0
        btst    #EBB_CLOGGED,EB_FLAGS(a6)
        bne.s   .cc_ret
        bsr     exp_allocconfigdev
        tst.l   d0
        beq.s   .cc_nomem
        move.l  d0,a3
        move.l  a2,a0
        move.l  a3,a1
        bsr     exp_readrom
        tst.l   d0
        bne.s   .cc_end
        move.l  a2,a0
        move.l  a3,a1
        bsr     exp_configboard
        tst.l   d0
        beq.s   .cc_add
        cmp.l   #EE_NOEXPANSION,d0
        bne.s   .cc_end
.cc_add:
        move.l  a3,a0
        bsr     exp_addconfigdev
        bra.s   .cc_lp
.cc_end:
        move.l  a3,a0
        bsr     exp_freeconfigdev
        moveq   #0,d0
        bra.s   .cc_ret
.cc_nomem:
        moveq   #EE_NOMEMORY,d0
.cc_ret:
        movem.l (sp)+,a2-a3
        rts

; MakeDosNode(parmPacket a0) -> d0 = DeviceNode | 0. parmPacket : nom DOS (C), nom du device exec (C), unité, drapeaux
; d'OpenDevice, puis l'environnement (de_TableSize en tête). Cinq blocs PUBLIC|CLEAR (AllocEntry) : DeviceNode,
; FileSysStartupMsg, copie de l'environnement ((de_TableSize + 1) longs), BSTR du nom DOS, BSTR du nom du device.
; dn_StackSize = 600, dn_Priority = 10.
MD_ML           EQU 0                ; MemList modèle sur la pile (5 entrées)
MD_SIZE         EQU ML_ME+5*8
exp_makedosnode:
        movem.l d2-d3/a2-a4/a6,-(sp)
        lea     -MD_SIZE(sp),sp
        move.l  a0,a2
        move.w  #5,ML_NUMENTRIES(sp)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        lea     ML_ME(sp),a0
        move.l  d1,(a0)+
        move.l  #DN_SIZEOF,(a0)+
        move.l  d1,(a0)+
        move.l  #FSSM_SIZEOF,(a0)+
        move.l  d1,(a0)+
        move.l  16(a2),d0            ; de_TableSize
        addq.l  #1,d0
        lsl.l   #2,d0
        move.l  d0,d3                ; d3 = octets d'environnement
        move.l  d0,(a0)+
        move.l  d1,(a0)+
        move.l  (a2),a1
        bsr     md_bstrsize
        move.l  d0,(a0)+
        move.l  d1,(a0)+
        move.l  4(a2),a1
        bsr     md_bstrsize
        move.l  d0,(a0)+
        move.l  sp,a0
        move.l  EB_EXECBASE(a6),a6
        jsr     LVO_ALLOCENTRY(a6)
        tst.l   d0
        bmi.s   .md_fail
        move.l  d0,a4
        lea     ML_ME(a4),a4         ; a4 -> me_Addr des 5 blocs
        move.l  (a4),a3              ; a3 = DeviceNode
        move.l  #600,DN_STACKSIZE(a3)
        move.l  #10,DN_PRIORITY(a3)
        move.l  8(a4),a1             ; FileSysStartupMsg
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,DN_STARTUP(a3)
        move.l  8(a2),FSSM_UNIT(a1)
        move.l  12(a2),FSSM_FLAGS(a1)
        move.l  16(a4),d0            ; environnement
        move.l  d0,d2
        lsr.l   #2,d0
        move.l  d0,FSSM_ENVIRON(a1)
        move.l  32(a4),d0            ; BSTR du nom du device
        move.l  d0,a0
        lsr.l   #2,d0
        move.l  d0,FSSM_DEVICE(a1)
        move.l  4(a2),a1
        bsr.s   md_bstr
        move.l  24(a4),d0            ; BSTR du nom DOS
        move.l  d0,a0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a3)
        move.l  (a2),a1
        bsr.s   md_bstr
        lea     16(a2),a0
        move.l  d2,a1
        move.l  d3,d0
        jsr     LVO_COPYMEM(a6)
        move.l  a3,d0
        bra.s   .md_ret
.md_fail:
        moveq   #0,d0
.md_ret:
        lea     MD_SIZE(sp),sp
        movem.l (sp)+,d2-d3/a2-a4/a6
        rts
; md_bstrsize(a1 = chaîne C) -> d0 = longueur + 2 (octet de longueur, caractères, NUL). Préserve a0/d1.
md_bstrsize:
        moveq   #2,d0
.bs_lp:
        tst.b   (a1)+
        beq.s   .bs_r
        addq.l  #1,d0
        bra.s   .bs_lp
.bs_r:
        rts
; md_bstr(a0 = destination, a1 = chaîne C) : BSTR (octet de longueur puis caractères ; bloc déjà à zéro).
md_bstr:
        move.l  a0,d1
        addq.l  #1,a0
.mb_lp:
        move.b  (a1)+,(a0)+
        bne.s   .mb_lp
        sub.l   d1,a0
        subq.l  #2,a0
        move.l  d1,a1
        move.l  a0,d1
        move.b  d1,(a1)
        rts

; AddDosNode(bootPri d0, flags d1, dosNode a0) -> d0 = 1 | 0. dos.library présente : le DeviceNode entre dans la liste
; des devices DOS (DosInfo->di_DevInfo, sous Forbid). Sinon : BootNode (ln_Pri = bootPri, bn_Flags = flags,
; bn_DeviceNode, ln_Name = nom du DeviceNode) inséré par priorité dans eb_MountList, monté plus tard.
exp_adddosnode:
        movem.l d2-d3/a2-a3/a6,-(sp)
        move.l  a0,d2
        beq.s   .ad_fail
        move.l  a0,a2
        move.l  d0,d2
        move.l  d1,d3
        move.l  a6,a3
        move.l  EB_EXECBASE(a6),a6
        lea     exp_dosname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   .ad_boot
        move.l  d0,-(sp)
        jsr     LVO_FORBID(a6)
        move.l  (sp),a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_INFO(a0),d0
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  DI_DEVINFO(a0),DN_NEXT(a2)
        move.l  a2,d0
        lsr.l   #2,d0
        move.l  d0,DI_DEVINFO(a0)
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a1
        jsr     LVO_CLOSELIBRARY(a6)
        bra.s   .ad_ok
.ad_boot:
        moveq   #BN_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .ad_fail
        move.l  d0,a1
        move.b  d2,LN_PRI(a1)
        move.w  d3,BN_FLAGS(a1)
        move.l  a2,BN_DEVICENODE(a1)
        move.l  DN_NAME(a2),d0
        lsl.l   #2,d0
        addq.l  #1,d0
        move.l  d0,LN_NAME(a1)
        lea     EB_MOUNTLIST(a3),a0
        jsr     LVO_ENQUEUE(a6)
.ad_ok:
        moveq   #1,d0
        bra.s   .ad_ret
.ad_fail:
        moveq   #0,d0
.ad_ret:
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

; initFunc (d0 = base, a0 = segList, a6 = ExecBase) -> d0 = base : libère l'espace mémoire Zorro II (slots $20-$9F)
; et l'espace E/S (slots $E9-$EF ; $E8 = adresse de configuration, jamais libre), puis configure la chaîne en $E80000.
expansion_initfunc:
        movem.l d2/a2/a6,-(sp)
        move.l  d0,a2
        lea     expansion_name(pc),a1
        move.l  a1,LN_NAME(a2)
        move.l  a6,EB_EXECBASE(a2)
        move.l  a0,EB_SEGLIST(a2)
        lea     EB_BINDSEM(a2),a0
        jsr     LVO_INITSEMAPHORE(a6)
        move.l  a2,a6
        moveq   #$20,d0
        move.l  #$80,d1
        bsr     exp_freeexpmem
        move.l  #E_IOSLOT_LO+1,d0
        moveq   #E_IOSLOT_HI-E_IOSLOT_LO-1,d1
        bsr     exp_freeexpmem
        lea     EB_BOARDLIST(a6),a1
        jsr     newlist
        lea     EB_MOUNTLIST(a6),a1
        jsr     newlist
        lea     $E80000,a0
        bsr     exp_configchain
        move.l  a6,d0
        movem.l (sp)+,d2/a2/a6
        rts

        EVEN
expansion_end:
