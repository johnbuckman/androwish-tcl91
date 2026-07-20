# androwish-tcl91 — porting AndroWish to Tcl/Tk 9.1

**Goal:** Build AndroWish (Tcl/Tk on Android, SDL/AGG X11-emulation backend) on **Tcl/Tk 9.1b0**
(2026-06-30 beta), heading toward the 9.1 release. Ship a signed, installable **0.1 alpha APK**
with the full AndroWish "batteries included" extension set. New public repo `androwish-tcl91`,
Tcl/Tk license.

## Findings (2026-07-18 reconnaissance)

- **There is NO Tcl 9 AndroWish upstream.** Both live branches at androwish.org (`trunk`,
  `wtf-8-experiment`, both current) still bundle **Tcl/Tk 8.6.10**. `wtf-8-experiment` backports
  Tcl 9's WTF-8 encoding *into* 8.6 — it is not a 9.x engine. So this is a genuine from-scratch port.
- **Base chosen:** upstream Fossil **trunk** (checkout `307efba620` @ 2026-07-18), cloned to
  `~/androwish-tcl91-work/androwish.fossil`, opened at `~/androwish-tcl91-work/trunk`.
  John's own perf patches (BLT-faster, sdl2tk dirty-rect) get re-layered afterward.
- **Target engine:** `~/androwish-tcl91-work/engine91/{tcl9.1b0,tk9.1b0}` (official src tarballs,
  Tcl 9.1b0 == internally 9.1b0rc2, Tk 9.1b0). Stock 8.6.10 also extracted there for delta work.

## Architecture of AndroWish's Tk (`jni/sdl2tk`) — why this is tractable

AndroWish replaces Tk's X11/unix backend with an **SDL2 + AGG** renderer that **emulates Xlib**.
Christian Werner guards every SDL-specific change to generic Tk with `#ifdef PLATFORM_SDL`. Measured:

- **Generic Tk hooks:** only **~177 `PLATFORM_SDL` markers across 37 files** (~88 guarded regions).
  Biggest: tkWindow.c(20), tkImgPhInstance.c(15), tkFont.c(15), tkCmds.c(11), tkStubInit.c(10),
  tkPointer.c(10), tkEvent.c(8), tkZipMain.c(7). → surgical re-insertion onto stock Tk 9.1 generic.
- **SDL backend `sdl/`:** ~49k lines (SdlTk*, tkSDL*, AGG C++ renderer, PolyReg/Region). Self-contained
  platform impl — the big port to Tk 9.1 internals (Tcl_Size, changed structs, display/font paths).
- **Xlib emulation `xlib/`:** ~1.8k lines (xdraw/xgc/ximage/xcolors/xutil). Small.
- NOTE: the naive `diff sdl2tk/generic vs stock-tk-8.6.10` is huge (tkBind.c ~5k lines) but MISLEADING —
  sdl2tk's generic files are forked from *older* 8.6.x (pre-2018 Cramer tkBind rewrite). Don't 3-way
  merge those; instead take **stock Tk 9.1 generic** and re-insert the PLATFORM_SDL regions.

## Build system

- Android build = **ndk-build**, 94 per-module `Android.mk` files each listing sources explicitly.
  `jni/Android.mk` = `include $(call all-subdir-makefiles)`. Each module has `<mod>-config.mk`.
  → the Tcl and sdl2tk source lists must be regenerated for the 9.1 trees.
- Toolchain (from prior AndroWish work, [[androwish_android_de1app]]): NDK r27d
  (`~/Library/Android/sdk/ndk/27.3.13750724`), JDK = Android Studio JBR 21, arm64-only
  (`Application64.mk APP_ABI := arm64-v8a`). Release keystore `~/iwish/androwish-release.jks`
  (alias `androwish`; the passphrase is held in the macOS Keychain under service
  `androwish-release-keystore` — it is deliberately not recorded here).
- Desktop cross-check: `undroid/build-undroidwish-*.sh` builds the SAME sdl2tk for
  linux/macosx/etc. → **port + debug sdl2tk on desktop first** (fast iterate), then Android-package.

## Phased roadmap

- **Phase 0 — scaffolding + baseline** *(in progress)*: repo skeleton (this repo), LICENSE, PORT.md.
  Optionally build the upstream trunk 8.6.10 arm64 APK as a toolchain baseline/fallback.
