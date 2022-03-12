#ifndef LUAT_MCU_H
#define LUAT_MCU_H
#include "luat_base.h"

int luat_mcu_set_clk(size_t mhz);
int luat_mcu_get_clk(void);

const char* luat_mcu_unique_id(size_t* t);

long luat_mcu_ticks(void);

uint32_t luat_mcu_hz(void);

#endif