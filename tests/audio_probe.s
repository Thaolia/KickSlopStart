; tests/audio_probe.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM).
; Sonde boîte noire « audio.device » (piste analyse, docs/analysis/audio-device-v34.md).
; Lancée depuis la startup-sequence d'une disquette (tests/audio_probe.sh). Appelle audio.device par OpenDevice/BeginIO
; et écrit chaque résultat sur le série direct (SERDAT), une ligne par test, en hexadécimal.
; Mesure du temps : trames (serveur VERTB) × 313 + ligne courante (une unité = une ligne, 64 µs).
; Assemblage : vasmm68k_mot -Fhunkexe -kick1hunks -nosym -o build/audio_probe tests/audio_probe.s
; Code auteur ; structures publiques (exec/io.h, devices/audio.h).

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
SERPER   EQU $DFF032
IO_DEV   EQU 20
IO_UNIT  EQU 24
IO_CMD   EQU 28
IO_FLG   EQU 30
IO_ERR   EQU 31
A_KEY    EQU 32
A_DATA   EQU 34
A_LEN    EQU 38
A_PER    EQU 42
A_VOL    EQU 44
A_CYC    EQU 46
LN_PRI   EQU 9
RSZ      EQU 80
NREQ     EQU 12
SLEN     EQU 1000
LIM      EQU 40000            ; garde de temps par attente (lignes, ≈ 2,5 s)

LR      macro
        lea     reqs-vars+(\1)*RSZ(a4),a1
        endm
PS      macro
        bsr     pstr
        dc.b    \1,0
        even
        endm

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     vars(pc),a4
                move.w  #372,SERPER
                move.l  4.w,a6
                move.l  #4096,d0
                move.l  #$10003,d1
                jsr     -198(a6)
                move.l  d0,chip-vars(a4)
                beq     .out
                move.l  d0,a5
                move.l  a5,a0
                move.w  #SLEN-1,d0
                moveq   #0,d1
.fill:          move.b  d1,(a0)+
                addq.b  #7,d1
                dbf     d0,.fill
; port
                moveq   #-1,d0
                jsr     -330(a6)
                lea     port-vars(a4),a2
                move.b  d0,15(a2)
                sub.l   a1,a1
                jsr     -294(a6)
                move.l  d0,16(a2)
                move.b  #4,8(a2)
                lea     20(a2),a0
                move.l  a0,8(a0)
                addq.l  #4,a0
                clr.l   (a0)
                move.l  a0,-(a0)
; requêtes
                lea     reqs-vars(a4),a0
                move.w  #NREQ-1,d0
.ri:            move.w  #RSZ/2-1,d1
                move.l  a0,a1
.rc:            clr.w   (a1)+
                dbf     d1,.rc
                move.l  a2,14(a0)
                move.w  #68,18(a0)
                lea     RSZ(a0),a0
                dbf     d0,.ri
                lea     vbint-vars(a4),a1
                move.b  #2,8(a1)
                lea     vbcnt-vars(a4),a0
                move.l  a0,14(a1)
                lea     vbsrv(pc),a0
                move.l  a0,18(a1)
                moveq   #5,d0
                jsr     -168(a6)
                PS      <10,"ADP debut",10>
                move.l  #LIM,d7

; ---------- T0 : Paula seule (sans audio.device), interruptions AUD0 masquées, scrutation d'INTREQR ----------
                PS      "T0"
                move.w  #$0080,$DFF09A
                move.w  #$0001,$DFF096
                move.w  #$0080,$DFF09C
                move.l  a5,$DFF0A0
                move.w  #SLEN/2,$DFF0A4
                move.w  #400,$DFF0A6
                move.w  #0,$DFF0A8
                bsr     now
                move.l  d0,t0-vars(a4)
                move.w  #$8201,$DFF096
                bsr     hwt
                bsr     sp1
                bsr     phex6
                move.w  #$0080,$DFF09C
                bsr     hwt
                bsr     sp1
                bsr     phex6
                move.w  #$0080,$DFF09C
                bsr     hwt
                bsr     sp1
                bsr     phex6
                move.w  #$0001,$DFF096
                move.w  #$0080,$DFF09C
                PS      " /"                    ; démarrage manuel : AUD0DAT avec PER=1 puis DMA
                move.w  #1,$DFF0A6
                bsr     now
                move.l  d0,t0-vars(a4)
                move.w  #$1234,$DFF0AA
                bsr     hwt
                bsr     sp1
                bsr     phex6
                move.w  #$0080,$DFF09C
                move.w  #$8201,$DFF096
                bsr     hwt
                bsr     sp1
                bsr     phex6
                move.w  #400,$DFF0A6
                move.w  #$0080,$DFF09C
                bsr     hwt
                bsr     sp1
                bsr     phex6
                move.w  #$0080,$DFF09C
                bsr     hwt
                bsr     sp1
                bsr     phex6
                move.w  #$0001,$DFF096
                move.w  #$0080,$DFF09C
                bsr     nl

; ---------- T1 : OpenDevice sans allocation (ioa_Length = 0) ----------
                PS      "T1"
                LR      0
                move.l  #$55,IO_UNIT(a1)
                bsr     opn
                bsr     nl

; ---------- T2 : OpenDevice avec allocation ----------
                PS      "T2a"
                LR      1
                lea     cmb1248-vars(a4),a0
                move.l  a0,A_DATA(a1)
                move.l  #4,A_LEN(a1)
                bsr     opn
                bsr     nl
                PS      "T2b"
                LR      2
                lea     cmb12-vars(a4),a0
                move.l  a0,A_DATA(a1)
                move.l  #2,A_LEN(a1)
                bsr     opn
                bsr     nl
                PS      "T2c"
                LR      3
                lea     cmb1-vars(a4),a0
                move.l  a0,A_DATA(a1)
                move.l  #1,A_LEN(a1)
                bsr     opn
                bsr     nl
                LR      1
                move.l  IO_DEV(a1),dev-vars(a4)
                move.w  A_KEY(a1),key1-vars(a4)

; ---------- T3 : préemption / choix de combinaison ----------
                PS      "T3a"                   ; pri 10 vole le canal 0 (pri 0)
                LR      4
                lea     cmb1-vars(a4),a0
                moveq   #1,d0
                moveq   #10,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                bsr     pkey
                bsr     nl
                PS      "T3b"                   ; ancien propriétaire écrit : NOALLOCATION
                LR      1
                moveq   #1,d0
                bsr     wset
                bsr     go
                bsr     fin
                bsr     nl
                PS      "T3c"                   ; pri 20, {3,C} : canaux libres préférés -> C
                LR      5
                lea     cmb3C-vars(a4),a0
                moveq   #2,d0
                moveq   #20,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                bsr     pkey
                bsr     nl
                PS      "T3d"                   ; pri 15, {1,2} : 1 = pri 10, 2 = pri 0 -> 2 (moindre dégât)
                LR      6
                lea     cmb12-vars(a4),a0
                moveq   #2,d0
                moveq   #15,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                bsr     pkey
                bsr     nl
                PS      "T3e"                   ; pri 15, {1} : pri 10 < 15 -> vol
                LR      7
                lea     cmb1-vars(a4),a0
                moveq   #1,d0
                moveq   #15,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                bsr     pkey
                bsr     nl
                PS      "T3f"                   ; pri 15, {2} : canal 1 à pri 15 (égal) -> échec
                LR      8
                lea     cmb2-vars(a4),a0
                moveq   #1,d0
                moveq   #15,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                bsr     pkey
                bsr     nl

