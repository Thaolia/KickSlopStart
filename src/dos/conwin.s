; src/dos/conwin.s - ROM console handler of the CON: and RAW: nodes (BCPL segment of dn_SegList, shared GV). Each Open
; of "CON:x/y/w/h/title" starts a process (starthandler) that opens its window on the Workbench screen, attaches
; console.device to it and serves packets until the last END. dn_Startup (Arg2 of the startup packet): 0 = CON (line
; edited with echo: backspace, Ctrl-\ = end of file), 1 = RAW (raw characters, no echo).
; Packets: FINDINPUT/FINDOUTPUT/FINDUPDATE (interactive stream), READ, WRITE, END, WAIT_CHAR, SCREEN_MODE, DISK_INFO.
; Keys arrive through a console.device read that is always pending, in parallel with the packets.
; IMPLEMENTATION track ("clean"): spec docs/analysis/handlers-v34.md §2-3 + AutoDocs (console.device, intuition,
; packets). NO ROM reading.

                include "exec.i"
                include "dospkt.i"

                xdef    conwin_seg

ACTION_WAIT_CHAR   EQU 20
ACTION_SCREEN_MODE EQU 994
ERROR_ACTION_UNKNOWN EQU 209
ERROR_BAD_STREAM   EQU 206
CMD_READ_C      EQU 2
CMD_WRITE_C     EQU 3
LVO_OPENWINDOW_I EQU -204
LVO_CLOSEWINDOW_I EQU -72
ID_DISKTYPE     EQU 24               ; InfoData
ID_VOLUMENODE   EQU 28
ID_INUSE        EQU 32               ; id_InUse: our console IOStdReq (SetMap sends CD_SETKEYMAP to its unit)

; handler state (AllocMem, a5)
CW_PKT          EQU 0                ; BPTR of the current packet
CW_MODE         EQU 4                ; LONG: 0 CON, otherwise RAW
CW_OPENS        EQU 8                ; open streams
CW_IBASE        EQU 12
CW_WIN          EQU 16
CW_RPORT        EQU 20               ; MsgPort for console reads
CW_EOF          EQU 24               ; BYTE: Ctrl-\ received, returned on the next read
CW_RDON         EQU 25               ; BYTE: console read in progress
CW_KEY          EQU 26               ; BYTE: character received
CW_CSI          EQU 27               ; BYTE: inside a CSI sequence (line mode skips cursor and function keys)
CW_LLEN         EQU 28               ; LONG: bytes typed into CW_LINE
CW_DLV          EQU 32               ; LONG: deliverable bytes (completed line in CON, everything in RAW)
CW_RQN          EQU 36               ; LONG: pending reads
CW_RQ           EQU 40               ; CW_RQMAX x BPTR of pending READ packets
CW_RQMAX        EQU 8
CW_RIO          EQU CW_RQ+CW_RQMAX*4 ; read IOStdReq (48)
CW_WIO          EQU CW_RIO+48        ; write IOStdReq (48)
CW_NW           EQU CW_WIO+48        ; NewWindow (48)
CW_TITLE        EQU CW_NW+48         ; title (CW_TITLEMAX)
CW_TITLEMAX     EQU 80
CW_LINE         EQU CW_TITLE+CW_TITLEMAX  ; line buffer
CW_LINEMAX      EQU 256
CW_WCPKT        EQU CW_LINE+CW_LINEMAX   ; BPTR of a WAIT_CHAR waiting for a key or its delay, 0 = none
CW_TOPEN        EQU CW_WCPKT+4       ; BYTE: timer.device opened (first WAIT_CHAR that has to wait)
CW_TON          EQU CW_TOPEN+1       ; BYTE: the delay is running
CW_TIO          EQU CW_TOPEN+2       ; timerequest (TR_SIZE), replied on CW_RPORT like the console read
CW_SIZE         EQU CW_TIO+TR_SIZE
; NewWindow
NW_DETAILPEN_C  EQU 8
NW_FLAGS_C      EQU 14
NW_TITLE_C      EQU 26
NW_MINWIDTH_C   EQU 38
NW_TYPE_C       EQU 46
CW_WINFLAGS     EQU $00021007        ; SIZING, DRAG, DEPTH, ACTIVATE, NOCAREREFRESH

                cnop    0,4
