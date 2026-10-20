; src/dos/shell.s — shell interactif minimal (E2). Corps d'un Process : ouvre la console « CON:0/0/640/200/
; AmigaSlopDOS » (handler E1 via DOS packets vers DOS_CONPORT : fenêtre sur l'écran Workbench + miroir série), émet une
; bannière de test sur le série, exécute la startup-sequence (fenêtre fermée si EndCLI a passé le CLI en arrière-plan),
; puis boucle : écrit l'invite, lit UNE LIGNE, parse le 1er mot, dispatche vers un builtin. Builtins : « ver »
; (bannière de version) et « echo <args> » (comme c:Echo : sans guillemets englobants, puis saut de ligne) ;
; tout le reste -> « ? ». PAS de CLI BCPL (pr_CLI/CommandLineInterface/Execute = Bootstrap réel F).
;
; Tout l'IO passe par des FileHandles DOS (ici la clé renvoyée par FINDINPUT) vers le handler console — jamais
; directement sur SERDAT. En F on remplacera le handler par un console.device sans toucher à CE binaire shell.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs dos (Open/Read/Write) + spec analyse packets. AUCUNE lecture ROM.

                include "exec.i"
                include "dospkt.i"

                xdef    shell_main
                xref    ser_puts             ; exec/boot.s (bannière de test sur le série)
                xref    dos_sendpkt
                xref    ls_load_hunks        ; dos/loadseg.s (E3 : parse hunk d'un buffer lu via dos)
                xref    dos_unloadseg        ; dos/loadseg.s (E3 : libérer la seglist)
                xref    ser_lock             ; exec/boot.s (émission série atomique)
                xref    ser_unlock
                xref    dos_boot_assigns     ; dos/dos_lib.s (assigns + volume + répertoire courant)
                xref    bcpl_call            ; dos/bcpl.s (A5/A6 des commandes BCPL)
                xref    bcpl_ret
                xref    bcpl_cli_setup
                xref    bcpl_cli_register

SH_SCRIPTMAX    EQU 2048             ; taille max de la startup-sequence lue (F1)

SHELL_LINEMAX   EQU 128              ; taille max d'une ligne lue
SH_ECHO_ARGOFF  EQU 5                ; offset des args après « echo » + 1 espace

; shell_main : corps du process. GPR à zéro à l'entrée (frame AddTask) -> recharge SysBase.
; a2 = StandardPacket (pile), a3 = buffer ligne (pile), d7 = clé console, d6 = octets lus.
shell_main:
                move.l  ($4).w,a6
                lea     -(SP_SIZEOF+SHELL_LINEMAX)(sp),sp
                move.l  sp,a2                ; a2 = StandardPacket
                lea     SP_SIZEOF(sp),a3     ; a3 = buffer ligne
                ; ouvrir la console
                move.l  DOS_CONPORT,a1
                move.l  a2,a0
                move.l  #ACTION_FINDINPUT,d0
                moveq   #0,d1
                moveq   #0,d2
                move.l  #sh_conname,d3       ; « CON:0/0/640/200/AmigaSlopDOS » : fenêtre de la console initiale
                lsr.l   #2,d3
                jsr     dos_sendpkt
                move.l  d0,d7                ; d7 = clé
                ; FileHandle console -> pr_CIS/pr_COS : Input()/Output() des commandes lancées écrivent sur la console
                move.l  #FH_SIZEOF+4,d0      ; bloc getvec [taille][FileHandle] : Close le libère par l'en-tête
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .nofh
                move.l  d0,a0
                move.l  #FH_SIZEOF+4,(a0)+
                move.l  a0,d0
                move.l  DOS_CONPORT,FH_TYPE(a0)
                move.l  d7,FH_ARG1(a0)
                move.l  #DOSTRUE,FH_INTERACTIVE(a0)
                moveq   #-1,d1
                move.l  d1,FH_POS(a0)        ; fh_Pos = fh_End = -1 : tampon vide, la 1re lecture BCPL remplit
                move.l  d1,FH_END(a0)
                lsr.l   #2,d0
                move.l  EB_THISTASK(a6),a0
                move.l  d0,PR_CIS(a0)
                move.l  d0,PR_COS(a0)
.nofh:
                bsr     sh_make_cli          ; pr_CLI : sans lui les commandes se croient lancées par le Workbench
                lea     sh_doslib(pc),a1     ; assigns SYS: C: S: L: ... + répertoire courant = racine du disque
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq.s   .noassign
                move.l  d0,a6
                jsr     dos_boot_assigns
                move.l  a6,a1
                move.l  ($4).w,a6
                jsr     LVO_CLOSELIBRARY(a6)
.noassign:
                ; bannière de test (marqueur série du harnais : l'Initial CLI démarre ; pas dans la fenêtre)
                lea     sh_banner(pc),a0
                jsr     ser_puts
                ifeq    F1_NO_STARTUP
                bsr     sh_run_startup       ; F1 : exécuter s/startup-sequence (sous-rép OFS) AVANT l'interactif
                endc                         ; RED F1_NO_STARTUP : saute le script -> directement interactif
                bsr     sh_cli_ptr           ; EndCLI a passé le CLI en arrière-plan : sa fenêtre se ferme (END) ;
                beq.s   .loop                ; l'invite de secours continue sur le série
                tst.l   CLI_BACKGROUND(a1)
                beq.s   .loop
                move.l  DOS_CONPORT,a1
                move.l  a2,a0
                move.l  #ACTION_END,d0
                move.l  d7,d1
                moveq   #0,d2
                moveq   #0,d3
                jsr     dos_sendpkt
.loop:
                move.l  #sh_prompt,a4        ; invite « > »
                move.l  #sh_prompt_len,d4
                bsr     sh_write
                bsr     sh_readline          ; -> d6 = octets, ligne en (a3)
                bsr     sh_dispatch_line     ; parse le 1er mot -> builtin / commande externe / « ? »
                bra.s   .loop

; sh_dispatch_line(a3 = ligne, d6 = longueur) : parse le 1er mot et dispatche. Appelé par la boucle interactive ET
; par l'exécuteur de startup-sequence (F1). Clobbe d0/d1/d4 + a0/a1/a4 ; préserve d2/d3/d5/d6/d7 + a2/a3/a5/a6.
sh_dispatch_line:
                ifne    E2_NO_DISPATCH
                bra     .dl_extern           ; RED E2 : pas de dispatch builtin -> commande externe
                endc
                lea     sh_cmd_ver(pc),a0    ; « ver » ?
                move.l  a3,a1
                bsr     sh_match
                tst.l   d0
                beq.s   .dl_not_ver
                move.l  #sh_vermsg,a4
                move.l  #sh_vermsg_len,d4
                bsr     sh_write
                rts
.dl_not_ver:
                lea     sh_cmd_echo(pc),a0   ; « echo <args> » ?
                move.l  a3,a1
                bsr     sh_match
                tst.l   d0
                beq.s   .dl_extern
                move.l  d6,d4                ; args = ligne + SH_ECHO_ARGOFF, len = longueur - SH_ECHO_ARGOFF
                sub.l   #SH_ECHO_ARGOFF,d4
                bls.s   .dl_ret              ; « echo » sans args
                move.l  a3,a4
                add.l   #SH_ECHO_ARGOFF,a4
.dl_etrim:                           ; comme c:Echo : sans fin de ligne ni guillemets englobants, puis saut de ligne
                move.b  -1(a4,d4.l),d0
                cmp.b   #13,d0
                beq.s   .dl_ecut
                cmp.b   #10,d0
                bne.s   .dl_equote
.dl_ecut:
                subq.l  #1,d4
                bne.s   .dl_etrim
                bra.s   .dl_enl
.dl_equote:
                cmp.l   #2,d4
                blo.s   .dl_eout
                cmp.b   #'"',(a4)
                bne.s   .dl_eout
                cmp.b   #'"',-1(a4,d4.l)
                bne.s   .dl_eout
                addq.l  #1,a4
                subq.l  #2,d4
.dl_eout:
                bsr     sh_write
.dl_enl:
                lea     sh_crlf(pc),a4
                moveq   #2,d4
                bsr     sh_write
.dl_ret:
                rts
.dl_extern:
                ; commande externe -> charger+exécuter via dos. Termine le 1er mot en place ; le reste = arguments.
                ; Espaces de tête ignorés ; ligne vide ou commentaire seul (ex. suite de ligne « ;... ») -> rien.
                move.l  a3,a0
.dl_lead:
                move.b  (a0),d0
                cmp.b   #' ',d0
                beq.s   .dl_skip
                cmp.b   #9,d0
                bne.s   .dl_first
.dl_skip:
                addq.l  #1,a0
                bra.s   .dl_lead
.dl_first:
                tst.b   d0
                beq     .dl_ret
                cmp.b   #';',d0
                beq     .dl_ret
                cmp.b   #13,d0
                beq     .dl_ret
                cmp.b   #10,d0
                beq     .dl_ret
                move.l  a0,-(sp)             ; début du nom de commande
.dl_nt:
                move.b  (a0),d0
                beq.s   .dl_noargs
                cmp.b   #' ',d0
                beq.s   .dl_cut_sp
                cmp.b   #13,d0
                beq.s   .dl_cut
                cmp.b   #10,d0               ; LF (ligne de script) aussi = frontière
                beq.s   .dl_cut
                addq.l  #1,a0
                bra.s   .dl_nt
.dl_cut_sp:
                clr.b   (a0)+                ; termine le nom ; les arguments suivent l'espace
                move.l  a0,a1
                move.l  a3,d1
                add.l   d6,d1
                sub.l   a0,d1                ; d1 = longueur restante de la ligne
                bra.s   .dl_call
.dl_cut:
                clr.b   (a0)
.dl_noargs:
                move.l  a0,a1
                moveq   #0,d1                ; pas d'arguments
.dl_call:
                move.l  (sp)+,a0             ; a0 = nom de commande C-string
                bsr     sh_exec_cmd          ; d0 = 1 si trouvée+chargée, 0 sinon
                tst.l   d0
                bne.s   .dl_ret2
                move.l  #sh_unknown,a4       ; non trouvée -> « ? »
                move.l  #sh_unknown_len,d4
                bsr     sh_write
.dl_ret2:
                rts

; sh_write(a4=buffer, d4=len) : WRITE via le handler console. Préserve a2/a3/a4/d4/d6/d7.
sh_write:
                movem.l d0-d3/a0-a1,-(sp)
                move.l  DOS_CONPORT,a1
                move.l  a2,a0
                move.l  #ACTION_WRITE,d0
                move.l  d7,d1
                move.l  a4,d2
                move.l  d4,d3
                jsr     dos_sendpkt
                movem.l (sp)+,d0-d3/a0-a1
                rts

; sh_readline() -> d6 = octets lus, ligne en (a3). READ via le handler console (bloque jusqu'au CR).
sh_readline:
                movem.l d0-d3/a0-a1,-(sp)
                move.l  DOS_CONPORT,a1
                move.l  a2,a0
                move.l  #ACTION_READ,d0
                move.l  d7,d1
                move.l  a3,d2
                move.l  #SHELL_LINEMAX,d3
                jsr     dos_sendpkt
                move.l  d0,d6
                movem.l (sp)+,d0-d3/a0-a1
                rts

; sh_match(a0=cmd C-string, a1=ligne) -> d0 = 1 si la ligne commence par cmd suivi d'une frontière de mot
; (espace / CR / fin). Clobbe a0/a1/d0/d1.
sh_match:
.m_lp:
                move.b  (a0)+,d1
                beq.s   .m_wordend           ; fin du mot cmd
                cmp.b   (a1)+,d1
                bne.s   .m_no
                bra.s   .m_lp
.m_wordend:
                move.b  (a1),d1              ; caractère de la ligne après le préfixe
                cmp.b   #' ',d1
                beq.s   .m_yes
                cmp.b   #13,d1               ; CR (fin de ligne)
                beq.s   .m_yes
                tst.b   d1
                beq.s   .m_yes               ; fin de chaîne
.m_no:
                moveq   #0,d0
                rts
.m_yes:
                moveq   #1,d0
                rts

; sh_exec_cmd(a0 = nom C-string, a1 = arguments bruts, d1 = longueur des arguments) : charge+exécute une commande via
; dos -> d0 = 1 si trouvée + chargée, 0 sinon. Recherche : le nom tel quel (répertoire courant, ou « device: »/assign),
; puis « C:<nom> » si le nom n'a pas de ':'. Convention d'appel CLI : a0 = arguments terminés par '\n', d0 = leur
; longueur, 4(sp) = taille de pile. La commande peut écraser tous les registres : seglist, DosBase et drapeau vivent
; dans un cadre sur la pile. Préserve le contexte shell (movem d2-d7/a2-a6) ; a6 = SysBase en sortie.
XF_FLAG         EQU 0                ; LONG : 1 si trouvée + chargée
XF_SEG          EQU 4                ; LONG : BPTR seglist
XF_DOS          EQU 8                ; APTR : DosBase
XF_ARGLEN       EQU 12               ; LONG : longueur des arguments (avec le '\n')
XF_NAME         EQU 16               ; « C:<nom> » (SH_NAMEMAX)
SH_NAMEMAX      EQU 64
XF_ARGS         EQU XF_NAME+SH_NAMEMAX   ; arguments filtrés (SH_ARGMAX)
SH_ARGMAX       EQU 256
XF_STK          EQU XF_ARGS+SH_ARGMAX    ; APTR : pile dédiée de la commande
XF_STKSZ        EQU XF_STK+4         ; LONG : taille du bloc en octets (pile annoncée + 4)
XF_ABUF         EQU XF_STKSZ+4       ; APTR : tampon d'arguments de la CLI (aligné : BPTR)
XF_FH           EQU XF_ABUF+4        ; APTR : FileHandle d'entrée (injection des arguments)
XF_SBUF         EQU XF_FH+4          ; fh_Buf / fh_Pos / fh_End sauvés
XF_SPOS         EQU XF_SBUF+4
XF_SEND         EQU XF_SPOS+4
XF_RC           EQU XF_SEND+4        ; LONG : code retour
XF_SIZE         EQU XF_RC+4
SH_DEFSTACK     EQU 1000             ; pile par défaut d'une commande, en longs (cli_DefaultStack)
sh_exec_cmd:
                movem.l d2-d7/a2-a6,-(sp)
                lea     -XF_SIZE(sp),sp
                clr.l   XF_FLAG(sp)
                move.l  a0,d5                ; d5 = nom
                lea     XF_ARGS(sp),a2
                bsr     sh_build_args        ; (a1, d1) -> arguments filtrés en (a2) ; d0 = longueur
                move.l  d0,XF_ARGLEN(sp)
                move.l  ($4).w,a6            ; SysBase
                lea     sh_doslib(pc),a1
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq     .x_ret
                move.l  d0,a4                ; a4 = DosBase
                move.l  d0,XF_DOS(sp)
                ; --- taille réelle du fichier : Lock + Examine ---
                move.l  #FIB_SIZEOF,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .x_closelib
                move.l  d0,a5                ; a5 = FileInfoBlock
                moveq   #0,d4                ; d4 = taille (0 = introuvable / illisible)
                move.l  a4,a6
                move.l  d5,d1
                moveq   #SHARED_LOCK,d2
                jsr     DOS_LVO_LOCK(a6)     ; BPTR lock | 0
                tst.l   d0
                bne.s   .x_locked
                move.l  d5,a0                ; repli « C:<nom> » seulement pour un nom sans ':'
.x_colon:
                move.b  (a0)+,d0
                beq.s   .x_tryc
                cmp.b   #':',d0
                bne.s   .x_colon
                bra.s   .x_nolock
.x_tryc:
                lea     XF_NAME(sp),a1
                move.b  #'C',(a1)+
                move.b  #':',(a1)+
                move.l  d5,a0
                moveq   #SH_NAMEMAX-3,d1
.x_ccpy:
                move.b  (a0)+,(a1)+
                beq.s   .x_cdone
                subq.l  #1,d1
                bne.s   .x_ccpy
                clr.b   (a1)                 ; nom tronqué
.x_cdone:
                lea     XF_NAME(sp),a0
                move.l  a0,d1
                moveq   #SHARED_LOCK,d2
                jsr     DOS_LVO_LOCK(a6)
                tst.l   d0
                beq.s   .x_nolock
                lea     XF_NAME(sp),a0
                move.l  a0,d5                ; le fichier sera ouvert sous ce nom
.x_locked:
                move.l  d0,d7                ; d7 = lock
                move.l  d7,d1
                move.l  a5,d2
                jsr     DOS_LVO_EXAMINE(a6)
                tst.l   d0
                beq.s   .x_unlock
                tst.l   FIB_DIRENTRYTYPE(a5)
                bpl.s   .x_unlock            ; répertoire -> pas exécutable
                move.l  FIB_SIZE(a5),d4
.x_unlock:
                move.l  d7,d1
                jsr     DOS_LVO_UNLOCK(a6)
.x_nolock:
                move.l  ($4).w,a6
                move.l  a5,a1
                move.l  #FIB_SIZEOF,d0
                jsr     LVO_FREEMEM(a6)
                tst.l   d4
                beq     .x_closelib
                ; --- buffer à la taille du fichier, MEMF_PUBLIC : en slow RAM si présente (la chip reste au programme) ---
                move.l  d4,d0
                move.l  #MEMF_PUBLIC,d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .x_closelib
                move.l  d0,a5                ; a5 = filebuf (d4 octets)
                moveq   #0,d7                ; d7 = 0 tant qu'aucune seglist (Open raté -> rien à exécuter)
                move.l  a4,a6
                move.l  d5,d1
                move.l  #MODE_OLDFILE,d2
                jsr     DOS_LVO_OPEN(a6)     ; BPTR fh | 0
                tst.l   d0
                beq.s   .x_freebuf
                move.l  d0,d7                ; d7 = BPTR fh
                moveq   #0,d6                ; d6 = octets lus
.x_rd:                                       ; le file-handler est séquentiel : boucle jusqu'à EOF / plein
                move.l  d7,d1
                move.l  a5,d2
                add.l   d6,d2
                move.l  d4,d3
                sub.l   d6,d3
                beq.s   .x_rddone
                jsr     DOS_LVO_READ(a6)     ; d0 = octets lus (0 = EOF, -1 = erreur)
                tst.l   d0
                ble.s   .x_rddone
                add.l   d0,d6
                bra.s   .x_rd
.x_rddone:
                move.l  d7,d1
                jsr     DOS_LVO_CLOSE(a6)
                move.l  ($4).w,a6            ; SysBase
                moveq   #0,d7                ; d7 = seglist (0 = échec)
                tst.l   d6
                beq.s   .x_freebuf           ; rien lu
                move.l  a5,a0
                move.l  d6,d0
                jsr     ls_load_hunks        ; d0 = BPTR seglist | 0
                move.l  d0,d7
.x_freebuf:
                move.l  ($4).w,a6            ; libère le buffer AVANT d'exécuter : rend la mémoire au programme
                move.l  a5,a1
                move.l  d4,d0
                jsr     LVO_FREEMEM(a6)
                tst.l   d7
                beq     .x_closelib
                move.l  d7,XF_SEG(sp)
                move.l  #1,XF_FLAG(sp)       ; TROUVÉE + chargée
                move.l  d5,a0
                move.l  d7,d0
                bsr     sh_cli_begin         ; cli_CommandName = nom, cli_Module = seglist
                ifeq    E3_NO_EXEC
                jsr     ser_lock             ; la commande chargée émet sous Forbid -> marqueur atomique (pas d'entrelacement)
                ; --- pile dédiée de cli_DefaultStack longs (comme runcommand) : le stub BCPL pose la base de ses
                ; frames à 8(sp) - 4(sp) = (sommet - 4) - taille -> bloc d'UN long de plus que la taille annoncée,
                ; sinon le premier frame écrase le dernier long du bloc mémoire précédent ---
                move.l  #SH_DEFSTACK*4,d0
                bsr     sh_cli_ptr
                beq.s   .x_stk
                move.l  CLI_DEFAULTSTACK(a1),d0
                lsl.l   #2,d0
.x_stk:
                addq.l  #4,d0
                move.l  d0,XF_STKSZ(sp)
                move.l  #MEMF_PUBLIC,d1
                move.l  ($4).w,a6
                jsr     LVO_ALLOCMEM(a6)
                move.l  d0,XF_STK(sp)
                beq     .x_nostack
                ; --- arguments : copie dans le tampon aligné de la CLI, injectée dans le FileHandle d'entrée ---
                bsr     sh_cli_ptr
                lea     SH_ARGBUF(a1),a1
                move.l  a1,XF_ABUF(sp)
                lea     XF_ARGS(sp),a0
                move.l  XF_ARGLEN(sp),d0
                bra.s   .x_acnext
.x_acpy:
                move.b  (a0)+,(a1)+
.x_acnext:
                dbra    d0,.x_acpy
                move.l  ($4).w,a2
                move.l  EB_THISTASK(a2),a2   ; a2 = process
                clr.l   PR_RESULT2(a2)
                move.l  PR_CIS(a2),d0        ; entrée de la commande = cli_StandardInput (spec §4.2.3), pas pr_CIS
                bsr     sh_cli_ptr           ; (qu'une commande précédente a pu sélectionner puis fermer : Mount)
                beq.s   .x_inpok
                move.l  CLI_STANDARDINPUT(a1),d0
                move.l  d0,PR_CIS(a2)        ; selectinput(stdin) avant la commande
                move.l  CLI_STANDARDOUTPUT(a1),PR_COS(a2)
.x_inpok:
                lsl.l   #2,d0
                move.l  d0,XF_FH(sp)
                beq.s   .x_noinj
                move.l  d0,a0
                move.l  FH_BUF(a0),XF_SBUF(sp)
                move.l  FH_POS(a0),XF_SPOS(sp)
                move.l  FH_END(a0),XF_SEND(sp)
                move.l  XF_ABUF(sp),d0
                lsr.l   #2,d0
                move.l  d0,FH_BUF(a0)
                clr.l   FH_POS(a0)
                move.l  XF_ARGLEN(sp),FH_END(a0)
.x_noinj:
                ; registres d'entrée (spec §4.3) : a0/d0 = arguments, 4(sp) = taille de pile, A1 = frame BCPL du CLI
                ; (bas de SA pile), A2 = GV du CLI, A3 = segment, A4 = point d'entrée, A5/A6 = appel/retour BCPL
                move.l  XF_SEG(sp),d0
                lsl.l   #2,d0
                move.l  d0,a3                ; a3 = segment
                lea     4(a3),a4             ; a4 = point d'entrée
                move.l  XF_STK(sp),a5
                add.l   XF_STKSZ(sp),a5      ; a5 = sommet de la pile de la commande
                move.l  sp,-(a5)             ; 8(sp) à l'entrée : ancien SP (restauré au retour)
                move.l  XF_STKSZ(sp),d0
                subq.l  #4,d0
                move.l  d0,-(a5)             ; 4(sp) : taille de la pile en octets (sans le long de base)
                move.l  a5,PR_RETURNADDR(a2) ; pr_ReturnAddr -> ce long : exit()/stop y retrouvent la pile
                move.l  XF_ABUF(sp),d2
                move.l  XF_ARGLEN(sp),d0
                move.l  PR_GLOBVEC(a2),a1
                move.l  TC_SPLOWER(a2),d1
                move.l  a1,a2                ; a2 = GV
                move.l  d1,a1                ; a1 = bas de la pile du CLI = frame BCPL de l'appelant
                move.l  a5,sp                ; bascule sur la pile de la commande (plus d'accès XF_* jusqu'au retour)
                move.l  d2,a0
                moveq   #0,d1
                lea     bcpl_call,a5
                lea     bcpl_ret,a6
                jsr     (a4)                 ; exécute la commande ; d0 = code retour
                addq.l  #4,sp
                move.l  (sp),sp              ; retour sur la pile du shell
                move.l  d0,XF_RC(sp)
                move.l  ($4).w,a2
                move.l  EB_THISTASK(a2),a2
                clr.l   PR_RETURNADDR(a2)
                bsr     sh_cli_ptr           ; après la commande (spec §4.4) : selectoutput(cli_StandardOutput),
                beq.s   .x_noresel           ; selectinput(cli_CurrentInput) — la commande a pu changer ou fermer ses flux
                move.l  CLI_STANDARDOUTPUT(a1),PR_COS(a2)
                move.l  CLI_CURRENTINPUT(a1),PR_CIS(a2)
.x_noresel:
                move.l  XF_FH(sp),d0         ; restaure le tampon d'entrée (spec §4.2.6)
                beq.s   .x_norest
                move.l  d0,a0
                move.l  XF_ABUF(sp),d0
                lsr.l   #2,d0
                cmp.l   FH_BUF(a0),d0
                bne.s   .x_rbuf
                move.l  XF_SBUF(sp),FH_BUF(a0)
.x_rbuf:
                move.l  XF_SPOS(sp),FH_POS(a0)
                tst.l   FH_END(a0)
                beq.s   .x_norest            ; fh_End = 0 : EOF forcé par la commande (EndCLI) -> conservé
                move.l  XF_SEND(sp),FH_END(a0)
.x_norest:
                move.l  XF_STK(sp),a1
                move.l  XF_STKSZ(sp),d0
                move.l  ($4).w,a6
                jsr     LVO_FREEMEM(a6)
                move.l  XF_RC(sp),d0
                bra.s   .x_ran
.x_nostack:
                moveq   #-1,d0               ; pile impossible : code spécial « impossible de lancer »
.x_ran:
                bsr     sh_cli_end           ; cli_ReturnCode = d0, cli_Module = 0
                jsr     ser_unlock
                endc                         ; RED E3_NO_EXEC : saute le JSR -> commande chargée mais pas exécutée
                move.l  ($4).w,a6
                move.l  XF_SEG(sp),d0
                jsr     dos_unloadseg
.x_closelib:
                move.l  ($4).w,a6
                move.l  XF_DOS(sp),a1
                jsr     LVO_CLOSELIBRARY(a6)
.x_ret:
                move.l  XF_FLAG(sp),d0
                lea     XF_SIZE(sp),sp
                movem.l (sp)+,d2-d7/a2-a6
                rts

; sh_make_cli() : alloue une CommandLineInterface + ses BSTR (nom de commande, SetName, prompt) et la publie dans
; pr_CLI de ThisTask. Flux = pr_CIS/pr_COS, pile par défaut = SH_STK, FailLevel 10. Préserve tout.
SH_CLIBSTR      EQU 256              ; taille d'un buffer BSTR de la CLI
SH_ARGBUF       EQU CLI_SIZEOF+3*SH_CLIBSTR  ; tampon d'arguments injectés (aligné long : fh_Buf est un BPTR)
SH_CLIALLOC     EQU SH_ARGBUF+SH_ARGMAX
sh_make_cli:
                movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  ($4).w,a6
                move.l  #SH_CLIALLOC,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .mc_ret
                move.l  d0,a0                ; a0 = CLI
                lea     CLI_SIZEOF(a0),a1
                move.l  a1,d1
                lsr.l   #2,d1
                move.l  d1,CLI_COMMANDNAME(a0)
                add.l   #SH_CLIBSTR/4,d1
                move.l  d1,CLI_SETNAME(a0)
                add.l   #SH_CLIBSTR/4,d1
                move.l  d1,CLI_PROMPT(a0)
                lsl.l   #2,d1
                move.l  d1,a1
                move.l  #$023E2000,(a1)      ; prompt BSTR « > » (longueur 2)
                move.l  #10,CLI_FAILLEVEL(a0)
                move.l  #SH_DEFSTACK,CLI_DEFAULTSTACK(a0)
                move.l  #DOSTRUE,CLI_INTERACTIVE(a0)
                move.l  EB_THISTASK(a6),a1
                move.l  PR_CIS(a1),d1
                move.l  d1,CLI_STANDARDINPUT(a0)
                move.l  d1,CLI_CURRENTINPUT(a0)
                move.l  PR_COS(a1),d1
                move.l  d1,CLI_STANDARDOUTPUT(a0)
                move.l  d1,CLI_CURRENTOUTPUT(a0)
                lsr.l   #2,d0
                move.l  d0,PR_CLI(a1)
                move.l  a1,a0                ; vecteur global BCPL + segarray du runtime (commandes c: BCPL)
                jsr     bcpl_cli_setup
                jsr     bcpl_cli_register    ; slot 1 de rn_TaskArray, pr_TaskNum = 1 (Run prend les suivants)
.mc_ret:
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts

; sh_cli_begin(a0 = nom C-string, d0 = BPTR seglist) : renseigne cli_CommandName (BSTR) et cli_Module. Clobbe d0-d1/a0-a1.
sh_cli_begin:
                move.l  a2,-(sp)
                bsr.s   sh_cli_ptr           ; a1 = CLI | 0
                beq.s   .cb_ret
                move.l  d0,CLI_MODULE(a1)
                move.l  CLI_COMMANDNAME(a1),d0
                lsl.l   #2,d0
                move.l  d0,a2                ; a2 = BSTR
                moveq   #0,d1
.cb_cpy:
                move.b  (a0)+,d0
                beq.s   .cb_len
                move.b  d0,1(a2,d1.l)
                addq.l  #1,d1
                cmp.l   #SH_CLIBSTR-1,d1
                bcs.s   .cb_cpy
.cb_len:
                move.b  d1,(a2)
.cb_ret:
                move.l  (sp)+,a2
                rts

; sh_cli_end(d0 = code retour de la commande) : cli_ReturnCode = d0, cli_Module = 0. Préserve tout sauf a1.
sh_cli_end:
                move.l  d0,-(sp)
                bsr.s   sh_cli_ptr
                beq.s   .ce_ret
                move.l  (sp),CLI_RETURNCODE(a1)
                clr.l   CLI_MODULE(a1)
.ce_ret:
                move.l  (sp)+,d0
                rts

; sh_cli_ptr() -> a1 = CLI de ThisTask (Z = 1 si aucune). Préserve d0.
sh_cli_ptr:
                move.l  d0,-(sp)
                move.l  ($4).w,a1
                move.l  EB_THISTASK(a1),a1
                move.l  PR_CLI(a1),d0
                lsl.l   #2,d0
                move.l  d0,a1
                movem.l (sp)+,d0             ; movem ne touche pas le CCR : Z vient du lsl
                rts

; sh_build_args(a1 = arguments bruts, d1 = longueur, a2 = destination SH_ARGMAX) -> d0 = longueur écrite (avec '\n').
; Copie jusqu'à CR/LF/NUL, retire les redirections (« >x », « <x » en début de mot : pas encore de redirection
; réelle, la commande écrit sur la console) et le commentaire « ; » hors guillemets ; termine par '\n' puis NUL.
; Clobbe d0-d4/a0/a2.
sh_build_args:
                move.l  a1,a0
                moveq   #0,d2                ; d2 = octets écrits
                moveq   #1,d3                ; d3 != 0 : début de mot
                moveq   #0,d4                ; bit0 = entre guillemets, bit1 = saute une redirection
.ba_lp:
                tst.l   d1
                ble.s   .ba_end
                move.b  (a0)+,d0
                subq.l  #1,d1
                cmp.b   #13,d0
                beq.s   .ba_end
                cmp.b   #10,d0
                beq.s   .ba_end
                tst.b   d0
                beq.s   .ba_end
                btst    #1,d4
                beq.s   .ba_noskip
                cmp.b   #' ',d0
                bne.s   .ba_lp
                bclr    #1,d4                ; fin du mot de redirection
                moveq   #1,d3
                bra.s   .ba_lp
.ba_noskip:
                cmp.b   #'"',d0
                bne.s   .ba_noquote
                bchg    #0,d4
                moveq   #0,d3
                bra.s   .ba_put
.ba_noquote:
                btst    #0,d4
                bne.s   .ba_plain
                cmp.b   #';',d0
                beq.s   .ba_end              ; commentaire
                tst.l   d3
                beq.s   .ba_plain
                cmp.b   #'>',d0
                beq.s   .ba_redir
                cmp.b   #'<',d0
                bne.s   .ba_plain
.ba_redir:
                bset    #1,d4
                bra.s   .ba_lp
.ba_plain:
                moveq   #0,d3
                cmp.b   #' ',d0
                bne.s   .ba_put
                moveq   #1,d3
.ba_put:
                cmp.l   #SH_ARGMAX-2,d2
                bhs.s   .ba_lp               ; plein : le reste est ignoré
                move.b  d0,(a2)+
                addq.l  #1,d2
                bra.s   .ba_lp
.ba_end:
                move.b  #10,(a2)+
                clr.b   (a2)
                addq.l  #1,d2
                move.l  d2,d0
                rts

; sh_run_startup() : F1 — lit « s/startup-sequence » (sous-répertoire OFS du disque boot) via dos et exécute chaque ligne via
; sh_dispatch_line (mêmes builtins + chargement de commandes externes que l'interactif). Pas de startup-sequence ->
; rien (OK). Lignes vides et commentaires « ; » ignorés. Préserve tout (movem). Simplification F1 : fichier en
; RACINE (pas « s/ ») -> la traversée de sous-répertoires OFS est différée (déviation documentée, cf. strap.s).
sh_run_startup:
                movem.l d2-d7/a2-a6,-(sp)
                move.l  ($4).w,a6
                lea     sh_doslib(pc),a1
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq     .s_ret
                move.l  d0,a4                ; a4 = DosBase
                move.l  #SH_SCRIPTMAX,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .s_closelib
                move.l  d0,a5                ; a5 = buffer script
                move.l  a4,a6                ; a6 = DosBase
                move.l  #sh_startupname,d1
                move.l  #MODE_OLDFILE,d2
                jsr     DOS_LVO_OPEN(a6)     ; BPTR fh | 0 (0 = pas de startup-sequence)
                tst.l   d0
                beq     .s_free
                move.l  d0,d7                ; d7 = BPTR fh
                move.l  d7,d1
                move.l  a5,d2
                move.l  #SH_SCRIPTMAX,d3
                jsr     DOS_LVO_READ(a6)     ; d0 = octets lus
                move.l  d0,d5                ; d5 = taille script
                move.l  d7,d1
                jsr     DOS_LVO_CLOSE(a6)
                move.l  ($4).w,a6            ; SysBase
                tst.l   d5
                beq.s   .s_free
                ; a2 reste le StandardPacket (sh_write/sh_readline en dépendent !) -> pos/fin/DosBase en registres de DONNÉES.
                move.l  a5,d3
                add.l   d5,d3                ; d3 = fin du buffer (AVANT de réutiliser d5)
                move.l  a4,d5                ; d5 = DosBase (sûr à travers sh_dispatch_line)
                move.l  a5,d2                ; d2 = position courante (début)
.sl_loop:
                cmp.l   d3,d2
                bcc.s   .sl_done             ; pos >= fin
                move.l  d2,a3                ; a3 = début de ligne
                move.l  d2,a0                ; scan
.sl_scan:
                cmp.l   d3,a0
                bcc.s   .sl_eol
                move.b  (a0),d0
                cmp.b   #13,d0
                beq.s   .sl_eol
                cmp.b   #10,d0
                beq.s   .sl_eol
                addq.l  #1,a0
                bra.s   .sl_scan
.sl_eol:
                move.l  a0,d6
                sub.l   a3,d6                ; d6 = longueur de ligne (hors terminateur)
                move.l  a0,d2                ; pos = position du terminateur
                cmp.l   d3,d2
                bcc.s   .sl_check            ; fin atteinte, pas de terminateur à sauter
                move.l  d2,a0
                move.b  (a0),d0
                cmp.b   #13,d0
                bne.s   .sl_notcr
                addq.l  #1,d2                ; saute CR
                cmp.l   d3,d2
                bcc.s   .sl_check
                move.l  d2,a0
                move.b  (a0),d0
.sl_notcr:
                cmp.b   #10,d0
                bne.s   .sl_check
                addq.l  #1,d2                ; saute LF
.sl_check:
                tst.l   d6
                beq.s   .sl_loop             ; ligne vide
                move.b  (a3),d0
                cmp.b   #';',d0
                beq.s   .sl_loop             ; commentaire
                bsr     sh_dispatch_line     ; a2=StandardPacket intact, a3=ligne, d6=longueur
                bra.s   .sl_loop
.sl_done:
                move.l  d5,a4                ; restaure DosBase
.s_free:
                move.l  ($4).w,a6
                move.l  a5,a1
                move.l  #SH_SCRIPTMAX,d0
                jsr     LVO_FREEMEM(a6)
.s_closelib:
                move.l  ($4).w,a6
                move.l  a4,a1
                jsr     LVO_CLOSELIBRARY(a6)
.s_ret:
                movem.l (sp)+,d2-d7/a2-a6
                rts

sh_doslib:
                dc.b    "dos.library",0
sh_startupname:
                dc.b    "s/startup-sequence",0
                EVEN
                cnop    0,4                  ; BSTR passé en BPTR
sh_conname:
                dc.b    sh_conname_end-sh_conname-1,"CON:0/0/640/200/AmigaSlopDOS"
sh_conname_end:
                even
sh_banner:
                dc.b    "E2 SHELL READY (interactive shell: prompt, read line via console handler, parse, dispatch)",13,10,0
sh_crlf:
                dc.b    13,10
sh_prompt:
                dc.b    "> "
sh_prompt_end:
sh_prompt_len   EQU sh_prompt_end-sh_prompt
sh_vermsg:
                dc.b    "E2 SHELL ver OK (builtin dispatched from typed command line)",13,10
sh_vermsg_end:
sh_vermsg_len   EQU sh_vermsg_end-sh_vermsg
sh_unknown:
                dc.b    "?",13,10
sh_unknown_end:
sh_unknown_len  EQU sh_unknown_end-sh_unknown
sh_cmd_ver:
                dc.b    "ver",0
sh_cmd_echo:
                dc.b    "echo",0
                EVEN
