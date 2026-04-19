/*
@module  airui.shape
@summary AIRUI Shape 图形绘制组件 Lua 绑定
@version 0.1.0
@date    2026.04.17
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define AIRUI_SHAPE_MT "airui.shape"

/**
 * 创建 Shape 组件
 * @api airui.shape(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 100
 * @table config.items 图元数组，可选。当前支持以下图元：
 * line 直线：
 *   - type = "line"
 *   - x1, y1 起点坐标
 *   - x2, y2 终点坐标
 *   - color 线条颜色，0xRRGGBB
 *   - width 线宽，默认 1
 *   - opacity 透明度，0-255，默认 255
 *   - dash_width 虚线实线段长度，默认 0
 *   - dash_gap 虚线间隔长度，默认 0
 *   - round_start 起点是否圆头，bool
 *   - round_end 终点是否圆头，bool
 * circle 圆形：
 *   - type = "circle"
 *   - cx, cy 圆心坐标
 *   - r 半径
 *   - color 描边颜色，0xRRGGBB
 *   - width 描边宽度，默认 1
 *   - opacity 描边透明度，0-255
 *   - fill 是否填充，bool
 *   - fill_color 填充颜色，默认同 color
 *   - fill_opacity 填充透明度，0-255
 * ellipse 椭圆：
 *   - type = "ellipse"
 *   - cx, cy 椭圆中心坐标
 *   - rx, ry X/Y 半径
 *   - color 描边颜色，0xRRGGBB
 *   - width 描边宽度，默认 1
 *   - opacity 描边透明度，0-255
 *   - fill 是否填充，bool
 *   - fill_color 填充颜色，默认同 color
 *   - fill_opacity 填充透明度，0-255
 *   - segments 椭圆折线逼近分段数，可选
 * rect 矩形/圆角矩形：
 *   - type = "rect"
 *   - x, y 左上角坐标
 *   - w, h 宽高
 *   - radius 圆角半径，默认 0
 *   - color 描边颜色，0xRRGGBB
 *   - width 描边宽度，默认 1
 *   - opacity 描边透明度，0-255
 *   - fill 是否填充，bool
 *   - fill_color 填充颜色，默认同 color
 *   - fill_opacity 填充透明度，0-255
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Shape 对象
 *
 * @usage
 * local shape = airui.shape({
 *     x = 20, y = 20, w = 200, h = 120,
 *     items = {
 *         {type = "line", x1 = 10, y1 = 10, x2 = 180, y2 = 10, color = 0xff0000, width = 2},
 *         {type = "circle", cx = 40, cy = 60, r = 18, color = 0x00ff00, width = 2},
 *         {type = "ellipse", cx = 100, cy = 60, rx = 30, ry = 18, color = 0x00ffff, width = 2},
 *         {type = "rect", x = 140, y = 30, w = 40, h = 40, radius = 8, color = 0xffffff, width = 2, fill = true, fill_color = 0x334455},
 *     }
 * })
 */
static int l_airui_shape(lua_State *L)
{
    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);

    if (ctx == NULL) {
        luaL_error(L, "airui not initialized, call airui.init() first");
        return 0;
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    {
        lv_obj_t *shape = airui_shape_create_from_config(L, 1);
        if (shape == NULL) {
            lua_pushnil(L);
            return 1;
        }
        airui_push_component_userdata(L, shape, AIRUI_SHAPE_MT);
    }
    return 1;
}

/**
 * Shape:set_items(items)
 * @api shape:set_items(items)
 * @table items 图元数组，会整体替换当前所有图元
 * @return nil
 *
 * @usage
 * shape:set_items({
 *     {type = "line", x1 = 10, y1 = 10, x2 = 100, y2 = 10, color = 0xff0000, width = 2},
 *     {type = "circle", cx = 60, cy = 50, r = 20, color = 0x00ff00, fill = true, fill_color = 0x003300}
 * })
 */
