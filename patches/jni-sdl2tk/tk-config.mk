sdl_path := $(tk_path)/../SDL2
tk_includes := $(tk_path)/generic $(tk_path)/generic/ttk $(tk_path)/sdl $(tk_path)/xlib \
	$(sdl_path)/include $(tk_path)/bitmaps \
	$(tk_path)/sdl/agg-2.4/include $(tk_path)/sdl/agg-2.4/font_freetype $(tk_path)/sdl/agg-2.4/agg2d \
	$(tk_path)/../freetype/include
tk_cflags := \
	-DTK_LIBRARY="\"//zipfs:/assets/sdl2tk9.1\"" \
	-DPLATFORM_SDL=1 \
	-DTK_USE_POLL=1 \
	-DAGG_CUSTOM_ALLOCATOR=1 \
	-DTK_LAYOUT_WITH_BASE_CHUNKS=1
