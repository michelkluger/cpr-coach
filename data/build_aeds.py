"""Build the offline AED dataset bundled into the watch app.

Fetches every `emergency=defibrillator` in Switzerland and Liechtenstein from
OpenStreetMap (Overpass), splits them into 0.1-degree tiles and writes:

  watch/resources/aed/aed.xml          jsonData resource declarations
  watch/resources/aed/tiles/*.json     bin-packed resources (< 8 KB, <= 250 of them):
                                       {"<tile key>": [[packed...], [label...]], ...}
  watch/source/AedIndex.mc             tile -> resources lookup + dataset metadata

Packed AED (32-bit signed int, always positive):
  bits 17..30  latitude offset inside the tile, 1e-5 degrees (0..10000)
  bits  3..16  longitude offset inside the tile, 1e-5 degrees (0..10000)
  bit   2      indoor
  bit   1      restricted access (private / customers / ...)
  bit   0      open 24/7

Label: "title|where|hours" (hours empty when 24/7 or unknown).

Usage: uv run python -I data/build_aeds.py [--refresh]
"""

import datetime as dt
import json
import math
import shutil
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "aeds_ch_li.json"
RES_DIR = ROOT / "watch" / "resources" / "aed"
TILE_DIR = RES_DIR / "tiles"
INDEX_MC = ROOT / "watch" / "source" / "AedIndex.mc"

OVERPASS = "https://overpass-api.de/api/interpreter"
QUERY = """
[out:json][timeout:170];
(area["ISO3166-1"="CH"][admin_level=2];area["ISO3166-1"="LI"][admin_level=2];)->.a;
(node["emergency"="defibrillator"](area.a);way["emergency"="defibrillator"](area.a););
out center tags;
"""

TILES_PER_DEG = 10
E5_PER_TILE = 100_000 // TILES_PER_DEG
# Keys must stay positive for any lat/lon so the watch code needs no special cases.
LAT_IDX_OFFSET = 90 * TILES_PER_DEG
LON_IDX_OFFSET = 180 * TILES_PER_DEG
KEY_STRIDE = 360 * TILES_PER_DEG + 1

FLAG_24_7 = 1
FLAG_RESTRICTED = 2
FLAG_INDOOR = 4

RESTRICTED_ACCESS = {"private", "no", "customers", "permit", "employees", "permissive_customers"}
INDOOR_VALUES = {"yes", "room", "area", "corridor", "level"}

# Serialized JSON bytes per resource. The compiler warns above 8 KB and its
# serialized form is a bit larger than the JSON text.
CHUNK_BYTES = 6500
# Devices on API level 3.x allow at most 254 members in Rez.JsonData
MAX_RESOURCES = 250

MAX_TITLE = 32
MAX_WHERE = 64
MAX_HOURS = 40


def fetch(refresh: bool) -> dict:
    if RAW.exists() and not refresh:
        return json.loads(RAW.read_text(encoding="utf-8"))
    body = urllib.parse.urlencode({"data": QUERY}).encode()
    req = urllib.request.Request(OVERPASS, data=body, headers={"User-Agent": "cpr-coach-data/0.1"})
    with urllib.request.urlopen(req, timeout=200) as resp:
        raw = resp.read()
    RAW.parent.mkdir(parents=True, exist_ok=True)
    RAW.write_bytes(raw)
    return json.loads(raw)


def clean(text: str | None, limit: int) -> str:
    if not text:
        return ""
    text = " ".join(text.replace("|", "/").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def first_tag(tags: dict, *keys: str) -> str | None:
    for key in keys:
        if tags.get(key):
            return tags[key]
    return None


def label(tags: dict) -> str:
    street = " ".join(filter(None, [tags.get("addr:street"), tags.get("addr:housenumber")]))
    title = first_tag(tags, "name", "operator") or street or "AED"
    where = first_tag(
        tags,
        "defibrillator:location",
        "defibrillator:location:de",
        "defibrillator:location:fr",
        "defibrillator:location:it",
        "defibrillator:location:en",
        "description",
    )
    hours = tags.get("opening_hours")
    if hours == "24/7":
        hours = None
    return "|".join([clean(title, MAX_TITLE), clean(where, MAX_WHERE), clean(hours, MAX_HOURS)])


def flags(tags: dict) -> int:
    value = 0
    if tags.get("opening_hours") == "24/7":
        value |= FLAG_24_7
    if tags.get("access") in RESTRICTED_ACCESS:
        value |= FLAG_RESTRICTED
    if tags.get("indoor") in INDOOR_VALUES:
        value |= FLAG_INDOOR
    return value


def tile_index(deg: float) -> int:
    return math.floor(deg * TILES_PER_DEG)


def pack(lat: float, lon: float, flag_bits: int) -> tuple[int, int, int]:
    lat_idx, lon_idx = tile_index(lat), tile_index(lon)
    lat_off = round((lat - lat_idx / TILES_PER_DEG) * 100_000)
    lon_off = round((lon - lon_idx / TILES_PER_DEG) * 100_000)
    assert 0 <= lat_off <= E5_PER_TILE and 0 <= lon_off <= E5_PER_TILE, (lat, lon)
    packed = (lat_off << 17) | (lon_off << 3) | flag_bits
    assert 0 <= packed < 2**31
    return lat_idx, lon_idx, packed


def unpack(lat_idx: int, lon_idx: int, packed: int) -> tuple[float, float, int]:
    lat = lat_idx / TILES_PER_DEG + (packed >> 17) / 100_000
    lon = lon_idx / TILES_PER_DEG + ((packed >> 3) & 0x3FFF) / 100_000
    return lat, lon, packed & 7


def tile_key(lat_idx: int, lon_idx: int) -> int:
    return (lat_idx + LAT_IDX_OFFSET) * KEY_STRIDE + (lon_idx + LON_IDX_OFFSET)


def res_id(lat_idx: int, lon_idx: int) -> str:
    return f"aed_{lat_idx}_{lon_idx}".replace("-", "m")


def build(data: dict) -> None:
    tiles: dict[tuple[int, int], list[tuple[int, str]]] = {}
    for el in data["elements"]:
        lat = el.get("lat", el.get("center", {}).get("lat"))
        lon = el.get("lon", el.get("center", {}).get("lon"))
        if lat is None or lon is None:
            continue
        tags = el.get("tags", {})
        lat_idx, lon_idx, packed = pack(lat, lon, flags(tags))
        tiles.setdefault((lat_idx, lon_idx), []).append((packed, label(tags)))

    if TILE_DIR.exists():
        shutil.rmtree(TILE_DIR)
    TILE_DIR.mkdir(parents=True)

    # Bin-pack tile pieces into resources of at most CHUNK_BYTES, each a JSON
    # object {"<tile key>": [[packed...], [label...]], ...}. Small neighbouring
    # tiles share a resource, dense tiles span several.
    bins: list[dict[str, list]] = []
    current: dict[str, list] = {}
    tile_bins: dict[int, list[int]] = {}
    for (lat_idx, lon_idx), aeds in sorted(tiles.items()):
        aeds.sort()
        key = tile_key(lat_idx, lon_idx)
        for piece in chunked(aeds):
            payload = [[p for p, _ in piece], [l for _, l in piece]]
            if current and (str(key) in current or bin_bytes({**current, str(key): payload}) > CHUNK_BYTES):
                bins.append(current)
                current = {}
            current[str(key)] = payload
            tile_bins.setdefault(key, [])
            if not tile_bins[key] or tile_bins[key][-1] != len(bins):
                tile_bins[key].append(len(bins))
    bins.append(current)
    assert len(bins) <= MAX_RESOURCES, f"{len(bins)} resources exceed the {MAX_RESOURCES} limit of API 3.x devices"

    for n, content in enumerate(bins):
        (TILE_DIR / f"aed_{n}.json").write_text(
            json.dumps(content, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
        )
    entries = [(key, [f"aed_{n}" for n in ns]) for key, ns in tile_bins.items()]

    xml = ['<jsonDataResources>']
    xml += [f'    <jsonData id="aed_{n}" filename="tiles/aed_{n}.json" />' for n in range(len(bins))]
    xml.append("</jsonDataResources>\n")
    (RES_DIR / "aed.xml").write_text("\n".join(xml), encoding="utf-8")

    count = sum(len(a) for a in tiles.values())
    stamp = data.get("osm3s", {}).get("timestamp_osm_base", dt.datetime.now(dt.UTC).isoformat())[:10]
    lines = [
        "// Generated by data/build_aeds.py - do not edit.",
        "// AED locations (c) OpenStreetMap contributors, ODbL.",
        "",
        "import Toybox.Lang;",
        "",
        "module AedIndex {",
        f"    const TILES_PER_DEG = {TILES_PER_DEG};",
        f"    const LAT_IDX_OFFSET = {LAT_IDX_OFFSET};",
        f"    const LON_IDX_OFFSET = {LON_IDX_OFFSET};",
        f"    const KEY_STRIDE = {KEY_STRIDE};",
        f'    const DATA_DATE = "{stamp}";',
        f"    const AED_COUNT = {count};",
        "",
        "    var _tiles as Dictionary<Number, Array<ResourceId> >?;",
        "",
        "    function tileKey(latIdx as Number, lonIdx as Number) as Number {",
        "        return (latIdx + LAT_IDX_OFFSET) * KEY_STRIDE + (lonIdx + LON_IDX_OFFSET);",
        "    }",
        "",
        "    //! Resources holding parts of tile (latIdx, lonIdx), or null when the tile is empty.",
        "    //! Each resource is a Dictionary keyed by tileKey().toString().",
        "    function tileResources(latIdx as Number, lonIdx as Number) as Array<ResourceId>? {",
        "        if (_tiles == null) {",
        "            _tiles = {",
    ]
    for key, chunk_ids in entries:
        refs = ", ".join(f"$.Rez.JsonData.{rid}" for rid in chunk_ids)
        lines.append(f"                {key} => [{refs}],")
    lines += [
        "            };",
        "        }",
        "        return (_tiles as Dictionary<Number, Array<ResourceId> >)[tileKey(latIdx, lonIdx)];",
        "    }",
        "}",
        "",
    ]
    INDEX_MC.parent.mkdir(parents=True, exist_ok=True)
    INDEX_MC.write_text("\n".join(lines), encoding="utf-8")

    sizes = sorted(((len(a), res_id(la, lo)) for (la, lo), a in tiles.items()), reverse=True)
    files = list(TILE_DIR.iterdir())
    total_bytes = sum(p.stat().st_size for p in files)
    largest = max(p.stat().st_size for p in files)
    print(f"{count} AEDs in {len(tiles)} tiles / {len(files)} resources, {total_bytes / 1024:.0f} KiB of JSON, "
          f"largest {largest} B (OSM {stamp})")
    print("densest tiles:", ", ".join(f"{rid}={n}" for n, rid in sizes[:5]))


def bin_bytes(content: dict) -> int:
    return len(json.dumps(content, ensure_ascii=False, separators=(",", ":")).encode())


def serialize(aeds: list[tuple[int, str]]) -> str:
    payload = [[p for p, _ in aeds], [l for _, l in aeds]]
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def chunked(aeds: list[tuple[int, str]]) -> list[list[tuple[int, str]]]:
    """Split a tile so each resource stays under the compiler's 8 KB guideline."""
    chunks, current = [], []
    for aed in aeds:
        if current and len(serialize(current + [aed]).encode()) > CHUNK_BYTES:
            chunks.append(current)
            current = []
        current.append(aed)
    chunks.append(current)
    return chunks


def self_check() -> None:
    for lat, lon in [(47.39901, 8.61702), (45.81802, 5.95591), (47.80845, 10.49203), (47.0, 8.0)]:
        la, lo, p = pack(lat, lon, 5)
        lat2, lon2, f = unpack(la, lo, p)
        assert abs(lat2 - lat) < 6e-6 and abs(lon2 - lon) < 6e-6 and f == 5, (lat, lon, lat2, lon2)


if __name__ == "__main__":
    self_check()
    build(fetch(refresh="--refresh" in sys.argv))
