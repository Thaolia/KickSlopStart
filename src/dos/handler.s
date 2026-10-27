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
                include "disk.i"

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
                xref    ow_inhibit
                xref    ws_open
                xref    ws_write
                xref    ws_close
                xref    ofs_read_block       ; hnd_bootclock : lecture du bloc racine
                xref    timer_now            ; heure système (exec/timer.s)
                xref    timer_setnow

ACTION_MORE_CACHE EQU 18             ; AddBuffers : ajoute des tampons au filesystem
ID_VALIDATING   EQU 81               ; InfoData.id_DiskState : pas de bitmap (pas de disque, ou disque non DOS)
IND_WRITEEVENT_C EQU 11              ; input.device
IE_SIZE         EQU 22               ; struct InputEvent
DT_DOS          EQU $444F5300        ; « DOS\0 »
DT_NDOS         EQU $4E444F53        ; « NDOS » : amorce DOS mais bloc racine invalide
DT_BAD          EQU $42414400        ; « BAD\0 » : bloc 0 illisible

; contexte du handler (alloué à son démarrage, pointeur en HND_CTX)
HC_TDIO         EQU 0                ; IOStdReq trackdisk (questions de changement), puis un bloc de 512 octets
HC_TMPORT       EQU HC_TDIO+IOREQ_SZ+OFS_BSIZE  ; port des réponses du timer (MP_SIZE, arrondi)
HC_TMREQ        EQU HC_TMPORT+36     ; timerequest (40)
HC_INPORT       EQU HC_TMREQ+40      ; port des réponses d'input.device
HC_INIO         EQU HC_INPORT+36     ; IOStdReq input.device
HC_IEV          EQU HC_INIO+IOREQ_SZ ; InputEvent (IE_SIZE, arrondi)
HC_SIGS         EQU HC_IEV+24        ; signaux attendus : port des packets | timer
HC_CHG          EQU HC_SIGS+4        ; TD_CHANGENUM au montage
HC_DTYPE        EQU HC_CHG+4         ; type du disque monté (id_DiskType), -1 : aucun
HC_MOUNTED      EQU HC_DTYPE+4       ; byte : un disque a été examiné depuis la dernière éjection
HC_INHIB        EQU HC_MOUNTED+1     ; byte : ACTION_INHIBIT en cours
HC_TMOK         EQU HC_INHIB+1       ; byte : timer ouvert, requête en cours
HC_INOK         EQU HC_TMOK+1        ; byte : input.device ouvert
HC_SIZE         EQU HC_INOK+1
ACTION_INHIBIT  EQU 31               ; Arg1 = DOSTRUE : le disque n'est plus accédé (DiskCopy, Format)
WS_MAGICV       EQU $57524954        ; tête d'un état d'écriture (ofswrite.s) ; un état de lecture commence par un APTR
HND_NAMEBUF     EQU 112              ; chaîne C d'un nom reçu en BSTR (pile)

; dos_handler_df0 : corps du process. GPR à zéro à l'entrée (frame AddTask) -> recharge SysBase.
; a2 = pr_MsgPort (persistant) ; a3 = Message courant ; a4 = DosPacket courant.
; Changement de disquette (spec disk-change-v34 §2) : réveil par un packet ou par un tic timer d'1 s ; à chaque réveil
; hnd_check interroge trackdisk (TD_CHANGESTATE / TD_CHANGENUM) : éjection -> volume détaché, DISKREMOVED ;
; insertion -> volume retrouvé (même nom, même date de création) ou créé, DISKINSERTED.
dos_handler_df0:
                move.l  ($4).w,a6
                move.l  EB_THISTASK(a6),a2
                lea     PR_MSGPORT(a2),a2    ; a2 = son propre pr_MsgPort
                bsr     hnd_init
.hl:
                move.l  HND_CTX,d0
                beq.s   .hl_port             ; sans contexte : packets seulement
                move.l  d0,a0
                move.l  HC_SIGS(a0),d0
                jsr     LVO_WAIT(a6)         ; packet ou tic
                bsr     hnd_tick
                bsr     hnd_check
                bra.s   .hl_msg
