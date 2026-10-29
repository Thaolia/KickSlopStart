; src/dos/bcpl.s — runtime BCPL de dos.library : appel/retour BCPL (registres A5/A6), arithmétique, vecteur global
; (GV), segment runtime au format BCPL et globales. Les commandes c: du Workbench 1.3 (AddBuffers, CD, Path,
; Execute...) n'appellent AUCUNE bibliothèque par LVO : tout passe par les globales du GV pointé par A2.
; Piste IMPLÉMENTATION (« clean ») : convention publique (documentation Bill Kinnersley), AROS arch/m68k-all/dos
; (lecture seule, rien copié), spec docs/analysis/bcpl-runtime-v34.md (relue clean-room). AUCUNE lecture ROM.
;
; Convention : A0 = 0, A1 = frame BCPL courant, A2 = GV (adresse du slot 0), A4 = routine courante, A5 = bcpl_call,
; A6 = bcpl_ret. Appel : d0 = taille de la frame de l'appelant (décalage du nouveau A1), a4 = routine appelée,
; d1-d4 = 4 premiers arguments (les suivants sont écrits par l'appelant à 16, 20... de la nouvelle frame).
; Sous la nouvelle frame : ancien A1 (-12), adresse de retour (-8), entrée de la routine appelée (-4). Résultat d1.
; Scratch pour une routine : d0, d2-d7, a3, a4 ; A1/A2/A5/A6 rendus intacts ; A0 rendu à 0.
;
; Comment une commande obtient le runtime (spec §3.3) : son hunk 0 (stub) appelle findsegarray (89), getvec (29) et
; globin (28) du GV du CLI pour se créer un GV PRIVÉ, y installe chaque segment du segarray de pr_SegList puis sa
; propre seglist. Notre runtime est donc publié comme un SEGMENT AU FORMAT BCPL (bcpl_rtseg) dans le segarray du CLI.

                include "exec.i"
                include "dos.i"
                include "dospkt.i"

                xdef    bcpl_call            ; registre A5 des programmes BCPL
                xdef    bcpl_ret             ; registre A6
                xdef    bcpl_cli_setup       ; GV + segarray d'un process CLI
                xdef    bcpl_starthandler
                xdef    bcpl_cli_register    ; slot de rn_TaskArray + pr_TaskNum du CLI initial
                xdef    bcpl_execute         ; LVO Execute (dos_lib.s)
                xdef    rt_fault             ; texte d'une erreur dos via C:FAULT (shell.s)
                xref    rcli_seg
                xref    dos_bufwrite         ; dos_lib.s : écriture différée (wrch & co vers un fichier)
                xref    dos_flushout
                xref    dos_pktretry         ; dos_lib.s : requester « Please replace volume »
                xref    dos_setnow           ; dos_lib.s : règle l'heure système (setdatstamp)
                xref    proc_create          ; process.s : Process + pile + pr_MsgPort + AddTask
                xref    ser_puts
                xref    ser_puthex
                xref    dos_resolve          ; dos_lib.s : nom -> port du handler + lock (deviceproc)
                xref    dos_sendpkt          ; process.s : packet synchrone (a0 = StandardPacket, a1 = port)

GV_NEGSLOTS     EQU 50               ; slots -50..-1
GV_MAX          EQU 150              ; GV[0] = plus grande globale autorisée
GV_NEG          EQU GV_NEGSLOTS*4
GV_POS          EQU (GV_MAX+1)*4
GV_SIZE         EQU GV_NEG+GV_POS    ; 804 octets
ERR_GLOBIN      EQU 111              ; Result2 de globin quand une globale dépasse GV[0]
ERR_BADTEMPLATE EQU 120              ; Result2 de rdargs en erreur
ACTION_MORE_CACHE EQU 18
WF_BUFSZ        EQU 128              ; tampon de sortie local de writef & co (vidé quand plein et à la fin)
CP_STKEXTRA     EQU 4096             ; marge de pile 68000 des process créés par createproc

; --- appel / retour (A5 / A6) — multiply DOIT être à bcpl_call+$10, divide à +$12 (appels « jsr $10(a5) ») ---
; L'ABI fige cette entrée à 16 octets (frame -12/-8/-4, sauts à +$10/+$12) : la séquence est de ce fait identique à
; celle de BCPL_jsr/BCPL_rts d'AROS (arch/m68k-all/dos/bcpl.S), relevé par l'audit docs/audit/aros-similarity.md.
bcpl_call:
        move.l  (sp)+,a3             ; adresse de retour (l'appel est fait par jsr (a5))
        movem.l a1/a3-a4,-12(a1,d0.l) ; sous le nouveau frame : ancien A1, retour, routine appelée
        adda.l  d0,a1                ; A1 = nouveau frame
        movem.l d1-d4,(a1)           ; arguments
        jmp     (a4)
        bra.s   bcpl_mul             ; bcpl_call+$10
        bra.s   bcpl_divmod          ; bcpl_call+$12
bcpl_ret:
        movem.l -12(a1),a1/a3        ; ancien A1 et adresse de retour
        move.l  -4(a1),a4            ; routine du frame de l'appelant
        jmp     (a3)

; bcpl_mul : d1 = d1 * d2 (32 bits bas, signé ou non). Autres registres préservés.
bcpl_mul:
        movem.l d0/d3-d4,-(sp)
        move.l  d1,d3
        swap    d3
        mulu.w  d2,d3                ; poids fort de a * poids faible de b
        move.l  d2,d4
        swap    d4
        mulu.w  d1,d4                ; poids faible de a * poids fort de b
        add.w   d4,d3
        swap    d3
        clr.w   d3                   ; (somme des produits croisés) << 16
        mulu.w  d2,d1                ; poids faibles
        add.l   d3,d1
        movem.l (sp)+,d0/d3-d4
        rts

; bcpl_divmod : d1 = d1 / d2 (troncature vers 0), d2 = reste (signe du dividende). Division par 0 -> 0, 0.
bcpl_divmod:
        movem.l d0/d3-d5,-(sp)
        tst.l   d2
        bne     .dm_go
        moveq   #0,d1
        bra     .dm_out
.dm_go:
        moveq   #0,d5                ; bit0 = quotient négatif, bit1 = reste négatif
        tst.l   d1
        bpl     .dm_apos
        neg.l   d1
        bchg    #0,d5
        bset    #1,d5
.dm_apos:
        tst.l   d2
        bpl     .dm_bpos
        neg.l   d2
        bchg    #0,d5
.dm_bpos:
        bsr     udivmod32            ; d1 = quotient, d3 = reste (non signés)
        btst    #0,d5
        beq     .dm_qpos
        neg.l   d1
.dm_qpos:
        btst    #1,d5
        beq     .dm_rpos
        neg.l   d3
.dm_rpos:
        move.l  d3,d2
.dm_out:
        movem.l (sp)+,d0/d3-d5
        rts

; udivmod32(d1 = dividende, d2 = diviseur non nul) -> d1 = quotient, d3 = reste (non signés). Clobbe d4.
udivmod32:
        moveq   #0,d3
        moveq   #31,d4
.ud_lp:                              ; division par décalage-soustraction (68000 : pas de divu.l)
        add.l   d1,d1
        addx.l  d3,d3
        cmp.l   d2,d3
        blo     .ud_nb
        sub.l   d2,d3
        addq.l  #1,d1
.ud_nb:
        dbra    d4,.ud_lp
        rts


; bcpl_cli_setup(a6 = SysBase, a0 = Process) : crée le GV du CLI (pr_GlobVec) et son segarray (pr_SegList =
; [2, runtime, 0]). GV : chaque slot reçoit le stub de diagnostic de son offset, puis globin du runtime ; GV[0] = 150.
; Sans RAM -> champs laissés à 0. Préserve tout.
bcpl_cli_setup:
        movem.l d0-d2/a0-a3,-(sp)
        move.l  a0,a3                ; a3 = process
        move.l  #GV_SIZE,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .cs_ret
        move.l  d0,a0                ; remplissage par les stubs, du slot -50 au slot 150
        lea     bcpl_stubs(pc),a1
        move.w  #(GV_SIZE/4)-1,d2
.cs_fill:
        move.l  a1,(a0)+
        addq.l  #BCPL_STUBSZ,a1
        dbra    d2,.cs_fill
        add.l   #GV_NEG,d0
        move.l  d0,a2                ; a2 = slot 0
        move.l  #GV_MAX,(a2)
        lea     bcpl_rtseg(pc),a0
        move.l  a0,d1
        lsr.l   #2,d1
        bsr     rt_globin            ; installe le runtime dans ce GV
        move.l  a2,PR_GLOBVEC(a3)    ; APTR (pas BPTR)
        lea     bcpl_intuiname(pc),a1  ; GV[92] = IntuitionBase (openwindow, CloseWindow des handlers)
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,92*4(a2)
        moveq   #4,d1                ; segarray [4, runtime, 0, 0, CLI ROM] : Run recopie V!1 et V!2 du parent (V!2 = 0 :
        bsr     rt_getvec_raw        ; globin de 0 = rien) ; NewCLI recopie les entrées 0..4 et démarre son CLI sur
        tst.l   d0                   ; l'entrée 4 faute de résident « CLI » ; bloc getvec, libérable par freevec
        beq     .cs_ret
        move.l  d0,a0
        add.l   a0,a0
        add.l   a0,a0
        move.l  #4,(a0)
        lea     bcpl_rtseg(pc),a1
        move.l  a1,d1
        lsr.l   #2,d1
        move.l  d1,4(a0)
        clr.l   8(a0)
        clr.l   12(a0)
        move.l  #rcli_seg,d1
        lsr.l   #2,d1
        move.l  d1,16(a0)
        move.l  d0,PR_SEGLIST(a3)
.cs_ret:
        movem.l (sp)+,d0-d2/a0-a3
        rts

; rt_makeglobvec(d1 = segarray BPTR, a6 = SysBase) -> d0 = BPTR du slot 0 d'un GV neuf | 0 (Result2 = 103). Taille =
; plus grand « max » des segments de V!1..V!n (plancher 15), + 50 slots négatifs ; GV[0] = ce max (spec §8.1, 13).
; Les slots -50..150 reçoivent les stubs de diagnostic (la ROM les laisse indéfinis), au-delà 0. Préserve d1-d7/a2-a6.
rt_makeglobvec:
        movem.l d1-d4/a0-a1,-(sp)
        moveq   #15,d3               ; d3 = max retenu
        lsl.l   #2,d1
        beq.s   .mg_alloc
        move.l  d1,a0
        move.l  (a0)+,d2             ; n
        bra.s   .mg_next
.mg_seglp:
        move.l  (a0)+,d1             ; V!i : chaîne de hunks
.mg_hunk:
        lsl.l   #2,d1
        beq.s   .mg_next
        move.l  d1,a1
        move.l  (a1),d1              ; hunk suivant
        move.l  4(a1),d4             ; N (longs)
        lsl.l   #2,d4
        move.l  0(a1,d4.l),d4        ; dernier long = max
        cmp.l   d3,d4
        ble.s   .mg_hunk
        move.l  d4,d3
        bra.s   .mg_hunk
.mg_next:
        subq.l  #1,d2
        bpl.s   .mg_seglp
.mg_alloc:
        move.l  d3,d1
        add.l   #GV_NEGSLOTS,d1      ; slots -50..max
        bsr     rt_getvec_raw
        tst.l   d0
        beq.s   .mg_fail
        move.l  d0,d4
        lsl.l   #2,d0
        move.l  d0,a0                ; a0 = slot -50
        lea     bcpl_stubs(pc),a1
        move.l  d3,d2
        add.l   #GV_NEGSLOTS,d2      ; d2 = nombre de slots - 1
        moveq   #-GV_NEGSLOTS,d1     ; d1 = n° du slot courant
.mg_fill:
        cmp.l   #GV_MAX,d1
        bgt.s   .mg_zero
        move.l  a1,(a0)+
        addq.l  #BCPL_STUBSZ,a1
        bra.s   .mg_fnext
.mg_zero:
        clr.l   (a0)+
.mg_fnext:
        addq.l  #1,d1
        dbra    d2,.mg_fill
        move.l  d4,d0
        add.l   #GV_NEGSLOTS,d0      ; BPTR du slot 0
        move.l  d0,a0
        add.l   a0,a0
        add.l   a0,a0
        move.l  d3,(a0)              ; GV[0] = max
        bra.s   .mg_ret
.mg_fail:
        moveq   #103,d0
        bsr     rt_setr2
        moveq   #0,d0
.mg_ret:
        movem.l (sp)+,d1-d4/a0-a1
        rts

; bcpl_starthandler(a2 = DeviceNode, a0 = nom complet C (ex. « NEWCON:0/0/640/200/T »)) -> d0 = MsgPort du handler
; | 0 (Result2 = erreur), Result2 := dn_Lock en cas de succès. Spec §13.3 (globale 112) : charge dn_Handler dans
; dn_SegList s'il est vide (une seule fois) ; dn_GlobalVec = -1 -> handler C (process lancé directement sur le code
; du premier hunk, pile dn_StackSize en OCTETS) ; sinon handler BCPL : segarray [3, runtime, 0, dn_SegList], GV =
; dn_GlobalVec (partagé) ou makeglobvec, createproc (pile en LONGS, pri dn_Priority, nom dn_Name). Puis packet de
; démarrage synchrone : Arg1 = BSTR du nom complet, Arg2 = dn_Startup, Arg3 = BPTR du nœud, Res2 = GV (BCPL) ;
; succès si le handler répond Res1 != 0. dn_Task n'est pas écrit ici (c'est au handler de le faire). L'appelant doit
; être un process (la réponse arrive sur son pr_MsgPort). Préserve d1-d7/a0-a6.
bcpl_starthandler:
        movem.l d1-d7/a0-a6,-(sp)
        move.l  a0,a5                ; a5 = nom complet
        move.l  ($4).w,a6
        move.l  DN_SEGLIST(a2),d0
        bne.s   .sh_seg
        lea     -256(sp),sp
        move.l  DN_HANDLER(a2),d1
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  ($4).w,a6
        lea     256(sp),sp
        tst.l   d0
        beq     .sh_fail0            ; Result2 laissé par LoadSeg
        move.l  d0,DN_SEGLIST(a2)
.sh_seg:
        move.l  d0,d3                ; d3 = seglist du handler
        moveq   #3,d1                ; segarray [3, runtime, 0, seglist]
        bsr     rt_getvec_raw
        move.l  d0,d5
        beq     .sh_nomem
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  #3,(a0)+
        lea     bcpl_rtseg(pc),a1
        move.l  a1,d1
        lsr.l   #2,d1
        move.l  d1,(a0)+
        clr.l   (a0)+
        move.l  d3,(a0)
        move.l  a5,a0                ; BSTR du nom complet (getvec, libéré après la réponse)
        moveq   #0,d4
.sh_len:
        tst.b   (a0)+
        beq.s   .sh_lend
        addq.l  #1,d4
        cmp.l   #255,d4
        bcs.s   .sh_len
.sh_lend:
        move.l  d4,d1
        lsr.l   #2,d1                ; (L+1)/4 arrondi : getvec(L/4) = L/4+1 longs >= L+1 octets
        bsr     rt_getvec_raw
        move.l  d0,a4                ; a4 = BPTR du BSTR
        tst.l   d0
        beq     .sh_nomem
        lsl.l   #2,d0
        move.l  d0,a0
        move.b  d4,(a0)+
        move.l  a5,a1
        bra.s   .sh_cnext
.sh_ccpy:
        move.b  (a1)+,(a0)+
.sh_cnext:
        dbra    d4,.sh_ccpy
        move.l  DN_PRIORITY(a2),d7
        move.l  DN_STACKSIZE(a2),d6
        move.l  DN_GLOBALVEC(a2),d1
        cmp.l   #-1,d1
        beq.s   .sh_chandler
        lsl.l   #2,d6                ; BCPL : pile en longs
        add.l   #CP_STKEXTRA,d6
        lsl.l   #2,d1
        bne.s   .sh_gv
        move.l  d5,d1
        bsr     rt_makeglobvec
        tst.l   d0
        beq     .sh_freename
        move.l  d0,d1
        lsl.l   #2,d1
.sh_gv:
        move.l  d1,d2
        lsr.l   #2,d2                ; d2 = Res2 du packet = BPTR du GV
        move.l  DN_NAME(a2),d4
        bsr     rt_createproc        ; d0 = port | 0
        tst.l   d0
        beq     .sh_freename
        bra.s   .sh_started
.sh_chandler:                        ; handler C : process direct sur le code, nom C = dn_Name (NUL garanti)
        move.l  DN_NAME(a2),d0
        lsl.l   #2,d0
        move.l  d0,a0
        addq.l  #1,a0
        move.l  d3,d0
        lsl.l   #2,d0
        move.l  d0,a1
        addq.l  #4,a1                ; entrée = premier hunk
        move.l  d7,d0
        move.l  d6,d1
        jsr     LVO_FORBID(a6)
        jsr     proc_create
        move.l  d0,d4                ; d4 = port (Permit écrase d0/d1)
        beq.s   .sh_cfail
        move.l  d0,a0
        lea     -PR_MSGPORT(a0),a0
        move.l  d5,PR_SEGLIST(a0)
        bsr     rt_this
        move.l  PR_CONSOLETASK(a3),PR_CONSOLETASK(a0)
        move.l  PR_FILESYSTEMTASK(a3),PR_FILESYSTEMTASK(a0)
        move.l  PR_WINDOWPTR(a3),PR_WINDOWPTR(a0)
        jsr     LVO_PERMIT(a6)
        move.l  d4,d0
        moveq   #0,d2                ; Res2 = 0 (pas de GV)
        bra.s   .sh_started
.sh_cfail:
        jsr     LVO_PERMIT(a6)
        moveq   #103,d0
        bsr     rt_setr2
        bra     .sh_freename
.sh_started:
        move.l  d0,a3                ; a3 = port du handler
        lea     -(SP_SIZEOF+2)(sp),sp ; packet de démarrage, aligné sur un long (le handler le reçoit en BPTR)
        move.l  sp,d0
        btst    #1,d0
        beq.s   .sh_palign
        addq.l  #2,d0
.sh_palign:
        move.l  d0,a1                ; a1 = message
        move.l  d0,a0
        moveq   #SP_SIZEOF/2-1,d0
.sh_pclr:
        clr.w   (a0)+
        dbra    d0,.sh_pclr
        lea     SP_PKT(a1),a0        ; a0 = packet
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.w  #DP_SIZEOF,MN_LENGTH(a1)
        move.l  a0,LN_NAME(a1)
        move.l  a1,DP_LINK(a0)
        move.l  EB_THISTASK(a6),d0
        add.l   #PR_MSGPORT,d0
        move.l  d0,d6                ; d6 = notre port de réponse
        move.l  d0,MN_REPLYPORT(a1)
        move.l  d0,DP_PORT(a0)
        move.l  a4,DP_ARG1(a0)
        move.l  DN_STARTUP(a2),DP_ARG2(a0)
        move.l  a2,d0
        lsr.l   #2,d0
        move.l  d0,DP_ARG3(a0)
        move.l  d2,DP_RES2(a0)
        move.l  a3,a0
        jsr     LVO_PUTMSG(a6)       ; PutMsg(port a0, message a1)
.sh_wait:
        move.l  d6,a0
        jsr     LVO_WAITPORT(a6)
        move.l  d6,a0
        jsr     LVO_GETMSG(a6)
        move.l  sp,d1
        btst    #1,d1
        beq.s   .sh_galign
        addq.l  #2,d1
.sh_galign:
        cmp.l   d1,d0
        bne.s   .sh_wait
        move.l  d0,a0
        move.l  SP_PKT+DP_RES1(a0),d7
        move.l  SP_PKT+DP_RES2(a0),d2
        lea     SP_SIZEOF+2(sp),sp
        bsr.s   .sh_free_a4
        tst.l   d7
        beq.s   .sh_refused
        move.l  DN_LOCK(a2),d0
        bsr     rt_setr2
        move.l  a3,d0
        bra.s   .sh_ret
.sh_refused:
        move.l  d2,d0
        bsr     rt_setr2
        moveq   #0,d0
        bra.s   .sh_ret
.sh_nomem:
        moveq   #103,d0
        bsr     rt_setr2
        bra.s   .sh_fail0
.sh_freename:
        bsr.s   .sh_free_a4
.sh_fail0:
        moveq   #0,d0
.sh_ret:
        movem.l (sp)+,d1-d7/a0-a6
        rts
.sh_free_a4:                         ; libère le BSTR du nom complet (a4 = BPTR | 0)
        move.l  a4,d0
        lsl.l   #2,d0
        beq.s   .sh_fr
        move.l  d0,a1
        subq.l  #4,a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
.sh_fr:
        rts

; bcpl_cli_register(a0 = Process) : prend le premier slot libre de rn_TaskArray pour ce CLI (taskid = MsgPort) et
; pose pr_TaskNum. Préserve tout.
bcpl_cli_register:
        movem.l d0-d1/a0-a2/a6,-(sp)
        move.l  a0,a2
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  DOS_DOSBASE,a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_TASKARRAY(a0),d0
        lsl.l   #2,d0
        beq.s   .cr_done
        move.l  d0,a0
        move.l  (a0)+,d1             ; taille
        moveq   #1,d0
.cr_lp:
        cmp.l   d1,d0
        bhi.s   .cr_done             ; plein
        tst.l   (a0)
        beq.s   .cr_take
        addq.l  #4,a0
        addq.l  #1,d0
        bra.s   .cr_lp
.cr_take:
        lea     PR_MSGPORT(a2),a1
        move.l  a1,(a0)
        move.l  d0,PR_TASKNUM(a2)
.cr_done:
        jsr     LVO_PERMIT(a6)
        movem.l (sp)+,d0-d1/a0-a2/a6
        rts

; bcpl_proc_entry : corps de tout process créé par createproc (spec §2.4). Pile remplie de $ABABABAB, frame BCPL de
; base au BAS de la pile (!1 = -1, !2 = limite haute), GV[12] := BPTR(base), globin de chaque segment du segarray
; dans pr_GlobVec, attente du packet de démarrage, puis start(pkt) (globale 1, frame 32 o). Au retour : fin du process.
BP_STKMARGIN    EQU 256              ; zone non remplie sous le SP courant (pile du trampoline)
bcpl_proc_entry:
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a3   ; a3 = process
        move.l  TC_SPLOWER(a3),a0
        lea     -BP_STKMARGIN(sp),a1
        move.l  #$ABABABAB,d0
.pe_fill:
        cmp.l   a1,a0
        bhs.s   .pe_filled
        move.l  d0,(a0)+
        bra.s   .pe_fill
.pe_filled:
        move.l  TC_SPLOWER(a3),a4    ; a4 = frame de base
        moveq   #-1,d0
        move.l  d0,4(a4)
        move.l  TC_SPUPPER(a3),d0
        sub.l   #160,d0
        move.l  d0,8(a4)
        move.l  PR_GLOBVEC(a3),a2    ; a2 = GV
        move.l  a4,d0
        lsr.l   #2,d0
        move.l  d0,12*4(a2)          ; GV[12] = currco / base de pile BCPL
        move.l  PR_SEGLIST(a3),d0    ; globin de V!1..V!n
        lsl.l   #2,d0
        beq.s   .pe_wait
        move.l  d0,a5
        move.l  (a5)+,d7             ; n
.pe_glob:
        subq.l  #1,d7
        bmi.s   .pe_wait
        move.l  (a5)+,d1
        movem.l d7/a3-a5,-(sp)
        bsr     rt_globin
        movem.l (sp)+,d7/a3-a5
        bra.s   .pe_glob
.pe_wait:                            ; packet de démarrage
        lea     PR_MSGPORT(a3),a0
        jsr     LVO_WAITPORT(a6)
        lea     PR_MSGPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .pe_wait
        move.l  d0,a0
        move.l  LN_NAME(a0),d1
        lsr.l   #2,d1                ; d1 = BPTR du packet
        clr.l   -(sp)                ; pr_ReturnAddr -> ce long : stop(n) fait SP := ReturnAddr-4 puis rts ->
        move.l  sp,PR_RETURNADDR(a3) ; revient sur .pe_end (sinon SP = -4 : faute au premier stop)
        pea     .pe_end(pc)
        sub.l   a0,a0
        move.l  a4,a1                ; a1 = frame de base
        move.l  4(a2),a4             ; start = GV[1]
        moveq   #32,d0
        lea     bcpl_call(pc),a5
        lea     bcpl_ret(pc),a6
        jsr     (a5)                 ; start(pkt) ; retour normal ou stop -> .pe_end
.pe_end:
        move.l  ($4).w,a6
        sub.l   a1,a1
        jsr     LVO_REMTASK(a6)      ; fin du process (RemTask(0) ne revient pas)
.pe_hang:
        bra.s   .pe_hang

; ===================================== primitives internes (convention 68000) ===================================

; rt_globin(d1 = BPTR chaîne de segments, a2 = GV) -> d0 = -1 (succès) / 0 (Result2 = 111). Pour chaque segment
; (lien en tête), lit la table en fin de hunk : dernier long = max (ignoré), puis paires (globale, offset octet depuis
; le début des données) en descendant jusqu'à un offset nul. GV[n] := données + offset. Clobbe d0-d3/a0.
rt_globin:
.gi_seg:
        lsl.l   #2,d1
        beq     .gi_ok
        move.l  d1,a0                ; a0 = segment
        move.l  (a0),d1              ; lien suivant (BPTR)
        lea     4(a0),a0             ; a0 = début des données (long N)
        move.l  (a0),d2
        lsl.l   #2,d2
        lea     -4(a0,d2.l),a1       ; a1 -> long « max »
.gi_pair:
        move.l  -(a1),d3             ; offset (0 = terminateur)
        beq     .gi_seg
        move.l  -(a1),d2             ; numéro de globale
        cmp.l   (a2),d2
        bgt     .gi_fail             ; > GV[0] (signé : les négatives passent)
        add.l   a0,d3
        lsl.l   #2,d2
        move.l  d3,0(a2,d2.l)
        bra     .gi_pair
.gi_ok:
        moveq   #-1,d0
        rts
.gi_fail:
        moveq   #ERR_GLOBIN,d0
        bsr     rt_setr2
        moveq   #0,d0
        rts

; rt_getvec_raw(d1 = n, a6 = SysBase) -> d0 = BPTR d'un vecteur de n+1 longs (non effacé) | 0. En-tête caché à -4 =
; taille totale en octets (pour freevec). Préserve d1-d7/a2-a6.
rt_getvec_raw:
        movem.l d1/a0-a1,-(sp)
        moveq   #0,d0
        tst.l   d1
        bmi     .gv_ret
        addq.l  #2,d1                ; n+1 longs + en-tête
        lsl.l   #2,d1
        move.l  d1,-(sp)
        move.l  d1,d0
        move.l  #MEMF_PUBLIC,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  (sp)+,d1
        tst.l   d0
        beq     .gv_ret
        move.l  d0,a0
        move.l  d1,(a0)+             ; en-tête = taille
        move.l  a0,d0
        lsr.l   #2,d0
.gv_ret:
        movem.l (sp)+,d1/a0-a1
        rts

; rt_setr2(d0) : pr_Result2 de ThisTask := d0. Préserve tout.
rt_setr2:
        move.l  a0,-(sp)
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  d0,PR_RESULT2(a0)
        move.l  (sp)+,a0
        rts

; rt_this() -> a3 = ThisTask (process). Préserve tout le reste.
rt_this:
        move.l  ($4).w,a3
        move.l  EB_THISTASK(a3),a3
        rts

; rt_write(a0 = tampon, d0 = longueur) : Write(output(), ...) via dos. Préserve tout.
rt_write:
        movem.l d0-d3/a0-a1/a3/a6,-(sp)
        tst.l   d0
        beq     .wr_ret
        move.l  d0,d3
        move.l  a0,d2
        bsr     rt_this
        move.l  PR_COS(a3),d1
        beq     .wr_ret
        jsr     dos_bufwrite            ; dos_lib.s : différé vers un fichier, immédiat vers une console
.wr_ret:
        movem.l (sp)+,d0-d3/a0-a1/a3/a6
        rts

; rt_cstr(d1 = BSTR (BPTR), a0 = tampon >= 256 o) : copie en C-string NUL-terminée. Préserve tout.
rt_cstr:
        movem.l d0-d1/a0-a1,-(sp)
        lsl.l   #2,d1
        beq     .cs_empty
        move.l  d1,a1
        moveq   #0,d0
        move.b  (a1)+,d0
        bra     .cs_next
.cs_cpy:
        move.b  (a1)+,(a0)+
.cs_next:
        dbra    d0,.cs_cpy
.cs_empty:
        clr.b   (a0)
        movem.l (sp)+,d0-d1/a0-a1
        rts

; rt_upper(d0.b) -> d0.b en majuscule (a-z). Préserve le reste.
rt_upper:
        cmp.b   #'a',d0
        blo     .up_ret
        cmp.b   #'z',d0
        bhi     .up_ret
        sub.b   #'a'-'A',d0
.up_ret:
        rts

; --- flux d'entrée (layout FileHandle §5.1 : fh_Buf BPTR, fh_Pos/fh_End index octets) ---
; rt_rdch() -> d0 = caractère (0..255) | -1 (EOF), sur input(). Remplit le tampon (200 o) par Read si épuisé.
; Préserve tout sauf d0.
rt_rdch:
        movem.l d1-d3/a0-a1/a3/a6,-(sp)
        bsr     rt_this
        move.l  PR_CIS(a3),d0
        lsl.l   #2,d0
        beq     .rc_eof
        move.l  d0,a3                ; a3 = FileHandle
        move.l  FH_POS(a3),d0
        cmp.l   FH_END(a3),d0
        bge     .rc_refill
.rc_take:
        move.l  FH_BUF(a3),d1
        lsl.l   #2,d1
        move.l  d1,a0
        moveq   #0,d1
        move.b  0(a0,d0.l),d1
        addq.l  #1,FH_POS(a3)
        move.l  d1,d0
        bra     .rc_ret
.rc_refill:
        tst.l   FH_END(a3)
        beq     .rc_eof              ; fh_End = 0 : EOF sans contacter le handler
        tst.l   FH_BUF(a3)
        bne     .rc_read
        move.l  ($4).w,a6
        moveq   #RT_FHBUFLONGS,d1    ; tampon paresseux de 200 octets (Close le reconnaît à sa taille)
        bsr     rt_getvec_raw
        move.l  d0,FH_BUF(a3)
        beq     .rc_fail
.rc_read:
        move.l  a3,-(sp)
        bsr     rt_this
        move.l  PR_COS(a3),d1
        move.l  (sp)+,a3
        jsr     dos_flushout         ; invite sans retour à la ligne : visible avant d'attendre la saisie
        move.l  a3,d1
        lsr.l   #2,d1                ; fh (BPTR)
        move.l  FH_BUF(a3),d2
        lsl.l   #2,d2
        move.l  #200,d3
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_READ(a6)
        tst.l   d0
        ble     .rc_fail
        move.l  d0,FH_END(a3)
        clr.l   FH_POS(a3)
        moveq   #0,d0
        bra     .rc_take
.rc_fail:
        clr.l   FH_POS(a3)
        clr.l   FH_END(a3)
.rc_eof:
        moveq   #-1,d0
.rc_ret:
        movem.l (sp)+,d1-d3/a0-a1/a3/a6
        rts

; rt_unrdch() -> d0 = -1 si le caractère est rendu (fh_Pos > 0, ou EOF relisible fh_End = 0), 0 sinon.
rt_unrdch:
        move.l  a3,-(sp)
        bsr     rt_this
        move.l  PR_CIS(a3),d0
        lsl.l   #2,d0
        beq     .ur_no
        move.l  d0,a3
        tst.l   FH_POS(a3)
        ble     .ur_end
        subq.l  #1,FH_POS(a3)
        bra     .ur_yes
.ur_end:
        tst.l   FH_END(a3)
        bne     .ur_no
.ur_yes:
        moveq   #-1,d0
        bra     .ur_ret
.ur_no:
        moveq   #0,d0
.ur_ret:
        move.l  (sp)+,a3
        rts