; ---------- T4 : ADCMD_FREE ----------
                PS      "T4"
                LR      1                       ; tout volé : F6
                moveq   #9,d0
                moveq   #$F,d1
                bsr     cset
                bsr     go
                bsr     fin
                LR      4                       ; canal 0 volé par R7
                moveq   #9,d0
                moveq   #1,d1
                bsr     cset2
                bsr     go
                bsr     fin
                LR      7
                moveq   #9,d0
                moveq   #1,d1
                bsr     cset2
                bsr     go
                bsr     fin
                LR      6
                moveq   #9,d0
                moveq   #2,d1
                bsr     cset2
                bsr     go
                bsr     fin
                LR      5
                moveq   #9,d0
                moveq   #$C,d1
                bsr     cset2
                bsr     go
                bsr     fin
                LR      2
                moveq   #9,d0
                moveq   #2,d1
                bsr     cset2
                bsr     go
                bsr     fin
                bsr     nl

; ---------- T5 : ADKCON nettoyé par l'allocation ----------
                PS      "T5"
                move.w  #$80FF,$DFF09E
                bsr     regs
                LR      1
                lea     cmb1-vars(a4),a0
                moveq   #1,d0
                moveq   #0,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                bsr     regs
                LR      2
                lea     cmb4-vars(a4),a0
                moveq   #1,d0
                moveq   #0,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                bsr     regs
                move.w  #$00FF,$DFF09E
                LR      2
                moveq   #9,d0
                moveq   #4,d1
                bsr     cset2
                bsr     go
                bsr     fin
                bsr     nl
                LR      1
                move.w  A_KEY(a1),key1-vars(a4)

; ---------- T6 : CMD_WRITE, durée selon ioa_Cycles ----------
                PS      "T6"
                moveq   #1,d0
                bsr     t6one
                moveq   #2,d0
                bsr     t6one
                moveq   #4,d0
                bsr     t6one
                bsr     regs
                bsr     nl

; ---------- T7 : enchaînement A puis B, CMD_READ ----------
                PS      "T7"
                LR      9
                moveq   #1,d0
                bsr     wset
                bsr     go
                LR      10
                moveq   #1,d0
                bsr     wset
                bsr     bio
                move.l  #300,d0
                bsr     dly
                LR      6
                moveq   #2,d0
                moveq   #1,d1
                bsr     cset
                bsr     bio
                bsr     fin
                PS      " rd="
                move.l  A_DATA(a1),d0
                lea     reqs-vars+9*RSZ(a4),a0
                sub.l   a0,d0
                bsr     phex8
                LR      9
                bsr     fin
                LR      10
                bsr     fin
                LR      6
                moveq   #2,d0
                moveq   #1,d1
                bsr     cset
                bsr     bio
                bsr     fin
                PS      " rd="
                move.l  A_DATA(a1),d0
                bsr     phex8
                bsr     nl

; ---------- T8 : ADCMD_WAITCYCLE sur canal inactif (le cas « canal en lecture » est en T17, en dernier) ----------
                PS      "T8"
                LR      11
                moveq   #14,d0
                moveq   #1,d1
                bsr     cset
                bsr     go
                bsr     fin
                bsr     nl

; ---------- T9 : AbortIO ----------
                PS      "T9"
                LR      9
                moveq   #5,d0
                bsr     wset
                bsr     go
                LR      10
                moveq   #1,d0
                bsr     wset
                bsr     bio
                LR      11
                moveq   #1,d0
                bsr     wset
                bsr     bio
                move.l  #300,d0
                bsr     dly
                LR      11
                jsr     -480(a6)
                LR      11
                bsr     fin
                LR      9
                jsr     -480(a6)
                LR      9
                bsr     fin
                LR      10
                bsr     fin
                bsr     nl

; ---------- T10 : CMD_FLUSH ----------
                PS      "T10"
                LR      9
                moveq   #5,d0
                bsr     wset
                bsr     go
                LR      10
                moveq   #2,d0
                bsr     wset
                bsr     bio
                move.l  #300,d0
                bsr     dly
                LR      6
                moveq   #8,d0
                moveq   #1,d1
                bsr     cset
                bsr     bio
                bsr     fin
                LR      9
                bsr     fin
                LR      10
                bsr     fin
                bsr     nl

