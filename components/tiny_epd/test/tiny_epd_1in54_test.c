#include "tiny_epd.h"
#include "tiny_epd_driver.h"
#include "tiny_epd_gfx.h"
#include "tiny_epd_hzfont.h"
#include "tiny_epd_qrcode.h"
#include "tiny_epd_port_example.h"
#include "tiny_epd_port_sim.h"

#include <stdio.h>
#include <string.h>

#define CHECK(expr) do { \
    if (!(expr)) { \
        printf("[tiny_epd_1in54_test] FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); \
        return 1; \
    } \
} while (0)

static const uint8_t g_expect_lut_full[] = {
    0x02, 0x02, 0x01, 0x11, 0x12, 0x12, 0x22, 0x22,
    0x66, 0x69, 0x69, 0x59, 0x58, 0x99, 0x99, 0x88,
    0x00, 0x00, 0x00, 0x00, 0xF8, 0xB4, 0x13, 0x51,
    0x35, 0x51, 0x51, 0x19, 0x01, 0x00
};

static const uint8_t g_expect_lut_partial[] = {
    0x10, 0x18, 0x18, 0x08, 0x18, 0x18, 0x08, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x13, 0x14, 0x44, 0x12,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static int buffer_is_value(const uint8_t *buf, size_t len, uint8_t value)
{
    size_t i;

    for (i = 0; i < len; i++) {
        if (buf[i] != value) {
            return 0;
        }
    }
    return 1;
}

static int check_lut_trace(tiny_epd_sim_t *sim, const uint8_t *lut, size_t len)
{
    return sim->cmd_count[0x32] == 1 &&
           sim->data_count[0x32] == len &&
           sim->checksum[0x32] == tiny_epd_sim_checksum_bytes(lut, len) &&
           sim->first_data[0x32] == lut[0] &&
           sim->last_data[0x32] == lut[len - 1u];
}

typedef struct {
    uint8_t dc_level;
    uint8_t rst_level;
    uint8_t busy_level;
    uint8_t last_spi_byte;
    uint32_t spi_bytes;
    uint64_t tick_ms;
} tiny_epd_example_hal_test_t;

static int tiny_epd_example_test_spi_write(void *user, const uint8_t *data, size_t len)
{
    tiny_epd_example_hal_test_t *hal = (tiny_epd_example_hal_test_t *)user;

    if (hal == NULL || (data == NULL && len != 0)) {
        return -1;
    }
    if (len != 0) {
        hal->last_spi_byte = data[len - 1u];
    }
    hal->spi_bytes += (uint32_t)len;
    return 0;
}

static int tiny_epd_example_test_gpio_write(void *user, int pin, uint8_t level)
{
    tiny_epd_example_hal_test_t *hal = (tiny_epd_example_hal_test_t *)user;

    if (hal == NULL) {
        return -1;
    }
    if (pin == 1) {
        hal->dc_level = level;
    }
    else if (pin == 2) {
        hal->rst_level = level;
    }
    else {
        return -1;
    }
    return 0;
}

static int tiny_epd_example_test_gpio_read(void *user, int pin)
{
    tiny_epd_example_hal_test_t *hal = (tiny_epd_example_hal_test_t *)user;

    if (hal == NULL || pin != 3) {
        return -1;
    }
    return hal->busy_level;
}

static uint64_t tiny_epd_example_test_tick_ms(void *user)
{
    tiny_epd_example_hal_test_t *hal = (tiny_epd_example_hal_test_t *)user;

    return hal ? hal->tick_ms : 0;
}

static void tiny_epd_example_test_delay_ms(void *user, uint32_t ms)
{
    tiny_epd_example_hal_test_t *hal = (tiny_epd_example_hal_test_t *)user;

    if (hal != NULL) {
        hal->tick_ms += ms;
    }
}

static int tiny_epd_test_port_example(void)
{
    tiny_epd_example_hal_test_t hal;
    tiny_epd_port_example_config_t config;
    tiny_epd_port_example_t ctx;
    tiny_epd_port_t port;
    const uint8_t data[] = {0x12, 0x34};
    const tiny_epd_reset_step_t reset_steps[] = {
        {0, 2},
        {1, 3}
    };
    const tiny_epd_reset_sequence_t reset = {reset_steps, 2};

    memset(&hal, 0, sizeof(hal));
    memset(&config, 0, sizeof(config));
    CHECK(tiny_epd_port_example_init(&port, &ctx, &config) == TINY_EPD_ERR_PARAM);

    config.hal.user = &hal;
    config.hal.spi_write = tiny_epd_example_test_spi_write;
    config.hal.gpio_write = tiny_epd_example_test_gpio_write;
    config.hal.gpio_read = tiny_epd_example_test_gpio_read;
    config.hal.tick_ms = tiny_epd_example_test_tick_ms;
    config.hal.delay_ms = tiny_epd_example_test_delay_ms;
    config.pin_dc = 1;
    config.pin_rst = 2;
    config.pin_busy = 3;
    config.busy_poll_ms = 10;
    CHECK(tiny_epd_port_example_init(&port, &ctx, &config) == TINY_EPD_OK);
    CHECK(port.write_cmd(port.user, 0xA5) == 0);
    CHECK(hal.dc_level == 0 && hal.spi_bytes == 1 && hal.last_spi_byte == 0xA5);
    CHECK(port.write_data(port.user, data, sizeof(data)) == 0);
    CHECK(hal.dc_level == 1 && hal.spi_bytes == 3 && hal.last_spi_byte == 0x34);
    CHECK(port.reset(port.user, &reset) == 0);
    CHECK(hal.rst_level == 1 && hal.tick_ms == 5);
    hal.busy_level = 0;
    CHECK(port.wait_busy(port.user, 0, 20) == 0);
    hal.busy_level = 1;
    CHECK(port.wait_busy(port.user, 0, 20) != 0);
    CHECK(hal.tick_ms == 25);
    return 0;
}

typedef struct {
    tiny_epd_rect_t last_rect;
    uint32_t refresh_count;
} tiny_epd_fake_driver_trace_t;

static tiny_epd_fake_driver_trace_t g_fake_driver_trace;

static int tiny_epd_fake_init(tiny_epd_t *epd)
{
    (void)epd;
    return TINY_EPD_OK;
}

static int tiny_epd_fake_refresh(tiny_epd_t *epd,
                                 tiny_epd_refresh_mode_t mode,
                                 const tiny_epd_rect_t *rect)
{
    (void)epd;
    if (mode != TINY_EPD_REFRESH_PARTIAL_RECT || rect == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    g_fake_driver_trace.last_rect = *rect;
    g_fake_driver_trace.refresh_count++;
    return TINY_EPD_OK;
}

static int tiny_epd_fake_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode)
{
    (void)epd;
    (void)mode;
    return TINY_EPD_OK;
}

/* Deliberately non-square: 90/270 rotation must swap public dimensions. */
static const tiny_epd_driver_t g_tiny_epd_fake_122x250_driver = {
    "tiny_epd_test_122x250",
    122,
    250,
    1,
    1,
    TINY_EPD_CAP_REFRESH_PARTIAL_RECT | TINY_EPD_CAP_COLOR_BW,
    0,
    tiny_epd_fake_init,
    tiny_epd_fake_refresh,
    tiny_epd_fake_sleep
};

int main(void)
{
    tiny_epd_sim_t sim;
    tiny_epd_port_t port;
    tiny_epd_t *epd = NULL;
    uint8_t *fb;
    tiny_epd_rect_t rect;
    size_t fb_size;

    CHECK(tiny_epd_test_port_example() == 0);
    tiny_epd_sim_init(&sim);
    port = tiny_epd_sim_port(&sim);

    CHECK(tiny_epd_create(&epd, tiny_epd_driver_1in54(), &port) == TINY_EPD_OK);
    CHECK(epd != NULL);
    CHECK(tiny_epd_width(epd) == 200);
    CHECK(tiny_epd_height(epd) == 200);
    CHECK(tiny_epd_stride(epd) == 25);
    CHECK(tiny_epd_bits_per_pixel(epd) == 1);
    CHECK(tiny_epd_plane_count(epd) == 1);
    CHECK((tiny_epd_caps(epd) & TINY_EPD_CAP_REFRESH_FULL) != 0);
    CHECK((tiny_epd_caps(epd) & TINY_EPD_CAP_REFRESH_PARTIAL) != 0);
    CHECK((tiny_epd_caps(epd) & TINY_EPD_CAP_REFRESH_PARTIAL_RECT) != 0);
    CHECK((tiny_epd_caps(epd) & TINY_EPD_CAP_SLEEP_DEEP) != 0);

    fb = tiny_epd_framebuffer(epd);
    fb_size = tiny_epd_framebuffer_size(epd);
    CHECK(fb != NULL);
    CHECK(fb_size == 5000);
    CHECK(buffer_is_value(fb, fb_size, 0xFF));

    CHECK(tiny_epd_init(epd) == TINY_EPD_OK);
    CHECK(sim.reset_count == 1);
    CHECK(sim.reset_step_count == 3);
    CHECK(sim.delay_ms_total == 402);
    CHECK(sim.cmd_count[0x01] == 1);
    CHECK(sim.data_count[0x01] == 3);
    CHECK(sim.first_data[0x01] == 0xC7);
    CHECK(sim.last_data[0x01] == 0x00);
    CHECK(sim.cmd_count[0x0C] == 1);
    CHECK(sim.data_count[0x0C] == 3);
    CHECK(sim.cmd_count[0x2C] == 1);
    CHECK(sim.first_data[0x2C] == 0xA8);
    CHECK(sim.cmd_count[0x3A] == 1);
    CHECK(sim.first_data[0x3A] == 0x1A);
    CHECK(sim.cmd_count[0x3B] == 1);
    CHECK(sim.first_data[0x3B] == 0x08);
    CHECK(sim.cmd_count[0x11] == 1);
    CHECK(sim.first_data[0x11] == 0x03);
    CHECK(check_lut_trace(&sim, g_expect_lut_full, sizeof(g_expect_lut_full)));

    CHECK(tiny_epd_clear(epd, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
    CHECK(buffer_is_value(fb, fb_size, 0xFF));
    CHECK(tiny_epd_draw_pixel(epd, 0, 0, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
    CHECK(fb[0] == 0x7F);
    CHECK(tiny_epd_draw_pixel(epd, 7, 0, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
    CHECK(fb[0] == 0x7E);
    CHECK(tiny_epd_draw_pixel(epd, 8, 0, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
    CHECK(fb[1] == 0x7F);
    CHECK(tiny_epd_draw_pixel(epd, 8, 0, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
    CHECK(fb[1] == 0xFF);
    CHECK(tiny_epd_draw_pixel(epd, -1, 0, TINY_EPD_COLOR_BLACK) == TINY_EPD_ERR_PARAM);
    CHECK(tiny_epd_draw_pixel(epd, 200, 0, TINY_EPD_COLOR_BLACK) == TINY_EPD_ERR_PARAM);

    tiny_epd_sim_reset_trace(&sim);
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_FULL, NULL) == TINY_EPD_OK);
    CHECK(sim.cmd_count[0x44] == 1);
    CHECK(sim.cmd_count[0x45] == 1);
    CHECK(sim.cmd_count[0x4E] == 200);
    CHECK(sim.cmd_count[0x4F] == 200);
    CHECK(sim.cmd_count[0x24] == 200);
    CHECK(sim.data_count[0x24] == fb_size);
    CHECK(sim.cmd_count[0x22] == 1);
    CHECK(sim.first_data[0x22] == 0xC4);
    CHECK(sim.cmd_count[0x20] == 1);
    CHECK(sim.cmd_count[0xFF] == 1);
    CHECK(sim.busy_wait_count == 1);
    CHECK(sim.last_busy_idle_level == 0);

    tiny_epd_sim_reset_trace(&sim);
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_PARTIAL, NULL) == TINY_EPD_OK);
    CHECK(check_lut_trace(&sim, g_expect_lut_partial, sizeof(g_expect_lut_partial)));
    CHECK(sim.data_count[0x24] == fb_size);
    CHECK(sim.busy_wait_count == 1);

    /* x=9..18 expands to byte-aligned x=8..23, so three rows send six bytes. */
    fb[10u * tiny_epd_stride(epd) + 1u] = 0xA1;
    fb[10u * tiny_epd_stride(epd) + 2u] = 0xA2;
    fb[11u * tiny_epd_stride(epd) + 1u] = 0xB1;
    fb[11u * tiny_epd_stride(epd) + 2u] = 0xB2;
    fb[12u * tiny_epd_stride(epd) + 1u] = 0xC1;
    fb[12u * tiny_epd_stride(epd) + 2u] = 0xC2;
    rect.x = 9;
    rect.y = 10;
    rect.w = 10;
    rect.h = 3;
    tiny_epd_sim_reset_trace(&sim);
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_PARTIAL_RECT, &rect) == TINY_EPD_OK);
    /* The preceding whole-screen partial refresh already loaded this LUT. */
    CHECK(sim.cmd_count[0x32] == 0 && sim.data_count[0x32] == 0);
    CHECK(sim.cmd_count[0x44] == 1 && sim.data_count[0x44] == 2);
    CHECK(sim.first_data[0x44] == 1 && sim.last_data[0x44] == 2);
    CHECK(sim.cmd_count[0x45] == 1 && sim.data_count[0x45] == 4);
    CHECK(sim.first_data[0x45] == 10 && sim.last_data[0x45] == 0);
    CHECK(sim.cmd_count[0x4E] == 3 && sim.data_count[0x4E] == 3);
    CHECK(sim.first_data[0x4E] == 1 && sim.last_data[0x4E] == 1);
    CHECK(sim.cmd_count[0x4F] == 3 && sim.data_count[0x4F] == 6);
    CHECK(sim.cmd_count[0x24] == 3 && sim.data_count[0x24] == 6);
    {
        const uint8_t expect_rect_data[] = {0xA1, 0xA2, 0xB1, 0xB2, 0xC1, 0xC2};
        CHECK(sim.checksum[0x24] == tiny_epd_sim_checksum_bytes(expect_rect_data,
                                                                  sizeof(expect_rect_data)));
    }
    CHECK(sim.busy_wait_count == 1);

    tiny_epd_sim_reset_trace(&sim);
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_FULL, NULL) == TINY_EPD_OK);
    CHECK(check_lut_trace(&sim, g_expect_lut_full, sizeof(g_expect_lut_full)));
    CHECK(sim.data_count[0x24] == fb_size);

    rect.x = 0;
    rect.y = 0;
    rect.w = 0;
    rect.h = 1;
    tiny_epd_sim_reset_trace(&sim);
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_PARTIAL_RECT, &rect) == TINY_EPD_ERR_PARAM);
    CHECK(sim.write_cmd_total == 0 && sim.write_data_total == 0);
    rect.x = 199;
    rect.y = 199;
    rect.w = 2;
    rect.h = 1;
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_PARTIAL_RECT, &rect) == TINY_EPD_ERR_PARAM);
    CHECK(sim.write_cmd_total == 0 && sim.write_data_total == 0);
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_PARTIAL_RECT, NULL) == TINY_EPD_ERR_PARAM);
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_FAST, NULL) == TINY_EPD_ERR_UNSUPPORTED_MODE);

    tiny_epd_sim_reset_trace(&sim);
    CHECK(tiny_epd_sleep(epd, TINY_EPD_SLEEP_DEEP) == TINY_EPD_OK);
    CHECK(sim.cmd_count[0x10] == 1);
    CHECK(sim.data_count[0x10] == 1);
    CHECK(sim.first_data[0x10] == 0x01);
    CHECK(tiny_epd_refresh(epd, TINY_EPD_REFRESH_FULL, NULL) == TINY_EPD_ERR_BAD_STATE);

    tiny_epd_destroy(epd);
    epd = NULL;

    /* ---------------------------------------------------------------- */
    /* Gfx primitives (line / rect / circle / qrcode) + rotation         */
    /* ---------------------------------------------------------------- */
    {
        tiny_epd_t *epd2 = NULL;
        uint8_t *fb2;
        size_t fb2_size;
        int i;
        int j;

        CHECK(tiny_epd_create(&epd2, tiny_epd_driver_1in54(), &port) == TINY_EPD_OK);
        CHECK(epd2 != NULL);
        fb2 = tiny_epd_framebuffer(epd2);
        fb2_size = tiny_epd_framebuffer_size(epd2);
        CHECK(fb2 != NULL);
        CHECK(fb2_size == 5000);

        /* (1) 270 must survive the public enum/API and expose correct degrees. */
        CHECK(tiny_epd_set_rotation(epd2, 90) == TINY_EPD_OK);
        CHECK(epd2->rotate == 1);
        CHECK(tiny_epd_set_rotation(epd2, 180) == TINY_EPD_OK);
        CHECK(epd2->rotate == 2);
        CHECK(tiny_epd_set_rotation(epd2, 270) == TINY_EPD_OK);
        CHECK(epd2->rotate == 3);
        CHECK(tiny_epd_rotate_get(epd2) == 270);
        CHECK(tiny_epd_set_rotation(epd2, 45) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_set_rotation(epd2, 0) == TINY_EPD_OK);
        CHECK(epd2->rotate == 0);

        /* (2) hline: 8-pixel horizontal at row 0 → byte 0 = 0x00. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_hline(epd2, 0, 0, 8, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        CHECK(fb2[0] == 0x00);
        CHECK(tiny_epd_draw_hline(epd2, 0, 0, 8, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(fb2[0] == 0xFF);

        /* (3) vline: 8-pixel vertical at col 0 → MSB of rows 0..7 is black. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_vline(epd2, 0, 0, 8, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        for (i = 0; i < 8; i++) {
            CHECK(fb2[i * tiny_epd_stride(epd2)] == 0x7F);
        }
        CHECK(fb2[8 * tiny_epd_stride(epd2)] == 0xFF); /* row 8 unaffected */

        /* (4) line axis-aligned: 8-pixel horizontal at (0,5) → fb2[5*25] = 0x00. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_line(epd2, 0, 5, 7, 5, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        CHECK(fb2[5 * tiny_epd_stride(epd2)] == 0x00);

        /* (5) line 45°: (0,0)→(9,9) → pixels (i,i) for i=0..9 are black. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_line(epd2, 0, 0, 9, 9, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        for (i = 0; i < 10; i++) {
            uint8_t byte = fb2[i * tiny_epd_stride(epd2) + (uint16_t)(i / 8u)];
            uint8_t mask = (uint8_t)(0x80u >> (i & 0x07u));
            CHECK((byte & mask) == 0);
        }

        /* (6) rotation 90°: a logical horizontal line becomes a physical
         * vertical line. pixel() uses exactly the same logical transform. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_set_rotation(epd2, 90) == TINY_EPD_OK);
        tiny_epd_clear_dirty(epd2);
        CHECK(tiny_epd_draw_pixel(epd2, 0, 0, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        {
            tiny_epd_rect_t dirty_rect;
            CHECK(tiny_epd_get_dirty_rect(epd2, &dirty_rect) == TINY_EPD_OK);
            CHECK(dirty_rect.x == 199 && dirty_rect.y == 0 &&
                  dirty_rect.w == 1 && dirty_rect.h == 1);
        }
        CHECK(tiny_epd_draw_hline(epd2, 0, 0, 6, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        for (j = 0; j <= 5; j++) {
            uint8_t byte = fb2[j * tiny_epd_stride(epd2) + (199u / 8u)];
            uint8_t mask = (uint8_t)(0x80u >> (199u & 0x07u));
            CHECK((byte & mask) == 0);
        }
        CHECK(tiny_epd_set_rotation(epd2, 0) == TINY_EPD_OK);

        /* (7) rect hollow: 8x8 outline, center (3,3) still white. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_rect(epd2, 0, 0, 7, 7,
                                 TINY_EPD_COLOR_BLACK, 0) == TINY_EPD_OK);
        /* Top edge byte 0 = 0x00 (all 8 bits black). */
        CHECK(fb2[0] == 0x00);
        /* Bottom edge at y=7, byte 0 = 0x00. */
        CHECK(fb2[7 * tiny_epd_stride(epd2)] == 0x00);
        /* Center pixel (3,3): byte 0 bit 4 should still be 1 (white). */
        CHECK((fb2[3 * tiny_epd_stride(epd2)] & 0x08u) != 0);

        /* (8) rect filled: 8x8 fill → 8 rows all 0x00. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_rect(epd2, 0, 0, 7, 7,
                                 TINY_EPD_COLOR_BLACK, 1) == TINY_EPD_OK);
        for (i = 0; i < 8; i++) {
            CHECK(fb2[i * tiny_epd_stride(epd2)] == 0x00);
        }

        /* (9) circle hollow: outline only, center (50,50) is still white. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_circle(epd2, 50, 50, 4,
                                   TINY_EPD_COLOR_BLACK, 0) == TINY_EPD_OK);
        /* Center (50,50) still white. */
        {
            uint8_t byte = fb2[50 * tiny_epd_stride(epd2) + (50u / 8u)];
            uint8_t mask = (uint8_t)(0x80u >> (50u & 0x07u));
            CHECK((byte & mask) != 0);
        }
        /* Cardinal top point (50, 50-4) = (50, 46) should be black. */
        {
            uint8_t byte = fb2[46 * tiny_epd_stride(epd2) + (50u / 8u)];
            uint8_t mask = (uint8_t)(0x80u >> (50u & 0x07u));
            CHECK((byte & mask) == 0);
        }

        /* (10) circle filled: center (50,50) is now black. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_circle(epd2, 50, 50, 4,
                                   TINY_EPD_COLOR_BLACK, 1) == TINY_EPD_OK);
        {
            uint8_t byte = fb2[50 * tiny_epd_stride(epd2) + (50u / 8u)];
            uint8_t mask = (uint8_t)(0x80u >> (50u & 0x07u));
            CHECK((byte & mask) == 0);
        }

        /* (11) QR code: encode "HI" at 33x33. The 21x21 symbol is centered
         *     with a 6-pixel margin, so row 6 enters the top-left finder. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_qrcode(epd2, 0, 0, "HI", 33,
                                   TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        /* Finder bits at x=6.. should make the first byte of row 6 non-white. */
        CHECK(fb2[6 * tiny_epd_stride(epd2)] != 0xFF);

        /* (12) Param guard: bad inputs return PARAM/UNSUPPORTED. */
        CHECK(tiny_epd_set_rotation(NULL, 0) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_draw_hline(NULL, 0, 0, 8, 0) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_draw_line(epd2, 0, 0, 0, 0, 7) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_draw_rect(epd2, 0, 0, 1, 1, 0, 7) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_draw_circle(epd2, 0, 0, 1, 0, 7) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_draw_qrcode(epd2, 0, 0, "HI", 1, 0) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_draw_qrcode(epd2, 190, 190, "HI", 20, 0) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_clear(epd2, 2) == TINY_EPD_ERR_PARAM);
        CHECK(tiny_epd_draw_pixel(epd2, 0, 0, 2) == TINY_EPD_ERR_PARAM);
        {
            tiny_epd_hzfont_style_t style;
            tiny_epd_hzfont_style_init(&style);
            CHECK(style.fg == TINY_EPD_COLOR_BLACK && style.bg == -1 &&
                  style.antialias == -1 && style.threshold == 128);
            CHECK(tiny_epd_hzfont_draw_utf8(epd2, 0, 0, "A", 12, &style) ==
                  TINY_EPD_ERR_UNSUPPORTED_MODE);
        }

        /* (13) gfx_hv_line: dir=0 equivalent to hline, dir=1 equivalent to vline. */
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_gfx_hv_line(epd2, 0, 10, 8, 0,
                                   TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        CHECK(fb2[10 * tiny_epd_stride(epd2)] == 0x00);
        CHECK(tiny_epd_clear(epd2, TINY_EPD_COLOR_WHITE) == TINY_EPD_OK);
        CHECK(tiny_epd_gfx_hv_line(epd2, 0, 0, 8, 1,
                                   TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        for (i = 0; i < 8; i++) {
            CHECK(fb2[i * tiny_epd_stride(epd2)] == 0x7F);
        }

        tiny_epd_destroy(epd2);
    }

    /* ---------------------------------------------------------------- */
    /* Non-square rotation and logical partial-rectangle mapping        */
    /* ---------------------------------------------------------------- */
    {
        tiny_epd_t *epd3 = NULL;

        memset(&g_fake_driver_trace, 0, sizeof(g_fake_driver_trace));
        CHECK(tiny_epd_create(&epd3, &g_tiny_epd_fake_122x250_driver, &port) == TINY_EPD_OK);
        CHECK(tiny_epd_init(epd3) == TINY_EPD_OK);
        CHECK(tiny_epd_width(epd3) == 122 && tiny_epd_height(epd3) == 250);
        CHECK(tiny_epd_set_rotation(epd3, TINY_EPD_ROTATE_90) == TINY_EPD_OK);
        CHECK(tiny_epd_width(epd3) == 250 && tiny_epd_height(epd3) == 122);
        CHECK(tiny_epd_native_width(epd3) == 122 && tiny_epd_native_height(epd3) == 250);
        {
            tiny_epd_rect_t logical_rect = {10, 20, 30, 40};
            CHECK(tiny_epd_refresh(epd3, TINY_EPD_REFRESH_PARTIAL_RECT, &logical_rect) == TINY_EPD_OK);
            /* (10..39,20..59) -> native x=62..101, y=10..39. */
            CHECK(g_fake_driver_trace.refresh_count == 1);
            CHECK(g_fake_driver_trace.last_rect.x == 62);
            CHECK(g_fake_driver_trace.last_rect.y == 10);
            CHECK(g_fake_driver_trace.last_rect.w == 40);
            CHECK(g_fake_driver_trace.last_rect.h == 30);
        }
        CHECK(tiny_epd_draw_pixel(epd3, 249, 121, TINY_EPD_COLOR_BLACK) == TINY_EPD_OK);
        CHECK(tiny_epd_draw_pixel(epd3, 250, 0, TINY_EPD_COLOR_BLACK) == TINY_EPD_ERR_PARAM);
        tiny_epd_destroy(epd3);
    }

    printf("[tiny_epd_1in54_test] PASS\n");
    return 0;
}
