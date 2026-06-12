/*
@module  airui.camera
@summary AIRUI Camera 组件 Lua 绑定（摄像头预览，lv_image + 双 framebuffer RGB565）
@version 0.1.0
@date    2026.06.11
@tag     LUAT_USE_AIRUI
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui.camera"
#include "luat_log.h"

#ifdef LUAT_USE_AIRUI_CAMERA

/**
 * 创建 Camera 组件
 * @api airui.camera(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 320
 * @int config.h 高度，默认 240
 * @boolean config.auto_start 创建后是否自动启动，默认 false
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Camera 对象
 */
static int l_airui_camera(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    lv_obj_t *camera = airui_camera_create_from_config(L, 1);
    if (camera == NULL) {
        lua_pushnil(L);
        return 1;
    }

    airui_push_component_userdata(L, camera, AIRUI_CAMERA_MT);
    return 1;
}

static lv_obj_t *camera_check(lua_State *L)
{
    return airui_check_component(L, 1, AIRUI_CAMERA_MT);
}

/**
 * Camera:start()
 * @api camera:start()
 * @return nil
 * @usage
 * camera:start()
 */
static int l_camera_start(lua_State *L)
{
    airui_camera_start(camera_check(L));
    return 0;
}

/**
 * Camera:stop()
 * @api camera:stop()
 * @return nil
 * @usage
 * camera:stop()
 */
static int l_camera_stop(lua_State *L)
{
    airui_camera_stop(camera_check(L));
    return 0;
}

/**
 * Camera:destroy()
 * @api camera:destroy()
 * @return nil
 * @usage
 * camera:destroy()
 */
static int l_camera_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_CAMERA_MT);
}

/**
 * Camera:register()
 * 显式注册为摄像头帧接收目标（底层解码后的 RGB565 帧会直接推送到此组件）
 * @api camera:register()
 * @return nil
 * @usage
 * camera:register()
 */
static int l_camera_register(lua_State *L)
{
    airui_camera_register_target(camera_check(L));
    return 0;
}

/**
 * 注册 Camera 元表
 */
void airui_register_camera_meta(lua_State *L)
{
    luaL_newmetatable(L, AIRUI_CAMERA_MT);
    airui_component_set_metatable_gc(L);

    static const luaL_Reg methods[] = {
        {"start", l_camera_start},
        {"stop", l_camera_stop},
        {"destroy", l_camera_destroy},
        {"register", l_camera_register},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };

    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * Camera 创建函数（供主模块注册）
 */
int airui_camera_create(lua_State *L)
{
    return l_airui_camera(L);
}

#endif /* LUAT_USE_AIRUI_CAMERA */
