/*
@module  easylvgl.image
@summary EasyLVGL Image 组件 Lua 绑定
@version 0.1.0
@date    2025.12.02
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include <string.h>

#define LUAT_LOG_TAG "easylvgl.image"
#include "luat_log.h"

// 元表名称
#define EASYLVGL_IMAGE_MT "easylvgl.image"

/**
 * 创建 Image 组件
 * @api easylvgl.image(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 100
 * @string config.src 图片路径，可选
 * @table config.pivot 旋转中心点，可选，格式 {x=0, y=0}
 * @int config.zoom 缩放比例，默认 256（100%）
 * @int config.opacity 透明度，默认 255（不透明），范围 0-255
 * @function config.on_click 点击回调函数，可选
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Image 对象
 */
static int l_easylvgl_image(lua_State *L) {
    // 检查上下文是否已初始化（从注册表获取）
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    
    if (ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }
    
    luaL_checktype(L, 1, LUA_TTABLE);
    
    lv_obj_t *img = easylvgl_image_create_from_config(L, 1);
    if (img == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    easylvgl_push_component_userdata(L, img, EASYLVGL_IMAGE_MT);
    return 1;
}

/**
 * Image:set_src(src)
 * @api image:set_src(src)
 * @string src 图片路径或符号
 * @return nil
 */
static int l_image_set_src(lua_State *L) {
    lv_obj_t *img = easylvgl_check_component(L, 1, EASYLVGL_IMAGE_MT);
    const char *src = luaL_checkstring(L, 2);
    easylvgl_image_set_src(img, src);
    return 0;
}

/**
 * Image:set_zoom(zoom)
 * @api image:set_zoom(zoom)
 * @int zoom 缩放比例，256 = 100%
 * @return nil
 */
static int l_image_set_zoom(lua_State *L) {
    lv_obj_t *img = easylvgl_check_component(L, 1, EASYLVGL_IMAGE_MT);
    int zoom = luaL_checkinteger(L, 2);
    easylvgl_image_set_zoom(img, zoom);
    return 0;
}

/**
 * Image:set_opacity(opacity)
 * @api image:set_opacity(opacity)
 * @int opacity 透明度，0-255
 * @return nil
 */
static int l_image_set_opacity(lua_State *L) {
    lv_obj_t *img = easylvgl_check_component(L, 1, EASYLVGL_IMAGE_MT);
    int opacity = luaL_checkinteger(L, 2);
    easylvgl_image_set_opacity(img, opacity);
    return 0;
}

/**
 * Image:destroy（手动销毁）
 */
static int l_image_destroy(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_IMAGE_MT);
    if (ud != NULL && ud->obj != NULL) {
        // 获取元数据并释放
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            easylvgl_component_meta_free(meta);
        }
        
        // 删除 LVGL 对象
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

/**
 * 注册 Image 元表
 * @param L Lua 状态
 */
void easylvgl_register_image_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_IMAGE_MT);
    
    // 设置方法表
    static const luaL_Reg methods[] = {
        {"set_src", l_image_set_src},
        {"set_zoom", l_image_set_zoom},
        {"set_opacity", l_image_set_opacity},
        {"destroy", l_image_destroy},
        {NULL, NULL}
    };
    
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    
    lua_pop(L, 1);
}

/**
 * Image 创建函数（供主模块注册）
 */
int easylvgl_image_create(lua_State *L) {
    return l_easylvgl_image(L);
}

