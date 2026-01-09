/**
 * @file luat_easylvgl.h
 * @summary EasyLVGL 主头文件：上下文、平台操作接口、错误码
 * @responsible EasyLVGL 核心数据结构定义与平台抽象接口
 */

#ifndef EASYLVGL_H
#define EASYLVGL_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "lvgl9/lvgl.h"

/*********************
 *      DEFINES
 *********************/

/** 回调函数类型最大数量 */
#define EASYLVGL_CALLBACK_MAX 16

/** 颜色格式常量（用于 Lua API，直接使用 LVGL 常量值） */
#define EASYLVGL_COLOR_FORMAT_RGB565    LV_COLOR_FORMAT_RGB565     /**< RGB565 格式，16位，适用于嵌入式设备 */
#define EASYLVGL_COLOR_FORMAT_ARGB8888  LV_COLOR_FORMAT_ARGB8888   /**< ARGB8888 格式，32位，默认格式 */

/**********************
 *      TYPEDEFS
 *********************/

/** 前向声明 */
typedef struct easylvgl_ctx easylvgl_ctx_t;
typedef struct easylvgl_buffer easylvgl_buffer_t;
typedef struct easylvgl_component_meta easylvgl_component_meta_t;

/**
 * 缓冲模式
 */
typedef enum {
    EASYLVGL_BUFFER_MODE_SINGLE,        /**< 单缓冲 */
    EASYLVGL_BUFFER_MODE_DOUBLE,        /**< 双缓冲 */
    EASYLVGL_BUFFER_MODE_LCD_SHARED,    /**< LCD 共享缓冲 */
    EASYLVGL_BUFFER_MODE_EXTERNAL       /**< 外部缓冲 */
} easylvgl_buffer_mode_t;

/**
 * 缓冲所有权
 */
typedef enum {
    EASYLVGL_BUFFER_OWNER_SYSTEM,       /**< 系统 heap */
    EASYLVGL_BUFFER_OWNER_LUA           /**< Lua heap */
} easylvgl_buffer_owner_t;

/**
 * 错误码
 */
typedef enum {
    EASYLVGL_OK = 0,
    EASYLVGL_ERR_INVALID_PARAM = -1,
    EASYLVGL_ERR_NO_MEM = -2,
    EASYLVGL_ERR_INIT_FAILED = -3,
    EASYLVGL_ERR_NOT_INITIALIZED = -4,
    EASYLVGL_ERR_PLATFORM_ERROR = -5,
    EASYLVGL_ERR_NOT_SUPPORTED = -6
} easylvgl_err_t;

/**
 * 显示驱动操作接口
 */
typedef struct {
    int (*init)(easylvgl_ctx_t *ctx, uint16_t w, uint16_t h, lv_color_format_t fmt);
    void (*flush)(easylvgl_ctx_t *ctx, const lv_area_t *area, const uint8_t *px_map);
    void (*wait_vsync)(easylvgl_ctx_t *ctx);
    void (*deinit)(easylvgl_ctx_t *ctx);
} easylvgl_display_ops_t;

/**
 * 文件系统操作接口
 */
typedef struct {
    void *(*open)(easylvgl_ctx_t *ctx, const char *path, lv_fs_mode_t mode);
    lv_fs_res_t (*read)(easylvgl_ctx_t *ctx, void *file, void *buf, uint32_t len, uint32_t *read);
    lv_fs_res_t (*write)(easylvgl_ctx_t *ctx, void *file, const void *buf, uint32_t len, uint32_t *written);
    lv_fs_res_t (*seek)(easylvgl_ctx_t *ctx, void *file, uint32_t pos, lv_fs_whence_t whence);
    lv_fs_res_t (*tell)(easylvgl_ctx_t *ctx, void *file, uint32_t *pos);
    lv_fs_res_t (*close)(easylvgl_ctx_t *ctx, void *file);
} easylvgl_fs_ops_t;

/**
 * 输入设备操作接口
 */
