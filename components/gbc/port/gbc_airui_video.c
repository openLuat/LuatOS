/**
 * @file gbc_airui_video.c
 * @brief GBC 模拟器 AirUI/LVGL9 视频输出适配器实现
 *
 * 镜像 components/nes/port/nes_airui_video.c：
 *   - 维护一个 160x144 RGB565 framebuffer（按 scale 放大显示）
 *   - LVGL image + 触控 d-pad / AB / SELECT/START / Exit
 *   - 通过 luat_msgbus_put 将 lv_obj_invalidate 从 emulator 线程投递到 Lua 主线程
 *
 * GBC 渲染特性：
 *   - 分辨率：160x144
 *   - 颜色格式：RGB565（GBC_COLOR_DEPTH=16）
 *   - 半帧绘制（GBC_RAM_LACK=1）：gbc_draw() 被调用两次
 *       第一次：y=0..71，第二次：y=72..143
 *   - GBC_COLOR_SWAP=0（PC）：字节序与 LVGL 一致，可直接 memcpy
 *   - GBC_COLOR_SWAP=1（其他平台）：字节序与 LVGL 相反，写入 framebuffer 时需要字节对换
 *
 * @tag LUAT_USE_GBC, LUAT_USE_AIRUI
 */

#include "luat_base.h"

#ifdef LUAT_USE_AIRUI

#include "gbc_airui_video.h"
#include "gbc.h"
#include "gbc_joypad.h"
#include "luat_airui.h"
#include "luat_msgbus.h"
#include <lvgl.h>
#include <string.h>
#include <stdlib.h>

#ifdef __LUATOS__
#include "luat_log.h"
#define LUAT_LOG_TAG "gbc.airui"
#endif

/* ========== 内部按键 ID ========== */

#define GBC_AIR_KEY_UP      1
#define GBC_AIR_KEY_DOWN    2
#define GBC_AIR_KEY_LEFT    3
#define GBC_AIR_KEY_RIGHT   4
#define GBC_AIR_KEY_A       5
#define GBC_AIR_KEY_B       6
#define GBC_AIR_KEY_START   7
#define GBC_AIR_KEY_SELECT  8

/* ========== 按钮尺寸 ========== */

#define BTN_SIZE_A      60
#define BTN_SIZE_B      50
#define BTN_SIZE_FUNC   70

/* ========== 上下文结构 ========== */

struct gbc_airui_video {
    /* LVGL 对象 */
    lv_obj_t *main_container;       /**< 主容器（flex column） */
    lv_obj_t *game_screen;          /**< 游戏画面（lv_image） */
    lv_obj_t *controls_container;   /**< 控制按钮容器 */
    lv_obj_t *title_bar;            /**< 标题栏 */

    /* 帧缓冲：全帧 160x144 RGB565（LVGL 格式，非字节对换） */
    gbc_color_t *framebuffer;
    lv_image_dsc_t img_dsc;         /**< 必须在结构体中，不能是临时变量 */

    /* 布局 */
    int scale;                      /**< 缩放倍数 1-3 */

    /* 状态 */
    int initialized;
    int quit_requested;
    volatile int refresh_pending;   /**< 1=已向 msgbus 投递刷新消息，等待处理 */
};

static gbc_airui_video_t *g_gbc_airui = NULL;

/* 宿主 gbc_t（由 luat_lib_gbc.c 提供） */
extern gbc_t *luat_gbc_get_global_ctx(void);

/* ========== 前向声明 ========== */

static void _set_key_state(int key_id, int pressed);
static void _btn_event_cb(lv_event_t *e);
static void _btn_back_cb(lv_event_t *e);
static void _create_title_bar(gbc_airui_video_t *v);
static void _create_game_screen(gbc_airui_video_t *v);
static void _create_controls(gbc_airui_video_t *v);
static int  _gbc_refresh_handler(lua_State *L, void *ptr);

