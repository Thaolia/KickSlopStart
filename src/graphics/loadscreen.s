; src/graphics/loadscreen.s — ÉCRAN DE CHARGEMENT (gros fichier).
; Rend VISIBLE le bitplane texte de la console.device (320x256, 1 plan) : monte une View dessus via l'ABI
; graphics.library (MakeVPort/MrgCop/LoadView), écrit « Chargement <nom>... », puis affiche une BARRE DE
; PROGRESSION ('#' par chunk) pendant une lecture STREAMING du fichier (ofs_stream_read, data-block par
; data-block, sans buffer whole-file), puis « OK ». La console.device blitte déjà les glyphes 8x8 dans son
; bitplane (#3a) ; ici on affiche ce bitplane et on y écrit via CMD_WRITE. Démo autonome (appels directs :
; console + graphics + ofs_stream ; pas de process/handler). NE REVIENT PAS (tient l'écran). a6 = SysBase.
;
; Clean-room : structures d'affichage publiques (graphics.i) + ofs streaming (D1, ADF de test) ; AUCUNE ROM.

                include "exec.i"
                include "graphics.i"
                include "ofs.i"

                xdef    loadscreen_demo
                xref    ofs_stream_open      ; dos/ofs.s (streaming OFS réel)
                xref    ofs_stream_read

LS_CHUNK      EQU 4096           ; octets lus par itération (progression = 1 '#' par chunk)
; offsets IOStdReq (console.s les redéfinit localement ; standard AmigaOS)
LS_IO_DEVICE  EQU 20
LS_IO_COMMAND EQU 28
LS_IO_LENGTH  EQU 36
LS_IO_DATA    EQU 40
LS_IOSIZE     EQU 48
LS_CMD_WRITE  EQU 3
; bloc de structures d'affichage : View/VP/RasInfo/BitMap/ColorMap/ColorTable[2] (mêmes offsets que gfx.s)
LS_STRUCTSZ   EQU GFX_O_COLORTAB+2*2

loadscreen_demo:
        ; --- 1. base console.device (son bitplane = la surface texte) ---
        lea     EB_DEVICELIST(a6),a0
        lea     ls_conname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,a4                        ; a4 = base console (préservé partout)
        ; --- 1b. bitplane 352x272 (= géométrie de gfx_MakeVPort, fixe overscan) + REPOINTE la console dessus ---
        ; (le bitplane natif de la console est 320x256 ; la géométrie d'affichage attend 352 px/ligne -> stride 44)
        move.l  #GFX_BOOT_PLANE_SZ,d0         ; 352x272, 1 plan (11968 o)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,d4                         ; d4 = bitplane loadscreen (préservé par ofs_stream/ls_write)
        move.l  d4,CONB_BITMAP(a4)           ; la console blitte désormais dans CE bitplane...
        move.w  #GFX_BOOT_BYTES,CONB_BWIDTH(a4) ; ...avec le stride 44 (352 px)
        clr.w   CONB_CURX(a4)                ; curseur à (0,0)
        clr.w   CONB_CURY(a4)
        ; --- 2. bloc de structures d'affichage (chip) ---
        move.l  #LS_STRUCTSZ,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,a2                        ; a2 = bloc de structures
        ; BitMap 352x272, 1 plan ; Planes[0] = le bitplane loadscreen (où la console blitte maintenant)
        move.w  #GFX_BOOT_BYTES,GFX_O_BITMAP+bm_BytesPerRow(a2)
        move.w  #GFX_BOOT_H,GFX_O_BITMAP+bm_Rows(a2)
        move.b  #1,GFX_O_BITMAP+bm_Depth(a2)
        move.l  d4,GFX_O_BITMAP+bm_Planes(a2)
        ; RasInfo -> BitMap
        lea     GFX_O_BITMAP(a2),a0
        move.l  a0,GFX_O_RASINFO+ri_BitMap(a2)
        ; ColorMap : 2 couleurs (fond bleu nuit / texte blanc)
        move.w  #2,GFX_O_COLORMAP+cm_Count(a2)
        lea     GFX_O_COLORTAB(a2),a0
        move.l  a0,GFX_O_COLORMAP+cm_ColorTable(a2)
        move.w  #$0002,(a0)                  ; COLOR00 = bleu nuit
        move.w  #$0FFF,2(a0)                 ; COLOR01 = blanc (glyphes)
        ; ViewPort 352x272 (= géométrie fixe de MakeVPort)
        move.w  #GFX_BOOT_W,GFX_O_VP+vp_DWidth(a2)
        move.w  #GFX_BOOT_H,GFX_O_VP+vp_DHeight(a2)
        lea     GFX_O_RASINFO(a2),a0
        move.l  a0,GFX_O_VP+vp_RasInfo(a2)
        lea     GFX_O_COLORMAP(a2),a0
        move.l  a0,GFX_O_VP+vp_ColorMap(a2)
        ; View -> ViewPort
        lea     GFX_O_VP(a2),a0
        move.l  a0,GFX_O_VIEW+v_ViewPort(a2)
        ; --- 3. graphics.library : MakeVPort/MrgCop/LoadView -> affiche le bitplane console ---
        lea     EB_LIBLIST(a6),a0
        lea     ls_gfxname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,a5                        ; a5 = GfxBase
        lea     GFX_O_VIEW(a2),a0
        lea     GFX_O_VP(a2),a1
        move.l  a5,a6
        jsr     LVO_MAKEVPORT(a6)
        move.l  a5,a6
        lea     GFX_O_VIEW(a2),a1
        jsr     LVO_MRGCOP(a6)
        move.l  a5,a6
        lea     GFX_O_VIEW(a2),a1
        jsr     LVO_LOADVIEW(a6)
        move.l  ($4).w,a6                    ; a6 = SysBase
        ; --- 4. ioreq console (CMD_WRITE) ---
        move.l  #LS_IOSIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,a3                        ; a3 = ioreq (préservé)
        move.l  a4,LS_IO_DEVICE(a3)          ; io_Device = console
        lea     ls_msg1(pc),a0              ; « Chargement bigseg... »
        moveq   #ls_msg1_len,d0
        bsr     ls_write
        ; --- 5. état streaming + buffer dest ---
        move.l  #SS_ALLOC,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,d2                        ; d2 = état streaming
        move.l  #LS_CHUNK,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,d3                        ; d3 = buffer dest (jeté ; on ne veut que la progression)
        lea     ls_fname(pc),a0            ; « bigseg »
        move.l  d2,a1                        ; a1 = état
        jsr     ofs_stream_open               ; d0 = 1 OK / 0 KO
        tst.l   d0
        beq.s   .failmsg
        lea     ls_ind(pc),a0                ; indent de la barre (colonne 0 rognée par l'overscan)
        moveq   #2,d0
        bsr     ls_write
        ; --- 6. boucle de lecture + barre de progression ---
.rloop:
        move.l  d2,a1                        ; a1 = état
        move.l  d3,a2                        ; a2 = dest
        move.l  #LS_CHUNK,d0
        jsr     ofs_stream_read               ; d0 = octets copiés (0 = EOF) ; préserve d2/d3/a3/a4
        tst.l   d0
        beq.s   .done
        lea     ls_hash(pc),a0              ; un '#' de progression
        moveq   #1,d0
        bsr     ls_write
        bra.s   .rloop
.done:
        lea     ls_msgok(pc),a0            ; « \nOK »
        moveq   #ls_msgok_len,d0
        bsr     ls_write
        bra.s   .hold
.failmsg:
        lea     ls_msgfail(pc),a0
        moveq   #ls_msgfail_len,d0
        bsr     ls_write
.hold:
        bra.s   .hold                         ; tient l'écran (démo)

; ls_write(a0 = buffer, d0 = longueur) : CMD_WRITE synchrone sur la console (a3 = ioreq, a4 = base console).
ls_write:
        move.l  a0,LS_IO_DATA(a3)
        move.l  d0,LS_IO_LENGTH(a3)
        move.w  #LS_CMD_WRITE,LS_IO_COMMAND(a3)
        move.l  a6,-(sp)
        move.l  a4,a6                         ; a6 = base console (convention BeginIO)
        move.l  a3,a1
        jsr     -30(a6)                       ; BeginIO (synchrone : console_beginio rend le flux)
        move.l  (sp)+,a6
        rts

ls_conname:   dc.b    "console.device",0
ls_gfxname:   dc.b    "graphics.library",0
ls_fname:     dc.b    "bigseg",0
ls_ind:       dc.b    "  "               ; retrait 2 colonnes (colonne 0 rognée par l'overscan)
              EVEN
ls_msg1:      dc.b    "  Chargement bigseg...",13,10
ls_msg1_end:
ls_msg1_len   EQU ls_msg1_end-ls_msg1
ls_hash:      dc.b    "#"
ls_msgok:     dc.b    13,10,"  OK",13,10
ls_msgok_end:
ls_msgok_len  EQU ls_msgok_end-ls_msgok
ls_msgfail:   dc.b    13,10,"  ECHEC",13,10
ls_msgfail_end:
ls_msgfail_len EQU ls_msgfail_end-ls_msgfail
              EVEN
