#ifndef LUAT_TINY_EPD_PORT_EXAMPLE_H
#define LUAT_TINY_EPD_PORT_EXAMPLE_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Bare-metal / RTOS porting example.
 *
 * Fill these callbacks with the target BSP's SPI, GPIO, tick and heap APIs,
 * then call tiny_epd_port_example_init() and pass the resulting port to
 * tiny_epd_create().  The SPI bus itself must be configured by the caller.
 */
typedef struct {
    void *user;
    int (*spi_write)(void *user, const uint8_t *data, size_t len);
    int (*gpio_write)(void *user, int pin, uint8_t level);
    int (*gpio_read)(void *user, int pin);
    uint64_t (*tick_ms)(void *user);
    void (*delay_ms)(void *user, uint32_t ms);
    void *(*malloc)(void *user, size_t size);
    void (*free)(void *user, void *ptr);
} tiny_epd_port_example_hal_t;

typedef struct {
    tiny_epd_port_example_hal_t hal;
    int pin_dc;
    int pin_rst;
    int pin_busy;
    uint32_t busy_poll_ms;
} tiny_epd_port_example_config_t;

typedef struct {
    tiny_epd_port_example_config_t config;
} tiny_epd_port_example_t;

/* Returns TINY_EPD_OK, or TINY_EPD_ERR_PARAM for an incomplete HAL config. */
int tiny_epd_port_example_init(tiny_epd_port_t *port,
                               tiny_epd_port_example_t *ctx,
                               const tiny_epd_port_example_config_t *config);

#ifdef __cplusplus
}
#endif

#endif
