#ifndef LUAT_TINY_EPD_HZFONT_H
#define LUAT_TINY_EPD_HZFONT_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    TINY_EPD_HZFONT_DITHER_THRESHOLD = 0,
    TINY_EPD_HZFONT_DITHER_BAYER4 = 1
} tiny_epd_hzfont_dither_t;

/* bg == -1 keeps the framebuffer transparent below the glyph coverage.
 * FG/BG sentinels select the panel-local drawing colors. */
typedef struct {
    uint8_t fg;
    int16_t bg;
    int8_t antialias; /* -1 = auto, 1..3 = HzFont supersample level. */
    uint8_t threshold;
    tiny_epd_hzfont_dither_t dither;
} tiny_epd_hzfont_style_t;

void tiny_epd_hzfont_style_init(tiny_epd_hzfont_style_t *style);
uint32_t tiny_epd_hzfont_get_utf8_width(const char *utf8, uint8_t size);
/* x,y is the text baseline, matching lcd.drawHzfontUtf8 and legacy eink. */
int tiny_epd_hzfont_draw_utf8(tiny_epd_t *epd,
                               int16_t x, int16_t baseline_y,
                               const char *utf8, uint8_t size,
                               const tiny_epd_hzfont_style_t *style);

#ifdef __cplusplus
}
#endif

#endif
