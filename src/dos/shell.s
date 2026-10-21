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
                include "dos.i"

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
                move.l  DOS_CONPORT,PR_CONSOLETASK(a0)   ; « * » des process créés (Run : sortie du CLI de fond)
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
                bsr     sh_runscript
                bra.s   .loop

; sh_dispatch_line(a3 = ligne, d6 = longueur) : builtins ver/echo, sinon commande externe (sh_extern). Appelé par la
; boucle interactive ET par l'exécuteur de startup-sequence (F1). Clobbe d0/d1/d4 + a0/a1/a4 ; préserve d2/d3/d5/d6/d7
; + a2/a3/a5/a6.
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
                move.l  a3,a0                ; redirection hors guillemets : c:Echo (le builtin écrit sur la console)
                moveq   #0,d1
.dl_rscan:
                move.b  (a0)+,d0
                beq.s   .dl_rnone
                cmp.b   #'"',d0
                bne.s   .dl_rq
                not.b   d1
.dl_rq:
                tst.b   d1
                bne.s   .dl_rscan
                cmp.b   #'>',d0
                beq     .dl_extern
                cmp.b   #'<',d0
                beq     .dl_extern
                bra.s   .dl_rscan
.dl_rnone:
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
                bsr     sh_extern            ; -> d0 = 1 exécutée, 0 introuvable, -1 ligne vide
                tst.l   d0
                bne.s   .dl_ret2
                move.l  #sh_unknown,a4       ; non trouvée -> « ? »
                move.l  #sh_unknown_len,d4
                bsr     sh_write
.dl_ret2:
                rts

; sh_extern(a3 = ligne, d6 = longueur) -> d0 = 1 si la commande a été trouvée et exécutée, 0 si introuvable (a0 = son
; nom C-string, terminé en place), -1 pour une ligne vide ou un commentaire. Le 1er mot est le nom, le reste les
; arguments ; espaces de tête ignorés. Clobbe d1/a1 ; préserve d2-d7/a2-a6.
sh_extern:
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
                beq.s   .dl_empty
                cmp.b   #';',d0
                beq.s   .dl_empty
                cmp.b   #13,d0
                beq.s   .dl_empty
                cmp.b   #10,d0
                beq.s   .dl_empty
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
                move.l  (sp),a0              ; a0 = nom de commande C-string
                bsr     sh_exec_cmd          ; d0 = 1 si trouvée+chargée, 0 sinon
                move.l  (sp)+,a0
                rts
.dl_empty:
                moveq   #-1,d0
                rts

; sh_runscript() : tant que cli_CurrentInput n'est pas l'entrée standard (c:Execute y a mis un script), ses lignes sont
; lues et exécutées ; à sa fin il est fermé, son fichier temporaire supprimé et l'entrée standard reprise (FailLevel
; 10). Préserve tout.
sh_runscript:
                movem.l d0-d7/a0-a6,-(sp)
                lea     -(SHELL_LINEMAX+4)(sp),sp
.sr_lp:
                bsr     sh_cli_ptr
                beq.s   .sr_ret
                move.l  CLI_CURRENTINPUT(a1),d0
                cmp.l   CLI_STANDARDINPUT(a1),d0
                beq.s   .sr_ret
                move.l  sp,a3
                bsr     rcli_rdline          ; d6 = longueur, -1 = fin du script
                tst.l   d6
                bmi.s   .sr_eof
                clr.b   0(a3,d6.l)
                bsr     sh_extern
                tst.l   d0
                bne.s   .sr_lp
                bsr     rcli_unknown
                bra.s   .sr_lp
.sr_eof:
                bsr     sh_cli_ptr
                move.l  CLI_CURRENTINPUT(a1),d1
                move.l  CLI_STANDARDINPUT(a1),d0
                move.l  d0,CLI_CURRENTINPUT(a1)
                move.l  #10,CLI_FAILLEVEL(a1)
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a0
                move.l  d0,PR_CIS(a0)
                move.l  DOS_DOSBASE,a6
                jsr     DOS_LVO_CLOSE(a6)
                move.l  sp,a3
                bsr     rcli_delcmdfile
                bra.s   .sr_lp
.sr_ret:
                lea     SHELL_LINEMAX+4(sp),sp
                movem.l (sp)+,d0-d7/a0-a6
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
XF_FIN          EQU XF_RC+4          ; BPTR : fichier de « <nom » | 0
XF_FOUT         EQU XF_FIN+4         ; BPTR : fichier de « >nom » | 0
XF_RIN          EQU XF_FOUT+4        ; nom de « <nom » (SH_REDMAX, vide = pas de redirection)
SH_REDMAX       EQU 64
XF_ROUT         EQU XF_RIN+SH_REDMAX ; nom de « >nom »
XF_SIZE         EQU XF_ROUT+SH_REDMAX
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
                ; --- redirections : « <nom » (MODE_OLDFILE) et « >nom » (MODE_NEWFILE), ouvertes avant la commande ---
                clr.l   XF_FIN(sp)
                clr.l   XF_FOUT(sp)
                move.l  XF_DOS(sp),a6
                tst.b   XF_RIN(sp)
                beq.s   .x_nrin
                lea     XF_RIN(sp),a0
                move.l  a0,d1
                move.l  #MODE_OLDFILE,d2
                jsr     DOS_LVO_OPEN(a6)
                move.l  d0,XF_FIN(sp)
                bne.s   .x_nrin
                lea     XF_RIN(sp),a0        ; (Open a écrasé a0)
                bra.s   .x_rfail
.x_nrin:
                tst.b   XF_ROUT(sp)
                beq.s   .x_nrout
                lea     XF_ROUT(sp),a0
                move.l  a0,d1
                move.l  #MODE_NEWFILE,d2
                jsr     DOS_LVO_OPEN(a6)
                move.l  d0,XF_FOUT(sp)
                bne.s   .x_nrout
                lea     XF_ROUT(sp),a0
.x_rfail:
                bsr     sh_cantopen          ; « Can't open <nom> » : la commande n'est pas lancée
                bsr     sh_redclose
                moveq   #20,d0
                bsr     sh_cli_end
                bra     .x_unload
