; tests/loadseg_big.s - test HUNK executable (TEST ASSET, NOT ROM code): file > 16 KB to prove
; the LoadSeg cap bump (handler HS_BUF + LoadSeg buffer raised 16K -> 32K). Layout: 1 CODE + 1 DATA + 1
; RELOC32 (code->data, count=1). The DATA holds 24000 bytes of ON-DISK padding then a SENTINEL at the very
; end. The CODE reads the sentinel through a relocated pointer: if it holds the expected value, the large
; DATA (> 16 KB) was read IN FULL into the segment -> emits "LOADSEG BIG OK". With the cap lowered back to 16 KB
; (RED LOADSEG_CAP16K), the file is truncated at FINDINPUT -> the sentinel (offset 24000) is not loaded -> no output.
; PC-relative message (in the CODE) -> a single relocation (to the sentinel). Clean-room: AUTHORED code, no ROM reading.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018
BIGPAD   EQU 24000                      ; on-disk padding (forces the file beyond 16 KB)
SENTINEL EQU $B16B00B5

                section code,code
_start:
                move.l  #bigsentinel,a0     ; RELOC32 code->data: pointer to the sentinel (end of the large DATA)
                cmp.l   #SENTINEL,(a0)
                bne.s   .done               ; large DATA not fully loaded -> no output
                lea     bigmsg(pc),a0       ; PC-relative message (in the CODE -> no 2nd relocation)
.lp:
                move.b  (a0)+,d1
                beq.s   .done
                move.w  #$2000,d2
.wt:
                move.w  SERDATR,d3
                btst    #13,d3
                bne.s   .tx
                dbra    d2,.wt
                bra.s   .lp
.tx:
                and.w   #$00FF,d1
                or.w    #$0100,d1
                move.w  d1,SERDAT
                bra.s   .lp
.done:
                moveq   #0,d0
                rts
bigmsg:
                dc.b    "LOADSEG BIG OK (>16KB executable loaded via LoadSeg -150: full DATA hunk read into segment; cap raised 16K->32K, not streaming)",13,10,0
                even

                section data,data
bigpad:
                dcb.b   BIGPAD,0            ; on-disk padding: makes the file > 16 KB (READ cap)
bigsentinel:
                dc.l    SENTINEL            ; sentinel at the END of the large DATA: proves everything was read
