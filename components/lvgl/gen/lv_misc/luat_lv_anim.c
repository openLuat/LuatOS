

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"

#if LV_USE_ANIMATION
//  void lv_anim_init(lv_anim_t* a)
int luat_lv_anim_init(lua_State *L) {
    LV_DEBUG("CALL lv_anim_init");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    lv_anim_init(a);
    return 0;
}

//  void lv_anim_set_var(lv_anim_t* a, void* var)
int luat_lv_anim_set_var(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_var");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    void* var = (void*)lua_touserdata(L, 2);
    lv_anim_set_var(a ,var);
    return 0;
}

//  void lv_anim_set_time(lv_anim_t* a, uint32_t duration)
int luat_lv_anim_set_time(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_time");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    uint32_t duration = (uint32_t)luaL_checkinteger(L, 2);
    lv_anim_set_time(a ,duration);
    return 0;
}

//  void lv_anim_set_delay(lv_anim_t* a, uint32_t delay)
int luat_lv_anim_set_delay(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_delay");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    uint32_t delay = (uint32_t)luaL_checkinteger(L, 2);
    lv_anim_set_delay(a ,delay);
    return 0;
}

//  void lv_anim_set_values(lv_anim_t* a, lv_anim_value_t start, lv_anim_value_t end)
int luat_lv_anim_set_values(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_values");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    lv_anim_value_t start = (lv_anim_value_t)luaL_checkinteger(L, 2);
    lv_anim_value_t end = (lv_anim_value_t)luaL_checkinteger(L, 3);
    lv_anim_set_values(a ,start ,end);
    return 0;
}

//  void lv_anim_set_path(lv_anim_t* a, lv_anim_path_t* path)
int luat_lv_anim_set_path(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_path");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 2);
    lv_anim_set_path(a ,path);
    return 0;
}

//  void lv_anim_set_playback_time(lv_anim_t* a, uint32_t time)
int luat_lv_anim_set_playback_time(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_playback_time");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    uint32_t time = (uint32_t)luaL_checkinteger(L, 2);
    lv_anim_set_playback_time(a ,time);
    return 0;
}

//  void lv_anim_set_playback_delay(lv_anim_t* a, uint32_t delay)
int luat_lv_anim_set_playback_delay(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_playback_delay");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    uint32_t delay = (uint32_t)luaL_checkinteger(L, 2);
    lv_anim_set_playback_delay(a ,delay);
    return 0;
}

//  void lv_anim_set_repeat_count(lv_anim_t* a, uint16_t cnt)
int luat_lv_anim_set_repeat_count(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_repeat_count");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    uint16_t cnt = (uint16_t)luaL_checkinteger(L, 2);
    lv_anim_set_repeat_count(a ,cnt);
    return 0;
}

//  void lv_anim_set_repeat_delay(lv_anim_t* a, uint32_t delay)
int luat_lv_anim_set_repeat_delay(lua_State *L) {
    LV_DEBUG("CALL lv_anim_set_repeat_delay");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    uint32_t delay = (uint32_t)luaL_checkinteger(L, 2);
    lv_anim_set_repeat_delay(a ,delay);
    return 0;
}

//  void lv_anim_start(lv_anim_t* a)
int luat_lv_anim_start(lua_State *L) {
    LV_DEBUG("CALL lv_anim_start");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    lv_anim_start(a);
    return 0;
}

//  void lv_anim_path_init(lv_anim_path_t* path)
int luat_lv_anim_path_init(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_init");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    lv_anim_path_init(path);
    return 0;
}

//  void lv_anim_path_set_user_data(lv_anim_path_t* path, void* user_data)
int luat_lv_anim_path_set_user_data(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_set_user_data");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    void* user_data = (void*)lua_touserdata(L, 2);
    lv_anim_path_set_user_data(path ,user_data);
    return 0;
}

//  uint32_t lv_anim_get_delay(lv_anim_t* a)
int luat_lv_anim_get_delay(lua_State *L) {
    LV_DEBUG("CALL lv_anim_get_delay");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_anim_get_delay(a);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_anim_del(void* var, lv_anim_exec_xcb_t exec_cb)
int luat_lv_anim_del(lua_State *L) {
    LV_DEBUG("CALL lv_anim_del");
    void* var = (void*)lua_touserdata(L, 1);
    lv_anim_exec_xcb_t exec_cb = NULL;
    // miss arg convert
    bool ret;
    ret = lv_anim_del(var ,exec_cb);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_anim_del_all()
int luat_lv_anim_del_all(lua_State *L) {
    LV_DEBUG("CALL lv_anim_del_all");
    lv_anim_del_all();
    return 0;
}

//  lv_anim_t* lv_anim_get(void* var, lv_anim_exec_xcb_t exec_cb)
int luat_lv_anim_get(lua_State *L) {
    LV_DEBUG("CALL lv_anim_get");
    void* var = (void*)lua_touserdata(L, 1);
    lv_anim_exec_xcb_t exec_cb = NULL;
    // miss arg convert
    lv_anim_t* ret = NULL;
    ret = lv_anim_get(var ,exec_cb);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  bool lv_anim_custom_del(lv_anim_t* a, lv_anim_custom_exec_cb_t exec_cb)
int luat_lv_anim_custom_del(lua_State *L) {
    LV_DEBUG("CALL lv_anim_custom_del");
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 1);
    lv_anim_custom_exec_cb_t exec_cb = NULL;
    // miss arg convert
    bool ret;
    ret = lv_anim_custom_del(a ,exec_cb);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_anim_count_running()
int luat_lv_anim_count_running(lua_State *L) {
    LV_DEBUG("CALL lv_anim_count_running");
    uint16_t ret;
    ret = lv_anim_count_running();
    lua_pushinteger(L, ret);
    return 1;
}

//  uint32_t lv_anim_speed_to_time(uint32_t speed, lv_anim_value_t start, lv_anim_value_t end)
int luat_lv_anim_speed_to_time(lua_State *L) {
    LV_DEBUG("CALL lv_anim_speed_to_time");
    uint32_t speed = (uint32_t)luaL_checkinteger(L, 1);
    lv_anim_value_t start = (lv_anim_value_t)luaL_checkinteger(L, 2);
    lv_anim_value_t end = (lv_anim_value_t)luaL_checkinteger(L, 3);
    uint32_t ret;
    ret = lv_anim_speed_to_time(speed ,start ,end);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_anim_refr_now()
int luat_lv_anim_refr_now(lua_State *L) {
    LV_DEBUG("CALL lv_anim_refr_now");
    lv_anim_refr_now();
    return 0;
}

//  lv_anim_value_t lv_anim_path_linear(lv_anim_path_t* path, lv_anim_t* a)
int luat_lv_anim_path_linear(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_linear");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 2);
    lv_anim_value_t ret;
    ret = lv_anim_path_linear(path ,a);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_anim_value_t lv_anim_path_ease_in(lv_anim_path_t* path, lv_anim_t* a)
int luat_lv_anim_path_ease_in(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_ease_in");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 2);
    lv_anim_value_t ret;
    ret = lv_anim_path_ease_in(path ,a);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_anim_value_t lv_anim_path_ease_out(lv_anim_path_t* path, lv_anim_t* a)
int luat_lv_anim_path_ease_out(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_ease_out");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 2);
    lv_anim_value_t ret;
    ret = lv_anim_path_ease_out(path ,a);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_anim_value_t lv_anim_path_ease_in_out(lv_anim_path_t* path, lv_anim_t* a)
int luat_lv_anim_path_ease_in_out(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_ease_in_out");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 2);
    lv_anim_value_t ret;
    ret = lv_anim_path_ease_in_out(path ,a);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_anim_value_t lv_anim_path_overshoot(lv_anim_path_t* path, lv_anim_t* a)
int luat_lv_anim_path_overshoot(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_overshoot");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 2);
    lv_anim_value_t ret;
    ret = lv_anim_path_overshoot(path ,a);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_anim_value_t lv_anim_path_bounce(lv_anim_path_t* path, lv_anim_t* a)
int luat_lv_anim_path_bounce(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_bounce");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 2);
    lv_anim_value_t ret;
    ret = lv_anim_path_bounce(path ,a);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_anim_value_t lv_anim_path_step(lv_anim_path_t* path, lv_anim_t* a)
int luat_lv_anim_path_step(lua_State *L) {
    LV_DEBUG("CALL lv_anim_path_step");
    lv_anim_path_t* path = (lv_anim_path_t*)lua_touserdata(L, 1);
    lv_anim_t* a = (lv_anim_t*)lua_touserdata(L, 2);
    lv_anim_value_t ret;
    ret = lv_anim_path_step(path ,a);
    lua_pushinteger(L, ret);
    return 1;
}

#endif
