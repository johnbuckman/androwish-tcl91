/*
 * tcltest-main.c --
 *
 *	Native smoke test for the Tcl 9.1 Android build.
 *
 *	ndk-build bypasses configure, so jni/tcl/tcl-config.mk hand-rolls every
 *	macro configure would have derived.  A macro that is missing or spelled
 *	the 8.6 way does not fail the build -- it fails silently at runtime.
 *	That is how a missing TCL_WIDE_INT_IS_LONG turned into "bad level #0"
 *	from `upvar #0` deep inside tkInit, with arithmetic still apparently
 *	working (bytecode literals are parsed at compile time; only *runtime*
 *	string->integer conversion was broken).
 *
 *	Every check below is an assertion with a non-zero exit, so this is
 *	usable as a build gate rather than something a human has to eyeball.
 *
 *	Build/run with scripts/tcltest-Android.mk, then:
 *	    adb push tcltest /data/local/tmp/ && adb shell /data/local/tmp/tcltest
 *	Exit status 0 = all checks passed.
 */

#include <tcl.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>

static int failures = 0;

#define CHECK(cond, ...)					\
    do {							\
	if (cond) {						\
	    printf("  ok   ");					\
	} else {						\
	    printf("  FAIL ");					\
	    failures++;						\
	}							\
	printf(__VA_ARGS__);					\
	printf("\n");						\
    } while (0)

/*
 * Round-trip a decimal string through Tcl_GetIntFromObj.  This is the exact
 * path that broke: Tcl_GetLongFromObj took its 32-bit-long branch, where
 * (Tcl_WideInt)(ULONG_MAX) overflows to -1, making the range check w <= -1
 * reject every non-negative value.
 */
static void
CheckIntRoundTrip(Tcl_Interp *interp, const char *str, int want)
{
    Tcl_Obj *obj = Tcl_NewStringObj(str, -1);
    int got = 0;
    int ok;

    Tcl_IncrRefCount(obj);
    ok = (Tcl_GetIntFromObj(interp, obj, &got) == TCL_OK) && (got == want);
    Tcl_DecrRefCount(obj);
    CHECK(ok, "Tcl_GetIntFromObj(\"%s\") -> %d", str, got);
}

static void
CheckEval(Tcl_Interp *interp, const char *script, const char *want)
{
    int code = Tcl_Eval(interp, script);
    const char *got = Tcl_GetStringResult(interp);

    CHECK((code == TCL_OK) && (strcmp(got, want) == 0),
	    "[%s] -> \"%s\" (want \"%s\")", script, got, want);
}

int
main(int argc, char **argv)
{
    Tcl_Interp *interp;

    Tcl_FindExecutable(argv[0]);
    interp = Tcl_CreateInterp();
    if (interp == NULL) {
	printf("FAIL: cannot create interp\n");
	return 1;
    }
    printf("Tcl patchlevel %s\n",
	    Tcl_GetVar(interp, "tcl_patchLevel", TCL_GLOBAL_ONLY));

    /*
     * LP64 ABI.  If any of these are wrong the -D flags in tcl-config.mk do
     * not match the compiler that is actually being used.
     */
    printf("\nLP64 ABI\n");
    CHECK(sizeof(void *) == 8, "sizeof(void *) == %u", (unsigned) sizeof(void *));
    CHECK(sizeof(long) == 8, "sizeof(long) == %u", (unsigned) sizeof(long));
    CHECK(sizeof(Tcl_Size) == 8, "sizeof(Tcl_Size) == %u",
	    (unsigned) sizeof(Tcl_Size));
    CHECK(sizeof(Tcl_WideInt) == 8, "sizeof(Tcl_WideInt) == %u",
	    (unsigned) sizeof(Tcl_WideInt));

    /*
     * NB this reflects how *this file* was compiled, not how libtcl was.  It
     * is only meaningful when built via scripts/tcltest-Android.mk, which
     * includes tcl-config.mk so the flags match.  The runtime checks below
     * are the ones that test the library itself.
     */
#ifdef TCL_WIDE_INT_IS_LONG
    CHECK(1, "TCL_WIDE_INT_IS_LONG is defined");
#else
    CHECK(0, "TCL_WIDE_INT_IS_LONG is NOT defined (this is the 'bad level #0' bug)"
	    " -- if you compiled this by hand, use scripts/tcltest-Android.mk");
#endif

    /*
     * Runtime string->integer conversion, the thing that actually broke.
     */
    printf("\nruntime string->integer conversion\n");
    CheckIntRoundTrip(interp, "0", 0);
    CheckIntRoundTrip(interp, "1", 1);
    CheckIntRoundTrip(interp, "42", 42);
    CheckIntRoundTrip(interp, "-1", -1);
    CheckIntRoundTrip(interp, "2147483647", INT_MAX);

    {
	Tcl_Obj *obj = Tcl_NewStringObj("9223372036854775807", -1);
	Tcl_WideInt w = 0;
	int ok;

	Tcl_IncrRefCount(obj);
	ok = (Tcl_GetWideIntFromObj(interp, obj, &w) == TCL_OK)
		&& (w == LLONG_MAX);
	Tcl_DecrRefCount(obj);
	CHECK(ok, "Tcl_GetWideIntFromObj(LLONG_MAX) round-trips");
    }

    /*
     * The original symptom, end to end: `upvar #0` parses its level argument
     * through the conversion path above.
     */
    printf("\nregression: upvar #0 (original 'bad level' symptom)\n");
    CheckEval(interp, "set ::probe 7; proc p {} {upvar #0 probe v; return $v}; p",
	    "7");

    /*
     * Interpreter basics, incl. bignum -> libtommath.
     */
    printf("\ninterpreter basics\n");
    CheckEval(interp, "expr {6*7}", "42");
    CheckEval(interp, "expr {2**64}", "18446744073709551616");
    CheckEval(interp, "string toupper {tcl nine on android}",
	    "TCL NINE ON ANDROID");
    CheckEval(interp, "string length \\u00e9\\u4e2d", "2");

    /*
     * HAVE_STRUCT_STAT_ST_BLKSIZE / _BLOCKS.  Tcl 9 renamed these probes; the
     * config still carried the 8.6 spelling (HAVE_ST_BLKSIZE), so `file stat`
     * silently omitted the members.
     */
    printf("\nfile stat members (HAVE_STRUCT_STAT_ST_*)\n");
    CheckEval(interp,
	    "file stat [info nameofexecutable] s;"
	    "expr {[info exists s(blksize)] && [info exists s(blocks)]"
	    " && $s(blksize) > 0}",
	    "1");

    printf("\n%s (%d failure%s)\n", failures ? "FAILED" : "PASSED",
	    failures, (failures == 1) ? "" : "s");
    return failures ? 1 : 0;
}
