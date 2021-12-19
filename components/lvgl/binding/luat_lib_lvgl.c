/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"

#define LUAT_LOG_TAG "lvgl"
#include "luat_log.h"

//---------------------------------
// 几个快捷方法
//---------------------------------

/*
获取当前活跃的screen对象
@api lvgl.scr_act()
@return screen指针
@usage
local scr = lvgl.scr_act()

*/
static int luat_lv_scr_act(lua_State *L) {
    lua_pushlightuserdata(L, lv_scr_act());
    return 1;
};

/*
获取layout_top
@api lvgl.layout_top()
@return layout指针
*/
static int luat_lv_layer_top(lua_State *L) {
    lua_pushlightuserdata(L, lv_layer_top());
    return 1;
};

/*
获取layout_sys
@api lvgl.layout_sys()
@return layout指针
*/
static int luat_lv_layer_sys(lua_State *L) {
    lua_pushlightuserdata(L, lv_layer_sys());
    return 1;
};

/*
载入指定的screen
@api lvgl.scr_load(scr)
@userdata screen指针
@usage
lvgl.disp_set_bg_color(nil, 0xFFFFFF)
local scr = lvgl.obj_create(nil, nil)
local btn = lvgl.btn_create(scr)
lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
lvgl.label_set_text(label, "LuatOS!")
lvgl.scr_load(scr)
*/
static int luat_lv_scr_load(lua_State *L) {
    lv_scr_load(lua_touserdata(L, 1));
    return 0;
};

// 函数注册
static const rotable_Reg reg_lvgl[] = {

{"init", luat_lv_init, 0},
{"scr_act", luat_lv_scr_act, 0},
{"layer_top", luat_lv_layer_top, 0},
{"layer_sys", luat_lv_layer_sys, 0},
{"scr_load", luat_lv_scr_load, 0},

// 兼容性命名
{"sw_create", luat_lv_switch_create, 0},

LUAT_LV_DISP_RLT
LUAT_LV_GROUP_RLT
LUAT_LV_OBJ_RLT
LUAT_LV_REFR_RLT

LUAT_LV_STYLE_RLT
LUAT_LV_STYLE2_RLT
// 添加STYLE_DEC那一百多个函数
LUAT_LV_STYLE_DEC_RLT

LUAT_LV_DRAW_RLT
LUAT_LV_DRAW_EX_RLT
LUAT_LV_ANIM_RLT
LUAT_LV_ANIM_EX_RLT
LUAT_LV_AREA_RLT
LUAT_LV_COLOR_RLT
LUAT_LV_THEME_RLT
LUAT_LV_MAP_RLT

// 输入设备
#ifdef LUAT_USE_LVGL_INDEV
LUAT_LV_INDEV_RLT
#endif

//LVGL组件
#ifdef LUAT_USE_LVGL_ARC
LUAT_LV_ARC_RLT
#endif
#ifdef LUAT_USE_LVGL_BAR
LUAT_LV_BAR_RLT
#endif
#ifdef LUAT_USE_LVGL_BTN
LUAT_LV_BTN_RLT
#endif
#ifdef LUAT_USE_LVGL_BTNMATRIX
LUAT_LV_BTNMATRIX_RLT
LUAT_LV_BTNMATRIX_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_CALENDAR
LUAT_LV_CALENDAR_RLT
LUAT_LV_CALENDAR_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_CANVAS
LUAT_LV_CANVAS_RLT
LUAT_LV_CANVAS_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_CHECKBOX
LUAT_LV_CHECKBOX_RLT
#endif
#ifdef LUAT_USE_LVGL_CHART
LUAT_LV_CHART_RLT
#endif
#ifdef LUAT_USE_LVGL_CONT
LUAT_LV_CONT_RLT
#endif
#ifdef LUAT_USE_LVGL_CPICKER
LUAT_LV_CPICKER_RLT
#endif
#ifdef LUAT_USE_LVGL_DROPDOWN
LUAT_LV_DROPDOWN_RLT
LUAT_LV_DROPDOWN_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_GAUGE
LUAT_LV_GAUGE_RLT
LUAT_LV_GAUGE_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_IMG
LUAT_LV_IMG_RLT
LUAT_LV_IMG_EX_RTL
#endif
#ifdef LUAT_USE_LVGL_IMGBTN
LUAT_LV_IMGBTN_RLT
LUAT_LV_IMGBTN_EX_RTL
#endif
#ifdef LUAT_USE_LVGL_KEYBOARD
LUAT_LV_KEYBOARD_RLT
#endif
#ifdef LUAT_USE_LVGL_LABEL
LUAT_LV_LABEL_RLT
#endif
#ifdef LUAT_USE_LVGL_LED
LUAT_LV_LED_RLT
#endif
#ifdef LUAT_USE_LVGL_LINE
LUAT_LV_LINE_RLT
LUAT_LV_LINE_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_LIST
LUAT_LV_LIST_RLT
#endif
#ifdef LUAT_USE_LVGL_LINEMETER
LUAT_LV_LINEMETER_RLT
#endif
#ifdef LUAT_USE_LVGL_MSGBOX
LUAT_LV_MSGBOX_RLT
LUAT_LV_MSGBOX_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_OBJMASK
LUAT_LV_OBJMASK_RLT
#endif
#ifdef LUAT_USE_LVGL_PAGE
LUAT_LV_PAGE_RLT
#endif
#ifdef LUAT_USE_LVGL_SPINNER
LUAT_LV_SPINNER_RLT
#endif
#ifdef LUAT_USE_LVGL_ROLLER
LUAT_LV_ROLLER_RLT
LUAT_LV_ROLLER_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_SLIDER
LUAT_LV_SLIDER_RLT
#endif
#ifdef LUAT_USE_LVGL_SPINBOX
LUAT_LV_SPINBOX_RLT
#endif
#ifdef LUAT_USE_LVGL_SWITCH
LUAT_LV_SWITCH_RLT
#endif
#ifdef LUAT_USE_LVGL_TEXTAREA
LUAT_LV_TEXTAREA_RLT
#endif
#ifdef LUAT_USE_LVGL_TABLE
LUAT_LV_TABLE_RLT
#endif
#ifdef LUAT_USE_LVGL_TABVIEW
LUAT_LV_TABVIEW_RLT
#endif
#ifdef LUAT_USE_LVGL_TILEVIEW
LUAT_LV_TILEVIEW_RLT
LUAT_LV_TILEVIEW_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_WIN
LUAT_LV_WIN_RLT
#endif

// 图像库
LUAT_LV_QRCODE_RLT
#if defined(LUA_USE_LINUX) || defined(LUA_USE_WINDOWS) || defined(LUA_USE_MACOSX)
LUAT_LV_GIF_RLT
#endif

// 回调
LUAT_LV_CB_RLT

// 额外添加的函数
LUAT_LV_EX_RLT
// LUAT_LV_WIDGETS_EX_RLT

// 字体API
LUAT_LV_FONT_EX_RLT

// 结构体
LUAT_LV_STRUCT_RLT

// 常量
LUAT_LV_ENMU_RLT

{"ROLLER_MODE_INIFINITE", NULL, LV_ROLLER_MODE_INIFINITE},
{NULL, NULL, 0},
};

#if (LV_USE_LOG && LV_LOG_PRINTF == 0)
static void lv_log_print(lv_log_level_t level, const char * file, uint32_t lineno, const char * func, const char * desc) {
    switch (level)
    {
    case LV_LOG_LEVEL_TRACE:
        LLOGD("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    case LV_LOG_LEVEL_INFO:
        LLOGI("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    case LV_LOG_LEVEL_WARN:
        LLOGW("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    case LV_LOG_LEVEL_ERROR:
        LLOGE("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    default:
        LLOGD("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    }
};
#endif

LUAMOD_API int luaopen_lvgl( lua_State *L ) {
    #if (LV_USE_LOG && LV_LOG_PRINTF == 0)
    lv_log_register_print_cb(lv_log_print);
    #endif
    luat_newlib(L, reg_lvgl);
    luat_lvgl_struct_init(L);
    return 1;
}

static int lv_func_unref(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (msg->arg1)
        luaL_unref(L, LUA_REGISTRYINDEX, msg->arg1);
    if (msg->arg2)
        luaL_unref(L, LUA_REGISTRYINDEX, msg->arg2);
    return 0;
}

void luat_lv_user_data_free(lv_obj_t * obj) {
    if (obj == NULL || (obj->user_data.event_cb_ref == 0 && obj->user_data.signal_cb_ref)) return;
    rtos_msg_t msg = {0};
    msg.handler = lv_func_unref;
    msg.arg1 = obj->user_data.event_cb_ref;
    msg.arg2 = obj->user_data.signal_cb_ref;
    luat_msgbus_put(&msg, 0);
}
