
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_led_create(lv_obj_t* parent)
int luat_lv_led_create(lua_State *L) {
    LV_DEBUG("CALL lv_led_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_led_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_led_set_color(lv_obj_t* led, lv_color_t color)
int luat_lv_led_set_color(lua_State *L) {
    LV_DEBUG("CALL lv_led_set_color");
    lv_obj_t* led = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    lv_led_set_color(led ,color);
    return 0;
}

//  void lv_led_set_brightness(lv_obj_t* led, uint8_t bright)
int luat_lv_led_set_brightness(lua_State *L) {
    LV_DEBUG("CALL lv_led_set_brightness");
    lv_obj_t* led = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t bright = (uint8_t)luaL_checkinteger(L, 2);
    lv_led_set_brightness(led ,bright);
    return 0;
}

//  void lv_led_on(lv_obj_t* led)
int luat_lv_led_on(lua_State *L) {
    LV_DEBUG("CALL lv_led_on");
    lv_obj_t* led = (lv_obj_t*)lua_touserdata(L, 1);
    lv_led_on(led);
    return 0;
}

//  void lv_led_off(lv_obj_t* led)
int luat_lv_led_off(lua_State *L) {
    LV_DEBUG("CALL lv_led_off");
    lv_obj_t* led = (lv_obj_t*)lua_touserdata(L, 1);
    lv_led_off(led);
    return 0;
}

//  void lv_led_toggle(lv_obj_t* led)
int luat_lv_led_toggle(lua_State *L) {
    LV_DEBUG("CALL lv_led_toggle");
    lv_obj_t* led = (lv_obj_t*)lua_touserdata(L, 1);
    lv_led_toggle(led);
    return 0;
}

//  uint8_t lv_led_get_brightness(lv_obj_t* obj)
int luat_lv_led_get_brightness(lua_State *L) {
    LV_DEBUG("CALL lv_led_get_brightness");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t ret;
    ret = lv_led_get_brightness(obj);
    lua_pushinteger(L, ret);
    return 1;
}

