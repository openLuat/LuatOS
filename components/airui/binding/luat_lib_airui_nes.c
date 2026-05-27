/*
@module  airui.nes
@summary AIRUI NES/FC 模拟器组件 Lua 绑定（纯视频输出，控制由外部 Lua 脚本实现）
@version 1.0.0
@date    2026.05.25
@tag     LUAT_USE_AIRUI, LUAT_USE_NES
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui.h"
#include "../inc/luat_airui_component.h"
#include "../inc/luat_airui_binding.h"

#define LUAT_LOG_TAG "airui.nes"
#include "luat_log.h"

#ifdef LUAT_USE_NES

/**
 * 创建 NES 模拟器组件（纯视频输出，256×240 游戏画面）
 * @api airui.nes(config)
 * @table config 配置表
 * @string config.rom ROM 文件路径（*.nes），必填
 * @int config.scale 缩放倍数 1~3，默认 1
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata NES 组件对象，失败返回 nil
 * @usage
 * local nes = airui.nes({
 *     parent = container,           -- 嵌入到容器中
 *     rom    = "/luadb/mario.nes",  -- ROM 路径
 *     scale  = 2,                   -- 2x 缩放
 *     x      = 0, y      = 0,       -- 坐标
 * })
 * 
 * -- 构造虚拟按键控制
 * airui.button({
 *     text = "A", w = 64, h = 64,
 *     on_pressed  = function() nes:key(airui.NES_KEY_A, 1) end,
 *     on_released = function() nes:key(airui.NES_KEY_A, 0) end,
 * })
 * 
 * -- 键盘映射（AirUI keypad_subscribe）
 * airui.keypad_subscribe(function(key, pressed, timestamp)
 *     if key == SDL_SCANCODE_X then
 *         nes:key(airui.NES_KEY_A, pressed and 1 or 0)
 *     end
 * end)
 */
static int l_airui_nes(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    lv_obj_t *nes = airui_nes_create_from_config(L, 1);
    if (!nes) {
        lua_pushnil(L);
        return 1;
    }
    airui_push_component_userdata(L, nes, AIRUI_NES_MT);
    return 1;
}

/**
 * 注入模拟器按键
 * @api nes:key(key_code, pressed)
 * @int key_code 按键编码（使用 airui.NES_KEY_* 常量）
 * @int pressed 按键状态，1=按下，0=释放
 * @return nil
 * @usage
 * nes:key(airui.NES_KEY_A, 1)   -- 按下 A
 * nes:key(airui.NES_KEY_A, 0)   -- 释放 A
 */
static int l_nes_key(lua_State *L) {
    lv_obj_t *nes = airui_check_component(L, 1, AIRUI_NES_MT);
    int key = (int)luaL_checkinteger(L, 2);
    int pressed = (int)luaL_checkinteger(L, 3);
    airui_nes_set_key(nes, key, pressed);
    return 0;
}

/**
 * 销毁 NES 组件及关联资源（模拟器线程、帧缓冲、LVGL 对象）
 * @api nes:destroy()
 * @return nil
 */
static int l_nes_destroy(lua_State *L) {
    return airui_component_destroy_userdata(L, 1, AIRUI_NES_MT);
}

/**
 * 注册 NES 组件元表及实例方法
 */
void airui_register_nes_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_NES_MT);
    static const luaL_Reg methods[] = {
        {"destroy",      l_nes_destroy},
        {"key",          l_nes_key},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

/**
 * airui.nes 模块入口函数
 * @see l_airui_nes
 */
int airui_nes_create(lua_State *L) {
    return l_airui_nes(L);
}

#else  /* LUAT_USE_NES */

void airui_register_nes_meta(lua_State *L) {
    (void)L;
}

int airui_nes_create(lua_State *L) {
    lua_pushnil(L);
    return 1;
}

#endif /* LUAT_USE_NES */
