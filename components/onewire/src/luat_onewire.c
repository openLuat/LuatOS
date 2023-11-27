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

int ds18b20_reset_gpio(luat_onewire_ctx_t* ctx) {
    int pin = ctx->id;
    luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
    luat_gpio_set(pin, Luat_GPIO_LOW);
    luat_timer_us_delay(550); /* 480us - 960us */
    luat_gpio_set(pin, Luat_GPIO_HIGH);
    luat_timer_us_delay(40); /* 15us - 60us*/
    return 0;
}

int ds18b20_connect_gpio(luat_onewire_ctx_t* ctx) {
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

static const uint8_t crc8_maxim[256] = {
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


int luat_onewire_ds18b20(const luat_onewire_ctx_t* ctx, int check_crc, int32_t *re) {

    // 初始化单总线
    luat_os_entry_cri();
    int ret = luat_onewire_setup(ctx);
    if (ret)
    {
        LLOGW("setup失败 mode %d id %d ret %d", ctx->mode, ctx->id, ret);
        goto exit;
    }
    // 复位设备
    ret = ds18b20_reset_gpio(ctx);
    // if (ret) {
    //     LLOGW("reset失败 mode %d id %d ret %d", ctx->mode, ctx->id, ret);
    //     return 0;
    // }
    // 建立连接
    ret = ds18b20_connect_gpio(ctx);
    if (ret)
    {
        LLOGW("connect失败 mode %d id %d ret %d", ctx->mode, ctx->id, ret);
        goto exit;
    }
    // 写入2字节的数据
    char wdata[] = {0xCC, 0x44}; /* skip rom */ /* convert */
    luat_onewire_write(ctx, wdata, 2);

    // 再次复位
    ds18b20_reset_gpio(ctx);
    // 再次建立连接
    ret = ds18b20_connect_gpio(ctx);
    if (ret)
    {
        LLOGW("connect失败2 mode %d id %d ret %d", ctx->mode, ctx->id, ret);
        goto exit;
    }

    wdata[1] = 0xBE;
    luat_onewire_write(ctx, wdata, 2);

    uint8_t data[9] = {0};
    // 校验模式读9个字节, 否则读2个字节
    ret = luat_onewire_read(ctx, (char*)data, check_crc ? 9 : 2);
    luat_onewire_close(ctx); // 后续不需要读取的
    if (ret != 9)
    {
        LLOGW("read失败2 mode %d id %d ret %d", ctx->mode, ctx->id, ret);
        goto exit;
    }

    if (check_crc)
    {
        uint8_t crc = 0;
        for (size_t i = 0; i < 8; i++){
            crc = crc8_maxim[crc ^ data[i]];
        }
        if (crc != data[8]) {
            LLOGD("crc %02X %02X", crc, data[8]);
            goto exit;
        }
    }

    uint8_t TL, TH;
    int32_t tem;
    int32_t val;

    TL = data[0];
    TH = data[1];

    // LLOGD("读出的数据");
    // LLOGDUMP(data, 9);

    if (TH > 7)
    {
        TH = ~TH;
        TL = ~TL;
        tem = TH;
        tem <<= 8;
        tem += TL;
        tem = (int32_t)(tem * 0.0625 * 10 + 0.5);
        val = -tem;
    }
    else
    {
        tem = TH;
        tem <<= 8;
        tem += TL;
        tem = (int32_t)(tem * 0.0625 * 10 + 0.5);
        val = tem;
    }
    luat_onewire_close(ctx); // 清理并关闭
    luat_os_exit_cri();
    *re = val;
    return 0;
exit:
    luat_onewire_close(ctx); // 清理并关闭
    luat_os_exit_cri();
    return -1;
}

