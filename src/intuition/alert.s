; src/intuition/alert.s — intuition.library : DisplayAlert (spec docs/analysis/alert-v34.md §2).
; Bande d'alerte en haut de l'affichage : 640 pixels hires, 1 plan, fond $111, texte et cadre $F20 (une seule palette en
; 1.3), cadre de bandes 6 px / 3 lignes qui clignote (COMPLEMENT, ~46 trames par phase), attente du bouton gauche (CIA-A
; PRA bit 6 -> TRUE) ou droit (POTGOR bit 10 -> FALSE) par lecture directe, sans délai d'expiration.
; Écart : la bande a sa propre liste copper (en COP1LC le temps de l'alerte) au lieu d'une
; ViewPort chaînée sous laquelle les écrans glissent : pendant l'alerte, le reste de l'affichage est au fond $111
; (comme une alerte sans issue de la 1.3). Les trames sont comptées au faisceau : l'alerte fonctionne interruptions
; coupées (Alert depuis une exception).
; Piste IMPLÉMENTATION (« clean ») : AutoDocs intuition DisplayAlert + spec alert-v34. AUCUNE lecture ROM.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xdef    intuition_DisplayAlert

AL_W            EQU 640              ; largeur de l'alerte (pixels hires)
AL_BPR          EQU AL_W/8
AL_BLINK        EQU 46               ; trames par phase du clignotement du cadre
AL_TOP          EQU $2C              ; première ligne affichée (DIWSTRT)
VPOSR           EQU CUSTOM+$004
VHPOSR          EQU CUSTOM+$006
POTGOR          EQU CUSTOM+$016
DMACONR         EQU CUSTOM+$002
; cadre sur la pile
AF_BM           EQU 0                ; BitMap
AF_RP           EQU bm_SIZEOF        ; RastPort
AF_RAS          EQU AF_RP+rp_SIZEOF  ; long : raster
AF_COP          EQU AF_RAS+4         ; long : liste copper
AF_DMA          EQU AF_COP+4         ; word : bits copper / bitplanes / sprites de DMACONR avant l'alerte
AF_H            EQU AF_DMA+2         ; word : hauteur
AF_SIZE         EQU AF_H+2
AL_COPSZ        EQU 30*4             ; liste copper (mots MOVE/WAIT)

; DisplayAlert(alertNumber d0, chaîne a0, hauteur d1) -> d0 = 1 (bouton gauche) | 0 (bouton droit). Chaîne : blocs
; « x (mot), y (octet, ligne de base), texte terminé par 0, octet de suite (0 = fin) », octets consécutifs sans
; alignement. Raster impossible à allouer : 0 ; pour une alerte sans issue (bit 31), exec Alert prend le relais.
intuition_DisplayAlert:
        movem.l d2-d7/a2-a6,-(sp)
        lea     -AF_SIZE(sp),sp
        move.l  sp,a4                ; a4 = cadre
        move.l  d0,d7                ; d7 = numéro
        move.l  a0,a3                ; a3 = chaîne
        move.w  d1,AF_H(a4)
        move.l  IB_GFXBASE(a6),a5    ; a5 = GfxBase
        move.l  ($4).w,a6
        moveq   #0,d0                ; raster : hauteur x 80 octets, chip
        move.w  d1,d0
        mulu    #AL_BPR,d0
        move.l  #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,AF_RAS(a4)
        beq     .da_noras
        move.l  #AL_COPSZ,d0
        move.l  #MEMF_CHIP,d1
        jsr     LVO_ALLOCMEM(a6)
        move.l  d0,AF_COP(a4)
        beq     .da_nocop
        move.l  a5,a6                ; graphics : BitMap, RastPort, raster effacé
        lea     AF_BM(a4),a0
        moveq   #1,d0
        move.l  #AL_W,d1
        moveq   #0,d2
        move.w  AF_H(a4),d2
        jsr     LVO_INITBITMAP(a6)
        move.l  AF_RAS(a4),AF_BM+bm_Planes(a4)
        lea     AF_RP(a4),a1
        jsr     LVO_INITRASTPORT(a6)
        lea     AF_BM(a4),a0
        move.l  a0,AF_RP+rp_BitMap(a4)
        lea     AF_RP(a4),a1
        moveq   #0,d0
        jsr     LVO_SETRAST(a6)
        lea     AF_RP(a4),a1
        moveq   #1,d0
        jsr     LVO_SETAPEN(a6)
        lea     AF_RP(a4),a1
        moveq   #JAM1,d0
        jsr     LVO_SETDRMD(a6)
        bsr     al_frame             ; cadre (présent dès l'affichage)
.da_txt:                             ; blocs de texte
        moveq   #0,d0
        move.b  (a3)+,d0
        lsl.w   #8,d0
        move.b  (a3)+,d0             ; x (lu octet par octet : la chaîne n'est pas alignée)
        moveq   #0,d1
        move.b  (a3)+,d1             ; y
        lea     AF_RP(a4),a1
        jsr     LVO_MOVE(a6)
        move.l  a3,a0                ; longueur du texte
.da_len:
        tst.b   (a3)+
        bne.s   .da_len
        move.l  a3,d0
        sub.l   a0,d0
        subq.l  #1,d0
        beq.s   .da_notx
        lea     AF_RP(a4),a1
        jsr     LVO_TEXT(a6)
.da_notx:
        tst.b   (a3)+                ; octet de suite
        bne.s   .da_txt
        bsr     al_coplist           ; affichage : la bande d'alerte remplace la liste copper (aussi au boot, avant
        move.w  DMACONR,d0           ; toute vue : COP1LC directement)
        and.w   #(DMAF_RASTER|DMAF_COPPER|DMAF_SPRITE),d0
        move.w  d0,AF_DMA(a4)
        move.l  AF_COP(a4),COP1LC
        move.w  #0,COPJMP1
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_RASTER|DMAF_COPPER),DMACON
        move.w  #DMAF_SPRITE,DMACON  ; pointeur invisible pendant l'attente
        bsr     al_release           ; boutons relâchés
        moveq   #0,d6                ; d6 = trames de la phase en cours
        bsr     al_line
        move.w  d0,d5                ; d5 = ligne précédente
.da_wait:
        btst    #6,CIAA_PRA          ; gauche (0 = enfoncé) : prioritaire
        beq.s   .da_left
        move.w  POTGOR,d0
        btst    #10,d0
        beq.s   .da_right
        bsr     al_line              ; nouvelle trame : ligne courante < ligne précédente
        move.w  d5,d1
        move.w  d0,d5
        cmp.w   d1,d0
        bhs.s   .da_wait
        addq.w  #1,d6
        cmp.w   #AL_BLINK,d6
        blo.s   .da_wait
        moveq   #0,d6
        lea     AF_RP(a4),a1
        moveq   #COMPLEMENT,d0
        jsr     LVO_SETDRMD(a6)
        bsr     al_frame
        bra.s   .da_wait
.da_left:
        moveq   #1,d7
        bra.s   .da_end
.da_right:
        moveq   #0,d7
.da_end:
        bsr     al_release
        move.w  #(DMAF_RASTER|DMAF_COPPER|DMAF_SPRITE),DMACON   ; affichage d'avant
        tst.l   gb_ActiView(a5)
        beq.s   .da_dma
        move.l  gb_LOFlist(a5),d0    ; une vue est chargée : son enchaînement copinit -> liste maîtresse
        move.l  d0,COP2LC
        move.l  gb_copinit(a5),d1
        beq.s   .da_ci
        move.l  d1,d0
.da_ci:
        move.l  d0,COP1LC
        move.w  #0,COPJMP1
.da_dma:
        move.w  AF_DMA(a4),d0
        or.w    #DMAF_SETCLR,d0
        move.w  d0,DMACON
        move.l  ($4).w,a6
        move.l  AF_COP(a4),a1
        move.l  #AL_COPSZ,d0
        jsr     LVO_FREEMEM(a6)
        move.l  AF_RAS(a4),a1
        moveq   #0,d0
        move.w  AF_H(a4),d0
        mulu    #AL_BPR,d0
        jsr     LVO_FREEMEM(a6)
        move.l  d7,d0
        bra.s   .da_ret
.da_nocop:
        move.l  AF_RAS(a4),a1
        moveq   #0,d0
        move.w  AF_H(a4),d0
        mulu    #AL_BPR,d0
        jsr     LVO_FREEMEM(a6)
.da_noras:
        tst.l   d7                   ; sans issue : exec Alert (chemin dur : reset, Guru au boot suivant)
        bpl.s   .da_false
        jsr     LVO_ALERT(a6)
.da_false:
        moveq   #0,d0
.da_ret:
        lea     AF_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; al_line -> d0.w = ligne courante du faisceau (0..312). Préserve tout le reste.
al_line:
        move.l  VPOSR,d0             ; VPOSR (bit 0 = ligne 8) puis VHPOSR (octet haut = lignes 0-7)
        lsr.l   #8,d0
        and.w   #$1FF,d0
        rts

; al_release : attend que les deux boutons soient relâchés. Clobbe d0.
al_release:
        btst    #6,CIAA_PRA
        beq.s   al_release
        move.w  POTGOR,d0
        btst    #10,d0
        beq.s   al_release
        rts

; al_frame(a4 = cadre, a6 = GfxBase) : bandes verticales de 6 px (lignes 0..H-2) et horizontales de 3 lignes en haut et
; en bas (y = H-4..H-2), au mode courant du RastPort ; la dernière ligne reste au fond. Clobbe d0-d3/a0-a1.
al_frame:
        moveq   #0,d0                ; gauche
        moveq   #0,d1
        moveq   #5,d2
        bsr.s   .af_vbar
        move.l  #AL_W-6,d0           ; droite
        moveq   #0,d1
        move.l  #AL_W-1,d2
        bsr.s   .af_vbar
        moveq   #6,d0                ; haut
        moveq   #0,d1
        move.l  #AL_W-7,d2
        moveq   #2,d3
        bsr.s   .af_fill
        moveq   #6,d0                ; bas
        moveq   #0,d1
        move.w  AF_H(a4),d1
        subq.l  #4,d1
        move.l  #AL_W-7,d2
        moveq   #0,d3
        move.w  AF_H(a4),d3
        subq.l  #2,d3
        bra.s   .af_fill
.af_vbar:
        moveq   #0,d3
        move.w  AF_H(a4),d3
        subq.l  #2,d3
.af_fill:
        cmp.l   d1,d3                ; hauteur trop petite : rien
        blt.s   .af_r
        lea     AF_RP(a4),a1
        jmp     LVO_RECTFILL(a6)
.af_r:
        rts

; al_coplist(a4 = cadre) : liste copper de la bande : bitplanes hires 1 plan sur 640 px, couleurs, puis bitplanes
; coupés après la dernière ligne de l'alerte. Clobbe d0-d1/a0.
al_coplist:
        move.l  AF_COP(a4),a0
        move.l  #$01009200,(a0)+     ; BPLCON0 : hires, 1 plan, couleur
        move.l  #$01020000,(a0)+     ; BPLCON1
        move.l  #$01040000,(a0)+     ; BPLCON2
        move.l  #$01080000,(a0)+     ; BPL1MOD
        move.l  #$010A0000,(a0)+     ; BPL2MOD
        move.l  #$008E2C81,(a0)+     ; DIWSTRT
        move.l  #$00902CC1,(a0)+     ; DIWSTOP
        move.l  #$0092003C,(a0)+     ; DDFSTRT (hires 640)
        move.l  #$009400D4,(a0)+     ; DDFSTOP
        move.l  AF_RAS(a4),d0
        move.w  #$00E0,(a0)+         ; BPL1PTH
        swap    d0
        move.w  d0,(a0)+
        move.w  #$00E2,(a0)+         ; BPL1PTL
        swap    d0
        move.w  d0,(a0)+
        move.l  #$01800111,(a0)+     ; COLOR00
        move.l  #$01820F20,(a0)+     ; COLOR01
        moveq   #AL_TOP,d0           ; WAIT sur la ligne qui suit l'alerte
        add.w   AF_H(a4),d0
        cmp.w   #$FF,d0
        bls.s   .ac_wait
        move.l  #$FFDFFFFE,(a0)+     ; au-delà de la ligne 255
.ac_wait:
        lsl.w   #8,d0
        or.w    #$0001,d0
        move.w  d0,(a0)+
        move.w  #$FFFE,(a0)+
        move.l  #$01000200,(a0)+     ; bitplanes coupés : le reste de l'affichage au fond
        move.l  #$FFFFFFFE,(a0)+     ; fin
        rts
