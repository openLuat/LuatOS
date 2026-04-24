/*
@module  airui.image
@summary AIRUI Image 组件 Lua 绑定
@version 0.1.0
@date    2025.12.02
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.image"
#include "luat_log.h"

// 元表名称
#define AIRUI_IMAGE_MT "airui.image"

/**
 * 创建 Image 组件
 * @api airui.image(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 100
 * @string config.src 图片路径，可选
 * @table config.pivot 旋转中心点，可选，格式 {x=0, y=0}
 * @int config.rotation 旋转角度，可选，0.1 度单位，900 = 90.0 度
 * @int config.zoom 缩放比例，默认 256（100%）
 * @int config.opacity 透明度，默认 255（不透明），范围 0-255
 * @function config.on_click 点击回调函数，可选
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Image 对象
 */
static int l_airui_image(lua_State *L) {
    // 检查上下文是否已初始化（从注册表获取）
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
    
    lv_obj_t *img = airui_image_create_from_config(L, 1);
    if (img == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    airui_push_component_userdata(L, img, AIRUI_IMAGE_MT);
    return 1;
}

/**
 * Image:set_src(src)
 * @api image:set_src(src)
 * @string src 图片路径或符号
 * @return nil
 */
static int l_image_set_src(lua_State *L) {
    lv_obj_t *img = airui_check_component(L, 1, AIRUI_IMAGE_MT);
    const char *src = luaL_checkstring(L, 2);
    airui_image_set_src(img, src);
    return 0;
}

/**
 * Image:set_pivot(x, y)
 * @api image:set_pivot(x, y)
 * @int x 旋转中心 X 坐标
 * @int y 旋转中心 Y 坐标
 * @return nil
 */
static int l_image_set_pivot(lua_State *L) {
    lv_obj_t *img = airui_check_component(L, 1, AIRUI_IMAGE_MT);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    airui_image_set_pivot(img, x, y);
    return 0;
}

/**
 * Image:set_rotation(rotation)
 * @api image:set_rotation(rotation)
 * @int rotation 旋转角度，0.1 度单位，900 = 90.0 度
 * @return nil
 */
static int l_image_set_rotation(lua_State *L) {
    lv_obj_t *img = airui_check_component(L, 1, AIRUI_IMAGE_MT);
    int rotation = luaL_checkinteger(L, 2);
    airui_image_set_rotation(img, rotation);
    return 0;
}

/**
 * Image:set_zoom(zoom)
 * @api image:set_zoom(zoom)
 * @int zoom 缩放比例，256 = 100%
 * @return nil
 */
static int l_image_set_zoom(lua_State *L) {
    lv_obj_t *img = airui_check_component(L, 1, AIRUI_IMAGE_MT);
    int zoom = luaL_checkinteger(L, 2);
    airui_image_set_zoom(img, zoom);
    return 0;
}

/**
 * Image:set_opacity(opacity)
 * @api image:set_opacity(opacity)
 * @int opacity 透明度，0-255
 * @return nil
 */
static int l_image_set_opacity(lua_State *L) {
    lv_obj_t *img = airui_check_component(L, 1, AIRUI_IMAGE_MT);
    int opacity = luaL_checkinteger(L, 2);
    airui_image_set_opacity(img, opacity);
    return 0;
}

/**
 * Image:get_pos()
 * @api image:get_pos()
 * @return int x X 坐标
 * @return int y Y 坐标
 */
static int l_image_get_pos(lua_State *L) {
    lv_obj_t *img = airui_check_component(L, 1, AIRUI_IMAGE_MT);
    int32_t x = 0;
    int32_t y = 0;
    if (airui_component_get_pos(img, &x, &y) != AIRUI_OK) {
        return luaL_error(L, "invalid image");
    }
    lua_pushinteger(L, x);
    lua_pushinteger(L, y);
    return 2;
}

/**
 * Image:set_pos(x, y)
 * @api image:set_pos(x, y)
 * @int x X 坐标
 * @int y Y 坐标
 */
static int l_image_set_pos(lua_State *L) {
    lv_obj_t *img = airui_check_component(L, 1, AIRUI_IMAGE_MT);
    int32_t x = (int32_t)luaL_checkinteger(L, 2);
    int32_t y = (int32_t)luaL_checkinteger(L, 3);
    if (airui_component_set_pos(img, x, y) != AIRUI_OK) {
        return luaL_error(L, "invalid image");
    }
    return 0;
}

/**
 * Image:move(dx, dy)
 * @api image:move(dx, dy)
 * @int dx X 方向偏移量
 * @int dy Y 方向偏移量
 */
static int l_image_move(lua_State *L) {
    lv_obj_t *img = airui_check_component(L, 1, AIRUI_IMAGE_MT);
    int32_t dx = (int32_t)luaL_checkinteger(L, 2);
    int32_t dy = (int32_t)luaL_checkinteger(L, 3);
    if (airui_component_move(img, dx, dy) != AIRUI_OK) {
        return luaL_error(L, "invalid image");
    }
    return 0;
}

/**
 * Image:destroy（手动销毁）
 */
static int l_image_destroy(lua_State *L) {
    return airui_component_destroy_userdata(L, 1, AIRUI_IMAGE_MT);
}

/**
 * 注册 Image 元表
 * @param L Lua 状态
 */
void airui_register_image_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_IMAGE_MT);
    
    // 设置方法表
    static const luaL_Reg methods[] = {
        {"set_src", l_image_set_src},
        {"set_pivot", l_image_set_pivot},
        {"set_rotation", l_image_set_rotation},
        {"set_zoom", l_image_set_zoom},
        {"set_opacity", l_image_set_opacity},
        {"get_pos", l_image_get_pos},
        {"set_pos", l_image_set_pos},
        {"move", l_image_move},
        {"destroy", l_image_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };
    
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    
    lua_pop(L, 1);
}

/**
 * Image 创建函数（供主模块注册）
 */
int airui_image_create(lua_State *L) {
    return l_airui_image(L);
}