.x_nrout:
                ifeq    E3_NO_EXEC
                ifeq    PROD                 ; ROM de dev : la commande de preuve émet son marqueur sous Forbid (pas
                jsr     ser_lock             ; d'entrelacement avec les tâches démo) ; jamais en production, où le
                endc                         ; Forbid figerait le multitâche jusqu'au premier Wait de la commande
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
                move.l  XF_FIN(sp),d1        ; redirections : flux de la commande (arguments injectés dans « <nom »)
                beq.s   .x_rin
                move.l  d1,d0
                move.l  d1,PR_CIS(a2)
.x_rin:
                move.l  XF_FOUT(sp),d1
                beq.s   .x_rout
                move.l  d1,PR_COS(a2)
.x_rout:
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
                bsr     sh_redclose
                move.l  XF_STK(sp),a1
                move.l  XF_STKSZ(sp),d0
                move.l  ($4).w,a6
                jsr     LVO_FREEMEM(a6)
                move.l  XF_RC(sp),d0
                bra.s   .x_ran
.x_nostack:
                moveq   #-1,d0               ; pile impossible : code spécial « impossible de lancer »
.x_ran:
                bsr     sh_cli_end           ; cli_ReturnCode = d0, cli_Module = 0 ; d1 = module à décharger
                tst.l   d1
                bmi.s   .x_mod
                move.l  d1,XF_SEG(sp)        ; 0 : la commande est restée résidente
.x_mod:
                ifeq    PROD
                jsr     ser_unlock
                endc
                endc                         ; RED E3_NO_EXEC : saute le JSR -> commande chargée mais pas exécutée
.x_unload:
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

; sh_redclose() : ferme les fichiers de redirection de la commande (cadre XF de l'appelant, à 4(sp)). Préserve d0.
sh_redclose:
                movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  XF_DOS+24(sp),a6
                move.l  XF_FIN+24(sp),d1
                beq.s   .rc_out
                clr.l   XF_FIN+24(sp)
                jsr     DOS_LVO_CLOSE(a6)
.rc_out:
                move.l  XF_FOUT+24(sp),d1
                beq.s   .rc_ret
                clr.l   XF_FOUT+24(sp)
                jsr     DOS_LVO_CLOSE(a6)
.rc_ret:
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts

; sh_cantopen(a0 = nom) : « Can't open <nom> » sur la sortie courante. Préserve d0-d7/a2-a6.
sh_cantopen:
                movem.l d0-d3/a0-a2/a6,-(sp)
                move.l  a0,a2
                move.l  DOS_DOSBASE,a6
                move.l  ($4).w,a1
                move.l  EB_THISTASK(a1),a1
                move.l  PR_COS(a1),d1
                beq.s   .co_ret
                move.l  d1,-(sp)
                move.l  #sh_cantmsg,d2
                moveq   #sh_cantmsg_end-sh_cantmsg,d3
                jsr     DOS_LVO_WRITE(a6)
                move.l  (sp),d1
                move.l  a2,d2
                moveq   #0,d3
.co_len:
                tst.b   (a2)+
                beq.s   .co_w
                addq.l  #1,d3
                bra.s   .co_len
.co_w:
                jsr     DOS_LVO_WRITE(a6)
                move.l  (sp)+,d1
                move.l  #sh_crlf+1,d2
                moveq   #1,d3
                jsr     DOS_LVO_WRITE(a6)
.co_ret:
                movem.l (sp)+,d0-d3/a0-a2/a6
                rts

; sh_make_cli() : alloue une CommandLineInterface + ses BSTR (nom de commande, SetName, prompt, fichier de commandes) et la publie dans
; pr_CLI de ThisTask. Flux = pr_CIS/pr_COS, pile par défaut = SH_STK, FailLevel 10. Préserve tout.
SH_CLIBSTR      EQU 256              ; taille d'un buffer BSTR de la CLI
SH_ARGBUF       EQU CLI_SIZEOF+4*SH_CLIBSTR  ; tampon d'arguments injectés (aligné long : fh_Buf est un BPTR)
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
                add.l   #SH_CLIBSTR/4,d1
                move.l  d1,CLI_COMMANDFILE(a0)   ; tampon du nom de script temporaire d'Execute (écrit aussi par l'init de Run)
                sub.l   #SH_CLIBSTR/4,d1
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

; sh_cli_end(d0 = code retour de la commande) -> d1 = cli_Module tel que la commande l'a laissé (-1 sans CLI) :
; cli_ReturnCode = d0, puis cli_Module = 0. Une commande qui se rend résidente (SetPatch) met elle-même cli_Module à 0 :
; seule la seglist rendue ici doit être déchargée. Préserve tout sauf d1/a1.
sh_cli_end:
                move.l  d0,-(sp)
                moveq   #-1,d1
                bsr.s   sh_cli_ptr
                beq.s   .ce_ret
                move.l  (sp),CLI_RETURNCODE(a1)
                move.l  CLI_MODULE(a1),d1
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
; Copie jusqu'à CR/LF/NUL, retire les redirections (« >x », « <x », ou « > x », en début de mot hors guillemets : noms rangés dans
; XF_ROUT / XF_RIN du même cadre que la destination, qui est XF_ARGS) et le commentaire « ; » hors guillemets ; termine
; par '\n' puis NUL. Clobbe d0-d4/a0-a3.
sh_build_args:
                move.l  a1,a0
                move.l  a2,a1                ; a1 = XF_ARGS : les noms de redirection vont dans le même cadre
                clr.b   XF_RIN-XF_ARGS(a1)
                clr.b   XF_ROUT-XF_ARGS(a1)
                moveq   #0,d2                ; d2 = octets écrits
                moveq   #1,d3                ; d3 != 0 : début de mot
                moveq   #0,d4                ; bit0 = entre guillemets, bit1 = saute une redirection
