; clipreg.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Sonde boîte noire de layers.library InstallClipRegion (piste analyse).
; Fenêtre BORDERLESS 100x50 en (100,50) sur le WB ; on installe des régions sur sa couche, on remplit
; toute la couche (RectFill) et on relit les pixels dans le RastPort de l'écran (sans couche).
; Lignes :  CR minx miny maxx maxy lobs bitmap        (ClipRects de la couche, coordonnées écran)
;           Tn ...                                     (valeurs du test n, cf. commentaires)
;           P x y pen                                  (pixel écran)
; Code auteur, structures publiques (graphics/layers 1.3).

L_CLIPREGION    EQU     $7e

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     dosname(pc),a1
                bsr     open
                move.l  d0,dosbase-V(a5)
                lea     gfxname(pc),a1
                bsr     open
                move.l  d0,gfxbase-V(a5)
                lea     layname(pc),a1
                bsr     open
                move.l  d0,laybase-V(a5)
                lea     intname(pc),a1
                bsr     open
                move.l  d0,intbase-V(a5)
                beq     .ret
                move.l  d0,a6
                lea     nw(pc),a0
                jsr     -204(a6)             ; OpenWindow
                move.l  d0,win-V(a5)
                beq     .ret
                move.l  d0,a0
                move.l  50(a0),rp-V(a5)      ; wd_RPort
                move.l  124(a0),lay-V(a5)    ; wd_WLayer
                move.l  46(a0),a1            ; wd_WScreen
                lea     84(a1),a1            ; Screen.RastPort
                move.l  a1,srp-V(a5)
                lea     buf,a4
; T0 : état initial
                moveq   #0,d0
                bsr     tline
                move.l  lay(pc),a0
                move.l  L_CLIPREGION(a0),d0
                bsr     hex
                bsr     nl
                bsr     crs
                bsr     newreg
                move.l  d0,r1-V(a5)
                move.l  d0,a0
                lea     rect1(pc),a1
                bsr     orrect
                moveq   #0,d0
                bsr     fill
; T1 : Install(R1) -> ancien, ClipRegion ; ClipRects ; remplissage pen 1 ; pixels
                moveq   #1,d0
                bsr     tline
                move.l  r1(pc),a1
                bsr     install
                bsr     hex
                move.l  lay(pc),a0
                move.l  L_CLIPREGION(a0),d0
                bsr     hex
                bsr     nl
                bsr     crs
                moveq   #1,d0
                bsr     fill
                lea     pts1(pc),a3
                bsr     pixels
; T2 : R1 modifiée après installation (ajout 50,30-59,39), remplissage pen 2, puis réinstallation
                moveq   #2,d0
                bsr     tline
                bsr     nl
                move.l  r1(pc),a0
                lea     rect2(pc),a1
                bsr     orrect
                moveq   #2,d0
                bsr     fill
                lea     pts2(pc),a3
                bsr     pixels
                move.l  r1(pc),a1
                bsr     install
                bsr     hex
                bsr     nl
                bsr     crs
                moveq   #2,d0
                bsr     fill
                lea     pts2(pc),a3
                bsr     pixels
; T3 : Install(NULL) -> ancien ; ClipRects ; remplissage pen 0
                moveq   #3,d0
                bsr     tline
                suba.l  a1,a1
                bsr     install
                bsr     hex
                move.l  lay(pc),a0
                move.l  L_CLIPREGION(a0),d0
                bsr     hex
                bsr     nl
                bsr     crs
                moveq   #0,d0
                bsr     fill
                lea     pts1(pc),a3
                bsr     pixels
; T4 : région vide
                moveq   #4,d0
                bsr     tline
                bsr     newreg
                move.l  d0,r2-V(a5)
                move.l  d0,a1
                bsr     install
                bsr     hex
                move.l  lay(pc),a0
                move.l  8(a0),d0             ; layer->ClipRect
                bsr     hex
                bsr     nl
                moveq   #1,d0
                bsr     fill
                lea     pts1(pc),a3
                bsr     pixels
                suba.l  a1,a1
                bsr     install
; T5 : région débordant la couche (-20,-20 .. 200,200)
                moveq   #5,d0
                bsr     tline
                bsr     nl
                move.l  r2(pc),a0
                lea     rect3(pc),a1
                bsr     orrect
                move.l  r2(pc),a1
                bsr     install
                bsr     crs
                suba.l  a1,a1
                bsr     install
; T6 : opération de couche avec région installée : MoveWindow(+20,+10)
                moveq   #6,d0
                bsr     tline
                bsr     nl
                moveq   #0,d0
                bsr     fill
                move.l  r1(pc),a1
                bsr     install
                move.l  intbase(pc),a6
                move.l  win(pc),a0
                moveq   #20,d0
                moveq   #10,d1
                jsr     -168(a6)             ; MoveWindow
                moveq   #50,d1
                move.l  dosbase(pc),a6
                jsr     -198(a6)             ; Delay(50)
                move.l  lay(pc),a0
                bsr     tline6
                bsr     crs
                moveq   #3,d0
                bsr     fill
                lea     pts6(pc),a3
                bsr     pixels
                suba.l  a1,a1
                bsr     install
; fin
                move.l  intbase(pc),a6
                move.l  win(pc),a0
                jsr     -72(a6)              ; CloseWindow
                move.l  a4,a1
                lea     buf,a0
                bsr     outbuf
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

open:           moveq   #0,d0
                jsr     -552(a6)
                lea     V(pc),a5
                rts
tline6:                                      ; « L minx miny cliprgn »
                move.b  #'L',(a4)+
                move.b  #' ',(a4)+
                move.w  16(a0),d0
                bsr     hex4
                move.w  18(a0),d0
                bsr     hex4
                move.l  L_CLIPREGION(a0),d0
                bsr     hex
                bra     nl
tline:          move.b  #'T',(a4)+
                add.b   #'0',d0
                move.b  d0,(a4)+
                move.b  #' ',(a4)+
                rts
nl:             move.b  #10,(a4)+
                rts
newreg:         move.l  gfxbase(pc),a6
                jsr     -516(a6)             ; NewRegion
                rts
orrect:         move.l  gfxbase(pc),a6
                jsr     -510(a6)             ; OrRectRegion(a0 région, a1 rect)
                rts
install:        move.l  laybase(pc),a6
                move.l  lay(pc),a0
                jsr     -174(a6)             ; InstallClipRegion(a0 couche, a1 région) -> d0
                rts
fill:                                        ; SetAPen(d0) + RectFill de toute la couche
                move.l  gfxbase(pc),a6
                move.l  rp(pc),a1
                jsr     -342(a6)             ; SetAPen
                move.l  rp(pc),a1
                moveq   #0,d0
                moveq   #0,d1
                moveq   #99,d2
                moveq   #49,d3
                jsr     -306(a6)             ; RectFill
                jsr     -228(a6)             ; WaitBlit
                rts
pixels:                                      ; liste (x,y) en a3, fin = -1
.p:             move.w  (a3)+,d4
                bmi.s   .px
                move.w  (a3)+,d5
                move.b  #'P',(a4)+
                move.b  #' ',(a4)+
                move.w  d4,d0
                bsr     hex4
                move.w  d5,d0
                bsr     hex4
                move.l  gfxbase(pc),a6
                move.l  srp(pc),a1
                moveq   #0,d0
                move.w  d4,d0
                moveq   #0,d1
                move.w  d5,d1
                jsr     -318(a6)             ; ReadPixel
                bsr     hex
                bsr     nl
                bra.s   .p
.px:            rts
crs:                                         ; ClipRects de la couche
                move.l  lay(pc),a0
                move.l  8(a0),a2
.c:             move.l  a2,d0
                beq.s   .cx
                move.b  #'C',(a4)+
                move.b  #'R',(a4)+
                move.b  #' ',(a4)+
                move.w  16(a2),d0
                bsr     hex4
                move.w  18(a2),d0
                bsr     hex4
                move.w  20(a2),d0
                bsr     hex4
                move.w  22(a2),d0
                bsr     hex4
                move.l  8(a2),d0
                bsr     hex
                move.l  12(a2),d0
                bsr     hex
                bsr     nl
                move.l  (a2),a2
                bra.s   .c
.cx:            rts
hex4:           swap    d0
                moveq   #3,d3
                bra.s   hexl
hex:            moveq   #7,d3
hexl:           rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:             move.b  d1,(a4)+
                dbra    d3,hexl
                move.b  #' ',(a4)+
                rts
outbuf:         move.l  a1,d3
                sub.l   a0,d3
                move.l  a0,d2
                move.l  dosbase(pc),a6
                jsr     -60(a6)
                move.l  d0,d1
                jsr     -48(a6)
                rts

                cnop    0,2
rect1:          dc.w    10,10,29,19
rect2:          dc.w    50,30,59,39
rect3:          dc.w    -20,-20,200,200
pts1:           dc.w    105,55, 115,65, 129,69, 130,70, -1
pts2:           dc.w    115,65, 155,85, -1
pts6:           dc.w    125,65, 135,75, 149,79, 150,80, 115,65, -1
nw:             dc.w    100,50,100,50
                dc.b    -1,-1
                dc.l    0
                dc.l    $00001800            ; BORDERLESS|ACTIVATE, SMART_REFRESH
                dc.l    0,0,0,0,0
                dc.w    0,0,0,0
                dc.w    1
V:
dosbase:        dc.l    0
gfxbase:        dc.l    0
laybase:        dc.l    0
intbase:        dc.l    0
win:            dc.l    0
rp:             dc.l    0
lay:            dc.l    0
srp:            dc.l    0
r1:             dc.l    0
r2:             dc.l    0
dosname:        dc.b    "dos.library",0
gfxname:        dc.b    "graphics.library",0
layname:        dc.b    "layers.library",0
intname:        dc.b    "intuition.library",0
                section bss,bss
buf:            ds.b    8192
