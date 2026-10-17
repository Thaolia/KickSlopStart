; src/dos/handler.s — process file-handler DF0: (D3b). Corps d'un Process (créé par proc_create) qui boucle
; WaitPort/GetMsg sur son pr_MsgPort et sert les DOS packets du chemin lecture : ACTION_FINDINPUT / READ / END,
; en s'appuyant sur ofs_read_file (D1). Machinerie INTERNE (pas de dos.library user-facing = D3c).
;
; Protocole (docs/analysis/dos-v34-spec.md §2) : msg->ln_Name -> DosPacket. Sur FINDINPUT (ARG1=BPTR FileHandle,
; ARG2=lock ignoré, ARG3=BSTR nom) le handler lit le fichier ENTIER (ofs_read_file) dans un buffer, alloue un
; état {buffer,taille,pos}, pose fh_Arg1 = état dans le FileHandle (BADDR(ARG1)), renvoie DOSTRUE. READ (ARG1=
; fh_Arg1, ARG2=buffer dest, ARG3=len) copie depuis l'état et avance pos (RES1=octets, 0=EOF). END (ARG1=fh_Arg1)
; libère l'état. Simplification D3b assumée : fichier entier bufferisé sur FINDINPUT (lectures incrémentales OFS
; différées). Piste IMPLÉMENTATION (« clean ») : spec analyse + AutoDocs exec. AUCUNE lecture ROM.

                include "exec.i"
                include "ofs.i"
                include "dospkt.i"

                xdef    dos_handler_df0
                xref    ofs_read_file

HND_FILEMAX     EQU DOS_FILEMAX       ; taille max d'un fichier bufferisé par le handler (cap-bump 32K, exec.i)
HS_BUF          EQU 0                ; état : APTR buffer du fichier
HS_SIZE         EQU 4                ; LONG taille lue
HS_POS          EQU 8                ; LONG position de lecture courante
HND_STATE_SIZE  EQU 12
ERROR_ACTION_NOT_KNOWN EQU 209       ; dos/dos.i : action non supportée

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
                move.l  #DOSFALSE,DP_RES1(a4)         ; action inconnue
                move.l  #ERROR_ACTION_NOT_KNOWN,DP_RES2(a4)
                bra     .reply

.findinput:
                move.l  #HND_FILEMAX,d0              ; buffer du fichier
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fi_fail
                move.l  d0,d5                        ; d5 = buffer (préservé par ofs_read_file)
                move.l  #HND_STATE_SIZE,d0           ; état {buffer,taille,pos}
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .fi_fail_buf
                move.l  d0,d6                        ; d6 = état
                ; convertir le BSTR nom (ARG3) en C-string sur la pile pour ofs_read_file
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
                move.l  sp,a0                         ; a0 = nom, a1 = buffer, d0 = max
                move.l  d5,a1
                move.l  #HND_FILEMAX,d0
                jsr     ofs_read_file                 ; d0 = taille | 0
                lea     112(sp),sp                    ; restaure la pile (C-string consommée)
                tst.l   d0
                beq.s   .fi_fail_state                ; introuvable/vide
                move.l  d6,a0                          ; remplir l'état
                move.l  d5,HS_BUF(a0)
                move.l  d0,HS_SIZE(a0)
                clr.l   HS_POS(a0)
                move.l  DP_ARG1(a4),d0                ; FileHandle = BADDR(ARG1)
                lsl.l   #2,d0
                move.l  d0,a1
                move.l  d6,FH_ARG1(a1)                ; fh_Arg1 = clé = état
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply
.fi_fail_state:
                move.l  #ERROR_OBJECT_NOT_FOUND,DP_RES2(a4)  ; fichier introuvable -> IoErr (via dp_Res2)
                move.l  d6,a1
                move.l  #HND_STATE_SIZE,d0
                jsr     LVO_FREEMEM(a6)
.fi_fail_buf:
                move.l  d5,a1
                move.l  #HND_FILEMAX,d0
                jsr     LVO_FREEMEM(a6)
.fi_fail:
                move.l  #DOSFALSE,DP_RES1(a4)
                bra     .reply

.read:
                ifne    D3B_NO_READ
                clr.l   DP_RES1(a4)                   ; RED D3B_NO_READ : ne sert PAS READ -> EOF immédiat
                bra     .reply
                endc
                move.l  DP_ARG1(a4),a0                ; a0 = état (fh_Arg1)
                move.l  HS_SIZE(a0),d0
                move.l  HS_POS(a0),d1
                sub.l   d1,d0                          ; restant = taille - pos
                bls.s   .rd_eof                        ; pos >= taille -> EOF
                move.l  DP_ARG3(a4),d2                ; len demandé
                cmp.l   d2,d0
                bls.s   .rd_n
                move.l  d2,d0                          ; n = min(restant, len)
.rd_n:                                                ; d0 = n
                move.l  HS_BUF(a0),a1
                add.l   d1,a1                          ; src = buffer + pos
                move.l  DP_ARG2(a4),a5                ; dest (APTR)
                move.l  d0,d2                          ; sauve n
                move.l  d0,d1
                beq.s   .rd_copied
.rd_cpy:
                move.b  (a1)+,(a5)+
                subq.l  #1,d1
                bne.s   .rd_cpy
.rd_copied:
                move.l  DP_ARG1(a4),a0
                add.l   d2,HS_POS(a0)                 ; pos += n
                move.l  d2,DP_RES1(a4)                ; RES1 = octets lus
                bra.s   .reply
.rd_eof:
                clr.l   DP_RES1(a4)                   ; 0 = EOF
                bra.s   .reply

.seek:                                                ; Seek(ARG1=état, ARG2=position, ARG3=mode) -> RES1 = ancienne pos
                ifne    HND_NO_SEEK
                move.l  DP_ARG1(a4),a0                ; RED HND_NO_SEEK : lit l'état mais NE repositionne PAS HS_POS
                move.l  HS_POS(a0),DP_RES1(a4)
                bra     .reply
                endc
                move.l  DP_ARG1(a4),a0                ; a0 = état
                move.l  HS_POS(a0),d3                 ; d3 = ancienne position (valeur de retour)
                move.l  DP_ARG2(a4),d1                ; position (signée)
                move.l  DP_ARG3(a4),d2                ; mode (OFFSET_BEGINNING -1 / CURRENT 0 / END 1)
                tst.l   d2
                blt.s   .sk_begin
                beq.s   .sk_current
                move.l  HS_SIZE(a0),d0                ; END : taille + position
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
                cmp.l   HS_SIZE(a0),d0
                bhi.s   .sk_err                       ; hors [0, taille]
                move.l  d0,HS_POS(a0)                 ; repositionne
                move.l  d3,DP_RES1(a4)                ; renvoie l'ANCIENNE position
                bra     .reply
.sk_err:
                move.l  #-1,DP_RES1(a4)
                move.l  #ERROR_SEEK_ERROR,DP_RES2(a4)
                bra     .reply

.end:
                move.l  DP_ARG1(a4),a5                ; a5 = état (survit à FreeMem)
                move.l  HS_BUF(a5),a1
                move.l  #HND_FILEMAX,d0
                jsr     LVO_FREEMEM(a6)               ; libère le buffer
                move.l  a5,a1
                move.l  #HND_STATE_SIZE,d0
                jsr     LVO_FREEMEM(a6)               ; libère l'état
                move.l  #DOSTRUE,DP_RES1(a4)
.reply:
                move.l  a3,a1
                jsr     LVO_REPLYMSG(a6)              ; renvoie au mn_ReplyPort de l'appelant
                bra     .hl
