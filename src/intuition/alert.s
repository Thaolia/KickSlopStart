; src/intuition/alert.s - intuition.library: DisplayAlert (spec docs/analysis/alert-v34.md §2).
; Alert band at the top of the display: 640 hires pixels, 1 plane, background $111, text and frame $F20 (a single
; palette in 1.3), frame of 6 px / 3 line bands that blinks (COMPLEMENT, ~46 frames per phase), wait for the left button
; (CIA-A PRA bit 6 -> TRUE) or right button (POTGOR bit 10 -> FALSE) by direct reading, with no timeout.
; Deviation: the band has its own copper list (in COP1LC for the duration of the alert) instead of a
; chained ViewPort under which the screens slide: during the alert, the rest of the display is at background $111
; (like a 1.3 dead-end alert). Frames are counted from the beam: the alert works with interrupts
; disabled (Alert from an exception).
; IMPLEMENTATION track ("clean"): AutoDocs intuition DisplayAlert + spec alert-v34. NO ROM reading.

                include "exec.i"
                include "graphics.i"
                include "intuition.i"

                xdef    intuition_DisplayAlert

AL_W            EQU 640              ; alert width (hires pixels)
AL_BPR          EQU AL_W/8
AL_BLINK        EQU 46               ; frames per phase of the frame blinking
AL_TOP          EQU $2C              ; first displayed line (DIWSTRT)
VPOSR           EQU CUSTOM+$004
VHPOSR          EQU CUSTOM+$006
POTGOR          EQU CUSTOM+$016
DMACONR         EQU CUSTOM+$002
; frame on the stack
AF_BM           EQU 0                ; BitMap
AF_RP           EQU bm_SIZEOF        ; RastPort
AF_RAS          EQU AF_RP+rp_SIZEOF  ; long: raster
AF_COP          EQU AF_RAS+4         ; long: copper list
AF_DMA          EQU AF_COP+4         ; word: copper / bitplane / sprite bits of DMACONR before the alert
AF_H            EQU AF_DMA+2         ; word: height
AF_SIZE         EQU AF_H+2
AL_COPSZ        EQU 30*4             ; copper list (MOVE/WAIT words)

; DisplayAlert(alertNumber d0, string a0, height d1) -> d0 = 1 (left button) | 0 (right button). String: blocks
; "x (word), y (byte, baseline), 0-terminated text, continuation byte (0 = end)", consecutive bytes without
; alignment. Raster cannot be allocated: 0; for a dead-end alert (bit 31), exec Alert takes over.
intuition_DisplayAlert:
        movem.l d2-d7/a2-a6,-(sp)
        lea     -AF_SIZE(sp),sp
        move.l  sp,a4                ; a4 = frame
        move.l  d0,d7                ; d7 = number
        move.l  a0,a3                ; a3 = string
        move.w  d1,AF_H(a4)
        move.l  IB_GFXBASE(a6),a5    ; a5 = GfxBase
        move.l  ($4).w,a6
        moveq   #0,d0                ; raster: height x 80 bytes, chip
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
        move.l  a5,a6                ; graphics: BitMap, RastPort, cleared raster
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
        bsr     al_frame             ; frame (present as soon as displayed)
.da_txt:                             ; text blocks
        moveq   #0,d0
        move.b  (a3)+,d0
        lsl.w   #8,d0
        move.b  (a3)+,d0             ; x (read byte by byte: the string is not aligned)
        moveq   #0,d1
        move.b  (a3)+,d1             ; y
        lea     AF_RP(a4),a1
        jsr     LVO_MOVE(a6)
        move.l  a3,a0                ; text length
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
        tst.b   (a3)+                ; continuation byte
        bne.s   .da_txt
        bsr     al_coplist           ; display: the alert band replaces the copper list (also at boot, before
        move.w  DMACONR,d0           ; any view: COP1LC directly)
        and.w   #(DMAF_RASTER|DMAF_COPPER|DMAF_SPRITE),d0
        move.w  d0,AF_DMA(a4)
        move.l  AF_COP(a4),COP1LC
        move.w  #0,COPJMP1
        move.w  #(DMAF_SETCLR|DMAF_MASTER|DMAF_RASTER|DMAF_COPPER),DMACON
        move.w  #DMAF_SPRITE,DMACON  ; pointer invisible during the wait
        bsr     al_release           ; buttons released
        moveq   #0,d6                ; d6 = frames of the current phase
        bsr     al_line
        move.w  d0,d5                ; d5 = previous line
.da_wait:
        btst    #6,CIAA_PRA          ; left (0 = pressed): takes priority
        beq.s   .da_left
        move.w  POTGOR,d0
        btst    #10,d0
        beq.s   .da_right
        bsr     al_line              ; new frame: current line < previous line
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
        move.w  #(DMAF_RASTER|DMAF_COPPER|DMAF_SPRITE),DMACON   ; previous display
        tst.l   gb_ActiView(a5)
        beq.s   .da_dma
        move.l  gb_LOFlist(a5),d0    ; a view is loaded: its copinit -> master list chaining
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
        tst.l   d7                   ; dead-end: exec Alert (hard path: reset, Guru at next boot)
        bpl.s   .da_false
        jsr     LVO_ALERT(a6)
.da_false:
        moveq   #0,d0
.da_ret:
        lea     AF_SIZE(sp),sp
        movem.l (sp)+,d2-d7/a2-a6
        rts

; al_line -> d0.w = current beam line (0..312). Preserves everything else.
al_line:
        move.l  VPOSR,d0             ; VPOSR (bit 0 = line 8) then VHPOSR (high byte = lines 0-7)
        lsr.l   #8,d0
        and.w   #$1FF,d0
        rts

; al_release: waits until both buttons are released. Clobbers d0.
al_release:
        btst    #6,CIAA_PRA
        beq.s   al_release
        move.w  POTGOR,d0
        btst    #10,d0
        beq.s   al_release
        rts

; al_frame(a4 = frame, a6 = GfxBase): vertical bands of 6 px (lines 0..H-2) and horizontal bands of 3 lines at the top
; and bottom (y = H-4..H-2), in the current RastPort mode; the last line stays background. Clobbers d0-d3/a0-a1.
al_frame:
        moveq   #0,d0                ; left
        moveq   #0,d1
        moveq   #5,d2
        bsr.s   .af_vbar
        move.l  #AL_W-6,d0           ; right
        moveq   #0,d1
        move.l  #AL_W-1,d2
        bsr.s   .af_vbar
        moveq   #6,d0                ; top
        moveq   #0,d1
        move.l  #AL_W-7,d2
        moveq   #2,d3
        bsr.s   .af_fill
        moveq   #6,d0                ; bottom
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
        cmp.l   d1,d3                ; height too small: nothing
        blt.s   .af_r
        lea     AF_RP(a4),a1
        jmp     LVO_RECTFILL(a6)
.af_r:
        rts

; al_coplist(a4 = frame): copper list of the band: hires bitplanes, 1 plane over 640 px, colors, then bitplanes
; disabled after the last line of the alert. Clobbers d0-d1/a0.
al_coplist:
        move.l  AF_COP(a4),a0
        move.l  #$01009200,(a0)+     ; BPLCON0: hires, 1 plane, color
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
        moveq   #AL_TOP,d0           ; WAIT on the line following the alert
        add.w   AF_H(a4),d0
        cmp.w   #$FF,d0
        bls.s   .ac_wait
        move.l  #$FFDFFFFE,(a0)+     ; beyond line 255
.ac_wait:
        lsl.w   #8,d0
        or.w    #$0001,d0
        move.w  d0,(a0)+
        move.w  #$FFFE,(a0)+
        move.l  #$01000200,(a0)+     ; bitplanes disabled: the rest of the display at background
        move.l  #$FFFFFFFE,(a0)+     ; end
        rts
