
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_obj_scroll_by(lv_obj_t* obj, lv_coord_t x, lv_coord_t y, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_by(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_by");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)luaL_checkinteger(L, 4);
    lv_obj_scroll_by(obj ,x ,y ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to(lv_obj_t* obj, lv_coord_t x, lv_coord_t y, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)luaL_checkinteger(L, 4);
    lv_obj_scroll_to(obj ,x ,y ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to_x(lv_obj_t* obj, lv_coord_t x, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)luaL_checkinteger(L, 3);
    lv_obj_scroll_to_x(obj ,x ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to_y(lv_obj_t* obj, lv_coord_t y, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)luaL_checkinteger(L, 3);
    lv_obj_scroll_to_y(obj ,y ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to_view(lv_obj_t* obj, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to_view(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to_view");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)luaL_checkinteger(L, 2);
    lv_obj_scroll_to_view(obj ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to_view_recursive(lv_obj_t* obj, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to_view_recursive(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to_view_recursive");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)luaL_checkinteger(L, 2);
    lv_obj_scroll_to_view_recursive(obj ,anim_en);
    return 0;
}

//  void lv_obj_scrollbar_invalidate(lv_obj_t* obj)
int luat_lv_obj_scrollbar_invalidate(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scrollbar_invalidate");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_scrollbar_invalidate(obj);
    return 0;
}

