#include "luat_airui_component.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"
#include "lua.h"
#include "lauxlib.h"
#include <lvgl.h>
#include <string.h>

#ifdef LUAT_USE_AIRUI
#ifdef LUAT_USE_GBC

#include "gbc.h"
#include "gbc_port.h"
#include "gbc_joypad.h"

#define LUAT_LOG_TAG "airui.gbc"
#include "luat_log.h"

#define GBC_SCREEN_W 160
#define GBC_SCREEN_H 144

/* AIRUI_GBC_KEY_* 常量来自 luat_airui_component.h，与 gbc_key_t 枚举值匹配 */
typedef struct {
    gbc_t *gbc_ctx;
    luat_rtos_task_handle gbc_thread;

    lv_obj_t *game_screen;

    uint16_t *framebuffer;
    lv_image_dsc_t img_dsc;

    char *rom_path;
    int scale;

    volatile int refresh_pending;
    int initialized;
} airui_gbc_data_t;

/* ========== 前向声明 ========== */

static int  _gbc_refresh_handler(lua_State *L, void *ptr);
static int  _gbc_draw_cb(void *ctx, int x1, int y1, int x2, int y2, void *pixels);
static void _gbc_frame_cb(void *ctx);
static void _gbc_release_data(void *user_data);

/* ========== GBC 渲染回调（GBC 线程中调用）========== */

static int _gbc_draw_cb(void *ctx, int x1, int y1, int x2, int y2, void *pixels_in) {
    airui_gbc_data_t *data = (airui_gbc_data_t *)ctx;
    uint16_t *pixels = (uint16_t *)pixels_in;
    if (!data || !data->initialized || !data->framebuffer) return -1;
    if (!pixels) return -2;
    if (x1 >= GBC_SCREEN_W || y1 >= GBC_SCREEN_H) return -3;
    if (x2 >= GBC_SCREEN_W)  x2 = GBC_SCREEN_W  - 1;
    if (y2 >= GBC_SCREEN_H) y2 = GBC_SCREEN_H - 1;

    size_t cols = x2 - x1 + 1;
    size_t rows = y2 - y1 + 1;
    int f = data->scale;
    int dst_stride = GBC_SCREEN_W * f;

#if (GBC_COLOR_SWAP == 0)
    if (f == 1) {
        for (size_t row = 0; row < rows; row++) {
            uint16_t *dst = data->framebuffer + (y1 + row) * dst_stride + x1;
            memcpy(dst, pixels + row * cols, cols * sizeof(uint16_t));
        }
    } else {
        for (size_t row = 0; row < rows; row++) {
            for (int dy = 0; dy < f; dy++) {
                uint16_t *dst = data->framebuffer + ((y1 + row) * f + dy) * dst_stride + x1 * f;
                const uint16_t *src = pixels + row * cols;
                for (size_t col = 0; col < cols; col++) {
                    uint16_t v = src[col];
                    uint16_t *dp = dst + col * f;
                    for (int dx = 0; dx < f; dx++) dp[dx] = v;
                }
            }
        }
    }
#else
    if (f == 1) {
        for (size_t row = 0; row < rows; row++) {
            uint16_t *dst = data->framebuffer + (y1 + row) * dst_stride + x1;
            const uint16_t *src = pixels + row * cols;
            for (size_t col = 0; col < cols; col++) {
                uint16_t v = src[col];
                dst[col] = (uint16_t)((v >> 8) | (v << 8));
            }
        }
    } else {
        for (size_t row = 0; row < rows; row++) {
            for (int dy = 0; dy < f; dy++) {
                uint16_t *dst = data->framebuffer + ((y1 + row) * f + dy) * dst_stride + x1 * f;
                const uint16_t *src = pixels + row * cols;
                for (size_t col = 0; col < cols; col++) {
                    uint16_t v = (uint16_t)((src[col] >> 8) | (src[col] << 8));
                    uint16_t *dp = dst + col * f;
                    for (int dx = 0; dx < f; dx++) dp[dx] = v;
                }
            }
        }
    }
#endif
    return 0;
}

