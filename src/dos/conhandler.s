; src/dos/conhandler.s — process handler console-série (E1). Même forme que dos_handler_df0 (D3b) : corps d'un
; Process (créé par proc_create) qui boucle WaitPort/GetMsg sur son pr_MsgPort et sert les DOS packets d'une
; CONSOLE au lieu d'un fichier OFS. C'est le substitut du console.device : en Bootstrap réel (F) on remplace CE
; handler par un console.device sans toucher au binaire shell (le shell fait tout son IO via FileHandles DOS).
;
; Actions servies :
;   FINDINPUT / FINDOUTPUT (ouvrir « CON: ») -> RES1 = clé non-nulle (console globale, pas d'état par-handle).
;   WRITE (ARG1=clé, ARG2=src, ARG3=len)     -> émet len octets sur le série (TX, poll TBE borné). RES1 = len.
;   READ  (ARG1=clé, ARG2=dest, ARG3=len)    -> lit UNE LIGNE jusqu'au CR, avec écho. RES1 = octets. Sources
;                                               d'entrée : le ring clavier LIVE (F2b, con_ring_get) PUIS le RBF série.
;   END (fermer)                              -> RES1 = DOSTRUE.
;
; READ bloque PROPREMENT (COOP-safe) : poll sur tick timer.device MICROHZ (BeginIO TR_ADDREQUEST + Wait, précédent
; task_timer), draine RBF à chaque réveil. PAS de busy-poll (incompatible COOP) ; PAS d'interrupt RBF niveau-5
; (différé à F, cf. M7k). Latence ~1 tick, overrun en rafale (Paula RX = 1 octet) -> frappe humaine lente OK.
; Piste IMPLÉMENTATION (« clean ») : spec analyse dos + AutoDocs exec (timer.device/MsgPort) + HRM (série). AUCUNE lecture ROM.

                include "exec.i"
                include "dospkt.i"

                xdef    con_handler
                xref    ser_lock             ; exec/boot.s (émission série atomique)
                xref    ser_unlock

CON_POLL_US     EQU 20000            ; 20 ms par tick de poll RX (latence d'entrée ~1 tick)
ERROR_ACTION_NOT_KNOWN EQU 209       ; dos/dos.i : action non supportée
CON_CMD_READ    EQU 2                ; io_Command CMD_READ (console.device)
CON_CMD_WRITE   EQU 3                ; io_Command CMD_WRITE
CON_IODATA      EQU 40               ; IOStdReq io_Data (local : conhandler n'inclut pas disk.i)
CON_IOLEN       EQU 36               ; IOStdReq io_Length
CON_IOACT       EQU 32               ; IOStdReq io_Actual

; bloc d'état (AllocMem au démarrage, pointeur publié dans CON_STATE)
CS_TBASE        EQU 0                ; APTR base timer.device
CS_RPORT        EQU 4                ; APTR reply MsgPort (tick timer)
CS_TREQ         EQU 8                ; APTR timerequest réutilisé
CS_SIGMASK      EQU 12               ; LONG masque du signal du reply port
CS_DEST         EQU 16               ; APTR destination READ courante
CS_MAX          EQU 20               ; LONG taille max READ
CS_CNT          EQU 24               ; LONG octets accumulés par READ
; SHELL_ON_SCREEN (intégration F, item 2) : le handler rend AUSSI à l'écran via console.device + lit le clavier
; via console.device (alimenté par le feeder). Champs toujours présents (coût négligeable si le flag est off).
CS_CONBASE      EQU 28               ; APTR base console.device
CS_ECHO         EQU 32               ; BYTE tampon d'écho 1 octet (CMD_WRITE écran)
CS_CONIO        EQU 36               ; IOStdReq (48) pour BeginIO console.device
CS_SIZE         EQU 84

; con_handler : corps du process. GPR à zéro à l'entrée (frame AddTask) -> recharge SysBase.
con_handler:
                move.l  ($4).w,a6
                clr.l   CON_STATE            ; défaut : pas d'état -> READ renvoie EOF (WRITE marche quand même)
                ; --- setup timer.device MICROHZ (une fois) : base + signal + reply port + timerequest ---
                lea     EB_DEVICELIST(a6),a0
                lea     con_timername(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .setup_done          ; pas de timer -> WRITE marche, READ -> EOF
                move.l  d0,d2                ; d2 = base timer.device
                move.l  #CS_SIZE,d0          ; bloc d'état
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .setup_done
                move.l  d0,a4                ; a4 = état (temp ; réassigné dans la boucle)
                move.l  d2,CS_TBASE(a4)
                moveq   #-1,d0               ; AllocSignal -> bit du reply port
                jsr     LVO_ALLOCSIGNAL(a6)
                move.l  d0,d3                ; d3 = n° de bit
                moveq   #1,d1
                lsl.l   d0,d1                ; d1 = 1<<bit
                move.l  d1,CS_SIGMASK(a4)
                move.l  #MP_SIZE,d0          ; reply port
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .setup_done          ; état laissé alloué (boot-time, bénin) -> CON_STATE reste 0
                move.l  d0,a3                ; a3 = reply port (temp)
                move.l  d0,CS_RPORT(a4)
                move.b  #NT_MSGPORT,LN_TYPE(a3)
                move.b  #PA_SIGNAL,MP_FLAGS(a3)
                move.b  d3,MP_SIGBIT(a3)
                move.l  EB_THISTASK(a6),MP_SIGTASK(a3)
                lea     MP_MSGLIST(a3),a1    ; NEWLIST(mp_MsgList) en ligne
                move.l  a1,d0
                addq.l  #4,d0
                move.l  d0,(a1)
                clr.l   4(a1)
                move.l  a1,8(a1)
                move.l  #TR_SIZE,d0          ; timerequest
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .setup_done
                move.l  d0,a1
                move.l  d0,CS_TREQ(a4)
                move.l  CS_RPORT(a4),MN_REPLYPORT(a1)
                move.l  CS_TBASE(a4),IO_DEVICE(a1)
                move.l  #UNIT_MICROHZ,IO_UNIT(a1)
                ifne    SHELL_ON_SCREEN
                lea     EB_DEVICELIST(a6),a0 ; item 2 : base console.device (rendu écran + lecture clavier via feeder)
                lea     con_consolename(pc),a1
                jsr     LVO_FINDNAME(a6)
                move.l  d0,CS_CONBASE(a4)    ; 0 si absent -> WRITE/READ écran se dégradent proprement
                endc
                move.l  a4,CON_STATE         ; publie l'état -> READ activé
.setup_done:
                move.l  EB_THISTASK(a6),a2
                lea     PR_MSGPORT(a2),a2    ; a2 = son propre pr_MsgPort
.hl:
                move.l  a2,a0
                jsr     LVO_WAITPORT(a6)
                move.l  a2,a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .hl
                move.l  d0,a3                ; a3 = Message
                move.l  LN_NAME(a3),a4       ; a4 = DosPacket
                clr.l   DP_RES2(a4)
                move.l  DP_TYPE(a4),d0
                cmp.l   #ACTION_FINDINPUT,d0
                beq     .open
                cmp.l   #ACTION_FINDOUTPUT,d0
                beq     .open
                cmp.l   #ACTION_WRITE,d0
                beq     .write
                cmp.l   #ACTION_READ,d0
                beq     .read
                cmp.l   #ACTION_END,d0
                beq     .end
                move.l  #DOSFALSE,DP_RES1(a4)
                move.l  #ERROR_ACTION_NOT_KNOWN,DP_RES2(a4)
                bra     .reply

.open:
                move.l  #1,DP_RES1(a4)       ; clé non-nulle (console globale)
                bra     .reply
.end:
                move.l  #DOSTRUE,DP_RES1(a4)
                bra     .reply

.write:
                ifne    E1_NO_WRITE
                move.l  DP_ARG3(a4),DP_RES1(a4)  ; RED E1_NO_WRITE : prétend écrire, n'émet rien
                bra     .reply
                endc
                move.l  DP_ARG3(a4),DP_RES1(a4)  ; RES1 = len
                ifne    SHELL_ON_SCREEN
                ; item 2 : rend le buffer ENTIER à l'écran via console.device CMD_WRITE (le miroir série suit)
                move.l  CON_STATE,a0
                move.l  a0,d0
                beq.s   .wr_mirror
                move.l  CS_CONBASE(a0),d0
                beq.s   .wr_mirror
                lea     CS_CONIO(a0),a1
                move.l  d0,IO_DEVICE(a1)
                move.w  #CON_CMD_WRITE,IO_COMMAND(a1)
                move.l  DP_ARG2(a4),CON_IODATA(a1)
                move.l  DP_ARG3(a4),CON_IOLEN(a1)
                move.l  d0,a6                ; a6 = base console.device pour BeginIO
                jsr     -30(a6)              ; console BeginIO (CMD_WRITE écran)
                move.l  ($4).w,a6            ; restaure a6 = SysBase
.wr_mirror:
                endc
                move.l  DP_ARG2(a4),a5       ; src (a5 survit à con_putc)
                move.l  DP_ARG3(a4),d3       ; len (d3 survit à con_putc)
                tst.l   d3
                beq     .reply
                jsr     ser_lock             ; buffer entier atomique sur le série (pas d'entrelacement de marqueur)
.wr_lp:
                move.b  (a5)+,d0
                bsr     con_putc
                subq.l  #1,d3
                bne.s   .wr_lp
                jsr     ser_unlock
                bra     .reply

.read:
                move.l  CON_STATE,d0
                beq     .rd_eof              ; pas de timer -> EOF
                move.l  d0,a0
                move.l  DP_ARG2(a4),CS_DEST(a0)
                move.l  DP_ARG3(a4),CS_MAX(a0)
                clr.l   CS_CNT(a0)
.rd_tick:
                bsr     con_poll_wait        ; ~20 ms (préserve a2/a3/a4/a6)
.rd_drain:
                ifne    SHELL_ON_SCREEN
                bsr     con_scr_read         ; item 2 : source = console.device CMD_READ (clavier via feeder)
                beq.s   .rd_tick             ; rien ce tick -> attendre le prochain
                else
                bsr     con_ring_get         ; F2b : clavier LIVE d'abord (ring SPSC, consommateur)
                bne.s   .rd_got              ; une touche dispo -> d0.b = ASCII
                move.w  SERDATR,d0
                btst    #14,d0               ; sinon RBF série : octet reçu ?
                beq.s   .rd_tick             ; rien des deux ce tick -> attendre le prochain
                and.w   #$00FF,d0            ; octet reçu (série)
                move.w  #INTF_RBF,INTREQ     ; acquitte RBF
                endc
.rd_got:
                move.l  d0,d4                ; d4 = octet (survit con_putc)
                bsr     con_putc             ; écho série (miroir)
                ifne    SHELL_ON_SCREEN
                move.b  d4,d0
                bsr     con_scr_emit         ; écho écran
                endc
                cmp.b   #13,d4
                bne.s   .rd_store
                moveq   #10,d0               ; CR -> aussi LF pour l'affichage
                bsr     con_putc
                ifne    SHELL_ON_SCREEN
                moveq   #10,d0
                bsr     con_scr_emit         ; CR -> LF à l'écran aussi
                endc
.rd_store:
                move.l  CON_STATE,a0
                move.l  CS_CNT(a0),d1
                cmp.l   CS_MAX(a0),d1
                bge.s   .rd_done             ; buffer plein
                move.l  CS_DEST(a0),a1
                move.b  d4,(0,a1,d1.l)       ; dest[cnt] = octet
                addq.l  #1,CS_CNT(a0)
                cmp.b   #13,d4               ; fin de ligne ?
                beq.s   .rd_done
                bra.s   .rd_drain            ; vider d'autres octets dispo ce tick
.rd_done:
                move.l  CON_STATE,a0
                move.l  CS_CNT(a0),DP_RES1(a4)
                bra     .reply
.rd_eof:
                clr.l   DP_RES1(a4)
.reply:
                move.l  a3,a1
                jsr     LVO_REPLYMSG(a6)
                bra     .hl

; con_putc : émet d0.b sur le série (poll TBE borné). Clobbe d0/d1/d2 ; préserve le reste.
con_putc:
                and.w   #$00FF,d0
                or.w    #$0100,d0
                move.w  #$2000,d2
.cp_w:
                move.w  SERDATR,d1
                btst    #13,d1               ; TBE (buffer TX vide) ?
                bne.s   .cp_tx
                dbra    d2,.cp_w
                rts                          ; timeout -> abandon (borné)
.cp_tx:
                move.w  d0,SERDAT
                rts

; con_poll_wait : une attente ~CON_POLL_US via timer.device MICROHZ. Préserve tout le contexte boucle.
con_poll_wait:
                movem.l d0-d2/a0-a4,-(sp)
                move.l  CON_STATE,a2
                move.l  CS_TREQ(a2),a1
                clr.l   TV_SECS(a1)
                move.l  #CON_POLL_US,TV_MICRO(a1)
                move.w  #TR_ADDREQUEST,IO_COMMAND(a1)
                move.l  CS_TBASE(a2),a0      ; base device
                move.l  a6,-(sp)
                move.l  a0,a6
                jsr     TD_BEGINIO(a6)       ; BeginIO(a6=base, a1=requête)
                move.l  (sp)+,a6
                move.l  CS_SIGMASK(a2),d0
                jsr     LVO_WAIT(a6)         ; BLOQUE ~20 ms (yield -> COOP-safe)
                move.l  CS_RPORT(a2),a0
                jsr     LVO_GETMSG(a6)       ; retire la réponse (requête réutilisée au tick suivant)
                movem.l (sp)+,d0-d2/a0-a4
                rts

; con_ring_get : F2b — retire un octet du ring clavier (consommateur SPSC). -> d0.b = ASCII (propre), Z=0
; (obtenu) | Z=1 (ring vide). Lit KBD_HEAD/KBD_TAIL, avance KBD_HEAD. Lock-free (pas de masquage : le
; producteur kbd_interrupt écrit la donnée AVANT d'avancer KBD_TAIL). Clobbe d0/d1/a0 (réassignés par la boucle READ).
con_ring_get:
                move.w  KBD_HEAD,d1
                cmp.w   KBD_TAIL,d1
                beq.s   .crg_empty           ; HEAD==TAIL -> vide
                lea     KBD_RING,a0
                moveq   #0,d0
                move.b  0(a0,d1.w),d0        ; d0 = octet lu
                addq.w  #1,d1
                and.w   #KBD_RMASK,d1
                move.w  d1,KBD_HEAD          ; avance HEAD (publie la consommation)
                moveq   #1,d1
                tst.b   d1                   ; Z=0 -> octet obtenu
                rts
.crg_empty:
                moveq   #0,d1
                tst.b   d1                   ; Z=1 -> ring vide
                rts

                ifne    SHELL_ON_SCREEN
; con_scr_read (item 2) : lit 1 octet via console.device CMD_READ (clavier cuit par son handler, via le feeder).
; -> d0.b = octet, Z=0 (obtenu) | Z=1 (rien ce tick). a6=SysBase. Préserve d4/a2-a4 (console BeginIO les sauve).
con_scr_read:
                move.l  CON_STATE,a1
                move.l  a1,d0
                beq.s   .sr_empty
                move.l  CS_CONBASE(a1),d0
                beq.s   .sr_empty
                lea     CS_CONIO(a1),a0
                move.l  d0,IO_DEVICE(a0)
                move.w  #CON_CMD_READ,IO_COMMAND(a0)
                move.l  a1,d1
                add.l   #CS_ECHO,d1
                move.l  d1,CON_IODATA(a0)    ; io_Data = &CS_ECHO (1 octet)
                move.l  #1,CON_IOLEN(a0)
                clr.l   CON_IOACT(a0)
                move.l  d0,a6                ; a6 = base console.device
                move.l  a0,a1
                jsr     -30(a6)              ; console BeginIO (CMD_READ)
                move.l  ($4).w,a6            ; restaure SysBase
                move.l  CON_STATE,a0
                lea     CS_CONIO(a0),a1
                move.l  CON_IOACT(a1),d0     ; octets réellement lus
                beq.s   .sr_empty
                moveq   #0,d0
                move.b  CS_ECHO(a0),d0       ; d0.b = octet lu
                moveq   #1,d1
                tst.b   d1                   ; Z=0 -> obtenu
                rts
.sr_empty:
                moveq   #0,d1
                tst.b   d1                   ; Z=1 -> rien
                rts

; con_scr_emit (item 2) : écrit d0.b à l'écran via console.device CMD_WRITE (1 octet). a6=SysBase. Préserve d4/a2-a4.
con_scr_emit:
                move.l  CON_STATE,a1
                move.l  a1,d1
                beq.s   .se_ret
                move.l  CS_CONBASE(a1),d1
                beq.s   .se_ret
                move.b  d0,CS_ECHO(a1)
                lea     CS_CONIO(a1),a0
                move.l  d1,IO_DEVICE(a0)
                move.w  #CON_CMD_WRITE,IO_COMMAND(a0)
                move.l  a1,d0
                add.l   #CS_ECHO,d0
                move.l  d0,CON_IODATA(a0)
                move.l  #1,CON_IOLEN(a0)
                move.l  d1,a6                ; a6 = base console.device
                move.l  a0,a1
                jsr     -30(a6)              ; console BeginIO (CMD_WRITE 1 octet)
                move.l  ($4).w,a6
.se_ret:
                rts

con_consolename:
                dc.b    "console.device",0
                EVEN
                endc

con_timername:
                dc.b    "timer.device",0
                EVEN
