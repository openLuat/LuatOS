/*
@module spislave
@summary SPI从机
@version 1.0
@date    2024.3.27
@demo spislave
@tag LUAT_USE_SPI_SLAVE
@usage
-- 请查阅demo
-- 当前仅XT804系列支持, 例如 Air101/Air103/Air601
 */
#include "luat_base.h"
#include "rotable2.h"
#include "luat_zbuff.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_spi_slave.h"

#define LUAT_LOG_TAG "spislave"
#include "luat_log.h"

// 存放回调函数
static int lua_cb_ref;

/*
初始化SPI从机
@api spislave.setup(id, opts)
@int 从机SPI的编号,注意与SPI主机的编号的差异,这个与具体设备相关
@table opts 扩展配置参数,当前无参数
@return boolean true表示成功,其他失败
@usage
-- 当前仅XT804系列支持, 例如 Air101/Air103/Air601/Air690
-- Air101为例, 初始化SPI从机, 编号为2, SPI模式
spislave.setup(2)
-- Air101为例, 初始化SPI从机, 编号为3, SDIO模式
spislavve.setup(3)
*/
static int l_spi_slave_setup(lua_State *L) {
    luat_spi_slave_conf_t conf = {
        .id = luaL_checkinteger(L, 1)
    };
    int ret = luat_spi_slave_open(&conf);
    if (ret) {
        lua_pushboolean(L, 0);
        lua_pushinteger(L, ret);
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/*
是否可写
@api spislave.ready(id)
@int 从机SPI的编号
@return boolean true表示可写,其他不可写
*/
static int l_spi_slave_ready(lua_State *L) {
    luat_spi_slave_conf_t conf = {
        .id = luaL_checkinteger(L, 1)
    };
    int ret = luat_spi_slave_writable(&conf);
    if (ret) {
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

/*
注册事件回调函数
@api spislave.on(id, cb)
@int 从机SPI的编号
@function 回调函数
*/
static int l_spi_slave_on(lua_State *L) {
    if (lua_cb_ref) {
        luaL_unref(L, LUA_REGISTRYINDEX, lua_cb_ref);
        lua_cb_ref = 0;
    }
    if (lua_isfunction(L, 2)) {
        lua_pushvalue(L, 2);
        lua_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    return 0;
}

/*
读取数据
@api spislave.read(id, ptr, buff, len)
@int 从机SPI的编号
@userdata 用户数据指针, 从回调函数得到
@int zbuff缓冲对象
@int 读取长度,从回调函数得到
@return int 读取到字节数,通常与期望读取的长度相同
@return int 错误码, 仅当出错时返回
*/
static int l_spi_slave_read(lua_State *L) {
    luat_spi_slave_conf_t conf = {
        .id = luaL_checkinteger(L, 1)
    };
    void* ptr = lua_touserdata(L, 2);
    luat_zbuff_t* zbuf = (luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE);
    int len = luaL_checkinteger(L, 4);
    int ret = luat_spi_slave_read(&conf, ptr, zbuf->addr, len);
    if (ret >= 0 ){
        lua_pushinteger(L, ret);
        return 1;
    }
    lua_pushinteger(L, 0);
    lua_pushinteger(L, ret);
    return 2;
}
/*
写入数据
@api spislave.write(id, ptr, buff, len)
@int 从机SPI的编号
@userdata 用户数据指针, 当前传nil
@int zbuff缓冲对象
@int 写入长度,注意不能超过硬件限制,通常是1500字节
@return boolean true表示成功,其他失败
@return int 错误码, 仅当出错时返回
*/
static int l_spi_slave_write(lua_State *L) {
    luat_spi_slave_conf_t conf = {
        .id = luaL_checkinteger(L, 1)
    };
    luat_zbuff_t* zbuf = (luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE);
    int len = luaL_checkinteger(L, 4);
    int ret = luat_spi_slave_write(&conf, zbuf->addr, len);
    if (ret == 0 ){
        lua_pushboolean(L, 1);
        return 1;
    }
    lua_pushboolean(L, 0);
    lua_pushinteger(L, ret);
    return 2;
}

static const rotable_Reg_t reg_spi_slave[] = {
    { "setup",              ROREG_FUNC(l_spi_slave_setup)},
    { "ready",              ROREG_FUNC(l_spi_slave_ready)},
    { "read",               ROREG_FUNC(l_spi_slave_read)},
    { "write",              ROREG_FUNC(l_spi_slave_write)},
    { "on",                 ROREG_FUNC(l_spi_slave_on)},
    { NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_spislave(lua_State *L)
{
    luat_newlib2(L, reg_spi_slave);
    return 1;
}

static int l_spi_slave_event_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (!lua_cb_ref) {
        return 0; // 没设置回调函数, 直接退出
    }
    lua_rawgeti(L, LUA_REGISTRYINDEX, lua_cb_ref);
    if (!lua_isfunction(L, -1)) {
        return 0; // 没设置回调函数, 直接退出
    }
    lua_pushinteger(L, msg->arg1);
    lua_pushlightuserdata(L, msg->ptr);
    lua_pushinteger(L, msg->arg2);
    lua_call(L, 3, 0);
    return 0;
}

int l_spi_slave_event(int id, int event, void* buff, size_t max_size) {
    rtos_msg_t msg = {
        .handler = l_spi_slave_event_handler,
        .arg1 = id | event,
        .arg2 = max_size,
        .ptr = buff,
    };
    luat_msgbus_put(&msg, 0);
    return 0;
}
