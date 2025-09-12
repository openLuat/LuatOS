#ifndef __LUAT_MISC_H__
#define __LUAT_MISC_H__
#include "stdint.h"
typedef void (*powerkey_cb)(uint32_t event);
uint8_t luat_misc_powerkey_get(void);
void luat_misc_powerkey_setup(uint8_t enable, uint16_t press_deboubce_time, uint16_t release_deboubce_time, powerkey_cb cb);
#endif
