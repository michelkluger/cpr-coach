import Toybox.Lang;
import Toybox.WatchUi;

//! Pages reachable with UP/DOWN. CPR is only part of the cycle while a session runs.
module Pages {
    enum Page {
        CPR,
        AED,
        POSITION
    }

    function order() as Array<Page> {
        return $.getApp().session != null ? [CPR, AED, POSITION] : [AED, POSITION];
    }

    function next(current as Page) as Void {
        var pages = order();
        var i = pages.indexOf(current);
        show(pages[(i + 1) % pages.size()], WatchUi.SLIDE_UP);
    }

    function previous(current as Page) as Void {
        var pages = order();
        var i = pages.indexOf(current);
        show(pages[(i + pages.size() - 1) % pages.size()], WatchUi.SLIDE_DOWN);
    }

    function show(page as Page, transition as WatchUi.SlideType) as Void {
        if (page == CPR) {
            WatchUi.switchToView(new $.CprView(), new $.CprDelegate(), transition);
        } else if (page == AED) {
            var view = new $.AedView();
            WatchUi.switchToView(view, new $.AedDelegate(view), transition);
        } else {
            WatchUi.switchToView(new $.PositionView(), new $.PositionDelegate(), transition);
        }
    }

    //! BACK from AED or position: return to CPR while it runs, else to the start screen
    function back() as Void {
        if ($.getApp().session != null) {
            show(CPR, WatchUi.SLIDE_RIGHT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
