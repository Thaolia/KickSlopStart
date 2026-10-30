; src/dos/workbench.s - workbench.task resident: the process launched by c:LoadWB.
; Spec: docs/analysis/workbench-task-v34.md (clean-room reviewed). Contract with LoadWB:
;   - NT_TASK ROMTag without a class flag: present in ResModules (FindResident) but never initialised at boot;
;   - LoadWB does CreateProc(..., seglist = BPTR(ROMTag+42), ...): the truncation yields a fake segment at ROMTag+40
;     (link) and an entry point at ROMTag+44 (ROMTag aligned on 4);
;   - the process must reply to LoadWB's message (28 bytes: +$14 = BPTR of the path, +$18 = -debug flag) as soon as
;     it is initialised, otherwise LoadWB stays blocked; it is named "Workbench" (LoadWB finds it via FindTask) and
;     runs at priority 1.
; Desktop: Workbench screen, backdrop window (BACKDROP) with one icon per mounted volume of the DosList (spec
; disk-change-v34 §4): "<volume>:Disk.info", otherwise default disk icon; scanned at startup, on the 5 s tick and
; on DISKINSERTED / DISKREMOVED; a volume gone from the DosList loses its icon. Drawer windows (WB_MAXDRAWERS): the
; root (double-click on the disk) and any nested drawer (double-click on a drawer icon), icons read through
; Examine/ExNext + GetDiskObject, redrawn on REFRESHWINDOW (BeginRefresh/EndRefresh). Only one icon selected at a
; time (inverted rectangle). Double-click on a tool: launched by CreateProc with a WBStartup message (argument 0 =
; the tool); on a project: its default tool, the project as argument 1. The message comes back on the "Workbench"
; port when the tool ends: segment unloaded, locks returned. Workbench / Disk / Special menus: Open, Close, Rename,
; Discard, Clean Up, Last Error, Redraw, Snapshot and Version active, the rest ghosted. Screen title (spec §6): free
; memory on the 5 s tick, frozen message (Version, Last Error) until the next click or menu. Scope: a single selected
; icon; Rename and Discard only apply to the icons of a drawer. Failures reported in the screen title like 1.3 (spec
; §6.9): "Error while <action>: <IoErr>" when opening a drawer, on launch, on Rename (and
; "Do not use ':' in names"), on Discard and on Snapshot.
; IMPLEMENTATION track ("clean"): spec above + exec/dos/workbench AutoDocs (WBStartup, DiskObject).
; NO ROM reading.

                include "exec.i"
                include "dospkt.i"
                include "intuition.i"
                include "graphics.i"
                include "dos.i"

                ifeq    PROD
                xref    ser_puts             ; test markers (development ROM)
                endc

LVO_DRAWIMAGE   EQU -114             ; intuition.library (intuition_lib.fd)
LVO_SETWINDOWTITLES EQU -276
LVO_DISPLAYBEEP EQU -96
LVO_SETMENUSTRIP EQU -264
LVO_CLEARMENUSTRIP EQU -54
LVO_WINDOWTOFRONT EQU -312
LVO_DOUBLECLICK EQU -102
LVO_REPORTMOUSE EQU -234
ICON_LVO_GETDISKOBJECT EQU -78       ; icon.library (icon_lib.fd)
ICON_LVO_PUTDISKOBJECT EQU -84
ICON_LVO_GETWBOBJECT EQU -30         ; icon.library 1.3 (spec workbench-task-v34 §7.8)
ICON_LVO_FREEWBOBJECT EQU -60
ICON_LVO_ADDFREELIST EQU -72
ICON_LVO_PUTWBOBJECT EQU -36
WB_LVO_NEWMODIFYPROP EQU -468       ; intuition
WB_LVO_MODIFYIDCMP EQU -150         ; intuition ModifyIDCMP(window a0, classes d0)
DOS_LVO_INFO    EQU -114             ; Info(lock d1, InfoData d2)
ID_NUMBLOCKS    EQU 12               ; struct InfoData
ID_NUMBLOCKSUSED EQU 16
ICON_LVO_BUMPREVISION EQU -108
WBO_CURX        EQU $54              ; WBObject: position of the icon (LONG)
WBO_CURY        EQU $58
WBO_NAME        EQU $40              ; WBObject (private, allocated by icon.library): C name
WBO_DRAWER      EQU $4C              ; Workbench DrawerData (446 bytes) | 0
WBO_FREE        EQU $8C              ; FreeList of the object
WBO_LOCK        EQU $A4              ; BPTR of the containing directory
WBD_LOCK        EQU $1BA             ; DrawerData: BPTR of the drawer / disk directory
ICON_LVO_FREEDISKOBJECT EQU -90
DOS_LVO_CREATEPROC EQU -138
NW_SIZEOF       EQU 48               ; struct NewWindow
DO_GADGET       EQU 4                ; struct DiskObject (workbench/workbench.h): embedded gadget
DO_TYPE         EQU 48
DO_DEFAULTTOOL  EQU 50
DO_CURRENTX     EQU 58
DO_CURRENTY     EQU 62
DO_DRAWERDATA   EQU 66               ; struct DrawerData: dd_NewWindow at the head
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

WB_MSGPATH      EQU $14              ; LoadWB message: BPTR of the path (-> cli_CommandDir)

                cnop    0,4
wb_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    wb_romtag            ; RT_MATCHTAG = self
        dc.l    wb_end               ; RT_ENDSKIP
        dc.b    0,34,NT_TASK,0       ; RT_FLAGS (no class: launched by LoadWB), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    wb_taskname          ; RT_NAME
        dc.l    wb_idstring          ; RT_IDSTRING
        dc.l    wb_entry             ; RT_INIT
        dcb.b   40-26,0              ; up to the fake segment
        dc.l    0                    ; ROMTag+40: link of the fake segment (end of chain)
wb_entry:                            ; ROMTag+44: entry point of the process created by LoadWB
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a4   ; a4 = this process
        lea     wb_procname(pc),a0
        move.l  a0,LN_NAME(a4)
        move.l  a4,a1
        moveq   #1,d0
        jsr     LVO_SETTASKPRI(a6)
        moveq   #CLI_SIZEOF,d0       ; fake CLI: tools launched later find the command path there
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a3                ; a3 = CLI | 0
        tst.l   d0
        beq.s   .we_nocli
        lsr.l   #2,d0
        move.l  d0,PR_CLI(a4)
.we_nocli:
        lea     PR_MSGPORT(a4),a0    ; LoadWB startup message
        jsr     LVO_WAITPORT(a6)
        lea     PR_MSGPORT(a4),a0
        jsr     LVO_GETMSG(a6)
        move.l  d0,a1
        move.l  a3,d1
        beq.s   .we_reply
        move.l  WB_MSGPATH(a1),CLI_COMMANDDIR(a3)
.we_reply:
        jsr     LVO_REPLYMSG(a6)     ; immediate reply: LoadWB continues
        move.l  #WBS_SIZE,d0         ; desktop state
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .we_idle
        move.l  d0,a5                ; a5 = state
        move.w  #-1,WBS_SELW(a5)
        move.w  #-1,WBS_DRAGW(a5)
        bsr     wb_mkmenus
        moveq   #MP_SIZE,d0          ; public "Workbench" port (WBStartup messages returned by the tools)
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
        bsr     wb_desktop           ; Workbench screen, backdrop window, disk icon
        bsr     wb_timeropen         ; 5 s tick (screen title: free memory)
.we_loop:                            ; waits on the public port and the IDCMP ports of all the windows
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
.we_drain:                           ; public port: returned WBStartup messages, or foreign messages (replied)
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
        moveq   #0,d7                ; window 0: the desktop, then drawers 1..WB_MAXDRAWERS
.we_win:
        bsr     wb_dispatch
        addq.w  #1,d7
        cmp.w   #WB_MAXDRAWERS,d7
        bls.s   .we_win
        bra     .we_loop
.we_idle:                            ; without state or port: endless wait (the process does not end, like the real one)
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .we_idle

; desktop state
WBS_IBASE       EQU 0                ; IntuitionBase
WBS_GFXBASE     EQU 4
WBS_DOSBASE     EQU 8
WBS_ICONBASE    EQU 12
WBS_WIN         EQU 16               ; backdrop window (BACKDROP) | 0
WBS_NVOL        EQU 20               ; WORD: volumes on the desktop (WBS_VOLS[0..NVOL-1], desktop icons 0..NVOL-1)
WBS_DEFIMG      EQU 22               ; data of the default disk image, copied to CHIP | 0 (those of the ROM)
WBS_NAMEMAX     EQU 32
WBS_PORT        EQU WBS_DEFIMG+4     ; public "Workbench" port
WBS_SELW        EQU WBS_PORT+4       ; WORD: window of the selected icon (0 desktop, 1.. drawer), -1: none
WBS_SELI        EQU WBS_SELW+2       ; WORD: number of the selected icon
WBS_LSEC        EQU WBS_SELI+2       ; timestamp of the previous click (double-click)
WBS_LMIC        EQU WBS_LSEC+4
WBS_GON         EQU WBS_LMIC+4       ; BYTE: ghost frame of the drag displayed
WBS_DRAGW       EQU WBS_GON+2        ; WORD: window of the dragged icon, -1: no drag
WBS_DRAGI       EQU WBS_DRAGW+2      ; WORD: dragged icon
WBS_DSX         EQU WBS_DRAGI+2      ; mouse at the click (relative to the window)
WBS_DSY         EQU WBS_DSX+2
WBS_GX          EQU WBS_DSY+2        ; ghost frame: corner and size (screen coordinates)
WBS_GY          EQU WBS_GX+2
WBS_GW          EQU WBS_GY+2
WBS_GH          EQU WBS_GW+2
WBS_GRP         EQU WBS_GH+2         ; RastPort of the screen (frame drawn in COMPLEMENT)
WBS_TREQ        EQU WBS_GRP+4        ; timerequest of the 5 s tick (reply on the public port)
WBS_MEMV        EQU WBS_TREQ+TR_SIZE ; last AvailMem value displayed
WBS_TBUF        EQU WBS_MEMV+4       ; screen title of the Workbench windows (C string)
WBS_TBUFMAX     EQU 80
WBS_TON         EQU WBS_TBUF+WBS_TBUFMAX ; BYTE: timer.device open
WBS_FLAGS       EQU WBS_TON+1        ; BYTE: bit 1 = title locked (Rename), bit 2 = a message is displayed
WBS_MSGBUF      EQU WBS_TON+2        ; last message (Version, Last Error): WBS_TBUFMAX bytes
WBS_MSGOK       EQU WBS_MSGBUF+WBS_TBUFMAX ; BYTE: a message has been produced
WBS_ARROWS      EQU WBS_MSGOK+2      ; 4 Images of the scroll arrows, in CHIP memory | 0
WBS_MADDR       EQU WBS_ARROWS+4     ; IAddress of the last message read (wb_getmsg)
WBS_MQUAL       EQU WBS_MADDR+4      ; WORD: its qualifier
WBS_SCRW        EQU WBS_MQUAL+2      ; WORD: drawer being scrolled
WBS_SCRG        EQU WBS_SCRW+2       ; WORD: GadgetID of the scroll gadget held, 0: none
WBS_SCRGAD      EQU WBS_SCRG+2       ; LONG: that gadget
WBS_SCRTICK     EQU WBS_SCRGAD+4     ; WORD: arrow held without Shift -> one step per INTUITICKS (added to the IDCMP)
WBS_UPDCNT      EQU WBS_SCRTICK+2    ; WORD: nesting of wb_updopen (a single update for the whole WB)
WBS_VOLS        EQU WBS_UPDCNT+2     ; WB_MAXVOLS volume records (desktop icons)
WBS_DRAWERS     EQU WBS_VOLS+WB_MAXVOLS*VE_SIZE ; WB_MAXDRAWERS drawer records
WBS_MENUS       EQU WBS_DRAWERS+WB_MAXDRAWERS*DR_SIZE ; copy of the menus (intuition writes into it)
WBS_SIZE        EQU WBS_MENUS+WBM_SIZE
WB_MAXDRAWERS   EQU 6
WB_MAXVOLS      EQU 8
; record of a desktop volume
VE_NODE         EQU 0                ; BPTR of the DosList volume node
VE_DOBJ         EQU 4                ; DiskObject: the one of "<volume>:Disk", or VE_DEFO
VE_DEF          EQU 8                ; BYTE: default icon (copy in VE_DEFO, never returned to icon.library)
VE_SEEN         EQU 9                ; BYTE: seen again at the last DosList scan
VE_X            EQU 10               ; WORD: position of the icon in the backdrop window
VE_Y            EQU 12
VE_DATE         EQU 14               ; creation date of the volume (dl_VolumeDate)
VE_NAME         EQU 26               ; name of the volume (C string)
VE_PATH         EQU VE_NAME+WBS_NAMEMAX ; "<name>:"
VE_DEFO         EQU VE_PATH+36       ; default DiskObject (78 bytes)
VE_DEFI         EQU VE_DEFO+78       ; its Image (IG_SIZE)
VE_SIZE         EQU VE_DEFI+IG_SIZE
WB_COLW         EQU 96               ; automatic placement: 96-pixel columns (spec disk-change-v34 §4.3)
WB_LABELH       EQU 11               ; room for the name under an icon (tf_YSize of topaz 8 + 3)
; record of a drawer
DR_WIN          EQU 0                ; window | 0 (free record)
DR_NICON        EQU 4                ; icons read
DR_ICONS        EQU 8                ; WB_MAXICONS x DiskObject
DR_NAMES        EQU DR_ICONS+WB_MAXICONS*4 ; WB_MAXICONS x name (WBS_NAMEMAX bytes)
DR_PATH         EQU DR_NAMES+WB_MAXICONS*WBS_NAMEMAX ; path of the drawer ("SYS:", "SYS:System"...)
DR_TITLE        EQU DR_PATH+WB_PATHMAX ; title of the window
DR_ID           EQU DR_TITLE+WBS_NAMEMAX ; WORD: window number (1..WB_MAXDRAWERS)
DR_SX           EQU DR_ID+2          ; WORD: scroll position (dd_CurrentX / dd_CurrentY of the .info)
DR_SY           EQU DR_SX+2
DR_EMINX        EQU DR_SY+2          ; WORD x 4: extent (visible rectangle enlarged to the icons)
DR_EMINY        EQU DR_EMINX+2
DR_EMAXX        EQU DR_EMINY+2
DR_EMAXY        EQU DR_EMAXX+2
DR_DISK         EQU DR_EMAXY+2       ; BYTE: window of a disk (gauge on the left)
DR_USED         EQU DR_DISK+2        ; gauge: used blocks, total blocks (InfoData)
DR_TOTAL        EQU DR_USED+4
DR_GADS         EQU DR_TOTAL+4       ; 6 scroll gadgets (spec workbench-task-v34 §8.1)
DR_PROPS        EQU DR_GADS+6*GG_SIZEOF  ; PropInfo of the vertical then horizontal bars
DR_KNOBS        EQU DR_PROPS+2*PI_SIZE   ; Images (empty, AUTOKNOB) of their knobs
DR_SIZE         EQU DR_KNOBS+2*IG_SIZE
PI_SIZE         EQU 22
IG_SIZE         EQU 20
DD_CURRENTX     EQU 48               ; DrawerData: remembered scroll position
DD_CURRENTY     EQU 52
WB_DISKGAUGE    EQU 14               ; width reserved for the gauge of a disk window
WB_MAXICONS     EQU 16
WB_PATHMAX      EQU 96
WB_CPBUF        EQU 4096             ; copy buffer of Duplicate
WB_GRIDX        EQU 80
WB_TOOLSTACK    EQU 4096             ; minimum stack of a launched tool

