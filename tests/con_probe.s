; tests/con_probe.s — sonde boîte noire de console.device / keymap.resource 1.3
; (ASSET DE TEST, PAS du code ROM ; piste ANALYSE, docs/analysis/console-keymap-v34.md).
; Code AUTEUR : n'utilise que l'ABI publique (exec/intuition/graphics .fd, devices/console.h,
; devices/conunit.h, devices/keymap.h, devices/inputevent.h du NDK 1.3).
;
; Assemblé en binaire brut (vasm -Fbin -m68000), posé à l'offset 12 d'un ADF par tests/con_probe.sh.
; Étage 1 (bootblock) : relit les 32 premiers Ko de la disquette en chip RAM et y saute.
; Étage 2 : ouvre une fenêtre type CON: sur l'écran Workbench, y ouvre console.device, puis enchaîne
; des écritures (CMD_WRITE) ; après chacune journalise sur le port série :
;   T <nom>                       début d'un test
;   U xcp ycp xccp yccp xmax ymax xrs yrs xro yro xre yre modes[3] raw[3] fg bg drmd style mask
;   R nn |<texte reconnu>|<couleurs>|   ligne nn de la zone de texte (lecture du BitMap de l'écran,
;                                  reconnaissance des glyphes de la police de la console ;
;                                  « ? » = cellule non reconnue ; couleurs : chiffre hexa = masque des
;                                  couleurs présentes (bit n = couleur n) ; lettre g..v = idem mais
;                                  glyphe reconnu en INVERSE)
;   I <n> <octets hexa>           réponse lue par CMD_READ
;   K ...                         résultats RawKeyConvert / commandes de keymap
; « @S x » : capture d'écran par le harnais ; « @K » : le harnais tape au clavier.
; Dernière action VOLONTAIREMENT fatale : CMD_READ de longueur 0 (bogue V34, Guru attendu) ; « IDLE »
; n'est donc jamais atteint et le harnais s'arrête sur sa durée maximale.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
LOADSZ   EQU 32768
LOGSZ    EQU 65536

; LVO exec
_AllocMem   EQU -198
_FindTask   EQU -294
_AllocSignal EQU -330
_OpenLibrary EQU -552
_OpenDevice EQU -444
_CloseDevice EQU -450
_DoIO       EQU -456
_SendIO     EQU -462
_CheckIO    EQU -468
_WaitIO     EQU -474
_AbortIO    EQU -480
_Forbid     EQU -132
_Permit     EQU -138
; intuition / graphics
_OpenWindow EQU -204
_SizeWindow EQU -288
_WaitTOF    EQU -270

; variables (relatives à A5)
v_ib     EQU 0
v_gfx    EQU 4
v_win    EQU 8
v_unit   EQU 12
v_cdev   EQU 16
v_lptr   EQU 20
v_lbuf   EQU 24
v_glyph  EQU 28
v_port   EQU 40          ; MsgPort (34)
v_wio    EQU 76          ; IOStdReq écriture console (48)
v_rio    EQU 124         ; IOStdReq lecture console (48)
v_iio    EQU 172         ; IOStdReq input.device (48)
v_kio    EQU 220         ; IOStdReq console unité -1 (48)
v_ev     EQU 268         ; InputEvent (24)
v_ev2    EQU 292         ; InputEvent (24)
v_rbuf   EQU 316         ; tampon de lecture (128)
v_km     EQU 444         ; KeyMap (32)
v_km2    EQU 476         ; KeyMap (32)
v_tmp    EQU 508         ; 64 octets
v_xio    EQU 572         ; IOStdReq console 2e unité (48)
v_mytab  EQU 620         ; table LoKeyMap modifiée (256)
v_size   EQU 880

start:
; ---------------------------------------------------------------- étage 1 (bootblock)
        movea.l 4.w,a6
        movea.l a1,a2
        move.l  #LOADSZ,d0
        move.l  #$10003,d1
        jsr     _AllocMem(a6)
        tst.l   d0
        beq.s   *
        movea.l d0,a3
        movea.l a2,a1
        move.w  #2,28(a1)           ; CMD_READ
        move.l  a3,40(a1)
        move.l  #LOADSZ,36(a1)
        clr.l   44(a1)
        jsr     _DoIO(a6)
        movea.l a2,a1
        move.w  #9,28(a1)           ; TD_MOTOR off
        clr.l   36(a1)
        jsr     _DoIO(a6)
        lea     12(a3),a0
        jmp     stage2-start(a0)

; ---------------------------------------------------------------- étage 2
stage2:
        lea     vars(pc),a5
        movea.l 4.w,a6
        move.l  #LOGSZ,d0
        move.l  #$10001,d1
        jsr     _AllocMem(a6)
        move.l  d0,v_lbuf(a5)
        move.l  d0,v_lptr(a5)
        beq.s   *
        move.l  #224*8,d0
        move.l  #$10001,d1
        jsr     _AllocMem(a6)
        move.l  d0,v_glyph(a5)
        lea     m_hello(pc),a0
        bsr     puts
        lea     intname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,v_ib(a5)
        lea     gfxname(pc),a1
        moveq   #0,d0
        jsr     _OpenLibrary(a6)
        move.l  d0,v_gfx(a5)
        ; port de réponse
        moveq   #-1,d0
        jsr     _AllocSignal(a6)
        lea     v_port(a5),a2
        move.b  #4,8(a2)
        clr.b   14(a2)
        move.b  d0,15(a2)
        suba.l  a1,a1
        jsr     _FindTask(a6)
        move.l  d0,16(a2)
        lea     20(a2),a0
        move.l  a0,8(a0)
        addq.l  #4,a0
        clr.l   (a0)
        move.l  a0,-4(a0)
        lea     v_wio(a5),a1
        bsr     initio
        lea     v_rio(a5),a1
        bsr     initio
        lea     v_iio(a5),a1
        bsr     initio
        lea     v_kio(a5),a1
        bsr     initio
        lea     v_xio(a5),a1
        bsr     initio
        ; --- OpenDevice : unité -1 (accès aux fonctions)
        lea     m_open(pc),a0
        bsr     puts
        lea     v_kio(a5),a1
        move.l  #$55555555,24(a1)
        lea     conname(pc),a0
        moveq   #-1,d0
        moveq   #0,d1
        jsr     _OpenDevice(a6)
        bsr     hex8s
        lea     v_kio(a5),a1
        move.b  31(a1),d0
        bsr     hex2s
        move.l  24(a1),d0           ; io_Unit
        bsr     hex8s
        move.l  20(a1),d0           ; io_Device
        move.l  d0,v_cdev(a5)
        bsr     hex8s
        movea.l d0,a0
        move.w  32(a0),d0           ; lib_OpenCnt
        bsr     hex4s
        bsr     nl
        ; --- OpenDevice sans fenêtre (io_Data = 0)
        lea     m_open0(pc),a0
        bsr     puts
        lea     v_xio(a5),a1
        clr.l   40(a1)
        lea     conname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        jsr     _OpenDevice(a6)
        bsr     hex8s
        lea     v_xio(a5),a1
        move.b  31(a1),d0
        bsr     hex2s
        move.l  20(a1),d0
        bsr     hex8s
        movea.l v_cdev(a5),a0
        move.w  32(a0),d0
        bsr     hex4s
        bsr     nl
        ; --- fenêtre principale
        movea.l v_ib(a5),a6
        lea     nw1(pc),a0
        lea     s_title(pc),a1
        move.l  a1,26(a0)
        jsr     _OpenWindow(a6)
        move.l  d0,v_win(a5)
        beq     failed
        bsr     dumpwin
        ; --- console sur la fenêtre (unité 0, io_Length = taille)
        movea.l 4.w,a6
        lea     m_open1(pc),a0
        bsr     puts
        lea     v_wio(a5),a1
        move.l  v_win(a5),40(a1)
        move.l  #48,36(a1)
        lea     conname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        jsr     _OpenDevice(a6)
        bsr     hex8s
        lea     v_wio(a5),a1
        move.l  24(a1),d0
        move.l  d0,v_unit(a5)
        bsr     hex8s
        movea.l v_cdev(a5),a0
        move.w  32(a0),d0
        bsr     hex4s
        movea.l v_unit(a5),a0
        move.l  34(a0),d0           ; cu_Window
        bsr     hex8s
        move.l  $114(a0),d0         ; cu_Font
        bsr     hex8s
        bsr     nl
        ; requête de lecture : même unité
        lea     v_rio(a5),a1
        lea     v_wio(a5),a0
        move.l  20(a0),20(a1)
        move.l  24(a0),24(a1)
        ; input.device
        lea     v_iio(a5),a1
        lea     inpname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        jsr     _OpenDevice(a6)
        bsr     buildglyphs
        bsr     dumptabs
        bsr     logcu
        lea     m_shot(pc),a0
        moveq   #'a',d0
        bsr     shot
        bsr     flush
        ; ------------------------------------------------ écritures
        lea     tests(pc),a4
.tl:    move.w  (a4)+,d0
        beq.s   .td
        lea     tests(pc),a0
        adda.w  d0,a0
        move.w  (a4)+,d1
        move.w  (a4)+,d2
        bsr     runtest
        bra.s   .tl
.td:    bsr     flush
        bsr     specials
        bsr     flush
        bsr     rkctests
        bsr     flush
        bsr     kmtests
        bsr     flush
        bsr     cmdtests
        bsr     flush
        bsr     inputtests
        bsr     flush
        bsr     resizetests
        bsr     flush
        lea     nw2(pc),a0
        lea     altl1(pc),a4
        bsr     altwin
        lea     nw3(pc),a0
        lea     altl2(pc),a4
        bsr     altwin
        bsr     flush
        bsr     livekeys
        ; dernier : CMD_READ de longueur 0 (crash attendu si le registre A2 non initialisé est utilisé)
        lea     m_rd0(pc),a0
        bsr     puts
        bsr     flush
        lea     v_rio(a5),a1
        move.w  #2,28(a1)
        clr.l   36(a1)
        move.b  #1,30(a1)
        movea.l #$00000001,a2
        movea.l 20(a1),a6
        jsr     -30(a6)
        lea     m_rd0b(pc),a0
        bsr     puts
        lea     v_rio(a5),a1
        move.b  31(a1),d0
        bsr     hex2s
        bsr     nl
        lea     m_idle(pc),a0
        bsr     puts
        bsr     flush
.idle:  bsr     wtof
        bra.s   .idle

failed: lea     m_fail(pc),a0
        bsr     puts
        bsr     flush
        bra.s   *

initio: move.b  #5,8(a1)            ; NT_MESSAGE
        lea     v_port(a5),a0
        move.l  a0,14(a1)
        move.w  #48,18(a1)
        rts

; ---------------------------------------------------------------- un test d'écriture
; a0 = enregistrement « nom\0 charge\0 »
; d1 = nombre de lignes à vider (0 = aucune), d2 = nombre de colonnes
runtest:
        movem.l d1-d2/a4,-(a7)
        move.l  a0,-(a7)
        lea     m_t(pc),a0
        bsr     puts
        movea.l (a7)+,a0
        bsr     puts                ; nom (a0 avance après le NUL)
        bsr     nl
        bsr     strlen
        bsr     conwrite
        movem.l (a7)+,d1-d2/a4
        bsr     logcu
        bsr     dumptabs
        tst.w   d1
        beq.s   .n
        moveq   #0,d0
        bsr     dumprows
.n:     rts

; écrit a0, longueur d0 (CMD_WRITE, DoIO) ; renvoie io_Actual dans d0
conwrite:
        movem.l a1/a6,-(a7)
        lea     v_wio(a5),a1
        move.w  #3,28(a1)
        move.l  a0,40(a1)
        move.l  d0,36(a1)
        movea.l 4.w,a6
        jsr     _DoIO(a6)
        lea     v_wio(a5),a1
        move.l  32(a1),d0
        movem.l (a7)+,a1/a6
        rts

strlen: moveq   #0,d0
.l:     tst.b   0(a0,d0.l)
        beq.s   .e
        addq.l  #1,d0
        bra.s   .l
.e:     rts

; ---------------------------------------------------------------- journal de l'état ConUnit
logcu:  movem.l d0-d2/a0-a2,-(a7)
        lea     m_u(pc),a0
        bsr     puts
        movea.l v_unit(a5),a2
        lea     cuw(pc),a1
.w:     move.w  (a1)+,d1
        bmi.s   .b
        move.w  0(a2,d1.w),d0
        bsr     hex4s
        bra.s   .w
.b:     move.w  (a1)+,d1
        bmi.s   .e
        move.b  0(a2,d1.w),d0
        bsr     hex2s
        bra.s   .b
.e:     bsr     nl
        movem.l (a7)+,d0-d2/a0-a2
        rts
cuw:    dc.w    $26,$28,$3E,$40,$2A,$2C,$2E,$30,$32,$34,$36,$38,-1
        dc.w    $122,$123,$124,$125,$126,$127,$103,$104,$106,$118,$102,-1

dumpwin:
        movem.l d0-d2/a0-a2,-(a7)
        lea     m_win(pc),a0
        bsr     puts
        movea.l v_win(a5),a2
        move.w  4(a2),d0
        bsr     hex4s
        move.w  6(a2),d0
        bsr     hex4s
        move.w  8(a2),d0
        bsr     hex4s
        move.w  10(a2),d0
        bsr     hex4s
        move.b  $36(a2),d0
        bsr     hex2s
        move.b  $37(a2),d0
        bsr     hex2s
        move.b  $38(a2),d0
        bsr     hex2s
        move.b  $39(a2),d0
        bsr     hex2s
        move.l  $18(a2),d0
        bsr     hex8s
        movea.l $32(a2),a1          ; RPort
        movea.l $34(a1),a0          ; Font
        move.w  $14(a0),d0
        bsr     hex4s
        move.w  $18(a0),d0
        bsr     hex4s
        move.w  $1A(a0),d0
        bsr     hex4s
        bsr     nl
        movem.l (a7)+,d0-d2/a0-a2
        rts

dumptabs:
        movem.l d0-d1/a0-a2,-(a7)
        lea     m_tabs(pc),a0
        bsr     puts
        movea.l v_unit(a5),a2
        lea     $62(a2),a1
        moveq   #11,d1
.l:     move.w  (a1)+,d0
        bsr     hex4s
        dbra    d1,.l
        move.w  $100(a2),d0
        bsr     hex4s
        bsr     nl
        movem.l (a7)+,d0-d1/a0-a2
        rts

; ---------------------------------------------------------------- glyphes de la police de la console
buildglyphs:
        movem.l d0-d7/a0-a4,-(a7)
        movea.l v_unit(a5),a0
        movea.l $114(a0),a3         ; cu_Font
        movea.l v_glyph(a5),a4
        move.w  #$20,d7             ; caractère
.c:     moveq   #0,d6
        move.b  $20(a3),d6          ; tf_LoChar
        moveq   #0,d5
        move.b  $21(a3),d5          ; tf_HiChar
        move.w  d7,d4
        cmp.w   d6,d4
        blt.s   .blank
        cmp.w   d5,d4
        bgt.s   .blank
        sub.w   d6,d4
        movea.l $28(a3),a0          ; tf_CharLoc
        lsl.w   #2,d4
        move.w  0(a0,d4.w),d3       ; décalage en bits
        move.w  2(a0,d4.w),d2       ; largeur
        moveq   #0,d1               ; ligne
.r:     movea.l $22(a3),a1          ; tf_CharData
        move.w  $26(a3),d0          ; tf_Modulo
        mulu    d1,d0
        adda.l  d0,a1
        move.w  d3,d0
        lsr.w   #3,d0
        adda.w  d0,a1
        move.b  (a1)+,d0
        lsl.w   #8,d0
        move.b  (a1),d0
        move.w  d3,d6
        and.w   #7,d6
        lsl.w   d6,d0
        lsr.w   #8,d0
        ; masque de largeur (bits de gauche)
        move.w  #$FF,d6
        lsr.w   d2,d6
        not.b   d6
        and.b   d6,d0
        move.b  d0,(a4)+
        addq.w  #1,d1
        cmp.w   #8,d1
        blt.s   .r
        bra.s   .nx
.blank: moveq   #7,d1
.bl:    clr.b   (a4)+
        dbra    d1,.bl
.nx:    addq.w  #1,d7
        cmp.w   #$100,d7
        blt     .c
        movem.l (a7)+,d0-d7/a0-a4
        rts

; ---------------------------------------------------------------- lecture d'une cellule
; d0 = colonne, d1 = ligne (texte) ; rend d0 = code du glyphe (0 = non reconnu, bit 8 = inverse),
; d1 = masque des couleurs présentes (bit n = couleur n)
cell:   movem.l d2-d7/a0-a4,-(a7)
        movea.l v_unit(a5),a2
        movea.l v_win(a5),a3
        mulu    $2E(a2),d0          ; XRSize
        add.w   $32(a2),d0          ; XROrigin
        add.w   4(a3),d0            ; LeftEdge
        mulu    $30(a2),d1
        add.w   $34(a2),d1
        add.w   6(a3),d1
        movea.l $2E(a3),a0          ; WScreen
        lea     $B8(a0),a0          ; sc_BitMap
        moveq   #0,d2
        move.w  (a0),d2             ; BytesPerRow
        movea.l d2,a3
        mulu    d2,d1
        moveq   #0,d3
        move.w  d0,d3
        lsr.w   #3,d3
        add.l   d3,d1
        and.w   #7,d0
        movea.l 8(a0),a1            ; plan 0
        movea.l 12(a0),a4           ; plan 1
        adda.l  d1,a1
        adda.l  d1,a4
        lea     v_tmp(a5),a0
        moveq   #0,d4               ; couleur 0 présente (OU des bits)
        moveq   #0,d5               ; couleur 1
        moveq   #0,d6               ; couleur 2
        moveq   #0,d7               ; couleur 3
        moveq   #7,d3
.r:     move.b  (a1),d1
        lsl.w   #8,d1
        move.b  1(a1),d1
        lsl.w   d0,d1
        lsr.w   #8,d1               ; p0
        move.b  (a4),d2
        lsl.w   #8,d2
        move.b  1(a4),d2
        lsl.w   d0,d2
        lsr.w   #8,d2               ; p1
        move.b  d1,(a0)
        or.b    d2,(a0)+            ; motif = p0|p1
        movea.w d1,a2
        and.b   d2,d1
        or.b    d1,d7               ; p0&p1
        move.w  a2,d1
        not.b   d2
        and.b   d1,d2
        or.b    d2,d5               ; p0&~p1
        move.b  -1(a0),d2
        not.b   d1
        and.b   d1,d2
        or.b    d2,d6               ; ~p0&p1
        move.b  -1(a0),d2
        not.b   d2
        or.b    d2,d4               ; ~(p0|p1)
        adda.l  a3,a1
        adda.l  a3,a4
        dbra    d3,.r
        moveq   #0,d1
        tst.b   d4
        beq.s   .c1
        bset    #0,d1
.c1:    tst.b   d5
        beq.s   .c2
        bset    #1,d1
.c2:    tst.b   d6
        beq.s   .c3
        bset    #2,d1
.c3:    tst.b   d7
        beq.s   .c4
        bset    #3,d1
.c4:    moveq   #0,d2               ; passe 0 = normal, 1 = inverse
.pass:  move.w  #$20,d0
        movea.l v_glyph(a5),a1
.g:     lea     v_tmp(a5),a0
        moveq   #7,d3
.gc:    move.b  (a0)+,d4
        tst.w   d2
        beq.s   .ni
        not.b   d4
.ni:    cmp.b   (a1)+,d4
        bne.s   .skip
        dbra    d3,.gc
        tst.w   d2
        beq.s   .ok
        bset    #8,d0
        bra.s   .ok
.skip:  adda.w  d3,a1
        addq.w  #1,d0
        cmp.w   #$100,d0
        blt.s   .g
        addq.w  #1,d2
        cmp.w   #2,d2
        blt.s   .pass
        moveq   #0,d0
.ok:    movem.l (a7)+,d2-d7/a0-a4
        rts

; vide d1 lignes (à partir de la ligne d0) sur d2 colonnes
dumprows:
        movem.l d0-d7/a0,-(a7)
        move.w  d0,d5
        move.w  d1,d6
        move.w  d2,d7
.row:   lea     m_r(pc),a0
        bsr     puts
        move.w  d5,d0
        bsr     hex2
        moveq   #' ',d0
        bsr     putc
        moveq   #'|',d0
        bsr     putc
        moveq   #0,d4
.c:     move.w  d4,d0
        move.w  d5,d1
        bsr     cell
        move.w  d0,d3
        and.w   #$FF,d0
        bne.s   .k
        moveq   #'?',d0
.k:     cmp.w   #$7F,d0
        blo.s   .p
        moveq   #'*',d0
.p:     bsr     putc
        addq.w  #1,d4
        cmp.w   d7,d4
        blt.s   .c
        moveq   #'|',d0
        bsr     putc
        moveq   #0,d4
.c2:    move.w  d4,d0
        move.w  d5,d1
        bsr     cell
        move.w  d1,d2
        btst    #8,d0
        bne.s   .inv
        move.w  d2,d0
        bsr     hexdig
        bra.s   .nx
.inv:   move.w  d2,d0
        add.w   #'g',d0
        bsr     putc
.nx:    addq.w  #1,d4
        cmp.w   d7,d4
        blt.s   .c2
        moveq   #'|',d0
        bsr     putc
        bsr     nl
        addq.w  #1,d5
        subq.w  #1,d6
        bne     .row
        movem.l (a7)+,d0-d7/a0
        rts

; ---------------------------------------------------------------- lecture console (CMD_READ) avec délai
; lit ce qui est disponible (attend au plus d7 trames) ; journalise « I n octets »
conread:
        movem.l d0-d7/a0-a1/a6,-(a7)
        movea.l 4.w,a6
        lea     v_rio(a5),a1
        move.w  #2,28(a1)
        lea     v_rbuf(a5),a0
        move.l  a0,40(a1)
        move.l  #120,36(a1)
        clr.l   32(a1)
        jsr     _SendIO(a6)
.w:     lea     v_rio(a5),a1
        jsr     _CheckIO(a6)
        tst.l   d0
        bne.s   .done
        bsr     wtof
        subq.w  #1,d7
        bgt.s   .w
        lea     v_rio(a5),a1
        jsr     _AbortIO(a6)
.done:  lea     v_rio(a5),a1
        jsr     _WaitIO(a6)
        lea     m_i(pc),a0
        bsr     puts
        lea     v_rio(a5),a1
        move.b  31(a1),d0
        bsr     hex2s
        move.l  32(a1),d6
        move.l  d6,d0
        bsr     hex4s
        lea     v_rbuf(a5),a0
        bra.s   .pe
.pl:    move.b  (a0)+,d0
        bsr     hex2s
.pe:    dbra    d6,.pl
        bsr     nl
        movem.l (a7)+,d0-d7/a0-a1/a6
        rts

; ---------------------------------------------------------------- injection d'un événement (IND_WRITEEVENT)
; d0 = classe, d1 = code, d2 = qualificatif, d3 = ie_X/ie_Y (long : prev1 code/qual, prev2 code/qual)
inject: movem.l d0-d3/a0-a1/a6,-(a7)
        lea     v_ev(a5),a0
        clr.l   (a0)
        move.b  d0,4(a0)
        clr.b   5(a0)
        move.w  d1,6(a0)
        move.w  d2,8(a0)
        move.l  d3,10(a0)
        clr.l   14(a0)
        clr.l   18(a0)
        lea     v_iio(a5),a1
        move.w  #11,28(a1)
        move.l  a0,40(a1)
        move.l  #22,36(a1)
        movea.l 4.w,a6
        jsr     _DoIO(a6)
        moveq   #3,d0
.w:     bsr     wtof
        dbra    d0,.w
        movem.l (a7)+,d0-d3/a0-a1/a6
        rts

wtof:   movem.l d0-d1/a0-a1/a6,-(a7)
        movea.l v_gfx(a5),a6
        jsr     _WaitTOF(a6)
        movem.l (a7)+,d0-d1/a0-a1/a6
        rts

; ---------------------------------------------------------------- tests spéciaux d'écriture
specials:
        ; io_Length = -1 (chaîne terminée par NUL)
        lea     m_t(pc),a0
        bsr     puts
        lea     s_len1(pc),a0
        bsr     puts
        bsr     nl
        lea     p_len1(pc),a0
        moveq   #-1,d0
        bsr     conwrite
        bsr     hex8s
        lea     v_wio(a5),a1
        move.b  31(a1),d0
        bsr     hex2s
        bsr     nl
        bsr     logcu
        ; io_Length = 0
        lea     p_len1(pc),a0
        moveq   #0,d0
        bsr     conwrite
        bsr     hex8s
        bsr     nl
        ; rapport de position : CSI 6n puis lecture
        lea     m_t(pc),a0
        bsr     puts
        lea     s_dsr(pc),a0
        bsr     puts
        bsr     nl
        lea     p_dsr(pc),a0
        bsr     strlen
        bsr     conwrite
        moveq   #10,d7
        bsr     conread
        lea     p_dsr2(pc),a0       ; CSI 5n, CSI n, CSI 6;6n : rien / un / un ?
        bsr     strlen
        bsr     conwrite
        moveq   #10,d7
        bsr     conread
        ; rapport de fenêtre
        lea     p_wsr(pc),a0
        bsr     strlen
        bsr     conwrite
        moveq   #10,d7
        bsr     conread
        lea     p_wsr2(pc),a0       ; avec paramètre, sans espace, deux espaces
        bsr     strlen
        bsr     conwrite
        moveq   #10,d7
        bsr     conread
        ; lecture vide : expiration
        moveq   #5,d7
        bsr     conread
        ; tampon d'entrée : 40 rapports (> 255 octets ?) puis lectures
        lea     m_t(pc),a0
        bsr     puts
        lea     s_ovf(pc),a0
        bsr     puts
        bsr     nl
        moveq   #59,d6
.ov:    lea     p_dsr(pc),a0
        bsr     strlen
        bsr     conwrite
        dbra    d6,.ov
        moveq   #5,d6
.ovr:   moveq   #5,d7
        bsr     conread
        dbra    d6,.ovr
        ; CMD_CLEAR vide-t-il le tampon ?
        lea     p_dsr(pc),a0
        bsr     strlen
        bsr     conwrite
        lea     v_wio(a5),a1
        move.w  #5,28(a1)
        movea.l 4.w,a6
        jsr     _DoIO(a6)
        lea     m_clr(pc),a0
        bsr     puts
        lea     v_wio(a5),a1
        move.b  30(a1),d0
        bsr     hex2s
        move.b  31(a1),d0
        bsr     hex2s
        bsr     nl
        moveq   #5,d7
        bsr     conread
        bsr     flush
        rts

; ---------------------------------------------------------------- RawKeyConvert
; d0 = code, d1 = qualificatif, d3 = prev (ie_X/ie_Y), d2 = longueur du tampon ; journalise « n:octets »
rkc1:   movem.l d0-d7/a0-a3/a6,-(a7)
        lea     v_ev(a5),a0
        clr.l   (a0)
        move.b  #1,4(a0)
        clr.b   5(a0)
        move.w  d0,6(a0)
        move.w  d1,8(a0)
        move.l  d3,10(a0)
        clr.l   14(a0)
        clr.l   18(a0)
        lea     v_rbuf(a5),a1
        move.l  d2,d1
        suba.l  a2,a2
        movea.l v_cdev(a5),a6
        jsr     -48(a6)
        move.l  d0,d6
        bsr     hex4
        moveq   #':',d0
        bsr     putc
        tst.w   d6
        ble.s   .e
        lea     v_rbuf(a5),a0
        subq.w  #1,d6
.l:     move.b  (a0)+,d0
        bsr     hex2
        dbra    d6,.l
.e:     moveq   #' ',d0
        bsr     putc
        movem.l (a7)+,d0-d7/a0-a3/a6
        rts

rkctests:
        lea     m_rk(pc),a0
        bsr     puts
        bsr     nl
        ; table complète : codes 0..$77, qualificatifs de la liste quals
        moveq   #0,d5
.code:  lea     m_k(pc),a0
        bsr     puts
        move.w  d5,d0
        bsr     hex2s
        lea     quals(pc),a3
.q:     move.w  (a3)+,d1
        bmi.s   .qe
        move.w  d5,d0
        moveq   #0,d3
        moveq   #64,d2
        bsr     rkc1
        bra.s   .q
.qe:    bsr     nl
        addq.w  #1,d5
        cmp.w   #$78,d5
        blt.s   .code
        bsr     flush
        ; relâchements, répétition, longueur courte, combinaisons mortes
        lea     rkx(pc),a3
.x:     move.w  (a3)+,d0
        cmp.w   #-1,d0
        beq.s   .xe
        move.w  (a3)+,d1
        move.l  (a3)+,d3
        move.w  (a3)+,d2
        ext.l   d2
        lea     m_kx(pc),a0
        bsr     puts
        bsr     hex4s
        move.w  d1,d0
        bsr     hex4s
        move.l  d3,d0
        bsr     hex8s
        move.w  d2,d0
        bsr     hex4s
        move.w  -10(a3),d0
        bsr     rkc1
        bsr     nl
        bra.s   .x
.xe:    ; touches mortes : pour chaque morte (f g h j k) x qualif. (alt, alt+maj), chaque modifiable
        lea     deadk(pc),a3
.d1:    move.w  (a3)+,d4            ; code de la morte
        bmi.s   .de
        move.w  (a3)+,d6            ; qualif de la morte
        lea     m_kd(pc),a0
        bsr     puts
        move.w  d4,d0
        bsr     hex2s
        move.w  d6,d0
        bsr     hex4s
        lea     modk(pc),a2
.d2:    move.w  (a2)+,d0
        bmi.s   .d3
        move.w  (a2)+,d1
        move.l  d4,d3
        lsl.w   #8,d3
        move.b  d6,d3               ; prev1 = code, qualif (octet bas)
        swap    d3
        clr.w   d3
        moveq   #64,d2
        bsr     rkc1
        bra.s   .d2
.d3:    bsr     nl
        bra.s   .d1
.de:    ; double morte (prev1 et prev2 mortes)
        lea     m_kd2(pc),a0
        bsr     puts
        move.w  #$12,d0
        moveq   #0,d1
        move.l  #$23102410,d3       ; prev1 = alt-f, prev2 = alt-g
        moveq   #64,d2
        bsr     rkc1
        move.l  #$00002310,d3       ; prev2 seule
        bsr     rkc1
        move.l  #$23002310,d3       ; prev1 = f sans alt
        bsr     rkc1
        bsr     nl
        ; chaîne de deux événements RAWKEY + un non-RAWKEY
        lea     m_kc(pc),a0
        bsr     puts
        lea     v_ev(a5),a0
        lea     v_ev2(a5),a1
        move.l  a1,(a0)
        move.l  #$01000020,4(a0)    ; classe 1, sous-classe 0, code $20 (a)
        clr.w   8(a0)
        clr.l   10(a0)
        clr.l   14(a0)
        clr.l   18(a0)
        clr.l   (a1)
        move.l  #$01000035,4(a1)    ; b
        move.w  #1,8(a1)            ; maj
        clr.l   10(a1)
        clr.l   14(a1)
        clr.l   18(a1)
        moveq   #64,d1
        bsr     rkchain
        moveq   #1,d1
        bsr     rkchain
        lea     v_ev(a5),a0
        move.b  #2,4(a0)            ; premier = RAWMOUSE
        moveq   #64,d1
        bsr     rkchain
        bsr     nl
        bsr     flush
        rts

rkchain:
        movem.l d0-d7/a0-a3/a6,-(a7)
        lea     v_ev(a5),a0
        lea     v_rbuf(a5),a1
        suba.l  a2,a2
        movea.l v_cdev(a5),a6
        jsr     -48(a6)
        move.l  d0,d6
        bsr     hex8
        moveq   #':',d0
        bsr     putc
        tst.w   d6
        ble.s   .e
        cmp.w   #64,d6
        bgt.s   .e
        lea     v_rbuf(a5),a0
        subq.w  #1,d6
.l:     move.b  (a0)+,d0
        bsr     hex2
        dbra    d6,.l
.e:     moveq   #' ',d0
        bsr     putc
        movem.l (a7)+,d0-d7/a0-a3/a6
        rts

; ---------------------------------------------------------------- commandes de keymap
kmdoio: ; a1 = io ; d0 = commande, d1 = longueur, a0 = données ; journalise err, actual
        movem.l d0-d1/a0-a1/a6,-(a7)
        move.w  d0,28(a1)
        move.l  d1,36(a1)
        move.l  a0,40(a1)
        move.l  #$AAAAAAAA,32(a1)
        movea.l 4.w,a6
        jsr     _DoIO(a6)
        movem.l (a7),d0-d1/a0-a1
        lea     m_kio(pc),a0
        bsr     puts
        bsr     hex4s
        move.b  31(a1),d0
        bsr     hex2s
        move.l  32(a1),d0
        bsr     hex8s
        movem.l (a7)+,d0-d1/a0-a1/a6
        rts

dumpkm: ; a0 = KeyMap (8 pointeurs)
        movem.l d0-d1/a0,-(a7)
        moveq   #7,d1
.l:     move.l  (a0)+,d0
        bsr     hex8s
        dbra    d1,.l
        bsr     nl
        movem.l (a7)+,d0-d1/a0
        rts

kmtests:
        lea     m_km(pc),a0
        bsr     puts
        bsr     nl
        ; keymap.resource
        movea.l 4.w,a6
        lea     kmrname(pc),a1
        jsr     -498(a6)            ; OpenResource
        move.l  d0,d7
        lea     m_kmr(pc),a0
        bsr     puts
        move.l  d7,d0
        bsr     hex8s
        movea.l d7,a2
        move.b  8(a2),d0
        bsr     hex2s
        move.l  14(a2),d0           ; lh_Head
        bsr     hex8s
        movea.l d0,a3
        move.l  (a3),d0             ; succ du premier noeud
        bsr     hex8s
        movea.l 10(a3),a0           ; nom
        bsr     puts
        bsr     nl
        lea     14(a3),a0
        bsr     dumpkm
        ; ASK sur l'unité, longueur 32 puis 31 puis 33
        lea     v_wio(a5),a1
        lea     v_km(a5),a0
        moveq   #9,d0
        moveq   #32,d1
        bsr     kmdoio
        bsr     dumpkm
        moveq   #31,d1
        bsr     kmdoio
        bsr     nl
        moveq   #33,d1
        bsr     kmdoio
        bsr     nl
        ; ASKDEFAULT
        moveq   #11,d0
        moveq   #32,d1
        lea     v_km2(a5),a0
        bsr     kmdoio
        bsr     dumpkm
        ; keymap modifiée : LoKeyMap copiée, code $20 (a) -> 'z' / 'Z'
        movea.l v_km2(a5),a0        ; (inutile : on lit le pointeur ci-dessous)
        lea     v_km2(a5),a0
        movea.l 4(a0),a1            ; LoKeyMap
        lea     v_mytab(a5),a2
        moveq   #63,d1
.cp:    move.l  (a1)+,(a2)+
        dbra    d1,.cp
        lea     v_mytab(a5),a2
        move.l  #$5A7A5A7A,$21*4(a2) ; s -> z
        lea     v_km(a5),a0
        lea     v_km2(a5),a1
        moveq   #7,d1
.c2:    move.l  (a1)+,(a0)+
        dbra    d1,.c2
        lea     v_km(a5),a0
        lea     v_mytab(a5),a1
        move.l  a1,4(a0)
        ; SETDEFAULT puis RawKeyConvert(NULL) sur s, puis unité existante (ASK), puis nouvelle unité
        lea     v_wio(a5),a1
        moveq   #12,d0
        moveq   #32,d1
        bsr     kmdoio
        bsr     nl
        lea     m_kx(pc),a0
        bsr     puts
        moveq   #$21,d0
        moveq   #0,d1
        moveq   #0,d3
        moveq   #64,d2
        bsr     rkc1
        bsr     nl
        lea     v_wio(a5),a1
        lea     v_tmp(a5),a0
        moveq   #9,d0
        moveq   #32,d1
        bsr     kmdoio
        bsr     dumpkm
        ; nouvelle unité sur la même fenêtre
        lea     v_xio(a5),a1
        move.l  v_win(a5),40(a1)
        lea     conname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        movea.l 4.w,a6
        jsr     _OpenDevice(a6)
        lea     m_open2(pc),a0
        bsr     puts
        bsr     hex8s
        lea     v_xio(a5),a1
        move.l  24(a1),d0
        bsr     hex8s
        bsr     nl
        lea     v_xio(a5),a1
        lea     v_tmp(a5),a0
        moveq   #9,d0
        moveq   #32,d1
        bsr     kmdoio
        bsr     dumpkm
        lea     v_xio(a5),a1
        movea.l 4.w,a6
        jsr     _CloseDevice(a6)
        ; SETKEYMAP sur l'unité principale, puis restauration du défaut
        lea     v_wio(a5),a1
        lea     v_km(a5),a0
        moveq   #10,d0
        moveq   #32,d1
        bsr     kmdoio
        bsr     nl
        lea     v_km2(a5),a0
        moveq   #12,d0
        bsr     kmdoio
        bsr     nl
        lea     m_kx(pc),a0
        bsr     puts
        moveq   #$21,d0
        moveq   #0,d1
        moveq   #0,d3
        moveq   #64,d2
        bsr     rkc1
        bsr     nl
        bsr     flush
        rts

; ---------------------------------------------------------------- commandes diverses
cmdtests:
        lea     m_cmd(pc),a0
        bsr     puts
        bsr     nl
        lea     cmdl(pc),a3
.l:     move.w  (a3)+,d0
        bmi.w   .e
        lea     v_xio(a5),a1        ; requête jetable sur la même unité
        lea     v_wio(a5),a0
        move.l  20(a0),20(a1)
        move.l  24(a0),24(a1)
        move.w  d0,28(a1)
        clr.l   36(a1)
        lea     v_rbuf(a5),a0
        move.l  a0,40(a1)
        move.b  #1,30(a1)           ; IOF_QUICK
        move.b  #$77,31(a1)
        move.l  #$AAAAAAAA,32(a1)
        movea.l 20(a1),a6
        jsr     -30(a6)             ; BeginIO
        lea     m_kio(pc),a0
        bsr     puts
        lea     v_xio(a5),a1
        move.w  28(a1),d0
        bsr     hex4s
        move.b  30(a1),d0
        bsr     hex2s
        move.b  31(a1),d0
        bsr     hex2s
        move.l  32(a1),d0
        bsr     hex8s
        move.b  8(a1),d0            ; ln_Type (7 = NT_REPLYMSG si répondu)
        bsr     hex2s
        bsr     nl
        ; si la requête est encore en file (READ), l'annuler
        lea     v_xio(a5),a1
        btst    #0,30(a1)
        bne.w   .l
        movea.l 4.w,a6
        jsr     _CheckIO(a6)
        tst.l   d0
        bne.s   .w
        lea     v_xio(a5),a1
        jsr     _AbortIO(a6)
.w:     lea     v_xio(a5),a1
        jsr     _WaitIO(a6)
        bra.w   .l
.e:     ; CMD_CLEAR et CMD_UPDATE envoyés SANS IOF_QUICK : sont-ils répondus ?
        lea     cmdnq(pc),a3
