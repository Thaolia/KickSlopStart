; tests/menucat.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Ouvre une fenêtre sur l'écran Workbench avec un menu « Projet » dont les éléments ont des raccourcis (COMMSEQ) :
; en dérouler le menu (bouton droit) montre le symbole de la touche Amiga (le chat de KickSlopStart) devant chaque
; lettre. Attend ensuite indéfiniment (CLOSEWINDOW non géré : sonde visuelle).
; Assemblage : vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/menucat tests/menucat.s
; Code auteur ; structures publiques (intuition/intuition.h).

                section code,code
_start:
                move.l  4.w,a6
                lea     intname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                move.l  d0,a5
                tst.l   d0
                beq.s   .out
                lea     newwin(pc),a0
                move.l  a5,a6
                jsr     -204(a6)             ; OpenWindow
                tst.l   d0
                beq.s   .out
                move.l  d0,a0
                lea     menu(pc),a1
                jsr     -264(a6)             ; SetMenuStrip
                move.l  4.w,a6
.wait:
                moveq   #0,d0
                jsr     -318(a6)             ; Wait(0) : pour toujours
                bra.s   .wait
.out:
                moveq   #20,d0
                rts

newwin:         dc.w    40,30,300,80
                dc.b    0,1
                dc.l    $100                 ; IDCMP : MENUPICK
                dc.l    $100F                ; WINDOWSIZING|DRAG|DEPTH|CLOSE|ACTIVATE
                dc.l    0,0
                dc.l    wtitle
                dc.l    0,0
                dc.w    80,40,640,256
                dc.w    1                    ; WBENCHSCREEN
menu:           dc.l    0
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
                dc.w    $0056
                dc.l    0
                dc.l    it2,0
                dc.b    'S',0
                dc.l    0
                dc.w    0
item3:          dc.l    0
                dc.w    0,20,150,10
                dc.w    $0056
                dc.l    0
                dc.l    it3,0
                dc.b    'Q',0
                dc.l    0
                dc.w    0
it1:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t1,0
it2:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t2,0
it3:            dc.b    0,1,1,0
                dc.w    2,1
                dc.l    0,t3,0
intname:        dc.b    "intuition.library",0
wtitle:         dc.b    "Le chat de la touche Amiga",0
mname:          dc.b    "Projet",0
t1:             dc.b    "Ouvrir",0
t2:             dc.b    "Sauver",0
t3:             dc.b    "Quitter",0
                even
