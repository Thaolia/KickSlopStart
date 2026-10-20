; src/exec/diskres.s — disk.resource : arbitrage du matériel disque entre pilotes (trackdisk, chargeurs NDOS).
;
; AllocUnit/FreeUnit réservent une unité (bits DRF_ALLOCn) ; GetUnit/GiveUnit prêtent le contrôleur disque à UN
; pilote à la fois (les demandeurs suivants attendent dans dr_Waiting et reçoivent ReplyMsg de leur DRU quand le
; contrôleur se libère) ; GetUnitID rend l'identifiant de lecteur lu au démarrage. La ressource possède les
; interruptions DSKBLK / DSKSYNC et l'index CIA-B FLG et les relaie aux interruptions du DRU courant.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs disk.resource + resources/disk.h + HRM (identifiant de lecteur).
; AUCUNE lecture ROM.

                include "exec.i"
                include "disk.i"

                xref    newlist          ; lists.s

; --- struct DiscResourceUnit (resources/disk.h) ---
DRU_DISCBLOCK   EQU MN_SIZE          ; struct Interrupt
DRU_DISCSYNC    EQU MN_SIZE+IS_SIZE
DRU_INDEX       EQU MN_SIZE+2*IS_SIZE
DRU_SIZE        EQU MN_SIZE+3*IS_SIZE
; --- struct DiscResource ---
DR_CURRENT      EQU LIB_SIZE         ; DRU propriétaire actuel (ou dernier propriétaire)
DR_FLAGS        EQU LIB_SIZE+4
DR_SYSLIB       EQU LIB_SIZE+6
DR_CIARES       EQU LIB_SIZE+10
DR_UNITID       EQU LIB_SIZE+14      ; ULONG[4]
DR_WAITING      EQU LIB_SIZE+30      ; struct List
DR_DISCBLOCK    EQU DR_WAITING+14   ; sizeof(struct List)
DR_DISCSYNC     EQU DR_DISCBLOCK+IS_SIZE
DR_INDEX        EQU DR_DISCSYNC+IS_SIZE
DR_CURRTASK     EQU DR_INDEX+IS_SIZE
DR_NOBODY       EQU DR_CURRTASK+4    ; DRU vide : « dernier pilote » tant que personne n'a pris le contrôleur
DR_SIZE         EQU DR_NOBODY+DRU_SIZE

DRB_ACTIVE      EQU 7
DR_NUNITS       EQU 4
INTB_DSKBLK     EQU 1
INTB_DSKSYNC    EQU 12
INTF_DSKSYNC    EQU $1000
CIAICRB_FLG     EQU 4                ; CIA-B FLG = impulsion d'index du lecteur
CIAF_DSKSEL1    EQU $10

        EVEN
diskres_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    diskres_romtag
        dc.l    diskres_end
        dc.b    RTF_COLDSTART,34,NT_RESOURCE,70
        dc.l    diskres_name
        dc.l    diskres_name
        dc.l    diskres_init
diskres_name:
        dc.b    "disk.resource",0
ciab_resname:
        dc.b    "ciab.resource",0
        EVEN
diskres_vectors:
        dc.l    dr_allocunit         ; -6  AllocUnit(unité d0)
        dc.l    dr_freeunit          ; -12 FreeUnit(unité d0)
        dc.l    dr_getunit           ; -18 GetUnit(dru a1)
        dc.l    dr_giveunit          ; -24 GiveUnit()
        dc.l    dr_getunitid         ; -30 GetUnitID(unité d0)
        dc.l    -1

diskres_init:
        movem.l d2-d3/a2-a3,-(sp)
        lea     diskres_vectors(pc),a0
        suba.l  a1,a1
        suba.l  a2,a2
        move.l  #DR_SIZE,d0
        moveq   #0,d1
        jsr     LVO_MAKELIBRARY(a6)
        tst.l   d0
        beq     .ri_ret
        move.l  d0,a3                ; a3 = DiscResource (MakeLibrary ne met pas la zone positive à zéro)
        lea     LIB_SIZE(a3),a0
        move.w  #(DR_SIZE-LIB_SIZE)/2-1,d1
