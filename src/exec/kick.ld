/* src/exec/kick.ld — vlink linker script for the 256K Kickstart ROM image.
 *
 * Places a single section at $FC0000 (256K ROM base). The CODE of the objects
 * is aggregated in the ORDER OF THE vlink COMMAND LINE (cf. Makefile):
 * boot.o MUST be first -> its CODE carries the header/reset at $FC0000.
 * Raw output via "vlink -b rawbin1"; mkrom.py adds padding + footer.
 */
MEMORY {
  rom : org = 0xfc0000, len = 0x40000
}
SECTIONS {
  .text : {
    *(text) *(CODE) *(code)
    *(data) *(DATA)
    *(bss)  *(BSS)
  } > rom
}
