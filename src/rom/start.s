; src/rom/start.s — hello-ROM M0
;
; Objectif : prouver la chaîne vasm -> image 256K -> romtool -> émulateur.
; Code bas niveau Amiga 100% générique (registres matériels documentés
; publiquement, HRM) + format conteneur ROM (amitools, open-source). AUCUNE
; dérivation de la ROM Kickstart analysee : ce fichier appartient a la piste
; IMPLEMENTATION (« clean »).
;
; Comportement : gèle le matériel (IRQ/DMA off), met le fond en vert (signal
; visuel « vivant »), émet un marqueur sur le port série (canal d'assertion
; primaire), puis boucle. N'utilise NI pile NI RAM : exécutable tel quel au
; reset, avant toute configuration mémoire/overlay.
;
; Disposition du conteneur, calquée sur un Kickstart 256K authentique :
;   $FC0000 en-tête de reset (ROM-ID + vecteur PC)
;   $FC00D0 instruction RESET (champ magic_reset attendu par romtool)
;   $FC00D2 coldstart (point d'entrée de reset)

; --- Registres custom chip (Amiga Hardware Reference Manual) ---
CUSTOM   EQU $DFF000
DMACON   EQU CUSTOM+$096         ; write : SET/CLR + canaux DMA
INTENA   EQU CUSTOM+$09A         ; write : SET/CLR + masque IRQ
INTREQ   EQU CUSTOM+$09C         ; write : SET/CLR + requêtes IRQ
SERDAT   EQU CUSTOM+$030         ; write : donnée série + stop bit
SERPER   EQU CUSTOM+$032         ; write : période série (baud)
SERDATR  EQU CUSTOM+$018         ; read  : bit 13 = TBE (TX buffer vide)
COLOR00  EQU CUSTOM+$180         ; write : couleur de fond

ROMBASE  EQU $FC0000             ; base d'une ROM 256K (A500 Kickstart 1.x)
COLDSTART_OFF EQU $D2            ; offset du coldstart (comme un Kickstart réel)
GREEN    EQU $00F0               ; RGB 4 bits : vert
SERPER_9600_PAL EQU 368          ; 3546895/9600 - 1

        ORG     ROMBASE

; --- En-tête de reset (format conteneur, cf. Cloanto ROM FAQ / amitools) ---
; longword $0 (= SSP initial de reset) = 0x11114EF9 : bénin, on n'empile jamais.
; longword $4 (= PC  initial de reset) = adresse de coldstart.
rom_header:
        dc.w    $1111            ; mot ROM-ID 256K
        dc.w    $4EF9            ; opcode JMP abs.l (rend $FC0000 exécutable au warm-reset)
        dc.l    coldstart        ; cible du reset / du JMP (= $FC00D2)

        dcb.b   COLDSTART_OFF-2-(*-rom_header),0  ; remplissage jusqu'à l'offset $D0
        dc.w    $4E70            ; $FC00D0 : instruction RESET (magic_reset)

coldstart:                        ; $FC00D2
        move.w  #$7FFF,DMACON    ; coupe tout le DMA
        move.w  #$7FFF,INTENA    ; masque toutes les IRQ
        move.w  #$7FFF,INTREQ    ; acquitte les IRQ en attente

        move.w  #GREEN,COLOR00   ; fond vert AVANT le série : signal visuel garanti

        move.w  #SERPER_9600_PAL,SERPER
        lea     msg(pc),a0
.emit:
        move.b  (a0)+,d0
        beq.s   freeze
.wait:
        move.w  SERDATR,d1
        btst    #13,d1           ; attend TBE (buffer TX vide)
        beq.s   .wait
        and.w   #$00FF,d0
        or.w    #$0100,d0         ; ajoute le stop bit
        move.w  d0,SERDAT
        bra.s   .emit

freeze:
        bra.s   freeze           ; fond vert figé

msg:
        dc.b    "M0 HELLO kickstart13-reimpl alive",13,10,0
        EVEN
