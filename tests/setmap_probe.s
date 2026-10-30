; tests/setmap_probe.s - black-box probe of keymap.resource / console.device keymaps around SetMap 1.3
; (TEST ASSET, NOT ROM code; ANALYSIS track, docs/analysis/setmap-13.md).
; AUTHORED code: uses only the public ABI (exec/dos .fd, devices/console.h, devices/conunit.h,
; devices/keymap.h, devices/inputevent.h, dos/dos.h InfoData and packets from the 1.3 NDK).
;
; AmigaDOS executable (vasm -Fhunkexe -kick1hunks), run from the startup-sequence of a probe disk built by
; tests/setmap_probe.sh: "sp <tag>". The log is buffered, then sent to the serial port (direct SERDAT) at the
; end, one line per Delay(1) (a dense burst triggers the FS-UAE lost-CIA-interrupt artefact, "out of event2"):
;   P <tag> rc=<cli_ReturnCode of the previous command>
;   R <res> type head tail tailpred ltype     keymap.resource and its kr_List header
;   N <node> succ pred type pri seglen "name" <8 KeyMap pointers>   each node of kr_List (max 8)
;   A err actual <8 pointers>                 CD_ASKDEFAULTKEYMAP on an OpenDevice(unit -1) request
;   W sigbit <task State SigAlloc SigWait SigRecvd> x2  our task, console handler task (before the packet)
;   I waits res1 res2 <9 longs of InfoData>        ACTION_DISK_INFO sent to pr_ConsoleTask
;   T no reply                                no reply within 10 s (then W again)
;   Q dev unit win                            fields of the IOStdReq found in id_InUse (if non zero)
;   U err actual <8 pointers>                 CD_ASKKEYMAP on that unit
;   K D|U code qual x y = n bytes             RawKeyConvert, keymap NULL (D) or the unit's (U)
;   @S <c>                                    screen capture by the harness (c = first char of tag)

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

_Forbid      EQU -132
_Permit      EQU -138
_FindTask    EQU -294
_AllocSignal EQU -330
_PutMsg      EQU -366
_GetMsg      EQU -372
_WaitPort    EQU -384
_OpenDevice  EQU -444
_CloseDevice EQU -450
_DoIO        EQU -456
_OpenResource EQU -498
_RawKeyConvert EQU -48
_OpenLibrary EQU -552
_Delay       EQU -198

pr_MsgPort   EQU $5C
pr_CLI       EQU $AC
pr_ConsoleTask EQU $A4
cli_ReturnCode EQU 12

        section code,code
start:
        lea     vars,a5
        lea     obuf(a5),a1
        move.l  a1,optr(a5)
        move.l  4.w,a6
        lea     tag(a5),a1
        moveq   #14,d1
.tg:    subq.l  #1,d0                ; command line: tag = first word
        bmi.s   .tge
        move.b  (a0)+,d2
        cmp.b   #' ',d2
        bls.s   .tge
        move.b  d2,(a1)+
        dbf     d1,.tg
