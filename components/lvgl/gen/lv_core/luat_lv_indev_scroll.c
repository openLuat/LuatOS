
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_coord_t lv_indev_scroll_throw_predict(lv_indev_t* indev, lv_dir_t dir)
int luat_lv_indev_scroll_throw_predict(lua_State *L) {
    LV_DEBUG("CALL lv_indev_scroll_throw_predict");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_dir_t dir = (lv_dir_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_indev_scroll_throw_predict(indev ,dir);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_indev_scroll_get_snap_dist(lv_obj_t* obj, lv_point_t* p)
int luat_lv_indev_scroll_get_snap_dist(lua_State *L) {
    LV_DEBUG("CALL lv_indev_scroll_get_snap_dist");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lua_pushvalue(L, 2);
    lv_point_t p = {0};
    lua_geti(L, -1, 1); p.x = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); p.y = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_indev_scroll_get_snap_dist(obj ,&p);
    return 0;
}

