/*
 * gpio_hostabi_demo — call the host GPIO v2 CSRs.
 *
 * Configures pin 5 as output (mode=1, pull=0, irq_mode=0), drives it
 * high (level=1), reads it back, and stashes the four return values
 * into the exchange buffer for the Lua host to inspect.
 */
#include "luat_ndk_helper.h"

static int main(void) {
    volatile uint32_t *ex = ndk_exchange_u32(0);

    uint32_t pin      = 5u;
    uint32_t mode     = LUAT_NDK_GPIO_MODE_OUTPUT;   /* 1 */
    uint32_t pull     = LUAT_NDK_GPIO_PULL_DEFAULT;  /* 0 */
    uint32_t irq_mode = LUAT_NDK_GPIO_IRQ_RISING;    /* 0 */
    uint32_t level    = 1u;

    ex[0] = ndk_gpio_config (pin, mode, pull, irq_mode);
    ex[1] = ndk_gpio_write_v2(pin, level);
    ex[2] = ndk_gpio_read_v2 (pin);
    ex[3] = pin;
    ex[4] = level;

    ndk_exit_ok();
    return 0;
}

NDK_GUEST_START(main)
