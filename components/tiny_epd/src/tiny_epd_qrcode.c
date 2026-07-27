#include "tiny_epd_qrcode.h"
#include "tiny_epd_driver.h"

#include "qrcodegen.h"

#include <stdint.h>

static void tiny_epd_qrcode_put_pixel(tiny_epd_t *epd, int32_t x, int32_t y, uint8_t color)
{
    if (x < 0 || y < 0 || x >= tiny_epd_width(epd) || y >= tiny_epd_height(epd)) {
        return;
    }
    (void)tiny_epd_draw_pixel(epd, (int16_t)x, (int16_t)y, color);
}

int tiny_epd_draw_qrcode(tiny_epd_t *epd,
                         int16_t x, int16_t y,
                         const char *text, uint16_t size,
                         uint8_t color)
{
    uint8_t *qrcode;
    uint8_t *temp;
    uint16_t logical_width;
    uint16_t logical_height;
    int qr_size;
    int scale;
    int margin;
    int module_x;
    int module_y;
    int pixel_x;
    int pixel_y;
    uint8_t background;

    if (epd == NULL || text == NULL || color > TINY_EPD_COLOR_WHITE ||
        tiny_epd_bits_per_pixel(epd) != 1 || tiny_epd_plane_count(epd) != 1) {
        return TINY_EPD_ERR_PARAM;
    }
    logical_width = tiny_epd_width(epd);
    logical_height = tiny_epd_height(epd);
    if (x < 0 || y < 0 || x >= logical_width || y >= logical_height) {
        return TINY_EPD_ERR_PARAM;
    }
    {
        uint16_t remaining_width = (uint16_t)(logical_width - (uint16_t)x);
        uint16_t remaining_height = (uint16_t)(logical_height - (uint16_t)y);

        if (size == 0) {
            size = remaining_width < remaining_height ? remaining_width : remaining_height;
        }
        /* A QR code must be complete. Cropping a caller-supplied size makes
         * the resulting symbol invalid and is considerably harder to debug
         * than an explicit parameter error. */
        if (size == 0 || size > remaining_width || size > remaining_height) {
            return TINY_EPD_ERR_PARAM;
        }
    }

    qrcode = (uint8_t *)tiny_epd_port_alloc(epd, qrcodegen_BUFFER_LEN_MAX);
    if (qrcode == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    temp = (uint8_t *)tiny_epd_port_alloc(epd, qrcodegen_BUFFER_LEN_MAX);
    if (temp == NULL) {
        tiny_epd_port_free(epd, qrcode);
        return TINY_EPD_ERR_NO_MEM;
    }
    if (!luat_qrcodegen_encodeText(text, temp, qrcode,
                                   qrcodegen_Ecc_LOW,
                                   qrcodegen_VERSION_MIN,
                                   qrcodegen_VERSION_MAX,
                                   qrcodegen_Mask_AUTO,
                                   1)) {
        tiny_epd_port_free(epd, temp);
        tiny_epd_port_free(epd, qrcode);
        return TINY_EPD_ERR_PARAM;
    }

    qr_size = luat_qrcodegen_getSize(qrcode);
    scale = (int)size / qr_size;
    if (scale < 1) {
        tiny_epd_port_free(epd, temp);
        tiny_epd_port_free(epd, qrcode);
        return TINY_EPD_ERR_PARAM;
    }
    margin = ((int)size - qr_size * scale) / 2;
    background = color == TINY_EPD_COLOR_BLACK ? TINY_EPD_COLOR_WHITE : TINY_EPD_COLOR_BLACK;

    for (pixel_y = 0; pixel_y < size; pixel_y++) {
        for (pixel_x = 0; pixel_x < size; pixel_x++) {
            tiny_epd_qrcode_put_pixel(epd, (int32_t)x + pixel_x, (int32_t)y + pixel_y, background);
        }
    }
    for (module_y = 0; module_y < qr_size; module_y++) {
        for (module_x = 0; module_x < qr_size; module_x++) {
            int sx;
            int sy;

            if (!luat_qrcodegen_getModule(qrcode, module_x, module_y)) {
                continue;
            }
            for (sy = 0; sy < scale; sy++) {
                for (sx = 0; sx < scale; sx++) {
                    tiny_epd_qrcode_put_pixel(epd,
                                               (int32_t)x + margin + module_x * scale + sx,
                                               (int32_t)y + margin + module_y * scale + sy,
                                               color);
                }
            }
        }
    }

    tiny_epd_port_free(epd, temp);
    tiny_epd_port_free(epd, qrcode);
    return TINY_EPD_OK;
}
