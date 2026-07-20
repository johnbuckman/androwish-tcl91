#!/bin/sh
#
# tclcfg-audit.sh --
#
#	Diff the hand-rolled jni/tcl/tcl-config.mk against what a real
#	configure run derives for the Android target.
#
#	ndk-build never runs configure, so tcl-config.mk asserts by hand every
#	macro configure would have probed for.  A macro that is absent, or
#	spelled the Tcl 8.6 way, does not break the build -- it changes
#	behaviour silently at runtime.  Two real examples from this port:
#
#	  TCL_WIDE_INT_IS_LONG       missing -> Tcl_GetIntFromObj rejected
#	                             every non-negative integer on arm64,
#	                             surfacing as `bad level "#0"` in tkInit.
#	  HAVE_STRUCT_STAT_ST_BLKSIZE  missing; the config carried the 8.6
#	                             spelling HAVE_ST_BLKSIZE, which Tcl 9
#	                             does not test anywhere, so `file stat`
#	                             quietly under-reported.
#
#	Run this after any Tcl version bump.  It only reports -- it never
#	edits tcl-config.mk, because the two lists legitimately differ (see
#	the exclusion notes in tcl-config.mk itself).
#
# Usage:
#	scripts/tclcfg-audit.sh <path-to-build-tree>
#
# Requires ANDROID_NDK_HOME.

set -e

TREE="${1:?usage: tclcfg-audit.sh <path-to-build-tree>}"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME}"
: "${API:=21}"

TCLSRC="$TREE/jni/tcl"
CONFIGMK="$TCLSRC/tcl-config.mk"
[ -f "$CONFIGMK" ] || { echo "no $CONFIGMK" >&2; exit 1; }

HOSTTAG=$(ls "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" | head -1)
TC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOSTTAG/bin"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "=== cross-configuring Tcl for aarch64-linux-android (API $API) ==="
(
    cd "$WORK"
    CC="$TC/aarch64-linux-android$API-clang" \
    AR="$TC/llvm-ar" RANLIB="$TC/llvm-ranlib" \
    tcl_cv_sys_version=Linux-4.4 \
	"$TCLSRC/unix/configure" \
	    --host=aarch64-linux-android \
	    --build=x86_64-unknown-linux-gnu \
	    --enable-64bit >configure.log 2>&1
) || { echo "configure failed; see $WORK/configure.log" >&2; exit 1; }

# What configure derived.
sed -n "s/^TCL_DEFS='//p" "$WORK/tclConfig.sh" | tr ' ' '\n' \
    | sed -n 's/^-D\([A-Za-z_0-9]*\).*/\1/p' | sort -u >"$WORK/from-configure"

# What we assert by hand.
sed -n 's/.*/&/p' "$CONFIGMK" | grep -oE -- '-D[A-Za-z_0-9]+' \
    | sed 's/^-D//' | sort -u >"$WORK/from-configmk"

echo
echo "=== in configure, NOT in tcl-config.mk ==="
echo "    (filtered to macros Tcl 9 actually references -- the rest is"
echo "     autoconf boilerplate.  Check each against the NDK sysroot before"
echo "     adopting: this configure run still leaks some build-host results,"
echo "     which is how TCL_WIDE_CLICKS slipped through and broke the build.)"
echo
comm -23 "$WORK/from-configure" "$WORK/from-configmk" | while read -r m; do
    if grep -rql --include='*.c' --include='*.h' "\\b$m\\b" \
	    "$TCLSRC/generic" "$TCLSRC/unix" 2>/dev/null; then
	printf '    %s\n' "$m"
    fi
done

echo
echo "=== in tcl-config.mk, dead for Tcl 9 ==="
echo "    (do NOT delete blindly: tcl_cflags is shared with all 84 extension"
echo "     modules, several of which still test the Tcl 8.6 macro names.)"
echo
comm -13 "$WORK/from-configure" "$WORK/from-configmk" | while read -r m; do
    case "$m" in
	CFG_*|TCL_LIBRARY|TCL_PACKAGE_PATH) continue ;;   # deliberate, ours
    esac
    if ! grep -rql --include='*.c' --include='*.h' "\\b$m\\b" \
	    "$TCLSRC/generic" "$TCLSRC/unix" "$TCLSRC/libtommath" 2>/dev/null
    then
	printf '    %s\n' "$m"
    fi
done

echo
echo "Done.  Neither list should be acted on without checking the notes at"
echo "the top of tcl-config.mk."
