; src/dos/shell.s - minimal interactive shell (E2). Body of a Process: opens the console "CON:0/0/640/200/
; AmigaSlopDOS" (E1 handler via DOS packets to DOS_CONPORT: window on the Workbench screen + serial mirror), emits a
; test banner on serial, runs the startup-sequence (window closed if EndCLI has moved the CLI to the background),
; then loops: writes the prompt, reads ONE LINE, parses the 1st word, dispatches to a builtin. Builtins: "ver"
; (version banner) and "echo <args>" (like c:Echo: without enclosing quotes, then a newline);
; everything else -> "?". NO BCPL CLI (pr_CLI/CommandLineInterface/Execute = real Bootstrap F).
;
; All IO goes through DOS FileHandles (here the key returned by FINDINPUT) to the console handler - never
; directly to SERDAT. In F the handler will be replaced by a console.device without touching THIS shell binary.
; IMPLEMENTATION track ("clean"): dos AutoDocs (Open/Read/Write) + packets analysis spec. NO ROM reading.

                include "exec.i"
                include "dospkt.i"
                include "dos.i"

                xdef    shell_main
                xref    ser_puts             ; exec/boot.s (test banner on serial)
                xref    dos_sendpkt
                xref    dos_unloadseg        ; dos/loadseg.s (E3: free the seglist)
                xref    ser_lock             ; exec/boot.s (atomic serial output)
                xref    ser_unlock
                xref    dos_boot_assigns     ; dos/dos_lib.s (assigns + volume + current directory)
                xref    bcpl_call            ; dos/bcpl.s (A5/A6 of BCPL commands)
                xref    bcpl_ret
                xref    rt_fault             ; bcpl.s: text of a dos error (C:FAULT)
                xref    bcpl_cli_setup
                xref    bcpl_cli_register

SH_SCRIPTMAX    EQU 2048             ; max size of the startup-sequence read (F1)

SHELL_LINEMAX   EQU 128              ; max size of a line read
SH_ECHO_ARGOFF  EQU 5                ; offset of the args after "echo" + 1 space

; shell_main: process body. GPRs at zero on entry (AddTask frame) -> reload SysBase.
; a2 = StandardPacket (stack), a3 = line buffer (stack), d7 = console key, d6 = bytes read.
shell_main:
                move.l  ($4).w,a6
                lea     -(SP_SIZEOF+SHELL_LINEMAX)(sp),sp
                move.l  sp,a2                ; a2 = StandardPacket
                lea     SP_SIZEOF(sp),a3     ; a3 = line buffer
                ; open the console
                move.l  DOS_CONPORT,a1
                move.l  a2,a0
                move.l  #ACTION_FINDINPUT,d0
                moveq   #0,d1
                moveq   #0,d2
                move.l  #sh_conname,d3       ; "CON:0/0/640/200/AmigaSlopDOS": window of the initial console
                lsr.l   #2,d3
                jsr     dos_sendpkt
                move.l  d0,d7                ; d7 = key
                ; console FileHandle -> pr_CIS/pr_COS: Input()/Output() of launched commands write to the console
                move.l  #DOS_FH_ALLOC+4,d0   ; same block as Open (getvec [size][FileHandle+private]): buffered output
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq.s   .nofh
                move.l  d0,a0
                move.l  #DOS_FH_ALLOC+4,(a0)+
                move.l  a0,d0
                move.l  DOS_CONPORT,FH_TYPE(a0)
                move.l  d7,FH_ARG1(a0)
                move.l  #DOSTRUE,FH_INTERACTIVE(a0)
                moveq   #-1,d1
                move.l  d1,FH_POS(a0)        ; fh_Pos = fh_End = -1: buffer empty, the 1st BCPL read fills it
                move.l  d1,FH_END(a0)
                lsr.l   #2,d0
                move.l  EB_THISTASK(a6),a0
                move.l  d0,PR_CIS(a0)
                move.l  d0,PR_COS(a0)
                move.l  DOS_CONPORT,PR_CONSOLETASK(a0)   ; "*" of created processes (Run: output of the background CLI)
.nofh:
                bsr     sh_make_cli          ; pr_CLI: without it commands believe they were launched by the Workbench
                lea     sh_doslib(pc),a1     ; assigns SYS: C: S: L: ... + current directory = root of the disk
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq.s   .noassign
                move.l  d0,a6
                jsr     dos_boot_assigns
                bsr     sh_sysconfig         ; Preferences from the disk (DEVS: has just been assigned)
                move.l  a6,a1
                move.l  ($4).w,a6
                jsr     LVO_CLOSELIBRARY(a6)
.noassign:
                ; test banner (harness serial marker: the Initial CLI starts; not in the window)
                lea     sh_banner(pc),a0
                jsr     ser_puts
                ifeq    F1_NO_STARTUP
                bsr     sh_run_startup       ; F1: run s/startup-sequence (OFS subdir) BEFORE the interactive loop
                endc                         ; RED F1_NO_STARTUP: skips the script -> straight to interactive
                bsr     sh_cli_ptr           ; EndCLI has moved the CLI to the background: its window closes (END);
                beq.s   .loop                ; the fallback prompt continues on serial
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
                move.l  #sh_prompt,a4        ; prompt ">"
                move.l  #sh_prompt_len,d4
                bsr     sh_write
                bsr     sh_readline          ; -> d6 = bytes, line in (a3)
                bsr     sh_dispatch_line     ; parse the 1st word -> builtin / external command
                moveq   #-1,d1               ; interactive: possible message, never aborts
                bsr     sh_report
                bsr     sh_runscript
                bra.s   .loop

