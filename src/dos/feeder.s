; src/dos/feeder.s — feeder clavier -> input.device (intégration F, item 1).
;
; Process (proc_create) qui DRAINE le ring BRUT du clavier (KBD_FEEDRING, alimenté par kbd_interrupt au même point
; que le push cuit) et injecte chaque frappe comme un InputEvent RAWKEY dans input.device via IND_WRITEEVENT ->
; input.device devient la SOURCE UNIQUE du clavier ; ses handlers (console.device) cuisent. Poll COOP-safe sur tick
; timer.device MICROHZ (BeginIO TR_ADDREQUEST + Wait, comme con_handler) -> pas de busy-poll.
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

IO_DATA2     EQU 40               ; IOStdReq io_Data (local : feeder.s n'inclut pas disk.i)
IO_LENGTH    EQU 36               ; IOStdReq io_Length
IO_ACTUAL    EQU 32               ; IOStdReq io_Actual
CMD_READ     EQU 2                ; console.device CMD_READ
FEED_POLL_US EQU 10000            ; 10 ms par tick de poll

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
FD_SIZE    EQU 108

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
                move.l  #UNIT_MICROHZ,IO_UNIT(a1)
.fm_loop:
                bsr     fd_poll_wait         ; ~10 ms (COOP)
.fm_drain:
                move.w  KBD_FHEAD,d2
                cmp.w   KBD_FTAIL,d2
                beq.s   .fm_loop             ; ring vide -> prochain tick
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
                ifeq    FEEDER_NO_WRITEEVENT
                lea     FD_IOREQ(a5),a3      ; IND_WRITEEVENT vers input.device
                move.l  FD_INPUT(a5),IO_DEVICE(a3)
                move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
                lea     FD_EVENT(a5),a0
                move.l  a0,IO_DATA2(a3)
                move.l  FD_INPUT(a5),a6
                move.l  a3,a1
                jsr     -30(a6)              ; input BeginIO (IND_WRITEEVENT)
                move.l  ($4).w,a6
                endc                         ; RED FEEDER_NO_WRITEEVENT : n'injecte rien dans input.device
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

; fd_poll_wait : une attente ~FEED_POLL_US via timer.device MICROHZ. a5 = état, a6 = SysBase. Préserve a5.
fd_poll_wait:
                movem.l d2-d4/a0-a4,-(sp)
                move.l  FD_TREQ(a5),a1
                clr.l   TV_SECS(a1)
                move.l  #FEED_POLL_US,TV_MICRO(a1)
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
