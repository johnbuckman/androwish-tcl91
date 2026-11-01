#
# suite.tcl --
#
#	Run Tcl's or Tk's own test suite (tests/*.test from the matching
#	source release) inside the installed APK -- the app is the only
#	interpreter on the device -- single-process, the way Tk's all.tcl
#	runs it.  Driven by scripts/emulator-suite.sh, which pushes the
#	tests and a conf.tcl and restarts the run after a crash or hang.
#
#	conf.tcl sets: suite (tcl|tk), testdir, outfile, notfile (files
#	already run, or that crashed/hung the app).
#

set B /sdcard/Android/data/tk.tcl.wish.tcl91/files/t
source $B/conf.tcl
file mkdir $B/work $B/tmp
cd $B/work                       ;# tcltest refuses an unreadable cwd ("/")
set ::argv {}
proc L {msg} { catch {exec /system/bin/log -t AWSUITE "x $msg"} }

after 2000 {
    L "START $suite tcl [info patchlevel] tk $::tk_patchLevel"
    if {[catch {
	package require tcltest 2.2
	tcltest::configure -singleproc 1 -verbose bps -testdir $testdir -tmpdir $B/tmp \
	    -outfile $outfile -errfile $outfile.err -notfile $notfile
	if {$suite eq "tk"} {
	    # as tk/tests/all.tcl: skip the other platforms' files
	    tcltest::configure -notfile [concat $notfile testutils.test unix*.test win*.test]
	}
	tcltest::runAllTests
    } err]} { L "ERROR $err | $::errorInfo" }
    L "END"
    after 500 exit
}
