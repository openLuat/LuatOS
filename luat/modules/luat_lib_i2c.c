
/*
@module  i2c
@summary I2C操作
@version 1.0
@date    2020.03.30
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_i2c.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "i2c"
#include "luat_log.h"

static void i2c_soft_start(luat_ei2c *ei2c)
{
    luat_gpio_mode(ei2c->sda, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 1);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->scl, Luat_GPIO_HIGH);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->sda, Luat_GPIO_LOW);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
    luat_timer_us_delay(5);
}
static void i2c_soft_stop(luat_ei2c *ei2c)
{
    luat_gpio_mode(ei2c->sda, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 1);
    luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->sda, Luat_GPIO_LOW);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->scl, Luat_GPIO_HIGH);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->sda, Luat_GPIO_HIGH);
    luat_timer_us_delay(5);
}
static unsigned char i2c_soft_wait_ack(luat_ei2c *ei2c)
{
    luat_gpio_set(ei2c->sda, Luat_GPIO_HIGH);
    luat_gpio_mode(ei2c->sda, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, 1);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->scl, Luat_GPIO_HIGH);
    luat_timer_us_delay(15);
    int max_wait_time = 3000;
    while (max_wait_time--)
    {
        if (luat_gpio_get(ei2c->sda) == Luat_GPIO_LOW)
        {
            luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
            return 1;
        }
        luat_timer_us_delay(1);
    }
    i2c_soft_stop(ei2c);
    return 0;
}
static void i2c_soft_send_ack(luat_ei2c *ei2c)
{
    luat_gpio_mode(ei2c->sda, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->scl, Luat_GPIO_HIGH);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
}
static void i2c_soft_send_noack(luat_ei2c *ei2c)
{
    luat_gpio_mode(ei2c->sda, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 1);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->scl, Luat_GPIO_HIGH);
    luat_timer_us_delay(5);
    luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
}
static void i2c_soft_send_byte(luat_ei2c *ei2c, unsigned char data)
{
    unsigned char i = 8;
    luat_gpio_mode(ei2c->sda, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0);
    while (i--)
    {
        luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
        luat_timer_us_delay(10);
        if (data & 0x80)
        {
            luat_gpio_set(ei2c->sda, Luat_GPIO_HIGH);
        }
        else
        {
            luat_gpio_set(ei2c->sda, Luat_GPIO_LOW);
        }
        luat_timer_us_delay(5);
        data <<= 1;
        luat_gpio_set(ei2c->scl, Luat_GPIO_HIGH);
        luat_timer_us_delay(5);
        luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
        luat_timer_us_delay(5);
    }
}
static char i2c_soft_recv_byte(luat_ei2c *ei2c)
{
    unsigned char i = 8;
    unsigned char data = 0;
    luat_gpio_set(ei2c->sda, Luat_GPIO_HIGH);
    luat_gpio_mode(ei2c->sda, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, 1);
    while (i--)
    {
        data <<= 1;
        luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
        luat_timer_us_delay(5);
        luat_gpio_set(ei2c->scl, Luat_GPIO_HIGH);
        luat_timer_us_delay(5);
        if (luat_gpio_get(ei2c->sda))
            data |= 0x01;
    }
    luat_gpio_set(ei2c->scl, Luat_GPIO_LOW);
    return (data);
}
static char i2c_soft_recv(luat_ei2c *ei2c, unsigned char addr, char *buff, size_t len)
{
    size_t i;
    i2c_soft_start(ei2c);
    i2c_soft_send_byte(ei2c, (addr << 1) + 1);
    if (!i2c_soft_wait_ack(ei2c))
    {
        i2c_soft_stop(ei2c);
        return -1;
    }
    luat_timer_us_delay(2000);
    for (i = 0; i < len; i++)
    {
        *buff++ = i2c_soft_recv_byte(ei2c);
        if (i < (len - 1))
            i2c_soft_send_ack(ei2c);
    }
    i2c_soft_send_noack(ei2c);
    i2c_soft_stop(ei2c);
    return 0;
}
static char i2c_soft_send(luat_ei2c *ei2c, unsigned char addr, char *data, size_t len)
{
    size_t i;
    i2c_soft_start(ei2c);
    i2c_soft_send_byte(ei2c, addr << 1);
    if (!i2c_soft_wait_ack(ei2c))
    {
        i2c_soft_stop(ei2c);
        return -1;
    }
    for (i = 0; i < len; i++)
    {
        i2c_soft_send_byte(ei2c, data[i]);
        if (!i2c_soft_wait_ack(ei2c))
        {
            i2c_soft_stop(ei2c);
            return -1;
        }
    }
    i2c_soft_stop(ei2c);
    return 0;
}

/*
i2c编号是否存在
@api i2c.exist(id)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@return int 存在就返回1,否则返回0
@usage
-- 检查i2c1是否存在
if i2c.exist(1) then
    log.info("存在 i2c1")
end
*/
static int l_i2c_exist(lua_State *L)
{
    int re = luat_i2c_exist(luaL_checkinteger(L, 1));
    lua_pushinteger(L, re);
    return 1;
}

