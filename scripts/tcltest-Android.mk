LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
tcl_path := $(LOCAL_PATH)/../tcl
# Pull in tcl_cflags so the test translation unit is compiled with exactly the
# macros the library was built with.  Without this the #ifdef checks in
# main.c test the test's own compilation rather than libtcl's, and report a
# false failure for TCL_WIDE_INT_IS_LONG.
include $(tcl_path)/tcl-config.mk
LOCAL_MODULE := tcltest
LOCAL_SRC_FILES := main.c
LOCAL_C_INCLUDES := $(tcl_includes)
LOCAL_CFLAGS := $(tcl_cflags)
LOCAL_SHARED_LIBRARIES := tcl
LOCAL_LDLIBS := -llog
include $(BUILD_EXECUTABLE)
