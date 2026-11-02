; tests/dosexit_test.s - dos.library Exit (-144), GetPacket (-162), QueuePacket (-168) (implementation-side test,
; docs/analysis/dos-exit-packets-v34.md). Run by tests/dosexit_probe.sh, whose startup-sequence (FailAt 10) calls
; this program once per mode (first letter of the argument). Results on the serial port. Expected:
;   m  GQ 00000000 FFFFFFFF FFFFFFFF 00000000 1   GetPacket(buf/4, 3) -> 0, buffer intact; QueuePacket(BSTR) -> 0;
;                                                 pr_MsgPort still empty
;      CPX 1 0 00000000                           CreateProc'd child ran, Exit(5) ended it before the next line,
;                                                 FindTask(name) = 0 afterwards
;   a  (Exit(7) from 4 nested 512-byte frames, pr_Result2 = 205 just before)
;   c  CLI 00000007 000000CD <avail>              cli_ReturnCode = 7, cli_Result2 = 205
;   z  (Exit(0) from 4 nested 512-byte frames, pr_Result2 = 205)
;   c  CLI 00000000 00000000 <same avail>         code 0 -> cli_Result2 = 0; no memory lost
;   f  DOSEXIT END, then Exit(20): the shell prints "dosexit_test failed returncode 20" and abandons the script
;   n  NEVER (must not appear)
;   e  (Exit(-1) from 4 nested 512-byte frames, pr_Result2 = 205): not in the default run. With MODES="e c f n"
;      the shell treats it as a command that could not be loaded: "Unknown command df0:dosexit_test", script
;      abandoned whatever FailAt (no CLI/DOSEXIT line follows); interactively cli_ReturnCode = cli_Result2 = 0
;   u / v / w  same as e with pr_Result2 = 0 / 103 / 218 at Exit time (which message the shell prints)

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
PR_MSGPORT  EQU $5C
PR_RESULT2  EQU $94
PR_CLI      EQU $AC
MP_MSGLIST  EQU $14

start:  move.l  a0,a2
        move.l  d0,d2
        move.l  4.w,a6
        lea     dosname(pc),a1
        moveq   #0,d0
        jsr     -552(a6)                ; OpenLibrary
        move.l  d0,dosbase
        beq     done
        moveq   #'m',d3
.skip:  subq.l  #1,d2
        bmi.s   .disp
        move.b  (a2)+,d0
        cmp.b   #' ',d0
        beq.s   .skip
        move.b  d0,d3
.disp:  cmp.b   #'a',d3
        beq     mode_a
        cmp.b   #'z',d3
        beq     mode_z
        cmp.b   #'e',d3
        beq     mode_e
        cmp.b   #'u',d3
        beq     mode_u
        cmp.b   #'v',d3
        beq     mode_v
        cmp.b   #'w',d3
        beq     mode_w
        cmp.b   #'c',d3
        beq     mode_c
        cmp.b   #'f',d3
        beq     mode_f
        cmp.b   #'n',d3
        beq     mode_n

        lea     m_gq(pc),a0             ; --- mode m: GetPacket / QueuePacket
        bsr     puts
        lea     buf,a0
        moveq   #-1,d0
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  dosbase,a6
        move.l  #buf,d1
        lsr.l   #2,d1
        moveq   #3,d2
        jsr     -162(a6)                ; GetPacket
        bsr     hex8
        move.l  buf,d0
        bsr     hex8
        move.l  buf+12,d0
        bsr     hex8
        move.l  #bname,d1
        lsr.l   #2,d1
        jsr     -168(a6)                ; QueuePacket
        bsr     hex8
        move.l  4.w,a0
        move.l  276(a0),a0              ; ThisTask
        lea     PR_MSGPORT+MP_MSGLIST(a0),a1
        moveq   #0,d0
        lea     4(a1),a0
        cmp.l   (a1),a0                 ; lh_Head = &lh_Tail: empty
        bne.s   .gq1
        moveq   #1,d0
.gq1:   bsr     dig
        bsr     nl

        clr.w   flags                   ; --- CreateProc'd child calls Exit(5)
        move.l  dosbase,a6
        move.l  #cname,d1
        moveq   #0,d2
        move.l  #seg,d3
        lsr.l   #2,d3
        move.l  #4000,d4
        jsr     -138(a6)                ; CreateProc
        tst.l   d0
        beq     done
        moveq   #50,d1
        jsr     -198(a6)                ; Delay(1 s)
        lea     m_cpx(pc),a0
        bsr     puts
        moveq   #0,d0
        tst.b   flags
        beq.s   .c1
        moveq   #1,d0
.c1:    bsr     dig
        moveq   #0,d0
        tst.b   flags+1
        beq.s   .c2
        moveq   #1,d0
.c2:    bsr     dig
        move.l  4.w,a6
        lea     cname(pc),a1
        jsr     -294(a6)                ; FindTask(name)
        bsr     hex8
        bsr     nl
        bra     done

