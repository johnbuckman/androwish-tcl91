#!/bin/sh
#
# emulator-smoke.sh --
#
#	Run scripts/smoke.tcl inside the installed APK on an emulator or
#	device and grade the result.
#
#	The four bugs this guards against (see README) were all invisible
#	without a running screen: the app either crashed on startup or drew
#	something subtly wrong.  Nothing about them shows up in a build log,
#	so they need an on-device check.
#
#	Bug 4 in particular is density-dependent, so run this against more
#	than one density -- a 320 dpi tablet AVD and a 420 dpi phone AVD
#	between them would have caught it.
#
# Usage:
#	scripts/emulator-smoke.sh [-s <serial>] [-p <package>]
#
# Exit status 0 = all checks passed.

set -e

SERIAL=""
PKG="tk.tcl.wish.tcl91"
SELF=$(cd "$(dirname "$0")" && pwd)

while [ $# -gt 0 ]; do
    case "$1" in
	-s) SERIAL="-s $2"; shift 2 ;;
	-p) PKG="$2"; shift 2 ;;
	*)  echo "usage: $0 [-s serial] [-p package]" >&2; exit 2 ;;
    esac
done

ADB="adb $SERIAL"

$ADB shell pm list packages | grep -q "^package:$PKG\$" || {
    echo "$PKG is not installed on the target." >&2
    echo "Install the APK first: adb $SERIAL install -r <apk>" >&2
    exit 1
}

DENSITY=$($ADB shell wm density | sed -n 's/.*: *//p' | tr -d '\r' | head -1)
SDK=$($ADB shell getprop ro.build.version.sdk | tr -d '\r')

# Identify the APK under test, loudly.
#
# This is not decoration.  A stale build left on an emulator from an earlier
# session once produced a full set of font failures that were read as a live
# regression in the shipped release; the release itself was fine.  A run that
# does not say which build it exercised is not evidence about any build.
VERNAME=$($ADB shell dumpsys package "$PKG" \
    | sed -n 's/.*versionName=//p' | tr -d '\r' | head -1)
VERCODE=$($ADB shell dumpsys package "$PKG" \
    | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | tr -d '\r' | head -1)
APKPATH=$($ADB shell pm path "$PKG" | sed -n 's/^package://p' | tr -d '\r' | head -1)
INSTALLED=$($ADB shell dumpsys package "$PKG" \
    | sed -n 's/.*lastUpdateTime=//p' | tr -d '\r' | head -1)
# md5 of the installed base.apk: the only way to tell two builds with the same
# versionName apart.
APKSUM=$($ADB shell "md5sum $APKPATH 2>/dev/null || toybox md5sum $APKPATH" \
    | awk '{print $1}' | tr -d '\r' | head -1)

echo "target:    $PKG"
echo "device:    api $SDK, ${DENSITY}dpi"
echo "version:   $VERNAME (code $VERCODE)"
echo "installed: $INSTALLED"
echo "apk md5:   $APKSUM"
echo

# smoke.tcl reports through logcat, so the app needs no writable shared
# storage and this works unchanged under scoped storage.
REMOTE=/data/local/tmp/smoke.tcl
$ADB push "$SELF/smoke.tcl" "$REMOTE" >/dev/null
$ADB shell chmod 644 "$REMOTE"

$ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
$ADB logcat -c 2>/dev/null || true

echo "launching..."
$ADB shell am start -W \
    -a android.intent.action.VIEW \
    -d "file://$REMOTE" \
    -t "text/plain" \
    -n "$PKG/tk.tcl.wish.AndroWishLauncher" >/dev/null

# Poll for the END marker rather than sleeping a fixed amount: first launch
# has to unpack assets and is much slower than subsequent ones.
i=0
while [ $i -lt 60 ]; do
    if $ADB logcat -d -s AWSMOKE 2>/dev/null | grep -q 'END'; then
	break
    fi
    sleep 1
    i=$((i + 1))
done

OUT=$($ADB logcat -d -s AWSMOKE 2>/dev/null | sed -n 's/.*AWSMOKE *: *//p')

if [ -z "$OUT" ]; then
    echo "no AWSMOKE output -- the app probably crashed before running the payload." >&2
    echo "--- last 40 lines of logcat ---" >&2
    $ADB logcat -d 2>/dev/null | tail -40 >&2
    exit 1
fi

echo
echo "$OUT" | grep -v '^BEGIN$\|^END$'
echo

if echo "$OUT" | grep -q 'RESULT PASSED'; then
    echo "PASSED  api $SDK, ${DENSITY}dpi, $PKG $VERNAME, md5 $APKSUM"
    exit 0
fi

echo "FAILED  api $SDK, ${DENSITY}dpi, $PKG $VERNAME, md5 $APKSUM" >&2
echo "Before treating this as a regression, confirm the md5 above is the" >&2
echo "build you meant to test -- reinstall with 'adb $SERIAL install -r'." >&2
exit 1