; ---------- T11 : ADCMD_FINISH (cycles infinis) ----------
                PS      "T11"
                LR      9
                moveq   #0,d0
                bsr     wset
                bsr     go
                move.l  #6000,d0
                bsr     dly
                bsr     pend
                bsr     regs
                LR      6
                moveq   #11,d0
                moveq   #1,d1
                bsr     cset
                move.b  #$20,IO_FLG(a1)
                bsr     bio
                bsr     fin
                LR      9
                bsr     fin
                PS      " /"
                LR      9
                moveq   #0,d0
                bsr     wset
                bsr     bio
                move.l  #3000,d0
                bsr     dly
                LR      6
                moveq   #11,d0
                moveq   #1,d1
                bsr     cset
                bsr     go
                bsr     fin
                LR      9
                bsr     fin
                bsr     regs
                bsr     nl

; ---------- T12 : CMD_STOP / CMD_START ----------
                PS      "T12"
                LR      9
                moveq   #2,d0
                bsr     wset
                bsr     go
                move.l  #500,d0
                bsr     dly
                LR      6
                moveq   #6,d0
                moveq   #1,d1
                bsr     cset
                bsr     bio
                bsr     regs
                move.l  #6000,d0
                bsr     dly
                LR      9
                bsr     pend
                LR      6
                moveq   #7,d0
                moveq   #1,d1
                bsr     cset
                bsr     bio
                bsr     regs
                LR      9
                bsr     fin
                PS      " /"
                LR      6                       ; STOP d'abord, puis WRITE sur canal arrêté
                moveq   #6,d0
                moveq   #1,d1
                bsr     cset
                bsr     bio
                LR      9
                moveq   #1,d0
                bsr     wset
                bsr     bio
                move.l  #3000,d0
                bsr     dly
                bsr     pend
                bsr     regs
                LR      6
                moveq   #7,d0
                moveq   #1,d1
                bsr     cset
                bsr     go
                LR      9
                bsr     fin
                bsr     nl

; ---------- T13 : ADCMD_LOCK et vol ----------
                PS      "T13"
                LR      2
                lea     cmb8-vars(a4),a0
                moveq   #1,d0
                moveq   #0,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                LR      8                       ; LOCK avec la clé de R2
                moveq   #13,d0
                moveq   #8,d1
                bsr     cset
                lea     reqs-vars+2*RSZ(a4),a0
                move.w  A_KEY(a0),A_KEY(a1)
                bsr     bio
                bsr     pend
                LR      4                       ; pri 50 NOWAIT sur canal verrouillé
                clr.w   A_KEY(a1)
                lea     cmb8-vars(a4),a0
                moveq   #1,d0
                moveq   #50,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     pend
                LR      8
                move.l  #2000,d7
                bsr     fin
                LR      4
                bsr     pend
                PS      " /"
                LR      2
                moveq   #9,d0
                moveq   #8,d1
                bsr     cset2
                bsr     go
                bsr     fin
                LR      4
                bsr     fin
                bsr     pkey
                PS      " /"
                LR      9                       ; LOCK par R4 puis FREE : LOCK rendu
                moveq   #13,d0
                moveq   #8,d1
                bsr     cset
                lea     reqs-vars+4*RSZ(a4),a0
                move.w  A_KEY(a0),A_KEY(a1)
                bsr     bio
                bsr     pend
                LR      4
                moveq   #9,d0
                moveq   #8,d1
                bsr     cset2
                bsr     go
                bsr     fin
                LR      9
                bsr     fin
                move.l  #LIM,d7
                bsr     nl

