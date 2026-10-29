; ticks.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Black-box probe of INTUITICKS / key repeat / held gadget (analysis track).
; Opens a BORDERLESS|ACTIVATE|RMBTRAP 640x160 window at (0,0) on the WB, covered by a
; GADGIMMEDIATE|RELVERIFY boolean gadget, IDCMP RAWKEY|GADGETDOWN|GADGETUP|MOUSEBUTTONS|INTUITICKS|
; ACTIVEWINDOW|INACTIVEWINDOW. Writes "TKREADY" then records ~30 s of messages (replied within
; <= 20 ms), then leaves 2 s of messages unread (accumulation test), then prints the log:
;   W window                          (address of the window)
;   c code qual secs micros mx my ia  (ia: '=' window, '0' null, else hex); '#' = start of the accumulation test
; Author's code, public structures (intuition.h 1.3).

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
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,d7                ; IntuitionBase
                beq     .ret
                move.l  d7,a6
                lea     nw(pc),a0
                lea     gad(pc),a1
                move.l  a1,18(a0)            ; nw_FirstGadget
                jsr     -204(a6)             ; OpenWindow
                move.l  d0,d6
                beq     .ret
                lea     ready(pc),a0
                lea     8(a0),a1
                bsr     outbuf
                lea     log,a4               ; log write pointer
                move.l  #1500,d5             ; Delay(1) iterations
.loop:          bsr     drain
                moveq   #1,d1
                move.l  a6,-(sp)
                move.l  dosbase(pc),a6
                jsr     -198(a6)             ; Delay(1)
                move.l  (sp)+,a6
                subq.l  #1,d5
                bne.s   .loop
                move.l  #$23232323,(a4)+     ; '#' marker
                lea     20(a4),a4
                moveq   #100,d1
                move.l  dosbase(pc),a6
                jsr     -198(a6)             ; Delay(100) without reading the port
                bsr     drain
                move.l  d7,a6
                move.l  d6,a0
                jsr     -72(a6)              ; CloseWindow
; --- printing
                lea     buf,a1
                lea     t_w(pc),a0
                bsr     cpy
                move.l  d6,d0
                bsr     hex
                move.b  #10,(a1)+
                lea     log,a3
.pr:            cmp.l   a4,a3
                bcc     .pre
                move.l  (a3),d0
                cmp.l   #$23232323,d0
                bne.s   .pr1
                move.b  #'#',(a1)+
                move.b  #10,(a1)+
                lea     24(a3),a3
                bra.s   .pr
.pr1:           bsr     clsch
                move.b  d0,(a1)+
                move.b  #' ',(a1)+
                move.w  4(a3),d0
                bsr     hex4
                move.w  6(a3),d0
                bsr     hex4
                move.l  16(a3),d0
                bsr     hex4                 ; seconds (low 16 bits)
                move.l  20(a3),d0
                bsr     hex
                move.w  12(a3),d0
                bsr     hex4
                move.w  14(a3),d0
                bsr     hex4
                move.l  8(a3),d0
                cmp.l   d6,d0
                bne.s   .ia1
                move.b  #'=',(a1)+
                bra.s   .ia2
.ia1:           tst.l   d0
                bne.s   .ia3
                move.b  #'0',(a1)+
                bra.s   .ia2
.ia3:           bsr     hex
.ia2:           move.b  #10,(a1)+
                lea     24(a3),a3
                cmp.l   #bufend-100,a1
                bcs     .pr
.pre:           lea     buf,a0
                bsr     outbuf
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

drain:                                       ; drains the UserPort into the log, replies
                move.l  4.w,a6
.d:             move.l  d6,a0
                move.l  86(a0),a0            ; wd_UserPort
                jsr     -372(a6)             ; GetMsg
                tst.l   d0
                beq.s   .dx
                move.l  d0,a1
                cmp.l   #logend-48,a4
                bcc.s   .dr
                move.l  20(a1),(a4)+         ; Class
                move.w  24(a1),(a4)+         ; Code
                move.w  26(a1),(a4)+         ; Qualifier
                move.l  28(a1),(a4)+         ; IAddress
                move.w  32(a1),(a4)+         ; MouseX
                move.w  34(a1),(a4)+         ; MouseY
                move.l  36(a1),(a4)+         ; Seconds
                move.l  40(a1),(a4)+         ; Micros
.dr:            jsr     -378(a6)             ; ReplyMsg
                bra.s   .d
.dx:            move.l  d7,a6
                rts

clsch:                                       ; class d0 -> letter d0
                lea     ctab(pc),a0
.c:             tst.l   (a0)
                beq.s   .cq
                cmp.l   (a0),d0
                beq.s   .cf
                addq.l  #6,a0
                bra.s   .c
.cf:            move.w  4(a0),d0
                rts
.cq:            moveq   #'?',d0
                rts

cpy:
                move.b  (a0)+,(a1)+
                bne.s   cpy
                subq.l  #1,a1
                rts
hex4:
                swap    d0
                moveq   #3,d3
                bra.s   hexl
hex:
                moveq   #7,d3
hexl:           rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:             move.b  d1,(a1)+
                dbra    d3,hexl
                move.b  #' ',(a1)+
                rts
outbuf:
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

                cnop    0,2
ctab:           dc.l    $400000
                dc.w    'T'
                dc.l    $400
                dc.w    'K'
                dc.l    $20
                dc.w    'D'
                dc.l    $40
                dc.w    'U'
                dc.l    $8
                dc.w    'B'
                dc.l    $40000
                dc.w    'A'
                dc.l    $80000
                dc.w    'I'
                dc.l    $10
                dc.w    'M'
                dc.l    0
nw:             dc.w    0,0,640,160
                dc.b    -1,-1
                dc.l    $004C0478            ; IDCMP (+MOUSEMOVE $10)
                dc.l    $00011800            ; BORDERLESS|ACTIVATE|RMBTRAP
                dc.l    0,0,0,0,0
                dc.w    0,0,0,0
                dc.w    1                    ; WBENCHSCREEN
gad:            dc.l    0
                dc.w    0,0,640,160
                dc.w    0                    ; GADGHCOMP
                dc.w    3                    ; RELVERIFY|GADGIMMEDIATE
                dc.w    1                    ; BOOLGADGET
                dc.l    0,0,0,0,0
                dc.w    0
                dc.l    0
dosbase:        dc.l    0
dosname:        dc.b    "dos.library",0
intname:        dc.b    "intuition.library",0
ready:          dc.b    "TKREADY",10
t_w:            dc.b    "W ",0
                section bss,bss
log:            ds.b    24*1200
logend:
buf:            ds.b    60000
bufend:
