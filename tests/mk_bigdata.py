#!/usr/bin/env python3
# tests/mk_bigdata.py — fichier de DONNÉES de test « BigData » pour la preuve du streaming OFS réel.
# Taille 48000 octets = > 32768 (l'ancien cap whole-file DOS_FILEMAX) SANS ambiguïté : l'ancien handler
# aurait tronqué à FINDINPUT ; le handler en streaming (lecture incrémentale data-block par data-block, un seul
# buffer 512 o) le lit en entier. Pattern déterministe (i*73+17 & 0xFF) + sentinelle $B16B00B5 aux 4 derniers
# octets. Écrit sur l'ADF de test par mk_boot_adf.sh ; lu par d3j_client via dos Open/Read. AUCUNE lecture ROM.
import sys, struct

SIZE = 48000
SENTINEL = 0xB16B00B5

buf = bytearray(SIZE)
for i in range(SIZE - 4):
    buf[i] = (i * 73 + 17) & 0xFF
struct.pack_into(">I", buf, SIZE - 4, SENTINEL)

with open(sys.argv[1], "wb") as f:
    f.write(buf)

# Constantes pour l'assertion du client (évite une erreur d'arithmétique côté asm).
at500 = struct.unpack(">I", buf[500:504])[0]
print(f"BigData {SIZE} o, sentinelle $B16B00B5 @{SIZE-4}, long@500 = ${at500:08X}")
