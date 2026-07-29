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

    /* NULL selects the legacy BLACK/WHITE INDEX1 surface. Kept last so
     * positional legacy driver descriptors remain source compatible. */
    const tiny_epd_surface_desc_t *surface;
};

struct tiny_epd {
    const tiny_epd_driver_t *driver;
    tiny_epd_port_t port;
    /* Native panel dimensions. Public width/height accessors are logical. */
    uint16_t width;
    uint16_t height;
    uint16_t stride;
    uint8_t bits_per_pixel;
    uint8_t plane_count;
    const tiny_epd_surface_desc_t *surface;
    tiny_epd_color_t foreground;
    tiny_epd_color_t background;
    uint8_t initialized;
    uint8_t sleeping;
    uint8_t rotate; /* Internal index 0/1/2/3, never exposed directly. */
    uint32_t caps;
    uint8_t *framebuffer;
    size_t framebuffer_size;
    tiny_epd_rect_t dirty_rect;
    uint8_t dirty_valid;
};

void *tiny_epd_driver_state(tiny_epd_t *epd);
const void *tiny_epd_driver_state_const(const tiny_epd_t *epd);

/* Internal native-surface helpers for drivers and optional adapters. */
int tiny_epd_draw_pixel_native(tiny_epd_t *epd, int16_t x, int16_t y,
                               tiny_epd_color_t color);
int tiny_epd_get_pixel_native(const tiny_epd_t *epd, int16_t x, int16_t y,
                              tiny_epd_color_t *color);
int tiny_epd_map_point_to_native(const tiny_epd_t *epd,
                                 uint16_t x, uint16_t y,
                                 uint16_t *native_x, uint16_t *native_y);
int tiny_epd_map_rect_to_native(const tiny_epd_t *epd,
                                const tiny_epd_rect_t *logical_rect,
                                tiny_epd_rect_t *native_rect);
void *tiny_epd_port_alloc(tiny_epd_t *epd, size_t size);
void tiny_epd_port_free(tiny_epd_t *epd, void *ptr);

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