; wb_desktop(a5 = state, a6 = SysBase): opens the Workbench screen, the backdrop window (BACKDROP, borderless, below
; the screen bar), then scans the DosList volumes (wb_vscan) and draws the desktop.
; Each step is optional (library or file missing: poorer desktop). Preserves d2-d7/a2-a6.
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
        move.l  d0,a2                ; a2 = screen
        lea     -NW_SIZEOF(sp),sp    ; NewWindow of the backdrop window
        bsr     wb_nwclear
        moveq   #0,d1
        move.b  SC_BARHEIGHT(a2),d1
        addq.w  #1,d1
        move.w  d1,NW_TOPEDGE(a0)
        move.w  SC_WIDTH(a2),NW_WIDTH(a0)
        move.w  SC_HEIGHT(a2),d0
        sub.w   d1,d0
        move.w  d0,NW_HEIGHT(a0)
        move.l  #REFRESHWINDOW|MOUSEBUTTONS|MOUSEMOVE|MENUPICK|DISKINSERTED|DISKREMOVED,NW_IDCMPFLAGS(a0)
        move.l  #BACKDROP|BORDERLESS,NW_FLAGS(a0)
        jsr     LVO_OPENWINDOW(a6)
        lea     NW_SIZEOF(sp),sp
        move.l  d0,WBS_WIN(a5)
        beq.s   .wd_vol
        move.l  d0,a0
        bsr     wb_setmenus
.wd_vol:
        lea     wb_dosname(pc),a1
        bsr     wb_openlib
        move.l  d0,WBS_DOSBASE(a5)
        lea     wb_iconname(pc),a1
        bsr     wb_openlib
        move.l  d0,WBS_ICONBASE(a5)
        move.l  ($4).w,a6
        move.l  #4*32,d0             ; default disk image in CHIP (32 x 16, 2 planes)
        move.l  #(MEMF_CHIP|MEMF_PUBLIC),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,WBS_DEFIMG(a5)
        beq.s   .wd_scan
        move.l  d0,a1
        lea     wb_defdata(pc),a0
        moveq   #32-1,d0
.wd_img:
        move.l  (a0)+,(a1)+
        dbra    d0,.wd_img
.wd_scan:
        bsr     wb_vscan             ; volume icons, then desktop drawn
.wd_ret:
        movem.l (sp)+,d2-d3/a2/a6
        rts

; --- desktop volumes (spec disk-change-v34 §4) ---------------------------------------------------------------------
; wb_volent(d1.w = volume number, a5) -> a0 = its record. Clobbers d0.
wb_volent:
        move.w  d1,d0
        mulu    #VE_SIZE,d0
        lea     WBS_VOLS(a5),a0
        add.l   d0,a0
        rts

; wb_vscan(a5): scan of the DosList. Known volume (same node, present or not): seen again. Unknown mounted volume
; (dl_Task non-zero): new icon (wb_vadd), in list order. Record whose node has left the list: icon removed.
; Change: desktop redrawn. Nothing during a drag. Preserves d2-d7/a2-a6.
wb_vscan:
        movem.l d2-d7/a2-a4/a6,-(sp)
        tst.l   WBS_DOSBASE(a5)
        beq     .vs_ret
        tst.w   WBS_DRAGW(a5)
        bpl     .vs_ret
        moveq   #0,d5                ; d5 = change
        lea     WBS_VOLS(a5),a2
        move.w  WBS_NVOL(a5),d0
        bra.s   .vs_ue
.vs_un:
        sf      VE_SEEN(a2)
        lea     VE_SIZE(a2),a2
.vs_ue:
        dbra    d0,.vs_un
        lea     -4*WB_MAXVOLS(sp),sp ; nodes of the new volumes
        moveq   #0,d6                ; d6 = their number
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        bsr     wb_devinfo
        move.l  (a0),d2
.vs_lp:
        lsl.l   #2,d2
        beq.s   .vs_end
        move.l  d2,a3
        lsr.l   #2,d2                ; d2 = BPTR of the node
        cmp.l   #DLT_VOLUME,DN_TYPE(a3)
        bne.s   .vs_nx
        lea     WBS_VOLS(a5),a2
        move.w  WBS_NVOL(a5),d0
        bra.s   .vs_fe
.vs_find:
        cmp.l   VE_NODE(a2),d2
        beq.s   .vs_seen
        lea     VE_SIZE(a2),a2
.vs_fe:
        dbra    d0,.vs_find
        tst.l   DN_TASK(a3)          ; unknown: only if it is mounted
        beq.s   .vs_nx
        cmp.w   #WB_MAXVOLS,d6
        bhs.s   .vs_nx
        move.w  d6,d0
        lsl.w   #2,d0
        move.l  d2,0(sp,d0.w)
        addq.w  #1,d6
        bra.s   .vs_nx
.vs_seen:
        st      VE_SEEN(a2)
.vs_nx:
        move.l  DN_NEXT(a3),d2
        bra.s   .vs_lp
.vs_end:
        jsr     LVO_PERMIT(a6)
        move.w  WBS_NVOL(a5),d4      ; vanished records, from the last to the first
.vs_rm:
        subq.w  #1,d4
        bmi.s   .vs_add
        move.w  d4,d1
        bsr     wb_volent
        tst.b   VE_SEEN(a0)
        bne.s   .vs_rm
        move.w  d4,d1
        bsr     wb_vremove
        moveq   #1,d5
        bra.s   .vs_rm
.vs_add:
        moveq   #0,d4
.vs_al:
        cmp.w   d6,d4
        bhs.s   .vs_draw
        move.w  d4,d0
        lsl.w   #2,d0
        move.l  0(sp,d0.w),d0
        bsr     wb_vadd
        beq.s   .vs_an
        moveq   #1,d5
.vs_an:
        addq.w  #1,d4
        bra.s   .vs_al
.vs_draw:
        lea     4*WB_MAXVOLS(sp),sp
        tst.l   d5
        beq.s   .vs_ret
        moveq   #0,d7
        bsr     wb_redraw1
.vs_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts
; wb_devinfo(a5) -> a0 = &DosInfo.di_DevInfo. Clobbers d0.
wb_devinfo:
        move.l  WBS_DOSBASE(a5),a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_INFO(a0),d0
        lsl.l   #2,d0
        move.l  d0,a0
        lea     DI_DEVINFO(a0),a0
        rts

; wb_vremove(d1.w = volume number, a5): its icon leaves the desktop (DiskObject returned, except the default icon);
; the following records move down one rank. A selection on the desktop is dropped. Preserves d2-d7/a2-a6.
wb_vremove:
        movem.l d2/a2/a6,-(sp)
        tst.w   WBS_SELW(a5)
        bne.s   .vr_sel
        move.w  #-1,WBS_SELW(a5)     ; the desktop is redrawn afterwards
.vr_sel:
        move.w  d1,d2
        bsr     wb_volent
        move.l  a0,a2
        tst.b   VE_DEF(a2)
        bne.s   .vr_shift
        move.l  VE_DOBJ(a2),a0
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_FREEDISKOBJECT(a6)
.vr_shift:
        subq.w  #1,WBS_NVOL(a5)
.vr_lp:
        cmp.w   WBS_NVOL(a5),d2
        bhs.s   .vr_ret
        lea     VE_SIZE(a2),a0       ; next record copied here
        move.l  a2,a1
        move.w  #VE_SIZE/2-1,d0
.vr_cp:
        move.w  (a0)+,(a1)+
        dbra    d0,.vr_cp
        bsr     wb_vfix
        lea     VE_SIZE(a2),a2
        addq.w  #1,d2
        bra.s   .vr_lp
.vr_ret:
        movem.l (sp)+,d2/a2/a6
        rts
; wb_vfix(a2 = record): default icon: pointers to its own copy (the record may have been moved). Clobbers a0.
wb_vfix:
        tst.b   VE_DEF(a2)
        beq.s   .vf_ret
        lea     VE_DEFO(a2),a0
        move.l  a0,VE_DOBJ(a2)
        lea     VE_DEFI(a2),a0
        move.l  a0,VE_DEFO+DO_GADGET+GG_GADGETRENDER(a2)
.vf_ret:
        rts

; wb_vadd(d0 = BPTR of the volume node, a5) -> Z = 0 if an icon was added: next record filled (name, path,
; date, under Forbid and only if the node is still in the DosList with dl_Task); DiskObject of
; "<volume>:Disk", otherwise the default icon; position by wb_vplace. Preserves d2-d7/a2-a6.
wb_vadd:
        movem.l d2-d3/a2-a3/a6,-(sp)
        move.l  d0,d2
        cmp.w   #WB_MAXVOLS,WBS_NVOL(a5)
        bhs     .va_no
        move.w  WBS_NVOL(a5),d1
        bsr     wb_volent
        move.l  a0,a2                ; a2 = record (zeroed)
        move.w  #VE_SIZE/2-1,d0
.va_clr:
        clr.w   (a0)+
        dbra    d0,.va_clr
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        bsr     wb_devinfo
        move.l  (a0),d0
.va_find:
        cmp.l   d0,d2
        beq.s   .va_got
        lsl.l   #2,d0
        beq     .va_gone
        move.l  d0,a0
        move.l  DN_NEXT(a0),d0
        bra.s   .va_find
.va_got:
        lsl.l   #2,d0
        move.l  d0,a3
        tst.l   DN_TASK(a3)
        beq     .va_gone
        move.l  d2,VE_NODE(a2)
        move.l  DOL_VOLDATE(a3),VE_DATE(a2)
        move.l  DOL_VOLDATE+4(a3),VE_DATE+4(a2)
        move.l  DOL_VOLDATE+8(a3),VE_DATE+8(a2)
        move.l  DN_NAME(a3),d0
        lsl.l   #2,d0
        move.l  d0,a0
        moveq   #0,d0
        move.b  (a0)+,d0             ; BSTR
        cmp.w   #WBS_NAMEMAX-2,d0
        bls.s   .va_nl
        moveq   #WBS_NAMEMAX-2,d0
.va_nl:
        lea     VE_NAME(a2),a1
        lea     VE_PATH(a2),a3
        bra.s   .va_ne
.va_nc:
        move.b  (a0),(a1)+
        move.b  (a0)+,(a3)+
.va_ne:
        dbra    d0,.va_nc
        move.b  #':',(a3)+
        jsr     LVO_PERMIT(a6)
        lea     -WB_PATHMAX(sp),sp   ; "<volume>:Disk"
        lea     VE_PATH(a2),a0
        move.l  sp,a1
        moveq   #WB_PATHMAX-2,d0
        bsr     wb_strcpy
        move.l  sp,a0
        bsr     wb_strlen
        lea     0(sp,d0.w),a1
        lea     wb_diskicon(pc),a0
        moveq   #5,d0
        bsr     wb_strcpy
        moveq   #0,d0
        move.l  WBS_ICONBASE(a5),d1
        beq.s   .va_dobj
        move.l  d1,a6
        move.l  sp,a0
        jsr     ICON_LVO_GETDISKOBJECT(a6)
.va_dobj:
        lea     WB_PATHMAX(sp),sp
        move.l  d0,VE_DOBJ(a2)
        bne.s   .va_place
        bsr     wb_vdefault
.va_place:
        bsr     wb_vplace
        st      VE_SEEN(a2)
        addq.w  #1,WBS_NVOL(a5)
        moveq   #1,d0                ; Z = 0
        bra.s   .va_ret
.va_gone:
        jsr     LVO_PERMIT(a6)
.va_no:
        moveq   #0,d0                ; Z = 1
.va_ret:
        movem.l (sp)+,d2-d3/a2-a3/a6
        rts

; wb_vdefault(a2 = record, a5): default disk icon (spec disk-change-v34 §4.2): copy of wb_defobj and of its
; Image into the record, image data in CHIP if possible. Clobbers d0/a0/a1.
wb_vdefault:
        lea     wb_defobj(pc),a0
        lea     VE_DEFO(a2),a1
        moveq   #(78+IG_SIZE)/2-1,d0
.vd_cp:
        move.w  (a0)+,(a1)+
        dbra    d0,.vd_cp
        st      VE_DEF(a2)
        move.l  WBS_DEFIMG(a5),d0
        bne.s   .vd_img
        lea     wb_defdata(pc),a0
        move.l  a0,d0
.vd_img:
        move.l  d0,VE_DEFI+IG_IMAGEDATA(a2)
        bra     wb_vfix

; wb_vplace(a2 = new record, a5): VE_X/VE_Y of its icon among those already on the desktop (spec disk-change-v34
; §4.3). The position from the .info is kept if the rectangle [X-2, X+w+2] x [Y-m, Y+h+m] (m = room for the name)
; touches no icon; otherwise, 96-pixel columns from the right, in each the first gap from the top (y = 5 at the
; start, icons of the column taken by increasing Y) that fits in the window; failing that, (W-60, 5).
; Preserves d2-d7/a2-a6.
wb_vplace:
        movem.l d2-d7/a3-a4,-(sp)
        clr.l   VE_X(a2)
        move.l  WBS_WIN(a5),d0
        beq     .vp_ret
        move.l  d0,a3
        move.l  VE_DOBJ(a2),a4
        move.w  DO_GADGET+GG_WIDTH(a4),d6     ; d6 = w
        move.w  DO_GADGET+GG_HEIGHT(a4),d7    ; d7 = h
        cmp.l   #NO_ICON_POSITION,DO_CURRENTX(a4)
        beq.s   .vp_cols
        move.w  DO_CURRENTX+2(a4),d0
        move.w  DO_CURRENTY+2(a4),d1
        move.w  d0,d2                ; guard rectangle
        subq.w  #2,d2
        move.w  d0,d3
        add.w   d6,d3
        addq.w  #2,d3
        move.w  d1,d4
        sub.w   #WB_LABELH,d4
        move.w  d1,d5
        add.w   d7,d5
        add.w   #WB_LABELH,d5
        bsr     wb_vhit
        bne.s   .vp_cols
        move.w  d0,VE_X(a2)
        move.w  d1,VE_Y(a2)
        bra     .vp_ret
.vp_cols:
        move.w  WD_WIDTH(a3),d2
        sub.w   #WB_COLW,d2          ; d2 = x0
.vp_col:
        tst.w   d2
        bmi.s   .vp_none
        moveq   #5,d3                ; d3 = candidate y
        moveq   #0,d4                ; d4 = icons of the column already taken (bits)
.vp_next:
        bsr     wb_vlow              ; d0 = untaken column icon with the smallest Y | -1, a0 = its record
        bmi.s   .vp_fit
        bset    d0,d4
        move.w  d3,d1
        add.w   d7,d1
        add.w   #WB_LABELH,d1
        cmp.w   VE_Y(a0),d1
        ble.s   .vp_fit              ; the gap above this icon is enough
        move.l  VE_DOBJ(a0),a1
        move.w  VE_Y(a0),d1
        add.w   DO_GADGET+GG_HEIGHT(a1),d1
        add.w   #WB_LABELH,d1
        cmp.w   d1,d3
        bge.s   .vp_next
        move.w  d1,d3
        bra.s   .vp_next
.vp_fit:
        move.w  d3,d1
        add.w   d7,d1
        add.w   #WB_LABELH,d1
        move.w  WD_HEIGHT(a3),d0
        subq.w  #5,d0
        cmp.w   d0,d1
        bgt.s   .vp_left
        move.w  #WB_COLW,d0
        sub.w   d6,d0
        asr.w   #1,d0
        add.w   d2,d0
        move.w  d0,VE_X(a2)
        move.w  d3,VE_Y(a2)
        bra.s   .vp_ret
.vp_left:
        sub.w   #WB_COLW,d2
        bra.s   .vp_col
.vp_none:
        move.w  WD_WIDTH(a3),d0
        sub.w   #60,d0
        move.w  d0,VE_X(a2)
        move.w  #5,VE_Y(a2)
.vp_ret:
        movem.l (sp)+,d2-d7/a3-a4
        rts
; wb_vhit(d2..d5 = rectangle x0, x1, y0, y1, a5) -> Z = 0 if it touches the icon of an already placed volume (records
; 0..NVOL-1). Preserves d2-d7/a2-a6 and d0/d1.
wb_vhit:
        movem.l d0-d1/d6/a1,-(sp)
        moveq   #0,d6
.vh_lp:
        cmp.w   WBS_NVOL(a5),d6
        bhs.s   .vh_no
        move.w  d6,d1
        bsr     wb_volent
        move.l  VE_DOBJ(a0),a1
        move.w  VE_X(a0),d0
        cmp.w   d3,d0
        bgt.s   .vh_nx
        add.w   DO_GADGET+GG_WIDTH(a1),d0
        cmp.w   d2,d0
        blt.s   .vh_nx
        move.w  VE_Y(a0),d0
        cmp.w   d5,d0
        bgt.s   .vh_nx
        add.w   DO_GADGET+GG_HEIGHT(a1),d0
        cmp.w   d4,d0
        bge.s   .vh_yes
.vh_nx:
        addq.w  #1,d6
        bra.s   .vh_lp
.vh_yes:
        movem.l (sp)+,d0-d1/d6/a1    ; (movem to registers does not touch the condition codes)
        andi.b  #$FB,ccr             ; Z = 0
        rts
.vh_no:
        movem.l (sp)+,d0-d1/d6/a1
        ori.b   #$04,ccr             ; Z = 1
        rts
