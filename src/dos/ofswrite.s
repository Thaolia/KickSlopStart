; src/dos/ofswrite.s — écriture OFS pour le handler DF0: : création de fichiers et de répertoires, flux d'écriture,
; suppression, renommage/déplacement, protection, commentaire, informations disque. Les blocs passent par
; trackdisk.device (CMD_WRITE dans son cache de pistes, CMD_UPDATE à la fin de chaque opération).
; Format OFS public (ADF-FAQ / AmigaDOS Technical Reference) : header (type 2, clé = son bloc, high_seq, first_data,
; table des blocs de données remplie depuis la fin, taille, nom, chaîne de hachage, parent, extension, type
; secondaire), bloc de données (type 8, clé du header, n° de séquence, taille, suivant, 488 octets), bloc d'extension
; (type 16), bitmap (bit à 1 = bloc libre, bit 0 du long 1 = bloc 2, somme de contrôle au long 0), somme de contrôle des
; autres blocs au long 5 (somme de tous les longs = 0).
; Piste IMPLÉMENTATION (« clean ») : format public + AutoDocs dos. AUCUNE lecture ROM.

                include "exec.i"
                include "ofs.i"
                include "disk.i"
                include "dospkt.i"

                xdef    ow_create
                xdef    ow_delete
                xdef    ow_rename
                xdef    ow_setfield
                xdef    ow_diskinfo
                xdef    ws_open
                xdef    ws_write
                xdef    ws_close
                xref    ofs_name_to_block
                xref    ofs_hash
                xref    ofs_namecmp
                xref    dos_now              ; dos_lib.s : heure système en DateStamp

OFS_T_LIST      EQU 16               ; bloc d'extension
OFSB_KEY        EQU 4                ; clé (le bloc lui-même)
OFSB_HIGHSEQ    EQU 8                ; header : blocs dans sa table ; données : n° de séquence
OFSB_CKSUM      EQU 20
OFSB_EXT        EQU 504              ; bloc d'extension suivant
OFS_TABN        EQU 72               ; entrées de table d'un header / d'une extension
OFSB_TABEND     EQU OFSB_HASHTAB+(OFS_TABN-1)*4  ; dernière entrée = premier bloc de données
WS_MAGICV       EQU $57524954        ; « WRIT » : état d'écriture (l'état de lecture commence par la base trackdisk)
ID_VALIDATED    EQU 82
OFSB_VDAYS      EQU 472              ; racine : date de dernière modification du disque

; contexte d'écriture (un seul, alloué au premier besoin ; pointeur en DOS_OWCTX)
OW_TD           EQU 0
OW_IO           EQU 4                ; IOStdReq
OW_BMBLK        EQU OW_IO+IOREQ_SZ   ; bloc bitmap (0 = pas encore lu)
OW_BMDIRTY      EQU OW_BMBLK+4
OW_ERR          EQU OW_BMDIRTY+4     ; dernière erreur d'entrée-sortie (code dos)
OW_BM           EQU OW_ERR+4         ; bitmap (512)
OW_B1           EQU OW_BM+OFS_BSIZE
OW_B2           EQU OW_B1+OFS_BSIZE
OW_PATH         EQU OW_B2+OFS_BSIZE  ; copie de chemin (OW_PATHMAX)
OW_PATHMAX      EQU 128
OW_NAME         EQU OW_PATH+OW_PATHMAX   ; nom final (32)
OW_SIZE         EQU OW_NAME+32

; état d'écriture d'un fichier ouvert (FINDOUTPUT)
WS_MAGIC        EQU 0
WS_HDR          EQU 4                ; bloc header
WS_SIZE         EQU 8                ; octets écrits
WS_NBLK         EQU 12               ; blocs de données
WS_CUR          EQU 16               ; bloc de données courant (0 = aucun)
WS_CURLEN       EQU 20               ; octets dans le bloc courant
WS_EXT          EQU 24               ; extension courante (0 = la table du header)
WS_EXTN         EQU 28               ; entrées dans la table courante
WS_FIRST        EQU 32               ; premier bloc de données
WS_HBUF         EQU 36
WS_XBUF         EQU WS_HBUF+OFS_BSIZE
WS_DBUF         EQU WS_XBUF+OFS_BSIZE
WS_SIZEOF       EQU WS_DBUF+OFS_BSIZE

; ------------------------------------------------------------------------------------------------------------------
; ow_ctx(a6) -> a5 = contexte (alloué au premier appel, bitmap pas encore lue) ; Z = 1 si impossible. Clobbe d0/d1/a0/a1.
ow_ctx:
        move.l  DOS_OWCTX,d0
        bne.s   .cx_have
        move.l  #OW_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .cx_ret
        move.l  d0,a5
        lea     EB_DEVICELIST(a6),a0
        lea     ow_tdname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,OW_TD(a5)
        beq.s   .cx_free
        move.l  a5,DOS_OWCTX
        move.l  a5,d0
.cx_have:
        move.l  d0,a5
.cx_ret:
        rts
.cx_free:
        move.l  a5,a1
        move.l  #OW_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #0,d0
        rts