; sh_dispatch_line(a3 = line, d6 = length): builtins ver/echo, otherwise external command (sh_extern). Called by the
; interactive loop AND by the startup-sequence executor (F1). -> d0/a0 as sh_extern (builtin: d0 = -1).
; Clobbers d0/d1/d4 + a0/a1/a4; preserves d2/d3/d5/d6/d7 + a2/a3/a5/a6.
sh_dispatch_line:
                ifne    E2_NO_DISPATCH
                bra     .dl_extern           ; RED E2: no builtin dispatch -> external command
                endc
                lea     sh_cmd_ver(pc),a0    ; "ver"?
                move.l  a3,a1
                bsr     sh_match
                tst.l   d0
                beq.s   .dl_not_ver
                move.l  #sh_vermsg,a4
                move.l  #sh_vermsg_len,d4
                bsr     sh_write
                moveq   #-1,d0
                rts
.dl_not_ver:
                move.l  a3,a0                ; redirection outside quotes: c:Echo (the builtin writes to the console)
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
                lea     sh_cmd_echo(pc),a0   ; "echo <args>"?
                move.l  a3,a1
                bsr     sh_match
                tst.l   d0
                beq.s   .dl_extern
                move.l  d6,d4                ; args = line + SH_ECHO_ARGOFF, len = length - SH_ECHO_ARGOFF
                sub.l   #SH_ECHO_ARGOFF,d4
                bls.s   .dl_ret              ; "echo" without args
                move.l  a3,a4
                add.l   #SH_ECHO_ARGOFF,a4
.dl_etrim:                           ; like c:Echo: without line ending or enclosing quotes, then a newline
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
                moveq   #-1,d0
                rts
.dl_extern:
                bra     sh_extern

; sh_extern(a3 = line, d6 = length) -> d0 = 1 if the command was found and executed, 0 if not found, 2 if its
; file is not loadable (pr_Result2 = error code) - a0 = its name as a C string, terminated in place -, -1 for an
; empty line or a comment. The 1st word is the name, the rest the
; arguments; leading spaces ignored. Clobbers d1/a1; preserves d2-d7/a2-a6.
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
                move.l  a0,-(sp)             ; start of the command name
.dl_nt:
                move.b  (a0),d0
                beq.s   .dl_noargs
                cmp.b   #' ',d0
                beq.s   .dl_cut_sp
                cmp.b   #13,d0
                beq.s   .dl_cut
                cmp.b   #10,d0               ; LF (script line) is also a boundary
                beq.s   .dl_cut
                addq.l  #1,a0
                bra.s   .dl_nt
.dl_cut_sp:
                clr.b   (a0)+                ; terminate the name; the arguments follow the space
                move.l  a0,a1
                move.l  a3,d1
                add.l   d6,d1
                sub.l   a0,d1                ; d1 = remaining length of the line
                bra.s   .dl_call
.dl_cut:
                clr.b   (a0)
.dl_noargs:
                move.l  a0,a1
                moveq   #0,d1                ; no arguments
.dl_call:
                move.l  (sp),a0              ; a0 = command name C string
                bsr     sh_exec_cmd          ; d0 = 1 if found+loaded, 0 otherwise
                move.l  (sp)+,a0
                rts
.dl_empty:
                moveq   #-1,d0
                rts

; sh_runscript(): as long as cli_CurrentInput is not the standard input (c:Execute put a script there), its lines are
; read and executed; at its end it is closed, its temporary file deleted and the standard input resumed (FailLevel
; 10). Preserves everything.
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
                bsr     rcli_rdline          ; d6 = length, -1 = end of script
                tst.l   d6
                bmi.s   .sr_eof
                clr.b   0(a3,d6.l)
                bsr     sh_extern
                moveq   #0,d1
                bsr     sh_report
                tst.l   d0
                bne.s   .sr_eof              ; failure: the script is abandoned as if it had finished
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

; sh_write(a4=buffer, d4=len): WRITE via the console handler. Preserves a2/a3/a4/d4/d6/d7.
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

; sh_readline() -> d6 = bytes read, line in (a3). READ via the console handler (blocks until CR).
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

; sh_match(a0=cmd C string, a1=line) -> d0 = 1 if the line starts with cmd followed by a word boundary
; (space / CR / end). Clobbers a0/a1/d0/d1.
sh_match:
.m_lp:
                move.b  (a0)+,d1
                beq.s   .m_wordend           ; end of the cmd word
                cmp.b   (a1)+,d1
                bne.s   .m_no
                bra.s   .m_lp
.m_wordend:
                move.b  (a1),d1              ; character of the line after the prefix
                cmp.b   #' ',d1
                beq.s   .m_yes
                cmp.b   #13,d1               ; CR (end of line)
                beq.s   .m_yes
                tst.b   d1
                beq.s   .m_yes               ; end of string
.m_no:
                moveq   #0,d0
                rts
.m_yes:
                moveq   #1,d0
                rts

