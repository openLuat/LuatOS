#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_malloc.h"

static lv_indev_data_t point_emulator_data = {0};

bool point_input_read(lv_indev_drv_t * drv, lv_indev_data_t*data) {
    memcpy(data, drv->user_data, sizeof(lv_indev_data_t));
    return false;
}

int luat_lv_indev_drv_register(lua_State* L) {
    lv_indev_drv_t indev_drv;
    lv_indev_drv_init(&indev_drv);
    const char* type = luaL_checkstring(L, 1);
    int ok = 0;
    if (!strcmp("pointer", type)) {
        indev_drv.type = LV_INDEV_TYPE_POINTER;
        const char* dtype = luaL_checkstring(L, 2);
        if (!strcmp("emulator", dtype)) {
            indev_drv.user_data = &point_emulator_data;
            memset(indev_drv.user_data, 0, sizeof(lv_indev_data_t));
            indev_drv.read_cb = point_input_read;
            lv_indev_drv_register(&indev_drv);
            ok = 1;
        }
        else if(!strcmp("xpt2046", type)) {
            // TODO 支持xpt2046?
        }
    }
    lua_pushboolean(L, ok);
    return 1;
}

int luat_lv_indev_point_emulator_update(lua_State* L) {
    int x = luaL_checkinteger(L, 1);
    int y = luaL_checkinteger(L, 2);
    int state = luaL_optinteger(L, 3, 1);
    point_emulator_data.point.x = x;
    point_emulator_data.point.y = y;
    point_emulator_data.state = state;
    return 0;
}
