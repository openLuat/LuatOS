/**
 * @file luat_airui_platform_luatos.c
 * @summary LuatOS 平台驱动 ops 导出
 * @responsible 汇总显示/输入/时基接口，提供 TP 绑定辅助
 */

 #include "luat_conf_bsp.h"
 #if defined(__BK72XX__)
     #include "luat_conf_bsp_air8101.h"
 #endif
 
 #if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui.h"
#include "luat_airui_platform_luatos.h"

// 驱动接口获取函数声明
extern const airui_display_ops_t *airui_platform_luatos_get_display_ops(void);
extern const airui_input_ops_t *airui_platform_luatos_get_input_ops(void);
extern const airui_time_ops_t *airui_platform_luatos_get_time_ops(void);

// 默认触摸配置绑定（可选）
static luat_tp_config_t *g_tp_bind = NULL;

void airui_platform_luatos_bind_tp(luat_tp_config_t *cfg)
{
    g_tp_bind = cfg;
}

luat_tp_config_t *airui_platform_luatos_get_tp_bind(void)
{
    return g_tp_bind;
}

/**
 * 获取 LuatOS 平台驱动操作接口
 */
const airui_platform_ops_t *airui_platform_ops_luatos_get(void)
{
    static bool initialized = false;
    static airui_platform_ops_t ops;

    if (!initialized) {
        ops.display_ops = airui_platform_luatos_get_display_ops();
        ops.input_ops = airui_platform_luatos_get_input_ops();
        ops.time_ops = airui_platform_luatos_get_time_ops();
        ops.fs_ops = NULL;   // 默认使用 LuatOS 文件系统桥接
        ops.log_ops = NULL;  // 复用 LuatOS 日志
        initialized = true;
    }

    return &ops;
}

#endif /* LUAT_USE_AIRUI_LUATOS */


