; src/exec/strap.s — strap (romboot) : lit, valide et EXÉCUTE le bootblock de DF0: (jalon C « ça boote ! »).
; strap_boot(a6=SysBase) -> d0 = 0 si AUCUN volume bootable (l'appelant affiche l'écran insert-disk),
;                           d0 != 0 si le bootblock a été exécuté avec succès (un vrai boot ne reviendrait pas).
;
; Chaîne : FindName("trackdisk.device") -> CMD_READ(offset 0, len 1024 = secteurs 0+1 = bootblock, DANS la piste 0)
; via BeginIO -30 (pattern prouvé par M6w) -> valide magic « DOS » + checksum additif -> JSR au boot code à +12.
;
; Critère de bootabilité 1.3 (public, vérifié empiriquement sur un ADF formaté) : magic « DOS » ET checksum
; one's-complement (somme à retenue CIRCULAIRE des 256 longs == $FFFFFFFF). Un ADF formaté non installé a
; checksum=0 -> non bootable -> l'écran insert-disk apparaît PARCE QUE le bootblock de DF0: ne valide pas :
; c'est le VRAI déclencheur 1.3 (plus l'échafaudage « renvoie toujours 0 » de M6r).
;
; Déviations clean-room ASSUMÉES (jalon sans dos) :
;  - La vraie convention renvoie aussi A0 = adresse de handoff (dos) que le strap JMPerait ; ici on renvoie
;    seulement « bouté » sans suivre A0 (pas encore de dos.library — D/E/F).
;  - Un vrai bootblock ne revient pas (il prend la main) ; notre bootblock de test revient (D0=0) + on FreeMem.
;  - Mécanisme de boot interne propre (le vrai 1.3 n'expose pas `AddBootNode`, V36/2.0+) ; on reproduit le
;    COMPORTEMENT observable, pas l'interne du ROM.
; Piste IMPLÉMENTATION (« clean ») : AutoDocs exec + RKRM Devices (boot process) + devices/bootblock.i (public).
; AUCUNE lecture ROM.

                include "exec.i"

                xdef    strap_boot

; constantes IO non présentes dans exec.i (spécifiques lecture) — littéraux documentés (strap n'inclut pas disk.i)
CMD_READ       EQU 2
IOF_QUICK      EQU $01
IO_ACTUAL      EQU 32               ; octets réellement transférés
IO_LENGTH      EQU 36               ; octets demandés
IO_DATA        EQU 40               ; APTR buffer destination
IO_OFFSET      EQU 44               ; offset octet sur le disque
TD_LVO_BEGINIO EQU -30              ; vecteur device standard BeginIO
BB_SIZE        EQU 1024             ; bootblock = 2 secteurs de 512 o
BB_ENTRY       EQU 12               ; offset du boot code dans le bootblock (après magic/checksum/rootptr)
IOREQ_SIZE     EQU 48               ; IOStdReq

; STRAP_FAKE_BOOTDEV=1 (RED hérité M6r) : simule un boot réussi en tête -> ni insert-disk ni écran. Défaut 0.
STRAP_FAKE_BOOTDEV EQU 0
; STRAP_BAD_CSUM=1 (RED C) : INVERSE la décision du checksum -> un bootblock VALIDE est rejeté -> boot_c.adf
; n'est pas bouté -> « M6Y » + « CBOOT » absents, insert-disk à la place. Isole la VALIDATION (prouve que le
; chemin « accepte un bon bloc » n'est pas vide). Défaut 0.
STRAP_BAD_CSUM EQU 0
; STRAP_NO_EXEC=1 (RED C) : valide le bootblock mais SAUTE le JSR au boot code -> le marqueur « CBOOT » du
; bootblock est absent, mais le strap renvoie quand même « bouté » (M6Y présent). Isole l'EXÉCUTION. Défaut 0.
STRAP_NO_EXEC  EQU 0

strap_boot:
                ifne    STRAP_FAKE_BOOTDEV
        moveq   #1,d0                ; RED : prétend avoir bouté -> aucun insert-disk
        rts
                endc
        movem.l a2/a3,-(sp)          ; ne renvoie que d0 ; a2/a3 préservés (convention)
        lea     EB_DEVICELIST(a6),a0
        lea     strap_td_name(pc),a1
        jsr     LVO_FINDNAME(a6)
        tst.l   d0
        beq     .nb_nofree           ; pas de trackdisk.device -> non bootable
        move.l  d0,a2                ; a2 = trackdisk base
        move.l  #IOREQ_SIZE+BB_SIZE,d0
        move.l  #(MEMF_PUBLIC|MEMF_CLEAR),d1
        jsr     LVO_ALLOCMEM(a6)
        tst.l   d0
        beq     .nb_nofree           ; pas de RAM -> non bootable
        move.l  d0,a3                ; a3 = ioreq ; bootblock buffer = a3 + IOREQ_SIZE
        move.l  a2,IO_DEVICE(a3)
        move.w  #CMD_READ,IO_COMMAND(a3)
        move.l  #BB_SIZE,IO_LENGTH(a3)
        lea     IOREQ_SIZE(a3),a0
        move.l  a0,IO_DATA(a3)
        clr.l   IO_OFFSET(a3)        ; bootblock = secteurs 0+1 (offset 0, dans la piste 0)
        move.b  #IOF_QUICK,IO_FLAGS(a3)
        move.l  a6,-(sp)             ; BeginIO via -30 (a6 = trackdisk, a1 = ioreq)
        move.l  a2,a6
        move.l  a3,a1
        jsr     TD_LVO_BEGINIO(a6)
        move.l  (sp)+,a6             ; restaure a6 = SysBase
        tst.b   IO_ERROR(a3)
        bne     .reject              ; lecture KO (pas de disque dans DF0:) -> insert-disk
        cmp.l   #BB_SIZE,IO_ACTUAL(a3)
        bne     .reject
        ; --- validation : magic « DOS » + checksum additif ---
        lea     IOREQ_SIZE(a3),a2    ; a2 = bootblock (trackdisk base plus nécessaire)
        move.l  (a2),d0
        and.l   #$FFFFFF00,d0
        cmp.l   #$444F5300,d0        ; « DOS » (octet flag ignoré)
        bne     .reject
        ; checksum one's-complement : somme à retenue CIRCULAIRE des 256 longs == $FFFFFFFF (ADD, PAS XOR :
        ; le checksum bootblock est ADDITIF, contrairement aux checksums MFM par-secteur de td_decode_track)
        move.l  a2,a0
        moveq   #0,d0
        move.w  #256-1,d1
.cs:
        add.l   (a0)+,d0
        bcc.s   .cs_nc
        addq.l  #1,d0                ; retenue circulaire (end-around carry)
.cs_nc:
        dbra    d1,.cs
        addq.l  #1,d0                ; $FFFFFFFF+1 -> 0 (Z) ssi checksum valide
                ifeq    STRAP_BAD_CSUM
        bne     .reject              ; checksum invalide -> non bootable (disque présent mais pas installé)
                endc
                ifne    STRAP_BAD_CSUM
        beq     .reject              ; RED STRAP_BAD_CSUM : rejette un bloc VALIDE -> isole la validation
                endc
        ; --- bootblock valide -> exécuter le boot code à +BB_ENTRY ---
                ifeq    STRAP_NO_EXEC
        move.l  a3,-(sp)             ; protège l'ioreq (un boot code quelconque peut clobber a3)
        lea     BB_ENTRY(a2),a0
        move.l  a3,a1                ; A1 = ioreq réutilisable ; A6 = SysBase (convention bootblock)
        jsr     (a0)                 ; D0 = retour du bootblock (0 = succès) ; A0 (handoff dos) IGNORÉ en C
        move.l  (sp)+,a3
        move.l  ($4).w,a6            ; recharge SysBase (le bootblock a pu clobber a6)
        tst.l   d0
        bne.s   .boot_failed         ; le boot code a signalé une erreur -> insert-disk
                endc                 ; RED STRAP_NO_EXEC : saute le JSR -> « CBOOT » absent, mais « bouté »
        bsr.s   .free
        moveq   #1,d0                ; bouté -> l'appelant NE montre PAS l'insert-disk
        bra.s   .ret
.boot_failed:
        bsr.s   .free
        moveq   #0,d0
        bra.s   .ret
.reject:
        bsr.s   .free                ; disque présent mais non bootable -> libère puis insert-disk
        moveq   #0,d0
        bra.s   .ret
.nb_nofree:
        moveq   #0,d0                ; rien alloué -> rien à libérer
.ret:
        movem.l (sp)+,a2/a3
        rts
.free:
        move.l  a3,a1
        move.l  #IOREQ_SIZE+BB_SIZE,d0
        jsr     LVO_FREEMEM(a6)      ; a6 = SysBase sur tous les chemins qui arrivent ici
        rts

strap_td_name:
        dc.b    "trackdisk.device",0
        even
