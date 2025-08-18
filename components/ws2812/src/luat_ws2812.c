#include "luat_base.h"
#include "luat_ws2812.h"
#include "luat_msgbus.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_pwm.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "ws2812"
#include "luat_log.h"

int luat_ws28128_send_gpio(luat_ws2812_t *ctx);
int luat_ws28128_send_spi(luat_ws2812_t *ctx);
int luat_ws28128_send_pwm(luat_ws2812_t *ctx);
int luat_ws28128_send_notok(luat_ws2812_t *ctx);

// 默认实现注册表, 通过luat_ws2812_set_opt可修改
luat_ws2812_opt_t ws2812_opts[] = {
#ifdef LUAT_USE_GPIO
    {.mode = LUAT_WS2812_MODE_GPIO, .opt = luat_ws28128_send_gpio},
#endif
#ifdef LUAT_USE_SPI
    {.mode = LUAT_WS2812_MODE_SPI, .opt = luat_ws28128_send_spi},
#endif
#ifdef LUAT_USE_PWM
    {.mode = LUAT_WS2812_MODE_PWM, .opt = luat_ws28128_send_pwm},
#endif
    {.mode = LUAT_WS2812_MODE_RMT, .opt = luat_ws28128_send_notok},
    {.mode = LUAT_WS2812_MODE_HW, .opt = luat_ws28128_send_notok}
};

int luat_ws2812_set_opt(uint8_t mode, ws2812_send_opt_impl opt) {
    for (size_t i = 0; i < sizeof(ws2812_opts) / sizeof(luat_ws2812_opt_t); i++)
    {
        if (ws2812_opts[i].mode == mode) {
            ws2812_opts[i].opt = opt;
        }
    }
    return 0;
}

int luat_ws2812_send(luat_ws2812_t* ctx) {
    if (ctx == NULL) {
        return -1;
    }
    for (size_t i = 0; i < sizeof(ws2812_opts) / sizeof(luat_ws2812_opt_t); i++)
    {
        if (ws2812_opts[i].mode == ctx->mode) {
            return ws2812_opts[i].opt(ctx);
        }
    }
    return 0;
}

//------------------------------------------------
//  GPIO 模式
//-----------------------------------------------
static const unsigned char xor_bit_table[8]={0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80};

#define WS2812B_BIT_0() \
  t0h_temp = t0h; t0l_temp = t0l; \
  luat_gpio_pulse(pin,&pulse_level,2,t0h); \
  while(t0l_temp--)
#define WS2812B_BIT_1() \
  t1h_temp = t1h; t1l_temp = t1l; \
  luat_gpio_pulse(pin,&pulse_level,2,t1h); \
  while(t1l_temp--)


int luat_ws28128_send_gpio(luat_ws2812_t *ctx)
{
  int j;
  size_t len,i;
  uint8_t pulse_level = 0x80;
  const char *send_buff = NULL;
  int pin = ctx->id;
  send_buff = (const char*)ctx->colors;
  len = ctx->count * sizeof(luat_ws2812_color_t);
#ifdef LUAT_WS2812B_MAX_CNT
  luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
  uint32_t frame_cnt = ctx->args[4];
  luat_gpio_driver_ws2812b(pin, send_buff, len, frame_cnt, ctx->args[0], ctx->args[1], ctx->args[2], ctx->args[3]);
#else
  volatile uint32_t t0h_temp,t0h = ctx->args[0];
  volatile uint32_t t0l_temp,t0l = ctx->args[1];
  volatile uint32_t t1h_temp,t1h = ctx->args[2];
  volatile uint32_t t1l_temp,t1l = ctx->args[3];
  
  luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
  pulse_level = 0 ;
  luat_gpio_pulse(pin,&pulse_level,2,t0h);
  pulse_level = 0x80;
  luat_os_entry_cri();

  for(i=0;i<len;i++)
  {
    for(j=7;j>=0;j--)
    {
      if(send_buff[i]&xor_bit_table[j])
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
#endif
  return 0;
}

//------------------------------------------------
//  SPI 模式
//-----------------------------------------------

int luat_ws28128_send_spi(luat_ws2812_t *ctx)
{
    int j, m;
    size_t len, i;
    const char *send_buff = NULL;

    luat_spi_t ws2812b_spi_conf = {
        .cs = 255,
        .CPHA = 0,
        .CPOL = 0,
        .dataw = 8,
        .bandrate = 5 * 1000 * 1000,
        .bit_dict = 1,
        .master = 1,
        .mode = 1,
    };

    ws2812b_spi_conf.id = ctx->id;
    send_buff = (const char*)ctx->colors;
    len = ctx->count * sizeof(luat_ws2812_color_t);

    const char res_buff = 0x00;
    const char low_buff = 0xc0;
    const char high_buff = 0xf8;
    luat_spi_setup(&ws2812b_spi_conf);

    luat_spi_send(ws2812b_spi_conf.id, &res_buff, 1);

    char *gbr_buff = luat_heap_malloc(len * 8);
    m = 0;
    for (i = 0; i < len; i++)
    {
        for (j = 7; j >= 0; j--)
        {
            if (send_buff[i] >> j & 0x01)
            {
                gbr_buff[m] = high_buff;
            }
            else
            {
                gbr_buff[m] = low_buff;
            }
            m++;
        }
    }
    luat_spi_send(ws2812b_spi_conf.id, gbr_buff, len * 8);
    luat_spi_close(ws2812b_spi_conf.id);
    luat_heap_free(gbr_buff);
    return 0;
}

//------------------------------------------------
//  PWM 模式
//-----------------------------------------------

int luat_ws28128_send_pwm(luat_ws2812_t *ctx)
{
    int ret = 0;
    int j = 0;
    size_t len, i;
    const char *send_buff = NULL;
    luat_pwm_conf_t ws2812b_pwm_conf = {
        .pnum = 1,
        .period = 800 * 1000,
        .precision = 100};
    ws2812b_pwm_conf.channel = ctx->id;
    send_buff = (const char*)ctx->colors;
    len = ctx->count * sizeof(luat_ws2812_color_t);

    // ws2812b_pwm_conf.pulse = 0;
    // luat_pwm_setup(&ws2812b_pwm_conf);

    for (i = 0; i < len; i++)
    {
        for (j = 7; j >= 0; j--)
        {
            if (send_buff[i] >> j & 0x01)
            {
                ws2812b_pwm_conf.pulse = 200 / 3;
                ret = luat_pwm_setup(&ws2812b_pwm_conf);
            }
            else
            {
                ws2812b_pwm_conf.pulse = 100 / 3;
                ret = luat_pwm_setup(&ws2812b_pwm_conf);
            }
            if (ret)
            {
                LLOGW("luat_pwm_setup ret %d, end of PWM output", ret);
                return -1;
            }
        }
    }

    return 0;
}

int luat_ws28128_send_notok(luat_ws2812_t *ctx)
{
    LLOGW("该模式的ws2812发送方式未支持");
    return -1;
}
