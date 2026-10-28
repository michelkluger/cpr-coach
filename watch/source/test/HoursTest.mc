import Toybox.Lang;
import Toybox.Test;

// Weekdays as Hours counts them
const MO = 0;
const TU = 1;
const TH = 3;
const FR = 4;
const SA = 5;
const SU = 6;

(:debug)
function at(hh as Number, mm as Number) as Number {
    return hh * 60 + mm;
}

(:test)
function officeHours(logger as Test.Logger) as Boolean {
    var h = "Mo-Fr 08:00-17:00";
    Test.assertEqual(Hours.isOpen(h, MO, at(10, 0)), true);
    Test.assertEqual(Hours.isOpen(h, MO, at(7, 59)), false);
    Test.assertEqual(Hours.isOpen(h, FR, at(16, 59)), true);
    Test.assertEqual(Hours.isOpen(h, FR, at(17, 0)), false);
    Test.assertEqual(Hours.isOpen(h, SA, at(10, 0)), false);
    Test.assertEqual(Hours.isOpen("Mo-Fr 8:00-17:00", TU, at(8, 0)), true);
    Test.assertEqual(Hours.isOpen("08:00-18:00", SU, at(9, 0)), true);
    return true;
}

(:test)
function lunchBreakAndAdditionalRules(logger as Test.Logger) as Boolean {
    Test.assertEqual(Hours.isOpen("Mo-Fr 08:00-12:00, 13:00-17:00", TU, at(12, 30)), false);
    Test.assertEqual(Hours.isOpen("Mo-Fr 08:00-12:00, 13:00-17:00", TU, at(13, 0)), true);
    var h = "Mo-Th 08:00-12:00,13:30-17:00, Fr 08:00-12:00,13:30-16:00";
    Test.assertEqual(Hours.isOpen(h, TH, at(16, 30)), true);
    Test.assertEqual(Hours.isOpen(h, FR, at(16, 30)), false);
    Test.assertEqual(Hours.isOpen("Mo,Th 09:00-11:00", TH, at(10, 0)), true);
    Test.assertEqual(Hours.isOpen("Mo,Th 09:00-11:00", TU, at(10, 0)), false);
    return true;
}

(:test)
function laterRulesReplaceDays(logger as Test.Logger) as Boolean {
    var h = "Mo-Fr 07:00-18:00; Sa 08:00-12:00; Su off; PH off";
    Test.assertEqual(Hours.isOpen(h, SA, at(11, 0)), true);
    Test.assertEqual(Hours.isOpen(h, SU, at(11, 0)), false);
    Test.assertEqual(Hours.isOpen(h, MO, at(17, 0)), true);
    Test.assertEqual(Hours.isOpen("Mo-Fr 08:00-18:00; We 08:00-12:00", 2, at(14, 0)), false);
    return true;
}

(:test)
function pastMidnightAndWrappedDays(logger as Test.Logger) as Boolean {
    var h = "Fr-Sa 22:00-02:00";
    Test.assertEqual(Hours.isOpen(h, SA, at(1, 0)), true);
    Test.assertEqual(Hours.isOpen(h, SU, at(1, 0)), true);
    Test.assertEqual(Hours.isOpen(h, MO, at(1, 0)), false);
    Test.assertEqual(Hours.isOpen(h, FR, at(21, 0)), false);
    Test.assertEqual(Hours.isOpen("Sa-Mo 10:00-12:00", SU, at(11, 0)), true);
    Test.assertEqual(Hours.isOpen("Sa-Mo 10:00-12:00", TU, at(11, 0)), false);
    Test.assertEqual(Hours.isOpen("Mo-Su 00:00-24:00", SU, at(23, 59)), true);
    return true;
}

(:test)
function unknownFormatsAreNull(logger as Test.Logger) as Boolean {
    var unknown = ["", "Mo-Fr", "sunrise-sunset", "May-Jun 09:00-20:00", "Mo-Fr 08:00-17:00 \"nach Absprache\"",
        "Mo-Fr 08:00-12:00, 13:…", "Mo-Fr 25:00-26:00", "Mo-Fr 08:00-", "mo-fr 08:00-17:00"];
    for (var i = 0; i < unknown.size(); i++) {
        Test.assertMessage(Hours.isOpen(unknown[i], MO, at(10, 0)) == null, "should be unknown: " + unknown[i]);
    }
    return true;
}
