; src/dos/workbench.s — résident workbench.task : le process que lance c:LoadWB.
; Spec : docs/analysis/workbench-task-v34.md (relue clean-room). Contrat avec LoadWB :
;   - ROMTag NT_TASK sans drapeau de classe : présent dans ResModules (FindResident) mais jamais initialisé au boot ;
;   - LoadWB fait CreateProc(..., seglist = BPTR(ROMTag+42), ...) : la troncature donne un faux segment à ROMTag+40
;     (lien) et un point d'entrée à ROMTag+44 (ROMTag aligné sur 4) ;
;   - le process doit répondre au message de LoadWB (28 octets : +$14 = BPTR du chemin, +$18 = drapeau -debug) dès son
;     initialisation, sinon LoadWB reste bloqué ; il se nomme « Workbench » (LoadWB le retrouve par FindTask) et
;     tourne en priorité 1.
; Portée : bureau MINIMAL — écran Workbench, fenêtre de fond (BACKDROP) avec l'icône du disque de boot (SYS:Disk.info
; lue par l'icon.library du disque) et le nom du volume, redessinée au REFRESHWINDOW. Ni menus, ni double-clic, ni
; tiroirs (layers.library manque). Le process vit indéfiniment comme le vrai et répond à tout message reçu sur son
; port public « Workbench ».
; Piste IMPLÉMENTATION (« clean ») : spec ci-dessus + AutoDocs exec/dos/workbench (WBStartup). AUCUNE lecture ROM.

                include "exec.i"
                include "dospkt.i"
                include "intuition.i"
                include "graphics.i"

LVO_DRAWIMAGE   EQU -114             ; intuition.library (intuition_lib.fd)
ICON_LVO_GETDISKOBJECT EQU -78       ; icon.library (icon_lib.fd)
NW_SIZEOF       EQU 48               ; struct NewWindow
DO_GADGET       EQU 4                ; struct DiskObject (workbench/workbench.h) : gadget embarqué
DO_CURRENTX     EQU 58
DO_CURRENTY     EQU 62
GG_GADGETRENDER EQU 18               ; struct Gadget : image
NO_ICON_POSITION EQU $80000000
DO_DRAWERDATA   EQU 66               ; struct DrawerData : dd_NewWindow en tête
LVO_DOUBLECLICK EQU -102

WB_MSGPATH      EQU $14              ; message de LoadWB : BPTR du chemin (-> cli_CommandDir)

                cnop    0,4
wb_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    wb_romtag            ; RT_MATCHTAG = self
        dc.l    wb_end               ; RT_ENDSKIP
        dc.b    0,34,NT_TASK,0       ; RT_FLAGS (aucune classe : lancé par LoadWB), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    wb_taskname          ; RT_NAME
        dc.l    wb_idstring          ; RT_IDSTRING
        dc.l    wb_entry             ; RT_INIT
        dcb.b   40-26,0              ; jusqu'au faux segment
        dc.l    0                    ; ROMTag+40 : lien du faux segment (fin de chaîne)
wb_entry:                            ; ROMTag+44 : point d'entrée du process créé par LoadWB
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a4   ; a4 = ce process
        lea     wb_procname(pc),a0
        move.l  a0,LN_NAME(a4)
        move.l  a4,a1
        moveq   #1,d0
        jsr     LVO_SETTASKPRI(a6)
        moveq   #CLI_SIZEOF,d0       ; faux CLI : les outils lancés plus tard y trouvent le chemin de commandes
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a3                ; a3 = CLI | 0
        tst.l   d0
        beq.s   .we_nocli
        lsr.l   #2,d0
        move.l  d0,PR_CLI(a4)
.we_nocli:
        lea     PR_MSGPORT(a4),a0    ; message de démarrage de LoadWB
        jsr     LVO_WAITPORT(a6)
        lea     PR_MSGPORT(a4),a0
        jsr     LVO_GETMSG(a6)
        move.l  d0,a1
        move.l  a3,d1
        beq.s   .we_reply
        move.l  WB_MSGPATH(a1),CLI_COMMANDDIR(a3)
