/**
 * @file luat_airui_spinner.c
 * @summary Spinner 组件实现
 * @responsible 解析配置、创建 lv_spinner、应用样式与动画参数
 */

#include "luat_airui_component.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/spinner/lv_spinner.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>

static airui_ctx_t *airui_spinner_get_ctx(lua_State *L)
{
    if (L == NULL) {
        return NULL;
    }

    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

static void airui_spinner_apply_default_style(lv_obj_t *spinner)
{
    lv_style_selector_t main_sel = (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_style_selector_t indicator_sel = (lv_style_selector_t)(LV_PART_INDICATOR | LV_STATE_DEFAULT);
    lv_color_t color = lv_color_hex(0x00b4ff);
    lv_color_t track_color = lv_color_hex(0x202835);

    lv_obj_set_style_arc_color(spinner, track_color, main_sel);
    lv_obj_set_style_arc_color(spinner, color, indicator_sel);
    lv_obj_set_style_arc_width(spinner, 4, main_sel);
    lv_obj_set_style_arc_width(spinner, 4, indicator_sel);
    lv_obj_set_style_arc_opa(spinner, LV_OPA_COVER, main_sel);
    lv_obj_set_style_arc_opa(spinner, LV_OPA_COVER, indicator_sel);
}

lv_obj_t *airui_spinner_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_spinner_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int w = airui_marshal_integer(L, idx, "w", 40);
    int h = airui_marshal_integer(L, idx, "h", 40);
    int duration = airui_marshal_integer(L, idx, "duration", 1000);
    int arc_angle = airui_marshal_integer(L, idx, "arc_angle", 200);

    if (duration < 0) {
        duration = 0;
    }
    if (arc_angle < 0) {
        arc_angle = 0;
    }

    lv_obj_t *spinner = lv_spinner_create(parent);
    if (spinner == NULL) {
        return NULL;
    }

    lv_obj_set_pos(spinner, x, y);
    lv_obj_set_size(spinner, w, h);
    airui_spinner_apply_default_style(spinner);

    lua_getfield(L_state, idx, "style");
    if (lua_type(L_state, -1) == LUA_TTABLE) {
        airui_spinner_set_style(spinner, L_state, lua_gettop(L_state));
    }
    lua_pop(L_state, 1);

    airui_spinner_set_anim_params(spinner, (uint32_t)duration, (uint32_t)arc_angle);

    airui_component_meta_t *meta = airui_component_meta_alloc(ctx, spinner, AIRUI_COMPONENT_SPINNER);
    if (meta == NULL) {
        lv_obj_delete(spinner);
        return NULL;
    }

    return spinner;
}

int airui_spinner_set_style(lv_obj_t *spinner, void *L, int idx)
{
    if (spinner == NULL || L == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lua_State *L_state = (lua_State *)L;
    idx = lua_absindex(L_state, idx);
    if (!lua_istable(L_state, idx)) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    int value = 0;
    lv_style_selector_t main_sel = (lv_style_selector_t)(LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_style_selector_t indicator_sel = (lv_style_selector_t)(LV_PART_INDICATOR | LV_STATE_DEFAULT);

    if (airui_marshal_integer_opt(L_state, idx, "color", &value)) {
        lv_obj_set_style_arc_color(spinner, lv_color_hex((uint32_t)value), indicator_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "track_color", &value)) {
        lv_obj_set_style_arc_color(spinner, lv_color_hex((uint32_t)value), main_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "line_width", &value)) {
        if (value < 0) {
            value = 0;
        }
        lv_obj_set_style_arc_width(spinner, value, main_sel);
        lv_obj_set_style_arc_width(spinner, value, indicator_sel);
    }
    if (airui_marshal_integer_opt(L_state, idx, "opa", &value)) {
        lv_opa_t opa = airui_marshal_opacity(value);
        lv_obj_set_style_arc_opa(spinner, opa, main_sel);
        lv_obj_set_style_arc_opa(spinner, opa, indicator_sel);
    }

    return AIRUI_OK;
}

int airui_spinner_set_anim_params(lv_obj_t *spinner, uint32_t duration, uint32_t arc_angle)
{
    if (spinner == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_spinner_set_anim_params(spinner, duration, arc_angle);
    return AIRUI_OK;
}
