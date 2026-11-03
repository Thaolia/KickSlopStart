; kicktag_test.s - warm reset survival through KickMemPtr/KickTagPtr/CoolCapture (implementation track, our own test
; program; behaviour from coldstart-hardware-v34 §5 and the exec AutoDocs of SumKickData).
; Arms, under Forbid:
;   - KickMemPtr = one MemList whose single entry covers this program's code hunk;
;   - KickTagPtr = a table holding tag1 then a link (bit 31) to a second table holding tag2;
;       tag1 "kicktest" v1, RTF_COLDSTART: its init writes "KICKTAG INIT" on the serial port;
;       tag2 "keymap.resource" v1, RTF_COLDSTART: older than the ROM's, so it must NOT replace it; its init would
;       write "KICKTAG WRONG";
;   - KickCheckSum = SumKickData(), CoolCapture = a routine writing "COOLCAPTURE", ExecBase ChkSum recomputed.
; Writes "KICK ARMED" through dos and then sleeps; the harness resets the machine. After a warm reset the serial
; port must show "COOLCAPTURE" then "KICKTAG INIT", and never "KICKTAG WRONG". Each routine also counts its calls
; in the three longs just before table1 (KickTagPtr - 12: cool, tag1, tag2), for a debugger to read when the
; serial port is not drained after an emulated reset (the serial wait gives up after a while).
; Build: vasmm68k_mot -Fhunkexe -kick1hunks -o kicktag_test tests/kicktag_test.s

        section code,code

start:
        move.l  ($4).w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)             ; OpenLibrary
        move.l  d0,a5                ; a5 = DOSBase
        jsr     -132(a6)             ; Forbid
        move.l  #memlist,$222(a6)    ; KickMemPtr
        move.l  #table1,$226(a6)     ; KickTagPtr
        jsr     -612(a6)             ; SumKickData
        move.l  d0,$22A(a6)          ; KickCheckSum
        move.l  #cool,$2E(a6)        ; CoolCapture
        lea     $22(a6),a0           ; ChkSum = complement of the word sum of +$22..+$4E
        moveq   #0,d1
        moveq   #($4E-$22)/2,d0
.cks:
        add.w   (a0)+,d1
        dbra    d0,.cks
        not.w   d1
        move.w  d1,$52(a6)
        jsr     -138(a6)             ; Permit
        move.l  a5,a6
        jsr     -60(a6)              ; Output
        move.l  d0,d1
        lea     m_armed(pc),a0
        move.l  a0,d2
        moveq   #m_armed_len,d3
        jsr     -48(a6)              ; Write
.sleep:
        move.l  #50*60,d1
        jsr     -198(a6)             ; Delay: the hunk must stay allocated until the reset
        bra.s   .sleep

; serout(a0 = text ended by 0): polled write to SERDAT (no system call: CoolCapture and the tag inits run during
; the boot).
serout:
        move.l  d1,-(sp)
.so_ch:
        move.b  (a0)+,d0
        beq.s   .so_end
        move.l  #100000,d1
.so_wait:
        btst    #13-8,$DFF018        ; SERDATR TBE
        bne.s   .so_put
        subq.l  #1,d1
        bne.s   .so_wait
        bra.s   .so_end
.so_put:
        and.w   #$FF,d0
        or.w    #$100,d0             ; stop bit
        move.w  d0,$DFF030           ; SERDAT
        bra.s   .so_ch
.so_end:
        move.l  (sp)+,d1
        rts

cool:
        movem.l d0/a0,-(sp)
        lea     hits(pc),a0
        addq.l  #1,(a0)
        lea     m_cool(pc),a0
        bsr.s   serout
        movem.l (sp)+,d0/a0
        rts

init1:
        lea     hits+4(pc),a0
        addq.l  #1,(a0)
        lea     m_init(pc),a0
        bsr.s   serout
        moveq   #0,d0
        rts

init2:
        lea     hits+8(pc),a0
        addq.l  #1,(a0)
        lea     m_wrong(pc),a0
        bsr.s   serout
        moveq   #0,d0
        rts

        even
tag1:
        dc.w    $4AFC
        dc.l    tag1,codeend
        dc.b    $01,1,0,0            ; RTF_COLDSTART, version 1, type 0, pri 0
        dc.l    name1,name1,init1
tag2:
        dc.w    $4AFC
        dc.l    tag2,codeend
        dc.b    $01,1,8,0            ; RTF_COLDSTART, version 1, NT_RESOURCE, pri 0
        dc.l    name2,name2,init2
hits:
        dc.l    0,0,0                ; calls of cool, init1, init2
table1:
        dc.l    tag1
        dc.l    table2+$80000000     ; link to the next table
        dc.l    0                    ; never reached
table2:
        dc.l    tag2
        dc.l    0
memlist:
        dc.l    0,0                  ; LN_SUCC (end of the chain), LN_PRED
        dc.b    0,0                  ; LN_TYPE, LN_PRI
        dc.l    0                    ; LN_NAME
        dc.w    1                    ; ml_NumEntries
        dc.l    start,codeend-start  ; the whole hunk
dosname: dc.b    "dos.library",0
name1:   dc.b    "kicktest",0
name2:   dc.b    "keymap.resource",0
m_cool:  dc.b    "COOLCAPTURE",13,10,0
m_init:  dc.b    "KICKTAG INIT",13,10,0
m_wrong: dc.b    "KICKTAG WRONG",13,10,0
m_armed: dc.b    "KICK ARMED",10
m_armed_len EQU *-m_armed
        even
codeend:
