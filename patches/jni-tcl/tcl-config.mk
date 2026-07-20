tcl_includes := $(tcl_path)/generic $(tcl_path)/unix $(tcl_path)/libtommath $(tcl_path)/compat/zlib $(tcl_path)/compat/zlib/contrib/minizip

# Macros recovered by diffing this hand-rolled config against a real
# cross-configure run for the actual target:
#
#   CC=<ndk>/aarch64-linux-android21-clang tcl_cv_sys_version=Linux-4.4 \
#     tcl/unix/configure --host=aarch64-linux-android --enable-64bit
#
# ndk-build bypasses configure entirely, so anything missing here fails
# silently at runtime rather than at build time -- that is exactly how the
# missing TCL_WIDE_INT_IS_LONG turned into "bad level #0".  scripts/
# tclcfg-audit.sh re-runs that diff; run it after any Tcl version bump.
#
# Note HAVE_ST_BLKSIZE further down: that is the Tcl 8.6 spelling and Tcl 9
# does not test it anywhere.  The 9.x spelling is HAVE_STRUCT_STAT_ST_BLKSIZE,
# which was absent -- so `file stat` had been under-reporting.  The other
# dead-for-Tcl-9 defines are deliberately left in place: tcl_cflags is shared
# with all 84 extension modules, several of which still test the old names.
#
# Deliberately NOT adopted from configure:
#   MODULE_SCOPE / HAVE_HIDDEN  hidden visibility would strip Tcl internals
#                               from libtcl9.1.so; extensions resolve lazily
#                               at dlopen time, so breakage would surface at
#                               runtime rather than at link time.
#   HAVE_MTSAFE_GETHOSTBYNAME/ADDR
#                               tcl.m4 infers these from a glibc heuristic
#                               keyed on "Linux"; bionic is not glibc.
#   _DARWIN_C_SOURCE, TCL_LOAD_FROM_MEMORY, HAVE_WEAK_IMPORT, TCL_WIDE_CLICKS
#                               macOS-only, leaked in from the build host.
#                               TCL_WIDE_CLICKS is the trap: configure offers
#                               it, but tclUnixTime.c #errors unless
#                               MAC_OSX_TCL is also set.
#
# Everything adopted above was re-verified by compiling a probe against the
# NDK sysroot at API 21 rather than trusting configure, since the run above
# still leaked some darwin results despite tcl_cv_sys_version.
tcl_cflags_from_configure := \
	-DHAVE_STRUCT_STAT_ST_BLKSIZE=1 -DHAVE_STRUCT_STAT_ST_BLOCKS=1 \
	-DHAVE_STRUCT_STAT_ST_RDEV=1 -DHAVE_BLKCNT_T=1 \
	-DHAVE_GETPWUID_R=1 -DHAVE_GETPWUID_R_5=1 \
	-DHAVE_GETPWNAM_R=1 -DHAVE_GETPWNAM_R_5=1 \
	-DHAVE_CFMAKERAW=1 -DHAVE_VFORK=1 -DHAVE_FTS=1 \
	-DHAVE_INTTYPES_H=1 -DHAVE_STDINT_H=1 -DHAVE_SYS_TYPES_H=1 \
	-DHAVE_SYS_STAT_H=1 -DHAVE_STRING_H=1 -DHAVE_STRINGS_H=1 \
	-DHAVE_STDLIB_H=1 -DHAVE_STDIO_H=1 \
	-DTCL_CFG_DO64BIT=1 -DNDEBUG=1

