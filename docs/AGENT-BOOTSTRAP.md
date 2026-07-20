# Agent bootstrap

Written by Claude, for Claude. If you are picking this project up cold, read this
file first and you should be able to rebuild the whole working state without
re-deriving anything.

This is deliberately not a tidy narrative. It records the traps, the wrong turns
and the exact commands, because those are what cost time.

---

## 1. Where everything is

| What | Path | Notes |
| --- | --- | --- |
| **Deliverable repo** | `~/androwish-tcl91` | PUBLIC — `johnbuckman/androwish-tcl91`. Docs + build config only. |
| **Build tree** | `~/androwish-tcl91-work/build-tree` | ~1.5 GB, full third-party source. Local git, **no remote — never push it**. |
| **8.6 reference tree** | `~/androwish-tcl91-work/build-tree/jni/sdl2tk/library-86bak` | AndroWish 8.6's Tk library. Source of the bundled fonts and `LICENSE.Symbola`. |
| **Release keystore** | `~/iwish/androwish-release.jks` | alias `androwish`. Passphrase lives in **macOS Keychain**, service `androwish-release-keystore`. **Never write it to a file.** |
| **NDK** | `~/Library/Android/sdk/ndk/27.3.13750724` | r27d. |
| **JDK** | `/Applications/Android Studio.app/Contents/jbr/Contents/Home` | JBR 21. |

The two repos are separate on purpose: the public one carries no third-party
source and no secrets.

### Emulators

| Serial | AVD | API | Density | Role |
| --- | --- | --- | --- | --- |
| `emulator-5560` | `awlatest_api31` | 31 | 420 dpi | phone; the "other density" check |
| `emulator-5580` | `aw_tablet_api34` | 34 | 320 dpi | tablet; the primary dev target |

`emulator-5560` also has the unrelated Magnatune app installed — do not be
confused by a screenshot of it. Other AVDs exist (`emulator -list-avds`).

---

## 2. Build

```sh
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.3.13750724
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
cd ~/androwish-tcl91-work/build-tree

# native only
"$ANDROID_NDK_HOME/ndk-build" NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=./jni/Android.mk \
    NDK_APPLICATION_MK=./jni/Application64.mk APP_ABI=arm64-v8a -j8

./gradlew assembleDebug      # no keystore needed — use this for diagnosis
./gradlew assembleRelease    # signed; needs ant.properties + keystore
```

A full native build takes a few minutes; `assembleDebug` re-runs ndk-build for
every module in `preBuild`, so budget ~5–8 min per cycle. **Run builds in the
background** — the foreground 2-minute tool timeout will kill them mid-link and
leave a half-built tree.

### The ndk-build staleness trap (bites every single time)

Changing a `-D` flag in `*-config.mk` does **not** invalidate the `.o` files.
ndk-build relinks from stale objects and the flag silently does nothing — or
worse, half the objects have it and you get undefined symbols.

```sh
rm -rf obj/local/arm64-v8a/objs/tcl     # after editing tcl-config.mk
rm -rf obj/local/arm64-v8a/objs/tk      # after editing tk-config.mk or sdl2tk/Android.mk
```

If you see undefined symbols that make no sense (e.g. `TclpGetWideClicks`),
this is why.

---

## 3. Test

### Native Tcl smoke test (config/ABI assertions)

`scripts/tcltest-main.c` — assertion harness, exits non-zero on failure. Build it
with `scripts/tcltest-Android.mk`, which **must** include `tcl-config.mk` so the
test TU is compiled with the same macros as the library. Compiling it by hand
without those flags gives a false `TCL_WIDE_INT_IS_LONG` failure.

Quick manual run:

```sh
TC=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin
T=~/androwish-tcl91-work/build-tree/jni/tcl
B=~/androwish-tcl91-work/build-tree
$TC/aarch64-linux-android21-clang scripts/tcltest-main.c \
  -I$T/generic -I$T/unix -DTCL_WIDE_INT_IS_LONG=1 -DTCL_WIDE_INT_TYPE="long long" \
  -L$B/libs/arm64-v8a -ltcl -llog -o /tmp/tcltest
adb -s SERIAL push /tmp/tcltest /data/local/tmp/
adb -s SERIAL push $B/libs/arm64-v8a/libtcl.so /data/local/tmp/
adb -s SERIAL shell "cd /data/local/tmp && LD_LIBRARY_PATH=. ./tcltest"
```

