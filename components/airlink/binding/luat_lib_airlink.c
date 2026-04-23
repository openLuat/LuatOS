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
#include "luat_airlink.h"
#include "luat_airlink_fota.h"
#include "luat_zbuff.h"
#include "luat_hmeta.h"

#include <math.h>

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_pause;
extern luat_airlink_irq_ctx_t g_airlink_wakeup_irq_ctx;

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
        else if(id == 1)
    {
        LLOGD("启动AirLink主机模式");
    }
    else if(id == 2)
    {
        LLOGD("启动AirLink UART模式");
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
    // int id = luaL_checkinteger(L, 1);
    // luat_airlink_stop(id);
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
    if (cmd == NULL) return 0;
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
    if (luat_airlink_current_mode_get() == LUAT_AIRLINK_MODE_SPI_SLAVE) {

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
    if (cmd == NULL) return 0;
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
    if (cmd == NULL) return 0;
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
        data = luaL_checklstring(L, 2, &len);
    }
    else if (lua_isuserdata(L, 2)) {
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
    if (cmd == NULL) return 0;
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
    if (cmd == NULL) return 0;
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
    if (cmd == NULL) return 0;
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
    case LUAT_AIRLINK_CONF_IRQ_TIMEOUT:
        if (value < 5) {
            value = 5;
        }
        else if (value > 60*1000) {
            value = 60*1000;
        }
        g_airlink_spi_conf.irq_timeout = value;
        break;
    case LUAT_AIRLINK_CONF_SPI_SPEED:
        if (value < 1000000) {
            value = 1000000; // 最低1MHz
        }
        else if (value > 100000000) {
            value = 100000000; // 最高100MHz
        }
        g_airlink_spi_conf.speed = value;
        break;
    case LUAT_AIRLINK_CONF_UART_ID:
        // if (value < 0 || value > 3) {
        //     LLOGE("无效的UART %d, 只能是0~3", value);
        //     return 0;
        // }
        LLOGD("配置UART ID为 %d", value);
        g_airlink_spi_conf.uart_id = value;
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
    uint32_t val = luaL_checkinteger(L, 1);
    luat_airlink_set_pause(val);
    // 配置过wakeup pin，并且airlink恢复运行时，就触发一次中断唤醒
    if (g_airlink_wakeup_irq_ctx.master_pin != 0 && !g_airlink_pause) {
        g_airlink_wakeup_irq_ctx.enable = 1;
    }
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

/*
开启wakeup唤醒中断模式
@api airlink.wakeupIrqmode(mode, master_gpio, slave_gpio, irq_mode)
@int mode false: 禁用 true: 启用
@int master_gpio 主机引脚, 建议使用GPIO20
@int slave_gpio 从机引脚, Air8000使用GPIO140, Air8101使用GPIO28
@int irq_mode 中断模式, 例如gpio.RISING (上升沿), gpio.FALLING (下降沿)
@return nil 无返回值
@usage
-- 用于设置唤醒wifi 开启此功能后, 会在Air8000主机休眠唤醒时，允许在master_gpio上产生一个脉冲，从而通过绑定的slave_gpio触发中断唤醒wifi
airlink.wakeupIrqmode(true, 20, 140, gpio.RISING)
-- 注意, 开启本模式, 外部接线必须稳固, 否则可能会导致触发的中断脉冲不完整或接收不到，从而无法唤醒wifi
*/
static int l_airlink_wakeup_irqmode(lua_State *L) {
    luat_airlink_irq_ctx_t ctx = {0};
    ctx.enable = lua_toboolean(L, 1);
    if (ctx.enable) {
        ctx.master_pin = luaL_checkinteger(L, 2);
        ctx.slave_pin = luaL_checkinteger(L, 3);
        ctx.irq_mode = luaL_checkinteger(L, 4);
    }
    else {
        ctx.master_pin = 0;
        ctx.slave_pin = 0;
        ctx.irq_mode = -1;
    }
    luat_airlink_wakeup_irqmode(&ctx);
    return 0;
}

/*
关闭airlink相关供电
@api airlink.power(enable)
@boolean enable true: 使能 false: 禁用
@return nil 无返回值
@usage
-- 关闭airlink相关供电, 通常用于省电
-- 当前仅对Air8000带wifi功能的模组有效
-- 关闭之后, 如需使用wifi功能, 需要重新执行wifi.init等操作
-- 注意, wifi供电关掉后, >=128的GPIO也会变成输入高阻态
airlink.power(false)
-- 开启wifi芯片,恢复airlink通信
airlink.power(true)
*/
static int l_airlink_power(lua_State *L) {
    int enable = 0;
    if (lua_isboolean(L, 1)) {
        enable = lua_toboolean(L, 1);
    }
    else if (lua_isinteger(L, 1)) {
        enable = luaL_checkinteger(L, 1);
    }
    // 首先, 判断是不是有wifi的Air8000
    if (luat_airlink_has_wifi()) {
        if (enable) {
            luat_gpio_set(23, 1);
            luat_airlink_set_pause(0);
            LLOGI("wifi chip power on, airlink pause=false");
        }
        else {
            luat_gpio_set(23, 0);
            luat_airlink_set_pause(1);
            LLOGI("wifi chip power off, airlink pause=true");
        }
    }
    return 0;
}

/*
获取从机版本号
@api airlink.sver()
@return int 从机固件版本号
@usage
-- 注意, 获取之前, 需要确定airlink.ready()已经返回true
log.info("airlink", "从机固件版本号", airlink.sver())

*/
static int l_airlink_sversion(lua_State *L) {
    uint32_t version = 0;
    if (g_airlink_ext_dev_info.tp == 0x01) {
        memcpy(&version, g_airlink_ext_dev_info.wifi.version, 4);
    }
    else if (g_airlink_ext_dev_info.tp == 0x02) {
        memcpy(&version, g_airlink_ext_dev_info.cat1.version, 4);
    }
    lua_pushinteger(L, version);
    return 1;
}

// ============================================================
// 多出口绑定 & RPC Lua 绑定
// ============================================================

#ifdef LUAT_USE_AIRLINK_MULTI_TRANSPORT
//@api airlink.bindTransport(adapter_id, mode)
//@int  adapter_id  网络适配器ID (0=wifi, 1=4G 等, 对应 luat_netdrv_get 的 id)
//@int  mode        目标传输 mode (airlink.MODE_SPI_SLAVE / MODE_SPI_MASTER / MODE_UART)
//@return bool 成功返回 true, 失败返回 false
//@usage
// -- wifi(0) 走 UART, 4G(1) 走 SPI Master
// airlink.bindTransport(0, airlink.MODE_UART)
// airlink.bindTransport(1, airlink.MODE_SPI_MASTER)
static int l_airlink_bind_transport(lua_State* L) {
    uint8_t adapter_id = (uint8_t)luaL_checkinteger(L, 1);
    uint8_t mode       = (uint8_t)luaL_checkinteger(L, 2);
    int ret = luat_airlink_bind_adapter_transport(adapter_id, mode);
    lua_pushboolean(L, ret == 0);
    return 1;
}
#endif

#ifdef LUAT_USE_AIRLINK_RPC

//@api airlink.rpcRegister(rpc_id, func)
//@int      rpc_id  RPC 功能号 (uint16_t)
//@function func    处理函数, 原型: function(rpc_id, req_data) return resp_data end
//                  req_data 为 string 或 nil; resp_data 为 string 或 nil
//@return bool 成功返回 true, 失败返回 false
//@usage
// airlink.rpcRegister(0x0001, function(rpc_id, req)
//     log.info("rpc", "收到请求", rpc_id, req)
//     return "response"
// end)
static int l_airlink_rpc_handler(uint16_t rpc_id,
                                  const uint8_t* req, uint16_t req_len,
                                  uint8_t* resp, uint16_t resp_size, uint16_t* resp_len,
                                  void* userdata);

// Lua 函数引用表 (rpc_id → lua ref), 简单数组实现
#define MAX_LUA_RPC_HANDLERS 32
static struct {
    uint16_t rpc_id;
    int lua_ref;
    uint8_t active;
} s_lua_rpc_handlers[MAX_LUA_RPC_HANDLERS];
static lua_State* s_lua_rpc_L = NULL;

static int l_airlink_rpc_handler(uint16_t rpc_id,
                                   const uint8_t* req, uint16_t req_len,
                                   uint8_t* resp, uint16_t resp_size, uint16_t* resp_len,
                                   void* userdata) {
    (void)userdata;
    *resp_len = 0;
    if (s_lua_rpc_L == NULL) return -1;
    lua_State* L = s_lua_rpc_L;

    // 查找 lua_ref
    int ref = LUA_NOREF;
    for (int i = 0; i < MAX_LUA_RPC_HANDLERS; i++) {
        if (s_lua_rpc_handlers[i].active && s_lua_rpc_handlers[i].rpc_id == rpc_id) {
            ref = s_lua_rpc_handlers[i].lua_ref;
            break;
        }
    }
    if (ref == LUA_NOREF) return -404;

    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);  // push function
    lua_pushinteger(L, rpc_id);               // arg1: rpc_id
    if (req && req_len > 0) {
        lua_pushlstring(L, (const char*)req, req_len); // arg2: req as string
    } else {
        lua_pushnil(L);
    }
    if (lua_pcall(L, 2, 1, 0) != LUA_OK) {
        LLOGE("airlink rpc lua call error: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
        return -1;
    }
    // 取返回值
    if (lua_isstring(L, -1)) {
        size_t rlen = 0;
        const char* rdata = lua_tolstring(L, -1, &rlen);
        if (rlen > resp_size) rlen = resp_size;
        if (rdata && rlen > 0) {
            memcpy(resp, rdata, rlen);
            *resp_len = (uint16_t)rlen;
        }
    }
    lua_pop(L, 1);
    return 0;
}

static int l_airlink_rpc_register(lua_State* L) {
    uint16_t rpc_id = (uint16_t)luaL_checkinteger(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);

    // 保存 Lua 状态指针 (线程共享)
    s_lua_rpc_L = L;

    // 找空槽或已有同 rpc_id 的槽
    int slot = -1;
    for (int i = 0; i < MAX_LUA_RPC_HANDLERS; i++) {
        if (s_lua_rpc_handlers[i].active && s_lua_rpc_handlers[i].rpc_id == rpc_id) {
            // 取消旧引用
            luaL_unref(L, LUA_REGISTRYINDEX, s_lua_rpc_handlers[i].lua_ref);
            slot = i;
            break;
        }
        if (slot == -1 && !s_lua_rpc_handlers[i].active) {
            slot = i;
        }
    }
    if (slot == -1) {
        lua_pushboolean(L, 0);
        return 1;
    }

    lua_pushvalue(L, 2);  // 复制函数到栈顶
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    s_lua_rpc_handlers[slot].rpc_id  = rpc_id;
    s_lua_rpc_handlers[slot].lua_ref = ref;
    s_lua_rpc_handlers[slot].active  = 1;

    // 注册 C 层 handler (l_airlink_rpc_handler)
    luat_airlink_rpc_register(rpc_id, l_airlink_rpc_handler, NULL);

    lua_pushboolean(L, 1);
    return 1;
}

//@api airlink.rpc(mode, rpc_id, req_data, timeout_ms)
//@int    mode        目标传输 mode
//@int    rpc_id      RPC 功能号
//@string req_data    请求数据 (string 或 nil)
//@int    timeout_ms  超时毫秒数 (默认 3000)
//@return bool,string 成功返回 true+响应数据, 失败/超时返回 false+错误信息
//@usage
// local ok, resp = airlink.rpc(airlink.MODE_UART, 0x0001, "hello", 3000)
// if ok then log.info("rpc", "响应:", resp) end
static int l_airlink_rpc(lua_State* L) {
    uint8_t  mode      = (uint8_t)luaL_checkinteger(L, 1);
    uint16_t rpc_id    = (uint16_t)luaL_checkinteger(L, 2);
    size_t   req_len   = 0;
    const uint8_t* req = NULL;
    if (lua_isstring(L, 3)) {
        req = (const uint8_t*)lua_tolstring(L, 3, &req_len);
    }
    uint32_t timeout_ms = (uint32_t)luaL_optinteger(L, 4, 3000);

    uint8_t resp_buf[512];
    uint16_t resp_len = 0;
    int ret = luat_airlink_rpc(mode, rpc_id, req, (uint16_t)req_len,
                                resp_buf, sizeof(resp_buf), &resp_len, timeout_ms);
    if (ret == 0) {
        lua_pushboolean(L, 1);
        lua_pushlstring(L, (const char*)resp_buf, resp_len);
    } else if (ret == -1) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "timeout");
    } else {
        lua_pushboolean(L, 0);
        lua_pushinteger(L, ret);
    }
    return 2;
}

