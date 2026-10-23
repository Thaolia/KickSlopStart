; src/dos/workbench.s — résident workbench.task : le process que lance c:LoadWB.
; Spec : docs/analysis/workbench-task-v34.md (relue clean-room). Contrat avec LoadWB :
;   - ROMTag NT_TASK sans drapeau de classe : présent dans ResModules (FindResident) mais jamais initialisé au boot ;
;   - LoadWB fait CreateProc(..., seglist = BPTR(ROMTag+42), ...) : la troncature donne un faux segment à ROMTag+40
;     (lien) et un point d'entrée à ROMTag+44 (ROMTag aligné sur 4) ;
;   - le process doit répondre au message de LoadWB (28 octets : +$14 = BPTR du chemin, +$18 = drapeau -debug) dès son
;     initialisation, sinon LoadWB reste bloqué ; il se nomme « Workbench » (LoadWB le retrouve par FindTask) et
;     tourne en priorité 1.
; Bureau : écran Workbench, fenêtre de fond (BACKDROP) avec l'icône du disque de boot (SYS:Disk.info, icon.library du
; disque) et le nom du volume. Fenêtres de tiroir (WB_MAXDRAWERS) : la racine (double-clic sur le disque) et tout
; tiroir imbriqué (double-clic sur une icône de tiroir), icônes lues par Examine/ExNext + GetDiskObject, redessinées
; au REFRESHWINDOW (BeginRefresh/EndRefresh). Une seule icône sélectionnée à la fois (rectangle inversé). Double-clic
; sur un outil : lancé par CreateProc avec un message WBStartup (argument 0 = l'outil) ; sur un projet : son outil par
; défaut, le projet en argument 1. Le message revient sur le port « Workbench » à la fin de l'outil : segment
; déchargé, verrous rendus. Menus Workbench / Disk / Special : Open, Close, Rename, Discard, Clean Up, Last Error,
; Redraw, Snapshot et Version actifs, le reste grisé. Titre d'écran (spec §6) : mémoire libre au tic de 5 s, message
; figé (Version, Last Error) jusqu'au prochain clic ou menu. Portée : ni Info / Duplicate, ni icône Ram Disk, ni
; défilement des tiroirs, une seule icône sélectionnée ; Rename et Discard ne s'appliquent qu'aux icônes d'un
; tiroir. Échecs signalés en titre d'écran comme la 1.3 (spec §6.9) : « Error while <action>: <IoErr> » à l'ouverture
; d'un tiroir, au lancement, au Rename (et « Do not use ':' in names »), au Discard et au Snapshot.
; Piste IMPLÉMENTATION (« clean ») : spec ci-dessus + AutoDocs exec/dos/workbench (WBStartup, DiskObject).
; AUCUNE lecture ROM.

                include "exec.i"
                include "dospkt.i"
                include "intuition.i"
                include "graphics.i"

                ifeq    PROD
                xref    ser_puts             ; marqueurs de test (ROM de développement)
                endc

LVO_DRAWIMAGE   EQU -114             ; intuition.library (intuition_lib.fd)
LVO_SETWINDOWTITLES EQU -276
LVO_DISPLAYBEEP EQU -96
LVO_SETMENUSTRIP EQU -264
LVO_CLEARMENUSTRIP EQU -54
LVO_BEGINREFRESH EQU -354
LVO_ENDREFRESH  EQU -366
LVO_WINDOWTOFRONT EQU -312
LVO_DOUBLECLICK EQU -102
LVO_REPORTMOUSE EQU -234
ICON_LVO_GETDISKOBJECT EQU -78       ; icon.library (icon_lib.fd)
ICON_LVO_PUTDISKOBJECT EQU -84
ICON_LVO_GETWBOBJECT EQU -30         ; icon.library 1.3 (spec workbench-task-v34 §7.8)
ICON_LVO_FREEWBOBJECT EQU -60
ICON_LVO_ADDFREELIST EQU -72
ICON_LVO_PUTWBOBJECT EQU -36
ICON_LVO_BUMPREVISION EQU -108
WBO_CURX        EQU $54              ; WBObject : position de l'icône (LONG)
WBO_CURY        EQU $58
WBO_NAME        EQU $40              ; WBObject (privé, alloué par icon.library) : nom C
WBO_DRAWER      EQU $4C              ; DrawerData du Workbench (446 octets) | 0
WBO_FREE        EQU $8C              ; FreeList de l'objet
WBO_LOCK        EQU $A4              ; BPTR du répertoire contenant
WBD_LOCK        EQU $1BA             ; DrawerData : BPTR du répertoire du tiroir / disque
ICON_LVO_FREEDISKOBJECT EQU -90
DOS_LVO_CREATEPROC EQU -138
NW_SIZEOF       EQU 48               ; struct NewWindow
DO_GADGET       EQU 4                ; struct DiskObject (workbench/workbench.h) : gadget embarqué
DO_TYPE         EQU 48
DO_DEFAULTTOOL  EQU 50
DO_CURRENTX     EQU 58
DO_CURRENTY     EQU 62
DO_DRAWERDATA   EQU 66               ; struct DrawerData : dd_NewWindow en tête
DO_STACKSIZE    EQU 74
NO_ICON_POSITION EQU $80000000
WBDISK          EQU 1
WBDRAWER        EQU 2
WBTOOL          EQU 3
WBPROJECT       EQU 4
WBGARBAGE       EQU 5
SM_PROCESS      EQU 20               ; struct WBStartup (workbench/startup.h)
SM_SEGMENT      EQU 24
SM_NUMARGS      EQU 28
SM_TOOLWINDOW   EQU 32
SM_ARGLIST      EQU 36
SM_SIZE         EQU 40
WA_LOCK         EQU 0                ; struct WBArg
WA_NAME         EQU 4
WA_SIZE         EQU 8

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
        move.w  #-1,WBS_SELW(a5)
        move.w  #-1,WBS_DRAGW(a5)
        bsr     wb_mkmenus
        moveq   #MP_SIZE,d0          ; port public « Workbench » (messages WBStartup rendus par les outils)
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
        lea     MP_MSGLIST(a3),a0
        move.l  a0,8(a0)
        addq.l  #4,a0
        move.l  a0,-4(a0)
        move.l  a3,a1
        jsr     LVO_ADDPORT(a6)
        move.l  a3,WBS_PORT(a5)
        bsr     wb_desktop           ; écran Workbench, fenêtre de fond, icône du disque
        bsr     wb_timeropen         ; tic de 5 s (titre d'écran : mémoire libre)
.we_loop:                            ; attend le port public et les ports IDCMP de toutes les fenêtres
        move.l  ($4).w,a6
        move.l  WBS_PORT(a5),a0
        moveq   #0,d0
        move.b  MP_SIGBIT(a0),d1
        bset    d1,d0
        move.l  WBS_WIN(a5),a0
        bsr     wb_sigbit
        lea     WBS_DRAWERS(a5),a4
        moveq   #WB_MAXDRAWERS-1,d2
.we_sig:
        move.l  DR_WIN(a4),a0
        bsr     wb_sigbit
        lea     DR_SIZE(a4),a4
        dbra    d2,.we_sig
        jsr     LVO_WAIT(a6)
.we_drain:                           ; port public : messages WBStartup rendus, ou messages étrangers (répondus)
        move.l  ($4).w,a6
        move.l  WBS_PORT(a5),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .we_wins
        move.l  d0,a1
        lea     WBS_TREQ(a5),a0
        cmp.l   a0,a1
        bne.s   .we_ntick
        bsr     wb_tick
        bra.s   .we_drain
.we_ntick:
        cmp.b   #NT_REPLYMSG,LN_TYPE(a1)
        bne.s   .we_foreign
        bsr     wb_toolreturn
        bra.s   .we_drain
.we_foreign:
        jsr     LVO_REPLYMSG(a6)
        bra.s   .we_drain
.we_wins:
        moveq   #0,d7                ; fenêtre 0 : le bureau, puis les tiroirs 1..WB_MAXDRAWERS
.we_win:
        bsr     wb_dispatch
        addq.w  #1,d7
        cmp.w   #WB_MAXDRAWERS,d7
        bls.s   .we_win
        bra     .we_loop
.we_idle:                            ; sans état ni port : attente sans fin (le process ne se termine pas, comme le vrai)
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
WBS_PORT        EQU WBS_NAME+WBS_NAMEMAX ; port public « Workbench »
WBS_IX          EQU WBS_PORT+4       ; position de l'icône du disque dans la fenêtre de fond
WBS_IY          EQU WBS_IX+2
WBS_SELW        EQU WBS_IY+2         ; WORD : fenêtre de l'icône sélectionnée (0 bureau, 1.. tiroir), -1 : aucune
WBS_SELI        EQU WBS_SELW+2       ; WORD : n° de l'icône sélectionnée
WBS_LSEC        EQU WBS_SELI+2       ; horodatage du clic précédent (double-clic)
WBS_LMIC        EQU WBS_LSEC+4
WBS_SHOWN       EQU WBS_LMIC+4       ; BYTE : icône du disque dessinée
WBS_GON         EQU WBS_SHOWN+1      ; BYTE : cadre fantôme du glisser affiché
WBS_DRAGW       EQU WBS_SHOWN+2      ; WORD : fenêtre de l'icône glissée, -1 : aucun glisser
WBS_DRAGI       EQU WBS_DRAGW+2      ; WORD : icône glissée
WBS_DSX         EQU WBS_DRAGI+2      ; souris au clic (relative à la fenêtre)
WBS_DSY         EQU WBS_DSX+2
WBS_GX          EQU WBS_DSY+2        ; cadre fantôme : coin et taille (coordonnées de l'écran)
WBS_GY          EQU WBS_GX+2
WBS_GW          EQU WBS_GY+2
WBS_GH          EQU WBS_GW+2
WBS_GRP         EQU WBS_GH+2         ; RastPort de l'écran (cadre tracé en COMPLEMENT)
WBS_TREQ        EQU WBS_GRP+4        ; timerequest du tic de 5 s (réponse sur le port public)
WBS_MEMV        EQU WBS_TREQ+TR_SIZE ; dernière valeur d'AvailMem affichée
WBS_TBUF        EQU WBS_MEMV+4       ; titre d'écran des fenêtres du Workbench (chaîne C)
WBS_TBUFMAX     EQU 80
WBS_TON         EQU WBS_TBUF+WBS_TBUFMAX ; BYTE : timer.device ouvert
WBS_FLAGS       EQU WBS_TON+1        ; BYTE : bit 1 = titre verrouillé (Rename), bit 2 = un message est affiché
WBS_MSGBUF      EQU WBS_TON+2        ; dernier message (Version, Last Error) : WBS_TBUFMAX octets
WBS_MSGOK       EQU WBS_MSGBUF+WBS_TBUFMAX ; BYTE : un message a été produit
WBS_DRAWERS     EQU WBS_MSGOK+2      ; WB_MAXDRAWERS fiches de tiroir
WBS_MENUS       EQU WBS_DRAWERS+WB_MAXDRAWERS*DR_SIZE ; copie des menus (intuition y écrit)
WBS_SIZE        EQU WBS_MENUS+WBM_SIZE
WB_MAXDRAWERS   EQU 6
; fiche d'un tiroir
DR_WIN          EQU 0                ; fenêtre | 0 (fiche libre)
DR_NICON        EQU 4                ; icônes lues
DR_ICONS        EQU 8                ; WB_MAXICONS x DiskObject
DR_NAMES        EQU DR_ICONS+WB_MAXICONS*4 ; WB_MAXICONS x nom (WBS_NAMEMAX octets)
DR_PATH         EQU DR_NAMES+WB_MAXICONS*WBS_NAMEMAX ; chemin du tiroir (« SYS: », « SYS:System »...)
DR_TITLE        EQU DR_PATH+WB_PATHMAX ; titre de la fenêtre
DR_ID           EQU DR_TITLE+WBS_NAMEMAX ; WORD : n° de la fenêtre (1..WB_MAXDRAWERS)
DR_SIZE         EQU DR_ID+2
WB_MAXICONS     EQU 16
WB_PATHMAX      EQU 96
WB_CPBUF        EQU 4096             ; tampon de copie de Duplicate
WB_ICONGAP      EQU 20               ; marge droite de l'icône de disque (pas de position mémorisée)
WB_ICONTOP      EQU 6
WB_GRIDX        EQU 80
WB_TOOLSTACK    EQU 4096             ; pile minimale d'un outil lancé

; wb_desktop(a5 = état, a6 = SysBase) : ouvre l'écran Workbench, la fenêtre de fond (BACKDROP, sans bordure, sous la
; barre de l'écran), lit le nom du volume SYS: et l'icône SYS:Disk (icon.library du disque), puis dessine le bureau.
; Chaque étape est optionnelle (bibliothèque ou fichier absent : bureau plus pauvre). Préserve d2-d7/a2-a6.
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
        bsr     wb_nwclear
        moveq   #0,d1
        move.b  SC_BARHEIGHT(a2),d1
        addq.w  #1,d1
        move.w  d1,NW_TOPEDGE(a0)
        move.w  SC_WIDTH(a2),NW_WIDTH(a0)
        move.w  SC_HEIGHT(a2),d0
        sub.w   d1,d0
        move.w  d0,NW_HEIGHT(a0)
        move.l  #REFRESHWINDOW|MOUSEBUTTONS|MOUSEMOVE|MENUPICK,NW_IDCMPFLAGS(a0)
        move.l  #BACKDROP|BORDERLESS,NW_FLAGS(a0)
        jsr     LVO_OPENWINDOW(a6)
        lea     NW_SIZEOF(sp),sp
        move.l  d0,WBS_WIN(a5)
        beq.s   .wd_vol
        move.l  d0,a0
        bsr     wb_setmenus
.wd_vol:
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
        moveq   #0,d7
        bsr     wb_drawwin
.wd_ret:
        movem.l (sp)+,d2-d3/a2/a6
        rts

; wb_nwclear(sp+4 = NewWindow réservée par l'appelant) -> a0 = NewWindow à zéro, stylos de l'écran, type WBENCHSCREEN.
; Clobbe d1.
wb_nwclear:
        lea     4(sp),a0
        moveq   #NW_SIZEOF/2-1,d1
.nc_lp:
        clr.w   (a0)+
        dbra    d1,.nc_lp
        lea     4(sp),a0
        move.w  #$FFFF,NW_DETAILPEN(a0)
        move.w  #WBENCHSCREEN,NW_TYPE(a0)
        rts

; wb_openlib(a1 = nom) -> d0 = base | 0 (OpenLibrary version 0).
wb_openlib:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  (sp)+,a6
        rts

; wb_setmenus(a0 = fenêtre, a5) : y attache la barre de menus du Workbench. Préserve d2-d7/a2-a6.
wb_setmenus:
        move.l  a6,-(sp)
        lea     WBS_MENUS(a5),a1
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_SETMENUSTRIP(a6)
        move.l  (sp)+,a6
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

; wb_window(d7.w = n° de fenêtre, a5) -> a3 = fenêtre | 0, a4 = fiche du tiroir (n° > 0) ; Z = 1 si pas de fenêtre.
; Clobbe d0.
wb_window:
        tst.w   d7
        bne.s   .ww_dr
        move.l  WBS_WIN(a5),a3
        bra.s   .ww_ret
.ww_dr:
        move.w  d7,d0
        subq.w  #1,d0
        mulu    #DR_SIZE,d0
        lea     WBS_DRAWERS(a5),a4
        add.l   d0,a4
        move.l  DR_WIN(a4),a3
.ww_ret:
        move.l  a3,d0
        rts

; wb_dispatch(d7.w = n° de fenêtre, a5) : traite les messages IDCMP de la fenêtre (déjà répondus par wb_getmsg) :
; REFRESHWINDOW -> redessin des zones abîmées ; SELECTDOWN -> clic ; MENUPICK -> menu ; CLOSEWINDOW -> fermeture du
; tiroir (fin du traitement : la fenêtre n'existe plus). Préserve d7/a5.
wb_dispatch:
        bsr     wb_window
        beq     .dp_ret
        move.l  ($4).w,a6
        move.l  a3,a0
        bsr     wb_getmsg            ; d2 = classe, d3 = code, d4/d5 = souris, d6 = secondes, a0 = micros
        beq     .dp_ret
        cmp.l   #REFRESHWINDOW,d2
        bne.s   .dp_mb
        bsr     wb_window
        move.l  a3,a0
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_BEGINREFRESH(a6)
        bsr     wb_drawwin
        bsr     wb_window
        move.l  a3,a0
        moveq   #1,d0
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_ENDREFRESH(a6)
        bra.s   wb_dispatch
.dp_mb:
        cmp.l   #MOUSEBUTTONS,d2
        bne.s   .dp_mv
        cmp.w   #SELECTDOWN,d3
        bne.s   .dp_up
        bsr     wb_restore           ; clic gauche : le titre mémoire revient (spec §6.2)
        bsr     wb_click
        bra     wb_dispatch
.dp_up:
        cmp.w   #SELECTUP,d3
        bne     wb_dispatch
        bsr     wb_dragend
        bra     wb_dispatch
.dp_mv:
        cmp.l   #MOUSEMOVE,d2
        bne.s   .dp_menu
        bsr     wb_dragmove
        bra     wb_dispatch
.dp_menu:
        cmp.l   #MENUPICK,d2
        bne.s   .dp_close
        bsr     wb_menupick
        bra.s   wb_dispatch
.dp_close:
        cmp.l   #CLOSEWINDOW,d2
        bne.s   wb_dispatch
        tst.w   d7
        beq.s   wb_dispatch
        bra     wb_closedrawer
.dp_ret:
        rts

; wb_getmsg(a0 = fenêtre, a6 = SysBase) -> Z = 1 si aucun message ; sinon d2 = classe, d3 = code, d4/d5 = souris,
; d6 = secondes, a0 = micros, et le message est déjà répondu (il appartient à la fenêtre). Clobbe d0/d1/a1.
wb_getmsg:
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
        move.l  IM_MICROS(a1),-(sp)
        jsr     LVO_REPLYMSG(a6)
        move.l  (sp)+,a0
        moveq   #1,d0                ; Z = 0
        rts
.gm_none:
        moveq   #0,d0
        rts

; wb_iconrect(d7.w = fenêtre, d1.w = n° d'icône, a5) -> a2 = DiskObject, d0..d3 = x0,y0,x1,y1 dans la fenêtre ;
; Z = 1 si l'icône n'existe pas. Bureau : l'icône du disque à (IX, IY) ; tiroir : position du .info (sinon grille)
; décalée des bordures gauche et haute. Clobbe a0/a1.
wb_iconrect:
        tst.w   d7
        bne.s   .ir_dr
        tst.w   d1
        bne.s   .ir_none
        tst.b   WBS_SHOWN(a5)
        beq.s   .ir_none
        move.l  WBS_DOBJ(a5),a2
        move.w  WBS_IX(a5),d0
        move.w  WBS_IY(a5),d1
        bra.s   .ir_size
.ir_dr:
        move.l  a4,-(sp)
        move.l  a3,-(sp)
        bsr     wb_window
        move.l  a3,a1
        move.l  (sp)+,a3
        beq.s   .ir_pop
        cmp.w   DR_NICON+2(a4),d1
        bhs.s   .ir_pop
        move.w  d1,d0
        lsl.w   #2,d0
        move.l  DR_ICONS(a4,d0.w),a2
        move.w  #WB_GRIDX,d0
        mulu    d1,d0
        moveq   #4,d1
        cmp.l   #NO_ICON_POSITION,DO_CURRENTX(a2)
        beq.s   .ir_bord
        move.w  DO_CURRENTX+2(a2),d0
        move.w  DO_CURRENTY+2(a2),d1
.ir_bord:
        moveq   #0,d2
        move.b  WD_BORDERLEFT(a1),d2
        add.w   d2,d0
        move.b  WD_BORDERTOP(a1),d2
        add.w   d2,d1
        move.l  (sp)+,a4
.ir_size:
        move.w  d0,d2
        add.w   DO_GADGET+GG_WIDTH(a2),d2
        subq.w  #1,d2
        move.w  d1,d3
        add.w   DO_GADGET+GG_HEIGHT(a2),d3
        subq.w  #1,d3
        move.l  a2,-(sp)             ; Z = 0
        tst.l   (sp)+
        rts
.ir_pop:
        move.l  (sp)+,a4
.ir_none:
        moveq   #0,d0                ; Z = 1
        rts

; wb_drawwin(d7.w = fenêtre, a5) : dessine ses icônes (et le nom de chacune dessous) ; la sélection est réinversée.
; Préserve d2-d7/a2-a6.
wb_drawwin:
        movem.l d2-d7/a2-a4/a6,-(sp)
        bsr     wb_window
        beq     .dw_ret
        tst.w   d7
        bne.s   .dw_dr
        move.l  WBS_DOBJ(a5),d0      ; bureau : position de l'icône du disque (en haut à droite, nom compris)
        beq     .dw_ret
        move.l  d0,a2
        lea     WBS_NAME(a5),a0
        bsr     wb_strlen
        lsl.w   #3,d0
        sub.w   DO_GADGET+GG_WIDTH(a2),d0
        bpl.s   .dw_wide
        moveq   #0,d0
.dw_wide:
        lsr.w   #1,d0
        move.w  WD_WIDTH(a3),d4
        sub.w   DO_GADGET+GG_WIDTH(a2),d4
        sub.w   d0,d4
        sub.w   #WB_ICONGAP,d4
        moveq   #WB_ICONTOP,d5
        cmp.l   #NO_ICON_POSITION,DO_CURRENTX(a2)
        beq.s   .dw_pos
        move.w  DO_CURRENTX+2(a2),d4
        move.w  DO_CURRENTY+2(a2),d5
.dw_pos:
        move.w  d4,WBS_IX(a5)
        move.w  d5,WBS_IY(a5)
        st      WBS_SHOWN(a5)
        lea     WBS_NAME(a5),a4
        moveq   #0,d6
        bsr     wb_drawicon
        bra.s   .dw_ret
.dw_dr:
        moveq   #0,d6                ; d6 = icône
.dw_lp:
        cmp.w   DR_NICON+2(a4),d6
        bhs.s   .dw_ret
        bsr.s   wb_drawone
        addq.w  #1,d6
        bra.s   .dw_lp
.dw_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts

; wb_drawone(d7.w = tiroir, d6.w = icône, a5) : dessine l'icône si elle tient entière (nom compris) dans l'intérieur
; de la fenêtre (pas de défilement : une icône hors champ apparaît quand on agrandit). Préserve d2-d7/a2-a4.
wb_drawone:
        movem.l d2-d7/a2-a4,-(sp)
        bsr     wb_window            ; a3/a4 (avant wb_iconrect : wb_window écrase d0)
        move.w  d6,d1
        bsr     wb_iconrect
        beq.s   .do_ret
        bsr     wb_inside
        bne.s   .do_ret
        move.w  d0,d4
        move.w  d1,d5
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a4
        bsr     wb_drawicon
.do_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; wb_inside(a3 = fenêtre, d0..d3 = rectangle de l'icône) -> Z = 1 si l'icône et son nom (une ligne de texte sous elle)
; tiennent dans l'intérieur de la fenêtre. Clobbe a0 ; préserve d0-d3.
wb_inside:
        movem.l d0-d4,-(sp)
        moveq   #0,d4
        move.b  WD_BORDERLEFT(a3),d4
        cmp.w   d4,d0
        blt.s   .in_no
        move.b  WD_BORDERTOP(a3),d4
        cmp.w   d4,d1
        blt.s   .in_no
        move.w  WD_WIDTH(a3),d4
        moveq   #0,d0
        move.b  WD_BORDERRIGHT(a3),d0
        sub.w   d0,d4                ; d4 = premier x hors intérieur
        cmp.w   d4,d2
        bge.s   .in_no
        move.w  WD_HEIGHT(a3),d4
        moveq   #0,d0
        move.b  WD_BORDERBOTTOM(a3),d0
        sub.w   d0,d4
        add.w   #GFX_FONTH+1,d3      ; ligne du nom
        cmp.w   d4,d3
        bge.s   .in_no
        moveq   #0,d0                ; Z = 1
        bra.s   .in_ret
.in_no:
        moveq   #1,d0                ; Z = 0
.in_ret:
        movem.l (sp)+,d0-d4
        rts

; wb_drawicon(a2 = DiskObject, a3 = fenêtre, a4 = nom, d4/d5 = position, d6.w = n°, d7.w = fenêtre, a5) : image de
; l'icône, nom centré dessous (stylo 2, JAM1), inversion si sélectionnée. Préserve d2-d7/a2-a4.
wb_drawicon:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  WBS_IBASE(a5),a6
        move.l  WD_RPORT(a3),a0
        move.l  DO_GADGET+GG_GADGETRENDER(a2),a1
        move.w  d4,d0
        move.w  d5,d1
        jsr     LVO_DRAWIMAGE(a6)
        move.l  a4,a0
        bsr     wb_strlen
        move.w  d0,d2
        beq.s   .di_sel
        move.l  WBS_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #2,d0
        jsr     LVO_SETAPEN(a6)
        move.l  WD_RPORT(a3),a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        move.w  DO_GADGET+GG_WIDTH(a2),d0
        lsr.w   #1,d0
        add.w   d4,d0
        move.w  d2,d1
        lsl.w   #2,d1                ; demi-largeur du texte
        sub.w   d1,d0
        move.w  d5,d1
        add.w   DO_GADGET+GG_HEIGHT(a2),d1
        add.w   #1+GFX_FONTBASE,d1
        move.l  WD_RPORT(a3),a1
        jsr     LVO_MOVE(a6)
        move.l  a4,a0
        move.w  d2,d0
        move.l  WD_RPORT(a3),a1
        jsr     LVO_TEXT(a6)
.di_sel:
        cmp.w   WBS_SELW(a5),d7
        bne.s   .di_ret
        cmp.w   WBS_SELI(a5),d6
        bne.s   .di_ret
        move.w  d6,d1
        bsr     wb_invert
.di_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; wb_invert(d7.w = fenêtre, d1.w = icône, a5) : inverse (COMPLEMENT) le rectangle de l'icône. Préserve d2-d7/a2-a5.
wb_invert:
        movem.l d2-d3/a2-a4/a6,-(sp)
        bsr     wb_iconrect
        beq.s   .iv_ret
        movem.w d0-d3,-(sp)
        bsr     wb_window
        move.l  WBS_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        movem.w (sp)+,d0-d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        move.l  WD_RPORT(a3),a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
.iv_ret:
        movem.l (sp)+,d2-d3/a2-a4/a6
        rts

; wb_click(d7.w = fenêtre, d4/d5 = souris dans la fenêtre, d6/a0 = horodatage, a5) : sur une icône -> sélection (la
; précédente est rendue normale) et début d'un glisser ; sur l'icône déjà sélectionnée dans le délai de double-clic
; -> ouverture ; ailleurs -> désélection. Préserve d7/a5.
wb_click:
        move.l  a0,-(sp)             ; micros
        clr.l   -(sp)                ; (sp) = icône testée
        bsr     wb_window            ; a3 = fenêtre
.ck_find:
        move.l  (sp),d1
        bsr     wb_iconrect
        beq.s   .ck_none
        tst.w   d7
        beq.s   .ck_test
        bsr     wb_inside            ; tiroir : icône dessinée seulement si elle tient dans l'intérieur
        bne.s   .ck_nx
.ck_test:
        cmp.w   d0,d4
        blt.s   .ck_nx
        cmp.w   d2,d4
        bgt.s   .ck_nx
        cmp.w   d1,d5
        blt.s   .ck_nx
        cmp.w   d3,d5
        ble.s   .ck_hit
.ck_nx:
        addq.l  #1,(sp)
        bra.s   .ck_find
.ck_hit:
        move.l  (sp)+,d1
        cmp.w   WBS_SELW(a5),d7
        bne.s   .ck_select
        cmp.w   WBS_SELI(a5),d1
        bne.s   .ck_select
        move.l  d1,-(sp)             ; même icône : double-clic ?
        move.l  WBS_LSEC(a5),d0
        move.l  WBS_LMIC(a5),d1
        move.l  d6,d2
        move.l  4(sp),d3
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_DOUBLECLICK(a6)
        move.l  (sp)+,d1
        tst.l   d0
        beq.s   .ck_drag
        bsr     wb_openicon
        bra.s   .ck_stamp
.ck_select:
        move.l  d1,-(sp)
        bsr     wb_deselect
        move.l  (sp),d1
        move.w  d7,WBS_SELW(a5)
        move.w  d1,WBS_SELI(a5)
        bsr     wb_invert
        move.l  (sp)+,d1
.ck_drag:
        bsr     wb_dragstart         ; l'icône peut être glissée tant que le bouton reste enfoncé
.ck_stamp:
        move.l  d6,WBS_LSEC(a5)
        move.l  (sp)+,WBS_LMIC(a5)
        rts
.ck_none:
        addq.l  #8,sp
        bra     wb_deselect

; wb_redraw1(d7.w = fenêtre, a5) : intérieur effacé au stylo 0 puis icônes redessinées. Préserve d7/a5.
wb_redraw1:
        movem.l d2-d6/a2-a4/a6,-(sp)
        bsr     wb_window
        beq.s   .r1_ret
        move.l  WBS_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #0,d0
        jsr     LVO_SETAPEN(a6)
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        moveq   #0,d1
        move.b  WD_BORDERTOP(a3),d1
        move.w  WD_WIDTH(a3),d2
        moveq   #0,d3
        move.b  WD_BORDERRIGHT(a3),d3
        sub.w   d3,d2
        subq.w  #1,d2
        move.w  WD_HEIGHT(a3),d3
        moveq   #0,d4
        move.b  WD_BORDERBOTTOM(a3),d4
        sub.w   d4,d3
        subq.w  #1,d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        bsr     wb_drawwin
.r1_ret:
        movem.l (sp)+,d2-d6/a2-a4/a6
        rts

; wb_dragstart(d7.w = fenêtre, d1.w = icône, d4/d5 = souris, a5) : glisser armé ; la fenêtre reçoit les mouvements
; (ReportMouse). Préserve d2-d7/a2-a5.
wb_dragstart:
        move.w  d7,WBS_DRAGW(a5)
        move.w  d1,WBS_DRAGI(a5)
        move.w  d4,WBS_DSX(a5)
        move.w  d5,WBS_DSY(a5)
        clr.b   WBS_GON(a5)
        moveq   #1,d0
; wb_report(d0 = drapeau, WBS_DRAGW, a5) : ReportMouse de la fenêtre du glisser. Préserve d2-d7/a2-a5.
wb_report:
        movem.l d7/a3-a4/a6,-(sp)
        move.l  d0,-(sp)
        move.w  WBS_DRAGW(a5),d7
        bsr     wb_window
        move.l  (sp)+,d0
        cmpa.w  #0,a3
        beq.s   .rp_ret
        move.l  a3,a0
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_REPORTMOUSE(a6)
.rp_ret:
        movem.l (sp)+,d7/a3-a4/a6
        rts

; wb_dragmove(d7.w = fenêtre, d4/d5 = souris, a5) : le cadre fantôme (taille de l'icône) suit le déplacement depuis
; le clic, tracé en COMPLEMENT dans le RastPort de l'écran. Préserve d2-d7/a2-a5.
wb_dragmove:
        cmp.w   WBS_DRAGW(a5),d7
        bne.s   .gm_r
        movem.l d2-d3/a2-a4,-(sp)
        tst.b   WBS_GON(a5)
        beq.s   .gm_new
        bsr     wb_ghost             ; efface l'ancien cadre
.gm_new:
        move.w  WBS_DRAGI(a5),d1
        bsr     wb_iconrect
        beq.s   .gm_out
        sub.w   d0,d2
        addq.w  #1,d2
        move.w  d2,WBS_GW(a5)
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  d3,WBS_GH(a5)
        add.w   d4,d0
        sub.w   WBS_DSX(a5),d0
        add.w   d5,d1
        sub.w   WBS_DSY(a5),d1
        movem.w d0-d1,-(sp)
        bsr     wb_window
        movem.w (sp)+,d0-d1
        add.w   WD_LEFTEDGE(a3),d0
        add.w   WD_TOPEDGE(a3),d1
        move.w  d0,WBS_GX(a5)
        move.w  d1,WBS_GY(a5)
        move.l  WD_WSCREEN(a3),a0
        lea     SC_RASTPORT(a0),a0
        move.l  a0,WBS_GRP(a5)
        bsr     wb_ghost             ; trace le nouveau
.gm_out:
        movem.l (sp)+,d2-d3/a2-a4
.gm_r:
        rts

; wb_ghost(a5) : bascule le cadre fantôme (quatre traits d'un pixel en COMPLEMENT, coins non doublés) ; WBS_GON
; indique s'il est affiché. Préserve d2-d7/a2-a5.
wb_ghost:
        movem.l d2-d5/a6,-(sp)
        not.b   WBS_GON(a5)
        move.l  WBS_GFXBASE(a5),a6
        move.l  WBS_GRP(a5),a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        move.w  WBS_GX(a5),d4
        move.w  WBS_GY(a5),d5
        move.w  d4,d0                ; haut
        move.w  d5,d1
        move.w  d4,d2
        add.w   WBS_GW(a5),d2
        subq.w  #1,d2
        move.w  d5,d3
        bsr.s   .gh_fill
        move.w  d5,d1                ; bas
        add.w   WBS_GH(a5),d1
        subq.w  #1,d1
        move.w  d1,d3
        bsr.s   .gh_fill
        move.w  WBS_GH(a5),d3
        subq.w  #3,d3
        bmi.s   .gh_end              ; pas de côtés pour une hauteur < 3
        move.w  d5,d1                ; gauche
        addq.w  #1,d1
        add.w   d1,d3
        move.w  d4,d0
        move.w  d4,d2
        bsr.s   .gh_fill
        move.w  d4,d0                ; droite
        add.w   WBS_GW(a5),d0
        subq.w  #1,d0
        move.w  d0,d2
        bsr.s   .gh_fill
.gh_end:
        move.l  WBS_GRP(a5),a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        movem.l (sp)+,d2-d5/a6
        rts
.gh_fill:                            ; RectFill(d0..d3) ; préserve d0-d5
        movem.l d0-d3,-(sp)
        move.l  WBS_GRP(a5),a1
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d0-d3
        rts

; wb_dragend(d7.w = fenêtre, d4/d5 = souris au relâchement, a5) : fin du glisser (cadre effacé, plus de mouvements).
; Relâché dans la fenêtre d'origine, à au moins 3 pixels du clic : l'icône y prend sa nouvelle position (DiskObject
; mis à jour en mémoire, non sauvé) et la fenêtre est redessinée. Préserve d7/a5.
wb_dragend:
        move.w  WBS_DRAGW(a5),d0
        bmi     .de_ret
        cmp.w   d0,d7
        bne     .de_ret
        tst.b   WBS_GON(a5)
        beq.s   .de_ng
        bsr     wb_ghost
.de_ng:
        moveq   #0,d0
        bsr     wb_report
        move.w  #-1,WBS_DRAGW(a5)
        movem.l d2-d6/a2-a4,-(sp)
        move.w  d4,d2
        sub.w   WBS_DSX(a5),d2       ; d2/d3 = déplacement
        move.w  d5,d3
        sub.w   WBS_DSY(a5),d3
        move.w  d2,d0
        bpl.s   .de_ax
        neg.w   d0
.de_ax:
        move.w  d3,d1
        bpl.s   .de_ay
        neg.w   d1
.de_ay:
        add.w   d1,d0
        cmp.w   #3,d0
        blt.s   .de_out              ; simple clic
        bsr     wb_window
        beq.s   .de_out
        tst.w   d4                   ; relâché hors de la fenêtre d'origine : rien
        bmi.s   .de_out
        tst.w   d5
        bmi.s   .de_out
        cmp.w   WD_WIDTH(a3),d4
        bge.s   .de_out
        cmp.w   WD_HEIGHT(a3),d5
        bge.s   .de_out
        move.w  WBS_DRAGI(a5),d1
        movem.w d2-d3,-(sp)
        bsr     wb_iconrect          ; a2 = DiskObject, d0/d1 = position actuelle dans la fenêtre
        movem.w (sp)+,d2-d3
        beq.s   .de_out
        add.w   d2,d0
        add.w   d3,d1
        tst.w   d7
        beq.s   .de_desk
        moveq   #0,d2                ; tiroir : DO_Current* est relatif à l'intérieur (sans les bordures)
        move.b  WD_BORDERLEFT(a3),d2
        sub.w   d2,d0
        move.b  WD_BORDERTOP(a3),d2
        sub.w   d2,d1
.de_desk:
        tst.w   d0
        bpl.s   .de_x
        moveq   #0,d0
.de_x:
        tst.w   d1
        bpl.s   .de_y
        moveq   #0,d1
.de_y:
        ext.l   d0
        ext.l   d1
        move.l  d0,DO_CURRENTX(a2)
        move.l  d1,DO_CURRENTY(a2)
        bsr     wb_redraw1
.de_out:
        movem.l (sp)+,d2-d6/a2-a4
.de_ret:
        rts

; wb_deselect(a5) : plus d'icône sélectionnée (rendue normale si sa fenêtre existe). Préserve d2-d7/a2-a5.
wb_deselect:
        move.w  WBS_SELW(a5),d0
        bmi.s   .ds_ret
        move.l  d7,-(sp)
        move.w  d0,d7
        move.w  WBS_SELI(a5),d1
        move.w  #-1,WBS_SELW(a5)
        bsr     wb_invert
        move.l  (sp)+,d7
.ds_ret:
        rts

; wb_openicon(d7.w = fenêtre, d1.w = icône, a5) : bureau -> tiroir racine ; tiroir / poubelle -> sa fenêtre ; outil ->
; lancé ; projet -> son outil par défaut avec le projet en argument. Préserve d6/d7/a5.
wb_openicon:
        movem.l d6-d7/a3-a4,-(sp)
        lea     -WB_PATHMAX(sp),sp
        tst.w   d7
        bne.s   .oi_dr
        move.l  WBS_DOBJ(a5),d0      ; disque : racine « SYS: », titre = nom du volume
        beq     .oi_ret
        move.l  d0,a2
        lea     wb_sysname(pc),a0
        lea     WBS_NAME(a5),a1
        bsr     wb_opendrawer
        bra     .oi_ret
.oi_dr:
        move.w  d1,d6
        bsr     wb_iconrect
        beq     .oi_ret
        bsr     wb_window
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a3 ; a3 = nom de l'icône
        lea     DR_PATH(a4),a0
        move.l  sp,a1
        move.l  a3,a4
        bsr     wb_join              ; (sp) = chemin complet
        move.b  DO_TYPE(a2),d0
        cmp.b   #WBDRAWER,d0
        beq.s   .oi_drawer
        cmp.b   #WBGARBAGE,d0
        beq.s   .oi_drawer
        cmp.b   #WBTOOL,d0
        beq.s   .oi_tool
        cmp.b   #WBPROJECT,d0
        bne.s   .oi_ret
        move.l  DO_DEFAULTTOOL(a2),d0 ; projet : outil par défaut, le projet en argument
        beq.s   .oi_ret
        move.l  d0,a0
        move.l  sp,a1
        bsr     wb_launch
        bra.s   .oi_ret
.oi_tool:
        move.l  sp,a0
        suba.l  a1,a1
        bsr     wb_launch
        bra.s   .oi_ret
.oi_drawer:
        move.l  sp,a0
        move.l  a4,a1
        bsr     wb_opendrawer
.oi_ret:
        lea     WB_PATHMAX(sp),sp
        movem.l (sp)+,d6-d7/a3-a4
        rts

; wb_join(a0 = répertoire, a4 = nom, a1 = destination de WB_PATHMAX octets) : « rép:nom » ou « rép/nom », tronqué.
; Préserve a2-a6.
wb_join:
        moveq   #WB_PATHMAX-2,d1
        moveq   #0,d0
.jn_dir:
        move.b  (a0)+,d0
        beq.s   .jn_sep
        move.b  d0,(a1)+
        subq.w  #1,d1
        bgt.s   .jn_dir
        bra.s   .jn_end
.jn_sep:
        cmp.b   #':',-1(a1)
        beq.s   .jn_nm
        move.b  #'/',(a1)+
        subq.w  #1,d1
.jn_nm:
        move.l  a4,a0
.jn_name:
        move.b  (a0)+,(a1)+
        beq.s   .jn_ret
        subq.w  #1,d1
        bgt.s   .jn_name
.jn_end:
        clr.b   (a1)
.jn_ret:
        rts

; wb_opendrawer(a0 = chemin, a1 = titre, a2 = DiskObject (sa DrawerData donne la géométrie), a5) : déjà ouvert ->
; ramené devant ; sinon fiche libre, fenêtre (déplacement, profondeur, fermeture, taille ; IDCMP CLOSEWINDOW |
; REFRESHWINDOW | MOUSEBUTTONS | MENUPICK), menus, icônes lues puis dessinées. Préserve d7/a5.
wb_opendrawer:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a0,d4                ; d4 = chemin, d5 = titre
        move.l  a1,d5
        moveq   #1,d7                ; déjà ouvert ?
.od_find:
        bsr     wb_window
        beq.s   .od_fnx
        lea     DR_PATH(a4),a0
        move.l  d4,a1
        bsr     wb_streq
        bne.s   .od_fnx
        move.l  a3,a0
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_WINDOWTOFRONT(a6)
        bra     .od_ret
.od_fnx:
        addq.w  #1,d7
        cmp.w   #WB_MAXDRAWERS,d7
        bls.s   .od_find
        moveq   #1,d7                ; fiche libre
.od_free:
        bsr     wb_window
        beq.s   .od_slot
        addq.w  #1,d7
        cmp.w   #WB_MAXDRAWERS,d7
        bls.s   .od_free
        bra     .od_ret
.od_slot:
        move.l  d4,a0                ; chemin et titre dans la fiche
        lea     DR_PATH(a4),a1
        moveq   #WB_PATHMAX-2,d0
        bsr     wb_strcpy
        move.l  d5,a0
        lea     DR_TITLE(a4),a1
        moveq   #WBS_NAMEMAX-2,d0
        bsr     wb_strcpy
        lea     -NW_SIZEOF(sp),sp
        bsr     wb_nwclear
        move.l  #$000A0014,NW_LEFTEDGE(a0)   ; par défaut : 10,20 400x120
        move.l  #$01900078,NW_WIDTH(a0)
        move.l  DO_DRAWERDATA(a2),d0
        beq.s   .od_geo
        move.l  d0,a1
        move.l  (a1)+,NW_LEFTEDGE(a0)        ; dd_NewWindow : LeftEdge, TopEdge, Width, Height
        move.l  (a1),NW_WIDTH(a0)
.od_geo:
        move.l  #CLOSEWINDOW|REFRESHWINDOW|MOUSEBUTTONS|MOUSEMOVE|MENUPICK,NW_IDCMPFLAGS(a0)
        move.l  #WINDOWDRAG|WINDOWDEPTH|WINDOWCLOSE|WINDOWSIZING|SIZEBRIGHT,NW_FLAGS(a0)
        lea     DR_TITLE(a4),a1
        move.l  a1,NW_TITLE(a0)
        move.l  #(90<<16)|40,NW_MINWIDTH(a0)
        move.l  #(640<<16)|256,NW_MAXWIDTH(a0)
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_OPENWINDOW(a6)
        lea     NW_SIZEOF(sp),sp
        move.l  d0,DR_WIN(a4)
        beq.s   .od_ret
        move.w  d7,DR_ID(a4)
        move.l  d0,a0
        bsr     wb_setmenus
        bsr     wb_titles
        bsr     wb_loadicons
.od_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; wb_closedrawer(d7.w = tiroir, a5) : ferme sa fenêtre, rend ses icônes, libère la fiche ; la sélection qui s'y
; trouvait disparaît. Préserve d7/a5.
wb_closedrawer:
        movem.l d2/a2-a4/a6,-(sp)
        bsr     wb_window
        beq.s   .cd_ret
        cmp.w   WBS_SELW(a5),d7
        bne.s   .cd_sel
        move.w  #-1,WBS_SELW(a5)
.cd_sel:
        clr.l   DR_WIN(a4)
        move.l  WBS_IBASE(a5),a6
        move.l  a3,a0
        jsr     LVO_CLEARMENUSTRIP(a6)
        move.l  a3,a0
        jsr     LVO_CLOSEWINDOW(a6)
        move.l  DR_NICON(a4),d2
        clr.l   DR_NICON(a4)
        lea     DR_ICONS(a4),a2
        move.l  WBS_ICONBASE(a5),a6
        bra.s   .cd_fnx
.cd_free:
        move.l  (a2)+,a0
        jsr     ICON_LVO_FREEDISKOBJECT(a6)
.cd_fnx:
        dbra    d2,.cd_free
.cd_ret:
        movem.l (sp)+,d2/a2-a4/a6
        rts

; wb_loadicons(a4 = fiche, a5) : parcourt le répertoire du tiroir (Examine / ExNext) ; chaque « nom.info » (sauf
; Disk.info) donne une icône (GetDiskObject du chemin sans « .info ») et son nom, WB_MAXICONS au plus.
; Préserve d2-d7/a2-a6.
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
        lea     -WB_PATHMAX(sp),sp   ; chemin de l'icône
        move.l  WBS_DOSBASE(a5),a6
        lea     DR_PATH(a4),a0
        move.l  a0,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d7                ; d7 = lock
        beq     .li_exerr
        move.l  d7,d1
        move.l  d6,d2
        jsr     DOS_LVO_EXAMINE(a6)
        tst.l   d0
        bne.s   .li_next
        bsr     .li_exam
        bra     .li_unlock
.li_exerr:
        bsr     .li_exam
        bra     .li_free
.li_exam:                            ; « Error while examining <tiroir>: n »
        moveq   #7,d0
        lea     DR_TITLE(a4),a0
        bra     wb_error
.li_next:
        cmp.l   #WB_MAXICONS,DR_NICON(a4)
        bhs     .li_unlock
        move.l  WBS_DOSBASE(a5),a6
        move.l  d7,d1
        move.l  d6,d2
        jsr     DOS_LVO_EXNEXT(a6)
        tst.l   d0
        bne.s   .li_entry
        jsr     DOS_LVO_IOERR(a6)    ; fin normale du répertoire : pas de message
        cmp.l   #ERROR_NO_MORE_ENTRIES,d0
        beq     .li_unlock
        moveq   #0,d0                ; « Error while examining directory: n »
        suba.l  a0,a0
        bsr     wb_error
        bra     .li_unlock
.li_entry:
        move.l  d6,a0
        lea     FIB_FILENAME(a0),a2  ; a2 = nom
        move.l  a2,a0
        bsr     wb_strlen
        move.w  d0,d3                ; d3 = longueur
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
        move.l  DR_NICON(a4),d4      ; nom -> DR_NAMES[n]
        move.w  d4,d0
        mulu    #WBS_NAMEMAX,d0
        move.l  a4,-(sp)
        lea     DR_NAMES(a4,d0.l),a1
        move.l  a2,a0
        move.w  d3,d0
        subq.w  #1,d0
.li_ncp:
        move.b  (a0)+,(a1)+
        dbra    d0,.li_ncp
        clr.b   (a1)
        sub.w   d3,a1                ; a1 = nom recopié
        move.l  a1,a4
        lea     4(sp),a1             ; chemin « répertoire/nom »
        move.l  (sp),a0
        lea     DR_PATH(a0),a0
        bsr     wb_join
        move.l  (sp)+,a4
        move.l  WBS_ICONBASE(a5),a6
        move.l  sp,a0
        jsr     ICON_LVO_GETDISKOBJECT(a6)
        tst.l   d0
        beq     .li_next
        move.l  d4,d1
        lsl.l   #2,d1
        move.l  d0,DR_ICONS(a4,d1.l)
        addq.l  #1,DR_NICON(a4)
        movem.l d6-d7,-(sp)          ; dessinée tout de suite (la lecture de la disquette est lente)
        move.w  DR_ID(a4),d7
        move.w  d4,d6
        bsr     wb_drawone
        movem.l (sp)+,d6-d7
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

; wb_launch(a0 = chemin de l'outil, a1 = chemin du projet | 0, a2 = DiskObject de l'outil (pile) si a1 = 0, a5) :
; LoadSeg de l'outil, message WBStartup (argument 0 = l'outil, 1 = le projet : verrou du répertoire + nom),
; CreateProc puis PutMsg ; le message revient au port « Workbench » à la fin de l'outil (wb_toolreturn).
; Échec (outil introuvable, mémoire) : rien. Préserve d7/a5.
WBSM_SIZE       EQU SM_SIZE+2*WA_SIZE+2*WBS_NAMEMAX ; message + 2 arguments + leurs noms
wb_launch:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.l  a0,a3                ; a3 = outil
        move.l  a1,a4                ; a4 = projet | 0
        move.l  #WB_TOOLSTACK,d6     ; d6 = pile
        move.l  a4,d0
        bne.s   .la_stk
        move.l  DO_STACKSIZE(a2),d0
        cmp.l   d6,d0
        bls.s   .la_stk
        move.l  d0,d6
.la_stk:
        move.l  WBS_DOSBASE(a5),a6
        move.l  a3,d1
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  d0,d5                ; d5 = seglist
        bne.s   .la_seg
        move.l  a3,a0                ; « Error while opening <outil>: n » : nom de l'icône d'un outil (son
        move.l  a4,d0                ; répertoire est le répertoire courant), Default Tool tel quel d'un projet
        bne.s   .la_named
        bsr     wb_base
.la_named:
        moveq   #2,d0
        bsr     wb_error
        bra     .la_ret
.la_seg:
        move.l  ($4).w,a6
        move.l  #WBSM_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .la_unload
        move.l  d0,a2                ; a2 = WBStartup
        lea     SM_SIZE(a2),a0
        move.l  a0,SM_ARGLIST(a2)
        move.l  a3,a0                ; argument 0 : l'outil
        moveq   #0,d2
        bsr     wb_arg
        move.l  a4,d0
        beq.s   .la_proc
        move.l  a4,a0                ; argument 1 : le projet
        moveq   #1,d2
        bsr     wb_arg
.la_proc:
        move.l  SM_ARGLIST(a2),a0
        move.l  WA_NAME(a0),d1       ; nom du process = nom de l'outil
        moveq   #0,d2
        move.l  d5,d3
        move.l  d6,d4
        move.l  WBS_DOSBASE(a5),a6
        jsr     DOS_LVO_CREATEPROC(a6)
        tst.l   d0
        beq.s   .la_noproc
        move.l  d0,a0
        move.b  #NT_MESSAGE,LN_TYPE(a2)
        move.l  WBS_PORT(a5),MN_REPLYPORT(a2)
        move.w  #SM_SIZE,MN_LENGTH(a2)
        move.l  d0,SM_PROCESS(a2)
        move.l  d5,SM_SEGMENT(a2)
        move.l  a2,a1
        move.l  ($4).w,a6
        jsr     LVO_PUTMSG(a6)
        ifeq    PROD
        lea     wb_msgrun(pc),a0
        jsr     ser_puts
        endc
        bra.s   .la_ret
.la_noproc:
        move.l  a2,a1
        bsr     wb_freestartup
        bra.s   .la_ret
.la_unload:
        move.l  WBS_DOSBASE(a5),a6
        move.l  d5,d1
        jsr     DOS_LVO_UNLOADSEG(a6)
.la_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts

; wb_arg(a2 = WBStartup, d2 = n° d'argument, a0 = chemin complet, a5) : wa_Lock = verrou du répertoire (partie avant
; le dernier « / » ou « : » inclus), wa_Name = nom (copié dans le message) ; sm_NumArgs = d2 + 1. Préserve d2-d7/a2-a6.
wb_arg:
        movem.l d2-d4/a2-a4/a6,-(sp)
        move.l  a0,a3
        move.l  a0,a1                ; a1 = début du nom (après le dernier séparateur)
.ag_scan:
        move.b  (a0)+,d0
        beq.s   .ag_split
        cmp.b   #':',d0
        beq.s   .ag_sep
        cmp.b   #'/',d0
        bne.s   .ag_scan
.ag_sep:
        move.l  a0,a1
        bra.s   .ag_scan
.ag_split:
        move.l  SM_ARGLIST(a2),a4
        move.w  d2,d0
        lsl.w   #3,d0
        add.w   d0,a4                ; a4 = WBArg
        move.w  d2,d0
        mulu    #WBS_NAMEMAX,d0
        lea     SM_SIZE+2*WA_SIZE(a2,d0.l),a0
        move.l  a0,WA_NAME(a4)
        exg     a0,a1
        moveq   #WBS_NAMEMAX-2,d0
        bsr     wb_strcpy            ; nom
        move.l  WA_NAME(a4),d4       ; répertoire : copie temporaire du chemin coupée avant le nom
        lea     -WB_PATHMAX(sp),sp
        move.l  a3,a0
        move.l  sp,a1
        moveq   #WB_PATHMAX-2,d0
        bsr     wb_strcpy
        move.l  a3,a0                ; longueur du répertoire = début du nom - début du chemin
        bsr     wb_strlen
        move.l  d4,a0
        move.w  d0,d3
        bsr     wb_strlen
        sub.w   d0,d3                ; d3 = longueur avec le séparateur
        beq.s   .ag_lock
        cmp.b   #'/',-1(sp,d3.w)
        bne.s   .ag_cut
        subq.w  #1,d3                ; « rép/nom » -> « rép »
.ag_cut:
        clr.b   0(sp,d3.w)
.ag_lock:
        move.l  WBS_DOSBASE(a5),a6
        move.l  sp,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,WA_LOCK(a4)
        lea     WB_PATHMAX(sp),sp
        move.l  (sp),d2
        addq.l  #1,d2
        move.l  d2,SM_NUMARGS(a2)
        movem.l (sp)+,d2-d4/a2-a4/a6
        rts

; wb_toolreturn(a1 = WBStartup rendu, a5) : l'outil est fini : segment déchargé, verrous rendus, message libéré.
; Préserve d2-d7/a2-a5.
wb_toolreturn:
        move.l  a1,-(sp)
        move.l  WBS_DOSBASE(a5),a6
        move.l  SM_SEGMENT(a1),d1
        jsr     DOS_LVO_UNLOADSEG(a6)
        move.l  (sp)+,a1
        ifeq    PROD
        move.l  a1,-(sp)
        lea     wb_msgend(pc),a0
        jsr     ser_puts
        move.l  (sp)+,a1
        endc
; wb_freestartup(a1 = WBStartup, a5) : rend les verrous de ses arguments et libère le message.
wb_freestartup:
        movem.l d2/a2,-(sp)
        move.l  a1,a2
        move.l  SM_NUMARGS(a2),d2
        move.l  SM_ARGLIST(a2),a1
        move.l  WBS_DOSBASE(a5),a6
        bra.s   .fs_nx
.fs_lp:
        move.l  WA_LOCK(a1),d1
        move.l  a1,-(sp)
        jsr     DOS_LVO_UNLOCK(a6)
        move.l  (sp)+,a1
        addq.l  #WA_SIZE,a1
.fs_nx:
        dbra    d2,.fs_lp
        move.l  a2,a1
        move.l  #WBSM_SIZE,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        movem.l (sp)+,d2/a2
        rts

; wb_menupick(d3.w = code, d7.w = fenêtre, a5) : Workbench/Open -> ouvre l'icône sélectionnée ; Workbench/Close ->
; ferme ce tiroir ; Special/Redraw -> efface et redessine toutes les fenêtres. Préserve d7/a5.
wb_menupick:
        bsr     wb_restore           ; tout choix de menu rend le titre mémoire (spec §6.2)
        cmp.w   #MENUNULL,d3
        beq     .mp_ret
        move.w  d3,d0
        and.w   #$1F,d0              ; menu
        move.w  d3,d1
        lsr.w   #5,d1
        and.w   #$3F,d1              ; élément
        tst.w   d0
        bne.s   .mp_special
        tst.w   d1
        bne.s   .mp_close
        move.w  WBS_SELW(a5),d0      ; Open
        bmi     .mp_ret
        move.l  d7,-(sp)
        move.w  d0,d7
        move.w  WBS_SELI(a5),d1
        bsr     wb_openicon
        move.l  (sp)+,d7
        rts
.mp_close:
        cmp.w   #5,d1
        beq     wb_discard
        cmp.w   #2,d1
        beq     wb_duplicate
        cmp.w   #4,d1
        beq     wb_info
        cmp.w   #3,d1
        beq     wb_rename
        cmp.w   #1,d1
        bne     .mp_ret
        tst.w   d7
        beq     .mp_ret
        bra     wb_closedrawer
.mp_special:
        cmp.w   #2,d0
        bne     .mp_ret
        cmp.w   #3,d1
        beq     wb_snapshot
        tst.w   d1                   ; Clean Up
        beq     wb_cleanup
        cmp.w   #4,d1
        beq     wb_version
        cmp.w   #1,d1
        beq     wb_lasterr
        cmp.w   #2,d1                ; Redraw
        bne     .mp_ret
        move.l  d7,-(sp)
        moveq   #0,d7
.mp_rd:
        bsr     wb_redraw1
.mp_rnx:
        addq.w  #1,d7
        cmp.w   #WB_MAXDRAWERS,d7
        bls.s   .mp_rd
        move.l  (sp)+,d7
.mp_ret:
        rts

; wb_timeropen(a5) : timer.device (unité VBLANK) sur la timerequest de l'état, réponse sur le port public ; puis premier
; tic. Sans timer : pas de tic (le titre d'écran reste celui de l'écran).
wb_timeropen:
        lea     WBS_TREQ(a5),a1
        move.l  WBS_PORT(a5),MN_REPLYPORT(a1)
        lea     wb_timername(pc),a0
        moveq   #UNIT_VBLANK,d0
        moveq   #0,d1
        move.l  ($4).w,a6
        jsr     LVO_OPENDEVICE(a6)
        tst.l   d0
        bne.s   .to_ret
        st      WBS_TON(a5)
        moveq   #-1,d0
        move.l  d0,WBS_MEMV(a5)
        bra.s   wb_tick
.to_ret:
        rts

; wb_tick(a5) : tic de 5 s (spec workbench-task-v34 §3.4). AvailMem(0) ; si la valeur a changé, le titre d'écran est
; reformaté (« Workbench release 1.2.  %ld free memory », que le SetWindowTitles détourné par LoadWB 1.3.3 retouche)
; et appliqué aux fenêtres ; puis la requête repart pour 5 s. Préserve d2-d7/a2-a6.
wb_tick:
        movem.l a2-a3/a6,-(sp)
        bsr.s   wb_memtitle
        lea     WBS_TREQ(a5),a1
        move.w  #TR_ADDREQUEST,IO_COMMAND(a1)
        move.l  #5,TV_SECS(a1)
        clr.l   TV_MICRO(a1)
        move.l  ($4).w,a6
        jsr     LVO_SENDIO(a6)
        movem.l (sp)+,a2-a3/a6
        rts
wb_putch:
        move.b  d0,(a3)+
        rts

; wb_memtitle(a5) : partie titre du tic. Message affiché : rien. Sinon AvailMem(0) ; valeur changée : titre mémoire
; reformaté, puis appliqué aux fenêtres sauf pendant un Rename (titre verrouillé). Préserve d2-d7/a2-a6.
wb_memtitle:
        btst    #2,WBS_FLAGS(a5)
        bne.s   .mt_ret
        movem.l a2-a3/a6,-(sp)
        move.l  ($4).w,a6
        moveq   #0,d1
        jsr     LVO_AVAILMEM(a6)
        cmp.l   WBS_MEMV(a5),d0
        beq.s   .mt_pop
        move.l  d0,WBS_MEMV(a5)
        lea     wb_relfmt(pc),a0
        lea     WBS_MEMV(a5),a1
        lea     wb_putch(pc),a2
        lea     WBS_TBUF(a5),a3
        jsr     LVO_RAWDOFMT(a6)
        btst    #1,WBS_FLAGS(a5)
        bne.s   .mt_pop
        bsr     wb_titles
.mt_pop:
        movem.l (sp)+,a2-a3/a6
.mt_ret:
        rts

; wb_restore(a5) : un message était affiché (et le titre n'est pas verrouillé) : le titre mémoire revient sur les
; fenêtres. Appelé au début de tout MENUPICK et sur SELECTDOWN. Préserve d2-d7/a2-a6.
wb_restore:
        btst    #1,WBS_FLAGS(a5)
        bne.s   .rs_ret
        bclr    #2,WBS_FLAGS(a5)
        bne     wb_titles
.rs_ret:
        rts

; wb_message(a0 = format | WBS_MSGBUF, a1 = arguments longs, a5) : un message est déjà affiché : rien (le premier
; reste). Sinon il devient le titre d'écran de toutes les fenêtres du Workbench ; un nouveau format est précédé d'un
; DisplayBeep puis formaté dans WBS_MSGBUF, WBS_MSGBUF lui-même est réaffiché tel quel. Le titre mémoire revient au
; prochain clic ou choix de menu. Préserve d2-d7/a2-a6.
wb_message:
        bset    #2,WBS_FLAGS(a5)
        bne.s   .ms_ret
        movem.l a2-a3/a6,-(sp)
        lea     WBS_MSGBUF(a5),a3
        cmp.l   a3,a0
        beq.s   .ms_show
        st      WBS_MSGOK(a5)
        movem.l a0-a1,-(sp)
        move.l  WBS_WIN(a5),d0
        beq.s   .ms_nobeep
        move.l  d0,a0
        move.l  WD_WSCREEN(a0),a0
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_DISPLAYBEEP(a6)
.ms_nobeep:
        movem.l (sp)+,a0-a1
        lea     wb_putch(pc),a2
        move.l  ($4).w,a6
        jsr     LVO_RAWDOFMT(a6)
.ms_show:
        lea     WBS_MSGBUF(a5),a2
        bsr     wb_apply
        movem.l (sp)+,a2-a3/a6
.ms_ret:
        rts

; wb_error(d0.w = action, a0 = nom | 0, a5) : « Error while <action>: <IoErr> » en titre d'écran (spec §6.5, §6.9) ;
; IoErr est lu avant tout autre appel dos. L'action vient de wb_errtab (%s = nom). Comme tout message : le premier
; affiché reste jusqu'au prochain clic ou menu. Préserve d2-d7/a2-a6.
WE_BUF          EQU 0                ; action formatée (WBS_TBUFMAX)
WE_ARGS         EQU WE_BUF+WBS_TBUFMAX ; « Error while %s: %ld » : action, erreur
WE_NAME         EQU WE_ARGS+8        ; argument %s de l'action
WE_SIZE         EQU WE_NAME+4
wb_error:
        movem.l d2/a2-a3/a6,-(sp)
        lea     -WE_SIZE(sp),sp
        move.l  a0,WE_NAME(sp)
        move.w  d0,d2
        move.l  WBS_DOSBASE(a5),a6
        jsr     DOS_LVO_IOERR(a6)
        move.l  d0,WE_ARGS+4(sp)
        lea     wb_errtab(pc),a0
        add.w   d2,d2
        add.w   0(a0,d2.w),a0        ; a0 = texte de l'action
        lea     WE_NAME(sp),a1
        lea     wb_putch(pc),a2
        lea     WE_BUF(sp),a3
        move.l  ($4).w,a6
        jsr     LVO_RAWDOFMT(a6)
        lea     WE_BUF(sp),a0
        move.l  a0,WE_ARGS(sp)
        lea     wb_errfmt(pc),a0
        lea     WE_ARGS(sp),a1
        bsr     wb_message
        lea     WE_SIZE(sp),sp
        movem.l (sp)+,d2/a2-a3/a6
        rts

; wb_base(a0 = chemin) -> a0 = son dernier composant (après le dernier « : » ou « / »). Clobbe d0/a1.
wb_base:
        move.l  a0,a1
.bs_lp:
        move.b  (a1)+,d0
        beq.s   .bs_ret
        cmp.b   #':',d0
        beq.s   .bs_cut
        cmp.b   #'/',d0
        bne.s   .bs_lp
.bs_cut:
        move.l  a1,a0
        bra.s   .bs_lp
.bs_ret:
        rts

; wb_version(a5) : Special/Version (spec §6.3). Kickstart : version et révision de l'en-tête de la ROM (mots en +$0C et
; +$0E, la ROM commençant à $1000000 - sa taille, rangée en $FFFFEC). Workbench : lib_Version et lib_Revision de
; version.library (ouverte en version 0, chargée de LIBS: au besoin), -1 et -1 sans elle.
wb_version:
        movem.l a6,-(sp)
        lea     -16(sp),sp
        move.l  #$1000000,d0
        sub.l   $FFFFEC,d0
        move.l  d0,a0
        moveq   #0,d0
        move.w  $0C(a0),d0
        move.l  d0,(sp)
        moveq   #0,d0
        move.w  $0E(a0),d0
        move.l  d0,4(sp)
        moveq   #-1,d0
        move.l  d0,8(sp)
        move.l  d0,12(sp)
        move.l  ($4).w,a6
        lea     wb_vername(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   .vr_show
        move.l  d0,a1
        moveq   #0,d0
        move.w  LIB_VERSION(a1),d0
        move.l  d0,8(sp)
        moveq   #0,d0
        move.w  LIB_REVISION(a1),d0
        move.l  d0,12(sp)
        jsr     LVO_CLOSELIBRARY(a6)
.vr_show:
        lea     wb_verfmt(pc),a0
        move.l  sp,a1
        bsr     wb_message
        lea     16(sp),sp
        movem.l (sp)+,a6
        rts

; wb_lasterr(a5) : Special/Last Error (spec §6.5) : le dernier message, réaffiché sans bip ; aucun encore : bip et
; titre vide.
wb_lasterr:
        lea     WBS_MSGBUF(a5),a0
        tst.b   WBS_MSGOK(a5)
        bne     wb_message
        lea     wb_empty(pc),a0
        bra     wb_message

; wb_titles(a5) : le titre mémoire (WBS_TBUF) sur toutes les fenêtres du Workbench ; encore vide : rien. Préserve
; d2-d7/a2-a6.
wb_titles:
        tst.b   WBS_TBUF(a5)
        beq.s   .ti_none
        move.l  a2,-(sp)
        lea     WBS_TBUF(a5),a2
        bsr.s   wb_apply
        move.l  (sp)+,a2
.ti_none:
        rts
; wb_apply(a2 = titre d'écran, a5) : SetWindowTitles(fenêtre, -1, a2) sur la fenêtre de fond et chaque tiroir ouvert.
; Préserve d2-d7/a2-a6.
wb_apply:
        movem.l d2/a2/a4/a6,-(sp)
        move.l  WBS_IBASE(a5),a6
        move.l  WBS_WIN(a5),d0
        beq.s   .ti_dr
        bsr.s   .ti_one
.ti_dr:
        lea     WBS_DRAWERS(a5),a4
        moveq   #WB_MAXDRAWERS-1,d2
.ti_lp:
        move.l  DR_WIN(a4),d0
        beq.s   .ti_nx
        bsr.s   .ti_one
.ti_nx:
        lea     DR_SIZE(a4),a4
        dbra    d2,.ti_lp
.ti_ret:
        movem.l (sp)+,d2/a2/a4/a6
        rts
.ti_one:
        move.l  d0,a0
        move.l  #-1,a1
        jmp     LVO_SETWINDOWTITLES(a6)

; wb_cleanup(d7.w = fenêtre, a5) : Special/Clean Up (sondé sur la vraie 1.3). Les icônes du tiroir, triées par position
; actuelle (X puis Y ; sans position : en dernier), sont rangées par colonnes de haut en bas dans des cellules de
; CU_CELL de large, chacune centrée dans sa cellule ; écart vertical CU_GAPY sous chaque icône (nom compris). Colonne
; suivante quand l'icône dépasserait la hauteur intérieure qu'aurait la fenêtre sous la 1.3 (titre + barre de
; défilement basse = CU_FRAMEH lignes). Positions en mémoire seulement (Snapshot les écrit). Bureau : rien.
CU_CELL         EQU 96
CU_GAPY         EQU 11
CU_FRAMEH       EQU 20
wb_cleanup:
        movem.l d2-d7/a2-a4,-(sp)
        tst.w   d7
        beq     .cu_ret
        bsr     wb_window
        beq     .cu_ret
        move.l  DR_NICON(a4),d6
        beq     .cu_ret
        lea     -WB_MAXICONS(sp),sp  ; ordre : n° d'icônes
        moveq   #0,d0
.cu_init:
        move.b  d0,0(sp,d0.w)
        addq.w  #1,d0
        cmp.w   d6,d0
        blt.s   .cu_init
        moveq   #1,d2                ; tri par insertion (stable)
.cu_si:
        cmp.w   d6,d2
        bge.s   .cu_sorted
        move.b  0(sp,d2.w),d3
        move.w  d2,d4
.cu_sj:
        tst.w   d4
        beq.s   .cu_put
        move.b  -1(sp,d4.w),d5
        move.b  d5,d0
        move.b  d3,d1
        bsr     cu_less              ; d0 = 1 si l'icône d3 précède l'icône d5
        tst.l   d0
        beq.s   .cu_put
        move.b  d5,0(sp,d4.w)
        subq.w  #1,d4
        bra.s   .cu_sj
.cu_put:
        move.b  d3,0(sp,d4.w)
        addq.w  #1,d2
        bra.s   .cu_si
.cu_sorted:
        move.w  WD_HEIGHT(a3),d5
        sub.w   #CU_FRAMEH,d5        ; d5 = hauteur utile
        moveq   #0,d2                ; d2 = gauche de la colonne
        moveq   #0,d3                ; d3 = y courant
        moveq   #CU_CELL,d4          ; d4 = largeur de la colonne (une icône plus large l'élargit)
        moveq   #0,d1
.cu_lp:
        cmp.w   d6,d1
        bge.s   .cu_done
        moveq   #0,d0
        move.b  0(sp,d1.w),d0
        lsl.w   #2,d0
        move.l  DR_ICONS(a4,d0.w),a2
        tst.w   d3
        beq.s   .cu_fit
        move.w  d3,d0
        add.w   DO_GADGET+GG_HEIGHT(a2),d0
        add.w   #CU_GAPY,d0
        cmp.w   d5,d0
        ble.s   .cu_fit
        add.w   d4,d2                ; colonne suivante
        moveq   #0,d3
        moveq   #CU_CELL,d4
.cu_fit:
        move.w  DO_GADGET+GG_WIDTH(a2),d0
        cmp.w   d4,d0
        ble.s   .cu_wok
        move.w  d0,d4
.cu_wok:
        neg.w   d0
        add.w   #CU_CELL,d0          ; marge = (cellule - largeur) / 2, nulle si l'icône est plus large
        bpl.s   .cu_mg
        moveq   #0,d0
.cu_mg:
        lsr.w   #1,d0
        add.w   d2,d0
        ext.l   d0
        move.l  d0,DO_CURRENTX(a2)
        move.w  d3,d0
        ext.l   d0
        move.l  d0,DO_CURRENTY(a2)
        add.w   DO_GADGET+GG_HEIGHT(a2),d3
        add.w   #CU_GAPY,d3
        addq.w  #1,d1
        bra.s   .cu_lp
.cu_done:
        lea     WB_MAXICONS(sp),sp
        bsr     wb_redraw1
.cu_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; cu_less(d0.b = icône a, d1.b = icône b, a4 = fiche) -> d0 = 1 si b précède a (X puis Y ; sans position = en
; dernier), 0 sinon. Préserve d2-d7/a1-a6.
cu_less:
        movem.l d2-d3,-(sp)
        move.b  d1,-(sp)
        bsr.s   cu_key
        move.l  d0,d2
        move.l  d1,d3
        move.b  (sp)+,d0
        bsr.s   cu_key
        cmp.l   d2,d0
        blt.s   .cl_yes
        bgt.s   .cl_no
        cmp.l   d3,d1
        blt.s   .cl_yes
.cl_no:
        moveq   #0,d0
        bra.s   .cl_ret
.cl_yes:
        moveq   #1,d0
.cl_ret:
        movem.l (sp)+,d2-d3
        rts
; cu_key(d0.b = icône, a4) -> d0/d1 = X/Y de tri. Clobbe a0.
cu_key:
        and.w   #$FF,d0
        lsl.w   #2,d0
        move.l  DR_ICONS(a4,d0.w),a0
        move.l  DO_CURRENTX(a0),d0
        move.l  DO_CURRENTY(a0),d1
        cmp.l   #NO_ICON_POSITION,d0
        bne.s   .ck_ret
        move.l  #$7FFFFFFF,d0
        move.l  d0,d1
.ck_ret:
        rts

; wb_snapshot(a5) : Special/Snapshot. La position de l'icône sélectionnée est mise dans son DiskObject puis écrite
; dans son « .info » (PutDiskObject) ; disque ou tiroir dont la fenêtre est ouverte : la géométrie de cette fenêtre va
; aussi dans dd_NewWindow (rouverte au même endroit). Requesters de dos coupés pendant l'écriture (pr_WindowPtr = -1).
wb_snapshot:
        movem.l d2-d7/a2-a4/a6,-(sp)
        lea     -WB_PATHMAX(sp),sp
        move.w  WBS_SELW(a5),d7
        bmi     .ss_ret
        move.w  WBS_SELI(a5),d1
        bsr     wb_iconrect          ; a2 = DiskObject, d0/d1 = coin dans la fenêtre
        beq     .ss_ret
        tst.w   d7
        bne.s   .ss_dr
        lea     wb_diskname(pc),a0   ; disque : SYS:Disk, sa fenêtre est la racine SYS:
        move.l  sp,a1
        movem.w d0-d1,-(sp)
        moveq   #WB_PATHMAX-2,d0
        bsr     wb_strcpy
        movem.w (sp)+,d0-d1
        lea     wb_sysname(pc),a3
        bra.s   .ss_pos
.ss_dr:
        movem.w d0-d1,-(sp)
        bsr     wb_window            ; a3 = fenêtre, a4 = fiche (d0 écrasé)
        movem.w (sp)+,d0-d1
        moveq   #0,d2                ; DO_Current* est relatif à l'intérieur du tiroir
        move.b  WD_BORDERLEFT(a3),d2
        sub.w   d2,d0
        move.b  WD_BORDERTOP(a3),d2
        sub.w   d2,d1
        move.w  WBS_SELI(a5),d2
        mulu    #WBS_NAMEMAX,d2
        movem.w d0-d1,-(sp)
        move.l  a4,-(sp)
        lea     DR_PATH(a4),a0
        lea     8(sp),a1
        lea     DR_NAMES(a4,d2.l),a4
        bsr     wb_join
        move.l  (sp)+,a4
        movem.w (sp)+,d0-d1
        move.l  sp,a3                ; fenêtre éventuelle : celle de ce chemin
.ss_pos:
        ext.l   d0
        ext.l   d1
        move.l  d0,DO_CURRENTX(a2)
        move.l  d1,DO_CURRENTY(a2)
        move.l  DO_DRAWERDATA(a2),d5 ; d5 = dd_NewWindow | 0
        beq.s   .ss_put
        move.l  a3,d6                ; d6 = chemin dont on cherche la fenêtre
        moveq   #1,d7
.ss_find:
        bsr     wb_window            ; a3 = fenêtre, a4 = fiche
        beq.s   .ss_fnx
        move.l  d6,a0
        lea     DR_PATH(a4),a1
        bsr     wb_streq
        bne.s   .ss_fnx
        move.l  d5,a1
        move.l  WD_LEFTEDGE(a3),(a1)+        ; LeftEdge, TopEdge, Width, Height
        move.l  WD_WIDTH(a3),(a1)
        bra.s   .ss_put
.ss_fnx:
        addq.w  #1,d7
        cmp.w   #WB_MAXDRAWERS,d7
        bls.s   .ss_find
.ss_put:
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a3
        move.l  PR_WINDOWPTR(a3),-(sp)
        move.l  #-1,PR_WINDOWPTR(a3)
        lea     4(sp),a0
        move.l  a2,a1
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_PUTDISKOBJECT(a6)
        move.l  (sp)+,PR_WINDOWPTR(a3)
        tst.l   d0
        bne.s   .ss_ret
        moveq   #8,d0                ; « Error while writing <nom>: n » (« Disk » pour le disque)
        move.l  sp,a0
        bsr     wb_base
        bsr     wb_error
.ss_ret:
        lea     WB_PATHMAX(sp),sp
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts

; wb_info(a5) : Workbench/Info (spec workbench-task-v34 §7). La fenêtre Info est celle de libs:info.library (disque),
; appelée de façon synchrone : LVO -30, A0 = A6 = sa base, A1 = un WBObject. Celui-ci est fabriqué par icon.library
; (GetWBObject, dans le répertoire de l'icône ; « Disk » pour le disque), complété du nom (inscrit dans sa FreeList) et du
; lock du répertoire contenant (+$A4 ; disque : aussi DrawerData+$1BA). info.library change pr_CurrentDir sans le
; rendre : le répertoire courant du Workbench est rétabli après. Sans info.library : « Info not available ». Au retour,
; le tiroir est relu (SAVE a pu modifier l'icône) et l'objet rendu par FreeWBObject.
wb_info:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.w  WBS_SELW(a5),d7
        bmi     .if_ret
        bne.s   .if_dr
        lea     wb_sysname(pc),a0    ; disque : racine, icône « Disk »
        lea     wb_diskicon(pc),a3
        bra.s   .if_lock
.if_dr:
        bsr     wb_window            ; a4 = fiche du tiroir
        beq     .if_ret
        move.w  WBS_SELI(a5),d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a3 ; a3 = nom de l'icône
        lea     DR_PATH(a4),a0
.if_lock:
        move.l  a0,d1
        moveq   #SHARED_LOCK,d2
        move.l  WBS_DOSBASE(a5),a6
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d6                ; d6 = lock du répertoire contenant
        beq     .if_ret
        move.l  ($4).w,a6
        lea     wb_infolib(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,d5                ; d5 = InfoBase
        bne.s   .if_lib
        lea     wb_noinfo(pc),a0
        suba.l  a1,a1
        bsr     wb_message
        bra     .if_unlock
.if_lib:
        move.l  WBS_DOSBASE(a5),a6
        move.l  d6,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        move.l  d0,d4                ; d4 = répertoire courant du Workbench
        move.l  a3,a0
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_GETWBOBJECT(a6)
        move.l  d0,a2                ; a2 = WBObject
        tst.l   d0
        beq     .if_close
        move.l  a3,a0                ; nom : copie inscrite dans la FreeList (rendue avec l'objet)
        bsr     wb_strlen
        addq.l  #1,d0
        move.l  d0,d3
        moveq   #0,d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .if_free
        move.l  d0,a1
        move.l  a3,a0
.if_cpy:
        move.b  (a0)+,(a1)+
        bne.s   .if_cpy
        move.l  d0,WBO_NAME(a2)
        move.l  a2,-(sp)
        lea     WBO_FREE(a2),a0
        move.l  d0,a1
        move.l  d3,a2
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_ADDFREELIST(a6)
        move.l  (sp)+,a2
        tst.l   d0
        bne.s   .if_named
        move.l  WBO_NAME(a2),a1      ; non inscrit : rendu tout de suite, pas d'Info
        move.l  d3,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        bra.s   .if_free
.if_named:
        move.l  d6,WBO_LOCK(a2)
        tst.w   d7
        bne.s   .if_call
        move.l  WBO_DRAWER(a2),d0    ; disque : lock de la racine aussi dans son DrawerData
        beq.s   .if_call
        move.l  d0,a0
        move.l  d6,WBD_LOCK(a0)
.if_call:
        move.l  d5,a6
        move.l  d5,a0
        move.l  a2,a1
        jsr     -30(a6)
.if_free:
        move.l  a2,a0
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_FREEWBOBJECT(a6)
.if_close:
        move.l  WBS_DOSBASE(a5),a6
        move.l  d4,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        move.l  ($4).w,a6
        move.l  d5,a1
        jsr     LVO_CLOSELIBRARY(a6)
        tst.w   d7
        beq.s   .if_unlock
        bsr     wb_reload
.if_unlock:
        move.l  WBS_DOSBASE(a5),a6
        move.l  d6,d1
        jsr     DOS_LVO_UNLOCK(a6)
.if_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts

; wb_duplicate(a5) : Workbench/Duplicate (spec workbench-task-v34 §7.9). Disque : son outil par défaut (DiskCopy)
; est lancé avec le disque en argument, « This disk cannot be copied » sans outil. Autre icône : nouveau nom par
; BumpRevision (« copy of … », 25 caractères au plus) ; l'icône de l'original, décalée de +30/+15, est écrite sous
; ce nom par PutWBObject AVANT les données ; elle est relue (échec : « Cannot read info file <nom> », rien n'est
; copié) et ajoutée au tiroir sans le relire, l'original restant sélectionné ; puis l'objet est copié (wb_cptree).
DU_NEW          EQU 0                ; nouveau nom
DU_SRC          EQU DU_NEW+WBS_NAMEMAX   ; chemin de l'original
DU_DST          EQU DU_SRC+WB_PATHMAX    ; chemin de la copie
DU_ARG          EQU DU_DST+WB_PATHMAX    ; argument du message « Cannot read info file %s »
DU_SIZE         EQU DU_ARG+4
DU_NAMEMAX      EQU 25
wb_duplicate:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.w  WBS_SELW(a5),d7
        bmi     .du_ret
        bne.s   .du_obj
        move.l  WBS_DOBJ(a5),d0      ; disque
        beq     .du_ret
        move.l  d0,a2
        move.l  DO_DEFAULTTOOL(a2),d0
        bne.s   .du_tool
        lea     wb_nodiskcopy(pc),a0
        suba.l  a1,a1
        bsr     wb_message
        bra     .du_ret
.du_tool:
        move.l  d0,a0
        lea     wb_sysname(pc),a1
        bsr     wb_launch
        bra     .du_ret
.du_obj:
        move.w  WBS_SELI(a5),d6
        bsr     wb_window
        beq     .du_ret
        lea     -DU_SIZE(sp),sp
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a2 ; a2 = nom de l'original
        lea     DR_PATH(a4),a0
        move.l  WBS_DOSBASE(a5),a6
        move.l  a0,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d5                ; d5 = verrou du tiroir
        beq     .du_free
        move.l  d5,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        move.l  d0,d4                ; d4 = ancien répertoire courant
        move.l  a2,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d3                ; d3 = verrou de l'original
        bne.s   .du_bump
        moveq   #1,d0                ; « accessing <nom> »
        move.l  a2,a0
        bsr     wb_error
        bra     .du_cd
.du_bump:
        lea     DU_NEW(sp),a0
        move.l  a2,a1
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_BUMPREVISION(a6)
        clr.b   DU_NEW+DU_NAMEMAX(sp)
        move.l  a2,a0                ; icône de la copie : celle de l'original, décalée, écrite sous le nouveau nom
        jsr     ICON_LVO_GETWBOBJECT(a6)
        tst.l   d0
        beq     .du_unlock
        move.l  d0,a3                ; a3 = WBObject de l'original
        movem.l WBO_CURX(a3),d0-d1
        movem.l d0-d1,-(sp)
        add.l   #30,WBO_CURX(a3)
        add.l   #15,WBO_CURY(a3)
        move.l  WBO_NAME(a3),-(sp)
        lea     12+DU_NEW(sp),a0
        move.l  a0,WBO_NAME(a3)
        move.l  a3,a1
        jsr     ICON_LVO_PUTWBOBJECT(a6)
        move.l  (sp)+,WBO_NAME(a3)
        movem.l (sp)+,d0-d1
        movem.l d0-d1,WBO_CURX(a3)
        move.l  a3,a0
        jsr     ICON_LVO_FREEWBOBJECT(a6)
        move.l  a4,-(sp)             ; chemins de l'original et de la copie
        lea     DR_PATH(a4),a0
        lea     4+DU_DST(sp),a1
        lea     4+DU_NEW(sp),a4
        bsr     wb_join
        move.l  a2,a4
        move.l  (sp),a0
        lea     DR_PATH(a0),a0
        lea     4+DU_SRC(sp),a1
        bsr     wb_join
        move.l  (sp)+,a4
        lea     DU_DST(sp),a0        ; relecture de l'icône de la copie
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_GETDISKOBJECT(a6)
        tst.l   d0
        bne.s   .du_icon
        lea     DU_NEW(sp),a0
        move.l  a0,DU_ARG(sp)
        lea     wb_noinfofile(pc),a0
        lea     DU_ARG(sp),a1
        bsr     wb_message
        bra     .du_unlock
.du_icon:
        move.l  d0,a3                ; a3 = DiskObject de la copie
        bsr     .du_place
        lea     DU_SRC(sp),a0
        lea     DU_DST(sp),a1
        bsr     wb_cptree
.du_unlock:
        move.l  WBS_DOSBASE(a5),a6
        move.l  d3,d1
        jsr     DOS_LVO_UNLOCK(a6)
.du_cd:
        move.l  WBS_DOSBASE(a5),a6
        move.l  d4,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        move.l  d5,d1
        jsr     DOS_LVO_UNLOCK(a6)
.du_free:
        lea     DU_SIZE(sp),sp
.du_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts
; .du_place(a3 = DiskObject, a4 = tiroir, d7 = son n°, nom en 4+DU_NEW(sp)) : une icône du même nom est remplacée
; (le tiroir est alors redessiné), sinon la copie est ajoutée et dessinée. Plus de place : icône rendue.
.du_place:
        movem.l d2/d6/a2,-(sp)
        moveq   #0,d6                ; d6 = indice
.dp_find:
        cmp.l   DR_NICON(a4),d6
        bhs.s   .dp_add
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a0
        lea     16+DU_NEW(sp),a1
        bsr     wb_streq
        beq.s   .dp_same
        addq.l  #1,d6
        bra.s   .dp_find
.dp_same:
        move.l  d6,d0
        lsl.l   #2,d0
        move.l  DR_ICONS(a4,d0.l),a0
        move.l  a3,DR_ICONS(a4,d0.l)
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_FREEDISKOBJECT(a6)
        bsr     wb_redraw1
        bra.s   .dp_ret
.dp_add:
        cmp.l   #WB_MAXICONS,d6
        blo.s   .dp_new
        move.l  a3,a0
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_FREEDISKOBJECT(a6)
        bra.s   .dp_ret
.dp_new:
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a1
        lea     16+DU_NEW(sp),a0
        moveq   #WBS_NAMEMAX-1,d0
        bsr     wb_strcpy
        move.l  d6,d0
        lsl.l   #2,d0
        move.l  a3,DR_ICONS(a4,d0.l)
        addq.l  #1,DR_NICON(a4)
        bsr     wb_drawone
.dp_ret:
        movem.l (sp)+,d2/d6/a2
        rts

; wb_discard(a5) : Workbench/Discard. L'icône sélectionnée d'un tiroir (pas le disque) : confirmation par
; AutoRequest, puis l'objet (un tiroir avec tout son contenu) et son « .info » sont supprimés et le tiroir est relu.
DS_PATH         EQU 0                ; chemin de l'objet (WB_PATHMAX)
DS_QUEST        EQU DS_PATH+WB_PATHMAX   ; « OK to discard <nom>? »
DS_IT           EQU DS_QUEST+WBS_NAMEMAX+16  ; 5 IntuiText : 3 lignes, « Discard », « Cancel »
DS_SIZE         EQU DS_IT+5*IT_SIZEOF
wb_discard:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.w  WBS_SELW(a5),d7
        ble     .dc_ret              ; aucune sélection (-1) ou l'icône du disque (0)
        move.w  WBS_SELI(a5),d6
        bsr     wb_window
        beq     .dc_ret
        lea     -DS_SIZE(sp),sp
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a2 ; a2 = nom de l'icône
        move.l  a4,-(sp)
        lea     DR_PATH(a4),a0
        lea     4+DS_PATH(sp),a1
        move.l  a2,a4
        bsr     wb_join
        move.l  (sp)+,a4
        lea     DS_QUEST(sp),a1      ; question : « OK to discard <nom>? »
        lea     wbs_dsq(pc),a0
.dc_q1:
        move.b  (a0)+,(a1)+
        bne.s   .dc_q1
        subq.l  #1,a1
        move.l  a2,a0
.dc_q2:
        move.b  (a0)+,(a1)+
        bne.s   .dc_q2
        move.b  #'?',-1(a1)
        clr.b   (a1)
        lea     DS_IT(sp),a0         ; corps : trois lignes chaînées
        lea     wbs_dsw1(pc),a1
        moveq   #4,d1
        bsr     wb_itext
        lea     wbs_dsw2(pc),a1
        moveq   #14,d1
        bsr     wb_itext
        lea     DS_QUEST(sp),a1
        moveq   #24,d1
        bsr     wb_itext
        clr.l   IT_NEXTTEXT-IT_SIZEOF(a0)   ; fin du corps
        lea     wbs_discard(pc),a1   ; gadgets
        moveq   #3,d1
        bsr     wb_itext
        clr.l   IT_NEXTTEXT-IT_SIZEOF(a0)
        lea     wbs_cancel(pc),a1
        moveq   #3,d1
        bsr     wb_itext
        clr.l   IT_NEXTTEXT-IT_SIZEOF(a0)
        move.l  a3,a0                ; AutoRequest(fenêtre du tiroir, corps, Discard, Cancel, 0, 0, 320, 80)
        lea     DS_IT(sp),a1
        lea     DS_IT+3*IT_SIZEOF(sp),a2
        lea     DS_IT+4*IT_SIZEOF(sp),a3
        moveq   #0,d0
        moveq   #0,d1
        move.l  #320,d2
        moveq   #80,d3
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_AUTOREQUEST(a6)
        tst.l   d0
        beq.s   .dc_free
        bsr     wb_deselect
        lea     DS_PATH(sp),a0
        bsr     wb_rmtree
        lea     DS_PATH(sp),a0       ; puis « <chemin>.info »
        bsr     wb_strlen
        cmp.w   #WB_PATHMAX-6,d0
        bhs.s   .dc_reload
        lea     0(a0,d0.w),a1
        lea     wb_infosuffix(pc),a0
.dc_inf:
        move.b  (a0)+,(a1)+
        bne.s   .dc_inf
        lea     DS_PATH(sp),a0
        move.l  a0,d1
        move.l  WBS_DOSBASE(a5),a6
        jsr     DOS_LVO_DELETEFILE(a6)
        tst.l   d0
        bne.s   .dc_reload
        jsr     DOS_LVO_IOERR(a6)
        cmp.l   #ERROR_OBJECT_NOT_FOUND,d0
        beq.s   .dc_reload           ; pas de .info : rien à dire
        moveq   #6,d0                ; « Error while removing <nom>.info: n »
        lea     DS_PATH(sp),a0
        bsr     wb_base
        bsr     wb_error
.dc_reload:
        bsr     wb_reload
.dc_free:
        lea     DS_SIZE(sp),sp
.dc_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts

; wb_rename(a5) : Workbench/Rename. L'icône sélectionnée d'un tiroir (pas le disque) : fenêtre « Rename » avec un
; gadget texte prérempli et activé ; Return renomme l'objet puis son « .info », et le tiroir est relu ; la case de
; fermeture annule. Préserve d7/a5.
RN_OLD          EQU 0                ; ancien chemin (WB_PATHMAX)
RN_NEW          EQU RN_OLD+WB_PATHMAX
RN_BUF          EQU RN_NEW+WB_PATHMAX    ; texte du gadget (nom OFS : 30 caractères)
RN_UNDO         EQU RN_BUF+32
RN_SI           EQU RN_UNDO+32       ; StringInfo
RN_GAD          EQU RN_SI+36         ; Gadget
RN_BRD          EQU RN_GAD+GG_SIZEOF ; Border puis ses 5 points
RN_SIZE         EQU RN_BRD+16+20
RN_MAXCHARS     EQU 31
wb_rename:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.w  WBS_SELW(a5),d7
        ble     .rn_ret              ; aucune sélection (-1) ou l'icône du disque (0)
        move.w  WBS_SELI(a5),d6
        bsr     wb_window
        beq     .rn_ret
        lea     -RN_SIZE(sp),sp
        move.l  sp,a0                ; tout à zéro
        move.w  #RN_SIZE/2-1,d0
.rn_clr:
        clr.w   (a0)+
        dbra    d0,.rn_clr
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a2 ; a2 = nom de l'icône
        move.l  a4,-(sp)
        lea     DR_PATH(a4),a0
        lea     4+RN_OLD(sp),a1
        move.l  a2,a4
        bsr     wb_join
        move.l  (sp)+,a4
        move.l  a2,a0
        lea     RN_BUF(sp),a1
        moveq   #RN_MAXCHARS-1,d0
        bsr     wb_strcpy
        lea     RN_BUF(sp),a0
        bsr     wb_strlen
        lea     RN_SI(sp),a0
        lea     RN_BUF(sp),a1
        move.l  a1,SI_BUFFER(a0)
        lea     RN_UNDO(sp),a1
        move.l  a1,SI_UNDOBUFFER(a0)
        move.w  d0,SI_BUFFERPOS(a0)  ; curseur en fin de nom
        move.w  #RN_MAXCHARS,SI_MAXCHARS(a0)
        lea     RN_GAD(sp),a1
        move.l  #(10<<16)|16,GG_LEFTEDGE(a1)
        move.l  #(280<<16)|9,GG_WIDTH(a1)
        move.w  #RELVERIFY,GG_ACTIVATION(a1)
        move.w  #STRGADGET,GG_GADGETTYPE(a1)
        move.l  a0,GG_SPECIALINFO(a1)
        lea     RN_BRD(sp),a0
        move.l  a0,GG_GADGETRENDER(a1)
        move.l  #$FFFEFFFE,BD_LEFTEDGE(a0)   ; cadre à 2 pixels autour du texte
        move.b  #1,BD_FRONTPEN(a0)
        move.b  #5,BD_COUNT(a0)
        lea     16(a0),a1
        move.l  a1,BD_XY(a0)
        clr.l   (a1)+                ; (0,0) (283,0) (283,12) (0,12) (0,0)
        move.l  #(283<<16),(a1)+
        move.l  #(283<<16)|12,(a1)+
        move.l  #12,(a1)+
        lea     -NW_SIZEOF(sp),sp
        bsr     wb_nwclear
        move.l  #(150<<16)|60,NW_LEFTEDGE(a0)
        move.l  #(300<<16)|32,NW_WIDTH(a0)
        move.l  #GADGETUP|CLOSEWINDOW,NW_IDCMPFLAGS(a0)
        move.l  #WINDOWDRAG|WINDOWDEPTH|WINDOWCLOSE|ACTIVATE,NW_FLAGS(a0)
        lea     NW_SIZEOF+RN_GAD(sp),a1
        move.l  a1,NW_FIRSTGADGET(a0)
        lea     wbs_rename(pc),a1
        move.l  a1,NW_TITLE(a0)
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_OPENWINDOW(a6)
        lea     NW_SIZEOF(sp),sp
        move.l  d0,d5                ; d5 = fenêtre « Rename »
        beq     .rn_free
        bset    #1,WBS_FLAGS(a5)     ; titre verrouillé : l'invite tient lieu de titre d'écran (spec §6.4)
        clr.l   WBS_MEMV(a5)
        lea     wb_renmsg(pc),a0
        lea     WBS_TBUF(a5),a1
        moveq   #WBS_TBUFMAX-2,d0
        bsr     wb_strcpy
        move.l  d5,a0
        move.l  #-1,a1
        lea     WBS_TBUF(a5),a2
        jsr     LVO_SETWINDOWTITLES(a6)
        lea     RN_GAD(sp),a0
        move.l  d5,a1
        sub.l   a2,a2
        jsr     LVO_ACTIVATEGADGET(a6)
        moveq   #0,d4                ; d4 = confirmé
.rn_wait:
        move.l  d5,a0
        move.l  WD_USERPORT(a0),a0
        move.l  ($4).w,a6
        jsr     LVO_WAITPORT(a6)
.rn_get:
        move.l  d5,a0
        move.l  WD_USERPORT(a0),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .rn_wait
        move.l  d0,a1
        move.l  IM_CLASS(a1),d3
        jsr     LVO_REPLYMSG(a6)
        cmp.l   #CLOSEWINDOW,d3
        beq.s   .rn_close
        cmp.l   #GADGETUP,d3
        bne.s   .rn_get
        moveq   #1,d4
.rn_close:
        move.l  d5,a0
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_CLOSEWINDOW(a6)
        bclr    #1,WBS_FLAGS(a5)     ; fin de saisie : titre mémoire refait tout de suite
        bsr     wb_memtitle
        tst.w   d4
        beq     .rn_free
        tst.b   RN_BUF(sp)           ; nom vide : rien à faire
        beq     .rn_free
        lea     RN_BUF(sp),a0        ; « : » et « / » refusés dans un nom (spec §6.9)
.rn_chk:
        moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .rn_ok
        cmp.b   #':',d0
        beq.s   .rn_bad
        cmp.b   #'/',d0
        bne.s   .rn_chk
.rn_bad:
        move.l  d0,-(sp)
        lea     wb_badchar(pc),a0
        move.l  sp,a1
        bsr     wb_message
        addq.l  #4,sp
        bra     .rn_free
.rn_ok:
        move.l  a4,-(sp)
        lea     DR_PATH(a4),a0
        lea     4+RN_NEW(sp),a1
        lea     4+RN_BUF(sp),a4
        bsr     wb_join
        move.l  (sp)+,a4
        move.l  WBS_DOSBASE(a5),a6
        lea     RN_OLD(sp),a0
        move.l  a0,d1
        lea     RN_NEW(sp),a0
        move.l  a0,d2
        jsr     DOS_LVO_RENAME(a6)
        tst.l   d0
        bne.s   .rn_info
        jsr     DOS_LVO_IOERR(a6)    ; objet absent (seul le .info existe) : toléré
        cmp.l   #ERROR_OBJECT_NOT_FOUND,d0
        beq.s   .rn_info
        moveq   #5,d0                ; « Error while moving <ancien nom>: n »
        lea     RN_OLD(sp),a0
        bsr     wb_base
        bsr     wb_error
        bra.s   .rn_free
.rn_info:
        lea     RN_OLD(sp),a0        ; puis les « .info »
        bsr     rn_info
        lea     RN_NEW(sp),a0
        bsr     rn_info
        lea     RN_OLD(sp),a0
        move.l  a0,d1
        lea     RN_NEW(sp),a0
        move.l  a0,d2
        jsr     DOS_LVO_RENAME(a6)
        bsr     wb_deselect
        bsr     wb_reload
.rn_free:
        lea     RN_SIZE(sp),sp
.rn_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts
; rn_info(a0 = chemin de WB_PATHMAX octets) : « .info » ajouté s'il tient. Clobbe d0/a0/a1.
rn_info:
        bsr     wb_strlen
        cmp.w   #WB_PATHMAX-6,d0
        bhs.s   .ri_ret
        lea     0(a0,d0.w),a1
        lea     wb_infosuffix(pc),a0
.ri_cp:
        move.b  (a0)+,(a1)+
        bne.s   .ri_cp
.ri_ret:
        rts

; wb_itext(a0 = IntuiText, a1 = texte, d1.w = haut) -> a0 = IntuiText suivante (la NextText posée y pointe) :
; stylo 2 sur 1, JAM1, 6 pixels à gauche. Clobbe d0.
wb_itext:
        move.b  #2,IT_FRONTPEN(a0)
        move.b  #1,IT_BACKPEN(a0)
        move.b  #JAM1,IT_DRAWMODE(a0)
        move.w  #6,IT_LEFTEDGE(a0)
        move.w  d1,IT_TOPEDGE(a0)
        clr.l   8(a0)                ; ITextFont
        move.l  a1,IT_ITEXT(a0)
        lea     IT_SIZEOF(a0),a0
        move.l  a0,IT_NEXTTEXT-IT_SIZEOF(a0)
        rts

; wb_rmtree(a0 = chemin, a5) -> d0 = vrai si l'objet a disparu : DeleteFile ; un répertoire non vide est d'abord vidé
; (chaque entrée supprimée récursivement, l'énumération reprise depuis le début après chaque suppression).
; Préserve d2-d7/a2-a6.
wb_rmtree:
        movem.l d2-d3/a2-a4/a6,-(sp)
        move.l  a0,a2                ; a2 = chemin
        move.l  WBS_DOSBASE(a5),a6
        move.l  a2,d1
        jsr     DOS_LVO_DELETEFILE(a6)
        tst.l   d0
        bne     .rt_ret
        jsr     DOS_LVO_IOERR(a6)
        cmp.l   #ERROR_OBJECT_NOT_FOUND,d0
        beq     .rt_gone             ; déjà absent : compté comme supprimé
        cmp.l   #ERROR_DIRECTORY_NOT_EMPTY,d0
        bne     .rt_err
        move.l  ($4).w,a6
        move.l  #FIB_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,d3                ; d3 = FIB
        beq     .rt_fail
        lea     -WB_PATHMAX(sp),sp   ; chemin d'une entrée
.rt_entry:
        move.l  WBS_DOSBASE(a5),a6
        move.l  a2,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,a3                ; a3 = verrou du répertoire
        tst.l   d0
        beq.s   .rt_done
        move.l  a3,d1
        move.l  d3,d2
        jsr     DOS_LVO_EXAMINE(a6)
        tst.l   d0
        beq.s   .rt_unlock
        move.l  a3,d1
        move.l  d3,d2
        jsr     DOS_LVO_EXNEXT(a6)
        tst.l   d0
        beq.s   .rt_unlock           ; vide : on peut supprimer le répertoire
        move.l  d3,a4
        lea     FIB_FILENAME(a4),a4
        move.l  a2,a0
        move.l  sp,a1
        bsr     wb_join
        move.l  a3,d1
        jsr     DOS_LVO_UNLOCK(a6)
        move.l  sp,a0
        bsr     wb_rmtree
        tst.l   d0
        bne.s   .rt_entry
        bra.s   .rt_done             ; une entrée résiste : on arrête
.rt_unlock:
        move.l  a3,d1
        jsr     DOS_LVO_UNLOCK(a6)
.rt_done:
        lea     WB_PATHMAX(sp),sp
        move.l  ($4).w,a6
        move.l  d3,a1
        move.l  #FIB_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        move.l  WBS_DOSBASE(a5),a6
        move.l  a2,d1
        jsr     DOS_LVO_DELETEFILE(a6)
        tst.l   d0
        bne.s   .rt_ret
.rt_err:                             ; « Error while removing <nom>: n » (le premier message affiché reste)
        moveq   #6,d0
        move.l  a2,a0
        bsr     wb_base
        bsr     wb_error
.rt_fail:
        moveq   #0,d0
        bra.s   .rt_ret
.rt_gone:
        moveq   #1,d0
.rt_ret:
        movem.l (sp)+,d2-d3/a2-a4/a6
        rts

; wb_cptree(a0 = source, a1 = destination, a5) -> d0 = 1 si l'objet (et tout son contenu) est copié, 0 sinon, le
; message d'erreur déjà affiché (spec workbench-task-v34 §6.6). Répertoire : Lock de la destination, CreateDir si
; absente, puis chaque entrée récursivement. Fichier : Open source (MODE_OLDFILE) et destination (MODE_NEWFILE), puis
; Read / Write par tampon de WB_CPBUF jusqu'à la taille annoncée par Examine. Préserve d2-d7/a2-a6.
CT_SRC          EQU 0                ; chemin d'une entrée source
CT_DST          EQU WB_PATHMAX       ; chemin de l'entrée destination
CT_SIZE         EQU 2*WB_PATHMAX
wb_cptree:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.l  a0,a2                ; a2 = source
        move.l  a1,a3                ; a3 = destination
        moveq   #0,d7                ; d7 = résultat
        move.l  ($4).w,a6
        move.l  #FIB_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,d6                ; d6 = FIB
        beq     .ct_nomem
        move.l  WBS_DOSBASE(a5),a6
        move.l  a2,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d5                ; d5 = verrou de la source
        bne.s   .ct_exam
        moveq   #1,d0                ; « accessing <entrée> »
        move.l  a2,a0
        bsr     wb_base
        bsr     wb_error
        bra     .ct_ffib
.ct_exam:
        move.l  d5,d1
        move.l  d6,d2
        jsr     DOS_LVO_EXAMINE(a6)
        tst.l   d0
        bne.s   .ct_kind
        moveq   #7,d0                ; « examining <entrée> »
        move.l  a2,a0
        bsr     wb_base
        bsr     wb_error
        bra     .ct_unlock
.ct_kind:
        move.l  d6,a0
        tst.l   FIB_DIRENTRYTYPE(a0)
        bmi     .ct_file
        move.l  a3,d1                ; répertoire : la destination existe-t-elle ?
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        tst.l   d0
        bne.s   .ct_dlock
        jsr     DOS_LVO_IOERR(a6)
        cmp.l   #ERROR_OBJECT_NOT_FOUND,d0
        bne.s   .ct_derr
        move.l  a3,d1
        jsr     DOS_LVO_CREATEDIR(a6)
        tst.l   d0
        bne.s   .ct_dlock
.ct_derr:
        moveq   #1,d0                ; « accessing <destination> »
        move.l  a3,a0
        bsr     wb_base
        bsr     wb_error
        bra     .ct_unlock
.ct_dlock:
        move.l  d0,d1
        jsr     DOS_LVO_UNLOCK(a6)
        lea     -CT_SIZE(sp),sp
.ct_next:
        move.l  d5,d1
        move.l  d6,d2
        jsr     DOS_LVO_EXNEXT(a6)
        tst.l   d0
        beq.s   .ct_dend
        move.l  d6,a4
        lea     FIB_FILENAME(a4),a4
        move.l  a2,a0
        lea     CT_SRC(sp),a1
        bsr     wb_join
        move.l  a3,a0
        lea     CT_DST(sp),a1
        bsr     wb_join
        lea     CT_SRC(sp),a0
        lea     CT_DST(sp),a1
        bsr     wb_cptree
        tst.l   d0
        bne.s   .ct_next
        bra.s   .ct_dout             ; une entrée a échoué : son message est affiché, on arrête
.ct_dend:
        jsr     DOS_LVO_IOERR(a6)
        cmp.l   #ERROR_NO_MORE_ENTRIES,d0
        beq.s   .ct_dok
        moveq   #0,d0                ; « examining directory »
        suba.l  a0,a0
        bsr     wb_error
        bra.s   .ct_dout
.ct_dok:
        moveq   #1,d7
.ct_dout:
        lea     CT_SIZE(sp),sp
        bra     .ct_unlock
.ct_file:
        move.l  FIB_SIZE(a0),d4      ; d4 = octets restant à copier
        move.l  ($4).w,a6
        move.l  #WB_CPBUF,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a4                ; a4 = tampon
        tst.l   d0
        bne.s   .ct_open
        bsr     .ct_oom
        bra     .ct_unlock
.ct_open:
        clr.l   -(sp)                ; 4(sp) = fichier destination
        move.l  WBS_DOSBASE(a5),a6
        move.l  a2,d1
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,-(sp)             ; (sp) = fichier source
        bne.s   .ct_odst
        moveq   #2,d0                ; « opening <source> »
        move.l  a2,a0
        bsr     wb_base
        bsr     wb_error
        bra.s   .ct_close
.ct_odst:
        move.l  a3,d1
        move.l  #MODE_NEWFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,4(sp)
        bne.s   .ct_rw
        moveq   #2,d0                ; « opening <destination> »
        move.l  a3,a0
        bsr     wb_base
        bsr     wb_error
        bra.s   .ct_close
.ct_rw:
        tst.l   d4
        beq.s   .ct_fok
        move.l  d4,d3
        cmp.l   #WB_CPBUF,d3
        bls.s   .ct_rd
        move.l  #WB_CPBUF,d3
.ct_rd:
        move.l  (sp),d1
        move.l  a4,d2
        jsr     DOS_LVO_READ(a6)
        tst.l   d0
        bgt.s   .ct_wr
        moveq   #3,d0                ; « reading »
        suba.l  a0,a0
        bsr     wb_error
        bra.s   .ct_close
.ct_wr:
        move.l  d0,d3
        move.l  4(sp),d1
        move.l  a4,d2
        jsr     DOS_LVO_WRITE(a6)
        cmp.l   d3,d0
        beq.s   .ct_wok
        moveq   #4,d0                ; « writing »
        suba.l  a0,a0
        bsr     wb_error
        bra.s   .ct_close
.ct_wok:
        sub.l   d3,d4
        bra.s   .ct_rw
.ct_fok:
        moveq   #1,d7
.ct_close:
        move.l  (sp)+,d1
        beq.s   .ct_c2
        jsr     DOS_LVO_CLOSE(a6)
.ct_c2:
        move.l  (sp)+,d1
        beq.s   .ct_c3
        jsr     DOS_LVO_CLOSE(a6)
.ct_c3:
        move.l  ($4).w,a6
        move.l  a4,a1
        move.l  #WB_CPBUF,d0
        jsr     LVO_FREEMEM(a6)
.ct_unlock:
        move.l  WBS_DOSBASE(a5),a6
        move.l  d5,d1
        jsr     DOS_LVO_UNLOCK(a6)
.ct_ffib:
        move.l  ($4).w,a6
        move.l  d6,a1
        move.l  #FIB_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .ct_ret
.ct_nomem:
        bsr.s   .ct_oom
.ct_ret:
        move.l  d7,d0
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts
.ct_oom:                             ; spec §6.6 point 9
        lea     wb_nomem(pc),a0
        suba.l  a1,a1
        bra     wb_message

; wb_reload(d7.w = tiroir, a5) : ses icônes sont rendues, l'intérieur effacé, le répertoire relu (icônes redessinées
; au fur et à mesure). Préserve d2-d7/a2-a5.
wb_reload:
        movem.l d2/a2-a4/a6,-(sp)
        bsr     wb_window
        beq.s   .rl_ret
        move.l  DR_NICON(a4),d2
        clr.l   DR_NICON(a4)
        lea     DR_ICONS(a4),a2
        move.l  WBS_ICONBASE(a5),a6
        bra.s   .rl_fnx
.rl_free:
        move.l  (a2)+,a0
        jsr     ICON_LVO_FREEDISKOBJECT(a6)
.rl_fnx:
        dbra    d2,.rl_free
        bsr     wb_redraw1
        bsr     wb_loadicons
.rl_ret:
        movem.l (sp)+,d2/a2-a4/a6
        rts

; wb_mkmenus(a5) : recopie le modèle des menus dans l'état (intuition écrit dans les éléments) et y reloge les
; pointeurs internes (table wbm_reloc : décalages des champs qui pointent dans le modèle). Préserve d2-d7/a2-a6.
wb_mkmenus:
        lea     wbm_tmpl(pc),a0
        lea     WBS_MENUS(a5),a1
        move.w  #WBM_SIZE/2-1,d0
.mk_cpy:
        move.w  (a0)+,(a1)+
        dbra    d0,.mk_cpy
        lea     WBS_MENUS(a5),a1
        lea     wbm_reloc(pc),a0
.mk_rel:
        move.w  (a0)+,d0
        bmi.s   .mk_ret
        move.l  a1,d1
        add.l   d1,0(a1,d0.w)
        bra.s   .mk_rel
.mk_ret:
        rts

; wb_strlen(a0) -> d0 = longueur. Préserve a0. wb_strcpy(a0 -> a1, d0 = longueur max) : copie terminée par 0.
; wb_streq(a0, a1) -> Z = 1 si égales (insensible à la casse ASCII). Clobbe d0/d1.
wb_strlen:
        move.l  a0,-(sp)
        moveq   #-1,d0
.sl_lp:
        addq.l  #1,d0
        tst.b   (a0)+
        bne.s   .sl_lp
        move.l  (sp)+,a0
        rts
wb_strcpy:
        move.b  (a0)+,(a1)+
        dbeq    d0,wb_strcpy
        clr.b   -1(a1)               ; terminateur (ou dernier octet sacrifié si tronqué)
        rts
wb_streq:
        move.b  (a0)+,d0
        move.b  (a1)+,d1
        and.b   #$DF,d0
        and.b   #$DF,d1
        cmp.b   d0,d1
        bne.s   .se_ret
        tst.b   -1(a0)
        bne.s   wb_streq
.se_ret:
        rts

; --- modèle des menus (struct Menu / MenuItem / IntuiText) : pointeurs internes relatifs à wbm_tmpl, relogés par
; wb_mkmenus ; les textes restent en ROM. Workbench (Open, Close, Duplicate, Rename, Info, Discard), Disk (Empty
; Trash, Initialize), Special (Clean Up, Last Error, Redraw, Snapshot, Version).
WBM_ITEMW       EQU 120
WBM_ITEMH       EQU 10
WBM_ON          EQU ITEMTEXT|ITEMENABLED|$40 ; texte, actif, HIGHCOMP
WBM_OFF         EQU ITEMTEXT|$40
WBMENU          MACRO                ; \1 = étiquette, \2 = suivant (0 ou étiquette), \3 = x, \4 = largeur, \5 = nom, \6 = 1er élément
\1:
        ifc     "\2","0"
        dc.l    0
        else
        dc.l    \2-wbm_tmpl
        endc
        dc.w    \3,0,\4,10,MENUENABLED
        dc.l    \5,\6-wbm_tmpl
        dc.w    0,0,0,0
                ENDM
WBITEM          MACRO                ; \1 = étiquette, \2 = suivant (0 ou étiquette), \3 = y, \4 = drapeaux, \5 = texte
\1:
        ifc     "\2","0"
        dc.l    0
        else
        dc.l    \2-wbm_tmpl
        endc
        dc.w    0,\3,WBM_ITEMW,WBM_ITEMH,\4
        dc.l    0,\1t-wbm_tmpl,0
        dc.b    0,0
        dc.l    0
        dc.w    MENUNULL
\1t:
        dc.b    2,1,JAM2,0           ; IntuiText : stylo 2 sur 1
        dc.w    2,1
        dc.l    0,\5,0
                ENDM
                cnop    0,2
wbm_tmpl:
        WBMENU  wbm_m0,wbm_m1,0,88,wbs_wb,wbm_i00
        WBMENU  wbm_m1,wbm_m2,96,48,wbs_disk,wbm_i10
        WBMENU  wbm_m2,0,152,72,wbs_special,wbm_i20
        WBITEM  wbm_i00,wbm_i01,0,WBM_ON,wbs_open
        WBITEM  wbm_i01,wbm_i02,10,WBM_ON,wbs_close
        WBITEM  wbm_i02,wbm_i03,20,WBM_ON,wbs_dup
        WBITEM  wbm_i03,wbm_i04,30,WBM_ON,wbs_rename
        WBITEM  wbm_i04,wbm_i05,40,WBM_ON,wbs_info
        WBITEM  wbm_i05,0,50,WBM_ON,wbs_discard
        WBITEM  wbm_i10,wbm_i11,0,WBM_OFF,wbs_trash
        WBITEM  wbm_i11,0,10,WBM_OFF,wbs_init
        WBITEM  wbm_i20,wbm_i21,0,WBM_ON,wbs_cleanup
        WBITEM  wbm_i21,wbm_i22,10,WBM_ON,wbs_lasterr
        WBITEM  wbm_i22,wbm_i23,20,WBM_ON,wbs_redraw
        WBITEM  wbm_i23,wbm_i24,30,WBM_ON,wbs_snapshot
        WBITEM  wbm_i24,0,40,WBM_ON,wbs_version
wbm_end:
WBM_SIZE        EQU wbm_end-wbm_tmpl
; décalages (dans le modèle) des pointeurs internes à reloger : menus (suivant, 1er élément), éléments (suivant non
; nul, texte)
RELM            MACRO
        dc.w    \1-wbm_tmpl+MU_FIRSTITEM
        ifnc    "\2","0"
        dc.w    \1-wbm_tmpl+MU_NEXTMENU
        endc
                ENDM
RELI            MACRO
        dc.w    \1-wbm_tmpl+MI_ITEMFILL
        ifnc    "\2","0"
        dc.w    \1-wbm_tmpl+MI_NEXTITEM
        endc
                ENDM
wbm_reloc:
        RELM    wbm_m0,1
        RELM    wbm_m1,1
        RELM    wbm_m2,0
        RELI    wbm_i00,1
        RELI    wbm_i01,1
        RELI    wbm_i02,1
        RELI    wbm_i03,1
        RELI    wbm_i04,1
        RELI    wbm_i05,0
        RELI    wbm_i10,1
        RELI    wbm_i11,0
        RELI    wbm_i20,1
        RELI    wbm_i21,1
        RELI    wbm_i22,1
        RELI    wbm_i23,1
        RELI    wbm_i24,0
        dc.w    -1

wbs_wb:         dc.b    "Workbench",0
wbs_disk:       dc.b    "Disk",0
wbs_special:    dc.b    "Special",0
wbs_open:       dc.b    "Open",0
wbs_close:      dc.b    "Close",0
wbs_dup:        dc.b    "Duplicate",0
wbs_rename:     dc.b    "Rename",0
wbs_info:       dc.b    "Info",0
wbs_discard:    dc.b    "Discard",0
wbs_cancel:     dc.b    "Cancel",0
wbs_dsw1:       dc.b    "Warning: you cannot get back",0
wbs_dsw2:       dc.b    "what you discard!",0
wbs_dsq:        dc.b    "OK to discard ",0
wbs_trash:      dc.b    "Empty Trash",0
wbs_init:       dc.b    "Initialize",0
wbs_cleanup:    dc.b    "Clean Up",0
wbs_lasterr:    dc.b    "Last Error",0
wbs_redraw:     dc.b    "Redraw",0
wbs_snapshot:   dc.b    "Snapshot",0
wbs_version:    dc.b    "Version",0
                ifeq    PROD
wb_msgrun:      dc.b    13,10,"WB TOOL RUN",13,10,0
wb_msgend:      dc.b    13,10,"WB TOOL END",13,10,0
                endc
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
        dc.b    ".info",0
wb_procname:
        dc.b    "Workbench",0
wb_timername:
        dc.b    "timer.device",0
wb_relfmt:
        dc.b    "Workbench release 1.2.  %ld free memory",0
wb_verfmt:
        dc.b    "Kickstart version %ld.%ld. Workbench version %ld.%ld",0
wb_vername:
        dc.b    "version.library",0
wb_renmsg:
        dc.b    "Enter the new name.  Press return when done.",0
wb_empty:
        dc.b    0
wb_infolib:
        dc.b    "info.library",0
wb_noinfo:
        dc.b    "Info not available",0
wb_nodiskcopy:
        dc.b    "This disk cannot be copied",0
wb_noinfofile:
        dc.b    "Cannot read info file %s",0
wb_nomem:
        dc.b    "Ran out of memory.  Please free some and try again.",0
wb_diskicon:
        dc.b    "Disk",0
wb_errfmt:
        dc.b    "Error while %s: %ld",0
wb_badchar:
        dc.b    "Do not use '%lc' in names",0
        even
wb_errtab:                           ; actions des messages d'erreur, par index (spec §6.5)
        dc.w    wbe_0-wb_errtab,wbe_1-wb_errtab,wbe_2-wb_errtab,wbe_3-wb_errtab,wbe_4-wb_errtab
        dc.w    wbe_5-wb_errtab,wbe_6-wb_errtab,wbe_7-wb_errtab,wbe_8-wb_errtab
wbe_0:  dc.b    "examining directory",0
wbe_1:  dc.b    "accessing %s",0
wbe_2:  dc.b    "opening %s",0
wbe_3:  dc.b    "reading",0
wbe_4:  dc.b    "writing",0
wbe_5:  dc.b    "moving %s",0
wbe_6:  dc.b    "removing %s",0
wbe_7:  dc.b    "examining %s",0
wbe_8:  dc.b    "writing %s",0
wb_idstring:
        dc.b    "workbench.task 34.2",13,10,0
        EVEN
wb_end:
