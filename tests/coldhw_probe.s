; tests/coldhw_probe.s - black-box PROBE bootblock for the coldstart (TEST ASSET, NOT ROM code).
; Assembled as a raw binary (vasm -Fbin -m68000 -DMODE=n), placed at offset +12 of an ADF bootblock by
; tests/coldhw_probe.sh. Used to observe, under the REAL 1.3 ROM, the state left by the coldstart (ExecBase,
; MemList, low RAM, survival across reset) and the Alert -> reset -> alert.hook chain. AUTHORED code: uses only
; the public ABI (ExecBase offsets from exec/execbase.i, LVOs from exec_lib.fd) and the public hardware registers.
;
; Boot counter: magic long 'CHWM' + counter at CHIPMARK (and SLOWMARK if RAM exists at $C00000).
; First boot (counter = 1): MODE action; subsequent boots: report only, then infinite wait.
;   MODE 0: report only.
;   MODE 1: dead-end Alert($8100000F), A5 -> $CAFEBABE.
;   MODE 2: recoverable Alert($35000001), A5 -> $12345678, then "RET" report.
;   MODE 3: ILLEGAL instruction.
;   MODE 4: software reboot (RESET + jump into the ROM via address 2, public 1.3 technique).
;   MODE 5: sets ColdCapture/CoolCapture (stubs copied into chip RAM), recomputes ChkSum, then MODE 4 reboot.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
CHIPMARK EQU $60000
SLOWMARK EQU $C40100
STUBS    EQU $61000
        IFND MODE
MODE    EQU 0
        ENDC

start:
        movea.l 4.w,a6
        lea     m_head(pc),a0
        bsr     puts
        moveq   #MODE,d0
        bsr     hex8
        bsr     nl
        ; low RAM
        lea     m_low(pc),a0
        bsr     puts
        move.l  0.w,d0
        bsr     hex8
        move.l  $100.w,d0
        bsr     hex8
        move.l  $104.w,d0
        bsr     hex8
        bsr     nl
        ; ExecBase and fields
        lea     m_eb(pc),a0
        bsr     puts
        move.l  a6,d0
        bsr     hex8
        move.l  $3E(a6),d0          ; MaxLocMem
        bsr     hex8
        move.l  $4E(a6),d0          ; MaxExtMem
        bsr     hex8
        move.l  $36(a6),d0          ; SysStkUpper
        bsr     hex8
        move.l  $3A(a6),d0          ; SysStkLower
        bsr     hex8
        bsr     nl
        lea     m_cap(pc),a0
        bsr     puts
        move.l  $2A(a6),d0          ; ColdCapture
        bsr     hex8
        move.l  $2E(a6),d0          ; CoolCapture
        bsr     hex8
        move.l  $32(a6),d0          ; WarmCapture
        bsr     hex8
        move.l  $202(a6),d0         ; LastAlert[0]
        bsr     hex8
        move.l  $206(a6),d0         ; LastAlert[1]
        bsr     hex8
        move.w  $128(a6),d0         ; AttnFlags
        bsr     hex8
        move.l  $212(a6),d0         ; VBlankFreq/PowerSupplyFreq (2 high bytes)
        bsr     hex8
        bsr     nl
        ; MemList
        lea     $142(a6),a2
        movea.l (a2),a2
.ml:    tst.l   (a2)
        beq.s   .mld
        lea     m_mh(pc),a0
        bsr     puts
        move.l  a2,d0
        bsr     hex8
        moveq   #0,d0
        move.b  9(a2),d0            ; LN_PRI
        bsr     hex8
        move.w  $E(a2),d0           ; mh_Attributes
        bsr     hex8
        move.l  $14(a2),d0          ; mh_Lower
        bsr     hex8
        move.l  $18(a2),d0          ; mh_Upper
        bsr     hex8
        move.l  $1C(a2),d0          ; mh_Free
        bsr     hex8
        movea.l $A(a2),a0           ; name
        bsr     puts
        bsr     nl
        movea.l (a2),a2
        bra.s   .ml
.mld:
        ; survival markers
        lea     m_mark(pc),a0
        bsr     puts
        lea     CHIPMARK,a3
        bsr     mark
        move.l  d0,d6               ; chip counter (after increment)
        move.l  $4E(a6),d1
        cmp.l   #SLOWMARK+16,d1
        bls.s   .noslow
        lea     SLOWMARK,a3
        bsr     mark
