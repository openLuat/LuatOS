
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "rtthread.h"
#include "rthw.h"
#include <rtdevice.h>
#include "luat_gpio.h"

#define CONNECT_SUCCESS  0
#define CONNECT_FAILED   1

RT_WEAK void luat_timer_us_delay(size_t us) {
    rt_hw_us_delay(us);
}

static void w1_reset(int pin)
{
    luat_gpio_mode(pin, Luat_GPIO_OUTPUT);
    luat_gpio_set(pin, Luat_GPIO_LOW);
    luat_timer_us_delay(780);               /* 480us - 960us */
    luat_gpio_set(pin, Luat_GPIO_HIGH);
    luat_timer_us_delay(40);                /* 15us - 60us*/
}

static uint8_t w1_connect(int pin)
{
    uint8_t retry = 0;
    luat_gpio_mode(pin, Luat_GPIO_INPUT);

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

    luat_gpio_mode(pin, Luat_GPIO_OUTPUT);
    luat_gpio_set(pin, Luat_GPIO_LOW);
    luat_timer_us_delay(2);
    luat_gpio_set(pin, Luat_GPIO_HIGH);
    luat_gpio_mode(pin, Luat_GPIO_INPUT);
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

    for (i = 1; i <= 8; i++)
    {
        j = w1_read_bit(pin);
        dat = (j << 7) | (dat >> 1);
    }

    return dat;
}

static void w1_write_byte(int pin, uint8_t dat)
{
    uint8_t j;
    uint8_t testb;
    luat_gpio_mode(pin, Luat_GPIO_OUTPUT);

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

static int32_t ds18b20_get_temperature(int pin)
{
    uint8_t TL, TH;
    int32_t tem;
    
    //ds18b20_start(pin);
    w1_reset(pin);
    w1_connect(pin);
    w1_write_byte(pin, 0xcc);  /* skip rom */
    w1_write_byte(pin, 0x44);  /* convert */

    //ds18b20_init(pin);
    w1_reset(pin);
    w1_connect(pin);

    w1_write_byte(pin, 0xcc);
    w1_write_byte(pin, 0xbe);
    TL = w1_read_byte(pin);    /* LSB first */
    TH = w1_read_byte(pin);
    if (TH > 7)
    {
        TH =~ TH;
        TL =~ TL;
        tem = TH;
        tem <<= 8;
        tem += TL;
        tem = (int32_t)(tem * 0.0625 * 10 + 0.5);
        return -tem;
    }
    else
    {
        tem = TH;
        tem <<= 8;
        tem += TL;
        tem = (int32_t)(tem * 0.0625 * 10 + 0.5);
        return tem;
    }
}


// 获取DS18B20的温度数据
// while 1 do timer.mdelay(5000) sensor.ds18b20(14) end
static int l_sensor_ds18b20(lua_State *L) {
    int32_t temp = ds18b20_get_temperature(luaL_checkinteger(L, 1));
    //rt_kprintf("temp:%3d.%dC\n", temp/10, temp%10);
    lua_pushinteger(L, temp);
    return 1;
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