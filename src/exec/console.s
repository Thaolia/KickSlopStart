; src/exec/console.s — console.device (#3a : rendu texte à l'écran via blitter de glyphes 8x8).
;
; ROMTag RTF_AUTOINIT NT_DEVICE pri 20 -> MakeLibrary (chemin AUTOINIT) crée la base, Enqueue dans EB_DEVICELIST.
; initfunc alloue un BITPLANE 1-plan (CON_BMSIZE octets, chip RAM) et l'état texte (curseur). BeginIO dispatche :
;   CMD_WRITE (io_Data=buf, io_Length=len) : interprète le flux octet par octet (con_putglyph) — caractère
;     imprimable -> BLIT du glyphe 8x8 (copie CPU de 8 octets depuis font8x8 dans le bitplane à (curx,cury)) +
;     avance colonne ; CR -> colonne 0 ; LF / dépassement de colonne -> ligne suivante (+8 px, clampée).
; Blitter = COPIE CPU synchrone (pas le Blitter matériel) : simple ET immédiat (le readback de preuve voit les
; octets tout de suite, pas d'attente blitter-done). graphics.library n'a pas de Text() -> rendu fait ici.
;
; Portée #3a : rendu WRITE prouvé par READBACK du bitplane (headless, marqueur série « CONSOLE WRITE OK ») ; le
; rendu À L'ÉCRAN (pointer le Copper sur ce bitplane) et la lecture clavier (#3b, via input.device) sont séparés.
; Déviations assumées : pas de scrolling (clamp en bas), pas de séquences CSI/ANSI, pas de curseur visible.
; Police 8x8 HAND-AUTHORED (domaine public, tests/mk_font8x8.py) — JAMAIS la topaz de la ROM (clean-room).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs console.device + includes NDK publics. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xref    font8x8          ; graphics/font8x8.s (glyphes 8x8, ASCII 0x20..0x7F)
                xref    kbd_cook         ; exec/keymap.s (#5 : cook keycode(+qualifiers)->ASCII, US/AZERTY)

CMD_READ     EQU 2                ; io_Command standard (io.i : READ=2, WRITE=3)
CMD_WRITE    EQU 3
IO_DATA2     EQU 40               ; IOStdReq io_Data (local : console.s n'inclut pas disk.i)
IO_LEN2      EQU 36               ; IOStdReq io_Length
IO_ACTUAL2   EQU 32               ; IOStdReq io_Actual

; --- ROMTag console.device (scanné par build_reslist) ---
                EVEN
console_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    console_romtag       ; RT_MATCHTAG = self
        dc.l    console_end          ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,34,NT_DEVICE,20  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (20 : place roadmap console)
        dc.l    console_name         ; RT_NAME
        dc.l    console_name         ; RT_IDSTRING
        dc.l    console_inittab      ; RT_INIT -> table AUTOINIT
console_name:
        dc.b    "console.device",0
        EVEN
console_inittab:
        dc.l    CONDEV_SIZE          ; dataSize
        dc.l    console_vectors      ; funcTable
        dc.l    console_datatab      ; dataTable (InitStruct)
        dc.l    console_initfunc     ; initFunc
console_vectors:                     ; table ABSOLUE, terminée par -1 (ordre device standard)
        dc.l    console_open         ; LVO -6
        dc.l    console_close        ; LVO -12
        dc.l    console_expunge      ; LVO -18
        dc.l    console_null         ; LVO -24 (réservé)
        dc.l    console_beginio      ; LVO -30
        dc.l    console_abortio      ; LVO -36
        dc.l    -1
console_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)   ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

; Open(iorequest a1, unité d0, flags d1) : io_Data = fenêtre (NEWCON:, CON:) -> io_Unit = ConUnit allouée pour
; cette fenêtre (devices/conunit.h : cu_Window, curseur, bornes de la zone de texte) ; io_Data = 0 -> io_Unit = la
; base (bitplane partagé, sans fenêtre). Les requêtes d'une unité ouverte suivent la sémantique exec standard
; (réponse ReplyMsg hors IOF_QUICK, CMD_READ mis en attente tant qu'aucun caractère n'est arrivé).
console_open:
        movem.l a2/a6,-(sp)
        move.l  a1,a2
        clr.b   IO_ERROR(a2)
        move.l  IO_DATA2(a2),d0
        bne.s   .co_win
        move.l  a6,IO_UNIT(a2)
        bra.s   .co_ok
.co_win:
        move.l  ($4).w,a6
        move.l  #CU_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  4(sp),a6             ; a6 = base console
        tst.l   d0
        bne.s   .co_unit
        move.b  #-1,IO_ERROR(a2)     ; IOERR_OPENFAIL
        bra.s   .co_ret
.co_unit:
        move.l  d0,a0
        move.l  IO_DATA2(a2),a1
        bsr     cu_init
        move.l  a0,IO_UNIT(a2)
.co_ok:
        addq.w  #1,LIB_OPENCNT(a6)
.co_ret:
        movem.l (sp)+,a2/a6
        rts
; Close(iorequest a1) : libère la ConUnit d'une unité fenêtre.
console_close:
        subq.w  #1,LIB_OPENCNT(a6)
        move.l  IO_UNIT(a1),d0
        beq.s   .cc_ret
        cmp.l   a6,d0
        beq.s   .cc_ret
        clr.l   IO_UNIT(a1)
        move.l  a6,-(sp)
        move.l  d0,a1
        move.l  #CU_SIZE,d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  (sp)+,a6
.cc_ret:
        moveq   #0,d0
        rts
console_expunge:
        moveq   #0,d0
        rts
console_null:
        moveq   #0,d0
        rts
; AbortIO(iorequest a1) : retire un CMD_READ en attente (io_Error = IOERR_ABORTED) et y répond. -> d0 = 0.
console_abortio:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        lea     CONB_RQ(a2),a0       ; a0 = maillon précédent (LN_SUCC à l'offset 0)
.ca_lp:
        move.l  (a0),d0
        beq.s   .ca_none
        cmp.l   d0,a1
        beq.s   .ca_found
        move.l  d0,a0
        bra.s   .ca_lp
.ca_found:
        move.l  (a1),(a0)            ; décroche
        move.b  #IOERR_ABORTED,IO_ERROR(a1)
        jsr     LVO_ENABLE(a6)
        jsr     LVO_REPLYMSG(a6)
        bra.s   .ca_ret
.ca_none:
        jsr     LVO_ENABLE(a6)
.ca_ret:
        moveq   #0,d0
        movem.l (sp)+,a2/a6
        rts

; console_beginio(device a6, ioreq a1) : CMD_WRITE -> rend le flux. Synchrone. a6 ressort = base device.
console_beginio:
        movem.l d4/a2-a4,-(sp)
        move.l  a6,a2                ; a2 = base device (= état console)
        move.l  a1,a3                ; a3 = ioreq
        clr.b   IO_ERROR(a3)
        tst.l   IO_UNIT(a3)
        bne     .bi_unit             ; unité ouverte : sémantique asynchrone
        move.w  IO_COMMAND(a3),d0
        cmp.w   #CMD_WRITE,d0
        beq.s   .bi_write
        cmp.w   #CMD_READ,d0
        beq.s   .bi_read
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
        bra.s   .bi_done
.bi_write:
        move.l  IO_DATA2(a3),a4      ; a4 = buffer
        move.l  IO_LEN2(a3),d4       ; d4 = longueur
.bi_wl:
        tst.l   d4
        beq.s   .bi_done
        move.b  (a4)+,d0
        bsr     con_putglyph         ; rend un octet (a2 = base ; clobbe d0/d1/a0/a1)
        subq.l  #1,d4
        bra.s   .bi_wl
.bi_read:                            ; #3b : draine le read buffer (ASCII cuit via input.device) vers io_Data
        move.l  IO_DATA2(a3),a4      ; dest
        move.l  IO_LEN2(a3),d4       ; max
        moveq   #0,d0                ; compte lu
.bi_rl:
        tst.l   d4
        beq.s   .bi_rdone
        move.w  CONB_RHEAD(a2),d1
        cmp.w   CONB_RTAIL(a2),d1
        beq.s   .bi_rdone            ; read buffer vide
        lea     CONB_RBUF(a2),a0
        move.b  0(a0,d1.w),(a4)+
        addq.w  #1,d1
        and.w   #CON_RBMASK,d1
        move.w  d1,CONB_RHEAD(a2)
        addq.l  #1,d0
        subq.l  #1,d4
        bra.s   .bi_rl
.bi_rdone:
        move.l  d0,IO_ACTUAL2(a3)    ; io_Actual = octets lus
.bi_done:
        move.l  a2,a6                ; a6 = base device (convention BeginIO)
        movem.l (sp)+,d4/a2-a4
        rts
; --- unité ouverte (requête issue d'OpenDevice) : appelants synchrones directs = IO_UNIT nul (chemin ci-dessus) ---
.bi_unit:
        move.w  IO_COMMAND(a3),d0
        cmp.w   #CMD_WRITE,d0
        beq.s   .bu_write
        cmp.w   #CMD_READ,d0
        beq.s   .bu_read
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
        bra.s   .bu_reply
.bu_write:
        move.l  IO_DATA2(a3),a4
        move.l  IO_LEN2(a3),d4
        cmp.l   #-1,d4               ; io_Length = -1 : chaîne terminée par 0
        bne.s   .bu_len
        moveq   #0,d4
        move.l  a4,a0
.bu_strlen:
        tst.b   (a0)+
        beq.s   .bu_len
        addq.l  #1,d4
        bra.s   .bu_strlen
.bu_len:
        move.l  d4,IO_ACTUAL2(a3)
        move.l  IO_UNIT(a3),a0
        cmp.l   a2,a0
        beq.s   .bu_wl               ; unité sans fenêtre : bitplane partagé
        move.l  CU_WINDOW(a0),a1
        tst.l   WD_RPORT(a1)
        beq.s   .bu_wl               ; fenêtre sans RastPort : bitplane partagé
        tst.l   CONB_GFXBASE(a2)
        beq.s   .bu_wl
        bsr     cu_write
        bra     .bu_reply
.bu_wl:
        tst.l   d4
        beq.s   .bu_reply
        move.b  (a4)+,d0
        bsr     con_putglyph
        subq.l  #1,d4
        bra.s   .bu_wl
.bu_read:
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.l  a3,a1
        bsr     con_fillread         ; d0 = octets copiés
        tst.l   d0
        bne.s   .bu_rgot
        bclr    #0,IO_FLAGS(a3)      ; rien à lire : en attente (réponse par le handler d'input)
        clr.l   (a3)                 ; LN_SUCC = fin de file
        lea     CONB_RQ(a2),a0
.bu_tail:
        tst.l   (a0)
        beq.s   .bu_link
        move.l  (a0),a0
        bra.s   .bu_tail
.bu_link:
        move.l  a3,(a0)
        jsr     LVO_ENABLE(a6)
        bra     .bi_done
.bu_rgot:
        jsr     LVO_ENABLE(a6)
.bu_reply:
        btst    #0,IO_FLAGS(a3)      ; IOF_QUICK : terminé sur place
        bne     .bi_done
        move.l  ($4).w,a6
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        bra     .bi_done

; con_fillread(a1 = CMD_READ, a2 = base) : copie le read buffer dans io_Data (max io_Length) -> d0 = octets copiés
; = io_Actual. Appelé sous Disable. Clobbe d1/a0.
con_fillread:
        movem.l d2/a3,-(sp)
        move.l  IO_DATA2(a1),a3
        move.l  IO_LEN2(a1),d2
        moveq   #0,d0
.cf_lp:
        tst.l   d2
        beq.s   .cf_done
        move.w  CONB_RHEAD(a2),d1
        cmp.w   CONB_RTAIL(a2),d1
        beq.s   .cf_done
        lea     CONB_RBUF(a2),a0
        move.b  0(a0,d1.w),(a3)+
        addq.w  #1,d1
        and.w   #CON_RBMASK,d1
        move.w  d1,CONB_RHEAD(a2)
        addq.l  #1,d0
        subq.l  #1,d2
        bra.s   .cf_lp
.cf_done:
        move.l  d0,IO_ACTUAL2(a1)
        movem.l (sp)+,d2/a3
        rts

; con_putglyph(d0.b = caractère, a2 = base console) : rend un octet. Clobbe d0/d1/a0/a1 ; préserve le reste
; (sauve d2/d3 pour le blit). CR -> colonne 0 ; LF / wrap -> ligne suivante (+8, clampée) ; imprimable -> blit.
con_putglyph:
        tst.b   CONB_ESC(a2)         ; séquence ESC / CSI en cours : ignorée (pas d'interprétation ANSI)
        beq.s   .cpg_plain
        cmp.b   #1,CONB_ESC(a2)
        bne.s   .cpg_csi
        move.b  #2,CONB_ESC(a2)      ; ESC suivi de '[' = CSI ; autre caractère = fin de séquence
        cmp.b   #'[',d0
        beq     .cpg_ret
        clr.b   CONB_ESC(a2)
        rts
.cpg_csi:
        cmp.b   #$40,d0              ; octet final d'un CSI : $40..$7E
        blo     .cpg_ret
        cmp.b   #$7E,d0
        bhi     .cpg_ret
        clr.b   CONB_ESC(a2)
        rts
.cpg_plain:
        cmp.b   #$1B,d0
        bne.s   .cpg_n9b
        move.b  #1,CONB_ESC(a2)
        rts
.cpg_n9b:
        cmp.b   #$9B,d0
        bne.s   .cpg_chr
        move.b  #2,CONB_ESC(a2)
        rts
.cpg_chr:
        cmp.b   #13,d0
        beq     .cpg_cr
        cmp.b   #10,d0
        beq     .cpg_nl
        cmp.b   #$20,d0
        blo     .cpg_ret             ; contrôle (<space) non géré -> ignore
        cmp.b   #$7F,d0
        bhi     .cpg_ret
                ifeq    CON_NO_BLIT
        move.l  CONB_BITMAP(a2),d1
        bne.s   .cpg_have
        movem.l d0/a6,-(sp)          ; bitplane de l'unité sans fenêtre : alloué à la première écriture (10 Ko de
        move.l  ($4).w,a6            ; chip que les systèmes à fenêtres n'utilisent jamais)
        move.l  #CON_BMSIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,CONB_BITMAP(a2)
        move.l  d0,d1
        movem.l (sp)+,d0/a6
        tst.l   d1
        beq.s   .cpg_advance         ; pas de bitplane (alloc échouée) -> n'écrit pas, avance quand même
.cpg_have:
        movem.l d2/d3,-(sp)
        moveq   #0,d1
        move.b  d0,d1
        subi.w  #$20,d1
        lsl.w   #3,d1                ; (char-0x20)*8 = offset du glyphe
        move.l  #font8x8,a0
        add.l   d1,a0                ; a0 = glyphe (8 octets)
        move.l  CONB_BITMAP(a2),a1
        moveq   #0,d2
        move.w  CONB_BWIDTH(a2),d2   ; d2 = stride (octets/ligne)
        moveq   #0,d1
        move.w  CONB_CURY(a2),d1
        mulu    d2,d1                ; cury * stride (cury<256, stride=40 -> <10240)
        add.l   d1,a1
        moveq   #0,d1
        move.w  CONB_CURX(a2),d1
        add.l   d1,a1                ; a1 = dest = bitplane + cury*stride + curx
        moveq   #7,d3                ; 8 lignes
.cpg_row:
        move.b  (a0)+,(a1)           ; octet glyphe -> bitplane
        add.w   d2,a1                ; ligne suivante (+stride)
        dbra    d3,.cpg_row
        movem.l (sp)+,d2/d3
                endc                 ; RED CON_NO_BLIT : blit sauté -> cellules non-espace restent à 0
.cpg_advance:
        addq.w  #1,CONB_CURX(a2)     ; avance la colonne
        cmp.w   #CON_COLS,CONB_CURX(a2)
        blo.s   .cpg_ret
        clr.w   CONB_CURX(a2)        ; dépassement -> colonne 0 + ligne suivante
        bra.s   .cpg_nl
.cpg_cr:
        clr.w   CONB_CURX(a2)        ; retour chariot
        bra.s   .cpg_ret
.cpg_nl:
        move.w  CONB_CURY(a2),d0     ; ligne suivante (+8 px)
        add.w   #8,d0
        cmp.w   #CON_PXH,d0
        blo.s   .cpg_sety
        move.w  #CON_PXH-8,d0        ; clamp en bas (pas de scroll ce milestone)
.cpg_sety:
        move.w  d0,CONB_CURY(a2)
.cpg_ret:
        rts

; console_input_handler(a0 = liste d'InputEvents, a1 = is_Data = base console) : #3b — handler enregistré sur
; input.device via IND_ADDHANDLER. Cuit chaque RAWKEY key-down (keycode -> ASCII via kbd_keymap) et le pousse dans
; le read buffer de console.device (que CMD_READ ressert). Rend d0 = liste inchangée (pass-through). Convention
; handler : préserve d2-d7/a2-a6 (on sauve d2/d3/a2/a3). Cook minimal (keymap US de F2b ; shift/ctrl = keymap.resource #5).
console_input_handler:
        movem.l d2/d3/a2/a3,-(sp)
        move.l  a0,d3                ; d3 = liste originale (retour pass-through)
        move.l  a1,a2                ; a2 = base console
        move.l  a0,a3                ; a3 = event courant
.cih_loop:
        move.l  a3,d0
        beq.s   .cih_done            ; NextEvent == 0 -> fin de liste
        cmp.b   #IECLASS_RAWKEY,IE_CLASS(a3)
        bne.s   .cih_next
        move.w  IE_CODE(a3),d2       ; keycode (bit 7 = up/down)
        btst    #7,d2
        bne.s   .cih_next            ; key-up -> ignore
        and.w   #$007F,d2
        move.l  d2,d0                ; d0 = keycode
        move.w  IE_QUALIFIER(a3),d1  ; d1 = qualifieurs de l'event (shift/caps/ctrl)
        jsr     kbd_cook             ; #5 : cuisson via keymap active (préserve d2/a0/a1)
        move.b  d0,d2                ; d2.b = ASCII cuit (0 = non mappé)
        beq.s   .cih_next
                ifeq    CON_NO_READBUF
        move.w  CONB_RTAIL(a2),d0    ; push ASCII dans le read buffer
        move.w  d0,d1
        addq.w  #1,d1
        and.w   #CON_RBMASK,d1
        cmp.w   CONB_RHEAD(a2),d1
        beq.s   .cih_next            ; plein -> drop
        lea     CONB_RBUF(a2),a0
        move.b  d2,0(a0,d0.w)
        move.w  d1,CONB_RTAIL(a2)
        bsr     con_servereads       ; un CMD_READ d'unité ouverte attendait : servi et répondu
                endc                 ; RED CON_NO_READBUF : cuit mais ne bufferise pas -> CMD_READ vide
.cih_next:
        move.l  IE_NEXTEVENT(a3),a3  ; event suivant
        bra.s   .cih_loop
.cih_done:
        move.l  d3,d0                ; rend la liste originale (pass-through)
        movem.l (sp)+,d2/d3/a2/a3
        rts

; con_servereads(a2 = base) : si un CMD_READ attend et que le read buffer a des octets, le remplit, le décroche
; et y répond. Préserve d2-d7/a2-a6.
con_servereads:
        movem.l a3/a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_DISABLE(a6)
        move.l  CONB_RQ(a2),d0
        beq.s   .sr_none
        move.l  d0,a3
        move.l  a3,a1
        bsr     con_fillread
        tst.l   d0
        beq.s   .sr_none
        move.l  (a3),CONB_RQ(a2)     ; décroche la tête de file
        jsr     LVO_ENABLE(a6)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        bra.s   .sr_ret
.sr_none:
        jsr     LVO_ENABLE(a6)
.sr_ret:
        movem.l (sp)+,a3/a6
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Pose le nom, alloue le bitplane, init l'état,
; et ENREGISTRE le handler d'input sur input.device (IND_ADDHANDLER) -> le clavier (via input.device) alimentera
; le read buffer. input.device (pri 40) est inité AVANT console (pri 20) -> présent à ce stade.
console_initfunc:
        movem.l d2/a2/a3,-(sp)
        move.l  d0,a2                ; a2 = base device
        lea     console_name(pc),a0
        move.l  a0,LN_NAME(a2)
        move.w  #CON_BYTEW,CONB_BWIDTH(a2)
        move.w  #CON_PXH,CONB_PXROWS(a2)
        clr.w   CONB_CURX(a2)
        clr.w   CONB_CURY(a2)
        clr.w   CONB_RHEAD(a2)
        clr.w   CONB_RTAIL(a2)
        lea     EB_LIBLIST(a6),a0    ; GfxBase (graphics.library, pri 65, initialisée avant console, pri 20)
        lea     console_gfxname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,CONB_GFXBASE(a2)
        ; prépare le struct Interrupt du handler (dans la base) + enregistre sur input.device
        move.b  #0,CONB_INT+LN_PRI(a2)
        move.l  #console_input_handler,CONB_INT+IS_CODE(a2)
        move.l  a2,CONB_INT+IS_DATA(a2)     ; is_Data = base console (reçu en a1 par le handler)
        lea     EB_DEVICELIST(a6),a0
        lea     console_inputdev(pc),a1     ; FindName("input.device")
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .ci_done
        move.l  d0,a3                        ; a3 = base input.device
        move.l  a3,-(sp)                     ; (AllocMem clobbe a0/a1/d0/d1 ; a2/a3 préservés)
        move.l  #64,d0                        ; ioreq temporaire
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,a3
        tst.l   d0
        beq.s   .ci_done
        move.l  d0,a1                        ; a1 = ioreq
        move.l  a3,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        lea     CONB_INT(a2),a0
        move.l  a0,IO_DATA2(a1)
        move.l  a1,-(sp)                     ; sauve ioreq (pour le free)
        move.l  a3,a6                        ; a6 = base input.device pour BeginIO
        jsr     -30(a6)                      ; input BeginIO IND_ADDHANDLER (Enqueue CONB_INT dans la chaîne)
        move.l  ($4).w,a6                    ; restaure a6 = SysBase
        move.l  (sp)+,a1                     ; ioreq
        move.l  #64,d0
        jsr     LVO_FREEMEM(a6)
.ci_done:
        move.l  a2,d0                ; retourne la base
        movem.l (sp)+,d2/a2/a3
        rts

console_inputdev:
        dc.b    "input.device",0
console_gfxname:
        dc.b    "graphics.library",0
        EVEN

; === unités fenêtre (ConUnit) : rendu dans le RastPort de la fenêtre via graphics.library ===
; Zone de texte = intérieur de la fenêtre (bordures exclues), cellules 8x8. Contrôles : BEL ignoré, BS, TAB (tous les
; 8), LF (avec retour en colonne 0), VT, FF (efface), CR, ESC c (réinitialise), $84 IND, $85 NEL, $8D RI. CSI
; (ESC [ ou $9B) : A B C D E F (déplacements), H f (position), J K (effacements), L M (insertion / suppression de
; lignes), m (stylos 30-37/40-47, inversion 7, 0 = défaut : texte stylo 2, fond 0), SPACE p (curseur visible ou
; non). CSI P (suppression de caractères) efface jusqu'à la fin de la ligne (pas de décalage horizontal) ; @, t, u,
; x, y, q ignorés. Retour à la ligne automatique en écrivant au-delà de la dernière colonne, défilement d'une ligne en bas de zone. Curseur :
; cellule inversée (mode COMPLEMENT), retirée avant chaque écriture et redessinée après.
CU_WINDOW       EQU 34               ; struct ConUnit (devices/conunit.h)
CU_XCP          EQU 38
CU_YCP          EQU 40
CU_XMAX         EQU 42
CU_YMAX         EQU 44
CU_XRSIZE       EQU 46
CU_YRSIZE       EQU 48
CU_XRORIGIN     EQU 50
CU_YRORIGIN     EQU 52
CU_XREXTANT     EQU 54
CU_YREXTANT     EQU 56
CU_FGPEN        EQU 259
CU_BGPEN        EQU 260
CU_ESC          EQU 296              ; privé : 0 normal, 1 après ESC, 2 dans un CSI
CU_NPAR         EQU 297              ; privé : index du paramètre CSI courant (0..1)
CU_PSEEN        EQU 298              ; privé : un chiffre a été lu pour le paramètre 0
CU_INTER        EQU 299              ; privé : octet intermédiaire du CSI ($20..$2F)
CU_PAR0         EQU 300              ; privé : paramètres CSI
CU_PAR1         EQU 302
CU_CUROFF       EQU 304              ; privé : curseur masqué (CSI 0 SPACE p)
CU_CURVIS       EQU 305              ; privé : curseur actuellement dessiné
CU_INV          EQU 306              ; privé : vidéo inverse (CSI 7 m)
CU_SIZE         EQU 308
CU_DEFFG        EQU 2                ; stylo du texte par défaut : noir sur le fond vert (thème du projet ; 1.3 : 1)

; cu_init(a0 = ConUnit effacée, a1 = Window) : bornes de la zone de texte depuis la géométrie de la fenêtre.
; Préserve tout sauf d0/d1.
cu_init:
        move.l  a1,CU_WINDOW(a0)
        move.w  #GFX_FONTW,CU_XRSIZE(a0)
        move.w  #GFX_FONTH,CU_YRSIZE(a0)
        moveq   #0,d0
        move.b  WD_BORDERLEFT(a1),d0
        move.w  d0,CU_XRORIGIN(a0)
        move.b  WD_BORDERTOP(a1),d0
        move.w  d0,CU_YRORIGIN(a0)
        move.w  WD_WIDTH(a1),d0
        moveq   #0,d1
        move.b  WD_BORDERLEFT(a1),d1
        sub.w   d1,d0
        move.b  WD_BORDERRIGHT(a1),d1
        sub.w   d1,d0
        asr.w   #3,d0
        subq.w  #1,d0
        bpl.s   .ci_x
        moveq   #0,d0
.ci_x:
        move.w  d0,CU_XMAX(a0)
        addq.w  #1,d0
        lsl.w   #3,d0
        add.w   CU_XRORIGIN(a0),d0
        subq.w  #1,d0
        move.w  d0,CU_XREXTANT(a0)
        move.w  WD_HEIGHT(a1),d0
        moveq   #0,d1
        move.b  WD_BORDERTOP(a1),d1
        sub.w   d1,d0
        move.b  WD_BORDERBOTTOM(a1),d1
        sub.w   d1,d0
        asr.w   #3,d0
        subq.w  #1,d0
        bpl.s   .ci_y
        moveq   #0,d0
.ci_y:
        move.w  d0,CU_YMAX(a0)
        addq.w  #1,d0
        lsl.w   #3,d0
        add.w   CU_YRORIGIN(a0),d0
        subq.w  #1,d0
        move.w  d0,CU_YREXTANT(a0)
        move.b  #CU_DEFFG,CU_FGPEN(a0)
        clr.b   CU_BGPEN(a0)
        rts

; cu_write(a0 = ConUnit, a4 = données, d4 = longueur, a2 = base console) : interprète le flux dans la fenêtre.
; Préserve d2-d7/a2-a6 (a4/d4 consommés : sauvés).
cu_write:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  a0,a5                ; a5 = ConUnit
        move.l  CONB_GFXBASE(a2),a6  ; a6 = GfxBase
        move.l  CU_WINDOW(a5),a0
        move.l  WD_RPORT(a0),a3      ; a3 = RastPort
        move.l  a3,a1
        moveq   #JAM2,d0
        jsr     LVO_SETDRMD(a6)
        bsr     cu_setpens
        bsr     cu_curoff
.cw_lp:
        tst.l   d4
        beq.s   .cw_end
        tst.b   CU_ESC(a5)
        bne.s   .cw_ctl
        move.b  (a4),d0
        bsr     cu_isprint
        beq.s   .cw_print
.cw_ctl:
        move.b  (a4)+,d0
        subq.l  #1,d4
        bsr     cu_ctl
        bra.s   .cw_lp
.cw_print:
        move.w  CU_XCP(a5),d0        ; colonne au-delà de la dernière : retour à la ligne avant d'écrire
        cmp.w   CU_XMAX(a5),d0
        ble.s   .cw_fit
        clr.w   CU_XCP(a5)
        bsr     cu_lf
.cw_fit:
        move.w  CU_XMAX(a5),d3
        sub.w   CU_XCP(a5),d3
        addq.w  #1,d3                ; d3 = cellules restantes sur la ligne
        move.l  a4,a2                ; a2 = début de la plage
        moveq   #0,d2                ; d2 = longueur de la plage
.cw_cnt:
        cmp.w   d3,d2
        bge.s   .cw_out
        tst.l   d4
        beq.s   .cw_out
        move.b  (a4),d0
        bsr     cu_isprint
        bne.s   .cw_out
        addq.l  #1,a4
        subq.l  #1,d4
        addq.w  #1,d2
        bra.s   .cw_cnt
.cw_out:
        bsr     cu_cellxy
        addq.w  #GFX_FONTBASE,d1
        move.l  a3,a1
        jsr     LVO_MOVE(a6)
        move.l  a2,a0
        move.w  d2,d0
        move.l  a3,a1
        jsr     LVO_TEXT(a6)
        add.w   d2,CU_XCP(a5)
        bra.s   .cw_lp
.cw_end:
        bsr     cu_curon
        movem.l (sp)+,d2-d7/a2-a6
        rts

; cu_isprint(d0.b) -> Z = 1 si caractère imprimable ($20..$7E, $A0..$FF). Ne touche que les codes conditions.
cu_isprint:
        cmp.b   #$20,d0
        blo.s   .ip_no
        cmp.b   #$7F,d0
        blo.s   .ip_yes
        cmp.b   #$A0,d0
        blo.s   .ip_no
.ip_yes:
        move.w  #4,ccr               ; Z = 1
        rts
.ip_no:
        move.w  #0,ccr               ; Z = 0
        rts

; cu_cellxy(a5) -> d0.w/d1.w = coin haut-gauche de la cellule du curseur (coordonnées de la fenêtre).
cu_cellxy:
        move.w  CU_XCP(a5),d0
        lsl.w   #3,d0
        add.w   CU_XRORIGIN(a5),d0
        move.w  CU_YCP(a5),d1
        lsl.w   #3,d1
        add.w   CU_YRORIGIN(a5),d1
        rts

; cu_setpens(a5, a3 = RastPort, a6 = GfxBase) : stylos A/B effectifs (permutés en vidéo inverse). Clobbe d0/d1/a0/a1.
cu_setpens:
        moveq   #0,d0
        move.b  CU_FGPEN(a5),d0
        moveq   #0,d1
        move.b  CU_BGPEN(a5),d1
        tst.b   CU_INV(a5)
        beq.s   .sp_n
        exg     d0,d1
.sp_n:
        move.l  d1,-(sp)
        move.l  a3,a1
        jsr     LVO_SETAPEN(a6)
        move.l  (sp)+,d0
        move.l  a3,a1
        jmp     LVO_SETBPEN(a6)

; cu_curoff / cu_curon(a5, a3, a6) : retire / dessine le curseur (cellule inversée). Clobbe d0-d3/a0/a1.
cu_curoff:
        tst.b   CU_CURVIS(a5)
        beq.s   cu_ret
        clr.b   CU_CURVIS(a5)
        bra.s   cu_cplcell
cu_curon:
        tst.b   CU_CUROFF(a5)
        bne.s   cu_ret
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        bgt.s   cu_ret               ; en attente de retour à la ligne : pas de cellule
        st      CU_CURVIS(a5)
cu_cplcell:
        move.l  a3,a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        bsr     cu_cellxy
        move.w  d0,d2
        addq.w  #GFX_FONTW-1,d2
        move.w  d1,d3
        addq.w  #GFX_FONTH-1,d3
        move.l  a3,a1
        jsr     LVO_RECTFILL(a6)
        move.l  a3,a1
        moveq   #JAM2,d0
        jmp     LVO_SETDRMD(a6)
cu_ret:
        rts

; cu_fill(d0..d3 = rectangle, a3, a6) : remplit au stylo de fond effectif. Clobbe d0-d3/a0/a1.
cu_fill:
        movem.w d0-d3,-(sp)
        move.l  a3,a1
        moveq   #0,d0
        move.b  CU_BGPEN(a5),d0
        tst.b   CU_INV(a5)
        beq.s   .fl_n
        move.b  CU_FGPEN(a5),d0
.fl_n:
        jsr     LVO_SETAPEN(a6)
        movem.w (sp)+,d0-d3
        move.l  a3,a1
        jsr     LVO_RECTFILL(a6)
        bra     cu_setpens

; cu_scroll(d1.w = dy en pixels, d3.w = première ligne en pixels, a3, a6) : décale [d3 .. YRExtant] de la zone de
; texte (vers le haut si dy > 0), bande libérée au stylo B. Clobbe d0-d3/a0/a1.
cu_scroll:
        movem.l d4/d5,-(sp)
        moveq   #0,d0
        move.w  CU_XRORIGIN(a5),d2
        move.w  CU_XREXTANT(a5),d4
        move.w  CU_YREXTANT(a5),d5
        move.l  a3,a1
        jsr     LVO_SCROLLRASTER(a6)
        movem.l (sp)+,d4/d5
        rts

; cu_lf(a5, a3, a6) : ligne suivante ; en bas de zone, défilement d'une ligne. Clobbe d0-d3/a0/a1.
cu_lf:
        move.w  CU_YCP(a5),d0
        cmp.w   CU_YMAX(a5),d0
        bge.s   .lf_scroll
        addq.w  #1,CU_YCP(a5)
        rts
.lf_scroll:
        move.w  CU_YMAX(a5),CU_YCP(a5)
        moveq   #GFX_FONTH,d1
        move.w  CU_YRORIGIN(a5),d3
        bra.s   cu_scroll

; cu_eol(a5, a3, a6) : efface de la cellule du curseur à la fin de la ligne. Clobbe d0-d3/a0/a1.
cu_eol:
        move.w  CU_XCP(a5),d0
        cmp.w   CU_XMAX(a5),d0
        bgt.s   cu_ret
        bsr     cu_cellxy
        move.w  CU_XREXTANT(a5),d2
        move.w  d1,d3
        addq.w  #GFX_FONTH-1,d3
        bra.s   cu_fill

; cu_ctl(d0.b = octet de contrôle ou de séquence, a5, a3, a6) : contrôles et séquences ESC / CSI.
; Clobbe d0-d3/d5-d7/a0/a1.
cu_ctl:
        move.b  CU_ESC(a5),d1
        beq.s   .ct_plain
        subq.b  #1,d1
        beq     .ct_esc
        bra     .ct_csi
.ct_plain:
        cmp.b   #$1B,d0
        bne.s   .ct_n1b
        move.b  #1,CU_ESC(a5)
        rts
.ct_n1b:
        cmp.b   #$9B,d0
        beq     .ct_csistart
        cmp.b   #8,d0
        bne.s   .ct_nbs
        tst.w   CU_XCP(a5)
        beq.s   .ct_ret
        move.w  CU_XCP(a5),d0        ; après une ligne pleine, BS revient sur la dernière colonne
        cmp.w   CU_XMAX(a5),d0
        ble.s   .ct_bs
        move.w  CU_XMAX(a5),CU_XCP(a5)
        rts
.ct_bs:
        subq.w  #1,CU_XCP(a5)
.ct_ret:
        rts
.ct_nbs:
        cmp.b   #9,d0
        bne.s   .ct_ntab
        move.w  CU_XCP(a5),d0
        or.w    #7,d0
        addq.w  #1,d0
        cmp.w   CU_XMAX(a5),d0
        ble.s   .ct_tab
        move.w  CU_XMAX(a5),d0
.ct_tab:
        move.w  d0,CU_XCP(a5)
        rts
.ct_ntab:
        cmp.b   #10,d0
        bne.s   .ct_nlf
        clr.w   CU_XCP(a5)
        bra     cu_lf
.ct_nlf:
        cmp.b   #11,d0
        bne.s   .ct_nvt
        tst.w   CU_YCP(a5)
        beq.s   .ct_ret
        subq.w  #1,CU_YCP(a5)
        rts
.ct_nvt:
        cmp.b   #12,d0
        beq     .ct_ff
        cmp.b   #13,d0
        bne.s   .ct_ncr
        clr.w   CU_XCP(a5)
        rts
.ct_ncr:
        cmp.b   #$84,d0              ; IND
        beq     cu_lf
        cmp.b   #$85,d0              ; NEL
        bne.s   .ct_nnel
        clr.w   CU_XCP(a5)
        bra     cu_lf
.ct_nnel:
        cmp.b   #$8D,d0              ; RI : ligne précédente, défilement vers le bas en haut de zone
        bne.s   .ct_ret
        tst.w   CU_YCP(a5)
        beq.s   .ct_ri
        subq.w  #1,CU_YCP(a5)
        rts
.ct_ri:
        moveq   #-GFX_FONTH,d1
        move.w  CU_YRORIGIN(a5),d3
        bra     cu_scroll
.ct_esc:                             ; après ESC
        clr.b   CU_ESC(a5)
        cmp.b   #'[',d0
        beq.s   .ct_csistart
        cmp.b   #'c',d0              ; RIS : réinitialisation (stylos, curseur, effacement)
        bne     .ct_ret
        move.b  #CU_DEFFG,CU_FGPEN(a5)
        clr.b   CU_BGPEN(a5)
        clr.b   CU_INV(a5)
        clr.b   CU_CUROFF(a5)
        bsr     cu_setpens
.ct_ff:
        clr.l   CU_XCP(a5)           ; XCP = YCP = 0
        move.w  CU_XRORIGIN(a5),d0
        move.w  CU_YRORIGIN(a5),d1
        move.w  CU_XREXTANT(a5),d2
        move.w  CU_YREXTANT(a5),d3
        bra     cu_fill
.ct_csistart:
        move.b  #2,CU_ESC(a5)
        clr.l   CU_PAR0(a5)          ; PAR0 = PAR1 = 0
        clr.b   CU_NPAR(a5)
        clr.b   CU_PSEEN(a5)
        clr.b   CU_INTER(a5)
        rts
.ct_csi:                             ; dans un CSI : paramètres, intermédiaires, octet final
        cmp.b   #'0',d0
        blo.s   .ct_nd
        cmp.b   #'9',d0
        bhi.s   .ct_nd
        and.w   #$000F,d0
        lea     CU_PAR0(a5),a0
        tst.b   CU_NPAR(a5)
        beq.s   .ct_p0
        lea     CU_PAR1(a5),a0
        bra.s   .ct_pacc
.ct_p0:
        st      CU_PSEEN(a5)
.ct_pacc:
        move.w  (a0),d1
        mulu    #10,d1
        add.w   d0,d1
        cmp.w   #999,d1
        bls.s   .ct_pst
        move.w  #999,d1
.ct_pst:
        move.w  d1,(a0)
        rts
.ct_nd:
        cmp.b   #';',d0
        bne.s   .ct_nsc
        move.b  #1,CU_NPAR(a5)
        rts
.ct_nsc:
        cmp.b   #$40,d0
        bhs.s   .ct_final
        cmp.b   #$20,d0
        blo.s   .ct_abort
        move.b  d0,CU_INTER(a5)      ; intermédiaire ($20..$3F hors chiffres et ';')
        rts
.ct_abort:
        clr.b   CU_ESC(a5)           ; octet de contrôle dans un CSI : séquence abandonnée
        rts
.ct_final:
        clr.b   CU_ESC(a5)
        move.w  CU_PAR0(a5),d6       ; d6 = n (paramètre 0, au moins 1 pour les déplacements)
        bne.s   .ct_n1
        moveq   #1,d6
.ct_n1:
        cmp.b   #'A',d0
        bne.s   .ct_nA
        move.w  CU_YCP(a5),d1
        sub.w   d6,d1
        bra     .ct_sety
.ct_nA:
        cmp.b   #'B',d0
        bne.s   .ct_nB
        move.w  CU_YCP(a5),d1
        add.w   d6,d1
        bra     .ct_sety
.ct_nB:
        cmp.b   #'C',d0
        bne.s   .ct_nC
        move.w  CU_XCP(a5),d1
        add.w   d6,d1
        bra     .ct_setx
.ct_nC:
        cmp.b   #'D',d0
        bne.s   .ct_nD
        move.w  CU_XCP(a5),d1
        sub.w   d6,d1
        bra     .ct_setx
.ct_nD:
        cmp.b   #'E',d0
        bne.s   .ct_nE
        clr.w   CU_XCP(a5)
        move.w  CU_YCP(a5),d1
        add.w   d6,d1
        bra     .ct_sety
.ct_nE:
        cmp.b   #'F',d0
        bne.s   .ct_nF
        clr.w   CU_XCP(a5)
        move.w  CU_YCP(a5),d1
        sub.w   d6,d1
        bra     .ct_sety
.ct_nF:
        cmp.b   #'H',d0
        beq.s   .ct_pos
        cmp.b   #'f',d0
        bne.s   .ct_nH
.ct_pos:
        move.w  CU_PAR1(a5),d1       ; colonne (1 par défaut)
        bne.s   .ct_pc
        moveq   #1,d1
.ct_pc:
        subq.w  #1,d1
        bsr     .ct_setx
        move.w  d6,d1
        subq.w  #1,d1
        bra     .ct_sety
.ct_nH:
        cmp.b   #'J',d0
        bne.s   .ct_nJ
        bsr     cu_eol
        move.w  CU_YCP(a5),d1        ; puis les lignes suivantes
        cmp.w   CU_YMAX(a5),d1
        bge     .ct_ret2
        addq.w  #1,d1
        lsl.w   #3,d1
        add.w   CU_YRORIGIN(a5),d1
        move.w  CU_XRORIGIN(a5),d0
        move.w  CU_XREXTANT(a5),d2
        move.w  CU_YREXTANT(a5),d3
        bra     cu_fill
.ct_nJ:
        cmp.b   #'K',d0
        beq     cu_eol
        cmp.b   #'P',d0
        beq     cu_eol
        cmp.b   #'L',d0
        beq.s   .ct_lines
        cmp.b   #'M',d0
        bne.s   .ct_nM
.ct_lines:                           ; L : insère n lignes (vers le bas) ; M : en supprime n (vers le haut)
        move.w  d6,d1
        lsl.w   #3,d1
        cmp.b   #'L',d0
        bne.s   .ct_lm
        neg.w   d1
.ct_lm:
        move.w  CU_YCP(a5),d3
        lsl.w   #3,d3
        add.w   CU_YRORIGIN(a5),d3
        bra     cu_scroll
.ct_nM:
        cmp.b   #'m',d0
        bne.s   .ct_nm
        move.w  CU_PAR0(a5),d0
        bsr.s   .ct_sgr
        tst.b   CU_NPAR(a5)
        beq.s   .ct_sgrdone
        move.w  CU_PAR1(a5),d0
        bsr.s   .ct_sgr
.ct_sgrdone:
        bra     cu_setpens
.ct_nm:
        cmp.b   #'p',d0
        bne.s   .ct_ret2
        cmp.b   #' ',CU_INTER(a5)
        bne.s   .ct_ret2
        clr.b   CU_CUROFF(a5)        ; CSI SPACE p : visible ; CSI 0 SPACE p : masqué
        tst.b   CU_PSEEN(a5)
        beq.s   .ct_ret2
        tst.w   CU_PAR0(a5)
        bne.s   .ct_ret2
        st      CU_CUROFF(a5)
.ct_ret2:
        rts
; .ct_sgr(d0.w = paramètre SGR) : 0 défaut, 7 inverse, 30..37 / 39 premier plan, 40..47 / 49 fond.
.ct_sgr:
        tst.w   d0
        bne.s   .sg_n0
        move.b  #CU_DEFFG,CU_FGPEN(a5)
        clr.b   CU_BGPEN(a5)
        clr.b   CU_INV(a5)
        rts
.sg_n0:
        cmp.w   #7,d0
        bne.s   .sg_n7
        st      CU_INV(a5)
        rts
.sg_n7:
        cmp.w   #39,d0
        bne.s   .sg_n39
        move.b  #CU_DEFFG,CU_FGPEN(a5)
        rts
.sg_n39:
        cmp.w   #49,d0
        bne.s   .sg_n49
        clr.b   CU_BGPEN(a5)
        rts
.sg_n49:
        sub.w   #30,d0
        bcs.s   .sg_ret
        cmp.w   #7,d0
        bhi.s   .sg_bg
        move.b  d0,CU_FGPEN(a5)
        rts
.sg_bg:
        sub.w   #10,d0
        bcs.s   .sg_ret
        cmp.w   #7,d0
        bhi.s   .sg_ret
        move.b  d0,CU_BGPEN(a5)
.sg_ret:
        rts
; .ct_setx / .ct_sety(d1.w = position voulue) : bornée à la zone de texte.
.ct_setx:
        tst.w   d1
        bpl.s   .sx_lo
        moveq   #0,d1
.sx_lo:
        cmp.w   CU_XMAX(a5),d1
        ble.s   .sx_hi
        move.w  CU_XMAX(a5),d1
.sx_hi:
        move.w  d1,CU_XCP(a5)
        rts
.ct_sety:
        tst.w   d1
        bpl.s   .sy_lo
        moveq   #0,d1
.sy_lo:
        cmp.w   CU_YMAX(a5),d1
        ble.s   .sy_hi
        move.w  CU_YMAX(a5),d1
.sy_hi:
        move.w  d1,CU_YCP(a5)
        rts
console_end:
