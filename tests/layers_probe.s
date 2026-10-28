; tests/layers_probe.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Sonde boîte noire de layers.library (piste analyse, docs/analysis/layers-v34.md).
; Lancée depuis la startup-sequence d'une disquette (tests/layers_probe.sh). Travaille sur une BitMap
; privée (non affichée) et une Layer_Info privée ; appelle les fonctions par leurs LVO publics et écrit
; l'état des structures (Layer, ClipRect, DamageList, Layer_Info) sur le série direct, en hexadécimal.
; Assemblage : vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/layers_probe tests/layers_probe.s
; Code auteur ; structures publiques (graphics/clip.h, layers.h, gfx.h, regions.h de la 1.3).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
SCRW     EQU 320
SCRH     EQU 200
PLSZ     EQU SCRW/8*SCRH            ; 8000 octets par plan
SBW      EQU 256
SBH      EQU 128
SBPL     EQU SBW/8*SBH              ; 4096
O_P0     EQU 0
O_P1     EQU PLSZ
O_SB0    EQU 2*PLSZ
O_SB1    EQU 2*PLSZ+SBPL
CHIPSZ   EQU 2*PLSZ+2*SBPL

; layers.library
L_InitLayers    EQU -30
L_CreateUpfront EQU -36
L_CreateBehind  EQU -42
L_Upfront       EQU -48
L_Behind        EQU -54
L_Move          EQU -60
L_Size          EQU -66
L_Scroll        EQU -72
L_BeginUpdate   EQU -78
L_EndUpdate     EQU -84
L_Delete        EQU -90
L_LockLayer     EQU -96
L_UnlockLayer   EQU -102
L_LockLayers    EQU -108
L_UnlockLayers  EQU -114
L_LockLayerInfo EQU -120
L_WhichLayer    EQU -132
L_UnlockLayerInfo EQU -138
L_NewLayerInfo  EQU -144
L_DisposeLayerInfo EQU -150
L_Fatten        EQU -156
L_Thin          EQU -162
L_MoveInFrontOf EQU -168
; graphics.library
G_InitRastPort  EQU -198
G_RectFill      EQU -306
G_ReadPixel     EQU -318
G_SetAPen       EQU -342
G_InitBitMap    EQU -390
G_OrRectRegion  EQU -510
G_NewRegion     EQU -516
G_DisposeRegion EQU -534

LAY     macro
        move.l  layb-vars(a4),a6
        jsr     \1(a6)
        endm
GFX     macro
        move.l  gfxb-vars(a4),a6
        jsr     \1(a6)
        endm
MSG     macro
        lea     \1(pc),a0
        bsr     puts
        endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  4.w,a6
                lea     gfxname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,gfxb-vars(a4)
                beq     .out
                lea     layname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,layb-vars(a4)
                beq     .out
                move.l  #CHIPSZ,d0
                move.l  #$10002,d1
                jsr     -198(a6)
                move.l  d0,chip-vars(a4)
                beq     .out
                move.l  d0,a5
                MSG     m_start
; version de layers
                move.l  layb-vars(a4),a0
                move.w  20(a0),d0
                bsr     phex4
                bsr     sp1
                move.w  22(a0),d0
                bsr     phex4
                bsr     sp1
                move.w  16(a0),d0               ; lib_NegSize
                bsr     phex4
                bsr     sp1
                move.w  18(a0),d0               ; lib_PosSize
                bsr     phex4
                bsr     nl
; écran : BitMap 320x200x2, plans remplis de $FF
                lea     scrbm-vars(a4),a0
                moveq   #2,d0
                move.l  #SCRW,d1
                move.l  #SCRH,d2
                GFX     G_InitBitMap
                lea     scrbm-vars(a4),a0
                lea     O_P0(a5),a1
                move.l  a1,8(a0)
                lea     O_P1(a5),a1
                move.l  a1,12(a0)
                lea     O_P0(a5),a0
                move.w  #2*PLSZ/4-1,d0
.ff:            move.l  #-1,(a0)+
                dbra    d0,.ff
                lea     scrrp-vars(a4),a1
                GFX     G_InitRastPort
                lea     scrrp-vars(a4),a1
                lea     scrbm-vars(a4),a0
                move.l  a0,4(a1)

