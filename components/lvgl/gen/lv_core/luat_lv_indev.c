
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_indev_drv_init(lv_indev_drv_t* driver)
int luat_lv_indev_drv_init(lua_State *L) {
    LV_DEBUG("CALL lv_indev_drv_init");
    lv_indev_drv_t* driver = (lv_indev_drv_t*)lua_touserdata(L, 1);
    lv_indev_drv_init(driver);
    return 0;
}

//  lv_indev_t* lv_indev_drv_register(lv_indev_drv_t* driver)
int luat_lv_indev_drv_register(lua_State *L) {
    LV_DEBUG("CALL lv_indev_drv_register");
    lv_indev_drv_t* driver = (lv_indev_drv_t*)lua_touserdata(L, 1);
    lv_indev_t* ret = NULL;
    ret = lv_indev_drv_register(driver);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_indev_drv_update(lv_indev_t* indev, lv_indev_drv_t* new_drv)
int luat_lv_indev_drv_update(lua_State *L) {
    LV_DEBUG("CALL lv_indev_drv_update");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_indev_drv_t* new_drv = (lv_indev_drv_t*)lua_touserdata(L, 2);
    lv_indev_drv_update(indev ,new_drv);
    return 0;
}

//  lv_indev_t* lv_indev_get_next(lv_indev_t* indev)
int luat_lv_indev_get_next(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_next");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_indev_t* ret = NULL;
    ret = lv_indev_get_next(indev);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_indev_t* lv_indev_get_act()
int luat_lv_indev_get_act(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_act");
    lv_indev_t* ret = NULL;
    ret = lv_indev_get_act();
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_indev_type_t lv_indev_get_type(lv_indev_t* indev)
int luat_lv_indev_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_type");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_indev_type_t ret;
    ret = lv_indev_get_type(indev);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_indev_reset(lv_indev_t* indev, lv_obj_t* obj)
int luat_lv_indev_reset(lua_State *L) {
    LV_DEBUG("CALL lv_indev_reset");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 2);
    lv_indev_reset(indev ,obj);
    return 0;
}

//  void lv_indev_reset_long_press(lv_indev_t* indev)
int luat_lv_indev_reset_long_press(lua_State *L) {
    LV_DEBUG("CALL lv_indev_reset_long_press");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_indev_reset_long_press(indev);
    return 0;
}

//  void lv_indev_enable(lv_indev_t* indev, bool en)
int luat_lv_indev_enable(lua_State *L) {
    LV_DEBUG("CALL lv_indev_enable");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_indev_enable(indev ,en);
    return 0;
}

//  void lv_indev_set_cursor(lv_indev_t* indev, lv_obj_t* cur_obj)
int luat_lv_indev_set_cursor(lua_State *L) {
    LV_DEBUG("CALL lv_indev_set_cursor");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_obj_t* cur_obj = (lv_obj_t*)lua_touserdata(L, 2);
    lv_indev_set_cursor(indev ,cur_obj);
    return 0;
}

//  void lv_indev_set_group(lv_indev_t* indev, lv_group_t* group)
int luat_lv_indev_set_group(lua_State *L) {
    LV_DEBUG("CALL lv_indev_set_group");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 2);
    lv_indev_set_group(indev ,group);
    return 0;
}

//  void lv_indev_get_point(lv_indev_t* indev, lv_point_t* point)
int luat_lv_indev_get_point(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_point");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lua_pushvalue(L, 2);
    lv_point_t point = {0};
    lua_geti(L, -1, 1); point.x = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); point.y = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_indev_get_point(indev ,&point);
    return 0;
}

//  lv_gesture_dir_t lv_indev_get_gesture_dir(lv_indev_t* indev)
int luat_lv_indev_get_gesture_dir(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_gesture_dir");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_gesture_dir_t ret;
    ret = lv_indev_get_gesture_dir(indev);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint32_t lv_indev_get_key(lv_indev_t* indev)
int luat_lv_indev_get_key(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_key");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_indev_get_key(indev);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_indev_is_dragging(lv_indev_t* indev)
int luat_lv_indev_is_dragging(lua_State *L) {
    LV_DEBUG("CALL lv_indev_is_dragging");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_indev_is_dragging(indev);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_indev_get_vect(lv_indev_t* indev, lv_point_t* point)
int luat_lv_indev_get_vect(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_vect");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lua_pushvalue(L, 2);
    lv_point_t point = {0};
    lua_geti(L, -1, 1); point.x = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); point.y = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_indev_get_vect(indev ,&point);
    return 0;
}

//  lv_res_t lv_indev_finish_drag(lv_indev_t* indev)
int luat_lv_indev_finish_drag(lua_State *L) {
    LV_DEBUG("CALL lv_indev_finish_drag");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_res_t ret;
    ret = lv_indev_finish_drag(indev);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_indev_wait_release(lv_indev_t* indev)
int luat_lv_indev_wait_release(lua_State *L) {
    LV_DEBUG("CALL lv_indev_wait_release");
    lv_indev_t* indev = (lv_indev_t*)lua_touserdata(L, 1);
    lv_indev_wait_release(indev);
    return 0;
}

//  lv_obj_t* lv_indev_get_obj_act()
int luat_lv_indev_get_obj_act(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_obj_act");
    lv_obj_t* ret = NULL;
    ret = lv_indev_get_obj_act();
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_obj_t* lv_indev_search_obj(lv_obj_t* obj, lv_point_t* point)
int luat_lv_indev_search_obj(lua_State *L) {
    LV_DEBUG("CALL lv_indev_search_obj");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lua_pushvalue(L, 2);
    lv_point_t point = {0};
    lua_geti(L, -1, 1); point.x = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); point.y = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_obj_t* ret = NULL;
    ret = lv_indev_search_obj(obj ,&point);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_task_t* lv_indev_get_read_task(lv_disp_t* indev)
int luat_lv_indev_get_read_task(lua_State *L) {
    LV_DEBUG("CALL lv_indev_get_read_task");
    lv_disp_t* indev = (lv_disp_t*)lua_touserdata(L, 1);
    lv_task_t* ret = NULL;
    ret = lv_indev_get_read_task(indev);
    lua_pushlightuserdata(L, ret);
    return 1;
}

