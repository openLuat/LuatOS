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
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "spi"

#define META_SPI "SPI*"


/**
设置并启用SPI
@api spi.setup(id, cs, CPHA, CPOL, dataw, bandrate, bitdict, ms, mode)
@int SPI号,例如0
@int CS 片选脚,在w600不可用请填nil
@int CPHA 默认0,可选0/1
@int CPOL 默认0,可选0/1
@int 数据宽度,默认8bit
@int 波特率,默认2M=2000000
@int 大小端, 默认spi.MSB, 可选spi.LSB
@int 主从设置, 默认主1, 可选从机0. 通常只支持主机模式
@int 工作模式, 全双工1, 半双工0, 默认全双工
@return int 成功返回0,否则返回其他值
@usage
-- 初始化spi
spi.setup(0,20,0,0,8,2000000,spi.MSB,1,1)
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
@usage
-- 初始化spi
spi.close(0)
*/
static int l_spi_close(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    lua_pushinteger(L, luat_spi_close(id));
    return 1;
}

/**
传输SPI数据
@api spi.transfer(id, send_data[, len])
@int SPI号,例如0
@string/zbuff 待发送的数据，如果为zbuff数据，则会从对象所处的指针处开始读
@int 可选。待发送数据的长度，默认为data长度
@int 可选。读取数据的长度，默认为1
@return string 读取成功返回字符串,否则返回nil
@usage
-- 初始化spi
spi.setup(0,nil,0,0,8,2000000,spi.MSB,1,1)
local recv = spi.transfer(0, "123")--发送123,并读取数据

local buff = zbuff.create(1024, 0x33) --创建一个初值全为0x33的内存区域
local recv = spi.transfer(0, buff)--把zbuff数据从指针开始，全发出去,并读取数据
*/
static int l_spi_transfer(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    size_t send_length = 0;
    const char* send_buff = NULL;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        send_buff = (const char*)(buff->addr+buff->cursor);
        send_length = buff->len - buff->cursor;
    }else{
        send_buff = lua_tolstring(L, 2, &send_length);
    }
    size_t length = luaL_optinteger(L,3,1);
    if(length <= send_length)
        send_length = length;
    size_t recv_length = luaL_optinteger(L,4,1);
    //长度为0时，直接返回空字符串
    if(send_length <= 0){
        lua_pushlstring(L,NULL,0);
        return 1;
    }
    char* recv_buff = luat_heap_malloc(recv_length);
    if(recv_buff == NULL)
        return 0;
    int ret = luat_spi_transfer(id, send_buff, send_length, recv_buff, recv_length);
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
@usage
-- 初始化spi
spi.setup(0,nil,0,0,8,2000000,spi.MSB,1,1)
local recv = spi.recv(0, 4)--接收4字节数据
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
@api spi.send(id, data[, len])
@int SPI号,例如0
@string/zbuff 待发送的数据，如果为zbuff数据，则会从对象所处的指针处开始读
@int 可选。待发送数据的长度，默认为data长度
@return int 发送结果
@usage
-- 初始化spi
spi.setup(0,nil,0,0,8,2000000,spi.MSB,1,1)
local result = spi.send(0, "123")--发送123

