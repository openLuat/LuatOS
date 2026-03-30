/**
 * @file luat_mgba_airui_video.c
 * @brief LuatOS mGBA AirUI/LVGL9 视频输出适配器
 * 
 * 将mGBA帧缓冲渲染为LVGL画布对象，可嵌入AirUI界面
 * 支持触摸控制按钮、美化界面
 * 
 * @module gba
 * @summary GBA模拟器AirUI视频输出
 * @tag LUAT_USE_MGBA, LUAT_USE_AIRUI
 */

#include "luat_conf_bsp.h"

#ifdef LUAT_USE_MGBA
#ifdef LUAT_USE_AIRUI

#include "luat_mgba.h"
#include "luat_airui.h"
#include <lvgl.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#ifdef __LUATOS__
#include "luat_log.h"
#define LUAT_LOG_TAG "mgba.airui"
#endif

/* ========== 常量定义 ========== */

#define GBA_VIDEO_WIDTH     240
#define GBA_VIDEO_HEIGHT    160
#define GBA_FPS             60
#define FRAME_TIME_MS       (1000 / GBA_FPS)

/* 控制按钮尺寸 */
#define BTN_SIZE_A          60
#define BTN_SIZE_B          50
#define BTN_SIZE_FUNC       70
#define BTN_SIZE_DPAD       40
#define BTN_RADIUS          30

/* ========== AirUI视频上下文结构 ========== */

typedef struct luat_mgba_airui_video {
    /* LVGL对象 */
    lv_obj_t *main_container;       /**< 主容器 */
    lv_obj_t *game_screen;          /**< 游戏画面区域（canvas/image） */
    lv_obj_t *controls_container;   /**< 控制按钮容器 */
    lv_obj_t *title_bar;            /**< 标题栏 */
    
    /* 帧缓冲 */
    uint16_t *framebuffer;          /**< 帧缓冲区 (RGB565格式) */
    lv_draw_buf_t *draw_buf;        /**< LVGL绘制缓冲区 */
    lv_image_dsc_t img_dsc;         /**< 图像描述符（必须在结构体中，不能是静态变量）*/
    
    /* 缩放和布局 */
    int scale;                      /**< 显示缩放倍数 */
    int screen_width;               /**< 屏幕宽度 */
    int screen_height;              /**< 屏幕高度 */
    
    /* 状态 */
    int initialized;                /**< 初始化标志 */
    int quit_requested;             /**< 退出请求 */
    
    /* 按键状态 */
    uint32_t current_keys;          /**< 当前按键状态 */
} luat_mgba_airui_video_t;

/* 全局上下文 */
static luat_mgba_airui_video_t *g_airui_video = NULL;

/* 外部引用（来自luat_lib_gba.c）- 使用函数访问 */
extern luat_mgba_t* luat_mgba_get_global_ctx(void);

/* ========== 前向声明 ========== */

static luat_mgba_t* _get_gba_ctx(void);
static void _set_key_state(int key, int pressed);
static void btn_back_cb(lv_event_t *e);
static void _btn_event_cb(lv_event_t *e);
static void _dpad_event_cb(lv_event_t *e);
static void _create_title_bar(luat_mgba_airui_video_t *video);
static void _create_game_screen(luat_mgba_airui_video_t *video);
static void _create_control_buttons(luat_mgba_airui_video_t *video);

/* ========== 默认配置 ========== */

static const luat_mgba_airui_video_config_t default_config = {
    .scale = 2,
    .show_controls = 1,
    .bg_color = 0x2C3E50,
    .btn_a_color = 0xE74C3C,
    .btn_b_color = 0x3498DB,
};

/* ========== 辅助函数 ========== */

/**
 * @brief 获取mGBA上下文
 */
static luat_mgba_t* _get_gba_ctx(void) {
    return luat_mgba_get_global_ctx();
}

/**
 * @brief 设置按键状态
 */
static void _set_key_state(int key, int pressed) {
    if (!_get_gba_ctx()) return;
    
    if (g_airui_video) {
        if (pressed) {
            g_airui_video->current_keys |= key;
        } else {
            g_airui_video->current_keys &= ~key;
        }
    }
    
    luat_mgba_set_key(_get_gba_ctx(), key, pressed);
}

/**
 * @brief 模拟按键按下然后释放（点击效果）
 */
static void _trigger_key(int key) {
    _set_key_state(key, 1);
    
    /* 使用LuatOS定时器延迟释放 */
    #ifdef __LUATOS__
    /* 100ms后释放 */
    extern int luat_timer_start(int timer_id, int timeout);
    /* 注意：实际实现需要异步处理，这里简化处理 */
    #endif
}

/* ========== 控件创建 ========== */

/**
 * @brief 创建标题栏
 */
static void _create_title_bar(luat_mgba_airui_video_t *video) {
    video->title_bar = lv_obj_create(video->main_container);
    lv_obj_set_size(video->title_bar, LV_PCT(100), 40);
    lv_obj_set_style_bg_color(video->title_bar, lv_color_hex(0x2C3E50), 0);
    lv_obj_set_style_border_width(video->title_bar, 0, 0);
    lv_obj_set_style_pad_all(video->title_bar, 5, 0);
    
    /* 标题标签 - 使用默认字体 */
    lv_obj_t *title = lv_label_create(video->title_bar);
    lv_label_set_text(title, "LuatOS GBA");
    lv_obj_set_style_text_color(title, lv_color_hex(0xFFFFFF), 0);
    /* lv_obj_set_style_text_font(title, &lv_font_montserrat_16, 0); */
    lv_obj_center(title);
    
    /* 返回按钮 */
    lv_obj_t *btn_back = lv_btn_create(video->title_bar);
    lv_obj_set_size(btn_back, 60, 30);
    lv_obj_align(btn_back, LV_ALIGN_LEFT_MID, 5, 0);
    lv_obj_set_style_bg_color(btn_back, lv_color_hex(0xE74C3C), 0);
    
    lv_obj_t *lbl_back = lv_label_create(btn_back);
    lv_label_set_text(lbl_back, LV_SYMBOL_LEFT " Exit");
    lv_obj_center(lbl_back);
    
    /* 退出回调 */
    lv_obj_add_event_cb(btn_back, btn_back_cb, LV_EVENT_CLICKED, video);
}

/**
 * @brief 返回按钮回调
 */
static void btn_back_cb(lv_event_t *e) {
    luat_mgba_airui_video_t *video = lv_event_get_user_data(e);
    if (video) {
        video->quit_requested = 1;
    }
}

/**
 * @brief 创建游戏画面区域
 */
static void _create_game_screen(luat_mgba_airui_video_t *video) {
    /* 计算显示尺寸 */
    video->screen_width = GBA_VIDEO_WIDTH * video->scale;
    video->screen_height = GBA_VIDEO_HEIGHT * video->scale;
    
    /* 分配帧缓冲区 - 使用 RGB565 格式 (16位 = 2字节/像素) */
    size_t buf_size = GBA_VIDEO_WIDTH * GBA_VIDEO_HEIGHT * sizeof(uint16_t);
    video->framebuffer = lv_malloc(buf_size);
    if (!video->framebuffer) {
        LLOGE("Failed to allocate framebuffer");
        return;
    }
    memset(video->framebuffer, 0, buf_size);
    
    /* 创建绘制缓冲区 - 使用 RGB565 */
    video->draw_buf = lv_draw_buf_create(GBA_VIDEO_WIDTH, GBA_VIDEO_HEIGHT, 
                                          LV_COLOR_FORMAT_RGB565, 0);
    if (!video->draw_buf) {
        LLOGE("Failed to create draw buffer");
        lv_free(video->framebuffer);
        video->framebuffer = NULL;
        return;
    }
    
    /* 创建图像对象（比canvas更高效） */
    video->game_screen = lv_image_create(video->main_container);
    lv_obj_set_size(video->game_screen, video->screen_width, video->screen_height);
    
    /* 设置图像源 - 使用 RGB565 格式 */
    video->img_dsc = (lv_image_dsc_t){
        .header = {
            .magic = LV_IMAGE_HEADER_MAGIC,
            .cf = LV_COLOR_FORMAT_RGB565,
            .w = GBA_VIDEO_WIDTH,
            .h = GBA_VIDEO_HEIGHT,
            .stride = GBA_VIDEO_WIDTH * sizeof(uint16_t),  /* 480字节/行 */
            .flags = 0,
        },
        .data_size = GBA_VIDEO_WIDTH * GBA_VIDEO_HEIGHT * sizeof(uint16_t),  /* 76800字节 */
        .data = (const uint8_t *)video->framebuffer,
        .reserved = NULL,
        .reserved_2 = NULL,
    };
    lv_image_set_src(video->game_screen, &video->img_dsc);
    
    /* 设置缩放 */
    if (video->scale > 1) {
        lv_image_set_scale(video->game_screen, video->scale * 256);  /* LVGL scale: 256 = 1x */
    }
    
    /* 添加边框 */
    lv_obj_set_style_border_width(video->game_screen, 4, 0);
    lv_obj_set_style_border_color(video->game_screen, lv_color_hex(0x1A252F), 0);
    lv_obj_set_style_radius(video->game_screen, 4, 0);
    lv_obj_set_style_clip_corner(video->game_screen, true, 0);
}

