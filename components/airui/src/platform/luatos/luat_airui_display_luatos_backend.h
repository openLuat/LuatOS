#pragma once
/**
 * @file luat_airui_display_luatos_backend.h
 * @summary LuatOS 显示后端 vtable（内部头，不暴露 lcd/display 类型）
 */

#include "luat_airui.h"

typedef struct airui_luatos_fb_backend {
    const char *name;
    int (*attach)(airui_ctx_t *ctx, uint16_t w, uint16_t h, void **out_ctx);
    int (*get_buffers)(void *backend_ctx, void **fb_addr, uint32_t *buf_size, uint32_t *count);
    void (*flush)(airui_ctx_t *ctx, void *backend_ctx, const lv_area_t *area, const uint8_t *px_map);
    int (*direct_present)(airui_ctx_t *ctx, void *backend_ctx, const void *owner,
                          const lv_area_t *area, const void *buffer, lv_color_format_t fmt);
    void (*direct_hide)(airui_ctx_t *ctx, void *backend_ctx, const void *owner);
    int (*suspend)(airui_ctx_t *ctx, void *backend_ctx);
    int (*resume)(airui_ctx_t *ctx, void *backend_ctx);
    void (*detach)(void *backend_ctx);
} airui_luatos_fb_backend_t;

const airui_luatos_fb_backend_t *airui_luatos_fb_backend_display(void);
const airui_luatos_fb_backend_t *airui_luatos_fb_backend_lcd(void);