; ---------- T0 : NewLayerInfo ----------
                MSG     m_t0
                LAY     L_NewLayerInfo
                move.l  d0,li-vars(a4)
                bsr     phex8
                bsr     nl
                bsr     dumpli
; ---------- T1 : A SMART (16,10)-(115,59) ----------
                MSG     m_t1
                move.l  #$10,d0
                moveq   #10,d1
                move.l  #115,d2
                moveq   #59,d3
                moveq   #2,d4
                sub.l   a2,a2
                bsr     cup
                move.l  d0,lA-vars(a4)
                bsr     okline
                moveq   #16,d0
                moveq   #10,d1
                bsr     pix
                moveq   #15,d0
                moveq   #10,d1
                bsr     pix
                bsr     nl
                bsr     dumpall
                move.l  lA-vars(a4),a0
                moveq   #1,d0
                bsr     fill
; ---------- T2 : B SIMPLE (60,30)-(159,89) ----------
                MSG     m_t2
                moveq   #60,d0
                moveq   #30,d1
                move.l  #159,d2
                move.l  #89,d3
                moveq   #1,d4
                sub.l   a2,a2
                bsr     cup
                move.l  d0,lB-vars(a4)
                bsr     okline
                moveq   #70,d0
                moveq   #40,d1
                bsr     pix
                moveq   #20,d0
                moveq   #20,d1
                bsr     pix
                bsr     nl
                bsr     dumpall
                bsr     dumpli
                move.l  lB-vars(a4),a0
                moveq   #2,d0
                bsr     fill
; ---------- T3 : C SMART (100,20)-(199,49) ----------
                MSG     m_t3
                moveq   #100,d0
                moveq   #20,d1
                move.l  #199,d2
                moveq   #49,d3
                moveq   #2,d4
                sub.l   a2,a2
                bsr     cup
                move.l  d0,lC-vars(a4)
                bsr     okline
                bsr     dumpall
                move.l  lC-vars(a4),a0
                moveq   #3,d0
                bsr     fill
                bsr     pixset
; ---------- T4 : UpfrontLayer(A) ----------
                MSG     m_t4
                move.l  lA-vars(a4),a1
                LAY     L_Upfront
                bsr     okline
                bsr     dumpall
                bsr     pixset
; ---------- T5 : BehindLayer(A) ----------
                MSG     m_t5
                move.l  lA-vars(a4),a1
                LAY     L_Behind
                bsr     okline
                bsr     dumpall
                bsr     pixset
; ---------- T6 : UpfrontLayer(B) (B simple) ----------
                MSG     m_t6
                move.l  lB-vars(a4),a1
                LAY     L_Upfront
                bsr     okline
                bsr     dumpall
                bsr     pixset
; ---------- T7 : MoveLayer(C, +10, +5) ----------
                MSG     m_t7
                move.l  lC-vars(a4),a1
                moveq   #10,d0
                moveq   #5,d1
                LAY     L_Move
                bsr     okline
                bsr     dumpall
                bsr     pixset
; ---------- T8 : SizeLayer(C, +20, +10) puis (-30,-15) ----------
                MSG     m_t8
                move.l  lC-vars(a4),a0
                bsr     cleardmg
                move.l  lC-vars(a4),a1
                moveq   #20,d0
                moveq   #10,d1
                LAY     L_Size
                bsr     okline
                move.l  lC-vars(a4),a2
                moveq   #'C',d6
                bsr     dumpL
                move.l  lC-vars(a4),a1
                moveq   #-30,d0
                moveq   #-15,d1
                LAY     L_Size
                bsr     okline
                move.l  lC-vars(a4),a2
                moveq   #'C',d6
                bsr     dumpL
; ---------- T9 : SizeLayer(B simple, +10, 0), MoveLayer(B,0,0), ScrollLayer(B,3,4) ----------
                MSG     m_t9
                move.l  lB-vars(a4),a0
                bsr     cleardmg
                move.l  lB-vars(a4),a1
                moveq   #10,d0
                moveq   #0,d1
                LAY     L_Size
                bsr     okline
                move.l  lB-vars(a4),a2
                moveq   #'B',d6
                bsr     dumpL
                move.l  lB-vars(a4),a1
                moveq   #0,d0
                moveq   #0,d1
                LAY     L_Move
                bsr     okline
                move.l  lB-vars(a4),a1
                moveq   #3,d0
                moveq   #4,d1
                LAY     L_Scroll
                bsr     okline
                move.l  lB-vars(a4),a2
                moveq   #'B',d6
                bsr     dumpL
                move.l  lB-vars(a4),a1          ; remettre le défilement à 0
                moveq   #-3,d0
                moveq   #-4,d1
                LAY     L_Scroll
; ---------- T10 : BeginUpdate / EndUpdate ----------
                MSG     m_t10
                move.l  lA-vars(a4),a0          ; A : forcer des dommages connus
                bsr     cleardmg
                move.l  lA-vars(a4),a0
                move.l  $9C(a0),a0
                lea     rect1(pc),a1
                GFX     G_OrRectRegion
                move.l  lA-vars(a4),a0
                LAY     L_BeginUpdate
                bsr     okline
                move.l  lA-vars(a4),a2
                moveq   #'A',d6
                bsr     dumpL
                move.l  lA-vars(a4),a0
                moveq   #1,d0
                bsr     fill                     ; pen 1 dans A pendant la mise à jour
                move.l  lA-vars(a4),a0
                moveq   #-1,d0
                LAY     L_EndUpdate
                move.l  lA-vars(a4),a2
                moveq   #'A',d6
                bsr     dumpL
                move.l  lA-vars(a4),a0          ; dommages vides
                LAY     L_BeginUpdate
                bsr     okline
                move.l  lA-vars(a4),a0
                move.l  8(a0),d0
                bsr     phex8
                bsr     nl
                move.l  lA-vars(a4),a0
                moveq   #0,d0
                LAY     L_EndUpdate
; ---------- T11 : WhichLayer ----------
                MSG     m_t11
                lea     wpts(pc),a3
.wl:            move.w  (a3)+,d0
                bmi.s   .wle
                move.w  (a3)+,d1
                ext.l   d0
                ext.l   d1
                move.l  li-vars(a4),a0
                LAY     L_WhichLayer
                bsr     tagof
                bsr     putc
                bsr     sp1
                bra.s   .wl
.wle:           bsr     nl
; ---------- T12 : verrous ----------
                MSG     m_t12
                move.l  li-vars(a4),a0
                LAY     L_LockLayers
                bsr     dumpcnt
                move.l  li-vars(a4),a0
                LAY     L_LockLayers
                bsr     dumpcnt
                move.l  li-vars(a4),a0
                LAY     L_UnlockLayers
                bsr     dumpcnt
                move.l  li-vars(a4),a0
                LAY     L_UnlockLayers
                bsr     dumpcnt
                move.l  li-vars(a4),a0
                move.l  lA-vars(a4),a1
                LAY     L_LockLayer
                bsr     dumpcnt
                move.l  lA-vars(a4),a0
                LAY     L_UnlockLayer
                bsr     dumpcnt
                move.l  li-vars(a4),a0
                LAY     L_LockLayerInfo
                bsr     dumpcnt
                move.l  li-vars(a4),a0
                LAY     L_UnlockLayerInfo
                bsr     dumpcnt
                bsr     nl
; ---------- T13 : D BACKDROP|SIMPLE plein écran, puis UpfrontLayer(D) ----------
                MSG     m_t13
                moveq   #0,d0
                moveq   #0,d1
                move.l  #SCRW-1,d2
                move.l  #SCRH-1,d3
                moveq   #$41,d4
                sub.l   a2,a2
                bsr     cup
                move.l  d0,lD-vars(a4)
                bsr     okline
                bsr     order
                move.l  lD-vars(a4),a1
                LAY     L_Upfront
                bsr     okline
                bsr     order
                move.l  lA-vars(a4),a0           ; MoveLayerInFrontOf(A, B)
                move.l  lB-vars(a4),a1
                LAY     L_MoveInFrontOf
                bsr     okline
                bsr     order
                move.l  lA-vars(a4),a1          ; BehindLayer(A) : derrière tous sauf backdrop
                LAY     L_Behind
                bsr     okline
                bsr     order
                bsr     dumpall
; ---------- T14 : S SUPER_BITMAP ----------
                MSG     m_t14
                lea     superbm-vars(a4),a0
                moveq   #2,d0
                move.l  #SBW,d1
                move.l  #SBH,d2
                GFX     G_InitBitMap
                lea     superbm-vars(a4),a0
                lea     O_SB0(a5),a1
                move.l  a1,8(a0)
                lea     O_SB1(a5),a1
                move.l  a1,12(a0)
                lea     O_SB0(a5),a0            ; plan 0 : lignes paires $FFFF, impaires 0
                moveq   #SBH-1,d1
.sbl:           moveq   #SBW/32-1,d0
                move.l  d1,d2
                and.l   #1,d2
                beq.s   .sbe
                moveq   #0,d2
                bra.s   .sbw
.sbe:           moveq   #-1,d2
.sbw:           move.l  d2,(a0)+
                dbra    d0,.sbw
                dbra    d1,.sbl
                move.l  #200,d0
                move.l  #120,d1
                move.l  #279,d2
                move.l  #169,d3
                moveq   #4,d4
                lea     superbm-vars(a4),a2
                bsr     cup
                move.l  d0,lS-vars(a4)
                bsr     okline
                move.l  lS-vars(a4),a2
                moveq   #'S',d6
                bsr     dumpL
                move.l  #200,d0                 ; écran (200,120) = sbm (0,0) : 1 ; (200,121) : 0
                moveq   #120,d1
                bsr     pix
                move.l  #200,d0
                moveq   #121,d1
                bsr     pix
                bsr     nl
                move.l  lS-vars(a4),a1
                moveq   #16,d0
                moveq   #7,d1
                LAY     L_Scroll
                bsr     okline
                move.l  lS-vars(a4),a2
                moveq   #'S',d6
                bsr     dumpL
                move.l  #200,d0                 ; écran (200,120) = sbm (16,7) : 0
                moveq   #120,d1
                bsr     pix
                move.l  #200,d0
                moveq   #121,d1
                bsr     pix
                bsr     nl
                move.l  lS-vars(a4),a1          ; SizeLayer superbitmap
                moveq   #8,d0
                moveq   #4,d1
                LAY     L_Size
                bsr     okline
                move.l  lS-vars(a4),a2
                moveq   #'S',d6
                bsr     dumpL
; ---------- T15 : DeleteLayer ----------
                MSG     m_t15
                move.l  lC-vars(a4),a1
                LAY     L_Delete
                bsr     okline
                clr.l   lC-vars(a4)
                bsr     dumpall
                bsr     pixset
                move.l  lS-vars(a4),a1
                LAY     L_Delete
                bsr     okline
                clr.l   lS-vars(a4)
                move.l  lD-vars(a4),a1
                LAY     L_Delete
                bsr     okline
                clr.l   lD-vars(a4)
                move.l  lB-vars(a4),a1
                LAY     L_Delete
                bsr     okline
                clr.l   lB-vars(a4)
                move.l  lA-vars(a4),a1
                LAY     L_Delete
                bsr     okline
                clr.l   lA-vars(a4)
                bsr     dumpli
                moveq   #70,d0
                moveq   #40,d1
                bsr     pix
                bsr     nl
; ---------- T16 : Fatten/Thin/Dispose ----------
                MSG     m_t16
                move.l  li-vars(a4),a0
                LAY     L_Fatten
                bsr     okline
                bsr     dumpli
                move.l  li-vars(a4),a0
                LAY     L_Thin
                bsr     okline
                bsr     dumpli
                move.l  li-vars(a4),a0
                LAY     L_DisposeLayerInfo
                bsr     okline
; ---------- T17 : InitLayers sans Fatten (Layer_Info statique) ----------
                MSG     m_t17
                lea     sli-vars(a4),a0
                moveq   #101,d0
.sf:            move.b  #$EE,(a0)+
                dbra    d0,.sf
                lea     sli-vars(a4),a0
                LAY     L_InitLayers
                bsr     okline
                lea     sli-vars(a4),a0
                move.l  a0,li-vars(a4)
                bsr     dumpli
                moveq   #16,d0
                moveq   #10,d1
                moveq   #63,d2
                moveq   #49,d3
                moveq   #2,d4
                sub.l   a2,a2
                bsr     cup
                move.l  d0,lA-vars(a4)
                bsr     okline
                bsr     dumpli
                move.l  lA-vars(a4),a1
                LAY     L_Delete
                bsr     okline
                bsr     dumpli

; ---------- T20 : nouvelle Layer_Info ; A SMART, B SIMPLE créé DERRIÈRE ----------
                MSG     m_t20
                clr.l   lA-vars(a4)
                LAY     L_NewLayerInfo
                move.l  d0,li-vars(a4)
                moveq   #10,d0
                moveq   #10,d1
                moveq   #109,d2
                moveq   #59,d3
                moveq   #2,d4
                sub.l   a2,a2
                bsr     cup
                move.l  d0,lA-vars(a4)
                move.l  d0,a0
                moveq   #1,d0
                bsr     fill
                move.l  li-vars(a4),a0
                lea     scrbm-vars(a4),a1
                moveq   #50,d0
                moveq   #30,d1
                move.l  #149,d2
                move.l  #89,d3
                moveq   #1,d4
                sub.l   a2,a2
                LAY     L_CreateBehind
                move.l  d0,lB-vars(a4)
                bsr     okline
                bsr     dumpall
                move.l  lB-vars(a4),a0
                moveq   #2,d0
                bsr     fill
                bsr     pixset2
; ---------- T21 : MoveLayer(B simple, +8, +4) ----------
                MSG     m_t21
                move.l  lB-vars(a4),a0
                bsr     cleardmg
                move.l  lB-vars(a4),a1
                moveq   #8,d0
                moveq   #4,d1
                LAY     L_Move
                bsr     okline
                bsr     dumpall
                bsr     pixset2
; ---------- T22 : MoveLayer(A smart, +8, +4) au-dessus de B simple ----------
                MSG     m_t22
                move.l  lB-vars(a4),a0
                bsr     cleardmg
                move.l  lA-vars(a4),a1
                moveq   #8,d0
                moveq   #4,d1
                LAY     L_Move
                bsr     okline
                bsr     dumpall
                bsr     pixset2
; ---------- T23 : SwapBitsRastPortClipRect ----------
                MSG     m_t23
                move.l  lB-vars(a4),a1
                LAY     L_Upfront
                bsr     okline
                bsr     pixset2
                move.l  lA-vars(a4),a0
                move.l  8(a0),a1
.sw:            tst.l   8(a1)
                bne.s   .swf
                move.l  (a1),a1
                bra.s   .sw
.swf:           move.l  a1,swcr-vars(a4)
                move.l  $10(a1),d0
                bsr     phex8
                bsr     nl
                move.l  lA-vars(a4),a0
                move.l  12(a0),a0
                move.l  swcr-vars(a4),a1
                LAY     -126
                bsr     pixset2
                move.l  lA-vars(a4),a0
                move.l  12(a0),a0
                move.l  swcr-vars(a4),a1
                LAY     -126
                bsr     pixset2
; ---------- T24 : échecs mémoire (CHIP épuisée) ----------
                MSG     m_t24
                move.l  lA-vars(a4),a1
                LAY     L_Upfront
                bsr     okline
                bsr     hog
                move.l  hogn-vars(a4),d0
                bsr     phex8
                bsr     nl
                move.l  lA-vars(a4),a1          ; A smart derrière B simple : tampon CHIP requis
                LAY     L_Behind
                bsr     okline
                bsr     order
                bsr     dumpall
                moveq   #30,d0                  ; C smart chevauchant
                moveq   #20,d1
                moveq   #89,d2
                moveq   #69,d3
                moveq   #2,d4
                sub.l   a2,a2
                bsr     cup
                bsr     okline
                bsr     dumpli
                move.l  lA-vars(a4),a1
                moveq   #10,d0
                moveq   #10,d1
                LAY     L_Size
                bsr     okline
                move.l  lA-vars(a4),a1
                moveq   #-4,d0
                moveq   #0,d1
                LAY     L_Move
                bsr     okline
                bsr     dumpall
                bsr     pixset2
                bsr     unhog
                move.l  lA-vars(a4),a1
                LAY     L_Behind
                bsr     okline
                bsr     dumpall
                bsr     pixset2
                move.l  lA-vars(a4),a1
                LAY     L_Delete
                move.l  lB-vars(a4),a1
                LAY     L_Delete
                move.l  li-vars(a4),a0
                LAY     L_DisposeLayerInfo
                MSG     m_end
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- CreateUpfrontLayer(li, scrbm, d0..d3, flags d4, superbm a2) ; rend D0
cup:            move.l  li-vars(a4),a0
                lea     scrbm-vars(a4),a1
                move.l  layb-vars(a4),a6
                jmp     L_CreateUpfront(a6)

