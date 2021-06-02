
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_area_set(lv_area_t* area_p, lv_coord_t x1, lv_coord_t y1, lv_coord_t x2, lv_coord_t y2)
int luat_lv_area_set(lua_State *L) {
    LV_DEBUG("CALL %s", lv_area_set);
    lua_pushvalue(L, 1);
    lv_area_t area_p = {0};
    lua_geti(L, -1, 1); area_p.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); area_p.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); area_p.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); area_p.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_coord_t x1 = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t y1 = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_coord_t x2 = (lv_coord_t)luaL_checkinteger(L, 4);
    lv_coord_t y2 = (lv_coord_t)luaL_checkinteger(L, 5);
    lv_area_set(&area_p ,x1 ,y1 ,x2 ,y2);
    return 0;
}

//  void lv_area_copy(lv_area_t* dest, lv_area_t* src)
int luat_lv_area_copy(lua_State *L) {
    LV_DEBUG("CALL %s", lv_area_copy);
    lua_pushvalue(L, 1);
    lv_area_t dest = {0};
    lua_geti(L, -1, 1); dest.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); dest.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); dest.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); dest.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lua_pushvalue(L, 2);
    lv_area_t src = {0};
    lua_geti(L, -1, 1); src.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); src.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); src.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); src.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_area_copy(&dest ,&src);
    return 0;
}

//  lv_coord_t lv_area_get_width(lv_area_t* area_p)
int luat_lv_area_get_width(lua_State *L) {
    LV_DEBUG("CALL %s", lv_area_get_width);
    lua_pushvalue(L, 1);
    lv_area_t area_p = {0};
    lua_geti(L, -1, 1); area_p.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); area_p.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); area_p.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); area_p.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_coord_t ret;
    ret = lv_area_get_width(&area_p);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_area_get_height(lv_area_t* area_p)
int luat_lv_area_get_height(lua_State *L) {
    LV_DEBUG("CALL %s", lv_area_get_height);
    lua_pushvalue(L, 1);
    lv_area_t area_p = {0};
    lua_geti(L, -1, 1); area_p.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); area_p.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); area_p.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); area_p.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_coord_t ret;
    ret = lv_area_get_height(&area_p);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_area_set_width(lv_area_t* area_p, lv_coord_t w)
int luat_lv_area_set_width(lua_State *L) {
    LV_DEBUG("CALL %s", lv_area_set_width);
    lua_pushvalue(L, 1);
    lv_area_t area_p = {0};
    lua_geti(L, -1, 1); area_p.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); area_p.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); area_p.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); area_p.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_coord_t w = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_area_set_width(&area_p ,w);
    return 0;
}

//  void lv_area_set_height(lv_area_t* area_p, lv_coord_t h)
int luat_lv_area_set_height(lua_State *L) {
    LV_DEBUG("CALL %s", lv_area_set_height);
    lua_pushvalue(L, 1);
    lv_area_t area_p = {0};
    lua_geti(L, -1, 1); area_p.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); area_p.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); area_p.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); area_p.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_coord_t h = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_area_set_height(&area_p ,h);
    return 0;
}

//  uint32_t lv_area_get_size(lv_area_t* area_p)
int luat_lv_area_get_size(lua_State *L) {
    LV_DEBUG("CALL %s", lv_area_get_size);
    lua_pushvalue(L, 1);
    lv_area_t area_p = {0};
    lua_geti(L, -1, 1); area_p.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); area_p.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); area_p.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); area_p.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    uint32_t ret;
    ret = lv_area_get_size(&area_p);
    lua_pushinteger(L, ret);
    return 1;
}

