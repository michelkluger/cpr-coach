import Toybox.Lang;
import Toybox.Test;

(:debug)
function runSearch(lat as Double, lon as Double) as AedFinder {
    var finder = new AedFinder();
    finder.search(lat, lon);
    for (var i = 0; i < 500; i++) {
        if (finder.step()) {
            break;
        }
    }
    return finder;
}

(:test)
function findsKnownAedAtItsLocation(logger as Test.Logger) as Boolean {
    // Gemeinde Staefa, facade of Schulhaus Nord, tagged 24/7 in OSM
    var finder = runSearch(47.2398129d, 8.730395d);
    Test.assertMessage(finder.isDone(), "search not finished");
    var hit = finder.hits()[0];
    logger.debug(hit.title() + " / " + hit.where() + " / " + hit.distM + " m");
    Test.assertMessage(hit.distM < 2, "nearest AED not at the known location");
    Test.assertMessage(hit.title().find("Stäfa") != null, "wrong title");
    Test.assertMessage(hit.isOpen24h(), "should be 24/7");
    Test.assertMessage(!hit.isRestricted(), "should be public");
    return true;
}

(:test)
function nearestFiveInCitySorted(logger as Test.Logger) as Boolean {
    var finder = runSearch(47.37818d, 8.54019d);
    var hits = finder.hits();
    Test.assertMessage(finder.isDone(), "search not finished");
    Test.assertEqual(hits.size(), finder.MAX_HITS);
    for (var i = 1; i < hits.size(); i++) {
        Test.assertMessage(hits[i].distM >= hits[i - 1].distM, "hits not sorted");
    }
    logger.debug("nearest = " + hits[0].distM + " m, 5th = " + hits[hits.size() - 1].distM + " m");
    Test.assertMessage(hits[0].distM < 300, "nothing near Zurich HB");
    return true;
}

(:test)
function fastDistanceMatchesHaversine(logger as Test.Logger) as Boolean {
    var finder = runSearch(46.50d, 8.03d);
    var hits = finder.hits();
    Test.assertMessage(finder.isDone(), "search not finished");
    Test.assertMessage(hits.size() > 0, "no AED in the Alps");
    var hit = hits[hits.size() - 1];
    var exact = Geo.distanceM(46.50d, 8.03d, hit.lat, hit.lon);
    logger.debug("remote: " + hits.size() + " hits, farthest " + hit.distM + " m vs " + exact + " m");
    Test.assertMessage(hit.distM < 60000, "farther than the search radius");
    Test.assertMessage((hit.distM - exact).abs() / exact < 0.01, "fast distance off by > 1%");
    return true;
}

(:test)
function emptyOutsideTheData(logger as Test.Logger) as Boolean {
    var finder = runSearch(0.5d, -30.5d);
    Test.assertMessage(finder.isDone(), "search not finished");
    Test.assertEqual(finder.hits().size(), 0);
    return true;
}

(:test)
function hitLabelFields(logger as Test.Logger) as Boolean {
    var hit = new AedHit(47.0d, 8.0d, 6, 10.0, "Gemeindehaus|Eingang links||");
    Test.assertEqual(hit.title(), "Gemeindehaus");
    Test.assertEqual(hit.where(), "Eingang links");
    Test.assertEqual(hit.hours(), "");
    Test.assertMessage(!hit.isOpen24h(), "flag 24/7");
    Test.assertMessage(hit.isRestricted(), "flag restricted");
    Test.assertMessage(hit.isIndoor(), "flag indoor");
    return true;
}