.we_reply:
        jsr     LVO_REPLYMSG(a6)     ; réponse immédiate : LoadWB continue
        move.l  #WBS_SIZE,d0         ; état du bureau
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .we_idle
        move.l  d0,a5                ; a5 = état
        bsr     wb_desktop           ; écran Workbench, fenêtre de fond, icône du disque
        moveq   #MP_SIZE,d0          ; port public « Workbench »
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .we_idle
        move.l  d0,a3                ; a3 = port
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        move.b  d0,MP_SIGBIT(a3)
        bmi     .we_idle
        move.l  a4,MP_SIGTASK(a3)
        move.b  #PA_SIGNAL,MP_FLAGS(a3)
        move.b  #NT_MSGPORT,LN_TYPE(a3)
        lea     wb_procname(pc),a0
        move.l  a0,LN_NAME(a3)
        move.l  a3,a1
        jsr     LVO_ADDPORT(a6)
.we_loop:                            ; attend le port public et les ports IDCMP (fond, fenêtre du disque)
        moveq   #0,d0
        move.b  MP_SIGBIT(a3),d1
        bset    d1,d0
        move.l  WBS_WIN(a5),a0
        bsr     wb_sigbit
        move.l  WBS_DWIN(a5),a0
        bsr     wb_sigbit
        jsr     LVO_WAIT(a6)
