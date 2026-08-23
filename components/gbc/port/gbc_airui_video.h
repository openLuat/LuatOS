/**
 * @file gbc_airui_video.h
 * @brief GBC 模拟器 AirUI/LVGL9 视频输出适配器（legacy 单实例）
 *
 * 将 GBC 帧缓冲渲染为 LVGL image 对象（可缩放），并自带触控 d-pad / AB / START/SELECT / Exit。
 * 该文件镜像 components/nes/port/nes_airui_video.h。
 *
 * @tag LUAT_USE_GBC, LUAT_USE_AIRUI
 */

#ifndef GBC_AIRUI_VIDEO_H
#define GBC_AIRUI_VIDEO_H

#include "luat_base.h"

#ifdef LUAT_USE_AIRUI

#include "gbc_conf.h"
#include "gbc_default.h"
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========== 常量 ========== */

#define GBC_AIRUI_WIDTH     160
#define GBC_AIRUI_HEIGHT    144

/* ========== 配置结构体 ========== */

/**
 * @brief GBC AirUI 视频输出配置
 */
typedef struct {
    int scale;              /**< 显示缩放倍数，1-3，默认 1 */
    int show_controls;      /**< 是否显示触控按钮，默认 1 */
    uint32_t bg_color;      /**< 背景颜色，默认 0x1A1A2E */
    uint32_t btn_a_color;   /**< A 按钮颜色，默认 0xE74C3C */
    uint32_t btn_b_color;   /**< B 按钮颜色，默认 0x3498DB */
} gbc_airui_video_config_t;

/* ========== 不透明上下文类型 ========== */

typedef struct gbc_airui_video gbc_airui_video_t;

/* ========== 生命周期 API ========== */

void gbc_airui_video_get_default_config(gbc_airui_video_config_t *config);

gbc_airui_video_t *gbc_airui_video_init(const gbc_airui_video_config_t *config);

void gbc_airui_video_deinit(gbc_airui_video_t *video);

/* ========== 渲染 API ========== */

int gbc_airui_video_draw(gbc_airui_video_t *video,
                         size_t x1, size_t y1,
                         size_t x2, size_t y2,
                         const gbc_color_t *pixels);

void gbc_airui_video_frame(gbc_airui_video_t *video);

/* ========== 状态查询 ========== */

int gbc_airui_video_quit_requested(gbc_airui_video_t *video);

int gbc_airui_video_set_scale(gbc_airui_video_t *video, int scale);

void gbc_airui_video_show_controls(gbc_airui_video_t *video, int show);

gbc_airui_video_t *gbc_airui_video_get_global(void);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_USE_AIRUI */
#endif /* GBC_AIRUI_VIDEO_H */