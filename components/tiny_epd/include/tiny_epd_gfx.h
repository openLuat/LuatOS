#ifndef LUAT_TINY_EPD_GFX_H
#define LUAT_TINY_EPD_GFX_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Horizontal line from (x, y) of length w. Pixels outside the panel are clipped. */
int tiny_epd_draw_hline(tiny_epd_t *epd, int16_t x, int16_t y, int16_t w, uint8_t color);

/** Vertical line from (x, y) of length h. Pixels outside the panel are clipped. */
int tiny_epd_draw_vline(tiny_epd_t *epd, int16_t x, int16_t y, int16_t h, uint8_t color);

/** Bresenham line from (x0, y0) to (x1, y1). Honours the current rotation. */
int tiny_epd_draw_line(tiny_epd_t *epd,
                       int16_t x0, int16_t y0, int16_t x1, int16_t y1,
                       uint8_t color);

/**
 * @brief Rectangle in end-point form (x, y) to (x2, y2).
 * @param fill 0 = hollow (outline only), 1 = filled.
 */
int tiny_epd_draw_rect(tiny_epd_t *epd,
                       int16_t x, int16_t y, int16_t x2, int16_t y2,
                       uint8_t color, uint8_t fill);

/**
 * @brief Circle with center (x, y) and radius r.
 * @param fill 0 = hollow (outline only), 1 = filled.
 */
int tiny_epd_draw_circle(tiny_epd_t *epd,
                        int16_t x, int16_t y, uint8_t r,
                        uint8_t color, uint8_t fill);

/**
 * @brief Directional span used by u8g2 font decoders.
 * @param dir 0=right, 1=down, 2=left, 3=up.
 */
int tiny_epd_gfx_hv_line(tiny_epd_t *epd,
                        int16_t x, int16_t y, int16_t len,
                        uint8_t dir, uint8_t color);

#ifdef __cplusplus
}
#endif

#endif
