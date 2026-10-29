; src/graphics/loadscreen.s — LOADING SCREEN (large file).
; Makes the console.device text bitplane VISIBLE (320x256, 1 plane): sets up a View on it through the
; graphics.library ABI (MakeVPort/MrgCop/LoadView), writes "Chargement <nom>...", then shows a PROGRESS
; BAR ('#' per chunk) during a STREAMING read of the file (ofs_stream_read, data block by data block,
; without a whole-file buffer), then "OK". console.device already blits the 8x8 glyphs into its
; bitplane (#3a); here we display that bitplane and write into it via CMD_WRITE. Standalone demo (direct calls:
; console + graphics + ofs_stream; no process/handler). DOES NOT RETURN (holds the screen). a6 = SysBase.
;
; Clean-room: public display structures (graphics.i) + OFS streaming (D1, test ADF); NO ROM.

                include "exec.i"
                include "graphics.i"
                include "ofs.i"

                xdef    loadscreen_demo
                xref    ofs_stream_open      ; dos/ofs.s (real OFS streaming)
                xref    ofs_stream_read

LS_CHUNK      EQU 4096           ; bytes read per iteration (progress = 1 '#' per chunk)
; IOStdReq offsets (console.s redefines them locally; standard AmigaOS)
LS_IO_DEVICE  EQU 20
LS_IO_COMMAND EQU 28
LS_IO_LENGTH  EQU 36
LS_IO_DATA    EQU 40
LS_IOSIZE     EQU 48
LS_CMD_WRITE  EQU 3
; display structure block: View/VP/RasInfo/BitMap/ColorMap/ColorTable[2] (same offsets as gfx.s)
LS_STRUCTSZ   EQU GFX_O_COLORTAB+2*2