static int l_shape_set_items(lua_State *L)
{
    lv_obj_t *shape = airui_check_component(L, 1, AIRUI_SHAPE_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    if (airui_shape_set_items(shape, L, 2) != AIRUI_OK) {
        return luaL_error(L, "shape:set_items failed");
    }
    return 0;
}

/**
 * Shape:add_item(item)
 * @api shape:add_item(item)
 * @table item 单个图元配置
 * @return nil
 *
 * @usage
 * shape:add_item({
 *     type = "ellipse",
 *     cx = 120,
 *     cy = 60,
 *     rx = 36,
 *     ry = 20,
 *     color = 0x00ffff,
 *     width = 2
 * })
 */
static int l_shape_add_item(lua_State *L)
{
    lv_obj_t *shape = airui_check_component(L, 1, AIRUI_SHAPE_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    if (airui_shape_add_item(shape, L, 2) != AIRUI_OK) {
        return luaL_error(L, "shape:add_item failed");
    }
    return 0;
}

/**
 * Shape:clear()
 * @api shape:clear()
 * @return nil
 *
 * @usage
 * shape:clear()
 */
static int l_shape_clear(lua_State *L)
{
    lv_obj_t *shape = airui_check_component(L, 1, AIRUI_SHAPE_MT);
    airui_shape_clear(shape);
    return 0;
}

/**
 * Shape:get_count()
 * @api shape:get_count()
 * @return int count 当前图元数量
 *
 * @usage
 * local count = shape:get_count()
 * log.info("shape", "item count", count)
 */
static int l_shape_get_count(lua_State *L)
{
    lv_obj_t *shape = airui_check_component(L, 1, AIRUI_SHAPE_MT);
    lua_pushinteger(L, airui_shape_get_count(shape));
    return 1;
}

/**
 * Shape:get_pos()
 * @api shape:get_pos()
 * @return int x X 坐标
 * @return int y Y 坐标
 *
 * @usage
 * local x, y = shape:get_pos()
 * log.info("shape", "pos", x, y)
 */
static int l_shape_get_pos(lua_State *L)
{
    lv_obj_t *shape = airui_check_component(L, 1, AIRUI_SHAPE_MT);
    int32_t x = 0;
    int32_t y = 0;
    if (airui_component_get_pos(shape, &x, &y) != AIRUI_OK) {
        return luaL_error(L, "invalid shape");
    }
    lua_pushinteger(L, x);
    lua_pushinteger(L, y);
    return 2;
}

/**
 * Shape:set_pos(x, y)
 * @api shape:set_pos(x, y)
 * @int x X 坐标
 * @int y Y 坐标
 * @return nil
 *
 * @usage
 * shape:set_pos(40, 80)
 */
static int l_shape_set_pos(lua_State *L)
{
    lv_obj_t *shape = airui_check_component(L, 1, AIRUI_SHAPE_MT);
    int32_t x = (int32_t)luaL_checkinteger(L, 2);
    int32_t y = (int32_t)luaL_checkinteger(L, 3);
    if (airui_component_set_pos(shape, x, y) != AIRUI_OK) {
        return luaL_error(L, "invalid shape");
    }
    return 0;
}

/**
 * Shape:move(dx, dy)
 * @api shape:move(dx, dy)
 * @int dx X 方向偏移量
 * @int dy Y 方向偏移量
 * @return nil
 *
 * @usage
 * shape:move(10, -5)
 */
static int l_shape_move(lua_State *L)
{
    lv_obj_t *shape = airui_check_component(L, 1, AIRUI_SHAPE_MT);
    int32_t dx = (int32_t)luaL_checkinteger(L, 2);
    int32_t dy = (int32_t)luaL_checkinteger(L, 3);
    if (airui_component_move(shape, dx, dy) != AIRUI_OK) {
        return luaL_error(L, "invalid shape");
    }
    return 0;
}

/**
 * Shape:destroy（手动销毁）
 *
 * @usage
 * shape:destroy()
 */
static int l_shape_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_SHAPE_MT);
}

/**
 * 注册 Shape 元表
 * @param L Lua 状态机
 */
void airui_register_shape_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_SHAPE_MT);
    static const luaL_Reg methods[] = {
        {"set_items", l_shape_set_items},
        {"add_item", l_shape_add_item},
        {"clear", l_shape_clear},
        {"get_count", l_shape_get_count},
        {"get_pos", l_shape_get_pos},
        {"set_pos", l_shape_set_pos},
        {"move", l_shape_move},
        {"destroy", l_shape_destroy},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Shape 创建函数（供主模块注册）
 */
int airui_shape_create(lua_State *L)
{
    return l_airui_shape(L);
}
