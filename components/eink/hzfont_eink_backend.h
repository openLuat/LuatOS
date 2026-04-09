/**
 * HzFont EINK后端接口定义
 * @file    hzfont_eink_backend.h
 * @brief   为EINK墨水屏提供HzFont矢量字体渲染支持
 * @author  wjq
 * @date    2026-4-9
 * @version 1.0
 */

#ifndef HZFONT_EINK_BACKEND_H
#define HZFONT_EINK_BACKEND_H

#include "epdpaint.h"
#include "luat_base.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * HzFont EINK渲染上下文
 * 用于管理HzFont在EINK上的渲染状态
 */
typedef struct {
    Paint* paint;           /**< EINK绘制上下文 */
    uint8_t font_size;      /**< 当前字号 */
    uint8_t antialias;      /**< 抗锯齿等级 */
    uint8_t threshold;      /**< 灰度阈值（用于二值化） */
    uint32_t fg_color;      /**< 前景色（COLORED/UNCOLORED）*/
    uint32_t bg_color;      /**< 背景色（COLORED/UNCOLORED）*/
    uint8_t inited;         /**< 初始化标志 */
} eink_hzfont_ctx_t;

/**
 * 错误码定义
 */
typedef enum {
    HZFONT_EINK_ERR_OK = 0,            /**< 成功 */
    HZFONT_EINK_ERR_UNINIT = -1,      /**< HzFont未初始化 */
    HZFONT_EINK_ERR_INVALID_PARAM = -2, /**< 参数无效 */
    HZFONT_EINK_ERR_NO_MEMORY = -3,    /**< 内存不足 */
    HZFONT_EINK_ERR_GLYPH_NOT_FOUND = -4, /**< 字符不存在 */
    HZFONT_EINK_ERR_INVALID_SIZE = -5, /**< 字号超出范围 */
} eink_hzfont_err_t;

/**
 * 在EINK绘制上下文中绘制HzFont UTF-8文本
 * @param paint EINK绘制上下文
 * @param x X坐标
 * @param y Y坐标
 * @param text UTF-8文本（支持中文、英文、数字）
 * @param font_size 字号，范围12-255
 * @param antialias 抗锯齿等级（-1:自动, 1-3:指定等级）
 * @return 0=成功，<0=失败（错误码）
 * @usage
 * Paint paint;
 * Paint_Init(&paint, image, 200, 200);
 * eink_hzfont_draw_utf8(&paint, 10, 10, "合宙LuatOS", 20, 1);
 */
int eink_hzfont_draw_utf8(Paint* paint, int x, int y,
                          const char* text, uint8_t font_size,
                          uint8_t antialias);


/**
 * 获取HzFont EINK后端渲染上下文
 * @return 渲染上下文指针，失败返回NULL
 * @usage
 * eink_hzfont_ctx_t* ctx = eink_hzfont_get_ctx();
 */
eink_hzfont_ctx_t* eink_hzfont_get_ctx(void);

/**
 * 初始化EINK HzFont后端
 * @return 0=成功，<0=失败（错误码）
 * @usage
 * if (eink_hzfont_backend_init() != HZFONT_EINK_ERR_OK) {
 *     // 初始化失败处理
 * }
 */
int eink_hzfont_backend_init(void);

/**
 * 反初始化EINK HzFont后端
 * @usage
 * eink_hzfont_backend_deinit();
 */
void eink_hzfont_backend_deinit(void);

/**
 * 设置HzFont EINK渲染参数
 * @param font_size 字号，范围12-255
 * @param antialias 抗锯齿等级（-1:自动, 1-3:指定等级）
 * @param threshold 灰度阈值（0-255）
 * @return 0=成功，<0=失败
 * @usage
 * eink_hzfont_set_params(20, 1, 128);
 */
int eink_hzfont_set_params(uint8_t font_size, uint8_t antialias, uint8_t threshold);

/**
 * 设置EINK绘制上下文
 * @param paint EINK绘制上下文
 * @return 0=成功，<0=失败
 * @usage
 * eink_hzfont_set_paint(&paint);
 */
int eink_hzfont_set_paint(Paint* paint);

/**
 * 获取错误描述
 * @param err 错误码
 * @return 错误描述字符串
 * @usage
 * const char* msg = eink_hzfont_strerror(HZFONT_EINK_ERR_UNINIT);
 */
const char* eink_hzfont_strerror(int err);

#ifdef __cplusplus
}
#endif

#endif // HZFONT_EINK_BACKEND_H