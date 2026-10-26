; tests/cfgdev2.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM) : variante étendue de tests/cfgdev.s.
; Écrit sur la sortie du CLI une ligne par ConfigDev (FindConfigDev(prev, -1, -1)) :
;   « CD BoardAddr BoardSize Flags/Type/Product/ErFlags Manufacturer SlotAddr/SlotSize
;        InitDiagVec er_Reserved0c..0f cd_Driver ln_Type<<16|cd_Pad »
; puis une ligne par MemHeader d'ExecBase->MemList : « MH bas haut attributs<<16|ln_Type<<8|priorité libre nom ».
; Vecteurs attendus (vraie ROM 34.5) : docs/analysis/autoconfig-v34.md §8. Lancer « cfgdev2 >SER: » pour capturer en série.
; Clean-room : structures publiques, code auteur.

EB_MEMLIST EQU $142

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
                lea     expname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,d6
                beq     .mem
                suba.l  a3,a3
.cd:
                move.l  d6,a6
                move.l  a3,a0
                moveq   #-1,d0
                moveq   #-1,d1
                jsr     -72(a6)              ; FindConfigDev(prev a0, manu d0, prod d1)
                tst.l   d0
                beq     .mem
                move.l  d0,a3
                lea     line(pc),a1
                lea     t_cd(pc),a0
                bsr     cpy
                move.l  32(a3),d0            ; cd_BoardAddr
                bsr     hex
                move.l  36(a3),d0            ; cd_BoardSize
                bsr     hex
                move.b  14(a3),d0            ; cd_Flags
                lsl.l   #8,d0
                move.b  16(a3),d0            ; er_Type
                lsl.l   #8,d0
                move.b  17(a3),d0            ; er_Product
                lsl.l   #8,d0
                move.b  18(a3),d0            ; er_Flags
                bsr     hex
                moveq   #0,d0
                move.w  20(a3),d0            ; er_Manufacturer
                bsr     hex
                move.l  40(a3),d0            ; cd_SlotAddr, cd_SlotSize
                bsr     hex
                moveq   #0,d0
                move.w  26(a3),d0            ; er_InitDiagVec
                bsr     hex
                move.l  28(a3),d0            ; er_Reserved0c..0f
                bsr     hex
                move.l  44(a3),d0            ; cd_Driver
                bsr     hex
                moveq   #0,d0
                move.b  8(a3),d0             ; ln_Type
                swap    d0
                move.b  15(a3),d0            ; cd_Pad
                bsr     hex
                bsr     out
                bra     .cd
.mem:
                move.l  4.w,a6
                jsr     -132(a6)             ; Forbid (lecture de MemList ; Write ensuite hors Forbid)
                move.l  EB_MEMLIST(a6),a2
                lea     buf(pc),a1
.mh:
                tst.l   (a2)
                beq.s   .mhe
                lea     t_mh(pc),a0
                bsr     cpy
                move.l  20(a2),d0            ; mh_Lower
                bsr     hex
                move.l  24(a2),d0            ; mh_Upper
                bsr     hex
                moveq   #0,d0
                move.w  14(a2),d0            ; mh_Attributes
                swap    d0
                move.b  8(a2),d0             ; ln_Type
                lsl.w   #8,d0
                move.b  9(a2),d0             ; ln_Pri
                bsr     hex
                move.l  28(a2),d0            ; mh_Free
                bsr     hex
                move.l  10(a2),d0            ; ln_Name
                beq.s   .nn
                move.l  d0,a0
                moveq   #23,d1
.nm:
                move.b  (a0)+,d0
                beq.s   .nn
                move.b  d0,(a1)+
                dbra    d1,.nm
.nn:
                move.b  #10,(a1)+
                move.l  (a2),a2
                bra.s   .mh
.mhe:
                jsr     -138(a6)             ; Permit
                lea     buf(pc),a0
                bsr     outbuf
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

cpy:                                         ; copie la chaîne a0 en (a1)+ (sans le NUL)
                move.b  (a0)+,(a1)+
                bne.s   cpy
                subq.l  #1,a1
                rts
hex:                                         ; d0 en 8 chiffres + espace, en (a1)+
                moveq   #7,d3
.h:
                rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:
                move.b  d1,(a1)+
                dbra    d3,.h
                move.b  #' ',(a1)+
                rts
out:                                         ; termine la ligne en (a1) et l'écrit
                move.b  #10,(a1)+
                lea     line(pc),a0
outbuf:                                      ; écrit [a0, a1) sur Output()
                move.l  a1,d3
                sub.l   a0,d3
                move.l  a0,d2
                move.l  a6,-(sp)
                move.l  dosbase(pc),a6
                jsr     -60(a6)              ; Output
                move.l  d0,d1
                jsr     -48(a6)              ; Write(fh d1, tampon d2, longueur d3)
                move.l  (sp)+,a6
                rts

dosname:        dc.b    "dos.library",0
expname:        dc.b    "expansion.library",0
t_cd:           dc.b    "CD ",0
t_mh:           dc.b    "MH ",0
                even
dosbase:        dc.l    0
line:           ds.b    160
buf:            ds.b    512
