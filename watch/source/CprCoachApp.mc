import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

//! Wrist CPR coach: compression metronome with rate feedback, offline nearest
//! AED finder and coordinates to read out to the emergency dispatcher.
class CprCoachApp extends Application.AppBase {

    //! Active CPR session, null when no CPR is running
    public var session as CprSession?;

    public var finder as AedFinder;

    private var _position as Position.Info?;

    public function initialize() {
        AppBase.initialize();
        finder = new AedFinder();
    }

    //! GPS starts with the app so a fix is ready by the time someone needs the AED page
    public function onStart(state as Dictionary?) as Void {
        _position = Position.getInfo();
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    public function onStop(state as Dictionary?) as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        endSession();
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var demo = DemoHook.initialView();
        if (demo != null) {
            return demo;
        }
        if (!Settings.disclaimerSeen()) {
            return [new $.DisclaimerView(), new $.DisclaimerDelegate(true)];
        }
        return [new $.StartView(), new $.StartDelegate()];
    }

    public function onPosition(info as Position.Info) as Void {
        _position = info;
        WatchUi.requestUpdate();
    }

    //! Latest fix, or the last known position until the first fix arrives
    public function position() as Position.Info? {
        return _position;
    }

    //! Latitude and longitude in degrees, or null without any position
    public function latLon() as [Double, Double]? {
        var info = _position;
        if (info == null || info.position == null || info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return null;
        }
        var deg = (info.position as Position.Location).toDegrees();
        return [deg[0].toDouble(), deg[1].toDouble()];
    }

    public function beginSession(training as Boolean) as CprSession {
        endSession();
        var s = new $.CprSession(training);
        session = s;
        s.start();
        return s;
    }

    //! Stops the running session (if any) and returns it for the summary
    public function endSession() as CprSession? {
        var s = session;
        session = null;
        if (s != null) {
            s.stop();
        }
        return s;
    }
}

function getApp() as CprCoachApp {
    return Application.getApp() as CprCoachApp;
}
