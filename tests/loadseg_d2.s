; tests/loadseg_d2.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM) pour le jalon D2 (LoadSeg).
; Linké en load file Amiga (hunk) : une section CODE + une section DATA, avec UNE relocation 32 bits CODE->DATA
; (move.l #d2msg,a0 référence la string stockée en DATA). Prouve que LoadSeg a chargé les hunks ET APPLIQUÉ la
; relocation : le code émet « D2LOADSEG OK ... » via SERDAT. Si la relocation est SAUTÉE (RED), le pointeur reste
; l'offset link-time (0 dans le hunk DATA) -> lecture de la RAM basse -> octets faux -> marqueur absent, SANS bus
; error (RAM valide). Entrée : appelé en JSR (A6 = SysBase, ignoré ; émission série directe, autonome).
; Clean-room : code AUTEUR, registres hardware publics, aucune lecture ROM.

SERDAT   EQU $DFF030                ; registre série (écriture)
SERDATR  EQU $DFF018                ; registre série (lecture ; TBE = bit 13)

                section code,code
_start:
                move.l  #d2msg,a0          ; pointeur ABSOLU -> string en DATA (génère un RELOC32 code->data)
.lp:
                move.b  (a0)+,d1
                beq.s   .done
                move.w  #$2000,d2          ; timeout TBE (borne, jamais de hang)
.wt:
                move.w  SERDATR,d3
                btst    #13,d3            ; TBE (transmit buffer empty) ?
                bne.s   .tx
                dbra    d2,.wt
                bra.s   .lp               ; timeout -> caractère suivant
.tx:
                and.w   #$00FF,d1
                or.w    #$0100,d1         ; bit stop
                move.w  d1,SERDAT
                bra.s   .lp
.done:
                moveq   #0,d0             ; D0 = 0 (succès ; convention LoadSeg : on JSR puis on revient)
                rts

                section data,data
d2msg:
                dc.b    "D2LOADSEG OK (hunk loaded + relocated from OFS, ran from RAM)",13,10,0
                even