; ow_io(d0 = bloc, a0 = tampon, d1.w = commande, a5, a6) -> d0 = 1 ok / 0 (OW_ERR posé). Préserve d2-d7/a2-a6.
ow_io:
        move.l  a2,-(sp)
        lea     OW_IO(a5),a1
        move.l  OW_TD(a5),a2
        move.l  a2,IO_DEVICE(a1)
        move.w  d1,IO_COMMAND(a1)
        move.l  a0,IO_DATA(a1)
        move.l  #OFS_BSIZE,IO_LENGTH(a1)
        lsl.l   #8,d0
        add.l   d0,d0
        move.l  d0,IO_OFFSET(a1)
        move.b  #IOF_QUICK,IO_FLAGS(a1)
        clr.l   IO_ACTUAL(a1)
        move.l  a6,-(sp)
        move.l  a2,a6
        jsr     -30(a6)
        move.l  (sp)+,a6
        move.l  (sp)+,a2
        lea     OW_IO(a5),a1
        move.b  IO_ERROR(a1),d0
        beq.s   .io_ok
        move.l  #ERROR_DISK_WRITE_PROTECTED,d1
        cmp.b   #28,d0
        beq.s   .io_err
        move.l  #ERROR_OBJECT_NOT_FOUND,d1
.io_err:
        move.l  d1,OW_ERR(a5)
        moveq   #0,d0
        rts
.io_ok:
        moveq   #1,d0
        rts
ow_rd:
        moveq   #2,d1                ; CMD_READ
        bra.s   ow_io
; ow_wr(d0 = bloc, a0 = tampon) : somme de contrôle posée (long 5), puis écriture dans le cache trackdisk.
ow_wr:
        move.l  d0,-(sp)
        bsr.s   ow_cksum
        move.l  (sp)+,d0
        moveq   #3,d1                ; CMD_WRITE
        bra.s   ow_io
; ow_sync(a5) -> d0 = 1 ok / 0 : bitmap écrite si modifiée, puis CMD_UPDATE (pistes du cache vers le disque).
ow_sync:
        tst.l   OW_BMDIRTY(a5)
        beq.s   .sy_upd
        clr.l   OW_BMDIRTY(a5)
        lea     OW_BM(a5),a0         ; somme de la bitmap au long 0
        clr.l   (a0)
        moveq   #0,d0
        moveq   #127,d1
.sy_sum:
        add.l   (a0)+,d0
        dbra    d1,.sy_sum
        neg.l   d0
        move.l  d0,OW_BM(a5)
        move.l  OW_BMBLK(a5),d0
        lea     OW_BM(a5),a0
        moveq   #3,d1
        bsr     ow_io
        tst.l   d0
        beq.s   .sy_ret
.sy_upd:
        moveq   #0,d0
        lea     OW_B2(a5),a0
        moveq   #4,d1                ; CMD_UPDATE
        bsr     ow_io
.sy_ret:
        rts
; ow_cksum(a0 = bloc) : long 5 = -(somme des autres longs). Préserve a0 et d2-d7.
ow_cksum:
        clr.l   OFSB_CKSUM(a0)
        move.l  a0,a1
        moveq   #0,d0
        moveq   #127,d1
.ck_sum:
        add.l   (a1)+,d0
        dbra    d1,.ck_sum
        neg.l   d0
        move.l  d0,OFSB_CKSUM(a0)
        rts

; ow_bmload(a5) -> d0 = 1 ok / 0 : la bitmap (désignée par le bloc racine) est lue une fois et gardée.
ow_bmload:
        tst.l   OW_BMBLK(a5)
        bne.s   .bl_ok
        move.l  #OFS_ROOTBLK,d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .bl_ret
        lea     OW_B1(a5),a0
        moveq   #-1,d0               ; bitmap non validée : pas d'écriture
        cmp.l   OFSB_BMFLAG(a0),d0
        bne.s   .bl_nv
        move.l  OFSB_BMPAGES(a0),d0
        move.l  d0,-(sp)
        lea     OW_BM(a5),a0
        bsr     ow_rd
        move.l  (sp)+,d1
        tst.l   d0
        beq.s   .bl_ret
        move.l  d1,OW_BMBLK(a5)
.bl_ok:
        moveq   #1,d0
.bl_ret:
        rts
.bl_nv:
        move.l  #ERROR_DISK_NOT_VALIDATED,OW_ERR(a5)
        moveq   #0,d0
        rts
; ow_bmbit(d0 = bloc) -> a0 = long de la bitmap, d1 = n° de bit. Clobbe d0.
ow_bmbit:
        subq.l  #2,d0
        move.l  d0,d1
        lsr.l   #5,d0
        lsl.l   #2,d0
        lea     OW_BM+4(a5),a0
        add.l   d0,a0
        and.w   #31,d1
        rts
; ow_alloc(a5) -> d0 = bloc libre pris dans la bitmap (recherche à partir de la racine, puis depuis le début) | 0.
ow_alloc:
        movem.l d2-d3,-(sp)
        move.l  #OFS_ROOTBLK+1,d2
        move.l  #OFS_NBLK,d3
.al_lp:
        cmp.l   d3,d2
        blo.s   .al_try
        cmp.l   #OFS_NBLK,d3
        bne.s   .al_full
        moveq   #2,d2                ; deuxième passe : du début à la racine
        move.l  #OFS_ROOTBLK,d3
