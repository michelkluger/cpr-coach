import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

//! One AED near the user. Label fields come from build_aeds.py: "title|where|hours".
class AedHit {
    public var lat as Double;
    public var lon as Double;
    public var flags as Number;
    public var distM as Float;
    private var _label as String;

    public function initialize(latitude as Double, longitude as Double, flagBits as Number, distance as Float, label as String) {
        lat = latitude;
        lon = longitude;
        flags = flagBits;
        distM = distance;
        _label = label;
    }

    public function title() as String {
        return field(0);
    }

    //! Where exactly the AED hangs, e.g. "Eingang links neben Lift"
    public function where() as String {
        return field(1);
    }

    //! Opening hours when not 24/7, "" when 24/7 or unknown
    public function hours() as String {
        return field(2);
    }

    public function isOpen24h() as Boolean {
        return (flags & 1) != 0;
    }

    public function isRestricted() as Boolean {
        return (flags & 2) != 0;
    }

    public function isIndoor() as Boolean {
        return (flags & 4) != 0;
    }

    private function field(index as Number) as String {
        var rest = _label;
        for (var i = 0; i < index; i++) {
            var sep = rest.find("|");
            if (sep == null) {
                return "";
            }
            rest = rest.substring(sep + 1, rest.length()) as String;
        }
        var end = rest.find("|");
        return end == null ? rest : rest.substring(0, end) as String;
    }
}

//! Finds the nearest AEDs in the bundled OpenStreetMap tiles without any connection.
//!
//! Tiles are 0.1 degree squares. The search scans rings of tiles around the
//! user and stops once the k-th nearest AED is closer than any unscanned tile.
//! Work is split into steps so a dense city tile never trips the watchdog.
class AedFinder {
    public const MAX_HITS = 5;
    //! 6 rings = 0.6 degree, roughly 45-65 km in Switzerland
    private const MAX_RING = 6;
    private const AEDS_PER_STEP = 800;
    private const E5_PER_TILE = 10000;
    //! Metres per 1e-5 degree of latitude
    private const M_PER_E5 = 1.11195;

    private var _lat as Double = 0.0d;
    private var _lon as Double = 0.0d;
    private var _latE5 as Number = 0;
    private var _lonE5 as Number = 0;
    private var _cosLat as Float = 1.0;
    private var _centerLat as Number = 0;
    private var _centerLon as Number = 0;
    private var _ring as Number = 0;
    private var _queue as Array<[Number, Number]> = [] as Array<[Number, Number]>;
    private var _next as Number = 0;
    private var _hits as Array<AedHit> = [] as Array<AedHit>;
    private var _searched as Boolean = false;
    private var _done as Boolean = true;

    public function initialize() {
    }

    //! True before the first search or once the user moved more than 25 m
    public function needsSearch(lat as Double, lon as Double) as Boolean {
        return !_searched || Geo.distanceM(_lat, _lon, lat, lon) > 25;
    }

    public function search(lat as Double, lon as Double) as Void {
        _lat = lat;
        _lon = lon;
        _latE5 = Math.round(lat * 100000).toNumber();
        _lonE5 = Math.round(lon * 100000).toNumber();
        _cosLat = Math.cos(Math.toRadians(lat)).toFloat();
        _centerLat = Math.floor(lat * AedIndex.TILES_PER_DEG).toNumber();
        _centerLon = Math.floor(lon * AedIndex.TILES_PER_DEG).toNumber();
        _ring = 0;
        _queue = [[_centerLat, _centerLon]] as Array<[Number, Number]>;
        _next = 0;
        _hits = [] as Array<AedHit>;
        _searched = true;
        _done = false;
    }

    //! Scan tiles until about AEDS_PER_STEP AEDs were checked. Returns true when the search is complete.
    public function step() as Boolean {
        var scanned = 0;
        while (!_done && scanned < AEDS_PER_STEP) {
            if (_next >= _queue.size()) {
                if (isSettled() || _ring >= MAX_RING) {
                    _done = true;
                    break;
                }
                _ring++;
                _queue = ringTiles(_ring);
                _next = 0;
            }
            var tile = _queue[_next];
            _next++;
            scanned += scanTile(tile[0], tile[1]);
        }
        return _done;
    }

