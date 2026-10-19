; src/exec/resident.s — exec.library : découverte des modules résidents (M4).
;   build_reslist   : scanne la ROM pour les ROMTags (struct Resident), bâtit le tableau
;                     NUL-terminé ExecBase->ResModules trié par RT_PRI décroissant.
;   FindResident    : recherche un résident par nom dans ResModules.
;   InitResident    : initialise UN résident (matchword vérifié ; chemin direct-init ;
;                     AUTOINIT/MakeLibrary DIFFÉRÉ -> no-op ce milestone).
;   InitCode        : parcourt ResModules et InitResident chacun (filtre version).
; C'est la colonne vertébrale du boot Amiga : l'OS se construit en scannant des ROMTags
; et en les initialisant par priorité décroissante (au lieu d'un dispatch codé en dur).
; Convention Amiga : scratch = d0/d1/a0/a1 ; a6 = library base.
; Piste IMPLÉMENTATION (« clean ») : NDK exec/resident.i + AutoDocs (ABI publique).
; AUCUNE lecture de la ROM propriétaire ; priorités des résidents démo = arbitraires.

                include "exec.i"

                xdef    build_reslist
                xdef    exec_FindResident
                xdef    exec_InitResident
                xdef    exec_InitCode
                xdef    exec_AddResource
                xdef    exec_OpenResource

; build_reslist : a6 = SysBase. Alloue le tableau, scanne [RESSCAN_LO,RESSCAN_HI), trie,
; publie ExecBase->ResModules. Un ROMTag = mot $4AFC à adresse PAIRE dont RT_MATCHTAG
; pointe sur lui-même (rejette les $4AFC fortuits). Reprise du scan à RT_ENDSKIP.
build_reslist:
        movem.l d2-d6/a2-a4,-(sp)
        move.l  #(RESMAX+1)*4,d0     ; RESMAX pointeurs + 1 terminateur NUL
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a3                ; a3 = base du tableau
        move.l  d0,EB_RESMODULES(a6)
        move.l  d0,a4                ; a4 = curseur d'écriture
        moveq   #0,d2                ; d2 = compte de résidents
        move.l  #RESSCAN_LO,a2       ; a2 = p (pointeur de scan, toujours pair)
.scan:
        cmp.l   #RESSCAN_HI,a2
        bcc.s   .sort                ; p >= fin -> scan terminé
        cmp.w   #RTC_MATCHWORD,(a2)
        bne.s   .scan_next
        move.l  RT_MATCHTAG(a2),d0
        cmp.l   a2,d0
        bne.s   .scan_next           ; RT_MATCHTAG != self -> $4AFC fortuit
        cmp.w   #RESMAX,d2
        bcc.s   .scan_skip           ; tableau plein (défensif) -> ne pas enregistrer
        move.l  a2,(a4)+             ; array[count++] = p
        addq.l  #1,d2
.scan_skip:
        move.l  RT_ENDSKIP(a2),d0    ; reprendre après le corps du module
        cmp.l   a2,d0
        bls.s   .scan_next           ; ENDSKIP <= p (non-avançant) -> avance de 2 (défensif)
        move.l  d0,a2
        bra.s   .scan
.scan_next:
        addq.l  #2,a2
        bra.s   .scan
.sort:
        ; tri à bulles décroissant par RT_PRI (N petit ; pas d'échange à pri égale -> stable
        ; = FIFO dans l'ordre de scan = ordre d'adresse). array = a3, count = d2.
        cmp.l   #2,d2
        bcs.s   .done                ; 0 ou 1 résident -> déjà trié
.sort_pass:
        moveq   #0,d4                ; drapeau d'échange
        move.l  a3,a0                ; a0 = &array[0]
        moveq   #1,d3                ; j = 1
.sort_j:
        cmp.l   d2,d3
        bcc.s   .sort_passend        ; j >= count -> fin de passe
        move.l  (a0),a1              ; array[j-1]
        move.l  4(a0),a2             ; array[j]
        move.b  RT_PRI(a1),d5
        move.b  RT_PRI(a2),d6
        cmp.b   d6,d5                ; pri[j-1] - pri[j] (signé)
        bge.s   .sort_noswap         ; pri[j-1] >= pri[j] -> ordre décroissant respecté
        move.l  a2,(a0)              ; échange array[j-1] <-> array[j]
        move.l  a1,4(a0)
        moveq   #1,d4
.sort_noswap:
        addq.l  #4,a0
        addq.l  #1,d3
        bra.s   .sort_j
.sort_passend:
        tst.l   d4
        bne.s   .sort_pass           ; un échange eu lieu -> repasse
.done:
        movem.l (sp)+,d2-d6/a2-a4
        rts

; FindResident(name a1) -> d0 = struct Resident* | 0. Recherche dans ResModules.
exec_FindResident:
        movem.l d2/a2/a3,-(sp)
        move.l  a1,a2                ; a2 = nom recherché
        move.l  EB_RESMODULES(a6),a3
        move.l  a3,d0
        beq.s   .fr_none             ; pas de tableau
.fr_loop:
        move.l  (a3)+,d0             ; prochain Resident* (d0 conservé = valeur de retour)
        beq.s   .fr_none             ; terminateur NUL -> non trouvé
        move.l  d0,a0
        move.l  RT_NAME(a0),a0       ; nom du résident
        move.l  a2,a1                ; nom recherché
.fr_cmp:
        move.b  (a0)+,d1
        move.b  (a1)+,d2
        cmp.b   d1,d2
        bne.s   .fr_loop             ; divergence -> résident suivant
        tst.b   d1
        bne.s   .fr_cmp              ; pas la fin -> continuer
        bra.s   .fr_done             ; égalité complète -> d0 = ce Resident*
.fr_none:
        moveq   #0,d0
.fr_done:
        movem.l (sp)+,d2/a2/a3
        rts

; InitResident(resident a1, segList d1) -> d0. Valide le matchword puis appelle l'init.
; Chemin direct-init (RTF_AUTOINIT clair) : RT_INIT est une routine appelée avec, par
; convention ABI (AutoDoc exec InitResident) : D0 = 0, A0 = segList, A6 = ExecBase ;
; le pointeur resident N'EST PAS passé (la routine d'init se connaît statiquement). Sa
; valeur de retour (d0) est renvoyée. Pour un module ROM, segList = NULL.
; AUTOINIT (RTF_AUTOINIT) : RT_INIT -> 4 longs {dataSize, funcTable, dataTable, initFunc}
; passés à MakeLibrary ; la base rendue est Enqueue'd dans la liste système selon RT_TYPE
; (NT_LIBRARY->LibList, NT_DEVICE->DeviceList, NT_RESOURCE->ResourceList). V34 : les champs
; name/type/version du nœud ne sont PAS remplis depuis le ROMTag (le module le fait).
exec_InitResident:
        cmp.w   #RTC_MATCHWORD,(a1)
        bne.s   .ir_fail             ; pas un ROMTag -> 0
        btst    #7,RT_FLAGS(a1)      ; RTF_AUTOINIT ?
        bne.s   .ir_autoinit
        move.l  a2,-(sp)
        move.l  RT_INIT(a1),a2       ; routine d'init
        move.l  d1,a0                ; a0 = segList (convention)
        moveq   #0,d0                ; d0 = 0 (convention)
        jsr     (a2)                 ; init(d0=0, a0=segList, a6=SysBase) -> d0
        move.l  (sp)+,a2
        rts
.ir_autoinit:
        ; RT_INIT -> 4 longs {dataSize, funcTable, dataTable, initFunc} passés à MakeLibrary.
        movem.l d2-d3/a2-a3,-(sp)
        move.l  d1,d3                ; d3 = segList (préservé)
        move.l  a1,a3                ; a3 = resident (pour l'ajout par type)
        move.l  RT_INIT(a1),a2       ; a2 = table AUTOINIT
        move.l  (a2),d0              ; dataSize
        move.l  4(a2),a0             ; funcTable (vectors)
        move.l  8(a2),a1             ; dataTable (structure InitStruct)
        move.l  12(a2),a2           ; initFunc
        move.l  d3,d1                ; segList
        jsr     LVO_MAKELIBRARY(a6)  ; -> d0 = base | 0
        tst.l   d0
        beq.s   .ira_fail
        ; V34 : ne PAS remplir name/type/version du nœud depuis le ROMTag (le module l'a fait).
        ; Ajout à la liste système selon RT_TYPE.
        move.l  d0,a1                ; a1 = base (nœud)
        move.b  RT_TYPE(a3),d1
        cmp.b   #NT_DEVICE,d1
        beq.s   .ira_dev
        cmp.b   #NT_RESOURCE,d1
        beq.s   .ira_res
        lea     EB_LIBLIST(a6),a0    ; NT_LIBRARY (défaut)
        bra.s   .ira_add
.ira_dev:
        lea     EB_DEVICELIST(a6),a0
        bra.s   .ira_add
.ira_res:
        lea     EB_RESOURCELIST(a6),a0
.ira_add:
        jsr     LVO_ENQUEUE(a6)      ; Enqueue(list a0, node a1=base) ; a1 préservé
        move.l  a1,d0                ; d0 = base (valeur de retour)
.ira_done:
        movem.l (sp)+,d2-d3/a2-a3
        rts
.ira_fail:
        moveq   #0,d0
        bra.s   .ira_done
.ir_fail:
        moveq   #0,d0
        rts

; InitCode(startClass d0, version d1) : parcourt ResModules (déjà pri-trié) et appelle
; InitResident sur chaque résident dont RT_FLAGS a un bit commun avec startClass (RTF_COLDSTART...)
; et de RT_VERSION >= version. Un résident sans drapeau de classe (workbench.task) reste dans
; ResModules sans être initialisé. segList = 0 (nos ROMTags n'ont pas de seglist).
exec_InitCode:
        movem.l d2-d4/a2,-(sp)
        move.b  d0,d4                ; d4 = classe de démarrage (RTF_COLDSTART...)
        move.l  d1,d3                ; version minimale
        move.l  EB_RESMODULES(a6),a2
        move.l  a2,d0
        beq.s   .ic_done             ; pas de tableau
.ic_loop:
        move.l  (a2)+,d0             ; Resident*
        beq.s   .ic_done             ; terminateur NUL
        move.l  d0,a1                ; a1 = resident (pour InitResident)
        move.b  RT_FLAGS(a1),d2
        and.b   d4,d2
        beq.s   .ic_loop             ; pas de cette classe (ex. workbench.task, lancé par LoadWB) -> sauter
        moveq   #0,d2
        move.b  RT_VERSION(a1),d2
        cmp.l   d3,d2
        bcs.s   .ic_loop             ; RT_VERSION < version -> sauter
        moveq   #0,d1                ; segList = 0
        jsr     LVO_INITRESIDENT(a6)
        bra.s   .ic_loop
.ic_done:
        movem.l (sp)+,d2-d4/a2
        rts

; AddResource(resource a1) : type NT_RESOURCE puis Enqueue dans ResourceList (Forbid-enveloppé,
; comme AddPort : liste partagée). OpenResource s'en sert pour retrouver le resource par nom.
exec_AddResource:
        move.b  #NT_RESOURCE,LN_TYPE(a1)
        jsr     LVO_FORBID(a6)
        lea     EB_RESOURCELIST(a6),a0
        jsr     LVO_ENQUEUE(a6)
        jsr     LVO_PERMIT(a6)
        rts

; OpenResource(name a1) -> d0 = resource | 0 (recherche dans ResourceList ; pas de CloseResource).
exec_OpenResource:
        lea     EB_RESOURCELIST(a6),a0
        jsr     LVO_FINDNAME(a6)
        rts