.al_try:
        move.l  d2,d0
        bsr.s   ow_bmbit
        move.l  (a0),d0
        btst    d1,d0
        bne.s   .al_got
        addq.l  #1,d2
        bra.s   .al_lp
.al_got:
        bclr    d1,d0
        move.l  d0,(a0)
        st      OW_BMDIRTY(a5)
        move.l  d2,d0
        bra.s   .al_ret
.al_full:
        move.l  #ERROR_DISK_FULL,OW_ERR(a5)
        moveq   #0,d0
.al_ret:
        movem.l (sp)+,d2-d3
        rts
; ow_free(d0 = bloc, a5) : le bloc redevient libre (blocs hors disque ignorés).
ow_free:
        cmp.l   #2,d0
        blo.s   .fr_ret
        cmp.l   #OFS_NBLK,d0
        bhs.s   .fr_ret
        bsr.s   ow_bmbit
        move.l  (a0),d0
        bset    d1,d0
        move.l  d0,(a0)
        st      OW_BMDIRTY(a5)
.fr_ret:
        rts

; ow_parent(a0 = chemin, d0 = répertoire de départ (0 = racine), a5) -> d0 = répertoire qui contient l'objet | 0,
; a1 = nom final (OW_NAME). Le chemin est coupé après son dernier « / » ou « : » ; le préfixe (séparateur compris :
; « vol: » = racine, « / » = parent) est résolu par ofs_name_to_block. Nom vide ou > 30 : échec. B2 = le répertoire.
ow_parent:
        movem.l d2-d3,-(sp)
        move.l  d0,d2
        lea     OW_PATH(a5),a1
        moveq   #OW_PATHMAX-2,d1
        moveq   #0,d3                ; d3 = position après le dernier séparateur | 0
.pa_cp:
        move.b  (a0)+,d0
        move.b  d0,(a1)+
        beq.s   .pa_end
        cmp.b   #'/',d0
        beq.s   .pa_sep
        cmp.b   #':',d0
        bne.s   .pa_nx
.pa_sep:
        move.l  a1,d3
.pa_nx:
        dbra    d1,.pa_cp
        clr.b   (a1)
.pa_end:
        lea     OW_PATH(a5),a0       ; a0 = nom (tout le chemin s'il n'y a pas de séparateur)
        tst.l   d3
        beq.s   .pa_name
        move.l  d3,a0
.pa_name:
        lea     OW_NAME(a5),a1       ; nom : 1 à 30 caractères
        moveq   #30,d1               ; 30 caractères + NUL au plus
.pa_nc:
        move.b  (a0)+,(a1)+
        dbeq    d1,.pa_nc
        bne.s   .pa_bad
        lea     OW_NAME(a5),a1
        tst.b   (a1)
        beq.s   .pa_bad
        move.l  d2,d0
        tst.l   d3
        beq.s   .pa_dir
        move.l  d3,a0                ; le préfixe s'arrête au séparateur inclus
        clr.b   (a0)
        lea     OW_PATH(a5),a0
        move.l  d2,d0
        jsr     ofs_name_to_block
.pa_dir:
        tst.l   d0
        bne.s   .pa_rd
        move.l  #OFS_ROOTBLK,d0
        tst.l   d3
        bne.s   .pa_nf
.pa_rd:
        move.l  d0,d2                ; le parent doit être un répertoire
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .pa_nf
        lea     OW_B2(a5),a0
        move.l  OFSB_SECTYPE(a0),d0
        cmp.l   #OFS_ST_ROOT,d0
        beq.s   .pa_ok
        cmp.l   #OFS_ST_USERDIR,d0
        bne.s   .pa_nf
.pa_ok:
        lea     OW_NAME(a5),a1
        move.l  d2,d0
        bra.s   .pa_ret
.pa_bad:
        move.l  #ERROR_INVALID_COMPONENT_NAME,OW_ERR(a5)
        moveq   #0,d0
        bra.s   .pa_ret
.pa_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
        moveq   #0,d0
.pa_ret:
        movem.l (sp)+,d2-d3
        rts

; ow_lookup(d0 = répertoire, a1 = nom, a5) -> d0 = bloc de l'objet | 0 ; d2 = prédécesseur dans la chaîne (0 = la
; table du répertoire), d3 = index de hachage. B2 contient l'objet trouvé. Clobbe d1/a0/a1/a4.
ow_lookup:
        movem.l d4-d5,-(sp)
        move.l  d0,d4                ; d4 = répertoire
        move.l  a1,a4
        moveq   #OFS_HTDEF,d3
        jsr     ofs_hash             ; d1 = index
        move.l  d1,d3
        move.l  d4,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .lk_no
        lea     OW_B2(a5),a0
        move.l  d3,d0
        lsl.l   #2,d0
        move.l  OFSB_HASHTAB(a0,d0.l),d5 ; d5 = bloc courant
        moveq   #0,d2
