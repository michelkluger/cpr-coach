"""Pick the watches CPR Coach supports from the installed Connect IQ device profiles
and write them into watch/manifest.xml.

Criteria (the app is laid out for round screens and needs ~95 KB at peak):
  - a wrist watch (no bike computers or handhelds)
  - round display
  - at least 512 KB of memory for watch apps
  - Connect IQ API level 3.2 or newer

Usage: uv run python -I tools/select_devices.py [--dry-run]
"""

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "watch" / "manifest.xml"
DEVICES = Path(os.environ["APPDATA"]) / "Garmin" / "ConnectIQ" / "Devices"

NOT_WATCHES = ("edge", "gpsmap", "oregon", "montana", "rino", "etrex")
MIN_MEMORY = 512 * 1024
MIN_API = (3, 2, 0)


def api_level(compiler: dict) -> tuple[int, ...]:
    versions = [pn.get("connectIQVersion", "0") for pn in compiler.get("partNumbers", [])]
    return max(tuple(int(x) for x in v.split(".")) for v in versions) if versions else (0,)


def supported(device_id: str, compiler: dict) -> bool:
    memory = next((a.get("memoryLimit") or 0 for a in compiler.get("appTypes", []) if a.get("type") == "watchApp"), 0)
    return (
        not device_id.startswith(NOT_WATCHES)
        and compiler.get("deviceFamily", "").startswith("round")
        and memory >= MIN_MEMORY
        and api_level(compiler) >= MIN_API
    )


def main() -> None:
    selected = []
    for device_id in sorted(os.listdir(DEVICES)):
        path = DEVICES / device_id / "compiler.json"
        if path.exists() and supported(device_id, json.loads(path.read_text(encoding="utf-8"))):
            selected.append(device_id)
    print(f"{len(selected)} devices: {' '.join(selected)}")
    if "--dry-run" in sys.argv:
        return

    products = "\n".join(f'      <iq:product id="{d}"/>' for d in selected)
    text = MANIFEST.read_text(encoding="utf-8")
    text = re.sub(r"(<iq:products>\n).*?(\n\s*</iq:products>)", lambda m: m.group(1) + products + m.group(2), text, flags=re.S)
    MANIFEST.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
