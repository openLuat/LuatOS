cmake_minimum_required(VERSION 3.20)

if(NOT CONFIG_LUATOS)
  return()
endif()

# Root of LuatOS repo (two levels up from this file: zephyr/ -> repo root)
get_filename_component(LUATOS_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

zephyr_library_named(luatos)

# ── Include paths ──────────────────────────────────────────────────────────────
# Public headers exported to all targets (app, luatos library, etc.)
zephyr_include_directories(
  ${LUATOS_ROOT}/luat/include
  ${LUATOS_ROOT}/lua/src
  ${LUATOS_ROOT}/lua/include
  ${LUATOS_ROOT}/bsp/zephyr/port/include
  ${LUATOS_ROOT}/components/printf
)

# Private headers only needed when compiling luatos library sources
zephyr_library_include_directories(
  ${LUATOS_ROOT}/components/cjson
  ${LUATOS_ROOT}/components/lua-cjson
)

# ── Compile definitions ────────────────────────────────────────────────────────
# Force-include luat_conf_bsp.h as the very first thing in every luatos library
# source file. This defines __LUATOS__ (and all other BSP flags) before any
# other header is processed, breaking the circular dependency where luat_base.h
# needs __LUATOS__ to include lua.h, but __LUATOS__ only gets defined inside
# the include chain that is gated by that same #ifdef.
zephyr_library_compile_options(
  -include ${LUATOS_ROOT}/bsp/zephyr/port/include/luat_conf_bsp.h
)

# ── Lua VM ─────────────────────────────────────────────────────────────────────
file(GLOB LUA_SRC ${LUATOS_ROOT}/lua/src/*.c)
zephyr_library_sources(${LUA_SRC})

# ── printf component (provides snprintf_) ─────────────────────────────────────
zephyr_library_sources(${LUATOS_ROOT}/components/printf/printf.c)

# ── cjson / lua-cjson ──────────────────────────────────────────────────────────
zephyr_library_sources(
  ${LUATOS_ROOT}/components/cjson/cJSON.c
  ${LUATOS_ROOT}/components/lua-cjson/lua_cjson.c
  ${LUATOS_ROOT}/components/lua-cjson/strbuf.c
  ${LUATOS_ROOT}/components/lua-cjson/fpconv.c
)

# ── LuatOS core modules ────────────────────────────────────────────────────────
zephyr_library_sources(
  ${LUATOS_ROOT}/luat/modules/luat_main.c
  ${LUATOS_ROOT}/luat/modules/luat_base.c
  ${LUATOS_ROOT}/luat/modules/luat_lib_rtos.c
  ${LUATOS_ROOT}/luat/modules/luat_lib_timer.c
  ${LUATOS_ROOT}/luat/modules/luat_lib_gpio.c
  ${LUATOS_ROOT}/luat/modules/luat_lib_log.c
  ${LUATOS_ROOT}/luat/modules/luat_lib_zbuff.c
  ${LUATOS_ROOT}/luat/modules/luat_lib_pack.c
  ${LUATOS_ROOT}/luat/modules/luat_lib_fs.c
  ${LUATOS_ROOT}/luat/modules/luat_lib_bit64.c
)

# ── VFS layer ──────────────────────────────────────────────────────────────────
zephyr_library_sources(
  ${LUATOS_ROOT}/luat/vfs/luat_vfs.c
  ${LUATOS_ROOT}/luat/vfs/luat_fs_inline.c
  ${LUATOS_ROOT}/luat/vfs/luat_inline_libs.c
)

# ── Weak / legacy RTOS wrappers ────────────────────────────────────────────────
zephyr_library_sources(
  ${LUATOS_ROOT}/luat/weak/luat_rtos_lua.c
  ${LUATOS_ROOT}/luat/weak/luat_rtos_legacy_to_std.c
  ${LUATOS_ROOT}/luat/weak/luat_mem_weak.c
  ${LUATOS_ROOT}/luat/weak/luat_malloc_weak.c
  ${LUATOS_ROOT}/luat/weak/luat_fs_weak.c
)

# ── Zephyr BSP port files ──────────────────────────────────────────────────────
zephyr_library_sources(
  ${LUATOS_ROOT}/bsp/zephyr/port/luat_base_zephyr.c
  ${LUATOS_ROOT}/bsp/zephyr/port/luat_log_zephyr.c
  ${LUATOS_ROOT}/bsp/zephyr/port/luat_malloc_zephyr.c
  ${LUATOS_ROOT}/bsp/zephyr/port/luat_fs_zephyr.c
  ${LUATOS_ROOT}/bsp/zephyr/port/rtos/luat_rtos_zephyr.c
  ${LUATOS_ROOT}/bsp/zephyr/port/luat_spi_zephyr.c
  ${LUATOS_ROOT}/bsp/zephyr/port/luat_gpio_zephyr.c
  ${LUATOS_ROOT}/bsp/zephyr/port/luat_mcu_zephyr.c
  ${LUATOS_ROOT}/bsp/zephyr/port/luat_lcd_zephyr_ltdc.c
)

# ── LCD + AirUI (enabled by LUAT_USE_GUI in luat_conf_bsp.h) ──────────────────

# Include paths for LCD, u8g2, AirUI, LVGL9
zephyr_include_directories(
  ${LUATOS_ROOT}/components/lcd
  ${LUATOS_ROOT}/components/u8g2
  ${LUATOS_ROOT}/components/tp
  ${LUATOS_ROOT}/components/qrcode
  ${LUATOS_ROOT}/components/hzfont/inc
  ${LUATOS_ROOT}/components/airui
  ${LUATOS_ROOT}/components/airui/inc
  ${LUATOS_ROOT}/components/airui/lvgl9
  ${LUATOS_ROOT}/components/airui/lvgl9/src
  ${LUATOS_ROOT}/components/airui/lvgl9/src/stdlib/custom
)

# Also ensure LVGL can find lv_conf.h (lv_conf.h → luat_airui_conf.h → luat_conf_bsp.h)
zephyr_library_compile_options(-I${LUATOS_ROOT}/components/airui/lvgl9)

# LCD core (luat_lcd.c + Lua binding)
zephyr_library_sources(
  ${LUATOS_ROOT}/components/lcd/luat_lcd.c
  ${LUATOS_ROOT}/components/lcd/luat_lib_lcd.c
  # LCD panel drivers (each provides lcd_opts_<panelname>)
  ${LUATOS_ROOT}/components/lcd/luat_lcd_st7735.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_st7735v.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_st7735s.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_st7789.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_st7796.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_gc9a01.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_gc9106l.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_gc9306x.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_ili9341.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_ili9486.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_nv3037.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_nv3041a.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_h050iwv.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_jd9261t.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_sh8601z.c
  ${LUATOS_ROOT}/components/lcd/luat_lcd_custom.c
)

# QR code encoder (used by luat_lib_lcd.c l_lcd_drawQrcode)
zephyr_library_sources(
  ${LUATOS_ROOT}/components/qrcode/qrcodegen.c
)

# u8g2 minimal core — only rendering files needed for u8g2_t in luat_lcd_conf_t.
# Device-specific u8x8_d_*.c drivers are excluded (hardware-specific, ~100 files).
zephyr_library_sources(
  ${LUATOS_ROOT}/components/u8g2/u8g2_arc.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_bitmap.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_box.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_buffer.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_button.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_circle.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_cleardisplay.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_d_memory.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_d_setup.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_font.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_fonts.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_hvline.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_input_value.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_intersection.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_kerning.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_line.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_ll_hvline.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_message.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_polygon.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_selection_list.c
  ${LUATOS_ROOT}/components/u8g2/u8g2_setup.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_8x8.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_byte.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_cad.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_capture.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_debounce.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_display.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_fonts.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_gpio.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_input_value.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_message.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_selection_list.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_setup.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_string.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_u16toa.c
  ${LUATOS_ROOT}/components/u8g2/u8x8_u8toa.c
  ${LUATOS_ROOT}/components/u8g2/u8log.c
  ${LUATOS_ROOT}/components/u8g2/u8log_u8g2.c
  ${LUATOS_ROOT}/components/u8g2/u8log_u8x8.c
  ${LUATOS_ROOT}/components/u8g2/mui.c
  ${LUATOS_ROOT}/components/u8g2/mui_u8g2.c
  # Font data used by luat_lib_lcd.c (u8g2_font_opposansm12 symbol)
  ${LUATOS_ROOT}/components/u8g2/u8g2_font_opposansm.c
)

# LVGL 9 — all .c files from src/, excluding:
#   thorvg/  (C++ renderer for SVG/Lottie; requires C++ toolchain)
#   lottie/  (Lottie animation; depends on thorvg)
#   SDL/Arduino/GLTF specific files (not applicable on Zephyr/embedded)
file(GLOB_RECURSE LVGL9_SRCS
  ${LUATOS_ROOT}/components/airui/lvgl9/src/*.c
)
list(FILTER LVGL9_SRCS EXCLUDE REGEX ".*/thorvg/.*")
list(FILTER LVGL9_SRCS EXCLUDE REGEX ".*/lottie/.*")
list(FILTER LVGL9_SRCS EXCLUDE REGEX ".*lv_lovyan_gfx.*")
list(FILTER LVGL9_SRCS EXCLUDE REGEX ".*lv_tft_espi.*")
list(FILTER LVGL9_SRCS EXCLUDE REGEX ".*lv_fs_arduino.*")
list(FILTER LVGL9_SRCS EXCLUDE REGEX ".*lv_gltf.*")
# The custom allocator file is in stdlib/custom/ — already included by the glob,
# but list it explicitly here as documentation:
# ${LUATOS_ROOT}/components/airui/lvgl9/src/stdlib/custom/luat_lv_mem_core_custom.c
zephyr_library_sources(${LVGL9_SRCS})

# AirUI core + platform (luatos) — all .c, excluding:
#   platform/sdl/       (SDL2 desktop simulator, not available on Zephyr)
#   luat_airui_lottie   (depends on thorvg C++)
#   luat_airui_video    (depends on video player hardware)
#   luat_airui_jpg_decoder_luatos (depends on JPEG hardware decoder)
file(GLOB_RECURSE AIRUI_SRCS
  ${LUATOS_ROOT}/components/airui/src/*.c
)
list(FILTER AIRUI_SRCS EXCLUDE REGEX ".*/platform/sdl/.*")
list(FILTER AIRUI_SRCS EXCLUDE REGEX ".*luat_airui_lottie.*")
list(FILTER AIRUI_SRCS EXCLUDE REGEX ".*luat_airui_video.*")
list(FILTER AIRUI_SRCS EXCLUDE REGEX ".*luat_airui_jpg_decoder.*")
zephyr_library_sources(${AIRUI_SRCS})

# AirUI Lua bindings (binding/*.c), excluding bindings for excluded widgets
file(GLOB AIRUI_BINDING_SRCS
  ${LUATOS_ROOT}/components/airui/binding/*.c
)
list(FILTER AIRUI_BINDING_SRCS EXCLUDE REGEX ".*luat_lib_airui_lottie.*")
list(FILTER AIRUI_BINDING_SRCS EXCLUDE REGEX ".*luat_lib_airui_video.*")
zephyr_library_sources(${AIRUI_BINDING_SRCS})

# ── luat_image — image decoding (JPEG via tjpgd, PNG via lodepng) ─────────────
zephyr_include_directories(
  ${LUATOS_ROOT}/components/luat_image/include
  ${LUATOS_ROOT}/components/tjpgd
  ${LUATOS_ROOT}/components/luat_image/libs/lodepng
)

# luat_image_common.h is a private header only needed by luat_image src files
zephyr_library_include_directories(
  ${LUATOS_ROOT}/components/luat_image/src
)

zephyr_library_sources(
  ${LUATOS_ROOT}/components/luat_image/src/luat_image.c
  ${LUATOS_ROOT}/components/luat_image/src/luat_image_common.c
  ${LUATOS_ROOT}/components/luat_image/src/luat_image_jpeg.c
  ${LUATOS_ROOT}/components/luat_image/src/luat_image_png.c
  ${LUATOS_ROOT}/components/luat_image/src/luat_image_webp.c
  # tjpgd SW JPEG decoder (LV_USE_TJPGD=0, so LVGL does not compile its copy)
  ${LUATOS_ROOT}/components/tjpgd/tjpgd.c
  # lodepng is compiled by LVGL (LV_USE_LODEPNG=1 in luat_airui_conf.h); do NOT add here
  # LCD JPEG draw helpers (lcd_draw_jpeg / lcd_jpeg_decode weak implementations)
  ${LUATOS_ROOT}/components/lcd/luat_lib_lcd_jpg.c
)
