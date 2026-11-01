#!/bin/sh
#
# emulator-suite.sh --
#
#	Run the Tcl or Tk test suite inside the installed APK (see
#	scripts/suite.tcl).  A test file that kills the app (a panic, or an
#	[exit]) or makes no progress for $HANG seconds is recorded and
#	skipped, and the run goes on from the next file.
#
# Usage:
#	scripts/emulator-suite.sh <serial> tcl|tk <tests-dir> <outdir>
#
#	<tests-dir> is tests/ from the Tcl or Tk source release the APK
#	was built from.  Output: <outdir>/round*.txt (tcltest's output),
#	<outdir>/crashed.txt, <outdir>/summary.txt.

SER=${1:?usage}; SUITE=${2:?usage}; TESTS=${3:?usage}; OUT=${4:?usage}
HANG=${HANG:-300}
A="adb -s $SER"; PKG=tk.tcl.wish.tcl91
B=/sdcard/Android/data/$PKG/files/t
SELF=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"; : > "$OUT/crashed.txt"

$A shell rm -rf $B; $A shell mkdir -p $B/$SUITE
$A push "$TESTS/." $B/$SUITE/ >/dev/null 2>&1   # adb may end with a spurious EOF error
$A push "$SELF/suite.tcl" $B/suite.tcl >/dev/null
NOT=""
for round in $(seq 1 60); do
    O=$B/round$round.txt
    printf 'set suite %s\nset testdir %s\nset outfile %s\nset notfile {%s}\n' \
	"$SUITE" "$B/$SUITE" "$O" "$NOT" > "$OUT/conf.tcl"
    $A push "$OUT/conf.tcl" $B/conf.tcl >/dev/null
    $A shell am force-stop $PKG; $A logcat -c
    $A shell am start -W -a android.intent.action.VIEW -d "file://$B/suite.tcl" \
	-t text/plain -n $PKG/tk.tcl.wish.AndroWishLauncher >/dev/null
    last=""; still=0; state=""
    while :; do
	sleep 5
	# done: tcltest's closing summary ":<tab>Total ..." -- not "Sourced N Test Files",
	# which tcltest.test's nested all-single.tcl also prints. (A test can break
	# [exec], so the END log may not come.)
	if $A shell "grep -q '^:[[:space:]]Total' $O 2>/dev/null"; then state=done; break; fi
	if $A logcat -d -s AWSUITE | grep -q ' x END'; then state=done; break; fi
	sz=$($A shell "wc -c < $O 2>/dev/null" | tr -d '\r ')
	if [ -z "$($A shell pidof $PKG | tr -d '\r')" ]; then state=crash; break; fi
	if [ "$sz" = "$last" ]; then still=$((still + 5)); else still=0; last=$sz; fi
	[ $still -ge $HANG ] && { state=hang; break; }
    done
    $A pull $O "$OUT/round$round.txt" >/dev/null 2>&1
    $A pull $O.err "$OUT/round$round.err" >/dev/null 2>&1
    $A logcat -d -s AWSUITE | sed -n 's/.*AWSUITE *: x //p' > "$OUT/round$round.log"
    # trust "done" only if what we pulled shows it; otherwise resume like a crash
    if [ $state = done ] && ! grep -q '^:[[:space:]]Total' "$OUT/round$round.txt" \
	&& ! grep -q '^END$' "$OUT/round$round.log"; then
	state=crash
    fi
    [ $state = done ] && break
    # every file this round started; the last one is the culprit
    files=$(grep -E '^[A-Za-z0-9_.-]+\.test$' "$OUT/round$round.txt" 2>/dev/null)
    bad=$(echo "$files" | tail -1)
    [ -z "$bad" ] && { echo "round $round: no test file started ($state)" >> "$OUT/crashed.txt"; break; }
    echo "$bad $state" >> "$OUT/crashed.txt"
    NOT="$NOT $(echo $files)"
    $A shell am force-stop $PKG
done
$A shell am force-stop $PKG
{
    echo "version: $($A shell dumpsys package $PKG | sed -n 's/.*versionName=//p' | tr -d '\r' | head -1)"
    # counted per test (suite.tcl runs -verbose bps), so a crashed round still counts
    # distinct test names: tcltest prints a failure twice ("==== name desc FAILED", "==== name FAILED")
    n() { cat "$OUT"/round*.txt | sed -n -E "$1" | sort -u | wc -l | tr -d ' '; }
    echo "Passed $(n 's/^\+\+\+\+ ([^ ]+) PASSED$/\1/p')" \
	"Skipped $(n 's/^\+\+\+\+ ([^ ]+) SKIPPED.*/\1/p')" \
	"Failed $(n 's/^==== ([^ ]+) .*FAILED$/\1/p')"
    echo "Sourced: $(cat "$OUT"/round*.txt | grep -cE '^[A-Za-z0-9_.-]+\.test$') files"
    echo "Crashed/hung: $(tr '\n' ' ' < "$OUT/crashed.txt")"
} > "$OUT/summary.txt"
cat "$OUT/summary.txt"
