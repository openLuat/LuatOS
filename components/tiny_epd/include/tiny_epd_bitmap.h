#ifndef LUAT_TINY_EPD_BITMAP_H
#define LUAT_TINY_EPD_BITMAP_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Pass this as bg to leave source zero bits unchanged. */
#define TINY_EPD_BITMAP_TRANSPARENT (-1)

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
