#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "../src/lv_gif/lv_gif.h"


int luat_lv_gif_create(lua_State *L) {
    lv_obj_t * parent = lua_touserdata(L, 1);
    const char* path = luaL_checkstring(L, 2);
    lv_obj_t *gif = lv_gif_create_from_file(parent, path);
    lua_pushlightuserdata(L, gif);
    return 1;
}

int luat_lv_gif_restart(lua_State *L) {
    lv_obj_t * gif = lua_touserdata(L, 1);
    lv_gif_restart(gif);
    return 0;
}

int luat_lv_gif_delete(lua_State *L);