tcl_cflags := \
	-DHAVE_SYS_SELECT_H=1 -DHAVE_LIMITS_H=1 -DHAVE_UNISTD_H=1 -DHAVE_SYS_PARAM_H=1 \
	-D_LARGEFILE64_SOURCE=1 -DTCL_WIDE_INT_TYPE="long long" -DTCL_WIDE_INT_IS_LONG=1 -DTCL_SHLIB_EXT="\".so\"" \
	-DHAVE_CAST_TO_UNION=1 -DHAVE_GETCWD=1 -DHAVE_OPENDIR=1 -DHAVE_MKSTEMP=1 -DHAVE_MKSTEMPS=1 \
	-DHAVE_STRSTR=1 -DHAVE_STRTOL=1 -DHAVE_STRTOLL=1 -DHAVE_STRTOULL=1 \
	-DHAVE_WAITPID=1 -DHAVE_STRUCT_ADDRINFO=1 -DHAVE_STRUCT_IN6_ADDR=1 \
	-DHAVE_STRUCT_SOCKADDR_IN6=1 -DHAVE_STRUCT_SOCKADDR_STORAGE=1 -DHAVE_GETHOSTBYNAME_R=1 \
	-DHAVE_GETADDRINFO=1 -DHAVE_GETNAMEINFO=1 -DHAVE_FREEADDRINFO=1 -DHAVE_GAI_STRERROR=1 \
	-DUSE_TERMIOS=1 -DHAVE_TERMIOS_H=1 -DHAVE_MKTIME=1 -DUSE_INTERP_ERRORLINE=1 \
	-DHAVE_SYS_TIME_H=1 -DTIME_WITH_SYS_TIME=1 -DHAVE_TM_ZONE=1 -DHAVE_GMTIME_R=1 \
	-DHAVE_LOCALTIME_R=1 -DHAVE_TM_GMTOFF=1 -DHAVE_TIMEZONE_VAR=1 -DHAVE_ST_BLKSIZE=1 \
	-DSTDC_HEADERS=1 -DHAVE_INTPTR_T=1 -DHAVE_UINTPTR_T=1 -DHAVE_SIGNED_CHAR=1 \
	-DHAVE_SYS_IOCTL_H=1 -DHAVE_MEMCPY=1 -DHAVE_MEMMOVE=1 -DHAVE_CLOCK_GETTIME=1 \
	$(tcl_cflags_from_configure) \
	-DHAVE_PTHREAD_CONDATTR_SETCLOCK=1 -DHAVE_PTHREAD_ATFORK=1 -DHAVE_PTHREAD_ATTR_SETSTACKSIZE=1 \
	-DVOID=void -DNO_UNION_WAIT=1 -DHAVE_ZLIB=1 \
	-DMP_PREC=4 -DMP_FIXED_CUTOFFS=1 -DTCL_TOMMATH=1 \
	-D_REENTRANT=1 -D_THREAD_SAFE=1 \
	-DTCL_THREADS=1 -DUSE_THREAD_ALLOC=1 \
	-DTCL_CFGVAL_ENCODING="\"utf-8\"" -DTCL_UNLOAD_DLLS=1 -DTCL_CFG_OPTIMIZED=1 \
	-DZIPFS_BUILD=1 -DUTF8PROC_STATIC \
	-DTCL_PACKAGE_PATH="\"/assets\"" \
	  -DCFG_RUNTIME_DLLFILE="\"libtcl9.1.so\"" -DCFG_RUNTIME_DEMODIR="\"/assets/demos\"" -DCFG_INSTALL_DEMODIR="\"/assets/demos\"" -DCFG_RUNTIME_LIBDIR="\"/assets\"" -DCFG_RUNTIME_BINDIR="\"/assets\"" -DCFG_RUNTIME_SCRDIR="\"/assets/tcl9.1\"" -DCFG_RUNTIME_INCDIR="\"/assets/include\"" -DCFG_RUNTIME_DOCDIR="\"/assets/doc\"" -DCFG_RUNTIME_ENCODING="\"utf-8\"" -DCFG_INSTALL_LIBDIR="\"/assets\"" -DCFG_INSTALL_BINDIR="\"/assets\"" -DCFG_INSTALL_SCRDIR="\"/assets/tcl9.1\"" -DCFG_INSTALL_INCDIR="\"/assets/include\"" -DCFG_INSTALL_DOCDIR="\"/assets/doc\"" \
	-DTCL_LIBRARY="\"//zipfs:/assets/tcl9.1\""
