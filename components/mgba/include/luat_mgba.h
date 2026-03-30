/**
 * @file luat_mgba.h
 * @brief LuatOS mGBA 接口头文件
 * 
 * 该文件定义了 LuatOS 平台上 mGBA 模拟器的接口
 */

#ifndef LUAT_MGBA_H
#define LUAT_MGBA_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========== 类型定义 ========== */

/**
 * @brief 颜色类型 (32位 ABGR8888 / A8B8G8R8)
 * 
 * mGBA 颜色定义: R=0x000000FF, G=0x0000FF00, B=0x00FF0000
 * 小端系统内存布局: [R][G][B][A] (低地址→高地址)
 * 对应 SDL_PIXELFORMAT_ABGR8888 (小端: [R][G][B][A])
 */
typedef uint32_t luat_mgba_color_t;

/**
 * @brief mGBA 实例结构
 */
typedef struct luat_mgba {
    void* core;                     /**< mGBA 核心实例 (mCore*) */
    luat_mgba_color_t* framebuffer; /**< 帧缓冲 */
    uint32_t width;                 /**< 视频宽度 */
    uint32_t height;                /**< 视频高度 */
    int audio_rate;                 /**< 音频采样率 */
    
    /* 状态 */
    int running;                    /**< 运行标志 */
    int paused;                     /**< 暂停标志 */
    int initialized;                /**< 初始化标志 */
    
    
    /* 回调函数 */
    void (*video_cb)(struct luat_mgba* ctx, luat_mgba_color_t* fb);
    void (*audio_cb)(struct luat_mgba* ctx, int16_t* samples, size_t count);
} luat_mgba_t;

/* ========== GBA 按键定义 ========== */

#define LUAT_MGBA_KEY_A        (1 << 0)    /**< A 按钮 */
#define LUAT_MGBA_KEY_B        (1 << 1)    /**< B 按钮 */
#define LUAT_MGBA_KEY_SELECT   (1 << 2)    /**< SELECT 按钮 */
#define LUAT_MGBA_KEY_START    (1 << 3)    /**< START 按钮 */
#define LUAT_MGBA_KEY_RIGHT    (1 << 4)    /**< 方向键右 */
#define LUAT_MGBA_KEY_LEFT     (1 << 5)    /**< 方向键左 */
#define LUAT_MGBA_KEY_UP       (1 << 6)    /**< 方向键上 */
#define LUAT_MGBA_KEY_DOWN     (1 << 7)    /**< 方向键下 */
#define LUAT_MGBA_KEY_R        (1 << 8)    /**< R 肩键 */
#define LUAT_MGBA_KEY_L        (1 << 9)    /**< L 肩键 */

/* ========== 平台类型 ========== */

#define LUAT_MGBA_PLATFORM_GBA     0       /**< Game Boy Advance */
#define LUAT_MGBA_PLATFORM_GB      1       /**< Game Boy */
#define LUAT_MGBA_PLATFORM_GBC     2       /**< Game Boy Color */
#define LUAT_MGBA_PLATFORM_AUTO    3       /**< 自动检测 */

/* ========== 生命周期 API ========== */

/**
 * @brief 初始化 mGBA 实例
 * @param ctx_out 输出指针，返回创建的实例
 * @param platform 平台类型 (GBA/GB/GBC/AUTO)
 * @return 0 成功，负数失败
 */
int luat_mgba_init(luat_mgba_t** ctx_out, int platform);

/**
 * @brief 销毁 mGBA 实例
 * @param ctx mGBA 实例
 * @return 0 成功，负数失败
 */
int luat_mgba_deinit(luat_mgba_t* ctx);

/**
 * @brief 检查实例是否已初始化
 * @param ctx mGBA 实例
 * @return 1 已初始化，0 未初始化
 */
int luat_mgba_is_initialized(luat_mgba_t* ctx);

/* ========== ROM 加载 ========== */

