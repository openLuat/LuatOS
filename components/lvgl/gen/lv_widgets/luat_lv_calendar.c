
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_calendar_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_calendar_create(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_calendar_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_calendar_set_today_date(lv_obj_t* calendar, lv_calendar_date_t* today)
int luat_lv_calendar_set_today_date(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_set_today_date");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    lv_calendar_date_t* today = (lv_calendar_date_t*)lua_touserdata(L, 2);
    lv_calendar_set_today_date(calendar ,today);
    return 0;
}

//  void lv_calendar_set_showed_date(lv_obj_t* calendar, lv_calendar_date_t* showed)
int luat_lv_calendar_set_showed_date(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_set_showed_date");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    lv_calendar_date_t* showed = (lv_calendar_date_t*)lua_touserdata(L, 2);
    lv_calendar_set_showed_date(calendar ,showed);
    return 0;
}

//  lv_calendar_date_t* lv_calendar_get_today_date(lv_obj_t* calendar)
int luat_lv_calendar_get_today_date(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_get_today_date");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    lv_calendar_date_t* ret = NULL;
    ret = lv_calendar_get_today_date(calendar);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_calendar_date_t* lv_calendar_get_showed_date(lv_obj_t* calendar)
int luat_lv_calendar_get_showed_date(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_get_showed_date");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    lv_calendar_date_t* ret = NULL;
    ret = lv_calendar_get_showed_date(calendar);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_calendar_date_t* lv_calendar_get_pressed_date(lv_obj_t* calendar)
int luat_lv_calendar_get_pressed_date(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_get_pressed_date");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    lv_calendar_date_t* ret = NULL;
    ret = lv_calendar_get_pressed_date(calendar);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_calendar_date_t* lv_calendar_get_highlighted_dates(lv_obj_t* calendar)
int luat_lv_calendar_get_highlighted_dates(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_get_highlighted_dates");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    lv_calendar_date_t* ret = NULL;
    ret = lv_calendar_get_highlighted_dates(calendar);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint16_t lv_calendar_get_highlighted_dates_num(lv_obj_t* calendar)
int luat_lv_calendar_get_highlighted_dates_num(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_get_highlighted_dates_num");
    lv_obj_t* calendar = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_calendar_get_highlighted_dates_num(calendar);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint8_t lv_calendar_get_day_of_week(uint32_t year, uint32_t month, uint32_t day)
int luat_lv_calendar_get_day_of_week(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_get_day_of_week");
    uint32_t year = (uint32_t)luaL_checkinteger(L, 1);
    uint32_t month = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t day = (uint32_t)luaL_checkinteger(L, 3);
    uint8_t ret;
    ret = lv_calendar_get_day_of_week(year ,month ,day);
    lua_pushinteger(L, ret);
    return 1;
}

