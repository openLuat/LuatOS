
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_refr_now(lv_disp_t* disp)
int luat_lv_refr_now(lua_State *L) {
    LV_DEBUG("CALL lv_refr_now");
    lv_disp_t* disp = (lv_disp_t*)lua_touserdata(L, 1);
    lv_refr_now(disp);
    return 0;
}

//  uint32_t lv_refr_get_fps_avg()
int luat_lv_refr_get_fps_avg(lua_State *L) {
    LV_DEBUG("CALL lv_refr_get_fps_avg");
    uint32_t ret;
    ret = lv_refr_get_fps_avg();
    lua_pushinteger(L, ret);
    return 1;
}

