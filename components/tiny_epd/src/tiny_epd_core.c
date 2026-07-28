#include "tiny_epd_driver.h"

#include <stdlib.h>
#include <string.h>

static void *tiny_epd_default_malloc(void *user, size_t size)
{
    (void)user;
    return malloc(size);
}

static void tiny_epd_default_free(void *user, void *ptr)
{
    (void)user;
    free(ptr);
}

static void *tiny_epd_alloc(const tiny_epd_port_t *port, size_t size)
{
    if (port != NULL && port->malloc != NULL) {
        return port->malloc(port->user, size);
    }
    return tiny_epd_default_malloc(NULL, size);
}

static void tiny_epd_free_with_port(const tiny_epd_port_t *port, void *ptr)
{
    if (ptr == NULL) {
        return;
    }
    if (port != NULL && port->free != NULL) {
        port->free(port->user, ptr);
        return;
    }
    tiny_epd_default_free(NULL, ptr);
}

void *tiny_epd_port_alloc(tiny_epd_t *epd, size_t size)
{
    if (epd == NULL) {
        return NULL;
    }
    return tiny_epd_alloc(&epd->port, size);
}

void tiny_epd_port_free(tiny_epd_t *epd, void *ptr)
{
    if (epd != NULL) {
        tiny_epd_free_with_port(&epd->port, ptr);
    }
}

static int tiny_epd_calc_framebuffer_size(const tiny_epd_driver_t *driver,
                                          uint16_t *stride_out,
                                          size_t *size_out)
{
    size_t bits_per_line;
    size_t stride;
    size_t size;

    if (driver == NULL || stride_out == NULL || size_out == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (driver->width == 0 || driver->height == 0 ||
        driver->bits_per_pixel == 0 || driver->plane_count == 0) {
        return TINY_EPD_ERR_PARAM;
    }

    bits_per_line = (size_t)driver->width * (size_t)driver->bits_per_pixel;
    stride = (bits_per_line + 7u) / 8u;
    if (stride == 0 || stride > UINT16_MAX) {
        return TINY_EPD_ERR_PARAM;
    }
    if (driver->height > ((size_t)-1) / stride) {
        return TINY_EPD_ERR_PARAM;
    }
    size = stride * (size_t)driver->height;
    if (driver->plane_count > ((size_t)-1) / size) {
        return TINY_EPD_ERR_PARAM;
    }
    size *= (size_t)driver->plane_count;

    *stride_out = (uint16_t)stride;
    *size_out = size;
    return TINY_EPD_OK;
}

int tiny_epd_create(tiny_epd_t **out,
                    const tiny_epd_driver_t *driver,
                    const tiny_epd_port_t *port)
{
    tiny_epd_t *epd;
    uint16_t stride;
    size_t framebuffer_size;
    size_t object_size;
    int ret;

    if (out == NULL || driver == NULL || port == NULL ||
        port->write_cmd == NULL || port->write_data == NULL) {
        return TINY_EPD_ERR_PARAM;
    }

    *out = NULL;
    ret = tiny_epd_calc_framebuffer_size(driver, &stride, &framebuffer_size);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    if (driver->context_size > ((size_t)-1) - sizeof(tiny_epd_t)) {
        return TINY_EPD_ERR_PARAM;
    }
    object_size = sizeof(tiny_epd_t) + driver->context_size;

    epd = (tiny_epd_t *)tiny_epd_alloc(port, object_size);
    if (epd == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    memset(epd, 0, object_size);

    epd->framebuffer = (uint8_t *)tiny_epd_alloc(port, framebuffer_size);
    if (epd->framebuffer == NULL) {
        tiny_epd_free_with_port(port, epd);
        return TINY_EPD_ERR_NO_MEM;
    }
    memset(epd->framebuffer, 0xFF, framebuffer_size);

    epd->driver = driver;
    epd->port = *port;
    epd->width = driver->width;
    epd->height = driver->height;
    epd->stride = stride;
    epd->bits_per_pixel = driver->bits_per_pixel;
    epd->plane_count = driver->plane_count;
    epd->caps = driver->caps;
    epd->framebuffer_size = framebuffer_size;
    epd->rotate = 0;
    epd->dirty_rect.x = 0;
    epd->dirty_rect.y = 0;
    epd->dirty_rect.w = epd->width;
    epd->dirty_rect.h = epd->height;
    epd->dirty_valid = 1;

    *out = epd;
    return TINY_EPD_OK;
}

void tiny_epd_destroy(tiny_epd_t *epd)
{
    tiny_epd_port_t port;

    if (epd == NULL) {
        return;
    }
    port = epd->port;
    tiny_epd_free_with_port(&port, epd->framebuffer);
    epd->framebuffer = NULL;
    tiny_epd_free_with_port(&port, epd);
}

int tiny_epd_init(tiny_epd_t *epd)
{
    int ret;

    if (epd == NULL || epd->driver == NULL || epd->driver->init == NULL) {
        return TINY_EPD_ERR_PARAM;
    }

    ret = epd->driver->init(epd);
    if (ret == TINY_EPD_OK) {
        epd->initialized = 1;
        epd->sleeping = 0;
    }
    return ret;
}

static int tiny_epd_refresh_check(const tiny_epd_t *epd)
{
    if (epd == NULL || epd->driver == NULL || epd->driver->refresh == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (!epd->initialized || epd->sleeping) {
        return TINY_EPD_ERR_BAD_STATE;
    }
    return TINY_EPD_OK;
}

static int tiny_epd_refresh_native(tiny_epd_t *epd,
                                   tiny_epd_refresh_mode_t mode,
                                   const tiny_epd_rect_t *native_rect)
{
    int ret;

    ret = tiny_epd_refresh_check(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    if ((mode == TINY_EPD_REFRESH_PARTIAL_RECT && native_rect == NULL) ||
        (mode != TINY_EPD_REFRESH_PARTIAL_RECT && native_rect != NULL)) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }

    ret = epd->driver->refresh(epd, mode, native_rect);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    if (mode == TINY_EPD_REFRESH_FULL || mode == TINY_EPD_REFRESH_PARTIAL ||
        mode == TINY_EPD_REFRESH_AUTO) {
        tiny_epd_clear_dirty(epd);
    }
    else if (epd->dirty_valid &&
             native_rect->x <= epd->dirty_rect.x && native_rect->y <= epd->dirty_rect.y &&
             (uint32_t)native_rect->x + native_rect->w >=
                 (uint32_t)epd->dirty_rect.x + epd->dirty_rect.w &&
             (uint32_t)native_rect->y + native_rect->h >=
                 (uint32_t)epd->dirty_rect.y + epd->dirty_rect.h) {
        tiny_epd_clear_dirty(epd);
    }
    return TINY_EPD_OK;
}

int tiny_epd_refresh(tiny_epd_t *epd,
                     tiny_epd_refresh_mode_t mode,
                     const tiny_epd_rect_t *rect)
{
    tiny_epd_rect_t native_rect;
    int ret;

    if (mode == TINY_EPD_REFRESH_PARTIAL_RECT) {
        ret = tiny_epd_map_rect_to_native(epd, rect, &native_rect);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
        return tiny_epd_refresh_native(epd, mode, &native_rect);
    }
    if (rect != NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    return tiny_epd_refresh_native(epd, mode, NULL);
}

static int tiny_epd_dirty_is_complete_panel(const tiny_epd_t *epd)
{
    return epd->dirty_rect.x == 0 && epd->dirty_rect.y == 0 &&
           epd->dirty_rect.w == epd->width && epd->dirty_rect.h == epd->height;
}

int tiny_epd_refresh_dirty(tiny_epd_t *epd, tiny_epd_refresh_mode_t mode)
{
    int ret;

    ret = tiny_epd_refresh_check(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    if (mode == TINY_EPD_REFRESH_PARTIAL_RECT) {
        if ((epd->caps & TINY_EPD_CAP_REFRESH_PARTIAL_RECT) == 0) {
            return TINY_EPD_ERR_UNSUPPORTED_MODE;
        }
        if (!epd->dirty_valid) {
            return TINY_EPD_OK;
        }
        return tiny_epd_refresh_native(epd, TINY_EPD_REFRESH_PARTIAL_RECT,
                                       &epd->dirty_rect);
    }

    if (mode == TINY_EPD_REFRESH_AUTO) {
        if (!epd->dirty_valid) {
            return TINY_EPD_OK;
        }
        if ((epd->caps & TINY_EPD_CAP_REFRESH_PARTIAL_RECT) != 0 &&
            !tiny_epd_dirty_is_complete_panel(epd)) {
            return tiny_epd_refresh_native(epd, TINY_EPD_REFRESH_PARTIAL_RECT,
                                           &epd->dirty_rect);
        }
        return tiny_epd_refresh_native(epd, TINY_EPD_REFRESH_FULL, NULL);
    }

    if (mode != TINY_EPD_REFRESH_FULL && mode != TINY_EPD_REFRESH_FAST &&
        mode != TINY_EPD_REFRESH_PARTIAL) {
        return TINY_EPD_ERR_PARAM;
    }
    return tiny_epd_refresh_native(epd, mode, NULL);
}

int tiny_epd_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode)
{
    int ret;

    if (epd == NULL || epd->driver == NULL || epd->driver->sleep == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (!epd->initialized) {
        return TINY_EPD_ERR_BAD_STATE;
    }

    ret = epd->driver->sleep(epd, mode);
    if (ret == TINY_EPD_OK) {
        epd->sleeping = 1;
    }
    return ret;
}

int tiny_epd_clear(tiny_epd_t *epd, uint8_t color)
{
    if (epd == NULL || epd->framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (epd->bits_per_pixel != 1 || epd->plane_count != 1) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    if (color > TINY_EPD_COLOR_WHITE) {
        return TINY_EPD_ERR_PARAM;
    }
    memset(epd->framebuffer, color ? 0xFF : 0x00, epd->framebuffer_size);
    epd->dirty_rect.x = 0;
    epd->dirty_rect.y = 0;
    epd->dirty_rect.w = epd->width;
    epd->dirty_rect.h = epd->height;
    epd->dirty_valid = 1;
    return TINY_EPD_OK;
}

static int tiny_epd_rotation_index(tiny_epd_rotation_t rotation, uint8_t *index)
{
    if (index == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    switch (rotation) {
    case TINY_EPD_ROTATE_0:
        *index = 0;
        return TINY_EPD_OK;
    case TINY_EPD_ROTATE_90:
        *index = 1;
        return TINY_EPD_OK;
    case TINY_EPD_ROTATE_180:
        *index = 2;
        return TINY_EPD_OK;
    case TINY_EPD_ROTATE_270:
        *index = 3;
        return TINY_EPD_OK;
    default:
        return TINY_EPD_ERR_PARAM;
    }
}

int tiny_epd_set_rotation(tiny_epd_t *epd, tiny_epd_rotation_t rotation)
{
    uint8_t index;
    int ret;

    if (epd == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_rotation_index(rotation, &index);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    epd->rotate = index;
    return TINY_EPD_OK;
}

tiny_epd_rotation_t tiny_epd_get_rotation(const tiny_epd_t *epd)
{
    if (epd == NULL) {
        return TINY_EPD_ROTATE_0;
    }
    switch (epd->rotate & 0x03u) {
    case 1u:
        return TINY_EPD_ROTATE_90;
    case 2u:
        return TINY_EPD_ROTATE_180;
    case 3u:
        return TINY_EPD_ROTATE_270;
    default:
        return TINY_EPD_ROTATE_0;
    }
}

int tiny_epd_map_point_to_native(const tiny_epd_t *epd,
                                 uint16_t x, uint16_t y,
                                 uint16_t *native_x, uint16_t *native_y)
{
    uint16_t logical_width;
    uint16_t logical_height;

    if (epd == NULL || native_x == NULL || native_y == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    logical_width = tiny_epd_width(epd);
    logical_height = tiny_epd_height(epd);
    if (x >= logical_width || y >= logical_height) {
        return TINY_EPD_ERR_PARAM;
    }

    switch (epd->rotate & 0x03u) {
    case 0:
        *native_x = x;
        *native_y = y;
        break;
    case 1: /* 90 degrees clockwise */
        *native_x = (uint16_t)(epd->width - 1u - y);
        *native_y = x;
        break;
    case 2:
        *native_x = (uint16_t)(epd->width - 1u - x);
        *native_y = (uint16_t)(epd->height - 1u - y);
        break;
    default: /* 270 degrees clockwise */
        *native_x = y;
        *native_y = (uint16_t)(epd->height - 1u - x);
        break;
    }
    return TINY_EPD_OK;
}

int tiny_epd_map_rect_to_native(const tiny_epd_t *epd,
                                const tiny_epd_rect_t *logical_rect,
                                tiny_epd_rect_t *native_rect)
{
    uint32_t x_end;
    uint32_t y_end;
    uint16_t xs[4];
    uint16_t ys[4];
    uint16_t min_x;
    uint16_t max_x;
    uint16_t min_y;
    uint16_t max_y;
    uint8_t i;

    if (epd == NULL || logical_rect == NULL || native_rect == NULL ||
        logical_rect->w == 0 || logical_rect->h == 0) {
        return TINY_EPD_ERR_PARAM;
    }
    x_end = (uint32_t)logical_rect->x + logical_rect->w;
    y_end = (uint32_t)logical_rect->y + logical_rect->h;
    if (logical_rect->x >= tiny_epd_width(epd) || logical_rect->y >= tiny_epd_height(epd) ||
        x_end > tiny_epd_width(epd) || y_end > tiny_epd_height(epd)) {
        return TINY_EPD_ERR_PARAM;
    }

    if (tiny_epd_map_point_to_native(epd, logical_rect->x, logical_rect->y, &xs[0], &ys[0]) != TINY_EPD_OK ||
        tiny_epd_map_point_to_native(epd, (uint16_t)(x_end - 1u), logical_rect->y, &xs[1], &ys[1]) != TINY_EPD_OK ||
        tiny_epd_map_point_to_native(epd, logical_rect->x, (uint16_t)(y_end - 1u), &xs[2], &ys[2]) != TINY_EPD_OK ||
        tiny_epd_map_point_to_native(epd, (uint16_t)(x_end - 1u), (uint16_t)(y_end - 1u), &xs[3], &ys[3]) != TINY_EPD_OK) {
        return TINY_EPD_ERR_PARAM;
    }
    min_x = max_x = xs[0];
    min_y = max_y = ys[0];
    for (i = 1; i < 4; i++) {
        if (xs[i] < min_x) min_x = xs[i];
        if (xs[i] > max_x) max_x = xs[i];
        if (ys[i] < min_y) min_y = ys[i];
        if (ys[i] > max_y) max_y = ys[i];
    }
    native_rect->x = min_x;
    native_rect->y = min_y;
    native_rect->w = (uint16_t)(max_x - min_x + 1u);
    native_rect->h = (uint16_t)(max_y - min_y + 1u);
    return TINY_EPD_OK;
}

int tiny_epd_draw_pixel_native(tiny_epd_t *epd, int16_t x, int16_t y, uint8_t color)
{
    uint8_t *p;
    uint8_t mask;

    if (epd == NULL || epd->framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (epd->bits_per_pixel != 1 || epd->plane_count != 1) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    if (color > TINY_EPD_COLOR_WHITE) {
        return TINY_EPD_ERR_PARAM;
    }
    if (x < 0 || y < 0 || x >= (int16_t)epd->width || y >= (int16_t)epd->height) {
        return TINY_EPD_ERR_PARAM;
    }

    p = epd->framebuffer + ((size_t)y * epd->stride) + ((uint16_t)x / 8u);
    mask = (uint8_t)(0x80u >> ((uint16_t)x & 0x07u));
    if (color) {
        *p |= mask;
    }
    else {
        *p &= (uint8_t)~mask;
    }
    {
        tiny_epd_rect_t rect;
        rect.x = (uint16_t)x;
        rect.y = (uint16_t)y;
        rect.w = 1;
        rect.h = 1;
        (void)tiny_epd_mark_dirty(epd, &rect);
    }
    return TINY_EPD_OK;
}

int tiny_epd_draw_pixel(tiny_epd_t *epd, int16_t x, int16_t y, uint8_t color)
{
    uint16_t native_x;
    uint16_t native_y;
    int ret;

    if (epd == NULL || x < 0 || y < 0) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_map_point_to_native(epd, (uint16_t)x, (uint16_t)y, &native_x, &native_y);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return tiny_epd_draw_pixel_native(epd, (int16_t)native_x, (int16_t)native_y, color);
}

uint16_t tiny_epd_width(const tiny_epd_t *epd)
{
    if (epd == NULL) {
        return 0;
    }
    return (epd->rotate & 0x01u) ? epd->height : epd->width;
}

uint16_t tiny_epd_height(const tiny_epd_t *epd)
{
    if (epd == NULL) {
        return 0;
    }
    return (epd->rotate & 0x01u) ? epd->width : epd->height;
}

uint16_t tiny_epd_native_width(const tiny_epd_t *epd)
{
    return epd ? epd->width : 0;
}

uint16_t tiny_epd_native_height(const tiny_epd_t *epd)
{
    return epd ? epd->height : 0;
}

uint16_t tiny_epd_stride(const tiny_epd_t *epd)
{
    return epd ? epd->stride : 0;
}

uint8_t tiny_epd_bits_per_pixel(const tiny_epd_t *epd)
{
    return epd ? epd->bits_per_pixel : 0;
}

uint8_t tiny_epd_plane_count(const tiny_epd_t *epd)
{
    return epd ? epd->plane_count : 0;
}

uint32_t tiny_epd_caps(const tiny_epd_t *epd)
{
    return epd ? epd->caps : 0;
}

uint16_t tiny_epd_rotate_get(const tiny_epd_t *epd)
{
    return (uint16_t)tiny_epd_get_rotation(epd);
}

int tiny_epd_mark_dirty(tiny_epd_t *epd, const tiny_epd_rect_t *native_rect)
{
    uint32_t x_end;
    uint32_t y_end;
    uint32_t dirty_x_end;
    uint32_t dirty_y_end;
    uint16_t x0;
    uint16_t y0;
    uint16_t x1;
    uint16_t y1;

    if (epd == NULL || native_rect == NULL || native_rect->w == 0 || native_rect->h == 0) {
        return TINY_EPD_ERR_PARAM;
    }
    x_end = (uint32_t)native_rect->x + native_rect->w;
    y_end = (uint32_t)native_rect->y + native_rect->h;
    if (native_rect->x >= epd->width || native_rect->y >= epd->height ||
        x_end > epd->width || y_end > epd->height) {
        return TINY_EPD_ERR_PARAM;
    }
    if (!epd->dirty_valid) {
        epd->dirty_rect = *native_rect;
        epd->dirty_valid = 1;
        return TINY_EPD_OK;
    }

    dirty_x_end = (uint32_t)epd->dirty_rect.x + epd->dirty_rect.w;
    dirty_y_end = (uint32_t)epd->dirty_rect.y + epd->dirty_rect.h;
    x0 = native_rect->x < epd->dirty_rect.x ? native_rect->x : epd->dirty_rect.x;
    y0 = native_rect->y < epd->dirty_rect.y ? native_rect->y : epd->dirty_rect.y;
    x1 = x_end > dirty_x_end ? (uint16_t)x_end : (uint16_t)dirty_x_end;
    y1 = y_end > dirty_y_end ? (uint16_t)y_end : (uint16_t)dirty_y_end;
    epd->dirty_rect.x = x0;
    epd->dirty_rect.y = y0;
    epd->dirty_rect.w = (uint16_t)(x1 - x0);
    epd->dirty_rect.h = (uint16_t)(y1 - y0);
    return TINY_EPD_OK;
}

int tiny_epd_get_dirty_rect(const tiny_epd_t *epd, tiny_epd_rect_t *native_rect)
{
    if (epd == NULL || native_rect == NULL || !epd->dirty_valid) {
        return TINY_EPD_ERR_BAD_STATE;
    }
    *native_rect = epd->dirty_rect;
    return TINY_EPD_OK;
}

void tiny_epd_clear_dirty(tiny_epd_t *epd)
{
    if (epd != NULL) {
        memset(&epd->dirty_rect, 0, sizeof(epd->dirty_rect));
        epd->dirty_valid = 0;
    }
}

uint8_t *tiny_epd_framebuffer(tiny_epd_t *epd)
{
    return epd ? epd->framebuffer : NULL;
}

const uint8_t *tiny_epd_framebuffer_const(const tiny_epd_t *epd)
{
    return epd ? epd->framebuffer : NULL;
}

size_t tiny_epd_framebuffer_size(const tiny_epd_t *epd)
{
    return epd ? epd->framebuffer_size : 0;
}

void *tiny_epd_driver_state(tiny_epd_t *epd)
{
    if (epd == NULL || epd->driver == NULL || epd->driver->context_size == 0) {
        return NULL;
    }
    return (void *)((uint8_t *)epd + sizeof(tiny_epd_t));
}

const void *tiny_epd_driver_state_const(const tiny_epd_t *epd)
{
    if (epd == NULL || epd->driver == NULL || epd->driver->context_size == 0) {
        return NULL;
    }
    return (const void *)((const uint8_t *)epd + sizeof(tiny_epd_t));
}

int tiny_epd_write_cmd(tiny_epd_t *epd, uint8_t cmd)
{
    if (epd == NULL || epd->port.write_cmd == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    return epd->port.write_cmd(epd->port.user, cmd) == 0 ? TINY_EPD_OK : TINY_EPD_ERR_IO;
}

int tiny_epd_write_data(tiny_epd_t *epd, const uint8_t *data, size_t len)
{
    if (epd == NULL || epd->port.write_data == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (len == 0) {
        return TINY_EPD_OK;
    }
    if (data == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    return epd->port.write_data(epd->port.user, data, len) == 0 ? TINY_EPD_OK : TINY_EPD_ERR_IO;
}

int tiny_epd_write_data_byte(tiny_epd_t *epd, uint8_t data)
{
    return tiny_epd_write_data(epd, &data, 1);
}

int tiny_epd_reset_panel(tiny_epd_t *epd, const tiny_epd_reset_sequence_t *sequence)
{
    if (epd == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (epd->port.reset == NULL) {
        return TINY_EPD_OK;
    }
    return epd->port.reset(epd->port.user, sequence) == 0 ? TINY_EPD_OK : TINY_EPD_ERR_IO;
}

int tiny_epd_wait_busy(tiny_epd_t *epd, uint8_t idle_level, uint32_t timeout_ms)
{
    if (epd == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (epd->port.wait_busy == NULL) {
        return TINY_EPD_OK;
    }
    return epd->port.wait_busy(epd->port.user, idle_level, timeout_ms) == 0 ?
           TINY_EPD_OK : TINY_EPD_ERR_BUSY_TIMEOUT;
}

void tiny_epd_delay_ms(tiny_epd_t *epd, uint32_t ms)
{
    if (epd != NULL && epd->port.delay_ms != NULL) {
        epd->port.delay_ms(epd->port.user, ms);
    }
}