.ri_clr:
        clr.w   (a0)+
        dbra    d1,.ri_clr
        lea     diskres_name(pc),a0
        move.l  a0,LN_NAME(a3)
        move.b  #NT_RESOURCE,LN_TYPE(a3)
        move.l  a6,DR_SYSLIB(a3)
        lea     DR_NOBODY(a3),a0
        move.l  a0,DR_CURRENT(a3)
        lea     DR_WAITING(a3),a1
        jsr     newlist
        ; identifiants : DF0 n'a pas de registre d'identification (toujours DRT_AMIGA = 0)
        moveq   #1,d2
.ri_id:
        bsr     dr_readid
        move.l  d2,d1
        lsl.l   #2,d1
        move.l  d0,DR_UNITID(a3,d1.l)
        addq.l  #1,d2
        cmp.l   #DR_NUNITS,d2
        bcs.s   .ri_id
        ; vecteurs exclusifs DSKBLK / DSKSYNC + index CIA-B (laissé désactivé : AbleICR au pilote)
        lea     DR_DISCBLOCK(a3),a1
        lea     dr_blkint(pc),a0
        moveq   #INTB_DSKBLK,d0
        bsr     dr_setint
        lea     DR_DISCSYNC(a3),a1
        lea     dr_syncint(pc),a0
        moveq   #INTB_DSKSYNC,d0
        bsr     dr_setint
        lea     ciab_resname(pc),a1
        jsr     LVO_OPENRESOURCE(a6)
        move.l  d0,DR_CIARES(a3)
        beq.s   .ri_add
        move.l  d0,a6
        lea     DR_INDEX(a3),a1
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        move.l  a3,IS_DATA(a1)
        lea     dr_idxint(pc),a0
        move.l  a0,IS_CODE(a1)
        moveq   #CIAICRB_FLG,d0
        jsr     -6(a6)               ; AddICRVector(FLG, &dr_Index)
        moveq   #1<<CIAICRB_FLG,d0
        jsr     -18(a6)              ; AbleICR(FLG) : désactive
        move.l  ($4).w,a6
.ri_add:
        move.l  a3,a1
        jsr     LVO_ADDRESOURCE(a6)
.ri_ret:
        moveq   #0,d0
        movem.l (sp)+,d2-d3/a2-a3
        rts

; dr_setint : a1 = struct Interrupt de la ressource, a0 = code, d0 = n° d'interruption ; a3 = ressource.
dr_setint:
        move.b  #NT_INTERRUPT,LN_TYPE(a1)
        move.l  a3,IS_DATA(a1)
        move.l  a0,IS_CODE(a1)
        jmp     LVO_SETINTVECTOR(a6)

; dr_readid : d2 = unité 1..3 -> d0 = identifiant 32 bits (HRM : moteur on puis off avec le lecteur sélectionné
; remet à zéro son registre d'identification ; ensuite 32 sélections successives, chacune présente un bit sur
; /RDY, poids fort d'abord, bit = 1 quand /RDY est haut). Absent -> $FFFFFFFF (DRT_EMPTY).
dr_readid:
        moveq   #CIAF_DSKSEL1>>1,d3
        lsl.b   d2,d3
        not.b   d3                   ; d3 = PRB avec SELn bas, le reste haut (moteur off)
        move.b  #$FF,CIAB_DDRB
        move.b  #PRB_OFF,CIAB_PRB
        move.b  #PRB_MOTOR_ON,CIAB_PRB
        move.b  d3,d0
        and.b   #PRB_MOTOR_ON,d0
        move.b  d0,CIAB_PRB          ; sélection avec moteur bas : latche moteur on
        move.b  #PRB_OFF,CIAB_PRB
        move.b  d3,CIAB_PRB          ; sélection avec moteur haut : latche moteur off
        move.b  #PRB_OFF,CIAB_PRB
        moveq   #0,d0
        moveq   #31,d1
.rd_bit:
        move.b  d3,CIAB_PRB
        add.l   d0,d0
        btst    #DSKB_RDY,CIAA_PRA_HW
        beq.s   .rd_lo
        addq.l  #1,d0
.rd_lo:
        move.b  #PRB_OFF,CIAB_PRB
        dbra    d1,.rd_bit
        rts

; AllocUnit(unité d0) -> d0 = 1 si l'unité est attribuée, 0 si déjà prise ou invalide. bset = lecture-écriture
; indivisible sur 68000 (aucune interruption entre le test et la pose).
dr_allocunit:
        cmp.l   #DR_NUNITS,d0
        bcc.s   .au_no
        bset    d0,DR_FLAGS(a6)
        bne.s   .au_no
        moveq   #1,d0
        rts
.au_no:
        moveq   #0,d0
        rts

; FreeUnit(unité d0).
dr_freeunit:
        cmp.l   #DR_NUNITS,d0
        bcc.s   .fu_r
        bclr    d0,DR_FLAGS(a6)
.fu_r:
        rts

; GetUnitID(unité d0) -> d0 = type de lecteur.
dr_getunitid:
        cmp.l   #DR_NUNITS,d0
        bcc.s   .gi_empty
        lsl.l   #2,d0
        move.l  DR_UNITID(a6,d0.l),d0
        rts
.gi_empty:
        moveq   #-1,d0
        rts

; GetUnit(dru a1) -> d0 = DRU du dernier pilote si le contrôleur est libre (il passe à a1), sinon 0 et a1 est mis
; en attente : GiveUnit lui fera ReplyMsg, l'appelant retente alors GetUnit.
dr_getunit:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  DR_SYSLIB(a2),a6
        jsr     LVO_DISABLE(a6)
        bset    #DRB_ACTIVE,DR_FLAGS(a2)
        bne.s   .gu_busy
        move.l  DR_CURRENT(a2),d0
        move.l  a1,DR_CURRENT(a2)
        bra.s   .gu_out
.gu_busy:
        lea     DR_WAITING(a2),a0
        jsr     LVO_ADDTAIL(a6)
        moveq   #0,d0
.gu_out:
        move.l  d0,-(sp)
        jsr     LVO_ENABLE(a6)
        move.l  (sp)+,d0
        movem.l (sp)+,a2/a6
        rts

; GiveUnit() : libère le contrôleur et réveille le premier pilote en attente.
dr_giveunit:
        movem.l a2/a6,-(sp)
        move.l  a6,a2
        move.l  DR_SYSLIB(a2),a6
        jsr     LVO_DISABLE(a6)
        bclr    #DRB_ACTIVE,DR_FLAGS(a2)
        lea     DR_WAITING(a2),a0
        jsr     LVO_REMHEAD(a6)
        tst.l   d0
        beq.s   .gv_out
        move.l  d0,a1
        jsr     LVO_REPLYMSG(a6)
.gv_out:
        jsr     LVO_ENABLE(a6)
        movem.l (sp)+,a2/a6
        rts

; Relais d'interruption (a1 = ressource) : acquitte puis appelle l'interruption correspondante du DRU courant,
; seulement si un pilote tient le contrôleur et a posé un IS_CODE (appelé avec a1 = IS_DATA).
dr_blkint:
        move.w  #INTF_DSKBLK,INTREQ
        moveq   #DRU_DISCBLOCK,d0
        bra.s   dr_relay
dr_syncint:
        move.w  #INTF_DSKSYNC,INTREQ
        moveq   #DRU_DISCSYNC,d0
        bra.s   dr_relay
dr_idxint:
        moveq   #DRU_INDEX,d0        ; le dispatch CIA a déjà acquitté l'ICR
dr_relay:
        btst    #DRB_ACTIVE,DR_FLAGS(a1)
        beq.s   .rl_r
        move.l  DR_CURRENT(a1),a0
        add.l   d0,a0
        move.l  IS_CODE(a0),d1
        beq.s   .rl_r
        move.l  d1,-(sp)
        move.l  IS_DATA(a0),a1
.rl_r:
        rts                          ; avec IS_CODE empilé : saut vers le handler, qui revient à notre appelant
diskres_end:
