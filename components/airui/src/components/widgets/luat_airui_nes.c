#include "luat_airui_component.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"
#include "lua.h"
#include "lauxlib.h"
#include "nes.h"
#include "nes_port.h"
#include <lvgl.h>
#include <string.h>

#ifdef LUAT_USE_AIRUI
#ifdef LUAT_USE_NES

#define LUAT_LOG_TAG "airui.nes"
#include "luat_log.h"

#define NES_SCREEN_W 256
#define NES_SCREEN_H 240

enum {
    NES_KEY_UP = 1,
    NES_KEY_DOWN,
    NES_KEY_LEFT,
    NES_KEY_RIGHT,
    NES_KEY_A,
    NES_KEY_B,
    NES_KEY_START,
    NES_KEY_SELECT
};

typedef struct {
    nes_t *nes_ctx;
    luat_rtos_task_handle nes_thread;

    lv_obj_t *game_screen;

    uint16_t *framebuffer;
    lv_image_dsc_t img_dsc;

    char *rom_path;
    int scale;

    volatile int refresh_pending;
    int initialized;
} airui_nes_data_t;

/* ========== 前向声明 ========== */

static int  _nes_refresh_handler(lua_State *L, void *ptr);
static int  _nes_draw_cb(void *ctx, int x1, int y1, int x2, int y2, void *pixels);
static void _nes_frame_cb(void *ctx);
static void _nes_release_data(void *user_data);

/* ========== NES 渲染回调（NES 线程中调用）========== */

