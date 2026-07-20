#
# smoke.tcl --
#
#	On-device regression payload for the AndroWish/Tcl 9.1 port.
#
#	Each of the four bugs fixed between "it links" and "it runs" was
#	invisible without a running screen, which is what made them expensive
#	to find.  This asserts all four, plus the console wiring, and reports
#	through logcat (tag AWSMOKE) so scripts/emulator-smoke.sh can grade it
#	without a human looking at the display.
#
#	Launched by emulator-smoke.sh via a file:// VIEW intent -- which is
#	itself worth exercising, since the intent argv path in tkZipMain.c had
#	live int*/Tcl_Size* out-param bugs of the same class as bug 1.
#

# Counters live in their own namespace: check bodies run at #0, and a body
# using [scan ... n] would otherwise clobber a global counter named n.
namespace eval smoke {
    variable fails 0
    variable n 0
}

proc report {ok what {detail ""}} {
    variable smoke::fails
    variable smoke::n
    incr smoke::n
    set tag [expr {$ok ? "ok" : "FAIL"}]
    if {!$ok} { incr smoke::fails }
    catch {exec /system/bin/log -t AWSMOKE "$tag $what $detail"}
}

proc note {msg} {
    # Leading "-" would be eaten as an option by log(1).
    catch {exec /system/bin/log -t AWSMOKE "info $msg"}
}

