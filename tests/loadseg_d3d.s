; tests/loadseg_d3d.s - test HUNK executable (TEST ASSET, NOT ROM code) for milestone D3d.
; Same structure as loadseg_d2.s (CODE emitting via SERDAT + DATA + 1 32-bit CODE->DATA relocation),
; but emits a DISTINCT marker "D3D LOADSEG-VIA-DOS OK". Loaded BY THE DOS LAYER (dos Open/Read -> handler
; via packets -> OFS -> ls_load_hunks -> relocation) then executed: if it emits its marker, the whole
; "load a command through dos" chain worked (packet reads + reloc + run from RAM).
; Clean-room: AUTHORED code, public hardware registers, no ROM reading.

SERDAT   EQU $DFF030
SERDATR  EQU $DFF018

                section code,code
_start:
                move.l  #d3dmsg,a0          ; ABSOLUTE pointer -> string in DATA (RELOC32 code->data)
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
d3dmsg:
                dc.b    "D3D LOADSEG-VIA-DOS OK (command loaded through dos Open/Read packets -> handler -> OFS, relocated, ran from RAM)",13,10,0
                even
