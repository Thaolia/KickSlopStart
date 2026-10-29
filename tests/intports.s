; intports.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe of the interrupt state (analysis track, UAE board with DiagArea):
;   IE intenar intreqr rtarea_int        : INTENAR/INTREQR + byte $F0FFEB (UAE "uae_int" flag)
;   IV n iv_Data iv_Code iv_Node         : ExecBase->IntVects[n] ($54 + 12*n), n = 0..13
;   SV n node type<<8|pri is_Data is_Code name : servers of the PORTS (3), VERTB (5), EXTER (13) lists
;   DA copy +off l0 l1 l2 l3             : RAM copy of the DiagArea (er_Reserved0c) of each ConfigDev
;   RT adr flags.ver.type.pri name idstring : ROMTags found in these copies (2-byte step)
;   RS adr name                          : ExecBase->ResourceList ($150)
; Output: Output() (run "intports >SER:"). Author's code, public structures.

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                lea     dosbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                lea     expname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,d6
                lea     buf,a1
                jsr     -120(a6)             ; Disable (consistent read)
; --- INTENAR / INTREQR / rtarea flag
                lea     t_ie(pc),a0
                bsr     cpy
                moveq   #0,d0
                move.w  $dff01c,d0
                bsr     hex
                moveq   #0,d0
                move.w  $dff01e,d0
                bsr     hex
                moveq   #0,d0
                move.b  $f0ffeb,d0
                bsr     hex
                move.b  #10,(a1)+
; --- IntVects
                moveq   #0,d4
.iv:            lea     t_iv(pc),a0
                bsr     cpy
                move.l  d4,d0
                bsr     hex
                move.l  d4,d0
                mulu    #12,d0
                lea     $54(a6,d0.l),a2
                move.l  (a2),d0
                bsr     hex
                move.l  4(a2),d0
                bsr     hex
                move.l  8(a2),d0
                bsr     hex
                move.b  #10,(a1)+
                addq.w  #1,d4
                cmp.w   #14,d4
                bne.s   .iv
; --- server chains
                moveq   #3,d4
                bsr     servers
                moveq   #5,d4
                bsr     servers
                moveq   #13,d4
                bsr     servers
; --- DiagArea copies
                tst.l   d6
                beq     .noda
                move.l  d6,a2
                move.l  $3c(a2),a2           ; eb_BoardList.lh_Head
.cd:            tst.l   (a2)
                beq     .noda
                move.l  $1c(a2),d5           ; cd_Rom.er_Reserved0c
                beq     .cdn
                moveq   #0,d4
.dal:           lea     t_da(pc),a0
                bsr     cpy
                move.l  d5,d0
                bsr     hex
                move.l  d4,d0
                bsr     hex
                move.l  d5,a3
                add.l   d4,a3
                moveq   #3,d7
.dw:            move.l  (a3)+,d0
                bsr     hex
                dbra    d7,.dw
                move.b  #10,(a1)+
                add.l   #16,d4
                cmp.l   #$90,d4
                bne.s   .dal
                move.l  d5,a3                ; ROMTags in the first $200 bytes
                move.l  a3,d7
                add.l   #$200,d7
.rt:            cmp.w   #$4afc,(a3)
                bne.s   .rtn
                cmp.l   2(a3),a3
                bne.s   .rtn
                lea     t_rt(pc),a0
                bsr     cpy
                move.l  a3,d0
                bsr     hex
                move.l  10(a3),d0            ; rt_Flags rt_Version rt_Type rt_Pri
                bsr     hex
                move.l  14(a3),a0
                bsr     cpyn
                move.b  #' ',(a1)+
                move.l  18(a3),a0
                bsr     cpyn
                move.b  #10,(a1)+
.rtn:           addq.l  #2,a3
                cmp.l   d7,a3
                bcs.s   .rt
.cdn:           move.l  (a2),a2
                bra     .cd
.noda:
                lea     $150(a6),a2
                move.l  (a2),a2
.rs:            tst.l   (a2)
                beq.s   .rse
                lea     t_rs(pc),a0
                bsr     cpy
                move.l  a2,d0
                bsr     hex
                move.l  10(a2),a0
                bsr     cpyn
                move.b  #10,(a1)+
                move.l  (a2),a2
                bra.s   .rs
.rse:
                jsr     -126(a6)             ; Enable
                lea     buf,a0
                bsr     outbuf
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

servers:                                     ; d4 = n; list = IntVects[n].iv_Data
                move.l  d4,d0
                mulu    #12,d0
                move.l  $54(a6,d0.l),d0
                beq.s   .x
                move.l  d0,a2
                move.l  (a2),a2              ; lh_Head
.s:             tst.l   (a2)
                beq.s   .x
                lea     t_sv(pc),a0
                bsr     cpy
                move.l  d4,d0
                bsr     hex
                move.l  a2,d0
                bsr     hex
                moveq   #0,d0
                move.b  8(a2),d0
                lsl.w   #8,d0
                move.b  9(a2),d0
                bsr     hex
                move.l  14(a2),d0
                bsr     hex
                move.l  18(a2),d0
                bsr     hex
                move.l  10(a2),a0
                bsr     cpyn
                move.b  #10,(a1)+
                move.l  (a2),a2
                bra.s   .s
.x:             rts

cpyn:                                        ; C name a0 (<= 31 chars) to (a1)+, NULL tolerated
                move.l  a0,d0
                beq.s   .x
                moveq   #31,d1
.l:             move.b  (a0)+,d0
                beq.s   .x
                cmp.b   #32,d0
                bcs.s   .x
                move.b  d0,(a1)+
                dbra    d1,.l
.x:             rts
cpy:
                move.b  (a0)+,(a1)+
                bne.s   cpy
                subq.l  #1,a1
                rts
hex:
                moveq   #7,d3
.h:             rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:             move.b  d1,(a1)+
                dbra    d3,.h
                move.b  #' ',(a1)+
                rts
outbuf:                                      ; writes [a0, a1) to Output()
                move.l  a1,d3
                sub.l   a0,d3
                move.l  a0,d2
                move.l  a6,-(sp)
                move.l  dosbase(pc),a6
                jsr     -60(a6)
                move.l  d0,d1
                jsr     -48(a6)
                move.l  (sp)+,a6
                rts

dosbase:        dc.l    0
dosname:        dc.b    "dos.library",0
expname:        dc.b    "expansion.library",0
t_ie:           dc.b    "IE ",0
t_iv:           dc.b    "IV ",0
t_sv:           dc.b    "SV ",0
t_da:           dc.b    "DA ",0
t_rt:           dc.b    "RT ",0
t_rs:           dc.b    "RS ",0
                section bss,bss
buf:            ds.b    8192
