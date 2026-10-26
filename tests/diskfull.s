; diskfull.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Sonde du comportement « disque plein » (spec docs/analysis/disk-full-write-v34.md), à lancer depuis la
; startup-sequence d'une disquette DF0: inscriptible ayant moins de 200000 octets libres.
; Assembler avec -kick1hunks (la 1.3 refuse HUNK_DREL32). Deux lignes par étape, sur Output() :
;   <lettre> r1 r2
;    pos used
;     r1/r2 = dp_Res1/dp_Res2 (packet brut) ou valeur rendue/IoErr (appel dos) ; pr_Result2 remis à 0 avant
;     pos   = Seek(fh, 0, OFFSET_CURRENT) après l'étape ; used = id_NumBlocksUsed de Info(lock "df0:")
;   A  Open("df0:big", MODE_NEWFILE) : r1 = fh
;   B  packet ACTION_WRITE brut, 200000 octets
;   C  packet ACTION_WRITE brut, 1000 octets
;   D  dos Write(fh, 1000)
;   E  packet ACTION_WRITE brut, 200000 octets, depuis pos 2000 (au-delà des blocs déjà alloués)
;   F  dos Write(fh, 200000)
;   G  dos Write(fh, 1000) (disque plein)
;   H  Close(fh) : pos non significatif
;   I  Open("df0:big3", MODE_NEWFILE) (disque plein) : r1 = fh
;   ZZ fin
; Code auteur, structures publiques (exec/dos 1.3).

ACTION_WRITE    EQU     87
pr_MsgPort      EQU     $5C
pr_Result2      EQU     $94
SRC             EQU     $FC0000

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                lea     dosbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                sub.l   a1,a1
                jsr     -294(a6)             ; FindTask(0)
                lea     proc(pc),a0
                move.l  d0,(a0)
                move.l  #nroot,d1
                moveq   #-2,d2
                move.l  dosbase(pc),a6
                jsr     -84(a6)              ; Lock("df0:", SHARED)
                lea     rlock(pc),a0
                move.l  d0,(a0)
; A
                bsr     clr2
                move.l  #nbig,d1
                move.l  #1006,d2
                move.l  dosbase(pc),a6
                jsr     -30(a6)              ; Open
                move.l  d0,d7
                moveq   #'A',d1
                bsr     dosline
                tst.l   d7
                beq     .done
; B
                move.l  #200000,d5
                moveq   #'B',d1
                bsr     rawwrite
; C
                move.l  #1000,d5
                moveq   #'C',d1
                bsr     rawwrite
; D
                move.l  #1000,d5
                moveq   #'D',d1
                bsr     doswrite
; E
                move.l  #200000,d5
                moveq   #'E',d1
                bsr     rawwrite
; F
                move.l  #200000,d5
                moveq   #'F',d1
                bsr     doswrite
; G
                move.l  #1000,d5
                moveq   #'G',d1
                bsr     doswrite
; H
                bsr     clr2
                move.l  d7,d1
                move.l  dosbase(pc),a6
                jsr     -36(a6)              ; Close
                moveq   #0,d7
                moveq   #'H',d1
                bsr     dosline
; I
                bsr     clr2
                move.l  #nbig3,d1
                move.l  #1006,d2
                move.l  dosbase(pc),a6
                jsr     -30(a6)
                move.l  d0,d7
                moveq   #'I',d1
                bsr     dosline
                tst.l   d7
                beq     .done
                move.l  d7,d1
                move.l  dosbase(pc),a6
                jsr     -36(a6)
.done:
                lea     line,a4
                move.b  #'Z',(a4)+
                move.b  #'Z',(a4)+
                bsr     flush
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; dos Write(d7, SRC, d5), puis ligne (lettre d1)
doswrite:
                move.l  d1,d6
                bsr     clr2
                move.l  d7,d1
                move.l  #SRC,d2
                move.l  d5,d3
                move.l  dosbase(pc),a6
                jsr     -48(a6)              ; Write
                move.l  d6,d1
                bra     dosline

