#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "luat_irq.h"
#include "luat_gpio.h"
#include "luat_gpio_drv.h"
#ifdef LUAT_USE_WINDOWS
#include "luat_ch347_pc.h"
#endif

#define LUAT_LOG_TAG "gpio"
#include "luat_log.h"

luat_gpio_drv_opts_t* gpio_drvs[128];

luat_gpio_t gpio_confs[128];
uint8_t gpio_levels[128];

int luat_gpio_setup(luat_gpio_t *gpio){
    if (gpio->pin >= 128)
        return -1;
    memcpy(&gpio_confs[gpio->pin], gpio, sizeof(luat_gpio_t));

    #ifdef LUAT_USE_WINDOWS
    if(!g_ch3470_DevIsOpened)
        luat_load_ch347(0);
    if(g_ch3470_DevIsOpened) {
        luat_ch347_gpio_setup(gpio->pin, gpio->mode, gpio->pull, gpio->irq);
    }
    #endif

    if (gpio_drvs[gpio->pin]) {
        return gpio_drvs[gpio->pin]->setup(NULL, gpio);
    }
    return 0;
}

int luat_gpio_set(int pin, int level)
{
    if (pin < 0 || pin >= 128)
        return -1;
    gpio_levels[pin] = level == 0 ? 0 : 1;

    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened) {
        luat_ch347_gpio_set(pin, level);
    }
    #endif

    if (gpio_drvs[pin]) {
        return gpio_drvs[pin]->write(NULL, pin, level);
    }
    return 0;
}

//hyj
void luat_gpio_pulse(int pin, uint8_t *level, uint16_t len,uint16_t delay_ns)
{
    (void)pin;
    (void)level;
    (void)len;
    (void)delay_ns;
    return;
}

int luat_gpio_get(int pin)
{
    if (pin < 0 || pin >= 128)
        return -1;

    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened && (pin >=0 && pin <= 7)) {
        return luat_ch347_gpio_get(pin);
    }
    #endif

    if (gpio_drvs[pin]) {
        return gpio_drvs[pin]->read(NULL, pin);
    }
    // PC 模拟器: 直接返回 gpio_levels[pin]，不区分输入/输出模式
    return gpio_levels[pin];
}

void luat_gpio_close(int pin)
{
    if (pin < 0 || pin >= 128)
        return;

    memset(&gpio_confs[pin], 0, sizeof(luat_gpio_t));
    gpio_confs[pin].mode = LUAT_GPIO_INPUT;
    if (gpio_drvs[pin]) {
        gpio_drvs[pin]->close(NULL, pin);
    }

    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened) {
        luat_ch347_gpio_setup(pin, LUAT_GPIO_INPUT, 0, 0);
    }
    #endif

}

int luat_gpio_irq_enable(int pin, uint8_t enabled, uint8_t irq_type, void *arg)
{
    (void)pin;
    (void)enabled;
    (void)irq_type;
    (void)arg;
    // PC 模拟器暂不支持 GPIO 硬件中断，返回成功以满足调用方
    return 0;
}

void luat_gpio_set_default_cfg(luat_gpio_cfg_t* gpio) {
    if (gpio) {
        memset(gpio, 0, sizeof(luat_gpio_cfg_t));
    }
}

int luat_gpio_open(luat_gpio_cfg_t* gpio) {
    if (!gpio || gpio->pin < 0 || gpio->pin >= 128) return -1;
    // Minimal PC implementation: store mode, set initial level for output
    gpio_confs[gpio->pin].pin  = gpio->pin;
    gpio_confs[gpio->pin].mode = gpio->mode;
    gpio_confs[gpio->pin].pull = gpio->pull;
    if (gpio->mode == Luat_GPIO_OUTPUT) {
        gpio_levels[gpio->pin] = gpio->output_level ? 1 : 0;
    }
    return 0;
}

int luat_gpio_ctrl(int pin, LUAT_GPIO_CTRL_CMD_E cmd, int param) {
    (void)cmd;
    (void)param;
    if (pin < 0 || pin >= 128) return -1;
    return 0;
}