/**
 * @brief 从文件路径加载 ROM
 * @param ctx mGBA 实例
 * @param path ROM 文件路径
 * @return 0 成功，负数失败
 */
int luat_mgba_load_rom(luat_mgba_t* ctx, const char* path);

/**
 * @brief 从内存数据加载 ROM
 * @param ctx mGBA 实例
 * @param data ROM 数据指针
 * @param len 数据长度
 * @return 0 成功，负数失败
 */
int luat_mgba_load_rom_data(luat_mgba_t* ctx, const uint8_t* data, size_t len);

/**
 * @brief 卸载当前 ROM
 * @param ctx mGBA 实例
 * @return 0 成功，负数失败
 */
int luat_mgba_unload_rom(luat_mgba_t* ctx);

/* ========== 执行控制 ========== */

/**
 * @brief 执行单帧
 * @param ctx mGBA 实例
 * @return 0 成功，负数失败
 */
int luat_mgba_run_frame(luat_mgba_t* ctx);

/**
 * @brief 执行多帧
 * @param ctx mGBA 实例
 * @param count 帧数
 * @return 实际执行的帧数
 */
int luat_mgba_run_frames(luat_mgba_t* ctx, int count);

/**
 * @brief 暂停模拟
 * @param ctx mGBA 实例
 */
void luat_mgba_pause(luat_mgba_t* ctx);

/**
 * @brief 恢复模拟
 * @param ctx mGBA 实例
 */
void luat_mgba_resume(luat_mgba_t* ctx);

/**
 * @brief 重置游戏
 * @param ctx mGBA 实例
 * @return 0 成功，负数失败
 */
int luat_mgba_reset(luat_mgba_t* ctx);

/**
 * @brief 检查是否正在运行
 * @param ctx mGBA 实例
 * @return 1 运行中，0 未运行
 */
int luat_mgba_is_running(luat_mgba_t* ctx);

/* ========== 输入控制 ========== */

/**
 * @brief 设置按键状态
 * @param ctx mGBA 实例
 * @param key 按键位掩码 (LUAT_MGBA_KEY_*)
 * @param pressed 1 按下，0 释放
 */
void luat_mgba_set_key(luat_mgba_t* ctx, int key, int pressed);

/**
 * @brief 设置多个按键状态
 * @param ctx mGBA 实例
 * @param keys 按键位掩码组合
 */
void luat_mgba_set_keys(luat_mgba_t* ctx, uint16_t keys);

/**
 * @brief 获取当前按键状态
 * @param ctx mGBA 实例
 * @return 按键位掩码
 */
uint16_t luat_mgba_get_keys(luat_mgba_t* ctx);

/* ========== 存档管理 ========== */

/**
 * @brief 保存游戏状态到文件
 * @param ctx mGBA 实例
 * @param path 存档文件路径
 * @return 0 成功，负数失败
 */
int luat_mgba_save_state(luat_mgba_t* ctx, const char* path);

/**
 * @brief 从文件加载游戏状态
 * @param ctx mGBA 实例
 * @param path 存档文件路径
 * @return 0 成功，负数失败
 */
int luat_mgba_load_state(luat_mgba_t* ctx, const char* path);

/**
 * @brief 保存游戏存档 (SRAM)
 * @param ctx mGBA 实例
 * @param path 存档文件路径
 * @return 0 成功，负数失败
 */
int luat_mgba_save_sram(luat_mgba_t* ctx, const char* path);

/**
 * @brief 加载游戏存档 (SRAM)
 * @param ctx mGBA 实例
 * @param path 存档文件路径
 * @return 0 成功，负数失败
 */
int luat_mgba_load_sram(luat_mgba_t* ctx, const char* path);

/* ========== 配置 ========== */

/**
 * @brief 设置音频采样率
 * @param ctx mGBA 实例
 * @param rate 采样率 (如 44100)
 * @return 0 成功，负数失败
 */
int luat_mgba_set_audio_rate(luat_mgba_t* ctx, int rate);