# Poll until script returns non-zero, or timeout.  main.tcl installs the
# Demos menu from an after-driven retry loop (up to 80 x 150ms), so a check
# that runs the instant the payload starts would race it.
proc waitFor {script {ms 15000}} {
    set deadline [expr {[clock milliseconds] + $ms}]
    while {[clock milliseconds] < $deadline} {
        if {![catch {uplevel #0 $script} r] && $r} { return 1 }
        after 250
        update
    }
    return 0
}

proc check {what script expected} {
    if {[catch {uplevel #0 $script} res]} {
        report 0 $what "error: $res"
    } else {
        report [expr {$res eq $expected}] $what "got '$res' want '$expected'"
    }
}

# Does not error == pass.  For calls whose return value is not meaningful
# under the SDL window-manager emulation, but whose argument marshalling is
# exactly the int*/Tcl_Size* path that corrupted the stack.
proc checkNoError {what script} {
    if {[catch {uplevel #0 $script} res]} {
        report 0 $what "error: $res"
    } else {
        report 1 $what "ok ('$res')"
    }
}

catch {exec /system/bin/log -t AWSMOKE "BEGIN"}

# ---------------------------------------------------------------- bug 2 ----
# Runtime string->integer conversion.  Broke when TCL_WIDE_INT_IS_LONG was
# undefined; surfaced as `bad level "#0"` from upvar inside tkInit.
check "int-conversion/upvar-hash-zero" {
    set ::probe 7
    proc smokeUpvar {} {upvar #0 probe v; return $v}
    smokeUpvar
} 7
check "int-conversion/scan" {
    expr {[scan "2147483647" %d smokeScanned] == 1 && $smokeScanned == 2147483647}
} 1

# ---------------------------------------------------------------- bug 1 ----
# Stack corruption from int* where Tcl 9 wants Tcl_Size*.  `wm title` was the
# crasher; the others below walk the same out-param family.
check "wm/title-roundtrip" {
    wm title . "smoke-title"
    wm title .
} "smoke-title"
# The SDL window manager does not honour geometry requests (the toplevel is
# the whole screen), so only the round-trip through the argument marshalling
# is asserted, not the effect.
check "wm/geometry-parses" {
    wm geometry . "200x150+0+0"
    expr {[scan [wm geometry .] "%dx%d+%d+%d" \
            smokeW smokeH smokeX smokeY] == 4}
} 1
checkNoError "wm/colormapwindows-marshalling" {
    wm colormapwindows . [list .]
    wm colormapwindows .
}
check "wm/command-splitlist" {
    wm command . [list wish -foo bar]
    llength [wm command .]
} 3

# ---------------------------------------------------------------- bug 3 ----
# Bundled DejaVu faces must be present and resolvable.
check "font/default-family-is-bundled" {
    expr {[string match -nocase "*DejaVu*" [font actual TkDefaultFont -family]] ? 1 : 0}
} 1
check "font/fixed-family-is-mono" {
    expr {[string match -nocase "*Mono*" [font actual TkFixedFont -family]] ? 1 : 0}
} 1
foreach {label want} {Helvetica Sans courier Mono times Serif} {
    check "font/generic-$label-maps-to-$want" [format {
        expr {[string match -nocase {*%s*} [font actual [list %s 10] -family]] ? 1 : 0}
    } $want $label] 1
}

# ---------------------------------------------------------------- bug 4 ----
# High-DPI scaling.  Tk computed the right pixel size; the emulated
# XListFonts answered generic families with a hardcoded XLFD carrying pixel
# size 12, which X11 reads as a *fixed bitmap* font, so Tk threw its own
# (correct) size away.  Synthesized entries must use pixel size 0 = scalable.
#
# Guard: a 10-point font must actually occupy ~10 points on screen.  With the
# bug this collapsed to ~12px regardless of density.
set f [font create -family Helvetica -size 10]
set wantPx [winfo fpixels . 10p]
set gotPx  [font metrics $f -linespace]
note "density [winfo fpixels . 1i] dpi, tk scaling [tk scaling],\
      10p = $wantPx px, Helvetica-10 linespace = $gotPx px,\
      actual size [font actual $f -size]"
report [expr {$gotPx >= 0.75 * $wantPx && $gotPx <= 2.5 * $wantPx}] \
        "font/10pt-scales-with-dpi" "linespace ${gotPx}px vs 10p = ${wantPx}px"

# Control: an exact family name bypasses the generic-family fallback.  If
# this passes while the generic checks above fail, the fault is in the
# fallback (SdlTkListFonts) or in CreateClosestFont's TkFontGetPixels == 0
# guard, not in the font machinery as a whole.
set exact [font create -family "DejaVu LGC Sans" -size 10]
report [expr {[font actual $exact -size] == 10}] \
        "font/exact-family-honours-size" \
        "actual size [font actual $exact -size],\
         linespace [font metrics $exact -linespace]px"

# Same again through the size-0-is-scalable path specifically: two different
# requested sizes must produce two different pixel sizes.
set small [font create -family Helvetica -size 8]
set large [font create -family Helvetica -size 24]
report [expr {[font metrics $large -linespace] > [font metrics $small -linespace]}] \
        "font/distinct-sizes-are-distinct" \
        "8pt=[font metrics $small -linespace] 24pt=[font metrics $large -linespace]"

# ------------------------------------------------------------- console ----
# console.tcl runs in the same interp family as wish, so `console eval` works;
# main.tcl relies on that to install the File > Demos menu.
# Only meaningful on the interactive launch path: a file:// script launch
# runs without a console, so these are skipped rather than failed.
if {[catch {console eval {info tclversion}}]} {
    note "no console on this launch path -- skipping console checks"
} else {
    check "console/eval-reaches-console-interp" {
        console eval {expr {1+1}}
    } 2
    # main.tcl installs Demos only on the interactive launch path; a file://
    # script launch runs the script instead, so ::aw_demos is never defined
    # and there is nothing to assert.  Verified on api 34 / 320dpi: the File
    # menu there is Source... / Hide Console / Clear Console / Exit.
    if {![info exists ::aw_demos]} {
        note "main.tcl demo machinery absent (script launch) -- skipping\
              Demos menu check; run the app interactively to exercise it"
    } else {
    check "console/demos-menu-installed" {
        waitFor {console eval {
            # Inside the console interp the console *is* ".".
            set m .menubar.file
            set found 0
            if {[winfo exists $m]} {
                for {set i 0} {$i <= [$m index end]} {incr i} {
                    if {![catch {$m entrycget $i -label} l] && $l eq "Demos"} {
                        set found 1
                    }
                }
            }
            set found
        }}
    } 1
    }
    catch {
        note "console File menu entries:\
              [console eval {set o {}; set m .menubar.file
                  if {[winfo exists $m]} {
                      for {set i 0} {$i <= [$m index end]} {incr i} {
                          catch {lappend o [$m entrycget $i -label]}
                      }
                  }; set o}]"
        note "fallback .awmenu exists: [winfo exists .awmenu]"
    }
}

# ------------------------------------------------------------------ done ----
catch {exec /system/bin/log -t AWSMOKE \
        "RESULT [expr {$smoke::fails ? {FAILED} : {PASSED}}]\
         $smoke::fails/$smoke::n failed"}
catch {exec /system/bin/log -t AWSMOKE "END"}
after 1500 exit