/* ========== msgbus 刷新 handler（Lua 主任务线程中执行）========== */

static int _gbc_refresh_handler(lua_State *L, void *ptr) {
    (void)L;
    (void)ptr;  /* ptr 可能是已释放的悬空指针（deinit 后的队列残留），
                 * 必须使用全局 g_gbc_airui 而非 ptr 做有效性判断。 */
    gbc_airui_video_t *v = g_gbc_airui;
    if (!v || !v->initialized || !v->game_screen) return 0;
    lv_obj_invalidate(v->game_screen);
    v->refresh_pending = 0;
    return 0;
}

/* ========== 默认配置 ========== */

static const gbc_airui_video_config_t s_default_cfg = {
    .scale         = 1,
    .show_controls = 1,
    .bg_color      = 0x1A1A2E,
    .btn_a_color   = 0xE74C3C,
    .btn_b_color   = 0x3498DB,
};

/* ========== 按键操作 ========== */

static void _set_key_state(int key_id, int pressed) {
    gbc_t *gbc = luat_gbc_get_global_ctx();
    if (!gbc) return;
    gbc_key_t key;
    switch (key_id) {
        case GBC_AIR_KEY_UP:     key = GBC_KEY_UP;     break;
        case GBC_AIR_KEY_DOWN:   key = GBC_KEY_DOWN;   break;
        case GBC_AIR_KEY_LEFT:   key = GBC_KEY_LEFT;   break;
        case GBC_AIR_KEY_RIGHT:  key = GBC_KEY_RIGHT;  break;
        case GBC_AIR_KEY_A:      key = GBC_KEY_A;      break;
        case GBC_AIR_KEY_B:      key = GBC_KEY_B;      break;
        case GBC_AIR_KEY_START:  key = GBC_KEY_START;  break;
        case GBC_AIR_KEY_SELECT: key = GBC_KEY_SELECT; break;
        default: return;
    }
    gbc_joypad_set(gbc, key, (uint8_t)pressed);
}

/* ========== LVGL 回调 ========== */

static void _btn_back_cb(lv_event_t *e) {
    gbc_airui_video_t *v = (gbc_airui_video_t *)lv_event_get_user_data(e);
    if (v) v->quit_requested = 1;
}

static void _btn_event_cb(lv_event_t *e) {
    lv_event_code_t code = lv_event_get_code(e);
    int key_id = (int)(intptr_t)lv_event_get_user_data(e);
    if (code == LV_EVENT_PRESSED) {
        _set_key_state(key_id, 1);
    } else if (code == LV_EVENT_RELEASED) {
        _set_key_state(key_id, 0);
    }
}

/* ========== 界面创建 ========== */

static void _make_dpad_btn(lv_obj_t *parent, lv_align_t align, int key_id) {
    lv_obj_t *btn = lv_btn_create(parent);
    lv_obj_set_size(btn, 46, 46);
    lv_obj_set_style_bg_color(btn, lv_color_hex(0x34495E), 0);
    lv_obj_set_style_radius(btn, 8, 0);
    lv_obj_align(btn, align, 0, 0);
    lv_obj_add_event_cb(btn, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)key_id);
    lv_obj_add_event_cb(btn, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)key_id);
}

