import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Opens DemoConfig.PAGE with realistic state (GPS fix at Zurich HB, a CPR
//! session part-way through, synthetic compressions) so screenshots need no
//! clicking in the simulator.
(:demo)
module DemoHook {
    const LAT = 47.37818d;
    const LON = 8.54019d;
    const RATE_HZ = 25;
    const DEPTH_CM = 5.2;

    var _timer as Timer.Timer?;
    var _cpm as Float = 112.0;

    function initialView() as [Views, InputDelegates]? {
        var app = $.getApp();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        var info = new Position.Info();
        info.position = new Position.Location({:latitude => LAT, :longitude => LON, :format => :degrees});
        info.accuracy = Position.QUALITY_GOOD;
        info.altitude = 408.0;
        app.onPosition(info);

        var page = DemoConfig.PAGE;
        if (page.equals("start")) {
            return [new $.StartView(), new $.StartDelegate()];
        }
        if (page.equals("disclaimer")) {
            return [new $.DisclaimerView(), new $.DisclaimerDelegate(true)];
        }
        if (page.equals("aed")) {
            var view = new $.AedView();
            return [view, new $.AedDelegate(view)];
        }
        if (page.equals("position")) {
            return [new $.PositionView(), new $.PositionDelegate()];
        }

        var s = app.beginSession(page.equals("training"));
        Sensor.unregisterSensorDataListener();
        s.startMs -= 200000;
        s.cycleStartMs -= 80000;
        s.cycle = 2;
        s.shocks = 1;
        _cpm = page.equals("slow") ? 92.0 : 112.0;

        if (page.equals("summary")) {
            // A few seconds only: feeding a minute at once trips the watchdog
            var now = System.getTimer();
            for (var i = 8; i > 0; i--) {
                feedSecond(s.detector, now - i * 1000);
            }
            s.compressingMs = 172000;
            s.rateSum = 112 * 180;
            s.rateSamples = 180;
            app.endSession();
            return [new $.SummaryView(s), new $.SummaryDelegate()];
        }

        var timer = new Timer.Timer();
        timer.start(new Lang.Method($.DemoHook, :tick), 1000, true);
        _timer = timer;
        for (var i = 5; i > 0; i--) {
            feedSecond(s.detector, System.getTimer() - i * 1000);
        }
        return [new $.CprView(), new $.CprDelegate()];
    }

    function tick() as Void {
        var s = $.getApp().session;
        if (s != null) {
            feedSecond(s.detector, System.getTimer());
        }
    }

    //! One second of vertical wrist motion ending at wallMs
    function feedSecond(det as CompressionDetector, wallMs as Number) as Void {
        var omega = 2.0 * Math.PI * _cpm / 60.0;
        var amp = (DEPTH_CM / 200.0) * omega * omega / 0.00980665;
        var x = new Array<Number>[RATE_HZ];
        var y = new Array<Number>[RATE_HZ];
        var z = new Array<Number>[RATE_HZ];
        for (var i = 0; i < RATE_HZ; i++) {
            var t = (wallMs - 1000 + (i + 1) * 1000 / RATE_HZ) / 1000.0;
            x[i] = 0;
            y[i] = 0;
            z[i] = (1000.0 + amp * Math.sin(omega * t)).toNumber();
        }
        det.addSamples(x, y, z, wallMs);
    }
}
