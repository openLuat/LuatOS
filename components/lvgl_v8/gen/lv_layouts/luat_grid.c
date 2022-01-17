
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_grid_init()
int luat_lv_grid_init(lua_State *L) {
    LV_DEBUG("CALL lv_grid_init");
    lv_grid_init();
    return 0;
}

//  lv_coord_t lv_grid_fr(uint8_t x)
int luat_lv_grid_fr(lua_State *L) {
    LV_DEBUG("CALL lv_grid_fr");
    uint8_t x = (uint8_t)luaL_checkinteger(L, 1);
    lv_coord_t ret;
    ret = lv_grid_fr(x);
    lua_pushinteger(L, ret);
    return 1;
}