.tge:   clr.b   (a1)

        lea     s_dos(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,dosb(a5)
        lea     s_p(pc),a0
        bsr     puts
        lea     tag(a5),a0
        bsr     puts
        lea     s_rc(pc),a0
        bsr     puts
        suba.l  a1,a1
        jsr     _FindTask(a6)
        move.l  d0,a4                ; a4 = our process
        move.l  pr_CLI(a4),d0
        lsl.l   #2,d0
        beq.s   .norc
        move.l  d0,a0
        move.l  cli_ReturnCode(a0),d0
.norc:  bsr     hex8
        bsr     nl

; ---- keymap.resource and kr_List ----
        lea     s_kres(pc),a1
        jsr     _OpenResource(a6)
        move.l  d0,a3
        moveq   #'R',d0
        bsr     putc
        move.l  a3,d0
        bsr     hex8s
        move.l  a3,d0
        beq     .nores
        moveq   #0,d0
        move.b  8(a3),d0
        bsr     hex8s
        move.l  $0E(a3),d0
        bsr     hex8s
        move.l  $12(a3),d0
        bsr     hex8s
        move.l  $16(a3),d0
        bsr     hex8s
        moveq   #0,d0
        move.b  $1A(a3),d0
        bsr     hex8
        bsr     nl
        jsr     _Forbid(a6)
        move.l  $0E(a3),a2
        moveq   #7,d7
.nd:    tst.l   (a2)                 ; ln_Succ = 0 => this is the tail
        beq.s   .nde
        moveq   #'N',d0
        bsr     putc
        move.l  a2,d0
        bsr     hex8s
        move.l  (a2),d0
        bsr     hex8s
        move.l  4(a2),d0
        bsr     hex8s
        moveq   #0,d0
        move.b  8(a2),d0
        bsr     hex8s
        move.b  9(a2),d0
        bsr     hex8s
        move.l  -8(a2),d0            ; long before the segment link (LoadSeg allocation size)
        bsr     hex8s
        moveq   #'"',d0
        bsr     putc
        move.l  10(a2),d0
        beq.s   .nn
        move.l  d0,a0
        moveq   #23,d1
.nc:    move.b  (a0)+,d0
        beq.s   .nn
        bsr     putc
        dbf     d1,.nc
.nn:    moveq   #'"',d0
        bsr     putc
        lea     14(a2),a0
        bsr     km8
        bsr     nl
        move.l  (a2),a2
        dbf     d7,.nd
.nde:   jsr     _Permit(a6)
.nores:

; ---- console.device: unit -1, CD_ASKDEFAULTKEYMAP ----
        lea     port(a5),a2
        moveq   #-1,d0
        jsr     _AllocSignal(a6)
        move.b  #4,8(a2)             ; NT_MSGPORT
        clr.b   14(a2)               ; PA_SIGNAL
        move.b  d0,15(a2)
        move.l  a4,16(a2)
        lea     20(a2),a0            ; NewList(mp_MsgList)
        move.l  a0,8(a0)
        addq.l  #4,a0
        clr.l   (a0)
        move.l  a0,-(a0)
        lea     ioreq(a5),a1
        move.l  a2,14(a1)            ; mn_ReplyPort
        lea     s_con(pc),a0
        moveq   #-1,d0
        moveq   #0,d1
        jsr     _OpenDevice(a6)
        tst.l   d0
        bne     .noconsole
        moveq   #11,d0               ; CD_ASKDEFAULTKEYMAP
        lea     kmbuf(a5),a0
        moveq   #'A',d1
        bsr     askkm

; ---- ACTION_DISK_INFO to pr_ConsoleTask ----
        clr.b   haveu(a5)
        move.l  pr_ConsoleTask(a4),d0
        beq     .nocons
        move.l  d0,a3
        lea     pkt(a5),a1
        lea     20(a1),a0            ; sp_Pkt
        move.l  a0,10(a1)            ; ln_Name = packet
        move.l  a1,(a0)              ; dp_Link
        move.l  a2,4(a0)             ; dp_Port
        move.l  #25,8(a0)            ; ACTION_DISK_INFO
        lea     info(a5),a0
        moveq   #8,d1
.ci:    clr.l   (a0)+
        dbf     d1,.ci
        lea     info(a5),a0
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,20+20(a1)         ; dp_Arg1 = BPTR InfoData
        bsr     wstate
        move.l  a3,a0
        jsr     _PutMsg(a6)
        cmp.b   #'W',tag(a5)         ; tag "W": plain WaitPort (as SetMap does)
        bne.s   .poll
        move.l  a2,a0
        jsr     _WaitPort(a6)
        move.l  a2,a0
        jsr     _GetMsg(a6)
        moveq   #-1,d6
        bra.s   .wgot
.poll:  moveq   #50,d6               ; polled wait, 50 x Delay(10) = 10 s at most
.wp:    move.l  a2,a0
        jsr     _GetMsg(a6)
        tst.l   d0
        bne.s   .wgot
        move.l  a6,-(sp)
        move.l  dosb(a5),a6
        moveq   #10,d1
        jsr     _Delay(a6)
        move.l  (sp)+,a6
        dbf     d6,.wp
        lea     s_tmo(pc),a0         ; no reply: state of both tasks, packet skipped
        bsr     puts
        bsr     wstate
        bra     .nocons
.wgot:
        moveq   #'I',d0
        bsr     putc
        moveq   #50,d0               ; number of Delay(10) waited before the reply (-1 = WaitPort)
        sub.l   d6,d0
        tst.l   d6
        bpl.s   .wn
        moveq   #-1,d0
.wn:    bsr     hex8s
        lea     pkt+20(a5),a0
        move.l  12(a0),d0            ; dp_Res1
        bsr     hex8s
        move.l  16(a0),d0            ; dp_Res2
        bsr     hex8s
        lea     info(a5),a3
        moveq   #8,d6
.il:    move.l  (a3)+,d0
        bsr     hex8s
        dbf     d6,.il
        bsr     nl
        move.l  info+$20(a5),d0      ; id_InUse
        beq.s   .nocons
        move.l  d0,a3
        moveq   #'Q',d0
        bsr     putc
        move.l  $14(a3),d0
        bsr     hex8s
        move.l  $18(a3),d0
        bsr     hex8s
        move.l  $18(a3),d0
        beq.s   .qn
        move.l  d0,a0
        move.l  $22(a0),d0           ; cu_Window
.qn:    bsr     hex8
        bsr     nl
        move.l  $18(a3),d0
        beq.s   .nocons
        lea     ioreq(a5),a1
        move.l  $14(a3),d1
        cmp.l   $14(a1),d1
        bne.s   .nocons              ; not our console.device
        move.l  d0,$18(a1)
        moveq   #9,d0                ; CD_ASKKEYMAP
        lea     ukm(a5),a0
        moveq   #'U',d1
        bsr     askkm
        lea     ioreq(a5),a1
        move.l  #-1,$18(a1)
        st      haveu(a5)
.nocons:

; ---- RawKeyConvert vectors ----
        lea     vectors(pc),a3
.kv:    move.w  (a3),d0
        cmp.w   #-1,d0
        beq.s   .kve
        suba.l  a2,a2
        moveq   #'D',d4
        bsr     rkc
        tst.b   haveu(a5)
        beq.s   .kn
        lea     ukm(a5),a2
        moveq   #'U',d4
        bsr     rkc
.kn:    addq.l  #8,a3
        bra.s   .kv
.kve:
        lea     ioreq(a5),a1
        move.l  4.w,a6
        jsr     _CloseDevice(a6)
.noconsole:
        move.l  dosb(a5),a6          ; log -> serial, one line then Delay(1): a dense burst of
        lea     obuf(a5),a2          ; SERDAT writes triggers the FS-UAE lost-CIA-interrupt artefact
.ol:    cmp.l   optr(a5),a2
        bhs.s   .nout
        move.b  (a2)+,d0
        bsr     serc
        cmp.b   #10,d0
        bne.s   .ol
        moveq   #1,d1
        jsr     _Delay(a6)
        bra.s   .ol
.nout:  lea     s_cap(pc),a0
.cp:    move.b  (a0)+,d0
        beq.s   .cpe
        bsr     serc
        bra.s   .cp
.cpe:   move.b  tag(a5),d0
        bsr     serc
        moveq   #10,d0
        bsr     serc
        moveq   #0,d0
        rts

; wstate: logs "W sigbit our(SigAlloc SigWait SigRecvd) handler(State SigWait SigRecvd)" (a2 = our port,
; a3 = handler MsgPort)
wstate: movem.l d0/a0,-(sp)
        moveq   #'W',d0
        bsr     putc
        moveq   #0,d0
        move.b  15(a2),d0
        bsr     hex8s
        move.l  16(a2),a0
        bsr.s   tstate
        move.l  16(a3),a0
        bsr.s   tstate
        bsr     nl
        movem.l (sp)+,d0/a0
        rts
tstate: move.l  a0,d0
        bsr     hex8s
        moveq   #0,d0
        move.b  15(a0),d0            ; tc_State
        bsr     hex8s
        move.l  18(a0),d0            ; tc_SigAlloc
        bsr     hex8s
        move.l  22(a0),d0            ; tc_SigWait
        bsr     hex8s
        move.l  26(a0),d0            ; tc_SigRecvd
        bra     hex8s

; askkm(command d0, buffer a0, letter d1): DoIO on ioreq, io_Length 32; logs letter err actual 8 ptrs
askkm:  movem.l d2/a2,-(sp)
        move.l  a0,a2
        move.l  d1,d2
        lea     ioreq(a5),a1
        move.w  d0,28(a1)
        move.l  a0,40(a1)
        move.l  #32,36(a1)
        clr.l   32(a1)
        jsr     _DoIO(a6)
        move.l  d2,d0
        bsr     putc
        lea     ioreq(a5),a1
        moveq   #0,d0
        move.b  31(a1),d0
        bsr     hex8s
        move.l  32(a1),d0
        bsr     hex8s
        move.l  a2,a0
        bsr     km8
        bsr     nl
        movem.l (sp)+,d2/a2
        rts

; rkc(vector a3, keymap a2, letter d4): RawKeyConvert of one RAWKEY event; logs the result
rkc:    movem.l d2-d3/a2-a3/a6,-(sp)
        lea     event(a5),a0
        clr.l   (a0)                 ; ie_NextEvent
        move.b  #1,4(a0)             ; IECLASS_RAWKEY
        clr.b   5(a0)
        move.w  (a3),6(a0)
        move.w  2(a3),8(a0)
        move.w  4(a3),10(a0)         ; ie_Prev1DownCode/Qual
        move.w  6(a3),12(a0)         ; ie_Prev2DownCode/Qual
        clr.l   14(a0)
        clr.l   18(a0)
        lea     outb(a5),a1
        moveq   #16,d1
        lea     ioreq(a5),a6
        move.l  20(a6),a6            ; io_Device = console base
        jsr     _RawKeyConvert(a6)
        move.l  d0,d3
        moveq   #'K',d0
        bsr     putc
        moveq   #' ',d0
        bsr     putc
        move.l  d4,d0
        bsr     putc
        moveq   #' ',d0
        bsr     putc
        move.w  (a3),d0
        bsr     hex2
        moveq   #' ',d0
        bsr     putc
        move.w  2(a3),d0
        bsr     hex4
        moveq   #' ',d0
        bsr     putc
        move.w  4(a3),d0
        bsr     hex4
        moveq   #' ',d0
        bsr     putc
        move.w  6(a3),d0
        bsr     hex4
        lea     s_eq(pc),a0
        bsr     puts
        move.l  d3,d0
        bsr     hex8
        tst.l   d3
        ble.s   .rd
        lea     outb(a5),a2
        subq.w  #1,d3
.rl:    moveq   #' ',d0
        bsr     putc
        move.b  (a2)+,d0
        bsr     hex2
        dbf     d3,.rl
.rd:    bsr     nl
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

km8:    movem.l d2/a2,-(sp)          ; 8 longs at a0
        move.l  a0,a2
        moveq   #7,d2
.k:     moveq   #' ',d0
        bsr     putc
        move.l  (a2)+,d0
        bsr     hex8
        dbf     d2,.k
        movem.l (sp)+,d2/a2
        rts

hex8s:  bsr.s   hex8
        moveq   #' ',d0
        bra.s   putc
hex8:   swap    d0
        bsr.s   hex4
        swap    d0
hex4:   ror.w   #8,d0
        bsr.s   hex2
        rol.w   #8,d0
hex2:   move.l  d0,-(sp)
        lsr.b   #4,d0
        bsr.s   nib
        move.l  (sp),d0
        bsr.s   nib
        move.l  (sp)+,d0
        rts
nib:    and.w   #15,d0
        move.b  hexd(pc,d0.w),d0
        bra.s   putc
hexd:   dc.b    "0123456789ABCDEF"
nl:     moveq   #10,d0
putc:   movem.l a0-a1,-(sp)          ; appends to the output buffer (sent at the end)
        move.l  optr(a5),a0
        lea     obuf+OBSZ(a5),a1
        cmp.l   a1,a0
        bhs.s   .pf
        move.b  d0,(a0)+
        move.l  a0,optr(a5)
.pf:    movem.l (sp)+,a0-a1
        rts
serc:   btst    #13-8,SERDATR        ; one byte to the serial port (only the short "@S x" marker)
        beq.s   serc
        move.w  d0,-(sp)
        and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        move.w  (sp)+,d0
        rts
puts:   move.l  d0,-(sp)
.p:     move.b  (a0)+,d0
        beq.s   .pe
        bsr.s   putc
        bra.s   .p
.pe:    move.l  (sp)+,d0
        rts

; RawKeyConvert vectors: code, qualifier, ie_X (Prev1 code<<8|qual), ie_Y (Prev2)
        cnop    0,2
vectors:
        dc.w    $15,0,0,0            ; y (US position) / z on German
        dc.w    $31,0,0,0            ; z (US position) / y on German
        dc.w    $15,1,0,0
        dc.w    $31,1,0,0
        dc.w    $29,0,0,0            ; ; / ö
        dc.w    $29,1,0,0
        dc.w    $2A,0,0,0            ; ' / ä
        dc.w    $2A,1,0,0
        dc.w    $1A,0,0,0            ; [ / ü
        dc.w    $1A,1,0,0
        dc.w    $1A,$10,0,0          ; Alt
        dc.w    $0B,0,0,0            ; - / ß
        dc.w    $0B,1,0,0
        dc.w    $0C,0,0,0            ; = / dead acute
        dc.w    $0C,1,0,0            ; dead grave
        dc.w    $0C,$10,0,0
        dc.w    $2B,0,0,0            ; # (key next to Return)
        dc.w    $30,0,0,0            ; < (left of Z)
        dc.w    $30,1,0,0
        dc.w    $00,0,0,0
        dc.w    $5A,0,0,0            ; keypad (
        dc.w    $5D,0,0,0            ; keypad *
        dc.w    $12,0,$0C00,0        ; e after dead acute key
        dc.w    $12,0,$0C01,0        ; e after Shift + dead key (grave)
        dc.w    $12,1,$0C00,0        ; E after dead acute
        dc.w    $20,0,$0C00,0        ; a after dead acute
        dc.w    $40,0,$0C00,0        ; space after dead acute
        dc.w    $10,0,$0C00,0        ; q after dead acute (not modifiable)
        dc.w    $12,0,$2310,0        ; e after Alt-f
        dc.w    $12,0,$2410,0        ; e after Alt-g
        dc.w    $12,0,$2510,0        ; e after Alt-h
        dc.w    $16,0,$2710,0        ; u after Alt-k
        dc.w    $18,0,$2610,0        ; o after Alt-j
        dc.w    $12,0,$0C00,$0C00    ; e after two dead acute
        dc.w    $12,0,$0C00,$0C01    ; e after grave then acute
        dc.w    $12,0,$0C00,$2510    ; e after circumflex then acute
        dc.w    $12,0,$2510,$0C00    ; e after acute then circumflex
        dc.w    $20,0,$2510,$0C00    ; a after acute then circumflex
        dc.w    $12,0,$0C00,$2310    ; e after Alt-f then dead acute key
        dc.w    -1

s_p:    dc.b    "P ",0
s_rc:   dc.b    " rc=",0
s_kres: dc.b    "keymap.resource",0
s_con:  dc.b    "console.device",0
s_eq:   dc.b    " = ",0
s_dos:  dc.b    "dos.library",0
s_tmo:  dc.b    "T no reply",10,0
s_cap:  dc.b    "@S ",0

        section bss,bss
vars:
port    EQU     0                    ; MsgPort (34)
ioreq   EQU     36                   ; IOStdReq (48)
pkt     EQU     84                   ; StandardPacket (68)
info    EQU     152                  ; InfoData (36), long aligned
kmbuf   EQU     188                  ; KeyMap (32)
ukm     EQU     220                  ; KeyMap (32)
event   EQU     252                  ; InputEvent (22)
outb    EQU     276                  ; 16 bytes
tag     EQU     292                  ; 16 bytes
haveu   EQU     308
dosb    EQU     312
optr    EQU     316
obuf    EQU     320
OBSZ    EQU     12000
        ds.b    320+OBSZ