; sh_exec_cmd(a0 = C string name, a1 = raw arguments, d1 = length of the arguments): loads+executes a command via
; dos -> d0 = 1 if found + loaded, 0 otherwise. Search: the name as is (current directory, or "device:"/assign),
; then "C:<name>" if the name has no ':'. CLI calling convention: a0 = arguments terminated by '\n', d0 = their
; length, 4(sp) = stack size. The command may clobber all registers: seglist, DosBase and flag live
; in a frame on the stack. Preserves the shell context (movem d2-d7/a2-a6); a6 = SysBase on exit.
XF_FLAG         EQU 0                ; LONG: 1 if found + loaded
XF_SEG          EQU 4                ; LONG: BPTR seglist
XF_DOS          EQU 8                ; APTR: DosBase
XF_ARGLEN       EQU 12               ; LONG: length of the arguments (with the '\n')
XF_NAME         EQU 16               ; "C:<name>" (SH_NAMEMAX)
SH_NAMEMAX      EQU 64
XF_ARGS         EQU XF_NAME+SH_NAMEMAX   ; filtered arguments (SH_ARGMAX)
SH_ARGMAX       EQU 256
XF_STK          EQU XF_ARGS+SH_ARGMAX    ; APTR: dedicated stack of the command
XF_STKSZ        EQU XF_STK+4         ; LONG: block size in bytes (announced stack + 4)
XF_ABUF         EQU XF_STKSZ+4       ; APTR: argument buffer of the CLI (aligned: BPTR)
XF_FH           EQU XF_ABUF+4        ; APTR: input FileHandle (argument injection)
XF_SBUF         EQU XF_FH+4          ; fh_Buf / fh_Pos / fh_End saved
XF_SPOS         EQU XF_SBUF+4
XF_SEND         EQU XF_SPOS+4
XF_RC           EQU XF_SEND+4        ; LONG: return code
XF_FIN          EQU XF_RC+4          ; BPTR: file of "<name" | 0
XF_FOUT         EQU XF_FIN+4         ; BPTR: file of ">name" | 0
XF_RIN          EQU XF_FOUT+4        ; name of "<name" (SH_REDMAX, empty = no redirection)
SH_REDMAX       EQU 64
XF_ROUT         EQU XF_RIN+SH_REDMAX ; name of ">name"
XF_SIZE         EQU XF_ROUT+SH_REDMAX
SH_DEFSTACK     EQU 1000             ; default stack of a command, in longs (cli_DefaultStack)
sh_exec_cmd:
                movem.l d2-d7/a2-a6,-(sp)
                lea     -XF_SIZE(sp),sp
                clr.l   XF_FLAG(sp)
                move.l  a0,d5                ; d5 = name
                lea     XF_ARGS(sp),a2
                bsr     sh_build_args        ; (a1, d1) -> filtered arguments in (a2); d0 = length
                move.l  d0,XF_ARGLEN(sp)
                move.l  ($4).w,a6            ; SysBase
                lea     sh_doslib(pc),a1
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq     .x_ret
                move.l  d0,a4                ; a4 = DosBase
                move.l  d0,XF_DOS(sp)
                ; --- real size of the file: Lock + Examine ---
                move.l  #FIB_SIZEOF,d0
                move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
                jsr     LVO_ALLOCMEM(a6)
                tst.l   d0
                beq     .x_closelib
                move.l  d0,a5                ; a5 = FileInfoBlock
                moveq   #0,d4                ; d4 = size (0 = not found / unreadable)
                move.l  a4,a6
                move.l  d5,d1
                moveq   #SHARED_LOCK,d2
                jsr     DOS_LVO_LOCK(a6)     ; BPTR lock | 0
                tst.l   d0
                bne.s   .x_locked
                move.l  d5,a0                ; "C:<name>" fallback only for a name without ':'
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
                clr.b   (a1)                 ; name truncated
.x_cdone:
                lea     XF_NAME(sp),a0
                move.l  a0,d1
                moveq   #SHARED_LOCK,d2
                jsr     DOS_LVO_LOCK(a6)
                tst.l   d0
                beq.s   .x_nolock
                lea     XF_NAME(sp),a0
                move.l  a0,d5                ; the file will be opened under this name
.x_locked:
                move.l  d0,d7                ; d7 = lock
                move.l  d7,d1
                move.l  a5,d2
                jsr     DOS_LVO_EXAMINE(a6)
                tst.l   d0
                beq.s   .x_unlock
                tst.l   FIB_DIRENTRYTYPE(a5)
                bpl.s   .x_unlock            ; directory -> not executable
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
                move.l  a4,a6                ; LoadSeg reads the file as a stream (no buffer for the whole file)
                move.l  d5,d1
                jsr     DOS_LVO_LOADSEG(a6)  ; BPTR seglist | 0 (IoErr: 103 memory, 121 not an executable)
                move.l  d0,d7
                bne.s   .x_loaded
                move.l  #2,XF_FLAG(sp)       ; found but not loadable
.x_loaded:
                move.l  ($4).w,a6
                tst.l   d7
                beq     .x_closelib
                move.l  d7,XF_SEG(sp)
                move.l  #1,XF_FLAG(sp)       ; FOUND + loaded
                move.l  d5,a0
                move.l  d7,d0
                bsr     sh_cli_begin         ; cli_CommandName = name, cli_Module = seglist
                ; --- redirections: "<name" (MODE_OLDFILE) and ">name" (MODE_NEWFILE), opened before the command ---
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
                lea     XF_RIN(sp),a0        ; (Open clobbered a0)
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
                bsr     sh_cantopen          ; "Can't open <name>": the command is not launched
                bsr     sh_redclose
                moveq   #20,d0
                bsr     sh_cli_end
                bra     .x_unload
.x_nrout:
                ifeq    E3_NO_EXEC
                ifeq    PROD                 ; dev ROM: the proof command emits its marker under Forbid (no
                jsr     ser_lock             ; interleaving with the demo tasks); never in production, where
                endc                         ; Forbid would freeze multitasking until the command's first Wait
                ; --- dedicated stack of cli_DefaultStack longs (like runcommand): the BCPL stub puts the base of its
                ; frames at 8(sp) - 4(sp) = (top - 4) - size -> block ONE long larger than the announced size,
                ; otherwise the first frame overwrites the last long of the previous memory block ---
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
                ; --- arguments: copied into the aligned CLI buffer, injected into the input FileHandle ---
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
                move.l  PR_CIS(a2),d0        ; input of the command = cli_StandardInput (spec §4.2.3), not pr_CIS
                bsr     sh_cli_ptr           ; (which a previous command may have selected then closed: Mount)
                beq.s   .x_inpok
                move.l  CLI_STANDARDINPUT(a1),d0
                move.l  d0,PR_CIS(a2)        ; selectinput(stdin) before the command
                move.l  CLI_STANDARDOUTPUT(a1),PR_COS(a2)
