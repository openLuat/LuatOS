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

int tiny_epd_refresh(tiny_epd_t *epd,
                     tiny_epd_refresh_mode_t mode,
                     const tiny_epd_rect_t *rect)
{
    if (epd == NULL || epd->driver == NULL || epd->driver->refresh == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (!epd->initialized || epd->sleeping) {
        return TINY_EPD_ERR_BAD_STATE;
    }
    return epd->driver->refresh(epd, mode, rect);
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
    memset(epd->framebuffer, color ? 0xFF : 0x00, epd->framebuffer_size);
    return TINY_EPD_OK;
}

int tiny_epd_draw_pixel(tiny_epd_t *epd, int16_t x, int16_t y, uint8_t color)
{
    uint8_t *p;
    uint8_t mask;

    if (epd == NULL || epd->framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (epd->bits_per_pixel != 1 || epd->plane_count != 1) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
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
    return TINY_EPD_OK;
}

uint16_t tiny_epd_width(const tiny_epd_t *epd)
{
    return epd ? epd->width : 0;
}

uint16_t tiny_epd_height(const tiny_epd_t *epd)
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
