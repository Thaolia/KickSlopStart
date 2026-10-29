# Tests & test bench

## boot_test.sh - headless boot of a ROM under FS-UAE

Starts FS-UAE in an Xvfb virtual display, lets the ROM boot, captures the emulated screen and reports the
dominant colours. For the M0 hello-ROM, a **green background** confirms that the coldstart wrote COLOR00
(hence that our code runs on the emulated A500).

```sh
tests/boot_test.sh [path/to/rom] [boot_seconds]
# default: build/kick13-hello.rom, 10 s
```

Prerequisites: `fs-uae`, `Xvfb`, `xwd`, `convert` (ImageMagick). Outputs in `build/boot/`:
`hello.fs-uae` (generated config), `fs-uae.log`, `screen.png` (capture).

Expected M0 result: dominant colour `#00FF00` (green) over the active area, FS-UAE log
"KS ROM ... (262144 bytes)" without errors.

## Coming next (from M2)

Capture of the **serial log** (SERDAT register) as the primary assertion channel, serial markers per
milestone, and black-box oracle comparison against the real KS 1.3 (targeted behavioural probes).

## Clean-room audit - audit_rom_similarity.py, audit_aros_similarity.py

Similarity measurements published in [docs/AUDIT.md](../docs/AUDIT.md) (summary) and `docs/audit/` (details). Both
tools only print statistics and locations in the first argument (our code).

```sh
python3 -I tests/audit_rom_similarity.py build/kick13-prod.rom <reference_kick13_rom> [--temoin NAME files...] [--selftest]
python3 -I tests/audit_aros_similarity.py src <aros_clone>
```
