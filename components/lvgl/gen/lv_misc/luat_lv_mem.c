
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void* lv_mem_alloc(size_t size)
int luat_lv_mem_alloc(lua_State *L) {
    LV_DEBUG("CALL lv_mem_alloc");
    size_t size = (size_t)luaL_checkinteger(L, 1);
    void* ret = NULL;
    ret = lv_mem_alloc(size);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_mem_free(void* data)
int luat_lv_mem_free(lua_State *L) {
    LV_DEBUG("CALL lv_mem_free");
    void* data = (void*)lua_touserdata(L, 1);
    lv_mem_free(data);
    return 0;
}

//  void* lv_mem_realloc(void* data_p, size_t new_size)
int luat_lv_mem_realloc(lua_State *L) {
    LV_DEBUG("CALL lv_mem_realloc");
    void* data_p = (void*)lua_touserdata(L, 1);
    size_t new_size = (size_t)luaL_checkinteger(L, 2);
    void* ret = NULL;
    ret = lv_mem_realloc(data_p ,new_size);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_mem_defrag()
int luat_lv_mem_defrag(lua_State *L) {
    LV_DEBUG("CALL lv_mem_defrag");
    lv_mem_defrag();
    return 0;
}

//  lv_res_t lv_mem_test()
int luat_lv_mem_test(lua_State *L) {
    LV_DEBUG("CALL lv_mem_test");
    lv_res_t ret;
    ret = lv_mem_test();
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_mem_monitor(lv_mem_monitor_t* mon_p)
int luat_lv_mem_monitor(lua_State *L) {
    LV_DEBUG("CALL lv_mem_monitor");
    lv_mem_monitor_t* mon_p = (lv_mem_monitor_t*)lua_touserdata(L, 1);
    lv_mem_monitor(mon_p);
    return 0;
}

