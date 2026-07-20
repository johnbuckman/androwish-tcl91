#!/bin/bash
# Regenerate AndroWish's jni/tcl module for Tcl 9.1b0 (Android/ndk-build) and build libtcl.so (arm64).
# Produces a self-contained ndk-build project proving the Tcl 9.1 core cross-compiles + links for Android.
#
# Prereqs: NDK r27d, and the Tcl 9.1b0 source tree extracted at $TCLSRC.
# Usage: TCLSRC=~/androwish-tcl91-work/engine91/tcl9.1b0 OUT=~/androwish-tcl91-work/ndk-tcl91 ./gen-tcl91-android-module.sh
set -e
TCLSRC="${TCLSRC:-$HOME/androwish-tcl91-work/engine91/tcl9.1b0}"
OUT="${OUT:-$HOME/androwish-tcl91-work/ndk-tcl91}"
NDK="${NDK:-$HOME/Library/Android/sdk/ndk/27.3.13750724}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # repo root

rm -rf "$OUT"; mkdir -p "$OUT/jni/tcl"
for d in generic libtommath unix compat library utf8proc; do cp -R "$TCLSRC/$d" "$OUT/jni/tcl/"; done

# --- source list, extracted authoritatively from Tcl's own unix/Makefile.in OBJS vars ---
extract() { awk -v v="$1" 'BEGIN{p="^"v"[ \t]*="} $0 ~ p {f=1} f{print} f&&!/\\$/{exit}' \
    "$TCLSRC/unix/Makefile.in" | sed -E 's/^[A-Z_]+[ \t]*=//' | tr ' \t\\' '\n\n\n' \
    | grep -E '\.o$' | sed -E "s#^#\t$2/#; s#\.o\$#.c \\\\#"; }
{ echo "LOCAL_SRC_FILES := \\"
  extract GENERIC_OBJS generic; extract OO_OBJS generic
  extract TOMMATH_OBJS libtommath
  extract UNIX_OBJS unix; extract NOTIFY_OBJS unix
  printf '\tutf8proc/utf8proc.c \\\n\tunix/tclLoadDl.c\n'   # utf8proc (9.x encoding) + dlopen backend
} > "$OUT/jni/tcl/srclist.mk"

# --- config + module makefile (kept in the repo under patches/jni-tcl/) ---
cp "$HERE/patches/jni-tcl/tcl-config.mk" "$OUT/jni/tcl/tcl-config.mk"
cp "$HERE/patches/jni-tcl/Android.mk"    "$OUT/jni/tcl/Android.mk"

# --- build-generated headers the real Makefile would create ---
printf '#define TCL_VERSION_UUID androwish_tcl91_9_1b0\n' > "$OUT/jni/tcl/generic/tclUuid.h"

# --- ndk-build harness (just the tcl module) ---
printf 'include $(call all-subdir-makefiles)\n' > "$OUT/jni/Android.mk"
printf 'APP_ABI := arm64-v8a\nAPP_PLATFORM := android-21\nAPP_STL := none\n' > "$OUT/jni/Application.mk"

cd "$OUT"
"$NDK/ndk-build" NDK_PROJECT_PATH=. NDK_APPLICATION_MK=jni/Application.mk -j4
file "$OUT/libs/arm64-v8a/libtcl.so"
