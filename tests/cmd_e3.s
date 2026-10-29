; tests/cmd_e3.s - test HUNK executable (TEST ASSET, NOT ROM code) for milestone E3.
; Same structure as loadseg_d3d.s (CODE emitting via SERDAT + DATA + 1 32-bit CODE->DATA relocation), but
; emits "E3 CMD RAN OK". Written to the ADF under the name "e3cmd"; typed at the shell ("e3cmd\r"), the shell loads it
; from DF0: via dos (Open/Read -> ls_load_hunks -> reloc) then runs it: if it emits its marker, the
; "type a command name -> load+run from disk via dos" chain worked.
; Clean-room: AUTHORED code, public hardware registers, no ROM reading.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

                section code,code
_start:
                move.l  #e3msg,a0           ; ABSOLUTE pointer -> string in DATA (RELOC32 code->data)
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

                section data,data
e3msg:
                dc.b    "E3 CMD RAN OK (command typed at the shell, loaded from DF0: via dos Open/Read, relocated, ran from RAM)",13,10,0
                even
