; src/dos/shell.s — shell interactif minimal (E2). Corps d'un Process : ouvre la console (handler E1 via DOS
; packets vers DOS_CONPORT), émet une bannière, puis boucle : écrit l'invite, lit UNE LIGNE, parse le 1er mot,
; dispatche vers un builtin. Builtins : « ver » (bannière de version) et « echo <args> » (ré-émet les args) ;
; tout le reste -> « ? ». PAS de CLI BCPL (pr_CLI/CommandLineInterface/Execute = Bootstrap réel F).
;
; Tout l'IO passe par des FileHandles DOS (ici la clé renvoyée par FINDINPUT) vers le handler console — jamais
; directement sur SERDAT. En F on remplacera le handler par un console.device sans toucher à CE binaire shell.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs dos (Open/Read/Write) + spec analyse packets. AUCUNE lecture ROM.

                include "exec.i"
                include "dospkt.i"

                xdef    shell_main
                xref    dos_sendpkt
                xref    ls_load_hunks        ; dos/loadseg.s (E3 : parse hunk d'un buffer lu via dos)
                xref    dos_unloadseg        ; dos/loadseg.s (E3 : libérer la seglist)

SH_CMDBUF       EQU 16384            ; buffer de chargement d'une commande externe (E3)
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
                moveq   #0,d3
                jsr     dos_sendpkt
                move.l  d0,d7                ; d7 = clé
                ; bannière (prouve : l'Initial CLI démarre + console WRITE)
                move.l  #sh_banner,a4
                move.l  #sh_banner_len,d4
                bsr     sh_write
                ifeq    F1_NO_STARTUP
                bsr     sh_run_startup       ; F1 : exécuter s:startup-sequence (racine) AVANT l'interactif
                endc                         ; RED F1_NO_STARTUP : saute le script -> directement interactif
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
                bsr     sh_write
.dl_ret:
                rts
.dl_extern:
                ; commande inconnue -> charger+exécuter depuis DF0: via dos. null-terminer le 1er mot en place.
                move.l  a3,a0
.dl_nt:
                move.b  (a0),d0
                beq.s   .dl_nt_done
                cmp.b   #' ',d0
                beq.s   .dl_nt_cut
                cmp.b   #13,d0
                beq.s   .dl_nt_cut
                cmp.b   #10,d0               ; LF (ligne de script) aussi = frontière
                beq.s   .dl_nt_cut
                addq.l  #1,a0
                bra.s   .dl_nt
.dl_nt_cut:
                clr.b   (a0)                 ; termine le nom en C-string
.dl_nt_done:
                move.l  a3,a0                ; a0 = nom de commande C-string
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

; sh_exec_cmd(a0 = nom C-string) : charge+exécute une commande depuis DF0: via dos (comme D3d) ->
;   d0 = 1 si trouvée + chargée (exécutée en GREEN), 0 si introuvable/non chargeable. Préserve tout le
;   contexte shell (movem d2-d7/a2-a6). a6 restauré à SysBase en sortie. Drapeau « trouvée » sur la PILE
;   (survit aux appels et au JSR de la commande, qui pourrait clobber un registre).
sh_exec_cmd:
                movem.l d2-d7/a2-a6,-(sp)
                clr.l   -(sp)                ; [sp] = drapeau « trouvée » = 0
                move.l  a0,d5                ; d5 = nom
                move.l  ($4).w,a6            ; SysBase
                lea     sh_doslib(pc),a1
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq     .x_ret
                move.l  d0,a4                ; a4 = DosBase
                move.l  #SH_CMDBUF,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .x_closelib
                move.l  d0,a5                ; a5 = filebuf
                move.l  a4,a6                ; a6 = DosBase
                move.l  d5,d1                ; nom
                move.l  #MODE_OLDFILE,d2
                jsr     DOS_LVO_OPEN(a6)     ; BPTR fh | 0 (0 = introuvable)
                tst.l   d0
                beq     .x_free
                move.l  d0,d7                ; d7 = BPTR fh
                move.l  d7,d1
                move.l  a5,d2
                move.l  #SH_CMDBUF,d3
                jsr     DOS_LVO_READ(a6)     ; d0 = octets lus
                move.l  d0,d6                ; d6 = taille
                move.l  d7,d1
                jsr     DOS_LVO_CLOSE(a6)
                move.l  ($4).w,a6            ; SysBase
                tst.l   d6
                beq.s   .x_free              ; rien lu
                move.l  a5,a0
                move.l  d6,d0
                jsr     ls_load_hunks        ; d0 = BPTR seglist | 0
                tst.l   d0
                beq.s   .x_free
                move.l  d0,d7                ; d7 = BPTR seglist
                move.l  #1,(sp)              ; TROUVÉE + chargée (drapeau pile)
                ifeq    E3_NO_EXEC
                move.l  d7,d0                ; entry = (seglist<<2)+4
                lsl.l   #2,d0
                addq.l  #4,d0
                move.l  d0,a0
                jsr     (a0)                 ; exécute la commande tapée
                move.l  ($4).w,a6            ; recharge SysBase (le code a pu clobber a6)
                endc                         ; RED E3_NO_EXEC : saute le JSR -> commande chargée mais pas exécutée
                move.l  d7,d0
                jsr     dos_unloadseg
.x_free:
                move.l  ($4).w,a6
                move.l  a5,a1
                move.l  #SH_CMDBUF,d0
                jsr     LVO_FREEMEM(a6)
.x_closelib:
                move.l  ($4).w,a6
                move.l  a4,a1
                jsr     LVO_CLOSELIBRARY(a6)
.x_ret:
                move.l  (sp)+,d0             ; dépile le drapeau trouvée -> d0 (survit au movem)
                movem.l (sp)+,d2-d7/a2-a6
                rts

; sh_run_startup() : F1 — lit « startup-sequence » (racine du disque boot) via dos et exécute chaque ligne via
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
                dc.b    "startup-sequence",0
                EVEN
sh_banner:
                dc.b    "E2 SHELL READY (interactive shell: prompt, read line via console handler, parse, dispatch)",13,10
sh_banner_end:
sh_banner_len   EQU sh_banner_end-sh_banner
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