/*
i2c初始化
@api i2c.setup(id, speed, slaveAddr)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int I2C速度, 例如i2c.FAST
@int 从设备地址（7位）, 例如0x38
@return int 成功就返回1,否则返回0
@usage
-- 初始化i2c1
if i2c.setup(1, i2c.FAST, 0x38) == 1 then
    log.info("存在 i2c1")
else
    i2c.close(1) -- 关掉
end
*/
static int l_i2c_setup(lua_State *L)
{
    int re = luat_i2c_setup(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 0), luaL_optinteger(L, 3, 0));
    lua_pushinteger(L, re == 0 ? luaL_optinteger(L, 2, 0) : -1);
    return 1;
}

/*
新建一个软件i2c对象
@api i2c.createSoft(scl,sda,slaveAddr)
@int i2c SCL引脚编号
@int i2c SDA引脚编号
@int 从设备地址（7位）, 例如0x38
@return 软件I2C对象 可当作i2c的id使用
@usage
-- 注意！这个接口是软件模拟i2c，速度可能会比硬件的慢
-- 不需要调用i2c.close接口
-- 初始化软件i2c
local softI2C = i2c.createSoft(1,2,0x38)
i2c.send(softI2C, 0x5C, string.char(0x0F, 0x2F))
*/
static int l_i2c_soft(lua_State *L)
{
    luat_ei2c *ei2c = (luat_ei2c *)lua_newuserdata(L, sizeof(luat_ei2c));
    ei2c->scl = luaL_checkinteger(L, 1);
    ei2c->sda = luaL_checkinteger(L, 2);
    ei2c->addr = luaL_checkinteger(L, 3);
    luat_gpio_mode(ei2c->scl, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 1);
    luat_gpio_mode(ei2c->sda, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 1);
    i2c_soft_stop(ei2c);
    luaL_setmetatable(L, LUAT_EI2C_TYPE);
    return 1;
}

/*
i2c发送数据
@api i2c.send(id, addr, data)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int I2C子设备的地址, 7位地址
@integer/string/table 待发送的数据,自适应参数类型
@return true/false 发送是否成功
@usage
-- 往i2c0发送1个字节的数据
i2c.send(0, 0x68, 0x75)
-- 往i2c1发送2个字节的数据
i2c.send(1, 0x5C, string.char(0x0F, 0x2F))
i2c.send(1, 0x5C, {0x0F, 0x2F})
*/
static int l_i2c_send(lua_State *L)
{
    int id = 0;
    if (!lua_isuserdata(L, 1))
    {
        id = luaL_checkinteger(L, 1);
    }
    int addr = luaL_checkinteger(L, 2);
    size_t len = 0;
    int result = 0;

    if (lua_isinteger(L, 3))
    {
        len = lua_gettop(L) - 2;
        char *buff = (char *)luat_heap_malloc(len);
        for (size_t i = 0; i < len; i++)
        {
            buff[i] = (char)lua_tointeger(L, 3 + i);
        }
        if (lua_isuserdata(L, 1))
        {
            luat_ei2c *ei2c = toei2c(L);
            result = i2c_soft_send(ei2c, addr, buff, len);
        }
        else
        {
            result = luat_i2c_send(id, addr, buff, len);
        }
        luat_heap_free(buff);
    }
    else if (lua_isstring(L, 3))
    {
        const char *buff = luaL_checklstring(L, 3, &len);
        if (lua_isuserdata(L, 1))
        {
            luat_ei2c *ei2c = toei2c(L);
            result = i2c_soft_send(ei2c, addr, (char *)buff, len);
        }
        else
        {
            result = luat_i2c_send(id, addr, (char *)buff, len);
        }
    }
    else if (lua_istable(L, 3))
    {
        const int len = lua_rawlen(L, 3); //返回数组的长度
        char *buff = (char *)luat_heap_malloc(len);

        for (size_t i = 0; i < len; i++)
        {
            lua_rawgeti(L, 3, 1 + i);
            buff[i] = (char)lua_tointeger(L, -1);
            lua_pop(L, 1); //将刚刚获取的元素值从栈中弹出
        }
        if (lua_isuserdata(L, 1))
        {
            luat_ei2c *ei2c = toei2c(L);
            result = i2c_soft_send(ei2c, addr, buff, len);
        }
        else
        {
            result = luat_i2c_send(id, addr, buff, len);
        }
        luat_heap_free(buff);
    }

    lua_pushboolean(L, result == 0);
    return 1;
}

