/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "../lv_demos/lv_ex_conf.h"
#include "luat_malloc.h"

int luat_lv_demo_benchmark(lua_State *L){
#if LV_USE_DEMO_BENCHMARK
    lv_demo_benchmark();
#else
    LLOGW("please defined LV_USE_DEMO_BENCHMARK");
#endif
    return 0;
}

int luat_lv_demo_keypad_encoder(lua_State *L){
#if LV_USE_DEMO_KEYPAD_AND_ENCODER
    lv_demo_keypad_encoder();
#else
    LLOGW("please defined LV_USE_DEMO_KEYPAD_AND_ENCODER");
#endif
    return 0;
}

int luat_lv_demo_music(lua_State *L){
#if LV_USE_DEMO_MUSIC
    lv_demo_music();
#else
    LLOGW("please defined LV_USE_DEMO_MUSIC");
#endif
    return 0;
}

int luat_lv_demo_printer(lua_State *L){
#if LV_USE_DEMO_PRINTER
    lv_demo_printer();
#else
    LLOGW("please defined LV_USE_DEMO_PRINTER");
#endif
    return 0;
}

int luat_lv_demo_stress(lua_State *L){
#if LV_USE_DEMO_STRESS
    lv_demo_stress();
#else
    LLOGW("please defined LV_USE_DEMO_STRESS");
#endif
    return 0;
}

int luat_lv_demo_widgets(lua_State *L){
#if LV_USE_DEMO_WIDGETS
    lv_demo_widgets();
#else
    LLOGW("please defined LV_USE_DEMO_WIDGETS");
#endif
    return 0;
}
