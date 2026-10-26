; tests/timerprobe.s — exécutable HUNK de test (ASSET DE TEST, PAS du code ROM) : sonde boîte noire de
; timer.device et du partage des CIA. Lancer « timerprobe >SER: » (ou sur la console) ; une ligne par mesure. Assembler avec -kick1hunks (HUNK_RELOC32 :
; la 1.3 refuse HUNK_RELOC32SHORT, « file is not an object module »).
; Vecteurs attendus (vraie ROM 34.5) : docs/analysis/timer-v34.md.
; Mesure du temps : compteur de trames d'un serveur VERTB de la sonde + ligne verticale (VPOSR/VHPOSR) ;
; « F » = trames écoulées, « L » = différence de ligne (signée) ; durée ≈ F × 313 + L lignes de 64 µs (PAL).
; Clean-room : structures publiques (timerequest, Interrupt, IntVector, ExecBase), code auteur.

EB_INTVECTS     EQU $54
TR_SIZE         EQU 40

                section code,code
_start:
                movem.l d2-d7/a2-a6,-(sp)
                lea     line(pc),a4
                move.l  4.w,a6
                lea     dosname(pc),a1
                moveq   #0,d0
                jsr     -552(a6)             ; OpenLibrary
                lea     dosbase(pc),a0
                move.l  d0,(a0)
                beq     .ret
                ; port de réponse
                moveq   #-1,d0
                jsr     -330(a6)             ; AllocSignal
                lea     port(pc),a2
                move.b  #4,8(a2)             ; NT_MSGPORT
                clr.b   14(a2)               ; PA_SIGNAL
                move.b  d0,15(a2)
                suba.l  a1,a1
                jsr     -294(a6)             ; FindTask(0)
                move.l  d0,16(a2)
                lea     20(a2),a0
                move.l  a0,28(a2)
                addq.l  #4,a0
                clr.l   (a0)
                move.l  a0,-4(a0)
                ; serveur VERTB de mesure
                lea     vbint(pc),a1
                move.b  #2,8(a1)
                move.b  #-100,9(a1)
                lea     vbname(pc),a0
                move.l  a0,10(a1)
                lea     vbcnt(pc),a0
                move.l  a0,14(a1)
                lea     vbcode(pc),a0
                move.l  a0,18(a1)
                moveq   #5,d0
                jsr     -168(a6)             ; AddIntServer(INTB_VERTB)

                bsr     t_exec
                bsr     t_cia
                bsr     t_icr
                bsr     t_vec
                bsr     t_open
                tst.l   d0
                bne     .rem
                bsr     t_cmd
                bsr     t_times
                bsr     t_delays
                bsr     t_preempt
                bsr     t_gst
                bsr     t_hj6
                bsr     t_hj2
                bsr     t_delays2
                lea     t_end(pc),a0
                bsr     ps
                bsr     nl
.rem:
                move.l  4.w,a6
                lea     vbint(pc),a1
                moveq   #5,d0
                jsr     -174(a6)             ; RemIntServer
.ret:
                movem.l (sp)+,d2-d7/a2-a6
                moveq   #0,d0
                rts

vbcode:                                      ; serveur VERTB : a1 = &vbcnt
                addq.l  #1,(a1)
                moveq   #0,d0
                rts

; ---------------------------------------------------------------- horodatage
; now : d0 = trames, d1 = ligne verticale (0..312), relu jusqu'à cohérence
now:
                move.l  vbcnt(pc),d0
                move.l  $dff004,d1
                lsr.l   #8,d1
                and.l   #$1ff,d1
                cmp.l   vbcnt(pc),d0
                bne.s   now
                rts
; stamp a0 : mémorise now en (a0)
stamp:
                move.l  a0,-(sp)
                bsr.s   now
                move.l  (sp)+,a0
                movem.l d0-d1,(a0)
                rts
; since a0 : d0 = trames, d1 = lignes depuis le stamp (a0)
since:
                move.l  a0,-(sp)
                bsr.s   now
                move.l  (sp)+,a0
                sub.l   (a0),d0
                sub.l   4(a0),d1
                rts