/*
i2c接收数据
@api i2c.recv(id, addr, len)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int I2C子设备的地址, 7位地址
@int 接收数据的长度
@return string 收到的数据
@usage
-- 从i2c1读取2个字节的数据
local data = i2c.recv(1, 0x5C, 2)
*/
static int l_i2c_recv(lua_State *L)
{
    int id = 0;
    if (!lua_isuserdata(L, 1))
    {
        id = luaL_checkinteger(L, 1);
    }
    int addr = luaL_checkinteger(L, 2);
    int len = luaL_checkinteger(L, 3);
    char *buff = (char *)luat_heap_malloc(len);
    int result;
    if (lua_isuserdata(L, 1))
    {
        luat_ei2c *ei2c = toei2c(L);
        result = i2c_soft_recv(ei2c, addr, buff, len);
    }
    else
    {
        result = luat_i2c_recv(id, addr, buff, len);
    }
    if (result != 0)
    { //如果返回值不为0，说明收失败了
        len = 0;
        LLOGD("i2c receive result %d", result);
    }
    lua_pushlstring(L, buff, len);
    luat_heap_free(buff);
    return 1;
}

/*
i2c写寄存器数据
@api i2c.writeReg(id, addr, reg, data)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int I2C子设备的地址, 7位地址
@int 寄存器地址
@string 待发送的数据
@return true/false 发送是否成功
@usage
-- 从i2c1的地址为0x5C的设备的寄存器0x01写入2个字节的数据
i2c.writeReg(1, 0x5C, 0x01, string.char(0x00, 0xF2))
*/
static int l_i2c_write_reg(lua_State *L)
{
    int id = 0;
    if (!lua_isuserdata(L, 1))
    {
        id = luaL_checkinteger(L, 1);
    }
    int addr = luaL_checkinteger(L, 2);
    int reg = luaL_checkinteger(L, 3);
    size_t len;
    const char *lb = luaL_checklstring(L, 4, &len);
    char *buff = (char *)luat_heap_malloc(sizeof(char) * len + 1);
    *buff = (char)reg;
    memcpy(buff + 1, lb, sizeof(char) + len + 1);
    int result;
    if (lua_isuserdata(L, 1))
    {
        luat_ei2c *ei2c = toei2c(L);
        result = i2c_soft_send(ei2c, addr, buff, len + 1);
    }
    else
    {
        result = luat_i2c_send(id, addr, buff, len + 1);
    }
    luat_heap_free(buff);
    lua_pushboolean(L, result == 0);
    return 1;
}