.hl_port:
                move.l  a2,a0
                jsr     LVO_WAITPORT(a6)
.hl_msg:
                move.l  a2,a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .hl
                move.l  d0,a3                ; a3 = Message
                move.l  LN_NAME(a3),a4       ; a4 = DosPacket (convention : msg->ln_Name)
                clr.l   DP_RES2(a4)
                bsr     hnd_gate             ; lock ou fichier d'un autre volume, pas de disque : refus
                tst.l   d0
                bne     .refuse
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
                cmp.l   #ACTION_INHIBIT,d0
                beq     .inhibit
                move.l  #DOSFALSE,DP_RES1(a4)         ; action inconnue
                move.l  #ERROR_ACTION_NOT_KNOWN,DP_RES2(a4)
                bra     .reply
.refuse:
                move.l  d0,DP_RES2(a4)
                move.l  #DOSFALSE,DP_RES1(a4)
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
                move.l  d6,a1
                bsr     hnd_usevol
                move.l  d0,SS_VOL(a1)
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
                bsr     hnd_usevol
                move.l  d0,FL_VOLUME(a0)               ; nœud volume du disque monté (compté)
                move.l  a0,d1                          ; FL_LINK/curseur = 0 (MEMF_CLEAR)
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
                move.l  FL_VOLUME(a1),d0
                bsr     hnd_unusevol
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
                bsr     hnd_usevol
                move.l  d0,FL_VOLUME(a0)
                move.l  a0,d0
                lsr.l   #2,d0
                move.l  d0,DP_RES1(a4)
                bra     .reply
.pa_root:
                clr.l   DP_RES1(a4)
                bra     .reply

.inhibit:                                            ; (ARG1 : DOSTRUE = inhiber, 0 = lever)
                move.l  DP_ARG1(a4),d0
                jsr     ow_inhibit                     ; bitmap écrite / oubliée
                move.l  HND_CTX,d0
                beq.s   .ih_ok
                move.l  d0,a0
                tst.l   DP_ARG1(a4)
                beq.s   .ih_off
                tst.b   HC_INHIB(a0)
                bne.s   .ih_ok
                st      HC_INHIB(a0)                   ; volume détaché comme à l'éjection, sans événement
                move.l  a3,-(sp)
                move.l  a0,a3
                moveq   #0,d0
                bsr     hnd_eject
                move.l  #$42555359,HC_DTYPE(a3)        ; « BUSY »
                move.l  (sp)+,a3
                bra.s   .ih_ok
.ih_off:
                tst.b   HC_INHIB(a0)
                beq.s   .ih_ok
                sf      HC_INHIB(a0)                   ; remontage complet au réveil suivant
                sf      HC_MOUNTED(a0)
                move.l  #-1,HC_DTYPE(a0)
.ih_ok:
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply

.morecache:                                          ; AddBuffers : pas de cache de blocs FS (le trackdisk garde la piste)
                move.l  #DOSTRUE,DP_RES1(a4)          ; -> accepté sans effet
                bra     .reply

.end:
                move.l  DP_ARG1(a4),a1                ; a1 = état de streaming (un seul AllocMem)
                cmp.l   #WS_MAGICV,(a1)
                beq.s   .end_w
                move.l  SS_VOL(a1),d0
                bsr     hnd_unusevol
                move.l  #SS_ALLOC,d0
                jsr     LVO_FREEMEM(a6)               ; libère l'état (ioreq + block buffer inclus)
                move.l  #DOSTRUE,DP_RES1(a4)
.reply:                                              ; returnpkt : vers dp_Port (mn_ReplyPort peut
                move.l  DP_PORT(a4),a0                ; ne pas être rempli : DiskCopy), qui reçoit
                move.l  a2,DP_PORT(a4)                ; en retour le port du handler
                move.l  a3,a1
                jsr     LVO_PUTMSG(a6)
                bra     .hl_msg
