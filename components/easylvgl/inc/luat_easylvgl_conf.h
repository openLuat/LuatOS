/**
 * @file luat_easylvgl_conf.h
 * @summary EasyLVGL 平台相关配置
 * @description 根据不同的平台（SDL2、BK7258等）配置 LVGL 参数
 * 
 * 注意：此文件会被 lv_conf.h 包含，用于覆盖默认配置
 */

#ifndef LUAT_EASYLVGL_CONF_H
#define LUAT_EASYLVGL_CONF_H

/*=================
 * PLATFORM CONFIGURATION
 *=================*/
 
 // 打开png支持
 #define LV_USE_LODEPNG 1

#if defined(LUAT_USE_EASYLVGL_SDL2)
    /* SDL2 平台配置 */
    #define LV_USE_OS   LV_OS_NONE  /* SDL2 平台可能不需要 OSAL */

    #define LV_USE_LOG 1
    /** Set value to one of the following levels of logging detail:
     *  - LV_LOG_LEVEL_TRACE    Log detailed information.
     *  - LV_LOG_LEVEL_INFO     Log important events.
     *  - LV_LOG_LEVEL_WARN     Log if something unwanted happened but didn't cause a problem.
     *  - LV_LOG_LEVEL_ERROR    Log only critical issues, when system may fail.
     *  - LV_LOG_LEVEL_USER     Log only custom log messages added by the user.
     *  - LV_LOG_LEVEL_NONE     Do not log anything. */
    #define LV_LOG_LEVEL LV_LOG_LEVEL_INFO

    #define LV_MEM_SIZE (256 * 1024U)
    
    // 打开png支持
    #define LV_USE_LODEPNG 1

#elif defined(__BK72XX__)
    /* BK7258 平台配置 */
    #define LV_USE_OS   LV_OS_NONE  /* BK7258 使用自定义 OSAL */

    #define LV_USE_LOG 1
    /** Set value to one of the following levels of logging detail:
     *  - LV_LOG_LEVEL_TRACE    Log detailed information.
     *  - LV_LOG_LEVEL_INFO     Log important events.
     *  - LV_LOG_LEVEL_WARN     Log if something unwanted happened but didn't cause a problem.
     *  - LV_LOG_LEVEL_ERROR    Log only critical issues, when system may fail.
     *  - LV_LOG_LEVEL_USER     Log only custom log messages added by the user.
     *  - LV_LOG_LEVEL_NONE     Do not log anything. */
    #define LV_LOG_LEVEL LV_LOG_LEVEL_INFO

    #define LV_MEM_SIZE (128 * 1024U)
    
    // 打开png支持
    #define LV_USE_LODEPNG 1

#else
    /* 默认配置（如果未定义平台） */
    /* 使用 lv_conf.h 中的默认值，这里不需要重新定义 */
#endif

#endif /* LUAT_EASYLVGL_CONF_H */