; ligne « lettre d0 IoErr pos used » (d1 = lettre, d0 = valeur rendue)
dosline:
                move.l  d0,d6
                lea     line,a4
                move.b  d1,(a4)+
                move.b  #' ',(a4)+
                move.l  d6,d0
                bsr     hex
                move.l  dosbase(pc),a6
                jsr     -132(a6)             ; IoErr
                bsr     hex
                bra     tail

; packet ACTION_WRITE brut de d5 octets depuis SRC sur le FileHandle d7, puis ligne (lettre d1)
rawwrite:
                move.l  d1,d6
                lea     pkt,a0
                lea     20(a0),a1            ; DosPacket
                move.l  a1,10(a0)            ; ln_Name = DosPacket
                move.l  a0,(a1)              ; dp_Link = Message
                move.l  proc(pc),a2
                lea     pr_MsgPort(a2),a3
                move.l  a3,4(a1)             ; dp_Port
                move.l  #ACTION_WRITE,8(a1)
                move.l  #$DEADBEEF,12(a1)
                move.l  #$DEADBEEF,16(a1)
                move.l  d7,d0
                lsl.l   #2,d0
                move.l  d0,a2
                move.l  $24(a2),20(a1)       ; dp_Arg1 = fh_Args
                move.l  #SRC,24(a1)
                move.l  d5,28(a1)
                move.l  8(a2),a0             ; fh_Type = port du handler
                lea     pkt,a1
                move.l  4.w,a6
                jsr     -366(a6)             ; PutMsg
                move.l  a3,a0
                jsr     -384(a6)             ; WaitPort
                move.l  a3,a0
                jsr     -372(a6)             ; GetMsg
                lea     line,a4
                move.b  d6,(a4)+
                move.b  #' ',(a4)+
                lea     pkt+20,a0
                move.l  12(a0),d0
                bsr     hex
                lea     pkt+20,a0
                move.l  16(a0),d0
                bsr     hex
                bra     tail

; ajoute pos et used puis écrit la ligne
tail:
                bsr     flush                ; résultat d'abord : Seek/Info ne doivent pas le masquer
                lea     line,a4
                move.b  #' ',(a4)+
                moveq   #-1,d0
                tst.l   d7
                beq.s   .np
                move.l  d7,d1
                moveq   #0,d2
                moveq   #0,d3                ; OFFSET_CURRENT
                move.l  dosbase(pc),a6
                jsr     -66(a6)              ; Seek
.np:            bsr     hex
                moveq   #-1,d0
                move.l  rlock(pc),d1
                beq.s   .nu
                move.l  #info,d2
                move.l  dosbase(pc),a6
                jsr     -114(a6)             ; Info
                move.l  info+16,d0           ; id_NumBlocksUsed
.nu:            bsr     hex
                bra     flush

clr2:           move.l  proc(pc),a0
                clr.l   pr_Result2(a0)
                rts

hex:            moveq   #7,d3
.hl:            rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:             move.b  d1,(a4)+
                dbra    d3,.hl
                move.b  #' ',(a4)+
                rts

flush:                                       ; Write(Output(), line, a4 - line) avec saut de ligne
                move.b  #10,(a4)+
                move.l  dosbase(pc),a6
                jsr     -60(a6)              ; Output
                move.l  d0,d1
                lea     line,a0
                move.l  a0,d2
                move.l  a4,d3
                sub.l   a0,d3
                jsr     -48(a6)              ; Write
                rts

dosbase:        dc.l    0
proc:           dc.l    0
rlock:          dc.l    0
dosname:        dc.b    'dos.library',0
nroot:          dc.b    'df0:',0
nbig:           dc.b    'df0:big',0
nbig3:          dc.b    'df0:big3',0

                section bss,bss
                cnop    0,4
pkt:            ds.l    20
info:           ds.l    10
line:           ds.b    80