/**
 * @brief 创建控制按钮
 */
static void _create_control_buttons(luat_mgba_airui_video_t *video) {
    video->controls_container = lv_obj_create(video->main_container);
    lv_obj_set_size(video->controls_container, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(video->controls_container, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(video->controls_container, LV_FLEX_ALIGN_SPACE_AROUND,
                          LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_gap(video->controls_container, 10, 0);
    lv_obj_set_style_bg_opa(video->controls_container, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(video->controls_container, 0, 0);
    
    /* ===== 方向键区域 ===== */
    lv_obj_t *dpad_area = lv_obj_create(video->controls_container);
    lv_obj_set_size(dpad_area, 140, 140);
    lv_obj_set_style_bg_opa(dpad_area, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(dpad_area, 0, 0);
    
    /* 方向键矩阵 */
    static const char *dpad_map[] = {"", "▲", "", "\n", "◀", "", "▶", "\n", "", "▼", "", ""};
    lv_obj_t *dpad = lv_btnmatrix_create(dpad_area);
    lv_btnmatrix_set_map(dpad, dpad_map);
    lv_obj_set_size(dpad, 120, 120);
    lv_obj_center(dpad);
    
    /* 设置按钮样式 */
    lv_obj_set_style_bg_color(dpad, lv_color_hex(0x34495E), LV_PART_ITEMS);
    lv_obj_set_style_bg_opa(dpad, LV_OPA_80, LV_PART_ITEMS);
    lv_obj_set_style_text_color(dpad, lv_color_hex(0xFFFFFF), LV_PART_ITEMS);
    
    lv_obj_add_event_cb(dpad, _dpad_event_cb, LV_EVENT_VALUE_CHANGED, NULL);
    
    /* ===== AB按钮区域 ===== */
    lv_obj_t *ab_area = lv_obj_create(video->controls_container);
    lv_obj_set_size(ab_area, 140, 140);
    lv_obj_set_flex_flow(ab_area, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(ab_area, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_bg_opa(ab_area, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(ab_area, 0, 0);
    
    /* B按钮（蓝色，略小，在左下） */
    lv_obj_t *btn_b = lv_btn_create(ab_area);
    lv_obj_set_size(btn_b, BTN_SIZE_B, BTN_SIZE_B);
    lv_obj_set_style_bg_color(btn_b, lv_color_hex(0x3498DB), 0);
    lv_obj_set_style_radius(btn_b, LV_RADIUS_CIRCLE, 0);
    lv_obj_align(btn_b, LV_ALIGN_BOTTOM_LEFT, 10, -10);
    
    lv_obj_t *lbl_b = lv_label_create(btn_b);
    lv_label_set_text(lbl_b, "B");
    /* lv_obj_set_style_text_font(lbl_b, &lv_font_montserrat_20, 0); */
    lv_obj_center(lbl_b);
    
    lv_obj_add_event_cb(btn_b, _btn_event_cb, LV_EVENT_PRESSED, (void *)LUAT_MGBA_KEY_B);
    lv_obj_add_event_cb(btn_b, _btn_event_cb, LV_EVENT_RELEASED, (void *)LUAT_MGBA_KEY_B);
    
    /* A按钮（红色，略大，在右上） */
    lv_obj_t *btn_a = lv_btn_create(ab_area);
    lv_obj_set_size(btn_a, BTN_SIZE_A, BTN_SIZE_A);
    lv_obj_set_style_bg_color(btn_a, lv_color_hex(0xE74C3C), 0);
    lv_obj_set_style_radius(btn_a, LV_RADIUS_CIRCLE, 0);
    lv_obj_align(btn_a, LV_ALIGN_TOP_RIGHT, -10, 10);
    
    lv_obj_t *lbl_a = lv_label_create(btn_a);
    lv_label_set_text(lbl_a, "A");
    /* lv_obj_set_style_text_font(lbl_a, &lv_font_montserrat_24, 0); */
    lv_obj_center(lbl_a);
    
    lv_obj_add_event_cb(btn_a, _btn_event_cb, LV_EVENT_PRESSED, (void *)LUAT_MGBA_KEY_A);
    lv_obj_add_event_cb(btn_a, _btn_event_cb, LV_EVENT_RELEASED, (void *)LUAT_MGBA_KEY_A);
    
    /* ===== 功能按钮区域 ===== */
    lv_obj_t *func_area = lv_obj_create(video->controls_container);
    lv_obj_set_size(func_area, 100, 140);
    lv_obj_set_flex_flow(func_area, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(func_area, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_gap(func_area, 10, 0);
    lv_obj_set_style_bg_opa(func_area, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(func_area, 0, 0);
    
    /* Start按钮 */
    lv_obj_t *btn_start = lv_btn_create(func_area);
    lv_obj_set_size(btn_start, BTN_SIZE_FUNC, 35);
    lv_obj_set_style_bg_color(btn_start, lv_color_hex(0x95A5A6), 0);
    lv_obj_set_style_radius(btn_start, 17, 0);
    
    lv_obj_t *lbl_start = lv_label_create(btn_start);
    lv_label_set_text(lbl_start, "START");
    /* lv_obj_set_style_text_font(lbl_start, &lv_font_montserrat_12, 0); */
    lv_obj_center(lbl_start);
    
    lv_obj_add_event_cb(btn_start, _btn_event_cb, LV_EVENT_PRESSED, (void *)LUAT_MGBA_KEY_START);
    lv_obj_add_event_cb(btn_start, _btn_event_cb, LV_EVENT_RELEASED, (void *)LUAT_MGBA_KEY_START);
    
    /* Select按钮 */
    lv_obj_t *btn_select = lv_btn_create(func_area);
    lv_obj_set_size(btn_select, BTN_SIZE_FUNC, 35);
    lv_obj_set_style_bg_color(btn_select, lv_color_hex(0x95A5A6), 0);
    lv_obj_set_style_radius(btn_select, 17, 0);
    
    lv_obj_t *lbl_select = lv_label_create(btn_select);
    lv_label_set_text(lbl_select, "SELECT");
    /* lv_obj_set_style_text_font(lbl_select, &lv_font_montserrat_12, 0); */
    lv_obj_center(lbl_select);
    
    lv_obj_add_event_cb(btn_select, _btn_event_cb, LV_EVENT_PRESSED, (void *)LUAT_MGBA_KEY_SELECT);
    lv_obj_add_event_cb(btn_select, _btn_event_cb, LV_EVENT_RELEASED, (void *)LUAT_MGBA_KEY_SELECT);
}

/**
 * @brief 按钮事件回调
 */
static void _btn_event_cb(lv_event_t *e) {
    lv_event_code_t code = lv_event_get_code(e);
    int key = (int)(intptr_t)lv_event_get_user_data(e);
    
    if (code == LV_EVENT_PRESSED) {
        _set_key_state(key, 1);
    } else if (code == LV_EVENT_RELEASED) {
        _set_key_state(key, 0);
    }
}

/**
 * @brief 方向键事件回调
 */
static void _dpad_event_cb(lv_event_t *e) {
    lv_obj_t *obj = lv_event_get_target(e);
    uint32_t id = lv_btnmatrix_get_selected_btn(obj);
    const char *txt = lv_btnmatrix_get_btn_text(obj, id);
    
    if (!txt) return;
    
    /* 先释放所有方向键 */
    _set_key_state(LUAT_MGBA_KEY_UP, 0);
    _set_key_state(LUAT_MGBA_KEY_DOWN, 0);
    _set_key_state(LUAT_MGBA_KEY_LEFT, 0);
    _set_key_state(LUAT_MGBA_KEY_RIGHT, 0);
    
    /* 根据文本设置对应方向键 */
    if (strcmp(txt, "▲") == 0) {
        _set_key_state(LUAT_MGBA_KEY_UP, 1);
    } else if (strcmp(txt, "▼") == 0) {
        _set_key_state(LUAT_MGBA_KEY_DOWN, 1);
    } else if (strcmp(txt, "◀") == 0) {
        _set_key_state(LUAT_MGBA_KEY_LEFT, 1);
    } else if (strcmp(txt, "▶") == 0) {
        _set_key_state(LUAT_MGBA_KEY_RIGHT, 1);
    }
}

/* ========== 公共API ========== */

/**
 * @brief 获取默认AirUI视频配置
 */
void luat_mgba_airui_video_get_default_config(luat_mgba_airui_video_config_t *config) {
    if (config) {
        memcpy(config, &default_config, sizeof(luat_mgba_airui_video_config_t));
    }
}

/**
 * @brief 初始化AirUI视频输出
 */
luat_mgba_airui_video_t* luat_mgba_airui_video_init(const luat_mgba_airui_video_config_t *config) {
    /* 检查是否已初始化 */
    if (g_airui_video) {
        LLOGW("AirUI video already initialized");
        return g_airui_video;
    }
    
    /* 分配上下文 */
    g_airui_video = lv_malloc(sizeof(luat_mgba_airui_video_t));
    if (!g_airui_video) {
        LLOGE("Failed to allocate video context");
        return NULL;
    }
    memset(g_airui_video, 0, sizeof(luat_mgba_airui_video_t));
    
    /* 应用配置 */
    luat_mgba_airui_video_config_t cfg;
    if (config) {
        memcpy(&cfg, config, sizeof(luat_mgba_airui_video_config_t));
    } else {
        luat_mgba_airui_video_get_default_config(&cfg);
    }
    
    g_airui_video->scale = cfg.scale;
    if (g_airui_video->scale < 1) g_airui_video->scale = 1;
    if (g_airui_video->scale > 4) g_airui_video->scale = 4;
    
    /* 获取活动屏幕 */
    lv_obj_t *screen = lv_screen_active();
    if (!screen) {
        LLOGE("No active LVGL screen");
        lv_free(g_airui_video);
        g_airui_video = NULL;
        return NULL;
    }
    
    /* 创建主容器 */
    g_airui_video->main_container = lv_obj_create(screen);
    lv_obj_set_size(g_airui_video->main_container, LV_PCT(100), LV_PCT(100));
    lv_obj_set_layout(g_airui_video->main_container, LV_LAYOUT_FLEX);
    lv_obj_set_flex_flow(g_airui_video->main_container, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(g_airui_video->main_container, LV_FLEX_ALIGN_START,
                          LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_bg_color(g_airui_video->main_container, lv_color_hex(cfg.bg_color), 0);
    lv_obj_set_style_pad_gap(g_airui_video->main_container, 10, 0);
    
    /* 创建标题栏 */
    _create_title_bar(g_airui_video);
    
    /* 创建游戏画面 */
    _create_game_screen(g_airui_video);
    
    /* 创建控制按钮 */
    if (cfg.show_controls) {
        _create_control_buttons(g_airui_video);
    }
    
    g_airui_video->initialized = 1;
    g_airui_video->quit_requested = 0;
    
    LLOGI("AirUI video initialized, scale=%d", g_airui_video->scale);
    
    return g_airui_video;
}

/**
 * @brief 销毁AirUI视频输出
 */
void luat_mgba_airui_video_deinit(luat_mgba_airui_video_t *video) {
    if (!video && g_airui_video) {
        video = g_airui_video;
    }
    
    if (!video) return;
    
    /* 释放帧缓冲区 */
    if (video->framebuffer) {
        lv_free(video->framebuffer);
        video->framebuffer = NULL;
    }
    
    /* 释放绘制缓冲区 */
    if (video->draw_buf) {
        lv_draw_buf_destroy(video->draw_buf);
        video->draw_buf = NULL;
    }
    
    /* 删除主容器（会级联删除所有子对象） */
    if (video->main_container) {
        lv_obj_delete(video->main_container);
        video->main_container = NULL;
    }
    
    if (video == g_airui_video) {
        g_airui_video = NULL;
    }
    
    LLOGI("AirUI video deinitialized");
}

/**
 * @brief 显示帧缓冲到屏幕
 */
int luat_mgba_airui_video_present(luat_mgba_airui_video_t *video, 
                                   const luat_mgba_color_t *fb,
                                   uint32_t width, uint32_t height) {
    if (!video && g_airui_video) {
        video = g_airui_video;
    }
    
    if (!video || !video->initialized || !video->game_screen) {
        return -1;
    }
    
    if (!fb || width != GBA_VIDEO_WIDTH || height != GBA_VIDEO_HEIGHT) {
        return -2;
    }
    
    /* mGBA 输出 ABGR8888 (小端内存: [R][G][B][A])
     * 需要转换为 RGB565 (小端内存: [低字节][高字节])
     * RGB565 格式: RRRRRGGGGGGBBBBB
     */
    const uint32_t *src = (const uint32_t *)fb;
    uint16_t *dst = video->framebuffer;
    
    for (int i = 0; i < GBA_VIDEO_WIDTH * GBA_VIDEO_HEIGHT; i++) {
        uint32_t pixel = src[i];
        /* 提取 ABGR 各通道 (小端: [R][G][B][A]) */
        uint8_t r8 = pixel & 0xFF;           /* 红色 */
        uint8_t g8 = (pixel >> 8) & 0xFF;    /* 绿色 */
        uint8_t b8 = (pixel >> 16) & 0xFF;   /* 蓝色 */
        
        /* 转换为 RGB565: R5G6B5 */
        uint8_t r5 = r8 >> 3;   /* 5位红色 */
        uint8_t g6 = g8 >> 2;   /* 6位绿色 */
        uint8_t b5 = b8 >> 3;   /* 5位蓝色 */
        
        /* 打包成 uint16_t (小端系统会自动处理字节序) */
        dst[i] = (r5 << 11) | (g6 << 5) | b5;
    }
    
    /* 标记图像为脏，触发重绘 */
    lv_obj_invalidate(video->game_screen);
    
    return 0;
}

/**
 * @brief 检查是否有退出请求
 */
int luat_mgba_airui_video_quit_requested(luat_mgba_airui_video_t *video) {
    if (!video && g_airui_video) {
        video = g_airui_video;
    }
    
    if (!video) return 0;
    
    return video->quit_requested;
}

/**
 * @brief 设置显示缩放倍数
 */
int luat_mgba_airui_video_set_scale(luat_mgba_airui_video_t *video, int scale) {
    if (!video && g_airui_video) {
        video = g_airui_video;
    }
    
    if (!video || !video->game_screen) return -1;
    if (scale < 1 || scale > 4) return -2;
    
    video->scale = scale;
    video->screen_width = GBA_VIDEO_WIDTH * scale;
    video->screen_height = GBA_VIDEO_HEIGHT * scale;
    
    lv_obj_set_size(video->game_screen, video->screen_width, video->screen_height);
    lv_image_set_scale(video->game_screen, scale * 256);
    
    return 0;
}

/**
 * @brief 显示/隐藏控制按钮
 */
void luat_mgba_airui_video_show_controls(luat_mgba_airui_video_t *video, int show) {
    if (!video && g_airui_video) {
        video = g_airui_video;
    }
    
    if (!video || !video->controls_container) return;
    
    if (show) {
        lv_obj_clear_flag(video->controls_container, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(video->controls_container, LV_OBJ_FLAG_HIDDEN);
    }
}

/**
 * @brief 初始化AirUI视频输出（扩展版，支持嵌入外部容器）
 */
luat_mgba_airui_video_t* luat_mgba_airui_video_init_ex(const luat_mgba_airui_video_config_ex_t *config) {
    /* 检查是否已初始化 */
    if (g_airui_video) {
        LLOGW("AirUI video already initialized");
        return g_airui_video;
    }
    
    /* 分配上下文 */
    g_airui_video = lv_malloc(sizeof(luat_mgba_airui_video_t));
    if (!g_airui_video) {
        LLOGE("Failed to allocate video context");
        return NULL;
    }
    memset(g_airui_video, 0, sizeof(luat_mgba_airui_video_t));
    
    /* 应用配置 */
    luat_mgba_airui_video_config_ex_t cfg;
    if (config) {
        memcpy(&cfg, config, sizeof(luat_mgba_airui_video_config_ex_t));
    } else {
        memset(&cfg, 0, sizeof(cfg));
        cfg.scale = 2;
        cfg.show_controls = 1;
        cfg.bg_color = 0x2C3E50;
    }
    
    g_airui_video->scale = cfg.scale;
    if (g_airui_video->scale < 1) g_airui_video->scale = 1;
    if (g_airui_video->scale > 4) g_airui_video->scale = 4;
    
    /* 确定父容器 */
    lv_obj_t *parent = NULL;
    if (cfg.parent_obj) {
        /* 使用外部提供的父容器 */
        parent = (lv_obj_t*)cfg.parent_obj;
    } else {
        /* 获取活动屏幕 */
        parent = lv_screen_active();
    }
    
    if (!parent) {
        LLOGE("No parent object available");
        lv_free(g_airui_video);
        g_airui_video = NULL;
        return NULL;
    }
    
    /* 创建主容器 */
    g_airui_video->main_container = lv_obj_create(parent);
    
    /* 设置位置和大小 */
    if (cfg.parent_obj) {
        /* 嵌入模式：使用指定位置和大小，不使用Flex布局 */
        lv_obj_set_pos(g_airui_video->main_container, cfg.x, cfg.y);
        if (cfg.width > 0 && cfg.height > 0) {
            lv_obj_set_size(g_airui_video->main_container, cfg.width, cfg.height);
        } else {
            /* 默认大小 */
            lv_obj_set_size(g_airui_video->main_container, 
                GBA_VIDEO_WIDTH * g_airui_video->scale + 40, 
                GBA_VIDEO_HEIGHT * g_airui_video->scale + 200);
        }
        /* 嵌入模式：不使用Flex布局，手动定位子对象 */
        lv_obj_set_style_bg_opa(g_airui_video->main_container, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(g_airui_video->main_container, 0, 0);
        lv_obj_clear_flag(g_airui_video->main_container, LV_OBJ_FLAG_SCROLLABLE);
    } else {
        /* 全屏模式 */
        lv_obj_set_size(g_airui_video->main_container, LV_PCT(100), LV_PCT(100));
        lv_obj_set_layout(g_airui_video->main_container, LV_LAYOUT_FLEX);
        lv_obj_set_flex_flow(g_airui_video->main_container, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_flex_align(g_airui_video->main_container, LV_FLEX_ALIGN_START,
                              LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_bg_color(g_airui_video->main_container, lv_color_hex(cfg.bg_color), 0);
        lv_obj_set_style_pad_gap(g_airui_video->main_container, 10, 0);
    }
    
    /* 创建标题栏（仅全屏模式） */
    if (!cfg.parent_obj) {
        _create_title_bar(g_airui_video);
    }
    
    /* 创建游戏画面 */
    _create_game_screen(g_airui_video);
    
    /* 嵌入模式：手动定位游戏画面到中心 */
    if (cfg.parent_obj && g_airui_video->game_screen) {
        lv_obj_center(g_airui_video->game_screen);
    }
    
    /* 创建控制按钮 */
    if (cfg.show_controls) {
        _create_control_buttons(g_airui_video);
    }
    
    g_airui_video->initialized = 1;
    g_airui_video->quit_requested = 0;
    
    LLOGI("AirUI video initialized (ex), scale=%d", g_airui_video->scale);
    
    return g_airui_video;
}

#endif /* LUAT_USE_AIRUI */
#endif /* LUAT_USE_MGBA */
