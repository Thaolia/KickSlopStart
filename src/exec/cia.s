; src/exec/cia.s — cia.resource (ciaa.resource + ciab.resource) — M5b.
; PREMIER vrai module résident (direct-init, pri 80). Son ROMTag est scanné par
; build_reslist ; InitResident appelle cia_init qui crée les DEUX resources CIA via
; MakeLibrary (base library-like + jump table AddICRVector/RemICRVector/AbleICR/SetICR),
; les nomme (ciaa/ciab), pose la base matérielle, AddResource. Les fonctions gèrent les
; slots de vecteurs ICR (5 par CIA) + le shadow du masque ICR + le registre ICR du chip.
; DISPATCH D'INTERRUPTION : cia_dispatch lit l'ICR du chip une fois (ACK + efface tous les pending) et
; appelle le vecteur de chaque bit posé. En M7b, cia_server (wrappe cia_dispatch) est enregistré comme
; SERVEUR PORTS/EXTER via le dispatcher par numéro d'exec (AddIntServer/SetIntVector) au lieu d'un
; autovecteur hardcodé -> cia.resource EST le handler PORTS/EXTER, comme dans le vrai exec.
; Convention : fonctions appelées avec a6 = base resource ; scratch = d0/d1/a0/a1.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs cia.resource + exec. AUCUNE lecture de la ROM.
; Table de vecteurs ABSOLUE ici (la démo AUTOINIT M5a est relative -> les deux branches de
; MakeFunctions restent exercées).

                include "exec.i"

                xdef    cia_init
                xdef    ciaa_server       ; M7b : serveur PORTS (ciaa) — IS_CODE d'un serveur enregistré
                xdef    ciab_server       ; M7b : serveur EXTER (ciab)

; --- ROMTag cia.resource (scanné par build_reslist) ---
        EVEN
cia_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    cia_romtag           ; RT_MATCHTAG = self
        dc.l    cia_end              ; RT_ENDSKIP
        dc.b    0,34,NT_RESOURCE,80  ; RT_FLAGS (0 = direct-init), RT_VERSION, RT_TYPE, RT_PRI
        dc.l    cia_resname          ; RT_NAME
        dc.l    cia_resname          ; RT_IDSTRING
        dc.l    cia_init             ; RT_INIT (direct-init)
cia_resname:
        dc.b    "cia.resource",0
ciaa_name:
        dc.b    "ciaa.resource",0
ciab_name:
        dc.b    "ciab.resource",0
        EVEN
cia_vectors:                         ; table ABSOLUE, terminée par -1
        dc.l    cia_AddICRVector     ; LVO -6
        dc.l    cia_RemICRVector     ; LVO -12
        dc.l    cia_AbleICR          ; LVO -18
        dc.l    cia_SetICR           ; LVO -24
        dc.l    -1

; cia_init : direct-init (D0=0, A0=segList, A6=ExecBase) -> D0=0. Crée ciaa puis ciab.
cia_init:
        movem.l d2/a2,-(sp)
        move.l  #CIAA_HW,d2
        lea     ciaa_name(pc),a2
        bsr.s   cia_make
        move.l  #CIAB_HW,d2
        lea     ciab_name(pc),a2
        bsr.s   cia_make
        moveq   #0,d0
        movem.l (sp)+,d2/a2
        rts

; cia_make : crée un resource CIA. d2 = base matérielle, a2 = nom. a6 = SysBase.
cia_make:
        move.l  a2,-(sp)             ; sauve le nom (MakeLibrary clobbe a2)
        lea     cia_vectors(pc),a0
        suba.l  a1,a1                ; structure = NULL
        suba.l  a2,a2                ; init = NULL
        move.l  #CIAR_SIZE,d0
        moveq   #0,d1                ; segList = 0
        jsr     LVO_MAKELIBRARY(a6)  ; -> d0 = base (jump table bâtie)
        move.l  (sp)+,a2
        tst.l   d0
        beq.s   .cm_ret              ; alloc KO
        move.l  d0,a1                ; a1 = base resource
        move.l  a2,LN_NAME(a1)
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        move.l  d2,CIAR_HWBASE(a1)
        jsr     LVO_ADDRESOURCE(a6)  ; AddResource(a1=base) (préserve a1 et d2)
        cmp.l   #CIAA_HW,d2          ; publie le pointeur de base pour le handler d'interruption
        bne.s   .cm_notA
        move.l  a1,CIAA_PTR
        bra.s   .cm_ret
.cm_notA:
        move.l  a1,CIAB_PTR
.cm_ret:
        rts

; --- fonctions cia.resource (a6 = base resource) ---