/*
i2c读寄存器数据
@api i2c.readReg(id, addr, reg, len)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int I2C子设备的地址, 7位地址
@int 寄存器地址
@int 待接收的数据长度
@return string 收到的数据
@usage
-- 从i2c1的地址为0x5C的设备的寄存器0x01读出2个字节的数据
i2c.readReg(1, 0x5C, 0x01, 2)
*/
static int l_i2c_read_reg(lua_State *L)
{
    int id = 0;
    if (!lua_isuserdata(L, 1))
    {
        id = luaL_checkinteger(L, 1);
    }
    int addr = luaL_checkinteger(L, 2);
    int reg = luaL_checkinteger(L, 3);
    int len = luaL_checkinteger(L, 4);
    char temp = (char)reg;
    int result;
    if (lua_isuserdata(L, 1))
    {
        luat_ei2c *ei2c = toei2c(L);
        result = i2c_soft_send(ei2c, addr, &temp, 1);
    }
    else
    {
        result = luat_i2c_send(id, addr, &temp, 1);
    }
    if (result != 0)
    { //如果返回值不为0，说明收失败了
        LLOGD("i2c send result %d", result);
        lua_pushlstring(L, NULL, 0);
        return 1;
    }
    char *buff = (char *)luat_heap_malloc(sizeof(char) * len);
    if (lua_isuserdata(L, 1))
    {
        luat_ei2c *ei2c = toei2c(L);
        result = i2c_soft_recv(ei2c, addr, buff, len);
    }
    else
    {
        result = luat_i2c_recv(id, addr, buff, len);
    }
    if (result != 0)
    { //如果返回值不为0，说明收失败了
        len = 0;
        LLOGD("i2c receive result %d", result);
    }
    lua_pushlstring(L, buff, len);
    luat_heap_free(buff);
    return 1;
}

/*
关闭i2c设备
@api i2c.close(id)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@return nil 无返回值
@usage
-- 关闭i2c1
i2c.close(1)
*/
static int l_i2c_close(lua_State *L)
{
    int id = luaL_checkinteger(L, 1);
    luat_i2c_close(id);
    return 0;
}

/*
从i2c总线读取DHT12的温湿度数据
@api i2c.readDHT12(id)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int DHT12的设备地址,默认0x5C
@return boolean 读取成功返回true,否则返回false
@return int 湿度值,单位0.1%, 例如 591 代表 59.1%
@return int 温度值,单位0.1摄氏度, 例如 292 代表 29.2摄氏度
@usage
-- 从i2c0读取DHT12
i2c.setup(0)
local re, H, T = i2c.readDHT12(0)
if re then
    log.info("dht12", H, T)
end
*/
static int l_i2c_readDHT12(lua_State *L)
{
    int id = 0;
    if (!lua_isuserdata(L, 1))
    {
        id = luaL_checkinteger(L, 1);
    }
    int addr = luaL_optinteger(L, 2, 0x5C);
    char buff[5] = {0};
    char temp = 0x00;
    int result = -1;
    if (lua_isuserdata(L, 1))
    {
        luat_ei2c *ei2c = toei2c(L);
        result = i2c_soft_send(ei2c, addr, &temp, 1);
    }
    else
    {
        result = luat_i2c_send(id, addr, &temp, 1);
    }
    if (result != 0)
    {
        LLOGD("DHT12 i2c bus write fail");
        lua_pushboolean(L, 0);
        return 1;
    }
    if (lua_isuserdata(L, 1))
    {
        luat_ei2c *ei2c = toei2c(L);
        result = i2c_soft_recv(ei2c, addr, buff, 5);
    }
    else
    {
        result = luat_i2c_recv(id, addr, buff, 5);
    }
    if (result != 0)
    {
        lua_pushboolean(L, 0);
        return 1;
    }
    else
    {
        if (buff[0] == 0 && buff[1] == 0 && buff[2] == 0 && buff[3] == 0 && buff[4] == 0)
        {
            LLOGD("DHT12 DATA emtry");
            lua_pushboolean(L, 0);
            return 1;
        }
        // 检查crc值
        LLOGD("DHT12 DATA %02X%02X%02X%02X%02X", buff[0], buff[1], buff[2], buff[3], buff[4]);
        uint8_t crc_act = (uint8_t)buff[0] + (uint8_t)buff[1] + (uint8_t)buff[2] + (uint8_t)buff[3];
        uint8_t crc_exp = (uint8_t)buff[4];
        if (crc_act != crc_exp)
        {
            LLOGD("DATA12 DATA crc not ok");
            lua_pushboolean(L, 0);
            return 1;
        }
        lua_pushboolean(L, 1);
        lua_pushinteger(L, (uint8_t)buff[0] * 10 + (uint8_t)buff[1]);
        if (((uint8_t)buff[2]) > 127)
            lua_pushinteger(L, ((uint8_t)buff[2] - 128) * -10 + (uint8_t)buff[3]);
        else
            lua_pushinteger(L, (uint8_t)buff[2] * 10 + (uint8_t)buff[3]);
        return 3;
    }
}

