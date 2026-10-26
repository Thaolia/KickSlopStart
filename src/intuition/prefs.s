; src/intuition/prefs.s — Preferences d'intuition : GetPrefs (-132), GetDefPrefs (-126), SetPrefs (-324).
;
; La copie courante (232 octets) vit dans IntuitionBase (IB_PREFS). Le reste d'intuition la lit à la volée :
; PointerTicks (pointer.s), DoubleClick (screens.s), décalage et image du pointeur, couleurs du Workbench à
; l'ouverture de son écran. SetPrefs la remplace puis applique police par défaut, couleurs, pointeur et décalage de
; la vue ; avec « inform », chaque fenêtre qui a demandé NEWPREFS en est avertie.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs intuition, preferences.h public, spec docs/analysis/intuition-prefs-v34.md.

                include "exec.i"
                include "intuition.i"
                include "graphics.i"

                xdef    intuition_GetPrefs
                xdef    intuition_GetDefPrefs
                xdef    intuition_SetPrefs
                xdef    it_prefsinit
                xref    ptr_image            ; pointer.s : image par défaut du pointeur (16 lignes, 2 plans)
                xref    it_ptrmoved          ; pointer.s : replace le sprite (décalage des Preferences compris)
                xref    wn_sendmsg           ; screens.s : IntuiMessage vers une fenêtre qui a demandé la classe

LVO_OPENFONT    EQU -72
LVO_SETRGB4     EQU -288

; GetPrefs(buffer a0, taille d0) -> d0 = buffer : les « taille » premiers octets de la copie courante.
intuition_GetPrefs:
        lea     IB_PREFS(a6),a1
        exg     a0,a1
        bra.s   pf_copy

; GetDefPrefs(buffer a0, taille d0) -> d0 = buffer : valeurs par défaut de la ROM, image du pointeur comprise ; la
; copie courante n'est pas touchée.
intuition_GetDefPrefs:
        move.l  a0,a1
        lea     pf_defaults(pc),a0
        move.l  d0,-(sp)
        bsr.s   pf_copy
        move.l  (sp)+,d1
        cmp.l   #PF_PTRMATRIX+72,d1
        blt.s   .gd_ret
        move.l  d0,a1
        lea     PF_PTRMATRIX+4(a1),a1   ; POS et CTL restent à 0, de même que la fin de liste
        lea     ptr_image,a0
        moveq   #PTR_ROWS*2-1,d1
.gd_img:
        move.w  (a0)+,(a1)+
        dbra    d1,.gd_img
.gd_ret:
        rts
PTR_ROWS        EQU 16

; pf_copy(source a0, destination a1, taille d0, a6 = IntuitionBase) -> d0 = destination. Taille signée : <= 0, rien ;
; bornée à 232. Si ViewInitX/Y sont dans la copie, ils prennent les décalages de la vue fixés à l'init.
pf_copy:
        move.l  a1,-(sp)
        tst.l   d0
        ble.s   .pc_ret
        cmp.l   #PF_SIZE,d0
        bls.s   .pc_n
        move.l  #PF_SIZE,d0
.pc_n:
        move.l  d0,d1
        subq.w  #1,d1
.pc_lp:
        move.b  (a0)+,(a1)+
        dbra    d1,.pc_lp
        cmp.w   #PF_VIEWEND,d0
        blo.s   .pc_ret
        move.l  (sp),a1
        move.w  IB_VINITX(a6),PF_VIEWINITX(a1)
        move.w  IB_VINITY(a6),PF_VIEWINITY(a1)
.pc_ret:
        move.l  (sp)+,d0
        rts

