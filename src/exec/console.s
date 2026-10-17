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

                xref    font8x8          ; graphics/font8x8.s (glyphes 8x8, ASCII 0x20..0x7F)

CMD_WRITE    EQU 3                ; io_Command standard (io.i : READ=2, WRITE=3)
IO_DATA2     EQU 40               ; IOStdReq io_Data (local : console.s n'inclut pas disk.i)
IO_LEN2      EQU 36               ; IOStdReq io_Length
IOERR_NOCMD  EQU -3               ; commande io non reconnue

; --- ROMTag console.device (scanné par build_reslist) ---
                EVEN
console_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    console_romtag       ; RT_MATCHTAG = self
        dc.l    console_end          ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT,34,NT_DEVICE,20  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI (20 : place roadmap console)
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

console_open:
        addq.w  #1,LIB_OPENCNT(a6)
        rts
console_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
console_expunge:
        moveq   #0,d0
        rts
console_null:
        moveq   #0,d0
        rts
console_abortio:
        moveq   #0,d0
        rts

; console_beginio(device a6, ioreq a1) : CMD_WRITE -> rend le flux. Synchrone. a6 ressort = base device.
console_beginio:
        movem.l d4/a2-a4,-(sp)
        move.l  a6,a2                ; a2 = base device (= état console)
        move.l  a1,a3                ; a3 = ioreq
        clr.b   IO_ERROR(a3)
        move.w  IO_COMMAND(a3),d0
        cmp.w   #CMD_WRITE,d0
        bne.s   .bi_nocmd
        move.l  IO_DATA2(a3),a4      ; a4 = buffer
        move.l  IO_LEN2(a3),d4       ; d4 = longueur
.bi_wl:
        tst.l   d4
        beq.s   .bi_done
        move.b  (a4)+,d0
        bsr.s   con_putglyph         ; rend un octet (a2 = base ; clobbe d0/d1/a0/a1)
        subq.l  #1,d4
        bra.s   .bi_wl
.bi_nocmd:
        move.b  #IOERR_NOCMD,IO_ERROR(a3)
.bi_done:
        move.l  a2,a6                ; a6 = base device (convention BeginIO)
        movem.l (sp)+,d4/a2-a4
        rts

; con_putglyph(d0.b = caractère, a2 = base console) : rend un octet. Clobbe d0/d1/a0/a1 ; préserve le reste
; (sauve d2/d3 pour le blit). CR -> colonne 0 ; LF / wrap -> ligne suivante (+8, clampée) ; imprimable -> blit.
con_putglyph:
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
        beq.s   .cpg_advance         ; pas de bitplane (alloc échouée) -> n'écrit pas, avance quand même
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

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Pose le nom, alloue le bitplane, init l'état.
console_initfunc:
        movem.l d2/a2,-(sp)
        move.l  d0,a2                ; a2 = base device
        lea     console_name(pc),a0
        move.l  a0,LN_NAME(a2)
        move.w  #CON_BYTEW,CONB_BWIDTH(a2)
        move.w  #CON_PXH,CONB_PXROWS(a2)
        clr.w   CONB_CURX(a2)
        clr.w   CONB_CURY(a2)
        move.l  #CON_BMSIZE,d0       ; bitplane : chip RAM, effacé (fond 0)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,CONB_BITMAP(a2)   ; 0 si l'alloc échoue -> CMD_WRITE blitterait à l'adresse 0 : garde ci-dessous
        move.l  a2,d0                ; retourne la base
        movem.l (sp)+,d2/a2
        rts

        EVEN
console_end:
