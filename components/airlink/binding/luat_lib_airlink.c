/*
@module  airlink
@summary AirLink(设备间通讯协议)
@catalog 外设API
@version 1.0
@date    2025.05.30
@demo airlink
@tag LUAT_USE_AIRLINK
@usage
-- 本库仅部分BSP支持, 通信形式以设备内SPI/设备间UART/设备间UART通信为主要载体
-- 主要是 Air8000 和 Air780E 系列
-- 详细用法请参考demo
*/

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
#include "luat_airlink_fota.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_spi_task_mode;
extern uint32_t g_airlink_pause;

/*
初始化AirLink
@api airlink.init()
@return nil 无返回值
@usage
-- 对于Air8000, 本函数已自动执行, 无需手动调用
-- 对于Air780EPM+Air8101的组合, 需要执行一次
airlink.init()
*/
static int l_airlink_init(lua_State *L) {
    LLOGD("初始化AirLink");
    luat_airlink_init();
    return 0;
}

/*
启动AirLink
@api airlink.start(mode)
@int mode 0: SPI从机模式 1: SPI主机模式 2: UART模式
@return nil 无返回值
@usage
-- 对于Air8000, 本函数已自动执行, 无需手动调用
-- 对于Air780EPM+Air8101的组合, 需要执行一次
-- Air780EPM作为SPI主机
airlink.start(airlink.MODE_SPI_MASTER)
-- Air8101作为SPI从机
airlink.start(airlink.MODE_SPI_SLAVE)
*/
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

/*
关闭AirLink
@api airlink.stop(mode)
@int mode 0: SPI从机模式 1: SPI主机模式 2: UART模式
@return nil 无返回值
@usage
-- 本函数当前无任何功能, 只做预留
*/
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

/*
发送测试指令(nop空指令)
@api airlink.test(count)
@int count 发送次数
@return nil 无返回值
@usage
-- 本函数仅供内部测试使用
airlink.test(10)
*/
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

/*
打印统计信息
@api airlink.statistics()
@return nil 无返回值
@usage
-- 调试用途, 可周期性调用
airlink.statistics()
*/
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

/*
重启从机
@api airlink.slave_reboot()
@return nil 无返回值
@usage
-- 调试用途, 可重启从机
airlink.slave_reboot()
*/
static int l_airlink_slave_reboot(lua_State *L) {
    LLOGD("重启从机");
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + 4);
    cmd->cmd = 0x03;
    cmd->len = 4;
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    return 0;
}

/*
发送自定义数据
@api airlink.sdata(data)
@string/zbuff 待传输的自定义数据,可以是字符串, 可以是zbuff
@return nil 无返回值
@usage
-- 本函数用于传递自定义数据到对端设备, 通常用于Air8101+Air780EPM的场景
airlink.sdata("hello world")
*/
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

/*
判断是否就绪
@api airlink.ready()
@return bool 是否就绪
@usage
-- 判断AirLink是否就绪, 指底层通信是否通畅, 最近一次通信是否超时(默认2s)
-- 本函数仅用于判断AirLink是否就绪, 不能用于判断是否收到数据
if airlink.ready() then
    log.info("airlink", "已经就绪")
else
    log.info("airlink", "尚未就绪")
end
*/
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

/*
升级从机固件
@api airlink.sfota(path)
@string 升级文件的路径
@return bool 成功返回true, 失败返回nil
@usage
-- 注意, 升级过程是异步的, 耗时1~2分钟, 注意观察日志
airlink.sfota("/luadb/air8000s_v5.bin")
-- 注意, 升级过程中, 其他任何指令和数据都不再传输和执行!!!
*/
static int l_airlink_sfota(lua_State *L) {
    // 直接发指令是不行了, 需要干预airlink task的执行流程
    // bk72xx的flash擦除很慢, 导致spi master需要等很久才能发下一个包
    const char* path = luaL_checkstring(L, 1);
    luat_airlink_fota_t ctx = {0};
    memcpy(ctx.path, path, strlen(path) + 1);
    int ret = luat_airlink_fota_init(&ctx);
    if (ret) {
        LLOGE("sfota 启动失败!!! %s %d", path, ret);
    }
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
调试开关
@api airlink.debug(mode)
@int mode 0: 关闭调试 1: 打开调试
@return nil 无返回值
@usage
-- 打开调试(默认是关闭状态)
airlink.debug(1)
*/
static int l_airlink_debug(lua_State *L) {
    g_airlink_debug = luaL_checkinteger(L, 1);
    return 0;
}

/*
暂停或回复airlink通信
@api airlink.pause(mode)
@int mode 0: 恢复 1: 暂停
@return nil 无返回值
@usage
-- 仅当airlink运行在轮询模式, 需要暂停时使用, 通常是为了休眠
airlink.pause(1)
*/
static int l_airlink_pause(lua_State *L) {
    g_airlink_pause = luaL_checkinteger(L, 1);
    return 0;
}

/*
开启中断模式
@api airlink.irqmode(mode, master_gpio, slave_gpio)
@int mode false: 禁用 true: 启用
@int master_gpio 主机引脚, 建议使用GPIO20
@int slave_gpio 从机引脚, Air8000使用GPIO140, Air8101使用GPIO28
@return nil 无返回值
@usage
-- 默认情况下, airlink工作在轮询模式, 周期性查询数据
-- 开启中断模式后, 从机有新数据时, 会在slave_gpio上产生一个下升沿+上升沿中断
airlink.irqmode(true, 20, 140)
-- 注意, 开启本模式, 外部接线必须稳固, 否则各种airlink相关操作都会异常
*/
static int l_airlink_irqmode(lua_State *L) {
    luat_airlink_irq_ctx_t ctx = {0};
    ctx.enable = lua_toboolean(L, 1);
    if (ctx.enable) {
        ctx.master_pin = luaL_checkinteger(L, 2);
        ctx.slave_pin = luaL_checkinteger(L, 3);
    }
    luat_airlink_irqmode(&ctx);
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
    { "pause",         ROREG_FUNC(l_airlink_pause)},
    { "irqmode",       ROREG_FUNC(l_airlink_irqmode)},

    // 测试用的fota指令
    { "sfota",         ROREG_FUNC(l_airlink_sfota )},
    { "sfota_init",    ROREG_FUNC(l_airlink_sfota_init )},
    { "sfota_done",    ROREG_FUNC(l_airlink_sfota_done )},
    { "sfota_end",     ROREG_FUNC(l_airlink_sfota_end )},
    { "sfota_write",   ROREG_FUNC(l_airlink_sfota_write )},

    { "debug",         ROREG_FUNC(l_airlink_debug )},

    { "MODE_SPI_SLAVE",    ROREG_INT(0) },
    { "MODE_SPI_MASTER",   ROREG_INT(1) },
    { "MODE_UART",         ROREG_INT(2) },

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