typedef struct {
    bool (*read_pointer)(easylvgl_ctx_t *ctx, lv_indev_data_t *data);
    bool (*read_keypad)(easylvgl_ctx_t *ctx, lv_indev_data_t *data);
    void (*calibration)(easylvgl_ctx_t *ctx, int16_t *x, int16_t *y);
} easylvgl_input_ops_t;

/**
 * 时基操作接口
 */
typedef struct {
    uint32_t (*get_tick)(easylvgl_ctx_t *ctx);
    void (*delay_ms)(easylvgl_ctx_t *ctx, uint32_t ms);
} easylvgl_time_ops_t;

/**
 * 日志操作接口（可选）
 */
typedef struct {
    void (*log)(easylvgl_ctx_t *ctx, lv_log_level_t level, const char *fmt, ...);
} easylvgl_log_ops_t;

/**
 * 平台操作接口集合
 */
typedef struct {
    const easylvgl_display_ops_t *display_ops;
    const easylvgl_fs_ops_t *fs_ops;
    const easylvgl_input_ops_t *input_ops;
    const easylvgl_time_ops_t *time_ops;
    const easylvgl_log_ops_t *log_ops;  /**< 可选 */
} easylvgl_platform_ops_t;

/**
 * EasyLVGL 上下文对象
 * 统一管理所有运行态数据，替代全局变量
 */
struct easylvgl_ctx {
    // LVGL 驱动实例
    lv_display_t *display;          /**< 显示设备 */
    lv_indev_t *indev;               /**< 输入设备 */
    lv_fs_drv_t fs_drv;          /**< 文件系统驱动（和 /） */
    
    // 缓冲管理
    easylvgl_buffer_t *buffer;       /**< 缓冲管理器 */
    
    // 平台操作接口
    const easylvgl_platform_ops_t *ops;  /**< 平台驱动 ops */
    
    // Lua 状态
    void *L;                         /**< Lua 状态指针（lua_State*，避免直接依赖） */
    
    // 配置标志
    uint8_t flags;                   /**< 配置标志位 */
    uint16_t width;                 /**< 屏幕宽度 */
    uint16_t height;                 /**< 屏幕高度 */
    
    // 内部状态
    lv_timer_t *tick_timer;          /**< Tick 定时器（可选） */
    void *platform_data;             /**< 平台私有数据 */
    lv_obj_t *focused_textarea;      /**< 当前聚焦的 textarea，供系统键盘使用 */
    bool system_keyboard_enabled;    /**< 是否允许系统键盘输入 */
    int32_t system_keyboard_preedit_pos; /**< 上一次插入的 SDL 预编辑文本起始位置 */
    int32_t system_keyboard_preedit_len; /**< 上一次插入的 SDL 预编辑文本长度（字符数） */
    bool system_keyboard_preedit_active; /**< 当前是否处于 SDL 预编辑（拼音）阶段 */
};

/**********************
 * GLOBAL PROTOTYPES
 **********************/

/**
 * 创建 EasyLVGL 上下文对象
 * @param ctx 上下文指针（输出）
 * @param ops 平台操作接口
 * @return 0 成功，<0 失败
 * @pre-condition ops 必须非空
 * @post-condition ctx 已初始化，可调用 easylvgl_init
 */
int easylvgl_ctx_create(easylvgl_ctx_t *ctx, const easylvgl_platform_ops_t *ops);

/**
 * 初始化 EasyLVGL
 * @param ctx 上下文指针
 * @param width 屏幕宽度
 * @param height 屏幕高度
 * @param color_format 颜色格式
 * @return 0 成功，<0 失败
 * @pre-condition ctx 已通过 easylvgl_ctx_create 创建
 * @post-condition LVGL 已初始化，驱动已注册，缓冲已申请
 */
int easylvgl_init(easylvgl_ctx_t *ctx, uint16_t width, uint16_t height, lv_color_format_t color_format);

/**
 * 反初始化 EasyLVGL
 * @param ctx 上下文指针
 * @pre-condition ctx 已初始化
 * @post-condition 所有资源已释放
 */
