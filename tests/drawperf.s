; tests/drawperf.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM) : chronométrage de Draw et RectFill
; de graphics.library. Lancer « drawperf >df0:dp.out » ; une ligne par mesure. Assembler avec -kick1hunks.
; Écran CUSTOMSCREEN 640x200 HIRES 2 plans. Mesures sur le RastPort de l'écran (sans couche), puis dans une fenêtre
; BORDERLESS 400x150 en (100,20) recouverte en partie par une seconde fenêtre 120x60 en (420,110) : la couche de la
; première a alors plusieurs ClipRects.
;   H : 100 Draw horizontaux (620 px sur l'écran, 390 dans la fenêtre)
;   V : 100 Draw verticaux (180 px / 140 px)
;   D : 50 Draw diagonaux (coin à coin)
;   R : 10 RectFill pleins
;   P : 1 RectFill à motif de 2 lignes (comme les barres des fenêtres)
;   X1..X4 : 20 Text de 70 caractères (45 dans la fenêtre), en JAM2, JAM1, COMPLEMENT et gras
;   B : 20 BltTemplate de 560 x 8 (360 x 8 dans la fenêtre), comme FastFonts
; Chaque ligne : « nom F L » = trames VERTB écoulées et différence de ligne vidéo (durée ≈ F × 313 + L lignes de 64 µs).
; Clean-room : structures publiques (NewScreen, NewWindow, Screen, Window), code auteur.

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     line(pc),a4
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                lea     dosbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                lea     gfxbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                lea     intbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                ; serveur VERTB de mesure
                lea     vbint(pc),a1
                move.b  #2,8(a1)
                move.b  #-100,9(a1)
                lea     vbname(pc),a0
                move.l  a0,10(a1)
                lea     vbcnt(pc),a0
                move.l  a0,14(a1)
                lea     vbcode(pc),a0
                move.l  a0,18(a1)
                moveq   #5,d0
                jsr     -168(a6)             ; AddIntServer(INTB_VERTB)

                move.l  intbase(pc),a6
                lea     ns(pc),a0
                jsr     -198(a6)             ; OpenScreen
                lea     scr(pc),a0
                move.l  d0,(a0)
                beq     .rem
                lea     nw1(pc),a0
                move.l  d0,30(a0)            ; nw_Screen
                lea     nw2(pc),a0
                move.l  d0,30(a0)
                ; --- écran, sans couche ---
                move.l  scr(pc),a0
                lea     84(a0),a2            ; Screen.RastPort
                lea     limscr(pc),a3
                lea     s_scr(pc),a0
                bsr     ps
                bsr     nl
                bsr     suite
                ; --- fenêtre recouverte ---
                move.l  intbase(pc),a6
                lea     nw1(pc),a0
                jsr     -204(a6)             ; OpenWindow
                lea     win1(pc),a0
                move.l  d0,(a0)
                beq     .cs
                lea     nw2(pc),a0
                jsr     -204(a6)
                lea     win2(pc),a0
                move.l  d0,(a0)
                beq     .cw1
                move.l  win1(pc),a0
                move.l  50(a0),a2            ; wd_RPort
                lea     limwin(pc),a3
                lea     s_win(pc),a0
                bsr     ps
                bsr     nl
                bsr     suite
                move.l  intbase(pc),a6
                move.l  win2(pc),a0
                jsr     -72(a6)              ; CloseWindow
.cw1:
                move.l  intbase(pc),a6
                move.l  win1(pc),a0
                jsr     -72(a6)
.cs:
                move.l  intbase(pc),a6
                move.l  scr(pc),a0
                jsr     -66(a6)              ; CloseScreen
                lea     t_end(pc),a0
                bsr     ps
                bsr     nl
.rem:
                move.l  4.w,a6
                lea     vbint(pc),a1
                moveq   #5,d0
                jsr     -174(a6)             ; RemIntServer
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

vbcode:                                      ; serveur VERTB : a1 = &vbcnt
                addq.l  #1,(a1)
                moveq   #0,d0
                rts

; suite(a2 = RastPort, a3 = limites x0,y0,x1,y1) : les quatre mesures H V D R
suite:
                move.l  gfxbase(pc),a6
                move.l  a2,a1
                moveq   #3,d0
                jsr     -342(a6)             ; SetAPen
                ; H
                bsr     start
                moveq   #99,d7
                move.w  2(a3),d6
.h:
                move.l  a2,a1
                move.w  (a3),d0
                move.w  d6,d1
                jsr     -240(a6)             ; Move
                move.l  a2,a1
                move.w  4(a3),d0
                move.w  d6,d1
                jsr     -246(a6)             ; Draw
                addq.w  #1,d6
                dbra    d7,.h
                lea     s_h(pc),a0
                bsr     stopt
                ; V
                bsr     start
                moveq   #99,d7
                move.w  (a3),d6
.v:
                move.l  a2,a1
                move.w  d6,d0
                move.w  2(a3),d1
                jsr     -240(a6)
                move.l  a2,a1
                move.w  d6,d0
                move.w  6(a3),d1
                jsr     -246(a6)
                addq.w  #1,d6
                dbra    d7,.v
                lea     s_v(pc),a0
                bsr     stopt
                ; D
                bsr     start
                moveq   #49,d7
.d:
                move.l  a2,a1
                move.w  (a3),d0
                move.w  2(a3),d1
                jsr     -240(a6)
                move.l  a2,a1
                move.w  4(a3),d0
                move.w  6(a3),d1
                jsr     -246(a6)
                dbra    d7,.d
                lea     s_d(pc),a0
                bsr     stopt
                ; R
                bsr     start
                moveq   #9,d7
.r:
                move.l  a2,a1
                moveq   #1,d0
                and.w   d7,d0
                addq.w  #1,d0
                jsr     -342(a6)             ; SetAPen 1 / 2 en alternance
                move.l  a2,a1
                movem.w (a3),d0-d3
                jsr     -306(a6)             ; RectFill
                dbra    d7,.r
                lea     s_r(pc),a0
                bsr     stopt
                ; P : un seul RectFill de même taille avec un motif de 2 lignes (SetAfPt), comme les barres des fenêtres
                lea     pat2(pc),a0
                move.l  a0,8(a2)             ; rp_AreaPtrn
                move.b  #1,29(a2)            ; rp_AreaPtSz
                bsr     start
                moveq   #0,d7
.p:
                move.l  a2,a1
                moveq   #1,d0
                and.w   d7,d0
                addq.w  #1,d0
                jsr     -342(a6)
                move.l  a2,a1
                movem.w (a3),d0-d3
                jsr     -306(a6)
                dbra    d7,.p
                lea     s_p(pc),a0
                bsr     stopt
                clr.l   8(a2)
                clr.b   29(a2)
                ; X1..X4 : 20 lignes de 70 caractères à l'abscisse x0+1 (non alignée) : JAM2, JAM1, COMPLEMENT, gras
                moveq   #1,d4                ; JAM2
                lea     s_x1(pc),a0
                bsr     txt
                moveq   #0,d4                ; JAM1
                lea     s_x2(pc),a0
                bsr     txt
                moveq   #2,d4                ; COMPLEMENT
                lea     s_x3(pc),a0
                bsr     txt
                move.b  #2,56(a2)            ; rp_AlgoStyle = FSF_BOLD
                moveq   #0,d4
                lea     s_x4(pc),a0
                bsr     txt
                clr.b   56(a2)
                ; B : 20 BltTemplate de 560 x 8 pixels en JAM1 (rendu de FastFonts)
                move.l  a2,a1
                moveq   #0,d0
                jsr     -354(a6)
                bsr     start
                moveq   #19,d7
                move.w  2(a3),d6
.b:
                lea     msg(pc),a0
                moveq   #0,d0
                moveq   #MSGLEN,d1
                move.l  a2,a1
                move.w  (a3),d2
                addq.w  #1,d2
                move.w  d6,d3
                move.w  #MSGLEN*8,d4
                cmp.w   #400,4(a3)
                bhi.s   .bw
                move.w  #45*8,d4
.bw:
                moveq   #8,d5
                jsr     -36(a6)              ; BltTemplate (octets du message comme gabarit)
                addq.w  #7,d6
                dbra    d7,.b
                lea     s_b(pc),a0
                bsr     stopt
                rts
; txt(a2 = RastPort, a3 = limites, d4 = mode, a0 = étiquette) : chronomètre 20 Text de 70 caractères
txt:
                move.l  a0,-(sp)
                move.l  a2,a1
                move.l  d4,d0
                jsr     -354(a6)             ; SetDrMd
                move.l  a2,a1
                moveq   #2,d0
                jsr     -348(a6)             ; SetBPen
                bsr     start
                moveq   #19,d7
                move.w  2(a3),d6
                addq.w  #8,d6
.l:
                move.l  a2,a1
                move.w  (a3),d0
                addq.w  #1,d0
                move.w  d6,d1
                jsr     -240(a6)             ; Move
                move.l  a2,a1
                lea     msg(pc),a0
                moveq   #MSGLEN,d0
                cmp.w   #400,4(a3)           ; dans la fenêtre : 45 caractères (390 pixels)
                bhi.s   .w
                moveq   #45,d0
.w:
                jsr     -60(a6)              ; Text
                addq.w  #7,d6
                dbra    d7,.l
                move.l  (sp)+,a0
                bsr     stopt
                move.l  a2,a1
                moveq   #0,d0
                jmp     -354(a6)

; start : mémorise l'instant ; stop(a0 = étiquette) : écrit « étiquette F L »
start:
                bsr.s   now
                movem.l d0-d1,t0
                rts
stopt:
                bsr     ps
                bsr.s   now
                sub.l   t0(pc),d0
                sub.l   t0+4(pc),d1
                bsr     ph
                move.l  d1,d0
                bsr     ph
                bra     nl
; now : d0 = trames, d1 = ligne verticale (0..312), relu jusqu'à cohérence
now:
                move.l  vbcnt(pc),d0
                move.l  $dff004,d1
                lsr.l   #8,d1
                and.l   #$1ff,d1
                cmp.l   vbcnt(pc),d0
                bne.s   now
                rts

ps:                                          ; copie la chaîne a0 en (a4)+
                move.b  (a0)+,(a4)+
                bne.s   ps
                subq.l  #1,a4
                rts
ph:                                          ; d0 en 8 chiffres + espace
                movem.l d1/d3,-(sp)
                moveq   #7,d3
.h:
                rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:
                move.b  d1,(a4)+
                dbra    d3,.h
                move.b  #' ',(a4)+
                movem.l (sp)+,d1/d3
                rts
nl:                                          ; termine la ligne et l'écrit sur Output()
                movem.l d0-d3/a0-a1/a6,-(sp)
                move.b  #10,(a4)+
                lea     line(pc),a0
                move.l  a4,d3
                sub.l   a0,d3
                move.l  a0,d2
                move.l  dosbase(pc),a6
                jsr     -60(a6)              ; Output
                move.l  d0,d1
                jsr     -48(a6)              ; Write
                lea     line(pc),a4
                movem.l (sp)+,d0-d3/a0-a1/a6
                rts

dosname:        dc.b    "dos.library",0
gfxname:        dc.b    "graphics.library",0
intname:        dc.b    "intuition.library",0
vbname:         dc.b    "drawperf-vb",0
s_scr:          dc.b    "ECRAN",0
s_win:          dc.b    "FENETRE",0
s_h:            dc.b    "H ",0
s_v:            dc.b    "V ",0
s_d:            dc.b    "D ",0
s_r:            dc.b    "R ",0
s_p:            dc.b    "P ",0
s_x1:           dc.b    "X1 ",0
s_x2:           dc.b    "X2 ",0
s_x3:           dc.b    "X3 ",0
s_x4:           dc.b    "X4 ",0
s_b:            dc.b    "B ",0
msg:            dc.b    "The quick brown fox jumps over the lazy dog 0123456789 ABCDEFGHIJKLMNO"
MSGLEN          EQU *-msg
t_end:          dc.b    "END",0
                even
limscr:         dc.w    10,10,629,189
pat2:           dc.w    $aaaa,$5555
limwin:         dc.w    5,5,394,144
ns:             dc.w    0,0,640,200,2        ; NewScreen : Left Top Width Height Depth
                dc.b    0,1                  ; DetailPen BlockPen
                dc.w    $8000,$000f          ; HIRES, CUSTOMSCREEN
                dc.l    0,0,0,0              ; Font DefaultTitle Gadgets CustomBitMap
nw1:            dc.w    100,20,400,150       ; NewWindow : Left Top Width Height
                dc.b    0,1
                dc.l    0,$0800              ; IDCMP, BORDERLESS
                dc.l    0,0,0,0,0            ; FirstGadget CheckMark Title Screen BitMap
                dc.w    0,0,0,0,$000f        ; Min/Max, CUSTOMSCREEN
nw2:            dc.w    420,110,120,60
                dc.b    0,1
                dc.l    0,$0800
                dc.l    0,0,0,0,0
                dc.w    0,0,0,0,$000f
vbint:          ds.b    22
                even
t0:             ds.l    2
vbcnt:          dc.l    0
dosbase:        dc.l    0
gfxbase:        dc.l    0
intbase:        dc.l    0
scr:            dc.l    0
win1:           dc.l    0
win2:           dc.l    0
line:           ds.b    200
