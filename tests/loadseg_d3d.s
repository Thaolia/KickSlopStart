; tests/loadseg_d3d.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM) pour le jalon D3d.
; Identique en structure à loadseg_d2.s (CODE émettant via SERDAT + DATA + 1 relocation 32 bits CODE->DATA),
; mais émet un marqueur DISTINCT « D3D LOADSEG-VIA-DOS OK ». Chargé PAR LA COUCHE DOS (dos Open/Read -> handler
; par packets -> OFS -> ls_load_hunks -> relocation) puis exécuté : s'il émet son marqueur, toute la chaîne
; « charger une commande via dos » a fonctionné (lecture par packets + reloc + run depuis la RAM).
; Clean-room : code AUTEUR, registres hardware publics, aucune lecture ROM.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

                section code,code
_start:
                move.l  #d3dmsg,a0          ; pointeur ABSOLU -> string en DATA (RELOC32 code->data)
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

                section data,data
d3dmsg:
                dc.b    "D3D LOADSEG-VIA-DOS OK (command loaded through dos Open/Read packets -> handler -> OFS, relocated, ran from RAM)",13,10,0
                even
