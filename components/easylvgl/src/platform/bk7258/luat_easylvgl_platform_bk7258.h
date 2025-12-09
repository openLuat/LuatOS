#pragma once
/**
 * @file luat_easylvgl_platform_bk7258.h
 * @summary BK7258 平台共享数据与辅助接口
 * @responsible 统一维护 platform_data 结构，触摸配置绑定
 */
#if defined(__BK72XX__)

#include "luat_easylvgl.h"
#include "luat_lcd.h"
#include "luat_tp.h"

typedef struct {
    luat_lcd_conf_t *lcd_conf;       /**< LCD 配置指针 */
    luat_tp_config_t *tp_config;     /**< 触摸配置指针（可选） */
} bk7258_platform_data_t;

/**
 * 可选：在调用 easylvgl.init 之前绑定触摸配置，供平台驱动使用
 */
void easylvgl_platform_bk7258_bind_tp(luat_tp_config_t *cfg);

/**
 * 获取已绑定的触摸配置（可能为 NULL）
 */
luat_tp_config_t *easylvgl_platform_bk7258_get_tp_bind(void);

/**
 * 从 ctx->platform_data 获取 BK7258 平台数据
 */
static inline bk7258_platform_data_t *easylvgl_bk7258_get_data(easylvgl_ctx_t *ctx) {
    return (bk7258_platform_data_t *)(ctx ? ctx->platform_data : NULL);
}

#endif /* LUAT_USE_EASYLVGL_BK7258 */


