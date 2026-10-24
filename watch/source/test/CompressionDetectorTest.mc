import Toybox.Lang;
import Toybox.Test;

(:debug)
function assertRate(logger as Test.Logger, rate as Number?, low as Number, high as Number) as Void {
    logger.debug("rate = " + rate);
    Test.assertMessage(rate != null, "no rate");
    var r = rate as Number;
    Test.assertMessage(r >= low, "rate below " + low);
    Test.assertMessage(r <= high, "rate above " + high);
}

(:test)
function detectsGuidelineRate(logger as Test.Logger) as Boolean {
    var det = new CompressionDetector(SyntheticCpr.RATE_HZ);
    var wall = SyntheticCpr.feed(det, 0, 10, 110.0, 5.0, 0, 0.0);
    logger.debug("count = " + det.count());
    assertRate(logger, det.rate(wall), 108, 112);
    Test.assertMessage(det.count() >= 16, "too few compressions");
    Test.assertMessage(det.count() <= 19, "too many compressions");
    Test.assertMessage(det.isCompressing(wall), "not compressing");
    return true;
}

(:test)
function detectsSlowRate(logger as Test.Logger) as Boolean {
    var det = new CompressionDetector(SyntheticCpr.RATE_HZ);
    var wall = SyntheticCpr.feed(det, 0, 10, 80.0, 5.0, 0, 0.0);
    assertRate(logger, det.rate(wall), 78, 82);
    return true;
}

(:test)
function detectsFastRate(logger as Test.Logger) as Boolean {
    var det = new CompressionDetector(SyntheticCpr.RATE_HZ);
    var wall = SyntheticCpr.feed(det, 0, 10, 140.0, 5.0, 0, 0.0);
    assertRate(logger, det.rate(wall), 137, 143);
    return true;
}

(:test)
function rateSurvivesNoiseAndTilt(logger as Test.Logger) as Boolean {
    var det = new CompressionDetector(SyntheticCpr.RATE_HZ);
    var wall = SyntheticCpr.feed(det, 0, 12, 110.0, 5.0, 60, 0.9);
    assertRate(logger, det.rate(wall), 105, 115);
    return true;
}

(:test)
function stillWristIsNotCompressing(logger as Test.Logger) as Boolean {
    var det = new CompressionDetector(SyntheticCpr.RATE_HZ);
    var wall = SyntheticCpr.feed(det, 0, 10, 0.0, 0.0, 0, 0.0);
    Test.assertEqual(det.count(), 0);
    Test.assertMessage(det.rate(wall) == null, "rate while not compressing");
    Test.assertMessage(!det.isCompressing(wall), "compressing while still");
    return true;
}

(:test)
function sensorNoiseIsNotCompressing(logger as Test.Logger) as Boolean {
    var det = new CompressionDetector(SyntheticCpr.RATE_HZ);
    SyntheticCpr.feed(det, 0, 10, 0.0, 0.0, 40, 0.3);
    logger.debug("count = " + det.count());
    Test.assertEqual(det.count(), 0);
    return true;
}

(:test)
function pauseStopsAndResumes(logger as Test.Logger) as Boolean {
    var det = new CompressionDetector(SyntheticCpr.RATE_HZ);
    var wall = SyntheticCpr.feed(det, 0, 6, 110.0, 5.0, 0, 0.0);
    wall = SyntheticCpr.feed(det, wall, 4, 0.0, 0.0, 0, 0.0);
    logger.debug("idle ms = " + det.msSinceCompression(wall));
    Test.assertMessage(!det.isCompressing(wall), "still compressing in the pause");
    Test.assertMessage(det.rate(wall) == null, "rate while not compressing");
    Test.assertMessage(det.msSinceCompression(wall) > 3000, "hands-off time too short");
    wall = SyntheticCpr.feed(det, wall, 6, 110.0, 5.0, 0, 0.0);
    assertRate(logger, det.rate(wall), 105, 115);
    return true;
}

(:test)
function estimatesDepth(logger as Test.Logger) as Boolean {
    var deep = new CompressionDetector(SyntheticCpr.RATE_HZ);
    var wall = SyntheticCpr.feed(deep, 0, 10, 110.0, 5.0, 0, 0.0);
    var d5 = deep.depthCm(wall);
    var shallow = new CompressionDetector(SyntheticCpr.RATE_HZ);
    wall = SyntheticCpr.feed(shallow, 0, 10, 110.0, 3.0, 0, 0.0);
    var d3 = shallow.depthCm(wall);
    logger.debug("depth 5 cm -> " + d5 + ", 3 cm -> " + d3);
    Test.assertMessage(d5 != null, "no depth for 5 cm");
    Test.assertMessage(d3 != null, "no depth for 3 cm");
    Test.assertMessage(((d5 as Float) - 5.0).abs() < 0.5, "5 cm off");
    Test.assertMessage(((d3 as Float) - 3.0).abs() < 0.5, "3 cm off");
    return true;
}
