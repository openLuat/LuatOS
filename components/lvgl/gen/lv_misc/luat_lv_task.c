
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  uint32_t lv_task_handler()
int luat_lv_task_handler(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_handler);
    uint32_t ret;
    ret = lv_task_handler();
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_task_t* lv_task_create_basic()
int luat_lv_task_create_basic(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_create_basic);
    lv_task_t* ret = NULL;
    ret = lv_task_create_basic();
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_task_t* lv_task_create(lv_task_cb_t task_xcb, uint32_t period, lv_task_prio_t prio, void* user_data)
int luat_lv_task_create(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_create);
    lv_task_cb_t task_xcb;
    // miss arg convert
    uint32_t period = (uint32_t)luaL_checkinteger(L, 2);
    lv_task_prio_t prio;
    // miss arg convert
    void* user_data = (void*)lua_touserdata(L, 4);
    lv_task_t* ret = NULL;
    ret = lv_task_create(task_xcb ,period ,prio ,user_data);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_task_del(lv_task_t* task)
int luat_lv_task_del(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_del);
    lv_task_t* task = (lv_task_t*)lua_touserdata(L, 1);
    lv_task_del(task);
    return 0;
}

//  void lv_task_set_prio(lv_task_t* task, lv_task_prio_t prio)
int luat_lv_task_set_prio(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_set_prio);
    lv_task_t* task = (lv_task_t*)lua_touserdata(L, 1);
    lv_task_prio_t prio;
    // miss arg convert
    lv_task_set_prio(task ,prio);
    return 0;
}

//  void lv_task_set_period(lv_task_t* task, uint32_t period)
int luat_lv_task_set_period(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_set_period);
    lv_task_t* task = (lv_task_t*)lua_touserdata(L, 1);
    uint32_t period = (uint32_t)luaL_checkinteger(L, 2);
    lv_task_set_period(task ,period);
    return 0;
}

//  void lv_task_ready(lv_task_t* task)
int luat_lv_task_ready(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_ready);
    lv_task_t* task = (lv_task_t*)lua_touserdata(L, 1);
    lv_task_ready(task);
    return 0;
}

//  void lv_task_set_repeat_count(lv_task_t* task, int32_t repeat_count)
int luat_lv_task_set_repeat_count(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_set_repeat_count);
    lv_task_t* task = (lv_task_t*)lua_touserdata(L, 1);
    int32_t repeat_count = (int32_t)luaL_checkinteger(L, 2);
    lv_task_set_repeat_count(task ,repeat_count);
    return 0;
}

//  void lv_task_reset(lv_task_t* task)
int luat_lv_task_reset(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_reset);
    lv_task_t* task = (lv_task_t*)lua_touserdata(L, 1);
    lv_task_reset(task);
    return 0;
}

//  void lv_task_enable(bool en)
int luat_lv_task_enable(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_enable);
    bool en = (bool)lua_toboolean(L, 1);
    lv_task_enable(en);
    return 0;
}

//  uint8_t lv_task_get_idle()
int luat_lv_task_get_idle(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_get_idle);
    uint8_t ret;
    ret = lv_task_get_idle();
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_task_t* lv_task_get_next(lv_task_t* task)
int luat_lv_task_get_next(lua_State *L) {
    LV_DEBUG("CALL %s", lv_task_get_next);
    lv_task_t* task = (lv_task_t*)lua_touserdata(L, 1);
    lv_task_t* ret = NULL;
    ret = lv_task_get_next(task);
    lua_pushlightuserdata(L, ret);
    return 1;
}

