; src/exec/interrupts.s — exec.library : plomberie d'interruptions, M3a (minimal).
;   init_ints   : installe l'autovecteur 68000 niveau 3 (VBlank), active VERTB +
;                 le maître INTEN, abaisse le masque IPL -> les interruptions passent.
;   vbl_handler : handler VBlank direct — incrémente VBL_COUNT et acquitte INTREQ.
; M3a = PLOMBERIE SEULE : prouve que la chaîne d'interruptions est vivante (le
; compteur avance). À VENIR (M3b+) : dispatcher complet par niveau (décodage
; INTREQR), IntVects/SetIntVector/AddIntServer, et le quantum d'ordonnancement
; (poser SFB_TQE dans SysFlags) pilotant Switch/Dispatch. Le handler reste
; volontairement AUTONOME et REMPLAÇABLE : il deviendra l'entrée de l'ordonnanceur.
; Piste IMPLÉMENTATION (« clean ») : hardware/intbits.i (ABI publique) + HRM.

                include "exec.i"

                xdef    init_ints

; init_ints : arme l'interruption VBlank. a6 = SysBase. Clobbers d0/a0.
init_ints:
        lea     VBL_COUNT,a0
        clr.l   (a0)                              ; compteur à zéro
        move.l  #vbl_handler,AUTOVEC_L3           ; autovecteur niveau 3 -> handler
        move.w  #INTF_VERTB,INTREQ                ; efface un VERTB pendant
        move.w  #(INTF_SETCLR|INTF_INTEN|INTF_VERTB),INTENA   ; active VERTB + maître
        move.w  #$2000,sr                         ; superviseur, IPL=0 -> VERTB passe
        rts

; vbl_handler : interruption VBlank (niveau 3). Préserve a0 ; le RTE restaure SR/CC.
vbl_handler:
        move.l  a0,-(sp)
        lea     VBL_COUNT,a0
        addq.l  #1,(a0)
        move.w  #INTF_VERTB,INTREQ               ; acquitte VERTB (une écriture suffit sur 68000)
        move.l  (sp)+,a0
        rte
