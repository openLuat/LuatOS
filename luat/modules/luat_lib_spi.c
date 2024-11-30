/*
@module  spi
@summary spi操作库
@version 1.0
@date    2020.04.23
@demo spi
@video https://www.bilibili.com/video/BV1VY411M7YH
@tag LUAT_USE_SPI
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_mem.h"
#include "luat_spi.h"
#include "luat_zbuff.h"
#include "luat_gpio.h"
#include "luat_irq.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "spi"

#define META_SPI "SPI*"

#define LUAT_ESPI_TYPE "ESPI*"
#define toespi(L) ((luat_espi_t *)luaL_checkudata(L, 1, LUAT_ESPI_TYPE))

// 软件spi
typedef struct luat_espi {
    uint8_t cs;
    uint8_t mosi;
    uint8_t miso;
    uint32_t clk;
    uint8_t CPHA;
    uint8_t CPOL;
    uint8_t dataw;
    uint8_t bit_dict;
    uint8_t master;
    uint8_t mode;
} luat_espi_t;

// 软SPI 发送一个字节
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

// 软SPI 接收一个字节
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

// 软SPI 收发一个字节
static char spi_soft_xfer_byte(luat_espi_t *espi, uint8_t send_data)
{
    unsigned char i = 8;
    unsigned char data = 0;
    while (i--)
    {
        // 发送
        if (send_data&0x80)
        {
            luat_gpio_set(espi->mosi, Luat_GPIO_HIGH);
        }
        else
        {
            luat_gpio_set(espi->mosi, Luat_GPIO_LOW);
        }
        send_data<<=1;
        // 接收
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

int luat_spi_soft_send(luat_espi_t *espi, const char*data, size_t len)
{
    size_t i = 0;
    if (espi->cs != Luat_GPIO_MAX_ID)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_LOW);
    }
    for (i = 0; i < len; i++)
    {
        spi_soft_send_byte(espi, data[i]);
    }
    if (espi->cs != Luat_GPIO_MAX_ID)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_HIGH);
    }
    return 0;
}


int luat_spi_soft_recv(luat_espi_t *espi, char *buff, size_t len)
{
    size_t i = 0;
    if (espi->cs != Luat_GPIO_MAX_ID)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_LOW);
    }
    luat_gpio_set(espi->mosi, Luat_GPIO_LOW);
    for (i = 0; i < len; i++)
    {
        *buff++ = spi_soft_recv_byte(espi);
    }
    if (espi->cs != Luat_GPIO_MAX_ID)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_HIGH);
    }
    luat_gpio_set(espi->mosi, Luat_GPIO_HIGH);
    return 0;
}

int luat_spi_soft_xfer(luat_espi_t *espi, const char *send_buff, char* recv_buff, size_t len)
{
    size_t i = 0;
    if (espi->cs != Luat_GPIO_MAX_ID)
    {
        luat_gpio_set(espi->cs, Luat_GPIO_LOW);
    }
    luat_gpio_set(espi->mosi, Luat_GPIO_LOW);
    for (i = 0; i < len; i++)
    {
        *recv_buff++ = spi_soft_xfer_byte(espi, (uint8_t)send_buff[i]);
    }
    if (espi->cs != Luat_GPIO_MAX_ID)
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
    spi_config.cs = luaL_optinteger(L, 2, Luat_GPIO_MAX_ID); // 默认无
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
@int 工作模式，全双工1，半双工0，默认半双工
@return 软件SPI对象 可当作SPI的id使用
@usage
-- 初始化软件spi
local softSpiDevice = spi.createSoft(0, 1, 2, 3, 0, 0, 8, spi.MSB, 1, 1)
local result = spi.send(softSpiDevice, string.char(0x9f))
*/
static int l_spi_soft(lua_State *L) {
    luat_espi_t *espi = (luat_espi_t *)lua_newuserdata(L, sizeof(luat_espi_t));
    espi->cs = luaL_optinteger(L, 1, Luat_GPIO_MAX_ID);
    espi->mosi = luaL_checkinteger(L, 2);
    espi->miso = luaL_checkinteger(L, 3);
    espi->clk = luaL_checkinteger(L, 4);
    espi->CPHA = luaL_optinteger(L, 5, 0);
    espi->CPOL = luaL_optinteger(L, 6, 0);
    espi->dataw = luaL_optinteger(L, 7, 8);
    espi->bit_dict = luaL_optinteger(L, 8, 1);
    espi->master = luaL_optinteger(L, 9, 1);
    espi->mode = luaL_optinteger(L, 10, 0);
    luat_gpio_mode(espi->cs, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
    luat_gpio_mode(espi->mosi, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
    luat_gpio_mode(espi->miso, Luat_GPIO_INPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    if (espi->CPOL == 0)
    {
        luat_gpio_mode(espi->clk, Luat_GPIO_OUTPUT, Luat_GPIO_PULLDOWN, Luat_GPIO_LOW);
    }
    else if (espi->CPOL == 1)
    {
        luat_gpio_mode(espi->clk, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
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
            lua_pushinteger(L, ret);
        }
        else {
            lua_pushinteger(L, 0);
        }
    }
    else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/**
传输SPI数据
@api spi.transfer(id, send_data, send_len, recv_len)
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
        send_buff = luaL_checklstring(L, 2, &send_length);
    }
    size_t length = luaL_optinteger(L,3,send_length);
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
        // 软SPI
        luat_espi_t *espi = toespi(L);
        uint8_t csPin = Luat_GPIO_MAX_ID;
        if (espi->cs != Luat_GPIO_MAX_ID)
        {
            csPin = espi->cs;
            espi->cs = Luat_GPIO_MAX_ID;
            luat_gpio_set(csPin, Luat_GPIO_LOW);
        }
        // 半双工, 先发后读
        if (espi->mode == 0 || (send_length != recv_length)) {
            luat_spi_soft_send(espi, send_buff, send_length);
            luat_spi_soft_recv(espi, recv_buff, recv_length);
        }
        // 全双工, 边发边读, 当且仅当收发都是一样长度时,才是全双工
        else {
            luat_spi_soft_xfer(espi, send_buff, recv_buff, send_length);
        }
        if (csPin!= Luat_GPIO_MAX_ID)
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
@api spi.recv(id, size, buff)
@int SPI号,例如0
@int 数据长度
@userdata zbuff对象,可选,2024.3.29新增
@return string/int 读取成功返回字符串,若传入的是zbuff就返回读取大小,出错返回nil
@usage
-- 初始化spi
spi.setup(0,nil,0,0,8,2000000,spi.MSB,1,1)
-- 接收数据
local recv = spi.recv(0, 4)--接收4字节数据

-- 当传入zbuff参数时,返回值有所不同. 2024.3.29新增
-- 读取成功后, 指针会往后移动len个字节
-- 写入位置以当前used()位置开始, 请务必确保有足够空间写入len长度的数据
local len = spi.recv(0, 4, buff)
*/
static int l_spi_recv(lua_State *L) {
    luat_zbuff_t* buff = NULL;
    char* recv_buff = NULL;
    luaL_Buffer b = {0};
    int ret = 0;
    int len = luaL_optinteger(L, 2, 1);
    if (len <= 0) {
        return 0;
    }
    if (lua_isuserdata(L, 3)) {
        buff = (luat_zbuff_t*)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE);
        recv_buff = (char*)buff->addr + buff->used;
        if (buff->len - buff->used < len) {
            LLOGW("zbuff放不下 %d %d %d", buff->len - buff->used, len);
            return 0;
        }
    }
    else {
        luaL_buffinitsize(L, &b, len);
        recv_buff = b.b;
    }
    if(recv_buff == NULL) {
        LLOGW("out of memory when malloc spi buff %d", len);
        return 0;
    }
    
    if (lua_isinteger(L, 1))
    {
        int id = luaL_checkinteger(L, 1);
        ret = luat_spi_recv(id, recv_buff, len);
        b.n = ret;
    }
    else if (lua_isuserdata(L, 1))
    {
        luat_spi_device_t *spi_device = (luat_spi_device_t *)luaL_testudata(L, 1, META_SPI);
        if (spi_device){
            luat_spi_device_recv(spi_device, recv_buff, len);
            ret = len;
        }
        else {
            luat_espi_t *espi = (luat_espi_t *)luaL_testudata(L, 1, LUAT_ESPI_TYPE);
            if (espi){
                luat_spi_soft_recv(espi, recv_buff, len);
                ret = len;
            }
        }
    }
    if (ret <= 0) {
        return 0;
    }
    
    if (buff == NULL) {
        luaL_pushresult(&b);
    }
    else {
        buff->used += len;
        lua_pushinteger(L, len);
    }
    return 1;
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
        send_buff = luaL_checklstring(L, 2, &len);
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
        lua_pushinteger(L, luat_spi_soft_send(espi, send_buff, len));
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
local result = spi_device:transfer({0x00,0x01})--发送0x00,0x01,并读取数据

local buff = zbuff.create(1024, 0x33) --创建一个初值全为0x33的内存区域
local recv = spi_device:transfer(buff)--把zbuff数据从指针开始，全发出去,并读取数据
*/
static int l_spi_device_transfer(lua_State *L) {
    luat_spi_device_t* spi_device = (luat_spi_device_t*)lua_touserdata(L, 1);
    size_t send_length = 0;
    char* send_buff = NULL;
    char* recv_buff = NULL;
    uint8_t send_mode = 0;
    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
        luat_zbuff_t *buff = (luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
        send_buff = (char*)(buff->addr+buff->cursor);
        send_length = buff->len - buff->cursor;
    }else if (lua_istable(L, 2)){
        send_mode = LUA_TTABLE;
        send_length = lua_rawlen(L, 2); //返回数组的长度
        send_buff = (char*)luat_heap_malloc(send_length);
        for (size_t i = 0; i < send_length; i++){
            lua_rawgeti(L, 2, 1 + i);
            send_buff[i] = (char)lua_tointeger(L, -1);
            lua_pop(L, 1); //将刚刚获取的元素值从栈中弹出
        }
    }else if(lua_isstring(L, 2)){
        send_buff = (char*)luaL_checklstring(L, 2, &send_length);
    }else{
        LLOGE("spi_device transfer first arg error");
        return 0;
    }
    if (lua_isinteger(L, 3)){
        send_length = (size_t)lua_tointeger(L, 3);
    }
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
    if (send_mode == LUA_TTABLE){
        luat_heap_free(send_buff);
    }
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
local result = spi_device:send({0x00,0x01})--发送0x00,0x01

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
        lua_pushinteger(L, luat_spi_device_send(spi_device, send_buff, len));
        luat_heap_free(send_buff);
    }else if(lua_isstring(L, 2)){
        send_buff = (char*)luaL_checklstring(L, 2, &len);
        lua_pushinteger(L, luat_spi_device_send(spi_device, send_buff, len));
    }else{
        LLOGE("spi_device transfer first arg error");
        return 0;
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

static int _spi_struct_gc(lua_State *L) {
    luat_spi_device_t* spi_device = (luat_spi_device_t*)lua_touserdata(L, 1);
    LLOGI("spi_device对象正在被回收,相关内存将释放 %p , spi id=%d", spi_device, spi_device->bus_id);
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
    lua_pushcfunction(L, _spi_struct_gc);
    lua_setfield( L, -2, "__gc" );
    lua_pushcfunction(L, _spi_struct_newindex);
    lua_setfield( L, -2, "__index" );
    lua_pop(L, 1);
}

void luat_soft_spi_struct_init(lua_State *L) {
    luaL_newmetatable(L, LUAT_ESPI_TYPE);
    lua_pop(L, 1);
}


int LUAT_WEAK luat_spi_no_block_transfer(int id, uint8_t *tx_buff, uint8_t *rx_buff, size_t len, void *CB, void *pParam)
{
    return -1;
}

/**
非阻塞方式硬件SPI传输SPI数据，目的为了提高核心利用率。API直接返回是否启动传输，传输完成后通过topic回调，本API适合硬件SPI传输大量数据传输，外设功能（LCD SPI，W5500 SPI之类的）占据的SPI和软件SPI不能用，少量数据传输建议使用传统阻塞型API
@api spi.xfer(id, txbuff, rxbuff, rx_len, transfer_done_topic)
@userdata or int spi_device或者spi_id，注意，如果是spi_device，需要手动在传输完成后拉高cs!!!!!!
@zbuff 待发送的数据，如果为nil，则只接收数据，由于用的非阻塞模型，为保证动态数据的有效性，只能使用zbuff，发送的数据从zbuff.addr
@zbuff 接收数据，如果为nil，则只发送数据，由于用的非阻塞模型，为保证动态数据的有效性，只能使用zbuff，接收的数据从zbuff.addr开始存储
@int 传输数据长度，特别说明 如果为半双工，先发后收，比如spi flash操作这种，则长度=发送字节+接收字节，注意上面发送和接收buff都要留足够的数据，后续接收数据处理需要跳过发送数据长度字节
@string 传输完成后回调的topic
@return boolean true/false 本次传输是否正确启动，true，启动，false，有错误无法启动。传输完成会发布消息transfer_done_topic和boolean型结果
@usage
local result = spi.xfer(spi.SPI_0, txbuff, rxbuff, 1024, "SPIDONE") if result then result, spi_id, succ, error_code = sys.waitUntil("SPIDONE") end if not result or not succ then log.info("spi fail, error code", error_code) else log.info("spi ok") end

*/
static int l_spi_no_block_transfer(lua_State *L)
{
	size_t topic_len = 0;
	const char *topic = luaL_checklstring(L, 5, &topic_len);
	size_t len = luaL_optinteger(L, 4, 0);

	int result = -1;
	uint8_t *tx_buff = NULL;
	uint8_t *rx_buff = NULL;
	luat_zbuff_t *txbuff = ((luat_zbuff_t *)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE));
	luat_zbuff_t *rxbuff = ((luat_zbuff_t *)luaL_testudata(L, 3, LUAT_ZBUFF_TYPE));
	if ((!txbuff && !rxbuff) || !len) {
		lua_pushboolean(L, 0);
		return 1;
	}
	if (txbuff) tx_buff = txbuff->addr;
	if (rxbuff) rx_buff = rxbuff->addr;

	char *cb_topic = luat_heap_malloc(topic_len + 1);
	memcpy(cb_topic, topic, topic_len);
	cb_topic[topic_len] = 0;

    if (lua_isinteger(L, 1)) {
        int id = luaL_checkinteger(L, 1);
        result = luat_spi_no_block_transfer(id, tx_buff, rx_buff, len, luat_irq_hardware_cb_handler, cb_topic);
    }
    else {
    	luat_spi_device_t* spi_dev = (luat_spi_device_t*)lua_touserdata(L, 1);
    	luat_spi_device_config(spi_dev);
    	luat_gpio_set(spi_dev->spi_config.cs, 0);
    	result = luat_spi_no_block_transfer(spi_dev->bus_id, tx_buff, rx_buff, len, luat_irq_hardware_cb_handler, cb_topic);
    }
    if (result) {
    	luat_heap_free(cb_topic);
    }
	lua_pushboolean(L, !result);
	return 1;
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
	{ "xfer",   		  ROREG_FUNC(l_spi_no_block_transfer)},

    //@const MSB number 大端模式
    { "MSB",               ROREG_INT(1)},
    //@const LSB number 小端模式
    { "LSB",               ROREG_INT(0)},
    //@const master number 主机模式
    { "master",            ROREG_INT(1)},
    //@const slave number 从机模式
    { "slave",             ROREG_INT(0)},
    //@const full number 全双工
    { "full",              ROREG_INT(1)},
    //@const half number 半双工
    { "half",              ROREG_INT(0)},
	//@const SPI_0 number SPI0
    { "SPI_0",             ROREG_INT(0)},
	//@const SPI_1 number SPI1
    { "SPI_1",             ROREG_INT(1)},
	//@const SPI_2 number SPI2
    { "SPI_2",             ROREG_INT(2)},
	//@const SPI_3 number SPI3
    { "SPI_3",             ROREG_INT(3)},
	//@const SPI_4 number SPI4
    { "SPI_4",             ROREG_INT(4)},
	//@const HSPI_0 number 高速SPI0，目前105专用
	{ "HSPI_0",             ROREG_INT(5)},
	{ NULL,                ROREG_INT(0) }
};

LUAMOD_API int luaopen_spi( lua_State *L ) {
    luat_newlib2(L, reg_spi);
    luat_spi_struct_init(L);
    luat_soft_spi_struct_init(L);
    return 1;
}
