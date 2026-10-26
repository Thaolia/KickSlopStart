; src/dos/feeder.s — feeder clavier -> input.device (intégration F, item 1).
;
; Process (proc_create) qui DRAINE le ring BRUT du clavier (KBD_FEEDRING, alimenté par kbd_interrupt au même point
; que le push cuit) et injecte chaque frappe comme un InputEvent RAWKEY dans input.device via IND_WRITEEVENT ->
; input.device devient la SOURCE UNIQUE du clavier ; ses handlers (console.device) cuisent. Poll COOP-safe à chaque
; trame (timer.device VBLANK, BeginIO TR_ADDREQUEST + Wait) -> pas de busy-poll. Rôle de la tâche d'input.device 1.3
; (spec docs/analysis/intuiticks-repeat-v34.md) : un événement IECLASS_TIMER toutes les 5 trames (10 par seconde) et la
; répétition automatique de la dernière touche enfoncée (délai et période d'input.device, IND_SETTHRESH/SETPERIOD).
;
; SELF-TEST (ifeq SHELL_ON_SCREEN, item 1) : après avoir injecté la 1re frappe, lit console.device CMD_READ (que
; son handler a cuit) et émet « FEEDER OK=<char> » sur série (prouve clavier -> feeder -> input.device -> console).
; Quand SHELL_ON_SCREEN=1 (item 2), pas de self-test : le shell (via le handler écran) consomme console.device.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs input.device/timer.device + exec. AUCUNE lecture ROM.

                include "exec.i"
                include "dospkt.i"

                xdef    feeder_main
                xref    ser_lock             ; exec/boot.s (émission série atomique)
                xref    ser_unlock
                xref    kbd_pushcooked       ; exec/keyboard.s (caractère cuit vers l'anneau du CLI)

IO_DATA2     EQU 40               ; IOStdReq io_Data (local : feeder.s n'inclut pas disk.i)
IO_LENGTH    EQU 36               ; IOStdReq io_Length
IO_ACTUAL    EQU 32               ; IOStdReq io_Actual
CMD_READ     EQU 2                ; console.device CMD_READ
FD_NOREPEAT  EQU $FFFF            ; FD_RPTCODE : aucune répétition
TICK_FRAMES  EQU 5                ; IECLASS_TIMER toutes les 5 trames (100 ms en PAL)
KEY_NOREPEAT EQU $60              ; codes >= $60 (qualificatifs) : jamais répétés, arrêtent la répétition

; bloc d'état (AllocMem)
FD_INPUT   EQU 0                  ; APTR base input.device
FD_CON     EQU 4                  ; APTR base console.device (self-test)
FD_TBASE   EQU 8                  ; APTR base timer.device
FD_RPORT   EQU 12                 ; APTR reply MsgPort
FD_TREQ    EQU 16                 ; APTR timerequest
FD_SIGMASK EQU 20                 ; LONG masque signal du reply port
FD_DONE    EQU 24                 ; BYTE self-test émis
FD_IOREQ   EQU 28                 ; IOStdReq (48) pour input BeginIO
FD_EVENT   EQU 76                 ; InputEvent (22)
FD_RDBUF   EQU 100                ; 4 octets : buffer de lecture console (self-test)
FD_REVENT  EQU 104                ; InputEvent (22) : touche qui se répète (qualificatif | IEQUALIFIER_REPEAT)
FD_RPTCODE EQU 126                ; WORD : code de la touche qui se répète ($FFFF : aucune)
FD_RPTDUE  EQU 128                ; LONG : trame (VBL_COUNT) de la prochaine répétition
FD_TICKDUE EQU 132                ; LONG : trame du prochain IECLASS_TIMER
FD_GSTREQ  EQU 136                ; timerequest (40) : TR_GETSYSTIME pour l'horodatage
FD_SIZE    EQU 176

feeder_main:
                move.l  ($4).w,a6
                move.l  #FD_SIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fm_idle             ; pas de RAM -> idle
                move.l  d0,a5                ; a5 = état (persistant)
                lea     EB_DEVICELIST(a6),a0 ; input.device
                lea     fd_inputname(pc),a1
                jsr     LVO_FINDNAME(a6)
                move.l  d0,FD_INPUT(a5)
                beq     .fm_idle
                lea     EB_DEVICELIST(a6),a0 ; console.device
                lea     fd_conname(pc),a1
                jsr     LVO_FINDNAME(a6)
                move.l  d0,FD_CON(a5)
                ; --- setup timer.device MICROHZ (poll COOP) ---
                lea     EB_DEVICELIST(a6),a0
                lea     fd_timername(pc),a1
                jsr     LVO_FINDNAME(a6)
                tst.l   d0
                beq     .fm_idle
                move.l  d0,FD_TBASE(a5)
                moveq   #-1,d0               ; AllocSignal
                jsr     LVO_ALLOCSIGNAL(a6)
                moveq   #1,d1
                lsl.l   d0,d1
                move.l  d1,FD_SIGMASK(a5)
                move.l  d0,d3                ; d3 = n° de bit
                move.l  #MP_SIZE,d0          ; reply port
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fm_idle
                move.l  d0,FD_RPORT(a5)
                move.l  d0,a3
                move.b  #NT_MSGPORT,LN_TYPE(a3)
                move.b  #PA_SIGNAL,MP_FLAGS(a3)
                move.b  d3,MP_SIGBIT(a3)
                move.l  EB_THISTASK(a6),MP_SIGTASK(a3)
                lea     MP_MSGLIST(a3),a1    ; NEWLIST en ligne
                move.l  a1,d0
                addq.l  #4,d0
                move.l  d0,(a1)
                clr.l   4(a1)
                move.l  a1,8(a1)
                move.l  #TR_SIZE,d0          ; timerequest
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .fm_idle
                move.l  d0,FD_TREQ(a5)
                move.l  d0,a1
                move.l  FD_RPORT(a5),MN_REPLYPORT(a1)
                move.l  FD_TBASE(a5),IO_DEVICE(a1)
                move.l  #UNIT_VBLANK,IO_UNIT(a1)
                lea     FD_GSTREQ(a5),a1
                move.l  FD_TBASE(a5),IO_DEVICE(a1)
                move.w  #FD_NOREPEAT,FD_RPTCODE(a5)
.fm_loop:
                bsr     fd_poll_wait         ; une trame (COOP)
                bsr     fd_timed             ; tic IECLASS_TIMER et répétition échue
.fm_drain:
                move.w  KBD_FHEAD,d2
                cmp.w   KBD_FTAIL,d2
                beq.s   .fm_loop             ; ring vide -> prochaine trame
                lea     KBD_FEEDRING,a0
                move.w  0(a0,d2.w),d4        ; d4 = (qual<<8)|keycode
                addq.w  #2,d2
                and.w   #KBD_FRMASK,d2
                move.w  d2,KBD_FHEAD         ; avance HEAD (consommé)
                ; construit l'InputEvent RAWKEY
                lea     FD_EVENT(a5),a1
                clr.l   IE_NEXTEVENT(a1)
                move.b  #IECLASS_RAWKEY,IE_CLASS(a1)
                move.b  d4,IE_CODE+1(a1)     ; keycode (octet bas de ie_Code word)
                clr.b   IE_CODE(a1)
                moveq   #0,d0
                move.w  d4,d0
                lsr.w   #8,d0                ; qualifieurs
                move.w  d0,IE_QUALIFIER(a1)
                bsr     fd_stamp
                bsr     fd_repeat_key        ; arme / arrête la répétition selon cette frappe
                lea     FD_EVENT(a5),a0
                bsr     fd_write
                ifeq    SHELL_ON_SCREEN
                bsr     fd_selftest          ; item 1 : émet « FEEDER OK=<char> » une fois (lit console.device)
                endc
                bra.s   .fm_drain
.fm_idle:
                move.l  ($4).w,a6            ; échec setup : dort sur un signal jamais reçu (COOP, ne spin pas)
.fm_idle_lp:
                moveq   #0,d0
                jsr     LVO_WAIT(a6)
                bra.s   .fm_idle_lp

; fd_write(a0 = InputEvent) : IND_WRITEEVENT vers input.device. a5 = état, a6 = SysBase. Préserve a5/a6.
fd_write:
                ifeq    FEEDER_NO_WRITEEVENT
                movem.l a2-a3,-(sp)
                lea     FD_IOREQ(a5),a3
                move.l  FD_INPUT(a5),IO_DEVICE(a3)
                move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
                move.l  a0,IO_DATA2(a3)
                move.l  FD_INPUT(a5),a6
                move.l  a3,a1
                jsr     -30(a6)              ; input BeginIO (IND_WRITEEVENT)
                move.l  ($4).w,a6
                movem.l (sp)+,a2-a3
                endc                         ; RED FEEDER_NO_WRITEEVENT : n'injecte rien dans input.device
                rts

; fd_stamp(a1 = InputEvent) : ie_TimeStamp = heure système (timer.device TR_GETSYSTIME, synchrone). Préserve a1/a5/a6.
fd_stamp:
                movem.l a1-a2/a6,-(sp)
                move.l  a1,a2
                lea     FD_GSTREQ(a5),a1
                move.w  #TR_GETSYSTIME,IO_COMMAND(a1)
                move.b  #IOF_QUICK,IO_FLAGS(a1)
                move.l  FD_TBASE(a5),a6
                jsr     TD_BEGINIO(a6)
                lea     FD_GSTREQ(a5),a1
                move.l  TV_SECS(a1),IE_TIMESTAMP(a2)
                move.l  TV_MICRO(a1),IE_TIMESTAMP+4(a2)
                movem.l (sp)+,a1-a2/a6
                rts

; fd_frames(a0 = timeval) -> d0 = nombre de trames : max(1, secondes × 50 + ⌈µs / 20 000⌉), comme UNIT_VBLANK.
fd_frames:
                move.l  (a0),d0
                mulu    #50,d0
                move.l  4(a0),d1
                add.l   #20000-1,d1
                divu    #20000,d1
                and.l   #$FFFF,d1
                add.l   d1,d0
                bne.s   .fr_r
                moveq   #1,d0
.fr_r:
                rts

; fd_repeat_key(a1 = événement RAWKEY de la frappe) : enfoncement d'une touche < $60 -> elle devient la touche qui se
; répète (copie avec IEQUALIFIER_REPEAT, 1re répétition après le délai) ; enfoncement d'un qualificatif (>= $60) ->
; arrêt ; relâchement de la touche qui se répète, ou qualificatif différent (masques $05FF / $07FF) -> arrêt.
; a5 = état. Préserve a1/a5/a6.
fd_repeat_key:
                move.w  IE_CODE(a1),d0
                bclr    #7,d0
                bne.s   .rk_up
                cmp.w   #KEY_NOREPEAT,d0
                bhs.s   .rk_stop
                move.w  d0,FD_RPTCODE(a5)
                lea     FD_REVENT(a5),a0
                moveq   #IE_SIZEOF/2-1,d1
                move.l  a1,-(sp)
.rk_cp:
                move.w  (a1)+,(a0)+
                dbra    d1,.rk_cp
                move.l  (sp)+,a1
                or.w    #IEQUALIFIER_REPEAT,FD_REVENT+IE_QUALIFIER(a5)
                move.l  FD_INPUT(a5),a0
                lea     ID_THRESH(a0),a0
                bsr.s   fd_frames
                add.l   VBL_COUNT,d0
                move.l  d0,FD_RPTDUE(a5)
                rts
.rk_up:
                cmp.w   FD_RPTCODE(a5),d0
                beq.s   .rk_stop
                move.w  FD_REVENT+IE_QUALIFIER(a5),d0
                and.w   #$05FF,d0
                move.w  IE_QUALIFIER(a1),d1
                and.w   #$07FF,d1
                cmp.w   d1,d0
                beq.s   .rk_ret
.rk_stop:
                move.w  #FD_NOREPEAT,FD_RPTCODE(a5)
.rk_ret:
                rts

; fd_timed : à chaque trame, IECLASS_TIMER si son échéance est atteinte (toutes les TICK_FRAMES trames), puis
; répétition de la touche tenue si son échéance est atteinte (réarmée à la période). a5 = état, a6 = SysBase.
fd_timed:
                move.l  VBL_COUNT,d0
                sub.l   FD_TICKDUE(a5),d0
                bmi.s   .td_rpt
                move.l  VBL_COUNT,d0
                addq.l  #TICK_FRAMES,d0
                move.l  d0,FD_TICKDUE(a5)
                lea     FD_EVENT(a5),a1
                clr.l   IE_NEXTEVENT(a1)
                move.w  #IECLASS_TIMER<<8,IE_CLASS(a1)
                clr.l   IE_CODE(a1)          ; code et qualificatif
                clr.l   IE_X(a1)
                bsr     fd_stamp
                move.l  a1,a0
                bsr     fd_write
.td_rpt:
                cmp.w   #FD_NOREPEAT,FD_RPTCODE(a5)
                beq.s   .td_ret
                move.l  VBL_COUNT,d0
                sub.l   FD_RPTDUE(a5),d0
                bmi.s   .td_ret
                move.l  FD_INPUT(a5),a0
                lea     ID_PERIOD(a0),a0
                bsr     fd_frames
                add.l   VBL_COUNT,d0
                move.l  d0,FD_RPTDUE(a5)
                lea     FD_REVENT(a5),a0     ; le modèle reste intact (un handler peut neutraliser l'événement
                lea     FD_EVENT(a5),a1      ; transmis, ex. intuition vers une fenêtre RAWKEY)
                moveq   #IE_SIZEOF/2-1,d0
.td_cp:
                move.w  (a0)+,(a1)+
                dbra    d0,.td_cp
                lea     FD_EVENT(a5),a1
                clr.l   IE_NEXTEVENT(a1)
                bsr     fd_stamp
                move.l  a1,a0
                bsr     fd_write
                move.w  FD_REVENT+IE_CODE(a5),d0  ; le CLI de l'écran lit l'anneau cuit, pas input.device : la
                move.w  FD_REVENT+IE_QUALIFIER(a5),d1 ; répétition y dépose aussi son caractère
                jsr     LVO_DISABLE(a6)      ; (deux producteurs : l'interruption clavier et nous)
                jsr     kbd_pushcooked
                jsr     LVO_ENABLE(a6)
.td_ret:
                rts

; fd_poll_wait : attente d'une trame via timer.device VBLANK. a5 = état, a6 = SysBase. Préserve a5.
fd_poll_wait:
                movem.l d2-d4/a0-a4,-(sp)
                move.l  FD_TREQ(a5),a1
                clr.l   TV_SECS(a1)
                moveq   #1,d0
                move.l  d0,TV_MICRO(a1)
                move.w  #TR_ADDREQUEST,IO_COMMAND(a1)
                move.l  FD_TBASE(a5),a0
                move.l  a0,a6
                jsr     TD_BEGINIO(a6)
                move.l  ($4).w,a6
                move.l  FD_SIGMASK(a5),d0
                jsr     LVO_WAIT(a6)
                move.l  FD_RPORT(a5),a0
                jsr     LVO_GETMSG(a6)
                movem.l (sp)+,d2-d4/a0-a4
                rts

                ifeq    SHELL_ON_SCREEN
; fd_selftest : item 1 — lit UNE fois console.device CMD_READ (cuit par son handler) et émet « FEEDER OK=<char> »
; sur série. Done-flag dans FD_DONE. a5 = état, a6 = SysBase. Préserve a5.
fd_selftest:
                tst.b   FD_DONE(a5)
                bne.s   .st_ret
                move.l  FD_CON(a5),d0
                beq.s   .st_ret
                lea     FD_IOREQ(a5),a3      ; console CMD_READ 1 octet -> FD_RDBUF
                move.l  FD_CON(a5),IO_DEVICE(a3)
                move.w  #CMD_READ,IO_COMMAND(a3)
                lea     FD_RDBUF(a5),a0
                move.l  a0,IO_DATA2(a3)
                move.l  #1,IO_LENGTH(a3)
                clr.l   IO_ACTUAL(a3)
                clr.b   FD_RDBUF(a5)
                move.l  FD_CON(a5),a6
                move.l  a3,a1
                jsr     -30(a6)              ; console BeginIO (CMD_READ)
                move.l  ($4).w,a6
                tst.l   IO_ACTUAL(a3)
                beq.s   .st_ret              ; rien lu ce tick -> réessaie au prochain
                st      FD_DONE(a5)          ; self-test émis une seule fois
                jsr     ser_lock             ; marqueur entier atomique (pas d'entrelacement)
                lea     fd_msg_ok(pc),a0     ; « FEEDER OK= »
                bsr     fd_puts
                move.b  FD_RDBUF(a5),d0      ; le char cuit
                bsr     fd_putc
                moveq   #13,d0
                bsr     fd_putc
                moveq   #10,d0
                bsr     fd_putc
                jsr     ser_unlock
.st_ret:
                rts

; fd_puts(a0 = chaîne NUL-term) / fd_putc(d0.b) : émission série bornée (TBE). Clobbe d0/d1.
fd_puts:
                move.b  (a0)+,d0
                beq.s   .ps_ret
                bsr.s   fd_putc
                bra.s   fd_puts
.ps_ret:
                rts
fd_putc:                                     ; émet d0.b sur série (poll TBE borné). Clobbe d0/d1/d2 ; préserve a0.
                and.w   #$00FF,d0
                or.w    #$0100,d0            ; bit stop
                move.w  #$3000,d1            ; timeout
.pc_wt:
                move.w  SERDATR,d2
                btst    #13,d2               ; TBE (transmit buffer empty) ?
                bne.s   .pc_tx
                dbra    d1,.pc_wt
                rts                          ; timeout -> abandonne ce caractère
.pc_tx:
                move.w  d0,SERDAT
                rts
fd_msg_ok:
                dc.b    "FEEDER OK=",0
                even
                endc

fd_inputname:
                dc.b    "input.device",0
fd_conname:
                dc.b    "console.device",0
fd_timername:
                dc.b    "timer.device",0
                even
