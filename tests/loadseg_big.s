; tests/loadseg_big.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM) : fichier > 16 Ko pour prouver
; le cap-bump de LoadSeg (handler HS_BUF + LoadSeg buffer relevés 16K -> 32K). Structure : 1 CODE + 1 DATA + 1
; RELOC32 (code->data, count=1). Le DATA contient 24000 octets de padding ON-DISK puis une SENTINELLE à la toute
; fin. Le CODE lit la sentinelle via un pointeur relocalisé : si elle vaut la valeur attendue, c'est que le gros
; DATA (> 16 Ko) a été lu EN ENTIER dans le segment -> émet « LOADSEG BIG OK ». Avec le cap re-plafonné à 16 Ko
; (RED LOADSEG_CAP16K), le fichier tronque à FINDINPUT -> la sentinelle (offset 24000) n'est pas chargée -> pas d'émission.
; Message PC-relatif (dans le CODE) -> une seule relocation (vers la sentinelle). Clean-room : code AUTEUR, aucune lecture ROM.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
BIGPAD   EQU 24000                      ; padding on-disk (force le fichier au-delà de 16 Ko)
SENTINEL EQU $B16B00B5

                section code,code
_start:
                move.l  #bigsentinel,a0     ; RELOC32 code->data : pointeur vers la sentinelle (fin du gros DATA)
                cmp.l   #SENTINEL,(a0)
                bne.s   .done               ; gros DATA pas chargé en entier -> pas d'émission
                lea     bigmsg(pc),a0       ; message PC-relatif (dans le CODE -> pas de 2e relocation)
.lp:
                move.b  (a0)+,d1
                beq.s   .done
                move.w  #$2000,d2
.wt:
                move.w  SERDATR,d3
                btst    #13,d3
                bne.s   .tx
                dbra    d2,.wt
                bra.s   .lp
.tx:
                and.w   #$00FF,d1
                or.w    #$0100,d1
                move.w  d1,SERDAT
                bra.s   .lp
.done:
                moveq   #0,d0
                rts
bigmsg:
                dc.b    "LOADSEG BIG OK (>16KB executable loaded via LoadSeg -150: full DATA hunk read into segment; cap raised 16K->32K, not streaming)",13,10,0
                even

                section data,data
bigpad:
                dcb.b   BIGPAD,0            ; padding on-disk : rend le fichier > 16 Ko (cap de LECTURE)
bigsentinel:
                dc.l    SENTINEL            ; sentinelle à la FIN du gros DATA : prouve que tout a été lu