; --- tampon de sortie de writef & co : a3 = position, a5 = début (sur la pile de l'appelant, WF_BUFSZ) ---
; wf_putc(d0.b) : ajoute un caractère, vide si plein. Préserve tout sauf a3.
wf_putc:
        move.b  d0,(a3)+
        move.l  d0,-(sp)
        move.l  a3,d0
        sub.l   a5,d0
        cmp.l   #WF_BUFSZ,d0
        movem.l (sp)+,d0             ; movem ne touche pas le CCR
        blo     wf_ret
wf_flush:                            ; vide le tampon (a5..a3) ; préserve tout sauf a3 (remis à a5)
        movem.l d0/a0,-(sp)
        move.l  a3,d0
        sub.l   a5,d0
        move.l  a5,a0
        bsr     rt_write
        move.l  a5,a3
        movem.l (sp)+,d0/a0
wf_ret:
        rts

; wf_bstr(d1 = BSTR) -> écrit les caractères ; d2 = nombre écrit. Préserve d1.
wf_bstr:
        movem.l d1/a0,-(sp)
        moveq   #0,d2
        lsl.l   #2,d1
        beq     .wb_ret
        move.l  d1,a0
        moveq   #0,d1
        move.b  (a0)+,d1
        move.l  d1,d2
        bra     .wb_next
.wb_lp:
        move.b  (a0)+,d0
        bsr     wf_putc
.wb_next:
        dbra    d1,.wb_lp
.wb_ret:
        movem.l (sp)+,d1/a0
        rts

; wf_spaces(d0 = nombre) : écrit d0 espaces (rien si <= 0).
wf_spaces:
        move.l  d1,-(sp)
        move.l  d0,d1
        bra     .sp_next
.sp_lp:
        moveq   #' ',d0
        bsr     wf_putc
.sp_next:
        subq.l  #1,d1
        bpl     .sp_lp
        move.l  (sp)+,d1
        rts

; wf_num(d1 = valeur, d2 = largeur, d3 = base 10/16/8, d4 = mode) : mode 0 = décimal signé cadré à droite sur d2
; (espaces avant le signe) ; 1 = décimal non signé cadré à droite ; 2 = exactement d2 chiffres (zéros de tête, bits
; hauts tronqués ; d2 <= 1 -> 1 chiffre) — hexa majuscules / octal. Préserve d1-d7.
wf_num:
        movem.l d1-d7/a0,-(sp)
        lea     -16(sp),sp
        lea     16(sp),a0            ; chiffres écrits de droite à gauche
        moveq   #0,d6                ; d6 = 1 si négatif
        cmp.w   #2,d4
        beq     .wn_fixed
        tst.w   d4
        bne     .wn_conv
        tst.l   d1
        bpl     .wn_conv
        neg.l   d1
        moveq   #1,d6
.wn_conv:
        move.l  d2,d7                ; d7 = largeur
        move.l  d3,d2                ; diviseur
.wn_dlp:
        movem.l d4,-(sp)
        bsr     udivmod32            ; d1 /= base, d3 = chiffre
        movem.l (sp)+,d4
        bsr     .wn_digit
        tst.l   d1
        bne     .wn_dlp
        tst.w   d6
        beq     .wn_pad
        move.b  #'-',-(a0)
.wn_pad:
        lea     16(sp),a1
        move.l  a1,d0
        sub.l   a0,d0                ; longueur produite
        sub.l   d0,d7
        move.l  d7,d0
        bsr     wf_spaces
        bra     .wn_out
.wn_fixed:                           ; exactement d2 chiffres
        move.l  d2,d7
        cmp.l   #1,d7
        bge     .wn_fx
        moveq   #1,d7
.wn_fx:
        cmp.l   #16,d7
        ble     .wn_fx2
        moveq   #16,d7
.wn_fx2:
        move.l  d3,d2
        move.l  d7,d5
.wn_flp:
        movem.l d4,-(sp)
        bsr     udivmod32
        movem.l (sp)+,d4
        bsr     .wn_digit
        subq.l  #1,d5
        bne     .wn_flp
.wn_out:
        lea     16(sp),a1
.wn_emit:
        cmp.l   a1,a0
        bhs     .wn_done
        move.b  (a0)+,d0
        bsr     wf_putc
        bra     .wn_emit
.wn_done:
        lea     16(sp),sp
        movem.l (sp)+,d1-d7/a0
        rts
.wn_digit:                           ; d3 = chiffre -> -(a0)
        move.b  d3,d0
        add.b   #'0',d0
        cmp.b   #'9',d0
        bls     .wd_ok
        addq.b  #7,d0
.wd_ok:
        move.b  d0,-(a0)
        rts

; ====================================== globales (convention BCPL) =============================================
; Entrée : a1 = frame, d1-d4 = arguments. BENTER sauve a0-a2/a5-a6 et copie la frame dans a4 ; BLEAVE les restaure
; (A0 = 0 compris) et retourne par A6 avec le résultat dans d1.
BENTER          MACRO
        movem.l a0-a2/a5-a6,-(sp)
        move.l  a1,a4
                ENDM
BLEAVE          MACRO
        movem.l (sp)+,a0-a2/a5-a6
        jmp     (a6)
                ENDM

; 2 stop(code) : sortie de commande -> SP := pr_ReturnAddr - 4 puis rts avec d0 = code (le lanceur restaure tout).
g_stop:
        bsr     rt_this
        move.l  d1,d0
        move.l  PR_RETURNADDR(a3),sp
        subq.l  #4,sp
        rts

; 10 result2(set, v) : set = 0 -> renvoie pr_Result2 ; sinon renvoie l'ancien et écrit v.
g_result2:
        bsr     rt_this
        move.l  PR_RESULT2(a3),d0
        tst.l   d1
        beq     .r2_get
        move.l  d2,PR_RESULT2(a3)
.r2_get:
        move.l  d0,d1
        jmp     (a6)

; 14 taskid() -> MsgPort du process courant.
g_taskid:
        bsr     rt_this
        lea     PR_MSGPORT(a3),a3
        move.l  a3,d1
        jmp     (a6)

; 28 globin(seg) -> -1 / 0 (Result2 = 111), dans le GV courant (A2).
g_globin:
        BENTER
        bsr     rt_globin
        move.l  d0,d1
        BLEAVE

; 29 getvec(n) -> BPTR d'un vecteur de n+1 longs | 0.
g_getvec:
        BENTER
        move.l  ($4).w,a6
        bsr     rt_getvec_raw
        move.l  d0,d1
        BLEAVE

; 30 freevec(v) : libère un vecteur getvec (v = 0 : rien).
g_freevec:
        BENTER
        lsl.l   #2,d1
        beq     .fv_ret
        move.l  d1,a1
        subq.l  #4,a1
        move.l  (a1),d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
.fv_ret:
        BLEAVE

; 35 parentdir(lock) -> lock du répertoire parent | 0 (racine) : packet ACTION_PARENT (29) au handler du lock.
g_parentdir:
        BENTER
        move.l  d1,d0
        lsl.l   #2,d0
        beq     .pd_root
        move.l  d0,a0
        move.l  FL_TASK(a0),a1       ; port du handler
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        moveq   #ACTION_PARENT,d0
        moveq   #0,d2
        moveq   #0,d3
        move.l  ($4).w,a6
        jsr     dos_sendpkt          ; d0 = dp_Res1 ; Result2 posé
        lea     SP_SIZEOF(sp),sp
        move.l  d0,d1
        BLEAVE
.pd_root:
        moveq   #0,d1
        BLEAVE

; 114 errorreq(...) : requester d'erreur disque -> TRUE = abandon, FALSE = réessayer (observé dans c:Dir, qui reboucle
; sur ExNext tant qu'errorreq rend 0). Pas de requester Intuition à ce stade : toujours TRUE.
g_errorreq:
        moveq   #-1,d1
        jmp     (a6)

; 17 level() -> frame de l'appelant (APTR) ; 18 longjump(level, label) : reprend à label dans la frame level.
g_level:
        move.l  -12(a1),d1
        jmp     (a6)
g_longjump:
        move.l  d1,a1                ; frame cible
        move.l  -4(a1),a4            ; routine propriétaire de cette frame
        move.l  d2,a3
        jmp     (a3)

; 19 getmem(n, flags) : comme getvec mais avec les attributs AllocMem donnés (ex. MEMF_PUBLIC|MEMF_CLEAR).
g_getmem:
        BENTER
        moveq   #0,d0
        tst.l   d1
        bmi.s   .gm_ret
        addq.l  #2,d1
        lsl.l   #2,d1
        move.l  d1,d3                ; d3 = taille totale
        move.l  d1,d0
        move.l  d2,d1
        move.l  ($4).w,a6
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .gm_ret
        move.l  d0,a0
        move.l  d3,(a0)+
        move.l  a0,d0
        lsr.l   #2,d0
.gm_ret:
        move.l  d0,d1
        BLEAVE

; 47 delay(ticks) : 1/50 s (= LVO Delay).
g_delay:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_DELAY(a6)
        moveq   #0,d1
        BLEAVE

; 59 findinput(nom) / 60 findoutput(nom) -> FileHandle (BPTR) | 0 ; 93 endstream(fh) ; 63 endread() / 64 endwrite().
g_findinput:
        move.l  #MODE_OLDFILE,d2
        bra.s   g_findstream
g_findoutput:
        move.l  #MODE_NEWFILE,d2
g_findstream:
        BENTER
        lea     -256(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE
g_endread:
        bsr     rt_this
        move.l  PR_CIS(a3),d1
        bra.s   g_endstream
g_endwrite:
        bsr     rt_this
        move.l  PR_COS(a3),d1
g_endstream:
        BENTER
        tst.l   d1
        beq.s   .es_ret
        bsr     rt_this
        move.l  PR_RESULT2(a3),d7    ; Result2 préservé (spec §5.1)
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_CLOSE(a6)
        move.l  d7,d0
        bsr     rt_setr2
.es_ret:
        BLEAVE

; 81 load(nom) -> seglist (LoadSeg, nom BSTR) ; 82 unloadseg(seg).
g_load:
        BENTER
        lea     -256(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE
g_unloadseg:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
        BLEAVE

; 88 callexec(lvo, d0, d1, a0, a1, a2) / 103 calllib(base, lvo, d0, d1, a0, a1) -> d0 de la fonction appelée.
g_callexec:
        BENTER
        move.l  d1,d7                ; lvo
        move.l  d2,d0
        move.l  d3,d1
        move.l  d4,a0
        movem.l 16(a4),a1-a2
        move.l  ($4).w,a6
        jsr     0(a6,d7.l)
        move.l  d0,d1
        BLEAVE
g_calllib:
        BENTER
        move.l  d1,a6                ; base
        move.l  d2,d7                ; lvo
        move.l  d3,d0
        move.l  d4,d1
        movem.l 16(a4),a0-a1
        jsr     0(a6,d7.l)
        move.l  d0,d1
        BLEAVE

; 90 deleteobj(nom) -> booléen (ACTION_DELETE_OBJECT) / 125 createdir(nom) -> lock | 0 (ACTION_CREATE_DIR) : nom BSTR,
; par les LVO DeleteFile / CreateDir (résolution du nom et démarrage du handler compris).
g_deleteobj:
        moveq   #DOS_LVO_DELETEFILE,d0
        bra.s   g_namelvo
g_createdir:
        moveq   #DOS_LVO_CREATEDIR,d0
g_namelvo:
        BENTER
        lea     -256(sp),sp
        move.l  d0,d7
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        move.l  DOS_DOSBASE,a6
        jsr     0(a6,d7.w)
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE

; 91 rename(ancien, nouveau) : noms BSTR -> booléen (LVO Rename : ACTION_RENAME_OBJECT ; handlers différents ->
; Result2 = 215).
g_rename:
        BENTER
        lea     -512(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  d2,d1
        lea     256(sp),a0
        bsr     rt_cstr
        move.l  sp,d1
        lea     256(sp),a0
        move.l  a0,d2
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_RENAME(a6)
        move.l  d0,d1
        lea     512(sp),sp
        BLEAVE

; 113 copydir(lock) -> DupLock (ACTION_COPY_DIR au handler du lock) ; 0 -> 0.
g_copydir:
        BENTER
        move.l  d1,d0
        lsl.l   #2,d0
        beq.s   .cp_zero
        move.l  d0,a0
        move.l  FL_TASK(a0),a1
        lea     -SP_SIZEOF(sp),sp
        move.l  sp,a0
        moveq   #ACTION_COPY_DIR,d0
        moveq   #0,d2
        moveq   #0,d3
        move.l  ($4).w,a6
        jsr     dos_sendpkt
        lea     SP_SIZEOF(sp),sp
        move.l  d0,d1
        BLEAVE
.cp_zero:
        moveq   #0,d1
        BLEAVE

; -2 copyvec(src, dst, n) : copie n+1 longs de BADDR(src) vers BADDR(dst).
g_copyvec:
        lsl.l   #2,d1
        move.l  d1,a3
        lsl.l   #2,d2
        move.l  d2,a4                ; (a4 rechargé par bcpl_ret)
.cv_lp:
        move.l  (a3)+,(a4)+
        subq.l  #1,d3
        bpl.s   .cv_lp
        jmp     (a6)

; 107 splitname(préfixe, car, chaîne, pos) : copie les caractères du BSTR chaîne à partir de la position pos (1 = 1er
; caractère) jusqu'à car (exclu) dans le BSTR préfixe (30 caractères max) -> position après car | 0 si car absent.
g_splitname:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a0                ; a0 = préfixe
        lsl.l   #2,d3
        move.l  d3,a3                ; a3 = chaîne
        moveq   #0,d5
        move.b  (a3),d5              ; d5 = longueur de la chaîne
        moveq   #0,d6                ; d6 = longueur du préfixe
        move.l  d4,d7                ; d7 = position courante
.sn_lp:
        cmp.l   d5,d7
        bgt.s   .sn_none
        move.b  0(a3,d7.l),d0
        addq.l  #1,d7
        cmp.b   d2,d0
        beq.s   .sn_hit
        cmp.l   #30,d6
        bhs.s   .sn_lp
        addq.l  #1,d6
        move.b  d0,0(a0,d6.l)
        bra.s   .sn_lp
.sn_hit:
        move.b  d6,(a0)
        move.l  d7,d1
        BLEAVE
.sn_none:
        move.b  d6,(a0)
        moveq   #0,d1
        BLEAVE

; rt_devinfo() -> a0 = DosInfo (adresse). Clobbe d0.
rt_devinfo:
        move.l  DOS_DOSBASE,a0
        move.l  DL_ROOT(a0),a0
        move.l  RN_INFO(a0),d0
        lsl.l   #2,d0
        move.l  d0,a0
        rts

; 85 makedevnode(nom) : nom BSTR sans « : ». Nœud DosList de 11 longs (getvec) + copie du nom (suivie d'un NUL),
; champs à 0 sauf dn_Name et dn_GlobalVec (laissé à l'appelant), inséré en tête de di_DevInfo sous Forbid.
; -> BPTR du nœud | 0 (Result2 = 103).
g_makedevnode:
        BENTER
        move.l  ($4).w,a6
        move.l  d1,d5                ; d5 = nom
        moveq   #10,d1
        bsr     rt_getvec_raw
        move.l  d0,d6                ; d6 = nœud (BPTR)
        beq     .md_fail
        move.l  d5,d0
        lsl.l   #2,d0
        move.l  d0,a3                ; a3 = nom source
        moveq   #0,d1
        move.b  (a3),d1
        addq.l  #1,d1
        lsr.l   #2,d1                ; getvec((L+1)/4) = (L+1)/4+1 longs >= L+2 octets (longueur + L car. + NUL)
        bsr     rt_getvec_raw
        tst.l   d0
        beq     .md_free
        move.l  d0,d7                ; d7 = copie du nom (BPTR)
        lsl.l   #2,d0
        move.l  d0,a4
        moveq   #0,d1
        move.b  (a3),d1
.md_cpy:
        move.b  (a3)+,(a4)+
        dbra    d1,.md_cpy
        clr.b   (a4)                 ; NUL après le nom (CreateProc d'un handler C l'utilise comme chaîne C)
        move.l  d6,d0
        lsl.l   #2,d0
        move.l  d0,a3                ; a3 = nœud
        moveq   #DN_GLOBALVEC/4-1,d1
        move.l  a3,a4
.md_clr:
        clr.l   (a4)+
        dbra    d1,.md_clr
        move.l  d7,DN_NAME(a3)
        jsr     LVO_FORBID(a6)
        bsr     rt_devinfo
        move.l  DI_DEVINFO(a0),DN_NEXT(a3)
        move.l  d6,DI_DEVINFO(a0)
        jsr     LVO_PERMIT(a6)
        move.l  d6,d1
        BLEAVE
.md_free:
        move.l  d6,d0
        lsl.l   #2,d0
        move.l  d0,a1
        subq.l  #4,a1
        move.l  (a1),d0
        jsr     LVO_FREEMEM(a6)
.md_fail:
        moveq   #103,d0              ; ERROR_NO_FREE_STORE
        bsr     rt_setr2
        moveq   #0,d1
        BLEAVE

; 124 finddevinfo(nom) : nom BSTR sans « : », insensible à la casse -> premier nœud DLT_DEVICE de ce nom, sinon le
; dernier nœud homonyme d'un autre type, sinon 0. Result2 inchangé.
g_finddevinfo:
        BENTER
        move.l  d1,d5                ; d5 = nom cherché
        moveq   #0,d6                ; d6 = dernier homonyme non-device
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        bsr     rt_devinfo
        move.l  DI_DEVINFO(a0),d7
.fd_lp:
        lsl.l   #2,d7
        beq.s   .fd_end
        move.l  d7,a3
        move.l  DN_NAME(a3),d1
        move.l  d5,d2
        movem.l a3,-(sp)
        bsr     rt_compbstr
        movem.l (sp)+,a3
        tst.l   d0
        bne.s   .fd_next
        move.l  a3,d0
        lsr.l   #2,d0
        tst.l   DN_TYPE(a3)
        beq.s   .fd_dev
        move.l  d0,d6
.fd_next:
        move.l  DN_NEXT(a3),d7
        bra.s   .fd_lp
.fd_dev:
        move.l  d0,d6
.fd_end:
        jsr     LVO_PERMIT(a6)
        move.l  d6,d1
        BLEAVE

; -26 IsInteractive(fh) : renvoie fh_Interactive brut (non normalisé, comme la V34).
g_isinteractive:
        lsl.l   #2,d1
        beq.s   .ia_ret
        move.l  d1,a3
        move.l  FH_INTERACTIVE(a3),d1
.ia_ret:
        jmp     (a6)

; 33 createproc(segarray, pile, pri, nom, gv) : pile en LONGS, nom BSTR, gv BPTR (5e argument ; 0 -> GV du créateur).
; Process + pile (proc_create), hérite ConsoleTask/FileSystemTask/WindowPtr, démarre dans bcpl_proc_entry. Sous
; Forbid jusqu'à ce que les champs soient posés. -> taskid (MsgPort) | 0 (Result2 = 103).
g_createproc:
        BENTER
        move.l  d1,d5                ; segarray
        move.l  d2,d6
        lsl.l   #2,d6                ; pile en octets
        add.l   #CP_STKEXTRA,d6      ; marge : notre runtime utilise la pile 68000 (tampons, packets)
        move.l  d3,d7                ; pri
        move.l  16(a4),d1            ; gv (5e argument)
        lsl.l   #2,d1
        bsr     rt_createproc
        move.l  d0,d1
        BLEAVE

; rt_createproc(d1 = GV APTR (0 -> GV du créateur), d4 = nom BSTR, d5 = segarray BPTR, d6 = pile en octets, d7 = pri)
; -> d0 = taskid (MsgPort) | 0 (Result2 = 103). Process démarrant dans bcpl_proc_entry ; hérite ConsoleTask,
; FileSystemTask, WindowPtr du créateur ; champs posés sous Forbid. Préserve d1-d7/a0-a6.
rt_createproc:
        movem.l d1-d2/a0-a1/a3/a6,-(sp)
        move.l  ($4).w,a6
        move.l  d1,d2                ; d2 = GV
        moveq   #32,d0               ; nom C (vit autant que le process)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .cp_fail
        move.l  d0,a0
        move.l  d4,d1
        lsl.l   #2,d1
        beq.s   .cp_named
        move.l  d1,a1
        moveq   #0,d1
        move.b  (a1)+,d1
        cmp.w   #31,d1
        bls.s   .cp_ncpy
        moveq   #31,d1
        bra.s   .cp_ncpy
.cp_nlp:
        move.b  (a1)+,(a0)+
.cp_ncpy:
        dbra    d1,.cp_nlp
.cp_named:
        move.l  d0,-(sp)             ; nom C (libéré si la création échoue)
        move.l  d0,a0
        jsr     LVO_FORBID(a6)
        lea     bcpl_proc_entry(pc),a1
        move.l  d7,d0
        move.l  d6,d1
        jsr     proc_create          ; d0 = &pr_MsgPort | 0
        move.l  (sp)+,a3             ; (Permit peut écraser a0/a1)
        tst.l   d0
        beq.s   .cp_failp
        move.l  d0,a0
        lea     -PR_MSGPORT(a0),a0   ; a0 = nouveau process
        bsr     rt_this              ; a3 = créateur
        move.l  d5,PR_SEGLIST(a0)
        tst.l   d2
        bne.s   .cp_gv
        move.l  PR_GLOBVEC(a3),d2
.cp_gv:
        move.l  d2,PR_GLOBVEC(a0)
        move.l  PR_CONSOLETASK(a3),PR_CONSOLETASK(a0)
        move.l  PR_FILESYSTEMTASK(a3),PR_FILESYSTEMTASK(a0)
        move.l  PR_WINDOWPTR(a3),PR_WINDOWPTR(a0)
        jsr     LVO_PERMIT(a6)
        bra.s   .cp_ret
.cp_failp:
        jsr     LVO_PERMIT(a6)
        move.l  a3,a1
        moveq   #32,d0
        jsr     LVO_FREEMEM(a6)
.cp_fail:
        moveq   #103,d0
        bsr     rt_setr2
        moveq   #0,d0
.cp_ret:
        movem.l (sp)+,d1-d2/a0-a1/a3/a6
        rts

; 34 endtask() : fin du process courant.
g_endtask:
        move.l  ($4).w,a6
        sub.l   a1,a1
        jsr     LVO_REMTASK(a6)
.et_hang:
        bra.s   .et_hang

; 40 readbytes(adr, n) / 43 writebytes(adr, n) : Read(input(), ...) / Write(output(), ...) sur une adresse octet.
g_readbytes:
        BENTER
        move.l  d2,d3
        move.l  d1,d2
        bsr     rt_this
        move.l  PR_CIS(a3),d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_READ(a6)
        move.l  d0,d1
        BLEAVE
g_writebytes:
        BENTER
        move.l  d2,d3
        move.l  d1,d2
        bsr     rt_this
        move.l  PR_COS(a3),d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_WRITE(a6)
        move.l  d0,d1
        BLEAVE

; 41 taskwait() -> BPTR du prochain packet reçu sur le port du process.
g_taskwait:
        BENTER
        bsr     rt_this
        move.l  ($4).w,a6
.tw_lp:
        lea     PR_MSGPORT(a3),a0
        jsr     LVO_WAITPORT(a6)
        lea     PR_MSGPORT(a3),a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .tw_lp
        move.l  d0,a0
        move.l  LN_NAME(a0),d1
        lsr.l   #2,d1
        BLEAVE

; 42 qpkt(pkt) : envoie le packet à dp_Port (message dp_Link, ln_Name := packet) ; dp_Port := port du process (la
; réponse reviendra ici). dp_Link <= 0 -> 0 (Result2 = 101) ; sinon -1.
; 49 returnpkt(pkt, res1, res2) : pose les résultats puis qpkt (retour à l'émetteur).
g_returnpkt:
        move.l  d1,d0
        lsl.l   #2,d0
        move.l  d0,a3
        move.l  d2,DP_RES1(a3)
        move.l  d3,DP_RES2(a3)
g_qpkt:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a4                ; a4 = packet
        move.l  DP_LINK(a4),d0
        ble.s   .qp_bad
        bsr     rt_this
        lea     PR_MSGPORT(a3),a3    ; a3 = port du process
        move.l  d0,a1                ; message
        move.l  a4,LN_NAME(a1)       ; message -> packet
        move.l  DP_PORT(a4),a0       ; destination
        move.l  a3,DP_PORT(a4)
        move.l  a3,MN_REPLYPORT(a1)
        move.l  ($4).w,a6
        jsr     LVO_PUTMSG(a6)
        moveq   #-1,d1
        BLEAVE
.qp_bad:
        moveq   #101,d0
        bsr     rt_setr2
        moveq   #0,d1
        BLEAVE

; 121 runcommand(seg, pile, args, len) : lance le premier hunk de seg sur une pile neuve de « pile » longs (spec §4.3),
; plus la marge CP_STKEXTRA (notre runtime prend ses tampons et packets sur la pile 68000 de la commande) :
; a0 = BADDR(args), d0 = len, 4(sp) = taille, pr_ReturnAddr -> ce long, A1 = frame appelante, A2 = GV courant, A3 =
; segment, A5/A6 = appel/retour BCPL. -> code retour (d0 de la commande) ; -1 si pile impossible. Result2 intact.
g_runcommand:
        BENTER
        move.l  d1,d5                ; seg
        move.l  d2,d6                ; pile (longs)
        move.l  d3,d7                ; args (BPTR)
        move.l  a4,d3                ; d3 = frame appelante (a1 est écrasé par AllocMem)
        move.l  ($4).w,a6
        add.l   #CP_STKEXTRA/4,d6    ; marge : notre runtime utilise la pile 68000 de la commande (tampons, packets)
        move.l  d6,d1
        bsr     rt_getvec_raw
        tst.l   d0
        beq     .rcm_fail
        bsr     rt_this              ; a3 = process
        move.l  PR_RETURNADDR(a3),-(sp)   ; restauré au retour
        move.l  d0,-(sp)             ; pile (BPTR), libérée au retour
        lsl.l   #2,d0
        move.l  d0,a0
        move.l  d6,d1
        addq.l  #1,d1
        lsl.l   #2,d1
        add.l   d1,a0                ; a0 = sommet du vecteur
        lsl.l   #2,d6                ; d6 = taille en octets
        move.l  sp,-(a0)             ; ancien SP (8(sp) à l'entrée)
        move.l  d6,-(a0)             ; taille (4(sp) à l'entrée)
        move.l  a0,PR_RETURNADDR(a3)
        move.l  d5,d0
        lsl.l   #2,d0
        move.l  d0,a3                ; a3 = segment
        lea     4(a3),a4             ; a4 = point d'entrée
        lsl.l   #2,d7                ; d7 = adresse des arguments
        move.l  d4,d0                ; d0 = longueur
        move.l  d6,d2                ; d2 = taille (non contractuel)
        move.l  a0,sp                ; bascule sur la pile neuve
        move.l  d7,a0                ; a0 = arguments
        move.l  d3,a1                ; a1 = frame appelante
        moveq   #0,d1
        lea     bcpl_call(pc),a5
        lea     bcpl_ret(pc),a6
        jsr     (a4)                 ; d0 = code retour
        addq.l  #4,sp
        move.l  (sp),sp              ; retour sur la pile de l'appelant
        move.l  d0,d5
        move.l  (sp)+,d7             ; pile
        bsr     rt_this
        move.l  (sp)+,PR_RETURNADDR(a3)
        lsl.l   #2,d7
        move.l  d7,a1
        subq.l  #4,a1
        move.l  (a1),d0
        move.l  ($4).w,a6
        jsr     LVO_FREEMEM(a6)
        move.l  d5,d1
        BLEAVE
.rcm_fail:
        moveq   #-1,d1
        BLEAVE

; bcpl_execute : LVO Execute(cmd d1 [C], in d2, out d3) -> d0 = DOSTRUE | DOSFALSE (globale 101, spec §8.2) : charge
; C:Run, sélectionne in/out, pr_Result2 := BSTR de la commande, runcommand(Run, 600 longs) ; Run crée un CLI de fond
; qui exécute la commande puis lit la suite sur « in » (Execute("", fenêtre, 0) = CLI interactif dans la fenêtre).
; L'appelant doit avoir un GV (pr_GlobVec : hérité par CreateProc). Flux et Result2 rendus au retour.
EX_FRAME        EQU 256                 ; frame BCPL de l'appelant fabriquée sur la pile (Run y fait ses premiers appels)
bcpl_execute:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  d1,a4                   ; a4 = commande C
        move.l  d2,d6                   ; d6/d7 = in/out
        move.l  d3,d7
        bsr     rt_this
        tst.l   PR_GLOBVEC(a3)
        beq     .ex_fail
        bsr     rt_devinfo              ; le CLI de fond de Run a besoin d'un segment CLI : résident « CLI » ...
        move.l  DI_RESLIST(a0),d0
.ex_res:
        lsl.l   #2,d0
        beq.s   .ex_cons
        move.l  d0,a0
        cmp.b   #3,12(a0)
        bne.s   .ex_rnx
        move.l  12(a0),d0
        and.l   #$FFDFDFDF,d0
        cmp.l   #$03434C49,d0           ; BSTR « CLI » (casse ignorée)
        beq.s   .ex_go
.ex_rnx:
        move.l  (a0),d0
        bra.s   .ex_res
.ex_cons:
        move.l  DOS_DOSBASE,a0          ; ... ou rn_ConsoleSegment (le CLI ROM de shell.s) ; sinon échec,
        move.l  DL_ROOT(a0),a0          ; comme avant le « resident CLI L:Shell-Seg » de la startup-sequence
        tst.l   RN_CONSOLESEG(a0)
        beq     .ex_fail
.ex_go:
        move.l  ($4).w,a6
        moveq   #64,d1                  ; BSTR de la commande (255 octets au plus) dans un vecteur getvec
        bsr     rt_getvec_raw
        move.l  d0,d5                   ; d5 = BPTR de la commande
        beq     .ex_fail
        lsl.l   #2,d0
        move.l  d0,a0
        lea     1(a0),a1
        moveq   #0,d0
.ex_cpy:
        move.b  (a4)+,d1
        beq.s   .ex_cpyd
        move.b  d1,(a1)+
        addq.b  #1,d0
        cmp.b   #255,d0
        bne.s   .ex_cpy
.ex_cpyd:
        move.b  d0,(a0)
        move.l  DOS_DOSBASE,a6
        move.l  #ex_runname,d1
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  d0,d4                   ; d4 = Run
        beq     .ex_free
        bsr     rt_this
        move.l  PR_SEGLIST(a3),-(sp)    ; segarray de l'appelant : pendant Run, [2, V!1, V!2] (le stub de Run fait
        lea     -16(sp),sp              ; globin de chaque entrée : la seglist d'un programme C, entrée 3 d'un process
        move.l  sp,d0                   ; de CreateProc, n'est pas un segment BCPL)
        addq.l  #3,d0
        and.w   #-4,d0                  ; aligné sur un long (BPTR)
        move.l  d0,a0
        move.l  #2,(a0)
        move.l  PR_SEGLIST(a3),d1
        lsl.l   #2,d1
        beq.s   .ex_noseg
        move.l  d1,a1
        move.l  4(a1),4(a0)
        move.l  8(a1),8(a0)
.ex_noseg:
        lsr.l   #2,d0
        move.l  d0,PR_SEGLIST(a3)
        move.l  PR_CONSOLETASK(a3),-(sp) ; console, flux et Result2 de l'appelant, rendus au retour
        move.l  PR_CIS(a3),-(sp)
        move.l  PR_COS(a3),-(sp)
        move.l  PR_RESULT2(a3),-(sp)
        move.l  d5,-(sp)                ; vecteur de la commande et Run : d4/d5 ne survivent pas à runcommand
        move.l  d4,-(sp)
        clr.l   -(sp)                   ; (sp) = sortie ouverte ici (à refermer si Run échoue)
        move.l  d6,d0                   ; entrée sur un handler : il devient la console (« * ») de l'appelant, donc
        lsl.l   #2,d0                   ; du CLI que Run crée ; sortie nulle -> « * » sur cette console (AutoDoc :
        beq.s   .ex_streams             ; sortie dans la fenêtre courante)
        move.l  d0,a0
        move.l  FH_TYPE(a0),d0
        beq.s   .ex_streams
        move.l  d0,PR_CONSOLETASK(a3)
        tst.l   d7
        bne.s   .ex_streams
        move.l  DOS_DOSBASE,a6
        move.l  #ex_star,d1
        move.l  #MODE_NEWFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,d7
        move.l  d0,(sp)
        bsr     rt_this
.ex_streams:
        move.l  d6,PR_CIS(a3)
        move.l  d7,PR_COS(a3)
        move.l  d5,PR_RESULT2(a3)
        move.l  PR_GLOBVEC(a3),a2
        lea     -EX_FRAME(sp),sp
        move.l  sp,a1                   ; frame BCPL : Run écrit au-dessus (vers le haut), la pile 68000 descend
        move.l  d4,d1                   ; runcommand(Run, 600, pas d'arguments injectés : commande dans Result2)
        move.l  #600,d2
        moveq   #0,d3
        moveq   #0,d4
        lea     .ex_back(pc),a6         ; le BLEAVE de runcommand revient par jmp (a6)
        bra     g_runcommand
.ex_back:
        lea     EX_FRAME(sp),sp
        move.l  d1,d2                   ; d2 = code retour (-1 : pile impossible)
        move.l  (sp)+,d3                ; sortie ouverte ici
        move.l  (sp)+,d4
        move.l  (sp)+,d5
        bsr     rt_this
        move.l  (sp)+,PR_RESULT2(a3)
        move.l  (sp)+,PR_COS(a3)
        move.l  (sp)+,PR_CIS(a3)
        move.l  (sp)+,PR_CONSOLETASK(a3)
        lea     16(sp),sp
        move.l  (sp)+,PR_SEGLIST(a3)
        move.l  DOS_DOSBASE,a6
        tst.l   d2
        bpl.s   .ex_owned               ; le CLI créé possède la sortie
        move.l  d3,d1
        beq.s   .ex_owned
        jsr     DOS_LVO_CLOSE(a6)
.ex_owned:
        move.l  d4,d1
        jsr     DOS_LVO_UNLOADSEG(a6)
        bsr.s   .ex_vfree
        moveq   #-1,d0
        tst.l   d2
        bpl.s   .ex_ret
        moveq   #0,d0
        bra.s   .ex_ret
.ex_free:
        bsr.s   .ex_vfree
.ex_fail:
        moveq   #0,d0
.ex_ret:
        movem.l (sp)+,d2-d7/a2-a6
        rts
.ex_vfree:                              ; libère le vecteur de la commande (en-tête getvec)
        move.l  d5,d0
        lsl.l   #2,d0
        move.l  d0,a1
        subq.l  #4,a1
        move.l  (a1),d0
        move.l  ($4).w,a6
        jmp     LVO_FREEMEM(a6)
ex_runname:
        dc.b    "C:Run",0
ex_star:
        dc.b    "*",0
        even

; 3 mult(a, b) -> a*b ; 4 div(a, b) -> a/b (troncature vers 0) ; 5 rem(a, b) -> reste (signe du dividende).
g_mult:
        bsr     bcpl_mul
        jmp     (a6)
g_div:
        bsr     bcpl_divmod
        jmp     (a6)
g_rem:
        bsr     bcpl_divmod
        move.l  d2,d1
        jmp     (a6)

; -20 clearvec(v, n) : met à 0 les n+1 longs de BADDR(v).
g_clearvec:
        lsl.l   #2,d1
        move.l  d1,a3
.clv_lp:
        clr.l   (a3)+
        subq.l  #1,d2
        bpl.s   .clv_lp
        jmp     (a6)

; -1 Open(nom C, mode) / -3 Read(fh, tampon, n) / -6 Write(fh, tampon, n) / -8 Seek(fh, pos, mode) : adaptateurs ABI C
; (les arguments d1-d3 sont déjà ceux des LVO dos).
g_copen:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_OPEN(a6)
        move.l  d0,d1
        BLEAVE
g_cread:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_READ(a6)
        move.l  d0,d1
        BLEAVE
g_cwrite:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_WRITE(a6)
        move.l  d0,d1
        BLEAVE
g_cseek:
        BENTER
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_SEEK(a6)
        move.l  d0,d1
        BLEAVE

; 37 testflags(m) : teste ET efface les bits CTRL de m (bit0 = CTRL-C ... bit3 = CTRL-F) -> -1 si l'un était posé.
g_testflags:
        BENTER
        moveq   #12,d0
        lsl.l   d0,d1                ; SIGBREAKB_CTRL_C = 12
        move.l  d1,d2
        moveq   #0,d0
        move.l  ($4).w,a6
        jsr     LVO_SETSIGNAL(a6)    ; d0 = nouveaux (0), d1 = masque -> efface et renvoie l'ancien état
        and.l   d2,d0
        sne     d1
        ext.w   d1
        ext.l   d1
        BLEAVE

; 36 setflags(taskid, m) : Signal des bits CTRL de m (bit0 = CTRL-C ... bit3 = CTRL-F) au process dont taskid est le
; MsgPort (sa tâche = mp_SigTask). taskid 0 : rien.
g_setflags:
        BENTER
        tst.l   d1
        beq.s   .sf_ret
        move.l  d1,a0
        move.l  MP_SIGTASK(a0),a1
        moveq   #12,d0
        lsl.l   d0,d2
        move.l  d2,d0
        move.l  ($4).w,a6
        jsr     LVO_SIGNAL(a6)
.sf_ret:
        BLEAVE

; 6 setio(iob, cmd, data, len, offset) : iob BPTR d'une IOStdReq ; io_Command (mot) := cmd, io_Data := BADDR(data),
; io_Length := len, io_Offset := offset (5e argument).
g_setio:
        lsl.l   #2,d1
        move.l  d1,a3
        move.w  d2,IO_COMMAND(a3)
        lsl.l   #2,d3
        move.l  d3,IOSTD_DATA(a3)
        move.l  d4,IOSTD_LENGTH(a3)
        move.l  16(a1),IOSTD_OFFSET(a3)
        jmp     (a6)

; 21 doio(iob) -> io_Error (DoIO) ; 22 sendio(iob, pkt) : lie la requête au packet (ln_Name = packet, dp_Link =
; requête : taskwait rendra ce packet à la réponse) puis SendIO ; 32 closedevice(iob).
g_doio:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a1
        move.l  ($4).w,a6
        jsr     LVO_DOIO(a6)
        move.l  d0,d1
        BLEAVE
g_sendio:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a1
        lsl.l   #2,d2
        move.l  d2,LN_NAME(a1)
        move.l  d2,a0
        move.l  a1,DP_LINK(a0)
        move.l  ($4).w,a6
        jsr     LVO_SENDIO(a6)
        BLEAVE
g_closedevice:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a1
        move.l  ($4).w,a6
        jsr     LVO_CLOSEDEVICE(a6)
        BLEAVE

; 31 opendevice(iob, nom, unité, flags) : nom BSTR suivi d'un NUL ; ln_Name := nom, port de réponse := MsgPort du
; process, mn_Length := 12 (valeurs V34) -> -1 succès | 0.
g_opendevice:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a1
        lsl.l   #2,d2
        addq.l  #1,d2
        move.l  d2,a0                ; nom C
        move.l  a0,LN_NAME(a1)
        bsr     rt_this
        lea     PR_MSGPORT(a3),a3
        move.l  a3,MN_REPLYPORT(a1)
        move.w  #12,MN_LENGTH(a1)
        move.l  d3,d0
        move.l  d4,d1
        move.l  ($4).w,a6
        jsr     LVO_OPENDEVICE(a6)
        tst.l   d0
        seq     d1
        ext.w   d1
        ext.l   d1
        BLEAVE

; 50 openwindow(x, y, l, h, titre) -> APTR Window | 0 : OpenWindow (IntuitionBase = GV[92]) avec une NewWindow sur la
; pile (spec handlers §complément) : pinceaux $FF/$FF, IDCMP 0, Flags $00021007, titre = BADDR(titre) (chaîne C),
; Min 120x50, Max $FFFFx$FFFF, Type WBENCHSCREEN.
OW_NWSIZE       EQU 48
g_openwindow:
        BENTER
        lea     -OW_NWSIZE(sp),sp
        move.l  sp,a0
        move.w  d1,(a0)+             ; LeftEdge
        move.w  d2,(a0)+             ; TopEdge
        move.w  d3,(a0)+             ; Width
        move.w  d4,(a0)+             ; Height
        move.w  #$FFFF,(a0)+         ; DetailPen, BlockPen
        clr.l   (a0)+                ; IDCMPFlags
        move.l  #$00021007,(a0)+     ; Flags
        clr.l   (a0)+                ; FirstGadget
        clr.l   (a0)+                ; CheckMark
        move.l  16(a4),d0
        lsl.l   #2,d0
        move.l  d0,(a0)+             ; Title
        clr.l   (a0)+                ; Screen
        clr.l   (a0)+                ; BitMap
        move.l  #(120<<16)|50,(a0)+  ; MinWidth, MinHeight
        move.l  #$FFFFFFFF,(a0)+     ; MaxWidth, MaxHeight
        move.w  #1,(a0)              ; Type = WBENCHSCREEN
        move.l  sp,a0
        move.l  92*4(a2),a6          ; IntuitionBase
        jsr     LVO_OPENWINDOW(a6)
        move.l  d0,d1
        lea     OW_NWSIZE(sp),sp
        BLEAVE

; 86 datstamp(v) : DateStamp dans v!0..v!2 (jours, minutes, ticks) -> v.
g_datstamp:
        BENTER
        move.l  d1,d5
        lsl.l   #2,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_DATESTAMP(a6)
        move.l  d5,d1
        BLEAVE

; 128 setdatstamp(v) : règle l'heure système sur le vecteur [jours, minutes, ticks] (BPTR) ; résultat non
; significatif. 126 compstamp(a, b) : 0 si égaux, +1 si a est plus récent que b, -1 sinon (jours, minutes, ticks).
g_setdatstamp:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a0
        jsr     dos_setnow
        moveq   #0,d1
        BLEAVE
g_compstamp:
        BENTER
        lsl.l   #2,d1
        move.l  d1,a0
        lsl.l   #2,d2
        move.l  d2,a1
        moveq   #2,d3
.cs_lp:
        move.l  (a0)+,d0
        cmp.l   (a1)+,d0
        bgt.s   .cs_newer
        blt.s   .cs_older
        dbra    d3,.cs_lp
        moveq   #0,d1
        BLEAVE
.cs_newer:
        moveq   #1,d1
        BLEAVE
.cs_older:
        moveq   #-1,d1
        BLEAVE

g_rootstruct:
        move.l  DOS_DOSBASE,a3
        move.l  DL_ROOT(a3),d1
        lsr.l   #2,d1
        jmp     (a6)

; 48 sendpkt(_, port, type, res1, res2, arg1...) : la FRAME D'ARGUMENTS est le DosPacket (Link, Port, Type, Res1,
; Res2, Arg1...). Envoi synchrone au port, réponse sur le port du process ; -> dp_Res1 ; Result2 := dp_Res2.
g_sendpkt:
        BENTER
        move.l  DP_PORT(a4),-(sp)    ; destination, gardée pour un renvoi
        lea     -MN_SIZE(sp),sp      ; Message exec sur la pile 68000
        move.l  sp,a0
        moveq   #(MN_SIZE/2)-1,d0
.sp_clr:
        clr.w   (a0)+
        dbra    d0,.sp_clr
        move.l  sp,a0
        move.b  #NT_MESSAGE,LN_TYPE(a0)
        move.l  a4,LN_NAME(a0)       ; msg -> packet (= la frame)
        bsr     rt_this
        lea     PR_MSGPORT(a3),a3    ; port de réponse
        move.l  a3,MN_REPLYPORT(a0)
        move.l  a0,DP_LINK(a4)
        move.l  ($4).w,a6
.sk_send:
        move.l  a3,DP_PORT(a4)       ; le handler répond au port du process
        move.l  sp,a1                ; a1 = message
        move.l  MN_SIZE(sp),a0       ; a0 = destination (argument 2)
        jsr     LVO_PUTMSG(a6)       ; PutMsg(port a0, message a1)
.sk_wait:
        move.l  a3,a0
        jsr     LVO_WAITPORT(a6)
        move.l  a3,a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq     .sk_wait
        move.l  DP_RES1(a4),d0
        move.l  DP_RES2(a4),d1
        jsr     dos_pktretry         ; volume éjecté : « Please replace volume », Retry -> renvoi
        tst.l   d0
        beq.s   .sk_done
        clr.l   DP_RES1(a4)
        clr.l   DP_RES2(a4)
        bra.s   .sk_send
.sk_done:
        move.l  DP_RES2(a4),d0
        bsr     rt_setr2
        move.l  DP_RES1(a4),d1
        lea     MN_SIZE+4(sp),sp
        BLEAVE

; 51 currentdir(set, lock) : set = 0 -> renvoie pr_CurrentDir ; sinon renvoie l'ancien et écrit lock.
g_currentdir:
        bsr     rt_this
        move.l  PR_CURRENTDIR(a3),d0
        tst.l   d1
        beq     .cd_get
        move.l  d2,PR_CURRENTDIR(a3)
.cd_get:
        move.l  d0,d1
        jmp     (a6)

; 54 rdch() / 55 unrdch() / 56 wrch(c)
g_rdch:
        BENTER
        bsr     rt_rdch
        move.l  d0,d1
        BLEAVE
g_unrdch:
        BENTER
        bsr     rt_unrdch
        move.l  d0,d1
        BLEAVE
g_wrch:
        BENTER
        move.b  d1,-(sp)
        move.l  sp,a0
        moveq   #1,d0
        bsr     rt_write
        addq.l  #2,sp                ; (move.b -(sp) décrémente de 2 : SP reste pair)
        BLEAVE

; 61 selectinput(fh) / 62 selectoutput(fh) / 65 input() / 66 output()
g_selectinput:
        bsr     rt_this
        move.l  d1,PR_CIS(a3)
        jmp     (a6)
g_selectoutput:
        bsr     rt_this
        move.l  d1,PR_COS(a3)
        jmp     (a6)
g_input:
        bsr     rt_this
        move.l  PR_CIS(a3),d1
        jmp     (a6)
g_output:
        bsr     rt_this
        move.l  PR_COS(a3),d1
        jmp     (a6)

; --- sortie formatée : chaque globale ouvre un tampon WF_BUFSZ sur la pile (a5 = début, a3 = position) ---
WFOPEN          MACRO
        lea     -WF_BUFSZ(sp),sp
        move.l  sp,a5
        move.l  sp,a3
                ENDM
WFCLOSE         MACRO
        bsr     wf_flush
        lea     WF_BUFSZ(sp),sp
                ENDM

; 53 writet(s, w) : BSTR puis espaces jusqu'à w colonnes.
g_writet:
        BENTER
        WFOPEN
        move.l  d2,d3
        bsr     wf_bstr
        move.l  d3,d0
        sub.l   d2,d0
        bsr     wf_spaces
        WFCLOSE
        BLEAVE

; 68 newline()
g_newline:
        BENTER
        WFOPEN
        moveq   #10,d0
        bsr     wf_putc
        WFCLOSE
        BLEAVE

; 69 writed(n, w) / 70 writen(n) / 71 writehex(n, d) / 72 writeoct(n, d)
g_writed:
        BENTER
        moveq   #10,d3
        moveq   #0,d4
        bra     g_numout
g_writen:
        BENTER
        moveq   #0,d2
        moveq   #10,d3
        moveq   #0,d4
        bra     g_numout
g_writehex:
        BENTER
        moveq   #16,d3
        moveq   #2,d4
        bra     g_numout
g_writeoct:
        BENTER
        moveq   #8,d3
        moveq   #2,d4
g_numout:
        WFOPEN
        bsr     wf_num
        WFCLOSE
        BLEAVE

; 73 writes(s) : écrit le BSTR s.
g_writes:
        BENTER
        WFOPEN
        bsr     wf_bstr
        WFCLOSE
        BLEAVE

; 74 writef(fmt, a1, a2, ...) : fmt BSTR ; arguments = longs suivants de la frame. Codes (insensibles à la casse) :
; %S BSTR, %T BSTR sur largeur w, %C caractère, %N décimal, %I décimal largeur w, %U non signé largeur w, %X hexa w
; chiffres, %O octal w chiffres, %$ saute un argument ; autre lettre : écrite telle quelle (%% -> %). Largeur =
; caractère suivant : 0-9, ou lettre (A = 10...).
g_writef:
        BENTER
        WFOPEN
        lea     4(a4),a2             ; a2 = argument suivant (a2 restauré par BLEAVE)
        move.l  d1,d0
        lsl.l   #2,d0
        beq     .wf_end
        move.l  d0,a0                ; a0 = format (BSTR)
        moveq   #0,d5
        move.b  (a0)+,d5             ; d5 = caractères restants
.wf_lp:
        subq.l  #1,d5
        bmi     .wf_end
        move.b  (a0)+,d0
        cmp.b   #'%',d0
        beq     .wf_pct
        bsr     wf_putc
        bra     .wf_lp
.wf_pct:
        subq.l  #1,d5
        bmi     .wf_end
        move.b  (a0)+,d0
        bsr     rt_upper
        cmp.b   #'S',d0
        beq     .wf_s
        cmp.b   #'T',d0
        beq     .wf_t
        cmp.b   #'C',d0
        beq     .wf_c
        cmp.b   #'N',d0
        beq     .wf_n
        cmp.b   #'I',d0
        beq     .wf_i
        cmp.b   #'U',d0
        beq     .wf_u
        cmp.b   #'X',d0
        beq     .wf_x
        cmp.b   #'O',d0
        beq     .wf_o
        cmp.b   #'$',d0
        beq     .wf_skip
        bsr     wf_putc              ; lettre inconnue (dont %) : écrite telle quelle
        bra     .wf_lp
.wf_s:
        move.l  (a2)+,d1
        bsr     wf_bstr
        bra     .wf_lp
.wf_t:
        bsr     .wf_width
        move.l  (a2)+,d1
        move.l  d2,d3
        bsr     wf_bstr
        move.l  d3,d0
        sub.l   d2,d0
        bsr     wf_spaces
        bra     .wf_lp
.wf_c:
        move.l  (a2)+,d0
        bsr     wf_putc
        bra     .wf_lp
.wf_n:
        moveq   #0,d2
        moveq   #10,d3
        moveq   #0,d4
        bra     .wf_num
.wf_i:
        bsr     .wf_width
        moveq   #10,d3
        moveq   #0,d4
        bra     .wf_num
.wf_u:
        bsr     .wf_width
        moveq   #10,d3
        moveq   #1,d4
        bra     .wf_num
.wf_x:
        bsr     .wf_width
        moveq   #16,d3
        moveq   #2,d4
        bra     .wf_num
.wf_o:
        bsr     .wf_width
        moveq   #8,d3
        moveq   #2,d4
.wf_num:
        move.l  (a2)+,d1
        bsr     wf_num
        bra     .wf_lp
.wf_skip:
        addq.l  #4,a2
        bra     .wf_lp
.wf_width:                           ; d2 = largeur lue au caractère suivant (0-9, lettre -> 10+)
        moveq   #0,d2
        subq.l  #1,d5
        bmi     .ww_ret
        move.b  (a0)+,d0
        bsr     rt_upper
        cmp.b   #'9',d0
        bhi     .ww_let
        sub.b   #'0',d0
        bra     .ww_set
.ww_let:
        sub.b   #'A'-10,d0
.ww_set:
        and.l   #$FF,d0
        move.l  d0,d2
.ww_ret:
        rts
.wf_end:
        WFCLOSE
        BLEAVE

; 75 capitalch(c) / 76 compch(a, b) / 77 compstring(s1, s2) (0 = égales, insensible à la casse)
g_capitalch:
        move.l  d1,d0
        bsr     rt_upper
        and.l   #$FF,d0
        move.l  d0,d1
        jmp     (a6)
g_compch:
        move.l  d1,d0
        bsr     rt_upper
        and.l   #$FF,d0
        move.l  d0,d1
        move.l  d2,d0
        bsr     rt_upper
        and.l   #$FF,d0
        sub.l   d0,d1
        jmp     (a6)
g_compstring:
        BENTER
        bsr     rt_compbstr
        move.l  d0,d1
        BLEAVE

; rt_compbstr(d1, d2 = BSTR) -> d0 = 0 si égales (insensible à la casse), sinon différence du premier écart (ou des
; longueurs). Clobbe d1-d4/a0/a1.
rt_compbstr:
        lsl.l   #2,d1
        lsl.l   #2,d2
        move.l  d1,a0
        move.l  d2,a1
        moveq   #0,d3
        moveq   #0,d4
        move.b  (a0)+,d3
        move.b  (a1)+,d4
.cb_lp:
        tst.l   d3
        beq     .cb_len
        tst.l   d4
        beq     .cb_len
        move.b  (a0)+,d0
        bsr     rt_upper
        move.b  d0,d1
        move.b  (a1)+,d0
        bsr     rt_upper
        and.l   #$FF,d0
        and.l   #$FF,d1
        sub.l   d0,d1
        bne     .cb_diff
        subq.l  #1,d3
        subq.l  #1,d4
        bra     .cb_lp
.cb_len:
        move.l  d3,d0
        sub.l   d4,d0
        rts
.cb_diff:
        move.l  d1,d0
        rts

; 79 rditem(v, n) -> 1 item, 2 item quoté, 0 fin de ligne, -2 « = » seul, -1 erreur. Item rangé en BSTR dans le
; vecteur v (n+1 longs, effacé au début). Spec §5.3.
g_rditem:
        BENTER
        bsr     rt_rditem
        move.l  d0,d1
        BLEAVE

; rt_rditem(d1 = BPTR v, d2 = n) -> d0 = résultat (cf. g_rditem). Préserve tout sauf d0.
rt_rditem:
        movem.l d1-d4/a0-a1,-(sp)
        lsl.l   #2,d1
        move.l  d1,a0                ; a0 = vecteur (BSTR)
        move.l  d2,d3
        addq.l  #1,d3
        move.l  d3,d4
        lsl.l   #2,d4
        subq.l  #1,d4                ; d4 = capacité en caractères
        move.l  a0,a1
.ri_clr:
        clr.l   (a1)+
        subq.l  #1,d3
        bgt     .ri_clr
        moveq   #0,d3                ; d3 = longueur
.ri_skip:
        bsr     rt_rdch
        cmp.b   #' ',d0
        beq     .ri_skip
        cmp.b   #9,d0
        beq     .ri_skip
        cmp.l   #'"',d0
        beq     .ri_quoted
        cmp.l   #10,d0
        beq     .ri_end0
        cmp.l   #';',d0
        beq     .ri_end0
        tst.l   d0
        bmi     .ri_end0
        cmp.l   #'=',d0
        bne     .ri_plain
        moveq   #-2,d0
        bra     .ri_ret
.ri_end0:
        bsr     rt_unrdch
        moveq   #0,d0
        bra     .ri_ret
.ri_plain:
        bsr     .ri_store
        bmi     .ri_err
        bsr     rt_rdch
        cmp.l   #10,d0
        beq     .ri_plainend
        cmp.l   #';',d0
        beq     .ri_plainend
        cmp.l   #' ',d0
        beq     .ri_plainend
        cmp.l   #9,d0
        beq     .ri_plainend
        cmp.l   #'=',d0
        beq     .ri_plainend
        tst.l   d0
        bpl     .ri_plain
.ri_plainend:
        bsr     rt_unrdch
        moveq   #1,d0
        bra     .ri_ret
.ri_quoted:
        bsr     rt_rdch
        cmp.l   #'"',d0
        beq     .ri_qend
        cmp.l   #10,d0
        beq     .ri_err
        tst.l   d0
        bmi     .ri_err
        cmp.l   #'*',d0
        bne     .ri_qstore
        bsr     rt_rdch              ; *N -> LF, *E -> ESC, *x -> x
        cmp.l   #10,d0
        beq     .ri_err
        tst.l   d0
        bmi     .ri_err
        move.l  d0,d1
        bsr     rt_upper
        cmp.b   #'N',d0
        bne     .ri_qe
        moveq   #10,d0
        bra     .ri_qstore
.ri_qe:
        cmp.b   #'E',d0
        bne     .ri_qx
        moveq   #27,d0
        bra     .ri_qstore
.ri_qx:
        move.l  d1,d0
.ri_qstore:
        bsr     .ri_store
        bmi     .ri_err
        bra     .ri_quoted
.ri_qend:
        moveq   #2,d0
        bra     .ri_ret
.ri_err:
        moveq   #-1,d0
.ri_ret:
        movem.l (sp)+,d1-d4/a0-a1
        rts
.ri_store:                           ; d0.b -> item ; N = 1 (et Z) si la capacité est dépassée
        cmp.l   d4,d3
        bhs     .rs_full
        addq.l  #1,d3
        move.b  d0,0(a0,d3.l)
        move.b  d3,(a0)
        moveq   #0,d0                ; N = 0
        rts
.rs_full:
        moveq   #-1,d0               ; N = 1
        rts

; 80 findarg(tpl, item) -> index de la clé dont un alias égale item (insensible à la casse) | -1.
g_findarg:
        BENTER
        bsr     rt_findarg
        move.l  d0,d1
        BLEAVE

; rt_findarg(d1 = BSTR template, d2 = BSTR item) -> d0 = index | -1. Préserve d1-d7/a0-a6 sauf d0.
rt_findarg:
        movem.l d1-d6/a0-a1,-(sp)
        lsl.l   #2,d1
        lsl.l   #2,d2
        move.l  d1,a0                ; a0 = template
        moveq   #0,d5
        move.b  (a0)+,d5             ; d5 = caractères restants du template
        moveq   #0,d6                ; d6 = index de clé courant
.fa_alias:                           ; compare l'alias courant (jusqu'à = / , fin) à l'item
        move.l  d2,a1
        moveq   #0,d4
        move.b  (a1)+,d4             ; d4 = longueur de l'item
        moveq   #1,d3                ; d3 = 1 tant que l'alias correspond
.fa_ch:
        tst.l   d5
        beq     .fa_aend
        move.b  (a0),d0
        cmp.b   #'=',d0
        beq     .fa_aend
        cmp.b   #'/',d0
        beq     .fa_aend
        cmp.b   #',',d0
        beq     .fa_aend
        addq.l  #1,a0
        subq.l  #1,d5
        tst.l   d4
        beq     .fa_miss
        bsr     rt_upper
        move.b  d0,d1
        move.b  (a1)+,d0
        subq.l  #1,d4
        bsr     rt_upper
        cmp.b   d0,d1
        beq     .fa_ch
.fa_miss:
        moveq   #0,d3
        bra     .fa_ch
.fa_aend:
        tst.l   d3
        beq     .fa_next
        tst.l   d4
        bne     .fa_next             ; item plus long que l'alias
        move.l  d6,d0
        bra     .fa_found
.fa_next:
        tst.l   d5
        beq     .fa_none
        move.b  (a0)+,d0
        subq.l  #1,d5
        cmp.b   #'=',d0
        beq     .fa_alias            ; alias suivant de la même clé
        cmp.b   #',',d0
        bne     .fa_next             ; qualificatifs (/A /K /S) : avance jusqu'à , ou =
        addq.l  #1,d6                ; clé suivante
        bra     .fa_alias
.fa_none:
        moveq   #-1,d0
.fa_found:
        movem.l (sp)+,d1-d6/a0-a1
        rts

; rt_tplflags(d1 = BSTR template, d2 = index de clé) -> d0 = drapeaux (bit0 /A, bit1 /K, bit2 /S) ; d0 = -1 si la
; clé n'existe pas. Préserve le reste.
rt_tplflags:
        movem.l d1-d5/a0,-(sp)
        lsl.l   #2,d1
        move.l  d1,a0
        moveq   #0,d5
        move.b  (a0)+,d5
        moveq   #0,d3                ; index courant
        moveq   #0,d4                ; drapeaux de la clé courante
.tf_lp:
        tst.l   d5
        beq     .tf_end
        move.b  (a0)+,d0
        subq.l  #1,d5
        cmp.b   #',',d0
        bne     .tf_slash
        cmp.l   d2,d3
        beq     .tf_hit
        addq.l  #1,d3
        moveq   #0,d4
        bra     .tf_lp
.tf_slash:
        cmp.b   #'/',d0
        bne     .tf_lp
        tst.l   d5
        beq     .tf_end
        move.b  (a0)+,d0
        subq.l  #1,d5
        bsr     rt_upper
        cmp.b   #'A',d0
        bne     .tf_k
        bset    #0,d4
.tf_k:
        cmp.b   #'K',d0
        bne     .tf_s
        bset    #1,d4
.tf_s:
        cmp.b   #'S',d0
        bne     .tf_lp
        bset    #2,d4
        bra     .tf_lp
.tf_end:
        cmp.l   d2,d3
        beq     .tf_hit
        moveq   #-1,d0
        bra     .tf_ret
.tf_hit:
        move.l  d4,d0
.tf_ret:
        movem.l (sp)+,d1-d5/a0
        rts

; rt_tplcount(d1 = BSTR template) -> d0 = nombre de clés (0 pour un template vide).
rt_tplcount:
        movem.l d1/d5/a0,-(sp)
        moveq   #0,d0
        lsl.l   #2,d1
        move.l  d1,a0
        moveq   #0,d5
        move.b  (a0)+,d5
        beq     .tc_ret
        moveq   #1,d0
.tc_lp:
        cmp.b   #',',(a0)+
        bne     .tc_next
        addq.l  #1,d0
.tc_next:
        subq.l  #1,d5
        bne     .tc_lp
.tc_ret:
        movem.l (sp)+,d1/d5/a0
        rts

; 78 rdargs(tpl, argv, n) -> BPTR du premier long libre d'argv (succès) | 0 (Result2 = 120). Spec §5.4 :
; argv!i = 0 absent, -1 switch /S présent, sinon BPTR d'un BSTR rangé dans la zone libre d'argv (après les clés).
; Pendant l'analyse, argv!i (0..7) = drapeaux de la clé = « non remplie ».
g_rdargs:
        BENTER
        move.l  d1,d5                ; d5 = template
        move.l  d2,d6
        lsl.l   #2,d6
        move.l  d6,a3                ; a3 = argv (adresse)
        move.l  d3,d7                ; d7 = taille d'argv en longs
        bsr     rt_tplcount
        move.l  d0,d4                ; d4 = nombre de clés
        cmp.l   d7,d4
        bgt     .ra_err
        moveq   #0,d2
.ra_init:
        cmp.l   d4,d2
        bhs     .ra_initd
        move.l  d5,d1
        bsr     rt_tplflags
        move.l  d2,d1
        lsl.l   #2,d1
        move.l  d0,0(a3,d1.l)
        addq.l  #1,d2
        bra     .ra_init
.ra_initd:
        move.l  d4,d0
        lsl.l   #2,d0
        lea     0(a3,d0.l),a2        ; a2 = zone libre (a2 restauré par BLEAVE)
        sub.l   d4,d7                ; d7 = longs libres
.ra_item:
        subq.l  #1,d7
        bmi     .ra_err
        addq.l  #1,d7
        move.l  a2,d1
        lsr.l   #2,d1
        move.l  d7,d2
        subq.l  #1,d2
        bsr     rt_rditem
        tst.l   d0
        beq     .ra_done
        cmp.l   #-2,d0
        beq     .ra_item             ; « = » isolé : ignoré
        tst.l   d0
        bmi     .ra_err
        cmp.l   #2,d0
        beq     .ra_positional       ; item quoté : jamais un mot-clé
        cmp.w   #$013F,(a2)          ; « ? » suivi de LF : affiche le template et relit une ligne
        bne     .ra_kw
        bsr     rt_rdch
        cmp.l   #10,d0
        beq     .ra_help
        bsr     rt_unrdch
.ra_kw:
        move.l  d5,d1
        move.l  a2,d2
        lsr.l   #2,d2
        bsr     rt_findarg
        tst.l   d0
        bmi     .ra_positional
        move.l  d0,d3                ; d3 = clé
        lsl.l   #2,d3
        move.l  0(a3,d3.l),d0
        btst    #2,d0
        beq     .ra_keyval
        cmp.l   #7,d0
        bhi     .ra_keyval
        moveq   #-1,d0               ; switch /S
        move.l  d0,0(a3,d3.l)
        bra     .ra_item
.ra_keyval:                          ; mot-clé : la valeur est l'item suivant (éventuellement après « = »)
        move.l  a2,d1
        lsr.l   #2,d1
        move.l  d7,d2
        subq.l  #1,d2
        bsr     rt_rditem
        cmp.l   #-2,d0
        bne     .ra_kv2
        bsr     rt_rditem
.ra_kv2:
        tst.l   d0
        ble     .ra_err
        bsr     .ra_take             ; d0 = BPTR de l'item, zone libre avancée
        move.l  d0,0(a3,d3.l)
        bra     .ra_item
.ra_positional:                      ; première clé non remplie qui n'est ni /K ni /S
        moveq   #0,d3
.ra_pfind:
        cmp.l   d4,d3
        bhs     .ra_err
        move.l  d3,d1
        lsl.l   #2,d1
        move.l  0(a3,d1.l),d0
        cmp.l   #7,d0
        bhi     .ra_pnext
        and.l   #6,d0
        bne     .ra_pnext
        bsr     .ra_take
        move.l  d0,0(a3,d1.l)
        bra     .ra_item
.ra_pnext:
        addq.l  #1,d3
        bra     .ra_pfind
.ra_help:
        lea     -256(sp),sp          ; « <template>: »
        move.l  sp,a0
        move.l  d5,d1
        bsr     rt_cstr
        move.l  sp,a0
        moveq   #-1,d0
.ra_hlen:
        addq.l  #1,d0
        tst.b   (a0)+
        bne     .ra_hlen
        move.l  sp,a0
        bsr     rt_write
        lea     ra_colon(pc),a0
        moveq   #2,d0
        bsr     rt_write
        lea     256(sp),sp
        bra     .ra_item
.ra_take:                            ; -> d0 = BPTR de l'item en a2 ; avance a2/d7 de sa taille. Clobbe d2.
        move.l  a2,d0
        lsr.l   #2,d0
        moveq   #0,d2
        move.b  (a2),d2
        addq.l  #4,d2
        lsr.l   #2,d2                ; longs occupés = (longueur + 1 + 3) / 4
        sub.l   d2,d7
        lsl.l   #2,d2
        add.l   d2,a2
        rts
.ra_done:
        moveq   #0,d3                ; clés non remplies : /A -> erreur, sinon 0 (absente)
.ra_chk:
        cmp.l   d4,d3
        bhs     .ra_ok
        move.l  d3,d1
        lsl.l   #2,d1
        move.l  0(a3,d1.l),d0
        cmp.l   #7,d0
        bhi     .ra_cnext
        btst    #0,d0
        bne     .ra_err
        clr.l   0(a3,d1.l)
.ra_cnext:
        addq.l  #1,d3
        bra     .ra_chk
.ra_ok:
        bsr     rt_rdch              ; consomme le terminateur (LF ou ;)
        move.l  a2,d1
        lsr.l   #2,d1
        BLEAVE
.ra_err:
.ra_eskip:                           ; saute le reste de la ligne
        bsr     rt_rdch
        cmp.l   #10,d0
        beq     .ra_efin
        cmp.l   #';',d0
        beq     .ra_efin
        tst.l   d0
        bpl     .ra_eskip
.ra_efin:
        moveq   #ERR_BADTEMPLATE,d0
        bsr     rt_setr2
        moveq   #0,d1
        BLEAVE

; 13 makeglobvec(segarray) -> BPTR du slot 0 d'un GV neuf | 0 (Result2 = 103).
g_makeglobvec:
        BENTER
        move.l  ($4).w,a6
        bsr     rt_makeglobvec
        move.l  d0,d1
        BLEAVE

; 112 starthandler(nœud, nom) : nœud = BPTR du DeviceNode, nom = BSTR complet -> MsgPort | 0 ; Result2 = dn_Lock.
g_starthandler:
        BENTER
        lea     -256(sp),sp
        move.l  d1,d5                ; nœud
        move.l  d2,d1
        move.l  sp,a0
        bsr     rt_cstr
        lsl.l   #2,d5
        move.l  d5,a2
        bsr     bcpl_starthandler
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE

; 89 findsegarray() -> pr_SegList (BPTR du segarray)
g_findsegarray:
        bsr     rt_this
        move.l  PR_SEGLIST(a3),d1
        jmp     (a6)

; 102 deviceproc(nom) -> MsgPort du handler | 0 (Result2 = 218) ; Result2 = lock associé (assign) sinon 0.
g_deviceproc:
        BENTER
        lea     -256(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,a4                ; a4 = nom C (dos_resolve)
        move.l  DOS_DOSBASE,a6
        bsr     rt_this
        move.l  a3,a5                ; a5 = process (survit à dos_resolve)
        jsr     dos_resolve          ; a3 = port | 0, d6 = lock
        move.l  a3,d1
        beq     .dp_ret              ; dos_resolve a posé Result2 = 218
        move.l  d6,PR_RESULT2(a5)
.dp_ret:
        lea     256(sp),sp
        BLEAVE

; 104 fault(code) (spec fault-v34 §2) : code != 0 -> le texte de l'erreur est écrit par C:FAULT (rt_fault).
g_fault:
        BENTER
        move.l  d1,d0
        bsr     rt_fault
        BLEAVE

; rt_fault(d0 = code) : rien pour 0. Sinon C:FAULT est chargé sans requester (pr_WindowPtr = -1 le temps du
; chargement, pas de liste Resident), pr_Result2 := code APRÈS le chargement (C:Fault y lit le code et n'écrit alors que
; le texte et un saut de ligne), lancé par runcommand sur 400 longs sans arguments (sorties de l'appelant), puis
; déchargé. Introuvable, ou runcommand rend -1 : « Error code <n> » et saut de ligne. pr_Result2 = code au retour.
; Préserve tout.
FT_STACK        EQU 400
rt_fault:
        movem.l d0-d7/a0-a6,-(sp)
        move.l  d0,d7                ; d7 = code
        beq     .rf_ret
        bsr     rt_this
        move.l  PR_WINDOWPTR(a3),d6
        moveq   #-1,d0
        move.l  d0,PR_WINDOWPTR(a3)
        move.l  #ft_cfault,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOADSEG(a6)
        move.l  d0,d5                ; d5 = seglist | 0
        bsr     rt_this
        move.l  d6,PR_WINDOWPTR(a3)
        move.l  d7,PR_RESULT2(a3)
        tst.l   d5
        beq.s   .rf_fallback
        move.l  PR_GLOBVEC(a3),d0
        beq.s   .rf_unload           ; sans vecteur global : pas de commande BCPL possible
        move.l  d0,a2
        movem.l d5/d7,-(sp)          ; runcommand se sert de d5-d7
        lea     -EX_FRAME(sp),sp
        move.l  sp,a1                ; frame BCPL de l'appelant fabriquée sur la pile
        move.l  d5,d1
        move.l  #FT_STACK,d2
        moveq   #0,d3
        moveq   #0,d4
        lea     .rf_back(pc),a6      ; le BLEAVE de runcommand revient par jmp (a6)
        bra     g_runcommand
.rf_back:
        lea     EX_FRAME(sp),sp
        move.l  d1,d6                ; d6 = code retour (-1 : pas lancée)
        movem.l (sp)+,d5/d7
        move.l  d5,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
        cmp.l   #-1,d6
        bne.s   .rf_ret
        bra.s   .rf_fallback
.rf_unload:
        move.l  d5,d1
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOADSEG(a6)
.rf_fallback:
        WFOPEN
        lea     ft_msg(pc),a0
.rf_lp:
        move.b  (a0)+,d0
        beq     .rf_num
        bsr     wf_putc
        bra     .rf_lp
.rf_num:
        move.l  d7,d1
        moveq   #0,d2
        moveq   #10,d3
        moveq   #0,d4
        bsr     wf_num
        moveq   #10,d0
        bsr     wf_putc
        WFCLOSE
        bsr     rt_this
        move.l  d7,PR_RESULT2(a3)
.rf_ret:
        movem.l (sp)+,d0-d7/a0-a6
        rts

; 108 locateobj(nom) / 123 lock(nom, mode) -> lock partagé | 0 ; 109 freeobj(lock).
g_locateobj:
g_lock:
        BENTER
        lea     -256(sp),sp
        move.l  sp,a0
        bsr     rt_cstr
        move.l  sp,d1
        moveq   #SHARED_LOCK,d2
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_LOCK(a6)
        move.l  d0,d1
        lea     256(sp),sp
        BLEAVE
g_freeobj:
        BENTER
        bsr     rt_this
        move.l  PR_RESULT2(a3),d7    ; Result2 préservé
        move.l  DOS_DOSBASE,a6
        jsr     DOS_LVO_UNLOCK(a6)
        move.l  d7,d0
        bsr     rt_setr2
        BLEAVE

; 110 getlong(i, base) / 111 putlong(i, base, v) : long d'INDEX i (en longs) à partir de l'adresse machine base,
; soit base + 4*i. Observé dans c:Run : getlong(11, taskid) = pr_GlobVec (MsgPort $5C + 44 = $88), getlong(20,
; taskid) = pr_CLI, putlong(12, taskid, slot) = pr_TaskNum. (La spec analyse §8.1 inversait base/indice : corrigé.)
g_getlong:
        move.l  d2,a3
        lsl.l   #2,d1
        move.l  0(a3,d1.l),d1
        jmp     (a6)
g_putlong:
        move.l  d2,a3
        lsl.l   #2,d1
        move.l  d3,0(a3,d1.l)
        jmp     (a6)

; 115 copystring(src, dst) : copie le BSTR src (longueur + 1 octets) dans dst.
g_copystring:
        lsl.l   #2,d1
        move.l  d1,a3
        lsl.l   #2,d2
        move.l  d2,a4                ; (a4 rechargé par bcpl_ret)
        moveq   #0,d0
        move.b  (a3),d0
.cy_lp:
        move.b  (a3)+,(a4)+
        dbra    d0,.cy_lp
        jmp     (a6)

; 134 findcli() -> pr_CLI (BPTR)
g_findcli:
        bsr     rt_this
        move.l  PR_CLI(a3),d1
        jmp     (a6)

; consoletask() (105) / filesystemtask() (106) -> pr_ConsoleTask / pr_FileSystemTask du process (ports des handlers)
g_consoletask:
        bsr     rt_this
        move.l  PR_CONSOLETASK(a3),d1
        jmp     (a6)
g_filesystemtask:
        bsr     rt_this
        move.l  PR_FILESYSTEMTASK(a3),d1
        jmp     (a6)

ft_msg:
        dc.b    "Error code ",0
ft_cfault:
        dc.b    "C:FAULT",0
ra_colon:
        dc.b    ": "
        EVEN

; --- segment runtime au format BCPL (spec §3.1) : [lien][N][0][paires (globale, offset)]...[max] ---
GLOB            MACRO
        dc.l    \1,\2-bcpl_rtdata
                ENDM
        cnop    0,4
bcpl_rtseg:
        dc.l    0                    ; lien : segment unique
bcpl_rtdata:
        dc.l    (bcpl_rtend-bcpl_rtdata)/4
        dc.l    0                    ; terminateur de la table
        GLOB    -26,g_isinteractive
        GLOB    -20,g_clearvec
        GLOB    -8,g_cseek
        GLOB    -6,g_cwrite
        GLOB    -3,g_cread
        GLOB    -2,g_copyvec
        GLOB    -1,g_copen
        GLOB    2,g_stop
        GLOB    3,g_mult
        GLOB    4,g_div
        GLOB    5,g_rem
        GLOB    6,g_setio
        GLOB    10,g_result2
        GLOB    13,g_makeglobvec
        GLOB    14,g_taskid
        GLOB    17,g_level
        GLOB    18,g_longjump
        GLOB    19,g_getmem
        GLOB    21,g_doio
        GLOB    22,g_sendio
        GLOB    28,g_globin
        GLOB    29,g_getvec
        GLOB    30,g_freevec
        GLOB    31,g_opendevice
        GLOB    32,g_closedevice
        GLOB    33,g_createproc
        GLOB    34,g_endtask
        GLOB    35,g_parentdir
        GLOB    36,g_setflags
        GLOB    37,g_testflags
        GLOB    39,g_rootstruct
        GLOB    40,g_readbytes
        GLOB    41,g_taskwait
        GLOB    42,g_qpkt
        GLOB    43,g_writebytes
        GLOB    47,g_delay
        GLOB    48,g_sendpkt
        GLOB    49,g_returnpkt
        GLOB    50,g_openwindow
        GLOB    51,g_currentdir
        GLOB    53,g_writet
        GLOB    54,g_rdch
        GLOB    55,g_unrdch
        GLOB    56,g_wrch
        GLOB    59,g_findinput
        GLOB    60,g_findoutput
        GLOB    61,g_selectinput
        GLOB    62,g_selectoutput
        GLOB    63,g_endread
        GLOB    64,g_endwrite
        GLOB    65,g_input
        GLOB    66,g_output
        GLOB    68,g_newline
        GLOB    69,g_writed
        GLOB    70,g_writen
        GLOB    71,g_writehex
        GLOB    72,g_writeoct
        GLOB    73,g_writes
        GLOB    74,g_writef
        GLOB    75,g_capitalch
        GLOB    76,g_compch
        GLOB    77,g_compstring
        GLOB    78,g_rdargs
        GLOB    79,g_rditem
        GLOB    80,g_findarg
        GLOB    81,g_load
        GLOB    82,g_unloadseg
        GLOB    85,g_makedevnode
        GLOB    86,g_datstamp
        GLOB    88,g_callexec
        GLOB    89,g_findsegarray
        GLOB    90,g_deleteobj
        GLOB    91,g_rename
        GLOB    93,g_endstream
        GLOB    102,g_deviceproc
        GLOB    103,g_calllib
        GLOB    104,g_fault
        GLOB    105,g_consoletask
        GLOB    106,g_filesystemtask
        GLOB    107,g_splitname
        GLOB    108,g_locateobj
        GLOB    109,g_freeobj
        GLOB    110,g_getlong
        GLOB    111,g_putlong
        GLOB    112,g_starthandler
        GLOB    113,g_copydir
        GLOB    114,g_errorreq
        GLOB    115,g_copystring
        GLOB    121,g_runcommand
        GLOB    123,g_lock
        GLOB    124,g_finddevinfo
        GLOB    125,g_createdir
        GLOB    126,g_compstamp
        GLOB    128,g_setdatstamp
        GLOB    134,g_findcli
        dc.l    134                  ; plus grande globale du segment
bcpl_rtend:

; --- stubs de diagnostic (GV du CLI) : un par slot (-50..150). Le stub i fait bsr.w bcpl_unimpl : l'adresse de
; retour donne l'offset du slot appelé, émis sur le série (« BCPL GLOBAL xxxx NON IMPL »), puis retour BCPL d1 = 0.
; (Le GV PRIVÉ d'une commande ne les voit pas : son stub remplit les slots non définis par $474C0001+2n.)
BCPL_STUB       MACRO
        bsr.w   bcpl_unimpl          ; taille FIXE (bsr.w) : les stubs doivent être identiques
                ENDM
bcpl_stubs:
        BCPL_STUB
bcpl_stub1:
BCPL_STUBSZ     EQU bcpl_stub1-bcpl_stubs   ; 4 = taille d'un slot : le calcul d'offset de bcpl_unimpl en dépend
                rept    (GV_SIZE/4)-1
        BCPL_STUB
                endr
bcpl_unimpl:
        movem.l d0/a0,-(sp)
        move.l  8(sp),d0             ; retour = stub + BCPL_STUBSZ
        sub.l   #bcpl_stubs+BCPL_STUBSZ,d0   ; = index * 4
        sub.l   #GV_NEG,d0           ; -> offset du slot dans le GV
        lea     bcpl_msg_unimpl(pc),a0
        jsr     ser_puts
        jsr     ser_puthex
        lea     bcpl_msg_crlf(pc),a0
        jsr     ser_puts
        movem.l (sp)+,d0/a0
        addq.l  #4,sp                ; retire l'adresse de retour du stub
        moveq   #0,d1
        jmp     (a6)
bcpl_intuiname:
        dc.b    "intuition.library",0
        EVEN
bcpl_msg_unimpl:
        dc.b    "BCPL GLOBAL ",0
bcpl_msg_crlf:
        dc.b    " NON IMPL",13,10,0
        EVEN