; --- remplit toute la couche a0 au stylo d0 (coordonnées couche, via son RastPort)
fill:           movem.l d2-d3/a2,-(sp)
                move.l  a0,a2
                move.l  12(a2),a1
                GFX     G_SetAPen
                move.l  12(a2),a1
                moveq   #0,d0
                moveq   #0,d1
                move.w  $14(a2),d2
                sub.w   $10(a2),d2
                ext.l   d2
                move.w  $16(a2),d3
                sub.w   $12(a2),d3
                ext.l   d3
                GFX     G_RectFill
                movem.l (sp)+,d2-d3/a2
                rts

; --- vide la DamageList de la couche a0 et efface LAYERREFRESH
cleardmg:       move.l  a0,-(sp)
                move.l  $9C(a0),a0
                move.l  gfxb-vars(a4),a6
                jsr     -528(a6)                ; ClearRegion
                move.l  (sp)+,a0
                and.w   #$FF7F,$1E(a0)
                rts

; --- ligne « = d0 » ; préserve d0
okline:         move.l  d0,-(sp)
                moveq   #'=',d1
                bsr     putc
                bsr     phex8
                bsr     nl
                move.l  (sp)+,d0
                rts

; --- pixel écran (d0,d1) : imprime « P x y v »
pix:            movem.l d0-d1,-(sp)
                moveq   #'P',d1
                bsr     putc
                move.l  (sp),d0
                bsr     phex4
                bsr     sp1
                move.l  4(sp),d0
                bsr     phex4
                bsr     sp1
                movem.l (sp)+,d0-d1
                lea     scrrp-vars(a4),a1
                GFX     G_ReadPixel
                bsr     phex2
                bsr     sp1
                rts


; --- épuise la CHIP : blocs chaînés (suivant +0, taille +4)
hog:            clr.l   hogl-vars(a4)
                clr.l   hogn-vars(a4)
.l:             move.l  4.w,a6
                move.l  #$20002,d1              ; MEMF_CHIP|MEMF_LARGEST
                jsr     -216(a6)                ; AvailMem
                cmp.l   #16,d0
                blo.s   .e
                move.l  d0,d2
                moveq   #2,d1
                jsr     -198(a6)
                tst.l   d0
                beq.s   .e
                move.l  d0,a0
                move.l  hogl-vars(a4),(a0)
                move.l  d2,4(a0)
                move.l  a0,hogl-vars(a4)
                add.l   d2,hogn-vars(a4)
                bra.s   .l
.e:             move.l  4.w,a6
                moveq   #2,d1
                jsr     -216(a6)
                move.l  d0,hogr-vars(a4)
                rts
unhog:          move.l  4.w,a6
.l:             move.l  hogl-vars(a4),d0
                beq.s   .e
                move.l  d0,a1
                move.l  (a1),hogl-vars(a4)
                move.l  4(a1),d0
                jsr     -210(a6)
                bra.s   .l
.e:             rts

pixset2:        lea     ppts2(pc),a3
                bra     pixset+4

; --- jeu de pixels témoins
pixset:         lea     ppts(pc),a3
.l:             move.w  (a3)+,d0
                bmi.s   .e
                move.w  (a3)+,d1
                ext.l   d0
                ext.l   d1
                bsr     pix
                bra.s   .l
.e:             bra     nl

; --- compteurs : LockLayersCount, nest du sémaphore LI, nest du verrou de A
dumpcnt:        moveq   #'k',d1
                bsr     putc
                move.l  li-vars(a4),a0
                move.b  $5B(a0),d0
                bsr     phex2
                moveq   #'/',d1
                bsr     putc
                move.l  li-vars(a4),a0
                move.w  $18+$0E(a0),d0          ; ss_NestCount
                bsr     phex4
                moveq   #'/',d1
                bsr     putc
                move.l  lA-vars(a4),a0
                move.w  $48+$0E(a0),d0
                bsr     phex4
                bra     sp1

