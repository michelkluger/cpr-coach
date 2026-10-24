import Toybox.Lang;
import Toybox.Math;

//! Detects chest compressions in wrist accelerometer data.
//!
//! During CPR the arms are locked and the wrist follows the sternum up and
//! down, parallel to gravity. The acceleration magnitude therefore oscillates
//! around 1 g once per compression, whatever the watch orientation. A slow
//! baseline removes gravity, a light low-pass removes jitter, and maxima above
//! an adaptive threshold count as compressions.
//!
//! Depth is estimated by modelling the motion as a sinusoid: peak-to-peak
//! acceleration = depth * omega^2, corrected for the filter gain at the
//! measured rate. This is a first approximation to calibrate on a manikin,
//! which is why the UI only shows it in training mode.
class CompressionDetector {
    private const BASELINE_TAU_S = 0.8;
    private const SMOOTH_TAU_S = 0.08;
    private const ENVELOPE_TAU_S = 1.5;
    private const MIN_PEAK_MG = 120.0;
    private const PEAK_FRACTION = 0.4;
    //! Caps detection at 200 compressions per minute
    private const REFRACTORY_MS = 300.0;
    //! No compression for this long means hands are off the chest
    private const STALE_MS = 2000.0;
    private const RATE_WINDOW = 6;
    private const DEPTH_SMOOTHING = 0.3;
    private const MG_TO_MS2 = 0.00980665;

    private var _sampleMs as Float;
    private var _alphaBase as Float;
    private var _alphaSmooth as Float;
    private var _envDecay as Float;

    private var _baseline as Float?;
    private var _smooth as Float = 0.0;
    private var _prev1 as Float = 0.0;
    private var _prev2 as Float = 0.0;
    private var _envelope as Float = 0.0;
    private var _trough as Float = 0.0;

    //! Sample clock in ms since the first sample; wall time is mapped onto it
    //! so rate and staleness do not depend on callback jitter
    private var _clockMs as Float = 0.0;
    private var _wallMs as Number?;
    private var _wallClockMs as Float = 0.0;

    private var _lastPeakMs as Float?;
    private var _intervals as Array<Float> = [] as Array<Float>;
    private var _count as Number = 0;
    private var _peakToPeak as Float?;

    //! @param sampleRate accelerometer samples per second
    public function initialize(sampleRate as Number) {
        var dt = 1.0 / sampleRate;
        _sampleMs = 1000.0 / sampleRate;
        _alphaBase = (1.0 - Math.pow(Math.E, -dt / BASELINE_TAU_S)).toFloat();
        _alphaSmooth = (1.0 - Math.pow(Math.E, -dt / SMOOTH_TAU_S)).toFloat();
        _envDecay = Math.pow(Math.E, -dt / ENVELOPE_TAU_S).toFloat();
    }

    //! Feed one batch of samples in milli-g; the last sample was taken at wallMs
    public function addSamples(x as Array<Number>, y as Array<Number>, z as Array<Number>, wallMs as Number) as Void {
        for (var i = 0; i < x.size(); i++) {
            var xi = x[i].toFloat();
            var yi = y[i].toFloat();
            var zi = z[i].toFloat();
            processSample(Math.sqrt(xi * xi + yi * yi + zi * zi).toFloat());
        }
        _wallMs = wallMs;
        _wallClockMs = _clockMs;
    }

    //! Compressions detected since the start
    public function count() as Number {
        return _count;
    }

    public function isCompressing(wallMs as Number) as Boolean {
        var last = _lastPeakMs;
        return last != null && clockAt(wallMs) - last <= STALE_MS;
    }

    //! Milliseconds since the last detected compression (since start when none yet)
    public function msSinceCompression(wallMs as Number) as Number {
        var last = _lastPeakMs;
        return (clockAt(wallMs) - (last != null ? last : 0.0)).toNumber();
    }

    //! Compressions per minute (median of the recent intervals), null when not compressing
    public function rate(wallMs as Number) as Number? {
        if (!isCompressing(wallMs) || _intervals.size() < 2) {
            return null;
        }
        return Math.round(60000.0 / median(_intervals)).toNumber();
    }

    //! Estimated compression depth in cm (experimental), null when not compressing
    public function depthCm(wallMs as Number) as Float? {
        var cpm = rate(wallMs);
        var p2p = _peakToPeak;
        if (cpm == null || p2p == null) {
            return null;
        }
        var omega = (2.0 * Math.PI * cpm / 60.0).toFloat();
        var gain = filterGain(omega);
        return (100.0 * p2p * MG_TO_MS2 / (omega * omega * gain)).toFloat();
    }

    private function processSample(magnitude as Float) as Void {
        _clockMs += _sampleMs;

        var base = _baseline;
        if (base == null) {
            base = magnitude;
        }
        base += _alphaBase * (magnitude - base);
        _baseline = base;

        _smooth += _alphaSmooth * ((magnitude - base) - _smooth);
        var s = _smooth;

        var decayed = _envelope * _envDecay;
        _envelope = s.abs() > decayed ? s.abs() : decayed;

        var threshold = PEAK_FRACTION * _envelope;
        if (threshold < MIN_PEAK_MG) {
            threshold = MIN_PEAK_MG;
        }

        // The previous sample is a peak when it tops both neighbours and the threshold.
        // A parabola through the three samples places the true peak between samples,
        // otherwise 25 Hz quantises a 545 ms interval to 520 or 560 ms.
        if (_prev1 > _prev2 && _prev1 >= s && _prev1 > threshold) {
            var curvature = _prev2 - 2.0 * _prev1 + s;
            var offset = curvature < 0.0 ? 0.5 * (_prev2 - s) / curvature : 0.0;
            var t = _clockMs - _sampleMs + offset * _sampleMs;
            var last = _lastPeakMs;
            if (last == null || t - last >= REFRACTORY_MS) {
                onPeak(t, (_prev1 - 0.25 * (_prev2 - s) * offset).toFloat());
            }
        }
        if (s < _trough) {
            _trough = s;
        }
        _prev2 = _prev1;
        _prev1 = s;
    }

    private function onPeak(t as Float, value as Float) as Void {
        var last = _lastPeakMs;
        if (last != null && t - last <= STALE_MS) {
            _intervals.add(t - last);
            if (_intervals.size() > RATE_WINDOW) {
                _intervals = _intervals.slice(1, _intervals.size());
            }
            var p2p = value - _trough;
            var smoothed = _peakToPeak;
            _peakToPeak = smoothed == null ? p2p : smoothed + DEPTH_SMOOTHING * (p2p - smoothed);
        } else {
            // First compression, or resuming after a pause: old intervals no longer apply
            _intervals = [] as Array<Float>;
            _peakToPeak = null;
        }
        _count++;
        _lastPeakMs = t;
        _trough = value;
    }

    private function clockAt(wallMs as Number) as Float {
        var anchor = _wallMs;
        return anchor == null ? 0.0 : _wallClockMs + (wallMs - anchor);
    }

    //! Combined amplitude gain of the baseline high-pass and smoothing low-pass at omega (rad/s)
    private function filterGain(omega as Float) as Float {
        var wt = omega * _sampleMs / 1000.0;
        var cosWt = Math.cos(wt);
        var b = 1.0 - _alphaBase;
        var highPass = b * 2.0 * Math.sin(wt / 2.0) / Math.sqrt(1.0 - 2.0 * b * cosWt + b * b);
        var s = 1.0 - _alphaSmooth;
        var lowPass = _alphaSmooth / Math.sqrt(1.0 - 2.0 * s * cosWt + s * s);
        return (highPass * lowPass).toFloat();
    }

    private function median(values as Array<Float>) as Float {
        var sorted = values.slice(0, values.size());
        for (var i = 1; i < sorted.size(); i++) {
            var v = sorted[i];
            var j = i - 1;
            while (j >= 0 && sorted[j] > v) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = v;
        }
        var n = sorted.size();
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0;
    }
}
