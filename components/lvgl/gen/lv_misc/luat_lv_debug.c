
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  bool lv_debug_check_null(void* p)
int luat_lv_debug_check_null(lua_State *L) {
    LV_DEBUG("CALL %s", lv_debug_check_null);
    void* p = (void*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_debug_check_null(p);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_debug_check_mem_integrity()
int luat_lv_debug_check_mem_integrity(lua_State *L) {
    LV_DEBUG("CALL %s", lv_debug_check_mem_integrity);
    bool ret;
    ret = lv_debug_check_mem_integrity();
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_debug_check_str(void* str)
int luat_lv_debug_check_str(lua_State *L) {
    LV_DEBUG("CALL %s", lv_debug_check_str);
    void* str = (void*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_debug_check_str(str);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_debug_log_error(char* msg, uint64_t value)
int luat_lv_debug_log_error(lua_State *L) {
    LV_DEBUG("CALL %s", lv_debug_log_error);
    char* msg = (char*)luaL_checkstring(L, 1);
    uint64_t value;
    // miss arg convert
    lv_debug_log_error(msg ,value);
    return 0;
}