; SetPrefs(prefs a0, taille d0, inform d1) -> d0 = prefs. Copie bornée dans la copie courante, ext_size à 0, puis
; application complète (même si rien n'a été copié) ; inform : NEWPREFS aux fenêtres qui l'ont demandé.
intuition_SetPrefs:
        movem.l d2-d3/a0/a2-a3,-(sp)
        move.w  d1,d2
        lea     IB_PREFS(a6),a1
        bsr.s   pf_copy
        clr.b   IB_PREFS+PF_EXTSIZE(a6)
        bsr     pf_apply
        tst.w   d2
        beq.s   .sp_ret
        bsr     pf_inform
.sp_ret:
        movem.l (sp)+,d2-d3/a0/a2-a3
        move.l  a0,d0
        rts

; it_prefsinit(a2 = IntuitionBase) : décalages de la vue (standard PAL si InitView ne les a pas posés), copie
; courante = valeurs par défaut. Appelé avant le pointeur, qui y prend son image. Préserve d2-d7/a2-a6.
it_prefsinit:
        move.l  a6,-(sp)
        move.l  a2,a6
        move.w  IB_VIEWLORD+v_DxOffset(a6),d0
        bne.s   .pi_x
        move.w  #PF_STDX,d0
        move.w  d0,IB_VIEWLORD+v_DxOffset(a6)
.pi_x:
        move.w  d0,IB_VINITX(a6)
        move.w  IB_VIEWLORD+v_DyOffset(a6),d0
        bne.s   .pi_y
        move.w  #PF_STDY,d0
        move.w  d0,IB_VIEWLORD+v_DyOffset(a6)
.pi_y:
        move.w  d0,IB_VINITY(a6)
        lea     IB_PREFS(a6),a0
        move.l  #PF_SIZE,d0
        bsr     intuition_GetDefPrefs
        bsr.s   pf_tattr
        move.l  (sp)+,a6
        rts
PF_STDX         EQU $81              ; début de la fenêtre d'affichage PAL standard (DIWSTRT $2C81)
PF_STDY         EQU $2C

; pf_tattr(a6 = IntuitionBase) -> a0 = TextAttr de la police par défaut : topaz 8 si FontHeight = 8, topaz 9 sinon.
pf_tattr:
        lea     IB_TATTR(a6),a0
        lea     pf_topaz(pc),a1
        move.l  a1,ta_Name(a0)
        moveq   #9,d0
        cmp.b   #8,IB_PREFS+PF_FONTHEIGHT(a6)
        bne.s   .ta_h
        moveq   #8,d0
.ta_h:
        move.w  d0,ta_YSize(a0)
        clr.w   ta_Style(a0)         ; Style et Flags
        rts

; pf_apply(a6 = IntuitionBase) : police par défaut, écran Workbench (police, couleurs), décalage de la vue,
; pointeur (image et décalage), répétition des touches (input.device). Clobbe d0-d3/a0-a3.
pf_apply:
        move.l  a6,a3
        move.l  IB_GFXBASE(a3),a6
        bsr     pf_tattr_a3
        jsr     LVO_OPENFONT(a6)
        tst.l   d0
        beq.s   .pa_view
        move.l  d0,gb_DefaultFont(a6)
        move.l  IB_WBSCREEN(a3),d1
        beq.s   .pa_view
        move.l  d1,a2
        lea     IB_TATTR(a3),a0
        move.l  a0,SC_FONT(a2)
        move.l  d0,a0
        lea     SC_RASTPORT(a2),a1
        jsr     LVO_SETFONT(a6)
.pa_view:
        move.b  IB_PREFS+PF_VIEWXOFF(a3),d0
        ext.w   d0
        add.w   IB_VINITX(a3),d0
        move.w  d0,IB_VIEWLORD+v_DxOffset(a3)
        move.b  IB_PREFS+PF_VIEWYOFF(a3),d0
        ext.w   d0
        add.w   IB_VINITY(a3),d0
        move.w  d0,IB_VIEWLORD+v_DyOffset(a3)
        move.l  IB_WBSCREEN(a3),d0
        beq.s   .pa_ptr
        move.l  d0,a2
        lea     IB_PREFS+PF_COLOR0(a3),a0
        moveq   #0,d2
        bsr     pf_rgb4
        lea     IB_PREFS+PF_COLOR17(a3),a0
        moveq   #17,d2
        bsr     pf_rgb4
.pa_ptr:
        move.l  IB_PTRDATA(a3),d0
        beq.s   .pa_ret
        move.l  d0,a1
        addq.l  #4,a1                ; POS et CTL du sprite affiché restent ceux de MoveSprite
        lea     IB_PREFS+PF_PTRMATRIX+4(a3),a0
        moveq   #PTR_ROWS*2-1,d0
.pa_img:
        move.w  (a0)+,(a1)+
        dbra    d0,.pa_img
        jsr     it_ptrmoved
.pa_ret:
        bsr.s   pf_keyrpt
        move.l  a3,a6
        rts

; pf_keyrpt(a3 = IntuitionBase) : KeyRptDelay -> IND_SETTHRESH, KeyRptSpeed -> IND_SETPERIOD (spec intuition-prefs-v34
; §3.3), si input.device est là. Clobbe d0-d1/a0-a2/a6.
pf_keyrpt:
        move.l  ($4).w,a6
        lea     EB_DEVICELIST(a6),a0
        lea     pf_inputname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .kr_ret
        move.l  d0,a6
        lea     -TR_SIZE(sp),sp
        move.l  sp,a2
        move.l  a6,IO_DEVICE(a2)
        move.w  #IND_SETTHRESH,IO_COMMAND(a2)
        move.l  IB_PREFS+PF_KEYRPTDELAY(a3),TV_SECS(a2)
        move.l  IB_PREFS+PF_KEYRPTDELAY+4(a3),TV_MICRO(a2)
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        move.w  #IND_SETPERIOD,IO_COMMAND(a2)
        move.l  IB_PREFS+PF_KEYRPTSPEED(a3),TV_SECS(a2)
        move.l  IB_PREFS+PF_KEYRPTSPEED+4(a3),TV_MICRO(a2)
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        lea     TR_SIZE(sp),sp
.kr_ret:
        rts
pf_inputname:
        dc.b    "input.device",0
        EVEN

pf_tattr_a3:
        exg     a3,a6
        bsr     pf_tattr
        exg     a3,a6
        rts

; pf_rgb4(couleurs a0, premier registre d2, écran a2, a6 = GfxBase) : SetRGB4 de 4 couleurs (0..3) ou 3 (17..19)
; sur le ViewPort de l'écran.
pf_rgb4:
        move.l  a0,-(sp)
        moveq   #3,d3
        tst.w   d2
        beq.s   .rg_lp
        moveq   #2,d3
.rg_lp:
        move.l  (sp),a1
        move.w  (a1)+,d1
        move.l  a1,(sp)
        movem.l d2-d3,-(sp)
        move.w  d2,d0
        move.w  d1,d3                ; b
        move.w  d1,d2
        lsr.w   #4,d2                ; g
        lsr.w   #8,d1                ; r
        lea     SC_VIEWPORT(a2),a0
        jsr     LVO_SETRGB4(a6)
        movem.l (sp)+,d2-d3
        addq.w  #1,d2
        dbra    d3,.rg_lp
        addq.l  #4,sp
        rts

; pf_inform(a6 = IntuitionBase) : NEWPREFS à chaque fenêtre de chaque écran qui l'a demandé. Sous Forbid : la
; tâche d'entrée puise dans les mêmes réserves de messages. Clobbe d0-d3/a0-a3.
pf_inform:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  (sp),a0
        move.l  IB_FIRSTSCREEN(a0),a2
.pf_scr:
        move.l  a2,d0
        beq.s   .pf_end
        move.l  SC_FIRSTWINDOW(a2),a3
.pf_win:
        move.l  a3,d0
        beq.s   .pf_nscr
        move.l  #NEWPREFS,d0
        moveq   #0,d1
        moveq   #0,d2
        moveq   #0,d3
        movem.l d6/a6,-(sp)
        jsr     wn_sendmsg
        movem.l (sp)+,d6/a6
        move.l  WD_NEXTWINDOW(a3),a3
        bra.s   .pf_win
.pf_nscr:
        move.l  SC_NEXTSCREEN(a2),a2
        bra.s   .pf_scr
.pf_end:
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
        rts

pf_topaz:
        dc.b    "topaz.font",0
        even

; Preferences par défaut (mise en page preferences.h V34, 232 octets ; valeurs de la spec intuition-prefs-v34 §4.3,
; sauf les couleurs, qui sont celles du thème du projet, et le décalage du pointeur, nul pour notre image).
pf_defaults:
        dc.b    9,0                      ; FontHeight (topaz 9), PrinterPort = PARALLEL_PRINTER
        dc.w    5                        ; BaudRate = BAUD_9600
        dc.l    0,100000                 ; KeyRptSpeed
        dc.l    0,800000                 ; KeyRptDelay
        dc.l    1,500000                 ; DoubleClick
        dcb.w   36,0                     ; PointerMatrix (image remplie par GetDefPrefs)
        dc.b    0,0                      ; XOffset, YOffset
        dc.w    $0E44,$0000,$0EEC        ; color17..19 (pointeur)
        dc.w    2                        ; PointerTicks
        dc.w    SC_BGCOLOR,$0FFF,$0000,$0F80 ; color0..3 (Workbench)
        dc.b    0,0                      ; ViewXOffset, ViewYOffset
        dc.w    0,0                      ; ViewInitX, ViewInitY (remplacés à la copie)
        dc.w    0                        ; EnableCLI
        dc.w    7                        ; PrinterType
        dc.b    "generic"                ; PrinterFilename[30]
        dcb.b   30-7,0
        dc.w    0,0,0,5,75,0,0,1,2,$20,66,0 ; PrintPitch .. PaperType
        dc.b    0,0,0,0                  ; SerRWBits, SerStopBuf, SerParShk, LaceWB
        dcb.b   30,0                     ; WorkName
        dc.b    0,0                      ; RowSizeChange, ColumnSizeChange
        dc.w    0,0,0                    ; PrintFlags, PrintMaxWidth, PrintMaxHeight
        dc.b    0,0                      ; PrintDensity, PrintXOffset
        dc.w    0,0                      ; wb_Width, wb_Height
        dc.b    0,0                      ; wb_Depth, ext_size
pf_defaults_end:
        even
        ifne    pf_defaults_end-pf_defaults-PF_SIZE
        fail    "Preferences : taille différente de 232 octets"
        endc