; wb_vlow(d2 = x0 of the column, d4 = icons already taken, a5) -> d0 = number of the icon of column [x0, x0+96[ with
; the smallest Y among the others, a0 = its record; d0 = -1 (N = 1) if there are none left. Preserves d1-d7/a1-a6.
wb_vlow:
        movem.l d1/d5-d6/a1,-(sp)
        moveq   #-1,d5               ; best: number
        moveq   #0,d6
.vl_lp:
        cmp.w   WBS_NVOL(a5),d6
        bhs.s   .vl_end
        btst    d6,d4
        bne.s   .vl_nx
        move.w  d6,d1
        bsr     wb_volent
        move.l  VE_DOBJ(a0),a1
        move.w  VE_X(a0),d0
        move.w  d2,d1
        add.w   #WB_COLW-1,d1
        cmp.w   d1,d0
        bgt.s   .vl_nx
        add.w   DO_GADGET+GG_WIDTH(a1),d0
        cmp.w   d2,d0
        blt.s   .vl_nx
        tst.w   d5
        bmi.s   .vl_take
        move.w  d5,d1
        move.l  a0,a1
        bsr     wb_volent
        move.w  VE_Y(a0),d0
        move.l  a1,a0
        cmp.w   VE_Y(a0),d0
        ble.s   .vl_nx
.vl_take:
        move.w  d6,d5
.vl_nx:
        addq.w  #1,d6
        bra.s   .vl_lp
.vl_end:
        move.w  d5,d1
        bmi.s   .vl_ret
        bsr     wb_volent
.vl_ret:
        move.w  d5,d0
        ext.l   d0
        movem.l (sp)+,d1/d5-d6/a1
        tst.l   d0
        rts

; wb_nwclear(sp+4 = NewWindow reserved by the caller) -> a0 = zeroed NewWindow, screen pens, type WBENCHSCREEN.
; Clobbers d1.
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

; wb_openlib(a1 = name) -> d0 = base | 0 (OpenLibrary version 0).
wb_openlib:
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  (sp)+,a6
        rts

; wb_setmenus(a0 = window, a5): attaches the Workbench menu bar to it. Preserves d2-d7/a2-a6.
wb_setmenus:
        move.l  a6,-(sp)
        lea     WBS_MENUS(a5),a1
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_SETMENUSTRIP(a6)
        move.l  (sp)+,a6
        rts

; wb_sigbit(a0 = window | 0, d0 = mask) -> d0 |= bit of the window's IDCMP port. Clobbers d1/a0.
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

; wb_window(d7.w = window number, a5) -> a3 = window | 0, a4 = drawer record (number > 0); Z = 1 if no window.
; Clobbers d0.
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

; wb_dispatch(d7.w = window number, a5): handles the IDCMP messages of the window (already replied by wb_getmsg):
; REFRESHWINDOW -> redraw of the damaged areas; SELECTDOWN -> click; MENUPICK -> menu; CLOSEWINDOW -> closing of the
; drawer (end of processing: the window no longer exists). Preserves d7/a5.
wb_dispatch:
        bsr     wb_window
        beq     .dp_ret
        move.l  ($4).w,a6
        move.l  a3,a0
        bsr     wb_getmsg            ; d2 = class, d3 = code, d4/d5 = mouse, d6 = seconds, a0 = micros
        beq     .dp_ret
        tst.w   d7
        beq.s   .dp_ref
        bsr     wb_scrollev          ; scroll gadgets of a drawer
        bne     wb_dispatch
        cmp.l   #NEWSIZE,d2
        bne.s   .dp_ref
        bsr     wb_bars              ; new size: bars recomputed (the drawing follows REFRESHWINDOW)
        bra     wb_dispatch
.dp_ref:
        move.l  d2,d0
        and.l   #DISKINSERTED|DISKREMOVED,d0
        beq.s   .dp_rf
        bsr     wb_vscan             ; floppy inserted or ejected: volumes scanned
        bra     wb_dispatch
.dp_rf:
        cmp.l   #REFRESHWINDOW,d2
        bne.s   .dp_mb
        bsr     wb_repair
        bra     wb_dispatch
.dp_mb:
        cmp.l   #MOUSEBUTTONS,d2
        bne.s   .dp_mv
        cmp.w   #SELECTDOWN,d3
        bne.s   .dp_up
        bsr     wb_restore           ; left click: the memory title comes back (spec §6.2)
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
        bra     wb_dispatch
.dp_close:
        cmp.l   #CLOSEWINDOW,d2
        bne     wb_dispatch
        tst.w   d7
        beq     wb_dispatch
        bra     wb_closedrawer
.dp_ret:
        rts

; wb_getmsg(a0 = window, a6 = SysBase) -> Z = 1 if no message; otherwise d2 = class, d3 = code, d4/d5 = mouse,
; d6 = seconds, a0 = micros, and the message is already replied (it belongs to the window). Clobbers d0/d1/a1.
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
        move.l  IM_IADDRESS(a1),WBS_MADDR(a5)
        move.w  IM_QUALIFIER(a1),WBS_MQUAL(a5)
        move.l  IM_MICROS(a1),-(sp)
        jsr     LVO_REPLYMSG(a6)
        move.l  (sp)+,a0
        moveq   #1,d0                ; Z = 0
        rts
.gm_none:
        moveq   #0,d0
        rts

; --- scrolling of drawers and gauge of disks (spec workbench-task-v34 §8) -----------------------------------------
; wb_origin(a3 = window, a4 = record) -> d0/d1 = corner of the icon space in the window: left border (plus
; the gauge of a disk) and top border, minus the scroll position. Preserves everything else.
wb_origin:
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        tst.b   DR_DISK(a4)
        beq.s   .or_x
        add.w   #WB_DISKGAUGE,d0
.or_x:
        sub.w   DR_SX(a4),d0
        moveq   #0,d1
        move.b  WD_BORDERTOP(a3),d1
        sub.w   DR_SY(a4),d1
        rts

; wb_content(a3 = window, a4 = record | 0) -> d0..d3 = visible icon area (x0, y0, x1, y1 in the window): without
; the borders or the gauge of a disk. Preserves everything else.
wb_content:
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a3),d0
        move.l  a4,d1
        beq.s   .ct_x
        tst.b   DR_DISK(a4)
        beq.s   .ct_x
        add.w   #WB_DISKGAUGE,d0
.ct_x:
        moveq   #0,d1
        move.b  WD_BORDERTOP(a3),d1
        move.l  d4,-(sp)
        move.w  WD_WIDTH(a3),d2
        moveq   #0,d4
        move.b  WD_BORDERRIGHT(a3),d4
        sub.w   d4,d2
        subq.w  #1,d2
        move.w  WD_HEIGHT(a3),d3
        move.b  WD_BORDERBOTTOM(a3),d4
        sub.w   d4,d3
        subq.w  #1,d3
        move.l  (sp)+,d4
        rts

; wb_mkgads(a4 = record) -> a0 = first of the 6 scroll gadgets, built in the record from wb_gadtab:
; bars (PropInfo AUTOKNOB, Pots 0, Bodies $FFFF, FREEVERT / FREEHORIZ; empty knob Image) then arrows (Images
; of WBS_ARROWS). Preserves d2-d7/a2-a6.
wb_mkgads:
        movem.l d2-d3/a2-a3,-(sp)
        lea     DR_GADS(a4),a0
        move.w  #6*GG_SIZEOF+2*PI_SIZE+2*IG_SIZE-1,d0
.mg_clr:
        clr.b   (a0)+
        dbra    d0,.mg_clr
        lea     wb_gadtab(pc),a2
        lea     DR_GADS(a4),a3
        moveq   #5,d3
.mg_lp:
        movem.w (a2)+,d0-d1          ; LeftEdge, TopEdge
        move.w  d0,GG_LEFTEDGE(a3)
        move.w  d1,GG_TOPEDGE(a3)
        movem.w (a2)+,d0-d1          ; Width, Height
        move.w  d0,GG_WIDTH(a3)
        move.w  d1,GG_HEIGHT(a3)
        move.w  (a2)+,GG_FLAGS(a3)
        move.w  (a2)+,GG_ACTIVATION(a3)
        move.w  (a2)+,GG_GADGETTYPE(a3)
        move.w  (a2)+,GG_GADGETID(a3)
        move.w  (a2)+,d2             ; rendering: 0/1 = vertical/horizontal bar, 2..5 = arrow
        cmp.w   #2,d2
        bhs.s   .mg_arrow
        move.w  d2,d0
        mulu    #PI_SIZE,d0
        lea     DR_PROPS(a4),a0
        add.w   d0,a0
        move.l  a0,GG_SPECIALINFO(a3)
        move.w  #AUTOKNOB|FREEVERT,PI_FLAGS(a0)
        tst.w   d2
        beq.s   .mg_pv
        move.w  #AUTOKNOB|FREEHORIZ,PI_FLAGS(a0)
.mg_pv:
        moveq   #-1,d0
        move.w  d0,PI_HBODY(a0)
        move.w  d0,PI_VBODY(a0)
        move.w  d2,d0
        mulu    #IG_SIZE,d0
        lea     DR_KNOBS(a4),a0
        add.w   d0,a0
        move.l  a0,GG_GADGETRENDER(a3)
        bra.s   .mg_next
.mg_arrow:
        move.l  WBS_ARROWS(a5),d0
        beq.s   .mg_next
        subq.w  #2,d2
        mulu    #IG_SIZE,d2
        add.l   d2,d0
        move.l  d0,GG_GADGETRENDER(a3)
.mg_next:
        lea     GG_SIZEOF(a3),a0
        tst.w   d3
        beq.s   .mg_last
        move.l  a0,GG_NEXTGADGET(a3)
.mg_last:
        move.l  a0,a3
        dbra    d3,.mg_lp
        lea     DR_GADS(a4),a0
        movem.l (sp)+,d2-d3/a2-a3
        rts

; wb_arrowsinit(a5): the 4 arrow Images (structures and data) copied once into CHIP memory, where the
; DMA reads them. Without memory: arrows without an image. Preserves d2-d7/a2-a5.
WB_ARROWSZ      EQU 4*IG_SIZE+(wb_arrdata_end-wb_arrdata)
wb_arrowsinit:
        tst.l   WBS_ARROWS(a5)
        bne.s   .ai_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        move.l  #WB_ARROWSZ,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,WBS_ARROWS(a5)
        beq.s   .ai_pop
        move.l  d0,a1
        lea     wb_arrimg(pc),a0     ; structures, then data right after
        moveq   #WB_ARROWSZ/2-1,d0
.ai_cp:
        move.w  (a0)+,(a1)+
        dbra    d0,.ai_cp
        move.l  WBS_ARROWS(a5),a1    ; ImageData pointers: offsets in the block -> addresses
        move.l  WBS_ARROWS(a5),d1
        moveq   #3,d0
.ai_fix:
        add.l   d1,IG_IMAGEDATA(a1)
        lea     IG_SIZE(a1),a1
        dbra    d0,.ai_fix
.ai_pop:
        move.l  (sp)+,a6
.ai_ret:
        rts

; wb_bars(d7.w = drawer, a5): extent = visible area at the current position enlarged to the box of each icon;
; then, per axis, Body = 65535 x visible / range and Pot = 65535 x (position - min) / (range - visible) ($7FFF if the
; range is the visible area); NewModifyProp of a single gadget if a value changes (spec §8.2-8.3). Preserves d2-d7.
wb_bars:
        movem.l d2-d7/a2-a4/a6,-(sp)
        bsr     wb_window
        beq     .ba_ret
        bsr     wb_content
        sub.w   d0,d2
        addq.w  #1,d2                ; d2 = visible width
        sub.w   d1,d3
        addq.w  #1,d3                ; d3 = visible height
        move.w  DR_SX(a4),d4         ; d4..d7 = extent
        move.w  DR_SY(a4),d5
        move.w  d4,d6
        add.w   d2,d6
        move.w  d5,d7
        add.w   d3,d7
        moveq   #0,d1
.ba_icon:
        cmp.w   DR_NICON+2(a4),d1
        bhs.s   .ba_props
        move.w  d1,d0
        lsl.w   #2,d0
        move.l  DR_ICONS(a4,d0.w),a2
        movem.w d2-d3,-(sp)
        move.w  #WB_GRIDX,d2         ; position of the icon in the drawer space (like wb_iconrect)
        mulu    d1,d2
        moveq   #4,d3
        cmp.l   #NO_ICON_POSITION,DO_CURRENTX(a2)
        beq.s   .ba_pos
        move.w  DO_CURRENTX+2(a2),d2
        move.w  DO_CURRENTY+2(a2),d3
.ba_pos:
        cmp.w   d4,d2
        bge.s   .ba_x0
        move.w  d2,d4
.ba_x0:
        cmp.w   d5,d3
        bge.s   .ba_y0
        move.w  d3,d5
.ba_y0:
        add.w   DO_GADGET+GG_WIDTH(a2),d2
        cmp.w   d6,d2
        ble.s   .ba_x1
        move.w  d2,d6
.ba_x1:
        add.w   DO_GADGET+GG_HEIGHT(a2),d3
        cmp.w   d7,d3
        ble.s   .ba_y1
        move.w  d3,d7
.ba_y1:
        movem.w (sp)+,d2-d3
        addq.w  #1,d1
        bra.s   .ba_icon
.ba_props:
        movem.w d4-d7,DR_EMINX(a4)
        lea     DR_GADS+GG_SIZEOF(a4),a2 ; horizontal bar
        move.w  d2,d0                ; visible
        move.w  d6,d1
        sub.w   d4,d1                ; range
        move.w  DR_SX(a4),d2
        sub.w   d4,d2                ; position - min
        bsr.s   .ba_set
        lea     DR_GADS(a4),a2       ; vertical bar
        move.w  d3,d0
        move.w  d7,d1
        sub.w   d5,d1
        move.w  DR_SY(a4),d2
        sub.w   d5,d2
        bsr.s   .ba_set
.ba_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts
.ba_set:                             ; a2 = bar, d0 = visible, d1 = range, d2 = position -> NewModifyProp if needed
        movem.l d3-d7,-(sp)
        moveq   #-1,d3               ; d3 = Body
        cmp.w   d0,d1
        bls.s   .bs_pot              ; range = visible (or less): $FFFF
        move.l  #$FFFF,d3
        mulu    d0,d3
        divu    d1,d3
.bs_pot:
        move.w  #$7FFF,d4            ; d4 = Pot
        sub.w   d0,d1                ; range - visible
        bls.s   .bs_cmp
        tst.w   d2
        bpl.s   .bs_pos
        moveq   #0,d2
.bs_pos:
        moveq   #0,d4
        move.w  d2,d4
        mulu    #$FFFF,d4
        divu    d1,d4
.bs_cmp:
        move.l  GG_SPECIALINFO(a2),a0
        move.w  PI_FLAGS(a0),d0
        btst    #1,d0                ; FREEHORIZ: its axis is H, otherwise V
        beq.s   .bs_v
        cmp.w   PI_HPOT(a0),d4
        bne.s   .bs_mod
        cmp.w   PI_HBODY(a0),d3
        beq.s   .bs_ret
        bra.s   .bs_mod
.bs_v:
        cmp.w   PI_VPOT(a0),d4
        bne.s   .bs_mod
        cmp.w   PI_VBODY(a0),d3
        beq.s   .bs_ret
.bs_mod:
        move.l  a2,a0
        move.l  a3,a1
        move.l  a2,-(sp)
        suba.l  a2,a2
        move.w  d4,d1
        move.w  d4,d2
        move.w  d3,d4
        moveq   #1,d5
        move.l  WBS_IBASE(a5),a6
        jsr     WB_LVO_NEWMODIFYPROP(a6)
        move.l  (sp)+,a2
.bs_ret:
        movem.l (sp)+,d3-d7
        rts

; wb_scrollto(d7.w = drawer, d0.w/d1.w = new position, a5): new scroll position, bars
; recomputed, interior redrawn; nothing if it does not change. Preserves d2-d7.
wb_scrollto:
        movem.l a3-a4,-(sp)
        move.l  d0,-(sp)
        bsr     wb_window
        move.l  (sp)+,d0
        cmp.w   DR_SX(a4),d0
        bne.s   .st_set
        cmp.w   DR_SY(a4),d1
        beq.s   .st_ret
.st_set:
        move.w  d0,DR_SX(a4)
        move.w  d1,DR_SY(a4)
        bsr     wb_bars
        bsr     wb_redraw1
.st_ret:
        movem.l (sp)+,a3-a4
        rts

; wb_scrollev(d7.w = drawer, d2 = class, a5): GADGETDOWN on a scroll gadget: it becomes the held gadget;
; an arrow advances by one eighth of the visible area (Shift: 1 pixel, a single step). Arrow held without Shift:
; INTUITICKS is added to the IDCMP and each INTUITICKS or MOUSEMOVE advances one step (spec workbench-task-v34 §8.3).
; MOUSEMOVE and GADGETUP on a held bar: the position follows its Pot; GADGETUP ends the scrolling (and removes
; INTUITICKS). Z = 0 if the event was for scrolling.
wb_scrollev:
        movem.l d2-d6/a2-a4,-(sp)
        bsr     wb_window
        beq     .se_no
        cmp.l   #GADGETDOWN,d2
        bne     .se_held
        move.l  WBS_MADDR(a5),a2
        lea     DR_GADS(a4),a0
        cmp.l   a0,a2
        blo     .se_no
        lea     DR_GADS+6*GG_SIZEOF(a4),a0
        cmp.l   a0,a2
        bhs     .se_no
        move.w  d7,WBS_SCRW(a5)
        move.l  a2,WBS_SCRGAD(a5)
        move.w  GG_GADGETID(a2),d6
        move.w  d6,WBS_SCRG(a5)
        cmp.w   #3,d6
        blo     .se_yes              ; bar: the position will follow its Pot
        move.w  WBS_MQUAL(a5),d0
        and.w   #KQ_SHIFT,d0
        bne.s   .se_once             ; Shift: a single one-pixel step
        move.w  #1,WBS_SCRTICK(a5)
        move.l  WD_IDCMPFLAGS(a3),d0
        or.l    #INTUITICKS,d0
        bsr     .se_idcmp
.se_once:
        bsr.s   .se_arrow
        bra     .se_yes
.se_arrow:                           ; d6 = arrow (3..6): step of one eighth of the visible area (Shift: 1)
        bsr     wb_content
        sub.w   d0,d2
        addq.w  #1,d2
        lsr.w   #3,d2
        sub.w   d1,d3
        addq.w  #1,d3
        lsr.w   #3,d3
        move.w  WBS_MQUAL(a5),d0
        and.w   #KQ_SHIFT,d0
        beq.s   .se_step
        moveq   #1,d2
        moveq   #1,d3
.se_step:
        move.w  DR_SX(a4),d0
        move.w  DR_SY(a4),d1
        cmp.w   #3,d6
        bne.s   .se_r
        sub.w   d2,d0
.se_r:
        cmp.w   #4,d6
        bne.s   .se_u
        add.w   d2,d0
.se_u:
        cmp.w   #5,d6
        bne.s   .se_d
        sub.w   d3,d1
.se_d:
        cmp.w   #6,d6
        bne.s   .se_go
        add.w   d3,d1
.se_go:
        bra     wb_scrollto
.se_held:
        tst.w   WBS_SCRG(a5)
        beq     .se_no
        cmp.w   WBS_SCRW(a5),d7
        bne     .se_no
        cmp.l   #INTUITICKS,d2
        beq.s   .se_rep
        cmp.l   #MOUSEMOVE,d2
        bne.s   .se_up
        bsr.s   .se_bar
.se_rep:                             ; arrow held: one step per INTUITICKS / MOUSEMOVE, as long as it is selected
        tst.w   WBS_SCRTICK(a5)
        beq     .se_yes
        move.l  WBS_SCRGAD(a5),a0
        btst    #7,GG_FLAGS+1(a0)    ; SELECTED: released outside the arrow (no GADGETUP) -> end
        beq.s   .se_end
        move.w  WBS_SCRG(a5),d6
        bsr     .se_arrow
        bra     .se_yes
.se_up:
        cmp.l   #GADGETUP,d2
        bne     .se_no
        bsr.s   .se_bar
.se_end:
        clr.w   WBS_SCRG(a5)         ; end of scrolling
        tst.w   WBS_SCRTICK(a5)
        beq     .se_yes
        clr.w   WBS_SCRTICK(a5)
        move.l  WD_IDCMPFLAGS(a3),d0
        and.l   #~INTUITICKS,d0
        bsr     .se_idcmp
        bra     .se_yes
.se_bar:                             ; bar held: position = Pot / 65535 x (range - visible) + min
        move.w  WBS_SCRG(a5),d6
        cmp.w   #3,d6
        bhs.s   .sb_ret
        bsr     wb_content
        sub.w   d0,d2
        addq.w  #1,d2
        sub.w   d1,d3
        addq.w  #1,d3
        move.w  DR_SX(a4),d0
        move.w  DR_SY(a4),d1
        cmp.w   #1,d6
        bne.s   .sb_v
        move.l  DR_GADS+GG_SIZEOF+GG_SPECIALINFO(a4),a0
        move.w  PI_HPOT(a0),d4
        move.w  DR_EMAXX(a4),d5
        sub.w   DR_EMINX(a4),d5
        sub.w   d2,d5
        bsr.s   .sb_pos
        add.w   DR_EMINX(a4),d4
        move.w  d4,d0
        bra.s   .sb_go
.sb_v:
        move.l  DR_GADS+GG_SPECIALINFO(a4),a0
        move.w  PI_VPOT(a0),d4
        move.w  DR_EMAXY(a4),d5
        sub.w   DR_EMINY(a4),d5
        sub.w   d3,d5
        bsr.s   .sb_pos
        add.w   DR_EMINY(a4),d4
        move.w  d4,d1
.sb_go:
        bsr     wb_scrollto
.sb_ret:
        rts
.se_idcmp:                           ; ModifyIDCMP(a3, d0)
        move.l  a6,-(sp)
        move.l  a3,a0
        move.l  WBS_IBASE(a5),a6
        jsr     WB_LVO_MODIFYIDCMP(a6)
        move.l  (sp)+,a6
        rts
.sb_pos:                             ; d4 = Pot, d5 = range - visible -> d4 = Pot x (range - visible) / 65535
        tst.w   d5
        bgt.s   .sp_mul
        moveq   #0,d4
        rts
.sp_mul:
        and.l   #$FFFF,d4
        mulu    d5,d4
        divu    #$FFFF,d4
        rts
.se_yes:
        moveq   #1,d0
        bra.s   .se_out
.se_no:
        moveq   #0,d0
.se_out:
        movem.l (sp)+,d2-d6/a2-a4
        tst.l   d0
        rts

; wb_gaugeinfo(d7.w = drawer, a5): used and total blocks of the drawer's volume (Info), for the gauge of a disk.
; Preserves d2-d7/a2-a5.
wb_gaugeinfo:
        movem.l d2/a2-a4/a6,-(sp)
        bsr     wb_window
        beq.s   .gi_ret
        tst.b   DR_DISK(a4)
        beq.s   .gi_ret
        lea     -40(sp),sp
        move.l  WBS_DOSBASE(a5),a6
        lea     DR_PATH(a4),a0
        move.l  a0,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,-(sp)
        beq.s   .gi_free
        move.l  d0,d1
        lea     4+3(sp),a0
        move.l  a0,d2
        and.b   #$FC,d2              ; long-aligned InfoData
        move.l  d2,a2
        jsr     DOS_LVO_INFO(a6)
        tst.l   d0
        beq.s   .gi_unl
        move.l  ID_NUMBLOCKSUSED(a2),DR_USED(a4)
        move.l  ID_NUMBLOCKS(a2),DR_TOTAL(a4)
.gi_unl:
        move.l  (sp),d1
        jsr     DOS_LVO_UNLOCK(a6)
.gi_free:
        lea     44(sp),sp
.gi_ret:
        movem.l (sp)+,d2/a2-a4/a6
        rts

; wb_gauge(a3 = window, a4 = record, a5): fill gauge of a disk window, against the left edge (spec
; §8.4): "F" block at the top and "E" block at the bottom in pen 2 (letters in pen 1), rule in pen 1 on the
; right, empty bar in pen 2 and filled in pen 3 in proportion to the used blocks. Preserves d2-d7/a2-a5.
wb_gauge:
        tst.b   DR_DISK(a4)
        beq     .ga_ret
        movem.l d2-d7/a2/a6,-(sp)
        move.l  WBS_GFXBASE(a5),a6
        moveq   #0,d6
        move.b  WD_BORDERLEFT(a3),d6
        add.w   #9,d6                ; d6 = right x of the gauge
        moveq   #0,d4
        move.b  WD_BORDERTOP(a3),d4  ; d4 = BT
        move.w  WD_HEIGHT(a3),d5
        moveq   #0,d0
        move.b  WD_BORDERBOTTOM(a3),d0
        sub.w   d0,d5                ; d5 = H - BB
        lea     wb_gaugetab(pc),a2   ; rectangles: pen, x0, y0, x1, y1 (relative y: 0 = BT, 1 = H - BB; x: -1 = right)
.ga_lp:
        move.b  (a2)+,d0
        bmi.s   .ga_bar
        ext.w   d0
        move.l  WD_RPORT(a3),a1
        jsr     LVO_SETAPEN(a6)
        bsr.s   .ga_x
        move.w  d0,d2
        bsr.s   .ga_y
        move.w  d0,d1
        move.w  d2,d0
        movem.w d0-d1,-(sp)
        bsr.s   .ga_x
        move.w  d0,d2
        bsr.s   .ga_y
        move.w  d0,d3
        movem.w (sp)+,d0-d1
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        bra.s   .ga_lp
.ga_x:                               ; signed byte: >= 0 absolute x, < 0 offset from the right of the gauge
        move.b  (a2)+,d0
        ext.w   d0
        bpl.s   .gx_r
        add.w   d6,d0
        addq.w  #1,d0
.gx_r:
        rts
.ga_y:                               ; base (0: BT, 1: H - BB) then signed offset
        move.b  (a2)+,d1
        move.b  (a2)+,d0
        ext.w   d0
        tst.b   d1
        bne.s   .gy_b
        add.w   d4,d0
        rts
.gy_b:
        add.w   d5,d0
        rts
.ga_bar:
        moveq   #1,d0                ; rule in pen 1, to the right of the gauge (2 pixels), over its whole height
        move.l  WD_RPORT(a3),a1
        jsr     LVO_SETAPEN(a6)
        move.w  d6,d0
        addq.w  #1,d0
        move.w  d4,d1
        subq.w  #1,d1
        move.w  d6,d2
        addq.w  #2,d2
        move.w  d5,d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        move.w  d4,d2
        addq.w  #6,d2                ; y0
        move.w  d5,d3
        subq.w  #7,d3                ; y1
        move.w  d3,d7
        sub.w   d2,d7                ; d7 = h
        moveq   #0,d0                ; filled = round(used x h / total)
        move.l  DR_TOTAL(a4),d1
        beq.s   .ga_fill
        move.l  DR_USED(a4),d0
        mulu    d7,d0
        add.l   d0,d0
        add.l   d1,d0
        add.l   d1,d1
        divu    d1,d0
.ga_fill:
        move.w  d2,d4
        add.w   d7,d4
        sub.w   d0,d4                ; d4 = top of the filled part
        moveq   #2,d0
        move.l  WD_RPORT(a3),a1
        jsr     LVO_SETAPEN(a6)
        moveq   #2,d0
        move.w  d2,d1
        move.w  d6,d2
        move.w  d4,d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        moveq   #3,d0
        move.l  WD_RPORT(a3),a1
        jsr     LVO_SETAPEN(a6)
        moveq   #2,d0
        move.w  d4,d1
        move.w  d6,d2
        move.w  d5,d3
        subq.w  #7,d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d2-d7/a2/a6
.ga_ret:
        rts

; wb_iconrect(d7.w = window, d1.w = icon number, a5) -> a2 = DiskObject, d0..d3 = x0,y0,x1,y1 in the window;
; Z = 1 if the icon does not exist. Desktop: the icon of volume number d1 at its position (VE_X, VE_Y); drawer:
; position from the .info (otherwise grid) offset by the left and top borders. Clobbers a0/a1.
wb_iconrect:
        tst.w   d7
        bne.s   .ir_dr
        cmp.w   WBS_NVOL(a5),d1
        bhs.s   .ir_none
        bsr     wb_volent            ; a0 = volume record
        move.l  VE_DOBJ(a0),a2
        move.w  VE_X(a0),d0
        move.w  VE_Y(a0),d1
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
        movem.w d0-d1,-(sp)          ; position in the drawer space -> window (wb_origin)
        exg     a1,a3
        bsr     wb_origin
        exg     a1,a3
        add.w   (sp)+,d0
        add.w   (sp)+,d1
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

; wb_drawwin(d7.w = window, a5): draws its icons (and the name of each one below it); the selection is re-inverted.
; Preserves d2-d7/a2-a6.
wb_drawwin:
        movem.l d2-d7/a2-a4/a6,-(sp)
        bsr     wb_window
        beq     .dw_ret
        tst.w   d7
        bne.s   .dw_dr
        moveq   #0,d6                ; desktop: the volume icons
.dw_vol:
        cmp.w   WBS_NVOL(a5),d6
        bhs.s   .dw_ret
        move.w  d6,d1
        bsr     wb_volent
        move.l  VE_DOBJ(a0),a2
        move.w  VE_X(a0),d4
        move.w  VE_Y(a0),d5
        lea     VE_NAME(a0),a4
        bsr     wb_drawicon
        addq.w  #1,d6
        bra.s   .dw_vol
.dw_dr:
        bsr     wb_gauge             ; window of a disk: its gauge (outside the contents, hence outside the update)
        bsr.s   wb_drawicons
.dw_ret:
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts

; wb_drawicons(d7.w = drawer, a4 = its record, a5): all its icons, in an update limited to the contents.
; Preserves d2-d7/a2-a4.
wb_drawicons:
        move.l  d6,-(sp)
        moveq   #1,d0
        bsr     wb_updopen
        moveq   #0,d6                ; d6 = icon
.di_lp:
        cmp.w   DR_NICON+2(a4),d6
        bhs.s   .di_end
        bsr.s   wb_drawone
        addq.w  #1,d6
        bra.s   .di_lp
.di_end:
        bsr     wb_updclose
        move.l  (sp)+,d6
        rts

; wb_drawone(d7.w = drawer, d6.w = icon, a5): draws the whole icon, name included, in an update limited to the
; contents: layers clips an icon straddling the edge (spec wb-icon-clipping-v34 §3). Only an icon more than
; 4 times the screen size away is not drawn (§4). Preserves d2-d7/a2-a4.
wb_drawone:
        movem.l d2-d7/a2-a4,-(sp)
        bsr     wb_window            ; a3/a4 (before wb_iconrect: wb_window clobbers d0)
        move.w  d6,d1
        bsr     wb_iconrect
        beq.s   .do_ret
        bsr     wb_toofar
        bne.s   .do_ret
        moveq   #1,d0
        bsr     wb_updopen
        move.w  d6,d1
        bsr     wb_iconrect          ; position re-read (wb_updopen clobbers d0/d1)
        move.w  d0,d4
        move.w  d1,d5
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a4
        bsr     wb_drawicon
        bsr     wb_updclose
.do_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; wb_toofar(a3 = window, d0/d1 = position of the icon in the window) -> Z = 0 if |x| > 4 x width or |y| > 4 x
; height of the screen (safeguard for 16-bit coordinates, spec wb-icon-clipping-v34 §4). Preserves everything but
; the CCR.
wb_toofar:
        movem.l d0-d3/a0,-(sp)
        move.l  WD_WSCREEN(a3),a0
        move.w  SC_WIDTH(a0),d2
        lsl.w   #2,d2
        move.w  SC_HEIGHT(a0),d3
        lsl.w   #2,d3
        tst.w   d0
        bpl.s   .tf_x
        neg.w   d0
.tf_x:
        tst.w   d1
        bpl.s   .tf_y
        neg.w   d1
.tf_y:
        cmp.w   d2,d0
        bgt.s   .tf_far
        cmp.w   d3,d1
        bgt.s   .tf_far
        moveq   #0,d0                ; Z = 1
        bra.s   .tf_ret
.tf_far:
        moveq   #1,d0                ; Z = 0
.tf_ret:
        movem.l (sp)+,d0-d3/a0
        rts

; wb_updopen(d7.w = window, d0 = mode, a5): WB drawing is limited to the contents of the window (spec
; wb-icon-clipping-v34 §1). At the first level only: layer locked (LockLayerRom), then mode 1: damage
; replaced by the contents rectangle (the real damage kept in UserData); mode 0: damage AND contents; BeginUpdate.
; Preserves d2-d7/a2-a5; clobbers d0/d1/a0/a1/a6.
wb_updopen:
        addq.w  #1,WBS_UPDCNT(a5)
        cmp.w   #1,WBS_UPDCNT(a5)
        bne     .uo_r
        movem.l d2-d6/a2-a4,-(sp)
        move.l  d0,d6
        bsr     wb_window
        tst.w   d7
        bne.s   .uo_dr
        suba.l  a4,a4                ; desktop: no gauge
.uo_dr:
        bsr     wb_content
        movem.w d0-d3,-(sp)          ; contents rectangle (layer coordinates)
        move.l  WD_RPORT(a3),a0
        move.l  (a0),a2              ; rp_Layer
        move.l  WBS_GFXBASE(a5),a6
        exg     a2,a5
        jsr     LVO_LOCKLAYERROM(a6)
        exg     a2,a5
        clr.l   WD_USERDATA(a3)
        tst.l   d6
        beq.s   .uo_and
        jsr     LVO_NEWREGION(a6)
        tst.l   d0
        beq.s   .uo_clr
        move.l  IL_DAMAGE(a2),WD_USERDATA(a3)
        move.l  d0,IL_DAMAGE(a2)
.uo_clr:
        move.l  IL_DAMAGE(a2),a0
        jsr     LVO_CLEARREGION(a6)
        move.l  IL_DAMAGE(a2),a0
        move.l  sp,a1
        jsr     LVO_ORRECTREGION(a6)
        bra.s   .uo_upd
.uo_and:
        move.l  IL_DAMAGE(a2),a0
        move.l  sp,a1
        jsr     LVO_ANDRECTREGION(a6)
.uo_upd:
        addq.l  #8,sp
        move.l  WBS_IBASE(a5),a6
        move.l  IB_LAYERSBASE(a6),a6
        move.l  a2,a0
        jsr     LVO_BEGINUPDATE(a6)
        movem.l (sp)+,d2-d6/a2-a4
.uo_r:
        rts

; wb_updclose(d7.w = window, a5): end of wb_updopen (§2). At the last level: mode 1 -> WB region freed, real
; damage put back, EndUpdate(FALSE); otherwise LAYERREFRESH cleared and EndUpdate(TRUE); unlock. Preserves d2-d7/a2-a5;
; clobbers d0/d1/a0/a1/a6.
wb_updclose:
        subq.w  #1,WBS_UPDCNT(a5)
        bne     .uc_r
        movem.l d2/a2-a4,-(sp)
        bsr     wb_window
        move.l  WD_RPORT(a3),a0
        move.l  (a0),a2
        moveq   #0,d2                ; d2 = EndUpdate flag
        move.l  WD_USERDATA(a3),d0
        beq.s   .uc_rep
        move.l  WBS_GFXBASE(a5),a6
        move.l  IL_DAMAGE(a2),a0
        move.l  d0,IL_DAMAGE(a2)
        clr.l   WD_USERDATA(a3)
        jsr     LVO_DISPOSEREGION(a6)
        bra.s   .uc_end
.uc_rep:
        bclr    #ILB_REFRESH,IL_FLAGS+1(a2)
        moveq   #1,d2
.uc_end:
        move.l  WBS_IBASE(a5),a6
        move.l  IB_LAYERSBASE(a6),a6
        move.l  a2,a0
        move.l  d2,d0
        jsr     LVO_ENDUPDATE(a6)
        move.l  WBS_GFXBASE(a5),a6
        exg     a2,a5
        jsr     LVO_UNLOCKLAYERROM(a6)
        exg     a2,a5
        movem.l (sp)+,d2/a2-a4
.uc_r:
        rts

; wb_repair(d7.w = window, a5): REFRESHWINDOW, only if the layer is damaged (spec §6): gauge of a disk
; (outside the update), then icons in damage AND contents; damage cleared. The frame is repaired by intuition.
wb_repair:
        movem.l d6/a2-a4,-(sp)
        bsr     wb_window
        beq.s   .rp_ret
        move.l  WD_RPORT(a3),a0
        move.l  (a0),a2
        btst    #ILB_REFRESH,IL_FLAGS+1(a2)
        beq.s   .rp_ret
        tst.w   d7
        beq.s   .rp_desk
        bsr     wb_gauge
        moveq   #0,d0
        bsr     wb_updopen
        bsr     wb_drawicons
        bra.s   .rp_close
.rp_desk:
        moveq   #0,d0
        bsr     wb_updopen
        bsr     wb_drawwin
.rp_close:
        bsr     wb_updclose
.rp_ret:
        movem.l (sp)+,d6/a2-a4
        rts

; wb_drawicon(a2 = DiskObject, a3 = window, a4 = name, d4/d5 = position, d6.w = number, d7.w = window, a5): image of
; the icon, name centred below it (pen 2, JAM1), inverted if selected. Preserves d2-d7/a2-a4.
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
        lsl.w   #2,d1                ; half-width of the text
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

; wb_invert(d7.w = window, d1.w = icon, a5): shows the selection state of the icon, just changed in WBS_SELW/WBS_SELI
; by the caller. Highlighting from do_Gadget.Flags (RKM, Workbench icons): GADGHIMAGE with a SelectRender -> the
; alternate image (open drawer) or the normal one, drawn over the cleared rectangle; otherwise the rectangle is
; inverted (COMPLEMENT: a toggle). Preserves d2-d7/a2-a5.
wb_invert:
        movem.l d2-d4/a2-a4/a6,-(sp)
        move.w  d1,d4                ; d4 = icon
        moveq   #1,d0
        bsr     wb_updopen
        move.w  d4,d1
        bsr     wb_iconrect
        beq     .iv_end
        movem.w d0-d3,-(sp)
        bsr     wb_window
        move.w  DO_GADGET+GG_FLAGS(a2),d0
        and.w   #3,d0
        cmp.w   #GADGHIMAGE,d0
        bne.s   .iv_comp
        tst.l   DO_GADGET+GG_SELECTRENDER(a2)
        beq.s   .iv_comp
        move.l  WBS_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #0,d0
        jsr     LVO_SETAPEN(a6)
        movem.w (sp),d0-d3
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        move.l  DO_GADGET+GG_GADGETRENDER(a2),a1
        cmp.w   WBS_SELW(a5),d7
        bne.s   .iv_img
        cmp.w   WBS_SELI(a5),d4
        bne.s   .iv_img
        move.l  DO_GADGET+GG_SELECTRENDER(a2),a1
.iv_img:
        movem.w (sp)+,d0-d3
        move.l  WBS_IBASE(a5),a6
        move.l  WD_RPORT(a3),a0
        jsr     LVO_DRAWIMAGE(a6)
        bra.s   .iv_end
.iv_comp:
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
.iv_end:
        bsr     wb_updclose
        movem.l (sp)+,d2-d4/a2-a4/a6
        rts

; wb_click(d7.w = window, d4/d5 = mouse in the window, d6/a0 = timestamp, a5): on an icon -> selection (the
; previous one is made normal again) and start of a drag; on the already selected icon within the double-click delay
; -> open; elsewhere -> deselection. Preserves d7/a5.
wb_click:
        move.l  a0,-(sp)             ; micros
        clr.l   -(sp)                ; (sp) = icon tested
        bsr     wb_window            ; a3 = window
.ck_find:
        move.l  (sp),d1
        bsr     wb_iconrect
        beq     .ck_none
        tst.w   d7
        beq.s   .ck_test
        movem.l d0-d3,-(sp)
        bsr     wb_content           ; drawer: only the part of an icon inside the contents is clickable
        cmp.w   d0,d4
        blt.s   .ck_out
        cmp.w   d2,d4
        bgt.s   .ck_out
        cmp.w   d1,d5
        blt.s   .ck_out
        cmp.w   d3,d5
        bgt.s   .ck_out
        movem.l (sp)+,d0-d3
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
        move.l  d1,-(sp)             ; same icon: double-click?
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
        bsr     wb_dragstart         ; the icon can be dragged as long as the button stays pressed
.ck_stamp:
        move.l  d6,WBS_LSEC(a5)
        move.l  (sp)+,WBS_LMIC(a5)
        rts
.ck_out:
        movem.l (sp)+,d0-d3
        bra.s   .ck_nx
.ck_none:
        addq.l  #8,sp
        bra     wb_deselect

; wb_redraw1(d7.w = window, a5): full redisplay (spec wb-icon-clipping-v34 §5): gauge of a disk, then in
; an update limited to the contents, contents cleared in pen 0 and icons redrawn. Preserves d7/a5.
wb_redraw1:
        movem.l d2-d6/a2-a4/a6,-(sp)
        bsr     wb_window
        beq.s   .r1_ret
        tst.w   d7
        bne.s   .r1_dr
        suba.l  a4,a4                ; desktop: no gauge
        bra.s   .r1_open
.r1_dr:
        bsr     wb_gauge
.r1_open:
        moveq   #1,d0
        bsr     wb_updopen
        move.l  WBS_GFXBASE(a5),a6
        move.l  WD_RPORT(a3),a1
        moveq   #0,d0
        jsr     LVO_SETAPEN(a6)
        bsr     wb_content
        move.l  WD_RPORT(a3),a1
        jsr     LVO_RECTFILL(a6)
        tst.w   d7
        bne.s   .r1_icons
        bsr     wb_drawwin
        bra.s   .r1_close
.r1_icons:
        bsr     wb_drawicons
.r1_close:
        bsr     wb_updclose
.r1_ret:
        movem.l (sp)+,d2-d6/a2-a4/a6
        rts

; wb_dragstart(d7.w = window, d1.w = icon, d4/d5 = mouse, a5): drag armed; the window receives the movements
; (ReportMouse). Preserves d2-d7/a2-a5.
wb_dragstart:
        move.w  d7,WBS_DRAGW(a5)
        move.w  d1,WBS_DRAGI(a5)
        move.w  d4,WBS_DSX(a5)
        move.w  d5,WBS_DSY(a5)
        clr.b   WBS_GON(a5)
        moveq   #1,d0
; wb_report(d0 = flag, WBS_DRAGW, a5): ReportMouse of the drag window. Preserves d2-d7/a2-a5.
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

; wb_dragmove(d7.w = window, d4/d5 = mouse, a5): the ghost frame (size of the icon) follows the movement since
; the click, drawn in COMPLEMENT in the screen's RastPort. Preserves d2-d7/a2-a5.
wb_dragmove:
        cmp.w   WBS_DRAGW(a5),d7
        bne.s   .gm_r
        movem.l d2-d3/a2-a4,-(sp)
        tst.b   WBS_GON(a5)
        beq.s   .gm_new
        bsr     wb_ghost             ; erase the old frame
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
        bsr     wb_ghost             ; draw the new one
.gm_out:
        movem.l (sp)+,d2-d3/a2-a4
.gm_r:
        rts

; wb_ghost(a5): toggles the ghost frame (four one-pixel lines in COMPLEMENT, corners not doubled); WBS_GON
; tells whether it is displayed. Preserves d2-d7/a2-a5.
wb_ghost:
        movem.l d2-d5/a6,-(sp)
        not.b   WBS_GON(a5)
        move.l  WBS_GFXBASE(a5),a6
        move.l  WBS_GRP(a5),a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        move.w  WBS_GX(a5),d4
        move.w  WBS_GY(a5),d5
        move.w  d4,d0                ; top
        move.w  d5,d1
        move.w  d4,d2
        add.w   WBS_GW(a5),d2
        subq.w  #1,d2
        move.w  d5,d3
        bsr.s   .gh_fill
        move.w  d5,d1                ; bottom
        add.w   WBS_GH(a5),d1
        subq.w  #1,d1
        move.w  d1,d3
        bsr.s   .gh_fill
        move.w  WBS_GH(a5),d3
        subq.w  #3,d3
        bmi.s   .gh_end              ; no sides for a height < 3
        move.w  d5,d1                ; left
        addq.w  #1,d1
        add.w   d1,d3
        move.w  d4,d0
        move.w  d4,d2
        bsr.s   .gh_fill
        move.w  d4,d0                ; right
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
.gh_fill:                            ; RectFill(d0..d3); preserves d0-d5
        movem.l d0-d3,-(sp)
        move.l  WBS_GRP(a5),a1
        jsr     LVO_RECTFILL(a6)
        movem.l (sp)+,d0-d3
        rts

; wb_dragend(d7.w = window, d4/d5 = mouse at release, a5): end of the drag (frame erased, no more movements).
; Released in the original window, at least 3 pixels from the click: the icon takes its new position there
; (DiskObject updated in memory, not saved) and the window is redrawn. Preserves d7/a5.
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
        sub.w   WBS_DSX(a5),d2       ; d2/d3 = displacement
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
        blt     .de_out              ; simple click
        bsr     wb_window
        beq.s   .de_out
        tst.w   d4                   ; released outside the original window: nothing
        bmi.s   .de_out
        tst.w   d5
        bmi.s   .de_out
        cmp.w   WD_WIDTH(a3),d4
        bge.s   .de_out
        cmp.w   WD_HEIGHT(a3),d5
        bge.s   .de_out
        move.w  WBS_DRAGI(a5),d1
        movem.w d2-d3,-(sp)
        bsr     wb_iconrect          ; a2 = DiskObject, d0/d1 = current position in the window
        movem.w (sp)+,d2-d3
        beq.s   .de_out
        add.w   d2,d0
        add.w   d3,d1
        tst.w   d7
        beq.s   .de_desk
        movem.w d0-d1,-(sp)          ; drawer: DO_Current* is relative to the icon space (wb_origin)
        bsr     wb_origin
        move.w  d0,d2
        move.w  d1,d3
        movem.w (sp)+,d0-d1
        sub.w   d2,d0
        sub.w   d3,d1
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
        tst.w   d7
        bne.s   .de_draw
        movem.w d0-d1,-(sp)          ; desktop: new position of the volume
        move.w  WBS_DRAGI(a5),d1
        bsr     wb_volent
        movem.w (sp)+,d0-d1
        move.w  d0,VE_X(a0)
        move.w  d1,VE_Y(a0)
.de_draw:
        bsr     wb_redraw1
.de_out:
        movem.l (sp)+,d2-d6/a2-a4
.de_ret:
        rts

; wb_deselect(a5): no icon selected any more (made normal again if its window exists). Preserves d2-d7/a2-a5.
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

; wb_openicon(d7.w = window, d1.w = icon, a5): desktop -> root drawer; drawer / trashcan -> its window; tool ->
; launched; project -> its default tool with the project as argument. Preserves d6/d7/a5.
wb_openicon:
        movem.l d6-d7/a3-a4,-(sp)
        lea     -WB_PATHMAX(sp),sp
        tst.w   d7
        bne.s   .oi_dr
        bsr     wb_volent            ; disk: its root "<volume>:", title = name of the volume
        move.l  VE_DOBJ(a0),a2
        lea     VE_NAME(a0),a1
        lea     VE_PATH(a0),a0
        bsr     wb_opendrawer
        bra     .oi_ret
.oi_dr:
        move.w  d1,d6
        bsr     wb_iconrect
        beq     .oi_ret
        bsr     wb_window
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a3 ; a3 = name of the icon
        lea     DR_PATH(a4),a0
        move.l  sp,a1
        move.l  a3,a4
        bsr     wb_join              ; (sp) = full path
        move.b  DO_TYPE(a2),d0
        cmp.b   #WBDRAWER,d0
        beq.s   .oi_drawer
        cmp.b   #WBGARBAGE,d0
        beq.s   .oi_drawer
        cmp.b   #WBTOOL,d0
        beq.s   .oi_tool
        cmp.b   #WBPROJECT,d0
        bne.s   .oi_ret
        move.l  DO_DEFAULTTOOL(a2),d0 ; project: default tool, the project as argument
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

; wb_join(a0 = directory, a4 = name, a1 = destination of WB_PATHMAX bytes): "dir:name" or "dir/name", truncated.
; Preserves a2-a6.
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

; wb_opendrawer(a0 = path, a1 = title, a2 = DiskObject (its DrawerData gives the geometry), a5): already open ->
; brought to the front; otherwise free record, window (drag, depth, close, size; IDCMP CLOSEWINDOW |
; REFRESHWINDOW | MOUSEBUTTONS | MENUPICK), menus, icons read then drawn. Preserves d7/a5.
wb_opendrawer:
        movem.l d2-d7/a2-a4,-(sp)
        move.l  a0,d4                ; d4 = path, d5 = title
        move.l  a1,d5
        moveq   #1,d7                ; already open?
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
        moveq   #1,d7                ; free record
.od_free:
        bsr     wb_window
        beq.s   .od_slot
        addq.w  #1,d7
        cmp.w   #WB_MAXDRAWERS,d7
        bls.s   .od_free
        bra     .od_ret
.od_slot:
        move.l  d4,a0                ; path and title in the record
        lea     DR_PATH(a4),a1
        moveq   #WB_PATHMAX-2,d0
        bsr     wb_strcpy
        move.l  d5,a0
        lea     DR_TITLE(a4),a1
        moveq   #WBS_NAMEMAX-2,d0
        bsr     wb_strcpy
        clr.l   DR_SX(a4)            ; scroll position (dd_CurrentX/Y of the .info), disk window?
        clr.b   DR_DISK(a4)
        clr.l   DR_NICON(a4)
        lea     DR_PATH(a4),a0
        bsr     wb_strlen
        cmp.b   #':',-1(a0,d0.w)
        seq     DR_DISK(a4)
        bsr     wb_arrowsinit
        bsr     wb_mkgads
        move.l  a0,-(sp)             ; first scroll gadget
        lea     -NW_SIZEOF(sp),sp
        bsr     wb_nwclear
        move.l  #$000A0014,NW_LEFTEDGE(a0)   ; default: 10,20 400x120
        move.l  #$01900078,NW_WIDTH(a0)
        move.l  DO_DRAWERDATA(a2),d0
        beq.s   .od_geo
        move.l  d0,a1
        move.l  (a1),NW_LEFTEDGE(a0)         ; dd_NewWindow : LeftEdge, TopEdge, Width, Height
        move.l  4(a1),NW_WIDTH(a0)
        move.w  DD_CURRENTX+2(a1),DR_SX(a4)
        move.w  DD_CURRENTY+2(a1),DR_SY(a4)
.od_geo:
        move.l  #CLOSEWINDOW|REFRESHWINDOW|MOUSEBUTTONS|MOUSEMOVE|MENUPICK|GADGETDOWN|GADGETUP|NEWSIZE,NW_IDCMPFLAGS(a0)
        move.l  #WINDOWDRAG|WINDOWDEPTH|WINDOWCLOSE|WINDOWSIZING|SIZEBRIGHT|SIZEBBOTTOM|REPORTMOUSE,NW_FLAGS(a0)
        move.l  NW_SIZEOF(sp),NW_FIRSTGADGET(a0)
        lea     DR_TITLE(a4),a1
        move.l  a1,NW_TITLE(a0)
        move.l  #(90<<16)|40,NW_MINWIDTH(a0)
        move.l  #(640<<16)|256,NW_MAXWIDTH(a0)
        move.l  WBS_IBASE(a5),a6
        jsr     LVO_OPENWINDOW(a6)
        lea     NW_SIZEOF+4(sp),sp
        move.l  d0,DR_WIN(a4)
        beq.s   .od_ret
        move.w  d7,DR_ID(a4)
        move.l  d0,a0
        bsr     wb_setmenus
        bsr     wb_titles
        bsr     wb_gaugeinfo
        move.l  DR_WIN(a4),a3
        bsr     wb_gauge
        bsr     wb_loadicons
        bsr     wb_bars
.od_ret:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; wb_closedrawer(d7.w = drawer, a5): closes its window, returns its icons, frees the record; the selection that was
; there disappears. Preserves d7/a5.
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

; wb_loadicons(a4 = record, a5): walks the drawer's directory (Examine / ExNext); each "name.info" (except
; Disk.info) gives an icon (GetDiskObject of the path without ".info") and its name, WB_MAXICONS at most.
; Preserves d2-d7/a2-a6.
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
        lea     -WB_PATHMAX(sp),sp   ; path of the icon
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
.li_exam:                            ; "Error while examining <drawer>: n"
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
        jsr     DOS_LVO_IOERR(a6)    ; normal end of the directory: no message
        cmp.l   #ERROR_NO_MORE_ENTRIES,d0
        beq     .li_unlock
        moveq   #0,d0                ; "Error while examining directory: n"
        suba.l  a0,a0
        bsr     wb_error
        bra     .li_unlock
.li_entry:
        move.l  d6,a0
        lea     FIB_FILENAME(a0),a2  ; a2 = name
        move.l  a2,a0
        bsr     wb_strlen
        move.w  d0,d3                ; d3 = length
        cmp.w   #5,d3
        bls.s   .li_next             ; too short for "x.info"
        cmp.w   #WBS_NAMEMAX+4,d3
        bhs.s   .li_next
        lea     -5(a2,d3.w),a0       ; ".info" suffix (case-insensitive)
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
        subq.w  #5,d3                ; d3 = length of the name without ".info"
        cmp.w   #4,d3                ; "Disk": the icon of the disk itself
        bne.s   .li_keep
        lea     wb_diskicon(pc),a0
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
        move.l  DR_NICON(a4),d4      ; name -> DR_NAMES[n]
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
        sub.w   d3,a1                ; a1 = copied name
        move.l  a1,a4
        lea     4(sp),a1             ; path "directory/name"
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
        movem.l d6-d7,-(sp)          ; drawn right away (reading the floppy is slow)
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

; wb_launch(a0 = path of the tool, a1 = path of the project | 0, a2 = DiskObject of the tool (stack) if a1 = 0, a5):
; LoadSeg of the tool, WBStartup message (argument 0 = the tool, 1 = the project: lock of the directory + name),
; CreateProc then PutMsg; the message comes back to the "Workbench" port when the tool ends (wb_toolreturn).
; Failure (tool not found, memory): nothing. Preserves d7/a5.
WBSM_SIZE       EQU SM_SIZE+2*WA_SIZE+2*WBS_NAMEMAX ; message + 2 arguments + their names
wb_launch:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.l  a0,a3                ; a3 = tool
        move.l  a1,a4                ; a4 = project | 0
        move.l  #WB_TOOLSTACK,d6     ; d6 = stack
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
        move.l  a3,a0                ; "Error while opening <tool>: n": name of a tool's icon (its
        move.l  a4,d0                ; directory is the current directory), a project's Default Tool as is
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
        move.l  a3,a0                ; argument 0: the tool
        moveq   #0,d2
        bsr     wb_arg
        move.l  a4,d0
        beq.s   .la_proc
        move.l  a4,a0                ; argument 1: the project
        moveq   #1,d2
        bsr     wb_arg
