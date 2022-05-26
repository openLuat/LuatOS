#ifndef LUAT_FOTA_H
#define LUAT_FOTA_H

#include "luat_base.h"
#include "luat_spi.h"

int luat_fota_init(uint32_t start_address, uint32_t len, luat_spi_device_t* spi_device, const char *path, uint32_t pathlen);

int luat_fota_write(uint8_t *data, uint32_t len);

int luat_fota_done(void);

int luat_fota_end(uint8_t is_ok);

uint8_t luat_fota_wait_ready(void);

#endif
