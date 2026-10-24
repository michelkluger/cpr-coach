import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Main CPR screen: measured rate with faster/slower feedback, 2-minute cycle
//! ring, beat flash, hands-off warning, and depth estimate in training mode.
class CprView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        var s = $.getApp().session;
        if (s == null) {
            Ui.text(dc, 0.5, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "No CPR running");
            return;
        }
        var now = System.getTimer();
        var cycleMs = s.cycleElapsedMs(now);
        var ringColor = cycleMs >= s.CYCLE_WARN_MS ? Graphics.COLOR_ORANGE : Graphics.COLOR_GREEN;
        Ui.ring(dc, cycleMs.toFloat() / s.CYCLE_MS, ringColor);

        var header = Geo.formatDuration(s.elapsedMs(now)) + "  cycle " + s.cycle;
        Ui.text(dc, 0.15, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, s.training ? "TRAINING " + header : header);

        if (now - s.lastBeatMs < 180) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(dc.getWidth() / 2, (dc.getHeight() * 0.25).toNumber(), dc.getWidth() / 37);
        }

        var breathMs = s.breathRemainingMs(now);
        if (s.isPaused()) {
            Ui.text(dc, 0.45, Graphics.FONT_LARGE, Graphics.COLOR_YELLOW, "PAUSED");
            Ui.text(dc, 0.60, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "hands off " + Geo.formatDuration(s.pausedForMs(now)));
            Ui.text(dc, 0.72, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "START resume");
        } else if (breathMs != null) {
            Ui.text(dc, 0.45, Graphics.FONT_LARGE, Graphics.COLOR_BLUE, "2 BREATHS");
            Ui.text(dc, 0.62, Graphics.FONT_NUMBER_MEDIUM, Graphics.COLOR_WHITE, ((breathMs + 999) / 1000).toString());
        } else {
            drawFeedback(dc, s, now);
        }

        var footer = s.detector.count() + " comp";
        if (s.shocks > 0) {
            footer += "  " + s.shocks + " shock" + (s.shocks > 1 ? "s" : "");
        }
        Ui.text(dc, 0.86, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, footer);
    }

    private function drawFeedback(dc as Graphics.Dc, s as CprSession, now as Number) as Void {
        var rate = s.detector.rate(now);
        if (rate == null) {
            var idle = s.detector.msSinceCompression(now);
            Ui.text(dc, 0.45, Graphics.FONT_LARGE, Graphics.COLOR_RED, "PUSH");
            Ui.text(dc, 0.60, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "hard and fast");
            if (idle > 3000) {
                Ui.text(dc, 0.72, Graphics.FONT_XTINY, Graphics.COLOR_ORANGE, "no compressions " + Geo.formatDuration(idle));
            }
            return;
        }

        var color = Graphics.COLOR_GREEN;
        var advice = "GOOD";
        if (rate < s.TARGET_MIN) {
            color = Graphics.COLOR_ORANGE;
            advice = "FASTER";
        } else if (rate > s.TARGET_MAX) {
            color = Graphics.COLOR_ORANGE;
            advice = "SLOWER";
        }
        Ui.text(dc, 0.45, Graphics.FONT_NUMBER_HOT, color, rate.toString());
        Ui.text(dc, 0.64, Graphics.FONT_SMALL, color, advice);

        if (s.training) {
            var depth = s.detector.depthCm(now);
            if (depth != null) {
                var depthColor = depth < 5.0 || depth > 6.0 ? Graphics.COLOR_ORANGE : Graphics.COLOR_GREEN;
                Ui.text(dc, 0.75, Graphics.FONT_XTINY, depthColor, "depth ~" + depth.format("%.1f") + " cm (exp.)");
            }
        }
    }
}

class CprDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    //! Physical START button pauses/resumes. Taps are ignored: a sleeve or a
    //! patient's clothing brushing the screen must not pause the metronome.
    public function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_ENTER) {
            var s = $.getApp().session;
            if (s != null) {
                s.togglePause();
            }
            return true;
        }
        return BehaviorDelegate.onKey(keyEvent);
    }

    public function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    public function onSelect() as Boolean {
        return true;
    }

    public function onNextPage() as Boolean {
        Pages.next(Pages.CPR);
        return true;
    }

    public function onPreviousPage() as Boolean {
        Pages.previous(Pages.CPR);
        return true;
    }

    public function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({:title => "CPR"});
        menu.addItem(new WatchUi.MenuItem("Log AED shock", null, :shock, null));
        Options.addToggles(menu);
        menu.addItem(new WatchUi.MenuItem("End CPR", null, :end, null));
        WatchUi.pushView(menu, new CprMenuDelegate(), WatchUi.SLIDE_LEFT);
        return true;
    }

    public function onBack() as Boolean {
        confirmEnd();
        return true;
    }
}

class CprMenuDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :shock) {
            var s = $.getApp().session;
            if (s != null) {
                s.logShock();
            }
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (id == :end) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            confirmEnd();
        } else {
            Options.handleToggle(item);
        }
    }
}

function confirmEnd() as Void {
    WatchUi.pushView(new WatchUi.Confirmation("End CPR?"), new EndConfirmationDelegate(), WatchUi.SLIDE_IMMEDIATE);
}

//! The confirmation pops itself after onResponse, so the summary is shown a
//! moment later instead of fighting the view stack from inside the callback.
class EndConfirmationDelegate extends WatchUi.ConfirmationDelegate {

    public function initialize() {
        ConfirmationDelegate.initialize();
    }

    public function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            Deferred.run(new Lang.Method($, :showSummary));
        }
        return true;
    }
}

function showSummary() as Void {
    var s = $.getApp().endSession();
    if (s != null) {
        WatchUi.switchToView(new $.SummaryView(s), new $.SummaryDelegate(), WatchUi.SLIDE_LEFT);
    }
}

//! Runs a callback shortly after the current input event, once the view stack settled
module Deferred {
    var _timer as Timer.Timer?;

    function run(callback as Method() as Void) as Void {
        var timer = new Timer.Timer();
        timer.start(callback, 50, false);
        // Keep a reference so the one-shot timer is not collected before it fires
        _timer = timer;
    }
}