.la_proc:
        move.l  SM_ARGLIST(a2),a0
        move.l  WA_NAME(a0),d1       ; process name = name of the tool
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

; wb_arg(a2 = WBStartup, d2 = argument number, a0 = full path, a5): wa_Lock = lock of the directory (part before
; the last "/" or ":" included), wa_Name = name (copied into the message); sm_NumArgs = d2 + 1. Preserves d2-d7/a2-a6.
wb_arg:
        movem.l d2-d4/a2-a4/a6,-(sp)
        move.l  a0,a3
        move.l  a0,a1                ; a1 = start of the name (after the last separator)
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
        bsr     wb_strcpy            ; name
        move.l  WA_NAME(a4),d4       ; directory: temporary copy of the path cut before the name
        lea     -WB_PATHMAX(sp),sp
        move.l  a3,a0
        move.l  sp,a1
        moveq   #WB_PATHMAX-2,d0
        bsr     wb_strcpy
        move.l  a3,a0                ; length of the directory = start of the name - start of the path
        bsr     wb_strlen
        move.l  d4,a0
        move.w  d0,d3
        bsr     wb_strlen
        sub.w   d0,d3                ; d3 = length with the separator
        beq.s   .ag_lock
        cmp.b   #'/',-1(sp,d3.w)
        bne.s   .ag_cut
        subq.w  #1,d3                ; "dir/name" -> "dir"
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

; wb_toolreturn(a1 = returned WBStartup, a5): the tool has finished: segment unloaded, locks returned, message freed.
; Preserves d2-d7/a2-a5.
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
; wb_freestartup(a1 = WBStartup, a5): returns the locks of its arguments and frees the message.
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

; wb_menupick(d3.w = code, d7.w = window, a5): Workbench/Open -> opens the selected icon; Workbench/Close ->
; closes this drawer; Special/Redraw -> clears and redraws all windows. Preserves d7/a5.
wb_menupick:
        bsr     wb_restore           ; any menu choice restores the memory title (spec §6.2)
        cmp.w   #MENUNULL,d3
        beq     .mp_ret
        move.w  d3,d0
        and.w   #$1F,d0              ; menu
        move.w  d3,d1
        lsr.w   #5,d1
        and.w   #$3F,d1              ; item
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

; wb_timeropen(a5): timer.device (VBLANK unit) on the state's timerequest, reply on the public port; then first
; tick. Without a timer: no tick (the screen title stays that of the screen).
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

; wb_tick(a5): 5 s tick (spec workbench-task-v34 §3.4). Volumes scanned (wb_vscan), then AvailMem(0); if the value
; has changed, the screen title is reformatted ("Workbench release 1.2.  %ld free memory", which the SetWindowTitles
; patched by LoadWB 1.3.3 touches up) and applied to the windows; then the request restarts for 5 s. Preserves
; d2-d7/a2-a6.
wb_tick:
        movem.l a2-a3/a6,-(sp)
        bsr     wb_vscan
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

; wb_memtitle(a5): title part of the tick. Message displayed: nothing. Otherwise AvailMem(0); value changed: memory
; title reformatted, then applied to the windows except during a Rename (title locked). Preserves d2-d7/a2-a6.
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

; wb_restore(a5): a message was displayed (and the title is not locked): the memory title comes back on the
; windows. Called at the start of every MENUPICK and on SELECTDOWN. Preserves d2-d7/a2-a6.
wb_restore:
        btst    #1,WBS_FLAGS(a5)
        bne.s   .rs_ret
        bclr    #2,WBS_FLAGS(a5)
        bne     wb_titles
.rs_ret:
        rts

; wb_message(a0 = format | WBS_MSGBUF, a1 = long arguments, a5): a message is already displayed: nothing (the first
; one stays). Otherwise it becomes the screen title of all the Workbench windows; a new format is preceded by a
; DisplayBeep then formatted into WBS_MSGBUF, WBS_MSGBUF itself is redisplayed as is. The memory title comes back on
; the next click or menu choice. Preserves d2-d7/a2-a6.
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

; wb_error(d0.w = action, a0 = name | 0, a5): "Error while <action>: <IoErr>" in the screen title (spec §6.5, §6.9);
; IoErr is read before any other dos call. The action comes from wb_errtab (%s = name). Like any message: the first
; one displayed stays until the next click or menu. Preserves d2-d7/a2-a6.
WE_BUF          EQU 0                ; formatted action (WBS_TBUFMAX)
WE_ARGS         EQU WE_BUF+WBS_TBUFMAX ; "Error while %s: %ld": action, error
WE_NAME         EQU WE_ARGS+8        ; %s argument of the action
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
        add.w   0(a0,d2.w),a0        ; a0 = text of the action
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

; wb_base(a0 = path) -> a0 = its last component (after the last ":" or "/"). Clobbers d0/a1.
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

; wb_version(a5): Special/Version (spec §6.3). Kickstart: version and revision from the ROM header (words at +$0C and
; +$0E, the ROM starting at $1000000 - its size, stored at $FFFFEC). Workbench: lib_Version and lib_Revision of
; version.library (opened with version 0, loaded from LIBS: if needed), -1 and -1 without it.
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

; wb_lasterr(a5): Special/Last Error (spec §6.5): the last message, redisplayed without a beep; none yet: beep and
; empty title.
wb_lasterr:
        lea     WBS_MSGBUF(a5),a0
        tst.b   WBS_MSGOK(a5)
        bne     wb_message
        lea     wb_empty(pc),a0
        bra     wb_message

; wb_titles(a5): the memory title (WBS_TBUF) on all the Workbench windows; still empty: nothing. Preserves
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
; wb_apply(a2 = screen title, a5): SetWindowTitles(window, -1, a2) on the backdrop window and each open drawer.
; Preserves d2-d7/a2-a6.
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

; wb_cleanup(d7.w = window, a5): Special/Clean Up (probed on the real 1.3). The icons of the drawer, sorted by current
; position (X then Y; without a position: last), are arranged in columns from top to bottom in cells
; CU_CELL wide, each centred in its cell; vertical gap CU_GAPY below each icon (name included). Next
; column when the icon would exceed the interior height the window would have under 1.3 (title + bottom
; scroll bar = CU_FRAMEH lines). Positions in memory only (Snapshot writes them). Desktop: nothing.
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
        lea     -WB_MAXICONS(sp),sp  ; order: icon numbers
        moveq   #0,d0
.cu_init:
        move.b  d0,0(sp,d0.w)
        addq.w  #1,d0
        cmp.w   d6,d0
        blt.s   .cu_init
        moveq   #1,d2                ; insertion sort (stable)
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
        bsr     cu_less              ; d0 = 1 if icon d3 comes before icon d5
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
        sub.w   #CU_FRAMEH,d5        ; d5 = usable height
        moveq   #0,d2                ; d2 = left of the column
        moveq   #0,d3                ; d3 = current y
        moveq   #CU_CELL,d4          ; d4 = width of the column (a wider icon widens it)
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
        add.w   d4,d2                ; next column
        moveq   #0,d3
        moveq   #CU_CELL,d4
.cu_fit:
        move.w  DO_GADGET+GG_WIDTH(a2),d0
        cmp.w   d4,d0
        ble.s   .cu_wok
        move.w  d0,d4
.cu_wok:
        neg.w   d0
        add.w   #CU_CELL,d0          ; margin = (cell - width) / 2, zero if the icon is wider
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

; cu_less(d0.b = icon a, d1.b = icon b, a4 = record) -> d0 = 1 if b comes before a (X then Y; without a position =
; last), 0 otherwise. Preserves d2-d7/a1-a6.
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
; cu_key(d0.b = icon, a4) -> d0/d1 = sort X/Y. Clobbers a0.
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

; wb_snapshot(a5): Special/Snapshot. The position of the selected icon is put into its DiskObject then written
; into its ".info" (PutDiskObject); disk or drawer whose window is open: the geometry of that window also goes
; into dd_NewWindow (reopened at the same place). dos requesters suppressed during the write (pr_WindowPtr = -1).
wb_snapshot:
        movem.l d2-d7/a2-a4/a6,-(sp)
        lea     -WB_PATHMAX(sp),sp
        move.w  WBS_SELW(a5),d7
        bmi     .ss_ret
        move.w  WBS_SELI(a5),d1
        bsr     wb_iconrect          ; a2 = DiskObject, d0/d1 = corner in the window
        beq     .ss_ret
        tst.w   d7
        bne.s   .ss_dr
        movem.w d0-d1,-(sp)          ; disk: "<volume>:Disk", its window is the root "<volume>:"
        move.w  WBS_SELI(a5),d1
        bsr     wb_volent
        lea     VE_PATH(a0),a3
        move.l  a3,a0
        lea     4(sp),a1
        moveq   #WB_PATHMAX-2,d0
        bsr     wb_strcpy
        lea     4(sp),a0
        bsr     wb_strlen
        lea     4(sp,d0.w),a1
        lea     wb_diskicon(pc),a0
        moveq   #5,d0
        bsr     wb_strcpy
        movem.w (sp)+,d0-d1
        bra.s   .ss_pos
.ss_dr:
        movem.w d0-d1,-(sp)
        bsr     wb_window            ; a3 = window, a4 = record (d0 clobbered)
        movem.w (sp)+,d0-d1
        movem.w d0-d1,-(sp)          ; DO_Current* is relative to the drawer's icon space (wb_origin)
        bsr     wb_origin
        move.w  d0,d2
        move.w  d1,d3
        movem.w (sp)+,d0-d1
        sub.w   d2,d0
        sub.w   d3,d1
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
        move.l  sp,a3                ; possible window: the one of this path
.ss_pos:
        ext.l   d0
        ext.l   d1
        move.l  d0,DO_CURRENTX(a2)
        move.l  d1,DO_CURRENTY(a2)
        move.l  DO_DRAWERDATA(a2),d5 ; d5 = dd_NewWindow | 0
        beq.s   .ss_put
        move.l  a3,d6                ; d6 = path whose window is looked for
        moveq   #1,d7
.ss_find:
        bsr     wb_window            ; a3 = window, a4 = record
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
        moveq   #8,d0                ; "Error while writing <name>: n" ("Disk" for the disk)
        move.l  sp,a0
        bsr     wb_base
        bsr     wb_error
.ss_ret:
        lea     WB_PATHMAX(sp),sp
        movem.l (sp)+,d2-d7/a2-a4/a6
        rts

