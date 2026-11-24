#include "luat_base.h"
#if defined(LUAT_USE_IR_RX) && !defined(LUAT_IR_CUSTOM_CAPTURE)
#include "luat_ir_rx.h"
#include "luat_gpio.h"
#include "luat_mcu.h"

static int ir_gpio_irq(int pin, void *args) {
    (void)args;
    /* 在中断现场取时，将硬件计数换算为微秒，避免任务调度延迟影响脉宽判断。 */
    uint64_t tick = luat_mcu_tick64();
    luat_ir_rx_edge(pin, tick / (unsigned)luat_mcu_us_period());
    return 0;
}

int luat_ir_capture_start(int pin) {
    if (luat_mcu_us_period() <= 0) return -1;
    luat_gpio_cfg_t cfg = {0};
    cfg.pin = pin;
    cfg.mode = LUAT_GPIO_IRQ;
    cfg.pull = LUAT_GPIO_PULLUP;
    cfg.irq_type = LUAT_GPIO_FALLING_IRQ;
    cfg.irq_cb = ir_gpio_irq;
    return luat_gpio_open(&cfg);
}

void luat_ir_capture_stop(int pin) {
    luat_gpio_close(pin);
}
#endif
