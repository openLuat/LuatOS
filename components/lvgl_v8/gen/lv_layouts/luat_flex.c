
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_flex_init()
int luat_lv_flex_init(lua_State *L) {
    LV_DEBUG("CALL lv_flex_init");
    lv_flex_init();
    return 0;
}

