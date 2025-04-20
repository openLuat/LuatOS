#ifndef LUAT_AIRLINK_FOTA_H
#define LUAT_AIRLINK_FOTA_H
#include "luat_base.h"
#include "luat_fs.h"

typedef struct luat_airlink_fota {
    uint32_t state;
    size_t total_size;
    char path[64];
    size_t wait_init;
    size_t wait_first_data;
    size_t wait_data;
    size_t wait_done;
    size_t wait_reboot;
    uint8_t pwr_gpio;
}luat_airlink_fota_t;

int luat_airlink_fota_init(luat_airlink_fota_t* ctx);
int luat_airlink_fota_stop(void);

extern luat_airlink_fota_t* g_airlink_fota;

#endif