static void _gbc_frame_cb(void *ctx) {
    airui_gbc_data_t *data = (airui_gbc_data_t *)ctx;
    if (!data || !data->initialized || !data->game_screen) return;
    if (data->refresh_pending) return;
    data->refresh_pending = 1;
    rtos_msg_t msg = {
        .handler = _gbc_refresh_handler,
        .ptr     = data,
        .arg1    = 0,
        .arg2    = 0,
    };
    if (luat_msgbus_put(&msg, 0) != 0) {
        data->refresh_pending = 0;
    }
}

/* ========== msgbus 刷新 handler（Lua 主线程中执行）========== */

static int _gbc_refresh_handler(lua_State *L, void *ptr) {
    (void)L;
    airui_gbc_data_t *data = (airui_gbc_data_t *)ptr;
    if (!data || !data->initialized || !data->game_screen) return 0;
    lv_obj_invalidate(data->game_screen);
    data->refresh_pending = 0;
    return 0;
}

/* ========== GBC 任务入口 ========== */

static void _gbc_task_entry(void *param) {
    gbc_t *ctx = (gbc_t *)param;
    if (!ctx) {
        while (1) { luat_rtos_task_sleep(1000); }
    }
    gbc_run(ctx);
    while (1) { luat_rtos_task_sleep(1000); }
}

/* ========== 销毁 ========== */

static void _gbc_release_data(void *user_data) {
    airui_gbc_data_t *data = (airui_gbc_data_t *)user_data;
    if (!data) return;

    data->initialized = 0;

    gbc_port_clear_render_cb();

    if (data->gbc_ctx) {
        data->gbc_ctx->gbc_quit = 1;
    }

    if (data->gbc_thread) {
        int timeout = 50;
        while (timeout-- > 0) {
            luat_rtos_task_sleep(10);
        }
        luat_rtos_task_delete(data->gbc_thread);
        data->gbc_thread = 0;
    }

    if (data->gbc_ctx) {
        gbc_deinit(data->gbc_ctx);
        data->gbc_ctx = NULL;
    }

    if (data->framebuffer) {
        lv_free(data->framebuffer);
        data->framebuffer = NULL;
    }

    if (data->rom_path) {
        luat_heap_free(data->rom_path);
        data->rom_path = NULL;
    }

    luat_heap_free(data);
}

/* ========== 公共 API ========== */

static airui_ctx_t *airui_gbc_get_ctx(lua_State *L_state) {
    airui_ctx_t *ctx = NULL;
    if (L_state == NULL) return NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    return ctx;
}

