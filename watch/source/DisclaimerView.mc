import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Shown on first launch and from Options > About: not a medical device, beta.
class DisclaimerView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        Ui.stack(dc, Graphics.FONT_XTINY, [
            ["BETA - IN DEVELOPMENT", Graphics.COLOR_ORANGE],
            ["Not a medical device. For training and information only.", Graphics.COLOR_WHITE],
            ["AED data may be incomplete.", Graphics.COLOR_LT_GRAY],
            ["Emergency: call 144/112", Graphics.COLOR_RED],
            ["START: OK", Graphics.COLOR_LT_GRAY]
        ]);
    }
}

class DisclaimerDelegate extends WatchUi.BehaviorDelegate {
    //! First launch continues to the start screen; from the menu it just closes
    private var _firstRun as Boolean;

    public function initialize(firstRun as Boolean) {
        BehaviorDelegate.initialize();
        _firstRun = firstRun;
    }

    public function onSelect() as Boolean {
        Settings.setDisclaimerSeen();
        if (_firstRun) {
            WatchUi.switchToView(new $.StartView(), new $.StartDelegate(), WatchUi.SLIDE_LEFT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    public function onBack() as Boolean {
        if (_firstRun) {
            return false;
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
