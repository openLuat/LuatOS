
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_rtos.h"
#include "luat_mcu.h"
#include <math.h>
#include "luat_airlink.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

static int l_airlink_start(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id == 0) {
        // 临时入口,先写死
        LLOGD("启动AirLink从机模式");
    }
    else {
        // 临时入口,先写死
        LLOGD("启动AirLink主机模式");
    }
    luat_airlink_task_start();
    luat_airlink_start(id);
    return 0;
}
static int l_airlink_stop(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id == 0) {
        // 临时入口,先写死
        LLOGD("停止AirLink从机模式");
    }
    else {
        // 临时入口,先写死
        LLOGD("停止AirLink主机模式");
    }
    luat_airlink_stop(id);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_airlink[] =
{
    { "start" ,        ROREG_FUNC(l_airlink_start )},
    { "stop" ,         ROREG_FUNC(l_airlink_stop )},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_airlink( lua_State *L ) {
    luat_newlib2(L, reg_airlink);
    return 1;
}