
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
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "sensor"
#include "luat_log.h"

#define CONNECT_SUCCESS 0
#define CONNECT_FAILED 1
unsigned int temp;
static void w1_reset(int pin)
{
  luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
  luat_gpio_set(pin, Luat_GPIO_LOW);
  luat_timer_us_delay(550); /* 480us - 960us */
  luat_gpio_set(pin, Luat_GPIO_HIGH);
  luat_timer_us_delay(40); /* 15us - 60us*/
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

  if (retry >= 200)
    return CONNECT_FAILED;
  else
    retry = 0;

  while (!luat_gpio_get(pin) && retry < 240)
  {
    retry++;
    luat_timer_us_delay(1);
  };

  if (retry >= 240)
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

  if (luat_gpio_get(pin))
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

    if (testb)
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

static uint8_t crc8_maxim[256] = {
    0, 94, 188, 226, 97, 63, 221, 131, 194, 156, 126, 32, 163, 253, 31, 65,
    157, 195, 33, 127, 252, 162, 64, 30, 95, 1, 227, 189, 62, 96, 130, 220,
    35, 125, 159, 193, 66, 28, 254, 160, 225, 191, 93, 3, 128, 222, 60, 98,
    190, 224, 2, 92, 223, 129, 99, 61, 124, 34, 192, 158, 29, 67, 161, 255,
    70, 24, 250, 164, 39, 121, 155, 197, 132, 218, 56, 102, 229, 187, 89, 7,
    219, 133, 103, 57, 186, 228, 6, 88, 25, 71, 165, 251, 120, 38, 196, 154,
    101, 59, 217, 135, 4, 90, 184, 230, 167, 249, 27, 69, 198, 152, 122, 36,
    248, 166, 68, 26, 153, 199, 37, 123, 58, 100, 134, 216, 91, 5, 231, 185,
    140, 210, 48, 110, 237, 179, 81, 15, 78, 16, 242, 172, 47, 113, 147, 205,
    17, 79, 173, 243, 112, 46, 204, 146, 211, 141, 111, 49, 178, 236, 14, 80,
    175, 241, 19, 77, 206, 144, 114, 44, 109, 51, 209, 143, 12, 82, 176, 238,
    50, 108, 142, 208, 83, 13, 239, 177, 240, 174, 76, 18, 145, 207, 45, 115,
    202, 148, 118, 40, 171, 245, 23, 73, 8, 86, 180, 234, 105, 55, 213, 139,
    87, 9, 235, 181, 54, 104, 138, 212, 149, 203, 41, 119, 244, 170, 72, 22,
    233, 183, 85, 11, 136, 214, 52, 106, 43, 117, 151, 201, 74, 20, 246, 168,
    116, 42, 200, 150, 21, 75, 169, 247, 182, 232, 10, 84, 215, 137, 107, 53};

static int32_t ds18b20_get_temperature(int pin, int32_t *val, int check_crc)
{
  uint8_t TL, TH;
  int32_t tem;

  uint8_t data[9] = {0};

  //ds18b20_start(pin);
  w1_reset(pin);
  if (w1_connect(pin))
  {
    //LLOGD("ds18b20 connect fail");
    return -1;
  }
  w1_write_byte(pin, 0xcc); /* skip rom */
  w1_write_byte(pin, 0x44); /* convert */

  //ds18b20_init(pin);
  w1_reset(pin);
  if (w1_connect(pin))
  {
    //LLOGD("ds18b20 connect fail");
    return -2;
  }

  w1_write_byte(pin, 0xcc);
  w1_write_byte(pin, 0xbe);
  data[0] = w1_read_byte(pin); /* LSB first */
  data[1] = w1_read_byte(pin);

  if (data[0] == 0xFF || data[1] == 0xFF)
  {
    //LLOGD("ds18b20 bad data, skip");
    return -3;
  }

  // 9个字节都读出来,校验CRC
  if (check_crc)
  {
    for (size_t i = 2; i < 9; i++)
    {
      data[i] = w1_read_byte(pin);
    }
    uint8_t crc = 0;
    for (size_t i = 0; i < 8; i++)
    {
      crc = crc8_maxim[crc ^ data[i]];
    }
    // LLOGD("ds18b20 %02X%02X%02X%02X%02X%02X%02X%02X [%02X %02X]",
    //            data[0], data[1], data[2], data[3],
    //            data[4], data[5], data[6], data[7],
    //            data[8], crc);
    if (data[8] != crc)
    {
      //LLOGD("ds18b20 bad crc");
      return -4;
    }
  }
  TL = data[0];
  TH = data[1];

  if (TH > 7)
  {
    TH = ~TH;
    TL = ~TL;
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
@int    gpio端口号
@boolean 是否校验crc值,默认为true. 不校验crc值能提高读取成功的概率,但可能会读取到错误的值
@return int 温度数据,单位0.1摄氏度，读取失败时返回错误码
@return boolean 成功返回true,否则返回false
@usage
while 1 do
    sys.wait(5000)
    local val,result = sensor.ds18b20(17, true) -- GPIO17且校验CRC值
    -- val 301 == 30.1摄氏度
    -- result true 读取成功
    log.info("ds18b20", val, result)
end
*/
static int l_sensor_ds18b20(lua_State *L)
{
  int32_t val = 0;
  int check_crc = lua_gettop(L) > 1 ? lua_toboolean(L, 2) : 1;
  int pin = luaL_checkinteger(L, 1);
  luat_os_entry_cri();
  int32_t ret = ds18b20_get_temperature(pin, &val, check_crc);
  luat_os_exit_cri();
  // -55°C ~ 125°C
  if (ret || !(val <= 1250 && val >= -550))
  {
    LLOGI("ds18b20 read fail");
    lua_pushinteger(L, ret);
    lua_pushboolean(L, 0);
    return 2;
  }
  //rt_kprintf("temp:%3d.%dC\n", temp/10, temp%10);
  lua_pushinteger(L, val);
  lua_pushboolean(L, 1);
  return 2;
}

//-------------------------------------
// W1 单总线协议, 暴露w1_xxx方法
//-------------------------------------

/*
单总线协议,复位设备
@api    sensor.w1_reset(pin)
@int  gpio端口号
@return nil 无返回
*/
static int l_w1_reset(lua_State *L)
{
  w1_reset((int)luaL_checkinteger(L, 1));
  return 0;
}

/*
单总线协议,连接设备
@api    sensor.w1_reset(pin)
@int  gpio端口号
@return boolean 成功返回true,失败返回false
*/
static int l_w1_connect(lua_State *L)
{
  if (w1_connect((int)luaL_checkinteger(L, 1)) == CONNECT_SUCCESS)
  {
    lua_pushboolean(L, 1);
  }
  else
  {
    lua_pushboolean(L, 0);
  }
  return 1;
}

/*
单总线协议,往总线写入数据
@api    sensor.w1_write(pin, data1,data2)
@int  gpio端口号
@int  第一个数据
@int  第二个数据, 可以写N个数据
@return nil 无返回值
*/
static int l_w1_write_byte(lua_State *L)
{
  int pin = luaL_checkinteger(L, 1);
  int top = lua_gettop(L);
  if (top > 1)
  {
    for (size_t i = 2; i <= top; i++)
    {
      uint8_t data = luaL_checkinteger(L, i);
      w1_write_byte(pin, data);
    }
  }
  return 0;
}

/*
单总线协议,从总线读取数据
@api    sensor.w1_read(pin, len)
@int  gpio端口号
@int  读取的长度
@return int 按读取的长度返回N个整数
*/
static int l_w1_read_byte(lua_State *L)
{
  int pin = luaL_checkinteger(L, 1);
  int len = luaL_checkinteger(L, 2);
  for (size_t i = 0; i < len; i++)
  {
    lua_pushinteger(L, w1_read_byte(pin));
  }
  return len;
}
unsigned long ReadCount(int date,int clk) //增益128
{
  unsigned long count;
  unsigned char i;
  luat_gpio_mode(date, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0);
  luat_gpio_set(date, Luat_GPIO_HIGH);
  luat_timer_us_delay(1);
  luat_gpio_mode(clk, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0);
  luat_gpio_set(clk, Luat_GPIO_LOW);
  luat_gpio_mode(date, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, 0);
  luat_timer_us_delay(1);
  count = 0;
  while (luat_gpio_get(date))
    ; // TODO 用tick或者us_delay统计timeout
  for (i = 0; i < 24; i++)
  {
    luat_gpio_set(clk, Luat_GPIO_HIGH);
    count = count << 1;
    luat_gpio_set(clk, Luat_GPIO_LOW);
    if (luat_gpio_get(date))
      count++;
  }
  luat_gpio_set(clk, Luat_GPIO_HIGH);
  luat_timer_us_delay(1);
  luat_gpio_set(clk, Luat_GPIO_LOW);

  return count;
}
/*
获取Hx711的温度数据
@api    sensor.hx711(pin_date,pin_clk)
@int    数据的gpio端口号
@int    时钟的gpio端口号
@return int hx711读到的数据
@usage
--  如果设备不存在会卡在读取接口
sys.taskInit(
    function()
        sys.wait(1000)
        local maopi = sensor.hx711(0,7)
        while true do
            sys.wait(2000)
            a = sensor.hx711(0,7) - maopi
            if a > 0 then
                log.info("tag", a / 4.6)
            end
        end
    end
)
*/
static int l_sensor_hx711(lua_State *L)
{
  unsigned int j;
  unsigned long hx711_dat;
  int date = luaL_checkinteger(L, 1);
  int clk = luaL_checkinteger(L, 2);
  //for (j = 0; j < 5; j++)
  //  luat_timer_us_delay(5000);
  hx711_dat = ReadCount(date,clk);                //HX711AD转换数据处理
  temp = (unsigned int)(hx711_dat / 100); //缩放long数据为int型，方便处理
  //LLOGI("hx711:%d",temp);
  lua_pushinteger(L, temp);

  return 1;
}


/*
设置ws2812b输出
@api    sensor.ws2812b(pin,data,T0H,T0L,T1H,T1L)
@int    ws2812b的gpio端口号
@string/zbuff    待发送的数据（如果为zbuff数据，则会无视指针位置始终从0偏移开始）
@int    T0H时间，表示延时多少个nop，每个型号不一样，自己调
@int    T0L时间，表示延时多少个nop
@int    T1H时间，表示延时多少个nop
@int    T1L时间，表示延时多少个nop
@usage
local buff = zbuff.create({8,8,24})
buff:drawLine(1,2,5,6,0x00ffff)
sensor.ws2812b(7,buff,300,700,700,700)
*/
#define WS2812B_BIT_0() \
  t0h_temp = t0h; t0l_temp = t0l; \
  luat_gpio_set(pin, Luat_GPIO_HIGH); \
  while(t0h_temp--); \
  luat_gpio_set(pin, Luat_GPIO_LOW); \
  while(t0l_temp--)
#define WS2812B_BIT_1() \
  t1h_temp = t1h; t1l_temp = t1l; \
  luat_gpio_set(pin, Luat_GPIO_HIGH); \
  while(t1h_temp--); \
  luat_gpio_set(pin, Luat_GPIO_LOW); \
  while(t1l_temp--)
static int l_sensor_ws2812b(lua_State *L)
{
  int j;
  size_t len,i;
  const char *send_buff = NULL;
  int pin = luaL_checkinteger(L, 1);
  if (lua_isuserdata(L, 2))
  {
    luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
    send_buff = (const char*)buff->addr;
    len = buff->len;
  }
  else
  {
    send_buff = lua_tolstring(L, 2, &len);
  }
  uint32_t t0h_temp,t0h = luaL_checkinteger(L, 3);
  uint32_t t0l_temp,t0l = luaL_checkinteger(L, 4);
  uint32_t t1h_temp,t1h = luaL_checkinteger(L, 5);
  uint32_t t1l_temp,t1l = luaL_checkinteger(L, 6);

  luat_os_entry_cri();
  luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
  //luat_gpio_set(pin, Luat_GPIO_LOW);
  luat_timer_us_delay(1);
  //luat_gpio_set(pin, Luat_GPIO_HIGH);
  for(i=0;i<len;i++)
  {
    for(j=7;j>=0;j--)
    {
      if(send_buff[i]>>j&0x01)
      {
        WS2812B_BIT_1();
      }
      else
      {
        WS2812B_BIT_0();
      }
    }
  }
  luat_os_exit_cri();
  return 0;
}

#include "rotable.h"
static const rotable_Reg reg_sensor[] =
    {
        {"w1_reset", l_w1_reset, 0},
        {"w1_connect", l_w1_connect, 0},
        {"w1_write", l_w1_write_byte, 0},
        {"w1_read", l_w1_read_byte, 0},
        {"ds18b20", l_sensor_ds18b20, 0},
        {"hx711", l_sensor_hx711, 0},
        {"ws2812b", l_sensor_ws2812b, 0},
        {NULL, NULL, 0}};

LUAMOD_API int luaopen_sensor(lua_State *L)
{
  luat_newlib(L, reg_sensor);
  return 1;
}
