
/*
@module  sensor
@summary 传感器操作库
@version 1.0
@date    2020.03.30
*/
#include "luat_base.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "luat.sensor"
#include "luat_log.h"

#define CONNECT_SUCCESS  0
#define CONNECT_FAILED   1

#define W1_INPUT_MODE PIN_MODE_INPUT_PULLUP



static void w1_reset(int pin)
{
    luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_set(pin, Luat_GPIO_LOW);
    luat_timer_us_delay(550);               /* 480us - 960us */
    luat_gpio_set(pin, Luat_GPIO_HIGH);
    luat_timer_us_delay(40);                /* 15us - 60us*/
}

static uint8_t w1_connect(int pin)
{
    uint8_t retry = 0;
    luat_gpio_mode(pin, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, 0);

    while (luat_gpio_get(pin) && retry < 200)
    {
        retry++;
        luat_timer_us_delay(1);
    };

    if(retry >= 200)
        return CONNECT_FAILED;
    else
        retry = 0;

    while (!luat_gpio_get(pin) && retry < 240)
    {
        retry++;
        luat_timer_us_delay(1);
    };

    if(retry >= 240)
        return CONNECT_FAILED;

    return CONNECT_SUCCESS;
}

static uint8_t w1_read_bit(int pin)
{
    uint8_t data;

    luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0);
    luat_gpio_set(pin, Luat_GPIO_LOW);
    luat_timer_us_delay(2);
    luat_gpio_set(pin, Luat_GPIO_HIGH);
    luat_gpio_mode(pin, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, 0);
    luat_timer_us_delay(5);

    if(luat_gpio_get(pin))
        data = 1;
    else
        data = 0;

    luat_timer_us_delay(50);

    return data;
}

static uint8_t w1_read_byte(int pin)
{
    uint8_t i, j, dat;
    dat = 0;

    //rt_base_t level;
    //level = rt_hw_interrupt_disable();
    for (i = 1; i <= 8; i++)
    {
        j = w1_read_bit(pin);
        dat = (j << 7) | (dat >> 1);
    }
    //rt_hw_interrupt_enable(level);

    return dat;
}

static void w1_write_byte(int pin, uint8_t dat)
{
    uint8_t j;
    uint8_t testb;
    luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);

    for (j = 1; j <= 8; j++)
    {
        testb = dat & 0x01;
        dat = dat >> 1;

        if(testb)
        {
            luat_gpio_set(pin, Luat_GPIO_LOW);
            luat_timer_us_delay(2);
            luat_gpio_set(pin, Luat_GPIO_HIGH);
            luat_timer_us_delay(60);
        }
        else
        {
            luat_gpio_set(pin, Luat_GPIO_LOW);
            luat_timer_us_delay(60);
            luat_gpio_set(pin, Luat_GPIO_HIGH);
            luat_timer_us_delay(2);
        }
    }
}

static int32_t ds18b20_get_temperature(int pin, int32_t *val)
{
    uint8_t TL, TH;
    int32_t tem;
    
    //ds18b20_start(pin);
    w1_reset(pin);
    if (w1_connect(pin)) {
        LLOGD("ds18b20 connect fail");
        return -1;
    }
    w1_write_byte(pin, 0xcc);  /* skip rom */
    w1_write_byte(pin, 0x44);  /* convert */

    //ds18b20_init(pin);
    w1_reset(pin);
    if (w1_connect(pin)) {
        LLOGD("ds18b20 connect fail");
        return -1;
    }

    w1_write_byte(pin, 0xcc);
    w1_write_byte(pin, 0xbe);
    TL = w1_read_byte(pin);    /* LSB first */
    TH = w1_read_byte(pin);
    // TODO 9个字节都读出来,校验CRC
    if (TH > 7)
    {
        TH =~ TH;
        TL =~ TL;
        tem = TH;
        tem <<= 8;
        tem += TL;
        tem = (int32_t)(tem * 0.0625 * 10 + 0.5);
        *val = tem;
        return 0;
    }
    else
    {
        tem = TH;
        tem <<= 8;
        tem += TL;
        tem = (int32_t)(tem * 0.0625 * 10 + 0.5);
        *val = tem;
        return 0;
    }
}

/*
获取DS18B20的温度数据
@api    sensor.ds18b20(pin)
@int  gpio端口号
@return int 温度数据
@return boolean 成功返回true,否则返回false
--  如果读取失败,会返回nil
while 1 do 
    sys.wait(5000) 
    local val,result = sensor.ds18b20(17)
    -- val 301 == 30.1摄氏度
    -- result true 读取成功
    log.info("ds18b20", val, result)
end
*/
static int l_sensor_ds18b20(lua_State *L) {
    int32_t val = 0;
    int32_t ret = ds18b20_get_temperature(luaL_checkinteger(L, 1), &val);
    // -55°C ~ 125°C
    if (ret || !(val <= 1250 && val >= -550)) {
        LLOGI("ds18b20 read fail");
        lua_pushinteger(L, 0);
        lua_pushboolean(L, 0);
        return 2;
    }
    //rt_kprintf("temp:%3d.%dC\n", temp/10, temp%10);
    lua_pushinteger(L, val);
    lua_pushboolean(L, 1);
    return 2;
}


#include "rotable.h"
static const rotable_Reg reg_sensor[] =
{
    { "ds18b20" ,  l_sensor_ds18b20 , 0},
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_sensor( lua_State *L ) {
    rotable_newlib(L, reg_sensor);
    return 1;
}
