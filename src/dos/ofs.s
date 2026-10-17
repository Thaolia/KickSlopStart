; src/dos/ofs.s — lecture seule OFS (D1) : ofs_read_file(name, dest, max) -> taille lue | 0.
; Machinerie INTERNE du filesystem (PAS encore de packets / file-handler BCPL = D3). S'appuie sur trackdisk
; CMD_READ (M6z multi-piste) pour lire des blocs logiques de 512 o de DF0:. Algorithme OFS verrouillé
; empiriquement sur un ADF de test (asset, PAS la ROM) : root@880 ; hash h=len, h=(h*13+toupper(c))&$7FF,
; idx=h%ht_size ; table de hash -> header (nom BCPL, sec_type, first_data, hash_chain) ; data block OFS
; (type 8, data_size, next_data, données @+24). Clean-room : ADF-FAQ / AmigaDOS Technical Reference (public)
; + AROS rom/filesys (lecture seule). AUCUNE lecture ROM.
;
; Déviations/portée ASSUMÉES : lecture seule ; traversée de sous-répertoires via chemins '/'-séparés (USERDIR
; intermédiaires -> fichier final ; ht_size des USERDIR = 72 par défaut, long[3] non peuplé = mesuré sur l'ADF) ;
; nom insensible à la casse ASCII a-z (OFS non-international) ; les boucles hash-chain/data sont CAPPÉES
; (anti-hang sur disque corrompu). FFS (pas de header de data block) non supporté (1.3 boote en OFS).

                include "exec.i"
                include "disk.i"
                include "ofs.i"
                include "dospkt.i"       ; FIB_* (remplissage du FileInfoBlock par ofs_fib_fill)

                xdef    ofs_read_file
                xdef    ofs_name_to_block    ; résout un chemin -> bloc header (Lock)
                xdef    ofs_fill_fib         ; remplit un FIB depuis un bloc header (Examine)
                xdef    ofs_dir_next         ; énumère l'entrée suivante d'un répertoire (ExNext)

; ofs_read_file(a6=SysBase, a0=path NUL-terminé, a1=dest, d0=max octets) -> d0 = taille lue | 0.
; Résout un CHEMIN à composants séparés par '/' (ex. « s/startup-sequence ») : traverse les sous-répertoires
; USERDIR intermédiaires puis lit le FICHIER final. Un chemin mono-composant (« kickslop ») = lookup racine
; (compat D1). Noms comparés SANS tenir compte de la casse. Lit via trackdisk.device (FindName).
ofs_read_file:
                movem.l d2-d7/a2-a5,-(sp)
                lea     -OFS_FRAME(sp),sp           ; frame local : [comp buf][curseur path][flag dernier]
                move.l  a0,LF_PATHCUR(sp)           ; curseur path initial (a0 = chemin)
                move.l  a1,a5                        ; a5 = dest (avance à chaque data block)
                move.l  d0,d7                        ; d7 = max octets restant (garde buffer)
                moveq   #0,d6                        ; d6 = total lu (valeur de retour)
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .fail_nofree                 ; pas de trackdisk.device
                move.l  d0,a2                        ; a2 = trackdisk base
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fail_nofree
                move.l  d0,a3                        ; a3 = ioreq ; block buffer = a3 + IOREQ_SZ
                move.l  #OFS_ROOTBLK,d4             ; d4 = bloc répertoire courant (démarre à la racine)
.nextcomp:
                lea     LF_COMP(sp),a4             ; a4 = buffer composant (NUL-terminé par ofs_split)
                move.l  LF_PATHCUR(sp),a0          ; a0 = curseur path
                bsr     ofs_split                    ; copie le composant -> (a4) ; a0 avance ; d0 = 1 si dernier
                move.l  a0,LF_PATHCUR(sp)
                move.b  d0,LF_LAST(sp)
                bsr     ofs_dir_lookup               ; (d4=dir, a4=comp) -> d0 = bloc header trouvé | 0
                tst.l   d0
                beq     .exit                        ; composant introuvable -> échec
                move.l  d0,d4                        ; d4 = bloc du composant trouvé
                move.l  d4,d0                         ; relire ce bloc (sectype ; et file header si dernier)
                bsr     ofs_read_block
                tst.l   d0
                beq     .exit
                lea     IOREQ_SZ(a3),a0
                tst.b   LF_LAST(sp)
                bne.s   .comp_last
                cmp.l   #OFS_ST_USERDIR,OFSB_SECTYPE(a0) ; composant intermédiaire -> doit être un RÉPERTOIRE
                bne     .exit
                bra     .nextcomp                    ; descend : d4 = ce userdir, composant suivant
.comp_last:
                cmp.l   #OFS_ST_FILE,OFSB_SECTYPE(a0)    ; dernier composant -> doit être un FICHIER
                bne     .exit
                ; --- lire la chaîne de data (le file header est déjà dans le buffer) ---
                move.l  OFSB_FIRSTDATA(a0),d2        ; premier data block
                move.w  #OFS_NBLK,d5                 ; cap chaîne data
.dloop:
                bsr     ofs_blk_valid
                beq.s   .exit                        ; 0 / invalide -> fin
                move.l  d2,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .exit
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_DATA,OFSB_TYPE(a0)    ; valider : data block OFS
                bne.s   .exit
                move.l  OFSB_DSIZE(a0),d0            ; d0 = data_size
                cmp.l   #OFS_DMAX,d0
                bhi.s   .exit                        ; data_size absurde -> stop
                cmp.l   d7,d0
                bhi.s   .exit                        ; dépasserait le buffer (garde) -> stop
                lea     OFSB_DATA(a0),a0             ; a0 = données (@+24)
                move.l  d0,d1
                beq.s   .dnext                       ; bloc vide
                subq.l  #1,d1
.dcopy:
                move.b  (a0)+,(a5)+                  ; copie data_size octets (<=488)
                dbra    d1,.dcopy
.dnext:
                add.l   d0,d6                        ; total += data_size
                sub.l   d0,d7                        ; max restant -= data_size
                ifne    OFS_NO_DATACHAIN
                bra.s   .exit                        ; RED : ne suit PAS next_data -> seul le 1er data block lu
                endc
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_NEXT(a0),d2             ; prochain data block
                subq.w  #1,d5
                bne.s   .dloop
.exit:
                move.l  a3,a1                        ; libère ioreq + block buffer
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d6,d0                        ; retour = total lu
                bra.s   .ret
.fail_nofree:
                moveq   #0,d0
.ret:
                lea     OFS_FRAME(sp),sp             ; libère le frame local
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ofs_dir_lookup(d4=bloc répertoire, a4=composant NUL-term ; a2=trackdisk, a3=ioreq, a6=SysBase) -> d0 = bloc
; header du nom (fichier OU sous-rép) | 0. Match par NOM (unique dans un répertoire) ; le driver vérifie le
; sectype. ht_size : lu du bloc (root=72) ; 0 (userdir) ou >=128 (corrompu) -> défaut OFS_HTDEF. Préserve
; d4/d6/d7/a4/a5 ; clobbe d0-d3/d5/a0/a1 (ofs_read_block préserve d2-d7/a2-a5).
ofs_dir_lookup:
                move.l  d4,d0
                bsr     ofs_read_block               ; lit le bloc répertoire courant
                tst.l   d0
                beq.s   .dl_fail
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_SHORT,OFSB_TYPE(a0)
                bne.s   .dl_fail
                move.l  OFSB_HTSIZE(a0),d3           ; hash_table_size stocké
                beq.s   .dl_htdef                    ; 0 (userdir : long[3] non peuplé) -> défaut
                cmp.l   #OFS_HTMAX,d3
                blo.s   .dl_hthave
.dl_htdef:
                moveq   #OFS_HTDEF,d3                ; 72 = BSIZE/4 - 56
.dl_hthave:
                bsr     ofs_hash                     ; a4=comp, d3=ht_size -> d1 = idx
                lea     IOREQ_SZ(a3),a0
                lsl.l   #2,d1                        ; idx * 4 (octets)
                lea     OFSB_HASHTAB(a0),a0
                move.l  0(a0,d1.l),d2                ; d2 = header block courant (bucket)
                move.w  #OFS_NBLK,d5                 ; cap anti-boucle
.dl_chain:
                bsr     ofs_blk_valid
                beq.s   .dl_fail                     ; bloc 0 / hors [2,1760) -> fin de chaîne, pas trouvé
                move.l  d2,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .dl_fail
                lea     IOREQ_SZ(a3),a0
                lea     OFSB_NAME(a0),a1             ; nom BCPL stocké
                move.l  a4,a0                        ; query = composant
                bsr     ofs_namecmp                  ; Z=1 si égal (insensible casse)
                beq.s   .dl_hit
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_HASHCHAIN(a0),d2        ; prochain header du même bucket
                subq.w  #1,d5
                bne.s   .dl_chain
.dl_fail:
                moveq   #0,d0
                rts
.dl_hit:
                move.l  d2,d0                        ; bloc header trouvé (nom OK ; sectype vérifié par le driver)
                rts

; ofs_split(a0=curseur path, a4=buffer dest) -> copie le composant [a0..] (jusqu'à '/' ou NUL) dans (a4) et
; NUL-termine ; a0 avance APRÈS le '/' (ou reste au NUL) ; d0 = 1 si dernier composant (terminé par NUL), 0 sinon.
; Cap OFS_COMPMAX-1 chars (le reste du composant trop long est avalé). Clobbe d0/d1/a0/a1 (a4 préservé).
; RED OFS_NO_SUBDIR : '/' traité comme char normal -> le chemin entier devient un seul composant (dernier).
ofs_split:
                move.l  a4,a1                        ; a1 = dest (a4 préservé)
                moveq   #OFS_COMPMAX-1,d1            ; cap
.sp_lp:
                move.b  (a0),d0
                beq.s   .sp_nul
                ifeq    OFS_NO_SUBDIR
                cmp.b   #'/',d0
                beq.s   .sp_slash
                endc
                move.b  d0,(a1)+
                addq.l  #1,a0
                subq.l  #1,d1
                bne.s   .sp_lp
.sp_eat:                                             ; cap atteint : avale le reste du composant (jusqu'à '/' ou NUL)
                move.b  (a0),d0
                beq.s   .sp_nul
                ifeq    OFS_NO_SUBDIR
                cmp.b   #'/',d0
                beq.s   .sp_slash
                endc
                addq.l  #1,a0
                bra.s   .sp_eat
.sp_slash:
                addq.l  #1,a0                        ; passe le '/'
                clr.b   (a1)                         ; NUL-termine le composant
                moveq   #0,d0                        ; pas le dernier
                rts
.sp_nul:
                clr.b   (a1)                         ; NUL-termine le composant
                moveq   #1,d0                        ; dernier composant (terminé par NUL)
                rts

; ofs_read_block(d0=block num, a2=trackdisk, a3=ioreq, a6=SysBase) -> d0 = 1 OK / 0 KO ; remplit a3+IOREQ_SZ.
; N'utilise que d0/d1/a0/a1 comme scratch (BeginIO préserve d2-d7/a2-a5) -> l'état de boucle de l'appelant survit.
ofs_read_block:
                lsl.l   #8,d0
                lsl.l   #1,d0                        ; offset = block * 512 (< 901120, pas d'overflow 32 bits)
                move.l  a2,IO_DEVICE(a3)
                move.w  #CMD_READ,IO_COMMAND(a3)
                move.l  #OFS_BSIZE,IO_LENGTH(a3)
                lea     IOREQ_SZ(a3),a0
                move.l  a0,IO_DATA(a3)
                move.l  d0,IO_OFFSET(a3)
                move.b  #IOF_QUICK,IO_FLAGS(a3)
                clr.l   IO_ACTUAL(a3)
                move.l  a6,-(sp)                     ; BeginIO via le vecteur -30 (a6=trackdisk, a1=ioreq)
                move.l  a2,a6
                move.l  a3,a1
                jsr     -30(a6)
                move.l  (sp)+,a6
                tst.b   IO_ERROR(a3)
                bne.s   .rb_fail
                cmp.l   #OFS_BSIZE,IO_ACTUAL(a3)
                bne.s   .rb_fail
                moveq   #1,d0
                rts
.rb_fail:
                moveq   #0,d0
                rts

; ofs_blk_valid(d2=block) -> Z=1 si INVALIDE (0 ou hors [2,1760)). Clobbe d0 seulement (flags via moveq).
ofs_blk_valid:
                cmp.l   #2,d2
                blo.s   .bv_inv
                cmp.l   #OFS_NBLK,d2
                bhs.s   .bv_inv
                moveq   #-1,d0                       ; valide -> Z=0
                rts
.bv_inv:
                moveq   #0,d0                        ; invalide -> Z=1
                rts

; ofs_hash(a4=name NUL-terminé, d3=ht_size) -> d1 = idx. Clobbe d0/d1/a0. h=len ; h=(h*13+toupper(c))&$7FF ;
; idx = h mod ht_size. toupper = ASCII a-z seulement (OFS non-international DOS\0).
ofs_hash:
                move.l  a4,a0
                moveq   #0,d1                        ; d1 = h (initialisé à la longueur)
.hlen:
                tst.b   (a0)+
                beq.s   .hgo
                addq.l  #1,d1
                bra.s   .hlen
.hgo:
                move.l  a4,a0                        ; relire depuis le début (d1 = len = h initial)
.hc:
                moveq   #0,d0
                move.b  (a0)+,d0
                beq.s   .hdone
                cmp.b   #'a',d0
                blo.s   .hnoup
                cmp.b   #'z',d0
                bhi.s   .hnoup
                sub.b   #$20,d0                      ; toupper
.hnoup:
                mulu    #13,d1                       ; h*13 (h<=$7FF -> <26624, tient dans un mot)
                add.l   d0,d1
                and.l   #$7FF,d1
                bra.s   .hc
.hdone:
                divu.w  d3,d1                        ; d1 / ht_size -> reste dans le mot haut
                clr.w   d1
                swap    d1                           ; d1 = reste = idx
                rts

; ofs_namecmp(a0=query NUL-terminé, a1=nom BCPL [octet longueur + chars]) -> Z=1 si égal (insensible casse ASCII).
; Préserve d2/a0/a1 (movem ne touche pas le CCR -> le Z du dernier moveq survit au rts).
ofs_namecmp:
                movem.l d2/a0/a1,-(sp)
                moveq   #0,d1
                move.b  (a1)+,d1                     ; d1 = longueur stockée
.nc_loop:
                tst.l   d1
                beq.s   .nc_qend                     ; nom stocké épuisé
                moveq   #0,d0
                move.b  (a0)+,d0                     ; char query
                beq.s   .nc_ne                       ; query plus courte -> différent
                cmp.b   #'a',d0
                blo.s   .nc_u0
                cmp.b   #'z',d0
                bhi.s   .nc_u0
                sub.b   #$20,d0
.nc_u0:
                moveq   #0,d2
                move.b  (a1)+,d2                     ; char stocké
                cmp.b   #'a',d2
                blo.s   .nc_u1
                cmp.b   #'z',d2
                bhi.s   .nc_u1
                sub.b   #$20,d2
.nc_u1:
                cmp.b   d0,d2
                bne.s   .nc_ne
                subq.l  #1,d1
                bra.s   .nc_loop
.nc_qend:
                tst.b   (a0)                         ; stocké fini -> query doit être au NUL
                bne.s   .nc_ne
                moveq   #0,d0                        ; égal -> pose Z=1
                bra.s   .nc_ret
.nc_ne:
                moveq   #1,d0                        ; différent -> pose Z=0
.nc_ret:
                movem.l (sp)+,d2/a0/a1               ; movem ne modifie pas le CCR
                rts

; ofs_fib_fill(d0=bloc header, a1=fib ; bloc DÉJÀ lu dans IOREQ_SZ(a3)) : remplit le FileInfoBlock.
; DiskKey = bloc ; DirEntryType = sec_type (<0 fichier, >0 répertoire) ; Size = byte_size@324 si fichier sinon 0 ;
; FileName = nom BCPL converti en C-string (cappé 30 chars, borne anti-corruption). Clobbe d0/d1/a0/a1 (a1 réassigné).
ofs_fib_fill:
                move.l  d0,FIB_DISKKEY(a1)
                lea     IOREQ_SZ(a3),a0              ; a0 = buffer du bloc header
                move.l  OFSB_SECTYPE(a0),d0          ; type secondaire
                move.l  d0,FIB_DIRENTRYTYPE(a1)
                tst.l   d0
                bpl.s   .ff_dir                      ; >= 0 -> répertoire (ST_ROOT/USERDIR) : taille 0
                move.l  OFSB_FILESIZE(a0),FIB_SIZE(a1)   ; fichier : byte_size
                bra.s   .ff_name
.ff_dir:
                clr.l   FIB_SIZE(a1)
.ff_name:
                lea     OFSB_NAME(a0),a0             ; a0 = nom BCPL (octet longueur + chars)
                moveq   #0,d0
                move.b  (a0)+,d0                     ; longueur stockée
                lea     FIB_FILENAME(a1),a1          ; dest (a1 réassigné -> plus de champ fib base après)
                cmp.l   #30,d0                       ; borne (nom AmigaDOS <= 30 ; garde anti-corruption)
                bls.s   .ff_ncap
                moveq   #30,d0
.ff_ncap:
                move.l  d0,d1
                beq.s   .ff_nend
.ff_ncpy:
                move.b  (a0)+,(a1)+
                subq.l  #1,d1
                bne.s   .ff_ncpy
.ff_nend:
                clr.b   (a1)                         ; NUL-termine la C-string
                rts

; ofs_name_to_block(a0=chemin NUL-term, a6=SysBase) -> d0 = bloc header de l'objet | 0. Résout un chemin : préfixe
; « xxx: » ignoré (un seul volume DF0:) ; vide / « : » -> racine (OFS_ROOTBLK). Sinon traverse les sous-répertoires
; USERDIR ('/'-séparés) comme ofs_read_file, MAIS le composant FINAL peut être un fichier OU un répertoire (Lock
; d'un dir autorisé). Réutilise ofs_split / ofs_dir_lookup / ofs_read_block. Setup trackdisk/ioreq interne.
ofs_name_to_block:
                movem.l d2-d7/a2-a5,-(sp)
                move.l  a0,a1                        ; a1 = scan de préfixe « xxx: »
.n2b_colon:
                move.b  (a1)+,d0
                beq.s   .n2b_nocolon                 ; NUL -> pas de ':'
                cmp.b   #':',d0
                bne.s   .n2b_colon
                move.l  a1,a0                         ; a0 = juste après le ':'
.n2b_nocolon:
                tst.b   (a0)
                bne.s   .n2b_resolve
                move.l  #OFS_ROOTBLK,d0              ; chemin vide (ou « : ») -> racine (pas d'alloc)
                movem.l (sp)+,d2-d7/a2-a5
                rts
.n2b_resolve:
                lea     -OFS_FRAME(sp),sp            ; frame local (comp + curseur path + flag dernier)
                move.l  a0,LF_PATHCUR(sp)
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .n2b_fail                    ; pas de trackdisk (rien alloué)
                move.l  d0,a2
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .n2b_fail                    ; pas de RAM (rien à free)
                move.l  d0,a3
                move.l  #OFS_ROOTBLK,d4             ; d4 = répertoire courant (racine)
.n2b_nextcomp:
                lea     LF_COMP(sp),a4
                move.l  LF_PATHCUR(sp),a0
                bsr     ofs_split                    ; (a4) = composant ; a0 avance ; d0 = 1 si dernier
                move.l  a0,LF_PATHCUR(sp)
                move.b  d0,LF_LAST(sp)
                bsr     ofs_dir_lookup               ; (d4, a4) -> d0 = bloc | 0 (préserve d4/a4)
                tst.l   d0
                beq.s   .n2b_notfound                ; composant introuvable
                move.l  d0,d4                         ; d4 = bloc du composant
                tst.b   LF_LAST(sp)
                bne.s   .n2b_hit                      ; dernier -> objet final (fichier OU dir)
                move.l  d4,d0                         ; intermédiaire : doit être un USERDIR
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .n2b_notfound
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_ST_USERDIR,OFSB_SECTYPE(a0)
                bne.s   .n2b_notfound                ; pas un sous-rép -> chemin invalide
                bra.s   .n2b_nextcomp
.n2b_hit:
                move.l  d4,d7                         ; d7 = bloc résultat
                bra.s   .n2b_free
.n2b_notfound:
                moveq   #0,d7
.n2b_free:
                move.l  a3,a1                         ; libère ioreq + buffer
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d7,d0
                lea     OFS_FRAME(sp),sp
                movem.l (sp)+,d2-d7/a2-a5
                rts
.n2b_fail:
                moveq   #0,d0                         ; échec avant/pendant alloc -> rien à libérer
                lea     OFS_FRAME(sp),sp
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ofs_fill_fib(d0=bloc header, a1=fib, a6=SysBase) -> d0 = 1 OK / 0 KO. Lit le bloc puis remplit le FIB
; (ofs_fib_fill). Setup trackdisk/ioreq interne. Le reset du curseur d'énumération est à la charge de l'appelant.
ofs_fill_fib:
                movem.l d2-d7/a2-a5,-(sp)
                moveq   #0,d7                         ; résultat par défaut
                move.l  d0,d4                         ; d4 = bloc
                move.l  a1,a5                         ; a5 = fib
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq.s   .fib_ret                     ; pas de trackdisk (rien alloué)
                move.l  d0,a2
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .fib_ret                     ; pas de RAM (rien à free)
                move.l  d0,a3
                move.l  d4,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .fib_free                    ; lecture KO
                move.l  d4,d0
                move.l  a5,a1
                bsr     ofs_fib_fill
                moveq   #1,d7
.fib_free:
                move.l  a3,a1
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
.fib_ret:
                move.l  d7,d0
                movem.l (sp)+,d2-d7/a2-a5
                rts

; ofs_dir_next(d0=dirblock, d1=bucket, d2=chain, a1=fib, a6=SysBase) -> d0 = 1 trouvé / 0 fin ; d1 = bucket màj,
; d2 = chain màj (curseur à repasser tel quel au prochain appel). Parcourt la chaîne hash courante puis avance de
; bucket en bucket dans la hashtable du répertoire ; remplit le FIB de l'entrée trouvée. Setup trackdisk/ioreq
; interne. Réutilise ofs_read_block / ofs_blk_valid / ofs_fib_fill. Préserve d3-d7/a2-a5 ; retours en d0/d1/d2
; (hors movem). RED OFS_NO_DIRNEXT : renvoie found=0 d'emblée (ExNext ne trouve jamais rien).
ofs_dir_next:
                movem.l d3-d7/a2-a5,-(sp)
                move.l  d0,d4                         ; d4 = dirblock
                move.l  d1,d5                         ; d5 = bucket
                move.l  d2,d6                         ; d6 = chain
                move.l  a1,a5                         ; a5 = fib
                ifne    OFS_NO_DIRNEXT
                moveq   #0,d0                         ; RED : fin immédiate (rien alloué)
                move.l  d5,d1
                move.l  d6,d2
                movem.l (sp)+,d3-d7/a2-a5
                rts
                endc
                lea     EB_DEVICELIST(a6),a0
                lea     ofs_td_name(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .dn_noalloc
                move.l  d0,a2
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .dn_noalloc
                move.l  d0,a3
.dn_loop:
                tst.l   d6                            ; chaîne courante non vide ?
                beq.s   .dn_advbucket
                move.l  d6,d2                         ; valider le bloc de chaîne
                bsr     ofs_blk_valid
                beq.s   .dn_chainend                  ; invalide -> fin de chaîne -> avance bucket
                move.l  d6,d0
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .dn_end_notfound
                lea     IOREQ_SZ(a3),a0
                move.l  OFSB_HASHCHAIN(a0),d3         ; d3 = chaîne suivante (avant que fib_fill ne touche le buffer)
                move.l  d6,d0                         ; bloc courant = DiskKey
                move.l  a5,a1
                bsr     ofs_fib_fill
                move.l  d3,d6                         ; le curseur chaîne avance
                moveq   #1,d7                         ; trouvé
                bra.s   .dn_end
.dn_chainend:
                moveq   #0,d6                         ; force l'avance de bucket
.dn_advbucket:
                move.l  d4,d0                         ; (re)lire le dir block : ht_size + hashtab[bucket]
                bsr     ofs_read_block
                tst.l   d0
                beq.s   .dn_end_notfound
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_SHORT,OFSB_TYPE(a0)
                bne.s   .dn_end_notfound              ; pas un bloc répertoire
                move.l  OFSB_HTSIZE(a0),d7            ; ht_size (root stocké ; userdir long[3]=0 -> défaut)
                beq.s   .dn_htdef
                cmp.l   #OFS_HTMAX,d7
                blo.s   .dn_scan
.dn_htdef:
                moveq   #OFS_HTDEF,d7
.dn_scan:
                cmp.l   d7,d5                         ; bucket >= ht_size ?
                bhs.s   .dn_end_notfound              ; buckets épuisés -> fin d'énumération
                lea     IOREQ_SZ(a3),a0
                move.l  d5,d0
                lsl.l   #2,d0
                lea     OFSB_HASHTAB(a0),a0
                move.l  0(a0,d0.l),d6                 ; chaîne = hashtab[bucket]
                addq.l  #1,d5                         ; bucket++ (ne re-scanne pas le bucket courant)
                tst.l   d6
                beq.s   .dn_scan                      ; bucket vide -> suivant
                bra.s   .dn_loop                      ; chaîne non vide -> émettre
.dn_end_notfound:
                moveq   #0,d7
.dn_end:
                move.l  a3,a1                         ; libère ioreq + buffer
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
                move.l  d7,d0                         ; found
                move.l  d5,d1                         ; bucket màj
                move.l  d6,d2                         ; chain màj
                movem.l (sp)+,d3-d7/a2-a5
                rts
.dn_noalloc:
                moveq   #0,d0
                move.l  d5,d1
                move.l  d6,d2
                movem.l (sp)+,d3-d7/a2-a5
                rts

ofs_td_name:
                dc.b    "trackdisk.device",0
                even