.ba_lp:
                tst.l   d1
                ble     .ba_end
                move.b  (a0)+,d0
                subq.l  #1,d1
                cmp.b   #13,d0
                beq     .ba_end
                cmp.b   #10,d0
                beq     .ba_end
                tst.b   d0
                beq     .ba_end
                btst    #1,d4
                beq.s   .ba_noskip
                cmp.b   #' ',d0
                bne.s   .ba_rch
                cmp.l   #SH_REDMAX-1,d3
                bne.s   .ba_rend
                bra.s   .ba_lp               ; espaces entre « > » et le nom (« cmd > NIL: »)
.ba_rch:
                subq.l  #1,d3                ; d3 = place restante du nom
                bmi.s   .ba_lp
                move.b  d0,(a3)+
                bra.s   .ba_lp
.ba_rend:
                clr.b   (a3)
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
                lea     XF_ROUT-XF_ARGS(a1),a3
                cmp.b   #'>',d0
                beq.s   .ba_rto
                lea     XF_RIN-XF_ARGS(a1),a3
.ba_rto:
                bset    #1,d4
                moveq   #SH_REDMAX-1,d3
                bra     .ba_lp
.ba_plain:
                moveq   #0,d3
                cmp.b   #' ',d0
                bne.s   .ba_put
                moveq   #1,d3
.ba_put:
                cmp.l   #SH_ARGMAX-2,d2
                bhs     .ba_lp               ; plein : le reste est ignoré
                move.b  d0,(a2)+
                addq.l  #1,d2
                bra     .ba_lp
.ba_end:
                btst    #1,d4
                beq.s   .ba_nred
                clr.b   (a3)                 ; redirection en fin de ligne
.ba_nred:
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
                bsr     sh_runscript         ; Execute a pu basculer l'entrée du CLI sur un script
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
sh_cantmsg:
                dc.b    "Can't open "
sh_cantmsg_end:
sh_cmd_ver:
                dc.b    "ver",0
sh_cmd_echo:
                dc.b    "echo",0
                EVEN

