; tests/tdwrite.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Sonde boîte noire « écriture trackdisk » (piste analyse, docs/analysis/trackdisk-write-v34.md).
; Lancée depuis la startup-sequence d'une disquette OFS vierge (tests/tdwrite_run.sh). Envoie une suite de
; requêtes à trackdisk.device unité 0 et écrit chaque résultat sur le série direct (SERDAT), une ligne par étape :
;   « <étape> E=<io_Error> A=<io_Actual> L=<premier long lu> » (hex).
; io_Actual est préchargé à $DEADBEEF avant chaque requête pour voir s'il est modifié.
; Blocs utilisés : 1100 (piste 100), 220 (piste 20), piste 158 (formatée). Tampons en CHIP (exigé par le blitter).
; Assemblage : vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/tdwrite tests/tdwrite.s
; Code auteur ; structures publiques (exec/io.h, devices/trackdisk.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
IO_CMD   EQU $1C
IO_ERR   EQU $1F
IO_ACT   EQU $20
IO_LEN   EQU $24
IO_DATA  EQU $28
IO_OFF   EQU $2C
TRKB     EQU 11*512

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  #TRKB,d0
                move.l  #$10003,d1              ; MEMF_CHIP|MEMF_CLEAR
                jsr     -198(a6)
                move.l  d0,buf-vars(a4)
                beq     .out
                sub.l   a1,a1
                jsr     -294(a6)                ; FindTask(0)
                lea     port(pc),a2
                move.l  d0,16(a2)
                moveq   #-1,d0
                jsr     -330(a6)                ; AllocSignal
                move.b  d0,15(a2)
                move.b  #4,8(a2)
                lea     20(a2),a0
                move.l  a0,8(a0)
                addq.l  #4,a0
                clr.l   (a0)
                move.l  a0,-(a0)
                lea     ioreq(pc),a1
                move.b  #5,8(a1)
                move.l  a2,14(a1)
                move.w  #$38,18(a1)
                lea     tdname(pc),a0
                moveq   #0,d0
                moveq   #0,d1
                jsr     -444(a6)                ; OpenDevice
                tst.l   d0
                bne     .out
                lea     msg0(pc),a0
                bsr     puts
; A : lecture bloc 1100 (piste 100)
                moveq   #'A',d7
                moveq   #2,d2
                move.l  #1100*512,d3
                move.l  #512,d4
                bsr     doio
; B : écriture motif 11111111 sur 1100 (tampon seulement)
                move.l  #$11111111,d0
                bsr     fill
                moveq   #'B',d7
                moveq   #3,d2
                bsr     doio
; C : CMD_CLEAR
                moveq   #'C',d7
                moveq   #5,d2
                bsr     doio
; D : relecture 1100 (ancien contenu attendu si CLEAR jette le tampon)
                moveq   #'D',d7
                moveq   #2,d2
                bsr     doio
; E : réécriture 22222222 + F : CMD_UPDATE + G : CLEAR + relecture
                move.l  #$22222222,d0
                bsr     fill
                moveq   #'E',d7
                moveq   #3,d2
                bsr     doio
                moveq   #'F',d7
                moveq   #4,d2
                bsr     doio
                moveq   #'g',d7
                moveq   #5,d2
                bsr     doio
                moveq   #'G',d7
                moveq   #2,d2
                bsr     doio
; H : écriture longueur 0 (motif 33333333), UPDATE, CLEAR, relecture
                move.l  #$33333333,d0
                bsr     fill
                moveq   #'H',d7
                moveq   #3,d2
                moveq   #0,d4
                bsr     doio
                move.l  #512,d4
                moveq   #'h',d7
                moveq   #4,d2
                bsr     doio
                moveq   #'i',d7
                moveq   #5,d2
                bsr     doio
                moveq   #'I',d7
                moveq   #2,d2
                bsr     doio
; J : écriture + UPDATE sur la piste 20 (bloc 220), comparaison precomp au journal disque
                move.l  #$44444444,d0
                bsr     fill
                moveq   #'J',d7
                moveq   #3,d2
                move.l  #220*512,d3
                bsr     doio
                moveq   #'j',d7
                moveq   #4,d2
                bsr     doio
; K : TD_FORMAT longueur 512 (non multiple d'une piste)
                moveq   #'K',d7
                moveq   #11,d2
                move.l  #158*TRKB,d3
                bsr     doio
; L : TD_FORMAT piste 158 entière, motif 55555555, puis relecture
                move.l  #$55555555,d0
                bsr     fill
                moveq   #'L',d7
                moveq   #11,d2
                move.l  #TRKB,d4
                bsr     doio
                move.l  #512,d4
                moveq   #'l',d7
                moveq   #2,d2
                bsr     doio
; M : TD_PROTSTATUS ; N : CMD_WRITE décalage impair ; O : TD_MOTOR 0 (état précédent dans io_Actual)
                moveq   #'M',d7
                moveq   #15,d2
                bsr     doio
                moveq   #'N',d7
                moveq   #3,d2
                move.l  #100,d3
                bsr     doio
                moveq   #'O',d7
                moveq   #9,d2
                moveq   #0,d4
                bsr     doio
                lea     msg1(pc),a0
                bsr     puts
                lea     ioreq(pc),a1
                jsr     -450(a6)                ; CloseDevice
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; fill(d0) : remplit le tampon (une piste, 5632 octets) avec le long d0
fill:           move.l  buf(pc),a0
                move.w  #TRKB/4-1,d1
.f:             move.l  d0,(a0)+
                dbra    d1,.f
                rts

; doio : commande d2, offset d3, longueur d4, étiquette d7 ; affiche le résultat
doio:           lea     ioreq(pc),a1
                move.w  d2,IO_CMD(a1)
                clr.b   30(a1)
                move.l  #$DEADBEEF,IO_ACT(a1)
                move.l  d4,IO_LEN(a1)
                move.l  buf(pc),IO_DATA(a1)
                move.l  d3,IO_OFF(a1)
                cmp.w   #2,d2
                bne.s   .nr
                move.l  buf(pc),a0
                clr.l   (a0)
.nr:            jsr     -456(a6)                ; DoIO
                move.b  d7,d1
                bsr     putc
                moveq   #' ',d1
                bsr     putc
                moveq   #'E',d1
                bsr     putc
                lea     ioreq(pc),a1
                move.b  IO_ERR(a1),d0
                moveq   #1,d5
                bsr     hex
                moveq   #'A',d1
                bsr     putc
                lea     ioreq(pc),a1
                move.l  IO_ACT(a1),d0
                moveq   #7,d5
                bsr     hex
                moveq   #'L',d1
                bsr     putc
                move.l  buf(pc),a0
                move.l  (a0),d0
                moveq   #7,d5
                bsr     hex
                moveq   #10,d1
                bra.s   putc

; hex : d0 sur d5+1 chiffres, puis espace
hex:            move.l  d0,d6
                move.w  d5,d1
                addq.w  #1,d1
                lsl.w   #2,d1
                ror.l   d1,d6
.h:             rol.l   #4,d6
                move.b  d6,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:             bsr.s   putc
                dbra    d5,.h
                moveq   #' ',d1
                bra.s   putc

puts:           move.b  (a0)+,d1
                beq.s   .e
                bsr.s   putc
                bra.s   puts
.e:             rts

putc:           move.w  SERDATR,d0
                btst    #13,d0
                beq.s   putc
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                rts

vars:
buf:            dc.l    0
port:           ds.b    34
                even
ioreq:          ds.b    $38
tdname:         dc.b    "trackdisk.device",0
msg0:           dc.b    10,"TDW debut",10,0
msg1:           dc.b    "TDW fin",10,0
                even