.lk_lp:
        tst.l   d5
        beq.s   .lk_no
        cmp.l   #OFS_NBLK,d5
        bhs.s   .lk_no
        move.l  d5,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .lk_no
        lea     OW_B2+OFSB_NAME(a5),a1
        move.l  a4,a0
        jsr     ofs_namecmp
        beq.s   .lk_hit
        move.l  d5,d2
        move.l  OW_B2+OFSB_HASHCHAIN(a5),d5
        bra.s   .lk_lp
.lk_hit:
        move.l  d5,d0
        bra.s   .lk_ret
.lk_no:
        moveq   #0,d0
.lk_ret:
        movem.l (sp)+,d4-d5
        rts

; ow_unlink(d4 = répertoire, d5 = objet (en B2), d2 = prédécesseur, d3 = index, a5) -> d0 = 1/0 : l'objet quitte la
; chaîne de hachage de son répertoire. B1 est utilisé, B2 conservé.
ow_unlink:
        move.l  OW_B2+OFSB_HASHCHAIN(a5),-(sp)   ; suivant de l'objet
        move.l  d2,d0
        bne.s   .ul_pred
        move.l  d4,d0
.ul_pred:
        move.l  d0,-(sp)
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .ul_fail
        lea     OW_B1(a5),a0
        tst.l   d2
        bne.s   .ul_chain
        move.l  d3,d0
        lsl.l   #2,d0
        move.l  4(sp),OFSB_HASHTAB(a0,d0.l)
        bra.s   .ul_w
.ul_chain:
        move.l  4(sp),OFSB_HASHCHAIN(a0)
.ul_w:
        move.l  (sp),d0
        bsr     ow_wr
        addq.l  #8,sp
        rts
.ul_fail:
        addq.l  #8,sp
        moveq   #0,d0
        rts

; ow_link(d4 = répertoire, d5 = objet, a1 = son nom, a5) -> d0 = 1/0 : l'objet (en B1, nom/parent déjà posés) entre en
; tête de la chaîne de son index dans le répertoire ; l'objet puis le répertoire sont écrits. B2 est utilisé.
ow_link:
        move.l  a4,-(sp)
        move.l  a1,a4
        moveq   #OFS_HTDEF,d3
        jsr     ofs_hash
        move.l  (sp)+,a4
        lsl.l   #2,d1
        move.l  d1,-(sp)
        move.l  d4,d0
        lea     OW_B2(a5),a0
        bsr     ow_rd
        move.l  (sp)+,d1
        tst.l   d0
        beq.s   .lnk_ret
        lea     OW_B2(a5),a0
        move.l  OFSB_HASHTAB(a0,d1.l),OW_B1+OFSB_HASHCHAIN(a5)
        move.l  d5,OFSB_HASHTAB(a0,d1.l)
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_wr
        tst.l   d0
        beq.s   .lnk_ret
        lea     OW_B2(a5),a0         ; le répertoire change : sa date aussi
        bsr     ow_stamp
        move.l  d4,d0
        bsr     ow_wr
.lnk_ret:
        rts

; ow_setname(a0 = bloc, a1 = nom C) : nom BCPL (longueur + caractères) au long 108.
ow_setname:
        lea     OFSB_NAME+1(a0),a0
        moveq   #0,d0
.sn_lp:
        move.b  (a1)+,d1
        beq.s   .sn_end
        move.b  d1,(a0)+
        addq.w  #1,d0
        bra.s   .sn_lp
.sn_end:
        sub.l   d0,a0
        move.b  d0,-1(a0)
        rts

; ow_clear(a0 = bloc) : 128 longs à 0. Préserve a0.
ow_clear:
        move.l  a0,a1
        moveq   #127,d0
.cl_lp:
        clr.l   (a1)+
        dbra    d0,.cl_lp
        rts