loadscreen_demo:
        ; --- 1. console.device base (its bitplane = the text surface) ---
        lea     EB_DEVICELIST(a6),a0
        lea     ls_conname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,a4                        ; a4 = console base (preserved throughout)
        ; --- 1b. 352x272 bitplane (= gfx_MakeVPort geometry, fixed overscan) + REPOINTS the console to it ---
        ; (the console's native bitplane is 320x256; the display geometry expects 352 px/row -> stride 44)
        move.l  #GFX_BOOT_PLANE_SZ,d0         ; 352x272, 1 plane (11968 bytes)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,d4                         ; d4 = loadscreen bitplane (preserved by ofs_stream/ls_write)
        move.l  d4,CONB_BITMAP(a4)           ; the console now blits into THIS bitplane...
        move.w  #GFX_BOOT_BYTES,CONB_BWIDTH(a4) ; ...with stride 44 (352 px)
        clr.w   CONB_CURX(a4)                ; cursor at (0,0)
        clr.w   CONB_CURY(a4)
        ; --- 2. display structure block (chip) ---
        move.l  #LS_STRUCTSZ,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,a2                        ; a2 = structure block
        ; BitMap 352x272, 1 plane; Planes[0] = the loadscreen bitplane (where the console now blits)
        move.w  #GFX_BOOT_BYTES,GFX_O_BITMAP+bm_BytesPerRow(a2)
        move.w  #GFX_BOOT_H,GFX_O_BITMAP+bm_Rows(a2)
        move.b  #1,GFX_O_BITMAP+bm_Depth(a2)
        move.l  d4,GFX_O_BITMAP+bm_Planes(a2)
        ; RasInfo -> BitMap
        lea     GFX_O_BITMAP(a2),a0
        move.l  a0,GFX_O_RASINFO+ri_BitMap(a2)
        ; ColorMap: 2 colours (midnight blue background / white text)
        move.w  #2,GFX_O_COLORMAP+cm_Count(a2)
        lea     GFX_O_COLORTAB(a2),a0
        move.l  a0,GFX_O_COLORMAP+cm_ColorTable(a2)
        move.w  #$0002,(a0)                  ; COLOR00 = midnight blue
        move.w  #$0FFF,2(a0)                 ; COLOR01 = white (glyphs)
        ; ViewPort 352x272 (= fixed MakeVPort geometry)
        move.w  #GFX_BOOT_W,GFX_O_VP+vp_DWidth(a2)
        move.w  #GFX_BOOT_H,GFX_O_VP+vp_DHeight(a2)
        lea     GFX_O_RASINFO(a2),a0
        move.l  a0,GFX_O_VP+vp_RasInfo(a2)
        lea     GFX_O_COLORMAP(a2),a0
        move.l  a0,GFX_O_VP+vp_ColorMap(a2)
        ; View -> ViewPort
        lea     GFX_O_VP(a2),a0
        move.l  a0,GFX_O_VIEW+v_ViewPort(a2)
        ; --- 3. graphics.library: MakeVPort/MrgCop/LoadView -> displays the console bitplane ---
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
        ; --- 4. console ioreq (CMD_WRITE) ---
        move.l  #LS_IOSIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,a3                        ; a3 = ioreq (preserved)
        move.l  a4,LS_IO_DEVICE(a3)          ; io_Device = console
        lea     ls_msg1(pc),a0              ; "Chargement bigseg..."
        moveq   #ls_msg1_len,d0
        bsr     ls_write
        ; --- 5. streaming state + dest buffer ---
        move.l  #SS_ALLOC,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,d2                        ; d2 = streaming state
        move.l  #LS_CHUNK,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .hold
        move.l  d0,d3                        ; d3 = dest buffer (discarded; we only want the progress)
        lea     ls_fname(pc),a0            ; "bigseg"
        move.l  d2,a1                        ; a1 = state
        jsr     ofs_stream_open               ; d0 = 1 OK / 0 failed
        tst.l   d0
        beq.s   .failmsg
        lea     ls_ind(pc),a0                ; bar indent (column 0 clipped by the overscan)
        moveq   #2,d0
        bsr     ls_write
        ; --- 6. read loop + progress bar ---
.rloop:
        move.l  d2,a1                        ; a1 = state
        move.l  d3,a2                        ; a2 = dest
        move.l  #LS_CHUNK,d0
        ; Turns off DISPLAY DMA (bitplane+copper) DURING the disk read: on WinUAE (timing-exact), running bitplane
        ; DMA starves disk DMA -> read fails (empty buffer, proven). FS-UAE does not model this contention.
        ; The Lemmings cracktro reads fine on WinUAE because it has no display of ours set up during the read.
        move.w  #(DMAF_RASTER|DMAF_COPPER),DMACON   ; clear BPLEN+COPEN (brief black screen)
        jsr     ofs_stream_read               ; d0 = bytes copied (0 = EOF); preserves d2/d3/a3/a4
        move.w  #(DMAF_SETCLR|DMAF_RASTER|DMAF_COPPER),DMACON  ; turn the display back on to paint the '#'
        tst.l   d0
        beq.s   .done
        lea     ls_hash(pc),a0              ; one progress '#'
        moveq   #1,d0
        bsr     ls_write
        bra.s   .rloop
.done:
        lea     ls_msgok(pc),a0            ; "\nOK"
        moveq   #ls_msgok_len,d0
        bsr     ls_write
        bra.s   .hold
.failmsg:
        lea     ls_msgfail(pc),a0
        moveq   #ls_msgfail_len,d0
        bsr     ls_write
.hold:
        bra.s   .hold                         ; holds the screen (demo)

; ls_write(a0 = buffer, d0 = length): synchronous CMD_WRITE on the console (a3 = ioreq, a4 = console base).
ls_write:
        move.l  a0,LS_IO_DATA(a3)
        move.l  d0,LS_IO_LENGTH(a3)
        move.w  #LS_CMD_WRITE,LS_IO_COMMAND(a3)
        move.l  a6,-(sp)
        move.l  a4,a6                         ; a6 = console base (BeginIO convention)
        move.l  a3,a1
        jsr     -30(a6)                       ; BeginIO (synchronous: console_beginio returns the stream)
        move.l  (sp)+,a6
        rts

ls_conname:   dc.b    "console.device",0
ls_gfxname:   dc.b    "graphics.library",0
ls_fname:     dc.b    "bigseg",0
ls_ind:       dc.b    "  "               ; 2-column indent (column 0 clipped by the overscan)
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