.end_w:
                move.l  WS_VOL(a1),d0
                bsr     hnd_unusevol
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
                move.l  d0,a1
                bsr     hnd_usevol
                move.l  d0,WS_VOL(a1)
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
                move.l  DL_VOLUME(a1),d1
                beq.s   .di_none
                move.l  d1,a1
                jsr     ow_diskinfo
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.di_none:                                            ; pas de volume : état « validation », type courant
                moveq   #8,d0
.di_clr:
                clr.l   (a0)+
                dbra    d0,.di_clr
                lea     -36(a0),a0
                move.l  #ID_VALIDATING,8(a0)
                moveq   #-1,d1
                move.l  HND_CTX,d0
                beq.s   .di_ty
                move.l  d0,a1
                move.l  HC_DTYPE(a1),d1
.di_ty:
                move.l  d1,24(a0)
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply

; hnd_bootclock(a6 = SysBase) : réglage d'heure au montage (spec boot-clock-v34) : l'heure système prend la plus
; récente des deux dates du bloc racine (répertoire racine, longs 105-107 ; disque, longs 118-120) si elle est encore
; au premier jour (horloge jamais réglée) et antérieure à cette date ; jamais reculée. Appelé à chaque montage d'un
; disque DOS. Préserve tout.
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
hnd_tmname:
                dc.b    "timer.device",0
hnd_inname:
                dc.b    "input.device",0
                even


; hnd_init(a2 = pr_MsgPort, a6) : contexte, port et requête timer (UNIT_VBLANK, 1 s), input.device, puis premier
; montage. Sans mémoire : le handler tourne quand même, sans détection de changement. Préserve d2-d7/a2-a6.
hnd_init:
                movem.l d2/a3,-(sp)
                moveq   #0,d2
                move.b  MP_SIGBIT(a2),d0
                bset    d0,d2                         ; d2 = signal du port des packets
                move.l  #HC_SIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                move.l  d0,HND_CTX
                beq     .in_ret
                move.l  d0,a3
                move.l  d2,HC_SIGS(a3)
                move.l  #-1,HC_DTYPE(a3)
                lea     EB_DEVICELIST(a6),a0
                lea     hnd_tdname(pc),a1
                jsr     LVO_FINDNAME(a6)
                move.l  d0,HC_TDIO+IO_DEVICE(a3)
                lea     HC_TMPORT(a3),a0
                bsr     hnd_port
                beq.s   .in_input
                or.l    d0,HC_SIGS(a3)
                lea     HC_TMREQ(a3),a1
                lea     HC_TMPORT(a3),a0
                move.l  a0,MN_REPLYPORT(a1)
                lea     hnd_tmname(pc),a0
                moveq   #UNIT_VBLANK,d0
                moveq   #0,d1
                jsr     LVO_OPENDEVICE(a6)
                tst.l   d0
                bne.s   .in_input
                st      HC_TMOK(a3)
                bsr     hnd_arm
.in_input:
                lea     HC_INPORT(a3),a0
                bsr     hnd_port
                beq.s   .in_mount
                lea     HC_INIO(a3),a1
                lea     HC_INPORT(a3),a0
                move.l  a0,MN_REPLYPORT(a1)
                lea     hnd_inname(pc),a0
                moveq   #0,d0
                moveq   #0,d1
                jsr     LVO_OPENDEVICE(a6)
                tst.l   d0
                bne.s   .in_mount
                st      HC_INOK(a3)
.in_mount:
                bsr     hnd_check
.in_ret:
                movem.l (sp)+,d2/a3
                rts
; hnd_port(a0 = MsgPort à préparer, a6) -> d0 = masque de son signal (0 : aucun signal libre). Clobbe d1/a0/a1.
hnd_port:
                move.l  a0,-(sp)
                moveq   #-1,d0
                jsr     LVO_ALLOCSIGNAL(a6)
                move.l  (sp)+,a0
                tst.b   d0
                bmi.s   .po_none
                move.b  #NT_MSGPORT,LN_TYPE(a0)
                clr.b   MP_FLAGS(a0)                  ; PA_SIGNAL
                move.b  d0,MP_SIGBIT(a0)
                move.l  EB_THISTASK(a6),MP_SIGTASK(a0)
                lea     MP_MSGLIST(a0),a1             ; liste vide
                move.l  a1,8(a1)
                addq.l  #4,a1
                clr.l   (a1)
                move.l  a1,-(a1)
                moveq   #0,d1
                bset    d0,d1
                move.l  d1,d0
                rts
.po_none:
                moveq   #0,d0
                rts
; hnd_arm(a3 = contexte, a6) : requête timer d'une seconde, asynchrone. Clobbe d0/d1/a0/a1.
hnd_arm:
                lea     HC_TMREQ(a3),a1
                move.w  #TR_ADDREQUEST,IO_COMMAND(a1)
                move.l  #1,TV_SECS(a1)
                clr.l   TV_SECS+4(a1)
                jmp     LVO_SENDIO(a6)
; hnd_tick(a6) : réponse du timer reçue -> requête réarmée. Préserve d2-d7/a2-a6.
hnd_tick:
                move.l  a3,-(sp)
                move.l  HND_CTX,d0
                beq.s   .tk_ret
                move.l  d0,a3
                tst.b   HC_TMOK(a3)
                beq.s   .tk_ret
                lea     HC_TMPORT(a3),a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .tk_ret
                bsr.s   hnd_arm
.tk_ret:
                move.l  (sp)+,a3
                rts

; hnd_tdcmd(d0.w = commande, a3 = contexte, a6) -> d0 = io_Actual. Clobbe d1/a0/a1.
hnd_tdcmd:
                lea     HC_TDIO(a3),a1
                move.w  d0,IO_COMMAND(a1)
                move.b  #IOF_QUICK,IO_FLAGS(a1)
                clr.l   IO_ACTUAL(a1)
                move.l  a6,-(sp)
                move.l  IO_DEVICE(a1),a6
                jsr     -30(a6)              ; BeginIO
                move.l  (sp)+,a6
                move.l  HC_TDIO+IO_ACTUAL(a3),d0
                rts

; hnd_check(a2 = port du handler, a6) : éjection ou insertion depuis le dernier passage (spec disk-change-v34 §2.1).
; Monté : disque absent ou compteur de changements différent -> éjection. Non monté et disque présent -> montage.
; Rien pendant une inhibition. Préserve d2-d7/a2-a6.
hnd_check:
                movem.l d2/a3,-(sp)
                move.l  HND_CTX,d0
                beq.s   .ck_ret
                move.l  d0,a3
                tst.l   HC_TDIO+IO_DEVICE(a3)
                beq.s   .ck_ret
                tst.b   HC_INHIB(a3)
                bne.s   .ck_ret
                moveq   #TD_CHANGESTATE,d0
                bsr     hnd_tdcmd
                move.l  d0,d2                         ; d2 = 0 : disque présent
                tst.b   HC_MOUNTED(a3)
                beq.s   .ck_in
                tst.l   d2
                bne.s   .ck_out
                moveq   #TD_CHANGENUM,d0
                bsr     hnd_tdcmd
                cmp.l   HC_CHG(a3),d0
                beq.s   .ck_ret
.ck_out:
                moveq   #1,d0
                bsr     hnd_eject
                tst.l   d2
                bne.s   .ck_ret
.ck_in:
                tst.l   d2
                bne.s   .ck_ret
                bsr     hnd_mount
.ck_ret:
                movem.l (sp)+,d2/a3
                rts

; hnd_mount(a2 = port, a3 = contexte, a6) : examine le disque inséré (bloc 0 puis bloc racine, spec §2.2.2 et §2.5).
; Disque DOS : nœud volume de même nom et même date de création réactivé, sinon créé en tête de la DosList ; il devient
; DL_VOLUME, bitmap oubliée, heure réglée. Puis DISKINSERTED, disque DOS ou non. Préserve d2-d7/a2-a6.
hnd_mount:
                movem.l d2/a2-a4,-(sp)
                move.l  a2,a4                         ; a4 = port du handler
                st      HC_MOUNTED(a3)
                move.l  HC_TDIO+IO_DEVICE(a3),a2
                moveq   #0,d0
                move.l  a3,-(sp)
                lea     HC_TDIO(a3),a3
                jsr     ofs_read_block
                move.l  (sp)+,a3
                move.l  #DT_BAD,d2
                tst.l   d0
                beq     .mo_type
                move.l  HC_TDIO+IOREQ_SZ(a3),d2       ; premier long du bloc 0 : « DOS\0 » seulement (OFS)
                cmp.l   #DT_DOS,d2
                bne     .mo_type
                move.l  #DT_NDOS,d2
                move.l  #OFS_ROOTBLK,d0
                move.l  a3,-(sp)
                lea     HC_TDIO(a3),a3
                jsr     ofs_read_block
                move.l  (sp)+,a3
                tst.l   d0
                beq     .mo_type
                lea     HC_TDIO+IOREQ_SZ(a3),a0       ; contrôles du bloc racine
                moveq   #0,d0
                moveq   #OFS_BSIZE/4-1,d1
.mo_sum:
                add.l   (a0)+,d0
                dbra    d1,.mo_sum
                tst.l   d0
                bne     .mo_type
                lea     HC_TDIO+IOREQ_SZ(a3),a0
                cmp.l   #OFS_T_SHORT,OFSB_TYPE(a0)
                bne     .mo_type
                tst.l   4(a0)                         ; clé d'en-tête
                bne     .mo_type
                cmp.l   #72,OFSB_HTSIZE(a0)
                bne     .mo_type
                cmp.l   #OFS_ST_ROOT,OFSB_SECTYPE(a0)
                bne     .mo_type
                moveq   #0,d0
                move.b  OFSB_NAME(a0),d0
                beq     .mo_type
                cmp.b   #30,d0
                bhi     .mo_type
                move.l  #DT_DOS,d2
                bsr     hnd_findvol                   ; d0 = BPTR du nœud (réactivé ou créé) | 0
                move.l  DOS_DOSBASE,a0
                move.l  d0,DL_VOLUME(a0)
                moveq   #0,d0
                jsr     ow_inhibit                    ; bitmap de l'ancien disque oubliée
                bsr     hnd_bootclock
.mo_type:
                move.l  d2,HC_DTYPE(a3)
                moveq   #TD_CHANGENUM,d0
                bsr     hnd_tdcmd
                move.l  d0,HC_CHG(a3)
                moveq   #IECLASS_DISKINSERTED,d0
                bsr     hnd_event
                movem.l (sp)+,d2/a2-a4
                rts

; hnd_findvol(a3 = contexte (bloc racine en HC_TDIO+IOREQ_SZ), a4 = port, a6) -> d0 = BPTR du nœud volume | 0 :
; nœud DLT_VOLUME de même nom (sans casse) et de même date de création (longs 121..123) : dl_Task := port ; sinon
; nœud neuf en tête de la DosList (date, nom, dl_Task ; dl_Lock, dl_LockList et dl_DiskType à 0). Sous Forbid.
; Clobbe d0/d1/a0/a1.
HND_CDATE       EQU 484              ; bloc racine : date de création du disque (longs 121..123)
hnd_findvol:
                movem.l d2/a2,-(sp)
                jsr     LVO_FORBID(a6)
                bsr     hnd_devinfo                   ; a0 = &di_DevInfo
                move.l  (a0),d2
.fv_lp:
                lsl.l   #2,d2
                beq.s   .fv_new
                move.l  d2,a2
                cmp.l   #DLT_VOLUME,DN_TYPE(a2)
                bne.s   .fv_nx
                lea     HC_TDIO+IOREQ_SZ+HND_CDATE(a3),a0
                lea     DOL_VOLDATE(a2),a1
                cmpm.l  (a0)+,(a1)+
                bne.s   .fv_nx
                cmpm.l  (a0)+,(a1)+
                bne.s   .fv_nx
                cmpm.l  (a0)+,(a1)+
                bne.s   .fv_nx
                move.l  DN_NAME(a2),d0
                lsl.l   #2,d0
                move.l  d0,a0
                lea     HC_TDIO+IOREQ_SZ+OFSB_NAME(a3),a1
                bsr     hnd_bstreq
                beq.s   .fv_found
.fv_nx:
                move.l  DN_NEXT(a2),d2
                bra.s   .fv_lp
.fv_found:
                move.l  a4,DN_TASK(a2)
                clr.l   DOL_LOCKLIST(a2)
                bra.s   .fv_ret
.fv_new:
                move.l  #DOL_NODESIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                move.l  d0,a2
                tst.l   d0
                beq.s   .fv_none
                move.l  #DLT_VOLUME,DN_TYPE(a2)
                move.l  a4,DN_TASK(a2)
                lea     HC_TDIO+IOREQ_SZ+HND_CDATE(a3),a0
                lea     DOL_VOLDATE(a2),a1
                move.l  (a0)+,(a1)+
                move.l  (a0)+,(a1)+
                move.l  (a0)+,(a1)+
                lea     HC_TDIO+IOREQ_SZ+OFSB_NAME(a3),a0
                lea     DN_SIZEOF(a2),a1              ; BSTR du nom juste après le nœud
                move.l  a1,d0
                lsr.l   #2,d0
                move.l  d0,DN_NAME(a2)
                moveq   #0,d0
                move.b  (a0),d0                       ; longueur (1..30, contrôlée)
.fv_cp:
                move.b  (a0)+,(a1)+
                dbra    d0,.fv_cp
                bsr     hnd_devinfo
                move.l  (a0),DN_NEXT(a2)
                move.l  a2,d0
                lsr.l   #2,d0
                move.l  d0,(a0)
.fv_ret:
                move.l  a2,d0
                lsr.l   #2,d0
.fv_none:
                jsr     LVO_PERMIT(a6)
                movem.l (sp)+,d2/a2
                rts
; hnd_devinfo -> a0 = &DosInfo.di_DevInfo. Clobbe d0.
hnd_devinfo:
                move.l  DOS_DOSBASE,a0
                move.l  DL_ROOT(a0),a0
                move.l  RN_INFO(a0),d0
                lsl.l   #2,d0
                move.l  d0,a0
                lea     DI_DEVINFO(a0),a0
                rts
; hnd_bstreq(a0, a1 = BSTR) -> Z = 1 si égales sans tenir compte de la casse (ASCII). Clobbe d0/d1/a0/a1.
hnd_bstreq:
                move.l  d2,-(sp)
                moveq   #0,d2
                move.b  (a0)+,d2
                cmp.b   (a1)+,d2
                bne.s   .be_ret
                bra.s   .be_nx
.be_lp:
                move.b  (a0)+,d0
                move.b  (a1)+,d1
                bsr.s   .be_up
                exg     d0,d1
                bsr.s   .be_up
                cmp.b   d0,d1
                bne.s   .be_ret
.be_nx:
                dbra    d2,.be_lp
                moveq   #0,d0                         ; Z = 1
.be_ret:
                movem.l (sp)+,d2                      ; (movem ne touche pas aux codes de condition)
                rts
.be_up:
                cmp.b   #'a',d0
                blo.s   .bu_r
                cmp.b   #'z',d0
                bhi.s   .bu_r
                sub.b   #'a'-'A',d0
.bu_r:
                rts

; hnd_eject(d0 = 1 : émettre DISKREMOVED, a3 = contexte, a6) : volume courant détaché (spec §2.2.1) : sans lock ni
; fichier ouvert, son nœud quitte la DosList et est libéré ; sinon dl_Task := 0 (le nœud reste). Bitmap oubliée.
; Préserve d2-d7/a2-a6.
hnd_eject:
                movem.l d2/a2,-(sp)
                move.l  d0,d2
                moveq   #0,d0
                jsr     ow_inhibit
                sf      HC_MOUNTED(a3)
                move.l  #-1,HC_DTYPE(a3)
                move.l  DOS_DOSBASE,a0
                move.l  DL_VOLUME(a0),d0
                clr.l   DL_VOLUME(a0)
                lsl.l   #2,d0
                beq.s   .ej_ev
                move.l  d0,a2
                jsr     LVO_FORBID(a6)
                tst.l   DOL_USE(a2)
                bne.s   .ej_keep
                bsr     hnd_devinfo                   ; retrait de la DosList
.ej_find:
                move.l  (a0),d0
                lsl.l   #2,d0
                beq.s   .ej_free
                cmp.l   d0,a2
                beq.s   .ej_unlink
                move.l  d0,a0                         ; DN_NEXT = 0
                bra.s   .ej_find
.ej_unlink:
                move.l  DN_NEXT(a2),(a0)
.ej_free:
                jsr     LVO_PERMIT(a6)
                move.l  a2,a1
                move.l  #DOL_NODESIZE,d0
                jsr     LVO_FREEMEM(a6)
                bra.s   .ej_ev
.ej_keep:
                clr.l   DN_TASK(a2)
                jsr     LVO_PERMIT(a6)
.ej_ev:
                tst.l   d2
                beq.s   .ej_ret
                moveq   #IECLASS_DISKREMOVED,d0
                bsr     hnd_event
.ej_ret:
                movem.l (sp)+,d2/a2
                rts

; hnd_event(d0.b = ie_Class, a3 = contexte, a6) : InputEvent nulle de cette classe écrite dans input.device
; (IND_WRITEEVENT) : intuition en fait DISKINSERTED / DISKREMOVED. Clobbe d0/d1/a0/a1.
hnd_event:
                tst.b   HC_INOK(a3)
                beq.s   .ev_ret
                lea     HC_IEV(a3),a0
                clr.l   (a0)
                clr.l   4(a0)
                clr.l   8(a0)
                clr.l   12(a0)
                clr.l   16(a0)
                clr.w   20(a0)
                move.b  d0,4(a0)                      ; ie_Class
                lea     HC_INIO(a3),a1
                move.w  #IND_WRITEEVENT_C,IO_COMMAND(a1)
                move.l  a0,IO_DATA(a1)
                move.l  #IE_SIZE,IO_LENGTH(a1)
                jsr     LVO_DOIO(a6)
.ev_ret:
                rts

; hnd_gate(a4 = DosPacket) -> d0 = 0 si le packet peut être servi, sinon le code d'erreur (spec §2.4) : un lock ou
; un fichier d'un autre volume que le disque monté -> 218 (ERROR_DEVICE_NOT_MOUNTED) ; une action sur la racine
; sans disque -> 226 (ERROR_NO_DISK), disque non DOS -> 225. Fermetures, UnLock, Info disque et inhibition passent
; toujours. Clobbe d1/a0/a1.
hnd_gate:
                move.l  DP_TYPE(a4),d0
                lea     hnd_gtab(pc),a0
.gt_lp:
                move.w  (a0)+,d1
                beq.s   .gt_ok                        ; action sans lock à contrôler
                cmp.w   d1,d0
                beq.s   .gt_hit
                addq.l  #2,a0
                bra.s   .gt_lp
.gt_hit:
                move.l  DOS_DOSBASE,a1
                move.l  DL_VOLUME(a1),d1              ; d1 = volume monté | 0
                move.w  (a0),d0                       ; décalages des arguments (octet haut, octet bas ; 0 = aucun)
                tst.b   d0
                bmi.s   .gt_state
                bsr.s   .gt_arg
                bne.s   .gt_ret
                lsr.w   #8,d0
                bsr.s   .gt_arg
                bne.s   .gt_ret
.gt_ok:
                moveq   #0,d0
.gt_ret:
                rts
.gt_state:                                            ; READ/WRITE/SEEK : ARG1 = état d'un fichier ouvert
                move.l  DP_ARG1(a4),a0
                move.l  SS_VOL(a0),d0
                cmp.l   #WS_MAGICV,(a0)
                bne.s   .gs_cmp
                move.l  WS_VOL(a0),d0
.gs_cmp:
                tst.l   d1
                beq.s   .gt_218
                cmp.l   d1,d0
                beq.s   .gt_ok
.gt_218:
                move.l  d0,HND_REFVOL                 ; volume réclamé par le requester « Please replace volume » (dos)
                move.l  #ERROR_DEVICE_NOT_MOUNTED,d0
                rts
; .gt_arg(d0.b = décalage dans le packet de l'argument lock | 0, d1 = volume monté) -> Z = 1 : accepté, sinon d0 = code
.gt_arg:
                move.l  d0,-(sp)
                and.w   #$FF,d0
                beq.s   .ga_ok
                move.l  0(a4,d0.w),d0                 ; BPTR lock | 0
                lsl.l   #2,d0
                bne.s   .ga_lock
                tst.l   d1                            ; racine du disque monté
                bne.s   .ga_ok
                move.l  #ERROR_NO_DISK,d0
                move.l  HND_CTX,a0
                cmpa.w  #0,a0
                beq.s   .ga_err
                cmp.l   #-1,HC_DTYPE(a0)
                beq.s   .ga_err
                move.l  #ERROR_NOT_A_DOS_DISK,d0
                bra.s   .ga_err
.ga_lock:
                move.l  d0,a0
                tst.l   d1
                beq.s   .ga_218
                cmp.l   FL_VOLUME(a0),d1
                beq.s   .ga_ok
.ga_218:
                move.l  FL_VOLUME(a0),HND_REFVOL
                move.l  #ERROR_DEVICE_NOT_MOUNTED,d0
.ga_err:
                addq.l  #4,sp
                tst.l   d0                            ; Z = 0
                rts
.ga_ok:
                move.l  (sp)+,d0
                cmp.w   d0,d0                         ; Z = 1
                rts
; action, décalages (octet haut : 2e lock, octet bas : 1er lock) ; $80 : état de fichier en ARG1
hnd_gtab:
                dc.w    ACTION_LOCATE_OBJECT,DP_ARG1
                dc.w    ACTION_EXAMINE_OBJECT,DP_ARG1
                dc.w    ACTION_EXAMINE_NEXT,DP_ARG1
                dc.w    ACTION_PARENT,DP_ARG1
                dc.w    ACTION_COPY_DIR,DP_ARG1
                dc.w    ACTION_DELETE_OBJECT,DP_ARG1
                dc.w    ACTION_RENAME_OBJECT,DP_ARG3<<8|DP_ARG1
                dc.w    ACTION_CREATE_DIR,DP_ARG1
                dc.w    ACTION_SET_PROTECT,DP_ARG2
                dc.w    ACTION_SET_COMMENT,DP_ARG2
                dc.w    ACTION_INFO,DP_ARG1
                dc.w    ACTION_FINDINPUT,DP_ARG2
                dc.w    ACTION_FINDOUTPUT,DP_ARG2
                dc.w    ACTION_FINDUPDATE,DP_ARG2
                dc.w    ACTION_READ,$80
                dc.w    ACTION_WRITE,$80
                dc.w    ACTION_SEEK,$80
                dc.w    0

; hnd_usevol -> d0 = BPTR du volume monté (DL_VOLUME) | 0, son compte d'usage augmenté (lock ou fichier ouvert).
; hnd_unusevol(d0 = BPTR volume | 0) : compte diminué. Préservent tout sauf d0.
hnd_usevol:
                move.l  a0,-(sp)
                move.l  DOS_DOSBASE,a0
                move.l  DL_VOLUME(a0),d0
                beq.s   .uv_ret
                lsl.l   #2,d0
                move.l  d0,a0
                addq.l  #1,DOL_USE(a0)
                lsr.l   #2,d0
.uv_ret:
                move.l  (sp)+,a0
                rts
hnd_unusevol:
                lsl.l   #2,d0
                beq.s   .un_ret
                move.l  a0,-(sp)
                move.l  d0,a0
                tst.l   DOL_USE(a0)
                beq.s   .un_z
                subq.l  #1,DOL_USE(a0)
.un_z:
                move.l  (sp)+,a0
.un_ret:
                rts

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