; ---------- T14 : file d'attente d'allocation, AbortIO, SETPREC ----------
                PS      "T14"
                LR      4
                lea     cmb8-vars(a4),a0
                moveq   #1,d0
                moveq   #50,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                LR      5
                clr.w   A_KEY(a1)
                lea     cmb8-vars(a4),a0
                moveq   #1,d0
                moveq   #0,d1
                moveq   #0,d2
                bsr     alloc
                bsr     go
                bsr     pend
                jsr     -480(a6)
                LR      5
                bsr     fin
                PS      " /"
                LR      5
                lea     cmb8-vars(a4),a0
                moveq   #1,d0
                moveq   #0,d1
                moveq   #0,d2
                bsr     alloc
                bsr     go
                bsr     pend
                LR      4                       ; SETPREC -100 : R5 (pri 0) obtient le canal
                moveq   #10,d0
                moveq   #8,d1
                bsr     cset2
                move.b  #-100,LN_PRI(a1)
                bsr     bio
                bsr     fin
                LR      5
                bsr     fin
                bsr     pkey
                LR      5
                moveq   #9,d0
                moveq   #8,d1
                bsr     cset2
                bsr     bio
                bsr     fin
                bsr     nl

; ---------- T15 : ALLOCATE ioa_Length = 0 ; commande inconnue avec io_Unit = 0 ----------
                PS      "T15"
                LR      6
                clr.w   A_KEY(a1)
                moveq   #0,d0
                moveq   #0,d1
                moveq   #0,d2
                bsr     alloc
                move.l  #$33,IO_UNIT(a1)
                bsr     go
                bsr     fin
                bsr     pkey
                LR      6
                moveq   #$1F,d0
                moveq   #0,d1
                bsr     cset
                bsr     go
                bsr     fin
                bsr     nl

; ---------- T16 : CloseDevice libère les canaux ----------
                PS      "T16"
                LR      1
                jsr     -450(a6)
                PS      " dev="
                LR      1
                move.l  IO_DEV(a1),d0
                bsr     phex8
                PS      " cmd="
                move.w  IO_CMD(a1),d0
                bsr     phex4
                LR      6
                clr.w   A_KEY(a1)
                lea     cmb1-vars(a4),a0
                moveq   #1,d0
                moveq   #-128,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                LR      6
                moveq   #9,d0
                moveq   #1,d1
                bsr     cset2
                bsr     bio
                LR      0
                jsr     -450(a6)
                LR      2
                jsr     -450(a6)
                bsr     regs
                bsr     nl

; ---------- T17 : ADCMD_WAITCYCLE pendant une lecture (dernier test : peut corrompre la mémoire) ----------
                PS      "T17"
                LR      1
                move.l  dev-vars(a4),IO_DEV(a1)
                clr.w   A_KEY(a1)
                lea     cmb1-vars(a4),a0
                moveq   #1,d0
                moveq   #0,d1
                moveq   #$40,d2
                bsr     alloc
                bsr     go
                bsr     fin
                LR      1
                move.w  A_KEY(a1),key1-vars(a4)
                LR      9
                moveq   #3,d0
                bsr     wset
                bsr     go
                move.l  #200,d0
                bsr     dly
                LR      11
                moveq   #14,d0
                moveq   #1,d1
                bsr     cset
                bsr     bio
                bsr     pend
                move.l  #8000,d7
                bsr     fin
                LR      9
                bsr     fin
                bsr     nl

                PS      "ADP fin"
                bsr     nl
                lea     vbint-vars(a4),a1
                moveq   #5,d0
                jsr     -174(a6)
                move.l  chip-vars(a4),a1
                move.l  #4096,d0
                jsr     -210(a6)
.out:           movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

; ---------- sous-programmes ----------
; opn : a1 = requête (ln_Pri = 0) ; OpenDevice ; affiche d0, err, unit, clé, flags, cmd, device
opn:            move.l  a1,-(sp)
                lea     devname-vars(a4),a0
                moveq   #0,d0
                moveq   #0,d1
                jsr     -444(a6)
                move.l  (sp)+,a1
                move.l  d0,-(sp)
                PS      " d0="
                move.l  (sp)+,d0
                bsr     phex8
                PS      " e="
                move.b  IO_ERR(a1),d0
                bsr     phex2
                PS      " u="
                move.l  IO_UNIT(a1),d0
                bsr     phex8
                bsr     pkey
                PS      " f="
                move.b  IO_FLG(a1),d0
                bsr     phex2
                PS      " c="
                move.w  IO_CMD(a1),d0
                bsr     phex4
                PS      " dv="
                move.l  IO_DEV(a1),d0
                bsr     phex8
                rts

; alloc : a1 = requête, a0 = combinaisons, d0 = longueur, d1 = pri, d2 = flags
alloc:          move.w  #32,IO_CMD(a1)
                move.l  a0,A_DATA(a1)
                move.l  d0,A_LEN(a1)
                move.b  d1,LN_PRI(a1)
                move.b  d2,IO_FLG(a1)
                move.l  dev-vars(a4),IO_DEV(a1)
                rts

; cset : a1 = requête, d0 = commande, d1 = io_Unit ; clé = key1 ; flags 0
cset:           move.w  key1-vars(a4),A_KEY(a1)
; cset2 : idem sans toucher la clé
cset2:          move.w  d0,IO_CMD(a1)
                move.l  d1,IO_UNIT(a1)
                clr.b   IO_FLG(a1)
                move.l  dev-vars(a4),IO_DEV(a1)
                rts

; wset : a1 = requête, d0 = cycles ; CMD_WRITE canal 0, ADIOF_PERVOL
wset:           move.w  #3,IO_CMD(a1)
                move.b  #$10,IO_FLG(a1)
                move.l  #1,IO_UNIT(a1)
                move.l  chip-vars(a4),A_DATA(a1)
                move.l  #SLEN,A_LEN(a1)
                move.w  #400,A_PER(a1)
                move.w  #64,A_VOL(a1)
                move.w  d0,A_CYC(a1)
                move.w  key1-vars(a4),A_KEY(a1)
                move.l  dev-vars(a4),IO_DEV(a1)
                rts

t6one:          move.l  d0,-(sp)
                PS      " c"
                move.l  (sp)+,d0
                move.l  d0,-(sp)
                bsr     phex2
                move.l  (sp)+,d0
                LR      9
                bsr     wset
                bsr     go
                move.l  #100,d0
                bsr     dly
                bsr     regs
                LR      9
                bra     fin

; go : t0 = maintenant puis BeginIO
go:             move.l  d0,-(sp)
                bsr     now
                move.l  d0,t0-vars(a4)
                move.l  (sp)+,d0
; bio : BeginIO(a1) sans toucher io_Flags
bio:            movem.l d0-d1/a0-a1/a6,-(sp)
                move.l  IO_DEV(a1),a6
                jsr     -30(a6)
                movem.l (sp)+,d0-d1/a0-a1/a6
                rts

; fin : a1 = requête ; attend sa fin (CheckIO) au plus d7 lignes depuis t0 ; affiche t, err, unit
fin:            movem.l d2/a2,-(sp)
                move.l  a1,a2
.l:             move.l  a2,a1
                jsr     -468(a6)
                tst.l   d0
                bne.s   .d
                bsr     now
                sub.l   t0-vars(a4),d0
                nop
                cmp.l   d7,d0
                bcs.s   .l
                PS      " TO"
                moveq   #-1,d2
                bra.s   .p
.d:             bsr     now
                sub.l   t0-vars(a4),d0
                nop
                move.l  d0,d2
                move.l  a2,a1
                jsr     -474(a6)
.p:             PS      " t="
                move.l  d2,d0
                bsr     phex6
                PS      " e="
                move.b  IO_ERR(a2),d0
                bsr     phex2
                PS      " u="
                move.l  IO_UNIT(a2),d0
                bsr     phex2
                move.l  a2,a1
                movem.l (sp)+,d2/a2
                rts

; pend : a1 = requête ; affiche p=1 si encore en cours
pend:           move.l  a1,-(sp)
                PS      " p="
                move.l  (sp),a1
                jsr     -468(a6)
                tst.l   d0
                seq     d0
                and.b   #1,d0
                bsr     phex2
                move.l  (sp)+,a1
                rts

pkey:           move.l  a1,-(sp)
                PS      " k="
                move.l  (sp),a1
                move.w  A_KEY(a1),d0
                bsr     phex4
                move.l  (sp)+,a1
                rts

