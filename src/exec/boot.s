; src/exec/boot.s — exec.library : en-tête ROM, coldstart, build ExecBase,
; publication de SysBase, auto-vérification + auto-test. Module « glue » du
; coldstart (M2.3 : extrait de l'ancien coldstart.s monolithique).
; Piste IMPLÉMENTATION (« clean ») : écrit depuis docs/analysis/exec-spec.md +
; ABI publique. AUCUNE lecture de la ROM.
;
; Reset $FC00D2 -> superviseur + gel HW (ROUGE) -> coupe overlay + pile (BLEU)
; -> ExecBase + jump table (CYAN) -> publie SysBase, auto-vérif + auto-test des
; fonctions via la jump table -> BLANC si tout passe, MAGENTA sinon.
;
; Couleur -> phase (débogueur visuel) : rouge=entré, bleu=overlay off/pile,
; cyan=build ExecBase+table, blanc=SUCCÈS, magenta=échec d'une vérification.

                include "exec.i"
                include "dospkt.i"       ; D3 : constantes Process/packet pour le scaffold de preuve
                include "dos.i"          ; D3c : DL_ROOT/RN_INFO/DI_DEVINFO (montage DeviceNode)
                include "expansion.i"    ; expansion.library : EXP_LVO_*/ConfigDev (preuve round-trip)

                xref    newlist          ; lists.s
                xref    build_jumptable  ; library.s
                xref    init_memory      ; memory.s
                xref    add_slow_memory  ; memory.s (slow RAM $C00000 en tête de MemList)
                xref    init_task        ; tasks.s
                xref    init_ints        ; interrupts.s
                xref    dispatch_in      ; interrupts.s (M7c : lancement 1re tâche = transition user-mode)
                xref    build_reslist    ; resident.s (scan des ROMTags)
                xref    timer_micro_int  ; timer.s (struct Interrupt de l'unité MICROHZ, vecteur ICR CIA-B)
                xref    timer_micro_start
                xref    task_alloc
                xref    ciaa_server      ; cia.s (serveur PORTS/INT2)
                xref    ciab_server      ; cia.s (serveur EXTER/INT6, vecteur exclusif)
                xref    gfx_display_init ; graphics/gfx.s (M4a : premier affichage piloté par le Copper)
                xref    strap_boot       ; exec/strap.s (M6r : décision de boot -> insert-disk si non bootable)
                xref    kbd_selftest     ; exec/keyboard.s (F2a : réception+décodage clavier CIA-A)
                xref    kbd_devevent     ; exec/kbddev.s (keyboard.device : keycode brut synthétique pour la preuve)
                xref    kbd_install      ; exec/keyboard.s (F2b : installe le driver clavier LIVE interrupt-driven)
                xref    font8x8          ; graphics/font8x8.s (#3a : glyphes 8x8 — readback de preuve console.device)
                xref    dv_validate      ; dos/diskvalidator.s (#4 : valide le bitmap OFS de DF0:)
                xref    kbd_cook         ; exec/keymap.s (#5 : cook keycode(+qualifiers)->ASCII, US/AZERTY)
                xref    req_draw         ; intuition/requester.s (requester : rendu bord+texte)
                xref    req_input_handler ; intuition/requester.s (requester : handler clic sur input.device)
                xref    td_read_track0   ; exec/trackdisk.s (B2 : lecture d'une piste MFM brute de DF0)
                xref    td_decode_track  ; exec/trackdisk.s (B3 : décodage MFM piste -> secteurs 512 o)
                xref    td_read_track    ; exec/trackdisk.s (B2b : seek + lecture d'une piste arbitraire)
                xref    td_disk_present  ; exec/trackdisk.s (écran insert-disk : disquette insérée ?)
                xref    ofs_read_file    ; dos/ofs.s (D1 : lecture seule OFS -> lire un fichier par nom)
                xref    dos_loadseg      ; dos/loadseg.s (D2 : charger un exécutable hunk de l'OFS + reloc)
                xref    dos_unloadseg    ; dos/loadseg.s (D2 : libérer une seglist)
                xref    proc_create      ; dos/process.s (D3 : créer un Process + pr_MsgPort)
                xref    dos_sendpkt      ; dos/process.s (D3 : envoi d'un DOS packet + WaitPort/GetMsg)
                xref    dos_handler_df0  ; dos/handler.s (D3b : process file-handler DF0: OFS)
                xref    ls_load_hunks    ; dos/loadseg.s (D3d : parse hunk depuis un buffer lu via dos)
                xref    con_handler      ; dos/conhandler.s (E1 : process handler console-série)
                xref    shell_main       ; dos/shell.s (E2 : shell interactif minimal)
                xref    feeder_main      ; dos/feeder.s (intégration F : feeder clavier -> input.device)
                ifne    LOADSCREEN_DEMO
                xref    loadscreen_demo  ; graphics/loadscreen.s (écran de chargement, gaté LOADSCREEN_DEMO)
                endc
                xref    gp_delta8        ; exec/gameport.s (souris : delta signé avec wraparound 8 bits)
                xref    gp_poll          ; exec/gameport.s (souris : logique poll -> InputEvent RAWMOUSE via IND_WRITEEVENT)
                xref    gp_install       ; exec/gameport.s (souris : arme gp_vblank_server sur la chaîne VERTB)
                xref    pointer_input_handler ; intuition/pointer.s (accumulateur deltas relatifs -> position absolue)

                xref    exec_softint_init
                xdef    ser_puts         ; émission série (diagnostics du runtime BCPL)
                xdef    ser_puthex
                xdef    ser_lock         ; émission série atomique (Forbid gated SCHED_ON) — utilisé par conhandler/feeder/shell
                xdef    ser_unlock

DEMO_STK     EQU 2048         ; pile des tâches démo (frames de switch)
D3_STK       EQU 4096         ; pile des processes D3 (driver/handler : ser_puts + ofs/loadseg plus tard)
LYT_PIX      macro                    ; pixel (\1, \2) du BitMap de la sonde layers == \3, sinon échec
        moveq   #\1,d0
        moveq   #\2,d1
        moveq   #\3,d2
        bsr     lyt_px
        bne     lyt_fail
             endm
LYT_RPIX     macro                    ; ReadPixel(L2, \1, \2) == \3, sinon échec
        moveq   #\1,d0
        moveq   #\2,d1
        moveq   #\3,d2
        bsr     lyt_rpx
        bne     lyt_fail
             endm
AUT_KEY      EQU 32           ; IOAudio ioa_AllocKey / ioa_Data / ioa_Length / ioa_Period / ioa_Volume / ioa_Cycles
AUT_DATA     EQU 34
AUT_LENGTH   EQU 38
AUT_PERIOD   EQU 42
AUT_VOLUME   EQU 44
AUT_CYCLES   EQU 46
SEMT_NEST    EQU 14           ; SignalSemaphore ss_NestCount / ss_Owner / ss_QueueCount (sonde sémaphores)
SEMT_OWNER   EQU 40
SEMT_QC      EQU 44
SEMT_SIZE    EQU 48
KDT_ACTUAL   EQU 32           ; IOStdReq io_Actual / io_Length / io_Data (sonde keyboard.device)
KDT_LENGTH   EQU 36
KDT_DATA     EQU 40
IOF_QUICK_K  EQU 1
INP_IO_DATA  EQU 40           ; #2 : IOStdReq io_Data (boot.s n'inclut pas disk.i -> EQU local)
INPUT_TESTBLK EQU 120         ; #2 : bloc de test input.device = ioreq(48)+h1(24)+h2(24)+event(22), arrondi pair
CMD_WRITE_BO EQU 3            ; #3a : io_Command CMD_WRITE (EQU local)
CMD_READ_BO  EQU 2            ; #3b : io_Command CMD_READ (EQU local)
IO_LEN_BO    EQU 36           ; #3a : IOStdReq io_Length (EQU local)
; D3b : bloc du fs-driver (une seule AllocMem, sous-parties long-alignées pour les BPTR)
FSD_SP       EQU 0            ; StandardPacket (68)
FSD_FH       EQU 68           ; FileHandle (44)
FSD_BUF      EQU 112          ; buffer de lecture (2048)
FSD_NAME     EQU 2160         ; BSTR nom (len + "kickslop")
FSD_TOTAL    EQU 2176
DEMO_SIG     EQU 16           ; bit de signal de task_H (hors 0-15 réservés système)
DEMO_PRI_H   EQU 10           ; task_H : haute priorité (cible du yield-sur-Permit)
FB_SIG       EQU 17           ; bit de signal de task_fb (preuve atomicité Forbid ; hors 0-15, != DEMO_SIG)
FB_PRI_FA    EQU 3            ; task_fa : priorité basse (tient le Forbid)
FB_PRI_FB    EQU 7            ; task_fb : priorité HAUTE (préempterait fa si Forbid n'était pas respecté)
DEMO_PRI_T   EQU 10           ; task_timer (M7a) : même pri que task_H -> partagent les dispatches
CONS_THRESH  EQU 100          ; réveils de task_H (via yield) requis pour « M3F LIVE »
                ifne    M7E_COOP
SPIN_THRESH  EQU 0            ; coopératif : pas de task_S -> « M3F LIVE » par le seul yield
                else
SPIN_THRESH  EQU 5            ; itérations de task_S (via préemption) requises pour « M3F LIVE »
                endc
TCONS_THRESH EQU 50           ; réveils de task_timer (via l'IRQ MICROHZ) requis pour « M7A TIMER OK »
M7A_MINTICKS EQU 250          ; ET délai minimum (ticks VBlank = 5 s) écoulé avant d'émettre OK :
                              ; le détecteur de clash tourne à chaque INT6 (~2/s), donc en RED un
                              ; clash tombe BIEN AVANT 5 s -> « M7A FAILED » précède, OK n'apparaît pas.
                ifne    M7D_STRESS_MAX
DEMO_PRI_P   EQU 20           ; RED A/B : task_port martèle le port (contention max vs IRQ)
                else
DEMO_PRI_P   EQU 0            ; task_port (M7d) : pri 0 -> partage le CPU équitablement avec task_S/L
                endc
STRESS_K     EQU 4            ; nb de messages de stress circulant sur le port partagé
PORTT_THRESH EQU 60           ; itérations GetMsg+PutMsg de task_port requises pour « M7D PORTS OK »
PORTI_THRESH EQU 300          ; itérations côté interruption requises (producteur rapide ~INT6)
PEMPTY_LIMIT EQU 50000        ; M7d : GetMsg vides consécutifs = nœuds perdus (corruption) ; GREEN ~0
SENT_H       EQU $CAFE0010    ; sentinelles de contexte (doivent survivre à TOUT switch)
SENT_L       EQU $CAFE0020
SENT_S       EQU $CAFE0030
SENT_T       EQU $CAFE0040    ; sentinelle de task_timer (M7a)
SENT_P       EQU $CAFE0050    ; sentinelle de task_port (M7d)
SENT_Q2      EQU $CAFE0060    ; sentinelle de task_q2 (M7h, spinner-2 d'isolation)
SENT_RM      EQU $CAFE0070    ; sentinelle de task_rm (M7j, tâche qui se termine)
M7H_MINTICKS EQU 150          ; ticks VBlank min avant d'émettre « M7H QUANTUM OK » (ratio stable, ~3 s)
                ifne    M7L_OLD_CONV
TT_MICRO_REQ EQU 400000       ; RED M7L_OLD_CONV : /20000 -> 20 int -> ~7,2 ms (période inchangée)
                else
TT_MICRO_REQ EQU 7000         ; M7l : 7000 µs RÉELS (≈ ancien débit ~140/s)
                endc
; (FTEST_LO/FTEST_HI, région de test multi-header, sont dans exec.i — carte mémoire)

; L'en-tête doit atterrir à $FC0000 : boot.o est le PREMIER objet passé à vlink
; (cf. Makefile), son CODE porte donc le reset vector. hdr_start = offset 0 de la
; section ; le padding utilise une différence intra-section (constante en relogeable).
hdr_start:
        dc.w    $1111
        dc.w    $4EF9
        dc.l    coldstart        ; +04 PC de reset
        dc.l    $0000FFFF        ; +08
        dc.l    $00220005        ; +0C version ROM 34.5
        dc.l    $00220002        ; +10
        dc.l    $FFFFFFFF        ; +14
        dcb.b   $D0-(*-hdr_start),0
        dc.w    $4E70            ; $FC00D0 RESET (magic_reset)

coldstart:                        ; $FC00D2
        ; --- Phase 1 : superviseur + gel matériel (straight-line, pas de pile) ---
        move.w  #$2700,sr
        move.w  #$7FFF,DMACON
        move.w  #$7FFF,INTENA
        move.w  #$7FFF,INTREQ
        move.w  #C_RED,COLOR00

        ; --- Phase 2 : coupe overlay puis installe la pile ---
        move.b  #$03,CIAA_DDRA
        move.b  #$02,CIAA_PRA        ; OVL off -> RAM chip à $0
        move.l  #STACKTOP,sp
        move.w  #C_BLUE,COLOR00
        move.w  #SERPER_9600_PAL,SERPER
        lea     msg_cold(pc),a0
        bsr     ser_puts

        ; --- F2a : réception+décodage clavier CIA-A (TÔT, interruptions encore masquées -> pas de course avec le
        ; cia_wrapper qui clearait le flag SP). Décode le flux power-up du clavier émulé ($FD initiate + $FE terminate),
        ; prouvant la voie clavier SANS injecteur. d0 = flags ; d0==3 = les deux vus. ---
        jsr     kbd_selftest         ; keyboard.o lié loin -> jsr absolu
        cmp.b   #3,d0
        bne.s   .f2a_nokbd
        lea     msg_f2kbd(pc),a0
        bsr     ser_puts             ; « F2 KBD OK »
.f2a_nokbd:

        ; --- Phase 3 : ExecBase + jump table ---
        move.w  #C_CYAN,COLOR00
        lea     EXECBASE,a0          ; zéro-remplit la zone des champs positifs
        move.w  #(EXEC_POSSIZE/4)-1,d0
.zf:
        clr.l   (a0)+
        dbf     d0,.zf

        lea     EXECBASE,a6          ; a6 = SysBase (convention library base)
        move.b  #NT_LIBRARY,LN_TYPE(a6)
        move.l  #exec_name,LN_NAME(a6)
        move.w  #EXEC_NEGSIZE,LIB_NEGSIZE(a6)
        move.w  #EXEC_POSSIZE,LIB_POSSIZE(a6)
        move.w  #34,LIB_VERSION(a6)
        move.w  #2,LIB_REVISION(a6)
        move.l  #exec_id,LIB_IDSTRING(a6)
        move.l  #MAXCHIP,EB_MAXLOCMEM(a6)
        move.w  #0,EB_ATTNFLAGS(a6)
        move.b  #50,EB_VBLANKFREQ(a6)
        move.b  #50,EB_POWERFREQ(a6)
        move.b  #-1,EB_IDNEST(a6)
        move.b  #-1,EB_TDNEST(a6)
        move.l  #EXECBASE,d0
        not.l   d0
        move.l  d0,EB_CHKBASE(a6)

        lea     EB_MEMLIST(a6),a1
        jsr     newlist
        lea     EB_RESOURCELIST(a6),a1
        jsr     newlist
        lea     EB_DEVICELIST(a6),a1
        jsr     newlist
        lea     EB_INTRLIST(a6),a1
        jsr     newlist
        lea     EB_LIBLIST(a6),a1
        jsr     newlist
        lea     EB_PORTLIST(a6),a1
        jsr     newlist
        lea     EB_TASKREADY(a6),a1
        jsr     newlist
        lea     EB_TASKWAIT(a6),a1
        jsr     newlist
        lea     EB_SEMLIST(a6),a1
        jsr     newlist

        jsr     build_jumptable
        jsr     init_memory
        jsr     init_task            ; TCB « boot task » -> ThisTask (avant selftest)

        ; --- Phase 4 : publie SysBase, auto-vérif, auto-test ---
        move.l  a6,($4).w

        move.l  ($4).w,d0
        cmp.l   #EXECBASE,d0
        bne     eb_fail
        cmp.w   #34,LIB_VERSION(a6)
        bne     eb_fail
        move.l  a6,d0
        not.l   d0
        cmp.l   EB_CHKBASE(a6),d0
        bne     eb_fail
        move.l  EB_MEMLIST(a6),d0    ; lh_Head doit pointer sur le MemHeader ajouté
        cmp.l   #MH_CHIP,d0
        bne     eb_fail

        bsr     selftest             ; d0 = 0 (OK) / !=0 (échec)
        tst.l   d0
        bne     eb_fail
        jsr     add_slow_memory      ; après le selftest mémoire (qui suppose la chip en tête de liste)
        lsr.l   #8,d0                ; octets -> Ko (512 Ko = $0200)
        lsr.l   #2,d0
        move.w  d0,d2
        lea     msg_memslow(pc),a0
        bsr     ser_puts             ; « MEM SLOW KB= »
        move.w  d2,d0
        bsr     ser_puthex
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        bsr     rdf_selftest         ; RawDoFmt (-522) : formatage comparé à une chaîne attendue
        ; --- M3a : arme VBlank et prouve que la chaîne d'interruptions tourne ---
        jsr     init_ints
        jsr     exec_softint_init    ; file des interruptions logicielles (Cause) + serveur SOFTINT
        move.l  #$00100000,d1        ; timeout du spin (le GREEN sort sur count=5 bien avant)
.vbl_wait:
        lea     VBL_COUNT,a0
        move.l  (a0),d0              ; chargement DANS la boucle (le compteur évolue)
        cmp.l   #5,d0
        bcc.s   .vbl_live
        subq.l  #1,d1
        bne.s   .vbl_wait
        lea     msg_vbltimeout(pc),a0  ; interruptions mortes -> échec
        bsr     ser_puts
        bra     eb_fail
.vbl_live:
        lea     msg_vblok(pc),a0
        bsr     ser_puts

        move.w  #C_WHITE,COLOR00
        lea     msg_ok(pc),a0
        bsr     ser_puts             ; « self-test passed » émis AVANT le lancement (gate conservée)

        ; --- M4 : scan des résidents + InitCode (machinerie data-driven) ---
        ; Prouve la MACHINERIE de découverte de modules (scan ROM des ROMTags -> ResModules
        ; pri-trié -> InitResident/InitCode de chacun en ordre décroissant) avec des résidents
        ; DÉMO. N'EST PAS le handoff de boot : le handoff reste la démo M3f codée en dur
        ; ci-dessous (rte qui ne revient jamais) tant qu'aucun vrai module (cia/timer...)
        ; n'existe. Les résidents démo ne font qu'émettre leur nom ; rien n'est lancé par eux.
        move.l  #127,RES_LASTPRI     ; borne haute (toute RT_PRI <= 127 passe)
        clr.l   RES_COUNT
        jsr     build_reslist        ; scanne [RESSCAN_LO,HI) -> ExecBase->ResModules
        moveq   #RTF_COLDSTART,d0    ; startClass : résidents de démarrage à froid
        moveq   #0,d1                ; version minimale 0
        jsr     LVO_INITCODE(a6)     ; init chaque résident démo (émet son nom en ordre de pri)
        lea     res_mid_name(pc),a1  ; FindResident(nom) doit retrouver le bon résident
        jsr     LVO_FINDRESIDENT(a6)
        cmp.l   #res_mid,d0
        bne     res_fail
        cmp.l   #3,RES_COUNT         ; les 3 résidents démo direct-init initialisés ?
        bne     res_fail
        lea     msg_res_ok(pc),a0
        bsr     ser_puts             ; « M4 RESIDENTS OK »

        ; --- M5a : vérifier le résident AUTOINIT (demo.autolib) créé par MakeLibrary ---
        lea     EB_LIBLIST(a6),a0    ; la lib doit avoir été ajoutée à LibList
        lea     autolib_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     auto_fail            ; lib absente -> AUTOINIT/add KO
        move.l  d0,a2                ; a2 = base de la lib
        cmp.w   #40,LIB_VERSION(a2)  ; InitStruct (INITWORD) a posé la version ?
        bne     auto_fail
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; InitStruct (INITBYTE) a posé le type ?
        bne     auto_fail
        cmp.w   #$5A,LIB_REVISION(a2) ; l'init function a tourné (a posé la révision) ?
        bne     auto_fail
        move.l  a6,-(sp)             ; sauve SysBase
        move.l  a2,a6                ; a6 = base de la lib (convention d'appel)
        jsr     -6(a6)               ; appelle func0 via la jump table -> d0 (MakeFunctions OK ?)
        move.l  (sp)+,a6             ; restaure SysBase
        cmp.l   #$5A,d0
        bne     auto_fail
        lea     msg_auto_ok(pc),a0
        bsr     ser_puts             ; « M5A AUTOINIT OK »

        ; --- M5b : vérifier cia.resource (1er vrai module résident, direct-init) ---
        lea     ciab_test_name(pc),a1  ; OpenResource("ciab.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     cia_fail             ; resource absent -> KO
        move.l  d0,a2                ; a2 = base ciab
        cmp.l   #CIAB_HW,CIAR_HWBASE(a2)  ; bonne base matérielle ?
        bne     cia_fail
        move.l  a6,-(sp)             ; AbleICR($81 = enable bit0) via la jump table du resource
        move.l  a2,a6                ; a6 = base resource (convention d'appel)
        moveq   #$81,d0
        jsr     CIA_ABLEICR(a6)
        move.l  (sp)+,a6
        move.b  CIAR_ICRMASK(a2),d0  ; le shadow doit avoir le bit0 posé
        and.b   #1,d0
        beq     cia_fail
        move.l  a6,-(sp)             ; AddICRVector(bit1, dummy) -> doit rendre NULL (slot libre)
        move.l  a2,a6
        moveq   #1,d0
        lea     cia_dummy_int(pc),a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        tst.l   d0
        bne     cia_fail
        lea     msg_cia_ok(pc),a0
        bsr     ser_puts             ; « M5B CIA OK »

        ; --- M5c : vérifier timer.device (AUTOINIT, 2e vrai module résident) ---
        lea     EB_DEVICELIST(a6),a0 ; le device doit avoir été ajouté à DeviceList
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)     ; (= ce que fait OpenDevice en interne)
        tst.l   d0
        beq     timer_fail
        move.l  d0,a2                ; a2 = base device
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD) ?
        bne     timer_fail
        cmp.b   #NT_DEVICE,LN_TYPE(a2)  ; InitStruct (INITBYTE) ?
        bne     timer_fail
        move.l  a6,-(sp)             ; Open via la jump table du device -> LIB_OPENCNT++
        move.l  a2,a6                ; a6 = base device (convention)
        suba.l  a1,a1                ; iorequest = NULL (stub l'ignore)
        moveq   #0,d0                ; unit 0
        moveq   #0,d1                ; flags
        jsr     -6(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)   ; Open a bien incrémenté ?
        bne     timer_fail
        lea     msg_timer_ok(pc),a0
        bsr     ser_puts             ; « M5C TIMER OK »

        ; --- M4c1 : vérifier graphics.library (AUTOINIT, 1er LIBRARY -> LibList) ---
        ; Miroir de la preuve M5c, mais sur EB_LIBLIST (branche NT_LIBRARY->LibList, neuve). Skip-on-fail :
        ; en RED (RT_TYPE=NT_DEVICE) GfxBase est routée vers DeviceList -> FindName(LibList) rate -> marqueur
        ; absent, sans « FAILED » (le reste du boot continue).
        lea     EB_LIBLIST(a6),a0
        lea     graphics_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   m4c1_done
        move.l  d0,a2                ; a2 = GfxBase
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD) ?
        bne.s   m4c1_done
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; InitStruct (INITBYTE) ? (device mal routé ne passerait pas ici non plus)
        bne.s   m4c1_done
        move.l  a6,-(sp)             ; Open via la jump table -> LIB_OPENCNT++
        move.l  a2,a6
        jsr     -6(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)
        bne.s   m4c1_done
        lea     msg_m4c1_ok(pc),a0
        bsr     ser_puts             ; « M4C1 GFX LIB OK »
m4c1_done:

        ; --- M5 : vérifier intuition.library (squelette résident + ViewAddress) ---
        ; Miroir de la preuve M4c1 sur EB_LIBLIST, étendu d'un appel ABI RÉEL : ViewAddress (LVO -294) doit
        ; renvoyer &ib_ViewLord (= IntuitionBase + IB_VIEWLORD). Skip-on-fail : si l'une des vérifs échoue
        ; (ou RED M5I_BAD_VIEWADDR -> ViewAddress=0), le marqueur « M5I INTUI LIB OK » est absent, sans FAILED.
        lea     EB_LIBLIST(a6),a0
        lea     intuition_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   m5i_done
        move.l  d0,a2                ; a2 = IntuitionBase
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD) ?
        bne.s   m5i_done
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; InitStruct (INITBYTE) ? (device mal routé ne passerait pas FindName non plus)
        bne.s   m5i_done
        move.l  a6,-(sp)             ; Open via la jump table -> LIB_OPENCNT++
        move.l  a2,a6
        jsr     LVO_OPEN(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)
        bne.s   m5i_done
        move.l  a6,-(sp)             ; ViewAddress() via la jump table (a6 = IntuitionBase)
        move.l  a2,a6
        jsr     -294(a6)             ; LVO_VIEWADDRESS = -294 (littéral : boot.s n'inclut qu'exec.i)
        move.l  (sp)+,a6
        lea     LIB_SIZE(a2),a1      ; attendu : &ib_ViewLord (IB_VIEWLORD = LIB_SIZE : le ViewLord suit la base Library)
        cmp.l   a1,d0
        bne.s   m5i_done
        lea     msg_m5i_ok(pc),a0
        bsr     ser_puts             ; « M5I INTUI LIB OK »
m5i_done:

        ; --- OpenLibrary : ouverture par nom + gate de version (exec) ---
        ; 1) OpenLibrary("intuition.library",34) == base & OpenCnt+1 ; 2) version 99 -> 0 (gate de version) ;
        ; 3) lib inexistante -> 0 ; 3b) OldOpenLibrary == base (sans gate) ; 4) CloseLibrary -> OpenCnt-1.
        ; RED OPENLIB_NO_VERCHECK : (2) ouvre À TORT
        ; (d0 != 0) -> assertion échoue -> « M5O OPENLIB OK » absent. a2 = IntuitionBase, d3 = OpenCnt baseline.
        lea     EB_LIBLIST(a6),a0
        lea     intuition_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   m5o_done
        move.l  d0,a2                ; a2 = IntuitionBase
        move.w  LIB_OPENCNT(a2),d3   ; d3 = OpenCnt baseline (N)
        lea     intuition_test_name(pc),a1   ; 1) succès version 34
        moveq   #34,d0
        jsr     LVO_OPENLIBRARY(a6)
        cmp.l   a2,d0                ; == IntuitionBase ?
        bne.s   m5o_done
        move.w  LIB_OPENCNT(a2),d0
        subq.w  #1,d0
        cmp.w   d3,d0                ; OpenCnt == N+1 ?
        bne.s   m5o_done
        lea     intuition_test_name(pc),a1   ; 2) version 99 trop haute -> 0, OpenCnt inchangé
        move.w  #99,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        bne.s   m5o_done             ; RED OPENLIB_NO_VERCHECK : renvoie base != 0 -> M5O absent
        move.w  LIB_OPENCNT(a2),d0
        subq.w  #1,d0
        cmp.w   d3,d0                ; toujours N+1 (aucune ouverture) ?
        bne.s   m5o_done
        lea     noexist_test_name(pc),a1     ; 3) lib inexistante -> 0
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        bne.s   m5o_done
        lea     intuition_test_name(pc),a1   ; 3b) OldOpenLibrary (pré-V33, sans gate de version) == base
        jsr     LVO_OLDOPENLIBRARY(a6)
        cmp.l   a2,d0
        bne.s   m5o_done
        move.l  a2,a1                ; rééquilibre l'ouverture 3b (net zéro) avant le step 4
        jsr     LVO_CLOSELIBRARY(a6)
        move.l  a2,a1                ; 4) CloseLibrary -> OpenCnt revient à N
        jsr     LVO_CLOSELIBRARY(a6)
        move.w  LIB_OPENCNT(a2),d0
        cmp.w   d3,d0                ; OpenCnt == N ?
        bne.s   m5o_done
        lea     msg_m5o_ok(pc),a0
        bsr     ser_puts             ; « M5O OPENLIB OK »
m5o_done:

        ; --- M6 : vérifier dos.library (squelette résident + convention BPTR + DateStamp) ---
        ; Miroir des preuves M4c1/M5 sur EB_LIBLIST, étendu de deux vérifs : (a) round-trip BPTR — dl_Root (APTR) ->
        ; RootNode, rn_Info (BPTR) <<2 doit égaler &DosInfo (lu via le scaffold DL_DISHADOW, en compute-then-compare,
        ; SANS déréférencer le pointeur décodé : en RED l'échec est un mismatch d'adresse, jamais un bus error) ;
        ; (b) DateStamp(-192) remplit (0,0,0) « horloge non réglée » et renvoie le pointeur. Skip-on-fail : toute
        ; vérif ratée (ou RED M6D_BAD_BPTR) -> « M6D DOS LIB OK » absent, sans FAILED. a6 = ExecBase.
        lea     EB_LIBLIST(a6),a0
        lea     dos_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m6d_done
        move.l  d0,a2                ; a2 = DosBase
        cmp.w   #34,LIB_VERSION(a2)  ; InitStruct (INITWORD) ?
        bne     m6d_done
        cmp.b   #NT_LIBRARY,LN_TYPE(a2)  ; InitStruct (INITBYTE) ?
        bne     m6d_done
        move.l  a6,-(sp)             ; Open via la jump table -> LIB_OPENCNT++
        move.l  a2,a6
        jsr     LVO_OPEN(a6)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)
        bne     m6d_done
        ; (a) round-trip BPTR — AUCUN déréférencement du pointeur décodé
        move.l  LIB_SIZE(a2),a3      ; a3 = dl_Root (DL_ROOT = LIB_SIZE = 34) = RootNode (APTR)
        move.l  a3,d0
        beq     m6d_done             ; RootNode alloué ?
        move.l  70(a2),d2            ; d2 = DL_DISHADOW (offset 70) = &DosInfo (APTR brut, connu)
        beq     m6d_done             ; DosInfo alloué ?
        move.l  24(a3),d0            ; d0 = rn_Info (RN_INFO = 24) ; lecture sûre (a3 = RootNode valide, GREEN et RED)
        lsl.l   #2,d0                ; BPTR -> APTR
        cmp.l   d2,d0                ; == &DosInfo ?  RED M6D_BAD_BPTR : rn_Info brut -> 4*&DosInfo != shadow
        bne     m6d_done
        ; (b) DateStamp -> (0,0,0) + renvoie le pointeur. Buffer de 12 octets sur la pile, pré-sali.
        lea     -12(sp),sp           ; buf = sp (DS_SIZEOF = 12)
        move.l  #$5A5A5A5A,(sp)      ; salit les 3 longs : « mis à 0 » devient discriminant
        move.l  #$5A5A5A5A,4(sp)
        move.l  #$5A5A5A5A,8(sp)
        move.l  sp,d1                ; d1 = &date (convention dos : arg en d1)
        move.l  a6,-(sp)             ; swap a6 -> DosBase (décale sp de 4 ; d1 = adresse absolue, inchangée)
        move.l  a2,a6
        jsr     -192(a6)             ; LVO_DATESTAMP = -192 ; d0 = &date, date = {0,0,0}
        move.l  (sp)+,a6             ; restore a6 = ExecBase (sp revient au buffer)
        cmp.l   sp,d0                ; renvoie bien le pointeur passé ?
        bne.s   m6d_ds_pop
        tst.l   (sp)                 ; ds_Days == 0 ?
        bne.s   m6d_ds_pop
        tst.l   4(sp)               ; ds_Minute == 0 ?
        bne.s   m6d_ds_pop
        tst.l   8(sp)               ; ds_Tick == 0 ?
        bne.s   m6d_ds_pop
        lea     12(sp),sp            ; libère le buffer (succès)
        lea     msg_m6d_ok(pc),a0
        bsr     ser_puts             ; « M6D DOS LIB OK »
        bra.s   m6d_done
m6d_ds_pop:
        lea     12(sp),sp            ; libère le buffer (échec DateStamp)
m6d_done:

        ; --- expansion.library : gate de version v37 + round-trip de la liste ConfigDev (Alloc->Add->Find) ---
        ; (1) OpenLibrary("expansion.library", 37) DOIT échouer (gate KS 2.0 ; c'est ce qui fait sauter la branche
        ; expansion du bootblock Lemmings sur notre V34) ; OpenLibrary(..., 34) réussit. (2) AllocConfigDev -> pose
        ; manufacturer/product -> AddConfigDev -> FindConfigDev les retrouve (exact + wildcard produit) + un ID absent
        ; ne matche pas -> « EXPANSION OK ». Cleanup robuste : Remove UNIQUEMENT si le nœud est chaîné (ln_Succ!=0),
        ; sinon (RED EXP_NO_ENQUEUE : pas ajouté) on free seulement. Synchrone (fonctions lib pures, pas de packets).
        lea     expansion_test_name(pc),a1
        moveq   #37,d0               ; v37 (KS 2.0) -> DOIT renvoyer 0 sur notre V34
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        bne     exp_done             ; v37 ouvre à tort (gate cassé) -> ne pas émettre
        lea     expansion_test_name(pc),a1
        moveq   #34,d0               ; V34 -> doit réussir
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     exp_done
        move.l  d0,a2                ; a2 = ExpansionBase (préservé par exec + les fonctions exp_*)
        move.l  a2,a6
        jsr     EXP_LVO_ALLOCCONFIGDEV(a6)   ; d0 = ConfigDev | 0
        tst.l   d0
        beq     exp_close1
        move.l  d0,a3                ; a3 = ConfigDev
        move.w  #$0202,ER_MANUFACTURER(a3)   ; IDs de test (manufacturer word + product byte)
        move.b  #$42,ER_PRODUCT(a3)
        move.l  a2,a6                ; AddConfigDev(cd a0)
        move.l  a3,a0
        jsr     EXP_LVO_ADDCONFIGDEV(a6)
        move.l  a2,a6                ; FindConfigDev(0, $0202, $42) -> doit == a3
        suba.l  a0,a0
        move.l  #$0202,d0
        move.l  #$42,d1
        jsr     EXP_LVO_FINDCONFIGDEV(a6)
        cmp.l   a3,d0
        bne     exp_rem
        move.l  a2,a6                ; FindConfigDev(0, $0202, -1) wildcard produit -> a3
        suba.l  a0,a0
        move.l  #$0202,d0
        moveq   #-1,d1
        jsr     EXP_LVO_FINDCONFIGDEV(a6)
        cmp.l   a3,d0
        bne     exp_rem
        move.l  a2,a6                ; FindConfigDev(0, $9999, $42) -> pas de match -> 0
        suba.l  a0,a0
        move.l  #$9999,d0
        move.l  #$42,d1
        jsr     EXP_LVO_FINDCONFIGDEV(a6)
        tst.l   d0
        bne     exp_rem
        lea     msg_expansion_ok(pc),a0
        bsr     ser_puts             ; « EXPANSION OK »
exp_rem:
        tst.l   (a3)                 ; ln_Succ != 0 -> le ConfigDev est bien chaîné dans la liste
        beq.s   exp_freeonly
        move.l  ($4).w,a6
        move.l  a3,a1
        jsr     LVO_REMOVE(a6)       ; Remove(cd) avant free
exp_freeonly:
        move.l  a2,a6
        move.l  a3,a0
        jsr     EXP_LVO_FREECONFIGDEV(a6)
exp_close1:
        move.l  ($4).w,a6
        move.l  a2,a1
        jsr     LVO_CLOSELIBRARY(a6)
exp_done:
        move.l  ($4).w,a6            ; restaure a6 = ExecBase pour la suite (M6t)

        ; --- mathffp.library : table de vecteurs FFP (LVO, d0, d1, résultat attendu calculé hors ROM) ---
        ; Chaque appel passe par le vecteur LVO de la base ouverte ; un écart -> « MATHFFP FAIL » + LVO fautif.
        ; La boucle garde son état dans d4/d5/a2/a3 : une fonction qui ne préserve pas d2-d7 casse la preuve.
        movem.l d4-d5/a2-a3,-(sp)
        lea     mathffp_test_name(pc),a1
        moveq   #34,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   mft_done
        move.l  d0,a3
        lea     mft_table(pc),a2
        moveq   #(mft_table_end-mft_table)/14-1,d5
mft_lp:
        move.w  (a2)+,d4
        move.l  (a2)+,d0
        move.l  (a2)+,d1
        move.l  a3,a6
        jsr     0(a6,d4.w)
        cmp.l   (a2)+,d0
        bne.s   mft_fail
        dbra    d5,mft_lp
        lea     msg_mathffp_ok(pc),a0
        bsr     ser_puts
        bra.s   mft_close
mft_fail:
        lea     msg_mathffp_fail(pc),a0
        bsr     ser_puts
        move.w  d4,d0
        bsr     ser_puthex
        lea     msg_crlf_mft(pc),a0
        bsr     ser_puts
mft_close:
        move.l  ($4).w,a6
        move.l  a3,a1
        jsr     LVO_CLOSELIBRARY(a6)
mft_done:
        movem.l (sp)+,d4-d5/a2-a3
        move.l  ($4).w,a6

        ; --- disk.resource : AllocUnit/FreeUnit, GetUnitID, puis GetUnit/GiveUnit avec file d'attente ---
        ; dru1 prend le contrôleur (GetUnit rend le « dernier pilote », non nul et != dru1) ; dru2 est mis en attente
        ; (GetUnit = 0) ; GiveUnit lui fait ReplyMsg (sans port : LN_TYPE -> NT_REPLYMSG) ; dru2 retente et obtient
        ; dru1 comme dernier pilote. Les DRU vivent sur la pile : DR_CURRENT reste ensuite un simple témoin (jamais
        ; déréférencé hors possession du contrôleur). L'identifiant DF1 lu au démarrage est affiché.
        movem.l d4/a2-a4,-(sp)
        lea     diskres_test_name(pc),a1
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     drt_done
        move.l  d0,a2
        lea     -176(sp),sp
        move.l  sp,a3                ; a3 = dru1, a4 = dru2 (88 octets chacun, mis à zéro)
        lea     88(a3),a4
        move.l  a3,a0
        moveq   #43,d0
drt_clr:
        clr.l   (a0)+
        dbra    d0,drt_clr
        move.l  a2,a6
        moveq   #0,d0
        jsr     -6(a6)               ; AllocUnit(0) -> 1
        cmp.l   #1,d0
        bne     drt_fail
        moveq   #0,d0
        jsr     -6(a6)               ; déjà prise -> 0
        tst.l   d0
        bne     drt_fail
        moveq   #0,d0
        jsr     -12(a6)              ; FreeUnit(0)
        moveq   #0,d0
        jsr     -6(a6)               ; de nouveau libre -> 1
        cmp.l   #1,d0
        bne     drt_fail
        moveq   #0,d0
        jsr     -12(a6)
        moveq   #4,d0
        jsr     -6(a6)               ; unité invalide -> 0
        tst.l   d0
        bne     drt_fail
        moveq   #0,d0
        jsr     -30(a6)              ; GetUnitID(0) = DRT_AMIGA
        tst.l   d0
        bne     drt_fail
        moveq   #1,d0
        jsr     -30(a6)
        move.l  d0,d4                ; d4 = identifiant DF1
        move.l  a3,a1
        jsr     -18(a6)              ; GetUnit(dru1) : libre
        tst.l   d0
        beq     drt_fail
        cmp.l   a3,d0
        beq     drt_fail
        move.b  #NT_MESSAGE,LN_TYPE(a4)
        move.l  a4,a1
        jsr     -18(a6)              ; GetUnit(dru2) : occupé -> 0, mis en attente
        tst.l   d0
        bne     drt_fail
        jsr     -24(a6)              ; GiveUnit -> ReplyMsg(dru2)
        cmp.b   #NT_REPLYMSG,LN_TYPE(a4)
        bne     drt_fail
        move.l  a4,a1
        jsr     -18(a6)              ; dru2 retente : dernier pilote = dru1
        cmp.l   a3,d0
        bne     drt_fail
        jsr     -24(a6)
        lea     msg_diskres_ok(pc),a0
        bsr     ser_puts
        move.l  d4,d0
        swap    d0
        bsr     ser_puthex
        move.l  d4,d0
        bsr     ser_puthex
        lea     msg_crlf_mft(pc),a0
        bsr     ser_puts
        bra.s   drt_free
drt_fail:
        lea     msg_diskres_fail(pc),a0
        bsr     ser_puts
drt_free:
        lea     176(sp),sp
drt_done:
        movem.l (sp)+,d4/a2-a4
        move.l  ($4).w,a6

        ; --- potgo.resource : règles d'attribution START / DATxx + conservation de l'octet haut par WritePotgo ---
        ; (attendus : AutoDoc AllocPotBits ; un appelant peut se bloquer lui-même, la ressource ne suit pas les
        ; propriétaires). POTGO est remis à 0 (toutes broches en entrée, valeur de reset) à la fin.
        move.l  a2,-(sp)
        lea     potgo_test_name(pc),a1
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     pgt_done
        move.l  d0,a6
        move.l  d0,a2
        move.w  #$0101,d0
        jsr     -6(a6)               ; START + DATLX en entrée -> accordés
        cmp.w   #$0101,d0
        bne     pgt_fail
        move.w  #$0400,d0
        jsr     -6(a6)               ; DATLY en entrée alors que START est tenu -> refusé
        tst.w   d0
        bne     pgt_fail
        move.w  #$0C00,d0
        jsr     -6(a6)               ; DATLY en sortie -> accordé
        cmp.w   #$0400,d0
        bne     pgt_fail
        move.w  #$0100,d0
        jsr     -6(a6)               ; DATLX déjà pris -> refusé
        tst.w   d0
        bne     pgt_fail
        move.w  #$0101,d0
        jsr     -12(a6)              ; FreePotBits(START + DATLX)
        moveq   #1,d0
        jsr     -6(a6)               ; START : seul DATLY (sortie) reste pris -> accordé
        cmp.w   #1,d0
        bne     pgt_fail
        move.w  #$0401,d0
        jsr     -12(a6)
        move.w  #$0C01,d0
        move.w  #$0C01,d1
        jsr     -18(a6)              ; WritePotgo : octet haut conservé, START non conservé
        cmp.w   #$0C00,LIB_SIZE+2(a2)
        bne     pgt_fail
        moveq   #0,d0
        move.w  #$FF00,d1
        jsr     -18(a6)
        tst.w   LIB_SIZE+2(a2)
        bne     pgt_fail
        lea     msg_potgo_ok(pc),a0
        bsr     ser_puts
        bra.s   pgt_done
pgt_fail:
        lea     msg_potgo_fail(pc),a0
        bsr     ser_puts
pgt_done:
        move.l  (sp)+,a2
        move.l  ($4).w,a6

        ; --- keyboard.device : matrice, KBD_READEVENT (tampon / requête en attente rendue par l'événement),
        ; CMD_CLEAR, AbortIO, liste des gestionnaires de reset. Keycodes SYNTHÉTIQUES remis à kbd_devevent (le même
        ; point d'entrée que kbd_interrupt) ; la matrice est rendue vide (touches relâchées) et le tampon vidé.
        ; Pile : IOStdReq 48 o, tampon 24 o (InputEvent / matrice), struct Interrupt 24 o.
        movem.l a2-a3,-(sp)
        lea     -96(sp),sp
        move.l  sp,a3
        move.l  a3,a0
        moveq   #23,d0
kdt_clr:
        clr.l   (a0)+
        dbra    d0,kdt_clr
        lea     kbddev_test_name(pc),a0
        moveq   #0,d0
        move.l  a3,a1
        moveq   #0,d1
        jsr     LVO_OPENDEVICE(a6)
        tst.b   d0
        bne     kdt_fail0
        move.l  IO_DEVICE(a3),a2
        bsr     kdt_matrix           ; matrice vide au départ (touches $20-$27 = octet 4)
        tst.l   48+4(a3)
        bne     kdt_fail
        moveq   #$20,d0              ; « A » enfoncée
        jsr     kbd_devevent
        bsr     kdt_matrix
        cmp.b   #1,48+4(a3)
        bne     kdt_fail
        move.b  #IOF_QUICK_K,IO_FLAGS(a3)
        bsr     kdt_read             ; servie depuis le tampon
        cmp.b   #IECLASS_RAWKEY,48+IE_CLASS(a3)
        bne     kdt_fail
        cmp.w   #$20,48+IE_CODE(a3)
        bne     kdt_fail
        cmp.l   #IE_SIZEOF,KDT_ACTUAL(a3)
        bne     kdt_fail
        move.l  #$A0,d0              ; « A » relâchée
        jsr     kbd_devevent
        bsr     kdt_matrix
        tst.b   48+4(a3)
        bne     kdt_fail
        bsr     kdt_clear
        clr.b   IO_FLAGS(a3)         ; tampon vide : la requête attend un événement
        move.b  #NT_MESSAGE,LN_TYPE(a3)
        bsr     kdt_read
        cmp.b   #NT_MESSAGE,LN_TYPE(a3)
        bne     kdt_fail
        moveq   #$45,d0              ; Échap enfoncée -> rend la requête en attente
        jsr     kbd_devevent
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne     kdt_fail
        cmp.w   #$45,48+IE_CODE(a3)
        bne     kdt_fail
        move.l  #$C5,d0              ; Échap relâchée (tamponnée puis effacée)
        jsr     kbd_devevent
        bsr     kdt_clear
        move.b  #NT_MESSAGE,LN_TYPE(a3)
        move.b  #IOF_QUICK_K,IO_FLAGS(a3)
        bsr     kdt_read             ; rien en tampon : IOF_QUICK effacé, requête en attente
        btst    #0,IO_FLAGS(a3)
        bne     kdt_fail
        move.l  a3,a1
        move.l  a2,a6
        jsr     -36(a6)              ; AbortIO
        move.l  ($4).w,a6
        cmp.b   #IOERR_ABORTED,IO_ERROR(a3)
        bne     kdt_fail
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne     kdt_fail
        lea     72(a3),a0            ; gestionnaire de reset : ajouté puis retiré
        move.b  #NT_INTERRUPT,LN_TYPE(a0)
        move.l  a0,KDT_DATA(a3)
        move.w  #11,IO_COMMAND(a3)   ; KBD_ADDRESETHANDLER
        bsr     kdt_io
        lea     72(a3),a0
        cmp.l   LIB_SIZE+30(a2),a0   ; tête de la liste des gestionnaires
        bne     kdt_fail
        move.w  #12,IO_COMMAND(a3)   ; KBD_REMRESETHANDLER
        bsr     kdt_io
        move.l  LIB_SIZE+30(a2),a0
        tst.l   (a0)                 ; liste vide : la tête est le nœud de queue
        bne     kdt_fail
        lea     msg_kbddev_ok(pc),a0
        bsr     ser_puts
        bra.s   kdt_close
kdt_fail:
        lea     msg_kbddev_fail(pc),a0
        bsr     ser_puts
kdt_close:
        move.l  a3,a1
        jsr     LVO_CLOSEDEVICE(a6)
        bra.s   kdt_done
kdt_fail0:
        lea     msg_kbddev_fail(pc),a0
        bsr     ser_puts
kdt_done:
        lea     96(sp),sp
        movem.l (sp)+,a2-a3
        move.l  ($4).w,a6
        bra     kdt_end
; sous-routines de la sonde keyboard.device (a3 = IOStdReq, a2 = device ; rendent a6 = SysBase)
kdt_matrix:
        move.w  #10,IO_COMMAND(a3)   ; KBD_READMATRIX
        move.b  #IOF_QUICK_K,IO_FLAGS(a3)
        moveq   #16,d0
        bra.s   kdt_rd2
kdt_read:
        move.w  #9,IO_COMMAND(a3)    ; KBD_READEVENT
        moveq   #IE_SIZEOF,d0
kdt_rd2:
        move.l  d0,KDT_LENGTH(a3)
        lea     48(a3),a0
        move.l  a0,KDT_DATA(a3)
kdt_io:
        move.l  a3,a1
        move.l  a2,a6
        jsr     -30(a6)              ; BeginIO
        move.l  ($4).w,a6
        rts
kdt_clear:
        move.w  #5,IO_COMMAND(a3)    ; CMD_CLEAR
        move.b  #IOF_QUICK_K,IO_FLAGS(a3)
        bra.s   kdt_io
kdt_end:

        ; --- audio.device : attribution (sans DMA ni interruption : synchrone au boot) ---
        ; ioa1 = canal 0 à pri 0 ; ioa2 à pri -10 ne peut pas le voler (ALLOCFAILED) mais obtient le canal 1 par la
        ; 2e combinaison ; ioa3 à pri 10 vole le canal 0 (la clé de ioa1 n'y vaut plus : NOALLOCATION) ; ioa3 le
        ; verrouille ; ioa2 à pri 20 le réclame : le verrou est rendu ADIOERR_CHANNELSTOLEN et ioa2 attend ; ioa3
        ; libère -> ioa2 est servi par le réessai. Pile : 3 IOAudio (72 o chacun).
        movem.l a2-a3,-(sp)
        lea     -216(sp),sp
        move.l  sp,a3
        move.l  a3,a0
        moveq   #53,d0
aut_clr:
        clr.l   (a0)+
        dbra    d0,aut_clr
        lea     audio_test_name(pc),a0
        moveq   #0,d0
        move.l  a3,a1
        moveq   #0,d1
        jsr     LVO_OPENDEVICE(a6)
        tst.b   d0
        bne     aut_fail0
        move.l  IO_DEVICE(a3),a2
        tst.w   AUT_KEY(a3)
        beq     aut_fail
        move.l  a2,IO_DEVICE+72(a3)
        move.l  a2,IO_DEVICE+144(a3)
        lea     0(a3),a1             ; ioa1 : canal 0, pri 0
        lea     aut_ch0(pc),a0
        moveq   #0,d0
        bsr     aut_alloc
        bne     aut_fail
        cmp.b   #1,IO_UNIT+3(a3)
        bne     aut_fail
        lea     72(a3),a1            ; ioa2 : canal 0 à pri -10 -> refusé
        lea     aut_ch0(pc),a0
        moveq   #-10,d0
        bsr     aut_alloc
        cmp.b   #-11,d0
        bne     aut_fail
        lea     72(a3),a1            ; ioa2 : {canal 0, canal 1} -> canal 1 (sans vol)
        lea     aut_ch0or1(pc),a0
        moveq   #-10,d0
        moveq   #2,d1
        bsr     aut_allocn
        bne     aut_fail
        cmp.b   #2,IO_UNIT+3+72(a3)
        bne     aut_fail
        move.w  AUT_KEY+72(a3),d0
        cmp.w   AUT_KEY(a3),d0
        beq     aut_fail             ; clés distinctes
        lea     72(a3),a1            ; ioa2 libère le canal 1
        moveq   #9,d0                ; ADCMD_FREE
        bsr     aut_cmd
        bne     aut_fail
        lea     144(a3),a1           ; ioa3 : canal 0 à pri 10 -> vol
        lea     aut_ch0(pc),a0
        moveq   #10,d0
        bsr     aut_alloc
        bne     aut_fail
        cmp.b   #1,IO_UNIT+3+144(a3)
        bne     aut_fail
        move.b  #1,IO_UNIT+3(a3)     ; ioa1 : CMD_RESET du canal volé -> NOALLOCATION
        lea     0(a3),a1
        moveq   #1,d0
        bsr     aut_cmd
        cmp.b   #-10,d0
        bne     aut_fail
        lea     144(a3),a1           ; ioa3 : ADCMD_LOCK (asynchrone)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        clr.b   IO_FLAGS(a1)
        move.w  #13,IO_COMMAND(a1)
        bsr     aut_io
        cmp.b   #NT_MESSAGE,LN_TYPE+144(a3)
        bne     aut_fail
        lea     72(a3),a1            ; ioa2 : canal 0 à pri 20 -> verrou volé, attente (malgré NOWAIT)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        lea     aut_ch0(pc),a0
        moveq   #20,d0
        bsr     aut_alloc
        cmp.b   #NT_REPLYMSG,LN_TYPE+144(a3)
        bne     aut_fail
        cmp.b   #-12,IO_ERROR+144(a3)
        bne     aut_fail
        cmp.b   #NT_MESSAGE,LN_TYPE+72(a3)
        bne     aut_fail
        lea     144(a3),a1           ; ioa3 libère -> ioa2 servi
        move.b  #1,IO_UNIT+3(a1)
        moveq   #9,d0
        bsr     aut_cmd
        bne     aut_fail
        cmp.b   #NT_REPLYMSG,LN_TYPE+72(a3)
        bne     aut_fail
        tst.b   IO_ERROR+72(a3)
        bne     aut_fail
        cmp.b   #1,IO_UNIT+3+72(a3)
        bne     aut_fail
        lea     72(a3),a1
        moveq   #9,d0
        bsr     aut_cmd
        lea     msg_audio_ok(pc),a0
        bsr     ser_puts
        bra.s   aut_close
aut_fail:
        lea     msg_audio_fail(pc),a0
        bsr     ser_puts
aut_close:
        move.l  a3,a1
        jsr     LVO_CLOSEDEVICE(a6)
        bra.s   aut_done
aut_fail0:
        lea     msg_audio_fail(pc),a0
        bsr     ser_puts
aut_done:
        lea     216(sp),sp
        movem.l (sp)+,a2-a3
        move.l  ($4).w,a6
        bra     aut_end
; sous-routines (a1 = IOAudio, a2 = device) -> d0.b = io_Error, codes conditions posés ; a6 = SysBase en sortie
aut_alloc:
        moveq   #1,d1
aut_allocn:
        move.b  d0,LN_PRI(a1)
        move.l  a0,AUT_DATA(a1)
        move.l  d1,AUT_LENGTH(a1)
        moveq   #32,d0               ; ADCMD_ALLOCATE
aut_cmd:
        move.w  d0,IO_COMMAND(a1)
        move.b  #$41,IO_FLAGS(a1)    ; IOF_QUICK | ADIOF_NOWAIT
aut_io:
        move.l  a1,-(sp)
        move.l  a2,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        move.l  (sp)+,a1
        move.b  IO_ERROR(a1),d0
        rts
aut_ch0:
        dc.b    $01
aut_ch0or1:
        dc.b    $01,$02
        EVEN
aut_end:

        ; --- sémaphores d'exec : publication (Add/Find), Attempt + Obtain imbriqués, Release jusqu'à libre. En dev,
        ; le sémaphore reste PRIS pour task_semw (bloquée dans Obtain) que task_semr débloque par Release. ---
        move.l  a2,-(sp)
        moveq   #SEMT_SIZE,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     semt_done
        move.l  d0,a2
        lea     semt_name(pc),a0
        move.l  a0,LN_NAME(a2)
        move.l  a2,a1
        jsr     LVO_ADDSEMAPHORE(a6)
        lea     semt_name(pc),a1
        jsr     LVO_FINDSEMAPHORE(a6)
        cmp.l   a2,d0
        bne     semt_fail
        cmp.w   #-1,SEMT_QC(a2)
        bne     semt_fail
        move.l  a2,a0
        jsr     LVO_ATTEMPTSEMAPHORE(a6)
        cmp.l   #1,d0
        bne     semt_fail
        move.l  a2,a0
        jsr     LVO_OBTAINSEMAPHORE(a6)    ; imbriqué : ne bloque pas
        cmp.w   #2,SEMT_NEST(a2)
        bne     semt_fail
        cmp.w   #1,SEMT_QC(a2)
        bne     semt_fail
        move.l  a2,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        move.l  a2,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        cmp.w   #-1,SEMT_QC(a2)
        bne     semt_fail
        tst.w   SEMT_NEST(a2)
        bne     semt_fail
        tst.l   SEMT_OWNER(a2)
        bne     semt_fail
        lea     msg_sem_ok(pc),a0
        bsr     ser_puts
                ifeq    PROD
        move.l  a2,a0
        jsr     LVO_OBTAINSEMAPHORE(a6)    ; tenu pour la preuve d'attente (task_semw / task_semr)
        bra.s   semt_done
                else
        bra.s   semt_free
                endc
semt_fail:
        lea     msg_sem_fail(pc),a0
        bsr     ser_puts
semt_free:
        move.l  a2,a1
        jsr     LVO_REMSEMAPHORE(a6)
        move.l  a2,a1
        moveq   #SEMT_SIZE,d0
        jsr     LVO_FREEMEM(a6)
semt_done:
        move.l  (sp)+,a2

        ; --- graphics Regions : Or/And/ClearRect/Xor sur rectangles puis Or/Xor/And de régions ; aires, bornes et
        ; appartenance de points comparées à un modèle par ensembles de pixels (calcul hors ROM). ---
        movem.l d2/a2-a5,-(sp)
        lea     graphics_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     rgt_done
        exg     a5,a6
        jsr     -516(a6)             ; R1 = NewRegion
        move.l  d0,a2
        jsr     -516(a6)             ; R2
        move.l  d0,a3
        jsr     -516(a6)             ; R3
        move.l  d0,a4
        move.l  a2,d0
        beq     rgt_fail
        move.l  a3,d0
        beq     rgt_fail
        move.l  a4,d0
        beq     rgt_fail
        lea     rgt_rects(pc),a1
        move.l  a2,a0
        jsr     -510(a6)             ; R1 |= (0,0,9,9)
        lea     rgt_rects+8(pc),a1
        move.l  a2,a0
        jsr     -510(a6)             ; R1 |= (5,5,14,14)
        move.l  #175,d2
        bsr     rgt_check1
        bne     rgt_fail
        lea     rgt_rects+16(pc),a1
        move.l  a2,a0
        jsr     -504(a6)             ; R1 &= (3,3,11,11)
        moveq   #73,d2
        bsr     rgt_check1
        bne     rgt_fail
        lea     rgt_rects+24(pc),a1
        move.l  a2,a0
        jsr     -522(a6)             ; R1 -= (6,6,7,7)
        moveq   #69,d2
        bsr     rgt_check1
        bne     rgt_fail
        lea     rgt_rects+32(pc),a1
        move.l  a2,a0
        jsr     -558(a6)             ; R1 ^= (10,10,21,21)
        move.l  #205,d2
        bsr     rgt_check1
        bne     rgt_fail
        cmp.l   #$00030003,(a2)      ; bornes (3,3,21,21)
        bne     rgt_fail
        cmp.l   #$00150015,4(a2)
        bne     rgt_fail
        lea     rgt_pts(pc),a1       ; points : (x, y, attendu)
        moveq   #7,d2
rgt_pt:
        move.w  (a1)+,d0
        move.w  (a1)+,d1
        move.l  a2,a0
        bsr     rgt_has
        cmp.w   (a1)+,d0
        bne     rgt_fail
        dbra    d2,rgt_pt
        lea     rgt_rects+40(pc),a1
        move.l  a3,a0
        jsr     -510(a6)             ; R2 = (3,3,4,4) | (30,0,31,1)
        lea     rgt_rects+48(pc),a1
        move.l  a3,a0
        jsr     -510(a6)
        move.l  a2,a0
        move.l  a4,a1
        jsr     -612(a6)             ; R3 = R1
        move.l  a3,a0
        move.l  a4,a1
        jsr     -612(a6)             ; R3 |= R2
        move.l  a4,a0
        bsr     rgt_area
        cmp.l   #209,d0
        bne     rgt_fail
        cmp.l   #$00030000,(a4)      ; bornes (3,0,31,21)
        bne     rgt_fail
        cmp.l   #$001F0015,4(a4)
        bne     rgt_fail
        move.l  a4,a0
        jsr     -528(a6)             ; ClearRegion(R3)
        tst.l   8(a4)
        bne     rgt_fail
        move.l  a2,a0
        move.l  a4,a1
        jsr     -612(a6)             ; R3 = R1
        move.l  a3,a0
        move.l  a4,a1
        jsr     -618(a6)             ; R3 ^= R2
        move.l  a4,a0
        bsr     rgt_area
        cmp.l   #205,d0
        bne     rgt_fail
        move.l  a3,a0
        move.l  a2,a1
        jsr     -624(a6)             ; R1 &= R2
        move.l  a2,a0
        bsr     rgt_area
        cmp.l   #4,d0
        bne     rgt_fail
        cmp.l   #$00030003,(a2)
        bne     rgt_fail
        cmp.l   #$00040004,4(a2)
        bne     rgt_fail
        lea     msg_regions_ok(pc),a0
        bra.s   rgt_msg
rgt_fail:
        lea     msg_regions_fail(pc),a0
rgt_msg:
        exg     a5,a6
        bsr     ser_puts
        exg     a5,a6
        move.l  a2,a0
        jsr     -534(a6)             ; DisposeRegion (0 accepté)
        move.l  a3,a0
        jsr     -534(a6)
        move.l  a4,a0
        jsr     -534(a6)
        exg     a5,a6
        move.l  a5,a1
        jsr     LVO_CLOSELIBRARY(a6)
rgt_done:
        movem.l (sp)+,d2/a2-a5
        bra     rgt_end
; rgt_check1 : aire de R1 (a2) comparée à d2 -> Z si égale.
rgt_check1:
        move.l  a2,a0
        bsr.s   rgt_area
        cmp.l   d2,d0
        rts
; rgt_area(a0 = région) -> d0 = somme des aires de ses rectangles.
rgt_area:
        moveq   #0,d0
        move.l  8(a0),a0
rgt_ar:
        cmpa.w  #0,a0
        beq.s   rgt_ar_r
        move.w  14(a0),d1
        sub.w   10(a0),d1
        addq.w  #1,d1
        move.w  d1,-(sp)             ; hauteur
        move.w  12(a0),d1
        sub.w   8(a0),d1
        addq.w  #1,d1                ; largeur
        mulu    (sp)+,d1
        add.l   d1,d0
        move.l  (a0),a0
        bra.s   rgt_ar
rgt_ar_r:
        rts
; rgt_has(a0 = région, d0 = x, d1 = y) -> d0.w = 1 si le point est dans la région, sinon 0. Préserve a1.
rgt_has:
        sub.w   (a0),d0
        sub.w   2(a0),d1
        move.l  8(a0),a0
rgt_hl:
        cmpa.w  #0,a0
        beq.s   rgt_hno
        cmp.w   8(a0),d0
        blt.s   rgt_hn
        cmp.w   12(a0),d0
        bgt.s   rgt_hn
        cmp.w   10(a0),d1
        blt.s   rgt_hn
        cmp.w   14(a0),d1
        bgt.s   rgt_hn
        moveq   #1,d0
        rts
rgt_hn:
        move.l  (a0),a0
        bra.s   rgt_hl
rgt_hno:
        moveq   #0,d0
        rts
rgt_rects:
        dc.w    0,0,9,9, 5,5,14,14, 3,3,11,11, 6,6,7,7, 10,10,21,21, 3,3,4,4, 30,0,31,1
rgt_pts:
        dc.w    3,3,1, 6,6,0, 7,8,1, 10,10,0, 11,11,0, 12,12,1, 21,21,1, 0,0,0
rgt_end:

        ; --- polices (graphics) : OpenFont topaz 8 = police par défaut (accès compté), topaz 9 -> la plus proche (8),
        ; nom inconnu -> 0 ; InitRastPort pose la police par défaut ; TextLength (espacement compris) ; styles
        ; logiciels (italique refusé) ; Text en gras de « I » dans un BitMap 32x8 relu : glyphe | glyphe >> 1. ---
FNT_RP          EQU 0                ; RastPort (100 octets)
FNT_BM          EQU 100              ; BitMap (40)
FNT_DATA        EQU 140              ; plan 32x8 (32)
FNT_FRAME       EQU 172
        movem.l d2-d3/a2-a5,-(sp)
        lea     graphics_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     fnt_done
        exg     a5,a6                ; a6 = GfxBase, a5 = SysBase
        lea     -FNT_FRAME(sp),sp
        move.l  sp,a4
        lea     fnt_ta8(pc),a0
        jsr     -72(a6)              ; OpenFont(topaz 8)
        move.l  d0,a2
        cmp.l   154(a6),d0           ; gb_DefaultFont
        bne     fnt_fail
        tst.l   d0
        beq     fnt_fail
        move.w  30(a2),d3            ; tf_Accessors après l'ouverture
        lea     fnt_ta9(pc),a0
        jsr     -72(a6)              ; OpenFont(topaz 9) -> topaz 8
        cmp.l   a2,d0
        bne     fnt_fail
        addq.w  #1,d3
        cmp.w   30(a2),d3
        bne     fnt_fail
        lea     fnt_tanone(pc),a0
        jsr     -72(a6)
        tst.l   d0
        bne     fnt_fail
        move.l  a2,a1
        jsr     -78(a6)              ; CloseFont x2
        move.l  a2,a1
        jsr     -78(a6)
        subq.w  #2,d3
        cmp.w   30(a2),d3
        bne     fnt_fail
        lea     FNT_RP(a4),a1
        jsr     -198(a6)             ; InitRastPort
        cmp.l   FNT_RP+52(a4),a2     ; rp_Font
        bne     fnt_fail
        cmp.l   #$00080008,FNT_RP+58(a4)   ; TxHeight, TxWidth
        bne     fnt_fail
        cmp.w   #6,FNT_RP+62(a4)     ; TxBaseline
        bne     fnt_fail
        lea     FNT_RP(a4),a1
        lea     fnt_abc(pc),a0
        moveq   #3,d0
        jsr     -54(a6)              ; TextLength("Abc") = 24
        cmp.l   #24,d0
        bne     fnt_fail
        move.w  #2,FNT_RP+64(a4)     ; TxSpacing = 2 -> 30
        lea     FNT_RP(a4),a1
        lea     fnt_abc(pc),a0
        moveq   #3,d0
        jsr     -54(a6)
        cmp.l   #30,d0
        bne     fnt_fail
        clr.w   FNT_RP+64(a4)
        lea     FNT_RP(a4),a1
        jsr     -84(a6)              ; AskSoftStyle = souligné | gras
        cmp.l   #3,d0
        bne     fnt_fail
        lea     FNT_RP(a4),a1
        moveq   #6,d0                ; gras | italique
        moveq   #-1,d1
        jsr     -90(a6)              ; SetSoftStyle -> gras seul
        cmp.l   #2,d0
        bne     fnt_fail
        cmp.b   #2,FNT_RP+56(a4)     ; rp_AlgoStyle
        bne     fnt_fail
        lea     FNT_BM(a4),a0
        moveq   #1,d0
        moveq   #32,d1
        moveq   #8,d2
        jsr     -390(a6)             ; InitBitMap(1 plan, 32x8)
        lea     FNT_DATA(a4),a0
        move.l  a0,FNT_BM+8(a4)
        moveq   #7,d0
fnt_clr:
        clr.l   (a0)+
        dbra    d0,fnt_clr
        lea     FNT_BM(a4),a0
        move.l  a0,FNT_RP+4(a4)      ; rp_BitMap
        clr.b   FNT_RP+28(a4)        ; JAM1
        move.l  #$00000006,FNT_RP+36(a4)   ; cp = (0, ligne de base 6)
        lea     FNT_RP(a4),a1
        lea     fnt_i(pc),a0
        moveq   #1,d0
        jsr     -60(a6)              ; Text("I")
        cmp.w   #8,FNT_RP+36(a4)     ; cp_x avancé de 8
        bne     fnt_fail
        lea     font8x8+($49-$20)*8,a0
        lea     FNT_DATA(a4),a1
        moveq   #7,d2
fnt_row:
        moveq   #0,d0
        move.b  (a0)+,d0
        move.w  d0,d1
        lsl.w   #8,d1
        lsl.w   #7,d0
        or.w    d0,d1                ; gras : pixels du glyphe et leurs voisins de droite (9 pixels)
        cmp.b   1(a1),d1
        bne     fnt_fail
        lsr.w   #8,d1
        cmp.b   (a1),d1
        bne     fnt_fail
        tst.w   2(a1)
        bne     fnt_fail
        addq.l  #4,a1
        dbra    d2,fnt_row
        lea     msg_fonts_ok(pc),a0
        bra.s   fnt_msg
fnt_fail:
        lea     msg_fonts_fail(pc),a0
fnt_msg:
        exg     a5,a6
        bsr     ser_puts
        lea     FNT_FRAME(sp),sp
        move.l  a5,a1
        jsr     LVO_CLOSELIBRARY(a6)
fnt_done:
        movem.l (sp)+,d2-d3/a2-a5

        ; --- GELs (graphics) : Bob 16x4x2 (OVERLAY + SAVEBACK, masque d'InitMasks) posé à x non aligné sur un fond
        ; de couleur 1 et relu au pixel (zone hors masque transparente) ; collision avec un VSprite (CollMask) ->
        ; routine 1 ; déplacement : fond d'origine restauré, nouvelle position dessinée et découpée au bord ; sortie
        ; à droite des bornes -> routine 0 (RIGHTHIT) ; SortGList ; RemIBob restaure le fond. ---
GLT_GI          EQU 0
GLT_HEAD        EQU 40
GLT_TAIL        EQU 100
GLT_COLL        EQU 160
GLT_VS1         EQU 224
GLT_BOB         EQU 284
GLT_VS2         EQU 316
GLT_RP          EQU 376
GLT_BM          EQU 476
GLT_PL0         EQU 516
GLT_PL1         EQU 580
GLT_IMG         EQU 644
GLT_MASK        EQU 660
GLT_BORD        EQU 668
GLT_SAVE        EQU 670
GLT_MASK2       EQU 686
GLT_OB          EQU 696              ; AnimOb (42)
GLT_CA          EQU 740              ; AnimComp A, B (38)
GLT_CB          EQU 780
GLT_BA          EQU 820              ; leurs Bobs (32) et VSprites (60)
GLT_BB          EQU 852
GLT_VA          EQU 884
GLT_VB          EQU 944
GLT_KEY         EQU 1004
GLT_SIZE        EQU 1008
        movem.l d2-d3/a2-a5,-(sp)
        lea     graphics_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a5                ; a5 = GfxBase
        tst.l   d0
        beq     glt_done
        move.l  #GLT_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a4
        tst.l   d0
        beq     glt_close
        exg     a5,a6                ; a6 = GfxBase, a5 = SysBase
        lea     GLT_IMG(a4),a0       ; image : plan 0 = $FF00, plan 1 = $F0F0 (couleurs 3,1,2,- par quart)
        moveq   #3,d0
glt_img:
        move.w  #$FF00,(a0)
        move.w  #$F0F0,8(a0)
        move.w  #$FFFF,GLT_MASK2-GLT_IMG(a0)
        addq.l  #2,a0
        dbra    d0,glt_img
        lea     GLT_VS1(a4),a0
        move.w  #6,20(a0)            ; SAVEBACK | OVERLAY
        move.l  #$00020003,22(a0)    ; Y = 2, X = 3
        move.l  #$00040001,26(a0)    ; Height 4, Width 1 mot
        move.w  #2,30(a0)            ; Depth
        move.l  #$00020003,32(a0)    ; MeMask = 2, HitMask = 3 (bord + type 1)
        lea     GLT_IMG(a4),a1
        move.l  a1,36(a0)
        lea     GLT_BORD(a4),a1
        move.l  a1,40(a0)
        lea     GLT_MASK(a4),a1
        move.l  a1,44(a0)
        lea     GLT_BOB(a4),a1
        move.l  a1,52(a0)
        move.b  #3,56(a0)            ; PlanePick
        move.l  a0,18(a1)            ; bob->BobVSprite
        lea     GLT_SAVE(a4),a0
        move.l  a0,2(a1)             ; SaveBuffer
        lea     GLT_MASK(a4),a0
        move.l  a0,6(a1)             ; ImageShadow
        lea     GLT_VS2(a4),a0
        move.w  #1,20(a0)            ; VSPRITE
        move.l  #$00040008,22(a0)    ; Y = 4, X = 8
        move.l  #$00040001,26(a0)
        move.l  #$00020002,32(a0)
        lea     GLT_MASK2(a4),a1
        move.l  a1,44(a0)
        lea     GLT_GI(a4),a0
        lea     GLT_COLL(a4),a1
        move.l  a1,18(a0)            ; collHandler
        move.l  #$0000001F,22(a0)    ; leftmost 0, rightmost 31
        move.l  #$0000000F,26(a0)    ; topmost 0, bottommost 15
        lea     GLT_BM(a4),a0
        moveq   #2,d0
        moveq   #32,d1
        moveq   #16,d2
        jsr     -390(a6)             ; InitBitMap
        lea     GLT_PL0(a4),a0
        move.l  a0,GLT_BM+8(a4)
        lea     GLT_PL1(a4),a0
        move.l  a0,GLT_BM+12(a4)
        lea     GLT_RP(a4),a1
        jsr     -198(a6)             ; InitRastPort
        lea     GLT_BM(a4),a0
        move.l  a0,GLT_RP+4(a4)
        lea     GLT_GI(a4),a0
        move.l  a0,GLT_RP+20(a4)     ; rp_GelsInfo
        lea     GLT_RP(a4),a1
        moveq   #1,d0
        jsr     -234(a6)             ; SetRast(1)
        lea     GLT_HEAD(a4),a0
        lea     GLT_TAIL(a4),a1
        lea     GLT_GI(a4),a2
        jsr     -120(a6)             ; InitGels
        lea     GLT_VS1(a4),a0
        jsr     -126(a6)             ; InitMasks
        cmp.l   #$FFF0FFF0,GLT_MASK(a4)
        bne     glt_fail
        cmp.w   #$FFF0,GLT_BORD(a4)
        bne     glt_fail
        moveq   #0,d0
        lea     glt_coll0(pc),a0
        lea     GLT_GI(a4),a1
        jsr     -144(a6)             ; SetCollision(0)
        moveq   #1,d0
        lea     glt_coll1(pc),a0
        lea     GLT_GI(a4),a1
        jsr     -144(a6)             ; SetCollision(1)
        lea     GLT_BOB(a4),a0
        lea     GLT_RP(a4),a1
        jsr     -96(a6)              ; AddBob
        lea     GLT_RP(a4),a1
        suba.l  a0,a0
        jsr     -114(a6)             ; DrawGList
        lea     glt_px1(pc),a2
        bsr     glt_check
        bne     glt_fail
        lea     GLT_VS2(a4),a0
        lea     GLT_RP(a4),a1
        jsr     -102(a6)             ; AddVSprite
        lea     GLT_RP(a4),a1
        jsr     -108(a6)             ; DoCollision : Bob x VSprite -> routine 1
        cmp.w   #1,GLT_VS1+58(a4)
        bne     glt_fail
        cmp.w   #1,GLT_VS2+58(a4)
        bne     glt_fail
        move.l  #$00080014,GLT_VS1+22(a4)   ; Y = 8, X = 20
        lea     GLT_RP(a4),a1
        jsr     -150(a6)             ; SortGList : VSprite (Y 4) puis Bob (Y 8)
        lea     GLT_VS2(a4),a0
        cmp.l   GLT_HEAD(a4),a0
        bne     glt_fail
        lea     GLT_RP(a4),a1
        suba.l  a0,a0
        jsr     -114(a6)             ; DrawGList
        lea     glt_px2(pc),a2
        bsr     glt_check
        bne     glt_fail
        lea     GLT_RP(a4),a1
        jsr     -108(a6)             ; DoCollision : bord droit -> routine 0
        cmp.w   #8,GLT_VS1+58(a4)    ; RIGHTHIT
        bne     glt_fail
        cmp.w   #1,GLT_VS2+58(a4)    ; plus de chevauchement
        bne     glt_fail
        lea     GLT_BOB(a4),a0
        lea     GLT_RP(a4),a1
        suba.l  a2,a2
        jsr     -132(a6)             ; RemIBob
        lea     glt_px3(pc),a2
        bsr     glt_check
        bne     glt_fail
        btst    #3,GLT_BOB(a4)       ; BOBNIX
        beq     glt_fail
        lea     GLT_VS2(a4),a0
        cmp.l   GLT_HEAD(a4),a0      ; head->Next = VSprite
        bne     glt_fail
        ; animation : composants A et B en anneau (TimeSet 2), objet en (5, 7) + 1 pixel/appel en X (fraction 6 bits)
        lea     GLT_OB(a4),a0
        move.l  #(5<<6)<<16|(7<<6),16(a0)  ; AnY, AnX
        move.w  #1<<6,22(a0)         ; XVel
        lea     GLT_CA(a4),a1
        move.l  a1,36(a0)            ; HeadComp = A
        lea     GLT_CB(a4),a2
        move.w  #2,4(a1)
        move.w  #2,4(a2)
        move.l  a2,14(a1)            ; A.NextSeq = B
        move.l  a1,14(a2)            ; B.NextSeq = A
        move.l  #$00010002,26(a1)    ; A : YTrans 1, XTrans 2
        lea     GLT_BA(a4),a0
        move.l  a0,34(a1)
        lea     GLT_VA(a4),a1
        move.l  a1,18(a0)
        lea     GLT_BB(a4),a0
        move.l  a0,34(a2)
        lea     GLT_VB(a4),a1
        move.l  a1,18(a0)
        lea     GLT_IMG(a4),a2
        lea     GLT_VA(a4),a0
        move.l  #$00010001,26(a0)    ; 1 ligne, 1 mot, profondeur 1
        move.w  #1,30(a0)
        move.l  a2,36(a0)
        move.l  #$00010001,26(a1)
        move.w  #1,30(a1)
        move.l  a2,36(a1)
        lea     GLT_OB(a4),a0
        lea     GLT_RP(a4),a1
        moveq   #0,d0
        jsr     -168(a6)             ; GetGBuffers
        tst.w   d0
        beq     glt_fail
        tst.l   GLT_BA+2(a4)         ; SaveBuffer
        beq     glt_fail
        tst.l   GLT_VB+44(a4)        ; CollMask de B
        beq     glt_fail
        lea     GLT_OB(a4),a0
        jsr     -174(a6)             ; InitGMasks
        move.l  GLT_VB+44(a4),a0
        cmp.w   #$FF00,(a0)
        bne     glt_fail
        lea     GLT_OB(a4),a0
        lea     GLT_KEY(a4),a1
        lea     GLT_RP(a4),a2
        jsr     -156(a6)             ; AddAnimOb
        lea     GLT_OB(a4),a0
        cmp.l   GLT_KEY(a4),a0
        bne     glt_fail
        cmp.l   #$00060009,GLT_VA+22(a4)   ; (5 + 1, 7 + 2)
        bne     glt_fail
        bsr     glt_anim
        cmp.w   #10,GLT_VA+24(a4)
        bne     glt_fail
        cmp.w   #1,GLT_CA+2(a4)      ; Timer
        bne     glt_fail
        bsr     glt_anim             ; minuteur à 0 : B remplace A
        lea     GLT_CB(a4),a0
        cmp.l   GLT_OB+36(a4),a0
        bne     glt_fail
        btst    #2,GLT_BA(a4)        ; BOBSAWAY
        beq     glt_fail
        cmp.l   #$00050009,GLT_VB+22(a4)
        bne     glt_fail
        cmp.w   #2,GLT_CB+2(a4)
        bne     glt_fail
        cmp.l   #2,GLT_OB+8(a4)      ; Clock
        bne     glt_fail
        lea     GLT_RP(a4),a1
        suba.l  a0,a0
        jsr     -114(a6)             ; DrawGList : A retiré (BOBNIX)
        btst    #3,GLT_BA(a4)
        beq     glt_fail
        lea     GLT_OB(a4),a0
        lea     GLT_RP(a4),a1
        moveq   #0,d0
        jsr     -600(a6)             ; FreeGBuffers
        tst.l   GLT_BA+2(a4)
        bne     glt_fail
        tst.l   GLT_VB+44(a4)
        bne     glt_fail
        lea     msg_gels_ok(pc),a0
        bra.s   glt_msg
glt_fail:
        lea     msg_gels_fail(pc),a0
glt_msg:
        exg     a5,a6
        bsr     ser_puts
        move.l  a4,a1
        move.l  #GLT_SIZE,d0
        jsr     LVO_FREEMEM(a6)
glt_close:
        move.l  a5,a1
        jsr     LVO_CLOSELIBRARY(a6)
glt_done:
        movem.l (sp)+,d2-d3/a2-a5
        bra     glt_end
glt_anim:
        lea     GLT_KEY(a4),a0
        lea     GLT_RP(a4),a1
        jmp     -162(a6)             ; Animate
; glt_check(a2 = table (x, y, attendu)... terminée par -1, a4, a6 = GfxBase) : Z = 1 si chaque ReadPixel correspond.
glt_check:
        move.w  (a2)+,d0
        bmi.s   glt_ck_ok
        move.w  (a2)+,d1
        lea     GLT_RP(a4),a1
        jsr     -318(a6)             ; ReadPixel
        cmp.w   (a2)+,d0
        beq.s   glt_check
        rts
glt_ck_ok:
        moveq   #0,d0
        rts
; routines de collision (convention C) : compte dans VUserExt (offset 58) de chaque gel ; bords : drapeaux.
glt_coll1:
        move.l  4(sp),a0
        addq.w  #1,58(a0)
        move.l  8(sp),a0
        addq.w  #1,58(a0)
        rts
glt_coll0:
        move.l  4(sp),a0
        move.w  10(sp),58(a0)
        rts
glt_px1:                             ; Bob à (3, 2) : 3,3 | 1 | 2 | transparent ; fond 1 autour
        dc.w    3,2,3, 6,2,3, 7,2,1, 10,2,1, 11,2,2, 14,2,2, 15,2,1, 18,2,1
        dc.w    5,1,1, 5,5,3, 5,6,1, 2,3,1, -1
glt_px2:                             ; ancien emplacement restauré ; Bob à (20, 8), découpé à x = 31
        dc.w    3,2,1, 7,2,1, 11,2,1, 6,5,1
        dc.w    20,8,3, 23,8,3, 24,8,1, 27,8,1, 28,8,2, 31,8,2, 20,11,3, 20,12,1, 19,8,1, -1
glt_px3:                             ; RemIBob : fond restauré
        dc.w    20,8,1, 24,8,1, 28,8,1, 31,11,1, -1
glt_end:

        ; --- layers.library : une couche SIMPLE (L1) et une SMART (L2) sur un BitMap hors écran 64x32x2. Dessin,
        ; BehindLayer (zone simple redécouverte : effacée + dommage ; zone smart cachée : sauvegardée), dessin dans la
        ; partie cachée de L2 (lu par ReadPixel), BeginUpdate/EndUpdate de L1, UpfrontLayer (restauration), MoveLayer,
        ; SizeLayer de L2 (agrandissement smart : dommage), DeleteLayer (fond et couche de dessous), SizeLayer de L1,
        ; WhichLayer. Attendus : modèle Python au pixel. ---
        movem.l d2-d7/a2-a5,-(sp)
        lea     -16(sp),sp
        move.l  sp,a5                ; 0 BitMap, 4 L1, 8 L2, 12 Layer_Info
        clr.l   (a5)
        clr.l   4(a5)
        clr.l   8(a5)
        clr.l   12(a5)
        lea     graphics_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a2                ; a2 = GfxBase
        lea     layers_test_name(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        move.l  d0,a3                ; a3 = LayersBase
        move.l  a2,d0
        beq     lyt_fail0
        move.l  a3,d0
        beq     lyt_fail0
        move.l  #40+512,d0
        move.l  #MEMF_PUBLIC|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,(a5)
        beq     lyt_fail0
        move.l  d0,a0
        moveq   #2,d0
        moveq   #64,d1
        moveq   #32,d2
        exg     a2,a6
        jsr     -390(a6)             ; InitBitMap(bm, 2, 64, 32)
        exg     a2,a6
        move.l  (a5),a0
        lea     40(a0),a1
        move.l  a1,8(a0)             ; plans
        lea     256(a1),a1
        move.l  a1,12(a0)
        exg     a3,a6
        jsr     -144(a6)             ; NewLayerInfo
        exg     a3,a6
        move.l  d0,12(a5)
        beq     lyt_fail
        moveq   #0,d0                ; L1 = simple (0,0)-(31,15)
        moveq   #0,d1
        moveq   #31,d2
        moveq   #15,d3
        moveq   #1,d4
        bsr     lyt_create
        move.l  d0,4(a5)
        beq     lyt_fail
        moveq   #1,d0
        bsr     lyt_setrast1
        moveq   #16,d0               ; L2 = smart (16,8)-(47,23)
        moveq   #8,d1
        moveq   #47,d2
        moveq   #23,d3
        moveq   #2,d4
        bsr     lyt_create
        move.l  d0,8(a5)
        beq     lyt_fail
        move.l  8(a5),a1
        move.l  12(a1),a1
        moveq   #2,d0
        exg     a2,a6
        jsr     -234(a6)             ; SetRast(L2, 2)
        exg     a2,a6
        LYT_PIX 20,10,2
        LYT_PIX 5,5,1
        LYT_PIX 40,20,2
        LYT_PIX 50,5,0
        move.l  4(a5),a1             ; L1 : RectFill 3 sur toute la couche (seule sa partie visible change)
        moveq   #3,d0
        bsr     lyt_fill
        LYT_PIX 20,10,2
        LYT_PIX 5,5,3
        move.l  8(a5),a1
        moveq   #-54,d7              ; BehindLayer(L2)
        bsr     lyt_lcall
        LYT_PIX 20,10,0
        LYT_PIX 5,5,3
        LYT_PIX 40,20,2
        move.l  4(a5),a0
        btst    #7,31(a0)            ; L1 : LAYERREFRESH
        beq     lyt_fail
        LYT_RPIX 4,2,2
        move.l  8(a5),a1             ; dessin dans la partie cachée de L2 : (0,0)-(7,3) au stylo 1
        moveq   #1,d0
        moveq   #0,d4
        moveq   #0,d5
        moveq   #7,d6
        moveq   #3,d7
        bsr     lyt_rect
        LYT_PIX 20,10,0
        LYT_RPIX 4,2,1
        move.l  4(a5),a0             ; BeginUpdate(L1) + RectFill 3 + EndUpdate(L1, TRUE)
        exg     a3,a6
        jsr     -78(a6)
        exg     a3,a6
        move.l  4(a5),a1
        moveq   #3,d0
        bsr     lyt_fill
        move.l  4(a5),a0
        moveq   #1,d0
        exg     a3,a6
        jsr     -84(a6)
        exg     a3,a6
        LYT_PIX 20,10,3
        LYT_PIX 5,5,3
        move.l  4(a5),a0
        btst    #7,31(a0)
        bne     lyt_fail
        move.l  8(a5),a1
        moveq   #-48,d7              ; UpfrontLayer(L2) : contenu restauré depuis la sauvegarde
        bsr     lyt_lcall
        LYT_PIX 20,10,1
        LYT_PIX 30,14,2
        LYT_PIX 5,5,3
        move.l  8(a5),a1             ; MoveLayer(L2, +8, +4)
        moveq   #8,d0
        moveq   #4,d1
        moveq   #-60,d7
        bsr     lyt_lcall
        LYT_PIX 28,14,1
        LYT_PIX 17,9,0
        LYT_PIX 20,10,0
        LYT_PIX 50,26,2
        move.l  8(a5),a1             ; SizeLayer(L2 smart, +4, +2) : contenu gardé, partie agrandie à 0 et en dommage
        moveq   #4,d0
        moveq   #2,d1
        moveq   #-66,d7
        bsr     lyt_lcall
        LYT_PIX 50,26,2
        LYT_PIX 57,28,0
        move.l  8(a5),a0
        btst    #7,31(a0)
        beq     lyt_fail
        move.l  4(a5),a0
        btst    #7,31(a0)
        beq     lyt_fail
        bsr     lyt_clrdmg
        move.l  8(a5),a1             ; DeleteLayer(L2)
        moveq   #-90,d7
        bsr     lyt_lcall
        clr.l   8(a5)
        LYT_PIX 28,14,0
        LYT_PIX 50,20,0
        LYT_PIX 5,5,3
        move.l  4(a5),a0
        btst    #7,31(a0)
        beq     lyt_fail
        bsr     lyt_clrdmg
        move.l  4(a5),a1             ; SizeLayer(L1, +8, +4)
        moveq   #8,d0
        moveq   #4,d1
        moveq   #-66,d7
        bsr     lyt_lcall
        LYT_PIX 35,17,0
        LYT_PIX 5,5,3
        move.l  4(a5),a0
        btst    #7,31(a0)
        beq     lyt_fail
        move.l  12(a5),a0            ; WhichLayer
        moveq   #5,d0
        moveq   #5,d1
        exg     a3,a6
        jsr     -132(a6)
        exg     a3,a6
        cmp.l   4(a5),d0
        bne     lyt_fail
        move.l  12(a5),a0
        moveq   #60,d0
        moveq   #30,d1
        exg     a3,a6
        jsr     -132(a6)
        exg     a3,a6
        tst.l   d0
        bne     lyt_fail
        lea     msg_layers_ok(pc),a0
        bra.s   lyt_msg
lyt_fail:
        lea     msg_layers_fail(pc),a0
lyt_msg:
        bsr     ser_puts
        moveq   #8,d6                ; couches restantes supprimées, puis Layer_Info et BitMap rendus
lyt_del:
        move.l  0(a5,d6.w),d0
        beq.s   lyt_deln
        move.l  d0,a1
        moveq   #-90,d7
        bsr     lyt_lcall
lyt_deln:
        subq.w  #4,d6
        bne.s   lyt_del
        move.l  12(a5),d0
        beq.s   lyt_nli
        move.l  d0,a0
        exg     a3,a6
        jsr     -150(a6)             ; DisposeLayerInfo
        exg     a3,a6
lyt_nli:
        move.l  (a5),a1
        move.l  #40+512,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   lyt_close
lyt_fail0:
        lea     msg_layers_fail(pc),a0
        bsr     ser_puts
lyt_close:
        move.l  a2,a1
        jsr     LVO_CLOSELIBRARY(a6)
        move.l  a3,a1
        jsr     LVO_CLOSELIBRARY(a6)
        lea     16(sp),sp
        movem.l (sp)+,d2-d7/a2-a5
        bra     lyt_end
; sous-routines de la sonde layers (a2 = GfxBase, a3 = LayersBase, a5 = cadre, a6 = SysBase)
lyt_create:                          ; CreateUpfrontLayer(li, bm, d0..d3, flags d4) -> d0
        move.l  12(a5),a0
        move.l  (a5),a1
        movem.l a2,-(sp)
        suba.l  a2,a2
        exg     a3,a6
        jsr     -36(a6)
        exg     a3,a6
        movem.l (sp)+,a2
        rts
lyt_setrast1:                        ; SetRast(L1, d0)
        move.l  4(a5),a1
        move.l  12(a1),a1
        exg     a2,a6
        jsr     -234(a6)
        exg     a2,a6
        rts
lyt_fill:                            ; a1 = couche, d0 = stylo : RectFill de toute la couche initiale (0,0)-(31,15)
        moveq   #0,d4
        moveq   #0,d5
        moveq   #31,d6
        moveq   #15,d7
lyt_rect:                            ; a1 = couche, d0 = stylo, d4..d7 = rectangle relatif
        move.l  12(a1),a1
        exg     a2,a6
        jsr     -342(a6)             ; SetAPen
        move.w  d4,d0
        move.w  d5,d1
        move.w  d6,d2
        move.w  d7,d3
        jsr     -306(a6)             ; RectFill
        exg     a2,a6
        rts
lyt_lcall:                           ; layers(dummy a0, couche a1, d0, d1) au LVO d7
        suba.l  a0,a0
        exg     a3,a6
        jsr     0(a6,d7.w)
        exg     a3,a6
        rts
lyt_clrdmg:                          ; dommages de L1 effacés (BeginUpdate + EndUpdate TRUE)
        move.l  4(a5),a0
        exg     a3,a6
        jsr     -78(a6)
        move.l  4(a5),a0
        moveq   #1,d0
        jsr     -84(a6)
        exg     a3,a6
        rts
; lyt_px(d0 = x, d1 = y) -> d0 = couleur lue directement dans les deux plans du BitMap ; d2 = attendu -> Z si égal.
lyt_px:
        move.l  (a5),a0
        lsl.w   #3,d1                ; 8 octets par ligne
        move.w  d0,d3
        lsr.w   #3,d3
        add.w   d3,d1
        not.w   d0
        and.w   #7,d0
        moveq   #0,d3
        move.l  12(a0),a1
        btst    d0,0(a1,d1.w)
        beq.s   lyt_p1
        moveq   #2,d3
lyt_p1:
        move.l  8(a0),a1
        btst    d0,0(a1,d1.w)
        beq.s   lyt_p2
        addq.w  #1,d3
lyt_p2:
        cmp.w   d2,d3
        rts
; lyt_rpx(d0 = x, d1 = y relatifs à L2) : ReadPixel(L2) comparé à d2.
lyt_rpx:
        move.l  8(a5),a1
        move.l  12(a1),a1
        exg     a2,a6
        jsr     -318(a6)
        exg     a2,a6
        cmp.w   d2,d0
        rts
lyt_end:

        ; --- M6t : vérifier trackdisk.device (squelette résident + validation d'unité) ---
        ; FindName(DeviceList) + version 34 + NT_DEVICE + Open(unité 0) OK (OpenCnt==1, io_Error==0, io_Unit ==
        ; base+LIB_SIZE = aire EXACTE de l'unité 0, io_Device==base) + Open(unité 4) ÉCHOUE (io_Error!=0,
        ; io_Device==0, OpenCnt inchangé). RED TD_NO_UNITCHECK : unité 4 ouvre à tort -> M6T absent. a6=ExecBase.
        lea     EB_DEVICELIST(a6),a0
        lea     trackdisk_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m6t_done
        move.l  d0,a2                ; a2 = TDBase
        cmp.w   #34,LIB_VERSION(a2)
        bne     m6t_done
        cmp.b   #NT_DEVICE,LN_TYPE(a2)
        bne     m6t_done
        lea     -32(sp),sp           ; IORequest sur la pile (IO_SIZE=32), mis à 0
        move.l  sp,a3                ; a3 = ioreq
        moveq   #(32/4)-1,d0
        move.l  a3,a0
.m6t_clr:
        clr.l   (a0)+
        dbf     d0,.m6t_clr
        move.l  a6,-(sp)             ; Open(unité 0) via le vecteur -6 (a6=dev, a1=ioreq, d0=unit, d1=flags)
        move.l  a2,a6
        move.l  a3,a1
        moveq   #0,d0
        moveq   #0,d1
        jsr     -6(a6)               ; trackdisk Open (LVO -6, littéral : boot.s n'inclut qu'exec.i)
        move.l  (sp)+,a6
        cmp.w   #1,LIB_OPENCNT(a2)   ; OpenCnt==1 ?
        bne.s   m6t_pop
        tst.b   IO_ERROR(a3)         ; io_Error==0 ?
        bne.s   m6t_pop
        move.l  IO_DEVICE(a3),d0     ; io_Device==TDBase ?
        cmp.l   a2,d0
        bne.s   m6t_pop
        lea     LIB_SIZE(a2),a0      ; attendu io_Unit = base + TDU_UNIT0 (TDU_UNIT0 = LIB_SIZE = 34)
        cmp.l   IO_UNIT(a3),a0       ; io_Unit == base+TDU_UNIT0 ? (prouve l'offset de base + io_Unit posé ; le stride
        bne.s   m6t_pop              ;   par-unité est placeholder, re-prouvé quand les unités seront réelles en B2)
        move.l  a6,-(sp)             ; Open(unité 4) -> doit ÉCHOUER
        move.l  a2,a6
        move.l  a3,a1
        moveq   #4,d0
        moveq   #0,d1
        jsr     -6(a6)
        move.l  (sp)+,a6
        tst.b   IO_ERROR(a3)         ; io_Error != 0 (échec) ?
        beq.s   m6t_pop              ; RED TD_NO_UNITCHECK : io_Error==0 -> ouvre à tort -> M6T absent
        move.l  IO_DEVICE(a3),d0     ; io_Device == 0 (échec OpenDevice) ?
        bne.s   m6t_pop
        cmp.w   #1,LIB_OPENCNT(a2)   ; OpenCnt toujours 1 (unité 4 n'a pas compté) ?
        bne.s   m6t_pop
        lea     32(sp),sp            ; libère l'IORequest (succès)
        lea     msg_m6t_ok(pc),a0
        bsr     ser_puts             ; « M6T TRACKDISK OK »
        bra.s   m6t_done
m6t_pop:
        lea     32(sp),sp            ; libère l'IORequest (échec)
m6t_done:

        clr.b   TD_CYLVALID         ; cylinder-tracking : position tête inconnue avant la 1re lecture -> recalibrer
        ; --- M6u/M6v : lecture brute (B2) + décodage MFM (B3) — UNE SEULE lecture de DF0 ---
        ; td_read_track0 lit la piste brute ; M6U compte les mots de synchro $4489 (impossibles en MFM normal -> 0
        ; faux positif), M6V décode les secteurs (combine odd/even) + vérifie les checksums en-tête ET data. UNE
        ; seule lecture pour les deux (un 2e timeout sans disque décalerait la preuve M7A). Sans disque -> rien, sans FAILED.
        moveq   #0,d4                ; d4 = flag « disque présent » (gate M6W : évite un 2e timeout sans disque)
        bsr     td_read_track0
        tst.l   d0
        beq     m6uv_done
        moveq   #1,d4                ; disque présent
        move.l  d0,a4                ; a4 = rawbuf chip (piste brute ; préservé jusqu'au FreeMem)
        ; M6U : compter les mots de synchro
        move.l  a4,a0
        move.l  #$1900-1,d2          ; TD_RAWWORDS-1 (disk.i) : 6399 < 65535 -> dbra OK
        moveq   #0,d3
.m6u_scan:
        cmp.w   #$4489,(a0)+         ; TD_SYNC (disk.i)
        bne.s   .m6u_next
        addq.l  #1,d3
.m6u_next:
        dbra    d2,.m6u_scan
        lea     msg_m6u_syncs(pc),a0
        bsr     ser_puts             ; « M6U SYNCS= »
        move.w  d3,d0
        bsr     ser_puthex
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        cmp.l   #5,d3                ; seuil : au moins 5 syncs (une piste formatée en a ~22)
        blt.s   .m6v_decode
        lea     msg_m6u_ok(pc),a0
        bsr     ser_puts             ; « M6U TRACKDISK READ OK »
.m6v_decode:
        ; M6V : décoder la piste en secteurs 512 o + vérifier les checksums
        move.l  #512*11,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .m6uv_freeraw        ; pas de RAM -> libère juste rawbuf
        move.l  d0,a3                ; a3 = sectorbuf
        move.l  a4,a0
        move.l  a3,a1
        bsr     td_decode_track      ; d0 = nombre de secteurs décodés+vérifiés
        move.l  d0,d5
        lea     msg_m6v_sect(pc),a0
        bsr     ser_puts             ; « M6V SECTORS= »
        move.w  d5,d0
        bsr     ser_puthex
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        cmp.l   #11,d5               ; 11 secteurs valides ?
        bne.s   .m6v_free
        cmp.l   #$444F5300,(a3)      ; secteur 0 décodé == « DOS\0 » (bootblock OFS) ?
        bne.s   .m6v_free
        lea     msg_m6v_ok(pc),a0
        bsr     ser_puts             ; « M6V TRACKDISK DECODE OK »
.m6v_free:
        move.l  a3,a1                ; libère sectorbuf
        move.l  #512*11,d0
        jsr     LVO_FREEMEM(a6)
.m6uv_freeraw:
        move.l  a4,a1                ; libère rawbuf (TD_RAWBYTES = $1900*2)
        move.l  #$1900*2,d0
        jsr     LVO_FREEMEM(a6)
m6uv_done:

        ; --- M6w : trackdisk CMD_READ (B4) — SEULEMENT si disque présent (d4=1 ; évite un 2e timeout sans disque) ---
        ; Monte un IOStdReq (CMD_READ, offset 0, length 512, IOF_QUICK), appelle BeginIO via le vecteur -30, vérifie
        ; io_Error==0 + io_Actual==512 + secteur lu == « DOS\0 ». RED TD_READ_NOCMD -> io_Data reste vide -> absent.
        tst.l   d4
        beq     m6w_done
        lea     EB_DEVICELIST(a6),a0
        lea     trackdisk_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m6w_done
        move.l  d0,a2                ; a2 = trackdisk base
        move.l  #48+512,d0           ; IOStdReq (48) + databuf (512)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   m6w_done
        move.l  d0,a3                ; a3 = ioreq
        move.l  a2,IO_DEVICE(a3)     ; io_Device = trackdisk
        move.w  #2,IO_COMMAND(a3)    ; CMD_READ (= 2)
        move.l  #512,36(a3)          ; IO_LENGTH (offset 36) = 512
        lea     48(a3),a0
        move.l  a0,40(a3)            ; IO_DATA (offset 40) = databuf (ioreq+48)
        clr.l   44(a3)               ; IO_OFFSET (offset 44) = 0 (secteur logique 0)
        move.b  #1,IO_FLAGS(a3)      ; IOF_QUICK -> BeginIO ne fait pas ReplyMsg
        move.l  a6,-(sp)             ; BeginIO via le vecteur -30 (a6 = trackdisk, a1 = ioreq)
        move.l  a2,a6
        move.l  a3,a1
        jsr     -30(a6)
        move.l  (sp)+,a6
        tst.b   IO_ERROR(a3)         ; io_Error == 0 ?
        bne.s   .m6w_free
        cmp.l   #512,32(a3)          ; IO_ACTUAL (offset 32) == 512 octets transférés ?
        bne.s   .m6w_free
        lea     48(a3),a0            ; databuf
        cmp.l   #$444F5300,(a0)      ; secteur 0 lu == « DOS\0 » (bootblock) ?
        bne.s   .m6w_free
        lea     msg_m6w_ok(pc),a0
        bsr     ser_puts             ; « M6W TRACKDISK CMD_READ OK »
.m6w_free:
        move.l  a3,a1
        move.l  #48+512,d0
        jsr     LVO_FREEMEM(a6)
m6w_done:

        ; --- M6x : trackdisk SEEK + side-select (B2b) — lire la PISTE 2 (cylindre 1, face 0) ---
        ; td_read_track(2) seek vers cylindre 1 + face 0 ; td_decode_track renvoie d1 = n° de piste des secteurs.
        ; Succès = 11 secteurs valides ET track == 2 (prouve le seek ET le side : un mauvais side lirait la piste 3).
        ; Gaté sur d4 (disque présent) : pas de 2e timeout sans disque. RED SEEK_NOSTEP -> reste piste 0 -> absent.
        tst.l   d4
        beq     m6x_done
        moveq   #2,d0
        bsr     td_read_track        ; d0 = rawbuf (piste 2) | 0
        tst.l   d0
        beq     m6x_done
        move.l  d0,a4                ; a4 = rawbuf
        move.l  #512*11,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .m6x_freeraw
        move.l  d0,a3                ; a3 = sectorbuf
        move.l  a4,a0
        move.l  a3,a1
        bsr     td_decode_track      ; d0 = nb secteurs valides, d1 = n° de piste lu
        move.l  d1,d5                ; d5 = piste lue (sauvée avant que d1 soit clobbé)
        move.l  d0,d2                ; d2 = count (sauvé : ser_puthex clobbe d0-d3)
        lea     msg_m6x_track(pc),a0
        bsr     ser_puts             ; « M6X TRACK= » (diagnostic : piste réellement atteinte par le seek)
        move.w  d5,d0
        bsr     ser_puthex
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        cmp.l   #11,d2               ; 11 secteurs valides ?
        bne.s   .m6x_free
        cmp.l   #2,d5                ; piste lue == 2 (seek + side corrects) ?
        bne.s   .m6x_free
        lea     msg_m6x_ok(pc),a0
        bsr     ser_puts             ; « M6X TRACKDISK SEEK OK »
.m6x_free:
        move.l  a3,a1
        move.l  #512*11,d0
        jsr     LVO_FREEMEM(a6)
.m6x_freeraw:
        move.l  a4,a1
        move.l  #$1900*2,d0
        jsr     LVO_FREEMEM(a6)
m6x_done:

        ; --- M6z : CMD_READ MULTI-PISTE (prérequis D) — SEULEMENT si disque présent (d4=1) ---
        ; Deux lectures via BeginIO (le vrai chemin device que dos appellera) prouvent le mapping offset->piste :
        ;  (1) root block @ bloc 880 = piste 80 (cyl 40) -> type primaire +0 == 2 (T_SHORT) ET type secondaire
        ;      +508 == 1 (ST_ROOT). Un mauvais mapping renverrait la piste 0 (bootblock « DOS\0 ») -> échoue.
        ;  (2) lecture SPANNING : offset 10*512, length 1024 = blocs 10+11 -> TRAVERSE la frontière piste 0/1.
        ;      Le bloc 10 (piste 0, secteur 10) porte « SPAN0010 », le bloc 11 (piste 1, secteur 0) « SPAN0011 »
        ;      (posés par patch_bootblock.py). Les deux marqueurs présents <=> la boucle a lu DEUX pistes et les
        ;      a assemblées. RED TD_NOSEEK (lit toujours la piste 0) -> les deux contrôles échouent -> M6Z absent.
        tst.l   d4
        beq     m6z_done
        lea     EB_DEVICELIST(a6),a0
        lea     trackdisk_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m6z_done
        move.l  d0,a2                ; a2 = trackdisk base
        move.l  #48+1024,d0          ; IOStdReq (48) + databuf (1024 = lecture spanning 2 blocs)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m6z_done
        move.l  d0,a3                ; a3 = ioreq ; databuf = a3+48
        move.l  a2,IO_DEVICE(a3)
        move.w  #2,IO_COMMAND(a3)    ; CMD_READ
        ; (1) root block @ bloc 880 (piste 80)
        move.l  #512,36(a3)          ; IO_LENGTH = 512
        lea     48(a3),a0
        move.l  a0,40(a3)            ; IO_DATA = databuf
        move.l  #880*512,44(a3)      ; IO_OFFSET = bloc 880 (piste 80, cyl 40)
        move.b  #1,IO_FLAGS(a3)      ; IOF_QUICK
        move.l  a6,-(sp)             ; BeginIO via le vecteur -30
        move.l  a2,a6
        move.l  a3,a1
        jsr     -30(a6)
        move.l  (sp)+,a6
        tst.b   IO_ERROR(a3)
        bne     .m6z_free
        cmp.l   #512,32(a3)          ; io_Actual == 512 ?
        bne     .m6z_free
        lea     48(a3),a0            ; databuf = root block
        cmp.l   #2,(a0)              ; +0 == T_SHORT (0x00000002) ?
        bne.s   .m6z_free
        cmp.l   #1,508(a0)           ; +508 == ST_ROOT (0x00000001) ?
        bne.s   .m6z_free
        ; (2) lecture spanning piste 0/1 : blocs 10+11 (offset 10*512, length 1024)
        move.l  #1024,36(a3)         ; IO_LENGTH = 1024
        lea     48(a3),a0
        move.l  a0,40(a3)            ; IO_DATA = databuf
        move.l  #10*512,44(a3)       ; IO_OFFSET = bloc 10 (dernier secteur de la piste 0)
        move.b  #1,IO_FLAGS(a3)      ; IOF_QUICK
        move.l  a6,-(sp)
        move.l  a2,a6
        move.l  a3,a1
        jsr     -30(a6)
        move.l  (sp)+,a6
        tst.b   IO_ERROR(a3)
        bne.s   .m6z_free
        cmp.l   #1024,32(a3)         ; io_Actual == 1024 ?
        bne.s   .m6z_free
        lea     48(a3),a0           ; databuf : [0..511]=bloc 10 (piste 0), [512..1023]=bloc 11 (piste 1)
        cmp.l   #$5350414E,(a0)      ; bloc 10 « SPAN » ?
        bne.s   .m6z_free
        cmp.l   #$30303130,4(a0)     ; bloc 10 « 0010 » ?
        bne.s   .m6z_free
        cmp.l   #$5350414E,512(a0)   ; bloc 11 « SPAN » (piste 1) ?
        bne.s   .m6z_free
        cmp.l   #$30303131,516(a0)   ; bloc 11 « 0011 » ?
        bne.s   .m6z_free
        lea     msg_m6z_ok(pc),a0
        bsr     ser_puts             ; « M6Z TRACKDISK CMD_READ MULTI-TRACK OK »
.m6z_free:
        move.l  a3,a1
        move.l  #48+1024,d0
        jsr     LVO_FREEMEM(a6)
m6z_done:

        ; --- D1 : OFS lecture seule — lire le fichier « KickSlop » de DF0: PAR NOM (gaté disque d4) ---
        ; ofs_read_file parcourt le filesystem OFS (root 880 -> hash -> header via chaîne de hash -> chaîne de
        ; data blocks) en s'appuyant sur trackdisk CMD_READ (M6z). Preuve : taille retournée == 1024 (RED
        ; OFS_NO_DATACHAIN -> 488) ET marqueurs aux frontières de data block OFS : @0 « D1OFSOK0 », @488
        ; « D1OFSOK1 » (2e block, 488 o/bloc OFS), @976 « D1OFSOK2 » (3e block). Prouve trouvé-PAR-NOM — requête
        ; « kickslop » vs stocké « KickSlop » exerce le toupper hash + compare insensible à la casse — ET la
        ; chaîne data complète. RED OFS_NO_DATACHAIN -> taille 488 -> D1 absent (isole le chaînage).
        tst.l   d4
        beq     d1_done
        move.l  #2048,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     d1_done
        move.l  d0,a4                ; a4 = buffer destination (préservé par ofs_read_file : movem d2-d7/a2-a5)
        lea     ofs_test_name(pc),a0 ; « kickslop » (casse différente du nom stocké)
        move.l  a4,a1
        move.l  #2048,d0             ; max octets (garde buffer)
        jsr     ofs_read_file        ; d0 = taille lue | 0 (jsr absolu : ofs.o lié hors portée bsr 16 bits)
        cmp.l   #1024,d0             ; fichier complet lu ?
        bne.s   .d1_free
        cmp.l   #$44314F46,(a4)      ; @0 « D1OF »
        bne.s   .d1_free
        cmp.l   #$534F4B30,4(a4)     ; @0 « SOK0 »
        bne.s   .d1_free
        cmp.l   #$534F4B31,492(a4)   ; @488 « SOK1 » (2e data block OFS)
        bne.s   .d1_free
        cmp.l   #$534F4B32,980(a4)   ; @976 « SOK2 » (3e data block OFS)
        bne.s   .d1_free
        lea     msg_d1_ok(pc),a0
        bsr     ser_puts             ; « D1 OFS READ OK »
.d1_free:
        move.l  a4,a1
        move.l  #2048,d0
        jsr     LVO_FREEMEM(a6)
d1_done:

        ; --- D2 : LoadSeg — charger « D2Test » de l'OFS, relocaliser, EXÉCUTER (gaté disque d4) ---
        ; dos_loadseg lit l'exécutable hunk via ofs_read_file (D1), alloue les segments, APPLIQUE les relocations
        ; et renvoie le BPTR de la seglist. On exécute le code chargé : entry = (BPTR<<2)+4. Le code émet LUI-MÊME
        ; « D2LOADSEG OK » (preuve qu'il tourne depuis la RAM AVEC relocation appliquée — même logique que CBOOT en
        ; C). RED D2_NO_RELOC : load OK mais pointeur non relocaté -> le code lit la RAM basse -> marqueur absent.
        tst.l   d4
        beq     d2_done
        lea     ls_test_name(pc),a0
        jsr     dos_loadseg          ; d0 = BPTR 1er segment | 0 (jsr absolu : loadseg.o hors portée bsr)
        tst.l   d0
        beq.s   d2_done              ; échec de chargement -> pas de marqueur
        move.l  d0,-(sp)             ; BPTR sur la pile (survit au code chargé)
        lsl.l   #2,d0
        addq.l  #4,d0                ; entry = (BPTR<<2)+4 = contenu du 1er hunk (CODE)
        move.l  d0,a0
        jsr     (a0)                 ; exécute le code chargé (A6=SysBase) -> émet « D2LOADSEG OK »
        move.l  ($4).w,a6            ; recharge SysBase (le code chargé a pu clobber a6)
        move.l  (sp)+,d0             ; BPTR
        jsr     dos_unloadseg        ; libère les segments
d2_done:

        ; --- M6a : unité VBLANK de timer.device FONCTIONNELLE ---
        ; alloue reply port + timerequest, demande 100000 us (= 5 ticks), BeginIO, puis
        ; interroge le reply port (le service VBlank répond après ~5 VBlank). d6 = base timer,
        ; d7 = VBL_COUNT au départ (préservés par AllocMem/newlist/GetMsg).
        lea     EB_DEVICELIST(a6),a0
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,d6                ; d6 = base timer.device
        beq     m6a_fail
        move.l  #MP_SIZE,d0          ; reply port (PA_IGNORE : boot interroge par GetMsg)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m6a_fail
        move.l  d0,a2                ; a2 = port
        lea     MP_MSGLIST(a2),a1
        jsr     newlist
        move.b  #PA_SIGNAL,MP_FLAGS(a2)   ; PA_SIGNAL -> exerce exec_Signal DEPUIS le handler
        move.b  #16,MP_SIGBIT(a2)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a2)  ; signale la boot task (TS_RUN -> no-wake)
        move.l  #TR_SIZE,d0          ; timerequest
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m6a_fail
        move.l  d0,a3                ; a3 = timerequest
        move.l  a2,MN_REPLYPORT(a3)
        move.l  d6,IO_DEVICE(a3)
        move.l  #UNIT_VBLANK,IO_UNIT(a3)  ; unité VBLANK (le défaut de BeginIO est MICROHZ depuis M7a)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a3)
        clr.l   TV_SECS(a3)
        move.l  #100000,TV_MICRO(a3) ; 100000 us / 20000 = 5 ticks
        move.l  EB_THISTASK(a6),a0   ; efface le bit 16 de SIGRECVD (on le veut posé par la reply)
        move.l  TC_SIGRECVD(a0),d0
        bclr    #16,d0
        move.l  d0,TC_SIGRECVD(a0)
        move.l  VBL_COUNT,d7         ; T0
        move.l  a6,-(sp)             ; BeginIO (a6 = base timer, a1 = requête)
        move.l  d6,a6
        move.l  a3,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
.m6a_wait:
        move.l  VBL_COUNT,d0         ; garde-fou timeout (~4 s)
        sub.l   d7,d0
        cmp.l   #200,d0
        bcc     m6a_fail
        move.l  a2,a0                ; GetMsg(port) ?
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .m6a_wait
        cmp.l   a3,d0                ; le reply doit être NOTRE requête
        bne     m6a_fail
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)  ; marquée répondue ?
        bne     m6a_fail
        move.l  VBL_COUNT,d0         ; délai ≈ 5 ticks ? (marge [3..40])
        sub.l   d7,d0
        cmp.l   #3,d0
        bcs     m6a_fail
        cmp.l   #40,d0
        bhi     m6a_fail
        move.l  EB_THISTASK(a6),a0   ; exec_Signal (depuis le handler) a-t-il posé le bit 16 ?
        move.l  TC_SIGRECVD(a0),d0
        btst    #16,d0
        beq     m6a_fail
        lea     msg_m6a_ok(pc),a0
        bsr     ser_puts             ; « M6A TIMER OK »

        ; --- M7b : dispatcher par numéro — chaîne PORTS (INT2) via AddIntServer ---
        ; SCHED_ON encore 0 (aucune interaction scheduler/gate ; INT2 niveau 2 < 3 de toute façon).
        ; Enregistre DEUX serveurs sur PORTS : ciaa_server (pri 10, lit+acquitte l'ICR ciaa ->
        ; cia_test_vec incrémente CIA_FIRED) et int2_srv2 (pri 0, incrémente INT2_SRV2). La chaîne les
        ; appelle DANS L'ORDRE DE PRIORITÉ (cia avant srv2) -> prouve AddIntServer + walker + ordre.
        ; Structs serveur en RAM (Enqueue les chaîne). CIA-A Timer A en CONTINU déclenche INT2.
        ; Généralise M6b : cia.resource EST le handler PORTS (serveur), plus un autovecteur hardcodé.
        clr.l   CIA_FIRED
        clr.l   INT2_SRV2
        clr.l   INT2_ORDER_SNAP
        lea     ciaa_test_name(pc),a1   ; OpenResource("ciaa.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     m7b_fail
        move.l  d0,a2                ; a2 = base ciaa (survit au spin + cleanup)
        move.l  #(2*IS_STRIDE),d0    ; 2 struct Interrupt RAM alignées (Enqueue les chaîne -> pas en ROM)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7b_fail
        move.l  d0,a3                ; a3 = bloc serveurs : srvA=+0, srvB=+IS_STRIDE (aligné)
        move.b  #10,LN_PRI(a3)       ; srvA = ciaa_server, pri 10 (appelé en 1er)
        move.l  #ciaa_server,IS_CODE(a3)
        move.b  #0,IS_STRIDE+LN_PRI(a3) ; srvB = int2_srv2, pri 0 (appelé en 2e)
        move.l  #int2_srv2,IS_STRIDE+IS_CODE(a3)
        moveq   #INTB_PORTS,d0       ; AddIntServer(PORTS, srvA)
        move.l  a3,a1
        jsr     LVO_ADDINTSERVER(a6)
        moveq   #INTB_PORTS,d0       ; AddIntServer(PORTS, srvB)
        lea     IS_STRIDE(a3),a1
        jsr     LVO_ADDINTSERVER(a6)
        move.l  a6,-(sp)             ; AddICRVector(ciaa, bit0=timerA, &cia_test_int)
        move.l  a2,a6
        moveq   #0,d0
        lea     cia_test_int(pc),a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        move.l  CIAR_HWBASE(a2),a0   ; démarre CIA-A Timer A CONTINU, latch $00FF (~360 us/IRQ)
        move.b  #$FF,CIA_TALO(a0)
        move.b  #$00,CIA_TAHI(a0)
        move.b  #$11,CIA_CRA(a0)     ; START(b0)+LOAD(b4), continu (b3=0) -> INT2 périodique
        move.l  VBL_COUNT,d7         ; T0 (timeout)
.m7b_wait:
        move.l  VBL_COUNT,d0
        sub.l   d7,d0
        cmp.l   #150,d0
        bcc     m7b_fail             ; timeout -> chaîne non dispatchée
        tst.l   CIA_FIRED            ; 1er serveur (ciaa) appelé via la chaîne ?
        beq.s   .m7b_wait
        tst.l   INT2_SRV2            ; 2e serveur de la chaîne appelé ?
        beq.s   .m7b_wait
        move.l  CIAR_HWBASE(a2),a0   ; les deux tournent -> cleanup matériel
        move.b  #$00,CIA_CRA(a0)     ; stop Timer A
        move.l  a6,-(sp)             ; RemICRVector(bit0)
        move.l  a2,a6
        moveq   #0,d0
        suba.l  a1,a1
        jsr     CIA_REMICRVECTOR(a6)
        move.l  (sp)+,a6
        move.w  #INTF_PORTS,INTENA   ; désactive Paula PORTS -> pas d'INT2 pendant la démo
        tst.l   INT2_ORDER_SNAP      ; ordre : ciaa (pri 10) a tourné AVANT srv2 (pri 0) ?
        beq     m7b_fail
        lea     msg_m7b_ok(pc),a0
        bsr     ser_puts             ; « M7B PORTS OK »

        jsr     kbd_install          ; F2b : installe le driver clavier LIVE (AddICRVector bit 3 -> kbd_interrupt)
        tst.l   d0
        bne.s   .f2b_nokbd
        lea     msg_f2bkbd(pc),a0
        bsr     ser_puts             ; « F2B KBD OK » (driver clavier live installé ; le CLI est pilotable au clavier)
.f2b_nokbd:

        ; --- input.device (#2) : OpenDevice (FindName) + IND_ADDHANDLER x2 (pri) + IND_WRITEEVENT -> chaîne ---
        ; Prouve EN ISOLATION le cœur d'input.device : la chaîne de handlers triée par pri + la propagation d'un
        ; InputEvent via IND_WRITEEVENT (point d'injection public, celui qu'Intuition utilise). Deux handlers à
        ; pri 10 / 0 : l'ordre d'appel (h1 avant h2) prouve le tri ; le keycode relayé prouve la propagation.
        clr.w   INPUT_SEQ
        clr.w   INPUT_H1_ORD
        clr.w   INPUT_H2_ORD
        clr.w   INPUT_CODE
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1   ; FindName("input.device") (= ce que fait OpenDevice en interne)
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .input_done             ; pas d'input.device (ne devrait pas arriver) -> skip
        move.l  d0,a2                   ; a2 = base input.device (survit aux BeginIO)
        move.l  #INPUT_TESTBLK,d0       ; bloc RAM : ioreq(48) + h1(24) + h2(24) + event(22) -> structs writables
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .input_done
        move.l  d0,a3                   ; a3 = bloc ; ioreq=+0, h1=+48, h2=+72, event=+96
        lea     48(a3),a0               ; h1 : handler pri 10 (appelé 1er)
        move.b  #10,LN_PRI(a0)
        move.l  #input_test_h1,IS_CODE(a0)
        lea     72(a3),a0               ; h2 : handler pri 0 (appelé 2e)
        move.l  #input_test_h2,IS_CODE(a0)
        lea     96(a3),a0               ; event : RAWKEY, code $34 ('v')
        move.b  #IECLASS_RAWKEY,IE_CLASS(a0)
        move.w  #$0034,IE_CODE(a0)
        move.l  a2,IO_DEVICE(a3)
        lea     48(a3),a0               ; ADDHANDLER h1
        move.w  #IND_ADDHANDLER,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        lea     72(a3),a0               ; ADDHANDLER h2
        move.w  #IND_ADDHANDLER,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        lea     96(a3),a0               ; WRITEEVENT event -> parcourt la chaîne
        move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        cmp.w   #$0034,INPUT_CODE       ; keycode relayé par la chaîne ?
        bne.s   .input_free
        cmp.w   #1,INPUT_H1_ORD         ; h1 (pri 10) a tourné en 1er ?
        bne.s   .input_free
        cmp.w   #2,INPUT_H2_ORD         ; h2 (pri 0) a tourné en 2e ?
        bne.s   .input_free
        lea     msg_input_ok(pc),a0
        bsr     ser_puts                ; « INPUT OK »
.input_free:
        lea     48(a3),a0               ; REMHANDLER h1 (nettoyage)
        move.w  #IND_REMHANDLER,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        lea     72(a3),a0               ; REMHANDLER h2
        move.w  #IND_REMHANDLER,IO_COMMAND(a3)
        move.l  a0,INP_IO_DATA(a3)
        bsr     .input_beginio
        move.l  a3,a1
        move.l  #INPUT_TESTBLK,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .input_done
.input_beginio:                         ; helper : BeginIO(input, a3=ioreq) + recharge SysBase. a2=device base.
        move.l  a3,a1
        move.l  a2,a6
        jsr     -30(a6)                 ; input_beginio (LVO -30)
        move.l  ($4).w,a6               ; recharge a6 = SysBase (BeginIO ressort avec a6 = base device)
        rts
.input_done:

        ; --- console.device (#3a) : CMD_WRITE d'une string -> blit glyphes 8x8 -> READBACK du bitplane ---
        ; Prouve le blitter + la police SANS affichage : on écrit une string connue via CMD_WRITE puis on relit
        ; chaque cellule du bitplane et on la compare au glyphe de font8x8. Correct math d'adresse + bons octets
        ; = « CONSOLE WRITE OK ». Headless (série, pas de Xvfb) ; RED CON_NO_BLIT -> readback != glyphes -> absent.
        lea     EB_DEVICELIST(a6),a0
        lea     console_dev_name(pc),a1  ; FindName("console.device")
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .con_done
        move.l  d0,a2                    ; a2 = base console.device
        move.l  #64,d0                   ; ioreq (48 -> arrondi 64)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .con_done
        move.l  d0,a3                    ; a3 = ioreq (survit jusqu'au free)
        move.l  a2,IO_DEVICE(a3)
        move.w  #CMD_WRITE_BO,IO_COMMAND(a3)
        lea     con_test_str(pc),a0
        move.l  a0,INP_IO_DATA(a3)       ; io_Data = string
        move.l  #con_test_end-con_test_str,IO_LEN_BO(a3)  ; io_Length
        move.l  a3,a1
        move.l  a2,a6
        jsr     -30(a6)                  ; console BeginIO (CMD_WRITE -> blit dans le bitplane)
        move.l  ($4).w,a6
        ; readback : chaque cellule (col, lignes 0..7) == glyphe de font8x8 du char correspondant ?
        move.l  CONB_BITMAP(a2),d0       ; bitplane alloué par la 1re écriture ?
        beq     .con_free
        move.l  d0,a5                    ; a5 = bitplane
        moveq   #0,d4
        move.w  CONB_BWIDTH(a2),d4       ; d4 = stride
        lea     con_test_str(pc),a4      ; a4 = string rendue
        moveq   #0,d5                    ; d5 = colonne
.con_rb:
        moveq   #0,d0
        move.b  (a4)+,d0
        beq.s   .con_match               ; fin de string (NUL) -> toutes cellules OK
        subi.w  #$20,d0
        lsl.l   #3,d0                    ; (char-0x20)*8
        move.l  #font8x8,a0
        add.l   d0,a0                    ; a0 = glyphe
        move.l  a5,a1
        add.l   d5,a1                    ; a1 = bitplane + col (cury=0)
        moveq   #7,d2                    ; 8 lignes
.con_rbrow:
        move.b  (a0)+,d0                 ; octet glyphe attendu
        cmp.b   (a1),d0                  ; octet réellement blitté
        bne.s   .con_mismatch
        add.w   d4,a1                    ; ligne suivante (+stride)
        dbra    d2,.con_rbrow
        addq.l  #1,d5                    ; colonne suivante
        bra.s   .con_rb
.con_mismatch:
        bra.s   .con_free                ; une cellule diffère -> pas de marqueur
.con_match:
        lea     msg_console_ok(pc),a0
        bsr     ser_puts                 ; « CONSOLE WRITE OK »
.con_free:
        move.l  a3,a1
        move.l  #64,d0
        jsr     LVO_FREEMEM(a6)
.con_done:

        ; --- console.device READ via input.device (#3b) : IND_WRITEEVENT RAWKEY -> handler console -> CMD_READ ---
        ; Le handler de console.device (enregistré sur input.device à l'init) cuit le RAWKEY -> ASCII -> read buffer ;
        ; CMD_READ le ressert. On injecte un RAWKEY 'v' ($34) par le chemin PUBLIC IND_WRITEEVENT (celui d'Intuition)
        ; -> la chaîne #2 devient load-bearing avec console comme vrai consommateur. (Feeder clavier->input.device = F.)
        lea     EB_DEVICELIST(a6),a0
        lea     console_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .conr_done
        move.l  d0,a2                    ; a2 = base console.device
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .conr_done
        move.l  d0,a4                    ; a4 = base input.device
        move.l  #96,d0                   ; bloc : ioreq@0(48) + event@48(22) + readbuf@80
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .conr_done
        move.l  d0,a3                    ; a3 = bloc
        move.l  a2,IO_DEVICE(a3)         ; draine le read buffer (restes du test #2)
        move.w  #CMD_READ_BO,IO_COMMAND(a3)
        lea     80(a3),a0
        move.l  a0,INP_IO_DATA(a3)
        move.l  #16,IO_LEN_BO(a3)
        bsr     .conr_bio_con
        lea     48(a3),a0               ; construit l'event RAWKEY 'v' ($34)
        move.b  #IECLASS_RAWKEY,IE_CLASS(a0)
        move.w  #$0034,IE_CODE(a0)
        clr.l   IE_NEXTEVENT(a0)
        move.l  a4,IO_DEVICE(a3)        ; IND_WRITEEVENT -> input.device -> chaîne -> handler console
        move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
        lea     48(a3),a0
        move.l  a0,INP_IO_DATA(a3)
        move.l  a3,a1
        move.l  a4,a6
        jsr     -30(a6)                 ; input BeginIO WRITEEVENT
        move.l  ($4).w,a6
        clr.b   80(a3)                  ; console CMD_READ 1 octet -> doit être 'v' cuit
        move.l  a2,IO_DEVICE(a3)
        move.w  #CMD_READ_BO,IO_COMMAND(a3)
        lea     80(a3),a0
        move.l  a0,INP_IO_DATA(a3)
        move.l  #1,IO_LEN_BO(a3)
        bsr     .conr_bio_con
        cmp.b   #'v',80(a3)             ; char rendu par CMD_READ == le keycode cuit ?
        bne.s   .conr_free
        lea     msg_conread_ok(pc),a0
        bsr     ser_puts                ; « CONSOLE READ=v »
.conr_free:
        move.l  a3,a1
        move.l  #96,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .conr_done
.conr_bio_con:                          ; helper : console BeginIO(a3=ioreq) + recharge SysBase. a2=base console.
        move.l  a3,a1
        move.l  a2,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts
.conr_done:

        ; --- disk-validator (#4) : valide le bitmap d'allocation OFS de DF0: ---
        ; (sur ADF : rootblock+bitmap checksums OFS + bm_flag valide + root marqué alloué ; NODISK : pas de disque -> 0)
        jsr     dv_validate          ; diskvalidator.o lié loin -> jsr absolu
        tst.l   d0
        beq.s   .dv4_done
        lea     msg_diskvalid(pc),a0
        bsr     ser_puts             ; « DISK VALID OK »
.dv4_done:

        ; --- keymap (#5) : cook keycode(+qualifiers) via keymap.resource (US QWERTY ou FR AZERTY selon le build) ---
                ifeq    KEYMAP_AZERTY
        moveq   #$10,d0             ; 'q' non-shifté
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #'q',d0
        bne     .km5_done
        moveq   #$10,d0             ; SHIFT -> 'Q'
        moveq   #$01,d1
        jsr     kbd_cook
        cmp.b   #'Q',d0
        bne     .km5_done
        moveq   #$10,d0             ; CAPS -> 'Q'
        moveq   #$04,d1
        jsr     kbd_cook
        cmp.b   #'Q',d0
        bne     .km5_done
        moveq   #$01,d0             ; '1' non-shifté ; SHIFT -> '!'
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #'1',d0
        bne     .km5_done
        moveq   #$01,d0
        moveq   #$01,d1
        jsr     kbd_cook
        cmp.b   #'!',d0
        bne     .km5_done
        moveq   #$33,d0             ; CTRL+'c' -> $03
        moveq   #$08,d1
        jsr     kbd_cook
        cmp.b   #3,d0
        bne     .km5_done
        lea     msg_keymap_ok(pc),a0
        bsr     ser_puts            ; « KEYMAP OK »
                else
        moveq   #$10,d0             ; AZERTY : keycode $10 -> 'a'
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #'a',d0
        bne     .km5_done
        moveq   #$01,d0             ; AZERTY : $01 non-shifté -> '&'
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #'&',d0
        bne     .km5_done
        moveq   #$01,d0             ; SHIFT -> '1'
        moveq   #$01,d1
        jsr     kbd_cook
        cmp.b   #'1',d0
        bne     .km5_done
        moveq   #$02,d0             ; AZERTY : $02 non-shifté -> 'é' ($E9)
        moveq   #0,d1
        jsr     kbd_cook
        cmp.b   #$E9,d0
        bne     .km5_done
        lea     msg_keymap_azerty(pc),a0
        bsr     ser_puts            ; « KEYMAP AZERTY OK »
                endc
.km5_done:

        ; --- requester Intuition « insert disk » cliquable : rendu (readback) + clic (RAWMOUSE via input.device) ---
        ; (1) req_draw -> bord + texte dans un bitplane -> readback (bord haut + glyphe 'I'). (2) req_input_handler sur
        ; input.device -> IND_WRITEEVENT d'un RAWMOUSE DANS le gadget (hit) puis HORS (miss) -> prouve le hit-test.
        move.l  #CON_BMSIZE,d0          ; bitplane de test (chip, effacé)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .req_done
        move.l  d0,a2                   ; a2 = bitplane (survit)
        move.l  a2,a0
        moveq   #CON_BYTEW,d0
        jsr     req_draw                ; dessine le requester
        move.l  a2,a0
        cmp.b   #$FF,(64*CON_BYTEW)+10(a0)  ; bord haut (row 64, octet 10) tracé ?
        bne     .req_dfree
        move.l  #font8x8,a1             ; glyphe 'I' attendu
        move.l  #('I'-$20)*8,d0
        add.l   d0,a1
        lea     (72*CON_BYTEW)+12(a0),a3    ; cellule rendue (col 12, row 72)
        moveq   #7,d2
.req_rb:
        move.b  (a1)+,d0
        cmp.b   (a3),d0
        bne.s   .req_dfree
        add.w   #CON_BYTEW,a3
        dbra    d2,.req_rb
        lea     msg_req_drawn(pc),a0
        bsr     ser_puts                ; « REQUESTER DRAWN OK »
.req_dfree:
        move.l  a2,a1
        move.l  #CON_BMSIZE,d0
        jsr     LVO_FREEMEM(a6)
        lea     EB_DEVICELIST(a6),a0    ; clic via input.device
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .req_done
        move.l  d0,a4                   ; a4 = input.device base
        move.l  #96,d0                  ; bloc : req_int(24) + ioreq(48@24) + event(22@72)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .req_done
        move.l  d0,a3                   ; a3 = bloc
        move.b  #0,LN_PRI(a3)           ; req_int : handler pri 0
        move.l  #req_input_handler,IS_CODE(a3)
        lea     24(a3),a1              ; ADDHANDLER req_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .req_bio
        lea     72(a3),a0              ; event RAWMOUSE DANS le gadget (160,112)
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a0)
        move.w  #IECODE_LBUTTON,IE_CODE(a0)
        move.w  #160,IE_X(a0)
        move.w  #112,IE_Y(a0)
        clr.w   REQ_HIT
        lea     24(a3),a1             ; WRITEEVENT (clic dans)
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a1)
        lea     72(a3),a0
        move.l  a0,INP_IO_DATA(a1)
        bsr     .req_bio
        cmp.w   #1,REQ_HIT            ; clic DANS -> doit avoir posé REQ_HIT
        bne.s   .req_cfree
        lea     72(a3),a0            ; event RAWMOUSE HORS (5,5)
        move.w  #5,IE_X(a0)
        move.w  #5,IE_Y(a0)
        clr.w   REQ_HIT
        lea     24(a3),a1
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a1)
        lea     72(a3),a0
        move.l  a0,INP_IO_DATA(a1)
        bsr     .req_bio
        tst.w   REQ_HIT              ; clic HORS -> REQ_HIT doit rester 0
        bne.s   .req_cfree
        lea     msg_req_click(pc),a0
        bsr     ser_puts             ; « REQUESTER CLICK OK »
.req_cfree:
        lea     24(a3),a1            ; REMHANDLER
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_REMHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .req_bio
        move.l  a3,a1
        move.l  #96,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .req_done
.req_bio:                            ; helper : input BeginIO(a1=ioreq) + recharge SysBase. a4=input base.
        move.l  a4,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts
.req_done:

        ; --- gameport.device (souris matérielle) : LOGIQUE prouvée par snapshots SYNTHÉTIQUES de registres ---
        ; (headless : JOY0DAT non pilotable + framebuffer invisible -> on prouve la LOGIQUE, pas le matériel ; le
        ; serveur VBlank est prouvé séparément, LIVE, par GP_POLLS dans le système tournant). (1) gp_delta8 :
        ; vecteurs de wraparound 8 bits. (2) gp_poll : mouvement (dx incl. wrap) + edge bouton, capturés par un
        ; handler sur input.device (IND_WRITEEVENT = la vraie voie d'injection, comme le feeder clavier).
        moveq   #5,d0                   ; gp_delta8(cur,prev) : (5,2) -> +3
        moveq   #2,d1
        jsr     gp_delta8
        cmp.w   #3,d0
        bne     .gp_done
        moveq   #2,d0                   ; (2,5) -> -3
        moveq   #5,d1
        jsr     gp_delta8
        cmp.w   #-3,d0
        bne     .gp_done
        move.w  #$01,d0                 ; ($01,$FE) -> +3 (wrap bas->haut)
        move.w  #$FE,d1
        jsr     gp_delta8
        cmp.w   #3,d0
        bne     .gp_done
        move.w  #$FE,d0                 ; ($FE,$01) -> -3 (wrap haut->bas)
        move.w  #$01,d1
        jsr     gp_delta8
        cmp.w   #-3,d0
        bne     .gp_done
        lea     EB_DEVICELIST(a6),a0    ; capture via un handler sur input.device
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .gp_done
        move.l  d0,a4                   ; a4 = input.device base
        move.l  d0,GP_INPUTBASE         ; cible d'injection de gp_poll
        move.l  #72,d0                  ; bloc : gp_int(24) + ioreq(48@24)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .gp_done
        move.l  d0,a3                   ; a3 = bloc
        move.b  #0,LN_PRI(a3)           ; gp_int : handler de capture pri 0
        move.l  #gp_cap_handler,IS_CODE(a3)
        lea     24(a3),a1               ; ADDHANDLER gp_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .gp_bio
        move.w  #$00FE,GP_PREV_JOY      ; mouvement+wrap : prev (X=$FE,Y=$00), poll JOY=$0001 (X=$01,Y=$00) -> dx=+3 dy=0
        clr.b   GP_PREV_BTN
        clr.b   GP_PREV_RBTN
        clr.w   GP_CAP_N
        move.w  #$0001,d0
        move.w  #$00FF,d1               ; CIAA_PRA bit6=1 -> bouton relâché
        jsr     gp_poll
        cmp.w   #1,GP_CAP_N             ; un event (mouvement pur)
        bne.s   .gp_cfree
        cmp.w   #IECODE_NOBUTTON,GP_CAP_CODE
        bne.s   .gp_cfree
        cmp.w   #3,GP_CAP_DX            ; dx=+3 au passage $FE->$01 (RED GP_NO_WRAP -> -253)
        bne.s   .gp_cfree
        tst.w   GP_CAP_DY               ; dy=0
        bne.s   .gp_cfree
        move.w  #$1234,GP_PREV_JOY      ; edge bouton : position CONSTANTE (cur==prev -> dx=dy=0) pour isoler le front
        clr.b   GP_PREV_BTN             ; relâché au départ
        clr.w   GP_CAP_N
        move.w  #$1234,d0               ; A : pressé (bit6=0, $BF) -> front -> LBUTTON down
        move.w  #$00BF,d1
        jsr     gp_poll
        move.w  #$1234,d0               ; B : tenu -> GREEN rien / RED GP_NO_EDGE un 2e down
        move.w  #$00BF,d1
        jsr     gp_poll
        move.w  #$1234,d0               ; C : tenu -> GREEN rien / RED un 3e down
        move.w  #$00BF,d1
        jsr     gp_poll
        move.w  #$1234,d0               ; D : relâché (bit6=1) -> front -> LBUTTON up
        move.w  #$00FF,d1
        jsr     gp_poll
        cmp.w   #2,GP_CAP_N             ; exactement 2 events (down + up) ; RED GP_NO_EDGE -> 3
        bne.s   .gp_cfree
        cmp.w   #(IECODE_LBUTTON|IECODE_UP_PREFIX),GP_CAP_CODE  ; dernier = up ($E8)
        bne.s   .gp_cfree
        lea     msg_gameport_ok(pc),a0
        bsr     ser_puts                ; « GAMEPORT OK »
.gp_cfree:
        lea     24(a3),a1               ; REMHANDLER
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_REMHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .gp_bio
        clr.l   GP_INPUTBASE            ; gp_install la re-publiera pour le serveur live
        move.l  a3,a1
        move.l  #72,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .gp_done
.gp_bio:                                ; input BeginIO(a1=ioreq) + recharge SysBase. a4=input base.
        move.l  a4,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts
.gp_done:

        ; --- câblage M6R LIVE : deltas RAWMOUSE RELATIFS -> accumulateur de pointeur (absolu, clampé) -> requester ---
        ; Le chaînon live : pointer_input_handler (pri 50) intègre les deltas en position absolue clampée et réécrit
        ; ie_X/ie_Y -> req_input_handler (pri 0, INCHANGÉ) hit-teste en absolu. La voie JOY->RAWMOUSE est prouvée au
        ; bloc GAMEPORT ; ici on injecte des RAWMOUSE relatifs (= la sortie de gameport) via IND_WRITEEVENT.
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .m6r_done
        move.l  d0,a4                   ; a4 = input.device base
        move.l  #120,d0                 ; bloc : ptr_int(24) + req_int(24@24) + ioreq(48@48) + event(22@96)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .m6r_done
        move.l  d0,a3                   ; a3 = bloc
        move.b  #50,LN_PRI(a3)          ; ptr_int : accumulateur pri 50 (AVANT le requester dans la chaîne)
        move.l  #pointer_input_handler,IS_CODE(a3)
        move.b  #0,LN_PRI+24(a3)        ; req_int : requester pri 0
        move.l  #req_input_handler,IS_CODE+24(a3)
        lea     48(a3),a1               ; ADDHANDLER ptr_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .m6r_bio
        lea     48(a3),a1               ; ADDHANDLER req_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        lea     24(a3),a0
        move.l  a0,INP_IO_DATA(a1)
        bsr     .m6r_bio
        move.w  #10,PTR_X               ; départ (10,10)
        move.w  #10,PTR_Y
        lea     96(a3),a0               ; event RAWMOUSE relatif (-50,-50) NOBUTTON -> clamp (0,0)
        clr.l   IE_NEXTEVENT(a0)
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a0)
        move.w  #IECODE_NOBUTTON,IE_CODE(a0)
        move.w  #-50,IE_X(a0)
        move.w  #-50,IE_Y(a0)
        bsr     .m6r_write
        lea     96(a3),a0               ; mouvement +160,+112 -> (160,112) sur le gadget
        move.w  #IECODE_NOBUTTON,IE_CODE(a0)
        move.w  #160,IE_X(a0)
        move.w  #112,IE_Y(a0)
        clr.l   IE_NEXTEVENT(a0)
        bsr     .m6r_write
        cmp.w   #160,PTR_X              ; position absolue correcte (RED PTR_NO_CLAMP -> 120 : base -40)
        bne.s   .m6r_free
        cmp.w   #112,PTR_Y              ; (RED -> 72)
        bne.s   .m6r_free
        clr.w   REQ_HIT                 ; clic LBUTTON (delta nul) -> pointeur réécrit abs (160,112) -> hit-test DANS
        lea     96(a3),a0
        move.w  #IECODE_LBUTTON,IE_CODE(a0)
        move.w  #0,IE_X(a0)
        move.w  #0,IE_Y(a0)
        clr.l   IE_NEXTEVENT(a0)
        bsr     .m6r_write
        cmp.w   #1,REQ_HIT              ; clic DANS le gadget -> REQ_HIT posé
        bne.s   .m6r_free
        lea     96(a3),a0               ; déplace HORS : (160,112) -155 -> (5,112)
        move.w  #IECODE_NOBUTTON,IE_CODE(a0)
        move.w  #-155,IE_X(a0)
        move.w  #0,IE_Y(a0)
        clr.l   IE_NEXTEVENT(a0)
        bsr     .m6r_write
        clr.w   REQ_HIT
        lea     96(a3),a0               ; clic HORS (5,112) : x<120 -> miss
        move.w  #IECODE_LBUTTON,IE_CODE(a0)
        move.w  #0,IE_X(a0)
        move.w  #0,IE_Y(a0)
        clr.l   IE_NEXTEVENT(a0)
        bsr     .m6r_write
        tst.w   REQ_HIT                 ; clic HORS -> REQ_HIT reste 0
        bne.s   .m6r_free
        lea     msg_m6r_live_ok(pc),a0
        bsr     ser_puts                ; « M6R LIVE OK »
.m6r_free:
        lea     48(a3),a1               ; REMHANDLER ptr_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_REMHANDLER,IO_COMMAND(a1)
        move.l  a3,INP_IO_DATA(a1)
        bsr     .m6r_bio
        lea     48(a3),a1               ; REMHANDLER req_int
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_REMHANDLER,IO_COMMAND(a1)
        lea     24(a3),a0
        move.l  a0,INP_IO_DATA(a1)
        bsr     .m6r_bio
        move.l  a3,a1
        move.l  #120,d0
        jsr     LVO_FREEMEM(a6)
        bra.s   .m6r_done
.m6r_write:                             ; IND_WRITEEVENT(event @ 96(a3)) ; a4=input base, a3=bloc. Clobbe a0/a1.
        lea     48(a3),a1
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a1)
        lea     96(a3),a0
        move.l  a0,INP_IO_DATA(a1)
.m6r_bio:
        move.l  a4,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts
.m6r_done:

                ifne    LOADSCREEN_DEMO
        ; DÉMO écran de chargement : tous les modules sont up (console/graphics/trackdisk) + disque en DF0:.
        ; loadscreen_demo monte l'affichage, lit « bigseg » en streaming avec barre de progression, tient l'écran.
        move.l  ($4).w,a6            ; a6 = SysBase
        jsr     loadscreen_demo      ; NE REVIENT PAS
                endc
        ; --- M7a + M3f : démo combinée (SCHED_ON=1) ---
        ; Setup entier à IPL7 pour qu'aucune IRQ ne parte avant le lancement (le CIA-B démarre
        ; mais son underflow reste pending jusqu'au rte). M7a : unité MICROHZ via CIA-B/INT6 +
        ; task_timer qui bloque dessus -> prouve (a) une TÂCHE réveillée par un timer d'interruption
        ; (Wait->wake) et (b) la fidélité IPL-par-niveau (M7e) : INT6 (niveau 6) préempte le CORPS de
        ; vbl_handler (IPL natif 3) -> VBL_PREEMPT_COUNT>0, MAIS la chirurgie de listes du switch reste
        ; atomique (IPL7 bref) -> VBL_CLASH==0 (overlap, pas corruption). RED1 (M7E_SURGERY_INTENA=1 :
        ; INTENA-off au lieu d'IPL7) -> VBL_CLASH>0 ; RED2 (M7E_PROLOGUE_IPL7=1 : IPL7 au prologue) ->
        ; VBL_PREEMPT_COUNT==0. M3f (rejoué, non-régression) : task_H/L/S prouvent
        ; la coexistence préemption + yield (« M3F LIVE »). GREEN = « M7A TIMER OK » + « M7E IPL OK ».
        move.w  #$2700,sr            ; masque les interruptions pendant TOUT le setup
                ifeq    PROD            ; PROD : vbl_tail est un serveur de PREUVE (M7e/M7f) -> hors prod
        clr.l   VBL_CLASH
        clr.l   VBL_PREEMPT_COUNT    ; M7e : baseline des préemptions du corps de vbl (INT6 armé juste après)
        clr.b   M7E_STAT             ; M7e : marqueur « M7E IPL OK » pas encore émis
        clr.l   VERTB_CHAIN_N        ; M7f : baseline des parcours de chaîne VERTB
        clr.b   M7F_STAT             ; M7f : marqueur « M7F VERTB OK » pas encore émis
        ; M7f : enregistre vbl_tail_server (serveur de PREUVE, pri -10) en QUEUE de la chaîne VERTB
        ; (après sched_server pri 20 + timer_vblank pri 0). Son compteur VERTB_CHAIN_N prouve le parcours complet.
        move.b  #-10,VBL_TAIL_INT+LN_PRI
        clr.l   VBL_TAIL_INT+IS_DATA
        move.l  #vbl_tail_server,VBL_TAIL_INT+IS_CODE
        moveq   #INTB_VERTB,d0
        lea     VBL_TAIL_INT,a1
        jsr     LVO_ADDINTSERVER(a6)
                endc                    ; fin bloc preuve VERTB (PROD=0)
        ; souris matérielle : arme le poller gameport.device (gp_vblank_server) sur la chaîne VERTB du système
        ; tournant — câblage LIVE PERSISTANT (pendant du feeder clavier). GP_POLLS avancera sur les VBlanks réels ;
        ; headless (JOY0DAT statique) le poller n'injecte rien (prev primé = courant) -> inerte vis-à-vis de M7.
        jsr     gp_install
                ifeq    PROD            ; PROD : COPER = source de PREUVE (M7g multi-source int3) -> hors prod
        ; M7g : 2e source de NIVEAU 3 (COPER) pour prouver le décodage INTREQR multi-source d'int3.
        ; coper_test (vecteur EXCLUSIF) incrémente COPER_FIRED ; vbl_tail déclenche COPER par logiciel.
        clr.l   COPER_FIRED
        clr.b   COPER_TICK
        clr.b   M7G_STAT
        moveq   #INTB_COPER,d0          ; SetIntVector(COPER, &coper_int)
        lea     coper_int(pc),a1
        jsr     LVO_SETINTVECTOR(a6)
        move.w  #(INTF_SETCLR|INTF_COPER),INTENA ; active COPER (niveau 3) ; vbl_tail la déclenche
                endc                    ; fin source COPER de preuve (PROD=0) ; MICROHZ/CIA-B conservé ci-dessous
        lea     ciab_test_name(pc),a1   ; OpenResource("ciab.resource")
        jsr     LVO_OPENRESOURCE(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a2                ; a2 = base ciab
        moveq   #INTB_EXTER,d0       ; SetIntVector(EXTER, &ciab_server_int) : vecteur EXCLUSIF ->
        lea     ciab_server_int(pc),a1  ; INT6 passe par le dispatcher par numéro (ciab_server/cia_dispatch)
        jsr     LVO_SETINTVECTOR(a6)
        move.l  a6,-(sp)             ; AddICRVector(ciab, bit0 = timer A, &timer_micro_int)
        move.l  a2,a6
        moveq   #0,d0
        move.l  #timer_micro_int,a1
        jsr     CIA_ADDICRVECTOR(a6)
        move.l  (sp)+,a6
        move.w  #(INTF_SETCLR|INTF_EXTER),INTENA   ; active Paula EXTER (INT6, niveau 6 > VBlank 3)
        jsr     timer_micro_start    ; timer A de CIA-B en one-shot (dev : réarmé toutes les ~360 µs)
        bsr     setup_stress_port    ; M7d : port partagé + K messages (martelé par tâche ET interruption)
        bsr     setup_demo_tasks     ; task_H(10) + task_L(0) + task_S(0) + task_timer(10, M7a) + task_port(0, M7d)
        ; --- M6r/M6y : strap (romboot) — lit, valide et EXÉCUTE le bootblock de DF0: (jalon C « ça boote ! ») ---
        ; strap_boot lit les secteurs 0+1 (bootblock) de DF0:, valide magic « DOS » + checksum additif, et saute
        ; au boot code à +12. d0=0 = aucun volume bootable (pas de disque, ou checksum invalide = formaté non
        ; installé) -> ÉCRAN DE BOOT insert-disk (M6R). d0!=0 = bootblock exécuté -> PAS d'insert-disk (M6Y) ;
        ; le marqueur « CBOOT » est émis par le bootblock LUI-MÊME pendant son exécution (preuve du saut).
        ; Les deux branches convergent vers SCHED_ON (le set M7 complet suit dans les deux cas).
        ; RED STRAP_FAKE_BOOTDEV : d0!=0 sans lire -> M6Y présent mais CBOOT absent. RED STRAP_NO_EXEC : valide
        ; mais ne saute pas -> CBOOT absent, M6Y présent. RED STRAP_BAD_CSUM : rejette un bon bloc -> M6R.
        bsr     strap_boot
        tst.l   d0
        bne.s   .m6r_booted
        lea     msg_m6r_ok(pc),a0
        bsr     ser_puts             ; « M6R STRAP OK (no bootable volume -> insert-disk) »
        jsr     gfx_display_init     ; M6s : ÉCRAN DE BOOT (image chaton 32 couleurs) via l'ABI graphics.library
        lea     msg_m6s_ok(pc),a0
        bsr     ser_puts             ; « M6S BOOTSCR OK » (écran monté ; discriminant VISUEL = couleurs)
        bsr     m6r_wire_requester   ; câblage LIVE : handlers pointeur+requester PERSISTANTS sur input.device
        lea     dw_name(pc),a0       ; surveillance de DF0: : une disquette insérée redémarre la machine (boot)
        move.l  #disk_watch,a1
        moveq   #-1,d0
        move.l  #DW_STK,d1
        jsr     proc_create
        bra.s   .strap_done
.m6r_booted:
        lea     msg_m6y_ok(pc),a0
        bsr     ser_puts             ; « M6Y STRAP BOOTED OK » (bootblock exécuté ; CBOOT émis par le bootblock)
        bsr     ptr_wire             ; souris : pointeur à l'écran (sprite) dans le système tournant
        ; --- F1 : disque BOOTABLE -> créer l'Initial CLI (shell). GATÉ sur le boot (c'est la ligne F vs E) :
        ; sur un disque non bootable (branche M6R insert-disk), AUCUN Initial CLI n'est créé. Le shell exécute
        ; d'abord s:startup-sequence (racine) puis passe à l'invite interactive. a6 = SysBase (strap l'a restauré).
        lea     sh_cname(pc),a0
        move.l  #shell_main,a1       ; absolu : shell.o lié hors portée lea(pc) 16 bits
        moveq   #2,d0                ; Initial CLI pri 2 (consommateur unique de la console)
        move.l  #SH_STK,d1           ; les commandes lancées tournent sur cette pile
        jsr     proc_create
.strap_done:
                ifeq    M7E_COOP
        move.b  #1,SCHED_ON          ; ARME la préemption périodique (défaut)
                endc                 ; M7E_COOP=1 : SCHED_ON reste 0 -> non-régression yield-only
        ; --- M7c : LANCEMENT de la 1re tâche = transition SUPERVISEUR -> USER mode ---
        ; La pile boot (STACKTOP) devient la SSP PARTAGÉE des interruptions ; chaque tâche a sa pile
        ; user (AllocMem'd). On réinitialise la SSP à STACKTOP (abandonne le contexte boot), on réserve
        ; un slot de frame, et dispatch_in relocalise la frame user de task_H -> SSP puis rte en USER mode.
        move.l  #STACKTOP,sp         ; SSP partagée propre (le contexte boot ne reprend jamais)
        lea     -FRAME_SIZE(sp),sp   ; slot 66 o pour dispatch_in (movem+rte ramènent sp à STACKTOP)
        lea     EB_TASKREADY(a6),a0  ; dispatch initial explicite
        jsr     LVO_REMHEAD(a6)      ; tête = task_H (pri 10) -> elle Wait d'abord
        move.l  d0,a1
        bra     dispatch_in          ; -> task_H en USER mode (SR=$0000 ; VBlank + INT6 + yield actifs)

eb_fail:
        move.w  #C_FAIL,COLOR00
        lea     msg_fail(pc),a0
        bsr     ser_puts
.ff:
        bra.s   .ff

; ser_puts : chaîne NUL-terminée sur le série (a0) ; timeout borné sur TBE
ser_puts:
        movem.l d0/d1/d2/a0,-(sp)
        bsr     ser_lock             ; émission ATOMIQUE (aucun autre émetteur ne s'entrelace)
.lp:
        move.b  (a0)+,d0
        beq.s   .done
        move.w  #$2000,d2
.wt:
        move.w  SERDATR,d1
        btst    #13,d1
        bne.s   .tx
        dbra    d2,.wt
        bra.s   .done
.tx:
        and.w   #$00FF,d0
        or.w    #$0100,d0
        move.w  d0,SERDAT
        bra.s   .lp
.done:
        bsr     ser_unlock
        movem.l (sp)+,d0/d1/d2/a0
        rts

; ser_lock / ser_unlock : rendent TOUTE émission série atomique entre tâches (Forbid gated SCHED_ON — no-op avant
; le multitâche). Mécanisme = exclusion mutuelle par Forbid (aucun switch de tâche pendant l'émission), déjà éprouvé
; (task_timer). Préservent TOUS les registres (Forbid/Permit les préservent ; seul a6 est touché, sauvé/restauré).
; Tous les émetteurs concurrents (ser_puts, ser_puthex, con_handler WRITE, feeder, binaires chargés via le Forbid de
; leur appelant) les utilisent -> plus d'entrelacement octet-à-octet des marqueurs (plus de faux-GREEN).
ser_lock:
        tst.b   SCHED_ON
        beq.s   .slk_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)
        move.l  (sp)+,a6
.slk_ret:
        rts
ser_unlock:
        tst.b   SCHED_ON
        beq.s   .sulk_ret
        move.l  a6,-(sp)
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        move.l  (sp)+,a6
.sulk_ret:
        rts

; ser_puthex(d0.w) : émet les 4 chiffres hexa de d0 (mot) sur le série (MSB d'abord). Scratch sauvé (d0-d3).
ser_puthex:
        movem.l d0-d3,-(sp)
        bsr     ser_lock             ; émission atomique
        move.w  d0,d3                ; d3 = valeur à afficher
        moveq   #3,d2                ; 4 nibbles
.ph_nib:
        rol.w   #4,d3                ; amène le nibble de poids fort suivant en bits 0-3
        move.w  #$2000,d1            ; timeout TBE
.ph_wt:
        move.w  SERDATR,d0
        btst    #13,d0               ; TBE (transmit buffer empty) ?
        bne.s   .ph_send
        dbra    d1,.ph_wt
        bra.s   .ph_next             ; timeout -> saute ce chiffre
.ph_send:
        move.w  d3,d0
        and.w   #$000F,d0
        add.w   #'0',d0
        cmp.w   #'9',d0
        bls.s   .ph_out
        addq.w  #7,d0                ; 'A'..'F'
.ph_out:
        and.w   #$00FF,d0
        or.w    #$0100,d0            ; 8 bits
        move.w  d0,SERDAT
.ph_next:
        dbra    d2,.ph_nib
        bsr     ser_unlock
        movem.l (sp)+,d0-d3
        rts

; ============================ auto-test (M2.1a+) ====================
; Exerce le dispatch jump-table et le comportement des fonctions.
; Retour : d0 = 0 (tout OK) / 1 (échec).
selftest:
        movem.l d6-d7/a2-a5,-(sp)
        ; baseline du tas chip : 1er chunk libre APRÈS les allocations permanentes
        ; de boot (TCB ThisTask...). Les asserts de coalescing comparent à cette
        ; baseline (robuste aux allocations permanentes, pas au tas vide).
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),a5     ; a5 = adresse baseline du 1er chunk
        move.l  MC_BYTES(a5),d7     ; d7 = taille baseline
        ; Forbid : TDNestCnt -1 -> 0 ; Permit : 0 -> -1
        jsr     LVO_FORBID(a6)
        cmp.b   #0,EB_TDNEST(a6)
        bne.w   .bad
        jsr     LVO_PERMIT(a6)
        cmp.b   #-1,EB_TDNEST(a6)
        bne.w   .bad
        ; Disable/Enable : IDNestCnt -1 -> 0 -> -1
        jsr     LVO_DISABLE(a6)
        cmp.b   #0,EB_IDNEST(a6)
        bne.w   .bad
        jsr     LVO_ENABLE(a6)
        cmp.b   #-1,EB_IDNEST(a6)
        bne.w   .bad

        ; liste : NEWLIST, AddTail(n1), AddTail(n2), FindName
        lea     TST_LIST,a1
        jsr     newlist
        move.l  #str_alpha,TST_N1+LN_NAME
        move.l  #str_beta,TST_N2+LN_NAME
        lea     TST_LIST,a0
        lea     TST_N1,a1
        jsr     LVO_ADDTAIL(a6)
        lea     TST_LIST,a0
        lea     TST_N2,a1
        jsr     LVO_ADDTAIL(a6)
        ; FindName("beta") == TST_N2
        lea     TST_LIST,a0
        move.l  #str_beta,a1
        jsr     LVO_FINDNAME(a6)
        cmp.l   #TST_N2,d0
        bne.w   .bad
        ; FindName("gamma") == 0
        lea     TST_LIST,a0
        move.l  #str_gamma,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.w   .bad
        ; Remove(n1) ; FindName("alpha") == 0
        lea     TST_N1,a1
        jsr     LVO_REMOVE(a6)
        lea     TST_LIST,a0
        move.l  #str_alpha,a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        bne.w   .bad
        ; AddHead(n1) ; FindName("alpha") == TST_N1
        lea     TST_LIST,a0
        lea     TST_N1,a1
        jsr     LVO_ADDHEAD(a6)
        lea     TST_LIST,a0
        move.l  #str_alpha,a1
        jsr     LVO_FINDNAME(a6)
        cmp.l   #TST_N1,d0
        bne.w   .bad
        ; Open/Close : OpenCnt +1 puis -1, Open retourne SysBase
        jsr     LVO_OPEN(a6)
        cmp.l   a6,d0
        bne.w   .bad
        jsr     LVO_CLOSE(a6)
        tst.w   LIB_OPENCNT(a6)
        bne.w   .bad
        lea     chk_core(pc),a0      ; checkpoint série : groupe « core » passé
        bsr     ser_puts

        ; --- mémoire : AllocMem / FreeMem ---
        move.l  #256,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; p1
        move.l  #256,d0
        moveq   #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3                ; p2
        move.l  #$11111111,(a2)      ; non-recouvrement par motif
        move.l  #$22222222,(a3)
        cmp.l   #$11111111,(a2)
        bne.w   .bad
        cmp.l   #$22222222,(a3)
        bne.w   .bad
        move.l  #$DEADBEEF,(a2)      ; dirty p1, free, realloc CLEAR -> zéro
        move.l  a2,a1
        move.l  #256,d0
        jsr     LVO_FREEMEM(a6)
        move.l  #256,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a1
        tst.l   (a1)                 ; MEMF_CLEAR -> 1er longword == 0
        bne.w   .bad
        move.l  #256,d0              ; libère le bloc CLEAR puis p2
        jsr     LVO_FREEMEM(a6)
        move.l  a3,a1
        move.l  #256,d0
        jsr     LVO_FREEMEM(a6)

        ; coalescing : après tous les free, le tas doit être revenu à sa baseline
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),d0
        cmp.l   a5,d0
        bne.w   .bad
        move.l  d0,a0
        cmp.l   MC_BYTES(a0),d7
        bne.w   .bad
        lea     chk_mem(pc),a0       ; checkpoint : mémoire M2.1/M2.2 + coalescing
        bsr     ser_puts

        ; ===== M2.4a : multi-MemHeader + primitives de listes =====
        ; (1) 2e MemHeader « fast » sur la région DISJOINTE [FTEST_LO,FTEST_HI).
        ;     Struct allouée depuis le tas ; la région est fixe/disjointe (c'est
        ;     ainsi que fonctionne un vrai multi-header : régions physiques distinctes).
        move.l  #MH_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; a2 = H (header fast)
        move.b  #NT_MEMORY,LN_TYPE(a2)
        move.w  #(MEMF_FAST|MEMF_PUBLIC),MH_ATTRIBUTES(a2)
        move.l  #FTEST_LO,MH_LOWER(a2)
        move.l  #FTEST_HI,MH_UPPER(a2)
        move.l  #(FTEST_HI-FTEST_LO),MH_FREE(a2)
        move.l  #FTEST_LO,a0         ; chunk initial = toute la région
        clr.l   MC_NEXT(a0)
        move.l  #(FTEST_HI-FTEST_LO),MC_BYTES(a0)
        move.l  a0,MH_FIRST(a2)
        lea     EB_MEMLIST(a6),a0
        move.l  a2,a1
        jsr     LVO_ADDTAIL(a6)
        ; AvailMem(MEMF_FAST) == taille de la région
        moveq   #MEMF_FAST,d1
        jsr     LVO_AVAILMEM(a6)
        cmp.l   #(FTEST_HI-FTEST_LO),d0
        bne.w   .bad
        ; AllocMem(1024,MEMF_FAST) -> sélection par attribut -> adresse dans la région
        move.l  #1024,d0
        moveq   #MEMF_FAST,d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3               ; a3 = bloc fast
        cmp.l   #FTEST_LO,d0
        bcs.w   .bad                ; < FTEST_LO
        cmp.l   #FTEST_HI,d0
        bcc.w   .bad                ; >= FTEST_HI
        ; TypeOfMem(bloc) a le bit MEMF_FAST (= bit 2)
        move.l  a3,a1
        jsr     LVO_TYPEOFMEM(a6)
        btst    #2,d0
        beq.w   .bad
        ; FreeMem(bloc fast) : l'owner-search doit retrouver H (pas le header chip)
        move.l  a3,a1
        move.l  #1024,d0
        jsr     LVO_FREEMEM(a6)
        moveq   #MEMF_FAST,d1
        jsr     LVO_AVAILMEM(a6)
        cmp.l   #(FTEST_HI-FTEST_LO),d0   ; région de nouveau pleine -> owner-search OK
        bne.w   .bad
        ; retire H de la MemList + libère sa struct
        move.l  a2,a1
        jsr     LVO_REMOVE(a6)
        move.l  a2,a1
        move.l  #MH_SIZE,d0
        jsr     LVO_FREEMEM(a6)

        ; (2) Enqueue : 3 noeuds pri 0/10/5 -> ordre tête->queue 10,5,0 (FIFO à pri égale)
        move.l  #(3*16),d0          ; 3 noeuds (LN_SIZE=14 arrondi à 16)
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3               ; a3 = n0=+0, n1=+16, n2=+32
        move.l  #16,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a4               ; a4 = struct List
        move.l  a4,a1
        jsr     newlist
        move.b  #0,LN_PRI(a3)
        move.b  #10,16+LN_PRI(a3)
        move.b  #5,32+LN_PRI(a3)
        move.l  a4,a0
        move.l  a3,a1               ; Enqueue n0 (pri 0)
        jsr     LVO_ENQUEUE(a6)
        move.l  a4,a0
        lea     16(a3),a1           ; Enqueue n1 (pri 10)
        jsr     LVO_ENQUEUE(a6)
        move.l  a4,a0
        lea     32(a3),a1           ; Enqueue n2 (pri 5)
        jsr     LVO_ENQUEUE(a6)
        ; ordre attendu : head=n1, n1->Succ=n2, n2->Succ=n0, n0->Succ=&lh_Tail
        move.l  (a4),a0             ; lh_Head
        lea     16(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n1->Succ
        lea     32(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n2->Succ
        move.l  a3,a1
        cmp.l   a1,a0
        bne.w   .bad
        move.l  (a0),a0             ; n0->Succ == &lh_Tail (= a4+LH_TAIL)
        lea     LH_TAIL(a4),a1
        cmp.l   a1,a0
        bne.w   .bad
        ; RemHead -> n1 ; nouvelle tête = n2
        move.l  a4,a0
        jsr     LVO_REMHEAD(a6)
        lea     16(a3),a1
        cmp.l   a1,d0
        bne.w   .bad
        move.l  (a4),a0
        lea     32(a3),a1
        cmp.l   a1,a0
        bne.w   .bad
        ; RemTail -> n0 (plus basse pri, en queue)
        move.l  a4,a0
        jsr     LVO_REMTAIL(a6)
        move.l  a3,a1
        cmp.l   a1,d0
        bne.w   .bad
        ; Insert(list, n0, pred=n2) -> n2->Succ == n0
        move.l  a4,a0
        move.l  a3,a1               ; node n0
        lea     32(a3),a2           ; pred n2
        jsr     LVO_INSERT(a6)
        lea     32(a3),a0
        move.l  (a0),a0             ; n2->Succ
        move.l  a3,a1
        cmp.l   a1,a0
        bne.w   .bad
        ; libère list + noeuds
        move.l  a4,a1
        move.l  #16,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a3,a1
        move.l  #(3*16),d0
        jsr     LVO_FREEMEM(a6)
        lea     chk_m24a(pc),a0      ; checkpoint : multi-header + listes
        bsr     ser_puts

        ; ===== M2.4b : tâches + signaux (non bloquants) =====
        ; FindTask(NULL) == ThisTask
        sub.l   a1,a1
        jsr     LVO_FINDTASK(a6)
        cmp.l   EB_THISTASK(a6),d0
        bne.w   .bad
        ; AllocSignal(-1) -> 16 (bits 0-15 pré-alloués via SYS_SIGALLOC)
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #16,d0
        bne.w   .bad
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #17,d0
        bne.w   .bad
        moveq   #16,d0               ; libère 16 -> redevient le plus petit libre
        jsr     LVO_FREESIGNAL(a6)
        moveq   #-1,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #16,d0
        bne.w   .bad
        ; AllocSignal efface un SIGRECVD rémanent sur le bit alloué
        move.l  EB_THISTASK(a6),a2
        or.l    #$00100000,TC_SIGRECVD(a2)   ; bit 20 rémanent
        moveq   #20,d0
        jsr     LVO_ALLOCSIGNAL(a6)
        cmp.l   #20,d0
        bne.w   .bad
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00100000,d0
        bne.w   .bad                 ; le bit 20 doit avoir été effacé
        ; SetSignal : pose le bit 16, retourne l'ancien jeu
        move.l  #$00010000,d0
        move.l  #$00010000,d1
        jsr     LVO_SETSIGNAL(a6)
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00010000,d0
        beq.w   .bad
        ; Signal(ThisTask, bit 17) -> bit posé dans SIGRECVD
        move.l  a2,a1
        move.l  #$00020000,d0
        jsr     LVO_SIGNAL(a6)
        move.l  TC_SIGRECVD(a2),d0
        and.l   #$00020000,d0
        beq.w   .bad
        ; SetTaskPri(ThisTask,5) -> ancienne 0 ; LN_PRI == 5 ; puis restaure 0
        move.l  a2,a1
        moveq   #5,d0
        jsr     LVO_SETTASKPRI(a6)
        tst.l   d0
        bne.w   .bad
        cmp.b   #5,LN_PRI(a2)
        bne.w   .bad
        move.l  a2,a1
        moveq   #0,d0
        jsr     LVO_SETTASKPRI(a6)
        moveq   #16,d0               ; nettoie les signaux de test (16,17,20)
        jsr     LVO_FREESIGNAL(a6)
        moveq   #17,d0
        jsr     LVO_FREESIGNAL(a6)
        moveq   #20,d0
        jsr     LVO_FREESIGNAL(a6)
        move.l  #0,TC_SIGRECVD(a2)   ; remet SIGRECVD propre

        ; FindTask(nom) : nœud tâche factice dans TaskReady
        move.l  #TC_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3                ; tâche factice
        move.b  #NT_TASK,LN_TYPE(a3)
        move.l  #task_test_name,LN_NAME(a3)
        lea     EB_TASKREADY(a6),a0
        move.l  a3,a1
        jsr     LVO_ADDTAIL(a6)
        move.l  #task_test_name,a1
        jsr     LVO_FINDTASK(a6)
        cmp.l   a3,d0
        bne.w   .bad
        move.l  #str_gamma,a1        ; nom inconnu -> 0
        jsr     LVO_FINDTASK(a6)
        tst.l   d0
        bne.w   .bad
        move.l  a3,a1                ; retire + libère la tâche factice
        jsr     LVO_REMOVE(a6)
        move.l  a3,a1
        move.l  #TC_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        lea     chk_m24b(pc),a0      ; checkpoint : tâches + signaux
        bsr     ser_puts

        ; ===== M2.4c : ports / messages (non bloquants) =====
        moveq   #-1,d0               ; bit de signal pour le port
        jsr     LVO_ALLOCSIGNAL(a6)
        move.l  d0,d6                ; d6 = n° de bit
        move.l  #MP_SIZE,d0          ; port principal depuis le tas
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a2                ; a2 = port
        lea     MP_MSGLIST(a2),a1    ; le caller initialise la file
        jsr     newlist
        move.l  #str_port,LN_NAME(a2)
        move.b  #PA_SIGNAL,MP_FLAGS(a2)
        move.b  d6,MP_SIGBIT(a2)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a2)
        move.l  a2,a1
        jsr     LVO_ADDPORT(a6)
        ; FindPort(nom) == port ; FindPort(inconnu) == 0
        move.l  #str_port,a1
        jsr     LVO_FINDPORT(a6)
        cmp.l   a2,d0
        bne.w   .bad
        move.l  #str_gamma,a1
        jsr     LVO_FINDPORT(a6)
        tst.l   d0
        bne.w   .bad
        ; 2 messages depuis le tas (msg1=+0, msg2=+MN_SIZE)
        move.l  #(2*MN_SIZE),d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a3
        ; PutMsg(msg1) doit poser le bit du port dans SIGRECVD de ThisTask
        move.l  EB_THISTASK(a6),a0
        clr.l   TC_SIGRECVD(a0)
        move.l  a2,a0
        move.l  a3,a1
        jsr     LVO_PUTMSG(a6)
        move.l  EB_THISTASK(a6),a0
        move.l  TC_SIGRECVD(a0),d0
        moveq   #1,d1
        lsl.l   d6,d1
        and.l   d1,d0
        beq.w   .bad                 ; bit du port non posé
        ; PutMsg(msg2) ; GetMsg FIFO : msg1, msg2, puis 0 (vide)
        move.l  a2,a0
        lea     MN_SIZE(a3),a1
        jsr     LVO_PUTMSG(a6)
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        cmp.l   a3,d0
        bne.w   .bad
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        lea     MN_SIZE(a3),a1
        cmp.l   a1,d0
        bne.w   .bad
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        bne.w   .bad
        ; ReplyMsg : msg1 revient sur un reply port avec le type NT_REPLYMSG
        move.l  #MP_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.w   .bad
        move.l  d0,a4                ; a4 = reply port
        lea     MP_MSGLIST(a4),a1
        jsr     newlist
        move.b  #PA_IGNORE,MP_FLAGS(a4)   ; pas de signal au reply
        move.l  a4,MN_REPLYPORT(a3)
        move.l  a3,a1
        jsr     LVO_REPLYMSG(a6)
        move.l  a4,a0
        jsr     LVO_GETMSG(a6)
        cmp.l   a3,d0                ; msg1 revenu sur le reply port
        bne.w   .bad
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne.w   .bad
        ; nettoyage : RemPort du port PUBLIC seulement (rport n'a jamais été
        ; AddPort'd -> le retirer appellerait Remove sur un noeud non chaîné, qui
        ; écrirait dans la low RAM $0/$4). free messages + ports + signal.
        move.l  a2,a1
        jsr     LVO_REMPORT(a6)
        move.l  a3,a1
        move.l  #(2*MN_SIZE),d0
        jsr     LVO_FREEMEM(a6)
        move.l  a4,a1
        move.l  #MP_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  a2,a1
        move.l  #MP_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d6,d0
        jsr     LVO_FREESIGNAL(a6)
        lea     chk_m24c(pc),a0      ; checkpoint : ports + messages
        bsr     ser_puts

        ; invariant final : tas chip revenu à la baseline (chunk unique)
        lea     MH_CHIP,a0
        move.l  MH_FIRST(a0),d0
        cmp.l   a5,d0
        bne.w   .bad
        move.l  d0,a0
        cmp.l   MC_BYTES(a0),d7
        bne.w   .bad

        moveq   #0,d0
        bra.s   .out
.bad:
        moveq   #1,d0
.out:
        movem.l (sp)+,d6-d7/a2-a5
        rts

; ============================ démo recombinaison (M3f) ==============
; Crée 3 tâches superviseur et les met dans TaskReady. Scaffolding de PREUVE (comme le
; selftest) : sera remplacé par la suite d'init exec (scan résidents) plus tard. Signal
; CÂBLÉ EN DUR (DEMO_SIG=16, hors 0-15 réservés) plutôt qu'AllocSignal (qui opère sur
; ThisTask = tâche de boot ; Wait/Signal ne consultent que le MASQUE). task_L signale
; task_H via son TCB publié dans WP_HTASK (posé AVANT lancement -> toujours valide).
;   task_H (pri 10) : cible du yield. task_L/task_S (pri 0) : round-robin préemptif.
setup_demo_tasks:                    ; a6 = SysBase ; clobbers scratch + d2/a2-a4 (sauvés)
        movem.l d2/a2-a4,-(sp)
        clr.l   WP_HTASK             ; RAM basse non garantie nulle au power-on -> explicite
        clr.l   FB_TASK              ; preuve atomicité Forbid : TCB de task_fb (posé à la création)
        clr.l   FORBID_TEST_FLAG     ; flag « fb a tourné » (task_fa le ré-efface avant son test)
        clr.l   WP_CONS
        clr.l   WP_PROD
        clr.l   WP_SPIN
        clr.l   WP_STAT
        clr.l   WP_TCONS             ; M7a : réveils de task_timer
        clr.b   QUANTUM_ELAPSED      ; M7h : time-slice courant
        clr.l   QUANTUM_EXPIRE_N     ; M7h : expirations de quantum
        clr.l   Q2_RUNS              ; M7h : itérations du 2e spinner
        clr.b   M7H_STAT             ; M7h : marqueur « M7H QUANTUM OK » pas encore émis
        clr.l   RM_RUNS              ; M7j : itérations de task_rm
        clr.b   M7J_STAT             ; M7j : marqueur « M7J REMTASK OK » pas encore émis
                ifne    M7H_QUANTUM_DEMO
        ; === M7h : démo d'ISOLATION du quantum — SEULEMENT 2 spinners pri 0, aucun préempteur ===
        ; prioritaire ni yield -> la rotation n'est pilotée QUE par le quantum VBlank (observable).
        lea     task_s(pc),a2        ; spinner-1 (compteur WP_SPIN)
        lea     task_s_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
        lea     task_q2(pc),a2       ; spinner-2 (compteur Q2_RUNS + émet « M7H QUANTUM OK »)
        lea     task_q2_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
                else
                ifeq    PROD            ; PROD : tâches démo M7 (scheduler proofs : H/L/S/timer/port/fa/fb) -> hors prod
        lea     task_h(pc),a2        ; task_H (pri 10) -> tête (Enqueue trie), publiée
        lea     task_h_name(pc),a3
        moveq   #DEMO_PRI_H,d2
        bsr     mk_demo_task
        move.l  a4,WP_HTASK
        lea     task_l(pc),a2        ; task_L (pri 0) : signale+yield+spin préemptible
        lea     task_l_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
                ifeq    M7E_COOP
        lea     task_s(pc),a2        ; task_S (pri 0) : spinner pur (dispatché par préemption)
        lea     task_s_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task         ; M7E_COOP=1 : retiré (monopoliserait sans préemption)
        ; preuve atomicité Forbid (SCHED_ON=1 seulement) : fb (pri 7) créée+publiée AVANT fa (pri 3) pour être en
        ; Wait quand fa la signale sous Forbid. fa vérifie que fb ne préempte PAS son Forbid -> « FORBID ATOMIC OK ».
        lea     task_fb(pc),a2       ; task_fb (pri 7) : victime prioritaire
        lea     task_fb_name(pc),a3
        moveq   #FB_PRI_FB,d2
        bsr     mk_demo_task
        move.l  a4,FB_TASK           ; publie le TCB de fb (fa le signale)
        lea     task_fa(pc),a2       ; task_fa (pri 3) : tient le Forbid + signale fb + vérifie l'atomicité
        lea     task_fa_name(pc),a3
        moveq   #FB_PRI_FA,d2
        bsr     mk_demo_task
                endc
        lea     task_semw(pc),a2     ; task_semw (pri 5) : bloque dans ObtainSemaphore (sémaphore tenu par le boot)
        lea     task_semw_name(pc),a3
        moveq   #5,d2
        bsr     mk_demo_task
        lea     task_semr(pc),a2     ; task_semr (pri 0) : ReleaseSemaphore -> transmet à task_semw
        lea     task_semr_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
        lea     task_aud(pc),a2      ; task_aud (pri 5) : lecture DMA par audio.device (« AUDIO PLAY OK ») ; au-dessus
        lea     task_aud_name(pc),a3 ; du shell et de la console, sinon un boot qui affiche beaucoup l'affame et elle
        moveq   #5,d2                ; rate la fenêtre « w1 rendu, w2 en cours » qu'elle doit observer
        bsr     mk_demo_task
        lea     task_timer(pc),a2    ; task_timer (pri 10, M7a) : bloque sur l'unité MICROHZ
        lea     task_t_name(pc),a3
        moveq   #DEMO_PRI_T,d2
        bsr     mk_demo_task
                ifeq    M7E_COOP
        lea     task_port(pc),a2     ; task_port (pri 0, M7d) : martèle le port partagé (consommateur TÂCHE)
        lea     task_p_name(pc),a3
        moveq   #DEMO_PRI_P,d2
        bsr     mk_demo_task         ; M7E_COOP=1 : retiré (spinner pur, monopoliserait sans préemption)
                endc
                endc                    ; fin tâches démo M7 (PROD=0)
        ; --- D3a : créer le process file-handler (echo) + le process driver (tournent après dispatch_in) ---
        ; Créés dans les DEUX modes (GREEN SCHED_ON=1 ET COOP) : driver/handler bloquent sur WaitPort (switch
        ; synchrone M3d) -> round-trip packet coopératif. proc_create via jsr (process.o hors portée bsr).
        ; Paire echo PRIORITAIRE (8/7) au-dessus de la paire OFS (6/5) : son round-trip (rapide, sans disque)
        ; s'achève TÔT -> « D3A » émis bien avant la lecture OFS lente -> pas d'émission série concurrente avec D3B.
                ifeq    PROD            ; PROD : paire echo D3a = preuve round-trip packet (D3A) -> hors prod
        lea     d3a_hname(pc),a0
        lea     d3a_handler(pc),a1
        moveq   #8,d0                ; echo handler pri 8
        move.l  #D3_STK,d1
        jsr     proc_create
        move.l  d0,DOS_HANDLERPORT   ; publie le port du handler pour le driver
        lea     d3a_dname(pc),a0
        lea     d3a_driver(pc),a1
        moveq   #7,d0                ; echo driver pri 7
        move.l  #D3_STK,d1
        jsr     proc_create
                endc                    ; fin paire echo D3a (PROD=0)
        ; --- D3b : créer le process file-handler DF0: (OFS) — INFRASTRUCTURE (le CLI résout DF0: par lui). Le
        ; fs-driver qui suit est un CLIENT de PREUVE (lit « kickslop » -> « D3B HANDLER OK ») -> gaté en prod. ---
        lea     d3b_hname(pc),a0
        move.l  #dos_handler_df0,a1  ; absolu : handler.o lié hors portée lea(pc) 16 bits
        moveq   #6,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        move.l  d0,DOS_FSPORT        ; publie le port du file-handler OFS
                ifeq    PROD            ; PROD : fs-driver = client de preuve D3b (lit kickslop) -> hors prod ; le handler reste
        lea     d3b_dname(pc),a0
        lea     dos_fsdriver(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
                endc                    ; fin fs-driver de preuve D3b (PROD=0)
        ; --- D3c : monter un DeviceNode DF0: dans DosInfo.di_DevInfo (dn_Task = port du handler OFS) + client dos ---
        lea     EB_LIBLIST(a6),a0
        lea     dos_libname(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .d3c_noclient        ; pas de dos.library (ne devrait pas) -> pas de client
        move.l  d0,a2                ; a2 = DosBase
        move.l  #DN_SIZEOF+4+FSSM_SIZEOF,d0  ; + BSTR « DF0 » + FileSysStartupMsg (long-alignés : BPTR)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .d3c_noclient
        move.l  d0,a3                ; a3 = DeviceNode (dn_Type = DLT_DEVICE = 0 via MEMF_CLEAR)
        move.l  DOS_FSPORT,DN_TASK(a3)   ; dn_Task = port du process file-handler OFS
        move.l  #$03444630,DN_SIZEOF(a3) ; BSTR : longueur 3, « DF0 »
        lea     DN_SIZEOF(a3),a0
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,DN_NAME(a3)       ; dn_Name -> dos résout « DF0: » par ce nœud
        lea     DN_SIZEOF+4(a3),a0   ; FileSysStartupMsg : unité 0 (MEMF_CLEAR), « trackdisk.device », géométrie DD
        lea     df0_device(pc),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,FSSM_DEVICE(a0)
        lea     df0_environ(pc),a1
        move.l  a1,d0
        lsr.l   #2,d0
        move.l  d0,FSSM_ENVIRON(a0)
        move.l  a0,d0
        lsr.l   #2,d0
        move.l  d0,DN_STARTUP(a3)
        move.l  DL_ROOT(a2),a0       ; RootNode (APTR)
        move.l  RN_INFO(a0),d0       ; BPTR DosInfo
        lsl.l   #2,d0
        move.l  d0,a0                ; DosInfo
        move.l  a3,d0
        lsr.l   #2,d0                ; BPTR(DeviceNode)
        move.l  d0,DI_DEVINFO(a0)    ; di_DevInfo = BPTR(DeviceNode) -> dos Open résout DF0: par ce nœud
                ifeq    PROD            ; PROD : clients de test D3 (d3c..d3j lisent kickslop/D3DTest/bigseg/BigData,
                                        ; absents d'un vrai disque Workbench) -> hors prod ; le MONTAGE DF0: ci-dessus reste
        lea     d3c_cname(pc),a0
        lea     d3c_client(pc),a1
        moveq   #4,d0                ; client pri 4 (bloque sur packets ; sous echo/OFS)
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3d : client qui charge+exécute « D3DTest » À TRAVERS dos (Open/Read par packets -> ls_load_hunks -> run)
        lea     d3d_cname(pc),a0
        lea     d3d_client(pc),a1
        moveq   #3,d0                ; pri 3 (sous le client D3c)
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3e : client qui charge « D3DTest » via le VRAI vecteur LVO LoadSeg(-150) de dos.library (qui compose
        ; Open/Read/Close + ls_load_hunks EN INTERNE) puis UnLoadSeg(-156). Prouve LoadSeg par vecteur LVO ; d3d
        ; (load inline) reste la baseline indépendante de la couche en-dessous -> RED LOADSEG_LVO_UNWIRED isole d3e.
        lea     d3e_cname(pc),a0
        lea     d3e_client(pc),a1
        moveq   #5,d0                ; pri 5 : AU-DESSUS du shell (Initial CLI pri 2) -> d3e charge+émet TÔT, hors de
                                     ; la fenêtre tardive startup-sequence (sinon son marqueur entrelace « E3 CMD RAN OK »)
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3f : client prouvant IoErr(-132) + Seek(-66). pri 5 + émet sous Forbid (même discipline que d3e : tôt,
        ; hors fenêtre startup, atomique). IoErr : Open absent -> 0 + IoErr != 0 ; Open d3dtest -> IoErr 0. Seek :
        ; Read 4 -> Seek(0,BEGINNING) -> Read 4 identiques (repositionnement).
        lea     d3f_cname(pc),a0
        lea     d3f_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3g : client prouvant CurrentDir(-126) + Input(-54) + Output(-60) + Write(-48). pri 5. CurrentDir/Input
        ; round-trip, puis pr_COS = FileHandle console (fh_Type = DOS_CONPORT) ; Write(Output(), marqueur) -> le
        ; marqueur « DOS WRITE OK » est émis PAR le Write via con_handler (prouve les 4 d'un coup).
        lea     d3g_cname(pc),a0
        lea     d3g_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3h : client prouvant le cap-bump LoadSeg. Charge « bigseg » (> 16 Ko) via LoadSeg(-150) + l'exécute :
        ; le binaire vérifie une sentinelle en fin de son gros DATA et émet « LOADSEG BIG OK » si tout a été lu.
        lea     d3h_cname(pc),a0
        lea     d3h_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3i : client prouvant Lock(-84)/UnLock(-90)/Examine(-102)/ExNext(-108). pri 5 (même discipline : tôt, hors
        ; fenêtre startup, émet sous ser_lock). Lock("kickslop")->Examine (fichier, 1024 o) ; Lock(":")->ExNext trouve
        ; kickslop par énumération du répertoire racine.
        lea     d3i_cname(pc),a0
        lea     d3i_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        ; D3j : client prouvant le STREAMING OFS RÉEL. pri 5. Ouvre « BigData » (48000 o > ancien cap 32 Ko), le lit
        ; en entier par chunks (lecture incrémentale sans buffer whole-file) + seek cross-block -> « OFS STREAM OK ».
        lea     d3j_cname(pc),a0
        lea     d3j_client(pc),a1
        moveq   #5,d0
        move.l  #D3_STK,d1
        jsr     proc_create
                endc                    ; fin clients de test D3 (PROD=0)
        ; --- E1 : handler console-série (pri 6, comme le handler OFS). INFRASTRUCTURE -> créé inconditionnellement.
        ; Le shell (Initial CLI, F1) n'est PAS créé ici : il est GATÉ sur un disque bootable (branche .m6r_booted).
        lea     e1_hname(pc),a0
        move.l  #con_handler,a1      ; absolu : conhandler.o lié hors portée lea(pc) 16 bits
        moveq   #6,d0
        move.l  #D3_STK,d1
        jsr     proc_create
        move.l  d0,DOS_CONPORT       ; publie le port du handler console
        ; --- feeder clavier -> input.device (intégration F, item 1) : INFRASTRUCTURE, créé inconditionnellement.
        ; Draine le ring brut du clavier (KBD_FEEDRING) et injecte les RAWKEY dans input.device (IND_WRITEEVENT).
        lea     fd_cname(pc),a0
        move.l  #feeder_main,a1      ; absolu : feeder.o lié hors portée lea(pc) 16 bits
        moveq   #4,d0                ; pri 4 (sous le handler console)
        move.l  #D3_STK,d1
        jsr     proc_create
.d3c_noclient:
                ifne    M7J_DEMO
        ; M7j : capture AvailMem AVANT de créer task_rm (baseline) ; après son auto-retrait, AvailMem
        ; doit remonter d'au moins M7J_RECOVER (pile+TCB libérés). task_timer vérifie la remontée.
        moveq   #0,d1                ; AvailMem(requirements=0) -> total libre
        jsr     LVO_AVAILMEM(a6)
        move.l  d0,M7J_AVAIL_BEFORE
        lea     task_rm(pc),a2       ; tâche à durée de vie finie (RTS -> task_exit -> RemTask self)
        lea     task_rm_name(pc),a3
        moveq   #0,d2
        bsr     mk_demo_task
                endc
                endc
        movem.l (sp)+,d2/a2-a4
        rts

; setup_stress_port (M7d) : crée le port partagé + STRESS_K messages (MAGIC + IN_HAND=0), tous AddTail'd
; sur le port. a6 = SysBase. WP_SPORT est écrit EN DERNIER (une fois le port prêt) pour que le service
; MICROHZ (qui teste WP_SPORT) ne le voie qu'entièrement construit. clobbers scratch + d2/a2 (sauvés).
setup_stress_port:
                ifne    PROD            ; PROD : pas de stress M7d ; efface WP_SPORT -> le service MICROHZ le voit
        clr.l   WP_SPORT             ; nul et saute la voie de stress (sinon valeur power-up aléatoire = crash)
        rts
                endc
        movem.l d2/a2,-(sp)
        clr.l   WP_SPORT             ; (RAM basse non garantie nulle)
        clr.l   WP_PORTT
        clr.l   WP_PORTI
        clr.l   WP_PORTFAIL
        clr.b   M7D_STAT
        move.l  #MP_SIZE,d0          ; alloue le port
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7d_fail
        move.l  d0,a2                ; a2 = port
        move.b  #NT_MSGPORT,LN_TYPE(a2)
        move.b  #PA_IGNORE,MP_FLAGS(a2)   ; action != PA_SIGNAL -> PutMsg saute la voie de signal
        move.l  a2,a1                ; NEWLIST(&port->MsgList)
        lea     MP_MSGLIST(a2),a1
        jsr     newlist
        moveq   #STRESS_K,d2         ; d2 = compteur de messages à créer
.sp_loop:
        move.l  #STRESS_MSG_SIZE,d0
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7d_fail
        move.l  d0,a1                ; a1 = message
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.l  #STRESS_MAGIC,MSG_MAGIC_OFF(a1)   ; MAGIC ; IN_HAND déjà 0 (MEMF_CLEAR)
        lea     MP_MSGLIST(a2),a0    ; AddTail(&port->MsgList, msg)
        jsr     LVO_ADDTAIL(a6)
        subq.l  #1,d2
        bne.s   .sp_loop
        move.l  a2,WP_SPORT          ; port prêt -> publié EN DERNIER
        movem.l (sp)+,d2/a2
        rts

; --- D3a : corps du process file-handler ECHO + du process driver (preuve process + round-trip packet) ---
; Les corps démarrent GPR à zéro (frame AddTask) -> rechargent SysBase depuis ($4).w. Le handler boucle
; WaitPort/GetMsg sur SON pr_MsgPort et renvoie dp_Res1 = dp_Arg1 (echo). Le driver monte un StandardPacket,
; PutMsg au port du handler, WaitPort(son port)/GetMsg, vérifie l'echo, émet « D3A », puis bloque pour toujours.
; Round-trip via WaitPort = switch SYNCHRONE (M3d) -> fonctionne en GREEN (préemption) ET en COOP.
d3a_handler:
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a2
        lea     PR_MSGPORT(a2),a2    ; a2 = pr_MsgPort du handler (le sien)
.h_loop:
        move.l  a2,a0
        jsr     LVO_WAITPORT(a6)     ; bloque jusqu'à l'arrivée d'un message
        move.l  a2,a0
        jsr     LVO_GETMSG(a6)       ; d0 = Message | 0
        tst.l   d0
        beq.s   .h_loop
        move.l  d0,a1                ; a1 = Message (= &sp_Msg)
        move.l  LN_NAME(a1),a3       ; a3 = &sp_Pkt (convention : msg->ln_Name -> DosPacket)
                ifeq    D3A_NO_REPLY
        move.l  DP_ARG1(a3),DP_RES1(a3)   ; ECHO : res1 = arg1
        jsr     LVO_REPLYMSG(a6)     ; renvoie au mn_ReplyPort (port du driver)
                endc                 ; RED D3A_NO_REPLY : ne répond pas -> le driver reste bloqué -> « D3A » absent
        bra.s   .h_loop
d3a_driver:
        move.l  ($4).w,a6
        move.l  EB_THISTASK(a6),a4
        lea     PR_MSGPORT(a4),a4    ; a4 = pr_MsgPort du driver (port de réponse)
        move.l  #SP_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq.s   .d_block
        move.l  d0,a2                ; a2 = StandardPacket (&sp_Msg)
        lea     SP_PKT(a2),a3        ; a3 = &sp_Pkt (DosPacket)
        move.b  #NT_MESSAGE,LN_TYPE(a2)
        move.l  a4,MN_REPLYPORT(a2)  ; ReplyMsg reviendra ici
        move.w  #DP_SIZEOF,MN_LENGTH(a2)
        move.l  a3,LN_NAME(a2)       ; sp_Msg.ln_Name -> sp_Pkt
        move.l  a2,DP_LINK(a3)
        move.l  a4,DP_PORT(a3)
        move.l  #ACTION_READ,DP_TYPE(a3)   ; valeur de test (echo ne l'interprète pas)
        move.l  #$D3A0CAFE,DP_ARG1(a3)     ; magic à echoer
        move.l  DOS_HANDLERPORT,a0
        move.l  a2,a1
        jsr     LVO_PUTMSG(a6)       ; PutMsg(handlerPort, &sp_Msg) -> signale le handler
        move.l  a4,a0
        jsr     LVO_WAITPORT(a6)     ; attend la réponse (switch synchrone -> handler)
        move.l  a4,a0
        jsr     LVO_GETMSG(a6)
        lea     SP_PKT(a2),a3
        cmp.l   #$D3A0CAFE,DP_RES1(a3)    ; echo correct ?
        bne.s   .d_free
        jsr     LVO_FORBID(a6)       ; émission atomique (évite l'entrelacement série avec le fs-driver)
        lea     msg_d3a_ok(pc),a0
        bsr     ser_puts             ; « D3A ... OK »
        jsr     LVO_PERMIT(a6)
.d_free:
        move.l  a2,a1
        move.l  #SP_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.d_block:
        moveq   #0,d0                ; terminé -> bloque pour toujours (ne spinne pas)
        jsr     LVO_WAIT(a6)
        bra.s   .d_block

; --- D3b : corps du fs-driver — ouvre/lit/ferme « kickslop » À TRAVERS le process file-handler DF0: via packets ---
; FINDINPUT(BPTR fh, 0, BSTR nom) -> DOSTRUE + fh_Arg1 = clé ; READ(clé, buf, 1024) -> 1024 + marqueurs ;
; END(clé). Émet « D3B » si tout OK. Utilise dos_sendpkt (process.s). a5 = bloc, d6 = flag succès, d7 = clé.
dos_fsdriver:
        move.l  ($4).w,a6
        move.l  #FSD_TOTAL,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .fd_block
        move.l  d0,a5                ; a5 = bloc (persistant)
        moveq   #0,d6                ; d6 = flag succès
        ; construire le BSTR nom {8,"kickslop"} à a5+FSD_NAME
        lea     FSD_NAME(a5),a1
        move.b  #8,(a1)+
        lea     fsd_name_src(pc),a0
        moveq   #8-1,d0
.fd_ncpy:
        move.b  (a0)+,(a1)+
        dbra    d0,.fd_ncpy
        ; --- FINDINPUT : arg1 = BPTR(fh), arg2 = 0, arg3 = BPTR(nom) ---
        lea     FSD_SP(a5),a0
        move.l  DOS_FSPORT,a1
        move.l  #ACTION_FINDINPUT,d0
        move.l  a5,d1
        add.l   #FSD_FH,d1
        lsr.l   #2,d1                ; BPTR(FileHandle)
        moveq   #0,d2                ; lock 0 (racine)
        move.l  a5,d3
        add.l   #FSD_NAME,d3
        lsr.l   #2,d3                ; BPTR(nom)
        jsr     dos_sendpkt          ; d0 = dp_Res1
        cmp.l   #DOSTRUE,d0
        bne     .fd_free
        move.l  a5,a0                ; clé = fh.FH_ARG1 (posée par le handler)
        add.l   #FSD_FH,a0
        move.l  FH_ARG1(a0),d7       ; d7 = clé du fichier
        ; --- READ : arg1 = clé, arg2 = buffer (APTR), arg3 = 1024 ---
        lea     FSD_SP(a5),a0
        move.l  DOS_FSPORT,a1
        move.l  #ACTION_READ,d0
        move.l  d7,d1
        move.l  a5,d2
        add.l   #FSD_BUF,d2          ; dest = buffer (APTR, PAS un BPTR)
        move.l  #1024,d3
        jsr     dos_sendpkt          ; d0 = octets lus
        cmp.l   #1024,d0
        bne.s   .fd_close
        lea     FSD_BUF(a5),a0       ; vérifier les marqueurs (mêmes que D1 : @0/@488/@976)
        cmp.l   #$44314F46,(a0)      ; "D1OF"
        bne.s   .fd_close
        cmp.l   #$534F4B30,4(a0)     ; "SOK0"
        bne.s   .fd_close
        cmp.l   #$534F4B31,492(a0)   ; "SOK1"
        bne.s   .fd_close
        cmp.l   #$534F4B32,980(a0)   ; "SOK2"
        bne.s   .fd_close
        moveq   #1,d6                ; succès
.fd_close:
        ; --- END : arg1 = clé (ferme toujours, même si READ a échoué) ---
        lea     FSD_SP(a5),a0
        move.l  DOS_FSPORT,a1
        move.l  #ACTION_END,d0
        move.l  d7,d1
        moveq   #0,d2
        moveq   #0,d3
        jsr     dos_sendpkt
        tst.l   d6
        beq.s   .fd_free
        jsr     LVO_FORBID(a6)       ; émission atomique (évite l'entrelacement série avec l'echo-driver)
        lea     msg_d3b_ok(pc),a0
        bsr     ser_puts             ; « D3B ... OK »
        jsr     LVO_PERMIT(a6)
.fd_free:
        move.l  a5,a1
        move.l  #FSD_TOTAL,d0
        jsr     LVO_FREEMEM(a6)
.fd_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .fd_block

; --- D3c : corps du process client dos — OpenLibrary(dos) + Open/Read/Close « kickslop » via les LVO dos ---
; Prouve la couche dos user-facing (Open/Read/Close fabriquent les packets vers le handler, appelées depuis un
; PROCESS qui fournit son pr_MsgPort comme port de réponse). a4 = DosBase, a5 = buffer, d6 = octets, d7 = BPTR fh.
d3c_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)  ; DosBase | 0
        tst.l   d0
        beq     .c_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  #2048,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .c_closelib
        move.l  d0,a5                ; a5 = buffer de lecture
        move.l  a4,a6                ; a6 = DosBase pour les appels dos
        lea     ofs_test_name(pc),a0
        move.l  a0,d1                ; name = « kickslop » (C-string)
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)     ; d0 = BPTR FileHandle | 0
        tst.l   d0
        beq     .c_free
        move.l  d0,d7                ; d7 = BPTR fh
        move.l  d7,d1
        move.l  a5,d2
        move.l  #1024,d3
        jsr     DOS_LVO_READ(a6)     ; d0 = octets lus
        move.l  d0,d6
        move.l  d7,d1
        jsr     DOS_LVO_CLOSE(a6)
        move.l  ($4).w,a6            ; -> SysBase (ser_puts / Forbid / FreeMem)
        cmp.l   #1024,d6             ; fichier complet lu via dos ?
        bne.s   .c_free
        cmp.l   #$44314F46,(a5)      ; « D1OF »
        bne.s   .c_free
        cmp.l   #$534F4B30,4(a5)     ; « SOK0 »
        bne.s   .c_free
        cmp.l   #$534F4B31,492(a5)   ; « SOK1 »
        bne.s   .c_free
        cmp.l   #$534F4B32,980(a5)   ; « SOK2 »
        bne.s   .c_free
        jsr     LVO_FORBID(a6)
        lea     msg_d3c_ok(pc),a0
        bsr     ser_puts             ; « D3C ... OK »
        jsr     LVO_PERMIT(a6)
.c_free:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #2048,d0
        jsr     LVO_FREEMEM(a6)
.c_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.c_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .c_block

; --- D3d : corps du client — charge « D3DTest » À TRAVERS dos (Open/Read par packets) puis l'EXÉCUTE ---
; OpenLibrary(dos) ; dos Open/Read/Close « d3dtest » dans un filebuf ; ls_load_hunks(filebuf,size) -> seglist ;
; JSR (seglist<<2)+4 -> la commande émet « D3D LOADSEG-VIA-DOS OK » depuis la RAM. Prouve la chaîne complète
; « charger une commande via dos ». a4=DosBase, a5=filebuf, d6=size, d7=fh puis BPTR seglist.
d3d_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .q_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  #16384,d0            ; filebuf (>= taille d'un exécutable hunk)
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .q_closelib
        move.l  d0,a5                ; a5 = filebuf
        move.l  a4,a6                ; a6 = DosBase pour les appels dos
        lea     d3d_fname(pc),a0
        move.l  a0,d1                ; « d3dtest »
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)     ; BPTR fh | 0
        tst.l   d0
        beq     .q_free
        move.l  d0,d7                ; d7 = BPTR fh
        move.l  d7,d1
        move.l  a5,d2                ; buffer
        move.l  #16384,d3            ; len (le handler renvoie la taille réelle)
        jsr     DOS_LVO_READ(a6)     ; d0 = octets lus = taille fichier
        move.l  d0,d6
        move.l  d7,d1
        jsr     DOS_LVO_CLOSE(a6)
        move.l  ($4).w,a6            ; -> SysBase
        tst.l   d6
        beq     .q_free              ; rien lu
        move.l  a5,a0
        move.l  d6,d0
        jsr     ls_load_hunks        ; d0 = BPTR seglist | 0 (jsr : loadseg.o loin)
        tst.l   d0
        beq     .q_free
        move.l  d0,d7                ; d7 = BPTR seglist
                ifeq    D3D_NO_RUN
        move.l  d7,d0                ; entry = (seglist<<2)+4 = contenu du 1er hunk (CODE)
        lsl.l   #2,d0
        addq.l  #4,d0
        move.l  d0,a0
        bsr     ser_lock             ; le binaire chargé émet sous Forbid -> son marqueur reste atomique
        jsr     (a0)                 ; exécute D3DTest -> émet « D3D LOADSEG-VIA-DOS OK »
        bsr     ser_unlock
        move.l  ($4).w,a6            ; recharge SysBase (le code chargé a pu clobber a6)
                endc                 ; RED D3D_NO_RUN : saute le run -> commande pas exécutée -> D3D absent
        move.l  d7,d0
        jsr     dos_unloadseg        ; libère le seglist
.q_free:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #16384,d0
        jsr     LVO_FREEMEM(a6)
.q_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.q_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .q_block

; d3e_client : charge « D3DTest » via le VRAI vecteur LVO LoadSeg(-150) de dos.library (qui ouvre/lit/parse/reloc
; EN INTERNE via Open/Read), prouve un seglist non nul (« D3E LOADSEG LVO OK »), puis UnLoadSeg(-156). Ne RE-exécute
; pas le programme (d3d le fait déjà) -> pas de double marqueur. a6 = SysBase à l'entrée (corps de process).
d3e_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq.s   .e_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  a4,a6
        lea     d3d_fname(pc),a0     ; « d3dtest » (même exécutable que d3d, prouvé chargeable)
        move.l  a0,d1
        jsr     DOS_LVO_LOADSEG(a6)  ; -150 : ouvre+lit+parse hunk+reloc via Open/Read -> BPTR seglist | 0
        tst.l   d0
        beq.s   .e_closelib          ; RED LOADSEG_LVO_UNWIRED : -150 = dos_null -> 0 -> pas de marqueur
        move.l  d0,d7                ; d7 = BPTR seglist (non nul = chargé+relocalisé via le vecteur LVO)
        move.l  ($4).w,a6            ; émet le marqueur sous Forbid (atomicité vs les autres émetteurs série)
        jsr     LVO_FORBID(a6)
        lea     msg_d3e_loadseg(pc),a0
        bsr     ser_puts             ; « D3E LOADSEG LVO OK »
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        move.l  a4,a6
        move.l  d7,d1
        jsr     DOS_LVO_UNLOADSEG(a6) ; -156 : libère le seglist
.e_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.e_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .e_block

; d3f_client : prouve IoErr(-132) + Seek(-66) via les vrais vecteurs LVO. a6 = SysBase à l'entrée (corps de process).
d3f_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .f_block
        move.l  d0,a4                ; a4 = DosBase
        ; IoErr : Open d'un nom ABSENT -> 0 puis IoErr != 0
        move.l  a4,a6
        lea     d3f_badname(pc),a0
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        tst.l   d0
        bne     .f_closelib          ; a ouvert à tort un nom absent -> abort
        move.l  a4,a6
        jsr     DOS_LVO_IOERR(a6)    ; doit être != 0 (ERROR_OBJECT_NOT_FOUND) ; RED DOS_NO_IOERR -> 0
        tst.l   d0
        beq     .f_closelib
        ; Open d3dtest ; IoErr doit repasser à 0
        move.l  a4,a6
        lea     d3d_fname(pc),a0
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        tst.l   d0
        beq     .f_closelib
        move.l  d0,d7                ; d7 = BPTR fh
        move.l  a4,a6
        jsr     DOS_LVO_IOERR(a6)    ; doit être 0 après un Open réussi
        tst.l   d0
        bne     .f_close
        ; Seek : Read 4 @0 -> Seek(0,BEGINNING) -> Read 4 identiques
        lea     -8(sp),sp            ; 2 buffers de 4 octets (buf1=sp, buf2=sp+4)
        move.l  a4,a6
        move.l  d7,d1
        move.l  sp,d2
        moveq   #4,d3
        jsr     DOS_LVO_READ(a6)     ; lit 4 @ pos 0 -> buf1
        cmp.l   #4,d0
        bne     .f_free8
        move.l  a4,a6                ; Seek(fh, 0, OFFSET_BEGINNING) -> ancienne pos (= 4)
        move.l  d7,d1
        moveq   #0,d2
        moveq   #OFFSET_BEGINNING,d3
        jsr     DOS_LVO_SEEK(a6)
        cmp.l   #4,d0                ; Seek rend l'ANCIENNE position (4) ; RED HND_NO_SEEK -> 4 aussi mais pos pas remise
        bne     .f_free8
        move.l  a4,a6                ; Read 4 à nouveau -> buf2
        move.l  d7,d1
        move.l  sp,d2
        addq.l  #4,d2
        moveq   #4,d3
        jsr     DOS_LVO_READ(a6)
        cmp.l   #4,d0
        bne     .f_free8
        move.l  (sp),d0              ; buf1 == buf2 ? (Seek a bien ramené au début)
        cmp.l   4(sp),d0
        bne     .f_free8
        lea     8(sp),sp
        move.l  ($4).w,a6            ; succès -> émet sous Forbid (atomicité série)
        jsr     LVO_FORBID(a6)
        lea     msg_d3f_ok(pc),a0
        bsr     ser_puts             ; « DOS IOERR SEEK OK »
        move.l  ($4).w,a6
        jsr     LVO_PERMIT(a6)
        bra.s   .f_close
.f_free8:
        lea     8(sp),sp
.f_close:
        move.l  a4,a6
        move.l  d7,d1
        jsr     DOS_LVO_CLOSE(a6)
.f_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.f_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .f_block

; d3g_client : prouve CurrentDir(-126) + Input(-54) + Output(-60) + Write(-48). a6 = SysBase à l'entrée (process).
d3g_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .g_block
        move.l  d0,a4                ; a4 = DosBase
        ; CurrentDir round-trip : pose $1234, puis 0 (doit rendre $1234)
        move.l  a4,a6
        move.l  #$1234,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        move.l  a4,a6
        moveq   #0,d1
        jsr     DOS_LVO_CURRENTDIR(a6)
        cmp.l   #$1234,d0
        bne     .g_closelib
        ; Input : pose pr_CIS = $5678, relit via Input()
        move.l  ($4).w,a0
        move.l  EB_THISTASK(a0),a0
        move.l  #$5678,PR_CIS(a0)
        move.l  a4,a6
        jsr     DOS_LVO_INPUT(a6)
        cmp.l   #$5678,d0
        bne     .g_closelib
        ; FileHandle console (fh_Type = DOS_CONPORT) pour Output/Write
        move.l  DOS_CONPORT,d7
        tst.l   d7
        beq     .g_closelib          ; pas de console
        move.l  ($4).w,a6
        move.l  #FH_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .g_closelib
        move.l  d0,a5                ; a5 = FileHandle
        move.l  d7,FH_TYPE(a5)       ; fh_Type = port con_handler
        move.l  ($4).w,a0            ; pr_COS = BPTR(a5)
        move.l  EB_THISTASK(a0),a0
        move.l  a5,d0
        lsr.l   #2,d0
        move.l  d0,PR_COS(a0)
        move.l  a4,a6                ; Output() doit rendre BPTR(a5)
        jsr     DOS_LVO_OUTPUT(a6)
        move.l  a5,d1
        lsr.l   #2,d1
        cmp.l   d1,d0
        bne.s   .g_free
        move.l  d0,d1                ; Write(Output() [BPTR], msg, len)
        move.l  #msg_dos_write,d2
        move.l  #msg_dos_write_len,d3
        move.l  a4,a6
        jsr     DOS_LVO_WRITE(a6)    ; con_handler émet « DOS WRITE OK » sur série (= le marqueur)
.g_free:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #FH_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.g_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.g_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .g_block

; d3h_client : prouve le cap-bump LoadSeg. Charge « bigseg » (> 16 Ko) via LoadSeg(-150) + l'exécute (le binaire
; vérifie la sentinelle en fin de son gros DATA -> émet « LOADSEG BIG OK » SSI tout a été lu). a6 = SysBase à l'entrée.
d3h_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .h_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  a4,a6
        lea     d3h_fname(pc),a0     ; « bigseg »
        move.l  a0,d1
        jsr     DOS_LVO_LOADSEG(a6)  ; -150 : charge l'exécutable > 16 Ko (cap 32 Ko)
        tst.l   d0
        beq.s   .h_closelib
        move.l  d0,d7                ; d7 = BPTR seglist
        move.l  d7,d0                ; entry = (seglist<<2)+4
        lsl.l   #2,d0
        addq.l  #4,d0
        move.l  d0,a0
        bsr     ser_lock             ; le binaire émet sous Forbid -> marqueur atomique
        jsr     (a0)                 ; exécute bigseg -> « LOADSEG BIG OK » si la sentinelle (fin du gros DATA) est bonne
        bsr     ser_unlock
        move.l  ($4).w,a6
        move.l  a4,a6
        move.l  d7,d1
        jsr     DOS_LVO_UNLOADSEG(a6)
.h_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.h_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .h_block

; d3i_client : prouve Lock(-84) + UnLock(-90) + Examine(-102) + ExNext(-108) via les vrais vecteurs LVO. a6 = SysBase
; à l'entrée (corps de process). (A) Lock("kickslop") -> Examine -> fib : DirEntryType < 0 (fichier) ET Size == 1024
; (ORACLE byte_size@324 confirmé sur l'ADF). (B) Lock(":") [racine] -> Examine -> DirEntryType > 0 (répertoire) ->
; ExNext en boucle -> trouve l'entrée fichier de 1024 octets (= kickslop spécifiquement, note advisor). Le curseur
; d'énumération vit dans le lock (flp_Bucket/flp_ChainBlk) -> déviation documentée (le vrai OS le garde dans le FIB).
d3i_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .i_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  ($4).w,a6            ; FileInfoBlock long-aligné (AllocMem -> BPTR réversible)
        move.l  #FIB_SIZEOF,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .i_closelib
        move.l  d0,a5                ; a5 = fib
        ; --- (A) Examine un FICHIER : Lock("kickslop") ---
        move.l  a4,a6
        lea     ofs_test_name(pc),a0 ; "kickslop"
        move.l  a0,d1
        move.l  #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)     ; -84 -> BPTR lock
        tst.l   d0
        beq     .i_freefib
        move.l  d0,d6                ; d6 = BPTR lock (fichier)
        move.l  a4,a6
        move.l  d6,d1
        move.l  a5,d2               ; fib
        jsr     DOS_LVO_EXAMINE(a6)  ; -102
        tst.l   d0
        beq     .i_unlockfile
        move.l  FIB_DIRENTRYTYPE(a5),d0
        bpl     .i_unlockfile        ; >= 0 -> pas un fichier
        move.l  FIB_SIZE(a5),d0
        cmp.l   #1024,d0            ; ORACLE : taille lue @324 -> write@124 -> readback
        bne     .i_unlockfile
        moveq   #1,d3               ; d3 = (A) fichier OK
        bra.s   .i_fileok
.i_unlockfile:
        moveq   #0,d3
.i_fileok:
        move.l  a4,a6               ; UnLock(fichier)
        move.l  d6,d1
        jsr     DOS_LVO_UNLOCK(a6)   ; -90
        tst.l   d3
        beq     .i_freefib
        ; --- (B) Examine + ExNext un RÉPERTOIRE : Lock(":") ---
        move.l  a4,a6
        lea     d3i_rootname(pc),a0  ; ":"
        move.l  a0,d1
        move.l  #SHARED_LOCK,d2
        jsr     DOS_LVO_LOCK(a6)
        tst.l   d0
        beq     .i_freefib
        move.l  d0,d6               ; d6 = BPTR lock (racine)
        move.l  a4,a6               ; Examine racine -> doit être un répertoire
        move.l  d6,d1
        move.l  a5,d2
        jsr     DOS_LVO_EXAMINE(a6)
        tst.l   d0
        beq     .i_unlockroot
        move.l  FIB_DIRENTRYTYPE(a5),d0
        ble     .i_unlockroot        ; <= 0 -> pas un répertoire
        moveq   #0,d4               ; d4 = flag « kickslop trouvé par ExNext »
        moveq   #24,d5              ; cap d'itérations (anti-boucle)
.i_exloop:
        move.l  a4,a6
        move.l  d6,d1
        move.l  a5,d2
        jsr     DOS_LVO_EXNEXT(a6)   ; -108
        tst.l   d0
        beq.s   .i_exdone            ; DOSFALSE -> fin d'énumération (ERROR_NO_MORE_ENTRIES)
        move.l  FIB_DIRENTRYTYPE(a5),d0
        bpl.s   .i_exnextit          ; répertoire -> pas kickslop
        move.l  FIB_SIZE(a5),d0
        cmp.l   #1024,d0            ; entrée fichier de 1024 octets = kickslop (unique sur l'ADF)
        bne.s   .i_exnextit
        moveq   #1,d4
.i_exnextit:
        subq.l  #1,d5
        bne.s   .i_exloop
.i_exdone:
        move.l  a4,a6               ; UnLock(racine)
        move.l  d6,d1
        jsr     DOS_LVO_UNLOCK(a6)
        tst.l   d4
        beq.s   .i_freefib           ; énumération n'a pas trouvé kickslop
        bsr     ser_lock             ; (A) && (B) OK -> émet sous ser_lock (atomicité série)
        lea     msg_d3i_ok(pc),a0
        bsr     ser_puts             ; « DOS LOCK EXAMINE OK »
        bsr     ser_unlock
        bra.s   .i_freefib
.i_unlockroot:
        move.l  a4,a6
        move.l  d6,d1
        jsr     DOS_LVO_UNLOCK(a6)
.i_freefib:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #FIB_SIZEOF,d0
        jsr     LVO_FREEMEM(a6)
.i_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.i_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .i_block

D3J_BUFSZ       EQU 4096             ; taille des chunks de lecture (non-multiple de 488 -> traverse les data blocks)
D3J_SIZE        EQU 48000            ; taille de BigData (> ancien cap 32 Ko)

; d3j_client : prouve le STREAMING OFS RÉEL. Ouvre « BigData » (48000 o, > ancien cap whole-file DOS_FILEMAX=32 Ko)
; via dos Open, le lit INTÉGRALEMENT en chunks de 4096 o (12 Read, le curseur avance dans l'état de streaming entre
; chaque appel), vérifie total == 48000 ET sentinelle $B16B00B5 aux 4 derniers octets. Puis Seek(500, BEGINNING) +
; Read(4) == $A5EE3780 (seek cross-block : rewind + marche avant jusqu'au bloc contenant l'octet 500). Ancien handler
; whole-file aurait tronqué à 32 Ko -> preuve auto-suffisante du cap levé. a6 = SysBase à l'entrée. pri 5, sous ser_lock.
d3j_client:
        move.l  ($4).w,a6
        lea     dos_libname(pc),a1
        moveq   #0,d0
        jsr     LVO_OPENLIBRARY(a6)
        tst.l   d0
        beq     .j_block
        move.l  d0,a4                ; a4 = DosBase
        move.l  ($4).w,a6
        move.l  #D3J_BUFSZ,d0        ; buffer de lecture
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .j_closelib
        move.l  d0,a5               ; a5 = buffer
        move.l  a4,a6
        lea     d3j_fname(pc),a0     ; « BigData »
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        jsr     DOS_LVO_OPEN(a6)
        tst.l   d0
        beq     .j_freebuf
        move.l  d0,d7               ; d7 = BPTR fh
        moveq   #0,d5               ; d5 = total lu
        moveq   #0,d4               ; d4 = 4 derniers octets du flux
.j_rloop:
        move.l  a4,a6
        move.l  d7,d1
        move.l  a5,d2
        move.l  #D3J_BUFSZ,d3
        jsr     DOS_LVO_READ(a6)    ; lit un chunk incrémental (data-block par data-block côté handler)
        tst.l   d0
        ble.s   .j_rdone            ; 0 (EOF) ou erreur
        add.l   d0,d5               ; total += n
        cmp.l   #4,d0
        blo.s   .j_rloop            ; chunk < 4 o (ne peut pas arriver ici) -> continue
        move.l  d0,d1
        subq.l  #4,d1               ; offset des 4 derniers octets de ce chunk
        move.l  0(a5,d1.l),d4       ; d4 = 4 derniers octets (= sentinelle au dernier chunk)
        bra.s   .j_rloop
.j_rdone:
        cmp.l   #D3J_SIZE,d5        ; total == 48000 ? (ancien handler aurait tronqué à 32768)
        bne     .j_close
        cmp.l   #$B16B00B5,d4       ; sentinelle lue jusqu'au bout ?
        bne     .j_close
        move.l  a4,a6               ; seek cross-block : Seek(500, BEGINNING)
        move.l  d7,d1
        move.l  #500,d2
        moveq   #OFFSET_BEGINNING,d3
        jsr     DOS_LVO_SEEK(a6)
        move.l  a4,a6               ; Read(4) @500
        move.l  d7,d1
        move.l  a5,d2
        moveq   #4,d3
        jsr     DOS_LVO_READ(a6)
        cmp.l   #4,d0
        bne.s   .j_close
        move.l  (a5),d0             ; long@500 attendu $A5EE3780 (pattern déterministe)
        cmp.l   #$A5EE3780,d0
        bne.s   .j_close
        bsr     ser_lock            ; tout OK -> émet sous ser_lock
        lea     msg_d3j_ok(pc),a0
        bsr     ser_puts            ; « OFS STREAM OK »
        bsr     ser_unlock
.j_close:
        move.l  a4,a6
        move.l  d7,d1
        jsr     DOS_LVO_CLOSE(a6)
.j_freebuf:
        move.l  ($4).w,a6
        move.l  a5,a1
        move.l  #D3J_BUFSZ,d0
        jsr     LVO_FREEMEM(a6)
.j_closelib:
        move.l  ($4).w,a6
        move.l  a4,a1
        jsr     LVO_CLOSELIBRARY(a6)
.j_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .j_block

; task_semw : bloque sur « kicksem.test » (pris au boot) ; réveillée, elle doit en être propriétaire avec une
; imbrication de 1. Elle le libère puis le retire et le rend.
task_semw:
        move.l  ($4).w,a6
        lea     semt_name(pc),a1
        jsr     LVO_FINDSEMAPHORE(a6)
        tst.l   d0
        beq.s   .sw_fail
        move.l  d0,a2
        move.l  a2,a0
        jsr     LVO_OBTAINSEMAPHORE(a6)
        move.l  EB_THISTASK(a6),d0
        cmp.l   SEMT_OWNER(a2),d0
        bne.s   .sw_fail
        cmp.w   #1,SEMT_NEST(a2)
        bne.s   .sw_fail
        move.l  a2,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
        cmp.w   #-1,SEMT_QC(a2)
        bne.s   .sw_fail
        move.l  a2,a1
        jsr     LVO_REMSEMAPHORE(a6)
        move.l  a2,a1
        moveq   #SEMT_SIZE,d0
        jsr     LVO_FREEMEM(a6)
        lea     msg_semw_ok(pc),a0
        bra.s   .sw_out
.sw_fail:
        lea     msg_semw_fail(pc),a0
.sw_out:
        jsr     LVO_FORBID(a6)
        bsr     ser_puts
        jmp     LVO_PERMIT(a6)
; task_semr : libère la prise du boot (le propriétaire n'est pas vérifié, comme en V34).
task_semr:
        move.l  ($4).w,a6
        lea     semt_name(pc),a1
        jsr     LVO_FINDSEMAPHORE(a6)
        tst.l   d0
        beq.s   .sr_r
        move.l  d0,a0
        jsr     LVO_RELEASESEMAPHORE(a6)
.sr_r:
        rts

; task_aud : CMD_WRITE réel sur le canal 0 (volume 0 : DMA et interruptions sans son audible). w1 puis w2 (30 cycles
; chacun) en file ; ADCMD_WAITCYCLE doit être rendu avant w1 (fin du 1er cycle), w1 avant w2 (enchaînement
; par la file), CMD_READ rend w1 pendant la lecture puis 0, et le DMA du canal est coupé à la fin.
; Pile : 3 IOAudio (ioa1 = commandes, w1, w2). d5 = constats d'ordre (b0 WAITCYCLE avant w1, b1 w1 avant w2).
task_aud:
        move.l  ($4).w,a6
        lea     -216(sp),sp
        move.l  sp,a3
        move.l  a3,a0
        moveq   #53,d0
.ta_clr:
        clr.l   (a0)+
        dbra    d0,.ta_clr
        moveq   #64,d0
        move.l  #MEMF_CHIP|MEMF_CLEAR,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,a4                ; a4 = échantillon (64 o de zéros en chip)
        tst.l   d0
        beq     .ta_fail0
        lea     audio_test_name(pc),a0
        moveq   #0,d0
        move.l  a3,a1
        moveq   #0,d1
        jsr     LVO_OPENDEVICE(a6)
        tst.b   d0
        bne     .ta_fail1
        move.l  IO_DEVICE(a3),a2
        move.l  a3,a1
        lea     aut_ch0(pc),a0
        moveq   #0,d0
        bsr     aut_alloc
        bne     .ta_fail
        lea     72(a3),a1            ; w1 et w2 : même device, clé et canal que ioa1
        moveq   #30,d2               ; ~210 ms : bien plus qu'un quantum de préemption
        bsr     .ta_mkw
        lea     144(a3),a1
        moveq   #30,d2               ; fenêtre « w1 rendu, w2 en cours » de ~210 ms, observable malgré la préemption
        bsr     .ta_mkw
        jsr     LVO_FORBID(a6)       ; lancement + CMD_READ + WAITCYCLE sans préemption (les IRQ restent actives)
        lea     72(a3),a1
        bsr     aut_io               ; CMD_WRITE w1 (démarre)
        lea     144(a3),a1
        bsr     aut_io               ; CMD_WRITE w2 (en file)
        move.l  a3,a1
        moveq   #2,d0                ; CMD_READ -> w1
        bsr     aut_cmd
        lea     72(a3),a0
        cmp.l   AUT_DATA(a3),a0
        bne     .ta_failp
        move.l  a3,a1                ; ADCMD_WAITCYCLE (asynchrone)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        clr.b   IO_FLAGS(a1)
        move.w  #14,IO_COMMAND(a1)
        bsr     aut_io
        jsr     LVO_PERMIT(a6)
        moveq   #0,d5
        move.l  #2000000,d4
.ta_poll:
        cmp.b   #NT_REPLYMSG,LN_TYPE(a3)
        bne.s   .ta_p1
        cmp.b   #NT_REPLYMSG,LN_TYPE+72(a3)
        beq.s   .ta_p1
        bset    #0,d5                ; WAITCYCLE rendu, w1 encore en cours
.ta_p1:
        cmp.b   #NT_REPLYMSG,LN_TYPE+72(a3)
        bne.s   .ta_p2
        cmp.b   #NT_REPLYMSG,LN_TYPE+144(a3)
        beq.s   .ta_p2
        bset    #1,d5                ; w1 rendu, w2 encore en cours
.ta_p2:
        cmp.b   #NT_REPLYMSG,LN_TYPE+144(a3)
        beq.s   .ta_end
        subq.l  #1,d4
        bne.s   .ta_poll
        bra     .ta_fail
.ta_end:
        cmp.b   #3,d5
        bne     .ta_fail
        tst.b   IO_ERROR+72(a3)
        bne     .ta_fail
        tst.b   IO_ERROR+144(a3)
        bne     .ta_fail
        btst    #0,$DFF003           ; DMACONR AUD0EN : canal coupé
        bne     .ta_fail
        move.l  a3,a1
        move.b  #1,IO_UNIT+3(a1)
        moveq   #2,d0                ; CMD_READ -> plus d'écriture
        bsr     aut_cmd
        tst.l   AUT_DATA(a3)
        bne     .ta_fail
        jsr     LVO_FORBID(a6)
        lea     msg_audplay_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
        bra.s   .ta_free
.ta_failp:
        jsr     LVO_PERMIT(a6)
.ta_fail:
        jsr     LVO_FORBID(a6)
        lea     msg_audplay_fail(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.ta_free:
        move.l  a3,a1
        move.b  #1,IO_UNIT+3(a1)
        moveq   #9,d0                ; ADCMD_FREE
        bsr     aut_cmd
        move.l  a3,a1
        jsr     LVO_CLOSEDEVICE(a6)
.ta_fail1:
        move.l  a4,a1
        moveq   #64,d0
        jsr     LVO_FREEMEM(a6)
.ta_fail0:
        lea     216(sp),sp
        rts
; .ta_mkw : a1 = IOAudio à préparer en CMD_WRITE de d2 cycles (période 400, volume 0, ADIOF_PERVOL).
.ta_mkw:
        move.l  a2,IO_DEVICE(a1)
        move.w  AUT_KEY(a3),AUT_KEY(a1)
        move.b  #1,IO_UNIT+3(a1)
        move.w  #3,IO_COMMAND(a1)
        move.b  #$10,IO_FLAGS(a1)
        move.b  #NT_MESSAGE,LN_TYPE(a1)
        move.l  a4,AUT_DATA(a1)
        moveq   #64,d0
        move.l  d0,AUT_LENGTH(a1)
        move.w  #400,AUT_PERIOD(a1)
        clr.w   AUT_VOLUME(a1)
        move.w  d2,AUT_CYCLES(a1)
        rts

; mk_demo_task : a2 = PC du corps, a3 = nom, d2.b = priorité -> a4 = TCB créé.
; AllocMem préserve a2/a3/d2 ; AddTask lit a2 (initPC) / a3 (finalPC=task_exit).
mk_demo_task:
        move.l  #TC_SIZE,d0          ; TCB + pile dans tc_MemEntry (pas de DMA : slow RAM d'abord)
        move.l  #DEMO_STK,d1
        jsr     task_alloc
        move.l  d0,a4                ; a4 = TCB
        move.l  a3,LN_NAME(a4)
        move.b  d2,LN_PRI(a4)
        move.l  #SYS_SIGALLOC,TC_SIGALLOC(a4)  ; bits 0-15 réservés -> AllocSignal rend 16+ (task_timer)
        move.l  a4,a1
        lea     task_exit(pc),a3     ; finalPC (a3 = nom écrasé, déjà posé dans LN_NAME)
        jsr     LVO_ADDTASK(a6)      ; AddTask(a1=task, a2=initPC, a3=finalPC)
        rts

; Corps des tâches de démo M3f — PREUVE que préemption périodique et yield-sur-Permit
; COEXISTENT (SCHED_ON=1), sans corruption de contexte. Déterministe, indépendant du
; cadencement série (les compteurs avancent par l'ordonnancement, pas par l'émission).
;   task_H (pri 10) : boucle Wait(DEMO_SIG) ; WP_CONS++. Dispatchée par le yield de task_L.
;   task_L (pri 0)  : boucle Forbid/Signal(task_H)/Permit(<-yield) ; WP_PROD++. Ne bloque jamais.
;   task_S (pri 0)  : spinner PUR (WP_SPIN++) ; ne bloque/signale/yield JAMAIS -> ne tourne
;                     que si la PRÉEMPTION partage le CPU (sinon il monopoliserait -> RED).
; Chaque tâche garde une sentinelle en d7 (préservé par tout switch) et la revérifie :
; corruption -> « M3F FAILED ». « M3F LIVE » émis UNE fois quand WP_CONS >= CONS_THRESH
; (yield répété) ET WP_SPIN >= SPIN_THRESH (task_S a tourné via préemption).
; RED (SCHED_ON=0 = préemption OFF) : task_S (ou task_L) monopolise le CPU -> task_L ne
; peut plus signaler task_H -> WP_CONS gèle -> « M3F LIVE » jamais émis (absent).
task_h:                              ; haute priorité (les tâches démarrent a6=0)
        move.l  ($4).w,a6            ; SysBase (cf. frame AddTask qui zéro-remplit les GPR)
        move.l  #SENT_H,d7           ; sentinelle de contexte
.h_loop:
        moveq   #1,d0
        moveq   #DEMO_SIG,d1
        lsl.l   d1,d0               ; masque = 1 << DEMO_SIG (décalage registre : 68000 immédiat <= 8)
        jsr     LVO_WAIT(a6)         ; BLOQUE jusqu'au signal de task_L (dispatch via yield)
        cmp.l   #SENT_H,d7
        bne.w   demo_fail            ; contexte corrompu par un switch
        addq.l  #1,WP_CONS
        btst    #0,WP_STAT
        bne.s   .h_loop              ; marqueur déjà émis
        move.l  WP_CONS,d0
        cmp.l   #CONS_THRESH,d0
        bcs.s   .h_loop              ; WP_CONS < seuil -> continuer
        move.l  WP_SPIN,d0
        cmp.l   #SPIN_THRESH,d0
        bcs.s   .h_loop              ; WP_SPIN < seuil -> préemption pas encore prouvée
        bset    #0,WP_STAT           ; marque émis (une seule fois)
        jsr     LVO_FORBID(a6)       ; émission non fractionnée
        lea     msg_m3flive(pc),a0
        bsr     ser_puts
        tst.b   WP_UMODE             ; M7c : une tâche s'est observée en USER mode (SR bit S == 0) ?
        beq.s   .h_noum
        lea     msg_m7c_ok(pc),a0
        bsr     ser_puts             ; « M7C USERMODE OK » (user-mode + relocation + préemption prouvés)
.h_noum:
        jsr     LVO_PERMIT(a6)
        bra.s   .h_loop
task_l:                              ; basse priorité, ne bloque jamais
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_L,d7
.l_loop:
        jsr     LVO_FORBID(a6)       ; Signal sous Forbid -> yield reporté au Permit
        move.l  WP_HTASK,a1
        moveq   #1,d0
        moveq   #DEMO_SIG,d1
        lsl.l   d1,d0
        jsr     LVO_SIGNAL(a6)       ; réveille task_H + pose AttnResched (pri 10 > 0)
        jsr     LVO_PERMIT(a6)       ; <- YIELD : dispatche task_H immédiatement
        cmp.l   #SENT_L,d7
        bne.w   demo_fail
        addq.l  #1,WP_PROD
        bra.s   .l_loop
task_s:                              ; basse priorité, spinner PUR (jamais de blocage/yield)
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_S,d7
        move.w  sr,d0                ; M7c : preuve DIRECTE du user-mode (MOVE from SR non privilégié
        and.w   #$2000,d0            ; sur 68000) -> bit S attendu à 0
        bne.w   demo_fail            ; S=1 => tâche en superviseur => régression user-mode (sentinelle KO)
        move.b  #1,WP_UMODE          ; user mode confirmé (consommé par task_H -> « M7C USERMODE OK »)
.s_loop:
        cmp.l   #SENT_S,d7
        bne.w   demo_fail            ; contexte corrompu par une PRÉEMPTION
        addq.l  #1,WP_SPIN
        move.l  #$00001000,d0
.s_spin:
        subq.l  #1,d0
        bne.s   .s_spin
        bra.s   .s_loop

; task_fb (pri 7, preuve atomicité Forbid) : BLOQUE sur FB_SIG ; quand elle tourne, pose FORBID_TEST_FLAG=1.
; Si elle tourne PENDANT le Forbid de task_fa (pri 3), c'est que la préemption n'a PAS respecté Forbid (bug).
task_fb:
        move.l  ($4).w,a6            ; SysBase (GPR zéro-remplis par la frame AddTask)
.fb_loop:
        moveq   #1,d0
        moveq   #FB_SIG,d1
        lsl.l   d1,d0                ; masque = 1 << FB_SIG (décalage REGISTRE : count > 8 OK sur 68000)
        jsr     LVO_WAIT(a6)         ; bloque jusqu'au signal de task_fa
        move.l  #1,FORBID_TEST_FLAG  ; « j'ai tourné » (observé par task_fa)
        bra.s   .fb_loop

; task_fa (pri 3, preuve atomicité Forbid) : prend Forbid, réveille task_fb (pri 7 > 3 -> arme AttnResched),
; attend 2 VBlanks SOUS Forbid (garantit >= 1 sortie d'IRQ pendant le Forbid, où intr_isr_defer pourrait switcher).
; Si FORBID_TEST_FLAG est resté 0 -> task_fb n'a PAS préempté sous Forbid -> « FORBID ATOMIC OK ». Tourne UNE fois
; puis bloque (pas de monopolisation). RED SCHED_NO_FORBID_GATE : fb préempte pendant le Forbid -> flag=1 -> absent.
task_fa:
        move.l  ($4).w,a6
        jsr     LVO_FORBID(a6)       ; section d'émission atomique à prouver
        clr.l   FORBID_TEST_FLAG
        move.l  FB_TASK,a1           ; réveille task_fb (pri 7 > courante 3 -> exec_Signal pose AttnResched)
        moveq   #1,d0
        moveq   #FB_SIG,d1
        lsl.l   d1,d0
        jsr     LVO_SIGNAL(a6)
        move.l  VBL_COUNT,d2         ; attend que VBL_COUNT avance de 2 (>= 1 IRQ-exit VBlank pendant le Forbid)
        addq.l  #2,d2
.fa_wait:
        cmp.l   VBL_COUNT,d2
        bhi.s   .fa_wait             ; VBL_COUNT incrémenté par l'IRQ VBlank (fire même sous Forbid)
        tst.l   FORBID_TEST_FLAG     ; task_fb a-t-elle tourné pendant le Forbid ?
        bne.s   .fa_perm             ; oui -> Forbid violé -> ne PAS émettre
        lea     msg_forbid_ok(pc),a0
        bsr     ser_puts             ; « FORBID ATOMIC OK » (sous le Forbid tenu -> émission atomique)
.fa_perm:
        jsr     LVO_PERMIT(a6)       ; yield -> task_fb tourne enfin (pose le flag, trop tard pour fausser la preuve)
.fa_block:
        moveq   #0,d0
        jsr     LVO_WAIT(a6)
        bra.s   .fa_block

; task_q2 (M7h) : 2e spinner d'ISOLATION (pri 0 ; config M7H_QUANTUM_DEMO seulement). Rotation avec task_s
; pilotée UNIQUEMENT par le quantum VBlank (aucun préempteur prioritaire). Émet « M7H QUANTUM OK » quand
; le débit d'expirations prouve un quantum > 1 tick : QUANTUM_EXPIRE_N*2 < VBL_COUNT (GREEN N=4 : ~VBL/4 ;
; RED N=1 : ~VBL -> échoue). Vérifie aussi que task_s a tourné (WP_SPIN>0) = rotation réelle.
task_q2:
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_Q2,d7
.q2_loop:
        cmp.l   #SENT_Q2,d7
        bne.w   demo_fail            ; contexte corrompu par une PRÉEMPTION
        addq.l  #1,Q2_RUNS
        btst    #0,M7H_STAT
        bne.s   .q2_spin             ; déjà émis -> juste spinner
        move.l  VBL_COUNT,d0
        cmp.l   #M7H_MINTICKS,d0     ; assez de ticks pour un ratio stable ?
        bcs.s   .q2_spin
        tst.l   WP_SPIN              ; task_s (spinner-1) a-t-il tourné ? (rotation réelle, pas monopolisé)
        beq.s   .q2_spin
        move.l  QUANTUM_EXPIRE_N,d1
        add.l   d1,d1                ; EXPIRE_N * 2
        cmp.l   VBL_COUNT,d1         ; EXPIRE_N*2 >= VBL_COUNT ? (quantum ~1 tick -> RED)
        bcc.s   .q2_spin             ; oui -> quantum trop court -> pas prouvé
        bset    #0,M7H_STAT          ; EXPIRE_N*2 < VBL_COUNT -> quantum > ~2 ticks prouvé
        jsr     LVO_FORBID(a6)
        lea     msg_m7h_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.q2_spin:
        move.l  #$00001000,d0
.q2_delay:
        subq.l  #1,d0
        bne.s   .q2_delay
        bra.s   .q2_loop

; task_rm (M7j, pri 0 ; config M7J_DEMO seulement) : tâche à DURÉE DE VIE FINIE. Tourne RM_THRESH fois
; (RM_RUNS++) puis fait RTS -> finalPC task_exit -> RemTask(self) -> libère sa pile + TCB et bascule.
; Prouve le cycle de vie : AvailMem remonte après son auto-retrait (vérifié par task_timer).
task_rm:
        move.l  ($4).w,a6
        move.l  #SENT_RM,d7
.rm_loop:
        cmp.l   #SENT_RM,d7
        bne.w   demo_fail            ; contexte corrompu par une préemption
        addq.l  #1,RM_RUNS
        move.l  RM_RUNS,d0
        cmp.l   #RM_THRESH,d0
        bcc.s   .rm_done             ; RM_RUNS >= RM_THRESH -> se terminer (RTS)
        move.l  #$00008000,d0        ; délai (laisse les compteurs des autres avancer)
.rm_delay:
        subq.l  #1,d0
        bne.s   .rm_delay
        bra.s   .rm_loop
.rm_done:
        rts                          ; -> task_exit -> RemTask(self) (ne revient pas)

; task_timer (pri 10, M7a) : bloque sur l'unité MICROHZ (CIA-B/INT6). À chaque tour, arme une
; requête courte (1 tick CIA-B), Wait sur le reply port, vérifie la réponse. Prouve qu'une TÂCHE
; se réveille sur un timer d'interruption (Wait->wake par l'IRQ MICROHZ) ET surveille VBL_CLASH :
; si INT6 a préempté la chirurgie de listes de vbl_handler (gate violé en RED), VBL_CLASH>0 ->
; « M7A FAILED ». GREEN = TCONS_THRESH réveils accumulés avec VBL_CLASH toujours == 0.
; Setup en contexte tâche (AllocSignal opère bien sur task_timer). a4=base timer, a3=reply port,
; a2=timerequest, d6=bit de signal, d7=sentinelle — tous préservés par les appels exec (vérifié).
task_timer:
        move.l  ($4).w,a6            ; SysBase
        move.l  #SENT_T,d7           ; sentinelle de contexte
        lea     EB_DEVICELIST(a6),a0 ; base timer.device
        lea     timer_test_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a4                ; a4 = base timer.device
        moveq   #-1,d0               ; AllocSignal -> bit du reply port (task_timer a SYS_SIGALLOC)
        jsr     LVO_ALLOCSIGNAL(a6)
        move.l  d0,d6                ; d6 = n° de bit
        move.l  #MP_SIZE,d0          ; reply port
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a3                ; a3 = reply port
        lea     MP_MSGLIST(a3),a1
        jsr     newlist
        move.b  #PA_SIGNAL,MP_FLAGS(a3)
        move.b  d6,MP_SIGBIT(a3)
        move.l  EB_THISTASK(a6),MP_SIGTASK(a3)   ; se signale elle-même
        move.l  #TR_SIZE,d0          ; timerequest
        move.l  #(MEMF_CHIP|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     m7a_fail
        move.l  d0,a2                ; a2 = timerequest
        move.l  a3,MN_REPLYPORT(a2)
        move.l  a4,IO_DEVICE(a2)
        move.l  #UNIT_MICROHZ,IO_UNIT(a2)   ; unité MICROHZ (CIA-B/INT6)
        ; M7l — CALIBRATION µs RÉELLE (une fois, avant la boucle) : une requête MICROHZ LONGUE connue
        ; (M7L_CAL_US = 0,5 s), mesurée contre l'horloge VBLANK (50 Hz, INDÉPENDANTE : raster display vs
        ; E-clock CPU). 0,5 s de µs réelles doit s'écouler en ~25 ticks VBLANK. Hors bande -> M7L non émis
        ; (RED OLD_CONV : la requête expire en ~0-1 tick) ; on tombe quand même dans la boucle (M7A reste prouvable).
        move.l  VBL_COUNT,M7L_VBL_BEFORE    ; T0 sur l'horloge VBLANK
        clr.l   TV_SECS(a2)
        move.l  #M7L_CAL_US,TV_MICRO(a2)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a2)
        move.l  a6,-(sp)             ; BeginIO(a4 = base, a2 = requête)
        move.l  a4,a6
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
        moveq   #1,d0                ; Wait(1<<bit) : BLOQUE jusqu'à expiration de la requête de calibration
        move.l  d6,d1
        lsl.l   d1,d0
        jsr     LVO_WAIT(a6)
        move.l  a3,a0                ; GetMsg(reply port) -> doit être NOTRE requête
        jsr     LVO_GETMSG(a6)
        cmp.l   a2,d0
        bne     m7a_fail
        move.l  VBL_COUNT,d0         ; T1 ; élapsed = T1 - T0 (ticks VBLANK pendant 0,5 s MICROHZ)
        sub.l   M7L_VBL_BEFORE,d0
        move.l  d0,M7L_ELAPSED
        cmp.l   #M7L_LO,d0           ; dans la bande [M7L_LO, M7L_HI] ? (0,5 s ≈ 25 ticks)
        bcs.s   .tt_cal_done         ; trop rapide (RED OLD_CONV) -> M7L non émis, on continue
        cmp.l   #M7L_HI+1,d0
        bcc.s   .tt_cal_done         ; trop lent (constante grossièrement fausse) -> M7L non émis
        bset    #0,M7L_STAT          ; émet « M7L MICROHZ CALIB OK » une seule fois
        jsr     LVO_FORBID(a6)
        lea     msg_m7l_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_cal_done:
        move.l  VBL_COUNT,d5         ; T0 (ticks VBlank au départ ; d5 préservé par les appels exec)
.tt_loop:
        cmp.l   #SENT_T,d7           ; contexte intact après chaque switch ?
        bne     m7a_fail
        tst.l   VBL_CLASH            ; le gate IPL7 a-t-il été violé ? (RED -> != 0)
        bne     m7a_fail
        clr.l   TV_SECS(a2)          ; (ré)arme une requête MICROHZ ~7 ms (TT_MICRO_REQ µs RÉELLES depuis M7l)
        move.l  #TT_MICRO_REQ,TV_MICRO(a2) ; 7000 us / 359 = 19 int CIA-B -> ~140 réveils/s (coexiste avec M3f ;
                                     ; 1 int seule préempterait ~2800/s via le dispatch différé et starverait task_s/L)
        move.w  #TR_ADDREQUEST,IO_COMMAND(a2)
        move.l  a6,-(sp)             ; BeginIO(a4 = base, a2 = requête)
        move.l  a4,a6
        move.l  a2,a1
        jsr     TD_BEGINIO(a6)
        move.l  (sp)+,a6
        moveq   #1,d0                ; Wait(1<<bit) : BLOQUE jusqu'au réveil MICROHZ
        move.l  d6,d1
        lsl.l   d1,d0
        jsr     LVO_WAIT(a6)
        move.l  a3,a0                ; GetMsg(reply port)
        jsr     LVO_GETMSG(a6)
        cmp.l   a2,d0                ; doit être NOTRE requête
        bne     m7a_fail
        addq.l  #1,WP_TCONS          ; un réveil MICROHZ réussi de plus
        btst    #0,M7E_STAT          ; M7e : marqueur IPL-par-niveau déjà émis ? (testé à chaque réveil,
        bne.s   .tt_m7e_done         ; indépendamment du flag M7a ; -> tombe sur le check M7F (ne PAS sauter)
        move.l  VBL_PREEMPT_COUNT,d0 ; INT6(6) a-t-il déjà préempté le CORPS de vbl(3) ? (fidélité IPL natif)
        beq.s   .tt_m7e_done         ; pas encore observé -> pas prouvé (mais checker quand même M7F)
        tst.l   VBL_CLASH            ; ET la chirurgie du switch est-elle restée atomique ? (doit == 0)
        bne.s   .tt_m7e_done         ; clash -> le check en tête de boucle prendra m7a_fail au prochain tour
        bset    #0,M7E_STAT          ; émet « M7E IPL OK » une seule fois
        jsr     LVO_FORBID(a6)
        lea     msg_m7e_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_m7e_done:
        btst    #0,M7F_STAT          ; M7f : marqueur chaîne VERTB déjà émis ?
        bne.s   .tt_m7f_done         ; -> tombe sur le check M7G (ne PAS sauter)
        move.l  VERTB_CHAIN_N,d0     ; le walker a-t-il parcouru la chaîne VERTB jusqu'à la QUEUE (vbl_tail) ?
        cmp.l   #VERTB_CHAIN_THRESH,d0  ; (prouve sched_server pri 20 + timer_vblank pri 0 AVANT vbl_tail pri -10)
        bcs.s   .tt_m7f_done         ; pas encore assez de parcours complets de chaîne (mais checker M7G)
        bset    #0,M7F_STAT          ; émet « M7F VERTB OK » une seule fois
        jsr     LVO_FORBID(a6)
        lea     msg_m7f_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_m7f_done:
        btst    #0,M7G_STAT          ; M7g : marqueur multi-source déjà émis ?
        bne.s   .tt_m7g_done
        move.l  COPER_FIRED,d0       ; la 2e source de niveau 3 (COPER) a-t-elle été servie via le décodage ?
        cmp.l   #COPER_THRESH,d0
        bcs.s   .tt_m7g_done         ; pas encore assez d'appels coper_test (mais checker M7J)
        bset    #0,M7G_STAT          ; émet « M7G MULTISRC OK » une seule fois
        jsr     LVO_FORBID(a6)
        lea     msg_m7g_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_m7g_done:
        btst    #0,GP_LIVE_STAT      ; gameport : serveur souris VBlank live déjà prouvé ?
        bne.s   .tt_gp_done          ; -> tombe sur le check M7J (ne PAS sauter)
        move.l  GP_POLLS,d0          ; gp_vblank_server tourne-t-il sur les VBlanks RÉELS du système tournant ?
        cmp.l   #GP_POLLS_THRESH,d0
        bcs.s   .tt_gp_done          ; pas encore assez de polls (checker M7J quand même)
        bset    #0,GP_LIVE_STAT      ; émet « GP VBLANK LIVE OK » une seule fois
        jsr     LVO_FORBID(a6)
        lea     msg_gp_live_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_gp_done:
        btst    #0,M7J_STAT          ; M7j : marqueur cycle-de-vie déjà émis ?
        bne.s   .tt_m7a
        move.l  RM_RUNS,d0           ; task_rm a-t-elle fini ses itérations (puis s'est auto-retirée) ?
        cmp.l   #RM_THRESH,d0
        bcs.s   .tt_m7a              ; pas encore -> attendre (en RED NOFREE on reste ici : AvailMem gelé)
        moveq   #0,d1                ; AvailMem(now)
        jsr     LVO_AVAILMEM(a6)     ; (préserve d2-d7/a2-a6 ; clobbe d0/d1/a0/a1)
        move.l  M7J_AVAIL_BEFORE,d1
        sub.l   #M7J_RECOVER,d1      ; seuil = baseline - M7J_RECOVER
        cmp.l   d1,d0                ; AvailMem(now) >= baseline - RECOVER ? (pile+TCB bien libérés)
        bcs.s   .tt_m7a              ; < seuil -> pas remonté (fuite = RED) -> pas prouvé
        bset    #0,M7J_STAT          ; émet « M7J REMTASK OK » une seule fois
        jsr     LVO_FORBID(a6)
        lea     msg_m7j_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
.tt_m7a:
        btst    #1,WP_STAT
        bne     .tt_loop             ; marqueur déjà émis (branche word : corps de boucle long)
        move.l  WP_TCONS,d0
        cmp.l   #TCONS_THRESH,d0
        bcs     .tt_loop             ; pas encore assez de réveils
        move.l  VBL_COUNT,d0         ; ET assez de temps écoulé ? (fenêtre où un clash RED serait tombé)
        sub.l   d5,d0
        cmp.l   #M7A_MINTICKS,d0
        bcs     .tt_loop
        bset    #1,WP_STAT           ; émet « M7A TIMER OK » une seule fois
        jsr     LVO_FORBID(a6)
        lea     msg_m7a_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
        bra     .tt_loop

; task_port (pri 0, M7d) : CONSOMMATEUR TÂCHE du port de stress partagé. Boucle serrée GetMsg+PutMsg ;
; le PRODUCTEUR est timer_micro_service (INTERRUPTION). Ports interrupt-safe (Disable) -> la course
; GetMsg(tâche)/PutMsg(IRQ) sur le même MP_MSGLIST est sûre. En RED (ports remis en Forbid) elle corrompt
; la liste. Vérifie MAGIC (mauvais pointeur) + IN_HAND==0 (doublon) à chaque message. a4 = port (préservé
; par GetMsg/PutMsg = scratch d0/d1/a0/a1). Émet « M7D PORTS OK » quand les 2 compteurs passent sans fail.
task_port:
        move.l  ($4).w,a6
        move.l  #SENT_P,d7
        moveq   #0,d6                ; d6 = compteur de GetMsg vides CONSÉCUTIFs (détecteur de nœuds perdus)
.pp_wait:
        move.l  WP_SPORT,a4          ; attendre que le port existe (créé pré-handoff -> déjà prêt)
        move.l  a4,d0
        beq.s   .pp_wait
.pp_loop:
        cmp.l   #SENT_P,d7
        bne.w   demo_fail            ; contexte corrompu par un switch
        move.l  a4,a0                ; GetMsg(SP)
        jsr     LVO_GETMSG(a6)
        tst.l   d0
        beq.s   .pp_empty            ; vide -> compter (K messages circulent, le port n'est quasi
        move.l  d0,a1                ; jamais vide ; vide PROLONGÉ = nœuds perdus par corruption)
        cmp.l   #STRESS_MAGIC,MSG_MAGIC_OFF(a1)
        bne     m7d_fail             ; mauvais pointeur -> corruption de liste
        tst.l   MSG_INHAND_OFF(a1)
        bne     m7d_fail             ; déjà « en main » -> doublon = corruption
        move.l  #1,MSG_INHAND_OFF(a1)
        clr.l   MSG_INHAND_OFF(a1)
        move.l  a4,a0                ; PutMsg(SP, msg)
        jsr     LVO_PUTMSG(a6)
        addq.l  #1,WP_PORTT
        moveq   #0,d6                ; message obtenu -> reset du compteur de vides
        bra.s   .pp_emit
.pp_empty:
        addq.l  #1,d6
        cmp.l   #PEMPTY_LIMIT,d6
        bcc     m7d_fail             ; port vide trop longtemps -> nœuds perdus = corruption
.pp_emit:
        btst    #0,M7D_STAT
        bne     .pp_loop             ; marqueur déjà émis
        tst.l   WP_PORTFAIL          ; corruption vue côté interruption ?
        bne     m7d_fail
        move.l  WP_PORTT,d0
        cmp.l   #PORTT_THRESH,d0
        bcs     .pp_loop             ; pas assez d'itérations côté tâche
        move.l  WP_PORTI,d0
        cmp.l   #PORTI_THRESH,d0
        bcs     .pp_loop             ; pas assez côté interruption (producteur)
        bset    #0,M7D_STAT
        jsr     LVO_FORBID(a6)
        lea     msg_m7d_ok(pc),a0
        bsr     ser_puts
        jsr     LVO_PERMIT(a6)
        bra     .pp_loop
m7d_fail:                            ; corruption de liste de port (RED) -> preuve
        jsr     LVO_FORBID(a6)
        lea     msg_m7d_fail(pc),a0
        bsr     ser_puts
.m7df_hang:
        bra.s   .m7df_hang

demo_fail:                           ; sentinelle KO -> preuve de corruption
        jsr     LVO_FORBID(a6)
        lea     msg_m3ffail(pc),a0
        bsr     ser_puts
.df_hang:
        bra.s   .df_hang
task_exit:                           ; M7j : finalPC — une tâche a fait RTS (fin de corps) -> se retire
        move.l  ($4).w,a6            ; elle-même via RemTask(self). RemTask ne revient pas (bascule).
        suba.l  a1,a1                ; a1 = 0 -> RemTask interprète NULL comme la tâche courante
        jsr     LVO_REMTASK(a6)
        bra.s   task_exit            ; filet (ne doit jamais être atteint)

; ============================ résidents démo (M4) ==================
; 3 ROMTags scannés par build_reslist puis initialisés par InitCode en ordre de PRIORITÉ
; DÉCROISSANTE (hi=60, mid=10, lo=-20). Chacun partage res_demo_init, qui vérifie que sa
; RT_PRI n'est PAS supérieure à la précédente (ordre décroissant maintenu) puis émet son
; nom. Preuve : noms émis hi->mid->lo dans le log + RES_COUNT==3.
; IMPORTANT : rangés en mémoire dans un ordre (mid, lo, hi) DIFFÉRENT de l'ordre de
; priorité, pour que le TRI de build_reslist soit load-bearing (sinon l'ordre de scan
; suffirait). ROMTags non-AUTOINIT (direct-init). Alignement PAIR obligatoire (le scan
; lit des mots à adresses paires ; RT_ENDSKIP doit rester pair).
        EVEN
res_mid:
        dc.w    RTC_MATCHWORD
        dc.l    res_mid              ; RT_MATCHTAG = self (valide le match)
        dc.l    res_mid_end          ; RT_ENDSKIP
        dc.b    RTF_COLDSTART,1,NT_RESOURCE,10   ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    res_mid_name         ; RT_NAME
        dc.l    res_mid_name         ; RT_IDSTRING
        dc.l    res_mid_init         ; RT_INIT (routine propre au module)
res_mid_name:
        dc.b    "demo.res.mid",0
        EVEN
res_mid_end:
res_lo:
        dc.w    RTC_MATCHWORD
        dc.l    res_lo
        dc.l    res_lo_end
        dc.b    RTF_COLDSTART,1,NT_RESOURCE,-20
        dc.l    res_lo_name
        dc.l    res_lo_name
        dc.l    res_lo_init
res_lo_name:
        dc.b    "demo.res.lo",0
        EVEN
res_lo_end:
res_hi:
        dc.w    RTC_MATCHWORD
        dc.l    res_hi
        dc.l    res_hi_end
        dc.b    RTF_COLDSTART,1,NT_RESOURCE,60
        dc.l    res_hi_name
        dc.l    res_hi_name
        dc.l    res_hi_init
res_hi_name:
        dc.b    "demo.res.hi",0
        EVEN
res_hi_end:

; Routines d'init des résidents démo. Appelées par InitResident avec la convention ABI
; direct-init (D0=0, A0=segList, A6=SysBase) : le pointeur resident n'est PAS fourni, donc
; chaque routine connaît STATIQUEMENT sa priorité et son nom (comme un vrai module). Elles
; passent (d0=pri signée, a1=nom) à res_demo_common.
res_hi_init:
        moveq   #60,d0
        lea     res_hi_name(pc),a1
        bra.s   res_demo_common
res_mid_init:
        moveq   #10,d0
        lea     res_mid_name(pc),a1
        bra.s   res_demo_common
res_lo_init:
        moveq   #-20,d0
        lea     res_lo_name(pc),a1
        ; tombe dans res_demo_common
; res_demo_common : d0 = RT_PRI (signée, longword via moveq), a1 = nom. Vérifie l'ordre
; décroissant via RES_LASTPRI, compte dans RES_COUNT, émet le nom + CRLF. Retourne d0=0.
res_demo_common:
        cmp.l   RES_LASTPRI,d0
        bgt     res_fail             ; pri > précédente -> ordre CROISSANT = scan/tri FAUX
        move.l  d0,RES_LASTPRI
        addq.l  #1,RES_COUNT
        move.l  a1,a0                ; nom
        bsr     ser_puts             ; émet le nom (ordre visible hi->mid->lo)
        lea     msg_crlf(pc),a0
        bsr     ser_puts
        moveq   #0,d0
        rts

res_fail:                            ; échec M4 (scan/ordre/dispatch) -> fige
        lea     msg_res_fail(pc),a0
        bsr     ser_puts
.resf_hang:
        bra.s   .resf_hang
auto_fail:                           ; échec M5a (AUTOINIT/MakeLibrary) -> fige
        lea     msg_auto_fail(pc),a0
        bsr     ser_puts
.autof_hang:
        bra.s   .autof_hang
cia_fail:                            ; échec M5b (cia.resource) -> fige
        lea     msg_cia_fail(pc),a0
        bsr     ser_puts
.ciaf_hang:
        bra.s   .ciaf_hang
timer_fail:                          ; échec M5c (timer.device) -> fige
        lea     msg_timer_fail(pc),a0
        bsr     ser_puts
.tmrf_hang:
        bra.s   .tmrf_hang
m6a_fail:                            ; échec M6a (unité VBLANK timer) -> fige
        lea     msg_m6a_fail(pc),a0
        bsr     ser_puts
.m6af_hang:
        bra.s   .m6af_hang
m7b_fail:                            ; échec M7b (dispatcher par numéro / chaîne PORTS) -> fige
        lea     msg_m7b_fail(pc),a0
        bsr     ser_puts
.m7bf_hang:
        bra.s   .m7bf_hang
m7a_fail:                            ; échec M7a (gate de ré-entrance / unité MICROHZ) -> fige
        jsr     LVO_FORBID(a6)       ; émission non fractionnée (atteint depuis le contexte tâche)
        lea     msg_m7a_fail(pc),a0
        bsr     ser_puts
.m7af_hang:
        bra.s   .m7af_hang
; struct Interrupt de test (M6b) : IS_CODE -> cia_test_vec (incrémente CIA_FIRED).
        EVEN
cia_test_int:
        dcb.b   14,0                 ; LN (non chaîné)
        dc.l    0                    ; IS_DATA
        dc.l    cia_test_vec         ; IS_CODE
cia_test_vec:                        ; serveur ICR (a1=data, a5=code, a6=SysBase)
        addq.l  #1,CIA_FIRED
        rts
cia_dummy_int:                       ; fausse struct Interrupt (AddICRVector ne stocke que le ptr)
        dc.l    0,0,0,0,0

; int2_srv2 (M7b) : 2e serveur de la chaîne PORTS (pri 0, après ciaa_server pri 10). Incrémente
; INT2_SRV2 et capture l'ordre (CIA_FIRED > 0 au 1er appel => ciaa_server a tourné avant = pri OK).
; a1=IS_DATA (inutilisé), a6=SysBase. Préserve d2-d7/a2-a4 (ne touche que d0 + mémoire). Z MIS (continue).
int2_srv2:
        addq.l  #1,INT2_SRV2
        tst.l   INT2_ORDER_SNAP      ; déjà capturé ?
        bne.s   .s2_z
        move.l  CIA_FIRED,d0         ; ciaa_server (pri 10) a-t-il déjà tourné dans CET INT2 ?
        beq.s   .s2_z                ; pas encore -> on capturera à un INT2 ultérieur
        move.l  d0,INT2_ORDER_SNAP   ; > 0 -> ordre de priorité confirmé (ciaa avant srv2)
.s2_z:
        moveq   #0,d0                ; Z set -> continue la chaîne
        rts

; input_test_h1 / input_test_h2 (#2) : handlers input.device de test. Convention : a0 = liste d'InputEvents,
; a1 = is_Data ; rend d0 = liste (pass-through). h1 (pri 10) tourne avant h2 (pri 0) -> INPUT_SEQ ordonne.
; h1 relève aussi le keycode du 1er event (preuve de propagation). Clobbe d0 (+ mémoire) ; préserve a0-a6/d1-d7.
input_test_h1:
        addq.w  #1,INPUT_SEQ
        move.w  INPUT_SEQ,INPUT_H1_ORD   ; ordre d'appel (doit = 1)
        move.w  IE_CODE(a0),INPUT_CODE   ; keycode relayé par la chaîne
        move.l  a0,d0                    ; rend la liste inchangée
        rts
input_test_h2:
        addq.w  #1,INPUT_SEQ
        move.w  INPUT_SEQ,INPUT_H2_ORD   ; ordre d'appel (doit = 2)
        move.l  a0,d0
        rts

; gp_cap_handler(a0 = liste d'InputEvents, a1 = is_Data) -> d0 = liste : handler de capture du bloc GAMEPORT.
; Compte les RAWMOUSE vus (GP_CAP_N) et mémorise ie_Code/ie_X/ie_Y du dernier (events injectés unitaires -> tête
; seule). Scratch d0/d1/a1 uniquement (préserve d2-d7/a2-a4, convention handler).
gp_cap_handler:
        move.l  a0,d1
        beq.s   .gc_ret
        move.l  a0,a1
        cmp.b   #IECLASS_RAWMOUSE,IE_CLASS(a1)
        bne.s   .gc_ret
        addq.w  #1,GP_CAP_N
        move.w  IE_CODE(a1),GP_CAP_CODE
        move.w  IE_X(a1),GP_CAP_DX
        move.w  IE_Y(a1),GP_CAP_DY
.gc_ret:
        move.l  a0,d0
        rts

; disk_watch : process de l'écran insert-disk (pri -1). Toutes les DW_TICKS : td_disk_present ; une disquette
; insérée (lecteur vu vide auparavant) -> redémarrage à froid (Supervisor : RESET puis saut à l'entrée de la ROM) : le boot la trouve alors comme
; à la mise sous tension. Ne revient pas.
DW_TICKS        EQU 25               ; 0,5 s entre deux sondages
DW_STK          EQU 1024
disk_watch:
        move.l  ($4).w,a6
        moveq   #0,d7                ; d7 != 0 : lecteur vu vide (une disquette non amorçable déjà présente ne
.dw_lp:                              ; redémarre pas la machine : il faut la retirer puis en insérer une)
        move.l  DOS_DOSBASE,a6
        moveq   #DW_TICKS,d1
        jsr     DOS_LVO_DELAY(a6)
        move.l  ($4).w,a6
        jsr     td_disk_present
        tst.l   d0
        bne.s   .dw_in
        moveq   #-1,d7
        bra.s   .dw_lp
.dw_in:
        tst.l   d7
        beq.s   .dw_lp
        lea     dw_reboot(pc),a5
        jsr     LVO_SUPERVISOR(a6)   ; ne revient pas
        bra.s   .dw_lp
; dw_reboot (superviseur) : RESET réinitialise les puces (l'overlay remet la ROM en $0) ; le JMP doit être dans le
; même mot long que le RESET (déjà préchargé). Entrée = PC initial de la ROM (long en $FC0004).
        cnop    0,4
dw_reboot:
        move.w  #$2700,sr
        move.l  ($FC0004).l,a0
        bra.s   dw_rst
        cnop    0,4
dw_rst:
        reset
        jmp     (a0)
dw_name:
        dc.b    "DF0 watch",0
        even

; ptr_wire : installe le handler de pointeur PERSISTANT (PTR_INT, pri 50) sur input.device : deltas RAWMOUSE ->
; position absolue PTR_X/PTR_Y + sprite du pointeur. Appelé sur les deux branches de boot (insert-disk et disquette).
; a6 = SysBase. Préserve d2-d7/a2-a6.
ptr_wire:
        movem.l a2/a4,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq.s   .pw_ret
        move.l  d0,a4
        clr.l   PTR_INT+LN_SUCC          ; struct Interrupt pointeur (pri 50), RAM basse réservée
        move.b  #50,PTR_INT+LN_PRI
        clr.l   PTR_INT+IS_DATA
        move.l  #pointer_input_handler,PTR_INT+IS_CODE
        lea     -48(sp),sp               ; IOStdReq scratch
        move.l  sp,a1
        move.l  a4,IO_DEVICE(a1)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a1)
        move.l  #PTR_INT,INP_IO_DATA(a1)
        move.l  a4,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        lea     48(sp),sp
.pw_ret:
        movem.l (sp)+,a2/a4
        rts

; m6r_wire_requester : câble les handlers CONSOMMATEURS (pointeur pri 50 + requester pri 0) PERSISTANTS sur
; input.device (PAS de teardown) -> la chaîne gameport -> input.device -> pointeur -> requester vit dans le
; système tournant (symétrique du producteur gp_vblank_server persistant). Puis self-check SYNCHRONE : injecte via
; les handlers persistants un move relatif -> gadget puis un clic -> REQ_HIT -> « M6R WIRED OK ». a6 = SysBase.
; Appelé une fois dans la branche M6R insert-disk (IRQ masquées ; IND_WRITEEVENT est synchrone). Préserve a2-a4.
m6r_wire_requester:
        movem.l a2-a4,-(sp)
        lea     EB_DEVICELIST(a6),a0
        lea     input_dev_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .mw_ret
        move.l  d0,a4                    ; a4 = input.device base
        bsr     ptr_wire                 ; handler pointeur pri 50 (PERSISTANT)
        clr.l   REQ_INT+LN_SUCC          ; struct Interrupt requester (pri 0)
        clr.b   REQ_INT+LN_PRI
        clr.l   REQ_INT+IS_DATA
        move.l  #req_input_handler,REQ_INT+IS_CODE
        lea     -48(sp),sp               ; IOStdReq scratch
        move.l  sp,a2                    ; a2 = ioreq
        lea     REQ_INT,a0               ; ADDHANDLER requester (PERSISTANT)
        bsr.s   .mw_add
        clr.w   PTR_X                    ; self-check : les handlers persistants répondent-ils ?
        clr.w   PTR_Y
        clr.w   REQ_HIT
        lea     -24(sp),sp               ; InputEvent scratch
        move.l  sp,a3                    ; a3 = event
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a3)
        clr.b   IE_SUBCLASS(a3)
        clr.w   IE_QUALIFIER(a3)
        clr.l   IE_NEXTEVENT(a3)
        move.w  #IECODE_NOBUTTON,IE_CODE(a3)  ; move relatif -> (160,112) sur le gadget
        move.w  #160,IE_X(a3)
        move.w  #112,IE_Y(a3)
        bsr.s   .mw_write
        move.w  #IECODE_LBUTTON,IE_CODE(a3)   ; clic (delta nul) -> hit-test (160,112) -> REQ_HIT
        clr.w   IE_X(a3)
        clr.w   IE_Y(a3)
        clr.l   IE_NEXTEVENT(a3)
        bsr.s   .mw_write
        lea     24(sp),sp                ; libère l'event scratch
        cmp.w   #1,REQ_HIT               ; les handlers PERSISTANTS ont traité le clic ?
        bne.s   .mw_done
        lea     msg_m6r_wired(pc),a0
        bsr     ser_puts                 ; « M6R WIRED OK »
.mw_done:
        clr.w   PTR_X                    ; remet le pointeur à zéro pour la vraie souris (handlers RESTENT câblés)
        clr.w   PTR_Y
        clr.w   REQ_HIT
        lea     48(sp),sp                ; libère l'ioreq scratch
.mw_ret:
        movem.l (sp)+,a2-a4
        rts
.mw_add:                                 ; IND_ADDHANDLER(a0 = struct Interrupt) ; a2=ioreq, a4=input base
        move.l  a4,IO_DEVICE(a2)
        move.w  #IND_ADDHANDLER,IO_COMMAND(a2)
        move.l  a0,INP_IO_DATA(a2)
        bra.s   .mw_bio
.mw_write:                               ; IND_WRITEEVENT(a3 = event) ; a2=ioreq, a4=input base
        move.l  a4,IO_DEVICE(a2)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a2)
        move.l  a3,INP_IO_DATA(a2)
.mw_bio:
        move.l  a2,a1
        move.l  a4,a6
        jsr     -30(a6)
        move.l  ($4).w,a6
        rts

; vbl_tail_server (M7f) : serveur VERTB de plus basse priorité (-10). Incrémente VERTB_CHAIN_N ->
; prouve que le walker parcourt TOUTE la chaîne VERTB (sched_server pri 20 + timer_vblank pri 0 ont donc
; tourné AVANT lui). a1=IS_DATA (inutilisé), a6=SysBase. Préserve d2-d7/a2-a4 (ne touche que d0+mémoire).
vbl_tail_server:
        addq.l  #1,VERTB_CHAIN_N
        ; M7g : déclenche COPER par LOGICIEL (2e source niveau 3), rate-limité 1 VBlank sur 4, pour prouver
        ; le décodage multi-source d'int3 (COPER sera servie au prochain INT3). Scratch d0 (préserve d2-d7/a2-a4).
        addq.b  #1,COPER_TICK
        move.b  COPER_TICK,d0
        and.b   #3,d0
        bne.s   .vt_z
        move.w  #(INTF_SETCLR|INTF_COPER),INTREQ ; pose la requête COPER (Paula)
.vt_z:
        moveq   #0,d0                ; Z set -> continue (dernier noeud : fin de chaîne de toute façon)
        rts

; coper_test (M7g) : handler EXCLUSIF de la source COPER (niveau 3), installé par SetIntVector. Prouve
; que le décodage INTREQR d'int3 dispatche une 2e source de niveau 3. a0=$DFF000, a1=IS_DATA (inutilisé),
; a6=SysBase. Préserve d2-d7/a2-a4 (ne touche que COPER_FIRED -> d2 de int3_dispatch survit).
coper_test:
        addq.l  #1,COPER_FIRED
        rts

; coper_int (M7g) : struct Interrupt du vecteur EXCLUSIF COPER (SetIntVector copie IS_DATA/IS_CODE ->
; peut rester en ROM). IS_CODE -> coper_test. IS_DATA inutilisé.
        EVEN
coper_int:
        dc.l    0                    ; LN_SUCC
        dc.l    0                    ; LN_PRED
        dc.b    0                    ; LN_TYPE
        dc.b    0                    ; LN_PRI (inusité : vecteur exclusif)
        dc.l    coper_int_name       ; LN_NAME
        dc.l    0                    ; IS_DATA
        dc.l    coper_test           ; IS_CODE
coper_int_name:
        dc.b    "test.coper",0

; ciab_server_int (M7b) : vecteur EXCLUSIF EXTER installé par SetIntVector -> ciab_server. Non chaîné
; (SetIntVector copie IS_DATA/IS_CODE) -> peut rester en ROM. IS_DATA inutilisé (ciab_server lit CIAB_PTR).
        EVEN
ciab_server_int:
        dc.l    0                    ; LN_SUCC
        dc.l    0                    ; LN_PRED
        dc.b    0                    ; LN_TYPE
        dc.b    0                    ; LN_PRI (inusité : vecteur exclusif)
        dc.l    srv_ciab_name        ; LN_NAME
        dc.l    0                    ; IS_DATA
        dc.l    ciab_server          ; IS_CODE
srv_ciab_name:
        dc.b    "ciab.exter",0
        EVEN

; ============================ résident AUTOINIT démo (M5a) =========
; ROMTag RTF_AUTOINIT (pri 40) -> InitResident appelle MakeLibrary avec la table de 4 longs.
; Prouve : jump table bâtie (func0 rend $5A), InitStruct pose version/type, init func pose
; la révision + le nom, lib ajoutée à LibList. Table de vecteurs ABSOLUE (longwords, -1).
; Data table = INITWORD(LIB_VERSION,40) + INITBYTE(LN_TYPE,NT_LIBRARY). Le nom (adresse) est
; posé par l'init func (PC-relative), pas par InitStruct (une adresse relogée ne peut pas être
; scindée en deux mots à l'assemblage).
        EVEN
res_auto:
        dc.w    RTC_MATCHWORD
        dc.l    res_auto             ; RT_MATCHTAG = self
        dc.l    res_auto_end         ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT|RTF_COLDSTART,1,NT_LIBRARY,40  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    autolib_name         ; RT_NAME
        dc.l    autolib_name         ; RT_IDSTRING
        dc.l    autolib_inittab      ; RT_INIT -> table AUTOINIT (4 longs)
autolib_name:
        dc.b    "demo.autolib",0
        EVEN
autolib_inittab:
        dc.l    LIB_SIZE             ; dataSize (base mini)
        dc.l    autolib_vectors      ; funcTable
        dc.l    autolib_datatab      ; dataTable (InitStruct)
        dc.l    autolib_initfunc     ; initFunc
autolib_vectors:                     ; table RELATIVE (exerce la détection + l'arithmétique word)
        dc.w    -1                            ; marqueur : déplacements word relatifs à cette base
        dc.w    autolib_func0-autolib_vectors ; LVO -6
        dc.w    autolib_func1-autolib_vectors ; LVO -12
        dc.w    -1                            ; terminateur (word)
autolib_datatab:
        dc.w    $D000,LIB_VERSION,40          ; INITWORD(LIB_VERSION, 40)
        dc.w    $E000,LN_TYPE,(NT_LIBRARY<<8) ; INITBYTE(LN_TYPE, NT_LIBRARY)
        dc.b    0                             ; terminateur du flux InitStruct
        EVEN
autolib_func0:                       ; appelée via jsr -6(base) -> preuve MakeFunctions
        moveq   #$5A,d0
        rts
autolib_func1:                       ; LVO -12 (non exercée)
        moveq   #0,d0
        rts
autolib_initfunc:                    ; (D0=base, A0=segList, A6=ExecBase) -> D0 = base
        move.l  d0,a1                ; a1 = base
        move.w  #$5A,LIB_REVISION(a1) ; preuve : l'init func a tourné
        lea     autolib_name(pc),a0
        move.l  a0,LN_NAME(a1)       ; nom (adresse, PC-relative) -> OpenLibrary/FindName
        rts                          ; d0 = base inchangé
        EVEN
res_auto_end:

; ============================ données ==============================
exec_name:
        dc.b    "exec.library",0
exec_id:
        dc.b    "exec 34.2 (clean-room reimpl)",13,10,0
str_alpha:
        dc.b    "alpha",0
str_beta:
        dc.b    "beta",0
str_gamma:
        dc.b    "gamma",0
task_test_name:
        dc.b    "testtask",0
str_port:
        dc.b    "testport",0
task_h_name:
        dc.b    "demo.H",0
task_l_name:
        dc.b    "demo.L",0
task_s_name:
        dc.b    "demo.S",0
task_t_name:
        dc.b    "demo.timer",0
task_p_name:
        dc.b    "demo.port",0
task_fa_name:
        dc.b    "demo.forbidA",0
task_fb_name:
        dc.b    "demo.forbidB",0
task_q2_name:
        dc.b    "demo.q2",0
task_rm_name:
        dc.b    "demo.rm",0
msg_cold:
        dc.b    "EXEC coldstart: overlay off, stack live",13,10,0
msg_f2kbd:
        dc.b    "F2 KBD OK (CIA-A keyboard: power-up stream received+decoded, $FD initiate + $FE terminate; handshake drives the stream)",13,10,0
msg_f2bkbd:
        dc.b    "F2B KBD OK (live keyboard driver: AddICRVector SP bit3 -> kbd_interrupt -> keymap -> ring; console READ drains it)",13,10,0
msg_input_ok:
        dc.b    "INPUT OK (input.device: IND_ADDHANDLER pri-sorted chain + IND_WRITEEVENT propagates RAWKEY; 2 handlers in pri order, keycode relayed)",13,10,0
input_dev_name:
        dc.b    "input.device",0
msg_console_ok:
        dc.b    "CONSOLE WRITE OK (console.device CMD_WRITE: 8x8 glyph blitter into bitplane; readback matches font)",13,10,0
console_dev_name:
        dc.b    "console.device",0
msg_conread_ok:
        dc.b    "CONSOLE READ=v (console.device input handler on input.device cooked a RAWKEY -> read buffer -> CMD_READ)",13,10,0
msg_diskvalid:
        dc.b    "DISK VALID OK (disk-validator: OFS rootblock+bitmap checksums, bm_flag valid, rootblock allocated in bitmap)",13,10,0
msg_keymap_ok:
        dc.b    "KEYMAP OK (keymap.resource US QWERTY: kbd_cook keycode+SHIFT/CAPS/CTRL -> q/Q/Q, 1/!, ctrl-C=$03)",13,10,0
msg_keymap_azerty:
        dc.b    "KEYMAP AZERTY OK (keymap.resource FR AZERTY: kbd_cook keycode $10->a, $01->& (SHIFT->1), $02->e-acute)",13,10,0
msg_req_drawn:
        dc.b    "REQUESTER DRAWN OK (insert-disk requester: border + text rendered via font8x8; bitplane readback matches)",13,10,0
msg_req_click:
        dc.b    "REQUESTER CLICK OK (RAWMOUSE via input.device: click inside gadget -> hit, click outside -> miss)",13,10,0
msg_gameport_ok:
        dc.b    "GAMEPORT OK (gameport.device logic: gp_delta8 8-bit wraparound, button edge-detect, RAWMOUSE emitted via IND_WRITEEVENT)",13,10,0
msg_m6r_live_ok:
        dc.b    "M6R LIVE OK (relative RAWMOUSE deltas -> pointer accumulator -> absolute clamped pos -> requester hit-test: on gadget -> hit, off -> miss)",13,10,0
msg_gp_live_ok:
        dc.b    "GP VBLANK LIVE OK (gameport VBlank server runs on real frame interrupts in the running system: GP_POLLS advancing)",13,10,0
msg_m6r_wired:
        dc.b    "M6R WIRED OK (pointer+requester handlers registered PERSISTENTLY on input.device in the running system; injected click -> REQ_HIT)",13,10,0
        EVEN
con_test_str:
        dc.b    "CONSOLE WRITE OK 0123456789"
con_test_end:
        dc.b    0
        EVEN
msg_ok:
        dc.b    "EXEC ExecBase + jump table OK, self-test passed",13,10,0
msg_fail:
        dc.b    "EXEC self-check/self-test FAILED",13,10,0
chk_core:
        dc.b    "chk core",13,10,0
chk_mem:
        dc.b    "chk mem",13,10,0
chk_m24a:
        dc.b    "chk m24a",13,10,0
chk_m24b:
        dc.b    "chk m24b",13,10,0
chk_m24c:
        dc.b    "chk m24c",13,10,0
msg_vblok:
        dc.b    "M3 VBlank interrupts live",13,10,0
msg_vbltimeout:
        dc.b    "M3 VBL timeout",13,10,0
msg_m3flive:
        dc.b    "M3F LIVE: preemption + yield coexist (both scheduling paths OK)",13,10,0
msg_forbid_ok:
        dc.b    "FORBID ATOMIC OK (deferred reschedule honors Forbid: pri-7 task signaled under a pri-3 Forbid did NOT preempt it; intr_isr_defer gates on TDNestCnt)",13,10,0
msg_m3ffail:
        dc.b    "M3F FAILED: context sentinel corrupted across a switch",13,10,0
msg_res_ok:
        dc.b    "M4 RESIDENTS OK (scan + InitResident in priority order)",13,10,0
msg_auto_ok:
        dc.b    "M5A AUTOINIT OK (MakeLibrary + MakeFunctions + InitStruct)",13,10,0
msg_res_fail:
        dc.b    "M4 FAILED: resident scan/init incorrect",13,10,0
msg_auto_fail:
        dc.b    "M5A FAILED: AUTOINIT/MakeLibrary incorrect",13,10,0
msg_cia_ok:
        dc.b    "M5B CIA OK (cia.resource: OpenResource + AbleICR + AddICRVector)",13,10,0
msg_cia_fail:
        dc.b    "M5B FAILED: cia.resource incorrect",13,10,0
msg_timer_ok:
        dc.b    "M5C TIMER OK (timer.device AUTOINIT -> DeviceList, Open works)",13,10,0
msg_m4c1_ok:
        dc.b    "M4C1 GFX LIB OK (graphics.library AUTOINIT -> LibList, NT_LIBRARY routing, Open works)",13,10,0
msg_timer_fail:
        dc.b    "M5C FAILED: timer.device incorrect",13,10,0
msg_m6a_ok:
        dc.b    "M6A TIMER OK (VBLANK unit: request replied after ~5 ticks)",13,10,0
msg_m6a_fail:
        dc.b    "M6A FAILED: timer VBLANK unit incorrect",13,10,0
msg_m7b_ok:
        dc.b    "M7B PORTS OK (per-number dispatch: AddIntServer chain, 2 servers in pri order)",13,10,0
msg_m7b_fail:
        dc.b    "M7B FAILED: per-number interrupt dispatch / server chain incorrect",13,10,0
msg_m7a_ok:
        dc.b    "M7A TIMER OK (MICROHZ via CIA-B/INT6: task woke on timer, reentrancy gate held)",13,10,0
msg_m7a_fail:
        dc.b    "M7A FAILED: MICROHZ wake or scheduler-list reentrancy gate",13,10,0
msg_m7c_ok:
        dc.b    "M7C USERMODE OK (user-mode tasks on shared SSP, deferred Dispatch survives preemption)",13,10,0
msg_m7d_ok:
        dc.b    "M7D PORTS OK (interrupt-safe PutMsg/GetMsg: task vs IRQ race on shared port, no corruption)",13,10,0
msg_m7d_fail:
        dc.b    "M7D FAILED: shared-port list corrupted (task GetMsg vs IRQ PutMsg race)",13,10,0
msg_m7e_ok:
        dc.b    "M7E IPL OK (native-IPL: INT6 preempts vbl body; scheduler surgery IPL7-atomic, no overlap)",13,10,0
msg_m7f_ok:
        dc.b    "M7F VERTB OK (VERTB is a server chain: sched+timer+tail walked in pri order via int3_dispatch)",13,10,0
msg_m7g_ok:
        dc.b    "M7G MULTISRC OK (int3 decodes INTREQR, services each pending level-3 source; COPER, not just VERTB)",13,10,0
msg_m7h_ok:
        dc.b    "M7H QUANTUM OK (isolation: 2 equal-pri spinners rotate every ~QUANTUM ticks, not every tick)",13,10,0
msg_m7j_ok:
        dc.b    "M7J REMTASK OK (task ended -> RemTask self freed its stack+TCB, AvailMem recovered)",13,10,0
msg_m7l_ok:
        dc.b    "M7L MICROHZ CALIB OK (TV_MICRO = real us: 0.5s MICROHZ request elapsed ~25 VBLANK ticks)",13,10,0
msg_m6t_ok:
        dc.b    "M6T TRACKDISK OK (trackdisk.device AUTOINIT -> DeviceList; Open unit 0 OK + io_Unit=base+34; Open unit 4 -> OpenDevice fail: io_Error, io_Device=0)",13,10,0
msg_m6u_syncs:
        dc.b    "M6U SYNCS=",0
msg_m6u_ok:
        dc.b    "M6U TRACKDISK READ OK (raw MFM track read from DF0 via disk DMA; $4489 sync words found)",13,10,0
msg_m6v_sect:
        dc.b    "M6V SECTORS=",0
msg_m6v_ok:
        dc.b    "M6V TRACKDISK DECODE OK (MFM decoded: 11 sectors, header+data checksums valid, sector 0 = DOS bootblock)",13,10,0
msg_m6w_ok:
        dc.b    "M6W TRACKDISK CMD_READ OK (BeginIO CMD_READ: 512 bytes read from DF0 sector 0 = DOS bootblock)",13,10,0
msg_m6x_track:
        dc.b    "M6X TRACK=",0
msg_m6x_ok:
        dc.b    "M6X TRACKDISK SEEK OK (step/seek + side-select: read track 2, decoded sectors report track==2)",13,10,0
msg_m6z_ok:
        dc.b    "M6Z TRACKDISK CMD_READ MULTI-TRACK OK (offset->track: block 880 = root block @track 80; spanning read blocks 10+11 crosses track 0/1 boundary)",13,10,0
msg_d1_ok:
        dc.b    "D1 OFS READ OK (read file 'KickSlop' by name from DF0: via OFS root->hash->header->data chain; 1024 bytes, case-insensitive, 3 OFS data blocks)",13,10,0
msg_d3a_ok:
        dc.b    "D3A PACKET OK (Process+CreateProc; driver -> StandardPacket PutMsg -> handler process -> ReplyMsg -> driver got echo)",13,10,0
msg_d3b_ok:
        dc.b    "D3B HANDLER OK (file-handler process served FINDINPUT/READ/END packets; read 'kickslop' 1024 bytes via OFS, markers match)",13,10,0
msg_d3c_ok:
        dc.b    "D3C DOS OK (client process: dos.library Open/Read/Close 'kickslop' via packets -> DeviceNode handler; 1024 bytes, markers match)",13,10,0
; nom du device et géométrie DD du disque DF0 (dosfilehandler.i : DosEnvec), désignés par BPTR depuis le FSSM
        cnop    0,4
df0_device:
        dc.b    16,"trackdisk.device",0
        cnop    0,4
df0_environ:
        dc.l    12                   ; de_TableSize
        dc.l    128                  ; de_SizeBlock (longs)
        dc.l    0                    ; de_SecOrg
        dc.l    2                    ; de_Surfaces
        dc.l    1                    ; de_SectorPerBlock
        dc.l    11                   ; de_BlocksPerTrack
        dc.l    2                    ; de_Reserved
        dc.l    11                   ; de_PreAlloc
        dc.l    0                    ; de_Interleave
        dc.l    0                    ; de_LowCyl
        dc.l    79                   ; de_HighCyl
        dc.l    5                    ; de_NumBuffers
        dc.l    3                    ; de_BufMemType
dos_libname:
        dc.b    "dos.library",0
d3c_cname:
        dc.b    "dos.client",0
d3d_cname:
        dc.b    "dos.cmdclient",0
d3d_fname:
        dc.b    "d3dtest",0
d3e_cname:
        dc.b    "dos.loadsegclient",0
msg_d3e_loadseg:
        dc.b    "D3E LOADSEG LVO OK (dos.library LoadSeg -150: file opened+read+hunk-parsed+relocated via real LVO -> seglist; UnLoadSeg -156)",13,10,0
d3f_cname:
        dc.b    "dos.ioseekclient",0
d3f_badname:
        dc.b    "nosuchfile",0
msg_d3f_ok:
        dc.b    "DOS IOERR SEEK OK (IoErr -132 reflects Open-not-found then 0; Seek -66 ACTION_SEEK rewinds, re-read matches)",13,10,0
d3g_cname:
        dc.b    "dos.ioclient",0
d3h_cname:
        dc.b    "dos.bigclient",0
d3h_fname:
        dc.b    "bigseg",0
d3i_cname:
        dc.b    "dos.lockclient",0
d3i_rootname:
        dc.b    ":",0                ; racine du volume (ACTION_LOCATE_OBJECT -> OFS_ROOTBLK)
msg_d3i_ok:
        dc.b    "DOS LOCK EXAMINE OK (Lock -84 'kickslop' -> Examine -102: file, size 1024@fib_Size; Lock ':' -> ExNext -108 enumerates root, finds kickslop; UnLock -90)",13,10,0
d3j_cname:
        dc.b    "dos.streamclient",0
d3j_fname:
        dc.b    "BigData",0
msg_d3j_ok:
        dc.b    "OFS STREAM OK (dos Open/Read 'BigData' 48000 bytes > 32K old cap, incremental per-datablock stream, sentinel reached; Seek -66 cross-block re-reads @500)",13,10,0
        even
; marqueur émis PAR le Write lui-même (con_handler), pas NUL-terminé (Write utilise une longueur explicite).
msg_dos_write:
        dc.b    "DOS WRITE OK (dos Write -48 -> ACTION_WRITE -> con_handler -> serial; Input -54/Output -60/CurrentDir -126 ok)",13,10
msg_dos_write_end:
msg_dos_write_len EQU msg_dos_write_end-msg_dos_write
        even
e1_hname:
        dc.b    "con.handler",0
sh_cname:
        dc.b    "shell",0
fd_cname:
        dc.b    "feeder",0
        even
d3a_hname:
        dc.b    "dos.handler.echo",0
d3a_dname:
        dc.b    "dos.driver",0
d3b_hname:
        dc.b    "dos.handler.df0",0
d3b_dname:
        dc.b    "dos.fsdriver",0
fsd_name_src:
        dc.b    "kickslop"
        even
ofs_test_name:
        dc.b    "kickslop",0
        even
ls_test_name:
        dc.b    "d2test",0
        even
msg_m6r_ok:
        dc.b    "M6R STRAP OK (strap read DF0: bootblock and found NO bootable volume -> insert-disk; real 1.3 trigger: DOS-magic+additive-checksum invalid, or no disk)",13,10,0
msg_m6s_ok:
        dc.b    "M6S BOOTSCR OK (boot screen 320x256x5 = 32-color image displayed via graphics.library ABI; visual proof = RMSE vs reference)",13,10,0
msg_m6y_ok:
        dc.b    "M6Y STRAP BOOTED OK (strap read+validated+executed DF0: bootblock; CBOOT marker came from the bootblock itself; no insert-disk)",13,10,0
msg_m5i_ok:
        dc.b    "M5I INTUI LIB OK (intuition.library AUTOINIT -> LibList; ViewAddress -294 returns &ib_ViewLord)",13,10,0
msg_m5o_ok:
        dc.b    "M5O OPENLIB OK (OpenLibrary by name + version gate + Open vector; too-high ver -> 0; OldOpenLibrary; CloseLibrary)",13,10,0
msg_m6d_ok:
        dc.b    "M6D DOS LIB OK (dos.library AUTOINIT -> LibList; rn_Info BPTR round-trips &DosInfo; DateStamp -192 -> 0,0,0 unset + returns ptr)",13,10,0
expansion_test_name:
        dc.b    "expansion.library",0
        EVEN
msg_expansion_ok:
        dc.b    "EXPANSION OK (expansion.library: OpenLibrary v37 gated->0 / v34 ok; AllocConfigDev->AddConfigDev->FindConfigDev exact+wildcard, absent ID miss)",13,10,0
mathffp_test_name:
        dc.b    "mathffp.library",0
msg_mathffp_ok:
        dc.b    "MATHFFP OK (mathffp.library: SPFlt/SPFix/SPAdd/SPSub/SPMul/SPDiv/SPCmp/SPTst/SPNeg/SPFloor/SPCeil + div0 overflow)",13,10,0
msg_mathffp_fail:
        dc.b    "MATHFFP FAIL LVO ",0
msg_crlf_mft:
        dc.b    13,10,0
task_aud_name:
        dc.b    "task_aud",0
msg_audplay_ok:
        dc.b    "AUDIO PLAY OK (audio.device: CMD_WRITE DMA 30 cycles + queued write chained, WAITCYCLE before end, CMD_READ, channel off)",13,10,0
msg_audplay_fail:
        dc.b    "AUDIO PLAY FAIL",13,10,0
msg_gels_ok:
        dc.b    "GELS OK (graphics: InitGels/InitMasks, Bob OVERLAY+SAVEBACK drawn/moved/restored at pixel level, Bob x VSprite + border collisions, SortGList, RemIBob, Get/FreeGBuffers, InitGMasks, AddAnimOb, Animate sequence switch)",13,10,0
msg_gels_fail:
        dc.b    "GELS FAIL",13,10,0
msg_fonts_ok:
        dc.b    "FONTS OK (graphics: OpenFont topaz 8/9/unknown + accessors, InitRastPort default font, TextLength + TxSpacing, soft styles, bold Text readback)",13,10,0
msg_fonts_fail:
        dc.b    "FONTS FAIL",13,10,0
fnt_ta8:
        dc.l    fnt_topaz
        dc.w    8
        dc.b    0,0
fnt_ta9:
        dc.l    fnt_topaz
        dc.w    9
        dc.b    0,0
fnt_tanone:
        dc.l    fnt_nope
        dc.w    8
        dc.b    0,0
fnt_topaz:
        dc.b    "TOPAZ.font",0
fnt_nope:
        dc.b    "nope.font",0
fnt_abc:
        dc.b    "Abc"
fnt_i:
        dc.b    "I"
        even
msg_regions_ok:
        dc.b    "REGIONS OK (graphics: Or/And/ClearRect/XorRect + Or/Xor/AndRegionRegion: areas, bounds, points vs pixel-set model)",13,10,0
msg_regions_fail:
        dc.b    "REGIONS FAIL",13,10,0
layers_test_name:
        dc.b    "layers.library",0
msg_layers_ok:
        dc.b    "LAYERS OK (layers.library: simple+smart layers, behind/upfront backing store, damage+BeginUpdate, move, delete, size, WhichLayer)",13,10,0
msg_layers_fail:
        dc.b    "LAYERS FAIL",13,10,0
semt_name:
        dc.b    "kicksem.test",0
msg_sem_ok:
        dc.b    "SEM OK (exec semaphores: Add/FindSemaphore, Attempt + nested Obtain, Release to free)",13,10,0
msg_sem_fail:
        dc.b    "SEM FAIL",13,10,0
msg_semw_ok:
        dc.b    "SEM WAIT OK (blocked ObtainSemaphore handed over by ReleaseSemaphore: owner + nest set, woken)",13,10,0
msg_semw_fail:
        dc.b    "SEM WAIT FAIL",13,10,0
task_semw_name:
        dc.b    "task_semw",0
task_semr_name:
        dc.b    "task_semr",0
audio_test_name:
        dc.b    "audio.device",0
msg_audio_ok:
        dc.b    "AUDIO ALLOC OK (audio.device: precedence, combo order, steal + key invalidation, lock stolen, wait + retry on free)",13,10,0
msg_audio_fail:
        dc.b    "AUDIO ALLOC FAIL",13,10,0
kbddev_test_name:
        dc.b    "keyboard.device",0
msg_kbddev_ok:
        dc.b    "KBDDEV OK (keyboard.device: READMATRIX, READEVENT buffered + pending replied by event, CMD_CLEAR, AbortIO, ADD/REMRESETHANDLER)",13,10,0
msg_kbddev_fail:
        dc.b    "KBDDEV FAIL",13,10,0
potgo_test_name:
        dc.b    "potgo.resource",0
msg_potgo_ok:
        dc.b    "POTGO OK (potgo.resource: AllocPotBits START/DATxx in/out rules, FreePotBits, WritePotgo keeps high byte not START)",13,10,0
msg_potgo_fail:
        dc.b    "POTGO FAIL",13,10,0
diskres_test_name:
        dc.b    "disk.resource",0
msg_diskres_ok:
        dc.b    "DISKRES OK (disk.resource: AllocUnit/FreeUnit, GetUnitID(0)=DRT_AMIGA, GetUnit busy->queue, GiveUnit->ReplyMsg) DF1 ID=",0
msg_diskres_fail:
        dc.b    "DISKRES FAIL",13,10,0
        EVEN
; LVO.w, d0.l, d1.l, attendu.l — 3.0=$C0000042, -10.0=$A00000C4, 1.0=$80000041, -2.5=$A00000C2.
mft_table:
        dc.w    -36
        dc.l    3,0,$C0000042                    ; SPFlt(3)
        dc.w    -36
        dc.l    -10,0,$A00000C4                  ; SPFlt(-10)
        dc.w    -78
        dc.l    $C0000042,$A00000C4,$F00000C5    ; SPMul(3,-10) = -30
        dc.w    -30
        dc.l    $F00000C5,0,-30                  ; SPFix(-30.0)
        dc.w    -84
        dc.l    $80000041,$C0000042,$AAAAAB3F    ; SPDiv : 1/3 arrondi au plus près
        dc.w    -78
        dc.l    $AAAAAB3F,$C0000042,$80000041    ; SPMul(1/3,3) = 1.0 après arrondi
        dc.w    -66
        dc.l    $C0000042,$A00000C4,$E00000C3    ; SPAdd(3,-10) = -7
        dc.w    -72
        dc.l    $C0000042,$A00000C4,$D0000044    ; SPSub : 3 - (-10) = 13
        dc.w    -42
        dc.l    $C0000042,$A00000C4,1            ; SPCmp(3,-10) -> +1
        dc.w    -42
        dc.l    $A00000C4,$C0000042,-1           ; SPCmp(-10,3) -> -1
        dc.w    -48
        dc.l    0,$A00000C4,-1                   ; SPTst(-10) en d1 -> -1
        dc.w    -60
        dc.l    $C0000042,0,$C00000C2            ; SPNeg(3) = -3
        dc.w    -90
        dc.l    $A00000C2,0,$C00000C2            ; SPFloor(-2.5) = -3
        dc.w    -96
        dc.l    $A00000C2,0,$800000C2            ; SPCeil(-2.5) = -2
        dc.w    -90
        dc.l    $C0000042,0,$C0000042            ; SPFloor(3) = 3
        dc.w    -36
        dc.l    123456,0,$F1200051               ; SPFlt(123456)
        dc.w    -30
        dc.l    $F1200051,0,123456               ; SPFix -> aller-retour exact
        dc.w    -84
        dc.l    $C0000042,0,$FFFFFF7F            ; SPDiv(3/0) -> plus grand positif
mft_table_end:
ciaa_test_name:
        dc.b    "ciaa.resource",0
ciab_test_name:
        dc.b    "ciab.resource",0
timer_test_name:
        dc.b    "timer.device",0
trackdisk_test_name:
        dc.b    "trackdisk.device",0
graphics_test_name:
        dc.b    "graphics.library",0
intuition_test_name:
        dc.b    "intuition.library",0
noexist_test_name:
        dc.b    "inexistante.library",0
dos_test_name:
        dc.b    "dos.library",0
msg_memslow:
        dc.b    "MEM SLOW KB=",0
        EVEN

; rdf_selftest : RawDoFmt via la jump table (LVO -522) dans un tampon pile, comparé octet à octet (NUL compris) à
; rdf_expect -> « RAWDOFMT OK » ou « RAWDOFMT FAILED ». Couvre d/ld signés, largeur, cadrage gauche, remplissage
; '0' avec signe, x, s, c, et la restitution de a3. a6 = SysBase. Préserve tout.
rdf_selftest:
        movem.l d0-d1/a0-a3,-(sp)
        lea     -64(sp),sp
        lea     rdf_fmt(pc),a0
        lea     rdf_data(pc),a1
        lea     rdf_putch(pc),a2
        move.l  sp,a3
        jsr     LVO_RAWDOFMT(a6)
        cmp.l   sp,a3                ; a3 doit être restitué (convention d'appel)
        bne.s   .rdf_bad
        move.l  sp,a0
        lea     rdf_expect(pc),a1
.rdf_cmp:
        move.b  (a1)+,d0
        cmp.b   (a0)+,d0
        bne.s   .rdf_bad
        tst.b   d0
        bne.s   .rdf_cmp
        lea     msg_rdf_ok(pc),a0
        bra.s   .rdf_out
.rdf_bad:
        lea     msg_rdf_bad(pc),a0
.rdf_out:
        bsr     ser_puts
        lea     64(sp),sp
        movem.l (sp)+,d0-d1/a0-a3
        rts
rdf_putch:
        move.b  d0,(a3)+
        rts
rdf_fmt:
        dc.b    "%d|%5ld|%-3x|%s|%04x|%c|%05ld",0
rdf_expect:
        dc.b    "-42| 1234|AB |hi|001F|Z|-0007",0
rdf_hi:
        dc.b    "hi",0
        EVEN
rdf_data:
        dc.w    -42
        dc.l    1234
        dc.w    $AB
        dc.l    rdf_hi
        dc.w    $1F
        dc.w    'Z'
        dc.l    -7
msg_rdf_ok:
        dc.b    "RAWDOFMT OK (exec RawDoFmt -522: d/ld, width, left-justify, zero-pad with sign, x, s, c)",13,10,0
msg_rdf_bad:
        dc.b    "RAWDOFMT FAILED",13,10,0
        EVEN
msg_crlf:
        dc.b    13,10,0
        EVEN