static void _create_title_bar(gbc_airui_video_t *v) {
    v->title_bar = lv_obj_create(v->main_container);
    lv_obj_set_size(v->title_bar, LV_PCT(100), 40);
    lv_obj_set_style_bg_color(v->title_bar, lv_color_hex(0x16213E), 0);
    lv_obj_set_style_border_width(v->title_bar, 0, 0);
    lv_obj_set_style_pad_all(v->title_bar, 5, 0);
    lv_obj_clear_flag(v->title_bar, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *title = lv_label_create(v->title_bar);
    lv_label_set_text(title, "LuatOS GBC");
    lv_obj_set_style_text_color(title, lv_color_hex(0xFFFFFF), 0);
    lv_obj_center(title);

    lv_obj_t *btn_back = lv_btn_create(v->title_bar);
    lv_obj_set_size(btn_back, 60, 30);
    lv_obj_align(btn_back, LV_ALIGN_LEFT_MID, 5, 0);
    lv_obj_set_style_bg_color(btn_back, lv_color_hex(0xE74C3C), 0);

    lv_obj_t *lbl = lv_label_create(btn_back);
    lv_label_set_text(lbl, LV_SYMBOL_LEFT " Exit");
    lv_obj_center(lbl);

    lv_obj_add_event_cb(btn_back, _btn_back_cb, LV_EVENT_CLICKED, v);
}

static void _create_game_screen(gbc_airui_video_t *v) {
    size_t buf_size = GBC_AIRUI_WIDTH * GBC_AIRUI_HEIGHT * sizeof(gbc_color_t);
    v->framebuffer = (gbc_color_t *)lv_malloc(buf_size);
    if (!v->framebuffer) {
        LLOGE("GBC AirUI: framebuffer alloc failed");
        return;
    }
    memset(v->framebuffer, 0, buf_size);

    v->game_screen = lv_image_create(v->main_container);

    v->img_dsc = (lv_image_dsc_t){
        .header = {
            .magic  = LV_IMAGE_HEADER_MAGIC,
            .cf     = LV_COLOR_FORMAT_RGB565,
            .w      = GBC_AIRUI_WIDTH,
            .h      = GBC_AIRUI_HEIGHT,
            .stride = GBC_AIRUI_WIDTH * sizeof(gbc_color_t),
            .flags  = 0,
        },
        .data_size = GBC_AIRUI_WIDTH * GBC_AIRUI_HEIGHT * sizeof(gbc_color_t),
        .data      = (const uint8_t *)v->framebuffer,
        .reserved  = NULL,
        .reserved_2 = NULL,
    };
    lv_image_set_src(v->game_screen, &v->img_dsc);

    if (v->scale > 1) {
        lv_image_set_scale(v->game_screen, v->scale * 256);
    }

    lv_obj_set_size(v->game_screen,
                    GBC_AIRUI_WIDTH  * v->scale,
                    GBC_AIRUI_HEIGHT * v->scale);

    lv_obj_set_style_border_width(v->game_screen, 3, 0);
    lv_obj_set_style_border_color(v->game_screen, lv_color_hex(0x0F3460), 0);
    lv_obj_set_style_radius(v->game_screen, 3, 0);
}

static void _create_controls(gbc_airui_video_t *v) {
    /*
     * GB 手柄布局（绝对定位，无 flex，无滚动）：
     *
     *   [dpad 140x140 左侧中部]        [AB 140x140 右侧中部]
     *               [SELECT]  [START]  底部居中
     *
     * 所有容器清除 LV_OBJ_FLAG_SCROLLABLE，防止滚动手势拦截按键事件。
     */
    v->controls_container = lv_obj_create(v->main_container);
    lv_obj_set_size(v->controls_container, LV_PCT(100), 220);
    lv_obj_set_layout(v->controls_container, LV_LAYOUT_NONE);
    lv_obj_clear_flag(v->controls_container, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(v->controls_container, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(v->controls_container, 0, 0);
    lv_obj_set_style_pad_all(v->controls_container, 0, 0);

    /* 十字方向键 */
    lv_obj_t *dpad_area = lv_obj_create(v->controls_container);
    lv_obj_set_size(dpad_area, 140, 140);
    lv_obj_set_layout(dpad_area, LV_LAYOUT_NONE);
    lv_obj_clear_flag(dpad_area, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(dpad_area, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(dpad_area, 0, 0);
    lv_obj_set_style_pad_all(dpad_area, 0, 0);
    lv_obj_align(dpad_area, LV_ALIGN_LEFT_MID, 10, -20);

    _make_dpad_btn(dpad_area, LV_ALIGN_TOP_MID,    GBC_AIR_KEY_UP);
    _make_dpad_btn(dpad_area, LV_ALIGN_BOTTOM_MID, GBC_AIR_KEY_DOWN);
    _make_dpad_btn(dpad_area, LV_ALIGN_LEFT_MID,   GBC_AIR_KEY_LEFT);
    _make_dpad_btn(dpad_area, LV_ALIGN_RIGHT_MID,  GBC_AIR_KEY_RIGHT);

    /* A/B 按钮区 */
    lv_obj_t *ab_area = lv_obj_create(v->controls_container);
    lv_obj_set_size(ab_area, 140, 140);
    lv_obj_set_layout(ab_area, LV_LAYOUT_NONE);
    lv_obj_clear_flag(ab_area, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_opa(ab_area, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(ab_area, 0, 0);
    lv_obj_set_style_pad_all(ab_area, 0, 0);
    lv_obj_align(ab_area, LV_ALIGN_RIGHT_MID, -10, -20);

    /* B 按钮（蓝色，左下） */
    lv_obj_t *btn_b = lv_btn_create(ab_area);
    lv_obj_set_size(btn_b, BTN_SIZE_B, BTN_SIZE_B);
    lv_obj_set_style_bg_color(btn_b, lv_color_hex(0x3498DB), 0);
    lv_obj_set_style_radius(btn_b, LV_RADIUS_CIRCLE, 0);
    lv_obj_align(btn_b, LV_ALIGN_BOTTOM_LEFT, 10, -10);
    lv_obj_t *lbl_b = lv_label_create(btn_b);
    lv_label_set_text(lbl_b, "B");
    lv_obj_set_style_text_color(lbl_b, lv_color_hex(0xFFFFFF), 0);
    lv_obj_center(lbl_b);
    lv_obj_add_event_cb(btn_b, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)GBC_AIR_KEY_B);
    lv_obj_add_event_cb(btn_b, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)GBC_AIR_KEY_B);

    /* A 按钮（红色，右上） */
    lv_obj_t *btn_a = lv_btn_create(ab_area);
    lv_obj_set_size(btn_a, BTN_SIZE_A, BTN_SIZE_A);
    lv_obj_set_style_bg_color(btn_a, lv_color_hex(0xE74C3C), 0);
    lv_obj_set_style_radius(btn_a, LV_RADIUS_CIRCLE, 0);
    lv_obj_align(btn_a, LV_ALIGN_TOP_RIGHT, -10, 10);
    lv_obj_t *lbl_a = lv_label_create(btn_a);
    lv_label_set_text(lbl_a, "A");
    lv_obj_set_style_text_color(lbl_a, lv_color_hex(0xFFFFFF), 0);
    lv_obj_center(lbl_a);
    lv_obj_add_event_cb(btn_a, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)GBC_AIR_KEY_A);
    lv_obj_add_event_cb(btn_a, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)GBC_AIR_KEY_A);

    /* SELECT + START（底部居中） */
    lv_obj_t *btn_sel = lv_btn_create(v->controls_container);
    lv_obj_set_size(btn_sel, 85, 32);
    lv_obj_set_style_bg_color(btn_sel, lv_color_hex(0x95A5A6), 0);
    lv_obj_set_style_radius(btn_sel, 16, 0);
    lv_obj_align(btn_sel, LV_ALIGN_BOTTOM_MID, -55, -8);
    lv_obj_t *lbl_sel = lv_label_create(btn_sel);
    lv_label_set_text(lbl_sel, "SELECT");
    lv_obj_center(lbl_sel);
    lv_obj_add_event_cb(btn_sel, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)GBC_AIR_KEY_SELECT);
    lv_obj_add_event_cb(btn_sel, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)GBC_AIR_KEY_SELECT);

    lv_obj_t *btn_start = lv_btn_create(v->controls_container);
    lv_obj_set_size(btn_start, 85, 32);
    lv_obj_set_style_bg_color(btn_start, lv_color_hex(0x95A5A6), 0);
    lv_obj_set_style_radius(btn_start, 16, 0);
    lv_obj_align(btn_start, LV_ALIGN_BOTTOM_MID, 55, -8);
    lv_obj_t *lbl_start = lv_label_create(btn_start);
    lv_label_set_text(lbl_start, "START");
    lv_obj_center(lbl_start);
    lv_obj_add_event_cb(btn_start, _btn_event_cb, LV_EVENT_PRESSED,  (void *)(intptr_t)GBC_AIR_KEY_START);
    lv_obj_add_event_cb(btn_start, _btn_event_cb, LV_EVENT_RELEASED, (void *)(intptr_t)GBC_AIR_KEY_START);
}

/* ========== 公共 API ========== */

void gbc_airui_video_get_default_config(gbc_airui_video_config_t *config) {
    if (config) memcpy(config, &s_default_cfg, sizeof(gbc_airui_video_config_t));
}

gbc_airui_video_t *gbc_airui_video_init(const gbc_airui_video_config_t *config) {
    if (g_gbc_airui) {
        LLOGW("GBC AirUI already initialized");
        return g_gbc_airui;
    }

    gbc_airui_video_t *v = (gbc_airui_video_t *)lv_malloc(sizeof(gbc_airui_video_t));
    if (!v) {
        LLOGE("GBC AirUI: context alloc failed");
        return NULL;
    }
    memset(v, 0, sizeof(gbc_airui_video_t));

    gbc_airui_video_config_t cfg;
    if (config) {
        memcpy(&cfg, config, sizeof(cfg));
    } else {
        gbc_airui_video_get_default_config(&cfg);
    }
    v->scale = (cfg.scale >= 1 && cfg.scale <= 3) ? cfg.scale : 1;

    /* 自动限制 scale，防止 GBC 画面超出显示器宽高（ThorVG canvas 溢出崩溃） */
    {
        lv_display_t *disp = lv_display_get_default();
        if (disp) {
            int disp_w = lv_display_get_horizontal_resolution(disp);
            int disp_h = lv_display_get_vertical_resolution(disp);
            int avail_h = disp_h - 40 - 220 - 16;
            while (v->scale > 1 &&
                   (GBC_AIRUI_WIDTH  * v->scale > disp_w ||
                    GBC_AIRUI_HEIGHT * v->scale > avail_h)) {
                v->scale--;
            }
            LLOGI("GBC AirUI scale=%d (display %dx%d, avail_h=%d)",
                  v->scale, disp_w, disp_h, avail_h);
        }
    }

    lv_obj_t *screen = lv_screen_active();
    if (!screen) {
        LLOGE("GBC AirUI: no active LVGL screen");
        lv_free(v);
        return NULL;
    }

    v->main_container = lv_obj_create(screen);
    lv_obj_set_size(v->main_container, LV_PCT(100), LV_PCT(100));
    lv_obj_set_layout(v->main_container, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_flow(v->main_container, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(v->main_container, LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_bg_color(v->main_container, lv_color_hex(cfg.bg_color), 0);
    lv_obj_set_style_pad_gap(v->main_container, 8, 0);
    lv_obj_set_style_pad_all(v->main_container, 0, 0);
    lv_obj_set_style_border_width(v->main_container, 0, 0);
    lv_obj_clear_flag(v->main_container, LV_OBJ_FLAG_SCROLLABLE);

    _create_title_bar(v);
    _create_game_screen(v);
    if (cfg.show_controls) {
        _create_controls(v);
    }

    v->initialized    = 1;
    v->quit_requested = 0;
    g_gbc_airui       = v;

    LLOGI("GBC AirUI initialized, scale=%d", v->scale);
    return v;
}

void gbc_airui_video_deinit(gbc_airui_video_t *video) {
    if (!video) video = g_gbc_airui;
    if (!video) return;

    if (video == g_gbc_airui) {
        g_gbc_airui = NULL;
    }
    video->initialized = 0;

    if (video->game_screen) {
        lv_image_set_src(video->game_screen, NULL);
        video->game_screen = NULL;
    }
    if (video->main_container) {
        lv_obj_delete(video->main_container);
        video->main_container = NULL;
    }
    if (video->framebuffer) {
        lv_free(video->framebuffer);
        video->framebuffer = NULL;
    }
    lv_free(video);
    LLOGI("GBC AirUI deinitialized");
}

int gbc_airui_video_draw(gbc_airui_video_t *video,
                         size_t x1, size_t y1,
                         size_t x2, size_t y2,
                         const gbc_color_t *pixels) {
    if (!video) video = g_gbc_airui;
    if (!video || !video->initialized || !video->framebuffer) return -1;
    if (!pixels) return -2;

    if (x1 >= GBC_AIRUI_WIDTH || y1 >= GBC_AIRUI_HEIGHT) return -3;
    if (x2 >= GBC_AIRUI_WIDTH)  x2 = GBC_AIRUI_WIDTH  - 1;
    if (y2 >= GBC_AIRUI_HEIGHT) y2 = GBC_AIRUI_HEIGHT - 1;

    size_t cols = x2 - x1 + 1;
    size_t rows = y2 - y1 + 1;

#if (GBC_COLOR_SWAP == 0)
    for (size_t row = 0; row < rows; row++) {
        gbc_color_t *dst = video->framebuffer + (y1 + row) * GBC_AIRUI_WIDTH + x1;
        const gbc_color_t *src = pixels + row * cols;
        memcpy(dst, src, cols * sizeof(gbc_color_t));
    }
#else
    for (size_t row = 0; row < rows; row++) {
        gbc_color_t *dst = video->framebuffer + (y1 + row) * GBC_AIRUI_WIDTH + x1;
        const gbc_color_t *src = pixels + row * cols;
        for (size_t col = 0; col < cols; col++) {
            uint16_t v = src[col];
            dst[col] = (gbc_color_t)((v >> 8) | (v << 8));
        }
    }
#endif
    return 0;
}

void gbc_airui_video_frame(gbc_airui_video_t *video) {
    if (!video) video = g_gbc_airui;
    if (!video || !video->initialized || !video->game_screen) return;
    if (video->refresh_pending) return;
    video->refresh_pending = 1;
    rtos_msg_t msg = {
        .handler = _gbc_refresh_handler,
        .ptr     = video,
        .arg1    = 0,
        .arg2    = 0,
    };
    if (luat_msgbus_put(&msg, 0) != 0) {
        video->refresh_pending = 0;
    }
}

int gbc_airui_video_quit_requested(gbc_airui_video_t *video) {
    if (!video) video = g_gbc_airui;
    if (!video) return 0;
    return video->quit_requested;
}

int gbc_airui_video_set_scale(gbc_airui_video_t *video, int scale) {
    if (!video) video = g_gbc_airui;
    if (!video || !video->game_screen) return -1;
    if (scale < 1 || scale > 3) return -2;
    video->scale = scale;
    lv_obj_set_size(video->game_screen,
                    GBC_AIRUI_WIDTH  * scale,
                    GBC_AIRUI_HEIGHT * scale);
    lv_image_set_scale(video->game_screen, scale * 256);
    return 0;
}

void gbc_airui_video_show_controls(gbc_airui_video_t *video, int show) {
    if (!video) video = g_gbc_airui;
    if (!video || !video->controls_container) return;
    if (show) {
        lv_obj_clear_flag(video->controls_container, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(video->controls_container, LV_OBJ_FLAG_HIDDEN);
    }
}

gbc_airui_video_t *gbc_airui_video_get_global(void) {
    return g_gbc_airui;
}

#endif /* LUAT_USE_AIRUI */