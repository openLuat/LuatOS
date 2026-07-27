#include "tiny_epd_driver.h"

#include <stddef.h>
#include <stdint.h>

#define TINY_EPD_1IN54_WIDTH  200u
#define TINY_EPD_1IN54_HEIGHT 200u
#define TINY_EPD_1IN54_LUT_SIZE 30u
#define TINY_EPD_1IN54_BUSY_IDLE_LEVEL 0u
#define TINY_EPD_1IN54_BUSY_TIMEOUT_MS 10000u
#define TINY_EPD_1IN54_BUSY_SETTLE_MS 100u

typedef struct {
    uint8_t lut_loaded;
    tiny_epd_refresh_mode_t lut_mode;
} tiny_epd_1in54_ctx_t;

static const uint8_t g_1in54_lut_full[TINY_EPD_1IN54_LUT_SIZE] = {
    0x02, 0x02, 0x01, 0x11, 0x12, 0x12, 0x22, 0x22,
    0x66, 0x69, 0x69, 0x59, 0x58, 0x99, 0x99, 0x88,
    0x00, 0x00, 0x00, 0x00, 0xF8, 0xB4, 0x13, 0x51,
    0x35, 0x51, 0x51, 0x19, 0x01, 0x00
};

static const uint8_t g_1in54_lut_partial[TINY_EPD_1IN54_LUT_SIZE] = {
    0x10, 0x18, 0x18, 0x08, 0x18, 0x18, 0x08, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x13, 0x14, 0x44, 0x12,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static int epd_1in54_cmd_data1(tiny_epd_t *epd, uint8_t cmd, uint8_t data)
{
    int ret = tiny_epd_write_cmd(epd, cmd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return tiny_epd_write_data_byte(epd, data);
}

static int epd_1in54_cmd_data(tiny_epd_t *epd,
                              uint8_t cmd,
                              const uint8_t *data,
                              size_t len)
{
    size_t i;
    int ret = tiny_epd_write_cmd(epd, cmd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    /*
     * Keep the first hardware driver close to the legacy LuatOS epaper path:
     * one data byte per SPI device transaction.
     */
    for (i = 0; i < len; i++) {
        ret = tiny_epd_write_data_byte(epd, data[i]);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    return TINY_EPD_OK;
}

static int epd_1in54_load_lut(tiny_epd_t *epd, tiny_epd_refresh_mode_t mode)
{
    tiny_epd_1in54_ctx_t *ctx = (tiny_epd_1in54_ctx_t *)tiny_epd_driver_state(epd);
    const uint8_t *lut;
    int ret;

    if (mode == TINY_EPD_REFRESH_AUTO) {
        mode = TINY_EPD_REFRESH_FULL;
    }
    if (mode != TINY_EPD_REFRESH_FULL && mode != TINY_EPD_REFRESH_PARTIAL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    if (ctx != NULL && ctx->lut_loaded && ctx->lut_mode == mode) {
        return TINY_EPD_OK;
    }

    lut = (mode == TINY_EPD_REFRESH_FULL) ? g_1in54_lut_full : g_1in54_lut_partial;
    ret = epd_1in54_cmd_data(epd, 0x32, lut, TINY_EPD_1IN54_LUT_SIZE);
    if (ret == TINY_EPD_OK && ctx != NULL) {
        ctx->lut_loaded = 1;
        ctx->lut_mode = mode;
    }
    return ret;
}

static int epd_1in54_set_window(tiny_epd_t *epd,
                                uint16_t x_start,
                                uint16_t y_start,
                                uint16_t x_end,
                                uint16_t y_end)
{
    uint8_t data[4];
    int ret;

    ret = tiny_epd_write_cmd(epd, 0x44);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    data[0] = (uint8_t)((x_start >> 3) & 0xFFu);
    data[1] = (uint8_t)((x_end >> 3) & 0xFFu);
    ret = tiny_epd_write_data(epd, data, 2);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    ret = tiny_epd_write_cmd(epd, 0x45);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    data[0] = (uint8_t)(y_start & 0xFFu);
    data[1] = (uint8_t)((y_start >> 8) & 0xFFu);
    data[2] = (uint8_t)(y_end & 0xFFu);
    data[3] = (uint8_t)((y_end >> 8) & 0xFFu);
    return tiny_epd_write_data(epd, data, 4);
}

static int epd_1in54_set_cursor(tiny_epd_t *epd, uint16_t x_start, uint16_t y_start)
{
    uint8_t data[2];
    int ret;

    ret = tiny_epd_write_cmd(epd, 0x4E);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    data[0] = (uint8_t)((x_start >> 3) & 0xFFu);
    ret = tiny_epd_write_data(epd, data, 1);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    ret = tiny_epd_write_cmd(epd, 0x4F);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    data[0] = (uint8_t)(y_start & 0xFFu);
    data[1] = (uint8_t)((y_start >> 8) & 0xFFu);
    return tiny_epd_write_data(epd, data, 2);
}

static int epd_1in54_turn_on_display(tiny_epd_t *epd)
{
    int ret;

    ret = epd_1in54_cmd_data1(epd, 0x22, 0xC4);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x20);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0xFF);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    /*
     * BUSY is idle-low on this controller. Some boards still read LOW for a
     * short time after MASTER_ACTIVATION before BUSY rises, so an immediate
     * wait-for-low can falsely complete and the next command may interrupt the
     * refresh. Give the panel time to enter the busy phase, then keep the
     * legacy driver's post-busy settle margin.
     */
    tiny_epd_delay_ms(epd, TINY_EPD_1IN54_BUSY_SETTLE_MS);
    ret = tiny_epd_wait_busy(epd,
                             TINY_EPD_1IN54_BUSY_IDLE_LEVEL,
                             TINY_EPD_1IN54_BUSY_TIMEOUT_MS);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, TINY_EPD_1IN54_BUSY_SETTLE_MS);
    return TINY_EPD_OK;
}

static int epd_1in54_write_frame(tiny_epd_t *epd)
{
    const uint8_t *framebuffer = tiny_epd_framebuffer_const(epd);
    uint16_t y;
    uint16_t x;
    int ret;

    if (framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }

    /*
     * Keep the existing LuatOS epaper 1.54-inch addressing behavior:
     * SetWindow(0, 0, WIDTH, HEIGHT), then set cursor and stream one row
     * at a time. Some newer examples use WIDTH-1/HEIGHT-1, but this keeps
     * the first tiny_epd driver byte-for-byte close to the validated driver.
     */
    ret = epd_1in54_set_window(epd, 0, 0,
                               tiny_epd_native_width(epd),
                               tiny_epd_native_height(epd));
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    for (y = 0; y < tiny_epd_native_height(epd); y++) {
        ret = epd_1in54_set_cursor(epd, 0, y);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
        ret = tiny_epd_write_cmd(epd, 0x24);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
        for (x = 0; x < tiny_epd_stride(epd); x++) {
            ret = tiny_epd_write_data_byte(epd,
                                           framebuffer[((size_t)y * tiny_epd_stride(epd)) + x]);
            if (ret != TINY_EPD_OK) {
                return ret;
            }
        }
    }
    return TINY_EPD_OK;
}

static int epd_1in54_rect_to_window(const tiny_epd_t *epd,
                                    const tiny_epd_rect_t *rect,
                                    uint16_t *x_start,
                                    uint16_t *y_start,
                                    uint16_t *x_end,
                                    uint16_t *y_end)
{
    uint32_t rect_x_end;
    uint32_t rect_y_end;

    if (epd == NULL || rect == NULL || x_start == NULL || y_start == NULL ||
        x_end == NULL || y_end == NULL || rect->w == 0 || rect->h == 0) {
        return TINY_EPD_ERR_PARAM;
    }

    rect_x_end = (uint32_t)rect->x + rect->w;
    rect_y_end = (uint32_t)rect->y + rect->h;
    if (rect->x >= tiny_epd_native_width(epd) || rect->y >= tiny_epd_native_height(epd) ||
        rect_x_end > tiny_epd_native_width(epd) || rect_y_end > tiny_epd_native_height(epd)) {
        return TINY_EPD_ERR_PARAM;
    }

    /* The controller addresses X in bytes. Expand to preserve neighboring bits. */
    *x_start = (uint16_t)(rect->x & (uint16_t)~0x07u);
    *x_end = (uint16_t)(((rect_x_end - 1u) | 0x07u));
    *y_start = rect->y;
    *y_end = (uint16_t)(rect_y_end - 1u);
    return TINY_EPD_OK;
}

static int epd_1in54_write_frame_rect(tiny_epd_t *epd, const tiny_epd_rect_t *rect)
{
    const uint8_t *framebuffer = tiny_epd_framebuffer_const(epd);
    uint16_t x_start;
    uint16_t y_start;
    uint16_t x_end;
    uint16_t y_end;
    uint16_t x_start_byte;
    uint16_t bytes_per_row;
    uint16_t y;
    uint16_t x;
    int ret;

    if (framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }

    ret = epd_1in54_rect_to_window(epd, rect, &x_start, &y_start, &x_end, &y_end);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    x_start_byte = (uint16_t)(x_start >> 3);
    bytes_per_row = (uint16_t)((x_end >> 3) - x_start_byte + 1u);
    ret = epd_1in54_set_window(epd, x_start, y_start, x_end, y_end);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    for (y = y_start; y <= y_end; y++) {
        ret = epd_1in54_set_cursor(epd, x_start, y);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
        ret = tiny_epd_write_cmd(epd, 0x24);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
        for (x = 0; x < bytes_per_row; x++) {
            ret = tiny_epd_write_data_byte(epd,
                                           framebuffer[((size_t)y * tiny_epd_stride(epd)) +
                                                       x_start_byte + x]);
            if (ret != TINY_EPD_OK) {
                return ret;
            }
        }
    }
    return TINY_EPD_OK;
}

static int epd_1in54_init(tiny_epd_t *epd)
{
    static const tiny_epd_reset_step_t reset_steps[] = {
        {1, 200},
        {0, 2},
        {1, 200}
    };
    static const tiny_epd_reset_sequence_t reset_sequence = {
        reset_steps,
        sizeof(reset_steps) / sizeof(reset_steps[0])
    };
    tiny_epd_1in54_ctx_t *ctx = (tiny_epd_1in54_ctx_t *)tiny_epd_driver_state(epd);
    uint8_t data[3];
    int ret;

    if (ctx != NULL) {
        ctx->lut_loaded = 0;
        ctx->lut_mode = TINY_EPD_REFRESH_AUTO;
    }

    ret = tiny_epd_reset_panel(epd, &reset_sequence);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    data[0] = (uint8_t)((TINY_EPD_1IN54_HEIGHT - 1u) & 0xFFu);
    data[1] = (uint8_t)(((TINY_EPD_1IN54_HEIGHT - 1u) >> 8) & 0xFFu);
    data[2] = 0x00;
    ret = epd_1in54_cmd_data(epd, 0x01, data, 3);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    data[0] = 0xD7;
    data[1] = 0xD6;
    data[2] = 0x9D;
    ret = epd_1in54_cmd_data(epd, 0x0C, data, 3);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    ret = epd_1in54_cmd_data1(epd, 0x2C, 0xA8);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x3A, 0x1A);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x3B, 0x08);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x11, 0x03);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    return epd_1in54_load_lut(epd, TINY_EPD_REFRESH_FULL);
}

