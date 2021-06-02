
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_img_cache_set_size(uint16_t new_slot_num)
int luat_lv_img_cache_set_size(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_cache_set_size);
    uint16_t new_slot_num = (uint16_t)luaL_checkinteger(L, 1);
    lv_img_cache_set_size(new_slot_num);
    return 0;
}

//  void lv_img_cache_invalidate_src(void* src)
int luat_lv_img_cache_invalidate_src(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_cache_invalidate_src);
    void* src = (void*)lua_touserdata(L, 1);
    lv_img_cache_invalidate_src(src);
    return 0;
}

