import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! One AED near the user. Label fields come from build_aeds.py: "title|where|hours".
class AedHit {
    public var lat as Double;
    public var lon as Double;
    public var flags as Number;
    public var distM as Float;
    //! Open at search time per its hours; null when they are unknown or not understood
    public var openNow as Boolean?;
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

    //! Probably out of reach right now: listed after the accessible AEDs. Outdoor AEDs
    //! stay accessible whatever the hours say, which then belong to the building.
    public function isDemoted() as Boolean {
        return isRestricted() || (isIndoor() && openNow == false);
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
//! user and stops once the k-th nearest accessible AED is closer than any
//! unscanned tile. Closed or restricted AEDs nearer than that one follow at the
//! end of the list. Work is split into steps so a dense city tile never trips
//! the watchdog.
class AedFinder {
    public const MAX_HITS = 5;
    public const MAX_DEMOTED = 5;
    //! 6 rings = 0.6 degree, roughly 45-65 km in Switzerland
    private const MAX_RING = 6;
    //! Work units per step (one per AED checked) and what reading one opening hours costs
    private const WORK_PER_STEP = 800;
    private const PARSE_WORK = 60;
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
    //! Next resource of the current tile
    private var _part as Number = 0;
    private var _open as Array<AedHit> = [] as Array<AedHit>;
    private var _demoted as Array<AedHit> = [] as Array<AedHit>;
    private var _hits as Array<AedHit> = [] as Array<AedHit>;
    private var _weekday as Number = 0;
    private var _minute as Number = 0;
    private var _openByHours as Dictionary<String, Boolean?> = {} as Dictionary<String, Boolean?>;
    private var _searched as Boolean = false;
    private var _done as Boolean = true;

    public function initialize() {
    }

    //! True before the first search or once the user moved more than 25 m
    public function needsSearch(lat as Double, lon as Double) as Boolean {
        return !_searched || Geo.distanceM(_lat, _lon, lat, lon) > 25;
    }

    //! shortcut: opening hours are judged when the search starts, so an AED that
    //! closes while the page stays open keeps its place until the user moves 25 m.
    public function search(lat as Double, lon as Double) as Void {
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        // day_of_week is 1 for Sunday; Hours counts from Monday
        searchAt(lat, lon, ((now.day_of_week as Number) + 5) % 7, (now.hour as Number) * 60 + (now.min as Number));
    }

    //! search() at a given time: weekday 0 = Monday, minute of the day
    public function searchAt(lat as Double, lon as Double, weekday as Number, minute as Number) as Void {
        _weekday = weekday;
        _minute = minute;
        _openByHours = {} as Dictionary<String, Boolean?>;
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
        _part = 0;
        _open = [] as Array<AedHit>;
        _demoted = [] as Array<AedHit>;
        _hits = [] as Array<AedHit>;
        _searched = true;
        _done = false;
    }

    //! Scan tile parts until about WORK_PER_STEP was spent. Returns true when the search is complete.
    //! Dense tiles span several resources, so a step can stop in the middle of a tile.
    public function step() as Boolean {
        var work = 0;
        while (!_done && work < WORK_PER_STEP) {
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
            var resources = AedIndex.tileResources(tile[0], tile[1]);
            if (resources != null && _part < resources.size()) {
                work += scanResource(tile[0], tile[1], resources[_part]);
                _part++;
            }
            if (resources == null || _part >= resources.size()) {
                _next++;
                _part = 0;
            }
            work++;
        }
        return _done;
    }

    public function isDone() as Boolean {
        return _done;
    }

    public function isSearched() as Boolean {
        return _searched;
    }

    //! Nearest accessible AEDs found so far, closest first, then the nearer demoted ones
    public function hits() as Array<AedHit> {
        return _hits;
    }

    //! Scans the tile's part in one resource; returns the work spent.
    //! Resources are shared by neighbouring tiles, keyed by the tile key.
    private function scanResource(latIdx as Number, lonIdx as Number, resource as ResourceId) as Number {
        var content = WatchUi.loadResource(resource) as Dictionary<String, Array<Array> >;
        var part = content[AedIndex.tileKey(latIdx, lonIdx).toString()];
        return part != null ? scanPart(part, latIdx * E5_PER_TILE, lonIdx * E5_PER_TILE) : 0;
    }

    //! Work: one unit per AED checked, n per nearest-first pick, PARSE_WORK per hours read
    private function scanPart(part as Array<Array>, originLat as Number, originLon as Number) as Number {
        var packed = part[0] as Array<Number>;
        var labels = part[1] as Array<String>;
        var kx = M_PER_E5 * _cosLat;
        var n = packed.size();
        var d2s = new [n] as Array<Float>;
        for (var i = 0; i < n; i++) {
            var p = packed[i];
            var dy = (originLat + (p >> 17) - _latE5) * M_PER_E5;
            var dx = (originLon + ((p >> 3) & 0x3FFF) - _lonE5) * kx;
            d2s[i] = dy * dy + dx * dx;
        }

        // Nearest first, so reading the opening hours (slow on the watch) stops
        // as soon as the part can't improve the list anymore
        var worst = worstDistanceSq();
        var work = n;
        while (true) {
            var best = -1;
            for (var i = 0; i < n; i++) {
                if (d2s[i] < worst && (best < 0 || d2s[i] < d2s[best])) {
                    best = i;
                }
            }
            work += n;
            if (best < 0) {
                break;
            }
            var p = packed[best];
            var latE5 = originLat + (p >> 17);
            var lonE5 = originLon + ((p >> 3) & 0x3FFF);
            var hit = new AedHit(latE5 / 100000.0d, lonE5 / 100000.0d, p & 7, Math.sqrt(d2s[best]).toFloat(), labels[best]);
            if (hit.isOpen24h()) {
                hit.openNow = true;
            } else if (hit.isIndoor() && !hit.isRestricted()) {
                // Only where the hours decide the order; outdoor AEDs stay accessible anyway.
                // Office AEDs share a few hours strings, so each is read once per search.
                var hours = hit.hours();
                if (!_openByHours.hasKey(hours)) {
                    _openByHours[hours] = Hours.isOpen(hours, _weekday, _minute);
                    work += PARSE_WORK;
                }
                hit.openNow = _openByHours[hours];
            }
            insert(hit);
            d2s[best] = 1.0e30;
            worst = worstDistanceSq();
        }
        return work;
    }

    private function insert(hit as AedHit) as Void {
        if (hit.isDemoted()) {
            _demoted = insertSorted(_demoted, hit, MAX_DEMOTED);
        } else {
            _open = insertSorted(_open, hit, MAX_HITS);
        }
        var limit = _open.size() < MAX_HITS ? 1.0e9 : _open[MAX_HITS - 1].distM;
        _hits = _open.slice(0, _open.size());
        for (var i = 0; i < _demoted.size() && _demoted[i].distM < limit; i++) {
            _hits.add(_demoted[i]);
        }
    }

    private function insertSorted(list as Array<AedHit>, hit as AedHit, max as Number) as Array<AedHit> {
        var i = list.size();
        while (i > 0 && list[i - 1].distM > hit.distM) {
            i--;
        }
        if (i >= max) {
            return list;
        }
        var head = list.slice(0, i);
        head.add(hit);
        head.addAll(list.slice(i, list.size()));
        return head.size() > max ? head.slice(0, max) : head;
    }

    private function worstDistanceSq() as Float {
        if (_open.size() < MAX_HITS) {
            return 1.0e15;
        }
        var d = _open[MAX_HITS - 1].distM;
        return d * d;
    }

    //! Every unscanned tile is farther away than the current k-th accessible hit
    private function isSettled() as Boolean {
        if (_open.size() < MAX_HITS) {
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
        return _open[MAX_HITS - 1].distM <= bound;
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