.x_inpok:
                move.l  XF_FIN(sp),d1        ; redirections: streams of the command (arguments injected into "<name")
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
                ; entry registers (spec §4.3): a0/d0 = arguments, 4(sp) = stack size, A1 = BCPL frame of the CLI
                ; (bottom of ITS stack), A2 = GV of the CLI, A3 = segment, A4 = entry point, A5/A6 = BCPL call/return
                move.l  XF_SEG(sp),d0
                lsl.l   #2,d0
                move.l  d0,a3                ; a3 = segment
                lea     4(a3),a4             ; a4 = entry point
                move.l  XF_STK(sp),a5
                add.l   XF_STKSZ(sp),a5      ; a5 = top of the command's stack
                move.l  sp,-(a5)             ; 8(sp) on entry: old SP (restored on return)
                move.l  XF_STKSZ(sp),d0
                subq.l  #4,d0
                move.l  d0,-(a5)             ; 4(sp): stack size in bytes (without the base long)
                move.l  a5,PR_RETURNADDR(a2) ; pr_ReturnAddr -> this long: exit()/stop find the stack there
                move.l  XF_ABUF(sp),d2
                move.l  XF_ARGLEN(sp),d0
                move.l  PR_GLOBVEC(a2),a1
                move.l  TC_SPLOWER(a2),d1
                move.l  a1,a2                ; a2 = GV
                move.l  d1,a1                ; a1 = bottom of the CLI stack = BCPL frame of the caller
                move.l  a5,sp                ; switch to the command's stack (no more XF_* access until the return)
                move.l  d2,a0
                moveq   #0,d1
                lea     bcpl_call,a5
                lea     bcpl_ret,a6
                jsr     (a4)                 ; execute the command; d0 = return code
                addq.l  #4,sp
                move.l  (sp),sp              ; back on the shell's stack
                move.l  d0,XF_RC(sp)
                move.l  ($4).w,a2
                move.l  EB_THISTASK(a2),a2
                clr.l   PR_RETURNADDR(a2)
                bsr     sh_cli_ptr           ; after the command (spec §4.4): selectoutput(cli_StandardOutput),
                beq.s   .x_noresel           ; selectinput(cli_CurrentInput) - the command may
                                             ; have changed or closed its streams
                move.l  CLI_STANDARDOUTPUT(a1),PR_COS(a2)
                move.l  CLI_CURRENTINPUT(a1),PR_CIS(a2)
.x_noresel:
                move.l  XF_FH(sp),d0         ; restore the input buffer (spec §4.2.6)
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
                beq.s   .x_norest            ; fh_End = 0: EOF forced by the command (EndCLI) -> kept
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
                moveq   #-1,d0               ; stack impossible: special "unable to launch" code
.x_ran:
                bsr     sh_cli_end           ; cli_ReturnCode = d0, cli_Module = 0; d1 = module to unload
                tst.l   d1
                bmi.s   .x_mod
                move.l  d1,XF_SEG(sp)        ; 0: the command stayed resident
.x_mod:
                ifeq    PROD
                jsr     ser_unlock
                endc
                endc                         ; RED E3_NO_EXEC: skips the JSR -> command loaded but not executed
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

; sh_redclose(): closes the redirection files of the command (caller's XF frame, at 4(sp)). Preserves d0.
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

; sh_cantopen(a0 = name): "Can't open <name>" on the current output. Preserves d0-d7/a2-a6.
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

; sh_make_cli(): allocates a CommandLineInterface + its BSTRs (command name, SetName, prompt, command file) and
; publishes it in pr_CLI of ThisTask. Streams = pr_CIS/pr_COS, default stack = SH_STK, FailLevel 10. Preserves
; everything.
SH_CLIBSTR      EQU 256              ; size of a CLI BSTR buffer
SH_ARGBUF       EQU CLI_SIZEOF+4*SH_CLIBSTR  ; buffer of injected arguments (long-aligned: fh_Buf is a BPTR)
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
                move.l  d1,CLI_COMMANDFILE(a0)   ; buffer for Execute's temp script name (also written by Run's init)
                sub.l   #SH_CLIBSTR/4,d1
                lsl.l   #2,d1
                move.l  d1,a1
                move.l  #$023E2000,(a1)      ; BSTR prompt ">" (length 2)
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
                move.l  a1,a0                ; BCPL global vector + runtime segarray (BCPL c: commands)
                jsr     bcpl_cli_setup
                jsr     bcpl_cli_register    ; slot 1 of rn_TaskArray, pr_TaskNum = 1 (Run takes the following ones)
.mc_ret:
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts

; sh_cli_begin(a0 = C string name, d0 = BPTR seglist): fills in cli_CommandName (BSTR) and cli_Module.
; Clobbers d0-d1/a0-a1.
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

; sh_cli_end(d0 = return code of the command) -> d1 = cli_Module as the command left it (-1 without a CLI):
; cli_ReturnCode = d0, then cli_Module = 0. A command that makes itself resident (SetPatch) sets cli_Module to 0 itself:
; only the seglist returned here must be unloaded. Preserves everything except d1/a1.
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

