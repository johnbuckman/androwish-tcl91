# Batteries build triage vs Tcl 9.1 core — 2026-07-19 (full ndk-build -k, arm64-v8a)

## FINAL: **49 shared libs build** vs Tcl 9.1 (was 20 at first triage)
After the BUILD_tcl fix (below) + 4 parallel subagents porting every Tcl-only extension:
SDL2 SDL2_mixer TclCurl WavReader argparse bcrypt crypto_tls curl dropbear expect ffidl freetype
fswatch jpeg_tkimg lmdb memchan modbus mpexpr mpg123 nsf parse_args parser pikchr png_tkimg pty_tcl
rhash rl_json ssl_tls tbcload tcl tclcsv tclepeg tcllibc tclmixer tclral tcltls tcltrf tcludp tclvfs
tclx tclxml tdom tiff_tkimg tnc topcua usb vectcl vqtcl xml2xslt.
Remaining ~12 failing = ALL tk-dependent (blt tkhtml tkpath tkzinc Tix tktable snack tktreectrl rtext
vu 3dcanvas tcl-stbimage) — gated on libtk; retry once sdl2tk links (see SDL2TK-GRAFT.md, near done).

## History — after the BUILD_tcl fix: 30 shared libs (was 20)
SDL2 SDL2_mixer TclCurl WavReader argparse bcrypt crypto_tls curl dropbear freetype fswatch jpeg_tkimg lmdb modbus mpg123 parser pikchr png_tkimg ssl_tls tcl tclcsv tclepeg tclvfs tdom tiff_tkimg tnc usb vectcl vqtcl xml2xslt 

Key fix: `-DBUILD_tcl` had leaked into the SHARED tcl_cflags → suppressed ckalloc/ckfree
(`#ifndef BUILD_tcl` in tcl.h) across ALL extensions (~2800 errors). Moved it to the tcl
core module only. Errors 5574 -> 2478.

## Remaining Tcl-only extensions: small, per-extension Tcl-9 migrations (NOT one lever)
Each needs its own fix; representative:
- tls (2): TCL_CHANNEL_VERSION_2 gone -> use v5 channel type; Tcl_FreeProc sig (char* -> void*).
- tcludp (2): Tcl_DriverCloseProc removed -> Close2Proc; udpClose redef.
- Memchan (1): channel-type struct gained ThreadAction/wide fields.
- trf (1): TCL_PARSE_PART1 removed.
- tclral (4): Tcl_HashKeyProc now returns TCL_HASH_TYPE (size_t) not unsigned int.
- parse_args (5): bundled tip445.h shim conflicts (TIP 445 is in the 9.x core) -> guard for >=9.
- pty_tcl (5): old TCL_VARARGS / objv arg macros.
- panic (x8 across mods) -> Tcl_Panic ;  Tcl_Backslash (x8) removed.
Bigger: expect(213), tclxml(114), rl_json(38), nsf(38), tclx(20), mpexpr(11).

## Tk-dependent (~25) — ALL gated on sdl2tk->Tk9.1 (the keystone)
blt Tix itk vu src ZBar zint tkled tkvnc tkimg tksvg snack rtext VecTcl(vectcl built? see list)
tcluvc imgjp2 tkpsvg tkpath tkhtml tkzinc tktable libdmtx 3dcanvas imgtools tknotebook
tktreectrl tcl-stbimage. Mostly fail only on the tk.h '8.6 must be compiled with tcl.h from
8.6' guard + cascade -> should largely clear once libtk is Tk 9.1.

## sdl2tk -> Tk 9.1 graft = the multi-week keystone (proven NOT automatable)
Base stock Tk 9.1 generic + overlay sdl/ (49k lines) + xlib/ + re-insert 37 files' PLATFORM_SDL
hooks. Both 3-way-merge (35/37 conflict) and PLATFORM_SDL-hunk-extraction (34/37 reject) fail to
auto-apply because Tk 9.1's code around each hook site differs from 8.6.10. Requires manual
per-file hook placement + backend Tcl_Size/struct/stub-table porting. Graft scaffold staged at
~/androwish-tcl91-work/graft-sdl2tk91/ (stock 9.1 + backend overlaid + hooked_files.txt + .rej files).
