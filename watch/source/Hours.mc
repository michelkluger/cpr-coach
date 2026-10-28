import Toybox.Lang;

//! Reads the common subset of OpenStreetMap opening_hours, e.g.
//! "Mo-Fr 08:00-12:00,13:30-17:00; Sa 09:00-12:00; Su off". Anything else
//! (months, sunrise, comments, cut-off text) counts as not understood.
module Hours {
    const DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];
    const DAY = 0;
    const HOLIDAY = 1;
    const TIME = 2;
    const DASH = 3;
    const COMMA = 4;
    const SEMICOLON = 5;
    const OFF = 6;

    //! Open at minute (0-1439) of weekday (0 = Monday)? null when the text is not understood
    function isOpen(text as String, weekday as Number, minute as Number) as Boolean? {
        var week = parse(text);
        if (week == null) {
            return null;
        }
        var ranges = week[weekday];
        for (var i = 0; i < ranges.size(); i++) {
            if (minute >= ranges[i][0] && minute < ranges[i][1]) {
                return true;
            }
        }
        return false;
    }

    //! Open [from, to) minutes per weekday (0 = Monday), or null when the text is not understood.
    //! Rules after ";" replace earlier ones for their days, rules after "," add to them.
    //! Holiday rules (PH, SH) are skipped: the watch doesn't know the holidays.
    function parse(text as String) as Array<Array<[Number, Number]> >? {
        var tokens = tokenize(text);
        if (tokens == null || tokens[0].size() == 0) {
            return null;
        }
        var kinds = tokens[0];
        var values = tokens[1];
        var n = kinds.size();
        var week = [[], [], [], [], [], [], []] as Array<Array<[Number, Number]> >;
        var additive = false;
        var i = 0;
        while (i < n) {
            // Day selector such as "Mo-Fr", "Mo,We" or "PH"; none means every day
            var mask = 0;
            var hasDays = false;
            while (i < n && (kinds[i] == DAY || kinds[i] == HOLIDAY)) {
                hasDays = true;
                if (kinds[i] == DAY) {
                    var day = values[i];
                    var last = day;
                    if (i + 2 < n && kinds[i + 1] == DASH && kinds[i + 2] == DAY) {
                        last = values[i + 2];
                        i += 2;
                    }
                    mask |= 1 << day;
                    while (day != last) {
                        day = (day + 1) % 7;
                        mask |= 1 << day;
                    }
                }
                i++;
                if (i + 1 < n && kinds[i] == COMMA && (kinds[i + 1] == DAY || kinds[i + 1] == HOLIDAY)) {
                    i++;
                } else {
                    break;
                }
            }
            if (!hasDays) {
                mask = 0x7F;
            }

            // Time selector such as "08:00-12:00,13:30-17:00", or "off"
            var ranges = [] as Array<[Number, Number]>;
            if (i < n && kinds[i] == OFF) {
                i++;
            } else {
                while (i + 2 < n && kinds[i] == TIME && kinds[i + 1] == DASH && kinds[i + 2] == TIME) {
                    ranges.add([values[i], values[i + 2]]);
                    i += 3;
                    if (i + 1 < n && kinds[i] == COMMA && kinds[i + 1] == TIME) {
                        i++;
                    } else {
                        break;
                    }
                }
                if (ranges.size() == 0) {
                    return null;
                }
            }

            // Clear all days first so "Fr-Sa 22:00-02:00" keeps Friday's hours past midnight
            for (var d = 0; d < 7; d++) {
                if (!additive && (mask & (1 << d)) != 0) {
                    week[d] = [] as Array<[Number, Number]>;
                }
            }
            for (var d = 0; d < 7; d++) {
                if ((mask & (1 << d)) != 0) {
                    for (var r = 0; r < ranges.size(); r++) {
                        var from = ranges[r][0];
                        var to = ranges[r][1];
                        if (to > from) {
                            week[d].add([from, to]);
                        } else {
                            // Past midnight, e.g. 22:00-02:00
                            week[d].add([from, 1440]);
                            week[(d + 1) % 7].add([0, to]);
                        }
                    }
                }
            }

            if (i < n) {
                if (kinds[i] == SEMICOLON) {
                    additive = false;
                } else if (kinds[i] == COMMA && i + 1 < n && (kinds[i + 1] == DAY || kinds[i + 1] == HOLIDAY)) {
                    additive = true;
                } else {
                    return null;
                }
                i++;
            }
        }
        return week;
    }

    //! Token kinds and values (weekday, minute of day), or null on anything unknown
    function tokenize(text as String) as [Array<Number>, Array<Number>]? {
        var chars = text.toCharArray();
        var n = chars.size();
        var kinds = [] as Array<Number>;
        var values = [] as Array<Number>;
        var i = 0;
        while (i < n) {
            var c = chars[i];
            var start = i;
            if (c == ' ') {
                i++;
            } else if (c == '-' || c == ',' || c == ';') {
                kinds.add(c == '-' ? DASH : (c == ',' ? COMMA : SEMICOLON));
                values.add(0);
                i++;
            } else if (isDigit(c)) {
                // H:MM or HH:MM
                var h = 0;
                while (i < n && i - start < 2 && isDigit(chars[i])) {
                    h = h * 10 + chars[i].toNumber() - 48;
                    i++;
                }
                if (i + 2 >= n || chars[i] != ':' || !isDigit(chars[i + 1]) || !isDigit(chars[i + 2])) {
                    return null;
                }
                var m = (chars[i + 1].toNumber() - 48) * 10 + chars[i + 2].toNumber() - 48;
                i += 3;
                if (h > 24 || m > 59) {
                    return null;
                }
                kinds.add(TIME);
                values.add(h * 60 + m);
            } else if (isLetter(c)) {
                while (i < n && isLetter(chars[i])) {
                    i++;
                }
                var word = text.substring(start, i) as String;
                var kind = OFF;
                var value = 0;
                for (var d = 0; d < DAYS.size(); d++) {
                    if (word.equals(DAYS[d])) {
                        kind = DAY;
                        value = d;
                    }
                }
                if (word.equals("PH") || word.equals("SH")) {
                    kind = HOLIDAY;
                } else if (kind != DAY && !word.equals("off") && !word.equals("closed")) {
                    return null;
                }
                kinds.add(kind);
                values.add(value);
            } else {
                return null;
            }
        }
        return [kinds, values];
    }

    function isDigit(c as Char) as Boolean {
        return c.toNumber() >= 48 && c.toNumber() <= 57;
    }

    function isLetter(c as Char) as Boolean {
        var code = c.toNumber();
        return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    }
}
