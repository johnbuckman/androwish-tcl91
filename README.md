# androwish-tcl91

**[AndroWish](https://www.androwish.org/) rebuilt on Tcl/Tk 9.1** — documentation, ndk-build config
patches and scripts for porting AndroWish (Tcl/Tk on Android, via an SDL2 + AGG X11-emulation backend)
from its bundled **Tcl/Tk 8.6.10** to **Tcl/Tk 9.1.0** (the 9.1 release; the 0.1-alpha tracked 9.1b0).

Upstream AndroWish (both the `trunk` and `wtf-8-experiment` Fossil branches) ships Tcl/Tk 8.6.10,
and there is no Tk-9-on-SDL upstream.

> **Status: 1.0b2 (beta), on the Tcl/Tk 9.1.0 release.** A signed arm64 APK boots on Android to an
> interactive Tcl console with a **Demos** menu, and all eight demos run. All 84 native libraries build.
> 755 bundled packages load and none crashes the app; BLT and Expect work as of 1.0b2. Tcl's and Tk's
> own test suites run on the device. (1.0b0 and the 0.1-alpha claimed the demos launched; only the
> widget demo did.)

Part of the [johnbuckman.github.io/tcltk](https://johnbuckman.github.io/tcltk/) collection ·
[project page](https://johnbuckman.github.io/tcltk/androwish-tcl91.html).

---

## What's in this repo

This repo carries **documentation and build configuration only**. It does **not** redistribute the Tcl,
Tk, SDL2 or AndroWish sources; those are supplied from upstream.

| Path | What it is |
| --- | --- |
| `docs/PORT.md` | The full port: roadmap, analysis, and every runtime fix (**start here**) |
| `docs/AGENT-BOOTSTRAP.md` | Working notes: exact build/test commands, environment traps, and how the config macros were derived |
| `docs/SDL2TK-GRAFT.md` | How the `sdl/` + `xlib/` backend was grafted onto stock Tk 9.1 |
| `docs/BATTERIES-TRIAGE.md` | Per-extension Tcl 9 migration matrix (~80 extensions) |
| `patches/jni-tcl/` | ndk-build module config for Tcl 9.1 (`Android.mk`, `tcl-config.mk`, `srclist.mk`) |
| `patches/jni-sdl2tk/` | ndk-build module config + regenerated source list for Tk 9.1; `sdl/tk-9.1.0-backend.diff` is the backend change 9.1.0 needed |
| `patches/build-tree/1.0b1.diff` | Every 1.0b1 change to the AndroWish tree: extension Tcl 9 fixes, package indexes, the Demos menu |
| `patches/build-tree/expect-tcl9.diff` | Expect on Tcl 9 (1.0b2): version-5 channel type, `Tcl_Size` |
| `patches/build-tree/blt-tcl9.diff` | BLT on Tcl 9 (1.0b2): prototypes, object `Tk_ConfigureWidget`, `Tcl_Size`, the label-cache guard |
| `scripts/` | Tcl 9.1 module regeneration, a native Tcl/ABI assertion test, an on-device regression smoke test, an on-device package-load sweep, Tcl's and Tk's test suites run on the device, a config-macro audit, and `fix_tclsize.py` (the `int*`→`Tcl_Size*` fixer) |

## Port structure

AndroWish's `jni/sdl2tk` is Tk with an SDL2/AGG Xlib-emulation backend, and Christian Werner guards every
SDL-specific change to generic Tk behind `#ifdef PLATFORM_SDL` — ~177 markers across 37 files. The
port is **stock Tk 9.1 `generic/` + re-inserted PLATFORM_SDL hooks**, rather than a three-way merge (the
sdl2tk `generic/` is forked from an *older* 8.6.x, so diffing against 8.6.10 is misleading).

The remaining work is the self-contained `sdl/` backend (~49k lines) plus `xlib/` (~1.8k), ported to Tk 9.1
internals — `Tcl_Size`, changed structs, and the Tcl 9 object-based widget-option APIs.

## The bugs

Four runtime bugs stood between "it links" and "it runs". All are written up in `docs/PORT.md`:

1. **`Tcl_GetIntFromObj` failed for *every* non-negative integer on arm64**, surfacing as
   `bad level "#0"` from `upvar #0` inside `tkInit`. `TCL_WIDE_INT_IS_LONG` was undefined on this LP64
   build, so `Tcl_GetLongFromObj` took its 32-bit-`long` branch where `(Tcl_WideInt)(ULONG_MAX)`
   overflows to `-1` — making the range check `w <= -1` reject everything. Fix: define it.
   (Arithmetic still worked, because bytecode literals are parsed at compile time; only *runtime*
   string→integer conversion broke.)

2. **Stack corruption (`SIGABRT`) in `wm title`.** The 8.6-era X11-emulation layer passed `int*` where
   Tcl 9 expects `Tcl_Size*` (8-byte) out-params, smashing the stack. These are silent
   `-Wincompatible-pointer-types` warnings; grep the SDL layer for every `Tcl_GetStringFromObj`,
   `Tcl_ListObjGetElements`, `Tcl_GetByteArrayFromObj` and `Tcl_SplitList` feeding an `int`.

3. **No usable font.** Stock Tk 9.1 does not ship AndroWish's bundled DejaVu/Symbola faces, and the
   absolute font fallback could not resolve, so `TkpGetFontFromAttributes` panicked.

4. **Everything rendered tiny on high-DPI.** Tk was correct — it computed 44.5px for a 10pt font at
   320 dpi. The bug was that the emulated `XListFonts` answered generic family requests
   (`Helvetica`, `courier`) with a hardcoded XLFD carrying **pixel size 12**. A non-zero pixel size means
   a *fixed bitmap font* in X11, so Tk loaded it as-is and discarded the wanted size. Synthesized font
   list entries must use **pixel size 0 (= scalable)**.

## Building

Requires the AndroWish source tree, the Tcl 9.1 and Tk 9.1 sources, Android NDK **r27d**, and a JDK 21
(Android Studio's JBR works).

1. Check out AndroWish (Fossil) and rsync it to a working tree.
2. Replace `jni/tcl` with Tcl 9.1 and graft `jni/sdl2tk` onto Tk 9.1 — see `docs/SDL2TK-GRAFT.md`.
3. Copy this repo's `patches/jni-tcl/` and `patches/jni-sdl2tk/` over the corresponding module configs.
4. Stage the Tcl/Tk script libraries into `assets/tcl9.1` and `assets/sdl2tk9.1`, **including the bundled
   fonts** in `assets/sdl2tk9.1/fonts/`.
5. Build:

```sh
export ANDROID_NDK_HOME=.../ndk/27.3.13750724
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$ANDROID_NDK_HOME:$PATH"

"$ANDROID_NDK_HOME/ndk-build" NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=./jni/Android.mk \
    NDK_APPLICATION_MK=./jni/Application64.mk APP_ABI=arm64-v8a -j8
./gradlew assembleRelease
```

> **Gotchas.** Changing a `*-config.mk` compiler flag does **not** invalidate ndk-build's `.o` files;
> after editing one, `rm -rf obj/local/arm64-v8a/objs/<module>` or the flag will not apply.
> Gradle can also repackage a **stale** `.so`: build with `ndk-build` first, then
> `./gradlew --no-daemon assembleRelease --rerun-tasks`, and verify the `.so` inside the APK.

## The APK

`applicationId` is `tk.tcl.wish.tcl91`, so it installs **alongside** stock AndroWish rather than
replacing it.

- arm64-v8a only, `minSdkVersion 21`, `targetSdkVersion 36`, 84 native libraries
- Tcl/Tk 9.1.0 under `assets/tcl9.1` + `assets/sdl2tk9.1`
- Full batteries-included extension set

See [Releases](https://github.com/johnbuckman/androwish-tcl91/releases) for a signed build.

## Known limitations

- **Not every bundled package loads on Tcl 9 yet.** `scripts/emulator-pkgsweep.sh` tries every
  package: 755 load, 128 fail, and none crashes the app (1.0b1: 754 / 128, and Expect
  crashed). The failures are mostly nsf/nx/XOTcl (32), Tclx, Ffidl, Tix, Itcl/Itk and
  Thread, and the packages that need them. (1.0b0: 113 load, 192 fail, 7 crash.)
- **Some extensions still pass `int*` where Tcl 9 wants `Tcl_Size*`.** That corrupts the stack, and
  the app aborts with `stack corruption detected`. 1.0b1 fixed the extensions that load (tdom, tkimg,
  imgjp2, tkpsvg, tkpath, tkzinc, zint, vu, trofs, tclJBlend), and 1.0b2 fixed BLT and Expect; over a thousand call
  sites remain in others (snack, tktreectrl, Tix, Tclx, …). `scripts/fix_tclsize.py` fixes most of them from
  clang's `-Werror=incompatible-pointer-types` output.
- **Tktable is disabled.** Tktable 2.11 calls Tk 9's `Tk_ConfigureWidget` with strings and crashes.
- **arm64-v8a only** — no 32-bit or x86 ABI in this build.
- In production use by a number of people. The automated checks run on emulators:
  `scripts/emulator-smoke.sh` asserts all four bugs above on-device and passes
  15/15 at both 320 dpi/API 34 and 420 dpi/API 31. `scripts/emulator-suite.sh` runs Tcl's and
  Tk's own test suites inside the app: 54,102 Tcl tests pass and 438 fail; 7,704 Tk tests pass
  and 199 fail. Most failures are the device, not the port: no `tclsh` to `exec`, no network,
  shared storage, and no standard channels.
- On API 34+, GPS/NMEA (`borg gps`) is inactive: the legacy listeners are guarded off to keep launch
  from crashing, and the modern `GnssStatus`/`OnNmeaMessageListener` replacements aren't wired to Tcl yet.
- Polish outstanding: default icon, and the main `.` window is an empty placeholder.

## License

Same terms as Tcl/Tk — see [`LICENSE`](LICENSE).

AndroWish is by Christian Werner; Tcl/Tk by the Tcl Core Team. This repository only contains the port's
documentation and build configuration.
