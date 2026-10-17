#!/usr/bin/env bash
# tests/mk_boot_adf.sh — fabrique l'ADF de test BOOTABLE du jalon C.
# Formate un ADF DD (xdftool), assemble tests/bootblock_c.s en binaire brut (vasm -Fbin), puis patche le
# bootblock (checksum additif valide + boot code custom) via tests/patch_bootblock.py avec round-trip.
# Sortie : assets/boot_c.adf (NON committé — régénérable). L'ADF reste un filesystem OFS valide (la piste 2
# reste lisible par M6X, le secteur 0 garde le magic « DOS\0 » lu par M6W). patch_bootblock.py pose aussi des
# marqueurs spanning (« SPAN0010 »/« SPAN0011 » en tête des blocs libres 10/11 = frontière piste 0/1) consommés
# par la preuve M6Z (lecture CMD_READ multi-piste, prérequis D). Un fichier OFS « KickSlop » (1024 o) est aussi
# écrit sur le disque pour la preuve D1 (lecture seule OFS : lire un fichier par nom).
#
# Usage : tests/mk_boot_adf.sh [chemin_sortie.adf]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/assets/boot_c.adf}"
VASM="${VASM:-vasmm68k_mot}"
XDFTOOL="${XDFTOOL:-xdftool}"

for t in "$VASM" "$XDFTOOL" python3; do
  command -v "$t" >/dev/null || { echo "outil absent : $t"; exit 2; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT")"

# 1) ADF DD formaté OFS (fournit un filesystem valide : rootblock @880, pistes lisibles). PAS d'install :
#    on pose NOTRE bootblock ensuite. Le format laisse checksum=0 -> non bootable tant qu'on ne patche pas.
"$XDFTOOL" "$TMP/fmt.adf" format "KickSlopC" >/dev/null

# 2) fichier de test OFS « KickSlop » (preuve D1 : lecture par nom). Casse MIXTE (stocké « KickSlop », cherché
#    « kickslop ») pour exercer le hash+compare insensibles à la casse. xdftool l'alloue près du root (866-869)
#    -> blocs 10/11 restent libres pour les marqueurs spanning (garde dans patch_bootblock.py).
python3 -I "$ROOT/tests/mk_ofs_testfile.py" "$TMP/kickslop.bin"
"$XDFTOOL" "$TMP/fmt.adf" write "$TMP/kickslop.bin" KickSlop >/dev/null

# 3) boot code custom -> binaire brut
"$VASM" -Fbin -m68000 -o "$TMP/bb.bin" "$ROOT/tests/bootblock_c.s"

# 4) patch bootblock + marqueurs spanning + round-trip (python3 -I : entrée binaire non fiable, env isolé)
python3 -I "$ROOT/tests/patch_bootblock.py" "$TMP/fmt.adf" "$TMP/bb.bin" "$OUT"
echo "OK : $OUT"
