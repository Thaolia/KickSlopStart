/* src/exec/kick.ld — script linker vlink pour l'image ROM Kickstart 256K.
 *
 * Place une section unique à $FC0000 (base ROM 256K). Les CODE des objets
 * sont agrégés dans l'ORDRE DE LA LIGNE DE COMMANDE vlink (cf. Makefile) :
 * boot.o DOIT être premier -> son CODE porte l'en-tête/reset à $FC0000.
 * Sortie brute via « vlink -b rawbin1 » ; mkrom.py ajoute padding + footer.
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
