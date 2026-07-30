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

/* The historic driver descriptor did not carry a surface. Keep that ABI
 * useful by supplying the exact old BLACK=0 / WHITE=1, MSB-first layout. */
static const tiny_epd_palette_entry_t g_tiny_epd_default_palette[] = {
    {TINY_EPD_COLOR_BLACK, 0u, 0x000000u},
    {TINY_EPD_COLOR_WHITE, 1u, 0xFFFFFFu}
};

static const tiny_epd_surface_desc_t g_tiny_epd_default_surface = {
    TINY_EPD_SURFACE_INDEX1,
    1u,
    1u,
    (uint16_t)(sizeof(g_tiny_epd_default_palette) / sizeof(g_tiny_epd_default_palette[0])),
    TINY_EPD_COLOR_WHITE,
    g_tiny_epd_default_palette
};

static const tiny_epd_surface_desc_t *tiny_epd_driver_surface(const tiny_epd_driver_t *driver)
{
    if (driver != NULL && driver->surface != NULL) {
        return driver->surface;
    }
    return &g_tiny_epd_default_surface;
}

static const tiny_epd_palette_entry_t *tiny_epd_palette_find_in_surface(
    const tiny_epd_surface_desc_t *surface, tiny_epd_color_t color)
{
    uint16_t i;

    if (surface == NULL || surface->palette == NULL) {
        return NULL;
    }
    for (i = 0; i < surface->palette_count; i++) {
        if (surface->palette[i].color == color) {
            return &surface->palette[i];
        }
    }
    return NULL;
}