static int _nes_draw_cb(void *ctx, int x1, int y1, int x2, int y2, void *pixels_in) {
    airui_nes_data_t *data = (airui_nes_data_t *)ctx;
    uint16_t *pixels = (uint16_t *)pixels_in;
    if (!data || !data->initialized || !data->framebuffer) return -1;
    if (!pixels) return -2;
    if (x1 >= NES_SCREEN_W || y1 >= NES_SCREEN_H) return -3;
    if (x2 >= NES_SCREEN_W)  x2 = NES_SCREEN_W  - 1;
    if (y2 >= NES_SCREEN_H) y2 = NES_SCREEN_H - 1;

    size_t cols = x2 - x1 + 1;
    size_t rows = y2 - y1 + 1;
    int f = data->scale;
    int dst_stride = NES_SCREEN_W * f;

#if (NES_COLOR_SWAP == 0)
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

static void _nes_frame_cb(void *ctx) {
    airui_nes_data_t *data = (airui_nes_data_t *)ctx;
    if (!data || !data->initialized || !data->game_screen) return;
    if (data->refresh_pending) return;
    data->refresh_pending = 1;
    rtos_msg_t msg = {
        .handler = _nes_refresh_handler,
        .ptr     = data,
        .arg1    = 0,
        .arg2    = 0,
    };
    if (luat_msgbus_put(&msg, 0) != 0) {
        data->refresh_pending = 0;
    }
}

/* ========== msgbus 刷新 handler（Lua 主线程中执行）========== */

static int _nes_refresh_handler(lua_State *L, void *ptr) {
    (void)L;
    airui_nes_data_t *data = (airui_nes_data_t *)ptr;
    if (!data || !data->initialized || !data->game_screen) return 0;
    lv_obj_invalidate(data->game_screen);
    data->refresh_pending = 0;
    return 0;
}

/* ========== NES 任务入口 ========== */

static void _nes_task_entry(void *param) {
    nes_t *ctx = (nes_t *)param;
    if (!ctx) {
        while (1) { luat_rtos_task_sleep(1000); }
    }
    nes_run(ctx);
    while (1) { luat_rtos_task_sleep(1000); }
}

/* ========== 销毁 ========== */

static void _nes_release_data(void *user_data) {
    airui_nes_data_t *data = (airui_nes_data_t *)user_data;
    if (!data) return;

    data->initialized = 0;

    nes_port_clear_render_cb();

    if (data->nes_ctx) {
        data->nes_ctx->nes_quit = 1;
    }

    if (data->nes_thread) {
        int timeout = 50;
        while (timeout-- > 0) {
            luat_rtos_task_sleep(10);
        }
        luat_rtos_task_delete(data->nes_thread);
        data->nes_thread = 0;
    }

    if (data->nes_ctx) {
        nes_deinit(data->nes_ctx);
        data->nes_ctx = NULL;
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

static airui_ctx_t *airui_nes_get_ctx(lua_State *L_state) {
    airui_ctx_t *ctx = NULL;
    if (L_state == NULL) return NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    return ctx;
}

lv_obj_t *airui_nes_create_from_config(void *L, int idx) {
    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_nes_get_ctx(L_state);

    const char *rom = airui_marshal_string(L, idx, "rom", NULL);
    if (!rom) {
        LLOGE("NES: 'rom' is required");
        return NULL;
    }

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    if (!parent) {
        parent = lv_screen_active();
    }
    if (!parent) {
        LLOGE("NES: no parent or active screen");
        return NULL;
    }

    int scale = airui_marshal_integer(L, idx, "scale", 0);
    if (scale < 1) scale = 1;
    if (scale > 3) scale = 3;

    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);

    int scaled_w = NES_SCREEN_W * scale;
    int scaled_h = NES_SCREEN_H * scale;
    size_t buf_size = scaled_w * scaled_h * sizeof(uint16_t);
    uint16_t *fb = lv_malloc(buf_size);
    if (!fb) {
        LLOGE("NES: framebuffer alloc failed");
        return NULL;
    }
    memset(fb, 0, buf_size);

    lv_obj_t *game_screen = lv_image_create(parent);

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, game_screen, AIRUI_COMPONENT_NES);
    if (!meta) {
        lv_free(fb);
        lv_obj_delete(game_screen);
        return NULL;
    }

    airui_nes_data_t *data = (airui_nes_data_t *)luat_heap_malloc(sizeof(airui_nes_data_t));
    if (!data) {
        lv_free(fb);
        lv_obj_delete(game_screen);
        return NULL;
    }
    memset(data, 0, sizeof(airui_nes_data_t));
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

    data->nes_ctx = nes_init();
    if (!data->nes_ctx) {
        LLOGE("NES: nes_init failed");
        _nes_release_data(data);
        lv_obj_delete(game_screen);
        return NULL;
    }
    nes_load_file(data->nes_ctx, rom);

    if (luat_rtos_task_create(&data->nes_thread, 8 * 1024, 27,
                              "airui_nes", _nes_task_entry, data->nes_ctx, 0)) {
        LLOGE("NES: task create failed");
        _nes_release_data(data);
        lv_obj_delete(game_screen);
        return NULL;
    }

    nes_port_render_cb_t cb = {
        .draw  = _nes_draw_cb,
        .frame = _nes_frame_cb,
        .ctx   = data,
    };
    nes_port_set_render_cb(&cb);

    data->initialized = 1;

    airui_component_meta_set_user_data(meta, data, _nes_release_data);

    return game_screen;
}

int airui_nes_destroy(lv_obj_t *nes) {
    if (!nes) return 0;
    lv_obj_delete(nes);
    return 0;
}

int airui_nes_set_key(lv_obj_t *nes, int key, int pressed) {
    airui_component_meta_t *meta = airui_component_meta_get(nes);
    if (!meta || !meta->user_data) return -1;
    airui_nes_data_t *data = (airui_nes_data_t *)meta->user_data;
    if (!data->nes_ctx) return -2;
    switch (key) {
        case NES_KEY_UP:     data->nes_ctx->nes_cpu.joypad.U1  = pressed; break;
        case NES_KEY_DOWN:   data->nes_ctx->nes_cpu.joypad.D1  = pressed; break;
        case NES_KEY_LEFT:   data->nes_ctx->nes_cpu.joypad.L1  = pressed; break;
        case NES_KEY_RIGHT:  data->nes_ctx->nes_cpu.joypad.R1  = pressed; break;
        case NES_KEY_A:      data->nes_ctx->nes_cpu.joypad.A1  = pressed; break;
        case NES_KEY_B:      data->nes_ctx->nes_cpu.joypad.B1  = pressed; break;
        case NES_KEY_START:  data->nes_ctx->nes_cpu.joypad.ST1 = pressed; break;
        case NES_KEY_SELECT: data->nes_ctx->nes_cpu.joypad.SE1 = pressed; break;
        default: return -3;
    }
    return 0;
}

#endif /* LUAT_USE_NES */
#endif /* LUAT_USE_AIRUI */
