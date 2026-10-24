import Toybox.Lang;
import Toybox.Math;

//! Synthetic wrist accelerometer data for the detector tests
(:debug)
module SyntheticCpr {
    const RATE_HZ = 25;

    //! Feeds `seconds` of CPR into the detector, one 1-second batch at a time.
    //! The wrist moves vertically as a sinusoid of `depthCm` (peak to peak) at
    //! `cpm`; cpm 0 means a still wrist. Gravity is tilted by `tilt` radians
    //! from the z axis and uniform noise of +/- noiseMg is added to each axis.
    //! Returns the wall clock after the last batch.
    function feed(det as CompressionDetector, startMs as Number, seconds as Number, cpm as Float, depthCm as Float,
            noiseMg as Number, tilt as Float) as Number {
        var omega = 2.0 * Math.PI * cpm / 60.0;
        var ampMg = (depthCm / 100.0 / 2.0) * omega * omega / 0.00980665;
        var gx = Math.sin(tilt);
        var gz = Math.cos(tilt);
        var seed = 12345l;
        var wall = startMs;
        for (var sec = 0; sec < seconds; sec++) {
            var x = new Array<Number>[RATE_HZ];
            var y = new Array<Number>[RATE_HZ];
            var z = new Array<Number>[RATE_HZ];
            for (var i = 0; i < RATE_HZ; i++) {
                var t = (startMs / 1000.0) + sec + i.toFloat() / RATE_HZ;
                var force = 1000.0 + ampMg * Math.sin(omega * t);
                var n = [0, 0, 0] as Array<Number>;
                if (noiseMg > 0) {
                    for (var k = 0; k < 3; k++) {
                        seed = (seed * 1103515245l + 12345l) % 2147483648l;
                        n[k] = (seed % (2 * noiseMg + 1)).toNumber() - noiseMg;
                    }
                }
                x[i] = (force * gx).toNumber() + n[0];
                y[i] = n[1];
                z[i] = (force * gz).toNumber() + n[2];
            }
            wall += 1000;
            det.addSamples(x, y, z, wall);
        }
        return wall;
    }
}