.noslow:
        move.l  CHIPMARK+16,d0      ; ColdCapture/CoolCapture counters (MODE 5)
        bsr     hex8
        move.l  CHIPMARK+20,d0
        bsr     hex8
        bsr     nl
        cmp.l   #1,d6
        bne     idle
        IFEQ MODE-1
        lea     v_cafe(pc),a5
        move.l  #$8100000F,d7
        jsr     -108(a6)
        ENDC
        IFEQ MODE-2
        lea     v_1234(pc),a5
        move.l  #$35000001,d7
        jsr     -108(a6)
        lea     m_ret(pc),a0
        bsr     puts
        move.l  $202(a6),d0
        bsr     hex8
        move.l  0.w,d0
        bsr     hex8
        bsr     nl
        ENDC
        IFEQ MODE-3
        illegal
        ENDC
        IFEQ MODE-5
        clr.l   CHIPMARK+16
        clr.l   CHIPMARK+20
        lea     stub_cold(pc),a0
        lea     STUBS,a1
        moveq   #(stub_end-stub_cold)/2-1,d0
.cp:    move.w  (a0)+,(a1)+
        dbra    d0,.cp
        move.l  #STUBS,$2A(a6)
        move.l  #STUBS+(stub_cool-stub_cold),$2E(a6)
        ; ChkSum: complement of the sum of words $22..$50
        lea     $22(a6),a0
        moveq   #0,d1
        moveq   #($52-$22)/2-1,d0
.cs:    add.w   (a0)+,d1
        dbra    d0,.cs
        not.w   d1
        move.w  d1,$52(a6)
        ENDC
        IFGE MODE-4
        lea     m_rb(pc),a0
        bsr     puts
        lea     2.w,a0              ; the bootblock runs in USER mode: RESET requires Supervisor()
        lea     resetcode(pc),a5
        jsr     -30(a6)
        ENDC
idle:   lea     m_idle(pc),a0
        bsr     puts
.w:     bra.s   .w

        cnop    0,4
resetcode:
        reset
        jmp     (a0)

stub_cold:
        addq.l  #1,CHIPMARK+16
        jmp     (a5)
stub_cool:
        addq.l  #1,CHIPMARK+20
        rts
stub_end:

; mark: A3 = area; if 'CHWM' is present, increments the counter, otherwise initialises it to 1. Prints before/after.
mark:   move.l  (a3),d0
        bsr     hex8
        move.l  4(a3),d0
        bsr     hex8
        cmp.l   #'CHWM',(a3)
        beq.s   .inc
        move.l  #'CHWM',(a3)
        clr.l   4(a3)
.inc:   addq.l  #1,4(a3)
        move.l  4(a3),d0
        rts

; hex8: prints D0 as 8 hex digits + space
hex8:   movem.l d0-d2,-(a7)
        move.l  d0,d2
        moveq   #7,d1
.h:     rol.l   #4,d2
        move.b  d2,d0
        and.b   #$F,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls.s   .o
        addq.b  #7,d0
.o:     bsr.s   putc
        dbra    d1,.h
        moveq   #' ',d0
        bsr.s   putc
        movem.l (a7)+,d0-d2
        rts
nl:     move.l  d0,-(a7)
        moveq   #13,d0
        bsr.s   putc
        moveq   #10,d0
        bsr.s   putc
        move.l  (a7)+,d0
        rts
puts:   move.l  d0,-(a7)
.p:     move.b  (a0)+,d0
        beq.s   .e
        bsr.s   putc
        bra.s   .p
.e:     move.l  (a7)+,d0
        rts
putc:   movem.l d0/d2,-(a7)
        move.w  #$4000,d2
.wt:    btst    #13-8,SERDATR
        bne.s   .tx
        dbra    d2,.wt
.tx:    and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (a7)+,d0/d2
        rts

v_cafe: dc.l    $CAFEBABE
v_1234: dc.l    $12345678
m_head: dc.b    "CHW mode ",0
m_low:  dc.b    "LOW 0/100/104 ",0
m_eb:   dc.b    "EB base/MaxLoc/MaxExt/StkUp/StkLo ",0
m_cap:  dc.b    "CAP cold/cool/warm LA0 LA1 Attn VBF ",0
m_mh:   dc.b    "MH adr/pri/attr/lower/upper/free ",0
m_mark: dc.b    "MARK chip(avant cnt) [slow(avant cnt)] coldcnt coolcnt ",0
m_ret:  dc.b    "RET LA0 low0 ",0
m_rb:   dc.b    "REBOOT",13,10,0
m_idle: dc.b    "IDLE",13,10,0
        even