; sh_cli_ptr() -> a1 = CLI of ThisTask (Z = 1 if none). Preserves d0.
sh_cli_ptr:
                move.l  d0,-(sp)
                move.l  ($4).w,a1
                move.l  EB_THISTASK(a1),a1
                move.l  PR_CLI(a1),d0
                lsl.l   #2,d0
                move.l  d0,a1
                movem.l (sp)+,d0             ; movem does not touch the CCR: Z comes from the lsl
                rts

; sh_build_args(a1 = raw arguments, d1 = length, a2 = SH_ARGMAX destination) -> d0 = length written (with '\n').
; Copies up to CR/LF/NUL, removes the redirections (">x", "<x", or "> x", at the start of a word outside quotes
; and BEFORE the first argument, like the 1.3 CLI - after that ">" and "<" are argument characters; names stored in
; XF_ROUT / XF_RIN of the same frame as the destination, which is XF_ARGS) and the ";" comment outside quotes; ends
; with '\n' then NUL. Clobbers d0-d4/a0-a3.
sh_build_args:
                move.l  a1,a0
                move.l  a2,a1                ; a1 = XF_ARGS: the redirection names go into the same frame
                clr.b   XF_RIN-XF_ARGS(a1)
                clr.b   XF_ROUT-XF_ARGS(a1)
                moveq   #0,d2                ; d2 = bytes written
                moveq   #1,d3                ; d3 != 0: start of word
                moveq   #0,d4                ; bit0 = inside quotes, bit1 = skipping a redirection, bit2 = argument seen
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
                bra.s   .ba_lp               ; spaces between ">" and the name ("cmd > NIL:")
.ba_rch:
                subq.l  #1,d3                ; d3 = remaining room for the name
                bmi.s   .ba_lp
                move.b  d0,(a3)+
                bra.s   .ba_lp
.ba_rend:
                clr.b   (a3)
                bclr    #1,d4                ; end of the redirection word
                moveq   #1,d3
                bra.s   .ba_lp
.ba_noskip:
                cmp.b   #'"',d0
                bne.s   .ba_noquote
                bchg    #0,d4
                moveq   #0,d3
                bra.s   .ba_arg
.ba_noquote:
                btst    #0,d4
                bne.s   .ba_plain
                cmp.b   #';',d0
                beq.s   .ba_end              ; comment
                tst.l   d3
                beq.s   .ba_plain
                btst    #2,d4
                bne.s   .ba_plain            ; after an argument: no more redirection
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
                bne.s   .ba_arg
                moveq   #1,d3
                bra.s   .ba_put
.ba_arg:
                bset    #2,d4
.ba_put:
                cmp.l   #SH_ARGMAX-2,d2
                bhs     .ba_lp               ; full: the rest is ignored
                move.b  d0,(a2)+
                addq.l  #1,d2
                bra     .ba_lp
.ba_end:
                btst    #1,d4
                beq.s   .ba_nred
                clr.b   (a3)                 ; redirection at end of line
.ba_nred:
                move.b  #10,(a2)+
                clr.b   (a2)
                addq.l  #1,d2
                move.l  d2,d0
                rts

; sh_run_startup(): F1 - reads "s/startup-sequence" (OFS subdirectory of the boot disk) via dos and executes
; each line via sh_dispatch_line (same builtins + loading of external commands as interactive). No
; startup-sequence -> nothing (OK). Empty lines and ";" comments ignored. Preserves everything (movem). F1
; simplification: file in the ROOT (not "s/") -> OFS subdirectory traversal is deferred (documented deviation, see
; strap.s).
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
                move.l  d0,a5                ; a5 = script buffer
                move.l  a4,a6                ; a6 = DosBase
                move.l  #sh_startupname,d1
                move.l  #MODE_OLDFILE,d2
                jsr     DOS_LVO_OPEN(a6)     ; BPTR fh | 0 (0 = no startup-sequence)
                tst.l   d0
                beq     .s_free
                move.l  d0,d7                ; d7 = BPTR fh
                move.l  d7,d1
                move.l  a5,d2
                move.l  #SH_SCRIPTMAX,d3
                jsr     DOS_LVO_READ(a6)     ; d0 = bytes read
                move.l  d0,d5                ; d5 = script size
                move.l  d7,d1
                jsr     DOS_LVO_CLOSE(a6)
                move.l  ($4).w,a6            ; SysBase
                tst.l   d5
                beq.s   .s_free
                ; a2 stays the StandardPacket (sh_write/sh_readline depend on it!) -> pos/end/DosBase in DATA registers.
                move.l  a5,d3
                add.l   d5,d3                ; d3 = end of the buffer (BEFORE reusing d5)
                move.l  a4,d5                ; d5 = DosBase (safe across sh_dispatch_line)
                move.l  a5,d2                ; d2 = current position (start)
.sl_loop:
                cmp.l   d3,d2
                bcc.s   .sl_done             ; pos >= end
                move.l  d2,a3                ; a3 = start of line
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
                sub.l   a3,d6                ; d6 = line length (excluding the terminator)
                move.l  a0,d2                ; pos = position of the terminator
                cmp.l   d3,d2
                bcc.s   .sl_check            ; end reached, no terminator to skip
                move.l  d2,a0
                move.b  (a0),d0
                cmp.b   #13,d0
                bne.s   .sl_notcr
                addq.l  #1,d2                ; skip CR
                cmp.l   d3,d2
                bcc.s   .sl_check
                move.l  d2,a0
                move.b  (a0),d0
.sl_notcr:
                cmp.b   #10,d0
                bne.s   .sl_check
                addq.l  #1,d2                ; skip LF
