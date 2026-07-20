# sdl2tk → Tk 9.1b0 graft — recipe & status

Goal: AndroWish's SDL2/AGG Xlib-emulation Tk backend, re-based onto **stock Tk 9.1b0** generic sources.

## Approach that worked (empirical compile-and-fix, NOT patch-replay)
Patch-replay of the PLATFORM_SDL hooks FAILED (3-way merge 35/37 conflict; hunk-extract 34/37 reject —
Tk 9.1's code around each hook differs from 8.6.10). Instead: **stock Tk 9.1 generic + overlay the SDL
backend (sdl/, xlib/) + fix compile errors as they surface.** AndroWish's generic is 105 stock-Tk files
+ 2 net-new, and the SDL backend is self-contained, which makes this tractable.

Work tree: `~/androwish-tcl91-work/build-tree/jni/sdl2tk` (9.1 generic in `generic/`, 8.6 backup in
`generic-86bak/`, backend in `sdl/`+`xlib/`). Build just the tk module (isolated):
```
cd ~/androwish-tcl91-work/build-tree
ndk-build NDK_PROJECT_PATH=. NDK_APPLICATION_MK=jni/Application.mk APP_MODULES=tk \
  NDK_OUT=/tmp/obj-tk NDK_LIBS_OUT=/tmp/libs-tk -k -j6
```

## Error trajectory: 633 → 0 compile errors (widget backend was the tail)
The fixes, in leverage order (each cleared the count shown):

1. **Platform-include hooks** (the compile-critical PLATFORM_SDL redirects), applied to 9.1 generic:
   - `tkPort.h`: `#if defined(PLATFORM_SDL) # include "tkSDLPort.h"` before the win/unix branches.
   - `tkInt.h`: `#ifdef PLATFORM_SDL #include "SdlTkX.h" #endif` after the tkPort include.
   - `default.h`: `#ifdef PLATFORM_SDL # include "tkSDLDefault.h"` before win/unix.
2. **XIDProc unknown → 336 errors.** Tk 9.1 added Xlib callback types the SDL Xlib subset lacks. Added
   `typedef void (*XIDProc)(Display*, XPointer, XPointer);` (guarded) at point-of-use in
   `generic/tkIntXlibDecls.h` (the full Xlib.h isn't in the SDL include path). Also added the 9.1 callback
   types (XConnectionWatchProc/XOMProc/XIOError*Handler) to `xlib/X11/Xlib.h`.
3. **Native-bitmap macro collision → 250 errors.** `sdl/tkSDLPort.h` `#define`d `TkpDefineNativeBitmaps`/
   `TkpCreateNativeBitmap`/`TkpGetNativeAppBitmap` as macros, colliding with 9.1's function decls.
   9.1's `tkIntDecls.h:1109` **already** provides no-op macros for `!MAC_OSX_TK && !USE_TK_STUBS` — so
   just comment out tkSDLPort.h's three defines (do NOT add a compat .c — that conflicts with the macros).
4. **`-DUSE_TCL_STUBS` on the tk lib was wrong** — remove it (a library implements, not stub-calls).
5. **`tkUnixInt.h` not found (7 files).** Create `sdl/tkUnixInt.h` that `#include "tkInt.h"` +
   `#include "tkIntPlatDecls.h"` + (PLATFORM_SDL) `#include "SdlTkInt.h"` — the real tkUnixInt.h is what
   pulls tkIntPlatDecls.h (tkInt.h alone doesn't), which is why TkCreateXEventSource et al. were undeclared.
6. **PointerUpdate/XUpdatePointerEvent** — AndroWish's custom pointer event, in the 8.6 tk.h but not 9.1.
   Port the `#define PointerUpdate (MappingNotify+6)` + the `XUpdatePointerEvent` struct into 9.1 `tk.h`
   under `#ifdef PLATFORM_SDL`.
7. **SdlTk.h**: `TkpCmapStressed`/`TkpWmSetState` return `int` → change to `bool` (9.1 signature).
8. **`TK_LAYOUT_WITH_BASE_CHUNKS`** must be defined (`-DTK_LAYOUT_WITH_BASE_CHUNKS=1`) — 9.1 tkTextDisp.c's
   `CharInfo.isRtl` and the RTL code assume base-chunk layout; it's build-supplied, never #defined in-source.
9. **Source list**: generate from Tk 9.1 `unix/Makefile.in` OBJS (GENERIC/WIDG/CANV/IMAGE/TEXT/STUB → generic/,
   TTK → generic/ttk/) + the SDL backend (sdl/tkSDL*, sdl/SdlTk*, Region/PolyReg/AGG, xlib/xcolors). DROP the
   unix font objs (tkUnixFont/tkUnixRFont/tkUnixBidiFont) — SDL provides fonts via tkSDLFont. 152 sources.
   Config kept in `patches/jni-sdl2tk/{tk-config.mk,Android.mk}` (+ srclist91.mk).

## Remaining tail (widget-struct reconciliation, ~120 errors in 7 SDL widget files)
`sdl/tkSDLButton.c tkSDLScale.c tkSDLScrlbr.c tkSDLMenu.c tkSDLMenubu.c tkSDLWm.c tkSDLFont.c` reference
Tk widget-struct fields that Tk 9.0+ migrated to **Tcl_Obj\*** (`highlightWidth`→`highlightWidthObj`,
`borderWidth`→`borderWidthObj`, `padX/Y`→`padX/YObj`, `width`→`widthObj`, `masterMenuPtr`→`mainMenuPtr`, …)
plus font-function signature changes (Tcl_Size lengths for Tk_DrawChars/Tk_MeasureChars/etc.). Each needs the
old int field replaced with the Obj + a Tk_GetPixelsFromObj conversion. (In progress.)
