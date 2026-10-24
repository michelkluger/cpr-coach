import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.SensorLogging;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! One resuscitation: drives the metronome, tracks 2-minute cycles, breath
//! pauses (30:2 mode), pauses and shocks, and feeds the compression detector.
class CprSession {
    //! 110 per minute, the middle of the 100-120 guideline range
    public const BEAT_MS = 545;
    //! Swap rescuers every 2 minutes
    public const CYCLE_MS = 120000;
    public const CYCLE_WARN_MS = 110000;
    public const COMPRESSIONS_PER_SET = 30;
    public const BREATH_PAUSE_MS = 5000;
    public const TARGET_MIN = 100;
    public const TARGET_MAX = 120;
    private const SAMPLE_RATE = 25;

    public var training as Boolean;
    public var detector as CompressionDetector;
    public var startMs as Number = 0;
    public var endMs as Number?;
    public var startTime as System.ClockTime?;
    public var cycle as Number = 1;
    public var cycleStartMs as Number = 0;
    public var shocks as Number = 0;
    public var lastBeatMs as Number = 0;
    //! Time with compressions detected, for the compression fraction
    public var compressingMs as Number = 0;
    public var rateSum as Number = 0;
    public var rateSamples as Number = 0;

    private var _timer as Timer.Timer;
    private var _pauseStartMs as Number?;
    private var _breathEndMs as Number?;
    private var _beatsInSet as Number = 0;
    private var _cycleWarned as Boolean = false;
    private var _lastBatchMs as Number?;
    private var _recording as ActivityRecording.Session?;
    private var _beatVibe as Array<Attention.VibeProfile>;

    public function initialize(isTraining as Boolean) {
        training = isTraining;
        detector = new $.CompressionDetector(SAMPLE_RATE);
        _timer = new Timer.Timer();
        _beatVibe = [new Attention.VibeProfile(100, 60)] as Array<Attention.VibeProfile>;
    }

    public function start() as Void {
        startMs = System.getTimer();
        cycleStartMs = startMs;
        startTime = System.getClockTime();
        _timer.start(method(:onBeat), BEAT_MS, true);
        startSensors();
        beat(startMs);
    }

    public function stop() as Void {
        if (endMs != null) {
            return;
        }
        endMs = System.getTimer();
        _timer.stop();
        try {
            Sensor.unregisterSensorDataListener();
        } catch (e) {
            System.println(e.getErrorMessage());
        }
        var recording = _recording;
        if (recording != null && recording.isRecording()) {
            recording.stop();
            recording.save();
        }
    }

    public function isPaused() as Boolean {
        return _pauseStartMs != null;
    }

    //! Pause the metronome, e.g. while the AED analyses the rhythm
    public function togglePause() as Void {
        var now = System.getTimer();
        if (_pauseStartMs == null) {
            _pauseStartMs = now;
            buzz([new Attention.VibeProfile(50, 200)]);
        } else {
            _pauseStartMs = null;
            _breathEndMs = null;
            _beatsInSet = 0;
            beat(now);
        }
        WatchUi.requestUpdate();
    }

    public function logShock() as Void {
        shocks++;
        buzz([new Attention.VibeProfile(100, 150), new Attention.VibeProfile(0, 100), new Attention.VibeProfile(100, 150)]);
    }

    //! Milliseconds left in the current breath pause, null outside one
    public function breathRemainingMs(now as Number) as Number? {
        var end = _breathEndMs;
        return end != null && now < end ? end - now : null;
    }

    public function pausedForMs(now as Number) as Number {
        var since = _pauseStartMs;
        return since != null ? now - since : 0;
    }

    public function elapsedMs(now as Number) as Number {
        var end = endMs;
        return (end != null ? end : now) - startMs;
    }

    public function cycleElapsedMs(now as Number) as Number {
        return now - cycleStartMs;
    }

    //! Share of the elapsed time with compressions detected, 0-100
    public function compressionFraction(now as Number) as Number {
        var total = elapsedMs(now);
        return total > 0 ? (100 * compressingMs / total) : 0;
    }

    public function averageRate() as Number? {
        return rateSamples > 0 ? rateSum / rateSamples : null;
    }

    public function onBeat() as Void {
        var now = System.getTimer();

        if (now - cycleStartMs >= CYCLE_MS) {
            cycle++;
            cycleStartMs = now;
            _cycleWarned = false;
            alert([new Attention.VibeProfile(100, 700)], Attention.TONE_ALERT_HI);
            WatchUi.requestUpdate();
            return;
        }
        if (!_cycleWarned && now - cycleStartMs >= CYCLE_WARN_MS) {
            _cycleWarned = true;
            alert([new Attention.VibeProfile(60, 150), new Attention.VibeProfile(0, 100), new Attention.VibeProfile(60, 150)],
                Attention.TONE_ALERT_LO);
            WatchUi.requestUpdate();
            return;
        }

        if (_pauseStartMs != null) {
            WatchUi.requestUpdate();
            return;
        }
        var breathEnd = _breathEndMs;
        if (breathEnd != null) {
            if (now < breathEnd) {
                WatchUi.requestUpdate();
                return;
            }
            _breathEndMs = null;
        }

        beat(now);
        if (Settings.breaths()) {
            _beatsInSet++;
            if (_beatsInSet >= COMPRESSIONS_PER_SET) {
                _beatsInSet = 0;
                _breathEndMs = now + BREATH_PAUSE_MS;
                alert([new Attention.VibeProfile(100, 300), new Attention.VibeProfile(0, 200), new Attention.VibeProfile(100, 300)],
                    Attention.TONE_INTERVAL_ALERT);
            }
        }
        WatchUi.requestUpdate();
    }

    public function onSensorData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (accel == null) {
            return;
        }
        var now = System.getTimer();
        detector.addSamples(accel.x, accel.y, accel.z, now);

        var last = _lastBatchMs;
        _lastBatchMs = now;
        if (last == null || _pauseStartMs != null || !detector.isCompressing(now)) {
            return;
        }
        var batchMs = now - last;
        compressingMs += batchMs < 1500 ? batchMs : 1500;
        var cpm = detector.rate(now);
        if (cpm != null) {
            rateSum += cpm;
            rateSamples++;
        }
    }

    private function startSensors() as Void {
        var rate = SAMPLE_RATE;
        if (Sensor has :getMaxSampleRateForSensorType) {
            var max = Sensor.getMaxSampleRateForSensorType(:accelerometer);
            if (max < rate) {
                rate = max;
                detector = new $.CompressionDetector(rate);
            }
        }
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => {:enabled => true, :sampleRate => rate}
            });
        } catch (e) {
            System.println(e.getErrorMessage());
        }

        if (training) {
            // Raw accelerometer data in the FIT file is the dataset for calibrating depth on a manikin
            try {
                var logger = new SensorLogging.SensorLogger({:accelerometer => {:enabled => true}});
                var recording = ActivityRecording.createSession({
                    :name => "CPR training",
                    :sport => Activity.SPORT_GENERIC,
                    :sensorLogger => logger
                });
                recording.start();
                _recording = recording;
            } catch (e) {
                System.println(e.getErrorMessage());
            }
        }
    }

    private function beat(now as Number) as Void {
        lastBeatMs = now;
        buzz(_beatVibe);
        if (Settings.sound() && Attention has :playTone) {
            Attention.playTone({:toneProfile => [new Attention.ToneProfile(1800, 40)]});
        }
    }

    private function alert(vibe as Array<Attention.VibeProfile>, tone as Attention.Tone) as Void {
        buzz(vibe);
        if (Settings.sound() && Attention has :playTone) {
            Attention.playTone(tone);
        }
    }

    private function buzz(profile as Array<Attention.VibeProfile>) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate(profile);
        }
    }
}