mode_a: move.l  #205,d6
        moveq   #7,d7
        bra.s   deep_go
mode_z: move.l  #205,d6
        moveq   #0,d7
        bra.s   deep_go
mode_u: moveq   #0,d6
        bra.s   exit_m1
mode_v: moveq   #103,d6
        bra.s   exit_m1
mode_w: move.l  #218,d6
        bra.s   exit_m1
mode_e: move.l  #205,d6
exit_m1:
        moveq   #-1,d7
deep_go:
        move.l  4.w,a0
        move.l  276(a0),a0
        move.l  d6,PR_RESULT2(a0)
        moveq   #4,d5
        bsr     deep
        lea     m_back(pc),a0           ; Exit returned: failure
        bsr     puts
        bra     done
; deep(d5 = depth, d7 = code): 512 bytes of locals per level, Exit(d7) at the bottom.
deep:   link    a5,#-512
        move.l  sp,a0
        move.w  #127,d0
.fill:  move.l  #$DEADBEEF,(a0)+
        dbra    d0,.fill
        subq.l  #1,d5
        beq.s   .bot
        bsr.s   deep
        unlk    a5
        rts
.bot:   move.l  dosbase,a6
        move.l  d7,d1
        jsr     -144(a6)                ; Exit(code): never returns
        unlk    a5
        rts

mode_c: lea     m_cli(pc),a0
        bsr     puts
        move.l  4.w,a6
        move.l  276(a6),a0
        move.l  PR_CLI(a0),d0
        lsl.l   #2,d0
        beq.s   .nocli
        move.l  d0,a2
        move.l  12(a2),d0               ; cli_ReturnCode
        bsr     hex8
        move.l  (a2),d0                 ; cli_Result2
        bsr     hex8
.nocli: moveq   #0,d1
        jsr     -216(a6)                ; AvailMem(MEMF_ANY)
        bsr     hex8
        bsr     nl
        bra.s   done

mode_f: lea     m_end(pc),a0
        bsr     puts
        move.l  dosbase,a6
        moveq   #20,d1
        jsr     -144(a6)
        lea     m_back(pc),a0
        bsr     puts
        bra.s   done

mode_n: lea     m_never(pc),a0
        bsr     puts

done:   move.l  4.w,a6
        move.l  dosbase,d0
        beq.s   done_r
        move.l  d0,a1
        jsr     -414(a6)                ; CloseLibrary
done_r: moveq   #0,d0
        rts

; child: body of the CreateProc'd process (entry through the fake segment below).
child:  st      flags
        move.l  dosbase,a6
        moveq   #5,d1
        jsr     -144(a6)                ; Exit(5): ends the process
        st      flags+1
.hang:  bra.s   .hang

; dig(d0 = 0/1): one digit and a space.
dig:    add.b   #'0',d0
        lea     hbuf,a0
        move.b  d0,(a0)+
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bra.s   puts
nl:     lea     m_nl(pc),a0
; puts(a0): NUL-terminated string on the serial port. Clobbers d1/a0.
puts:   move.b  (a0)+,d1
        beq.s   .e
.w:     btst    #5,SERDATR              ; TBE (bit 13)
        beq.s   .w
        and.w   #$FF,d1
        or.w    #$100,d1
        move.w  d1,SERDAT
        bra.s   puts
.e:     rts
; hex8(d0.l): 8 hex digits and a space. Preserves d0.
hex8:   movem.l d0-d1,-(sp)
        moveq   #7,d1
        lea     hbuf,a0
.dg:    rol.l   #4,d0
        move.l  d0,-(sp)
        and.w   #15,d0
        move.b  hexd(pc,d0.w),(a0)+
        move.l  (sp)+,d0
        dbra    d1,.dg
        move.b  #' ',(a0)+
        clr.b   (a0)
        lea     hbuf,a0
        bsr.s   puts
        movem.l (sp)+,d0-d1
        rts
hexd:   dc.b    "0123456789ABCDEF"

dosname: dc.b   "dos.library",0
cname:  dc.b    "dxchild",0
m_gq:   dc.b    13,10,"GQ ",0
m_cpx:  dc.b    "CPX ",0
m_cli:  dc.b    "CLI ",0
m_back: dc.b    "EXIT RETURNED",13,10,0
m_end:  dc.b    "DOSEXIT END",13,10,0
m_never: dc.b   "NEVER",13,10,0
m_nl:   dc.b    13,10,0
        even

        section segdata,data
; fake one-segment seglist for CreateProc: long-aligned [next = 0][code]. A data hunk starts long-aligned.
seg:    dc.l    0
        jmp     child
        cnop    0,4
bname:  dc.b    12,"dosexit_test"
        even

        section bss,bss
dosbase: ds.l   1
buf:    ds.l    4
flags:  ds.w    1
hbuf:   ds.b    12
