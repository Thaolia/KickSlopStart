; src/exec/keyboard.s — F2a/F2b : réception, décodage et driver LIVE du clavier via CIA-A.
;
; Le clavier Amiga transmet chaque scancode en série sur la ligne SP de CIA-A (horloge CNT). Quand 8 bits sont
; reçus, CIA-A pose l'ICR bit 3 (SP). L'octet brut dans SDR est le keycode INVERSÉ et tourné d'1 bit ->
; keycode = NOT(ROR.b #1, brut). bit 7 = up/down, bits 6-0 = touche. Codes spéciaux power-up : $FD (initiate
; power-up key stream), $FE (terminate). Après lecture, HANDSHAKE obligatoire (pulse SP en sortie ~75us via CRA
; bit 6) sinon le clavier stalle avant l'octet suivant.
;
; kbd_selftest : appelé TRÈS TÔT au boot (interruptions masquées, cf. le spike qui marchait ainsi) -> poll direct
; BORNÉ du CIA-A, décode+handshake le flux power-up du clavier émulé, renvoie d0 = flags vus ($FD/$FE). Prouve
; la voie de réception+décodage+handshake SANS injecteur (le clavier émulé envoie sa séquence power-up au reset).
; Autonome (ne dépend pas de SysBase). Clobbe d0-d4/a0-a1. Piste IMPLÉMENTATION : HRM (CIA/clavier). AUCUNE lecture ROM.
;
; F2b = driver LIVE interrupt-driven : kbd_install enregistre kbd_interrupt sur l'ICR bit 3 (SP) via
; AddICRVector (cia.resource) + ré-active PORTS/INT2 ; à chaque scancode reçu, cia_dispatch (via ciaa_server,
; chaîne PORTS) appelle kbd_interrupt qui décode, handshake, ignore les key-up, mappe keycode -> ASCII (keymap
; US minimal) et pousse dans un ring SPSC (producteur). con_handler (READ) draine ce ring (consommateur) EN PLUS
; du RBF série -> le CLI est pilotable au vrai clavier. Keycodes mesurés sous FS-UAE : v=$34 e=$12 r=$13 Return=$44
; space=$40 a=$20 (bit 7 = up). Lock-free (producteur avance TAIL en dernier, consommateur avance HEAD).

                include "exec.i"

                xdef    kbd_selftest
                xref    kbd_devevent     ; kbddev.s : matrice + KBD_READEVENT

CIAA_SDR     EQU $BFEC01          ; CIA-A reg $C : donnée série (scancode reçu)
CIAA_ICR     EQU $BFED01          ; CIA-A reg $D : interrupt control (lecture = pending + ACK ; bit 3 = SP)
CIAA_CRA     EQU $BFEE01          ; CIA-A reg $E : control A (bit 6 = SPMODE : 0 = entrée, 1 = sortie)

KBD_MAXBYTES EQU 32               ; borne : nb max d'octets lus (le flux power-up est court ; borne les resends)
KBD_BUDGET   EQU $00100000        ; borne TOTALE d'itérations de poll (~1,5 s de reads CIA) : borne le temps mur
                                  ; même si le clavier est lent/absent/stallé (pas de retard de boot pathologique)
KBD_HSDELAY  EQU $0100            ; handshake : itérations du pulse SPMODE (~> 75 us à 7 MHz)

KBF_FD       EQU 0                ; flag : $FD (initiate power-up) vu
KBF_FE       EQU 1                ; flag : $FE (terminate power-up) vu

; kbd_selftest() -> d0 = flags (bit KBF_FD, bit KBF_FE). d0==3 (les deux) = flux power-up reçu+décodé.
kbd_selftest:
                moveq   #0,d0                ; d0 = flags résultat
                move.b  CIAA_CRA,d1           ; SP en ENTRÉE (CRA bit 6 = 0)
                and.b   #$BF,d1
                move.b  d1,CIAA_CRA
                moveq   #KBD_MAXBYTES-1,d4    ; d4 = compteur d'octets max (borne sur les resends)
                move.l  #KBD_BUDGET,d2        ; budget TOTAL d'itérations de poll (borne le temps mur, clavier lent/absent)
.poll:
                move.b  CIAA_ICR,d1           ; lit ICR (ACK) ; bit 3 = SP
                btst    #3,d1
                bne.s   .got
                subq.l  #1,d2
                bne.s   .poll
                bra.s   .done                 ; budget épuisé -> fin (aucun octet / clavier absent)
.got:
                move.b  CIAA_SDR,d3           ; octet brut reçu
                ror.b   #1,d3
                not.b   d3                    ; d3 = keycode décodé
                ifeq    F2A_NO_HANDSHAKE
                move.b  CIAA_CRA,d1           ; handshake : pulse SPMODE sortie ~75us puis entrée
                or.b    #$40,d1
                move.b  d1,CIAA_CRA
                move.w  #KBD_HSDELAY,d1
