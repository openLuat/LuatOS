
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_led_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_led_create(lua_State *L) {
    LV_DEBUG("CALL lv_led_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_led_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_led_set_bright(lv_obj_t* led, uint8_t bright)
int luat_lv_led_set_bright(lua_State *L) {
    LV_DEBUG("CALL lv_led_set_bright");
    lv_obj_t* led = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t bright = (uint8_t)luaL_checkinteger(L, 2);
    lv_led_set_bright(led ,bright);
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

//  uint8_t lv_led_get_bright(lv_obj_t* led)
int luat_lv_led_get_bright(lua_State *L) {
    LV_DEBUG("CALL lv_led_get_bright");
    lv_obj_t* led = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t ret;
    ret = lv_led_get_bright(led);
    lua_pushinteger(L, ret);
    return 1;
}

