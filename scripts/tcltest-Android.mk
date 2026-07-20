LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := tcltest
LOCAL_SRC_FILES := main.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)/../tcl/generic
LOCAL_SHARED_LIBRARIES := tcl
LOCAL_LDLIBS := -llog
include $(BUILD_EXECUTABLE)