conwin_seg:
                dc.l    0                    ; link
cw_data:
                dc.l    (cw_end-cw_data)/4

; start(pkt) (global 1): D1 = BPTR of the startup packet (Arg1 = BSTR of the full name, Arg2 = dn_Startup). Does
; not return: the process ends with RemTask when the last stream is closed.
cw_start:
                move.l  d1,d7                ; d7 = BPTR of the startup packet
                move.l  ($4).w,a6
                move.l  #CW_SIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .st_fail
                move.l  d0,a5                ; a5 = state
                move.l  d7,CW_PKT(a5)
                lsl.l   #2,d7
                move.l  d7,a0
                move.l  DP_ARG2(a0),CW_MODE(a5)
                move.l  DP_ARG1(a0),d0       ; name -> window
                bsr     cw_parse
                beq     .st_bad
                lea     cw_intname(pc),a1
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                move.l  d0,CW_IBASE(a5)
                beq     .st_bad
                lea     CW_NW(a5),a0
                move.l  d0,a6
                jsr     LVO_OPENWINDOW_I(a6)
                move.l  ($4).w,a6
                move.l  d0,CW_WIN(a5)
                beq     .st_bad
                ; console read port (own signal)
                moveq   #-1,d0
                jsr     LVO_ALLOCSIGNAL(a6)
                move.l  d0,d6
                bmi     .st_nowin
                move.l  #MP_SIZE,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                move.l  d0,CW_RPORT(a5)
                beq     .st_nowin
                move.l  d0,a0
                move.b  #NT_MSGPORT,LN_TYPE(a0)
                move.b  d6,MP_SIGBIT(a0)
                move.l  EB_THISTASK(a6),MP_SIGTASK(a0)
                lea     MP_MSGLIST(a0),a1
                move.l  a1,8(a1)
                addq.l  #4,a1
                move.l  a1,-4(a1)
                clr.l   (a1)
                lea     CW_RIO(a5),a1        ; console.device on the window (the write request is a copy of it)
                move.l  CW_RPORT(a5),MN_REPLYPORT(a1)
                move.l  CW_WIN(a5),IOSTD_DATA(a1)
                lea     cw_conname(pc),a0
                moveq   #0,d0
                moveq   #0,d1
                jsr     LVO_OPENDEVICE(a6)
                tst.l   d0
                bne     .st_nowin
                lea     CW_RIO(a5),a0
                lea     CW_WIO(a5),a1
                moveq   #48/4-1,d0
.st_cpy:
                move.l  (a0)+,(a1)+
                dbra    d0,.st_cpy
                bsr     cw_startread
                moveq   #-1,d0               ; startup packet: success
                moveq   #0,d1
                move.l  CW_PKT(a5),d2
                bsr     cw_reply
                bra     cw_loop
.st_nowin:
                move.l  CW_WIN(a5),a0
                move.l  CW_IBASE(a5),a6
                jsr     LVO_CLOSEWINDOW_I(a6)
                move.l  ($4).w,a6
.st_bad:
                moveq   #0,d0                ; invalid name, window or device unavailable
                move.l  #ERROR_BAD_STREAM,d1
                move.l  CW_PKT(a5),d2
                bsr     cw_reply
                bra     cw_exit
.st_fail:
                lsl.l   #2,d7
                move.l  d7,a0
                clr.l   DP_RES1(a0)
                move.l  #103,DP_RES2(a0)
                move.l  DP_PORT(a0),a2
                move.l  EB_THISTASK(a6),a3
                lea     PR_MSGPORT(a3),a3
                move.l  a3,DP_PORT(a0)
                move.l  DP_LINK(a0),a1
                move.l  a2,a0
                jsr     LVO_PUTMSG(a6)
                sub.l   a1,a1
                jsr     LVO_REMTASK(a6)

; cw_loop: waits for packets (process port) and keys (console read port).
cw_loop:
                move.l  ($4).w,a6
                move.l  EB_THISTASK(a6),a3
                moveq   #0,d0
                move.b  PR_MSGPORT+MP_SIGBIT(a3),d1
                bset    d1,d0
                move.l  CW_RPORT(a5),a0
                move.b  MP_SIGBIT(a0),d1
                bset    d1,d0
                jsr     LVO_WAIT(a6)
