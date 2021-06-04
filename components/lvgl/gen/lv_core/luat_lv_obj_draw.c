
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_obj_draw_dsc_init(lv_obj_draw_part_dsc_t* dsc, lv_area_t* clip_area)
int luat_lv_obj_draw_dsc_init(lua_State *L) {
    LV_DEBUG("CALL lv_obj_draw_dsc_init");
    lv_obj_draw_part_dsc_t* dsc = (lv_obj_draw_part_dsc_t*)lua_touserdata(L, 1);
    lua_pushvalue(L, 2);
    lv_area_t clip_area = {0};
    lua_geti(L, -1, 1); clip_area.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 2); clip_area.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 3); clip_area.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_geti(L, -1, 4); clip_area.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_pop(L, 1);

    lv_obj_draw_dsc_init(dsc ,&clip_area);
    return 0;
}

