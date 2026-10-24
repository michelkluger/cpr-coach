import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.WatchUi;

//! Nearest AEDs from the bundled OSM data: compass arrow, distance and where
//! exactly it hangs. START cycles through the closest five.
class AedView extends WatchUi.View {
    private const TICK_MS = 250;

    private var _timer as Timer.Timer;
    private var _index as Number = 0;

    public function initialize() {
        View.initialize();
        _timer = new Timer.Timer();
    }

    public function onShow() as Void {
        _timer.start(method(:onTick), TICK_MS, true);
        onTick();
    }

    public function onHide() as Void {
        _timer.stop();
    }

    public function nextHit() as Void {
        var count = $.getApp().finder.hits().size();
        _index = count > 0 ? (_index + 1) % count : 0;
        WatchUi.requestUpdate();
    }

    //! Restarts the search when the user moved, advances it, refreshes the arrow
    public function onTick() as Void {
        var app = $.getApp();
        var ll = app.latLon();
        if (ll != null) {
            if (app.finder.needsSearch(ll[0], ll[1])) {
                app.finder.search(ll[0], ll[1]);
                _index = 0;
            }
            app.finder.step();
        }
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        var app = $.getApp();
        var ll = app.latLon();
        if (ll == null) {
            Ui.text(dc, 0.38, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "Waiting for GPS");
            Ui.text(dc, 0.52, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "Go outside, keep still");
            Ui.text(dc, 0.72, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, AedIndex.AED_COUNT + " AEDs offline");
            Ui.text(dc, 0.80, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "OSM " + AedIndex.DATA_DATE);
            return;
        }

        var hits = app.finder.hits();
        if (hits.size() == 0) {
            var msg = app.finder.isDone() ? "No AED within ~50 km" : "Searching...";
            Ui.text(dc, 0.5, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, msg);
            return;
        }
        if (_index >= hits.size()) {
            _index = 0;
        }
        var hit = hits[_index];

        var bearing = Geo.bearingRad(ll[0], ll[1], hit.lat, hit.lon);
        var heading = Sensor.getInfo().heading;
        var angle = heading != null ? bearing - heading : bearing;
        var w = dc.getWidth();
        var h = dc.getHeight();
        Ui.arrow(dc, w / 2, (h * 0.26).toNumber(), (h * 0.12).toNumber(), angle, Graphics.COLOR_GREEN);

        var dist = Geo.formatDistance(hit.distM);
        if (heading == null) {
            dist += " " + Geo.cardinal(bearing);
        }
        Ui.text(dc, 0.46, Graphics.FONT_MEDIUM, Graphics.COLOR_WHITE, dist);
        Ui.wrapped(dc, 0.57, 0.8, 0.09, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, hit.title());
        Ui.wrapped(dc, 0.69, 0.82, 0.16, Graphics.FONT_XTINY, Graphics.COLOR_WHITE, hit.where());

        var info = hit.isOpen24h() ? "24/7" : (hit.hours().length() > 0 ? hit.hours() : "hours unknown");
        if (hit.isRestricted()) {
            info = "restricted, " + info;
        }
        Ui.wrapped(dc, 0.80, 0.7, 0.10, Graphics.FONT_XTINY, hit.isOpen24h() ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE, info);

        var footer = (_index + 1) + "/" + hits.size();
        var pos = app.position();
        if (pos != null && pos.accuracy < Position.QUALITY_USABLE) {
            footer += " approx. GPS";
        } else if (heading == null) {
            footer += " north up";
        }
        Ui.text(dc, 0.89, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, footer);
    }
}

class AedDelegate extends WatchUi.BehaviorDelegate {
    private var _view as AedView;

    public function initialize(view as AedView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onSelect() as Boolean {
        _view.nextHit();
        return true;
    }

    public function onNextPage() as Boolean {
        Pages.next(Pages.AED);
        return true;
    }

    public function onPreviousPage() as Boolean {
        Pages.previous(Pages.AED);
        return true;
    }

    public function onBack() as Boolean {
        Pages.back();
        return true;
    }
}