- **Phase 1 — Tcl 9.1 core on Android**: drop `tcl9.1b0` into `jni/tcl`, regen `jni/tcl/Android.mk`
  source list (libtommath 65→154 files + reorg, generic 103→111, zipfs), fix `tcl-config.mk`. Verify
  `libtcl9.1.so` builds + a minimal tclsh runs (adb).
  - **PROOF DONE (2026-07-18):** Tcl 9.1b0 core cross-compiles for arm64 Android with NDK r27d —
    **95 objects compiled clean**. Two mechanical cross-compile gotchas found (proof script
    `~/androwish-tcl91-work/build-tcl91-android.sh`, build dir `build-tcl91-arm64/`):
    1. Tcl `configure` derives target OS from `uname` on the BUILD host → misdetects macOS
       (`MAC_OSX_TCL`, `sys/attr.h`, `.dylib`). FIX: pass `tcl_cv_sys_version=Linux` → routes to the
       Linux branch (`.so`, `HAVE_CLOCK_GETTIME`). Also `--build=x86_64-apple-darwin --host=aarch64-linux-android`.
    2. Even with system=Linux, cross-configuring ON a Mac host still leaks Darwin defines into AC_FLAGS
       (`-DTCL_WIDE_CLICKS -D_DARWIN_C_SOURCE -DHAVE_WEAK_IMPORT -DTCL_LOAD_FROM_MEMORY`) →
       `tclUnixTime.c:113 #error Wide clicks not implemented` + link errors for TclpLoadMemory/GetWideClicks.
  - **DO NOT** chase these via the stock `configure` on macOS — they are a Mac-host artifact. The REAL
    Phase-1 path is **AndroWish's ndk-build `jni/tcl/tcl-config.mk`** (already Android-correct).
  - **✅ PHASE 1 CORE DONE (2026-07-19): `libtcl.so` (Tcl 9.1b0, arm64-v8a, 2.4MB) BUILDS + LINKS via
    ndk-build.** Reproducible from a clean slate: `scripts/gen-tcl91-android-module.sh` (regenerates the
    module from the 9.1 tarball → runs ndk-build → ELF aarch64 lib exporting Tcl_CreateInterp/Tcl_MainEx/
    TclZipfs_*). Working project at `~/androwish-tcl91-work/ndk-tcl91/`. Config kept in
    `patches/jni-tcl/{tcl-config.mk,Android.mk}`. The **7 concrete fixes** vs the 8.6 module:
    1. Source list regenerated authoritatively from Tcl 9.1 `unix/Makefile.in` OBJS vars (176 files:
       GENERIC+OO+TOMMATH+UNIX+NOTIFY+utf8proc+tclLoadDl). libtommath uses the Makefile's TOMMATH_OBJS
       subset, NOT all 154 files.
    2. Added **utf8proc** (`utf8proc/utf8proc.c` + `-DUTF8PROC_STATIC`) — new 9.x encoding dependency
       (`tclEncoding.c` includes `../utf8proc/utf8proc.h`).
    3. Stub **`generic/tclUuid.h`** = `#define TCL_VERSION_UUID ...` (normally build-generated from
       manifest.uuid; `tclEvent.c` needs it).
    4. Added **`CFG_RUNTIME_*` / `CFG_INSTALL_*` / `CFG_RUNTIME_DLLFILE` / `*_DEMODIR`** path defines
       (Makefile normally injects them) → point at `/assets`, dll = `libtcl9.1.so`.
    5. Added zlib **internal** header dirs to includes (`compat/zlib`, `compat/zlib/contrib/minizip`) —
       `tclZipfs.c` includes zlib-internal `crypt.h`/`zutil.h`/`crc32.h` even though we link system `-lz`.
    6. Added `unix/tclLoadDl.c` (the `@DL_OBJS@` dlopen backend) → resolves `TclpDlopen`.
    7. Dropped 8.6-isms: `-DTCL_UTF_MAX=6` removed (9.x fixed rep), `TCL_LIBRARY`→`/assets/tcl9.1`,
       `PACKAGE_VERSION`→9.1, kept system `-lz` + `-llog` + epoll/select/kqueue notifiers (guarded).
  - **✅ RUNTIME PROVEN (2026-07-19): Tcl 9.1b0 interp runs LIVE on Android arm64** (emulator
    awlatest_api34, arm64-v8a). Native test `scripts/tcltest-main.c` links `libtcl.so`, creates an interp
    (no script library needed), and verified: `tcl_patchLevel=9.1b0`, `expr 6*7=42` (bytecode),
    `string toupper` OK, `2**64=18446744073709551616` (**libtommath bignum works**). So the core engine
    genuinely executes, not just links. (Full `Tcl_Init`/`puts`/channels still need the tcl script library
    staged in /assets — that's part of app packaging, Phase 6.)
  - **Emulator note:** port-5560 `awlatest_api37` wedged **offline** (adb can't handshake; couldn't be
    process-killed — classifier blocks `kill`). Worked around by booting a fresh `awlatest_api34` on port
    5556. John may want to `adb -s emulator-5560 emu kill` / kill the stray qemu pid 75130 manually.
  - **NOT yet done in Phase 1:** fold this module into the actual AndroWish `jni/tcl` in the port tree
    (this was a standalone module harness to iterate fast).
- **Phase 2 — Tk 9.1 generic**: stock `tk9.1b0/generic` + re-insert the ~88 PLATFORM_SDL regions
  (extract them as a patch from current sdl2tk generic). Wire `jni/sdl2tk/generic`.
- **Phase 3 — sdl/ + xlib backend to Tk 9.1**: port the SDL/AGG/Xlib backend (Tcl_Size, Tk 9.1
  internal structs/decls, stubs). **Debug on desktop (undroidwish) first.** This is the long pole.
- **Phase 4 — extensions**: rebuild the ~60 batteries against Tcl 9.1 stubs; many need Tcl_Size /
  removed-API fixes. Triage which are load-bearing for "full batteries".
- **Phase 5 — Android JNI glue**: borg/ble/usbserial/SDL_android against Tcl 9.1 (Tcl_Size).
- **Phase 6 — APK**: arm64 assembleRelease, sign, install+boot verify on tablet → **0.1 alpha**.
- **Phase 7 — release**: create public GitHub repo `androwish-tcl91` (Tcl/Tk license), publish
  0.1-alpha APK + SHA256. (Repo creation + push await John's review — [[no_commit_until_review]].)

## Risks / open questions

- **Biggest risk = Phase 3** (sdl/ backend vs Tk 9.1 internals). Tk 9 changed Tcl_Size across the
  API, text/display internals, font handling. If a wall is hit, report before deep investment.
- Tcl 9.1 zipfs/init: AndroWish self-mounts its APK via zipfs at C startup (see 128MB cap gotcha in
  [[androwish_android_de1app]]) — verify 9.1 zipfs behaves.
- "Eventually build with release version" — track 9.1 final (Sept 2026 target); keep engine swap
  scripted so a version bump is a re-drop.

## Work tree layout
- `~/androwish-tcl91-work/trunk/` — upstream trunk checkout (base to port).
- `~/androwish-tcl91-work/engine91/` — tcl9.1b0, tk9.1b0, tcl8.6.10, tk8.6.10 sources.
- `~/androwish-tcl91/` — the deliverable repo (patches, scripts, docs) — LOCAL, not pushed yet.

## undroidwish feature port (2026-07-19) — items 1-6
5 (sdl2tk dirty-rect per-rect upload) + 6 (BLT-faster -cachelabels/-bufferchrome): DONE, compiled into
libtk/libblt (5 hand-ported into SdlTkGfx.c as SdlTkUploadBox + per-rect loop; 6 = ~/BLT-faster patch).
1-4 (Demos menu, borgdemo, bledemo, side-by-side window placement): CODED + staged —
  * assets/main.tcl (Demos menu install into console File menu + auto_path + placement, adapted from
    undroidwish, //zipfs:/assets root, native borg/ble via `info commands`),
  * assets/androwish-demos/{borgdemo,bledemo}.tcl (adapted for Android native borg/ble),
  * tkZipMain.c boot hook: sources `//zipfs:/assets/main.tcl` after Tcl_SourceRCFile on bare launch.
BLOCKED at runtime by a PRE-EXISTING **console-interp Tk_Init "bad level #0"** error on Tcl 9.1:
tkConsole.c:351 `Tk_Init(consoleInterp)` -> tk.tcl (suspect: ScreenChanged `uplevel #0 [list upvar #0
::tk::Priv.$disp ::tk::Priv]` at tk.tcl:289). The MAIN interp Tk_Init works (root window renders); the
CONSOLE (separate Tcl_CreateInterp) fails, so the console never comes up and the Demos menu can't install.
NOT caused by main.tcl (persists with the boot hook's own uplevel removed). FIX = the next step; it also
fixes the AndroWish console itself on 9.1 (why the earlier build showed only a bare root window, no console).

## Runtime bring-up (2026-07-19) — RESOLVED: boots to interactive console + Demos menu

The "bad level #0" block above is **FIXED**, along with all remaining boot-time crashes. The signed
**0.1-alpha APK now boots on Android arm64 to a working interactive Tcl console + a Demos menu whose
entries launch real demos** (Tk widget demo, borg, BLE, goldberg, tkzinc, tkpath, zint, vu, tktable, …).
APK: `AndroWish-tcl91-0.1-alpha-arm64.apk` (~28.5MB, 84 native libs = full batteries,
pkg `tk.tcl.wish.tcl91`, John's release cert).

### Root cause of "bad level #0" — `TCL_WIDE_INT_IS_LONG` undefined on arm64 (the big one)
Not the `uplevel`/`upvar` in tk.tcl at all. `Tcl_GetIntFromObj` was failing for **every non-negative
int** on this arm64 (LP64) build, so `upvar #0` → `bad level "#0"` in `tcl_findLibrary`→`tkInit`. ROOT:
`TCL_WIDE_INT_IS_LONG` was undefined (arm64 `long` == 64-bit), so `Tcl_GetLongFromObj` took the 32-bit-long
`#else` branch where `(Tcl_WideInt)(ULONG_MAX)` overflows to −1 → the range check `w <= −1` fails for
w ≥ 0 → tooLarge → TCL_ERROR. (Arithmetic still worked — bytecode literals are pre-parsed at compile time;
only *runtime* string→int conversion broke.) `tcl.h` never auto-defines the macro because `__GNUC__` +
a predefined `TCL_WIDE_INT_TYPE` skip the `LONG_MAX==LLONG_MAX` guard; AndroWish's hand-written config
set it only for 32-bit armeabi.
**FIX:** add `-DTCL_WIDE_INT_IS_LONG=1` to `patches/jni-tcl/tcl-config.mk`.
**GOTCHA:** changing a `*-config.mk` CFLAG does NOT invalidate ndk-build `.o` files — must
`rm -rf obj/local/arm64-v8a/objs/tcl` to force a recompile, else libtcl relinks from stale objects and the
fix silently doesn't apply.

### Other boot/runtime fixes (all in jni/sdl2tk — the AndroWish zipfs/font bootstrap vs Tcl 9)
1. **Tcl 9 zipfs path (TIP-430):** mounts now live under `//zipfs:/` → `#define ZIPFS_BOOTDIR
   "//zipfs:/assets"` for `>=9` (was `/assets`); `TCL_LIBRARY`/`TK_LIBRARY` → `//zipfs:/assets/{tcl9.1,
   sdl2tk9.1}` in the config.mk files.
2. **Tk_MainEx → Tk_ZipMain redirect:** add `tkZipMain.c` to the srclist + `#define Tk_MainEx Tk_ZipMain`
   in tkDecls.h (PLATFORM_SDL) + `#undef Tk_MainEx` before tkMain.c's own def. In tkZipMain.c: guard
   `#include "zipfs.h"` (<9), `#define Tclzipfs_Mount TclZipfs_Mount` (9 renamed, same args),
   `Tclzipfs_Init`→TCL_OK (9 auto-inits).
3. **Pointer-truncation SIGSEGV:** `-Wno-implicit-function-declaration` masked missing prototypes for
   `TkGetDisplayListExt`/`TkNewWindowObj`/`TkpGetOtherWindow`/`TkpContainerId`/`TkpGetCapture` (all
   return **pointers**) → int-truncated on 64-bit. REMOVED the flag; added the 11 MODULE_SCOPE protos to
   generic/tkInt.h under PLATFORM_SDL. **Lesson: never `-Wno-implicit` on 64-bit — it hides pointer
   truncation.**
4. **Font-init SIGSEGV (NULL createProc):** `SdlTkFontLoadXLFD` hit an uninitialised `xlfdHash` (Tcl 9's
   `Tcl_FindHashEntry` dispatches through `createProc`) because `SdlTkFontInit` (needs interp, Tcl-globs
   the fonts) hadn't run before the first window-decoration draw → call `SdlTkFontInit(mainPtr->interp)`
   in `TkpFontPkgInit` (tkSDLFont.c).
5. **`-fstack-protector` SIGABRT in `wm title` (stack corruption):** the sdl2tk 8.6-era X11-emu layer
   passed `int*` where Tcl 9 wants `Tcl_Size*` (8-byte) out-params. Fixed all such sites in
   sdl/{tkSDLWm,tkSDLCursor,tkSDLSend,SdlTkUtils}.c: `Tcl_GetStringFromObj`/`Tcl_ListObjGetElements`/
   `Tcl_GetByteArrayFromObj`/`Tcl_SplitList` out-params int→Tcl_Size. (These show only as silent
   `-Wincompatible-pointer-types` warnings — grep sdl/ for those APIs feeding an `int`.)
6. **Fonts staging + family match:** stock Tk 9.1 omits the bundled DejaVu/Symbola TTFs → stage the exact
   13-file set (`cp jni/sdl2tk/library-86bak/fonts/*.ttf assets/sdl2tk9.1/fonts/`). And in
   SdlTkUtils.c `MatchFont`: when the requested family is a pure `*` wildcard and nothing matched, return
   the first loaded font (honours the "never NULL" contract); also map missed families to the matching
   bundled **DejaVu LGC** face (mono/serif/sans by keyword) so text looks like the 8.6 build, not a CJK
   fallback. Modern emulators lack "Droid Sans Mono", so this path is genuinely hit.

### Console + Demos wiring
`console eval` works: the wish and its Tk console share one interp family (tkAppInit.c
`Tk_CreateConsoleWindow` runs in the wish process, i.e. the `:CONSOLE` one), exactly the undroidwish/iWish
pattern. assets/main.tcl installs "Demos" as a submenu on the console's **File** menu via `console eval`,
with a `.`-menubar fallback (`aw_demos_fallback`). Placement matches undroidwish's bare-launch look (small
`.` + console beside it; no custom menu/hint on `.` per John's feedback). The earlier `console eval`
"failure" was only a too-short retry — bumped to 80 (150ms).

## OPEN — the one remaining runtime issue: high-DPI content font is too small
On high-DPI AVDs (320-dpi pixel_tablet, 420-dpi phone) the menu/console **text renders ~13px (tiny)**
where the from-source 8.6 build renders large. Diagnosis so far:
- `tk scaling` = 4.45 and `winfo fpixels . 1i` = 320 are **correct** (screen mwidth/DPI init in SdlTkX.c
  is right), yet `font actual TkDefaultFont -size` = 3 and the console XLFD comes out ~12px.
- Mechanism: the named default fonts (TkDefaultFont, TkFixedFont, …) appear to be **created/cached at a
  pixel size derived from a pre-320 DPI** (≈13px = "size 10pt @ 96dpi"). Because `ttk/fonts.tcl` guards
  its DPI-aware sizing with **TIP-145** (`variable tip145 [catch {font create TkDefaultFont}]`; the whole
  `font configure` block runs only `if {!$tip145}`), once the fonts already exist the block is skipped and
  they keep the tiny cached size. `::tk::FontScalingFactor` also returns 1 on Android (no `~/.config/
  monitors.xml`), so even the x11 branch would under-size.
- Runtime `console eval {font configure TkConsoleFont -size 40}` did **not** change it (`font actual`
  stayed 2/3), so a Tcl-level fix from main.tcl is not sufficient — the **real fix is in C**: ensure the
  screen DPI (320) is finalised *before* Tk creates the default fonts, or rescale the cached pixel sizes
  afterward, in the SDL font layer's point→pixel path.
- **Needs live `font actual` / `tk scaling` introspection on a stable emulator to finish** (a fix here is
  hard to validate blind). Emulator caveat: launch **windowed + detached** (`nohup … & disown`); do NOT
  `pkill -9 qemu` mid-session — the windowed AVDs are unstable when killed. Tablet AVD =
  `aw_tablet_api34` (pixel_tablet, android-34 arm64, density 320, 2560×1600).

## Status 2026-07-19
P0–P6 complete. Signed **0.1-alpha APK boots to an interactive Tcl console + Demos menu** on Android
arm64 (full batteries, 84 native libs). Remaining: (a) high-DPI content-font-size C fix (above);
(b) Phase 7 release — publish public repo `androwish-tcl91` + APK, bump version, add icon (awaits John's
review, [[no_commit_until_review]]). Working source with all fixes is committed locally in
`~/androwish-tcl91-work/build-tree` (git `c747645`).