/*
从i2c总线读取DHT30的温湿度数据(由"好奇星"贡献)
@api i2c.readSHT30(id,addr)
@int 设备id, 例如i2c1的id为1, i2c2的id为2
@int 设备addr,SHT30的设备地址,默认0x44 bit7
@return boolean 读取成功返回true,否则返回false
@return int 湿度值,单位0.1%, 例如 591 代表 59.1%
@return int 温度值,单位0.1摄氏度, 例如 292 代表 29.2摄氏度
@usage
-- 从i2c0读取SHT30
i2c.setup(0)
local re, H, T = i2c.readSHT30(0)
if re then
    log.info("sht30", H, T)
end
*/
static int l_i2c_readSHT30(lua_State *L)
{
    char buff[7] = {0x2c, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00};
    float temp = 0x00;
    float hum = 0x00;

    int result = -1;
    if (lua_isuserdata(L, 1))
    {
        luat_ei2c *ei2c = toei2c(L);
        i2c_soft_send(ei2c, ei2c->addr, buff, 2);
        luat_timer_mdelay(13);

        result = i2c_soft_recv(ei2c, ei2c->addr, buff, 6);
    }
    else
    {
        int id = luaL_optinteger(L, 1, 0);
        int addr = luaL_optinteger(L, 2, 0x44);

        luat_i2c_send(id, addr, &buff, 2);
        luat_timer_mdelay(1);
        result = luat_i2c_recv(id, addr, buff, 6);
    }

    if (result != 0)
    {
        lua_pushboolean(L, 0);
        return 1;
    }
    else
    {
        if (buff[0] == 0 && buff[1] == 0 && buff[2] == 0 && buff[3] == 0 && buff[4] == 0)
        {
            LLOGD("SHT30 DATA emtry");
            lua_pushboolean(L, 0);
            return 1;
        }
        // 检查crc值
        // LLOGD("SHT30 DATA %02X %02X %02X %02X %02X %02X", buff[0], buff[1], buff[2], buff[3], buff[4], buff[5]);

        temp = ((((buff[0] * 256) + buff[1]) * 175) / 6553.5) - 450;
        hum = ((((buff[3] * 256) + buff[4]) * 100) / 6553.5);

        // LLOGD("\r\n SHT30  %d deg  %d Hum ", temp, hum);
        //  跳过CRC

        // uint8_t crc_act = (uint8_t)buff[0] + (uint8_t)buff[1] + (uint8_t)buff[2] + (uint8_t)buff [3];
        // uint8_t crc_exp = (uint8_t)buff[4];
        // if (crc_act != crc_exp) {
        //     LLOGD("DATA12 DATA crc not ok");
        //     lua_pushboolean(L, 0);
        //     return 1;
        // }

        // Convert the data
        lua_pushboolean(L, 1);
        lua_pushinteger(L, (int)hum);
        lua_pushinteger(L, (int)temp);

        return 3;
        // 华氏度
        // fTemp = (cTemp * 1.8) + 32;
    }
}

#include "rotable.h"
static const rotable_Reg reg_i2c[] =
{
    { "exist", l_i2c_exist, 0},
    { "setup", l_i2c_setup, 0},
    { "createSoft", l_i2c_soft, 0},
#ifdef __F1C100S__
#else
    { "send", l_i2c_send, 0},
    { "recv", l_i2c_recv, 0},
#endif
    { "writeReg", l_i2c_write_reg, 0},
    { "readReg", l_i2c_read_reg, 0},
    { "close", l_i2c_close, 0},

    { "readDHT12", l_i2c_readDHT12, 0},
    { "readSHT30", l_i2c_readSHT30, 0},

    { "FAST",  NULL, 1},
    { "SLOW",  NULL, 0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_i2c(lua_State *L)
{
    luat_newlib(L, reg_i2c);
    luaL_newmetatable(L, LUAT_EI2C_TYPE);
    lua_pop(L, 1);
    return 1;
}