local buff = zbuff.create(1024, 0x33) --创建一个初值全为0x33的内存区域
local result = spi.send(0, buff)--把zbuff数据从指针开始，全发出去
*/
static int l_spi_send(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    size_t len = 0;
    const char* send_buff = NULL;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = (luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
        send_buff = (const char*)(buff->addr+buff->cursor);
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
    lua_pushinteger(L, luat_spi_send(id, send_buff, len));
    return 1;
}

/**
设置并启用SPI(对象方式)
@api spi.deviceSetup(id, cs, CPHA, CPOL, dataw, bandrate, bitdict, ms, mode)
@int SPI号,例如0
@int CS 片选脚,在w600不可用请填nil
@int CPHA 默认0,可选0/1
@int CPOL 默认0,可选0/1
@int 数据宽度,默认8bit
@int 波特率,默认20M=20000000
@int 大小端, 默认spi.MSB, 可选spi.LSB
@int 主从设置, 默认主1, 可选从机0. 通常只支持主机模式
@int 工作模式, 全双工1, 半双工0, 默认全双工
@return userdata spi_device
@usage
-- 初始化spi
local spi_device = spi.deviceSetup(0,17,0,0,8,2000000,spi.MSB,1,1)
*/
static int l_spi_device_setup(lua_State *L) {
    int bus_id = luaL_checkinteger(L, 1);
    int cs = luaL_optinteger(L, 2, 255); // 默认无
    int CPHA = luaL_optinteger(L, 3, 0); // CPHA0
    int CPOL = luaL_optinteger(L, 4, 0); // CPOL0
    int dataw = luaL_optinteger(L, 5, 8); // 8bit
    int bandrate = luaL_optinteger(L, 6, 20000000U); // 20000000U
    int bit_dict = luaL_optinteger(L, 7, 1); // MSB=1, LSB=0
    int master = luaL_optinteger(L, 8, 1); // master=1,slave=0
    int mode = luaL_optinteger(L, 9, 1); // FULL=1, half=0
    luat_spi_device_t* spi_device = lua_newuserdata(L, sizeof(luat_spi_device_t));
    if (spi_device == NULL)return 0;
    memset(spi_device, 0, sizeof(luat_spi_device_t));
    spi_device->bus_id = bus_id;
    spi_device->spi_config.cs = cs;
    spi_device->spi_config.CPHA = CPHA; 
    spi_device->spi_config.CPOL = CPOL;
    spi_device->spi_config.dataw = dataw;
    spi_device->spi_config.bandrate = bandrate; 
    spi_device->spi_config.bit_dict = bit_dict; 
    spi_device->spi_config.master = master; 
    spi_device->spi_config.mode = mode;
    luat_spi_device_setup(spi_device);
    luaL_setmetatable(L, META_SPI);
    return 1;
}

/**
关闭指定的SPI(对象方式)
@api spi_device:close()
@userdata spi_device
@return int 成功返回0,否则返回其他值
@usage
-- 初始化spi
spi_device.close()
*/
static int l_spi_device_close(lua_State *L) {
    luat_spi_device_t* spi_device = (luat_spi_device_t*)lua_touserdata(L, 1);
    int ret = luat_spi_device_close(spi_device);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/**
传输SPI数据(对象方式)
@api spi_device:transfer(send_data[, len])
@userdata spi_device
@string/zbuff 待发送的数据，如果为zbuff数据，则会从对象所处的指针处开始读
@int 可选。待发送数据的长度，默认为data长度
@int 可选。读取数据的长度，默认为1
@return string 读取成功返回字符串,否则返回nil
@usage
-- 初始化spi
local spi_device = spi.device_setup(0,17,0,0,8,2000000,spi.MSB,1,1)
local recv = spi_device:transfer("123")--发送123,并读取数据

local buff = zbuff.create(1024, 0x33) --创建一个初值全为0x33的内存区域
local recv = spi_device:transfer(buff)--把zbuff数据从指针开始，全发出去,并读取数据
*/
static int l_spi_device_transfer(lua_State *L) {
    luat_spi_device_t* spi_device = (luat_spi_device_t*)lua_touserdata(L, 1);
    size_t send_length = 0;
    const char* send_buff = NULL;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = (luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
        send_buff = (const char*)(buff->addr+buff->cursor);
        send_length = buff->len - buff->cursor;
    }else{
        send_buff = lua_tolstring(L, 2, &send_length);
    }
    size_t length = luaL_optinteger(L,3,1);
    if(length <= send_length)
        send_length = length;
    size_t recv_length = luaL_optinteger(L,4,1);
    //长度为0时，直接返回空字符串
    if(recv_length <= 0){
        lua_pushlstring(L,NULL,0);
        return 1;
    }
    char* recv_buff = luat_heap_malloc(recv_length);
    if(recv_buff == NULL)
        return 0;
    int ret = luat_spi_device_transfer(spi_device, send_buff, send_length, recv_buff, recv_length);
    if (ret > 0) {
        lua_pushlstring(L, recv_buff, ret);
        luat_heap_free(recv_buff);
        return 1;
    }
    luat_heap_free(recv_buff);
    return 0;
}

/**
发送SPI数据(对象方式)
@api spi_device:send(data[, len])
@userdata spi_device
@string/zbuff 待发送的数据，如果为zbuff数据，则会从对象所处的指针处开始读
@int 可选。待发送数据的长度，默认为data长度
@return int 发送结果
@usage
-- 初始化spi
local spi_device = spi.device_setup(0,17,0,0,8,2000000,spi.MSB,1,1)
local result = spi_device:send("123")--发送123

local buff = zbuff.create(1024, 0x33) --创建一个初值全为0x33的内存区域
local result = spi_device:send(buff)--把zbuff数据从指针开始，全发出去
*/
static int l_spi_device_send(lua_State *L) {
    luat_spi_device_t* spi_device = (luat_spi_device_t*)lua_touserdata(L, 1);
    size_t len = 0;
    const char* send_buff = NULL;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = (luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
        send_buff = (const char*)(buff->addr+buff->cursor);
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
    lua_pushinteger(L, luat_spi_device_send(spi_device, send_buff, len));
    return 1;
}

/**
接收指定长度的SPI数据(对象方式)
@api spi_device:recv(size)
@userdata spi_device
@int 数据长度
@return string 读取成功返回字符串,否则返回nil
@usage
-- 初始化spi
local spi_device = spi.device_setup(0,17,0,0,8,2000000,spi.MSB,1,1)
local recv = spi_device:recv(4)--接收4字节数据
*/
static int l_spi_device_recv(lua_State *L) {
    luat_spi_device_t* spi_device = (luat_spi_device_t*)lua_touserdata(L, 1);
    int len = luaL_checkinteger(L, 2);
    char* recv_buff = luat_heap_malloc(len);
    if(recv_buff == NULL) return 0;
    int ret = luat_spi_device_recv(spi_device, recv_buff, len);
    if (ret > 0) {
        lua_pushlstring(L, recv_buff, ret);
        luat_heap_free(recv_buff);
        return 1;
    }
    luat_heap_free(recv_buff);
    return 0;
}

int _spi_struct_newindex(lua_State *L) {
    const char* key = luaL_checkstring(L, 2);
    if (!strcmp("close", key)) {
        lua_pushcfunction(L, l_spi_device_close);
        return 1;
    }
    else if (!strcmp("transfer", key)) {
        lua_pushcfunction(L, l_spi_device_transfer);
        return 1;
    }
    else if (!strcmp("send", key)) {
        lua_pushcfunction(L, l_spi_device_send);
        return 1;
    }
    else if (!strcmp("recv", key)) {
        lua_pushcfunction(L, l_spi_device_recv);
        return 1;
    }
    return 0;
}

void luat_spi_struct_init(lua_State *L) {
    luaL_newmetatable(L, META_SPI);
    lua_pushcfunction(L, _spi_struct_newindex);
    lua_setfield( L, -2, "__index" );
    lua_pop(L, 1);
}

//------------------------------------------------------------------
#include "rotable.h"
static const rotable_Reg reg_spi[] =
{
    { "setup" ,           l_spi_setup,         0},
    { "close",            l_spi_close,         0},
    { "transfer",         l_spi_transfer,      0},
    { "recv",             l_spi_recv,          0},
    { "send",             l_spi_send,          0},
    { "deviceSetup",      l_spi_device_setup,  0},

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
    luat_spi_struct_init(L);
    return 1;
}
