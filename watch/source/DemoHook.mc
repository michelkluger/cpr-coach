import Toybox.Lang;
import Toybox.WatchUi;

//! Normal builds open on the start screen. The demo build (tools/ciq.sh demo)
//! swaps in watch/demo/DemoHook.mc to open a screen with realistic state.
(:nodemo)
module DemoHook {
    function initialView() as [Views, InputDelegates]? {
        return null;
    }
}
