
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

extern airlink_statistic_t g_airlink_statistic;

static int l_airlink_init(lua_State *L) {
    LLOGD("初始化AirLink");
    luat_airlink_init();
    return 0;
}

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

static int l_airlink_test(lua_State *L) {
    int count = luaL_checkinteger(L, 1);
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + 128);
    cmd->cmd = 0x21;
    cmd->len = 128;
    if (count > 0) {
        // 发送次数
        LLOGD("测试AirLink发送%d次", count);
        for (size_t i = 0; i < count; i++)
        {
            luat_airlink_send2slave(cmd);
        }
        
    }
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    return 0;
}

static void print_stat(const char* tag, airlink_statistic_part_t* part) {
    LLOGD("统计信息 %s %lld %lld %lld %lld", tag, part->total, part->ok, part->err, part->drop);
}

static int l_airlink_statistics(lua_State *L) {
    airlink_statistic_t tmp;
    memcpy(&tmp, &g_airlink_statistic, sizeof(airlink_statistic_t));
    print_stat("发送总包", &tmp.tx_pkg);
    // print_stat("接收总包", &tmp.rx_pkg);
    // print_stat("发送IP", &tmp.tx_ip);
    // print_stat("接收IP", &tmp.rx_ip);
    print_stat("等待从机", &tmp.wait_rdy);
    print_stat("Task超时事件", &tmp.event_timeout);
    print_stat("Task新数据事件", &tmp.event_new_data);
    print_stat("Task从机通知事件", &tmp.event_rdy_irq);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_airlink[] =
{
    { "init" ,         ROREG_FUNC(l_airlink_init )},
    { "start" ,        ROREG_FUNC(l_airlink_start )},
    { "stop" ,         ROREG_FUNC(l_airlink_stop )},
    { "test",          ROREG_FUNC(l_airlink_test )},
    { "statistics",    ROREG_FUNC(l_airlink_statistics )},
	{ NULL,            ROREG_INT(0) }
};

LUAMOD_API int luaopen_airlink( lua_State *L ) {
    luat_newlib2(L, reg_airlink);
    return 1;
}