; ow_stamp(a0 = bloc d'en-tête) : date de modification (+420) = maintenant ; pour la racine, aussi celle du disque
; (+472). Préserve tout sauf d0.
ow_stamp:
        move.l  a0,-(sp)
        lea     OFSB_DAYS(a0),a0
        jsr     dos_now
        move.l  (sp)+,a0
        cmp.l   #OFS_ST_ROOT,OFSB_SECTYPE(a0)
        bne.s   .st_ret
        move.l  a0,-(sp)
        lea     OFSB_VDAYS(a0),a0
        jsr     dos_now
        move.l  (sp)+,a0
.st_ret:
        rts

; ow_touch(d0 = répertoire, a5) -> d0 = 1/0 : le répertoire (lu dans B1) reçoit la date du jour et est réécrit.
ow_touch:
        move.l  d0,-(sp)
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .to_fail
        lea     OW_B1(a5),a0
        bsr.s   ow_stamp
        move.l  (sp)+,d0
        bra     ow_wr
.to_fail:
        addq.l  #4,sp
        rts

; ow_freeobj(d5 = objet (en B2), a5) : rend ses blocs : header, et pour un fichier ses blocs de données et extensions.
ow_freeobj:
        movem.l d2-d3/d5,-(sp)
        lea     OW_B2(a5),a0         ; table du header copiée en B1 (B2 sert ensuite aux extensions)
        lea     OW_B1(a5),a1
        moveq   #127,d0
.fo_cp:
        move.l  (a0)+,(a1)+
        dbra    d0,.fo_cp
        move.l  d5,d0
        bsr     ow_free
        cmp.l   #OFS_ST_FILE,OW_B1+OFSB_SECTYPE(a5)
        bne.s   .fo_ret
.fo_tab:
        lea     OW_B1+OFSB_HASHTAB(a5),a0
        moveq   #OFS_TABN-1,d2
.fo_ent:
        move.l  (a0)+,d0
        move.l  a0,-(sp)
        bsr     ow_free
        move.l  (sp)+,a0
        dbra    d2,.fo_ent
        move.l  OW_B1+OFSB_EXT(a5),d5
        beq.s   .fo_ret
        cmp.l   #OFS_NBLK,d5
        bhs.s   .fo_ret
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq.s   .fo_ret
        move.l  d5,d0
        bsr     ow_free
        bra.s   .fo_tab
.fo_ret:
        movem.l (sp)+,d2-d3/d5
        rts

; ------------------------------------------------------------------------------------------------------------------
; ow_create(a0 = chemin, d0 = répertoire de départ, d1 = type secondaire (fichier -3 / répertoire 2), a6) -> d0 = bloc
; du nouvel objet | 0, d1 = erreur dos. Un fichier existant du même nom est remplacé ; un répertoire est refusé.
ow_create:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  d1,d7                ; d7 = type secondaire
        move.l  d0,d6
        move.l  a0,a2
        bsr     ow_ctx
        beq     ow_fail0
        bsr     ow_bmload
        beq     ow_fail
        move.l  a2,a0
        move.l  d6,d0
        bsr     ow_parent            ; d0 = répertoire, a1 = nom
        tst.l   d0
        beq     ow_fail
        move.l  d0,d4
        move.l  a1,a3                ; a3 = nom
        bsr     ow_lookup
        tst.l   d0
        beq.s   .cr_new
        move.l  d0,d5                ; existe déjà : un fichier est remplacé
        cmp.l   #OFS_ST_FILE,d7
        bne.s   .cr_exists
        cmp.l   #OFS_ST_FILE,OW_B2+OFSB_SECTYPE(a5)
        bne.s   .cr_exists
        bsr     ow_unlink
        tst.l   d0
        beq     ow_fail
        bsr     ow_freeobj
.cr_new:
        bsr     ow_alloc
        tst.l   d0
        beq     ow_fail
        move.l  d0,d5                ; d5 = nouveau bloc
        lea     OW_B1(a5),a0
        bsr     ow_clear
        move.l  #OFS_T_SHORT,OFSB_TYPE(a0)
        move.l  d5,OFSB_KEY(a0)
        move.l  d4,OFSB_PARENT(a0)
        move.l  d7,OFSB_SECTYPE(a0)
        bsr     ow_stamp
        move.l  a3,a1
        bsr     ow_setname
        move.l  a3,a1
        bsr     ow_link
        tst.l   d0
        beq     ow_fail
        bsr     ow_sync
        tst.l   d0
        beq     ow_fail
        move.l  d5,d0
        moveq   #0,d1
        bra     ow_ret
.cr_exists:
        move.l  #ERROR_OBJECT_EXISTS,OW_ERR(a5)
ow_fail:
        move.l  OW_ERR(a5),d1
        moveq   #0,d0
ow_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts
ow_fail0:
        move.l  #ERROR_OBJECT_NOT_FOUND,d1
        moveq   #0,d0
        bra.s   ow_ret

; ow_delete(a0 = chemin, d0 = répertoire de départ, a6) -> d0 = -1 / 0, d1 = erreur. Un répertoire doit être vide.
ow_delete:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  d0,d6
        move.l  a0,a2
        bsr     ow_ctx
        beq.s   ow_fail0
        bsr     ow_bmload
        beq.s   ow_fail
        move.l  a2,a0
        move.l  d6,d0
        bsr     ow_parent
        tst.l   d0
        beq.s   ow_fail
        move.l  d0,d4
        bsr     ow_lookup
        tst.l   d0
        beq.s   .de_nf
        move.l  d0,d5
        cmp.l   #OFS_ST_USERDIR,OW_B2+OFSB_SECTYPE(a5)
        bne.s   .de_go
        lea     OW_B2+OFSB_HASHTAB(a5),a0  ; répertoire non vide : refusé
        moveq   #OFS_TABN-1,d0
.de_em:
        tst.l   (a0)+
        bne.s   .de_full
        dbra    d0,.de_em
.de_go:
        bsr     ow_unlink
        tst.l   d0
        beq     ow_fail
        bsr     ow_freeobj
        move.l  d4,d0
        bsr     ow_touch
        tst.l   d0
        beq     ow_fail
        bsr     ow_sync
        tst.l   d0
        beq     ow_fail
        moveq   #-1,d0
        moveq   #0,d1
        bra.s   ow_ret
.de_full:
        move.l  #ERROR_DIRECTORY_NOT_EMPTY,OW_ERR(a5)
        bra     ow_fail
.de_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
        bra     ow_fail

; ow_rename(a0 = ancien chemin, d0 = son départ, a1 = nouveau chemin, d1 = son départ, a6) -> d0 = -1 / 0, d1 = erreur.
; L'objet quitte la chaîne de son répertoire, prend le nouveau nom et le nouveau parent, entre dans la nouvelle chaîne.
ow_rename:
        movem.l d2-d7/a2-a5,-(sp)
        movem.l d1/a1,-(sp)          ; nouveau (départ, chemin)
        move.l  d0,d6
        move.l  a0,a2
        bsr     ow_ctx
        beq     .rn_f0
        bsr     ow_bmload
        beq     .rn_f
        move.l  a2,a0
        move.l  d6,d0
        bsr     ow_parent
        tst.l   d0
        beq     .rn_f
        move.l  d0,d4
        bsr     ow_lookup
        tst.l   d0
        beq     .rn_nf
        move.l  d0,d5                ; d5 = objet
        bsr     ow_unlink            ; retiré de l'ancien répertoire (B2 = l'objet)
        tst.l   d0
        beq     .rn_f
        movem.l (sp),d1/a0           ; nouveau répertoire et nom
        move.l  d1,d0
        bsr     ow_parent
        tst.l   d0
        beq.s   .rn_relink           ; destination invalide : l'objet retourne d'où il vient
        move.l  d0,d7
        move.l  a1,a3
        move.l  d7,d0
        bsr     ow_lookup            ; nom déjà pris -> refus (l'objet retourne d'où il vient)
        tst.l   d0
        bne.s   .rn_taken
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        tst.l   d0
        beq     .rn_f
        lea     OW_B1+OFSB_NAME(a5),a0   ; ancien nom effacé (32 octets)
        moveq   #7,d0
.rn_cn:
        clr.l   (a0)+
        dbra    d0,.rn_cn
        lea     OW_B1(a5),a0
        move.l  a3,a1
        bsr     ow_setname
        move.l  d7,OW_B1+OFSB_PARENT(a5)
        move.l  d7,d4
        move.l  a3,a1
        bsr     ow_link
        tst.l   d0
        beq.s   .rn_f
        bsr     ow_sync
        tst.l   d0
        beq.s   .rn_f
        addq.l  #8,sp
        moveq   #-1,d0
        moveq   #0,d1
        bra     ow_ret
.rn_taken:
        move.l  #ERROR_OBJECT_EXISTS,OW_ERR(a5)
.rn_relink:
        move.l  OW_ERR(a5),-(sp)     ; remis dans son répertoire d'origine sous son nom
        move.l  d5,d0
        lea     OW_B1(a5),a0
        bsr     ow_rd
        lea     OW_B1+OFSB_NAME+1(a5),a0   ; nom C reconstitué dans OW_PATH
        lea     OW_PATH(a5),a1
        moveq   #0,d0
        move.b  OW_B1+OFSB_NAME(a5),d0
        bra.s   .rl_nx
.rl_cp:
        move.b  (a0)+,(a1)+
.rl_nx:
        dbra    d0,.rl_cp
        clr.b   (a1)
        move.l  OW_B1+OFSB_PARENT(a5),d4
        lea     OW_PATH(a5),a1
        bsr     ow_link
        bsr     ow_sync
        move.l  (sp)+,OW_ERR(a5)
        bra.s   .rn_f
.rn_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
.rn_f:
        addq.l  #8,sp
        bra     ow_fail
.rn_f0:
        addq.l  #8,sp
        bra     ow_fail0

; ow_setfield(a0 = chemin, d0 = départ, d1 = 0 protection (d2 = masque) / 1 commentaire (d2 = BPTR BSTR), a6) ->
; d0 = -1 / 0, d1 = erreur.
ow_setfield:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  d1,d7
        move.l  d0,d6
        move.l  a0,a2
        move.l  d2,a3
        bsr     ow_ctx
        beq     ow_fail0
        move.l  a2,a0
        move.l  d6,d0
        bsr     ow_parent
        tst.l   d0
        beq     ow_fail
        bsr     ow_lookup
        tst.l   d0
        beq.s   .sf_nf
        move.l  d0,d5
        lea     OW_B2(a5),a0
        tst.l   d7
        bne.s   .sf_com
        move.l  a3,OFSB_PROTECT(a0)
        bra.s   .sf_w
.sf_com:
        move.l  a3,d0                ; commentaire BSTR, 79 caractères au plus
        lsl.l   #2,d0
        move.l  d0,a1
        lea     OFSB_COMMENT(a0),a0
        moveq   #0,d0
        move.b  (a1),d0
        cmp.w   #79,d0
        bls.s   .sf_cl
        moveq   #79,d0
.sf_cl:
        move.b  d0,(a0)+
        addq.l  #1,a1
        bra.s   .sf_cn
.sf_cc:
        move.b  (a1)+,(a0)+
.sf_cn:
        dbra    d0,.sf_cc
.sf_w:
        move.l  d5,d0
        lea     OW_B2(a5),a0
        bsr     ow_wr
        tst.l   d0
        beq     ow_fail
        bsr     ow_sync
        tst.l   d0
        beq     ow_fail
        moveq   #-1,d0
        moveq   #0,d1
        bra     ow_ret
.sf_nf:
        move.l  #ERROR_OBJECT_NOT_FOUND,OW_ERR(a5)
        bra     ow_fail

; ow_diskinfo(a0 = InfoData, a1 = nœud volume (BPTR), a6) -> d0 = -1 : état du disque (validé), blocs, blocs utilisés
; comptés dans la bitmap, 488 octets par bloc, type DOS\0.
ow_diskinfo:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a2
        move.l  a1,d6
        move.l  a2,a0
        moveq   #8,d0
.di_clr:
        clr.l   (a0)+
        dbra    d0,.di_clr
        move.l  #ID_VALIDATED,8(a2)  ; id_DiskState
        move.l  #OFS_NBLK-2,12(a2)   ; id_NumBlocks
        move.l  #OFS_DMAX,20(a2)     ; id_BytesPerBlock
        move.l  #$444F5300,24(a2)    ; id_DiskType « DOS\0 »
        move.l  d6,28(a2)            ; id_VolumeNode
        bsr     ow_ctx
        beq.s   .di_ret
        bsr     ow_bmload
        beq.s   .di_ret
        moveq   #0,d2                ; blocs libres : bits à 1 de la bitmap
        lea     OW_BM+4(a5),a0
        move.w  #OFS_NBLK-2-1,d3
        moveq   #0,d1
.di_bit:
        move.w  d1,d0
        lsr.w   #5,d0
        lsl.w   #2,d0
        move.l  0(a0,d0.w),d0
        move.w  d1,d4
        and.w   #31,d4
        btst    d4,d0
        beq.s   .di_used
        addq.l  #1,d2
.di_used:
        addq.w  #1,d1
        dbra    d3,.di_bit
        move.l  #OFS_NBLK-2,d0
        sub.l   d2,d0
        move.l  d0,16(a2)            ; id_NumBlocksUsed
.di_ret:
        moveq   #-1,d0
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ------------------------------------------------------------------------------------------------------------------
; ws_open(a0 = chemin, d0 = départ, a6) -> d0 = état d'écriture | 0, d1 = erreur : crée (ou remplace) le fichier.
ws_open:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a0,a2
        move.l  d0,d6
        move.l  #WS_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .wo_mem
        move.l  d0,a3                ; a3 = état
        move.l  a2,a0
        move.l  d6,d0
        moveq   #OFS_ST_FILE,d1
        bsr     ow_create
        tst.l   d0
        beq.s   .wo_fail
        move.l  #WS_MAGICV,WS_MAGIC(a3)
        move.l  d0,WS_HDR(a3)
        move.l  DOS_OWCTX,a5         ; header (écrit vide par ow_create) gardé dans l'état
        lea     OW_B1(a5),a0
        lea     WS_HBUF(a3),a1
        moveq   #127,d1
.wo_cp:
        move.l  (a0)+,(a1)+
        dbra    d1,.wo_cp
        move.l  a3,d0
        moveq   #0,d1
        bra.s   .wo_ret
.wo_fail:
        move.l  d1,-(sp)
        move.l  a3,a1
        move.l  #WS_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,d1
        moveq   #0,d0
        bra.s   .wo_ret
.wo_mem:
        move.l  #ERROR_DISK_FULL,d1
        moveq   #0,d0
.wo_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ws_write(a1 = état, a0 = données, d0 = longueur, a6) -> d0 = longueur | -1, d1 = erreur. Les blocs de données se
; remplissent un à un ; un bloc plein est écrit quand le suivant est alloué (son lien vers lui est alors connu).
ws_write:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a3
        move.l  a0,a2
        move.l  d0,d7                ; d7 = reste
        move.l  d0,d6                ; d6 = demandé
        bsr     ow_ctx
        beq     .ww_err
.ww_lp:
        tst.l   d7
        beq     .ww_ok
        tst.l   WS_CUR(a3)
        beq.s   .ww_new
        cmp.l   #OFS_DMAX,WS_CURLEN(a3)
        blo.s   .ww_copy
.ww_new:
        bsr     ow_alloc
        tst.l   d0
        beq     .ww_err
        move.l  d0,d5                ; d5 = nouveau bloc
        move.l  WS_CUR(a3),d0
        beq.s   .ww_first
        lea     WS_DBUF(a3),a0       ; bloc précédent : complet, lié au nouveau
        move.l  #OFS_DMAX,OFSB_DSIZE(a0)
        move.l  d5,OFSB_NEXT(a0)
        bsr     ow_wr
        tst.l   d0
        beq     .ww_err
        bra.s   .ww_init
.ww_first:
        move.l  d5,WS_FIRST(a3)
.ww_init:
        lea     WS_DBUF(a3),a0
        bsr     ow_clear
        move.l  #OFS_T_DATA,OFSB_TYPE(a0)
        move.l  WS_HDR(a3),OFSB_KEY(a0)
        addq.l  #1,WS_NBLK(a3)
        move.l  WS_NBLK(a3),OFSB_HIGHSEQ(a0)
        move.l  d5,WS_CUR(a3)
        clr.l   WS_CURLEN(a3)
        move.l  d5,d0
        bsr     ws_tabadd
        tst.l   d0
        beq     .ww_err
.ww_copy:
        move.l  #OFS_DMAX,d4         ; n = min(place, reste)
        sub.l   WS_CURLEN(a3),d4
        cmp.l   d7,d4
        bls.s   .ww_n
        move.l  d7,d4
