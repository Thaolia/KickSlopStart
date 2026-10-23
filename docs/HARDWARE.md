# Cible matérielle & toolchain

## Amiga 500 (cible)

- CPU **Motorola 68000**, big-endian, pas de MMU.
- **Kickstart ROM 256 KiB** mappée à **`$FC0000`–`$FFFFFF`** ; mirroir à `$0` au reset (overlay OVL,
  piloté par la CIA). RAM chip à partir de `$000000` (512 KiB sur A500 d'origine).
- Chipset (OCS) : adresses custom à partir de `$DFF000` (ex. `$DFF096` DMACON, `$DFF09A` INTENA,
  `$DFF09C` INTREQ, `$DFF180` COLOR00, `$DFF030/032/018` SERDAT/SERPER/SERDATR). CIA 8520 à `$BFE001`/`$BFD000`.
- Au power-on : DMA et interruptions doivent être neutralisés très tôt (le coldstart hello le fait).

### Vraie ROM (EPROM) — note pour M7
Une Kickstart 256K se remplace par une EPROM/flash adaptée (typiquement une 27C400 4 Mbit avec gestion
des lignes d'adresse, ou un adaptateur). À détailler au moment du portage matériel ; l'émulateur
suffit jusque-là.

## Toolchain (hôte, WSL2 Debian)

### Assembleur / linker 68k — vasm + vlink (Frank Wille)
Non packagés : compilés depuis les sources, installés dans `~/.local/bin`.

```sh
mkdir -p ~/.cache/amiga-tc && cd ~/.cache/amiga-tc
curl -fsSLO http://sun.hasenbraten.de/vasm/release/vasm.tar.gz
curl -fsSLO http://sun.hasenbraten.de/vlink/release/vlink.tar.gz
tar xzf vasm.tar.gz && tar xzf vlink.tar.gz
make -C vasm CPU=m68k SYNTAX=mot      # -> vasmm68k_mot
make -C vlink                          # -> vlink
cp vasm/vasmm68k_mot vlink/vlink ~/.local/bin/
```
Versions validées : vasm **2.0f**, vlink **V0.18a**. Option vlink utile dès M2 : `-kick1` (compat
loader Kickstart 1.x) et sorties `rawbin`/`ados`. Alternative C (modules en C plus tard) : gcc
**bebbo** `m68k-amigaos-gcc` (runtime KS1.3 : `-mcrt=nix13`).

### amitools (déjà installé, pipx)
`romtool` (info/build/split/copy de ROM, checksum), `fdtool` (LVO depuis `.fd`), `xdftool` (ADF),
`vamos` (exécution de binaires AmigaOS côté hôte — ne peut PAS héberger notre propre exec).

### Émulateur
**FS-UAE 3.2.35** (Debian) + **Xvfb** pour le boot headless / CI. Capture d'écran via `xwd` + ImageMagick
(`convert`). Côté Windows, `WinUAE.exe` (interop WSL2) reste une option, surtout pour un log série robuste
dès M2. Clés de config FS-UAE : `amiga_model`, `kickstart_file`, `chip_memory` (voir `tests/boot_test.sh`).

**Amiberry** (cœur WinUAE, compilé depuis les sources dans `~/dev/tools/amiberry`, SDL3) pour un A500 fidèle au matériel :
`--model A500 -b 2` donne 68000 cycle-exact (CPU, mémoire, blitter), OCS, PAL, 512 Ko chip + 512 Ko slow, disquette à
vitesse réelle (`--dump-config` pour vérifier). Sans interface : `-G` sous Xvfb, `SDL_AUDIODRIVER=dummy`. Série :
`-s serial_port=TCP://127.0.0.1:<port>/wait` (Amiberry attend la connexion de `socat -u TCP:127.0.0.1:<port> -`
avant de démarrer ; les PTY ne marchent pas). Suite ADF : `tests/adf_suite_amiberry.sh [rom] [secondes]`.
Recompiler : `cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j` (dépendances apt : libsdl3-dev,
libsdl3-image-dev, libflac-dev, libmpg123-dev, libpng-dev, libserialport-dev, libportmidi-dev, libenet-dev,
libpcap-dev, libcurl4-openssl-dev, nlohmann-json3-dev, libmpeg2-4-dev).

### Analyse (piste dirty)
**radare2 6.1.3** (`r2 -a m68k -e cfg.bigendian=true`, base `$FC0000`). Ghidra headless optionnel pour
le décompilateur (cf. règle ghidra-mcp : une instance dédiée par binaire).
