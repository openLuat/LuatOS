
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