### On-device regression smoke test

```sh
scripts/emulator-smoke.sh -s emulator-5580     # 320dpi tablet
scripts/emulator-smoke.sh -s emulator-5560     # 420dpi phone
```

Runs `scripts/smoke.tcl` inside the installed APK via a `file://` VIEW intent,
reports through logcat (tag `AWSMOKE`), exits 0 on pass. Asserts all four of the
release-notes bugs plus console wiring. **Baseline: 15/15 pass on both
emulators with the released v0.1-alpha.**

Config-macro audit after any Tcl version bump:

```sh
scripts/tclcfg-audit.sh ~/androwish-tcl91-work/build-tree
```

---

## 4. Read this before believing a test failure

**The single most expensive mistake of this session.** I ran the smoke test on
`emulator-5560`, got a full set of font failures, and reported that bug 4 was
still live in the shipped release. It was not. The emulator had a **stale
pre-fix development build** on it from an earlier session, and I had assumed it
was the release without checking.

There were three different APKs in play across two emulators, **all reporting
`versionName 0.1-alpha`** (versionCode was never bumped). Version strings could
not distinguish them.

Cost: two full bisect build cycles (reverting `tkZipMain.c`, then the
`SdlTkUtils.c` `ckfree` change) plus an instrumentation cycle, all chasing a bug
that did not exist. What finally settled it was downloading the actual release
asset from GitHub and verifying its sha256 against the release notes.

`emulator-smoke.sh` now prints, on every run:

```
version:   0.1-alpha (code 1)
installed: 2026-07-20 10:42:23
apk md5:   2d95add853106d18efb249342c058a82
```

The md5 is of the installed `base.apk` and matches the md5 of the original APK
file, so it ties a result to a specific artifact. **If a smoke run fails, check
that md5 against the build you meant to test before doing anything else.**

Released v0.1-alpha:
- sha256 `86516131694ddd32ed9f2d43d0158d35b317a427916c65c5644e24e1eb19f959`
- md5 `2d95add853106d18efb249342c058a82`
- 32,145,360 bytes
- `gh release download v0.1-alpha --repo johnbuckman/androwish-tcl91 --pattern '*.apk'`

Consider bumping `versionCode`/`versionName` per build in future so this cannot
recur by inspection alone.

---

## 5. The four release-notes bugs — current truth

All four are **fixed and verified**, on both densities, against the released
APK. The release notes' account of them is accurate.

1. **Stack corruption in `wm title`** — `int*` where Tcl 9 wants `Tcl_Size*`.
   Fixed across `sdl/`. Three further live instances were found later in
   `generic/tkZipMain.c` (the intent-argv path, which runs at every launch) and
   fixed — see §6.
2. **`Tcl_GetIntFromObj` rejecting every non-negative int** — `TCL_WIDE_INT_IS_LONG`
   undefined on LP64. Fixed in `tcl-config.mk`; now asserted by `tcltest-main.c`.
3. **No usable font** — bundled DejaVu/Symbola faces missing. Fixed; now
   enforced by a gradle check (§6).
4. **Tiny text on high-DPI** — the emulated `XListFonts` answered generic
   families with a hardcoded XLFD carrying pixel size 12 (= fixed bitmap in
   X11). Fixed by emitting **pixel size 0 = scalable** in
   `SdlTkUtils.c:SdlTkListFonts`, plus a generic-family→DejaVu classifier in
   `MatchFont`.

**Bug 4 diagnostic tell:** if `font actual` ever reports family
`dejavu lgc sans mono` *in lowercase*, that string only exists in the
last-resort XLFD literal at `SdlTkUtils.c:~232`. The real registered family is
mixed-case `DejaVu LGC Sans Mono`. Lowercase ⇒ both match loops returned
nothing ⇒ you are on the last-resort path.

There is a second hardcoded 12 at `tkSDLFont.c:CreateClosestFont`:

```c
want.fa.size = -TkFontGetPixels(tkwin, faPtr->size);
if (want.fa.size == 0.0) { want.fa.size = 12.0; }
```

`TkFontGetPixels` divides by the screen's mm dimensions, so if those are ever 0
this pins the font to 12px with the same visible symptom. Not currently firing —
verified by instrumentation that `Helvetica -size 10` at 422 dpi resolves to
`DejaVu LGC Sans` at **59 px** — but it is the first place to look if tiny fonts
ever come back.

---

## 6. Changes made 2026-07-20 (the hardening pass)

Prompted by "give me a plan to solve the four bugs" → the four were already
fixed, so the work was hardening them against regression.

### Build tree (`~/androwish-tcl91-work/build-tree`, local commits only)

- **`jni/sdl2tk/generic/tkZipMain.c`** — 3 live instances of bug 1: `int objc`
  passed to `Tcl_ListObjGetElements`. On the intent-argv path, i.e. every
  launch. Also `sprintf("%d", objc)` → `TCL_SIZE_MODIFIER`.
- **`jni/sdl2tk/Android.mk`** — removed `-Wno-int-conversion`. It was hiding 3
  real errors. Kept `-Wno-incompatible-function-pointer-types`.
- **`jni/sdl2tk/sdl/SdlTkX.c`, `SdlTkInt.c`** — the casts that suppression hid:
  `ckfree((void *) dest->clip_mask)` (a `Pixmap` holding a heap pointer) and
  `SdlTkSetCursor((TkpCursor) 0)` ×2.
- **`jni/sdl2tk/sdl/SdlTkUtils.c`** — removed `ckfree(fstorage.file)`.
  `MatchFont` assigns `_f->file` from the atom table (`SdlTkUtils.c:433`), so it
  is never heap-owned; only `xlfd` is `ckalloc`ed (`:454`). The old guard made
  it dead in the common path, but it was wrong.
- **`jni/sdl2tk/sdl/tkSDLWm.c`, `tkSDLDialog.c`** — ~40 `int objc` → `Tcl_Size`
  (definitions *and* forward declarations — miss the declarations and you get
  "conflicting types" for every handler).
- **`jni/tcl/tcl-config.mk`** — 19 macros recovered by diffing against a real
  cross-configure. See §7.
- **`build.gradle`** — font + license check in `preBuild`. Verified by hiding
  `Symbola.ttf` and confirming the build fails with a useful message.
- **`jni/sdl2tk/library/LICENSE.Symbola`** — existed in `library-86bak` but was
  never carried into the 9.1 tree, so the **shipped alpha redistributes Symbola
  with no license file**. Restored.
- **`jni/sdl2tk/library/LICENSE.DejaVuLGC`** — new. Extracted verbatim from the
  font's own `name` table (ID 13) rather than written from memory.

After this pass the `tk` module builds with **0 errors and 0 pointer-type
warnings**. Remaining warnings are 9 benign `-Wmacro-redefined` in tk (MIN/MAX,
`XParseColor`, `NeedWidePrototypes`); the ~237 `-Wpointer-sign` and 5
`-Wdeprecated-non-prototype` are all in third-party modules (dropbear,
libressl), not ours.

### Deliverable repo (`~/androwish-tcl91`)

- `scripts/tcltest-main.c` — rewritten as an assertion harness.
- `scripts/tcltest-Android.mk` — now includes `tcl-config.mk`.
- `scripts/tclcfg-audit.sh` — new; re-runs the config diff.
- `scripts/smoke.tcl`, `scripts/emulator-smoke.sh` — new; on-device regression.
- `patches/gradle/build.gradle-fontcheck.groovy` — new.
- `patches/jni-tcl/tcl-config.mk`, `patches/jni-sdl2tk/Android.mk` — synced.

---

## 7. Config macros: how `tcl-config.mk` is derived

ndk-build never runs `configure`, so `tcl-config.mk` hand-asserts every macro
configure would have probed. **A missing macro does not fail the build — it
changes behaviour silently at runtime.** That is exactly how bug 2 happened.

Ground truth:

```sh
CC=$TC/aarch64-linux-android21-clang AR=$TC/llvm-ar RANLIB=$TC/llvm-ranlib \
tcl_cv_sys_version=Linux-4.4 \
  jni/tcl/unix/configure --host=aarch64-linux-android \
    --build=x86_64-apple-darwin --enable-64bit
# then read TCL_DEFS out of the generated tclConfig.sh
```

`tcl_cv_sys_version=Linux-4.4` is required — without it `SC_CONFIG_SYSTEM` runs
`uname` and you get Darwin results (`MAC_OSX_TCL`, `TCL_SHLIB_EXT=".dylib"`).

**Even with it, some darwin results still leak.** Do not adopt macros from
configure blindly — verify each against the NDK sysroot with a probe program.
`TCL_WIDE_CLICKS` is the cautionary tale: configure offers it, and
`tclUnixTime.c` `#error`s unless `MAC_OSX_TCL` is also defined. The build caught
it; a subtler one might not.

Deliberately **not** adopted, with reasons recorded in the file itself:
`MODULE_SCOPE`/`HAVE_HIDDEN` (hidden visibility would strip Tcl internals from
`libtcl9.1.so`; extensions resolve lazily at dlopen, so breakage would appear at
runtime not link time), `HAVE_MTSAFE_GETHOSTBYNAME`/`ADDR` (tcl.m4 infers these
from a glibc heuristic keyed on "Linux"; bionic is not glibc), and the macOS
leakage.

**Do not delete the dead-for-Tcl-9 macros** (`HAVE_ST_BLKSIZE`, `HAVE_STRSTR`,
`HAVE_MEMMOVE`, …). `tcl_cflags` is shared with all 84 extension modules and
several still test the old names.

`__CHAR_UNSIGNED__` was investigated and ruled out — clang predefines it on
arm64, so `TclGetInt1AtPtr` sign-extends correctly. Don't re-litigate.

---

## 8. Environment gotchas

- **`timeout` and `xargs` are broken/absent on this Mac.** Don't use them.
- **Foreground `sleep` is blocked** by the harness. Use `run_in_background` with
  an `until` loop.
- **Emulators die** if launched from a backgrounded bash. Use a detached helper
  + `disown`. Do not `pkill -9 qemu` mid-session — it takes down emulators you
  still need.
- **logcat buffer floods easily.** A per-face font dump (230 faces × several
  lookups) evicted the `AWSMOKE` lines entirely and looked like "the payload
  never ran". Keep instrumentation to counts, not dumps.
- **`log -t TAG "-something"`** silently drops the message — the leading `-` is
  parsed as an option. `smoke.tcl`'s `note` proc prefixes text to avoid this.
- **Emulator EGL emits a SIGABRT at process `exit()`** (`__cxa_finalize` →
  `eglDestroyContext` → destroyed mutex). It is in `libEGL_emulation.so`, not
  our code. Ignore it; results logged before exit are still valid.
- **`am start -n .../AndroWishLauncher`** does not reliably foreground the app,
  and `monkey -c LAUNCHER` exits -5. The `file://` VIEW intent used by
  `emulator-smoke.sh` is the reliable path.
- Driving the interactive console with `adb shell input text` did not work in
  practice (focus never landed on AndroWish). If you need the interactive path,
  expect to do it by hand.

---

## 9. Known-good facts worth not re-deriving

- The **script-launch path has no console-installed Demos menu**. `main.tcl`
  installs it only on the interactive path, so `::aw_demos` is undefined under a
  `file://` launch and the console File menu is
  `Source... / Hide Console / Clear Console / Exit`. `smoke.tcl` skips the check
  rather than failing it. This is correct behaviour, not a bug.
- Inside `console eval`, the console **is** `.` — the File menu is
  `.menubar.file`, not `.console.menubar.file`.
- The SDL window manager ignores geometry requests (`wm geometry .` returns
  `1x1+0+0` under a script launch), and `wm colormapwindows` returns empty.
  Assert marshalling, not effect.
- 230 font faces get registered on api 31 — the bundled DejaVu faces *plus* all
  of `/system/fonts` (see the glob in `SdlTkUtils.c` font init).
- `applicationId` is `tk.tcl.wish.tcl91`, so it coexists with stock AndroWish.

---

## 10. Open / next

Nothing is broken. Remaining items, none urgent:

1. **Physical-device testing.** Still emulator-only, though now at two densities
   and two API levels.
2. **Cosmetic:** default app icon; the main `.` window is an empty grey
   placeholder.
3. **Tcl/Tk 9.1 final** — currently 9.1b0. Rebuild + v0.2 when it lands. Run
   `scripts/tclcfg-audit.sh` as part of that.
4. **Other ABIs** — arm64-v8a only.
5. Consider per-build `versionCode` bumps (§4).
6. Upstream candidate, not yet reported: the pixel-size-12 XLFD bug exists in
   upstream AndroWish 8.6 too, masked there because 8.6 ships the fonts so the
   fallback never runs. John's decision was to skip reporting it, since this
   port will always ship with fonts.

## 11. Working agreements

- **Never commit until John reviews**, unless he explicitly says to commit.
- The keystore passphrase must never appear in the public repo. Secret-scan
  before every push.
- The build tree must never be pushed anywhere.
