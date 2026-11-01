# Load every package AndroWish can find; report through logcat tag AWPKG.
proc L {msg} { catch {exec /system/bin/log -t AWPKG "x $msg"} }
after 1500 {
    L "patchlevel tcl [info patchlevel] tk $::tk_patchLevel"
    catch {package require __nonexistent__}
    set ok 0; set bad {}
    set skip {}
    catch {set f [open /data/local/tmp/pkgskip.txt]; set skip [read $f]; close $f}
    foreach p [lsort [package names]] {
        if {$p in $skip} { L "SKIP $p"; continue }
        L "TRY $p"
        if {[catch {package require $p} v]} {
            lappend bad $p
            L "FAILPKG $p : [string range [string map {\n " "} $v] 0 140]"
        } else { incr ok }
    }
    L "SUMMARY ok $ok fail [llength $bad]"
    L "FAILED [lsort $bad]"
    L "END"
    after 500 exit
}
