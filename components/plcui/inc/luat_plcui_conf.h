/**
 * @file luat_plcui_conf.h
 * @summary PLCUI runtime and platform-specific LVGL configuration.
 * @description Based on AirUI 1.3.1; maintained independently for PLCUI.
 */
#ifndef LUAT_PLCUI_CONF_H
#define LUAT_PLCUI_CONF_H

#include "luat_conf_bsp.h"
#if defined(LUAT_USE_PLCUI_SDL2) && defined(LUAT_USE_PLCUI_LUATOS)
#error "Select exactly one PLCUI platform"
#endif

#define PLCUI_VERSION "1.0.0"

/* Runtime settings are available even in the PC dual-library build, whose
 * single LVGL instance uses the AIRUI profile. */
#ifdef LUAT_USE_PLCUI_IMAGE_CACHE_SIZE
#define PLCUI_IMAGE_CACHE_BYTES LUAT_USE_PLCUI_IMAGE_CACHE_SIZE
#else
#define PLCUI_IMAGE_CACHE_BYTES (6U * 1024U * 1024U)
#endif
#define PLCUI_DISPLAY_LINES 80
#define PLCUI_HZFONT_DEFAULT_SIZE 16U
#define PLCUI_REFRESH_RATE_HZ 60U
#define PLCUI_HANDLER_PERIOD_MS 5U
#define PLCUI_REFRESH_PERIOD_MS ((1000U + PLCUI_REFRESH_RATE_HZ - 1U) / PLCUI_REFRESH_RATE_HZ)

#endif

/* Emit LVGL options only when selected by PLCUI's lv_conf.h. Keeping this
 * separate from the runtime guard also supports including runtime settings
 * before LVGL, without skipping the selected configuration later. */
#if defined(PLCUI_LVGL_CONFIG) && !defined(PLCUI_LVGL_CONFIG_H)
#define PLCUI_LVGL_CONFIG_H

/* Common rendering/allocator/codec settings, matching the verified 0.2 port. */
#define LV_COLOR_DEPTH 16
#define LV_USE_OS LV_OS_NONE
#define LV_USE_STDLIB_MALLOC LV_STDLIB_CUSTOM
#define LV_USE_LODEPNG 1
#define LV_USE_HZJPEG 1
#define LV_CACHE_DEF_SIZE PLCUI_IMAGE_CACHE_BYTES

/* PLCUI uses the bundled Expat parser. LVGL's XML initialization is compiled
 * as well because the bundled parser shares the LV_USE_XML feature gate. */
#define LV_USE_XML 1
#define LV_USE_OBJ_NAME 1
#define LV_USE_OBSERVER 1
#ifndef XML_STATIC
#define XML_STATIC
#endif

/* Preserve the codec/font/layout baseline; component APIs remain PLCUI's own. */
#define LV_USE_IME_PINYIN 1
#define LV_IME_PINYIN_USE_DEFAULT_DICT 0
#define LV_IME_PINYIN_CAND_TEXT_NUM 6

#ifdef LUAT_USE_PLCUI_LVGL_HEAP_TYPE
#define LUAT_PLCUI_LVGL_HEAP_TYPE LUAT_USE_PLCUI_LVGL_HEAP_TYPE
#elif defined(LUAT_USE_PSRAM)
#define LUAT_PLCUI_LVGL_HEAP_TYPE LUAT_HEAP_PSRAM
#else
#define LUAT_PLCUI_LVGL_HEAP_TYPE LUAT_HEAP_AUTO
#endif

/*=================
 * PLATFORM CONFIGURATION
 *=================*/
#if defined(LUAT_USE_PLCUI_SDL2)
    #define LV_IMAGE_HEADER_CACHE_DEF_CNT 32
    #define LV_USE_LOG 1
    #define LV_LOG_LEVEL LV_LOG_LEVEL_WARN

    #define LV_FONT_FMT_TXT_LARGE 1
    #define LV_USE_FONT_COMPRESSED 1
    #define LV_FONT_CUSTOM_DECLARE LV_FONT_DECLARE(lv_font_misans_14) LV_FONT_DECLARE(lv_font_misans_16) LV_FONT_DECLARE(lv_font_misans_20)
    #define LV_FONT_DEFAULT &lv_font_misans_14

    #define LV_USE_LOTTIE 1
    #define LV_USE_FLOAT 1
    #define LV_USE_MATRIX 1
    #define LV_USE_VECTOR_GRAPHIC 1
    #define LV_USE_THORVG_INTERNAL 1

#elif defined(LUAT_USE_PLCUI_LUATOS)
    #define LV_IMAGE_HEADER_CACHE_DEF_CNT 64
    #define LV_DRAW_LAYER_SIMPLE_BUF_SIZE (512U * 1024U)

    /* Optional default font, controlled only by PLCUI's BSP setting. */
    #ifdef LUAT_USE_PLCUI_MISANS_FONT_16
        #define LV_FONT_FMT_TXT_LARGE 1
        #define LV_USE_FONT_COMPRESSED 1
        #define LV_FONT_CUSTOM_DECLARE LV_FONT_DECLARE(lv_font_misans_16)
        #define LV_FONT_DEFAULT &lv_font_misans_16
    #endif
#else
    #error "The PLCUI LVGL profile requires a PLCUI SDL2 or LuatOS platform"
#endif

#endif /* PLCUI_LVGL_CONFIG */
