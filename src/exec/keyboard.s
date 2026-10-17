; src/exec/keyboard.s — F2a : réception + décodage des scancodes clavier via CIA-A.
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
; La version LIVE interrupt-driven (AddICRVector sur SP) + le câblage clavier->console = F2b.

                include "exec.i"

                xdef    kbd_selftest

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
