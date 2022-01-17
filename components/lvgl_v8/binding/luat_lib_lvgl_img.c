#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_zbuff.h"

//  void lv_img_set_src(lv_obj_t* img, void* src_img)
int luat_lv_img_set_src(lua_State *L) {
    LV_DEBUG("CALL lv_img_set_src");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    void* src_img = NULL;
    if (lua_isstring(L, 2))
        src_img = (void*)luaL_checkstring(L, 2);
    else if (lua_isuserdata(L, 2)) {
        luat_zbuff_t* buff = (luat_zbuff_t *)luaL_checkudata(L, 1, "ZBUFF*");
        src_img = buff->addr;
    }
    else {
        LLOGD("Bad src_img for img");
        return 0;
    }
    lv_img_set_src(img ,src_img);
    return 0;
}
