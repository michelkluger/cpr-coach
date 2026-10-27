import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Drawing helpers shared by the views
module Ui {
    const CENTER = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    function clear(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }

    //! Text centred horizontally at a fraction of the screen height
    function text(dc as Graphics.Dc, yFraction as Float, font as Graphics.FontType, color as Graphics.ColorType, value as String) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, (dc.getHeight() * yFraction).toNumber(), font, value, CENTER);
    }

    //! Text wrapped into a box of the given width/height fractions, centred on yFraction
    function wrapped(dc as Graphics.Dc, yFraction as Float, widthFraction as Float, heightFraction as Float,
            font as Graphics.FontType, color as Graphics.ColorType, value as String) as Void {
        if (value.length() == 0) {
            return;
        }
        var w = (dc.getWidth() * widthFraction).toNumber();
        var h = (dc.getHeight() * heightFraction).toNumber();
        var fitted = Graphics.fitTextToArea(value, font, w, h, true);
        text(dc, yFraction, font, color, fitted != null ? fitted : value);
    }

    //! Blocks of [text, color] wrapped to the screen's real font metrics and stacked,
    //! centred vertically. Robust across 218-466 px screens where font sizes differ.
    function stack(dc as Graphics.Dc, font as Graphics.FontType, blocks as Array<[String, Graphics.ColorType]>) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var lineHeight = dc.getFontHeight(font);
        var gap = lineHeight / 3;
        var fitted = [] as Array<String>;
        var heights = [] as Array<Number>;
        var total = 0;
        for (var i = 0; i < blocks.size(); i++) {
            var text = Graphics.fitTextToArea(blocks[i][0], font, (w * 0.72).toNumber(), h, false);
            var value = text != null ? text : blocks[i][0];
            var lines = 1;
            for (var rest = value; rest.find("\n") != null; lines++) {
                rest = rest.substring((rest.find("\n") as Number) + 1, rest.length()) as String;
            }
            fitted.add(value);
            heights.add(lines * lineHeight);
            total += lines * lineHeight + (i > 0 ? gap : 0);
        }
        var y = (h - total) / 2;
        for (var i = 0; i < blocks.size(); i++) {
            dc.setColor(blocks[i][1], Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y + heights[i] / 2, font, fitted[i], CENTER);
            y += heights[i] + gap;
        }
    }

    //! Progress ring along the bezel, clockwise from 12 o'clock
    function ring(dc as Graphics.Dc, fraction as Float, color as Graphics.ColorType) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var pen = dc.getWidth() / 32;
        var r = cx - pen / 2 - 1;
        dc.setPenWidth(pen);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        if (fraction > 0.005) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            var end = 90 - (360 * (fraction > 1.0 ? 1.0 : fraction)).toNumber();
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 90, (end + 360) % 360);
        }
        dc.setPenWidth(1);
    }

    //! Button positions on every supported watch, in degrees counter-clockwise from 3 o'clock
    const START_DEG = 30;
    const BACK_DEG = -30;
    //! Only on 5-button watches; touch watches send swipes as the same page events
    const UP_DEG = 180;
    const DOWN_DEG = -150;

    //! Arc on the bezel next to a physical button
    function buttonHint(dc as Graphics.Dc, degrees as Number, color as Graphics.ColorType) as Void {
        var c = dc.getWidth() / 2;
        var pen = dc.getWidth() / 40;
        dc.setPenWidth(pen);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(c, dc.getHeight() / 2, c - pen / 2 - 1, Graphics.ARC_COUNTER_CLOCKWISE, (degrees + 350) % 360, (degrees + 370) % 360);
        dc.setPenWidth(1);
    }

    //! BACK button hint with a return arrow beside it, on watches that have the button
    function backHint(dc as Graphics.Dc) as Void {
        if ((System.getDeviceSettings().inputButtons & System.BUTTON_INPUT_ESC) == 0) {
            return;
        }
        buttonHint(dc, BACK_DEG, Graphics.COLOR_WHITE);
        var c = dc.getWidth() / 2;
        var size = dc.getWidth() / 32;
        var dist = c - dc.getWidth() / 40 - 2 * size;
        var x = c + (dist * 0.866).toNumber();
        var y = dc.getHeight() / 2 + dist / 2;
        // Three-quarter circle ending in a head pointing down, like Garmin's own revert icon
        dc.setPenWidth(size / 3 + 1);
        dc.drawArc(x, y, size, Graphics.ARC_CLOCKWISE, 180, 270);
        dc.setPenWidth(1);
        dc.fillPolygon([[x - size * 3 / 2, y], [x - size / 2, y], [x - size, y + size * 2 / 3]] as Array<[Numeric, Numeric]>);
    }

    //! UP/DOWN marks with arrows on the left bezel, or swipe chevrons at the
    //! top and bottom edge on watches without those buttons
    function upDownHint(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var size = w / 28;
        var both = System.BUTTON_INPUT_UP | System.BUTTON_INPUT_DOWN;
        if ((System.getDeviceSettings().inputButtons & both) != both) {
            arrow(dc, w / 2, size + 2, size, 0.0, Graphics.COLOR_LT_GRAY);
            arrow(dc, w / 2, h - size - 2, size, Math.PI.toFloat(), Graphics.COLOR_LT_GRAY);
            return;
        }
        buttonHint(dc, UP_DEG, Graphics.COLOR_WHITE);
        buttonHint(dc, DOWN_DEG, Graphics.COLOR_WHITE);
        var dist = w / 2 - w / 40 - size * 3 / 2;
        arrow(dc, w / 2 - dist, h / 2, size, 0.0, Graphics.COLOR_WHITE);
        arrow(dc, w / 2 - (dist * 0.866).toNumber(), h / 2 + dist / 2, size, Math.PI.toFloat(), Graphics.COLOR_WHITE);
    }

    //! Arrow centred on (cx, cy) pointing at angle (radians clockwise from screen-up)
    function arrow(dc as Graphics.Dc, cx as Number, cy as Number, size as Number, angle as Float, color as Graphics.ColorType) as Void {
        var shape = [[0.0, -1.0], [0.6, 0.6], [0.0, 0.25], [-0.6, 0.6]];
        var c = Math.cos(angle);
        var s = Math.sin(angle);
        var points = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < shape.size(); i++) {
            var x = shape[i][0] * size;
            var y = shape[i][1] * size;
            points.add([cx + x * c - y * s, cy + x * s + y * c]);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(points);
    }
}
