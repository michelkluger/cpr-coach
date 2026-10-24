import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! First screen: what to do, in order. START begins CPR immediately.
class StartView extends WatchUi.View {

    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        Ui.text(dc, 0.17, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "CPR COACH BETA");
        Ui.text(dc, 0.31, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "1  Call 144 / 112");
        Ui.text(dc, 0.44, Graphics.FONT_SMALL, Graphics.COLOR_WHITE, "2  Send for an AED");
        Ui.text(dc, 0.60, Graphics.FONT_MEDIUM, Graphics.COLOR_RED, "START: CPR");
        Ui.text(dc, 0.75, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "DOWN nearest AED");
        Ui.text(dc, 0.84, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "UP my position");
    }
}

class StartDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onSelect() as Boolean {
        beginCpr(false);
        return true;
    }

    public function onNextPage() as Boolean {
        var view = new $.AedView();
        WatchUi.pushView(view, new $.AedDelegate(view), WatchUi.SLIDE_UP);
        return true;
    }

    public function onPreviousPage() as Boolean {
        WatchUi.pushView(new $.PositionView(), new $.PositionDelegate(), WatchUi.SLIDE_DOWN);
        return true;
    }

    public function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({:title => "Options"});
        menu.addItem(new WatchUi.MenuItem("Training", "manikin, records FIT", :training, null));
        Options.addToggles(menu);
        menu.addItem(new WatchUi.MenuItem("About", "not a medical device", :about, null));
        WatchUi.pushView(menu, new StartMenuDelegate(), WatchUi.SLIDE_LEFT);
        return true;
    }
}

function beginCpr(training as Boolean) as Void {
    $.getApp().beginSession(training);
    WatchUi.pushView(new $.CprView(), new $.CprDelegate(), WatchUi.SLIDE_LEFT);
}

class StartMenuDelegate extends WatchUi.Menu2InputDelegate {

    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :training) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            beginCpr(true);
        } else if (item.getId() == :about) {
            WatchUi.pushView(new $.DisclaimerView(), new $.DisclaimerDelegate(false), WatchUi.SLIDE_LEFT);
        } else {
            Options.handleToggle(item);
        }
    }
}

//! Toggles shared by the start menu and the in-CPR menu
module Options {
    function addToggles(menu as WatchUi.Menu2) as Void {
        menu.addItem(new WatchUi.ToggleMenuItem("30:2 breaths", {:enabled => "pause for 2 breaths", :disabled => "hands-only"},
            :breaths, Settings.breaths(), null));
        menu.addItem(new WatchUi.ToggleMenuItem("Beep", {:enabled => "beep + vibrate", :disabled => "vibrate only"},
            :sound, Settings.sound(), null));
    }

    function handleToggle(item as WatchUi.MenuItem) as Void {
        if (!(item instanceof WatchUi.ToggleMenuItem)) {
            return;
        }
        var on = (item as WatchUi.ToggleMenuItem).isEnabled();
        if (item.getId() == :breaths) {
            Settings.setBreaths(on);
        } else if (item.getId() == :sound) {
            Settings.setSound(on);
        }
    }
}
