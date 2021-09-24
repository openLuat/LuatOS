/*
@module  spiv2
@summary spiv2操作库
@version 1.0
@date    2021.09.24
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_spiv2.h"
#include "luat_zbuff.h"

#include "luat_log.h"
#define LUAT_LOG_TAG "luat.spiv2"

/**
设置并启用SPI总线
@api spiv2.bus_setup(id)
@int SPI总线ID,例如0
@return int 成功返回0,否则返回其他值
@usage
-- 初始化spi总线
spiv2.bus_setup(0)
*/
static int l_spiv2_bus_setup(lua_State *L) {
    int bus_id = luaL_checkinteger(L, 1);
    lua_pushinteger(L, luat_spiv2_bus_setup(bus_id));
    return 1;
}

/**
设置并启用SPI设备
@api spi_v2.device_setup(bus,id, cs, CPHA, CPOL, dataw, bandrate, bitdict, ms, mode)
@int SPI号,例如0
@int CS 片选脚
@int CPHA 默认0,可选0/1
@int CPOL 默认0,可选0/1
@int 数据宽度,默认8bit
@int 波特率,默认2M=2000000
@int 大小端, 默认spi.MSB, 可选spi.LSB
@int 主从设置, 默认主1, 可选从机0. 通常只支持主机模式
@int 工作模式, 全双工1, 半双工0, 默认全双工
@return int 成功返回0,否则返回其他值
@usage
-- 初始化spi设备
spi_v2.device_setup(0,0,20,0,0,8,2000000,spi.MSB,1,1)
*/
static int l_spiv2_device_setup(lua_State *L) {
    luat_spiv2_t spi_config = {0};
    spi_config.bus_id = luaL_checkinteger(L, 1);
    spi_config.dev_id = luaL_checkinteger(L, 2);
    spi_config.cs = luaL_optinteger(L, 3, 255); // 默认无
    spi_config.CPHA = luaL_optinteger(L, 4, 0); // CPHA0
    spi_config.CPOL = luaL_optinteger(L, 5, 0); // CPOL0
    spi_config.dataw = luaL_optinteger(L, 6, 8); // 8bit
    spi_config.bandrate = luaL_optinteger(L, 7, 2000000U); // 2000000U
    spi_config.bit_dict = luaL_optinteger(L, 8, 1); // MSB=1, LSB=0
    spi_config.master = luaL_optinteger(L, 9, 1); // master=1,slave=0
    spi_config.mode = luaL_optinteger(L, 10, 1); // FULL=1, half=0

    lua_pushinteger(L, luat_spiv2_device_setup(&spi_config));

    return 1;
}

/**
关闭指定的SPI总线
@api spiv2.bus_close(id)
@int SPI总线号,例如0
@return int 成功返回0,否则返回其他值
@usage
-- 初始化spi总线
spiv2.bus_close(0)
*/
static int l_spiv2_bus_close(lua_State *L) {
    int bus_id = luaL_checkinteger(L, 1);
    lua_pushinteger(L, luat_spiv2_bus_close(bus_id));
    return 1;
}

/**
关闭指定的SPI设备
@api spiv2.device_close(id)
@int SPI号,例如0
@return int 成功返回0,否则返回其他值
@usage
-- 初始化spi设备
spiv2.device_close(0)
*/
static int l_spiv2_device_close(lua_State *L) {
    int dev_id = luaL_checkinteger(L, 1);
    lua_pushinteger(L, luat_spiv2_device_close(dev_id));
    return 1;
}

/**
传输SPI数据
@api spiv2.transfer(id, send_data[, len])
@int SPI号,例如0
@string/zbuff 待发送的数据，如果为zbuff数据，则会从对象所处的指针处开始读
@int 可选。待发送数据的长度，默认为data长度
@return string 读取成功返回字符串,否则返回nil
@usage
-- 初始化spi
spiv2.device_setup(0,0,nil,0,0,8,2000000,spi.MSB,1,1)
local recv = spiv2.transfer(0, "123")--发送123,并读取数据

local buff = zbuff.create(1024, 0x33) --创建一个初值全为0x33的内存区域
local recv = spiv2.transfer(0, buff)--把zbuff数据从指针开始，全发出去,并读取数据
*/
static int l_spiv2_transfer(lua_State *L) {
    int dev_id = luaL_checkinteger(L, 1);
    size_t len;
    const char* send_buff;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        send_buff = buff->addr+buff->cursor;
        len = buff->len - buff->cursor;
    }else{
        send_buff = lua_tolstring(L, 2, &len);
    }
    if(lua_isinteger(L,3)){//长度参数
        size_t len_temp = luaL_checkinteger(L,3);
        if(len_temp < len)
            len = len_temp;
    }
    //长度为0时，直接返回空字符串
    if(len <= 0){
        lua_pushlstring(L,NULL,0);
        return 1;
    }
    char* recv_buff = luat_heap_malloc(len);
    if(recv_buff == NULL)
        return 0;
    int ret = luat_spiv2_transfer(dev_id, send_buff, recv_buff, len);
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
@api spiv2.recv(id, size)
@int SPI号,例如0
@int 数据长度
@return string 读取成功返回字符串,否则返回nil
@usage
-- 初始化spi
spiv2.device_setup(0,0,nil,0,0,8,2000000,spi.MSB,1,1)
local recv = spiv2.recv(0, 4)--接收4字节数据
*/
static int l_spiv2_recv(lua_State *L) {
    int dev_id = luaL_checkinteger(L, 1);
    int len = luaL_checkinteger(L, 2);
    char* recv_buff = luat_heap_malloc(len);
    if(recv_buff == NULL)
        return 0;
    int ret = luat_spiv2_recv(dev_id, recv_buff, len);
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
@api spiv2.send(id, data[, len])
@int SPI号,例如0
@string/zbuff 待发送的数据，如果为zbuff数据，则会从对象所处的指针处开始读
@int 可选。待发送数据的长度，默认为data长度
@return int 发送结果
@usage
-- 初始化spi
spiv2.setup(0,0,nil,0,0,8,2000000,spi.MSB,1,1)
local result = spiv2.send(0, "123")--发送123

local buff = zbuff.create(1024, 0x33) --创建一个初值全为0x33的内存区域
local result = spiv2.send(0, buff)--把zbuff数据从指针开始，全发出去
*/
static int l_spiv2_send(lua_State *L) {
    int dev_id = luaL_checkinteger(L, 1);
    size_t len;
    const char* send_buff;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        send_buff = buff->addr+buff->cursor;
        len = buff->len - buff->cursor;
    }else{
        send_buff = lua_tolstring(L, 2, &len);
    }
    if(lua_isinteger(L,3)){//长度参数
        size_t len_temp = luaL_checkinteger(L,3);
        if(len_temp < len)
            len = len_temp;
    }
    //长度为0时，直接返回
    if(len <= 0){
        lua_pushinteger(L,0);
        return 1;
    }
    lua_pushinteger(L, luat_spiv2_send(dev_id, send_buff, len));
    return 1;
}


//------------------------------------------------------------------
#include "rotable.h"
static const rotable_Reg reg_spiv2[] =
{
    { "bus_setup" ,       l_spiv2_bus_setup,         0},
    { "bus_close",        l_spiv2_bus_close,         0},
    { "device_setup" ,    l_spiv2_device_setup,      0},
    { "device_close",     l_spiv2_device_close,      0},
    { "transfer",         l_spiv2_transfer,      0},
    { "recv",             l_spiv2_recv,         0},
    { "send",             l_spiv2_send,         0},

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

LUAMOD_API int luaopen_spiv2( lua_State *L ) {
    luat_newlib(L, reg_spiv2);
    return 1;
}
