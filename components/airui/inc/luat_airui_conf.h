/**
 * @file luat_airui_conf.h
 * @summary AIRUI 平台相关配置
 * @description 根据不同的平台（SDL2、LuatOS等）配置 LVGL 参数
 * 
 * 注意：此文件会被 lv_conf.h 包含，用于覆盖默认配置
 */

#ifndef LUAT_AIRUI_CONF_H
#define LUAT_AIRUI_CONF_H

#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

/** AIRUI 库版本号 */
#define AIRUI_VERSION "1.0.2"

/*=================
 * PLATFORM CONFIGURATION
 *=================*/

#if defined(LUAT_USE_AIRUI_SDL2)
    /* SDL2 平台配置 */
    #define LV_USE_OS   LV_OS_NONE  /* SDL2 平台可能不需要 OSAL */

    #define LV_COLOR_DEPTH 16

    #define LV_USE_LOG 1
    #define LV_LOG_LEVEL LV_LOG_LEVEL_INFO

    // 使用自定义堆（Lua堆），测试在键盘组件会异常
    // #define LV_USE_STDLIB_MALLOC    LV_STDLIB_CUSTOM
    // 模拟器使用clib堆，todo： 研究为什么使用自定义堆在keyborad组件会失效
    #define LV_USE_STDLIB_MALLOC    LV_STDLIB_CLIB

    // 打开图片解码器
    #define LV_USE_LODEPNG 1
    #define LV_USE_TJPGD 1

    // 默认字体设置
    #define LV_FONT_FMT_TXT_LARGE 1
    #define LV_USE_FONT_COMPRESSED 1
    #define LV_FONT_CUSTOM_DECLARE LV_FONT_DECLARE(lv_font_misans_20) LV_FONT_DECLARE(lv_font_misans_14)
    
    // #define LV_FONT_DEFAULT &lv_font_misans_20
    #define LV_FONT_DEFAULT &lv_font_misans_14

    // 打开XML支持
    #define LV_USE_XML 1
    #define LV_USE_OBJ_NAME 1

    // 打开拼音输入法
    #define LV_USE_IME_PINYIN 1
    #define LV_IME_PINYIN_USE_DEFAULT_DICT 0 // 关闭默认使用自己的pinyin词库，但需要打开LUAT_USE_PINYIN宏
    #define LV_IME_PINYIN_CAND_TEXT_NUM 9 // 设置拼音候选词数量

    // lottie 支持
    #define LV_USE_LOTTIE 1
    #define LV_USE_FLOAT 1
    #define LV_USE_MATRIX 1
    #define LV_USE_VECTOR_GRAPHIC  1
    #define LV_USE_THORVG_INTERNAL 1

#elif defined(LUAT_USE_AIRUI_LUATOS)
    /* LuatOS 平台配置：使用 FreeRTOS 以支持 LVGL 多线程渲染 */
    #define LV_USE_OS   LV_OS_NONE  /* SDL2 平台可能不需要 OSAL */
    // #define LV_USE_OS   LV_OS_FREERTOS
    // #define LV_DRAW_SW_DRAW_UNIT_CNT    1   // 开启2个软件渲染单元以并行绘制
    // #define LV_USE_PARALLEL_DRAW_DEBUG  0    // 开启并行绘制调试

    #define LV_COLOR_DEPTH 16

    // 使用自定义堆（Lua堆）
    #define LV_USE_STDLIB_MALLOC    LV_STDLIB_CUSTOM


    // #define LV_USE_LOG 1
    // /** Set value to one of the following levels of logging detail:
    //  *  - LV_LOG_LEVEL_TRACE    Log detailed information.
    //  *  - LV_LOG_LEVEL_INFO     Log important events.
    //  *  - LV_LOG_LEVEL_WARN     Log if something unwanted happened but didn't cause a problem.
    //  *  - LV_LOG_LEVEL_ERROR    Log only critical issues, when system may fail.
    //  *  - LV_LOG_LEVEL_USER     Log only custom log messages added by the user.
    //  *  - LV_LOG_LEVEL_NONE     Do not log anything. */
    // #define LV_LOG_LEVEL LV_LOG_LEVEL_INFO
    
    // 图片解码支持
    #define LV_USE_LODEPNG 1
    #define LV_USE_TJPGD 1

    // 打开XML支持
    #define LV_USE_XML 1
    #define LV_USE_OBJ_NAME 1

    // 打开拼音输入法
    #define LV_USE_IME_PINYIN 1
    #define LV_IME_PINYIN_USE_DEFAULT_DICT 0 // 关闭默认使用自己的pinyin词库，但需要打开LUAT_USE_PINYIN宏
    #define LV_IME_PINYIN_CAND_TEXT_NUM 6 // 设置拼音候选词数量

#else
    /* 默认配置（如果未定义平台） */
    /* 使用 lv_conf.h 中的默认值，这里不需要重新定义 */
#endif

#endif /* LUAT_AIRUI_CONF_H */

