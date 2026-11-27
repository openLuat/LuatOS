#ifndef LUAT_TINY_EPD_BITMAP_H
#define LUAT_TINY_EPD_BITMAP_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Pass this as bg to leave source zero bits unchanged. */
#define TINY_EPD_BITMAP_TRANSPARENT (-1)

/*
 * Draw a 4bpp indexed bitmap in the current logical coordinate space.
 *
 * Source layout is row-major, ceil(width / 2) bytes per row, two pixels per
 * byte, high nibble first. Each nibble holds a *logical* color value
 * (TINY_EPD_COLOR_BLACK/WHITE/RED/YELLOW/ORANGE/BLUE/GREEN), not a controller
 * RAM code, so the same data works on any 4bpp driver. Pixels outside the
 * canvas are clipped. This is what a photo pipeline should feed: memory is
 * exactly stride * height bytes, no per-pixel Lua calls.
 */
int tiny_epd_draw_index4(tiny_epd_t *epd,
                         int16_t x, int16_t y,
                         uint16_t width, uint16_t height,
                         const uint8_t *data, size_t data_len);

/*
 * Draw an XBM bitmap in the current logical coordinate space.
 *
 * Source layout is row-major, ceil(width / 8) bytes per row, and bit 0 of
 * each source byte is the left-most pixel. This is the same representation
 * used by eink.drawXbm() and u8g2.DrawXBM(). A set source bit is fg; a clear
 * source bit is bg, unless bg is TINY_EPD_BITMAP_TRANSPARENT. fg/bg may be
 * real palette colors or TINY_EPD_COLOR_FG/TINY_EPD_COLOR_BG.
 */
int tiny_epd_draw_xbm(tiny_epd_t *epd,
                      int16_t x, int16_t y,
                      uint16_t width, uint16_t height,
                      const uint8_t *data, size_t data_len,
                      uint8_t fg, int16_t bg);

#ifdef __cplusplus
}
#endif

#endif
