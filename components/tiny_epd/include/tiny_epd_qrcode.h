#ifndef LUAT_TINY_EPD_QRCODE_H
#define LUAT_TINY_EPD_QRCODE_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Render a QR code in the current logical coordinate space. size == 0 uses
 * the smaller remaining logical canvas dimension. With an explicit BLACK or
 * WHITE color the square background retains the historic mono complement.
 * TINY_EPD_COLOR_FG uses the panel foreground/background pair, which is the
 * preferred form for palette panels.
 */
int tiny_epd_draw_qrcode(tiny_epd_t *epd,
                         int16_t x, int16_t y,
                         const char *text, uint16_t size,
                         uint8_t color);

#ifdef __cplusplus
}
#endif

#endif