.sl_check:
                tst.l   d6
                beq.s   .sl_loop             ; empty line
                move.b  (a3),d0
                cmp.b   #';',d0
                beq.s   .sl_loop             ; comment
                bsr     sh_dispatch_line     ; a2=StandardPacket intact, a3=line, d6=length
                moveq   #0,d1
                bsr     sh_report
                tst.l   d0
                bne.s   .sl_done             ; failure: the rest of the startup-sequence is abandoned
                bsr     sh_runscript         ; Execute may have switched the CLI input to a script
                bra.s   .sl_loop
.sl_done:
                move.l  d5,a4                ; restore DosBase
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
sh_sysconfname:
                dc.b    "devs:system-configuration",0
sh_intname:
                dc.b    "intuition.library",0
                even

; sh_sysconfig(a6 = DOSBase): like the 1.3 initial CLI, reads the 232 bytes of devs:system-configuration and passes
; them to SetPrefs(..., 232, TRUE). File missing or shorter: nothing. No "Please insert volume devs" requester on
; a disk without DEVS: (games): pr_WindowPtr is -1 for the duration of the Open. Intended difference: colours 0
; to 3 keep those of the current Preferences (the project's apple-green theme); the extension (ext_size) is ignored,
; intuition V34 clamping to 232 bytes anyway. Preserves everything except d0/d1/a0/a1.
SH_PREFSIZE     EQU 232
SH_PREFCOL      EQU $6E              ; Preferences: color0..3 (4 words)
sh_sysconfig:
                movem.l d2-d4/a6,-(sp)
                lea     -(SH_PREFSIZE+SH_PREFCOL+8)(sp),sp
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a0
                move.l  PR_WINDOWPTR(a0),-(sp)
                moveq   #-1,d0
                move.l  d0,PR_WINDOWPTR(a0)
                move.l  #sh_sysconfname,d1
                move.l  #MODE_OLDFILE,d2
                jsr     DOS_LVO_OPEN(a6)
                move.l  d0,d4
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a0
                move.l  (sp)+,PR_WINDOWPTR(a0)
                tst.l   d4
                beq.s   .sc_ret
                move.l  d4,d1
                move.l  sp,d2
                move.l  #SH_PREFSIZE,d3
                jsr     DOS_LVO_READ(a6)
                move.l  d0,d3
                move.l  d4,d1
                jsr     DOS_LVO_CLOSE(a6)
                cmp.l   #SH_PREFSIZE,d3
                bne.s   .sc_ret
                move.l  ($4).w,a6
                lea     sh_intname(pc),a1
                moveq   #0,d0
                jsr     LVO_OPENLIBRARY(a6)
                tst.l   d0
                beq.s   .sc_ret
                move.l  d0,a6
                lea     SH_PREFSIZE(sp),a0   ; current colours
                move.l  #SH_PREFCOL+8,d0
                jsr     SH_LVO_GETPREFS(a6)
                move.l  SH_PREFSIZE+SH_PREFCOL(sp),SH_PREFCOL(sp)
                move.l  SH_PREFSIZE+SH_PREFCOL+4(sp),SH_PREFCOL+4(sp)
                move.l  sp,a0
                move.l  #SH_PREFSIZE,d0
                moveq   #1,d1
                jsr     SH_LVO_SETPREFS(a6)
                move.l  a6,a1
                move.l  ($4).w,a6
                jsr     LVO_CLOSELIBRARY(a6)
.sc_ret:
                lea     SH_PREFSIZE+SH_PREFCOL+8(sp),sp
                movem.l (sp)+,d2-d4/a6
                rts
SH_LVO_GETPREFS EQU -132
SH_LVO_SETPREFS EQU -324
sh_startupname:
                dc.b    "s/startup-sequence",0
                EVEN
                cnop    0,4                  ; BSTR passed as a BPTR
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
sh_cantmsg:
                dc.b    "Can't open "
sh_cantmsg_end:
sh_cmd_ver:
                dc.b    "ver",0
sh_cmd_echo:
                dc.b    "echo",0
                EVEN

; ============================== ROM CLI (BCPL segment of rn_ConsoleSegment) ==============================
; Run (and Execute) use this segment as entry 4 of the segarray of a background CLI when no "CLI" resident
; exists (spec bcpl-runtime §9.2 / §13.5). The globin installs global 1 = rcli_start there, called by the
; process startup (bcpl_proc_entry) with the startup packet: the packet's init routine (dp_Type) fills
; the CLI (streams, current directory, stack...); if it returns a routine (> 0), that routine is called with pr_Result2
; (immediate reply to the creator); otherwise the packet is returned at the end of the CLI. The CLI then reads
; its commands from cli_CurrentInput (Run's memory FileHandle, or Execute's script), executes them through
; sh_extern and ends at EOF of its standard input.
                cnop    0,4
                xdef    rcli_seg
rcli_seg:
                dc.l    0                    ; link (BPTR of the next segment)
rcli_data:
                dc.l    (rcli_end-rcli_data)/4   ; segment size in longs
RC_LINE         EQU 0                ; line read (SHELL_LINEMAX + NUL)
RC_PKT          EQU SHELL_LINEMAX+4  ; BPTR of the startup packet
RC_R            EQU RC_PKT+4         ; init result: > 0 routine (Run), < 0 flags (Execute), 0 without packet
RC_OUT          EQU RC_R+4           ; standard output set by init (reselected on every round)
RC_SIZE         EQU RC_OUT+4
RC_FRAME        EQU 64               ; frame size announced to BCPL calls (the CLI is not in the frame)
rcli_start:
                lea     -RC_SIZE(sp),sp
                move.l  d1,RC_PKT(sp)
                clr.l   RC_R(sp)
                bsr     rcli_mkcli           ; pr_CLI set BEFORE init: it finds it through findcli()
                beq     rcli_exit
                move.l  RC_PKT(sp),d0
                lsl.l   #2,d0
                beq.s   .rs_set              ; no packet: nothing to initialise
                move.l  d0,a0
                move.l  DP_TYPE(a0),a4       ; init(pkt) in BCPL: A4 = its exact address, D1 = packet
                move.l  RC_PKT(sp),d1
                sub.l   a0,a0                ; A0 = 0: base of BCPL memory accesses (BPTR x 4)
                moveq   #RC_FRAME,d0
                jsr     (a5)
                move.l  d1,RC_R(sp)
                ble.s   .rs_set
                move.l  d1,a4                ; r > 0 (Run: qpkt): r(pr_Result2) returns the packet right away
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a0
                move.l  PR_RESULT2(a0),d1
                sub.l   a0,a0
                moveq   #RC_FRAME,d0
                jsr     (a5)
.rs_set:                                     ; from here on, no more BCPL calls: the CLI ends with RemTask
                bsr     sh_cli_ptr
                move.l  CLI_STANDARDOUTPUT(a1),RC_OUT(sp)
                moveq   #0,d0                ; interactive = not Background and standard input = current input
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
                bsr     rcli_rdline          ; d6 = length, -1 = EOF without data
                tst.l   d6
                bmi.s   .rs_eof
                clr.b   0(a3,d6.l)
                bsr     sh_extern
                bsr     sh_cli_ptr           ; interactive = not Background and standard input = current input
                moveq   #0,d1
                tst.l   CLI_BACKGROUND(a1)
                bne.s   .rs_rep
                move.l  CLI_STANDARDINPUT(a1),d1
                sub.l   CLI_CURRENTINPUT(a1),d1
                seq     d1
                ext.w   d1
                ext.l   d1
.rs_rep:
                bsr     sh_report
                tst.l   d0
                bne.s   .rs_eof              ; failure in a script: abandoned as if it had finished
                bra.s   .rs_loop
.rs_eof:
                bsr     sh_cli_ptr
                move.l  CLI_CURRENTINPUT(a1),d1
                cmp.l   CLI_STANDARDINPUT(a1),d1
                beq.s   .rs_top
                move.l  CLI_STANDARDINPUT(a1),CLI_CURRENTINPUT(a1)  ; end of a script: back to the standard input
                move.l  #10,CLI_FAILLEVEL(a1)
                moveq   #0,d0                ; interactive again if not in the background (NewCLI after
                tst.l   CLI_BACKGROUND(a1)   ; s:cli-startup: prompt from here on)
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
                beq.s   .rs_loop             ; interactive CLI: the console stays open, read again
                move.l  DOS_DOSBASE,a6
                move.l  RC_R(sp),d0
                bpl.s   .rs_runend
                btst    #1,d0                ; Execute: input supplied by the caller -> not closed
                bne.s   .rs_nord
                move.l  CLI_STANDARDINPUT(a1),d1
                jsr     DOS_LVO_CLOSE(a6)
