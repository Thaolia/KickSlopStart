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
                ; bannière (prouve : le shell démarre + console WRITE)
                move.l  #sh_banner,a4
                move.l  #sh_banner_len,d4
                bsr     sh_write
.loop:
                move.l  #sh_prompt,a4        ; invite « > »
                move.l  #sh_prompt_len,d4
                bsr     sh_write
                bsr     sh_readline          ; -> d6 = octets, ligne en (a3)
                ifne    E2_NO_DISPATCH
                bra     .extern              ; RED E2 : pas de dispatch builtin -> traité comme commande externe
                endc
                lea     sh_cmd_ver(pc),a0    ; « ver » ?
                move.l  a3,a1
                bsr     sh_match
                tst.l   d0
                beq.s   .not_ver
                move.l  #sh_vermsg,a4
                move.l  #sh_vermsg_len,d4
                bsr     sh_write
                bra     .loop
.not_ver:
                lea     sh_cmd_echo(pc),a0   ; « echo <args> » ?
                move.l  a3,a1
                bsr     sh_match
                tst.l   d0
                beq.s   .extern
                ; args = ligne + SH_ECHO_ARGOFF, len = d6 - SH_ECHO_ARGOFF (si > 0)
                move.l  d6,d4
                sub.l   #SH_ECHO_ARGOFF,d4
                bls.s   .loop                ; « echo » sans args -> rien
                move.l  a3,a4
                add.l   #SH_ECHO_ARGOFF,a4
                bsr     sh_write
                bra     .loop
.extern:
                ; E3 : commande inconnue -> tenter de la charger+exécuter depuis DF0: via dos.
                ; null-terminer le 1er mot de la ligne en place (frontière espace/CR).
                move.l  a3,a0
.nt_lp:
                move.b  (a0),d0
                beq.s   .nt_done
                cmp.b   #' ',d0
                beq.s   .nt_cut
                cmp.b   #13,d0
                beq.s   .nt_cut
                addq.l  #1,a0
                bra.s   .nt_lp
.nt_cut:
                clr.b   (a0)                 ; termine le nom en C-string
.nt_done:
                move.l  a3,a0                ; a0 = nom de commande C-string
                bsr     sh_exec_cmd          ; d0 = 1 si trouvée+chargée, 0 sinon
                tst.l   d0
                bne     .loop                ; trouvée (exécutée, ou chargée si RED E3) -> retour au prompt
                move.l  #sh_unknown,a4       ; non trouvée -> « ? »
                move.l  #sh_unknown_len,d4
                bsr     sh_write
                bra     .loop

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

sh_doslib:
                dc.b    "dos.library",0
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
