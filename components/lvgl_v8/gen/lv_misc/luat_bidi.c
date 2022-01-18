
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_bidi_calculate_align(lv_text_align_t* align, lv_base_dir_t* base_dir, char* txt)
int luat_lv_bidi_calculate_align(lua_State *L) {
    LV_DEBUG("CALL lv_bidi_calculate_align");
    lv_text_align_t* align = (lv_text_align_t*)lua_touserdata(L, 1);
    lv_base_dir_t* base_dir = (lv_base_dir_t*)lua_touserdata(L, 2);
    char* txt = (char*)luaL_checkstring(L, 3);
    lv_bidi_calculate_align(align ,base_dir ,txt);
    return 0;
}