.hs:
                dbra    d1,.hs
                move.b  CIAA_CRA,d1
                and.b   #$BF,d1
                move.b  d1,CIAA_CRA
                endc                          ; RED F2A_NO_HANDSHAKE : pas de handshake -> le clavier stalle après
                                              ; 1 octet -> $FE jamais atteint -> « F2 KBD OK » absent (isole le handshake)
                cmp.b   #$FD,d3
                bne.s   .notfd
                bset    #KBF_FD,d0
.notfd:
                cmp.b   #$FE,d3
                bne.s   .notfe
                bset    #KBF_FE,d0
                bra.s   .done                 ; $FE = terminate -> fin du flux power-up
.notfe:
                dbra    d4,.poll              ; borne resends : reprend le poll avec le budget restant
.done:
                rts

; ============================ F2b : driver clavier LIVE (interrupt-driven) ============================
                xdef    kbd_install
                xdef    kbd_pushcooked
                xref    kbd_cook         ; #5 : exec/keymap.s — cook keycode(+qualifiers)->ASCII (US/AZERTY)

; kbd_install() [a6=SysBase] -> d0 = 0 (ok) | !=0 (échec OpenResource). Installe le driver LIVE :
; vide le ring, SP en ENTRÉE, AddICRVector(bit 3 = SP) -> kbd_interrupt, ré-active PORTS/INT2 (coupé après
; la démo M7B). ciaa_server (resté sur la chaîne PORTS) acquitte l'ICR et route le bit 3 vers kbd_interrupt.
; Clobbe d0/d1/a0/a1 (a2/a6 préservés).
kbd_install:
                movem.l a2/a6,-(sp)
                clr.w   KBD_HEAD             ; RAM basse non garantie nulle au power-on
                clr.w   KBD_TAIL
                clr.w   KBD_FHEAD            ; tampon du feeder : un index impair laissé par la RAM du power-on faisait
                clr.w   KBD_FTAIL            ; une erreur d'adresse au 1er appui (WinUAE remplit la RAM, FS-UAE la vide)
                clr.w   KBD_QUAL             ; #5 : état des qualifieurs
                lea     kbd_ciaa_name(pc),a1
                jsr     LVO_OPENRESOURCE(a6) ; OpenResource("ciaa.resource")
                tst.l   d0
                beq.s   .ki_fail
                move.l  d0,a2                ; a2 = base ciaa.resource
                move.b  CIAA_CRA,d0          ; SP en ENTRÉE (b6=0) pour recevoir
                and.b   #$BF,d0
                move.b  d0,CIAA_CRA
                move.l  a2,a6                ; a6 = base resource pour AddICRVector
                moveq   #3,d0                ; CIA-A SP = ICR bit 3 (clavier)
                lea     kbd_int(pc),a1
                jsr     CIA_ADDICRVECTOR(a6) ; -> d0 = 0 (ok) | struct occupant le bit
                move.w  #(INTF_SETCLR|INTF_PORTS),INTENA ; ré-active Paula PORTS/INT2 (coupé après M7B)
                bra.s   .ki_ret              ; d0 = résultat AddICRVector (0 = ok)
.ki_fail:
                moveq   #-1,d0
.ki_ret:
                movem.l (sp)+,a2/a6
                rts

; kbd_interrupt : handler ICR bit 3 (SP clavier). Appelé par cia_dispatch via jsr (a5) : d2/d3 (index bit +
; ICR) et a2 (base resource) sont VIVANTS à travers l'appel -> on save/restore d0-d3/a0-a1 et on ne touche NI
; a2 NI a6. Décode (F2a) ; HANDSHAKE obligatoire. #5 : SUIVI DES QUALIFIEURS (shift/caps/ctrl/alt/Amiga, $60-$67)
; dans KBD_QUAL, puis cuisson keycode(+KBD_QUAL)->ASCII via kbd_cook (keymap US/AZERTY) ; push dans le ring SPSC
; (producteur : écrit la donnée puis avance TAIL en dernier -> consommateur jamais en avance).
kbd_interrupt:
                movem.l d0-d3/a0-a1,-(sp)
                move.b  CIAA_SDR,d0          ; octet brut reçu
                ror.b   #1,d0
                not.b   d0                   ; d0.b = keycode (bit 7 = up/down)
                move.b  CIAA_CRA,d1          ; handshake : pulse SPMODE sortie ~75us puis entrée
                or.b    #$40,d1
                move.b  d1,CIAA_CRA
                move.w  #KBD_HSDELAY,d1
.ki_hs:
                dbra    d1,.ki_hs
                move.b  CIAA_CRA,d1
                and.b   #$BF,d1
                move.b  d1,CIAA_CRA
                jsr     kbd_devevent         ; keyboard.device : matrice + événement brut (préserve tout)
                move.b  d0,d2                ; d2 = raw (bit7=up/down)
                and.b   #$7F,d2              ; d2 = keycode
                cmp.b   #$60,d2
                blo   .ki_key              ; < $60 -> touche normale
                cmp.b   #$68,d2
                bhs   .ki_out              ; >= $68 : codes spéciaux, ignorés
                cmp.b   #$62,d2
                beq   .ki_caps             ; $62 = CAPSLOCK (toggle)
                moveq   #0,d1                ; $60/$61 = shift L/R ; $63 = ctrl
                cmp.b   #$60,d2
                bne.s   .kq1
                moveq   #$01,d1
                bra.s   .ki_qmod
.kq1:
                cmp.b   #$61,d2
                bne.s   .kq2
                moveq   #$02,d1
                bra.s   .ki_qmod
.kq2:
                moveq   #$08,d1              ; $63 = ctrl
                cmp.b   #$63,d2
                beq.s   .ki_qmod
                moveq   #$10,d1              ; $64-$67 = alt G/D, Amiga G/D : bits $10 << (code - $64)
                move.b  d2,d3                ; (IEQUALIFIER_LALT, RALT, LCOMMAND, RCOMMAND)
                sub.b   #$64,d3
                lsl.w   d3,d1
.ki_qmod:
                btst    #7,d0                ; down -> set le bit, up -> clear
                bne.s   .ki_qclr
                or.w    d1,KBD_QUAL
                bra.s   .ki_feedout
.ki_qclr:
                not.w   d1
                and.w   d1,KBD_QUAL
                bra.s   .ki_feedout
.ki_caps:
                btst    #7,d0                ; CAPS : toggle sur key-down seulement
                bne.s   .ki_feedout
                move.w  KBD_QUAL,d1
                eori.w  #$04,d1
                move.w  d1,KBD_QUAL
                bra.s   .ki_feedout
.ki_key:
                btst    #7,d0
                bne.s   .ki_feedout          ; touche normale relâchée : pour input.device seulement
                bsr.s   .ki_feed
                ifne    F2B_NO_FEED
                bra.s   .ki_out              ; RED F2B_NO_FEED : décode mais NE nourrit PAS le ring cuit (isole le câblage)
                endc
                move.b  d2,d0                ; keycode
                move.w  KBD_QUAL,d1          ; qualifieurs courants
                bsr.s   kbd_pushcooked
                bra.s   .ki_out
.ki_feedout:
                bsr.s   .ki_feed
                bra.s   .ki_out
                ; --- tout événement (enfoncement, relâchement, qualificatifs) -> anneau du feeder : (KBD_QUAL << 8) |
                ; code brut (bit 7 = relâchement), qualificatif déjà à jour -> input.device reçoit tout, comme en 1.3 ---
.ki_feed:
                move.w  KBD_FTAIL,d1
                move.w  d1,d3
                addq.w  #2,d3
                and.w   #KBD_FRMASK,d3
                cmp.w   KBD_FHEAD,d3
                beq.s   .kf_ret              ; anneau plein : événement perdu (borné)
                move.w  d3,-(sp)
                move.w  KBD_QUAL,d3
                lsl.w   #8,d3
                move.b  d0,d3                ; d3 = (qualifieurs << 8) | code brut
                lea     KBD_FEEDRING,a0
                move.w  d3,0(a0,d1.w)        ; écrit l'entrée AVANT de publier TAIL
                move.w  (sp)+,KBD_FTAIL
.kf_ret:
                rts
.ki_out:
                movem.l (sp)+,d0-d3/a0-a1
                rts

; kbd_pushcooked(d0.b = keycode, d1.w = qualificatifs) : caractère cuit (kbd_cook) déposé dans l'anneau lu par le CLI
; (con_ring_get) ; non mappé ou anneau plein : rien. Deux producteurs (interruption clavier, répétition du feeder) :
; l'appelant hors interruption appelle sous Disable. Préserve d2-d7/a2-a6.
kbd_pushcooked:
                move.l  d2,-(sp)
                jsr     kbd_cook             ; -> d0.b = ASCII (préserve d2/a0/a1)
                tst.b   d0
                beq.s   .pc_ret              ; non mappé
                move.b  d0,d1
                move.w  KBD_TAIL,d0
                move.w  d0,d2
                addq.w  #1,d2
                and.w   #KBD_RMASK,d2
                cmp.w   KBD_HEAD,d2
                beq.s   .pc_ret              ; anneau plein : perdu (borné)
                lea     KBD_RING,a0
                move.b  d1,0(a0,d0.w)        ; écrit la donnée AVANT de publier TAIL
                move.w  d2,KBD_TAIL
.pc_ret:
                move.l  (sp)+,d2
                rts

                EVEN
kbd_int:                                     ; struct Interrupt en ROM (AddICRVector ne stocke qu'un pointeur)
                dc.l    0                    ; LN_SUCC
                dc.l    0                    ; LN_PRED
                dc.b    2                    ; LN_TYPE = NT_INTERRUPT
                dc.b    0                    ; LN_PRI
                dc.l    0                    ; LN_NAME
                dc.l    0                    ; IS_DATA (inutilisé : le handler lit des globals + adresses fixes)
                dc.l    kbd_interrupt        ; IS_CODE
kbd_ciaa_name:
                dc.b    "ciaa.resource",0
                EVEN

