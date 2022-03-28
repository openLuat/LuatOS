/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "../lv_demos/lv_examples.h"
#include "luat_malloc.h"

/*
lvgl benchmark demo
@api lvgl.demo_benchmark()
@return nil 无返回值
@usage
lvgl.init()
lvgl.demo_benchmark()
*/
int luat_lv_demo_benchmark(lua_State *L){
#if LV_USE_DEMO_BENCHMARK
    lv_demo_benchmark();
#else
    LLOGW("please defined LV_USE_DEMO_BENCHMARK");
#endif
    return 0;
}

/*
lvgl keypad_encoder demo
@api lvgl.demo_keypad_encoder()
@return nil 无返回值
@usage
lvgl.init()
lvgl.demo_keypad_encoder()
*/
int luat_lv_demo_keypad_encoder(lua_State *L){
#if LV_USE_DEMO_KEYPAD_AND_ENCODER
    lv_demo_keypad_encoder();
#else
    LLOGW("please defined LV_USE_DEMO_KEYPAD_AND_ENCODER");
#endif
    return 0;
}

/*
lvgl music demo
@api lvgl.demo_music()
@return nil 无返回值
@usage
lvgl.init()
lvgl.demo_music()
*/
int luat_lv_demo_music(lua_State *L){
#if LV_USE_DEMO_MUSIC
    lv_demo_music();
#else
    LLOGW("please defined LV_USE_DEMO_MUSIC");
#endif
    return 0;
}

/*
lvgl printer demo
@api lvgl.demo_printer()
@return nil 无返回值
@usage
lvgl.init()
lvgl.demo_printer()
*/
int luat_lv_demo_printer(lua_State *L){
#if LV_USE_DEMO_PRINTER
    lv_demo_printer();
#else
    LLOGW("please defined LV_USE_DEMO_PRINTER");
#endif
    return 0;
}

/*
lvgl stress demo
@api lvgl.demo_stress()
@return nil 无返回值
@usage
lvgl.init()
lvgl.demo_stress()
*/
int luat_lv_demo_stress(lua_State *L){
#if LV_USE_DEMO_STRESS
    lv_demo_stress();
#else
    LLOGW("please defined LV_USE_DEMO_STRESS");
#endif
    return 0;
}

/*
lvgl widgets demo
@api lvgl.demo_widgets()
@return nil 无返回值
@usage
lvgl.init()
lvgl.demo_widgets()
*/
int luat_lv_demo_widgets(lua_State *L){
#if LV_USE_DEMO_WIDGETS
    lv_demo_widgets();
#else
    LLOGW("please defined LV_USE_DEMO_WIDGETS");
#endif
    return 0;
}