regs:           move.l  a1,-(sp)
                PS      " dma="
                move.w  $DFF002,d0
                and.w   #$020F,d0
                bsr     phex4
                PS      " ie="
                move.w  $DFF01C,d0
                and.w   #$4780,d0
                bsr     phex4
                PS      " adk="
                move.w  $DFF010,d0
                bsr     phex2
                move.l  (sp)+,a1
                rts

; now : d0 = horloge en lignes = trames (serveur VERTB) * 313 + ligne courante ; lue sous Disable
now:            movem.l d1/a6,-(sp)
                move.l  4.w,a6
                jsr     -120(a6)
                move.l  $DFF004,d1
                lsr.l   #8,d1
                and.l   #$1FF,d1
                move.l  vbcnt-vars(a4),d0
                btst    #5,$DFF01F
                beq.s   .np
                cmp.w   #100,d1
                bcc.s   .np
                addq.l  #1,d0
.np:            mulu    #313,d0
                add.l   d1,d0
                move.l  d0,-(sp)
                jsr     -126(a6)
                move.l  (sp)+,d0
                movem.l (sp)+,d1/a6
                rts

vbsrv:          addq.l  #1,(a1)
                moveq   #0,d0
                rts

; hwt : attend que INTREQR bit 7 (AUD0) passe à 1, au plus 40000 lignes ; d0 = lignes écoulées depuis t0
hwt:            bsr     now
                sub.l   t0-vars(a4),d0
                nop
                cmp.l   #40000,d0
                bcc.s   .to
                btst    #7,$DFF01F
                beq.s   hwt
                rts
.to:            moveq   #-1,d0
                rts

; dly : attend d0 lignes
dly:            movem.l d2-d3,-(sp)
                move.l  d0,d3
                bsr     now
                move.l  d0,d2
.l:             bsr     now
                sub.l   d2,d0
                nop
                cmp.l   d3,d0
                bcs.s   .l
                movem.l (sp)+,d2-d3
                rts

pstr:           move.l  (sp)+,a0
.l:             move.b  (a0)+,d1
                beq.s   .e
                bsr.s   putc
                bra.s   .l
.e:             move.l  a0,d1
                addq.l  #1,d1
                and.b   #$FE,d1
                move.l  d1,a0
                jmp     (a0)

nl:             moveq   #10,d1
                bra     putc
sp1:            moveq   #' ',d1
                bra     putc
phex6:          swap    d0
                bsr.s   phex2
                swap    d0
                bra.s   phex4
phex8:          swap    d0
                bsr.s   phex4
                swap    d0
phex4:          move.w  d0,-(sp)
                lsr.w   #8,d0
                bsr.s   phex2
                move.w  (sp)+,d0
phex2:          move.w  d0,-(sp)
                lsr.b   #4,d0
                bsr.s   .n
                move.w  (sp)+,d0
.n:             move.w  d0,-(sp)
                and.w   #$F,d0
                move.b  hexd(pc,d0.w),d1
                bsr.s   putc
                move.w  (sp)+,d0
                rts
hexd:           dc.b    "0123456789ABCDEF"
putc:           move.w  d0,-(sp)
.w:             move.w  SERDATR,d0
                btst    #13,d0
                beq.s   .w
                and.w   #$FF,d1
                or.w    #$100,d1
                move.w  d1,SERDAT
                move.w  (sp)+,d0
                rts

devname:        dc.b    "audio.device",0
cmb1248:        dc.b    1,2,4,8
cmb12:          dc.b    1,2
cmb1:           dc.b    1
cmb2:           dc.b    2
cmb3C:          dc.b    3,$C
cmb4:           dc.b    4
cmb8:           dc.b    8
                even

vars:
chip:           dc.l    0
dev:            dc.l    0
t0:             dc.l    0
key1:           dc.w    0
                even
vbcnt:          dc.l    0
vbint:          ds.b    24
port:           ds.b    40
reqs:           ds.b    RSZ*NREQ
