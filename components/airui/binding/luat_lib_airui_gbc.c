/*
 * AirUI 绑定：airui.gbc GBC 模拟器组件
 *
 * 镜像 luat_lib_airui_nes.c 的结构：
 *   - airui.gbc({rom=..., parent=..., scale=1-3, x=0, y=0}) 工厂
 *   - gbc:key(key_code, pressed) 按键
 *   - gbc:destroy() / gbc:is_destroyed() 销毁
 */

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"

#include "luat_airui_component.h"
#include "luat_airui_binding.h"

#ifdef LUAT_USE_AIRUI
#ifdef LUAT_USE_GBC

/* ========== airui.gbc(config) 工厂 ========== */

static int l_airui_gbc(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    lv_obj_t *gbc = airui_gbc_create_from_config(L, 1);
    if (!gbc) {
        lua_pushnil(L);
        return 1;
    }
    airui_push_component_userdata(L, gbc, AIRUI_GBC_MT);
    return 1;
}

/* ========== gbc:key(key_code, pressed) ========== */

static int l_gbc_key(lua_State *L) {
    lv_obj_t *gbc = airui_check_component(L, 1, AIRUI_GBC_MT);
    int key = (int)luaL_checkinteger(L, 2);
    int pressed = (int)luaL_checkinteger(L, 3);
    airui_gbc_set_key(gbc, key, pressed);
    return 0;
}

/* ========== gbc:destroy() ========== */

static int l_gbc_destroy(lua_State *L) {
    return airui_component_destroy_userdata(L, 1, AIRUI_GBC_MT);
}

/* ========== 元表注册 ========== */

void airui_register_gbc_meta(lua_State *L) {
    luaL_newmetatable(L, AIRUI_GBC_MT);
    static const luaL_Reg methods[] = {
        {"destroy",      l_gbc_destroy},
        {"key",          l_gbc_key},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

int airui_gbc_create(lua_State *L) { return l_airui_gbc(L); }

#else  /* LUAT_USE_GBC */

void airui_register_gbc_meta(lua_State *L) { (void)L; }
int airui_gbc_create(lua_State *L) { lua_pushnil(L); return 1; }

#endif /* LUAT_USE_GBC */
#endif /* LUAT_USE_AIRUI */