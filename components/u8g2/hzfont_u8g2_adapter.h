/**
 * HzFont U8G2适配器接口定义
 * @file    hzfont_u8g2_adapter.h
 * @brief   为U8G2图形库提供HzFont矢量字体适配支持
 * @author  wjq
 * @date    2026-4-9
 * @version 1.0
 */

#ifndef HZFONT_U8G2_ADAPTER_H
#define HZFONT_U8G2_ADAPTER_H

#include "u8g2.h"
#include "luat_base.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * HzFont U8G2字体对象
 * 用于管理HzFont在U8G2上的渲染状态
 */
typedef struct {
    uint8_t font_size;          /**< 字号 */
    uint8_t antialias;          /**< 抗锯齿等级 */
    char* font_path;            /**< 字体文件路径，NULL表示使用内置 */
    uint8_t threshold;          /**< 灰度阈值（用于单色转换）*/
    uint8_t inited;             /**< 初始化标志 */
    uint32_t ref_count;         /**< 引用计数 */
} hzfont_u8g2_font_t;

/**
 * 错误码定义
 */
typedef enum {
    HZFONT_U8G2_ERR_OK = 0,            /**< 成功 */
    HZFONT_U8G2_ERR_UNINIT = -1,      /**< HzFont未初始化 */
    HZFONT_U8G2_ERR_INVALID_PARAM = -2, /**< 参数无效 */
    HZFONT_U8G2_ERR_NO_MEMORY = -3,    /**< 内存不足 */
    HZFONT_U8G2_ERR_GLYPH_NOT_FOUND = -4, /**< 字符不存在 */
    HZFONT_U8G2_ERR_INVALID_SIZE = -5, /**< 字号超出范围 */
    HZFONT_U8G2_ERR_NOT_READY = -6,    /**< 适配器未就绪 */
} hzfont_u8g2_err_t;

/**
 * 创建HzFont字体对象
 * @param path TTF字体路径，NULL表示使用内置字库
 * @param size 字号，范围12-255
 * @param antialias 抗锯齿等级（-1:自动, 1-3:指定等级）
 * @return 字体对象指针，失败返回NULL
 * @usage
 * void* font = hzfont_u8g2_create_font(NULL, 16, 1);
 */
void* hzfont_u8g2_create_font(const char* path, uint8_t size, uint8_t antialias);

/**
 * 释放HzFont字体对象
 * @param font 字体对象指针
 * @usage
 * hzfont_u8g2_free_font(font);
 */
void hzfont_u8g2_free_font(void* font);

/**
 * 设置U8G2使用HzFont
 * @param u8g2 U8G2上下文
 * @param font HzFont对象
 * @return 0=成功，<0=失败
 * @usage
 * hzfont_u8g2_set_font(&u8g2, font);
 */
int hzfont_u8g2_set_font(u8g2_t* u8g2, void* font);

/**
 * 使用HzFont绘制文本到U8G2缓冲区
 * @param u8g2 U8G2上下文
 * @param x X坐标
 * @param y Y坐标
 * @param text UTF-8文本
 * @param font_size 字号（0表示使用SetHzFont设置的默认值）
 * @param antialias 抗锯齿等级（0xFF表示使用SetHzFont设置的默认值）
 * @return 渲染的字符数
 * @usage
 * uint16_t count = hzfont_u8g2_draw_text(&u8g2, 10, 30, "合宙LuatOS", 16, 1);
 */
uint16_t hzfont_u8g2_draw_text(u8g2_t* u8g2, u8g2_uint_t x, u8g2_uint_t y, const char* text, uint8_t font_size, uint8_t antialias);


/**
 * 获取HzFont U8G2字体对象的属性
 * @param font HzFont对象
 * @param font_size 输出字号
 * @param antialias 输出抗锯齿等级
 * @return 0=成功，<0=失败
 * @usage
 * uint8_t size, aa;
 * hzfont_u8g2_get_font_attr(font, &size, &aa);
 */
int hzfont_u8g2_get_font_attr(void* font, uint8_t* font_size, uint8_t* antialias);

/**
 * 设置HzFont U8G2字体对象的属性
 * @param font HzFont对象
 * @param font_size 字号，范围12-255
 * @param antialias 抗锯齿等级
 * @param threshold 灰度阈值（0-255）
 * @return 0=成功，<0=失败
 * @usage
 * hzfont_u8g2_set_font_attr(font, 20, 1, 128);
 */
int hzfont_u8g2_set_font_attr(void* font, uint8_t font_size, uint8_t antialias, uint8_t threshold);

/**
 * 初始化HzFont U8G2适配器
 * @return 0=成功，<0=失败
 * @usage
 * if (hzfont_u8g2_adapter_init() != HZFONT_U8G2_ERR_OK) {
 *     // 初始化失败处理
 * }
 */
int hzfont_u8g2_adapter_init(void);

/**
 * 反初始化HzFont U8G2适配器
 * @usage
 * hzfont_u8g2_adapter_deinit();
 */
void hzfont_u8g2_adapter_deinit(void);

/**
 * 获取错误描述
 * @param err 错误码
 * @return 错误描述字符串
 * @usage
 * const char* msg = hzfont_u8g2_strerror(HZFONT_U8G2_ERR_UNINIT);
 */
const char* hzfont_u8g2_strerror(int err);

/**
 * 检查U8G2是否使用HzFont
 * @param u8g2 U8G2上下文
 * @return 1=使用HzFont，0=使用普通字体
 * @usage
 * if (hzfont_u8g2_is_hzfont(&u8g2)) {
 *     // 使用HzFont渲染
 * }
 */
int hzfont_u8g2_is_hzfont(u8g2_t* u8g2);

/**
 * 获取U8G2的HzFont对象
 * @param u8g2 U8G2上下文
 * @return HzFont对象指针，未使用HzFont时返回NULL
 * @usage
 * hzfont_u8g2_font_t* font = hzfont_u8g2_get_font(&u8g2);
 */
hzfont_u8g2_font_t* hzfont_u8g2_get_font(u8g2_t* u8g2);

#ifdef __cplusplus
}
#endif

#endif // HZFONT_U8G2_ADAPTER_H