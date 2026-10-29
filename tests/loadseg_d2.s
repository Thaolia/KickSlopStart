; tests/loadseg_d2.s - test HUNK executable (TEST ASSET, NOT ROM code) for milestone D2 (LoadSeg).
; Linked as an Amiga load file (hunk): one CODE section + one DATA section, with ONE 32-bit CODE->DATA relocation
; (move.l #d2msg,a0 references the string stored in DATA). Proves that LoadSeg loaded the hunks AND APPLIED the
; relocation: the code emits "D2LOADSEG OK ..." via SERDAT. If the relocation is SKIPPED (RED), the pointer stays
; at the link-time offset (0 in the DATA hunk) -> reads low RAM -> wrong bytes -> marker missing, WITHOUT a bus
; error (valid RAM). Entry: called via JSR (A6 = SysBase, ignored; direct serial output, self-contained).
; Clean-room: AUTHORED code, public hardware registers, no ROM reading.

SERDAT   EQU $DFF030                ; serial register (write)
SERDATR  EQU $DFF018                ; serial register (read; TBE = bit 13)

                section code,code
_start:
                move.l  #d2msg,a0          ; ABSOLUTE pointer -> string in DATA (generates a RELOC32 code->data)
.lp:
                move.b  (a0)+,d1
                beq.s   .done
                move.w  #$2000,d2          ; TBE timeout (bounded, never hangs)
.wt:
                move.w  SERDATR,d3
                btst    #13,d3            ; TBE (transmit buffer empty) ?
                bne.s   .tx
                dbra    d2,.wt
                bra.s   .lp               ; timeout -> next character
.tx:
                and.w   #$00FF,d1
                or.w    #$0100,d1         ; stop bit
                move.w  d1,SERDAT
                bra.s   .lp
.done:
                moveq   #0,d0             ; D0 = 0 (success; LoadSeg convention: JSR then return)
                rts

                section data,data
d2msg:
                dc.b    "D2LOADSEG OK (hunk loaded + relocated from OFS, ran from RAM)",13,10,0
                even
