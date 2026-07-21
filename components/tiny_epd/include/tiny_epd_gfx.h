#ifndef LUAT_TINY_EPD_GFX_H
#define LUAT_TINY_EPD_GFX_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Set the rotation angle applied to subsequent draw operations.
 *
 * Accepted values: 0, 90, 180, 270. Other values are masked to 0..3.
 * Rotation is implemented in software (coordinate transform) — see design doc
 * for why 90/270 cannot be done in hardware on the SSD1608/SSD1607 panel ICs.
 * Existing `tiny_epd_draw_pixel` is left untouched, so a `panel:pixel` call
 * after `setRotation(90)` still writes to the physical (x, y) coordinate.
 * The QR primitive is also rotation-agnostic (QR is a fixed bitmap).
 */
int tiny_epd_set_rotation(tiny_epd_t *epd, uint8_t rotate);

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
 * @brief QR code (Project Nayuki encoder, already vendored under
 *        components/qrcode/qrcodegen.h). Renders the QR at (x, y) in a
 *        `size x size` pixel square. Background is filled with the
 *        complement of `color`. Rotation is intentionally not applied to QR.
 */
int tiny_epd_draw_qrcode(tiny_epd_t *epd,
                         int16_t x, int16_t y,
                         const char *str, uint16_t size,
                         uint8_t color);

/**
 * @brief Horizontal (dir=0) or vertical (dir=1) span, length `len`.
 *        Signature matches eink's `u8g2_draw_hv_line` so future text/font
 *        rendering backends (u8g2 / HzFont) can route through this entry.
 */
int tiny_epd_gfx_hv_line(tiny_epd_t *epd,
                        int16_t x, int16_t y, int16_t len,
                        uint8_t dir, uint8_t color);

#ifdef __cplusplus
}
#endif

#endif
