#ifndef _LUAT_HZFONT_H_
#define _LUAT_HZFONT_H_

#include "luat_base.h"
#include <stdint.h>
#include "ttf_parser.h"

#include "luat_conf_bsp.h"

#ifdef __cplusplus
extern "C" {
#endif

// 字体状态枚举
typedef enum {
    LUAT_HZFONT_STATE_UNINIT = 0,
    LUAT_HZFONT_STATE_READY  = 1,
    LUAT_HZFONT_STATE_ERROR  = 2,
} luat_hzfont_state_t;

// 初始化 hzfont 库并加载指定字体，建立缓存（可选加载到 PSRAM）
int luat_hzfont_init(const char *ttf_path, uint32_t cache_size, int load_to_psram);
// 释放 hzfont 资源并清理缓存
void luat_hzfont_deinit(void);
// 查询当前 hzfont 状态
luat_hzfont_state_t luat_hzfont_get_state(void);
// 估算一段 UTF-8 字符串的像素宽度
uint32_t luat_hzfont_get_str_width(const char *utf8, unsigned char font_size);
/* antialias = -1(自动), 1(无AA), 2(2x2), 4(4x4) */
// 在屏幕上绘制 UTF-8 文本（带缓存和抗锯齿控制）
int luat_hzfont_draw_utf8(int x, int y, const char *utf8, unsigned char font_size, uint32_t color, int antialias);

#ifdef LUAT_USE_AIRUI
//  hzfont绘制耗时统计
typedef struct {
    uint8_t cache_hit;
    uint8_t cache_miss;
    uint8_t load_fail;
    uint8_t raster_fail;
    uint32_t load_us;
    uint32_t raster_us;
    uint32_t total_us;
} luat_hzfont_bitmap_profile_t;

// 用于 airui 的 hzfont 兼容接口：获取底层 TTF 结构
TtfFont * luat_hzfont_get_ttf(void);
// 用于 airui 的码点查找接口（复用 hzfont 内部 cp cache）
int luat_hzfont_lookup_glyph_index(uint32_t codepoint, uint16_t *glyph_index);
// 获取位图并输出本次流程统计（供 airui 调试汇总）
const TtfBitmap * luat_hzfont_get_bitmap_profiled(uint16_t glyph_index, uint8_t font_size,
                                                  uint8_t supersample, luat_hzfont_bitmap_profile_t *prof_out);
// 访问指定 glyph 的缓存位图（不存在时会触发实时渲染）
const TtfBitmap * luat_hzfont_get_bitmap(uint16_t glyph_index, uint8_t font_size, uint8_t supersample);
#endif

#ifdef __cplusplus
}
#endif

#endif /* _LUAT_HZFONT_H_ */
