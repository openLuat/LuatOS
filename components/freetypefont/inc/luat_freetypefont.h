#ifndef _LUAT_FREETYPEFONT_H_
#define _LUAT_FREETYPEFONT_H_

#include "luat_base.h"

#ifdef __cplusplus
extern "C" {
#endif

// FreeType 库初始化状态
typedef enum {
    LUAT_FREETYPEFONT_STATE_UNINIT = 0,
    LUAT_FREETYPEFONT_STATE_INITED = 1,
    LUAT_FREETYPEFONT_STATE_ERROR = 2
} luat_freetypefont_state_t;

/**
 * @brief 初始化 FreeType 字体库
 * 
 * @param ttf_path TTF字体文件路径
 * @return int 0: 失败, 1: 成功
 */
int luat_freetypefont_init(const char* ttf_path);

/**
 * @brief 反初始化 FreeType 字体库
 */
void luat_freetypefont_deinit(void);

/**
 * @brief 获取当前初始化状态
 * 
 * @return luat_freetypefont_state_t 当前状态
 */
luat_freetypefont_state_t luat_freetypefont_get_state(void);

/**
 * @brief 获取字符位图（1bpp单色）
 * 
 * @param pBits 输出缓冲区
 * @param sty 样式（保留，暂未使用）
 * @param fontCode Unicode字符码
 * @param width 字符宽度（像素）
 * @param height 字符高度（像素）
 * @param thick 粗细（保留，暂未使用）
 * @return unsigned int 实际字符宽度
 */
unsigned int luat_freetypefont_get_char(
    unsigned char *pBits,
    unsigned char sty,
    unsigned long fontCode,
    unsigned char width,
    unsigned char height,
    unsigned char thick
);

/**
 * @brief 获取字符位图（灰度）
 * 
 * @param pBits 输出缓冲区
 * @param sty 样式（保留，暂未使用）
 * @param fontCode Unicode字符码
 * @param fontSize 字体大小（像素）
 * @param thick 粗细（保留，暂未使用）
 * @return unsigned int* 返回数组：[0]=实际宽度, [1]=灰度阶数
 */
unsigned int* luat_freetypefont_get_char_gray(
    unsigned char *pBits,
    unsigned char sty,
    unsigned long fontCode,
    unsigned char fontSize,
    unsigned char thick
);

/**
 * @brief 获取UTF-8字符串宽度
 * 
 * @param str UTF-8字符串
 * @param fontSize 字体大小
 * @return unsigned int 字符串总宽度（像素）
 */
unsigned int luat_freetypefont_get_str_width(
    const char* str,
    unsigned char fontSize
);

/**
 * @brief 绘制UTF-8字符串到LCD
 * 
 * @param x X坐标
 * @param y Y坐标
 * @param str UTF-8字符串
 * @param fontSize 字体大小
 * @param color 颜色值
 * @return int 0: 成功, -1: 失败
 */
int luat_freetypefont_draw_utf8(
    int x,
    int y,
    const char* str,
    unsigned char fontSize,
    uint32_t color
);

#ifdef __cplusplus
}
#endif

#endif /* _LUAT_FREETYPEFONT_H_ */