#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_malloc.h"

/*
创建一个anim
@api lvgl.anim_create()
@return userdata anim指针
@usage
local anim = lvgl.anim_create()
*/
int luat_lv_anim_create(lua_State *L) {
    lv_anim_t* anim = (lv_anim_t*)luat_heap_malloc(sizeof(lv_anim_t));
    lv_anim_init(anim);
    lua_pushlightuserdata(L, anim);
    return 1;
}

/*
释放一个anim
@api lvgl.anim_free(anim)
@return userdata anim指针
@usage
local lvgl.anim_free(anim)
*/
int luat_lv_anim_free(lua_State *L) {
    lv_anim_t* anim = (lv_anim_t*)lua_touserdata(L, 1);
    if (anim != NULL) {
        luat_heap_free(anim);
    }
    return 0;
}
