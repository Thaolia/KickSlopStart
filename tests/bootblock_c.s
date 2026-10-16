; tests/bootblock_c.s — boot code CUSTOM du jalon C « ça boote ! » (ASSET DE TEST, PAS du code ROM).
; Assemblé en binaire brut (vasm -Fbin -m68000) et placé à l'offset +12 du bootblock d'un ADF de test
; (voir tests/mk_boot_adf.sh). Prouve que le strap a LU + VALIDÉ + EXÉCUTÉ le bootblock : émet un marqueur
; série « CBOOT ... » puis rend la main avec D0=0 (succès). Un VRAI bootblock chargerait dos ici et ne
; reviendrait pas — notre stub revient (jalon sans dos).
;
; Entrée (convention bootblock AmigaDOS, publique — RKRM Devices / devices/bootblock.i) : A6 = SysBase,
; A1 = IORequest réutilisable, mode superviseur. Tout en PC-relatif : le bloc tourne à une adresse AllocMem'd
; quelconque. On n'utilise ni A6 ni A1 (émission série directe via SERDAT, autonome). Clean-room : code AUTEUR,
; registres hardware publics, aucune lecture ROM.

SERDAT   EQU $DFF030                ; registre série (écriture)
SERDATR  EQU $DFF018                ; registre série (lecture ; TBE = bit 13)

        lea     bb_msg(pc),a0
.lp:
        move.b  (a0)+,d1
        beq.s   .done
        move.w  #$2000,d2            ; timeout TBE (borne, jamais de hang)
.wt:
        move.w  SERDATR,d3
        btst    #13,d3              ; TBE (transmit buffer empty) ?
        bne.s   .tx
        dbra    d2,.wt
        bra.s   .lp                 ; timeout -> caractère suivant
.tx:
        and.w   #$00FF,d1
        or.w    #$0100,d1           ; bit stop
        move.w  d1,SERDAT
        bra.s   .lp
.done:
        moveq   #0,d0               ; D0 = 0 : boot réussi (convention bootblock)
        rts
bb_msg:
        dc.b    "CBOOT bootblock execute (kickslop) D0=0",13,10,0
        even