.l2:    move.w  (a3)+,d0
        bmi.s   .e2
        lea     v_xio(a5),a1
        move.w  d0,28(a1)
        clr.l   36(a1)
        clr.b   30(a1)
        move.b  #$77,31(a1)
        move.b  #5,8(a1)
        movea.l 20(a1),a6
        jsr     -30(a6)
        moveq   #10,d7
.ww:    bsr     wtof
        dbra    d7,.ww
        lea     m_kio(pc),a0
        bsr     puts
        lea     v_xio(a5),a1
        move.w  28(a1),d0
        bsr     hex4s
        move.b  30(a1),d0
        bsr     hex2s
        move.b  31(a1),d0
        bsr     hex2s
        move.b  8(a1),d0
        bsr     hex2s
        bsr     nl
        cmp.b   #7,8(a1)
        bne.s   .l2
        movea.l 4.w,a6              ; retirer la réponse du port
        lea     v_xio(a5),a1
        jsr     _WaitIO(a6)
        bra.s   .l2
.e2:    ; CMD_STOP puis lecture d'un rapport, START
        lea     m_stop(pc),a0
        bsr     puts
        bsr     nl
        lea     v_xio(a5),a1
        move.w  #6,28(a1)
        movea.l 4.w,a6
        jsr     _DoIO(a6)
        lea     p_dsr(pc),a0
        bsr     strlen
        bsr     conwrite
        moveq   #10,d7
        bsr     conread
        lea     v_xio(a5),a1
        move.w  #7,28(a1)
        movea.l 4.w,a6
        jsr     _DoIO(a6)
        moveq   #10,d7
        bsr     conread
        bsr     flush
        rts

; ---------------------------------------------------------------- entrée clavier par input.device
; chaque élément : classe, code, qualif, prev (long) ; puis lecture
inputtests:
        lea     m_inp(pc),a0
        bsr     puts
        bsr     nl
        ; l'unité active a-t-elle survécu à l'ouverture/fermeture d'une 2e unité sur la fenêtre ?
        lea     m_act(pc),a0
        bsr     puts
        movea.l v_cdev(a5),a0
        move.l  $4A(a0),d0
        bsr     hex8s
        move.l  $4E(a0),d0
        bsr     hex8s
        move.l  v_unit(a5),d0
        bsr     hex8s
        bsr     nl
        moveq   #1,d0
        moveq   #$20,d1
        moveq   #0,d2
        moveq   #0,d3
        bsr     inject
        moveq   #1,d0
        move.w  #$A0,d1
        bsr     inject
        moveq   #10,d7
        bsr     conread
        movea.l v_ib(a5),a6
        movea.l v_win(a5),a0
        jsr     -450(a6)            ; ActivateWindow
        moveq   #20,d7
.aw:    bsr     wtof
        dbra    d7,.aw
        lea     m_act(pc),a0
        bsr     puts
        movea.l v_cdev(a5),a0
        move.l  $4A(a0),d0
        bsr     hex8s
        move.l  $4E(a0),d0
        bsr     hex8s
        bsr     nl
        moveq   #1,d0
        moveq   #$20,d1
        moveq   #0,d2
        moveq   #0,d3
        bsr     inject
        moveq   #1,d0
        move.w  #$A0,d1
        bsr     inject
        moveq   #10,d7
        bsr     conread
        movea.l v_cdev(a5),a0       ; à défaut : forcer l'unité active (lecture/écriture privée, sonde seulement)
        tst.l   $4A(a0)
        bne.s   .act
        move.l  v_unit(a5),$4A(a0)
        lea     m_force(pc),a0
        bsr     puts
.act:
        lea     inl(pc),a3
.l:     move.w  (a3)+,d0
        bmi.s   .e
        cmp.w   #$7FFF,d0           ; écriture console intercalée
        bne.s   .ev
        move.w  (a3)+,d0
        lea     tests(pc),a0
        adda.w  d0,a0
        moveq   #0,d1
        bsr     runtest
        bra.s   .l
.ev:    cmp.w   #$7FFE,d0           ; lecture
        bne.s   .in
        moveq   #10,d7
        bsr     conread
        bra.s   .l
.in:    move.w  (a3)+,d1
        move.w  (a3)+,d2
        move.l  (a3)+,d3
        bsr     inject
        bra.s   .l
.e:     bsr     flush
        rts

; ---------------------------------------------------------------- redimensionnement
resizetests:
        lea     m_t(pc),a0
        bsr     puts
        lea     s_rsz(pc),a0
        bsr     puts
        bsr     nl
        lea     p_fill(pc),a0
        bsr     strlen
        bsr     conwrite
        bsr     logcu
        movea.l v_ib(a5),a6
        movea.l v_win(a5),a0
        move.l  #-200,d0
        moveq   #-64,d1
        jsr     _SizeWindow(a6)
        moveq   #50,d7
.w1:    bsr     wtof
        dbra    d7,.w1
        bsr     dumpwin
        bsr     logcu
        lea     p_none(pc),a0
        bsr     strlen
        bsr     conwrite
        bsr     logcu
        lea     p_wsr(pc),a0
        bsr     strlen
        bsr     conwrite
        moveq   #10,d7
        bsr     conread
        moveq   #12,d1
        moveq   #60,d2
        moveq   #0,d0
        bsr     dumprows
        lea     m_shot(pc),a0
        moveq   #'r',d0
        bsr     shot
        ; agrandissement
        movea.l v_ib(a5),a6
        movea.l v_win(a5),a0
        move.l  #200,d0
        moveq   #64,d1
        jsr     _SizeWindow(a6)
        moveq   #50,d7
.w2:    bsr     wtof
        dbra    d7,.w2
        lea     p_none(pc),a0
        bsr     strlen
        bsr     conwrite
        bsr     logcu
        lea     m_shot(pc),a0
        moveq   #'s',d0
        bsr     shot
        moveq   #0,d0
        moveq   #23,d1
        moveq   #80,d2
        bsr     dumprows
        bsr     flush
        rts