.lp_key:
                move.l  CW_RPORT(a5),a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   .lp_pkt
                lea     CW_TIO(a5),a0
                cmp.l   a0,d0
                bne.s   .lp_rd
                clr.b   CW_TON(a5)           ; delay of a WAIT_CHAR over: no character came
                bsr     cw_wcdone
                bra.s   .lp_key
.lp_rd:
                clr.b   CW_RDON(a5)
                tst.b   CW_RIO+IO_ERROR(a5)
                bne.s   .lp_rearm
                tst.l   CW_RIO+IOSTD_ACTUAL(a5)
                beq.s   .lp_rearm
                move.b  CW_KEY(a5),d0
                bsr     cw_key
.lp_rearm:
                bsr     cw_startread
                bsr     cw_serve
                bra.s   .lp_key
.lp_pkt:
                move.l  ($4).w,a6
                move.l  EB_THISTASK(a6),a3
                lea     PR_MSGPORT(a3),a0
                jsr     LVO_GETMSG(a6)
                tst.l   d0
                beq.s   cw_loop
                move.l  d0,a0
                move.l  LN_NAME(a0),d2       ; packet (APTR)
                move.l  d2,a4
                lsr.l   #2,d2                ; d2 = BPTR
                bsr     cw_packet
                bra.s   .lp_pkt

; cw_packet(a4 = packet, d2 = its BPTR, a5): serves a packet (READ may stay pending).
cw_packet:
                move.l  DP_TYPE(a4),d0
                cmp.l   #ACTION_READ,d0
                beq     .pk_read
                cmp.l   #ACTION_WRITE,d0
                beq     .pk_write
                cmp.l   #ACTION_FINDINPUT,d0
                beq.s   .pk_open
                cmp.l   #ACTION_FINDOUTPUT,d0
                beq.s   .pk_open
                cmp.l   #ACTION_FINDUPDATE,d0
                beq.s   .pk_open
                cmp.l   #ACTION_END,d0
                beq     .pk_end
                cmp.l   #ACTION_WAIT_CHAR,d0
                beq.s   .pk_wait
                cmp.l   #ACTION_SCREEN_MODE,d0
                beq.s   .pk_mode
                cmp.l   #ACTION_DISK_INFO,d0
                beq.s   .pk_info
                moveq   #0,d0
                move.l  #ERROR_ACTION_UNKNOWN,d1
                bra     cw_reply
.pk_open:                                    ; interactive stream on this window
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .pk_onofh
                move.l  d0,a0
                move.l  #DOSTRUE,FH_INTERACTIVE(a0)
                move.l  a5,FH_ARG1(a0)
.pk_onofh:
                addq.l  #1,CW_OPENS(a5)
                moveq   #-1,d0
                moveq   #0,d1
                bra     cw_reply
.pk_wait:                                    ; Arg1 = delay in microseconds: answered as soon as a
                moveq   #-1,d0                       ; character is available, FALSE when the delay runs out
                tst.l   CW_DLV(a5)
                bne.s   .pk_wnow
                moveq   #0,d0
                move.l  DP_ARG1(a4),d1
                beq.s   .pk_wnow
                tst.l   CW_WCPKT(a5)
                bne.s   .pk_wnow             ; one WAIT_CHAR at a time (a second one: FALSE at once)
                bsr     cw_wcstart
                beq.s   .pk_wnow             ; no timer.device: FALSE at once
                move.l  d2,CW_WCPKT(a5)
                rts
.pk_wnow:
                moveq   #0,d1
                bra     cw_reply
.pk_mode:                                    ; Arg1: 0 = CON (line), otherwise RAW
                move.l  DP_ARG1(a4),CW_MODE(a5)
                beq.s   .pk_m0
                move.l  CW_LLEN(a5),CW_DLV(a5)   ; switch to RAW: everything typed becomes deliverable
.pk_m0:
                bsr     cw_serve
                moveq   #-1,d0
                moveq   #0,d1
                bra     cw_reply
