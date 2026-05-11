/**
 * @file nes_airui_video.h
 * @brief NES 模拟器 AirUI/LVGL9 视频输出适配器
 *
 * 将 NES 帧缓冲渲染为 LVGL image 对象，可嵌入 AirUI 界面。
 * 支持触摸控制按钮、缩放显示。
 *
 * @tag LUAT_USE_NES, LUAT_USE_AIRUI
 */

#ifndef NES_AIRUI_VIDEO_H
#define NES_AIRUI_VIDEO_H

#include "luat_base.h"

#ifdef LUAT_USE_AIRUI

#include "nes_conf.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========== 常量 ========== */

#define NES_AIRUI_WIDTH     256
#define NES_AIRUI_HEIGHT    240

/* ========== 配置结构体 ========== */

/**
 * @brief NES AirUI 视频输出配置
 */
typedef struct {
    int scale;              /**< 显示缩放倍数，1-3，默认 1 */
    int show_controls;      /**< 是否显示触控按钮，默认 1 */
    uint32_t bg_color;      /**< 背景颜色，默认 0x1A1A2E */
    uint32_t btn_a_color;   /**< A 按钮颜色，默认 0xE74C3C */
    uint32_t btn_b_color;   /**< B 按钮颜色，默认 0x3498DB */
} nes_airui_video_config_t;

/* ========== 不透明上下文类型 ========== */

/**
 * @brief NES AirUI 视频上下文（不透明类型）
 */
typedef struct nes_airui_video nes_airui_video_t;

/* ========== 生命周期 API ========== */

/**
 * @brief 获取默认配置
 * @param config 输出配置结构体
 */
void nes_airui_video_get_default_config(nes_airui_video_config_t *config);

/**
 * @brief 初始化 AirUI 视频输出，创建 LVGL 界面
 * @param config 配置参数，NULL 使用默认值
 * @return 上下文指针，失败返回 NULL
 */
nes_airui_video_t *nes_airui_video_init(const nes_airui_video_config_t *config);

/**
 * @brief 销毁 AirUI 视频输出，释放 LVGL 对象和帧缓冲
 * @param video 上下文指针，NULL 使用全局实例
 */
void nes_airui_video_deinit(nes_airui_video_t *video);

/* ========== 渲染 API ========== */

/**
 * @brief 将 nes_draw() 提供的矩形像素块写入帧缓冲
 *
 * 由 nes_port.c 的 nes_draw() 调用。NES_RAM_LACK=1 时每次提供半帧
 * (y1=0~119 或 y1=120~239)，此函数按行偏移写入全帧 framebuffer。
 *
 * @param video  上下文指针，NULL 使用全局实例
 * @param x1     起始列（通常为 0）
 * @param y1     起始行
 * @param x2     结束列（通常为 255）
 * @param y2     结束行
 * @param pixels RGB565 像素数据（行优先，(x2-x1+1)*(y2-y1+1) 个像素）
 * @return 0 成功，负数失败
 */
int nes_airui_video_draw(nes_airui_video_t *video,
                         size_t x1, size_t y1,
                         size_t x2, size_t y2,
                         const nes_color_t *pixels);

/**
 * @brief 一帧结束，通知 LVGL 刷新画面
 *
 * 由 nes_port.c 的 nes_frame() 调用。调用 lv_obj_invalidate() 触发重绘。
 *
 * @param video 上下文指针，NULL 使用全局实例
 */
void nes_airui_video_frame(nes_airui_video_t *video);

/* ========== 状态查询 ========== */

/**
 * @brief 检查用户是否请求退出（点击 Exit 按钮）
 * @param video 上下文指针，NULL 使用全局实例
 * @return 1 已请求退出，0 未请求
 */
int nes_airui_video_quit_requested(nes_airui_video_t *video);

/**
 * @brief 设置显示缩放倍数
 * @param video 上下文指针，NULL 使用全局实例
 * @param scale 缩放倍数 1-3
 * @return 0 成功，负数失败
 */
int nes_airui_video_set_scale(nes_airui_video_t *video, int scale);

/**
 * @brief 显示或隐藏触控按钮
 * @param video 上下文指针，NULL 使用全局实例
 * @param show  1 显示，0 隐藏
 */
void nes_airui_video_show_controls(nes_airui_video_t *video, int show);

/**
 * @brief 获取全局 NES AirUI 上下文（供 nes_port.c 使用）
 * @return 全局上下文指针，未初始化时为 NULL
 */
nes_airui_video_t *nes_airui_video_get_global(void);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_USE_AIRUI */
#endif /* NES_AIRUI_VIDEO_H */
