/* src/exec/kick-ram.ld — vlink linker script for the 256K Kickstart image of the soft-kick disk (RAMKICK).
 *
 * Same as kick.ld, with the section at $C00000 (slow RAM, loaded by src/softkick/bootblock.s) and kick_base, the
 * symbol the sources use as ROMBASE (src/exec/exec.i). make kick-ram links the same objects a second time with
 * another org to build the relocation table.
 * The CODE of the objects is aggregated in the ORDER OF THE vlink COMMAND LINE (cf. Makefile):
 * boot.o MUST be first -> its CODE carries the header/reset at $C00000.
 * Raw output via "vlink -b rawbin1"; mkrom.py adds padding + footer.
 */
MEMORY {
  rom : org = 0xc00000, len = 0x40000
}
SECTIONS {
  .text : {
    kick_base = .;
    *(text) *(CODE) *(code)
    *(data) *(DATA)
    *(bss)  *(BSS)
  } > rom
}
