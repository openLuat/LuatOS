#ifndef LUAT_TINY_EPD_H
#define LUAT_TINY_EPD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct tiny_epd tiny_epd_t;
typedef struct tiny_epd_driver tiny_epd_driver_t;

typedef enum {
    TINY_EPD_OK = 0,
    TINY_EPD_ERR_PARAM = -1,
    TINY_EPD_ERR_NO_MEM = -2,
    TINY_EPD_ERR_IO = -3,
    TINY_EPD_ERR_BUSY_TIMEOUT = -4,
    TINY_EPD_ERR_UNSUPPORTED_MODE = -5,
    TINY_EPD_ERR_BAD_STATE = -6,
    TINY_EPD_ERR_FONT_NOT_READY = -7
} tiny_epd_err_t;

typedef enum {
    TINY_EPD_REFRESH_AUTO = 0,
    TINY_EPD_REFRESH_FULL = 1,
    TINY_EPD_REFRESH_FAST = 2,
    /* Partial LUT with a complete framebuffer transfer. */
    TINY_EPD_REFRESH_PARTIAL = 3,
    TINY_EPD_REFRESH_PARTIAL_WAVEFORM = TINY_EPD_REFRESH_PARTIAL,
    /* Partial LUT with a driver-supported RAM rectangle transfer. */
    TINY_EPD_REFRESH_PARTIAL_RECT = 4
} tiny_epd_refresh_mode_t;

typedef enum {
    TINY_EPD_SLEEP_AUTO = 0,
    TINY_EPD_SLEEP_STANDBY = 1,
    TINY_EPD_SLEEP_DEEP = 2
} tiny_epd_sleep_mode_t;

/*
 * Rotation is part of the public logical canvas.  The framebuffer and every
 * driver still use their native panel orientation internally.
 */
typedef enum {
    TINY_EPD_ROTATE_0 = 0,
    TINY_EPD_ROTATE_90 = 90,
    TINY_EPD_ROTATE_180 = 180,
    TINY_EPD_ROTATE_270 = 270
} tiny_epd_rotation_t;

typedef struct {
    uint16_t x;
    uint16_t y;
    uint16_t w;
    uint16_t h;
} tiny_epd_rect_t;

typedef struct {
    uint8_t level;
    uint32_t delay_ms;
} tiny_epd_reset_step_t;

typedef struct {
    const tiny_epd_reset_step_t *steps;
    size_t count;
} tiny_epd_reset_sequence_t;

typedef struct {
    void *user;

    int (*write_cmd)(void *user, uint8_t cmd);
    int (*write_data)(void *user, const uint8_t *data, size_t len);
    int (*reset)(void *user, const tiny_epd_reset_sequence_t *sequence);
    int (*wait_busy)(void *user, uint8_t idle_level, uint32_t timeout_ms);
    void (*delay_ms)(void *user, uint32_t ms);

    void *(*malloc)(void *user, size_t size);
    void (*free)(void *user, void *ptr);
} tiny_epd_port_t;

#define TINY_EPD_COLOR_BLACK 0u
#define TINY_EPD_COLOR_WHITE 1u

#define TINY_EPD_CAP_REFRESH_FULL         (1u << 0)
#define TINY_EPD_CAP_REFRESH_FAST         (1u << 1)
#define TINY_EPD_CAP_REFRESH_PARTIAL      (1u << 2)
#define TINY_EPD_CAP_REFRESH_PARTIAL_RECT (1u << 3)
#define TINY_EPD_CAP_LUT_MCU              (1u << 8)
#define TINY_EPD_CAP_SLEEP_STANDBY        (1u << 16)
#define TINY_EPD_CAP_SLEEP_DEEP           (1u << 17)
#define TINY_EPD_CAP_COLOR_BW             (1u << 24)
#define TINY_EPD_CAP_COLOR_BWR            (1u << 25)
#define TINY_EPD_CAP_GRAY                 (1u << 26)

int tiny_epd_create(tiny_epd_t **out,
                    const tiny_epd_driver_t *driver,
                    const tiny_epd_port_t *port);
void tiny_epd_destroy(tiny_epd_t *epd);

int tiny_epd_init(tiny_epd_t *epd);
/* For PARTIAL_RECT, rect is expressed in the current logical coordinate space. */
int tiny_epd_refresh(tiny_epd_t *epd,
                     tiny_epd_refresh_mode_t mode,
                     const tiny_epd_rect_t *rect);
int tiny_epd_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode);

int tiny_epd_clear(tiny_epd_t *epd, uint8_t color);
/* Draw one pixel in the current logical coordinate space. */
int tiny_epd_draw_pixel(tiny_epd_t *epd, int16_t x, int16_t y, uint8_t color);

int tiny_epd_set_rotation(tiny_epd_t *epd, tiny_epd_rotation_t rotation);
tiny_epd_rotation_t tiny_epd_get_rotation(const tiny_epd_t *epd);

/* Logical canvas dimensions. They are swapped for 90/270 degree rotation. */
uint16_t tiny_epd_width(const tiny_epd_t *epd);
uint16_t tiny_epd_height(const tiny_epd_t *epd);
/* Native panel dimensions used by drivers and framebuffer addressing. */
uint16_t tiny_epd_native_width(const tiny_epd_t *epd);
uint16_t tiny_epd_native_height(const tiny_epd_t *epd);
uint16_t tiny_epd_stride(const tiny_epd_t *epd);
uint8_t tiny_epd_bits_per_pixel(const tiny_epd_t *epd);
uint8_t tiny_epd_plane_count(const tiny_epd_t *epd);
uint32_t tiny_epd_caps(const tiny_epd_t *epd);
/* Compatibility helper; returns 0/90/180/270 and is intentionally uint16_t. */
uint16_t tiny_epd_rotate_get(const tiny_epd_t *epd);

/* Dirty rectangles are native framebuffer coordinates. */
int tiny_epd_mark_dirty(tiny_epd_t *epd, const tiny_epd_rect_t *native_rect);
int tiny_epd_get_dirty_rect(const tiny_epd_t *epd, tiny_epd_rect_t *native_rect);
void tiny_epd_clear_dirty(tiny_epd_t *epd);

uint8_t *tiny_epd_framebuffer(tiny_epd_t *epd);
const uint8_t *tiny_epd_framebuffer_const(const tiny_epd_t *epd);
size_t tiny_epd_framebuffer_size(const tiny_epd_t *epd);

const tiny_epd_driver_t *tiny_epd_driver_1in54(void);
const tiny_epd_driver_t *tiny_epd_driver_1in54_v2(void);
const tiny_epd_driver_t *tiny_epd_driver_1in54_v3(void);
const tiny_epd_driver_t *tiny_epd_driver_1in54_ssd1607(void);

#ifdef __cplusplus
}
#endif

#endif
