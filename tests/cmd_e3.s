; tests/cmd_e3.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM) pour le jalon E3.
; Même structure que loadseg_d3d.s (CODE émettant via SERDAT + DATA + 1 relocation 32 bits CODE->DATA), mais
; émet « E3 CMD RAN OK ». Écrit sur l'ADF sous le nom « e3cmd » ; tapé au shell (« e3cmd\r »), le shell le charge
; depuis DF0: via dos (Open/Read -> ls_load_hunks -> reloc) puis l'exécute : s'il émet son marqueur, la chaîne
; « taper un nom de commande -> charger+exécuter depuis le disque via dos » a fonctionné.
; Clean-room : code AUTEUR, registres hardware publics, aucune lecture ROM.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

                section code,code
_start:
                move.l  #e3msg,a0           ; pointeur ABSOLU -> string en DATA (RELOC32 code->data)
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
e3msg:
                dc.b    "E3 CMD RAN OK (command typed at the shell, loaded from DF0: via dos Open/Read, relocated, ran from RAM)",13,10,0
                even
