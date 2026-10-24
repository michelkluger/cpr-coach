import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

//! Coordinates to read out to the dispatcher: WGS84 and, in Switzerland, LV95.
class PositionView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        Ui.text(dc, 0.14, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "MY POSITION");

        var app = $.getApp();
        var ll = app.latLon();
        if (ll == null) {
            Ui.text(dc, 0.5, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "Waiting for GPS");
            return;
        }
        var lat = ll[0];
        var lon = ll[1];
        Ui.text(dc, 0.29, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, lat.abs().format("%.5f") + (lat >= 0 ? " N" : " S"));
        Ui.text(dc, 0.40, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, lon.abs().format("%.5f") + (lon >= 0 ? " E" : " W"));

        if (Geo.inSwitzerland(lat, lon)) {
            var lv95 = Geo.toLv95(lat, lon);
            Ui.text(dc, 0.54, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "Swiss grid LV95");
            Ui.text(dc, 0.63, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, Geo.formatSwiss(lv95[0]));
            Ui.text(dc, 0.73, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, Geo.formatSwiss(lv95[1]));
        }

        var info = app.position() as Position.Info;
        var quality = ["no fix", "last known", "poor", "usable", "good"];
        var footer = "GPS " + quality[info.accuracy as Number];
        var alt = info.altitude;
        if (alt != null) {
            footer += "  " + alt.format("%d") + " m";
        }
        Ui.text(dc, 0.86, Graphics.FONT_XTINY, info.accuracy >= Position.QUALITY_USABLE ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE, footer);
    }
}

class PositionDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onNextPage() as Boolean {
        Pages.next(Pages.POSITION);
        return true;
    }

    public function onPreviousPage() as Boolean {
        Pages.previous(Pages.POSITION);
        return true;
    }

    public function onBack() as Boolean {
        Pages.back();
        return true;
    }
}
