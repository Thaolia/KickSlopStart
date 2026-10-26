; adn.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Sonde boîte noire : MakeDosNode + AddDosNode(0, 0, dn) APRÈS l'init de dos (piste analyse).
; Paquet : "ZZ0", "trackdisk.device", unité 1, géométrie DD 880 Ko. Le device n'est jamais accédé.
; Écrit « AD dn résultat » ; relancer bootlist ensuite pour voir DevInfo / eb_MountList.

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                lea     dosbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                lea     expname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)
                move.l  d0,a6
                tst.l   d0
                beq     .ret
                lea     pp(pc),a0
                lea     n_dos(pc),a1
                move.l  a1,(a0)
                lea     n_exec(pc),a1
                move.l  a1,4(a0)
                jsr     -144(a6)             ; MakeDosNode(a0 paquet)
                move.l  d0,d6
                beq.s   .out
                moveq   #0,d0                ; bootPri
                moveq   #0,d1                ; flags
                move.l  d6,a0
                jsr     -150(a6)             ; AddDosNode
                move.l  d0,d7
.out:           lea     buf(pc),a1
                move.b  #'A',(a1)+
                move.b  #'D',(a1)+
                move.b  #' ',(a1)+
                move.l  d6,d0
                bsr     hex
                move.l  d7,d0
                bsr     hex
                move.b  #10,(a1)+
                lea     buf(pc),a0
                move.l  a1,d3
                sub.l   a0,d3
                move.l  a0,d2
                move.l  dosbase(pc),a6
                jsr     -60(a6)
                move.l  d0,d1
                jsr     -48(a6)
.ret:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts
hex:            moveq   #7,d3
.h:             rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:             move.b  d1,(a1)+
                dbra    d3,.h
                move.b  #' ',(a1)+
                rts
                cnop    0,4
pp:             dc.l    0,0                  ; noms DOS / exec
                dc.l    1                    ; unité
                dc.l    0                    ; flags OpenDevice
                dc.l    11                   ; de_TableSize
                dc.l    128,0,2,1,11,2,0,0,0,79,5
dosbase:        dc.l    0
dosname:        dc.b    "dos.library",0
expname:        dc.b    "expansion.library",0
n_dos:          dc.b    "ZZ0",0
n_exec:         dc.b    "trackdisk.device",0
                cnop    0,2
buf:            ds.b    64
