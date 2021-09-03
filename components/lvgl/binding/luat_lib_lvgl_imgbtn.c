
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_zbuff.h"

//  void lv_imgbtn_set_src(lv_obj_t* imgbtn, lv_btn_state_t state, void* src)
int luat_lv_imgbtn_set_src(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_set_src");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_state_t state = (lv_btn_state_t)luaL_checkinteger(L, 2);
    void* src = NULL;
    if (lua_isstring(L, 3))
        src = (void*)luaL_checkstring(L, 3);
    else if (lua_isuserdata(L, 3)) {
        luat_zbuff_t* buff = (luat_zbuff_t *)luaL_checkudata(L, 1, "ZBUFF*");
        src = buff->addr;
    }
    else {
        LLOGD("Bad src_img for img");
        return 0;
    }
    lv_imgbtn_set_src(imgbtn ,state ,src);
    return 0;
}
