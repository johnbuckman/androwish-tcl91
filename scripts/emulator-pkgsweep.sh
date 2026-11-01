#!/bin/sh
#
# emulator-pkgsweep.sh --
#
#	Try [package require] on every package the installed APK can find,
#	via scripts/pkgsweep.tcl (reports through logcat tag AWPKG).  When a
#	package takes the whole app down (a Tcl_Panic, e.g. Expect's old
#	channel type), it is added to a skip list and the sweep is rerun, so
#	one run always ends with a complete picture.
#
#	Compare two builds by running it against each and diffing the
#	FAILPKG lines: 1.0b0 and 0.1-alpha gave identical results.
#
# Usage:
#	scripts/emulator-pkgsweep.sh <serial> [outfile]
#
# Prints SUMMARY / FAILED lines and the packages that crashed the app.

SER=${1:?usage: emulator-pkgsweep.sh <serial> [outfile]}
OUT=${2:-pkgsweep-$SER.txt}
PKG=tk.tcl.wish.tcl91
SELF=$(cd "$(dirname "$0")" && pwd)
A="adb -s $SER"
SKIP=""
CRASHED=""

$A push "$SELF/pkgsweep.tcl" /data/local/tmp/pkgsweep.tcl >/dev/null
$A shell chmod 644 /data/local/tmp/pkgsweep.tcl

for round in $(seq 1 100); do
    printf '%s\n' $SKIP | $A shell "cat > /data/local/tmp/pkgskip.txt; chmod 644 /data/local/tmp/pkgskip.txt"
    $A shell am force-stop $PKG
    $A logcat -c
    $A shell am start -W -a android.intent.action.VIEW \
	-d file:///data/local/tmp/pkgsweep.tcl -t text/plain \
	-n $PKG/tk.tcl.wish.AndroWishLauncher >/dev/null
    i=0
    while [ $i -lt 150 ]; do
	$A logcat -d -s AWPKG | grep -q ' x END' && break
	# the app died: stop waiting
	[ $i -gt 10 ] && [ -z "$($A shell pidof $PKG | tr -d '\r')" ] && break
	sleep 1; i=$((i + 1))
    done
    $A logcat -d -s AWPKG | sed -n 's/.*AWPKG *: x //p' > "$OUT"
    grep -q '^SUMMARY' "$OUT" && break
    last=$(grep '^TRY ' "$OUT" | tail -1 | cut -d' ' -f2-)
    [ -z "$last" ] && { echo "no progress; see $OUT" >&2; exit 1; }
    CRASHED="$CRASHED $last"; SKIP="$SKIP $last"
done

echo "version: $($A shell dumpsys package $PKG | sed -n 's/.*versionName=//p' | tr -d '\r' | head -1)"
grep -E '^(patchlevel|SUMMARY|FAILED)' "$OUT"
echo "crashed the app:$CRASHED"
