; tests/dskchg.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Sonde boîte noire « changement de disquette » (piste analyse, disk-change-v34.md).
; À lancer en tâche de fond depuis la startup-sequence (run >NIL: dskchg [opts]). Toutes les 100 ms :
;   - vide le port IDCMP d'une petite fenêtre WBENCHSCREEN (IDCMP DISKINSERTED|DISKREMOVED) et émet
;       « t=NNNN EV classe secondes micros » ;
;   - option T : interroge trackdisk.device unité 0 (TD_CHANGENUM 13, TD_CHANGESTATE 14) et émet
;     « TD n état » au changement ;
;   - photographie la DosList (sous Forbid) et, si elle a changé : « DL nombre », puis les nœuds nouveaux ou
;     modifiés « N index adresse +4 +8 +C +10 +14 +18 +1C +20 +24 nom » (index = rang dans la liste, longs bruts
;     du nœud, nom BSTR de +$28 ; un nœud peut réapparaître identique si les octets après son nom ont changé)
;     et les nœuds disparus « X adresse » ; battement « t=NNNN HB » toutes les 10 s ;
;   - option D : toutes les secondes, ACTION_DISK_INFO (25) au dn_Task
;     du nœud « DF0 », émet « DI état... » quand le résultat change (attente bornée à 2 s, sans renvoi
;     tant que la réponse n'est pas revenue) ;
;   - option L : prend au démarrage un lock partagé sur « DF0:c » (gardé jusqu'à la fin) ;
;   - option A (avec L) : 3 s après le premier DISKREMOVED, Examine(ce lock), Lock("Workbench1.3:c"),
;     Lock("DF0:") ; « AX/AV/AD résultat IoErr » (appels bloquants si un requester s'affiche).
; Options = lettres D/T/L/A/S n'importe où dans les arguments. Sortie : journal mémoire de 32 Ko (long 0 = longueur,
; puis texte, lignes terminées par LF) dont l'adresse est publiée en $3F0 (marqueur 'DCLG' en $3F4), relu au
; débogueur FS-UAE ; option S : copie aussi sur le série direct (SERDAT). Durée : 4000 itérations (~400 s). Assemblage : vasmm68k_mot -Fhunkexe -kick1hunks (LoadSeg 1.3).
; Code auteur ; structures publiques (dos/dosextens.h, exec/io.h, devices/trackdisk.h, intuition.h 1.3).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
NNODE    EQU 40                       ; nœuds photographiés au plus
LOGSZ    EQU 32768                    ; journal mémoire
NSZ      EQU 72                       ; adresse + 9 longs + 32 octets de nom

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars,a4
; options : lettres D, T, L n'importe où dans la ligne d'arguments (A0/D0)
.arg:           subq.l  #1,d0
                bmi.s   .argf
                move.b  (a0)+,d1
                cmp.b   #'D',d1
                bne.s   .a1
                st      optd-vars(a4)
.a1:            cmp.b   #'T',d1
                bne.s   .a2
                st      optt-vars(a4)
.a2:            cmp.b   #'S',d1
                bne.s   .a3
                st      opts-vars(a4)
.a3:            cmp.b   #'A',d1
                bne.s   .a4
                st      opta-vars(a4)
.a4:            cmp.b   #'L',d1
                bne.s   .arg
                st      optl-vars(a4)
                bra.s   .arg
.argf:
; journal mémoire : adresse publiée en $3F0 (vecteur utilisateur inutilisé), marqueur 'DCLG' en $3F4
                move.l  4.w,a6
                move.l  #LOGSZ,d0
                move.l  #$10001,d1           ; MEMF_PUBLIC|MEMF_CLEAR
                jsr     -198(a6)             ; AllocMem
                move.l  d0,logbuf-vars(a4)
                move.l  d0,$3F0.w
                move.l  #'DCLG',$3F4.w
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                move.l  d0,dosb-vars(a4)
                beq     .ret
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,intb-vars(a4)
                beq     .ret
; ports privés (paquets dos, trackdisk)
                lea     pkport,a0
                bsr     mkport
                lea     tdport,a0
                bsr     mkport
; trackdisk unité 0 (option T seulement)
                st      tdok-vars(a4)
                tst.b   optt-vars(a4)
                beq.s   .notd
                lea     tdio,a1
                lea     tdport,a0
                move.l  a0,14(a1)            ; mn_ReplyPort
                move.w  #48,18(a1)           ; mn_Length
                lea     tdname(pc),a0
                moveq   #0,d0
                moveq   #0,d1
                jsr     -444(a6)             ; OpenDevice
                move.b  d0,tdok-vars(a4)
.notd:
; fenêtre
                move.l  intb-vars(a4),a6
                lea     nw(pc),a0
                jsr     -204(a6)             ; OpenWindow
                move.l  d0,win-vars(a4)
; option L : lock sur DF0:c
                tst.b   optl-vars(a4)
                beq.s   .nol
                move.l  dosb-vars(a4),a6
                lea     lkname(pc),a0
                move.l  a0,d1
                moveq   #-2,d2
                jsr     -84(a6)              ; Lock(SHARED)
                move.l  d0,mylock-vars(a4)
                lea     t_lk(pc),a0
                bsr     puts
                move.l  mylock-vars(a4),d0
                bsr     puthex
                bsr     nl
.nol:
                lea     t_go(pc),a0
                bsr     puts
                move.l  win-vars(a4),d0
                bsr     puthex
                bsr     nl
                move.l  #-1,lastcn-vars(a4)
                move.l  #-1,lastcs-vars(a4)
                move.l  #4000,d7
.loop:
                move.l  dosb-vars(a4),a6
                moveq   #5,d1
                jsr     -198(a6)             ; Delay(5)
                addq.l  #1,tick-vars(a4)
                move.l  tick-vars(a4),d0
                divu    #100,d0
                swap    d0
                tst.w   d0
                bne.s   .nohb
                bsr     stamp                ; battement toutes les 10 s : « t=NNNN HB »
                lea     t_hb(pc),a0
                bsr     puts
                bsr     nl
.nohb:
                bsr     drainwin
                bsr     tdpoll
                bsr     snap
                bsr     access
                tst.b   optd-vars(a4)
                beq.s   .nod
                bsr     dinfo
.nod:
                subq.l  #1,d7
                bne.s   .loop
                lea     t_end(pc),a0
                bsr     puts
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; mkport(a0) : MsgPort privé PA_SIGNAL sur un nouveau signal de la tâche courante.
mkport:
                move.l  a0,a2
                move.l  4.w,a6
                moveq   #-1,d0
                jsr     -330(a6)             ; AllocSignal
                move.b  #4,8(a2)             ; NT_MSGPORT
                clr.b   14(a2)               ; PA_SIGNAL
                move.b  d0,15(a2)            ; mp_SigBit
                sub.l   a1,a1
                jsr     -294(a6)             ; FindTask(0)
                move.l  d0,16(a2)            ; mp_SigTask
                lea     20(a2),a0            ; mp_MsgList
                move.l  a0,8(a0)             ; lh_TailPred
                addq.l  #4,a0
                clr.l   (a0)                 ; lh_Tail
                move.l  a0,-(a0)             ; lh_Head
                rts

stamp:                                       ; « t=NNNNNNNN »
                lea     t_t(pc),a0
                bsr     puts
                move.l  tick-vars(a4),d0
                bra     puthex

; drainwin : messages IDCMP de la fenêtre
drainwin:
                move.l  win-vars(a4),d0
                beq.s   .r
                move.l  d0,a0
                move.l  86(a0),a3            ; wd_UserPort
.lp:
                move.l  4.w,a6
                move.l  a3,a0
                jsr     -372(a6)             ; GetMsg
                tst.l   d0
                beq.s   .r
                move.l  d0,a2
                bsr     stamp
                lea     t_ev(pc),a0
                bsr     puts
                move.l  20(a2),d0            ; im_Class
                cmp.l   #$10000,d0           ; DISKREMOVED : arme l'essai d'accès (option A) 3 s plus tard
                bne.s   .nrm
                tst.l   acct-vars(a4)
                bne.s   .nrm
                move.l  tick-vars(a4),d1
                add.l   #30,d1
                move.l  d1,acct-vars(a4)
.nrm:           move.l  20(a2),d0
                bsr     puthex
                move.l  36(a2),d0            ; im_Seconds
                bsr     puthex
                move.l  40(a2),d0            ; im_Micros
                bsr     puthex
                bsr     nl
                move.l  4.w,a6
                move.l  a2,a1
                jsr     -378(a6)             ; ReplyMsg
                bra.s   .lp
.r:
                rts

; tdpoll : TD_CHANGENUM / TD_CHANGESTATE
tdpoll:
                tst.b   tdok-vars(a4)
                bne.s   .r
                move.l  4.w,a6
                lea     tdio,a1
                move.w  #13,28(a1)
                jsr     -456(a6)             ; DoIO
                lea     tdio,a1
                move.l  32(a1),d5            ; io_Actual
                move.w  #14,28(a1)
                jsr     -456(a6)
                lea     tdio,a1
                move.l  32(a1),d6
                cmp.l   lastcn-vars(a4),d5
                bne.s   .pr
                cmp.l   lastcs-vars(a4),d6
                beq.s   .r
.pr:
                move.l  d5,lastcn-vars(a4)
                move.l  d6,lastcs-vars(a4)
                bsr     stamp
                lea     t_td(pc),a0
                bsr     puts
                move.l  d5,d0
                bsr     puthex
                move.l  d6,d0
                bsr     puthex
                bsr     nl
.r:
                rts

; snap : photographie de la DosList dans cur, comparée à prev
snap:
                move.l  4.w,a6
                jsr     -132(a6)             ; Forbid
                move.l  dosb-vars(a4),a0
                move.l  34(a0),a0            ; dl_Root
                move.l  24(a0),d0            ; rn_Info
                lsl.l   #2,d0
                move.l  d0,a0
                move.l  4(a0),d0             ; di_DevInfo
                lea     cur,a1
                moveq   #0,d4                ; nombre de nœuds
.nd:
                lsl.l   #2,d0
                beq.s   .fin
                cmp.w   #NNODE,d4
                bhs.s   .fin
                move.l  d0,a2
                move.l  d0,(a1)+
                moveq   #8,d1
                lea     4(a2),a3
.cp:            move.l  (a3)+,(a1)+
                dbra    d1,.cp
                move.l  40(a2),d0            ; dn_Name (BPTR)
                lsl.l   #2,d0
                move.l  d0,a3
                moveq   #31,d1
                tst.l   d0
                bne.s   .cn
.z:             clr.b   (a1)+
                dbra    d1,.z
                bra.s   .nx
.cn:            move.b  (a3)+,(a1)+
                dbra    d1,.cn
.nx:
                addq.w  #1,d4
                move.l  (a2),d0
                bra.s   .nd
.fin:
                jsr     -138(a6)             ; Permit
                move.w  d4,ncur-vars(a4)
; comparaison
                cmp.w   nprev-vars(a4),d4
                bne.s   .diff
                lea     cur,a0
                lea     prev,a1
                move.w  d4,d1
                mulu    #NSZ/4,d1
                bra.s   .ce
.cl:            cmpm.l  (a0)+,(a1)+
                bne.s   .diff
.ce:            dbra    d1,.cl
                rts
.diff:
; n'émet que les nœuds nouveaux ou modifiés (« N index adresse ... nom ») et les nœuds disparus (« X adresse »)
                bsr     stamp
                lea     t_dl(pc),a0
                bsr     puts
                moveq   #0,d0
                move.w  d4,d0
                bsr     puthex
                bsr     nl
                lea     cur,a2
                moveq   #0,d6                ; index
.ci:            cmp.w   d4,d6
                bhs.s   .gone
                lea     prev,a3
                move.w  nprev-vars(a4),d5
                bra.s   .se2
.sp:            move.l  a2,a0
                move.l  a3,a1
                moveq   #NSZ/4-1,d1
.cm:            cmpm.l  (a0)+,(a1)+
                bne.s   .nx2
                dbra    d1,.cm
                bra.s   .same                ; identique : rien à émettre
.nx2:           lea     NSZ(a3),a3
.se2:           dbra    d5,.sp
                bsr     pnode
.same:          lea     NSZ(a2),a2
                addq.w  #1,d6
                bra.s   .ci
.gone:          lea     prev,a3
                move.w  nprev-vars(a4),d5
                bra.s   .ge
.gl:            lea     cur,a0
                move.w  d4,d1
                bra.s   .fe
.fl:            move.l  (a0),d0
                cmp.l   (a3),d0
                beq.s   .found
                lea     NSZ(a0),a0
.fe:            dbra    d1,.fl
                lea     t_x(pc),a0
                bsr     puts
                move.l  (a3),d0
                bsr     puthex
                bsr     nl
.found:         lea     NSZ(a3),a3
.ge:            dbra    d5,.gl
                move.w  d4,nprev-vars(a4)
                lea     cur,a0
                lea     prev,a1
                move.w  #NNODE*NSZ/4-1,d1
.cc:            move.l  (a0)+,(a1)+
                dbra    d1,.cc
.r:
                rts

; dinfo : ACTION_DISK_INFO au handler de DF0, une fois par seconde
dinfo:
                tst.b   pkbusy-vars(a4)
                bne     .wait
                move.l  tick-vars(a4),d0
                divu    #10,d0
                swap    d0
                tst.w   d0
                bne     .r
; trouve le nœud « DF0 »
                move.l  4.w,a6
                jsr     -132(a6)             ; Forbid
                move.l  dosb-vars(a4),a0
                move.l  34(a0),a0
                move.l  24(a0),d0
                lsl.l   #2,d0
                move.l  d0,a0
                move.l  4(a0),d0
                moveq   #0,d3
.f:             lsl.l   #2,d0
                beq.s   .ff
                move.l  d0,a0
                move.l  40(a0),d1
                lsl.l   #2,d1
                beq.s   .fn
                move.l  d1,a1
                cmp.l   #$03444630,(a1)      ; BSTR "DF0"
                bne.s   .fn
                tst.l   4(a0)                ; dn_Type = 0 (device)
                bne.s   .fn
                move.l  8(a0),d3             ; dn_Task
                bra.s   .ff
.fn:            move.l  (a0),d0
                bra.s   .f
.ff:            jsr     -138(a6)             ; Permit
                tst.l   d3
                beq     .r
; paquet
                lea     pkt,a2
                lea     20(a2),a0            ; sp_Pkt
                move.l  a0,10(a2)            ; ln_Name = &sp_Pkt
                move.l  a2,(a0)              ; dp_Link = &sp_Msg
                lea     pkport,a1
                move.l  a1,4(a0)             ; dp_Port
                move.l  #25,8(a0)            ; ACTION_DISK_INFO
                lea     info,a1
                moveq   #8,d0
.ci:            move.l  #$5A5A5A5A,(a1)+     ; motif : champ non écrit = 5A5A5A5A
                dbra    d0,.ci
                move.l  #info,d0
                lsr.l   #2,d0
                move.l  d0,20(a0)            ; dp_Arg1 = BPTR InfoData
                move.l  d3,a0
                move.l  a2,a1
                jsr     -366(a6)             ; PutMsg
                st      pkbusy-vars(a4)
                clr.w   pkwait-vars(a4)
.wait:
                move.l  4.w,a6
                lea     pkport,a0
                jsr     -372(a6)             ; GetMsg
                tst.l   d0
                bne.s   .got
                addq.w  #1,pkwait-vars(a4)
                cmp.w   #20,pkwait-vars(a4)
                bne.s   .r
                bsr     stamp
                lea     t_dto(pc),a0         ; pas de réponse en 2 s (une seule fois)
                bsr     puts
                bsr     nl
                bra.s   .r
.got:
                sf      pkbusy-vars(a4)
                lea     pkt+20,a0
                lea     info,a1
                lea     lastdi,a3
                moveq   #0,d1
                move.l  12(a0),d0            ; Res1
                cmp.l   (a3),d0
                beq.s   .c1
                moveq   #1,d1
.c1:            move.l  d0,(a3)+
                moveq   #8,d2
.c2:            move.l  (a1)+,d0
                cmp.l   (a3),d0
                beq.s   .c3
                moveq   #1,d1
.c3:            move.l  d0,(a3)+
                dbra    d2,.c2
                tst.l   d1
                beq.s   .r
                bsr     stamp
                lea     t_di(pc),a0
                bsr     puts
                lea     lastdi,a2
                moveq   #9,d5
.p:             move.l  (a2)+,d0
                bsr     puthex
                dbra    d5,.p
                bsr     nl
.r:
                rts

; pnode(a2 = enregistrement, d6 = index) : « N index adresse +4..+24 nom »
pnode:
                lea     t_n(pc),a0
                bsr     puts
                moveq   #0,d0
                move.w  d6,d0
                bsr     puthex
                move.l  a2,a3
                moveq   #9,d5
.pl:            move.l  (a3)+,d0
                bsr     puthex
                dbra    d5,.pl
                moveq   #0,d5
                move.b  (a3),d5              ; longueur BSTR
                cmp.b   #31,d5
                bls.s   .ok
                moveq   #31,d5
.ok:            addq.l  #1,a3
                bra.s   .se
.sl:            move.b  (a3)+,d1
                bsr     putc
.se:            dbra    d5,.sl
                bra     nl

; access : option A, une seule fois, 3 s après le premier DISKREMOVED : Examine(lock gardé), puis
; Lock("Workbench1.3:c"), puis Lock("DF0:") ; émet « AX/AV/AD résultat IoErr » après chaque appel (bloquant
; si un requester s'affiche : le journal reprend à sa disparition).
access:
                tst.b   opta-vars(a4)
                beq     .r
                move.l  acct-vars(a4),d0
                beq     .r
                cmp.l   tick-vars(a4),d0
                bne     .r
                move.l  dosb-vars(a4),a6
                move.l  mylock-vars(a4),d1
                move.l  #fib,d2
                jsr     -102(a6)             ; Examine
                lea     t_ax(pc),a0
                bsr     .log
                move.l  dosb-vars(a4),a6
                lea     vname(pc),a0
                move.l  a0,d1
                moveq   #-2,d2
                jsr     -84(a6)              ; Lock
                lea     t_av(pc),a0
                bsr     .log
                move.l  dosb-vars(a4),a6
                lea     dname(pc),a0
                move.l  a0,d1
                moveq   #-2,d2
                jsr     -84(a6)
                lea     t_ad(pc),a0
                bsr     .log
.r:             rts
.log:           move.l  d0,-(sp)
                move.l  a0,-(sp)
                bsr     stamp
                move.l  (sp)+,a0
                bsr     puts
                move.l  (sp)+,d0
                bsr     puthex
                move.l  dosb-vars(a4),a6
                jsr     -132(a6)             ; IoErr
                bsr     puthex
                bra     nl

nl:             moveq   #10,d1
                bra.s   putc
puts:
                move.b  (a0)+,d1
                beq.s   .r
                bsr.s   putc
                bra.s   puts
.r:
                rts
; putc(d1.b) : ajoute l'octet au journal mémoire (long 0 = longueur) ; série directe seulement avec l'option S
putc:
                move.l  a0,-(sp)
                move.l  logbuf-vars(a4),d2
                beq.s   .ser
                move.l  d2,a0
                move.l  (a0),d2
                cmp.l   #LOGSZ-8,d2
                bhs.s   .ser
                move.b  d1,4(a0,d2.l)
                addq.l  #1,(a0)
.ser:           move.l  (sp)+,a0
                tst.b   opts-vars(a4)
                beq.s   .r
.w:             move.w  SERDATR,d2
                btst    #13,d2
                beq.s   .w
                and.w   #$00FF,d1
                or.w    #$0100,d1
                move.w  d1,SERDAT
.r:             rts
puthex:
                moveq   #7,d3
.h:
                rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:
                bsr.s   putc
                dbra    d3,.h
                moveq   #' ',d1
                bra.s   putc

                cnop    0,4
; NewWindow (intuition.h) : 60x10 en (0,190), BORDERLESS, IDCMP DISKINSERTED|DISKREMOVED, WBENCHSCREEN
nw:             dc.w    0,190,60,10
                dc.b    0,1
                dc.l    $00018000            ; IDCMP DISKINSERTED ($8000) | DISKREMOVED ($10000)
                dc.l    $00000800            ; BORDERLESS
                dc.l    0,0,0,0,0
                dc.w    60,10,60,10
                dc.w    1                    ; WBENCHSCREEN
dosname:        dc.b    "dos.library",0
intname:        dc.b    "intuition.library",0
tdname:         dc.b    "trackdisk.device",0
lkname:         dc.b    "DF0:c",0
t_go:           dc.b    "DCGO ",0
t_lk:           dc.b    "LOCK ",0
t_end:          dc.b    "DCEND",10,0
t_t:            dc.b    "t=",0
t_ev:           dc.b    "EV ",0
t_td:           dc.b    "TD ",0
t_dl:           dc.b    "DL ",0
t_n:            dc.b    "N ",0
t_di:           dc.b    "DI ",0
t_x:            dc.b    "X ",0
t_ax:           dc.b    "AX ",0
t_av:           dc.b    "AV ",0
t_ad:           dc.b    "AD ",0
vname:          dc.b    "Workbench1.3:c",0
dname:          dc.b    "DF0:",0
t_hb:           dc.b    "HB",0
t_dto:          dc.b    "DI-TIMEOUT",0

                section bss,bss
                cnop    0,4
vars:
dosb:           ds.l    1
logbuf:         ds.l    1
acct:           ds.l    1
intb:           ds.l    1
win:            ds.l    1
tick:           ds.l    1
mylock:         ds.l    1
lastcn:         ds.l    1
lastcs:         ds.l    1
ncur:           ds.w    1
nprev:          ds.w    1
pkwait:         ds.w    1
optd:           ds.b    1
optt:           ds.b    1
optl:           ds.b    1
opta:           ds.b    1
opts:           ds.b    1
tdok:           ds.b    1
pkbusy:         ds.b    1
                ds.b    1
                cnop    0,4
pkport:         ds.b    36
tdport:         ds.b    36
tdio:           ds.b    48
                cnop    0,4
pkt:            ds.b    68
info:           ds.l    9
fib:            ds.l    65
lastdi:         ds.l    10
cur:            ds.b    NNODE*NSZ
prev:           ds.b    NNODE*NSZ
