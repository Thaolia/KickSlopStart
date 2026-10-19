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

                xdef    dos_handler_df0
                xref    ofs_name_to_block    ; LOCATE_OBJECT : chemin -> bloc
                xref    ofs_fill_fib         ; EXAMINE_OBJECT : bloc -> FIB
                xref    ofs_dir_next         ; EXAMINE_NEXT : entrée suivante du répertoire
                xref    ofs_stream_open      ; FINDINPUT : ouvre un fichier en streaming
                xref    ofs_stream_read      ; READ : lecture incrémentale data-block par data-block
                xref    ofs_stream_seek      ; SEEK : repositionne le curseur de streaming

ACTION_MORE_CACHE EQU 18             ; AddBuffers : ajoute des tampons au filesystem

; dos_handler_df0 : corps du process. GPR à zéro à l'entrée (frame AddTask) -> recharge SysBase.
; a2 = pr_MsgPort (persistant) ; a3 = Message courant ; a4 = DosPacket courant.
dos_handler_df0:
                move.l  ($4).w,a6
                move.l  EB_THISTASK(a6),a2
                lea     PR_MSGPORT(a2),a2    ; a2 = son propre pr_MsgPort
.hl:
                move.l  a2,a0
                jsr     LVO_WAITPORT(a6)     ; bloque jusqu'à un packet
                move.l  a2,a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .hl
                move.l  d0,a3                ; a3 = Message
                move.l  LN_NAME(a3),a4       ; a4 = DosPacket (convention : msg->ln_Name)
                clr.l   DP_RES2(a4)
                move.l  DP_TYPE(a4),d0
                cmp.l   #ACTION_FINDINPUT,d0
                beq.s   .findinput
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
                move.l  d0,d1                          ; FL_LINK/FL_VOLUME/curseur = 0 (MEMF_CLEAR)
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
                move.l  #SS_ALLOC,d0
                jsr     LVO_FREEMEM(a6)               ; libère l'état (ioreq + block buffer inclus)
                move.l  #DOSTRUE,DP_RES1(a4)
.reply:
                move.l  a3,a1
                jsr     LVO_REPLYMSG(a6)              ; renvoie au mn_ReplyPort de l'appelant
                bra     .hl

; hnd_lockkey(d0 = BPTR FileLock | 0) -> d0 = bloc header verrouillé (fl_Key) | 0 (= racine pour ofs_*). Clobbe a0.
hnd_lockkey:
                lsl.l   #2,d0
                beq.s   .lk_root
                move.l  d0,a0
                move.l  FL_KEY(a0),d0
.lk_root:
                rts
hnd_slash:
                dc.b    "/",0
                even