/**
 * @brief 设置自定义帧缓冲
 * @param ctx mGBA 实例
 * @param buffer 帧缓冲指针
 * @return 0 成功，负数失败
 */
int luat_mgba_set_video_buffer(luat_mgba_t* ctx, luat_mgba_color_t* buffer);

/**
 * @brief 获取当前帧缓冲
 * @param ctx mGBA 实例
 * @return 帧缓冲指针
 */
luat_mgba_color_t* luat_mgba_get_framebuffer(luat_mgba_t* ctx);

/* ========== 信息获取 ========== */

/**
 * @brief ROM 信息结构
 */
typedef struct {
    char title[256];        /**< 游戏标题 */
    char code[16];          /**< 游戏代码 */
    char maker[16];         /**< 制作商代码 */
    int platform;           /**< 平台类型 */
    uint32_t rom_size;      /**< ROM 大小 */
    uint32_t width;         /**< 视频宽度 */
    uint32_t height;        /**< 视频高度 */
} luat_mgba_rom_info_t;

/**
 * @brief 获取当前 ROM 信息
 * @param ctx mGBA 实例
 * @param info 输出信息结构
 * @return 0 成功，负数失败
 */
int luat_mgba_get_rom_info(luat_mgba_t* ctx, luat_mgba_rom_info_t* info);

/**
 * @brief 获取 GBA 视频尺寸
 * @param width 输出宽度
 * @param height 输出高度
 */
void luat_mgba_get_gba_video_size(uint32_t* width, uint32_t* height);

/* ========== 回调设置 ========== */

/**
 * @brief 设置视频帧回调
 * @param ctx mGBA 实例
 * @param callback 回调函数
 */
void luat_mgba_set_video_callback(luat_mgba_t* ctx, 
    void (*callback)(luat_mgba_t* ctx, luat_mgba_color_t* fb));

/**
 * @brief 设置音频回调
 * @param ctx mGBA 实例
 * @param callback 回调函数
 */
void luat_mgba_set_audio_callback(luat_mgba_t* ctx,
    void (*callback)(luat_mgba_t* ctx, int16_t* samples, size_t count));

/* ========== 视频输出 API (SDL2) ========== */

/**
 * @brief 视频输出上下文 (平台相关，用户不应直接访问)
 */
typedef struct luat_mgba_video luat_mgba_video_t;

/**
 * @brief 视频输出配置
 */
typedef struct {
    int scale;              /**< 显示缩放倍数 (默认 2) */
    const char* title;      /**< 窗口标题 (默认 "LuatOS mGBA") */
    int fullscreen;         /**< 全屏模式 (0: 窗口, 1: 全屏) */
    int vsync;              /**< 垂直同步 (0: 禁用, 1: 启用) */
} luat_mgba_video_config_t;

/**
 * @brief 初始化视频输出
 * @param config 配置参数 (可为 NULL 使用默认值)
 * @return 视频上下文指针，失败返回 NULL
 */
luat_mgba_video_t* luat_mgba_video_init(const luat_mgba_video_config_t* config);

/**
 * @brief 销毁视频输出
 * @param video 视频上下文
 */
void luat_mgba_video_deinit(luat_mgba_video_t* video);

/**
 * @brief 显示帧缓冲到屏幕
 * @param video 视频上下文
 * @param fb 帧缓冲数据 (RGB565, 240x160)
 * @param width 帧缓冲宽度
 * @param height 帧缓冲高度
 * @return 0 成功，负数失败
 */
int luat_mgba_video_present(luat_mgba_video_t* video, 
    const luat_mgba_color_t* fb, uint32_t width, uint32_t height);

/**
 * @brief 设置显示缩放倍数
 * @param video 视频上下文
 * @param scale 缩放倍数 (1-4)
 * @return 0 成功，负数失败
 */
int luat_mgba_video_set_scale(luat_mgba_video_t* video, int scale);

/**
 * @brief 设置窗口标题
 * @param video 视频上下文
 * @param title 窗口标题
 */
