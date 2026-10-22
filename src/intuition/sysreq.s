; src/intuition/sysreq.s — intuition.library : AutoRequest, le requester système à deux réponses. Une fenêtre
; « System Request » s'ouvre sur l'écran de la fenêtre donnée (à défaut l'écran Workbench), le corps de texte y est
; écrit, les gadgets positif (en bas à gauche) et négatif (en bas à droite) sont dimensionnés sur leur texte.
; Piste IMPLÉMENTATION (« clean ») : AutoDoc intuition AutoRequest + structures publiques. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xdef    intuition_AutoRequest
                xref    intuition_OpenWindow
                xref    intuition_CloseWindow
                xref    intuition_PrintIText
                xref    intuition_IntuiTextLength

; bloc alloué : 2 gadgets, 2 bordures suivies chacune de leurs 5 points, la NewWindow
SR_GADP         EQU 0
SR_GADN         EQU SR_GADP+GG_SIZEOF
SR_BRDSZ        EQU 16               ; struct Border
SR_BRDP         EQU SR_GADN+GG_SIZEOF
SR_BRDN         EQU SR_BRDP+SR_BRDSZ+20
SR_NW           EQU SR_BRDN+SR_BRDSZ+20
SR_NWSIZE       EQU 48               ; struct NewWindow
SR_SIZE         EQU SR_NW+SR_NWSIZE
SR_MARGIN       EQU 6                ; écart des gadgets au bord de la fenêtre

; AutoRequest(fenêtre a0, corps a1, positif a2, négatif a3, drapeauxPos d0, drapeauxNég d1, largeur d2, hauteur d3)
; -> d0 = TRUE (gadget positif ou événement IDCMP de drapeauxPos) / FALSE (négatif, drapeauxNég, ou échec). Sans
; texte positif, seul le gadget négatif existe. Appelé depuis un process ou une tâche : le port IDCMP signale l'appelant.
intuition_AutoRequest:
        movem.l d2-d7/a2-a5,-(sp)
        move.l  a6,a5                ; a5 = IntuitionBase
        move.l  a0,d7                ; d7 = fenêtre de référence | 0
        move.l  a1,d6                ; d6 = corps
        move.l  d0,d4                ; d4 = drapeaux positifs
        move.l  d1,d5                ; d5 = drapeaux négatifs
        movem.w d2-d3,-(sp)          ; (sp) = largeur, 2(sp) = hauteur
        move.l  ($4).w,a6
        move.l  #SR_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .ar_nomem
        move.l  d0,a4                ; a4 = bloc
        move.l  a5,a6
        lea     SR_NW(a4),a0
        move.w  #30,NW_LEFTEDGE(a0)
        move.w  #20,NW_TOPEDGE(a0)
        move.w  (sp),NW_WIDTH(a0)
        move.w  2(sp),NW_HEIGHT(a0)
        move.b  #0,NW_DETAILPEN(a0)
        move.b  #1,NW_BLOCKPEN(a0)
        move.l  d4,d0
        or.l    d5,d0
        or.l    #GADGETUP,d0
        move.l  d0,NW_IDCMPFLAGS(a0)
        move.l  #WINDOWDRAG|WINDOWDEPTH|ACTIVATE,NW_FLAGS(a0)
        lea     sr_title(pc),a1
        move.l  a1,NW_TITLE(a0)
        move.w  #WBENCHSCREEN,NW_TYPE(a0)
        tst.l   d7
        beq.s   .ar_scr
        move.l  d7,a1
        move.l  WD_WSCREEN(a1),NW_SCREEN(a0)
        move.w  #CUSTOMSCREEN,NW_TYPE(a0)
.ar_scr:
        ; gadget négatif (toujours), en bas à droite ; gadget positif s'il a un texte, en bas à gauche
        lea     SR_GADN(a4),a0
        lea     SR_BRDN(a4),a1
        move.l  a3,d0
        bsr     sr_mkgad
        move.w  #GRELBOTTOM|GRELRIGHT,GG_FLAGS(a0)
        move.w  GG_WIDTH(a0),d0
        add.w   #SR_MARGIN+4,d0
        neg.w   d0
        move.w  d0,GG_LEFTEDGE(a0)
        clr.w   GG_GADGETID(a0)      ; ID 0 = négatif
        move.l  a0,SR_NW+NW_FIRSTGADGET(a4)
        move.l  a2,d0
        beq.s   .ar_open
        move.l  a0,-(sp)
        lea     SR_GADP(a4),a0
        lea     SR_BRDP(a4),a1
        bsr     sr_mkgad
        move.w  #GRELBOTTOM,GG_FLAGS(a0)
        move.w  #SR_MARGIN+2,GG_LEFTEDGE(a0)
        move.w  #1,GG_GADGETID(a0)   ; ID 1 = positif
        move.l  (sp)+,GG_NEXTGADGET(a0)
        move.l  a0,SR_NW+NW_FIRSTGADGET(a4)
.ar_open:
        lea     SR_NW(a4),a0
        jsr     intuition_OpenWindow
        tst.l   d0
        beq     .ar_nowin
        move.l  d0,a3                ; a3 = fenêtre du requester
        move.l  d6,d0
        beq.s   .ar_wait
        move.l  WD_RPORT(a3),a0
        move.l  d0,a1
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        moveq   #0,d1
        move.b  WD_BORDERTOP(a3),d1
        jsr     intuition_PrintIText
.ar_wait:
        move.l  ($4).w,a6
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_WAITPORT(a6)
.ar_get:
        move.l  WD_USERPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .ar_wait
        move.l  d0,a1
        move.l  IM_CLASS(a1),d0
        moveq   #-1,d2               ; d2 = réponse (-1 : pas encore)
        cmp.l   #GADGETUP,d0
        bne.s   .ar_flags
        move.l  IM_IADDRESS(a1),a0
        moveq   #0,d2
        tst.w   GG_GADGETID(a0)
        beq.s   .ar_reply
        moveq   #1,d2
        bra.s   .ar_reply
.ar_flags:
        move.l  d0,d1
        and.l   d4,d1
        beq.s   .ar_neg
        moveq   #1,d2
        bra.s   .ar_reply
.ar_neg:
        and.l   d5,d0
        beq.s   .ar_reply
        moveq   #0,d2
.ar_reply:
        jsr     LVO_REPLYMSG(a6)
        tst.l   d2
        bmi.s   .ar_get
        move.l  a3,a0
        move.l  a5,a6
        jsr     intuition_CloseWindow
        move.l  d2,d7
        bra.s   .ar_free
.ar_nowin:
        moveq   #0,d7
.ar_free:
        move.l  ($4).w,a6
        move.l  a4,a1
        move.l  #SR_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d7,d0
        bra.s   .ar_ret
.ar_nomem:
        moveq   #0,d0
.ar_ret:
        addq.l  #4,sp
        movem.l (sp)+,d2-d7/a2-a5
        rts

; sr_mkgad(a0 = gadget, a1 = sa Border (ses 5 points la suivent), d0 = IntuiText, a6 = IntuitionBase) :
; bouton RELVERIFY dimensionné sur son texte (marges du texte reportées de l'autre côté), cadre de 5 points autour,
; placé à SR_MARGIN du bas de la fenêtre. Préserve a0/a2-a6.
sr_mkgad:
        movem.l d2-d3/a0-a2,-(sp)
        move.l  d0,a2                ; a2 = texte
        move.w  #BOOLGADGET,GG_GADGETTYPE(a0)
        move.w  #RELVERIFY,GG_ACTIVATION(a0)
        move.l  a2,GG_GADGETTEXT(a0)
        move.l  a1,GG_GADGETRENDER(a0)
        moveq   #16,d2               ; largeur sans texte
        moveq   #12,d3               ; hauteur
        move.l  a2,d0
        beq.s   .mg_size
        move.l  a2,a0
        jsr     intuition_IntuiTextLength
        move.w  IT_LEFTEDGE(a2),d2
        add.w   d2,d2
        add.w   d0,d2                ; largeur = texte + 2 × marge gauche
        moveq   #8,d3
        add.w   IT_TOPEDGE(a2),d3
        add.w   IT_TOPEDGE(a2),d3    ; hauteur = police + 2 × marge haute
.mg_size:
        movem.l (sp),d0-d1/a0-a1     ; (d0/d1 : place de d2/d3 sauvés, ignorés)
        move.w  d2,GG_WIDTH(a0)
        move.w  d3,GG_HEIGHT(a0)
        move.w  d3,d0
        add.w   #SR_MARGIN,d0
        neg.w   d0
        move.w  d0,GG_TOPEDGE(a0)
        move.w  #-1,BD_LEFTEDGE(a1)  ; cadre d'un pixel autour du gadget
        move.w  #-1,BD_TOPEDGE(a1)
        move.b  #1,BD_FRONTPEN(a1)
        move.b  #JAM1,BD_DRAWMODE(a1)
        move.b  #5,BD_COUNT(a1)
        lea     SR_BRDSZ(a1),a2      ; points, juste après la Border
        move.l  a2,BD_XY(a1)
        addq.w  #1,d2                ; (0,0) (w+1,0) (w+1,h+1) (0,h+1) (0,0)
        addq.w  #1,d3
        clr.l   (a2)+
        move.w  d2,(a2)+
        clr.w   (a2)+
        move.w  d2,(a2)+
        move.w  d3,(a2)+
        clr.w   (a2)+
        move.w  d3,(a2)+
        clr.l   (a2)
        movem.l (sp)+,d2-d3/a0-a2
        rts

sr_title:
        dc.b    "System Request",0
        even