.pk_info:
                move.l  DP_ARG1(a4),d0
                lsl.l   #2,d0
                beq.s   .pk_i0
                move.l  d0,a0
                move.l  #$434F4E00,ID_DISKTYPE(a0)   ; "CON\0"
                tst.l   CW_MODE(a5)
                beq.s   .pk_icon
                move.l  #$52415700,ID_DISKTYPE(a0)   ; "RAW\0"
.pk_icon:
                move.l  CW_WIN(a5),ID_VOLUMENODE(a0)
                lea     CW_RIO(a5),a1
                move.l  a1,ID_INUSE(a0)
.pk_i0:
                moveq   #-1,d0
                moveq   #0,d1
                bra     cw_reply
.pk_write:
                move.l  DP_ARG2(a4),d0
                move.l  DP_ARG3(a4),d1
                bsr     cw_out
                move.l  DP_ARG3(a4),d0
                moveq   #0,d1
                bra     cw_reply
.pk_read:
                move.l  CW_RQN(a5),d0
                cmp.l   #CW_RQMAX,d0
                bhs.s   .pk_rfull
                lsl.l   #2,d0
                lea     CW_RQ(a5),a0
                move.l  d2,0(a0,d0.l)
                addq.l  #1,CW_RQN(a5)
                bra     cw_serve
.pk_rfull:
                moveq   #-1,d0               ; too many simultaneous reads: error
                move.l  #ERROR_ACTION_UNKNOWN,d1
                bra     cw_reply
.pk_end:
                moveq   #-1,d0
                moveq   #0,d1
                bsr     cw_reply
                subq.l  #1,CW_OPENS(a5)
                bgt.s   .pk_eret
                bra     cw_close             ; last stream: window closed, end of process
.pk_eret:
                rts

; cw_serve(a5): returns as many pending reads as possible (deliverable data, or end of file in CON).
cw_serve:
                movem.l d2-d6/a2-a4,-(sp)
.sv_lp:
                tst.l   CW_RQN(a5)
                beq.s   .sv_ret
                move.l  CW_DLV(a5),d4
                bne.s   .sv_data
                tst.b   CW_EOF(a5)
                beq.s   .sv_ret
                clr.b   CW_EOF(a5)           ; Ctrl-\: this read returns 0 (end of file)
                moveq   #0,d5
                bra.s   .sv_give
.sv_data:
                move.l  CW_RQ(a5),d0
                lsl.l   #2,d0
                move.l  d0,a4
                move.l  DP_ARG3(a4),d5       ; d5 = bytes requested
                cmp.l   d4,d5
                bls.s   .sv_n
                move.l  d4,d5
.sv_n:
                move.l  DP_ARG2(a4),a1       ; copy then shift the buffer
                lea     CW_LINE(a5),a0
                move.l  d5,d0
                bra.s   .sv_cn
.sv_cp:
                move.b  (a0)+,(a1)+
.sv_cn:
                dbra    d0,.sv_cp
                lea     CW_LINE(a5),a1
                move.l  CW_LLEN(a5),d0
                sub.l   d5,d0
                move.l  d0,CW_LLEN(a5)
                bra.s   .sv_mn
.sv_mv:
                move.b  (a0)+,(a1)+
.sv_mn:
                dbra    d0,.sv_mv
                sub.l   d5,CW_DLV(a5)
.sv_give:
                move.l  CW_RQ(a5),d2         ; the oldest read is returned
                lea     CW_RQ(a5),a0
                moveq   #CW_RQMAX-2,d0
.sv_sh:
                move.l  4(a0),(a0)+
                dbra    d0,.sv_sh
                subq.l  #1,CW_RQN(a5)
                move.l  d5,d0
                moveq   #0,d1
                bsr     cw_reply
                bra.s   .sv_lp
.sv_ret:
                tst.l   CW_WCPKT(a5)         ; a WAIT_CHAR waits and a character is there: TRUE
                beq.s   .sv_end
                tst.l   CW_DLV(a5)
                beq.s   .sv_end
                bsr     cw_wcdone
.sv_end:
                movem.l (sp)+,d2-d6/a2-a4
                rts