lv_obj_t *airui_gbc_create_from_config(void *L, int idx) {
    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_gbc_get_ctx(L_state);

    const char *rom = airui_marshal_string(L, idx, "rom", NULL);
    if (!rom) {
        LLOGE("GBC: 'rom' is required");
        return NULL;
    }

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    if (!parent) {
        parent = lv_screen_active();
    }
    if (!parent) {
        LLOGE("GBC: no parent or active screen");
        return NULL;
    }

    int scale = airui_marshal_integer(L, idx, "scale", 0);
    if (scale < 1) scale = 1;
    if (scale > 3) scale = 3;

    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);

    int scaled_w = GBC_SCREEN_W * scale;
    int scaled_h = GBC_SCREEN_H * scale;
    size_t buf_size = scaled_w * scaled_h * sizeof(uint16_t);
    uint16_t *fb = (uint16_t *)lv_malloc(buf_size);
    if (!fb) {
        LLOGE("GBC: framebuffer alloc failed");
        return NULL;
    }
    memset(fb, 0, buf_size);

    lv_obj_t *game_screen = lv_image_create(parent);

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, game_screen, AIRUI_COMPONENT_GBC);
    if (!meta) {
        lv_free(fb);
        lv_obj_delete(game_screen);
        return NULL;
    }

    airui_gbc_data_t *data = (airui_gbc_data_t *)luat_heap_malloc(sizeof(airui_gbc_data_t));
    if (!data) {
        lv_free(fb);
        lv_obj_delete(game_screen);
        return NULL;
    }
    memset(data, 0, sizeof(airui_gbc_data_t));
    data->game_screen = game_screen;
    data->framebuffer = fb;
    data->scale       = scale;
    data->rom_path    = (char *)luat_heap_malloc(strlen(rom) + 1);
    if (data->rom_path) {
        strcpy(data->rom_path, rom);
    }

    data->img_dsc = (lv_image_dsc_t){
        .header = {
            .magic  = LV_IMAGE_HEADER_MAGIC,
            .cf     = LV_COLOR_FORMAT_RGB565,
            .w      = (uint32_t)scaled_w,
            .h      = (uint32_t)scaled_h,
            .stride = (uint32_t)(scaled_w * sizeof(uint16_t)),
            .flags  = 0,
        },
        .data_size = (uint32_t)buf_size,
        .data      = (const uint8_t *)fb,
        .reserved  = NULL,
        .reserved_2 = NULL,
    };
    lv_image_set_src(game_screen, &data->img_dsc);

    lv_obj_set_size(game_screen, scaled_w, scaled_h);
    lv_obj_set_pos(game_screen, x, y);

    data->gbc_ctx = gbc_init();
    if (!data->gbc_ctx) {
        LLOGE("GBC: gbc_init failed");
        _gbc_release_data(data);
        lv_obj_delete(game_screen);
        return NULL;
    }
    if (gbc_load_file(data->gbc_ctx, rom) != GBC_OK) {
        LLOGE("GBC: gbc_load_file failed: %s", rom);
        _gbc_release_data(data);
        lv_obj_delete(game_screen);
        return NULL;
    }

    if (luat_rtos_task_create(&data->gbc_thread, 8 * 1024, 27,
                              "airui_gbc", _gbc_task_entry, data->gbc_ctx, 0)) {
        LLOGE("GBC: task create failed");
        _gbc_release_data(data);
        lv_obj_delete(game_screen);
        return NULL;
    }

    gbc_port_render_cb_t cb = {
        .draw  = _gbc_draw_cb,
        .frame = _gbc_frame_cb,
        .ctx   = data,
    };
    gbc_port_set_render_cb(&cb);

    data->initialized = 1;

    airui_component_meta_set_user_data(meta, data, _gbc_release_data);

    return game_screen;
}

int airui_gbc_destroy(lv_obj_t *gbc) {
    if (!gbc) return 0;
    lv_obj_delete(gbc);
    return 0;
}

int airui_gbc_set_key(lv_obj_t *gbc, int key, int pressed) {
    airui_component_meta_t *meta = airui_component_meta_get(gbc);
    if (!meta || !meta->user_data) return -1;
    airui_gbc_data_t *data = (airui_gbc_data_t *)meta->user_data;
    if (!data->gbc_ctx) return -2;
    gbc_key_t k;
    switch (key) {
        case AIRUI_GBC_KEY_UP:     k = GBC_KEY_UP;     break;
        case AIRUI_GBC_KEY_DOWN:   k = GBC_KEY_DOWN;   break;
        case AIRUI_GBC_KEY_LEFT:   k = GBC_KEY_LEFT;   break;
        case AIRUI_GBC_KEY_RIGHT:  k = GBC_KEY_RIGHT;  break;
        case AIRUI_GBC_KEY_A:      k = GBC_KEY_A;      break;
        case AIRUI_GBC_KEY_B:      k = GBC_KEY_B;      break;
        case AIRUI_GBC_KEY_START:  k = GBC_KEY_START;  break;
        case AIRUI_GBC_KEY_SELECT: k = GBC_KEY_SELECT; break;
        default: return -3;
    }
    gbc_joypad_set(data->gbc_ctx, k, (uint8_t)pressed);
    return 0;
}

#endif /* LUAT_USE_GBC */
#endif /* LUAT_USE_AIRUI */