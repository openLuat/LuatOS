#ifndef LUAT_TINY_EPD_PORT_LUATOS_H
#define LUAT_TINY_EPD_PORT_LUATOS_H

/* luat_base.h brings in the active BSP configuration and feature macros. */
#include "luat_base.h"
#include "tiny_epd.h"

/* This port is compiled only by a LuatOS firmware with LUAT_USE_TINY_EPD. */
#if defined(LUAT_USE_TINY_EPD)

#include "luat_spi.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    /* Use spi_device when non-NULL; otherwise spi_id is used. */
    int spi_id;
    luat_spi_device_t *spi_device;
    int pin_dc;
    int pin_rst;
    int pin_busy;
    int busy_pull;
    uint32_t busy_poll_ms;
} tiny_epd_port_luatos_config_t;

typedef struct {
    tiny_epd_port_luatos_config_t config;
} tiny_epd_port_luatos_t;

/* SPI / spi.device must be set up before this function is called. */
int tiny_epd_port_luatos_init(tiny_epd_port_t *port,
                              tiny_epd_port_luatos_t *ctx,
                              const tiny_epd_port_luatos_config_t *config);

#ifdef __cplusplus
}
#endif

#endif

#endif
