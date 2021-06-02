
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_res_t lv_async_call(lv_async_cb_t async_xcb, void* user_data)
int luat_lv_async_call(lua_State *L) {
    LV_DEBUG("CALL %s", lv_async_call);
    lv_async_cb_t async_xcb;
    // miss arg convert
    void* user_data = (void*)lua_touserdata(L, 2);
    lv_res_t ret;
    ret = lv_async_call(async_xcb ,user_data);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

