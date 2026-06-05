/*
@module  airui.slider
@summary AIRUI Slider 组件 Lua 绑定
@version 0.1.0
@date    2026.06.05
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define AIRUI_SLIDER_MT "airui.slider"

/**
 * 创建 Slider 组件
 * @api airui.slider(config)
 * @table config Slider 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 200
 * @int config.h 高度，默认 20
 * @int config.min 最小值，默认 0
 * @int config.max 最大值，默认 100
 * @int config.value 当前值，默认 min
 * @table config.style 样式表，可选
 * @int config.style.bg_color 主轨道背景色（0xRRGGBB）
 * @int config.style.bg_opa 主轨道背景透明度（0-255）
 * @int config.style.border_color 主轨道边框颜色（0xRRGGBB）
 * @int config.style.border_width 主轨道边框宽度
 * @int config.style.radius 主轨道、进度条、滑块圆角
 * @int config.style.pad 主轨道内边距
 * @int config.style.indicator_color 进度条颜色（0xRRGGBB）
 * @int config.style.indicator_opa 进度条透明度（0-255）
 * @int config.style.knob_color 滑块颜色（0xRRGGBB）
 * @int config.style.knob_opa 滑块透明度（0-255）
 * @int config.style.knob_border_color 滑块边框颜色（0xRRGGBB）
 * @int config.style.knob_border_width 滑块边框宽度
 * @function config.on_change 值变化回调
 * @userdata config.parent 父对象，可选
 * @return userdata Slider 对象，失败返回 nil
 */
static int l_airui_slider(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    lv_obj_t *slider = airui_slider_create_from_config(L, 1);
    if (slider == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, slider, AIRUI_SLIDER_MT);
    return 1;
}

/**
 * 从 userdata 中取出 Slider 对象
 * @param L Lua 状态
 * @return Slider 对象指针
 */
static lv_obj_t *slider_check(lua_State *L)
{
    return airui_check_component(L, 1, AIRUI_SLIDER_MT);
}

/**
 * Slider:set_value(value, anim) 设置当前滑块值
 * @api slider:set_value(value, anim)
 * @int value 目标值
 * @boolean anim 是否使用动画
 * @return nil
 */
static int l_slider_set_value(lua_State *L)
{
    lv_obj_t *slider = slider_check(L);
    int value = (int)luaL_checkinteger(L, 2);
    bool animated = lua_toboolean(L, 3);
    airui_slider_set_value(slider, value, animated);
    return 0;
}

/**
 * Slider:get_value() 获取当前滑块值
 * @api slider:get_value()
 * @return int 当前值
 */
static int l_slider_get_value(lua_State *L)
{
    lv_obj_t *slider = slider_check(L);
    lua_pushinteger(L, airui_slider_get_value(slider));
    return 1;
}

/**
 * Slider:set_range(min, max) 设置取值范围
 * @api slider:set_range(min, max)
 * @int min 最小值
 * @int max 最大值
 * @return nil
 */
static int l_slider_set_range(lua_State *L)
{
    lv_obj_t *slider = slider_check(L);
    int min = (int)luaL_checkinteger(L, 2);
    int max = (int)luaL_checkinteger(L, 3);
    airui_slider_set_range(slider, min, max);
    return 0;
}

/**
 * Slider:set_style(style) 设置滑块样式
 * @api slider:set_style(style)
 * @table style 样式表，仅覆盖传入字段
 * @return nil
 */
static int l_slider_set_style(lua_State *L)
{
    lv_obj_t *slider = slider_check(L);
    luaL_checktype(L, 2, LUA_TTABLE);
    airui_slider_set_style(slider, L, 2);
    return 0;
}

/**
 * Slider:destroy() 销毁滑块对象
 * @api slider:destroy()
 * @return nil
 */
static int l_slider_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_SLIDER_MT);
}

/**
 * 注册 Slider 元表
 * @param L Lua 状态
 */
void airui_register_slider_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_SLIDER_MT);
    airui_component_set_metatable_gc(L);

    static const luaL_Reg methods[] = {
        {"set_value", l_slider_set_value},
        {"get_value", l_slider_get_value},
        {"set_range", l_slider_set_range},
        {"set_style", l_slider_set_style},
        {"destroy", l_slider_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Slider 创建入口（供主模块注册）
 * @param L Lua 状态
 * @return 创建结果
 */
int airui_slider_create(lua_State *L)
{
    return l_airui_slider(L);
}