; --- Layer_Info
dumpli:         move.l  li-vars(a4),a3
                moveq   #'I',d1
                bsr     putc
                move.l  (a3),d0
                bsr     tagof
                bsr     putc
                bsr     sp1
                move.w  $58(a3),d0
                bsr     phex4
                bsr     sp1
                move.b  $5A(a3),d0
                bsr     phex2
                bsr     sp1
                move.b  $5B(a3),d0
                bsr     phex2
                bsr     sp1
                move.w  $5C(a3),d0
                bsr     phex4
                bsr     sp1
                move.l  $5E(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  $62(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  4(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  8(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  $0C(a3),d0              ; FreeClipRects.mlh_Head
                lea     $10(a3),a0
                cmp.l   a0,d0
                seq     d0
                bsr     phex2
                bsr     sp1
                move.l  $46(a3),d0              ; gs_Head non vide ?
                lea     $4A(a3),a0
                cmp.l   a0,d0
                seq     d0
                bsr     phex2
                bra     nl

; --- ordre de la pile : tags et priorités depuis top_layer
order:          moveq   #'O',d1
                bsr     putc
                move.l  li-vars(a4),a0
                move.l  (a0),a3
.l:             move.l  a3,d0
                beq.s   .e
                bsr     sp1
                move.l  a3,d0
                bsr     tagof
                bsr     putc
                moveq   #':',d1
                bsr     putc
                move.w  $1C(a3),d0
                bsr     phex4
                move.l  4(a3),a3
                bra.s   .l
.e:             bra     nl

; --- toutes les couches de la pile
dumpall:        move.l  li-vars(a4),a0
                move.l  (a0),a3
.l:             move.l  a3,d0
                beq.s   .e
                move.l  a3,a2
                move.l  a3,d0
                bsr     tagof
                move.b  d1,d6
                move.l  a3,-(sp)
                bsr     dumpL
                move.l  (sp)+,a3
                move.l  4(a3),a3
                bra.s   .l
.e:             rts

; --- couche a2, tag d6
dumpL:          moveq   #'L',d1
                bsr     putc
                move.b  d6,d1
                bsr     putc
                bsr     sp1
                move.w  $1E(a2),d0
                bsr     phex4
                bsr     sp1
                move.w  $1C(a2),d0
                bsr     phex4
                bsr     sp1
                move.l  $10(a2),d0
                bsr     phex8
                move.l  $14(a2),d0
                bsr     phex8
                bsr     sp1
                move.w  $2C(a2),d0
                bsr     phex4
                move.w  $2E(a2),d0
                bsr     phex4
                bsr     sp1
                move.l  (a2),d0
                bsr     tagof
                bsr     putc
                move.l  4(a2),d0
                bsr     tagof
                bsr     putc
                bsr     sp1
                move.l  $40(a2),d0
                bsr     phex8
                bsr     nl
                move.l  8(a2),a3
                moveq   #'C',d5
                bsr     dumpcr
                move.l  $24(a2),a3
                moveq   #'S',d5
                bsr     dumpcr
                move.l  $9C(a2),d0
                beq.s   .nd
                move.l  d0,a3
                moveq   #' ',d1
                bsr     putc
                bsr     sp1
                moveq   #'D',d1
                bsr     putc
                bsr     sp1
                move.l  (a3),d0
                bsr     phex8
                move.l  4(a3),d0
                bsr     phex8
                move.l  8(a3),a3
.dl:            move.l  a3,d0
                beq.s   .de
                bsr     sp1
                move.l  8(a3),d0
                bsr     phex8
                move.l  12(a3),d0
                bsr     phex8
                move.l  (a3),a3
                bra.s   .dl
.de:            bsr     nl
.nd:            rts

; --- liste de ClipRects a3, lettre d5
dumpcr:         move.l  a3,d0
                beq.s   .e
                bsr     sp1
                bsr     sp1
                move.b  d5,d1
                bsr     putc
                bsr     sp1
                move.l  $10(a3),d0
                bsr     phex8
                move.l  $14(a3),d0
                bsr     phex8
                bsr     sp1
                move.l  8(a3),d0
                bsr     tagof
                bsr     putc
                bsr     sp1
                move.l  12(a3),d0
                beq.s   .nb
                move.l  d0,a0
                move.w  (a0),d0                 ; BytesPerRow
                bsr     phex4
                move.w  2(a0),d0                ; Rows
                bsr     phex4
                move.b  5(a0),d0                ; Depth
                bsr     phex2
                bra.s   .f
.nb:            moveq   #'-',d1
                bsr     putc
.f:             bsr     sp1
                move.l  $24(a3),d0
                bsr     phex8
                bsr     nl
                move.l  (a3),a3
                bra.s   dumpcr
.e:             rts

; --- d0 = pointeur -> d1 = lettre (A B C D S, 0, 1, sinon ?)
tagof:          moveq   #'0',d1
                tst.l   d0
                beq.s   .r
                moveq   #'1',d1
                cmp.l   #1,d0
                beq.s   .r
                moveq   #'A',d1
                cmp.l   lA-vars(a4),d0
                beq.s   .r
                moveq   #'B',d1
                cmp.l   lB-vars(a4),d0
                beq.s   .r
                moveq   #'C',d1
                cmp.l   lC-vars(a4),d0
                beq.s   .r
                moveq   #'D',d1
                cmp.l   lD-vars(a4),d0
                beq.s   .r
                moveq   #'S',d1
                cmp.l   lS-vars(a4),d0
                beq.s   .r
                moveq   #'?',d1
.r:             rts

nl:             moveq   #10,d1
                bra     putc
sp1:            moveq   #' ',d1
                bra     putc
phex8:          swap    d0
                bsr.s   phex4
                swap    d0
phex4:          move.w  d0,-(sp)
                lsr.w   #8,d0
                bsr.s   phex2
                move.w  (sp)+,d0
phex2:          move.w  d0,-(sp)
                lsr.b   #4,d0
                bsr.s   .n
                move.w  (sp)+,d0
.n:             move.w  d0,-(sp)
                and.w   #$F,d0
                move.b  hexd(pc,d0.w),d1
                bsr.s   putc
                move.w  (sp)+,d0
                rts
hexd:           dc.b    "0123456789ABCDEF"
puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr.s   putc
                bra.s   puts
.e:             rts
putc:           move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
                rts

rect1:          dc.w    10,5,29,14              ; dommages forcés dans A (coordonnées couche)
; pixels témoins : A seul, A∩B, A∩C, B seul, C seul, B∩C, hors tout
ppts:           dc.w    20,15, 70,40, 105,25, 130,80, 180,30, 140,40, 300,190, 205,35, -1
ppts2:          dc.w    20,15, 60,40, 100,50, 70,50, 140,85, 115,60, 62,36, -1
wpts:           dc.w    20,15, 70,40, 105,25, 130,80, 180,30, 300,190, 16,10, 115,59, -1

gfxname:        dc.b    "graphics.library",0
layname:        dc.b    "layers.library",0
m_start:        dc.b    10,"LYP debut",10,0
m_t0:           dc.b    "T0 ",0
m_t1:           dc.b    "T1 ",0
m_t2:           dc.b    "T2 ",0
m_t3:           dc.b    "T3 ",0
m_t4:           dc.b    "T4 ",0
m_t5:           dc.b    "T5 ",0
m_t6:           dc.b    "T6 ",0
m_t7:           dc.b    "T7 ",0
m_t8:           dc.b    "T8 ",0
m_t9:           dc.b    "T9 ",0
m_t10:          dc.b    "T10 ",0
m_t11:          dc.b    "T11 ",0
m_t12:          dc.b    "T12 ",0
m_t13:          dc.b    "T13 ",0
m_t14:          dc.b    "T14 ",0
m_t15:          dc.b    "T15 ",0
m_t16:          dc.b    "T16 ",0
m_t17:          dc.b    "T17 ",0
m_t20:          dc.b    "T20 ",0
m_t21:          dc.b    "T21 ",0
m_t22:          dc.b    "T22 ",0
m_t23:          dc.b    "T23 ",0
m_t24:          dc.b    "T24 ",0
m_end:          dc.b    "LYP fin",10,0
                even

vars:
gfxb:           dc.l    0
layb:           dc.l    0
chip:           dc.l    0
li:             dc.l    0
lA:             dc.l    0
lB:             dc.l    0
lC:             dc.l    0
lD:             dc.l    0
lS:             dc.l    0
scrbm:          ds.b    40
superbm:        ds.b    40
scrrp:          ds.b    100
sli:            ds.b    104
swcr:           dc.l    0
hogl:           dc.l    0
hogn:           dc.l    0
hogr:           dc.l    0
