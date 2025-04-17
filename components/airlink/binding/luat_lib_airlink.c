
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
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_spi_task_mode;

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

static void print_stat(const char* tag, airlink_statistic_part_t* part, int is_full) {
    if (is_full) {
        LLOGD("统计信息 %s %lld %lld %lld %lld", tag, part->total, part->ok, part->err, part->drop);
    }
    else {
        LLOGD("统计信息 %s %lld", tag, part->total);
    }
}

static int l_airlink_statistics(lua_State *L) {
    airlink_statistic_t tmp;
    memcpy(&tmp, &g_airlink_statistic, sizeof(airlink_statistic_t));
    print_stat("收发总包", &tmp.tx_pkg, 1);
    
    print_stat("发送IP包",   &tmp.tx_ip, 1);
    print_stat("发送IP字节", &tmp.tx_bytes, 1);
    print_stat("接收IP包",   &tmp.rx_ip, 1);
    print_stat("接收IP字节", &tmp.rx_bytes, 1);
    if (g_airlink_spi_task_mode == 0) {

    }
    else {
        print_stat("等待从机", &tmp.wait_rdy, 0);
        print_stat("Task超时事件", &tmp.event_timeout, 0);
        print_stat("Task新数据事件", &tmp.event_new_data, 0);
        // print_stat("Task从机通知事件", &tmp.event_rdy_irq, 0);
    }
    return 0;
}

static int l_airlink_slave_reboot(lua_State *L) {
    LLOGD("重启从机");
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + 4);
    cmd->cmd = 0x03;
    cmd->len = 4;
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    return 0;
}

static int l_airlink_sdata(lua_State *L) {
    size_t len = 0;
    const char* data = NULL;
    if (lua_type(L, 1) == LUA_TSTRING) {
        data = luaL_checklstring(L, 1, &len);
    }
    else if (lua_isuserdata(L, 1)) {
        // zbuff
        luat_zbuff_t* buff = tozbuff(L);
        data = (const char*)buff->addr;
        len = buff->used;
    }
    else {
        LLOGE("无效的参数,只能是字符串或者zbuff");
        return 0;
    }
    if (len > 1500) {
        LLOGE("无效的数据长度,最大1500字节");
        return 0;
    }
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + len);
    cmd->cmd = 0x20;
    cmd->len = len;
    memcpy(cmd->data, data, len);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_airlink_ready(lua_State *L) {
    lua_pushboolean(L, luat_airlink_ready());
    return 1;
}

static int l_airlink_cmd(lua_State *L) {
    size_t len = 0;
    const char* data = NULL;
    uint32_t cmd_id = luaL_checkinteger(L, 1);
    if (lua_type(L, 2) == LUA_TSTRING) {
        data = luaL_checklstring(L, 1, &len);
    }
    else if (lua_isuserdata(L, 1)) {
        // zbuff
        luat_zbuff_t* buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        data = (const char*)buff->addr;
        len = buff->used;
    }
    else {
        LLOGE("无效的参数,只能是字符串或者zbuff");
        return 0;
    }
    if (len > 1500) {
        LLOGE("无效的数据长度,最大1500字节");
        return 0;
    }
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + len);
    cmd->cmd = cmd_id;
    cmd->len = len;
    memcpy(cmd->data, data, len);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    lua_pushboolean(L, 1);
    return 1;
}

static int sample_cmd_nodata(lua_State *L, uint32_t cmd_id) {
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(cmd_id, 8);
    uint64_t pkgid = luat_airlink_get_next_cmd_id();
    memcpy(cmd->data, &pkgid, 8);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_airlink_sfota_init(lua_State *L) {
    LLOGD("执行sfota_init");
    return sample_cmd_nodata(L, 0x04);
}

static int l_airlink_sfota_done(lua_State *L) {
    LLOGD("执行sfota_done");
    return sample_cmd_nodata(L, 0x06);
}

static int l_airlink_sfota_end(lua_State *L) {
    LLOGD("执行sfota_end");
    return sample_cmd_nodata(L, 0x07);
}

static int l_airlink_sfota_write(lua_State *L) {
    LLOGD("执行sfota_write");
    size_t len = 0;
    const char* data = NULL;
    if (lua_type(L, 1) == LUA_TSTRING) {
        data = luaL_checklstring(L, 1, &len);
    }
    else if (lua_isuserdata(L, 1)) {
        // zbuff
        luat_zbuff_t* buff = ((luat_zbuff_t *)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE));
        data = (const char*)buff->addr;
        len = buff->used;
    }
    else {
        LLOGE("无效的参数,只能是字符串或者zbuff");
        return 0;
    }
    if (len > 1500) {
        LLOGE("无效的数据长度,最大1500字节");
        return 0;
    }
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + len);
    cmd->cmd = 0x05;
    cmd->len = len;
    memcpy(cmd->data, data, len);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    lua_pushboolean(L, 1);
    return 1;
}

/*
配置AirLink的参数
@api airlink.config(key, value)
@int key 配置项, 参考airlink的常数项
@int value 配置值
@return bool 成功返回true, 失败返回nil
@usage
--配置AirLink的SPI ID为1, CS引脚为10, RDY引脚为11, IRQ引脚为12
airlink.config(airlink.CONF_SPI_ID, 1)
airlink.config(airlink.CONF_SPI_CS, 10)
airlink.config(airlink.CONF_SPI_RDY, 11)
airlink.config(airlink.CONF_SPI_IRQ, 12)
*/
static int l_airlink_config(lua_State *L) {
    int key = luaL_checkinteger(L, 1);
    int value = luaL_checkinteger(L, 2);
    switch (key)
    {
    case LUAT_AIRLINK_CONF_SPI_ID:
        g_airlink_spi_conf.spi_id = value;
        break;
    case LUAT_AIRLINK_CONF_SPI_CS:
        g_airlink_spi_conf.cs_pin = value;
        break;
    case LUAT_AIRLINK_CONF_SPI_RDY:
        g_airlink_spi_conf.rdy_pin = value;
        break;
    case LUAT_AIRLINK_CONF_SPI_IRQ:
        g_airlink_spi_conf.irq_pin = value;
        break;
    
    default:
        return 0;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int l_airlink_sfota(lua_State *L) {
    // 直接发指令是不行了, 需要干预airlink task的执行流程
    // bk72xx的flash擦除很慢, 导致spi master需要等很久才能发下一个包
    return 0;
}

static int l_airlink_debug(lua_State *L) {
    g_airlink_debug = luaL_checkinteger(L, 1);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_airlink[] =
{
    { "init" ,         ROREG_FUNC(l_airlink_init )},
    { "config",        ROREG_FUNC(l_airlink_config)},
    { "start" ,        ROREG_FUNC(l_airlink_start)},
    { "stop" ,         ROREG_FUNC(l_airlink_stop )},
    { "ready",         ROREG_FUNC(l_airlink_ready)},
    { "test",          ROREG_FUNC(l_airlink_test )},
    { "sdata",         ROREG_FUNC(l_airlink_sdata)},
    { "cmd",           ROREG_FUNC(l_airlink_cmd)},
    { "statistics",    ROREG_FUNC(l_airlink_statistics )},
    { "slave_reboot",  ROREG_FUNC(l_airlink_slave_reboot )},

    // 测试用的fota指令
    { "sfota",         ROREG_FUNC(l_airlink_sfota )},

    { "debug",         ROREG_FUNC(l_airlink_debug )},

    { "MODE_SPI_SLAVE",    ROREG_INT(0) },
    { "MODE_SPI_MASTER",   ROREG_INT(1) },

    { "CONF_SPI_ID",       ROREG_INT(LUAT_AIRLINK_CONF_SPI_ID)},
    { "CONF_SPI_CS",       ROREG_INT(LUAT_AIRLINK_CONF_SPI_CS)},
    { "CONF_SPI_RDY",      ROREG_INT(LUAT_AIRLINK_CONF_SPI_RDY)},
    { "CONF_SPI_IRQ",      ROREG_INT(LUAT_AIRLINK_CONF_SPI_IRQ)},
	{ NULL,                ROREG_INT(0) }
};

LUAMOD_API int luaopen_airlink( lua_State *L ) {
    luat_newlib2(L, reg_airlink);
    return 1;
}