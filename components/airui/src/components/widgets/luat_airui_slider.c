/**
 * @file luat_airui_slider.c
 * @summary Slider 组件实现
 * @responsible Slider 创建、值/范围/模式控制、事件绑定
 */

#include "luat_airui_component.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/slider/lv_slider.h"
#include "lvgl9/src/core/lv_group.h"

typedef enum {
    AIRUI_SLIDER_MODE_NORMAL = 0,
    AIRUI_SLIDER_MODE_SYMMETRICAL,
    AIRUI_SLIDER_MODE_RANGE
} airui_slider_mode_t;

typedef enum {
    AIRUI_SLIDER_ORIENTATION_AUTO = 0,
    AIRUI_SLIDER_ORIENTATION_HORIZONTAL,
    AIRUI_SLIDER_ORIENTATION_VERTICAL
} airui_slider_orientation_t;

#if LV_USE_SLIDER != 0

static airui_ctx_t *airui_slider_get_ctx(lua_State *L)
{
    airui_ctx_t *ctx = NULL;
    if (L == NULL) {
        return NULL;
    }

    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

/**
 * 应用 Slider 样式表
 * 支持 main/indicator/knob 三个部分的圆角、颜色、透明度与内边距。
 */
int airui_slider_set_style(lv_obj_t *slider, void *L, int idx)
{
    if (slider == NULL || L == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lua_State *L_state = (lua_State *)L;
    idx = lua_absindex(L_state, idx);
    if (!lua_istable(L_state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    int value = 0;
    lv_style_selector_t main_sel = (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT;
    lv_style_selector_t indicator_sel = (lv_style_selector_t)LV_PART_INDICATOR | LV_STATE_DEFAULT;
    lv_style_selector_t knob_sel = (lv_style_selector_t)LV_PART_KNOB | LV_STATE_DEFAULT;

    if (airui_marshal_integer_opt(L_state, idx, "bg_color", &value)) {
        lv_obj_set_style_bg_color(slider, lv_color_hex((uint32_t)value), main_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "bg_opa", &value)) {
        lv_obj_set_style_bg_opa(slider, airui_marshal_opacity(value), main_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "border_color", &value)) {
        lv_obj_set_style_border_color(slider, lv_color_hex((uint32_t)value), main_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "border_width", &value)) {
        lv_obj_set_style_border_width(slider, value < 0 ? 0 : value, main_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "radius", &value)) {
        value = value < 0 ? 0 : value;
        lv_obj_set_style_radius(slider, value, main_sel);
        lv_obj_set_style_radius(slider, value, indicator_sel);
        lv_obj_set_style_radius(slider, value, knob_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "pad", &value)) {
        lv_obj_set_style_pad_all(slider, value < 0 ? 0 : value, main_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "indicator_color", &value)) {
        lv_obj_set_style_bg_color(slider, lv_color_hex((uint32_t)value), indicator_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "indicator_opa", &value)) {
        lv_obj_set_style_bg_opa(slider, airui_marshal_opacity(value), indicator_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "knob_color", &value)) {
        lv_obj_set_style_bg_color(slider, lv_color_hex((uint32_t)value), knob_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "knob_opa", &value)) {
        lv_obj_set_style_bg_opa(slider, airui_marshal_opacity(value), knob_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "knob_border_color", &value)) {
        lv_obj_set_style_border_color(slider, lv_color_hex((uint32_t)value), knob_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "knob_border_width", &value)) {
        lv_obj_set_style_border_width(slider, value < 0 ? 0 : value, knob_sel);
    }

    return AIRUI_OK;
}

lv_obj_t *airui_slider_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_slider_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    idx = lua_absindex(L_state, idx);

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_floor_integer(L, idx, "x", 0);
    int y = airui_marshal_floor_integer(L, idx, "y", 0);
    int w = airui_marshal_floor_integer(L, idx, "w", 200);
    int h = airui_marshal_floor_integer(L, idx, "h", 20);
    int min = airui_marshal_integer(L, idx, "min", 0);
    int max = airui_marshal_integer(L, idx, "max", 100);
    int value = airui_marshal_integer(L, idx, "value", min);

    if (max < min) {
        max = min;
    }

    lv_obj_t *slider = lv_slider_create(parent);
    if (slider == NULL) {
        return NULL;
    }

    lv_obj_set_pos(slider, x, y);
    lv_obj_set_size(slider, w, h);
    lv_slider_set_range(slider, min, max);

    lua_getfield(L_state, idx, "style");
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        airui_slider_set_style(slider, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);
    lv_slider_set_value(slider, value, LV_ANIM_OFF);

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, slider, AIRUI_COMPONENT_SLIDER);
    if (meta == NULL) {
        lv_obj_delete(slider);
        return NULL;
    }

    int callback_ref = airui_component_capture_callback(L, idx, "on_change");
    if (callback_ref != LUA_NOREF) {
        airui_component_bind_event(meta, AIRUI_EVENT_VALUE_CHANGED, callback_ref);
    }

    lv_group_t *default_group = lv_group_get_default();
    if (default_group != NULL) {
        lv_group_add_obj(default_group, slider);
    }

    return slider;
}

int airui_slider_set_value(lv_obj_t *slider, int32_t value, bool animated)
{
    if (slider == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_slider_set_value(slider, value, animated ? LV_ANIM_ON : LV_ANIM_OFF);
    return AIRUI_OK;
}

int airui_slider_set_start_value(lv_obj_t *slider, int32_t value, bool animated)
{
    if (slider == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_slider_set_start_value(slider, value, animated ? LV_ANIM_ON : LV_ANIM_OFF);
    return AIRUI_OK;
}

int airui_slider_set_range(lv_obj_t *slider, int32_t min, int32_t max)
{
    if (slider == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (max < min) {
        max = min;
    }

    lv_slider_set_range(slider, min, max);
    return AIRUI_OK;
}

int airui_slider_set_mode(lv_obj_t *slider, airui_slider_mode_t mode)
{
    if (slider == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (mode < AIRUI_SLIDER_MODE_NORMAL || mode > AIRUI_SLIDER_MODE_RANGE) {
        mode = AIRUI_SLIDER_MODE_NORMAL;
    }

    lv_slider_set_mode(slider, (lv_slider_mode_t)mode);
    return AIRUI_OK;
}

int airui_slider_set_orientation(lv_obj_t *slider, airui_slider_orientation_t orientation)
{
    if (slider == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (orientation < AIRUI_SLIDER_ORIENTATION_AUTO || orientation > AIRUI_SLIDER_ORIENTATION_VERTICAL) {
        orientation = AIRUI_SLIDER_ORIENTATION_HORIZONTAL;
    }

    lv_slider_set_orientation(slider, (lv_slider_orientation_t)orientation);
    return AIRUI_OK;
}

int airui_slider_set_on_change(lv_obj_t *slider, int callback_ref)
{
    if (slider == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(slider);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return airui_component_bind_event(meta, AIRUI_EVENT_VALUE_CHANGED, callback_ref);
}

int airui_slider_get_value(lv_obj_t *slider)
{
    if (slider == NULL) {
        return 0;
    }

    return (int)lv_slider_get_value(slider);
}

int airui_slider_get_left_value(lv_obj_t *slider)
{
    if (slider == NULL) {
        return 0;
    }

    return (int)lv_slider_get_left_value(slider);
}

int airui_slider_get_min_value(lv_obj_t *slider)
{
    if (slider == NULL) {
        return 0;
    }

    return (int)lv_slider_get_min_value(slider);
}

int airui_slider_get_max_value(lv_obj_t *slider)
{
    if (slider == NULL) {
        return 0;
    }

    return (int)lv_slider_get_max_value(slider);
}

airui_slider_mode_t airui_slider_get_mode(lv_obj_t *slider)
{
    if (slider == NULL) {
        return AIRUI_SLIDER_MODE_NORMAL;
    }

    return (airui_slider_mode_t)lv_slider_get_mode(slider);
}

airui_slider_orientation_t airui_slider_get_orientation(lv_obj_t *slider)
{
    if (slider == NULL) {
        return AIRUI_SLIDER_ORIENTATION_HORIZONTAL;
    }

    return (airui_slider_orientation_t)lv_slider_get_orientation(slider);
}

bool airui_slider_is_dragged(lv_obj_t *slider)
{
    if (slider == NULL) {
        return false;
    }

    return lv_slider_is_dragged(slider);
}

bool airui_slider_is_symmetrical(lv_obj_t *slider)
{
    if (slider == NULL) {
        return false;
    }

    return lv_slider_is_symmetrical(slider);
}

int airui_slider_destroy(lv_obj_t *slider)
{
    if (slider == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_delete(slider);
    return AIRUI_OK;
}

#else
lv_obj_t *airui_slider_create_from_config(void *L, int idx)
{
    (void)L;
    (void)idx;
    return NULL;
}

int airui_slider_set_value(lv_obj_t *slider, int32_t value, bool animated)
{
    (void)slider;
    (void)value;
    (void)animated;
    return AIRUI_ERR_NOT_SUPPORTED;
}

int airui_slider_set_start_value(lv_obj_t *slider, int32_t value, bool animated)
{
    (void)slider;
    (void)value;
    (void)animated;
    return AIRUI_ERR_NOT_SUPPORTED;
}

int airui_slider_set_range(lv_obj_t *slider, int32_t min, int32_t max)
{
    (void)slider;
    (void)min;
    (void)max;
    return AIRUI_ERR_NOT_SUPPORTED;
}

int airui_slider_set_mode(lv_obj_t *slider, airui_slider_mode_t mode)
{
    (void)slider;
    (void)mode;
    return AIRUI_ERR_NOT_SUPPORTED;
}

int airui_slider_set_orientation(lv_obj_t *slider, airui_slider_orientation_t orientation)
{
    (void)slider;
    (void)orientation;
    return AIRUI_ERR_NOT_SUPPORTED;
}

int airui_slider_set_on_change(lv_obj_t *slider, int callback_ref)
{
    (void)slider;
    (void)callback_ref;
    return AIRUI_ERR_NOT_SUPPORTED;
}

int airui_slider_get_value(lv_obj_t *slider)
{
    (void)slider;
    return 0;
}

int airui_slider_get_left_value(lv_obj_t *slider)
{
    (void)slider;
    return 0;
}

int airui_slider_get_min_value(lv_obj_t *slider)
{
    (void)slider;
    return 0;
}

int airui_slider_get_max_value(lv_obj_t *slider)
{
    (void)slider;
    return 0;
}

airui_slider_mode_t airui_slider_get_mode(lv_obj_t *slider)
{
    (void)slider;
    return AIRUI_SLIDER_MODE_NORMAL;
}

airui_slider_orientation_t airui_slider_get_orientation(lv_obj_t *slider)
{
    (void)slider;
    return AIRUI_SLIDER_ORIENTATION_HORIZONTAL;
}

bool airui_slider_is_dragged(lv_obj_t *slider)
{
    (void)slider;
    return false;
}

bool airui_slider_is_symmetrical(lv_obj_t *slider)
{
    (void)slider;
    return false;
}

int airui_slider_destroy(lv_obj_t *slider)
{
    (void)slider;
    return AIRUI_ERR_NOT_SUPPORTED;
}
#endif
