; src/exec/gameport.s — gameport.device (souris matérielle) : driver + injecteur d'InputEvents RAWMOUSE.
;
; Rôle : lire le matériel souris chaque VBlank (JOY0DAT = compteurs quadrature X/Y ; CIAA_PRA bit 6 = bouton
; gauche, actif-bas), transformer les lectures en InputEvents RAWMOUSE (deltas signés avec wraparound 8 bits +
; détection de front bouton) et les injecter dans input.device via IND_WRITEEVENT. C'est le PENDANT souris du
; feeder clavier : comme lui, on utilise IND_WRITEEVENT (chemin d'injection PUBLIC) au lieu d'un input.task
; (déviation documentée, cf. input.s). Intuition (pointer.s) accumule ensuite ces deltas en position absolue.
;
; FACTORISATION (preuve en salle blanche headless) : la souris matérielle n'est PAS observable sous FS-UAE
; headless (deltas JOY0DAT RELATIFS + pas de mouvement injectable + framebuffer non capturable). On sépare donc :
;   - gp_delta8 / gp_poll : LOGIQUE PURE (delta+wraparound, edge bouton, construction d'event, IND_WRITEEVENT),
;     pilotable avec des snapshots SYNTHÉTIQUES de registres -> prouvée exhaustivement (« GAMEPORT OK »).
;   - gp_vblank_server : SHIM matériel mince (lit les vrais registres -> gp_poll). Seule partie non-E2E ;
;     prouvée STRUCTURELLEMENT : enregistrée sur la chaîne VERTB du système tournant, son compteur GP_POLLS
;     avance sur les VBlanks réels (« GP VBLANK LIVE OK »). Sur JOY0DAT statique (headless) elle n'émet rien.
; Piste IMPLÉMENTATION (« clean ») : HRM (JOY0DAT/CIAA PRA) + NDK devices/gameport.i + inputevent.i. AUCUNE lecture ROM.

                include "exec.i"

                xdef    gp_delta8
                xdef    gp_poll
                xdef    gp_vblank_server
                xdef    gp_install
                xdef    gameport_dev_name

IO_DATA2        EQU 40               ; IOStdReq io_Data (APTR) — local (évite d'inclure disk.i)
GAMEPORT_SIZE   EQU LIB_SIZE         ; base gameport.device : nœud Library seul (pas d'état device propre)

; --- ROMTag gameport.device (scanné par build_reslist ; pri 60 = place roadmap gameport) ---
                EVEN
gameport_romtag:
        dc.w    RTC_MATCHWORD
        dc.l    gameport_romtag      ; RT_MATCHTAG = self
        dc.l    gameport_end         ; RT_ENDSKIP
        dc.b    RTF_AUTOINIT,34,NT_DEVICE,60  ; RT_FLAGS, RT_VERSION, RT_TYPE, RT_PRI
        dc.l    gameport_dev_name    ; RT_NAME
        dc.l    gameport_dev_name    ; RT_IDSTRING
        dc.l    gameport_inittab     ; RT_INIT -> table AUTOINIT
gameport_dev_name:
        dc.b    "gameport.device",0
        EVEN
gameport_inittab:
        dc.l    GAMEPORT_SIZE        ; dataSize
        dc.l    gameport_vectors     ; funcTable
        dc.l    gameport_datatab     ; dataTable (InitStruct)
        dc.l    gameport_initfunc    ; initFunc
gameport_vectors:                    ; table ABSOLUE, terminée par -1 (ordre device standard)
        dc.l    gameport_open        ; LVO -6
        dc.l    gameport_close       ; LVO -12
        dc.l    gameport_expunge     ; LVO -18
        dc.l    gameport_null        ; LVO -24 (réservé)
        dc.l    gameport_beginio     ; LVO -30
        dc.l    gameport_abortio     ; LVO -36
        dc.l    -1
gameport_datatab:
        dc.w    $E000,LN_TYPE,(NT_DEVICE<<8)   ; INITBYTE(LN_TYPE, NT_DEVICE)
        dc.w    $D000,LIB_VERSION,34           ; INITWORD(LIB_VERSION, 34)
        dc.b    0
        EVEN

gameport_open:
        addq.w  #1,LIB_OPENCNT(a6)
        rts
gameport_close:
        subq.w  #1,LIB_OPENCNT(a6)
        moveq   #0,d0
        rts
gameport_expunge:
        moveq   #0,d0                ; base résidente : pas d'expunge
        rts
gameport_null:
        moveq   #0,d0
        rts
gameport_abortio:
        moveq   #0,d0
        rts

; gameport_beginio(device a6, ioreq a1) : notre gameport n'expose PAS de commandes gpd (GPD_READEVENT...). Son
; rôle actif est le poller VBlank qui injecte via IND_WRITEEVENT (pattern feeder) — comme input.device ne fait
; pas d'input.task. Toute commande io reçoit donc IOERR_NOCMD (le nœud device existe pour le ROMTag/parité carte).
gameport_beginio:
        move.b  #IOERR_NOCMD,IO_ERROR(a1)
        rts

; initFunc (D0=base, A0=segList, A6=ExecBase) -> D0 = base. Pose le nom (quirk V34). Le poller VBlank n'est PAS
; armé ici (init résident = tôt) : gp_install (appelé au bringup système) prime l'état + enregistre le serveur.
gameport_initfunc:
        move.l  d0,a1
        lea     gameport_dev_name(pc),a0
        move.l  a0,LN_NAME(a1)
        rts

; gp_delta8(d0.b = cur, d1.b = prev) -> d0.w = delta signé. Les compteurs quadrature JOY0DAT sont des octets qui
; WRAPPENT : (cur - prev) mod 256 puis sign-extend octet->mot donne le delta correct pour |delta| <= 127 (couvre
; tout mouvement réaliste par frame). Ne touche que d0 (lit d1).
gp_delta8:
                ifne    GP_NO_WRAP
        and.w   #$00FF,d0            ; RED : soustraction en MOT des valeurs 0..255 (PAS de modulo octet)
        and.w   #$00FF,d1
        sub.w   d1,d0               ; -> delta FAUX au passage $FF/$00 (ex: $FE->$01 = -253 au lieu de +3)
        rts
                endc
        sub.b   d1,d0               ; (cur - prev) mod 256
        ext.w   d0                  ; sign-extend octet -> mot : delta signé correct malgré le wraparound
        rts

; gp_poll(d0.w = JOY0DAT courant, d1.b = CIAA_PRA courant) : cœur logique. Calcule dx/dy (vs GP_PREV_JOY, via
; gp_delta8), détecte le front du bouton gauche (vs GP_PREV_BTN ; PRA bit 6 actif-bas), et si mouvement OU front,
; construit un InputEvent RAWMOUSE (ie_Code = $68 down / $E8 up / $FF mouvement ; ie_X=dx ie_Y=dy) et l'injecte
; dans input.device (GP_INPUTBASE) via IND_WRITEEVENT. Met GP_PREV_JOY/GP_PREV_BTN à jour. a6 = SysBase en entrée
; (rechargé via ($4).w), a6 = SysBase en sortie. Préserve d2-d7/a2-a4 (convention serveur VERTB).
gp_poll:
        movem.l d2-d7/a2-a4,-(sp)
        moveq   #0,d6
        move.b  d1,d6               ; d6 = CIAA_PRA (sauvé avant que les gp_delta8 clobbent d1)
        move.w  d0,d2               ; d2 = JOY0DAT courant
        move.w  GP_PREV_JOY,d3       ; d3 = JOY0DAT précédent
        move.b  d2,d0               ; dx = delta8(curX = octet bas, prevX = octet bas)
        move.b  d3,d1
        bsr     gp_delta8
        move.w  d0,d4               ; d4 = dx
        move.w  d2,d0               ; dy = delta8(curY = octet haut, prevY = octet haut)
        lsr.w   #8,d0
        move.w  d3,d1
        lsr.w   #8,d1
        bsr     gp_delta8
        move.w  d0,d5               ; d5 = dy
        move.w  d2,GP_PREV_JOY       ; mémorise la lecture courante
        moveq   #0,d7               ; d7 = bouton courant pressé (1/0)
        btst    #6,d6               ; CIAA_PRA bit 6 : 0 = pressé (actif-bas)
        bne.s   .gp_notpressed
        moveq   #1,d7
.gp_notpressed:
        moveq   #0,d2               ; d2 = bouton précédent (réutilise d2, JOY courant déjà rangé)
        move.b  GP_PREV_BTN,d2
        move.b  d7,GP_PREV_BTN       ; mémorise l'état courant
        moveq   #0,d1               ; d1 = flag « émettre » (0/1)
        moveq   #0,d3               ; d3 = ie_Code
                ifne    GP_NO_EDGE
        tst.l   d7                  ; RED : émet un down à CHAQUE poll pressé (ignore le front)
        beq.s   .gp_motion
        move.w  #IECODE_LBUTTON,d3
        moveq   #1,d1
        bra.s   .gp_motion
                endc
                ifeq    GP_NO_EDGE
        cmp.l   d2,d7               ; front bouton ? (précédent vs courant)
        beq.s   .gp_motion          ; pas de changement -> pas d'event bouton
        tst.l   d7
        beq.s   .gp_release
        move.w  #IECODE_LBUTTON,d3  ; relâché -> pressé : down ($68)
        moveq   #1,d1
        bra.s   .gp_motion
.gp_release:
        move.w  #(IECODE_LBUTTON|IECODE_UP_PREFIX),d3 ; pressé -> relâché : up ($E8)
        moveq   #1,d1
                endc
.gp_motion:
        tst.b   d1
        bne.s   .gp_emit            ; event bouton déjà décidé -> l'émettre (avec dx/dy courants)
        move.w  d4,d0               ; sinon : y a-t-il du mouvement ?
        or.w    d5,d0
        beq     .gp_noemit          ; ni bouton ni mouvement -> rien (anti-flood)
        move.w  #IECODE_NOBUTTON,d3 ; mouvement pur
        moveq   #1,d1
.gp_emit:
        move.l  GP_INPUTBASE,d0
        beq.s   .gp_noemit          ; pas de cible d'injection
        move.l  d0,a4               ; a4 = base input.device
        lea     -72(sp),sp          ; scratch pile : InputEvent(22) @ sp, IOStdReq(48) @ sp+24
        move.l  sp,a1               ; construit l'InputEvent RAWMOUSE
        clr.l   IE_NEXTEVENT(a1)
        move.b  #IECLASS_RAWMOUSE,IE_CLASS(a1)
        clr.b   IE_SUBCLASS(a1)
        move.w  d3,IE_CODE(a1)
        clr.w   IE_QUALIFIER(a1)
        move.w  d4,IE_X(a1)
        move.w  d5,IE_Y(a1)
        lea     24(sp),a3           ; construit l'IOStdReq IND_WRITEEVENT
        move.l  a4,IO_DEVICE(a3)
        move.w  #IND_WRITEEVENT,IO_COMMAND(a3)
        move.l  sp,IO_DATA2(a3)     ; io_Data = &event (base pile)
        move.l  a4,a6
        move.l  a3,a1
        jsr     -30(a6)             ; input.device BeginIO (IND_WRITEEVENT) — parcourt la chaîne de handlers
        move.l  ($4).w,a6           ; recharge SysBase
        lea     72(sp),sp
.gp_noemit:
        movem.l (sp)+,d2-d7/a2-a4
        rts

; gp_vblank_server : SHIM matériel. Serveur de la chaîne VERTB (AddIntServer) -> tourne chaque frame dans le
; système tournant. Lit les vrais registres souris et appelle gp_poll. Convention serveur : a6=SysBase (fourni),
; préserve d2-d7/a2-a4 (gp_poll le garantit), retourne Z-set (d0=0 -> « continue la chaîne »). Headless : JOY0DAT
; statique -> gp_poll ne trouve ni mouvement ni front -> aucun IND_WRITEEVENT (inerte, sans effet sur M7).
gp_vblank_server:
        addq.l  #1,GP_POLLS         ; preuve live : un poll de plus sur un VBlank RÉEL
        move.w  JOY0DAT,d0          ; compteurs quadrature souris (shim matériel)
        moveq   #0,d1
        move.b  CIAA_PRA,d1         ; bouton gauche (bit 6, actif-bas)
        bsr     gp_poll
        moveq   #0,d0               ; Z-set -> serveur call-all : continue la chaîne VERTB
        rts

; gp_install(a6 = SysBase) : arme le poller souris dans le système tournant. (1) publie la base input.device
; (GP_INPUTBASE) pour l'injection ; (2) PRIME GP_PREV_JOY avec la lecture JOY0DAT COURANTE (pas 0 : sinon un
; delta parasite à la 1re frame) et GP_PREV_BTN avec l'état bouton courant ; (3) enregistre gp_vblank_server sur
; la chaîne VERTB (AddIntServer, pri 5). Clobbe d0/d1/a0/a1 (+ ce qu'AddIntServer clobbe). À appeler IRQ masquées.
gp_install:
        clr.l   GP_POLLS
        clr.b   GP_LIVE_STAT
        lea     EB_DEVICELIST(a6),a0 ; publie la base input.device (0 si absente -> gp_poll n'injecte pas)
        lea     gp_inputname(pc),a1
        jsr     LVO_FINDNAME(a6)
        move.l  d0,GP_INPUTBASE
        move.w  JOY0DAT,GP_PREV_JOY  ; prime le delta sur la lecture courante (évite le parasite frame 1)
        moveq   #0,d0
        move.b  CIAA_PRA,d0          ; prime l'état bouton courant
        moveq   #0,d1
        btst    #6,d0
        bne.s   .gi_btndone
        moveq   #1,d1
.gi_btndone:
        move.b  d1,GP_PREV_BTN
        clr.l   GP_VBL_INT+LN_SUCC   ; struct Interrupt en RAM basse réservée (non garantie nulle au power-on)
        clr.l   GP_VBL_INT+IS_DATA
        move.b  #5,GP_VBL_INT+LN_PRI ; pri 5 : entre sched(20) et timer_vblank(0)/vbl_tail(-10) dans la chaîne VERTB
        move.l  #gp_vblank_server,GP_VBL_INT+IS_CODE
        moveq   #INTB_VERTB,d0
        lea     GP_VBL_INT,a1
        jsr     LVO_ADDINTSERVER(a6)
        rts

gp_inputname:
        dc.b    "input.device",0
        EVEN
gameport_end:
