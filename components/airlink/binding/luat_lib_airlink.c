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
#include "luat_airlink_ping.h"
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

#ifdef LUAT_USE_AIRLINK_RPC
#include "luat_airlink_rpc.h"
#include "drv_sdata.pb.h"
#define AIRLINK_SDATA_CHUNK 1400

/* 客户端 sdata 发送: RPC 模式走 nb_notify 分块, 否则走原始 cmd 0x20 */
int luat_airlink_sdata_send(const void* data, size_t len) {
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        const uint8_t* ptr = (const uint8_t*)data;
        size_t remaining = len;
        while (remaining > 0) {
            size_t chunk = (remaining > AIRLINK_SDATA_CHUNK) ? AIRLINK_SDATA_CHUNK : remaining;
            SdataNotify notify = SdataNotify_init_zero;
            notify.data.size = (pb_size_t)chunk;
            memcpy(notify.data.bytes, ptr, chunk);
            int rc = luat_airlink_rpc_nb_notify((uint8_t)mode, 0x0500,
                                                SdataNotify_fields, &notify);
            if (rc != 0) return rc;
            ptr       += chunk;
            remaining -= chunk;
        }
        return 0;
    }
    if (len > 1500) return -1;
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + len);
    if (!cmd) return -2;
    cmd->cmd = 0x20;
    cmd->len = (uint16_t)len;
    memcpy(cmd->data, data, len);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    return 0;
}
#else
static int luat_airlink_sdata_send(const void* data, size_t len) {
    if (len > 1500) return -1;
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + len);
    if (!cmd) return -2;
    cmd->cmd = 0x20;
    cmd->len = (uint16_t)len;
    memcpy(cmd->data, data, len);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    return 0;
}
#endif

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
        luat_zbuff_t* buff = tozbuff(L);
        data = (const char*)buff->addr;
        len = buff->used;
    }
    else {
        LLOGE("无效的参数,只能是字符串或者zbuff");
        return 0;
    }
    int rc = luat_airlink_sdata_send(data, len);
    lua_pushboolean(L, rc == 0);
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

#ifdef LUAT_USE_AIRLINK_LOOPBACK
#include "luat_airlink_rpc.h"
#include "drv_gpio.pb.h"
#include "drv_uart.pb.h"
#include "drv_wlan.pb.h"
#include "drv_pm.pb.h"

#define AIRLINK_LIB_RPC_ID_GPIO  0x0100
#define AIRLINK_LIB_RPC_ID_UART  0x0200
#define AIRLINK_LIB_RPC_ID_WLAN  0x0300
#define AIRLINK_LIB_RPC_ID_PM    0x0400

/*
nanopb GPIO RPC loopback 自测
@api airlink.testNanopbGpio()
@return int 0=全部通过, 负值=失败步骤号
@usage
-- 在 loopback 模式启动后调用
local rc = airlink.testNanopbGpio()
assert(rc == 0, "nanopb GPIO RPC 测试失败: " .. tostring(rc))
*/
static int l_airlink_test_nanopb_gpio(lua_State* L) {
    int rc = 0;

    // step 1: write pin=5 HIGH
    {
        drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
        drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
        req.which_payload = drv_gpio_GpioRpcRequest_write_tag;
        req.payload.write.pin   = 5;
        req.payload.write.level = drv_gpio_GpioLevel_GPIO_LEVEL_HIGH;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_GPIO,
            drv_gpio_GpioRpcRequest_fields,  &req,
            drv_gpio_GpioRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -1; goto done; }
        if (resp.which_payload != drv_gpio_GpioRpcResponse_write_tag) { rc = -2; goto done; }
        if (!resp.payload.write.result.has_code ||
            resp.payload.write.result.code != drv_gpio_GpioResultCode_GPIO_RES_OK) {
            rc = -3; goto done;
        }
    }

    // step 2: read pin=5 expect HIGH
    {
        drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
        drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
        req.which_payload = drv_gpio_GpioRpcRequest_read_tag;
        req.payload.read.pin = 5;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_GPIO,
            drv_gpio_GpioRpcRequest_fields,  &req,
            drv_gpio_GpioRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -4; goto done; }
        if (resp.which_payload != drv_gpio_GpioRpcResponse_read_tag) { rc = -5; goto done; }
        if (!resp.payload.read.result.has_code ||
            resp.payload.read.result.code != drv_gpio_GpioResultCode_GPIO_RES_OK) {
            rc = -6; goto done;
        }
        if (!resp.payload.read.has_level ||
            resp.payload.read.level != drv_gpio_GpioLevel_GPIO_LEVEL_HIGH) {
            rc = -7; goto done;
        }
    }

    // step 3: timeout test (unknown rpc_id, 500ms)
    {
        drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
        drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
        req.which_payload = drv_gpio_GpioRpcRequest_read_tag;
        req.payload.read.pin = 1;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, 0xFFFF,
            drv_gpio_GpioRpcRequest_fields,  &req,
            drv_gpio_GpioRpcResponse_fields, &resp,
            500);
        if (ret == 0) { rc = -8; goto done; } // 期望非零 (服务端无handler → -404, 或超时 → -1)
    }

