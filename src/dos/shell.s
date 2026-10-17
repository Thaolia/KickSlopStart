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
                bra     .unknown             ; RED E2 : pas de dispatch -> tout inconnu
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
                beq.s   .unknown
                ; args = ligne + SH_ECHO_ARGOFF, len = d6 - SH_ECHO_ARGOFF (si > 0)
                move.l  d6,d4
                sub.l   #SH_ECHO_ARGOFF,d4
                bls.s   .loop                ; « echo » sans args -> rien
                move.l  a3,a4
                add.l   #SH_ECHO_ARGOFF,a4
                bsr     sh_write
                bra     .loop
.unknown:
                move.l  #sh_unknown,a4
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
