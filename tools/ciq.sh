#!/usr/bin/env bash
# Build, test and run the watch app with the Connect IQ SDK (Git Bash on Windows).
#
#   tools/ciq.sh build [device]   compile watch/bin/cpr-coach.prg (default fenix7)
#   tools/ciq.sh test [device]    compile with unit tests and run them in the simulator
#   tools/ciq.sh run [device]     compile and launch in the simulator
#   tools/ciq.sh export           build the store package watch/bin/cpr-coach.iq for all devices
#   tools/ciq.sh data             refresh the AED tiles from OpenStreetMap
#   tools/ciq.sh demo PAGE [dev]  open PAGE (start|disclaimer|cpr|slow|training|aed|position|summary) with demo
#                                 state in the simulator and save watch/bin/screens/DEV-PAGE.png
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WATCH="$ROOT/watch"
OUT="$WATCH/bin"
SDK_BIN="$(cygpath -u "$(tr -d '\r' < "$APPDATA/Garmin/ConnectIQ/current-sdk.cfg")")bin"
JAVA="$(ls -d "$USERPROFILE"/.garmin/jdk/jdk-17*/bin | head -1)/java"
KEY="$USERPROFILE/.garmin/developer_key.der"
DEVICE="${2:-fenix7}"
JUNGLE="$(cygpath -w "$WATCH/monkey.jungle")"

monkeyc() {
  "$JAVA" -Xms1g -Dfile.encoding=UTF-8 -cp "$SDK_BIN/monkeybrains.jar" com.garmin.monkeybrains.Monkeybrains \
    -f "$JUNGLE" -y "$KEY" -w "$@"
}

monkeydo() {
  "$JAVA" -classpath "$SDK_BIN/monkeybrains.jar" com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux \
    -s "$SDK_BIN/shell.exe" "$@"
}

# Start the simulator (detached, so it outlives this shell) and push the app to it
push() {
  if ! tasklist //FI "IMAGENAME eq simulator.exe" | grep -qi simulator.exe; then
    cmd //c start "" "$(cygpath -w "$SDK_BIN/simulator.exe")"
    sleep 8
  fi
  monkeydo "$@"
}

mkdir -p "$OUT"
case "${1:-build}" in
  build)
    monkeyc -d "$DEVICE" -o "$OUT/cpr-coach.prg"
    ;;
  test)
    monkeyc -d "$DEVICE" -o "$OUT/cpr-coach-test.prg" --unit-test
    # monkeydo exits non-zero even when every test passes, so judge by the summary line
    push -f "$OUT/cpr-coach-test.prg" -d "$DEVICE" -t | tee "$OUT/test.log" || true
    grep -q "^PASSED" "$OUT/test.log"
    ;;
  run)
    monkeyc -d "$DEVICE" -o "$OUT/cpr-coach.prg"
    push -f "$OUT/cpr-coach.prg" -d "$DEVICE"
    ;;
  export)
    monkeyc -e -r -o "$OUT/cpr-coach.iq"
    ;;
  data)
    (cd "$ROOT" && uv run python -I data/build_aeds.py --refresh)
    ;;
  demo)
    PAGE="${2:-cpr}"
    DEVICE="${3:-fenix7}"
    printf '// Written by tools/ciq.sh demo <page>\n(:demo)\nmodule DemoConfig {\n    const PAGE = "%s";\n}\n' "$PAGE" \
      > "$WATCH/demo/DemoConfig.mc"
    JUNGLE="$JUNGLE;$(cygpath -w "$WATCH/demo.jungle")"
    monkeyc -d "$DEVICE" -o "$OUT/cpr-coach-demo.prg"
    push -f "$OUT/cpr-coach-demo.prg" -d "$DEVICE" > /dev/null 2>&1 &
    sleep 9
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ROOT/tools/screenshot.ps1")" \
      -Out "$(cygpath -w "$OUT/screens/$DEVICE-$PAGE.png")"
    echo "$OUT/screens/$DEVICE-$PAGE.png"
    ;;
  *)
    sed -n '2,11p' "$0"
    exit 1
    ;;
esac
