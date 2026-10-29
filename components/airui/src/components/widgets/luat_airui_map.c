/**
 * @file luat_airui_map.c
 * @summary Bounded offline XYZ tile map, driven on the AIRUI/Lua thread.
 */
#include "luat_airui_map.h"
#include "luat_airui_binding.h"
#include "luat_malloc.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/draw/lv_image_decoder_private.h"
#include "lvgl9/src/draw/lv_draw_triangle.h"
#include "lvgl9/src/misc/cache/instance/lv_image_cache.h"
#include "lua.h"
#include "lauxlib.h"
#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define LUAT_LOG_TAG "airui.map"
#include "luat_log.h"

#ifdef LUAT_USE_AIRUI_MAP

#define MAP_PATH_MAX 256
#define MAP_MAX_TILES 128
#define MAP_TIMER_MS 30
#define MAP_DEFAULT_CACHE (8U * 1024U * 1024U)
#define MAP_PI 3.14159265358979323846

/*
 * GCJ02 forward transform adapted from X-TRACK GPS_Transform.c.
 * MIT License
 * Copyright (c) 2021 - 2024 _VIFEXTech
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

static double airui_map_clamp(double value, double minimum, double maximum)
{
    return value < minimum ? minimum : (value > maximum ? maximum : value);
}

static double airui_map_wrap(double value, double period)
{
    double wrapped = fmod(value, period);
    if (wrapped < 0.0) wrapped += period;
    /* Addition can round a tiny negative input to exactly period. */
    return wrapped >= period ? 0.0 : wrapped;
}

static double airui_map_normalize_lon(double lon)
{
    double result = fmod(lon, 360.0);
    if (result < -180.0) result += 360.0;
    if (result >= 180.0) result -= 360.0;
    return result;
}

static int airui_map_valid_outputs(double *first, double *second)
{
    return first != NULL && second != NULL && first != second;
}

int airui_map_geo_to_world(double lon, double lat, int zoom, double *x, double *y)
{
    double size, sin_lat, world_x, world_y;
    if (!airui_map_valid_outputs(x, y) || !isfinite(lon) || !isfinite(lat) ||
        zoom < AIRUI_MAP_ZOOM_MIN || zoom > AIRUI_MAP_ZOOM_MAX) return 0;

    lon = airui_map_normalize_lon(lon);
    lat = airui_map_clamp(lat, -AIRUI_MAP_MAX_LATITUDE, AIRUI_MAP_MAX_LATITUDE);
    size = ldexp((double)AIRUI_MAP_TILE_SIZE, zoom);
    sin_lat = sin(lat * MAP_PI / 180.0);
    world_x = (lon / 360.0 + 0.5) * size;
    world_y = (0.5 - log((1.0 + sin_lat) / (1.0 - sin_lat)) /
               (4.0 * MAP_PI)) * size;
    /* Preserve the half-open x domain after floating-point rounding. */
    *x = airui_map_wrap(world_x, size);
    *y = airui_map_clamp(world_y, 0.0, size);
    return 1;
}

int airui_map_world_to_geo(double x, double y, int zoom, double *lon, double *lat)
{
    double size, result_lon, result_lat;
    if (!airui_map_valid_outputs(lon, lat) || !isfinite(x) || !isfinite(y) ||
        zoom < AIRUI_MAP_ZOOM_MIN || zoom > AIRUI_MAP_ZOOM_MAX) return 0;

    size = ldexp((double)AIRUI_MAP_TILE_SIZE, zoom);
    result_lon = (airui_map_wrap(x, size) / size - 0.5) * 360.0;
    y = airui_map_clamp(y, 0.0, size);
    result_lat = atan(sinh(MAP_PI * (1.0 - 2.0 * y / size))) *
                 180.0 / MAP_PI;
    *lon = result_lon;
    *lat = airui_map_clamp(result_lat, -AIRUI_MAP_MAX_LATITUDE, AIRUI_MAP_MAX_LATITUDE);
    return 1;
}

static int airui_map_outside_gcj(double lon, double lat)
{
    return lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;
}

static void airui_map_gcj_forward(double lon, double lat, double *out_lon, double *out_lat)
{
    const double axis = 6378245.0;
    const double eccentricity_squared = 0.00669342162296594323;
    double x = lon - 105.0, y = lat - 35.0;
    double harmonics = (20.0 * sin(6.0 * x * MAP_PI) +
                        20.0 * sin(2.0 * x * MAP_PI)) * 2.0 / 3.0;
    double dlat = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y +
                  0.1 * x * y + 0.2 * sqrt(fabs(x)) + harmonics;
    double dlon = 300.0 + x + 2.0 * y + 0.1 * x * x +
                  0.1 * x * y + 0.1 * sqrt(fabs(x)) + harmonics;
    double rad_lat = lat * MAP_PI / 180.0;
    double sin_lat = sin(rad_lat);
    double magic = 1.0 - eccentricity_squared * sin_lat * sin_lat;
    double root_magic = sqrt(magic);

    dlat += (20.0 * sin(y * MAP_PI) + 40.0 * sin(y * MAP_PI / 3.0) +
             160.0 * sin(y * MAP_PI / 12.0) +
             320.0 * sin(y * MAP_PI / 30.0)) * 2.0 / 3.0;
    dlon += (20.0 * sin(x * MAP_PI) + 40.0 * sin(x * MAP_PI / 3.0) +
             150.0 * sin(x * MAP_PI / 12.0) +
             300.0 * sin(x * MAP_PI / 30.0)) * 2.0 / 3.0;
    *out_lat = lat + dlat * 180.0 /
               (axis * (1.0 - eccentricity_squared) / (magic * root_magic) * MAP_PI);
    *out_lon = lon + dlon * 180.0 / (axis / root_magic * cos(rad_lat) * MAP_PI);
}

int airui_map_convert_crs(double lon, double lat, int from_crs, int to_crs,
                          double *out_lon, double *out_lat)
{
    double result_lon, result_lat;
    if (!airui_map_valid_outputs(out_lon, out_lat) || !isfinite(lon) || !isfinite(lat) ||
        (from_crs != AIRUI_MAP_CRS_WGS84 && from_crs != AIRUI_MAP_CRS_GCJ02) ||
        (to_crs != AIRUI_MAP_CRS_WGS84 && to_crs != AIRUI_MAP_CRS_GCJ02)) return 0;

    lon = airui_map_normalize_lon(lon);
    lat = airui_map_clamp(lat, -90.0, 90.0);
    result_lon = lon;
    result_lat = lat;
    if (from_crs != to_crs && !airui_map_outside_gcj(lon, lat)) {
        if (from_crs == AIRUI_MAP_CRS_WGS84) {
            airui_map_gcj_forward(lon, lat, &result_lon, &result_lat);
        }
        else {
            int iteration, converged = 0;
            for (iteration = 0; iteration < 16; iteration++) {
                double forward_lon, forward_lat, error_lon, error_lat;
                airui_map_gcj_forward(result_lon, result_lat, &forward_lon, &forward_lat);
                error_lon = forward_lon - lon;
                error_lat = forward_lat - lat;
                if (fabs(error_lon) <= 1e-9 && fabs(error_lat) <= 1e-9) {
                    converged = 1;
                    break;
                }
                result_lon -= error_lon;
                result_lat -= error_lat;
            }
            if (!converged) return 0;
        }
    }
    if (!isfinite(result_lon) || !isfinite(result_lat)) return 0;
    *out_lon = airui_map_normalize_lon(result_lon);
    *out_lat = airui_map_clamp(result_lat, -90.0, 90.0);
    return 1;
}

typedef enum {
    MAP_TILE_UNUSED = 0,
    MAP_TILE_PENDING,
    MAP_TILE_READY,
    MAP_TILE_MISSING,
    MAP_TILE_FAILED,
    MAP_TILE_DEFERRED
} map_tile_state_t;

typedef struct {
    lv_obj_t *image;
    lv_image_decoder_dsc_t decoder;
    char path[MAP_PATH_MAX];
    int32_t x;
    int32_t y;
    int zoom;
    uint32_t bytes;
    uint8_t attempts;
    map_tile_state_t state;
    bool wanted;
    bool visible;
    bool opened;
} map_tile_t;

typedef struct {
    lv_obj_t *obj;
    lv_timer_t *timer;
    map_tile_t *tiles;
    int capacity;
    int w;
    int h;
    int zoom;
    int min_zoom;
    int max_zoom;
    int prefetch;
    int input_crs;
    int tile_crs;
    double center_x;
    double center_y;
    double position_lon;
    double position_lat;
    double heading;
    uint32_t bytes_used;
    uint32_t cache_bytes;
    uint32_t generation;
    uint32_t loaded_total;
    uint32_t decode_failures;
    char path_template[MAP_PATH_MAX];
    bool follow;
    bool draggable;
    bool position_valid;
    bool pressed;
    bool dragging;
    bool dirty;
    bool change_pending;
    bool click_pending;
    bool error_pending;
    bool ready_reported;
    lv_point_t press_point;
    lv_point_t last_point;
    double click_x;
    double click_y;
    int error_zoom;
    int32_t error_x;
    int32_t error_y;
    const char *error_reason;
    char error_path[MAP_PATH_MAX];
} airui_map_data_t;

static airui_map_data_t *map_data(lv_obj_t *obj)
{
    airui_component_meta_t *meta = airui_component_meta_get(obj);
    if (meta == NULL || meta->component_type != AIRUI_COMPONENT_MAP) return NULL;
    return (airui_map_data_t *)meta->user_data;
}

static int map_grid_capacity(int w, int h, int prefetch)
{
    return ((w + 255) / 256 + 1 + 2 * prefetch) *
           ((h + 255) / 256 + 1 + 2 * prefetch);
}

static double map_world_size(const airui_map_data_t *d)
{
    return ldexp(256.0, d->zoom);
}

static void map_normalize_center(airui_map_data_t *d)
{
    double size = map_world_size(d);
    d->center_x = fmod(d->center_x, size);
    if (d->center_x < 0.0) d->center_x += size;
    if (d->center_y < 0.0) d->center_y = 0.0;
    if (d->center_y > size) d->center_y = size;
}

static int32_t map_tile_x(int32_t x, int zoom)
{
    int32_t n = (int32_t)(1U << zoom);
    x %= n;
    return x < 0 ? x + n : x;
}

static void map_drop_pixels(airui_map_data_t *d, map_tile_t *tile, bool detach)
{
    if (detach && tile->image != NULL) {
        lv_obj_add_flag(tile->image, LV_OBJ_FLAG_HIDDEN);
        lv_image_set_src(tile->image, NULL);
    }
    if (tile->opened) {
        /* Variable images may have a header cache keyed by the decoded pointer. */
        if (tile->decoder.decoded != NULL) lv_image_cache_drop(tile->decoder.decoded);
        lv_image_decoder_close(&tile->decoder);
        tile->opened = false;
    }
    if (d->bytes_used >= tile->bytes) d->bytes_used -= tile->bytes;
    tile->bytes = 0;
    memset(&tile->decoder, 0, sizeof(tile->decoder));
}

static void map_release(void *ptr)
{
    airui_map_data_t *d = (airui_map_data_t *)ptr;
    if (d == NULL) return;
    if (d->timer != NULL) lv_timer_delete(d->timer);
    /* Parent deletion has started; never touch child objects from this hook. */
    for (int i = 0; i < d->capacity; i++) map_drop_pixels(d, &d->tiles[i], false);
    luat_heap_free(d->tiles);
    luat_heap_free(d);
}

static bool map_make_path(const char *pattern, int zoom, int32_t x, int32_t y,
                          char *out, size_t len)
{
    size_t used = 0;
    while (*pattern != '\0') {
        int value = 0;
        bool token = false;
        if (strncmp(pattern, "{z}", 3) == 0) { value = zoom; token = true; }
        else if (strncmp(pattern, "{x}", 3) == 0) { value = x; token = true; }
        else if (strncmp(pattern, "{y}", 3) == 0) { value = y; token = true; }
        if (token) {
            int n = snprintf(out + used, len - used, "%d", value);
            if (n < 0 || (size_t)n >= len - used) return false;
            used += (size_t)n;
            pattern += 3;
        } else {
            if (*pattern == '{' || *pattern == '}' || used + 1 >= len) return false;
            out[used++] = *pattern++;
        }
    }
    out[used] = '\0';
    return true;
}

static void map_position_tiles(airui_map_data_t *d)
{
    double size = map_world_size(d);
    for (int i = 0; i < d->capacity; i++) {
        map_tile_t *tile = &d->tiles[i];
        if (tile->state != MAP_TILE_READY || tile->zoom != d->zoom) {
            lv_obj_add_flag(tile->image, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        double x = tile->x * 256.0 - d->center_x + d->w * 0.5;
        double y = tile->y * 256.0 - d->center_y + d->h * 0.5;
        /* Keep existing images nearby while a drag crosses the world seam. */
        if (size > d->w + 512.0) {
            if (x < -size * 0.5) x += size;
            if (x > size * 0.5) x -= size;
        }
        if (x < -512.0 || x > d->w + 256.0 || y < -512.0 || y > d->h + 256.0) {
            lv_obj_add_flag(tile->image, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_set_pos(tile->image, (int32_t)floor(x), (int32_t)floor(y));
            lv_obj_remove_flag(tile->image, LV_OBJ_FLAG_HIDDEN);
        }
    }
    lv_obj_invalidate(d->obj);
}

static void map_changed(airui_map_data_t *d)
{
    map_normalize_center(d);
    d->generation++;
    d->dirty = true;
    d->change_pending = true;
    d->ready_reported = false;
    map_position_tiles(d);
    lv_timer_resume(d->timer);
}

static void map_rebuild(airui_map_data_t *d)
{
    int32_t n = (int32_t)(1U << d->zoom);
    double left = d->center_x - d->w * 0.5;
    double top = d->center_y - d->h * 0.5;
    int32_t x0 = (int32_t)floor(left / 256.0) - d->prefetch;
    int32_t y0 = (int32_t)floor(top / 256.0) - d->prefetch;
    int32_t x1 = (int32_t)floor((left + d->w - 0.00001) / 256.0) + d->prefetch;
    int32_t y1 = (int32_t)floor((top + d->h - 0.00001) / 256.0) + d->prefetch;
    if (y0 < 0) y0 = 0;
    if (y1 >= n) y1 = n - 1;

    for (int i = 0; i < d->capacity; i++) {
        map_tile_t *t = &d->tiles[i];
        t->wanted = t->state != MAP_TILE_UNUSED && t->zoom == d->zoom &&
                    t->x >= x0 && t->x <= x1 && t->y >= y0 && t->y <= y1;
        if (!t->wanted) {
            map_drop_pixels(d, t, true);
            t->state = MAP_TILE_UNUSED;
        }
    }
    /* Recycle obsolete slots before assigning new tiles, even when the pool was full. */
    for (int32_t y = y0; y <= y1; y++) {
        for (int32_t x = x0; x <= x1; x++) {
            map_tile_t *tile = NULL;
            map_tile_t *free_tile = NULL;
            for (int i = 0; i < d->capacity; i++) {
                map_tile_t *t = &d->tiles[i];
                if (t->wanted && t->x == x && t->y == y) { tile = t; break; }
                if (t->state == MAP_TILE_UNUSED && free_tile == NULL) free_tile = t;
            }
            if (tile == NULL) {
                tile = free_tile;
                if (tile == NULL) continue; /* Capacity is validated before creation/resize. */
                tile->x = x;
                tile->y = y;
                tile->zoom = d->zoom;
                tile->state = MAP_TILE_PENDING;
                tile->attempts = 0;
                tile->wanted = true;
                tile->path[0] = '\0';
            }
            tile->visible = x * 256.0 < left + d->w && (x + 1) * 256.0 > left &&
                            y * 256.0 < top + d->h && (y + 1) * 256.0 > top;
            if (tile->visible && tile->state == MAP_TILE_DEFERRED) {
                tile->state = MAP_TILE_PENDING;
                tile->attempts = 0;
            }
        }
    }
    d->dirty = false;
    map_position_tiles(d);
}

static void map_record_error(airui_map_data_t *d, map_tile_t *tile, const char *reason)
{
    d->error_zoom = tile->zoom;
    d->error_x = map_tile_x(tile->x, tile->zoom);
    d->error_y = tile->y;
    d->error_reason = reason;
    memcpy(d->error_path, tile->path, sizeof(d->error_path));
    d->error_pending = true;
}

static bool map_make_room(airui_map_data_t *d, map_tile_t *tile, uint32_t need)
{
    if (need > d->cache_bytes) return false;
    if (d->bytes_used <= d->cache_bytes - need) return true;
    if (!tile->visible) return false;
    /* Preloaded pixels must never displace visible pixels. */
    for (int i = 0; i < d->capacity; i++) {
        map_tile_t *t = &d->tiles[i];
        if (t != tile && !t->visible && t->state == MAP_TILE_READY) {
            map_drop_pixels(d, t, true);
            t->state = MAP_TILE_DEFERRED;
            if (d->bytes_used <= d->cache_bytes - need) return true;
        }
    }
    return false;
}

static void map_load_tile(airui_map_data_t *d, map_tile_t *tile)
{
    lv_fs_file_t file;
    lv_image_header_t header;
    lv_image_decoder_args_t args;
    uint64_t estimated;
    if (!map_make_path(d->path_template, tile->zoom, map_tile_x(tile->x, tile->zoom),
                       tile->y, tile->path, sizeof(tile->path))) {
        tile->state = MAP_TILE_FAILED;
        map_record_error(d, tile, "path_too_long");
        return;
    }
    if (lv_fs_open(&file, tile->path, LV_FS_MODE_RD) != LV_FS_RES_OK) {
        tile->state = MAP_TILE_MISSING;
        map_record_error(d, tile, "missing");
        return;
    }
    lv_fs_close(&file);
    memset(&header, 0, sizeof(header));
    if (lv_image_decoder_get_info(tile->path, &header) != LV_RESULT_OK ||
        header.w != 256 || header.h != 256) {
        tile->state = MAP_TILE_FAILED;
        d->decode_failures++;
        map_record_error(d, tile, "invalid_image");
        return;
    }
    /* Conservatively reserve ARGB8888 space before entering a decoder. */
    estimated = (uint64_t)256 * 256 * 4;
    if (header.stride > 1024) estimated = (uint64_t)header.stride * 256;
    if (estimated > UINT32_MAX || !map_make_room(d, tile, (uint32_t)estimated)) {
        tile->state = MAP_TILE_DEFERRED;
        map_record_error(d, tile, "cache_budget");
        return;
    }
    memset(&args, 0, sizeof(args));
    args.stride_align = true;
    args.premultiply = true;
    /* A retained decoder owns exactly one pixel buffer. Rendering uses that
       buffer directly, so the global image LRU cannot repeatedly evict it. */
    args.no_cache = true;
    memset(&tile->decoder, 0, sizeof(tile->decoder));
    tile->attempts++;
    if (lv_image_decoder_open(&tile->decoder, tile->path, &args) != LV_RESULT_OK) {
        memset(&tile->decoder, 0, sizeof(tile->decoder));
        d->decode_failures++;
        if (tile->attempts >= 2) {
            tile->state = MAP_TILE_FAILED;
            map_record_error(d, tile, "decode_failed");
        }
        return;
    }
    tile->opened = true;
    if (tile->decoder.decoded == NULL || tile->decoder.decoded->header.w != 256 ||
        tile->decoder.decoded->header.h != 256 ||
        tile->decoder.decoded->data_size > d->cache_bytes - d->bytes_used) {
        map_drop_pixels(d, tile, true);
        tile->state = MAP_TILE_FAILED;
        d->decode_failures++;
        map_record_error(d, tile, "decode_buffer");
        return;
    }
    tile->bytes = tile->decoder.decoded->data_size;
    d->bytes_used += tile->bytes;
    tile->state = MAP_TILE_READY;
    d->loaded_total++;
    lv_image_set_src(tile->image, tile->decoder.decoded);
    map_position_tiles(d);
}

int airui_map_get_stats(lv_obj_t *obj, airui_map_stats_t *stats)
{
    airui_map_data_t *d = map_data(obj);
    if (d == NULL || stats == NULL) return AIRUI_ERR_INVALID_PARAM;
    memset(stats, 0, sizeof(*stats));
    stats->generation = d->generation;
    stats->loaded_total = d->loaded_total;
    stats->decode_failures = d->decode_failures;
    stats->bytes_used = d->bytes_used;
    stats->cache_bytes = d->cache_bytes;
    stats->capacity = (uint16_t)d->capacity;
    for (int i = 0; i < d->capacity; i++) {
        map_tile_t *t = &d->tiles[i];
        if (!t->wanted) continue;
        if (t->visible) stats->visible++;
        if (t->visible && t->state == MAP_TILE_READY) stats->visible_ready++;
        switch (t->state) {
            case MAP_TILE_READY: stats->ready++; break;
            case MAP_TILE_PENDING: stats->pending++; break;
            case MAP_TILE_MISSING: stats->missing++; break;
            case MAP_TILE_FAILED: stats->failed++; break;
            case MAP_TILE_DEFERRED: stats->failed++; break;
            default: break;
        }
    }
    /* A view change is pending even if no old slot is marked pending yet. */
    if (d->dirty && stats->pending == 0) stats->pending = 1;
    return AIRUI_OK;
}

static int map_callback_event(const char *name)
{
    if (strcmp(name, "on_click") == 0) return AIRUI_EVENT_CLICKED;
    if (strcmp(name, "on_change") == 0) return AIRUI_EVENT_VALUE_CHANGED;
    if (strcmp(name, "on_ready") == 0) return AIRUI_EVENT_READY;
    if (strcmp(name, "on_tile_error") == 0) return AIRUI_EVENT_COMPLETE;
    return -1;
}

int airui_map_set_callback(lv_obj_t *obj, void *vm, int idx, const char *name)
{
    lua_State *L = (lua_State *)vm;
    airui_component_meta_t *meta = airui_component_meta_get(obj);
    int event = map_callback_event(name);
    if (map_data(obj) == NULL || L == NULL || event < 0) return AIRUI_ERR_INVALID_PARAM;
    if (!lua_isnoneornil(L, idx) && !lua_isfunction(L, idx)) return AIRUI_ERR_INVALID_PARAM;
    int ref = LUA_NOREF;
    if (lua_isfunction(L, idx)) {
        lua_pushvalue(L, idx);
        ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    return airui_component_set_callback_ref(meta, (airui_event_type_t)event, ref);
}

static void map_number_field(lua_State *L, const char *key, double value)
{
    lua_pushnumber(L, value);
    lua_setfield(L, -2, key);
}

static void map_dispatch(airui_map_data_t *d, int event)
{
    airui_component_meta_t *meta = airui_component_meta_get(d->obj);
    if (meta == NULL || meta->ctx == NULL || meta->ctx->L == NULL) return;
    lua_State *L = (lua_State *)meta->ctx->L;
    int callback = meta->callback_refs[event];
    if (callback < 0) return;
    /* No widget state is accessed after Lua runs: callbacks can destroy this
       map, its parent, or the entire AIRUI context. */
    lua_rawgeti(L, LUA_REGISTRYINDEX, callback);
    airui_push_component_userdata(L, d->obj, AIRUI_MAP_MT);
    lua_createtable(L, 0, 12);
    double lon = 0.0, lat = 0.0;
    airui_map_get_center(d->obj, &lon, &lat);
    map_number_field(L, "lon", lon);
    map_number_field(L, "lat", lat);
    map_number_field(L, "zoom", d->zoom);
    map_number_field(L, "generation", d->generation);
    lua_pushboolean(L, d->follow);
    lua_setfield(L, -2, "follow");
    if (event == AIRUI_EVENT_CLICKED) {
        airui_map_screen_to_geo(d->obj, d->click_x, d->click_y, &lon, &lat);
        map_number_field(L, "lon", lon);
        map_number_field(L, "lat", lat);
        map_number_field(L, "x", d->click_x);
        map_number_field(L, "y", d->click_y);
    } else if (event == AIRUI_EVENT_COMPLETE) {
        map_number_field(L, "zoom", d->error_zoom);
        map_number_field(L, "x", d->error_x);
        map_number_field(L, "y", d->error_y);
        lua_pushstring(L, d->error_reason);
        lua_setfield(L, -2, "reason");
        lua_pushstring(L, d->error_path);
        lua_setfield(L, -2, "path");
    } else if (event == AIRUI_EVENT_READY) {
        airui_map_stats_t stats;
        airui_map_get_stats(d->obj, &stats);
        map_number_field(L, "ready", stats.ready);
        map_number_field(L, "missing", stats.missing);
        map_number_field(L, "failed", stats.failed);
    }
    if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
        LLOGE("callback: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
    }
}

static void map_timer(lv_timer_t *timer)
{
    airui_map_data_t *d = (airui_map_data_t *)lv_timer_get_user_data(timer);
    if (d == NULL || d->pressed || !lv_obj_is_visible(d->obj)) return;
    if (d->dirty) map_rebuild(d);
    map_tile_t *candidate = NULL;
    double nearest = 1e30;
    for (int i = 0; i < d->capacity; i++) {
        map_tile_t *t = &d->tiles[i];
        if (t->state != MAP_TILE_PENDING || !t->wanted) continue;
        double dx = (t->x + 0.5) * 256.0 - d->center_x;
        double dy = (t->y + 0.5) * 256.0 - d->center_y;
        double priority = dx * dx + dy * dy + (t->visible ? 0.0 : 1e20);
        if (priority < nearest) { nearest = priority; candidate = t; }
    }
    if (candidate != NULL) map_load_tile(d, candidate);
    /* Emit at most one event per tick, as the event may delete this timer. */
    if (d->error_pending) {
        d->error_pending = false;
        map_dispatch(d, AIRUI_EVENT_COMPLETE);
        return;
    }
    if (d->click_pending) {
        d->click_pending = false;
        map_dispatch(d, AIRUI_EVENT_CLICKED);
        return;
    }
    if (d->change_pending) {
        d->change_pending = false;
        map_dispatch(d, AIRUI_EVENT_VALUE_CHANGED);
        return;
    }
    if (candidate == NULL && !d->ready_reported) {
        d->ready_reported = true;
        map_dispatch(d, AIRUI_EVENT_READY);
    }
}

int airui_map_geo_to_screen(lv_obj_t *obj, double lon, double lat, double *x, double *y)
{
    airui_map_data_t *d = map_data(obj);
    double tx, ty, wx, wy;
    if (d == NULL || x == NULL || y == NULL ||
        !airui_map_convert_crs(lon, lat, d->input_crs, d->tile_crs, &tx, &ty) ||
        !airui_map_geo_to_world(tx, ty, d->zoom, &wx, &wy)) return AIRUI_ERR_INVALID_PARAM;
    double dx = wx - d->center_x;
    double size = map_world_size(d);
    if (dx > size * 0.5) dx -= size;
    if (dx < -size * 0.5) dx += size;
    *x = dx + d->w * 0.5;
    *y = wy - d->center_y + d->h * 0.5;
    return AIRUI_OK;
}

int airui_map_screen_to_geo(lv_obj_t *obj, double x, double y, double *lon, double *lat)
{
    airui_map_data_t *d = map_data(obj);
    double tx, ty;
    if (d == NULL || lon == NULL || lat == NULL || !isfinite(x) || !isfinite(y) ||
        fabs(x) > 1e12 || fabs(y) > 1e12 ||
        !airui_map_world_to_geo(d->center_x + x - d->w * 0.5,
                                 d->center_y + y - d->h * 0.5, d->zoom, &tx, &ty) ||
        !airui_map_convert_crs(tx, ty, d->tile_crs, d->input_crs, lon, lat))
        return AIRUI_ERR_INVALID_PARAM;
    return AIRUI_OK;
}

int airui_map_get_center(lv_obj_t *obj, double *lon, double *lat)
{
    airui_map_data_t *d = map_data(obj);
    if (d == NULL) return AIRUI_ERR_INVALID_PARAM;
    return airui_map_screen_to_geo(obj, d->w * 0.5, d->h * 0.5, lon, lat);
}

int airui_map_set_center(lv_obj_t *obj, double lon, double lat)
{
    airui_map_data_t *d = map_data(obj);
    double tx, ty, wx, wy;
    if (d == NULL || !airui_map_convert_crs(lon, lat, d->input_crs, d->tile_crs, &tx, &ty) ||
        !airui_map_geo_to_world(tx, ty, d->zoom, &wx, &wy)) return AIRUI_ERR_INVALID_PARAM;
    d->center_x = wx;
    d->center_y = wy;
    map_changed(d);
    return AIRUI_OK;
}

int airui_map_set_zoom(lv_obj_t *obj, int zoom)
{
    airui_map_data_t *d = map_data(obj);
    if (d == NULL || zoom < AIRUI_MAP_ZOOM_MIN || zoom > AIRUI_MAP_ZOOM_MAX)
        return AIRUI_ERR_INVALID_PARAM;
    if (zoom < d->min_zoom || zoom > d->max_zoom) return AIRUI_ERR_INVALID_PARAM;
    if (zoom == d->zoom) return AIRUI_OK;
    d->center_x = ldexp(d->center_x, zoom - d->zoom);
    d->center_y = ldexp(d->center_y, zoom - d->zoom);
    d->zoom = zoom;
    map_changed(d);
    return AIRUI_OK;
}

int airui_map_get_zoom(lv_obj_t *obj)
{
    airui_map_data_t *d = map_data(obj);
    return d == NULL ? -1 : d->zoom;
}

int airui_map_set_position(lv_obj_t *obj, double lon, double lat, double heading, bool valid)
{
    airui_map_data_t *d = map_data(obj);
    double x, y;
    if (d == NULL || !isfinite(heading)) return AIRUI_ERR_INVALID_PARAM;
    if (valid && airui_map_geo_to_screen(obj, lon, lat, &x, &y) != AIRUI_OK)
        return AIRUI_ERR_INVALID_PARAM;
    d->position_valid = valid;
    d->position_lon = lon;
    d->position_lat = lat;
    d->heading = fmod(heading, 360.0);
    if (d->heading < 0.0) d->heading += 360.0;
    if (valid && d->follow) return airui_map_set_center(obj, lon, lat);
    lv_obj_invalidate(obj);
    return AIRUI_OK;
}

int airui_map_set_follow(lv_obj_t *obj, bool follow)
{
    airui_map_data_t *d = map_data(obj);
    if (d == NULL) return AIRUI_ERR_INVALID_PARAM;
    d->follow = follow;
    if (follow && d->position_valid)
        return airui_map_set_center(obj, d->position_lon, d->position_lat);
    d->change_pending = true;
    return AIRUI_OK;
}

bool airui_map_get_follow(lv_obj_t *obj)
{
    airui_map_data_t *d = map_data(obj);
    return d != NULL && d->follow;
}

int airui_map_set_draggable(lv_obj_t *obj, bool draggable)
{
    airui_map_data_t *d = map_data(obj);
    if (d == NULL) return AIRUI_ERR_INVALID_PARAM;
    d->draggable = draggable;
    return AIRUI_OK;
}

int airui_map_set_size(lv_obj_t *obj, int w, int h)
{
    airui_map_data_t *d = map_data(obj);
    if (d == NULL || w < 1 || h < 1 || w > 4096 || h > 4096 ||
        map_grid_capacity(w, h, d->prefetch) > d->capacity) return AIRUI_ERR_INVALID_PARAM;
    d->w = w;
    d->h = h;
    lv_obj_set_size(obj, w, h);
    map_changed(d);
    return AIRUI_OK;
}

int airui_map_pan(lv_obj_t *obj, double dx, double dy)
{
    airui_map_data_t *d = map_data(obj);
    if (d == NULL || !isfinite(dx) || !isfinite(dy) || fabs(dx) > 1e12 || fabs(dy) > 1e12)
        return AIRUI_ERR_INVALID_PARAM;
    d->follow = false;
    d->center_x -= dx;
    d->center_y -= dy;
    map_changed(d);
    return AIRUI_OK;
}

int airui_map_refresh(lv_obj_t *obj)
{
    airui_map_data_t *d = map_data(obj);
    if (d == NULL) return AIRUI_ERR_INVALID_PARAM;
    for (int i = 0; i < d->capacity; i++) {
        map_tile_t *t = &d->tiles[i];
        map_drop_pixels(d, t, true);
        t->state = MAP_TILE_UNUSED;
        /* File headers must be refreshed too when a resource was replaced. */
        if (t->path[0] != '\0') lv_image_cache_drop(t->path);
    }
    map_changed(d);
    return AIRUI_OK;
}

static void map_draw_marker(lv_event_t *e, airui_map_data_t *d)
{
    double x, y;
    lv_area_t coords;
    lv_area_t area;
    lv_draw_rect_dsc_t dot;
    lv_draw_triangle_dsc_t arrow;
    lv_layer_t *layer = lv_event_get_layer(e);
    if (!d->position_valid || layer == NULL ||
        airui_map_geo_to_screen(d->obj, d->position_lon, d->position_lat, &x, &y) != AIRUI_OK ||
        x < -24 || y < -24 || x > d->w + 24 || y > d->h + 24) return;
    lv_obj_get_content_coords(d->obj, &coords);
    int32_t cx = coords.x1 + (int32_t)floor(x + 0.5);
    int32_t cy = coords.y1 + (int32_t)floor(y + 0.5);
    lv_draw_rect_dsc_init(&dot);
    dot.radius = LV_RADIUS_CIRCLE;
    dot.bg_color = lv_color_hex(0xffffff);
    dot.bg_opa = LV_OPA_COVER;
    dot.border_width = 2;
    dot.border_color = lv_color_hex(0x1769e0);
    dot.border_opa = LV_OPA_COVER;
    lv_area_set(&area, cx - 9, cy - 9, cx + 9, cy + 9);
    lv_draw_rect(layer, &dot, &area);
    lv_draw_triangle_dsc_init(&arrow);
    arrow.color = lv_color_hex(0x1769e0);
    arrow.opa = LV_OPA_COVER;
    double a = d->heading * MAP_PI / 180.0;
    const double px[3] = {0.0, -7.0, 7.0};
    const double py[3] = {-18.0, 7.0, 7.0};
    for (int i = 0; i < 3; i++) {
        arrow.p[i].x = cx + (int32_t)floor(px[i] * cos(a) - py[i] * sin(a) + 0.5);
        arrow.p[i].y = cy + (int32_t)floor(px[i] * sin(a) + py[i] * cos(a) + 0.5);
    }
    lv_draw_triangle(layer, &arrow);
}

static void map_event(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_current_target(e);
    airui_map_data_t *d = map_data(obj);
    if (d == NULL) return;
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_DRAW_POST) { map_draw_marker(e, d); return; }
    lv_indev_t *indev = lv_event_get_indev(e);
    lv_point_t point;
    if (indev == NULL) return;
    lv_indev_get_point(indev, &point);
    if (code == LV_EVENT_PRESSED) {
        d->pressed = true;
        d->dragging = false;
        d->press_point = point;
        d->last_point = point;
    } else if (code == LV_EVENT_PRESSING && d->pressed) {
        int32_t dx = point.x - d->press_point.x;
        int32_t dy = point.y - d->press_point.y;
        if (!d->dragging && (dx > 5 || dx < -5 || dy > 5 || dy < -5)) d->dragging = true;
        if (d->draggable && d->dragging &&
            (point.x != d->last_point.x || point.y != d->last_point.y)) {
            airui_map_pan(obj, point.x - d->last_point.x, point.y - d->last_point.y);
        }
        d->last_point = point;
    } else if (code == LV_EVENT_RELEASED || code == LV_EVENT_PRESS_LOST) {
        if (d->pressed && !d->dragging && code == LV_EVENT_RELEASED) {
            lv_area_t coords;
            lv_obj_get_content_coords(obj, &coords);
            d->click_x = point.x - coords.x1;
            d->click_y = point.y - coords.y1;
            d->click_pending = true;
        }
        d->pressed = false;
        d->dragging = false;
    }
}

static double map_config_number(lua_State *L, int idx, const char *key, double def,
                                 double min_value, double max_value, bool integer)
{
    lua_getfield(L, idx, key);
    double value = lua_isnil(L, -1) ? def : luaL_checknumber(L, -1);
    lua_pop(L, 1);
    if (!isfinite(value) || value < min_value || value > max_value ||
        (integer && floor(value) != value)) luaL_error(L, "map: invalid %s", key);
    return value;
}

static int map_config_crs(lua_State *L, int idx, const char *key, const char *def)
{
    const char *value = airui_marshal_string(L, idx, key, def);
    if (strcmp(value, "wgs84") == 0) return AIRUI_MAP_CRS_WGS84;
    if (strcmp(value, "gcj02") == 0) return AIRUI_MAP_CRS_GCJ02;
    return luaL_error(L, "map: %s must be wgs84 or gcj02", key);
}

lv_obj_t *airui_map_create_from_config(void *vm, int idx)
{
    lua_State *L = (lua_State *)vm;
    if (L == NULL) return NULL;
    idx = lua_absindex(L, idx);
    luaL_checktype(L, idx, LUA_TTABLE);
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    airui_ctx_t *ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    lua_pop(L, 1);
    if (ctx == NULL) return NULL;
    /* Parse everything that can raise a Lua error before owning resources. */
    int x = (int)map_config_number(L, idx, "x", 0, -32768, 32767, true);
    int y = (int)map_config_number(L, idx, "y", 0, -32768, 32767, true);
    int w = (int)map_config_number(L, idx, "w", 320, 1, 4096, true);
    int h = (int)map_config_number(L, idx, "h", 240, 1, 4096, true);
    int min_zoom = (int)map_config_number(L, idx, "min_zoom", 0, 0, 22, true);
    int max_zoom = (int)map_config_number(L, idx, "max_zoom", 22, min_zoom, 22, true);
    int zoom = (int)map_config_number(L, idx, "zoom", 15, min_zoom, max_zoom, true);
    int prefetch = (int)map_config_number(L, idx, "prefetch", 0, 0, 1, true);
    int capacity = (int)map_config_number(L, idx, "max_tiles", 64, 1, MAP_MAX_TILES, true);
    uint32_t cache_bytes = (uint32_t)map_config_number(L, idx, "cache_bytes",
                                  MAP_DEFAULT_CACHE, 1, 64 * 1024 * 1024, true);
    if (map_grid_capacity(w, h, prefetch) > capacity) {
        luaL_error(L, "map: max_tiles too small for viewport/prefetch");
        return NULL;
    }
    int input_crs = map_config_crs(L, idx, "input_crs", "wgs84");
    bool follow = airui_marshal_bool(L, idx, "follow", true);
    bool draggable = airui_marshal_bool(L, idx, "draggable", true);
    const char *callbacks[] = {"on_click", "on_change", "on_ready", "on_tile_error"};
    for (int i = 0; i < 4; i++) {
        lua_getfield(L, idx, callbacks[i]);
        if (!lua_isnil(L, -1) && !lua_isfunction(L, -1)) luaL_error(L, "map: invalid %s", callbacks[i]);
        lua_pop(L, 1);
    }
    double lon = 0.0, lat = 0.0;
    lua_getfield(L, idx, "center");
    if (!lua_isnil(L, -1)) {
        luaL_checktype(L, -1, LUA_TTABLE);
        int center_idx = lua_gettop(L);
        lon = map_config_number(L, center_idx, "lon", 0, -1e12, 1e12, false);
        lat = map_config_number(L, center_idx, "lat", 0, -90, 90, false);
    }
    lua_pop(L, 1);
    lua_getfield(L, idx, "source");
    if (lua_isnil(L, -1)) { lua_pop(L, 1); lua_newtable(L); }
    luaL_checktype(L, -1, LUA_TTABLE);
    int source_idx = lua_gettop(L);
    const char *type = airui_marshal_string(L, source_idx, "type", "file");
    const char *scheme = airui_marshal_string(L, source_idx, "scheme", "xyz");
    if (strcmp(type, "file") != 0 || strcmp(scheme, "xyz") != 0)
        luaL_error(L, "map: only file/xyz sources are supported");
    int tile_crs = map_config_crs(L, source_idx, "crs", "wgs84");
    char pattern[MAP_PATH_MAX] = {0};
    const char *custom = airui_marshal_string(L, source_idx, "path_template", NULL);
    if (custom != NULL) {
        if (strlen(custom) >= sizeof(pattern)) luaL_error(L, "map: path_template too long");
        memcpy(pattern, custom, strlen(custom) + 1);
    } else {
        const char *root = airui_marshal_string(L, source_idx, "root", "/sd/tiles");
        const char *format = airui_marshal_string(L, source_idx, "format", "jpg");
        if (strcmp(format, "jpg") != 0 && strcmp(format, "jpeg") != 0 && strcmp(format, "png") != 0)
            luaL_error(L, "map: format must be jpg/jpeg/png");
        int len = snprintf(pattern, sizeof(pattern), "%s/{z}/{x}/{y}.%s", root, format);
        if (len < 0 || len >= (int)sizeof(pattern)) luaL_error(L, "map: root path too long");
    }
    char check_path[MAP_PATH_MAX];
    if (pattern[0] != '/' || strstr(pattern, "{z}") == NULL || strstr(pattern, "{x}") == NULL ||
        strstr(pattern, "{y}") == NULL ||
        !map_make_path(pattern, 22, 4194303, 4194303, check_path, sizeof(check_path)))
        luaL_error(L, "map: invalid path_template (absolute path with {z}, {x}, {y} required)");
    lua_pop(L, 1);
    double tile_lon, tile_lat, wx, wy;
    if (!airui_map_convert_crs(lon, lat, input_crs, tile_crs, &tile_lon, &tile_lat) ||
        !airui_map_geo_to_world(tile_lon, tile_lat, zoom, &wx, &wy)) {
        luaL_error(L, "map: invalid center");
        return NULL;
    }
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    airui_map_data_t *d = luat_heap_malloc(sizeof(*d));
    if (d == NULL) return NULL;
    memset(d, 0, sizeof(*d));
    d->capacity = capacity;
    d->tiles = luat_heap_malloc(sizeof(map_tile_t) * (size_t)capacity);
    if (d->tiles == NULL) { luat_heap_free(d); return NULL; }
    memset(d->tiles, 0, sizeof(map_tile_t) * (size_t)capacity);
    lv_obj_t *obj = lv_obj_create(parent);
    if (obj == NULL) { luat_heap_free(d->tiles); luat_heap_free(d); return NULL; }
    d->obj = obj;
    d->w = w;
    d->h = h;
    d->zoom = zoom;
    d->min_zoom = min_zoom;
    d->max_zoom = max_zoom;
    d->prefetch = prefetch;
    d->input_crs = input_crs;
    d->tile_crs = tile_crs;
    d->cache_bytes = cache_bytes;
    d->follow = follow;
    d->draggable = draggable;
    d->center_x = wx;
    d->center_y = wy;
    memcpy(d->path_template, pattern, sizeof(pattern));
    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, obj, AIRUI_COMPONENT_MAP);
    if (meta == NULL) {
        lv_obj_delete(obj);
        luat_heap_free(d->tiles);
        luat_heap_free(d);
        return NULL;
    }
    airui_component_meta_set_user_data(meta, d, map_release);
    lv_obj_remove_style_all(obj);
    lv_obj_set_style_bg_color(obj, lv_color_hex(0xe0e5eb), 0);
    lv_obj_set_style_bg_opa(obj, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_all(obj, 0, 0);
    lv_obj_set_style_radius(obj, 0, 0);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_CHAIN);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_flag(obj, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(obj, x, y);
    lv_obj_set_size(obj, w, h);
    for (int i = 0; i < capacity; i++) {
        map_tile_t *tile = &d->tiles[i];
        tile->image = lv_image_create(obj);
        if (tile->image == NULL) { lv_obj_delete(obj); return NULL; }
        lv_obj_remove_flag(tile->image, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_remove_flag(tile->image, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_flag(tile->image, LV_OBJ_FLAG_IGNORE_LAYOUT);
        lv_obj_add_flag(tile->image, LV_OBJ_FLAG_HIDDEN);
    }
    d->timer = lv_timer_create(map_timer, MAP_TIMER_MS, d);
    if (d->timer == NULL) { lv_obj_delete(obj); return NULL; }
    const lv_event_code_t events[] = {LV_EVENT_PRESSED, LV_EVENT_PRESSING, LV_EVENT_RELEASED,
                                     LV_EVENT_PRESS_LOST, LV_EVENT_DRAW_POST};
    for (int i = 0; i < 5; i++) lv_obj_add_event_cb(obj, map_event, events[i], NULL);
    for (int i = 0; i < 4; i++) {
        lua_getfield(L, idx, callbacks[i]);
        airui_map_set_callback(obj, L, lua_gettop(L), callbacks[i]);
        lua_pop(L, 1);
    }
    map_changed(d);
    return obj;
}

#endif /* LUAT_USE_AIRUI_MAP */
