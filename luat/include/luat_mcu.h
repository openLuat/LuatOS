#ifndef LUAT_MCU_H
#define LUAT_MCU_H
#include "luat_base.h"

enum
{
	LUAT_MCU_PERIPHERAL_UART,
	LUAT_MCU_PERIPHERAL_I2C,
	LUAT_MCU_PERIPHERAL_SPI,
};

int luat_mcu_set_clk(size_t mhz);
int luat_mcu_get_clk(void);

const char* luat_mcu_unique_id(size_t* t);

long luat_mcu_ticks(void);
uint32_t luat_mcu_hz(void);

uint64_t luat_mcu_tick64(void);
int luat_mcu_us_period(void);
uint64_t luat_mcu_tick64_ms(void);
void luat_mcu_set_clk_source(uint8_t source_main, uint8_t source_32k, uint32_t delay);

#endif

