

void lwip_init(void);

#include "luat_mcu.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "lwip"
#include "luat_log.h"

#include "stdint.h"

void luat_lwip_init(void) {
    lwip_init();
}

#if NO_SYS == 1
uint32_t lwip_port_rand(void) {
    uint32_t t = 0;
    luat_crypto_trng((char*)&t, sizeof(uint32_t));
    return t;
}

uint32_t sys_now(void) {
    uint32_t ticks = luat_mcu_ticks();
    return ticks;
}
#endif
