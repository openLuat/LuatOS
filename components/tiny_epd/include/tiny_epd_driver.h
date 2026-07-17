#ifndef LUAT_TINY_EPD_DRIVER_H
#define LUAT_TINY_EPD_DRIVER_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

struct tiny_epd_driver {
    const char *name;
    uint16_t width;
    uint16_t height;
    uint8_t bits_per_pixel;
    uint8_t plane_count;
    uint32_t caps;
    size_t context_size;

    int (*init)(tiny_epd_t *epd);
    int (*refresh)(tiny_epd_t *epd,
                   tiny_epd_refresh_mode_t mode,
                   const tiny_epd_rect_t *rect);
    int (*sleep)(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode);
};

struct tiny_epd {
    const tiny_epd_driver_t *driver;
    tiny_epd_port_t port;
    uint16_t width;
    uint16_t height;
    uint16_t stride;
    uint8_t bits_per_pixel;
    uint8_t plane_count;
    uint8_t initialized;
    uint8_t sleeping;
    uint32_t caps;
    uint8_t *framebuffer;
    size_t framebuffer_size;
};

void *tiny_epd_driver_state(tiny_epd_t *epd);
const void *tiny_epd_driver_state_const(const tiny_epd_t *epd);

int tiny_epd_write_cmd(tiny_epd_t *epd, uint8_t cmd);
int tiny_epd_write_data(tiny_epd_t *epd, const uint8_t *data, size_t len);
int tiny_epd_write_data_byte(tiny_epd_t *epd, uint8_t data);
int tiny_epd_reset_panel(tiny_epd_t *epd, const tiny_epd_reset_sequence_t *sequence);
int tiny_epd_wait_busy(tiny_epd_t *epd, uint8_t idle_level, uint32_t timeout_ms);
void tiny_epd_delay_ms(tiny_epd_t *epd, uint32_t ms);

#ifdef __cplusplus
}
#endif

#endif
