/**
 * @file luat_airui_platform_sdl.c
 * @summary SDL2 平台驱动 ops 导出
 * @responsible 导出 SDL2 平台驱动操作接口集合
 */

#include "luat_conf_bsp.h"

#if defined(LUAT_USE_AIRUI_SDL2)

#include "luat_airui.h"

// 声明各驱动操作接口获取函数
extern const airui_display_ops_t *airui_platform_sdl2_get_display_ops(void);
extern const airui_input_ops_t *airui_platform_sdl2_get_input_ops(void);
extern const airui_time_ops_t *airui_platform_sdl2_get_time_ops(void);

/** SDL2 平台驱动操作接口集合 */
const airui_platform_ops_t airui_platform_ops_sdl2 = {
    .display_ops = NULL,  // 将在运行时设置
    .fs_ops = NULL,        // SDL 使用标准文件系统
    .input_ops = NULL,     // 将在运行时设置
    .time_ops = NULL,      // 将在运行时设置
    .log_ops = NULL
};

/**
 * 获取 SDL2 平台驱动操作接口
 * @return SDL2 平台驱动操作接口指针
 */
const airui_platform_ops_t *airui_platform_ops_sdl2_get(void)
{
    // 运行时初始化 ops（避免静态初始化顺序问题）
    static bool initialized = false;
    static airui_platform_ops_t ops;
    
    if (!initialized) {
        ops.display_ops = airui_platform_sdl2_get_display_ops();
        ops.input_ops = airui_platform_sdl2_get_input_ops();
        ops.time_ops = airui_platform_sdl2_get_time_ops();
        ops.fs_ops = NULL;
        ops.log_ops = NULL;
        initialized = true;
    }
    
    return &ops;
}

#endif /* LUAT_USE_AIRUI_SDL2 */

