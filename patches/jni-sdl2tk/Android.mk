LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
tcl_path := $(LOCAL_PATH)/../tcl
include $(tcl_path)/tcl-config.mk
tk_path := $(LOCAL_PATH)
include $(tk_path)/tk-config.mk
LOCAL_MODULE := tk
LOCAL_ARM_MODE := arm
LOCAL_C_INCLUDES := $(tk_includes) $(tcl_includes)
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_C_INCLUDES)
include $(tk_path)/srclist91.mk
LOCAL_CFLAGS := $(tcl_cflags) $(tk_cflags) -DBUILD_tk=1 -O2 \
	-Wno-int-conversion -Wno-incompatible-function-pointer-types
LOCAL_SHARED_LIBRARIES := libtcl libSDL2 libfreetype
LOCAL_LDLIBS := -llog
include $(BUILD_SHARED_LIBRARY)
