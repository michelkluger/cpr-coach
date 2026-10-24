import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

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
