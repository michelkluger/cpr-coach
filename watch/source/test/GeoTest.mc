import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

(:test)
function distanceZurichBern(logger as Test.Logger) as Boolean {
    var d = Geo.distanceM(47.37818d, 8.54019d, 46.94883d, 7.43913d);
    logger.debug("d = " + d);
    Test.assertMessage((d - 95960.0).abs() < 50, "Zurich-Bern distance off");
    return true;
}

(:test)
function bearingCardinals(logger as Test.Logger) as Boolean {
    var north = Geo.bearingRad(47.0d, 8.0d, 47.1d, 8.0d);
    var east = Geo.bearingRad(47.0d, 8.0d, 47.0d, 8.1d);
    logger.debug("north = " + north + ", east = " + east);
    Test.assertMessage(north.abs() < 0.001, "north bearing off");
    Test.assertMessage((east - Math.PI / 2).abs() < 0.01, "east bearing off");
    Test.assertEqual(Geo.cardinal(north), "N");
    Test.assertEqual(Geo.cardinal(east), "E");
    Test.assertEqual(Geo.cardinal(-2.4), "SW");
    return true;
}

//! swisstopo's worked example for the approximate WGS84 -> LV95 formulas
(:test)
function lv95MatchesSwisstopo(logger as Test.Logger) as Boolean {
    var lv95 = Geo.toLv95(46.0441305556d, 8.7304972222d);
    logger.debug("E = " + lv95[0] + ", N = " + lv95[1]);
    Test.assertMessage((lv95[0] - 2700000.0d).abs() < 1.0, "E off");
    Test.assertMessage((lv95[1] - 1100000.0d).abs() < 1.0, "N off");
    return true;
}

(:test)
function formatting(logger as Test.Logger) as Boolean {
    Test.assertEqual(Geo.formatDistance(243.0), "240 m");
    Test.assertEqual(Geo.formatDistance(1430.0), "1.4 km");
    Test.assertEqual(Geo.formatDistance(23400.0), "23 km");
    Test.assertEqual(Geo.formatDuration(125000), "2:05");
    Test.assertEqual(Geo.formatSwiss(2691234.4d), "2'691'234");
    Test.assertEqual(Geo.formatSwiss(1048765.6d), "1'048'766");
    return true;
}
