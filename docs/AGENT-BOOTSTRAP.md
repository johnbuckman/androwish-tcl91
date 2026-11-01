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

### Package-load sweep

```sh
scripts/emulator-pkgsweep.sh emulator-5560 sweep.txt
```

`package require`s every package the app can find (`scripts/pkgsweep.tcl`,
logcat tag `AWPKG`). A package that takes the app down is added to a skip list
and the sweep reruns, so one run gives the full picture. Diff the
`FAILPKG` lines between builds. A crash in the sweep can depend on load order:
before chasing one, `package require` it alone in a fresh app. If it loads
alone, bisect the packages loaded before it (1.0b1: awarc crashed only after
MaterialIcons, which loaded tksvg; shtmlview only after img::xpm + imgjp2).

### Tcl's and Tk's own test suites, in the app

```sh
scripts/emulator-suite.sh emulator-5580 tcl ~/androwish-tcl91-work/engine91/tcl9.1.0/tests OUTDIR
scripts/emulator-suite.sh emulator-5580 tk  ~/androwish-tcl91-work/engine91/tk9.1.0/tests  OUTDIR
```

Pushes the tests and `scripts/suite.tcl`, runs them single-process with
`-verbose bps`, and restarts after a crash or hang, skipping the file that
caused it. `OUTDIR/summary.txt` counts distinct test names (tcltest prints each
failure twice). About an hour for Tcl, 20 minutes for Tk. Run it on one
emulator at a time and don't reinstall the APK on it while it runs.

### Demos

Each Demos-menu entry is launched in its own app start and screenshotted;
check `WINDOWS` in the log and look at the pictures. An entry that only adds to
`.` (vu) shows no extra window.

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

Released v1.0b0 (Tcl/Tk 9.1.0, versionCode 2):
- sha256 `722e00a9566a9b4353e63a3e35a4738fe269af8180ae98d5820a8f96b27d8aeb`
- md5 `c6fc624c46ef90b624df551c8efcb77a`
- 32,155,127 bytes
- signed with the same certificate as v0.1-alpha, so it installs over it

Released v1.0b1 (Tcl/Tk 9.1.0, versionCode 3):
- sha256 `bebac259b73c0ab05b3aa374490b9e8cf6638f74b642b282739faf7c9839a6f6`
- md5 `4353618a6ed89a1e4274d4fa118ada8f`
- 32,452,095 bytes, 84 native libraries
- same certificate again

Released v1.0b2 (BLT and Expect fixed, versionCode 4):
- sha256 `e0e91ad91186f415223f7998b23187a9ed006115da3ba7cf419b1b835f8ad80f`
- md5 `1b0d28e6c415aaa94f718e585ec871fd`
- 32,451,745 bytes, 84 native libraries
- same certificate again; installs over 1.0b1 as an update

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
3. ~~Tcl/Tk 9.1 final~~ — done: 1.0b0 is on 9.1.0 (§12).
4. **Other ABIs** — arm64-v8a only.
7. **Packages that don't load on Tcl 9** — see §13 and §14. None crashes the
   app any more (Expect was the last). Load failures
   left: nsf/nx/XOTcl, Itcl/Itk, Thread, Tclx, Ffidl, Tix, and what needs them.
8. **`int*`→`Tcl_Size*` in the rest of the extensions** — over a thousand
   call sites (snack, tktreectrl, Tix, Tclx, …; BLT is done, §14). Each one can abort the app
   with `stack corruption detected`. `scripts/fix_tclsize.py` does most of a
   module from clang's output (§13).
9. **Tktable** — disabled; 2.11 uses the string `Tk_ConfigureWidget`. Port 2.12.
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

---

## 12. Moving to Tcl/Tk 9.1.0 (2026-11-01, release 1.0b0)

The port tracked 9.1b0. Going to the 9.1.0 release did not need a re-graft:
the build tree already carries every Android/SDL change, so the stock
9.1b0→9.1.0 delta was applied on top of it.

```sh
E=~/androwish-tcl91-work/engine91          # tcl9.1b0 tk9.1b0 tcl9.1.0 tk9.1.0 side by side
gh release download core-9-1-0 --repo tcltk/tcl --pattern tcl910-src.zip
gh release download core-9-1-0 --repo tcltk/tk  --pattern tk910-src.zip
diff -ruN tcl9.1b0 tcl9.1.0 -x tests -x doc -x win -x macosx -x .github -x pkgs -x tools  > tcl.diff
diff -ruN tk9.1b0  tk9.1.0  -x tests -x doc -x win -x macosx -x .github                  > tk.diff
# rewrite the headers to a/ b/, then:
cd build-tree/jni/tcl    && patch -p1 --batch < tcl.diff        # only README/changes.md reject
cd build-tree/jni/sdl2tk && patch -p1 --batch < tk-generic-library-only.diff
```