.ww_n:
        lea     WS_DBUF+OFSB_DATA(a3),a1
        add.l   WS_CURLEN(a3),a1
        move.l  d4,d0
        bra.s   .ww_cn
.ww_cp:
        move.b  (a2)+,(a1)+
.ww_cn:
        dbra    d0,.ww_cp
        add.l   d4,WS_CURLEN(a3)
        add.l   d4,WS_SIZE(a3)
        sub.l   d4,d7
        bra     .ww_lp
.ww_ok:
        move.l  d6,d0
        moveq   #0,d1
        bra.s   .ww_ret
.ww_err:
        moveq   #-1,d0
        move.l  #ERROR_DISK_FULL,d1
        move.l  DOS_OWCTX,d2
        beq.s   .ww_ret
        move.l  d2,a5
        move.l  OW_ERR(a5),d1
.ww_ret:
        movem.l (sp)+,d2-d7/a2-a5
        rts

; ws_tabadd(d0 = bloc de données, a3 = état, a5) -> d0 = 1/0 : le bloc entre dans la table courante (remplie depuis la
; fin) ; une table pleine fait allouer une extension, chaînée depuis le header ou l'extension précédente (écrite).
ws_tabadd:
        move.l  d2,-(sp)
        move.l  d0,d2
        cmp.l   #OFS_TABN,WS_EXTN(a3)
        blo.s   .ta_put
        bsr     ow_alloc             ; nouvelle extension
        tst.l   d0
        beq.s   .ta_ret
        move.l  d0,-(sp)
        tst.l   WS_EXT(a3)
        bne.s   .ta_prev
        move.l  d0,WS_HBUF+OFSB_EXT(a3)
        bra.s   .ta_newx
.ta_prev:
        lea     WS_XBUF(a3),a0       ; extension pleine : liée à la nouvelle et écrite
        move.l  d0,OFSB_EXT(a0)
        move.l  #OFS_TABN,OFSB_HIGHSEQ(a0)
        move.l  WS_EXT(a3),d0
        bsr     ow_wr
        tst.l   d0
        beq.s   .ta_fail
.ta_newx:
        lea     WS_XBUF(a3),a0
        bsr     ow_clear
        move.l  #OFS_T_LIST,OFSB_TYPE(a0)
        move.l  (sp),OFSB_KEY(a0)
        move.l  WS_HDR(a3),OFSB_PARENT(a0)
        move.l  #OFS_ST_FILE,OFSB_SECTYPE(a0)
        move.l  (sp)+,WS_EXT(a3)
        clr.l   WS_EXTN(a3)
.ta_put:
        lea     WS_HBUF(a3),a0
        tst.l   WS_EXT(a3)
        beq.s   .ta_tab
        lea     WS_XBUF(a3),a0
.ta_tab:
        move.l  WS_EXTN(a3),d0
        lsl.l   #2,d0
        neg.l   d0
        lea     OFSB_TABEND(a0),a0
        move.l  d2,0(a0,d0.l)
        addq.l  #1,WS_EXTN(a3)
        moveq   #1,d0
.ta_ret:
        move.l  (sp)+,d2
        rts
.ta_fail:
        addq.l  #4,sp
        moveq   #0,d0
        bra.s   .ta_ret

; ws_close(a1 = état, a6) -> d0 = -1 / 0 : dernier bloc de données, extension courante et header (taille, nombre de
; blocs de sa table, premier bloc) écrits, bitmap et cache vidés ; l'état est libéré.
ws_close:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a1,a3
        moveq   #0,d7                ; d7 = résultat
        bsr     ow_ctx
        beq.s   .wc_free
        move.l  WS_CUR(a3),d0
        beq.s   .wc_ext
        lea     WS_DBUF(a3),a0
        move.l  WS_CURLEN(a3),OFSB_DSIZE(a0)
        clr.l   OFSB_NEXT(a0)
        bsr     ow_wr
        tst.l   d0
        beq.s   .wc_free
.wc_ext:
        move.l  WS_EXT(a3),d0
        beq.s   .wc_hdr
        lea     WS_XBUF(a3),a0
        move.l  WS_EXTN(a3),OFSB_HIGHSEQ(a0)
        bsr     ow_wr
        tst.l   d0
        beq.s   .wc_free
.wc_hdr:
        lea     WS_HBUF(a3),a0
        move.l  WS_SIZE(a3),OFSB_FILESIZE(a0)
        move.l  WS_FIRST(a3),OFSB_FIRSTDATA(a0)
        move.l  WS_NBLK(a3),d0
        cmp.l   #OFS_TABN,d0
        bls.s   .wc_hs
        moveq   #OFS_TABN,d0
.wc_hs:
        move.l  d0,OFSB_HIGHSEQ(a0)
        bsr     ow_stamp
        move.l  WS_HDR(a3),d0
        bsr     ow_wr
        tst.l   d0
        beq.s   .wc_free
        bsr     ow_sync
        tst.l   d0
        beq.s   .wc_free
        moveq   #-1,d7
.wc_free:
        move.l  a3,a1
        move.l  #WS_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d7,d0
        movem.l (sp)+,d2-d7/a2-a5
        rts

ow_tdname:
        dc.b    "trackdisk.device",0
        even
