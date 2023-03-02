
#ifndef LUAT_LIB_FONTS_H
#define LUAT_LIB_FONTS_H

#include "luat_base.h"

#ifdef __cplusplus
extern "C" {
#endif
#include "../src/lv_font/lv_font.h"

bool lv_font_is_gt(lv_font_t *font);
lv_font_t *lv_font_new_gt(uint8_t sty_zh, uint8_t sty_en, uint8_t size, uint8_t bpp, uint16_t thickness, uint8_t cache_size);
void lv_font_del_gt(lv_font_t *font);

// LV_FONT_DECLARE(lv_font_opposans_m_8)
// LV_FONT_DECLARE(lv_font_opposans_m_10)
// LV_FONT_DECLARE(lv_font_opposans_m_12)
// LV_FONT_DECLARE(lv_font_opposans_m_14)
// LV_FONT_DECLARE(lv_font_opposans_m_16)
// LV_FONT_DECLARE(lv_font_opposans_m_18)
// LV_FONT_DECLARE(lv_font_opposans_m_20)
// LV_FONT_DECLARE(lv_font_opposans_m_22)

#ifdef __cplusplus
}
#endif
#endif