; wb_info(a5): Workbench/Info (spec workbench-task-v34 §7). The Info window is that of libs:info.library (disk),
; called synchronously: LVO -30, A0 = A6 = its base, A1 = a WBObject. That object is built by icon.library
; (GetWBObject, in the icon's directory; "Disk" for the disk), completed with the name (recorded in its FreeList)
; and the lock of the containing directory (+$A4; disk: also DrawerData+$1BA). info.library changes pr_CurrentDir
; without restoring it: the Workbench's current directory is restored afterwards. Without info.library:
; "Info not available". On return, the drawer is re-read (SAVE may have modified the icon) and the object freed
; by FreeWBObject.
wb_info:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.w  WBS_SELW(a5),d7
        bmi     .if_ret
        bne.s   .if_dr
        move.w  WBS_SELI(a5),d1      ; disk: its root, icon "Disk"
        bsr     wb_volent
        lea     VE_PATH(a0),a0
        lea     wb_diskicon(pc),a3
        bra.s   .if_lock
.if_dr:
        bsr     wb_window            ; a4 = drawer record
        beq     .if_ret
        move.w  WBS_SELI(a5),d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a3 ; a3 = name of the icon
        lea     DR_PATH(a4),a0
.if_lock:
        move.l  a0,d1
        moveq   #SHARED_LOCK,d2
        move.l  WBS_DOSBASE(a5),a6
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d6                ; d6 = lock of the containing directory
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
        move.l  d0,d4                ; d4 = current directory of the Workbench
        move.l  a3,a0
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_GETWBOBJECT(a6)
        move.l  d0,a2                ; a2 = WBObject
        tst.l   d0
        beq     .if_close
        move.l  a3,a0                ; name: copy recorded in the FreeList (freed with the object)
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
        move.l  WBO_NAME(a2),a1      ; not recorded: freed right away, no Info
        move.l  d3,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        bra.s   .if_free
.if_named:
        move.l  d6,WBO_LOCK(a2)
        tst.w   d7
        bne.s   .if_call
        move.l  WBO_DRAWER(a2),d0    ; disk: lock of the root also in its DrawerData
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

; wb_duplicate(a5): Workbench/Duplicate (spec workbench-task-v34 §7.9). Disk: its default tool (DiskCopy)
; is launched with the disk as argument, "This disk cannot be copied" without a tool. Other icon: new name by
; BumpRevision ("copy of ...", 25 characters at most); the original's icon, offset by +30/+15, is written under
; that name by PutWBObject BEFORE the data; it is re-read (failure: "Cannot read info file <name>", nothing is
; copied) and added to the drawer without re-reading it, the original staying selected; then the object is copied
; (wb_cptree).
DU_NEW          EQU 0                ; new name
DU_SRC          EQU DU_NEW+WBS_NAMEMAX   ; path of the original
DU_DST          EQU DU_SRC+WB_PATHMAX    ; path of the copy
DU_ARG          EQU DU_DST+WB_PATHMAX    ; argument of the "Cannot read info file %s" message
DU_SIZE         EQU DU_ARG+4
DU_NAMEMAX      EQU 25
wb_duplicate:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.w  WBS_SELW(a5),d7
        bmi     .du_ret
        bne.s   .du_obj
        move.w  WBS_SELI(a5),d1      ; disk
        bsr     wb_volent
        move.l  VE_DOBJ(a0),a2
        lea     VE_PATH(a0),a1
        move.l  DO_DEFAULTTOOL(a2),d0
        bne.s   .du_tool
        lea     wb_nodiskcopy(pc),a0
        suba.l  a1,a1
        bsr     wb_message
        bra     .du_ret
.du_tool:
        move.l  d0,a0
        bsr     wb_launch
        bra     .du_ret
.du_obj:
        move.w  WBS_SELI(a5),d6
        bsr     wb_window
        beq     .du_ret
        lea     -DU_SIZE(sp),sp
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a2 ; a2 = name of the original
        lea     DR_PATH(a4),a0
        move.l  WBS_DOSBASE(a5),a6
        move.l  a0,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d5                ; d5 = lock of the drawer
        beq     .du_free
        move.l  d5,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        move.l  d0,d4                ; d4 = old current directory
        move.l  a2,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d3                ; d3 = lock of the original
        bne.s   .du_bump
        moveq   #1,d0                ; "accessing <name>"
        move.l  a2,a0
        bsr     wb_error
        bra     .du_cd
.du_bump:
        lea     DU_NEW(sp),a0
        move.l  a2,a1
        move.l  WBS_ICONBASE(a5),a6
        jsr     ICON_LVO_BUMPREVISION(a6)
        clr.b   DU_NEW+DU_NAMEMAX(sp)
        move.l  a2,a0                ; icon of the copy: that of the original, offset, written under the new name
        jsr     ICON_LVO_GETWBOBJECT(a6)
        tst.l   d0
        beq     .du_unlock
        move.l  d0,a3                ; a3 = WBObject of the original
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
        move.l  a4,-(sp)             ; paths of the original and of the copy
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
        lea     DU_DST(sp),a0        ; re-reading of the copy's icon
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
        move.l  d0,a3                ; a3 = DiskObject of the copy
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
; .du_place(a3 = DiskObject, a4 = drawer, d7 = its number, name at 4+DU_NEW(sp)): an icon of the same name is replaced
; (the drawer is then redrawn), otherwise the copy is added and drawn. No more room: icon freed.
.du_place:
        movem.l d2/d6/a2,-(sp)
        moveq   #0,d6                ; d6 = index
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

; wb_discard(a5): Workbench/Discard. The selected icon of a drawer (not the disk): confirmation through
; AutoRequest, then the object (a drawer with all its contents) and its ".info" are deleted and the drawer is re-read.
DS_PATH         EQU 0                ; path of the object (WB_PATHMAX)
DS_QUEST        EQU DS_PATH+WB_PATHMAX   ; "OK to discard <name>?"
DS_IT           EQU DS_QUEST+WBS_NAMEMAX+16  ; 5 IntuiTexts: 3 lines, "Discard", "Cancel"
DS_SIZE         EQU DS_IT+5*IT_SIZEOF
wb_discard:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.w  WBS_SELW(a5),d7
        ble     .dc_ret              ; no selection (-1) or the disk icon (0)
        move.w  WBS_SELI(a5),d6
        bsr     wb_window
        beq     .dc_ret
        lea     -DS_SIZE(sp),sp
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a2 ; a2 = name of the icon
        move.l  a4,-(sp)
        lea     DR_PATH(a4),a0
        lea     4+DS_PATH(sp),a1
        move.l  a2,a4
        bsr     wb_join
        move.l  (sp)+,a4
        lea     DS_QUEST(sp),a1      ; question: "OK to discard <name>?"
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
        lea     DS_IT(sp),a0         ; body: three chained lines
        lea     wbs_dsw1(pc),a1
        moveq   #4,d1
        bsr     wb_itext
        lea     wbs_dsw2(pc),a1
        moveq   #14,d1
        bsr     wb_itext
        lea     DS_QUEST(sp),a1
        moveq   #24,d1
        bsr     wb_itext
        clr.l   IT_NEXTTEXT-IT_SIZEOF(a0)   ; end of the body
        lea     wbs_discard(pc),a1   ; gadgets
        moveq   #3,d1
        bsr     wb_itext
        clr.l   IT_NEXTTEXT-IT_SIZEOF(a0)
        lea     wbs_cancel(pc),a1
        moveq   #3,d1
        bsr     wb_itext
        clr.l   IT_NEXTTEXT-IT_SIZEOF(a0)
        move.l  a3,a0                ; AutoRequest(drawer window, body, Discard, Cancel, 0, 0, 320, 80)
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
        lea     DS_PATH(sp),a0       ; then "<path>.info"
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
        beq.s   .dc_reload           ; no .info: nothing to report
        moveq   #6,d0                ; "Error while removing <name>.info: n"
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

; wb_rename(a5): Workbench/Rename. The selected icon of a drawer (not the disk): "Rename" window with a
; prefilled and activated text gadget; Return renames the object then its ".info", and the drawer is re-read; the close
; box cancels. Preserves d7/a5.
RN_OLD          EQU 0                ; old path (WB_PATHMAX)
RN_NEW          EQU RN_OLD+WB_PATHMAX
RN_BUF          EQU RN_NEW+WB_PATHMAX    ; text of the gadget (OFS name: 30 characters)
RN_UNDO         EQU RN_BUF+32
RN_SI           EQU RN_UNDO+32       ; StringInfo
RN_GAD          EQU RN_SI+36         ; Gadget
RN_BRD          EQU RN_GAD+GG_SIZEOF ; Border then its 5 points
RN_SIZE         EQU RN_BRD+16+20
RN_MAXCHARS     EQU 31
wb_rename:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.w  WBS_SELW(a5),d7
        ble     .rn_ret              ; no selection (-1) or the disk icon (0)
        move.w  WBS_SELI(a5),d6
        bsr     wb_window
        beq     .rn_ret
        lea     -RN_SIZE(sp),sp
        move.l  sp,a0                ; all zero
        move.w  #RN_SIZE/2-1,d0
.rn_clr:
        clr.w   (a0)+
        dbra    d0,.rn_clr
        move.w  d6,d0
        mulu    #WBS_NAMEMAX,d0
        lea     DR_NAMES(a4,d0.l),a2 ; a2 = name of the icon
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
        move.w  d0,SI_BUFFERPOS(a0)  ; cursor at the end of the name
        move.w  #RN_MAXCHARS,SI_MAXCHARS(a0)
        lea     RN_GAD(sp),a1
        move.l  #(10<<16)|16,GG_LEFTEDGE(a1)
        move.l  #(280<<16)|9,GG_WIDTH(a1)
        move.w  #RELVERIFY,GG_ACTIVATION(a1)
        move.w  #STRGADGET,GG_GADGETTYPE(a1)
        move.l  a0,GG_SPECIALINFO(a1)
        lea     RN_BRD(sp),a0
        move.l  a0,GG_GADGETRENDER(a1)
        move.l  #$FFFEFFFE,BD_LEFTEDGE(a0)   ; frame 2 pixels around the text
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
        move.l  d0,d5                ; d5 = "Rename" window
        beq     .rn_free
        bset    #1,WBS_FLAGS(a5)     ; title locked: the prompt stands in for the screen title (spec §6.4)
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
        moveq   #0,d4                ; d4 = confirmed
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
        bclr    #1,WBS_FLAGS(a5)     ; end of input: memory title redone right away
        bsr     wb_memtitle
        tst.w   d4
        beq     .rn_free
        tst.b   RN_BUF(sp)           ; empty name: nothing to do
        beq     .rn_free
        lea     RN_BUF(sp),a0        ; ":" and "/" refused in a name (spec §6.9)
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
        jsr     DOS_LVO_IOERR(a6)    ; object missing (only the .info exists): tolerated
        cmp.l   #ERROR_OBJECT_NOT_FOUND,d0
        beq.s   .rn_info
        moveq   #5,d0                ; "Error while moving <old name>: n"
        lea     RN_OLD(sp),a0
        bsr     wb_base
        bsr     wb_error
        bra.s   .rn_free
.rn_info:
        lea     RN_OLD(sp),a0        ; then the ".info" files
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
; rn_info(a0 = path of WB_PATHMAX bytes): ".info" appended if it fits. Clobbers d0/a0/a1.
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

; wb_itext(a0 = IntuiText, a1 = text, d1.w = top) -> a0 = next IntuiText (the NextText set points to it):
; pen 2 on 1, JAM1, 6 pixels from the left. Clobbers d0.
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

; wb_rmtree(a0 = path, a5) -> d0 = true if the object is gone: DeleteFile; a non-empty directory is emptied first
; (each entry deleted recursively, the enumeration restarted from the beginning after each deletion).
; Preserves d2-d7/a2-a6.
wb_rmtree:
        movem.l d2-d3/a2-a4/a6,-(sp)
        move.l  a0,a2                ; a2 = path
        move.l  WBS_DOSBASE(a5),a6
        move.l  a2,d1
        jsr     DOS_LVO_DELETEFILE(a6)
        tst.l   d0
        bne     .rt_ret
        jsr     DOS_LVO_IOERR(a6)
        cmp.l   #ERROR_OBJECT_NOT_FOUND,d0
        beq     .rt_gone             ; already absent: counted as deleted
        cmp.l   #ERROR_DIRECTORY_NOT_EMPTY,d0
        bne     .rt_err
        move.l  ($4).w,a6
        move.l  #FIB_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,d3                ; d3 = FIB
        beq     .rt_fail
        lea     -WB_PATHMAX(sp),sp   ; path of an entry
.rt_entry:
        move.l  WBS_DOSBASE(a5),a6
        move.l  a2,d1
        moveq   #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,a3                ; a3 = lock of the directory
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
        beq.s   .rt_unlock           ; empty: the directory can be deleted
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
        bra.s   .rt_done             ; an entry resists: we stop
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
.rt_err:                             ; "Error while removing <name>: n" (the first message displayed stays)
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

; wb_cptree(a0 = source, a1 = destination, a5) -> d0 = 1 if the object (and all its contents) is copied, 0 otherwise,
; the error message already displayed (spec workbench-task-v34 §6.6). Directory: Lock of the destination, CreateDir
; if missing, then each entry recursively. File: Open source (MODE_OLDFILE) and destination (MODE_NEWFILE), then
; Read / Write in WB_CPBUF chunks up to the size reported by Examine. Preserves d2-d7/a2-a6.
CT_SRC          EQU 0                ; path of a source entry
CT_DST          EQU WB_PATHMAX       ; path of the destination entry
CT_SIZE         EQU 2*WB_PATHMAX
wb_cptree:
        movem.l d2-d7/a2-a4/a6,-(sp)
        move.l  a0,a2                ; a2 = source
        move.l  a1,a3                ; a3 = destination
        moveq   #0,d7                ; d7 = result
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
        move.l  d0,d5                ; d5 = lock of the source
        bne.s   .ct_exam
        moveq   #1,d0                ; "accessing <entry>"
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
        moveq   #7,d0                ; "examining <entry>"
        move.l  a2,a0
        bsr     wb_base
        bsr     wb_error
        bra     .ct_unlock
.ct_kind:
        move.l  d6,a0
        tst.l   FIB_DIRENTRYTYPE(a0)
        bmi     .ct_file
        move.l  a3,d1                ; directory: does the destination exist?
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
        moveq   #1,d0                ; "accessing <destination>"
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
        bra.s   .ct_dout             ; an entry failed: its message is displayed, we stop
.ct_dend:
        jsr     DOS_LVO_IOERR(a6)
        cmp.l   #ERROR_NO_MORE_ENTRIES,d0
        beq.s   .ct_dok
        moveq   #0,d0                ; "examining directory"
        suba.l  a0,a0
        bsr     wb_error
        bra.s   .ct_dout
.ct_dok:
        moveq   #1,d7
.ct_dout:
        lea     CT_SIZE(sp),sp
        bra     .ct_unlock
.ct_file:
        move.l  FIB_SIZE(a0),d4      ; d4 = bytes remaining to copy
        move.l  ($4).w,a6
        move.l  #WB_CPBUF,d0
        moveq   #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a4                ; a4 = buffer
        tst.l   d0
        bne.s   .ct_open
        bsr     .ct_oom
        bra     .ct_unlock
.ct_open:
        clr.l   -(sp)                ; 4(sp) = destination file
        move.l  WBS_DOSBASE(a5),a6
        move.l  a2,d1
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,-(sp)             ; (sp) = source file
        bne.s   .ct_odst
        moveq   #2,d0                ; "opening <source>"
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
        moveq   #2,d0                ; "opening <destination>"
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
        moveq   #3,d0                ; "reading"
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
        moveq   #4,d0                ; "writing"
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

; wb_reload(d7.w = drawer, a5): its icons are returned, the interior cleared, the directory re-read (icons redrawn
; as they come). Preserves d2-d7/a2-a5.
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
        bsr     wb_gaugeinfo
        bsr     wb_redraw1
        bsr     wb_loadicons
        bsr     wb_bars
.rl_ret:
        movem.l (sp)+,d2/a2-a4/a6
        rts

; wb_mkmenus(a5): copies the menu template into the state (intuition writes into the items) and relocates the
; internal pointers there (wbm_reloc table: offsets of the fields that point into the template). Preserves d2-d7/a2-a6.
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

; wb_strlen(a0) -> d0 = length. Preserves a0. wb_strcpy(a0 -> a1, d0 = max length): copy terminated by 0.
; wb_streq(a0, a1) -> Z = 1 if equal (ASCII case-insensitive). Clobbers d0/d1.
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
        clr.b   -1(a1)               ; terminator (or last byte sacrificed if truncated)
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

; --- menu template (struct Menu / MenuItem / IntuiText): internal pointers relative to wbm_tmpl, relocated by
; wb_mkmenus; the texts stay in ROM. Workbench (Open, Close, Duplicate, Rename, Info, Discard), Disk (Empty
; Trash, Initialize), Special (Clean Up, Last Error, Redraw, Snapshot, Version).
WBM_ITEMW       EQU 120
WBM_ITEMH       EQU 10
WBM_ON          EQU ITEMTEXT|ITEMENABLED|$40 ; text, enabled, HIGHCOMP
WBM_OFF         EQU ITEMTEXT|$40
WBMENU          MACRO                ; \1 = label, \2 = next (0 or label), \3 = x, \4 = width, \5 = name, \6 = 1st item
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
WBITEM          MACRO                ; \1 = label, \2 = next (0 or label), \3 = y, \4 = flags, \5 = text
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
        dc.b    2,1,JAM2,0           ; IntuiText: pen 2 on 1
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
; offsets (within the template) of the internal pointers to relocate: menus (next, 1st item), items (non-null
; next, text)
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
        even
wb_gadtab:                           ; scroll gadgets (spec §8.1): LeftEdge, TopEdge, Width, Height, Flags,
        ; Activation, GadgetType, GadgetID, rendering (0/1 vertical/horizontal bar, 2..5 arrow l/r/u/d)
        dc.w    -15,16,16,-31,$0054,$0013,3,2,0
        dc.w    13,-8,-40,9,$002C,$0083,3,1,1
        dc.w    2,-7,12,7,$000C,$0083,1,3,2
        dc.w    -25,-7,12,7,$001C,$0083,1,4,3
        dc.w    -14,10,14,6,$0014,$0013,1,5,4
        dc.w    -14,-14,14,6,$001C,$0013,1,6,5
wb_gaugetab:                         ; gauge (spec §8.4): pen, x0, base y0, dy0, x1, base y1, dy1; x < 0: from the
        ; right of the gauge; base 0 = BorderTop, 1 = Height - BorderBottom; -1: end
        dc.b    2, 2,0,-1, -1,0,5            ; top block
        dc.b    1, 4,0,0, -3,0,0             ; "F": top bar
        dc.b    1, 4,0,0, 5,0,4              ;      upright
        dc.b    1, 4,0,2, -5,0,2             ;      middle bar
        dc.b    2, 2,1,-6, -1,1,0            ; bottom block
        dc.b    1, 4,1,-5, 5,1,-1            ; "E": upright
        dc.b    1, 4,1,-5, -3,1,-5           ;      bars
        dc.b    1, 4,1,-3, -4,1,-3
        dc.b    1, 4,1,-1, -3,1,-1
        dc.b    -1                           ; (the rule to the right of the gauge is drawn separately)
        even
wb_arrimg:                           ; Arrow Images (1 plane: 1 = pen 1, 0 = pen 0; ImageData = offset in
        ; the block copied into CHIP, relocated by wb_arrowsinit)
        dc.w    -2,-1,14,8,1
        dc.l    4*IG_SIZE+(wb_arrl-wb_arrdata)
        dc.b    1,0
        dc.l    0
        dc.w    -1,-1,12,8,1
        dc.l    4*IG_SIZE+(wb_arrr-wb_arrdata)
        dc.b    1,0
        dc.l    0
        dc.w    -1,0,16,6,1
        dc.l    4*IG_SIZE+(wb_arru-wb_arrdata)
        dc.b    1,0
        dc.l    0
        dc.w    -1,0,16,6,1
        dc.l    4*IG_SIZE+(wb_arrd-wb_arrdata)
        dc.b    1,0
        dc.l    0
wb_arrdata:                          ; drawn from their description (chevron and shaft), not copied
wb_arrl:
        dc.w    $F8FC,$F1FC,$E3FC,$C7FC,$8000,$C7FC,$E3FC,$F1FC
wb_arrr:
        dc.w    $F1F0,$F8F0,$FC70,$FE30,$0010,$FE30,$FC70,$F8F0
wb_arru:
        dc.w    $FE7F,$F81F,$E667,$9E79,$FE7F,$FE7F
wb_arrd:
        dc.w    $FE7F,$FE7F,$9E79,$E667,$F81F,$FE7F
wb_arrdata_end:
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
wb_diskcopy:
        dc.b    "SYS:System/DiskCopy",0
wb_errfmt:
        dc.b    "Error while %s: %ld",0
wb_badchar:
        dc.b    "Do not use '%lc' in names",0
        even
wb_errtab:                           ; actions of the error messages, by index (spec §6.5)
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
; default disk icon (spec disk-change-v34 §4.2): DiskObject and Image copied into the volume record
; (pointers fixed up by wb_vfix), 32 x 16 drawing in 2 planes made by hand (K black, W white, O orange).
                cnop    0,2
wb_defobj:
        dc.w    $E310,1              ; do_Magic, do_Version
        dc.l    0                    ; Gadget : NextGadget
        dc.w    0,0,32,16            ;   LeftEdge, TopEdge, Width, Height
        dc.w    5,3,1                ;   Flags (GADGIMAGE|GADGHBOX), Activation, GadgetType (BOOLGADGET)
        dc.l    0,0,0,0,0            ;   GadgetRender (wb_vfix), SelectRender, GadgetText, MutualExclude, SpecialInfo
        dc.w    0                    ;   GadgetID
        dc.l    0                    ;   UserData
        dc.b    WBDISK,0             ; do_Type
        dc.l    wb_diskcopy          ; do_DefaultTool
        dc.l    0                    ; do_ToolTypes
        dc.l    NO_ICON_POSITION,NO_ICON_POSITION
        dc.l    0,0,0                ; do_DrawerData, do_ToolWindow, do_StackSize
        dc.w    0,0,32,16,2          ; Image: LeftEdge, TopEdge, Width, Height, Depth
        dc.l    0                    ;   ImageData (wb_vdefault)
        dc.b    3,0                  ;   PlanePick, PlaneOnOff
        dc.l    0                    ;   NextImage
                cnop    0,4
wb_defdata:                          ; plane 0
        dc.l    $00000000           ; KKKKKKKKKKKKKKKKKKKKKKKKKKKKKK..
        dc.l    $7FFFFFF8           ; KWWWWWWOOOOOOOOOOOOOOOOWWWWWWK..
        dc.l    $7FFF1FFC           ; KWWWWWWOOOOOOOOOKKKOOOOWWWWWWWK.
        dc.l    $7FFF1FFE           ; KWWWWWWOOOOOOOOOKKKOOOOWWWWWWWWK
        dc.l    $7FFF1FFE           ; KWWWWWWOOOOOOOOOKKKOOOOWWWWWWWWK
        dc.l    $7FFFFFFE           ; KWWWWWWOOOOOOOOOOOOOOOOWWWWWWWWK
        dc.l    $7FFFFFFE           ; KWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWK
        dc.l    $7FFFFFFE           ; KWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWK
        dc.l    $7000000E           ; KWWWKKKKKKKKKKKKKKKKKKKKKKKKWWWK
        dc.l    $77FFFFEE           ; KWWWKWWWWWWWWWWWWWWWWWWWWWWKWWWK
        dc.l    $760000EE           ; KWWWKWWKKKKKKKKKKKKKKKKKWWWKWWWK
        dc.l    $77FFFFEE           ; KWWWKWWWWWWWWWWWWWWWWWWWWWWKWWWK
        dc.l    $760007EE           ; KWWWKWWKKKKKKKKKKKKKKWWWWWWKWWWK
        dc.l    $77FFFFEE           ; KWWWKWWWWWWWWWWWWWWWWWWWWWWKWWWK
        dc.l    $77FFFFEE           ; KWWWKWWWWWWWWWWWWWWWWWWWWWWKWWWK
        dc.l    $00000000           ; KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
                                     ; plane 1
        dc.l    $FFFFFFFC
        dc.l    $81FFFE04
        dc.l    $81FFFE02
        dc.l    $81FFFE01
        dc.l    $81FFFE01
        dc.l    $81FFFE01
        dc.l    $80000001
        dc.l    $80000001
        dc.l    $8FFFFFF1
        dc.l    $88000011
        dc.l    $89FFFF11
        dc.l    $88000011
        dc.l    $89FFF811
        dc.l    $88000011
        dc.l    $88000011
        dc.l    $FFFFFFFF
wb_end:
