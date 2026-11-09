; tests/menucat.s - HUNK test executable (TEST ASSET, NOT ROM code).
; Opens a window on the Workbench screen with a "Projet" menu whose items have shortcuts (COMMSEQ):
; pulling down the menu (right button) shows the Amiga key symbol (the KickSlopStart cat) in front of each
; letter. The "Grise" ('G') item is disabled. "Option" menu: "Bascule" (CHECKIT|MENUTOGGLE, 'B') and "Coche"
; (CHECKIT, initially checked): the menu checkmark. "Export" (Projet, item 4) has two sub-items at (100, 0) and
; (100, 10): "Texte" ('T') and "Image". Each MENUPICK received (mouse or right Amiga + letter) is shown
; in the window title: "cccc qqqq #n > c1 c2 c3 c4 | ff" (code, qualifier, message index, the NextSelect chain
; walked from the code through ItemAddress, then the check state of the four "Option" items, bit n = item n).
; "Option" also has "Excl A" and "Excl B" (CHECKIT, MutualExclude each other; Excl B starts checked). "Sauver" is
; highlighted with HIGHBOX, "Quitter" with HIGHIMAGE (SelectFill = the text in capitals).
; Assembly: vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/menucat tests/menucat.s
; Author's code; public structures (intuition/intuition.h, exec/ports.h).

                section code,code
_start:
                move.l  4.w,a6
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                move.l  d0,a5                ; a5 = IntuitionBase
                tst.l   d0
                beq     .out
                lea     newwin(pc),a0
                move.l  a5,a6
                jsr     -204(a6)             ; OpenWindow
                tst.l   d0
                beq     .out
                move.l  d0,a4                ; a4 = window
                move.l  a4,a0
                lea     menu(pc),a1
                jsr     -264(a6)             ; SetMenuStrip
                moveq   #0,d7                ; message index
.wait:
                move.l  4.w,a6
                move.l  $56(a4),a0           ; UserPort
                jsr     -384(a6)             ; WaitPort
.get:
                move.l  4.w,a6
                move.l  $56(a4),a0
                jsr     -372(a6)             ; GetMsg
                tst.l   d0
                beq.s   .wait
                move.l  d0,a3
                cmp.l   #$100,20(a3)         ; im_Class = MENUPICK
                bne     .reply
                addq.w  #1,d7
                lea     tcode(pc),a0
                move.w  24(a3),d0            ; im_Code
                bsr     hex4
                lea     tqual(pc),a0
                move.w  26(a3),d0            ; im_Qualifier
                bsr     hex4
                lea     tnum(pc),a0
                move.w  d7,d0
                bsr     hex4
                lea     tchain(pc),a2        ; the chain: up to 4 codes ("----" after its end)
                move.w  24(a3),d6
                moveq   #3,d5
.chain:
                move.l  a2,a0
                cmp.w   #$FFFF,d6
                beq.s   .cend
                move.w  d6,d0
                bsr     hex4
                lea     menu(pc),a0
                move.w  d6,d0
                move.l  a5,a6
                jsr     -144(a6)             ; ItemAddress
                move.l  d0,a0
                move.w  32(a0),d6            ; NextSelect
                bra.s   .cnx
.cend:
                move.b  #'-',(a0)+
                move.b  #'-',(a0)+
                move.b  #'-',(a0)+
                move.b  #'-',(a0)+
.cnx:
                addq.l  #5,a2
                dbra    d5,.chain
                moveq   #0,d0                ; check states of the "Option" items
                lea     oitem1(pc),a0
                moveq   #0,d1
.ck:
                btst    #0,12(a0)            ; CHECKED ($100)
                beq.s   .ckn
                bset    d1,d0
.ckn:
                addq.w  #1,d1
                move.l  (a0),a0
                move.l  a0,d2
                bne.s   .ck
                lea     tchk(pc),a0
                bsr     hex4
                move.l  a4,a0
                lea     title(pc),a1
                move.l  #-1,a2
                move.l  a5,a6
                jsr     -276(a6)             ; SetWindowTitles
.reply:
                move.l  4.w,a6
                move.l  a3,a1
                jsr     -378(a6)             ; ReplyMsg
                bra     .get
.out:
                moveq   #20,d0
                rts

; hex4(a0 = 4 characters to fill, d0.w = value)
hex4:
                moveq   #3,d2
.hl:
                rol.w   #4,d0
                move.w  d0,d1
                and.w   #$F,d1
                move.b  hexd(pc,d1.w),(a0)+
                dbra    d2,.hl
                rts
hexd:           dc.b    "0123456789ABCDEF"

newwin:         dc.w    40,30,440,80
                dc.b    0,1
                dc.l    $100                 ; IDCMP: MENUPICK
                dc.l    $100F                ; WINDOWSIZING|DRAG|DEPTH|CLOSE|ACTIVATE
                dc.l    0,0
                dc.l    wtitle
                dc.l    0,0
                dc.w    80,40,640,256
                dc.w    1                    ; WBENCHSCREEN
menu:           dc.l    menu2
                dc.w    4,0,80,10
                dc.w    1                    ; MENUENABLED
                dc.l    mname
                dc.l    item1
                dc.w    0,0,0,0
item1:          dc.l    item2
                dc.w    0,0,150,10
                dc.w    $0056                ; ITEMTEXT|COMMSEQ|ITEMENABLED|HIGHCOMP
                dc.l    0
                dc.l    it1,0
                dc.b    'O',0
                dc.l    0
                dc.w    0
item2:          dc.l    item3
                dc.w    0,10,150,10
                dc.w    $0096                ; ITEMTEXT|COMMSEQ|ITEMENABLED|HIGHBOX
                dc.l    0
                dc.l    it2,0
                dc.b    'S',0
                dc.l    0
                dc.w    0
item3:          dc.l    item4
                dc.w    0,20,150,10
                dc.w    $0016                ; ITEMTEXT|COMMSEQ|ITEMENABLED|HIGHIMAGE
                dc.l    0
                dc.l    it3,it3s
                dc.b    'Q',0
                dc.l    0
                dc.w    0
item4:          dc.l    item5
                dc.w    0,30,150,10
                dc.w    $0046                ; ITEMTEXT|COMMSEQ|HIGHCOMP, disabled
                dc.l    0
                dc.l    it4,0
                dc.b    'G',0
                dc.l    0
                dc.w    0
item5:          dc.l    0
                dc.w    0,40,150,10
                dc.w    $0052                ; ITEMTEXT|ITEMENABLED|HIGHCOMP
                dc.l    0
                dc.l    it5,0
                dc.b    0,0
                dc.l    sub1
                dc.w    0
sub1:           dc.l    sub2
                dc.w    100,0,90,10
                dc.w    $0056                ; ITEMTEXT|COMMSEQ|ITEMENABLED|HIGHCOMP
                dc.l    0
                dc.l    st1,0
                dc.b    'T',0
                dc.l    0
                dc.w    0
sub2:           dc.l    0
                dc.w    100,10,90,10
                dc.w    $0052
                dc.l    0
                dc.l    st2,0
                dc.b    0,0
                dc.l    0
                dc.w    0
it5:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t5,0
st1:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,s1,0
st2:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,s2,0
menu2:          dc.l    0
                dc.w    90,0,80,10
                dc.w    1
                dc.l    mname2
                dc.l    oitem1
                dc.w    0,0,0,0
oitem1:         dc.l    oitem2
                dc.w    0,0,150,10
                dc.w    $005F                ; CHECKIT|ITEMTEXT|COMMSEQ|MENUTOGGLE|ITEMENABLED|HIGHCOMP
                dc.l    0
                dc.l    ot1,0
                dc.b    'B',0
                dc.l    0
                dc.w    0
oitem2:         dc.l    oitem3
                dc.w    0,10,150,10
                dc.w    $0153                ; CHECKIT|ITEMTEXT|ITEMENABLED|HIGHCOMP|CHECKED
                dc.l    0
                dc.l    ot2,0
                dc.b    0,0
                dc.l    0
                dc.w    0
oitem3:         dc.l    oitem4
                dc.w    0,20,150,10
                dc.w    $0053                ; CHECKIT|ITEMTEXT|ITEMENABLED|HIGHCOMP
                dc.l    %1000                ; excludes Excl B
                dc.l    ot3,0
                dc.b    0,0
                dc.l    0
                dc.w    0
oitem4:         dc.l    0
                dc.w    0,30,150,10
                dc.w    $0153                ; CHECKIT|ITEMTEXT|ITEMENABLED|HIGHCOMP|CHECKED
                dc.l    %0100                ; excludes Excl A
                dc.l    ot4,0
                dc.b    0,0
                dc.l    0
                dc.w    0
ot3:            dc.b    0,1,1,0
                dc.w    20,1
                dc.l    0,o3,0
ot4:            dc.b    0,1,1,0
                dc.w    20,1
                dc.l    0,o4,0
ot1:            dc.b    0,1,1,0
                dc.w    20,1
                dc.l    0,o1,0
ot2:            dc.b    0,1,1,0
                dc.w    20,1
                dc.l    0,o2,0
it1:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t1,0
it2:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t2,0
it3:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t3,0
it3s:           dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t3s,0
it4:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t4,0
intname:        dc.b    "intuition.library",0
wtitle:         dc.b    "Le chat de la touche Amiga",0
title:
tcode:          dc.b    "0000 "
tqual:          dc.b    "0000 #"
tnum:           dc.b    "0000 > "
tchain:         dc.b    "0000 0000 0000 0000 | "
tchk:           dc.b    "0000",0
mname:          dc.b    "Projet",0
mname2:         dc.b    "Option",0
o1:             dc.b    "Bascule",0
o2:             dc.b    "Coche",0
o3:             dc.b    "Excl A",0
o4:             dc.b    "Excl B",0
t1:             dc.b    "Ouvrir",0
t2:             dc.b    "Sauver",0
t3:             dc.b    "Quitter",0
t3s:            dc.b    "QUITTER",0
t4:             dc.b    "Grise",0
t5:             dc.b    "Export  >>",0
s1:             dc.b    "Texte",0
s2:             dc.b    "Image",0
                even
