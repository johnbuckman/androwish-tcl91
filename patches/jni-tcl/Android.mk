LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
tcl_path := $(LOCAL_PATH)
include $(tcl_path)/tcl-config.mk
LOCAL_ADDITIONAL_DEPENDENCIES += $(tcl_path)/tcl-config.mk
LOCAL_MODULE := tcl
LOCAL_ARM_MODE := arm
LOCAL_C_INCLUDES := $(tcl_includes)
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_C_INCLUDES)
include $(tcl_path)/srclist.mk
LOCAL_CFLAGS := $(tcl_cflags) -DPACKAGE_NAME="\"tcl\"" -DPACKAGE_VERSION="\"9.1\"" -O2 -Wno-implicit-function-declaration
LOCAL_LDLIBS := -ldl -lz -llog
include $(BUILD_SHARED_LIBRARY)