static int epd_1in54_refresh(tiny_epd_t *epd,
                             tiny_epd_refresh_mode_t mode,
                             const tiny_epd_rect_t *rect)
{
    uint16_t x_start;
    uint16_t y_start;
    uint16_t x_end;
    uint16_t y_end;
    int ret;

    if (mode == TINY_EPD_REFRESH_AUTO) {
        mode = TINY_EPD_REFRESH_FULL;
    }
    if (mode != TINY_EPD_REFRESH_FULL && mode != TINY_EPD_REFRESH_PARTIAL &&
        mode != TINY_EPD_REFRESH_PARTIAL_RECT) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    if ((mode == TINY_EPD_REFRESH_PARTIAL_RECT && rect == NULL) ||
        (mode != TINY_EPD_REFRESH_PARTIAL_RECT && rect != NULL)) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    if (mode == TINY_EPD_REFRESH_PARTIAL_RECT) {
        ret = epd_1in54_rect_to_window(epd, rect, &x_start, &y_start, &x_end, &y_end);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }

    ret = epd_1in54_load_lut(epd,
                              mode == TINY_EPD_REFRESH_PARTIAL_RECT ?
                              TINY_EPD_REFRESH_PARTIAL : mode);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = mode == TINY_EPD_REFRESH_PARTIAL_RECT ?
          epd_1in54_write_frame_rect(epd, rect) : epd_1in54_write_frame(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_1in54_turn_on_display(epd);
}

static int epd_1in54_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode)
{
    if (mode == TINY_EPD_SLEEP_AUTO) {
        mode = TINY_EPD_SLEEP_DEEP;
    }
    if (mode != TINY_EPD_SLEEP_DEEP) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    return epd_1in54_cmd_data1(epd, 0x10, 0x01);
}