    public function isDone() as Boolean {
        return _done;
    }

    public function isSearched() as Boolean {
        return _searched;
    }

    //! Nearest AEDs found so far, closest first
    public function hits() as Array<AedHit> {
        return _hits;
    }

    //! Scans every part of a tile; returns the number of AEDs checked.
    //! Resources are shared by neighbouring tiles, keyed by the tile key.
    private function scanTile(latIdx as Number, lonIdx as Number) as Number {
        var resources = AedIndex.tileResources(latIdx, lonIdx);
        if (resources == null) {
            return 0;
        }
        var key = AedIndex.tileKey(latIdx, lonIdx).toString();
        var scanned = 0;
        for (var i = 0; i < resources.size(); i++) {
            var content = WatchUi.loadResource(resources[i]) as Dictionary<String, Array<Array> >;
            var part = content[key];
            if (part != null) {
                scanned += scanPart(part, latIdx * E5_PER_TILE, lonIdx * E5_PER_TILE);
            }
        }
        return scanned;
    }

    private function scanPart(part as Array<Array>, originLat as Number, originLon as Number) as Number {
        var packed = part[0] as Array<Number>;
        var labels = part[1] as Array<String>;
        var kx = M_PER_E5 * _cosLat;
        var worst = worstDistanceSq();

        for (var i = 0; i < packed.size(); i++) {
            var p = packed[i];
            var latE5 = originLat + (p >> 17);
            var lonE5 = originLon + ((p >> 3) & 0x3FFF);
            var dy = (latE5 - _latE5) * M_PER_E5;
            var dx = (lonE5 - _lonE5) * kx;
            var d2 = dy * dy + dx * dx;
            if (d2 < worst) {
                insert(new AedHit(latE5 / 100000.0d, lonE5 / 100000.0d, p & 7, Math.sqrt(d2).toFloat(), labels[i]));
                worst = worstDistanceSq();
            }
        }
        return packed.size();
    }

    private function insert(hit as AedHit) as Void {
        var i = _hits.size();
        while (i > 0 && _hits[i - 1].distM > hit.distM) {
            i--;
        }
        var head = _hits.slice(0, i);
        head.add(hit);
        _hits = head.addAll(_hits.slice(i, _hits.size()));
        if (_hits.size() > MAX_HITS) {
            _hits = _hits.slice(0, MAX_HITS);
        }
    }

    private function worstDistanceSq() as Float {
        if (_hits.size() < MAX_HITS) {
            return 1.0e15;
        }
        var d = _hits[MAX_HITS - 1].distM;
        return d * d;
    }

    //! Every unscanned tile is farther away than the current k-th hit
    private function isSettled() as Boolean {
        if (_hits.size() < MAX_HITS) {
            return false;
        }
        var north = ((_centerLat + _ring + 1) * E5_PER_TILE - _latE5) * M_PER_E5;
        var south = (_latE5 - (_centerLat - _ring) * E5_PER_TILE) * M_PER_E5;
        var east = ((_centerLon + _ring + 1) * E5_PER_TILE - _lonE5) * M_PER_E5 * _cosLat;
        var west = (_lonE5 - (_centerLon - _ring) * E5_PER_TILE) * M_PER_E5 * _cosLat;
        var bound = north;
        if (south < bound) { bound = south; }
        if (east < bound) { bound = east; }
        if (west < bound) { bound = west; }
        return _hits[MAX_HITS - 1].distM <= bound;
    }

    //! Tiles exactly r steps away (Chebyshev distance) from the centre tile
    private function ringTiles(r as Number) as Array<[Number, Number]> {
        var tiles = [] as Array<[Number, Number]>;
        for (var dy = -r; dy <= r; dy++) {
            if (dy == -r || dy == r) {
                for (var dx = -r; dx <= r; dx++) {
                    tiles.add([_centerLat + dy, _centerLon + dx]);
                }
            } else {
                tiles.add([_centerLat + dy, _centerLon - r]);
                tiles.add([_centerLat + dy, _centerLon + r]);
            }
        }
        return tiles;
    }
}