.rs_nord:
                btst    #0,RC_R+3(sp)        ; output opened by init -> closed
                beq.s   .rs_nwr
                move.l  RC_OUT(sp),d1
                jsr     DOS_LVO_CLOSE(a6)
.rs_nwr:
                move.l  RC_PKT(sp),d0        ; returnpkt: the caller of Execute() continues now
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
.rs_runend:                                  ; Run: command stream and output closed
                move.l  CLI_STANDARDINPUT(a1),d1
                jsr     DOS_LVO_CLOSE(a6)
                move.l  RC_OUT(sp),d1
                jsr     DOS_LVO_CLOSE(a6)
.rs_free:
                bsr     rcli_free
rcli_exit:
                move.l  ($4).w,a6
                sub.l   a1,a1
                jsr     LVO_REMTASK(a6)      ; does not return
.rx_hang:
                bra.s   .rx_hang

; rcli_mkcli(): cleared CLI with its four BSTR buffers (command name, SetName, prompt, command file),
; published in pr_CLI; the packet's init routine fills it (streams, settings of the parent CLI). Z = 1 if memory
; is short. Preserves everything except d0.
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

; rcli_selio(d0 = remembered output): before each read, selectinput(cli_CurrentInput) and selectoutput(d0, if not
; zero). Preserves everything.
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

; rcli_prompt(a3 = buffer): interactive CLI reading its standard input -> prompt (BSTR cli_Prompt, "%N" = CLI number)
; on the current output. Preserves d2-d7/a2-a6.
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
                move.b  (a0)+,d2             ; d2 = length
                move.l  a3,a2                ; a2 = formatted text
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
; rcli_putdec(d0 = integer >= 0, a2 = destination): decimal digits, a2 advanced. Clobbers d0/d1/d4.
rcli_putdec:
                moveq   #0,d4                ; digits pushed
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

; rcli_rdline(a3 = buffer) -> d6 = length of the line (without the '\n'), -1 if the input is exhausted without data.
; Character by character on cli_CurrentInput: first its buffer (fh_Buf[fh_Pos..fh_End-1], like rdch), then,
; if it has a handler, Read of one byte; otherwise EOF. Truncated to SHELL_LINEMAX. Preserves d2-d5/d7/a2-a6.
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
                bhs.s   .rl_ch               ; line too long: the rest is ignored
                move.b  d2,0(a3,d6.l)
                addq.l  #1,d6
                bra.s   .rl_ch