static int epd_1in54_v2_wait_idle(tiny_epd_t *epd)
{
    int ret;

    tiny_epd_delay_ms(epd, TINY_EPD_1IN54_BUSY_SETTLE_MS);
    ret = tiny_epd_wait_busy(epd,
                             TINY_EPD_1IN54_BUSY_IDLE_LEVEL,
                             TINY_EPD_1IN54_BUSY_TIMEOUT_MS);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, TINY_EPD_1IN54_BUSY_SETTLE_MS);
    return TINY_EPD_OK;
}

static int epd_1in54_v2_turn_on_display(tiny_epd_t *epd)
{
    int ret;

    ret = epd_1in54_cmd_data1(epd, 0x22, 0xF7);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x20);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_1in54_v2_wait_idle(epd);
}

static int epd_1in54_v2_init(tiny_epd_t *epd)
{
    static const tiny_epd_reset_step_t reset_steps[] = {
        {1, 200},
        {0, 2},
        {1, 200}
    };
    static const tiny_epd_reset_sequence_t reset_sequence = {
        reset_steps,
        sizeof(reset_steps) / sizeof(reset_steps[0])
    };
    int ret;

    ret = tiny_epd_reset_panel(epd, &reset_sequence);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    ret = epd_1in54_v2_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x12);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_v2_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    {
        const uint8_t driver_output[] = {0xC7, 0x00, 0x01};
        ret = epd_1in54_cmd_data(epd, 0x01, driver_output, sizeof(driver_output));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    ret = epd_1in54_cmd_data1(epd, 0x11, 0x01);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    {
        const uint8_t x_window[] = {0x00, 0x18};
        ret = epd_1in54_cmd_data(epd, 0x44, x_window, sizeof(x_window));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    {
        const uint8_t y_window[] = {0xC7, 0x00, 0x00, 0x00};
        ret = epd_1in54_cmd_data(epd, 0x45, y_window, sizeof(y_window));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    ret = epd_1in54_cmd_data1(epd, 0x3C, 0x01);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x18, 0x80);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x22, 0xB1);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x20);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x4E, 0x00);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    {
        const uint8_t y_cursor[] = {0xC7, 0x00};
        ret = epd_1in54_cmd_data(epd, 0x4F, y_cursor, sizeof(y_cursor));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    return epd_1in54_v2_wait_idle(epd);
}

static int epd_1in54_v2_write_frame(tiny_epd_t *epd)
{
    const uint8_t *framebuffer = tiny_epd_framebuffer_const(epd);
    size_t i;
    int ret;

    if (framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_write_cmd(epd, 0x24);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    for (i = 0; i < tiny_epd_framebuffer_size(epd); i++) {
        ret = tiny_epd_write_data_byte(epd, framebuffer[i]);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    return TINY_EPD_OK;
}

static int epd_1in54_v2_refresh(tiny_epd_t *epd,
                                tiny_epd_refresh_mode_t mode,
                                const tiny_epd_rect_t *rect)
{
    int ret;

    if (mode == TINY_EPD_REFRESH_AUTO) {
        mode = TINY_EPD_REFRESH_FULL;
    }
    if (mode != TINY_EPD_REFRESH_FULL || rect != NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ret = epd_1in54_v2_write_frame(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_1in54_v2_turn_on_display(epd);
}

static int epd_1in54_v2_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode)
{
    int ret;

    if (mode == TINY_EPD_SLEEP_AUTO) {
        mode = TINY_EPD_SLEEP_DEEP;
    }
    if (mode != TINY_EPD_SLEEP_DEEP) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ret = epd_1in54_cmd_data1(epd, 0x10, 0x01);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, TINY_EPD_1IN54_BUSY_SETTLE_MS);
    return TINY_EPD_OK;
}

static const uint8_t g_1in54_v3_lut_vcom0[] = {
    0x02, 0x03, 0x03, 0x08, 0x08, 0x03, 0x05, 0x05,
    0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};
static const uint8_t g_1in54_v3_lut_w[] = {
    0x42, 0x43, 0x03, 0x48, 0x88, 0x03, 0x85, 0x08,
    0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};
static const uint8_t g_1in54_v3_lut_b[] = {
    0x82, 0x83, 0x03, 0x48, 0x88, 0x03, 0x05, 0x45,
    0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};
static const uint8_t g_1in54_v3_lut_g1[] = {
    0x82, 0x83, 0x03, 0x48, 0x88, 0x03, 0x05, 0x45,
    0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};
static const uint8_t g_1in54_v3_lut_g2[] = {
    0x82, 0x83, 0x03, 0x48, 0x88, 0x03, 0x05, 0x45,
    0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static int epd_1in54_v3_wait_idle(tiny_epd_t *epd)
{
    return tiny_epd_wait_busy(epd, 1u, TINY_EPD_1IN54_BUSY_TIMEOUT_MS);
}

static int epd_1in54_v3_load_lut(tiny_epd_t *epd)
{
    int ret;

    ret = epd_1in54_cmd_data(epd, 0x20, g_1in54_v3_lut_vcom0, sizeof(g_1in54_v3_lut_vcom0));
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data(epd, 0x21, g_1in54_v3_lut_w, sizeof(g_1in54_v3_lut_w));
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data(epd, 0x22, g_1in54_v3_lut_b, sizeof(g_1in54_v3_lut_b));
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data(epd, 0x23, g_1in54_v3_lut_g1, sizeof(g_1in54_v3_lut_g1));
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_1in54_cmd_data(epd, 0x24, g_1in54_v3_lut_g2, sizeof(g_1in54_v3_lut_g2));
}

static int epd_1in54_v3_init(tiny_epd_t *epd)
{
    static const tiny_epd_reset_step_t reset_steps[] = {
        {1, 200},
        {0, 10},
        {1, 200}
    };
    static const tiny_epd_reset_sequence_t reset_sequence = {
        reset_steps,
        sizeof(reset_steps) / sizeof(reset_steps[0])
    };
    int ret;

    ret = tiny_epd_reset_panel(epd, &reset_sequence);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    {
        const uint8_t power_setting[] = {0xC7, 0x00, 0x0D, 0x00};
        ret = epd_1in54_cmd_data(epd, 0x01, power_setting, sizeof(power_setting));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    ret = tiny_epd_write_cmd(epd, 0x04);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_v3_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x00, 0xDF);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x50, 0x77);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x30, 0x2A);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    {
        const uint8_t resolution[] = {0xC8, 0x00, 0xC8};
        ret = epd_1in54_cmd_data(epd, 0x61, resolution, sizeof(resolution));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    ret = epd_1in54_cmd_data1(epd, 0x82, 0x0A);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_1in54_v3_load_lut(epd);
}

static uint8_t epd_1in54_v3_pack_nibble(uint8_t value, uint8_t first_bit)
{
    uint8_t out = 0;
    uint8_t bit;

    for (bit = 0; bit < 4; bit++) {
        if ((value & (uint8_t)(0x80u >> (first_bit + bit))) != 0) {
            out |= (uint8_t)(0xC0u >> (bit * 2u));
        }
    }
    return out;
}

static int epd_1in54_v3_write_frame(tiny_epd_t *epd)
{
    const uint8_t *framebuffer = tiny_epd_framebuffer_const(epd);
    size_t i;
    int ret;

    if (framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_write_cmd(epd, 0x10);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    for (i = 0; i < tiny_epd_framebuffer_size(epd); i++) {
        ret = tiny_epd_write_data_byte(epd, epd_1in54_v3_pack_nibble(framebuffer[i], 0));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
        ret = tiny_epd_write_data_byte(epd, epd_1in54_v3_pack_nibble(framebuffer[i], 4));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    return TINY_EPD_OK;
}

static int epd_1in54_v3_turn_on_display(tiny_epd_t *epd)
{
    int ret;

    ret = epd_1in54_cmd_data1(epd, 0xE0, 0x01);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x12);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, TINY_EPD_1IN54_BUSY_SETTLE_MS);
    return epd_1in54_v3_wait_idle(epd);
}

static int epd_1in54_v3_refresh(tiny_epd_t *epd,
                                tiny_epd_refresh_mode_t mode,
                                const tiny_epd_rect_t *rect)
{
    int ret;

    if (mode == TINY_EPD_REFRESH_AUTO) {
        mode = TINY_EPD_REFRESH_FULL;
    }
    if (mode != TINY_EPD_REFRESH_FULL || rect != NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ret = epd_1in54_v3_write_frame(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_1in54_v3_turn_on_display(epd);
}

static int epd_1in54_v3_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode)
{
    int ret;

    if (mode == TINY_EPD_SLEEP_AUTO) {
        mode = TINY_EPD_SLEEP_DEEP;
    }
    if (mode != TINY_EPD_SLEEP_DEEP) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ret = epd_1in54_cmd_data1(epd, 0x82, 0x00);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    {
        const uint8_t power_setting[] = {0x02, 0x00, 0x00, 0x00};
        ret = epd_1in54_cmd_data(epd, 0x01, power_setting, sizeof(power_setting));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    tiny_epd_delay_ms(epd, 1500);
    ret = tiny_epd_write_cmd(epd, 0x02);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, TINY_EPD_1IN54_BUSY_SETTLE_MS);
    return TINY_EPD_OK;
}

/*
 * SSD1607-compatible 200x200 sequence based on the existing u8g2
 * u8x8_d_ssd1607_200x200 driver. This variant intentionally uses fixed
 * delays instead of BUSY because some boards leave BUSY unavailable or stuck
 * while still accepting the command sequence.
 */
static int epd_1in54_ssd1607_power_on(tiny_epd_t *epd)
{
    int ret;

    ret = epd_1in54_cmd_data1(epd, 0x22, 0xC0);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x20);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, 300);
    return TINY_EPD_OK;
}

static int epd_1in54_ssd1607_init(tiny_epd_t *epd)
{
    static const tiny_epd_reset_step_t reset_steps[] = {
        {1, 200},
        {0, 2},
        {1, 200}
    };
    static const tiny_epd_reset_sequence_t reset_sequence = {
        reset_steps,
        sizeof(reset_steps) / sizeof(reset_steps[0])
    };
    int ret;

    ret = tiny_epd_reset_panel(epd, &reset_sequence);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    {
        const uint8_t driver_output[] = {
            (uint8_t)((TINY_EPD_1IN54_HEIGHT - 1u) & 0xFFu),
            (uint8_t)(((TINY_EPD_1IN54_HEIGHT - 1u) >> 8) & 0xFFu),
            0x00
        };
        ret = epd_1in54_cmd_data(epd, 0x01, driver_output, sizeof(driver_output));
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    ret = epd_1in54_cmd_data1(epd, 0x03, 0x00);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x04, 0x0A);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x0F, 0x00);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0xF0, 0x1F);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x2C, 0xA8);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x3A, 0x1A);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x3B, 0x08);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x3C, 0x33);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x11, 0x03);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_set_window(epd, 0, 0,
                               (uint16_t)(TINY_EPD_1IN54_WIDTH - 1u),
                               (uint16_t)(TINY_EPD_1IN54_HEIGHT - 1u));
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_set_cursor(epd, 0, 0);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_1in54_ssd1607_power_on(epd);
}

static int epd_1in54_ssd1607_write_frame(tiny_epd_t *epd)
{
    const uint8_t *framebuffer = tiny_epd_framebuffer_const(epd);
    size_t i;
    int ret;

    if (framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = epd_1in54_set_window(epd, 0, 0,
                               (uint16_t)(TINY_EPD_1IN54_WIDTH - 1u),
                               (uint16_t)(TINY_EPD_1IN54_HEIGHT - 1u));
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_set_cursor(epd, 0, 0);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x24);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    for (i = 0; i < tiny_epd_framebuffer_size(epd); i++) {
        ret = tiny_epd_write_data_byte(epd, framebuffer[i]);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    return TINY_EPD_OK;
}

static int epd_1in54_ssd1607_turn_on_display(tiny_epd_t *epd)
{
    int ret;

    ret = epd_1in54_load_lut(epd, TINY_EPD_REFRESH_FULL);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_1in54_cmd_data1(epd, 0x22, 0x04);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x20);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, 1750);
    return TINY_EPD_OK;
}

static int epd_1in54_ssd1607_refresh(tiny_epd_t *epd,
                                     tiny_epd_refresh_mode_t mode,
                                     const tiny_epd_rect_t *rect)
{
    int ret;

    if (mode == TINY_EPD_REFRESH_AUTO) {
        mode = TINY_EPD_REFRESH_FULL;
    }
    if (mode != TINY_EPD_REFRESH_FULL || rect != NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ret = epd_1in54_ssd1607_write_frame(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_1in54_ssd1607_turn_on_display(epd);
}

static int epd_1in54_ssd1607_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode)
{
    int ret;

    if (mode == TINY_EPD_SLEEP_AUTO) {
        mode = TINY_EPD_SLEEP_STANDBY;
    }
    if (mode != TINY_EPD_SLEEP_STANDBY && mode != TINY_EPD_SLEEP_DEEP) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ret = epd_1in54_cmd_data1(epd, 0x22, 0x02);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0x20);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, 20);
    return TINY_EPD_OK;
}

static const tiny_epd_driver_t g_tiny_epd_1in54_driver = {
    "waveshare_1in54_bw",
    TINY_EPD_1IN54_WIDTH,
    TINY_EPD_1IN54_HEIGHT,
    1,
    1,
    TINY_EPD_CAP_REFRESH_FULL |
        TINY_EPD_CAP_REFRESH_PARTIAL |
        TINY_EPD_CAP_REFRESH_PARTIAL_RECT |
        TINY_EPD_CAP_LUT_MCU |
        TINY_EPD_CAP_SLEEP_DEEP |
        TINY_EPD_CAP_COLOR_BW,
    sizeof(tiny_epd_1in54_ctx_t),
    epd_1in54_init,
    epd_1in54_refresh,
    epd_1in54_sleep
};

static const tiny_epd_driver_t g_tiny_epd_1in54_v2_driver = {
    "waveshare_1in54_v2_bw",
    TINY_EPD_1IN54_WIDTH,
    TINY_EPD_1IN54_HEIGHT,
    1,
    1,
    TINY_EPD_CAP_REFRESH_FULL |
        TINY_EPD_CAP_SLEEP_DEEP |
        TINY_EPD_CAP_COLOR_BW,
    0,
    epd_1in54_v2_init,
    epd_1in54_v2_refresh,
    epd_1in54_v2_sleep
};

static const tiny_epd_driver_t g_tiny_epd_1in54_v3_driver = {
    "waveshare_1in54_v3_bw",
    TINY_EPD_1IN54_WIDTH,
    TINY_EPD_1IN54_HEIGHT,
    1,
    1,
    TINY_EPD_CAP_REFRESH_FULL |
        TINY_EPD_CAP_SLEEP_DEEP |
        TINY_EPD_CAP_COLOR_BW,
    0,
    epd_1in54_v3_init,
    epd_1in54_v3_refresh,
    epd_1in54_v3_sleep
};

static const tiny_epd_driver_t g_tiny_epd_1in54_ssd1607_driver = {
    "ssd1607_1in54_200x200_bw",
    TINY_EPD_1IN54_WIDTH,
    TINY_EPD_1IN54_HEIGHT,
    1,
    1,
    TINY_EPD_CAP_REFRESH_FULL |
        TINY_EPD_CAP_LUT_MCU |
        TINY_EPD_CAP_SLEEP_STANDBY |
        TINY_EPD_CAP_SLEEP_DEEP |
        TINY_EPD_CAP_COLOR_BW,
    sizeof(tiny_epd_1in54_ctx_t),
    epd_1in54_ssd1607_init,
    epd_1in54_ssd1607_refresh,
    epd_1in54_ssd1607_sleep
};

const tiny_epd_driver_t *tiny_epd_driver_1in54(void)
{
    return &g_tiny_epd_1in54_driver;
}

const tiny_epd_driver_t *tiny_epd_driver_1in54_v2(void)
{
    return &g_tiny_epd_1in54_v2_driver;
}

const tiny_epd_driver_t *tiny_epd_driver_1in54_v3(void)
{
    return &g_tiny_epd_1in54_v3_driver;
}

const tiny_epd_driver_t *tiny_epd_driver_1in54_ssd1607(void)
{
    return &g_tiny_epd_1in54_ssd1607_driver;
}