; cw_wcstart(d1 = delay in microseconds, a5): starts the delay of a WAIT_CHAR (timer.device VBLANK unit, opened on
; first use, reply on CW_RPORT). Z = 1 if timer.device cannot be opened. Preserves d2-d7/a2-a5.
cw_wcstart:
                move.l  a6,-(sp)
                move.l  ($4).w,a6
                lea     CW_TIO(a5),a1
                tst.b   CW_TOPEN(a5)
                bne.s   .ws_open
                move.l  d1,-(sp)
                move.l  CW_RPORT(a5),MN_REPLYPORT(a1)
                lea     cw_timername(pc),a0
                moveq   #UNIT_VBLANK,d0
                moveq   #0,d1
                jsr     LVO_OPENDEVICE(a6)
                move.l  (sp)+,d1
                tst.l   d0
                bne.s   .ws_fail
                st      CW_TOPEN(a5)
                lea     CW_TIO(a5),a1
.ws_open:
                moveq   #0,d0                ; seconds and microseconds (68000: no 32-bit divide)
.ws_sec:
                cmp.l   #1000000,d1
                blo.s   .ws_set
                sub.l   #1000000,d1
                addq.l  #1,d0
                bra.s   .ws_sec
.ws_set:
                move.l  d0,TV_SECS(a1)
                move.l  d1,TV_MICRO(a1)
                move.w  #TR_ADDREQUEST,IO_COMMAND(a1)
                jsr     LVO_SENDIO(a6)
                st      CW_TON(a5)
                moveq   #1,d0                ; Z = 0
                bra.s   .ws_ret
.ws_fail:
                moveq   #0,d0
.ws_ret:
                move.l  (sp)+,a6
                rts

; cw_wcdone(a5): answers the waiting WAIT_CHAR (TRUE if a character is available, otherwise FALSE) and stops its
; delay if it still runs. Preserves d2-d7/a2-a5.
cw_wcdone:
                move.l  d2,-(sp)
                move.l  CW_WCPKT(a5),d2
                beq.s   .wd_ret
                clr.l   CW_WCPKT(a5)
                tst.b   CW_TON(a5)
                beq.s   .wd_reply
                clr.b   CW_TON(a5)
                move.l  a6,-(sp)
                move.l  ($4).w,a6
                lea     CW_TIO(a5),a1
                jsr     LVO_ABORTIO(a6)
                lea     CW_TIO(a5),a1
                jsr     LVO_WAITIO(a6)
                move.l  (sp)+,a6
.wd_reply:
                moveq   #0,d0
                tst.l   CW_DLV(a5)
                beq.s   .wd_r
                moveq   #-1,d0
.wd_r:
                moveq   #0,d1
                bsr     cw_reply
.wd_ret:
                move.l  (sp)+,d2
                rts

; cw_key(d0.b = character, a5): RAW -> deliverable as is; CON -> line editing with echo (backspace,
; Return ends the line, Ctrl-\ = end of file).
cw_key:
                movem.l d2/a2,-(sp)
                move.b  d0,d2
                tst.l   CW_MODE(a5)
                bne     .ky_raw
                tst.b   CW_CSI(a5)           ; CSI sequence (cursor, function, Help keys): skipped up to its final byte
                beq.s   .ky_ncsi
                cmp.b   #$40,d2
                blo     .ky_ret
                cmp.b   #$7E,d2
                bhi     .ky_ret
                clr.b   CW_CSI(a5)
                bra     .ky_ret
.ky_ncsi:
                cmp.b   #$9B,d2
                bne.s   .ky_nbs
                st      CW_CSI(a5)
                bra     .ky_ret
.ky_nbs:
                cmp.b   #8,d2                ; backspace: only on the line not yet deliverable
                bne.s   .ky_ncr
                move.l  CW_LLEN(a5),d0
                cmp.l   CW_DLV(a5),d0
                bls     .ky_ret
                subq.l  #1,CW_LLEN(a5)
                lea     cw_bs(pc),a0
                move.l  a0,d0
                moveq   #3,d1
                bsr     cw_out
                bra.s   .ky_ret
.ky_ncr:
                cmp.b   #28,d2               ; Ctrl-\: end of file
                bne.s   .ky_cr
                st      CW_EOF(a5)
                bra.s   .ky_ret
