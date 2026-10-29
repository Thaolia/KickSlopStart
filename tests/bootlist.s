; bootlist.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe of booting with a DiagArea board (analysis track):
;   RM adr pri flags type name     : ExecBase->ResModules (array, bit 31 = continuation)
;   DV adr name / LB adr name      : exec DeviceList / LibList
;   BN adr type pri flags lnname devnode : expansion eb_MountList ($4A)
;   RN fhseg                       : RootNode+$1C (rn_FileHandlerSegment)
;   DN adr type task lock handler startup seglist gv name : DosInfo->di_DevInfo
; Output: Output() (run "bootlist >SER:"). Author's code, public structures.

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
                jsr     -132(a6)             ; Forbid
; --- ResModules
                move.l  $12c(a6),a2
.rm:            move.l  (a2)+,d0
                beq.s   .rme
                bpl.s   .rm1
                bclr    #31,d0
                move.l  d0,a2
                bra.s   .rm
.rm1:           move.l  d0,a3
                lea     t_rm(pc),a0
                bsr     cpy
                move.l  a3,d0
                bsr     hex
                moveq   #0,d0
                move.b  13(a3),d0            ; rt_Pri
                lsl.w   #8,d0
                move.b  10(a3),d0            ; rt_Flags
                swap    d0
                move.b  12(a3),d0            ; rt_Type
                lsl.w   #8,d0
                move.b  11(a3),d0            ; rt_Version
                bsr     hex
                move.l  14(a3),a0
                bsr     cpyn
                move.b  #10,(a1)+
                bra.s   .rm
.rme:
; --- DeviceList, LibList
                lea     $15e(a6),a2
                lea     t_dv(pc),a4
                bsr     nodes
                lea     $17a(a6),a2
                lea     t_lb(pc),a4
                bsr     nodes
; --- eb_MountList
                tst.l   d6
                beq.s   .nobn
                move.l  d6,a2
                move.l  $4a(a2),a2
.bn:            tst.l   (a2)
                beq.s   .nobn
                lea     t_bn(pc),a0
                bsr     cpy
                move.l  a2,d0
                bsr     hex
                moveq   #0,d0
                move.b  8(a2),d0             ; ln_Type
                lsl.w   #8,d0
                move.b  9(a2),d0             ; ln_Pri
                swap    d0
                move.w  14(a2),d0            ; bn_Flags
                bsr     hex
                move.l  10(a2),d0            ; ln_Name
                bsr     hex
                move.l  16(a2),d0            ; bn_DeviceNode
                bsr     hex
                move.b  #10,(a1)+
                move.l  (a2),a2
                bra.s   .bn
.nobn:
; --- RootNode / DevInfo
                move.l  dosbase(pc),a2
                move.l  34(a2),a2            ; dl_Root
                lea     t_rn(pc),a0
                bsr     cpy
                move.l  $1c(a2),d0
                bsr     hex
                move.l  $18(a2),d0           ; rn_Info BPTR
                bsr     hex
                move.b  #10,(a1)+
                move.l  $18(a2),d0
                lsl.l   #2,d0
                move.l  d0,a2
                move.l  4(a2),d0             ; di_DevInfo BPTR
.dn:            lsl.l   #2,d0
                beq.s   .dne
                move.l  d0,a2
                lea     t_dn(pc),a0
                bsr     cpy
                move.l  a2,d0
                bsr     hex
                move.l  4(a2),d0             ; dn_Type
                bsr     hex
                move.l  8(a2),d0             ; dn_Task
                bsr     hex
                move.l  12(a2),d0            ; dn_Lock
                bsr     hex
                move.l  16(a2),d0            ; dn_Handler
                bsr     hex
                move.l  28(a2),d0            ; dn_Startup
                bsr     hex
                move.l  32(a2),d0            ; dn_SegList
                bsr     hex
                move.l  36(a2),d0            ; dn_GlobalVec
                bsr     hex
                move.l  40(a2),d0            ; dn_Name BSTR
                lsl.l   #2,d0
                beq.s   .dnn
                move.l  d0,a0
                moveq   #0,d1
                move.b  (a0)+,d1
                cmp.w   #30,d1
                bhi.s   .dnn
                bra.s   .dnc
.dnl:           move.b  (a0)+,(a1)+
.dnc:           dbra    d1,.dnl
.dnn:           move.b  #10,(a1)+
                move.l  (a2),d0
                bra.s   .dn
.dne:
                jsr     -138(a6)             ; Permit
                lea     buf,a0
                bsr     outbuf
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

nodes:                                       ; exec list a2, prefix a4
                move.l  (a2),a2
.n:             tst.l   (a2)
                beq.s   .ne
                move.l  a4,a0
                bsr     cpy
                move.l  a2,d0
                bsr     hex
                move.l  10(a2),a0
                bsr     cpyn
                move.b  #10,(a1)+
                move.l  (a2),a2
                bra.s   .n
.ne:            rts

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
t_rm:           dc.b    "RM ",0
t_dv:           dc.b    "DV ",0
t_lb:           dc.b    "LB ",0
t_bn:           dc.b    "BN ",0
t_rn:           dc.b    "RN ",0
t_dn:           dc.b    "DN ",0
                section bss,bss
buf:            ds.b    8192
