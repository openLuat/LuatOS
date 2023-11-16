#include "luat_base.h"
#include "luat_onewire.h"
#include "luat_gpio.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "onewire"
#include "luat_log.h"

static luat_onewire_opt_t* opt_hw;
static const luat_onewire_opt_t opt_gpio = {
    .mode = LUAT_ONEWIRE_MODE_GPIO,
    .setup = luat_onewire_setup_gpio,
    .reset = luat_onewire_reset_gpio,
    .connect = luat_onewire_connect_gpio,
    .read = luat_onewire_read_gpio,
    .write = luat_onewire_write_gpio,
    .close = luat_onewire_close_gpio
};

int luat_onewire_set_hw_opt(const luat_onewire_opt_t* opt) {
    opt_hw = (luat_onewire_opt_t*)opt;
    return 0;
}

static const luat_onewire_opt_t* get_opt(luat_onewire_ctx_t* ctx) {
    const luat_onewire_opt_t* opt = &opt_gpio;
    if (ctx->mode != LUAT_ONEWIRE_MODE_GPIO) {
        if (opt_hw == NULL) {
            LLOGE("当前硬件未支持硬件模式驱动Onewire");
            return NULL;
        }
        opt = opt_hw; 
    }
    return opt;
}

int luat_onewire_setup(luat_onewire_ctx_t* ctx) {
    const luat_onewire_opt_t* opt = get_opt(ctx);
    if (opt == NULL)
        return -1;
    return opt->setup(ctx);
}

int luat_onewire_reset(luat_onewire_ctx_t* ctx){
    const luat_onewire_opt_t* opt = get_opt(ctx);
    if (opt == NULL)
        return -1;
    return opt->reset(ctx);
}

int luat_onewire_connect(luat_onewire_ctx_t* ctx){
    const luat_onewire_opt_t* opt = get_opt(ctx);
    if (opt == NULL)
        return -1;
    return opt->connect(ctx);
}

int luat_onewire_read(luat_onewire_ctx_t* ctx, char* buff, size_t len){
    const luat_onewire_opt_t* opt = get_opt(ctx);
    if (opt == NULL)
        return -1;
    return opt->read(ctx, buff, len);
}

int luat_onewire_write(luat_onewire_ctx_t* ctx, const char* buff, size_t len){
    const luat_onewire_opt_t* opt = get_opt(ctx);
    if (opt == NULL)
        return -1;
    return opt->write(ctx, buff, len);
}

int luat_onewire_close(luat_onewire_ctx_t* ctx){
    const luat_onewire_opt_t* opt = get_opt(ctx);
    if (opt == NULL)
        return -1;
    return opt->close(ctx);
}

// TODO GPIO默认实现, 可以从lib_sensor迁移过来
int luat_onewire_setup_gpio(luat_onewire_ctx_t* ctx) {
    luat_gpio_mode(ctx->id, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    return 0;
}

int luat_onewire_reset_gpio(luat_onewire_ctx_t* ctx) {
    int pin = ctx->id;
    luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_set(pin, Luat_GPIO_LOW);
    luat_timer_us_delay(550); /* 480us - 960us */
    luat_gpio_set(pin, Luat_GPIO_HIGH);
    luat_timer_us_delay(40); /* 15us - 60us*/
    return 0;
}

int luat_onewire_connect_gpio(luat_onewire_ctx_t* ctx) {
    uint8_t retry = 0;
    int pin = ctx->id;
    luat_gpio_mode(pin, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, 0);

    while (luat_gpio_get(pin) && retry < 200)
    {
        retry++;
        luat_timer_us_delay(1);
    };

    if (retry >= 200)
        return -1;
    else
        retry = 0;

    while (!luat_gpio_get(pin) && retry < 240)
    {
        retry++;
        luat_timer_us_delay(1);
    };

    if (retry >= 240)
        return -1;

    return 0;
}

static uint8_t w1_read_bit(int pin){
  uint8_t data;
  luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, 0);
  luat_gpio_set(pin, Luat_GPIO_LOW);
  luat_timer_us_delay(2);
  luat_gpio_set(pin, Luat_GPIO_HIGH);
  luat_gpio_mode(pin, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, 0);
  data = (uint8_t)luat_gpio_get(pin);
  luat_timer_us_delay(60);
  return data;
}

static uint8_t w1_read_byte(int pin)
{
  uint8_t i, j, dat;
  dat = 0;
  luat_timer_us_delay(90);
  for (i = 1; i <= 8; i++)
  {
    j = w1_read_bit(pin);
    dat = (j << 7) | (dat >> 1);
  }

  return dat;
}

int luat_onewire_read_gpio(luat_onewire_ctx_t* ctx, char* buff, size_t len) {
    for (size_t i = 0; i < len; i++)
    {
        buff[i] = w1_read_byte(ctx->id);
    }
    return len;
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

int luat_onewire_write_gpio(luat_onewire_ctx_t* ctx, const char* buff, size_t len) {
    for (size_t i = 0; i < len; i++)
    {
        w1_write_byte(ctx->id, (uint8_t)buff[i]);
    }
    
    return len;
}

int luat_onewire_close_gpio(luat_onewire_ctx_t* ctx) {
    luat_gpio_mode(ctx->id, Luat_GPIO_INPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    return 0;
}

