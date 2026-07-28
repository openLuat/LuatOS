#include "tiny_epd_bitmap.h"

#include <stdint.h>

int tiny_epd_draw_xbm(tiny_epd_t *epd,
                      int16_t x, int16_t y,
                      uint16_t width, uint16_t height,
                      const uint8_t *data, size_t data_len,
                      uint8_t fg, int16_t bg)
{
    size_t row_bytes;
    size_t required_len;
    uint16_t source_y;

    if (epd == NULL || data == NULL || width == 0 || height == 0 ||
        fg > TINY_EPD_COLOR_WHITE ||
        (bg != TINY_EPD_BITMAP_TRANSPARENT &&
         (bg < TINY_EPD_COLOR_BLACK || bg > TINY_EPD_COLOR_WHITE))) {
        return TINY_EPD_ERR_PARAM;
    }
    if (tiny_epd_bits_per_pixel(epd) != 1 || tiny_epd_plane_count(epd) != 1) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }

    row_bytes = ((size_t)width + 7u) / 8u;
    if (height > ((size_t)-1) / row_bytes) {
        return TINY_EPD_ERR_PARAM;
    }
    required_len = row_bytes * (size_t)height;
    if (data_len != required_len) {
        return TINY_EPD_ERR_PARAM;
    }

    for (source_y = 0; source_y < height; source_y++) {
        uint16_t source_x;

        for (source_x = 0; source_x < width; source_x++) {
            uint8_t source_byte = data[(size_t)source_y * row_bytes + (source_x >> 3)];
            int32_t dest_x = (int32_t)x + source_x;
            int32_t dest_y = (int32_t)y + source_y;
            uint8_t color;
            int ret;

            if ((source_byte & (uint8_t)(1u << (source_x & 0x07u))) != 0) {
                color = fg;
            }
            else if (bg == TINY_EPD_BITMAP_TRANSPARENT) {
                continue;
            }
            else {
                color = (uint8_t)bg;
            }

            /* XBM is permitted to be partly outside the logical canvas. */
            if (dest_x < 0 || dest_y < 0 || dest_x > INT16_MAX || dest_y > INT16_MAX) {
                continue;
            }
            ret = tiny_epd_draw_pixel(epd, (int16_t)dest_x, (int16_t)dest_y, color);
            if (ret != TINY_EPD_OK && ret != TINY_EPD_ERR_PARAM) {
                return ret;
            }
        }
    }
    return TINY_EPD_OK;
}
