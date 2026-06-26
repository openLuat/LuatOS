/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#pragma once

#include "gbc_default.h"

#ifdef __cplusplus
    extern "C" {
#endif

/* This header re-exports the platform hooks declared in gbc_default.h and
 * adds the LuatOS-specific rendering callback / AirUI mode switch. */

typedef struct {
    int  (*draw)(void *ctx, int x1, int y1, int x2, int y2, void *pixels);
    void (*frame)(void *ctx);
    void *ctx;
} gbc_port_render_cb_t;

/**
 * @brief 注册/替换 GBC 渲染回调（由 airui widget 等使用）
 * @param cb 非 NULL 时安装回调；传 NULL 等价于 clear_render_cb
 */
void gbc_port_set_render_cb(gbc_port_render_cb_t *cb);

/**
 * @brief 清除已注册的渲染回调
 */
void gbc_port_clear_render_cb(void);

#ifdef LUAT_USE_AIRUI
/**
 * @brief 切换 legacy AirUI 模式：1=走 gbc_airui_video，0=LCD 直绘（默认）
 */
void gbc_set_airui_mode(int enabled);
#endif

#ifdef __cplusplus
    }
#endif