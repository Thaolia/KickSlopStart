; src/dos/handler.s — process file-handler DF0: (D3b). Corps d'un Process (créé par proc_create) qui boucle
; WaitPort/GetMsg sur son pr_MsgPort et sert les DOS packets : ACTION_FINDINPUT/READ/SEEK/END + LOCATE_OBJECT/
; FREE_LOCK/EXAMINE_OBJECT/EXAMINE_NEXT, en s'appuyant sur la machinerie OFS (ofs_stream_* / ofs_name_to_block /
; ofs_fill_fib / ofs_dir_next). Machinerie INTERNE (pas de dos.library user-facing = D3c).
;
; Protocole (docs/analysis/dos-v34-spec.md §2) : msg->ln_Name -> DosPacket. Sur FINDINPUT (ARG1=BPTR FileHandle,
; ARG2=lock du répertoire de départ, ARG3=BSTR nom) le handler alloue un état de STREAMING (SS_*, ofs.i : un seul AllocMem incluant
; l'ioreq + un block buffer de 512 o), l'ouvre via ofs_stream_open (résout le chemin -> premier data block, SANS
; lire le fichier), pose fh_Arg1 = état dans le FileHandle (BADDR(ARG1)), renvoie DOSTRUE. READ (ARG1=fh_Arg1,
; ARG2=dest, ARG3=len) lit INCRÉMENTALEMENT via ofs_stream_read (data-block par data-block, le curseur avance dans
; l'état ; RES1=octets, 0=EOF). SEEK repositionne via ofs_stream_seek (rend l'ancienne position). END libère l'état.
; STREAMING RÉEL : plus de buffer whole-file -> aucun cap de taille de fichier (empreinte O(1) = 512 o par handle).
; Piste IMPLÉMENTATION (« clean ») : spec analyse + AutoDocs exec. AUCUNE lecture ROM.

                include "exec.i"
                include "ofs.i"
                include "dospkt.i"
                include "dos.i"

                xdef    dos_handler_df0
                xref    ofs_name_to_block    ; LOCATE_OBJECT : chemin -> bloc
                xref    ofs_fill_fib         ; EXAMINE_OBJECT : bloc -> FIB
                xref    ofs_dir_next         ; EXAMINE_NEXT : entrée suivante du répertoire
                xref    ofs_stream_open      ; FINDINPUT : ouvre un fichier en streaming
                xref    ofs_stream_read      ; READ : lecture incrémentale data-block par data-block
                xref    ofs_stream_seek      ; SEEK : repositionne le curseur de streaming
                xref    ow_create            ; écriture OFS (ofswrite.s)
                xref    ow_delete
                xref    ow_rename
                xref    ow_setfield
                xref    ow_diskinfo
                xref    ws_open
                xref    ws_write
                xref    ws_close
                xref    ofs_read_block       ; hnd_bootclock : lecture du bloc racine
                xref    timer_now            ; heure système (exec/timer.s)
                xref    timer_setnow

ACTION_MORE_CACHE EQU 18             ; AddBuffers : ajoute des tampons au filesystem
WS_MAGICV       EQU $57524954        ; tête d'un état d'écriture (ofswrite.s) ; un état de lecture commence par un APTR
HND_NAMEBUF     EQU 112              ; chaîne C d'un nom reçu en BSTR (pile)

; dos_handler_df0 : corps du process. GPR à zéro à l'entrée (frame AddTask) -> recharge SysBase.
; a2 = pr_MsgPort (persistant) ; a3 = Message courant ; a4 = DosPacket courant.
dos_handler_df0:
                move.l  ($4).w,a6
                clr.b   HND_CLOCKED          ; RAM basse non remise à zéro au reset
                move.l  EB_THISTASK(a6),a2
                lea     PR_MSGPORT(a2),a2    ; a2 = son propre pr_MsgPort
.hl:
                move.l  a2,a0
                jsr     LVO_WAITPORT(a6)     ; bloque jusqu'à un packet
                move.l  a2,a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .hl
                tst.b   HND_CLOCKED          ; premier packet = montage du disque de boot
                bne.s   .hl_clk
                st      HND_CLOCKED
                bsr     hnd_bootclock
.hl_clk:
                move.l  d0,a3                ; a3 = Message
                move.l  LN_NAME(a3),a4       ; a4 = DosPacket (convention : msg->ln_Name)
                clr.l   DP_RES2(a4)
                move.l  DP_TYPE(a4),d0
                cmp.l   #ACTION_FINDINPUT,d0
                beq     .findinput
                cmp.l   #ACTION_READ,d0
                beq     .read
                cmp.l   #ACTION_END,d0
                beq     .end
                cmp.l   #ACTION_SEEK,d0
                beq     .seek
                cmp.l   #ACTION_LOCATE_OBJECT,d0
                beq     .locate
                cmp.l   #ACTION_FREE_LOCK,d0
                beq     .freelock
                cmp.l   #ACTION_EXAMINE_OBJECT,d0
                beq     .examine
                cmp.l   #ACTION_EXAMINE_NEXT,d0
                beq     .exnext
                cmp.l   #ACTION_MORE_CACHE,d0
                beq     .morecache
                cmp.l   #ACTION_PARENT,d0
                beq     .parent
                cmp.l   #ACTION_COPY_DIR,d0
                beq     .copydir
                cmp.l   #ACTION_FINDOUTPUT,d0
                beq     .findoutput
                cmp.l   #ACTION_FINDUPDATE,d0
                beq     .findupdate
                cmp.l   #ACTION_WRITE,d0
                beq     .write
                cmp.l   #ACTION_DELETE_OBJECT,d0
                beq     .delete
                cmp.l   #ACTION_RENAME_OBJECT,d0
                beq     .rename
                cmp.l   #ACTION_CREATE_DIR,d0
                beq     .createdir
                cmp.l   #ACTION_SET_PROTECT,d0
                beq     .setprot
                cmp.l   #ACTION_SET_COMMENT,d0
                beq     .setcomment
                cmp.l   #ACTION_DISK_INFO,d0
                beq     .diskinfo
                cmp.l   #ACTION_INFO,d0
                beq     .info
                move.l  #DOSFALSE,DP_RES1(a4)         ; action inconnue
                move.l  #ERROR_ACTION_NOT_KNOWN,DP_RES2(a4)
                bra     .reply

.findinput:
                move.l  #SS_ALLOC,d0                 ; état de streaming (champs + ioreq + block buffer 512 o)
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .fi_fail
                move.l  d0,d6                        ; d6 = état (préservé par ofs_stream_open)
                ; convertir le BSTR nom (ARG3) en C-string sur la pile pour ofs_stream_open
                lea     -112(sp),sp
                move.l  DP_ARG3(a4),d0
                lsl.l   #2,d0                         ; BADDR(ARG3) = &BSTR (len + chars)
                move.l  d0,a0
                move.l  sp,a1
                moveq   #0,d1
                move.b  (a0)+,d1                      ; longueur BCPL
.fi_ncpy:
                tst.l   d1
                beq.s   .fi_ndone
                move.b  (a0)+,(a1)+
                subq.l  #1,d1
                bra.s   .fi_ncpy
.fi_ndone:
                clr.b   (a1)                          ; termine en C-string
                move.l  DP_ARG2(a4),d0                ; lock du répertoire de départ (0 = racine)
                bsr     hnd_lockkey                    ; d0 = bloc du répertoire | 0
                move.l  sp,a0                         ; a0 = chemin, a1 = état
                move.l  d6,a1
                jsr     ofs_stream_open                ; d0 = 1/0 (résout + init curseur, SANS lire le fichier)
                lea     112(sp),sp                    ; restaure la pile (C-string consommée)
                tst.l   d0
                beq.s   .fi_fail_state                ; introuvable / pas un fichier
                move.l  DP_ARG1(a4),d0                ; FileHandle = BADDR(ARG1)
                lsl.l   #2,d0
                move.l  d0,a1
                move.l  d6,FH_ARG1(a1)                ; fh_Arg1 = clé = état de streaming
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.fi_fail_state:
                move.l  #ERROR_OBJECT_NOT_FOUND,DP_RES2(a4)  ; introuvable -> IoErr (d3f en dépend)
                move.l  d6,a1
                move.l  #SS_ALLOC,d0
                jsr     LVO_FREEMEM(a6)
.fi_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                bra     .reply

.read:
                ifne    D3B_NO_READ
                clr.l   DP_RES1(a4)                   ; RED D3B_NO_READ : ne sert PAS READ -> EOF immédiat
                bra     .reply
                endc
                move.l  DP_ARG1(a4),a1
                cmp.l   #WS_MAGICV,(a1)
                beq     .rw_wrong                     ; fichier ouvert en écriture
                move.l  a2,-(sp)                       ; a2 = pr_MsgPort du handler : sauvé (ofs_stream_read prend dest en a2)
                move.l  DP_ARG1(a4),a1                ; a1 = état de streaming
                move.l  DP_ARG2(a4),a2                ; a2 = dest
                move.l  DP_ARG3(a4),d0                ; d0 = len demandé
                jsr     ofs_stream_read                ; d0 = octets lus (0 = EOF) ; curseur avancé dans l'état
                move.l  d0,DP_RES1(a4)
                move.l  (sp)+,a2                       ; restaure le port du handler
                bra     .reply

.seek:                                                ; Seek(ARG1=état, ARG2=position, ARG3=mode) -> RES1 = ancienne pos
                ifne    HND_NO_SEEK
                move.l  DP_ARG1(a4),a1                ; RED HND_NO_SEEK : lit l'état mais NE repositionne PAS
                move.l  SS_POS(a1),DP_RES1(a4)
                bra     .reply
                endc
                move.l  DP_ARG1(a4),a1                ; a1 = état
                cmp.l   #WS_MAGICV,(a1)
                beq     .sk_err                       ; pas de repositionnement en écriture
                move.l  SS_POS(a1),d3                 ; d3 = ancienne position (valeur de retour)
                move.l  DP_ARG2(a4),d1                ; position (signée)
                move.l  DP_ARG3(a4),d2                ; mode (OFFSET_BEGINNING -1 / CURRENT 0 / END 1)
                tst.l   d2
                blt.s   .sk_begin
                beq.s   .sk_current
                move.l  SS_SIZE(a1),d0                ; END : taille + position
                add.l   d1,d0
                bra.s   .sk_bounds
.sk_begin:
                move.l  d1,d0                         ; BEGINNING : position absolue
                bra.s   .sk_bounds
.sk_current:
                move.l  d3,d0                         ; CURRENT : ancienne + position
                add.l   d1,d0
.sk_bounds:
                tst.l   d0
                bmi.s   .sk_err
                cmp.l   SS_SIZE(a1),d0
                bhi.s   .sk_err                       ; hors [0, taille]
                jsr     ofs_stream_seek                ; a1 = état, d0 = cible -> repositionne le curseur (dumb seek)
                move.l  d3,DP_RES1(a4)                ; renvoie l'ANCIENNE position
                bra     .reply
.sk_err:
                move.l  #-1,DP_RES1(a4)
                move.l  #ERROR_SEEK_ERROR,DP_RES2(a4)
                bra     .reply

.locate:                                              ; Lock : (ARG2 BSTR nom, ARG3 mode) -> RES1 = BPTR FileLock
                lea     -112(sp),sp                   ; BSTR nom -> C-string sur la pile
                move.l  DP_ARG2(a4),d0
                lsl.l   #2,d0
                move.l  d0,a0                          ; BADDR(ARG2)
                move.l  sp,a1
                moveq   #0,d1
                move.b  (a0)+,d1                      ; longueur BCPL
.lo_ncpy:
                tst.l   d1
                beq.s   .lo_ndone
                move.b  (a0)+,(a1)+
                subq.l  #1,d1
                bra.s   .lo_ncpy
.lo_ndone:
                clr.b   (a1)                          ; C-string terminée
                move.l  DP_ARG1(a4),d0                ; lock parent (0 = racine)
                bsr     hnd_lockkey
                move.l  sp,a0                          ; a0 = nom
                jsr     ofs_name_to_block              ; d0 = bloc | 0 (a6 = SysBase ; préserve a2/a3/a4)
                lea     112(sp),sp
                tst.l   d0
                beq.s   .lo_fail                       ; objet introuvable
                move.l  d0,d2                          ; d2 = bloc (préservé par AllocMem)
                move.l  #FL_SIZEOF,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .lo_fail                       ; pas de RAM
                move.l  d0,a0                          ; a0 = FileLock
                move.l  d2,FL_KEY(a0)                 ; bloc locké
                move.l  DP_ARG3(a4),FL_ACCESS(a0)     ; mode (SHARED/EXCLUSIVE)
                move.l  a2,FL_TASK(a0)                ; port du handler (= notre pr_MsgPort) -> source UnLock/Examine
                move.l  DOS_DOSBASE,a1
                move.l  DL_VOLUME(a1),FL_VOLUME(a0)   ; nœud volume (0 avant sa création par le CLI initial)
                move.l  d0,d1                          ; FL_LINK/curseur = 0 (MEMF_CLEAR)
                lsr.l   #2,d1                          ; BPTR(lock)
                move.l  d1,DP_RES1(a4)
                bra     .reply
.lo_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  #ERROR_OBJECT_NOT_FOUND,DP_RES2(a4)
                bra     .reply

.freelock:                                            ; UnLock : (ARG1 BPTR lock) -> libère
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .frl_ok                        ; lock 0 -> no-op
                move.l  d0,a1
                move.l  #FL_SIZEOF,d0
                jsr     LVO_FREEMEM(a6)
.frl_ok:
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply

.examine:                                             ; Examine : (ARG1 BPTR lock, ARG2 BPTR fib) -> remplit le FIB
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .ex_fail
                move.l  d0,a0                          ; a0 = FileLock
                move.l  FL_KEY(a0),d0                 ; bloc de l'objet locké
                clr.l   FLP_BUCKET(a0)                ; reset du curseur d'énumération (Examine -> début)
                clr.l   FLP_CHAIN(a0)
                move.l  DP_ARG2(a4),d1
                lsl.l   #2,d1
                move.l  d1,a1                          ; a1 = fib
                jsr     ofs_fill_fib                   ; d0 = 1/0 (préserve a2/a3/a4/a6)
                tst.l   d0
                beq.s   .ex_fail
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.ex_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  #ERROR_OBJECT_NOT_FOUND,DP_RES2(a4)
                bra     .reply

.exnext:                                              ; ExNext : (ARG1 BPTR lock, ARG2 BPTR fib) -> entrée suivante
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .exn_end
                move.l  d0,a0                          ; a0 = FileLock
                move.l  FL_KEY(a0),d0                 ; bloc répertoire
                move.l  FLP_BUCKET(a0),d1             ; curseur bucket
                move.l  FLP_CHAIN(a0),d2              ; curseur chaîne
                move.l  DP_ARG2(a4),d3
                lsl.l   #2,d3
                move.l  d3,a1                          ; a1 = fib
                move.l  a0,-(sp)                       ; ofs_dir_next ne préserve PAS a0 -> sauver le lock
                jsr     ofs_dir_next                   ; d0=found, d1=bucket màj, d2=chain màj (préserve a2-a5)
                move.l  (sp)+,a0
                move.l  d1,FLP_BUCKET(a0)             ; réécrit le curseur dans le lock
                move.l  d2,FLP_CHAIN(a0)
                tst.l   d0
                beq.s   .exn_end
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.exn_end:
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  #ERROR_NO_MORE_ENTRIES,DP_RES2(a4)
                bra     .reply

.copydir:                                            ; DupLock : (ARG1 BPTR lock) -> nouveau lock, même bloc
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                tst.l   d0
                bne.s   .cd_key
                move.l  #OFS_ROOTBLK,d0                ; lock 0 = racine
.cd_key:
                move.l  d0,d2
                bra.s   .pa_alloc
.parent:                                             ; ParentDir : (ARG1 BPTR lock) -> lock du parent | 0 (racine)
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                lea     hnd_slash(pc),a0               ; « / » = parent du répertoire de départ
                jsr     ofs_name_to_block
                tst.l   d0
                beq.s   .pa_root                       ; parent de la racine : 0 sans erreur
                move.l  d0,d2
.pa_alloc:                                             ; d2 = bloc -> nouveau FileLock partagé
                move.l  #FL_SIZEOF,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .pa_root
                move.l  d0,a0
                move.l  d2,FL_KEY(a0)
                move.l  #SHARED_LOCK,FL_ACCESS(a0)
                move.l  a2,FL_TASK(a0)
                move.l  DOS_DOSBASE,a1
                move.l  DL_VOLUME(a1),FL_VOLUME(a0)
                lsr.l   #2,d0
                move.l  d0,DP_RES1(a4)
                bra     .reply
.pa_root:
                clr.l   DP_RES1(a4)
                bra     .reply

.morecache:                                          ; AddBuffers : pas de cache de blocs FS (le trackdisk garde la piste)
                move.l  #DOSTRUE,DP_RES1(a4)          ; -> accepté sans effet
                bra     .reply

.end:
                move.l  DP_ARG1(a4),a1                ; a1 = état de streaming (un seul AllocMem)
                cmp.l   #WS_MAGICV,(a1)
                beq.s   .end_w
                move.l  #SS_ALLOC,d0
                jsr     LVO_FREEMEM(a6)               ; libère l'état (ioreq + block buffer inclus)
                move.l  #DOSTRUE,DP_RES1(a4)
.reply:
                move.l  a3,a1
                jsr     LVO_REPLYMSG(a6)              ; renvoie au mn_ReplyPort de l'appelant
                bra     .hl
.end_w:
                jsr     ws_close                       ; données, extension, header, bitmap écrits ; état libéré
                move.l  d0,DP_RES1(a4)
                bne.s   .reply
                move.l  #ERROR_DISK_WRITE_PROTECTED,DP_RES2(a4)
                bra.s   .reply
.rw_wrong:
                move.l  #-1,DP_RES1(a4)
                move.l  #ERROR_OBJECT_WRONG_TYPE,DP_RES2(a4)
                bra.s   .reply

; --- écriture (ofswrite.s) ---
.findupdate:                                         ; fichier existant -> lecture ; sinon créé comme FINDOUTPUT
                lea     -HND_NAMEBUF(sp),sp
                move.l  DP_ARG3(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG2(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                jsr     ofs_name_to_block
                lea     HND_NAMEBUF(sp),sp
                tst.l   d0
                bne     .findinput
.findoutput:                                         ; (ARG1 fh, ARG2 lock, ARG3 BSTR nom) : fichier créé ou remplacé
                lea     -HND_NAMEBUF(sp),sp
                move.l  DP_ARG3(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG2(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                jsr     ws_open                        ; d0 = état | 0, d1 = erreur
                lea     HND_NAMEBUF(sp),sp
                tst.l   d0
                beq     .w_fail
                move.l  DP_ARG1(a4),d1
                lsl.l   #2,d1
                move.l  d1,a1
                move.l  d0,FH_ARG1(a1)
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.write:                                              ; (ARG1 état, ARG2 données, ARG3 longueur) -> RES1 = longueur | -1
                move.l  DP_ARG1(a4),a1
                cmp.l   #WS_MAGICV,(a1)
                bne     .rw_wrong                     ; fichier ouvert en lecture
                move.l  DP_ARG2(a4),a0
                move.l  DP_ARG3(a4),d0
                jsr     ws_write
                move.l  d0,DP_RES1(a4)
                move.l  d1,DP_RES2(a4)
                bra     .reply
.delete:                                             ; (ARG1 lock, ARG2 BSTR nom)
                lea     -HND_NAMEBUF(sp),sp
                move.l  DP_ARG2(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                jsr     ow_delete
                bra     .w_res
.rename:                                             ; (ARG1 lock, ARG2 BSTR ancien, ARG3 lock, ARG4 BSTR nouveau)
                lea     -2*HND_NAMEBUF(sp),sp
                move.l  DP_ARG2(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG4(a4),d0
                lea     HND_NAMEBUF(sp),a1
                bsr     hnd_cstr
                move.l  DP_ARG3(a4),d0
                bsr     hnd_lockkey
                move.l  d0,d1
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                lea     HND_NAMEBUF(sp),a1
                jsr     ow_rename
                lea     HND_NAMEBUF(sp),sp
                bra     .w_res
.createdir:                                          ; (ARG1 lock, ARG2 BSTR nom) -> RES1 = lock du répertoire
                lea     -HND_NAMEBUF(sp),sp
                move.l  DP_ARG2(a4),d0
                move.l  sp,a1
                bsr     hnd_cstr
                move.l  DP_ARG1(a4),d0
                bsr     hnd_lockkey
                move.l  sp,a0
                moveq   #OFS_ST_USERDIR,d1
                jsr     ow_create
                lea     HND_NAMEBUF(sp),sp
                tst.l   d0
                beq.s   .w_fail
                move.l  d0,d2
                bra     .pa_alloc
.setprot:                                            ; (ARG2 lock, ARG3 BSTR nom, ARG4 masque)
                moveq   #0,d1
                bra.s   .setfield
.setcomment:                                         ; (ARG2 lock, ARG3 BSTR nom, ARG4 BSTR commentaire)
                moveq   #1,d1
.setfield:
                lea     -HND_NAMEBUF(sp),sp
                move.l  d1,-(sp)
                move.l  DP_ARG3(a4),d0
                lea     4(sp),a1
                bsr     hnd_cstr
                move.l  DP_ARG2(a4),d0
                bsr     hnd_lockkey
                move.l  (sp)+,d1
                move.l  sp,a0
                move.l  DP_ARG4(a4),d2
                jsr     ow_setfield
.w_res:
                lea     HND_NAMEBUF(sp),sp
                tst.l   d0
                beq.s   .w_fail
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.w_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  d1,DP_RES2(a4)
                bra     .reply
.info:                                               ; (ARG1 lock, ARG2 BPTR InfoData)
                move.l  DP_ARG2(a4),d0
                bra.s   .di_go
.diskinfo:                                           ; (ARG1 BPTR InfoData)
                move.l  DP_ARG1(a4),d0
.di_go:
                lsl.l   #2,d0
                move.l  d0,a0
                move.l  DOS_DOSBASE,a1
                move.l  DL_VOLUME(a1),a1
                jsr     ow_diskinfo
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply

; hnd_bootclock(a6 = SysBase) : réglage d'heure au montage (spec boot-clock-v34) : l'heure système prend la plus
; récente des deux dates du bloc racine (répertoire racine, longs 105-107 ; disque, longs 118-120) si elle est encore
; au premier jour (horloge jamais réglée) et antérieure à cette date ; jamais reculée. Fait une fois, au premier
; packet (notre handler ne gère pas encore l'insertion d'un autre disque). Préserve tout.
HND_ROOTDATE    EQU 420              ; DateStamp de modification du répertoire racine
HND_DISKDATE    EQU 472              ; DateStamp de modification du disque
hnd_bootclock:
                movem.l d0-d7/a0-a3,-(sp)
                lea     EB_DEVICELIST(a6),a0
                lea     hnd_tdname(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .bc_ret
                move.l  d0,a2
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .bc_ret
                move.l  d0,a3
                move.l  #OFS_ROOTBLK,d0
                jsr     ofs_read_block
                tst.l   d0
                beq.s   .bc_free             ; pas de disque
                lea     IOREQ_SZ(a3),a0
                moveq   #0,d0                ; checksum OFS : somme des 128 longs nulle
                moveq   #OFS_BSIZE/4-1,d1
.bc_sum:
                add.l   (a0)+,d0
                dbra    d1,.bc_sum
                tst.l   d0
                bne.s   .bc_free
                lea     IOREQ_SZ(a3),a0
                cmp.l   #OFS_ST_ROOT,OFSB_SECTYPE(a0)
                bne.s   .bc_free
                lea     HND_ROOTDATE(a0),a1
                bsr.s   hnd_dssecs
                move.l  d0,d2                ; d2/d3 = date retenue (secondes, µs)
                move.l  d1,d3
                lea     IOREQ_SZ+HND_DISKDATE(a3),a1
                bsr.s   hnd_dssecs
                cmp.l   d2,d0
                bls.s   .bc_max
                move.l  d0,d2
                move.l  d1,d3
.bc_max:
                jsr     timer_now            ; d0/d1 = heure système
                cmp.l   #86400,d0
                bhs.s   .bc_free             ; déjà réglée (au-delà du premier jour)
                cmp.l   d2,d0
                bhi.s   .bc_free
                blo.s   .bc_set
                cmp.l   d3,d1
                bhs.s   .bc_free
.bc_set:
                move.l  d2,d0
                move.l  d3,d1
                jsr     timer_setnow
.bc_free:
                move.l  a3,a1
                move.l  #IOREQ_SZ+OFS_BSIZE,d0
                jsr     LVO_FREEMEM(a6)
.bc_ret:
                movem.l (sp)+,d0-d7/a0-a3
                rts

; hnd_dssecs(a1 = DateStamp [jours, minutes, ticks]) -> d0 = secondes, d1 = µs (ticks bornés à 16 bits).
hnd_dssecs:
                move.l  (a1),d0
                mulu    #1440,d0             ; jours -> minutes
                add.l   4(a1),d0
                move.l  d0,d1                ; × 60 = × 64 - × 4
                lsl.l   #6,d0
                lsl.l   #2,d1
                sub.l   d1,d0
                move.l  8(a1),d1
                and.l   #$0000FFFF,d1
                divu    #50,d1               ; d1 = reste : secondes
                add.w   d1,d0
                bcc.s   .ds_nc
                add.l   #$10000,d0
.ds_nc:
                clr.w   d1
                swap    d1
                mulu    #20000,d1            ; reste (ticks) -> µs
                rts
hnd_tdname:
                dc.b    "trackdisk.device",0
                even


; hnd_lockkey(d0 = BPTR FileLock | 0) -> d0 = bloc header verrouillé (fl_Key) | 0 (= racine pour ofs_*). Clobbe a0.
hnd_lockkey:
                lsl.l   #2,d0
                beq.s   .lk_root
                move.l  d0,a0
                move.l  FL_KEY(a0),d0
.lk_root:
                rts
; hnd_cstr(d0 = BPTR BSTR, a1 = destination HND_NAMEBUF) : chaîne C (longueur bornée). Clobbe d0/d1/a0/a1.
hnd_cstr:
                lsl.l   #2,d0
                move.l  d0,a0
                moveq   #0,d1
                move.b  (a0)+,d1
                cmp.w   #HND_NAMEBUF-1,d1
                bls.s   .cs_nx
                moveq   #HND_NAMEBUF-1,d1
                bra.s   .cs_nx
.cs_cp:
                move.b  (a0)+,(a1)+
.cs_nx:
                dbra    d1,.cs_cp
                clr.b   (a1)
                rts
hnd_slash:
                dc.b    "/",0
                even