void easylvgl_deinit(easylvgl_ctx_t *ctx);

/**
 * 错误码转字符串
 * @param err 错误码
 * @return 错误描述字符串
 */
const char *easylvgl_strerror(easylvgl_err_t err);

/**
 * 创建缓冲管理器
 * @return 缓冲管理器指针，失败返回 NULL
 */
easylvgl_buffer_t *easylvgl_buffer_create(void);

/**
 * 分配缓冲
 * @param ctx 上下文指针
 * @param size 缓冲大小（字节）
 * @param owner 缓冲所有权
 * @return 缓冲指针，失败返回 NULL
 */
void *easylvgl_buffer_alloc(easylvgl_ctx_t *ctx, size_t size, easylvgl_buffer_owner_t owner);

/**
 * 释放单个缓冲
 * @param ctx 上下文指针
 * @param buffer 缓冲指针
 */
void easylvgl_buffer_free(easylvgl_ctx_t *ctx, void *buffer);

/**
 * 释放所有缓冲
 * @param ctx 上下文指针
 * @pre-condition ctx 必须非空
 * @post-condition 所有缓冲已按所有权释放
 */
void easylvgl_buffer_free_all(easylvgl_ctx_t *ctx);

/**
 * 创建 HZFont（TTF）字体，用于 EasyLVGL
 * @param path TTF 文件路径，为 NULL 则使用内置字库
 * @param size 字号
 * @param cache_size 缓存容量
 * @param antialias 抗锯齿等级
 * @return lv_font_t 字体对象，失败返回 NULL
 */
lv_font_t * easylvgl_font_hzfont_create(const char * path, uint16_t size, uint32_t cache_size, int antialias);

/**
 * 设置显示缓冲
 * @param ctx 上下文指针
 * @param buf1 缓冲1指针
 * @param buf2 缓冲2指针（可选，双缓冲时使用）
 * @param buf_size 缓冲大小（字节）
 * @param mode 缓冲模式
 * @return 0 成功，<0 失败
 */
int easylvgl_display_set_buffers(
    easylvgl_ctx_t *ctx,
    void *buf1,
    void *buf2,
    uint32_t buf_size,
    easylvgl_buffer_mode_t mode);

/**
 * 初始化文件系统驱动
 * @param ctx 上下文指针
 * @return 0 成功，<0 失败
 * @pre-condition ctx 必须非空且已初始化
 * @post-condition 文件系统驱动已注册到 LVGL
 */
int easylvgl_fs_init(easylvgl_ctx_t *ctx);

/**
 * 读取文件到内存
 * @param ctx 上下文指针
 * @param path 文件路径，例如 "L:/anim.json"
 * @param out_data 输出缓冲指针（分配内存，需调用者释放）
 * @param out_len 输出长度
 * @return true 成功，false 失败
 */
bool easylvgl_fs_load_file(easylvgl_ctx_t *ctx, const char *path, void **out_data, size_t *out_len);

/**
 * 记录当前聚焦的 textarea，用于系统键盘转发
 */
void easylvgl_ctx_set_focused_textarea(easylvgl_ctx_t *ctx, lv_obj_t *textarea);
lv_obj_t *easylvgl_ctx_get_focused_textarea(easylvgl_ctx_t *ctx);

/**
 * 控制系统键盘输入
 */
int easylvgl_system_keyboard_enable(easylvgl_ctx_t *ctx, bool enable);
bool easylvgl_system_keyboard_is_enabled(easylvgl_ctx_t *ctx);
void easylvgl_system_keyboard_post_key(easylvgl_ctx_t *ctx, uint32_t key, bool pressed);
void easylvgl_system_keyboard_post_text(easylvgl_ctx_t *ctx, const char *text);
void easylvgl_system_keyboard_set_preedit(easylvgl_ctx_t *ctx, const char *text);
void easylvgl_system_keyboard_clear_preedit(easylvgl_ctx_t *ctx);


#ifdef __cplusplus
}
#endif

#endif /* EASYLVGL_H */