done:
    lua_pushinteger(L, rc);
    return 1;
}

/*
nanopb UART RPC loopback 自测
@api airlink.testNanopbUart()
@return int 0=全部通过, 负值=失败步骤号
*/
static int l_airlink_test_nanopb_uart(lua_State* L) {
    int rc = 0;

    // step 1: uart setup (PC stub 返回 -1 → FAIL result 也可接受)
    {
        drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
        drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
        req.which_payload       = drv_uart_UartRpcRequest_setup_tag;
        req.payload.setup.id        = 10;  // airlink uart 0
        req.payload.setup.has_baud_rate = true;
        req.payload.setup.baud_rate = 115200;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_UART,
            drv_uart_UartRpcRequest_fields,  &req,
            drv_uart_UartRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -1; goto done_uart; }
        if (resp.which_payload != drv_uart_UartRpcResponse_setup_tag) { rc = -2; goto done_uart; }
        // PC stub 可能返回 FAIL, 但只要 RPC 调通即可
    }

    // step 2: uart write (PC stub 无 uart driver, 预期 FAIL, 但 RPC 应答不超时)
    {
        drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
        drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
        req.which_payload        = drv_uart_UartRpcRequest_write_tag;
        req.payload.write.id     = 10;
        req.payload.write.data.size = 4;
        req.payload.write.data.bytes[0] = 'T';
        req.payload.write.data.bytes[1] = 'E';
        req.payload.write.data.bytes[2] = 'S';
        req.payload.write.data.bytes[3] = 'T';
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_UART,
            drv_uart_UartRpcRequest_fields,  &req,
            drv_uart_UartRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -3; goto done_uart; }
        if (resp.which_payload != drv_uart_UartRpcResponse_write_tag) { rc = -4; goto done_uart; }
    }

    // step 3: uart close
    {
        drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
        drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
        req.which_payload        = drv_uart_UartRpcRequest_close_tag;
        req.payload.close.id     = 10;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_UART,
            drv_uart_UartRpcRequest_fields,  &req,
            drv_uart_UartRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -5; goto done_uart; }
        if (resp.which_payload != drv_uart_UartRpcResponse_close_tag) { rc = -6; goto done_uart; }
    }

done_uart:
    lua_pushinteger(L, rc);
    return 1;
}

/*
nanopb WLAN RPC loopback 自测
@api airlink.testNanopbWlan()
@return int 0=全部通过, 负值=失败步骤号
*/
static int l_airlink_test_nanopb_wlan(lua_State* L) {
    int rc = 0;

    // step 1: wlan init (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_init_tag;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -1; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_init_tag) { rc = -2; goto done_wlan; }
        if (!resp.payload.init.result.has_code ||
            resp.payload.init.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -3; goto done_wlan;
        }
    }

    // step 2: wlan scan (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_scan_tag;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -4; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_scan_tag) { rc = -5; goto done_wlan; }
        if (!resp.payload.scan.result.has_code ||
            resp.payload.scan.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -6; goto done_wlan;
        }
    }

    // step 3: wlan ap_start (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_ap_start_tag;
        strncpy(req.payload.ap_start.ssid, "TestAP", sizeof(req.payload.ap_start.ssid) - 1);
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -7; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_ap_start_tag) { rc = -8; goto done_wlan; }
        if (!resp.payload.ap_start.result.has_code ||
            resp.payload.ap_start.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -9; goto done_wlan;
        }
    }

    // step 4: wlan ap_stop (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_ap_stop_tag;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -10; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_ap_stop_tag) { rc = -11; goto done_wlan; }
        if (!resp.payload.ap_stop.result.has_code ||
            resp.payload.ap_stop.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -12; goto done_wlan;
        }
    }

    // step 5: wlan connect (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_connect_tag;
        strncpy(req.payload.connect.ssid, "TestSSID", sizeof(req.payload.connect.ssid) - 1);
        req.payload.connect.has_password = true;
        strncpy(req.payload.connect.password, "testpass", sizeof(req.payload.connect.password) - 1);
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -13; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_connect_tag) { rc = -14; goto done_wlan; }
        if (!resp.payload.connect.result.has_code ||
            resp.payload.connect.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -15; goto done_wlan;
        }
    }

    // step 6: wlan disconnect (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_disconnect_tag;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -16; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_disconnect_tag) { rc = -17; goto done_wlan; }
        if (!resp.payload.disconnect.result.has_code ||
            resp.payload.disconnect.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -18; goto done_wlan;
        }
    }

done_wlan:
    lua_pushinteger(L, rc);
    return 1;
}

/*
nanopb PM RPC loopback 自测
@api airlink.testNanopbPm()
@return int 0=全部通过, 负值=失败步骤号
*/
static int l_airlink_test_nanopb_pm(lua_State* L) {
    int rc = 0;

    // step 1: pm_power_ctrl (PC stub 返回 0 → OK)
    {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload              = drv_pm_PmRpcRequest_power_ctrl_tag;
        req.payload.power_ctrl.id      = 1;
        req.payload.power_ctrl.val     = 1;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_PM,
            drv_pm_PmRpcRequest_fields,  &req,
            drv_pm_PmRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -1; goto done_pm; }
        if (resp.which_payload != drv_pm_PmRpcResponse_power_ctrl_tag) { rc = -2; goto done_pm; }
        if (!resp.payload.power_ctrl.result.has_code ||
            resp.payload.power_ctrl.result.code != drv_pm_PmResultCode_PM_RES_OK) {
            rc = -3; goto done_pm;
        }
    }

    // step 2: pm_wakeup_pin (PC stub 返回 -1 → FAIL result, 但 RPC 应答不超时)
    {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload             = drv_pm_PmRpcRequest_wakeup_pin_tag;
        req.payload.wakeup_pin.pin    = 5;
        req.payload.wakeup_pin.val    = 1;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_PM,
            drv_pm_PmRpcRequest_fields,  &req,
            drv_pm_PmRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -4; goto done_pm; }
        if (resp.which_payload != drv_pm_PmRpcResponse_wakeup_pin_tag) { rc = -5; goto done_pm; }
        // PC stub 返回 -1 → FAIL result 也可接受
    }

    // step 3: pm_request (PC stub 返回 0 → OK)
    {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload              = drv_pm_PmRpcRequest_pm_request_tag;
        req.payload.pm_request.mode    = 0;  // LUAT_PM_SLEEP_MODE_NONE
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_PM,
            drv_pm_PmRpcRequest_fields,  &req,
            drv_pm_PmRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -6; goto done_pm; }
        if (resp.which_payload != drv_pm_PmRpcResponse_pm_request_tag) { rc = -7; goto done_pm; }
        if (!resp.payload.pm_request.result.has_code ||
            resp.payload.pm_request.result.code != drv_pm_PmResultCode_PM_RES_OK) {
            rc = -8; goto done_pm;
        }
    }

done_pm:
    lua_pushinteger(L, rc);
    return 1;
}
#endif /* LUAT_USE_AIRLINK_LOOPBACK */

// =====================================================================
// airlink.ping() — async raw ping/pong
// =====================================================================

typedef struct {
    uint64_t pkgid;
    uint64_t rtt_ms;
    uint8_t  ok;
    int      error_code;
    uint16_t echo_len;
    uint8_t  echo_buf[AIRLINK_PING_ECHO_MAX];
} ping_result_msg_t;

typedef struct {
    uint8_t  mode;
    uint64_t pkgid;
    uint32_t timeout_ms;
    uint16_t payload_len;
    uint8_t  payload[0]; // flexible array member
} ping_worker_args_t;

static int ping_result_cb(lua_State *L, void *ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    ping_result_msg_t* result = (ping_result_msg_t*)msg->ptr;

    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "AIRLINK_PING_RESULT");
    lua_pushinteger(L, (lua_Integer)result->pkgid);
    lua_pushboolean(L, result->ok ? 1 : 0);
    if (result->ok) {
        lua_pushinteger(L, (lua_Integer)result->rtt_ms);
        lua_pushlstring(L, (const char*)result->echo_buf, result->echo_len);
    } else {
        if (result->error_code == -1) {
            lua_pushstring(L, "timeout");
        } else {
            lua_pushinteger(L, result->error_code);
        }
        lua_pushnil(L);
    }
    lua_call(L, 5, 0);

    luat_heap_free(result);
    return 0;
}

static int ping_worker_task(void* param) {
    ping_worker_args_t* args = (ping_worker_args_t*)param;

    ping_result_msg_t* result = (ping_result_msg_t*)luat_heap_malloc(sizeof(ping_result_msg_t));
    if (!result) {
        LLOGE("ping worker: malloc result failed");
        luat_heap_free(args);
        return -1;
    }
    memset(result, 0, sizeof(ping_result_msg_t));
    result->pkgid = args->pkgid;

    uint64_t rtt_ms   = 0;
    uint16_t echo_len = 0;
    int ret = luat_airlink_ping_raw(
        args->mode, args->pkgid,
        args->payload, args->payload_len,
        args->timeout_ms,
        &rtt_ms,
        result->echo_buf, AIRLINK_PING_ECHO_MAX,
        &echo_len);
    luat_heap_free(args);

    if (ret == 0) {
        result->ok       = 1;
        result->rtt_ms   = rtt_ms;
        result->echo_len = echo_len;
    } else {
        result->ok         = 0;
        result->error_code = ret;
    }

    rtos_msg_t msg = {0};
    msg.handler = ping_result_cb;
    msg.ptr     = result;
    luat_msgbus_put(&msg, 0);
    return 0;
}

/*
发起异步 ping, 结果通过 sys.subscribe("AIRLINK_PING_RESULT", ...) 接收
@api airlink.ping(data, timeout_ms)
@string/zbuff data 要回显的payload, 可为空字符串
@int timeout_ms 超时毫秒数, 默认3000
@return int request_id, 成功发起时返回pkgid; 失败返回nil
@usage
local reqid = airlink.ping("hello", 3000)
sys.subscribe("AIRLINK_PING_RESULT", function(id, ok, v1, v2)
    if id ~= reqid then return end
    if ok then
        log.info("ping", "rtt=" .. v1 .. "ms echo=" .. v2)
    else
        log.info("ping", "failed: " .. tostring(v1))
    end
end)
*/
static int l_airlink_ping(lua_State *L) {
    const char* data     = NULL;
    size_t      data_len = 0;

    int t = lua_type(L, 1);
    if (t == LUA_TSTRING) {
        data = lua_tolstring(L, 1, &data_len);
    } else if (t == LUA_TUSERDATA) {
        luat_zbuff_t* buff = (luat_zbuff_t*)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE);
        data     = (const char*)buff->addr;
        data_len = buff->used;
    }
    // nil/none → empty payload

    if (data_len > AIRLINK_PING_ECHO_MAX) {
        LLOGE("ping: payload too large %zu (max %d)", data_len, AIRLINK_PING_ECHO_MAX);
        lua_pushnil(L);
        return 1;
    }

    uint32_t timeout_ms = (uint32_t)luaL_optinteger(L, 2, 3000);
    uint64_t pkgid      = luat_airlink_get_next_cmd_id();

    size_t args_size = sizeof(ping_worker_args_t) + data_len;
    ping_worker_args_t* args = (ping_worker_args_t*)luat_heap_malloc(args_size);
    if (!args) {
        LLOGE("ping: malloc args failed");
        lua_pushnil(L);
        return 1;
    }
    memset(args, 0, sizeof(ping_worker_args_t));
    args->mode        = LUAT_AIRLINK_MODE_LOOPBACK;
    args->pkgid       = pkgid;
    args->timeout_ms  = timeout_ms;
    args->payload_len = (uint16_t)data_len;
    if (data && data_len > 0) {
        memcpy(args->payload, data, data_len);
    }

    luat_rtos_task_handle task_handle = NULL;
    int ret = luat_rtos_task_create(&task_handle, 4 * 1024, 30,
                                    "airlink_ping", ping_worker_task, args, 0);
    if (ret != 0) {
        LLOGE("ping: task create failed %d", ret);
        luat_heap_free(args);
        lua_pushnil(L);
        return 1;
    }

    lua_pushinteger(L, (lua_Integer)pkgid);
    return 1;
}

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
    { "ping",          ROREG_FUNC(l_airlink_ping)},
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
    //@const rpc function 同步调用对端 RPC
    { "rpc",           ROREG_FUNC(l_airlink_rpc )},
#endif

#ifdef LUAT_USE_AIRLINK_LOOPBACK
    //@const testNanopbGpio function nanopb GPIO RPC loopback 自测
    { "testNanopbGpio", ROREG_FUNC(l_airlink_test_nanopb_gpio) },
    //@const testNanopbUart function nanopb UART RPC loopback 自测
    { "testNanopbUart", ROREG_FUNC(l_airlink_test_nanopb_uart) },
    //@const testNanopbWlan function nanopb WLAN RPC loopback 自测
    { "testNanopbWlan", ROREG_FUNC(l_airlink_test_nanopb_wlan) },
    //@const testNanopbPm function nanopb PM RPC loopback 自测
    { "testNanopbPm",   ROREG_FUNC(l_airlink_test_nanopb_pm) },
    //@const MODE_LOOPBACK number airlink.start参数, loopback自测模式
    { "MODE_LOOPBACK",  ROREG_INT(LUAT_AIRLINK_MODE_LOOPBACK) },
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