.rl_eofd:
                tst.l   d6                   ; EOF after characters: last line without '\n'
                bne.s   .rl_ret
.rl_eof:
                tst.l   d6
                bne.s   .rl_ret
                moveq   #-1,d6
.rl_ret:
                movem.l (sp)+,d2-d3/a2/a6
                rts

; sh_report(d0 = result of sh_extern, a0 = name, d1 = interactive != 0) -> d0 = 1 if a non-interactive script must
; be abandoned. Not found: "Unknown command <name>"; not loadable: "Unable to load <name>: Error code <n>";
; executed with cli_ReturnCode >= cli_FailLevel, in non-interactive mode only: "<name> failed returncode <n>".
; Preserves d1-d7/a0-a6.
sh_report:
                movem.l d1-d3/a0-a2,-(sp)
                move.l  a0,a2
                move.l  d1,d3
                tst.l   d0
                bmi.s   .rp_ok
                beq.s   .rp_unk
                cmp.l   #2,d0
                beq.s   .rp_load
                tst.l   d3
                bne.s   .rp_ok
                bsr     sh_cli_ptr
                beq.s   .rp_ok
                move.l  CLI_RETURNCODE(a1),d2
                cmp.l   CLI_FAILLEVEL(a1),d2
                blt.s   .rp_ok
                move.l  a2,a0
                bsr     sh_puts
                lea     sh_failmsg(pc),a0
                bsr     sh_puts
                move.l  d2,d0
                bsr     sh_putdec
                bra.s   .rp_end
.rp_unk:
                lea     sh_unkmsg(pc),a0
                bsr     sh_puts
                move.l  a2,a0
                bsr     sh_puts
                bra.s   .rp_end
.rp_load:
                move.l  ($4).w,a0            ; read before writing: every Write sets pr_Result2 again
                move.l  EB_THISTASK(a0),a0
                move.l  PR_RESULT2(a0),d2
                lea     sh_loadmsg(pc),a0
                bsr     sh_puts
                move.l  a2,a0
                bsr     sh_puts
                lea     sh_colsp(pc),a0
                bsr     sh_puts
                move.l  d2,d0
                jsr     rt_fault             ; text of the error (C:FAULT), newline included
                bra.s   .rp_stop
.rp_end:
                lea     sh_nl(pc),a0
                bsr     sh_puts
.rp_stop:
                moveq   #0,d0
                tst.l   d3
                bne.s   .rp_ret
                moveq   #1,d0
                bra.s   .rp_ret
.rp_ok:
                moveq   #0,d0
.rp_ret:
                movem.l (sp)+,d1-d3/a0-a2
                rts

; sh_puts(a0 = C string): written to the current output. Preserves everything.
sh_puts:
                movem.l d0-d3/a0-a1/a6,-(sp)
                move.l  a0,d2
                moveq   #-1,d3
.pu_len:
                addq.l  #1,d3
                tst.b   (a0)+
                bne.s   .pu_len
                move.l  ($4).w,a0
                move.l  EB_THISTASK(a0),a0
                move.l  PR_COS(a0),d1
                beq.s   .pu_ret
                move.l  DOS_DOSBASE,a6
                jsr     DOS_LVO_WRITE(a6)
.pu_ret:
                movem.l (sp)+,d0-d3/a0-a1/a6
                rts

; sh_putdec(d0 = signed integer): written in decimal to the current output. Preserves everything.
sh_putdec:
                movem.l d0-d3/a0,-(sp)
                lea     -12(sp),sp
                lea     12(sp),a0
                clr.b   -(a0)
                move.l  d0,d2                ; d2 = sign
                bpl.s   .pd_lp
                neg.l   d0
.pd_lp:                                      ; d0 / 10 in two divu (32-bit quotient)
                moveq   #0,d1
                swap    d0
                move.w  d0,d1
                divu    #10,d1               ; d1 = remainder: quotient of the high word
                move.w  d1,d3
                swap    d0
                move.w  d0,d1
                divu    #10,d1               ; d1 = digit: quotient of the low word
                swap    d3
                move.w  d1,d3                ; d3 = full quotient
                swap    d1
                add.b   #'0',d1
                move.b  d1,-(a0)
                move.l  d3,d0
                bne.s   .pd_lp
                tst.l   d2
                bpl.s   .pd_out
                move.b  #'-',-(a0)
.pd_out:
                bsr     sh_puts
                lea     12(sp),sp
                movem.l (sp)+,d0-d3/a0
                rts

sh_unkmsg:      dc.b    "Unknown command ",0
sh_loadmsg:     dc.b    "Unable to load ",0
sh_colsp:       dc.b    ": ",0
sh_failmsg:     dc.b    " failed returncode ",0
sh_nl:          dc.b    10,0
                even

; rcli_delcmdfile(a3 = buffer): Execute's temporary command file (cli_CommandFile) is deleted and the
; name cleared. Preserves d6/d7/a3.
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

; rcli_free(): end of the CLI: current directory returned, path list (cli_CommandDir: getvec nodes [next, lock])
; returned, rn_TaskArray slot freed, CLI returned.
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
                move.l  d2,a2                ; a2 = node
                move.l  4(a2),d1
                beq.s   .fr_nolk
                move.l  DOS_DOSBASE,a6
                jsr     DOS_LVO_UNLOCK(a6)
.fr_nolk:
                move.l  (a2),d2              ; next (BPTR)
                lea     -4(a2),a1            ; freevec: size in the getvec header
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
                cnop    0,4
                dc.l    0                    ; end of the globin table
                dc.l    1,rcli_start-rcli_data   ; global 1 = start
                dc.l    1                    ; highest global defined
rcli_end:
