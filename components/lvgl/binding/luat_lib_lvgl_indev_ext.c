/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/
#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_malloc.h"

static lv_indev_data_t point_emulator_data = {0};
static lv_indev_data_t keyboard_emulator_data = {0};

static bool point_input_read(lv_indev_drv_t * drv, lv_indev_data_t*data) {
    memcpy(data, drv->user_data, sizeof(lv_indev_data_t));
    // if (((lv_indev_data_t*)drv->user_data)->state == LV_INDEV_STATE_PR){
    //     ((lv_indev_data_t*)drv->user_data)->state == LV_INDEV_STATE_REL;
    // }
    return false;
}

/*
注册输入设备驱动
@api lvgl.indev_drv_register(tp, dtp)
@string 设备类型，当前支持"pointer",指针类/触摸类均可，"keyboard",键盘类型
@string 设备型号，当前支持"emulator",模拟器类型
@return bool 成功返回true,否则返回false
@usage
lvgl.indev_drv_register("pointer", "emulator")
*/
int luat_lv_indev_drv_register(lua_State* L) {
    lv_indev_drv_t indev_drv;
    lv_indev_drv_init(&indev_drv);
    const char* type = luaL_checkstring(L, 1);
    int ok = 0;
    const char* dtype;
    if (!strcmp("pointer", type)) {
        indev_drv.type = LV_INDEV_TYPE_POINTER;
        dtype = luaL_checkstring(L, 2);
        if (!strcmp("emulator", dtype)) {
            indev_drv.user_data = &point_emulator_data;
            memset(indev_drv.user_data, 0, sizeof(lv_indev_data_t));
            indev_drv.read_cb = point_input_read;
            lv_indev_drv_register(&indev_drv);
            ok = 1;
        }
        //else if(!strcmp("xpt2046", type)) {
        //    // TODO 支持xpt2046?
        //}
    }
    else if (!strcmp("keyboard", type)) {
        indev_drv.type = LV_INDEV_TYPE_KEYPAD;
        //dtype = luaL_checkstring(L, 2);
        //if (!strcmp("emulator", dtype)) {
        {
            indev_drv.user_data = &keyboard_emulator_data;
            memset(indev_drv.user_data, 0, sizeof(lv_indev_data_t));
            indev_drv.read_cb = point_input_read;
            lv_indev_drv_register(&indev_drv);
            ok = 1;
        }
    }
    lua_pushboolean(L, ok);
    return 1;
}

/*
更新模拟输入设备的坐标数据
@api lvgl.indev_point_emulator_update(x, y, state)
@int x坐标,以左上角为0,右下角为最大值
@int y坐标,以左上角为0,右下角为最大值
@int 状态, 0 为 释放, 1 为按下
@return nil 无返回值
@usage
-- 模拟在屏幕上的点击,通过timeout模拟长按和短按
sys.taskInit(function(x, y, timeout)
    lvgl.indev_point_emulator_update(x, y, 1)
    sys.wait(timeout)
    lvgl.indev_point_emulator_update(x, y, 0)
end, 240, 120, 50)
*/
int luat_lv_indev_point_emulator_update(lua_State* L) {
    int x = luaL_checkinteger(L, 1);
    int y = luaL_checkinteger(L, 2);
    int state = luaL_optinteger(L, 3, 1);
    point_emulator_data.point.x = x;
    point_emulator_data.point.y = y;
    point_emulator_data.state = state;
    return 0;
}


/*
更新键盘输入设备的按键值
@api lvgl.indev_kb_update(key)
@int 按键值，默认为0，按键抬起
@return nil 无返回值
@usage
*/
int luat_lv_indev_keyboard_update(lua_State* L) {
    int key = luaL_optinteger(L, 1, 0);
    keyboard_emulator_data.key = key;
    return 0;
}
