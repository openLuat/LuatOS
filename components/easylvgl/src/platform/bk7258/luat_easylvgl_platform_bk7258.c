/**
 * @file luat_easylvgl_platform_bk7258.c
 * @summary BK7258 平台驱动 ops 导出
 * @responsible 汇总显示/输入/时基接口，提供 TP 绑定辅助
 */

#if defined(__BK72XX__)

#include "luat_easylvgl.h"
#include "luat_easylvgl_platform_bk7258.h"

// 驱动接口获取函数声明
extern const easylvgl_display_ops_t *easylvgl_platform_bk7258_get_display_ops(void);
extern const easylvgl_input_ops_t *easylvgl_platform_bk7258_get_input_ops(void);
extern const easylvgl_time_ops_t *easylvgl_platform_bk7258_get_time_ops(void);

// 默认触摸配置绑定（可选）
static luat_tp_config_t *g_tp_bind = NULL;

void easylvgl_platform_bk7258_bind_tp(luat_tp_config_t *cfg)
{
    g_tp_bind = cfg;
}

luat_tp_config_t *easylvgl_platform_bk7258_get_tp_bind(void)
{
    return g_tp_bind;
}

/**
 * 获取 BK7258 平台驱动操作接口
 */
const easylvgl_platform_ops_t *easylvgl_platform_ops_bk7258_get(void)
{
    static bool initialized = false;
    static easylvgl_platform_ops_t ops;

    if (!initialized) {
        ops.display_ops = easylvgl_platform_bk7258_get_display_ops();
        ops.input_ops = easylvgl_platform_bk7258_get_input_ops();
        ops.time_ops = easylvgl_platform_bk7258_get_time_ops();
        ops.fs_ops = NULL;   // 默认使用 LuatOS 文件系统桥接
        ops.log_ops = NULL;  // 复用 LuatOS 日志
        initialized = true;
    }

    return &ops;
}

#endif /* LUAT_USE_EASYLVGL_BK7258 */


