import Toybox.Application;
import Toybox.Lang;

//! User options, cached in memory because the metronome reads them on every beat
module Settings {
    const KEY_BREATHS = "breaths";
    const KEY_SOUND = "sound";
    const KEY_DISCLAIMER = "disclaimerSeen";

    var _breaths as Boolean?;
    var _sound as Boolean?;

    //! 30 compressions : 2 breaths instead of hands-only CPR (default off,
    //! hands-only is the recommendation for untrained bystanders)
    function breaths() as Boolean {
        if (_breaths == null) {
            _breaths = Application.Storage.getValue(KEY_BREATHS) == true;
        }
        return _breaths as Boolean;
    }

    function setBreaths(on as Boolean) as Void {
        _breaths = on;
        Application.Storage.setValue(KEY_BREATHS, on);
    }

    //! Metronome beep in addition to the vibration (default on)
    function sound() as Boolean {
        if (_sound == null) {
            _sound = Application.Storage.getValue(KEY_SOUND) != false;
        }
        return _sound as Boolean;
    }

    function setSound(on as Boolean) as Void {
        _sound = on;
        Application.Storage.setValue(KEY_SOUND, on);
    }

    //! The "not a medical device" notice was acknowledged once
    function disclaimerSeen() as Boolean {
        return Application.Storage.getValue(KEY_DISCLAIMER) == true;
    }

    function setDisclaimerSeen() as Void {
        Application.Storage.setValue(KEY_DISCLAIMER, true);
    }
}
