#pragma once
/**
 * @file luat_airui_platform_luatos.h
 * @summary LuatOS 平台共享数据与辅助接口
 * @responsible 统一维护 platform_data 结构，触摸配置绑定
 */


#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui.h"
#include "luat_lcd.h"
#include "luat_tp.h"

/** GPIO 按键配置结构体 */
typedef struct {
    int up; // 上键
    int down; // 下键
    int left; // 左键
    int right; // 右键
    int ok; // 确认键
    int back; // 返回键
    uint8_t active_low; // 低电平有效
    uint8_t pull_mode; // 推挽模式
    uint8_t enabled; // 是否启用
} airui_luatos_keypad_cfg_t;

/** LuatOS 平台数据结构体 */
typedef struct {
    luat_lcd_conf_t *lcd_conf;       /**< LCD 配置指针 */
    luat_tp_config_t *tp_config;     /**< 触摸配置指针（可选） */
    airui_luatos_keypad_cfg_t keypad_cfg; /**< GPIO 按键配置（可选） */
} luatos_platform_data_t;

/**
 * 可选：在调用 airui.init 之前绑定触摸配置，供平台驱动使用
 */
void airui_platform_luatos_bind_tp(luat_tp_config_t *cfg);

/**
 * 获取已绑定的触摸配置（可能为 NULL）
 */
luat_tp_config_t *airui_platform_luatos_get_tp_bind(void);

/**
 * 可选：在调用 airui.init 之前绑定 GPIO 按键配置
 */
void airui_platform_luatos_bind_keypad(const airui_luatos_keypad_cfg_t *cfg);

/**
 * 获取已绑定的 GPIO 按键配置（可能为 NULL）
 */
const airui_luatos_keypad_cfg_t *airui_platform_luatos_get_keypad_bind(void);

/**
 * 从 ctx->platform_data 获取 LuatOS 平台数据
 */
static inline luatos_platform_data_t *airui_luatos_get_data(airui_ctx_t *ctx) {
    return (luatos_platform_data_t *)(ctx ? ctx->platform_data : NULL);
}

#endif /* LUAT_USE_AIRUI_LUATOS */


