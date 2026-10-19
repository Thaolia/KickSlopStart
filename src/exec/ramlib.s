; src/exec/ramlib.s — chargement des librairies et devices depuis le disque (rôle de ramlib.library).
; OpenLibrary / OpenDevice appellent ram_loadmodule quand le nom est absent des listes système : LoadSeg de
; « LIBS:nom » ou « DEVS:nom », recherche du ROMTag (RTC_MATCHWORD dont RT_MATCHTAG pointe sur lui-même) dans les
; segments chargés, puis InitResident(romtag, seglist) qui l'ajoute à la liste système (AUTOINIT) ou appelle son init.
; Portée : l'appelant doit être un PROCESS (LoadSeg passe par des packets DOS répondus sur son pr_MsgPort) ; une
; simple tâche obtient l'échec habituel (la vraie ramlib délègue à son propre process : non reproduit).
; Piste IMPLÉMENTATION (« clean ») : RKRM Libraries (ramlib, LIBS:/DEVS:), format Resident (exec/resident.i),
; AutoDocs exec OpenLibrary/OpenDevice/InitResident, dos LoadSeg/UnLoadSeg. AUCUNE lecture ROM.

                include "exec.i"
                include "dospkt.i"

                xdef    ram_loadmodule

RL_PATHMAX      EQU 64

; ram_loadmodule(a0 = préfixe C (« LIBS: » / « DEVS: »), a1 = nom C, a6 = SysBase) -> d0 = -1 si un module a été
; chargé et initialisé, 0 sinon. Un nom contenant déjà ':' est chargé tel quel. Préserve d1-d7/a0-a6.
ram_loadmodule:
        movem.l d1-d4/a0-a3/a6,-(sp)
        move.l  DOS_DOSBASE,d0
        beq     .rl_fail             ; dos pas encore là (phase de boot)
        move.l  EB_THISTASK(a6),a2
        cmp.b   #NT_PROCESS,LN_TYPE(a2)
        bne     .rl_fail
        lea     -RL_PATHMAX(sp),sp
        move.l  sp,a2                ; a2 = chemin
        move.l  a1,a3
.rl_colon:
        move.b  (a3)+,d0
        beq.s   .rl_prefix
        cmp.b   #':',d0
        bne.s   .rl_colon
        bra.s   .rl_name             ; nom avec volume/assign : tel quel
.rl_prefix:
        move.b  (a0)+,(a2)+
        bne.s   .rl_prefix
        subq.l  #1,a2
.rl_name:
        moveq   #RL_PATHMAX-8,d1
.rl_ncpy:
        move.b  (a1)+,(a2)+
        beq.s   .rl_load
        subq.l  #1,d1
        bne.s   .rl_ncpy
        clr.b   (a2)
.rl_load:
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  ($4).w,a6
        lea     RL_PATHMAX(sp),sp
        move.l  d0,d3                ; d3 = seglist
        beq     .rl_fail
        move.l  d0,d2                ; parcours des segments : [taille à BADDR-4][lien][contenu]
.rl_seg:
        lsl.l   #2,d2
        beq     .rl_none
        move.l  d2,a0
        move.l  -4(a0),d4            ; taille du bloc (en-tête de 8 octets compris)
        lea     -4(a0,d4.l),a2       ; fin du bloc
        lea     4(a0),a1             ; début du contenu
        sub.l   #RT_SIZE,a2
.rl_scan:
        cmp.l   a2,a1
        bhi.s   .rl_next
        cmp.w   #RTC_MATCHWORD,(a1)
        bne.s   .rl_adv
        cmp.l   RT_MATCHTAG(a1),a1
        beq.s   .rl_found
.rl_adv:
        addq.l  #2,a1
        bra.s   .rl_scan
.rl_next:
        move.l  (a0),d2              ; segment suivant (BPTR)
        bra.s   .rl_seg
.rl_found:
        move.l  d3,d1                ; InitResident(a1 = romtag, d1 = seglist)
        jsr     LVO_INITRESIDENT(a6)
        tst.l   d0
        beq     .rl_none
        moveq   #-1,d0
        bra.s   .rl_ret
.rl_none:
        move.l  d3,d1                ; pas de ROMTag / init refusée : décharge
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
.rl_fail:
        moveq   #0,d0
.rl_ret:
        movem.l (sp)+,d1-d4/a0-a3/a6
        rts
