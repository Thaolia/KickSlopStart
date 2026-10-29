; reqtest.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Non-regression of intuition requesters on OUR ROM (spec intuition-requesters-v34): Request / EndRequest,
; REQSET / REQCLEAR, INREQUEST and ReqCount, end via ENDGADGET (harness click), then AutoRequest (click or Amiga-V).
; One line per step, written immediately to Output():
;   A req1 flags count layer      Request(R1); flags = Window.Flags & INREQUEST
;   M class                       IDCMP message received (replied)
;   B req2 count layer            Request(R2, with an ENDGADGET)
;   C count r1layer firstreq      EndRequest(R1) (not at the head): no REQCLEAR expected
;   D                             waiting for the click on R2's gadget
;   E count flags firstreq        after REQCLEAR
;   F result before after         AutoRequest; AvailMem(MEMF_ANY) before / after (leak if they differ)
;   G a b c                       custom screen opened: FirstScreen = it (a = 0); ScreenToFront(WB): FirstScreen =
;                                 WB (b = 0); ScreenToBack(WB): FirstScreen = the custom screen (c = 0); 2 s apart
; Authored code, public structures (intuition 1.3).

INREQUEST       EQU     $4000
REQSET          EQU     $80
REQCLEAR        EQU     $1000

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     V(pc),a5
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,dosbase-V(a5)
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,intbase-V(a5)
                move.l  d0,a6
                lea     nw(pc),a0
                jsr     -204(a6)             ; OpenWindow
                move.l  d0,win-V(a5)
                beq     .ret
; A: Request(R1)
                lea     req1,a0
                jsr     -138(a6)             ; InitRequester
                lea     req1,a0
                move.w  #10,4(a0)
                move.w  #15,6(a0)
                move.w  #120,8(a0)
                move.w  #40,10(a0)
                lea     it1(pc),a1
                move.l  a1,24(a0)
                move.b  #3,30(a0)            ; BackFill
                move.l  win(pc),a1
                jsr     -240(a6)             ; Request
                lea     line,a4
                move.b  #'A',(a4)+
                move.b  #' ',(a4)+
                bsr     hex
                move.l  win(pc),a0
                move.l  24(a0),d0
                and.l   #INREQUEST,d0
                bsr     hex
                move.l  win(pc),a0
                move.w  44(a0),d0
                ext.l   d0
                bsr     hex
                move.l  req1+32,d0
                bsr     hex
                bsr     flush
                bsr     drain
; B: Request(R2) with an ENDGADGET gadget
                lea     req2,a0
                jsr     -138(a6)
                lea     req2,a0
                move.w  #140,4(a0)
                move.w  #40,6(a0)
                move.w  #160,8(a0)
                move.w  #70,10(a0)
                lea     it2(pc),a1
                move.l  a1,24(a0)
                move.b  #2,30(a0)
                lea     gad(pc),a1
                move.l  a1,16(a0)
                move.l  win(pc),a1
                jsr     -240(a6)
                lea     line,a4
                move.b  #'B',(a4)+
                move.b  #' ',(a4)+
                bsr     hex
                move.l  win(pc),a0
                move.w  44(a0),d0
                ext.l   d0
                bsr     hex
                move.l  req2+32,d0
                bsr     hex
                bsr     flush
                bsr     drain
; C: EndRequest(R1), which is not at the head
                lea     req1,a0
                move.l  win(pc),a1
                jsr     -120(a6)             ; EndRequest
                lea     line,a4
                move.b  #'C',(a4)+
                move.b  #' ',(a4)+
                move.l  win(pc),a0
                move.w  44(a0),d0
                ext.l   d0
                bsr     hex
                move.l  req1+32,d0
                bsr     hex
                move.l  win(pc),a0
                move.l  36(a0),d0
                lea     req2,a1
                sub.l   a1,d0                ; 0 if FirstRequest = R2
                bsr     hex
                bsr     flush
                bsr     drain
; D: wait for the click on END (GADGETUP then REQCLEAR)
                lea     line,a4
                move.b  #'D',(a4)+
                bsr     flush
.wait:
                bsr     waitmsg              ; d0 = class
                cmp.l   #REQCLEAR,d0
                bne.s   .wait
                lea     line,a4
                move.b  #'E',(a4)+
                move.b  #' ',(a4)+
                move.l  win(pc),a0
                move.w  44(a0),d0
                ext.l   d0
                bsr     hex
                move.l  win(pc),a0
                move.l  24(a0),d0
                and.l   #INREQUEST,d0
                bsr     hex
                move.l  win(pc),a0
                move.l  36(a0),d0
                bsr     hex
                bsr     flush
; F: AutoRequest
                move.l  4.w,a6
                moveq   #0,d1
                jsr     -216(a6)             ; AvailMem
                move.l  d0,mem0-V(a5)
                move.l  intbase(pc),a6
                move.l  win(pc),a0
                lea     itbody(pc),a1
                lea     itpos(pc),a2
                lea     itneg(pc),a3
                moveq   #0,d0
                moveq   #0,d1
                move.l  #320,d2
                moveq   #72,d3
                jsr     -348(a6)             ; AutoRequest
                lea     line,a4
                move.b  #'F',(a4)+
                move.b  #' ',(a4)+
                bsr     hex
                move.l  mem0(pc),d0
                bsr     hex
                move.l  4.w,a6
                moveq   #0,d1
                jsr     -216(a6)
                bsr     hex
                bsr     flush
; G: ScreenToFront / ScreenToBack
                move.l  intbase(pc),a6
                lea     ns(pc),a0
                jsr     -198(a6)             ; OpenScreen
                move.l  d0,scr-V(a5)
                beq     .noscr
                lea     line,a4
                move.b  #'G',(a4)+
                move.b  #' ',(a4)+
                move.l  60(a6),d0            ; IntuitionBase->FirstScreen
                sub.l   scr(pc),d0
                bsr     hex
                bsr     delay2
                move.l  win(pc),a0
                move.l  46(a0),a0            ; WScreen
                jsr     -252(a6)             ; ScreenToFront
                move.l  60(a6),d0
                move.l  win(pc),a0
                sub.l   46(a0),d0
                bsr     hex
                bsr     delay2
                move.l  win(pc),a0
                move.l  46(a0),a0
                jsr     -246(a6)             ; ScreenToBack
                move.l  60(a6),d0
                sub.l   scr(pc),d0
                bsr     hex
                bsr     flush
                bsr     delay2
                move.l  scr(pc),a0
                jsr     -66(a6)              ; CloseScreen
.noscr:
                move.l  intbase(pc),a6
                move.l  win(pc),a0
                jsr     -72(a6)              ; CloseWindow
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; waitmsg -> d0 = class of the next message ("M class" line written, message replied)
waitmsg:
                move.l  4.w,a6
                move.l  win(pc),a0
                move.l  86(a0),a0            ; UserPort
                jsr     -384(a6)             ; WaitPort
; drain: each pending message -> "M class"; d0 = last class
drain:
                moveq   #0,d7
.dl:
                move.l  4.w,a6
                move.l  win(pc),a0
                move.l  86(a0),a0
                jsr     -372(a6)             ; GetMsg
                tst.l   d0
                beq.s   .dx
                move.l  d0,a1
                move.l  20(a1),d7            ; im_Class
                jsr     -378(a6)             ; ReplyMsg
                lea     line,a4
                move.b  #'M',(a4)+
                move.b  #' ',(a4)+
                move.l  d7,d0
                bsr     hex
                bsr     flush
                bra.s   .dl
.dx:
                move.l  d7,d0
                move.l  intbase(pc),a6
                rts

delay2:         move.l  dosbase(pc),a6
                moveq   #100,d1
                jsr     -198(a6)             ; Delay(2 s)
                move.l  intbase(pc),a6
                rts
hex:            moveq   #7,d3
.hl:            rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:             move.b  d1,(a4)+
                dbra    d3,.hl
                move.b  #' ',(a4)+
                rts
flush:                                       ; Write(Output(), line, a4 - line) with a newline
                move.b  #10,(a4)+
                move.l  dosbase(pc),a6
                jsr     -60(a6)              ; Output
                move.l  d0,d1
                lea     line,a0
                move.l  a0,d2
                move.l  a4,d3
                sub.l   a0,d3
                jsr     -48(a6)              ; Write
                move.l  intbase(pc),a6
                rts

                cnop    0,2
nw:             dc.w    100,30,320,130
                dc.b    -1,-1
                dc.l    REQSET|REQCLEAR|$60  ; + GADGETDOWN / GADGETUP
                dc.l    $00001006            ; WINDOWDRAG|WINDOWDEPTH|ACTIVATE, SMART_REFRESH
                dc.l    0,0,title,0,0
                dc.w    0,0,0,0
                dc.w    1                    ; WBENCHSCREEN
ns:             dc.w    0,0,320,200,2
                dc.b    0,1
                dc.w    0,$000F              ; ViewModes, CUSTOMSCREEN
                dc.l    0,stitle,0,0
gad:            dc.l    0
                dc.w    20,30,80,20
                dc.w    0                    ; GADGHCOMP
                dc.w    $0005                ; RELVERIFY|ENDGADGET
                dc.w    1                    ; BOOLGADGET
                dc.l    bord,0,itend,0,0
                dc.w    7
                dc.l    0
bord:           dc.w    0,0
                dc.b    1,0,0,5
                dc.l    bxy,0
bxy:            dc.w    0,0,79,0,79,19,0,19,0,0
it1:            dc.b    1,3,1,0
                dc.w    8,4
                dc.l    0,t1,0
it2:            dc.b    1,2,1,0
                dc.w    8,4
                dc.l    0,t2,0
itend:          dc.b    1,0,1,0
                dc.w    24,6
                dc.l    0,tend,0
itbody:         dc.b    0,1,1,0
                dc.w    12,8
                dc.l    0,tbody,0
itpos:          dc.b    3,1,1,0
                dc.w    6,3
                dc.l    0,tpos,0
itneg:          dc.b    3,1,1,0
                dc.w    6,3
                dc.l    0,tneg,0
V:
dosbase:        dc.l    0
intbase:        dc.l    0
win:            dc.l    0
mem0:           dc.l    0
scr:            dc.l    0
stitle:         dc.b    "Ecran perso",0
title:          dc.b    "ReqTest",0
t1:             dc.b    "R1",0
t2:             dc.b    "R2",0
tend:           dc.b    "END",0
tbody:          dc.b    "Body text",0
tpos:           dc.b    "Yes",0
tneg:           dc.b    "No",0
dosname:        dc.b    "dos.library",0
intname:        dc.b    "intuition.library",0
                section bss,bss
req1:           ds.b    112
req2:           ds.b    112
line:           ds.b    128
