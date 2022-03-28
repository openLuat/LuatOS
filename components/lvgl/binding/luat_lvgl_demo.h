
#ifndef LUAT_LVGL_DEMO
#define LUAT_LVGL_DEMO

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_demo_benchmark(lua_State *L);
int luat_lv_demo_keypad_encoder(lua_State *L);
int luat_lv_demo_music(lua_State *L);
int luat_lv_demo_printer(lua_State *L);
int luat_lv_demo_stress(lua_State *L);
int luat_lv_demo_widgets(lua_State *L);

#define LUAT_LV_DEMO_RLT {"demo_benchmark", ROREG_FUNC(luat_lv_demo_benchmark)},\
{"demo_keypad_encoder", ROREG_FUNC(luat_lv_demo_keypad_encoder)},\
{"demo_music", ROREG_FUNC(luat_lv_demo_music)},\
{"demo_printer", ROREG_FUNC(luat_lv_demo_printer)},\
{"demo_stress", ROREG_FUNC(luat_lv_demo_stress)},\
{"demo_widgets", ROREG_FUNC(luat_lv_demo_widgets)},\

#endif