- **Tk's `unix/` hunks were left out**: sdl2tk doesn't compile `unix/`, it
  has `sdl/`. Read them anyway, since several `sdl/` files are copies of
  `unix/` ones. Two applied (`long long` return type, the NULL-family font
  guard); the rest are `int`→`bool` tidying and X11 `_NET_WM_STATE` code.
- **`tcl/pkgs` was left alone** (Thread 2.8.5, Itcl 4.2.0, sqlite 3.53.3,
  TDBC 1.1.1 are AndroWish's own copies, not the 9.1 tarball's).
- New source: `generic/tclGrapheme.c` → added to `jni/tcl/srclist.mk`.
  `tkUnicodeKeysyms.h` is new but unused on this platform.
- `tcl-config.mk`: `tclcfg-audit.sh` found nothing new (configure.ac only
  changed the patch level).

Two Tk 9.1.0 interface changes broke the sdl backend
(`patches/jni-sdl2tk/sdl/tk-9.1.0-backend.diff`):

1. `Tk_GetUserInactiveTime` now returns `long long` (compile error,
   `conflicting types`, in `sdl/tkSDL.c`).
2. `generic/tkPointer.c` now calls `TkpGetEventTime()` instead of
   `TkpGetMS()` (link error, undefined symbol). Stock X11 never compiles
   `tkPointer.c`; Windows and macOS each define it. sdl's returns
   `TkpGetMS()`, the clock it used before.

Do a clean native build after a version bump (`rm -rf obj/local/arm64-v8a`):
`tcl.h` changed, and every extension includes it.

Warnings new with 9.1.0: `XIDProc` is typedef'd by both Tk's headers and
`xlib/X11/Xlib.h` (same type; `-Wtypedef-redefinition`, legal C11), seen in
blt, tkzinc, snack, tkpsvg and tk. Harmless.

### Verification for 1.0b0

| Check | Result |
| --- | --- |
| `emulator-smoke.sh` | 15/15 on emulator-5580 (API 34, 320 dpi) and emulator-5560 (API 31, 420 dpi) |
| `tcltest-main.c` | 0 failures |
| `tclcfg-audit.sh` | no new macros |
| `info patchlevel` / `$tk_patchLevel` on device | 9.1.0 / 9.1.0 |
| Native libraries in the APK | the same 84 as v0.1-alpha |
| `emulator-pkgsweep.sh` | 113 load, 192 fail, 7 crash the app: **identical to v0.1-alpha** |

The package sweep is new with 1.0b0, so the beta was never checked this way.
Its baseline (both builds):
- 86 fail on version: the package index asks for `Tcl 8.5`/`8.6`/`8.1`
  (41 / 14 / 16) or `Tk 8.x`. `package require Tcl 8.5` means 8.5 ≤ v < 9.
- ~50 fail with `cannot find symbol "<name>_Init"`: nsf/nx (32), tdom (12),
  vlerq, topcua, vectcl, tdbc.
- 7 crash the app: Expect (`channel type exp must be version
  TCL_CHANNEL_VERSION_5`), awdark, awlight, fsdialog, ttk::icons,
  ttk::theme::awdark, ttk::theme::awlight.
- Downgrading to compare builds: `adb install -r -d <old.apk>` works on the
  emulators (same signing key).

---

## 13. Release 1.0b1 (2026-11-01): demos, packages, test suites

John asked whether each demo had been run on 9.1 and whether Tcl's and Tk's
regression tests had been run. Neither had. **Correction:** 1.0b0 and the
0.1-alpha said the Demos menu "launches real demos". Run one at a time, only
the widget demo worked; the rest errored or crashed. All eight work in 1.0b1.

All build-tree changes are in `patches/build-tree/1.0b1.diff` (build tree
commit 5ac39bcc, local only).

### What was wrong, and the fixes

1. **Tk 9 option defaults must be NULL, not `"-1"`.** `sdl/tkSDLDefault.h`
   still had `"-1"` for the message widget's `-padx`/`-pady` and the scrollbar
   element border width. 49 Tk message-widget test failures.