; ---------------------------------------------------------------- ExecBase
t_exec:
                lea     s_exec(pc),a0
                bsr     ps
                move.l  4.w,a6
                moveq   #0,d0
                move.b  $212(a6),d0          ; VBlankFrequency
                bsr     ph
                moveq   #0,d0
                move.b  $213(a6),d0          ; PowerSupplyFrequency
                bsr     ph
                moveq   #0,d0
                move.w  $120(a6),d0          ; Quantum
                bsr     ph
                moveq   #0,d0
                move.w  $122(a6),d0          ; Elapsed
                bsr     ph
                moveq   #0,d0
                move.w  $124(a6),d0          ; SysFlags
                bsr     ph
                ; calibration : ligne verticale maximale vue pendant 2 trames complètes
                move.l  vbcnt(pc),d2         ; (attentes « au moins » : une tâche de même priorité peut garder le
                addq.l  #1,d2                ; processeur plusieurs trames, une égalité exacte serait ratée)
.w1:
                cmp.l   vbcnt(pc),d2
                bhi.s   .w1
                move.l  vbcnt(pc),d2
                addq.l  #2,d2
                moveq   #0,d3
.w2:
                bsr     now
                cmp.l   d3,d1
                bls.s   .w3
                move.l  d1,d3
.w3:
                cmp.l   d0,d2
                bhi.s   .w2
                move.l  d3,d0
                bsr     ph
                bra     nl

; ---------------------------------------------------------------- registres CIA
t_cia:
                lea     s_ciaa(pc),a0
                bsr     ps
                lea     $bfe001,a2
                bsr     ciaregs
                bsr     nl
                lea     s_ciab(pc),a0
                bsr     ps
                lea     $bfd000,a2
                bsr     ciaregs
                bra     nl
ciaregs:                                     ; CRA CRB TALO TAHI TBLO TBHI TOD(h,m,l) — pas l'ICR (lecture destructive)
                moveq   #0,d0
                move.b  $e00(a2),d0
                lsl.w   #8,d0
                move.b  $f00(a2),d0
                bsr     ph
                moveq   #0,d0
                move.b  $500(a2),d0
                lsl.w   #8,d0
                move.b  $400(a2),d0
                bsr     ph
                moveq   #0,d0
                move.b  $700(a2),d0
                lsl.w   #8,d0
                move.b  $600(a2),d0
                bsr     ph
                moveq   #0,d0
                move.b  $a00(a2),d0
                lsl.l   #8,d0
                move.b  $900(a2),d0
                lsl.l   #8,d0
                move.b  $800(a2),d0
                bra     ph

; ---------------------------------------------------------------- propriétaires ICR
; Pour chaque CIA : masque autorisé (AbleICR(0)), puis pour chaque bit 0..4 :
; AddICRVector d'une Interrupt factice ; 0 = libre (aussitôt RemICRVector), sinon nom du propriétaire.
t_icr:
                lea     ciaaname(pc),a1
                lea     s_icra(pc),a3
                bsr.s   icr1
                lea     ciabname(pc),a1
                lea     s_icrb(pc),a3
icr1:
                move.l  4.w,a6
                jsr     -498(a6)             ; OpenResource
                move.l  d0,d7
                beq     .x
                move.l  a3,a0
                bsr     ps
                move.l  d7,d0
                bsr     ph
                move.l  d7,a6
                moveq   #0,d0
                jsr     -18(a6)              ; AbleICR(0) = masque courant
                bsr     ph
                moveq   #0,d6
.bit:
                move.l  4.w,a6
                jsr     -120(a6)             ; Disable
                move.l  d7,a6
                lea     dumint(pc),a1
                move.l  d6,d0
                jsr     -6(a6)               ; AddICRVector
                move.l  d0,d5
                bne.s   .own
                lea     dumint(pc),a1
                move.l  d6,d0
                jsr     -12(a6)              ; RemICRVector
.own:
                move.l  4.w,a6
                jsr     -126(a6)             ; Enable
                move.l  d6,d0
                add.b   #'0',d0
                move.b  d0,(a4)+
                move.b  #'=',(a4)+
                tst.l   d5
                bne.s   .nm
                move.b  #'-',(a4)+
                bra.s   .nx
.nm:
                move.l  d5,a0
                move.l  10(a0),d0
                beq.s   .nx
                move.l  d0,a0
                bsr     ps
                move.b  #'/',(a4)+
                move.l  d5,a0
                move.l  18(a0),d0            ; is_Code (repère)
                bsr     ph
.nx:
                move.b  #' ',(a4)+
                addq.l  #1,d6
                cmp.w   #5,d6
                bne     .bit
                bsr     nl
.x:
                rts

; ---------------------------------------------------------------- vecteurs d'interruption + chaînes de serveurs
t_vec:
                move.l  4.w,a6
                moveq   #0,d6
.v:
                lea     s_iv(pc),a0
                bsr     ps
                move.l  d6,d0
                bsr     ph
                move.l  d6,d0
                mulu    #12,d0
                lea     EB_INTVECTS(a6,d0.w),a2
                move.l  (a2),d0
                bsr     ph
                move.l  4(a2),d0
                bsr     ph
                move.l  8(a2),d0
                move.l  d0,d5
                bsr     ph
                tst.l   d5
                beq.s   .nn
                move.l  d5,a0
                move.l  10(a0),d0
                beq.s   .nn
                move.l  d0,a0
                bsr     ps
.nn:
                bsr     nl
                ; chaînes de serveurs : 3 PORTS, 4 COPER, 5 VERTB, 13 EXTER
                cmp.w   #3,d6
                beq.s   .srv
                cmp.w   #4,d6
                beq.s   .srv
                cmp.w   #5,d6
                beq.s   .srv
                cmp.w   #13,d6
                bne.s   .nx
.srv:
                move.l  (a2),d0              ; iv_Data = liste des serveurs
                beq.s   .nx
                move.l  d0,a3
                move.l  (a3),a3
.sl:
                tst.l   (a3)
                beq.s   .nx
                lea     s_srv(pc),a0
                bsr     ps
                move.b  9(a3),d0
                ext.w   d0
                ext.l   d0
                bsr     ph
                move.l  14(a3),d0
                bsr     ph
                move.l  18(a3),d0
                bsr     ph
                move.l  10(a3),d0
                beq.s   .sn
                move.l  d0,a0
                bsr     ps
.sn:
                bsr     nl
                move.l  (a3),a3
                bra.s   .sl
.nx:
                addq.l  #1,d6
                cmp.w   #14,d6
                bne     .v
                rts

; ---------------------------------------------------------------- ouvertures
; rq0, rqa, rqb : unité 0 (MICROHZ) ; rq1, rqt : unité 1 (VBLANK) ; rqx : unité 2 (doit échouer)
t_open:
                lea     rq0(pc),a1
                moveq   #0,d0
                bsr     opn
                bne     .f
                lea     rqa(pc),a1
                moveq   #0,d0
                bsr     opn
                bne     .f
                lea     rqb(pc),a1
                moveq   #0,d0
                bsr     opn
                bne     .f
                lea     rq1(pc),a1
                moveq   #1,d0
                bsr     opn
                bne     .f
                lea     rqt(pc),a1
                moveq   #1,d0
                bsr     opn
                bne     .f
                lea     s_open(pc),a0
                bsr     ps
                lea     rq0(pc),a1
                move.l  20(a1),d0            ; io_Device
                bsr     ph
                move.l  24(a1),d0            ; io_Unit
                lea     rq0(pc),a1
                sub.l   20(a1),d0
                bsr     ph
                lea     rq1(pc),a1
                move.l  24(a1),d0
                sub.l   20(a1),d0
                bsr     ph
                move.l  20(a1),a0
                moveq   #0,d0
                move.w  32(a0),d0            ; lib_OpenCnt
                bsr     ph
                moveq   #0,d0
                move.w  20(a0),d0            ; lib_Version
                swap    d0
                move.w  22(a0),d0            ; lib_Revision
                bsr     ph
                ; unité 2
                lea     rqx(pc),a1
                moveq   #2,d0
                bsr     opn
                bsr     ph                   ; d0 rendu par OpenDevice
                lea     rqx(pc),a1
                move.b  31(a1),d0
                ext.w   d0
                ext.l   d0
                bsr     ph
                move.l  20(a1),d0
                bsr     ph
                move.l  24(a1),d0
                bsr     ph
                bsr     nl
                moveq   #0,d0
                rts
.f:
                lea     s_ofail(pc),a0
                bsr     ps
                bsr     nl
                moveq   #-1,d0
                rts
opn:                                         ; a1 = timerequest, d0 = unité → d0 = OpenDevice, CCR sur d0
                move.l  a1,-(sp)
                lea     port(pc),a0
                move.l  a0,14(a1)            ; mn_ReplyPort
                move.w  #TR_SIZE,18(a1)
                move.b  #5,8(a1)
                lea     tdname(pc),a0
                moveq   #0,d1
                move.l  4.w,a6
                jsr     -444(a6)             ; OpenDevice
                move.l  (sp)+,a1
                tst.l   d0
                rts

; ---------------------------------------------------------------- commandes invalides, AbortIO hors file
t_cmd:
                lea     s_cmd(pc),a0
                bsr     ps
                moveq   #2,d2                ; CMD_READ
                bsr.s   cmdx
                moveq   #12,d2               ; hors table
                bsr.s   cmdx
                moveq   #0,d2                ; CMD_INVALID
                bsr.s   cmdx
                ; AbortIO d'une requête non en file
                lea     rq0(pc),a1
                move.l  4.w,a6
                jsr     -480(a6)             ; AbortIO
                bsr     ph
                lea     rq0(pc),a1
                move.b  31(a1),d0
                ext.w   d0
                ext.l   d0
                bsr     ph
                bra     nl
cmdx:
                lea     rq0(pc),a1
                move.w  d2,28(a1)
                clr.b   30(a1)
                move.l  4.w,a6
                jsr     -456(a6)             ; DoIO
                bsr     ph                   ; d0 rendu par DoIO
                lea     rq0(pc),a1
                moveq   #0,d0
                move.b  8(a1),d0             ; ln_Type après réponse
                lsl.w   #8,d0
                move.b  31(a1),d0
                bsr     ph
                rts

; ---------------------------------------------------------------- AddTime / SubTime / CmpTime
t_times:
                lea     s_tim(pc),a0
                bsr     ps
                lea     rq0(pc),a1
                move.l  20(a1),a6            ; base timer.device
                ; AddTime {0,999999}+{0,2}
                lea     tv1(pc),a0
                move.l  #0,(a0)
                move.l  #999999,4(a0)
                lea     tv2(pc),a1
                move.l  #0,(a1)
                move.l  #2,4(a1)
                jsr     -42(a6)
                bsr     ptv1
                ; AddTime {0,3000000}+{0,0}
                lea     tv1(pc),a0
                clr.l   (a0)
                move.l  #3000000,4(a0)
                lea     tv2(pc),a1
                clr.l   (a1)
                clr.l   4(a1)
                jsr     -42(a6)
                bsr     ptv1
                ; AddTime {5,-3}+{0,0} (micro négatif)
                lea     tv1(pc),a0
                move.l  #5,(a0)
                move.l  #-3,4(a0)
                lea     tv2(pc),a1
                clr.l   (a1)
                clr.l   4(a1)
                jsr     -42(a6)
                bsr     ptv1
                ; SubTime {1,0}-{0,1}
                lea     tv1(pc),a0
                move.l  #1,(a0)
                clr.l   4(a0)
                lea     tv2(pc),a1
                clr.l   (a1)
                move.l  #1,4(a1)
                jsr     -48(a6)
                bsr     ptv1
                ; SubTime {0,0}-{0,3000000}
                lea     tv1(pc),a0
                clr.l   (a0)
                clr.l   4(a0)
                lea     tv2(pc),a1
                clr.l   (a1)
                move.l  #3000000,4(a1)
                jsr     -48(a6)
                bsr     ptv1
                ; SubTime {0,5000000}-{0,0} (micro > 1e6 non normalisé ?)
                lea     tv1(pc),a0
                clr.l   (a0)
                move.l  #5000000,4(a0)
                lea     tv2(pc),a1
                clr.l   (a1)
                clr.l   4(a1)
                jsr     -48(a6)
                bsr     ptv1
                bsr     nl
                lea     s_cmp(pc),a0
                bsr     ps
                ; CmpTime(a0={2,0}, a1={1,5}) ; ({1,5},{2,0}) ; égal ; ({0,1},{0,2}) ; secs « négatives »
                lea     cmpv(pc),a2
                moveq   #5-1,d7
.c:
                move.l  a2,a0
                lea     8(a2),a1
                jsr     -54(a6)
                bsr     ph
                lea     16(a2),a2
                dbra    d7,.c
                bra     nl
ptv1:
                movem.l tv1(pc),d0-d1
                move.l  d1,-(sp)
                bsr     ph
                move.l  (sp)+,d0
                bra     ph

; ---------------------------------------------------------------- délais (mesurés, avec garde-fou VBLANK)
; dly : a1 = requête (déjà ouverte), d0 = secs, d1 = micro → imprime « F L err » ou « TMO err »
dly:
                movem.l d2-d4/a2,-(sp)
                move.l  a1,a2
                move.w  #9,28(a2)            ; TR_ADDREQUEST
                clr.b   30(a2)
                movem.l d0-d1,32(a2)
                lea     rqt(pc),a1           ; garde-fou : VBLANK 3 s
                move.w  #9,28(a1)
                clr.b   30(a1)
                move.l  #3,32(a1)
                clr.l   36(a1)
                move.l  4.w,a6
                lea     t0(pc),a0
                bsr     stamp
                move.l  a2,a1
                jsr     -462(a6)             ; SendIO
                lea     rqt(pc),a1
                jsr     -462(a6)
                lea     port(pc),a0
                jsr     -384(a6)             ; WaitPort
                lea     t0(pc),a0
                bsr     since
                movem.l d0-d1,-(sp)
                lea     port(pc),a0
                jsr     -372(a6)             ; GetMsg
                cmp.l   a2,d0
                bne.s   .tmo
                lea     rqt(pc),a1
                jsr     -480(a6)             ; AbortIO
                lea     rqt(pc),a1
                jsr     -474(a6)             ; WaitIO
                movem.l (sp)+,d0-d1
                move.l  d1,-(sp)
                bsr     ph
                move.l  (sp)+,d0
                bsr     ph
                bra.s   .e
.tmo:
                addq.l  #8,sp
                lea     s_tmo(pc),a0
                bsr     ps
                move.l  a2,a1
                jsr     -480(a6)
                move.l  a2,a1
                jsr     -474(a6)
.e:
                move.b  31(a2),d0
                ext.w   d0
                ext.l   d0
                bsr     ph
                move.b  #'t',(a4)+           ; timeval rendu dans la requête
                move.b  #'v',(a4)+
                move.b  #' ',(a4)+
                move.l  32(a2),d0
                bsr     ph
                move.l  36(a2),d0
                bsr     ph
                movem.l (sp)+,d2-d4/a2
                rts

t_delays:
                lea     mzvals(pc),a3
                lea     s_mz(pc),a5
                lea     rq0(pc),a2
                bsr.s   dlist
                lea     vbvals(pc),a3
                lea     s_vb(pc),a5
                lea     rq1(pc),a2
dlist:                                       ; a3 = table (secs, micro) terminée par -1, a5 = étiquette
.l:
                move.l  (a3),d0
                cmp.l   #-1,d0
                beq.s   .x
                move.l  a5,a0
                bsr     ps
                move.l  (a3),d0
                bsr     ph
                move.l  4(a3),d0
                bsr     ph
                movem.l (a3)+,d0-d1
                move.l  a2,a1
                bsr     dly
                bsr     nl
                bra.s   .l
.x:
                rts

; ---------------------------------------------------------------- préemption / insertion derrière la tête
; PREa : A = 1 s, puis B = 0,5 s posée ~3 trames plus tard (B < reste de A → B en tête)
; PREb : A = 0,2 s, puis B = 0,4 s posée ~3 trames plus tard (B >= A → B derrière A)
; Imprime : F,L de la pose de B ; puis pour chaque réponse dans l'ordre : 'A'/'B' F L (depuis la pose de A)
t_preempt:
                lea     s_prea(pc),a0
                move.l  #1,d2
                moveq   #0,d3
                moveq   #0,d4
                move.l  #500000,d5
                bsr.s   pre
                lea     s_preb(pc),a0
                moveq   #0,d2
                move.l  #200000,d3
                moveq   #0,d4
                move.l  #400000,d5
                bsr.s   pre
                lea     s_prec(pc),a0        ; PREc : idem PREa sur l'unité VBLANK
                move.l  #1,d2
                moveq   #0,d3
                moveq   #0,d4
                move.l  #500000,d5
                lea     rq1(pc),a2
                lea     rqt(pc),a3
                bra.s   pre2
pre:
                lea     rqa(pc),a2
                lea     rqb(pc),a3
pre2:                                        ; a2 = A, a3 = B, d2/d3 = A, d4/d5 = B
                bsr     ps
                move.l  4.w,a6
                move.w  #9,28(a2)
                clr.b   30(a2)
                movem.l d2-d3,32(a2)
                move.w  #9,28(a3)
                clr.b   30(a3)
                movem.l d4-d5,32(a3)
                lea     t0(pc),a0
                bsr     stamp
                move.l  a2,a1
                jsr     -462(a6)             ; SendIO A
                move.l  vbcnt(pc),d0
                addq.l  #3,d0
.w:
                cmp.l   vbcnt(pc),d0         ; attente active de 3 trames (pas de timer pendant ce temps)
                bhi.s   .w
                move.l  $dff004,d0           ; décaler dans la trame
                lsr.l   #8,d0
                and.l   #$1ff,d0
                cmp.w   #150,d0
                bcs.s   .w
                lea     t0(pc),a0
                bsr     since
                movem.l d0-d1,-(sp)
                move.l  a3,a1
                jsr     -462(a6)             ; SendIO B
                movem.l (sp)+,d0-d1
                move.l  d1,-(sp)
                bsr     ph
                move.l  (sp)+,d0
                bsr     ph
                moveq   #2-1,d7
.r:
                lea     port(pc),a0
                jsr     -384(a6)
                lea     t0(pc),a0
                bsr     since
                movem.l d0-d1,-(sp)
                lea     port(pc),a0
                jsr     -372(a6)
                moveq   #'A',d1
                cmp.l   a2,d0
                beq.s   .n
                moveq   #'B',d1
.n:
                move.b  d1,(a4)+
                move.b  #' ',(a4)+
                movem.l (sp)+,d0-d1
                move.l  d1,-(sp)
                bsr     ph
                move.l  (sp)+,d0
                bsr     ph
                dbra    d7,.r
                bra     nl

; ---------------------------------------------------------------- horloge système
t_gst:
                lea     s_gst(pc),a0
                bsr     ps
                moveq   #4-1,d7
.g:
                bsr     gst
                dbra    d7,.g
                bsr     nl
                ; TR_SETSYSTIME {1000, 500000} puis 3 lectures, puis une lecture après 0,5 s
                lea     s_sst(pc),a0
                bsr     ps
                lea     rq0(pc),a1
                move.w  #11,28(a1)
                clr.b   30(a1)
                move.l  #1000,32(a1)
                move.l  #500000,36(a1)
                move.l  4.w,a6
                jsr     -456(a6)
                lea     rq0(pc),a1
                move.b  31(a1),d0
                ext.w   d0
                ext.l   d0
                bsr     ph
                moveq   #3-1,d7
.s:
                bsr     gst
                dbra    d7,.s
                lea     rq0(pc),a1
                moveq   #0,d0
                move.l  #500000,d1
                bsr     dly
                bsr     gst
                bra     nl
gst:                                         ; GETSYSTIME sur l'unité VBLANK (rq1), imprime secs micro
                lea     rq1(pc),a1
                move.w  #10,28(a1)
                clr.b   30(a1)
                move.l  4.w,a6
                jsr     -456(a6)
                lea     rq1(pc),a1
                move.l  32(a1),d0
                bsr     ph
                lea     rq1(pc),a1
                move.l  36(a1),d0
                bra     ph

; ---------------------------------------------------------------- détournement du vecteur $78 (niveau 6), façon jeu
; Le gestionnaire de la sonde lit l'ICR de CIA-B, acquitte EXTER, compte, RTE — sans chaîner.
; Pendant ce temps CIA-B timer B tourne en continu (latch $2E2E, ICR $82), comme la musique de Monkey Island.
t_hj6:
                lea     s_hj6(pc),a0
                bsr     ps
                move.l  4.w,a6
                lea     h6cnt(pc),a0
                clr.l   (a0)
                jsr     -120(a6)             ; Disable
                lea     save78(pc),a0
                move.l  $78.w,(a0)
                lea     h6(pc),a0
                move.l  a0,$78.w
                move.b  #$2e,$bfd600
                move.b  #$2e,$bfd700
                move.b  $bfdf00,d0           ; garder le bit ALARM posé par graphics
                and.b   #$80,d0
                or.b    #$11,d0              ; START | LOAD, continu
                move.b  d0,$bfdf00
                move.b  #$82,$bfdd00         ; autorise TB
                move.w  #$a000,$dff09a       ; INTENA EXTER
                jsr     -126(a6)             ; Enable
                lea     rq0(pc),a1
                moveq   #0,d0
                move.l  #500000,d1
                bsr     dly                  ; MICROHZ 0,5 s
                lea     rq1(pc),a1
                moveq   #0,d0
                move.l  #500000,d1
                bsr     dly                  ; VBLANK 0,5 s
                move.l  h6cnt(pc),d0
                bsr     ph
                move.l  4.w,a6
                jsr     -120(a6)
                move.b  #$02,$bfdd00         ; interdit TB
                move.b  $bfdf00,d0
                and.b   #$80,d0              ; arrêt (ALARM conservé)
                move.b  d0,$bfdf00
                tst.b   $bfdd00
                move.w  #$2000,$dff09c
                move.l  save78(pc),$78.w
                jsr     -126(a6)
                bra     nl
h6:
                tst.b   $bfdd00
                move.w  #$2000,$dff09c
                move.l  a0,-(sp)
                lea     h6cnt(pc),a0
                addq.l  #1,(a0)
                move.l  (sp)+,a0
                rte

; ---------------------------------------------------------------- contrôle négatif : détournement du vecteur $68 (niveau 2)
; MICROHZ 0,1 s avec garde-fou VBLANK : attendu TMO (timer B de CIA-A servi par ciaa.resource au niveau 2).
; Puis rétablissement, AbortIO déjà fait par dly, et nouvelle requête MICROHZ pour vérifier que l'unité repart.
t_hj2:
                lea     s_hj2(pc),a0
                bsr     ps
                move.l  4.w,a6
                lea     h2cnt(pc),a0
                clr.l   (a0)
                jsr     -120(a6)
                lea     save68(pc),a0
                move.l  $68.w,(a0)
                lea     h2(pc),a0
                move.l  a0,$68.w
                jsr     -126(a6)
                lea     rq0(pc),a1
                moveq   #0,d0
                move.l  #100000,d1
                bsr     dly
                move.l  h2cnt(pc),d0
                bsr     ph
                move.l  4.w,a6
                jsr     -120(a6)
                move.l  save68(pc),$68.w
                jsr     -126(a6)
                lea     rq0(pc),a1
                moveq   #0,d0
                move.l  #100000,d1
                bsr     dly
                bra     nl
h2:
                tst.b   $bfed01
                move.w  #$0008,$dff09c
                move.l  a0,-(sp)
                lea     h2cnt(pc),a0
                addq.l  #1,(a0)
                move.l  (sp)+,a0
                rte

; ---------------------------------------------------------------- délais bornés et valeurs nulles (en dernier : peuvent rester bloqués)
t_delays2:
                lea     mz2vals(pc),a3
                lea     s_mz2(pc),a5
                lea     rq0(pc),a2
                bra     dlist

; ---------------------------------------------------------------- sortie
ps:                                          ; copie la chaîne a0 en (a4)+
                move.b  (a0)+,(a4)+
                bne.s   ps
                subq.l  #1,a4
                rts
ph:                                          ; d0 en 8 chiffres + espace
                movem.l d1/d3,-(sp)
                moveq   #7,d3
.h:
                rol.l   #4,d0
                move.b  d0,d1
                and.b   #15,d1
                add.b   #'0',d1
                cmp.b   #'9',d1
                bls.s   .d
                addq.b  #7,d1
.d:
                move.b  d1,(a4)+
                dbra    d3,.h
                move.b  #' ',(a4)+
                movem.l (sp)+,d1/d3
                rts
nl:                                          ; termine la ligne et l'écrit sur Output()
                movem.l d0-d3/a0-a1/a6,-(sp)
                move.b  #10,(a4)+
                lea     line(pc),a0
                move.l  a4,d3
                sub.l   a0,d3
                move.l  a0,d2
                move.l  dosbase(pc),a6
                jsr     -60(a6)              ; Output
                move.l  d0,d1
                jsr     -48(a6)              ; Write
                lea     line(pc),a4
                movem.l (sp)+,d0-d3/a0-a1/a6
                rts

dumcode:
                moveq   #0,d0
                rts

dosname:        dc.b    "dos.library",0
tdname:         dc.b    "timer.device",0
ciaaname:       dc.b    "ciaa.resource",0
ciabname:       dc.b    "ciab.resource",0
vbname:         dc.b    "probe-vb",0
dumname:        dc.b    "probe-icr",0
s_exec:         dc.b    "EXEC vbf psf quantum elapsed sysflags maxline: ",0
s_ciaa:         dc.b    "CIAA cra.crb ta tb tod: ",0
s_ciab:         dc.b    "CIAB cra.crb ta tb tod: ",0
s_icra:         dc.b    "ICRA base mask: ",0
s_icrb:         dc.b    "ICRB base mask: ",0
s_iv:           dc.b    "IV n data code node: ",0
s_srv:          dc.b    "  SRV pri data code name: ",0
s_open:         dc.b    "OPEN dev u0off u1off opencnt ver.rev | u2: d0 err dev unit: ",0
s_ofail:        dc.b    "OPEN FAIL",0
s_cmd:          dc.b    "CMD read(d0 type.err) cmd12 invalid | abortNQ(d0 err): ",0
s_tim:          dc.b    "ADD/SUB: ",0
s_cmp:          dc.b    "CMP: ",0
s_mz:           dc.b    "MZ s us F L err: ",0
s_vb:           dc.b    "VB s us F L err: ",0
s_mz2:          dc.b    "MZ2 s us F L err: ",0
s_tmo:          dc.b    "TMO ",0
s_prea:         dc.b    "PREa(MZ A=1s B=.5s) poseB F L | ordre: ",0
s_preb:         dc.b    "PREb(MZ A=.2s B=.4s) poseB F L | ordre: ",0
s_prec:         dc.b    "PREc(VB A=1s B=.5s) poseB F L | ordre: ",0
s_gst:          dc.b    "GST: ",0
s_sst:          dc.b    "SST(1000,500000) err | GST x3 | MZ.5s | GST: ",0
s_hj6:          dc.b    "HJ6 MZ.5s(F L err) VB.5s(F L err) h6cnt: ",0
s_hj2:          dc.b    "HJ2 MZ.1s(F L err) h2cnt | apres retablissement MZ.1s: ",0
t_end:          dc.b    "END",0
                even
mzvals:         dc.l    0,1000, 0,10000, 0,20000, 0,91541, 0,91542, 0,100000, 0,250000, 1,0, 0,1000000, -1
vbvals:         dc.l    0,0, 0,1, 0,20000, 0,20001, 0,40000, 0,100000, 1,0, -1
mz2vals:        dc.l    0,50, 0,1, 0,0, -1
cmpv:           dc.l    2,0, 1,5
                dc.l    1,5, 2,0
                dc.l    3,7, 3,7
                dc.l    0,1, 0,2
                dc.l    -1,0, 1,0
dumint:         dc.l    0,0
                dc.b    2,0
                dc.l    dumname,0,dumcode
vbint:          ds.b    22
port:           ds.b    34
                even
rq0:            ds.b    TR_SIZE
rqa:            ds.b    TR_SIZE
rqb:            ds.b    TR_SIZE
rq1:            ds.b    TR_SIZE
rqt:            ds.b    TR_SIZE
rqx:            ds.b    TR_SIZE
tv1:            ds.l    2
tv2:            ds.l    2
t0:             ds.l    2
vbcnt:          dc.l    0
h6cnt:          dc.l    0
h2cnt:          dc.l    0
save78:         dc.l    0
save68:         dc.l    0
dosbase:        dc.l    0
line:           ds.b    400
