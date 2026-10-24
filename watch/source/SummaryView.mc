import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Handover for the paramedics: when CPR started, how long, rate and shocks.
class SummaryView extends WatchUi.View {
    private var _session as CprSession;

    public function initialize(session as CprSession) {
        View.initialize();
        _session = session;
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        var s = _session;
        var now = System.getTimer();
        var start = s.startTime;
        var started = start != null ? start.hour.format("%02d") + ":" + start.min.format("%02d") : "--:--";
        var avg = s.averageRate();

        Ui.text(dc, 0.15, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, s.training ? "TRAINING SUMMARY" : "CPR SUMMARY");
        Ui.text(dc, 0.29, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "Started " + started);
        Ui.text(dc, 0.40, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "Duration " + Geo.formatDuration(s.elapsedMs(now)));
        Ui.text(dc, 0.51, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "Shocks " + s.shocks);
        Ui.text(dc, 0.62, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY,
            s.detector.count() + " compressions, avg " + (avg != null ? avg.toString() : "--") + "/min");
        Ui.text(dc, 0.71, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "hands on chest " + s.compressionFraction(now) + "%");
        if (s.training) {
            Ui.text(dc, 0.80, Graphics.FONT_XTINY, Graphics.COLOR_GREEN, "Saved as activity");
        }
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    public function onSelect() as Boolean {
        return onBack();
    }
}