void luat_mgba_video_set_title(luat_mgba_video_t* video, const char* title);

/**
 * @brief 切换全屏模式
 * @param video 视频上下文
 * @param fullscreen 1 全屏, 0 窗口
 */
void luat_mgba_video_set_fullscreen(luat_mgba_video_t* video, int fullscreen);

/**
 * @brief 处理 SDL 事件 (输入等)
 * @param video 视频上下文
 * @param mgba_ctx mGBA 实例 (用于输入处理)
 * @return 0 正常, 1 用户请求退出
 */
int luat_mgba_video_handle_events(luat_mgba_video_t* video, luat_mgba_t* mgba_ctx);

/**
 * @brief 获取默认视频配置
 * @param config 输出配置结构
 */
void luat_mgba_video_get_default_config(luat_mgba_video_config_t* config);

/* ========== 输入处理 API ========== */

/**
 * @brief 键盘扫描码到 GBA 按键映射
 * @param scancode SDL 扫描码
 * @return GBA 按键位掩码，0 表示无映射
 */
int luat_mgba_key_from_scancode(int scancode);

/**
 * @brief 处理 SDL 键盘事件
 * @param ctx mGBA 实例
 * @param scancode SDL 扫描码
 * @param pressed 1 按下, 0 释放
 */
void luat_mgba_handle_key_event(luat_mgba_t* ctx, int scancode, int pressed);

/**
 * @brief 获取按键名称
 * @param key GBA 按键位掩码
 * @return 按键名称字符串
 */
const char* luat_mgba_key_name(int key);

/**
 * @brief 从按键名称字符串获取按键码
 * @param name 按键名称 ("a", "b", "start", "select", "up", "down", "left", "right", "l", "r")
 * @return 按键码，0 表示无效
 */
int luat_mgba_key_from_name(const char* name);

/* ========== 音频输出 API (SDL2) ========== */

/**
 * @brief 音频输出上下文 (平台相关，用户不应直接访问)
 */
typedef struct luat_mgba_audio luat_mgba_audio_t;

/**
 * @brief 音频输出配置
 */
typedef struct {
    int sample_rate;        /**< 采样率 (默认 44100) */
    int channels;           /**< 声道数 (默认 2) */
    int buffer_size;        /**< 缓冲区大小 (默认 1024) */
    int enabled;            /**< 启用音频 (默认 1) */
} luat_mgba_audio_config_t;

/**
 * @brief 初始化音频输出
 * @param config 配置参数 (可为 NULL 使用默认值)
 * @return 音频上下文指针，失败返回 NULL
 */
luat_mgba_audio_t* luat_mgba_audio_init(const luat_mgba_audio_config_t* config);

/**
 * @brief 销毁音频输出
 * @param audio 音频上下文
 */
void luat_mgba_audio_deinit(luat_mgba_audio_t* audio);

/**
 * @brief 输出音频数据
 * @param audio 音频上下文
 * @param samples 音频采样数据 (交错格式)
 * @param count 采样数 (每声道)
 * @return 0 成功，负数失败
 */
int luat_mgba_audio_output(luat_mgba_audio_t* audio, const int16_t* samples, size_t count);

/**
 * @brief 暂停/恢复音频输出
 * @param audio 音频上下文
 * @param pause 1 暂停, 0 恢复
 */
void luat_mgba_audio_pause(luat_mgba_audio_t* audio, int pause);

/**
 * @brief 设置音量
 * @param audio 音频上下文
 * @param volume 音量 (0-128, SDL 混音器格式)
 */
void luat_mgba_audio_set_volume(luat_mgba_audio_t* audio, int volume);

/**
 * @brief 清空音频缓冲
 * @param audio 音频上下文
 */
void luat_mgba_audio_clear(luat_mgba_audio_t* audio);

/**
 * @brief 获取默认音频配置
 * @param config 输出配置结构
 */
void luat_mgba_audio_get_default_config(luat_mgba_audio_config_t* config);

/* ========== AirUI视频输出 API ========== */
#ifdef LUAT_USE_AIRUI

