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

(:debug)
function runSearchAt(lat as Double, lon as Double, weekday as Number, minute as Number) as AedFinder {
    var finder = new AedFinder();
    finder.searchAt(lat, lon, weekday, minute);
    for (var i = 0; i < 500; i++) {
        if (finder.step()) {
            break;
        }
    }
    return finder;
}

(:test)
function nearestFiveInCitySorted(logger as Test.Logger) as Boolean {
    // Tuesday 10:00, offices open
    var finder = runSearchAt(47.37818d, 8.54019d, 1, 600);
    var hits = finder.hits();
    Test.assertMessage(finder.isDone(), "search not finished");
    Test.assertMessage(hits.size() >= finder.MAX_HITS, "fewer than 5 hits");
    for (var i = 1; i < finder.MAX_HITS; i++) {
        Test.assertMessage(hits[i].distM >= hits[i - 1].distM, "hits not sorted");
    }
    logger.debug("nearest = " + hits[0].distM + " m, 5th = " + hits[finder.MAX_HITS - 1].distM + " m");
    Test.assertMessage(hits[0].distM < 300, "nothing near Zurich HB");
    return true;
}

(:test)
function closedAedsFollowTheAccessibleOnes(logger as Test.Logger) as Boolean {
    // Standing at an indoor AED of the Amt für Städtebau, Zurich, open Mo-Fr 08:00-17:00
    var lat = 47.37417d;
    var lon = 8.54016d;
    var weekday = runSearchAt(lat, lon, 1, 600).hits()[0];
    Test.assertMessage(weekday.distM < 2 && weekday.title().find("Städtebau") != null, "office AED not first on Tuesday 10:00");
    Test.assertEqual(weekday.openNow, true);

    // Sunday 03:00: it moves behind the five accessible ones
    var finder = runSearchAt(lat, lon, 6, 180);
    var hits = finder.hits();
    var open = finder.MAX_HITS;
    Test.assertMessage(finder.isDone(), "search not finished");
    Test.assertMessage(hits.size() > open, "no closed AED listed");
    Test.assertMessage(hits[open].distM < 2 && hits[open].openNow == false, "closed office AED not first after the accessible ones");
    Test.assertMessage(hits.size() <= open + finder.MAX_DEMOTED, "too many hits");
    for (var i = 0; i < hits.size(); i++) {
        logger.debug(i + ": " + hits[i].distM.format("%.0f") + " m " + hits[i].title() + " [" + hits[i].hours() + "]");
        Test.assertMessage(hits[i].isDemoted() == (i >= open), "accessible and demoted AEDs mixed up");
        if (i >= open) {
            Test.assertMessage(hits[i].distM < hits[open - 1].distM, "demoted AED farther than the 5th accessible");
        }
        if (i > 0 && i != open) {
            Test.assertMessage(hits[i].distM >= hits[i - 1].distM, "hits not sorted");
        }
    }
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