.ky_cr:
                cmp.b   #13,d2
                bne.s   .ky_put
                moveq   #10,d2               ; the line ends with '\n'
                bsr.s   .ky_store
                beq.s   .ky_ret
                move.l  CW_LLEN(a5),CW_DLV(a5)
                lea     cw_crlf(pc),a0
                move.l  a0,d0
                moveq   #2,d1
                bsr     cw_out
                bra.s   .ky_ret
.ky_put:
                cmp.b   #' ',d2              ; other control characters ignored in line mode
                blo.s   .ky_ret
                bsr.s   .ky_store
                beq.s   .ky_ret
                move.b  d2,CW_KEY(a5)        ; echo
                lea     CW_KEY(a5),a0
                move.l  a0,d0
                moveq   #1,d1
                bsr     cw_out
                bra.s   .ky_ret
.ky_raw:
                bsr.s   .ky_store
                beq.s   .ky_ret
                move.l  CW_LLEN(a5),CW_DLV(a5)
.ky_ret:
                movem.l (sp)+,d2/a2
                rts
.ky_store:                                   ; d2.b appended to the buffer; Z = 1 if it is full
                move.l  CW_LLEN(a5),d0
                cmp.l   #CW_LINEMAX-1,d0
                bhs.s   .ks_full
                lea     CW_LINE(a5),a0
                move.b  d2,0(a0,d0.l)
                addq.l  #1,CW_LLEN(a5)       ; Z = 0
                rts
.ks_full:
                moveq   #0,d0                ; Z = 1
                rts

; cw_out(d0 = data, d1 = length, a5): writes into the window (console.device, synchronous). Preserves d2-d7/a2-a5.
cw_out:
                move.l  a6,-(sp)
                lea     CW_WIO(a5),a1
                move.w  #CMD_WRITE_C,IO_COMMAND(a1)
                move.l  d0,IOSTD_DATA(a1)
                move.l  d1,IOSTD_LENGTH(a1)
                move.l  ($4).w,a6
                jsr     LVO_DOIO(a6)
                move.l  (sp)+,a6
                rts

; cw_startread(a5): restarts the one-character console read (reply on CW_RPORT). Preserves d2-d7/a2-a5.
cw_startread:
                move.l  a6,-(sp)
                lea     CW_RIO(a5),a1
                move.w  #CMD_READ_C,IO_COMMAND(a1)
                lea     CW_KEY(a5),a0
                move.l  a0,IOSTD_DATA(a1)
                move.l  #1,IOSTD_LENGTH(a1)
                st      CW_RDON(a5)
                move.l  ($4).w,a6
                jsr     LVO_SENDIO(a6)
                move.l  (sp)+,a6
                rts

; cw_reply(d0 = Res1, d1 = Res2, d2 = BPTR of the packet): reply (returnpkt) to the sender. Preserves d2-d7/a2-a5.
cw_reply:
                movem.l a2-a3/a6,-(sp)
                lsl.l   #2,d2
                move.l  d2,a0
                lsr.l   #2,d2
                move.l  d0,DP_RES1(a0)
                move.l  d1,DP_RES2(a0)
                move.l  DP_PORT(a0),a2
                move.l  ($4).w,a6
                move.l  EB_THISTASK(a6),a3
                lea     PR_MSGPORT(a3),a3
                move.l  a3,DP_PORT(a0)
                move.l  DP_LINK(a0),a1
                move.l  a2,a0
                jsr     LVO_PUTMSG(a6)
                movem.l (sp)+,a2-a3/a6
                rts

; cw_close(a5): last stream closed: pending reads returned (0), console read aborted, device and window
; closed, state freed, end of process.
cw_close:
.cl_rq:
                tst.l   CW_RQN(a5)
                beq.s   .cl_io
                st      CW_EOF(a5)
                bsr     cw_serve
                bra.s   .cl_rq
.cl_io:
                bsr     cw_wcdone            ; a waiting WAIT_CHAR: FALSE, delay stopped
                move.l  ($4).w,a6
                tst.b   CW_TOPEN(a5)
                beq.s   .cl_rd
                lea     CW_TIO(a5),a1
                jsr     LVO_CLOSEDEVICE(a6)
.cl_rd:
                tst.b   CW_RDON(a5)
                beq.s   .cl_dev
                lea     CW_RIO(a5),a1
                jsr     LVO_ABORTIO(a6)
                lea     CW_RIO(a5),a1
                jsr     LVO_WAITIO(a6)
