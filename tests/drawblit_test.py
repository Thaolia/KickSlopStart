#!/usr/bin/env python3
"""Run the native graphics regression on our production ROM in Copperline."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--copperline", default=os.environ.get("COPPERLINE", "copperline"))
    parser.add_argument("--ctl", default=os.environ.get("COPPERLINE_CTL", "copperline-ctl"))
    parser.add_argument("--allow-slow", action="store_true", help="collect the CPU baseline")
    parser.add_argument("--seconds", type=int, default=240)
    parser.add_argument("--fast", default="0", help="Amiga fast RAM size")
    parser.add_argument("--tag", default="DRAWBLIT")
    parser.add_argument("--pass-marker")
    parser.add_argument("--workloads", nargs="*", default=["LINE", "FILL", "CLEAR", "SHORT", "AREA"])
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    info = subprocess.check_output(["romtool", "info", str(args.rom.resolve())], text=True)
    for field in ("is_kick", "chk_sum"):
        if not re.search(rf"^{field}\s+ok$", info, re.M):
            raise SystemExit(f"Invalid ROM: {field}")
    disk = out / "drawblit.adf"
    subprocess.run([args.ctl, "exe2adf", str(args.exe.resolve()), "--boot", "--out", str(disk)], check=True)
    config = out / "machine.toml"
    config.write_text(f'''rom = {json.dumps(str(args.rom.resolve()))}
identify = false
[machine]
profile = "A500"
[memory]
chip = "512K"
slow = "512K"
fast = {json.dumps(args.fast)}
[floppy.df0]
path = {json.dumps(str(disk))}
[serial]
mode = "stdout"
[audio]
floppy_sounds = false
''')
    command = [args.copperline, "--config", str(config), "--chipset", "OCS", "--noaudio", "--floppy-speed", "0",
               "--screenshot-after", str(args.seconds), str(out / "screen.png")]
    ledger = out / "session.json"
    with (out / "serial.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        session = {"command": command, "pid": process.pid, "started": time.time(), "state": "running"}
        ledger.write_text(json.dumps(session, indent=2) + "\n")
        try:
            process.wait(timeout=180)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            session.update(state="completed", returncode=process.returncode)
            ledger.write_text(json.dumps(session, indent=2) + "\n")
    output = (out / "serial.log").read_text(errors="replace")
    marker = args.pass_marker or f"{args.tag} PIXELS OK"
    if process.returncode or f"{args.tag} FAIL" in output or marker not in output or f"{args.tag} END" not in output:
        raise SystemExit(f"Native regression failed; see {out / 'serial.log'}")
    results = {}
    for name in args.workloads:
        match = re.search(rf"{re.escape(args.tag)} {re.escape(name)} ([0-9A-F]{{8}}) ([0-9A-F]{{8}})", output)
        if not match:
            raise SystemExit(f"Missing {name} timing")
        chip, cpu = (int(value, 16) for value in match.groups())
        if chip <= 0 or cpu <= 0:
            raise SystemExit(f"Invalid {name} timing")
        results[name.lower()] = {"chip_scanlines": chip, "cpu_scanlines": cpu, "speedup": cpu / chip}
        print(f"{name}: CHIP {chip}, CPU {cpu} scanlines, {cpu / chip:.2f}x")
    (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print("Pixels, guards and RastPort state match the CPU fallback." if args.workloads else marker)
    if not args.allow_slow and any(result["speedup"] < 1.25 for result in results.values()):
        raise SystemExit("Expected at least 1.25x acceleration for every workload")


if __name__ == "__main__":
    main()