;
; ---------------------------------------------------------------- autre fenêtre (a0 = NewWindow, a4 = liste d'offsets de tests)
altwin: movem.l d0-d7/a0-a4/a6,-(a7)
        lea     s_title(pc),a1
        move.l  a1,26(a0)
        movea.l v_ib(a5),a6
        jsr     _OpenWindow(a6)
        tst.l   d0
        beq     .x
        move.l  v_win(a5),-(a7)
        move.l  v_unit(a5),-(a7)
        move.l  d0,v_win(a5)
        lea     m_alt(pc),a0
        bsr     puts
        bsr     nl
        bsr     dumpwin
        lea     v_xio(a5),a1
        move.l  d0,40(a1)
        lea     conname(pc),a0
        moveq   #0,d0
        moveq   #0,d1
        movea.l 4.w,a6
        jsr     _OpenDevice(a6)
        lea     v_xio(a5),a1
        move.l  24(a1),v_unit(a5)
        lea     v_wio(a5),a0
        move.l  24(a1),24(a0)
        bsr     logcu
.l:     move.w  (a4)+,d0
        beq.s   .e
        lea     tests(pc),a0
        adda.w  d0,a0
        move.w  (a4)+,d1
        move.w  (a4)+,d2
        bsr     runtest
        bra.s   .l
.e:     lea     m_shot(pc),a0
        moveq   #'w',d0
        bsr     shot
        lea     v_xio(a5),a1
        movea.l 4.w,a6
        jsr     _CloseDevice(a6)
        move.l  (a7)+,v_unit(a5)
        lea     v_wio(a5),a0
        move.l  v_unit(a5),24(a0)
        movea.l v_win(a5),a0
        move.l  (a7)+,v_win(a5)
        movea.l v_ib(a5),a6
        jsr     -72(a6)             ; CloseWindow
.x:     movem.l (a7)+,d0-d7/a0-a4/a6
        rts

; ---------------------------------------------------------------- clavier réel (le harnais tape)
livekeys:
        lea     v_wio(a5),a1        ; keymap de l'unité remise au défaut
        lea     v_km2(a5),a0
        moveq   #10,d0
        moveq   #32,d1
        bsr     kmdoio
        bsr     nl
        lea     p_reset(pc),a0
        bsr     strlen
        bsr     conwrite
        lea     m_k2(pc),a0
        bsr     puts
        bsr     flush
        moveq   #29,d5
.l:     moveq   #100,d7
        bsr     conread
        bsr     flush
        dbra    d5,.l
        rts

shot:   bsr     puts                ; a0 = « @S », d0 = lettre
        bsr     putc
        bsr     nl
        bsr     flush
        moveq   #60,d0
.w:     bsr     wtof
        dbra    d0,.w
        rts

; ---------------------------------------------------------------- sorties
hex8s:  bsr.s   hex8
        bra.s   space
hex4s:  bsr.s   hex4
        bra.s   space
hex2s:  bsr.s   hex2
space:  move.l  d0,-(a7)
        moveq   #' ',d0
        bsr.s   putc
        move.l  (a7)+,d0
        rts
hex8:   movem.l d0-d2,-(a7)
        moveq   #7,d1
        bra.s   hexn
hex4:   movem.l d0-d2,-(a7)
        moveq   #3,d1
        bra.s   hexn
hex2:   movem.l d0-d2,-(a7)
        moveq   #1,d1
hexn:   move.l  d0,d2
        move.w  d1,d0
        addq.w  #1,d0
        lsl.w   #2,d0
        ror.l   d0,d2
.h:     rol.l   #4,d2
        move.l  d2,d0
        bsr.s   hexdig
        dbra    d1,.h
        movem.l (a7)+,d0-d2
        rts
hexdig: move.l  d0,-(a7)
        and.b   #15,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        ble.s   .o
        addq.b  #7,d0
.o:     bsr.s   putc
        move.l  (a7)+,d0
        rts
nl:     move.l  d0,-(a7)
        moveq   #10,d0
        bsr.s   putc
        move.l  (a7)+,d0
        rts
puts:   move.l  d0,-(a7)
.p:     move.b  (a0)+,d0
        beq.s   .e
        bsr.s   putc
        bra.s   .p
.e:     move.l  (a7)+,d0
        rts
putc:   move.l  a0,-(a7)
        movea.l v_lptr(a5),a0
        move.b  d0,(a0)+
        move.l  a0,v_lptr(a5)
        movea.l (a7)+,a0
        rts
flush:  movem.l d0/a0,-(a7)
        movea.l v_lbuf(a5),a0
.f:     cmpa.l  v_lptr(a5),a0
        bhs.s   .e
        move.b  (a0)+,d0
        bsr.s   serc
        bra.s   .f
.e:     move.l  v_lbuf(a5),v_lptr(a5)
        movem.l (a7)+,d0/a0
        rts
serc:   movem.l d0/d2,-(a7)
        move.w  #$4000,d2
.wt:    btst    #13-8,SERDATR
        bne.s   .tx
        dbra    d2,.wt
.tx:    and.w   #$FF,d0
        or.w    #$100,d0
        move.w  d0,SERDAT
        movem.l (a7)+,d0/d2
        rts

; ---------------------------------------------------------------- données
quals:  dc.w    0,1,$10,$11,8,9,$18,$19,4,5,2,$20,$C,$14,-1
; tests supplémentaires RawKeyConvert : code, qualif, prev (long), longueur
rkx:    dc.w    $A0,0
        dc.l    0
        dc.w    64                  ; relâchement de a
        dc.w    $C4,0
        dc.l    0
        dc.w    64                  ; relâchement de Return
        dc.w    $20,$200
        dc.l    0
        dc.w    64                  ; a répétée
        dc.w    $44,$200
        dc.l    0
        dc.w    64                  ; Return répétée (non répétable)
        dc.w    $43,$200
        dc.l    0
        dc.w    64                  ; Enter répétée
        dc.w    $4C,$200
        dc.l    0
        dc.w    64                  ; flèche répétée
        dc.w    $20,0
        dc.l    0
        dc.w    0                   ; longueur 0
        dc.w    $50,0
        dc.l    0
        dc.w    2                   ; F1 (3 octets) dans 2
        dc.w    $50,0
        dc.l    0
        dc.w    3
        dc.w    $5F,0
        dc.l    0
        dc.w    2                   ; Help
        dc.w    $23,$10
        dc.l    0
        dc.w    0                   ; alt-f (morte) longueur 0
        dc.w    $12,0
        dc.l    $23100000
        dc.w    0                   ; e après morte, longueur 0
        dc.w    $60,0
        dc.l    0
        dc.w    64                  ; Maj gauche seule
        dc.w    $63,0
        dc.l    0
        dc.w    64                  ; Ctrl seule
        dc.w    $70,0
        dc.l    0
        dc.w    64
        dc.w    $77,0
        dc.l    0
        dc.w    64
        dc.w    -1
deadk:  dc.w    $23,$10, $24,$10, $25,$10, $26,$10, $27,$10, $23,$11, $25,$20, $23,0, -1
; touches modifiables : code, qualif
modk:   dc.w    $40,0, $40,1, $20,0, $20,1, $12,0, $12,1, $17,0, $17,1, $18,0, $18,1
        dc.w    $16,0, $16,1, $15,0, $15,1, $36,0, $36,1, $20,4, $12,$10, $10,0, -1
; commandes avec IOF_QUICK
cmdl:   dc.w    0,1,4,5,6,7,8,13,14,$7FFF,-1
cmdnq:  dc.w    5,4,-1
; entrée par input.device : classe, code, qualif, prev.l ; $7FFF ofs = écriture ; $7FFE = lecture
inl:    dc.w    $7FFF,r_reset-tests
        dc.w    1,$20,0
        dc.l    0                   ; a
        dc.w    1,$A0,0
        dc.l    0
        dc.w    1,$20,1
        dc.l    0                   ; A
        dc.w    1,$4C,0
        dc.l    0                   ; flèche haut
        dc.w    1,$4C,1
        dc.l    0                   ; maj + haut
        dc.w    1,$50,0
        dc.l    0                   ; F1
        dc.w    1,$50,1
        dc.l    0                   ; maj F1
        dc.w    1,$5F,0
        dc.l    0                   ; Help
        dc.w    1,$42,1
        dc.l    0                   ; maj Tab
        dc.w    1,$45,$10
        dc.l    0                   ; alt Esc
        dc.w    1,$44,8
        dc.l    0                   ; ctrl Return
        dc.w    1,$23,$10
        dc.l    0                   ; alt f (morte)
        dc.w    1,$12,0
        dc.l    0                   ; e (prev non renseigné par nous)
        dc.w    1,$12,0
        dc.l    $23100000           ; e avec prev1 = alt-f
        dc.w    1,$41,0
        dc.l    0                   ; BS
        dc.w    1,$46,0
        dc.l    0                   ; Del
        dc.w    $7FFE
        dc.w    $7FFF,r_raw1-tests  ; CSI 1{ : RAWKEY en brut
        dc.w    1,$20,$8000
        dc.l    $12345678
        dc.w    $7FFE
        dc.w    $7FFF,r_raw2-tests  ; CSI 1} CSI 2{ (souris)
        dc.w    1,$20,0
        dc.l    0
        dc.w    2,$68,0
        dc.l    0
        dc.w    2,$E8,0
        dc.l    0
        dc.w    $7FFE
        dc.w    $7FFF,r_raw3-tests  ; CSI 2} CSI 0{ 4{ 6{
        dc.w    4,0,0
        dc.l    $00640032
        dc.w    0,0,0
        dc.l    0
        dc.w    1,$21,0
        dc.l    0
        dc.w    $7FFE
        dc.w    $7FFF,r_raw4-tests  ; CSI 0;4;6}
        dc.w    -1

m_hello: dc.b   "CONPROBE 1",10,0
m_open:  dc.b   "O-1 ",0
m_open0: dc.b   "O0 ",0
m_open1: dc.b   "O1 ",0
m_open2: dc.b   "O2 ",0
m_win:   dc.b   "W ",0
m_tabs:  dc.b   "TABS ",0
m_t:     dc.b   "T ",0
m_u:     dc.b   "U ",0
m_r:     dc.b   "R ",0
m_i:     dc.b   "I ",0
m_k:     dc.b   "K ",0
m_kx:    dc.b   "KX ",0
m_kd:    dc.b   "KD ",0
m_kd2:   dc.b   "KD2 ",0
m_kc:    dc.b   "KC ",0
m_kio:   dc.b   "KIO ",0
m_km:    dc.b   "KM",0
m_kmr:   dc.b   "KMR ",0
m_rk:    dc.b   "RK",0
m_cmd:   dc.b   "CMD",0
m_stop:  dc.b   "STOP",0
m_inp:   dc.b   "INP",0
m_clr:   dc.b   "CLR ",0
m_act:   dc.b   "ACT ",0
m_force: dc.b   "FORCED",10,0
m_alt:   dc.b   "ALTWIN ",0
m_k2:    dc.b   "@K",10,0
m_shot:  dc.b   "@S ",0
m_idle:  dc.b   "IDLE",10,0
m_rd0:   dc.b   "RD0",10,0
m_rd0b:  dc.b   "RD0 survived ",0
m_fail:  dc.b   "FAIL",10,0
s_len1:  dc.b   "len-1",0
s_dsr:   dc.b   "dsr",0
s_ovf:   dc.b   "ovf",0
s_rsz:   dc.b   "resize",0
intname: dc.b   "intuition.library",0
gfxname: dc.b   "graphics.library",0
conname: dc.b   "console.device",0
inpname: dc.b   "input.device",0
kmrname: dc.b   "keymap.resource",0
s_title: dc.b   "ConProbe",0
p_len1:  dc.b   "xyz",0
p_dsr:   dc.b   $9B,"6n",0
p_dsr2:  dc.b   $9B,"5n",$9B,"n",$9B,"6;6n",$1B,"[6n",0
p_wsr:   dc.b   $9B," q",0
p_wsr2:  dc.b   $9B,"0 q",$9B,"q",$9B,"  q",0
p_none:  dc.b   0
p_fill:  dc.b   $1B,"c",$9B,"24H","LAST",$9B,"1;75HRIGHT",0
p_reset: dc.b   $1B,"c",0

        even

; NewWindow : 0,0 640x200, gadgets sizing/drag/depth/close, ACTIVATE, SMART_REFRESH, WBENCHSCREEN
nw1:    dc.w    0,0,640,200
        dc.b    0,1
        dc.l    0, $100F, 0, 0, 0, 0, 0
        dc.w    100,40,640,200,1

CTEST   MACRO
        dc.w    \1-tests,\2,\3
        ENDM
; SIMPLE_REFRESH ($40), sans ACTIVATE
nw2:    dc.w    100,60,400,100
        dc.b    0,1
        dc.l    0, $004F, 0, 0, 0, 0, 0
        dc.w    100,40,640,200,1
; GIMMEZEROZERO ($400)
nw3:    dc.w    100,60,400,100
        dc.b    0,1
        dc.l    0, $040F, 0, 0, 0, 0, 0
        dc.w    100,40,640,200,1
altl1:  CTEST   a01,3,30
        CTEST   a02,3,30
        dc.w    0
altl2:  CTEST   a03,3,30
        CTEST   a04,3,30
        CTEST   a05,3,30
        dc.w    0

; ---------------------------------------------------------------- tests d'écriture
; enregistrements : dc.w décalage, lignes, colonnes ; fin = 0
tests:
        CTEST   t01,2,40
        CTEST   t02,2,40
        CTEST   t03,2,40
        CTEST   t04,3,40
        CTEST   t05,3,40
        CTEST   t06,3,40
        CTEST   t07,3,40
        CTEST   t08,3,40
        CTEST   t09,3,40
        CTEST   t10,3,40
        CTEST   t11,4,40
        CTEST   t12,4,40
        CTEST   t13,4,40
        CTEST   t14,6,40
        CTEST   t15,4,40
        CTEST   t16,4,40
        CTEST   t17,4,40
        CTEST   t18,4,40
        CTEST   t19,6,40
        CTEST   t20,6,40
        CTEST   t21,6,40
        CTEST   t22,6,40
        CTEST   t23,6,40
        CTEST   t24,6,40
        CTEST   t25,6,40
        CTEST   t26,6,40
        CTEST   t27,4,40
        CTEST   t28,4,40
        CTEST   t29,4,40
        CTEST   t30,4,40
        CTEST   t31,4,40
        CTEST   t32,4,40
        CTEST   t33,4,40
        CTEST   t34,4,40
        CTEST   t35,4,40
        CTEST   t36,4,40
        CTEST   t37,4,40
        CTEST   t38,4,40
        CTEST   t39,4,40
        CTEST   t40,4,40
        CTEST   t41,4,40
        CTEST   t42,4,40
        CTEST   t43,4,40
        CTEST   t44,4,40
        CTEST   t45,4,40
        CTEST   t46,4,40
        CTEST   t47,4,40
        CTEST   t48,4,40
        CTEST   t49,4,40
        CTEST   t50,4,40
        CTEST   t51,4,40
        CTEST   t52,4,40
        CTEST   t53,4,40
        CTEST   t54,4,40
        CTEST   t55,4,40
        CTEST   t56,4,40
        CTEST   t57,4,40
        CTEST   t58,4,40
        CTEST   t59,4,40
        CTEST   t60,3,80
        CTEST   t61,3,80
        CTEST   t62,3,80
        CTEST   t63,3,80
        CTEST   t64,3,80
        CTEST   t65,3,80
        CTEST   t66,2,40
        CTEST   t67,2,40
        CTEST   t68,4,40
        CTEST   t69,3,40
        CTEST   t70,3,40
        CTEST   t71,3,40
        CTEST   t72,3,40
        CTEST   t73,3,40
        CTEST   t74,3,40
        CTEST   t75,3,40
        CTEST   t76,3,40
        CTEST   t77,3,40
        CTEST   t78,3,40
        CTEST   t79,3,40
        CTEST   t80,24,40
        CTEST   t81,24,40
        CTEST   t82,24,40
        CTEST   t83,24,40
        CTEST   t84,12,60
        CTEST   t85,12,60
        CTEST   t86,4,40
        CTEST   t87,4,40
        CTEST   t88,4,40
        CTEST   t89,4,40
        CTEST   t90,4,40
        CTEST   w01,3,24
        CTEST   w02,3,24
        CTEST   w03,3,24
        CTEST   w04,3,24
        CTEST   w05,3,24
        CTEST   w06,3,24
        CTEST   w07,3,24
        CTEST   w08,3,24
        CTEST   w09,3,24
        CTEST   w10,3,24
        CTEST   w11,3,24
        CTEST   w12,3,24
        dc.w    0

RS      EQU     $1B         ; ESC
CSI     EQU     $9B
; chaque test commence par ESC c (réinitialisation) puis FF sauf mention
t01:    dc.b    "base",0,RS,"c",$0C,"ABC",0
t02:    dc.b    "esc_c_after_text",0,RS,"c",$0C,"HELLO",RS,"c",0
t03:    dc.b    "ff",0,RS,"c",$0C,"HELLO",$0C,"X",0
t04:    dc.b    "lf_lnm_default",0,RS,"c",$0C,"AB",$0A,"CD",$0D,$0A,"EF",0
t05:    dc.b    "lf_lnm_off",0,RS,"c",$0C,CSI,"20l","AB",$0A,"CD",$0A,$0D,"EF",0
t06:    dc.b    "cr_bs",0,RS,"c",$0C,"ABC",$08,$08,"X",$0D,"Y",0
t07:    dc.b    "bs_col0_awm",0,RS,"c",$0C,"AB",$0A,$08,"X",0
t08:    dc.b    "bs_col0_noawm",0,RS,"c",$0C,CSI,"?7l","AB",$0A,$08,"X",0
t09:    dc.b    "tab_default",0,RS,"c",$0C,$09,"A",$09,"B",$09,$09,"C",0
t10:    dc.b    "tab_hts_88",0,RS,"c",$0C,CSI,"1;4H",$88,$0D,$09,"X",$09,"Y",0
t11:    dc.b    "tab_esc_H",0,RS,"c",$0C,CSI,"1;3H",RS,"H",$0D,$09,"X",0
t12:    dc.b    "tab_W0_W2_W5",0,RS,"c",$0C,CSI,"1;6H",CSI,"W",$0D,$09,"X",CSI,"1;9H",CSI,"2W",$0D,$09,$09,"Y",CSI,"5W",$0D,$09,"Z",0
t13:    dc.b    "tab_g_3g",0,RS,"c",$0C,CSI,"1;9H",CSI,"g",$0D,$09,"X",CSI,"3g",$0D,$09,"Y",0
t14:    dc.b    "tab_end_wrap",0,RS,"c",$0C,CSI,"1;75H",$09,"X",CSI,"3;75H",CSI,"?7l",$09,"Y",0
t15:    dc.b    "cbt_cht",0,RS,"c",$0C,CSI,"1;20H",CSI,"Z","A",CSI,"2Z","B",CSI,"3I","C",CSI,"I","D",0
t16:    dc.b    "cbt_col0",0,RS,"c",$0C,CSI,"2;1H",CSI,"Z","A",CSI,"3;1H",CSI,"?7l",CSI,"Z","B",0
t17:    dc.b    "cuu_cud_cuf_cub",0,RS,"c",$0C,CSI,"3;10H",CSI,"A","A",CSI,"2B","B",CSI,"5C","C",CSI,"3D","D",CSI,"0A","E",CSI,"-2B","F",0
t18:    dc.b    "cup_defaults",0,RS,"c",$0C,"ABCDEF",CSI,"H","1",CSI,"2H","2",CSI,";5H","3",CSI,"3;f","4",CSI,"0;0H","5",0
t19:    dc.b    "cup_clamp",0,RS,"c",$0C,CSI,"99;999HX",0
t20:    dc.b    "cuu_top_asm",0,RS,"c",$0C,"L1",$0D,$0A,"L2",$0D,$0A,"L3",CSI,"1;1H",CSI,"2A","T",0
t21:    dc.b    "cuu_top_noasm",0,RS,"c",$0C,CSI,">1l","L1",$0D,$0A,"L2",CSI,"1;1H",CSI,"2A","T",0
t22:    dc.b    "cud_bottom_asm",0,RS,"c",$0C,"L1",CSI,"24;1H","LB",CSI,"2B","T",0
t23:    dc.b    "cuf_wrap",0,RS,"c",$0C,CSI,"1;78H",CSI,"5C","X",0
t24:    dc.b    "cub_wrap",0,RS,"c",$0C,CSI,"2;3H",CSI,"5D","X",0
t25:    dc.b    "cuf_nowrap",0,RS,"c",$0C,CSI,"?7l",CSI,"1;78H",CSI,"5C","X",CSI,"2;3H",CSI,"5D","Y",0
t26:    dc.b    "cnl_cpl",0,RS,"c",$0C,CSI,"3;10H",CSI,"E","A",CSI,"2F","B",CSI,"0E","C",0
t27:    dc.b    "el",0,RS,"c",$0C,"ABCDEFGH",$0D,$0A,"IJKLMNOP",CSI,"1;4H",CSI,"K",CSI,"2;4H",CSI,"1K",0
t28:    dc.b    "el2",0,RS,"c",$0C,"ABCDEFGH",CSI,"1;4H",CSI,"2K",0
t29:    dc.b    "ed",0,RS,"c",$0C,"ABCDEFGH",$0D,$0A,"IJKLMNOP",$0D,$0A,"QRSTUVWX",CSI,"2;4H",CSI,"J",0
t30:    dc.b    "ed1_ed2",0,RS,"c",$0C,"ABCDEFGH",$0D,$0A,"IJKLMNOP",$0D,$0A,"QRSTUVWX",CSI,"2;4H",CSI,"1J",CSI,"3;6H",CSI,"2J",0
t31:    dc.b    "ich",0,RS,"c",$0C,"ABCDEFGH",CSI,"1;3H",CSI,"@",CSI,"1;7H",CSI,"3@","x",0
t32:    dc.b    "dch",0,RS,"c",$0C,"ABCDEFGH",CSI,"1;3H",CSI,"P",CSI,"1;4H",CSI,"2P","x",0
t33:    dc.b    "il",0,RS,"c",$0C,"L1",$0D,$0A,"L2",$0D,$0A,"L3",CSI,"2;2H",CSI,"L","x",0
t34:    dc.b    "dl",0,RS,"c",$0C,"L1",$0D,$0A,"L2",$0D,$0A,"L3",$0D,$0A,"L4",CSI,"2;2H",CSI,"2M","x",0
t35:    dc.b    "su_sd",0,RS,"c",$0C,"L1",$0D,$0A,"L2",$0D,$0A,"L3",$0D,$0A,"L4",CSI,"S",CSI,"2T","x",0
t36:    dc.b    "sgr_bold",0,RS,"c",$0C,"A",CSI,"1m","B",CSI,"0m","C",0
t37:    dc.b    "sgr_2_3_4",0,RS,"c",$0C,CSI,"2m","D",CSI,"0m",CSI,"3m","I",CSI,"m",CSI,"4m","U",CSI,"0m","N",0
t38:    dc.b    "sgr_7_inverse",0,RS,"c",$0C,CSI,"7m","R",CSI,"0m","N",0
t39:    dc.b    "sgr_8_conceal",0,RS,"c",$0C,CSI,"8m","H",CSI,"0m","N",0
t40:    dc.b    "sgr_fg",0,RS,"c",$0C,CSI,"30mA",CSI,"31mB",CSI,"32mC",CSI,"33mD",CSI,"34mE",CSI,"37mF",CSI,"39mG",0
t41:    dc.b    "sgr_bg",0,RS,"c",$0C,CSI,"40mA",CSI,"41mB",CSI,"42mC",CSI,"43mD",CSI,"44mE",CSI,"49mF",0
t42:    dc.b    "sgr_multi",0,RS,"c",$0C,CSI,"1;4;33;41mM",CSI,";32mN",0
t43:    dc.b    "sgr_22_24_27",0,RS,"c",$0C,CSI,"1;4;7mA",CSI,"22;24;27mB",CSI,"0mC",0
t44:    dc.b    "sgr_bg_then_el",0,RS,"c",$0C,"ABCDEFGH",CSI,"43m",CSI,"1;4H",CSI,"K",CSI,"0m",0
t45:    dc.b    "sgr_bg_then_ff",0,RS,"c",$0C,CSI,"42m",$0C,"A",CSI,"0m",0
t46:    dc.b    "sgr_bg_scroll",0,RS,"c",$0C,CSI,"43m","L1",$0D,$0A,"L2",CSI,"1;1H",CSI,"T",CSI,"0m",0
t47:    dc.b    "sgr_bg_ich",0,RS,"c",$0C,"ABCDEF",CSI,"43m",CSI,"1;2H",CSI,"2@",CSI,"0m",0
t48:    dc.b    "sgr_bg_inverse_el",0,RS,"c",$0C,"ABCDEFGH",CSI,"7m",CSI,"1;4H",CSI,"K",CSI,"0m",0
t49:    dc.b    "modes_set",0,RS,"c",$0C,CSI,"20l",CSI,">1l",CSI,"?7l",CSI,"3h",0
t50:    dc.b    "modes_reset",0,CSI,"20h",CSI,">1h",CSI,"?7h",CSI,"3l",CSI,"1;2;19h",0
t51:    dc.b    "so_si",0,RS,"c",$0C,$0E,"Ab",$0F,"Ab",$C1,$E9,0
t52:    dc.b    "c1_ignored_and_7f",0,RS,"c",$0C,"A",$80,$81,$86,$90,$9A,$9F,"B",$7F,"C",0
t53:    dc.b    "esc_c1_equiv",0,RS,"c",$0C,"AB",RS,"D","C",RS,"E","D",RS,"M","E",RS,"[2;8H","F",0
t54:    dc.b    "esc_ignored",0,RS,"c",$0C,"A",RS,"7B",RS,"(0C",RS,"#8D",RS,"=E",RS,"aF",RS,RS,"[2CG",0
t55:    dc.b    "csi_aborts",0,RS,"c",$0C,"A",CSI,"2",$0A,"B",CSI,"1;",$1B,"[CC",CSI,"!pD",CSI,"5 HE",CSI,"1",$9B,"2CF",0
t56:    dc.b    "csi_intermediate",0,RS,"c",$0C,"A",CSI,"2!CB",CSI,"3 CC",CSI,"!2CD",0
t57:    dc.b    "csi_G_d_ignored",0,RS,"c",$0C,"ABC",CSI,"10GX",CSI,"3dY",CSI,"2XZ",0
t58:    dc.b    "cursor_off",0,RS,"c",$0C,"AB",CSI,"0 p",0
t59:    dc.b    "cursor_on",0,"C",CSI," p","D",CSI,"0p","E",CSI,"p",0
t60:    dc.b    "awm_wrap",0,RS,"c",$0C,"0123456789012345678901234567890123456789012345678901234567890123456789012345678",$0A,"B",0
t61:    dc.b    "awm_exact80_lf",0,RS,"c",$0C,"01234567890123456789012345678901234567890123456789012345678901234567890123456789",$0A,"B",0
t62:    dc.b    "awm_exact80_crlf",0,RS,"c",$0C,"01234567890123456789012345678901234567890123456789012345678901234567890123456789",$0D,$0A,"B",0
t63:    dc.b    "awm_exact80_char",0,RS,"c",$0C,"01234567890123456789012345678901234567890123456789012345678901234567890123456789","B",$0A,"C",0
t64:    dc.b    "noawm_overflow",0,RS,"c",$0C,CSI,"?7l","01234567890123456789012345678901234567890123456789012345678901234567890123456789XYZ",0
t65:    dc.b    "awm_exact80_cnl_cr",0,RS,"c",$0C,"01234567890123456789012345678901234567890123456789012345678901234567890123456789",CSI,"E","B",RS,"c",$0C,"01234567890123456789012345678901234567890123456789012345678901234567890123456789",$0D,"C",0
t66:    dc.b    "vt_ri",0,RS,"c",$0C,CSI,"3;5H","A",$0B,"B",$8D,"C",0
t67:    dc.b    "ind_nel",0,RS,"c",$0C,CSI,"20l","A",$84,"B",$85,"C",0
t68:    dc.b    "vt_at_top_asm",0,RS,"c",$0C,"L1",$0D,$0A,"L2",CSI,"1;1H",$0B,"T",0
t69:    dc.b    "params_big",0,RS,"c",$0C,CSI,"65535C","X",CSI,"1;99999HY",CSI,"40000DZ",0
t70:    dc.b    "params_many",0,RS,"c",$0C,CSI,"1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23;24;25;26;27;28;29;30mX",CSI,"5;5H","Y",0
t71:    dc.b    "params_colon_lt",0,RS,"c",$0C,CSI,"2:5H","X",CSI,"<3H","Y",CSI,"=4CZ",0
t72:    dc.b    "dsr_noread",0,RS,"c",$0C,"A",0
t73:    dc.b    "bel",0,RS,"c",$0C,"A",$07,"B",0
t74:    dc.b    "ich_dch_edge",0,RS,"c",$0C,"ABCDEFGH",CSI,"1;80H",CSI,"@",CSI,"1;1H",CSI,"99P",0
t75:    dc.b    "il_dl_bottom",0,RS,"c",$0C,"L1",CSI,"24;1H","LB",CSI,"L",CSI,"23;1H",CSI,"M",0
t76:    dc.b    "su_sd_param0",0,RS,"c",$0C,"L1",$0D,$0A,"L2",CSI,"0S",CSI,"0T",0
t77:    dc.b    "rawevents_flags",0,RS,"c",$0C,CSI,"1;2;18;19;-1{",0
t78:    dc.b    "rawevents_clear",0,CSI,"1;2;18}",0
t79:    dc.b    "lnm_lf_after_wrap",0,RS,"c",$0C,CSI,"20l","01234567890123456789012345678901234567890123456789012345678901234567890123456789",$0A,"B",0
t80:    dc.b    "lf_scroll_bottom",0,RS,"c",$0C,"TOP",CSI,"24;1H","BOT",$0A,"N",0
t81:    dc.b    "lf_noasm_bottom",0,RS,"c",$0C,CSI,">1l","TOP",CSI,"24;1H","BOT",$0A,"N",0
t82:    dc.b    "page_t_u",0,RS,"c",$0C,CSI,"5t",CSI,"20u","ABCDEFGHIJKLMNOPQRSTUVWXYZ",CSI,"5;1H","X",$0A,"Y",0
t83:    dc.b    "page_t_u_reset",0,CSI,"t",CSI,"u","Q",0
t84:    dc.b    "offsets_x_y",0,RS,"c",$0C,CSI,"16x",CSI,"20y","AB",0
t85:    dc.b    "offsets_reset",0,CSI,"x",CSI,"y","C",CSI,"0x",CSI,"0y","D",0
t86:    dc.b    "esc_c_after_modes",0,RS,"c",$0C,"A",CSI,"20l",CSI,"5t",CSI,"1m",RS,"c","B",0
t87:    dc.b    "home_ff_cursor",0,RS,"c",$0C,"AB",$0C,0
t88:    dc.b    "nul_ignored",0,RS,"c",$0C,"A",$01,"B",$1C,"C",$1F,"D",0
t89:    dc.b    "hts_c1_dup",0,RS,"c",$0C,CSI,"1;8H",$88,$88,CSI,"1;6H",$88,0
t90:    dc.b    "tabs_after",0,0
r_reset: dc.b   "reset",0,RS,"c",0
w01:    dc.b    "w20_lf",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQRST",$0A,"B",0
w02:    dc.b    "w20_crlf",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQRST",$0D,$0A,"B",0
w03:    dc.b    "w20_char_lf",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQRST","B",$0A,"C",0
w04:    dc.b    "w20_cnl",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQRST",CSI,"E","B",0
w05:    dc.b    "w20_noawm",0,RS,"c",$0C,CSI,"20u",CSI,"?7l","ABCDEFGHIJKLMNOPQRSTUVW",0
w06:    dc.b    "w20_lnmoff_lf",0,RS,"c",$0C,CSI,"20u",CSI,"20l","ABCDEFGHIJKLMNOPQRST",$0A,"B",0
w07:    dc.b    "w20_tab_lf",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQR",$09,$0A,"B",0
w08:    dc.b    "w20_bs",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQRST",$08,"X",0
w09:    dc.b    "w20_cuf_lf",0,RS,"c",$0C,CSI,"20u",CSI,"1;19H",CSI,"2C",$0A,"B",0
w10:    dc.b    "w20_lf_lf",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQRST",$0A,$0A,"B",0
w11:    dc.b    "w20_cpl",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQRST",CSI,"F","B",0
w12:    dc.b    "w20_ri_vt",0,RS,"c",$0C,CSI,"20u","ABCDEFGHIJKLMNOPQRST",$0B,"B",0
a01:    dc.b    "simple_text",0,"HELLO",$0D,$0A,"WORLD",0
a02:    dc.b    "simple_esc_c",0,RS,"c","X",0
a03:    dc.b    "gzz_text",0,"HELLO",0
a04:    dc.b    "gzz_x16",0,CSI,"16x","A",0
a05:    dc.b    "gzz_y16",0,CSI,"x",CSI,"16y","B",0
r_raw1: dc.b    "raw1",0,CSI,"1{",0
r_raw2: dc.b    "raw2",0,CSI,"1}",CSI,"2{",0
r_raw3: dc.b    "raw3",0,CSI,"2}",CSI,"0{",CSI,"4{",CSI,"6{",0
r_raw4: dc.b    "raw4",0,CSI,"0;4;6}",0
        even
vars:   ds.b    v_size
endprog:
