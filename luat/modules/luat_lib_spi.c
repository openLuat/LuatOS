/*
@module  spi
@summary spi操作库
@version 1.0
@date    2020.04.23
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_spi.h"

/**
设置并启用SPI
@api spi.setup(id, cs, CPHA, CPOL, dataw, bandrate, bitdict, ms, mode)
@int SPI号,例如0
@int CS 片选脚,暂不可用,请填nil
@int CPHA 默认0,可选0/1
@int CPOL 默认0,可选0/1
@int 数据宽度,默认8bit
@int 波特率,默认2M=2000000
@int 大小端, 默认spi.MSB, 可选spi.LSB
@int 主从设置, 默认主1, 可选从机0. 通常只支持主机模式
@int 工作模式, 全双工1, 半双工0, 默认全双工
@return int 成功返回0,否则返回其他值
*/
static int l_spi_setup(lua_State *L) {
    luat_spi_t spi_config = {0};

    spi_config.id = luaL_checkinteger(L, 1);
    spi_config.cs = luaL_optinteger(L, 2, 255); // 默认无
    spi_config.CPHA = luaL_optinteger(L, 3, 0); // CPHA0
    spi_config.CPOL = luaL_optinteger(L, 4, 0); // CPOL0
    spi_config.dataw = luaL_optinteger(L, 5, 8); // 8bit
    spi_config.bandrate = luaL_optinteger(L, 6, 2000000U); // 2000000U
    spi_config.bit_dict = luaL_optinteger(L, 7, 1); // MSB=1, LSB=0
    spi_config.master = luaL_optinteger(L, 8, 1); // master=1,slave=0
    spi_config.mode = luaL_optinteger(L, 9, 1); // FULL=1, half=0

    lua_pushinteger(L, luat_spi_setup(&spi_config));

    return 1;
}

/**
关闭指定的SPI
@api spi.close(id)
@int SPI号,例如0
@return int 成功返回0,否则返回其他值
*/
static int l_spi_close(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushinteger(L, luat_spi_close(id));
    return 1;
}

/**
传输SPI数据
@api spi.transfer(id, send_data)
@int SPI号,例如0
@string 待发送的数据
@return string 读取成功返回字符串,否则返回nil
*/
static int l_spi_transfer(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    size_t len;
    const char* send_buff;
    send_buff = lua_tolstring(L, 2, &len);
    char* recv_buff = luat_heap_malloc(len);
    if(recv_buff == NULL)
        return 0;
    int ret = luat_spi_transfer(id, send_buff, recv_buff, len);
    if (ret > 0) {
        lua_pushlstring(L, recv_buff, ret);
        luat_heap_free(recv_buff);
        return 1;
    }
    luat_heap_free(recv_buff);
    return 0;
}

/**
接收指定长度的SPI数据
@api spi.recv(id, size)
@int SPI号,例如0
@int 数据长度
@return string 读取成功返回字符串,否则返回nil
*/
static int l_spi_recv(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int len = luaL_checkinteger(L, 2);
    char* recv_buff = luat_heap_malloc(len);
    if(recv_buff == NULL)
        return 0;
    int ret = luat_spi_recv(id, recv_buff, len);
    if (ret > 0) {
        lua_pushlstring(L, recv_buff, ret);
        luat_heap_free(recv_buff);
        return 1;
    }
    luat_heap_free(recv_buff);
    return 0;
}

/**
发送SPI数据
@api spi.send(id, data)
@int SPI号,例如0
@string 待发送的数据
@return int 发送结果
*/
static int l_spi_send(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    size_t len;
    const char* send_buff;
    send_buff = lua_tolstring(L, 2, &len);
    lua_pushinteger(L, luat_spi_send(id, send_buff, len));
    return 1;
}


//------------------------------------------------------------------
#include "rotable.h"
static const rotable_Reg reg_spi[] =
{
    { "setup" ,           l_spi_setup,         0},
    { "close",            l_spi_close,         0},
    { "transfer",         l_spi_transfer,      0},
    { "recv",             l_spi_recv,         0},
    { "send",             l_spi_send,         0},

    { "MSB",               0,                  1},
    { "LSB",               0,                  2},
    { "master",            0,                  1},
    { "slave",             0,                  2},
    { "full",              0,                  1},
    { "half",              0,                  2},

    { "SPI_0",             0,                  0},
    { "SPI_1",             0,                  1},
    { "SPI_2",             0,                  2},
	{ NULL,                 NULL,              0}
};

LUAMOD_API int luaopen_spi( lua_State *L ) {
    luat_newlib(L, reg_spi);
    return 1;
}