; ============================== CLI ROM (segment BCPL de rn_ConsoleSegment) ==============================
; Run (et Execute) utilisent ce segment comme entrée 4 du segarray d'un CLI de fond quand aucun résident « CLI »
; n'existe (spec bcpl-runtime §9.2 / §13.5). La globin y installe la globale 1 = rcli_start, appelée par le
; démarrage du process (bcpl_proc_entry) avec le packet de démarrage : la routine d'init du packet (dp_Type) remplit
; la CLI (flux, répertoire courant, pile...) ; si elle rend une routine (> 0), celle-ci est appelée avec pr_Result2
; (réponse immédiate au créateur) ; sinon le packet est rendu à la fin du CLI. Le CLI lit ensuite ses commandes dans
; cli_CurrentInput (FileHandle mémoire de Run, ou script d'Execute), les exécute par sh_extern et se termine à l'EOF
; de son entrée standard.
                cnop    0,4
                xdef    rcli_seg
rcli_seg:
                dc.l    0                    ; lien (BPTR du segment suivant)
rcli_data:
                dc.l    (rcli_end-rcli_data)/4   ; taille du segment en longs
RC_LINE         EQU 0                ; ligne lue (SHELL_LINEMAX + NUL)
RC_PKT          EQU SHELL_LINEMAX+4  ; BPTR du packet de démarrage
RC_R            EQU RC_PKT+4         ; résultat d'init : > 0 routine (Run), < 0 drapeaux (Execute), 0 sans packet
RC_OUT          EQU RC_R+4           ; sortie standard posée par init (resélectionnée à chaque tour)
RC_SIZE         EQU RC_OUT+4
RC_FRAME        EQU 64               ; taille de frame annoncée aux appels BCPL (la CLI n'est pas dans le frame)
rcli_start:
                lea     -RC_SIZE(sp),sp
                move.l  d1,RC_PKT(sp)
                clr.l   RC_R(sp)
                bsr     rcli_mkcli           ; pr_CLI posé AVANT init : elle la trouve par findcli()
                beq     rcli_exit
                move.l  RC_PKT(sp),d0
                lsl.l   #2,d0
                beq.s   .rs_set              ; sans packet : rien à initialiser
                move.l  d0,a0
                move.l  DP_TYPE(a0),a4       ; init(pkt) en BCPL : A4 = son adresse exacte, D1 = packet
                move.l  RC_PKT(sp),d1
                sub.l   a0,a0                ; A0 = 0 : base des accès mémoire BCPL (BPTR x 4)
                moveq   #RC_FRAME,d0
                jsr     (a5)
                move.l  d1,RC_R(sp)
                ble.s   .rs_set
                move.l  d1,a4                ; r > 0 (Run : qpkt) : r(pr_Result2) rend le packet tout de suite
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a0
                move.l  PR_RESULT2(a0),d1
                sub.l   a0,a0
                moveq   #RC_FRAME,d0
                jsr     (a5)
.rs_set:                                     ; dès ici, plus d'appel BCPL : le CLI finit par RemTask
                bsr     sh_cli_ptr
                move.l  CLI_STANDARDOUTPUT(a1),RC_OUT(sp)
                moveq   #0,d0                ; interactif = non Background et entrée standard = entrée courante
                tst.l   CLI_BACKGROUND(a1)
                bne.s   .rs_ni
                move.l  CLI_STANDARDINPUT(a1),d1
                cmp.l   CLI_CURRENTINPUT(a1),d1
                bne.s   .rs_ni
                moveq   #-1,d0
.rs_ni:
                move.l  d0,CLI_INTERACTIVE(a1)
.rs_loop:
                move.l  RC_OUT(sp),d0
                bsr     rcli_selio
                lea     RC_LINE(sp),a3
                bsr     rcli_prompt
                bsr     rcli_rdline          ; d6 = longueur, -1 = EOF sans donnée
                tst.l   d6
                bmi.s   .rs_eof
                clr.b   0(a3,d6.l)
                bsr     sh_extern
                tst.l   d0
                bne.s   .rs_loop
                bsr     rcli_unknown         ; « <nom>: Unknown command »
                bra.s   .rs_loop
.rs_eof:
                bsr     sh_cli_ptr
                move.l  CLI_CURRENTINPUT(a1),d1
                cmp.l   CLI_STANDARDINPUT(a1),d1
                beq.s   .rs_top
                move.l  CLI_STANDARDINPUT(a1),CLI_CURRENTINPUT(a1)  ; fin d'un script : retour à l'entrée standard
                move.l  #10,CLI_FAILLEVEL(a1)
                moveq   #0,d0                ; de nouveau interactif s'il n'est pas en arrière-plan (NewCLI après
                tst.l   CLI_BACKGROUND(a1)   ; s:cli-startup : invite à partir d'ici)
                bne.s   .rs_bg
                moveq   #-1,d0
.rs_bg:
                move.l  d0,CLI_INTERACTIVE(a1)
                move.l  DOS_DOSBASE,a6
                jsr     DOS_LVO_CLOSE(a6)
                bsr     rcli_delcmdfile
                bra.s   .rs_loop
.rs_top:
                tst.l   CLI_BACKGROUND(a1)
                beq.s   .rs_loop             ; CLI interactif : la console reste ouverte, on relit
                move.l  DOS_DOSBASE,a6
                move.l  RC_R(sp),d0
                bpl.s   .rs_runend
                btst    #1,d0                ; Execute : entrée fournie par l'appelant -> pas fermée
                bne.s   .rs_nord
                move.l  CLI_STANDARDINPUT(a1),d1
                jsr     DOS_LVO_CLOSE(a6)
.rs_nord:
                btst    #0,RC_R+3(sp)        ; sortie ouverte par init -> fermée
                beq.s   .rs_nwr
                move.l  RC_OUT(sp),d1
                jsr     DOS_LVO_CLOSE(a6)
.rs_nwr:
                move.l  RC_PKT(sp),d0        ; returnpkt : l'appelant d'Execute() repart maintenant
                lsl.l   #2,d0
                beq.s   .rs_free
                move.l  d0,a0
                clr.l   DP_RES1(a0)
                bsr     sh_cli_ptr
                move.l  CLI_RESULT2(a1),DP_RES2(a0)
                move.l  DP_PORT(a0),a2
                move.l  ($4).w,a6
                move.l  EB_THISTASK(a6),a3
                lea     PR_MSGPORT(a3),a3
                move.l  a3,DP_PORT(a0)
                move.l  DP_LINK(a0),a1
                move.l  a2,a0
                jsr     LVO_PUTMSG(a6)
                bra.s   .rs_free
.rs_runend:                                  ; Run : flux de commandes et sortie fermés
                move.l  CLI_STANDARDINPUT(a1),d1
                jsr     DOS_LVO_CLOSE(a6)
                move.l  RC_OUT(sp),d1
                jsr     DOS_LVO_CLOSE(a6)
.rs_free:
                bsr     rcli_free
rcli_exit:
                move.l  ($4).w,a6
                sub.l   a1,a1
                jsr     LVO_REMTASK(a6)      ; ne revient pas
.rx_hang:
                bra.s   .rx_hang

; rcli_mkcli() : CLI effacée avec ses quatre tampons BSTR (nom de commande, SetName, prompt, fichier de commandes),
; publiée dans pr_CLI ; la routine d'init du packet la remplit (flux, réglages du CLI parent). Z = 1 si la mémoire
; manque. Préserve tout sauf d0.
rcli_mkcli:
                movem.l d1/a0-a1/a6,-(sp)
                move.l  ($4).w,a6
                move.l  #SH_CLIALLOC,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .rm_ret
                move.l  d0,a0
                lea     CLI_SIZEOF(a0),a1
                move.l  a1,d1
                lsr.l   #2,d1
                move.l  d1,CLI_COMMANDNAME(a0)
                add.l   #SH_CLIBSTR/4,d1
                move.l  d1,CLI_SETNAME(a0)
                add.l   #SH_CLIBSTR/4,d1
                move.l  d1,CLI_PROMPT(a0)
                add.l   #SH_CLIBSTR/4,d1
                move.l  d1,CLI_COMMANDFILE(a0)
                move.l  #10,CLI_FAILLEVEL(a0)
                move.l  #SH_DEFSTACK,CLI_DEFAULTSTACK(a0)
                move.l  EB_THISTASK(a6),a1
                lsr.l   #2,d0
                move.l  d0,PR_CLI(a1)        ; Z = 0
.rm_ret:
                movem.l (sp)+,d1/a0-a1/a6
                rts

; rcli_selio(d0 = sortie mémorisée) : avant chaque lecture, selectinput(cli_CurrentInput) et selectoutput(d0, si non
; nulle). Préserve tout.
rcli_selio:
                movem.l d0/a0-a1,-(sp)
                bsr     sh_cli_ptr
                beq.s   .si_ret
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a0
                move.l  CLI_CURRENTINPUT(a1),PR_CIS(a0)
                tst.l   d0
                beq.s   .si_ret
                move.l  d0,PR_COS(a0)
.si_ret:
                movem.l (sp)+,d0/a0-a1
                rts

; rcli_prompt(a3 = tampon) : CLI interactif lisant son entrée standard -> invite (BSTR cli_Prompt, « %N » = n° du CLI)
; sur la sortie courante. Préserve d2-d7/a2-a6.
rcli_prompt:
                movem.l d2-d4/a2/a6,-(sp)
                bsr     sh_cli_ptr
                beq     .pp_ret
                tst.l   CLI_INTERACTIVE(a1)
                beq.s   .pp_ret
                move.l  CLI_CURRENTINPUT(a1),d0
                cmp.l   CLI_STANDARDINPUT(a1),d0
                bne.s   .pp_ret
                move.l  CLI_PROMPT(a1),d0
                lsl.l   #2,d0
                beq.s   .pp_ret
                move.l  d0,a0
                moveq   #0,d2
                move.b  (a0)+,d2             ; d2 = longueur
                move.l  a3,a2                ; a2 = texte formaté
                bra.s   .pp_nx
.pp_ch:
                move.b  (a0)+,d0
                cmp.b   #'%',d0
                bne.s   .pp_put
                tst.w   d2
                beq.s   .pp_put
                cmp.b   #'N',(a0)
                bne.s   .pp_put
                addq.l  #1,a0
                subq.w  #1,d2
                move.l  ($4).w,a1
                move.l  EB_THISTASK(a1),a1
                move.l  PR_TASKNUM(a1),d0
                bsr     rcli_putdec
                bra.s   .pp_nx
.pp_put:
                move.b  d0,(a2)+
.pp_nx:
                dbra    d2,.pp_ch
                move.l  a3,d2
                move.l  a2,d3
                sub.l   a3,d3
                beq.s   .pp_ret
                move.l  ($4).w,a1
                move.l  EB_THISTASK(a1),a1
                move.l  PR_COS(a1),d1
                beq.s   .pp_ret
                move.l  DOS_DOSBASE,a6
                jsr     DOS_LVO_WRITE(a6)
.pp_ret:
                movem.l (sp)+,d2-d4/a2/a6
                rts
; rcli_putdec(d0 = entier >= 0, a2 = destination) : chiffres décimaux, a2 avancé. Clobbe d0/d1/d4.
rcli_putdec:
                moveq   #0,d4                ; chiffres empilés
.pd_div:
                divu    #10,d0
                swap    d0
                move.w  d0,-(sp)
                clr.w   d0
                swap    d0
                addq.w  #1,d4
                tst.l   d0
                bne.s   .pd_div
.pd_out:
                move.w  (sp)+,d1
                add.b   #'0',d1
                move.b  d1,(a2)+
                subq.w  #1,d4
                bne.s   .pd_out
                rts

; rcli_rdline(a3 = tampon) -> d6 = longueur de la ligne (sans le '\n'), -1 si l'entrée est épuisée sans donnée.
; Caractère par caractère sur cli_CurrentInput : d'abord son tampon (fh_Buf[fh_Pos..fh_End-1], comme rdch), puis,
; s'il a un handler, Read d'un octet ; sinon EOF. Tronquée à SHELL_LINEMAX. Préserve d2-d5/d7/a2-a6.
rcli_rdline:
                movem.l d2-d3/a2/a6,-(sp)
                moveq   #0,d6
.rl_ch:
                bsr     sh_cli_ptr
                beq.s   .rl_eof
                move.l  CLI_CURRENTINPUT(a1),d0
                lsl.l   #2,d0
                beq.s   .rl_eof
                move.l  d0,a2                ; a2 = FileHandle
                move.l  FH_POS(a2),d0
                cmp.l   FH_END(a2),d0
                bge.s   .rl_hnd
                move.l  FH_BUF(a2),d1
                lsl.l   #2,d1
                move.l  d1,a0
                move.b  0(a0,d0.l),d2
                addq.l  #1,FH_POS(a2)
                bra.s   .rl_got
.rl_hnd:
                tst.l   FH_TYPE(a2)
                beq.s   .rl_eof
                move.l  a2,d1
                lsr.l   #2,d1
                clr.w   -(sp)
                move.l  sp,d2
                moveq   #1,d3
                move.l  DOS_DOSBASE,a6
                jsr     DOS_LVO_READ(a6)
                move.b  (sp),d2
                addq.l  #2,sp
                cmp.l   #1,d0
                bne.s   .rl_eofd
.rl_got:
                cmp.b   #10,d2
                beq.s   .rl_ret
                cmp.w   #SHELL_LINEMAX,d6
                bhs.s   .rl_ch               ; ligne trop longue : la suite est ignorée
                move.b  d2,0(a3,d6.l)
                addq.l  #1,d6
                bra.s   .rl_ch
.rl_eofd:
                tst.l   d6                   ; EOF après des caractères : dernière ligne sans '\n'
                bne.s   .rl_ret
.rl_eof:
                tst.l   d6
                bne.s   .rl_ret
                moveq   #-1,d6
.rl_ret:
                movem.l (sp)+,d2-d3/a2/a6
                rts

; rcli_unknown(a0 = nom) : « <nom>: Unknown command » sur la sortie courante. Préserve d6/d7/a3.
rcli_unknown:
                movem.l d2-d3/a2/a6,-(sp)
                move.l  a0,a2
                move.l  a0,d2
                moveq   #0,d3
.un_len:
                tst.b   (a2)+
                beq.s   .un_go
                addq.l  #1,d3
                bra.s   .un_len
.un_go:
                move.l  DOS_DOSBASE,a6
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a0
                move.l  PR_COS(a0),d1
                beq.s   .un_ret
                move.l  d1,-(sp)
                jsr     DOS_LVO_WRITE(a6)
                move.l  (sp)+,d1
                move.l  #rcli_unkmsg,d2
                moveq   #rcli_unkmsg_end-rcli_unkmsg,d3
                jsr     DOS_LVO_WRITE(a6)
.un_ret:
                movem.l (sp)+,d2-d3/a2/a6
                rts

; rcli_delcmdfile(a3 = tampon) : le fichier de commandes temporaire d'Execute (cli_CommandFile) est supprimé et le
; nom vidé. Préserve d6/d7/a3.
rcli_delcmdfile:
                bsr     sh_cli_ptr
                beq.s   .dc_ret
                move.l  CLI_COMMANDFILE(a1),d0
                lsl.l   #2,d0
                beq.s   .dc_ret
                move.l  d0,a0
                moveq   #0,d0
                move.b  (a0),d0
                beq.s   .dc_ret
                clr.b   (a0)+
                move.l  a3,a1
                bra.s   .dc_nx
.dc_cp:
                move.b  (a0)+,(a1)+
.dc_nx:
                dbra    d0,.dc_cp
                clr.b   (a1)
                move.l  a3,d1
                move.l  DOS_DOSBASE,a6
                jsr     DOS_LVO_DELETEFILE(a6)
.dc_ret:
                rts

; rcli_free() : fin du CLI : répertoire courant rendu, liste de chemins (cli_CommandDir : nœuds getvec [suivant, lock])
; rendue, slot de rn_TaskArray libéré, CLI rendue.
rcli_free:
                move.l  DOS_DOSBASE,a6
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a3   ; a3 = process
                move.l  PR_CURRENTDIR(a3),d1
                beq.s   .fr_path
                clr.l   PR_CURRENTDIR(a3)
                jsr     DOS_LVO_UNLOCK(a6)
.fr_path:
                bsr     sh_cli_ptr
                beq.s   .fr_slot
                move.l  CLI_COMMANDDIR(a1),d2
                clr.l   CLI_COMMANDDIR(a1)
.fr_node:
                lsl.l   #2,d2
                beq.s   .fr_slot
                move.l  d2,a2                ; a2 = nœud
                move.l  4(a2),d1
                beq.s   .fr_nolk
                move.l  DOS_DOSBASE,a6
                jsr     DOS_LVO_UNLOCK(a6)
.fr_nolk:
                move.l  (a2),d2              ; suivant (BPTR)
                lea     -4(a2),a1            ; freevec : taille dans l'en-tête getvec
                move.l  (a1),d0
                move.l  ($4).w,a6
                jsr     LVO_FREEMEM(a6)
                bra.s   .fr_node
.fr_slot:
                move.l  ($4).w,a6
                jsr     LVO_FORBID(a6)
                move.l  DOS_DOSBASE,a0
                move.l  DL_ROOT(a0),a0
                move.l  RN_TASKARRAY(a0),d0
                lsl.l   #2,d0
                beq.s   .fr_perm
                move.l  d0,a0
                move.l  PR_TASKNUM(a3),d0
                beq.s   .fr_perm
                cmp.l   (a0),d0
                bhi.s   .fr_perm
                lsl.l   #2,d0
                clr.l   0(a0,d0.l)
.fr_perm:
                jsr     LVO_PERMIT(a6)
                move.l  PR_CLI(a3),d0
                lsl.l   #2,d0
                beq.s   .fr_ret
                clr.l   PR_CLI(a3)
                move.l  d0,a1
                move.l  #SH_CLIALLOC,d0
                jsr     LVO_FREEMEM(a6)
.fr_ret:
                rts
rcli_unkmsg:
                dc.b    ": Unknown command",10
rcli_unkmsg_end:
                cnop    0,4
                dc.l    0                    ; fin de la table de globin
                dc.l    1,rcli_start-rcli_data   ; globale 1 = start
                dc.l    1                    ; plus grande globale définie
rcli_end:
