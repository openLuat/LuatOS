/*
@module  spi
@summary spi操作库
@version 1.0
@date    2020.04.23
@demo spi
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_spi.h"
#include "luat_zbuff.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "spi"

#define META_SPI "SPI*"

static void spi_soft_send_byte(luat_espi_t *espi, uint8_t data)
{
    uint8_t i;
    for (i = 0; i < 8; i++)
    {
        if (data&0x80)
        {
            luat_gpio_set(espi->mosi, Luat_GPIO_HIGH);
        }
        else
        {
            luat_gpio_set(espi->mosi, Luat_GPIO_LOW);
        }
        data<<=1;
        if (espi->CPOL == 0)
        {
            luat_gpio_set(espi->clk, Luat_GPIO_HIGH);
            luat_gpio_set(espi->clk, Luat_GPIO_LOW);
        }
        else
        {
            luat_gpio_set(espi->clk, Luat_GPIO_LOW);
            luat_gpio_set(espi->clk, Luat_GPIO_HIGH);
        }
    }
}

static char spi_soft_recv_byte(luat_espi_t *espi)
{
    unsigned char i = 8;
    unsigned char data = 0;
    while (i--)
    {
        data <<= 1;
        if (luat_gpio_get(espi->miso))
        {
            data |= 0x01;
        }
        if (espi->CPOL == 0)
        {
            luat_gpio_set(espi->clk, Luat_GPIO_HIGH);
            luat_gpio_set(espi->clk, Luat_GPIO_LOW);
        }else{
            luat_gpio_set(espi->clk, Luat_GPIO_LOW);
            luat_gpio_set(espi->clk, Luat_GPIO_HIGH);
        }
    }
    return data;
}

static int spi_soft_send(luat_espi_t *espi, const char*data, size_t len)
{
    size_t i = 0;
    if (espi->cs != -1)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_LOW);
    }
    for (i = 0; i < len; i++)
    {
        spi_soft_send_byte(espi, data[i]);
    }
    if (espi->cs != -1)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_HIGH);
    }
    return 0;
}


static int spi_soft_recv(luat_espi_t *espi, char *buff, size_t len)
{
    size_t i = 0;
    if (espi->cs != -1)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_LOW);
    }
    luat_gpio_set(espi->mosi, Luat_GPIO_LOW);
    for (i = 0; i < len; i++)
    {
        *buff++ = spi_soft_recv_byte(espi);
    }
    if (espi->cs != -1)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_HIGH);
    }
    luat_gpio_set(espi->mosi, Luat_GPIO_HIGH);
    return 0;
}

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
设置并启用软件SPI
@api spi.createSoft(cs, mosi, miso, clk, CPHA, CPOL, dataw, bitdict, ms, mode)
@int cs引脚编号，传入nil意为Lua控制cs脚
@int mosi引脚编号
@int miso引脚编号
@int clk引脚编号
@int 默认0，可选0/1
@int 默认0，可选0/1
@int 数据宽度，默认8bit
@int 大小端，默认spi.MSB, 可选spi.LSB
@int 主从设置，默认主1, 可选从机0. 通常只支持主机模式
@int 工作模式，全双工1，半双工0，默认全双工
@return 软件SPI对象 可当作SPI的id使用
@usage
-- 初始化软件spi
local softSpiDevice = spi.createSoft(0, 1, 2, 3, 0, 0, 8, spi.MSB, 1, 1)
local result = spi.send(softSpiDevice, string.char(0x9f))
*/
static int l_spi_soft(lua_State *L) {
    luat_espi_t *espi = (luat_espi_t *)lua_newuserdata(L, sizeof(luat_espi_t));
    espi->cs = luaL_optinteger(L, 1, -1);
    espi->mosi = luaL_checkinteger(L, 2);
    espi->miso = luaL_checkinteger(L, 3);
    espi->clk = luaL_checkinteger(L, 4);
    espi->CPHA = luaL_optinteger(L, 5, 0);
    espi->CPOL = luaL_optinteger(L, 6, 0);
    espi->dataw = luaL_optinteger(L, 7, 8);
    espi->bit_dict = luaL_optinteger(L, 8, 1);
    espi->master = luaL_optinteger(L, 9, 1);
    espi->mode = luaL_optinteger(L, 10, 1);
    luat_gpio_mode(espi->cs, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 1);
    luat_gpio_mode(espi->mosi, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 1);
    luat_gpio_mode(espi->miso, Luat_GPIO_INPUT, Luat_GPIO_PULLDOWN, 0);
    if (espi->CPOL == 0)
    {
        luat_gpio_mode(espi->clk, Luat_GPIO_OUTPUT, Luat_GPIO_PULLDOWN, 0);
    }
    else if (espi->CPOL == 1)
    {
        luat_gpio_mode(espi->clk, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 1);
    }
    luaL_setmetatable(L, LUAT_ESPI_TYPE);
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
    if (lua_isinteger(L, 1))
    {
        int id = luaL_checkinteger(L, 1);
        lua_pushinteger(L, luat_spi_close(id));
    }
    else if (lua_isuserdata(L, 1))
    {
        luat_spi_device_t *spi_device = (luat_spi_device_t *)luaL_testudata(L, 1, META_SPI);
        if (spi_device){
            int ret = luat_spi_device_close(spi_device);
            lua_pushboolean(L, ret == 0 ? 1 : 0);
        }
        luat_espi_t *espi = (luat_espi_t *)luaL_testudata(L, 1, LUAT_ESPI_TYPE);
        if (espi){
            luat_espi_t *espi = (luat_espi_t*)lua_touserdata(L, 1);
            lua_pushinteger(L, 0);
        }
    }
    return 1;
}

/**
传输SPI数据
@api spi.transfer(id, send_data[, len])
@int SPI号(例如0)或软件SPI对象
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
    size_t send_length = 0;
    const char* send_buff = NULL;
    char* recv_buff = NULL;
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
    if(send_length == 0){
        lua_pushlstring(L, "",0);
        return 1;
    }
    if (recv_length > 0) {
        recv_buff = luat_heap_malloc(recv_length);
        if(recv_buff == NULL)
            return 0;
    }
    if (lua_isinteger(L, 1))
    {
        int id = luaL_checkinteger(L, 1);
        int ret = luat_spi_transfer(id, send_buff, send_length, recv_buff, recv_length);
        if (ret > 0) {
            lua_pushlstring(L, recv_buff, ret);
            luat_heap_free(recv_buff);
            return 1;
        }
    }
    else
    {
        luat_espi_t *espi = toespi(L);
        int csPin = -1;
        if (espi->cs!=-1)
        {
            csPin = espi->cs;
            espi->cs = -1;
            luat_gpio_set(csPin, Luat_GPIO_LOW);
        }
        spi_soft_send(espi, send_buff, send_length);
        spi_soft_recv(espi, recv_buff, recv_length);
        if (csPin!=-1)
        {
            luat_gpio_set(csPin, Luat_GPIO_HIGH);
            espi->cs = csPin;
        }
        lua_pushlstring(L, recv_buff, recv_length);
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
    int len = luaL_optinteger(L, 2, 1);
    char* recv_buff = luat_heap_malloc(len);
    if(recv_buff == NULL)return 0;
    if (lua_isinteger(L, 1))
    {
        int id = luaL_checkinteger(L, 1);
        int ret = luat_spi_recv(id, recv_buff, len);
        if (ret > 0) {
            lua_pushlstring(L, recv_buff, ret);
            luat_heap_free(recv_buff);
            return 1;
        }
        else
        {
            luat_heap_free(recv_buff);
            return 0;
        }
    }
    else if (lua_isuserdata(L, 1))
    {
        luat_spi_device_t *spi_device = (luat_spi_device_t *)luaL_testudata(L, 1, META_SPI);
        if (spi_device){
            luat_spi_device_recv(spi_device, recv_buff, len);
        }
        luat_espi_t *espi = (luat_espi_t *)luaL_testudata(L, 1, LUAT_ESPI_TYPE);
        if (espi){
            spi_soft_recv(espi, recv_buff, len);
        }
        lua_pushlstring(L, recv_buff, len);
        luat_heap_free(recv_buff);
        return 1;
    }
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
    size_t len = 0;
    const char* send_buff = NULL;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = (luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
        send_buff = (const char*)(buff->addr+buff->cursor);
        len = buff->len - buff->cursor;
    }
    else{
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
    if (lua_isinteger(L, 1))
    {
        int id = luaL_checkinteger(L, 1);
        lua_pushinteger(L, luat_spi_send(id, send_buff, len));
    }
    else
    {
        luat_espi_t *espi = toespi(L);
        lua_pushinteger(L, spi_soft_send(espi, send_buff, len));
    }
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
    char* recv_buff = NULL;

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
    if(recv_length == 0){
        lua_pushlstring(L,NULL,0);
        return 1;
    }
    if (recv_length > 0) {
        recv_buff = luat_heap_malloc(recv_length);
        if(recv_buff == NULL)
            return 0;
    }
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
    char* send_buff = NULL;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = (luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
        send_buff = (char*)(buff->addr+buff->cursor);
        len = buff->len - buff->cursor;
        lua_pushinteger(L, luat_spi_device_send(spi_device, send_buff, len));
    }else if (lua_istable(L, 2)){
        len = lua_rawlen(L, 2); //返回数组的长度
        send_buff = (char*)luat_heap_malloc(len);
        for (size_t i = 0; i < len; i++){
            lua_rawgeti(L, 2, 1 + i);
            send_buff[i] = (char)lua_tointeger(L, -1);
            lua_pop(L, 1); //将刚刚获取的元素值从栈中弹出
        }
        
    }else {
        send_buff = (char*)lua_tolstring(L, 2, &len);
        lua_pushinteger(L, luat_spi_device_send(spi_device, send_buff, len));
    }
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
    int len = luaL_optinteger(L, 2,1);
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

void luat_soft_spi_struct_init(lua_State *L) {
    luaL_newmetatable(L, LUAT_ESPI_TYPE);
    lua_pop(L, 1);
}

//------------------------------------------------------------------
#include "rotable2.h"
static const rotable_Reg_t reg_spi[] =
{
    { "setup" ,           ROREG_FUNC(l_spi_setup)},
    { "createSoft",       ROREG_FUNC(l_spi_soft) },
    { "close",            ROREG_FUNC(l_spi_close)},
    { "transfer",         ROREG_FUNC(l_spi_transfer)},
    { "recv",             ROREG_FUNC(l_spi_recv)},
    { "send",             ROREG_FUNC(l_spi_send)},
    { "deviceSetup",      ROREG_FUNC(l_spi_device_setup)},
    { "deviceTransfer",   ROREG_FUNC(l_spi_device_transfer)},
    { "deviceSend",       ROREG_FUNC(l_spi_device_send)},
    
    { "MSB",               ROREG_INT(1)},
    { "LSB",               ROREG_INT(0)},
    { "master",            ROREG_INT(1)},
    { "slave",             ROREG_INT(0)},
    { "full",              ROREG_INT(1)},
    { "half",              ROREG_INT(0)},

    { "SPI_0",             ROREG_INT(0)},
    { "SPI_1",             ROREG_INT(1)},
    { "SPI_2",             ROREG_INT(2)},
    { "SPI_3",             ROREG_INT(3)},
    { "SPI_4",             ROREG_INT(4)},
	{ "HSPI_0",             ROREG_INT(5)},
	{ NULL,                ROREG_INT(0) }
};

LUAMOD_API int luaopen_spi( lua_State *L ) {
    luat_newlib2(L, reg_spi);
    luat_spi_struct_init(L);
    luat_soft_spi_struct_init(L);
    return 1;
}