/**
 * @brief AirUI视频输出配置
 */
typedef struct {
    int scale;              /**< 显示缩放倍数 (默认 2) */
    int show_controls;      /**< 是否显示控制按钮 (默认 1) */
    uint32_t bg_color;      /**< 背景颜色 (默认 0x2C3E50) */
    uint32_t btn_a_color;   /**< A按钮颜色 (默认 0xE74C3C) */
    uint32_t btn_b_color;   /**< B按钮颜色 (默认 0x3498DB) */
} luat_mgba_airui_video_config_t;

/**
 * @brief AirUI视频输出上下文
 */
typedef struct luat_mgba_airui_video luat_mgba_airui_video_t;

/**
 * @brief 获取默认AirUI视频配置
 * @param config 输出配置结构
 */
void luat_mgba_airui_video_get_default_config(luat_mgba_airui_video_config_t* config);

/**
 * @brief 初始化AirUI视频输出
 * @param config 配置参数 (可为 NULL 使用默认值)
 * @return 视频上下文指针，失败返回 NULL
 */
luat_mgba_airui_video_t* luat_mgba_airui_video_init(const luat_mgba_airui_video_config_t* config);

/**
 * @brief 销毁AirUI视频输出
 * @param video 视频上下文
 */
void luat_mgba_airui_video_deinit(luat_mgba_airui_video_t* video);

/**
 * @brief 显示帧缓冲到AirUI画布
 * @param video 视频上下文
 * @param fb 帧缓冲数据 (ABGR8888格式)
 * @param width 帧缓冲宽度
 * @param height 帧缓冲高度
 * @return 0 成功，负数失败
 */
int luat_mgba_airui_video_present(luat_mgba_airui_video_t* video, 
    const luat_mgba_color_t* fb, uint32_t width, uint32_t height);

/**
 * @brief 检查是否有退出请求
 * @param video 视频上下文
 * @return 1 有退出请求，0 无
 */
int luat_mgba_airui_video_quit_requested(luat_mgba_airui_video_t* video);

/**
 * @brief 设置显示缩放倍数
 * @param video 视频上下文
 * @param scale 缩放倍数 (1-4)
 * @return 0 成功，负数失败
 */
int luat_mgba_airui_video_set_scale(luat_mgba_airui_video_t* video, int scale);

/**
 * @brief 显示/隐藏控制按钮
 * @param video 视频上下文
 * @param show 1 显示，0 隐藏
 */
void luat_mgba_airui_video_show_controls(luat_mgba_airui_video_t* video, int show);

/**
 * @brief AirUI视频输出配置（扩展版，支持外部容器）
 */
typedef struct {
    int scale;              /**< 显示缩放倍数 (默认 2) */
    int show_controls;      /**< 是否显示控制按钮 (默认 1) */
    uint32_t bg_color;      /**< 背景颜色 (默认 0x2C3E50) */
    uint32_t btn_a_color;   /**< A按钮颜色 (默认 0xE74C3C) */
    uint32_t btn_b_color;   /**< B按钮颜色 (默认 0x3498DB) */
    void* parent_obj;       /**< 父容器对象（lv_obj_t*），为NULL则使用全屏 */
    int x;                  /**< 在父容器中的X坐标 */
    int y;                  /**< 在父容器中的Y坐标 */
    int width;              /**< 宽度（0则使用父容器宽度） */
    int height;             /**< 高度（0则使用父容器高度） */
} luat_mgba_airui_video_config_ex_t;

/**
 * @brief 初始化AirUI视频输出（扩展版，支持嵌入外部容器）
 * @param config 配置参数
 * @return 视频上下文指针，失败返回 NULL
 */
luat_mgba_airui_video_t* luat_mgba_airui_video_init_ex(const luat_mgba_airui_video_config_ex_t* config);

#endif /* LUAT_USE_AIRUI */

#ifdef __cplusplus
}
#endif

#endif /* LUAT_MGBA_H */