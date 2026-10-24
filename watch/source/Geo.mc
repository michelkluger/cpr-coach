import Toybox.Lang;
import Toybox.Math;

module Geo {
    const EARTH_RADIUS_M = 6371000.0d;

    function distanceM(lat1 as Double, lon1 as Double, lat2 as Double, lon2 as Double) as Float {
        var p1 = Math.toRadians(lat1);
        var p2 = Math.toRadians(lat2);
        var dp = p2 - p1;
        var dl = Math.toRadians(lon2 - lon1);
        var a = Math.sin(dp / 2) * Math.sin(dp / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        return (2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a))).toFloat();
    }

    //! Initial bearing from point 1 to point 2, radians clockwise from true north
    function bearingRad(lat1 as Double, lon1 as Double, lat2 as Double, lon2 as Double) as Float {
        var p1 = Math.toRadians(lat1);
        var p2 = Math.toRadians(lat2);
        var dl = Math.toRadians(lon2 - lon1);
        var y = Math.sin(dl) * Math.cos(p2);
        var x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
        return Math.atan2(y, x).toFloat();
    }

    //! WGS84 to Swiss LV95 [E, N] in metres (swisstopo approximate formulas, ~1 m)
    function toLv95(lat as Double, lon as Double) as [Double, Double] {
        var phi = (lat * 3600.0d - 169028.66d) / 10000.0d;
        var lam = (lon * 3600.0d - 26782.5d) / 10000.0d;
        var e = 2600072.37d + 211455.93d * lam - 10938.51d * lam * phi - 0.36d * lam * phi * phi - 44.54d * lam * lam * lam;
        var n = 1200147.07d + 308807.95d * phi + 3745.25d * lam * lam + 76.63d * phi * phi
            - 194.56d * lam * lam * phi + 119.79d * phi * phi * phi;
        return [e, n];
    }

    //! Rough check for the area the LV95 formulas are valid in
    function inSwitzerland(lat as Double, lon as Double) as Boolean {
        return lat > 45.7d && lat < 47.9d && lon > 5.8d && lon < 10.6d;
    }

    function formatDistance(m as Float) as String {
        if (m < 1000) {
            return (Math.round(m / 10).toNumber() * 10).format("%d") + " m";
        }
        if (m < 10000) {
            return (m / 1000).format("%.1f") + " km";
        }
        return Math.round(m / 1000).toNumber().format("%d") + " km";
    }

    //! "m:ss"
    function formatDuration(ms as Number) as String {
        var s = ms / 1000;
        return (s / 60).format("%d") + ":" + (s % 60).format("%02d");
    }

    //! 2691234.4 -> "2'691'234"
    function formatSwiss(v as Double) as String {
        var n = Math.round(v).toLong();
        return (n / 1000000).format("%d") + "'" + ((n / 1000) % 1000).format("%03d") + "'" + (n % 1000).format("%03d");
    }

    function cardinal(rad as Float) as String {
        var deg = Math.toDegrees(rad).toNumber();
        deg = ((deg % 360) + 360) % 360;
        var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        return names[((deg + 22) / 45) % 8];
    }
}