2. **Version requirements excluded 9.** `"8.5"` means 8.5 ≤ v < 9. Relaxed
   to `"8.5-"`: 160 `Tcl_InitStubs`/`Tk_InitStubs`/`Tcl_PkgRequire` calls in 82
   C files, 93 `package require`/`vsatisfies` in 75 scripts, plus the
   `TKPATH_REQUIRE` and Tix `MIN_TK_VERSION` macros. Keep each file's line
   endings: rewrite in binary mode, or the diff becomes every line.
   Not relaxed: Tktable (it crashes), and the packages that then crashed
   (Itcl/Itk/Thread indexes, nsf, Tclx, Ffidl): they stay failing, not crashing.
3. **tcllib and tklib were invisible.** Their top-level `pkgIndex.tcl` starts
   with `if {![package vsatisfies [package provide Tcl] 8]} {return}`, so on
   Tcl 9 they never added themselves to `auto_path`. Relaxed to `8-`. This
   alone took the sweep from 196 to 734 loading packages.
4. **`load` uses the prefix literally in Tcl 9.** `load libtdom.so tdom`
   looks for `tdom_Init`; the library exports `Tdom_Init`. Capitalized in 19
   indexes (tdom, tdbc, tcllibc, treectrl, rl_json, vlerq, …).
5. **`int*` where Tcl 9 wants `Tcl_Size*`** (the alpha's `wm title` bug,
   again, in extensions). Found with
   `ndk-build APP_MODULES="<mod>" APP_CFLAGS="-Werror=incompatible-pointer-types -ferror-limit=0"`;
   `scripts/fix_tclsize.py <file:line:col list>` retypes the local variable,
   and prints what it can't do for hand fixing. Fixed in:
   - tkpath, tkzinc, zint, vu (the demos);
   - **tdom**: `generic/dom.h` hardcoded `#define domLength int`; now
     `Tcl_Size` on Tcl 9, as upstream does. 66 errors became 3;
   - **tkimg**: its own `int*` API is kept (other modules call it through
     stubs) with `Tcl_Size` temporaries inside; pixmap passed strings to Tk 9's
     object-only `Tk_ConfigureWidget`;
   - **imgjp2**: its format probe ran on every `image create photo -data`, so
     with imgjp2 loaded any `-data` image could abort the app;
   - tkpsvg, trofs, tclJBlend (`JavaGetString` wrote an `int` into
     `Tcl_Obj.length`).
6. **tksvg 0.14 replaced Tk 9's built-in svg format and then crashed.** Tk 9
   has svg built in with the same options, so on Tk 9 `package require tksvg`
   now just provides the package.
7. **Demos menu** (`assets/main.tcl`): goldberg sources the widget demo first;
   tkpath runs `demos/tiger.tcl` (the demos were copied into the assets); vu
   runs `demos/vu.tcl`; zint draws a QR code; ixset, tksqlite and Tktable
   removed.

### Test-runner bug worth knowing

`emulator-suite.sh` stopped the Tcl run at file 148 of 177. tcltest.test runs a
nested `all-single.tcl` that prints its own `Sourced 2 Test Files.`, which the
runner took as the end. It now waits for the real summary, `^:<tab>Total`, and
treats a "done" whose pulled output lacks it as a crash. The 1.0b0 and alpha
baselines ran all their files.

### Results

| Check | 1.0b0 | 1.0b1 |
| --- | --- | --- |
| Package sweep: load / fail / crash the app | 113 / 192 / 7 | **754 / 128 / 1** (Expect) |
| Tcl 9.1.0 suite: passed / failed | 54,102 / 438 | 54,102 / 438 (identical) |
| Tk 9.1.0 suite: passed / failed | 7,132 / 247 | **7,704 / 199** |
| Tk files that hang | event, textDisp, textIndex | event |
| Demos that work | 1 of 8 | **8 of 8**, both emulators |
| `emulator-smoke.sh` | 15/15 | 15/15, both emulators |

No package that loaded on 1.0b0 fails on 1.0b1. Tk: 63 tests fixed, none
regressed. The 0.1-alpha on its own 9.1b0 tests: Tcl 53,522 / 602 (binary.test
crashed), Tk 6,961 / 160.

Most remaining test failures are the device, not the port: no `tclsh` to
`exec`, no network for http, shared storage for fCmd, `info frame` depth, and
standard channels that are `none`.

---

## 14. BLT and Expect on Tcl 9 (release 1.0b2)

1.0b1's BLT loaded and drew an empty graph, but adding an element, closing a
graph, or `blt::table` crashed the app. Three separate bugs, plus one in the
port's own label cache. All in `patches/build-tree/blt-tcl9.diff`.

1. **Tcl 9 dropped `_ANSI_ARGS_`, and `blt.h` falls back to `()`.** Every BLT
   prototype became an unprototyped declaration, so calls lost argument
   conversion: `Blt_InitHashTable(&t, BLT_ONE_WORD_KEYS)` passed the `int` -1
   to a `size_t` parameter, the table got a garbage key type, and the first
   lookup in `blt::table` crashed. The fallback is now `x`. Restoring the
   prototypes exposed no new type errors. (Expect's headers have a `()`
   fallback too, but only for compilers without `__STDC__`, so clang keeps
   Expect's prototypes.)
2. **`Blt_ConfigureWidget` passed strings to Tk 9's object-only
   `Tk_ConfigureWidget`.** All of BLT's widgets and components configure
   through it, which is why an empty graph worked and an element with
   `-xdata` crashed. It now wraps the strings in `Tcl_Obj`s (same bug as
   tkimg's pixmap, §13).
3. **26 `int*`→`Tcl_Size*` sites**, from the strict build and
   `fix_tclsize.py`. One needed a hand fix: in `bltSwitch.c` the retyped
   `count` was also passed to `Tcl_GetInt`, so `Tcl_SplitList` got its own
   `Tcl_Size`.
4. **The port's `-cachelabels` sprite blit** (from BLT-faster) crashed the
   graph2 demo. Before the first layout a tick label's anchor can be about
   `INT_MAX`; `XCopyArea` to that point overflows SDL's blit clipping. Labels
   outside the 16-bit X coordinate range now go to `Blt_DrawText`, which
   clips. `option add *cacheLabels 0` was the diagnosis: graph2 ran without
   the cache.

The remaining strict-build errors in BLT are `const` qualifiers and two
`bltImage.c` array-pointer types that pass the same address. Harmless.

### Results (debug build, emulator-5560; the 1.0b2 release build was retested on both emulators)

- Every demo in `assets/blt2.4/demos` runs: graph1–7, barchart1/3/4/5,
  spline, stripchart1.
- Graph, barchart and stripchart with data and vectors, closed and recreated;
  `blt::table` with children; `blt::bitmap`: no crash.
- `emulator-smoke.sh`: passed.

### Expect

Expect was the last package that took the app down in the sweep.
`patches/build-tree/expect-tcl9.diff`.

1. **Its channel type had the Tcl 7 layout.** `exp_chan.c` picks the
   version-2 layout `#ifdef TCL_CHANNEL_VERSION_2`; Tcl 9 doesn't define it,
   so Expect got the older layout, with `ExpBlockModeProc` in the version slot,
   and `Tcl_CreateChannel` panicked. There is now a Tcl 9 branch: version 5,
   `closeProc` NULL, and an `ExpClose2Proc` that returns `EINVAL` for a
   half-close and otherwise calls `ExpCloseProc`.
2. **16 `int*`→`Tcl_Size*` sites.** `fix_tclsize.py` did 14. The others: the
   `Exp_*ObjCmd` functions that rebuild `objv` take `int objc_in` and work on a
   `Tcl_Size objc` copy; `Dbg.c` passed `(int *)0` as `TclFindElement`'s size;
   `send` passes an `int` temporary to Expect's own `exp_cook(char *, int *)`.

On the device, `spawn /system/bin/sh`, `expect`, `exp_send`, `close`/`wait`
and `exp_open` all work. With Tk loaded, use `exp_send`: Tk owns `send`.

### Results (debug build, emulator-5560; the 1.0b2 release build was retested on both emulators)

- Package sweep: **755 load, 128 fail, 0 crash the app** (1.0b1: 754 / 128 /
  1). The failure list is identical to 1.0b1's; Expect moved from crashing to
  loading.
- `emulator-smoke.sh`: passed. All 13 BLT demos still run.

### 1.0b2 release build

`versionCode 4`, `versionName "1.0b2"` in `build.gradle` (not in the patch
files; nothing else in it changed). On both emulators (API 31 420 dpi, API 34
320 dpi; on 5580 installed as an update over 1.0b1): smoke 15/15, the BLT
checks 13/13, the Expect checks 6/6, BLT demos graph1, graph2, barchart1 and
stripchart1 run. The demos, the package sweep and the test suites were not
rerun on the release build: its native libraries are byte-identical to the
debug build's that ran them (libblt and libexpect are the ones that changed
since 1.0b1).