.cl_dev:
                lea     CW_RIO(a5),a1
                jsr     LVO_CLOSEDEVICE(a6)
                move.l  CW_WIN(a5),a0
                move.l  CW_IBASE(a5),a6
                jsr     LVO_CLOSEWINDOW_I(a6)
                move.l  ($4).w,a6
                move.l  CW_IBASE(a5),a1
                jsr     LVO_CLOSELIBRARY(a6)
                move.l  CW_RPORT(a5),a0
                moveq   #0,d0
                move.b  MP_SIGBIT(a0),d0
                jsr     LVO_FREESIGNAL(a6)
                move.l  CW_RPORT(a5),a1
                moveq   #MP_SIZE,d0
                jsr     LVO_FREEMEM(a6)
cw_exit:
                move.l  ($4).w,a6
                move.l  a5,a1
                move.l  #CW_SIZE,d0
                jsr     LVO_FREEMEM(a6)
                sub.l   a1,a1
                jsr     LVO_REMTASK(a6)      ; does not return
.ex_hang:
                bra.s   .ex_hang

; cw_parse(d0 = BPTR of the BSTR "CON:x/y/w/h/title", a5) -> NewWindow and title in the state; Z = 1 if the name is
; invalid. The numbers start at the 5th character (4-character prefix: CON:/RAW:).
cw_parse:
                movem.l d2-d4/a2-a3,-(sp)
                lsl.l   #2,d0
                beq     .pa_bad
                move.l  d0,a2
                moveq   #0,d3
                move.b  (a2)+,d3             ; length
                subq.w  #4,d3
                ble     .pa_bad
                addq.l  #4,a2
                lea     CW_NW(a5),a3         ; LeftEdge, TopEdge, Width, Height
                moveq   #3,d4
.pa_num:
                moveq   #0,d1
                moveq   #0,d2                ; digits read
.pa_dig:
                tst.w   d3
                beq.s   .pa_bad
                subq.w  #1,d3
                moveq   #0,d0
                move.b  (a2)+,d0
                cmp.b   #'/',d0
                beq.s   .pa_sep
                sub.b   #'0',d0
                cmp.b   #9,d0
                bhi.s   .pa_bad
                mulu    #10,d1
                add.w   d0,d1
                addq.w  #1,d2
                bra.s   .pa_dig
.pa_sep:
                tst.w   d2
                beq.s   .pa_bad
                move.w  d1,(a3)+
                dbra    d4,.pa_num
                lea     CW_TITLE(a5),a0      ; title = the rest
                moveq   #CW_TITLEMAX-2,d0
.pa_tc:
                tst.w   d3
                beq.s   .pa_te
                subq.w  #1,d3
                move.b  (a2)+,(a0)+
                dbra    d0,.pa_tc
.pa_te:
                clr.b   (a0)
                lea     CW_NW(a5),a0
                move.w  #$FFFF,NW_DETAILPEN_C(a0)    ; screen pens
                move.l  #CW_WINFLAGS,NW_FLAGS_C(a0)
                lea     CW_TITLE(a5),a1
                move.l  a1,NW_TITLE_C(a0)
                move.l  #$00500028,NW_MINWIDTH_C(a0)     ; MinWidth 80, MinHeight 40
                move.l  #$FFFFFFFF,NW_MINWIDTH_C+4(a0)   ; no maximum
                move.w  #1,NW_TYPE_C(a0)                 ; WBENCHSCREEN
                moveq   #1,d0                ; Z = 0
                bra.s   .pa_ret
.pa_bad:
                moveq   #0,d0                ; Z = 1
.pa_ret:
                movem.l (sp)+,d2-d4/a2-a3
                rts

cw_intname:
                dc.b    "intuition.library",0
cw_conname:
                dc.b    "console.device",0
cw_timername:
                dc.b    "timer.device",0
cw_bs:
                dc.b    8,32,8
cw_crlf:
                dc.b    13,10
                cnop    0,4
                dc.l    0                    ; end of the globin table
                dc.l    1,cw_start-cw_data   ; global 1 = start
                dc.l    1                    ; highest global defined
cw_end:
