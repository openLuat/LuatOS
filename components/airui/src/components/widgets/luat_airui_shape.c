/**
 * @file luat_airui_shape.c
 * @summary Shape 缁勪欢瀹炵幇
 */

#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/core/lv_obj_pos.h"
#include "lvgl9/src/draw/lv_draw_arc.h"
#include "lvgl9/src/draw/lv_draw_line.h"
#include "lvgl9/src/draw/lv_draw_rect.h"
#include "lvgl9/src/misc/lv_area_private.h"
#include "lvgl9/src/misc/lv_color_op.h"
#include "lua.h"
#include "lauxlib.h"
#include <math.h>
#include <stdint.h>
#include <string.h>

#define LUAT_LOG_TAG "airui_shape"
#include "luat_log.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef enum {
    AIRUI_SHAPE_ITEM_LINE = 1,
    AIRUI_SHAPE_ITEM_CIRCLE,
    AIRUI_SHAPE_ITEM_ELLIPSE,
    AIRUI_SHAPE_ITEM_RECT,
    AIRUI_SHAPE_ITEM_ARC
} airui_shape_item_type_t;

typedef struct {
    airui_shape_item_type_t type;
    lv_color_t color;
    lv_color_t fill_color;
    lv_color_t grad_color;
    lv_color_t fill_grad_color;
    lv_grad_dir_t grad_dir;
    lv_grad_dir_t fill_grad_dir;
    lv_opa_t opa;
    lv_opa_t fill_opa;
    int16_t width;
    int16_t dash_width;
    int16_t dash_gap;
    uint8_t fill;
    uint8_t round_start;
    uint8_t round_end;
    union {
        struct {
            int16_t x1;
            int16_t y1;
            int16_t x2;
            int16_t y2;
        } line;
        struct {
            int16_t cx;
            int16_t cy;
            int16_t r;
        } circle;
        struct {
            int16_t cx;
            int16_t cy;
            int16_t rx;
            int16_t ry;
            uint16_t segments;
        } ellipse;
        struct {
            int16_t x;
            int16_t y;
            int16_t w;
            int16_t h;
            int16_t radius;
        } rect;
        struct {
            int16_t cx;
            int16_t cy;
            int16_t r;
            int16_t start_angle;
            int16_t end_angle;
        } arc;
    } data;
} airui_shape_item_t;

typedef struct {
    airui_shape_item_t *items;
    uint16_t count;
    uint16_t capacity;
    int16_t max_stroke_width;
} airui_shape_data_t;

static airui_ctx_t *airui_shape_get_ctx(lua_State *L);
static airui_shape_data_t *airui_shape_get_data(lv_obj_t *shape);
static airui_shape_data_t *airui_shape_ensure_data(lv_obj_t *shape);
static void airui_shape_release_data(void *user_data);
static int airui_shape_ensure_capacity(airui_shape_data_t *data, uint16_t target);
static void airui_shape_recompute_metrics(airui_shape_data_t *data);
static int32_t airui_shape_round_double(double value);
static int airui_shape_parse_item(lua_State *L, int idx, airui_shape_item_t *item);
static void airui_shape_event_cb(lv_event_t *e);
static void airui_shape_draw(lv_event_t *e, airui_shape_data_t *data);
static void airui_shape_draw_line_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item);
static void airui_shape_draw_circle_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item);
static void airui_shape_draw_rect_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item);
static void airui_shape_draw_ellipse_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item);
static void airui_shape_prepare_arc_angles(int16_t start_in, int16_t end_in, int32_t *start_out, int32_t *end_out);
static void airui_shape_draw_arc_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item);

static airui_ctx_t *airui_shape_get_ctx(lua_State *L)
{
    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

static airui_shape_data_t *airui_shape_get_data(lv_obj_t *shape)
{
    airui_component_meta_t *meta = airui_component_meta_get(shape);
    if (meta == NULL) {
        return NULL;
    }
    return (airui_shape_data_t *)meta->user_data;
}

static airui_shape_data_t *airui_shape_ensure_data(lv_obj_t *shape)
{
    airui_component_meta_t *meta = airui_component_meta_get(shape);
    airui_shape_data_t *data;
    if (meta == NULL) {
        return NULL;
    }

    data = (airui_shape_data_t *)meta->user_data;
    if (data != NULL) {
        return data;
    }

    data = (airui_shape_data_t *)luat_heap_malloc(sizeof(airui_shape_data_t));
    if (data == NULL) {
        return NULL;
    }
    memset(data, 0, sizeof(airui_shape_data_t));
    airui_component_meta_set_user_data(meta, data, airui_shape_release_data);
    return data;
}

static void airui_shape_release_data(void *user_data)
{
    airui_shape_data_t *data = (airui_shape_data_t *)user_data;
    if (data == NULL) {
        return;
    }
    if (data->items != NULL) {
        luat_heap_free(data->items);
    }
    luat_heap_free(data);
}

static int airui_shape_ensure_capacity(airui_shape_data_t *data, uint16_t target)
{
    airui_shape_item_t *new_items;
    uint16_t new_capacity;

    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    if (target <= data->capacity) {
        return AIRUI_OK;
    }

    new_capacity = data->capacity == 0 ? 8 : data->capacity;
    while (new_capacity < target) {
        if (new_capacity > UINT16_MAX / 2) {
            new_capacity = target;
            break;
        }
        new_capacity = (uint16_t)(new_capacity * 2);
    }

    new_items = (airui_shape_item_t *)luat_heap_malloc(sizeof(airui_shape_item_t) * new_capacity);
    if (new_items == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    memset(new_items, 0, sizeof(airui_shape_item_t) * new_capacity);

    if (data->items != NULL && data->count > 0) {
        memcpy(new_items, data->items, sizeof(airui_shape_item_t) * data->count);
        luat_heap_free(data->items);
    }

    data->items = new_items;
    data->capacity = new_capacity;
    return AIRUI_OK;
}

static void airui_shape_recompute_metrics(airui_shape_data_t *data)
{
    uint16_t i;
    int16_t max_width = 1;

    if (data == NULL) {
        return;
    }

    for (i = 0; i < data->count; i++) {
        if (data->items[i].width > max_width) {
            max_width = data->items[i].width;
        }
    }
    data->max_stroke_width = max_width;
}

static int32_t airui_shape_round_double(double value)
{
    if (value >= 0.0) {
        return (int32_t)(value + 0.5);
    }
    return (int32_t)(value - 0.5);
}

static lv_grad_dir_t airui_shape_parse_gradient(lua_State *L, int idx, const char *color_key,
                                               const char *dir_key, lv_grad_dir_t default_dir,
                                               lv_color_t *color)
{
    lv_grad_dir_t dir = default_dir;
    bool has_color = airui_marshal_color(L, idx, color_key, color);
    bool has_dir = airui_marshal_grad_dir(L, idx, dir_key, &dir);
    lua_getfield(L, idx, dir_key);
    bool dir_present = !lua_isnil(L, -1);
    lua_pop(L, 1);
    if (dir_present && !has_dir) {
        LLOGW("%s currently supports only none/ver/hor (0/1/2); using solid color", dir_key);
        return LV_GRAD_DIR_NONE;
    }
    if (has_dir && dir == LV_GRAD_DIR_NONE) {
        return LV_GRAD_DIR_NONE;
    }
    if (!has_color) {
        if (has_dir) {
            LLOGW("%s requires %s; using solid color", dir_key, color_key);
        }
        return LV_GRAD_DIR_NONE;
    }
    return dir;
}

static void airui_shape_parse_gradients(lua_State *L, int idx, const char *type, airui_shape_item_t *item)
{
    lv_grad_dir_t line_dir = LV_GRAD_DIR_VER;
    if (item->type == AIRUI_SHAPE_ITEM_LINE && item->data.line.y1 == item->data.line.y2) {
        line_dir = LV_GRAD_DIR_HOR;
    }
    item->grad_dir = airui_shape_parse_gradient(L, idx, "grad_color", "grad_dir", line_dir, &item->grad_color);
    item->fill_grad_dir = airui_shape_parse_gradient(L, idx, "fill_grad_color", "fill_grad_dir",
                                                    LV_GRAD_DIR_VER, &item->fill_grad_color);
    if (item->grad_dir != LV_GRAD_DIR_NONE &&
        (item->type != AIRUI_SHAPE_ITEM_LINE ||
         (item->data.line.x1 != item->data.line.x2 && item->data.line.y1 != item->data.line.y2))) {
        LLOGW("%s stroke gradient is currently unsupported (only horizontal/vertical lines); using solid color", type);
        item->grad_dir = LV_GRAD_DIR_NONE;
    }
    if (item->fill_grad_dir != LV_GRAD_DIR_NONE &&
        (!item->fill || (item->type != AIRUI_SHAPE_ITEM_RECT && item->type != AIRUI_SHAPE_ITEM_CIRCLE))) {
        LLOGW("%s fill gradient is currently unsupported (requires filled rect/circle); using solid color", type);
        item->fill_grad_dir = LV_GRAD_DIR_NONE;
    }
}

static int airui_shape_parse_item(lua_State *L, int idx, airui_shape_item_t *item)
{
    const char *type;
    lv_color_t color;
    lv_color_t fill_color;
    int width;
    int opacity;
    int fill_opacity;
    int abs_idx;

    if (item == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    abs_idx = lua_absindex(L, idx);
    memset(item, 0, sizeof(airui_shape_item_t));

    type = airui_marshal_string(L, abs_idx, "type", "line");
    item->type = AIRUI_SHAPE_ITEM_LINE;
    if (type != NULL) {
        if (strcmp(type, "circle") == 0) {
            item->type = AIRUI_SHAPE_ITEM_CIRCLE;
        }
        else if (strcmp(type, "ellipse") == 0) {
            item->type = AIRUI_SHAPE_ITEM_ELLIPSE;
        }
        else if (strcmp(type, "rect") == 0) {
            item->type = AIRUI_SHAPE_ITEM_RECT;
        }
        else if (strcmp(type, "arc") == 0) {
            item->type = AIRUI_SHAPE_ITEM_ARC;
        }
    }

    color = lv_color_hex(0xffffff);
    if (airui_marshal_color(L, abs_idx, "color", &color)) {
        item->color = color;
    }
    else {
        item->color = lv_color_hex(0xffffff);
    }

    fill_color = item->color;
    if (airui_marshal_color(L, abs_idx, "fill_color", &fill_color)) {
        item->fill_color = fill_color;
    }
    else {
        item->fill_color = item->color;
    }

    width = airui_marshal_integer(L, abs_idx, "width", 1);
    if (width < 1) {
        width = 1;
    }
    item->width = (int16_t)width;
    item->dash_width = (int16_t)airui_marshal_integer(L, abs_idx, "dash_width", 0);
    item->dash_gap = (int16_t)airui_marshal_integer(L, abs_idx, "dash_gap", 0);
    item->fill = airui_marshal_bool(L, abs_idx, "fill", false) ? 1 : 0;
    item->round_start = airui_marshal_bool(L, abs_idx, "round_start", false) ? 1 : 0;
    item->round_end = airui_marshal_bool(L, abs_idx, "round_end", false) ? 1 : 0;

    opacity = airui_marshal_integer(L, abs_idx, "opacity", 255);
    fill_opacity = airui_marshal_integer(L, abs_idx, "fill_opacity", item->fill ? 255 : 0);
    item->opa = airui_marshal_opacity(opacity);
    item->fill_opa = airui_marshal_opacity(fill_opacity);

    switch (item->type) {
        case AIRUI_SHAPE_ITEM_LINE:
            item->data.line.x1 = (int16_t)airui_marshal_integer(L, abs_idx, "x1", 0);
            item->data.line.y1 = (int16_t)airui_marshal_integer(L, abs_idx, "y1", 0);
            item->data.line.x2 = (int16_t)airui_marshal_integer(L, abs_idx, "x2", 0);
            item->data.line.y2 = (int16_t)airui_marshal_integer(L, abs_idx, "y2", 0);
            break;

        case AIRUI_SHAPE_ITEM_CIRCLE:
            item->data.circle.cx = (int16_t)airui_marshal_integer(L, abs_idx, "cx", 0);
            item->data.circle.cy = (int16_t)airui_marshal_integer(L, abs_idx, "cy", 0);
            item->data.circle.r = (int16_t)airui_marshal_integer(L, abs_idx, "r", 0);
            if (item->data.circle.r < 0) {
                item->data.circle.r = 0;
            }
            break;

        case AIRUI_SHAPE_ITEM_ELLIPSE:
            item->data.ellipse.cx = (int16_t)airui_marshal_integer(L, abs_idx, "cx", 0);
            item->data.ellipse.cy = (int16_t)airui_marshal_integer(L, abs_idx, "cy", 0);
            item->data.ellipse.rx = (int16_t)airui_marshal_integer(L, abs_idx, "rx", 0);
            item->data.ellipse.ry = (int16_t)airui_marshal_integer(L, abs_idx, "ry", 0);
            item->data.ellipse.segments = (uint16_t)airui_marshal_integer(L, abs_idx, "segments", 0);
            if (item->data.ellipse.rx < 0) {
                item->data.ellipse.rx = 0;
            }
            if (item->data.ellipse.ry < 0) {
                item->data.ellipse.ry = 0;
            }
            if (item->data.ellipse.segments < 12) {
                int suggested = ((int)item->data.ellipse.rx + (int)item->data.ellipse.ry) / 2;
                if (suggested < 24) {
                    suggested = 24;
                }
                if (suggested > 96) {
                    suggested = 96;
                }
                item->data.ellipse.segments = (uint16_t)suggested;
            }
            break;

        case AIRUI_SHAPE_ITEM_RECT:
            item->data.rect.x = (int16_t)airui_marshal_integer(L, abs_idx, "x", 0);
            item->data.rect.y = (int16_t)airui_marshal_integer(L, abs_idx, "y", 0);
            item->data.rect.w = (int16_t)airui_marshal_integer(L, abs_idx, "w", 0);
            item->data.rect.h = (int16_t)airui_marshal_integer(L, abs_idx, "h", 0);
            item->data.rect.radius = (int16_t)airui_marshal_integer(L, abs_idx, "radius", 0);
            if (item->data.rect.w < 0) {
                item->data.rect.w = 0;
            }
            if (item->data.rect.h < 0) {
                item->data.rect.h = 0;
            }
            if (item->data.rect.radius < 0) {
                item->data.rect.radius = 0;
            }
            break;

        case AIRUI_SHAPE_ITEM_ARC:
            item->data.arc.cx = (int16_t)airui_marshal_integer(L, abs_idx, "cx", 0);
            item->data.arc.cy = (int16_t)airui_marshal_integer(L, abs_idx, "cy", 0);
            item->data.arc.r = (int16_t)airui_marshal_integer(L, abs_idx, "r", 0);
            item->data.arc.start_angle = (int16_t)airui_marshal_integer(L, abs_idx, "start_angle", 0);
            item->data.arc.end_angle = (int16_t)airui_marshal_integer(L, abs_idx, "end_angle", 0);
            if (item->data.arc.r < 0) {
                item->data.arc.r = 0;
            }
            /* lv_draw_arc has one rounded flag for both ends. */
            if (airui_marshal_bool(L, abs_idx, "rounded", false)) {
                item->round_start = 1;
                item->round_end = 1;
            }
            break;

        default:
            return AIRUI_ERR_INVALID_PARAM;
    }

    airui_shape_parse_gradients(L, abs_idx, type, item);
    return AIRUI_OK;
}

static void airui_shape_set_gradient(lv_grad_dsc_t *grad, lv_color_t start, lv_color_t end, lv_grad_dir_t dir)
{
    grad->dir = dir;
    grad->stops_count = 2;
    grad->stops[0].color = start;
    grad->stops[0].opa = LV_OPA_COVER;
    grad->stops[0].frac = 0;
    grad->stops[1].color = end;
    grad->stops[1].opa = LV_OPA_COVER;
    grad->stops[1].frac = 255;
}

static lv_color_t airui_shape_line_gradient_color(const airui_shape_item_t *item,
                                                 const lv_area_t *bounds, int32_t pos)
{
    int32_t start = item->grad_dir == LV_GRAD_DIR_HOR ? bounds->x1 : bounds->y1;
    int32_t end = item->grad_dir == LV_GRAD_DIR_HOR ? bounds->x2 : bounds->y2;
    uint8_t mix = end > start ? (uint8_t)(LV_CLAMP(0, pos - start, end - start) * 255 / (end - start)) : 0;
    return lv_color_mix(item->grad_color, item->color, mix);
}

/* Keep every dash and cap on the same gradient, without allocating a bitmap. */
static void airui_shape_draw_gradient_line_part(lv_layer_t *layer, const airui_shape_item_t *item,
                                               const lv_area_t *bounds, const lv_area_t *area,
                                               int32_t radius, const lv_area_t *clip)
{
    lv_area_t saved_clip = layer->_clip_area;
    if (clip != NULL && !lv_area_intersect(&layer->_clip_area, &saved_clip, clip)) {
        layer->_clip_area = saved_clip;
        return;
    }
    lv_draw_rect_dsc_t dsc;
    lv_draw_rect_dsc_init(&dsc);
    dsc.base.layer = layer;
    dsc.bg_opa = item->opa;
    dsc.border_width = 0;
    dsc.radius = radius;
    int32_t start = item->grad_dir == LV_GRAD_DIR_HOR ? area->x1 : area->y1;
    int32_t end = item->grad_dir == LV_GRAD_DIR_HOR ? area->x2 : area->y2;
    airui_shape_set_gradient(&dsc.bg_grad, airui_shape_line_gradient_color(item, bounds, start),
                            airui_shape_line_gradient_color(item, bounds, end), item->grad_dir);
    lv_draw_rect(layer, &dsc, area);
    layer->_clip_area = saved_clip;
}

static void airui_shape_draw_gradient_line(lv_layer_t *layer, const lv_draw_line_dsc_t *line,
                                         const airui_shape_item_t *item)
{
    bool horizontal = line->p1.y == line->p2.y;
    int32_t start = horizontal ? LV_MIN(line->p1.x, line->p2.x) : LV_MIN(line->p1.y, line->p2.y);
    int32_t end = horizontal ? LV_MAX(line->p1.x, line->p2.x) : LV_MAX(line->p1.y, line->p2.y);
    if (start == end || item->width <= 0 || item->opa <= LV_OPA_MIN) {
        return;
    }
    int32_t half = (item->width - 1) / 2;
    int32_t half_extra = item->width / 2;
    lv_area_t body;
    if (horizontal) {
        lv_area_set(&body, start, (int32_t)line->p1.y - half_extra, end - 1, (int32_t)line->p1.y + half);
    } else {
        lv_area_set(&body, (int32_t)line->p1.x - half_extra, start, (int32_t)line->p1.x + half, end - 1);
    }
    lv_area_t bounds = body;
    lv_area_t caps[2];
    bool rounded[2] = {item->round_start != 0, item->round_end != 0};
    int32_t cap_correction = (item->width & 1) ? 0 : 1;
    for (int i = 0; i < 2; i++) {
        int32_t x = (int32_t)(i == 0 ? line->p1.x : line->p2.x);
        int32_t y = (int32_t)(i == 0 ? line->p1.y : line->p2.y);
        lv_area_set(&caps[i], x - half_extra, y - half_extra,
                    x + half_extra - cap_correction, y + half_extra - cap_correction);
        if (rounded[i]) {
            lv_area_join(&bounds, &bounds, &caps[i]);
        }
    }

    bool dashed = item->dash_width > 0 && item->dash_gap > 0;
    int32_t period = dashed ? (int32_t)item->dash_width + item->dash_gap : end - start;
    lv_area_t visible;
    bool body_visible = lv_area_intersect(&visible, &body, &layer->_clip_area);
    int32_t first = body_visible ? (horizontal ? visible.x1 : visible.y1) : end;
    int32_t last_visible = body_visible ? (horizontal ? visible.x2 : visible.y2) : start - 1;
    /* Skip off-screen dashes while retaining the full line's gradient origin. */
    for (int32_t pos = start + (first - start) / period * period; pos <= last_visible; pos += period) {
        lv_area_t part = body;
        int32_t last = dashed ? LV_MIN(pos + item->dash_width, end) - 1 : end - 1;
        if (horizontal) {
            part.x1 = pos;
            part.x2 = last;
        } else {
            part.y1 = pos;
            part.y2 = last;
        }
        airui_shape_draw_gradient_line_part(layer, item, &bounds, &part, 0, NULL);
    }
    for (int i = 0; i < 2; i++) {
        if (!rounded[i]) continue;
        lv_area_t clip = caps[i];
        bool at_start = (horizontal ? line->p1.x : line->p1.y) == start;
        if (i == 1) at_start = !at_start;
        /* Clip caps to the outside half so translucent joins are drawn once. */
        if (horizontal) {
            if (at_start) clip.x2 = start - 1;
            else clip.x1 = end;
        } else {
            if (at_start) clip.y2 = start - 1;
            else clip.y1 = end;
        }
        if (clip.x1 <= clip.x2 && clip.y1 <= clip.y2) {
            airui_shape_draw_gradient_line_part(layer, item, &bounds, &caps[i], LV_RADIUS_CIRCLE, &clip);
        }
    }
}

static void airui_shape_draw_line_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item)
{
    lv_draw_line_dsc_t dsc;

    lv_draw_line_dsc_init(&dsc);
    dsc.base.layer = layer;
    dsc.color = item->color;
    dsc.width = item->width;
    dsc.opa = item->opa;
    dsc.dash_width = item->dash_width;
    dsc.dash_gap = item->dash_gap;
    dsc.round_start = item->round_start;
    dsc.round_end = item->round_end;
    dsc.p1.x = coords->x1 + item->data.line.x1;
    dsc.p1.y = coords->y1 + item->data.line.y1;
    dsc.p2.x = coords->x1 + item->data.line.x2;
    dsc.p2.y = coords->y1 + item->data.line.y2;
    if (item->grad_dir != LV_GRAD_DIR_NONE) {
        airui_shape_draw_gradient_line(layer, &dsc, item);
    } else {
        lv_draw_line(layer, &dsc);
    }
}

static void airui_shape_draw_circle_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item)
{
    int32_t cx = coords->x1 + item->data.circle.cx;
    int32_t cy = coords->y1 + item->data.circle.cy;
    int32_t r = item->data.circle.r;

    if (r <= 0) {
        return;
    }

    if (item->fill) {
        lv_area_t area;
        lv_draw_rect_dsc_t dsc;
        lv_area_set(&area, cx - r, cy - r, cx + r, cy + r);
        lv_draw_rect_dsc_init(&dsc);
        dsc.base.layer = layer;
        dsc.radius = LV_RADIUS_CIRCLE;
        dsc.bg_color = item->fill_color;
        dsc.bg_opa = item->fill_opa;
        airui_shape_set_gradient(&dsc.bg_grad, item->fill_color, item->fill_grad_color, item->fill_grad_dir);
        dsc.border_color = item->color;
        dsc.border_width = item->width;
        dsc.border_opa = item->opa;
        dsc.border_side = LV_BORDER_SIDE_FULL;
        lv_draw_rect(layer, &dsc, &area);
        return;
    }

    {
        lv_draw_arc_dsc_t dsc;
        lv_draw_arc_dsc_init(&dsc);
        dsc.base.layer = layer;
        dsc.color = item->color;
        dsc.width = item->width;
        dsc.opa = item->opa;
        dsc.rounded = item->round_start || item->round_end;
        dsc.center.x = cx;
        dsc.center.y = cy;
        dsc.radius = (uint16_t)r;
        dsc.start_angle = 0;
        dsc.end_angle = 360;
        lv_draw_arc(layer, &dsc);
    }
}

static void airui_shape_draw_rect_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item)
{
    lv_area_t area;
    lv_draw_rect_dsc_t dsc;
    int32_t x1 = coords->x1 + item->data.rect.x;
    int32_t y1 = coords->y1 + item->data.rect.y;
    int32_t x2 = x1 + item->data.rect.w;
    int32_t y2 = y1 + item->data.rect.h;

    if (item->data.rect.w <= 0 || item->data.rect.h <= 0) {
        return;
    }

    lv_area_set(&area, x1, y1, x2, y2);
    lv_draw_rect_dsc_init(&dsc);
    dsc.base.layer = layer;
    dsc.radius = item->data.rect.radius;
    dsc.bg_opa = item->fill ? item->fill_opa : LV_OPA_TRANSP;
    dsc.bg_color = item->fill_color;
    airui_shape_set_gradient(&dsc.bg_grad, item->fill_color, item->fill_grad_color, item->fill_grad_dir);
    dsc.border_opa = item->opa;
    dsc.border_color = item->color;
    dsc.border_width = item->width;
    dsc.border_side = LV_BORDER_SIDE_FULL;
    lv_draw_rect(layer, &dsc, &area);
}

static void airui_shape_draw_ellipse_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item)
{
    int32_t cx = coords->x1 + item->data.ellipse.cx;
    int32_t cy = coords->y1 + item->data.ellipse.cy;
    int32_t rx = item->data.ellipse.rx;
    int32_t ry = item->data.ellipse.ry;
    uint16_t segments = item->data.ellipse.segments;
    uint16_t i;

    if (rx <= 0 || ry <= 0 || segments < 3) {
        return;
    }

    if (item->fill && item->fill_opa > LV_OPA_TRANSP) {
        int32_t dy;
        for (dy = -ry; dy <= ry; dy++) {
            double ratio = 1.0 - (((double)dy * (double)dy) / ((double)ry * (double)ry));
            int32_t dx;
            lv_draw_line_dsc_t fill_dsc;
            if (ratio < 0.0) {
                ratio = 0.0;
            }
            dx = (int32_t)((double)rx * sqrt(ratio));
            lv_draw_line_dsc_init(&fill_dsc);
            fill_dsc.base.layer = layer;
            fill_dsc.color = item->fill_color;
            fill_dsc.width = 1;
            fill_dsc.opa = item->fill_opa;
            fill_dsc.p1.x = cx - dx;
            fill_dsc.p1.y = cy + dy;
            fill_dsc.p2.x = cx + dx;
            fill_dsc.p2.y = cy + dy;
            lv_draw_line(layer, &fill_dsc);
        }
    }

    for (i = 0; i < segments; i++) {
        double a1 = (2.0 * M_PI * (double)i) / (double)segments;
        double a2 = (2.0 * M_PI * (double)(i + 1)) / (double)segments;
        lv_draw_line_dsc_t dsc;
        lv_draw_line_dsc_init(&dsc);
        dsc.base.layer = layer;
        dsc.color = item->color;
        dsc.width = item->width;
        dsc.opa = item->opa;
        dsc.round_start = item->round_start;
        dsc.round_end = item->round_end;
        dsc.p1.x = cx + airui_shape_round_double((double)rx * cos(a1));
        dsc.p1.y = cy + airui_shape_round_double((double)ry * sin(a1));
        dsc.p2.x = cx + airui_shape_round_double((double)rx * cos(a2));
        dsc.p2.y = cy + airui_shape_round_double((double)ry * sin(a2));
        lv_draw_line(layer, &dsc);
    }
}

static void airui_shape_prepare_arc_angles(int16_t start_in, int16_t end_in, int32_t *start_out, int32_t *end_out)
{
    int32_t start = start_in;
    int32_t end = end_in;
    int32_t span = end - start;

    /* A full turn uses LVGL's closed-ring path: end = start + 360. */
    if (span >= 360 || span <= -360) {
        start %= 360;
        if (start < 0) {
            start += 360;
        }
        *start_out = start;
        *end_out = start + 360;
        return;
    }

    /* Fold the start into [0, 359] and shift the end with it. */
    if (start >= 360 || start < 0) {
        int32_t turns = start / 360;
        if (start < 0 && (start % 360) != 0) {
            turns -= 1;
        }
        start -= turns * 360;
        end -= turns * 360;
    }

    *start_out = start;
    *end_out = end;
}

static void airui_shape_draw_arc_item(lv_layer_t *layer, const lv_area_t *coords, const airui_shape_item_t *item)
{
    int32_t r = item->data.arc.r;
    int32_t start_angle;
    int32_t end_angle;
    lv_draw_arc_dsc_t dsc;

    if (r <= 0) {
        return;
    }

    airui_shape_prepare_arc_angles(item->data.arc.start_angle, item->data.arc.end_angle, &start_angle, &end_angle);
    if (start_angle == end_angle) {
        return;
    }

    lv_draw_arc_dsc_init(&dsc);
    dsc.base.layer = layer;
    dsc.color = item->color;
    dsc.width = item->width;
    dsc.opa = item->opa;
    dsc.rounded = item->round_start || item->round_end;
    dsc.center.x = coords->x1 + item->data.arc.cx;
    dsc.center.y = coords->y1 + item->data.arc.cy;
    dsc.radius = (uint16_t)r;
    dsc.start_angle = start_angle;
    dsc.end_angle = end_angle;
    lv_draw_arc(layer, &dsc);
}

static void airui_shape_draw(lv_event_t *e, airui_shape_data_t *data)
{
    lv_obj_t *shape = lv_event_get_current_target(e);
    lv_layer_t *layer = lv_event_get_layer(e);
    lv_area_t coords;
    uint16_t i;

    if (shape == NULL || layer == NULL || data == NULL || data->count == 0) {
        return;
    }

    lv_obj_get_content_coords(shape, &coords);
    for (i = 0; i < data->count; i++) {
        const airui_shape_item_t *item = &data->items[i];
        switch (item->type) {
            case AIRUI_SHAPE_ITEM_LINE:
                airui_shape_draw_line_item(layer, &coords, item);
                break;
            case AIRUI_SHAPE_ITEM_CIRCLE:
                airui_shape_draw_circle_item(layer, &coords, item);
                break;
            case AIRUI_SHAPE_ITEM_ELLIPSE:
                airui_shape_draw_ellipse_item(layer, &coords, item);
                break;
            case AIRUI_SHAPE_ITEM_RECT:
                airui_shape_draw_rect_item(layer, &coords, item);
                break;
            case AIRUI_SHAPE_ITEM_ARC:
                airui_shape_draw_arc_item(layer, &coords, item);
                break;
            default:
                break;
        }
    }
}

static void airui_shape_event_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    lv_obj_t *shape = lv_event_get_current_target(e);
    airui_shape_data_t *data = airui_shape_get_data(shape);

    if (code == LV_EVENT_REFR_EXT_DRAW_SIZE) {
        int32_t *size = (int32_t *)lv_event_get_param(e);
        if (size != NULL && data != NULL) {
            int32_t ext = data->max_stroke_width / 2 + 2;
            if (ext > *size) {
                *size = ext;
            }
        }
        return;
    }

    if (code == LV_EVENT_DRAW_MAIN) {
        airui_shape_draw(e, data);
    }
}

lv_obj_t *airui_shape_create_from_config(void *L, int idx)
{
    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = NULL;
    lv_obj_t *shape;
    airui_component_meta_t *meta;
    lv_obj_t *parent;
    int x;
    int y;
    int w;
    int h;

    if (L == NULL) {
        return NULL;
    }

    ctx = airui_shape_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    parent = airui_marshal_parent(L, idx);
    x = airui_marshal_floor_integer(L, idx, "x", 0);
    y = airui_marshal_floor_integer(L, idx, "y", 0);
    w = airui_marshal_floor_integer(L, idx, "w", 100);
    h = airui_marshal_floor_integer(L, idx, "h", 100);

    shape = lv_obj_create(parent);
    if (shape == NULL) {
        return NULL;
    }

    lv_obj_set_pos(shape, x, y);
    lv_obj_set_size(shape, w, h);
    lv_obj_set_style_bg_opa(shape, LV_OPA_TRANSP, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(shape, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_all(shape, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
    /* Shape is a draw-only overlay and should not intercept parent clicks. */
    lv_obj_remove_flag(shape, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_remove_flag(shape, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(shape, LV_OBJ_FLAG_IGNORE_LAYOUT);

    meta = airui_component_meta_alloc(ctx, shape, AIRUI_COMPONENT_SHAPE);
    if (meta == NULL) {
        lv_obj_delete(shape);
        return NULL;
    }

    lv_obj_add_event_cb(shape, airui_shape_event_cb, LV_EVENT_DRAW_MAIN, NULL);
    lv_obj_add_event_cb(shape, airui_shape_event_cb, LV_EVENT_REFR_EXT_DRAW_SIZE, NULL);

    lua_getfield(L_state, idx, "items");
    if (lua_istable(L_state, -1)) {
        airui_shape_set_items(shape, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);

    return shape;
}

int airui_shape_set_items(lv_obj_t *shape, void *L, int idx)
{
    lua_State *L_state = (lua_State *)L;
    airui_shape_data_t *data = airui_shape_ensure_data(shape);
    uint16_t len;
    uint16_t i;

    if (shape == NULL || L_state == NULL || !lua_istable(L_state, idx) || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    len = (uint16_t)lua_rawlen(L_state, idx);
    data->count = 0;
    if (len > 0) {
        if (airui_shape_ensure_capacity(data, len) != AIRUI_OK) {
            return AIRUI_ERR_NO_MEM;
        }
    }

    for (i = 0; i < len; i++) {
        lua_rawgeti(L_state, idx, (lua_Integer)(i + 1));
        if (lua_istable(L_state, -1)) {
            if (airui_shape_parse_item(L_state, lua_gettop(L_state), &data->items[data->count]) == AIRUI_OK) {
                data->count++;
            }
        }
        lua_pop(L_state, 1);
    }

    airui_shape_recompute_metrics(data);
    lv_obj_refresh_ext_draw_size(shape);
    lv_obj_invalidate(shape);
    return AIRUI_OK;
}

int airui_shape_add_item(lv_obj_t *shape, void *L, int idx)
{
    lua_State *L_state = (lua_State *)L;
    airui_shape_data_t *data = airui_shape_ensure_data(shape);
    airui_shape_item_t item;

    if (shape == NULL || L_state == NULL || !lua_istable(L_state, idx) || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (airui_shape_parse_item(L_state, idx, &item) != AIRUI_OK) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    if (airui_shape_ensure_capacity(data, (uint16_t)(data->count + 1)) != AIRUI_OK) {
        return AIRUI_ERR_NO_MEM;
    }

    data->items[data->count] = item;
    data->count++;
    airui_shape_recompute_metrics(data);
    lv_obj_refresh_ext_draw_size(shape);
    lv_obj_invalidate(shape);
    return AIRUI_OK;
}

int airui_shape_clear(lv_obj_t *shape)
{
    airui_shape_data_t *data = airui_shape_get_data(shape);
    if (shape == NULL || data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->count = 0;
    data->max_stroke_width = 1;
    lv_obj_refresh_ext_draw_size(shape);
    lv_obj_invalidate(shape);
    return AIRUI_OK;
}

int airui_shape_get_count(lv_obj_t *shape)
{
    airui_shape_data_t *data = airui_shape_get_data(shape);
    if (shape == NULL || data == NULL) {
        return 0;
    }
    return (int)data->count;
}

int airui_shape_set_hidden(lv_obj_t *shape, bool hidden)
{
    if (shape == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    lv_obj_set_flag(shape, LV_OBJ_FLAG_HIDDEN, hidden);
    return AIRUI_OK;
}