.we_drain:                           ; port public : répond à tout message (pas d'objets Workbench à gérer)
        move.l  a3,a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .we_idcmp
        move.l  d0,a1
        jsr     LVO_REPLYMSG(a6)
        bra.s   .we_drain
.we_idcmp:                           ; fenêtre de fond : REFRESHWINDOW (redessiner), boutons (sélection, double-clic)
        move.l  WBS_WIN(a5),a0
        bsr     wb_getmsg            ; d2 = classe, d3 = code, d4/d5 = souris, d6/d7 = secondes/micros | Z = 1
        beq.s   .we_dmsg
        cmp.l   #REFRESHWINDOW,d2
        bne.s   .we_bmb
        bsr     wb_drawicons
        bra.s   .we_idcmp
.we_bmb:
        cmp.l   #MOUSEBUTTONS,d2
        bne.s   .we_idcmp
        cmp.w   #SELECTDOWN,d3
        bne.s   .we_idcmp
        bsr     wb_click
        bra.s   .we_idcmp
.we_dmsg:                            ; fenêtre du disque : CLOSEWINDOW (fermer), REFRESHWINDOW (redessiner)
        move.l  WBS_DWIN(a5),a0
        bsr     wb_getmsg
        beq     .we_loop
        cmp.l   #CLOSEWINDOW,d2
        bne.s   .we_drf
        bsr     wb_closedrawer
        bra     .we_loop
.we_drf:
        cmp.l   #REFRESHWINDOW,d2
        bne.s   .we_dmsg
        bsr     wb_drawdrawer
        bra.s   .we_dmsg
.we_idle:                            ; sans port : attente sans fin (le process ne se termine pas, comme le vrai)
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .we_idle

; état du bureau
WBS_IBASE       EQU 0                ; IntuitionBase
WBS_GFXBASE     EQU 4
WBS_DOSBASE     EQU 8
WBS_ICONBASE    EQU 12
WBS_WIN         EQU 16               ; fenêtre de fond (BACKDROP) | 0
WBS_DOBJ        EQU 20               ; DiskObject du disque de boot (icon.library) | 0
WBS_NAME        EQU 24               ; nom du volume (chaîne C)
WBS_NAMEMAX     EQU 32
WBS_DWIN        EQU WBS_NAME+WBS_NAMEMAX ; fenêtre du disque (ouverte par double-clic) | 0
WBS_IX          EQU WBS_DWIN+4       ; position de l'icône du disque dans la fenêtre de fond
WBS_IY          EQU WBS_IX+2
WBS_SEL         EQU WBS_IY+2         ; BYTE : icône du disque sélectionnée
WBS_SHOWN       EQU WBS_SEL+1        ; BYTE : icône du disque dessinée (à l'écran ou dans la sauvegarde de sa couche)
WBS_LSEC        EQU WBS_SHOWN+1      ; horodatage du clic précédent (double-clic)
WBS_LMIC        EQU WBS_LSEC+4
WBS_NICON       EQU WBS_LMIC+4       ; icônes de la racine lues (fenêtre du disque)
WBS_ICONS       EQU WBS_NICON+4      ; WB_MAXICONS x DiskObject
WBS_INAMES      EQU WBS_ICONS+WB_MAXICONS*4 ; WB_MAXICONS x nom (WBS_NAMEMAX octets)
WBS_SIZE        EQU WBS_INAMES+WB_MAXICONS*WBS_NAMEMAX
WB_MAXICONS     EQU 16
WB_ICONGAP      EQU 20               ; marge droite de l'icône de disque (pas de position mémorisée)
WB_ICONTOP      EQU 6

; wb_desktop(a5 = état, a6 = SysBase) : ouvre l'écran Workbench, la fenêtre de fond (BACKDROP, sans bordure, sous la
; barre de l'écran, IDCMP REFRESHWINDOW), lit le nom du volume SYS: et l'icône SYS:Disk (icon.library du disque), puis
; dessine le bureau. Chaque étape est optionnelle (bibliothèque ou fichier absent : bureau plus pauvre).
; Préserve d2-d7/a2-a6.
wb_desktop:
        movem.l d2-d3/a2/a6,-(sp)
        lea     wb_intname(pc),a1
        bsr     wb_openlib
        move.l  d0,WBS_IBASE(a5)
        beq     .wd_ret
        lea     wb_gfxname(pc),a1
        bsr     wb_openlib
        move.l  d0,WBS_GFXBASE(a5)
        beq     .wd_ret
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_OPENWORKBENCH(a6)
        tst.l   d0
        beq     .wd_ret
        move.l  d0,a2                ; a2 = écran
        lea     -NW_SIZEOF(sp),sp    ; NewWindow de la fenêtre de fond
        move.l  sp,a0
        moveq   #NW_SIZEOF/2-1,d1
.wd_clr:
        clr.w   (a0)+
        dbra    d1,.wd_clr
        move.l  sp,a0
        moveq   #0,d1
        move.b  SC_BARHEIGHT(a2),d1
        addq.w  #1,d1
        move.w  d1,NW_TOPEDGE(a0)
        move.w  SC_WIDTH(a2),NW_WIDTH(a0)
        move.w  SC_HEIGHT(a2),d0
        sub.w   d1,d0
        move.w  d0,NW_HEIGHT(a0)
        move.w  #$FFFF,NW_DETAILPEN(a0)
        move.l  #REFRESHWINDOW|MOUSEBUTTONS,NW_IDCMPFLAGS(a0)
        move.l  #BACKDROP|BORDERLESS,NW_FLAGS(a0)
        move.w  #WBENCHSCREEN,NW_TYPE(a0)
        jsr     LVO_OPENWINDOW(a6)
        lea     NW_SIZEOF(sp),sp
        move.l  d0,WBS_WIN(a5)
        move.l  ($4).w,a6
        lea     wb_dosname(pc),a1    ; nom du volume : Examine de SYS:
        bsr     wb_openlib
        move.l  d0,WBS_DOSBASE(a5)
        beq.s   .wd_icon
        move.l  #FIB_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,d3                ; d3 = FIB | 0
        beq.s   .wd_icon
        move.l  WBS_DOSBASE(a5),a6
        move.l  #wb_sysname,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,a2                ; a2 = lock | 0
        tst.l   d0
        beq.s   .wd_nofib
        move.l  d0,d1
        move.l  d3,d2
        jsr     DOS_LVO_EXAMINE(a6)
        tst.l   d0
        beq.s   .wd_unlock
        move.l  d3,a0
        lea     FIB_FILENAME(a0),a0
        lea     WBS_NAME(a5),a1
        moveq   #WBS_NAMEMAX-2,d0
.wd_ncpy:
        move.b  (a0)+,(a1)+
        dbeq    d0,.wd_ncpy
        clr.b   (a1)
.wd_unlock:
        move.l  a2,d1
        jsr     DOS_LVO_UNLOCK(a6)
.wd_nofib:
        move.l  ($4).w,a6
        move.l  d3,a1
        move.l  #FIB_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.wd_icon:
        move.l  ($4).w,a6
        lea     wb_iconname(pc),a1   ; icône du disque : SYS:Disk.info
        bsr     wb_openlib
        move.l  d0,WBS_ICONBASE(a5)
        beq.s   .wd_draw
        move.l  d0,a6
        lea     wb_diskname(pc),a0
        jsr     ICON_LVO_GETDISKOBJECT(a6)
        move.l  d0,WBS_DOBJ(a5)
.wd_draw:
        bsr     wb_drawicons
.wd_ret:
        movem.l (sp)+,d2-d3/a2/a6
        rts

; wb_openlib(a1 = nom) -> d0 = base | 0 (OpenLibrary version 0 ; a6 = SysBase).
wb_openlib:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  (sp)+,a6
        rts

; wb_drawicons(a5 = état) : icône du disque de boot (image de son gadget) en haut à droite de la fenêtre de fond, nom
; du volume centré dessous (stylo 2, JAM1). Sautée si une fenêtre placée devant la recouvre (pas de layers : elle
; sera redessinée au REFRESHWINDOW). Préserve d2-d7/a2-a6.
wb_drawicons:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.l  WBS_WIN(a5),d0
        beq     .di_ret
        move.l  d0,a3                ; a3 = fenêtre
        move.l  WBS_DOBJ(a5),d0
        beq     .di_ret
        move.l  d0,a2                ; a2 = DiskObject
        move.w  DO_GADGET+GG_WIDTH(a2),d6   ; d6 = largeur, d7 = hauteur de l'icône
        move.w  DO_GADGET+GG_HEIGHT(a2),d7
        lea     WBS_NAME(a5),a0      ; position : celle de l'icône, sinon en haut à droite, nom compris
        moveq   #-1,d0
.di_nl:
        addq.w  #1,d0
        tst.b   (a0)+
        bne.s   .di_nl
        lsl.w   #3,d0                ; largeur du nom
        sub.w   d6,d0
        bpl.s   .di_wide
        moveq   #0,d0
.di_wide:
        lsr.w   #1,d0                ; débord du nom de chaque côté de l'icône
        move.w  WD_WIDTH(a3),d4
        sub.w   d6,d4
        sub.w   d0,d4
        sub.w   #WB_ICONGAP,d4
        moveq   #WB_ICONTOP,d5
        cmp.l   #NO_ICON_POSITION,DO_CURRENTX(a2)
        beq.s   .di_pos
        move.w  DO_CURRENTX+2(a2),d4
        move.w  DO_CURRENTY+2(a2),d5
.di_pos:
        move.w  d4,WBS_IX(a5)
        move.w  d5,WBS_IY(a5)
        clr.b   WBS_SHOWN(a5)
        move.l  WBS_IBASE(a5),a6     ; image (cachée par une fenêtre : layers la range dans la sauvegarde)
        move.l  WD_RPORT(a3),a0
        move.l  DO_GADGET+GG_GADGETRENDER(a2),a1
        move.w  d4,d0
        move.w  d5,d1
        jsr     LVO_DRAWIMAGE(a6)
        lea     WBS_NAME(a5),a4      ; nom centré sous l'icône
        move.l  a4,a0
        moveq   #-1,d2
.di_len:
        addq.w  #1,d2
        tst.b   (a0)+
        bne.s   .di_len
        tst.w   d2
        beq.s   .di_ret
        move.l  WBS_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #2,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.w  d6,d0
        lsr.w   #1,d0
        add.w   d4,d0
        move.w  d2,d1
        lsl.w   #2,d1                ; demi-largeur du texte
        sub.w   d1,d0
        move.w  d5,d1
        add.w   d7,d1
        add.w   #1+GFX_FONTBASE,d1
        jsr     LVO_MOVE(a6)
        move.l  a4,a0
        move.w  d2,d0
        jsr     LVO_TEXT(a6)
        st      WBS_SHOWN(a5)
        tst.b   WBS_SEL(a5)
        beq.s   .di_ret
        bsr     wb_highlight         ; sélectionnée : redessinée inversée
.di_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts

; wb_sigbit(a0 = fenêtre | 0, d0 = masque) -> d0 |= bit du port IDCMP de la fenêtre. Clobbe d1/a0.
wb_sigbit:
        move.l  a0,d1
        beq.s   .sb_ret
        move.l  WD_USERPORT(a0),d1
        beq.s   .sb_ret
        move.l  d1,a0
        move.b  MP_SIGBIT(a0),d1
        bset    d1,d0
.sb_ret:
        rts

; wb_getmsg(a0 = fenêtre | 0) -> Z = 1 si aucun message ; sinon d2 = classe, d3 = code, d4/d5 = souris, d6/d7 =
; secondes/micros, et le message est déjà répondu (il appartient à la fenêtre). a6 = SysBase. Clobbe d0/d1/a0/a1.
wb_getmsg:
        move.l  a0,d0
        beq.s   .gm_none
        move.l  WD_USERPORT(a0),d0
        beq.s   .gm_none
        move.l  d0,a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .gm_none
        move.l  d0,a1
        move.l  IM_CLASS(a1),d2
        move.w  IM_CODE(a1),d3
        move.w  IM_MOUSEX(a1),d4
        move.w  IM_MOUSEY(a1),d5
        move.l  IM_SECONDS(a1),d6
        move.l  IM_MICROS(a1),d7
        jsr     LVO_REPLYMSG(a6)
        moveq   #1,d0                ; Z = 0
        rts
.gm_none:
        moveq   #0,d0
        rts

; wb_click(d4/d5 = souris dans la fenêtre de fond, d6/d7 = horodatage) : sur l'icône du disque -> sélection, et
; double-clic (icône déjà sélectionnée) -> fenêtre du disque ; ailleurs -> désélection. Préserve d2-d7/a2-a6.
wb_click:
        movem.l d2-d7/a2/a6,-(sp)
        tst.b   WBS_SHOWN(a5)
        beq.s   .ck_out
        move.l  WBS_DOBJ(a5),a2
        move.w  d4,d0
        sub.w   WBS_IX(a5),d0
        bmi.s   .ck_out
        cmp.w   DO_GADGET+GG_WIDTH(a2),d0
        bge.s   .ck_out
        move.w  d5,d0
        sub.w   WBS_IY(a5),d0
        bmi.s   .ck_out
        cmp.w   DO_GADGET+GG_HEIGHT(a2),d0
        bge.s   .ck_out
        tst.b   WBS_SEL(a5)
        beq.s   .ck_select
        move.l  WBS_LSEC(a5),d0      ; déjà sélectionnée : double-clic ?
        move.l  WBS_LMIC(a5),d1
        move.l  d6,d2
        move.l  d7,d3
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_DOUBLECLICK(a6)
        tst.l   d0
        beq.s   .ck_stamp
        bsr     wb_opendrawer
        bra.s   .ck_stamp
.ck_select:
        st      WBS_SEL(a5)
        bsr     wb_highlight
.ck_stamp:
        move.l  d6,WBS_LSEC(a5)
        move.l  d7,WBS_LMIC(a5)
        bra.s   .ck_ret
.ck_out:
        tst.b   WBS_SEL(a5)
        beq.s   .ck_ret
        clr.b   WBS_SEL(a5)
        tst.b   WBS_SHOWN(a5)
        beq.s   .ck_ret
        bsr     wb_highlight         ; inversion de nouveau : rendu normal
.ck_ret:
        movem.l (sp)+,d2-d7/a2/a6
        rts

; wb_highlight(a5) : inverse (mode COMPLEMENT) le rectangle de l'icône du disque dans la fenêtre de fond.
; Préserve d2-d7/a2-a6.
wb_highlight:
        movem.l d2-d3/a2/a6,-(sp)
        move.l  WBS_DOBJ(a5),a2
        move.l  WBS_GFXBASE(a5),a6
        move.l  WBS_WIN(a5),a1
        move.l  WD_RPORT(a1),a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        move.w  WBS_IX(a5),d0
        move.w  WBS_IY(a5),d1
        move.w  d0,d2
        add.w   DO_GADGET+GG_WIDTH(a2),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   DO_GADGET+GG_HEIGHT(a2),d3
        subq.w  #1,d3
        jsr     LVO_RECTFILL(a6)
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        movem.l (sp)+,d2-d3/a2/a6
        rts

; wb_opendrawer(a5) : ouvre la fenêtre du disque (géométrie de la DrawerData de Disk.info, titre = nom du volume,
; gadgets fermeture/déplacement/profondeur, IDCMP CLOSEWINDOW | REFRESHWINDOW), lit une fois les icônes de la racine
; puis les dessine. Déjà ouverte : rien. Préserve d2-d7/a2-a6.
wb_opendrawer:
        movem.l d2/a2/a6,-(sp)
        tst.l   WBS_DWIN(a5)
        bne     .od_ret
        lea     -NW_SIZEOF(sp),sp
        move.l  sp,a0
        moveq   #NW_SIZEOF/2-1,d1
.od_clr:
        clr.w   (a0)+
        dbra    d1,.od_clr
        move.l  sp,a0
        move.l  #$000A0014,NW_LEFTEDGE(a0)   ; par défaut : 10,20 400x120
        move.l  #$01900078,NW_WIDTH(a0)
        move.l  WBS_DOBJ(a5),a2
        move.l  DO_DRAWERDATA(a2),d0
        beq.s   .od_geo
        move.l  d0,a1
        move.l  (a1)+,NW_LEFTEDGE(a0)        ; dd_NewWindow : LeftEdge, TopEdge, Width, Height
        move.l  (a1),NW_WIDTH(a0)
.od_geo:
        move.w  #$FFFF,NW_DETAILPEN(a0)
        move.l  #CLOSEWINDOW|REFRESHWINDOW,NW_IDCMPFLAGS(a0)
        move.l  #WINDOWDRAG|WINDOWDEPTH|WINDOWCLOSE,NW_FLAGS(a0)
        lea     WBS_NAME(a5),a1
        move.l  a1,NW_TITLE(a0)
        move.w  #WBENCHSCREEN,NW_TYPE(a0)
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_OPENWINDOW(a6)
        lea     NW_SIZEOF(sp),sp
        move.l  d0,WBS_DWIN(a5)
        beq.s   .od_ret
        tst.l   WBS_NICON(a5)
        bne.s   .od_draw
        bsr     wb_loadicons
.od_draw:
        bsr     wb_drawdrawer
.od_ret:
        movem.l (sp)+,d2/a2/a6
        rts

; wb_closedrawer(a5) : ferme la fenêtre du disque (les icônes lues restent en mémoire pour la prochaine ouverture).
; Préserve d2-d7/a2-a6.
wb_closedrawer:
        move.l  a6,-(sp)
        move.l  WBS_DWIN(a5),d0
        beq.s   .cd_ret
        clr.l   WBS_DWIN(a5)
        move.l  d0,a0
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_CLOSEWINDOW(a6)
.cd_ret:
        move.l  (sp)+,a6
        rts

; wb_loadicons(a5) : parcourt la racine de SYS: (Examine / ExNext) ; chaque « nom.info » (sauf Disk.info) donne une
; icône (GetDiskObject("SYS:nom")) et son nom, WB_MAXICONS au plus. Préserve d2-d7/a2-a6.
wb_loadicons:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.l  WBS_DOSBASE(a5),d0
        beq     .li_ret
        tst.l   WBS_ICONBASE(a5)
        beq     .li_ret
        move.l  ($4).w,a6
        move.l  #FIB_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,d6                ; d6 = FIB
        beq     .li_ret
        lea     -WB_PATHMAX(sp),sp   ; chemin « SYS:nom »
        move.l  WBS_DOSBASE(a5),a6
        move.l  #wb_sysname,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d7                ; d7 = lock
        beq     .li_free
        move.l  d7,d1
        move.l  d6,d2
        jsr     DOS_LVO_EXAMINE(a6)
        tst.l   d0
        beq     .li_unlock
.li_next:
        cmp.l   #WB_MAXICONS,WBS_NICON(a5)
        bhs     .li_unlock
        move.l  WBS_DOSBASE(a5),a6
        move.l  d7,d1
        move.l  d6,d2
        jsr     DOS_LVO_EXNEXT(a6)
        tst.l   d0
        beq     .li_unlock
        move.l  d6,a0
        lea     FIB_FILENAME(a0),a2  ; a2 = nom
        move.l  a2,a0
        moveq   #-1,d3
.li_len:
        addq.w  #1,d3
        tst.b   (a0)+
        bne.s   .li_len              ; d3 = longueur
        cmp.w   #5,d3
        bls.s   .li_next             ; trop court pour « x.info »
        cmp.w   #WBS_NAMEMAX+4,d3
        bhs.s   .li_next
        lea     -5(a2,d3.w),a0       ; suffixe « .info » (insensible à la casse)
        lea     wb_infosuffix(pc),a1
        moveq   #4,d0
.li_suf:
        move.b  (a0)+,d1
        cmp.b   #'A',d1
        blo.s   .li_sc
        cmp.b   #'Z',d1
        bhi.s   .li_sc
        add.b   #'a'-'A',d1
.li_sc:
        cmp.b   (a1)+,d1
        bne.s   .li_next
        dbra    d0,.li_suf
        subq.w  #5,d3                ; d3 = longueur du nom sans « .info »
        cmp.w   #4,d3                ; « Disk » : l'icône du disque lui-même
        bne.s   .li_keep
        lea     wb_diskname+4(pc),a0
        move.l  a2,a1
        moveq   #3,d0
.li_dk:
        move.b  (a1)+,d1
        and.b   #$DF,d1
        move.b  (a0)+,d2
        and.b   #$DF,d2
        cmp.b   d2,d1
        bne.s   .li_keep
        dbra    d0,.li_dk
        bra     .li_next
.li_keep:
        move.l  WBS_NICON(a5),d4     ; nom -> WBS_INAMES[n]
        move.w  d4,d0
        mulu    #WBS_NAMEMAX,d0
        lea     WBS_INAMES(a5),a4
        add.l   d0,a4
        move.l  a2,a0
        move.l  a4,a1
        move.w  d3,d0
        subq.w  #1,d0
.li_ncp:
        move.b  (a0)+,(a1)+
        dbra    d0,.li_ncp
        clr.b   (a1)
        move.l  sp,a1                ; chemin « SYS:nom »
        lea     wb_sysname(pc),a0
.li_p1:
        move.b  (a0)+,(a1)+
        bne.s   .li_p1
        subq.l  #1,a1
        move.l  a4,a0
.li_p2:
        move.b  (a0)+,(a1)+
        bne.s   .li_p2
        move.l  WBS_ICONBASE(a5),a6
        move.l  sp,a0
        jsr     ICON_LVO_GETDISKOBJECT(a6)
        tst.l   d0
        beq     .li_next
        move.l  d4,d1
        lsl.l   #2,d1
        lea     WBS_ICONS(a5),a0
        move.l  d0,0(a0,d1.l)
        addq.l  #1,WBS_NICON(a5)
        bra     .li_next
.li_unlock:
        move.l  WBS_DOSBASE(a5),a6
        move.l  d7,d1
        jsr     DOS_LVO_UNLOCK(a6)
.li_free:
        lea     WB_PATHMAX(sp),sp
        move.l  ($4).w,a6
        move.l  d6,a1
        move.l  #FIB_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.li_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts
WB_PATHMAX      EQU 48

; wb_drawdrawer(a5) : dessine les icônes de la racine dans la fenêtre du disque, aux positions de leurs .info
; (relatives au coin intérieur : décalées des bordures gauche et haute), nom centré dessous. Préserve d2-d7/a2-a6.
wb_drawdrawer:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.l  WBS_DWIN(a5),d0
        beq     .dd_ret
        move.l  d0,a3
        moveq   #0,d7                ; d7 = icône
.dd_lp:
        cmp.l   WBS_NICON(a5),d7
        bhs     .dd_ret
        move.l  d7,d0
        lsl.l   #2,d0
        lea     WBS_ICONS(a5),a0
        move.l  0(a0,d0.l),a2        ; a2 = DiskObject
        move.w  #WB_GRIDX,d4         ; position : celle du .info, sinon grille (icône n)
        mulu    d7,d4
        moveq   #4,d5
        cmp.l   #NO_ICON_POSITION,DO_CURRENTX(a2)
        beq.s   .dd_pos
        move.w  DO_CURRENTX+2(a2),d4
        move.w  DO_CURRENTY+2(a2),d5
.dd_pos:
        moveq   #0,d0                ; coordonnées intérieures -> coordonnées de la fenêtre
        move.b  WD_BORDERLEFT(a3),d0
        add.w   d0,d4
        move.b  WD_BORDERTOP(a3),d0
        add.w   d0,d5
        move.l  WBS_IBASE(a5),a6
        move.l  WD_RPORT(a3),a0
        move.l  DO_GADGET+GG_GADGETRENDER(a2),a1
        move.w  d4,d0
        move.w  d5,d1
        jsr     LVO_DRAWIMAGE(a6)
        move.l  d7,d0                ; nom centré sous l'icône
        mulu    #WBS_NAMEMAX,d0
        lea     WBS_INAMES(a5),a4
        add.l   d0,a4
        move.l  a4,a0
        moveq   #-1,d2
.dd_len:
        addq.w  #1,d2
        tst.b   (a0)+
        bne.s   .dd_len
        move.l  WBS_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #2,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.w  DO_GADGET+GG_WIDTH(a2),d0
        lsr.w   #1,d0
        add.w   d4,d0
        move.w  d2,d1
        lsl.w   #2,d1
        sub.w   d1,d0
        move.w  d5,d1
        add.w   DO_GADGET+GG_HEIGHT(a2),d1
        add.w   #1+GFX_FONTBASE,d1
        jsr     LVO_MOVE(a6)
        move.l  a4,a0
        move.w  d2,d0
        jsr     LVO_TEXT(a6)
        addq.l  #1,d7
        bra     .dd_lp
.dd_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts
WB_GRIDX        EQU 80

wb_taskname:
        dc.b    "workbench.task",0
wb_intname:
        dc.b    "intuition.library",0
wb_gfxname:
        dc.b    "graphics.library",0
wb_dosname:
        dc.b    "dos.library",0
wb_iconname:
        dc.b    "icon.library",0
wb_sysname:
        dc.b    "SYS:",0
wb_diskname:
        dc.b    "SYS:Disk",0
wb_infosuffix:
        dc.b    ".info"
wb_procname:
        dc.b    "Workbench",0
wb_idstring:
        dc.b    "workbench.task 34.1 (minimal)",13,10,0
        EVEN
wb_end:
