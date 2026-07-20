# androwish-tcl91

**[AndroWish](https://www.androwish.org/) rebuilt on Tcl/Tk 9.1** — docs, ndk-build config patches and
scripts for porting AndroWish (Tcl/Tk on Android, via an SDL2 + AGG X11-emulation backend) from its
bundled **Tcl/Tk 8.6.10** to **Tcl/Tk 9.1b0**.

Upstream AndroWish (both the `trunk` and `wtf-8-experiment` Fossil branches) still ships Tcl/Tk 8.6.10,
and there is no Tk-9-on-SDL anywhere upstream — so this is a from-scratch port, not a version bump.

> **Status: 0.1-alpha — it works.** A signed arm64 APK boots on Android to an interactive Tcl console
> with a working **File ▸ Demos** menu, and the bundled demos launch. All 84 native libraries build,
> including the full "batteries included" extension set.

---

## What's in this repo

This repo carries **documentation and build configuration only**. It does **not** redistribute the Tcl,
Tk, SDL2 or AndroWish sources — you supply those from upstream.

| Path | What it is |
| --- | --- |
| `docs/PORT.md` | The full port: roadmap, analysis, and every runtime fix (**start here**) |
| `docs/SDL2TK-GRAFT.md` | How the `sdl/` + `xlib/` backend was grafted onto stock Tk 9.1 |
| `docs/BATTERIES-TRIAGE.md` | Per-extension Tcl 9 migration matrix (~80 extensions) |
| `patches/jni-tcl/` | ndk-build module config for Tcl 9.1 (`Android.mk`, `tcl-config.mk`) |
| `patches/jni-sdl2tk/` | ndk-build module config + regenerated source list for Tk 9.1 |
| `scripts/` | Tcl 9.1 module regeneration + a native Tcl smoke test |

## Why the port is tractable

AndroWish's `jni/sdl2tk` is Tk with an SDL2/AGG Xlib-emulation backend, and Christian Werner guards every
SDL-specific change to generic Tk behind `#ifdef PLATFORM_SDL` — only ~177 markers across 37 files. So the
port is **stock Tk 9.1 `generic/` + re-inserted PLATFORM_SDL hooks**, rather than a three-way merge (the
sdl2tk `generic/` is forked from an *older* 8.6.x, so diffing against 8.6.10 is misleading).

The real work is the self-contained `sdl/` backend (~49k lines) plus `xlib/` (~1.8k), ported to Tk 9.1
internals — `Tcl_Size`, changed structs, and the Tcl 9 object-based widget-option APIs.

## The interesting bugs

Four runtime bugs stood between "it links" and "it runs". All are written up in `docs/PORT.md`:

1. **Stack corruption (`SIGABRT`) in `wm title`.** The 8.6-era X11-emulation layer passed `int*` where
   Tcl 9 expects `Tcl_Size*` (8-byte) out-params, smashing the stack. These are silent
   `-Wincompatible-pointer-types` warnings — grep the SDL layer for every `Tcl_GetStringFromObj`,
   `Tcl_ListObjGetElements`, `Tcl_GetByteArrayFromObj` and `Tcl_SplitList` feeding an `int`.

2. **`Tcl_GetIntFromObj` failed for *every* non-negative integer on arm64**, surfacing as
   `bad level "#0"` from `upvar #0` inside `tkInit`. `TCL_WIDE_INT_IS_LONG` was undefined on this LP64
   build, so `Tcl_GetLongFromObj` took its 32-bit-`long` branch where `(Tcl_WideInt)(ULONG_MAX)`
   overflows to `-1` — making the range check `w <= -1` reject everything. Fix: define it.
   (Arithmetic still worked, because bytecode literals are parsed at compile time; only *runtime*
   string→integer conversion broke.)

3. **No usable font.** Stock Tk 9.1 doesn't ship AndroWish's bundled DejaVu/Symbola faces, and the
   absolute font fallback couldn't resolve, so `TkpGetFontFromAttributes` panicked.

4. **Everything rendered tiny on high-DPI.** Tk was correct — it computed 44.5px for a 10pt font at
   320 dpi. The bug was that the emulated `XListFonts` answered generic family requests
   (`Helvetica`, `courier`) with a hardcoded XLFD carrying **pixel size 12**. A non-zero pixel size means
   a *fixed bitmap font* in X11, so Tk loaded it as-is and threw the wanted size away. Synthesized font
   list entries must use **pixel size 0 (= scalable)**.

## Building

You need the AndroWish source tree, the Tcl 9.1 and Tk 9.1 sources, Android NDK **r27d**, and a JDK 21
(Android Studio's JBR works).

1. Check out AndroWish (Fossil) and rsync it to a working tree.
2. Replace `jni/tcl` with Tcl 9.1 and graft `jni/sdl2tk` onto Tk 9.1 — see `docs/SDL2TK-GRAFT.md`.
3. Copy this repo's `patches/jni-tcl/` and `patches/jni-sdl2tk/` over the corresponding module configs.
4. Stage the Tcl/Tk script libraries into `assets/tcl9.1` and `assets/sdl2tk9.1`, **including the bundled
   fonts** in `assets/sdl2tk9.1/fonts/`.
5. Build:

```sh
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.3.13750724
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$ANDROID_NDK_HOME:$PATH"

"$ANDROID_NDK_HOME/ndk-build" NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=./jni/Android.mk \
    NDK_APPLICATION_MK=./jni/Application64.mk APP_ABI=arm64-v8a -j8
./gradlew assembleRelease
```

> **Gotcha:** changing a `*-config.mk` compiler flag does **not** invalidate ndk-build's `.o` files.
> After editing one, `rm -rf obj/local/arm64-v8a/objs/<module>` or the flag silently won't apply.

## The alpha APK

`applicationId` is `tk.tcl.wish.tcl91`, so it installs **alongside** stock AndroWish rather than
replacing it.

- arm64-v8a only, `minSdkVersion 21`, 84 native libraries
- Tcl/Tk 9.1b0 under `assets/tcl9.1` + `assets/sdl2tk9.1`
- Full batteries-included extension set

See [Releases](https://github.com/johnbuckman/androwish-tcl91/releases) for a signed build.

## Known limitations

- Tracks Tcl/Tk **9.1b0**; will want a rebuild against 9.1 final.
- **arm64-v8a only** — no 32-bit or x86 ABI in this build.
- Verified on emulators (320 dpi tablet, 420 dpi phone); not yet broadly tested on physical devices.
- Alpha polish outstanding: default icon, and the main `.` window is an empty placeholder.

## License

Same terms as Tcl/Tk — see [`LICENSE`](LICENSE).

AndroWish is by Christian Werner; Tcl/Tk by the Tcl Core Team. This repository only contains the port's
documentation and build configuration.