static int tiny_epd_surface_storage_limit(const tiny_epd_surface_desc_t *surface,
                                          uint16_t *limit)
{
    if (surface == NULL || limit == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    switch (surface->format) {
    case TINY_EPD_SURFACE_INDEX1:
        *limit = 0x01u;
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX2:
        *limit = 0x03u;
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX4:
        *limit = 0x0Fu;
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX8:
        *limit = 0xFFu;
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_PLANAR1:
        if (surface->plane_count == 0 || surface->plane_count > 8u) {
            return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
        }
        *limit = (uint16_t)((1u << surface->plane_count) - 1u);
        return TINY_EPD_OK;
    default:
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
}

static int tiny_epd_validate_surface(const tiny_epd_driver_t *driver,
                                     const tiny_epd_surface_desc_t *surface)
{
    uint16_t storage_limit;
    uint16_t i;
    uint16_t j;
    int has_black = 0;
    int has_white = 0;

    if (driver == NULL || surface == NULL || surface->palette == NULL ||
        surface->palette_count == 0) {
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
    if (surface->bits_per_pixel != driver->bits_per_pixel ||
        surface->plane_count != driver->plane_count) {
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
    switch (surface->format) {
    case TINY_EPD_SURFACE_INDEX1:
        if (surface->bits_per_pixel != 1u || surface->plane_count != 1u ||
            surface->palette_count > 2u) {
            return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
        }
        break;
    case TINY_EPD_SURFACE_INDEX2:
        if (surface->bits_per_pixel != 2u || surface->plane_count != 1u ||
            surface->palette_count > 4u) {
            return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
        }
        break;
    case TINY_EPD_SURFACE_INDEX4:
        if (surface->bits_per_pixel != 4u || surface->plane_count != 1u ||
            surface->palette_count > 16u) {
            return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
        }
        break;
    case TINY_EPD_SURFACE_INDEX8:
        if (surface->bits_per_pixel != 8u || surface->plane_count != 1u ||
            surface->palette_count > 256u) {
            return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
        }
        break;
    case TINY_EPD_SURFACE_PLANAR1:
        if (surface->bits_per_pixel != 1u || surface->plane_count == 0u ||
            surface->plane_count > 8u || surface->palette_count > (1u << surface->plane_count)) {
            return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
        }
        break;
    default:
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
    if (tiny_epd_surface_storage_limit(surface, &storage_limit) != TINY_EPD_OK) {
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
    for (i = 0; i < surface->palette_count; i++) {
        const tiny_epd_palette_entry_t *entry = &surface->palette[i];

        if (entry->color == TINY_EPD_COLOR_FG || entry->color == TINY_EPD_COLOR_BG ||
            entry->storage_code > storage_limit) {
            return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
        }
        if (entry->color == TINY_EPD_COLOR_BLACK) {
            has_black = 1;
        }
        if (entry->color == TINY_EPD_COLOR_WHITE) {
            has_white = 1;
        }
        for (j = 0; j < i; j++) {
            if (surface->palette[j].color == entry->color ||
                surface->palette[j].storage_code == entry->storage_code) {
                return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
            }
        }
    }
    if (!has_black || !has_white ||
        tiny_epd_palette_find_in_surface(surface, surface->clear_color) == NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
    return TINY_EPD_OK;
}

static int tiny_epd_resolve_color(const tiny_epd_t *epd, tiny_epd_color_t requested,
                                  tiny_epd_color_t *resolved)
{
    tiny_epd_color_t color;

    if (epd == NULL || epd->surface == NULL || resolved == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (requested == TINY_EPD_COLOR_FG) {
        color = epd->foreground;
    }
    else if (requested == TINY_EPD_COLOR_BG) {
        color = epd->background;
    }
    else {
        color = requested;
    }
    if (tiny_epd_palette_find_in_surface(epd->surface, color) == NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_COLOR;
    }
    *resolved = color;
    return TINY_EPD_OK;
}

static int tiny_epd_storage_code_for_color(const tiny_epd_t *epd,
                                            tiny_epd_color_t requested,
                                            uint8_t *storage_code,
                                            tiny_epd_color_t *resolved_color)
{
    const tiny_epd_palette_entry_t *entry;
    tiny_epd_color_t color;
    int ret;

    if (storage_code == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_resolve_color(epd, requested, &color);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    entry = tiny_epd_palette_find_in_surface(epd->surface, color);
    if (entry == NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_COLOR;
    }
    *storage_code = entry->storage_code;
    if (resolved_color != NULL) {
        *resolved_color = color;
    }
    return TINY_EPD_OK;
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

static int tiny_epd_fill_framebuffer(tiny_epd_t *epd, uint8_t storage_code)
{
    uint8_t fill;

    if (epd == NULL || epd->framebuffer == NULL || epd->surface == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    switch (epd->surface->format) {
    case TINY_EPD_SURFACE_INDEX1:
        fill = storage_code == 0u ? 0x00u : 0xFFu;
        memset(epd->framebuffer, fill, epd->framebuffer_size);
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX2:
        fill = (uint8_t)(storage_code & 0x03u);
        fill = (uint8_t)(fill | (uint8_t)(fill << 2u));
        fill = (uint8_t)(fill | (uint8_t)(fill << 4u));
        memset(epd->framebuffer, fill, epd->framebuffer_size);
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX4:
        fill = (uint8_t)(storage_code & 0x0Fu);
        fill = (uint8_t)(fill | (uint8_t)(fill << 4u));
        memset(epd->framebuffer, fill, epd->framebuffer_size);
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX8:
        memset(epd->framebuffer, storage_code, epd->framebuffer_size);
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_PLANAR1:
    {
        size_t plane_size = (size_t)epd->stride * epd->height;
        uint8_t plane;

        for (plane = 0; plane < epd->plane_count; plane++) {
            fill = (storage_code & (uint8_t)(1u << plane)) != 0u ? 0xFFu : 0x00u;
            memset(epd->framebuffer + (size_t)plane * plane_size, fill, plane_size);
        }
        return TINY_EPD_OK;
    }
    default:
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
}

static int tiny_epd_write_native_storage(tiny_epd_t *epd, uint16_t x, uint16_t y,
                                         uint8_t storage_code)
{
    uint8_t *p;
    uint8_t shift;
    uint8_t mask;

    if (epd == NULL || epd->framebuffer == NULL || epd->surface == NULL ||
        x >= epd->width || y >= epd->height) {
        return TINY_EPD_ERR_PARAM;
    }
    switch (epd->surface->format) {
    case TINY_EPD_SURFACE_INDEX1:
        p = epd->framebuffer + (size_t)y * epd->stride + x / 8u;
        mask = (uint8_t)(0x80u >> (x & 0x07u));
        if ((storage_code & 0x01u) != 0u) {
            *p |= mask;
        }
        else {
            *p &= (uint8_t)~mask;
        }
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX2:
        p = epd->framebuffer + (size_t)y * epd->stride + x / 4u;
        shift = (uint8_t)(6u - ((x & 0x03u) * 2u));
        mask = (uint8_t)(0x03u << shift);
        *p = (uint8_t)((*p & (uint8_t)~mask) | ((storage_code & 0x03u) << shift));
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX4:
        p = epd->framebuffer + (size_t)y * epd->stride + x / 2u;
        shift = (x & 0x01u) == 0u ? 4u : 0u;
        mask = (uint8_t)(0x0Fu << shift);
        *p = (uint8_t)((*p & (uint8_t)~mask) | ((storage_code & 0x0Fu) << shift));
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_INDEX8:
        epd->framebuffer[(size_t)y * epd->stride + x] = storage_code;
        return TINY_EPD_OK;
    case TINY_EPD_SURFACE_PLANAR1:
    {
        size_t plane_size = (size_t)epd->stride * epd->height;
        uint8_t plane;

        mask = (uint8_t)(0x80u >> (x & 0x07u));
        for (plane = 0; plane < epd->plane_count; plane++) {
            p = epd->framebuffer + (size_t)plane * plane_size +
                (size_t)y * epd->stride + x / 8u;
            if ((storage_code & (uint8_t)(1u << plane)) != 0u) {
                *p |= mask;
            }
            else {
                *p &= (uint8_t)~mask;
            }
        }
        return TINY_EPD_OK;
    }
    default:
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
}

static int tiny_epd_read_native_storage(const tiny_epd_t *epd, uint16_t x, uint16_t y,
                                        uint8_t *storage_code)
{
    const uint8_t *p;
    uint8_t shift;
    uint8_t value = 0;

    if (epd == NULL || epd->framebuffer == NULL || epd->surface == NULL ||
        storage_code == NULL || x >= epd->width || y >= epd->height) {
        return TINY_EPD_ERR_PARAM;
    }
    switch (epd->surface->format) {
    case TINY_EPD_SURFACE_INDEX1:
        p = epd->framebuffer + (size_t)y * epd->stride + x / 8u;
        value = (uint8_t)((*p >> (7u - (x & 0x07u))) & 0x01u);
        break;
    case TINY_EPD_SURFACE_INDEX2:
        p = epd->framebuffer + (size_t)y * epd->stride + x / 4u;
        shift = (uint8_t)(6u - ((x & 0x03u) * 2u));
        value = (uint8_t)((*p >> shift) & 0x03u);
        break;
    case TINY_EPD_SURFACE_INDEX4:
        p = epd->framebuffer + (size_t)y * epd->stride + x / 2u;
        shift = (x & 0x01u) == 0u ? 4u : 0u;
        value = (uint8_t)((*p >> shift) & 0x0Fu);
        break;
    case TINY_EPD_SURFACE_INDEX8:
        value = epd->framebuffer[(size_t)y * epd->stride + x];
        break;
    case TINY_EPD_SURFACE_PLANAR1:
    {
        size_t plane_size = (size_t)epd->stride * epd->height;
        uint8_t plane;

        for (plane = 0; plane < epd->plane_count; plane++) {
            p = epd->framebuffer + (size_t)plane * plane_size +
                (size_t)y * epd->stride + x / 8u;
            if ((*p & (uint8_t)(0x80u >> (x & 0x07u))) != 0u) {
                value |= (uint8_t)(1u << plane);
            }
        }
        break;
    }
    default:
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
    *storage_code = value;
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
    const tiny_epd_surface_desc_t *surface;
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
    surface = tiny_epd_driver_surface(driver);
    ret = tiny_epd_validate_surface(driver, surface);
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
    epd->driver = driver;
    epd->port = *port;
    epd->width = driver->width;
    epd->height = driver->height;
    epd->stride = stride;
    epd->bits_per_pixel = driver->bits_per_pixel;
    epd->plane_count = driver->plane_count;
    epd->surface = surface;
    epd->foreground = TINY_EPD_COLOR_BLACK;
    epd->background = TINY_EPD_COLOR_WHITE;
    epd->caps = driver->caps;
    epd->framebuffer_size = framebuffer_size;
    epd->rotate = 0;
    {
        const tiny_epd_palette_entry_t *clear_entry =
            tiny_epd_palette_find_in_surface(surface, surface->clear_color);

        if (clear_entry == NULL ||
            tiny_epd_fill_framebuffer(epd, clear_entry->storage_code) != TINY_EPD_OK) {
            tiny_epd_free_with_port(port, epd->framebuffer);
            tiny_epd_free_with_port(port, epd);
            return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
        }
    }
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

int tiny_epd_color_set(tiny_epd_t *epd,
                       tiny_epd_color_t foreground,
                       tiny_epd_color_t background)
{
    if (epd == NULL || epd->surface == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    /* A state assignment must name two real palette colors, not recursively
     * refer to the old state through FG/BG sentinels. */
    if (foreground == TINY_EPD_COLOR_FG || foreground == TINY_EPD_COLOR_BG ||
        background == TINY_EPD_COLOR_FG || background == TINY_EPD_COLOR_BG ||
        tiny_epd_palette_find_in_surface(epd->surface, foreground) == NULL ||
        tiny_epd_palette_find_in_surface(epd->surface, background) == NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_COLOR;
    }
    epd->foreground = foreground;
    epd->background = background;
    return TINY_EPD_OK;
}

int tiny_epd_color_get(const tiny_epd_t *epd,
                       tiny_epd_color_t *foreground,
                       tiny_epd_color_t *background)
{
    if (epd == NULL || foreground == NULL || background == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    *foreground = epd->foreground;
    *background = epd->background;
    return TINY_EPD_OK;
}

int tiny_epd_color_supported(const tiny_epd_t *epd, tiny_epd_color_t color)
{
    tiny_epd_color_t resolved;

    return tiny_epd_resolve_color(epd, color, &resolved) == TINY_EPD_OK;
}

tiny_epd_surface_format_t tiny_epd_surface_format(const tiny_epd_t *epd)
{
    return epd != NULL && epd->surface != NULL ? epd->surface->format : 0;
}

uint16_t tiny_epd_palette_count(const tiny_epd_t *epd)
{
    return epd != NULL && epd->surface != NULL ? epd->surface->palette_count : 0;
}

int tiny_epd_palette_get(const tiny_epd_t *epd, uint16_t index,
                         tiny_epd_palette_entry_t *out)
{
    if (epd == NULL || epd->surface == NULL || out == NULL ||
        index >= epd->surface->palette_count) {
        return TINY_EPD_ERR_PARAM;
    }
    *out = epd->surface->palette[index];
    return TINY_EPD_OK;
}

int tiny_epd_clear(tiny_epd_t *epd, tiny_epd_color_t color)
{
    uint8_t storage_code;
    int ret;

    if (epd == NULL || epd->framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_storage_code_for_color(epd, color, &storage_code, NULL);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_fill_framebuffer(epd, storage_code);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
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

int tiny_epd_draw_pixel_native(tiny_epd_t *epd, int16_t x, int16_t y,
                               tiny_epd_color_t color)
{
    tiny_epd_rect_t rect;
    uint8_t storage_code;
    int ret;

    if (epd == NULL || epd->framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (x < 0 || y < 0 || x >= (int16_t)epd->width || y >= (int16_t)epd->height) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_storage_code_for_color(epd, color, &storage_code, NULL);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_native_storage(epd, (uint16_t)x, (uint16_t)y, storage_code);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    rect.x = (uint16_t)x;
    rect.y = (uint16_t)y;
    rect.w = 1;
    rect.h = 1;
    (void)tiny_epd_mark_dirty(epd, &rect);
    return TINY_EPD_OK;
}

int tiny_epd_get_pixel_native(const tiny_epd_t *epd, int16_t x, int16_t y,
                              tiny_epd_color_t *color)
{
    const tiny_epd_palette_entry_t *entry;
    uint8_t storage_code;
    int ret;

    if (epd == NULL || color == NULL || x < 0 || y < 0 ||
        x >= (int16_t)epd->width || y >= (int16_t)epd->height) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_read_native_storage(epd, (uint16_t)x, (uint16_t)y, &storage_code);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    if (epd->surface == NULL || epd->surface->palette == NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_FORMAT;
    }
    for (entry = epd->surface->palette;
         entry < epd->surface->palette + epd->surface->palette_count;
         entry++) {
        if (entry->storage_code == storage_code) {
            *color = entry->color;
            return TINY_EPD_OK;
        }
    }
    return TINY_EPD_ERR_UNSUPPORTED_COLOR;
}

int tiny_epd_draw_pixel(tiny_epd_t *epd, int16_t x, int16_t y, tiny_epd_color_t color)
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

int tiny_epd_get_pixel(const tiny_epd_t *epd, int16_t x, int16_t y,
                       tiny_epd_color_t *color)
{
    uint16_t native_x;
    uint16_t native_y;
    int ret;

    if (epd == NULL || color == NULL || x < 0 || y < 0) {
        return TINY_EPD_ERR_PARAM;
    }
    ret = tiny_epd_map_point_to_native(epd, (uint16_t)x, (uint16_t)y, &native_x, &native_y);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return tiny_epd_get_pixel_native(epd, (int16_t)native_x, (int16_t)native_y, color);
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
