; tests/gblit_probe.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Sonde boîte noire « blitter de graphics.library » (piste analyse, docs/analysis/graphics-blitter-v34.md).
; Lancée depuis la startup-sequence d'une disquette (tests/gblit_probe.sh). Appelle les fonctions blitter par
; leurs LVO publics et écrit chaque résultat sur le série direct (SERDAT), une ligne par test, en hexadécimal.
; Tous les tampons de données sont en CHIP (exigé par le blitter). Aucune RastPort n'a de Layer (chemin direct).
; Assemblage : vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/gblit_probe tests/gblit_probe.s
; Code auteur ; structures publiques (graphics/gfx.h, rastport.h, gfxbase.h, hardware/blit.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
CHIPSZ   EQU 12000
; décalages dans le bloc CHIP
O_BIGD   EQU 0          ; T3 destination (2200 o), placée AVANT la source
O_BIGS   EQU 2400       ; T3 source
O_OVG    EQU 4800       ; T5 garde basse (16 o)
O_OV     EQU 4816       ; T5 bitmap 8 o x 4 lignes
O_OVH    EQU 4848       ; T5 garde haute (16 o)
O_TBUF   EQU 4900       ; T5 TempA (16 o)
O_W2     EQU 5000       ; T4 destination 160 o x 2
O_W1     EQU 5400       ; T4 source 160 o x 2
O_CLR    EQU 5800       ; T6 3000 o
O_P1     EQU 9000       ; T1 plans (6 x 16 o)
O_T2S    EQU 9100
O_T2D    EQU 9102
O_TPL    EQU 9200       ; T7 gabarit 3 mots
O_TDST   EQU 9220       ; T7 destination 4 o
O_MS     EQU 9240       ; T8 source
O_MD     EQU 9260       ; T8 destination
O_MM     EQU 9280       ; T8 masque

LVO_BltBitMap   EQU -30
LVO_BltTemplate EQU -36
LVO_InitRastPort EQU -198
LVO_WaitBlit    EQU -228
LVO_QBlit       EQU -276
LVO_QBSBlit     EQU -294
LVO_BltClear    EQU -300
LVO_SetAPen     EQU -342
LVO_SetBPen     EQU -348
LVO_SetDrMd     EQU -354
LVO_OwnBlitter  EQU -456
LVO_DisownBlitter EQU -462
LVO_ClipBlit    EQU -552
LVO_BltBitMapRastPort EQU -606
LVO_BltMaskBitMapRastPort EQU -636

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
                move.l  #CHIPSZ,d0
                move.l  #$10003,d1
                jsr     -198(a6)
                move.l  d0,chip-vars(a4)
                beq     .out
                move.l  d0,a5
                lea     m_start(pc),a0
                bsr     puts
                move.l  gfxb-vars(a4),a6

; ---------- T1 : valeur rendue / masque de plans / profondeurs ----------
                lea     bmA-vars(a4),a0
                lea     O_P1(a5),a1
                moveq   #4,d0
                moveq   #2,d1
                moveq   #3,d2
                moveq   #16,d3
                bsr     setbm
                lea     bmB-vars(a4),a0
                lea     O_P1+48(a5),a1
                moveq   #4,d0
                moveq   #2,d1
                moveq   #3,d2
                moveq   #16,d3
                bsr     setbm
                lea     bmC-vars(a4),a0
                lea     O_P1(a5),a1
                moveq   #4,d0
                moveq   #2,d1
                moveq   #2,d2
                moveq   #16,d3
                bsr     setbm
                lea     m_t1(pc),a0
                bsr     puts
                moveq   #$05,d7
                lea     bmA-vars(a4),a0
                bsr     t1call
                moveq   #$00,d7
                lea     bmA-vars(a4),a0
                bsr     t1call
                move.l  #$FF,d7
                lea     bmC-vars(a4),a0
                bsr     t1call
                move.l  #$FF,d7
                lea     bmA-vars(a4),a0
                bsr     t1call
                bsr     nl

; ---------- T2 : quartet bas du minterm ----------
                lea     bmS1-vars(a4),a0
                lea     O_T2S(a5),a1
                moveq   #2,d0
                moveq   #1,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     bmD1-vars(a4),a0
                lea     O_T2D(a5),a1
                moveq   #2,d0
                moveq   #1,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                move.w  #$FF00,O_T2S(a5)
                lea     m_t2(pc),a0
                bsr     puts
                lea     mterms(pc),a3
.t2l:           move.w  (a3)+,d6
                bmi.s   .t2e
                move.w  #$F0F0,O_T2D(a5)
                lea     bmS1-vars(a4),a0
                lea     bmD1-vars(a4),a1
                moveq   #0,d0
                moveq   #0,d1
                moveq   #0,d2
                moveq   #0,d3
                moveq   #16,d4
                moveq   #1,d5
                moveq   #1,d7
                sub.l   a2,a2
                jsr     LVO_BltBitMap(a6)
                jsr     LVO_WaitBlit(a6)
                move.w  O_T2D(a5),d0
                bsr     phex4
                bsr     sp1
                bra.s   .t2l
.t2e:           bsr     nl

; ---------- T3 : hauteur nulle (destination avant la source, même BytesPerRow) ----------
                lea     O_BIGS(a5),a0
                move.w  #1099,d0
.t3f:           move.w  #$FFFF,(a0)+
                dbra    d0,.t3f
                lea     bmBS-vars(a4),a0
                lea     O_BIGS(a5),a1
                moveq   #2,d0
                move.w  #1100,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     bmBD-vars(a4),a0
                lea     O_BIGD(a5),a1
                moveq   #2,d0
                move.w  #1100,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     bmBS-vars(a4),a0
                lea     bmBD-vars(a4),a1
                moveq   #0,d0
                moveq   #0,d1
                moveq   #0,d2
                moveq   #0,d3
                moveq   #16,d4
                moveq   #0,d5
                move.l  #$C0,d6
                moveq   #1,d7
                sub.l   a2,a2
                jsr     LVO_BltBitMap(a6)
                move.l  d0,-(sp)
                jsr     LVO_WaitBlit(a6)
                lea     m_t3(pc),a0
                bsr     puts
                move.l  (sp)+,d0
                bsr     phex4
                bsr     sp1
                lea     O_BIGD(a5),a0
                move.w  #1099,d1
                moveq   #0,d0
.t3c:           tst.w   (a0)+
                beq.s   .t3n
                addq.l  #1,d0
.t3n:           dbra    d1,.t3c
                bsr     phex4
                bsr     nl

; ---------- T4 : largeur nulle à x=16 (destination avant la source) ----------
                lea     O_W1(a5),a0
                move.w  #159,d0
.t4f:           move.w  #$FFFF,(a0)+
                dbra    d0,.t4f
                lea     bmW1-vars(a4),a0
                lea     O_W1(a5),a1
                move.w  #160,d0
                moveq   #2,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     bmW2-vars(a4),a0
                lea     O_W2(a5),a1
                move.w  #160,d0
                moveq   #2,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     bmW1-vars(a4),a0
                lea     bmW2-vars(a4),a1
                moveq   #16,d0
                moveq   #0,d1
                moveq   #16,d2
                moveq   #0,d3
                moveq   #0,d4
                moveq   #1,d5
                move.l  #$C0,d6
                moveq   #1,d7
                sub.l   a2,a2
                jsr     LVO_BltBitMap(a6)
                jsr     LVO_WaitBlit(a6)
                lea     m_t4(pc),a0
                bsr     puts
                lea     O_W2(a5),a0
                move.w  #319,d1
                moveq   #0,d0
.t4c:           tst.b   (a0)+
                beq.s   .t4n
                addq.l  #1,d0
.t4n:           dbra    d1,.t4c
                bsr     phex4
                bsr     sp1
                move.w  O_W2+2(a5),d0           ; premier mot écrit attendu
                bsr     phex4
                bsr     sp1
                move.w  O_W2+128(a5),d0         ; dernier mot écrit attendu (64e)
                bsr     phex4
                bsr     sp1
                move.w  O_W2+130(a5),d0         ; au-delà
                bsr     phex4
                bsr     nl

; ---------- T5 : recouvrements dans une même BitMap (BytesPerRow 8, 4 lignes) ----------
                lea     bmOV-vars(a4),a0
                lea     O_OV(a5),a1
                moveq   #8,d0
                moveq   #4,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     t5tab(pc),a3
                moveq   #1,d7
.t5l:           tst.w   (a3)
                bmi     .t5e
                bsr     ovfill
                lea     m_t5(pc),a0
                bsr     puts
                move.l  d7,d0
                bsr     phex2
                bsr     sp1
                lea     bmOV-vars(a4),a0
                lea     bmOV-vars(a4),a1
                movem.w (a3)+,d0-d5
                ext.l   d0
                ext.l   d1
                ext.l   d2
                ext.l   d3
                ext.l   d4
                ext.l   d5
                lea     O_TBUF(a5),a2
                tst.w   (a3)+
                bne.s   .t5t
                sub.l   a2,a2
.t5t:           move.l  d7,-(sp)
                move.l  #$C0,d6
                moveq   #1,d7
                jsr     LVO_BltBitMap(a6)
                jsr     LVO_WaitBlit(a6)
                move.l  (sp)+,d7
                lea     O_OV(a5),a0
                moveq   #31,d2
.t5d:           move.b  (a0)+,d0
                bsr     phex2
                dbra    d2,.t5d
                bsr     sp1
                lea     O_TBUF(a5),a0
                moveq   #7,d2
.t5b:           move.w  (a0)+,d0
                bsr     phex4
                dbra    d2,.t5b
                bsr     sp1
                lea     O_OVG(a5),a0            ; gardes intactes ?
                moveq   #0,d0
                moveq   #15,d2
.t5g1:          cmp.b   #$77,(a0)+
                beq.s   .t5g2
                addq.l  #1,d0
.t5g2:          dbra    d2,.t5g1
                lea     O_OVH(a5),a0
                moveq   #15,d2
.t5g3:          cmp.b   #$77,(a0)+
                beq.s   .t5g4
                addq.l  #1,d0
.t5g4:          dbra    d2,.t5g3
                bsr     phex2
                bsr     nl
                addq.l  #1,d7
                bra     .t5l
.t5e:

; ---------- T6 : BltClear ----------
                lea     m_t6(pc),a0
                bsr     puts
                bsr     clrfill
                lea     O_CLR(a5),a1
                moveq   #7,d0
                moveq   #1,d1
                jsr     LVO_BltClear(a6)
                lea     O_CLR(a5),a0
                moveq   #7,d2
.t6d:           move.b  (a0)+,d0
                bsr     phex2
                dbra    d2,.t6d
                bsr     sp1
                bsr     clrfill
                lea     O_CLR(a5),a1
                move.l  #(1100<<16)|2,d0
                moveq   #3,d1
                jsr     LVO_BltClear(a6)
                bsr     clrcount
                bsr     sp1
                bsr     clrfill
                lea     O_CLR(a5),a1
                move.l  #(3<<16)|130,d0
                moveq   #3,d1
                jsr     LVO_BltClear(a6)
                bsr     clrcount
                bsr     sp1
                bsr     clrfill
                lea     O_CLR(a5),a1
                move.l  #130,d0
                moveq   #1,d1
                jsr     LVO_BltClear(a6)
                bsr     clrcount
                bsr     sp1
                bsr     clrfill
                lea     O_CLR(a5),a1
                move.l  #(5<<16)|8,d0
                moveq   #3,d1
                jsr     LVO_BltClear(a6)
                bsr     clrcount
                bsr     nl

; ---------- T7 : BltTemplate sans Layer, xSrc 0/16/4 ----------
                lea     rpT-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     bmT-vars(a4),a0
                lea     O_TDST(a5),a1
                moveq   #4,d0
                moveq   #1,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     rpT-vars(a4),a1
                lea     bmT-vars(a4),a0
                move.l  a0,4(a1)
                moveq   #1,d0
                jsr     LVO_SetAPen(a6)
                lea     rpT-vars(a4),a1
                moveq   #0,d0
                jsr     LVO_SetBPen(a6)
                lea     rpT-vars(a4),a1
                moveq   #1,d0
                jsr     LVO_SetDrMd(a6)
                move.l  #$0000FFFF,O_TPL(a5)
                move.w  #$0F0F,O_TPL+4(a5)
                lea     m_t7(pc),a0
                bsr     puts
                lea     t7xs(pc),a3
.t7l:           move.w  (a3)+,d0
                bmi.s   .t7e
                ext.l   d0
                move.l  #$55555555,O_TDST(a5)
                lea     O_TPL(a5),a0
                moveq   #6,d1
                lea     rpT-vars(a4),a1
                moveq   #0,d2
                moveq   #0,d3
                moveq   #16,d4
                moveq   #1,d5
                jsr     LVO_BltTemplate(a6)
                jsr     LVO_WaitBlit(a6)
                move.l  O_TDST(a5),d0
                bsr     phex8
                bsr     sp1
                bra.s   .t7l
.t7e:           bsr     nl

; ---------- T8 : BltMaskBitMapRastPort, BltBitMapRastPort, ClipBlit (sans Layer) ----------
                lea     rpM-vars(a4),a1
                jsr     LVO_InitRastPort(a6)
                lea     bmMD-vars(a4),a0
                lea     O_MD(a5),a1
                moveq   #4,d0
                moveq   #1,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     bmMS-vars(a4),a0
                lea     O_MS(a5),a1
                moveq   #4,d0
                moveq   #1,d1
                moveq   #1,d2
                moveq   #0,d3
                bsr     setbm
                lea     rpM-vars(a4),a1
                lea     bmMD-vars(a4),a0
                move.l  a0,4(a1)
                move.l  #$FF00FF00,O_MS(a5)
                move.l  #$FFFF0000,O_MM(a5)
                lea     m_t8(pc),a0
                bsr     puts
                move.l  #$E0,d6
                lea     O_MM(a5),a2
                bsr     t8call
                move.l  #$20,d6
                lea     O_MM(a5),a2
                bsr     t8call
                move.l  #$E0,d6
                sub.l   a2,a2
                bsr     t8call
                ; BltBitMapRastPort : valeur rendue
                move.l  #$0F0F0F0F,O_MD(a5)
                lea     bmMS-vars(a4),a0
                moveq   #0,d0
                moveq   #0,d1
                lea     rpM-vars(a4),a1
                moveq   #0,d2
                moveq   #0,d3
                moveq   #32,d4
                moveq   #1,d5
                move.l  #$C0,d6
                jsr     LVO_BltBitMapRastPort(a6)
                move.l  d0,-(sp)
                jsr     LVO_WaitBlit(a6)
                move.l  (sp)+,d0
                bsr     phex8
                bsr     sp1
                move.l  O_MD(a5),d0
                bsr     phex8
                bsr     sp1
                ; ClipBlit même RastPort, sans Layer : valeur rendue
                lea     rpM-vars(a4),a0
                moveq   #0,d0
                moveq   #0,d1
                lea     rpM-vars(a4),a1
                moveq   #16,d2
                moveq   #0,d3
                moveq   #16,d4
                moveq   #1,d5
                move.l  #$C0,d6
                jsr     LVO_ClipBlit(a6)
                move.l  d0,-(sp)
                jsr     LVO_WaitBlit(a6)
                move.l  (sp)+,d0
                bsr     phex8
                bsr     sp1
                move.l  O_MD(a5),d0
                bsr     phex8
                bsr     nl

; ---------- T9 : OwnBlitter / DisownBlitter, BlitLock ($AA) et BlitOwner ($BC) ----------
                lea     m_t9(pc),a0
                bsr     puts
                move.w  $AA(a6),d0
                bsr     phex4
                bsr     sp1
                jsr     LVO_OwnBlitter(a6)
                move.w  $AA(a6),d0
                bsr     phex4
                bsr     sp1
                move.l  $BC(a6),d0
                bsr     phex8
                bsr     sp1
                jsr     LVO_DisownBlitter(a6)
                move.w  $AA(a6),d0
                bsr     phex4
                bsr     sp1
                move.w  $A8(a6),d0
                bsr     phex4
                bsr     nl

; ---------- T10 : QBlit (appel synchrone ? registres ? reprise si non nul ? cleanup ?) ----------
                lea     m_t10(pc),a0
                bsr     puts
                lea     node1-vars(a4),a1
                clr.l   (a1)
                lea     qf1(pc),a0
                move.l  a0,4(a1)
                clr.b   8(a1)
                clr.w   $A(a1)
                clr.w   $C(a1)
                clr.l   $E(a1)
                clr.l   qcnt-vars(a4)
                move.b  #1,inq-vars(a4)
                jsr     LVO_QBlit(a6)
                clr.b   inq-vars(a4)
                move.l  qcnt-vars(a4),d0
                bsr     phex2
                bsr     sp1
                move.b  qinq-vars(a4),d0
                bsr     phex2
                bsr     sp1
                move.l  qa0-vars(a4),d0
                bsr     phex8
                bsr     sp1
                lea     node1-vars(a4),a0
                move.l  qa1-vars(a4),d0
                cmp.l   a0,d0
                seq     d0
                bsr     phex2
                bsr     sp1
                move.w  qsr-vars(a4),d0
                bsr     phex4
                bsr     sp1
                move.l  qa6-vars(a4),d0
                cmp.l   a6,d0
                seq     d0
                bsr     phex2
                bsr     sp1
                ; nœud 2 : rend non nul deux fois sans lancer de blit, CLEANUP demandé
                lea     node1-vars(a4),a1
                clr.l   (a1)
                lea     qf2(pc),a0
                move.l  a0,4(a1)
                move.b  #$40,8(a1)
                lea     qcl(pc),a0
                move.l  a0,$E(a1)
                clr.l   qcnt-vars(a4)
                clr.l   qclc-vars(a4)
                move.b  #1,inq-vars(a4)
                jsr     LVO_QBlit(a6)
                clr.b   inq-vars(a4)
                move.l  qcnt-vars(a4),d0
                bsr     phex2
                bsr     sp1
                move.l  qclc-vars(a4),d0
                bsr     phex2
                bsr     sp1
                move.b  qinq-vars(a4),d0
                bsr     phex2
                bsr     nl

; ---------- T11 : QBSBlit, beamsync = 200 demandé vers la ligne 50 ----------
                lea     m_t11(pc),a0
                bsr     puts
                moveq   #1,d3
.t11r:          lea     node1-vars(a4),a1
                clr.l   (a1)
                lea     qf3(pc),a0
                move.l  a0,4(a1)
                clr.b   8(a1)
                move.w  #200,$C(a1)
                clr.b   qdone-vars(a4)
                clr.w   qline-vars(a4)
.t11w:          move.l  $DFF004,d0
                lsr.l   #8,d0
                and.w   #$1FF,d0
                cmp.w   #50,d0
                bne.s   .t11w
                move.w  d0,d4
                move.b  #1,inq-vars(a4)
                lea     node1-vars(a4),a1
                jsr     LVO_QBSBlit(a6)
                clr.b   inq-vars(a4)
                move.l  $DFF004,d5
                lsr.l   #8,d5
                and.w   #$1FF,d5
                move.l  #400000,d2
.t11p:          tst.b   qdone-vars(a4)
                bne.s   .t11k
                subq.l  #1,d2
                bne.s   .t11p
.t11k:          move.w  d4,d0
                bsr     phex4
                bsr     sp1
                move.w  d5,d0
                bsr     phex4
                bsr     sp1
                move.b  qdone-vars(a4),d0
                bsr     phex2
                bsr     sp1
                move.w  qline-vars(a4),d0
                bsr     phex4
                bsr     sp1
                move.b  qinq-vars(a4),d0
                bsr     phex2
                bsr     sp1
                move.b  $A0(a6),d0
                bsr     phex2
                bsr     sp1
                move.w  $A2(a6),d0
                bsr     phex4
                bsr     sp1
                dbra    d3,.t11r
                bsr     nl

                lea     m_end(pc),a0
                bsr     puts
                move.l  4.w,a6
                move.l  chip-vars(a4),a1
                move.l  #CHIPSZ,d0
                jsr     -210(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; --- T1 : BltBitMap(a0 -> bmB) 16x1, masque d7, imprime D0
t1call:         lea     bmB-vars(a4),a1
                moveq   #0,d0
                moveq   #0,d1
                moveq   #0,d2
                moveq   #0,d3
                moveq   #16,d4
                moveq   #1,d5
                move.l  #$C0,d6
                sub.l   a2,a2
                jsr     LVO_BltBitMap(a6)
                move.l  d0,-(sp)
                jsr     LVO_WaitBlit(a6)
                move.l  (sp)+,d0
                bsr     phex8
                bra     sp1

; --- T8 : BltMaskBitMapRastPort(bmMS -> rpM) 32x1, minterm d6, masque a2
t8call:         move.l  #$0F0F0F0F,O_MD(a5)
                lea     bmMS-vars(a4),a0
                moveq   #0,d0
                moveq   #0,d1
                lea     rpM-vars(a4),a1
                moveq   #0,d2
                moveq   #0,d3
                moveq   #32,d4
                moveq   #1,d5
                jsr     LVO_BltMaskBitMapRastPort(a6)
                jsr     LVO_WaitBlit(a6)
                move.l  O_MD(a5),d0
                bsr     phex8
                bra     sp1

; --- fonctions QBlit (a0 = custom, a1 = nœud attendus)
qf1:            move.l  a2,-(sp)
                lea     vars(pc),a2
                addq.l  #1,qcnt-vars(a2)
                move.l  a0,qa0-vars(a2)
                move.l  a1,qa1-vars(a2)
                move.l  a6,qa6-vars(a2)
                move.w  sr,qsr-vars(a2)
                move.b  inq-vars(a2),qinq-vars(a2)
                move.l  (sp)+,a2
                moveq   #0,d0
                rts
qf2:            move.l  a2,-(sp)
                lea     vars(pc),a2
                addq.l  #1,qcnt-vars(a2)
                move.b  inq-vars(a2),qinq-vars(a2)
                move.l  qcnt-vars(a2),d0
                move.l  (sp)+,a2
                cmp.l   #3,d0
                bcc.s   .z
                moveq   #1,d0
                rts
.z:             moveq   #0,d0
                rts
qcl:            move.l  a2,-(sp)
                lea     vars(pc),a2
                addq.l  #1,qclc-vars(a2)
                move.l  (sp)+,a2
                rts
qf3:            move.l  a2,-(sp)
                lea     vars(pc),a2
                move.l  $DFF004,d0
                lsr.l   #8,d0
                and.w   #$1FF,d0
                move.w  d0,qline-vars(a2)
                move.b  inq-vars(a2),qinq-vars(a2)
                move.b  #1,qdone-vars(a2)
                move.l  (sp)+,a2
                moveq   #0,d0
                rts

; --- setbm : a0 = BitMap, d0 = BytesPerRow, d1 = Rows, d2 = Depth, a1 = plan 0, d3 = pas entre plans
setbm:          move.w  d0,(a0)
                move.w  d1,2(a0)
                clr.b   4(a0)
                move.b  d2,5(a0)
                clr.w   6(a0)
                lea     8(a0),a0
                moveq   #7,d0
.c:             clr.l   (a0)+
                dbra    d0,.c
                lea     -32(a0),a0
                subq.w  #1,d2
.p:             move.l  a1,(a0)+
                add.l   d3,a1
                dbra    d2,.p
                rts

; --- T5 : motif d'octets (i*37+11) et gardes $77, TempA à $DEAD
ovfill:         lea     O_OVG(a5),a0
                moveq   #15,d0
.g1:            move.b  #$77,(a0)+
                dbra    d0,.g1
                moveq   #11,d1
                moveq   #31,d0
.f:             move.b  d1,(a0)+
                add.b   #37,d1
                dbra    d0,.f
                moveq   #15,d0
.g2:            move.b  #$77,(a0)+
                dbra    d0,.g2
                lea     O_TBUF(a5),a0
                moveq   #7,d0
.t:             move.w  #$DEAD,(a0)+
                dbra    d0,.t
                rts

clrfill:        lea     O_CLR(a5),a0
                move.w  #2999,d0
.f:             move.b  #$55,(a0)+
                dbra    d0,.f
                rts
clrcount:       lea     O_CLR(a5),a0
                move.w  #2999,d1
                moveq   #0,d0
.c:             tst.b   (a0)+
                bne.s   .n
                addq.l  #1,d0
.n:             dbra    d1,.c
                bra     phex4

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

mterms:         dc.w    $C0,$CF,$C5,$60,$6A,$30,$0A,-1
; sx,sy,dx,dy,w,h,tempA(1 = tampon fourni)
t5tab:          dc.w    5,0,2,0,40,3,1
                dc.w    2,0,5,0,40,3,1
                dc.w    20,0,3,0,30,3,1
                dc.w    3,0,20,0,30,3,1
                dc.w    0,0,16,0,32,3,1
                dc.w    16,0,0,0,32,3,1
                dc.w    4,0,4,1,40,3,1
                dc.w    4,1,4,0,40,3,1
                dc.w    6,1,3,0,40,3,1
                dc.w    3,0,6,1,40,3,1
                dc.w    5,0,2,0,40,3,0
                dc.w    2,0,5,0,40,3,0
                dc.w    9,2,1,0,20,2,1
                dc.w    1,0,9,2,20,2,1
                dc.w    -1
t7xs:           dc.w    0,16,4,-1

gfxname:        dc.b    "graphics.library",0
m_start:        dc.b    10,"GBP debut",10,0
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
m_end:          dc.b    "GBP fin",10,0
                even

vars:
gfxb:           dc.l    0
chip:           dc.l    0
qcnt:           dc.l    0
qclc:           dc.l    0
qa0:            dc.l    0
qa1:            dc.l    0
qa6:            dc.l    0
qsr:            dc.w    0
qline:          dc.w    0
inq:            dc.b    0
qinq:           dc.b    0
qdone:          dc.b    0
                even
node1:          ds.b    20
bmA:            ds.b    40
bmB:            ds.b    40
bmC:            ds.b    40
bmS1:           ds.b    40
bmD1:           ds.b    40
bmBS:           ds.b    40
bmBD:           ds.b    40
bmW1:           ds.b    40
bmW2:           ds.b    40
bmOV:           ds.b    40
bmT:            ds.b    40
bmMS:           ds.b    40
bmMD:           ds.b    40
rpT:            ds.b    100
rpM:            ds.b    100