#endif /* LUAT_USE_AIRLINK_RPC */

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
    { "wakeupIrqmode", ROREG_FUNC(l_airlink_wakeup_irqmode)},
    { "power",         ROREG_FUNC(l_airlink_power)},

    { "sver",          ROREG_FUNC(l_airlink_sversion) },


    // 测试用的fota指令
    { "sfota",         ROREG_FUNC(l_airlink_sfota )},
    { "sfota_init",    ROREG_FUNC(l_airlink_sfota_init )},
    { "sfota_done",    ROREG_FUNC(l_airlink_sfota_done )},
    { "sfota_end",     ROREG_FUNC(l_airlink_sfota_end )},
    { "sfota_write",   ROREG_FUNC(l_airlink_sfota_write )},

    { "debug",         ROREG_FUNC(l_airlink_debug )},

#ifdef LUAT_USE_AIRLINK_MULTI_TRANSPORT
    // 多出口绑定
    //@const bindTransport function 绑定 adapter 到指定 transport
    { "bindTransport", ROREG_FUNC(l_airlink_bind_transport )},
#endif

#ifdef LUAT_USE_AIRLINK_RPC
    //@const rpcRegister function 注册 RPC 服务端处理函数
    { "rpcRegister",   ROREG_FUNC(l_airlink_rpc_register )},
    //@const rpc function 同步调用对端 RPC
    { "rpc",           ROREG_FUNC(l_airlink_rpc )},
#endif

    //@const MODE_SPI_SLAVE number airlink.start参数, SPI从机模式
    { "MODE_SPI_SLAVE",    ROREG_INT(LUAT_AIRLINK_MODE_SPI_SLAVE) },
    //@const MODE_SPI_MASTER number airlink.start参数, SPI主机模式
    { "MODE_SPI_MASTER",   ROREG_INT(LUAT_AIRLINK_MODE_SPI_MASTER) },
    //@const MODE_UART number airlink.start参数, UART模式
    { "MODE_UART",         ROREG_INT(LUAT_AIRLINK_MODE_UART) },

    //@const CONF_SPI_ID number SPI配置参数, 设置SPI的ID
    { "CONF_SPI_ID",       ROREG_INT(LUAT_AIRLINK_CONF_SPI_ID)},
    //@const CONF_SPI_CS number SPI配置参数, 设置SPI的CS脚的GPIO
    { "CONF_SPI_CS",       ROREG_INT(LUAT_AIRLINK_CONF_SPI_CS)},
    //@const CONF_SPI_RDY number SPI/UART配置参数, 设置RDY脚的GPIO
    { "CONF_SPI_RDY",      ROREG_INT(LUAT_AIRLINK_CONF_SPI_RDY)},
    //@const CONF_SPI_IRQ number SPI/UART配置参数, 设置IRQ脚的GPIO
    { "CONF_SPI_IRQ",      ROREG_INT(LUAT_AIRLINK_CONF_SPI_IRQ)},
    //@const CONF_SPI_SPEED number SPI配置参数, 设置SPI的波特率
    { "CONF_SPI_SPEED",    ROREG_INT(LUAT_AIRLINK_CONF_SPI_SPEED)},
    //@const CONF_IRQ_TIMEOUT number SPIUART配置参数, 设置IRQ模式的等待超时时间
    { "CONF_IRQ_TIMEOUT",  ROREG_INT(LUAT_AIRLINK_CONF_IRQ_TIMEOUT)},
    //@const CONF_UART_ID number UART配置参数, 设置UART的ID
    { "CONF_UART_ID",      ROREG_INT(LUAT_AIRLINK_CONF_UART_ID)},

	{ NULL,                ROREG_INT(0) }
};

LUAMOD_API int luaopen_airlink( lua_State *L ) {
    luat_newlib2(L, reg_airlink);
    return 1;
}