; AddICRVector(iCRBit d0, interrupt a1) -> d0 = NULL (ok) | interrupt occupant le bit.
; Stocke le vecteur dans le slot + active le bit ICR (shadow + registre chip).
cia_AddICRVector:
        move.l  d0,d1
        lsl.l   #2,d1                ; d1 = offset slot = bit*4 (index, préservé)
        lea     CIAR_VECTORS(a6),a0
        tst.l   0(a0,d1.l)           ; slot occupé ? (sans clobber l'index d1)
        bne.s   .aiv_owned
        move.l  a1,0(a0,d1.l)        ; stocke le vecteur
        moveq   #1,d1
        lsl.l   d0,d1                ; d1 = 1<<bit
        or.b    d1,CIAR_ICRMASK(a6)  ; shadow |= bit
        or.b    #$80,d1              ; chip : set-bits
        move.l  CIAR_HWBASE(a6),a0
        move.b  d1,CIA_ICR_OFF(a0)
        moveq   #0,d0                ; succès
        rts
.aiv_owned:
        move.l  0(a0,d1.l),d0        ; retourne l'occupant du bit
        rts

; RemICRVector(iCRBit d0, interrupt a1) -> void. Libère le slot + désactive le bit ICR.
cia_RemICRVector:
        move.l  d0,d1
        lsl.l   #2,d1
        lea     CIAR_VECTORS(a6),a0
        clr.l   0(a0,d1.l)           ; slot libéré
        moveq   #1,d1
        lsl.l   d0,d1                ; d1 = 1<<bit (chip : clear-bits, pas de $80)
        move.b  d1,d0
        not.b   d0
        and.b   d0,CIAR_ICRMASK(a6)  ; shadow &= ~bit
        move.l  CIAR_HWBASE(a6),a0
        move.b  d1,CIA_ICR_OFF(a0)
        rts

; AbleICR(mask d0) -> d0 = ancien masque. bit7=1 : active (mask&$7F) ; bit7=0 : désactive ;
; d0=0 : lecture seule du masque courant (shadow).
cia_AbleICR:
        move.l  d2,-(sp)
        moveq   #0,d2
        move.b  CIAR_ICRMASK(a6),d2  ; ancien masque (à retourner)
        move.l  d0,d1
        btst    #7,d1
        beq.s   .ai_clear
        and.b   #$7F,d1              ; active ces bits
        or.b    d1,CIAR_ICRMASK(a6)
        or.b    #$80,d1              ; chip : set-bits
        bra.s   .ai_hw
.ai_clear:
        and.b   #$7F,d1
        beq.s   .ai_done             ; mask == 0 -> lecture seule
        move.b  d1,d0
        not.b   d0
        and.b   d0,CIAR_ICRMASK(a6)  ; shadow &= ~bits (chip : clear-bits, d1 sans $80)
.ai_hw:
        move.l  CIAR_HWBASE(a6),a0
        move.b  d1,CIA_ICR_OFF(a0)
.ai_done:
        move.l  d2,d0                ; ancien masque
        move.l  (sp)+,d2
        rts

; SetICR(mask d0) -> d0. STUB minimal ce milestone (gestion du status d'interruption différée
; avec la dispatch INT2/INT6) : retourne 0, ne touche pas le chip (une lecture ICR effacerait
; le status). À compléter avec la dispatch.
cia_SetICR:
        moveq   #0,d0
        rts

; --- serveur d'interruption CIA (M6b -> M7b) ---
; ciaa_server / ciab_server : serveurs PORTS / EXTER appelés par le dispatcher générique par numéro
; (interrupts.s). La base resource N'EST PAS prise de IS_DATA (une struct Interrupt chaînée vit en RAM,
; mais le vecteur exclusif EXTER vit en ROM -> impossible d'y figer un pointeur runtime) : chaque
; wrapper lit CIAA_PTR / CIAB_PTR (publiés par cia_make). Lit+acquitte l'ICR du chip via cia_dispatch.
; Convention serveur : préserve d2-d7/a2-a4 ; cia_dispatch clobbe d2/d3/a2 -> on les sauve. Retourne
; Z MIS (d0=0) = « continue la chaîne » (type serveur VERTB : laisse les autres serveurs tourner aussi).
ciaa_server:
        move.l  CIAA_PTR,a1          ; base ciaa (0 si non créé -> cia_dispatch no-op)
        bra.s   cia_server_common
ciab_server:
        move.l  CIAB_PTR,a1          ; base ciab
cia_server_common:
        movem.l d2/d3/a2,-(sp)
        move.l  a1,a2                ; a2 = base resource
        bsr.s   cia_dispatch
        movem.l (sp)+,d2/d3/a2
        moveq   #0,d0                ; Z set -> continue la chaîne
        rts
cia_dispatch:                        ; a2 = base resource (0 ok), a6 = SysBase
        move.l  a2,d0
        beq.s   .cd_ret
        move.l  CIAR_HWBASE(a2),a0
        move.b  CIA_ICR_OFF(a0),d3   ; LECTURE ICR : pending (b7=IR, b0-4 sources) + ACK chip
        and.b   #$1F,d3
        beq.s   .cd_ret
        moveq   #0,d2                ; bit 0..4
.cd_loop:
        btst    d2,d3
        beq.s   .cd_next
        move.l  d2,d0
        lsl.l   #2,d0
        lea     CIAR_VECTORS(a2),a0
        move.l  0(a0,d0.l),d0        ; struct Interrupt* du slot
        beq.s   .cd_next
        move.l  d0,a0
        move.l  IS_DATA(a0),a1
        move.l  IS_CODE(a0),a5
        jsr     (a5)                 ; serveur (a1=data, a5=code, a6=SysBase)
.cd_next:
        addq.l  #1,d2
        cmp.l   #5,d2
        bne.s   .cd_loop
.cd_ret:
        rts
        EVEN
cia_end:
